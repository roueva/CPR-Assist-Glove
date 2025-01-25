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
  final BuildContext context; // BuildContext for showing Snackbars

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
    if (isScanning || connectedDevice != null) return;

    isScanning = true;
    availableDevices.clear();
    _scanSubscription?.cancel();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      availableDevices = results.toSet().toList();
      onUpdate();
    }, onError: (error) {
      _showSnackbar('Scan error: $error');
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10)).then((_) {
      isScanning = false;
      onUpdate();
    }).catchError((error) {
      isScanning = false;
      _showSnackbar('Failed to start scan: $error');
    });
  }

  /// Connects to a selected BLE device
  Future<void> connectToDevice(BluetoothDevice device, Function onUpdate) async {
    if (connectedDevice != null) return;

    try {
      connectedDevice = device;
      onUpdate();

      await device.connect();
      startReceivingData(device);
      _showSnackbar('Connected to ${device.platformName}');
      onUpdate();
    } catch (error) {
      connectedDevice = null;
      _showSnackbar('Connection failed: $error');
      onUpdate();
    }
  }

  /// Disconnects the currently connected BLE device
  Future<void> disconnectDevice(Function onUpdate) async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
        connectedDevice = null;
        _showSnackbar('Disconnected');
        onUpdate();
      } catch (error) {
        _showSnackbar('Disconnection failed: $error');
      }
    }
  }

  /// Starts receiving and processing BLE notification data
  void startReceivingData(BluetoothDevice device) {
    const String serviceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
    const String characteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

    List<int> dataBuffer = []; // Buffer to store incoming data

    device.discoverServices().then((services) {
      try {
        final service = services.firstWhere(
              (s) => s.uuid.toString() == serviceUuid,
        );

        final characteristic = service.characteristics.firstWhere(
              (c) => c.uuid.toString() == characteristicUuid,
        );

        _bleNotificationSubscription = characteristic.lastValueStream.listen(
              (data) {
            dataBuffer.addAll(data); // Append incoming data to the buffer

            if (dataBuffer.length >= 32) {
              // If buffer contains 32 or more bytes, process the data
              final Uint8List uint8Data = Uint8List.fromList(dataBuffer.sublist(0, 32));
              decryptedDataHandler.processReceivedData(uint8Data);

              // Debug message: print and show a snackbar
              print('Data received: $uint8Data');
              _showSnackbar('Data received');

              // Remove the processed 32-byte chunk from the buffer
              dataBuffer.removeRange(0, 32);
            }
          },
          onError: (error) {
            _showSnackbar('Notification error: $error');
          },
        );

        characteristic.setNotifyValue(true);
      } catch (e) {
        _showSnackbar('Error discovering services: $e');
      }
    }).catchError((error) {
      _showSnackbar('Service discovery failed: $error');
    });
  }


  /// Show a snackbar with a debug message
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Cancels all subscriptions and disconnects the device
  void dispose() {
    _disconnectDevice();
    _scanSubscription?.cancel();
    _bleNotificationSubscription?.cancel();
  }

  Future<void> _disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      connectedDevice = null;
    }
  }
}
