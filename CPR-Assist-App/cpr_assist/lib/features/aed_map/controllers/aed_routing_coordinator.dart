import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/core.dart';
import '../../../../models/aed_models.dart';
import '../../../../providers/app_providers.dart';
import '../../../services/network/network_service.dart';
import '../services/aed_service.dart';
import '../services/cache_service.dart';
import '../services/location_service.dart';
import '../services/map_service.dart';
import '../services/navigation_controller.dart' as nav;
import '../services/route_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SUPPORTING TYPES
// ══════════════════════════════════════════════════════════════════════════════

class RouteDistanceCalculation {
  final double distance;
  final bool isOffRoute;
  final double distanceFromRoute;

  const RouteDistanceCalculation({
    required this.distance,
    required this.isOffRoute,
    required this.distanceFromRoute,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// CALLBACKS
// ══════════════════════════════════════════════════════════════════════════════

/// Callbacks the widget must supply so the coordinator can trigger UI actions.
class AEDRoutingCallbacks {
  /// Rebuild the widget (setState).
  final VoidCallback onStateChanged;

  /// Called when the user has arrived at the AED destination.
  final void Function() onArrived;

  /// Called when the user is off-route (show recalculating banner).
  final void Function() onOffRoute;

  /// Called when a closer AED is detected during navigation.
  final void Function(AED closerAED, double distance) onCloserAEDFound;

  /// Switch GPS back to non-navigation accuracy.
  final Future<void> Function() onStopNavigationGPS;

  /// Switch GPS to navigation accuracy.
  final Future<void> Function() onStartNavigationGPS;

  const AEDRoutingCallbacks({
    required this.onStateChanged,
    required this.onArrived,
    required this.onOffRoute,
    required this.onCloserAEDFound,
    required this.onStopNavigationGPS,
    required this.onStartNavigationGPS,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// COORDINATOR
// ══════════════════════════════════════════════════════════════════════════════

/// Owns all routing and navigation logic that lives between the services and
/// the widget. Extracted from _AEDMapWidgetState.
class AEDRoutingCoordinator {
  final WidgetRef _ref;
  final AEDRoutingCallbacks _callbacks;

  // Injected from the widget — set after map creation.
  nav.NavigationController? navigationController;
  MapViewController? mapViewController;
  RouteHelper? _routeHelper;
  RoutePreloader? _routePreloader;
  String? _googleMapsApiKey;

  // ── Route state ────────────────────────────────────────────────────────────
  final Map<String, RouteResult> preloadedRoutes = {};
  bool _isRouteFetchInProgress = false;
  String _lastFetchReason = '';
  DateTime? _lastRouteUpdateTime;
  LatLng? _lastRouteUpdateLocation;
  DateTime? _lastOffRouteBannerTime;
  DateTime? _lastCloserAEDNotification;
  DateTime? _lastProgrammaticCameraMove;

  // ── Location-freshness flags (supplied by location controller) ─────────────
  bool isUsingCachedLocation = false;

  AEDRoutingCoordinator({
    required WidgetRef ref,
    required AEDRoutingCallbacks callbacks,
  })  : _ref = ref,
        _callbacks = callbacks;

  // ══════════════════════════════════════════════════════════════════════════
  // INITIALISATION
  // ══════════════════════════════════════════════════════════════════════════

  void setApiKey(String? key) {
    _googleMapsApiKey = key;
    if (key != null) {
      _routeHelper   = RouteHelper(key);
      _routePreloader = RoutePreloader(key, (status) {});
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NAVIGATION PREVIEW
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> showNavigationPreviewForAED(LatLng aedLocation) async {
    _lastProgrammaticCameraMove = DateTime.now();

    final currentState   = _ref.read(mapStateProvider);
    final mapNotifier    = _ref.read(mapStateProvider.notifier);
    final LatLng? currentLocation = currentState.userLocation;

    // ── No GPS: show AED location only ──────────────────────────────────────
    if (currentLocation == null) {
      mapNotifier.showNavigationPreview(aedLocation);
      await mapViewController?.zoomToAED(aedLocation);
      return;
    }

    mapNotifier.showNavigationPreview(aedLocation);

    final aed      = _findAED(aedLocation, currentState.aedList);
    final isTooOld = _isLocationTooOld(currentState);

    // Background preload of both transport modes (fire-and-forget).
    if (!isTooOld && !currentState.isOffline && _googleMapsApiKey != null) {
      Future.delayed(Duration.zero, () {
        preloadBothTransportModes(currentLocation, aedLocation);
      });
    }

    RouteResult? routeResult;

    // Step 1: RAM cache (preloaded routes).
    final routeKey = '${aed.id}_${currentState.navigation.transportMode}';
    if (preloadedRoutes.containsKey(routeKey)) {
      debugPrint(
          '🚀 Using preloaded route for AED ${aed.id} (${currentState.navigation.transportMode})');
      routeResult = preloadedRoutes[routeKey];
    }

    // Step 2: Fresh network fetch (only if RAM cache missed).
    final bool shouldFetchFresh = routeResult == null &&
        !currentState.isOffline &&
        _googleMapsApiKey != null &&
        !isTooOld;

    if (shouldFetchFresh) {
      debugPrint('🌎 Online: Fetching fresh route...');
      routeResult = await _routeHelper!.fetchAndCache(
        origin:        currentLocation,
        destination:   aedLocation,
        transportMode: currentState.navigation.transportMode,
      );

      if (routeResult?.actualDistance != null) {
        CacheService.setDistance(
          'aed_${aed.id}_${currentState.navigation.transportMode}',
          routeResult!.actualDistance!,
        );
      }
    }

    // Step 3: Disk cache fallback.
    if (routeResult == null) {
      routeResult = CacheService.getCachedRoute(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
      );
      routeResult ??= CacheService.getCachedRouteNearby(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
        maxDistanceMeters: 1000,
      );

      if (routeResult != null) {
        routeResult =
            _recolourRoute(routeResult, currentState.navigation.transportMode);
      }
    }

    // ── Render ──────────────────────────────────────────────────────────────
    if (routeResult != null && !isTooOld) {
      final shouldShowGray =
          isUsingCachedLocation || currentState.isOffline;

      final polyline = shouldShowGray
          ? _greyPolyline(routeResult)
          : _colouredPolyline(
          routeResult, currentState.navigation.transportMode);

      mapNotifier.updateRoute(
        polyline,
        routeResult.duration,
        routeResult.actualDistance ??
            LocationService.distanceBetween(currentLocation, aedLocation),
      );

      _lastProgrammaticCameraMove = DateTime.now();
      await mapViewController?.zoomToUserAndAED(
        userLocation:    currentLocation,
        aedLocation:     aedLocation,
        polylinePoints:  routeResult.points,
      );
    } else if (isTooOld) {
      mapNotifier.updateRoute(null, '', 0);
    } else {
      // Offline estimation.
      final estimatedDistance = AEDService.calculateEstimatedDistance(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
      );
      final estimatedTime = LocationService.calculateOfflineETA(
        estimatedDistance,
        currentState.navigation.transportMode,
      );

      if (aed.id != -1) {
        CacheService.setDistance(
            'aed_${aed.id}_walking_est',
            AEDService.calculateEstimatedDistance(
                currentLocation, aedLocation, 'walking'));
        CacheService.setDistance(
            'aed_${aed.id}_driving_est',
            AEDService.calculateEstimatedDistance(
                currentLocation, aedLocation, 'driving'));
      }

      mapNotifier.updateRoute(null, estimatedTime, estimatedDistance);

      _lastProgrammaticCameraMove = DateTime.now();
      await mapViewController?.zoomToUserAndAED(
        userLocation:   currentLocation,
        aedLocation:    aedLocation,
        polylinePoints: const [],
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // START NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> startNavigation(
      LatLng aedLocation, {
        required bool isUsingCachedOrStaleLocation,
        required bool isStale,
        required bool isTooOld,
        required LocationService locationService,
        required BuildContext context,
      }) async {
    final currentState = _ref.read(mapStateProvider);
    LatLng? currentLocation = currentState.userLocation;

    // Get a fresh high-accuracy fix if we only have a cached/stale location.
    if (currentLocation != null && isUsingCachedOrStaleLocation) {
      debugPrint(
          '⚠️ Using cached/stale location — getting fresh GPS fix before navigation...');
      try {
        UIHelper.showLoading(context, 'Getting precise location...');

        final freshPosition = await locationService.getCurrentPosition(
          accuracy:  LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        if (freshPosition != null) {
          currentLocation =
              LatLng(freshPosition.latitude, freshPosition.longitude);
          _ref
              .read(mapStateProvider.notifier)
              .updateUserLocation(currentLocation);
          debugPrint('✅ Got fresh HIGH accuracy location: $currentLocation');
          UIHelper.clearSnackbars(context);
        }
      } catch (e) {
        debugPrint('⚠️ Error getting fresh location: $e');
      }
    }

    final mapNotifier = _ref.read(mapStateProvider.notifier);

    // ── Compass-only navigation (no GPS or location too old) ─────────────────
    if (currentLocation == null || isTooOld) {
      debugPrint(
          '🧭 Starting compass-only navigation (no location or location too old)');
      mapNotifier.startNavigation(aedLocation);
      navigationController?.startCompassOnlyMode(aedLocation);
      return;
    }

    if (navigationController == null) {
      debugPrint('❌ NavigationController not ready');
      return;
    }

    await navigationController!.startNavigation(
      currentLocation,
      aedLocation,
      isOffline: currentState.isOffline || isStale,
    );

    mapNotifier.startNavigation(aedLocation);
    await _callbacks.onStartNavigationGPS();

    // ── Fetch / cache route ──────────────────────────────────────────────────
    RouteResult? routeResult;

    final bool locationRecentlyChanged = _lastRouteUpdateTime != null &&
        DateTime.now().difference(_lastRouteUpdateTime!) <
            const Duration(seconds: 10);

    if (!locationRecentlyChanged) {
      routeResult = CacheService.getCachedRoute(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
      );
      if (routeResult != null) {
        debugPrint('📦 Using cached route (location stable)');
      }
    }

    if (routeResult == null &&
        !currentState.isOffline &&
        _googleMapsApiKey != null) {
      if (context.mounted) {
        UIHelper.showLoading(context, 'Calculating route...');
      }

      routeResult = await _routeHelper!.fetchAndCache(
        origin:        currentLocation,
        destination:   aedLocation,
        transportMode: currentState.navigation.transportMode,
      );

      if (context.mounted) UIHelper.clearSnackbars(context);
    }

    // Nearby cache fallback.
    routeResult ??= CacheService.getCachedRouteNearby(
      currentLocation,
      aedLocation,
      currentState.navigation.transportMode,
      maxDistanceMeters: 500,
    );

    // ── Display route or offline estimation ──────────────────────────────────
    if (routeResult != null && !routeResult.isOffline) {
      final shouldShowGray =
          isUsingCachedLocation || currentState.isOffline || isStale;

      final polyline = shouldShowGray
          ? _greyPolyline(routeResult)
          : routeResult.polyline;

      final originalDurationMinutes =
      RouteHelper.parseDurationToMinutes(routeResult.duration);

      mapNotifier.updateRoute(
        polyline,
        routeResult.duration,
        routeResult.actualDistance ??
            LocationService.distanceBetween(currentLocation, aedLocation),
      );

      mapNotifier.setOriginalRouteMetrics(
        originalDistance:        routeResult.actualDistance ?? 0,
        originalDurationMinutes: originalDurationMinutes,
      );
    } else {
      final estimatedDistance = AEDService.calculateEstimatedDistance(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
      );
      final estimatedTime = LocationService.calculateOfflineETA(
        estimatedDistance,
        currentState.navigation.transportMode,
      );
      mapNotifier.updateRoute(null, estimatedTime, estimatedDistance);
      debugPrint('🧭 Starting navigation with offline estimation');
    }

    _lastRouteUpdateTime     = DateTime.now();
    _lastRouteUpdateLocation = currentLocation;
    debugPrint('✅ Navigation started — route updates enabled');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CANCEL NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> cancelNavigation(GoogleMapController? mapController) async {
    navigationController?.cancelNavigation();

    final currentState = _ref.read(mapStateProvider);
    final mapNotifier  = _ref.read(mapStateProvider.notifier);

    if (currentState.navigation.hasStarted) {
      mapNotifier.showNavigationPreview(currentState.navigation.destination!);

      if (currentState.userLocation != null) {
        mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target:  currentState.userLocation!,
              zoom:    AppConstants.defaultZoom,
              bearing: 0.0,
              tilt:    0.0,
            ),
          ),
        );
      }
    } else {
      mapNotifier.cancelNavigation();
    }

    await _callbacks.onStopNavigationGPS();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVE NAVIGATION UPDATES
  // ══════════════════════════════════════════════════════════════════════════

  /// Called from the location update pipeline during active navigation.
  Future<void> handleNavigationLocationUpdate(LatLng currentLocation) async {
    final currentState = _ref.read(mapStateProvider);

    if (!currentState.navigation.hasStarted ||
        currentState.navigation.destination == null) {
      return;
    }

    final destination = currentState.navigation.destination!;

    // ── Arrival check ────────────────────────────────────────────────────────
    final distToDestination =
    LocationService.distanceBetween(currentLocation, destination);
    if (distToDestination < AppConstants.navigationArrivalRadius) {
      _callbacks.onArrived();
      return;
    }

    // ── Closer AED check ─────────────────────────────────────────────────────
    if (currentState.aedList.length > 1) {
      _checkForCloserAED(currentLocation, currentState);
    }

    // ── ETA update ───────────────────────────────────────────────────────────
    final shouldUpdateETA = _lastRouteUpdateLocation == null ||
        LocationService.distanceBetween(
            _lastRouteUpdateLocation!, currentLocation) >
            AppConstants.routeEtaUpdateDistance;

    if (shouldUpdateETA) {
      await Future.microtask(() async {
        final state       = _ref.read(mapStateProvider);
        final mapNotifier = _ref.read(mapStateProvider.notifier);

        double remainingDistance;
        String estimatedTime;

        if (state.navigation.route != null &&
            state.navigation.route!.points.isNotEmpty) {
          final routeCalc = calculateRemainingRouteDistance(
            currentLocation,
            state.navigation.route!.points,
            state.navigation.destination!,
          );
          remainingDistance = routeCalc.distance;
          estimatedTime     = _calculateSmartETA(
            remainingDistance,
            state.navigation.route!,
            state.navigation.transportMode,
          );
        } else {
          remainingDistance = LocationService.distanceBetween(
              currentLocation, state.navigation.destination!);
          estimatedTime = LocationService.calculateOfflineETA(
            remainingDistance,
            state.navigation.transportMode,
          );
        }

        mapNotifier.updateRoute(
            state.navigation.route, estimatedTime, remainingDistance);
        await updateNavigationRoute(currentLocation, destination);
      });
    }

    // ── Forward to navigation controller ─────────────────────────────────────
    if (navigationController != null && navigationController!.isActive) {
      navigationController!.updateUserLocation(currentLocation);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ROUTE UPDATE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> updateNavigationRoute(
      LatLng currentLocation, LatLng destination) async {
    final currentState = _ref.read(mapStateProvider);
    final mapNotifier  = _ref.read(mapStateProvider.notifier);

    bool isOffRoute         = false;
    double distanceFromRoute = 0;

    if (currentState.navigation.route != null &&
        currentState.navigation.route!.points.isNotEmpty) {
      final routeCalc = calculateRemainingRouteDistance(
        currentLocation,
        currentState.navigation.route!.points,
        currentState.navigation.destination!,
      );
      isOffRoute        = routeCalc.isOffRoute;
      distanceFromRoute = routeCalc.distanceFromRoute;

      if (isOffRoute) {
        debugPrint(
            '⚠️ User is off-route by ${distanceFromRoute.toStringAsFixed(0)}m');
        if (_shouldShowOffRouteBanner()) {
          _callbacks.onOffRoute();
          _lastOffRouteBannerTime = DateTime.now();
        }
      }
    }

    if (!currentState.isOffline && _googleMapsApiKey != null) {
      final shouldFetch =
      _shouldFetchNewRoute(currentLocation, isOffRoute, distanceFromRoute);

      if (shouldFetch && !_isRouteFetchInProgress) {
        _isRouteFetchInProgress  = true;
        debugPrint('🔄 Fetching updated route (reason: $_lastFetchReason)...');
        _lastRouteUpdateTime     = DateTime.now();
        _lastRouteUpdateLocation = currentLocation;

        try {
          final newRoute = await _routeHelper!.fetchAndCache(
            origin:        currentLocation,
            destination:   destination,
            transportMode: currentState.navigation.transportMode,
          );

          if (newRoute != null) {
            debugPrint(
                '✅ Updated route: ${newRoute.distanceText} (${newRoute.duration})');
            final newOriginalDurationMinutes =
            RouteHelper.parseDurationToMinutes(newRoute.duration);

            mapNotifier.updateRoute(
              newRoute.polyline,
              newRoute.duration,
              newRoute.actualDistance ??
                  LocationService.distanceBetween(
                      currentLocation, destination),
            );

            mapNotifier.setOriginalRouteMetrics(
              originalDistance:        newRoute.actualDistance ?? 0,
              originalDurationMinutes: newOriginalDurationMinutes,
            );
          }
        } catch (e) {
          debugPrint('⚠️ Route fetch error: $e');
        } finally {
          _isRouteFetchInProgress = false;
        }
      } else if (shouldFetch && _isRouteFetchInProgress) {
        debugPrint('⏸️ Route fetch already in progress, skipping');
      }
    }

    // ── Update bearing toward next waypoint ────────────────────────────────
    if (currentState.navigation.route != null &&
        currentState.navigation.route!.points.isNotEmpty) {
      final nextPoint = _getNextWaypointAhead(
          currentLocation, currentState.navigation.route!.points);

      if (nextPoint != null) {
        _calculateBearing(currentLocation, nextPoint);
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RECALCULATE (after connectivity restore)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> recalculateActiveRoute() async {
    final currentState = _ref.read(mapStateProvider);

    if (currentState.navigation.destination == null ||
        currentState.userLocation == null) {
      return;
    }

    debugPrint('🔄 Recalculating active route after connection restore...');

    await updateNavigationRoute(
      currentState.userLocation!,
      currentState.navigation.destination!,
    );

    if (currentState.aedList.length > 1) {
      _checkForCloserAED(currentState.userLocation!, currentState);
    }
  }

  Future<void> switchNavigationToOfflineMode() async {
    final currentState = _ref.read(mapStateProvider);
    if (currentState.navigation.destination == null ||
        currentState.userLocation == null) {
      return;
    }

    final estimatedDistance = AEDService.calculateEstimatedDistance(
      currentState.userLocation!,
      currentState.navigation.destination!,
      currentState.navigation.transportMode,
    );
    final estimatedTime = LocationService.calculateOfflineETA(
      estimatedDistance,
      currentState.navigation.transportMode,
    );

    _ref.read(mapStateProvider.notifier).updateRoute(
      null,
      estimatedTime,
      estimatedDistance,
    );

    debugPrint('🔴 Switched to offline navigation mode');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CLOSER AED
  // ══════════════════════════════════════════════════════════════════════════

  void _checkForCloserAED(LatLng currentLocation, AEDMapState currentState) {
    final currentDestination = currentState.navigation.destination!;
    final currentDistance =
    LocationService.distanceBetween(currentLocation, currentDestination);

    final closestAED      = currentState.aedList.first;
    final closestDistance =
    LocationService.distanceBetween(currentLocation, closestAED.location);

    final isSameDestination =
        LocationService.distanceBetween(
            closestAED.location, currentDestination) <
            AppConstants.sameAedTolerance;

    if (!isSameDestination &&
        (currentDistance - closestDistance) > AppConstants.closerAedThreshold) {
      _notifyCloserAED(closestAED, closestDistance);
    }
  }

  void _notifyCloserAED(AED closerAED, double distance) {
    final now = DateTime.now();
    if (_lastCloserAEDNotification != null &&
        now.difference(_lastCloserAEDNotification!).inSeconds < 60) {
      return;
    }

    _lastCloserAEDNotification = now;
    _callbacks.onCloserAEDFound(closerAED, distance);
  }

  Future<void> switchToCloserAED(AED newAED) async {
    debugPrint('🔄 Switching navigation to closer AED: ${newAED.address}');
    navigationController?.cancelNavigation();
    await showNavigationPreviewForAED(newAED.location);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // EXTERNAL NAVIGATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> openExternalNavigation(
      LatLng destination, BuildContext context) async {
    final currentState = _ref.read(mapStateProvider);
    if (currentState.userLocation == null) return;

    final success = await RouteService.openExternalNavigation(
      origin:        currentState.userLocation!,
      destination:   destination,
      transportMode: currentState.navigation.transportMode,
    );

    if (!success && context.mounted) {
      UIHelper.showError(context, 'Could not open external navigation');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TRANSPORT MODE CHANGE
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> onTransportModeChanged(
      String mode, {
        required BuildContext context,
        required AEDService aedRepository,
      }) async {
    final mapNotifier = _ref.read(mapStateProvider.notifier);
    mapNotifier.updateTransportMode(mode);

    await Future.delayed(Duration.zero);

    final currentState = _ref.read(mapStateProvider);

    if (currentState.userLocation != null) {
      final resorted = aedRepository.sortAEDsByDistance(
        currentState.aedList,
        currentState.userLocation!,
        mode,
      );
      mapNotifier.updateAEDs(resorted);

      if (_googleMapsApiKey != null) {
        aedRepository.improveDistanceAccuracyInBackground(
          resorted,
          currentState.userLocation!,
          mode,
          _googleMapsApiKey,
              (improvedAEDs) {
            final s = _ref.read(mapStateProvider);
            final reSorted = aedRepository.sortAEDsByDistance(
              improvedAEDs,
              s.userLocation,
              mode,
            );
            mapNotifier.updateAEDs(reSorted);
            updatePreloadedRoutesFromCache(improvedAEDs, mode);
            _callbacks.onStateChanged();
          },
        );
      }
    }

    final navState = _ref.read(mapStateProvider).navigation;

    if (navState.destination != null && currentState.userLocation != null) {
      if (navState.hasStarted) {
        debugPrint(
            '🔄 Transport mode changed during navigation — recalculating route...');

        if (context.mounted) {
          UIHelper.showSnackbar(
            context,
            message: 'Switched to ${mode == "walking" ? "walking" : "driving"} mode',
            icon:     Icons.directions,
            duration: const Duration(seconds: 2),
          );
        }

        final newRoute = await _routeHelper?.fetchAndCache(
          origin:        currentState.userLocation!,
          destination:   navState.destination!,
          transportMode: mode,
        );

        if (newRoute != null) {
          final newOriginalDurationMinutes =
          RouteHelper.parseDurationToMinutes(newRoute.duration);

          _ref.read(mapStateProvider.notifier).updateRoute(
            newRoute.polyline,
            newRoute.duration,
            newRoute.actualDistance ??
                LocationService.distanceBetween(
                  currentState.userLocation!,
                  navState.destination!,
                ),
          );

          _ref.read(mapStateProvider.notifier).setOriginalRouteMetrics(
            originalDistance:        newRoute.actualDistance ?? 0,
            originalDurationMinutes: newOriginalDurationMinutes,
          );
        }
      } else if (navState.isActive) {
        await showNavigationPreviewForAED(navState.destination!);
      }
    }

    // Preload routes for new mode.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (_googleMapsApiKey != null && currentState.userLocation != null) {
        preloadTopRoutes();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ROUTE PRELOADING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> preloadTopRoutes() async {
    final currentState = _ref.read(mapStateProvider);
    final userLocation = currentState.userLocation;

    if (userLocation == null ||
        _routePreloader == null ||
        _googleMapsApiKey == null) {
      return;
    }

    final top10 = currentState.aedList.take(AppConstants.maxPreloadedRoutes).toList();
    debugPrint('🚀 Starting route preloading for top ${top10.length} AEDs...');

    try {
      for (final mode in ['walking', 'driving']) {
        await _routePreloader!.preloadRoutesForClosestAEDs(
          aeds:          top10,
          userLocation:  userLocation,
          transportMode: mode,
          onRouteLoaded: (originalAed, route) {
            if (route.actualDistance != null) {
              final routeKey = '${originalAed.id}_$mode';
              preloadedRoutes[routeKey] = route;
              _limitPreloadedRoutesSize();
              CacheService.setDistance(
                  'aed_${originalAed.id}_$mode', route.actualDistance!);
            }
          },
        );
      }
      await CacheService.saveDistanceCache();
    } catch (e) {
      debugPrint('❌ Error preloading routes: $e');
    }
  }

  Future<void> preloadBothTransportModes(
      LatLng userLocation, LatLng aedLocation) async {
    if (_googleMapsApiKey == null || !await NetworkService.isConnected()) return;

    debugPrint('🚗🚶 Preloading both walking and driving routes...');

    final currentState = _ref.read(mapStateProvider);

    for (final mode in ['walking', 'driving']) {
      final cached =
      CacheService.getCachedRoute(userLocation, aedLocation, mode);
      if (cached != null) {
        debugPrint('✅ $mode route already cached');
        continue;
      }

      final route = await _routeHelper!.fetchAndCache(
        origin:        userLocation,
        destination:   aedLocation,
        transportMode: mode,
      );

      if (route?.actualDistance != null) {
        final aed = currentState.aedList.firstWhere(
              (a) =>
          a.location.latitude == aedLocation.latitude &&
              a.location.longitude == aedLocation.longitude,
          orElse: () => currentState.aedList.first,
        );
        CacheService.setDistance('aed_${aed.id}_$mode', route!.actualDistance!);
      }

      await Future.delayed(AppConstants.apiCallDelay);
    }
  }

  void scheduleRoutePreloading() {
    final currentState = _ref.read(mapStateProvider);
    if (currentState.userLocation != null &&
        currentState.aedList.isNotEmpty &&
        _googleMapsApiKey != null) {
      Future.delayed(AppConstants.routePreloadDelay, preloadTopRoutes);
    }
  }

  void updatePreloadedRoutesFromCache(List<AED> aeds, String transportMode) {
    final currentState = _ref.read(mapStateProvider);
    if (currentState.userLocation == null) return;

    int updatedCount = 0;
    for (final aed in aeds.take(20)) {
      final cachedRoute = CacheService.getCachedRoute(
        currentState.userLocation!,
        aed.location,
        transportMode,
      );
      if (cachedRoute != null) {
        preloadedRoutes['${aed.id}_$transportMode'] = cachedRoute;
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      debugPrint(
          '♻️ Updated $updatedCount preloaded routes from cache ($transportMode)');
    }
  }

  void _limitPreloadedRoutesSize() {
    if (preloadedRoutes.length > AppConstants.maxPreloadedRoutesCache) {
      final keysToRemove = preloadedRoutes.keys
          .take(preloadedRoutes.length - AppConstants.maxPreloadedRoutesCache)
          .toList();
      for (final key in keysToRemove) {
        preloadedRoutes.remove(key);
      }
      debugPrint(
          '🗑️ Trimmed preloaded routes to ${AppConstants.maxPreloadedRoutesCache} entries');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ROUTE DISTANCE & ETA HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  RouteDistanceCalculation calculateRemainingRouteDistance(
      LatLng currentLocation,
      List<LatLng> routePoints,
      LatLng destination,
      ) {
    if (routePoints.isEmpty) {
      return RouteDistanceCalculation(
        distance:          LocationService.distanceBetween(currentLocation, destination),
        isOffRoute:        false,
        distanceFromRoute: 0,
      );
    }

    int closestIndex    = 0;
    double minDistance  = double.infinity;

    for (int i = 0; i < routePoints.length; i++) {
      final dist =
      LocationService.distanceBetween(currentLocation, routePoints[i]);
      if (dist < minDistance) {
        minDistance  = dist;
        closestIndex = i;
      }
    }

    final isOffRoute        = minDistance > AppConstants.offRouteDistanceThreshold;
    double remainingDistance = minDistance;

    for (int i = closestIndex; i < routePoints.length - 1; i++) {
      remainingDistance += LocationService.distanceBetween(
        routePoints[i],
        routePoints[i + 1],
      );
    }

    return RouteDistanceCalculation(
      distance:          remainingDistance,
      isOffRoute:        isOffRoute,
      distanceFromRoute: minDistance,
    );
  }

  String _calculateSmartETA(
      double remainingDistance, Polyline route, String transportMode) {
    final currentState           = _ref.read(mapStateProvider);
    final originalDistance       = currentState.navigation.originalDistance;
    final originalDurationMinutes = currentState.navigation.originalDurationMinutes;

    if (originalDistance != null &&
        originalDurationMinutes != null &&
        originalDistance > 0 &&
        originalDurationMinutes > 0 &&
        remainingDistance > 0) {
      final progressPercent  = 1.0 - (remainingDistance / originalDistance);
      final remainingMinutes =
      (originalDurationMinutes * (1.0 - progressPercent)).ceil();

      if (remainingMinutes < 1) return '< 1min';
      if (remainingMinutes < 60) return '${remainingMinutes}min';
      final hours   = remainingMinutes ~/ 60;
      final minutes = remainingMinutes % 60;
      return minutes > 0 ? '${hours}h ${minutes}min' : '${hours}h';
    }

    return LocationService.calculateOfflineETA(remainingDistance, transportMode);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  bool _shouldFetchNewRoute(
      LatLng currentLocation, bool isOffRoute, double distanceFromRoute) {
    final now = DateTime.now();

    if (isOffRoute &&
        distanceFromRoute > AppConstants.offRouteDistanceThreshold) {
      _lastFetchReason =
      'Off-route by ${distanceFromRoute.toStringAsFixed(0)}m';
      return true;
    }

    if (_lastRouteUpdateTime == null) {
      _lastFetchReason = 'Initial route fetch';
      return true;
    }

    final timeSinceLastFetch    = now.difference(_lastRouteUpdateTime!);
    final distanceSinceLastFetch = _lastRouteUpdateLocation != null
        ? LocationService.distanceBetween(
        _lastRouteUpdateLocation!, currentLocation)
        : 0.0;

    if (distanceSinceLastFetch > AppConstants.routeRefetchDistanceMeters ||
        timeSinceLastFetch.inSeconds > AppConstants.routeRefetchIntervalSeconds) {
      _lastFetchReason =
      'Moved ${distanceSinceLastFetch.toStringAsFixed(0)}m or '
          '${timeSinceLastFetch.inSeconds}s passed';
      return true;
    }

    if (timeSinceLastFetch.inMinutes >= AppConstants.routeRefetchPeriodicMinutes) {
      _lastFetchReason =
      'Periodic check (${timeSinceLastFetch.inMinutes} min)';
      return true;
    }

    return false;
  }

  bool _shouldShowOffRouteBanner() {
    if (_lastOffRouteBannerTime == null) return true;
    return DateTime.now().difference(_lastOffRouteBannerTime!).inSeconds >= 10;
  }

  bool _isLocationTooOld(AEDMapState state) {
    // Actual staleness is checked via AEDLocationController.isLocationTooOld().
    // This coordinator receives the flag via isUsingCachedLocation.
    return false;
  }

  LatLng? _getNextWaypointAhead(
      LatLng currentLocation, List<LatLng> routePoints) {
    if (routePoints.length < 2) return null;

    int closestIndex   = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < routePoints.length; i++) {
      final dist =
      LocationService.distanceBetween(currentLocation, routePoints[i]);
      if (dist < minDistance) {
        minDistance  = dist;
        closestIndex = i;
      }
    }

    final lookAheadIndex =
    (closestIndex + 8).clamp(0, routePoints.length - 1);
    return routePoints[lookAheadIndex];
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude  * (pi / 180);
    final lat2 = to.latitude    * (pi / 180);
    final dLon = (to.longitude - from.longitude) * (pi / 180);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * (180 / pi);
    return (bearing + 360) % 360;
  }

  AED _findAED(LatLng aedLocation, List<AED> aedList) {
    return aedList.firstWhere(
          (aed) =>
      aed.location.latitude == aedLocation.latitude &&
          aed.location.longitude == aedLocation.longitude,
      orElse: () =>
          AED(id: -1, foundation: '', address: '', location: aedLocation),
    );
  }

  RouteResult _recolourRoute(RouteResult route, String transportMode) {
    return RouteResult(
      polyline: Polyline(
        polylineId: route.polyline.polylineId,
        points:     route.polyline.points,
        color: transportMode == 'walking'
            ? AppColors.cprGreen
            : AppColors.info,
        patterns: transportMode == 'walking'
            ? [PatternItem.dash(15), PatternItem.gap(8)]
            : [],
        width: 4,
      ),
      duration:       route.duration,
      points:         route.points,
      isOffline:      route.isOffline,
      actualDistance: route.actualDistance,
      distanceText:   route.distanceText,
    );
  }

  Polyline _greyPolyline(RouteResult route) {
    return Polyline(
      polylineId: route.polyline.polylineId,
      points:     route.polyline.points,
      color:      AppColors.textDisabled,
      width:      4,
    );
  }

  Polyline _colouredPolyline(RouteResult route, String transportMode) {
    return Polyline(
      polylineId: route.polyline.polylineId,
      points:     route.polyline.points,
      color: transportMode == 'walking' ? AppColors.cprGreen : AppColors.info,
      patterns: transportMode == 'walking'
          ? [PatternItem.dash(15), PatternItem.gap(8)]
          : [],
      width: 4,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROGRAMMATIC CAMERA MOVE TIMESTAMP
  // ══════════════════════════════════════════════════════════════════════════

  DateTime? get lastProgrammaticCameraMove => _lastProgrammaticCameraMove;

  void markProgrammaticCameraMove() {
    _lastProgrammaticCameraMove = DateTime.now();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ══════════════════════════════════════════════════════════════════════════

  void dispose() {
    preloadedRoutes.clear();
    debugPrint('🗑️ AEDRoutingCoordinator disposed');
  }
}