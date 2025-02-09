import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/decrypted_data.dart';

class BLEConnection {
  static BLEConnection? _instance; // ✅ Track the single instance

  factory BLEConnection({
    required DecryptedData decryptedDataHandler,
    required SharedPreferences prefs,
    required Function(String) onStatusUpdate,
  }) {
    _instance ??= BLEConnection._internal( // ✅ Create only one instance
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
    _listenToAdapterState();

    Future.delayed(const Duration(seconds: 1), () async {
      if (await isBluetoothOn()) {
        scanAndConnect(); // ✅ Start scanning ONLY if Bluetooth is ON
      } else {
        _updateConnectionStatus("Bluetooth OFF");
      }
    });
  }

  bool isScanning = false;
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _bleNotificationSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _monitorConnectionTimer;
  final List<int> _receivedBuffer = [];

  final DecryptedData decryptedDataHandler;
  final SharedPreferences prefs;
  final Function(String) onStatusUpdate;

  String? _lastStatus; // ✅ Track last status to prevent duplicates

  void _updateConnectionStatus(String status) {
    if (_lastStatus == status) return; // ✅ Avoid duplicate updates
    _lastStatus = status;

    debugPrint("🔄 BLE Status: $status"); // ✅ Logs BLE state changes
    connectionStatusNotifier.value = status; // ✅ Notify UI listeners
  }

  final ValueNotifier<String> connectionStatusNotifier = ValueNotifier("Disconnected");


  /// **Monitor Bluetooth State**
  void _listenToAdapterState() {
    _adapterStateSubscription?.cancel();
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) async {
      String newStatus = (state == BluetoothAdapterState.off) ? "Bluetooth OFF" : "Bluetooth ON";

      if (_lastStatus != newStatus) {
        _updateConnectionStatus(newStatus);
      }

      // ✅ Ensure scanning starts IMMEDIATELY when Bluetooth turns on
      if (state == BluetoothAdapterState.on && !isConnected()) {
        debugPrint("🔍 Bluetooth is ON. Ensuring scan starts...");
        scanAndConnect();
      }
    });
  }


  /// ✅ Expose Bluetooth state changes as a Stream
  Stream<BluetoothAdapterState> get adapterStateStream => FlutterBluePlus.adapterState;


  /// **Check if Bluetooth is ON**
  Future<bool> isBluetoothOn() async {
    return await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
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

  /// **Check if Device is Connected**
  bool isConnected() => connectedDevice?.isConnected ?? false;


  Future<void> scanAndConnect() async {
    if (isConnected() || isScanning) return;

    if (!await isBluetoothOn()) {
      _updateConnectionStatus("Bluetooth OFF");
      isScanning = false;
      return;
    }

    isScanning = true;
    _updateConnectionStatus("Scanning for Arduino...");

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    FlutterBluePlus.startScan();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        if (result.device.platformName.contains("Arduino Nano 33 BLE")) {
          debugPrint("✅ Found Arduino, stopping scan...");
          FlutterBluePlus.stopScan();
          isScanning = false;
          connectToDevice(result.device);
          return;
        }
      }
    });

    await Future.delayed(const Duration(seconds: 15));

    if (!isConnected()) {
      debugPrint("❌ Arduino not found");
      FlutterBluePlus.stopScan();
      _updateConnectionStatus("Arduino Not Found");
    }
    isScanning = false;
  }

  /// **Connect to Arduino**
  Future<void> connectToDevice(BluetoothDevice device) async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
    }

    connectedDevice = device;
    try {
      await device.connect().timeout(const Duration(seconds: 15));
      await Future.delayed(const Duration(seconds: 2));

      _updateConnectionStatus("Connected");
      startReceivingData(device);
      startMonitoringConnection(); // ✅ Monitor connection for unexpected disconnections
    } catch (e) {
      _updateConnectionStatus("Disconnected → Reconnecting...");
      scanAndConnect(); // ✅ Immediately restart 15-sec scan if connection fails
    }
  }

  /// **Starts receiving and processing BLE notification data**
  void startReceivingData(BluetoothDevice device) {
    const String serviceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
    const String characteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

    device.discoverServices().then((services) {
      try {
        final service = services.firstWhere((s) => s.uuid.toString() == serviceUuid);
        final characteristic = service.characteristics.firstWhere((c) => c.uuid.toString() == characteristicUuid);

        characteristic.setNotifyValue(true).then((_) {
          debugPrint("✅ BLE Notifications Enabled");

          _bleNotificationSubscription = characteristic.lastValueStream.listen((data) {
            _receivedBuffer.addAll(data);

            if (_receivedBuffer.length >= 32) {
              debugPrint("📩 Full 32-Byte BLE Data Received: $_receivedBuffer");

              decryptedDataHandler.processReceivedData(_receivedBuffer.sublist(0, 32));
              _receivedBuffer.clear(); // ✅ Reset buffer for next transmission
            }
          });
        });
      } catch (e) {
        debugPrint("❌ Error during service discovery: $e");
      }
    });
  }

  /// **If Arduino Disconnects → Start 15-sec Scan Again Immediately**
  void startMonitoringConnection() {
    _monitorConnectionTimer?.cancel();
    _monitorConnectionTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (connectedDevice == null || !isConnected()) {
        debugPrint("🔴 Arduino Disconnected → Starting Scan Again...");
        _updateConnectionStatus("Disconnected → Reconnecting...");
        scanAndConnect();
      }
    });
  }

  /// **Manual Retry Button**
  Future<void> retryScan() async {
    if (_lastStatus == "Arduino Not Found" || _lastStatus == "Disconnected") {
      scanAndConnect();
    }
  }

  /// **Disconnect from Device**
  Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
      _updateConnectionStatus("Disconnected");
      _monitorConnectionTimer?.cancel(); // ✅ Stop automatic reconnection attempts
    }
  }

  /// **Clean Up Resources**
  void dispose() {
    _monitorConnectionTimer?.cancel();
    _scanSubscription?.cancel();
    _bleNotificationSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    connectedDevice = null;
  }
}
