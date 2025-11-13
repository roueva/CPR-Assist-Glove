import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../models/aed_models.dart';
import '../../widgets/aed_markers.dart';
import 'location_service.dart';

class ProgressiveMarkerLoader {
  static const int _batchSize = 50;  // Load 50 at a time
  static const Duration _batchDelay = Duration(milliseconds: 50);

  bool _isCancelled = false;
  int _loadedCount = 0;

  /// Load markers progressively starting from closest to user
  Future<void> loadMarkersProgressively({
    required List<AED> allAEDs,
    required LatLng? userLocation,
    required Function(Set<Marker>, int totalCount, int loadedCount) onBatchLoaded,
    required Function(LatLng) onMarkerTap,
    Function(LatLng userLocation, List<LatLng> closestAEDs)? onFirstBatchLoaded, // ✅ NEW
  }) async {
    _isCancelled = false;
    _loadedCount = 0;
    final Set<Marker> allMarkers = {};

    // Sort by distance if we have user location
    List<AED> sortedAEDs;
    if (userLocation != null) {
      sortedAEDs = List.from(allAEDs)
        ..sort((a, b) {
          final distA = LocationService.distanceBetween(userLocation, a.location);
          final distB = LocationService.distanceBetween(userLocation, b.location);
          return distA.compareTo(distB);
        });
      print('📍 Sorted ${sortedAEDs.length} AEDs by distance');
    } else {
      sortedAEDs = allAEDs;
    }

    // ✅ NEW: Track if first batch zoom happened
    bool hasZoomedFirstBatch = false;

    // Load in batches
    for (int i = 0; i < sortedAEDs.length; i += _batchSize) {
      if (_isCancelled) {
        print('⚠️ Marker loading cancelled');
        break;
      }

      final endIndex = (i + _batchSize < sortedAEDs.length)
          ? i + _batchSize
          : sortedAEDs.length;

      final batch = sortedAEDs.sublist(i, endIndex);

      // Create markers for this batch
      for (final aed in batch) {
        allMarkers.add(
          Marker(
            markerId: MarkerId(aed.id.toString()),
            position: aed.location,
            icon: CustomIcons.aedUpdated,
            infoWindow: InfoWindow(
              title: aed.address,
              snippet: null,
              onTap: () => onMarkerTap(aed.location),
            ),
          ),
        );
      }

      _loadedCount = endIndex;

      // Callback with progress
      onBatchLoaded(Set.from(allMarkers), sortedAEDs.length, _loadedCount);

      print('📍 Loaded batch: $_loadedCount/${sortedAEDs.length} markers');

      // ✅ NEW: Trigger zoom after first batch if we have location
      if (!hasZoomedFirstBatch && userLocation != null && onFirstBatchLoaded != null && sortedAEDs.length >= 2) {
        final closestAEDs = sortedAEDs.take(2).map((aed) => aed.location).toList();
        print('🎯 Triggering zoom to user + 2 closest AEDs after first batch');
        onFirstBatchLoaded(userLocation, closestAEDs);
        hasZoomedFirstBatch = true;
      }

      // Yield to UI thread
      await Future.delayed(_batchDelay);
    }

    print('✅ All $_loadedCount markers loaded');
  }

  void cancel() {
    _isCancelled = true;
    print('🛑 Cancelling marker loading');
  }

  int get loadedCount => _loadedCount;
  bool get isCancelled => _isCancelled;
}