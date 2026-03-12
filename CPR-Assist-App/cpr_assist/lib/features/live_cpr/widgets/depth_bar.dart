import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnimatedDepthBar
//
// Displays a vertical SVG gauge that tracks compression depth in real time.
// The moving indicator line fades near the top and bottom extremes.
// RELEASE pill lights up when depth < 0.2 cm (full recoil).
// DEPTH   pill lights up when depth > 5.0 cm (correct compression target).
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedDepthBar extends StatefulWidget {
  /// Live depth value from the BLE glove — range 0–6 cm.
  final double depth;

  const AnimatedDepthBar({super.key, required this.depth});

  @override
  State<AnimatedDepthBar> createState() => _AnimatedDepthBarState();
}

class _AnimatedDepthBarState extends State<AnimatedDepthBar>
    with SingleTickerProviderStateMixin {
  static const double _maxDepth = 6.0;

  // Fade-out band at each extreme so the line doesn't hard-clip
  static const double _fadeRange = 0.4;

  // Pixel headroom reserved for the RELEASE / DEPTH pills
  static const double _topPadding    = 34.0;
  static const double _bottomPadding = 28.0;

  late AnimationController _controller;
  late Animation<double>   _animation;
  double _currentValue = _maxDepth / 2;
  bool   _hasReceivedData = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = AlwaysStoppedAnimation(_currentValue);
  }

  @override
  void didUpdateWidget(covariant AnimatedDepthBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final target = widget.depth.clamp(0.0, _maxDepth);
    if (target == _currentValue) return;

    _animation = Tween<double>(begin: _currentValue, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward(from: 0);
    _currentValue = target;

    if (!_hasReceivedData && target > 0.01) {
      setState(() => _hasReceivedData = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Opacity for the moving line ────────────────────────────────────────────

  double _lineOpacity(double value) {
    if (value <= _fadeRange) {
      return (value / _fadeRange).clamp(0.0, 1.0);
    }
    if (value >= _maxDepth - _fadeRange) {
      return ((_maxDepth - value) / _fadeRange).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final usableHeight =
            constraints.maxHeight - _topPadding - _bottomPadding;

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Background SVG gauge
            SvgPicture.asset(
              'assets/icons/depth_background.svg',
              width:  constraints.maxWidth,
              height: constraints.maxHeight,
              fit:    BoxFit.contain,
            ),

            // RELEASE pill — top
            Positioned(
              top: 0,
              child: AnimatedPill(
                label:     'RELEASE',
                isCorrect: _hasReceivedData && widget.depth < 0.2,
              ),
            ),

            // DEPTH pill — bottom
            Positioned(
              bottom: 0,
              child: AnimatedPill(
                label:     'DEPTH',
                isCorrect: _hasReceivedData && widget.depth > 5.0,
              ),
            ),

            // Moving indicator line
            AnimatedBuilder(
              animation: _animation,
              builder: (_, __) {
                final percent = (_animation.value / _maxDepth).clamp(0.0, 1.0);
                final fromBottom = (1.0 - percent) * usableHeight;

                return Positioned(
                  bottom: _bottomPadding + fromBottom,
                  child: Opacity(
                    opacity: _lineOpacity(_animation.value),
                    child: SvgPicture.asset(
                      'assets/icons/depth_line.svg',
                      height: AppSpacing.cardSpacing,  // 6
                      width:  AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs, // 14
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
// Inactive state: brand-blue fill.
// Active  state: cprGreen fill + green glow shadow + scale pulse.
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
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      lowerBound: 0.98,
      upperBound: 1.05,
    );
    if (widget.isCorrect) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCorrect == oldWidget.isCorrect) return;

    if (widget.isCorrect) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillColor   = widget.isCorrect ? AppColors.cprGreen  : AppColors.primary;
    final borderColor = widget.isCorrect ? AppColors.primary    : AppColors.cprGreen;

    return ScaleTransition(
      scale: _pulseController,
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
              // AppColors.cprGreen at 60% opacity
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
            size:   AppSpacing.md - AppSpacing.xxs, // 14
            weight: FontWeight.w600,
            color:  AppColors.textOnDark,
          ),
        ),
      ),
    );
  }
}