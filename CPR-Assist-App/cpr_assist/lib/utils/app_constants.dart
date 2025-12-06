import 'package:google_maps_flutter/google_maps_flutter.dart';

class AppConstants {

  // Distance estimation multipliers for offline mode
  static const double walkingMultiplier = 1.3;     // 30% longer than straight line
  static const double bicyclingMultiplier = 1.2;   // 20% longer than straight line
  static const double drivingMultiplier = 1.4;     // 40% longer than straight line

  // Preloading and processing limits
  static const int maxPreloadedRoutes = 2;
  static const int maxDistanceCalculations = 5;

  // API delays
  static const Duration apiCallDelay = Duration(milliseconds: 200);
  static const Duration routePreloadDelay = Duration(milliseconds: 500);

  // Location timeouts
  static const Duration locationTimeoutLow = Duration(minutes: 4);
  static const Duration locationTimeoutMedium = Duration(minutes: 6);
  static const Duration locationTimeoutHigh = Duration(minutes: 8);

  // Location filters
  static const int locationDistanceFilterLowest = 100;
  static const int locationDistanceFilterLow = 50;
  static const int locationDistanceFilterMedium = 25;
  static const int locationDistanceFilterHigh = 10;
  static const double locationMinimumMovement = 5.0;
  static const double locationSignificantMovement = 10.0;

  // Map settings
  static const double defaultZoom = 16.0;
  static const double navigationZoom = 20;
  static const double navigationTilt = 45.0;
  static const double greeceZoom = 6.0;
  static const LatLng greeceCenter = LatLng(39.0742, 21.8243);
  static const Duration cacheTtl = Duration(days: 250);


  // Timing intervals
  static const Duration connectivityCheckInterval = Duration(seconds: 10);
  static const Duration locationMonitoringInterval = Duration(seconds: 2);
  static const Duration locationRetryDelay = Duration(seconds: 8);
  static const Duration improvementCheckInterval = Duration(minutes: 2);
  static const Duration mapAnimationDelay = Duration(milliseconds: 300);
  static const Duration zoomAnimationDelay = Duration(milliseconds: 500);

  // Background improvements
  static const Duration locationSettleTime = Duration(seconds: 30);
  static const Duration improvementTimeout = Duration(seconds: 30);
  static const int maxImprovementAttempts = 3;
  static const double significantImprovement = 50.0;
  static const double excellentAccuracy = 15.0;
  static const double goodAccuracy = 20.0;

  // ETA calculation speeds (km/h)
  static const double walkingSpeed = 5.0;
  static const double bicyclingSpeed = 15.0;
  static const double drivingSpeed = 40.0;
}