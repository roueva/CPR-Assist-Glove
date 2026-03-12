import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/core.dart';

enum NavigationState { inactive, compassTracking, userControlling }

class NavigationController {
  GoogleMapController? _mapController;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _userInteractionDebouncer;

  NavigationState _navigationState   = NavigationState.inactive;
  double?   _currentHeading;
  DateTime? _lastCompassUpdate;
  DateTime? _lastProgrammaticMoveTime;
  DateTime? _lastUserTouchTime;
  bool      _showRecenterButton      = false;
  LatLng?   _currentUserLocation;
  LatLng?   _previousUserLocation;
  DateTime? _lastLocationUpdateTime;
  double?   _currentBearing; // direction of travel (different from compass heading)
  Timer?    _predictionTimer;
  bool      _isRecenterInProgress    = false;

  // Callbacks
  final VoidCallback?       _onStateChanged;
  final void Function(bool)? _onRecenterButtonVisibilityChanged;

  NavigationController({
    VoidCallback?        onStateChanged,
    void Function(bool)? onRecenterButtonVisibilityChanged,
  })  : _onStateChanged = onStateChanged,
        _onRecenterButtonVisibilityChanged = onRecenterButtonVisibilityChanged;

  // ── Getters ───────────────────────────────────────────────────────────────

  NavigationState get navigationState  => _navigationState;
  bool            get showRecenterButton => _showRecenterButton;
  double?         get currentHeading   => _currentHeading;
  bool            get isActive         => _navigationState != NavigationState.inactive;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Initialize the controller with a Google Maps controller.
  void initialize(GoogleMapController mapController) {
    _mapController = mapController;
    debugPrint('🎮 NavigationController initialized with map controller');
  }

  /// Update the current user location.
  void updateUserLocation(LatLng location) {
    _currentUserLocation = location;

    if (_navigationState == NavigationState.compassTracking) {
      if (_wasRecentUserTouch()) {
        if (!_showRecenterButton) {
          _showRecenterButton = true;
          _onRecenterButtonVisibilityChanged?.call(true);
        }
        return;
      }

      _updateSpeedAndBearing(location);
      _updateCameraToLocation(location);
    } else if (_navigationState != NavigationState.inactive && _mapController != null) {
      if (_wasRecentUserTouch()) {
        if (!_showRecenterButton) {
          _showRecenterButton = true;
          _onRecenterButtonVisibilityChanged?.call(true);
        }
        return;
      }

      _lastProgrammaticMoveTime = DateTime.now();
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target:  location,
            zoom:    AppConstants.navigationZoom,
            tilt:    AppConstants.navigationTilt,
            bearing: _currentHeading ?? 0.0,
          ),
        ),
        duration: const Duration(milliseconds: 400),
      );
    }
  }

  /// Start navigation mode with compass tracking.
  Future<void> startNavigation(
      LatLng userLocation,
      LatLng destination, {
        bool isOffline = false,
      }) async {
    if (_mapController == null) {
      debugPrint('Cannot start navigation - map controller not initialized');
      return;
    }

    debugPrint('Starting navigation mode with location tracking...');
    _currentUserLocation = userLocation;

    await _enterNavigationMode(userLocation, destination);

    _navigationState = NavigationState.compassTracking;
    _startCompassTracking();
    debugPrint('🧭 Compass tracking enabled for navigation');

    _notifyStateChanged();
  }

  /// Start compass-only mode when GPS is unavailable.
  void startCompassOnlyMode(LatLng destination) {
    if (_mapController == null) {
      debugPrint('❌ Cannot start compass mode - map controller not initialized');
      return;
    }

    debugPrint('🧭 Starting compass-only mode (no GPS location)');

    _navigationState = NavigationState.compassTracking;
    _showRecenterButton = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    _lastProgrammaticMoveTime = DateTime.now();
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(destination, AppConstants.compassOnlyZoom),
    );

    _startCompassTracking();
    _notifyStateChanged();
  }

  /// Returns the current compass heading (bearing to destination requires GPS).
  double calculateBearingToDestination(LatLng destination) {
    return _currentHeading ?? 0.0;
  }

  /// Handle camera move started events.
  void onCameraMoveStarted() {
    if (_isRecenterInProgress) {
      debugPrint('📷 Camera move STARTED (recenter in progress - ignoring)');
      return;
    }

    if (_navigationState == NavigationState.inactive || _isRecentProgrammaticMove) {
      final isCompassMove =
          _navigationState == NavigationState.compassTracking && _isRecentProgrammaticMove;

      if (!isCompassMove && _wasRecentUserTouch()) {
        _lastUserTouchTime = DateTime.now();
        debugPrint('📱 User manual camera control detected (camera move started)');
        _handleUserInteraction();
      }
      return;
    }

    _lastUserTouchTime = DateTime.now();
    debugPrint('📱 User manual camera control detected');
    _handleUserInteraction();
  }

  /// Handle camera moved events.
  void onCameraMoved() {
    if (_isRecenterInProgress) return;

    if (_navigationState != NavigationState.compassTracking || _isRecentProgrammaticMove) {
      final isCompassMove =
          _navigationState == NavigationState.compassTracking && _isRecentProgrammaticMove;

      if (!isCompassMove && _wasRecentUserTouch()) {
        _lastUserTouchTime = DateTime.now();
        debugPrint('📱 User manual camera control detected (camera moved)');
        _handleUserInteraction();
      }
      return;
    }

    _lastUserTouchTime = DateTime.now();
    debugPrint('📱 User manual camera control detected (camera moved)');
    _handleUserInteraction();
  }

  /// Recenter map and resume compass tracking.
  void recenterAndResumeTracking(LatLng userLocation) {
    HapticFeedback.lightImpact();
    debugPrint('🎯 Recentering and resuming compass tracking');

    _isRecenterInProgress = true;
    _currentUserLocation  = userLocation;
    _navigationState      = NavigationState.compassTracking;
    _showRecenterButton   = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    _lastProgrammaticMoveTime = DateTime.now();
    _lastUserTouchTime        = null;

    if (_mapController != null) {
      double targetBearing = _currentHeading ?? 0.0;

      FlutterCompass.events?.take(1).timeout(
        const Duration(milliseconds: 100),
        onTimeout: (sink) => sink.close(),
      ).listen(
            (event) {
          if (event.heading != null) targetBearing = event.heading!;
        },
        onDone:  () => _performRecenterAnimation(userLocation, targetBearing),
        onError: (_) => _performRecenterAnimation(userLocation, targetBearing),
      );

      if (FlutterCompass.events == null) {
        _performRecenterAnimation(userLocation, targetBearing);
      }
    }
  }

  /// Cancel navigation and return to normal mode.
  void cancelNavigation() {
    debugPrint('🛑 Cancelling navigation');

    _navigationState    = NavigationState.inactive;
    _showRecenterButton = false;
    _stopCompassTracking();
    _stopPredictionUpdates();
    _userInteractionDebouncer?.cancel();
    _onRecenterButtonVisibilityChanged?.call(false);
    _notifyStateChanged();

    _previousUserLocation  = null;
    _lastLocationUpdateTime = null;
    _currentBearing        = null;
  }

  /// Dispose of all resources.
  void dispose() {
    debugPrint('🗑️ Disposing NavigationController');

    _compassSubscription?.cancel();
    _compassSubscription = null;

    _userInteractionDebouncer?.cancel();
    _userInteractionDebouncer = null;

    _stopPredictionUpdates();

    _mapController        = null;
    _currentUserLocation  = null;
    _previousUserLocation = null;

    _navigationState    = NavigationState.inactive;
    _showRecenterButton = false;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _updateSpeedAndBearing(LatLng location) {
    final now = DateTime.now();

    if (_previousUserLocation != null && _lastLocationUpdateTime != null) {
      final timeDelta =
          now.difference(_lastLocationUpdateTime!).inMilliseconds / 1000.0;

      if (timeDelta > 0 && timeDelta < 5) {
        _calculateDistance(_previousUserLocation!, location);
        _currentBearing = _calculateBearingBetweenPoints(_previousUserLocation!, location);
      }
    }

    _previousUserLocation   = location;
    _lastLocationUpdateTime = now;
  }

  void _stopPredictionUpdates() {
    _predictionTimer?.cancel();
    _predictionTimer = null;
  }

  void _updateCameraToLocation(LatLng location) {
    if (_mapController == null) return;

    if (_wasRecentUserTouch()) {
      if (!_showRecenterButton) {
        _showRecenterButton = true;
        _onRecenterButtonVisibilityChanged?.call(true);
      }
      return;
    }

    _lastProgrammaticMoveTime = DateTime.now();

    final cameraHeading = _currentBearing ?? _currentHeading ?? 0.0;

    // Use moveCamera (not animateCamera) — prevents "jumping every 5 meters"
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  location,
          zoom:    AppConstants.navigationZoom,
          tilt:    AppConstants.navigationTilt,
          bearing: cameraHeading,
        ),
      ),
    );
  }

  Future<void> _enterNavigationMode(LatLng userLocation, LatLng destination) async {
    _lastProgrammaticMoveTime = DateTime.now();

    try {
      double initialBearing = 0.0;

      try {
        final compassEvent = await FlutterCompass.events?.first.timeout(
          const Duration(seconds: 2),
        );
        initialBearing = compassEvent?.heading ?? 0.0;
        debugPrint('🧭 Got initial bearing: ${initialBearing.toStringAsFixed(1)}°');
      } catch (e) {
        debugPrint('⚠️ Could not get initial compass reading, using 0°');
      }

      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target:  userLocation,
            zoom:    AppConstants.navigationZoom,
            tilt:    AppConstants.navigationTilt,
            bearing: initialBearing,
          ),
        ),
      );

      debugPrint('✅ Navigation mode entered successfully');
    } catch (e) {
      debugPrint('⚠️ Error entering navigation mode: $e');
    }
  }

  void _startCompassTracking() {
    if (_compassSubscription != null) {
      debugPrint('⚠️ Compass tracking already active');
      return;
    }

    debugPrint('🧭 Starting compass tracking');
    _showRecenterButton = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    if (FlutterCompass.events == null) {
      debugPrint('❌ Compass not available on this device');
      return;
    }

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (_mapController == null ||
          _navigationState != NavigationState.compassTracking) {
        return;
      }

      if (event.heading == null) return;

      if (event.accuracy != null) _handleCompassAccuracy(event.accuracy!);

      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!).inMilliseconds <
              AppConstants.compassDebounceDurationMs) {
        return;
      }
      _lastCompassUpdate = now;

      if (_currentHeading != null) {
        final bearingDiff = (event.heading! - _currentHeading!).abs();
        if (bearingDiff < 2.0) return;

        final interpolated = _interpolateBearing(_currentHeading!, event.heading!, 0.3);
        _currentHeading = interpolated;
        _updateCameraWithCompass(interpolated);
      } else {
        _currentHeading = event.heading;
        _updateCameraWithCompass(event.heading!);
      }
    });
  }

  void _handleCompassAccuracy(double accuracy) {
    if (accuracy < 0.3) {
      debugPrint('⚠️ Compass accuracy low ($accuracy) - consider showing calibration hint');
    }
  }

  double _interpolateBearing(double from, double to, double factor) {
    double difference = to - from;
    if (difference > 180) difference -= 360;
    if (difference < -180) difference += 360;
    return from + (difference * factor);
  }

  void _updateCameraWithCompass(double heading) {
    if (_mapController == null || _currentUserLocation == null) return;
    if (_wasRecentUserTouch()) return;

    _lastProgrammaticMoveTime = DateTime.now();

    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  _currentUserLocation!,
          zoom:    AppConstants.navigationZoom,
          tilt:    AppConstants.navigationTilt,
          bearing: heading,
        ),
      ),
    );
  }

  void _handleUserInteraction() {
    if (_navigationState == NavigationState.inactive) return;
    if (_isRecentProgrammaticMove) return;

    debugPrint('👆 User manually controlling camera');
    _navigationState    = NavigationState.userControlling;
    _showRecenterButton = true;
    _onRecenterButtonVisibilityChanged?.call(true);

    _userInteractionDebouncer?.cancel();
    _userInteractionDebouncer = Timer(AppConstants.mapAnimationDelay, _notifyStateChanged);
  }

  void _performRecenterAnimation(LatLng userLocation, double bearing) {
    _lastProgrammaticMoveTime = DateTime.now();
    _lastUserTouchTime        = null;

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  userLocation,
          zoom:    AppConstants.navigationZoom,
          tilt:    AppConstants.navigationTilt,
          bearing: bearing,
        ),
      ),
      duration: const Duration(milliseconds: AppConstants.navigationRecenterDurationMs),
    ).then((_) {
      debugPrint('🎯 Recenter completed');
      _lastProgrammaticMoveTime = DateTime.now();
      _lastUserTouchTime        = null;
      _isRecenterInProgress     = false;

      Future.delayed(AppConstants.mapAnimationDelay, () {
        _lastProgrammaticMoveTime = DateTime.now();
      });

      _notifyStateChanged();
    }).catchError((Object error) {
      debugPrint('⚠️ Recenter failed: $error');
      _isRecenterInProgress = false;
      _showRecenterButton   = false;
      _onRecenterButtonVisibilityChanged?.call(false);
    });
  }

  void _stopCompassTracking() {
    debugPrint('🧭 Stopping compass tracking');
    _compassSubscription?.cancel();
    _compassSubscription = null;
  }

  bool _wasRecentUserTouch() {
    if (_lastUserTouchTime == null) return false;
    return DateTime.now().difference(_lastUserTouchTime!).inMilliseconds <
        AppConstants.userTouchTimeoutMs;
  }

  bool get _isRecentProgrammaticMove {
    if (_lastProgrammaticMoveTime == null) return false;
    return DateTime.now().difference(_lastProgrammaticMoveTime!).inMilliseconds <
        AppConstants.programmaticMoveDurationMs;
  }

  void _notifyStateChanged() => _onStateChanged?.call();

  // ── Math helpers ──────────────────────────────────────────────────────────

  double _calculateDistance(LatLng from, LatLng to) {
    const earthRadius = 6371000.0;
    const toRad = 3.14159265359 / 180.0;

    final lat1 = from.latitude  * toRad;
    final lat2 = to.latitude    * toRad;
    final dLat = (to.latitude  - from.latitude)  * toRad;
    final dLon = (to.longitude - from.longitude) * toRad;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);

    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _calculateBearingBetweenPoints(LatLng from, LatLng to) {
    const toRad  = 3.14159265359 / 180.0;
    const toDeg  = 180.0 / 3.14159265359;

    final lat1 = from.latitude  * toRad;
    final lat2 = to.latitude    * toRad;
    final dLon = (to.longitude - from.longitude) * toRad;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    return (atan2(y, x) * toDeg + 360) % 360;
  }
}