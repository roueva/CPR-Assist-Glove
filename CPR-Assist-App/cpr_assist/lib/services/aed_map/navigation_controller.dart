import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/app_constants.dart';

enum NavigationState { inactive, compassTracking, userControlling }

class NavigationController {
  GoogleMapController? _mapController;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _userInteractionDebouncer;

  NavigationState _navigationState = NavigationState.inactive;
  double? _currentHeading;
  DateTime? _lastCompassUpdate;
  DateTime? _lastProgrammaticMoveTime;
  DateTime? _lastUserTouchTime;
  bool _showRecenterButton = false;
  LatLng? _currentUserLocation;
  LatLng? _previousUserLocation;
  DateTime? _lastLocationUpdateTime;
  double? _currentBearing; // direction of travel (different from compass heading)
  Timer? _predictionTimer;
  bool _isRecenterInProgress = false;

  static const int _programmaticMoveDurationMs = 500;

  // Callbacks
  final VoidCallback? _onStateChanged;
  final Function(bool)? _onRecenterButtonVisibilityChanged;

  NavigationController({
    VoidCallback? onStateChanged,
    Function(bool)? onRecenterButtonVisibilityChanged,
  }) : _onStateChanged = onStateChanged,
        _onRecenterButtonVisibilityChanged = onRecenterButtonVisibilityChanged;

  // Getters
  NavigationState get navigationState => _navigationState;
  bool get showRecenterButton => _showRecenterButton;
  double? get currentHeading => _currentHeading;
  bool get isActive => _navigationState != NavigationState.inactive;

  /// Initialize the controller with a Google Maps controller
  void initialize(GoogleMapController mapController) {
    _mapController = mapController;
    print("🎮 NavigationController initialized with map controller");
  }

  /// Update the current user location
  void updateUserLocation(LatLng location) {
    _currentUserLocation = location;

    // ✅ During navigation, ALWAYS update camera (no throttling)
    if (_navigationState == NavigationState.compassTracking) {
      if (_wasRecentUserTouch()) {
        if (!_showRecenterButton) {
          _showRecenterButton = true;
          _onRecenterButtonVisibilityChanged?.call(true);
        }
        return;
      }

      // Calculate speed and bearing for smooth interpolation
      _updateSpeedAndBearing(location);

      // Update camera smoothly
      _updateCameraToLocation(location, isPrediction: false);
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
            target: location,
            zoom: AppConstants.navigationZoom,
            tilt: AppConstants.navigationTilt,
            bearing: _currentHeading ?? 0.0,
          ),
        ),
        duration: const Duration(milliseconds: 400),
      );
    }
  }

  void _updateSpeedAndBearing(LatLng location) {
    final now = DateTime.now();

    if (_previousUserLocation != null && _lastLocationUpdateTime != null) {
      final timeDelta = now.difference(_lastLocationUpdateTime!).inMilliseconds / 1000.0;

      if (timeDelta > 0 && timeDelta < 5) {
        _calculateDistance(_previousUserLocation!, location);
        _currentBearing = _calculateBearingBetweenPoints(_previousUserLocation!, location);
      }
    }

    _previousUserLocation = location;
    _lastLocationUpdateTime = now;
  }

  /// Stop prediction updates
  void _stopPredictionUpdates() {
    _predictionTimer?.cancel();
    _predictionTimer = null;
  }

  /// Update camera to a location (actual or predicted)
  void _updateCameraToLocation(LatLng location, {bool isPrediction = false}) {
    if (_mapController == null) return;

    if (_wasRecentUserTouch()) {
      if (!_showRecenterButton) {
        _showRecenterButton = true;
        _onRecenterButtonVisibilityChanged?.call(true);
      }
      return;
    }

    _lastProgrammaticMoveTime = DateTime.now();

    // ✅ Use movement bearing if available, otherwise compass heading
    final cameraHeading = _currentBearing ?? _currentHeading ?? 0.0;

    // ✅ CRITICAL: Use moveCamera for instant updates, NOT animateCamera
    // This prevents the "jumping every 5 meters" issue
    _mapController!.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: AppConstants.navigationZoom,
          tilt: AppConstants.navigationTilt,
          bearing: cameraHeading,
        ),
      ),
    );
  }

  /// Calculate distance between two points (Haversine formula)
  double _calculateDistance(LatLng from, LatLng to) {
    const earthRadius = 6371000.0; // meters

    final lat1 = from.latitude * (3.14159265359 / 180.0);
    final lat2 = to.latitude * (3.14159265359 / 180.0);
    final dLat = (to.latitude - from.latitude) * (3.14159265359 / 180.0);
    final dLon = (to.longitude - from.longitude) * (3.14159265359 / 180.0);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) *
            sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Calculate bearing from one point to another
  double _calculateBearingBetweenPoints(LatLng from, LatLng to) {
    final lat1 = from.latitude * (3.14159265359 / 180.0);
    final lat2 = to.latitude * (3.14159265359 / 180.0);
    final dLon = (to.longitude - from.longitude) * (3.14159265359 / 180.0);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * (180.0 / 3.14159265359);
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Start navigation mode with compass tracking
  Future<void> startNavigation(LatLng userLocation, LatLng destination, {bool isOffline = false}) async {
    if (_mapController == null) {
      print("Cannot start navigation - map controller not initialized");
      return;
    }

    print("Starting navigation mode with location tracking...");
    _currentUserLocation = userLocation;

    await _enterNavigationMode(userLocation, destination);

    // ✅ ALWAYS use compass tracking when we have user location
    _navigationState = NavigationState.compassTracking;
    _startCompassTracking();
    print("🧭 Compass tracking enabled for navigation");

    _notifyStateChanged();
  }
  /// Enter navigation mode by positioning camera
  Future<void> _enterNavigationMode(LatLng userLocation, LatLng destination) async {
    _lastProgrammaticMoveTime = DateTime.now();

    try {
      double initialBearing = 0.0;

      // Try to get initial compass reading
      try {
        final compassEvent = await FlutterCompass.events?.first.timeout(
          const Duration(seconds: 2),
        );
        initialBearing = compassEvent?.heading ?? 0.0;
        print("🧭 Got initial bearing: ${initialBearing.toStringAsFixed(1)}°");
      } catch (e) {
        print("⚠️ Could not get initial compass reading, using 0°");
      }

      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: userLocation,
            zoom: AppConstants.navigationZoom,
            tilt: AppConstants.navigationTilt,
            bearing: initialBearing,
          ),
        ),
      );

      print("✅ Navigation mode entered successfully");
    } catch (e) {
      print("⚠️ Error entering navigation mode: $e");
    }
  }

  /// Start compass-only navigation without GPS location
  void startCompassOnlyMode(LatLng destination) {
    if (_mapController == null) {
      print("❌ Cannot start compass mode - map controller not initialized");
      return;
    }

    print("🧭 Starting compass-only mode (no GPS location)");

    _navigationState = NavigationState.compassTracking;
    _showRecenterButton = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    // Center map on destination since we don't have user location
    _lastProgrammaticMoveTime = DateTime.now();
    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(destination, 15.0),
    );

    // Start compass tracking to show direction
    _startCompassTracking();

    _notifyStateChanged();
  }

  /// Calculate absolute bearing to a destination from current device heading
  double calculateBearingToDestination(LatLng destination) {
    // Without user location, we can only show relative bearing
    // The UI must show: "Turn until arrow points forward"
    // This is a limitation of not having GPS
    return _currentHeading ?? 0.0;
  }

  /// Start compass tracking for navigation
  void _startCompassTracking() {
    if (_compassSubscription != null) {
      print("⚠️ Compass tracking already active");
      return;
    }

    print("🧭 Starting compass tracking");
    _showRecenterButton = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    if (FlutterCompass.events == null) {
      print("❌ Compass not available on this device");
      return;
    }

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      // ✅ ADD THIS: Safety check
      if (_mapController == null || _navigationState != NavigationState.compassTracking) {
        return;
      }

      if (event.heading == null) return;

      if (event.accuracy != null) {
        _handleCompassAccuracy(event.accuracy!);
      }

      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!).inMilliseconds < 150) {
        return;
      }
      _lastCompassUpdate = now;

      if (_currentHeading != null) {
        final bearingDiff = (event.heading! - _currentHeading!).abs();
        if (bearingDiff < 2.0) return;

        final interpolatedBearing = _interpolateBearing(_currentHeading!, event.heading!, 0.3);
        _currentHeading = interpolatedBearing;
        _updateCameraWithCompass(interpolatedBearing);
      } else {
        _currentHeading = event.heading;
        _updateCameraWithCompass(event.heading!);
      }
    });
  }

  /// Handle compass accuracy warnings
  void _handleCompassAccuracy(double accuracy) {
    if (accuracy < 0.3) {
      print("⚠️ Compass accuracy low ($accuracy) - consider showing calibration hint");
      // You could show a UI hint here for users to calibrate their compass
    }
  }

  /// Interpolate bearing for smooth rotation
  double _interpolateBearing(double from, double to, double factor) {
    double difference = to - from;

    // Handle 360-degree wrap-around
    if (difference > 180) difference -= 360;
    if (difference < -180) difference += 360;

    return from + (difference * factor);
  }

  /// Update camera position with compass heading
  void _updateCameraWithCompass(double heading) {
    if (_mapController == null || _currentUserLocation == null) return;
    if (_wasRecentUserTouch()) return;

    _lastProgrammaticMoveTime = DateTime.now();

    _mapController!.moveCamera(         // ← was animateCamera with duration 300ms
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentUserLocation!,
          zoom: AppConstants.navigationZoom,
          tilt: AppConstants.navigationTilt,
          bearing: heading,
        ),
      ),
    );
  }

  /// Handle camera move started events
  void onCameraMoveStarted() {
    // ✅ CRITICAL: Ignore if recenter is in progress
    if (_isRecenterInProgress) {
      print("📷 Camera move STARTED (recenter in progress - ignoring)");
      return;
    }

    if (_navigationState == NavigationState.inactive || _isRecentProgrammaticMove) {
      final isCompassMove = _navigationState == NavigationState.compassTracking && _isRecentProgrammaticMove;

      if (!isCompassMove && _wasRecentUserTouch()) {
        _lastUserTouchTime = DateTime.now();
        print("📱 User manual camera control detected (camera move started)");
        _handleUserInteraction();
      }
      return;
    }

    _lastUserTouchTime = DateTime.now();
    print("📱 User manual camera control detected");
    _handleUserInteraction();
  }

  /// Handle camera moved events
  void onCameraMoved() {
    // ✅ CRITICAL: Ignore if recenter is in progress
    if (_isRecenterInProgress) {
      return;
    }

    if (_navigationState != NavigationState.compassTracking || _isRecentProgrammaticMove) {
      final isCompassMove = _navigationState == NavigationState.compassTracking && _isRecentProgrammaticMove;

      if (!isCompassMove && _wasRecentUserTouch()) {
        _lastUserTouchTime = DateTime.now();
        print("📱 User manual camera control detected (camera moved)");
        _handleUserInteraction();
      }
      return;
    }

    _lastUserTouchTime = DateTime.now();
    print("📱 User manual camera control detected (camera moved)");
    _handleUserInteraction();
  }

  /// Handle user interaction with map camera
  void _handleUserInteraction() {
    if (_navigationState == NavigationState.inactive) return;
    if (_isRecentProgrammaticMove) return;

    print("👆 User manually controlling camera");
    _navigationState = NavigationState.userControlling;
    _showRecenterButton = true;
    _onRecenterButtonVisibilityChanged?.call(true);

    // Debounce to prevent flickering
    _userInteractionDebouncer?.cancel();
    _userInteractionDebouncer = Timer(const Duration(milliseconds: 300), () {
      _notifyStateChanged();
    });
  }

  /// Recenter map and resume compass tracking
  void recenterAndResumeTracking(LatLng userLocation) {
    HapticFeedback.lightImpact();
    print("🎯 Recentering and resuming compass tracking");

    _isRecenterInProgress = true;  // ✅ ADD THIS
    _currentUserLocation = userLocation;
    _navigationState = NavigationState.compassTracking;
    _showRecenterButton = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    _lastProgrammaticMoveTime = DateTime.now();
    _lastUserTouchTime = null;

    if (_mapController != null) {
      double targetBearing = _currentHeading ?? 0.0;

      FlutterCompass.events?.take(1).timeout(
        const Duration(milliseconds: 100),
        onTimeout: (sink) => sink.close(),
      ).listen(
            (event) {
          if (event.heading != null) {
            targetBearing = event.heading!;
          }
        },
        onDone: () => _performRecenterAnimation(userLocation, targetBearing),
        onError: (_) => _performRecenterAnimation(userLocation, targetBearing),
      );

      if (FlutterCompass.events == null) {
        _performRecenterAnimation(userLocation, targetBearing);
      }
    }
  }

  /// Perform the recenter animation
  void _performRecenterAnimation(LatLng userLocation, double bearing) {
    _lastProgrammaticMoveTime = DateTime.now();
    _lastUserTouchTime = null;

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: userLocation,
          zoom: AppConstants.navigationZoom,
          tilt: AppConstants.navigationTilt,
          bearing: bearing,
        ),
      ),
      duration: const Duration(milliseconds: 600),
    ).then((_) {
      print("🎯 Recenter completed");
      _lastProgrammaticMoveTime = DateTime.now();
      _lastUserTouchTime = null;
      _isRecenterInProgress = false;

      Future.delayed(const Duration(milliseconds: 300), () {
        _lastProgrammaticMoveTime = DateTime.now();
      });

      _notifyStateChanged();
    }).catchError((error) {
      print("⚠️ Recenter failed: $error");
      _isRecenterInProgress = false; // ✅ Always reset
      _showRecenterButton = false; // ✅ Hide button on error
      _onRecenterButtonVisibilityChanged?.call(false);
    });
  }

  /// Cancel navigation and return to normal mode
  void cancelNavigation() {
    print("🛑 Cancelling navigation");

    _navigationState = NavigationState.inactive;
    _showRecenterButton = false;
    _stopCompassTracking();
    _stopPredictionUpdates(); // ✅ ADD THIS
    _userInteractionDebouncer?.cancel();
    _onRecenterButtonVisibilityChanged?.call(false);
    _notifyStateChanged();

    // ✅ ADD THIS: Clear prediction state
    _previousUserLocation = null;
    _lastLocationUpdateTime = null;
    _currentBearing = null;
  }

  /// Stop compass tracking
  void _stopCompassTracking() {
    print("🧭 Stopping compass tracking");
    _compassSubscription?.cancel();
    _compassSubscription = null;
  }

  /// Check if user recently touched the screen
  bool _wasRecentUserTouch() {
    if (_lastUserTouchTime == null) return false;

    final now = DateTime.now();
    final timeSinceTouch = now.difference(_lastUserTouchTime!).inMilliseconds;
    return timeSinceTouch < 1500;
  }

  /// Check if this is a recent programmatic camera move
  bool get _isRecentProgrammaticMove {
    if (_lastProgrammaticMoveTime == null) return false;

    final now = DateTime.now();
    final timeSinceMove = now.difference(_lastProgrammaticMoveTime!).inMilliseconds;

    return timeSinceMove < _programmaticMoveDurationMs;
  }

  /// Notify state change listeners
  void _notifyStateChanged() {
    _onStateChanged?.call();
  }

  /// Dispose of all resources
  void dispose() {
    print("🗑️ Disposing NavigationController");

    _compassSubscription?.cancel();
    _compassSubscription = null;

    _userInteractionDebouncer?.cancel();
    _userInteractionDebouncer = null;

    _stopPredictionUpdates(); // ✅ ADD THIS

    _mapController = null;
    _currentUserLocation = null;
    _previousUserLocation = null; // ✅ ADD THIS

    _navigationState = NavigationState.inactive;
    _showRecenterButton = false;
  }
}