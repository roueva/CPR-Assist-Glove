import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
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
  DateTime? _lastCompassUpdate;
  DateTime? _lastProgrammaticMoveTime;
  DateTime? _lastUserTouchTime;
  bool      _showRecenterButton      = false;
  LatLng?   _previousUserLocation;
  DateTime? _lastLocationUpdateTime;
  bool      _isRecenterInProgress    = false;

  // ── Single camera driver ─────────────────────────────────────────────────
  // GPS and compass only ever write these targets. The Ticker below is the
  // only thing that ever calls moveCamera — nothing else touches the camera
  // once navigation is active, so there is no animation to cancel and no
  // driver to fight.
  LatLng?   _targetPosition;
  double?   _targetBearing;
  Ticker?   _cameraTicker;
  Duration  _lastCameraTick = Duration.zero;
  LatLng?   _cameraPosition;
  double    _cameraBearing  = 0.0;
  double    _cameraZoom     = AppConstants.navigationZoom;

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
  double?         get currentHeading   => _targetBearing;
  bool            get isActive         => _navigationState != NavigationState.inactive;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Initialize the controller with a Google Maps controller.
  void initialize(GoogleMapController mapController) {
    _mapController = mapController;
    debugPrint('🎮 NavigationController initialized with map controller');
  }

  /// Update the current user location.
  void updateUserLocation(LatLng location) {
    _targetPosition = location;

    if (_navigationState == NavigationState.compassTracking) {
      if (_wasRecentUserTouch()) {
        if (!_showRecenterButton) {
          _showRecenterButton = true;
          _onRecenterButtonVisibilityChanged?.call(true);
        }
        return;
      }

      _updateLocationHistory(location);
      _ensureCameraTicker();
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
    _targetPosition = userLocation;

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

    _cameraZoom     = AppConstants.compassOnlyZoom;
    _targetPosition = destination;
    _cameraPosition = destination;
    _cameraBearing  = _targetBearing ?? 0.0;

    _startCompassTracking();
    _ensureCameraTicker();
    _notifyStateChanged();
  }

  /// Returns the current compass heading (bearing to destination requires GPS).
  double calculateBearingToDestination(LatLng destination) {
    return _targetBearing ?? 0.0;
  }

  /// Handle camera move started events.
  void onCameraMoveStarted() {
    if (_isRecenterInProgress) return;
    if (_navigationState == NavigationState.inactive) return;
    if (_isRecentProgrammaticMove) return;

    _lastUserTouchTime = DateTime.now();
    _handleUserInteraction();
  }

  void onCameraMoved() {
    if (_isRecenterInProgress) return;
    if (_navigationState == NavigationState.inactive) return;
    if (_isRecentProgrammaticMove) return;

    _lastUserTouchTime = DateTime.now();
    _handleUserInteraction();
  }

  /// Recenter map and resume compass tracking.
  void recenterAndResumeTracking(LatLng userLocation) {
    HapticFeedback.lightImpact();
    debugPrint('🎯 Recentering and resuming compass tracking');

    _isRecenterInProgress = true;
    _targetPosition        = userLocation;
    _navigationState       = NavigationState.compassTracking;
    _showRecenterButton    = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    _lastProgrammaticMoveTime = DateTime.now();
    _lastUserTouchTime        = null;

    if (_mapController != null) {
      double targetBearing = _targetBearing ?? 0.0;

      FlutterCompass.events?.take(1).timeout(
        const Duration(milliseconds: 100),
        onTimeout: (sink) => sink.close(),
      ).listen(
            (event) {
          if (event.heading != null) targetBearing = event.heading!;
        },
        onDone:  () => _completeRecenter(targetBearing),
        onError: (_) => _completeRecenter(targetBearing),
      );

      if (FlutterCompass.events == null) {
        _completeRecenter(targetBearing);
      }
    }
  }

  /// Cancel navigation and return to normal mode.
  void cancelNavigation() {
    debugPrint('🛑 Cancelling navigation');

    _navigationState    = NavigationState.inactive;
    _showRecenterButton = false;
    _stopCompassTracking();
    _stopCameraTicker();
    _userInteractionDebouncer?.cancel();
    _onRecenterButtonVisibilityChanged?.call(false);
    _notifyStateChanged();

    _previousUserLocation  = null;
    _lastLocationUpdateTime = null;
    _targetPosition = null;
    _cameraPosition = null;
  }

  /// Dispose of all resources.
  void dispose() {
    debugPrint('🗑️ Disposing NavigationController');

    _compassSubscription?.cancel();
    _compassSubscription = null;

    _userInteractionDebouncer?.cancel();
    _userInteractionDebouncer = null;

    _cameraTicker?.dispose();
    _cameraTicker = null;

    _mapController        = null;
    _targetPosition        = null;
    _cameraPosition        = null;
    _previousUserLocation = null;

    _navigationState    = NavigationState.inactive;
    _showRecenterButton = false;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _updateLocationHistory(LatLng location) {
    final now = DateTime.now();

    if (_previousUserLocation != null && _lastLocationUpdateTime != null) {
      final timeDelta =
          now.difference(_lastLocationUpdateTime!).inMilliseconds / 1000.0;

      if (timeDelta > 0 && timeDelta < 5) {
        _calculateDistance(_previousUserLocation!, location);
      }
    }

    _previousUserLocation   = location;
    _lastLocationUpdateTime = now;
  }

  Future<void> _enterNavigationMode(LatLng userLocation, LatLng destination) async {
    _lastProgrammaticMoveTime = DateTime.now();

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

    _cameraZoom     = AppConstants.navigationZoom;
    _targetBearing  = initialBearing;
    _targetPosition = userLocation;
    _cameraPosition = userLocation;
    _cameraBearing  = initialBearing;

    _ensureCameraTicker();

    debugPrint('✅ Navigation mode entered successfully');
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

      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!).inMilliseconds <
              AppConstants.compassDebounceDurationMs) {
        return;
      }
      _lastCompassUpdate = now;

      if (_targetBearing != null) {
        final bearingDiff = _shortestBearingDelta(_targetBearing!, event.heading!).abs();
        if (bearingDiff < 1.0) return;

        _targetBearing = _interpolateBearing(_targetBearing!, event.heading!, 0.15);
      } else {
        _targetBearing = event.heading;
      }

      _ensureCameraTicker();
    });
  }

  double _interpolateBearing(double from, double to, double factor) {
    final difference = _shortestBearingDelta(from, to);
    return _normalizeBearing(from + difference * factor);
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

  void _completeRecenter(double bearing) {
    _targetBearing = bearing;
    _ensureCameraTicker();

    Timer(const Duration(milliseconds: AppConstants.navigationRecenterDurationMs), () {
      _isRecenterInProgress = false;
      _lastUserTouchTime    = null;
      _notifyStateChanged();
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

  // ── Camera ticker — the single driver ────────────────────────────────────

  void _ensureCameraTicker() {
    final ticker = _cameraTicker ??= Ticker(_onCameraTick);
    if (!ticker.isTicking) {
      _lastCameraTick = Duration.zero;
      ticker.start();
    }
  }

  void _stopCameraTicker() {
    _cameraTicker?.stop();
  }

  void _onCameraTick(Duration elapsed) {
    final dtMs = (elapsed - _lastCameraTick).inMicroseconds / 1000.0;
    _lastCameraTick = elapsed;
    if (dtMs <= 0) return;

    // Stop rather than idle-tick at 60fps: no map/target, the user is
    // dragging, or the camera has already caught up to its targets. GPS and
    // compass updates call _ensureCameraTicker() again whenever there is
    // fresh work to do.
    if (_mapController == null || _targetPosition == null || _wasRecentUserTouch()) {
      _cameraTicker?.stop();
      return;
    }

    final target = _targetPosition!;
    final targetBearing = _targetBearing ?? _cameraBearing;
    final atTargetPosition = _cameraPosition != null &&
        _calculateDistance(_cameraPosition!, target) < AppConstants.cameraSnapDistanceMeters;
    final atTargetBearing =
        _shortestBearingDelta(_cameraBearing, targetBearing).abs() < AppConstants.cameraSnapBearingDegrees;
    if (atTargetPosition && atTargetBearing) {
      _cameraTicker?.stop();
      return;
    }

    final current = _cameraPosition ?? target;

    final positionT = _smoothingFactor(dtMs, AppConstants.cameraPositionSmoothingMs);
    var newPosition = LatLng(
      current.latitude  + (target.latitude  - current.latitude)  * positionT,
      current.longitude + (target.longitude - current.longitude) * positionT,
    );
    if (_calculateDistance(newPosition, target) < AppConstants.cameraSnapDistanceMeters) {
      newPosition = target;
    }

    final bearingT = _smoothingFactor(dtMs, AppConstants.cameraBearingSmoothingMs);
    var newBearing = _interpolateBearing(_cameraBearing, targetBearing, bearingT);
    if (_shortestBearingDelta(newBearing, targetBearing).abs() < AppConstants.cameraSnapBearingDegrees) {
      newBearing = targetBearing;
    }

    _cameraPosition = newPosition;
    _cameraBearing  = newBearing;
    _lastProgrammaticMoveTime = DateTime.now();

    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target:  newPosition,
          zoom:    _cameraZoom,
          tilt:    AppConstants.navigationTilt,
          bearing: newBearing,
        ),
      ),
    );
  }

  double _smoothingFactor(double dtMs, double timeConstantMs) {
    final factor = 1 - exp(-dtMs / timeConstantMs);
    return factor.clamp(0.0, 1.0);
  }

  // ── Math helpers ──────────────────────────────────────────────────────────

  double _shortestBearingDelta(double from, double to) {
    double difference = to - from;
    if (difference > 180) difference -= 360;
    if (difference < -180) difference += 360;
    return difference;
  }

  double _normalizeBearing(double bearing) {
    final normalized = bearing % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

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
}
