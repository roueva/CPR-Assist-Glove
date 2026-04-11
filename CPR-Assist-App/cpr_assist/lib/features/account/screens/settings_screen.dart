import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  StreamSubscription? _selftestSub;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

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
          subtitle: 'Warn if glove loses connection during an active session',
          value:    settings.notifyOnDisconnect,
          onChanged: (v) => notifier.setNotifyOnDisconnect(v),
        ),
        const _SettingsDivider(),
        _NavTile(
          icon:     Icons.tune_rounded,
          title:    'Recalibrate sensors',
          subtitle: 'Run if force readings seem inaccurate',
          onTap:    () => _runCalibration(),
        ),
        const _SettingsDivider(),
        _NavTile(
          icon:     Icons.biotech_outlined,
          title:    'Run glove self-test',
          subtitle: 'Check all sensors and battery status',
          onTap:    () => _runSelftest(),
        ),
      ]),

// ── Glove Feedback ───────────────────────────────────────────────
      const _SectionHeader(label: 'Glove Feedback'),
      _SettingsCard(children: [
        _ToggleTile(
          icon:     Icons.vibration_rounded,
          title:    'Haptic feedback',
          subtitle: 'Vibrate glove on compression detection',
          value:    settings.hapticFeedback,
          onChanged: (v) {
            notifier.setHapticFeedback(v);
            if (v) HapticFeedback.lightImpact();
            // ⚠️ TODO(firmware): replace with per-channel bitmask when 0xFE available
            final any = v || settings.audioFeedback || settings.visualFeedback;
            ref.read(bleConnectionProvider).sendFeedbackSet(enabled: any);
          },
        ),
        const _SettingsDivider(),
        _ToggleTile(
          icon:     Icons.volume_up_outlined,
          title:    'Audio feedback',
          subtitle: 'Spoken pace cues during CPR',
          value:    settings.audioFeedback,
          onChanged: (v) {
            notifier.setAudioFeedback(v);
            // ⚠️ TODO(firmware): replace with per-channel bitmask when 0xFE available
            final any = settings.hapticFeedback || v || settings.visualFeedback;
            ref.read(bleConnectionProvider).sendFeedbackSet(enabled: any);
          },
        ),
        const _SettingsDivider(),
        // ⚠️ TODO(firmware): visual feedback (NeoPixels) currently shares the same
        // 0xF2 sendFeedbackSet boolean as haptic+audio. When firmware implements
        // 0xFE SET_FEEDBACK_CHANNELS with a bitmask, wire this toggle separately.
        _ToggleTile(
          icon:     Icons.light_mode_outlined,
          title:    'Visual feedback',
          subtitle: 'NeoPixel LED depth bar and alerts on glove',
          value:    settings.visualFeedback,
          onChanged: (v) {
            notifier.setVisualFeedback(v);
            final any = settings.hapticFeedback || settings.audioFeedback || v;
            ref.read(bleConnectionProvider).sendFeedbackSet(enabled: any);
          },
        ),
      ]),

// ── Screen Feedback ──────────────────────────────────────────────
      const _SectionHeader(label: 'Screen Feedback'),
      _SettingsCard(children: [
        _ToggleTile(
          icon:     Icons.monitor_heart_outlined,
          title:    'Show CPR metrics',
          subtitle: 'Display depth, rate and coaching during CPR. '
              'When off, only vitals are shown.',
          value:    settings.showCprMetrics,
          onChanged: (v) => notifier.setShowCprMetrics(v),
        ),
        const _SettingsDivider(),
        _ToggleTile(
          icon:     Icons.checklist_rounded,
          title:    'Pre-session checklist',
          subtitle: 'Confirm setup before each training session starts',
          value:    settings.showChecklist,
          onChanged: (v) => notifier.setShowChecklist(v),
        ),
      ]),

// ── CPR Session ──────────────────────────────────────────────────
      const _SectionHeader(label: 'CPR Session'),
      _SettingsCard(children: [
        _ToggleTile(
          icon:     Icons.switch_right_outlined,
          title:    'Auto-switch to Live CPR',
          subtitle: 'Navigate automatically when glove detects CPR start',
          value:    settings.autoSwitchToCPR,
          onChanged: (v) => notifier.setAutoSwitchToCPR(v),
        ),
        const _SettingsDivider(),
        _ToggleTile(
          icon:     Icons.visibility_off_rounded,
          title:    'No-Feedback mode as default',
          subtitle: 'Start training without glove cues — for self-assessment',
          value:    settings.noFeedbackMode,
          onChanged: (v) async {
            await notifier.setNoFeedbackMode(v);
            final current = ref.read(appModeProvider);
            if (current.isTraining) {
              final newMode = v ? AppMode.trainingNoFeedback : AppMode.training;
              ref.read(appModeProvider.notifier).setMode(newMode);
              ref.read(bleConnectionProvider).sendModeSet(newMode.bleValue);
            }
          },
        ),
        const _SettingsDivider(),
        _SelectTile(
          icon:      Icons.medical_services_outlined,
          title:     'Default scenario',
          options:   const ['Adult', 'Pediatric'],
          selected:  _scenarioLabel(settings.defaultScenario),
          onChanged: (v) => notifier.setDefaultScenario(_scenarioKey(v)),
        ),
        const _SettingsDivider(),
        _SelectTile(
          icon:      Icons.mode_standby_outlined,
          title:     'Default mode',
          options:   const ['Emergency', 'Training'],
          selected:  settings.defaultMode == 'training' ? 'Training' : 'Emergency',
          onChanged: (v) => notifier.setDefaultMode(
            v == 'Training' ? 'training' : 'emergency',
          ),
        ),
      ]),

// ── Display ──────────────────────────────────────────────────────
      const _SectionHeader(label: 'Display'),
      _SettingsCard(children: [
        _ToggleTile(
          icon:     Icons.screen_lock_portrait_outlined,
          title:    'Keep screen on',
          subtitle: 'Prevent screen timeout during CPR sessions',
          value:    settings.keepScreenOn,
          onChanged: (v) => notifier.setKeepScreenOn(v),
        ),
        const _SettingsDivider(),
        _SelectTile(
          icon:      Icons.straighten_rounded,
          title:     'Depth unit',
          options:   const ['cm', 'in'],
          selected:  settings.compressionUnit,
          onChanged: (v) => notifier.setCompressionUnit(v),
        ),
      ]),

// ── Notifications ────────────────────────────────────────────────
      const _SectionHeader(label: 'Notifications'),
      _SettingsCard(children: [
        _ToggleTile(
          icon:     Icons.fitness_center_outlined,
          title:    'Training reminders',
          subtitle: 'Get reminded to keep your CPR skills sharp',
          value:    settings.trainingReminders,
          onChanged: (v) => notifier.setTrainingReminders(v),
        ),
        if (settings.trainingReminders) ...[
          const _SettingsDivider(),
          _SelectTile(
            icon:      Icons.schedule_outlined,
            title:     'Reminder frequency',
            options:   const ['Daily', 'Weekly'],
            selected:  settings.reminderFrequency == 'daily' ? 'Daily' : 'Weekly',
            onChanged: (v) => notifier.setReminderFrequency(
              v == 'Daily' ? 'daily' : 'weekly',
            ),
          ),
        ],
        const _SettingsDivider(),
        _ToggleTile(
          icon:     Icons.emoji_events_outlined,
          title:    'Achievement alerts',
          subtitle: 'Notify when you unlock a new achievement',
          value:    settings.achievementAlerts,
          onChanged: (v) => notifier.setAchievementAlerts(v),
        ),
        const _SettingsDivider(),
        // ⚠️ TODO: Nearby emergency alerts require backend support — a POST endpoint
        // to register active emergency sessions with coordinates, FCM/APNs push tokens,
        // and a background geofence listener. Wire this toggle when that is built.
        _ToggleTile(
          icon:     Icons.place_outlined,
          title:    'Nearby emergency alerts',
          subtitle: 'Get notified when CPR is needed near you',
          value:    settings.nearbyEmergencyAlerts,
          onChanged: (v) {
            if (v) {
              AppDialogs.showAlert(
                context,
                icon:      Icons.place_outlined,
                iconColor: AppColors.primary,
                iconBg:    AppColors.primaryLight,
                title:     'Coming Soon',
                message:   'Nearby emergency notifications will be '
                    'available in a future update.',
              );
              return;
            }
            notifier.setNearbyEmergencyAlerts(false);
          },
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

  Future<void> _runCalibration() async {
    final bleConn = ref.read(bleConnectionProvider);
    if (!bleConn.isConnected) {
      UIHelper.showError(context, 'Glove not connected.');
      return;
    }
    final ok = await bleConn.sendCalibrate();
    if (!mounted) return;
    if (ok) {
      UIHelper.showSuccess(context, 'Calibration started — keep glove still.');
    } else {
      UIHelper.showError(context, 'Calibration command failed. Try again.');
    }
  }

  Future<void> _runSelftest() async {
    final ble = ref.read(bleConnectionProvider);
    if (!ble.isConnected) {
      UIHelper.showError(context, 'Glove not connected.');
      return;
    }
    ref.read(selftestRequestedProvider.notifier).state = true;
    final ok = await ble.sendRunSelftest();
    if (!mounted) return;
    if (!ok) {
      ref.read(selftestRequestedProvider.notifier).state = false;
      UIHelper.showError(context, 'Self-test command failed.');
    } else {
      UIHelper.showSnackbar(
        context,
        message: 'Self-test running — results in a moment',
        icon: Icons.hourglass_top_rounded,
      );
    }
    _selftestSub?.cancel();
    _selftestSub = ref.read(bleConnectionProvider).dataStream
        .where((d) => d['isSelftestResult'] == true)
        .take(1)
        .listen((data) {
      if (!mounted) return;
      _selftestSub = null;
      ref.read(selftestRequestedProvider.notifier).state = false;
      _showSelftestResult(data);
    });
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

  String _scenarioLabel(String key) {
    return key == 'pediatric' ? 'Pediatric' : 'Adult';
  }

  String _scenarioKey(String label) {
    return label == 'Pediatric' ? 'pediatric' : 'standard_adult';
  }


  void _showSelftestResult(Map<String, dynamic> data) {
    final warn     = (data['selftestWarnMask']     as int?) ?? 0;
    final critical = (data['selftestCriticalMask'] as int?) ?? 0;
    final battery  = (data['selftestBatteryPct']   as int?) ?? 0;

    const sensorNames = [
      'IMU 1', 'IMU 2', 'Force sensor',
      'Fingertip optical', 'Wrist optical',
      'Temperature (MAX30205)', 'Humidity (GXHT30)', 'Audio (DFPlayer)',
    ];
    final failed   = <String>[];
    final warnings = <String>[];
    for (int i = 0; i < sensorNames.length; i++) {
      if (critical & (1 << i) != 0) {
        failed.add(sensorNames[i]);
      } else if (warn & (1 << i) != 0) warnings.add(sensorNames[i]);
    }
    final allPassed = failed.isEmpty && warnings.isEmpty;
    final parts = <String>[];
    if (failed.isNotEmpty)   parts.add('Failed: ${failed.join(', ')}.');
    if (warnings.isNotEmpty) parts.add('Warnings: ${warnings.join(', ')}.');
    parts.add('Battery: $battery%.');

    AppDialogs.showAlert(
      context,
      icon:      allPassed ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
      iconColor: allPassed ? AppColors.success : AppColors.emergencyRed,
      iconBg:    allPassed ? AppColors.successBg : AppColors.emergencyBg,
      title:     allPassed ? 'Glove Ready' : 'Sensor Issue Detected',
      message:   allPassed ? 'All sensors passed. Battery: $battery%.' : parts.join('\n'),
    );
  }

  @override
  void dispose() {
    _selftestSub?.cancel();
    super.dispose();
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
                    decoration: isSelected
                        ? AppDecorations.segmentSelected()
                        : AppDecorations.segmentUnselected(),
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
