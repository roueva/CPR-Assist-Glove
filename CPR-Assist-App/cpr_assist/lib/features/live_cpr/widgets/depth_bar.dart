import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedDepthBar
//
// Shows the full compression/recoil cycle as a vertical bar.
//
// Physics:
//   • Top    = full recoil (0 cm — hand fully released)
//   • Bottom = maximum depth (6 cm — deepest compression)
//
// The indicator line moves between these extremes in real time:
//   - When depth == 0 or recoilAchieved == true → line at TOP
//   - As depth increases → line moves DOWN
//   - As depth decreases back toward 0 → line moves UP
//
// The BLE live stream sends depth as a rolling average that stays at the
// last compression value between compressions. To show the return stroke,
// we use recoilAchieved (glove flag) to force the indicator back to 0.
//
// RELEASE pill (top)  — lights green when recoilAchieved == true
// DEPTH   pill (bottom) — lights green when depth > targetDepth
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedDepthBar extends StatefulWidget {
  /// Live depth from BLE — 0–6 cm. Moves the indicator down as it increases.
  final double depth;

  /// True when the glove detects full chest recoil. Forces indicator to top.
  final bool recoilAchieved;

  /// Depth at which the DEPTH pill lights green (cm). Default = 5.0 (adult).
  final double targetDepthCm;

  const AnimatedDepthBar({
    super.key,
    required this.depth,
    this.recoilAchieved  = false,
    this.targetDepthCm   = 5.0,
  });

  @override
  State<AnimatedDepthBar> createState() => _AnimatedDepthBarState();
}

class _AnimatedDepthBarState extends State<AnimatedDepthBar>
    with SingleTickerProviderStateMixin {

  // The bar maps 0 cm (top) → 6 cm (bottom).
  static const double _maxDepth = 6.0;

  // Fade the line near the very top/bottom so it doesn't hard-clip.
  static const double _fadeRange = 0.3;

  // Pixel space reserved for the pills at each end.
  static const double _topPadding    = 36.0;
  static const double _bottomPadding = 30.0;

  late AnimationController _ctrl;
  late Animation<double>   _anim;

  // Tracks the *displayed* position so tweens start from the right place.
  double _displayedDepth = 0.0;

  // Whether we have ever received a non-zero depth reading this session.
  bool _hasData = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120), // fast — matches 10 Hz BLE
    );
    _anim = const AlwaysStoppedAnimation(0.0);
  }

  @override
  void didUpdateWidget(covariant AnimatedDepthBar old) {
    super.didUpdateWidget(old);

    // Determine target position:
    //   • recoilAchieved → snap to 0 (line goes back to top)
    //   • otherwise      → follow the current depth value
    final double target = widget.recoilAchieved
        ? 0.0
        : widget.depth.clamp(0.0, _maxDepth);

    if ((target - _displayedDepth).abs() < 0.01) return;

    _anim = Tween<double>(
      begin: _displayedDepth,
      end:   target,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward(from: 0);
    _displayedDepth = target;

    if (!_hasData && widget.depth > 0.05) {
      setState(() => _hasData = true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Line opacity — fades near the very top and very bottom extremes.
  double _opacity(double v) {
    if (v <= _fadeRange) return (v / _fadeRange).clamp(0.0, 1.0);
    if (v >= _maxDepth - _fadeRange) {
      return ((_maxDepth - v) / _fadeRange).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  // Line colour — green in target zone, orange too shallow, red too deep.
  Color _lineColor(double v) {
    if (!_hasData || v <= 0.05) return AppColors.textOnDark.withValues(alpha: 0.35);
    if (v < widget.targetDepthCm)       return AppColors.cprOrange;
    if (v <= widget.targetDepthCm + 1)  return AppColors.cprGreen;
    return AppColors.cprRed;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final usable = constraints.maxHeight - _topPadding - _bottomPadding;

        return Stack(
          alignment:   Alignment.center,
          clipBehavior: Clip.none,
          children: [

            // ── Background gauge SVG ─────────────────────────────────────
            SvgPicture.asset(
              'assets/icons/depth_background.svg',
              width:  constraints.maxWidth,
              height: constraints.maxHeight,
              fit:    BoxFit.contain,
            ),

            // ── RELEASE pill — top ───────────────────────────────────────
            Positioned(
              top: 0,
              child: AnimatedPill(
                label:     'RELEASE',
                isCorrect: _hasData && widget.recoilAchieved,
              ),
            ),

            // ── DEPTH pill — bottom ──────────────────────────────────────
            Positioned(
              bottom: 0,
              child: AnimatedPill(
                label:     'DEPTH',
                isCorrect: _hasData && widget.depth >= widget.targetDepthCm,
              ),
            ),

            // ── Moving indicator line ────────────────────────────────────
            //
            // depth = 0  → percent = 0 → fromBottom = usable → line at TOP
            // depth = 6  → percent = 1 → fromBottom = 0      → line at BOTTOM
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                final v          = _anim.value.clamp(0.0, _maxDepth);
                final percent    = v / _maxDepth;
                final fromBottom = (1.0 - percent) * usable;

                return Positioned(
                  bottom: _bottomPadding + fromBottom,
                  child: Opacity(
                    opacity: _hasData ? _opacity(v) : 0.0,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        _lineColor(v),
                        BlendMode.srcIn,
                      ),
                      child: SvgPicture.asset(
                        'assets/icons/depth_line.svg',
                        height: AppSpacing.cardSpacing,
                        width:  AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedPill
//
// Pill label that pulses green when the compression target is met.
// Inactive: brand-blue fill. Active: cprGreen + glow + scale pulse.
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
    with SingleTickerProviderStateMixin {
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
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillColor   = widget.isCorrect ? AppColors.cprGreen : AppColors.primary;
    final borderColor = widget.isCorrect ? AppColors.primary   : AppColors.cprGreen;

    return ScaleTransition(
      scale: _pulseCtrl,
      child: Container(
        width:  widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color:        fillColor,
          borderRadius: BorderRadius.circular(widget.height / 2),
          border:       Border.all(color: borderColor, width: 3),
          boxShadow: widget.isCorrect
              ? [
            BoxShadow(
              color:       AppColors.cprGreen.withValues(alpha: 0.6),
              blurRadius:  AppSpacing.sm,
              spreadRadius: AppSpacing.xxs,
            ),
          ]
              : const [],
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