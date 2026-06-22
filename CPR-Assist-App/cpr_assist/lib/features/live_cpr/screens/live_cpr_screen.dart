import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../main.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../account/screens/login_screen.dart';
import '../../training/services/session_detail.dart';
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
  double _valleyDepth             = 0.0;
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
  int?          _pulseClassification;      // null = pending, final result from event
  int?          _livePulseClassification;  // 0/1/2 inferred from live stream during window
  int           _bestPulseClassification = 0; // highest seen (best wins for storage)
  double?       _pulseCheckDetectedBpm;
  int?          _pulseCheckConfidence;
  int           _livePpgSignalQuality = 0;
  double        _liveHeartRatePatient = 0.0;
  Timer?        _pulseResultTimer;
  bool _hasCompletedPulseCheck = false;
  int _swapSecondsRemaining = 10;
  Timer? _swapCountdownTimer;
  int _rescuerSignalQuality = 0;

  // ── Ventilation window state ───────────────────────────────────────────────
  bool _showVentilationOverlay = false;
  int  _ventilationCycleNumber = 0;
  int _ventilationsExpected = 2;
// compressionCount when overlay opened; null = closed

  final List<double> _ppgBuffer = []; // ring buffer for ECG waveform
  static const int   _ppgBufferMax = 150;
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

    liveCprTabActivationNotifier.addListener(_onTabActivated);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = ref.read(bleConnectionProvider);
      _bleDataSubscription = ble.dataStream.listen((data) {
        if (mounted) _updateDisplayValues(data);
      });
      // Reassembled offline sessions from glove flash storage.
      // Overrides the provider-level handler while this screen is mounted,
      // adding a snackbar confirmation. Cleared in dispose().
      ble.onOfflineSessionParsed = _handleOfflineSession;
    });
  }

  Future<void> _handleOfflineSession(SessionDetail detail, int sessionIndex) async {
    final service = ref.read(sessionServiceProvider);
    final ble     = ref.read(bleConnectionProvider);
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;

    // Offline parser doesn't compute a grade — do it here for training sessions.
    // Emergency sessions always stay at grade 0.
    if (detail.mode != 'emergency') {
      detail = detail.withGrade(service.calculateGradeFromDetail(detail));
    }

    // Always save locally first
    await service.saveLocalOnly(detail);

    // If logged in, try to push to backend
    int? savedId;
    if (isLoggedIn) {
      savedId = await service.saveDetail(detail);
      if (savedId != null) {
        detail = detail.withId(savedId);
        await SessionLocalStorage.markSynced(detail);
      }
    }

    // Tell the glove it's safe to delete this slot, regardless of backend status.
    // We have a local copy and will retry backend later via _syncLocalSessions.
    await ble.sendConfirmReceived(sessionIndex);

    if (mounted) {
      ref.invalidate(sessionSummariesProvider);
      final didSync = savedId != null;
      UIHelper.showSnackbar(
        context,
        message: didSync
            ? 'Glove session synced (${detail.compressionCount} compressions)'
            : 'Glove session saved locally (${detail.compressionCount} compressions)',
        icon: didSync ? Icons.cloud_done_rounded : Icons.save_rounded,
      );
    }
  }

  void _onTabActivated() {
    // Only auto-prompt for Bluetooth if the user has already granted
    // BLE permissions in a previous session. First-time permission
    // is handled by the BLE icon tap in the header.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = ref.read(bleConnectionProvider);
      if (ble.connectionStatusNotifier.value == 'Ready') return; // never granted yet
      _promptBluetoothIfNeeded();
    });
  }

  Future<void> _promptBluetoothIfNeeded() async {
    debugPrint('🔵 _promptBluetoothIfNeeded called');
    final ble = ref.read(bleConnectionProvider);
    final status = ble.connectionStatusNotifier.value;
    debugPrint('🔵 BLE status: $status');
    if (status == 'Connected') { debugPrint('🔵 returning — already connected'); return; }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.on) return;

    try {
      await FlutterBluePlus.turnOn();
    } on FlutterBluePlusException {
      if (mounted) {
        await AppDialogs.showAlert(
          context,
          icon:      Icons.bluetooth_disabled_rounded,
          iconColor: AppColors.emergency,
          iconBg:    AppColors.errorBg,
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
      ref.read(bleConnectionProvider).markPermissionsGranted();
      _syncLocalSessions();
      // Self-test is user-initiated only (Settings → Run self-test or the
      // Glove diagnostic sheet). Running it automatically on every connect
      // adds 300–500 ms of I²C bus contention right when the user is
      // already on the live-CPR screen, and can stall LIVE_STREAM packets.
      return;
    }

    if (!mounted) return;

    // Reconnect exhausted during active session — glove is unreachable but
    // still recording. The 60 s watchdog in BLEConnection will synthesise
    // SESSION_END. Tell the rescuer to keep going and that data is safe.
    if (status == 'Connection Lost — Session Running on Glove') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        UIHelper.showWarning(
          context,
          'Glove unreachable — keep performing CPR. '
              'Session will be recovered when glove reconnects.',
        );
      });
      return;
    }

    final notify = ref.read(settingsProvider).notifyOnDisconnect;
    if (!notify) return;

    if (status.contains('Reconnecting') || status.contains('Disconnected')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_isSessionActive) {
          UIHelper.showWarning(
            context,
            'Glove disconnected — reconnecting. Keep performing CPR.',
          );
        } else {
          UIHelper.showWarning(context, 'Glove disconnected.');
        }
      });
    }
  }

  Future<void> _syncLocalSessions() async {
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
    if (!isLoggedIn) return;
    if (ref.read(settingsProvider).syncWifiOnly) {
      final results = await Connectivity().checkConnectivity();
      if (!results.contains(ConnectivityResult.wifi)) return;
    }
    final locals  = await SessionLocalStorage.loadAll();
    final pending = locals.where((d) => !d.syncedToBackend).toList();
    if (pending.isEmpty) return;
    final service = ref.read(sessionServiceProvider);
    bool anySynced = false;
    for (var detail in pending) {
      final savedId = await service.saveDetail(detail);
      debugPrint('🔵 saveDetail returned: $savedId');
      if (savedId != null) {
        detail = detail.withId(savedId);
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
    liveCprTabActivationNotifier.removeListener(_onTabActivated);
    // Clear the screen-level offline session handler so the provider-level
    // fallback takes over when this screen is not mounted.
    ref.read(bleConnectionProvider).onOfflineSessionParsed = null;
    super.dispose();
  }

  // ── BLE data handler ───────────────────────────────────────────────────────
  void _updateDisplayValues(Map<String, dynamic> data) {
    if (data['isSelftestResult'] == true) {
      final wasCalibration = ref.read(calibrationPendingProvider);
      final wasRequested   = ref.read(selftestRequestedProvider);

      if (wasCalibration) ref.read(calibrationPendingProvider.notifier).state = false;
      ref.read(selftestRequestedProvider.notifier).state = false;

      final critical = (data['selftestCriticalMask'] as int?) ?? 0;
      final warn     = (data['selftestWarnMask']     as int?) ?? 0;

      if (wasCalibration) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (critical != 0) {
            AppDialogs.showAlert(
              context,
              icon:      Icons.warning_rounded,
              iconColor: AppColors.error,
              iconBg:    AppColors.errorBg,
              title:     'Calibration failed',
              message:   'A sensor error was detected after recalibration. '
                  'Run Sensor Check in Glove Maintenance for details.',
            );
          } else {
            UIHelper.showSuccess(context, 'Calibration complete — force sensor zeroed.');
          }
        });
        return;
      }

      if (!wasRequested) {
        if (critical != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            AppDialogs.showAlert(
              context,
              icon:      Icons.warning_rounded,
              iconColor: AppColors.error,
              iconBg:    AppColors.errorBg,
              title:     'Sensor Error',
              message:   'A critical glove sensor failed self-test. '
                  'Check hardware before starting CPR.',
            );
          });
        } else if (warn != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            UIHelper.showWarning(
                context, 'Glove sensor warning — some readings may be unreliable');
          });
        }
      }
      return;
    }

    // ── SESSION_START ──────────────────────────────────────────────────────
    if (data['isStartPing'] == true) {
      _sessionStartTime = DateTime.now();
      final gloveModeInt = data['currentMode'] as int? ?? 0;
      ref.read(appModeProvider.notifier).setModeFromGlove(gloveModeInt);
      ref.read(cprSessionActiveProvider.notifier).state = true;

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
        _hasCompletedPulseCheck = false;
        _pulseCheckDetectedBpm   = null;
        _pulseCheckConfidence    = null;
        _heartRatePatient = null;
        _spO2Patient = null;
        _patientTemperature = null;
        _heartRateUser = null;
        _spO2User = null;
        _rescuerTemperature = null;
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

    // ── Two-minute swap alert ──────────────────────────────────────────────
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

    // ── Ventilation window ─────────────────────────────────────────────────
    if (data['isVentilationWindow'] == true) {
      final ratio = ref.read(settingsProvider).ventilationRatio;
      if (ratio == 'compressions_only') return;
      setState(() {
        _showVentilationOverlay = true;
        _ventilationCycleNumber = (data['cycleNumber'] as int?) ?? 1;
        _ventilationsExpected   = (data['ventilationsExpected'] as int?) ?? 2;
      });
      return;
    }

    // ── Fatigue alert ──────────────────────────────────────────────────────
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

    // ── PENDING_LOCAL_DATA — glove has offline sessions ────────────────────
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
      _ppgBuffer.clear();
      setState(() {
        _pulseCheckActive         = true;
        _pulseCheckInterval       = data['intervalNumber'] as int?;
        _pulseClassification      = null;
        _livePulseClassification  = null;
        _bestPulseClassification  = 0;
        _livePpgSignalQuality     = 0;
        _liveHeartRatePatient     = 0.0;
        _pulseCheckDetectedBpm    = null;
        _pulseCheckConfidence     = null;
      });
      return;
    }

    // ── PULSE_CHECK_RESULT ─────────────────────────────────────────────────
    if (data['isPulseCheckResult'] == true) {
      final eventClass = data['pulseClassification'] as int? ?? 0;
      final best = eventClass > _bestPulseClassification
          ? eventClass
          : _bestPulseClassification;
      setState(() {
        _hasCompletedPulseCheck  = true;
        _pulseClassification     = best;
        _livePulseClassification = best;
        _pulseCheckDetectedBpm   = (data['detectedBPM'] as num?)?.toDouble();
        _pulseCheckConfidence    = data['confidencePct'] as int?;
      });
    }

    // ── LIVE_STREAM data ───────────────────────────────────────────────────
    if (data['isContinuousData'] == true) {
      _updateLiveValues(data);
    }
  }

  Future<void> _requestGloveSessions(int count) async {
    // Never pull offline sessions while a live session is active —
    // EVENT_CHANNEL write contention would corrupt the live stream.
    // The glove will re-send PENDING_LOCAL_DATA on the next connection.
    if (_isSessionActive) return;
    final ble = ref.read(bleConnectionProvider);
    for (int i = 0; i < count; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      if (_isSessionActive) return; // re-check after each delay
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

    if (data['isContinuousData'] == true && !_isSessionActive && !_hasHandledEndPing) {
      ref.read(cprSessionActiveProvider.notifier).state = true;
    }

    final rescuerSq = (data['rescuerSignalQuality'] as int?) ?? 0;
    final patientSq = (data['ppgSignalQuality'] as int?) ?? 0;
    final inPulseCheck = data['pulseCheckActive'] == true;

    final hrP    = (inPulseCheck && patientSq >= 40) ? readPositive('heartRatePatient') : null;
    final spo2P  = (inPulseCheck && patientSq >= 40) ? readPositive('spO2Patient')      : null;
    // patientTemperature is from MAX30205, gated on skin contact (IR DC) in
    // firmware — NOT on PPG pulse quality. A pulseless patient still has a
    // valid skin temp, so do not couple it to ppgSignalQuality. Show it
    // whenever a pulse-check window provided a reading.
    final tempP  = inPulseCheck ? readPositive('patientTemperature') : null;
    final hrU    = readPositive('heartRateUser');
    final spo2U  = readPositive('spO2User');
    final tempU  = readPositive('rescuerTemperature');  // GXHT30, always valid
    final humU   = readPositiveInt('rescuerHumidity');

    if (!mounted) return;
    setState(() {

      if (data['isContinuousData'] == true && !_hasHandledEndPing) {
        _isSessionActive = true;
        // Start timer if SESSION_START was missed
        if (_sessionTimer == null || !_sessionTimer!.isActive) {
          _sessionStartTime ??= DateTime.now();
          _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted && _isSessionActive) {
              setState(() {
                _displaySessionDuration = Duration(
                  seconds: DateTime.now().difference(_sessionStartTime!).inSeconds,
                );
              });
            }
          });
        }
      }

      if (data.containsKey('compressionCount')) {
        _displayCompressionCount = data['compressionCount'] as int;
      }

      // Ventilation overlay visibility is firmware-driven: the glove
      // streams inVentilationWindow in LIVE_STREAM byte 86 and owns the
      // open/close/compliant logic. The app only mirrors that flag.
      if (data.containsKey('inVentilationWindow')) {
        final fwVentOpen = data['inVentilationWindow'] == true;
        if (!fwVentOpen && _showVentilationOverlay) {
          _showVentilationOverlay = false;
        }
      }

      if (data.containsKey('recoilAchieved')) {
        _recoilAchieved = data['recoilAchieved'] as bool;
        if (_recoilAchieved) {
          final vd = (data['valleyDepth'] as num?)?.toDouble() ?? 0.0;
          if (vd >= 0) _valleyDepth = vd;
        }
      }

      if (data.containsKey('compressionInCycle')) {
        _compressionInCycle = (data['compressionInCycle'] as int?) ?? 0;
      }

      if (_isSessionActive) {
        if (data.containsKey('depth')) {
          _displayDepth = (data['depth'] as num).toDouble();
        }
        if (data.containsKey('instantaneousRate')) {
          _displayFrequency = (data['instantaneousRate'] as num).toDouble();
        }
        final newCount = data['compressionCount'] as int? ?? _displayCompressionCount;
        if (newCount > _lastSeenCompressionCount) {
          _lastSeenCompressionCount = newCount;
          final lp = (data['lastPeakDepthCm'] as num?)?.toDouble() ?? 0.0;
          if (lp > 0) {
            _peakDepth    = lp;
          }
        }
      }

      if (data.containsKey('imuCalibrated')) {
        _imuCalibrated = data['imuCalibrated'] as bool;
      }

      if (data.containsKey('pulseCheckActive')) {
        final active = data['pulseCheckActive'] as bool;
        if (!active && _pulseCheckActive) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) setState(() => _pulseCheckActive = false);
          });
        } else if (active && !_pulseCheckActive) {
          _pulseCheckActive = true;
        }
      }

      if (hrP   != null) _heartRatePatient   = hrP;
      if (spo2P != null) _spO2Patient = spo2P;

      if (_pulseCheckActive && data.containsKey('ppgRaw')) {
        final raw = (data['ppgRaw'] as num?)?.toDouble() ?? 0.0;
        if (raw > 0) {
          _ppgBuffer.add(raw);
          if (_ppgBuffer.length > _ppgBufferMax) _ppgBuffer.removeAt(0);
        }
      }

      if (_pulseCheckActive) {
        final sq = (data['ppgSignalQuality'] as int?) ?? 0;
        final hr = (data['heartRatePatient'] as num?)?.toDouble() ?? 0.0;
        _livePpgSignalQuality = sq;
        _liveHeartRatePatient = hr;

        int liveClass;
        if (sq < 40) {
          liveClass = 0;
        } else if (sq >= 60 && hr >= 30.0 && hr <= 180.0) {
          liveClass = 2;
        } else if (sq >= 40) {
          liveClass = 1;
        } else {
          liveClass = 0;
        }

        if (liveClass > _bestPulseClassification) {
          _bestPulseClassification = liveClass;
        }
        _livePulseClassification = _bestPulseClassification > 0
            ? _bestPulseClassification
            : (sq >= 40 ? 1 : null);
      }

      if (tempP != null) _patientTemperature = tempP;
      if (data.containsKey('rescuerSignalQuality')) {
        _rescuerSignalQuality = (data['rescuerSignalQuality'] as int?) ?? 0;
      }
      if (hrU   != null && hrU   > 0) _heartRateUser = hrU;
      if (spo2U != null && spo2U > 0) _spO2User      = spo2U;
      if (tempU != null) _rescuerTemperature = tempU;
    });
  }

  // ── Session end ────────────────────────────────────────────────────────────
  Future<void> _handleSessionEnd(Map<String, dynamic> data) async {
    final currentMode = ref.read(appModeProvider);
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
    final service = ref.read(sessionServiceProvider);
    final bleConn = ref.read(bleConnectionProvider);
    final container = ProviderScope.containerOf(context, listen: false);

    final endTime = DateTime.now();
    final sessionStartTs = _sessionStartTime ?? DateTime.now();
    final totalComps = (data['totalCompressions'] as int?) ?? 0;
    final wasInterrupted = data['wasInterrupted'] == true;

    // Trivial session — too few compressions to save.
    if (totalComps < AppConstants.minCompressionsToSave && !wasInterrupted) {
      if (mounted) {
        UIHelper.showSnackbar(
          context,
          message: 'Session too short — not saved.',
          icon: Icons.info_outline,
        );
      }
      return;
    }

    // Interrupted session — save what we have; glove will sync full version later.
    if (wasInterrupted && mounted) {
      UIHelper.showWarning(
        context,
        'Glove disconnected — saving partial session. '
            'Reconnect to recover the full version.',
      );
    }

    var detail = service.assembleDetail(
      summaryPacket: data,
      events: List.from(bleConn.compressionEvents),
      ventilationEvents: List.from(bleConn.ventilationEvents),
      pulseCheckEvents: List.from(bleConn.pulseCheckEvents),
      rescuerVitalSnapshots: List.from(bleConn.rescuerVitalSnapshots),
      sessionStart: sessionStartTs,
      sessionEnd:   endTime,
      sessionDurationSecs: _displaySessionDuration.inSeconds,
      mode: currentMode.sessionModeString,
      scenario: ref.read(scenarioProvider).sessionScenarioString,
      ventilationRatio: ref.read(settingsProvider).ventilationRatio,
      twoMinAlertTimestampsMs: List.from(bleConn.twoMinAlertTimestampsMs),
      fatigueAlertTimestampMs: bleConn.fatigueAlertTimestampMs,
      fatigueAlertScore: bleConn.fatigueAlertScore,
    );

    // ALWAYS persist locally first — before any dialog or navigation.
    final localOk = await service.saveLocalOnly(detail);
    container.invalidate(sessionSummariesProvider);
    if (!localOk && mounted) {
      UIHelper.showWarning(context, 'Session could not be saved on this device.');
    }

    // Emergency + not logged in: offer login once, non-blocking
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
        if (mounted) context.push(SessionResultsScreen(detail: detail));
        return;
      }
    }

    if (!mounted) return;
    final savedId = await service.saveDetail(detail);
    if (!mounted) return;

    if (savedId != null) {
      detail = detail.withId(savedId);
    }
    container.invalidate(sessionSummariesProvider);

    if (savedId == null) {
      if (mounted) {
        UIHelper.showWarning(context, 'Could not sync to server — session saved locally.');
      }
    } else {
      await SessionLocalStorage.markSynced(detail);
    }
    if (mounted) context.push(SessionResultsScreen(detail: detail));
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
      color: AppColors.headerSurface,
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
                  ble.sendSetScenario(next.bleValue);
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
                  final goingToTraining = currentMode == AppMode.emergency;

                  if (goingToTraining && !isLoggedIn) {
                    if (!mounted) return;
                    final shouldLogin = await AppDialogs.promptLogin(context);
                    if (shouldLogin != true || !mounted) return;
                    await context.push(const LoginScreen());
                    if (!mounted) return;
                    if (!ref.read(authStateProvider).isLoggedIn) return;
                  }

                  if (goingToTraining) {
                    final confirmed = await AppDialogs.confirmSwitchToTraining(context);
                    if (confirmed != true || !mounted) return;
                  } else {
                    final confirmed = await AppDialogs.confirmSwitchToEmergency(context);
                    if (confirmed != true || !mounted) return;
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
                      if (_hasCompletedPulseCheck) ...[
                        VitalsCard(
                          label:           'Patient Vitals',
                          heartRate:       _heartRatePatient,
                          spO2:            _spO2Patient,
                          temperature:     _patientTemperature,
                          pulseConfidence: _pulseCheckConfidence,
                          greyedOut:       !_pulseCheckActive,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      LiveCprMetricsCard(
                        depth:              _displayDepth,
                        peakDepth:          _peakDepth,
                        valleyDepth:        _valleyDepth,
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
                        isVentilationWindow: _showVentilationOverlay,
                        isNoFeedback:       currentMode.isNoFeedback,
                      ),
                      const SizedBox(height: AppSpacing.md),

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
                onDismiss: () => setState(() {}),
              ),
            ),

          if (_showSwapBanner)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _SwapBanner(
                alertNumber: _swapAlertNumber,
                onDismiss: () => setState(() => _showSwapBanner = false),
              ),
            ),

          if (_pulseCheckActive)
            Positioned.fill(
              child: PulseCheckOverlay(
                intervalNumber: _pulseCheckInterval,
                classification: _livePulseClassification,
                liveBpm: _liveHeartRatePatient > 0 ? _liveHeartRatePatient : null,
                ppgBuffer: List.from(_ppgBuffer),
                detectedBpm: _pulseCheckDetectedBpm,
                confidence: _pulseCheckConfidence != null
                    ? _pulseCheckConfidence
                    : (_livePpgSignalQuality > 0 ? _livePpgSignalQuality : null),
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
                  decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
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
                  constraints: const BoxConstraints(
                    minWidth:  AppSpacing.statusBarHeight,
                    minHeight: AppSpacing.statusBarHeight,
                  ),
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
    final modeColor = isEmergency ? AppColors.emergencyMode : AppColors.primary;
    const modeBg    = AppColors.primaryLight;
    final modeLabel    = isEmergency ? 'Emergency' : 'Training';
    final scenarioColor = scenario == CprScenario.pediatric
        ? AppColors.pediatric
        : modeColor;

    return Container(
      width: double.infinity,
      height: AppSpacing.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      color: modeBg,
      child: Row(
        children: [
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
                const SizedBox(width: AppSpacing.xxs),
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
                const SizedBox(width: AppSpacing.xxs),
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