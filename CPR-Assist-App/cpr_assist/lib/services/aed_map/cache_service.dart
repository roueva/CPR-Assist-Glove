import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../utils/app_constants.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'location_service.dart';
import 'route_service.dart';

class CacheService {
  // Cache keys - unified and consistent
  static const String _aedCacheKey = 'cached_aeds';
  static const String _aedTimestampKey = 'aed_cache_timestamp';
  static const String _mapRegionKey = 'last_map_region';
  static const String _mapDataKey = 'cached_map_data';
  static const String _routeCacheKey = 'persistent_route_cache';
  static const String _routeTimestampKey = 'route_cache_timestamps';
  static const String _distanceCacheKey = 'persistent_distance_cache';
  static const String _mapPreferencesKey = 'map_preferences';
  static const String _mapBoundsKey = 'visible_map_bounds';
  static const String _appStateKey = 'last_app_state';
  static final Map<String, RouteResult> _memoryRouteCache = {};
  static final Map<String, DateTime> _routeCacheTimestamps = {};
  static bool _isLoadingDistanceCache = false;
  static bool _isSavingDistanceCache = false;
  static const int _maxRouteCache = 600;
  static const int _maxDistanceCache = 8000;
  static Timer? _saveTimer;
  static Duration getCacheTTL() => _cacheTtl;
  static final Map<String, List<String>> _routesSpatialIndex = {};
  static const String _cacheMetadataKey = 'cache_metadata';
  static Timer? _routeSaveTimer;

  /// Get the age of the AED cache
  static Future<Duration> getCacheAge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_aedTimestampKey);

      if (timestamp == null) {
        return const Duration(days: 999); // Very old = no cache
      }

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return DateTime.now().difference(cacheTime);
    } catch (e) {
      print("⚠️ Error getting cache age: $e");
      return const Duration(days: 999);
    }
  }

  /// Get cache metadata including last update timestamps
  static Future<Map<String, dynamic>?> getCacheMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataJson = prefs.getString(_cacheMetadataKey);

      if (metadataJson != null) {
        return jsonDecode(metadataJson) as Map<String, dynamic>;
      }

      // If no metadata exists, try to infer from AED timestamp
      final aedTimestamp = prefs.getInt(_aedTimestampKey);
      if (aedTimestamp != null) {
        return {
          'aed_last_updated': aedTimestamp,
        };
      }
    } catch (e) {
      print("⚠️ Error getting cache metadata: $e");
    }
    return null;
  }

  /// Call this from saveAEDs() method
  static Future<void> _updateCacheMetadata({
    int? aedLastUpdated,
    int? routeLastUpdated,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getCacheMetadata() ?? {};

      if (aedLastUpdated != null) {
        existing['aed_last_updated'] = aedLastUpdated;
      }
      if (routeLastUpdated != null) {
        existing['route_last_updated'] = routeLastUpdated;
      }

      await prefs.setString(_cacheMetadataKey, jsonEncode(existing));
    } catch (e) {
      print("⚠️ Error updating cache metadata: $e");
    }
  }

// Single unified distance cache
  static final Map<String, double> _distanceCache = {};

  // TTL constants - unified
  static const Duration _cacheTtl = Duration(days: 7);

  // Unified distance management
  static void setDistance(String key, double distance) {
    _distanceCache[key] = distance;

    // Immediate eviction if over limit
    if (_distanceCache.length > _maxDistanceCache) {
      _evictOldDistanceEntries();
    }

    // ✅ SHORTER debounce for safety (500ms instead of 2s)
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      saveDistanceCache();
    });
  }

  static void _evictOldDistanceEntries() {
    if (_distanceCache.length <= _maxDistanceCache) return;

    final keysToRemove = _distanceCache.keys
        .take(_distanceCache.length - _maxDistanceCache)
        .toList();

    for (final key in keysToRemove) {
      _distanceCache.remove(key);
    }
  }


  static double? getDistance(String key) {
    return _distanceCache[key];
  }

  static Future<void> loadDistanceCache() async {
    if (_isLoadingDistanceCache) return;
    _isLoadingDistanceCache = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_distanceCacheKey);

      if (cacheData != null) {
        final Map<String, dynamic> decoded = jsonDecode(cacheData);
        _distanceCache.clear(); // Use unified cache
        decoded.forEach((key, value) {
          _distanceCache[key] = value.toDouble();
        });
        print("📦 Loaded ${_distanceCache.length} distance entries from cache");
      }
    } catch (e) {
      print("⚠️ Error loading distance cache: $e");
    } finally {
      _isLoadingDistanceCache = false;
    }
  }

  static Future<void> saveDistanceCache() async {
    if (_isSavingDistanceCache) return;
    _isSavingDistanceCache = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_distanceCacheKey, jsonEncode(_distanceCache)); // Use unified cache
    } catch (e) {
      print("⚠️ Error saving distance cache: $e");
    } finally {
      _isSavingDistanceCache = false;
    }
  }

  // === ROUTE MANAGEMENT (moved from RouteService) ===
  static String generateLocationKey(LatLng origin, LatLng destination, String mode) {
    return "${origin.latitude.toStringAsFixed(4)}|${origin.longitude.toStringAsFixed(4)}|"
        "${destination.latitude.toStringAsFixed(4)}|${destination.longitude.toStringAsFixed(4)}|$mode";
  }

  static bool isRouteCacheValid(String key) {
    final timestamp = _routeCacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheTtl;
  }

  static RouteResult? getCachedRoute(LatLng origin, LatLng destination, String mode) {
    final key = generateLocationKey(origin, destination, mode);
    if (isRouteCacheValid(key)) {
      return _memoryRouteCache[key];
    }
    return null;
  }

  static RouteResult? getCachedRouteNearby(
      LatLng origin,
      LatLng destination,
      String mode,
      {double maxDistanceMeters = 1000}
      ) {
    // First try exact match
    final exactMatch = getCachedRoute(origin, destination, mode);
    if (exactMatch != null) return exactMatch;

    // ✅ Use spatial index for faster search
    final gridKey = _getGridKey(origin, maxDistanceMeters);
    final nearbyKeys = _routesSpatialIndex[gridKey] ?? [];

    for (final key in nearbyKeys) {
      if (!key.endsWith('|$mode')) continue;
      if (!isRouteCacheValid(key)) continue;

      final route = _memoryRouteCache[key];
      if (route == null) continue;

      // Parse origin from key to check distance
      final parts = key.split('|');
      if (parts.length < 5) continue;

      try {
        final cachedOriginLat = double.parse(parts[0]);
        final cachedOriginLng = double.parse(parts[1]);
        final cachedOrigin = LatLng(cachedOriginLat, cachedOriginLng);

        final distance = LocationService.distanceBetween(origin, cachedOrigin);
        if (distance <= maxDistanceMeters) {
          print("📍 Found nearby cached route (${distance.round()}m away)");
          return route;
        }
      } catch (e) {
        continue;
      }
    }

    return null;
  }

  static void setCachedRoute(LatLng origin, LatLng destination, String mode, RouteResult route) {
    final key = generateLocationKey(origin, destination, mode);
    _memoryRouteCache[key] = route;
    _routeCacheTimestamps[key] = DateTime.now();

    final gridKey = _getGridKey(origin, 1000);
    _routesSpatialIndex.putIfAbsent(gridKey, () => []).add(key);

    _evictOldCacheEntries();

    // ✅ Debounce route saves — don't write on every single route
    _routeSaveTimer?.cancel();
    _routeSaveTimer = Timer(const Duration(seconds: 5), () {
      _persistAllRoutes();
    });
  }

  static Future<void> _persistAllRoutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache = <String, dynamic>{};
      final timestamps = <String, dynamic>{};

      for (final key in _memoryRouteCache.keys) {
        final route = _memoryRouteCache[key];
        final ts = _routeCacheTimestamps[key];
        if (route != null && ts != null) {
          cache[key] = _serializeRoute(route);
          timestamps[key] = ts.millisecondsSinceEpoch;
        }
      }

      await prefs.setString(_routeCacheKey, jsonEncode(cache));
      await prefs.setString(_routeTimestampKey, jsonEncode(timestamps));
    } catch (e) {
      print("⚠️ Error persisting routes: $e");
    }
  }

  static String _getGridKey(LatLng location, double gridSizeMeters) {
    // Simple grid-based spatial indexing
    final gridLat = (location.latitude * 1000).floor(); // ~100m precision
    final gridLng = (location.longitude * 1000).floor();
    return '$gridLat,$gridLng';
  }

  static Future<void> loadRouteCacheFromPersistent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_routeCacheKey);
      final timestampData = prefs.getString(_routeTimestampKey);

      if (cacheData != null && timestampData != null) {
        final Map<String, dynamic> decoded = jsonDecode(cacheData);
        final Map<String, dynamic> timestamps = jsonDecode(timestampData);

        int loadedCount = 0;
        int expiredCount = 0;

        for (final entry in decoded.entries) {
          final key = entry.key;
          final routeData = entry.value;
          final timestamp = timestamps[key];

          if (timestamp != null) {
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
            _routeCacheTimestamps[key] = cacheTime;

            // Only load if not expired
            if (isRouteCacheValid(key)) {
              _memoryRouteCache[key] = _deserializeRoute(routeData);
              loadedCount++;
            } else {
              expiredCount++;
            }
          }
        }

        print("📦 Loaded $loadedCount routes from cache ($expiredCount expired)");

        // ✅ Clean up expired routes from persistent storage
        if (expiredCount > 0) {
          await _cleanExpiredRoutes();
        }
      }
    } catch (e) {
      print("⚠️ Error loading persistent route cache: $e");
    }
  }

  static Future<void> _cleanExpiredRoutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Rebuild cache with only valid entries
      final validCache = <String, dynamic>{};
      final validTimestamps = <String, dynamic>{};

      for (final key in _memoryRouteCache.keys) {
        final route = _memoryRouteCache[key];
        final timestamp = _routeCacheTimestamps[key];

        if (route != null && timestamp != null) {
          validCache[key] = _serializeRoute(route);
          validTimestamps[key] = timestamp.millisecondsSinceEpoch;
        }
      }

      await prefs.setString(_routeCacheKey, jsonEncode(validCache));
      await prefs.setString(_routeTimestampKey, jsonEncode(validTimestamps));

      print("🗑️ Cleaned expired routes from persistent storage");
    } catch (e) {
      print("⚠️ Error cleaning expired routes: $e");
    }
  }

  static void _evictOldCacheEntries() {
    // Evict old route cache entries
    if (_memoryRouteCache.length > _maxRouteCache) {
      final sortedByAge = _routeCacheTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final toRemove = sortedByAge.length - _maxRouteCache;
      for (int i = 0; i < toRemove; i++) {
        final key = sortedByAge[i].key;
        _memoryRouteCache.remove(key);
        _routeCacheTimestamps.remove(key);
      }
      // ✅ Only log significant evictions
      if (toRemove > 10) {
        print("🗑️ Evicted $toRemove old route cache entries");
      }
    }

    if (_distanceCache.length > _maxDistanceCache) {
      final keysToRemove = _distanceCache.keys
          .take(_distanceCache.length - _maxDistanceCache)
          .toList();

      for (final key in keysToRemove) {
        _distanceCache.remove(key);
      }

      // ✅ Only log every 10th eviction to reduce spam
      if (keysToRemove.length % 10 == 0) {
        print("🗑️ Evicted ${keysToRemove.length} old distance cache entries");
      }
    }
  }

  // === CACHE INITIALIZATION ===
  static Future<void> initializeAllCaches() async {
    await loadDistanceCache();
    await loadRouteCacheFromPersistent();
    print("🚀 All caches initialized");
  }

  // Enhanced clearAllCache to include memory caches
  static Future<void> clearAllCache() async {
    // Clear persistent storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aedCacheKey);
    await prefs.remove(_aedTimestampKey);
    await prefs.remove(_mapRegionKey);
    await prefs.remove(_mapDataKey);
    await prefs.remove(_routeCacheKey);
    await prefs.remove(_routeTimestampKey);
    await prefs.remove(_distanceCacheKey);
    await prefs.remove(_mapPreferencesKey);
    await prefs.remove(_mapBoundsKey);
    await prefs.remove(_appStateKey);

    // Clear memory caches
    _distanceCache.clear();
    _memoryRouteCache.clear();
    _routeCacheTimestamps.clear();

    print("🗑️ All cache cleared (persistent + memory)");
  }

  // === CACHE STATISTICS ===
  static Map<String, int> getCacheStats() {
    return {
      'distanceEntries': _distanceCache.length, // Single cache now
      'routeEntries': _memoryRouteCache.length,
      'routeTimestamps': _routeCacheTimestamps.length,
      'maxRouteCache': _maxRouteCache,
      'maxDistanceCache': _maxDistanceCache,
    };
  }

  // === AED CACHING ===
  static Future<void> saveAEDs(List<dynamic> aeds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(aeds);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      print("💾 Attempting to save ${aeds.length} AEDs to cache...");

      // Save the data
      await prefs.setString(_aedCacheKey, jsonString);
      await prefs.setInt(_aedTimestampKey, timestamp);

      // ✅ Update metadata
      await _updateCacheMetadata(aedLastUpdated: timestamp);

      // Verify by actually checking the count
      final verification = prefs.getString(_aedCacheKey);
      if (verification != null && verification.isNotEmpty) {
        final verifiedData = jsonDecode(verification) as List;
        if (verifiedData.length == aeds.length) {
          print("✅ VERIFIED: Cache save successful - ${aeds.length} AEDs stored");
        } else {
          print("⚠️ WARNING: Saved ${aeds.length} but verified ${verifiedData.length}");
        }
      } else {
        print("❌ FAILED: Cache verification failed - no data found after save");
      }
    } catch (e) {
      print("❌ ERROR saving AEDs to cache: $e");
    }
  }
  static Future<List<dynamic>?> getAEDs() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(_aedCacheKey);
    if (cachedData == null) return null;

    try {
      final data = jsonDecode(cachedData);
      print("📦 Loaded ${data.length} AEDs from cache");
      return data;
    } catch (e) {
      print("⚠️ Error decoding cached AEDs: $e");
      return null;
    }
  }

  static Future<bool> isAEDCacheExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_aedTimestampKey);

    if (timestamp == null) return true;

    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final age = DateTime.now().difference(cacheTime);

    // Cache is expired if older than TTL
    return age > _cacheTtl;
  }

  // === MAP STATE CACHING ===
  static Future<void> saveLastMapRegion({
    required LatLng center,
    required double zoom,
    double? bearing,
    double? tilt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final regionData = {
      'latitude': center.latitude,
      'longitude': center.longitude,
      'zoom': zoom,
      'bearing': 0.0, // Always reset to north
      'tilt': 0.0,    // Always reset to flat
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_mapRegionKey, jsonEncode(regionData));
    print("💾 Saved general region: ${center.latitude.toStringAsFixed(2)}, ${center.longitude.toStringAsFixed(2)}");
  }

  static Future<CameraPosition?> getLastMapRegion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final regionData = prefs.getString(_mapRegionKey);
      if (regionData == null) return null;

      final Map<String, dynamic> data = jsonDecode(regionData);
      final timestamp = data['timestamp'] as int;
      final cacheAge = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(timestamp)
      );

      // Return cached region if it's not too old (30 days)
      if (cacheAge < const Duration(days: 30)) {
        print("📍 Loading cached general region");
        return CameraPosition(
          target: LatLng(data['latitude'], data['longitude']),
          zoom: data['zoom'],
          bearing: 0.0,  // Always start facing north
          tilt: 0.0,     // Always start flat
        );
      } else {
        print("⏰ Cached region too old, using default");
      }
    } catch (e) {
      print("⚠️ Error loading cached region: $e");
    }
    return null;
  }

  // Get cached map data for offline display
  static Future<Map<String, dynamic>?> getCachedMapData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapData = prefs.getString(_mapDataKey);

      if (mapData != null) {
        final data = jsonDecode(mapData);
        final timestamp = data['timestamp'] as int;
        final cacheAge = DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(timestamp)
        );

        // Return cached data if it's not too old
        if (cacheAge < _cacheTtl) {
          print("📊 Loading cached map data");
          return data;
        } else {
          print("⏰ Cached map data too old");
        }
      }
    } catch (e) {
      print("⚠️ Error loading cached map data: $e");
    }
    return null;
  }

  // Save user's preferred map settings
  static Future<void> saveMapPreferences({
    required double defaultZoom,
    required String preferredMapType,
    bool trafficEnabled = false,
    bool buildingsEnabled = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final preferences = {
      'defaultZoom': defaultZoom,
      'mapType': preferredMapType,
      'trafficEnabled': trafficEnabled,
      'buildingsEnabled': buildingsEnabled,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_mapPreferencesKey, jsonEncode(preferences));
  }

  // Get user's map preferences
  static Future<Map<String, dynamic>> getMapPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefsData = prefs.getString(_mapPreferencesKey);

      if (prefsData != null) {
        return jsonDecode(prefsData);
      }
    } catch (e) {
      print("⚠️ Error loading map preferences: $e");
    }

    // Return default preferences
    return {
      'defaultZoom': AppConstants.defaultZoom,
      'mapType': 'normal',
      'trafficEnabled': false,
      'buildingsEnabled': true,
    };
  }

  // Save last app state for restoration
  static Future<void> saveLastAppState(LatLng userLocation, String transportMode) async {
    final prefs = await SharedPreferences.getInstance();

    final appState = {
      'latitude': userLocation.latitude,
      'longitude': userLocation.longitude,
      'transportMode': transportMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_appStateKey, jsonEncode(appState));
  }

  // Get last app state
  static Future<Map<String, dynamic>?> getLastAppState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateData = prefs.getString(_appStateKey);
      if (stateData != null) {
        final data = jsonDecode(stateData);
        final timestamp = data['timestamp'] as int;
        final cacheAge = DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(timestamp)
        );

        if (cacheAge < _cacheTtl) {
          return {
            'latitude': (data['latitude'] as num).toDouble(),
            'longitude': (data['longitude'] as num).toDouble(),
            'transportMode': data['transportMode'] as String? ?? 'walking',
            'timestamp': data['timestamp'] as int,
          };
        }
      }
    } catch (e) {
      print("⚠️ Error loading last app state: $e");
    }
    return null;
  }

  // === ROUTE CACHING ===
  static Future<void> saveRoute(String routeKey, RouteResult route) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing cache
      final cacheData = prefs.getString(_routeCacheKey) ?? '{}';
      final timestampData = prefs.getString(_routeTimestampKey) ?? '{}';

      final Map<String, dynamic> cache = jsonDecode(cacheData);
      final Map<String, dynamic> timestamps = jsonDecode(timestampData);

      // Add new route
      cache[routeKey] = _serializeRoute(route);
      timestamps[routeKey] = DateTime.now().millisecondsSinceEpoch;

      // Save back
      await prefs.setString(_routeCacheKey, jsonEncode(cache));
      await prefs.setString(_routeTimestampKey, jsonEncode(timestamps));
    } catch (e) {
      print("⚠️ Error saving route cache: $e");
    }
  }

  static Future<RouteResult?> getRoute(String routeKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_routeCacheKey);
      final timestampData = prefs.getString(_routeTimestampKey);

      if (cacheData == null || timestampData == null) return null;

      final Map<String, dynamic> cache = jsonDecode(cacheData);
      final Map<String, dynamic> timestamps = jsonDecode(timestampData);

      if (!cache.containsKey(routeKey) || !timestamps.containsKey(routeKey)) return null;

      // Check if expired
      final timestamp = timestamps[routeKey];
      if (_isCacheExpired(timestamp, _cacheTtl)) return null;

      return _deserializeRoute(cache[routeKey]);
    } catch (e) {
      return null;
    }
  }


  // === UTILITIES ===

  // Clear only specific cache types
  static Future<void> clearAEDCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aedCacheKey);
    await prefs.remove(_aedTimestampKey);
    print("🗑️ AED cache cleared");
  }

  static Future<void> clearMapCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mapRegionKey);
    await prefs.remove(_mapDataKey);
    await prefs.remove(_mapPreferencesKey);
    await prefs.remove(_mapBoundsKey);
    print("🗑️ Map cache cleared");
  }

  static Future<void> clearRouteCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_routeCacheKey);
    await prefs.remove(_routeTimestampKey);
    print("🗑️ Route cache cleared");
  }

  // Get a fallback camera position for Greece
  static CameraPosition getDefaultGreecePosition() {
    return const CameraPosition(
      target: LatLng(39.0742, 21.8243), // Center of Greece
      zoom: 6.0,
      bearing: 0.0,
      tilt: 0.0,
    );
  }

  // Check if we have any cached map data
  static Future<bool> hasMapCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_mapRegionKey) ||
        prefs.containsKey(_mapDataKey);
  }

  static Future<bool> hasAEDCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_aedCacheKey);
  }

  // === PRIVATE HELPER METHODS ===
  static bool _isCacheExpired(dynamic timestamp, Duration ttl) {
    if (timestamp == null) return true;

    final int timestampInt = timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0;
    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestampInt);
    final age = DateTime.now().difference(cacheTime);
    return age > ttl;
  }

  // Route serialization helpers
  static Map<String, dynamic> _serializeRoute(RouteResult route) {
    return {
      'polylineId': route.polyline.polylineId.value, // ✅ Save the ID
      'duration': route.duration,
      'points': route.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'isOffline': route.isOffline,
      'actualDistance': route.actualDistance,
      'distanceText': route.distanceText,
      'transportMode': route.transportMode,
    };
  }

  static RouteResult _deserializeRoute(Map<String, dynamic> data) {
    final points = (data['points'] as List)
        .map((p) => LatLng(p['lat'], p['lng']))
        .toList();
    final transportMode = data['transportMode'] ?? 'walking';
    final polylineId = data['polylineId'] ?? 'cached_route'; // ✅ Use saved ID

    return RouteResult(
      polyline: Polyline(
        polylineId: PolylineId(polylineId), // ✅ Restore original ID
        points: points,
        color: transportMode == 'walking' ? Colors.green : Colors.blue,
        patterns: transportMode == 'walking'
            ? [PatternItem.dash(15), PatternItem.gap(8)]
            : [],
        width: 4,
      ),
      duration: data['duration'],
      points: points,
      isOffline: data['isOffline'] ?? false,
      actualDistance: data['actualDistance']?.toDouble(),
      distanceText: data['distanceText'],
      transportMode: transportMode,
    );
  }

  static void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }
}