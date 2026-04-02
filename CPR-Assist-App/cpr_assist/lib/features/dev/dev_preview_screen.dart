import 'dart:async';

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
import '../guide/screens/quiz_screen.dart';
import '../training/screens/achievements_screen.dart';
import '../training/widgets/pulse_check_overlay.dart';
import '../training/widgets/simulation_112_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEV ONLY — UI Preview Screen
// Remove the entry point in account_menu.dart before releasing.
// ─────────────────────────────────────────────────────────────────────────────



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

List<PulseCheckEvent> _mockPulseChecks({bool pulseDetected = false}) => [
  const PulseCheckEvent(
    timestampMs:    120000,
    intervalNumber: 1,
    classification: 0,   // ABSENT
    detectedBpm:    0.0,
    confidence:     72,
    perfusionIndex: 18,
    userDecision:   'continue',
  ),
  PulseCheckEvent(
    timestampMs:    240000,
    intervalNumber: 2,
    classification: pulseDetected ? 2 : 1,  // PRESENT or UNCERTAIN
    detectedBpm:    pulseDetected ? 64.0 : 0.0,
    confidence:     pulseDetected ? 85 : 38,
    perfusionIndex: pulseDetected ? 42 : 12,
    userDecision:   pulseDetected ? 'stop_cpr' : 'continue',
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

// ── Mock compressions — adult (5–6 cm, 110 BPM) ───────────────────────────

List<CompressionEvent> _mockCompressionsAdult({int count = 60}) =>
    List.generate(count, (i) => CompressionEvent(
      timestampMs:          i * 545,
      depth:                5.3 + (i % 5 == 0 ? 0.9 : i % 3 == 0 ? -0.6 : 0.1),
      instantaneousRate:    110.0 + (i % 4 == 0 ? 8.0 : i % 7 == 0 ? -11.0 : 1.0),
      frequency:            110.0 + (i % 4 == 0 ? 8.0 : i % 7 == 0 ? -11.0 : 1.0),
      force:                350.0 + (i % 6 == 0 ? 80.0 : -20.0),
      recoilAchieved:       i % 8 != 0,
      overForce:            i % 25 == 0,
      postureOk:            i % 10 != 0,
      leaningDetected:      i % 18 == 0,
      effectiveDepth:       5.1 + (i % 5 == 0 ? 0.7 : -0.3),
      wristAlignmentAngle:  8.0 + (i % 9 == 0 ? 12.0 : 0.0),
      compressionAxisDev:   5.0,
    ));

// ── Mock compressions — pediatric (4–5 cm, 110 BPM) ──────────────────────

List<CompressionEvent> _mockCompressionsPediatric({int count = 40}) =>
    List.generate(count, (i) => CompressionEvent(
      timestampMs:       i * 545,
      depth:             4.5 + (i % 5 == 0 ? 0.4 : i % 4 == 0 ? -0.5 : 0.1),
      instantaneousRate: 112.0 + (i % 5 == 0 ? 6.0 : -4.0),
      frequency:         112.0 + (i % 5 == 0 ? 6.0 : -4.0),
      force:             220.0 + (i % 7 == 0 ? 40.0 : -10.0),
      recoilAchieved:    i % 6 != 0,
      postureOk:         i % 8 != 0,
      effectiveDepth:    4.3 + (i % 5 == 0 ? 0.3 : -0.2),
    ));

// ─────────────────────────────────────────────────────────────────────────────
// TRAINING — ADULT
// ─────────────────────────────────────────────────────────────────────────────

SessionDetail _mockTrainingAdult({
  double grade           = 87,
  int    compressions    = 160,
  int    correctDepth    = 142,
  int    correctFrequency = 148,
  double avgDepth        = 5.4,
  double avgFrequency    = 111.0,
  int    durationSecs    = 185,
  String scenario         = 'standard_adult',
}) => SessionDetail(
  sessionStart:          DateTime.now().subtract(const Duration(hours: 2)),
  mode:                  'training',
  scenario: scenario,
  compressionCount:      compressions,
  correctDepth:          correctDepth,
  correctFrequency:      correctFrequency,
  correctRecoil:         (compressions * 0.88).round(),
  depthRateCombo:        (compressions * 0.82).round(),
  correctPosture:        (compressions * 0.91).round(),
  leaningCount:          4,
  overForceCount:        2,
  tooDeepCount:          3,
  correctVentilations:   7,
  averageDepth:          avgDepth,
  averageFrequency:      avgFrequency,
  averageEffectiveDepth: avgDepth - 0.2,
  peakDepth:             6.8,
  depthSD:               0.31,
  depthConsistency:      (correctDepth / compressions * 100),
  frequencyConsistency:  (correctFrequency / compressions * 100),
  handsOnRatio:          0.87,
  noFlowTime:            3.2,
  noFlowIntervals:       2,
  rateVariability:       78.0,
  timeToFirstCompression: 2.8,
  consecutiveGoodPeak:   22,
  fatigueOnsetIndex:     120,
  rescuerSwapCount:      1,
  ventilationCount:      5,
  ventilationCompliance: 80.0,
  sessionDuration:       durationSecs,
  totalGrade:            grade,
  compressions:          _mockCompressionsAdult(count: compressions.clamp(0, 120)),
  ventilations:          _mockVentilations(),
  rescuerVitals:         _mockRescuerVitals(),
  patientTemperature:    36.8,
  rescuerHRLastPause:    102.0,
  rescuerSpO2LastPause:  97.0,
  ambientTempStart:      22.1,
  ambientTempEnd:        23.4,
  syncedToBackend:       true,
);

// ─────────────────────────────────────────────────────────────────────────────
// TRAINING — PEDIATRIC
// ─────────────────────────────────────────────────────────────────────────────

SessionDetail _mockTrainingPediatric({double grade = 91}) => SessionDetail(
  sessionStart:          DateTime.now().subtract(const Duration(days: 1)),
  mode:                  'training',
  scenario:              'pediatric',
  compressionCount:      95,
  correctDepth:          87,
  correctFrequency:      89,
  correctRecoil:         82,
  depthRateCombo:        80,
  correctPosture:        90,
  leaningCount:          2,
  overForceCount:        0,
  tooDeepCount:          1,
  correctVentilations:   6,
  averageDepth:          4.6,
  averageFrequency:      112.0,
  averageEffectiveDepth: 4.4,
  peakDepth:             5.2,
  depthSD:               0.22,
  depthConsistency:      91.6,
  frequencyConsistency:  93.7,
  handsOnRatio:          0.89,
  noFlowTime:            2.1,
  noFlowIntervals:       1,
  rateVariability:       65.0,
  timeToFirstCompression: 2.2,
  consecutiveGoodPeak:   31,
  fatigueOnsetIndex:     0,
  rescuerSwapCount:      0,
  ventilationCount:      3,
  ventilationCompliance: 100.0,
  sessionDuration:       140,
  totalGrade:            grade,
  compressions:          _mockCompressionsPediatric(),
  ventilations:          _mockVentilations(count: 3),
  rescuerVitals:         _mockRescuerVitals(),
  patientTemperature:    36.5,
  rescuerHRLastPause:    94.0,
  rescuerSpO2LastPause:  98.0,
  ambientTempStart:      21.8,
  ambientTempEnd:        22.0,
  syncedToBackend:       true,
);

// ─────────────────────────────────────────────────────────────────────────────
// TRAINING — NO FEEDBACK
// ─────────────────────────────────────────────────────────────────────────────

SessionDetail _mockTrainingNoFeedback({double grade = 88}) => SessionDetail(
  sessionStart:          DateTime.now().subtract(const Duration(hours: 5)),
  mode:                  'training_no_feedback',
  scenario:              'standard_adult',
  compressionCount:      145,
  correctDepth:          128,
  correctFrequency:      134,
  correctRecoil:         120,
  depthRateCombo:        115,
  correctPosture:        132,
  leaningCount:          3,
  overForceCount:        1,
  tooDeepCount:          2,
  correctVentilations:   8,
  averageDepth:          5.5,
  averageFrequency:      113.0,
  averageEffectiveDepth: 5.3,
  peakDepth:             6.5,
  depthSD:               0.28,
  depthConsistency:      88.3,
  frequencyConsistency:  92.4,
  handsOnRatio:          0.91,
  noFlowTime:            1.8,
  noFlowIntervals:       1,
  rateVariability:       71.0,
  timeToFirstCompression: 3.1,
  consecutiveGoodPeak:   28,
  fatigueOnsetIndex:     0,
  rescuerSwapCount:      1,
  ventilationCount:      4,
  ventilationCompliance: 75.0,
  sessionDuration:       172,
  totalGrade:            grade,
  compressions:          _mockCompressionsAdult(count: 100),
  ventilations:          _mockVentilations(),
  rescuerVitals:         _mockRescuerVitals(),
  patientTemperature:    36.9,
  rescuerHRLastPause:    108.0,
  rescuerSpO2LastPause:  96.0,
  ambientTempStart:      22.5,
  ambientTempEnd:        23.1,
  syncedToBackend:       true,
);

// ─────────────────────────────────────────────────────────────────────────────
// EMERGENCY — ADULT
// ─────────────────────────────────────────────────────────────────────────────

SessionDetail _mockEmergencyAdult({required bool pulseDetected}) => SessionDetail(
  sessionStart:          DateTime.now().subtract(const Duration(days: 2)),
  mode:                  'emergency',
  scenario:              'standard_adult',
  compressionCount:      187,
  correctDepth:          162,
  correctFrequency:      171,
  correctRecoil:         155,
  depthRateCombo:        148,
  correctPosture:        170,
  leaningCount:          6,
  overForceCount:        3,
  tooDeepCount:          4,
  correctVentilations:   10,
  averageDepth:          5.6,
  averageFrequency:      113.0,
  averageEffectiveDepth: 5.4,
  peakDepth:             7.1,
  depthSD:               0.38,
  depthConsistency:      86.6,
  frequencyConsistency:  91.4,
  handsOnRatio:          0.83,
  noFlowTime:            8.4,
  noFlowIntervals:       4,
  rateVariability:       92.0,
  timeToFirstCompression: 4.1,
  consecutiveGoodPeak:   18,
  fatigueOnsetIndex:     140,
  rescuerSwapCount:      2,
  ventilationCount:      6,
  ventilationCompliance: 83.3,
  pulseChecksPrompted:   2,
  pulseChecksComplied:   2,
  pulseDetectedFinal:    pulseDetected,
  patientTemperature:    35.2,
  rescuerHRLastPause:    118.0,
  rescuerSpO2LastPause:  95.0,
  ambientTempStart:      20.3,
  ambientTempEnd:        21.8,
  sessionDuration:       252,
  totalGrade:            0,  // Emergency always 0
  compressions:          _mockCompressionsAdult(count: 120),
  ventilations:          _mockVentilations(count: 6),
  pulseChecks: _mockPulseChecks(pulseDetected: pulseDetected),
  rescuerVitals:         _mockRescuerVitals(),
  syncedToBackend:       true,
);

// ─────────────────────────────────────────────────────────────────────────────
// EMERGENCY — PEDIATRIC
// ─────────────────────────────────────────────────────────────────────────────

SessionDetail _mockEmergencyPediatric() => SessionDetail(
  sessionStart:          DateTime.now().subtract(const Duration(days: 3)),
  mode:                  'emergency',
  scenario:              'pediatric',
  compressionCount:      95,
  correctDepth:          82,
  correctFrequency:      88,
  correctRecoil:         79,
  depthRateCombo:        74,
  correctPosture:        88,
  leaningCount:          2,
  overForceCount:        0,
  tooDeepCount:          1,
  correctVentilations:   4,
  averageDepth:          4.7,
  averageFrequency:      115.0,
  averageEffectiveDepth: 4.5,
  peakDepth:             5.4,
  depthSD:               0.25,
  depthConsistency:      86.3,
  frequencyConsistency:  92.6,
  handsOnRatio:          0.85,
  noFlowTime:            4.2,
  noFlowIntervals:       2,
  rateVariability:       68.0,
  timeToFirstCompression: 3.5,
  consecutiveGoodPeak:   14,
  fatigueOnsetIndex:     0,
  rescuerSwapCount:      1,
  ventilationCount:      3,
  ventilationCompliance: 100.0,
  pulseChecksPrompted:   1,
  pulseChecksComplied:   1,
  pulseDetectedFinal:    false,
  patientTemperature:    35.8,
  rescuerHRLastPause:    111.0,
  rescuerSpO2LastPause:  96.0,
  ambientTempStart:      21.0,
  ambientTempEnd:        21.5,
  sessionDuration:       153,
  totalGrade:            0,
  compressions:          _mockCompressionsPediatric(),
  ventilations:          _mockVentilations(count: 3),
  pulseChecks: _mockPulseChecks(pulseDetected: false),
  rescuerVitals:         _mockRescuerVitals(),
  syncedToBackend:       true,
);

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY MOCKS — for fromSummary path
// ─────────────────────────────────────────────────────────────────────────────

SessionSummary _mockSummaryTraining({double grade = 81}) => SessionSummary(
  id:                    42,
  mode:                  'training',
  scenario:              'standard_adult',
  compressionCount:      138,
  correctDepth:          110,
  correctFrequency:      126,
  correctRecoil:         118,
  depthRateCombo:        104,
  correctPosture:        128,
  leaningCount:          5,
  overForceCount:        2,
  noFlowIntervals:       2,
  rescuerSwapCount:      1,
  fatigueOnsetIndex:     0,
  averageDepth:          5.3,
  averageFrequency:      110.0,
  averageEffectiveDepth: 5.1,
  peakDepth:             6.4,
  depthSD:               0.33,
  depthConsistency:      79.7,
  frequencyConsistency:  91.3,
  ventilationCount:      4,
  ventilationCompliance: 75.0,
  pulseDetectedFinal:    false,
  pulseChecksPrompted:   0,
  pulseChecksComplied:   0,
  patientTemperature:    36.7,
  rescuerHRLastPause:    99.0,
  rescuerSpO2LastPause:  97.0,
  sessionDuration:       168,
  totalGrade:            grade,
  sessionStart:          DateTime.now().subtract(const Duration(days: 4)),
);

SessionSummary _mockSummaryEmergency() => SessionSummary(
  id:                    17,
  mode:                  'emergency',
  scenario:              'standard_adult',
  compressionCount:      203,
  correctDepth:          174,
  correctFrequency:      185,
  correctRecoil:         162,
  depthRateCombo:        158,
  correctPosture:        190,
  leaningCount:          8,
  overForceCount:        4,
  noFlowIntervals:       5,
  rescuerSwapCount:      2,
  fatigueOnsetIndex:     160,
  averageDepth:          5.5,
  averageFrequency:      112.0,
  averageEffectiveDepth: 5.3,
  peakDepth:             7.2,
  depthSD:               0.41,
  depthConsistency:      85.7,
  frequencyConsistency:  91.1,
  ventilationCount:      6,
  ventilationCompliance: 83.3,
  pulseDetectedFinal:    true,
  pulseChecksPrompted:   2,
  pulseChecksComplied:   2,
  patientTemperature:    35.1,
  rescuerHRLastPause:    122.0,
  rescuerSpO2LastPause:  94.0,
  sessionDuration:       295,
  totalGrade:            0,
  sessionStart:          DateTime.now().subtract(const Duration(days: 5)),
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

          // ── Session Results — Training ───────────────────────────────────
          const _SectionHeader(label: 'Session Results — Training'),
          _PreviewCard(children: [

            _NavTile(
              icon:      Icons.emoji_events_rounded,
              iconColor: AppColors.success,
              label:     'Excellent — Adult, With Feedback (94%)',
              subtitle:  'Standard adult · 160 compressions · 3:05 · graphs',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockTrainingAdult(grade: 94),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.thumb_up_outlined,
              iconColor: AppColors.info,
              label:     'Good — Adult, With Feedback (76%)',
              subtitle:  'Standard adult · 130 compressions · 2:20',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockTrainingAdult(grade: 76,
                    compressions: 130, correctDepth: 95, correctFrequency: 105,
                    avgDepth: 5.1, avgFrequency: 108, durationSecs: 140),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.trending_up_rounded,
              iconColor: AppColors.warning,
              label:     'Needs Work — Adult (48%)',
              subtitle:  'Standard adult · 80 compressions · 1:30',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockTrainingAdult(grade: 48,
                    compressions: 80, correctDepth: 32, correctFrequency: 40,
                    avgDepth: 4.2, avgFrequency: 95, durationSecs: 90),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.child_care_rounded,
              iconColor: AppColors.primary,
              label:     'Pediatric — Excellent (91%)',
              subtitle:  'Pediatric scenario · 4–5 cm target · graphs',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockTrainingPediatric(grade: 91),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.visibility_off_rounded,
              iconColor: AppColors.textSecondary,
              label:     'No-Feedback Mode — Adult (88%)',
              subtitle:  'training_no_feedback · blind assessment',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockTrainingNoFeedback(grade: 88),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.bar_chart_rounded,
              label:    'From Summary (no graphs)',
              subtitle: 'History-view path — no compression stream',
              onTap: () => context.push(SessionResultsScreen.fromSummary(
                summary:       _mockSummaryTraining(grade: 81),
                sessionNumber: 7,
              )),
            ),
          ]),

// ── Session Results — Emergency ──────────────────────────────────
          const _SectionHeader(label: 'Session Results — Emergency'),
          _PreviewCard(children: [
            _NavTile(
              icon:      Icons.emergency_rounded,
              iconColor: AppColors.emergencyRed,
              label:     'Emergency — Adult, Pulse Detected',
              subtitle:  'ROSC · 187 compressions · 4:12 · pulse checks',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockEmergencyAdult(pulseDetected: true),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.monitor_heart_outlined,
              label:    'CPR Metrics Card — Calibrating',
              subtitle: 'imuCalibrated = false overlay shown',
              onTap:    () => context.push(
                const _LiveCprWidgetsPreview(calibrating: true),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.monitor_heart_outlined,
              label:    'CPR Metrics Card — No Feedback',
              subtitle: 'trainingNoFeedback mode',
              onTap:    () => context.push(
                const _LiveCprWidgetsPreview(noFeedback: true),
              ),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.favorite_rounded,
              iconColor: AppColors.success,
              label:    'Last Pulse Check — Pulse Detected',
              subtitle: 'Emergency mode strip, 94% confidence',
              onTap:    () => context.push(const _LastPulseCheckStripPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.heart_broken_rounded,
              iconColor: AppColors.error,
              label:    'Last Pulse Check — No Pulse',
              subtitle: 'Emergency mode strip',
              onTap:    () => context.push(const _LastPulseCheckStripPreviewAbsent()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.swap_vert_rounded,
              label:    'Status Bar — Emergency + Pediatric',
              subtitle: 'All three control areas visible',
              onTap:    () => context.push(const _StatusBarPreview()),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.emergency_outlined,
              iconColor: AppColors.warning,
              label:     'Emergency — Adult, No Pulse',
              subtitle:  'No ROSC · 210 compressions · 5:00',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockEmergencyAdult(pulseDetected: false),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.child_care_rounded,
              iconColor: AppColors.emergencyRed,
              label:     'Emergency — Pediatric',
              subtitle:  'Pediatric · 4–5 cm · 95 compressions · 2:30',
              onTap: () => context.push(SessionResultsScreen.fromDetail(
                detail: _mockEmergencyPediatric(),
              )),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.summarize_outlined,
              label:    'Emergency — From Summary (no graphs)',
              subtitle: 'History-view path',
              onTap: () => context.push(SessionResultsScreen.fromSummary(
                summary:       _mockSummaryEmergency(),
                sessionNumber: 3,
              )),
            ),
          ]),

// ── Session History & Leaderboard ────────────────────────────────
          const _SectionHeader(label: 'History & Leaderboard'),
          _PreviewCard(children: [
            _NavTile(
              icon:     Icons.history_rounded,
              label:    'Session History Screen',
              subtitle: 'Full training history with filters',
              onTap:    () => context.push(const SessionHistoryScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.leaderboard_rounded,
              label:    'Leaderboard Screen',
              subtitle: 'Global · Friends · My Sessions tabs',
              onTap:    () => context.push(const LeaderboardScreen()),
            ),

            const _Divider(),
            _NavTile(
              icon:     Icons.emoji_events_outlined,
              label:    'Achievements Screen',
              subtitle: '12 achievements — unlocked/locked grid',
              onTap:    () => context.push(const AchievementsScreen()),
            ),
            const _Divider(),
            _NavTile(
              icon:     Icons.quiz_outlined,
              label:    'Quiz Screen',
              subtitle: '10 CPR knowledge questions with scoring',
              onTap:    () => context.push(const QuizScreen()),
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
              icon:      Icons.sensors_rounded,
              iconColor: AppColors.primary,
              label:     'Pulse Check Overlay — Assessing',
              subtitle:  'Live waveform · countdown · no result yet',
              onTap:     () => context.push(const _PulseCheckOverlayPreview(classification: null)),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.favorite_rounded,
              iconColor: AppColors.success,
              label:     'Pulse Check Overlay — Pulse Detected',
              subtitle:  '64 BPM · 85% confidence · action buttons',
              onTap:     () => context.push(const _PulseCheckOverlayPreview(classification: 2)),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.heart_broken_rounded,
              iconColor: AppColors.emergencyRed,
              label:     'Pulse Check Overlay — No Pulse',
              subtitle:  'Continue CPR button',
              onTap:     () => context.push(const _PulseCheckOverlayPreview(classification: 0)),
            ),
            const _Divider(),
            _NavTile(
              icon:      Icons.help_outline_rounded,
              iconColor: AppColors.warning,
              label:     'Pulse Check Overlay — Uncertain',
              subtitle:  'Weak signal · check manually',
              onTap:     () => context.push(const _PulseCheckOverlayPreview(classification: 1)),
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
  final bool        calibrating;
  final bool        noFeedback;

  const _LiveCprWidgetsPreview({
    this.idle        = false,
    this.scenario    = CprScenario.standardAdult,
    this.calibrating = false,
    this.noFeedback  = false,
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
          imuCalibrated:  !calibrating,
          isNoFeedback:   noFeedback,
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
          Container(
          height: 260,
          decoration: BoxDecoration(
            color: AppColors.cprCardBg,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
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
            Container(
              decoration: BoxDecoration(
                color: AppColors.cprCardBg,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.md,
              ),
              child: AspectRatio(
                aspectRatio: 1.6, // wide enough for semicircle arc + labels
                child: FrequencyArcGauge(frequency: _freq),
              ),
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
// Pulse check overlay preview — simulates the full assessment window
// ─────────────────────────────────────────────────────────────────────────────

class _PulseCheckOverlayPreview extends StatefulWidget {
  final int? classification; // null=pending, 0=absent, 1=uncertain, 2=present
  const _PulseCheckOverlayPreview({required this.classification});

  @override
  State<_PulseCheckOverlayPreview> createState() =>
      _PulseCheckOverlayPreviewState();
}

class _PulseCheckOverlayPreviewState
    extends State<_PulseCheckOverlayPreview> {
  Timer?        _waveformTimer;
  Timer?        _resultTimer;
  int?          _classification;
  final List<double> _ppgBuffer = [];
  double        _phase = 0.0;

  @override
  void initState() {
    super.initState();
    _classification = widget.classification;

    // Simulate PPG waveform at 10 Hz
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        _phase += 0.35;
        // Realistic PPG shape: sharp systolic peak + diastolic notch
        final t      = _phase % (2 * 3.141592653589793);
        final systol = (t < 1.2) ? (t * 0.83) : 0.0;
        final diast  = (t > 2.0 && t < 3.5)
            ? 0.25 * ((t - 2.0) / 1.5)
            : 0.0;
        const base   = 0.12;
        double v = base
            + systol * (1 - systol / 2)
            + diast;
        // Add tiny noise
        v += ((_phase * 17.3) % 0.04) - 0.02;
        _ppgBuffer.add(v.clamp(0.0, 1.0));
        if (_ppgBuffer.length > 80) _ppgBuffer.removeAt(0);
      });
    });

    // If pending mode: after 4 s, auto-apply the result from widget prop
    if (widget.classification == null) {
      _resultTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _classification = 2); // simulate pulse detected
      });
    }
  }

  @override
  void dispose() {
    _waveformTimer?.cancel();
    _resultTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      appBar: AppBar(
        backgroundColor:        AppColors.primaryDark,
        elevation:              0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textOnDark),
          onPressed: context.pop,
        ),
        title: Text(
          'Pulse Check Preview',
          style: AppTypography.heading(size: 18, color: AppColors.textOnDark),
        ),
      ),
      body: PulseCheckOverlay(
        intervalNumber: 1,
        classification: _classification,
        ppgBuffer:      List.from(_ppgBuffer),
        detectedBpm:    _classification == 2 ? 64.0 : null,
        confidence:     _classification != null ? 85 : null,
        onContinueCpr:  context.pop,
        onStopCpr:      context.pop,
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
class _LastPulseCheckStripPreview extends StatelessWidget {
  const _LastPulseCheckStripPreview();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.screenBgGrey,
    appBar: const _PreviewAppBar(title: 'Last Pulse Check Strip'),
    body: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(children: [
        LastPulseCheckStrip(
          classification: 2,
          detectedBpm:    72,
          confidence:     94,
          temperature:    36.8,
          intervalNumber: 1,
        ),
        const SizedBox(height: AppSpacing.md),
        const LastPulseCheckStrip(
          classification: 1,
          confidence:     55,
          intervalNumber: 2,
        ),
      ]),
    ),
  );
}

class _LastPulseCheckStripPreviewAbsent extends StatelessWidget {
  const _LastPulseCheckStripPreviewAbsent();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.screenBgGrey,
    appBar: const _PreviewAppBar(title: 'Last Pulse Check — Absent'),
    body: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: const LastPulseCheckStrip(
        classification: 0,
        confidence:     88,
        intervalNumber: 1,
      ),
    ),
  );
}

class _StatusBarPreview extends StatelessWidget {
  const _StatusBarPreview();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.screenBgGrey,
    appBar: const _PreviewAppBar(title: 'Live CPR Status Bar'),
    body: Column(children: [
      // Emergency + Adult
      // (StatusBar is private — note to self: make it internal-public
      // or replicate the visual here with a note)
      const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Text(
          'Status bar is embedded in LiveCPRScreen.\n'
              'Use the full screen preview to test it.',
          textAlign: TextAlign.center,
        ),
      ),
    ]),
  );
}