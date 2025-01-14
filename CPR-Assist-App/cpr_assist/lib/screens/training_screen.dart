import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/account_menu.dart';
import 'home_screen.dart';
import '../services/decrypted_data.dart';
import 'login_screen.dart';

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
  int totalCompressions = 0;
  int correctWeightCompressions = 0;
  int correctFrequencyCompressions = 0;
  double totalGrade = 0.0;
  late StreamSubscription<Map<String, dynamic>> dataSubscription;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (!isLoggedIn) {
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
          totalCompressions = data['totalCompressions'] ?? totalCompressions;
          correctWeightCompressions = data['correctWeightCompressions'] ?? correctWeightCompressions;
          correctFrequencyCompressions = data['correctFrequencyCompressions'] ?? correctFrequencyCompressions;
          totalGrade = data['totalGrade'] ?? totalGrade;
        });
      },
      onError: (error) {
        setState(() {
          connectionStatus = "Error receiving data: $error";
        });
      },
      onDone: () {
        setState(() {
          connectionStatus = "Disconnected";
        });
      },
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
            Text('Total Compressions: $totalCompressions'),
            Text('Correct Weight Compressions: $correctWeightCompressions'),
            Text('Correct Frequency Compressions: $correctFrequencyCompressions'),
            Text('Total Grade: ${totalGrade.toStringAsFixed(2)}%'),
          ],
        ),
      ),
    );
  }
}
