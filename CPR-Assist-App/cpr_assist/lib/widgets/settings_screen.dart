import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../widgets/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── Local state (wire to actual prefs/providers when ready) ────────────────
  bool _hapticFeedback   = true;
  bool _audioFeedback    = true;
  bool _keepScreenOn     = true;
  bool _autoSwitchToCPR  = true;   // auto-navigate to Live CPR when glove starts
  bool _showDepthGuide   = true;
  bool _showRateGuide    = true;
  bool _notifyOnDisconnect = true;
  String _compressionUnit = 'cm';  // 'cm' or 'in'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgGrey,
      appBar: _buildAppBar(context),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [

          // ── Glove & Connection ─────────────────────────────────────────────
          _SectionHeader(label: 'Glove & Connection'),
          _SettingsCard(children: [
            _ToggleTile(
              icon: Icons.bluetooth_rounded,
              iconColor: kPrimary,
              title: 'Alert on disconnect',
              subtitle: 'Notify when glove loses BLE connection',
              value: _notifyOnDisconnect,
              onChanged: (v) => setState(() => _notifyOnDisconnect = v),
            ),
            _Divider(),
            _ToggleTile(
              icon: Icons.switch_right_outlined,
              iconColor: kPrimary,
              title: 'Auto-switch to Live CPR',
              subtitle: 'Navigate automatically when glove detects CPR start',
              value: _autoSwitchToCPR,
              onChanged: (v) => setState(() => _autoSwitchToCPR = v),
            ),
          ]),

          // ── Feedback ──────────────────────────────────────────────────────
          _SectionHeader(label: 'Feedback'),
          _SettingsCard(children: [
            _ToggleTile(
              icon: Icons.vibration_rounded,
              iconColor: kPrimary,
              title: 'Haptic feedback',
              subtitle: 'Vibrate on compression detection',
              value: _hapticFeedback,
              onChanged: (v) {
                setState(() => _hapticFeedback = v);
                if (v) HapticFeedback.lightImpact();
              },
            ),
            _Divider(),
            _ToggleTile(
              icon: Icons.volume_up_outlined,
              iconColor: kPrimary,
              title: 'Audio feedback',
              subtitle: 'Spoken pace cues during CPR',
              value: _audioFeedback,
              onChanged: (v) => setState(() => _audioFeedback = v),
            ),
            _Divider(),
            _ToggleTile(
              icon: Icons.straighten_outlined,
              iconColor: kPrimary,
              title: 'Show depth guide',
              subtitle: 'Display target compression depth on screen',
              value: _showDepthGuide,
              onChanged: (v) => setState(() => _showDepthGuide = v),
            ),
            _Divider(),
            _ToggleTile(
              icon: Icons.speed_outlined,
              iconColor: kPrimary,
              title: 'Show rate guide',
              subtitle: 'Display target compression rate on screen',
              value: _showRateGuide,
              onChanged: (v) => setState(() => _showRateGuide = v),
            ),
          ]),

          // ── Display ───────────────────────────────────────────────────────
          _SectionHeader(label: 'Display'),
          _SettingsCard(children: [
            _ToggleTile(
              icon: Icons.screen_lock_portrait_outlined,
              iconColor: kPrimary,
              title: 'Keep screen on',
              subtitle: 'Prevent screen timeout during CPR sessions',
              value: _keepScreenOn,
              onChanged: (v) => setState(() => _keepScreenOn = v),
            ),
            _Divider(),
            _SelectTile(
              icon: Icons.straighten_rounded,
              iconColor: kPrimary,
              title: 'Depth unit',
              options: const ['cm', 'in'],
              selected: _compressionUnit,
              onChanged: (v) => setState(() => _compressionUnit = v),
            ),
          ]),

          // ── Data & Privacy ─────────────────────────────────────────────────
          _SectionHeader(label: 'Data & Privacy'),
          _SettingsCard(children: [
            _NavTile(
              icon: Icons.download_outlined,
              iconColor: kPrimary,
              title: 'Export session data',
              subtitle: 'Download your training history as CSV',
              onTap: () {
                // TODO: trigger export
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export coming soon')),
                );
              },
            ),
            _Divider(),
            _NavTile(
              icon: Icons.delete_outline_rounded,
              iconColor: kEmergency,
              title: 'Delete all session data',
              subtitle: 'Permanently remove all training records',
              titleColor: kEmergency,
              onTap: () => _confirmDeleteData(context),
            ),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: kTextDark,
      elevation: 0,
      toolbarHeight: 52,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: kPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text('Settings', style: kHeading(size: 18)),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: kDivider),
      ),
    );
  }

  Future<void> _confirmDeleteData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: const BoxDecoration(
                          color: kEmergencyBg, shape: BoxShape.circle),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: kEmergency, size: 26),
                    ),
                    const SizedBox(height: 14),
                    Text('Delete All Data?', style: kHeading(size: 16)),
                    const SizedBox(height: 8),
                    Text(
                      'This will permanently delete all your training sessions and scores. This cannot be undone.',
                      textAlign: TextAlign.center,
                      style: kBody(size: 13),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: kDivider),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel',
                            style: kBody(size: 15, color: kTextMid).copyWith(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: kDivider),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kEmergency)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session data deleted')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRIVATE COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

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

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

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
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(
        height: 1, thickness: 1, color: kDivider, indent: 56, endIndent: 0);
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _IconBox(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: kBody(size: 14, color: kTextDark)
                        .copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!, style: kBody(size: 12, color: kTextLight)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: kPrimary,
          ),
        ],
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onChanged;

  const _SelectTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          _IconBox(icon: icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: kBody(size: 14, color: kTextDark)
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          Container(
            decoration: BoxDecoration(
              color: kPrimaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) {
                final isSelected = opt == selected;
                return GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      opt,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : kTextMid,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _IconBox(icon: icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: kBody(size: 14, color: titleColor ?? kTextDark)
                          .copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle!, style: kBody(size: 12, color: kTextLight)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: kTextLight),
          ],
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconBox({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}