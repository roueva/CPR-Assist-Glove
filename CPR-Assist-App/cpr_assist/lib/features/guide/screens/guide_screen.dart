import 'dart:math' as math;

import 'package:cpr_assist/features/guide/screens/quiz_screen.dart';
import 'package:flutter/material.dart';
import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GuideScreen
//
// Tabbed CPR reference guide — always accessible, no login required.
//
// Layout:
//   • Persistent emergency banner (red) — always visible, tappable
//   • Sticky tab bar: Steps | Technique | AED | Special cases
//   • Each tab is an independent scroll — no shared scroll position
//
// Design principles:
//   • Emergency context first — critical info reachable in < 3 taps
//   • Calm-study context second — full reference detail in each tab
//   • No login gates, no navigation guards
// ─────────────────────────────────────────────────────────────────────────────

class GuideScreen extends StatefulWidget {
  final Function(int)? onTabTapped;
  const GuideScreen({super.key, this.onTabTapped});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<_TabItem> _tabs = [
    _TabItem(icon: Icons.format_list_numbered_rounded, label: 'Steps'),
    _TabItem(icon: Icons.pan_tool_rounded,             label: 'Technique'),
    _TabItem(icon: Icons.bolt_rounded,                 label: 'AED'),
    _TabItem(icon: Icons.more_horiz_rounded,           label: 'More'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Column(
        children: [
          // ── Persistent emergency banner ───────────────────────────────────
          const _EmergencyBanner(),

          // ── Sticky tab bar ────────────────────────────────────────────────
          _GuideTabBar(controller: _tabController, tabs: _tabs),

          // ── Tab content ───────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _StepsTab(onTabTapped: widget.onTabTapped),
                const _TechniqueTab(),
                const _AedTab(),
                const _MoreTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String   label;
  const _TabItem({required this.icon, required this.label});
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMERGENCY BANNER
// Always visible — collapses to show the 5 critical actions
// ═══════════════════════════════════════════════════════════════════════════════

class _EmergencyBanner extends StatefulWidget {
  const _EmergencyBanner();

  @override
  State<_EmergencyBanner> createState() => _EmergencyBannerState();
}

class _EmergencyBannerState extends State<_EmergencyBanner>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double>   _expandAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _expandAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width:      double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.emergency, AppColors.emergencyDark],
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            // ── Collapsed header row ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width:  32,
                    height: 32,
                    decoration: BoxDecoration(
                      color:  AppColors.textOnDark.withValues(alpha: 0.20),
                      shape:  BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.emergency_rounded,
                      color: AppColors.textOnDark,
                      size:  18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency right now?',
                          style: AppTypography.bodyMedium(
                            size:  14,
                            color: AppColors.textOnDark,
                          ),
                        ),
                        Text(
                          'Tap to see the 5 critical steps',
                          style: AppTypography.body(
                            size:  12,
                            color: AppColors.textOnDark.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns:    _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 280),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ],
              ),
            ),

            // ── Expanded steps ──────────────────────────────────────────────
            SizeTransition(
              sizeFactor: _expandAnim,
              child: Container(
                color: AppColors.emergency.withValues(alpha: 0.15),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
                ),
                child: Column(
                  children: [
                    const Divider(
                      color:  AppColors.textOnDark,
                      height: AppSpacing.md,
                      thickness: 0.2,
                    ),
                    ..._kEmergencyQuickSteps.asMap().entries.map(
                          (e) => _QuickStep(
                        number: e.key + 1,
                        text:   e.value,
                        isLast: e.key == _kEmergencyQuickSteps.length - 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const List<String> _kEmergencyQuickSteps = [
  'Check scene safety — approach only when safe',
  'Tap shoulders, shout "Are you okay?" — call 112 immediately',
  'Place heel of hand on centre of chest. Second hand on top.',
  'Push hard, fast — 5–6 cm deep at 100–120 per minute',
  'After every 30 compressions, give 2 rescue breaths',
];

class _QuickStep extends StatelessWidget {
  final int    number;
  final String text;
  final bool   isLast;

  const _QuickStep({
    required this.number,
    required this.text,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width:  24,
              height: 24,
              decoration: BoxDecoration(
                color:  AppColors.textOnDark.withValues(alpha: 0.25),
                shape:  BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: AppTypography.badge(
                    size:  11,
                    color: AppColors.textOnDark,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(
                width:  1,
                height: 16,
                color:  AppColors.textOnDark.withValues(alpha: 0.25),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: isLast ? 0 : AppSpacing.xs,
              top:    2,
            ),
            child: Text(
              text,
              style: AppTypography.body(
                size:  13,
                color: AppColors.textOnDark,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB BAR
// ═══════════════════════════════════════════════════════════════════════════════

class _GuideTabBar extends StatelessWidget {
  final TabController    controller;
  final List<_TabItem>   tabs;

  const _GuideTabBar({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.screenBgGrey,
      child: TabBar(
        controller:         controller,
        labelColor:         AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor:     AppColors.primary,
        indicatorWeight:    2,
        labelStyle:         AppTypography.label(size: 12),
        unselectedLabelStyle: AppTypography.body(size: 12),
        tabs: tabs
            .map(
              (t) => Tab(
            height: 48,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(t.icon, size: 18),
                const SizedBox(height: 2),
                Text(t.label),
              ],
            ),
          ),
        )
            .toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — STEPS
// Sequential CPR flow + quick-ref number chips at top
// ═══════════════════════════════════════════════════════════════════════════════

class _StepsTab extends StatelessWidget {
  final Function(int)? onTabTapped;
  const _StepsTab({this.onTabTapped});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top:    AppSpacing.md,
        left:   AppSpacing.md,
        right:  AppSpacing.md,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Quick-ref chips ───────────────────────────────────────────────
          const _QuickRefChips(),
          const SizedBox(height: AppSpacing.lg),

          // ── Chain of survival intro ───────────────────────────────────────
          _SectionLabel(
            icon:  Icons.link_rounded,
            label: 'Chain of survival',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _ChainOfSurvivalCard(),
          const SizedBox(height: AppSpacing.xl),

          // ── Step-by-step flow ─────────────────────────────────────────────
          _SectionLabel(
            icon:  Icons.format_list_numbered_rounded,
            label: 'Step-by-step CPR',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _CprStepsList(),
          const SizedBox(height: AppSpacing.xl),

          // ── When to stop ──────────────────────────────────────────────────
          _SectionLabel(
            icon:  Icons.stop_circle_outlined,
            label: 'When to stop',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _WhenToStopCard(),
          const SizedBox(height: AppSpacing.xl),

          // ── Recovery position ─────────────────────────────────────────────
          _SectionLabel(
            icon:  Icons.airline_seat_flat_rounded,
            label: 'Recovery position',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RecoveryPositionCard(),
          const SizedBox(height: AppSpacing.xl),

          // ── Quiz CTA ──────────────────────────────────────────────────────
          _QuizCta(),
          const SizedBox(height: AppSpacing.md),

          // ── Find AED CTA ──────────────────────────────────────────────────
          _FindAedCta(onTabTapped: onTabTapped),
        ],
      ),
    );
  }
}

// ── Quick-ref number chips ────────────────────────────────────────────────────

class _QuickRefChips extends StatelessWidget {
  const _QuickRefChips();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _RefChip(
            value:   '100–120',
            unit:    '/min',
            label:   'Rate',
            color:   AppColors.primary,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _RefChip(
            value:   '5–6 cm',
            unit:    'depth',
            label:   'Push hard',
            color:   AppColors.success,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _RefChip(
            value:   '30 : 2',
            unit:    'ratio',
            label:   'Comp : breaths',
            color:   AppColors.primaryAlt,
          ),
        ),
      ],
    );
  }
}

class _RefChip extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final Color  color;

  const _RefChip({
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border:       Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.numericDisplay(size: 18, color: color),
            textAlign: TextAlign.center,
          ),
          Text(
            unit,
            style: AppTypography.caption(color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.badge(size: 10, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Chain of survival ─────────────────────────────────────────────────────────

class _ChainOfSurvivalCard extends StatelessWidget {
  const _ChainOfSurvivalCard();

  static const List<_ChainLink> _links = [
    _ChainLink(icon: Icons.phone_in_talk_rounded,   color: AppColors.emergency, label: 'Early recognition\n& call'),
    _ChainLink(icon: Icons.favorite_rounded,         color: AppColors.primary,      label: 'Early CPR'),
    _ChainLink(icon: Icons.bolt_rounded,             color: AppColors.warning,      label: 'Early defibrillation'),
    _ChainLink(icon: Icons.local_hospital_rounded,   color: AppColors.success,      label: 'Advanced care'),
    _ChainLink(icon: Icons.self_improvement_rounded, color: AppColors.primaryAlt,   label: 'Recovery'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Survival improves dramatically when each link in the chain is fast. '
                'Every minute without CPR reduces survival by ~10%.',
            style: AppTypography.body(size: 13),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 80,
            child: Row(
              children: [
                for (var i = 0; i < _links.length; i++) ...[
                  Expanded(child: _ChainLinkWidget(link: _links[i])),
                  if (i < _links.length - 1)
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size:  10,
                      color: AppColors.textDisabled,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainLink {
  final IconData icon;
  final Color    color;
  final String   label;
  const _ChainLink({required this.icon, required this.color, required this.label});
}

class _ChainLinkWidget extends StatelessWidget {
  final _ChainLink link;
  const _ChainLinkWidget({required this.link});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width:  36,
          height: 36,
          decoration: BoxDecoration(
            color:  link.color.withValues(alpha: 0.12),
            shape:  BoxShape.circle,
          ),
          child: Icon(link.icon, color: link.color, size: 18),
        ),
        const SizedBox(height: 4),
        Text(
          link.label,
          style: AppTypography.badge(size: 9, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
          maxLines: 2,
        ),
      ],
    );
  }
}

// ── CPR steps list (left-rail connector design) ───────────────────────────────

class _CprStepsList extends StatelessWidget {
  const _CprStepsList();

  static const List<_StepData> _steps = [
    _StepData(
      icon:    Icons.security_rounded,
      color:   AppColors.primary,
      title:   'Check scene safety',
      body:    'Ensure the area is safe for you and the person before approaching. '
          'Look for hazards: traffic, electrical cables, unstable structures, fire.',
    ),
    _StepData(
      icon:    Icons.touch_app_rounded,
      color:   AppColors.warning,
      title:   'Check responsiveness',
      body:    'Tap both shoulders firmly, shout "Are you okay?". '
          'Look for normal breathing — occasional gasps do not count. '
          'If no response and no normal breathing, assume cardiac arrest.',
    ),
    _StepData(
      icon:    Icons.phone_in_talk_rounded,
      color:   AppColors.emergency,
      title:   'Call 112 immediately',
      body:    'Call emergency services or instruct a specific bystander to call. '
          'Give your exact location. Stay on the line — the dispatcher will guide you. '
          'If alone with an infant or child, give 1 minute of CPR first then call.',
      urgent:  true,
    ),
    _StepData(
      icon:    Icons.location_on_rounded,
      color:   AppColors.success,
      title:   'Send someone for the AED',
      body:    'Shout for a nearby AED. Point at a specific person: '
          '"You — get the AED from reception". Use the AED Map to locate the closest one.',
    ),
    _StepData(
      icon:    Icons.pan_tool_rounded,
      color:   AppColors.primary,
      title:   'Position hands',
      body:    'Expose the chest. Place the heel of your dominant hand on the lower '
          'half of the sternum — centre of the chest. Second hand on top, '
          'fingers interlaced and raised so only the heel contacts the chest.',
    ),
    _StepData(
      icon:    Icons.favorite_rounded,
      color:   AppColors.primary,
      title:   'Give 30 compressions',
      body:    'Arms straight, shoulders directly above hands. Push hard and fast — '
          '5–6 cm deep at 100–120 per minute. Count aloud. '
          'Allow full chest recoil after each compression — do not lean.',
    ),
    _StepData(
      icon:    Icons.air_rounded,
      color:   AppColors.primaryAlt,
      title:   'Give 2 rescue breaths',
      body:    'Tilt head back, lift chin, pinch nose. Seal mouth completely. '
          'Blow steadily for ~1 second until chest rises visibly. '
          'If untrained — skip breaths and do continuous compressions only.',
    ),
    _StepData(
      icon:    Icons.repeat_rounded,
      color:   AppColors.success,
      title:   'Continue 30:2 cycles',
      body:    'Keep going until the AED is ready, EMS arrives, '
          'the person shows clear signs of life, or you cannot continue. '
          'Switch rescuer every 2 minutes if possible.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            _CprStepRow(
              step:   i + 1,
              data:   _steps[i],
              isLast: i == _steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _StepData {
  final IconData icon;
  final Color    color;
  final String   title;
  final String   body;
  final bool     urgent;
  const _StepData({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    this.urgent = false,
  });
}

class _CprStepRow extends StatelessWidget {
  final int       step;
  final _StepData data;
  final bool      isLast;

  const _CprStepRow({
    required this.step,
    required this.data,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left rail: number + connector line ─────────────────────────
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width:  28,
                  height: 28,
                  decoration: BoxDecoration(
                    color:  data.urgent
                        ? AppColors.emergency
                        : data.color,
                    shape:  BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$step',
                      style: AppTypography.badge(
                        size:  12,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 1.5,
                        color: data.color.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // ── Content ───────────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : AppSpacing.md,
                top: 3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(data.icon, size: 14, color: data.color),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          data.title,
                          style: AppTypography.bodyMedium(size: 14),
                        ),
                      ),
                      if (data.urgent)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical:   1,
                          ),
                          decoration: AppDecorations.chip(
                            color: AppColors.emergency,
                            bg:    AppColors.errorBg,
                          ),
                          child: Text(
                            'PRIORITY',
                            style: AppTypography.badge(
                              size:  9,
                              color: AppColors.emergency,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(data.body, style: AppTypography.body()),
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
// TAB 2 — TECHNIQUE
// Hand position, rate, depth, recoil — the "how to do it well" content
// ═══════════════════════════════════════════════════════════════════════════════

class _TechniqueTab extends StatelessWidget {
  const _TechniqueTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top:    AppSpacing.md,
        left:   AppSpacing.md,
        right:  AppSpacing.md,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(icon: Icons.pan_tool_rounded,   label: 'Hand position'),
          const SizedBox(height: AppSpacing.sm),
          const _HandPositionCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(icon: Icons.speed_rounded,      label: 'Compression rate'),
          const SizedBox(height: AppSpacing.sm),
          const _CompressionRateCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(icon: Icons.straighten_rounded, label: 'Compression depth'),
          const SizedBox(height: AppSpacing.sm),
          const _CompressionDepthCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(icon: Icons.air_rounded,        label: 'Rescue breaths'),
          const SizedBox(height: AppSpacing.sm),
          const _RescueBreathsCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(icon: Icons.report_problem_rounded, label: 'Common mistakes'),
          const SizedBox(height: AppSpacing.sm),
          const _CommonMistakesCard(),
        ],
      ),
    );
  }
}

// ── Hand position card ────────────────────────────────────────────────────────

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
          SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _ChestSchematicPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _BulletList(items: [
            'Heel of dominant hand on the lower half of the sternum — centre of chest',
            'Second hand on top, fingers interlaced and raised off the chest',
            'Arms straight, elbows locked — shoulders directly above hands',
            'Lean forward so body weight drives compressions, not arm strength',
          ]),
        ],
      ),
    );
  }
}

// ── Compression rate card ─────────────────────────────────────────────────────

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
          Text(
            'Aim for 100–120 compressions per minute — roughly 2 per second. '
                'Too slow reduces blood flow; too fast prevents full cardiac refill.',
            style: AppTypography.body(),
          ),
          const SizedBox(height: AppSpacing.md),
          const _RateGaugeBar(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('60', style: AppTypography.caption()),
              Text('100', style: AppTypography.label(color: AppColors.success)),
              Text('120', style: AppTypography.label(color: AppColors.success)),
              Text('160 /min', style: AppTypography.caption()),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.tintedCard(),
            child: Row(
              children: [
                const Icon(Icons.music_note_rounded,
                    size: AppSpacing.iconSm, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '"Stayin\' Alive" by Bee Gees is ~103 BPM — hum it to keep pace.',
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

  static const double _minCpm  = 60;
  static const double _maxCpm  = 160;
  static const double _safeMin = 100;
  static const double _safeMax = 120;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        double f(double v) => ((v - _minCpm) / (_maxCpm - _minCpm)).clamp(0.0, 1.0);
        final safeLeft  = f(_safeMin) * w;
        final safeWidth = (f(_safeMax) - f(_safeMin)) * w;
        return SizedBox(
          height: AppSpacing.lg,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color:        AppColors.divider,
                    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  ),
                ),
              ),
              Positioned(
                left:   safeLeft,
                width:  safeWidth,
                top:    0,
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

// ── Compression depth card ────────────────────────────────────────────────────

class _CompressionDepthCard extends StatelessWidget {
  const _CompressionDepthCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target depth is 5–6 cm for adults, 4–5 cm for children. '
                'Shallow compressions do not generate enough pressure to circulate blood. '
                'Deeper than 6 cm risks injury.',
            style: AppTypography.body(),
          ),
          const SizedBox(height: AppSpacing.md),
          const _DepthGaugeBar(),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _DepthLegend(color: AppColors.error,   label: 'Too shallow (< 5 cm)'),
              const SizedBox(width: AppSpacing.md),
              _DepthLegend(color: AppColors.success, label: 'Target (5–6 cm)'),
              const SizedBox(width: AppSpacing.md),
              _DepthLegend(color: AppColors.warning, label: 'Too deep (> 6 cm)'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.tintedCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: AppSpacing.iconSm, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Full recoil matters as much as depth. Release all pressure '
                        'between compressions — the chest must return fully to neutral '
                        'for the heart to refill. Do not lean on the chest.',
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

class _DepthGaugeBar extends StatelessWidget {
  const _DepthGaugeBar();

  @override
  Widget build(BuildContext context) {
    // Range 0–8 cm displayed
    // Zones: 0–5 = too shallow (red), 5–6 = target (green), 6–8 = too deep (orange)
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        const total    = 8.0;
        final redW     = (5 / total) * w;
        final greenW   = (1 / total) * w;
        final orangeW  = (2 / total) * w;
        const r        = Radius.circular(AppSpacing.chipRadius);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: AppSpacing.lg,
              child: Row(
                children: [
                  Container(
                    width: redW,
                    decoration: BoxDecoration(
                      color:        AppColors.error.withValues(alpha: 0.65),
                      borderRadius: const BorderRadius.only(
                        topLeft: r, bottomLeft: r,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'TOO SHALLOW',
                      style: AppTypography.badge(
                        size:  8,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ),
                  Container(
                    width: greenW,
                    color: AppColors.success.withValues(alpha: 0.85),
                    alignment: Alignment.center,
                    child: Text(
                      'TARGET',
                      style: AppTypography.badge(
                        size:  8,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ),
                  Container(
                    width: orangeW,
                    decoration: BoxDecoration(
                      color:        AppColors.warning.withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.only(
                        topRight: r, bottomRight: r,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'TOO DEEP',
                      style: AppTypography.badge(
                        size:  8,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: redW,
                  child: Text(
                    '0',
                    style: AppTypography.caption(),
                    textAlign: TextAlign.start,
                  ),
                ),
                SizedBox(
                  width: greenW,
                  child: Text(
                    '5',
                    style: AppTypography.label(color: AppColors.success),
                    textAlign: TextAlign.start,
                  ),
                ),
                SizedBox(
                  width: orangeW,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('6',
                          style:
                          AppTypography.label(color: AppColors.warning)),
                      Text('8 cm',
                          style: AppTypography.caption()),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DepthLegend extends StatelessWidget {
  final Color  color;
  final String label;
  const _DepthLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width:  8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.badge(size: 9, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ── Rescue breaths card ───────────────────────────────────────────────────────

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
          Container(
            padding:    const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:        AppColors.primaryAlt,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 15,
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
                Text(
                  ':',
                  style: AppTypography.heading(
                    size:  28,
                    color: AppColors.textOnDark,
                  ),
                ),
                Expanded(
                  flex: 4,
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
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.primaryCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: AppSpacing.iconSm, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'If untrained in rescue breaths, provide hands-only CPR — '
                        'continuous compressions without pauses are still highly effective.',
                    style: AppTypography.body(size: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Technique', style: AppTypography.subheading()),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(items: [
            'Tilt the head back and lift the chin to open the airway',
            'Pinch the nose firmly shut with thumb and forefinger',
            'Create a complete seal over the mouth',
            'Blow steadily for ~1 second — watch for visible chest rise',
            'If chest doesn\'t rise, reposition the head and try once more',
            'Give 2 breaths then immediately return to compressions — do not delay',
          ]),
        ],
      ),
    );
  }
}

// ── Common mistakes card ──────────────────────────────────────────────────────

class _CommonMistakesCard extends StatelessWidget {
  const _CommonMistakesCard();

  static const List<_MistakeData> _mistakes = [
    _MistakeData(
      title: 'Not going deep enough',
      body:  'Compressions under 5 cm do not circulate blood effectively. '
          'Use body weight with straight arms — lean over the patient rather than pushing with arm strength alone.',
    ),
    _MistakeData(
      title: 'Leaning between compressions',
      body:  'Keeping weight on the chest prevents full recoil and reduces '
          'venous return. Completely lift your weight after every single compression.',
    ),
    _MistakeData(
      title: 'Pausing too long for breaths',
      body:  'Each pause causes coronary perfusion pressure to drop sharply. '
          'Two quick breaths should take no more than 5 seconds total.',
    ),
    _MistakeData(
      title: 'Incorrect hand position',
      body:  'Hands on the lower ribs or xiphoid process risk injury. '
          'Always position on the centre of the chest over the lower sternum.',
    ),
    _MistakeData(
      title: 'Rate dropping with fatigue',
      body:  'Rate often falls below 100 BPM after 1–2 minutes. '
          'Switch rescuers every 2 minutes where possible.',
    ),
    _MistakeData(
      title: 'Stopping when the AED arrives',
      body:  'Keep compressions going while a second person prepares the device. '
          'Only stop when the AED explicitly says "Stand clear".',
    ),
    _MistakeData(
      title: 'Not resuming after a shock',
      body:  'A shock alone rarely restores rhythm. Resume compressions '
          'within 10 seconds of delivery — do not wait to check for a pulse.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.warningCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in _mistakes) ...[
            _MistakeRow(data: m),
            if (m != _mistakes.last)
              const Divider(height: AppSpacing.lg, color: AppColors.divider),
          ],
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.successCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    size: AppSpacing.iconSm, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Imperfect CPR is vastly better than no CPR. '
                        'Do not let fear of making a mistake stop you from acting.',
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

class _MistakeData {
  final String title;
  final String body;
  const _MistakeData({required this.title, required this.body});
}

class _MistakeRow extends StatelessWidget {
  final _MistakeData data;
  const _MistakeRow({required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs + AppSpacing.xxs),
          child: Container(
            width:  AppSpacing.xs + AppSpacing.xxs,
            height: AppSpacing.xs + AppSpacing.xxs,
            decoration: const BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(data.title, style: AppTypography.bodyMedium(size: 14)),
              const SizedBox(height: AppSpacing.xxs),
              Text(data.body, style: AppTypography.body()),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — AED
// ═══════════════════════════════════════════════════════════════════════════════

class _AedTab extends StatelessWidget {
  const _AedTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top:    AppSpacing.md,
        left:   AppSpacing.md,
        right:  AppSpacing.md,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Urgency banner ────────────────────────────────────────────────
          Container(
            width:  double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.emergencyCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt_rounded,
                    size: AppSpacing.iconSm, color: AppColors.emergency),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Do not stop CPR until the AED is ready and prompts you. '
                        'Resume compressions immediately after every shock — do not wait to check for a pulse.',
                    style: AppTypography.bodyMedium(
                        size: 13, color: AppColors.emergency),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _SectionLabel(icon: Icons.list_alt_rounded, label: 'Pad placement'),
          const SizedBox(height: AppSpacing.sm),
          const _AedPadPlacementCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(icon: Icons.list_alt_rounded, label: 'Step-by-step usage'),
          const SizedBox(height: AppSpacing.sm),
          const _AedSteps(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(icon: Icons.warning_amber_rounded, label: 'Important notes'),
          const SizedBox(height: AppSpacing.sm),
          const _AedNotesCard(),
        ],
      ),
    );
  }
}

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
          SizedBox(
            height: 190,
            child: CustomPaint(
              painter: _AedSchematicPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(
            bulletColor: AppColors.warning,
            items: [
              'Pad 1 (right): below the right collarbone, right of the sternum',
              'Pad 2 (left): left side of the chest, below the armpit on the ribcage',
              'Dry the chest first — moisture reduces shock effectiveness',
              'Remove any medication patches from the pad placement area',
              'For children under 8: use pediatric pads if available; if not, adult pads can be used',
            ],
          ),
        ],
      ),
    );
  }
}

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
      title: 'Expose and prepare the chest',
      body:  'Remove clothing. Dry the chest if wet. '
          'Remove medication patches from pad areas. Shave excessive chest hair if a razor is available.',
    ),
    _AedStepData(
      icon:  Icons.bolt_rounded,
      color: AppColors.warning,
      title: 'Attach the pads',
      body:  'Follow the diagrams printed on each pad exactly. '
          'Press firmly for full skin contact. Refer to the pad placement diagram above.',
    ),
    _AedStepData(
      icon:  Icons.do_not_touch_rounded,
      color: AppColors.emergency,
      title: 'Stand clear — let the AED analyse',
      body:  'Do not touch the patient during analysis. '
          'Announce loudly: "Stand clear — everyone back!" '
          'The AED assesses heart rhythm automatically.',
    ),
    _AedStepData(
      icon:  Icons.electric_bolt_rounded,
      color: AppColors.emergency,
      title: 'Deliver shock if advised',
      body:  'Press the flashing shock button only when prompted. '
          'Verify no one is touching the patient before pressing. '
          'If no shock is advised, immediately resume CPR.',
    ),
    _AedStepData(
      icon:  Icons.favorite_rounded,
      color: AppColors.primary,
      title: 'Resume CPR immediately',
      body:  'Begin compressions within 10 seconds of the shock. '
          'Continue until the AED prompts the next analysis (~2 minutes) '
          'or emergency services take over.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            _AedStepRow(
              step:   i + 1,
              data:   _steps[i],
              isLast: i == _steps.length - 1,
            ),
        ],
      ),
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
  final bool         isLast;

  const _AedStepRow({
    required this.step,
    required this.data,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width:  28,
                  height: 28,
                  decoration: BoxDecoration(
                    color:  data.color,
                    shape:  BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$step',
                      style: AppTypography.badge(
                        size:  12,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 1.5,
                        color: data.color.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : AppSpacing.md,
                top:    3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(data.icon, size: 14, color: data.color),
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
                  Text(data.body, style: AppTypography.body()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AedNotesCard extends StatelessWidget {
  const _AedNotesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: const _BulletList(items: [
        'Implanted pacemaker or ICD: place pads at least 8 cm away from the device',
        'Water or wet environment: move the patient to a dry surface before use if possible',
        'Pregnant patients: AED use is safe — the shock does not reach the fetus',
        'Hairy chest: some AEDs include a razor — shave briefly for better pad contact',
        'Multiple rescuers: one operates the AED, the other continues CPR until analysis is prompted',
        'Children 1–8 years: use pediatric pads/key if available; if unavailable, adult pads are acceptable',
        'Infants under 1 year: AED use is not recommended as a first line — prioritise CPR and advanced care',
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4 — MORE
// Special cases, two-rescuer, recovery position, when to stop, pediatric
// ═══════════════════════════════════════════════════════════════════════════════

class _MoreTab extends StatelessWidget {
  const _MoreTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        top:    AppSpacing.md,
        left:   AppSpacing.md,
        right:  AppSpacing.md,
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            icon:  Icons.stop_circle_outlined,
            label: 'When to stop CPR',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _WhenToStopCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(
            icon:  Icons.airline_seat_flat_rounded,
            label: 'Recovery position',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RecoveryPositionCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(
            icon:  Icons.people_rounded,
            label: 'Two-rescuer CPR',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _TwoRescuerCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(
            icon:  Icons.child_care_rounded,
            label: 'Pediatric CPR',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _PediatricCprCard(),
          const SizedBox(height: AppSpacing.xl),

          _SectionLabel(
            icon:  Icons.warning_amber_rounded,
            label: 'Critical reminders',
          ),
          const SizedBox(height: AppSpacing.sm),
          const _CriticalRemindersCard(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// WHEN TO STOP CPR
// ═══════════════════════════════════════════════════════════════════════════════

class _WhenToStopCard extends StatelessWidget {
  const _WhenToStopCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: AppDecorations.primaryCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      size: AppSpacing.iconSm, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Continue CPR while any of these apply',
                    style: AppTypography.subheading(color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const _BulletList(items: [
                'Emergency services have not yet arrived',
                'No AED available or AED is still analysing',
                'Person has not shown clear signs of life (normal breathing, purposeful movement)',
                'You are physically able to continue',
              ]),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: AppDecorations.emergencyCard(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stop_circle_outlined,
                      size: AppSpacing.iconSm, color: AppColors.emergency),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'It is appropriate to stop when',
                    style: AppTypography.subheading(
                        color: AppColors.emergency),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const _BulletList(
                bulletColor: AppColors.emergency,
                items: [
                  'A trained medical professional takes over and instructs you to stop',
                  'The person begins breathing normally on their own',
                  'An AED advises no shock and the person shows clear signs of life',
                  'The scene becomes immediately unsafe and continuing poses a direct risk to you',
                  'You are completely exhausted and no other rescuer is available',
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: AppDecorations.tintedCard(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.favorite_border_rounded,
                  size: AppSpacing.iconSm, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'There is no legal obligation to continue indefinitely. '
                      'If you have given CPR in good faith, you have done the right thing regardless of outcome.',
                  style: AppTypography.body(size: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// RECOVERY POSITION
// ═══════════════════════════════════════════════════════════════════════════════

class _RecoveryPositionCard extends StatelessWidget {
  const _RecoveryPositionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.successCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:        AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
            ),
            child: Text(
              'Use the recovery position when the person is breathing normally '
                  'but remains unconscious. It keeps the airway open and prevents '
                  'choking if they vomit.',
              style: AppTypography.body(size: 13, color: AppColors.success),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('How to position them', style: AppTypography.subheading()),
          const SizedBox(height: AppSpacing.sm),
          _NumberedList(
            color: AppColors.success,
            items: const [
              'Kneel beside the person and straighten both legs.',
              'Arm nearest to you at a right angle to the body, elbow bent, palm facing up.',
              'Bring the far arm across the chest, hold the back of their hand against their near cheek.',
              'Pull up the far knee so the foot is flat on the ground.',
              'Pull on the bent knee to roll them towards you onto their side.',
              'Adjust the top leg so hip and knee are at right angles.',
              'Tilt the head back slightly — mouth slightly downward to allow drainage.',
              'Call 112 if not already done. Monitor breathing continuously.',
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.tintedCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: AppSpacing.iconSm, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'If spinal injury is suspected, do not move the person unless '
                        'there is an immediate life threat. Maintain the airway without rotating the spine.',
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

// ═══════════════════════════════════════════════════════════════════════════════
// TWO-RESCUER CPR
// ═══════════════════════════════════════════════════════════════════════════════

class _TwoRescuerCard extends StatelessWidget {
  const _TwoRescuerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:        AppColors.primaryAlt.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
            ),
            child: Text(
              'Two rescuers significantly improve CPR quality. '
                  'One manages compressions, one manages the airway. '
                  'Switch roles every 2 minutes to prevent fatigue.',
              style: AppTypography.body(
                  size: 13, color: AppColors.primaryAlt),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Role cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: AppDecorations.primaryCard(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite_rounded,
                              size: AppSpacing.iconSm,
                              color: AppColors.primary),
                          const SizedBox(width: AppSpacing.xs),
                          Text('Rescuer 1',
                              style: AppTypography.label(
                                  color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Compressions',
                          style: AppTypography.bodyMedium(size: 13)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'At the side. 30 compressions at 100–120 BPM. Count aloud.',
                        style: AppTypography.body(size: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primaryAlt.withValues(alpha: 0.08),
                    borderRadius:
                    BorderRadius.circular(AppSpacing.cardRadius),
                    border: Border.all(
                        color: AppColors.primaryAlt.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.air_rounded,
                              size: AppSpacing.iconSm,
                              color: AppColors.primaryAlt),
                          const SizedBox(width: AppSpacing.xs),
                          Text('Rescuer 2',
                              style: AppTypography.label(
                                  color: AppColors.primaryAlt)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text('Airway & breaths',
                          style: AppTypography.bodyMedium(size: 13)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        'At the head. Head-tilt chin-lift. 2 breaths after every 30 compressions.',
                        style: AppTypography.body(size: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          Text('Switching roles', style: AppTypography.subheading()),
          const SizedBox(height: AppSpacing.sm),
          _NumberedList(
            color: AppColors.primaryAlt,
            items: const [
              'Switch every 2 minutes — at the ventilation pause after 30 compressions.',
              'Rescuer 2 calls "switch" as they deliver the 2nd breath.',
              'Rescuer 1 moves to the head; Rescuer 2 takes the chest position.',
              'Compressions must resume within 10 seconds of the switch.',
              'A third person can operate the AED without interrupting the CPR cycle.',
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          Text('With a bag-valve mask (BVM)', style: AppTypography.subheading()),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(items: [
            'Use both hands for the EC-clamp mask seal while a second person squeezes the bag',
            'Squeeze only until visible chest rise — over-inflation causes regurgitation',
            'If oxygen is available, attach at 10–15 L/min to the reservoir bag',
            'Do not ventilate during active compressions',
          ]),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppDecorations.tintedCard(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: AppSpacing.iconSm, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Healthcare providers using two-rescuer CPR on a child '
                        'should switch to 15:2 ratio (15 compressions, 2 breaths).',
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

// ═══════════════════════════════════════════════════════════════════════════════
// PEDIATRIC CPR
// ═══════════════════════════════════════════════════════════════════════════════

class _PediatricCprCard extends StatelessWidget {
  const _PediatricCprCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width:      double.infinity,
      padding:    const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:        AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
            ),
            child: Text(
              'Pediatric CPR differs from adult CPR in depth, hand technique, '
                  'and rescue breath volume. Use the Pediatric scenario on the glove '
                  'for adjusted feedback thresholds.',
              style: AppTypography.body(
                  size: 13, color: AppColors.warning),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(flex: 3, child: SizedBox()),
              Expanded(
                flex: 3,
                child: Text('Adult',
                    style: AppTypography.label(
                        size: 11, color: AppColors.textDisabled)),
              ),
              Expanded(
                flex: 3,
                child: Text('Pediatric',
                    style: AppTypography.label(
                        size: 11, color: AppColors.warning)),
              ),
            ],
          ),
          const Divider(height: AppSpacing.md, color: AppColors.divider),
          const _PediatricSpecRow(
              label: 'Compression depth',
              adult: '5–6 cm',
              pediatric: '4–5 cm',
              highlight: true),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          const _PediatricSpecRow(
              label: 'Compression rate',
              adult: '100–120 / min',
              pediatric: '100–120 / min'),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          const _PediatricSpecRow(
              label: 'Hand technique',
              adult: 'Two hands, heel',
              pediatric: 'Two fingers (infant)\nor one hand (child)',
              highlight: true),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          const _PediatricSpecRow(
              label: 'Comp : breaths',
              adult: '30 : 2',
              pediatric: '30 : 2 (single)\n15 : 2 (two rescuers)',
              highlight: true),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          const _PediatricSpecRow(
              label: 'Breath volume',
              adult: 'Chest rise',
              pediatric: 'Gentle puff only',
              highlight: true),
          const Divider(height: AppSpacing.lg, color: AppColors.divider),
          const _PediatricSpecRow(
              label: 'AED pads',
              adult: 'Chest and side',
              pediatric: 'Paediatric pads\n(front/back infants)',
              highlight: true),
          const SizedBox(height: AppSpacing.md),
          Text('Key reminders', style: AppTypography.label()),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(
            bulletColor: AppColors.warning,
            items: [
              'Infants under 1 year: two fingers, centre of chest just below the nipple line',
              'Children 1–8 years: one or two hands depending on child\'s size',
              'Never tilt an infant\'s head back too far — use a neutral sniffing position',
              'Pediatric arrest is usually respiratory, not cardiac — ventilations are especially important',
              'Pulse check: brachial artery (inner upper arm) for infants, carotid for children',
            ],
          ),
        ],
      ),
    );
  }
}

class _PediatricSpecRow extends StatelessWidget {
  final String label;
  final String adult;
  final String pediatric;
  final bool   highlight;

  const _PediatricSpecRow({
    required this.label,
    required this.adult,
    required this.pediatric,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            flex: 3,
            child: Text(label, style: AppTypography.bodyMedium(size: 13))),
        Expanded(
          flex: 3,
          child: Text(adult,
              style: AppTypography.body(
                  size: 13, color: AppColors.textSecondary)),
        ),
        Expanded(
          flex: 3,
          child: Text(
            pediatric,
            style: AppTypography.bodyMedium(
              size:  13,
              color: highlight ? AppColors.warning : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CRITICAL REMINDERS
// ═══════════════════════════════════════════════════════════════════════════════

class _CriticalRemindersCard extends StatelessWidget {
  const _CriticalRemindersCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.emergencyCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.emergency, size: AppSpacing.iconMd),
              const SizedBox(width: AppSpacing.sm),
              Text('Critical reminders',
                  style: AppTypography.subheading(
                      color: AppColors.emergency)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _BulletList(
            bulletColor: AppColors.emergency,
            items: [
              'Continue CPR until emergency services take over or person shows clear signs of life',
              'Minimise pauses — keep interruptions under 10 seconds',
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
// SHARED — Section label
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String   label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.label(
            size:  13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED — Bullet list
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
      children: items
          .map((item) => _BulletItem(text: item, color: bulletColor))
          .toList(),
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
              width:  AppSpacing.xs + AppSpacing.xxs,
              height: AppSpacing.xs + AppSpacing.xxs,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppTypography.body())),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED — Numbered list
// ═══════════════════════════════════════════════════════════════════════════════

class _NumberedList extends StatelessWidget {
  final List<String> items;
  final Color        color;

  const _NumberedList({
    required this.items,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width:  AppSpacing.iconSm,
                  height: AppSpacing.iconSm,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: AppTypography.badge(
                          size: 10, color: AppColors.textOnDark),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                    child: Text(items[i], style: AppTypography.body())),
              ],
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// FIND AED CTA
// ═══════════════════════════════════════════════════════════════════════════════

class _FindAedCta extends StatelessWidget {
  final Function(int)? onTabTapped;
  const _FindAedCta({this.onTabTapped});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTabTapped != null ? () => onTabTapped!(1) : null,
      child: Container(
        width:      double.infinity,
        padding:    const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: AppDecorations.primaryGradientCard(),
        child: Row(
          children: [
            Container(
              width:  AppSpacing.iconXl + AppSpacing.sm,
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
                  Text('Find nearest AED',
                      style: AppTypography.subheading(
                          color: AppColors.textOnDark)),
                  Text(
                    'Open the AED map and locate\nthe closest defibrillator to you now',
                    style: AppTypography.body(
                      size:  13,
                      color: AppColors.textOnDark.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textOnDark, size: AppSpacing.iconMd),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QUIZ CTA
// ═══════════════════════════════════════════════════════════════════════════════

class _QuizCta extends StatelessWidget {
  const _QuizCta();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(const QuizScreen()),
      child: Container(
        width:      double.infinity,
        padding:    const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: AppDecorations.card(),
        child: Row(
          children: [
            Container(
              width:  AppSpacing.iconXl + AppSpacing.sm,
              height: AppSpacing.iconXl + AppSpacing.sm,
              decoration: AppDecorations.iconCircle(
                bg: AppColors.primaryLight,
              ),
              child: const Icon(
                Icons.quiz_outlined,
                color: AppColors.primary,
                size:  AppSpacing.iconMd,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Test your CPR knowledge',
                      style: AppTypography.subheading()),
                  Text(
                    'Quick quiz to check your understanding',
                    style: AppTypography.body(
                        size: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: AppSpacing.iconMd),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTERS (unchanged from original)
// ═══════════════════════════════════════════════════════════════════════════════

class _ChestSchematicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

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

    final sternumPaint = Paint()
      ..color = AppColors.primaryAlt.withValues(alpha: 0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx, size.height * 0.08),
      Offset(cx, size.height * 0.85),
      sternumPaint,
    );

    final ribPaint = Paint()
      ..color = AppColors.primaryAlt.withValues(alpha: 0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 3; i++) {
      final y    = size.height * (0.25 + i * 0.18);
      final halfW = size.width * 0.22;

      final leftPath = Path()
        ..moveTo(cx - AppSpacing.xs, y)
        ..quadraticBezierTo(cx - halfW * 0.5, y - 12, cx - halfW, y + 8);
      canvas.drawPath(leftPath, ribPaint);

      final rightPath = Path()
        ..moveTo(cx + AppSpacing.xs, y)
        ..quadraticBezierTo(cx + halfW * 0.5, y - 12, cx + halfW, y + 8);
      canvas.drawPath(rightPath, ribPaint);
    }

    final targetY   = size.height * 0.58;
    final haloPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, targetY), 30, haloPaint);

    final handPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, targetY), width: 44, height: 26),
      handPaint,
    );

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

    void drawLabel(String text, Offset offset) {
      final tp = TextPainter(
        text: TextSpan(
          text:  text,
          style: const TextStyle(
            fontSize:   10,
            fontWeight: FontWeight.w600,
            color:      AppColors.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(offset.dx, offset.dy - tp.height / 2));
    }

    final arrowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx + 24, targetY),
      Offset(cx + size.width * 0.18, targetY),
      arrowPaint,
    );
    drawLabel('Place hands here',
        Offset(cx + size.width * 0.19, targetY));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AedSchematicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

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

    final collarPaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx - size.width * 0.22, size.height * 0.14),
      Offset(cx + size.width * 0.22, size.height * 0.14),
      collarPaint,
    );

    _drawPad(canvas,
        label:  '1',
        center: Offset(cx + size.width * 0.14, size.height * 0.24),
        color:  AppColors.warning);
    _drawPad(canvas,
        label:  '2',
        center: Offset(cx - size.width * 0.19, size.height * 0.58),
        color:  AppColors.warning);

    final linePaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final p1 = Offset(cx + size.width * 0.14, size.height * 0.24);
    final p2 = Offset(cx - size.width * 0.19, size.height * 0.58);
    _drawDashedLine(canvas, p1, p2, linePaint);
  }

  void _drawPad(
      Canvas canvas, {
        required String label,
        required Offset center,
        required Color  color,
      }) {
    final padPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 44, height: 32),
        const Radius.circular(AppSpacing.cardRadiusSm),
      ),
      padPaint,
    );
    final tp = TextPainter(
      text: TextSpan(
        text:  label,
        style: const TextStyle(
          fontSize:   13,
          fontWeight: FontWeight.w800,
          color:      AppColors.textOnDark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dx    = p2.dx - p1.dx;
    final dy    = p2.dy - p1.dy;
    final dist  = math.sqrt(dx * dx + dy * dy);
    const dash  = 6.0;
    const gap   = 4.0;
    final nx    = dx / dist;
    final ny    = dy / dist;
    double t    = 0;
    while (t < dist) {
      canvas.drawLine(
        Offset(p1.dx + nx * t, p1.dy + ny * t),
        Offset(
          p1.dx + nx * (t + dash).clamp(0, dist),
          p1.dy + ny * (t + dash).clamp(0, dist),
        ),
        paint,
      );
      t += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}