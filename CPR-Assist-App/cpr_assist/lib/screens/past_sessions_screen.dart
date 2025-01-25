import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/decrypted_data.dart';
import '../services/network_service.dart';
import 'login_screen.dart';

class PastSessionsScreen extends StatefulWidget {
  final Stream<Map<String, dynamic>> dataStream;
  final DecryptedData decryptedDataHandler;

  const PastSessionsScreen({
    super.key,
    required this.dataStream,
    required this.decryptedDataHandler,
  });

  @override
  _PastSessionsScreenState createState() => _PastSessionsScreenState();
}

class _PastSessionsScreenState extends State<PastSessionsScreen> {
  List<dynamic> sessionSummaries = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchSessionSummaries();
  }

  Future<void> fetchSessionSummaries() async {
    try {
      print('Fetching session summaries...');
      final response = await NetworkService.get('/sessions/summaries', requiresAuth: true);
      print('Response: $response');

      if (response['success'] == true && response['data'] is List) {
        setState(() {
          sessionSummaries = response['data'];
          isLoading = false;
        });
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      print('Error fetching session summaries: $e');
      if (e.toString().contains('401')) {
        await NetworkService.removeToken();
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
        setState(() {
          errorMessage = 'Failed to fetch session summaries: $e';
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Past Session Summaries')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(child: Text(errorMessage!))
          : sessionSummaries.isEmpty
          ? const Center(child: Text('No past sessions found.'))
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Total Sessions: ${sessionSummaries.length}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: sessionSummaries.length,
              itemBuilder: (context, index) {
                final session = sessionSummaries[index];
                final formattedDate = DateFormat.yMMMd()
                    .add_jm()
                    .format(DateTime.parse(session['session_start']));
                final correctAngle = double.tryParse(
                    session['correct_angle'].toString()) ??
                    0.0;

                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: ListTile(
                    title: Text('Session ${sessionSummaries.length - index}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compressions: ${session['compression_count'] ?? "N/A"}'),
                        Text('Correct Depth: ${session['correct_depth'] ?? "N/A"}'),
                        Text('Correct Frequency: ${session['correct_frequency'] ?? "N/A"}'),
                        Text('Correct Angle: ${correctAngle.toStringAsFixed(2)}°'),
                        if (session['correct_rebound'] != null)
                          Text(
                              'Correct Rebound: ${session['correct_rebound'] ? "Yes" : "No"}'),
                        if (session['patient_heart_rate'] != null)
                          Text('Patient Heart Rate: ${session['patient_heart_rate']} bpm'),
                        if (session['patient_temperature'] != null)
                          Text('Patient Temperature: ${session['patient_temperature']} °C'),
                        if (session['user_heart_rate'] != null)
                          Text('User Heart Rate: ${session['user_heart_rate']} bpm'),
                        if (session['user_temperature_rate'] != null)
                          Text(
                              'User Temperature: ${session['user_temperature_rate']} °C'),
                        Text('Duration: ${session['session_duration'] ?? "N/A"} seconds'),
                        Text('Date: $formattedDate'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
