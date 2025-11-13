import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class StaticPinOverlay extends StatelessWidget {
  final LatLngBounds? visibleRegion;
  final bool isLoading;

  const StaticPinOverlay({
    super.key,
    this.visibleRegion,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();

    return Positioned.fill(
      child: CustomPaint(
        painter: PinOverlayPainter(visibleRegion: visibleRegion),
      ),
    );
  }
}

class PinOverlayPainter extends CustomPainter {
  final LatLngBounds? visibleRegion;

  PinOverlayPainter({this.visibleRegion});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw a semi-transparent layer with grid dots representing AEDs
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    // Simple grid pattern (you can make this more sophisticated)
    for (double x = 0; x < size.width; x += 50) {
      for (double y = 0; y < size.height; y += 50) {
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }

    // Add loading text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Loading AEDs...',
        style: TextStyle(
          color: Colors.black87,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size.width / 2 - textPainter.width / 2, 20),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}