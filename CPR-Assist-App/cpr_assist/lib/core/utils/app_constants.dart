import 'package:google_maps_flutter/google_maps_flutter.dart';

/// **AppConstants — Numeric/duration/string configuration values**
///
/// Rules:
///   - Numbers, durations, strings ONLY.
///   - NO colors → app_colors.dart
///   - NO spacing/sizing → app_spacing.dart
///   - AED map UI panel sizes → AEDMapUIConstants (bottom of this file)
class AppConstants {
  AppConstants._();

  // ═══════════════════════════════════════════════════════
  // DISTANCE & ROUTE ESTIMATION
  // ═══════════════════════════════════════════════════════

  /// Real-world path complexity multipliers vs straight-line distance
  static const double walkingMultiplier   = 1.3;  // 30% longer
  static const double bicyclingMultiplier = 1.2;  // 20% longer
  static const double drivingMultiplier   = 1.4;  // 40% longer

  /// Average speeds for ETA calculation (km/h)
  static const double walkingSpeed   = 5.0;
  static const double bicyclingSpeed = 15.0;
  static const double drivingSpeed   = 40.0;

  // ═══════════════════════════════════════════════════════
  // LOCATION SERVICES
  // ═══════════════════════════════════════════════════════

  static const Duration locationTimeoutLow    = Duration(minutes: 4);
  static const Duration locationTimeoutMedium = Duration(minutes: 6);
  static const Duration locationTimeoutHigh   = Duration(minutes: 8);

  /// Distance filters (meters) — lower = more frequent updates, higher battery use
  static const int locationFilterLowest = 100;
  static const int locationFilterLow    = 50;
  static const int locationFilterMedium = 25;
  static const int locationFilterHigh   = 10;

  static const double locationMinMovement  = 5.0;   // GPS jitter threshold
  static const double locationSigMovement  = 20.0;  // Meaningful position change

  /// How far the user must move (meters) before AED distance cache is invalidated
  static const double cacheInvalidationDistance = 100.0;

  static const Duration locationSettleTime     = Duration(seconds: 30);
  static const Duration improvementTimeout     = Duration(seconds: 30);
  static const int      maxImprovementAttempts = 3;
  static const double   significantImprovement = 50.0; // meters
  static const double   excellentAccuracy      = 15.0; // meters
  static const double   goodAccuracy           = 20.0; // meters

  // ═══════════════════════════════════════════════════════
  // MAP CONFIGURATION
  // ═══════════════════════════════════════════════════════

  static const double  defaultZoom            = 16.0;
  static const double  navigationZoom         = 20.0;  // Close-up turn-by-turn zoom
  static const double  navigationZoomOverview = 18.5;  // Route overview / panel zoom
  static const double  compassOnlyZoom        = 15.0;  // No-GPS compass mode / single AED zoom
  static const double  navigationTilt         = 45.0;
  static const double  greeceZoom             = 6.0;
  static const double  maxMapZoom             = 18.0;
  static const LatLng  greeceCenter           = LatLng(39.0742, 21.8243);

  /// Reroute threshold — distance (meters) user must deviate before recalculating
  static const double rerouteThresholdMeters = 50.0;

  /// Distance from route polyline beyond which user is considered off-route
  static const double offRouteDistanceThreshold = 25.0; // meters

  /// Distance the user must move before a route ETA refresh is triggered
  static const double routeEtaUpdateDistance = 10.0; // meters

  /// Distance improvement required to suggest switching to a closer AED
  static const double closerAedThreshold = 100.0; // meters

  /// Max distance between two points to be considered the "same" AED destination
  static const double sameAedTolerance = 10.0; // meters

  /// User must move this many meters OR routeRefetchIntervalSeconds must pass
  /// before a new route is fetched during active navigation
  static const double routeRefetchDistanceMeters  = 100.0;
  static const int    routeRefetchIntervalSeconds = 30;
  static const int    routeRefetchPeriodicMinutes = 5;

  /// AED arrival radius — user is considered arrived when within this distance
  static const double navigationArrivalRadius = 30.0; // meters

  /// Maximum preloaded route cache size (RAM entries)
  static const int maxPreloadedRoutesCache = 25;

  /// AED marker clustering
  static const double aedClusterRadius  = 80.0; // cluster manager units, NOT meters
  static const int    aedClusterMinSize = 2;

  // ═══════════════════════════════════════════════════════
  // TIMING & INTERVALS
  // ═══════════════════════════════════════════════════════

  static const Duration connectivityCheckInterval = Duration(seconds: 10);
  static const Duration networkTimeout            = Duration(seconds: 30);
  static const Duration apiTimeout                = Duration(seconds: 10);
  static const Duration mapStyleLoadTimeout       = Duration(seconds: 5);

  static const Duration locationMonitoringInterval = Duration(seconds: 2);
  static const Duration locationRetryDelay         = Duration(seconds: 8);
  static const Duration improvementCheckInterval   = Duration(minutes: 2);

  static const Duration mapAnimationDelay  = Duration(milliseconds: 300);
  static const Duration zoomAnimationDelay = Duration(milliseconds: 500);

  /// Navigation camera animation durations (ms)
  static const int navigationRecenterDurationMs   = 600;
  static const int programmaticMoveDurationMs     = 500;

  /// Compass — minimum ms between heading updates (debounce)
  static const int compassDebounceDurationMs = 150;

  /// How long after a user touch the camera is considered "user-controlled"
  static const int userTouchTimeoutMs = 1500;

  static const Duration cacheTtl              = Duration(days: 50);
  static const Duration aedDataStaleThreshold = Duration(hours: 24);

  // ═══════════════════════════════════════════════════════
  // API & DATA FETCHING
  // ═══════════════════════════════════════════════════════

  static const Duration apiCallDelay      = Duration(milliseconds: 200);
  static const Duration routePreloadDelay = Duration(milliseconds: 500);

  static const int maxPreloadedRoutes       = 10;
  static const int maxDistanceCalculations  = 15;

  // ═══════════════════════════════════════════════════════
  // BLE
  // ═══════════════════════════════════════════════════════

  static const String   bleDeviceName        = 'CPR_Glove';
  static const Duration bleReconnectInterval = Duration(seconds: 3);
  static const Duration bleReconnectTimeout  = Duration(seconds: 30);

  /// Delay before first connection attempt at app start
  static const Duration bleInitialDelay      = Duration(milliseconds: 500);

  /// Delay after Bluetooth turns ON before scanning (stabilisation)
  static const Duration bleBluetoothOnDelay  = Duration(seconds: 1);

  /// Delay after device.connect() before discovering services
  static const Duration blePostConnectDelay  = Duration(seconds: 2);

  /// How long a single scan runs before giving up
  static const Duration bleScanTimeout       = Duration(seconds: 15);

  /// How long a single connect() call may take before timing out
  static const Duration bleConnectTimeout    = Duration(seconds: 15);

  /// How long service discovery may take before timing out
  static const Duration bleServiceDiscoveryTimeout = Duration(seconds: 15);

  /// Max consecutive auto-reconnect attempts before requiring manual retry
  static const int bleMaxReconnectAttempts = 5;

  /// BLE receive buffer overflow threshold (bytes) — clear when exceeded
  static const int bleBufferOverflowThreshold = 100;

  /// Expected BLE packet size in bytes
  static const int blePacketSize = 48;

  // ═══════════════════════════════════════════════════════
  // BATTERY THRESHOLDS (percentage)
  // ═══════════════════════════════════════════════════════

  static const int batteryFull     = 80;
  static const int batteryHigh     = 60;
  static const int batteryMedium   = 40;
  static const int batteryLow      = 20;
  static const int batteryCritical = 10;

  // ═══════════════════════════════════════════════════════
  // CPR & TRAINING
  // ═══════════════════════════════════════════════════════

  static const Duration pulseCheckWindow        = Duration(seconds: 10);
  static const double   routeDeviationThreshold = 50.0; // meters
  static const int      maxLocalSessions        = 20;

  // ═══════════════════════════════════════════════════════
  // LOCATION STALENESS
  // ═══════════════════════════════════════════════════════

  /// Number of hours after which a cached location is considered too stale
  /// to show ETA / distance data (shown as "--").
  static const int locationStaleHours = 5;


  // ═══════════════════════════════════════════════════════
  // PERMISSIONS
  // ═══════════════════════════════════════════════════════

  static const String locationPermissionRationale =
      'Location access is needed to find nearby AEDs and provide navigation during emergencies.';
}

// ═══════════════════════════════════════════════════════
// AED MAP UI — panel sizes & map-specific layout
// Kept here because they are feature-specific config,
// not general app spacing (which lives in app_spacing.dart).
// ═══════════════════════════════════════════════════════

class AEDMapUIConstants {
  AEDMapUIConstants._();

  // Panel sizes — Portrait
  static const double portraitListInitial    = 0.25;
  static const double portraitListMin        = 0.25;
  static const double portraitListMax        = 0.55;

  static const double portraitNavInitial     = 0.48;
  static const double portraitNavMin         = 0.20;
  static const double portraitNavMax         = 0.60;

  static const double portraitActiveNavInitial = 0.28;
  static const double portraitActiveNavMin     = 0.28;
  static const double portraitActiveNavMax     = 0.60;

  // Panel sizes — Landscape
  static const double landscapeListInitial   = 0.30;
  static const double landscapeListMin       = 0.30;
  static const double landscapeListMax       = 1.00;

  static const double landscapePanelWidth    = 380.0;
  static const double landscapeButtonOffset  = 390.0;

  // Map control buttons
  static const double recenterButtonSize   = 48.0;
  static const double mapTypeToggleSize    = 40.0;
  static const double logoSize             = 40.0;
  static const double compassControlSize   = 48.0;
  static const double connectivityIconSize = 24.0;

  // Positioning
  static const double recenterButtonBottom = 10.0;
  static const double recenterButtonRight  = 8.0;
  static const double logoPadding          = 14.0;

  // AED card border
  static const double aedCardBorderWidth  = 2.0;
  static const double aedCardBorderRadius = 8.0;

  // Scroll behaviour
  /// Pixel offset at which the "scroll to top" FAB appears in the AED list.
  static const double scrollToTopThreshold = 200.0;

  // Map camera padding
  static const double mapOverviewPadding     = 60.0;  // zoomToUserAndClosestAEDs / route overview
  static const double mapRoutePadding        = 20.0;  // route-specific padding
  static const double mapGhostPaddingFactor  = 0.75;  // ghost point offset for zoomToUserAndAED

  // Z-index layering
  static const double emergencyBannerZIndex = 1000;
  static const double headerZIndex          = 999;
  static const double panelZIndex           = 10;
  static const double mapZIndex             = 1;
}