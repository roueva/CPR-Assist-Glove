import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PulseCheckOverlay
//
// Non-blocking card shown in the Live CPR screen's scrollable content column
// when a circulation check is open or has just closed. Not a modal — nothing
// behind it is blocked, and there is no decision to make: the glove can't
// yet distinguish the patient's pulse from the rescuer's own, so the
// measurement is never presented as something to act on.
//
// The card contains:
//   • Header row  — "Pulse Check #N" pill  +  elapsed-time pill (while open)
//   • ECG graph   — scrolling PPG waveform, full width, visible on white
//   • Status area — pulsing dot + "in progress" while open; neutral icon +
//                   "Circulation check recorded" once closed
//   • Footer      — end-condition hint
//
// classification (matches PULSE_CHECK_RESULT byte 1) is used only to tell
// open (null) from closed (non-null) here — the value itself, plus BPM and
// confidence, are stored in the session record and shown on the results
// screen, never on this live card.
// ─────────────────────────────────────────────────────────────────────────────

class PulseCheckOverlay extends StatefulWidget {
  /// Which 2-minute interval triggered this check (from PULSE_CHECK_START byte 1–2).
  final int? intervalNumber;

  /// Result from PULSE_CHECK_RESULT byte 1. null = still open; non-null = closed.
  /// The value itself is not displayed here — see file header.
  final int? classification;

  /// Live PPG buffer — normalised 0.0–1.0 amplitudes from LIVE_STREAM ppgRaw.
  final List<double> ppgBuffer;

  const PulseCheckOverlay({
    super.key,
    this.intervalNumber,
    this.classification,
    this.ppgBuffer = const [],
  });

  @override
  State<PulseCheckOverlay> createState() => _PulseCheckOverlayState();
}

class _PulseCheckOverlayState extends State<PulseCheckOverlay> {

  // ── Pause duration counter (mirrors VentilationOverlay) ──────────────────
  Timer? _elapsedTimer;
  double _elapsed = 0.0;

  @override
  void initState() {
    super.initState();

    // Tenth-of-a-second tick — drives the elapsed-time pill turning red at 8 s.
    _elapsedTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed += 0.1);
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  // ── Derived state ──────────────────────────────────────────────────────────

  bool get _isPending => widget.classification == null;

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(
        color:  AppColors.white,
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
            _buildFooter(),
          ],
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
          // Elapsed-time pill while open (the window is open-ended and
          // firmware-driven now — no countdown). Nothing shown once closed;
          // the result itself lives on the session record, not here.
          if (_isPending)
            _Pill(
              label:     '${_elapsed.toStringAsFixed(1)}s',
              textColor: _elapsed >= 8.0
                  ? AppColors.emergency
                  : AppColors.primary,
              bg:        _elapsed >= 8.0
                  ? AppColors.errorBg
                  : AppColors.primaryLight,
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
              ],
            ),
          ),
          // The graph itself
          _PpgGraph(
            buffer:    widget.ppgBuffer,
            lineColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  // ── Status area — in-progress while open, neutral once closed ────────────
  //
  // No classification, no BPM, no confidence, no verdict colour — those
  // stay in the session record and the results screen. This card only ever
  // says whether a check is in progress or has been recorded.

  Widget _buildStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical:   AppSpacing.md,
      ),
      child: Column(
        children: [
          if (_isPending)
            const _PulsingDot()
          else
            const Icon(
              Icons.check_circle_outline_rounded,
              size:  AppSpacing.iconXl,
              color: AppColors.textSecondary,
            ),

          const SizedBox(height: AppSpacing.sm),

          Text(
            _isPending ? 'Circulation check in progress' : 'Circulation check recorded',
            textAlign: TextAlign.center,
            style: AppTypography.heading(
              size:  20,
              color: AppColors.textPrimary,
            ),
          ),
        ],
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
      child: Text('Stays open until you resume compressions',
        style:     AppTypography.caption(color: AppColors.textDisabled),
        textAlign: TextAlign.center,
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

  const _PpgGraph({
    required this.buffer,
    required this.lineColor,
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
          ),
        ),
      ),
    );
  }
}

class _PpgPainter extends CustomPainter {
  final List<double> buffer;
  final Color        lineColor;

  const _PpgPainter({
    required this.buffer,
    required this.lineColor,
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

    // If the PPG is essentially flat (no real signal) we draw a "No signal"
    // baseline + label instead of stretching noise to fill the canvas —
    // a fake square waveform was misleading and looked like a present pulse.
    if (range < 0.002) {
      // Faint flat baseline
      canvas.drawLine(
        Offset(0, size.height * 0.55),
        Offset(size.width, size.height * 0.55),
        Paint()
          ..color       = lineColor.withValues(alpha: 0.30)
          ..strokeWidth = 1.5
          ..strokeCap   = StrokeCap.round
          ..style       = PaintingStyle.stroke,
      );
      // "No signal" label, centred
      final tp = TextPainter(
        text: TextSpan(
          text: 'No signal',
          style: AppTypography.label(
            size:  11,
            color: AppColors.textDisabled,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(
        canvas,
        Offset(
          (size.width  - tp.width)  / 2,
          (size.height - tp.height) / 2 + 6,
        ),
      );
      return;
    }

    final scale = 1.0 / (maxV - minV);

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
          old.lineColor != lineColor;
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