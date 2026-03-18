import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../account/screens/login_screen.dart';
import '../../training/widgets/session_results.dart';
import '../widgets/live_cpr_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LiveCPRScreen
//
// Card order (clinical priority):
//   1. Patient Vitals  — top, most urgent
//   2. CPR Metrics     — dominant card with depth bar + frequency gauge
//   3. Rescuer Vitals  — bottom, secondary monitoring
//
// Overlay priority (rendered above cards when active):
//   - IMU calibrating banner   — shown until imuCalibrated = true
//   - Pulse check overlay      — full attention during pulse check window
//   - Rescuer swap banner      — auto-dismiss 10 s after TWO_MIN_ALERT
//   - Fatigue badge            — shown after FATIGUE_ALERT until session ends
//
// Mode/scenario changes from the glove button are synced to app providers here.
// ─────────────────────────────────────────────────────────────────────────────

class LiveCPRScreen extends ConsumerStatefulWidget {
  final Function(int) onTabTapped;
  const LiveCPRScreen({super.key, required this.onTabTapped});

  @override
  ConsumerState<LiveCPRScreen> createState() => _LiveCPRScreenState();
}

class _LiveCPRScreenState extends ConsumerState<LiveCPRScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Session timer ──────────────────────────────────────────────────────────
  Timer? _sessionTimer;
  Timer? _swapBannerTimer;

  // ── Display state ──────────────────────────────────────────────────────────
  bool     _isSessionActive         = false;
  bool     _hasHandledEndPing       = false;
  int      _displayCompressionCount = 0;
  Duration _displaySessionDuration  = Duration.zero;
  double   _displayDepth            = 0.0;
  double   _displayFrequency        = 0.0;
  DateTime? _sessionStartTime;

  // ── Overlay state ──────────────────────────────────────────────────────────
  bool   _imuCalibrated      = false; // false = show calibrating banner
  bool   _showSwapBanner     = false; // true after TWO_MIN_ALERT
  int    _swapAlertNumber    = 0;
  bool   _showFatigueBadge   = false;
  int    _fatigueScore       = 0;
  bool   _pulseCheckActive   = false;
  int?   _pulseCheckInterval;
  int?   _pulseClassification; // null = pending, 0/1/2 = result

  // ── Vitals display state ───────────────────────────────────────────────────
  double? _heartRatePatient;
  double? _spO2Patient;
  double? _patientTemperature;
  double? _heartRateUser;
  double? _spO2User;
  double? _rescuerTemperature;
  int?    _rescuerSignalQuality;

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _swapBannerTimer?.cancel();
    super.dispose();
  }

  // ── BLE data handler ───────────────────────────────────────────────────────
  void _updateDisplayValues(Map<String, dynamic> data) {
    // ── SESSION_START ──────────────────────────────────────────────────────
    if (data['isStartPing'] == true) {
      _sessionStartTime = DateTime.now();
      ref.read(cprSessionActiveProvider.notifier).state = true;
      setState(() {
        _isSessionActive         = true;
        _hasHandledEndPing       = false;
        _displayDepth            = 0.0;
        _displayFrequency        = 0.0;
        _displayCompressionCount = 0;
        _displaySessionDuration  = Duration.zero;
        _imuCalibrated           = false;
        _showSwapBanner          = false;
        _showFatigueBadge        = false;
        _pulseCheckActive        = false;
        _pulseClassification     = null;
      });
      _sessionTimer?.cancel();
      _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _isSessionActive) {
          setState(() {
            _displaySessionDuration = Duration(
              seconds: DateTime.now().difference(_sessionStartTime!).inSeconds,
            );
          });
        }
      });
      return;
    }

    // ── SESSION_END ────────────────────────────────────────────────────────
    if (data['isEndPing'] == true && !_hasHandledEndPing) {
      ref.read(cprSessionActiveProvider.notifier).state = false;
      setState(() {
        _isSessionActive     = false;
        _hasHandledEndPing   = true;
        _displayDepth        = 0.0;
        _displayFrequency    = 0.0;
        _pulseCheckActive    = false;
        _showSwapBanner      = false;
        _showFatigueBadge    = false;
      });
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _swapBannerTimer?.cancel();
      _handleSessionEnd(data);
      return;
    }

    // ── MODE_CHANGE from glove button ──────────────────────────────────────
    if (data['isModeChange'] == true) {
      final newMode = data['currentMode'] as int? ?? 0;
      // Only sync when idle — mid-session mode changes take effect next session
      if (!_isSessionActive) {
        ref.read(appModeProvider.notifier).setModeFromGlove(newMode);
      }
      return;
    }

    // ── SCENARIO_CHANGE from glove button ──────────────────────────────────
    if (data['isScenarioChange'] == true) {
      final newScenario = data['scenarioFromGlove'] as int? ?? 0;
      ref.read(scenarioProvider.notifier).setFromGlove(newScenario);
      return;
    }

    // ── TWO_MIN_ALERT — rescuer swap prompt ────────────────────────────────
    if (data['isTwoMinAlert'] == true) {
      setState(() {
        _showSwapBanner  = true;
        _swapAlertNumber = data['twoMinAlertNumber'] as int? ?? 1;
      });
      _swapBannerTimer?.cancel();
      _swapBannerTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _showSwapBanner = false);
      });
      return;
    }

    // ── FATIGUE_ALERT ──────────────────────────────────────────────────────
    if (data['isFatigueAlert'] == true) {
      setState(() {
        _showFatigueBadge = true;
        _fatigueScore     = data['fatigueAlertScore'] as int? ?? 0;
      });
      return;
    }

    // ── PULSE_CHECK_START ──────────────────────────────────────────────────
    if (data['isPulseCheckStart'] == true) {
      setState(() {
        _pulseCheckActive    = true;
        _pulseCheckInterval  = data['intervalNumber'] as int?;
        _pulseClassification = null;
      });
      return;
    }

    // ── PULSE_CHECK_RESULT ─────────────────────────────────────────────────
    if (data['isPulseCheckResult'] == true) {
      setState(() {
        _pulseClassification = data['pulseClassification'] as int? ?? 0;
        // Keep overlay visible for 3 s so user can read the result
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _pulseCheckActive = false);
      });
      return;
    }

    // ── LIVE_STREAM data ───────────────────────────────────────────────────
    if (data['isContinuousData'] == true || data.containsKey('depth')) {
      _updateLiveValues(data);
    }
  }

  void _updateLiveValues(Map<String, dynamic> data) {
    double? readPositive(String key) {
      final raw = data[key];
      if (raw == null) return null;
      final v = (raw as num).toDouble();
      return v > 0 ? v : null;
    }
    int? readPositiveInt(String key) {
      final raw = data[key];
      if (raw == null) return null;
      final v = (raw as num).toInt();
      return v > 0 ? v : null;
    }

    final hrP    = readPositive('heartRatePatient');
    final spo2P  = readPositive('spO2Patient');
    final tempP  = readPositive('patientTemperature');
    final hrU    = readPositive('heartRateUser');
    final spo2U  = readPositive('spO2User');
    final tempU  = readPositive('rescuerTemperature');
    final sigQ   = readPositiveInt('rescuerSignalQuality');

    if (!mounted) return;
    setState(() {
      _isSessionActive = data['isContinuousData'] == true;

      if (data.containsKey('compressionCount')) {
        _displayCompressionCount = data['compressionCount'] as int;
      }
      if (_isSessionActive) {
        if (data.containsKey('depth')) {
          _displayDepth     = (data['depth'] as num).toDouble();
        }
        if (data.containsKey('frequency')) {
          _displayFrequency = (data['frequency'] as num).toDouble();
        }
      }

      // IMU calibration status
      if (data.containsKey('imuCalibrated')) {
        _imuCalibrated = data['imuCalibrated'] as bool;
      }

      // Pulse check active from live stream (cross-check)
      if (data.containsKey('pulseCheckActive')) {
        _pulseCheckActive = data['pulseCheckActive'] as bool;
      }

      // Vitals — only update when non-null to avoid overwriting valid readings
      if (hrP   != null) _heartRatePatient   = hrP;
      if (spo2P != null) _spO2Patient = spo2P;
      if (tempP != null) _patientTemperature = tempP;
      if (hrU   != null) _heartRateUser      = hrU;
      if (spo2U != null) _spO2User           = spo2U;
      if (tempU != null) _rescuerTemperature = tempU;
      if (sigQ  != null) _rescuerSignalQuality = sigQ;
    });
  }

  // ── Session end ────────────────────────────────────────────────────────────
  Future<void> _handleSessionEnd(Map<String, dynamic> data) async {
    final currentMode = ref.read(appModeProvider);
    final scenario    = ref.read(scenarioProvider);
    final isLoggedIn  = ref.read(authStateProvider).isLoggedIn;
    final service     = ref.read(sessionServiceProvider);
    final bleConn     = ref.read(bleConnectionProvider);

    final detail = service.assembleDetail(
      summaryPacket:         data,
      events:                List.from(bleConn.compressionEvents),
      ventilationEvents:     List.from(bleConn.ventilationEvents),
      pulseCheckEvents:      List.from(bleConn.pulseCheckEvents),
      rescuerVitalSnapshots: List.from(bleConn.rescuerVitalSnapshots),
      sessionStart:          _sessionStartTime ?? DateTime.now(),
      sessionDurationSecs:   _displaySessionDuration.inSeconds,
      mode:                  currentMode.sessionModeString,
      scenario:              scenario.sessionScenarioString,
    );

    // Emergency mode: prompt login non-blocking AFTER session is assembled
    if (currentMode.isEmergency && !isLoggedIn) {
      if (!mounted) return;
      final shouldLogin = await AppDialogs.promptLogin(
        context,
        reason: 'Log in to save this session and track your progress.',
      );
      if (shouldLogin == true && mounted) {
        await context.push(const LoginScreen());
      }
      // If still not logged in after prompt, just show summary without saving
      final nowLoggedIn = ref.read(authStateProvider).isLoggedIn;
      if (!nowLoggedIn) {
        if (mounted) {
          context.push(SessionResultsScreen.fromDetail(detail: detail));
        }
        return;
      }
    }

    // Training mode: must be logged in (enforced at mode switch, but double-check)
    if (currentMode.isTraining && !isLoggedIn) {
      if (mounted) UIHelper.showError(context, 'Session not saved — please log in.');
      return;
    }

    final saved = await service.saveDetail(detail);
    if (!mounted) return;

    if (!saved) {
      UIHelper.showError(context, 'Failed to save session. Check your connection.');
    }

    // Always navigate to results — Emergency gets factual summary, Training gets grade
    context.push(SessionResultsScreen.fromDetail(detail: detail));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bleConnection = ref.watch(bleConnectionProvider);
    final currentMode   = ref.watch(appModeProvider);
    final scenario      = ref.watch(scenarioProvider);
    final sessionLocked = ref.watch(cprSessionActiveProvider);

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Stack(
        children: [
          Column(
            children: [
              // ── Mode / scenario header ─────────────────────────────────
              _ModeScenarioBanner(
                mode:         currentMode,
                scenario:     scenario,
                sessionLocked: sessionLocked,
                onScenarioToggle: sessionLocked ? null : () {
                  final notifier = ref.read(scenarioProvider.notifier);
                  notifier.toggle();
                  // Tell glove about the new scenario targets
                  final ble = ref.read(bleConnectionProvider);
                  final next = ref.read(scenarioProvider);
                  ble.sendSetTargetDepth(
                    minMm: next.targetDepthMinMm,
                    maxMm: next.targetDepthMaxMm,
                  );
                  ble.sendSetTargetRate(
                    minBpm: next.targetRateMin,
                    maxBpm: next.targetRateMax,
                  );
                },
              ),

              // ── IMU calibrating banner ─────────────────────────────────
              if (_isSessionActive && !_imuCalibrated)
                const _CalibrationBanner(),

              // ── Main content ───────────────────────────────────────────
              Expanded(
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: bleConnection.dataStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _updateDisplayValues(snapshot.data!);
                      });
                    }

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          // 1. Patient vitals
                          VitalsCard(
                            label:       'Patient Vitals',
                            heartRate:   _heartRatePatient,
                            spO2:        _spO2Patient,
                            temperature: _patientTemperature,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 2. CPR metrics
                          LiveCprMetricsCard(
                            depth:            _displayDepth,
                            frequency:        _displayFrequency,
                            cprTime:          _displaySessionDuration,
                            compressionCount: _displayCompressionCount,
                            isSessionActive:  _isSessionActive,
                            imuCalibrated:    _imuCalibrated,
                            showFatigueBadge: _showFatigueBadge,
                            fatigueScore:     _fatigueScore,
                            scenario:         scenario,
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // 3. Rescuer vitals
                          VitalsCard(
                            label:         'Your Vitals',
                            heartRate:     _heartRateUser,
                            spO2:          _spO2User,
                            temperature:   _rescuerTemperature,
                            signalQuality: _rescuerSignalQuality,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          // ── Rescuer swap banner (auto-dismissing overlay) ──────────────
          if (_showSwapBanner)
            Positioned(
              top:   0,
              left:  0,
              right: 0,
              child: _SwapBanner(
                alertNumber: _swapAlertNumber,
                onDismiss: () {
                  _swapBannerTimer?.cancel();
                  setState(() => _showSwapBanner = false);
                },
              ),
            ),

          // ── Pulse check overlay (full-width, above cards) ──────────────
          if (_pulseCheckActive)
            Positioned.fill(
              child: _PulseCheckOverlay(
                intervalNumber:   _pulseCheckInterval,
                classification:   _pulseClassification,
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ModeScenarioBanner
// Shows mode (colour-coded) + scenario toggle (Emergency only, idle only).
// ─────────────────────────────────────────────────────────────────────────────

class _ModeScenarioBanner extends StatelessWidget {
  final AppMode     mode;
  final CprScenario scenario;
  final bool        sessionLocked;
  final VoidCallback? onScenarioToggle;

  const _ModeScenarioBanner({
    required this.mode,
    required this.scenario,
    required this.sessionLocked,
    this.onScenarioToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isEmergency = mode.isEmergency;
    final bg    = isEmergency ? AppColors.primaryLight    : AppColors.warningBg;
    final color = isEmergency ? AppColors.primary         : AppColors.warning;
    final icon  = isEmergency ? Icons.emergency_outlined  : Icons.school_outlined;
    final label = isEmergency ? 'Emergency Mode'          : mode.label;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      color: bg,
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconSm, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.label(size: 13, color: color),
          ),
          const Spacer(),
          // Adult/Pediatric toggle — Emergency mode only, locked during session
          if (isEmergency)
            GestureDetector(
              onTap: sessionLocked ? null : onScenarioToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical:   AppSpacing.xxs,
                ),
                decoration: AppDecorations.chip(
                  color: color,
                  bg:    sessionLocked
                      ? AppColors.divider
                      : color.withValues(alpha: 0.15),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.swap_horiz_rounded,
                      size:  AppSpacing.iconSm - 4,
                      color: sessionLocked ? AppColors.textDisabled : color,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      scenario.label,
                      style: AppTypography.label(
                        size:  12,
                        color: sessionLocked ? AppColors.textDisabled : color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CalibrationBanner — shown at session start until imuCalibrated = true
// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationBanner extends StatelessWidget {
  const _CalibrationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.xs,
      ),
      color: AppColors.warningBg,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width:  12,
            height: 12,
            child:  CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Calibrating sensors…',
            style: AppTypography.label(size: 12, color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SwapBanner — rescuer swap prompt, auto-dismisses after 10 s
// ─────────────────────────────────────────────────────────────────────────────

class _SwapBanner extends StatelessWidget {
  final int          alertNumber;
  final VoidCallback onDismiss;

  const _SwapBanner({required this.alertNumber, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: AppColors.warning,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical:   AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.textOnDark,
                size:  AppSpacing.iconMd,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Consider switching rescuers',
                      style: AppTypography.label(
                        size:  13,
                        color: AppColors.textOnDark,
                      ),
                    ),
                    Text(
                      '2 minutes elapsed — fatigue may be setting in',
                      style: AppTypography.caption(
                        color: AppColors.textOnDark.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textOnDark,
                  size:  AppSpacing.iconSm,
                ),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PulseCheckOverlay — shown during 10-second pulse assessment window
// ─────────────────────────────────────────────────────────────────────────────

class _PulseCheckOverlay extends StatelessWidget {
  final int? intervalNumber;
  final int? classification; // null=pending, 0=absent, 1=uncertain, 2=present

  const _PulseCheckOverlay({
    this.intervalNumber,
    this.classification,
  });

  @override
  Widget build(BuildContext context) {
    final hasPendingResult = classification == null;
    final resultColor = classification == 2
        ? AppColors.success
        : classification == 1
        ? AppColors.warning
        : AppColors.emergencyRed;
    final resultLabel = classification == 2
        ? 'Pulse Detected'
        : classification == 1
        ? 'Uncertain — Continue CPR'
        : 'No Pulse — Continue CPR';
    final resultIcon = classification == 2
        ? Icons.favorite_rounded
        : Icons.favorite_border_rounded;

    return Container(
      color: AppColors.primaryDark.withValues(alpha: 0.92),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.sensors_rounded,
            size:  AppSpacing.iconXl + AppSpacing.md,
            color: AppColors.textOnDark,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            hasPendingResult ? 'PULSE CHECK' : 'PULSE CHECK RESULT',
            style: AppTypography.badge(
              size:  12,
              color: AppColors.textOnDark.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            hasPendingResult
                ? 'Assessing patient pulse…'
                : resultLabel,
            textAlign: TextAlign.center,
            style: AppTypography.poppins(
              size:   22,
              weight: FontWeight.w700,
              color:  hasPendingResult ? AppColors.textOnDark : resultColor,
            ),
          ),
          if (hasPendingResult) ...[
            const SizedBox(height: AppSpacing.lg),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnDark),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            Icon(resultIcon, size: AppSpacing.iconXl, color: resultColor),
          ],
          if (intervalNumber != null) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Check #$intervalNumber',
              style: AppTypography.caption(
                color: AppColors.textOnDark.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}