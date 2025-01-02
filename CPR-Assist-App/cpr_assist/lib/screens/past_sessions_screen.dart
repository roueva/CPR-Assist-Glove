import 'package:flutter/material.dart';
import '../services/network_service.dart';

class PastSessionsScreen extends StatefulWidget {
  const PastSessionsScreen({super.key});

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
      final response = await NetworkService.get('/auth/sessions', requiresAuth: true);

      // Extract the 'data' field which contains the list of sessions
      if (response['success'] == true && response['data'] is List) {
        setState(() {
          sessionSummaries = response['data'];
          isLoading = false;
        });
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to fetch session summaries: $e';
        isLoading = false;
      });
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

                // Safely parse correct_angle
                final double correctAngle = double.tryParse(
                    session['correct_angle'].toString()) ??
                    0.0;

                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: ListTile(
                    title: Text('Session ${sessionSummaries.length - index}'), // Reverse numbering
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Compressions: ${session['compression_count']}'),
                        Text('Correct Depth: ${session['correct_depth']}'),
                        Text('Correct Frequency: ${session['correct_frequency']}'),
                        Text('Correct Angle: ${correctAngle.toStringAsFixed(2)} seconds'),
                        Text('Duration: ${session['session_duration']} seconds'),
                        Text('Date: ${session['session_start']}'),
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
