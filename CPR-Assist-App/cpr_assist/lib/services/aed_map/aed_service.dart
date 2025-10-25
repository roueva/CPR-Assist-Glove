import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/app_constants.dart';
import '../../widgets/aed_markers.dart';
import '../../models/aed_models.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../network_service.dart';
import 'route_service.dart';

class AEDService {
  final NetworkService _networkService;

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

  Future<List<AED>> fetchAEDs({bool forceRefresh = false}) async {
    final isConnected = NetworkService.lastKnownConnectivityState;

    // ALWAYS try cache first (unless forcing refresh AND connected)
    if (!(forceRefresh && isConnected)) {
      final cached = await _tryGetFromCache();
      if (cached != null) {
        print("📦 Using cached AEDs (${cached.length} AEDs)");
        return cached;
      }
    }

    // Try network if connected
    if (isConnected) {
      final network = await _tryGetFromNetwork();
      if (network != null) {
        print("🌐 Fetched fresh AEDs from network (${network.length} AEDs)");
        return network;
      }
    }

    // Fallback to ANY cached data, even if expired
    final staleCache = await CacheService.getAEDs();
    if (staleCache != null) {
      print("⚠️ Using stale cached AEDs as fallback");
      return convertToAEDList(staleCache);
    }

    throw Exception("No AED data available - please connect to internet");
  }

  Future<List<AED>?> _tryGetFromCache() async {
    final cachedAEDs = await CacheService.getAEDs();
    if (cachedAEDs == null) return null;

    // Always return cache if available (we'll rely on network updates when online)
    return convertToAEDList(cachedAEDs);
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
      return convertToAEDList(aeds);
    } catch (e) {
      print("❌ Network fetch failed: $e");
      return null;
    }
  }


  List<AED> convertToAEDList(List<dynamic> rawData) {
    return rawData.map((aed) {
      final double? lat = double.tryParse(aed["latitude"].toString());
      final double? lng = double.tryParse(aed["longitude"].toString());

      if (lat == null || lng == null) return null;

      final location = LatLng(lat, lng);
      final rawAddress = aed["address"]?.toString() ?? "Unknown address";
      final int aedId = int.tryParse(aed["id"].toString()) ?? 0;

      return AED(
        id: aedId,
        name: rawAddress,
        address: rawAddress,
        location: location,
      );
    }).whereType<AED>().toList();
  }

  Set<Marker> createMarkers(List<AED> aeds, Function(LatLng) onPreviewPressed){
    return aeds.map((aed) => Marker(
      markerId: MarkerId(aed.id.toString()),
      position: aed.location,
      icon: CustomIcons.aedUpdated,
      infoWindow: InfoWindow(
        title: aed.address,
        snippet: null,
        onTap: () => onPreviewPressed(aed.location),
      ),
    )).toSet();
  }

  List<AED> sortAEDsByDistance(List<AED> aeds, LatLng? referenceLocation, String transportMode) {
    if (referenceLocation == null || aeds.isEmpty) return aeds;

    final sorted = List<AED>.from(aeds);

    // Calculate and cache distances
    for (final aed in sorted) {
      final straightDist = LocationService.distanceBetween(referenceLocation, aed.location);
      final multiplier = getTransportModeMultiplier(transportMode);
      final estimatedDist = straightDist * multiplier;

      // Cache the estimated distance for this AED
      CacheService.setDistance('aed_${aed.id}', estimatedDist);
    }

    // Sort by adjusted distance
    sorted.sort((a, b) {
      final distA = CacheService.getDistance('aed_${a.id}') ??
          LocationService.distanceBetween(referenceLocation, a.location);
      final distB = CacheService.getDistance('aed_${b.id}') ??
          LocationService.distanceBetween(referenceLocation, b.location);
      return distA.compareTo(distB);
    });

    return sorted;
  }

  Future<void> preloadRoutesForClosestAEDs(
      List<AED> aeds,
      LatLng userLocation,
      String transportMode,
      String? apiKey,
      Function(AED, RouteResult)? onRouteLoaded,
      ) async {
    if (aeds.isEmpty || apiKey == null || apiKey.isEmpty) return;

    // Get top 10 closest AEDs for better coverage
    final closestAEDs = aeds.take(10).toList();
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

          // Cache the distance for display
          if (routeResult.actualDistance != null) {
            CacheService.setDistance('aed_${aed.id}', routeResult.actualDistance!);
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

    // Process closest 15 AEDs for better accuracy
    final closestAEDs = aeds.take(15).toList();
    final aedsWithRoadDistance = <AED, double>{};
    bool anyUpdated = false;

    print("🔄 Improving distance accuracy for ${closestAEDs.length} AEDs");

    for (final aed in closestAEDs) {
      try {
        // Check if we have a cached route first
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, transportMode);
        if (cachedRoute != null && cachedRoute.actualDistance != null) {
          aedsWithRoadDistance[aed] = cachedRoute.actualDistance!;
          CacheService.setDistance('aed_${aed.id}', cachedRoute.actualDistance!);
          continue;
        }

        // Check distance cache
        final cacheKey = CacheService.generateLocationKey(userLocation, aed.location, transportMode);
        final cachedDistance = CacheService.getDistance(cacheKey);

        if (cachedDistance != null) {
          aedsWithRoadDistance[aed] = cachedDistance;
          CacheService.setDistance('aed_${aed.id}', cachedDistance);
        } else {
          // Fetch route for accurate distance and cache everything
          final routeService = RouteService(apiKey);
          final routeResult = await routeService.fetchRoute(userLocation, aed.location, transportMode);

          if (routeResult?.actualDistance != null) {
            // Cache the complete route (including polyline)
            CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult!);

            // Cache the distance
            CacheService.setDistance(cacheKey, routeResult.actualDistance!);
            CacheService.setDistance('aed_${aed.id}', routeResult.actualDistance!);

            aedsWithRoadDistance[aed] = routeResult.actualDistance!;
            anyUpdated = true;

            print("✅ Cached route & distance for AED ${aed.id}: ${routeResult.distanceText}");

            // Small delay to avoid API rate limiting
            await Future.delayed(AppConstants.apiCallDelay);
          } else {
            // Fallback to adjusted straight-line distance
            final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
            final adjustedDistance = straightDistance * getTransportModeMultiplier(transportMode);
            aedsWithRoadDistance[aed] = adjustedDistance;
            CacheService.setDistance('aed_${aed.id}', adjustedDistance);
          }
        }
      } catch (e) {
        print("❌ Error improving distance for AED ${aed.id}: $e");
        // Fallback to adjusted straight-line distance
        final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
        final adjustedDistance = straightDistance * getTransportModeMultiplier(transportMode);
        aedsWithRoadDistance[aed] = adjustedDistance;
        CacheService.setDistance('aed_${aed.id}', adjustedDistance);
      }
    }

    // Save distance cache if any updates occurred
    if (anyUpdated) {
      await CacheService.saveDistanceCache();
      print("💾 Saved distance cache after background improvements");

      // Resort by actual road distance
      final roadSorted = aedsWithRoadDistance.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final remaining = aeds.skip(15).toList();
      final newOrder = [...roadSorted.map((e) => e.key), ...remaining];

      onUpdated(newOrder);
      print("🔄 Resorted AEDs by actual road distance");
    }
  }


  bool haveAEDsChanged(List<AED> oldList, List<AED> newList) {
    if (oldList.length != newList.length) return true;
    for (int i = 0; i < oldList.length; i++) {
      if (oldList[i].id != newList[i].id ||
          oldList[i].location.latitude != newList[i].location.latitude ||
          oldList[i].location.longitude != newList[i].location.longitude ||
          oldList[i].address != newList[i].address) {
        return true;
      }
    }
    return false;
  }
}