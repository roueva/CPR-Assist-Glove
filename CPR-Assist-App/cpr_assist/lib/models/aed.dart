import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AED {
  final int id;
  final String name;
  final String address;
  final LatLng location;
  final double distanceInMeters;

  AED({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    this.distanceInMeters = 0.0,
  });

  AED copyWithDistance(LatLng userLocation) {
    final distance = Geolocator.distanceBetween(
      userLocation.latitude, userLocation.longitude,
      location.latitude, location.longitude,
    );

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
    };
  }
}