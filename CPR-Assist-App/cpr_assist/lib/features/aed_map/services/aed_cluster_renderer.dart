import 'dart:ui' as ui;
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart' as cluster_pkg;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../widgets/availability_parser.dart';
import '../../../models/aed_models.dart';
import '../widgets/aed_markers.dart';

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
    const counts = [2, 5, 10, 50, 100, 500];
    for (final count in counts) {
      await getClusterIcon(count);
    }
  }

  static Future<BitmapDescriptor> getClusterIcon(int count) async {
    if (_iconCache.containsKey(count)) return _iconCache[count]!;
    final icon = await _buildIcon(count);
    _iconCache[count] = icon;
    return icon;
  }


  static Future<BitmapDescriptor> _buildIcon(int count) async {
    const double scale = 3.0; // render at 3x for crisp display on high-DPI screens

    final Size logicalSize = switch (count) {
      < 10  => const Size(40, 40),
      < 50  => const Size(48, 48),
      < 100 => const Size(56, 56),
      < 500 => const Size(64, 64),
      _     => const Size(72, 72),
    };

    final double w = logicalSize.width  * scale;
    final double h = logicalSize.height * scale;

    const centerColor = Color(0xFF006636);
    const ringColor   = Color(0xFF93C01F);

    final recorder = ui.PictureRecorder();
    final canvas    = Canvas(recorder);

    canvas.scale(scale, scale);

    final center      = Offset(logicalSize.width / 2, logicalSize.height / 2);
    final outerRadius = logicalSize.width / 2 - 2;

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
      center.dx - tp.width  / 2,
      center.dy - tp.height / 2,
    ));

    final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      imagePixelRatio: scale,  // tells Google Maps this is a 3x image
    );
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