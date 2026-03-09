import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HELP & ABOUT SCREEN
// ─────────────────────────────────────────────────────────────────────────────

const _kAppVersion = '1.0.0';
const _kBuildNumber = '42';

class HelpAboutScreen extends StatefulWidget {
  const HelpAboutScreen({super.key});

  @override
  State<HelpAboutScreen> createState() => _HelpAboutScreenState();
}

class _HelpAboutScreenState extends State<HelpAboutScreen> {
  int _logoTapCount = 0; // Easter egg: tap logo 7x for debug info

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgGrey,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kTextDark,
        elevation: 0,
        toolbarHeight: 52,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Help & About', style: kHeading(size: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kDivider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [

          // ── App identity card ──────────────────────────────────────────────
          _AppIdentityCard(
            onLogoTap: () {
              setState(() => _logoTapCount++);
              if (_logoTapCount == 7) {
                HapticFeedback.heavyImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🐛 Debug mode enabled')),
                );
              }
            },
          ),

          // ── FAQ ───────────────────────────────────────────────────────────
          _SectionHeader(label: 'Frequently Asked Questions'),
          _FaqCard(items: const [
            _FaqItem(
              question: 'How do I pair the CPR glove?',
              answer:
              'Turn on the glove by holding the power button for 2 seconds. Open the app — it will automatically detect and connect via Bluetooth. The BLE indicator in the top bar will turn blue when connected.',
            ),
            _FaqItem(
              question: 'What is Training Mode?',
              answer:
              'Training Mode lets you practice CPR technique without it being treated as a real emergency. Sessions are recorded, scored, and saved to your history. Requires a logged-in account.',
            ),
            _FaqItem(
              question: 'What is Emergency Mode?',
              answer:
              'Emergency Mode is for real cardiac arrest situations. No session data is recorded or graded. The 112 call button is always visible.',
            ),
            _FaqItem(
                question: 'How is compression depth measured?',
                answer:
                'The glove uses a pressure sensor to estimate compression depth in real-time. Target depth is 5–6 cm. The Live CPR screen displays your current depth and whether its within range.',
            ),
            _FaqItem(
              question: 'Why does the app require login for Training Mode?',
              answer:
              'Your training sessions, scores, and leaderboard position are stored server-side and tied to your account. Emergency Mode always works without login.',
            ),
            _FaqItem(
              question: 'What do I do if the glove disconnects mid-session?',
              answer:
              'The app will display a disconnect warning. Try to stay calm, keep performing CPR manually, and ask a bystander to reconnect the glove. The session will resume automatically when reconnected.',
            ),
          ]),

          // ── CPR Reference ─────────────────────────────────────────────────
          _SectionHeader(label: 'CPR Quick Reference'),
          _ReferenceCard(),

          // ── Support ───────────────────────────────────────────────────────
          _SectionHeader(label: 'Support'),
          _LinksCard(context: context),

          // ── About ─────────────────────────────────────────────────────────
          _SectionHeader(label: 'About'),
          _AboutCard(),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP IDENTITY CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AppIdentityCard extends StatelessWidget {
  final VoidCallback onLogoTap;
  const _AppIdentityCard({required this.onLogoTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onLogoTap,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: kPrimaryLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kPrimaryMid, width: 1.5),
              ),
              child: const Center(
                child: Icon(Icons.favorite_rounded, color: kPrimary, size: 36),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('CPR Assist', style: kHeading(size: 20)),
          const SizedBox(height: 4),
          Text(
            'Version $_kAppVersion (build $_kBuildNumber)',
            style: kLabel(size: 12, color: kTextLight),
          ),
          const SizedBox(height: 10),
          Text(
            'A research-grade CPR guidance tool designed to\nimprove bystander CPR quality.',
            textAlign: TextAlign.center,
            style: kBody(size: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAQ CARD
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
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: widget.items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          final isLast = i == widget.items.length - 1;
          final isExpanded = _expanded == i;

          return Column(
            children: [
              InkWell(
                onTap: () =>
                    setState(() => _expanded = isExpanded ? null : i),
                borderRadius: BorderRadius.vertical(
                  top: i == 0 ? const Radius.circular(14) : Radius.zero,
                  bottom: isLast && !isExpanded
                      ? const Radius.circular(14)
                      : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.question,
                          style: kBody(size: 14, color: kTextDark).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            size: 20, color: kTextLight),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: isExpanded
                    ? Column(
                  children: [
                    const Divider(
                        height: 1, thickness: 1, color: kDivider),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Text(item.answer,
                          style: kBody(size: 13, color: kTextMid)),
                    ),
                  ],
                )
                    : const SizedBox.shrink(),
              ),
              if (!isLast)
                const Divider(
                    height: 1,
                    thickness: 1,
                    color: kDivider,
                    indent: 16,
                    endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CPR REFERENCE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _ReferenceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const specs = [
      ('Compression rate', '100–120 / min'),
      ('Compression depth', '5–6 cm'),
      ('Hand position', 'Centre of chest'),
      ('Ratio (CPR:breaths)', '30 : 2'),
      ('Chest recoil', 'Full between compressions'),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: specs.asMap().entries.map((e) {
          final isLast = e.key == specs.length - 1;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.value.$1,
                          style: kBody(size: 13, color: kTextMid)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: kPrimaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.value.$2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                    height: 1,
                    thickness: 1,
                    color: kDivider,
                    indent: 16,
                    endIndent: 16),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LINKS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _LinksCard extends StatelessWidget {
  final BuildContext context;
  const _LinksCard({required this.context});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          _LinkTile(
            icon: Icons.email_outlined,
            label: 'Contact Support',
            onTap: () {
              // TODO: launch mailto
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('support@cprassist.app')));
            },
          ),
          const Divider(height: 1, color: kDivider, indent: 16),
          _LinkTile(
            icon: Icons.bug_report_outlined,
            label: 'Report a Bug',
            onTap: () {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Bug report coming soon')));
            },
          ),
          const Divider(height: 1, color: kDivider, indent: 16),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            onTap: () {
              // TODO: launch URL
            },
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _LinkTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: kPrimary),
            const SizedBox(width: 12),
            Expanded(
                child: Text(label,
                    style: kBody(size: 14, color: kTextDark)
                        .copyWith(fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: kTextLight),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ABOUT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Version', style: kLabel()),
          const SizedBox(height: 2),
          Text('$_kAppVersion (build $_kBuildNumber)',
              style: kBody(size: 14, color: kTextDark)
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Text('Built with', style: kLabel()),
          const SizedBox(height: 2),
          Text('Flutter · Riverpod · BLE',
              style: kBody(size: 14, color: kTextDark)
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Text('Research context', style: kLabel()),
          const SizedBox(height: 2),
          Text(
            'Developed as part of a thesis project on improving bystander CPR quality through real-time glove-assisted feedback.',
            style: kBody(size: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(label.toUpperCase(), style: kLabel(size: 11, color: kTextLight)),
    );
  }
}