import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/decrypted_data.dart';
import 'dart:math' as math;

class BLEConnection {
  static BLEConnection? _instance;
  static BLEConnection get instance {
    if (_instance == null) {
      throw Exception("BLEConnection not initialized");
    }
    return _instance!;
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _stateDebounceTimer;

  Stream<Map<String, dynamic>> get dataStream => decryptedDataHandler.dataStream;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;

  BluetoothCharacteristic? liveCharacteristic;

  factory BLEConnection({
    required DecryptedData decryptedDataHandler,
    required SharedPreferences prefs,
    required Function(String) onStatusUpdate,
  }) {
    _instance ??= BLEConnection._internal(
      decryptedDataHandler: decryptedDataHandler,
      prefs: prefs,
      onStatusUpdate: onStatusUpdate,
    );
    return _instance!;
  }

  BLEConnection._internal({
    required this.decryptedDataHandler,
    required this.prefs,
    required this.onStatusUpdate,
  }) {
    _disableBleLogs();
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
        await _cleanupConnection();
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
      // Stop any existing scan
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      _scanSubscription?.cancel();
      _scanTimeoutTimer?.cancel();

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (result.device.platformName.contains("Arduino Nano 33 BLE")) {
            debugPrint("✅ Found Arduino: ${result.device.platformName}");
            _stopScanAndConnect(result.device);
            return;
          }
        }
      });

      // Handle scan timeout
      _scanTimeoutTimer = Timer(const Duration(seconds: 15), () {
        if (isScanning) {
          debugPrint("❌ Scan timeout - Arduino not found");
          _scanSubscription?.cancel();
          FlutterBluePlus.stopScan();
          isScanning = false;
          _updateConnectionStatus("Arduino Not Found - Tap to Retry");
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
        await _cleanupConnection();
      }

      connectedDevice = device;
      _updateConnectionStatus("Connecting...");

      await device.connect().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      await Future.delayed(const Duration(milliseconds: 2000));

      // Monitor connection state
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        _currentConnectionState = state;
        debugPrint("📡 Connection state: $state");

        if (state == BluetoothConnectionState.disconnected) {
          debugPrint("🔴 Device disconnected");
          _handleDisconnection();
        }
      });

      await _setupNotifications(device); // ✅ Don't wait for state variable

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
      _reconnectAttempts = 0; // Add this line
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
    if (_userDisconnected) return; // Don't auto-reconnect if user disconnected

    debugPrint("🔄 Auto-reconnecting...");

    // Wait a moment before trying to reconnect
    int delaySeconds = math.min(2 * math.pow(2, _reconnectAttempts).toInt(), 30);
    await Future.delayed(Duration(seconds: delaySeconds));
    _reconnectAttempts++;

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint("❌ Max reconnect attempts reached");
      _updateConnectionStatus("Connection Lost - Tap to Retry");
      return;
    }

    if (_userDisconnected) return; // Check again after delay

    // Try to reconnect
    _performSingleScan();
  }

  Future<void> _cleanupConnection() async {
    _bleNotificationSubscription?.cancel();
    _connectionStateSub?.cancel();
    _stateDebounceTimer?.cancel();
    _receivedBuffer.clear();


    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (e) {
        debugPrint("Error disconnecting: $e");
      }
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

    _reconnectAttempts = 0; // Add this line
    _userDisconnected = false; // Reset manual disconnect flag

    // Stop any ongoing operations
    if (isScanning) {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanTimeoutTimer?.cancel();
      isScanning = false;
    }

    if (_isConnecting) {
      await _cleanupConnection();
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
    await _cleanupConnection();
    _updateConnectionStatus("Disconnected");
  }

  void _disableBleLogs() {
    // Your existing implementation
  }

  void dispose() {
    _scanTimeoutTimer?.cancel();
    _stateDebounceTimer?.cancel();
    _scanSubscription?.cancel();
    _bleNotificationSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    _connectionStateSub?.cancel();
    _cleanupConnection();
    _instance = null;
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