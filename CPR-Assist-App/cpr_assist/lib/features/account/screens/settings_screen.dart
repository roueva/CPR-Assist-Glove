import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../training/services/export_service.dart';

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
              subtitle: 'Notify when glove loses BLE connection',
              value:    settings.notifyOnDisconnect,
              onChanged: (v) => notifier.setNotifyOnDisconnect(v),
            ),
            const _SettingsDivider(),
            _GloveTile(),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.switch_right_outlined,
              title:    'Auto-switch to Live CPR',
              subtitle: 'Navigate automatically when glove detects CPR start',
              value:    settings.autoSwitchToCPR,
              onChanged: (v) => notifier.setAutoSwitchToCPR(v),
            ),
            const _SettingsDivider(),
            _NavTile(
              icon:     Icons.tune_rounded,
              title:    'Calibrate glove',
              subtitle: 'Run force baseline + brightness calibration',
              onTap:    () => _runCalibration(),
            ),

            const _SettingsDivider(),
            _NavTile(
              icon:     Icons.biotech_outlined,
              title:    'Run glove self-test',
              subtitle: 'Check all sensors and battery status',
              onTap:    () => _runSelftest(),
            ),
            const _SettingsDivider(),
            _NavTile(
              icon:     Icons.play_circle_outline_rounded,
              title:    'App tutorial',
              subtitle: 'Coming in a future update',
              onTap:    () => _showTutorialComingSoon(),
            ),
          ]),

          // ── Feedback ────────────────────────────────────────────────────
          const _SectionHeader(label: 'Feedback'),
          _SettingsCard(children: [
            _ToggleTile(
              icon:     Icons.vibration_rounded,
              title:    'Haptic feedback',
              subtitle: 'Vibrate on compression detection',
              value:    settings.hapticFeedback,
              onChanged: (v) {
                notifier.setHapticFeedback(v);
                if (v) HapticFeedback.lightImpact();
                final audio = ref.read(settingsProvider).audioFeedback;
                ref.read(bleConnectionProvider).sendFeedbackSet(enabled: v || audio);
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
                final haptic = ref.read(settingsProvider).hapticFeedback;
                ref.read(bleConnectionProvider).sendFeedbackSet(enabled: v || haptic);
              },
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.straighten_outlined,
              title:    'Show depth guide',
              subtitle: 'Display target compression depth on screen',
              value:    settings.showDepthGuide,
              onChanged: (v) => notifier.setShowDepthGuide(v),
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.speed_outlined,
              title:    'Show rate guide',
              subtitle: 'Display target compression rate on screen',
              value:    settings.showRateGuide,
              onChanged: (v) => notifier.setShowRateGuide(v),
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.checklist_rounded,
              title:    'Pre-session checklist',
              subtitle: 'Show setup checklist before each training session',
              value:    settings.showChecklist,
              onChanged: (v) => notifier.setShowChecklist(v),
            ),
            const _SettingsDivider(),
            _ToggleTile(
              icon:     Icons.visibility_off_rounded,
              title:    'No-Feedback training',
              subtitle: 'Suppresses all glove cues — for self-assessment',
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
          ]),

          // ── Display ─────────────────────────────────────────────────────
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

          // ── Data & Privacy ───────────────────────────────────────────────
          const _SectionHeader(label: 'Data & Privacy'),
          _SettingsCard(children: [
            _NavTile(
              icon:     Icons.download_outlined,
              title:    'Export session data',
              subtitle:  'Download all sessions (training + emergency) as CSV',
              onTap: () => _exportData(),
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
            const _SettingsDivider(),
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

  void _showTutorialComingSoon() {
    AppDialogs.showAlert(
      context,
      icon:      Icons.play_circle_outline_rounded,
      iconColor: AppColors.primary,
      iconBg:    AppColors.primaryLight,
      title:     'Tutorial',
      message:   'The tutorial walkthrough will be available in a future update.',
    );
  }

  Future<void> _confirmDeleteData() async {
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
    if (!isLoggedIn) {
      UIHelper.showSnackbar(
        context,
        message: 'Sign in to manage session data',
        icon:    Icons.lock_outline_rounded,
      );
      return;
    }

    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.delete_outline_rounded,
      iconColor:    AppColors.emergencyRed,
      iconBg:       AppColors.emergencyBg,
      title:        'Delete All Data?',
      message:      'This will permanently delete all your training sessions '
          'and scores. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.emergencyRed,
      cancelLabel:  'Cancel',
    );

    if (confirmed != true || !mounted) return;

    final service = ref.read(sessionServiceProvider);
    final ok = await service.deleteAllSessions();
    if (!mounted) return;
    if (ok) {
      ref.invalidate(sessionSummariesProvider);
      UIHelper.showSuccess(context, 'All session data deleted');
    } else {
      UIHelper.showError(context, 'Failed to delete. Check your connection.');
    }
  }

  Future<void> _exportData() async {
    final summaries = ref.read(sessionSummariesProvider);
    final sessions  = summaries.valueOrNull ?? [];
    if (sessions.isEmpty) {
      UIHelper.showSnackbar(context,
          message: 'No sessions to export', icon: Icons.info_outline_rounded);
      return;
    }
    UIHelper.showSnackbar(context,
        message: 'Preparing export…', icon: Icons.download_outlined);
    final ok = await ExportService.exportSessionsAsCsv(sessions);
    if (!ok && mounted) {
      UIHelper.showError(context, 'Export failed. Please try again.');
    }
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
class _GloveTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ble        = ref.watch(bleConnectionProvider);
    return ValueListenableBuilder<String>(
      valueListenable: ble.connectionStatusNotifier,
      builder: (context, status, _) {
        final isConnected = status == 'Connected';
        return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical:   AppSpacing.cardPadding - AppSpacing.xxs,
            ),
            child: Row(
              children: [
                const _IconBox(icon: Icons.watch_rounded),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CPR Assist Glove',
                          style: AppTypography.bodyMedium(size: 14)),
                      Text(
                        isConnected ? 'Connected' : 'Not connected',
                        style: AppTypography.caption(
                          color: isConnected ? AppColors.success : AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical:   AppSpacing.xs,
                  ),
                  decoration: AppDecorations.chip(
                    color: isConnected ? AppColors.success : AppColors.textDisabled,
                    bg:    isConnected ? AppColors.successBg : AppColors.screenBgGrey,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        size:  10,
                        color: isConnected ? AppColors.success : AppColors.textDisabled,
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Text(
                        isConnected ? 'BLE' : 'Offline',
                        style: AppTypography.badge(
                          size:  10,
                          color: isConnected ? AppColors.success : AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
        );
      },
    );
  }
}