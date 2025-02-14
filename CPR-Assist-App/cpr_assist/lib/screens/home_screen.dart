import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../widgets/account_menu.dart';
import '../services/decrypted_data.dart';
import 'training_screen.dart';
import 'login_screen.dart';
import '../services/ble_connection.dart';
import '../widgets/ble_status_indicator.dart';
import '../widgets/aed_map_widget.dart';


class HomeScreen extends StatefulWidget {
  final DecryptedData decryptedDataHandler;
  final bool isLoggedIn; // ✅ Add this

  const HomeScreen({
    super.key,
    required this.decryptedDataHandler,
    required this.isLoggedIn, // ✅ Ensure it's required
  });

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BLEConnection bleConnection = globalBLEConnection; // ✅ Use global instance
  String connectionStatus = "Disconnected";

  @override
  void initState() {
    super.initState();
  }

  /// **📞 Make Emergency Call**
  void _makeEmergencyCall() {
    launchUrl(Uri.parse('tel:112'));
  }
  /// **🎯 Handle Training Mode Button Click**
  Future<void> _handleTrainingMode() async {
    final prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (!isLoggedIn) {
      debugPrint("❌ User not authenticated. Redirecting to Login.");

      // ✅ Ensure `Navigator.push()` only returns a boolean
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => LoginScreen(
            dataStream: widget.decryptedDataHandler.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
      );

      if (loggedIn == true) {
        debugPrint("✅ User successfully logged in. Navigating to Training Mode.");
        _navigateToTrainingMode();
      } else {
        debugPrint("❌ User canceled login. Staying on HomeScreen.");
      }
      return;
    }

    _navigateToTrainingMode();
  }


  /// **🔀 Navigate to Training Mode**
  void _navigateToTrainingMode() {
    debugPrint("✅ User authenticated. Navigating to Training Mode.");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrainingScreen(
          dataStream: widget.decryptedDataHandler.dataStream,
          decryptedDataHandler: widget.decryptedDataHandler,
        ),
      ),
    );
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
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 🚨 Emergency Call Button
                GestureDetector(
                  onTap: _makeEmergencyCall,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Call 112',
                        style: TextStyle(
                          fontSize: 26,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // 🏥 AED Map Widget (Scrollable)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12), // ✅ Rounded edges
                    child: AEDMapWidget(), // ✅ Add the Map Widget here
                  ),
                ),

                const SizedBox(height: 30),

                // 🎯 Training Mode Button
                ElevatedButton(
                  onPressed: _handleTrainingMode,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.black38,
                    elevation: 5,
                  ),
                  child: const Text('Training Mode'),
                ),
              ],
            ),
          ),

          // ✅ BLE Connection Status Indicator (Bottom Right)
          BLEStatusIndicator(
            bleConnection: globalBLEConnection,
            connectionStatusNotifier: globalBLEConnection.connectionStatusNotifier, // ✅ Pass ValueNotifier
          ),
        ],
      ),
    );
  }
}
