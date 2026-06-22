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

  static String _getDistanceCacheKey(int aedId, String transportMode) {
    return 'aed_${aedId}_$transportMode';
  }

  AEDService(this._networkService);

  static double getTransportModeMultiplier(String transportMode) {
    switch (transportMode) {
      case 'driving':
        return AppConstants.drivingMultiplier;
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

      if (cachedDistance != null && CacheService.isRoadDistance(cacheKey)) {
        // Only reuse cached distances that came from real road API calls.
        distances[aed.id] = cachedDistance;
      } else {
        // Always recalculate straight-line estimates from current position.
        final straightDist =
        LocationService.distanceBetween(referenceLocation, aed.location);
        distances[aed.id] = straightDist * getTransportModeMultiplier(transportMode);
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

    final closestAEDs = aeds.take(AppConstants.maxDistanceCalculations).toList();
    debugPrint('🔄 Improving distance accuracy for ${closestAEDs.length} AEDs in parallel (mode: $transportMode)');

    // Fetch all routes in parallel.
    await Future.wait(closestAEDs.map((aed) async {
      try {
        final cacheKey = _getDistanceCacheKey(aed.id, transportMode);

        // 1. Check in-memory route cache first.
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, transportMode);
        if (cachedRoute != null && cachedRoute.actualDistance != null) {
          CacheService.setDistance(cacheKey, cachedRoute.actualDistance!, isRoad: true);
          debugPrint('✅ Road distance from route cache for AED ${aed.id}');
          return;
        }

        // 2. Check distance-only cache (road-flagged).
        if (CacheService.isRoadDistance(cacheKey) && CacheService.getDistance(cacheKey) != null) {
          debugPrint('✅ Road distance from distance cache for AED ${aed.id}');
          return;
        }

        // 3. Fetch from Directions API.
        final routeService = RouteService(apiKey);
        final routeResult = await routeService.fetchRoute(userLocation, aed.location, transportMode);

        if (routeResult?.actualDistance != null) {
          CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult!);
          CacheService.setDistance(cacheKey, routeResult.actualDistance!, isRoad: true);
          debugPrint('✅ Fetched & cached road distance for AED ${aed.id}: ${routeResult.distanceText}');
        } else {
          // API failed — fall back to straight-line estimate.
          final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
          final adjustedDistance = straightDistance * getTransportModeMultiplier(transportMode);
          CacheService.setDistance(cacheKey, adjustedDistance);
          debugPrint('⚠️ API failed for AED ${aed.id}, using straight-line estimate');
        }
      } catch (e) {
        debugPrint('❌ Error improving distance for AED ${aed.id}: $e');
        final cacheKey = _getDistanceCacheKey(aed.id, transportMode);
        final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
        CacheService.setDistance(cacheKey, straightDistance * getTransportModeMultiplier(transportMode));
      }
    }));

    // All distances are now in cache. Re-sort the full list using sortAEDsByDistance
    // so the open-AED promotion is applied correctly on top of road distances.
    await CacheService.saveDistanceCache();
    final resorted = sortAEDsByDistance(aeds, userLocation, transportMode);
    onUpdated(resorted);
    debugPrint('🔄 Final re-sort complete after road distance fetch');
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
}
