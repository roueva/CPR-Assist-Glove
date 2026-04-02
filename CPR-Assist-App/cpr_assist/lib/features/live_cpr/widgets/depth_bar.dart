import 'package:flutter/material.dart';
import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedDepthBar — pure Flutter, no SVGs
//
// Depth range: 0–8 cm maps linearly to widget height.
//
//   0–1 cm   → RELEASE pill   (glows green)
//   1–5 cm   → track          (light blue fill grows downward)
//   5–6 cm   → DEPTH pill     (glows green when line inside)
//   6–7 cm   → overflow zone  (red fill + line)
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedDepthBar extends StatefulWidget {
  final double depth;           // live cm from BLE, 0–8
  final bool   recoilAchieved;  // true = full chest recoil
  final double targetDepthCm;   // where DEPTH pill starts  (adult=5, peds=4)
  final double targetDepthMaxCm;// where DEPTH pill ends    (adult=6, peds=5)
  final double maxDepthCm;      // absolute max shown       (default 8)

  const AnimatedDepthBar({
    super.key,
    required this.depth,
    this.recoilAchieved    = false,
    this.targetDepthCm     = 5.0,
    this.targetDepthMaxCm  = 6.0,
    this.maxDepthCm        = 7.0,
  });

  @override
  State<AnimatedDepthBar> createState() => _AnimatedDepthBarState();
}

class _AnimatedDepthBarState extends State<AnimatedDepthBar>
    with TickerProviderStateMixin {

  // Pill dimensions
  static const double _pillH = 60.0;  // taller — more prominent
  static const double _pillW = 124.0; // wider

  late AnimationController _ctrl;
  late AnimationController _pillPulse;
  late Animation<double>   _anim;
  double _displayed = 0.0;
  bool   _hasData   = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120),
    );
    _pillPulse = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _anim = const AlwaysStoppedAnimation(0.0);
  }

  @override
  void didUpdateWidget(covariant AnimatedDepthBar old) {
    super.didUpdateWidget(old);
    final double target = widget.recoilAchieved
        ? 0.0
        : widget.depth.clamp(0.0, widget.maxDepthCm);
    if ((target - _displayed).abs() < 0.01) return;
    _anim = Tween<double>(begin: _displayed, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward(from: 0);
    _displayed = target;
    if (!_hasData && widget.depth > 0.05) setState(() => _hasData = true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pillPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      final double W = constraints.maxWidth;
      final double H = constraints.maxHeight;

      // ── Map cm → px linearly across full widget height ─────────────────
      // 0 cm = y:0 (top), maxDepthCm = y:H (bottom)
      double cmToY(double cm) => (cm / widget.maxDepthCm) * H;

      // Key Y positions
      final double relPillTop    = cmToY(0);               // 0 cm
      final double relPillBot    = cmToY(1);               // 1 cm — RELEASE pill bottom
      final double trackTop      = relPillBot;             // 1 cm — fill starts
      final double depthPillTop  = cmToY(widget.targetDepthCm);     // 5 cm
      final double depthPillBot  = cmToY(widget.targetDepthMaxCm);  // 6 cm
      final double trackBottom   = depthPillTop;           // fill ends at DEPTH pill top
      final double overflowTop   = depthPillBot;           // 6 cm — overflow starts
      final double overflowBottom= H;                      // 7 cm

      return AnimatedBuilder(
        animation: Listenable.merge([_anim, _pillPulse]),
        builder: (_, __) {
          final double v = _anim.value;

          // ── State flags ─────────────────────────────────────────────────
          final bool releaseActive = !_hasData || widget.recoilAchieved || v < 1.0;
          final bool depthActive   = _hasData && v >= widget.targetDepthCm;
          final bool isExcessive   = _hasData && v > widget.targetDepthMaxCm;

          // ── Current line Y position ─────────────────────────────────────
          final double lineY = cmToY(v.clamp(0.0, widget.maxDepthCm));

          // ── Fill bottom for the track zone (clamped to trackBottom) ─────
          final double fillBottom = lineY.clamp(trackTop, trackBottom);

          // ── Overflow fill bottom ────────────────────────────────────────
          final double overflowFillBot = isExcessive
              ? lineY.clamp(overflowTop, overflowBottom)
              : overflowTop;
// Track is narrower than pills so pills appear to "cap" the track
          final double trackW = _pillW * 0.55;

          return CustomPaint(
            size: Size(W, H),
            painter: _DepthBarPainter(
              pulseValue: _pillPulse.value,
              W:               W,
              H:               H,
              pillW:           _pillW,
              pillH:           _pillH,
              relPillTop:      relPillTop,
              relPillBot:      relPillBot,
              depthPillTop:    depthPillTop,
              depthPillBot:    depthPillBot,
              trackTop:        trackTop,
              fillBottom:      fillBottom,
              overflowTop:     overflowTop,
              overflowFillBot: overflowFillBot,
              lineY:           lineY,
              hasData:         _hasData,
              releaseActive:   releaseActive,
              depthActive:     depthActive,
              isExcessive:     isExcessive,
              depth:           v,
              trackW: trackW,
              targetDepthCm:  widget.targetDepthCm,
            ),
          );
        },
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DepthBarPainter
// Draws everything: track outline, fill zones, pills, indicator line.
// ─────────────────────────────────────────────────────────────────────────────

class _DepthBarPainter extends CustomPainter {
  final double W, H, pillW, pillH, trackW, targetDepthCm, pulseValue;
  final double relPillTop, relPillBot;
  final double depthPillTop, depthPillBot;
  final double trackTop, fillBottom;
  final double overflowTop, overflowFillBot;
  final double lineY;
  final bool hasData, releaseActive, depthActive, isExcessive;
  final double depth;

  const _DepthBarPainter({
    required this.W, required this.H,
    required this.pillW, required this.pillH, required this.trackW,
    required this.targetDepthCm,
    required this.pulseValue,
    required this.relPillTop, required this.relPillBot,
    required this.depthPillTop, required this.depthPillBot,
    required this.trackTop, required this.fillBottom,
    required this.overflowTop, required this.overflowFillBot,
    required this.lineY,
    required this.hasData,
    required this.releaseActive,
    required this.depthActive,
    required this.isExcessive,
    required this.depth,
  });

  // ── Shared geometry ──────────────────────────────────────────────────────
  double get cx => W / 2;

// Pills are wider
  double get pillLeft => cx - pillW / 2;

  double get pillRight => cx + pillW / 2;

// Track is narrower
  double get trackLeft => cx - trackW / 2;

  double get trackRight => cx + trackW / 2;

  Radius get rPill => Radius.circular(pillH / 2);

  Radius get rTrack => const Radius.circular(4);

  // ── Colors ───────────────────────────────────────────────────────────────
  static const Color _trackBg = Color(0x55194E9D); // very subtle track hint
  static const Color _fillBlue = Color(0xFF3A72C8); // mid-blue fill — lighter than pill
  static const Color _pillBg = Color(
      0xFF0D3270); // darker blue pill — clearly different
  static const Color _borderInactive = Color(0xFF2E7D32); // cprGreen always

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Full track background — low opacity, full height 0→8cm ──────────
    // This is the "empty" state of the fill, always visible
    canvas.drawRRect(
      RRect.fromLTRBR(trackLeft, relPillTop, trackRight, H, rTrack),
      Paint()
        ..color = _trackBg,
    );

    // ── 2. Colored fill — one continuous column from top to line ───────────
    // Color determined by which zone the line is currently in:
    //   0–5 cm  → light blue
    //   5–6 cm  → green
    //   6–7 cm  → red (and the 0–6 portion stays green)
    if (hasData && depth > 0.05) {
      if (!isExcessive && depth < targetDepthCm) {
        // Light blue fill from top to line
        canvas.drawRRect(
          RRect.fromLTRBR(trackLeft, relPillTop, trackRight, lineY, rTrack),
          Paint()
            ..color = _fillBlue.withValues(alpha: 0.60),
        );
      } else if (!isExcessive && depth >= targetDepthCm) {
        // Whole track turns green (low opacity) — unified success signal
        canvas.drawRRect(
          RRect.fromLTRBR(
              trackLeft, relPillTop, trackRight, depthPillTop, rTrack),
          Paint()
            ..color = AppColors.cprGreen.withValues(alpha: 0.6),
        );
        // Solid green fill from depth pill top down to line
        canvas.drawRRect(
          RRect.fromLTRBR(
            trackLeft, depthPillTop, trackRight,
            lineY.clamp(depthPillTop, depthPillBot),
            rTrack,
          ),
          Paint()
            ..color = AppColors.cprGreen.withValues(alpha: 0.85),
        );
      }else {
        // Excessive: blue 0→5, green 5→6, red 6→line
        canvas.drawRRect(
          RRect.fromLTRBR(
              trackLeft, relPillTop, trackRight, depthPillTop, rTrack),
          Paint()
            ..color = _fillBlue.withValues(alpha: 0.60),
        );
        canvas.drawRect(
          Rect.fromLTRB(trackLeft, depthPillTop, trackRight, depthPillBot),
          Paint()
            ..color = AppColors.cprGreen.withValues(alpha: 0.85),
        );
        canvas.drawRRect(
          RRect.fromLTRBR(
            trackLeft, depthPillBot, trackRight,
            lineY.clamp(depthPillBot, H),
            rTrack,
          ),
          Paint()
            ..color = AppColors.cprRed.withValues(alpha: 0.55),
        );
      }
    }

    // ── 3. RELEASE pill — always on top of fill ────────────────────────────
    _drawPill(
      canvas,
      top: relPillTop,
      bot: relPillBot,
      label: 'RELEASE',
      active: releaseActive,
      color: AppColors.cprGreen,
    );

    // ── 4. DEPTH pill — always on top of fill ─────────────────────────────
    _drawPill(
      canvas,
      top: depthPillTop,
      bot: depthPillBot,
      label: 'DEPTH',
      active: depthActive,
      color: isExcessive ? AppColors.cprRed : AppColors.cprGreen,
    );

    // ── 5. Indicator line — skip if inside a pill ──────────────────────────
    if (hasData && depth > 0.05) {
      final bool insideRelease = lineY >= relPillTop && lineY <= relPillBot;
      final bool insideDepth = lineY >= depthPillTop && lineY <= depthPillBot;

      if (!insideRelease && !insideDepth) {
        final Color lineColor = isExcessive
            ? AppColors.cprRed
            : depth >= targetDepthCm
            ? AppColors.cprGreen
            : _fillBlue;

        final double lineHalfW = pillW * 0.45; // wider than track, narrower than pill
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - lineHalfW, lineY - 4.0,
            cx + lineHalfW, lineY + 4.0,
            const Radius.circular(4),
          ),
          Paint()
            ..color = lineColor
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
// Solid bright center on top of the soft glow
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - lineHalfW, lineY - 2.5,
            cx + lineHalfW, lineY + 2.5,
            const Radius.circular(3),
          ),
          Paint()
            ..color = lineColor,
        );
      }
    }
  }

  // ── Pill drawing helper ──────────────────────────────────────────────────
  void _drawPill(Canvas canvas, {
    required double top,
    required double bot,
    required String label,
    required bool active,
    required Color color,
  }) {
    final RRect pillRect = RRect.fromLTRBR(
        pillLeft, top, pillRight, bot, rPill);

    // Fill
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = active ? color : _pillBg,
    );

    // Border
    // Border — always the active color (teal green), brighter when active
    canvas.drawRRect(
      pillRect,
      Paint()
        ..color = active ? color : _borderInactive
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // Glow when active
// Animated glow when active — pulses using pulseValue 0→1→0
    if (active) {
      // Outer glow — expands and contracts
      final double glowRadius = 6.0 + pulseValue * 8.0;
      final double glowAlpha = 0.20 + pulseValue * 0.25;
      canvas.drawRRect(
        pillRect,
        Paint()
          ..color = color.withValues(alpha: glowAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius),
      );
      // Scale pulse — pill slightly grows
      final double scale = 1.0 + pulseValue * 0.025;
      final double dw = pillW * (scale - 1) / 2;
      final double dh = (bot - top) * (scale - 1) / 2;
      final RRect scaledRect = RRect.fromLTRBR(
        pillLeft - dw, top - dh,
        pillRight + dw, bot + dh,
        Radius.circular((bot - top) / 2 * scale),
      );
      // Bright border pulse
      canvas.drawRRect(
        scaledRect,
        Paint()
          ..color = color.withValues(alpha: 0.40 + pulseValue * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 + pulseValue * 2.0,
      );
    }

    // Label text
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active
              ? AppColors.textOnDark
              : AppColors.textOnDark.withValues(alpha: 0.60),
        ),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout();

    tp.paint(
      canvas,
      Offset(cx - tp.width / 2, top + (bot - top) / 2 - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_DepthBarPainter old) =>
      old.depth != depth ||
          old.fillBottom != fillBottom ||
          old.overflowFillBot != overflowFillBot ||
          old.releaseActive != releaseActive ||
          old.depthActive != depthActive ||
          old.isExcessive != isExcessive ||
          old.pulseValue != pulseValue;
}

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedPill — kept for external use elsewhere in the app
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedPill extends StatefulWidget {
  final String label;
  final bool   isCorrect;
  final double width;
  final double height;

  const AnimatedPill({
    super.key,
    required this.label,
    required this.isCorrect,
    this.width  = 117,
    this.height = 37,
  });

  @override
  State<AnimatedPill> createState() => _AnimatedPillState();
}

class _AnimatedPillState extends State<AnimatedPill>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync:      this,
      duration:   const Duration(milliseconds: 800),
      lowerBound: 0.98,
      upperBound: 1.05,
    );
    if (widget.isCorrect) _pulseCtrl.repeat(reverse: true);
    else _pulseCtrl.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant AnimatedPill old) {
    super.didUpdateWidget(old);
    if (widget.isCorrect == old.isCorrect) return;
    if (widget.isCorrect) {
      _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.value = 1.0;
    }
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final color = widget.isCorrect ? AppColors.cprGreen : AppColors.primary;
    return ScaleTransition(
      scale: _pulseCtrl,
      child: Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color:        color,
          borderRadius: BorderRadius.circular(widget.height / 2),
          border: Border.all(
            color: widget.isCorrect ? AppColors.primary : AppColors.cprGreen,
            width: 3,
          ),
          boxShadow: widget.isCorrect ? [
            BoxShadow(
              color:        AppColors.cprGreen.withValues(alpha: 0.6),
              blurRadius:   AppSpacing.sm,
              spreadRadius: AppSpacing.xxs,
            ),
          ] : const [],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: AppTypography.poppins(
            size:   AppSpacing.md - AppSpacing.xxs,
            weight: FontWeight.w600,
            color:  AppColors.textOnDark,
          ),
        ),
      ),
    );
  }
}