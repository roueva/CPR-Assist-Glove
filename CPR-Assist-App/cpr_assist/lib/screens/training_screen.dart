  import 'dart:async';
  import 'package:flutter/material.dart';
  import 'package:flutter_blue_plus/flutter_blue_plus.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import '../main.dart';
  import '../services/decrypted_data.dart';
  import 'live_cpr_screen.dart';
import 'login_screen.dart';
  import 'past_sessions_screen.dart';
  import '../services/network_service.dart';


  class TrainingScreen extends StatefulWidget {
    final Stream<Map<String, dynamic>> dataStream;
    final DecryptedData decryptedDataHandler;
    final Function(int) onTabTapped;

    const TrainingScreen({
      super.key,
      required this.dataStream,
      required this.decryptedDataHandler,
      required this.onTabTapped,
    });

    @override
    _TrainingScreenState createState() => _TrainingScreenState();
  }

  class _TrainingScreenState extends State<TrainingScreen> with AutomaticKeepAliveClientMixin {

    @override
    bool get wantKeepAlive => true;
    String connectionStatus = "Disconnected";
    int compressionCount = 0;
    int correctWeight = 0;
    int correctFrequency = 0;
    int? patientHeartRate;
    double? patientTemperature;
    int? userHeartRate;
    double? userTemperatureRate;
    bool? correctRebound;
    double totalGrade = 0.0;
    late StreamSubscription<Map<String, dynamic>> dataSubscription;
    bool? isLoggedIn;
    bool _isDisposed = false;

    @override
    void initState() {
      super.initState();
      _startReceivingData();

      // ✅ Listen to BLE Status
      globalBLEConnection.adapterStateStream.listen((state) {
        if (mounted) {
          setState(() {
            connectionStatus = (state == BluetoothAdapterState.on && globalBLEConnection.isConnected())
                ? "Connected"
                : "Bluetooth OFF";
          });
          if (state == BluetoothAdapterState.off && !_bluetoothPromptShown) {
            _showBluetoothPrompt();
          }
        }
      });
    }

    @override
    void dispose() {
      _isDisposed = true;
      dataSubscription.cancel();
      super.dispose();
    }

    bool _bluetoothPromptShown = false; // Add this in the class

    void _showBluetoothPrompt() async {
      if (_bluetoothPromptShown) return; // ✅ Prevent multiple prompts
      _bluetoothPromptShown = true;

      bool bluetoothEnabled = await globalBLEConnection.enableBluetooth(prompt: true);
      if (!bluetoothEnabled && mounted) {
        setState(() => connectionStatus = "Bluetooth is required for Training Mode.");
      }
    }

    void _startReceivingData() {
      if (_isDisposed) return;

      dataSubscription = widget.dataStream.listen(
            (data) {
          if (_isDisposed) return;
          setState(() {
            compressionCount = data['totalCompressions'] ?? 0;
            correctWeight = data['correctWeightCompressions'] ?? 0;
            correctFrequency = data['correctFrequencyCompressions'] ?? 0;
            patientHeartRate = data['patientHeartRate'] ?? 0;
            patientTemperature = data['patientTemperature'] ?? 0.0;
            userHeartRate = data['userHeartRate'] ?? 0;
            userTemperatureRate = data['userTemperatureRate'] ?? 0.0;
            correctRebound = data['correctRebound'] ?? false;
            totalGrade = data['totalGrade'] ?? 0.0;

          });
        },
        onError: (error) {
          if (_isDisposed) return;
          _showSnackbar("Data stream error: $error");

          // ✅ Only mark as disconnected if it was previously connected
          if (connectionStatus == "Connected") {
            setState(() => connectionStatus = "Disconnected");
          }
        },
        onDone: () {
          if (_isDisposed) return;
          if (connectionStatus == "Connected") {
            setState(() => connectionStatus = "Disconnected");
          }
        },
      );
    }

    /// **💾 Save Session Data (Only if Logged In)**
    Future<void> _saveSessionData() async {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (!isLoggedIn) {
        debugPrint("⚠️ User not logged in. Redirecting to Login...");

        // ✅ Redirect to login screen, then retry saving after login
        bool loggedIn = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LoginScreen(
              dataStream: widget.dataStream,
              decryptedDataHandler: widget.decryptedDataHandler,
            ),
          ),
        );

        if (loggedIn == true) {
          _saveSessionData(); // ✅ Try saving again after successful login
        }
        return;
      }

      try {
        final sessionData = {
          'compression_count': compressionCount,
          'correct_depth': correctWeight,
          'correct_frequency': correctFrequency,
          'correct_angle': 0.0,
          'patient_heart_rate': patientHeartRate ?? 0,
          'patient_temperature': patientTemperature ?? 0.0,
          'user_heart_rate': userHeartRate ?? 0,
          'user_temperature_rate': userTemperatureRate ?? 0.0,
          'correct_rebound': correctRebound ?? false,
          'total_grade': totalGrade,
          'session_start': DateTime.now().toIso8601String(),
          'session_duration': 0,
        };

        final response = await NetworkService.post(
          '/sessions/summary',
          sessionData,
          requiresAuth: true,
        );

        if (response['success'] == true) {
          _showSnackbar("Data saved successfully.");
        } else {
          _showSnackbar(response['message'] ?? 'Failed to save session data.');
        }
      } catch (e) {
        _showSnackbar("Error saving session data: ${e.toString()}");
      }
    }

    /// **🔔 Show Snackbar**
    void _showSnackbar(String message) {
      if (!_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    @override
    Widget build(BuildContext context) {
      super.build(context); // ✅ must call this

      return Container(
        color: const Color(0xFFEDF4F9),
        child: StreamBuilder<Map<String, dynamic>>(
          stream: widget.dataStream,
          builder: (context, snapshot) {
            final data = snapshot.data ?? {};

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const PatientVitalsCard(), // reuse same widget
                  const SizedBox(height: 16),
                  CprMetricsCard(
                    frequency: (data['frequency'] as num?)?.toDouble() ?? 0,
                    depth: (data['weight'] as num?)?.toDouble() ?? 0,
                  ),
                  const SizedBox(height: 16),
                  // Custom version of UserVitalsCard that replaces simulate button with save/past sessions
                  _trainingUserVitalsCard(),
                ],
              ),
            );
          },
        ),
      );
    }

    Widget _trainingUserVitalsCard() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your Vitals",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Color(0xFF194E9D),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(13),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${userHeartRate ?? "N/A"} bpm",
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                          color: Color(0xFF4D4A4A),
                        ),
                      ),
                      const Text(
                        "HEART RATE",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF727272),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${userTemperatureRate?.toStringAsFixed(1) ?? "N/A"}°C",
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                          color: Color(0xFF4D4A4A),
                        ),
                      ),
                      const Text(
                        "TEMPERATURE",
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF727272),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _saveSessionData,
            icon: const Icon(Icons.save),
            label: const Text("Save Session"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PastSessionsScreen(
                    dataStream: widget.dataStream,
                    decryptedDataHandler: widget.decryptedDataHandler,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.history),
            label: const Text("View Past Sessions"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      );
    }
  }