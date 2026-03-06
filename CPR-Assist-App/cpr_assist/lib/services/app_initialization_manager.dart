import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/aed_models.dart';
import 'aed_map/aed_service.dart';
import 'aed_map/cache_service.dart';
import 'aed_map/location_service.dart';
import 'network_service.dart';
import '../utils/safe_fonts.dart';

// ========================================
// INITIALIZATION RESULT MODEL
// ========================================

class InitializationResult {
  final bool hasLocation;
  final LatLng? userLocation;
  final List<AED> aedList;
  final bool isConnected;
  final String? apiKey;
  final bool shouldZoom;
  final LocationDataSource locationSource;
  final AEDDataSource aedSource;
  final DateTime? locationAge;
  final DateTime? aedAge;

  InitializationResult({
    required this.hasLocation,
    this.userLocation,
    required this.aedList,
    required this.isConnected,
    this.apiKey,
    this.shouldZoom = false,
    this.locationSource = LocationDataSource.none,
    this.aedSource = AEDDataSource.empty,
    this.locationAge,
    this.aedAge,
  });

  bool get hasValidData => aedList.isNotEmpty;
  bool get isLocationCached => locationSource == LocationDataSource.cached;
  bool get areAEDsCached => aedSource == AEDDataSource.cached;
}

List<AED> _parseAEDsIsolate(List<dynamic> rawData) {
  final result = <AED>[];
  for (final item in rawData) {
    try {
      if (item is Map<String, dynamic>) {
        result.add(AED.fromMap(item));
      }
    } catch (_) {}
  }
  return result;
}

List<AED> _sortAEDsIsolate(Map<String, dynamic> params) {
  final aeds = params['aeds'] as List<AED>;
  final location = LatLng(params['lat'] as double, params['lng'] as double);
  // Simple straight-line sort for cache load — no CacheService in isolate
  aeds.sort((a, b) {
    final dA = Geolocator.distanceBetween(
      location.latitude, location.longitude,
      a.location.latitude, a.location.longitude,
    );
    final dB = Geolocator.distanceBetween(
      location.latitude, location.longitude,
      b.location.latitude, b.location.longitude,
    );
    return dA.compareTo(dB);
  });
  return aeds;
}

enum LocationDataSource { none, cached, live }
enum AEDDataSource { empty, cached, fresh }

// ========================================
// MAIN INITIALIZATION MANAGER
// ========================================

class AppInitializationManager {
  static Future<InitializationResult>? _initFuture;
  static final LocationService _locationService = LocationService();

  static Future<InitializationResult> initializeApp(AEDService aedRepository) {
    _initFuture ??= _performInitialization(aedRepository).catchError((e, stackTrace) {
      print("❌ App initialization failed: $e");
      print("Stack trace: $stackTrace");

      // allow retry next call
      _initFuture = null;

      return InitializationResult(
        hasLocation: false,
        aedList: [],
        isConnected: false,
        locationSource: LocationDataSource.none,
        aedSource: AEDDataSource.empty,
      );
    });

    return _initFuture!;
  }

  /// Optional: call only if YOU want to force re-initialization manually
  static void reset() {
    _initFuture = null;
  }

  /// **Internal initialization logic**
  static Future<InitializationResult> _performInitialization(
      AEDService aedRepository,
      ) async {
    // STEP 1: Initialize lightweight services
    await _initializeLightweightServices();
    print("✅ Lightweight services initialized");

    // STEP 2: Check network connectivity
    final isConnected = await NetworkService.isConnected();
    print("🌐 Network: ${isConnected ? 'Connected' : 'Offline'}");

    // STEP 3: Get API key from environment
    final String? apiKey = NetworkService.googleMapsApiKey;
    print("🔑 API key: ${apiKey != null ? 'Loaded' : 'Missing'}");

    // STEP 4: Load cached location (instant)
    final cachedLocationData = await _loadCachedLocation();
    final cachedLocation = cachedLocationData.location;
    final locationSource = cachedLocationData.source;
    final locationAge = cachedLocationData.age;
    final cachedTransportMode = cachedLocationData.transportMode;

    print("📍 Cached location: ${cachedLocation != null ? 'Found' : 'None'} "
        "(source: $locationSource)");

    // STEP 5: Load cached AEDs (instant display)
    final cachedAEDs = await _loadCachedAEDs(aedRepository, cachedLocation, cachedTransportMode);
    final aedAge = await _getAEDCacheAge();
    print("📦 Cached AEDs: ${cachedAEDs.length}");

    // STEP 6: Start background tasks (non-blocking)
    _startBackgroundTasks(
      aedRepository: aedRepository,
      isConnected: isConnected,
      cachedLocation: cachedLocation,
    );

    // STEP 7: Return initial result with cached data
    return InitializationResult(
      hasLocation: cachedLocation != null,
      userLocation: cachedLocation,
      aedList: cachedAEDs,
      isConnected: isConnected,
      apiKey: apiKey,
      shouldZoom: cachedLocation != null && cachedAEDs.isNotEmpty,
      locationSource: locationSource,
      aedSource: cachedAEDs.isEmpty ? AEDDataSource.empty : AEDDataSource.cached,
      locationAge: locationAge,
      aedAge: aedAge,
    );
  }

  /// **Initialize fast, synchronous services**
  static Future<void> _initializeLightweightServices() async {
    try {
      SafeFonts.initializeFontCache();
      // Cache initialization already done in main.dart
    } catch (e) {
      print("⚠️ Error initializing lightweight services: $e");
    }
  }

  /// **Load cached location with typed result**
  static Future<CachedLocationData> _loadCachedLocation() async {
    try {
      final cachedAppState = await CacheService.getLastAppState();

      if (cachedAppState != null) {
        final lat = cachedAppState['latitude'];
        final lng = cachedAppState['longitude'];
        final timestamp = cachedAppState['timestamp'];

        // ✅ Type-safe extraction
        if (lat is num && lng is num) {
          final location = LatLng(lat.toDouble(), lng.toDouble());
          final age = (timestamp is int)
              ? DateTime.fromMillisecondsSinceEpoch(timestamp)
              : null;

          final transportMode = cachedAppState['transportMode'] as String? ?? 'walking';
          return CachedLocationData(
            location: location,
            source: LocationDataSource.cached,
            age: age,
            transportMode: transportMode,
          );
        }
      }
    } catch (e) {
      print("⚠️ Error loading cached location: $e");
    }

    return CachedLocationData(
      location: null,
      source: LocationDataSource.none,
      age: null,
    );
  }

  /// **Load cached AEDs with error recovery**
  static Future<List<AED>> _loadCachedAEDs(
      AEDService aedRepository,
      LatLng? userLocation,
      String transportMode,
      ) async {
    try {
      final cachedData = await CacheService.getAEDs();
      if (cachedData == null || cachedData.isEmpty) {
        print("📦 No cached AEDs found");
        return [];
      }

      // ✅ Parse with error tracking
      final aedList = await compute(_parseAEDsIsolate, List<dynamic>.from(cachedData));
      final parseErrors = cachedData.length - aedList.length;

      // ✅ Cache corruption detection
      if (parseErrors > 0) {
        final errorRate = parseErrors / cachedData.length;
        print("⚠️ Skipped $parseErrors invalid cached AEDs (${ (errorRate * 100).toStringAsFixed(1)}%)");

        if (errorRate > 0.5) {
          print("🗑️ Cache corrupted (>50% errors), clearing...");
          await CacheService.clearAEDCache();
          return [];
        }
      }

      // ✅ Sort by distance if we have location
      if (userLocation != null && aedList.isNotEmpty) {
        return await compute(_sortAEDsIsolate, {
          'aeds': aedList,
          'lat': userLocation.latitude,
          'lng': userLocation.longitude,
          'mode': transportMode,
        });
      }

      return aedList;
    } catch (e) {
      print("❌ Error loading cached AEDs: $e");
      return [];
    }
  }

  /// **Get AED cache age**
  static Future<DateTime?> _getAEDCacheAge() async {
    try {
      final metadata = await CacheService.getCacheMetadata();
      if (metadata != null && metadata['aed_last_updated'] is int) {
        return DateTime.fromMillisecondsSinceEpoch(metadata['aed_last_updated']);
      }
    } catch (e) {
      print("⚠️ Error getting AED cache age: $e");
    }
    return null;
  }

  /// **Start non-blocking background tasks**
  static void _startBackgroundTasks({
    required AEDService aedRepository,
    required bool isConnected,
    required LatLng? cachedLocation,
  }) {
    // Background tasks are handled by the widget after map is ready
    // GPS tracking is started in _initializeApp once map completes
  }

  // ========================================
  // PUBLIC API FOR WIDGETS
  // ========================================

  /// **Request user location with UI** (call from widget with context)
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

  /// **Fetch fresh AEDs** (call in background after initial load)
  static Future<List<AED>> fetchFreshAEDs(
      AEDService aedRepository, {
        required bool isConnected,
        LatLng? userLocation,
        String transportMode = 'walking',
      }) async {
    if (!isConnected) {
      print("⚠️ Skipping AED fetch - offline");
      return [];
    }

    try {
      final aeds = await aedRepository.fetchAEDs(forceRefresh: true);

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

  /// **Calculate estimated distances** (offline fallback)
  static void calculateEstimatedDistances({
    required List<AED> aeds,
    required LatLng userLocation,
    String transportMode = 'walking',
  }) {
    if (aeds.isEmpty) return;
    AEDService.calculateEstimatedDistancesForAll(aeds, userLocation, transportMode);
  }

  /// **Improve distance accuracy with Google API** (online enhancement)
  static Future<void> improveDistanceAccuracy(
      AEDService aedRepository, {
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

  /// **Check if location is available**
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
}

// ========================================
// HELPER MODELS
// ========================================

class CachedLocationData {
  final LatLng? location;
  final LocationDataSource source;
  final DateTime? age;
  final String transportMode;

  CachedLocationData({
    required this.location,
    required this.source,
    required this.age,
    this.transportMode = 'walking',
  });
}