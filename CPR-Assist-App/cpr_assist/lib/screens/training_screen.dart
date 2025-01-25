import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/account_menu.dart';
import 'home_screen.dart';
import '../services/decrypted_data.dart';
import 'login_screen.dart';
import 'past_sessions_screen.dart';
import '../services/network_service.dart';

class TrainingScreen extends StatefulWidget {
  final Stream<Map<String, dynamic>> dataStream;
  final DecryptedData decryptedDataHandler;

  const TrainingScreen({
    super.key,
    required this.dataStream,
    required this.decryptedDataHandler,
  });

  @override
  _TrainingScreenState createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  String connectionStatus = "Disconnected";
  int compressionCount = 0; // Updated naming for clarity
  int correctWeight = 0; // Correct depth
  int correctFrequency = 0;
  int? patientHeartRate;
  double? patientTemperature;
  int? userHeartRate;
  double? userTemperatureRate;
  bool? correctRebound;
  double totalGrade = 0.0;
  late StreamSubscription<Map<String, dynamic>> dataSubscription;
  bool? isLoggedIn;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    if (isLoggedIn == null) {
      final prefs = await SharedPreferences.getInstance();
      isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    }

    if (!isLoggedIn!) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => LoginScreen(
            dataStream: widget.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
            (route) => false,
      );
    } else {
      _startReceivingData();
    }
  }

  void _startReceivingData() {
    setState(() {
      connectionStatus = "Connected";
    });

    dataSubscription = widget.dataStream.listen(
          (data) {
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
        setState(() {
          connectionStatus = "Error: $error";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data stream error: $error')),
        );
      },
      onDone: () {
        setState(() {
          connectionStatus = "Disconnected";
        });
      },
    );
  }

  Future<void> _saveSessionData() async {
    try {
      final sessionData = {
        'compression_count': compressionCount,
        'correct_depth': correctWeight,
        'correct_frequency': correctFrequency,
        'correct_angle': 0.0,
        'patient_heart_rate': (patientHeartRate ?? 0).toInt(),
        'patient_temperature': double.parse((patientTemperature ?? 0.0).toStringAsFixed(1)),
        'user_heart_rate': (userHeartRate ?? 0).toInt(),
        'user_temperature_rate': double.parse((userTemperatureRate ?? 0.0).toStringAsFixed(1)),
        'correct_rebound': correctRebound ?? false,
        'total_grade': double.parse(totalGrade.toStringAsFixed(2)),
        'session_start': DateTime.now().toUtc().toIso8601String(),
        'session_duration': 0, // Placeholder
      };

      print('Sanitized Session Data: $sessionData');

      final response = await NetworkService.post(
        '/sessions/summary',
        sessionData,
        requiresAuth: true,
      );

      if (response['success'] == true) {
        _showSuccessMessage(); // Show success message
      } else {
        throw Exception(response['message'] ?? 'Failed to save session data');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving session data: $e')),
      );
    }
  }

  void _showSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('Data Saved Successfully!'),
            Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 3),
      ),
    );
  }


  @override
  void dispose() {
    dataSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training Mode'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                decryptedDataHandler: widget.decryptedDataHandler,
              ),
            ),
          ),
        ),
        actions: [
          AccountMenu(decryptedDataHandler: widget.decryptedDataHandler),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Connection Status: $connectionStatus'),
            const SizedBox(height: 20),
            Text('Total Compressions: $compressionCount'),
            Text('Correct Weight Compressions: $correctWeight'),
            Text('Correct Frequency Compressions: $correctFrequency'),
            Text('Patient Heart Rate: ${patientHeartRate?.toString() ?? "N/A"} bpm'),
            Text('Patient Temperature: ${patientTemperature?.toStringAsFixed(1) ?? "N/A"} °C'),
            Text('User Heart Rate: ${userHeartRate?.toString() ?? "N/A"} bpm'),
            Text('User Temperature: ${userTemperatureRate?.toStringAsFixed(1) ?? "N/A"} °C'),
            Text('Correct Rebound: ${correctRebound != null ? (correctRebound! ? "Yes" : "No") : "N/A"}'),
            Text('Total Grade: ${totalGrade.toStringAsFixed(2)}%'),
            const SizedBox(height: 40),
            if (connectionStatus == "Disconnected")
              ElevatedButton(
                onPressed: _startReceivingData,
                child: const Text('Retry Connection'),
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
            const SizedBox(height: 20),
            TextButton(
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
              child: const Text(
                'View Past Sessions',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
