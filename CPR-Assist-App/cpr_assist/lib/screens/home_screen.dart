import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/account_menu.dart';
import 'login_screen.dart';
import 'training_screen.dart';
import 'emergency_screen.dart';
import '../services/decrypted_data.dart';
import '../services/ble_connection.dart';

class HomeScreen extends StatefulWidget {
  final DecryptedData decryptedDataHandler;

  const HomeScreen({super.key, required this.decryptedDataHandler});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late BLEConnection bleConnection;
  bool isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    bleConnection = BLEConnection(
      decryptedDataHandler: widget.decryptedDataHandler,
      context: context,
    );
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkLoginStatus();
    if (await bleConnection.checkAndRequestPermissions()) {
      await bleConnection.enableBluetooth();
    }
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    });
  }

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
    bleConnection.dispose();
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
            // BLE Section
            if (bleConnection.connectedDevice == null) ...[
              ElevatedButton(
                onPressed: bleConnection.isScanning ? null : () => bleConnection.startScan(() => setState(() {})),
                child: const Text('Scan for Devices'),
              ),
              const SizedBox(height: 20),
              if (bleConnection.availableDevices.isNotEmpty)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: bleConnection.availableDevices.length,
                    itemBuilder: (context, index) {
                      final result = bleConnection.availableDevices[index];
                      return ListTile(
                        title: Text(result.device.platformName.isNotEmpty
                            ? result.device.platformName
                            : "Unnamed Device"),
                        subtitle: Text(result.device.remoteId.toString()),
                        trailing: ElevatedButton(
                          onPressed: () => bleConnection.connectToDevice(result.device, () => setState(() {})),
                          child: const Text('Connect'),
                        ),
                      );
                    },
                  ),
                ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Connected to: ${bleConnection.connectedDevice!.platformName}'),
                  ElevatedButton(
                    onPressed: () => bleConnection.disconnectDevice(() {
                      setState(() {});
                      bleConnection.startScan(() => setState(() {})); // Restart scanning
                    }),
                    child: const Text('Disconnect'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 40),
            // Buttons Section
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Square button with rounded corners for Training Mode
                    ElevatedButton(
                      onPressed: _handleTrainingMode,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 60), // Larger button
                        backgroundColor: Colors.blueGrey[300], // Softer color
                      ),
                      child: const Text(
                        'Training Mode',
                        style: TextStyle(fontSize: 20, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Square button with rounded corners for Emergency Mode
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 60), // Larger button
                        backgroundColor: Colors.red[300], // Softer color
                      ),
                      child: const Text(
                        'Emergency Mode',
                        style: TextStyle(fontSize: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
