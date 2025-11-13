import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'aed_models.dart';
import '../services/aed_map/location_service.dart';

class AED {
  final int id;
  final String name;
  final String address;
  final LatLng location;
  final double distanceInMeters;
  final String? infoUrl;

  AED({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.distanceInMeters = 0.0,
    this.infoUrl,
  });

  AED copyWithDistance(LatLng userLocation) {
    final distance = LocationService.distanceBetween(userLocation, location);

    return AED(
      id: id,
      name: name,
      address: address,
      location: location,
      distanceInMeters: distance,
    );
  }

  String get formattedDistance {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
    }
  }

  // Factory method to create AED from map data
  factory AED.fromMap(Map<String, dynamic> map) {
    return AED(
      id: int.parse(map['id'].toString()),
      name: map['name'] ?? map['address'] ?? 'AED',
      address: map['address'] ?? '',
      location: LatLng(
        double.parse(map['latitude'].toString()),
        double.parse(map['longitude'].toString()),
      ),
    );
  }

  factory AED.empty() => AED(
    id: -1,
    name: '',
    address: '',
    location: LatLng(0,0),
  );

  // Convert to map for storage
  Map<String, dynamic> toMap() {
    return {
      'id': id.toString(),
      'name': name,
      'address': address,
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'info_url': infoUrl,
    };
  }
}

class NavigationState {
  final bool isActive;
  final LatLng? destination;
  final Polyline? route;
  final String transportMode;
  final String estimatedTime;
  final double? distance;
  final bool hasStarted;


  const NavigationState({
    this.isActive = false,
    this.destination,
    this.route,
    this.transportMode = 'walking',
    this.estimatedTime = '',
    this.distance,
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
  final bool isOffline;


  const AEDMapState({
    this.markers = const {},
    this.aedList = const [],
    this.userLocation,
    this.isLoading = true,
    this.isRefreshing = false,
    this.navigation = const NavigationState(),
    this.currentBatch = 3,
    this.isOffline = false,
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
    bool? isOffline,
  }) {
    return AEDMapState(
      markers: markers ?? this.markers,
      aedList: aedList ?? this.aedList,
      userLocation: userLocation ?? this.userLocation,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      navigation: navigation ?? this.navigation,
      currentBatch: currentBatch ?? this.currentBatch,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}
