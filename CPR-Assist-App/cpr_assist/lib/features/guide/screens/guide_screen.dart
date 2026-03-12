import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GuideScreen
//
// A comprehensive, always-accessible CPR reference guide.
// No login required — visible in both Emergency and Training modes.
//
// Sections:
//   1. Hero banner
//   2. Emergency action steps (call → AED → CPR)
//   3. Chest compression technique with inline schematic
//   4. Compression rate visual gauge
//   5. Hand position schematic (drawn with CustomPainter)
//   6. Rescue breaths (30:2 ratio)
//   7. AED usage steps with pad placement schematic
//   8. Critical reminders
//   9. Find AED call-to-action
// ─────────────────────────────────────────────────────────────────────────────

class GuideScreen extends StatelessWidget {
  /// Called when the user taps "Find Nearest AED" to switch to the map tab.
  final Function(int)? onTabTapped;

  const GuideScreen({super.key, this.onTabTapped});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Hero ───────────────────────────────────────────────────
            const _GuideHero(),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),

                  // ── 2. Emergency steps ──────────────────────────────────
                  const _SectionHeader(
                    icon:  Icons.emergency_rounded,
                    color: AppColors.emergencyRed,
                    title: 'Emergency Action Steps',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _EmergencySteps(),

                  const SizedBox(height: AppSpacing.xl),

                  // ── 3. Chest compression technique ──────────────────────
                  const _SectionHeader(
                    icon:  Icons.favorite_rounded,
                    color: AppColors.primary,
                    title: 'Chest Compression Technique',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _CompressionSpecRow(),
                  const SizedBox(height: AppSpacing.md),

                  // ── 4. Compression rate gauge ────────────────────────────
                  const _CompressionRateCard(),
                  const SizedBox(height: AppSpacing.md),

                  // ── 5. Hand position schematic ───────────────────────────
                  const _HandPositionCard(),

                  const SizedBox(height: AppSpacing.xl),

                  // ── 6. Rescue breaths ────────────────────────────────────
                  const _SectionHeader(
                    icon:  Icons.air_rounded,
                    color: AppColors.info,
                    title: 'Rescue Breaths',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _RescueBreathsCard(),

                  const SizedBox(height: AppSpacing.xl),

                  // ── 7. AED usage ─────────────────────────────────────────
                  const _SectionHeader(
                    icon:  Icons.bolt_rounded,
                    color: AppColors.warning,
                    title: 'Using an AED',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const _AedPadPlacementCard(),
                  const SizedBox(height: AppSpacing.md),
                  const _AedSteps(),

                  const SizedBox(height: AppSpacing.xl),

                  // ── 8. Critical reminders ────────────────────────────────
                  const _CriticalRemindersCard(),

                  const SizedBox(height: AppSpacing.xl),

                  // ── 9. Find AED CTA ──────────────────────────────────────
                  _FindAedCta(onTabTapped: onTabTapped),

                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1. HERO BANNER
// ═══════════════════════════════════════════════════════════════════════════════

class _GuideHero extends StatelessWidget {
  const _GuideHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppDecorations.primaryGradientCard(radius: 0),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + title row
          Row(
            children: [
              Container(
                width:  AppSpacing.iconXl + AppSpacing.md,  // 64
                height: AppSpacing.iconXl + AppSpacing.md,
                decoration: BoxDecoration(
                  color:  AppColors.textOnDark.withValues(alpha: 0.15),
                  shape:  BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_rounded,
                  color: AppColors.textOnDark,
                  size:  AppSpacing.iconLg,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CPR Guide',
                      style: AppTypography.heading(
                        size:  26,
                        color: AppColors.textOnDark,
                      ),
                    ),
                    Text(
                      'Evidence-based guidelines · ERC 2021',
                      style: AppTypography.caption(
                        color: AppColors.textOnDark.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Every second counts in a cardiac arrest. '
                'Follow these steps to maximise the chance of survival '
                'until emergency services arrive.',
            style: AppTypography.body(
              size:  14,
              color: AppColors.textOnDark.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // "No login required" chip
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.chipPaddingH,
              vertical:   AppSpacing.chipPaddingV + AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color:        AppColors.textOnDark.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
              border: Border.all(
                color: AppColors.textOnDark.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_open_rounded,
                  size:  AppSpacing.iconSm,
                  color: AppColors.textOnDark,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Always accessible — no login required',
                  style: AppTypography.label(
                    size:  12,
                    color: AppColors.textOnDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED — Section header
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title;

  const _SectionHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width:  AppSpacing.iconLg,
          height: AppSpacing.iconLg,
          decoration: AppDecorations.iconCircle(
            bg: color.withValues(alpha: 0.12),
          ),
          child: Icon(icon, color: color, size: AppSpacing.iconSm),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTypography.heading(size: 18)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 2. EMERGENCY ACTION STEPS
// ═══════════════════════════════════════════════════════════════════════════════

class _EmergencySteps extends StatelessWidget {
  const _EmergencySteps();

  static const List<_StepData> _steps = [
    _StepData(
      icon:  Icons.security_rounded,
      color: AppColors.primary,
      title: 'Check Scene Safety',
      body:  'Ensure the area is safe for you and the victim before approaching. '
          'Look for hazards: traffic, electrical cables, unstable structures.',
    ),
    _StepData(
      icon:  Icons.touch_app_rounded,
      color: AppColors.warning,
      title: 'Check Responsiveness',
      body:  'Tap both shoulders firmly and shout "Are you okay?". '
          'If no response and no normal breathing, assume cardiac arrest.',
    ),
    _StepData(
      icon:  Icons.phone_in_talk_rounded,
      color: AppColors.emergencyRed,
      title: 'Call 112 Immediately',
      body:  'Call emergency services. Give your exact location. '
          'Stay on the line — the dispatcher will guide you.',
      highlight: true,
    ),
    _StepData(
      icon:  Icons.location_on_rounded,
      color: AppColors.success,
      title: 'Send Someone for the AED',
      body:  'Shout for a nearby AED. Use the AED Map tab to find the '
          'closest defibrillator. Every minute without defibrillation '
          'reduces survival by 10%.',
    ),
    _StepData(
      icon:  Icons.favorite_rounded,
      color: AppColors.primary,
      title: 'Start CPR Immediately',
      body:  'Begin chest compressions without delay. '
          'Use the Live CPR tab for real-time depth and rate guidance.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          _EmergencyStepCard(step: i + 1, data: _steps[i]),
          if (i < _steps.length - 1)
            _StepConnector(color: _steps[i].color),
        ],
      ],
    );
  }
}

class _StepData {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   body;
  final bool     highlight;

  const _StepData({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.highlight = false,
  });
}

class _EmergencyStepCard extends StatelessWidget {
  final int       step;
  final _StepData data;

  const _EmergencyStepCard({required this.step, required this.data});

  @override
  Widget build(BuildContext context) {
    final decoration = data.highlight
        ? AppDecorations.emergencyCard()
        : AppDecorations.card();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number badge
          Container(
            width:  AppSpacing.iconXl,
            height: AppSpacing.iconXl,
            decoration: BoxDecoration(
              color:  data.color,
              shape:  BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: AppTypography.heading(
                  size:  18,
                  color: AppColors.textOnDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(data.icon, size: AppSpacing.iconSm, color: data.color),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        data.title,
                        style: AppTypography.subheading(color: AppColors.textPrimary),
                      ),
                    ),
                    if (data.highlight)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.chipPaddingH,
                          vertical:   AppSpacing.xxs,
                        ),
                        decoration: AppDecorations.chip(
                          color: AppColors.emergencyRed,
                          bg:   AppColors.emergencyBg,
                        ),
                        child: Text(
                          'PRIORITY',
                          style: AppTypography.badge(
                            size:  10,
                            color: AppColors.emergencyRed,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(data.body, style: AppTypography.body()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  final Color color;
  const _StepConnector({required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: AppSpacing.iconXl, // align with step number badge centre
          child: Center(
            child: Container(
              width:  AppSpacing.xxs,
              height: AppSpacing.md,
              color: color.withValues(alpha: 0.35),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 3. COMPRESSION SPEC ROW
// ═══════════════════════════════════════════════════════════════════════════════

class _CompressionSpecRow extends StatelessWidget {
  const _CompressionSpecRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _SpecChip(
            icon:    Icons.speed_rounded,
            color:   AppColors.primary,
            value:   '100–120',
            unit:    'per min',
            caption: 'Rate',
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _SpecChip(
            icon:    Icons.straighten_rounded,
            color:   AppColors.success,
            value:   '5–6 cm',
            unit:    'depth',
            caption: 'Push hard',
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _SpecChip(
            icon:    Icons.expand_rounded,
            color:   AppColors.info,
            value:   'Full',
            unit:    'recoil',
            caption: 'Let chest rise',
          ),
        ),
      ],
    );
  }
}

class _SpecChip extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   value;
  final String   unit;
  final String   caption;

  const _SpecChip({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical:   AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          Icon(icon, color: color, size: AppSpacing.iconMd),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.subheading(size: 14, color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          Text(
            unit,
            style: AppTypography.caption(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            caption,
            style: AppTypography.badge(size: 10, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 4. COMPRESSION RATE CARD
// Visual bar showing the 100–120 CPM safe zone
// ═══════════════════════════════════════════════════════════════════════════════

class _CompressionRateCard extends StatelessWidget {
  const _CompressionRateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.primaryCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.speed_rounded,
                size:  AppSpacing.iconSm,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Target Compression Rate',
                style: AppTypography.subheading(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Aim for 100–120 compressions per minute — roughly 2 per second. '
                'Too slow reduces blood flow; too fast prevents full cardiac refill.',
            style: AppTypography.body(),
          ),
          const SizedBox(height: AppSpacing.md),
          const _RateGaugeBar(),
          const SizedBox(height: AppSpacing.sm),
          // Scale labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('60 CPM', style: AppTypography.caption()),
              Text('100', style: AppTypography.label(color: AppColors.success)),
              Text('120', style: AppTypography.label(color: AppColors.success)),
              Text('160 CPM', style: AppTypography.caption()),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Rhythm tip
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.tintedCard(),
            child: Row(
              children: [
                const Icon(
                  Icons.music_note_rounded,
                  size:  AppSpacing.iconSm,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Rhythm tip: "Stayin\' Alive" by Bee Gees is ~103 BPM — '
                        'hum it to keep the right pace.',
                    style: AppTypography.body(size: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RateGaugeBar extends StatelessWidget {
  const _RateGaugeBar();

  // Range: 60–160 CPM displayed
  static const double _minCpm  = 60.0;
  static const double _maxCpm  = 160.0;
  static const double _safeMin = 100.0;
  static const double _safeMax = 120.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final totalW = constraints.maxWidth;

        double fraction(double cpm) =>
            ((cpm - _minCpm) / (_maxCpm - _minCpm)).clamp(0.0, 1.0);

        final safeLeft  = fraction(_safeMin) * totalW;
        final safeWidth = (fraction(_safeMax) - fraction(_safeMin)) * totalW;

        return SizedBox(
          height: AppSpacing.lg,
          child: Stack(
            children: [
              // Background track
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color:        AppColors.divider,
                    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  ),
                ),
              ),
              // Safe zone highlight
              Positioned(
                left:  safeLeft,
                width: safeWidth,
                top:   0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'TARGET ZONE',
                    style: AppTypography.badge(
                      size:  9,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 5. HAND POSITION CARD (CustomPainter schematic)
// ═══════════════════════════════════════════════════════════════════════════════

class _HandPositionCard extends StatelessWidget {
  const _HandPositionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pan_tool_rounded,
                size:  AppSpacing.iconSm,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Hand Position',
                style: AppTypography.subheading(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Schematic
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _ChestSchematicPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Bullet instructions
          const _BulletList(items: [
            'Place the heel of one hand on the centre of the chest (lower half of sternum)',
            'Place your other hand on top — fingers interlaced, not touching the chest',
            'Keep arms straight, shoulders directly above hands',
            'Lean forward so your body weight does the work — not your arms',
          ]),
        ],
      ),
    );
  }
}

class _ChestSchematicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // ── Torso outline ──────────────────────────────────────────────────────
    final torsoPaint = Paint()
      ..color = AppColors.primaryLight
      ..style = PaintingStyle.fill;
    final torsoBorderPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final torsoRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.5),
        width:  size.width * 0.55,
        height: size.height * 0.82,
      ),
      const Radius.circular(AppSpacing.cardRadiusLg),
    );
    canvas.drawRRect(torsoRect, torsoPaint);
    canvas.drawRRect(torsoRect, torsoBorderPaint);

    // ── Sternum line ──────────────────────────────────────────────────────
    final sternumPaint = Paint()
      ..color = AppColors.primaryDark.withValues(alpha: 0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, size.height * 0.08),
      Offset(cx, size.height * 0.85),
      sternumPaint,
    );

    // ── Ribs (3 pairs) ─────────────────────────────────────────────────────
    final ribPaint = Paint()
      ..color = AppColors.primaryDark.withValues(alpha: 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.25 + i * 0.18);
      final halfW = size.width * 0.22;

      // Left rib arc
      final leftPath = Path()
        ..moveTo(cx - AppSpacing.xs, y)
        ..quadraticBezierTo(
          cx - halfW * 0.5, y - 12,
          cx - halfW,       y + 8,
        );
      canvas.drawPath(leftPath, ribPaint);

      // Right rib arc
      final rightPath = Path()
        ..moveTo(cx + AppSpacing.xs, y)
        ..quadraticBezierTo(
          cx + halfW * 0.5, y - 12,
          cx + halfW,       y + 8,
        );
      canvas.drawPath(rightPath, ribPaint);
    }

    // ── Compression target zone (lower half of sternum) ─────────────────
    final targetY = size.height * 0.58;

    // Glowing halo
    final haloPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, targetY), 30, haloPaint);

    // Hand heel oval
    final handPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, targetY), width: 44, height: 26),
      handPaint,
    );

    // Cross-hatch on hand to suggest fingers
    final crossPaint = Paint()
      ..color = AppColors.textOnDark.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(
        Offset(cx + i * 8.0, targetY - 10),
        Offset(cx + i * 8.0, targetY + 10),
        crossPaint,
      );
    }

    // ── Labels ─────────────────────────────────────────────────────────────
    void drawLabel(String text, Offset offset, {bool right = true}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          right ? offset.dx : offset.dx - tp.width,
          offset.dy - tp.height / 2,
        ),
      );
    }

    // Target zone arrow line
    final arrowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Right label
    canvas.drawLine(
      Offset(cx + 24, targetY),
      Offset(cx + size.width * 0.18, targetY),
      arrowPaint,
    );
    drawLabel('Place hands\nhere', Offset(cx + size.width * 0.19, targetY));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 6. RESCUE BREATHS CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _RescueBreathsCard extends StatelessWidget {
  const _RescueBreathsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 30:2 ratio visual
          const _RatioVisual(),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.primaryCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size:  AppSpacing.iconSm,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'If you are not trained in rescue breaths, '
                        'provide hands-only CPR — continuous compressions without pauses '
                        'are still highly effective.',
                    style: AppTypography.body(size: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Rescue Breath Technique',
            style: AppTypography.subheading(),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(items: [
            'Tilt the head back and lift the chin to open the airway',
            'Pinch the nose firmly shut',
            'Create a complete seal over the mouth',
            'Give a breath lasting ~1 second — watch for visible chest rise',
            'If chest doesn\'t rise, reposition the head and try once more',
            'Give 2 breaths then immediately return to compressions',
          ]),
        ],
      ),
    );
  }
}

class _RatioVisual extends StatelessWidget {
  const _RatioVisual();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color:        AppColors.primaryDark,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 15,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color:        AppColors.primaryAlt,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
              ),
              child: Column(
                children: [
                  Text(
                    '30',
                    style: AppTypography.numericDisplay(
                      size:  32,
                      color: AppColors.textOnDark,
                    ),
                  ),
                  Text(
                    'COMPRESSIONS',
                    style: AppTypography.badge(
                      size:  10,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              ':',
              style: AppTypography.heading(
                size:  28,
                color: AppColors.textOnDark,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color:        AppColors.info.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
              ),
              child: Column(
                children: [
                  Text(
                    '2',
                    style: AppTypography.numericDisplay(
                      size:  32,
                      color: AppColors.textOnDark,
                    ),
                  ),
                  Text(
                    'BREATHS',
                    style: AppTypography.badge(
                      size:  10,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 7a. AED PAD PLACEMENT SCHEMATIC
// ═══════════════════════════════════════════════════════════════════════════════

class _AedPadPlacementCard extends StatelessWidget {
  const _AedPadPlacementCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.warningCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                size:  AppSpacing.iconSm,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'AED Pad Placement',
                style: AppTypography.subheading(color: AppColors.warning),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _AedSchematicPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(items: [
            'Pad 1 (right): below the right collarbone',
            'Pad 2 (left): left side, below the armpit on the ribcage',
            'Dry the chest first if wet — moisture reduces shock effectiveness',
            'Remove any medication patches from the placement area',
          ]),
        ],
      ),
    );
  }
}

class _AedSchematicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // ── Torso ──────────────────────────────────────────────────────────────
    final torsoPaint = Paint()
      ..color = AppColors.warningBg
      ..style = PaintingStyle.fill;
    final torsoBorderPaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final torsoRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, size.height * 0.52),
        width:  size.width * 0.50,
        height: size.height * 0.86,
      ),
      const Radius.circular(AppSpacing.cardRadiusLg),
    );
    canvas.drawRRect(torsoRect, torsoPaint);
    canvas.drawRRect(torsoRect, torsoBorderPaint);

    // ── Collarbone line ────────────────────────────────────────────────────
    final collarPaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx - size.width * 0.22, size.height * 0.14),
      Offset(cx + size.width * 0.22, size.height * 0.14),
      collarPaint,
    );

    // ── Pad 1 — right side, below collarbone ──────────────────────────────
    _drawPad(
      canvas,
      label: '1',
      center: Offset(cx + size.width * 0.14, size.height * 0.24),
      color: AppColors.warning,
    );

    // ── Pad 2 — left side, below armpit ───────────────────────────────────
    _drawPad(
      canvas,
      label: '2',
      center: Offset(cx - size.width * 0.19, size.height * 0.58),
      color: AppColors.warning,
    );

    // ── Lead line between pads ─────────────────────────────────────────────
    final linePaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Dashed approximation
    final p1 = Offset(cx + size.width * 0.14, size.height * 0.24);
    final p2 = Offset(cx - size.width * 0.19, size.height * 0.58);
    _drawDashedLine(canvas, p1, p2, linePaint);
  }

  void _drawPad(
      Canvas canvas, {
        required String label,
        required Offset center,
        required Color color,
      }) {
    // Pad rectangle
    final padPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    final padRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 44, height: 32),
      const Radius.circular(AppSpacing.cardRadiusSm),
    );
    canvas.drawRRect(padRect, padPaint);

    // Lightning bolt icon using text
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize:   13,
          fontWeight: FontWeight.w800,
          color:      AppColors.textOnDark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  void _drawDashedLine(
      Canvas canvas,
      Offset p1,
      Offset p2,
      Paint paint,
      ) {
    final dx   = p2.dx - p1.dx;
    final dy   = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    const dashLen = 6.0;
    const gapLen  = 4.0;
    final nx = dx / dist;
    final ny = dy / dist;

    double t = 0;
    while (t < dist) {
      final start = Offset(p1.dx + nx * t, p1.dy + ny * t);
      final end   = Offset(
        p1.dx + nx * (t + dashLen).clamp(0, dist),
        p1.dy + ny * (t + dashLen).clamp(0, dist),
      );
      canvas.drawLine(start, end, paint);
      t += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 7b. AED USAGE STEPS
// ═══════════════════════════════════════════════════════════════════════════════

class _AedSteps extends StatelessWidget {
  const _AedSteps();

  static const List<_AedStepData> _steps = [
    _AedStepData(
      icon:  Icons.power_settings_new_rounded,
      color: AppColors.success,
      title: 'Power on the AED',
      body:  'Open the case — most AEDs power on automatically. '
          'Immediately follow the voice and visual prompts.',
    ),
    _AedStepData(
      icon:  Icons.person_remove_rounded,
      color: AppColors.primary,
      title: 'Expose & prepare the chest',
      body:  'Remove clothing. Dry the chest if wet. '
          'Remove any medication patches from the pad areas.',
    ),
    _AedStepData(
      icon:  Icons.bolt_rounded,
      color: AppColors.warning,
      title: 'Attach the pads',
      body:  'Follow the pad diagrams on each sticker exactly. '
          'Press firmly for full contact. '
          'Refer to the schematic above.',
    ),
    _AedStepData(
      icon:  Icons.do_not_touch_rounded,
      color: AppColors.emergencyRed,
      title: 'Stand clear — let the AED analyse',
      body:  'Do not touch the patient. '
          'Announce loudly: "Stand clear!" '
          'The AED will assess heart rhythm automatically.',
    ),
    _AedStepData(
      icon:  Icons.electric_bolt_rounded,
      color: AppColors.emergencyRed,
      title: 'Deliver shock (if advised)',
      body:  'Press the flashing shock button ONLY when prompted. '
          'Ensure nobody is touching the patient. '
          'If no shock is advised, continue CPR immediately.',
    ),
    _AedStepData(
      icon:  Icons.favorite_rounded,
      color: AppColors.primary,
      title: 'Resume CPR immediately',
      body:  'Begin chest compressions within 10 seconds of the shock. '
          'Continue until the AED prompts another analysis '
          'or emergency services take over.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _steps.length; i++)
          _AedStepRow(step: i + 1, data: _steps[i]),
      ],
    );
  }
}

class _AedStepData {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   body;

  const _AedStepData({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });
}

class _AedStepRow extends StatelessWidget {
  final int          step;
  final _AedStepData data;

  const _AedStepRow({required this.step, required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: AppDecorations.accentCard(accentColor: data.color),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step number circle
            Container(
              width:  AppSpacing.iconLg,
              height: AppSpacing.iconLg,
              decoration: BoxDecoration(
                color: data.color,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$step',
                  style: AppTypography.subheading(
                    color: AppColors.textOnDark,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(data.icon, size: AppSpacing.iconSm, color: data.color),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          data.title,
                          style: AppTypography.bodyMedium(size: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(data.body, style: AppTypography.body(size: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 8. CRITICAL REMINDERS CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _CriticalRemindersCard extends StatelessWidget {
  const _CriticalRemindersCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.emergencyCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.emergencyRed,
                size:  AppSpacing.iconMd,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Critical Reminders',
                style: AppTypography.subheading(color: AppColors.emergencyRed),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _BulletList(
            bulletColor: AppColors.emergencyRed,
            items: [
              'Continue CPR until emergency services take over or the person shows clear signs of life',
              'Minimise any pause in compressions — keep interruptions under 10 seconds',
              'Switch rescuers every 2 minutes to maintain compression quality',
              'Do not stop if you hear a rib crack — continue compressions',
              'If an AED is available, use it as soon as possible',
              'Never give up — CPR significantly improves survival chances',
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 9. FIND AED CTA
// ═══════════════════════════════════════════════════════════════════════════════

class _FindAedCta extends StatelessWidget {
  final Function(int)? onTabTapped;
  const _FindAedCta({this.onTabTapped});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTabTapped != null ? () => onTabTapped!(1) : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: AppDecorations.primaryGradientCard(),
        child: Row(
          children: [
            Container(
              width:  AppSpacing.iconXl + AppSpacing.sm, // 56
              height: AppSpacing.iconXl + AppSpacing.sm,
              decoration: BoxDecoration(
                color:  AppColors.textOnDark.withValues(alpha: 0.15),
                shape:  BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: AppColors.textOnDark,
                size:  AppSpacing.iconMd,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find Nearest AED',
                    style: AppTypography.subheading(
                      color: AppColors.textOnDark,
                    ),
                  ),
                  Text(
                    'Tap to open the AED map and locate\n'
                        'the closest defibrillator to you now',
                    style: AppTypography.body(
                      size:  13,
                      color: AppColors.textOnDark.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textOnDark,
              size:  AppSpacing.iconMd,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED — Bullet list helper
// ═══════════════════════════════════════════════════════════════════════════════

class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color        bulletColor;

  const _BulletList({
    required this.items,
    this.bulletColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) => _BulletItem(text: item, color: bulletColor)).toList(),
    );
  }
}

class _BulletItem extends StatelessWidget {
  final String text;
  final Color  color;

  const _BulletItem({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Container(
              width:  AppSpacing.xs + AppSpacing.xxs, // 6
              height: AppSpacing.xs + AppSpacing.xxs,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: AppTypography.body()),
          ),
        ],
      ),
    );
  }
}