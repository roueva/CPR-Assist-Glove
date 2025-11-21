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
    // Use API distance if available (from nearby query)
    final distanceToUse = distanceFromAPI ?? distanceInMeters;

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
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      availability: map['availability'],
      aedWebpage: map['aed_webpage'],
      lastUpdated: map['last_updated'] != null
          ? DateTime.parse(map['last_updated'])
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
  final List<AED> aedList;
  final LatLng? userLocation;
  final bool isLoading;
  final bool isRefreshing;
  final NavigationState navigation;
  final int currentBatch;
  final bool isOffline;
  final DateTime? lastSyncTime;

  const AEDMapState({
    this.aedList = const [],
    this.userLocation,
    this.isLoading = true,
    this.isRefreshing = false,
    this.navigation = const NavigationState(),
    this.currentBatch = 3,
    this.isOffline = false,
    this.lastSyncTime,
  });

  LatLng? get selectedAED => navigation.destination;
  String get transportMode => navigation.transportMode;
  bool get hasSelectedRoute => navigation.isActive;
  Polyline? get navigationLine => navigation.route;
  String get estimatedTime => navigation.estimatedTime;
  double? get distance => navigation.distance;
  bool get navigationMode => navigation.isActive;

  // NEW: Helper to get formatted sync time
  String get formattedSyncTime {
    if (lastSyncTime == null) return 'Never synced';

    final now = DateTime.now();
    final difference = now.difference(lastSyncTime!);

    if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? "day" : "days"} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? "hour" : "hours"} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? "minute" : "minutes"} ago';
    } else {
      return 'Just now';
    }
  }

  AEDMapState copyWith({
    List<AED>? aedList,
    LatLng? userLocation,
    bool? isLoading,
    bool? isRefreshing,
    NavigationState? navigation,
    int? currentBatch,
    bool? isOffline,
    DateTime? lastSyncTime,
  }) {
    return AEDMapState(
      aedList: aedList ?? this.aedList,
      userLocation: userLocation ?? this.userLocation,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      navigation: navigation ?? this.navigation,
      currentBatch: currentBatch ?? this.currentBatch,
      isOffline: isOffline ?? this.isOffline,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}