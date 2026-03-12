import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/core.dart';
import 'location_service.dart';
import 'route_service.dart';

class CacheService {
  // Cache keys
  static const String _aedCacheKey         = 'cached_aeds';
  static const String _aedTimestampKey      = 'aed_cache_timestamp';
  static const String _mapRegionKey         = 'last_map_region';
  static const String _mapDataKey           = 'cached_map_data';
  static const String _routeCacheKey        = 'persistent_route_cache';
  static const String _routeTimestampKey    = 'route_cache_timestamps';
  static const String _distanceCacheKey     = 'persistent_distance_cache';
  static const String _mapPreferencesKey    = 'map_preferences';
  static const String _mapBoundsKey         = 'visible_map_bounds';
  static const String _appStateKey          = 'last_app_state';
  static const String _cacheMetadataKey     = 'cache_metadata';

  static final Map<String, RouteResult> _memoryRouteCache      = {};
  static final Map<String, DateTime>    _routeCacheTimestamps   = {};
  static final Map<String, double>      _distanceCache          = {};
  static final Map<String, List<String>> _routesSpatialIndex   = {};

  static bool   _isLoadingDistanceCache = false;
  static bool   _isSavingDistanceCache  = false;
  static Timer? _saveTimer;
  static Timer? _routeSaveTimer;

  static const int      _maxRouteCache    = 600;
  static const int      _maxDistanceCache = 8000;
  static const Duration _cacheTtl         = Duration(days: 7);

  static Duration getCacheTTL() => _cacheTtl;

  // ── Cache metadata ─────────────────────────────────────────────────────────

  static Future<Duration> getCacheAge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_aedTimestampKey);
      if (timestamp == null) return const Duration(days: 999);
      return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
    } catch (e) {
      debugPrint('⚠️ Error getting cache age: $e');
      return const Duration(days: 999);
    }
  }

  static Future<Map<String, dynamic>?> getCacheMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataJson = prefs.getString(_cacheMetadataKey);
      if (metadataJson != null) {
        return jsonDecode(metadataJson) as Map<String, dynamic>;
      }
      final aedTimestamp = prefs.getInt(_aedTimestampKey);
      if (aedTimestamp != null) return {'aed_last_updated': aedTimestamp};
    } catch (e) {
      debugPrint('⚠️ Error getting cache metadata: $e');
    }
    return null;
  }

  static Future<void> _updateCacheMetadata({
    int? aedLastUpdated,
    int? routeLastUpdated,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await getCacheMetadata() ?? {};
      if (aedLastUpdated != null) existing['aed_last_updated'] = aedLastUpdated;
      if (routeLastUpdated != null) existing['route_last_updated'] = routeLastUpdated;
      await prefs.setString(_cacheMetadataKey, jsonEncode(existing));
    } catch (e) {
      debugPrint('⚠️ Error updating cache metadata: $e');
    }
  }

  // ── Distance cache ─────────────────────────────────────────────────────────

  static void setDistance(String key, double distance) {
    _distanceCache[key] = distance;

    if (_distanceCache.length > _maxDistanceCache) {
      _evictOldDistanceEntries();
    }

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), saveDistanceCache);
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

  static void clearDistanceCache() {
    _distanceCache.clear();
    _saveTimer?.cancel();
    debugPrint('🗑️ Distance cache cleared (location changed)');
  }

  static double? getDistance(String key) => _distanceCache[key];

  static Future<void> loadDistanceCache() async {
    if (_isLoadingDistanceCache) return;
    _isLoadingDistanceCache = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_distanceCacheKey);
      if (cacheData != null) {
        final Map<String, dynamic> decoded = jsonDecode(cacheData);
        _distanceCache.clear();
        decoded.forEach((key, value) {
          _distanceCache[key] = (value as num).toDouble();
        });
        debugPrint('📦 Loaded ${_distanceCache.length} distance entries from cache');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading distance cache: $e');
    } finally {
      _isLoadingDistanceCache = false;
    }
  }

  static Future<void> saveDistanceCache() async {
    if (_isSavingDistanceCache) return;
    _isSavingDistanceCache = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_distanceCacheKey, jsonEncode(_distanceCache));
    } catch (e) {
      debugPrint('⚠️ Error saving distance cache: $e');
    } finally {
      _isSavingDistanceCache = false;
    }
  }

  // ── Route cache ────────────────────────────────────────────────────────────

  static String generateLocationKey(LatLng origin, LatLng destination, String mode) {
    return '${origin.latitude.toStringAsFixed(4)}|${origin.longitude.toStringAsFixed(4)}|'
        '${destination.latitude.toStringAsFixed(4)}|${destination.longitude.toStringAsFixed(4)}|$mode';
  }

  static bool isRouteCacheValid(String key) {
    final timestamp = _routeCacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp) < _cacheTtl;
  }

  static RouteResult? getCachedRoute(LatLng origin, LatLng destination, String mode) {
    final key = generateLocationKey(origin, destination, mode);
    if (isRouteCacheValid(key)) return _memoryRouteCache[key];
    return null;
  }

  static RouteResult? getCachedRouteNearby(
      LatLng origin,
      LatLng destination,
      String mode, {
        double maxDistanceMeters = 1000,
      }) {
    final exactMatch = getCachedRoute(origin, destination, mode);
    if (exactMatch != null) return exactMatch;

    final gridKey = _getGridKey(origin, maxDistanceMeters);
    final nearbyKeys = _routesSpatialIndex[gridKey] ?? [];

    for (final key in nearbyKeys) {
      if (!key.endsWith('|$mode')) continue;
      if (!isRouteCacheValid(key)) continue;

      final route = _memoryRouteCache[key];
      if (route == null) continue;

      final parts = key.split('|');
      if (parts.length < 5) continue;

      try {
        final cachedOrigin = LatLng(double.parse(parts[0]), double.parse(parts[1]));
        final distance = LocationService.distanceBetween(origin, cachedOrigin);
        if (distance <= maxDistanceMeters) {
          debugPrint('📍 Found nearby cached route (${distance.round()}m away)');
          return route;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static void setCachedRoute(
      LatLng origin, LatLng destination, String mode, RouteResult route) {
    final key = generateLocationKey(origin, destination, mode);
    _memoryRouteCache[key] = route;
    _routeCacheTimestamps[key] = DateTime.now();

    final gridKey = _getGridKey(origin, 1000);
    _routesSpatialIndex.putIfAbsent(gridKey, () => []).add(key);

    _evictOldCacheEntries();

    _routeSaveTimer?.cancel();
    _routeSaveTimer = Timer(const Duration(seconds: 5), _persistAllRoutes);
  }

  static Future<void> _persistAllRoutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cache      = <String, dynamic>{};
      final timestamps = <String, dynamic>{};

      for (final key in _memoryRouteCache.keys) {
        final route = _memoryRouteCache[key];
        final ts    = _routeCacheTimestamps[key];
        if (route != null && ts != null) {
          cache[key]      = _serializeRoute(route);
          timestamps[key] = ts.millisecondsSinceEpoch;
        }
      }

      await prefs.setString(_routeCacheKey,      jsonEncode(cache));
      await prefs.setString(_routeTimestampKey,  jsonEncode(timestamps));
    } catch (e) {
      debugPrint('⚠️ Error persisting routes: $e');
    }
  }

  static String _getGridKey(LatLng location, double gridSizeMeters) {
    final gridLat = (location.latitude  * 1000).floor();
    final gridLng = (location.longitude * 1000).floor();
    return '$gridLat,$gridLng';
  }

  static Future<void> loadRouteCacheFromPersistent() async {
    try {
      final prefs         = await SharedPreferences.getInstance();
      final cacheData     = prefs.getString(_routeCacheKey);
      final timestampData = prefs.getString(_routeTimestampKey);

      if (cacheData != null && timestampData != null) {
        final Map<String, dynamic> decoded    = jsonDecode(cacheData);
        final Map<String, dynamic> timestamps = jsonDecode(timestampData);

        int loadedCount  = 0;
        int expiredCount = 0;

        for (final entry in decoded.entries) {
          final key       = entry.key;
          final timestamp = timestamps[key];

          if (timestamp != null) {
            final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
            _routeCacheTimestamps[key] = cacheTime;

            if (isRouteCacheValid(key)) {
              _memoryRouteCache[key] = _deserializeRoute(
                entry.value as Map<String, dynamic>,
              );
              loadedCount++;
            } else {
              expiredCount++;
            }
          }
        }

        debugPrint('📦 Loaded $loadedCount routes from cache ($expiredCount expired)');

        if (expiredCount > 0) await _cleanExpiredRoutes();
      }
    } catch (e) {
      debugPrint('⚠️ Error loading persistent route cache: $e');
    }
  }

  static Future<void> _cleanExpiredRoutes() async {
    try {
      final prefs           = await SharedPreferences.getInstance();
      final validCache      = <String, dynamic>{};
      final validTimestamps = <String, dynamic>{};

      for (final key in _memoryRouteCache.keys) {
        final route     = _memoryRouteCache[key];
        final timestamp = _routeCacheTimestamps[key];
        if (route != null && timestamp != null) {
          validCache[key]      = _serializeRoute(route);
          validTimestamps[key] = timestamp.millisecondsSinceEpoch;
        }
      }

      await prefs.setString(_routeCacheKey,     jsonEncode(validCache));
      await prefs.setString(_routeTimestampKey, jsonEncode(validTimestamps));

      debugPrint('🗑️ Cleaned expired routes from persistent storage');
    } catch (e) {
      debugPrint('⚠️ Error cleaning expired routes: $e');
    }
  }

  static void _evictOldCacheEntries() {
    if (_memoryRouteCache.length > _maxRouteCache) {
      final sortedByAge = _routeCacheTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final toRemove = sortedByAge.length - _maxRouteCache;
      for (int i = 0; i < toRemove; i++) {
        final key = sortedByAge[i].key;
        _memoryRouteCache.remove(key);
        _routeCacheTimestamps.remove(key);
      }
      if (toRemove > 10) debugPrint('🗑️ Evicted $toRemove old route cache entries');
    }

    if (_distanceCache.length > _maxDistanceCache) {
      final keysToRemove = _distanceCache.keys
          .take(_distanceCache.length - _maxDistanceCache)
          .toList();
      for (final key in keysToRemove) {
        _distanceCache.remove(key);
      }
      if (keysToRemove.length % 10 == 0) {
        debugPrint('🗑️ Evicted ${keysToRemove.length} old distance cache entries');
      }
    }
  }

  // ── Initialization ─────────────────────────────────────────────────────────

  static Future<void> initializeAllCaches() async {
    await loadDistanceCache();
    await loadRouteCacheFromPersistent();
    debugPrint('🚀 All caches initialized');
  }

  // ── AED caching ────────────────────────────────────────────────────────────

  static Future<void> saveAEDs(List<dynamic> aeds) async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(aeds);
      final timestamp  = DateTime.now().millisecondsSinceEpoch;

      debugPrint('💾 Attempting to save ${aeds.length} AEDs to cache...');

      await prefs.setString(_aedCacheKey,   jsonString);
      await prefs.setInt(_aedTimestampKey,   timestamp);
      await _updateCacheMetadata(aedLastUpdated: timestamp);

      final verification = prefs.getString(_aedCacheKey);
      if (verification != null && verification.isNotEmpty) {
        final verifiedData = jsonDecode(verification) as List;
        if (verifiedData.length == aeds.length) {
          debugPrint('✅ VERIFIED: Cache save successful - ${aeds.length} AEDs stored');
        } else {
          debugPrint('⚠️ WARNING: Saved ${aeds.length} but verified ${verifiedData.length}');
        }
      } else {
        debugPrint('❌ FAILED: Cache verification failed - no data found after save');
      }
    } catch (e) {
      debugPrint('❌ ERROR saving AEDs to cache: $e');
    }
  }

  static Future<List<dynamic>?> getAEDs() async {
    final prefs      = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(_aedCacheKey);
    if (cachedData == null) return null;

    try {
      final data = jsonDecode(cachedData) as List;
      debugPrint('📦 Loaded ${data.length} AEDs from cache');
      return data;
    } catch (e) {
      debugPrint('⚠️ Error decoding cached AEDs: $e');
      return null;
    }
  }

  static Future<bool> isAEDCacheExpired() async {
    final prefs     = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_aedTimestampKey);
    if (timestamp == null) return true;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    return age > _cacheTtl;
  }

  // ── Map state caching ──────────────────────────────────────────────────────

  static Future<void> saveLastMapRegion({
    required LatLng center,
    required double zoom,
    double? bearing,
    double? tilt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapRegionKey, jsonEncode({
      'latitude':  center.latitude,
      'longitude': center.longitude,
      'zoom':      zoom,
      'bearing':   0.0,
      'tilt':      0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }));
    debugPrint('💾 Saved general region: ${center.latitude.toStringAsFixed(2)}, ${center.longitude.toStringAsFixed(2)}');
  }

  static Future<CameraPosition?> getLastMapRegion() async {
    try {
      final prefs      = await SharedPreferences.getInstance();
      final regionData = prefs.getString(_mapRegionKey);
      if (regionData == null) return null;

      final Map<String, dynamic> data = jsonDecode(regionData);
      final cacheAge = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
      );

      if (cacheAge < const Duration(days: 30)) {
        debugPrint('📍 Loading cached general region');
        return CameraPosition(
          target:  LatLng(data['latitude'] as double, data['longitude'] as double),
          zoom:    data['zoom'] as double,
          bearing: 0.0,
          tilt:    0.0,
        );
      } else {
        debugPrint('⏰ Cached region too old, using default');
      }
    } catch (e) {
      debugPrint('⚠️ Error loading cached region: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getCachedMapData() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final mapData = prefs.getString(_mapDataKey);

      if (mapData != null) {
        final data     = jsonDecode(mapData) as Map<String, dynamic>;
        final cacheAge = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
        );
        if (cacheAge < _cacheTtl) {
          debugPrint('📊 Loading cached map data');
          return data;
        } else {
          debugPrint('⏰ Cached map data too old');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading cached map data: $e');
    }
    return null;
  }

  static Future<void> saveMapPreferences({
    required double defaultZoom,
    required String preferredMapType,
    bool trafficEnabled  = false,
    bool buildingsEnabled = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapPreferencesKey, jsonEncode({
      'defaultZoom':      defaultZoom,
      'mapType':          preferredMapType,
      'trafficEnabled':   trafficEnabled,
      'buildingsEnabled': buildingsEnabled,
      'timestamp':        DateTime.now().millisecondsSinceEpoch,
    }));
  }

  static Future<Map<String, dynamic>> getMapPreferences() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final prefsData = prefs.getString(_mapPreferencesKey);
      if (prefsData != null) return jsonDecode(prefsData) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ Error loading map preferences: $e');
    }
    return {
      'defaultZoom':      AppConstants.defaultZoom,
      'mapType':          'normal',
      'trafficEnabled':   false,
      'buildingsEnabled': true,
    };
  }

  static Future<void> saveLastAppState(LatLng userLocation, String transportMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appStateKey, jsonEncode({
      'latitude':      userLocation.latitude,
      'longitude':     userLocation.longitude,
      'transportMode': transportMode,
      'timestamp':     DateTime.now().millisecondsSinceEpoch,
    }));
  }

  static Future<Map<String, dynamic>?> getLastAppState() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final stateData = prefs.getString(_appStateKey);
      if (stateData != null) {
        final data     = jsonDecode(stateData) as Map<String, dynamic>;
        final cacheAge = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
        );
        if (cacheAge < _cacheTtl) {
          return {
            'latitude':      (data['latitude']  as num).toDouble(),
            'longitude':     (data['longitude'] as num).toDouble(),
            'transportMode': data['transportMode'] as String? ?? 'walking',
            'timestamp':     data['timestamp'] as int,
          };
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error loading last app state: $e');
    }
    return null;
  }

  // ── Route caching (key-based) ──────────────────────────────────────────────

  static Future<void> saveRoute(String routeKey, RouteResult route) async {
    try {
      final prefs         = await SharedPreferences.getInstance();
      final cacheData     = prefs.getString(_routeCacheKey)     ?? '{}';
      final timestampData = prefs.getString(_routeTimestampKey) ?? '{}';

      final Map<String, dynamic> cache      = jsonDecode(cacheData);
      final Map<String, dynamic> timestamps = jsonDecode(timestampData);

      cache[routeKey]      = _serializeRoute(route);
      timestamps[routeKey] = DateTime.now().millisecondsSinceEpoch;

      await prefs.setString(_routeCacheKey,     jsonEncode(cache));
      await prefs.setString(_routeTimestampKey, jsonEncode(timestamps));
    } catch (e) {
      debugPrint('⚠️ Error saving route cache: $e');
    }
  }

  static Future<RouteResult?> getRoute(String routeKey) async {
    try {
      final prefs         = await SharedPreferences.getInstance();
      final cacheData     = prefs.getString(_routeCacheKey);
      final timestampData = prefs.getString(_routeTimestampKey);
      if (cacheData == null || timestampData == null) return null;

      final Map<String, dynamic> cache      = jsonDecode(cacheData);
      final Map<String, dynamic> timestamps = jsonDecode(timestampData);

      if (!cache.containsKey(routeKey) || !timestamps.containsKey(routeKey)) return null;
      if (_isCacheExpired(timestamps[routeKey], _cacheTtl)) return null;

      return _deserializeRoute(cache[routeKey] as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  // ── Clear helpers ──────────────────────────────────────────────────────────

  static Future<void> clearAllCache() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_aedCacheKey),
      prefs.remove(_aedTimestampKey),
      prefs.remove(_mapRegionKey),
      prefs.remove(_mapDataKey),
      prefs.remove(_routeCacheKey),
      prefs.remove(_routeTimestampKey),
      prefs.remove(_distanceCacheKey),
      prefs.remove(_mapPreferencesKey),
      prefs.remove(_mapBoundsKey),
      prefs.remove(_appStateKey),
    ]);

    _distanceCache.clear();
    _memoryRouteCache.clear();
    _routeCacheTimestamps.clear();

    debugPrint('🗑️ All cache cleared (persistent + memory)');
  }

  static Future<void> clearAEDCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_aedCacheKey);
    await prefs.remove(_aedTimestampKey);
    debugPrint('🗑️ AED cache cleared');
  }

  static Future<void> clearMapCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_mapRegionKey);
    await prefs.remove(_mapDataKey);
    await prefs.remove(_mapPreferencesKey);
    await prefs.remove(_mapBoundsKey);
    debugPrint('🗑️ Map cache cleared');
  }

  static Future<void> clearRouteCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_routeCacheKey);
    await prefs.remove(_routeTimestampKey);
    debugPrint('🗑️ Route cache cleared');
  }

  // ── Getters ────────────────────────────────────────────────────────────────

  static CameraPosition getDefaultGreecePosition() {
    return const CameraPosition(
      target:  AppConstants.greeceCenter,
      zoom:    AppConstants.greeceZoom,
      bearing: 0.0,
      tilt:    0.0,
    );
  }

  static Future<bool> hasMapCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_mapRegionKey) || prefs.containsKey(_mapDataKey);
  }

  static Future<bool> hasAEDCache() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_aedCacheKey);
  }

  static Map<String, int> getCacheStats() {
    return {
      'distanceEntries':  _distanceCache.length,
      'routeEntries':     _memoryRouteCache.length,
      'routeTimestamps':  _routeCacheTimestamps.length,
      'maxRouteCache':    _maxRouteCache,
      'maxDistanceCache': _maxDistanceCache,
    };
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static bool _isCacheExpired(dynamic timestamp, Duration ttl) {
    if (timestamp == null) return true;
    final int ts = timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0;
    return DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) > ttl;
  }

  static Map<String, dynamic> _serializeRoute(RouteResult route) {
    return {
      'polylineId':    route.polyline.polylineId.value,
      'duration':      route.duration,
      'points':        route.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'isOffline':     route.isOffline,
      'actualDistance': route.actualDistance,
      'distanceText':  route.distanceText,
      'transportMode': route.transportMode,
    };
  }

  static RouteResult _deserializeRoute(Map<String, dynamic> data) {
    final points        = (data['points'] as List)
        .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
        .toList();
    final transportMode = data['transportMode'] as String? ?? 'walking';
    final polylineId    = data['polylineId']    as String? ?? 'cached_route';

    return RouteResult(
      polyline: Polyline(
        polylineId: PolylineId(polylineId),
        points:     points,
        color:      transportMode == 'walking' ? AppColors.aedNavGreen : AppColors.primary,
        patterns:   transportMode == 'walking'
            ? [PatternItem.dash(15), PatternItem.gap(8)]
            : [],
        width: 4,
      ),
      duration:       data['duration'] as String,
      points:         points,
      isOffline:      data['isOffline']      as bool?   ?? false,
      actualDistance: (data['actualDistance'] as num?)?.toDouble(),
      distanceText:   data['distanceText']   as String?,
      transportMode:  transportMode,
    );
  }

  static void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }
}