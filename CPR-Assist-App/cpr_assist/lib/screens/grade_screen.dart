import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/decrypted_data.dart';
import '../services/training/training_session_service.dart';
import '../widgets/grade_card.dart';
import 'login_screen.dart';
import 'past_sessions_screen.dart';

class TrainingScreen extends ConsumerStatefulWidget {
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

class _TrainingScreenState extends ConsumerState<TrainingScreen>
    with AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  TrainingSessionData? _currentSessionData;
  double _totalGrade = 0.0;
  DateTime? _sessionStartTime;
  StreamSubscription<Map<String, dynamic>>? _dataSubscription;

  late final TrainingSessionService _trainingService;

  @override
  void initState() {
    super.initState();

    _trainingService = TrainingSessionService(
      ref.read(networkServiceProvider),
    );

    _listenToDataStream();
    _loadCachedEndPing();
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _loadCachedEndPing() {
    final cached = widget.decryptedDataHandler.getLastEndPingData();
    if (cached != null && mounted) {
      _handleEndPing(cached);
    }
  }

  void _listenToDataStream() {
    _dataSubscription = widget.dataStream.listen((data) {
      if (!mounted) return;

      if (data['startPing'] == true) {
        setState(() {
          _sessionStartTime = DateTime.now();
        });
      }

      if (data['endPing'] == true) {
        _handleEndPing(data);
      }
    });
  }

  void _handleEndPing(Map<String, dynamic> data) {
    final sessionData = TrainingSessionData(
      totalCompressions: data['totalCompressions'] ?? 0,
      correctDepth: data['correctDepth'] ?? 0,
      correctFrequency: data['correctFrequency'] ?? 0,
      correctRecoil: data['correctRecoil'] ?? 0,
      depthRateCombo: data['depthRateCombo'] ?? 0,
      averageDepth: data['depth'] ?? 0.0,
      averageFrequency: data['frequency'] ?? 0.0,
      sessionDurationSeconds: (data['sessionDuration'] as Duration?)?.inSeconds ?? 0,
      sessionStart: _sessionStartTime ?? DateTime.now(),
      patientHeartRate: data['patientHeartRate'],
      patientTemperature: data['patientTemperature'],
      userHeartRate: data['userHeartRate'],
      userTemperature: data['userTemperature'],
    );

    setState(() {
      _currentSessionData = sessionData;
      _totalGrade = _trainingService.calculateGrade(sessionData);
    });

    _saveSessionIfLoggedIn();
  }

  Future<void> _saveSessionIfLoggedIn() async {
    if (_currentSessionData == null) return;

    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;

    if (!isLoggedIn) {
      // Redirect to login
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            dataStream: widget.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
      );

      if (loggedIn == true && mounted) {
        _saveSessionIfLoggedIn(); // Retry after login
      }
      return;
    }

    final success = await _trainingService.saveSession(_currentSessionData!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Session saved successfully' : 'Failed to save session'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: const Color(0xFFEDF4F9),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_currentSessionData != null)
              GradeCard(
                sessionData: _currentSessionData!,
                totalGrade: _totalGrade,
              )
            else
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'Complete a training session to see your results',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _buildPastSessionsButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPastSessionsButton() {
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
              builder: (_) => PastSessionsScreen(
                dataStream: widget.dataStream,
                decryptedDataHandler: widget.decryptedDataHandler,
              ),
            ),
          );
        },
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
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