import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
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
  final bool isLocationCached;
  final DateTime? locationAge;

  InitializationResult({
    required this.hasLocation,
    this.userLocation,
    required this.aedList,
    required this.isConnected,
    this.apiKey,
    this.shouldZoom = false,
    this.isLocationCached = false,
    this.locationAge,
  });
}

class AppInitializationManager {
  static bool _isInitializing = false;
  static final LocationService _locationService = LocationService();

  /// Main initialization - call this from your widget
  static Future<InitializationResult> initializeApp(
      AEDService aedRepository,
      NetworkService networkService,
      ) async {
    if (_isInitializing) {
      print("⚠️ Initialization already in progress");
      throw Exception("Initialization already in progress");
    }

    _isInitializing = true;
    print("🚀 Starting app initialization...");

    try {
      // STEP 1: Initialize lightweight services (fast)
      await _initializeLightweightServices();
      print("✅ Lightweight services initialized");

      // STEP 2: Check capabilities (parallel)
      final isConnected = await NetworkService.isConnected();
      print("🌐 Network: $isConnected");

      // STEP 3: Load cached location (instant)
      final cachedLocationData = await _loadCachedLocation();
      print("📍 Cached location: ${cachedLocationData['location'] != null ? 'Found' : 'None'}");

      // STEP 4: Load cached AEDs (instant display)
      final cachedAEDs = await _loadCachedAEDs(aedRepository, cachedLocationData['location']);
      print("📦 Cached AEDs: ${cachedAEDs.length}");

      // STEP 5: Get API key if online
      String? apiKey;
      if (isConnected) {
        apiKey = await NetworkService.fetchGoogleMapsApiKey();
        print("🔑 API key: ${apiKey != null ? 'Retrieved' : 'Failed'}");
      }

      // Return initial result with cached data
      return InitializationResult(
        hasLocation: cachedLocationData['location'] != null,
        userLocation: cachedLocationData['location'],
        aedList: cachedAEDs.take(10).toList(), // Only 10 closest for instant display
        isConnected: isConnected,
        apiKey: apiKey,
        shouldZoom: cachedLocationData['location'] != null && cachedAEDs.isNotEmpty,
        isLocationCached: cachedLocationData['isCached'] ?? false,
        locationAge: cachedLocationData['age'],
      );

    } catch (e) {
      print("❌ App initialization failed: $e");
      return InitializationResult(
        hasLocation: false,
        aedList: [],
        isConnected: false,
      );
    } finally {
      _isInitializing = false;
    }
  }

  /// Initialize fast services
  static Future<void> _initializeLightweightServices() async {
    try {
      SafeFonts.initializeFontCache();
      await CacheService.initializeAllCaches();
      NetworkService.startConnectivityMonitoring();
    } catch (e) {
      print("⚠️ Error initializing services: $e");
    }
  }

  /// Load cached location
  static Future<Map<String, dynamic>> _loadCachedLocation() async {
    try {
      final cachedAppState = await CacheService.getLastAppState();
      if (cachedAppState != null) {
        final lat = cachedAppState['latitude'] as double?;
        final lng = cachedAppState['longitude'] as double?;
        final timestamp = cachedAppState['timestamp'] as int?;

        if (lat != null && lng != null) {
          final location = LatLng(lat, lng);
          final age = timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              : null;

          return {
            'location': location,
            'isCached': true,
            'age': age,
          };
        }
      }
    } catch (e) {
      print("⚠️ Error loading cached location: $e");
    }

    return {'location': null, 'isCached': false, 'age': null};
  }

  /// Load cached AEDs
  static Future<List<AED>> _loadCachedAEDs(
      AEDService aedRepository, // 👈 ACCEPT service as parameter
      LatLng? userLocation,
      ) async {
    try {

      final cachedData = await CacheService.getAEDs();
      if (cachedData == null) {
        print("📦 No cached AEDs found");
        return [];
      }

    // Use the correct factory from aed_models.dart
      final aedList = cachedData
          .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
          .whereType<AED>()
          .toList();

      // Sort by distance if we have location
      if (userLocation != null && aedList.isNotEmpty) {
        return aedRepository.sortAEDsByDistance(
          aedList,
          userLocation,
          'walking',
        );
      }

      return aedList;
    } catch (e) {
      print("❌ Error loading cached AEDs: $e");
      return [];
    }
  }

  /// Request GPS location (call this separately from widget)
  static Future<LatLng?> requestUserLocation(BuildContext context) async {
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

  /// Fetch fresh AEDs (call this in background)
  static Future<List<AED>> fetchFreshAEDs(AEDService aedRepository,
      {
    required bool isConnected,
    LatLng? userLocation,
    String transportMode = 'walking',
  }) async {
    try {
      // Fetch AEDs
      final aeds = await aedRepository.fetchAEDs(forceRefresh: isConnected);

      if (aeds.isEmpty) return [];

      // Sort by distance if we have location
      if (userLocation != null) {
        return aedRepository.sortAEDsByDistance(
          aeds,
          userLocation,
          transportMode,
        );
      }

      return aeds;
    } catch (e) {
      print("❌ Error fetching fresh AEDs: $e");
      return [];
    }
  }

  /// Calculate distances for AEDs (call this in background)
  static Future<void> calculateDistances({
    required List<AED> aeds,
    required LatLng userLocation,
    String transportMode = 'walking',
  }) async {
    const batchSize = 100;
    final multiplier = AEDService.getTransportModeMultiplier(transportMode);

    for (int i = 0; i < aeds.length; i += batchSize) {
      final batch = aeds.skip(i).take(batchSize).toList();

      for (final aed in batch) {
        final straightDistance = LocationService.distanceBetween(
          userLocation,
          aed.location,
        );
        final estimatedDistance = straightDistance * multiplier;
        CacheService.setDistance('aed_${aed.id}', estimatedDistance);
      }

      // Yield to UI thread
      await Future.delayed(const Duration(microseconds: 1));
    }

    print("✅ Calculated distances for ${aeds.length} AEDs");
  }

  /// Improve distance accuracy with API (call this in background)
  static Future<void> improveDistanceAccuracy(AEDService aedRepository,
      {
    required List<AED> aeds,
    required LatLng userLocation,
    required String transportMode,
    required String? apiKey,
    required Function(List<AED>) onUpdated,
  }) async {
    if (apiKey == null || aeds.isEmpty) {
      print("⚠️ Skipping distance improvement - missing API key or AEDs");
      return;
    }

    try {

      await aedRepository.improveDistanceAccuracyInBackground(
        aeds,
        userLocation,
        transportMode,
        apiKey,
        onUpdated,
      );

      print("✅ Distance improvement completed");
    } catch (e) {
      print("❌ Distance improvement failed: $e");
    }
  }

  /// Check if location service is available
  static Future<bool> isLocationAvailable() async {
    try {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      final hasPermission = await _locationService.hasPermission;
      return isEnabled && hasPermission;
    } catch (e) {
      print("❌ Error checking location: $e");
      return false;
    }
  }

  /// Get current initialization status
  static bool get isInitializing => _isInitializing;
}