import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

// Screens
import 'package:cpr_assist/features/account/screens/login_screen.dart';
import 'package:cpr_assist/features/account/screens/registration_screen.dart';
import 'package:cpr_assist/features/account/screens/forgot_password_screen.dart';
import 'package:cpr_assist/features/account/screens/reset_password_screen.dart';
import 'package:cpr_assist/features/account/screens/profile_editor_screen.dart';
import 'package:cpr_assist/features/account/screens/settings_screen.dart';
import 'package:cpr_assist/features/account/screens/help_about_screen.dart';
import 'package:cpr_assist/features/aed_map/screens/aed_webview_screen.dart';

// Training
import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:cpr_assist/features/training/services/session_detail.dart';
import 'package:cpr_assist/features/training/services/compression_event.dart';
import 'package:cpr_assist/features/training/services/ventilation_event.dart';
import 'package:cpr_assist/features/training/services/pulse_check_event.dart';
import 'package:cpr_assist/features/training/services/rescuer_vital_snapshot.dart';
import 'package:cpr_assist/features/training/widgets/session_history.dart';
import 'package:cpr_assist/features/training/widgets/session_results.dart';

// Live CPR
import 'package:cpr_assist/features/live_cpr/widgets/live_cpr_widgets.dart';
import 'package:cpr_assist/features/live_cpr/widgets/depth_bar.dart';
import 'package:cpr_assist/features/live_cpr/widgets/rotating_arrow.dart';

// Leaderboard
import 'package:cpr_assist/features/training/screens/leaderboard_screen.dart';

// Other
import '../../providers/app_providers.dart';
import '../account/screens/account_menu.dart';
import '../training/widgets/simulation_112_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEV ONLY — UI Preview Screen
// Remove the entry point in account_menu.dart before releasing.
// ─────────────────────────────────────────────────────────────────────────────

// ── Mock compression events ───────────────────────────────────────────────

List<CompressionEvent> _mockCompressions({int count = 60}) =>
    List.generate(count, (i) => CompressionEvent(
      timestampMs:       i * 950,
      depth:             5.3 + (i % 5 == 0 ? 1.1 : i % 3 == 0 ? -0.9 : 0.2),
      instantaneousRate: 110 + (i % 4 == 0 ? 13.0 : i % 6 == 0 ? -14.0 : 1.5),
      frequency:         110 + (i % 4 == 0 ? 13.0 : i % 6 == 0 ? -14.0 : 1.5),
      recoilAchieved:    i % 7 != 0,
    ));

// ── Mock ventilation events ───────────────────────────────────────────────

List<VentilationEvent> _mockVentilations({int count = 4}) =>
    List.generate(count, (i) => VentilationEvent(
      timestampMs:       (i + 1) * 29000,
      cycleNumber:       i + 1,
      ventilationsGiven: i % 3 == 0 ? 1 : 2,
      durationSec:       3.2 + (i * 0.4),
      compliant:         i % 3 != 0,
    ));

// ── Mock pulse check events ───────────────────────────────────────────────

List<PulseCheckEvent> _mockPulseChecks({bool withPulse = false}) => [
  const PulseCheckEvent(
    timestampMs:    120000,
    intervalNumber: 1,
    classification: 0,
    detectedBpm:    0.0,
    confidence:     72,
    perfusionIndex: 18,
    userDecision:   'continue',
  ),
  if (withPulse) const PulseCheckEvent(
    timestampMs:    240000,
    intervalNumber: 2,
    classification: 2,
    detectedBpm:    64.0,
    confidence:     85,
    perfusionIndex: 42,
    userDecision:   'stop_cpr',
  ),
];

// ── Mock rescuer vitals ───────────────────────────────────────────────────

List<RescuerVitalSnapshot> _mockRescuerVitals() => List.generate(6, (i) =>
    RescuerVitalSnapshot(
      timestampMs:   i * 30000,
      heartRate:     88 + (i * 3.0),
      spO2:          98 - (i * 0.3),
      temperature:   37.1,
      signalQuality: 75 + i,
      pauseType:     i % 2 == 0 ? 'ventilation' : 'active',
      rmssd:         42 - i,
      rescuerPi:     55,
      fatigueScore:  i * 8,
    ));

// ── Mock SessionDetail ────────────────────────────────────────────────────

SessionDetail _mockDetail({
  double grade              = 87,
  int    compressions       = 142,
  int    correctDepth       = 118,
  int    correctFrequency   = 130,
  int    correctRecoil      = 105,
  int    depthRateCombo     = 98,
  double avgDepth           = 5.4,
  double avgFrequency       = 112,
  int    durationSecs       = 183,
  double? userHr,
  String mode               = 'training',
  String scenario           = 'standard_adult',
  bool   withGraphs         = false,
  bool   withVentilations   = false,
  bool   withPulseChecks    = false,
  bool   withRescuerVitals  = false,
}) =>
    SessionDetail(
      sessionStart:           DateTime.now().subtract(const Duration(hours: 2)),
      compressionCount:       compressions,
      correctDepth:           correctDepth,
      correctFrequency:       correctFrequency,
      correctRecoil:          correctRecoil,
      depthRateCombo:         depthRateCombo,
      correctPosture:         (correctRecoil * 0.85).round(),
      leaningCount:           (compressions * 0.04).round(),
      overForceCount:         2,
      averageDepth:           avgDepth,
      averageFrequency:       avgFrequency,
      averageEffectiveDepth:  avgDepth * 0.97,
      peakDepth:              6.1,
      depthConsistency:       83,
      frequencyConsistency:   91,
      handsOnRatio:           0.88,
      noFlowTime:             4.2,
      timeToFirstCompression: 1.8,
      sessionDuration:        durationSecs,
      totalGrade:             mode == 'emergency' ? 0.0 : grade,
      rescuerHRLastPause:     userHr,
      mode:                   mode,
      scenario:               scenario,
      ventilationCount:       withVentilations ? 4 : 0,
      ventilationCompliance:  withVentilations ? 75.0 : 0.0,
      pulseChecksPrompted:    withPulseChecks ? 2 : 0,
      pulseChecksComplied:    withPulseChecks ? 2 : 0,
      pulseDetectedFinal:     withPulseChecks,
      compressions:           withGraphs ? _mockCompressions() : [],
      ventilations:           withVentilations ? _mockVentilations() : [],
      pulseChecks:            withPulseChecks ? _mockPulseChecks(withPulse: mode == 'emergency') : [],
      rescuerVitals:          withRescuerVitals ? _mockRescuerVitals() : [],
    );

// ── Mock SessionSummary ───────────────────────────────────────────────────

SessionSummary _mockSummary({
  double grade            = 87,
  int    compressions     = 142,
  int    correctDepth     = 118,
  int    correctFrequency = 130,
  int    correctRecoil    = 105,
  int    depthRateCombo   = 98,
  double avgDepth         = 5.4,
  double avgFrequency     = 112,
  int    durationSecs     = 183,
  double? userHr,
  String mode = 'training',
  String scenario = 'standard_adult',
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
      rescuerHRLastPause: userHr,
      mode:             mode,
      scenario:         scenario,
    );

final _mockSessions = [
  _mockSummary(grade: 94, compressions: 160, correctDepth: 150, durationSecs: 210),
  _mockSummary(grade: 87, compressions: 142, correctDepth: 118, durationSecs: 183),
  _mockSummary(grade: 72, compressions: 98,  correctDepth: 75,  durationSecs: 140),
  _mockSummary(grade: 55, compressions: 80,  correctDepth: 44,  durationSecs: 95),
  _mockSummary(grade: 91, compressions: 155, correctDepth: 140, durationSecs: 200, userHr: 95),
  _mockSummary(grade: 0,  compressions: 200, correctDepth: 170, durationSecs: 240, mode: 'emergency'),
  _mockSummary(grade: 78, compressions: 120, correctDepth: 100, durationSecs: 160, scenario: 'pediatric'),
  _mockSummary(grade: 82, compressions: 130, correctDepth: 110, durationSecs: 170, mode: 'training_no_feedback'),
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
        backgroundColor:        AppColors.headerBg,
        foregroundColor:        AppColors.textPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('UI Preview', style: AppTypography.heading(size: 18)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: AppSpacing.md),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.chipPaddingH,
              vertical:   AppSpacing.chipPaddingV,
            ),
            decoration: AppDecorations.chip(
              color: AppColors.warning,
              bg:    AppColors.warningBg,
            ),
            child: Text('DEV ONLY',
                style: AppTypography.badge(color: AppColors.warning)),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(height: AppSpacing.dividerThickness,
              color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top:    AppSpacing.sm,
          bottom: AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
        ),
        children: [

          // ── Auth Screens ─────────────────────────────────────────────────
          const _SectionHeader(label: 'Auth Screens'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.login_rounded,
              label:    'Login Screen',
              subtitle: 'Username or email + password',
              onTap:    () => context.push(const LoginScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.person_add_outlined,
              label:    'Registration Screen',
              subtitle: 'Create new account',
              onTap:    () => context.push(const RegistrationScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.lock_reset_rounded,
              label:    'Forgot Password Screen',
              subtitle: 'Enter email → receive reset link',
              onTap:    () => context.push(const ForgotPasswordScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.lock_outline_rounded,
              label:    'Reset Password Screen',
              subtitle: 'Opened via deep link — set new password',
              onTap:    () => context.push(
                const ResetPasswordScreen(token: 'preview_token_dev_123'),
              ),
            ),
          ]),

          // ── Account Screens ──────────────────────────────────────────────
          const _SectionHeader(label: 'Account Screens'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.edit_outlined,
              label:    'Profile Editor Screen',
              subtitle: 'Edit display name and account details',
              onTap:    () => context.push(const ProfileEditorScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.settings_outlined,
              label:    'Settings Screen',
              subtitle: 'App preferences and configuration',
              onTap:    () => context.push(const SettingsScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.help_outline_rounded,
              label:    'Help & About Screen',
              subtitle: 'FAQ, references, app info',
              onTap:    () => context.push(const HelpAboutScreen()),
            ),
          ]),

          // ── Training & Sessions ──────────────────────────────────────────
          const _SectionHeader(label: 'Training & Sessions'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.leaderboard_rounded,
              label:    'Leaderboard Screen',
              subtitle: 'Global · Friends · My Sessions tabs',
              onTap:    () => context.push(const LeaderboardScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.history_rounded,
              label:    'Session History Screen',
              subtitle: 'Full training history with filters',
              onTap:    () => context.push(const SessionHistoryScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.bar_chart_rounded,
              label:    'Session Results — Excellent (94%)',
              subtitle: 'Training · standard adult · no graphs',
              onTap:    () => context.push(
                SessionResultsScreen.fromDetail(
                  detail: _mockDetail(
                    grade: 94, compressions: 160, correctDepth: 150,
                    withVentilations: true,
                  ),
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.show_chart_rounded,
              label:    'Session Results — Good (87%) + Graphs',
              subtitle: 'Training · with depth/rate charts + rescuer HR',
              onTap:    () => context.push(
                SessionResultsScreen.fromDetail(
                  detail: _mockDetail(
                    withGraphs: true, withVentilations: true,
                    withRescuerVitals: true, userHr: 88,
                  ),
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.bar_chart_rounded,
              label:    'Session Results — Needs Work (45%)',
              subtitle: 'Training · low scores across all metrics',
              onTap:    () => context.push(
                SessionResultsScreen.fromDetail(
                  detail: _mockDetail(
                    grade: 45, compressions: 60,
                    correctDepth: 22, correctFrequency: 30, correctRecoil: 15,
                  ),
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.child_care_rounded,
              label:    'Session Results — Pediatric (78%)',
              subtitle: 'Pediatric scenario · 4–5 cm depth target · with graphs',
              onTap:    () => context.push(
                SessionResultsScreen.fromDetail(
                  detail: _mockDetail(
                    grade: 78, scenario: 'pediatric',
                    withGraphs: true, withVentilations: true,
                  ),
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.visibility_off_outlined,
              label:    'Session Results — No-Feedback (82%)',
              subtitle: 'training_no_feedback · blind assessment mode',
              onTap:    () => context.push(
                SessionResultsScreen.fromDetail(
                  detail: _mockDetail(
                    grade: 82, mode: 'training_no_feedback',
                    withGraphs: true,
                  ),
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.emergency_outlined,
              iconColor: AppColors.emergencyRed,
              label:     'Session Results — Emergency',
              subtitle:  'No grade · factual summary · ventilations + pulse checks',
              onTap: () => context.push(
                SessionResultsScreen.fromDetail(
                  detail: _mockDetail(
                    grade: 0, mode: 'emergency',
                    withVentilations: true,
                    withPulseChecks: true,
                    withRescuerVitals: true,
                  ),
                ),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.history_edu_rounded,
              label:    'Session Results — History (Summary mode)',
              subtitle: 'Opened from history card · no flow data · no graphs',
              onTap:    () => context.push(
                SessionResultsScreen.fromSummary(
                  summary:       _mockSummary(userHr: 98),
                  sessionNumber: 3,
                ),
              ),
            ),
          ]),

          // ── Session Cards ────────────────────────────────────────────────
          const _SectionHeader(label: 'Session Cards'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.credit_card_rounded,
              label:    'Session Card List',
              subtitle: '8 mock sessions — training, emergency, pediatric, no-feedback',
              onTap:    () => context.push(const _SessionCardListPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.star_outline_rounded,
              label:    'Personal Best Card',
              subtitle: 'Gradient highlight for best session',
              onTap:    () => context.push(const _PersonalBestPreviewScreen()),
            ),
          ]),

          // ── AED Map ──────────────────────────────────────────────────────
          const _SectionHeader(label: 'AED Map'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.web_rounded,
              label:    'AED WebView Screen',
              subtitle: 'In-app browser for AED detail pages',
              onTap:    () => context.push(
                const AEDWebViewScreen(
                  url:   'https://isaveilves.gr',
                  title: 'iSaveLives',
                ),
              ),
            ),
          ]),

          // ── App Dialogs ──────────────────────────────────────────────────
          const _SectionHeader(label: 'App Dialogs'),
          _PreviewCard(children: [
            _NavTile(
              icon:      Icons.logout_rounded,
              iconColor: AppColors.emergencyRed,
              label:     'Confirm Logout',
              onTap:     () => AppDialogs.confirmLogout(context),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.school_outlined,
              iconColor: AppColors.warning,
              label:     'Switch to Training Mode',
              onTap:     () => AppDialogs.confirmSwitchToTraining(context),
            ),
            const _Divider(),
            _NavTile(
              icon:  Icons.emergency_outlined,
              label: 'Switch to Emergency Mode',
              onTap: () => AppDialogs.confirmSwitchToEmergency(context),
            ),
            const _Divider(),
            _NavTile(
              icon:  Icons.lock_outline_rounded,
              label: 'Login Required Prompt',
              onTap: () => AppDialogs.promptLogin(context),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.edit_off_rounded,
              iconColor: AppColors.warning,
              label:     'Discard Changes',
              onTap:     () => AppDialogs.confirmDiscard(context),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.delete_outline_rounded,
              iconColor: AppColors.emergencyRed,
              label:     'Destructive Confirm (Delete)',
              onTap: () => AppDialogs.showDestructiveConfirm(
                context,
                icon:         Icons.delete_outline_rounded,
                iconColor:    AppColors.emergencyRed,
                iconBg:       AppColors.emergencyBg,
                title:        'Delete All Data?',
                message:      'This will permanently delete all your training sessions. This cannot be undone.',
                confirmLabel: 'Delete',
                confirmColor: AppColors.emergencyRed,
                cancelLabel:  'Cancel',
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:  Icons.info_outline_rounded,
              label: 'Info Alert (single button)',
              onTap: () => AppDialogs.showAlert(
                context,
                title:   'Session Saved',
                message: 'Your training session has been saved successfully.',
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.check_circle_outline_rounded,
              iconColor: AppColors.success,
              label:     'Success Alert (with icon)',
              onTap: () => AppDialogs.showAlert(
                context,
                icon:         Icons.check_circle_outline_rounded,
                iconColor:    AppColors.success,
                iconBg:       AppColors.successBg,
                title:        'Password Reset!',
                message:      'Your password has been updated. You can now log in.',
                dismissLabel: 'Go to Login',
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.location_off_rounded,
              iconColor: AppColors.warning,
              label:     'Location Permission Dialog',
              onTap:     () => AppDialogs.showLocationPermissionSettings(context),
            ),
            const _Divider(),
            _NavTile(
              icon:  Icons.share_outlined,
              label: 'AED Share Dialog',
              onTap: () => AppDialogs.showAEDShare(
                context,
                aedName:   'AED — Athens Medical Centre, Entrance B',
                latitude:  37.9838,
                longitude: 23.7275,
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:  Icons.favorite_border_rounded,
              label: 'Kids Save Lives Info Dialog',
              onTap: () => AppDialogs.showKSLInfo(
                context,
                onVisitWebsite: () {},
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.phone_outlined,
              iconColor: AppColors.emergencyRed,
              label:     'Simulation 112 Call',
              onTap: () => showDialog<void>(
                context: context,
                barrierColor: AppColors.overlayDark,
                builder: (_) => const Simulation112Dialog(),
              ),
            ),
          ]),

          // ── Snackbars ────────────────────────────────────────────────────
          const _SectionHeader(label: 'Snackbars'),
          _PreviewCard(children: [
            _NavTile(
              icon:      Icons.check_circle_outline_rounded,
              iconColor: AppColors.success,
              label:     'Success Snackbar',
              onTap:     () => UIHelper.showSuccess(context, 'Session saved successfully'),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.error_outline_rounded,
              iconColor: AppColors.error,
              label:     'Error Snackbar',
              onTap:     () => UIHelper.showError(context,
                  'Failed to connect. Check your connection.'),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.warning_amber_rounded,
              iconColor: AppColors.warning,
              label:     'Warning Snackbar',
              onTap:     () => UIHelper.showWarning(context,
                  'Glove battery below 20%'),
            ),
            const _Divider(),
            _NavTile(
              icon:  Icons.info_outline_rounded,
              label: 'Info Snackbar',
              onTap: () => UIHelper.showSnackbar(
                context,
                message: 'Searching for nearby AEDs…',
                icon:    Icons.search_rounded,
              ),
            ),
          ]),

          // ── Live CPR Widgets ─────────────────────────────────────────────
          const _SectionHeader(label: 'Live CPR Widgets'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.monitor_heart_outlined,
              label:    'CPR Metrics Card — Active Session',
              subtitle: 'Depth bar + rate gauge + counters running',
              onTap:    () => context.push(const _LiveCprWidgetsPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.monitor_heart_outlined,
              label:    'CPR Metrics Card — Idle',
              subtitle: 'No active session · waiting for glove',
              onTap:    () => context.push(
                const _LiveCprWidgetsPreview(idle: true),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.monitor_heart_outlined,
              label:    'CPR Metrics Card — Pediatric',
              subtitle: 'Scenario: pediatric · 4–5 cm depth target',
              onTap:    () => context.push(
                const _LiveCprWidgetsPreview(scenario: CprScenario.pediatric),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.favorite_border_rounded,
              label:    'Vitals Cards — Active (Patient + Rescuer)',
              subtitle: 'Normal readings during compressions',
              onTap:    () => context.push(const _VitalsCardsPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.favorite_rounded,
              iconColor: AppColors.success,
              label:     'Vitals Cards — Pulse Check Window',
              subtitle:  'Patient vitals active · rescuer at pause · PPG signal',
              onTap:    () => context.push(const _VitalsCardsPulseCheckPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.compress_rounded,
              label:    'Animated Depth Bar',
              subtitle: 'Interactive slider — live compression depth',
              onTap:    () => context.push(const _DepthBarPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.rotate_90_degrees_ccw_rounded,
              label:    'Rotating Arrow (Frequency)',
              subtitle: 'Interactive slider — live CPR rate gauge',
              onTap:    () => context.push(const _RotatingArrowPreview()),
            ),
          ]),

          // ── Shared Widgets ───────────────────────────────────────────────
          const _SectionHeader(label: 'Shared Widgets'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.view_headline_rounded,
              label:    'Universal Header',
              subtitle: 'Main screen + sub-screen variants',
              onTap:    () => context.push(const _UniversalHeaderPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.battery_5_bar_rounded,
              label:    'Glove Battery Indicator',
              subtitle: 'All charge levels + charging state',
              onTap:    () => context.push(const _BatteryWidgetPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.bluetooth_rounded,
              label:    'BLE Status Indicator',
              subtitle: 'Connection state icon variants',
              onTap:    () => context.push(const _BleStatusPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.account_circle_outlined,
              label:    'Account Avatar Button',
              subtitle: 'Logged-in initials vs guest icon',
              onTap:    () => context.push(const _AccountAvatarPreview()),
            ),
          ]),

        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session card list preview
// ─────────────────────────────────────────────────────────────────────────────

class _SessionCardListPreview extends StatelessWidget {
  const _SessionCardListPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Session Cards'),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: _mockSessions.length,
        itemBuilder: (context, i) => SessionCard(
          session:       _mockSessions[i],
          sessionNumber: i + 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Personal best preview
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalBestPreviewScreen extends StatelessWidget {
  const _PersonalBestPreviewScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Personal Best Card'),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: PersonalBestCard(
          session: _mockSummary(
            grade:        94,
            compressions: 160,
            avgDepth:     5.6,
            avgFrequency: 114,
            durationSecs: 210,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live CPR metrics card preview
// ─────────────────────────────────────────────────────────────────────────────

class _LiveCprWidgetsPreview extends StatelessWidget {
  final bool        idle;
  final CprScenario scenario;

  const _LiveCprWidgetsPreview({
    this.idle     = false,
    this.scenario = CprScenario.standardAdult,
  });

  @override
  Widget build(BuildContext context) {
    final title = idle
        ? 'CPR Metrics — Idle'
        : scenario == CprScenario.pediatric
        ? 'CPR Metrics — Pediatric'
        : 'CPR Metrics — Active';

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: _PreviewAppBar(title: title),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: LiveCprMetricsCard(
          depth:            idle ? 0 : 5.4,
          frequency:        idle ? 0 : 112,
          cprTime:          idle ? Duration.zero : const Duration(minutes: 2, seconds: 47),
          compressionCount: idle ? 0 : 142,
          isSessionActive:  !idle,
          scenario:         scenario,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vitals cards — active session
// ─────────────────────────────────────────────────────────────────────────────

class _VitalsCardsPreview extends StatelessWidget {
  const _VitalsCardsPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Vitals Cards — Active'),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: const Column(
          children: [
            VitalsCard(
              label:       'Patient Vitals',
              heartRate:   0,
              temperature: 36.8,
            ),
            SizedBox(height: AppSpacing.md),
            VitalsCard(
              label:         'Your Vitals',
              heartRate:     98,
              spO2:          97,
              temperature:   37.1,
              signalQuality: 85,
            ),
            SizedBox(height: AppSpacing.md),
            VitalsCard(
              label:    'Patient Vitals — No Signal',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vitals cards — pulse check window
// Shows patient vitals active + rescuer at pause + quality-gated display
// ─────────────────────────────────────────────────────────────────────────────

class _VitalsCardsPulseCheckPreview extends StatelessWidget {
  const _VitalsCardsPulseCheckPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Vitals — Pulse Check Window'),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context label
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical:   AppSpacing.xs,
              ),
              decoration: AppDecorations.chip(
                color: AppColors.success,
                bg:    AppColors.successBg,
              ),
              child: Text(
                'PULSE CHECK ACTIVE — fingertip MAX30102 streaming',
                style: AppTypography.badge(color: AppColors.success),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Patient vitals — live during pulse check
            const VitalsCard(
              label:       'Patient Vitals',
              heartRate:   64,
              spO2:        94,
              temperature: 36.5,
            ),
            const SizedBox(height: AppSpacing.md),

            // Patient — high quality signal
            const VitalsCard(
              label:         'Patient Vitals — Strong Signal (quality 85)',
              heartRate:     71,
              spO2:          96,
              temperature:   36.7,
              signalQuality: 85,
            ),
            const SizedBox(height: AppSpacing.md),

            // Patient — weak signal (below 40 threshold → greyed)
            const VitalsCard(
              label:         'Patient Vitals — Weak Signal (quality 28)',
              heartRate:     55,
              spO2:          88,
              temperature:   36.2,
              signalQuality: 28,
            ),
            const SizedBox(height: AppSpacing.md),

            // Rescuer at pause — motion settled, good quality
            const VitalsCard(
              label:         'Your Vitals — At Pause (quality 78)',
              heartRate:     112,
              spO2:          98,
              temperature:   37.2,
              signalQuality: 78,
            ),
            const SizedBox(height: AppSpacing.md),

            // Rescuer during compressions — motion artefact
            const VitalsCard(
              label:         'Your Vitals — During Compressions (quality 12)',
              heartRate:     118,
              spO2:          97,
              temperature:   37.3,
              signalQuality: 12,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated depth bar preview
// ─────────────────────────────────────────────────────────────────────────────

class _DepthBarPreview extends StatefulWidget {
  const _DepthBarPreview();

  @override
  State<_DepthBarPreview> createState() => _DepthBarPreviewState();
}

class _DepthBarPreviewState extends State<_DepthBarPreview> {
  double _depth = 5.4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Animated Depth Bar'),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xl, AppSpacing.xl,
          AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 260,
              child: Center(child: AnimatedDepthBar(depth: _depth)),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Depth: ${_depth.toStringAsFixed(1)} cm',
              style: AppTypography.subheading(),
            ),
            const SizedBox(height: AppSpacing.md),
            Slider(
              value:    _depth,
              min:      0,
              max:      8,
              divisions: 80,
              onChanged: (v) => setState(() => _depth = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0 cm', style: AppTypography.caption()),
                Text('Target: 5–6 cm',
                    style: AppTypography.caption(color: AppColors.primary)),
                Text('8 cm', style: AppTypography.caption()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rotating arrow preview
// ─────────────────────────────────────────────────────────────────────────────

class _RotatingArrowPreview extends StatefulWidget {
  const _RotatingArrowPreview();

  @override
  State<_RotatingArrowPreview> createState() => _RotatingArrowPreviewState();
}

class _RotatingArrowPreviewState extends State<_RotatingArrowPreview> {
  double _freq = 110;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Rotating Arrow'),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.xl, AppSpacing.xl,
          AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: Center(child: RotatingArrow(frequency: _freq)),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Frequency: ${_freq.round()} BPM',
              style: AppTypography.subheading(),
            ),
            const SizedBox(height: AppSpacing.md),
            Slider(
              value:    _freq,
              min:      60,
              max:      160,
              divisions: 100,
              onChanged: (v) => setState(() => _freq = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('60', style: AppTypography.caption()),
                Text('Target: 100–120 BPM',
                    style: AppTypography.caption(color: AppColors.primary)),
                Text('160', style: AppTypography.caption()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Universal header preview
// ─────────────────────────────────────────────────────────────────────────────

class _UniversalHeaderPreview extends StatelessWidget {
  const _UniversalHeaderPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Universal Header'),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Main screen variant',
                style: AppTypography.caption(color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: AppSpacing.headerHeight,
              child: UniversalHeader.forMainScreens(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Sub-screen variant',
                style: AppTypography.caption(color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: AppSpacing.headerHeight,
              child: UniversalHeader.forOtherScreens(
                customTitle: 'Example Sub-Screen',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Battery widget preview
// ─────────────────────────────────────────────────────────────────────────────

class _BatteryWidgetPreview extends StatelessWidget {
  const _BatteryWidgetPreview();

  @override
  Widget build(BuildContext context) {
    final levels = [100, 70, 50, 30, 10];

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Glove Battery Indicator'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Container(
            padding:    const EdgeInsets.all(AppSpacing.lg),
            decoration: AppDecorations.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Charge Levels', style: AppTypography.subheading()),
                const SizedBox(height: AppSpacing.md),
                ...levels.map((pct) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      GloveBatteryIndicator(batteryPercentage: pct),
                      const SizedBox(width: AppSpacing.md),
                      Text('$pct%', style: AppTypography.body()),
                    ],
                  ),
                )),
                const Divider(color: AppColors.divider),
                const SizedBox(height: AppSpacing.sm),
                Text('Charging', style: AppTypography.subheading()),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const GloveBatteryIndicator(
                      batteryPercentage: 55,
                      isCharging:        true,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text('Charging (55%)', style: AppTypography.body()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BLE status indicator preview
// ─────────────────────────────────────────────────────────────────────────────

class _BleStatusPreview extends StatelessWidget {
  const _BleStatusPreview();

  @override
  Widget build(BuildContext context) {
    final statuses = [
      'Connected',
      'Disconnected',
      'Scanning',
      'Connecting',
      'Error',
    ];

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'BLE Status Indicator'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Container(
            padding:    const EdgeInsets.all(AppSpacing.lg),
            decoration: AppDecorations.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BLE connection states',
                    style: AppTypography.subheading()),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'BLEStatusIndicator requires a live BLEConnection instance. '
                      'Status labels shown here for reference.',
                  style: AppTypography.caption(color: AppColors.textDisabled),
                ),
                const SizedBox(height: AppSpacing.md),
                ...statuses.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Container(
                        width: AppSpacing.iconMd,
                        height: AppSpacing.iconMd,
                        decoration: AppDecorations.iconCircle(
                          bg: s == 'Connected'
                              ? AppColors.successBg
                              : s == 'Error'
                              ? AppColors.emergencyBg
                              : AppColors.primaryLight,
                        ),
                        child: Icon(
                          s == 'Connected'   ? Icons.bluetooth_connected_rounded
                              : s == 'Error'     ? Icons.bluetooth_disabled_rounded
                              : s == 'Scanning'  ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_rounded,
                          size:  AppSpacing.iconSm,
                          color: s == 'Connected' ? AppColors.success
                              : s == 'Error'      ? AppColors.emergencyRed
                              : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(s, style: AppTypography.body()),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account avatar button preview
// ─────────────────────────────────────────────────────────────────────────────

class _AccountAvatarPreview extends ConsumerWidget {
  const _AccountAvatarPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: const _PreviewAppBar(title: 'Account Avatar Button'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Renders based on auth state — log in/out to see both variants.',
                style: AppTypography.caption(color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.lg),
            const AccountAvatarButton(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable preview app bar
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const _PreviewAppBar({required this.title});

  @override
  Size get preferredSize =>
      const Size.fromHeight(AppSpacing.headerHeight + AppSpacing.dividerThickness);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor:        AppColors.headerBg,
      elevation:              0,
      scrolledUnderElevation: 0,
      toolbarHeight:          AppSpacing.headerHeight,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppColors.primary),
        onPressed: context.pop,
      ),
      title: Text(title, style: AppTypography.heading(size: 18)),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
        child: Divider(
            height: AppSpacing.dividerThickness,
            color:  AppColors.divider),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared local helper widgets
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
      margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: AppDecorations.card(),
      child:      Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height:    AppSpacing.dividerThickness,
      thickness: AppSpacing.dividerThickness,
      color:     AppColors.divider,
      indent:    AppSpacing.md + AppSpacing.touchTargetMin,
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData     icon;
  final Color?       iconColor;
  final String       label;
  final String?      subtitle;
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
      onTap:        onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.sm + AppSpacing.xs,
        ),
        child: Row(
          children: [
            Container(
              width:  AppSpacing.touchTargetMin - AppSpacing.sm,
              height: AppSpacing.touchTargetMin - AppSpacing.sm,
              decoration: AppDecorations.iconRounded(
                bg:     color.withValues(alpha: 0.1),
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
              size:  AppSpacing.iconSm,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}