import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AnimatedDepthBar extends StatefulWidget {
  final double depth; // Value from 0–maxDepth (e.g., 0–6)

  const AnimatedDepthBar({super.key, required this.depth});

  @override
  State<AnimatedDepthBar> createState() => _AnimatedDepthBarState();
}

class _AnimatedDepthBarState extends State<AnimatedDepthBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentValue = _maxDepth / 2;
  static const double _maxDepth = 6.0; // Replace with real max

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _currentValue = _maxDepth / 2;
    _animation = AlwaysStoppedAnimation(_currentValue);
  }

  @override
  void didUpdateWidget(covariant AnimatedDepthBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    final target = widget.depth.clamp(0.0, _maxDepth);

    if (target != _currentValue) {
      _animation = Tween<double>(
        begin: _currentValue,
        end: target,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ));
      _controller.forward(from: 0);
      _currentValue = target;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double bottomPadding = 28;
        const double topPadding = 34;
        final usableHeight = constraints.maxHeight - topPadding - bottomPadding;

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Main depth background icon
            SvgPicture.asset(
              'assets/icons/depth_background.svg',
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.contain,
            ),

            // ✅ Release circle (top)
            Positioned(
              top: 0,
              child: AnimatedPill(
                label: 'RELEASE',
                isCorrect: widget.depth < 0.2,
              ),
            ),

            // ✅ Depth circle (bottom)
            Positioned(
              bottom: 0,
              child: AnimatedPill(
                label: 'DEPTH',
                isCorrect: widget.depth > 5.0,
              ),
            ),

            // ✅ Moving line
            AnimatedBuilder(
              animation: _animation,
              builder: (_, __) {
                final percent = (_animation.value / _maxDepth).clamp(0.0, 1.0);
                final positionFromBottom = (1.0 - percent) * usableHeight;

                final fadeOutRange = 0.4; // cm range near top/bottom where it fades
                final fadeOutDepthTop = 0.0 + fadeOutRange;
                final fadeOutDepthBottom = _maxDepth - fadeOutRange;

                double opacity = 1.0;

                if (_animation.value <= fadeOutDepthTop) {
                  // Near full release
                  opacity = (_animation.value / fadeOutDepthTop).clamp(0.0, 1.0);
                } else if (_animation.value >= fadeOutDepthBottom) {
                  // Near full compression
                  opacity = ((_maxDepth - _animation.value) / fadeOutRange).clamp(0.0, 1.0);
                }

                return Positioned(
                  bottom: bottomPadding + positionFromBottom,
                  child: Opacity(
                    opacity: opacity,
                    child: SvgPicture.asset(
                      'assets/icons/depth_line.svg',
                      height: 6,
                      width: 14,
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
class AnimatedPill extends StatefulWidget {
  final String label;
  final bool isCorrect;
  final double width;
  final double height;

  const AnimatedPill({
    super.key,
    required this.label,
    required this.isCorrect,
    this.width = 117,
    this.height = 37,
  });

  @override
  State<AnimatedPill> createState() => _AnimatedPillState();
}

class _AnimatedPillState extends State<AnimatedPill> with SingleTickerProviderStateMixin {
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
    if (widget.isCorrect) _pulseController.forward(from: 0);
    if (!widget.isCorrect) {
      _pulseController.value = 1.0; // prevent visual bug on startup
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCorrect != oldWidget.isCorrect) {
      if (widget.isCorrect) {
        _pulseController.forward(from: 0);
      } else {
        _pulseController.stop();
        _pulseController.value = 1.0;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseController,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.isCorrect ? const Color(0xFF319E77) : const Color(0xFF335484),
          borderRadius: BorderRadius.circular(widget.height / 2),
          border: Border.all(
            color: widget.isCorrect ? const Color(0xFF335484) : const Color(0xFF319E77),
            width: 3,
          ),
          boxShadow: widget.isCorrect
              ? [
            BoxShadow(
              color: const Color(0xFF319E77).withValues(alpha: 0.6),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ]
              : [],
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

