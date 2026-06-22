import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../aed_map/services/cache_service.dart';
import 'glove_diagnostic_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: _buildAppBar(context),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.md,
            ),
        children: [
// ── Glove & Connection ───────────────────────────────────────────
          const _SectionHeader(label: 'Glove & Connection'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:      Icons.bluetooth_rounded,
              title:     'Alert on disconnect',
              subtitle:  'Warn if glove loses connection during an active session',
              value:     settings.notifyOnDisconnect,
              onChanged: (v) => notifier.setNotifyOnDisconnect(v),
            ),
          ]),

// ── Glove Feedback ───────────────────────────────────────────────
          const _SectionHeader(label: 'Glove Feedback'),
          _SettingsCard(children: [
            _SliderTile(
              icon:         Icons.volume_up_outlined,
              title:        'Audio volume',
              subtitle:     'Spoken pace cues during CPR. Drag to 0 to mute.',
              value:        settings.audioVolume,
              min:          AppConstants.audioVolumeMin,
              max:          AppConstants.audioVolumeMax,
              labelBuilder: (v) => v == 0
                  ? 'Off'
                  : '${(v * 100 / AppConstants.audioVolumeMax).round()}%',
              onChanged:   (v) => notifier.setAudioVolumeLive(v),
              onChangeEnd: (v) {
                notifier.setAudioVolumePersist(v);
                final s = ref.read(settingsProvider);
                ref.read(bleConnectionProvider).sendSetIntensity(
                  audioVolume:  v,
                  motorPercent: s.hapticIntensity,
                );
                ref.read(bleConnectionProvider).sendSetFeedbackChannels(
                  audio:  v > 0,
                  haptic: s.hapticIntensity > 0,
                  visual: s.gloveLedBrightness > 0,
                );
              },
            ),
            const _SettingsDivider(),
            _SliderTile(
              icon:         Icons.vibration_rounded,
              title:        'Vibration intensity',
              subtitle:     'Glove motor pulse strength. Drag to 0 to disable.',
              value:        settings.hapticIntensity,
              min:          0,
              max:          100,
              labelBuilder: (v) => v == 0 ? 'Off' : '$v%',
              onChanged:   (v) => notifier.setHapticIntensityLive(v),
              onChangeEnd: (v) {
                notifier.setHapticIntensityPersist(v);
                final s = ref.read(settingsProvider);
                ref.read(bleConnectionProvider).sendSetIntensity(
                  audioVolume:  s.audioVolume,
                  motorPercent: v,
                );
                ref.read(bleConnectionProvider).sendSetFeedbackChannels(
                  audio:  s.audioVolume > 0,
                  haptic: v > 0,
                  visual: s.gloveLedBrightness > 0,
                );
                if (v > 0) HapticFeedback.lightImpact();
              },
            ),
            const _SettingsDivider(),
            _SliderTile(
              icon:         Icons.light_mode_outlined,
              title:        'LED brightness',
              subtitle:     'NeoPixel depth bar on glove. Drag to 0 to turn off.',
              value:        settings.gloveLedBrightness,
              min:          AppConstants.diagLedBrightnessMin,
              max:          AppConstants.diagLedBrightnessMax,
              labelBuilder: (v) => v == 0
                  ? 'Off'
                  : '${(v * 100 / AppConstants.diagLedBrightnessMax).round()}%',
              onChanged:   (v) => notifier.setGloveLedBrightnessLive(v),
              onChangeEnd: (v) {
                notifier.setGloveLedBrightnessPersist(v);
                final s = ref.read(settingsProvider);
                final ble = ref.read(bleConnectionProvider);
                if (ble.isConnected) {
                  ble.sendSetLedBrightness(v);
                  ble.sendSetFeedbackChannels(
                    audio:  s.audioVolume > 0,
                    haptic: s.hapticIntensity > 0,
                    visual: v > 0,
                  );
                }
              },
            ),
          ]),

// ── CPR Session ──────────────────────────────────────────────────
          const _SectionHeader(label: 'CPR Session'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:      Icons.switch_right_outlined,
              title:     'Auto-switch to Live CPR',
              subtitle:  'Navigate automatically when glove detects CPR start',
              value:     settings.autoSwitchToCPR,
              onChanged: (v) => notifier.setAutoSwitchToCPR(v),
            ),
            const _SettingsDivider(),
            _SelectTile(
              icon:     Icons.air_rounded,
              title:    'Ventilation cycle',
              subtitle: 'Ventilation frequency',
              options:  const ['30:2', '15:2', 'None'],
              selected: _ventLabel(settings.ventilationRatio),
              onChanged: (v) {
                final key = _ventKey(v);
                notifier.setVentilationRatio(key);
                final bleConn = ref.read(bleConnectionProvider);
                if (bleConn.isConnected) {
                  int comps = 30, breaths = 2;
                  if      (key == '15:2')              { comps = 15; breaths = 2; }
                  else if (key == 'compressions_only') { comps = 0;  breaths = 0; }
                  bleConn.sendSetVentilation(
                    compressionsPerCycle: comps,
                    ventilationsPerPause: breaths,
                  );
                }
              },
            ),
          ]),

// ── Display ──────────────────────────────────────────────────────
          const _SectionHeader(label: 'Display'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:      Icons.screen_lock_portrait_outlined,
              title:     'Keep screen on',
              subtitle:  'Prevent screen timeout during CPR sessions',
              value:     settings.keepScreenOn,
              onChanged: (v) => notifier.setKeepScreenOn(v),
            ),
          ]),

// ── Data & Sync ──────────────────────────────────────────────────
          const _SectionHeader(label: 'Data & Sync'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:      Icons.wifi_rounded,
              title:     'Sync on Wi-Fi only',
              subtitle:  'Sessions sync only when on Wi-Fi',
              value:     settings.syncWifiOnly,
              onChanged: (v) => notifier.setSyncWifiOnly(v),
            ),
            const _SettingsDivider(),
            _NavTile(
              icon:     Icons.cleaning_services_outlined,
              title:    'Clear app cache',
              subtitle: 'Free up space',
              onTap:    () => _confirmClearCache(),
            ),
          ]),

// ── Glove Maintenance ────────────────────────────────────────────
          const _SectionHeader(label: 'Glove Maintenance'),
          _SettingsCard(children: [
            _NavTile(
              icon:     Icons.tune_rounded,
              title:    'Recalibrate force sensor',
              subtitle: 'Resets the force sensor zero-point. ',
              onTap:    () => _runCalibration(),
            ),
            const _SettingsDivider(),
            _NavTile(
              icon:     Icons.biotech_outlined,
              title:    'Run sensor check',
              subtitle: 'Tests every glove sensor and shows pass/warn/fail results',
              onTap:    () => _openDiagnosticPanel(),
            ),
          ]),

// ── Reset ────────────────────────────────────────────────────────
          const _SectionHeader(label: 'Reset'),
          _SettingsCard(children: [
            _NavTile(
              icon:     Icons.settings_backup_restore_rounded,
              title:    'Reset settings to defaults',
              subtitle: 'Restore all app settings to their original values',
              onTap:    () => _confirmResetDefaults(),
            ),
          ]),
      const SizedBox(height: AppSpacing.xl),
      ],
      ),
        ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor:        AppColors.white,
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

  Future<void> _runCalibration() async {
    final bleConn = ref.read(bleConnectionProvider);
    if (!bleConn.isConnected) {
      UIHelper.showError(context, 'Glove not connected.');
      return;
    }
    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.tune_rounded,
      iconColor:    AppColors.primary,
      iconBg:       AppColors.primaryLight,
      title:        'Recalibrate force sensor?',
      message:      'This resets the compression force baseline.\n\n'
          '• Rest the glove flat on a table\n'
          '• Do not wear it\n'
          '• Hold it completely still for 2–3 seconds\n\n'
          'The glove will flash and play a tone when done.',
      confirmLabel: 'Calibrate',
      confirmColor: AppColors.primary,
      cancelLabel:  'Cancel',
    );
    if (confirmed != true || !mounted) return;
    ref.read(calibrationPendingProvider.notifier).state = true;
    final ok = await bleConn.sendCalibrate();
    if (!mounted) return;
    if (ok) {
      UIHelper.showInfo(context, 'Calibrating…');
    } else {
      ref.read(calibrationPendingProvider.notifier).state = false;
      UIHelper.showError(context, 'Command failed. Check glove connection.');
    }
  }


  String _ventLabel(String key) {
    switch (key) {
      case '15:2':              return '15:2';
      case 'compressions_only': return 'None';
      default:                  return '30:2';
    }
  }

  String _ventKey(String label) {
    switch (label) {
      case '15:2':      return '15:2';
      case 'None': return 'compressions_only';
      default:          return '30:2';
    }
  }

  void _openDiagnosticPanel() {
    final ble = ref.read(bleConnectionProvider);
    if (!ble.isConnected) {
      UIHelper.showError(context, 'Glove not connected.');
      return;
    }
    ref.read(selftestRequestedProvider.notifier).state = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      builder: (_) => GloveDiagnosticSheet(ble: ble),
    );
  }

  Future<void> _confirmClearCache() async {
    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.cleaning_services_outlined,
      iconColor:    AppColors.warning,
      iconBg:       AppColors.warningBg,
      title:        'Clear app cache?',
      message:      'Cached AED data, routes, and map state will be removed. '
          'Your sessions and account are not affected.',
      confirmLabel: 'Clear',
      confirmColor: AppColors.warning,
      cancelLabel:  'Cancel',
    );
    if (confirmed != true || !mounted) return;
    await CacheService.clearAllCache();
    if (mounted) UIHelper.showSuccess(context, 'Cache cleared');
  }

  Future<void> _confirmResetDefaults() async {
    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.settings_backup_restore_rounded,
      iconColor:    AppColors.warning,
      iconBg:       AppColors.warningBg,
      title:        'Reset to Defaults?',
      message:      'All settings will be restored to their original values.',
      confirmLabel: 'Reset',
      confirmColor: AppColors.warning,
      cancelLabel:  'Cancel',
    );
    if (confirmed != true || !mounted) return;
    await ref.read(settingsProvider.notifier).resetToDefaults();
    if (mounted) UIHelper.showSuccess(context, 'Settings reset to defaults');
  }

  @override
  void dispose() {
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slider tile
// ─────────────────────────────────────────────────────────────────────────────

class _SliderTile extends StatelessWidget {
  final IconData              icon;
  final String                title;
  final String?               subtitle;
  final int                   value;
  final int                   min;
  final int                   max;
  final String Function(int)? labelBuilder;
  final ValueChanged<int>     onChanged;
  final ValueChanged<int>? onChangeEnd;

  const _SliderTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    this.labelBuilder,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final label = labelBuilder?.call(value) ?? value.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.bodyMedium(size: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xl,
            ),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
              ),
              child: Slider(
                value:         value.toDouble(),
                min:           min.toDouble(),
                max:           max.toDouble(),
                activeColor:   AppColors.primary,
                inactiveColor: AppColors.primaryMid.withValues(alpha: 0.3),
                onChanged:     (d) => onChanged(d.round()),
                onChangeEnd:  onChangeEnd == null ? null : (d) => onChangeEnd!(d.round()),
              ),
            ),
          ),
        ],
      ),
    );
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
        AppSpacing.cardRadiusSm,
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
      endIndent: AppSpacing.md + AppSpacing.sm,
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
        vertical:   AppSpacing.sm,
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
          const SizedBox(width: AppSpacing.sm),
          Switch(
            value:            value,
            onChanged:        onChanged,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primaryMid,
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
  final String               subtitle;
  final List<String>         options;
  final String               selected;
  final ValueChanged<String> onChanged;

  const _SelectTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyMedium(size: 14)),
                Text(subtitle, style: AppTypography.caption()),
              ],
            ),
          ),
          Container(
            decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadiusLg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: options.map((opt) {
                final isSelected = opt == selected;
                return GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.cardRadiusMd,
                      vertical:   AppSpacing.cardSpacing,
                    ),
                    decoration: isSelected
                        ? AppDecorations.segmentSelected()
                        : AppDecorations.segmentUnselected(),
                    child: Text(
                      opt,
                      style: AppTypography.buttonSmall(
                        size: 12,
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
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.sm,
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
            const SizedBox(width: AppSpacing.sm),
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
      width:  AppSpacing.iconBoxSize,
      height: AppSpacing.iconBoxSize,
      decoration: AppDecorations.iconRounded(
        bg:     c.withValues(alpha: 0.1),
        radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
      ),
      child: Icon(icon, color: c, size: AppSpacing.iconSm),
    );
  }
}
