import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../account/screens/login_screen.dart';
import '../../training/services/session_local_storage.dart';
import '../../training/widgets/pulse_check_overlay.dart';
import '../../training/widgets/session_results.dart';
import '../../training/widgets/ventilation_overlay.dart';
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

  // ── Display state ──────────────────────────────────────────────────────────
  bool     _isSessionActive         = false;
  bool     _hasHandledEndPing       = false;
  int      _displayCompressionCount = 0;
  Duration _displaySessionDuration  = Duration.zero;
  double   _displayDepth            = 0.0;
  double   _displayFrequency        = 0.0;
  double _peakDepth               = 0.0;
  int    _lastSeenCompressionCount = 0;
  DateTime? _sessionStartTime;

  // ── Overlay state ──────────────────────────────────────────────────────────
  bool   _imuCalibrated      = false; // false = show calibrating banner
  bool   _showSwapBanner     = false; // true after TWO_MIN_ALERT
  int    _swapAlertNumber    = 0;
  bool   _showFatigueBadge   = false;
  int    _fatigueScore       = 0;
  bool        _recoilAchieved  = false;
  int         _compressionInCycle = 0;
  bool          _pulseCheckActive      = false;
  int?          _pulseCheckInterval;
  int?          _pulseClassification;   // null = pending, 0/1/2 = result
  double?       _pulseCheckDetectedBpm;
  int?          _pulseCheckConfidence;
  Timer?        _pulseResultTimer;
  double? _wristAngle;
  int _swapSecondsRemaining = 5;
  Timer? _swapCountdownTimer;
  int _rescuerSignalQuality = 0;

  // ── Ventilation window state ───────────────────────────────────────────────
  bool _showVentilationOverlay = false;
  int  _ventilationCycleNumber = 0;
  int  _ventilationsExpected   = 2;

  final List<double> _ppgBuffer = []; // ring buffer for ECG waveform
  static const int   _ppgBufferMax = 60;
  StreamSubscription<Map<String, dynamic>>? _bleDataSubscription;

  // ── Vitals display state ───────────────────────────────────────────────────
  double? _heartRatePatient;
  double? _spO2Patient;
  double? _patientTemperature;
  double? _heartRateUser;
  double? _spO2User;
  double? _rescuerTemperature;

  @override
  void initState() {
    super.initState();
    // Sync local sessions when BLE connects
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bleConnectionProvider).connectionStatusNotifier.addListener(_onBleStatusChange);
    });

    // Prompt Bluetooth on when screen first loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _promptBluetoothIfNeeded();
    });

    // Warn user if old sessions are silently evicted
    SessionLocalStorage.onEviction = (count) {
      if (mounted) {
        UIHelper.showWarning(
          context,
          'Oldest $count local session(s) removed — storage limit reached. '
              'Log in to sync sessions to the cloud.',
        );
      }
    };
    // ADD THIS — process BLE data via subscription, not StreamBuilder callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bleDataSubscription = ref
          .read(bleConnectionProvider)
          .dataStream
          .listen((data) {
        if (mounted) _updateDisplayValues(data);
      });
    });
  }

  Future<void> _promptBluetoothIfNeeded() async {
    final ble = ref.read(bleConnectionProvider);
    final status = ble.connectionStatusNotifier.value;
    if (status == 'Connected') return;

    // Check if BT is already on — if so, nothing to do
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.on) return;

    // Try the system prompt silently (no custom dialog before)
    try {
      await FlutterBluePlus.turnOn();
    } on FlutterBluePlusException {
      // User denied the system prompt — now show our explanation dialog
      if (mounted) {
        await AppDialogs.showAlert(
          context,
          icon:      Icons.bluetooth_disabled_rounded,
          iconColor: AppColors.emergencyRed,
          iconBg:    AppColors.emergencyBg,
          title:     'Bluetooth Required',
          message:   'The CPR Assist glove connects via Bluetooth. '
              'Please enable Bluetooth to use the glove.',
        );
      }
    } catch (_) {
      // iOS or other — system handles it automatically
    }
  }
  void _onBleStatusChange() {
    final status = ref.read(bleConnectionProvider).connectionStatusNotifier.value;
    if (status == 'Connected') {
      _syncLocalSessions();
      // Trigger automatic selftest on connect — result handled in _updateDisplayValues
      ref.read(bleConnectionProvider).sendRunSelftest();
    }
  }

  Future<void> _syncLocalSessions() async {
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
    if (!isLoggedIn) return;
    final locals  = await SessionLocalStorage.loadAll();
    final pending = locals.where((d) => !d.syncedToBackend).toList();
    if (pending.isEmpty) return;
    final service = ref.read(sessionServiceProvider);
    bool anySynced = false;
    for (final detail in pending) {
      final savedId = await service.saveDetail(detail);
      if (savedId != null) {
        await SessionLocalStorage.markSynced(detail);
        anySynced = true;
      }
    }
    // Only refresh the session list when not in an active CPR session
    if (anySynced && !_isSessionActive && mounted) {
      ref.invalidate(sessionSummariesProvider);
    }
  }

  AppMode? _nextMode(AppMode current, bool isLoggedIn) {
    switch (current) {
      case AppMode.emergency:
        if (!isLoggedIn) {
          return null;
        }
        return AppMode.training;
      case AppMode.training:
      case AppMode.trainingNoFeedback:
        return AppMode.emergency;
    }
  }

  @override
  void dispose() {
    ref.read(bleConnectionProvider).connectionStatusNotifier.removeListener(_onBleStatusChange);
    _sessionTimer?.cancel();
    _bleDataSubscription?.cancel();
    _pulseResultTimer?.cancel();
    _swapCountdownTimer?.cancel();
    SessionLocalStorage.onEviction = null;
    super.dispose();
  }

  // ── BLE data handler ───────────────────────────────────────────────────────
  void _updateDisplayValues(Map<String, dynamic> data) {
    if (data['isSelftestResult'] == true) {
      // Only auto-show warnings on connect, not when user explicitly requested it
      // (settings screen handles the explicit request case via its own subscription)
      final wasRequested = ref.read(selftestRequestedProvider);
      if (!wasRequested) {
        final critical = (data['selftestCriticalMask'] as int?) ?? 0;
        final warn     = (data['selftestWarnMask']     as int?) ?? 0;
        if (critical != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppDialogs.showAlert(
              context,
              icon:      Icons.warning_rounded,
              iconColor: AppColors.error,
              iconBg:    AppColors.errorBg,
              title:     'Sensor Error',
              message:   'A critical glove sensor failed self-test. '
                  'Check hardware before starting CPR.',
            );
            }
          });
        } else if (warn != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              UIHelper.showWarning(
              context, 'Glove sensor warning — some readings may be unreliable',
            );
            }
          });
        }
        // If all clear, no toast — connecting already shows 'Connected' status
      }
      return;
    }
    // ── SESSION_START ──────────────────────────────────────────────────────
    if (data['isStartPing'] == true) {
      _sessionStartTime = DateTime.now();
      final gloveModeInt = data['currentMode'] as int? ?? 0;
      ref.read(appModeProvider.notifier).setModeFromGlove(gloveModeInt);
      ref.read(cprSessionActiveProvider.notifier).state = true;
      final autoSwitch = ref.read(settingsProvider).autoSwitchToCPR;
      if (autoSwitch) widget.onTabTapped(1);

      setState(() {
        _compressionInCycle = 0;
        _isSessionActive         = true;
        _hasHandledEndPing       = false;
        _displayDepth            = 0.0;
        _displayFrequency        = 0.0;
        _displayCompressionCount = 0;
        _displaySessionDuration  = Duration.zero;
        _imuCalibrated           = false;
        _showSwapBanner          = false;
        _showFatigueBadge        = false;
        _fatigueScore     = 0;
        _showVentilationOverlay = false;
        _ventilationCycleNumber = 0;
        _pulseCheckActive        = false;
        _pulseClassification     = null;
        _pulseCheckDetectedBpm   = null;
        _pulseCheckConfidence    = null;
        _rescuerSignalQuality = 0;
        _ppgBuffer.clear();
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
        _showVentilationOverlay = false;
        _pulseCheckActive    = false;
        _showSwapBanner      = false;
        _showFatigueBadge    = false;
        _peakDepth                = 0.0;
        _lastSeenCompressionCount = 0;
        final total = data['totalCompressions'] as int?;
        if (total != null && total > 0) _displayCompressionCount = total;
      });
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _handleSessionEnd(data);
      return;
    }

    // ── Two-minute swap alert ──────────────────────────────────────────
    if (data['isTwoMinAlert'] == true) {
      _swapCountdownTimer?.cancel();
      setState(() {
        _showSwapBanner       = true;
        _swapAlertNumber      = (data['twoMinAlertNumber'] as int?) ?? 1;
        _swapSecondsRemaining = 10;
      });
      _swapCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _swapSecondsRemaining--);
        if (_swapSecondsRemaining <= 0) {
          t.cancel();
          setState(() => _showSwapBanner = false);
        }
      });
      return;
    }


    // ── Ventilation window ─────────────────────────────────────────────
    if (data['isVentilationWindow'] == true) {
      setState(() {
        _showVentilationOverlay = true;
        _ventilationCycleNumber = (data['cycleNumber'] as int?) ?? 1;
        _ventilationsExpected   = (data['ventilationsExpected'] as int?) ?? 2;
      });
      return;
    }

    // ── Fatigue alert ──────────────────────────────────────────────────
    if (data['isFatigueAlert'] == true) {
      setState(() {
        _showFatigueBadge = true;
        _fatigueScore     = (data['fatigueAlertScore'] as int?) ?? 0;
      });
      return;
    }

    // ── MODE_CHANGE from glove button ──────────────────────────────────────
    if (data['isModeChange'] == true) {
      final newModeInt = data['currentMode'] as int? ?? 0;
      final newMode    = AppMode.fromBleValue(newModeInt);
      if (newMode.isTraining && !ref.read(authStateProvider).isLoggedIn) {
        ref.read(bleConnectionProvider).sendModeSet(AppMode.emergency.bleValue);
        ref.read(appModeProvider.notifier).setMode(AppMode.emergency);
        if (mounted) {
          UIHelper.showWarning(context, 'Training mode requires an account.');
          AppDialogs.promptLogin(context);
        }
      } else {
        ref.read(appModeProvider.notifier).setModeFromGlove(newModeInt);
        if (mounted) {
          UIHelper.showSnackbar(
            context,
            message: 'Mode: ${newMode.label}',
            icon: Icons.swap_horiz_rounded,
          );
        }
      }
      return;
    }

    // ── SCENARIO_CHANGE from glove button ──────────────────────────────────
    if (data['isScenarioChange'] == true) {
      final newScenario = data['scenarioFromGlove'] as int? ?? 0;
      ref.read(scenarioProvider.notifier).setFromGlove(newScenario);
      return;
    }


    // ── PENDING_LOCAL_DATA — glove has offline sessions ────────────────────────
    if (data['isPendingLocalData'] == true) {
      final count = data['pendingSessionCount'] as int? ?? 0;
      if (count > 0 && mounted) {
        UIHelper.showSnackbar(
          context,
          message: '$count session(s) stored on glove — syncing now…',
          icon: Icons.sync_rounded,
        );
        _requestGloveSessions(count); // fire-and-forget, no await
      }
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
      _pulseResultTimer?.cancel();
      setState(() {
        _pulseClassification = data['pulseClassification'] as int? ?? 0;
        _pulseCheckDetectedBpm = (data['detectedBPM'] as num?)?.toDouble();
        _pulseCheckConfidence = data['confidencePct'] as int?;
      });
      // Auto-dismiss only for absent/uncertain — PRESENT stays until user decides
      final classification = data['pulseClassification'] as int? ?? 0;
      if (classification != 2) {
        _pulseResultTimer = Timer(const Duration(seconds: 120), () {
          if (mounted) setState(() => _pulseCheckActive = false);
        });
      }
    }

    // ── LIVE_STREAM data ───────────────────────────────────────────────────
    if (data['isContinuousData'] == true || data.containsKey('depth')) {
      _updateLiveValues(data);
    }
  }

  Future<void> _requestGloveSessions(int count) async {
    final ble = ref.read(bleConnectionProvider);
    for (int i = 0; i < count; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await ble.sendRequestSession(i);
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
    readPositiveInt('rescuerSignalQuality');

    // Compressions resuming — dismiss ventilation overlay
    if (_showVentilationOverlay && data['isContinuousData'] == true) {
      if ((data['compressionInCycle'] as int? ?? 0) > 0) {
        setState(() => _showVentilationOverlay = false);
      }
    }

    if (!mounted) return;
    setState(() {
      if (data.containsKey('wristAlignmentAngle')) {
        _wristAngle = (data['wristAlignmentAngle'] as num?)?.toDouble();
      }

      if (data['isContinuousData'] == true) _isSessionActive = true;

      if (data.containsKey('compressionCount')) {
        _displayCompressionCount = data['compressionCount'] as int;
      }

      if (data.containsKey('recoilAchieved')) {
        _recoilAchieved = data['recoilAchieved'] as bool;
      }

      if (data.containsKey('compressionInCycle')) {
        _compressionInCycle = (data['compressionInCycle'] as int?) ?? 0;
      }

      if (_isSessionActive) {
        if (data.containsKey('depth')) {
          _displayDepth = (data['depth'] as num).toDouble();
        }
        if (data.containsKey('frequency')) {
          _displayFrequency = (data['frequency'] as num).toDouble();
        }
        // Update peak depth only when a new compression is detected
        final newCount = data['compressionCount'] as int? ?? _displayCompressionCount;
        if (newCount > _lastSeenCompressionCount && _displayDepth > 0) {
          _lastSeenCompressionCount = newCount;
          _peakDepth = _displayDepth;
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

      // Collect ppgRaw into ring buffer during pulse check window
      if (_pulseCheckActive && data.containsKey('ppgRaw')) {
        final raw = (data['ppgRaw'] as num?)?.toDouble() ?? 0.0;
        _ppgBuffer.add(raw);
        if (_ppgBuffer.length > _ppgBufferMax) _ppgBuffer.removeAt(0);
      }

      if (tempP != null) _patientTemperature = tempP;
      if (data.containsKey('rescuerSignalQuality')) {
        _rescuerSignalQuality = (data['rescuerSignalQuality'] as int?) ?? 0;
      }
      if (_rescuerSignalQuality >= 40) {
        if (hrU   != null) _heartRateUser = hrU;
        if (spo2U != null) _spO2User      = spo2U;
      } else {
        _heartRateUser = null;
        _spO2User      = null;
      }
      if (tempU != null) _rescuerTemperature = tempU;
    });
  }

  // ── Session end ────────────────────────────────────────────────────────────
  Future<void> _handleSessionEnd(Map<String, dynamic> data) async {
    final currentMode = ref.read(appModeProvider);
    final isLoggedIn  = ref.read(authStateProvider).isLoggedIn;
    final service     = ref.read(sessionServiceProvider);
    final bleConn     = ref.read(bleConnectionProvider);

    var detail = service.assembleDetail(
      summaryPacket:         data,
      events:                List.from(bleConn.compressionEvents),
      ventilationEvents:     List.from(bleConn.ventilationEvents),
      pulseCheckEvents:      List.from(bleConn.pulseCheckEvents),
      rescuerVitalSnapshots: List.from(bleConn.rescuerVitalSnapshots),
      sessionStart:          _sessionStartTime ?? DateTime.now(),
      sessionDurationSecs:   _displaySessionDuration.inSeconds,
      mode:     currentMode.sessionModeString,
      scenario: ref.read(scenarioProvider).sessionScenarioString,
    );

    // ── Emergency + not logged in: offer login once, non-blocking ─────────────
    if (currentMode == AppMode.emergency && !isLoggedIn) {
      if (!mounted) return;
      final shouldLogin = await AppDialogs.promptLogin(
        context,
        reason: 'Log in to save this session and track your progress.',
      );
      if (shouldLogin == true && mounted) {
        await context.push(const LoginScreen());
      }

      final nowLoggedIn = ref.read(authStateProvider).isLoggedIn;
      if (!nowLoggedIn) {
        // Not logged in — save locally and go to results
        await service.saveLocalOnly(detail);
        if (mounted) {
          ref.invalidate(sessionSummariesProvider);
          context.push(SessionResultsScreen.fromDetail(detail: detail));
        }
        return;
      }
    }

    if (!mounted) return;

    // ── Attempt backend save ───────────────────────────────────────────────────
    final savedId = await service.saveDetail(detail);
    if (!mounted) return;

    if (savedId != null) {
      // Stamp the backend id onto the detail so the results screen can edit note/delete
      detail = detail.withId(savedId);
      ref.invalidate(sessionSummariesProvider);
    } else {
      // Backend save failed — always save locally as fallback
      await service.saveLocalOnly(detail);
      ref.invalidate(sessionSummariesProvider);
      if (mounted) {
        UIHelper.showWarning(
          context, 'Could not sync to server — session saved locally.',
        );
      }
    }

    if (mounted) {
      context.push(SessionResultsScreen.fromDetail(detail: detail));
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);

    ref.watch(bleConnectionProvider);
    final currentMode = ref.watch(appModeProvider);
    final scenario = ref.watch(scenarioProvider);
    final sessionLocked = ref.watch(cprSessionActiveProvider);

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Stack(
        children: [
          Column(
            children: [
              _StatusBar(
                mode: currentMode,
                scenario: scenario,
                sessionLocked: sessionLocked,
                onScenarioToggle: () {
                  ref.read(scenarioProvider.notifier).toggle();
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
                onModeToggle: sessionLocked
                    ? null
                    : () async {
                  final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
                  if (currentMode == AppMode.emergency && !isLoggedIn) {
                    if (!mounted) return;
                    final shouldLogin = await AppDialogs.promptLogin(context);
                    if (shouldLogin == true && mounted) {
                      await context.push(const LoginScreen());
                    }
                    return;
                  }
                  final next = _nextMode(currentMode, true);
                  if (next == null || !mounted) return;
                  ref.read(bleConnectionProvider).sendModeSet(next.bleValue);
                  ref.read(appModeProvider.notifier).setMode(next);
                },

                onNoFeedbackToggle: sessionLocked
                    ? null
                    : () {
                  final next = currentMode.isNoFeedback
                      ? AppMode.training
                      : AppMode.trainingNoFeedback;
                  ref.read(appModeProvider.notifier).setMode(next);
                  ref.read(bleConnectionProvider).sendModeSet(next.bleValue);
                },
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      // ── Patient vitals — only after confirmed pulse ───────
                      if (_pulseClassification == 2 &&
                          (_pulseCheckConfidence ?? 0) >= 40) ...[
                        VitalsCard(
                          label:           'Patient Vitals',
                          heartRate:       _heartRatePatient,
                          spO2:            _spO2Patient,
                          temperature:     _patientTemperature,
                          pulseConfidence: _pulseCheckConfidence,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // ── Wrist angle warning ───────────────────────────────
                      if (_isSessionActive &&
                          _wristAngle != null &&
                          _wristAngle! > 15.0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical:   AppSpacing.xs,
                            ),
                            decoration: AppDecorations.warningBanner(),
                            child: Row(
                              children: [
                                const Icon(Icons.back_hand_outlined,
                                    size: 14, color: AppColors.warning),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Text(
                                    'Wrist angle ${_wristAngle!.toStringAsFixed(0)}°. Try to keep arms straight',
                                    style: AppTypography.label(
                                        size: 12, color: AppColors.warning),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // ── CPR metrics card ─────────────────────────────────
                      if (ref.watch(settingsProvider).showCprMetrics) ...[
                        LiveCprMetricsCard(
                          depth:              _displayDepth,
                          peakDepth: _peakDepth,
                          frequency:          _displayFrequency,
                          cprTime:            _displaySessionDuration,
                          compressionCount:   _displayCompressionCount,
                          isSessionActive:    _isSessionActive,
                          scenario:           scenario,
                          recoilAchieved:     _recoilAchieved,
                          imuCalibrated:      _imuCalibrated,
                          showFatigueBadge:   _showFatigueBadge,
                          fatigueScore:       _fatigueScore,
                          compressionInCycle: _compressionInCycle,
                          isNoFeedback:       currentMode.isNoFeedback,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // ── Rescuer vitals — always shown ────────────────────
                      VitalsCard(
                        label:                'Your Vitals',
                        heartRate:            _heartRateUser,
                        spO2:                 _spO2User,
                        temperature:          _rescuerTemperature,
                        rescuerSignalQuality: _rescuerSignalQuality > 0 ? _rescuerSignalQuality : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (_showVentilationOverlay)
            Positioned.fill(
              child: VentilationOverlay(
                cycleNumber:          _ventilationCycleNumber,
                ventilationsExpected: _ventilationsExpected,
                onDismiss: () => setState(() => _showVentilationOverlay = false),
              ),
            ),

          if (_showSwapBanner)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _SwapBanner(
                alertNumber: _swapAlertNumber,
                onDismiss: () {
                  setState(() => _showSwapBanner = false);
                },
              ),
            ),

          if (_pulseCheckActive)
            Positioned.fill(
              child: PulseCheckOverlay(
                intervalNumber: _pulseCheckInterval,
                classification: _pulseClassification,
                ppgBuffer: List.from(_ppgBuffer),
                detectedBpm: _pulseCheckDetectedBpm,
                confidence: _pulseCheckConfidence,
                onContinueCpr: () {
                  _pulseResultTimer?.cancel();
                  setState(() => _pulseCheckActive = false);
                },
                onStopCpr: () {
                  _pulseResultTimer?.cancel();
                  setState(() => _pulseCheckActive = false);
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SwapBanner — rescuer swap prompt, auto-dismisses after 10 s
// ─────────────────────────────────────────────────────────────────────────────

class _SwapBanner extends StatefulWidget {
  final int          alertNumber;
  final VoidCallback onDismiss;

  const _SwapBanner({required this.alertNumber, required this.onDismiss});

  @override
  State<_SwapBanner> createState() => _SwapBannerState();
}

class _SwapBannerState extends State<_SwapBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0,
        ),
        child: Container(
          width: double.infinity,
          decoration: AppDecorations.card(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm,
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Container(
                  width:  32,
                  height: 32,
                  decoration: AppDecorations.iconCircle(
                    bg: AppColors.primaryLight,
                  ),
                  child: const Icon(
                    Icons.people_alt_outlined,
                    color: AppColors.primary,
                    size:  16,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CPR in progress for ${widget.alertNumber * 2} minutes',
                        style: AppTypography.label(size: 13),
                      ),
                      Text(
                        'Consider switching rescuer to maintain quality',
                        style: AppTypography.caption(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textSecondary,
                    size:  AppSpacing.iconSm,
                  ),
                  onPressed: widget.onDismiss,
                  padding:     EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final AppMode       mode;
  final CprScenario   scenario;
  final bool          sessionLocked;
  final VoidCallback? onScenarioToggle;
  final VoidCallback? onModeToggle;
  final VoidCallback? onNoFeedbackToggle;

  const _StatusBar({
    required this.mode,
    required this.scenario,
    required this.sessionLocked,
    this.onScenarioToggle,
    this.onModeToggle,
    this.onNoFeedbackToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isEmergency  = mode.isEmergency;
    final isNoFeedback = mode.isNoFeedback;
    final modeColor    = isEmergency ? AppColors.primary : AppColors.warning;
    final modeBg       = isEmergency ? AppColors.primaryLight : AppColors.warningBg;
    final modeLabel    = isEmergency ? 'Emergency' : 'Training';
    final scenarioColor = scenario == CprScenario.pediatric
        ? AppColors.pediatric
        : modeColor;

    return Container(
      width: double.infinity,
      height: 32.0,   // or use AppSpacing — add statusBarHeight = 32.0 to AppSpacing
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      color: modeBg,
      child: Row(
        children:[
          GestureDetector(
            onTap: () => AppDialogs.showAlert(
              context,
              title:   isEmergency ? 'Emergency Mode' : 'Training Mode',
              message: isEmergency
                  ? 'Emergency mode guides you through a real cardiac arrest. '
                  'No login required. Session saved locally and synced later.'
                  : isNoFeedback
                  ? 'No-Feedback mode suppresses all glove feedback — audio, '
                  'vibration and LEDs. Your session is still fully recorded and graded.'
                  : 'Training mode records and grades your CPR on a manikin. '
                  'Requires a logged-in account.',
            ),
            child: Icon(Icons.info_outline_rounded, size: 12, color: modeColor.withValues(alpha: 0.55)),
          ),
          const SizedBox(width: AppSpacing.xxs),

          // ── LEFT: Mode swap ──────────────────────────────────────────────
          GestureDetector(
            onTap: (sessionLocked || onModeToggle == null) ? null : onModeToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  modeLabel,
                  style: AppTypography.label(
                    size:  12,
                    color: (sessionLocked || onModeToggle == null)
                        ? AppColors.textDisabled
                        : modeColor,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.swap_horiz_rounded,
                  size:  12,
                  color: (sessionLocked || onModeToggle == null)
                      ? AppColors.textDisabled
                      : modeColor,
                ),
              ],
            ),
          ),

          // ── Info icon ────────────────────────────────────────────────────

          // ── No-Feedback pill (training only) ─────────────────────────────
          if (!isEmergency) ...[
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: (sessionLocked || onNoFeedbackToggle == null)
                  ? null
                  : onNoFeedbackToggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isNoFeedback
                      ? AppColors.warning
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  border: Border.all(
                    color: AppColors.warning.withValues(
                        alpha: isNoFeedback ? 0.0 : 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sensors_off_rounded,
                      size:  10,
                      color: isNoFeedback
                          ? AppColors.textOnDark
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'No feedback',
                      style: AppTypography.label(
                        size:  10,
                        color: isNoFeedback
                            ? AppColors.textOnDark
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          // ── RIGHT: Scenario swap ─────────────────────────────────────────
          GestureDetector(
            onTap: (sessionLocked || onScenarioToggle == null)
                ? null
                : onScenarioToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  scenario.label,
                  style: AppTypography.label(
                    size:  12,
                    color: sessionLocked
                        ? AppColors.textDisabled
                        : scenarioColor,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.swap_horiz_rounded,
                  size:  12,
                  color: sessionLocked
                      ? AppColors.textDisabled
                      : scenarioColor,
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
}