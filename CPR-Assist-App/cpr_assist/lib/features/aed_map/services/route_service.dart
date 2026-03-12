import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/aed_models.dart';
import '../../../core/core.dart';
import 'aed_service.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../../../services/network/network_service.dart';

class RouteResult {
  final Polyline polyline;
  final String duration;
  final List<LatLng> points;
  final bool isOffline;
  final double? actualDistance;
  final String? distanceText;
  final String? transportMode;

  RouteResult({
    required this.polyline,
    required this.duration,
    required this.points,
    this.isOffline = false,
    this.actualDistance,
    this.distanceText,
    this.transportMode,
  });
}

class RouteService {
  final String apiKey;
  RouteService(this.apiKey);

  Future<RouteResult?> fetchRoute(LatLng origin, LatLng destination, String mode) async {
    if (apiKey.isEmpty) {
      debugPrint('❌ Missing API Key.');
      return null;
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=$mode'
          '&key=$apiKey',
    );

    try {
      final response = await NetworkService.getExternal(url.toString());

      if (response != null && response['status'] == 'OK') {
        final routePoints = PolylineUtils.decode(
          response['routes'][0]['overview_polyline']['points'] as String,
        );
        final durationText = response['routes'][0]['legs'][0]['duration']['text'] as String;
        final distanceMeters = response['routes'][0]['legs'][0]['distance']['value'] as int;
        final distanceText = response['routes'][0]['legs'][0]['distance']['text'] as String;

        return RouteResult(
          polyline: Polyline(
            polylineId: PolylineId(mode),
            points: routePoints,
            color: mode == 'walking' ? AppColors.aedNavGreen : AppColors.primary,
            patterns: mode == 'walking'
                ? [PatternItem.dash(15), PatternItem.gap(8)]
                : [],
            width: 4,
          ),
          duration: durationText,
          points: routePoints,
          actualDistance: distanceMeters.toDouble(),
          distanceText: distanceText,
          transportMode: mode,
        );
      }
    } catch (e) {
      debugPrint('❌ Error fetching route: $e');
    }

    return null;
  }

  Future<RouteResult?> fetchRouteWithOfflineFallback(
      LatLng origin, LatLng destination, String mode) async {
    final cachedRoute = CacheService.getCachedRoute(origin, destination, mode);
    if (cachedRoute != null) {
      debugPrint('🚀 Using cached route for $mode');
      return cachedRoute;
    }

    final isConnected = NetworkService.lastKnownConnectivityState;

    if (!isConnected) {
      return _createOfflineRouteWithoutLine(origin, destination, mode);
    }

    final onlineRoute = await fetchRoute(origin, destination, mode);
    if (onlineRoute != null) {
      CacheService.setCachedRoute(origin, destination, mode, onlineRoute);
      return onlineRoute;
    }

    debugPrint('⚠️ Online route failed, showing offline info only');
    return _createOfflineRouteWithoutLine(origin, destination, mode);
  }

  RouteResult _createOfflineRouteWithoutLine(
      LatLng origin, LatLng destination, String mode) {
    final distance = LocationService.distanceBetween(origin, destination);
    final adjustedDistance = distance * AEDService.getTransportModeMultiplier(mode);
    final estimatedTime = LocationService.calculateOfflineETA(adjustedDistance, mode);

    return RouteResult(
      polyline: Polyline(
        polylineId: PolylineId('${mode}_offline_empty'),
        points: const [],
        color: AppColors.overlayDark.withValues(alpha: 0),
        width: 0,
      ),
      duration: estimatedTime,
      points: const [],
      isOffline: true,
      actualDistance: adjustedDistance,
      distanceText: LocationService.formatDistance(adjustedDistance),
      transportMode: mode,
    );
  }

  Future<void> preloadCachedRoutesForStartup(
      List<AED> aeds,
      LatLng userLocation,
      String primaryTransportMode,
      void Function(AED, String, RouteResult) onRouteLoaded,
      ) async {
    debugPrint('🚀 Loading cached routes for startup (mode: $primaryTransportMode)...');

    final closestAEDs = aeds.take(5).toList();

    for (final aed in closestAEDs) {
      final modesToCheck = [
        primaryTransportMode,
        primaryTransportMode == 'walking' ? 'driving' : 'walking',
      ];

      for (final mode in modesToCheck) {
        final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, mode);
        if (cachedRoute != null) {
          debugPrint('📦 Found cached $mode route for AED ${aed.id}');
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
    required Map<String, RouteResult> preloadedRoutes,
  }) async {
    final aed = aedList.firstWhere(
          (aed) =>
      aed.location.latitude == aedLocation.latitude &&
          aed.location.longitude == aedLocation.longitude,
      orElse: () => AED(id: -1, foundation: '', address: '', location: aedLocation),
    );

    final preloadedRoute = preloadedRoutes['${aed.id}_$transportMode'];
    if (preloadedRoute != null) return preloadedRoute;

    final routeService = RouteService(apiKey ?? '');
    return routeService.fetchRouteWithOfflineFallback(
      currentLocation,
      aedLocation,
      transportMode,
    );
  }

  /// Opens external navigation app (Google Maps).
  static Future<bool> openExternalNavigation({
    required LatLng origin,
    required LatLng destination,
    required String transportMode,
  }) async {
    final googleMapsMode = transportMode == 'walking'
        ? 'walking'
        : transportMode == 'bicycling'
        ? 'bicycling'
        : 'driving';

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
          '&origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&travelmode=$googleMapsMode',
    );

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      } else {
        throw 'Could not launch maps app';
      }
    } catch (e) {
      debugPrint('❌ Could not open external navigation: $e');
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class RouteHelper {
  final String? apiKey;

  RouteHelper(this.apiKey);

  /// Fetches a route and caches it.
  Future<RouteResult?> fetchAndCache({
    required LatLng origin,
    required LatLng destination,
    required String transportMode,
  }) async {
    if (apiKey == null) {
      debugPrint('❌ No API key available');
      return null;
    }

    try {
      final routeService = RouteService(apiKey!);

      final route = await routeService.fetchRoute(
        origin,
        destination,
        transportMode,
      ).timeout(
        AppConstants.apiTimeout,
        onTimeout: () {
          debugPrint('⏱️ Route fetch timeout');
          return null;
        },
      );

      if (route != null) {
        CacheService.setCachedRoute(origin, destination, transportMode, route);
        debugPrint('✅ Fetched and cached route: ${route.distanceText}');

        if (route.actualDistance != null) {
          CacheService.setDistance(
            'route_${origin.latitude}_${destination.latitude}_$transportMode',
            route.actualDistance!,
          );
        }
      }

      return route;
    } catch (e) {
      debugPrint('❌ Error fetching route: $e');
      return null;
    }
  }

  /// Gets route from cache or fetches fresh.
  Future<RouteResult?> getOrFetch({
    required LatLng origin,
    required LatLng destination,
    required String transportMode,
    bool allowNearby = true,
  }) async {
    RouteResult? route = CacheService.getCachedRoute(origin, destination, transportMode);
    if (route != null) {
      debugPrint('📦 Using cached route');
      return route;
    }

    if (allowNearby) {
      route = CacheService.getCachedRouteNearby(
        origin,
        destination,
        transportMode,
        maxDistanceMeters: 500,
      );

      if (route != null) {
        debugPrint('📦 Using nearby cached route');
        return route;
      }
    }

    debugPrint('🌐 Fetching fresh route');
    return fetchAndCache(
      origin: origin,
      destination: destination,
      transportMode: transportMode,
    );
  }

  /// Parses duration string like "10 mins" or "1 hour 5 mins" to minutes.
  static int parseDurationToMinutes(String duration) {
    try {
      int totalMinutes = 0;

      final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(duration.toLowerCase());
      if (hourMatch != null) {
        totalMinutes += int.parse(hourMatch.group(1)!) * 60;
      }

      final minMatch = RegExp(r'(\d+)\s*min').firstMatch(duration.toLowerCase());
      if (minMatch != null) {
        totalMinutes += int.parse(minMatch.group(1)!);
      }

      return totalMinutes;
    } catch (e) {
      debugPrint("⚠️ Error parsing duration '$duration': $e");
      return 0;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class RoutePreloader {
  final String _apiKey;
  final void Function(String) _onStatusUpdate;

  RoutePreloader(this._apiKey, this._onStatusUpdate);

  bool _isPreloading = false;
  bool get isPreloading => _isPreloading;

  /// Preloads routes for the closest AEDs.
  Future<void> preloadRoutesForClosestAEDs({
    required List<AED> aeds,
    required LatLng userLocation,
    required String transportMode,
    required void Function(AED, RouteResult) onRouteLoaded,
    int maxRoutes = 10,
  }) async {
    if (!await NetworkService.isConnected()) {
      debugPrint('🔴 No network - skipping route preloading');
      _isPreloading = false;
      _onStatusUpdate('Route preloading skipped (offline)');
      return;
    }

    if (_isPreloading || aeds.isEmpty || _apiKey.isEmpty) return;

    _isPreloading = true;
    _onStatusUpdate('Preloading routes...');

    final closestAEDs = aeds.take(maxRoutes).toList();
    debugPrint('🚀 Preloading routes for ${closestAEDs.length} closest AEDs (mode: $transportMode)...');

    int cachedCount = 0;
    int fetchedCount = 0;
    int failureCount = 0;

    for (int i = 0; i < closestAEDs.length; i++) {
      if (!_isPreloading) {
        debugPrint('🛑 Preloading stopped at ${i + 1}/$maxRoutes');
        return;
      }

      if (failureCount > 3) {
        debugPrint('⚠️ Too many failures ($failureCount) - stopping preload');
        _isPreloading = false;
        _onStatusUpdate('Route preloading stopped (errors)');
        return;
      }

      final aed = closestAEDs[i];

      try {
        final cachedRoute = CacheService.getCachedRoute(
          userLocation,
          aed.location,
          transportMode,
        );

        if (cachedRoute != null && !cachedRoute.isOffline) {
          onRouteLoaded(aed, cachedRoute);
          cachedCount++;
          debugPrint('📦 [${i + 1}/$maxRoutes] Using cached route for AED ${aed.id}');
          await Future.delayed(AppConstants.apiCallDelay);
          continue;
        }

        debugPrint('🌐 [${i + 1}/$maxRoutes] Fetching route for AED ${aed.id}...');
        final routeService = RouteService(_apiKey);

        final routeResult = await routeService.fetchRoute(
          userLocation,
          aed.location,
          transportMode,
        ).timeout(AppConstants.apiTimeout);

        if (routeResult != null) {
          CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult);

          if (routeResult.actualDistance != null) {
            CacheService.setDistance(
              'aed_${aed.id}_$transportMode',
              routeResult.actualDistance!,
            );
            debugPrint('✅ Cached REAL distance for AED ${aed.id}: ${LocationService.formatDistance(routeResult.actualDistance!)}');
          }

          onRouteLoaded(aed, routeResult);
          fetchedCount++;
          failureCount = 0;

          debugPrint('✅ [${i + 1}/$maxRoutes] Cached route for AED ${aed.id}: '
              '${LocationService.formatDistance(routeResult.actualDistance ?? 0)} (${routeResult.duration})');
        } else {
          failureCount++;
          debugPrint('⚠️ [${i + 1}/$maxRoutes] Failed to get route for AED ${aed.id}');
        }

        if (i < closestAEDs.length - 1) {
          _onStatusUpdate('Preloading ${i + 1}/$maxRoutes...');
          final delay = failureCount > 0
              ? const Duration(seconds: 2)
              : const Duration(seconds: 1);
          await Future.delayed(delay);
        }
      } catch (e) {
        failureCount++;
        debugPrint('❌ Error preloading route for AED ${aed.id}: $e');

        if (i < closestAEDs.length - 1) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    _isPreloading = false;
    debugPrint('✅ Route preloading complete: $cachedCount cached, $fetchedCount fetched, $failureCount failed');
    _onStatusUpdate('Route preloading complete');
  }

  void cancelPreloading() {
    if (!_isPreloading) return;
    _isPreloading = false;
    _onStatusUpdate('Route preloading cancelled');
    debugPrint('🛑 Route preloading cancelled');
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class PolylineUtils {
  static List<LatLng> decode(String encoded) {
    final polylinePoints = <LatLng>[];
    int index = 0;
    final len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polylinePoints.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polylinePoints;
  }
}