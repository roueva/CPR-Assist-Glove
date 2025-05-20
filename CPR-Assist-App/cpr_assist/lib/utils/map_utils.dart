      import 'dart:async';
    import 'package:flutter/material.dart';
      import 'package:google_maps_flutter/google_maps_flutter.dart';
      import 'package:geolocator/geolocator.dart';

      class MapUtils {
        static const double navigationZoom = 17.0;
        static const double navigationTilt = 45.0;
        static const double overviewPadding = 60.0;
        static const double routePadding = 20.0;
        static const double rerouteThresholdMeters = 50.0;
      }

      // --- Transport Mode Helpers ---
      enum TransportMode { walking, driving, bicycling }

      extension TransportModeUtils on TransportMode {
        IconData get icon {
          switch (this) {
            case TransportMode.walking:
              return Icons.directions_walk;
            case TransportMode.driving:
              return Icons.directions_car;
            case TransportMode.bicycling:
              return Icons.directions_bike;
          }
        }

        String get label {
          switch (this) {
            case TransportMode.walking:
              return "Walking";
            case TransportMode.driving:
              return "Driving";
            case TransportMode.bicycling:
              return "Bicycling";
          }
        }

        static TransportMode fromString(String mode) {
          switch (mode) {
            case 'driving':
              return TransportMode.driving;
            case 'bicycling':
              return TransportMode.bicycling;
            case 'walking':
            default:
              return TransportMode.walking;
          }
        }
      }

      // -- MapViewController --
      class MapViewController {
        final GoogleMapController controller;
        final BuildContext context; // Add this
        bool _isAnimating = false;
        CameraPosition? _lastCameraPosition;

        MapViewController(this.controller, this.context); // Update constructor

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
                await zoomToUserAndClosestAEDs(
                  request.userLocation!,
                  request.aedLocations!,
                  padding: request.padding ?? 60,
                );
                break;
              case MapViewType.routeAndEndpoints:
                await zoomToRouteWithEndpoints(
                  userLocation: request.userLocation!,
                  aedLocation: request.targetLocation!,
                  routePoints: request.routePoints!,
                  context: request.context, // Use request context or fallback
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

        Future<void> enterNavigationMode({
          required LatLng userLocation,
          required LatLng destination,
          required List<LatLng> routePoints,
          required BuildContext context,
          double? initialBearing,
        }) async {
          if (_isAnimating) return;
          _isAnimating = true;

          try {
            // 1. Show entire route first
            await zoomToRouteWithEndpoints(
              userLocation: userLocation,
              aedLocation: destination,
              routePoints: routePoints,
              context: context,
            );

            // 2. Then zoom into navigation view
            await Future.delayed(const Duration(milliseconds: 300));

            await controller.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: userLocation,
                  zoom: _calculateAdaptiveZoom(0), // Start with walking speed
                  bearing: initialBearing ?? 0,
                  tilt: MapUtils.navigationTilt,
                ),
              ),
            );
          } finally {
            _isAnimating = false;
          }
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
          return speedKmh < 5 ? 17.0 :
          speedKmh < 20 ? 16.0 :
          15.0;
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

        static String shortenAddress(String fullAddress) {
          final parts = fullAddress.split(',');
          return parts.isNotEmpty ? parts.first.trim() : fullAddress;
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