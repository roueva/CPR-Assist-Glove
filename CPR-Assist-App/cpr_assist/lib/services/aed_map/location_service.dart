import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;

import '../../utils/app_constants.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _improvementTimer;
  static StreamController<bool>? _locationServiceController;
  static Timer? _locationServiceTimer;
  static StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

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
      // Step 1: Trigger the NATIVE OS dialog to enable location services
      // This is the Google Maps-style popup, not the Settings app
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        final locService = loc.Location();
        final enabled = await locService.requestService();
        // If user said no, bail out
        if (!enabled) return false;
        // Small delay for the OS to register the change
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Step 2: Check and request app-level permission
      final currentPermission = await Geolocator.checkPermission();

      if (currentPermission == LocationPermission.whileInUse ||
          currentPermission == LocationPermission.always) {
        return true;
      }

      if (currentPermission == LocationPermission.deniedForever) {
        if (showSettingsDialog && context.mounted) {
          return await _showPermissionSettingsDialog(context);
        }
        return false;
      }

      if (currentPermission == LocationPermission.denied) {
        final status = await Geolocator.requestPermission();
        return status == LocationPermission.whileInUse ||
            status == LocationPermission.always;
      }

      return false;
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
    if (_serviceStatusSubscription != null) return;
    _locationServiceController ??= StreamController<bool>.broadcast();

    _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen(
          (ServiceStatus status) {
        _locationServiceController?.add(status == ServiceStatus.enabled);
      },
    );
  }

  static Stream<bool>? get locationServiceStream => _locationServiceController?.stream;


  static void stopLocationServiceMonitoring() {
    _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = null;
    _locationServiceTimer?.cancel();
    _locationServiceController?.close();
    _locationServiceController = null;
  }

  Future<LatLng?> getCurrentLocationWithUI({
    required BuildContext context,
    bool showPermissionDialog = true,
    bool showErrorMessages = true,
    bool useTimeout = false,
  }) async {
    try {
      if (showPermissionDialog) {
        final hasPermissions = await handlePermissionWithDialog(
          context: context,
          showSettingsDialog: true,
        );
        if (!hasPermissions) return null;
      }

      // No services check here — let Android show the system dialog naturally
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
    Duration? timeLimit = const Duration(seconds: 30),
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
  Future<void> startProgressiveLocationTracking({
    required Function(LatLng) onLocationUpdate,
    required bool isNavigating,
    int distanceFilter = 10,
  }) async {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    // Check services are actually enabled before starting stream
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      print("⚠️ Location services disabled — not starting GPS stream");
      return;
    }

    print("🔍 GPS Phase 1: Low accuracy (quick start)");

    // ✅ Add flag to prevent multiple upgrades
    bool hasUpgraded = false;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        distanceFilter: 0,    // ← emit first position immediately
      ),
    ).listen((position) {
      onLocationUpdate(LatLng(position.latitude, position.longitude));
    });

    _improvementTimer = Timer(const Duration(seconds: 30), () {
      if (!hasUpgraded) {
        hasUpgraded = true;
        print("⏱️ GPS Phase 1 timeout — upgrading anyway");
        _upgradeToTargetAccuracy(
          onLocationUpdate: onLocationUpdate,
          isNavigating: isNavigating,
          distanceFilter: distanceFilter,
        );
      }
    });
  }

  /// Upgrade to target accuracy based on usage mode
  void _upgradeToTargetAccuracy({
    required Function(LatLng) onLocationUpdate,
    required bool isNavigating,
    required int distanceFilter,
  }) async {
    _positionSubscription?.cancel();

    if (!await Geolocator.isLocationServiceEnabled()) {
      print("🔴 Location services disabled - cannot upgrade accuracy");
      return;
    }

    final accuracy = isNavigating ? LocationAccuracy.high : LocationAccuracy.medium;

    print("📍 GPS Phase 2: ${isNavigating ? 'HIGH' : 'MEDIUM'} accuracy");

    if (isNavigating) {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen(
            (position) {
          onLocationUpdate(LatLng(position.latitude, position.longitude));
        },
        onError: (error) {
          print("❌ Location stream error: $error");
          // Stop if services disabled
          if (error.toString().contains('location')) {
            stopLocationMonitoring();
          }
        },
      );
    } else {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: distanceFilter,
        ),
      ).listen(
            (position) {
          onLocationUpdate(LatLng(position.latitude, position.longitude));
        },
        onError: (error) {
          print("❌ Location stream error: $error");
          if (error.toString().contains('location')) {
            stopLocationMonitoring();
          }
        },
      );
    }
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
    required bool isNavigating,
  }) {
    // ✅ Cancel existing timer properly
    stopBackgroundImprovement();

    if (isNavigating) {
      print("⏸️ Skipping background improvement (already HIGH accuracy)");
      return;
    }

    print("🔍 Starting background location improvement");
    int improvementAttempts = 0;

    _improvementTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      improvementAttempts++;

      if (!await Geolocator.isLocationServiceEnabled()) {
        print("🔴 Location services disabled - stopping background improvement");
        stopBackgroundImprovement(); // ✅ Use helper method
        return;
      }

      if (improvementAttempts > 5) {
        print("✅ Background improvement complete (max attempts)");
        stopBackgroundImprovement(); // ✅ Use helper method
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

        if (improvement > 50 || (betterPosition.accuracy < 15 && improvement > 20)) {
          print("✅ Improvement: ${improvement.round()}m, accuracy: ${betterPosition.accuracy}m");
          onImprovedLocation(betterLocation);
        }

        // Stop if excellent accuracy achieved
        if (betterPosition.accuracy < 15) {
          print("✅ Excellent accuracy (${betterPosition.accuracy}m) - stopping");
          stopBackgroundImprovement(); // ✅ Use helper method
          return;
        }
      } catch (e) {
        print("⚠️ Improvement attempt $improvementAttempts failed: $e");

        if (e.toString().toLowerCase().contains('location') ||
            e.toString().toLowerCase().contains('service')) {
          print("🔴 Location service error detected - stopping improvements");
          stopBackgroundImprovement(); // ✅ Use helper method
          return;
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
}


/// Manages GPS stream lifecycle and coordinates location updates
class GPSController {
  final LocationService _locationService;
  final Function(LatLng) onLocationUpdate;

  bool _isActive = false;
  bool _isNavigating = false;

  GPSController(this._locationService, {required this.onLocationUpdate});

  /// Starts GPS stream with appropriate settings
  Future<void> start({required bool isNavigating}) async {
    if (_isActive) {
      await stop();
    }

    _isNavigating = isNavigating;
    _isActive = true;

    await Future.delayed(const Duration(milliseconds: 200));

    print("🎯 Starting GPS...");

    await _locationService.startProgressiveLocationTracking( // ADD await
      onLocationUpdate: onLocationUpdate,
      isNavigating: isNavigating,
      distanceFilter: isNavigating ? 0 : 10,
    );
  }

  Future<void> stop() async {
    if (!_isActive) return;

    print("🛑 Stopping GPS stream");
    _isActive = false;

    // ✅ Let LocationService handle cleanup
    _locationService.stopLocationMonitoring();
    print("✅ GPS stream stopped");
  }


  bool get isActive => _isActive;
  bool get isNavigating => _isNavigating;

  void dispose() {
    stop(); // ✅ Use stop() instead of managing subscription
    _isActive = false;
  }
}