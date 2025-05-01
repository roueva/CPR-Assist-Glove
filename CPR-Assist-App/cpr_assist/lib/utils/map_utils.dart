import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// -- MapViewController --
class MapViewController {
  final GoogleMapController controller;
  bool _isAnimating = false;
  CameraPosition? _lastCameraPosition;

  MapViewController(this.controller);

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

  Future<void> enableNavigationMode(
      LatLng userLocation,
      double? heading,
      ) async {
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: userLocation,
          zoom: 17,
          bearing: heading ?? 0,
          tilt: 45,
        ),
      ),
    );
    await updateCameraPosition();
  }

  Future<void> showDefaultGreeceView() async {
    await controller.animateCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(
          target: LatLng(39.0742, 21.8243),
          zoom: 6.5,
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
      // Add this to store the position:
      _lastCameraPosition = CameraPosition(
        target: center,
        zoom: await controller.getZoomLevel(),
      );
    } catch (e) {
      print("Error updating camera position: $e");
      rethrow;
    }
  }

// Implementation for navigation mode in MapViewController
  Future<void> updateMapView(MapViewRequest request) async {
    if (_isAnimating) return;
    _isAnimating = true;

    try {
      switch (request.type) {
        case MapViewType.userAndClosestAEDs:
          await _zoomToUserAndClosestAEDs(
            request.userLocation!,
            request.aedLocations!,
            request.padding ?? 60,
          );
          break;
        case MapViewType.routeAndEndpoints:
          await _zoomToRouteAndEndpoints(
            request.routePoints!,
            request.padding ?? 20,
          );
          break;
        case MapViewType.specificLocation:
          await controller.animateCamera(
            CameraUpdate.newLatLngZoom(request.targetLocation!, 15),
          );
          break;
        case MapViewType.navigationMode:
        // Implement navigation mode camera update
          final tilt = 45.0;
          final zoom = 17.0;

          await controller.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: request.userLocation!,
                zoom: zoom,
                tilt: tilt,
                // If heading is provided, use it
                bearing: 0, // Default bearing - ideally from compass
              ),
            ),
          );
          break;
      }
    } finally {
      _isAnimating = false;
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


  Future<void> _zoomToUserAndClosestAEDs(
      LatLng userLocation, List<LatLng> aedLocations, double padding) async {
    final bounds = getBoundsFromPoints([userLocation, ...aedLocations]);
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
  }

  Future<void> _zoomToRouteAndEndpoints(List<LatLng> routePoints, double padding) async {
    final bounds = getBoundsFromPoints(routePoints);
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
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

  MapViewRequest.userAndClosestAEDs(this.userLocation, this.aedLocations, {this.padding})
      : type = MapViewType.userAndClosestAEDs,
        routePoints = null,
        targetLocation = null;

  MapViewRequest.routeAndEndpoints(this.routePoints, {this.padding})
      : type = MapViewType.routeAndEndpoints,
        userLocation = null,
        aedLocations = null,
        targetLocation = null;

  MapViewRequest.specificLocation(this.targetLocation)
      : type = MapViewType.specificLocation,
        userLocation = null,
        aedLocations = null,
        routePoints = null,
        padding = null;


  MapViewRequest.navigationMode({
    required this.userLocation,
    required LatLng destination,
    required List<LatLng> routePoints,
    this.padding
  }) : type = MapViewType.navigationMode,
        targetLocation = destination,
        aedLocations = [destination],
        routePoints = routePoints;
}

// -- PolylineUtils --
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

class LocationService {
  // Singleton pattern remains the same
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // --- Permission Handling --- (keep these as instance methods)
  Future<bool> get hasPermission async {
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  Future<bool> requestPermission() async {
    final status = await Geolocator.requestPermission();
    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  Future<bool> ensureLocationPermission() async {
    if (await hasPermission) return true;
    return await requestPermission();
  }

  // --- Position Fetching --- (keep these as instance methods)
  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );
    } catch (e) {
      print("Location error: $e");
      return null;
    }
  }

  Future<LatLng?> getCurrentLatLng() async {
    try {
      if (!await hasPermission && !await requestPermission()) {
        return null;
      }
      final position = await getCurrentPosition();
      return position != null
          ? LatLng(position.latitude, position.longitude)
          : null;
    } catch (e) {
      print("Error getting current location: $e");
      return null;
    }
  }

  StreamSubscription<Position> listenToPositionUpdates(
      void Function(LatLng) onUpdate, {
        int distanceFilter = 10,
      }) {
    return getPositionStream(distanceFilter: distanceFilter).listen((position) {
      onUpdate(LatLng(position.latitude, position.longitude));
    });
  }

  Stream<Position> getPositionStream({int distanceFilter = 10}) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: distanceFilter,
      ),
    );
  }

  // --- Convert all these to static methods ---
  static double distanceBetween(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude, a.longitude,
      b.latitude, b.longitude,
    );
  }

  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters/1000).toStringAsFixed(1)} km';
  }

  static String estimateTravelTime(double meters, String mode) {
    final speed = mode == 'walking' ? 1.4 : 10.0; // m/s
    final seconds = meters / speed;

    if (seconds < 60) return "< 1 min";
    if (seconds < 3600) return "${(seconds / 60).ceil()} min";

    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).ceil();
    return "$hours h $minutes min";
  }
}