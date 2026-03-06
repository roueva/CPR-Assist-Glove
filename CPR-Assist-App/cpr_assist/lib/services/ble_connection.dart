import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/decrypted_data.dart';
import 'dart:math' as math;

import '../utils/app_constants.dart';

class BLEConnection {
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _stateDebounceTimer;
  Timer? _reconnectTimer;


  Stream<Map<String, dynamic>> get dataStream => decryptedDataHandler.dataStream;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;

  BluetoothCharacteristic? liveCharacteristic;

  BLEConnection({
    required this.decryptedDataHandler,
    required this.prefs,
    required this.onStatusUpdate,
  }) {
    _listenToAdapterState();

    // Initial connection attempt
    Future.delayed(const Duration(milliseconds: 500), () {
      _performInitialConnection();
    });
  }

  bool isScanning = false;
  bool _isConnecting = false;
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _bleNotificationSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _scanTimeoutTimer;
  final List<int> _receivedBuffer = [];

  final DecryptedData decryptedDataHandler;
  final SharedPreferences prefs;
  final Function(String) onStatusUpdate;

  String? _lastStatus;
  BluetoothConnectionState _currentConnectionState = BluetoothConnectionState.disconnected;
  bool _userDisconnected = false; // Track if user manually disconnected
  bool _bluetoothWasOff = false; // Track if Bluetooth was turned off

  void _updateConnectionStatus(String status) {
    if (_lastStatus == status) return;
    _lastStatus = status;

    debugPrint("🔄 BLE Status: $status");
    connectionStatusNotifier.value = status;
    onStatusUpdate(status);
  }

  final ValueNotifier<String> connectionStatusNotifier = ValueNotifier("Disconnected");

  /// **INITIAL CONNECTION** - First attempt when app starts
  Future<void> _performInitialConnection() async {
    if (_userDisconnected) return; // Don't auto-connect if user disconnected

    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) {
      _performSingleScan();
    } else {
      _updateConnectionStatus("Bluetooth OFF");
    }
  }

  /// **Monitor Bluetooth State Changes**
  void _listenToAdapterState() {
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) async {
      if (state == BluetoothAdapterState.off) {
        _bluetoothWasOff = true;
        _updateConnectionStatus("Bluetooth OFF");
        _cleanupConnection();
      } else if (state == BluetoothAdapterState.on) {
        if (_bluetoothWasOff && !_userDisconnected) {
          // Auto-connect when Bluetooth turns back on (unless user manually disconnected)
          _bluetoothWasOff = false;
          _updateConnectionStatus("Bluetooth ON - Connecting...");
          await Future.delayed(const Duration(milliseconds: 1000)); // Give Bluetooth time to stabilize
          _performSingleScan();
        } else if (_bluetoothWasOff) {
          // Bluetooth turned on but user had disconnected manually
          _bluetoothWasOff = false;
          _updateConnectionStatus("Bluetooth ON - Tap to Connect");
        }
      }
    });
  }

  /// **Expose Bluetooth state changes as a Stream**
  Stream<BluetoothAdapterState> get adapterStateStream => FlutterBluePlus.adapterState;

  /// **Check if Bluetooth is ON**
  Future<bool> isBluetoothOn() async {
    return await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
  }

  bool get isConnected => _currentConnectionState == BluetoothConnectionState.connected;

  /// **SINGLE SCAN ATTEMPT**
  Future<void> _performSingleScan() async {
    if (_currentConnectionState == BluetoothConnectionState.connected ||
        isScanning || _isConnecting) {
      return;
    }

    if (!await isBluetoothOn()) {
      _updateConnectionStatus("Bluetooth OFF");
      return;
    }

    isScanning = true;
    _updateConnectionStatus("Scanning for Arduino...");

    try {
      // ✅ Cancel existing subscriptions FIRST
      _scanSubscription?.cancel();
      _scanSubscription = null;
      _scanTimeoutTimer?.cancel();

      // Stop any existing scan
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (result.device.platformName.contains(AppConstants.bleDeviceName)) {
            debugPrint("✅ Found Arduino: ${result.device.platformName}");
            _stopScanAndConnect(result.device);
            return;
          }
        }
        // Will be called when scan ends with no match found
      }, onDone: () {
        if (isScanning) {
          isScanning = false;
          _updateConnectionStatus("Glove Not Found - Tap to Retry");
        }
      });
    } catch (e) {
      debugPrint("❌ Scan error: $e");
      isScanning = false;
      _updateConnectionStatus("Scan Failed - Tap to Retry");
    }
  }

  void _stopScanAndConnect(BluetoothDevice device) {
    _scanTimeoutTimer?.cancel();
    _scanSubscription?.cancel();

    FlutterBluePlus.stopScan();
    isScanning = false;

    _connectToDevice(device);
  }

  /// **SINGLE CONNECTION ATTEMPT**
  Future<void> _connectToDevice(BluetoothDevice device) async {
    if (_isConnecting || _currentConnectionState == BluetoothConnectionState.connected) {
      debugPrint("⚠️ Already connecting or connected, skipping");
      return;
    }

    _isConnecting = true;
    debugPrint("🔌 Connecting to: ${device.platformName}");

    try {
      // Clean up existing connection
      if (connectedDevice != null && connectedDevice != device) {
        _cleanupConnection();
      }

      connectedDevice = device;
      _updateConnectionStatus("Connecting...");

      // ✅ Set up connection state listener BEFORE connecting
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        _currentConnectionState = state;
        debugPrint("📡 Connection state: $state");

        if (state == BluetoothConnectionState.disconnected) {
          debugPrint("🔴 Device disconnected");
          _handleDisconnection();
        }
      });

      // ✅ Now connect (listener is already set up)
      await device.connect().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      await Future.delayed(const Duration(milliseconds: 2000));

      await _setupNotifications(device);

    } catch (e) {
      debugPrint("❌ Connection failed: $e");
      _isConnecting = false;
      _updateConnectionStatus("Connection Failed - Tap to Retry");
    }
  }

  Future<void> _setupNotifications(BluetoothDevice device) async {
    const String serviceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
    const String characteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

    try {
      debugPrint("🔍 Setting up notifications...");
      final services = await device.discoverServices().timeout(const Duration(seconds: 15));

      final service = services.firstWhere(
            (s) => s.uuid.toString() == serviceUuid,
        orElse: () => throw Exception("Service not found"),
      );

      final characteristic = service.characteristics.firstWhere(
            (c) => c.uuid.toString() == characteristicUuid,
        orElse: () => throw Exception("Characteristic not found"),
      );

      liveCharacteristic = characteristic;

      await characteristic.setNotifyValue(true);

      _bleNotificationSubscription?.cancel();
      _bleNotificationSubscription = characteristic.lastValueStream.listen(
            (data) {
          _receivedBuffer.addAll(data);
          while (_receivedBuffer.length >= 48) {
            final completePacket = _receivedBuffer.sublist(0, 48);
            _receivedBuffer.removeRange(0, 48);
            decryptedDataHandler.processReceivedData(completePacket);
          }
          // Clear buffer if it gets too large (prevents memory leaks)
          if (_receivedBuffer.length > 100) {
            debugPrint("⚠️ Clearing oversized buffer");
            _receivedBuffer.clear();
          }
        },
        onError: (error) {
          debugPrint("❌ Notification error: $error");
          _handleDisconnection();
        },
      );

      _isConnecting = false;
      _userDisconnected = false; // Reset user disconnect flag on successful connection
      _reconnectAttempts = 0;
      _updateConnectionStatus("Connected");
      debugPrint("✅ Successfully connected");

    } catch (e) {
      debugPrint("❌ Notification setup failed: $e");
      _isConnecting = false;
      _updateConnectionStatus("Setup Failed - Tap to Retry");
    }
  }

  /// **Handle disconnection** - Auto-reconnect unless user manually disconnected
  void _handleDisconnection() {
    if (_currentConnectionState == BluetoothConnectionState.connected) return;

    _stateDebounceTimer?.cancel();
    _stateDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _processDisconnection();
    });
  }

  void _processDisconnection() {
    if (_isConnecting) {
      debugPrint("⚠️ Disconnection during connection attempt");
      _isConnecting = false;
    }

    if (_userDisconnected) {
      _updateConnectionStatus("Disconnected");
    } else {
      _updateConnectionStatus("Disconnected - Reconnecting...");
      _autoReconnect();
    }
  }

  /// **Auto-reconnect after unexpected disconnection**
  Future<void> _autoReconnect() async {
    if (_userDisconnected) return;

    // Cancel any existing reconnect timer
    _reconnectTimer?.cancel();

    // Check max attempts BEFORE delay
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint("❌ Max reconnect attempts reached");
      _updateConnectionStatus("Connection Lost - Tap to Retry");
      _reconnectAttempts = 0; // ✅ Reset for next manual retry
      return;
    }

    debugPrint("🔄 Auto-reconnect attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts");

    // Calculate delay AFTER incrementing
    _reconnectAttempts++;
    final delaySeconds = math.min(
      AppConstants.bleReconnectInterval.inSeconds * math.pow(2, _reconnectAttempts - 1).toInt(),
      AppConstants.bleReconnectTimeout.inSeconds,
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_userDisconnected) return;
      _performSingleScan();
    });
  }

  void _cleanupConnection() {
    _bleNotificationSubscription?.cancel();
    _connectionStateSub?.cancel();
    _stateDebounceTimer?.cancel();
    _receivedBuffer.clear();

    if (connectedDevice != null) {
      connectedDevice!.disconnect().catchError((e) {
        debugPrint("Error disconnecting: $e");
      });
    }

    connectedDevice = null;
    liveCharacteristic = null;
    _currentConnectionState = BluetoothConnectionState.disconnected;
  }

  /// **MANUAL RETRY** - Called when user taps retry button
  Future<void> manualRetry() async {
    if (_currentConnectionState == BluetoothConnectionState.connected) {
      debugPrint("⚠️ Already connected, ignoring retry");
      return;
    }

    debugPrint("🔄 Manual retry requested");

    _reconnectAttempts = 0;
    _userDisconnected = false;

    // ✅ ADD: Cancel any pending reconnect timer
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // Stop any ongoing operations
    if (isScanning) {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanTimeoutTimer?.cancel();
      isScanning = false;
    }

    if (_isConnecting) {
      _cleanupConnection();
      _isConnecting = false;
    }

    // Check if Bluetooth is on
    if (!await isBluetoothOn()) {
      _updateConnectionStatus("Bluetooth OFF");
      return;
    }

    // Start fresh scan
    _performSingleScan();
  }

  /// **Manual disconnect** - Prevents any automatic reconnection
  Future<void> disconnectDevice() async {
    debugPrint("🔌 Manual disconnect requested");
    _userDisconnected = true; // Set flag to prevent auto-reconnect
    _cleanupConnection();
    _updateConnectionStatus("Disconnected");
  }

  void dispose() {
    _scanTimeoutTimer?.cancel();
    _stateDebounceTimer?.cancel();
    _scanSubscription?.cancel();
    _reconnectTimer?.cancel();
    _bleNotificationSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _connectionStateSub?.cancel();
    _cleanupConnection();
  }

  /// **Enable Bluetooth (if OFF)**
  Future<bool> enableBluetooth({bool prompt = false}) async {
    if (await isBluetoothOn()) return true;

    if (prompt) {
      await FlutterBluePlus.turnOn();
      await Future.delayed(const Duration(seconds: 2));
      return await isBluetoothOn();
    }

    return false;
  }
}