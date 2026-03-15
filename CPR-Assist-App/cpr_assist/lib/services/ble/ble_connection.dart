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
// BLEConnection  —  BLE Spec v2.0
//
// Subscribes to both LIVE_STREAM (88 bytes, 10 Hz) and EVENT_CHANNEL
// (80 bytes, on-event). Each characteristic has its own receive buffer
// and subscription. Parsed packets from both are broadcast on [dataStream].
//
// Session event lists (cleared on SESSION_START, read on SESSION_END):
//   compressionEvents      — per-compression from LIVE_STREAM
//   ventilationEvents      — per 30:2 cycle from EVENT_CHANNEL 0x03
//   pulseCheckEvents       — per check from EVENT_CHANNEL 0x05
//   rescuerVitalSnapshots  — quality-gated rescuer vitals from LIVE_STREAM
// ─────────────────────────────────────────────────────────────────────────────

class BLEConnection {
  // ── Processor ─────────────────────────────────────────────────────────────

  final _processor = const BLEDataProcessor();
  final _dataController = StreamController<Map<String, dynamic>>.broadcast();

  // ── Session event accumulators ────────────────────────────────────────────

  final List<CompressionEvent>     _compressionEvents     = [];
  final List<VentilationEvent>     _ventilationEvents     = [];
  final List<PulseCheckEvent>      _pulseCheckEvents      = [];
  final List<RescuerVitalSnapshot> _rescuerVitalSnapshots = [];

  int _sessionStartMs = 0;

  // Pulse check context
  int _currentPulseIntervalNumber = 0;
  int _currentPulseStartMs        = 0;
  int _lastPerfusionIndex         = 0;

  // Ventilation window context
  int _currentCycleNumber  = 0;
  int _ventilationWindowMs = 0;

  // ── Public notifiers ──────────────────────────────────────────────────────

  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  final ValueNotifier<String> connectionStatusNotifier =
  ValueNotifier('Disconnected');
  final ValueNotifier<int>  batteryPercentageNotifier = ValueNotifier(0);
  final ValueNotifier<bool> isChargingNotifier        = ValueNotifier(false);

  // ── Internal state ────────────────────────────────────────────────────────

  bool _isScanning       = false;
  bool _isConnecting     = false;
  bool _userDisconnected = false;
  bool _bluetoothWasOff  = false;
  int  _reconnectAttempts = 0;

  BluetoothDevice?             _connectedDevice;
  BluetoothConnectionState     _connectionState =
      BluetoothConnectionState.disconnected;

  StreamSubscription<List<ScanResult>>?         _scanSub;
  StreamSubscription<List<int>>?                _liveStreamSub;
  StreamSubscription<List<int>>?                _eventChannelSub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<BluetoothAdapterState>?    _adapterStateSub;

  Timer? _debounceTimer;
  Timer? _reconnectTimer;

  // Separate receive buffers for each characteristic
  final List<int> _liveStreamBuffer   = [];
  final List<int> _eventChannelBuffer = [];

  // ── Dependencies ──────────────────────────────────────────────────────────

  final SharedPreferences     prefs;
  final void Function(String) onStatusUpdate;
  String? _lastStatus;

  // ── Constructor ───────────────────────────────────────────────────────────

  BLEConnection({
    required this.prefs,
    required this.onStatusUpdate,
  }) {
    _listenToAdapterState();
    Future.delayed(AppConstants.bleInitialDelay, _performInitialConnection);
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isConnected =>
      _connectionState == BluetoothConnectionState.connected;
  bool get isScanning => _isScanning;

  // ── Status ────────────────────────────────────────────────────────────────

  void _updateStatus(String status) {
    if (_lastStatus == status) return;
    _lastStatus = status;
    debugPrint('BLE: $status');
    connectionStatusNotifier.value = status;
    onStatusUpdate(status);
  }

  // ── Adapter state ─────────────────────────────────────────────────────────

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

  // ── Scan ──────────────────────────────────────────────────────────────────

  Future<void> _performSingleScan() async {
    if (isConnected || _isScanning || _isConnecting) return;
    if (!await _isBluetoothOn()) {
      _updateStatus('Bluetooth OFF');
      return;
    }

    _isScanning = true;
    _updateStatus('Scanning for Arduino...');

    try {
      _scanSub?.cancel();
      _scanSub = null;

      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(AppConstants.zoomAnimationDelay);
      }

      await FlutterBluePlus.startScan(timeout: AppConstants.bleScanTimeout);

      _scanSub = FlutterBluePlus.scanResults.listen(
            (results) {
          for (final r in results) {
            if (r.device.platformName.contains(AppConstants.bleDeviceName)) {
              debugPrint('BLE: found ${r.device.platformName}');
              _stopScanAndConnect(r.device);
              return;
            }
          }
        },
        onDone: () {
          if (_isScanning) {
            _isScanning = false;
            _updateStatus('Glove Not Found — Tap to Retry');
          }
        },
      );
    } catch (e) {
      debugPrint('BLE scan error: $e');
      _isScanning = false;
      _updateStatus('Scan Failed — Tap to Retry');
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

      _connStateSub?.cancel();
      _connStateSub = device.connectionState.listen((s) {
        _connectionState = s;
        if (s == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      await device.connect().timeout(
        AppConstants.bleConnectTimeout,
        onTimeout: () => throw TimeoutException('Connection timed out'),
      );

      await Future.delayed(AppConstants.blePostConnectDelay);
      await _setupNotifications(device);
    } catch (e) {
      debugPrint('BLE connect error: $e');
      _isConnecting = false;
      _updateStatus('Connection Failed — Tap to Retry');
    }
  }

  // ── Dual-characteristic subscription (v2.0) ───────────────────────────────

  Future<void> _setupNotifications(BluetoothDevice device) async {
    try {
      final services = await device
          .discoverServices()
          .timeout(AppConstants.bleServiceDiscoveryTimeout);

      final service = services.firstWhere(
            (s) => s.uuid.toString().toLowerCase() ==
            AppConstants.bleServiceUuid.toLowerCase(),
        orElse: () => throw Exception('BLE service not found'),
      );

      BluetoothCharacteristic? liveStreamChar;
      BluetoothCharacteristic? eventChannelChar;

      for (final c in service.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        if (uuid == AppConstants.bleLiveStreamUuid.toLowerCase()) {
          liveStreamChar = c;
        } else if (uuid == AppConstants.bleEventChannelUuid.toLowerCase()) {
          eventChannelChar = c;
        }
      }

      if (liveStreamChar == null) {
        throw Exception('LIVE_STREAM characteristic not found');
      }
      if (eventChannelChar == null) {
        throw Exception('EVENT_CHANNEL characteristic not found');
      }

      // ── LIVE_STREAM subscription ────────────────────────────────────────
      await liveStreamChar.setNotifyValue(true);
      _liveStreamSub?.cancel();
      _liveStreamSub = liveStreamChar.lastValueStream.listen(
            (data) => _handleIncoming(
          data,
          _liveStreamBuffer,
          AppConstants.bleLiveStreamPacketSize,
          isLiveStream: true,
        ),
        onError: (Object e) {
          debugPrint('BLE LIVE_STREAM error: $e');
          _handleDisconnection();
        },
      );

      // ── EVENT_CHANNEL subscription ──────────────────────────────────────
      await eventChannelChar.setNotifyValue(true);
      _eventChannelSub?.cancel();
      _eventChannelSub = eventChannelChar.lastValueStream.listen(
            (data) => _handleIncoming(
          data,
          _eventChannelBuffer,
          AppConstants.bleEventChannelPacketSize,
          isLiveStream: false,
        ),
        onError: (Object e) {
          debugPrint('BLE EVENT_CHANNEL error: $e');
        },
      );

      _isConnecting     = false;
      _userDisconnected = false;
      _reconnectAttempts = 0;
      _updateStatus('Connected');
      debugPrint('BLE: connected — LIVE_STREAM + EVENT_CHANNEL active');
    } catch (e) {
      debugPrint('BLE notification setup failed: $e');
      _isConnecting = false;
      _updateStatus('Setup Failed — Tap to Retry');
    }
  }

  // ── Incoming data handler — buffers and slices into fixed-size packets ────

  void _handleIncoming(
      List<int> data,
      List<int> buffer,
      int packetSize, {
        required bool isLiveStream,
      }) {
    buffer.addAll(data);

    while (buffer.length >= packetSize) {
      final packet = buffer.sublist(0, packetSize);
      buffer.removeRange(0, packetSize);
      _handlePacket(packet, isLiveStream: isLiveStream);
    }

    if (buffer.length > AppConstants.bleBufferOverflowThreshold) {
      debugPrint(
        'BLE: buffer overflow (${isLiveStream ? "LIVE_STREAM" : "EVENT_CHANNEL"}) — clearing',
      );
      buffer.clear();
    }
  }

  // ── Packet handling ───────────────────────────────────────────────────────

  void _handlePacket(List<int> packet, {required bool isLiveStream}) {
    final parsed = isLiveStream
        ? _processor.parseLiveStream(packet)
        : _processor.parseEventChannel(packet);
    if (parsed == null) return;

    // Battery notifiers (LIVE_STREAM only)
    if (parsed.batteryPercentage != null) {
      batteryPercentageNotifier.value = parsed.batteryPercentage!;
    }
    if (parsed.isCharging != null) {
      isChargingNotifier.value = parsed.isCharging!;
    }

    // ── SESSION_START ────────────────────────────────────────────────────
    if (parsed.isStartPing) {
      _compressionEvents.clear();
      _ventilationEvents.clear();
      _pulseCheckEvents.clear();
      _rescuerVitalSnapshots.clear();
      _sessionStartMs             = DateTime.now().millisecondsSinceEpoch;
      _currentCycleNumber         = 0;
      _currentPulseIntervalNumber = 0;
      _lastPerfusionIndex         = 0;
    }

    // ── LIVE_STREAM continuous data ──────────────────────────────────────
    if (parsed.isContinuousData) {
      final nowMs = DateTime.now().millisecondsSinceEpoch - _sessionStartMs;

      // Compression event — only when a compression is active
      if (parsed.depth > 0 && parsed.frequency > 0) {
        _compressionEvents.add(CompressionEvent(
          timestampMs:         nowMs,
          depth:               parsed.depth,
          frequency:           parsed.frequency,
          force:               parsed.force,
          recoilAchieved:      parsed.recoilAchieved,
          overForce:           parsed.overForceFlag,
          postureOk:           parsed.postureOk,
          leaningDetected:     parsed.leaningDetected,
          wristAlignmentAngle: parsed.wristAlignmentAngle,
          compressionAxisDev:  parsed.compressionAxisDeviation,
          effectiveDepth:      parsed.effectiveDepth,
        ));
      }

      if (parsed.perfusionIndex > 0) {
        _lastPerfusionIndex = parsed.perfusionIndex;
      }

      // Quality-gated rescuer vital snapshot (only when signal is reliable)
      if (parsed.rescuerSignalQuality >= 40 && parsed.heartRateUser > 0) {
        _rescuerVitalSnapshots.add(RescuerVitalSnapshot(
          timestampMs:   nowMs,
          heartRate:     parsed.heartRateUser,
          spO2:          parsed.spO2User,
          temperature:   parsed.rescuerTemperature,
          signalQuality: parsed.rescuerSignalQuality,
          pauseType:     'active',
        ));
      }
    }

    // ── VENTILATION_WINDOW (0x03) ────────────────────────────────────────
    if (parsed.isVentilationWindow) {
      _currentCycleNumber++;
      _ventilationWindowMs =
          DateTime.now().millisecondsSinceEpoch - _sessionStartMs;
      _ventilationEvents.add(VentilationEvent(
        timestampMs:       _ventilationWindowMs,
        cycleNumber:       parsed.cycleNumber ?? _currentCycleNumber,
        ventilationsGiven: 0,
        durationSec:       0.0,
        compliant:         false,
      ));
    }

    // ── PULSE_CHECK_START (0x04) ─────────────────────────────────────────
    if (parsed.isPulseCheckStart) {
      _currentPulseIntervalNumber++;
      _currentPulseStartMs = parsed.sessionElapsedMs ??
          (DateTime.now().millisecondsSinceEpoch - _sessionStartMs);
    }

    // ── PULSE_CHECK_RESULT (0x05) ────────────────────────────────────────
    if (parsed.isPulseCheckResult) {
      _pulseCheckEvents.add(PulseCheckEvent(
        timestampMs:    _currentPulseStartMs,
        intervalNumber: _currentPulseIntervalNumber,
        detected:       (parsed.pulseDetected ?? 0) == 1,
        detectedBpm:    parsed.detectedBPM     ?? 0.0,
        confidence:     parsed.confidencePct   ?? 0,
        perfusionIndex: _lastPerfusionIndex,
      ));
    }

    // ── Broadcast for UI screens ─────────────────────────────────────────
    _dataController.add({
      // Core live metrics
      'depth':               parsed.depth,
      'frequency':           parsed.frequency,
      'force':               parsed.force,
      'angle':               parsed.angle,
      'compressionCount':    parsed.compressionCount,
      'compressionInCycle':  parsed.compressionInCycle,
      'wristAlignmentAngle': parsed.wristAlignmentAngle,
      'wristFlexionAngle':   parsed.wristFlexionAngle,
      'effectiveDepth':      parsed.effectiveDepth,
      'recoilAchieved':      parsed.recoilAchieved,
      'leaningDetected':     parsed.leaningDetected,
      'overForceFlag':       parsed.overForceFlag,
      'postureOk':           parsed.postureOk,
      'fatigueFlag':         parsed.fatigueFlag,
      // Patient vitals
      'heartRatePatient':    parsed.heartRatePatient,
      'spO2Patient':         parsed.spO2Patient,
      'ppgRaw':              parsed.ppgRaw,
      'ppgSignalQuality':    parsed.ppgSignalQuality,
      'perfusionIndex':      parsed.perfusionIndex,
      'patientTemperature':  parsed.patientTemperature,
      // Rescuer vitals
      'heartRateUser':        parsed.heartRateUser,
      'spO2User':             parsed.spO2User,
      'rescuerSignalQuality': parsed.rescuerSignalQuality,
      'rescuerTemperature':   parsed.rescuerTemperature,
      'temperatureUser':      parsed.temperatureUser,
      'temperaturePatient':   parsed.temperaturePatient,
      // Session state
      'sessionActive':    parsed.sessionActive,
      'pulseCheckActive': parsed.pulseCheckActive,
      'currentMode':      parsed.currentMode,
      'feedbackEnabled':  parsed.feedbackEnabled,
      'batteryPercentage': parsed.batteryPercentage,
      'isCharging':       parsed.isCharging,
      // Packet type flags
      'isStartPing':         parsed.isStartPing,
      'isEndPing':           parsed.isEndPing,
      'isContinuousData':    parsed.isContinuousData,
      'isVentilationWindow': parsed.isVentilationWindow,
      'isPulseCheckStart':   parsed.isPulseCheckStart,
      'isPulseCheckResult':  parsed.isPulseCheckResult,
      'isTwoMinAlert':       parsed.isTwoMinAlert,
      'isFatigueAlert':      parsed.isFatigueAlert,
      'isPendingLocalData':  parsed.isPendingLocalData,
      // SESSION_END summary (non-zero only on isEndPing)
      'totalCompressions':   parsed.totalCompressions,
      'correctDepth':        parsed.correctDepth,
      'correctFrequency':    parsed.correctFrequency,
      'correctRecoil':       parsed.correctRecoil,
      'depthRateCombo':      parsed.depthRateCombo,
      'correctPosture':      parsed.correctPosture,
      'leaningCount':        parsed.leaningCount,
      'overForceCount':      parsed.overForceCount,
      'tooDeepCount':        parsed.tooDeepCount,
      'totalVentilations':   parsed.totalVentilations,
      'pulseChecksPrompted': parsed.pulseChecksPrompted,
      'pulseChecksComplied': parsed.pulseChecksComplied,
      'pulseDetected':       parsed.pulseDetected,
      'fatigueOnsetIndex':   parsed.fatigueOnsetIndex,
      'peakDepth':           parsed.peakDepth,
      // Event-specific fields
      'cycleNumber':         parsed.cycleNumber,
      'intervalNumber':      parsed.intervalNumber,
      'detectedBPM':         parsed.detectedBPM,
      'confidencePct':       parsed.confidencePct,
      'pendingSessionCount': parsed.pendingSessionCount,
    });
  }

  // ── Disconnection handling ────────────────────────────────────────────────

  void _handleDisconnection() {
    if (_connectionState == BluetoothConnectionState.connected) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(AppConstants.mapAnimationDelay, _processDisconnection);
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
    final delaySeconds = math.min(
      AppConstants.bleReconnectInterval.inSeconds *
          math.pow(2, _reconnectAttempts - 1).toInt(),
      AppConstants.bleReconnectTimeout.inSeconds,
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_userDisconnected) _performSingleScan();
    });
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  void _cleanupConnection() {
    _liveStreamSub?.cancel();
    _eventChannelSub?.cancel();
    _connStateSub?.cancel();
    _debounceTimer?.cancel();
    _liveStreamBuffer.clear();
    _eventChannelBuffer.clear();

    _connectedDevice?.disconnect().catchError(
          (Object e) => debugPrint('BLE disconnect error: $e'),
    );

    _connectedDevice = null;
    _connectionState = BluetoothConnectionState.disconnected;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  Future<void> manualRetry() async {
    if (isConnected) return;
    debugPrint('BLE: manual retry');
    _reconnectAttempts = 0;
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

  Future<void> disconnectDevice() async {
    debugPrint('BLE: manual disconnect');
    _userDisconnected = true;
    _cleanupConnection();
    _updateStatus('Disconnected');
  }

  Future<bool> enableBluetooth({bool prompt = false}) async {
    if (await _isBluetoothOn()) return true;
    if (prompt) {
      await FlutterBluePlus.turnOn();
      await Future.delayed(const Duration(seconds: 2));
      return _isBluetoothOn();
    }
    return false;
  }

  // ── Event list getters ────────────────────────────────────────────────────

  List<CompressionEvent>     get compressionEvents     =>
      List.unmodifiable(_compressionEvents);
  List<VentilationEvent>     get ventilationEvents     =>
      List.unmodifiable(_ventilationEvents);
  List<PulseCheckEvent>      get pulseCheckEvents      =>
      List.unmodifiable(_pulseCheckEvents);
  List<RescuerVitalSnapshot> get rescuerVitalSnapshots =>
      List.unmodifiable(_rescuerVitalSnapshots);

  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  void dispose() {
    _debounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _scanSub?.cancel();
    _liveStreamSub?.cancel();
    _eventChannelSub?.cancel();
    _adapterStateSub?.cancel();
    _connStateSub?.cancel();
    _cleanupConnection();
    _dataController.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _isBluetoothOn() async =>
      await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
}