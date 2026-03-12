import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';
import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:cpr_assist/features/training/services/session_detail.dart';
import 'package:cpr_assist/features/training/screens/past_sessions_screen.dart';
import 'package:cpr_assist/features/training/widgets/grade_card.dart';
import 'package:cpr_assist/features/training/widgets/grade_dialog.dart';
import 'package:cpr_assist/features/training/widgets/session_card.dart';
import 'package:cpr_assist/features/account/screens/settings_screen.dart';
import 'package:cpr_assist/features/account/screens/help_about_screen.dart';
import 'package:cpr_assist/features/account/screens/login_screen.dart';
import 'package:cpr_assist/features/account/screens/registration_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEV ONLY — UI Preview Screen
// Remove the entry point in account_menu.dart before releasing.
// ─────────────────────────────────────────────────────────────────────────────

// ── Mock SessionDetail — for GradeCard and GradeDialog ────────────────────

SessionDetail _mockDetail({
  double grade = 87,
  int compressions = 142,
  int correctDepth = 118,
  int correctFrequency = 130,
  int correctRecoil = 105,
  int depthRateCombo = 98,
  double avgDepth = 5.4,
  double avgFrequency = 112,
  int durationSecs = 183,
  int? userHr,
}) =>
    SessionDetail(
      sessionStart:           DateTime.now().subtract(const Duration(hours: 2)),
      compressionCount:       compressions,
      correctDepth:           correctDepth,
      correctFrequency:       correctFrequency,
      correctRecoil:          correctRecoil,
      depthRateCombo:         depthRateCombo,
      averageDepth:           avgDepth,
      averageFrequency:       avgFrequency,
      sessionDuration:        durationSecs,
      totalGrade:             grade,
      noFlowTime:             4.2,
      handsOnRatio:           0.88,
      timeToFirstCompression: 1.8,
      depthConsistency:       83,
      frequencyConsistency:   91,
      userHeartRate:          userHr,
      compressions:           [],
    );

// ── Mock SessionSummary — for SessionCard and PersonalBestCard ─────────────

SessionSummary _mockSummary({
  double grade = 87,
  int compressions = 142,
  int correctDepth = 118,
  int correctFrequency = 130,
  int correctRecoil = 105,
  int depthRateCombo = 98,
  double avgDepth = 5.4,
  double avgFrequency = 112,
  int durationSecs = 183,
  int? userHr,
}) =>
    SessionSummary(
      totalGrade:       grade,
      compressionCount: compressions,
      correctDepth:     correctDepth,
      correctFrequency: correctFrequency,
      correctRecoil:    correctRecoil,
      depthRateCombo:   depthRateCombo,
      averageDepth:     avgDepth,
      averageFrequency: avgFrequency,
      sessionDuration:  durationSecs,
      sessionStart:     DateTime.now().subtract(const Duration(hours: 2)),
      userHeartRate:    userHr,
    );

final _mockSessions = [
  _mockSummary(grade: 94, compressions: 160, correctDepth: 150, durationSecs: 210),
  _mockSummary(grade: 87, compressions: 142, correctDepth: 118, durationSecs: 183),
  _mockSummary(grade: 72, compressions: 98,  correctDepth: 75,  durationSecs: 140),
  _mockSummary(grade: 55, compressions: 80,  correctDepth: 44,  durationSecs: 95),
  _mockSummary(grade: 91, compressions: 155, correctDepth: 140, durationSecs: 200, userHr: 95),
];

// ─────────────────────────────────────────────────────────────────────────────
// DevPreviewScreen
// ─────────────────────────────────────────────────────────────────────────────

class DevPreviewScreen extends StatelessWidget {
  const DevPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text('UI Preview', style: AppTypography.heading(size: 18)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.chipPaddingH,
              vertical: AppSpacing.chipPaddingV,
            ),
            decoration: AppDecorations.chip(
              color: AppColors.warning,
              bg: AppColors.warningBg,
            ),
            child: Text('DEV ONLY', style: AppTypography.badge(color: AppColors.warning)),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
        ),
        children: [

          // ── Screens ────────────────────────────────────────────────────
          const _SectionHeader(label: 'Screens'),
          _PreviewCard(children: [
            _NavTile(
              icon: Icons.history_rounded,
              label: 'Past Sessions Screen',
              subtitle: 'Full training history with filters',
              onTap: () => context.push(const PastSessionsScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.settings_outlined,
              label: 'Settings Screen',
              onTap: () => context.push(const SettingsScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.help_outline_rounded,
              label: 'Help & About Screen',
              onTap: () => context.push(const HelpAboutScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.login_rounded,
              label: 'Login Screen',
              onTap: () => context.push(const LoginScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.person_add_outlined,
              label: 'Registration Screen',
              onTap: () => context.push(const RegistrationScreen()),
            ),
          ]),

          // ── Grade UI ───────────────────────────────────────────────────
          const _SectionHeader(label: 'Grade UI'),
          _PreviewCard(children: [
            _NavTile(
              icon: Icons.bar_chart_rounded,
              label: 'Grade Card (inline)',
              subtitle: 'The gradient card shown after a session',
              onTap: () => context.push(_GradeCardPreviewScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.open_in_new_rounded,
              label: 'Grade Dialog',
              subtitle: '"Session Complete!" popup',
              onTap: () => showDialog(
                context: context,
                barrierColor: AppColors.overlayDark,
                builder: (_) => GradeDialog(session: _mockDetail()),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.emoji_events_outlined,
              label: 'Session Details Sheet',
              subtitle: 'Bottom sheet from tapping a session card',
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: AppColors.overlayLight,
                builder: (_) => SessionDetailsSheet(
                  session: _mockSummary(userHr: 98),
                  sessionNumber: 3,
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.star_outline_rounded,
              label: 'Personal Best Card (inline)',
              subtitle: 'Gradient highlight for best session',
              onTap: () => context.push(_PersonalBestPreviewScreen()),
            ),
          ]),

          // ── App Dialogs ────────────────────────────────────────────────
          const _SectionHeader(label: 'App Dialogs'),
          _PreviewCard(children: [
            _NavTile(
              icon: Icons.logout_rounded,
              iconColor: AppColors.emergencyRed,
              label: 'Confirm Logout',
              onTap: () => AppDialogs.confirmLogout(context),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.school_outlined,
              iconColor: AppColors.warning,
              label: 'Switch to Training Mode',
              onTap: () => AppDialogs.confirmSwitchToTraining(context),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.emergency_outlined,
              label: 'Switch to Emergency Mode',
              onTap: () => AppDialogs.confirmSwitchToEmergency(context),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.lock_outline_rounded,
              label: 'Login Required Prompt',
              onTap: () => AppDialogs.promptLogin(context),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.edit_off_rounded,
              iconColor: AppColors.warning,
              label: 'Discard Changes',
              onTap: () => AppDialogs.confirmDiscard(context),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.delete_outline_rounded,
              iconColor: AppColors.emergencyRed,
              label: 'Destructive Confirm (Delete)',
              onTap: () => AppDialogs.showDestructiveConfirm(
                context,
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.emergencyRed,
                iconBg: AppColors.emergencyBg,
                title: 'Delete All Data?',
                message: 'This will permanently delete all your training sessions. This cannot be undone.',
                confirmLabel: 'Delete',
                confirmColor: AppColors.emergencyRed,
                cancelLabel: 'Cancel',
              ),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.info_outline_rounded,
              label: 'Info Alert (single button)',
              onTap: () => AppDialogs.showAlert(
                context,
                title: 'Session Saved',
                message: 'Your training session has been saved successfully and is now visible in your history.',
              ),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.location_off_rounded,
              iconColor: AppColors.warning,
              label: 'Location Permission Dialog',
              onTap: () => AppDialogs.showLocationPermissionSettings(context),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.share_outlined,
              label: 'AED Share Dialog',
              onTap: () => AppDialogs.showAEDShare(
                context,
                aedName: 'AED — Athens Medical Centre, Entrance B',
                latitude: 37.9838,
                longitude: 23.7275,
              ),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.phone_outlined,
              iconColor: AppColors.emergencyRed,
              label: 'Simulation 112 Call',
              onTap: () => AppDialogs.showSimulation112(context),
            ),
          ]),

          // ── Snackbars ──────────────────────────────────────────────────
          const _SectionHeader(label: 'Snackbars'),
          _PreviewCard(children: [
            _NavTile(
              icon: Icons.check_circle_outline_rounded,
              iconColor: AppColors.success,
              label: 'Success Snackbar',
              onTap: () => UIHelper.showSuccess(context, 'Session saved successfully'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.error_outline_rounded,
              iconColor: AppColors.error,
              label: 'Error Snackbar',
              onTap: () => UIHelper.showError(context, 'Failed to connect. Check your connection.'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.warning_amber_rounded,
              iconColor: AppColors.warning,
              label: 'Warning Snackbar',
              onTap: () => UIHelper.showWarning(context, 'Glove battery below 20%'),
            ),
            const _Divider(),
            _NavTile(
              icon: Icons.info_outline_rounded,
              label: 'Info Snackbar',
              onTap: () => UIHelper.showSnackbar(
                context,
                message: 'Searching for nearby AEDs…',
                icon: Icons.search_rounded,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Inline preview screens
// ─────────────────────────────────────────────────────────────────────────────

class _GradeCardPreviewScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text('Grade Card', style: AppTypography.heading(size: 18)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            Text('Grade: 94% — Excellent',
                style: AppTypography.label(color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.sm),
            GradeCard(session: _mockDetail(grade: 94, compressions: 160, correctDepth: 150)),
            const SizedBox(height: AppSpacing.xl),
            Text('Grade: 72% — Good',
                style: AppTypography.label(color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.sm),
            GradeCard(session: _mockDetail(grade: 72, compressions: 98, correctDepth: 65, correctFrequency: 80)),
            const SizedBox(height: AppSpacing.xl),
            Text('Grade: 45% — Needs Improvement',
                style: AppTypography.label(color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.sm),
            GradeCard(session: _mockDetail(grade: 45, compressions: 60, correctDepth: 22, correctFrequency: 30, correctRecoil: 15)),
          ],
        ),
      ),
    );
  }
}

class _PersonalBestPreviewScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor: AppColors.headerBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text('Personal Best Card', style: AppTypography.heading(size: 18)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: PersonalBestCard(
          session: _mockSummary(
            grade: 94, compressions: 160,
            avgDepth: 5.6, avgFrequency: 114, durationSecs: 210,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Local helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.cardSpacing,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.badge(color: AppColors.textDisabled),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final List<Widget> children;
  const _PreviewCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: AppSpacing.dividerThickness,
      thickness: AppSpacing.dividerThickness,
      color: AppColors.divider,
      indent: AppSpacing.md + AppSpacing.touchTargetMin,
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    this.iconColor,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        child: Row(
          children: [
            Container(
              width: AppSpacing.touchTargetMin - AppSpacing.sm,
              height: AppSpacing.touchTargetMin - AppSpacing.sm,
              decoration: AppDecorations.iconRounded(
                bg: color.withValues(alpha: 0.1),
                radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
              ),
              child: Icon(icon, color: color, size: AppSpacing.iconSm),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodyMedium(size: 14)),
                  if (subtitle != null)
                    Text(subtitle!, style: AppTypography.caption()),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: AppSpacing.iconSm,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}