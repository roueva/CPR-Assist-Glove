import '../network_service.dart';

class TrainingSessionService {
  final NetworkService _networkService;

  TrainingSessionService(this._networkService);

  Future<bool> saveSession(TrainingSessionData data) async {
    try {
      final response = await _networkService.post(
        '/sessions/summary',
        data.toJson(),
        requiresAuth: true,
      );

      return response['success'] == true;
    } catch (e) {
      print("❌ Error saving session: $e");
      return false;
    }
  }
  double calculateGrade(TrainingSessionData data) => data.grade;
}

class TrainingSessionData {
  final int totalCompressions;
  final int correctDepth;
  final int correctFrequency;
  final int correctRecoil;
  final int depthRateCombo;
  final double averageDepth;
  final double averageFrequency;
  final int sessionDurationSeconds;
  final DateTime sessionStart;
  final int? patientHeartRate;
  final double? patientTemperature;
  final int? userHeartRate;
  final double? userTemperature;

  TrainingSessionData({
    required this.totalCompressions,
    required this.correctDepth,
    required this.correctFrequency,
    required this.correctRecoil,
    required this.depthRateCombo,
    required this.averageDepth,
    required this.averageFrequency,
    required this.sessionDurationSeconds,
    required this.sessionStart,
    this.patientHeartRate,
    this.patientTemperature,
    this.userHeartRate,
    this.userTemperature,
  });

  Map<String, dynamic> toJson() {
    return {
      'compression_count': totalCompressions,
      'correct_depth': correctDepth,
      'correct_frequency': correctFrequency,
      'correct_recoil': correctRecoil,
      'depth_rate_combo': depthRateCombo,
      'average_depth': averageDepth,
      'average_frequency': averageFrequency,
      'correct_rebound': false,
      'patient_heart_rate': patientHeartRate,
      'patient_temperature': patientTemperature,
      'user_heart_rate': userHeartRate,
      'user_temperature': userTemperature,
      'session_duration': sessionDurationSeconds,
      'total_grade': grade,
      'session_start': sessionStart.toIso8601String(),
    };
  }
  double get grade {
    if (totalCompressions == 0) return 0.0;
    final score = (correctDepth + correctFrequency + correctRecoil + depthRateCombo) /
        (4 * totalCompressions) * 100;
    return score.clamp(0, 100);
  }
}