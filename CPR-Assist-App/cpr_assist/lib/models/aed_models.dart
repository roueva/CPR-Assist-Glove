import 'package:google_maps_flutter/google_maps_flutter.dart';

class AED {
  final int id;
  final String? foundation;        // NEW: Organization/foundation name
  final String? address;
  final LatLng location;
  final String? availability;      // NEW: Availability hours
  final String? aedWebpage;        // NEW: Info webpage URL
  final DateTime? lastUpdated;     // NEW: Last sync timestamp
  final double distanceInMeters;
  final double? distanceFromAPI;   // NEW: Distance from backend API (nearby query)
  final double? distance;

  AED({
    required this.id,
    this.foundation,
    this.address,
    required this.location,
    this.availability,
    this.aedWebpage,
    this.lastUpdated,
    this.distanceInMeters = 0.0,
    this.distanceFromAPI,
    this.distance,
  });

  // Get display name (prioritize foundation, fallback to address)
  String get name => foundation ?? address ?? 'AED Location';

  // Get info URL
  String? get infoUrl => aedWebpage;

  AED copyWithDistance(double distance) {
    return AED(
      id: id,
      foundation: foundation,
      address: address,
      location: location,
      availability: availability,
      aedWebpage: aedWebpage,
      lastUpdated: lastUpdated,
      distanceInMeters: distance,
      distanceFromAPI: distanceFromAPI,
    );
  }

  String get formattedDistance {
    // Prefer freshly calculated distanceInMeters; fall back to API distance from initial fetch
    final distanceToUse = distanceInMeters > 0 ? distanceInMeters : (distanceFromAPI ?? 0.0);

    // ✅ Handle zero/invalid distance
    if (distanceToUse <= 0) {
      return '--';  // Show placeholder instead of "0 m"
    }

    if (distanceToUse < 1000) {
      return '${distanceToUse.toStringAsFixed(0)} m';
    } else {
      return '${(distanceToUse / 1000).toStringAsFixed(1)} km';
    }
  }

  // Format availability text
  String get formattedAvailability {
    if (availability == null || availability!.isEmpty) {
      return 'Unknown availability';
    }
    return availability!;
  }

  // Format last updated time
  String get formattedLastUpdated {
    if (lastUpdated == null) return '';  // ✅ Return empty for display logic

    final now = DateTime.now();
    final difference = now.difference(lastUpdated!);

    if (difference.inDays == 0) {
      return 'today';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
    } else {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    }
  }

  // Factory method to create AED from backend API response
  factory AED.fromMap(Map<String, dynamic> map) {
    return AED(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      foundation: map['foundation'],
      address: map['address'],
      location: LatLng(
        (map['latitude'] as num?)?.toDouble() ?? 0.0,
        (map['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      availability: map['availability'],
      aedWebpage: map['aed_webpage'],
      lastUpdated: map['last_updated'] != null
          ? DateTime.parse(map['last_updated']).toLocal()
          : null,
      distanceFromAPI: map['distance'] != null
          ? (map['distance'] as num).toDouble() * 1000 // Convert km to meters
          : null,
    );
  }

  factory AED.empty() => AED(
    id: -1,
    foundation: null,
    address: '',
    location: const LatLng(0, 0),
  );

  // Convert to map for storage/caching
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'foundation': foundation,
      'address': address,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'availability': availability,
      'aed_webpage': aedWebpage,
      'last_updated': lastUpdated?.toIso8601String(),
      if (distanceFromAPI != null) 'distance': distanceFromAPI! / 1000, // Store as km
    };
  }

  // Helper to check if AED has valid location
  bool get hasValidLocation =>
      location.latitude != 0.0 && location.longitude != 0.0;

  // Helper to check if AED has webpage
  bool get hasWebpage => aedWebpage != null && aedWebpage!.isNotEmpty;
}