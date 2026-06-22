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
  static const double drivingMultiplier   = 1.4;  // 40% longer

  /// Average speeds for ETA calculation (km/h)
  static const double walkingSpeed   = 5.0;
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
  static const int programmaticMoveDurationMs   = 800;
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
  // BLE  —  Spec v3.0
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

  /// LIVE_STREAM characteristic UUID — notify, 100 bytes, 10 Hz
  static const String bleLiveStreamUuid      = '19b10001-e8f2-537e-4f6c-d104768a1214';

  /// EVENT_CHANNEL characteristic UUID — notify + write-without-response, 96 bytes
  static const String bleEventChannelUuid    = '19b10002-e8f2-537e-4f6c-d104768a1214';

  /// LIVE_STREAM packet size in bytes (v3.0)
  static const int bleLiveStreamPacketSize = 108;
  static const int bleEventChannelPacketSize = 96;

  /// Legacy alias — kept so any remaining callers compile without change.
  /// Points to the larger of the two packet sizes.
  @Deprecated('Use bleLiveStreamPacketSize or bleEventChannelPacketSize')

  static const int blePacketSizeLive  = 100; // LIVE_STREAM characteristic
  static const int blePacketSizeEvent = 96;  // EVENT_CHANNEL characteristic

  /// Receive buffer overflow threshold (bytes) — clear when exceeded.
  /// Set to 3 × larger packet size to absorb one full burst without losing data.
  static const int bleBufferOverflowThreshold = 500;

  static const Duration bleDisconnectDebounce = Duration(milliseconds: 300);

  /// How long to wait, after a mid-session BLE disconnect, before giving up on
  /// reconnect-and-recover and synthesising a SESSION_END locally. The glove
  /// keeps recording standalone; this only governs the app-side UI flow.
  static const Duration bleDisconnectSessionTimeout = Duration(seconds: 60);

  /// Below this many compressions, the firmware and the app both treat the
  /// session as trivial — no save, no grade screen, just exit. Must match
  /// STORAGE_MIN_COMPRESSIONS_TO_SAVE in firmware config.h (currently 3).
  static const int minCompressionsToSave = 3;

// ═══════════════════════════════════════════════════════
// GLOVE DIAGNOSTIC
// ═══════════════════════════════════════════════════════
  /// DFPlayer volume range (matches firmware 0–30)
  static const int audioVolumeMin     = 0;
  static const int audioVolumeMax     = 30;
  static const int audioVolumeDefault = 22;

  static const int hapticIntensityDefault = 100;

  /// NeoPixel brightness range (matches firmware 0–255)
  static const int diagLedBrightnessMin     = 0;
  static const int diagLedBrightnessMax     = 255;
  static const int diagLedBrightnessDefault = 180;

  /// CSV ring buffer size (seconds of data at 25Hz = 40ms packets)
  static const int diagCsvBufferSeconds = 30;
  static const int diagCsvMaxRows       = 750;   // 30s × 25Hz

  /// Expected WHO_AM_I value for LSM6DSOX
  static const int lsm6dsoxWhoAmIExpected = 0x6C;

  /// I2C scan channel bit positions
  static const int diagI2cBitPalmImu    = 0;   // CH0 → 0x6B
  static const int diagI2cBitWristImu   = 1;   // CH1 → 0x6A
  static const int diagI2cBitMax30205   = 2;   // CH2 → 0x48
  static const int diagI2cBitGxht30     = 3;   // CH3 → 0x44
  static const int diagI2cBitMax30102R  = 4;   // CH4 → 0x57
  static const int diagI2cBitMax30102P  = 5;   // CH5 → 0x57

  // ═══════════════════════════════════════════════════════
  // DIAGNOSTIC TEST THRESHOLDS
  // Used by the guided "press now / tilt now / breathe on sensor"
  // checks in the glove diagnostic sheet. These are intentionally
  // generous — the goal is to confirm the sensor responds at all,
  // not to verify clinical accuracy.
  // ═══════════════════════════════════════════════════════

  /// Guided-test capture window (how long we record after the user taps Start)
  static const Duration diagTestWindow         = Duration(seconds: 6);
  static const Duration diagTestWindowLong     = Duration(seconds: 15); // PPG, depth integration

  /// History card row count (rolling table of recent samples)
  static const int diagHistoryRows             = 6;

  /// FSR — minimum peak force during "press now" test (N)
  static const double diagFsrTestMinForceN     = 50.0;

  /// IMU — minimum angle swing during "tilt / rotate" test (degrees)
  static const double diagImuTestMinSwingDeg   = 30.0;

  /// MAX30102 patient — minimum quality reached during "cover sensor" test
  static const int    diagPpgPatientTestMinQuality = 40;

  /// MAX30102 rescuer — acceptable HR range during "wear glove" test (BPM)
  static const double diagPpgRescuerTestMinBpm = 40.0;
  static const double diagPpgRescuerTestMaxBpm = 200.0;

  /// MAX30205 — minimum temperature rise during "hold sensor" test (°C)
  static const double diagTempPatientTestMinRiseC = 1.0;

  /// GXHT30 — minimum humidity rise during "breathe on sensor" test (%RH)
  static const double diagHumidityTestMinRise  = 10.0;

  /// Depth integration — required number of force peaks during "5 compressions" test
  static const int    diagDepthTestRequiredPeaks = 5;
  /// Force level (N) that counts as a "peak" for the depth integration test
  static const double diagDepthTestPeakForceN  = 50.0;
  /// Force level (N) below which we consider a peak "complete" (the user released)
  static const double diagDepthTestReleaseN    = 20.0;

  /// Button — required number of presses during the button test
  static const int    diagButtonTestRequiredPresses = 3;

  /// Sparkline visible duration (last N seconds)
  static const int    diagSparklineWindowSec   = 10;

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
  static const double maxAcceptablePauseSec = 10.0;
  static const double minCompliantPauseSec = 3.0;
  static const double plannedWindowAssocToleranceSec = 3.0;
  /// Above this many unplanned pauses, session pause quality is flagged.
  static const int maxAcceptableUnplannedPauseCount = 2;

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
  static const double portraitNavMinSm   = 0.17;  // 1-line title
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