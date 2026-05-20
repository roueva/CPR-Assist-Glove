import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpr_assist/core/core.dart';

import '../../features/training/services/compression_event.dart';
import '../../features/training/services/session_detail.dart';
import '../../features/training/services/ventilation_event.dart';
import '../../features/training/services/pulse_check_event.dart';
import '../../features/training/services/rescuer_vital_snapshot.dart';
import 'ble_data_processor.dart';
import 'offline_session_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEConnection  —  BLE Spec v3.0
//
// Manages the full lifecycle of the CPR Assist Glove BLE connection:
//   scan → connect → MTU negotiation → discover services →
//   subscribe LIVE_STREAM + EVENT_CHANNEL → auto-reconnect on drop.
//
// Two separate characteristic subscriptions per spec v3.0 Section 2:
//   LIVE_STREAM   19b10001-...  108 bytes, 25 Hz notify
//   EVENT_CHANNEL 19b10002-...  96  bytes, on-event notify + write
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

  final List<double> _ppgBuffer = [];   // accumulates ppgRaw during pulse check window
  double _bestPatientSpO2 = 0.0;        // best spO2Patient reading during pulse check

  // ── Rescuer vital sampling state ──────────────────────────────────────────
  int _lastVitalSnapshotMs = 0;
  static const int _vitalSnapshotIntervalMs = 5000; // sample every 5 s

  // ── Alert timestamps (captured at receive time, session-relative ms) ──────
  final List<int> _twoMinAlertTimestampsMs = [];
  int? _fatigueAlertTimestampMs;       // null if not fired
  int? _fatigueAlertScore;             // null if not fired

  // ── Offline session chunk reassembly ──────────────────────────────────────
  /// sessionIndex → list of received chunks (each 92 bytes). Index is the
  /// chunkIndex from the LOCAL_SESSION_CHUNK packet.
  final Map<int, Map<int, List<int>>> _chunkBuffers = {};
  /// sessionIndex → totalChunks (from any received chunk for that session)
  final Map<int, int> _chunkTotals = {};
  /// Callback when an offline session is fully reassembled and parsed.
  void Function(SessionDetail detail, int sessionIndex)? onOfflineSessionParsed;

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

  List<int> get twoMinAlertTimestampsMs => List.unmodifiable(_twoMinAlertTimestampsMs);
  int? get fatigueAlertTimestampMs => _fatigueAlertTimestampMs;
  int? get fatigueAlertScore => _fatigueAlertScore;

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
    if (state != BluetoothAdapterState.on) {
      _updateStatus('Bluetooth OFF');
      return;
    }
    // BT is already on → permissions are already granted (system wouldn't
    // have turned BT on without them). Record this so future launches
    // also auto-scan, then scan immediately.
    await prefs.setBool('ble_permissions_granted', true);
    _performSingleScan();
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
      _liveStreamSub = liveChar.onValueReceived.listen(
            (data) {
          if (data.length == kLiveStreamSize) {
            _handleLivePacket(data);
          } else {
            debugPrint('BLE: LIVE_STREAM unexpected length ${data.length}');
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
      _eventChanSub = eventChar.onValueReceived.listen(
            (data) {
          if (data.length == kEventChannelSize) {
            _handleEventPacket(data);
          } else {
            debugPrint('BLE: EVENT_CHANNEL unexpected length ${data.length}');
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

    // Track peak depth between compression count increments.
    // We accumulate the maximum depth seen across all 25 Hz packets so that
    // when compressionCount increments we have the real peak, not whatever
    // the instantaneous depth happens to be at that exact packet.
    if (_sessionActive && parsed.isContinuousData) {
      if (parsed.depth > _pendingPeakDepth) {
        _pendingPeakDepth = parsed.depth;
        debugPrint('[DBG-APP] liveDepth=${parsed.depth.toStringAsFixed(2)} '
            'pendingPeak=${_pendingPeakDepth.toStringAsFixed(2)} '
            'cnt=${parsed.compressionCount} peakTs=${parsed.peakTimestampMs}');
      }
      if (parsed.force > _pendingPeakForce) {
        _pendingPeakForce = parsed.force;
      }
    }

    // Accumulate compression events when a new compression is confirmed.
    if (_sessionActive && parsed.isContinuousData &&
        parsed.compressionCount > _lastCompressionCount) {
      _lastCompressionCount = parsed.compressionCount;
      final recordDepth = _pendingPeakDepth > 0
          ? _pendingPeakDepth
          : (parsed.depthTrend > 0
          ? parsed.depthTrend
          : (parsed.depth > 0 ? parsed.depth : 0.0));
      final recordPeakForce = _pendingPeakForce > 0
          ? _pendingPeakForce
          : parsed.force;
      _pendingPeakDepth = 0.0; // reset for next compression
      _pendingPeakForce = 0.0;
      final compressionTimestampMs = parsed.peakTimestampMs > 0
          ? parsed.peakTimestampMs
          : now - _sessionStartMs;

// Downstroke time = current peakTs − previous valleyTs (start of downstroke)
      // First compression has no previous valley → 0
      final int downstrokeMs = (_prevValleyTimestampMs > 0 &&
          parsed.peakTimestampMs > _prevValleyTimestampMs)
          ? parsed.peakTimestampMs - _prevValleyTimestampMs
          : 0;

      _compressionEvents.add(CompressionEvent(
        timestampMs:         compressionTimestampMs,
        depth:               recordDepth,
        valleyDepth:         parsed.valleyDepth,
        instantaneousRate:   parsed.instantaneousRate,
        frequency:           parsed.frequency,
        force:               parsed.force,
        peakForce:           recordPeakForce,
        recoilAchieved:      parsed.recoilAchieved,
        overForce:           parsed.overForceFlag,
        postureOk:           parsed.postureOk,
        leaningDetected:     parsed.leaningDetected,
        wristAlignmentAngle: parsed.wristAlignmentAngle,
        wristFlexionAngle:   parsed.wristFlexionAngle,
        compressionAxisDev:  parsed.compressionAxisDeviation,
        effectiveDepth:      recordDepth * math.cos(
          parsed.compressionAxisDeviation * math.pi / 180.0,
        ),
        downstrokeTimeMs:    downstrokeMs,
        peakTimestampMs:     parsed.peakTimestampMs,
        valleyTimestampMs:   parsed.valleyTimestampMs,
      ));

      // Remember this valley for next compression's downstroke calc
      _prevValleyTimestampMs = parsed.valleyTimestampMs;
    }

    // Sample rescuer vitals every 5 s regardless of signal quality.
    // signalQuality is recorded in the row so the display layer can choose
    // to grey-out or hide entries with poor quality. This keeps the post-session
    // vitals graph continuous and lets us see when the sensor lost contact.
    if (_sessionActive &&
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
        humidity:      parsed.rescuerHumidity,
        pauseType:     pauseType,
      ));
    }

    _lastVentilationCount = parsed.ventilationCount;

    // Accumulate PPG samples during pulse check window for post-session replay
    if (_sessionActive && _pulseCheckOpen && parsed.ppgRaw > 0) {
      _ppgBuffer.add(parsed.ppgRaw);
      if (_ppgBuffer.length > 200) _ppgBuffer.removeAt(0);
    }
    if (_sessionActive && _pulseCheckOpen &&
        parsed.spO2Patient > 0 && parsed.spO2Patient > _bestPatientSpO2) {
      _bestPatientSpO2 = parsed.spO2Patient;
    }

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
      'inVentilationWindow': parsed.inVentilationWindow,
      // Rescuer vitals
      'heartRateUser':        parsed.heartRateUser,
      'spO2User':             parsed.spO2User,
      'rescuerSignalQuality': parsed.rescuerSignalQuality,
      'rescuerRMSSD':         parsed.rescuerRMSSD,
      'rescuerTemperature':   parsed.rescuerTemperature,
      'rescuerPI':            parsed.rescuerPI,
      'rescuerHumidity':      parsed.rescuerHumidity,
      // Session state
      'sessionActive':      parsed.sessionActive,
      'currentMode':        parsed.currentMode,
      'feedbackEnabled':    parsed.feedbackEnabled,
      'batteryPercentage':  parsed.batteryPercentage,
      'isCharging':         parsed.isCharging,
      'peakTimestampMs':   parsed.peakTimestampMs,
      'valleyTimestampMs': parsed.valleyTimestampMs,
      'lastPeakDepthCm':   parsed.lastPeakDepthCm,
    });
  }

  // Track last compression count to detect new compressions in live stream
  int _lastCompressionCount = 0;
  int _lastVentilationCount = 0;
  double _pendingPeakDepth = 0.0;
  // Track per-compression peak force and downstroke timing
  double _pendingPeakForce       = 0.0;  // max force seen since last compression
  int _prevValleyTimestampMs = 0;    // valley_ts of current compression (for downstroke calc)

  // ── EVENT_CHANNEL packet handler ──────────────────────────────────────────
  void _handleEventPacket(List<int> packet) {
    if (packet.isEmpty) return;
    // Ignore echo of outgoing app→glove commands (0xF0–0xFF)
    if (packet[0] >= 0xF0) return;
    final parsed = _processor.parseEventChannel(packet);
    if (parsed == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // ── SESSION_START ────────────────────────────────────────────────────────
    if (parsed.isStartPing) {
      _compressionEvents.clear();
      _ventilationEvents.clear();
      _pulseCheckEvents.clear();
      _twoMinAlertTimestampsMs.clear();
      _prevValleyTimestampMs = 0;
      _fatigueAlertTimestampMs = null;
      _fatigueAlertScore = null;
      _rescuerVitalSnapshots.clear();
      _sessionStartMs         = now;
      _sessionMode            = parsed.currentMode;
      _sessionActive          = true;
      _pulseCheckOpen         = false;
      _lastCompressionCount   = 0;
      _ppgBuffer.clear();
      _bestPatientSpO2 = 0.0;
      _pendingPeakDepth       = 0.0;
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
        'timeToFirstCompressionMs': parsed.timeToFirstCompressionMs,
        'pulseDetected':       parsed.pulseDetected,
        // Biometrics
        'patientTemperature':  parsed.patientTemperature,
        'rescuerHRLastPause':     parsed.rescuerHRLastPause,
        'rescuerSpO2LastPause':   parsed.rescuerSpO2LastPause,
        'rescuerWristTempStart':  parsed.rescuerWristTempStart,
        'rescuerWristTempEnd':    parsed.rescuerWristTempEnd,
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
        ppgSamples:     List<double>.from(_ppgBuffer),
        patientSpO2:    _bestPatientSpO2,
      ));
      _ppgBuffer.clear();
      _bestPatientSpO2 = 0.0;
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
      final timestampMs = now - _sessionStartMs;
      if (_sessionActive) _twoMinAlertTimestampsMs.add(timestampMs);
      debugPrint('BLE: TWO_MIN_ALERT #${parsed.twoMinAlertNumber} @ ${timestampMs}ms');
      _dataController.add({
        'isTwoMinAlert':    true,
        'twoMinAlertNumber': parsed.twoMinAlertNumber,
        'twoMinAlertTimestampMs': timestampMs,
      });
      return;
    }

    // ── FATIGUE_ALERT ────────────────────────────────────────────────────────
    if (parsed.isFatigueAlert) {
      final timestampMs = now - _sessionStartMs;
      if (_sessionActive && _fatigueAlertTimestampMs == null) {
        _fatigueAlertTimestampMs = timestampMs;
        _fatigueAlertScore = parsed.fatigueAlertScore;
      }
      debugPrint('BLE: FATIGUE_ALERT score=${parsed.fatigueAlertScore} @ ${timestampMs}ms');
      _dataController.add({
        'isFatigueAlert':   true,
        'fatigueAlertScore': parsed.fatigueAlertScore,
        'fatigueAlertTimestampMs': timestampMs,
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
// ── LOCAL_SESSION_CHUNK ──────────────────────────────────────────────────
    if (parsed.isLocalSessionChunk) {
      final sessionIdx  = parsed.localSessionIndex ?? 0;
      final chunkIdx    = parsed.localChunkIndex ?? 0;
      final totalChunks = parsed.localTotalChunks ?? 0;
      final chunkData   = parsed.localChunkData ?? const <int>[];

      _chunkTotals[sessionIdx] = totalChunks;
      _chunkBuffers
          .putIfAbsent(sessionIdx, () => <int, List<int>>{})[chunkIdx] = chunkData;

      _dataController.add({
        'isLocalSessionChunk': true,
        'localSessionIndex':   sessionIdx,
        'localChunkIndex':     chunkIdx,
        'localTotalChunks':    totalChunks,
      });

      // Once we've received all chunks for this session, reassemble + parse
      final buffers = _chunkBuffers[sessionIdx]!;
      if (buffers.length >= totalChunks && totalChunks > 0) {
        final fullBytes = <int>[];
        for (int i = 0; i < totalChunks; i++) {
          final c = buffers[i];
          if (c == null) {
            debugPrint('BLE: chunk $i missing for session $sessionIdx — aborting reassembly');
            return;
          }
          fullBytes.addAll(c);
        }
        _chunkBuffers.remove(sessionIdx);
        _chunkTotals.remove(sessionIdx);

        try {
          final detail = OfflineSessionParser.parse(fullBytes);
          debugPrint('BLE: offline session $sessionIdx parsed — '
              '${detail.compressions.length} comps, ${detail.ventilations.length} vents');
          onOfflineSessionParsed?.call(detail, sessionIdx);
        } catch (e) {
          debugPrint('BLE: offline session parse failed — $e');
        }
      }
      return;
    }

    // ── SELFTEST_RESULT ──────────────────────────────────────────────────────
    if (parsed.isSelftestResult) {
      debugPrint(
        'BLE: SELFTEST_RESULT pass=0x${parsed.selftestPassMask?.toRadixString(16)} '
            'warn=0x${parsed.selftestWarnMask?.toRadixString(16)} '
            'critical=0x${parsed.selftestCriticalMask?.toRadixString(16)}',
      );
      final result = {
        'isSelftestResult':     true,
        'selftestPassMask':     parsed.selftestPassMask,
        'selftestWarnMask':     parsed.selftestWarnMask,
        'selftestCriticalMask': parsed.selftestCriticalMask,
        'selftestBatteryPct':   parsed.selftestBatteryPct,
      };

      _dataController.add(result);
      onSelftestResult?.call(result);

      return;
    }
  }

  /// Called when SELFTEST_RESULT arrives AND was requested by the user.
  void Function(Map<String, dynamic>)? onSelftestResult;

  // ── App → Glove write commands ────────────────────────────────────────────
  // All commands are 96-byte frames. Unused bytes are 0x00.

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

  // /// 0xF3 — Trigger session start (equivalent to physical button press).
  // Future<bool> sendStart() =>
  //     _writeCommand([kCmdStart]);
  //
  // /// 0xF4 — Trigger session end.
  // Future<bool> sendStop() =>
  //     _writeCommand([kCmdStop]);

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
    final ts = DateTime.now().millisecondsSinceEpoch; // ms since epoch, NOT seconds
    return _writeCommand([
      kCmdSyncTime,
      ts         & 0xFF,   // little-endian LSB first
      (ts >> 8)  & 0xFF,
      (ts >> 16) & 0xFF,
      (ts >> 24) & 0xFF,
      (ts >> 32) & 0xFF,
      (ts >> 40) & 0xFF,
      (ts >> 48) & 0xFF,
      (ts >> 56) & 0xFF,
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
      AppConstants.bleDisconnectDebounce,
      _processDisconnection,
    );
  }

  void _processDisconnection() {
    if (_isConnecting) _isConnecting = false;
    if (_userDisconnected) {
      _sessionActive = false;
      _pulseCheckOpen = false;
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
    _eventCharacteristic = null;

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

  /// Call once after first successful BLE connection to enable silent
  /// startup scanning on future app launches.
  void markPermissionsGranted() {
    prefs.setBool('ble_permissions_granted', true);
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