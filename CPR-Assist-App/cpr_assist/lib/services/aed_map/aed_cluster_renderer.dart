import 'dart:math';
import 'dart:ui' as ui;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../models/aed_models.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../widgets/aed_markers.dart';

class ClusterPoint {
  final LatLng location;
  final List<AED> aeds;

  ClusterPoint(this.location, this.aeds);

  int get count => aeds.length;
  bool get isCluster => aeds.length > 1;
}

class SimpleClusterManager {
  static const double _clusterDistance = 0.002; // ~200m at equator

  /// Group AEDs into clusters based on zoom level
  static List<ClusterPoint> clusterAEDs(List<AED> aeds, double zoom) {
    if (aeds.isEmpty) return [];

    print("🔍 clusterAEDs() called:");
    print("   → AED count: ${aeds.length}");
    print("   → Zoom level: $zoom");

    // At high zoom (street level), show all individual AEDs
    if (zoom >= 16.0) {
      print("   → Zoom >= 16.0 - returning ALL individual AEDs");
      return aeds.map((aed) => ClusterPoint(aed.location, [aed])).toList();
    }

    // ✅ At very low zoom, use GRID-BASED clustering
    if (zoom < 8.0) {
      print("   → Low zoom - using GRID clustering");
      return _gridBasedClustering(aeds, zoom);
    }

    // Normal distance-based clustering for medium zoom
    print("   → Zoom < 16.0 - performing distance clustering");
    final distance = _getClusterDistanceForZoom(zoom);
    print("   → Cluster distance: $distance");

    final List<ClusterPoint> clusters = [];
    final List<AED> remaining = List.from(aeds);

    while (remaining.isNotEmpty) {
      final first = remaining.removeAt(0);
      final cluster = [first];

      remaining.removeWhere((aed) {
        final dist = _distance(first.location, aed.location);
        if (dist < distance) {
          cluster.add(aed);
          return true;
        }
        return false;
      });

      final centerLat = cluster.map((a) => a.location.latitude).reduce((a, b) => a + b) / cluster.length;
      final centerLng = cluster.map((a) => a.location.longitude).reduce((a, b) => a + b) / cluster.length;

      clusters.add(ClusterPoint(LatLng(centerLat, centerLng), cluster));
    }

    print("   → Created ${clusters.length} cluster points");
    return clusters;
  }

  /// ✅ Grid-based clustering for low zoom levels
  static List<ClusterPoint> _gridBasedClustering(List<AED> aeds, double zoom) {
    // Determine grid size based on zoom
    final double gridSize = _getGridSizeForZoom(zoom);
    print("   → Grid size: $gridSize degrees");

    // Group AEDs into grid cells
    final Map<String, List<AED>> gridCells = {};

    for (final aed in aeds) {
      // Round coordinates to grid cell
      final cellLat = (aed.location.latitude / gridSize).floor() * gridSize;
      final cellLng = (aed.location.longitude / gridSize).floor() * gridSize;
      final cellKey = '${cellLat}_$cellLng';

      gridCells.putIfAbsent(cellKey, () => []).add(aed);
    }

    print("   → Created ${gridCells.length} grid cells");

    // Create cluster for each grid cell
    final List<ClusterPoint> clusters = [];
    for (final cell in gridCells.values) {
      final centerLat = cell.map((a) => a.location.latitude).reduce((a, b) => a + b) / cell.length;
      final centerLng = cell.map((a) => a.location.longitude).reduce((a, b) => a + b) / cell.length;
      clusters.add(ClusterPoint(LatLng(centerLat, centerLng), cell));
    }

    // ✅ Force maximum cluster count based on zoom
    final maxClusters = _getMaxClustersForZoom(zoom);
    if (clusters.length > maxClusters) {
      print("   → Too many clusters (${clusters.length}) - reducing to $maxClusters");
      return _mergeSmallestClusters(clusters, maxClusters);
    }

    return clusters;
  }

  /// ✅ Get maximum number of clusters allowed at each zoom level
  static int _getMaxClustersForZoom(double zoom) {
    if (zoom >= 8) return 100;   // Many clusters
    if (zoom >= 7) return 50;    // Medium
    if (zoom >= 6) return 25;    // Fewer
    if (zoom >= 5) return 12;    // Very few
    if (zoom >= 4) return 5;     // Only 5 clusters ← NEW
    return 1;                    // ONE cluster for entire Greece ← NEW
  }

  /// ✅ Merge smallest clusters until we reach target count
  static List<ClusterPoint> _mergeSmallestClusters(List<ClusterPoint> clusters, int targetCount) {
    if (clusters.length <= targetCount) return clusters;

    print("   → Merging ${clusters.length} clusters down to $targetCount");

    while (clusters.length > targetCount) {
      // Find the two closest clusters to merge
      ClusterPoint? closest1;
      ClusterPoint? closest2;
      double minDistance = double.infinity;

      for (int i = 0; i < clusters.length - 1; i++) {
        for (int j = i + 1; j < clusters.length; j++) {
          final dist = _distance(clusters[i].location, clusters[j].location);
          if (dist < minDistance) {
            minDistance = dist;
            closest1 = clusters[i];
            closest2 = clusters[j];
          }
        }
      }

      if (closest1 != null && closest2 != null) {
        // Merge the two closest clusters
        clusters.remove(closest1);
        clusters.remove(closest2);

        final mergedAEDs = [...closest1.aeds, ...closest2.aeds];
        final centerLat = mergedAEDs.map((a) => a.location.latitude).reduce((a, b) => a + b) / mergedAEDs.length;
        final centerLng = mergedAEDs.map((a) => a.location.longitude).reduce((a, b) => a + b) / mergedAEDs.length;

        clusters.add(ClusterPoint(LatLng(centerLat, centerLng), mergedAEDs));
      } else {
        break; // Safety exit
      }
    }

    return clusters;
  }

  /// Get grid size based on zoom level - MUCH more aggressive
  static double _getGridSizeForZoom(double zoom) {
    if (zoom >= 8) return 0.05;    // ~5km grid
    if (zoom >= 7) return 0.15;    // ~15km grid
    if (zoom >= 6) return 0.5;     // ~50km grid
    if (zoom >= 5) return 1.0;     // ~100km grid
    if (zoom >= 4) return 2.5;     // ~250km grid ← NEW
    if (zoom >= 3) return 5.0;     // ~500km grid ← NEW
    return 10.0;                   // ~1000km grid (entire Greece = 1 cluster) ← NEW
  }

  /// Calculate distance between two points (simple Euclidean approximation)
  static double _distance(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return sqrt(dx * dx + dy * dy);
  }

  /// Get clustering distance based on zoom level
  static double _getClusterDistanceForZoom(double zoom) {
    if (zoom >= 17) return 0.0001;   // ~10m
    if (zoom >= 16) return 0.0005;   // ~50m
    if (zoom >= 15) return 0.002;    // ~200m
    if (zoom >= 14) return 0.005;    // ~500m
    if (zoom >= 12) return 0.015;    // ~1.5km
    if (zoom >= 10) return 0.04;     // ~4km
    if (zoom >= 8) return 0.1;       // ~10km
    // Grid-based clustering takes over below zoom 8
    return 0.2;
  }
}

class ClusterMarkerBuilder {
  // Cache for cluster icons to avoid regenerating them
  static final Map<int, BitmapDescriptor> _clusterIconCache = {};

  static Future<Marker> buildMarker(
      ClusterPoint cluster,
      Function(LatLng) onTap, {
        Map<String, LatLng>? previousPositions,
      }) async {
    final markerId = MarkerId(getMarkerId(cluster));

    if (cluster.isCluster) {
      // ✅ Check if this cluster is splitting from a parent
      LatLng? parentPosition;
      if (previousPositions != null) {
        // Look for nearby previous cluster that could be the parent
        parentPosition = _findParentCluster(cluster.location, previousPositions);
      }

      // Create cluster marker with animation hint
      return Marker(
        markerId: markerId,
        position: cluster.location,
        icon: await _getCachedClusterIcon(cluster.count),
        alpha: parentPosition != null ? 0.7 : 1.0, // Slightly transparent during split
        anchor: const Offset(0.5, 0.5),
        onTap: () {
          print('📍 Cluster with ${cluster.count} AEDs tapped');
        },
      );
    } else {
      // Single AED marker - check if splitting from cluster
      LatLng? parentPosition;
      if (previousPositions != null) {
        parentPosition = _findParentCluster(cluster.location, previousPositions);
      }

      return Marker(
        markerId: markerId,
        position: cluster.location,
        icon: CustomIcons.aedUpdated,
        alpha: parentPosition != null ? 0.8 : 1.0, // Fade in effect
        anchor: const Offset(0.5, 0.5),
        onTap: () => onTap(cluster.location),
      );
    }
  }

  /// ✅ NEW: Find parent cluster that this marker split from
  static LatLng? _findParentCluster(LatLng position, Map<String, LatLng> previousPositions) {
    // Look for a previous cluster within 0.05 degrees (~5km)
    for (final prevPos in previousPositions.values) {
      final distance = _distance(position, prevPos);
      if (distance < 0.05) {
        return prevPos;
      }
    }
    return null;
  }

  /// ✅ NEW: Public method to get marker ID (used for tracking)
  static String getMarkerId(ClusterPoint cluster) {
    if (cluster.isCluster) {
      // Use rounded coordinates for consistent cluster IDs
      final lat = (cluster.location.latitude * 100).round() / 100;
      final lng = (cluster.location.longitude * 100).round() / 100;
      return 'cluster_${lat}_${lng}_${cluster.count}';
    } else {
      return 'aed_${cluster.aeds.first.id}';
    }
  }

  /// ✅ Helper method for distance calculation
  static double _distance(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return sqrt(dx * dx + dy * dy);
  }

  /// Get cached cluster icon (or create and cache)
  static Future<BitmapDescriptor> _getCachedClusterIcon(int count) async {
    if (_clusterIconCache.containsKey(count)) {
      return _clusterIconCache[count]!;
    }

    final icon = await _createClusterIcon(count);
    _clusterIconCache[count] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> _createClusterIcon(int count) async {
    // ✅ Smaller base sizes for correct display
    final Size size;
    if (count < 10) {
      size = const Size(40, 40);
    } else if (count < 50) {
      size = const Size(48, 48);
    } else if (count < 100) {
      size = const Size(56, 56);
    } else if (count < 500) {
      size = const Size(64, 64);
    } else {
      size = const Size(72, 72);
    }

    // Fixed colors
    const centerColor = Color(0xFF006636);
    const ringColor = Color(0xFF93C01F);
    const textColor = Colors.white;

    // Create the marker image
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 2;

    // Draw circular shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawCircle(center + const Offset(1, 1), outerRadius, shadowPaint);

    // Draw outer ring (light green)
    final Paint ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, outerRadius, ringPaint);

    // Draw inner circle (dark green)
    const ringWidth = 2.0;
    final innerRadius = outerRadius - ringWidth;

    final Paint circlePaint = Paint()
      ..color = centerColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, innerRadius, circlePaint);

    // Draw white text
    final fontSize = count < 100 ? 14.0 : count < 500 ? 12.0 : 11.0;

    final TextPainter textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.text = TextSpan(
      text: count.toString(),
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );

    // Convert to image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );

    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List imageData = byteData!.buffer.asUint8List();

    // ✅ CORRECT: Use BitmapDescriptor.bytes (NOT fromBytes)
    return BitmapDescriptor.bytes(imageData);
  }


  /// Build marker at specific animated position
  static Future<Marker> buildMarkerAtPosition(
      ClusterPoint cluster,
      LatLng position,
      Function(LatLng) onTap, {
        double alpha = 1.0,
      }) async {
    final markerId = MarkerId(getMarkerId(cluster));

    if (cluster.isCluster) {
      return Marker(
        markerId: markerId,
        position: position,
        icon: await _getCachedClusterIcon(cluster.count),
        alpha: 1.0,
        anchor: const Offset(0.5, 0.5),
        onTap: () {
          print('📍 Cluster with ${cluster.count} AEDs tapped');
        },
      );
    } else {
      return Marker(
        markerId: markerId,
        position: position,
        icon: CustomIcons.aedUpdated,
        alpha: 1.0,
        anchor: const Offset(0.5, 0.5),
        onTap: () => onTap(cluster.location),
      );
    }
  }
}