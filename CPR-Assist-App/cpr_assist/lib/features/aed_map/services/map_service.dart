import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/core.dart';
import 'location_service.dart';

// MapUtils holds only values that are intentionally different from AppConstants
// (overview zoom vs close-up navigation zoom) or purely internal to this file.
class MapUtils {
  /// Route overview / navigation-panel zoom — intentionally less than
  /// AppConstants.navigationZoom (20.0) which is used for close-up turn-by-turn.
  static const double navigationZoom = AppConstants.navigationZoomOverview;

  static const double overviewPadding        = AEDMapUIConstants.mapOverviewPadding;
  static const double routePadding           = AEDMapUIConstants.mapRoutePadding;
  static const double rerouteThresholdMeters = AppConstants.rerouteThresholdMeters;

  /// Greece overview zoom — intentionally 6.5 (slightly closer than
  /// AppConstants.greeceZoom = 6.0 which is used for the default fallback position).
  static const double greeceZoom = 6.5;

  static const double maxZoom = AppConstants.maxMapZoom;
}


class MapViewController {
  final GoogleMapController controller;
  final BuildContext context;
  bool _isAnimating = false;
  CameraPosition? _lastCameraPosition;

  MapViewController(this.controller, this.context);

  Future<void> zoomToUserAndClosestAEDs(
      LatLng userLocation,
      List<LatLng> aedLocations, {
        double padding = AEDMapUIConstants.mapOverviewPadding,
        bool force = false,
      }) async {
    debugPrint('🗺️ zoomToUserAndClosestAEDs called, _isAnimating=$_isAnimating');

    if (_isAnimating && !force) {
      debugPrint('⚠️ zoomToUserAndClosestAEDs BLOCKED by _isAnimating');
      return;
    }
    _isAnimating = true;

    try {
      if (aedLocations.isEmpty) {
        debugPrint('🗺️ No AEDs, zooming to user only');
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(userLocation, AppConstants.defaultZoom - 1),
        );
        return;
      }

      final closestAEDs = getClosestAEDsToPoint(userLocation, aedLocations, 2);
      debugPrint('🎯 closestAEDs for bounds: $closestAEDs');

      final bounds = getBoundsFromPoints([userLocation, ...closestAEDs]);
      debugPrint('📦 bounds: SW=${bounds.southwest}, NE=${bounds.northeast}');

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
      debugPrint('✅ animateCamera done');
    } finally {
      _isAnimating = false;
      await updateCameraPosition();
    }
  }

  Future<void> enableNavigationView(
      LatLng userLocation,
      double? heading,
      ) async {
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  userLocation,
          zoom:    MapUtils.navigationZoom,
          bearing: heading ?? 0,
          tilt:    AppConstants.navigationTilt,
        ),
      ),
    );
    await updateCameraPosition();
  }

  Future<void> showDefaultGreeceView() async {
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: AppConstants.greeceCenter,
          zoom:   MapUtils.greeceZoom,
        ),
      ),
    );
    await updateCameraPosition();
  }

  Future<void> updateCameraPosition() async {
    try {
      final visibleRegion = await controller.getVisibleRegion();
      final center = LatLng(
        (visibleRegion.northeast.latitude  + visibleRegion.southwest.latitude)  / 2,
        (visibleRegion.northeast.longitude + visibleRegion.southwest.longitude) / 2,
      );

      _lastCameraPosition = CameraPosition(
        target: center,
        zoom:   await controller.getZoomLevel(),
      );
    } catch (e) {
      debugPrint('Error updating camera position: $e');
    }
  }

  List<LatLng> getClosestAEDsToPoint(
      LatLng point, List<LatLng> aedLocations, int count) {
    if (aedLocations.isEmpty) return [];

    final locationDistances = aedLocations.map((loc) {
      return MapEntry(loc, LocationService.distanceBetween(point, loc));
    }).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return locationDistances.take(count).map((e) => e.key).toList();
  }

  Future<void> zoomToRouteWithEndpoints({
    required LatLng userLocation,
    required LatLng aedLocation,
    required List<LatLng> routePoints,
    required BuildContext context,
  }) async {
    if (_isAnimating) return;
    _isAnimating = true;

    try {
      final allPoints    = [...routePoints, userLocation, aedLocation];
      final bounds       = getBoundsFromPoints(allPoints);
      final bottomPadding = _calculateBottomPadding(context);

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50),
      );

      final currentZoom = await controller.getZoomLevel();
      final optimalZoom = _getOptimalZoom(bounds);

      if ((currentZoom - optimalZoom).abs() > 1) {
        await controller.animateCamera(CameraUpdate.zoomTo(optimalZoom));
      }

      final visibleRegion = await controller.getVisibleRegion();
      final currentBounds = LatLngBounds(
        southwest: visibleRegion.southwest,
        northeast: visibleRegion.northeast,
      );

      if (!currentBounds.contains(aedLocation) ||
          !currentBounds.contains(userLocation)) {
        await _adjustCenter(bounds, bottomPadding);
      }
    } finally {
      _isAnimating = false;
    }
  }

  Future<void> _adjustCenter(LatLngBounds bounds, double bottomPadding) async {
    final center = LatLng(
      (bounds.northeast.latitude  + bounds.southwest.latitude)  / 2,
      (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
    );

    final heightRatio = bottomPadding / (context.screenHeight - bottomPadding);

    final adjustedCenter = LatLng(
      center.latitude + (bounds.northeast.latitude - center.latitude) * heightRatio,
      center.longitude,
    );

    await controller.animateCamera(CameraUpdate.newLatLng(adjustedCenter));
  }

  /// Zoom to a single AED location when no user location is available.
  Future<void> zoomToAED(LatLng aedLocation) async {
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: aedLocation,
            zoom:   AppConstants.compassOnlyZoom,
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Error zooming to AED: $e');
    }
  }

  Future<void> zoomToUserAndAED({
    required LatLng userLocation,
    required LatLng aedLocation,
    required List<LatLng> polylinePoints,
    double padding            = AEDMapUIConstants.mapOverviewPadding,
    double ghostPaddingFactor = AEDMapUIConstants.mapGhostPaddingFactor,
  }) async {
    if (_isAnimating) return;
    _isAnimating = true;

    try {
      final allPoints = [userLocation, aedLocation, ...polylinePoints];

      final latitudes = allPoints.map((p) => p.latitude).toList();
      final minLat    = latitudes.reduce((a, b) => a < b ? a : b);
      final maxLat    = latitudes.reduce((a, b) => a > b ? a : b);
      final latDelta  = maxLat - minLat;

      final ghostPoint = LatLng(
        minLat - latDelta * ghostPaddingFactor,
        userLocation.longitude,
      );

      final bounds = getBoundsFromPoints([...allPoints, ghostPoint]);

      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    } finally {
      _isAnimating = false;
      await updateCameraPosition();
    }
  }

  LatLngBounds getBoundsFromPoints(List<LatLng> points) {
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);

    return LatLngBounds(
      southwest: LatLng(lats.reduce((a, b) => a < b ? a : b),
          lngs.reduce((a, b) => a < b ? a : b)),
      northeast: LatLng(lats.reduce((a, b) => a > b ? a : b),
          lngs.reduce((a, b) => a > b ? a : b)),
    );
  }

  Future<void> updateNavigationView({
    required LatLng userLocation,
    double? bearing,
    double? speed,
  }) async {
    if (_isAnimating) return;

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  userLocation,
          zoom:    _calculateAdaptiveZoom(speed ?? 0),
          bearing: bearing ?? _lastCameraPosition?.bearing ?? 0,
          tilt:    AppConstants.navigationTilt,
        ),
      ),
    );
  }

  double _calculateBottomPadding(BuildContext context) {
    return context.screenHeight * 0.35 + 20;
  }

  double _getOptimalZoom(LatLngBounds bounds) {
    final diagonalDistance = LocationService.distanceBetween(
      bounds.southwest,
      bounds.northeast,
    );

    if (diagonalDistance < 100)  return 18.0;
    if (diagonalDistance < 300)  return 17.0;
    if (diagonalDistance < 1000) return 16.0;
    if (diagonalDistance < 3000) return 14.0;
    return 12.0;
  }

  double _calculateAdaptiveZoom(double speedMetersPerSecond) {
    final speedKmh = speedMetersPerSecond * 3.6;
    return speedKmh < 5  ? AppConstants.navigationZoom :
    speedKmh < 20 ? 16.0 :
    15.0;
  }

  void dispose() {
    _isAnimating        = false;
    _lastCameraPosition = null;
  }
}


enum MapViewType {
  userAndClosestAEDs,
  routeAndEndpoints,
  specificLocation,
  navigationMode,
}

class MapViewRequest {
  final MapViewType    type;
  final LatLng?        userLocation;
  final List<LatLng>?  aedLocations;
  final List<LatLng>?  routePoints;
  final LatLng?        targetLocation;
  final double?        padding;
  final BuildContext   context;

  MapViewRequest.userAndClosestAEDs(
      this.userLocation,
      this.aedLocations, {
        this.padding,
        required this.context,
      })  : type         = MapViewType.userAndClosestAEDs,
        routePoints  = null,
        targetLocation = null;

  MapViewRequest.routeAndEndpoints({
    required this.userLocation,
    required this.targetLocation,
    required this.routePoints,
    this.padding,
    required this.context,
  })  : type         = MapViewType.routeAndEndpoints,
        aedLocations = null;

  MapViewRequest.specificLocation(
      this.targetLocation, {
        required this.context,
      })  : type          = MapViewType.specificLocation,
        userLocation  = null,
        aedLocations  = null,
        routePoints   = null,
        padding       = null;

  MapViewRequest.navigationMode({
    required this.userLocation,
    required LatLng destination,
    required List<LatLng> this.routePoints,
    this.padding,
    required this.context,
  })  : type           = MapViewType.navigationMode,
        targetLocation = destination,
        aedLocations   = [destination];
}