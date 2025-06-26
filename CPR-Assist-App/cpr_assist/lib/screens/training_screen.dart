  import 'dart:async';
  import 'package:flutter/material.dart';
  import 'package:flutter_blue_plus/flutter_blue_plus.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import '../main.dart';
  import '../services/decrypted_data.dart';
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
    int correctDepth = 0;
    int correctFrequency = 0;
    int? patientHeartRate;
    double? patientTemperature;
    int? userHeartRate;
    double? userTemperatureRate;
    int correctRecoil = 0;
    double totalGrade = 0.0;
    int depthRateCombo = 0;
    double latestDepth = 0.0;
    double latestFrequency = 0.0;
    Duration sessionDuration = Duration.zero;
    DateTime? sessionStartTime;
    late StreamSubscription<Map<String, dynamic>> dataSubscription;
    bool? isLoggedIn;
    bool _isDisposed = false;

    @override
    void initState() {
      super.initState();
      _startReceivingData();

      final cached = widget.decryptedDataHandler.getLastEndPingData();
      if (cached != null && !_isDisposed) {
        _handleEndPing(cached);
      }


      // ✅ Listen to BLE Status
      globalBLEConnection.adapterStateStream.listen((state) {
        if (mounted) {
          setState(() {
            connectionStatus = (state == BluetoothAdapterState.on && globalBLEConnection.isConnected)
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

    void _handleEndPing(Map<String, dynamic> data) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          setState(() {
            compressionCount = data['totalCompressions'] ?? 0;
            correctDepth = data['correctDepth'] ?? 0;
            correctFrequency = data['correctFrequency'] ?? 0;
            correctRecoil = data['correctRecoil'] ?? 0;
            depthRateCombo = data['depthRateCombo'] ?? 0;
            sessionDuration = data['sessionDuration'] ?? Duration.zero;
            latestDepth = data['depth'] ?? 0.0;
            latestFrequency = data['frequency'] ?? 0.0;
            userHeartRate = data['userHeartRate'] ?? 0;
            userTemperatureRate = data['userTemperature'] ?? 0.0;
            patientHeartRate = data['patientHeartRate'] ?? 0;
            patientTemperature = data['patientTemperature'] ?? 0.0;

            totalGrade = _calculateTotalGrade(
              depth: correctDepth,
              freq: correctFrequency,
              recoil: correctRecoil,
              combo: depthRateCombo,
              total: compressionCount,
            );
          });
          _saveSessionData();
        }
      });
    }

    void _startReceivingData() {
      if (_isDisposed) return;

      dataSubscription = widget.dataStream.listen((data) {
        if (_isDisposed) return;

        final isStartPing = data['startPing'] == true;
        final isEndPing = data['endPing'] == true;

        if (isStartPing) {
          sessionStartTime = DateTime.now(); // ✅ Save timestamp when session starts
        }

        if (isEndPing) {
          _handleEndPing(data); // ✅ Call this to update all fields
        }
      });
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
          'correct_depth': correctDepth,
          'correct_frequency': correctFrequency,
          'correct_angle': 0.0,
          'patient_heart_rate': patientHeartRate ?? 0,
          'patient_temperature': patientTemperature ?? 0.0,
          'user_heart_rate': userHeartRate ?? 0,
          'user_temperature_rate': userTemperatureRate ?? 0.0,
          'correct_recoil': correctRecoil,
          'average_depth': latestDepth,
          'average_frequency': latestFrequency,
          'session_duration': sessionDuration.inSeconds,
          'total_grade': totalGrade,
          'session_start': (sessionStartTime ?? DateTime.now()).toIso8601String(),
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

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                GradeCard(
                totalCompressions: compressionCount,
                correctFrequency: correctFrequency,
                correctDepth: correctDepth,
                  correctCombo: depthRateCombo,
                  correctRecoil: correctRecoil,
                totalGrade: totalGrade,
              ),
                  const SizedBox(height: 16),
                  // const UserVitalsCard(heartRate: '0',),
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

  double _calculateTotalGrade({
    required int depth,
    required int freq,
    required int recoil,
    required int combo,
    required int total,
  }) {
    if (total == 0) return 0.0;
    double score =
        (depth + freq + recoil + combo) / (4 * total) * 100;
    return score.clamp(0, 100);
  }

  class GradeCard extends StatelessWidget {
    final int totalCompressions;
    final int correctFrequency;
    final int correctDepth;
    final int correctCombo;
    final int correctRecoil;
    final double totalGrade;

    const GradeCard({
      super.key,
      required this.totalCompressions,
      required this.correctFrequency,
      required this.correctDepth,
      required this.correctCombo,
      required this.correctRecoil,
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
                  _statBox("CORRECT DEPTH", correctDepth),
                  _statBox("FREQUENCY AND DEPTH", correctCombo),
                  _statBox("CORRECT RECOIL", correctRecoil),
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
