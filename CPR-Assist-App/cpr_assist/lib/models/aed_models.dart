import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AED model
//
// Pure data class — no colors, no spacing, no UI.
// Display helpers use only Dart string formatting; callers apply AppTypography.
// ─────────────────────────────────────────────────────────────────────────────

class AED {
  final int id;
  final String? foundation;
  final String? address;
  final LatLng location;
  final String? availability;
  final String? aedWebpage;
  final DateTime? lastUpdated;
  final double distanceInMeters;
  final double? distanceFromAPI; // metres (converted from km on parse)
  final double? distance;

  const AED({
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

  // ── Display helpers ───────────────────────────────────────────────────────

  /// Best available display name.
  String get name => foundation ?? address ?? 'AED Location';

  /// Info webpage URL.
  String? get infoUrl => aedWebpage;

  /// Human-readable distance string.
  /// Prefers freshly-calculated [distanceInMeters]; falls back to API distance.
  String get formattedDistance {
    final d = distanceInMeters > 0 ? distanceInMeters : (distanceFromAPI ?? 0.0);
    if (d <= 0) return '--';
    if (d < 1000) return '${d.toStringAsFixed(0)} m';
    return '${(d / 1000).toStringAsFixed(1)} km';
  }

  /// Human-readable availability text.
  String get formattedAvailability =>
      (availability?.isNotEmpty ?? false) ? availability! : 'Unknown availability';

  /// Human-readable age of the last data sync.
  String get formattedLastUpdated {
    if (lastUpdated == null) return '';
    final diff = DateTime.now().difference(lastUpdated!);
    if (diff.inDays == 0)  return 'today';
    if (diff.inDays == 1)  return 'yesterday';
    if (diff.inDays < 7)   return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return '$w ${w == 1 ? 'week' : 'weeks'} ago';
    }
    final m = (diff.inDays / 30).floor();
    return '$m ${m == 1 ? 'month' : 'months'} ago';
  }

  // ── Convenience flags ─────────────────────────────────────────────────────

  bool get hasValidLocation =>
      location.latitude != 0.0 && location.longitude != 0.0;

  bool get hasWebpage => aedWebpage?.isNotEmpty ?? false;

  // ── Copy helpers ──────────────────────────────────────────────────────────

  AED copyWithDistance(double newDistance) => AED(
    id:               id,
    foundation:       foundation,
    address:          address,
    location:         location,
    availability:     availability,
    aedWebpage:       aedWebpage,
    lastUpdated:      lastUpdated,
    distanceInMeters: newDistance,
    distanceFromAPI:  distanceFromAPI,
  );

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory AED.fromMap(Map<String, dynamic> map) {
    return AED(
      id:         map['id'] is int ? map['id'] as int : int.parse(map['id'].toString()),
      foundation: map['foundation'] as String?,
      address:    map['address'] as String?,
      location: LatLng(
        (map['latitude']  as num?)?.toDouble() ?? 0.0,
        (map['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      availability: map['availability'] as String?,
      aedWebpage:   map['aed_webpage']  as String?,
      lastUpdated: map['last_updated'] != null
          ? DateTime.parse(map['last_updated'] as String).toLocal()
          : null,
      // Backend returns km — convert to metres for internal consistency
      distanceFromAPI: map['distance'] != null
          ? (map['distance'] as num).toDouble() * 1000
          : null,
    );
  }

  factory AED.empty() => const AED(
    id:       -1,
    address:  '',
    location: LatLng(0, 0),
  );

  Map<String, dynamic> toMap() => {
    'id':           id,
    'foundation':   foundation,
    'address':      address,
    'latitude':     location.latitude,
    'longitude':    location.longitude,
    'availability': availability,
    'aed_webpage':  aedWebpage,
    'last_updated': lastUpdated?.toIso8601String(),
    if (distanceFromAPI != null) 'distance': distanceFromAPI! / 1000, // store as km
  };
}