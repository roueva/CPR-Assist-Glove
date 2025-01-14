import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/decrypted_data.dart';

class BLEConnection {
  bool isScanning = false;
  List<ScanResult> availableDevices = [];
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _bleNotificationSubscription;
  final DecryptedData decryptedDataHandler;

  final BuildContext context; // Store BuildContext for showing Snackbars

  BLEConnection({required this.decryptedDataHandler, required this.context});

  /// Checks and requests necessary BLE and location permissions
  Future<bool> checkAndRequestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ];

    final statuses = await permissions.request();
    return statuses.values.every((status) => status.isGranted);
  }

  /// Enables Bluetooth if it's not already enabled
  Future<void> enableBluetooth() async {
    BluetoothAdapterState adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }
  }

  /// Starts scanning for BLE devices
  void startScan(Function onUpdate) {
    if (connectedDevice != null) return;

    isScanning = true;
    availableDevices.clear();
    _scanSubscription?.cancel();

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      availableDevices = results.toSet().toList();
      onUpdate();
    });

    Future.delayed(const Duration(seconds: 10), () {
      isScanning = false;
      FlutterBluePlus.stopScan();
      onUpdate();
    });
  }

  /// Connects to a selected BLE device
  Future<void> connectToDevice(BluetoothDevice device, Function onUpdate) async {
    if (connectedDevice != null) return;

    connectedDevice = device;
    onUpdate();

    await device.connect();
    startReceivingData(device);
    onUpdate();
  }

  /// Disconnects the currently connected BLE device
  Future<void> disconnectDevice(Function onUpdate) async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
      onUpdate();
    }
  }

  /// Starts receiving and processing BLE notification data
  void startReceivingData(BluetoothDevice device) {
    const String serviceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
    const String characteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

    device.discoverServices().then((services) {
      try {
        final service = services.firstWhere(
              (s) => s.uuid.toString() == serviceUuid,
        );

        final characteristic = service.characteristics.firstWhere(
              (c) => c.uuid.toString() == characteristicUuid,
        );

        _bleNotificationSubscription = characteristic.lastValueStream.listen((data) {
          final Uint8List uint8Data = Uint8List.fromList(data); // Convert to Uint8List
          decryptedDataHandler.processReceivedData(uint8Data);

          // Debug message: print and show a snackbar
          print('Data received: $data');
          _showSnackbar('Data received');
        });

        characteristic.setNotifyValue(true);
      } catch (e) {
        print('Error during service/characteristic discovery: $e');
      }
    });
  }

  /// Show a snackbar with a debug message
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Cancels all subscriptions
  void dispose() {
    _disconnectDevice();
    _scanSubscription?.cancel();
    _bleNotificationSubscription?.cancel();
  }

  Future<void> _disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
    }
  }
}
