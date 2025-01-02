import 'dart:async';
import 'package:flutter/material.dart';
import '../services/mock_ble_data.dart';
import '../services/network_service.dart';
import 'past_sessions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MockBLEData _mockBLEData = MockBLEData();

  bool isSessionActive = false;
  int totalCompressions = 0;
  int correctDepth = 0;
  int correctFrequency = 0;
  double correctAngle = 0.0;
  DateTime? sessionStartTime;
  Timer? sessionTimer;
  late Stream<Map<String, dynamic>> sensorStream;
  StreamSubscription<Map<String, dynamic>>? sensorSubscription;

  @override
  void initState() {
    super.initState();
    sensorStream = _mockBLEData.generateSensorData();
  }

  void _startSession() {
    setState(() {
      isSessionActive = true;
      totalCompressions = 0;
      correctDepth = 0;
      correctFrequency = 0;
      correctAngle = 0.0; // Reset angle
      sessionStartTime = DateTime.now();
    });

    sessionTimer?.cancel();
    sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {}); // Update UI every second
    });

    sensorSubscription?.cancel(); // Cancel any previous subscription
    sensorStream = _mockBLEData.generateSensorData(); // Reinitialize the stream
    sensorSubscription = sensorStream.listen((data) {
      setState(() {
        totalCompressions++;
        if (data['depth'] >= 5 && data['depth'] <= 6) correctDepth++;
        if (data['frequency'] >= 100 && data['frequency'] <= 120) correctFrequency++;
        if (data['angle'] >= 0 && data['angle'] <= 15) correctAngle += 0.2;
      });
    });
  }

  Future<void> _stopSession() async {
    sessionTimer?.cancel();
    sensorSubscription?.cancel();

    final sessionDuration = DateTime.now().difference(sessionStartTime!);

    final summary = {
      "compression_count": totalCompressions,
      "correct_depth": correctDepth,
      "correct_frequency": correctFrequency,
      "correct_angle": correctAngle, // Send as double
      "session_duration": sessionDuration.inSeconds,
    };

    try {
      await NetworkService.post('/cpr/summary', summary, requiresAuth: true);
      print("Session summary sent successfully");
    } catch (e) {
      print("Failed to send summary: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save session: $e')),
      );
    }

    setState(() {
      isSessionActive = false;
    });

    _showSessionResults(summary);
  }

  void _showSessionResults(Map<String, dynamic> summary) {
    // Safely handle correct_angle to ensure it's treated as a double
    final double correctAngleValue = double.tryParse(summary['correct_angle'].toString()) ?? 0.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Results'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Total Compressions: ${summary['compression_count']}'),
            Text('Correct Depth: ${summary['correct_depth']}'),
            Text('Correct Frequency: ${summary['correct_frequency']}'),
            Text('Correct Angle: ${correctAngleValue.toStringAsFixed(2)} seconds'),
            Text('Session Duration: ${summary['session_duration']} seconds'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    await NetworkService.removeToken(); // Clear stored JWT and user ID
    Navigator.pushReplacementNamed(context, '/login'); // Navigate to login screen
  }

  @override
  void dispose() {
    sensorSubscription?.cancel();
    sessionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CPR Mock Data'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout, // Call logout function
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Total Compressions: $totalCompressions'),
            Text('Correct Depth: $correctDepth'),
            Text('Correct Frequency: $correctFrequency'),
            Text('Correct Angle: ${correctAngle.toStringAsFixed(2)} seconds'),
            Text(
              'Session Duration: ${isSessionActive && sessionStartTime != null ? DateTime.now().difference(sessionStartTime!).inSeconds : 0} seconds',
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isSessionActive ? _stopSession : _startSession,
              child: Text(isSessionActive ? 'Stop Session' : 'Start Session'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PastSessionsScreen()),
              ),
              child: const Text('View Past Sessions'),
            ),
          ],
        ),
      ),
    );
  }
}
