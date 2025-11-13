import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/aed_models.dart';
import 'route_service.dart';

/// Specialized service for caching the 10 closest AEDs with their full route data
class AEDPersistentCacheService {
  static const String _cachedClosestAEDsKey = 'cached_closest_aeds_v3';
  static const String _cachedUserLocationKey = 'cached_closest_aeds_location_v3';
  static const String _cachedRoutesKey = 'cached_closest_aeds_routes_v3';
  static const String _cacheTimestampKey = 'cached_closest_aeds_timestamp_v3';
  static const int maxCachedAEDs = 10;
  static const String _cachedPinsKey = 'cached_aed_pins_v1'; // For instant marker display


  /// Cache the 10 closest AEDs with their routes and distances
  static Future<void> cacheClosestAEDsWithRoutes({
    required List<AED> aeds,
    required LatLng userLocation,
    required Map<int, Map<String, RouteResult>> routesByAedAndMode,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Take only closest 10
      final closestAEDs = aeds.take(maxCachedAEDs).toList();

      // Serialize AEDs with distances
      final aedsJson = closestAEDs.map((aed) => {
        'id': aed.id,
        'name': aed.name,
        'address': aed.address,
        'latitude': aed.location.latitude,
        'longitude': aed.location.longitude,
        'distanceInMeters': aed.distanceInMeters,
        'infoUrl': aed.infoUrl
      }).toList();

      // Serialize all routes for these AEDs
      final routesJson = <String, dynamic>{};
      for (final aed in closestAEDs) {
        final routes = routesByAedAndMode[aed.id];
        if (routes != null) {
          for (final entry in routes.entries) {
            final mode = entry.key;
            final route = entry.value;
            final key = '${aed.id}_$mode';
            routesJson[key] = {
              'duration': route.duration,
              'actualDistance': route.actualDistance,
              'distanceText': route.distanceText,
              'isOffline': route.isOffline,
              'points': route.points.map((p) => {
                'lat': p.latitude,
                'lng': p.longitude,
              }).toList(),
            };
          }
        }
      }

      // Save everything
      await prefs.setString(_cachedClosestAEDsKey, jsonEncode(aedsJson));
      await prefs.setString(_cachedUserLocationKey, jsonEncode({
        'latitude': userLocation.latitude,
        'longitude': userLocation.longitude,
      }));
      await prefs.setString(_cachedRoutesKey, jsonEncode(routesJson));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      await cachePinsOnly(aeds);
      print('✅ Persistently cached ${closestAEDs.length} closest AEDs with routes');
    } catch (e) {
      print('❌ Error caching closest AEDs: $e');
    }
  }

  /// Get all cached closest AEDs (with their stored distances)
  static Future<List<AED>> getCachedClosestAEDs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final aedsJson = prefs.getString(_cachedClosestAEDsKey);

      if (aedsJson == null) return [];

      final aedsList = jsonDecode(aedsJson) as List;
      return aedsList.map((json) => AED(
        id: json['id'],
        name: json['name'],
        address: json['address'],
        location: LatLng(json['latitude'], json['longitude']),
        distanceInMeters: json['distanceInMeters'] ?? 0.0,
        infoUrl: json['infoUrl'],
      )).toList();
    } catch (e) {
      print('❌ Error getting cached closest AEDs: $e');
      return [];
    }
  }

  /// Get first N closest cached AEDs
  static Future<List<AED>> getCachedClosest(int limit) async {
    final all = await getCachedClosestAEDs();
    return all.take(limit).toList();
  }

  /// Get cached AEDs beyond first N (farther ones)
  static Future<List<AED>> getCachedFarther(int skipFirst) async {
    final all = await getCachedClosestAEDs();
    return all.skip(skipFirst).toList();
  }

  /// Get cached route for a specific AED and transport mode
  static Future<RouteResult?> getCachedRoute(int aedId, String transportMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final routesJson = prefs.getString(_cachedRoutesKey);

      if (routesJson == null) return null;

      final routes = jsonDecode(routesJson) as Map<String, dynamic>;
      final key = '${aedId}_$transportMode';
      final routeData = routes[key];

      if (routeData == null) return null;

      // Reconstruct polyline points
      final points = (routeData['points'] as List)
          .map((p) => LatLng(p['lat'], p['lng']))
          .toList();

      return RouteResult(
        polyline: Polyline(
          polylineId: PolylineId('cached_persistent_${aedId}_$transportMode'),
          points: points,
          color: transportMode == 'walking' ? Colors.green : Colors.blue,
          patterns: transportMode == 'walking'
              ? [PatternItem.dash(15), PatternItem.gap(8)]
              : [],
          width: 4,
        ),
        duration: routeData['duration'],
        points: points,
        isOffline: routeData['isOffline'] ?? true,
        actualDistance: routeData['actualDistance'],
        distanceText: routeData['distanceText'],
      );
    } catch (e) {
      print('❌ Error getting cached route for AED $aedId: $e');
      return null;
    }
  }

  /// Get cached user location
  static Future<LatLng?> getCachedUserLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationJson = prefs.getString(_cachedUserLocationKey);

      if (locationJson == null) return null;

      final location = jsonDecode(locationJson);
      return LatLng(location['latitude'], location['longitude']);
    } catch (e) {
      print('❌ Error getting cached user location: $e');
      return null;
    }
  }

  /// Check if cached location is close to current location (within 500m)
  static Future<bool> isCachedLocationStillValid(LatLng currentLocation) async {
    final cachedLocation = await getCachedUserLocation();
    if (cachedLocation == null) return false;

    // ✅ ADD: Check cache timestamp
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_cacheTimestampKey);
    if (timestamp == null) return false;

    final cacheAge = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp)
    );
    if (cacheAge > const Duration(days: 30)) {  // Reasonable threshold
      print('⏰ Cache expired (${cacheAge.inDays} days old)');
      return false;
    }

    // Check distance
    const double validRadius = 500.0;
    final distance = _calculateDistance(
      cachedLocation.latitude,
      cachedLocation.longitude,
      currentLocation.latitude,
      currentLocation.longitude,
    );

    if (distance > validRadius) {
      print('📍 Location moved ${distance.round()}m (> ${validRadius}m threshold)');
      return false;
    }
    return true;
  }

  /// Helper: Calculate distance in meters between two coordinates
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  /// Check if we have cached data
  static Future<bool> hasCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_cachedClosestAEDsKey);
  }

  /// Clear the persistent cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedClosestAEDsKey);
      await prefs.remove(_cachedUserLocationKey);
      await prefs.remove(_cachedRoutesKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove(_cachedPinsKey); // ADD THIS LINE
      print('🗑️ Persistent closest AEDs cache cleared');
    } catch (e) {
      print('❌ Error clearing persistent cache: $e');
    }
  }

  /// Cache just the pin positions for instant display (no routes, no details)
  static Future<void> cachePinsOnly(List<AED> aeds) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Store minimal data: just ID and location for markers
      final pinsJson = aeds.map((aed) => {
        'id': aed.id,
        'lat': aed.location.latitude,
        'lng': aed.location.longitude,
      }).toList();

      await prefs.setString(_cachedPinsKey, jsonEncode(pinsJson));
      print('📍 Cached ${aeds.length} pin positions for instant display');
    } catch (e) {
      print('❌ Error caching pins: $e');
    }
  }

  /// Get cached pins (returns just locations, no full AED data)
  static Future<List<Map<String, dynamic>>> getCachedPins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pinsJson = prefs.getString(_cachedPinsKey);

      if (pinsJson == null) return [];

      final pinsList = jsonDecode(pinsJson) as List;
      return pinsList.cast<Map<String, dynamic>>();
    } catch (e) {
      print('❌ Error getting cached pins: $e');
      return [];
    }
  }

  /// Clear cache if location changed significantly (>5km)
  static Future<void> clearCacheIfLocationChanged(LatLng newLocation) async {
    final cachedLocation = await getCachedUserLocation();

    if (cachedLocation != null) {
      final distance = _calculateDistance(
        cachedLocation.latitude,
        cachedLocation.longitude,
        newLocation.latitude,
        newLocation.longitude,
      );

      // If moved more than 5km, clear cache
      if (distance > 5000) {
        print('📍 Location changed significantly (${distance.round()}m) - clearing old cache');
        await clearCache();
        return;
      }

      print('📍 Location change within threshold (${distance.round()}m) - keeping cache');
    }
  }
}