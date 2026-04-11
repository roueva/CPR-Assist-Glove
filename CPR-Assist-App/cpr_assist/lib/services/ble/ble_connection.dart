import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpr_assist/core/core.dart';

import '../../features/training/services/compression_event.dart';
import '../../features/training/services/ventilation_event.dart';
import '../../features/training/services/pulse_check_event.dart';
import '../../features/training/services/rescuer_vital_snapshot.dart';
import 'ble_data_processor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEConnection  —  BLE Spec v3.0
//
// Manages the full lifecycle of the CPR Assist Glove BLE connection:
//   scan → connect → MTU negotiation → discover services →
//   subscribe LIVE_STREAM + EVENT_CHANNEL → auto-reconnect on drop.
//
// Two separate characteristic subscriptions per spec v3.0 Section 2:
//   LIVE_STREAM   19b10001-...  100 bytes, 10 Hz notify
//   EVENT_CHANNEL 19b10002-...  80  bytes, on-event notify + write
//
// Parsed packets are broadcast on [dataStream].
// Session event lists are accumulated here and exposed to SessionService
// via read-only getters after SESSION_END.
//
// Rules:
//   - All timing constants from AppConstants — no magic Duration literals.
//   - All debug output via debugPrint (stripped in release builds).
//   - No UI code, no colors, no spacing.
// ─────────────────────────────────────────────────────────────────────────────

// BLE service and characteristic UUIDs
const String _kServiceUuid    = '19b10000-e8f2-537e-4f6c-d104768a1214';
const String _kLiveStreamUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
const String _kEventChanUuid  = '19b10002-e8f2-537e-4f6c-d104768a1214';

class BLEConnection {
  // ── BLE processor ─────────────────────────────────────────────────────────
  final _processor = const BLEDataProcessor();

  // ── Broadcast stream — all parsed packets reach the UI via this ───────────
  final _dataController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  // ── Public state notifiers (battery pill, connection status) ─────────────
  final ValueNotifier<String> connectionStatusNotifier = ValueNotifier('Disconnected');
  final ValueNotifier<int>    batteryPercentageNotifier = ValueNotifier(0);
  final ValueNotifier<bool>   isChargingNotifier        = ValueNotifier(false);

  // ── Session event accumulators ────────────────────────────────────────────
  // Cleared on SESSION_START, read by SessionService on SESSION_END.
  final List<CompressionEvent>     _compressionEvents     = [];
  final List<VentilationEvent>     _ventilationEvents     = [];
  final List<PulseCheckEvent>      _pulseCheckEvents      = [];
  final List<RescuerVitalSnapshot> _rescuerVitalSnapshots = [];

  // ── Session state ─────────────────────────────────────────────────────────
  int    _sessionStartMs     = 0;
  int    _sessionMode        = 0;   // 0=emergency 1=training 2=no_feedback
  bool   _sessionActive      = false;
  bool   _pulseCheckOpen     = false;
  int _connectTimestampMs = 0;

  // ── Rescuer vital sampling state ──────────────────────────────────────────
  int _lastVitalSnapshotMs = 0;
  static const int _vitalSnapshotIntervalMs = 5000; // sample every 5 s

  // ── BLE connection state ──────────────────────────────────────────────────
  bool _isScanning       = false;
  bool _isConnecting     = false;
  bool _userDisconnected = false;
  bool _bluetoothWasOff  = false;
  int  _reconnectAttempts = 0;
  int _scanAttempts = 0;
  static const int _maxScanAttempts = 8; // 8 × 15s ≈ 2 min

  BluetoothDevice?                        _connectedDevice;
  BluetoothConnectionState                _connectionState =
      BluetoothConnectionState.disconnected;

  StreamSubscription<List<ScanResult>>?         _scanSub;
  StreamSubscription<List<int>>?                _liveStreamSub;
  StreamSubscription<List<int>>?                _eventChanSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<BluetoothAdapterState>?    _adapterStateSub;

  Timer? _debounceTimer;
  Timer? _reconnectTimer;

  // Separate receive buffers — packets from each characteristic are
  // independent streams with different expected sizes.
  final List<int> _liveBuffer  = [];
  final List<int> _eventBuffer = [];

  // ── Dependencies ──────────────────────────────────────────────────────────
  final SharedPreferences prefs;
  final void Function(String) onStatusUpdate;
  String? _lastStatus;

  // Set by the app after first connection to re-sync mode/scenario on every reconnect.
  void Function()? _onReconnectSync;

  void setReconnectSyncCallback(void Function() cb) {
    _onReconnectSync = cb;
  }

  // ── Constructor ───────────────────────────────────────────────────────────
  BLEConnection({
    required this.prefs,
    required this.onStatusUpdate,
  }) {
    _listenToAdapterState();
    Future.delayed(AppConstants.bleInitialDelay, _performInitialConnection);
  }

  // ── Session event list getters (read-only) ────────────────────────────────

  List<CompressionEvent>     get compressionEvents     => List.unmodifiable(_compressionEvents);
  List<VentilationEvent>     get ventilationEvents     => List.unmodifiable(_ventilationEvents);
  List<PulseCheckEvent>      get pulseCheckEvents      => List.unmodifiable(_pulseCheckEvents);
  List<RescuerVitalSnapshot> get rescuerVitalSnapshots => List.unmodifiable(_rescuerVitalSnapshots);

  /// Mode string for the current/last session ("emergency" / "training" / "training_no_feedback").
  String get sessionMode {
    const modes = ['emergency', 'training', 'training_no_feedback'];
    return modes[_sessionMode.clamp(0, 2)];
  }

  // ── Connection getters ────────────────────────────────────────────────────
  bool get isConnected => _connectionState == BluetoothConnectionState.connected;
  bool get isScanning  => _isScanning;

  // ── Status update ─────────────────────────────────────────────────────────
  void _updateStatus(String status) {
    if (_lastStatus == status) return;
    _lastStatus = status;
    debugPrint('BLE: $status');
    connectionStatusNotifier.value = status;
    onStatusUpdate(status);
  }

  // ── Adapter state listener ────────────────────────────────────────────────
  void _listenToAdapterState() {
    _adapterStateSub?.cancel();
    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) async {
      if (state == BluetoothAdapterState.off) {
        _bluetoothWasOff = true;
        _updateStatus('Bluetooth OFF');
        _cleanupConnection();
      } else if (state == BluetoothAdapterState.on) {
        if (_bluetoothWasOff && !_userDisconnected) {
          _bluetoothWasOff = false;
          _updateStatus('Bluetooth ON — Connecting…');
          await Future.delayed(AppConstants.bleBluetoothOnDelay);
          _performSingleScan();
        } else if (_bluetoothWasOff) {
          _bluetoothWasOff = false;
          _updateStatus('Bluetooth ON — Tap to Connect');
        }
      }
    });
  }

  // ── Initial connection ────────────────────────────────────────────────────
  Future<void> _performInitialConnection() async {
    if (_userDisconnected) return;
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) {
      _performSingleScan();
    } else {
      _updateStatus('Bluetooth OFF');
    }
  }

  Future<bool> requestEnableBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
      return true;
    } catch (_) {
      // User denied or not supported (iOS handles it natively)
      return false;
    }
  }

  // ── Scan ──────────────────────────────────────────────────────────────────
  Future<void> _performSingleScan() async {
    if (isConnected || _isScanning || _isConnecting) return;
    if (!await _isBluetoothOn()) {
      _updateStatus('Bluetooth OFF');
      return;
    }

    _isScanning = true;
    _updateStatus('Scanning for Glove...');

    try {
      _scanSub?.cancel();
      _scanSub = null;

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(AppConstants.zoomAnimationDelay);
      }

      await FlutterBluePlus.startScan(
        timeout: AppConstants.bleScanTimeout,
      );

      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final matchByService = r.advertisementData.serviceUuids
              .any((u) => u.toString().toLowerCase() == _kServiceUuid);
          final matchByName = r.device.platformName == AppConstants.bleDeviceName;
          if (matchByService || matchByName) {
            debugPrint('BLE: found ${r.device.platformName}');
            _stopScanAndConnect(r.device);
            return;
          }
        }
      });

      // flutter_blue_plus 1.x never calls onDone on timeout — handle it manually
      await Future.delayed(AppConstants.bleScanTimeout + const Duration(milliseconds: 500));

      if (_isScanning && !isConnected && !_isConnecting) {
        _isScanning = false;
        _scanSub?.cancel();
        _scanSub = null;

        if (!_userDisconnected) {
          _scanAttempts++;
          _reconnectAttempts = 0;

          if (_scanAttempts >= _maxScanAttempts) {
            // 2 minutes elapsed — stop and wait for manual retry
            _scanAttempts = 0;
            _updateStatus('Glove Not Found — Tap to Retry');
          } else {
            _updateStatus('Glove Not Found — Retrying…');
            _reconnectTimer?.cancel();
            _reconnectTimer = Timer(AppConstants.bleReconnectInterval, () {
              if (!_userDisconnected && !isConnected) _performSingleScan();
            });
          }
        } else {
          _updateStatus('Glove Not Found — Tap to Retry');
        }
      }

    } catch (e) {
      debugPrint('BLE scan error: $e');
      _scanSub?.cancel();
      _scanSub = null;
      _isScanning = false;
      if (!_userDisconnected) {
        _updateStatus('Glove Not Found — Retrying…');
        _reconnectTimer?.cancel();
        _reconnectTimer = Timer(AppConstants.bleReconnectInterval, () {
          if (!_userDisconnected && !isConnected) _performSingleScan();
        });
      } else {
        _updateStatus('Scan Failed — Tap to Retry');
      }
    }
  }

  void _stopScanAndConnect(BluetoothDevice device) {
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    _isScanning = false;
    _connectToDevice(device);
  }

  // ── Connect ───────────────────────────────────────────────────────────────
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting || isConnected) return;
    _isConnecting = true;
    debugPrint('BLE: connecting to ${device.platformName}');

    try {
      if (_connectedDevice != null && _connectedDevice != device) {
        _cleanupConnection();
      }

      _connectedDevice = device;
      _updateStatus('Connecting…');

      await device.connect().timeout(
        AppConstants.bleConnectTimeout,
        onTimeout: () => throw TimeoutException('Connection timed out'),
      );

      _connStateSub?.cancel();
      _connStateSub = device.connectionState.listen((s) {
        _connectionState = s;
        if (s == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // ── MTU negotiation — required by spec v3.0 Section 2.2 ───────────────
      // Must negotiate before service discovery.
      try {
        await device.requestMtu(247);
        debugPrint('BLE: MTU negotiated');
      } catch (e) {
        // MTU negotiation may fail on iOS (handled automatically) — non-fatal.
        debugPrint('BLE: MTU negotiation failed (non-fatal): $e');
      }

      await Future.delayed(AppConstants.blePostConnectDelay);
      await _setupNotifications(device);
    } catch (e) {
      debugPrint('BLE connect error: $e');
      _isConnecting = false;
      if (!_userDisconnected) {
        _updateStatus('Connection Failed — Retrying…');
        _autoReconnect();
      } else {
        _updateStatus('Connection Failed — Tap to Retry');
      }
    }
  }

  // ── Service discovery & dual characteristic subscription ─────────────────
  Future<void> _setupNotifications(BluetoothDevice device) async {
    try {
      final services = await device
          .discoverServices()
          .timeout(AppConstants.bleServiceDiscoveryTimeout);

      final service = services.firstWhere(
            (s) => s.uuid.toString() == _kServiceUuid,
        orElse: () => throw Exception('BLE service $_kServiceUuid not found'),
      );

      // ── Subscribe to LIVE_STREAM ──────────────────────────────────────────
      final liveChar = service.characteristics.firstWhere(
            (c) => c.uuid.toString() == _kLiveStreamUuid,
        orElse: () => throw Exception('LIVE_STREAM characteristic not found'),
      );
      await liveChar.setNotifyValue(true);

      _liveStreamSub?.cancel();
      _liveStreamSub = liveChar.lastValueStream.listen(
            (data) {
          _liveBuffer.addAll(data);
          while (_liveBuffer.length >= kLiveStreamSize) {
            final packet = _liveBuffer.sublist(0, kLiveStreamSize);
            _liveBuffer.removeRange(0, kLiveStreamSize);
            _handleLivePacket(packet);
          }
          if (_liveBuffer.length > AppConstants.bleBufferOverflowThreshold) {
            debugPrint('BLE: LIVE_STREAM buffer overflow — clearing');
            _liveBuffer.clear();
          }
        },
        onError: (Object e) {
          debugPrint('BLE LIVE_STREAM error: $e');
          _handleDisconnection();
        },
      );

      // ── Subscribe to EVENT_CHANNEL ────────────────────────────────────────
      final eventChar = service.characteristics.firstWhere(
            (c) => c.uuid.toString() == _kEventChanUuid,
        orElse: () => throw Exception('EVENT_CHANNEL characteristic not found'),
      );
      await eventChar.setNotifyValue(true);
      // Also enable write-without-response for app→glove commands
      // (write capability is already on the characteristic; no extra setup needed)

      _eventChanSub?.cancel();
      _eventChanSub = eventChar.lastValueStream.listen(
            (data) {
          _eventBuffer.addAll(data);
          while (_eventBuffer.length >= kEventChannelSize) {
            final packet = _eventBuffer.sublist(0, kEventChannelSize);
            _eventBuffer.removeRange(0, kEventChannelSize);
            _handleEventPacket(packet);
          }
          if (_eventBuffer.length > AppConstants.bleBufferOverflowThreshold) {
            debugPrint('BLE: EVENT_CHANNEL buffer overflow — clearing');
            _eventBuffer.clear();
          }
        },
        onError: (Object e) {
          debugPrint('BLE EVENT_CHANNEL error: $e');
          _handleDisconnection();
        },
      );

      // Store reference to event char for writing commands
      _eventCharacteristic = eventChar;

      _isConnecting     = false;
      _userDisconnected = false;
      _reconnectAttempts = 0;
      _scanAttempts      = 0;
      _updateStatus('Connected');
      // Sync wall-clock time so offline sessions have correct timestamps
      unawaited(sendSyncTime());
      // Re-sync mode and scenario so glove state matches app state after reboot/reconnect.
      // onReconnectSync is set by BLEConnection's owner (bleConnectionProvider) after first connect.
      _onReconnectSync?.call();

      debugPrint('BLE: connected and subscribed to both characteristics');
    } catch (e) {
      debugPrint('BLE notification setup failed: $e');
      _isConnecting = false;
      if (!_userDisconnected) {
        _updateStatus('Setup Failed — Retrying…');
        _cleanupConnection();
        _autoReconnect();
      } else {
        _updateStatus('Setup Failed — Tap to Retry');
      }
    }
  }

  // Keep a reference so writeCommand() can use it
  BluetoothCharacteristic? _eventCharacteristic;

  // ── LIVE_STREAM packet handler ────────────────────────────────────────────
  void _handleLivePacket(List<int> packet) {
    final parsed = _processor.parseLiveStream(packet);
    if (parsed == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Battery notifiers for header pill
    if (parsed.batteryPercentage != null) {
      batteryPercentageNotifier.value = parsed.batteryPercentage!;
    }
    if (parsed.isCharging != null) {
      isChargingNotifier.value = parsed.isCharging!;
    }

    // Accumulate compression events when session is active and a new
    // compression has just been confirmed (compressionCount incremented).
    // We detect this by checking compressionCount vs last known value.
    if (_sessionActive && parsed.isContinuousData &&
        parsed.compressionCount > _lastCompressionCount) {
      _lastCompressionCount = parsed.compressionCount;
      // Use depthTrend as the per-compression depth record (5-comp rolling avg peak)
      // since instantaneous depth may be 0 at the moment the count increments.
      final recordDepth = parsed.depthTrend > 0
          ? parsed.depthTrend
          : (parsed.depth > 0 ? parsed.depth : 0.1);
      _compressionEvents.add(CompressionEvent(
        timestampMs:          now - _sessionStartMs,
        depth: recordDepth,
        instantaneousRate:    parsed.instantaneousRate,
        frequency:            parsed.frequency,
        force:                parsed.force,
        recoilAchieved:       parsed.recoilAchieved,
        overForce:            parsed.overForceFlag,
        postureOk:            parsed.postureOk,
        leaningDetected:      parsed.leaningDetected,
        wristAlignmentAngle:  parsed.wristAlignmentAngle,
        wristFlexionAngle:    parsed.wristFlexionAngle,
        compressionAxisDev:   parsed.compressionAxisDeviation,
        effectiveDepth:       parsed.effectiveDepth,
      ));
    }

    // Sample rescuer vitals every 5 s when signal quality is good enough
    if (_sessionActive &&
        parsed.rescuerSignalQuality >= 40 &&
        (now - _lastVitalSnapshotMs) >= _vitalSnapshotIntervalMs) {
      _lastVitalSnapshotMs = now;
      final pauseType = _pulseCheckOpen
          ? 'pulse_check'
          : (parsed.ventilationCount > _lastVentilationCount ? 'ventilation' : 'active');
      _rescuerVitalSnapshots.add(RescuerVitalSnapshot(
        timestampMs:   now - _sessionStartMs,
        heartRate:     parsed.heartRateUser,
        spO2:          parsed.spO2User,
        rmssd:         parsed.rescuerRMSSD,
        rescuerPi:     parsed.rescuerPI,
        temperature:   parsed.rescuerTemperature ?? 0.0,
        fatigueScore:  parsed.rescuerFatigueScore,
        signalQuality: parsed.rescuerSignalQuality,
        pauseType:     pauseType,
      ));
    }

    _lastVentilationCount = parsed.ventilationCount;

    // Broadcast everything to UI screens
    _dataController.add({
      // Source
      'isStartPing':       false,
      'isEndPing':         false,
      'isContinuousData':  parsed.isContinuousData,
      // Core compression
      'depth':             parsed.depth,
      'frequency':         parsed.frequency,
      'instantaneousRate': parsed.instantaneousRate,
      'force':             parsed.force,
      'compressionCount':  parsed.compressionCount,
      'compressionInCycle': parsed.compressionInCycle,
      // Posture
      'wristAlignmentAngle':      parsed.wristAlignmentAngle,
      'wristFlexionAngle':        parsed.wristFlexionAngle,
      'compressionAxisDeviation': parsed.compressionAxisDeviation,
      'depthTrend':               parsed.depthTrend,
      'effectiveDepth':           parsed.effectiveDepth,
      // Flags
      'recoilAchieved':      parsed.recoilAchieved,
      'leaningDetected':     parsed.leaningDetected,
      'overForceFlag':       parsed.overForceFlag,
      'postureOk':           parsed.postureOk,
      'fatigueFlag':         parsed.fatigueFlag,
      'rescuerFatigueScore': parsed.rescuerFatigueScore,
      'imuCalibrated':       parsed.imuCalibrated,
      'wristDropped':        parsed.wristDropped,
      'ventilationCount':    parsed.ventilationCount,
      // Patient vitals
      'heartRatePatient':   parsed.heartRatePatient,
      'spO2Patient':        parsed.spO2Patient,
      'ppgRaw':             parsed.ppgRaw,
      'ppgSignalQuality':   parsed.ppgSignalQuality,
      'perfusionIndex':     parsed.perfusionIndex,
      'patientTemperature': parsed.patientTemperature,
      'pulseCheckActive':   parsed.pulseCheckActive,
      // Rescuer vitals
      'heartRateUser':        parsed.heartRateUser,
      'spO2User':             parsed.spO2User,
      'rescuerSignalQuality': parsed.rescuerSignalQuality,
      'rescuerRMSSD':         parsed.rescuerRMSSD,
      'rescuerTemperature':   parsed.rescuerTemperature,
      'rescuerPI':            parsed.rescuerPI,
      // Session state
      'sessionActive':      parsed.sessionActive,
      'currentMode':        parsed.currentMode,
      'feedbackEnabled':    parsed.feedbackEnabled,
      'batteryPercentage':  parsed.batteryPercentage,
      'isCharging':         parsed.isCharging,
    });
  }

  // Track last compression count to detect new compressions in live stream
  int _lastCompressionCount = 0;
  int _lastVentilationCount = 0;

  // ── EVENT_CHANNEL packet handler ──────────────────────────────────────────
  void _handleEventPacket(List<int> packet) {
    final parsed = _processor.parseEventChannel(packet);
    if (parsed == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // ── SESSION_START ────────────────────────────────────────────────────────
    if (parsed.isStartPing) {
      _compressionEvents.clear();
      _ventilationEvents.clear();
      _pulseCheckEvents.clear();
      _rescuerVitalSnapshots.clear();
      _sessionStartMs         = now;
      _sessionMode            = parsed.currentMode;
      _sessionActive          = true;
      _pulseCheckOpen         = false;
      _lastCompressionCount   = 0;
      _lastVentilationCount   = 0;
      _lastVitalSnapshotMs    = 0;
      debugPrint('BLE: SESSION_START mode=${parsed.currentMode}');
      _dataController.add({
        'isStartPing':  true,
        'isEndPing':    false,
        'currentMode':  parsed.currentMode,
      });
      return;
    }

    // ── SESSION_END ──────────────────────────────────────────────────────────
    if (parsed.isEndPing) {
      _sessionActive = false;
      debugPrint('BLE: SESSION_END totalCompressions=${parsed.totalCompressions}');
      _dataController.add({
        'isStartPing':        false,
        'isEndPing':          true,
        'currentMode':        parsed.currentMode,
        // Glove-side summary counts
        'totalCompressions':  parsed.totalCompressions,
        'correctDepth':       parsed.correctDepth,
        'correctFrequency':   parsed.correctFrequency,
        'correctRecoil':      parsed.correctRecoil,
        'depthRateCombo':     parsed.depthRateCombo,
        'correctPosture':     parsed.correctPosture,
        'leaningCount':       parsed.leaningCount,
        'overForceCount':     parsed.overForceCount,
        'tooDeepCount':       parsed.tooDeepCount,
        'totalVentilations':  parsed.totalVentilations,
        'correctVentilations': parsed.correctVentilations,
        'pulseChecksPrompted': parsed.pulseChecksPrompted,
        'pulseChecksComplied': parsed.pulseChecksComplied,
        'fatigueOnsetIndex':   parsed.fatigueOnsetIndex,
        'peakDepth':           parsed.peakDepth,
        'compressionDepthSD':  parsed.compressionDepthSD,
        'noFlowIntervals':     parsed.noFlowIntervalsEnd,
        'rescuerSwapCount':    parsed.rescuerSwapCountEnd,
        'pulseDetected':       parsed.pulseDetected,
        // Biometrics
        'patientTemperature':  parsed.patientTemperature,
        'rescuerHRLastPause':  parsed.rescuerHRLastPause,
        'rescuerTemperatureEnd': parsed.rescuerTemperatureEnd,
        'rescuerSpO2LastPause': parsed.rescuerSpO2LastPause,
        'ambientTempStart':    parsed.ambientTempStart,
        'ambientTempEnd':      parsed.ambientTempEnd,
      });
      return;
    }

    if (parsed.isScenarioChange) {
      debugPrint('BLE: SCENARIO_CHANGE scenario=${parsed.scenarioFromGlove}');
      _dataController.add({
        'isScenarioChange':      true,
        'scenarioFromGlove':     parsed.scenarioFromGlove,
        'scenarioChangeTrigger': parsed.scenarioChangeTrigger,
      });
      return;
    }

    // ── VENTILATION_WINDOW ───────────────────────────────────────────────────
    if (parsed.isVentilationWindow) {
      final timestampMs = now - _sessionStartMs;
      // Add a new VentilationEvent — duration and compliant will be updated
      // when compressions resume (compliant is determined by the glove;
      // we store what the glove sends via correctVentilations in SESSION_END).
      _ventilationEvents.add(VentilationEvent(
        timestampMs:  timestampMs,
        cycleNumber:  parsed.cycleNumber ?? _ventilationEvents.length + 1,
      ));
      debugPrint('BLE: VENTILATION_WINDOW cycle=${parsed.cycleNumber}');
      _dataController.add({
        'isVentilationWindow': true,
        'cycleNumber':         parsed.cycleNumber,
        'ventilationsExpected': parsed.ventilationsExpected,
      });
      return;
    }

    // ── PULSE_CHECK_START ────────────────────────────────────────────────────
    if (parsed.isPulseCheckStart) {
      _pulseCheckOpen = true;
      debugPrint('BLE: PULSE_CHECK_START interval=${parsed.intervalNumber}');
      _dataController.add({
        'isPulseCheckStart': true,
        'intervalNumber':    parsed.intervalNumber,
      });
      return;
    }

    // ── PULSE_CHECK_RESULT ───────────────────────────────────────────────────
    if (parsed.isPulseCheckResult) {
      _pulseCheckOpen = false;
      final timestampMs = now - _sessionStartMs;
      _pulseCheckEvents.add(PulseCheckEvent(
        timestampMs:    timestampMs,
        intervalNumber: parsed.intervalNumber ?? _pulseCheckEvents.length + 1,
        classification: parsed.pulseClassification ?? 0,
        detectedBpm:    parsed.detectedBPM ?? 0.0,
        confidence:     parsed.confidencePct ?? 0,
        detectorACount: parsed.detectorACount ?? 0,
        detectorBCount: parsed.detectorBCount ?? 0,
      ));
      debugPrint(
        'BLE: PULSE_CHECK_RESULT classification=${parsed.pulseClassification} '
            'bpm=${parsed.detectedBPM}',
      );
      _dataController.add({
        'isPulseCheckResult':  true,
        'pulseClassification': parsed.pulseClassification,
        'detectedBPM':         parsed.detectedBPM,
        'confidencePct':       parsed.confidencePct,
        'detectorACount':      parsed.detectorACount,
        'detectorBCount':      parsed.detectorBCount,
      });
      return;
    }

    // ── MODE_CHANGE ──────────────────────────────────────────────────────────
    if (parsed.isModeChange) {
      _sessionMode = parsed.currentMode;
      debugPrint('BLE: MODE_CHANGE newMode=${parsed.currentMode}');
      _dataController.add({
        'isModeChange':       true,
        'currentMode':        parsed.currentMode,
        'modeChangeTrigger':  parsed.modeChangeTrigger,
      });
      return;
    }

    // ── TWO_MIN_ALERT ────────────────────────────────────────────────────────
    if (parsed.isTwoMinAlert) {
      debugPrint('BLE: TWO_MIN_ALERT #${parsed.twoMinAlertNumber}');
      _dataController.add({
        'isTwoMinAlert':    true,
        'twoMinAlertNumber': parsed.twoMinAlertNumber,
      });
      return;
    }

    // ── FATIGUE_ALERT ────────────────────────────────────────────────────────
    if (parsed.isFatigueAlert) {
      debugPrint('BLE: FATIGUE_ALERT score=${parsed.fatigueAlertScore}');
      _dataController.add({
        'isFatigueAlert':   true,
        'fatigueAlertScore': parsed.fatigueAlertScore,
      });
      return;
    }

    // ── PENDING_LOCAL_DATA ───────────────────────────────────────────────────
    if (parsed.isPendingLocalData) {
      debugPrint('BLE: PENDING_LOCAL_DATA count=${parsed.pendingSessionCount}');
      _dataController.add({
        'isPendingLocalData':  true,
        'pendingSessionCount': parsed.pendingSessionCount,
      });
      return;
    }

    // ── LOCAL_SESSION_CHUNK ──────────────────────────────────────────────────
    if (parsed.isLocalSessionChunk) {
      _dataController.add({
        'isLocalSessionChunk': true,
        'localSessionIndex':   parsed.localSessionIndex,
        'localChunkIndex':     parsed.localChunkIndex,
        'localTotalChunks':    parsed.localTotalChunks,
        'localChunkData':      parsed.localChunkData,
      });
      return;
    }

    // ── SELFTEST_RESULT ──────────────────────────────────────────────────────
    if (parsed.isSelftestResult) {
      debugPrint(
        'BLE: SELFTEST_RESULT pass=0x${parsed.selftestPassMask?.toRadixString(16)} '
            'warn=0x${parsed.selftestWarnMask?.toRadixString(16)} '
            'critical=0x${parsed.selftestCriticalMask?.toRadixString(16)}',
      );
      _dataController.add({
        'isSelftestResult':    true,
        'selftestPassMask':    parsed.selftestPassMask,
        'selftestWarnMask':    parsed.selftestWarnMask,
        'selftestCriticalMask': parsed.selftestCriticalMask,
        'selftestBatteryPct':  parsed.selftestBatteryPct,
      });
      return;
    }
  }

  /// Called when SELFTEST_RESULT arrives AND was requested by the user.
  void Function(Map<String, dynamic>)? onSelftestResult;

  // ── App → Glove write commands ────────────────────────────────────────────
  // All commands are 80-byte frames. Unused bytes are 0x00.

  Future<bool> _writeCommand(List<int> payload) async {
    final char = _eventCharacteristic;
    if (char == null || !isConnected) {
      debugPrint('BLE: writeCommand — not connected');
      return false;
    }
    // Pad to kEventChannelSize
    final frame = List<int>.filled(kEventChannelSize, 0);
    for (int i = 0; i < payload.length && i < kEventChannelSize; i++) {
      frame[i] = payload[i];
    }
    try {
      await char.write(frame, withoutResponse: true);
      return true;
    } catch (e) {
      debugPrint('BLE: writeCommand failed — $e');
      return false;
    }
  }

  /// 0xF1 — Set glove mode. 0=Emergency 1=Training 2=No-Feedback.
  Future<bool> sendModeSet(int mode) =>
      _writeCommand([kCmdModeSet, mode.clamp(0, 2)]);

  /// 0xF2 — Toggle haptic/audio/LED feedback. true=on false=off.
  Future<bool> sendFeedbackSet({required bool enabled}) =>
      _writeCommand([kCmdFeedbackSet, enabled ? 1 : 0]);

  /// 0xF3 — Trigger session start (equivalent to physical button press).
  Future<bool> sendStart() =>
      _writeCommand([kCmdStart]);

  /// 0xF4 — Trigger session end.
  Future<bool> sendStop() =>
      _writeCommand([kCmdStop]);

  /// 0xF5 — Request a locally stored offline session by index.
  Future<bool> sendRequestSession(int index) =>
      _writeCommand([kCmdRequestSession, index]);

  /// 0xF6 — Confirm a session was received. Glove deletes it from flash.
  Future<bool> sendConfirmReceived(int index) =>
      _writeCommand([kCmdConfirmReceived, index]);

  /// 0xF7 — Trigger brightness sweep + force baseline recalibration.
  Future<bool> sendCalibrate() =>
      _writeCommand([kCmdCalibrate]);

  /// 0xF8 — Override depth target (mm). Scenario-specific.
  Future<bool> sendSetTargetDepth({required int minMm, required int maxMm}) =>
      _writeCommand([kCmdSetTargetDepth, minMm, maxMm]);

  /// 0xF9 — Override rate target (BPM). Scenario-specific.
  Future<bool> sendSetTargetRate({required int minBpm, required int maxBpm}) =>
      _writeCommand([kCmdSetTargetRate, minBpm, maxBpm]);

  /// 0xFA — Sync wall-clock time so offline sessions have correct timestamps.
  Future<bool> sendSyncTime() {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Unix seconds
    return _writeCommand([
      kCmdSyncTime,
      (ts >> 24) & 0xFF,
      (ts >> 16) & 0xFF,
      (ts >> 8)  & 0xFF,
      ts        & 0xFF,
    ]);
  }

  /// 0xFB — Set ventilation cycle ratio.
  Future<bool> sendSetVentilation({
    required int compressionsPerCycle,
    required int ventilationsPerPause,
  }) =>
      _writeCommand([kCmdSetVentilation, compressionsPerCycle, ventilationsPerPause]);

  /// 0xFC — Trigger on-demand self-test.
  Future<bool> sendRunSelftest() =>
      _writeCommand([kCmdRunSelftest]);

  /// 0xFD — Set scenario on glove. 0=adult 1=pediatric.
  /// Glove confirms with SCENARIO_CHANGE (0x0C) as acknowledgement.
  Future<bool> sendSetScenario(int scenario) =>
      _writeCommand([kCmdSetScenario, scenario.clamp(0, 1)]);

  // ── Disconnection handling ────────────────────────────────────────────────
  void _handleDisconnection() {
    if (_connectionState == BluetoothConnectionState.connected) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      AppConstants.mapAnimationDelay,
      _processDisconnection,
    );
  }

  void _processDisconnection() {
    if (_isConnecting) _isConnecting = false;
    if (_userDisconnected) {
      _updateStatus('Disconnected');
    } else {
      _updateStatus('Disconnected — Reconnecting…');
      _autoReconnect();
    }
  }

  Future<void> _autoReconnect() async {
    if (_userDisconnected) return;
    _reconnectTimer?.cancel();

    if (_reconnectAttempts >= AppConstants.bleMaxReconnectAttempts) {
      debugPrint('BLE: max reconnect attempts reached');
      _updateStatus('Connection Lost — Tap to Retry');
      _reconnectAttempts = 0;
      return;
    }

    _reconnectAttempts++;
    debugPrint(
      'BLE: auto-reconnect $_reconnectAttempts'
          '/${AppConstants.bleMaxReconnectAttempts}',
    );

    final delaySec = math.min(
      AppConstants.bleReconnectInterval.inSeconds *
          math.pow(2, _reconnectAttempts - 1).toInt(),
      AppConstants.bleReconnectTimeout.inSeconds,
    );

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_userDisconnected) _performSingleScan();
    });
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────
  void _cleanupConnection() {
    _liveStreamSub?.cancel();
    _eventChanSub?.cancel();
    _connStateSub?.cancel();
    _debounceTimer?.cancel();
    _liveBuffer.clear();
    _eventBuffer.clear();
    _eventCharacteristic = null;
    _connectTimestampMs = 0;

    _connectedDevice?.disconnect().catchError(
          (Object e) => debugPrint('BLE disconnect error: $e'),
    );

    _connectedDevice = null;
    _connectionState = BluetoothConnectionState.disconnected;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Called when the user taps the retry/reconnect button.
  Future<void> manualRetry() async {
    if (isConnected) return;
    debugPrint('BLE: manual retry');
    _reconnectAttempts = 0;
    _scanAttempts      = 0;
    _userDisconnected  = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    if (_isScanning) {
      FlutterBluePlus.stopScan();
      _scanSub?.cancel();
      _isScanning = false;
    }

    if (_isConnecting) {
      _cleanupConnection();
      _isConnecting = false;
    }

    if (!await _isBluetoothOn()) {
      _updateStatus('Bluetooth OFF');
      return;
    }

    _performSingleScan();
  }

  /// Manually disconnect — suppresses all auto-reconnect logic.
  Future<void> disconnectDevice() async {
    debugPrint('BLE: manual disconnect');
    _userDisconnected = true;
    _cleanupConnection();
    _updateStatus('Disconnected');
  }

  /// Request Bluetooth to turn on.
  Future<bool> enableBluetooth({bool prompt = false}) async {
    if (await _isBluetoothOn()) return true;
    if (prompt) {
      await FlutterBluePlus.turnOn();
      await Future.delayed(const Duration(seconds: 2));
      return _isBluetoothOn();
    }
    return false;
  }

  /// Adapter state stream — for widgets that need to react to BT on/off.
  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  void dispose() {
    _debounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _scanSub?.cancel();
    _liveStreamSub?.cancel();
    _eventChanSub?.cancel();
    _adapterStateSub?.cancel();
    _connStateSub?.cancel();
    _cleanupConnection();
    _dataController.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Future<bool> _isBluetoothOn() async =>
      await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
}