import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PulseCheckOverlay
//
// Full-screen modal overlay shown when PULSE_CHECK_START (0x04) fires.
// Renders a semi-transparent dark scrim with a centred white card —
// same pattern as VentilationOverlay.
//
// The card contains:
//   • Header row  — "Pulse Check #N" pill  +  countdown ring (10 s)
//   • ECG graph   — scrolling PPG waveform, full width, visible on white
//   • Status area — pulsing dot while pending; icon + label after result
//   • Vitals row  — BPM / SpO₂ / Temp chips, shown when pulse detected
//   • Decision note — user autonomy text before buttons
//   • Buttons     — "Continue CPR" / "Stop CPR" (or just "Continue CPR")
//   • Footer      — end-condition hint
//
// classification values (matches PULSE_CHECK_RESULT byte 1):
//   null — still assessing (10-second window in progress)
//   0    — ABSENT (no pulse)
//   1    — UNCERTAIN (weak / manual verify)
//   2    — PRESENT  (pulse detected)
//
// Usage (in live_cpr_screen.dart):
//   if (_pulseCheckActive)
//     Positioned.fill(
//       child: PulseCheckOverlay(
//         intervalNumber: _pulseIntervalNumber,
//         classification: _pulseClassification,
//         ppgBuffer:      List.from(_ppgBuffer),
//         detectedBpm:    _pulseCheckBpm,
//         confidence:     _pulseCheckConfidence,
//         spO2:           _pulseCheckSpO2,
//         patientTemp:    _patientTemperature,
//         onContinueCpr:  () => setState(() => _pulseCheckActive = false),
//         onStopCpr:      () => _endSession(),
//       ),
//     )
// ─────────────────────────────────────────────────────────────────────────────

class PulseCheckOverlay extends StatefulWidget {
  /// Which 2-minute interval triggered this check (from PULSE_CHECK_START byte 1–2).
  final int? intervalNumber;

  /// Result from PULSE_CHECK_RESULT byte 1. null = still assessing.
  final int? classification;

  /// Live PPG buffer — normalised 0.0–1.0 amplitudes from LIVE_STREAM ppgRaw.
  final List<double> ppgBuffer;

  /// BPM from PULSE_CHECK_RESULT bytes 2–5. null if classification != 2.
  final double? detectedBpm;

  /// Confidence 0–100 from PULSE_CHECK_RESULT byte 6.
  final int? confidence;

  /// Patient SpO₂ from LIVE_STREAM bytes 60–63 (gated to pulse window). null if no signal.
  final double? spO2;

  /// Patient temperature °C from LIVE_STREAM bytes 70–71 (decoded / 100). null if no reading.
  final double? patientTemp;

  final VoidCallback onContinueCpr;
  final VoidCallback onStopCpr;

  const PulseCheckOverlay({
    super.key,
    this.intervalNumber,
    this.classification,
    this.ppgBuffer    = const [],
    this.detectedBpm,
    this.confidence,
    this.spO2,
    this.patientTemp,
    required this.onContinueCpr,
    required this.onStopCpr,
  });

  @override
  State<PulseCheckOverlay> createState() => _PulseCheckOverlayState();
}

class _PulseCheckOverlayState extends State<PulseCheckOverlay>
    with TickerProviderStateMixin {

  // ── Countdown ─────────────────────────────────────────────────────────────
  late final Timer _countdownTimer;
  int _secondsRemainingMs = 10000; // milliseconds, ticks at 100ms

  // ── Heartbeat animation — plays once pulse is confirmed ───────────────────
  late final AnimationController _heartCtrl;
  late final Animation<double>   _heartScale;

  @override
  void initState() {
    super.initState();

    _heartCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 650),
    );
    _heartScale = Tween<double>(begin: 1.0, end: 1.30).animate(
      CurvedAnimation(parent: _heartCtrl, curve: Curves.easeInOut),
    );

    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      if (widget.classification != null) return;
      if (_secondsRemainingMs > 0) {
        setState(() => _secondsRemainingMs -= 100);
      }
    });
  }

  @override
  void didUpdateWidget(covariant PulseCheckOverlay old) {
    super.didUpdateWidget(old);
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

  // ── Derived state ──────────────────────────────────────────────────────────

  bool get _isPending => widget.classification == null;

  Color get _resultColor {
    if (_isPending)                     return AppColors.primary;
    if (widget.classification == 2)     return AppColors.success;
    if (widget.classification == 1)     return AppColors.warning;
    return AppColors.emergencyRed;
  }

  String get _resultLabel {
    if (_isPending)                     return 'Checking for pulse…';
    if (widget.classification == 2)     return 'Pulse Detected';
    if (widget.classification == 1)     return 'Signal Uncertain';
    return 'No Pulse Detected';
  }

  String get _resultSub {
    if (_isPending)                     return 'Keep both sensors on patient';
    if (widget.classification == 2)     return 'Decide whether to stop or continue CPR';
    if (widget.classification == 1)     return 'Verify manually and continue CPR unless certain';
    return 'Resume compressions immediately';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.overlayDark,
      child: SafeArea(
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.85,
              ),
              decoration: AppDecorations.card(
                color:  AppColors.surfaceWhite,
                radius: AppSpacing.cardRadiusLg,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    _buildWaveform(),
                    _buildStatus(),
                    if (!_isPending) _buildVitals(),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Header — pill + countdown ring ────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs,
      ),
      child: Row(
        children: [
          // "Pulse Check #N" pill
          _Pill(
            label:     widget.intervalNumber != null
                ? 'Pulse Check  #${widget.intervalNumber}'
                : 'Pulse Check',
            textColor: AppColors.primary,
            bg:        AppColors.primaryLight,
          ),
          const Spacer(),
          // Right side: countdown while pending, confidence badge after result
          if (_isPending)
            _CountdownRing(secondsRemainingMs: _secondsRemainingMs)
          else if (widget.confidence != null)
            _Pill(
              label:     '${widget.confidence}% confidence',
              textColor: _resultColor,
              bg:        _resultColor.withValues(alpha: 0.10),
            ),
        ],
      ),
    );
  }

  // ── ECG / PPG waveform ─────────────────────────────────────────────────────

  Widget _buildWaveform() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: label left, signal-quality hint right
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs, bottom: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Text(
                  'PPG Signal',
                  style: AppTypography.label(
                    size:  11,
                    color: AppColors.textDisabled,
                  ),
                ),
                const Spacer(),
                if (!_isPending && widget.classification == 2)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.circle,
                        size:  6,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        'Live',
                        style: AppTypography.label(
                          size:  11,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          // The graph itself
          _PpgGraph(
            buffer:    widget.ppgBuffer,
            lineColor: _isPending ? AppColors.primary : _resultColor,
            showFill:  widget.classification == 2,
          ),
        ],
      ),
    );
  }

  // ── Status area — icon + label + sub ──────────────────────────────────────

  Widget _buildStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical:   AppSpacing.md,
      ),
      child: Column(
        children: [
          // Icon / animation
          if (_isPending)
            const _PulsingDot()
          else if (widget.classification == 2)
            ScaleTransition(
              scale: _heartScale,
              child: const Icon(
                Icons.favorite_rounded,
                size:  AppSpacing.iconXl,
                color: AppColors.success,
              ),
            )
          else
            Icon(
              widget.classification == 1
                  ? Icons.help_outline_rounded
                  : Icons.heart_broken_rounded,
              size:  AppSpacing.iconXl,
              color: _resultColor,
            ),

          const SizedBox(height: AppSpacing.sm),

          Text(
            _resultLabel,
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              size:  20,
              color: _resultColor,
            ),
          ),

          const SizedBox(height: AppSpacing.xxs + 1),

          Text(
            _resultSub,
            textAlign: TextAlign.center,
            style: AppTypography.body(
              size:  13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Vitals row — BPM / SpO₂ / Temp (only when result present) ────────────

  Widget _buildVitals() {
    // Nothing to show if no values are available at all
    final hasBpm  = widget.detectedBpm != null && widget.classification == 2;
    final hasSpo2 = widget.spO2 != null && widget.classification == 2;
    final hasTemp = widget.patientTemp != null;

    if (!hasBpm && !hasSpo2 && !hasTemp) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color:        AppColors.screenBgGrey,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (hasBpm)
                _VitalChip(
                  icon:  Icons.favorite_rounded,
                  color: AppColors.primary,
                value: widget.detectedBpm!.toStringAsFixed(0),
                unit:  'BPM',
              ),
            if (hasBpm && hasSpo2)
              _VertDivider(),
            if (hasSpo2)
              _VitalChip(
                icon:  Icons.air_rounded,
                color: AppColors.primary,
                value: widget.spO2!.toStringAsFixed(0),
                unit:  'SpO₂%',
              ),
            if ((hasBpm || hasSpo2) && hasTemp)
              _VertDivider(),
            if (hasTemp)
              _VitalChip(
                icon:  Icons.thermostat_rounded,
                color: AppColors.primary,
                value: widget.patientTemp!.toStringAsFixed(1),
                unit:  '°C',
              ),
          ],
        ),
      ),
    );
  }



  // ── Footer — end-condition hint ────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.screenBgGrey,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppSpacing.cardRadiusLg),
        ),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Text('Ends automatically after 10s or when compressions resume',
        style:     AppTypography.caption(color: AppColors.textDisabled),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CountdownRing — circular 10-second countdown shown in the header
// ─────────────────────────────────────────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final int secondsRemainingMs;
  const _CountdownRing({required this.secondsRemainingMs});

  @override
  Widget build(BuildContext context) {
    final progress = (secondsRemainingMs / 10000.0).clamp(0.0, 1.0);
    final secs     = secondsRemainingMs / 1000.0;

    final Color trackColor;
    final Color arcColor;

    if (secs > 5) {
      arcColor   = AppColors.primary;
      trackColor = AppColors.divider;
    } else if (secs > 2) {
      arcColor   = AppColors.warning;
      trackColor = AppColors.warningBg;
    } else {
      arcColor   = AppColors.emergencyRed;
      trackColor = AppColors.errorBg;
    }

    return SizedBox(
      width:  48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value:           progress,
            strokeWidth:     3.5,
            strokeCap:       StrokeCap.round,
            backgroundColor: trackColor,
            valueColor:      AlwaysStoppedAnimation<Color>(arcColor),
          ),
          Text(
            secs.toStringAsFixed(1),
            style: AppTypography.poppins(
              size:   11,
              weight: FontWeight.w800,
              color:  arcColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PulsingDot — animated placeholder icon during assessment
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.75, end: 1.0).animate(
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
        width:  AppSpacing.iconXl,
        height: AppSpacing.iconXl,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: 0.10),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.35),
            width: 2.0,
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
// _PpgGraph — ECG-style scrolling PPG waveform on white background
// ─────────────────────────────────────────────────────────────────────────────

class _PpgGraph extends StatelessWidget {
  final List<double> buffer;
  final Color        lineColor;
  final bool         showFill;

  const _PpgGraph({
    required this.buffer,
    required this.lineColor,
    this.showFill = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  double.infinity,
      height: 110,
      decoration: BoxDecoration(
        color:        AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border:       Border.all(color: AppColors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: CustomPaint(
          painter: _PpgPainter(
            buffer:    buffer,
            lineColor: lineColor,
            showFill:  showFill,
          ),
        ),
      ),
    );
  }
}

class _PpgPainter extends CustomPainter {
  final List<double> buffer;
  final Color        lineColor;
  final bool         showFill;

  const _PpgPainter({
    required this.buffer,
    required this.lineColor,
    required this.showFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Grid lines ───────────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color       = AppColors.divider
      ..strokeWidth = 0.7
      ..style       = PaintingStyle.stroke;

    // 3 horizontal lines
    for (int i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // Vertical lines every ~60px
    final vCount = (size.width / 60).ceil();
    for (int i = 1; i < vCount; i++) {
      final x = size.width * i / vCount;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // ── Baseline when empty ──────────────────────────────────────────────────
    if (buffer.isEmpty) {
      // Flat baseline
      canvas.drawLine(
        Offset(0, size.height * 0.55),
        Offset(size.width, size.height * 0.55),
        Paint()
          ..color       = lineColor.withValues(alpha: 0.30)
          ..strokeWidth = 1.5
          ..strokeCap   = StrokeCap.round
          ..style       = PaintingStyle.stroke,
      );
      // Blinking leading cursor
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - 3, size.height * 0.35, 2, size.height * 0.4),
          const Radius.circular(1),
        ),
        Paint()
          ..color = lineColor.withValues(alpha: 0.55)
          ..style = PaintingStyle.fill,
      );
      return;
    }

    // ── Auto-scale ────────────────────────────────────────────────────────────
    const padFrac = 0.12;
    final drawH = size.height * (1 - 2 * padFrac);
    final padY  = size.height * padFrac;

    double minV = buffer.reduce((a, b) => a < b ? a : b);
    double maxV = buffer.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();
    if (range < 0.05) { minV -= 0.1; maxV += 0.1; }
    final scale = range < 0.05 ? 1.0 : 1.0 / (maxV - minV);

    final n = buffer.length;
    double xOf(int i) =>
        (i / (n <= 1 ? 1 : n - 1)) * size.width;
    double yOf(double v) {
      final norm = ((v - minV) * scale).clamp(0.0, 1.0);
      return padY + drawH * (1.0 - norm);
    }

    // ── Build path ────────────────────────────────────────────────────────────
    final path = Path()..moveTo(xOf(0), yOf(buffer[0]));
    for (int i = 1; i < n; i++) {
      final x0  = xOf(i - 1);  final x1  = xOf(i);
      final y0  = yOf(buffer[i - 1]); final y1  = yOf(buffer[i]);
      final cpx = (x0 + x1) / 2;
      path.cubicTo(cpx, y0, cpx, y1, x1, y1);
    }

    // ── Area fill + glow when pulse confirmed ─────────────────────────────────
    if (showFill) {
      final fill = Path.from(path)
        ..lineTo(xOf(n - 1), size.height)
        ..lineTo(xOf(0), size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..color = lineColor.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      // Soft glow stroke
      canvas.drawPath(
        path,
        Paint()
          ..color       = lineColor.withValues(alpha: 0.22)
          ..strokeWidth = 7.0
          ..style       = PaintingStyle.stroke
          ..strokeCap   = StrokeCap.round
          ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // ── Main line ─────────────────────────────────────────────────────────────
    canvas.drawPath(
      path,
      Paint()
        ..color       = lineColor
        ..strokeWidth = 2.0
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round,
    );

    // ── Leading cursor dot ───────────────────────────────────────────────────
    final lx = xOf(n - 1);
    final ly = yOf(buffer.last);
    canvas.drawCircle(
      Offset(lx, ly), 3.5,
      Paint()..color = lineColor..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(lx, ly), 3.5,
      Paint()
        ..color       = lineColor.withValues(alpha: 0.28)
        ..strokeWidth = 4.0
        ..style       = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _PpgPainter old) =>
      old.buffer != buffer ||
          old.lineColor != lineColor ||
          old.showFill != showFill;
}

// ─────────────────────────────────────────────────────────────────────────────
// _VitalChip — icon + value + unit, used in the vitals row
// ─────────────────────────────────────────────────────────────────────────────

class _VitalChip extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   value;
  final String   unit;

  const _VitalChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSpacing.iconSm, color: color),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          value,
          style: AppTypography.numericDisplay(
            size:  20,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          unit,
          style: AppTypography.label(
            size:  10,
            color: AppColors.textDisabled,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VertDivider — thin vertical separator between vitals chips
// ─────────────────────────────────────────────────────────────────────────────

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width:  AppSpacing.dividerThickness,
      height: AppSpacing.lg,
      color:  AppColors.divider,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Pill — small rounded chip, same as VentilationOverlay._Pill
// ─────────────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String    label;
  final Color     textColor;
  final Color     bg;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.textColor,
    required this.bg,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.chipPaddingH,
        vertical:   AppSpacing.chipPaddingV,
      ),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSpacing.iconXs, color: textColor),
            const SizedBox(width: AppSpacing.xxs + 1),
          ],
          Text(
            label,
            style: AppTypography.label(size: 11, color: textColor),
          ),
        ],
      ),
    );
  }
}