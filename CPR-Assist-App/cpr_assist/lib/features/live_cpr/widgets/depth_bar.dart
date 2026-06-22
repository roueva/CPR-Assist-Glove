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
  final double valleyDepth;     // actual recoil floor cm from firmware
  final bool   recoilAchieved;  // true = full chest recoil
  final double targetDepthCm;
  final double targetDepthMaxCm;
  final double maxDepthCm;
  final bool sessionActive;


  const AnimatedDepthBar({
    super.key,
    required this.depth,
    required this.targetDepthCm,
    required this.targetDepthMaxCm,
    this.valleyDepth       = 0.0,
    this.recoilAchieved    = false,
    this.maxDepthCm        = 6.5,
    this.sessionActive     = false,

  });

  @override
  State<AnimatedDepthBar> createState() => _AnimatedDepthBarState();
}

class _AnimatedDepthBarState extends State<AnimatedDepthBar>
    with TickerProviderStateMixin {

  // Pill dimensions
  static const double _pillH = 70.0;  // taller — more prominent
  static const double _pillW = 124.0; // wider

  late AnimationController _ctrl;
  late AnimationController _pillPulse;
  late Animation<double>   _anim;
  double _lastTarget = 0.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 40),
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
    final double target = widget.depth.clamp(0.0, widget.maxDepthCm);
    if ((target - _lastTarget).abs() < 0.01) return;
    _lastTarget = target;
    _anim = Tween<double>(begin: _anim.value, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.linear));
    _ctrl.forward(from: 0);
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
          final bool releaseActive = widget.sessionActive && (widget.recoilAchieved || v < 1.0);
          final bool depthActive   = widget.sessionActive && v >= widget.targetDepthCm;
          final bool isExcessive   = widget.sessionActive && v > widget.targetDepthMaxCm;

          // ── Current line Y position ─────────────────────────────────────
          final double lineY = cmToY(v.clamp(0.0, widget.maxDepthCm));

          // ── Fill bottom for the track zone (clamped to trackBottom) ─────
          final double fillBottom = lineY.clamp(trackTop, trackBottom);

          // ── Overflow fill bottom ────────────────────────────────────────
          final double overflowFillBot = isExcessive
              ? lineY.clamp(overflowTop, overflowBottom)
              : overflowTop;
// Track is narrower than pills so pills appear to "cap" the track
          const double trackW = _pillW * 0.70;

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
              hasData:         widget.sessionActive,
              releaseActive:   releaseActive,
              depthActive:     depthActive,
              isExcessive:     isExcessive,
              depth:           v,
              trackW:          trackW,
              targetDepthCm:   widget.targetDepthCm,
              targetDepthMaxCm: widget.targetDepthMaxCm,
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
  final double W, H, pillW, pillH, trackW, targetDepthCm, targetDepthMaxCm, pulseValue;
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
    required this.targetDepthMaxCm,
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

  Radius get rTrack => const Radius.circular(10);

  // ── Colors — all from AppColors, no raw values ───────────────────────────
  static const Color _trackBg       = AppColors.depthBarTrack;
  static const Color _pillBg        = AppColors.depthBarPillBg;
  static const Color _borderInactive = AppColors.success;

  @override
  void paint(Canvas canvas, Size size) {
    // ── 1. Full track background — low opacity, full height 0→8cm ──────────
    // This is the "empty" state of the fill, always visible
    // ── 1. Full track background ──────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        trackLeft, relPillTop, trackRight, H,
        bottomLeft: rTrack, bottomRight: rTrack,
      ),
      Paint()..color = isExcessive
          ? AppColors.depthFillBad.withValues(alpha: 0.18)
          : (hasData && depth > 0.05 && depth < targetDepthCm)
          ? AppColors.depthFillWarn.withValues(alpha: 0.12)
          : _trackBg,
    );

    // ── 2. Colored fill — one continuous column from top to line ───────────
    // Color determined by which zone the line is currently in:
    //   0–5 cm  → light blue
    //   5–6 cm  → green
    //   6–7 cm  → red (and the 0–6 portion stays green)
    if (hasData && depth > 0.05) {
      if (!isExcessive && depth < targetDepthCm) {
        // Too shallow — amber fill
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            trackLeft, relPillTop, trackRight, lineY,
            bottomLeft: rTrack, bottomRight: rTrack,
          ),
          Paint()..color = AppColors.depthFillWarn.withValues(alpha: 0.65),
        );
      } else if (!isExcessive && depth >= targetDepthCm) {
        // Upper green portion — sharp bottom
        canvas.drawRect(
          Rect.fromLTRB(trackLeft, relPillTop, trackRight, depthPillTop),
          Paint()..color = AppColors.depthFillGood.withValues(alpha: 0.6),
        );
        // Lower green portion — round bottom
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            trackLeft, depthPillTop, trackRight,
            lineY.clamp(depthPillTop, depthPillBot),
            bottomLeft: rTrack, bottomRight: rTrack,
          ),
          Paint()..color = AppColors.depthFillGood.withValues(alpha: 0.85),
        );
      } else {
        // Excessive — coral red fill
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            trackLeft, relPillTop, trackRight,
            lineY.clamp(relPillTop, H),
            bottomLeft: rTrack, bottomRight: rTrack,
          ),
          Paint()..color = AppColors.depthFillBad.withValues(alpha: 0.65),
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
      color: AppColors.feedbackGood,
    );

    // ── 4. DEPTH pill — always on top of fill ─────────────────────────────
    _drawPill(
      canvas,
      top: depthPillTop,
      bot: depthPillBot,
      label: 'DEPTH',
      active: depthActive,
      color: isExcessive ? AppColors.feedbackBad : AppColors.feedbackGood,
    );

    // ── 4b. Depth range labels — beside the DEPTH pill ────────────────────
    _drawSideLabel(canvas, text: '${targetDepthCm.toStringAsFixed(0)} cm',    y: depthPillTop - 8.0);
    _drawSideLabel(canvas, text: '${targetDepthMaxCm.toStringAsFixed(0)} cm', y: depthPillBot + 8.0);

    // ── 5. Indicator line — skip if inside a pill ──────────────────────────
    if (hasData && depth > 0.05) {
      final bool insideRelease = lineY >= relPillTop && lineY <= relPillBot;
      final bool insideDepth = lineY >= depthPillTop && lineY <= depthPillBot;

      if (!insideRelease && !insideDepth) {
        final Color lineColor = isExcessive
            ? AppColors.feedbackBad
            : depth >= targetDepthCm
            ? AppColors.feedbackGood
            : AppColors.feedbackWarn;

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
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textOnDark,
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
  // ── Side label helper — drawn to the LEFT of the pill ───────────────────
  void _drawSideLabel(Canvas canvas, {required String text, required double y}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize:   8,
          fontWeight: FontWeight.w600,
          color:      AppColors.textOnDark.withValues(alpha: 0.60),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Anchor to trackRight — always within widget bounds, just outside the track column
    final double x = trackRight + 4.0;
    tp.paint(canvas, Offset(x, y - tp.height / 2));
  }

  @override
  bool shouldRepaint(_DepthBarPainter old) =>
      old.depth != depth ||
          old.fillBottom != fillBottom ||
          old.overflowFillBot != overflowFillBot ||
          old.releaseActive != releaseActive ||
          old.depthActive != depthActive ||
          old.isExcessive != isExcessive ||
          old.pulseValue != pulseValue ||
          old.targetDepthCm    != targetDepthCm    ||
          old.targetDepthMaxCm != targetDepthMaxCm ||
          old.depthPillTop     != depthPillTop     ||
          old.depthPillBot     != depthPillBot;
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
    if (widget.isCorrect) {
      _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.value = 1.0;
    }
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
    final color = widget.isCorrect ? AppColors.success : AppColors.primary;
    return ScaleTransition(
      scale: _pulseCtrl,
      child: Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color:        color,
          borderRadius: BorderRadius.circular(widget.height / 2),
          border: Border.all(
            color: widget.isCorrect ? AppColors.primary : AppColors.success,
            width: 3,
          ),
          boxShadow: widget.isCorrect ? [
            BoxShadow(
              color:        AppColors.success.withValues(alpha: 0.6),
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