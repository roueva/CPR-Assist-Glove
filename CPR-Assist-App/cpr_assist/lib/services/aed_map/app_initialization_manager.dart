import 'dart:async';
import 'package:cpr_assist/services/aed_map/route_service.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/aed_models.dart';
import '../../services/aed_map/aed_service.dart';
import '../../services/aed_map/cache_service.dart';
import '../../services/aed_map/location_service.dart';
import '../../services/network_service.dart';
import '../../utils/safe_fonts.dart';

class InitializationResult {
  final bool hasLocation;
  final LatLng? userLocation;
  final List<AED> aedList;
  final bool isConnected;
  final String? apiKey;
  final bool shouldZoom;

  InitializationResult({
    required this.hasLocation,
    this.userLocation,
    required this.aedList,
    required this.isConnected,
    this.apiKey,
    this.shouldZoom = false,
  });
}

class AppInitializationManager {
  static bool _isInitializing = false;
  static final LocationService _locationService = LocationService();

  /// Main initialization method that runs in background
  static Future<InitializationResult> initializeApp(BuildContext context) async {
    if (_isInitializing) {
      throw Exception("Initialization already in progress");
    }

    _isInitializing = true;
    print("🚀 Starting app initialization...");

    try {
      // Step 1: Initialize lightweight services (UI thread)
      await _initializeLightweightServices();
      print("✅ Lightweight services initialized");

      // Step 2: Check capabilities (parallel execution)
      final futures = await Future.wait([
        _checkLocationCapability(),
        _checkNetworkCapability(),
      ]);

      final hasLocationCapability = futures[0];
      final isConnected = futures[1];

      print("📍 Location capability: $hasLocationCapability");
      print("🌐 Network connected: $isConnected");

      // Step 3: Get user location if possible
      LatLng? userLocation;
      if (hasLocationCapability) {
        userLocation = await _getUserLocation(context);
        print("📍 User location: ${userLocation != null ? 'Found' : 'Not found'}");
      }

      // Step 4: Load AED data (background processing)
      final aedData = await _loadAEDData(isConnected, userLocation);
      print("🏥 Loaded ${aedData.length} AEDs");

      // Step 5: Get API key if connected
      String? apiKey;
      if (isConnected) {
        try {
          apiKey = await NetworkService.fetchGoogleMapsApiKey();
          print("🔑 API key: ${apiKey != null ? 'Retrieved' : 'Failed'}");
        } catch (e) {
          print("⚠️ Failed to get API key: $e");
        }
      }

      final result = InitializationResult(
        hasLocation: userLocation != null,
        userLocation: userLocation,
        aedList: aedData,
        isConnected: isConnected,
        apiKey: apiKey,
        shouldZoom: userLocation != null && aedData.isNotEmpty,
      );

      print("✅ App initialization completed successfully");
      return result;

    } catch (e) {
      print("❌ App initialization failed: $e");
      // Return minimal working state
      return InitializationResult(
        hasLocation: false,
        aedList: [],
        isConnected: false,
      );
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize services that don't block the UI
  static Future<void> _initializeLightweightServices() async {
    try {
      // These are fast and don't block UI
      SafeFonts.initializeFontCache();
      await CacheService.initializeAllCaches();
      NetworkService.startConnectivityMonitoring();
    } catch (e) {
      print("⚠️ Error initializing lightweight services: $e");
      // Continue anyway - these are not critical
    }
  }

  /// Check location capability without requesting permission
  static Future<bool> _checkLocationCapability() async {
    try {
      final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      final hasPermission = await _locationService.hasPermission;
      return isLocationEnabled && hasPermission;
    } catch (e) {
      print("❌ Error checking location capability: $e");
      return false;
    }
  }

  /// Check network connectivity
  static Future<bool> _checkNetworkCapability() async {
    try {
      return await NetworkService.isConnected();
    } catch (e) {
      print("❌ Error checking network: $e");
      return false;
    }
  }

  /// Get user location with UI interaction
  static Future<LatLng?> _getUserLocation(BuildContext context) async {
    try {
      return await _locationService.getCurrentLocationWithUI(
        context: context,
        showPermissionDialog: true,
        showErrorMessages: true,
      );
    } catch (e) {
      print("❌ Error getting user location: $e");
      return null;
    }
  }

  /// Load AED data using background processing for heavy computations
  static Future<List<AED>> _loadAEDData(bool isConnected, LatLng? userLocation) async {
    try {
      // Create AED service with proper NetworkService instance
      // ✅ After: Properly instantiated with SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final networkService = NetworkService(prefs);
      final aedRepository = AEDService(networkService);

      if (isConnected) {
        print("🔄 Fetching fresh AED data...");
        // Try fresh data first
        final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);

        // Process distances in background if we have location
        if (userLocation != null && freshAEDs.isNotEmpty) {
          return await _processAEDDistances(freshAEDs, userLocation);
        }

        return freshAEDs;
      } else {
        print("📦 Loading cached AED data...");
        // Load cached data
        final cachedAEDs = await aedRepository.fetchAEDs(forceRefresh: false);

        // Process distances in background if we have location
        if (userLocation != null && cachedAEDs.isNotEmpty) {
          return await _processAEDDistances(cachedAEDs, userLocation);
        }

        return cachedAEDs;
      }
    } catch (e) {
      print("❌ Error loading AED data: $e");

      // Try to load cached data as fallback
      try {
        final cachedData = await CacheService.getAEDs();
        if (cachedData != null) {
          // You'll need to implement convertFromCache method or similar
          print("📦 Loaded ${cachedData.length} AEDs from cache as fallback");
          return _convertCachedAEDs(cachedData);
        }
      } catch (cacheError) {
        print("❌ Cache fallback also failed: $cacheError");
      }

      return [];
    }
  }

  /// Convert cached AED data to AED list
  static List<AED> _convertCachedAEDs(dynamic cachedData) {
    try {
      // This is a placeholder - implement based on your cache format
      if (cachedData is List) {
        return cachedData.map((item) {
          if (item is Map<String, dynamic>) {
            return AED(
              id: item['id'] ?? 0,
              name: item['name'] ?? '',
              address: item['address'] ?? '',
              location: LatLng(
                item['latitude'] ?? 0.0,
                item['longitude'] ?? 0.0,
              ),
            );
          }
          return null;
        }).where((aed) => aed != null).cast<AED>().toList();
      }
    } catch (e) {
      print("❌ Error converting cached AEDs: $e");
    }
    return [];
  }

  /// Process AED distances - this could be moved to an isolate
  static Future<List<AED>> _processAEDDistances(List<AED> aeds, LatLng userLocation) async {
    print("📏 Processing distances for ${aeds.length} AEDs...");
    return await _calculateDistancesOptimized(aeds, userLocation);
  }

  /// Optimized distance calculation that doesn't block UI
  static Future<List<AED>> _calculateDistancesOptimized(List<AED> aeds, LatLng userLocation) async {
    final processedAEDs = <AED>[];

    // Process in small chunks to avoid blocking UI
    const chunkSize = 10;
    for (int i = 0; i < aeds.length; i += chunkSize) {
      final chunk = aeds.skip(i).take(chunkSize).toList();

      for (final aed in chunk) {
        // Calculate straight-line distance with transport multiplier
        final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
        final multiplier = AEDService.getTransportModeMultiplier('walking'); // default
        final estimatedDistance = straightDistance * multiplier;

        // Cache the distance
        CacheService.setDistance('aed_${aed.id}', estimatedDistance);
        processedAEDs.add(aed);
      }

      // Yield control back to UI thread every chunk
      await Future.delayed(const Duration(microseconds: 1));
    }

    // Sort by distance
    processedAEDs.sort((a, b) {
      final distA = CacheService.getDistance('aed_${a.id}') ?? double.infinity;
      final distB = CacheService.getDistance('aed_${b.id}') ?? double.infinity;
      return distA.compareTo(distB);
    });

    print("✅ Distance processing completed, sorted ${processedAEDs.length} AEDs");
    return processedAEDs;
  }

  /// Background route preloading - can be called after initialization
  static void startBackgroundRoutePreloading({
    required List<AED> aeds,
    required LatLng userLocation,
    required String? apiKey,
    String transportMode = 'walking',
    Function(AED, RouteResult)? onRouteLoaded,
  }) {
    if (apiKey == null || aeds.isEmpty) {
      print("⚠️ Skipping route preloading - missing API key or AEDs");
      return;
    }

    print("🛣️ Starting background route preloading for ${aeds.length} AEDs");

    // Run in background without blocking UI
    Future.microtask(() async {
      try {
        // ✅ After: Properly instantiated with SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final networkService = NetworkService(prefs);
        final aedRepository = AEDService(networkService);

        // Process closest AEDs first (limit to prevent excessive API calls)
        final closestAEDs = aeds.take(5).toList();

        for (final aed in closestAEDs) {
          try {
            // This is a placeholder - you'll need to implement route preloading
            // based on your RouteService implementation
            await _preloadRouteForAED(aed, userLocation, transportMode, apiKey, onRouteLoaded);

            // Add delay to respect API rate limits
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            print("⚠️ Failed to preload route for AED ${aed.id}: $e");
          }
        }

        print("✅ Background route preloading completed");
      } catch (e) {
        print("❌ Background route preloading failed: $e");
      }
    });
  }

  /// Preload route for a single AED
  static Future<void> _preloadRouteForAED(
      AED aed,
      LatLng userLocation,
      String transportMode,
      String apiKey,
      Function(AED, RouteResult)? onRouteLoaded,
      ) async {
    try {
      // Check if route is already cached
      final cachedRoute = CacheService.getCachedRoute(userLocation, aed.location, transportMode);
      if (cachedRoute != null) {
        onRouteLoaded?.call(aed, cachedRoute);
        return;
      }

      // Create a simple offline route result as fallback
      // You should replace this with actual route fetching logic
      final estimatedDistance = LocationService.distanceBetween(userLocation, aed.location);
      final estimatedTime = LocationService.calculateOfflineETA(estimatedDistance, transportMode);

      final routeResult = RouteResult(
        polyline: Polyline(
          polylineId: PolylineId('route_${aed.id}'),
          points: [userLocation, aed.location], // Simple straight line
          color: Colors.blue,
          width: 3,
        ),
        duration: estimatedTime,
        points: [userLocation, aed.location],
        isOffline: true,
        actualDistance: estimatedDistance,
        distanceText: LocationService.formatDistance(estimatedDistance),
      );

      // Cache the route
      CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult);

      onRouteLoaded?.call(aed, routeResult);
      print("✅ Preloaded route for AED ${aed.id}");
    } catch (e) {
      print("❌ Error preloading route for AED ${aed.id}: $e");
    }
  }

  /// Background distance improvement - can be called after initialization
  static void startBackgroundDistanceImprovement({
    required List<AED> aeds,
    required LatLng userLocation,
    required String transportMode,
    required String? apiKey,
    required Function(List<AED>) onUpdated,
  }) {
    if (apiKey == null || aeds.isEmpty) {
      print("⚠️ Skipping distance improvement - missing API key or AEDs");
      return;
    }

    print("📏 Starting background distance improvement for ${aeds.length} AEDs");

    // Run in background without blocking UI
    Future.microtask(() async {
      try {
        // ✅ After: Properly instantiated with SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final networkService = NetworkService(prefs);
        final aedRepository = AEDService(networkService);

        await aedRepository.improveDistanceAccuracyInBackground(
          aeds,
          userLocation,
          transportMode,
          apiKey,
          onUpdated,
        );

        print("✅ Background distance improvement completed");
      } catch (e) {
        print("❌ Background distance improvement failed: $e");
      }
    });
  }

  /// Check if initialization is currently in progress
  static bool get isInitializing => _isInitializing;

  /// Force stop initialization (use with caution)
  static void forceStopInitialization() {
    _isInitializing = false;
    print("⚠️ Initialization force stopped");
  }
}

// Helper class for isolate communication (future enhancement)
class IsolateMessage {
  final String type;
  final Map<String, dynamic> data;

  IsolateMessage(this.type, this.data);

  Map<String, dynamic> toJson() => {
    'type': type,
    'data': data,
  };

  factory IsolateMessage.fromJson(Map<String, dynamic> json) {
    return IsolateMessage(json['type'], json['data']);
  }
}

// Extension for location service if needed
extension LocationServiceExtensions on LocationService {
  /// Calculate offline ETA (if not already implemented)
  static String calculateOfflineETA(double distanceInMeters, String transportMode) {
    // Average speeds in m/s
    const double walkingSpeed = 1.4; // ~5 km/h
    const double drivingSpeed = 13.9; // ~50 km/h (city driving)
    const double cyclingSpeed = 4.2; // ~15 km/h

    double speed;
    switch (transportMode.toLowerCase()) {
      case 'walking':
        speed = walkingSpeed;
        break;
      case 'driving':
        speed = drivingSpeed;
        break;
      case 'cycling':
        speed = cyclingSpeed;
        break;
      default:
        speed = walkingSpeed;
    }

    final timeInSeconds = distanceInMeters / speed;
    final minutes = (timeInSeconds / 60).round();

    if (minutes < 1) {
      return "< 1 min";
    } else if (minutes < 60) {
      return "$minutes min";
    } else {
      final hours = (minutes / 60).floor();
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return "$hours h";
      } else {
        return "$hours h $remainingMinutes min";
      }
    }
  }

  /// Format distance (if not already implemented)
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return "${distanceInMeters.round()} m";
    } else {
      final km = distanceInMeters / 1000;
      if (km < 10) {
        return "${km.toStringAsFixed(1)} km";
      } else {
        return "${km.round()} km";
      }
    }
  }
}