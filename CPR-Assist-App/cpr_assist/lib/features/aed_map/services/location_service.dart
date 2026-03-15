import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;

import '../../../core/core.dart';

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

      if (currentStatus == LocationPermission.whileInUse ||
          currentStatus == LocationPermission.always) {
        return true;
      }

      if (currentStatus == LocationPermission.deniedForever) {
        debugPrint('Location permission denied forever');
        return false;
      }

      if (currentStatus == LocationPermission.denied) {
        final status = await Geolocator.requestPermission();
        return status == LocationPermission.whileInUse ||
            status == LocationPermission.always;
      }

      return false;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return false;
    }
  }

  Future<bool> handlePermissionWithDialog({
    required BuildContext context,
    bool showSettingsDialog = true,
  }) async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        final locService = loc.Location();
        final enabled = await locService.requestService();
        if (!enabled) return false;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final currentPermission = await Geolocator.checkPermission();

      if (currentPermission == LocationPermission.whileInUse ||
          currentPermission == LocationPermission.always) {
        return true;
      }

      if (currentPermission == LocationPermission.deniedForever) {
        if (showSettingsDialog && context.mounted) {
          return _showPermissionSettingsDialog(context);
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
      debugPrint('❌ Exception in permission handling: $e');
      if (context.mounted) _showGenericErrorSnackBar(context);
      return false;
    }
  }

  Future<bool> _showPermissionSettingsDialog(BuildContext context) async {
    final result = await AppDialogs.showLocationPermissionSettings(context);
    if (result == true) {
      await Geolocator.openAppSettings();
      return true;
    }
    return false;
  }

  void _showGenericErrorSnackBar(BuildContext context) {
    if (!context.mounted) return;
    UIHelper.showError(context, 'Unable to get current location. Please try again.');
  }

  static void startLocationServiceMonitoring() {
    if (_serviceStatusSubscription != null) return;
    _locationServiceController ??= StreamController<bool>.broadcast();

    _serviceStatusSubscription =
        Geolocator.getServiceStatusStream().listen((ServiceStatus status) {
          _locationServiceController?.add(status == ServiceStatus.enabled);
        });
  }

  static Stream<bool>? get locationServiceStream =>
      _locationServiceController?.stream;

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
    bool showErrorMessages    = true,
    bool useTimeout           = false,
  }) async {
    try {
      if (showPermissionDialog) {
        final hasPermissions = await handlePermissionWithDialog(
          context: context,
          showSettingsDialog: true,
        );
        if (!hasPermissions) return null;
      }

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
      debugPrint('❌ Exception in getCurrentLocationWithUI: $e');
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
          accuracy:  accuracy,
          timeLimit: timeLimit,
        ),
      );
    } catch (e) {
      debugPrint('Location error: $e');
      return null;
    }
  }

  Future<LatLng?> getCurrentLatLng() async {
    try {
      if (!await hasPermission && !await requestPermission()) return null;
      final position = await getCurrentPosition();
      return position != null
          ? LatLng(position.latitude, position.longitude)
          : null;
    } catch (e) {
      debugPrint('Error getting current location: $e');
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
    int distanceFilter            = 10,
    LocationAccuracy accuracy = LocationAccuracy.medium,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy:       accuracy,
        distanceFilter: distanceFilter,
      ),
    );
  }

  /// Progressive location tracking — starts low accuracy then upgrades.
  Future<void> startProgressiveLocationTracking({
    required void Function(LatLng) onLocationUpdate,
    required bool isNavigating,
    int distanceFilter = 10,
  }) async {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      debugPrint('⚠️ Location services disabled — not starting GPS stream');
      return;
    }

    debugPrint('🔍 GPS Phase 1: Low accuracy (quick start)');

    bool hasUpgraded = false;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy:       LocationAccuracy.low,
        distanceFilter: 5,
      ),
    ).listen((position) {
      onLocationUpdate(LatLng(position.latitude, position.longitude));
    });

    _improvementTimer = Timer(AppConstants.locationSettleTime, () {
      if (!hasUpgraded) {
        hasUpgraded = true;
        debugPrint('⏱️ GPS Phase 1 timeout — upgrading anyway');
        _upgradeToTargetAccuracy(
          onLocationUpdate: onLocationUpdate,
          isNavigating:     isNavigating,
          distanceFilter:   distanceFilter,
        );
      }
    });
  }

  void _upgradeToTargetAccuracy({
    required void Function(LatLng) onLocationUpdate,
    required bool isNavigating,
    required int distanceFilter,
  }) async {
    _positionSubscription?.cancel();

    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('🔴 Location services disabled - cannot upgrade accuracy');
      return;
    }

    final accuracy = isNavigating ? LocationAccuracy.high : LocationAccuracy.medium;
    debugPrint('📍 GPS Phase 2: ${isNavigating ? 'HIGH' : 'MEDIUM'} accuracy');

    if (isNavigating) {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy:       LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
        ),
      ).listen(
            (position) => onLocationUpdate(LatLng(position.latitude, position.longitude)),
        onError: (Object error) {
          debugPrint('❌ Location stream error: $error');
          if (error.toString().contains('location')) stopLocationMonitoring();
        },
      );
    } else {
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy:       accuracy,
          distanceFilter: distanceFilter,
        ),
      ).listen(
            (position) => onLocationUpdate(LatLng(position.latitude, position.longitude)),
        onError: (Object error) {
          debugPrint('❌ Location stream error: $error');
          if (error.toString().contains('location')) stopLocationMonitoring();
        },
      );
    }
  }

  void updateAccuracyForNavigation(
      bool isNavigating, void Function(LatLng) onLocationUpdate) {
    if (_positionSubscription == null) return;
    debugPrint('🔄 Updating GPS accuracy for ${isNavigating ? 'NAVIGATION' : 'NORMAL'} mode');
    _upgradeToTargetAccuracy(
      onLocationUpdate: onLocationUpdate,
      isNavigating:     isNavigating,
      distanceFilter:   isNavigating ? AppConstants.locationFilterHigh : AppConstants.locationFilterMedium,
    );
  }

  void startBackgroundLocationImprovement({
    required LatLng currentLocation,
    required void Function(LatLng) onImprovedLocation,
    required bool isNavigating,
  }) {
    stopBackgroundImprovement();

    if (isNavigating) {
      debugPrint('⏸️ Skipping background improvement (already HIGH accuracy)');
      return;
    }

    debugPrint('🔍 Starting background location improvement');
    int improvementAttempts = 0;

    _improvementTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      improvementAttempts++;

      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('🔴 Location services disabled - stopping background improvement');
        stopBackgroundImprovement();
        return;
      }

      if (improvementAttempts > AppConstants.maxImprovementAttempts) {
        debugPrint('✅ Background improvement complete (max attempts)');
        stopBackgroundImprovement();
        return;
      }

      try {
        final betterPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy:  LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        ).timeout(AppConstants.improvementTimeout);

        final betterLocation = LatLng(betterPosition.latitude, betterPosition.longitude);
        final improvement    = distanceBetween(currentLocation, betterLocation);

        if (improvement > AppConstants.significantImprovement ||
            (betterPosition.accuracy < AppConstants.excellentAccuracy &&
                improvement > AppConstants.locationMinMovement)) {
          debugPrint('✅ Improvement: ${improvement.round()}m, accuracy: ${betterPosition.accuracy}m');
          onImprovedLocation(betterLocation);
        }

        if (betterPosition.accuracy < AppConstants.excellentAccuracy) {
          debugPrint('✅ Excellent accuracy (${betterPosition.accuracy}m) - stopping');
          stopBackgroundImprovement();
        }
      } catch (e) {
        debugPrint('⚠️ Improvement attempt $improvementAttempts failed: $e');
        if (e.toString().toLowerCase().contains('location') ||
            e.toString().toLowerCase().contains('service')) {
          debugPrint('🔴 Location service error detected - stopping improvements');
          stopBackgroundImprovement();
        }
      }
    });
  }

  void stopBackgroundImprovement() {
    _improvementTimer?.cancel();
    _improvementTimer = null;
  }

  void stopLocationMonitoring() {
    _positionSubscription?.cancel();
    _improvementTimer?.cancel();
    _positionSubscription = null;
    _improvementTimer     = null;
  }

  void dispose() {
    stopLocationMonitoring();
    stopBackgroundImprovement();
  }

  // ── Static utilities ───────────────────────────────────────────────────────

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
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String calculateOfflineETA(double distanceInMeters, String transportMode) {
    final distanceInKm = distanceInMeters / 1000;
    final double speedKmh;

    switch (transportMode) {
      case 'walking':
        speedKmh = AppConstants.walkingSpeed;
      case 'bicycling':
        speedKmh = AppConstants.bicyclingSpeed;
      case 'driving':
        speedKmh = AppConstants.drivingSpeed;
      default:
        speedKmh = AppConstants.walkingSpeed;
    }

    final timeInMinutes = ((distanceInKm / speedKmh) * 60).round();

    if (timeInMinutes < 60) return '${timeInMinutes}min';
    final hours   = timeInMinutes ~/ 60;
    final minutes = timeInMinutes % 60;
    return '${hours}h ${minutes}min';
  }
}