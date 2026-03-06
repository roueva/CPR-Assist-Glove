import 'dart:ui' as ui;
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart' as cluster_pkg;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../models/aed_models.dart';
import '../../utils/availability_parser.dart';
import '../../widgets/aed_markers.dart';

class AEDClusterItem with cluster_pkg.ClusterItem {
  final AED aed;
  final Function(LatLng) onTap;

  AEDClusterItem(this.aed, this.onTap);

  @override
  LatLng get location => aed.location;
}

class AEDClusterManager {
  // Icon cache keyed by count
  static final Map<int, BitmapDescriptor> _iconCache = {};

  // Pre-warm icons for common cluster sizes at startup
  static Future<void> prewarmIconCache() async {
    const counts = [2, 3, 5, 10, 20, 35, 50, 75, 100, 150, 200, 300, 500, 750, 1000, 1500, 2000, 3400];
    for (final count in counts) {
      await getClusterIcon(count);
    }
  }

  static int _bucketCount(int count) {
    if (count < 10)  return count;
    if (count < 50)  return (count ~/ 5) * 5;
    if (count < 200) return (count ~/ 10) * 10;
    return (count ~/ 50) * 50;
  }

  static Future<BitmapDescriptor> getClusterIcon(int count) async {
    final key = _bucketCount(count);
    if (_iconCache.containsKey(key)) return _iconCache[key]!;
    final icon = await _buildIcon(count);
    _iconCache[key] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> _buildIcon(int count) async {
    final Size size = switch (count) {
      < 10  => const Size(40, 40),
      < 50  => const Size(48, 48),
      < 100 => const Size(56, 56),
      < 500 => const Size(64, 64),
      _     => const Size(72, 72),
    };

    const centerColor = Color(0xFF006636);
    const ringColor   = Color(0xFF93C01F);

    final recorder = ui.PictureRecorder();
    final canvas    = Canvas(recorder);
    final center    = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 2;

    canvas.drawCircle(center, outerRadius,
        Paint()..color = ringColor..style = PaintingStyle.fill);
    canvas.drawCircle(center, outerRadius - 2.0,
        Paint()..color = centerColor..style = PaintingStyle.fill);

    final fontSize = count < 100 ? 14.0 : count < 500 ? 12.0 : 11.0;
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: count.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    )..layout();

    tp.paint(canvas, Offset(
      center.dx - tp.width / 2,
      center.dy - tp.height / 2,
    ));

    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }

  // Build a single AED marker (individual, not clustered)
  static Marker buildAEDMarker(AED aed, Function(LatLng) onTap) {
    final status = AvailabilityParser.parseAvailability(aed.availability);
    final opacity = (status.isOpen && !status.isUncertain) ? 1.0 : 0.5;

    return Marker(
      markerId: MarkerId('aed_${aed.id}'),
      position: aed.location,
      icon: CustomIcons.aedUpdated,
      alpha: opacity,
      onTap: () => onTap(aed.location),
    );
  }

  static Future<Marker> buildMarkerForCluster(cluster_pkg.Cluster<AEDClusterItem> cluster) async {
    if (!cluster.isMultiple) {
      // Single AED — use the existing individual marker logic
      final item = cluster.items.first;
      final status = AvailabilityParser.parseAvailability(item.aed.availability);
      final opacity = (status.isOpen && !status.isUncertain) ? 1.0 : 0.5;
      return Marker(
        markerId: MarkerId('aed_${item.aed.id}'),
        position: cluster.location,
        icon: CustomIcons.aedUpdated,
        alpha: opacity,
        onTap: () => item.onTap(item.aed.location),
      );
    }

    // Multiple AEDs — use your green circle icon
    return Marker(
      markerId: MarkerId(cluster.getId()),
      position: cluster.location,
      icon: await getClusterIcon(cluster.count),
      onTap: () {}, // zoom-in tap handled separately
    );
  }
}