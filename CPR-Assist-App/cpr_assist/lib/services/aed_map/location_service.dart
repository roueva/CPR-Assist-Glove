import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../utils/app_constants.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _improvementTimer;
  static StreamController<bool>? _locationServiceController;
  static Timer? _locationServiceTimer;

  Future<bool> get hasPermission async {
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  Future<bool> requestPermission() async {
    try {
      final currentStatus = await Geolocator.checkPermission();

      // If already granted, return true immediately
      if (currentStatus == LocationPermission.whileInUse ||
          currentStatus == LocationPermission.always) {
        return true;
      }

      // If denied forever, can't request again
      if (currentStatus == LocationPermission.deniedForever) {
        print("Location permission denied forever");
        return false;
      }

      // Only request once if currently denied
      if (currentStatus == LocationPermission.denied) {
        final status = await Geolocator.requestPermission();
        final granted = status == LocationPermission.whileInUse || status == LocationPermission.always;
        return granted;
      }

      return false;
    } catch (e) {
      print("Error requesting location permission: $e");
      return false;
    }
  }

  Future<bool> handlePermissionWithDialog({
    required BuildContext context,
    bool showSettingsDialog = true,
  }) async {
    try {
      // Just request permission - this handles location services AND app permissions
      final granted = await requestPermission();

      if (!granted) {
        // Check if it's permanently denied
        final currentPermission = await Geolocator.checkPermission();
        if (currentPermission == LocationPermission.deniedForever && showSettingsDialog && context.mounted) {
          return await _showPermissionSettingsDialog(context);
        }
      }

      return granted;
    } catch (e) {
      print("❌ Exception in permission handling: $e");
      if (context.mounted) {
        _showGenericErrorSnackBar(context);
      }
      return false;
    }
  }


  Future<bool> _showPermissionSettingsDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
            'Location access has been permanently denied. To use location features, please enable location permissions in your device settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop(true);
                await Geolocator.openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showGenericErrorSnackBar(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to get current location. Please try again.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  static void startLocationServiceMonitoring() {
    _locationServiceController ??= StreamController<bool>.broadcast();

    _locationServiceTimer?.cancel();
    _locationServiceTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final isEnabled = await Geolocator.isLocationServiceEnabled();
        _locationServiceController?.add(isEnabled);
      } catch (e) {
        print("Error checking location service: $e");
      }
    });
  }

  static Stream<bool>? get locationServiceStream => _locationServiceController?.stream;


  static void stopLocationServiceMonitoring() {
    _locationServiceTimer?.cancel();
    _locationServiceController?.close();
    _locationServiceController = null;
  }

  Future<LatLng?> getCurrentLocationWithUI({
    required BuildContext context,
    bool showPermissionDialog = true,
    bool showErrorMessages = true,
    bool useTimeout = false, // NEW: Allow disabling timeout
  }) async {
    try {
      if (showPermissionDialog) {
        final hasPermissions = await handlePermissionWithDialog(
          context: context,
          showSettingsDialog: true,
        );

        if (!hasPermissions) {
          return null;
        }
      }

      // Get current position without timeout for initial acquisition
      final position = await getCurrentPosition(
        timeLimit: useTimeout ? const Duration(seconds: 10) : null,
      );
      if (position == null) {
        if (showErrorMessages && context.mounted) {
          _showGenericErrorSnackBar(context);
        }
        return null;
      }

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      print("❌ Exception in getCurrentLocationWithUI: $e");
      if (showErrorMessages && context.mounted) {
        _showGenericErrorSnackBar(context);
      }
      return null;
    }
  }


  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration? timeLimit = const Duration(minutes: 10),
  }) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: timeLimit,
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

  Stream<Position> getPositionStream({
    int distanceFilter = 10,
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }
  /// Progressive location tracking with accuracy that adapts to usage
  void startProgressiveLocationTracking({
    required Function(LatLng) onLocationUpdate,
    required bool isNavigating,
    int distanceFilter = 10,
  }) {
    _positionSubscription?.cancel();

    // PHASE 1: Quick start with LOW accuracy (instant ~200ms)
    print("🔍 GPS Phase 1: Low accuracy (quick start)");

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 50, // Relaxed for quick fix
      ),
    ).listen((position) {
      onLocationUpdate(LatLng(position.latitude, position.longitude));

      // PHASE 2: Upgrade after first fix (based on mode)
      Future.delayed(const Duration(seconds: 1), () {
        _upgradeToTargetAccuracy(
          onLocationUpdate: onLocationUpdate,
          isNavigating: isNavigating,
          distanceFilter: distanceFilter,
        );
      });
    });
  }

  /// Upgrade to target accuracy based on usage mode
  void _upgradeToTargetAccuracy({
    required Function(LatLng) onLocationUpdate,
    required bool isNavigating,
    required int distanceFilter,
  }) {
    _positionSubscription?.cancel();

    final accuracy = isNavigating ? LocationAccuracy.high : LocationAccuracy.medium;
    final filter = distanceFilter;  // ✅ ALWAYS use the passed parameter

    print("📍 GPS Phase 2: ${isNavigating ? 'HIGH' : 'MEDIUM'} accuracy, ${filter}m filter");

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: filter,  // ✅ Use actual parameter
      ),
    ).listen((position) {
      onLocationUpdate(LatLng(position.latitude, position.longitude));
    });
  }

  /// Update accuracy when navigation mode changes
  void updateAccuracyForNavigation(bool isNavigating, Function(LatLng) onLocationUpdate) {
    if (_positionSubscription == null) return;

    print("🔄 Updating GPS accuracy for ${isNavigating ? 'NAVIGATION' : 'NORMAL'} mode");

    _upgradeToTargetAccuracy(
      onLocationUpdate: onLocationUpdate,
      isNavigating: isNavigating,
      distanceFilter: isNavigating ? 5 : 10,
    );
  }

  void startBackgroundLocationImprovement({
    required LatLng currentLocation,
    required Function(LatLng) onImprovedLocation,
    required bool isNavigating, // ✅ NEW: Know if we should stop
    }) {
    _improvementTimer?.cancel();

    // Don't run improvements during navigation (already at HIGH accuracy)
    if (isNavigating) {
      print("⏸️ Skipping background improvement (already HIGH accuracy)");
      return;
    }

    int improvementAttempts = 0;
    _improvementTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      improvementAttempts++;

      // ✅ ADD THIS: Check if location services still enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        print("🔴 Location services disabled - stopping background improvement");
        timer.cancel();
        _improvementTimer = null;
        return;
      }

      // Stop after 5 attempts OR if services disabled
      if (improvementAttempts > 5) {
        print("✅ Background improvement complete (max attempts)");
        timer.cancel();
        _improvementTimer = null;
        return;
      }

      // ✅ CRITICAL: Check if location services still enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        print("🔴 Location services disabled - stopping background improvement");
        timer.cancel();
        return;
      }

      try {
        final betterPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        ).timeout(const Duration(seconds: 10));

        final betterLocation = LatLng(betterPosition.latitude, betterPosition.longitude);
        final improvement = distanceBetween(currentLocation, betterLocation);

        // Only notify if significantly better
        if (improvement > 50 || (betterPosition.accuracy < 15 && improvement > 20)) {
          print("✅ Improvement: ${improvement.round()}m, accuracy: ${betterPosition.accuracy}m");
          onImprovedLocation(betterLocation);
        }

        // Stop if excellent accuracy achieved
        if (betterPosition.accuracy < 15) {
          print("✅ Excellent accuracy (${betterPosition.accuracy}m) - stopping");
          timer.cancel();
        }
      } catch (e) {
        print("⚠️ Improvement attempt $improvementAttempts failed: $e");

        // Stop if location services issue detected
        if (e.toString().toLowerCase().contains('location')) {
          timer.cancel();
        }
      }
    });
  }

  /// ✅ ADD: Method to stop background improvements
  void stopBackgroundImprovement() {
    _improvementTimer?.cancel();
    _improvementTimer = null;
    print("🛑 Stopped background location improvement");
  }

  void stopLocationMonitoring() {
    _positionSubscription?.cancel();
    _improvementTimer?.cancel();
    _positionSubscription = null;
    _improvementTimer = null;
  }

  void dispose() {
    stopLocationMonitoring();
    stopBackgroundImprovement();
  }




  static String shortenAddress(String fullAddress) {
    final parts = fullAddress.split(',');
    return parts.isNotEmpty ? parts.first.trim() : fullAddress;
  }


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

  static String calculateOfflineETA(double distanceInMeters, String transportMode) {
    final distanceInKm = distanceInMeters / 1000;
    double speedKmh;

    switch (transportMode) {
      case 'walking':
        speedKmh = AppConstants.walkingSpeed;
        break;
      case 'bicycling':
        speedKmh = AppConstants.bicyclingSpeed;
        break;
      case 'driving':
        speedKmh = AppConstants.drivingSpeed;
        break;
      default:
        speedKmh = 5.0;
    }

    final timeInHours = distanceInKm / speedKmh;
    final timeInMinutes = (timeInHours * 60).round();

    if (timeInMinutes < 60) {
      return "${timeInMinutes}min";
    } else {
      final hours = timeInMinutes ~/ 60;
      final minutes = timeInMinutes % 60;
      return "${hours}h ${minutes}min";
    }
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