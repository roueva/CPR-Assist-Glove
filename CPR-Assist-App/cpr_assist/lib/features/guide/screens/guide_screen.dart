import 'dart:math' as math;

import 'package:cpr_assist/features/guide/screens/quiz_screen.dart';
import 'package:flutter/material.dart';
import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// guide_screen.dart
//
// Hub-and-detail CPR reference. No login required.
//
// Structure:
//   GuideScreen                  ← hub with chain-of-survival banner + 5 cards
//   _GuideDetailScreen           ← reusable pushed-screen shell
//   _CompressionsDetailScreen    ← hand placement · rate · depth · 30:2 · breaths
//   _AedDetailScreen             ← what it is · pad placement · 6-step use
//   _QuickStepsDetailScreen      ← 8-step sequential checklist
//   _PediatricDetailScreen       ← photo pair + comparison table
//   _StopRecoveryDetailScreen    ← stop criteria + recovery position
//
// Shared widgets (reused across detail screens):
//   _PhotoCard          ← image with gradient caption overlay
//   _SectionCard        ← white card with title row + children
//   _InfoBanner         ← blue info row
//   _WarnBanner         ← orange warning row
//   _SuccessBanner      ← green note row
//   _BulletList         ← dot bullets
//   _StepRailList       ← numbered step rail (used for CPR steps + AED steps)
//   _RateGaugeBar       ← 100–120 /min gauge
//   _DepthGaugeBar      ← 5–6 cm depth gauge
//   _RatioBox           ← 30 : 2 large-number display
//   _PadPlacementSVG    ← torso + pad schematic
//   _PediatricTable     ← adult vs infant vs child comparison
//   _WhenToStopCard     ← keep-going / stop-when split card
// ─────────────────────────────────────────────────────────────────────────────

// ═══════════════════════════════════════════════════════════════════════════════
// GuideScreen — hub
// ═══════════════════════════════════════════════════════════════════════════════

class GuideScreen extends StatelessWidget {
  final Function(int)? onTabTapped;
  const GuideScreen({super.key, this.onTabTapped});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              bottomPad + AppSpacing.xxl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Chain of survival banner ──────────────────────────────
                _ChainBanner(
                  onTap: () => context.push(const _ChainOfSurvivalScreen()),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Hero card: Compressions & breathing ───────────────────
                _HubCard(
                  assetPath: 'assets/icons/guide/hub_compressions.png',
                  placeholderIcon: Icons.favorite_rounded,
                  placeholderColor: AppColors.primary,
                  overlayColor: AppColors.primary,
                  title: 'Compressions & breathing',
                  heroHeight: AppSpacing.guideHubHeroH,
                  onTap: () => context.push(const _CompressionsDetailScreen()),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Row: AED + Quick steps ────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _HubCard(
                        assetPath: 'assets/icons/guide/hub_aed.png',
                        placeholderIcon: Icons.bolt_rounded,
                        placeholderColor: AppColors.warning,
                        overlayColor: const Color(0xFF5A2800),
                        title: 'AED',
                        heroHeight: AppSpacing.guideHubSmH,
                        imageScale: 0.9,
                        imageAlignment: Alignment.center,
                        onTap: () => context.push(const _AedDetailScreen()),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _HubCard(
                        assetPath: 'assets/icons/guide/hub_steps.png',
                        placeholderIcon: Icons.format_list_numbered_rounded,
                        placeholderColor: AppColors.primaryAlt,
                        overlayColor: AppColors.primary,
                        title: 'Quick steps',
                        heroHeight: AppSpacing.guideHubSmH,
                        onTap: () =>
                            context.push(const _QuickStepsDetailScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Row: Pediatric + Stop & Recovery ─────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _HubCard(
                        assetPath: 'assets/icons/guide/hub_pediatric.png',
                        placeholderIcon: Icons.child_care_rounded,
                        placeholderColor: AppColors.pediatric,
                        overlayColor: const Color(0xFF003D50),
                        title: 'Special situations',
                        heroHeight: AppSpacing.guideHubSmH,
                        onTap: () =>
                            context.push(const _PediatricDetailScreen()),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _HubCard(
                        assetPath: 'assets/icons/guide/hub_recovery.png',
                        placeholderIcon: Icons.airline_seat_flat_rounded,
                        placeholderColor: AppColors.success,
                        overlayColor: const Color(0xFF0A2D10),
                        title: 'Stop & recovery',
                        heroHeight: AppSpacing.guideHubSmH,
                        onTap: () =>
                            context.push(const _StopRecoveryDetailScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.sm),

                // ── Knowledge quiz ────────────────────────────────────────
                _HubCard(
                  assetPath: 'assets/icons/guide/hub_quiz.png',
                  placeholderIcon: Icons.quiz_rounded,
                  placeholderColor: AppColors.primaryAlt,
                  overlayColor: AppColors.primary,
                  title: 'Test your knowledge',
                  heroHeight: AppSpacing.guideHubSmH,
                  onTap: () => context.push(const QuizScreen()),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainOfSurvivalScreen extends StatelessWidget {
  const _ChainOfSurvivalScreen();

  @override
  Widget build(BuildContext context) {
    return _GuideDetailScreen(
      title: 'Chain of survival',
      accentColor: AppColors.primary,
      children: const [
        _ChainRow(),
        SizedBox(height: AppSpacing.sm),
        _InfoBanner(
          text: 'Every minute without CPR reduces survival by ~10%...',
        ),
        SizedBox(height: AppSpacing.sm),
        _ChainLinkCard(
          number: 1,
          color: AppColors.warning,
          icon: Icons.phone_in_talk_rounded,
          title: 'Prevention & early recognition',
          goal: 'Prevent or detect cardiac arrest early',
          timeTarget: 'Before and within the first 1–2 minutes',
          points: [
            'Learn CPR and keep your skills current',
            'Recognise warning signs: chest pain, breathlessness, collapse',
            'If unresponsive and not breathing normally — treat as cardiac arrest',
            'Call 112 immediately, put on speakerphone, start CPR',
            'Delegate: "You — call 112. You — get the AED"',
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        _ChainLinkCard(
          number: 2,
          color: AppColors.primary,
          icon: Icons.favorite_rounded,
          title: 'Early CPR & defibrillation',
          goal: 'Preserve brain & restart the heart',
          timeTarget: 'Start within 2–3 minutes of collapse',
          points: [
            '30 chest compressions at 100–120 /min, 5–6 cm deep',
            'Full chest recoil between compressions',
            '2 rescue breaths after every 30 compressions',
            'Use AED as soon as it arrives — do not pause CPR to wait for it',
            'Do not pause CPR until the AED is attached and ready to analyse',
            'Each minute of delay to defibrillation reduces survival ~10%',
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        _ChainLinkCard(
          number: 3,
          color: AppColors.emergency,
          icon: Icons.local_hospital_rounded,
          title: 'Advanced & post resuscitation care',
          goal: 'Optimise brain & heart function',
          timeTarget: 'From EMS arrival onward',
          points: [
            'EMS takes over with advanced airway and IV medications',
            'Targeted temperature management may be used after ROSC',
            'Coronary angiography if cardiac cause suspected',
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        _ChainLinkCard(
          number: 4,
          color: AppColors.success,
          icon: Icons.self_improvement_rounded,
          title: 'Survival & recovery',
          goal: 'Restore quality of life',
          timeTarget: 'Hours to months after the event',
          points: [
            'Neurological and cardiac rehabilitation begins in ICU',
            'Cognitive, physical, and emotional recovery may take months',
            'Psychological support for both survivor and bystander rescuers',
            'Many survivors return to normal daily activities with proper follow-up',
          ],
        ),
        SizedBox(height: AppSpacing.sm),
        _InfoBanner(
          text: 'Source: European Resuscitation Council Guidelines 2025',
          icon: Icons.menu_book_outlined,
        ),
      ],
    );
  }
}

class _ChainLinkCard extends StatelessWidget {
  final int number;
  final Color color;
  final IconData icon;
  final String title;
  final String goal;
  final String timeTarget;
  final List<String> points;

  const _ChainLinkCard({
    required this.number,
    required this.color,
    required this.icon,
    required this.title,
    required this.goal,
    required this.timeTarget,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSpacing.iconBoxSize,
                height: AppSpacing.iconBoxSize,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: AppTypography.heading(size: 15, color: color),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTypography.bodyMedium(size: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Icon(Icons.flag_outlined, size: 11, color: color),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(goal,
                              style: AppTypography.label(size: 11, color: color)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 11, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xxs),
              Text(timeTarget,
                  style: AppTypography.body(size: 11, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _BulletList(color: color, items: points),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChainBanner — chain of survival photo banner at the top of the hub
// ─────────────────────────────────────────────────────────────────────────────

class _ChainBanner extends StatelessWidget {
  final VoidCallback? onTap;
  const _ChainBanner({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(                                          // ← NEW
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 12,
                spreadRadius: 0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Stack(
          children: [
            SizedBox(
              height: AppSpacing.guideChainBannerH,
              width: double.infinity,
              child: Image.asset(
                'assets/icons/guide/chain_of_survival.png',
                fit: BoxFit.contain,
                alignment: Alignment.center,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.primaryLight,
                  alignment: Alignment.center,
                  child: const Icon(Icons.link_rounded,
                      size: AppSpacing.iconXl, color: AppColors.primary),
                ),
              ),
            ),
            // Source credit — bottom right
            Positioned(
              right: AppSpacing.xs,
              bottom: AppSpacing.xs,
              child: Text(
                '© ERC Guidelines 2025',
                style: AppTypography.badge(
                    size: 6, color: AppColors.textSecondary.withValues(alpha: 0.6)),
              ),
            ),
          ],
            ),
          ),
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HubCard — photo card with gradient overlay, title, subtitle, chevron
// ─────────────────────────────────────────────────────────────────────────────

class _HubCard extends StatelessWidget {
  final String assetPath;
  final IconData placeholderIcon;
  final Color placeholderColor;
  final Color overlayColor;
  final String title;
  final String? subtitle;
  final double heroHeight;
  final double imageScale;
  final Alignment imageAlignment;
  final VoidCallback onTap;

  const _HubCard({
    required this.assetPath,
    required this.placeholderIcon,
    required this.placeholderColor,
    required this.overlayColor,
    required this.title,
    this.subtitle,
    required this.heroHeight,
    this.imageScale = 1.0,
    this.imageAlignment = Alignment.center,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Container(                                          // ← NEW outer container
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),   // ~15% black
                blurRadius: 8,
                spreadRadius: 0,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(                                        // ← same as before
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Stack(
          children: [
            // Photo
              SizedBox(
              height: heroHeight,
              width: double.infinity,
              child: ColoredBox(
                color: AppColors.white,
                child: Transform.scale(
                  scale: imageScale,
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    alignment: imageAlignment,
                    errorBuilder: (_, __, ___) => Container(
                      color: placeholderColor.withValues(alpha: 0.1),
                      alignment: Alignment.center,
                      child: Icon(placeholderIcon,
                          size: AppSpacing.iconXl,
                          color: placeholderColor.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),
            // Gradient overlay — dark at bottom
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      overlayColor.withValues(alpha: 0.82),
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
            ),
            // Text content
              Positioned(
                left: AppSpacing.sm + AppSpacing.xs,
                right: AppSpacing.xl,
                bottom: subtitle != null ? AppSpacing.sm + AppSpacing.xs : AppSpacing.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyMedium(
                          size: 14, color: AppColors.textOnDark),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: AppTypography.body(
                            size: 11,
                            color: AppColors.textOnDark.withValues(alpha: 0.82)),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
            // Chevron
            Positioned(
              right: AppSpacing.sm,
              top: AppSpacing.sm,
              child: Container(
                width: AppSpacing.iconBoxSize - AppSpacing.xxs,
                height: AppSpacing.iconBoxSize - AppSpacing.xxs,
                decoration: BoxDecoration(
                  color: AppColors.textOnDark.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  size: AppSpacing.iconMd,
                  color: AppColors.textOnDark,
                ),
              ),
            ),
          ],
            ),
          ),
        ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// _GuideDetailScreen — reusable pushed-screen shell
// ═══════════════════════════════════════════════════════════════════════════════

class _GuideDetailScreen extends StatelessWidget {
  final String title;
  final Color accentColor;
  final List<Widget> children;

  const _GuideDetailScreen({
    required this.title,
    required this.accentColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.shadowDefault,
        toolbarHeight: AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary, size: AppSpacing.iconMd),
          onPressed: () => context.pop(),
        ),
        title: Text(title, style: AppTypography.heading(size: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppSpacing.xxxs),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: AppSpacing.xxxs,
              width: AppSpacing.guideAccentBarW,
              margin: const EdgeInsets.only(
                  left: AppSpacing.xxl + AppSpacing.xxl,
                  bottom: AppSpacing.xxs),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius:
                BorderRadius.circular(AppSpacing.chipRadius),
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: bottomPad + AppSpacing.xxl,
        ),
        children: children,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAIL SCREEN 1 — Compressions & breathing
// ═══════════════════════════════════════════════════════════════════════════════

class _CompressionsDetailScreen extends StatelessWidget {
  const _CompressionsDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _GuideDetailScreen(
      title: 'Compressions & breathing',
      accentColor: AppColors.primary,
      children: const [
        // ── Hand placement photo + notes ──────────────────────────────────
        _PhotoCard(
          assetPath: 'assets/icons/guide/detail_hand_placement.png',
          caption: 'Heel of hand · lower sternum · arms locked straight',
          tint: AppColors.primary,
        ),
        SizedBox(height: AppSpacing.sm),
        _SectionCard(
          titleIcon: Icons.pan_tool_rounded,
          titleIconColor: AppColors.primary,
          title: 'Hand placement',
          child: Column(
            children: [
              _BulletRow(
                color: AppColors.primary,
                title: 'Dominant hand heel on lower half of sternum',
                body: 'Not on ribs or the xiphoid process',
              ),
              SizedBox(height: AppSpacing.sm),
              _BulletRow(
                color: AppColors.primary,
                title: 'Second hand on top, fingers interlaced and raised',
              ),
              SizedBox(height: AppSpacing.sm),
              _BulletRow(
                color: AppColors.primary,
                title: 'Arms straight, shoulders over hands, use body weight',
              ),
              SizedBox(height: AppSpacing.sm),
              _WarnBanner(
                text:
                'Hands on ribs or too low risk fracture — stay on the sternum',
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),

        // ── Rate gauge ────────────────────────────────────────────────────
        _SectionCard(
          titleIcon: Icons.speed_rounded,
          titleIconColor: AppColors.primary,
          title: 'Compression rate',
          child: Column(
            children: [
              _RateGaugeBar(),
              SizedBox(height: AppSpacing.sm),
              _InfoBanner(
                text:
                '"Stayin\' Alive" rhythm is 103 BPM — or count aloud: 1-and-2-and-3…',
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),

        // ── Depth gauge ───────────────────────────────────────────────────
        _SectionCard(
          titleIcon: Icons.straighten_rounded,
          titleIconColor: AppColors.primary,
          title: 'Compression depth',
          child: Column(
            children: [
              _DepthGaugeBar(),
              SizedBox(height: AppSpacing.sm),
              _BulletRow(
                color: AppColors.primary,
                title: 'Full chest recoil between compressions',
                body: 'Do not lean on the chest between compressions',
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),

        // ── 30:2 + rescue breath ──────────────────────────────────────────
        _SectionCard(
          titleIcon: Icons.refresh_rounded,
          titleIconColor: AppColors.primary,
          title: '30 : 2 cycle',
          child: Column(
            children: [
              _RatioBox(),
              SizedBox(height: AppSpacing.md),
              _PhotoCard(
                assetPath: 'assets/guide/detail_rescue_breath.jpg',
                caption: 'Head tilt · chin lift · pinch nose · seal mouth',
                tint: AppColors.primaryAlt,
              ),
              SizedBox(height: AppSpacing.sm),
              _BulletRow(
                color: AppColors.primaryAlt,
                title: 'Head tilt, chin lift — open airway before each breath',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.primaryAlt,
                title: 'Pinch nose · seal lips · ~1 second breath',
                body: 'Watch for visible chest rise — do not over-inflate',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.primaryAlt,
                title: 'Both breaths in under 5 seconds total',
              ),
              SizedBox(height: AppSpacing.sm),
              _InfoBanner(
                text:
                'Untrained or reluctant? Skip breaths — continuous compressions still save lives',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAIL SCREEN 2 — AED
// ═══════════════════════════════════════════════════════════════════════════════

class _AedDetailScreen extends StatelessWidget {
  const _AedDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _GuideDetailScreen(
      title: 'AED',
      accentColor: AppColors.warning,
      children: const [
        // ── What it looks like ────────────────────────────────────────────
        _PhotoCard(
          assetPath: 'assets/guide/detail_aed_cabinet.jpg',
          caption: 'Bright yellow or green cabinet — often on walls in public spaces',
          tint: AppColors.warning,
        ),
        SizedBox(height: AppSpacing.sm),
        _SectionCard(
          titleIcon: Icons.bolt_rounded,
          titleIconColor: AppColors.warning,
          title: 'What is an AED?',
          child: Column(
            children: [
              _BulletRow(
                color: AppColors.warning,
                title: 'Analyses heart rhythm automatically',
                body: 'Shocks only if a shockable rhythm is detected',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.warning,
                title: 'Cannot harm a healthy heart — safe for anyone',
              ),
              SizedBox(height: AppSpacing.sm),
              _WarnBanner(
                text:
                'Use this app\'s AED map to find the nearest device before you need it',
                icon: Icons.map_outlined,
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),

        // ── Pad placement ─────────────────────────────────────────────────
        _SectionCard(
          titleIcon: Icons.dashboard_outlined,
          titleIconColor: AppColors.warning,
          title: 'Pad placement',
          child: Column(
            children: [
              _PadPlacementSVG(),
              SizedBox(height: AppSpacing.sm),
              _BulletRow(
                color: AppColors.warning,
                title: 'Pad ①  below right collarbone, right of sternum',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.warning,
                title: 'Pad ②  left side, below the armpit on the ribcage',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.warning,
                title: 'Dry the chest first — moisture cuts effectiveness',
              ),
              SizedBox(height: AppSpacing.sm),
              _WarnBanner(
                text:
                'Remove pacemaker patches, bra underwires, and medication patches before placing pads',
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.sm),

        // ── AED usage steps ───────────────────────────────────────────────
        _SectionCard(
          titleIcon: Icons.list_alt_rounded,
          titleIconColor: AppColors.warning,
          title: 'How to use it — follow voice prompts',
          child: _StepRailList(steps: [
            _StepData(
              color: AppColors.success,
              title: 'Power on',
              body: 'Open the case — most power on automatically',
            ),
            _StepData(
              color: AppColors.primary,
              title: 'Expose & prepare chest',
              body: 'Remove clothing, dry skin, remove patches',
            ),
            _StepData(
              color: AppColors.warning,
              title: 'Attach pads as shown',
              body: 'Press firmly for full skin contact',
            ),
            _StepData(
              color: AppColors.emergency,
              title: 'Stand clear — analysis',
              body: 'Shout "Stand clear" · nobody touches the patient',
            ),
            _StepData(
              color: AppColors.emergency,
              title: 'Deliver shock if advised',
              body: 'Press the flashing button when prompted',
            ),
            _StepData(
              color: AppColors.primary,
              title: 'Immediately resume CPR',
              body: 'Within 10 seconds of the shock',
            ),
          ]),
        ),
        SizedBox(height: AppSpacing.sm),

        // ── Special situations ────────────────────────────────────────────
        _SectionCard(
          titleIcon: Icons.warning_amber_rounded,
          titleIconColor: AppColors.warning,
          title: 'Special situations',
          child: _BulletList(items: [
            'Pacemaker / ICD: place pads at least 8 cm from the device',
            'Wet skin: dry first — move to a dry surface if possible',
            'Pregnant: AED is safe — shock does not reach the fetus',
            'Hairy chest: shave briefly if a razor is included',
            'Children 1–8 yr: pediatric pads if available. Infants <1 yr: prioritise CPR.',
          ]),
        ),
        SizedBox(height: AppSpacing.sm),

        _InfoBanner(
          text:
          'Keep pads on and AED switched on throughout — it will re-analyse every 2 minutes',
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAIL SCREEN 3 — Quick steps
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickStepsDetailScreen extends StatelessWidget {
  const _QuickStepsDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _GuideDetailScreen(
      title: 'Quick steps',
      accentColor: AppColors.primary,
      children: const [
        _SectionCard(
          titleIcon: Icons.format_list_numbered_rounded,
          titleIconColor: AppColors.primary,
          title: 'What to do — in order',
          child: _StepRailList(steps: [
            _StepData(
              color: AppColors.textSecondary,
              title: 'Check scene safety',
              body: 'Traffic, electricity, fire — approach only if safe',
            ),
            _StepData(
              color: AppColors.warning,
              title: 'Check responsiveness',
              body: 'Tap shoulders · shout · look for normal breathing',
            ),
            _StepData(
              color: AppColors.emergency,
              title: 'Call 112 immediately',
              body: 'Call now or tell someone: "You — call 112". Stay on the line.',
              urgent: true,
            ),
            _StepData(
              color: AppColors.success,
              title: 'Send for an AED',
              body: 'Point at someone: "You — get the AED"',
            ),
            _StepData(
              color: AppColors.primary,
              title: '30 compressions',
              body: 'Position hands first · 5–6 cm · 100–120 /min',
            ),
            _StepData(
              color: AppColors.primaryAlt,
              title: '2 rescue breaths',
              body: 'Head tilt, chin lift · 1 s each · chest rise',
            ),
            _StepData(
              color: AppColors.primary,
              title: 'Continue 30 : 2',
              body: 'Until AED ready or EMS arrives',
            ),
            _StepData(
              color: AppColors.warning,
              title: 'AED when available',
              body: 'Don\'t stop CPR to wait for it',
            ),
          ]),
        ),
        SizedBox(height: AppSpacing.sm),
        _InfoBanner(
          text: 'Swap rescuers every 2 minutes to maintain compression quality',
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAIL SCREEN 4 — Pediatric
// ═══════════════════════════════════════════════════════════════════════════════

class _PediatricDetailScreen extends StatelessWidget {
  const _PediatricDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _GuideDetailScreen(
      title: 'Pediatric',
      accentColor: AppColors.pediatric,
      children: [
        // Two photos side by side
        Row(
          children: [
            Expanded(
              child: _LabelledPhoto(
                assetPath: 'assets/guide/detail_infant_cpr.jpg',
                label: 'Infant — 2 fingers',
                tint: AppColors.pediatric,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _LabelledPhoto(
                assetPath: 'assets/guide/detail_child_cpr.jpg',
                label: 'Child — 1–2 hands',
                tint: AppColors.pediatric,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.pediatricLight,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Text(
            'Same principles as adult CPR — only these specifics change',
            style:
            AppTypography.body(size: 13, color: AppColors.pediatric),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _SectionCard(
          titleIcon: Icons.table_chart_outlined,
          titleIconColor: AppColors.pediatric,
          title: 'Adult vs pediatric comparison',
          child: _PediatricTable(),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _InfoBanner(
          text:
          'No pediatric pads available? Adult pads are acceptable — better than no shock',
          accentColor: AppColors.pediatric,
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DETAIL SCREEN 5 — Stop & recovery
// ═══════════════════════════════════════════════════════════════════════════════

class _StopRecoveryDetailScreen extends StatelessWidget {
  const _StopRecoveryDetailScreen();

  @override
  Widget build(BuildContext context) {
    return _GuideDetailScreen(
      title: 'Stop & recovery',
      accentColor: AppColors.success,
      children: const [
        // When to stop card
        _WhenToStopCard(),
        SizedBox(height: AppSpacing.sm),

        // Recovery position photo + notes
        _PhotoCard(
          assetPath: 'assets/guide/detail_recovery_position.jpg',
          caption: 'Only when unconscious AND breathing normally',
          tint: AppColors.success,
        ),
        SizedBox(height: AppSpacing.sm),
        _SectionCard(
          titleIcon: Icons.rotate_90_degrees_ccw_rounded,
          titleIconColor: AppColors.success,
          title: 'Recovery position',
          child: Column(
            children: [
              Text(
                'Use when the person is unconscious but breathing normally. '
                    'Keeps the airway open and prevents choking.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: AppSpacing.md),
              _BulletRow(
                color: AppColors.success,
                title: 'Roll onto their side',
                body: 'Tilt head back slightly to keep airway open',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.success,
                title: 'Top knee bent forward as a prop',
              ),
              SizedBox(height: AppSpacing.xs),
              _BulletRow(
                color: AppColors.success,
                title: 'Monitor breathing continuously until EMS arrives',
              ),
              SizedBox(height: AppSpacing.sm),
              _SuccessBanner(
                text:
                'If they stop breathing — restart CPR immediately',
              ),
              SizedBox(height: AppSpacing.sm),
              _WarnBanner(
                text:
                'Suspected spinal injury? Don\'t move them unless there is an immediate life threat',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// _PhotoCard — image with gradient caption bar at the bottom
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoCard extends StatelessWidget {
  final String assetPath;
  final String caption;
  final Color tint;
  final double height;

  const _PhotoCard({
    required this.assetPath,
    required this.caption,
    this.tint = AppColors.primary,
    this.height = AppSpacing.guideDetailImageH,
  });

  @override
  Widget build(BuildContext context) {
    return Container(                                            // ← NEW
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 12,
              spreadRadius: 0,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: Stack(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: tint.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Icon(Icons.image_outlined,
                    size: AppSpacing.iconXl,
                    color: tint.withValues(alpha: 0.4)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.62)],
                ),
              ),
              child: Text(
                caption,
                style: AppTypography.body(
                    size: 11, color: AppColors.textOnDark),
              ),
            ),
          ),
        ],
          ),
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LabelledPhoto — small photo with a tinted label below (used in pediatric)
// ─────────────────────────────────────────────────────────────────────────────

class _LabelledPhoto extends StatelessWidget {
  final String assetPath;
  final String label;
  final Color tint;

  const _LabelledPhoto({
    required this.assetPath,
    required this.label,
    this.tint = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          child: SizedBox(
            height: AppSpacing.guideSmallPhotoH,
            child: Image.asset(
              assetPath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: tint.withValues(alpha: 0.08),
                alignment: Alignment.center,
                child: Icon(Icons.image_outlined,
                    size: AppSpacing.iconLg,
                    color: tint.withValues(alpha: 0.4)),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.label(size: 11, color: tint),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionCard — white card with icon + title row + body
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final IconData titleIcon;
  final Color titleIconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.titleIcon,
    required this.titleIconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon,
                  size: AppSpacing.iconSm, color: titleIconColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: AppTypography.label(
                    size: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InfoBanner / _WarnBanner / _SuccessBanner
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final String text;
  final Color accentColor;
  final IconData icon;

  const _InfoBanner({
    required this.text,
    this.accentColor = AppColors.primary,
    this.icon = Icons.info_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSpacing.iconSm, color: accentColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: AppTypography.body(size: 12, color: accentColor)),
          ),
        ],
      ),
    );
  }
}

class _WarnBanner extends StatelessWidget {
  final String text;
  final IconData icon;

  const _WarnBanner({
    required this.text,
    this.icon = Icons.warning_amber_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      decoration: AppDecorations.warningCard(
          radius: AppSpacing.cardRadiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSpacing.iconSm, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: AppTypography.body(
                    size: 12, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String text;

  const _SuccessBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      decoration: AppDecorations.successCard(
          radius: AppSpacing.cardRadiusMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: AppSpacing.iconSm, color: AppColors.success),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text,
                style: AppTypography.body(
                    size: 12, color: AppColors.success)),
          ),
        ],
      ),
    );
  }
}

class _ChainRow extends StatelessWidget {
  const _ChainRow();

  static const _links = [
    (Icons.phone_in_talk_rounded, AppColors.warning,    '1.\nRecognise\n& call'),
    (Icons.favorite_rounded,      AppColors.primary,    '2.\nCPR &\nAED'),
    (Icons.local_hospital_rounded,AppColors.emergency,  '3.\nAdvanced\ncare'),
    (Icons.self_improvement_rounded, AppColors.success, '4.\nRecovery'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.guideChainRowH,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (int i = 0; i < _links.length; i++) ...[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: AppSpacing.guideChainIcon,
                  height: AppSpacing.guideChainIcon,
                  decoration: BoxDecoration(
                    color: _links[i].$2.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _links[i].$2.withValues(alpha: 0.4)),
                  ),
                  child: Icon(_links[i].$1, size: 18, color: _links[i].$2),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _links[i].$3,
                  style: AppTypography.body(size: 9, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            if (i < _links.length - 1)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textSecondary.withValues(alpha: 0.4)),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BulletRow — single dot + title + optional body
// ─────────────────────────────────────────────────────────────────────────────

class _BulletRow extends StatelessWidget {
  final Color color;
  final String title;
  final String? body;

  const _BulletRow({
    required this.color,
    required this.title,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Container(
            width: AppSpacing.xs + AppSpacing.xxs,
            height: AppSpacing.xs + AppSpacing.xxs,
            decoration: AppDecorations.dot(color),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyMedium(size: 13)),
              if (body != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(body!,
                    style: AppTypography.body(
                        size: 12, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BulletList — multiple bullet rows (short items, no body)
// ─────────────────────────────────────────────────────────────────────────────

class _BulletList extends StatelessWidget {
  final List<String> items;
  final Color color;

  const _BulletList({
    required this.items,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _BulletRow(color: color, title: items[i]),
          if (i < items.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StepData + _StepRailList — numbered step rail
// ─────────────────────────────────────────────────────────────────────────────

class _StepData {
  final Color color;
  final String title;
  final String? body;
  final bool urgent;

  const _StepData({
    required this.color,
    required this.title,
    this.body,
    this.urgent = false,
  });
}

class _StepRailList extends StatelessWidget {
  final List<_StepData> steps;

  const _StepRailList({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRailRow(
            step: i + 1,
            data: steps[i],
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _StepRailRow extends StatelessWidget {
  final int step;
  final _StepData data;
  final bool isLast;

  const _StepRailRow({
    required this.step,
    required this.data,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final circleColor =
    data.urgent ? AppColors.emergency : data.color;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rail
          SizedBox(
            width: AppSpacing.guideStepRail,
            child: Column(
              children: [
                Container(
                  width: AppSpacing.guideStepNumber,
                  height: AppSpacing.guideStepNumber,
                  decoration: AppDecorations.iconCircle(bg: circleColor),
                  child: Center(
                    child: Text(
                      '$step',
                      style: AppTypography.badge(
                          size: 12, color: AppColors.textOnDark),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 1.5,
                        color: circleColor.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : AppSpacing.md,
                top: AppSpacing.xxs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(data.title,
                            style: AppTypography.bodyMedium(size: 13)),
                      ),
                      if (data.urgent) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 1,
                          ),
                          decoration: AppDecorations.chip(
                            color: AppColors.emergency,
                            bg: AppColors.errorBg,
                          ),
                          child: Text(
                            'PRIORITY',
                            style: AppTypography.badge(
                                size: 9,
                                color: AppColors.emergency),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (data.body != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(data.body!,
                        style: AppTypography.body(
                            size: 12,
                            color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RateGaugeBar — 100–120 /min gauge
// ─────────────────────────────────────────────────────────────────────────────

class _RateGaugeBar extends StatelessWidget {
  const _RateGaugeBar();

  static const double _min = 60;
  static const double _max = 160;
  static const double _safeMin = 100;
  static const double _safeMax = 120;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('60 /min', style: AppTypography.caption()),
            Text('100 – 120 /min',
                style: AppTypography.label(
                    size: 11, color: AppColors.success)),
            Text('160 /min', style: AppTypography.caption()),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LayoutBuilder(
          builder: (_, c) {
            final w = c.maxWidth;
            double f(double v) =>
                ((v - _min) / (_max - _min)).clamp(0.0, 1.0);
            final safeLeft = f(_safeMin) * w;
            final safeW = (f(_safeMax) - f(_safeMin)) * w;
            return SizedBox(
              height: AppSpacing.lg,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.55),
                        borderRadius:
                        BorderRadius.circular(AppSpacing.chipRadius),
                      ),
                    ),
                  ),
                  Positioned(
                    left: safeLeft,
                    width: safeW,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.85),
                        borderRadius:
                        BorderRadius.circular(AppSpacing.chipRadius),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'TARGET',
                        style: AppTypography.badge(
                            size: 9, color: AppColors.textOnDark),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DepthGaugeBar — 5–6 cm depth bar
// ─────────────────────────────────────────────────────────────────────────────

class _DepthGaugeBar extends StatelessWidget {
  const _DepthGaugeBar();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        const total = 8.0;
        final redW = (5 / total) * w;
        final greenW = (1 / total) * w;
        final orangeW = (2 / total) * w;
        const r = Radius.circular(AppSpacing.chipRadius);

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
                      color: AppColors.error.withValues(alpha: 0.65),
                      borderRadius: const BorderRadius.only(
                          topLeft: r, bottomLeft: r),
                    ),
                    alignment: Alignment.center,
                    child: Text('TOO SHALLOW',
                        style: AppTypography.badge(
                            size: 8, color: AppColors.textOnDark)),
                  ),
                  Container(
                    width: greenW,
                    color: AppColors.success.withValues(alpha: 0.85),
                    alignment: Alignment.center,
                    child: Text('✓',
                        style: AppTypography.badge(
                            size: 9, color: AppColors.textOnDark)),
                  ),
                  Container(
                    width: orangeW,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.75),
                      borderRadius: const BorderRadius.only(
                          topRight: r, bottomRight: r),
                    ),
                    alignment: Alignment.center,
                    child: Text('TOO DEEP',
                        style: AppTypography.badge(
                            size: 8, color: AppColors.textOnDark)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                SizedBox(
                  width: redW,
                  child: Text('0',
                      style: AppTypography.caption()),
                ),
                SizedBox(
                  width: greenW,
                  child: Text('5',
                      style: AppTypography.label(
                          size: 11, color: AppColors.success),
                      textAlign: TextAlign.start),
                ),
                SizedBox(
                  width: orangeW,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('6',
                          style: AppTypography.label(
                              size: 11, color: AppColors.warning)),
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

// ─────────────────────────────────────────────────────────────────────────────
// _RatioBox — 30 : 2 large-number display
// ─────────────────────────────────────────────────────────────────────────────

class _RatioBox extends StatelessWidget {
  const _RatioBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm + AppSpacing.xs),
      decoration: AppDecorations.primaryCard(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              Text('30',
                  style: AppTypography.numericDisplay(
                      size: 36, color: AppColors.primary)),
              Text('COMPRESSIONS',
                  style: AppTypography.badge(
                      size: 10, color: AppColors.primary)),
            ],
          ),
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(':',
                style: AppTypography.heading(
                    size: 32, color: AppColors.textDisabled)),
          ),
          Column(
            children: [
              Text('2',
                  style: AppTypography.numericDisplay(
                      size: 36, color: AppColors.primaryAlt)),
              Text('BREATHS',
                  style: AppTypography.badge(
                      size: 10, color: AppColors.primaryAlt)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PadPlacementSVG — torso outline + two numbered pads (CustomPaint)
// Preserved from original _AedSchematicPainter, no changes to logic.
// ─────────────────────────────────────────────────────────────────────────────

class _PadPlacementSVG extends StatelessWidget {
  const _PadPlacementSVG();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: AppSpacing.guideSchematicH,
          width: 130,
          child: CustomPaint(
            painter: _AedSchematicPainter(),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PadLabel(
                  number: '①',
                  text: 'Below right\ncollarbone',
                  color: AppColors.warning),
              const SizedBox(height: AppSpacing.md),
              _PadLabel(
                  number: '②',
                  text: 'Left side,\nbelow armpit',
                  color: AppColors.warning),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Dry chest first\nRemove clothing\nNo metal on skin',
                style: AppTypography.caption(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PadLabel extends StatelessWidget {
  final String number;
  final String text;
  final Color color;

  const _PadLabel({
    required this.number,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number,
            style: AppTypography.bodyMedium(size: 16, color: color)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(text,
              style: AppTypography.body(
                  size: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PediatricTable — adult vs infant vs child
// ─────────────────────────────────────────────────────────────────────────────

class _PediatricTable extends StatelessWidget {
  const _PediatricTable();

  static const _rows = [
    ['Depth', '5–6 cm', '4 cm', '4–5 cm'],
    ['Hands', 'Two hands', '2 fingers', '1–2 hands'],
    ['Ratio', '30 : 2', '15 : 2 (×2)', '15 : 2 (×2)'],
    ['Breaths', 'Full breath', 'Gentle puff', 'Small breath'],
    ['AED', 'Adult pads', 'Ped. pads\nfront/back', 'Ped. if available'],
  ];

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.4),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.5),
        3: FlexColumnWidth(1.5),
      },
      children: [
        // Header row
        TableRow(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.divider, width: 1.5),
            ),
          ),
          children: [
            const SizedBox(height: AppSpacing.lg),
            _TableHeader('Adult'),
            _TableHeader('Infant\n<1 yr', color: AppColors.pediatric),
            _TableHeader('Child\n1–8 yr', color: AppColors.pediatric),
          ],
        ),
        // Data rows
        for (var i = 0; i < _rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i.isEven ? AppColors.screenBgGrey : AppColors.white,
            ),
            children: [
              _TableCell(_rows[i][0], bold: true),
              _TableCell(_rows[i][1],
                  color: AppColors.textSecondary),
              _TableCell(_rows[i][2],
                  color: AppColors.pediatric, bold: true),
              _TableCell(_rows[i][3],
                  color: AppColors.pediatric, bold: true),
            ],
          ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String text;
  final Color color;

  const _TableHeader(this.text, {this.color = AppColors.textSecondary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          bottom: AppSpacing.xs, right: AppSpacing.xxs),
      child: Text(text,
          style: AppTypography.label(size: 10, color: color),
          textAlign: TextAlign.center),
    );
  }
}

class _TableCell extends StatelessWidget {
  final String text;
  final Color color;
  final bool bold;

  const _TableCell(this.text,
      {this.color = AppColors.textPrimary, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs + AppSpacing.xxs,
          horizontal: AppSpacing.xxs),
      child: Text(
        text,
        style: bold
            ? AppTypography.bodyMedium(size: 11, color: color)
            : AppTypography.body(size: 11, color: color),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WhenToStopCard
// ─────────────────────────────────────────────────────────────────────────────

class _WhenToStopCard extends StatelessWidget {
  const _WhenToStopCard();

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
              const Icon(Icons.play_circle_outline_rounded,
                  size: AppSpacing.iconSm, color: AppColors.success),
              const SizedBox(width: AppSpacing.xs),
              Text('Keep going while',
                  style: AppTypography.label(
                      size: 12, color: AppColors.success)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(
            color: AppColors.success,
            items: [
              'No AED available yet or AED is analysing',
              'No clear signs of life or normal breathing',
              'You are still physically able',
            ],
          ),
          const Divider(
              height: AppSpacing.lg, color: AppColors.divider),
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: AppSpacing.iconSm, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text('Stop when',
                  style: AppTypography.label(
                      size: 12, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _BulletList(
            color: AppColors.primary,
            items: [
              'EMS takes over care',
              'Person begins breathing normally',
              'You cannot safely continue',
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _InfoBanner(
            text:
            'Swap rescuers every 2 minutes if possible to maintain compression quality',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AED schematic painter — preserved from original, no logic changes
// ═══════════════════════════════════════════════════════════════════════════════

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
        width: size.width * 0.70,
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
      Offset(cx - size.width * 0.30, size.height * 0.14),
      Offset(cx + size.width * 0.30, size.height * 0.14),
      collarPaint,
    );

    _drawPad(canvas,
        label: '1',
        center: Offset(cx + size.width * 0.20, size.height * 0.24),
        color: AppColors.warning);
    _drawPad(canvas,
        label: '2',
        center: Offset(cx - size.width * 0.26, size.height * 0.58),
        color: AppColors.warning);

    final linePaint = Paint()
      ..color = AppColors.warning.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final p1 = Offset(cx + size.width * 0.20, size.height * 0.24);
    final p2 = Offset(cx - size.width * 0.26, size.height * 0.58);
    _drawDashedLine(canvas, p1, p2, linePaint);
  }

  void _drawPad(
      Canvas canvas, {
        required String label,
        required Offset center,
        required Color color,
      }) {
    final padPaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: center,
            width: AppSpacing.guideSchematicPadW,
            height: AppSpacing.guideSchematicPadH),
        const Radius.circular(AppSpacing.cardRadiusSm),
      ),
      padPaint,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: AppSpacing.guideSchematicLabelSize,
          fontWeight: FontWeight.w800,
          color: AppColors.textOnDark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    const dash = 6.0;
    const gap = 4.0;
    final nx = dx / dist;
    final ny = dy / dist;
    double t = 0;
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