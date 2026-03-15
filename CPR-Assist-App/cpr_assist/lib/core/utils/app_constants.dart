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

  static const double accountPanelWidthFraction = 0.82;
  static const double qrCodeSize = 180.0;

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
  static const double  navigationZoom         = 20.0;
  static const double  navigationZoomOverview = 18.5;
  static const double  compassOnlyZoom        = 15.0;
  static const double  navigationTilt         = 45.0;
  static const double  greeceZoom             = 6.0;
  static const double  maxMapZoom             = 18.0;
  static const LatLng  greeceCenter           = LatLng(39.0742, 21.8243);

  static const double rerouteThresholdMeters      = 50.0;
  static const double offRouteDistanceThreshold   = 25.0;
  static const double routeEtaUpdateDistance      = 10.0;
  static const double closerAedThreshold          = 100.0;
  static const double sameAedTolerance            = 10.0;
  static const double routeRefetchDistanceMeters  = 100.0;
  static const int    routeRefetchIntervalSeconds = 30;
  static const int    routeRefetchPeriodicMinutes = 5;
  static const double navigationArrivalRadius     = 30.0;
  static const int    maxPreloadedRoutesCache      = 25;
  static const double aedClusterRadius             = 80.0;
  static const int    aedClusterMinSize            = 2;

  // ═══════════════════════════════════════════════════════
  // TIMING & INTERVALS
  // ═══════════════════════════════════════════════════════

  static const Duration connectivityCheckInterval  = Duration(seconds: 10);
  static const Duration networkTimeout             = Duration(seconds: 30);
  static const Duration apiTimeout                 = Duration(seconds: 10);
  static const Duration mapStyleLoadTimeout        = Duration(seconds: 5);

  static const Duration locationMonitoringInterval = Duration(seconds: 2);
  static const Duration locationRetryDelay         = Duration(seconds: 8);
  static const Duration improvementCheckInterval   = Duration(minutes: 2);

  static const Duration mapAnimationDelay  = Duration(milliseconds: 300);
  static const Duration zoomAnimationDelay = Duration(milliseconds: 500);

  static const int navigationRecenterDurationMs = 600;
  static const int programmaticMoveDurationMs   = 500;
  static const int compassDebounceDurationMs    = 50;
  static const int userTouchTimeoutMs           = 3000;

  static const Duration cacheTtl              = Duration(days: 50);
  static const Duration aedDataStaleThreshold = Duration(hours: 24);

  // ═══════════════════════════════════════════════════════
  // API & DATA FETCHING
  // ═══════════════════════════════════════════════════════

  static const Duration apiCallDelay      = Duration(milliseconds: 200);
  static const Duration routePreloadDelay = Duration(milliseconds: 500);

  static const int maxPreloadedRoutes      = 10;
  static const int maxDistanceCalculations = 15;

  // ═══════════════════════════════════════════════════════
  // BLE  —  Spec v2.0
  // ═══════════════════════════════════════════════════════

  static const String   bleDeviceName        = 'CPR_Glove';
  static const Duration bleReconnectInterval = Duration(seconds: 3);
  static const Duration bleReconnectTimeout  = Duration(seconds: 30);
  static const Duration bleInitialDelay      = Duration(milliseconds: 500);
  static const Duration bleBluetoothOnDelay  = Duration(seconds: 1);
  static const Duration blePostConnectDelay  = Duration(seconds: 2);
  static const Duration bleScanTimeout       = Duration(seconds: 15);
  static const Duration bleConnectTimeout    = Duration(seconds: 15);
  static const Duration bleServiceDiscoveryTimeout = Duration(seconds: 15);
  static const int      bleMaxReconnectAttempts    = 5;

  /// BLE GATT service UUID
  static const String bleServiceUuid         = '19b10000-e8f2-537e-4f6c-d104768a1214';

  /// LIVE_STREAM characteristic UUID — notify, 88 bytes, 10 Hz
  static const String bleLiveStreamUuid      = '19b10001-e8f2-537e-4f6c-d104768a1214';

  /// EVENT_CHANNEL characteristic UUID — notify + write-without-response, 80 bytes
  static const String bleEventChannelUuid    = '19b10002-e8f2-537e-4f6c-d104768a1214';

  /// LIVE_STREAM packet size in bytes (v2.0)
  static const int bleLiveStreamPacketSize   = 88;

  /// EVENT_CHANNEL packet size in bytes (v2.0)
  static const int bleEventChannelPacketSize = 80;

  /// Legacy alias — kept so any remaining callers compile without change.
  /// Points to the larger of the two packet sizes.
  @Deprecated('Use bleLiveStreamPacketSize or bleEventChannelPacketSize')
  static const int blePacketSize = 88;

  /// Receive buffer overflow threshold (bytes) — clear when exceeded.
  /// Set to 3 × larger packet size to absorb one full burst without losing data.
  static const int bleBufferOverflowThreshold = 264; // 3 × 88

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
  static const double   routeDeviationThreshold = 50.0;
  static const int      maxLocalSessions        = 20;

  // ═══════════════════════════════════════════════════════
  // LOCATION STALENESS
  // ═══════════════════════════════════════════════════════

  static const int locationStaleHours = 5;

  // ═══════════════════════════════════════════════════════
  // PERMISSIONS
  // ═══════════════════════════════════════════════════════

  static const String locationPermissionRationale =
      'Location access is needed to find nearby AEDs and provide navigation during emergencies.';
}

// ═══════════════════════════════════════════════════════
// AED MAP UI — panel sizes & map-specific layout
// ═══════════════════════════════════════════════════════

class AEDMapUIConstants {
  AEDMapUIConstants._();

  static const double portraitListInitial    = 0.25;
  static const double portraitListMin        = 0.25;
  static const double portraitListMax        = 0.55;

  static const double portraitNavInitial     = 0.48;
  static const double portraitNavMin         = 0.20;
  static const double portraitNavMax         = 0.60;

  static const double portraitActiveNavInitial = 0.28;
  static const double portraitActiveNavMin     = 0.28;
  static const double portraitActiveNavMax     = 0.60;

  static const double landscapeListInitial   = 0.30;
  static const double landscapeListMin       = 0.30;
  static const double landscapeListMax       = 1.00;

  static const double landscapePanelWidth    = 380.0;
  static const double landscapeButtonOffset  = 390.0;

  static const double recenterButtonSize   = 48.0;
  static const double mapTypeToggleSize    = 40.0;
  static const double logoSize             = 40.0;
  static const double compassControlSize   = 48.0;
  static const double connectivityIconSize = 24.0;

  static const double recenterButtonBottom = 10.0;
  static const double recenterButtonRight  = 8.0;
  static const double logoPadding          = 14.0;

  static const double aedCardBorderWidth  = 2.0;
  static const double aedCardBorderRadius = 8.0;

  static const double scrollToTopThreshold = 200.0;

  static const double mapOverviewPadding    = 60.0;
  static const double mapRoutePadding       = 20.0;
  static const double mapGhostPaddingFactor = 0.75;

  static const double emergencyBannerZIndex = 1000;
  static const double headerZIndex          = 999;
  static const double panelZIndex           = 10;
  static const double mapZIndex             = 1;
}