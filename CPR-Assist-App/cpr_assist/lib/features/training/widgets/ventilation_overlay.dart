import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// VentilationOverlay
//
// Full-screen modal overlay shown when VENTILATION_WINDOW (0x03) fires.
// Renders a semi-transparent dark scrim with a centred white card.
//
// The card contains:
//   • Top pills row    — "Cycle N" + "Pause detected" (after 1 s)
//   • Animated circle  — brand-blue filled circle with white air icon;
//                        a ripple ring dissipates outward once per second
//                        (mimics a 1-second exhale)
//   • Instructions     — "BREATHE" heading + subtitle
//   • Pause timer      — runs in tenths; turns red after 8 s
//   • Footer           — "Closes automatically…" hint
//
// Dismiss: tap the scrim outside the card OR tap the × button.
// Auto-dismiss: called from live_cpr_screen when compressions resume.
//
// Usage (in live_cpr_screen.dart):
//   if (_showVentilationOverlay)
//     Positioned.fill(
//       child: VentilationOverlay(
//         cycleNumber:          _ventilationCycleNumber,
//         ventilationsExpected: _ventilationsExpected,
//         onDismiss: () => setState(() => _showVentilationOverlay = false),
//       ),
//     )
// ─────────────────────────────────────────────────────────────────────────────

class VentilationOverlay extends StatefulWidget {
  final int          cycleNumber;
  final int          ventilationsExpected;
  final VoidCallback onDismiss;

  const VentilationOverlay({
    super.key,
    required this.cycleNumber,
    required this.ventilationsExpected,
    required this.onDismiss,
  });

  @override
  State<VentilationOverlay> createState() => _VentilationOverlayState();
}

class _VentilationOverlayState extends State<VentilationOverlay>
    with TickerProviderStateMixin {

  // ── Pause duration counter ─────────────────────────────────────────────────
  late final Timer _durationTimer;
  double _pauseSeconds = 0.0;
  bool   _pauseDetected = false;   // shown after first second

  // ── Ripple animation — one cycle = 1 second (breath duration) ─────────────
  AnimationController? _rippleCtrl;
  Animation<double>?   _rippleScale;
  Animation<double>?   _rippleFade;

  AnimationController? _breatheCtrl;
  Animation<double>?   _breatheScale;

  @override
  void initState() {
    super.initState();

    // Tick every 100 ms — tenth-of-a-second precision
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _pauseSeconds += 0.1;
        if (_pauseSeconds >= 1.0) _pauseDetected = true;
      });
    });

    // Ripple: scale 1.0 → 1.9 over 1 second, repeating
    _rippleCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _rippleScale = Tween<double>(begin: 1.0, end: 1.9).animate(
      CurvedAnimation(parent: _rippleCtrl!, curve: Curves.easeOut),
    );
    _rippleFade = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _rippleCtrl!, curve: Curves.easeOut),
    );

    // Gentle breathe on the icon circle: 1.0 → 1.05 over 1.8 s
    _breatheCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _breatheScale = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _breatheCtrl!, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _durationTimer.cancel();
    _rippleCtrl?.dispose();
    _breatheCtrl?.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _timerDisplay {
    final secs = _pauseSeconds;
    return '${secs.toStringAsFixed(1)}s';
  }

  bool get _timerIsRed => _pauseSeconds >= 8.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Tap on the scrim → dismiss
      onTap: widget.onDismiss,
      child: Material(
        color: AppColors.overlayDark,
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              // Absorb taps inside the card so they don't bubble to the scrim
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                decoration: AppDecorations.card(
                  color:  AppColors.surfaceWhite,
                  radius: AppSpacing.cardRadiusLg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    _buildBody(),
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

  // ── Header — pills row + close button ─────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs,
      ),
        child: Row(
          children: [
            _Pill(
              label:     'Cycle ${widget.cycleNumber}',
              textColor: AppColors.primary,
              bg:        AppColors.primaryLight,
            ),
            const Spacer(),
            AnimatedOpacity(
              opacity:  _pauseDetected ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: const _Pill(
                label:     'Pause detected',
                textColor: AppColors.success,
                bg:        AppColors.successBg,
                icon:      Icons.check_circle_rounded,
              ),
            ),
          ],
        ),
    );
  }

  // ── Body — animated circle + text + timer ──────────────────────────────────

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical:   AppSpacing.md,
      ),
      child: Column(
        children: [

          // ── Animated breathing circle ───────────────────────────────────
          SizedBox(
            width:  120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ripple ring — dissipates outward once per second
                if (_rippleCtrl != null)
        AnimatedBuilder(
        animation: _rippleCtrl!,
        builder: (_, __) {
          return Transform.scale(
            scale: _rippleScale!.value,
            child: Container(
              width:  84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary
                    .withValues(alpha: _rippleFade!.value),
              ),
            ),
          );
        },
      ),

                // Icon circle — gently breathes
                ScaleTransition(
                  scale: _breatheScale ?? const AlwaysStoppedAnimation(1.0),
                  child: Container(
                    width:  84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                      boxShadow: [
                        BoxShadow(
                          color:        AppColors.primary.withValues(alpha: 0.3),
                          blurRadius:   16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.air_rounded,
                      size:  36,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── BREATHE heading ──────────────────────────────────────────────
          Text(
            'BREATHE',
            style: AppTypography.heading(
              size:  28,
              color: AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: AppSpacing.xs),

          // ── Subtitle ─────────────────────────────────────────────────────
          Text(
            'Give ${widget.ventilationsExpected} rescue breaths',
            style: AppTypography.bodyMedium(
              size:  15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '1 full second each',
            style: AppTypography.caption(color: AppColors.textSecondary),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Pause duration timer ─────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical:   AppSpacing.sm + AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color:        _timerIsRed ? AppColors.errorBg : AppColors.screenBgGrey,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        // AFTER
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pause duration',
              style: AppTypography.label(
                size:  11,
                color: _timerIsRed ? AppColors.error : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _timerDisplay,
                  style: AppTypography.numericDisplay(
                    size:  26,
                    color: _timerIsRed ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
      ),
        ],
      ),
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────

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
        border: Border(
          top: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.xs,
        children: [
          Text(
            'Closes automatically when compressions resume',
            style: AppTypography.caption(color: AppColors.textDisabled),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Pill — small rounded chip used in the header row
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