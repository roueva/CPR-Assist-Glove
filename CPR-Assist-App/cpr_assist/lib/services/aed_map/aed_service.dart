import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/app_constants.dart';
import '../../models/aed_models.dart';
import '../../utils/availability_parser.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../network_service.dart';
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

  static double calculateEstimatedDistance(LatLng from, LatLng to, String transportMode) {
    final straightDistance = LocationService.distanceBetween(from, to);
    final multiplier = getTransportModeMultiplier(transportMode);
    return straightDistance * multiplier;
  }

  static void calculateEstimatedDistancesForAll(
      List<AED> aeds, LatLng userLocation, String transportMode) {
    if (aeds.isEmpty) return;
    final multiplier = getTransportModeMultiplier(transportMode);

    for (final aed in aeds) {
      final straightDist = LocationService.distanceBetween(userLocation, aed.location);
      CacheService.setDistance(
        'aed_${aed.id}_$transportMode',
        straightDist * multiplier,
      );
    }
    // Don't call saveDistanceCache() here — let the 500ms debounce handle it
    print("✅ Batch calculated ${aeds.length} distances");
  }


  Future<List<AED>> fetchAEDs({bool forceRefresh = false}) async {
    final isConnected = NetworkService.lastKnownConnectivityState;

    // STEP 1: Try cache first (unless forcing refresh AND connected)
    if (!(forceRefresh && isConnected)) {
      // Check if cache is expired
      final isCacheExpired = await CacheService.isAEDCacheExpired();

      if (!isCacheExpired) {
        final cached = await _tryGetFromCache();
        if (cached != null) {
          final cacheAge = await CacheService.getCacheAge();
          print("📦 Using cached AEDs (${cached.length} AEDs) - age: ${cacheAge.inHours}h");
          return cached;
        }
      } else {
        print("⏰ Cache expired (>${CacheService.getCacheTTL().inDays} days old) - fetching fresh data");
      }
    }

    // STEP 2: Try network if connected
    if (isConnected) {
      final network = await _tryGetFromNetwork();
      if (network != null) {
        print("🌐 Fetched fresh AEDs from network (${network.length} AEDs)");
        return network;
      }
    }

    // STEP 3: Fallback to stale cache
    final staleCache = await CacheService.getAEDs();
    if (staleCache != null) {
      print("⚠️ Using stale cached AEDs as fallback");
      return staleCache
          .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
          .whereType<AED>()
          .toList();
    }

    throw Exception("No AED data available - please connect to internet");
  }

  Future<List<AED>?> _tryGetFromCache() async {
    final cachedAEDs = await CacheService.getAEDs();
    if (cachedAEDs == null) return null;

    // Always return cache if available (we'll rely on network updates when online)
    // Use the correct factory from aed_models.dart
    return cachedAEDs
        .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
        .whereType<AED>()
        .toList();
  }

  Future<List<AED>?> _tryGetFromNetwork() async {
    try {
      // Double-check connectivity before network call
      final isConnected = await NetworkService.isConnected();
      if (!isConnected) {
        print("🔴 Network unavailable - skipping network fetch");
        return null;
      }

      final aeds = await _networkService.fetchAEDLocations();
      await CacheService.saveAEDs(aeds);

      // Use the correct factory from aed_models.dart
      return aeds
          .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
          .whereType<AED>()
          .toList();
    } catch (e) {
      print("❌ Network fetch failed: $e");
      return null;
    }
  }


  List<AED> sortAEDsByDistance(List<AED> aeds, LatLng? referenceLocation, String transportMode) {
    if (referenceLocation == null || aeds.isEmpty) return aeds;

    // Step 1: Build distance map for all AEDs
    final Map<int, double> distances = {};
    for (final aed in aeds) {
      final cacheKey = _getDistanceCacheKey(aed.id, transportMode);
      final cachedDistance = CacheService.getDistance(cacheKey);

      if (cachedDistance != null) {
        distances[aed.id] = cachedDistance;
      } else {
        final straightDist = LocationService.distanceBetween(referenceLocation, aed.location);
        final estimated = straightDist * getTransportModeMultiplier(transportMode);
        distances[aed.id] = estimated;
        _queueDistanceUpdate(cacheKey, estimated);
      }
    }

    // Step 2: Sort everything by distance (pure distance order)
    final allSorted = List<AED>.from(aeds)
      ..sort((a, b) {
        final distA = distances[a.id] ?? double.infinity;
        final distB = distances[b.id] ?? double.infinity;
        return distA.compareTo(distB);
      });

    // Step 3: Find the top 3 closest AEDs that are confirmed open (not uncertain)
    final top3Open = allSorted
        .where((aed) {
      final s = AvailabilityParser.parseAvailability(aed.availability);
      return s.isOpen && !s.isUncertain;
    })
        .take(3)
        .toList();

    // Step 4: Build final list — top 3 open first, then all remaining in distance order
    final top3OpenIds = top3Open.map((e) => e.id).toSet();
    final remaining = allSorted.where((aed) => !top3OpenIds.contains(aed.id)).toList();

    final result = [...top3Open, ...remaining];

    // Step 5: Return with distanceInMeters updated so formattedDistance is correct
    print("📏 Sorted ${result.length} AEDs (${top3Open.length} open first, mode: $transportMode)");
    print("🔍 SORT DEBUG - referenceLocation: $referenceLocation");
    print("🔍 SORT DEBUG - top 5 results:");
    for (int i = 0; i < result.take(5).length; i++) {
      final aed = result.elementAt(i);
      final d = distances[aed.id];
      final straightDist = LocationService.distanceBetween(referenceLocation, aed.location);
      print("  [$i] AED ${aed.id} | cached dist: ${d?.toStringAsFixed(0)}m | straight: ${straightDist.toStringAsFixed(0)}m | loc: ${aed.location}");
    }
    print("🔍 SORT DEBUG - top3Open count: ${top3Open.length}");
    for (final aed in top3Open) {
      final avail = AvailabilityParser.parseAvailability(aed.availability);
      print("  OPEN: AED ${aed.id} | isOpen=${avail.isOpen} | isUncertain=${avail.isUncertain} | availability: ${aed.availability}");
    }
    return result.map((aed) {
      final d = distances[aed.id];
      return d != null ? aed.copyWithDistance(d) : aed;
    }).toList();
  }


  Future<void> preloadRoutesForClosestAEDs({
    required List<AED> aeds,
    required LatLng userLocation,
    required String transportMode,
    String? apiKey,
    Function(AED, RouteResult)? onRouteLoaded,
  }) async {
    if (aeds.isEmpty || apiKey == null || apiKey.isEmpty) return;

    // Get top 10 closest AEDs for better coverage
    final closestAEDs = aeds.take(AppConstants.maxPreloadedRoutes).toList();
    print("🚀 Preloading routes for ${closestAEDs.length} closest AEDs");

    for (final aed in closestAEDs) {
      try {
        // Check if route is already cached
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, transportMode);
        if (cachedRoute != null) {
          print("📦 Using cached route for AED ${aed.id}");
          onRouteLoaded?.call(aed, cachedRoute);
          continue;
        }

        // Fetch new route from API
        final routeService = RouteService(apiKey);
        final routeResult = await routeService.fetchRoute(userLocation, aed.location, transportMode);

        if (routeResult != null) {
          // Cache the complete route (including polyline)
          CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult);

          // ✅ Cache with transport mode to prevent overwriting
          if (routeResult.actualDistance != null) {
            CacheService.setDistance('aed_${aed.id}_$transportMode', routeResult.actualDistance!);
            print("✅ Cached REAL distance for AED ${aed.id} ($transportMode): ${LocationService.formatDistance(routeResult.actualDistance!)}");
          }

          print("✅ Cached route for AED ${aed.id}: ${routeResult.duration}, ${routeResult.distanceText}");
          onRouteLoaded?.call(aed, routeResult);

          // Add delay to avoid API rate limiting
          await Future.delayed(AppConstants.routePreloadDelay);
        } else {
          print("⚠️ Failed to get route for AED ${aed.id}");
        }
      } catch (e) {
        print("❌ Error preloading route for AED ${aed.id}: $e");
      }
    }

    // Save all distance cache updates to persistent storage
    await CacheService.saveDistanceCache();
    print("💾 Saved distance cache after route preloading");
  }

// Replace lines 142-185 with this corrected version:
  Future<void> improveDistanceAccuracyInBackground(
      List<AED> aeds,
      LatLng userLocation,
      String transportMode,
      String? apiKey,
      Function(List<AED>) onUpdated
      ) async {
    if (aeds.isEmpty || apiKey == null || apiKey.isEmpty) return;

    final closestAEDs = aeds.take(AppConstants.maxDistanceCalculations).toList();
    final aedsWithRoadDistance = <AED, double>{};
    bool anyUpdated = false;

    print("🔄 Improving distance accuracy for ${closestAEDs.length} AEDs (mode: $transportMode)");

    for (final aed in closestAEDs) {
      try {
        // ✅ ALWAYS use consistent cache key
        final cacheKey = _getDistanceCacheKey(aed.id, transportMode);

        // Check if we have a cached route first
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, transportMode);
        if (cachedRoute != null && cachedRoute.actualDistance != null) {
          aedsWithRoadDistance[aed] = cachedRoute.actualDistance!;
          CacheService.setDistance(cacheKey, cachedRoute.actualDistance!);
          continue;
        }

        // Check distance cache
        final cachedDistance = CacheService.getDistance(cacheKey);

        if (cachedDistance != null) {
          aedsWithRoadDistance[aed] = cachedDistance;
          anyUpdated = true;  // cached distances are still accurate — trigger re-sort
        }else {
          // Fetch route for accurate distance
          final routeService = RouteService(apiKey);
          final routeResult = await routeService.fetchRoute(userLocation, aed.location, transportMode);

          if (routeResult?.actualDistance != null) {
            // Cache the complete route
            CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult!);

            // ✅ Cache with consistent key
            CacheService.setDistance(cacheKey, routeResult.actualDistance!);

            aedsWithRoadDistance[aed] = routeResult.actualDistance!;
            anyUpdated = true;

            print("✅ Cached route & distance for AED ${aed.id}: ${routeResult.distanceText}");
            await Future.delayed(AppConstants.apiCallDelay);
          } else {
            // ✅ Fallback with transport mode multiplier
            final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
            final adjustedDistance = straightDistance * getTransportModeMultiplier(transportMode);

            aedsWithRoadDistance[aed] = adjustedDistance;
            CacheService.setDistance(cacheKey, adjustedDistance);
          }
        }
      } catch (e) {
        print("❌ Error improving distance for AED ${aed.id}: $e");

        // ✅ Fallback with consistent cache key
        final cacheKey = _getDistanceCacheKey(aed.id, transportMode);
        final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
        final adjustedDistance = straightDistance * getTransportModeMultiplier(transportMode);

        aedsWithRoadDistance[aed] = adjustedDistance;
        CacheService.setDistance(cacheKey, adjustedDistance);
      }
    }

    // Save and resort...
    if (anyUpdated) {
      await CacheService.saveDistanceCache();
      print("💾 Saved distance cache after background improvements");

      // Sort the top-15 by road distance only (pure distance, no availability pinning here)
      // The availability pinning (top 3 open first) will be applied by sortAEDsByDistance
      // when onUpdated triggers a full re-sort in the widget.
      final roadSorted = aedsWithRoadDistance.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      // Sort the remaining AEDs (beyond top 15) by whatever distance we have cached
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

      // Combine: top-15 road-accurate first, then the rest by estimated distance
      final newOrder = [
        ...roadSorted.map((e) => e.key.copyWithDistance(e.value)),
        ...remaining,
      ];

      onUpdated(newOrder);
      print("🔄 Resorted AEDs by actual road distance (${roadSorted.length} accurate + ${remaining.length} estimated)");
    }
  }

  bool haveAEDsChanged(List<AED> oldList, List<AED> newList) {
    if (oldList.length != newList.length) return true;

    // Compare as sets of IDs — order doesn't matter here
    final oldIds = oldList.map((a) => a.id).toSet();
    final newIds = newList.map((a) => a.id).toSet();
    if (!oldIds.containsAll(newIds)) return true;

    // Spot-check first 20 for data changes (addresses, locations)
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
    _flushTimer = Timer(const Duration(seconds: 3), () {
      _flushDistanceUpdates();
    });
  }

  Future<void> _flushDistanceUpdates() async {
    if (_pendingDistanceUpdates.isEmpty) return;

    print("💾 Flushing ${_pendingDistanceUpdates.length} distance updates...");

    for (final entry in _pendingDistanceUpdates.entries) {
      CacheService.setDistance(entry.key, entry.value);
    }

    // setDistance already schedules a debounced save internally — no need to call
    // saveDistanceCache() here as well
    _pendingDistanceUpdates.clear();
    print("✅ Distance cache flushed");
  }
}