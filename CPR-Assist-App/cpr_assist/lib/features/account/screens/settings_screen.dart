import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── Local toggle state — wire to SharedPreferences / provider when ready ──
  bool   _hapticFeedback     = true;
  bool   _audioFeedback      = true;
  bool   _keepScreenOn       = true;
  bool   _autoSwitchToCPR    = true;
  bool   _showDepthGuide     = true;
  bool   _showRateGuide      = true;
  bool   _notifyOnDisconnect = true;
  String _compressionUnit    = 'cm'; // 'cm' | 'in'

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
          // ── Glove & Connection ───────────────────────────────────────────
          const _SectionHeader(label: 'Glove & Connection'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:     Icons.bluetooth_rounded,
              title:    'Alert on disconnect',
              subtitle: 'Notify when glove loses BLE connection',
              value:    _notifyOnDisconnect,
              onChanged: (v) => setState(() => _notifyOnDisconnect = v),
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.switch_right_outlined,
              title:    'Auto-switch to Live CPR',
              subtitle: 'Navigate automatically when glove detects CPR start',
              value:    _autoSwitchToCPR,
              onChanged: (v) => setState(() => _autoSwitchToCPR = v),
            ),
          ]),

          // ── Feedback ────────────────────────────────────────────────────
          const _SectionHeader(label: 'Feedback'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:     Icons.vibration_rounded,
              title:    'Haptic feedback',
              subtitle: 'Vibrate on compression detection',
              value:    _hapticFeedback,
              onChanged: (v) {
                setState(() => _hapticFeedback = v);
                if (v) HapticFeedback.lightImpact();
              },
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.volume_up_outlined,
              title:    'Audio feedback',
              subtitle: 'Spoken pace cues during CPR',
              value:    _audioFeedback,
              onChanged: (v) => setState(() => _audioFeedback = v),
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.straighten_outlined,
              title:    'Show depth guide',
              subtitle: 'Display target compression depth on screen',
              value:    _showDepthGuide,
              onChanged: (v) => setState(() => _showDepthGuide = v),
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.speed_outlined,
              title:    'Show rate guide',
              subtitle: 'Display target compression rate on screen',
              value:    _showRateGuide,
              onChanged: (v) => setState(() => _showRateGuide = v),
            ),
          ]),

          // ── Display ─────────────────────────────────────────────────────
          const _SectionHeader(label: 'Display'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:     Icons.screen_lock_portrait_outlined,
              title:    'Keep screen on',
              subtitle: 'Prevent screen timeout during CPR sessions',
              value:    _keepScreenOn,
              onChanged: (v) => setState(() => _keepScreenOn = v),
            ),
            const _SettingsDivider(),
            _SelectTile(
              icon:      Icons.straighten_rounded,
              title:     'Depth unit',
              options:   const ['cm', 'in'],
              selected:  _compressionUnit,
              onChanged: (v) => setState(() => _compressionUnit = v),
            ),
          ]),

          // ── Data & Privacy ───────────────────────────────────────────────
          const _SectionHeader(label: 'Data & Privacy'),
          _SettingsCard(children: [
            _NavTile(
              icon:     Icons.download_outlined,
              title:    'Export session data',
              subtitle: 'Download your training history as CSV',
              onTap: () => UIHelper.showSnackbar(
                context,
                message: 'Export coming soon',
                icon:    Icons.download_outlined,
              ),
            ),
            const _SettingsDivider(),
            _NavTile(
              icon:       Icons.delete_outline_rounded,
              iconColor:  AppColors.emergencyRed,
              title:      'Delete all session data',
              subtitle:   'Permanently remove all training records',
              titleColor: AppColors.emergencyRed,
              onTap:      () => _confirmDeleteData(),
            ),
          ]),

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
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
        onPressed: () => context.pop(),
      ),
      title: Text('Settings', style: AppTypography.heading(size: 18)),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
        child: Divider(
          height: AppSpacing.dividerThickness,
          color:  AppColors.divider,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteData() async {
    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.delete_outline_rounded,
      iconColor:    AppColors.emergencyRed,
      iconBg:       AppColors.emergencyBg,
      title:        'Delete All Data?',
      message:      'This will permanently delete all your training sessions and scores. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.emergencyRed,
      cancelLabel:  'Cancel',
    );

    if (confirmed == true && mounted) {
      // TODO: call delete API
      UIHelper.showSuccess(context, 'All session data deleted');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
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

// ─────────────────────────────────────────────────────────────────────────────
// Settings card container
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height:    AppSpacing.dividerThickness,
      thickness: AppSpacing.dividerThickness,
      color:     AppColors.divider,
      indent:    AppSpacing.iconLg + AppSpacing.md + AppSpacing.sm, // aligns past icon box
      endIndent: 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle tile
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  final IconData         icon;
  final String           title;
  final String?          subtitle;
  final bool             value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.xs,
      ),
      child: Row(
        children: [
          _IconBox(icon: icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyMedium(size: 14)),
                if (subtitle != null)
                  Text(subtitle!, style: AppTypography.caption()),
              ],
            ),
          ),
          Switch(
            value:       value,
            onChanged:   onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented select tile (e.g. cm / in)
// ─────────────────────────────────────────────────────────────────────────────

class _SelectTile extends StatelessWidget {
  final IconData             icon;
  final String               title;
  final List<String>         options;
  final String               selected;
  final ValueChanged<String> onChanged;

  const _SelectTile({
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      child: Row(
        children: [
          _IconBox(icon: icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title, style: AppTypography.bodyMedium(size: 14)),
          ),
          Container(
            decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadiusSm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) {
                final isSelected = opt == selected;
                return GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.cardPadding - AppSpacing.xxs,
                      vertical:   AppSpacing.cardSpacing,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                    ),
                    child: Text(
                      opt,
                      style: AppTypography.buttonSmall(
                        color: isSelected ? AppColors.textOnDark : AppColors.textSecondary,
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

// ─────────────────────────────────────────────────────────────────────────────
// Nav tile (tappable row with chevron)
// ─────────────────────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final IconData     icon;
  final Color?       iconColor;
  final String       title;
  final String?      subtitle;
  final Color?       titleColor;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.onTap,
  });

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
            _IconBox(icon: icon, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium(
                      size:  14,
                      color: titleColor ?? AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: AppTypography.caption()),
                ],
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
// Shared icon box
// ─────────────────────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color?   color;

  const _IconBox({required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      width:  AppSpacing.touchTargetMin - AppSpacing.sm, // 36
      height: AppSpacing.touchTargetMin - AppSpacing.sm,
      decoration: AppDecorations.iconRounded(
        bg:     c.withValues(alpha: 0.1),
        radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
      ),
      child: Icon(icon, color: c, size: AppSpacing.iconSm),
    );
  }
}