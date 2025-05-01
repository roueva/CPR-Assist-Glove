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
      return Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMetricBox('Patient Heart Rate', '${patientHeartRate ?? "N/A"} bpm'),
                              _buildMetricBox('Patient Temperature', '${patientTemperature?.toStringAsFixed(1) ?? "N/A"} °C'),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.black),
                            ),
                            child: Table(
                              columnWidths: const {0: FlexColumnWidth(), 1: FlexColumnWidth()},
                              border: TableBorder.symmetric(
                                inside: const BorderSide(color: Colors.black38),
                              ),
                              children: [
                                _buildTableRow('Total Compressions', '$compressionCount'),
                                _buildTableRow('Correct Frequency', '$correctFrequency'),
                                _buildTableRow('Correct Weight', '$correctWeight'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          Text(
                            'Total Grade: ${totalGrade.toStringAsFixed(2)}%',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildMetricBox('User Heart Rate', '${userHeartRate ?? "N/A"} bpm'),
                              _buildMetricBox('User Temperature', '${userTemperatureRate?.toStringAsFixed(1) ?? "N/A"} °C'),
                            ],
                          ),
                          const SizedBox(height: 20),

                          ElevatedButton(
                            onPressed: _saveSessionData,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                            child: const Text('Save Session'),
                          ),

                          ElevatedButton.icon(
                            onPressed: () {
                              if (globalBLEConnection.isConnected()) {
                                widget.onTabTapped(1); // ✅ Navigate to LiveCPR tab
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('No active Bluetooth connection'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },

                            icon: const Icon(Icons.monitor_heart),
                            label: const Text("View Live CPR Feedback"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              textStyle: const TextStyle(fontSize: 18),
                            ),
                          ),


                          const SizedBox(height: 10),

                          TextButton(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (context) =>
                                    PastSessionsScreen(
                                      dataStream: widget.dataStream,
                                      decryptedDataHandler: widget.decryptedDataHandler,
                                    ),
                              ));
                            },
                            child: const Text(
                              'View Past Sessions',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
    }

    /// 📦 **Reusable UI Box for Metrics**
    Widget _buildMetricBox(String title, String value) {
      return Expanded( // ✅ Ensures the boxes take available space but don't force overflow
        child: Container(
          height: 90, // 🔹 Reduced height slightly to prevent overflow
          margin: const EdgeInsets.symmetric(horizontal: 8), // 🔹 Adds space between boxes
          padding: const EdgeInsets.all(10), // 🔹 Ensures content doesn't touch edges
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(12), // ✅ Rounded corners
            border: Border.all(color: Colors.black),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), // 🔹 Smaller font
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 5),
              Text(
                value,
                style: const TextStyle(fontSize: 14), // 🔹 Smaller font
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    /// 📊 **Reusable Table Row for Compression Metrics**
    TableRow _buildTableRow(String metric, String value) {
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(metric, style: const TextStyle(fontSize: 16)),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }
  }