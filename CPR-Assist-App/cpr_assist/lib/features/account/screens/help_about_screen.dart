import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HelpAboutScreen
// ─────────────────────────────────────────────────────────────────────────────

const _kAppVersion  = '1.0.0';
const _kBuildNumber = '42';

class HelpAboutScreen extends StatefulWidget {
  const HelpAboutScreen({super.key});

  @override
  State<HelpAboutScreen> createState() => _HelpAboutScreenState();
}

class _HelpAboutScreenState extends State<HelpAboutScreen> {
  int _logoTapCount = 0; // Easter egg: tap logo 7× for debug info

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: _buildAppBar(context),
      body: ListView(
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // ── App identity ─────────────────────────────────────────────────
          _AppIdentityCard(
            onLogoTap: () {
              setState(() => _logoTapCount++);
              if (_logoTapCount == 7) {
                HapticFeedback.heavyImpact();
                UIHelper.showSnackbar(
                  context,
                  message: '🐛 Debug mode enabled',
                  icon:    Icons.bug_report_outlined,
                );
              }
            },
          ),

          // ── FAQ ──────────────────────────────────────────────────────────
          const _SectionHeader(label: 'Frequently Asked Questions'),
          const _FaqCard(items: [
            _FaqItem(
              question: 'How do I pair the CPR glove?',
              answer:
              'Turn on the glove by holding the power button for 2 seconds. '
                  'Open the app — it will automatically detect and connect via Bluetooth. '
                  'The BLE indicator in the top bar will turn green when connected.',
            ),
            _FaqItem(
              question: 'What is Training Mode?',
              answer:
              'Training Mode lets you practise CPR technique without treating it as '
                  'a real emergency. Sessions are recorded, scored, and saved to your '
                  'history. Requires a logged-in account.',
            ),
            _FaqItem(
              question: 'What is Emergency Mode?',
              answer:
              'Emergency Mode is for real cardiac arrest situations. No session data '
                  'is recorded or graded. The 112 call button is always visible.',
            ),
            _FaqItem(
              question: 'How is compression depth measured?',
              answer:
              'The glove uses a pressure sensor to estimate compression depth in '
                  'real-time. Target depth is 5–6 cm. The Live CPR screen displays your '
                  'current depth and whether it is within the correct range.',
            ),
            _FaqItem(
              question: 'Why does Training Mode require login?',
              answer:
              'Your training sessions, scores, and leaderboard position are stored '
                  'server-side and tied to your account. Emergency Mode always works '
                  'without login.',
            ),
            _FaqItem(
              question: 'What if the glove disconnects mid-session?',
              answer:
              'The app will display a disconnect warning. Stay calm, continue CPR '
                  'manually, and ask a bystander to reconnect the glove. The session will '
                  'resume automatically when reconnected.',
            ),
          ]),

          // ── CPR Quick Reference ──────────────────────────────────────────
          const _SectionHeader(label: 'CPR Quick Reference'),
          const _ReferenceCard(),

          // ── Support ──────────────────────────────────────────────────────
          const _SectionHeader(label: 'Support'),
          _SupportCard(),

          // ── About ────────────────────────────────────────────────────────
          const _SectionHeader(label: 'About'),
          const _AboutCard(),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor:        AppColors.headerBg,
      foregroundColor:        AppColors.textPrimary,
      elevation:              0,
      scrolledUnderElevation: 0,
      toolbarHeight:          AppSpacing.headerHeight,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: AppColors.primary,
        ),
        onPressed: () => context.pop(),
      ),
      title: Text('Help & About', style: AppTypography.heading(size: 18)),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
        child: Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App identity card
// ─────────────────────────────────────────────────────────────────────────────

class _AppIdentityCard extends StatelessWidget {
  final VoidCallback onLogoTap;
  const _AppIdentityCard({required this.onLogoTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:   const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs,
      ),
      padding:  const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          GestureDetector(
            onTap: onLogoTap,
            child: Container(
              width:  AppSpacing.xxl + AppSpacing.lg,  // 72
              height: AppSpacing.xxl + AppSpacing.lg,
              decoration: BoxDecoration(
                color:        AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg - AppSpacing.xxs),
                border: Border.all(color: AppColors.primaryMid, width: 1.5),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: AppColors.primary,
                size:  AppSpacing.iconLg + AppSpacing.xs,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.cardPadding - AppSpacing.xxs),
          Text('CPR Assist', style: AppTypography.heading(size: 20)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Version $_kAppVersion (build $_kBuildNumber)',
            style: AppTypography.label(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A research-grade CPR guidance tool designed to\nimprove bystander CPR quality.',
            textAlign: TextAlign.center,
            style:     AppTypography.body(size: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAQ
// ─────────────────────────────────────────────────────────────────────────────

class _FaqItem {
  final String question;
  final String answer;
  const _FaqItem({required this.question, required this.answer});
}

class _FaqCard extends StatefulWidget {
  final List<_FaqItem> items;
  const _FaqCard({required this.items});

  @override
  State<_FaqCard> createState() => _FaqCardState();
}

class _FaqCardState extends State<_FaqCard> {
  int? _expanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        children: widget.items.asMap().entries.map((entry) {
          final i        = entry.key;
          final item     = entry.value;
          final isLast   = i == widget.items.length - 1;
          final expanded = _expanded == i;

          return Column(
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = expanded ? null : i),
                borderRadius: BorderRadius.vertical(
                  top:    i == 0    ? const Radius.circular(AppSpacing.cardRadius) : Radius.zero,
                  bottom: isLast && !expanded
                      ? const Radius.circular(AppSpacing.cardRadius)
                      : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical:   AppSpacing.cardPadding - AppSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.question,
                          style: AppTypography.bodyMedium(size: 14),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedRotation(
                        turns:    expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size:  AppSpacing.iconMd,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve:    Curves.easeInOut,
                child: expanded
                    ? Column(
                  children: [
                    const Divider(
                      height: AppSpacing.dividerThickness,
                      color:  AppColors.divider,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: Text(
                        item.answer,
                        style: AppTypography.body(size: 13),
                      ),
                    ),
                  ],
                )
                    : const SizedBox.shrink(),
              ),
              if (!isLast)
                const Divider(
                  height:    AppSpacing.dividerThickness,
                  color:     AppColors.divider,
                  indent:    AppSpacing.md,
                  endIndent: AppSpacing.md,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CPR Quick Reference card
// ─────────────────────────────────────────────────────────────────────────────

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard();

  static const _specs = [
    ('Compression rate',      '100–120 / min'),
    ('Compression depth',     '5–6 cm'),
    ('Hand position',         'Centre of chest'),
    ('Ratio (CPR:breaths)',   '30 : 2'),
    ('Chest recoil',          'Full between compressions'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        children: _specs.asMap().entries.map((e) {
          final isLast = e.key == _specs.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical:   AppSpacing.sm + AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.value.$1,
                        style: AppTypography.body(size: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + AppSpacing.xxs,
                        vertical:   AppSpacing.xs,
                      ),
                      decoration: AppDecorations.tintedCard(
                        radius: AppSpacing.cardRadiusSm,
                      ),
                      child: Text(
                        e.value.$2,
                        style: AppTypography.bodyBold(
                          size:  13,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                  height:    AppSpacing.dividerThickness,
                  color:     AppColors.divider,
                  indent:    AppSpacing.md,
                  endIndent: AppSpacing.md,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Support card
// ─────────────────────────────────────────────────────────────────────────────

class _SupportCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          _LinkTile(
            icon:  Icons.email_outlined,
            label: 'Contact Support',
            onTap: () => UIHelper.showSnackbar(
              context,
              message: 'support@cprassist.app',
              icon:    Icons.email_outlined,
            ),
          ),
          const Divider(height: AppSpacing.dividerThickness, color: AppColors.divider, indent: AppSpacing.md),
          _LinkTile(
            icon:  Icons.bug_report_outlined,
            label: 'Report a Bug',
            onTap: () => UIHelper.showSnackbar(
              context,
              message: 'Bug report coming soon',
              icon:    Icons.bug_report_outlined,
            ),
          ),
          const Divider(height: AppSpacing.dividerThickness, color: AppColors.divider, indent: AppSpacing.md),
          _LinkTile(
            icon:  Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () {}, // TODO: launch URL
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;

  const _LinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.cardPadding - AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Icon(icon, size: AppSpacing.iconMd, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMedium(size: 14),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size:  AppSpacing.iconSm,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// About card
// ─────────────────────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:   const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding:  const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AboutRow(label: 'Version',           value: '$_kAppVersion (build $_kBuildNumber)'),
          const SizedBox(height: AppSpacing.cardPadding - AppSpacing.xxs),
          const _AboutRow(label: 'Built with',        value: 'Flutter · Riverpod · BLE'),
          const SizedBox(height: AppSpacing.cardPadding - AppSpacing.xxs),
          Text('Research context', style: AppTypography.label()),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Developed as part of a thesis project on improving bystander CPR quality '
                'through real-time glove-assisted feedback.',
            style: AppTypography.body(size: 13),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label()),
        const SizedBox(height: AppSpacing.xxs),
        Text(value,  style: AppTypography.bodyMedium(size: 14)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.cardSpacing,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.badge(color: AppColors.textDisabled),
      ),
    );
  }
}