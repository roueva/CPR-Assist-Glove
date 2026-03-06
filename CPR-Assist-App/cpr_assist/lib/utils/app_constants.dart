import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// **Application-wide constants for CPR Assist**
///
/// Organized by functional area:
/// - Distance & Route Estimation
/// - Location Services
/// - Map Configuration
/// - Timing & Intervals
/// - BLE & Battery
/// - Network & API
/// - UI Layout
class AppConstants {
  // ========================================
  // DISTANCE & ROUTE ESTIMATION
  // ========================================

  /// Distance multipliers for offline route estimation
  /// These account for real-world path complexity vs straight-line distance
  static const double walkingMultiplier = 1.3;      // 30% longer (sidewalks, crossings)
  static const double bicyclingMultiplier = 1.2;    // 20% longer (bike lanes, fewer detours)
  static const double drivingMultiplier = 1.4;      // 40% longer (one-way streets, traffic rules)

  /// Average speeds for ETA calculation (km/h)
  static const double walkingSpeed = 5.0;           // Standard walking pace
  static const double bicyclingSpeed = 15.0;        // Casual cycling speed
  static const double drivingSpeed = 40.0;          // Urban driving average

  // ========================================
  // LOCATION SERVICES
  // ========================================

  /// Location service timeouts based on accuracy priority
  static const Duration locationTimeoutLow = Duration(minutes: 4);      // Coarse location OK
  static const Duration locationTimeoutMedium = Duration(minutes: 6);   // Balanced
  static const Duration locationTimeoutHigh = Duration(minutes: 8);     // High accuracy needed

  /// Location update distance filters (meters)
  /// Lower values = more frequent updates but higher battery use
  static const int locationDistanceFilterLowest = 100;   // Very coarse tracking
  static const int locationDistanceFilterLow = 50;       // Moderate tracking
  static const int locationDistanceFilterMedium = 25;    // Active navigation
  static const int locationDistanceFilterHigh = 10;      // Precise navigation

  /// Movement thresholds for location significance
  static const double locationMinimumMovement = 5.0;         // Meters - ignore GPS jitter
  static const double locationSignificantMovement = 20.0;    // Meters - meaningful position change

  /// Background location improvement settings
  static const Duration locationSettleTime = Duration(seconds: 30);       // Wait before improvement attempts
  static const Duration improvementTimeout = Duration(seconds: 30);       // Max time for improvement
  static const int maxImprovementAttempts = 3;                           // Retry limit
  static const double significantImprovement = 50.0;                     // Meters - worthwhile improvement
  static const double excellentAccuracy = 15.0;                          // Meters - excellent GPS
  static const double goodAccuracy = 20.0;                               // Meters - acceptable GPS

  // ========================================
  // MAP CONFIGURATION
  // ========================================

  /// Default map camera positions
  static const double defaultZoom = 16.0;            // Standard view with nearby AEDs
  static const double navigationZoom = 20.0;         // Close-up during navigation
  static const double navigationTilt = 45.0;         // 3D perspective during navigation
  static const double greeceZoom = 6.0;              // Country-wide view (fallback)
  static const LatLng greeceCenter = LatLng(39.0742, 21.8243);  // Geographic center of Greece

  /// AED marker clustering
  static const double aedClusterRadius = 80.0;  // Cluster manager units (NOT meters)
  static const int aedClusterMinSize = 2;            // Minimum AEDs to form cluster

  // ========================================
  // TIMING & INTERVALS
  // ========================================

  /// Network & connectivity monitoring
  static const Duration connectivityCheckInterval = Duration(seconds: 10);
  static const Duration networkTimeout = Duration(seconds: 30);
  static const Duration apiTimeout = Duration(seconds: 10);

  /// Location monitoring intervals
  static const Duration locationMonitoringInterval = Duration(seconds: 2);   // Active tracking frequency
  static const Duration locationRetryDelay = Duration(seconds: 8);           // Retry after failure
  static const Duration improvementCheckInterval = Duration(minutes: 2);     // Background improvement check

  /// Map animation timings
  static const Duration mapAnimationDelay = Duration(milliseconds: 300);
  static const Duration zoomAnimationDelay = Duration(milliseconds: 500);

  /// Cache time-to-live
  static const Duration cacheTtl = Duration(days: 50);                     // AED data staleness limit
  static const Duration aedDataStaleThreshold = Duration(hours: 24);        // Show "updated X ago" warning

  // ========================================
  // API & DATA FETCHING
  // ========================================

  /// Rate limiting for API calls
  static const Duration apiCallDelay = Duration(milliseconds: 200);          // Min time between calls
  static const Duration routePreloadDelay = Duration(milliseconds: 500);     // Delay before preloading routes

  /// Batch processing limits
  static const int maxPreloadedRoutes = 10;              // Top AEDs to preload routes for
  static const int maxDistanceCalculations = 15;         // AEDs to improve distance accuracy for

  // ========================================
  // BLE & BATTERY
  // ========================================

  /// BLE connection management
  static const String bleDeviceName = "CPR_Glove";
  static const Duration bleReconnectInterval = Duration(seconds: 3);     // Time between reconnect attempts
  static const Duration bleReconnectTimeout = Duration(seconds: 30);     // Give up after this duration

  /// Battery level thresholds (percentage)
  static const int batteryFull = 80;          // 80-100%
  static const int batteryHigh = 60;          // 60-79%
  static const int batteryMedium = 40;        // 40-59%
  static const int batteryLow = 20;           // 20-39%
  static const int batteryCritical = 10;      // Below 20%

  // ========================================
  // CPR & TRAINING
  // ========================================

  /// Pulse check timing
  static const Duration pulseCheckWindow = Duration(seconds: 10);        // Time to check for pulse after compressions stop

  /// Route deviation
  static const double routeDeviationThreshold = 50.0;                    // Meters - trigger route recalculation

  /// Session storage
  static const int maxLocalSessionsStored = 20;                          // Max training sessions in local storage

  // ========================================
  // LOCATION PERMISSION
  // ========================================

  /// User-facing permission rationale
  static const String locationPermissionRationale =
      "Location access is needed to find nearby AEDs and provide navigation during emergencies.";
}

// ========================================
// UI LAYOUT CONSTANTS
// ========================================

class AEDMapUIConstants {
  // Panel sizes - Portrait orientation
  static const double portraitListInitial = 0.20;     // 20% of screen height
  static const double portraitListMin = 0.20;
  static const double portraitListMax = 0.55;         // Max expansion

  static const double portraitNavInitial = 0.48;      // AED preview panel
  static const double portraitNavMin = 0.20;
  static const double portraitNavMax = 0.6;

  static const double portraitActiveNavInitial = 0.25; // During navigation
  static const double portraitActiveNavMin = 0.25;
  static const double portraitActiveNavMax = 0.6;

  // Panel sizes - Landscape orientation
  static const double landscapeListInitial = 0.3;
  static const double landscapeListMin = 0.3;
  static const double landscapeListMax = 1.0;

  static const double landscapePanelWidth = 380.0;     // Fixed width for side panel
  static const double landscapeButtonOffset = 390.0;   // Offset for buttons to avoid panel

  // Button & control sizes
  static const double recenterButtonSize = 40.0;
  static const double mapTypeToggleSize = 40.0;
  static const double logoSize = 40.0;
  static const double compassControlSize = 48.0;
  static const double connectivityIconSize = 24.0;

  // Touch targets (accessibility compliance)
  static const double minTouchTarget = 44.0;           // WCAG minimum
  static const double largeTouchTarget = 56.0;         // Emergency actions (112 call, navigation)

  // Spacing & padding
  static const double standardPadding = 16.0;
  static const double cardSpacing = 6.0;
  static const double dragHandleWidth = 40.0;
  static const double dragHandleHeight = 4.0;

  // Offsets & positioning
  static const double recenterButtonBottom = 10.0;
  static const double recenterButtonRight = 8.0;
  static const double logoPadding = 14.0;

  // Emergency call banner
  static const double emergencyBannerHeight = 56.0;

  // AED card styling
  static const double aedCardBorderWidth = 2.0;        // Green border for accessible AEDs
  static const double aedCardBorderRadius = 8.0;

  // Z-index layering
  static const double emergencyBannerZIndex = 1000;    // Always on top
  static const double headerZIndex = 999;
  static const double panelZIndex = 10;
  static const double mapZIndex = 1;
}

// ========================================
// COLOR PALETTE
// ========================================

class AppColors {
  // ===== Brand Colors =====
  static const Color primary = Color(0xFF194E9D);          // CPR Assist Blue
  static const Color secondary = Color(0xFFEDF4F9);        // Light Blue Background

  // ===== Semantic Colors (Material Design) =====
  static const Color success = Color(0xFF2E7D32);          // Material Green 700
  static const Color warning = Color(0xFFF57C00);          // Material Orange 700
  static const Color error = Color(0xFFD32F2F);            // Material Red 700
  static const Color info = Color(0xFF1976D2);             // Material Blue 700

  // ===== CPR-Specific Colors =====
  static const Color emergencyRed = Color(0xFFB71C1C);     // Emergency call banner
  static const Color cprGreen = Color(0xFF2E7D32);         // Correct compression feedback
  static const Color cprOrange = Color(0xFFF57C00);        // Needs improvement feedback
  static const Color cprRed = Color(0xFFD32F2F);           // Incorrect compression feedback

  // ===== Text Hierarchy (Material Grey) =====
  static const Color textPrimary = Color(0xFF212121);      // Material Grey 900
  static const Color textSecondary = Color(0xFF757575);    // Material Grey 600
  static const Color textDisabled = Color(0xFF9E9E9E);     // Material Grey 500
  static const Color textHint = Color(0xFFBDBDBD);         // Material Grey 400

  // ===== Backgrounds =====
  static const Color cardBackground = Color(0xFFEDF4F9);   // Light blue card
  static const Color screenBackground = Colors.white;       // Main background
  static const Color overlayBackground = Color(0x80000000); // 50% black overlay
  static const Color headerBackground = Color(0xFFFFFFFF);  // White header (changes per screen)

  // ===== AED Map Specific =====
  static const Color clusterGreen = Color(0xFF2E7D32);     // Cluster marker color
  static const Color aedOpenBorder = Color(0xFF2E7D32);    // Green border for accessible AEDs
  static const double aedClosedOpacity = 0.5;                // Opacity for closed AEDs

  // ===== BLE Status Indicator =====
  static const Color bleConnected = Color(0xFF2E7D32);     // Green - connected
  static const Color bleDisconnected = Color(0xFF757575);  // Grey - disconnected
  static const Color bleScanning = Color(0xFFF57C00);      // Orange - searching
}