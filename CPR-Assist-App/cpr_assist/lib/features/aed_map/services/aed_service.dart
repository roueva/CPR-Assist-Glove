import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/utils/app_constants.dart';
import '../widgets/availability_parser.dart';
import '../../../models/aed_models.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../../../services/network/network_service.dart';
import 'route_service.dart';

class AEDService {
  final NetworkService _networkService;
  final Map<String, double> _pendingDistanceUpdates = {};
  Timer? _flushTimer;

  static String _getDistanceCacheKey(int aedId, String transportMode) {
    return 'aed_${aedId}_$transportMode';
  }

  AEDService(this._networkService);

  static double getTransportModeMultiplier(String transportMode) {
    switch (transportMode) {
      case 'driving':
        return AppConstants.drivingMultiplier;
      case 'bicycling':
        return AppConstants.bicyclingMultiplier;
      case 'walking':
      default:
        return AppConstants.walkingMultiplier;
    }
  }

  static double calculateEstimatedDistance(
      LatLng from, LatLng to, String transportMode) {
    final straightDistance = LocationService.distanceBetween(from, to);
    final multiplier = getTransportModeMultiplier(transportMode);
    return straightDistance * multiplier;
  }

  static void calculateEstimatedDistancesForAll(
      List<AED> aeds, LatLng userLocation, String transportMode) {
    if (aeds.isEmpty) return;
    final multiplier = getTransportModeMultiplier(transportMode);

    for (final aed in aeds) {
      final straightDist =
      LocationService.distanceBetween(userLocation, aed.location);
      CacheService.setDistance(
        'aed_${aed.id}_$transportMode',
        straightDist * multiplier,
      );
    }
  }

  Future<List<AED>> fetchAEDs({bool forceRefresh = false}) async {
    final isConnected = NetworkService.lastKnownConnectivityState;

    if (!(forceRefresh && isConnected)) {
      final isCacheExpired = await CacheService.isAEDCacheExpired();

      if (!isCacheExpired) {
        final cached = await _tryGetFromCache();
        if (cached != null) {
          final cacheAge = await CacheService.getCacheAge();
          debugPrint(
              '📦 Using cached AEDs (${cached.length} AEDs) - age: ${cacheAge.inHours}h');
          return cached;
        }
      } else {
        debugPrint(
            '⏰ Cache expired (>${CacheService.getCacheTTL().inDays} days old) - fetching fresh data');
      }
    }

    if (isConnected) {
      final network = await _tryGetFromNetwork();
      if (network != null) {
        debugPrint('🌐 Fetched fresh AEDs from network (${network.length} AEDs)');
        return network;
      }
    }

    final staleCache = await CacheService.getAEDs();
    if (staleCache != null) {
      debugPrint('⚠️ Using stale cached AEDs as fallback');
      return staleCache
          .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
          .whereType<AED>()
          .toList();
    }

    throw Exception('No AED data available - please connect to internet');
  }

  Future<List<AED>?> _tryGetFromCache() async {
    final cachedAEDs = await CacheService.getAEDs();
    if (cachedAEDs == null) return null;

    return cachedAEDs
        .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
        .whereType<AED>()
        .toList();
  }

  Future<List<AED>?> _tryGetFromNetwork() async {
    try {
      final isConnected = await NetworkService.isConnected();
      if (!isConnected) {
        debugPrint('🔴 Network unavailable - skipping network fetch');
        return null;
      }

      final aeds = await _networkService.fetchAEDLocations();
      await CacheService.saveAEDs(aeds);

      return aeds
          .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
          .whereType<AED>()
          .toList();
    } catch (e) {
      debugPrint('❌ Network fetch failed: $e');
      return null;
    }
  }

  List<AED> sortAEDsByDistance(
      List<AED> aeds, LatLng? referenceLocation, String transportMode) {
    if (referenceLocation == null || aeds.isEmpty) return aeds;

    final Map<int, double> distances = {};
    for (final aed in aeds) {
      final cacheKey = _getDistanceCacheKey(aed.id, transportMode);
      final cachedDistance = CacheService.getDistance(cacheKey);

      if (cachedDistance != null) {
        distances[aed.id] = cachedDistance;
      } else {
        final straightDist =
        LocationService.distanceBetween(referenceLocation, aed.location);
        final estimated = straightDist * getTransportModeMultiplier(transportMode);
        distances[aed.id] = estimated;
        _queueDistanceUpdate(cacheKey, estimated);
      }
    }

    final allSorted = List<AED>.from(aeds)
      ..sort((a, b) {
        final distA = distances[a.id] ?? double.infinity;
        final distB = distances[b.id] ?? double.infinity;
        return distA.compareTo(distB);
      });

    final top3Open = allSorted
        .where((aed) {
      final s = AvailabilityParser.parseAvailability(aed.availability);
      return s.isOpen && !s.isUncertain;
    })
        .take(3)
        .toList();

    final top3OpenIds = top3Open.map((e) => e.id).toSet();
    final remaining =
    allSorted.where((aed) => !top3OpenIds.contains(aed.id)).toList();

    final result = [...top3Open, ...remaining];

    return result.map((aed) {
      final d = distances[aed.id];
      return d != null ? aed.copyWithDistance(d) : aed;
    }).toList();
  }

  /// Improves distance accuracy for the closest AEDs using actual road routes.
  /// Route preloading (for the AEDMapDisplay) is handled by [RoutePreloader]
  /// in route_service.dart via AEDRoutingCoordinator.
  Future<void> improveDistanceAccuracyInBackground(
      List<AED> aeds,
      LatLng userLocation,
      String transportMode,
      String? apiKey,
      Function(List<AED>) onUpdated,
      ) async {
    if (aeds.isEmpty || apiKey == null || apiKey.isEmpty) return;

    final closestAEDs =
    aeds.take(AppConstants.maxDistanceCalculations).toList();
    final aedsWithRoadDistance = <AED, double>{};
    bool anyUpdated = false;

    debugPrint(
        '🔄 Improving distance accuracy for ${closestAEDs.length} AEDs (mode: $transportMode)');

    for (final aed in closestAEDs) {
      try {
        final cacheKey = _getDistanceCacheKey(aed.id, transportMode);

        final cachedRoute =
        CacheService.getCachedRoute(userLocation, aed.location, transportMode);
        if (cachedRoute != null && cachedRoute.actualDistance != null) {
          aedsWithRoadDistance[aed] = cachedRoute.actualDistance!;
          CacheService.setDistance(cacheKey, cachedRoute.actualDistance!);
          continue;
        }

        final cachedDistance = CacheService.getDistance(cacheKey);

        if (cachedDistance != null) {
          aedsWithRoadDistance[aed] = cachedDistance;
          anyUpdated = true;
        } else {
          final routeService = RouteService(apiKey);
          final routeResult = await routeService.fetchRoute(
              userLocation, aed.location, transportMode);

          if (routeResult?.actualDistance != null) {
            CacheService.setCachedRoute(
                userLocation, aed.location, transportMode, routeResult!);
            CacheService.setDistance(cacheKey, routeResult.actualDistance!);
            aedsWithRoadDistance[aed] = routeResult.actualDistance!;
            anyUpdated = true;
            debugPrint(
                '✅ Cached route & distance for AED ${aed.id}: ${routeResult.distanceText}');
            await Future.delayed(AppConstants.apiCallDelay);
          } else {
            final straightDistance =
            LocationService.distanceBetween(userLocation, aed.location);
            final adjustedDistance =
                straightDistance * getTransportModeMultiplier(transportMode);
            aedsWithRoadDistance[aed] = adjustedDistance;
            CacheService.setDistance(cacheKey, adjustedDistance);
          }
        }
      } catch (e) {
        debugPrint('❌ Error improving distance for AED ${aed.id}: $e');
        final cacheKey = _getDistanceCacheKey(aed.id, transportMode);
        final straightDistance =
        LocationService.distanceBetween(userLocation, aed.location);
        final adjustedDistance =
            straightDistance * getTransportModeMultiplier(transportMode);
        aedsWithRoadDistance[aed] = adjustedDistance;
        CacheService.setDistance(cacheKey, adjustedDistance);
      }
    }

    if (anyUpdated) {
      await CacheService.saveDistanceCache();

      final roadSorted = aedsWithRoadDistance.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final roadSortedIds = roadSorted.map((e) => e.key.id).toSet();
      final remaining = aeds
          .where((a) => !roadSortedIds.contains(a.id))
          .toList()
        ..sort((a, b) {
          final distA = CacheService.getDistance(
              _getDistanceCacheKey(a.id, transportMode)) ??
              (LocationService.distanceBetween(userLocation, a.location) *
                  getTransportModeMultiplier(transportMode));
          final distB = CacheService.getDistance(
              _getDistanceCacheKey(b.id, transportMode)) ??
              (LocationService.distanceBetween(userLocation, b.location) *
                  getTransportModeMultiplier(transportMode));
          return distA.compareTo(distB);
        });

      final newOrder = [
        ...roadSorted.map((e) => e.key.copyWithDistance(e.value)),
        ...remaining,
      ];

      onUpdated(newOrder);
      debugPrint(
          '🔄 Resorted AEDs by actual road distance (${roadSorted.length} accurate + ${remaining.length} estimated)');
    }
  }

  bool haveAEDsChanged(List<AED> oldList, List<AED> newList) {
    if (oldList.length != newList.length) return true;

    final oldIds = oldList.map((a) => a.id).toSet();
    final newIds = newList.map((a) => a.id).toSet();
    if (!oldIds.containsAll(newIds)) return true;

    final newById = {for (final a in newList) a.id: a};
    for (final old in oldList.take(20)) {
      final fresh = newById[old.id];
      if (fresh == null) return true;
      if (fresh.location.latitude != old.location.latitude ||
          fresh.location.longitude != old.location.longitude ||
          fresh.address != old.address) {
        return true;
      }
    }
    return false;
  }

  void _queueDistanceUpdate(String key, double distance) {
    _pendingDistanceUpdates[key] = distance;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), _flushDistanceUpdates);
  }

  Future<void> _flushDistanceUpdates() async {
    if (_pendingDistanceUpdates.isEmpty) return;

    for (final entry in _pendingDistanceUpdates.entries) {
      CacheService.setDistance(entry.key, entry.value);
    }
    _pendingDistanceUpdates.clear();
  }
}
