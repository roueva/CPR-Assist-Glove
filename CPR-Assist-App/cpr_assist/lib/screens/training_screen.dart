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
                  GradeCard(
                    totalCompressions: compressionCount,
                    correctFrequency: correctFrequency,
                    correctWeight: correctWeight,
                    totalGrade: totalGrade,
                    correctAngle: 7,         // You can pass a real value
                    correctRebound: 6,       // You can pass a real value
                  ),
                  const SizedBox(height: 16),
                  const UserVitalsCard(),
                  const SizedBox(height: 16),
                  _pastSessionsButton(),

                ],
              ),
            );
          },
        ),
      );
    }

    Widget _pastSessionsButton() {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                "View Past Sessions",
                style: TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.black),
            ],
          ),
        ),
      );
    }
  }

  class GradeCard extends StatelessWidget {
    final int totalCompressions;
    final int correctFrequency;
    final int correctWeight;
    final int correctAngle;        // NEW
    final int correctRebound;      // NEW
    final double totalGrade;

    const GradeCard({
      super.key,
      required this.totalCompressions,
      required this.correctFrequency,
      required this.correctWeight,
      required this.correctAngle,
      required this.correctRebound,
      required this.totalGrade,
    });

    @override
    Widget build(BuildContext context) {
      return Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF194E9D), Color(0xFF355CA9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
          child: Column(
            children: [
              // 🔵 Circular Grade
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: CircularProgressIndicator(
                      value: totalGrade / 100,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  Text(
                    "${totalGrade.toStringAsFixed(0)}%",
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "TOTAL GRADE",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),

              // 🟦 TOTAL COMPRESSIONS Box spanning two columns
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      "$totalCompressions",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "TOTAL COMPRESSIONS",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // 🔷 Stats Grid
              GridView.count(
                shrinkWrap: true,
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.8,
                children: [
                  _statBox("CORRECT FREQUENCY", correctFrequency),
                  _statBox("CORRECT WEIGHT", correctWeight),
                  _statBox("CORRECT ANGLE", correctAngle),
                  _statBox("CORRECT REBOUND", correctRebound),
                ],
              ),
            ],
          ),
      );
    }

    Widget _statBox(String label, int value) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "$value",
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            )
          ],
        ),
      );
    }
  }
