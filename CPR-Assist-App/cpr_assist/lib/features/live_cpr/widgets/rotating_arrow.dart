import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FrequencyArcGauge
//
// Pure Flutter arc gauge. The arc SVG is replaced with CustomPainter.
// The needle remains the existing SVG (frequency_arrow.svg).
//
// Arc geometry:
//   Spans from 210° to 330° (120° total sweep, opening upward like your SVG).
//   Red zone:   60–100 CPM  (left side)
//   Green zone: 100–120 CPM (top, lit up when needle is inside)
//   Red zone:   120–160 CPM (right side)
//
// When frequency is in 100–120: green zone brightens fully.
// Outside: green zone dims, red zones show at lower opacity.
// ─────────────────────────────────────────────────────────────────────────────

class FrequencyArcGauge extends StatefulWidget {
  final double frequency; // 0 = idle/no data

  const FrequencyArcGauge({super.key, required this.frequency});

  @override
  State<FrequencyArcGauge> createState() => _FrequencyArcGaugeState();
}

class _FrequencyArcGaugeState extends State<FrequencyArcGauge>
    with TickerProviderStateMixin {

  // Needle rotation
  late AnimationController _needleCtrl;
  late Animation<double>   _needleAnim;
  double _displayedAngle = 0;

  // Green zone pulse (when in correct range)
  late AnimationController _pulseCtrl;

  static const double _minFreq   = 80.0;
  static const double _maxFreq   = 140.0;
  static const double _targetMin = 100.0;
  static const double _targetMax = 120.0;

  // Arc: starts at 210°, sweeps 120° to 330°
  static const double _arcStartDeg = 180.0; // 9 o'clock (left)
  static const double _arcSweepDeg = 180.0; // sweep to 3 o'clock (right) = full semicircle

  @override
  void initState() {
    super.initState();
    _needleCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 250),
    );
    _needleAnim = const AlwaysStoppedAnimation(0.0);

    _pulseCtrl = AnimationController(
      vsync:      this,
      duration:   const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant FrequencyArcGauge old) {
    super.didUpdateWidget(old);
    final newAngle = _freqToAngle(widget.frequency);
    if ((newAngle - _displayedAngle).abs() < 0.001) return;
    _needleAnim = Tween<double>(begin: _displayedAngle, end: newAngle)
        .animate(CurvedAnimation(parent: _needleCtrl, curve: Curves.easeOut));
    _needleCtrl.forward(from: 0);
    _displayedAngle = newAngle;
  }

  @override
  void dispose() {
    _needleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // Frequency → needle rotation angle (radians, 0 = pointing straight up)
  double _freqToAngle(double freq) {
    if (freq <= 0) return 0;
    // Linear map: 60 CPM → 210°, 160 CPM → 330°, centre 110 CPM → 270° (straight up)
    final arcFrac = ((freq - _minFreq) / (_maxFreq - _minFreq)).clamp(0.0, 1.0);
    final deg = _arcStartDeg + arcFrac * _arcSweepDeg;
    return (deg - 270.0) * pi / 180.0;
  }

  bool get _inGreenZone =>
      widget.frequency >= _targetMin && widget.frequency <= _targetMax;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_needleAnim, _pulseCtrl]),
      builder: (_, __) {
        return CustomPaint(
          painter: _ArcPainter(
            frequency:  widget.frequency,
            pulseValue: _inGreenZone ? _pulseCtrl.value : 0.0,
            minFreq:    _minFreq,
            maxFreq:    _maxFreq,
            targetMin:  _targetMin,
            targetMax:  _targetMax,
            arcStartDeg: _arcStartDeg,
            arcSweepDeg: _arcSweepDeg,
          ),
          child: _buildNeedle(),
        );
      },
    );
  }

  Widget _buildNeedle() {
    return LayoutBuilder(builder: (_, constraints) {
      final double W  = constraints.maxWidth;
      final double H  = constraints.maxHeight;
      final double cx = W / 2;
      final double cy = H * 0.88;

      const double dotR    = 12.0;
      const double needleW = 20.0;
      const double needleH = 66.0;
      // total height = triangle + overlap into circle so base touches circle edge
      const double totalH  = needleH + dotR;

      return Stack(
        clipBehavior: Clip.none,
        children: [

          // ── Rotating triangle only ─────────────────────────────────────
          Positioned(
            left: cx - needleW / 2,
            top:  cy - totalH, // bottom of widget sits at circle centre (cy)
            child: AnimatedBuilder(
              animation: _needleAnim,
              builder: (_, child) => Transform.rotate(
                angle:     _needleAnim.value,
                alignment: Alignment.bottomCenter, // pivot = circle centre
                child:     child,
              ),
              child: const CustomPaint(
                size: Size(needleW, totalH),
                painter: _TrianglePainter(dotR: dotR),
              ),
            ),
          ),

          // ── Static circle at cy, drawn on top ─────────────────────────
          Positioned(
            left: cx - dotR,
            top:  cy - dotR,
            child: Container(
              width:  dotR * 2,
              height: dotR * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFACC9F6),
                border: Border.all(
                  color: const Color(0xFFDDEAFF),
                  width: 3.5,
                ),
              ),
            ),
          ),

        ],
      );
    });
  }
}

class _TrianglePainter extends CustomPainter {
  final double dotR;
  const _TrianglePainter({required this.dotR});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFDDEAFF)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 0)           // tip
      ..lineTo(size.width,     size.height)  // bottom right — touches circle edge
      ..lineTo(0,              size.height)  // bottom left
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// _ArcPainter
// ─────────────────────────────────────────────────────────────────────────────

class _ArcPainter extends CustomPainter {
  final double frequency;
  final double pulseValue;   // 0–1, used to brighten green zone
  final double minFreq, maxFreq, targetMin, targetMax;
  final double arcStartDeg, arcSweepDeg;

  const _ArcPainter({
    required this.frequency,
    required this.pulseValue,
    required this.minFreq,
    required this.maxFreq,
    required this.targetMin,
    required this.targetMax,
    required this.arcStartDeg,
    required this.arcSweepDeg,
  });

  double _degToRad(double deg) => deg * pi / 180.0;

  // Frequency → angle in degrees within the arc
  double _freqToDeg(double freq) {
    final t = ((freq - minFreq) / (maxFreq - minFreq)).clamp(0.0, 1.0);
    return arcStartDeg + t * arcSweepDeg;
  }

  bool get _inGreenZone =>
      frequency >= targetMin && frequency <= targetMax;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cx     = size.width / 2;
    final cy     = size.height * 0.88; // centre close to bottom edge
    final radius = size.width * 0.46; // large radius, near full width
    final strokeW = size.width * 0.045; // chunky stroke

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);

    // ── Zone boundaries in degrees ─────────────────────────────────────────
    final greenStartDeg = _freqToDeg(targetMin); // 100 CPM
    final greenEndDeg   = _freqToDeg(targetMax); // 120 CPM

    // Left red zone: arcStart → greenStart
    final leftRedStart  = _degToRad(arcStartDeg);
    final leftRedSweep  = _degToRad(greenStartDeg - arcStartDeg);

    // Green zone: greenStart → greenEnd
    final greenStart = _degToRad(greenStartDeg);
    final greenSweep = _degToRad(greenEndDeg - greenStartDeg);

    // Right red zone: greenEnd → arcEnd
    final rightRedStart = _degToRad(greenEndDeg);
    final rightRedSweep = _degToRad((arcStartDeg + arcSweepDeg) - greenEndDeg);

    final arcPaint = Paint()
      ..style   = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeW;

    // ── When in green zone: full green illumination + dim red ─────────────
    // When outside: dim green + bright red on the relevant side
    final bool inGreen = _inGreenZone;
    final double greenAlpha  = inGreen ? 0.85 + pulseValue * 0.15 : 0.35;
    final double redAlpha    = inGreen ? 0.30 : 0.75;

    // Left red arc
    canvas.drawArc(rect, leftRedStart, leftRedSweep, false,
        arcPaint..color = AppColors.cprRed.withValues(alpha: redAlpha));

    // Green arc
    canvas.drawArc(rect, greenStart, greenSweep, false,
        arcPaint..color = AppColors.cprGreen.withValues(alpha: greenAlpha));

    // Right red arc
    canvas.drawArc(rect, rightRedStart, rightRedSweep, false,
        arcPaint..color = AppColors.cprRed.withValues(alpha: redAlpha));

    // ── Glow on green zone when active ────────────────────────────────────
    if (inGreen) {
      final glowPaint = Paint()
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..strokeWidth = strokeW + 4 + pulseValue * 6
        ..color       = AppColors.cprGreen.withValues(alpha: 0.15 + pulseValue * 0.15)
        ..maskFilter  = MaskFilter.blur(BlurStyle.normal, 6 + pulseValue * 4);
      canvas.drawArc(rect, greenStart, greenSweep, false, glowPaint);
    }

    // ── Tick marks at 60, 80, 100, 120, 140, 160 ─────────────────────────
    for (final f in [80.0, 100.0, 120.0, 140.0]) {
      final a     = _degToRad(_freqToDeg(f));
      final isBoundary = f == 100.0 || f == 120.0;
      final inner = radius - strokeW / 2 - (isBoundary ? 6.0 : 4.0);
      final outer = radius + strokeW / 2 + (isBoundary ? 4.0 : 2.0);
      canvas.drawLine(
        Offset(cx + inner * cos(a), cy + inner * sin(a)),
        Offset(cx + outer * cos(a), cy + outer * sin(a)),
        Paint()
          ..color       = Colors.white.withValues(alpha: isBoundary ? 0.70 : 0.35)
          ..strokeWidth = isBoundary ? 2.0 : 1.2,
      );
    }

    // ── 100 / 120 labels ──────────────────────────────────────────────────
    _drawLabel(canvas, size, cx, cy, radius, strokeW, 100.0, '100');
    _drawLabel(canvas, size, cx, cy, radius, strokeW, 120.0, '120');
  }

  void _drawLabel(Canvas canvas, Size size, double cx, double cy,
      double radius, double strokeW, double freq, String text) {
    final a       = _degToRad(_freqToDeg(freq));
    final labelR = radius + strokeW + 8.0; // outside the arc
    final lx      = cx + labelR * cos(a);
    final ly      = cy + labelR * sin(a);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize:   11,
          fontWeight: FontWeight.w600,
          color:      Colors.white.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(lx - tp.width / 2, ly - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.frequency  != frequency  ||
          old.pulseValue != pulseValue;
}