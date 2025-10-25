import 'dart:async';
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

  static const int _programmaticMoveDurationMs = 250;

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

    // If we're in compass tracking mode, update camera with new location
    if (_navigationState == NavigationState.compassTracking && _currentHeading != null) {
      _updateCameraWithCompass(_currentHeading!);
    }
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
      // Could show a dialog to user here
      return;
    }

    _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
      if (_navigationState != NavigationState.compassTracking) return;
      if (event.heading == null || _mapController == null) return;

      // Handle compass accuracy if available
      if (event.accuracy != null) {
        _handleCompassAccuracy(event.accuracy!);
      }

      // Throttle compass updates
      final now = DateTime.now();
      if (_lastCompassUpdate != null &&
          now.difference(_lastCompassUpdate!).inMilliseconds < 100) {
        return;
      }
      _lastCompassUpdate = now;

      // Smooth bearing interpolation
      if (_currentHeading != null) {
        final bearingDiff = (event.heading! - _currentHeading!).abs();
        if (bearingDiff < 1.0) return; // Skip tiny changes

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

    // Don't override recent user touches
    if (_wasRecentUserTouch()) {
      print("🧭 Compass move skipped - user recently touched screen");
      return;
    }

    _lastProgrammaticMoveTime = DateTime.now();
    print("🧭 COMPASS MOVE: Bearing ${heading.toStringAsFixed(1)}°");

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _currentUserLocation!,
          zoom: AppConstants.navigationZoom,
          tilt: AppConstants.navigationTilt,
          bearing: heading,
        ),
      ),
      duration: const Duration(milliseconds: 150),
    );
  }

  /// Handle camera move started events
  void onCameraMoveStarted() {
    if (_navigationState == NavigationState.inactive || _isRecentProgrammaticMove) {
      // Check if this is a genuine user interaction
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
    if (_navigationState != NavigationState.compassTracking || _isRecentProgrammaticMove) {
      // Check if this is a genuine user interaction
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

    _currentUserLocation = userLocation;
    _navigationState = NavigationState.compassTracking;
    _showRecenterButton = false;
    _onRecenterButtonVisibilityChanged?.call(false);

    if (_mapController != null) {
      double targetBearing = _currentHeading ?? 0.0;

      // Try to get current compass reading for more accurate recentering
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

      // Fallback if compass stream is not available
      if (FlutterCompass.events == null) {
        _performRecenterAnimation(userLocation, targetBearing);
      }
    }
  }

  /// Perform the recenter animation
  void _performRecenterAnimation(LatLng userLocation, double bearing) {
    _lastProgrammaticMoveTime = DateTime.now();

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: userLocation,
          zoom: AppConstants.navigationZoom,
          tilt: AppConstants.navigationTilt,
          bearing: bearing,
        ),
      ),
    ).then((_) {
      print("🎯 Recenter animation completed - resuming compass tracking");
      _notifyStateChanged();
    }).catchError((error) {
      print("⚠️ Recenter animation failed: $error");
    });
  }

  /// Cancel navigation and return to normal mode
  void cancelNavigation() {
    print("🛑 Cancelling navigation");

    _navigationState = NavigationState.inactive;
    _showRecenterButton = false;
    _stopCompassTracking();
    _userInteractionDebouncer?.cancel();
    _onRecenterButtonVisibilityChanged?.call(false);
    _notifyStateChanged();
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

    // If user touched screen within last 500ms, consider it user interaction
    return timeSinceTouch < 500;
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
    _stopCompassTracking();
    _userInteractionDebouncer?.cancel();
    _mapController = null;
    _currentUserLocation = null;
  }
}