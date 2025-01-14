import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/decrypted_data.dart'; // Import DecryptedData

class EmergencyScreen extends StatefulWidget {
  final Stream<Map<String, dynamic>> dataStream;
  final DecryptedData decryptedDataHandler; // DecryptedData handler

  const EmergencyScreen({
    super.key,
    required this.dataStream,
    required this.decryptedDataHandler, // Initialize DecryptedData handler
  });

  @override
  _EmergencyScreenState createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  int totalCompressions = 0;
  int correctDepth = 0;
  int correctFrequency = 0;
  double correctAngle = 0.0;

  late StreamSubscription<Map<String, dynamic>> dataSubscription;

  @override
  void initState() {
    super.initState();
    _startReceivingData();
  }

  void _startReceivingData() {
    dataSubscription = widget.dataStream.listen(
          (data) {
        setState(() {
          totalCompressions = data['depth'] ?? totalCompressions;
          correctDepth = data['frequency'] ?? correctDepth;
          correctFrequency = data['angle'] ?? correctFrequency;
          correctAngle = data['correct_angle_duration'] ?? correctAngle;
        });
      },
      onError: (error) {
        print('Error receiving data: $error');
      },
    );
  }

  void _prepareEmergencyCall() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Emergency Services'),
        content: const Text('Do you want to call 112?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse('tel:112')),
            child: const Text('Call'),
          ),
        ],
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
        title: const Text('Emergency Mode'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Connection Status: Connected'),
            const SizedBox(height: 20),
            Text('Total Compressions: $totalCompressions'),
            Text('Correct Depth: $correctDepth'),
            Text('Correct Frequency: $correctFrequency'),
            Text('Correct Angle: ${correctAngle.toStringAsFixed(2)}'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _prepareEmergencyCall,
              child: const Text('Call Emergency Services'),
            ),
          ],
        ),
      ),
    );
  }
}
