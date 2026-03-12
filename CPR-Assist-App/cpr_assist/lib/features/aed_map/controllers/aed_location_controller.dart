import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;

import '../../../../core/core.dart';
import '../../../../providers/app_providers.dart';
import '../services/cache_service.dart';
import '../services/location_service.dart';
import '../services/map_service.dart';

/// Callbacks the widget must supply so the controller can trigger UI-level actions.
class AEDLocationCallbacks {
  /// Called on every location update (cached or real GPS).
  final Future<void> Function(LatLng location, {bool fromCache}) onLocationUpdate;

  /// Called the first time a real GPS fix arrives (replaces cached position).
  final Future<void> Function(LatLng location) onFirstRealGPSFix;

  /// Called when the location changed enough to show a banner.
  final void Function(LatLng newLocation, LatLng? oldLocation) onShowLocationBanner;

  /// Called when location services become available/unavailable.
  final void Function(bool available) onLocationAvailabilityChanged;

  /// Called to trigger a zoom-to-user+AEDs after location changes.
  final Future<void> Function({bool force, LatLng? knownLocation}) onZoomRequested;

  /// Called to re-sort AEDs after a significant location change.
  final void Function() onResortRequested;

  const AEDLocationCallbacks({
    required this.onLocationUpdate,
    required this.onFirstRealGPSFix,
    required this.onShowLocationBanner,
    required this.onLocationAvailabilityChanged,
    required this.onZoomRequested,
    required this.onResortRequested,
  });
}

/// Owns all GPS / location logic that lives between [LocationService] and the widget.
/// Extracted from _AEDMapWidgetState.
class AEDLocationController {
  final LocationService _locationService;
  final WidgetRef _ref;
  final AEDLocationCallbacks _callbacks;

  // ── GPS state ──────────────────────────────────────────────────────────────
  bool _isActive = false;
  bool _isNavigating = false;
  StreamSubscription<Position>? _positionSubscription;

  // ── Manual GPS search ──────────────────────────────────────────────────────
  bool _isManuallySearchingGPS = false;
  bool _gpsSearchSuccess = false;
  StreamSubscription<Position>? _manualGPSSubscription;

  // ── Location freshness ─────────────────────────────────────────────────────
  DateTime? _locationLastUpdated;
  bool _isUsingCachedLocation = false;
  bool _hasRealGPSFix = false;
  bool _isSettingUpLocation = false;
  bool _hasRequestedPermission = false;

  // ── Throttling ─────────────────────────────────────────────────────────────
  DateTime? _lastResortTime;

  // Getters consumed by the widget / routing coordinator
  bool get isManuallySearchingGPS => _isManuallySearchingGPS;
  bool get gpsSearchSuccess => _gpsSearchSuccess;
  bool get hasRealGPSFix => _hasRealGPSFix;
  bool get isUsingCachedLocation => _isUsingCachedLocation;
  DateTime? get locationLastUpdated => _locationLastUpdated;
  bool get hasRequestedPermission => _hasRequestedPermission;

  bool isLocationStale() {
    if (!_isUsingCachedLocation || _locationLastUpdated == null) return false;
    final age = DateTime.now().difference(_locationLastUpdated!).inHours;
    return age >= 1 && age < 5;
  }

  bool isLocationTooOld() {
    if (!_isUsingCachedLocation || _locationLastUpdated == null) return false;
    return DateTime.now().difference(_locationLastUpdated!).inHours >= 5;
  }

  AEDLocationController({
    required LocationService locationService,
    required WidgetRef ref,
    required AEDLocationCallbacks callbacks,
  })  : _locationService = locationService,
        _ref = ref,
        _callbacks = callbacks;

  // ══════════════════════════════════════════════════════════════════════════
  // GPS STREAM LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  /// Starts GPS stream with appropriate accuracy for current mode.
  Future<void> startGPSTracking({required bool isNavigating}) async {
    if (_isActive) await stopGPSTracking();

    _isNavigating = isNavigating;
    _isActive = true;

    await Future.delayed(const Duration(milliseconds: 200));

    await _locationService.startProgressiveLocationTracking(
      onLocationUpdate: _onRawLocationUpdate,
      isNavigating: isNavigating,
      distanceFilter: isNavigating ? 0 : 10,
    );

    debugPrint('✅ GPS tracking started (navigating: $isNavigating)');
  }

  /// Stops GPS stream completely.
  Future<void> stopGPSTracking() async {
    if (!_isActive) return;
    _isActive = false;
    _locationService.stopLocationMonitoring();
    debugPrint('✅ GPS tracking stopped');
  }

  bool get isActive => _isActive;
  bool get isNavigating => _isNavigating;

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION SERVICE MONITORING
  // ══════════════════════════════════════════════════════════════════════════

  /// Starts monitoring location-service on/off transitions.
  void startLocationServiceMonitoring() {
    LocationService.startLocationServiceMonitoring();
    LocationService.locationServiceStream?.listen((isEnabled) async {
      final hasPermission = await _locationService.hasPermission;
      final shouldHaveLocation = isEnabled && hasPermission;

      if (shouldHaveLocation) {
        debugPrint('📍 Location services became available');
        _callbacks.onLocationAvailabilityChanged(true);
        await setupLocationAfterEnable();
      } else {
        debugPrint('📍 Location services became unavailable');
        _callbacks.onLocationAvailabilityChanged(false);
      }
    });
  }

  /// Full location setup after GPS is enabled (permission + cached position + stream).
  Future<void> setupLocationAfterEnable() async {
    if (_isSettingUpLocation) {
      debugPrint('⏭️ Location setup already in progress, skipping');
      return;
    }
    _isSettingUpLocation = true;

    try {
      await stopGPSTracking();

      if (!await _locationService.hasPermission) {
        debugPrint('❌ No permission after enable');
        return;
      }

      final cachedAppState = await CacheService.getLastAppState();
      if (cachedAppState != null) {
        final cachedLat = cachedAppState['latitude'] as double?;
        final cachedLng = cachedAppState['longitude'] as double?;

        if (cachedLat != null && cachedLng != null) {
          final cachedLocation = LatLng(cachedLat, cachedLng);
          final timestamp = cachedAppState['timestamp'] as int?;

          if (timestamp != null) {
            _locationLastUpdated =
                DateTime.fromMillisecondsSinceEpoch(timestamp);
            _isUsingCachedLocation = true;
          }

          debugPrint('📍 [GPS ON] Using cached location: $cachedLocation');
          await _callbacks.onLocationUpdate(cachedLocation, fromCache: true);
          await _callbacks.onZoomRequested();
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        await startGPSTracking(isNavigating: false);
      } else {
        debugPrint('⚠️ GPS still off — skipping stream start');
      }
    } catch (e) {
      debugPrint('❌ Error setting up location after enable: $e');
    } finally {
      _isSettingUpLocation = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PERMISSION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> requestLocationPermission({
    required Future<void> mapReadyFuture,
    required MapViewController? mapViewController,
    required BuildContext context,
  }) async {
    await mapReadyFuture;
    _hasRequestedPermission = true;

    final granted = await _locationService.requestPermission();

    if (granted) {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

      if (isServiceEnabled) {
        final location = await _locationService.getCurrentLatLng();
        if (location != null) {
          await _callbacks.onLocationUpdate(location);
        }
        await startGPSTracking(isNavigating: false);
      } else {
        debugPrint('⚠️ Permission granted but GPS off');
        _callbacks.onLocationAvailabilityChanged(false);
        await mapViewController?.showDefaultGreeceView();
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MANUAL GPS SEARCH
  // ══════════════════════════════════════════════════════════════════════════

  void startManualGPSSearch(VoidCallback onStateChanged) {
    if (_isManuallySearchingGPS) return;

    _isManuallySearchingGPS = true;
    _gpsSearchSuccess = false;
    onStateChanged();

    Future.delayed(const Duration(milliseconds: 200), () {
      _manualGPSSubscription = _locationService
          .getPositionStream(distanceFilter: 10, accuracy: LocationAccuracy.high)
          .timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) => sink.close(),
      )
          .listen(
            (position) {
          final location = LatLng(position.latitude, position.longitude);
          _callbacks.onLocationUpdate(location);

          _isManuallySearchingGPS = false;
          _gpsSearchSuccess = true;
          onStateChanged();

          Future.delayed(const Duration(seconds: 2), () {
            _gpsSearchSuccess = false;
            onStateChanged();
          });

          _manualGPSSubscription?.cancel();
        },
        onError: (error) {
          debugPrint('GPS search error: $error');
          _isManuallySearchingGPS = false;
          onStateChanged();
        },
      );
    });
  }

  void stopManualGPSSearch(VoidCallback onStateChanged) {
    _manualGPSSubscription?.cancel();
    _isManuallySearchingGPS = false;
    _gpsSearchSuccess = false;
    onStateChanged();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION UPDATE PROCESSING
  // ══════════════════════════════════════════════════════════════════════════

  /// Called by the GPS stream for every new position.
  Future<void> _onRawLocationUpdate(LatLng location) async {
    await processLocationUpdate(location, fromCache: false);
  }

  /// Full location-update pipeline (also called externally with fromCache=true).
  Future<void> processLocationUpdate(LatLng location,
      {bool fromCache = false}) async {
    final bool isFirstRealGPSFix = !fromCache && !_hasRealGPSFix;

    if (!fromCache) {
      _locationLastUpdated = DateTime.now();
      _isUsingCachedLocation = false;
      if (!_hasRealGPSFix) {
        _hasRealGPSFix = true;
      }
    } else {
      _isUsingCachedLocation = true;
    }

    final currentState = _ref.read(mapStateProvider);
    final LatLng? previousLocation = currentState.userLocation;
    final bool wasLocationNull = previousLocation == null;

    // Banner for significant real-GPS moves
    if (!wasLocationNull && !fromCache) {
      final distance =
      LocationService.distanceBetween(previousLocation, location);
      if (distance > 100) {
        _callbacks.onShowLocationBanner(location, previousLocation);
      }
    }

    // Skip tiny moves when not navigating
    if (!wasLocationNull && !fromCache && !currentState.navigation.hasStarted) {
      final distance =
      LocationService.distanceBetween(previousLocation, location);
      if (distance < 5) {
        _locationLastUpdated = DateTime.now();
        return;
      }
    }

    // Delegate to the widget's location-update handler which writes to state
    // and triggers routing coordinator actions.
    await _callbacks.onLocationUpdate(location, fromCache: fromCache);

    // ── First real GPS fix: clear stale distances and force re-zoom ─────────
    if (isFirstRealGPSFix) {
      await _callbacks.onFirstRealGPSFix(location);
      return;
    }

    // ── Subsequent updates: re-sort when moved significantly ─────────────────
    if (!wasLocationNull) {
      final distance =
      LocationService.distanceBetween(previousLocation, location);
      if (distance > AppConstants.locationSigMovement) {
        final now = DateTime.now();
        if (_lastResortTime == null ||
            now.difference(_lastResortTime!).inSeconds >= 10) {
          _lastResortTime = now;
          _callbacks.onResortRequested();
        }
      }
    }

    // ── Persist app state ─────────────────────────────────────────────────
    final latestState = _ref.read(mapStateProvider);
    if (latestState.userLocation != null) {
      CacheService.saveLastAppState(
        latestState.userLocation!,
        latestState.navigation.transportMode,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REGION CACHING HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  void cacheUserRegion(LatLng userLocation) {
    final generalRegion = _determineGeneralRegion(userLocation);
    CacheService.saveLastMapRegion(center: generalRegion, zoom: 12.0);
    debugPrint(
      '📍 Cached user\'s general region: '
          '${generalRegion.latitude.toStringAsFixed(2)}, '
          '${generalRegion.longitude.toStringAsFixed(2)}',
    );
  }

  LatLng _determineGeneralRegion(LatLng userLocation) {
    final roundedLat = (userLocation.latitude * 100).round() / 100;
    final roundedLng = (userLocation.longitude * 100).round() / 100;
    return LatLng(roundedLat, roundedLng);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION FRESHNESS FOR ROUTING
  // ══════════════════════════════════════════════════════════════════════════

  /// Shows a location-updated banner via UIHelper.
  void showLocationUpdatedBanner(
      BuildContext context,
      LatLng newLocation,
      LatLng? oldLocation,
      ) {
    String message = 'Updated to current location';

    if (oldLocation != null) {
      final distance =
      LocationService.distanceBetween(oldLocation, newLocation);
      if (distance > 1000) {
        message =
        'Location updated (${(distance / 1000).toStringAsFixed(1)} km away)';
      } else {
        message =
        'Location updated (${distance.toStringAsFixed(0)} m away)';
      }
    }

    UIHelper.clearSnackbars(context);
    UIHelper.showSnackbar(
      context,
      message: message,
      icon: Icons.my_location,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION PERMISSION + SERVICE PROMPT (resume / recenter flows)
  // ══════════════════════════════════════════════════════════════════════════

  /// Prompts for GPS service enable via the OS dialog, then sets up location.
  Future<bool> promptAndEnableLocationService() async {
    final locService = loc.Location();
    final enabled = await locService.requestService();
    if (!enabled) return false;
    await Future.delayed(const Duration(milliseconds: 500));
    await setupLocationAfterEnable();
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DISPOSE
  // ══════════════════════════════════════════════════════════════════════════

  void dispose() {
    _positionSubscription?.cancel();
    _manualGPSSubscription?.cancel();
    _locationService.stopLocationMonitoring();
    LocationService.stopLocationServiceMonitoring();
    debugPrint('🗑️ AEDLocationController disposed');
  }
}