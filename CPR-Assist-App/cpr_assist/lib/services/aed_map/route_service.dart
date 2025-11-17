import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/aed_models.dart';
import 'aed_service.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../network_service.dart';

class RouteResult {
  final Polyline polyline;
  final String duration;
  final List<LatLng> points;
  final bool isOffline;
  final double? actualDistance;
  final String? distanceText;

  RouteResult({
    required this.polyline,
    required this.duration,
    required this.points,
    this.isOffline = false,
    this.actualDistance,
    this.distanceText,
  });
}

class RouteService {
  final String apiKey;
  RouteService(this.apiKey);

  Future<RouteResult?> fetchRoute(LatLng origin, LatLng destination, String mode) async {
    if (apiKey.isEmpty) {
      print("❌ Missing API Key.");
      return null;
    }

    final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json?"
            "origin=${origin.latitude},${origin.longitude}"
            "&destination=${destination.latitude},${destination.longitude}"
            "&mode=$mode"
            "&key=$apiKey"
    );

    try {
      final response = await NetworkService.getExternal(url.toString());

      if (response != null && response['status'] == 'OK') {
        List<LatLng> routePoints = PolylineUtils.decode(response["routes"][0]["overview_polyline"]["points"]);
        String durationText = response["routes"][0]["legs"][0]["duration"]["text"];

        // Get actual road distance from API
        int distanceMeters = response["routes"][0]["legs"][0]["distance"]["value"];
        String distanceText = response["routes"][0]["legs"][0]["distance"]["text"];

        return RouteResult(
          polyline: Polyline(
            polylineId: PolylineId(mode),
            points: routePoints,
            color: mode == "walking" ? Colors.green : Colors.blue,
            patterns: mode == "walking"
                ? [PatternItem.dash(15), PatternItem.gap(8)]  // Shorter dashes, shorter gaps
                : [],
            width: 4,  // Slightly thinner for walking
          ),
          duration: durationText,
          points: routePoints,
          actualDistance: distanceMeters.toDouble(),
          distanceText: distanceText,
        );
      }
    } catch (e) {
      print("❌ Error fetching route: $e");
    }

    return null;
  }


  Future<RouteResult?> fetchRouteWithOfflineFallback(LatLng origin, LatLng destination, String mode) async {
    final cachedRoute = CacheService.getCachedRoute(origin, destination, mode);
    if (cachedRoute != null) {
      print("🚀 Using cached route for $mode");
      return cachedRoute;
    }

    final isConnected = NetworkService.lastKnownConnectivityState;

    if (!isConnected) {
      return _createOfflineRouteWithoutLine(origin, destination, mode);
    }

    // Try online route first
    final onlineRoute = await fetchRoute(origin, destination, mode);
    if (onlineRoute != null) {
      // Cache the successful route
      CacheService.setCachedRoute(origin, destination, mode, onlineRoute);
      return onlineRoute;
    }

    // Fallback to offline route without line
    print("⚠️ Online route failed, showing offline info only");
    return _createOfflineRouteWithoutLine(origin, destination, mode);
  }


  RouteResult _createOfflineRouteWithoutLine(LatLng origin, LatLng destination, String mode) {
    final distance = LocationService.distanceBetween(origin, destination);
    final estimatedTime = LocationService.estimateTravelTime(distance, mode);

    // Apply transport mode multiplier for offline estimates
    final adjustedDistance = distance * AEDService.getTransportModeMultiplier(mode);

    return RouteResult(
      polyline: Polyline(
        polylineId: PolylineId('${mode}_offline_empty'),
        points: [], // Empty points - no line drawn
        color: Colors.transparent,
        width: 0,
      ),
      duration: estimatedTime,
      points: [],
      isOffline: true,
      actualDistance: adjustedDistance, // Use adjusted distance
      distanceText: LocationService.formatDistance(adjustedDistance),
    );
  }

  Future<void> preloadCachedRoutesForStartup(
      List<AED> aeds,
      LatLng userLocation,
      Function(AED, String, RouteResult) onRouteLoaded // mode parameter added
      ) async {
    print("🚀 Loading cached routes for startup...");

    final closestAEDs = aeds.take(5).toList(); // Top 5 AEDs

    for (final aed in closestAEDs) {
      // Check for both walking and driving cached routes
      for (final mode in ['walking', 'driving']) {
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, mode);
        if (cachedRoute != null) {
          print("📦 Found cached $mode route for AED ${aed.id}");
          onRouteLoaded(aed, mode, cachedRoute);
        }
      }
    }
  }

  static Future<RouteResult?> showNavigationPreviewForAED({
    required LatLng aedLocation,
    required LatLng currentLocation,
    required String transportMode,
    required String? apiKey,
    required List<AED> aedList,
    required Map<int, RouteResult> preloadedRoutes,
  }) async {
    // Find the AED to check if we have a preloaded route
    final aed = aedList.firstWhere(
          (aed) => aed.location.latitude == aedLocation.latitude &&
          aed.location.longitude == aedLocation.longitude,
      orElse: () => AED(id: -1, foundation: '', address: '', location: aedLocation),
    );

    // Check if we have a preloaded route
    final preloadedRoute = preloadedRoutes[aed.id];
    if (preloadedRoute != null) {
      return preloadedRoute;
    }

    // Fallback to regular route calculation if not preloaded
    final routeService = RouteService(apiKey ?? '');
    return await routeService.fetchRouteWithOfflineFallback(
      currentLocation,
      aedLocation,
      transportMode,
    );
  }

  /// Opens external navigation app (Google Maps)
  static Future<bool> openExternalNavigation({
    required LatLng origin,
    required LatLng destination,
    required String transportMode,
  }) async {
    final String googleMapsMode = transportMode == 'walking' ? 'walking' :
    transportMode == 'bicycling' ? 'bicycling' : 'driving';

    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
            '&origin=${origin.latitude},${origin.longitude}'
            '&destination=${destination.latitude},${destination.longitude}'
            '&travelmode=$googleMapsMode'
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      } else {
        throw 'Could not launch maps app';
      }
    } catch (e) {
      print("❌ Could not open external navigation: $e");
      return false;
    }
  }
}


class RoutePreloader {
  final String _apiKey;
  final Function(String) _onStatusUpdate;

  RoutePreloader(this._apiKey, this._onStatusUpdate);

  bool _isPreloading = false;
  bool get isPreloading => _isPreloading;

  /// Preloads routes for the closest AEDs
  Future<void> preloadRoutesForClosestAEDs({
    required List<AED> aeds,
    required LatLng userLocation,
    required String transportMode,
    required Function(AED, RouteResult) onRouteLoaded,
    int maxRoutes = 2,
  }) async {
    if (_isPreloading || aeds.isEmpty || _apiKey.isEmpty) return;

    _isPreloading = true;
    _onStatusUpdate("Preloading routes...");

    // Get closest AEDs
    final closestAEDs = aeds.take(maxRoutes).toList();

    for (final aed in closestAEDs) {
      try {
        // Check cache first
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, transportMode);
        if (cachedRoute != null) {
          onRouteLoaded(aed, cachedRoute);
          continue;
        }

        // Fetch new route
        final routeService = RouteService(_apiKey);
        final routeResult = await routeService.fetchRouteWithOfflineFallback(
          userLocation,
          aed.location,
          transportMode,
        );

        if (routeResult != null) {
          // Cache the route
          CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult);

          // Cache the distance for display
          if (routeResult.actualDistance != null) {
            CacheService.setDistance('aed_${aed.id}_actual', routeResult.actualDistance!);
          }

          // Notify callback
          onRouteLoaded(aed, routeResult);

          // Add delay to avoid rate limiting
          await Future.delayed(const Duration(milliseconds: 500));
        }
      } catch (e) {
        print("Error preloading route for AED ${aed.id}: $e");
      }
    }

    _isPreloading = false;
    _onStatusUpdate("Route preloading complete");
  }
}

class PolylineUtils {
  static List<LatLng> decode(String encoded) {
    List<LatLng> polylinePoints = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polylinePoints.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polylinePoints;
  }
}

