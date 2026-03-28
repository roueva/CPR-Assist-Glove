import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PulseCheckOverlay
//
// Full-screen overlay shown during the 10-second pulse assessment window.
// Displays a scrolling PPG waveform, a countdown ring, and action buttons
// once a result arrives from the glove.
//
// Usage:
//   Positioned.fill(
//     child: PulseCheckOverlay(
//       intervalNumber: 1,
//       classification: _pulseClassification,
//       ppgBuffer:      List.from(_ppgBuffer),
//       detectedBpm:    _pulseCheckDetectedBpm,
//       confidence:     _pulseCheckConfidence,
//       onContinueCpr:  () => setState(() => _pulseCheckActive = false),
//       onStopCpr:      () => setState(() => _pulseCheckActive = false),
//     ),
//   )
//
// classification values:
//   null  — result not yet received (assessment in progress)
//   0     — ABSENT (no pulse)
//   1     — UNCERTAIN (weak signal)
//   2     — PRESENT (pulse detected)
// ─────────────────────────────────────────────────────────────────────────────

class PulseCheckOverlay extends StatefulWidget {
  final int?          intervalNumber;
  final int?          classification;
  final List<double>  ppgBuffer;
  final double?       detectedBpm;
  final int?          confidence;
  final VoidCallback  onContinueCpr;
  final VoidCallback  onStopCpr;

  const PulseCheckOverlay({
    super.key,
    this.intervalNumber,
    this.classification,
    this.ppgBuffer     = const [],
    this.detectedBpm,
    this.confidence,
    required this.onContinueCpr,
    required this.onStopCpr,
  });

  @override
  State<PulseCheckOverlay> createState() => _PulseCheckOverlayState();
}

class _PulseCheckOverlayState extends State<PulseCheckOverlay>
    with TickerProviderStateMixin {

  // Countdown — ticks while result is pending, stops when result arrives
  late final Timer _countdownTimer;
  int _secondsRemaining = 10;

  // Heartbeat pulse animation — plays when pulse is confirmed
  late final AnimationController _heartCtrl;
  late final Animation<double>   _heartScale;

  @override
  void initState() {
    super.initState();

    _heartCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    );
    _heartScale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _heartCtrl, curve: Curves.easeInOut),
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (widget.classification != null) return; // result arrived
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PulseCheckOverlay old) {
    super.didUpdateWidget(old);
    // Start heartbeat animation the moment pulse is confirmed
    if (old.classification == null && widget.classification == 2) {
      _heartCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    _heartCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPendingResult = widget.classification == null;

    final Color  resultColor;
    final String resultLabel;
    final String resultSubLabel;

    if (hasPendingResult) {
      resultColor    = AppColors.textOnDark;
      resultLabel    = 'Checking for pulse…';
      resultSubLabel = 'Hold still — keep fingers off the patient';
    } else if (widget.classification == 2) {
      resultColor    = AppColors.success;
      resultLabel    = 'Pulse Detected';
      resultSubLabel = widget.detectedBpm != null
          ? '${widget.detectedBpm!.toStringAsFixed(0)} BPM'
          : '';
    } else if (widget.classification == 1) {
      resultColor    = AppColors.warning;
      resultLabel    = 'Signal Uncertain';
      resultSubLabel = 'Check manually — continue CPR';
    } else {
      resultColor    = AppColors.emergencyRed;
      resultLabel    = 'No Pulse Detected';
      resultSubLabel = 'Continue CPR immediately';
    }

    return Container(
      color: AppColors.primaryDark.withValues(alpha: 0.96),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical:   AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              // ── Header row — badge + countdown/confidence ────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.chipPaddingH,
                      vertical:   AppSpacing.chipPaddingV,
                    ),
                    decoration: BoxDecoration(
                      color:        AppColors.textOnDark.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                      border: Border.all(
                        color: AppColors.textOnDark.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sensors_rounded,
                          size:  AppSpacing.iconSm - 2,
                          color: AppColors.textOnDark,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'PULSE CHECK'
                              '${widget.intervalNumber != null ? '  #${widget.intervalNumber}' : ''}',
                          style: AppTypography.badge(
                            size:  11,
                            color: AppColors.textOnDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (hasPendingResult)
                    PulseCountdownRing(secondsRemaining: _secondsRemaining)
                  else if (widget.confidence != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical:   AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color:        resultColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                        border: Border.all(
                          color: resultColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${widget.confidence}% confidence',
                        style: AppTypography.badge(size: 11, color: resultColor),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── PPG waveform ──────────────────────────────────────────────
              ScrollingPpgWaveform(
                buffer:    widget.ppgBuffer,
                lineColor: hasPendingResult ? AppColors.primary : resultColor,
                showPulse: widget.classification == 2,
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Status icon ───────────────────────────────────────────────
              if (!hasPendingResult && widget.classification == 2)
                ScaleTransition(
                  scale: _heartScale,
                  child: Icon(
                    Icons.favorite_rounded,
                    size:  AppSpacing.iconXl + AppSpacing.md,
                    color: resultColor,
                  ),
                )
              else if (!hasPendingResult)
                Icon(
                  widget.classification == 1
                      ? Icons.help_outline_rounded
                      : Icons.heart_broken_rounded,
                  size:  AppSpacing.iconXl + AppSpacing.md,
                  color: resultColor,
                )
              else
                const PulsingAssessmentDot(),

              const SizedBox(height: AppSpacing.lg),

              // ── Result label ──────────────────────────────────────────────
              Text(
                resultLabel,
                textAlign: TextAlign.center,
                style: AppTypography.poppins(
                  size:   24,
                  weight: FontWeight.w700,
                  color:  resultColor,
                ),
              ),
              if (resultSubLabel.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  resultSubLabel,
                  textAlign: TextAlign.center,
                  style: AppTypography.body(
                    size:  14,
                    color: AppColors.textOnDark.withValues(alpha: 0.65),
                  ),
                ),
              ],

              const Spacer(),

              // ── Action buttons — shown only after result arrives ───────────
              if (!hasPendingResult) ...[
                Row(
                  children: [
                    if (widget.classification == 2) ...[
                      // Pulse detected — offer both options
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.onContinueCpr,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textOnDark,
                            side: BorderSide(
                              color: AppColors.textOnDark.withValues(alpha: 0.4),
                            ),
                            minimumSize: const Size(0, AppSpacing.touchTargetLarge),
                          ),
                          child: Text(
                            'Continue CPR',
                            style: AppTypography.buttonSecondary(
                              color: AppColors.textOnDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.onStopCpr,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: AppColors.textOnDark,
                            minimumSize: const Size(0, AppSpacing.touchTargetLarge),
                          ),
                          child: Text(
                            'Stop CPR',
                            style: AppTypography.buttonPrimary(),
                          ),
                        ),
                      ),
                    ] else ...[
                      // No pulse / uncertain — single button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.onContinueCpr,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.emergencyRed,
                            foregroundColor: AppColors.textOnDark,
                            minimumSize: const Size(0, AppSpacing.touchTargetLarge),
                          ),
                          child: Text(
                            'Continue CPR',
                            style: AppTypography.buttonPrimary(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PulseCountdownRing — circular countdown for the 10-second window
// ─────────────────────────────────────────────────────────────────────────────

class PulseCountdownRing extends StatelessWidget {
  final int secondsRemaining;
  const PulseCountdownRing({super.key, required this.secondsRemaining});

  @override
  Widget build(BuildContext context) {
    final progress = secondsRemaining / 10.0;
    final color = secondsRemaining > 4
        ? AppColors.primary
        : secondsRemaining > 2
        ? AppColors.warning
        : AppColors.emergencyRed;

    return SizedBox(
      width:  44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value:           progress,
            strokeWidth:     3.5,
            strokeCap:       StrokeCap.round,
            backgroundColor: AppColors.textOnDark.withValues(alpha: 0.12),
            valueColor:      AlwaysStoppedAnimation<Color>(color),
          ),
          Text(
            '$secondsRemaining',
            style: AppTypography.poppins(
              size:   14,
              weight: FontWeight.w700,
              color:  color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PulsingAssessmentDot — animated indicator while assessment is running
// ─────────────────────────────────────────────────────────────────────────────

class PulsingAssessmentDot extends StatefulWidget {
  const PulsingAssessmentDot({super.key});

  @override
  State<PulsingAssessmentDot> createState() => _PulsingAssessmentDotState();
}

class _PulsingAssessmentDotState extends State<PulsingAssessmentDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width:  AppSpacing.iconXl + AppSpacing.md,
        height: AppSpacing.iconXl + AppSpacing.md,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.15),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.4),
            width: 2,
          ),
        ),
        child: const Icon(
          Icons.favorite_outline_rounded,
          size:  AppSpacing.iconLg,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ScrollingPpgWaveform — ECG-style PPG display
// ─────────────────────────────────────────────────────────────────────────────

class ScrollingPpgWaveform extends StatelessWidget {
  final List<double> buffer;
  final Color        lineColor;
  final bool         showPulse;

  const ScrollingPpgWaveform({
    super.key,
    required this.buffer,
    required this.lineColor,
    this.showPulse = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color:        AppColors.textOnDark.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
        border: Border.all(
          color: AppColors.textOnDark.withValues(alpha: 0.08),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
        child: CustomPaint(
          painter: _PpgWaveformPainter(
            buffer:    buffer,
            lineColor: lineColor,
            showPulse: showPulse,
          ),
        ),
      ),
    );
  }
}

class _PpgWaveformPainter extends CustomPainter {
  final List<double> buffer;
  final Color        lineColor;
  final bool         showPulse;

  const _PpgWaveformPainter({
    required this.buffer,
    required this.lineColor,
    required this.showPulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Grid ─────────────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color       = lineColor.withValues(alpha: 0.08)
      ..strokeWidth = 0.5
      ..style       = PaintingStyle.stroke;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final vCount = (size.width / 60).ceil();
    for (int i = 1; i < vCount; i++) {
      final x = size.width * i / vCount;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // ── Flat baseline when buffer is empty ────────────────────────────────────
    if (buffer.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height * 0.5),
        Offset(size.width, size.height * 0.5),
        Paint()
          ..color       = lineColor.withValues(alpha: 0.25)
          ..strokeWidth = 1.5
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round,
      );
      // Blinking cursor at right edge
      canvas.drawLine(
        Offset(size.width - 2, size.height * 0.3),
        Offset(size.width - 2, size.height * 0.7),
        Paint()
          ..color       = lineColor.withValues(alpha: 0.5)
          ..strokeWidth = 2.0
          ..style       = PaintingStyle.stroke,
      );
      return;
    }

    // ── Waveform — most recent sample always at right edge ────────────────────
    final n = buffer.length;
    const padFraction = 0.12;
    final drawH = size.height * (1 - 2 * padFraction);
    final padY  = size.height * padFraction;

    // Auto-scale to signal range
    double minV = buffer.reduce((a, b) => a < b ? a : b);
    double maxV = buffer.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();
    if (range < 0.05) {
      minV -= 0.1;
      maxV += 0.1;
    }
    final scale = range < 0.05 ? 1.0 : 1.0 / (maxV - minV);

    double xOf(int i) => (i / (n - 1 == 0 ? 1 : n - 1)) * size.width;
    double yOf(double v) {
      final norm = ((v - minV) * scale).clamp(0.0, 1.0);
      return padY + drawH * (1.0 - norm);
    }

    // Build path with cubic bezier for smooth ECG curve
    final path = Path()..moveTo(xOf(0), yOf(buffer[0]));
    for (int i = 1; i < n; i++) {
      final x0  = xOf(i - 1);
      final x1  = xOf(i);
      final y0  = yOf(buffer[i - 1]);
      final y1  = yOf(buffer[i]);
      final cpx = (x0 + x1) / 2;
      path.cubicTo(cpx, y0, cpx, y1, x1, y1);
    }

    // Fill + glow when pulse confirmed
    if (showPulse) {
      final fillPath = Path.from(path)
        ..lineTo(xOf(n - 1), size.height)
        ..lineTo(xOf(0), size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()
          ..color = lineColor.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color       = lineColor.withValues(alpha: 0.18)
          ..strokeWidth = 8.0
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // Main line
    canvas.drawPath(
      path,
      Paint()
        ..color       = lineColor
        ..strokeWidth = 2.0
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round,
    );

    // Cursor dot at leading edge
    final lastX = xOf(n - 1);
    final lastY = yOf(buffer.last);
    canvas.drawCircle(
      Offset(lastX, lastY),
      3.5,
      Paint()..color = lineColor..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(lastX, lastY),
      3.5,
      Paint()
        ..color       = lineColor.withValues(alpha: 0.3)
        ..strokeWidth = 4.0
        ..style       = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _PpgWaveformPainter old) =>
      old.buffer != buffer ||
          old.lineColor != lineColor ||
          old.showPulse != showPulse;
}