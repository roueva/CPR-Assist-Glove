import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../features/aed_map/services/aed_service.dart';
import '../features/aed_map/services/cache_service.dart';
import '../features/aed_map/services/location_service.dart';
import '../models/aed_models.dart';
import '../services/network/network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

enum LocationDataSource { none, cached, live }
enum AEDDataSource      { empty, cached, fresh }

// ─────────────────────────────────────────────────────────────────────────────
// Result model
// ─────────────────────────────────────────────────────────────────────────────

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

  const InitializationResult({
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

  bool get hasValidData     => aedList.isNotEmpty;
  bool get isLocationCached => locationSource == LocationDataSource.cached;
  bool get areAEDsCached    => aedSource == AEDDataSource.cached;
}

// ─────────────────────────────────────────────────────────────────────────────
// Isolate helpers (top-level — required by compute())
// ─────────────────────────────────────────────────────────────────────────────

List<AED> _parseAEDsIsolate(List<dynamic> rawData) {
  final result = <AED>[];
  for (final item in rawData) {
    try {
      if (item is Map<String, dynamic>) result.add(AED.fromMap(item));
    } catch (_) {}
  }
  return result;
}

List<AED> _sortAEDsIsolate(Map<String, dynamic> params) {
  final aeds     = params['aeds'] as List<AED>;
  final location = LatLng(params['lat'] as double, params['lng'] as double);
  final mode     = params['mode'] as String? ?? 'walking';
  final double multiplier;
  switch (mode) {
    case 'driving':   multiplier = 1.4; break;
    case 'bicycling': multiplier = 1.2; break;
    default:          multiplier = 1.3; break;
  }
  aeds.sort((a, b) {
    final dA = Geolocator.distanceBetween(
      location.latitude, location.longitude,
      a.location.latitude, a.location.longitude,
    ) * multiplier;
    final dB = Geolocator.distanceBetween(
      location.latitude, location.longitude,
      b.location.latitude, b.location.longitude,
    ) * multiplier;
    return dA.compareTo(dB);
  });
  return aeds;
}

// ─────────────────────────────────────────────────────────────────────────────
// AppInitializationManager
// ─────────────────────────────────────────────────────────────────────────────

class AppInitializationManager {
  AppInitializationManager._();

  static Future<InitializationResult>? _initFuture;
  static final LocationService _locationService = LocationService();

  /// Returns the single shared initialization future.
  /// Safe to call multiple times — computation runs only once.
  static Future<InitializationResult> initializeApp(AEDService aedRepository) {
    _initFuture ??= _run(aedRepository).catchError((Object e, StackTrace st) {
      debugPrint('AppInit failed: $e\n$st');
      _initFuture = null; // allow retry
      return const InitializationResult(
        hasLocation: false,
        aedList: [],
        isConnected: false,
      );
    });
    return _initFuture!;
  }

  /// Force re-initialization on next call (e.g. after permission grant).
  static void reset() => _initFuture = null;

  // ── Core pipeline ─────────────────────────────────────────────────────────

  static Future<InitializationResult> _run(AEDService aedRepository) async {
    final isConnected = await NetworkService.isConnected();
    final apiKey      = NetworkService.googleMapsApiKey;

    final locationData = await _loadCachedLocation();
    final cachedAEDs   = await _loadCachedAEDs(
      aedRepository,
      locationData.location,
      locationData.transportMode,
    );
    final aedAge = await _getAEDCacheAge();

    return InitializationResult(
      hasLocation:    locationData.location != null,
      userLocation:   locationData.location,
      aedList:        cachedAEDs,
      isConnected:    isConnected,
      apiKey:         apiKey,
      shouldZoom:     locationData.location != null && cachedAEDs.isNotEmpty,
      locationSource: locationData.source,
      aedSource:      cachedAEDs.isEmpty ? AEDDataSource.empty : AEDDataSource.cached,
      locationAge:    locationData.age,
      aedAge:         aedAge,
    );
  }

  // ── Cached location ───────────────────────────────────────────────────────

  static Future<CachedLocationData> _loadCachedLocation() async {
    try {
      final state = await CacheService.getLastAppState();
      if (state != null) {
        final lat  = state['latitude'];
        final lng  = state['longitude'];
        final ts   = state['timestamp'];
        if (lat is num && lng is num) {
          return CachedLocationData(
            location:      LatLng(lat.toDouble(), lng.toDouble()),
            source:        LocationDataSource.cached,
            age:           ts is int ? DateTime.fromMillisecondsSinceEpoch(ts) : null,
            transportMode: state['transportMode'] as String? ?? 'walking',
          );
        }
      }
    } catch (e) {
      debugPrint('CachedLocation error: $e');
    }
    return const CachedLocationData(location: null, source: LocationDataSource.none, age: null);
  }

  // ── Cached AEDs ───────────────────────────────────────────────────────────

  static Future<List<AED>> _loadCachedAEDs(
      AEDService aedRepository,
      LatLng? userLocation,
      String transportMode,
      ) async {
    try {
      final raw = await CacheService.getAEDs();
      if (raw == null || raw.isEmpty) return [];

      final aeds       = await compute(_parseAEDsIsolate, List<dynamic>.from(raw));
      final errorCount = raw.length - aeds.length;

      if (errorCount > 0) {
        final rate = errorCount / raw.length;
        debugPrint('Skipped $errorCount invalid cached AEDs (${(rate * 100).toStringAsFixed(1)}%)');
        if (rate > 0.5) {
          debugPrint('Cache corrupted — clearing');
          await CacheService.clearAEDCache();
          return [];
        }
      }

      if (userLocation != null && aeds.isNotEmpty) {
        return compute(_sortAEDsIsolate, {
          'aeds': aeds,
          'lat':  userLocation.latitude,
          'lng':  userLocation.longitude,
          'mode': transportMode,
        });
      }

      return aeds;
    } catch (e) {
      debugPrint('CachedAEDs error: $e');
      return [];
    }
  }

  // ── AED cache age ─────────────────────────────────────────────────────────

  static Future<DateTime?> _getAEDCacheAge() async {
    try {
      final meta = await CacheService.getCacheMetadata();
      if (meta != null && meta['aed_last_updated'] is int) {
        return DateTime.fromMillisecondsSinceEpoch(meta['aed_last_updated'] as int);
      }
    } catch (e) {
      debugPrint('AEDCacheAge error: $e');
    }
    return null;
  }

  // ── Public helpers (called from widgets/screens) ──────────────────────────

  /// Request device GPS location (shows permission dialogs if needed).
  static Future<LatLng?> requestUserLocation(BuildContext context) async {
    try {
      return await _locationService.getCurrentLocationWithUI(
        context: context,
        showPermissionDialog: true,
        showErrorMessages: true,
      );
    } catch (e) {
      debugPrint('requestUserLocation error: $e');
      return null;
    }
  }

  /// Fetch fresh AEDs from the backend (call after initial cached load).
  static Future<List<AED>> fetchFreshAEDs(
      AEDService aedRepository, {
        required bool isConnected,
        LatLng? userLocation,
        String transportMode = 'walking',
      }) async {
    if (!isConnected) return [];
    try {
      final aeds = await aedRepository.fetchAEDs(forceRefresh: true);
      if (aeds.isEmpty) return [];
      if (userLocation != null) {
        return aedRepository.sortAEDsByDistance(aeds, userLocation, transportMode);
      }
      return aeds;
    } catch (e) {
      debugPrint('fetchFreshAEDs error: $e');
      return [];
    }
  }

  /// Straight-line distance estimates (offline fallback, synchronous).
  static void calculateEstimatedDistances({
    required List<AED> aeds,
    required LatLng userLocation,
    String transportMode = 'walking',
  }) {
    if (aeds.isEmpty) return;
    AEDService.calculateEstimatedDistancesForAll(aeds, userLocation, transportMode);
  }

  /// Improve AED distances via Google Routes API (online, non-blocking).
  static Future<void> improveDistanceAccuracy(
      AEDService aedRepository, {
        required List<AED> aeds,
        required LatLng userLocation,
        required String transportMode,
        required String? apiKey,
        required void Function(List<AED>) onUpdated,
      }) async {
    if (apiKey == null || aeds.isEmpty) return;
    try {
      await aedRepository.improveDistanceAccuracyInBackground(
        aeds, userLocation, transportMode, apiKey, onUpdated,
      );
    } catch (e) {
      debugPrint('improveDistanceAccuracy error: $e');
    }
  }

  /// Returns true if GPS is enabled and permission granted.
  static Future<bool> isLocationAvailable() async {
    try {
      final enabled    = await Geolocator.isLocationServiceEnabled();
      final permission = await _locationService.hasPermission;
      return enabled && permission;
    } catch (e) {
      debugPrint('isLocationAvailable error: $e');
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper model
// ─────────────────────────────────────────────────────────────────────────────

class CachedLocationData {
  final LatLng? location;
  final LocationDataSource source;
  final DateTime? age;
  final String transportMode;

  const CachedLocationData({
    required this.location,
    required this.source,
    required this.age,
    this.transportMode = 'walking',
  });
}