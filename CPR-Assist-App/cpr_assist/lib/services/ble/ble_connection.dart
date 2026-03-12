import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpr_assist/core/core.dart';

import 'ble_data_processor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEConnection
//
// Manages the full lifecycle of the BLE glove connection:
//   scan → connect → discover services → subscribe to notifications
//   → auto-reconnect on unexpected drop → manual retry on request.
//
// Parsed packets are broadcast on [dataStream].
// Battery & charging state are exposed as [ValueNotifier]s so UI widgets
// can listen without coupling to any data-handler class.
//
// Rules:
//   - All timing constants come from AppConstants — no magic Duration literals.
//   - All debug output via debugPrint (stripped in release builds).
//   - No UI code, no colors, no spacing.
// ─────────────────────────────────────────────────────────────────────────────

class BLEConnection {
  // ── BLE data ──────────────────────────────────────────────────────────────

  final _processor = const BLEDataProcessor();
  final _dataController = StreamController<Map<String, dynamic>>.broadcast();

  /// Parsed BLE data packets broadcast to all listeners.
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  // ── Public state notifiers (read by UI widgets) ───────────────────────────

  final ValueNotifier<String> connectionStatusNotifier =
  ValueNotifier('Disconnected');
  final ValueNotifier<int>  batteryPercentageNotifier = ValueNotifier(0);
  final ValueNotifier<bool> isChargingNotifier        = ValueNotifier(false);

  // ── Internal state ────────────────────────────────────────────────────────

  bool _isScanning    = false;
  bool _isConnecting  = false;
  bool _userDisconnected = false;
  bool _bluetoothWasOff  = false;
  int  _reconnectAttempts = 0;

  BluetoothDevice?                        _connectedDevice;
  BluetoothConnectionState                _connectionState =
      BluetoothConnectionState.disconnected;

  StreamSubscription<List<ScanResult>>?         _scanSub;
  StreamSubscription<List<int>>?                _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<BluetoothAdapterState>?    _adapterStateSub;

  Timer? _debounceTimer;
  Timer? _reconnectTimer;

  final List<int> _buffer = [];

  // ── Dependencies ──────────────────────────────────────────────────────────

  final SharedPreferences prefs;
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

  // ── Connection getters ────────────────────────────────────────────────────

  bool get isConnected =>
      _connectionState == BluetoothConnectionState.connected;

  bool get isScanning => _isScanning;

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

  // ── Scan ─────────────────────────────────────────────────────────────────

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
        await Future.delayed(AppConstants.zoomAnimationDelay); // 500 ms stabilise
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

  // ── Service discovery & notifications ────────────────────────────────────

  Future<void> _setupNotifications(BluetoothDevice device) async {
    const serviceUuid        = '19b10000-e8f2-537e-4f6c-d104768a1214';
    const characteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

    try {
      final services = await device
          .discoverServices()
          .timeout(AppConstants.bleServiceDiscoveryTimeout);

      final service = services.firstWhere(
            (s) => s.uuid.toString() == serviceUuid,
        orElse: () => throw Exception('BLE service not found'),
      );

      final characteristic = service.characteristics.firstWhere(
            (c) => c.uuid.toString() == characteristicUuid,
        orElse: () => throw Exception('BLE characteristic not found'),
      );

      await characteristic.setNotifyValue(true);

      _notifySub?.cancel();
      _notifySub = characteristic.lastValueStream.listen(
            (data) {
          _buffer.addAll(data);

          while (_buffer.length >= AppConstants.blePacketSize) {
            final packet = _buffer.sublist(0, AppConstants.blePacketSize);
            _buffer.removeRange(0, AppConstants.blePacketSize);
            _handlePacket(packet);
          }

          if (_buffer.length > AppConstants.bleBufferOverflowThreshold) {
            debugPrint('BLE: buffer overflow — clearing');
            _buffer.clear();
          }
        },
        onError: (Object e) {
          debugPrint('BLE notification error: $e');
          _handleDisconnection();
        },
      );

      _isConnecting    = false;
      _userDisconnected = false;
      _reconnectAttempts = 0;
      _updateStatus('Connected');
      debugPrint('BLE: connected successfully');
    } catch (e) {
      debugPrint('BLE notification setup failed: $e');
      _isConnecting = false;
      _updateStatus('Setup Failed — Tap to Retry');
    }
  }

  // ── Packet handling ───────────────────────────────────────────────────────

  void _handlePacket(List<int> packet) {
    final parsed = _processor.parsePacket(packet);
    if (parsed == null) return;

    // Update battery notifiers for UI (header pill)
    if (parsed.batteryPercentage != null) {
      batteryPercentageNotifier.value = parsed.batteryPercentage!;
    }
    if (parsed.isCharging != null) {
      isChargingNotifier.value = parsed.isCharging!;
    }

    // Broadcast full packet data for screens that need it
    _dataController.add({
      'depth':             parsed.depth,
      'frequency':         parsed.frequency,
      'angle':             parsed.angle,
      'compressionCount':  parsed.compressionCount,
      'isStartPing':       parsed.isStartPing,
      'isEndPing':         parsed.isEndPing,
      'isContinuousData':  parsed.isContinuousData,
      'batteryPercentage': parsed.batteryPercentage,
      'isCharging':        parsed.isCharging,
      'heartRatePatient':  parsed.heartRatePatient,
      'temperaturePatient': parsed.temperaturePatient,
      'heartRateUser':     parsed.heartRateUser,
      'temperatureUser':   parsed.temperatureUser,
      'correctDepth':      parsed.correctDepth,
      'correctFrequency':  parsed.correctFrequency,
      'correctRecoil':     parsed.correctRecoil,
      'depthRateCombo':    parsed.depthRateCombo,
      'totalCompressions': parsed.totalCompressions,
    });
  }

  // ── Disconnection handling ────────────────────────────────────────────────

  void _handleDisconnection() {
    if (_connectionState == BluetoothConnectionState.connected) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      AppConstants.mapAnimationDelay, // 300 ms debounce
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
      'BLE: auto-reconnect attempt $_reconnectAttempts'
          '/${AppConstants.bleMaxReconnectAttempts}',
    );

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
    _notifySub?.cancel();
    _connStateSub?.cancel();
    _debounceTimer?.cancel();
    _buffer.clear();

    _connectedDevice?.disconnect().catchError(
          (Object e) => debugPrint('BLE disconnect error: $e'),
    );

    _connectedDevice    = null;
    _connectionState    = BluetoothConnectionState.disconnected;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Called when the user taps the retry/reconnect button.
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

  /// Manually disconnect — suppresses all auto-reconnect logic.
  Future<void> disconnectDevice() async {
    debugPrint('BLE: manual disconnect');
    _userDisconnected = true;
    _cleanupConnection();
    _updateStatus('Disconnected');
  }

  /// Request Bluetooth to turn on (no-op if already on).
  Future<bool> enableBluetooth({bool prompt = false}) async {
    if (await _isBluetoothOn()) return true;
    if (prompt) {
      await FlutterBluePlus.turnOn();
      await Future.delayed(const Duration(seconds: 2));
      return _isBluetoothOn();
    }
    return false;
  }

  /// Expose adapter state changes for any widget that needs it.
  Stream<BluetoothAdapterState> get adapterStateStream =>
      FlutterBluePlus.adapterState;

  void dispose() {
    _debounceTimer?.cancel();
    _reconnectTimer?.cancel();
    _scanSub?.cancel();
    _notifySub?.cancel();
    _adapterStateSub?.cancel();
    _connStateSub?.cancel();
    _cleanupConnection();
    _dataController.close();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _isBluetoothOn() async =>
      await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
}