import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class RotatingArrow extends StatefulWidget {
  final double frequency;

  const RotatingArrow({super.key, required this.frequency});

  @override
  State<RotatingArrow> createState() => _RotatingArrowState();
}

class _RotatingArrowState extends State<RotatingArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentAngle = 0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = AlwaysStoppedAnimation(_currentAngle);
  }

  @override
  void didUpdateWidget(covariant RotatingArrow oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newAngle = _calculateAngle(widget.frequency);

    if (newAngle != _currentAngle) {
      _animation = Tween<double>(
        begin: _currentAngle,
        end: newAngle,
      ).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ));

      _controller.forward(from: 0);
      _currentAngle = newAngle;
    }
  }

  double _calculateAngle(double frequency) {
    final normalized = ((frequency - 110) / 30).clamp(-1.0, 1.0);
    return normalized * (pi / 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, child) {
        return Transform.rotate(
          angle: _animation.value,
          alignment: Alignment.bottomCenter,
          child: child,
        );
      },
      child: SvgPicture.asset(
        'assets/icons/frequency_arrow.svg',
        width: 40,
        height: 80,
      ),
    );
  }
}
