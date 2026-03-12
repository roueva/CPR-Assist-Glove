import 'package:flutter/cupertino.dart';

import '../../../services/network/network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SERVICE
// Single source of truth for all session data: model, save, fetch, grade calc.
// Used by: grade_screen.dart, past_sessions_screen.dart, leaderboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

class SessionService {
  final NetworkService _network;

  SessionService(this._network);

  /// Fetch all session summaries for the logged-in user.
  Future<List<SessionSummary>> fetchSummaries() async {
    final response = await _network.get(
      '/sessions/summaries',
      requiresAuth: true,
    );

    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to fetch sessions');
    }

    final List<dynamic> raw = response['data'] ?? [];
    return raw.map((json) => SessionSummary.fromJson(json)).toList();
  }

  /// Save a completed session to the backend.
  Future<bool> saveSummary(SessionSummary session) async {
    try {
      await _network.post(
        '/sessions/summary',
        session.toJson(),
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('saveSummary failed: $e');
      return false;
    }
  }

  // ── Grade calculation ──────────────────────────────────────────────────────
  // Single place for grading logic — used by grade_screen after a session ends.

  /// Calculates a 0–100 grade from a completed session.
  double calculateGrade(SessionSummary session) {
    if (session.compressionCount == 0) return 0;

    final depthScore     = session.correctDepth     / session.compressionCount;
    final frequencyScore = session.correctFrequency / session.compressionCount;
    final recoilScore    = session.correctRecoil    / session.compressionCount;
    final comboScore     = session.depthRateCombo   / session.compressionCount;

    // Weighted: depth 35%, frequency 30%, recoil 20%, combo bonus 15%
    return ((depthScore * 35) +
        (frequencyScore * 30) +
        (recoilScore    * 20) +
        (comboScore     * 15))
        .clamp(0.0, 100.0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SUMMARY MODEL
// Single model used everywhere: BLE end-ping → grade screen → backend → history.
// ─────────────────────────────────────────────────────────────────────────────

class SessionSummary {
  final int? id;
  final int compressionCount;
  final int correctDepth;
  final int correctFrequency;
  final int correctRecoil;
  final int depthRateCombo;
  final double averageDepth;
  final double averageFrequency;
  final bool correctRebound;
  final int? patientHeartRate;
  final double? patientTemperature;
  final int? userHeartRate;
  final double? userTemperature;
  final int sessionDuration;     // seconds
  final double totalGrade;       // 0–100
  final DateTime? sessionStart;
  final DateTime? sessionEnd;

  const SessionSummary({
    this.id,
    required this.compressionCount,
    required this.correctDepth,
    required this.correctFrequency,
    this.correctRecoil = 0,
    this.depthRateCombo = 0,
    this.averageDepth = 0.0,
    this.averageFrequency = 0.0,
    this.correctRebound = false,
    this.patientHeartRate,
    this.patientTemperature,
    this.userHeartRate,
    this.userTemperature,
    required this.sessionDuration,
    this.totalGrade = 0.0,
    this.sessionStart,
    this.sessionEnd,
  });

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// "3:42"
  String get durationFormatted {
    final m = sessionDuration ~/ 60;
    final s = sessionDuration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// "8 Mar 2026"
  String get dateFormatted {
    if (sessionStart == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${sessionStart!.day} ${months[sessionStart!.month - 1]} ${sessionStart!.year}';
  }

  /// "8 Mar 2026 • 14:35"
  String get dateTimeFormatted {
    if (sessionStart == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = sessionStart!.hour.toString().padLeft(2, '0');
    final m = sessionStart!.minute.toString().padLeft(2, '0');
    return '${sessionStart!.day} ${months[sessionStart!.month - 1]} ${sessionStart!.year} • $h:$m';
  }

  // ── Build from BLE end-ping data ───────────────────────────────────────────

  /// Constructs a SessionSummary directly from the raw BLE data map
  /// received on endPing. Grade is calculated separately via SessionService.
  factory SessionSummary.fromBleData(
      Map<String, dynamic> data, {
        required DateTime sessionStart,
        required int sessionDuration,
        required double totalGrade,
      }) {
    return SessionSummary(
      compressionCount:   data['totalCompressions']  as int?    ?? 0,
      correctDepth:       data['correctDepth']       as int?    ?? 0,
      correctFrequency:   data['correctFrequency']   as int?    ?? 0,
      correctRecoil:      data['correctRecoil']      as int?    ?? 0,
      depthRateCombo:     data['depthRateCombo']     as int?    ?? 0,
      averageDepth:       (data['depth']             as num?)?.toDouble() ?? 0.0,
      averageFrequency:   (data['frequency']         as num?)?.toDouble() ?? 0.0,
      patientHeartRate:   data['patientHeartRate']   as int?,
      patientTemperature: (data['patientTemperature'] as num?)?.toDouble(),
      userHeartRate:      data['userHeartRate']      as int?,
      userTemperature:    (data['userTemperature']   as num?)?.toDouble(),
      sessionDuration: sessionDuration,
      totalGrade:         totalGrade,
      sessionStart:       sessionStart,
    );
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id:                 json['id'] as int?,
      compressionCount:   (json['compression_count']  as num).toInt(),
      correctDepth:       (json['correct_depth']       as num).toInt(),
      correctFrequency:   (json['correct_frequency']   as num).toInt(),
      correctRecoil:      (json['correct_recoil']      as num?)?.toInt()    ?? 0,
      depthRateCombo:     (json['depth_rate_combo']    as num?)?.toInt()    ?? 0,
      averageDepth:       (json['average_depth']       as num?)?.toDouble() ?? 0.0,
      averageFrequency:   (json['average_frequency']   as num?)?.toDouble() ?? 0.0,
      correctRebound:     json['correct_rebound']      as bool? ?? false,
      patientHeartRate:   (json['patient_heart_rate']  as num?)?.toInt(),
      patientTemperature: (json['patient_temperature'] as num?)?.toDouble(),
      userHeartRate:      (json['user_heart_rate']     as num?)?.toInt(),
      userTemperature:    (json['user_temperature']    as num?)?.toDouble(),
      sessionDuration:    (json['session_duration']    as num).toInt(),
      totalGrade:         (json['total_grade']         as num?)?.toDouble() ?? 0.0,
      sessionStart: json['session_start'] != null
          ? DateTime.tryParse(json['session_start'])
          : null,
      sessionEnd: json['session_end'] != null
          ? DateTime.tryParse(json['session_end'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'compression_count':  compressionCount,
    'correct_depth':      correctDepth,
    'correct_frequency':  correctFrequency,
    'correct_recoil':     correctRecoil,
    'depth_rate_combo':   depthRateCombo,
    'average_depth':      averageDepth,
    'average_frequency':  averageFrequency,
    'correct_rebound':    correctRebound,
    if (patientHeartRate   != null) 'patient_heart_rate':   patientHeartRate,
    if (patientTemperature != null) 'patient_temperature':  patientTemperature,
    if (userHeartRate      != null) 'user_heart_rate':      userHeartRate,
    if (userTemperature    != null) 'user_temperature':     userTemperature,
    'session_duration':   sessionDuration,
    'total_grade':        totalGrade,
    if (sessionStart != null) 'session_start': sessionStart!.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// USER STATS — computed client-side from session list
// ─────────────────────────────────────────────────────────────────────────────

class UserStats {
  final int sessionCount;
  final double averageGrade;
  final double bestGrade;
  final SessionSummary? bestSession;

  const UserStats({
    required this.sessionCount,
    required this.averageGrade,
    required this.bestGrade,
    this.bestSession,
  });

  factory UserStats.fromSessions(List<SessionSummary> sessions) {
    if (sessions.isEmpty) {
      return const UserStats(sessionCount: 0, averageGrade: 0, bestGrade: 0);
    }
    final grades = sessions.map((s) => s.totalGrade).toList();
    final avg    = grades.reduce((a, b) => a + b) / grades.length;
    final best   = grades.reduce((a, b) => a > b ? a : b);
    return UserStats(
      sessionCount: sessions.length,
      averageGrade: avg,
      bestGrade:    best,
      bestSession:  sessions.firstWhere((s) => s.totalGrade == best),
    );
  }

  String get averageGradeFormatted =>
      sessionCount == 0 ? '—' : '${averageGrade.toStringAsFixed(1)}%';

  String get sessionCountFormatted => sessionCount == 0 ? '—' : '$sessionCount';
}