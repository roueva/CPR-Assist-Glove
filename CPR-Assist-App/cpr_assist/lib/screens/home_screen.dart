import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/account_menu.dart';
import 'login_screen.dart';
import 'training_screen.dart';
import 'emergency_screen.dart';
import '../services/decrypted_data.dart'; // Import DecryptedData handler

class HomeScreen extends StatefulWidget {
  final DecryptedData decryptedDataHandler;

  const HomeScreen({super.key, required this.decryptedDataHandler});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isScanning = false;
  bool isLoggedIn = false; // Track login status
  List<ScanResult> availableDevices = [];
  String connectionStatus = "Idle";
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _bleNotificationSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// Initialize app: check login status and set up BLE workflow
  Future<void> _initializeApp() async {
    await _checkLoginStatus();
    _initializeBLEWorkflow();
  }

  /// Check login status from shared preferences
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    });
  }

  /// Initializes BLE workflow by checking permissions and enabling Bluetooth if needed
  Future<void> _initializeBLEWorkflow() async {
    if (!(await _checkAndRequestPermissions())) return;

    if (!(await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on)) {
      await _enableBluetooth();
    }
  }

  /// Checks and requests necessary BLE and location permissions
  Future<bool> _checkAndRequestPermissions() async {
    final permissions = [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ];

    final statuses = await permissions.request();
    if (statuses.values.every((status) => status.isGranted)) {
      return true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bluetooth and location permissions are required.')),
      );
      return false;
    }
  }

  /// Enables Bluetooth if it's not already enabled
  Future<void> _enableBluetooth() async {
    BluetoothAdapterState adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable Bluetooth'),
          content: const Text('Bluetooth is required to scan for devices. Please enable it.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                FlutterBluePlus.turnOn();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await FlutterBluePlus.adapterState.firstWhere((state) => state == BluetoothAdapterState.on);
    }
  }

  /// Starts scanning for BLE devices
  void _startScan() {
    if (connectedDevice != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already connected to a device. Disconnect first.')),
      );
      return;
    }

    setState(() {
      isScanning = true;
      connectionStatus = "Scanning for devices...";
      availableDevices.clear();
    });

    _scanSubscription?.cancel();

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        availableDevices = results.toSet().toList();
        connectionStatus = availableDevices.isEmpty ? "No devices found" : "Devices found";
      });
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && isScanning) {
        setState(() {
          isScanning = false;
        });
        FlutterBluePlus.stopScan();
      }
    });
  }

  /// Connects to a selected BLE device and starts receiving data
  void _connectToDevice(BluetoothDevice device) {
    if (connectedDevice != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already connected to a device.')),
      );
      return;
    }

    setState(() {
      connectionStatus = "Connecting to ${device.platformName}...";
    });

    device.connect().then((_) {
      setState(() {
        connectedDevice = device;
        connectionStatus = "Connected to ${device.platformName}";
        _startReceivingData(device);
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

  /// Disconnects the currently connected BLE device
  void _disconnectDevice() {
    if (connectedDevice != null) {
      connectedDevice!.disconnect().then((_) {
        setState(() {
          connectedDevice = null;
          connectionStatus = "Disconnected";
        });
      }).catchError((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error disconnecting: $error')),
        );
      });
    }
  }

  /// Starts receiving and processing BLE notification data
  void _startReceivingData(BluetoothDevice device) {
    const String serviceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
    const String characteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';

    device.discoverServices().then((services) {
      try {
        final service = services.firstWhere(
              (s) => s.uuid.toString() == serviceUuid,
          orElse: () => throw Exception('Service not found'),
        );

        final characteristic = service.characteristics.firstWhere(
              (c) => c.uuid.toString() == characteristicUuid,
          orElse: () => throw Exception('Characteristic not found'),
        );

        _bleNotificationSubscription = characteristic.lastValueStream.listen((data) {
          final Uint8List uint8Data = Uint8List.fromList(data); // Convert to Uint8List
          widget.decryptedDataHandler.processReceivedData(uint8Data);
        });

        characteristic.setNotifyValue(true).then((_) {
          print('Notifications enabled successfully.');
        }).catchError((error) {
          print('Failed to enable notifications: $error');
        });
      } catch (e) {
        print('Error during service/characteristic discovery: $e');
      }
    }).catchError((error) {
      print('Failed to discover services: $error');
    });
  }

  /// Handles navigation to Training Mode
  Future<void> _handleTrainingMode() async {
    if (isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TrainingScreen(
            dataStream: widget.decryptedDataHandler.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(
            dataStream: widget.decryptedDataHandler.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _disconnectDevice();
    _scanSubscription?.cancel();
    _bleNotificationSubscription?.cancel();
    widget.decryptedDataHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CPR Assist Dashboard'),
        actions: [
          AccountMenu(decryptedDataHandler: widget.decryptedDataHandler),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: isScanning ? null : _startScan,
              child: const Text('Scan for Devices'),
            ),
            const SizedBox(height: 20),
            if (availableDevices.isNotEmpty) ...[
              const Text(
                'Available Devices:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
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
              ),
              const SizedBox(height: 20),
              Text('Status: $connectionStatus'),
              const SizedBox(height: 20),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _handleTrainingMode,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200, 60),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: const Text('Training Mode'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EmergencyScreen(
                          dataStream: widget.decryptedDataHandler.dataStream,
                          decryptedDataHandler: widget.decryptedDataHandler,
                        ),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(200, 60),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: const Text('Emergency Mode'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
