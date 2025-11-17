import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/app_constants.dart';
import 'location_service.dart';

class MapUtils {
  static const double navigationZoom = 18.5;
  static const double navigationTilt = 45.0;
  static const double overviewPadding = 60.0;
  static const double routePadding = 20.0;
  static const double rerouteThresholdMeters = 50.0;

  static const LatLng greeceCenter = LatLng(39.0742, 21.8243);
  static const double greeceZoom = 6.5;
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const double defaultZoom = 16.0;
  static const double maxZoom = 18.0;
}


class MapViewController {
  final GoogleMapController controller;
  final BuildContext context;
  bool _isAnimating = false;
  CameraPosition? _lastCameraPosition;

  MapViewController(this.controller, this.context);

  Future<void> zoomToUserAndClosestAEDs(
      LatLng userLocation,
      List<LatLng> aedLocations,
      {double padding = 60}
      ) async {
    if (_isAnimating) return;
    _isAnimating = true;

    try {
      if (aedLocations.isEmpty) {
        await controller.animateCamera(
            CameraUpdate.newLatLngZoom(userLocation, 15)
        );
        return;
      }

      final closestAEDs = getClosestAEDsToPoint(userLocation, aedLocations, 2);
      final bounds = getBoundsFromPoints([userLocation, ...closestAEDs]);
      await controller.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding)
      );
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
          target: userLocation,
          zoom: MapUtils.navigationZoom,
          bearing: heading ?? 0,
          tilt: MapUtils.navigationTilt,
        ),
      ),
    );
    await updateCameraPosition();
  }

  Future<void> showDefaultGreeceView() async {
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: MapUtils.greeceCenter,
          zoom: MapUtils.greeceZoom,
        ),
      ),
    );
    await updateCameraPosition();
  }

  Future<void> updateCameraPosition() async {
    try {
      final visibleRegion = await controller.getVisibleRegion();
      final center = LatLng(
        (visibleRegion.northeast.latitude + visibleRegion.southwest.latitude) / 2,
        (visibleRegion.northeast.longitude + visibleRegion.southwest.longitude) / 2,
      );

      _lastCameraPosition = CameraPosition(
        target: center,
        zoom: await controller.getZoomLevel(),
      );
    } catch (e) {
      print("Error updating camera position: $e");
    }
  }

  List<LatLng> getClosestAEDsToPoint(LatLng point, List<LatLng> aedLocations, int count) {
    if (aedLocations.isEmpty) return [];

    // Create a list of (location, distance) pairs
    final locationDistances = aedLocations.map((loc) {
      final distance = LocationService.distanceBetween(point, loc);
      return MapEntry(loc, distance);
    }).toList();

    // Sort by distance
    locationDistances.sort((a, b) => a.value.compareTo(b.value));

    return locationDistances
        .take(count)
        .map((entry) => entry.key)
        .toList();
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
      // 1. Combine all points we need to show
      final allPoints = [...routePoints, userLocation, aedLocation];
      final bounds = getBoundsFromPoints(allPoints);

      // 2. Calculate dynamic padding
      final bottomPadding = _calculateBottomPadding(context);

      // 3. Create camera update with proper padding
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50), // uniform padding
      );


      // 4. Adjust zoom if needed
      final currentZoom = await controller.getZoomLevel();
      final optimalZoom = _getOptimalZoom(bounds);

      if ((currentZoom - optimalZoom).abs() > 1) {
        await controller.animateCamera(
          CameraUpdate.zoomTo(optimalZoom),
        );
      }

      // 5. Optional: Slight center adjustment if needed
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
      (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
      (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
    );

    final heightRatio = bottomPadding /
        (MediaQuery.of(context).size.height - bottomPadding);

    final adjustedCenter = LatLng(
      center.latitude + (bounds.northeast.latitude - center.latitude) * heightRatio,
      center.longitude,
    );

    await controller.animateCamera(
      CameraUpdate.newLatLng(adjustedCenter),
    );
  }

  /// Zoom to a single AED location when no location is available
  Future<void> zoomToAED(LatLng aedLocation) async {
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: aedLocation,
            zoom: 15.0,
          ),
        ),
      );
    } catch (e) {
      print("⚠️ Error zooming to AED: $e");
    }
  }


  Future<void> zoomToUserAndAED({
    required LatLng userLocation,
    required LatLng aedLocation,
    required List<LatLng> polylinePoints,
    double padding = 30,
    double ghostPaddingFactor = 0.50,
  }) async {
    if (_isAnimating) return;
    _isAnimating = true;

    try {
      // 1. Combine all points: user, AED, polyline
      final allPoints = [userLocation, aedLocation, ...polylinePoints];

      // 2. Calculate vertical span
      final latitudes = allPoints.map((p) => p.latitude).toList();
      final minLat = latitudes.reduce((a, b) => a < b ? a : b);
      final maxLat = latitudes.reduce((a, b) => a > b ? a : b);
      final latDelta = maxLat - minLat;

      // 3. Add ghost point below lowest visible point
      final ghostPoint = LatLng(minLat - latDelta * ghostPaddingFactor, userLocation.longitude);

      // 4. Compute bounds including all relevant points + ghost
      final bounds = getBoundsFromPoints([...allPoints, ghostPoint]);

      // 5. Animate
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    } finally {
      _isAnimating = false;
      await updateCameraPosition();
    }
  }

  LatLngBounds getBoundsFromPoints(List<LatLng> points) {
    final minLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }


  Future<void> updateNavigationView({
    required LatLng userLocation,
    double? bearing,
    double? speed,
  }) async {
    if (_isAnimating) return;

    final zoom = _calculateAdaptiveZoom(speed ?? 0);

    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: userLocation,
          zoom: zoom,
          bearing: bearing ?? _lastCameraPosition?.bearing ?? 0,
          tilt: MapUtils.navigationTilt,
        ),
      ),
    );
  }

  double _calculateBottomPadding(BuildContext context) {
    // 35% of screen height for navigation sheet + 20px margin
    return MediaQuery.of(context).size.height * 0.35 + 20;
  }

  double _getOptimalZoom(LatLngBounds bounds) {
    // Calculate diagonal distance in meters
    final diagonalDistance = LocationService.distanceBetween(
      bounds.southwest,
      bounds.northeast,
    );

    // Return zoom level based on distance
    if (diagonalDistance < 100) return 18.0;
    if (diagonalDistance < 300) return 17.0;
    if (diagonalDistance < 1000) return 16.0;
    if (diagonalDistance < 3000) return 14.0;
    return 12.0;
  }

  double _calculateAdaptiveZoom(double speedMetersPerSecond) {
    final speedKmh = speedMetersPerSecond * 3.6;
    return speedKmh < 5 ? AppConstants.navigationZoom :
    speedKmh < 20 ? 16.0 :
    15.0;
  }

  void dispose() {
    _isAnimating = false;
    _lastCameraPosition = null;
  }
}

class CompassCameraController {
  GoogleMapController? _mapController;
  StreamSubscription<CompassEvent>? _compassSubscription;
  LatLng? _userLocation;
  bool _shouldFollow = true;
  bool _isUserControlling = false;
  bool _hasStartedNavigation = false;

  VoidCallback? _setCompassMovementFlag;

  void initialize(GoogleMapController mapController, {VoidCallback? setCompassMovementFlag}) {
    _mapController = mapController;
    _setCompassMovementFlag = setCompassMovementFlag;
  }


  void updateState({
    LatLng? userLocation,
    bool? shouldFollow,
    bool? isUserControlling,
    bool? hasStartedNavigation,
  }) {
    if (userLocation != null) _userLocation = userLocation;
    if (shouldFollow != null) _shouldFollow = shouldFollow;
    if (isUserControlling != null) _isUserControlling = isUserControlling;
    if (hasStartedNavigation != null) _hasStartedNavigation = hasStartedNavigation;
  }

  void dispose() {
    _compassSubscription?.cancel();
  }
}


enum MapViewType {
  userAndClosestAEDs,
  routeAndEndpoints,
  specificLocation,
  navigationMode,
}

class MapViewRequest {
  final MapViewType type;
  final LatLng? userLocation;
  final List<LatLng>? aedLocations;
  final List<LatLng>? routePoints;
  final LatLng? targetLocation;
  final double? padding;
  final BuildContext context; // Make this required


  MapViewRequest.userAndClosestAEDs(this.userLocation, this.aedLocations,
      {this.padding, required this.context})
      : type = MapViewType.userAndClosestAEDs,
        routePoints = null,
        targetLocation = null;

  MapViewRequest.routeAndEndpoints({
    required this.userLocation,
    required this.targetLocation,
    required this.routePoints,
    this.padding,
    required this.context,
  })  : type = MapViewType.routeAndEndpoints,
        aedLocations = null;


  MapViewRequest.specificLocation(this.targetLocation, {required this.context})
      : type = MapViewType.specificLocation,
        userLocation = null,
        aedLocations = null,
        routePoints = null,
        padding = null;


  MapViewRequest.navigationMode({
    required this.userLocation,
    required LatLng destination,
    required List<LatLng> routePoints,
    this.padding,
    required this.context,
  }) : type = MapViewType.navigationMode,
        targetLocation = destination,
        aedLocations = [destination],
        routePoints = routePoints;
}