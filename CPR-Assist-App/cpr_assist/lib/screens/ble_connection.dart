import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart'; // For permissions

class BLEConnection extends StatefulWidget {
  const BLEConnection({super.key});

  @override
  _BLEConnection createState() => _BLEConnection();
}

class _BLEConnection extends State<BLEConnection> {
  bool isScanning = false;
  List<BluetoothDevice> pairedDevices = [];
  List<ScanResult> availableDevices = [];
  String connectionStatus = "Idle";

  StreamSubscription<List<ScanResult>>? scanSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBLEWorkflow();
  }

  Future<void> _initializeBLEWorkflow() async {
    // Step 1: Check and request Bluetooth permission
    if (!(await _checkAndRequestPermissions())) {
      return; // Stop if permissions are not granted
    }

    // Step 2: Check if Bluetooth is enabled
    if (!(await FlutterBluePlus.adapterState. first == BluetoothAdapterState. on)) {
      await _enableBluetooth();
    }

    // Step 3: Get paired devices
    await _getPairedDevices();
  }

  Future<bool> _checkAndRequestPermissions() async {
    final bluetoothPermission = await Permission.bluetooth.request();

    if (bluetoothPermission.isGranted) {
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth permission is required.')),
      );
      return false;
    }
  }

  Future<void> _enableBluetooth() async {
    bool isBluetoothEnabled = await FlutterBluePlus.adapterState. first == BluetoothAdapterState. on;

    if (!isBluetoothEnabled) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable Bluetooth'),
          content: const Text('Bluetooth is required to scan for devices. Please enable it.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                FlutterBluePlus.turnOn(); // Request to enable Bluetooth
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Wait until Bluetooth is turned on
      await FlutterBluePlus.adapterState.firstWhere((state) => state == BluetoothAdapterState.on);
    }
  }

  Future<void> _getPairedDevices() async {
    pairedDevices = FlutterBluePlus.connectedDevices;
    setState(() {}); // Update UI with paired devices
  }

  void _startScan() {
    setState(() {
      isScanning = true;
      connectionStatus = "Scanning for devices...";
      availableDevices.clear();
    });

    // Start scanning for available devices
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    // Listen to scan results (list of ScanResult)
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        availableDevices = results; // Directly assign the list of results
      });
    });

    // Stop scanning after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && isScanning) {
        setState(() {
          isScanning = false;
          connectionStatus = availableDevices.isEmpty
              ? "No devices found"
              : "Devices found";
        });
        scanSubscription?.cancel();
        FlutterBluePlus.stopScan();
      }
    });
  }

  void _connectToDevice(BluetoothDevice device) {
    setState(() {
      connectionStatus = "Connecting to ${device.platformName}...";
    });

    device.connect().then((_) {
      setState(() {
        connectionStatus = "Connected to ${device.platformName}";
      });
    }).catchError((error) {
      setState(() {
        connectionStatus = "Failed to connect";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $error')),
      );
    });
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Connection Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: isScanning ? null : _startScan,
              child: const Text('Scan for Devices'),
            ),
            const SizedBox(height: 20),
            if (pairedDevices.isNotEmpty) ...[
              const Text(
                'Paired Devices:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ListView.builder(
                shrinkWrap: true,
                itemCount: pairedDevices.length,
                itemBuilder: (context, index) {
                  final device = pairedDevices[index];
                  return ListTile(
                    title: Text(device.platformName),
                    subtitle: Text(device.remoteId.toString()),
                    trailing: ElevatedButton(
                      onPressed: () => _connectToDevice(device),
                      child: const Text('Connect'),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            if (availableDevices.isNotEmpty) ...[
              const Text(
                'Available Devices:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ListView.builder(
                shrinkWrap: true,
                itemCount: availableDevices.length,
                itemBuilder: (context, index) {
                  final result = availableDevices[index];
                  return ListTile(
                    title: Text(result.device.platformName.isNotEmpty
                        ? result.device.platformName
                        : "Unnamed Device"),
                    subtitle: Text(result.device.remoteId.toString()),
                    trailing: ElevatedButton(
                      onPressed: () => _connectToDevice(result.device),
                      child: const Text('Connect'),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            Text('Status: $connectionStatus'),
          ],
        ),
      ),
    );
  }
}
