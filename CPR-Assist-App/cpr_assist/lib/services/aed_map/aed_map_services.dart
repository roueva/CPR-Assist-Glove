import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../custom_icons.dart';
import '../../models/aed.dart';
import '../../utils/map_utils.dart';
import '../network_service.dart';

class NavigationState {
  final bool isActive;
  final LatLng? destination;
  final Polyline? route;
  final String transportMode;
  final String estimatedTime;
  final double? distance;
  final double? currentBearing;
  final double? currentSpeed;
  final DateTime? lastUpdated;
  final bool hasStarted;


  const NavigationState({
    this.isActive = false,
    this.destination,
    this.route,
    this.transportMode = 'walking',
    this.estimatedTime = '',
    this.distance,
    this.currentBearing,
    this.currentSpeed,
    this.lastUpdated,
    this.hasStarted = false,
  });

  NavigationState copyWith({
    bool? isActive,
    LatLng? destination,
    Polyline? route,
    String? transportMode,
    String? estimatedTime,
    double? distance,
    double? currentBearing,
    double? currentSpeed,
    DateTime? lastUpdated,
    bool? hasStarted,
  }) {
    return NavigationState(
      isActive: isActive ?? this.isActive,
      destination: destination ?? this.destination,
      route: route ?? this.route,
      transportMode: transportMode ?? this.transportMode,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      distance: distance ?? this.distance,
      currentBearing: currentBearing ?? this.currentBearing,
      currentSpeed: currentSpeed ?? this.currentSpeed,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      hasStarted: hasStarted ?? this.hasStarted,
    );
  }
}

class AEDMapState {
  final Set<Marker> markers;
  final List<AED> aedList;
  final LatLng? userLocation;
  final bool isLoading;
  final bool isRefreshing;
  final NavigationState navigation;
  final int currentBatch;

  const AEDMapState({
    this.markers = const {},
    this.aedList = const [],
    this.userLocation,
    this.isLoading = true,
    this.isRefreshing = false,
    this.navigation = const NavigationState(),
    this.currentBatch = 3,
  });

  LatLng? get selectedAED => navigation.destination;
  String get transportMode => navigation.transportMode;
  bool get hasSelectedRoute => navigation.isActive;
  Polyline? get navigationLine => navigation.route;
  String get estimatedTime => navigation.estimatedTime;
  double? get distance => navigation.distance;
  bool get navigationMode => navigation.isActive;

  AEDMapState copyWith({
    Set<Marker>? markers,
    List<AED>? aedList,
    LatLng? userLocation,
    bool? isLoading,
    bool? isRefreshing,
    NavigationState? navigation,
    int? currentBatch,
  }) {
    return AEDMapState(
      markers: markers ?? this.markers,
      aedList: aedList ?? this.aedList,
      userLocation: userLocation ?? this.userLocation,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      navigation: navigation ?? this.navigation,
      currentBatch: currentBatch ?? this.currentBatch,
    );
  }
}

// -- AEDRepository --
class AEDRepository {
  Future<List<AED>> fetchAEDs({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cachedAEDs = await AEDCache.getAEDs();
      if (cachedAEDs != null) {
        return convertToAEDList(cachedAEDs);
      }
    }

    try {
      final aeds = await NetworkService.fetchAEDLocations();
      await AEDCache.saveAEDs(aeds, null);
      return convertToAEDList(aeds);
    } catch (e) {
      print("❌ Error fetching AEDs: $e");
      final cachedAEDs = await AEDCache.getAEDs();
      if (cachedAEDs != null) {
        return convertToAEDList(cachedAEDs);
      }
      return [];
    }
  }

  List<AED> convertToAEDList(List<dynamic> rawData) {
    return rawData.map((aed) {
      final double? lat = double.tryParse(aed["latitude"].toString());
      final double? lng = double.tryParse(aed["longitude"].toString());

      if (lat == null || lng == null) return null;

      final location = LatLng(lat, lng);
      final rawAddress = aed["address"]?.toString() ?? "Unknown address";
      final int aedId = int.tryParse(aed["id"].toString()) ?? 0;

      return AED(
        id: aedId,
        name: rawAddress,
        address: rawAddress,
        location: location,
      );
    }).whereType<AED>().toList();
  }

  Set<Marker> createMarkers(List<AED> aeds, Function(LatLng) onPreviewPressed){
    return aeds.map((aed) => Marker(
      markerId: MarkerId(aed.id.toString()),
      position: aed.location,
      icon: CustomIcons.aedUpdated,
      infoWindow: InfoWindow(
        title: aed.address,
        snippet: null,
        onTap: () => onPreviewPressed(aed.location),
      ),
    )).toSet();
  }

  List<AED> sortAEDsByDistance(List<AED> aeds, LatLng? referenceLocation) {
    if (referenceLocation == null || aeds.isEmpty) return aeds;

    final sorted = List<AED>.from(aeds);
    sorted.sort((a, b) {
      final distA = LocationService.distanceBetween(referenceLocation, a.location);
      final distB = LocationService.distanceBetween(referenceLocation, b.location);
      return distA.compareTo(distB);
    });

    return sorted;
  }

  bool haveAEDsChanged(List<AED> oldList, List<AED> newList) {
    if (oldList.length != newList.length) return true;
    for (int i = 0; i < oldList.length; i++) {
      if (oldList[i].id != newList[i].id ||
          oldList[i].location.latitude != newList[i].location.latitude ||
          oldList[i].location.longitude != newList[i].location.longitude ||
          oldList[i].address != newList[i].address) {
        return true;
      }
    }
    return false;
  }

}

// -- AEDCache --
class AEDCache {
  static const String CACHE_KEY = 'cached_aeds';
  static const String TIMESTAMP_KEY = 'aed_cache_timestamp';
  static const Duration CACHE_TTL = Duration(hours: 24);

  static Future<void> saveAEDs(List<dynamic> aeds, LatLng? userLocation) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CACHE_KEY, jsonEncode(aeds));
    await prefs.setInt(TIMESTAMP_KEY, DateTime.now().millisecondsSinceEpoch);
    if (userLocation != null) {
      await prefs.setDouble('cached_lat', userLocation.latitude);
      await prefs.setDouble('cached_lng', userLocation.longitude);
    }
  }

  static Future<List<dynamic>?> getAEDs() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(CACHE_KEY);

    if (cachedData == null) return null;

    try {
      return jsonDecode(cachedData);
    } catch (e) {
      return null;
    }
  }

  static Future<LatLng?> getCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('cached_lat');
    final lng = prefs.getDouble('cached_lng');
    final timestamp = prefs.getInt(TIMESTAMP_KEY);

    if (lat == null || lng == null || timestamp == null) return null;

    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cacheTime) > Duration(days: 2)) {
      return null;
    }

    return LatLng(lat, lng);
  }

  static Future<void> saveLastAppState(AEDMapState state) async {
    final prefs = await SharedPreferences.getInstance();

    if (state.userLocation != null) {
      await prefs.setDouble('cached_lat', state.userLocation!.latitude);
      await prefs.setDouble('cached_lng', state.userLocation!.longitude);
      await prefs.setInt('location_timestamp', DateTime.now().millisecondsSinceEpoch);
    }

    // Save other important state data
    if (state.selectedAED != null) {
      await prefs.setDouble('selected_aed_lat', state.selectedAED!.latitude);
      await prefs.setDouble('selected_aed_lng', state.selectedAED!.longitude);
    } else {
      await prefs.remove('selected_aed_lat');
      await prefs.remove('selected_aed_lng');
    }

    await prefs.setString('transport_mode', state.transportMode);
    await prefs.setBool('has_selected_route', state.hasSelectedRoute);
  }
}


// -- RouteService --
class RouteService {
  final String apiKey;

  RouteService(this.apiKey);

  Future<RouteResult?> fetchRoute(LatLng origin, LatLng destination, String mode) async {
    if (apiKey.isEmpty) {
      print("❌ Missing API Key.");
      return null;
    }

    final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json?"
            "origin=${origin.latitude},${origin.longitude}"
            "&destination=${destination.latitude},${destination.longitude}"
            "&mode=$mode"
            "&key=$apiKey"
    );

    try {
      final response = await NetworkService.getExternal(url.toString());

      if (response != null && response['status'] == 'OK') {
        List<LatLng> routePoints = PolylineUtils.decode(response["routes"][0]["overview_polyline"]["points"]);
        String durationText = response["routes"][0]["legs"][0]["duration"]["text"];

        return RouteResult(
          polyline: Polyline(
            polylineId: PolylineId(mode),
            points: routePoints,
            color: mode == "walking" ? Colors.green : Colors.blue,
            patterns: mode == "walking"
                ? [PatternItem.dash(20), PatternItem.gap(10)]
                : [],
            width: 5,
          ),
          duration: durationText,
          points: routePoints,
        );
      }
    } catch (e) {
      print("❌ Error fetching route: $e");
    }

    return null;
  }
}

class RouteResult {
  final Polyline polyline;
  final String duration;
  final List<LatLng> points;

  RouteResult({required this.polyline, required this.duration, required this.points});
}
