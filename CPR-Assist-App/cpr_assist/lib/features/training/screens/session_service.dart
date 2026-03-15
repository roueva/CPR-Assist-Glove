import 'package:flutter/foundation.dart';

import '../../../services/network/network_service.dart';
import '../services/compression_event.dart';
import '../services/rescuer_vital_snapshot.dart';
import '../services/ventilation_event.dart';
import '../services/pulse_check_event.dart';
import '../services/session_detail.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SERVICE
// Single source of truth for all session data: model, save, fetch, grade calc.
// Used by: grade_screen.dart, past_sessions_screen.dart, leaderboard_screen.dart
// ─────────────────────────────────────────────────────────────────────────────

class SessionService {
  final NetworkService _network;

  SessionService(this._network);

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Fetch all session summaries for list views (history, leaderboard).
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

  /// Fetch a single session's full detail (with all sub-lists).
  Future<SessionDetail> fetchDetail(int sessionId) async {
    final response = await _network.get(
      '/sessions/$sessionId/detail',
      requiresAuth: true,
    );
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to fetch session detail');
    }
    return SessionDetail.fromJson(response['data'] as Map<String, dynamic>);
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Save a completed SessionDetail to the backend (upsert on session_start).
  Future<bool> saveDetail(SessionDetail detail) async {
    try {
      await _network.post(
        '/sessions/detail',
        detail.toJson(),
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('saveDetail failed: $e');
      return false;
    }
  }

  /// Update the note on a saved session.
  Future<bool> updateNote(int sessionId, String? note) async {
    try {
      await _network.patch(
        '/sessions/$sessionId/note',
        {'note': note},
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('updateNote failed: $e');
      return false;
    }
  }

  /// Legacy: save a summary-only record. Kept for backward compatibility.
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

  /// Calculates a 0–100 grade per BLE Spec v2.0 Section 9.
  /// Training mode only. Pulse check compliance excluded (manikins have no pulse).
  ///
  /// Weights:
  ///   Depth consistency       20%
  ///   Frequency consistency   18%
  ///   Correct recoil          15%
  ///   Depth + rate combo      12%
  ///   Hands-on ratio (CCF)    10%
  ///   Ventilation compliance  10%
  ///   Posture consistency      5%
  ///   Force safety             5%
  ///   Time to first comp       5%
  ///   Fatigue penalty         −5 pts (if fatigueOnsetIndex > 0)
  double calculateGradeFromDetail(SessionDetail s) {
    if (s.compressionCount == 0) return 0;

    final n = s.compressionCount.toDouble();

    final depthScore       = s.correctDepth     / n * 100;
    final freqScore        = s.correctFrequency / n * 100;
    final recoilScore      = s.correctRecoil    / n * 100;
    final comboScore       = s.depthRateCombo   / n * 100;
    final handsOnScore     = s.handsOnRatio * 100;
    // No ventilations in session = rescuer is not penalised
    final ventScore        = s.ventilationCount > 0
        ? s.ventilationCompliance
        : 100.0;
    final postureScore     = s.correctPosture   / n * 100;
    final forceSafetyScore = (1 - s.overForceCount / n) * 100;
    final double timeScore;
    if      (s.timeToFirstCompression < 5)  { timeScore = 100; }
    else if (s.timeToFirstCompression < 10) { timeScore = 80;  }
    else                                     { timeScore = 50;  }

    double grade =
        (depthScore       * 0.20) +
            (freqScore        * 0.18) +
            (recoilScore      * 0.15) +
            (comboScore       * 0.12) +
            (handsOnScore     * 0.10) +
            (ventScore        * 0.10) +
            (postureScore     * 0.05) +
            (forceSafetyScore * 0.05) +
            (timeScore        * 0.05);

    if (s.fatigueOnsetIndex > 0) grade -= 5;

    return grade.clamp(0.0, 100.0);
  }

  /// Legacy grade calc from a [SessionSummary] — kept for backward compat.
  double calculateGrade(SessionSummary session) {
    if (session.compressionCount == 0) return 0;
    final d = session.correctDepth     / session.compressionCount;
    final f = session.correctFrequency / session.compressionCount;
    final r = session.correctRecoil    / session.compressionCount;
    final c = session.depthRateCombo   / session.compressionCount;
    return ((d * 35) + (f * 30) + (r * 20) + (c * 15)).clamp(0.0, 100.0);
  }

  // ── Assemble SessionDetail from BLE data ───────────────────────────────────

  /// Called when the BLE end-ping arrives. Combines the accumulated event
  /// streams with the [summaryPacket] and calculates the grade.
  SessionDetail assembleDetail({
    required Map<String, dynamic>       summaryPacket,
    required List<CompressionEvent>     events,
    required List<VentilationEvent>     ventilationEvents,
    required List<PulseCheckEvent>      pulseCheckEvents,
    required List<RescuerVitalSnapshot> rescuerVitalSnapshots,
    required DateTime                   sessionStart,
    required int                        sessionDurationSecs,
    String mode = 'emergency',
  }) {
    // Build once to compute all app-side metrics
    final partialDetail = SessionDetail.fromBleSession(
      summaryPacket:         summaryPacket,
      events:                events,
      ventilationEvents:     ventilationEvents,
      pulseCheckEvents:      pulseCheckEvents,
      rescuerVitalSnapshots: rescuerVitalSnapshots,
      sessionStart:          sessionStart,
      sessionDurationSecs:   sessionDurationSecs,
      totalGrade:            0,
      mode:                  mode,
    );

    // Grade with the real formula, then rebuild with the final grade
    final grade = calculateGradeFromDetail(partialDetail);

    return SessionDetail.fromBleSession(
      summaryPacket:         summaryPacket,
      events:                events,
      ventilationEvents:     ventilationEvents,
      pulseCheckEvents:      pulseCheckEvents,
      rescuerVitalSnapshots: rescuerVitalSnapshots,
      sessionStart:          sessionStart,
      sessionDurationSecs:   sessionDurationSecs,
      totalGrade:            grade,
      mode:                  mode,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SUMMARY MODEL
// Lightweight projection used for list views, leaderboard, and legacy compat.
// Full detail lives in SessionDetail.
// ─────────────────────────────────────────────────────────────────────────────

class SessionSummary {
  final int?    id;
  final int     compressionCount;
  final int     correctDepth;
  final int     correctFrequency;
  final int     correctRecoil;
  final int     depthRateCombo;
  final double  averageDepth;
  final double  averageFrequency;
  final bool    correctRebound;
  final int?    userHeartRate;
  final double? userTemperature;
  final int     sessionDuration;  // seconds
  final double  totalGrade;       // 0–100
  final DateTime? sessionStart;
  final DateTime? sessionEnd;
  final String?   note;

  const SessionSummary({
    this.id,
    required this.compressionCount,
    required this.correctDepth,
    required this.correctFrequency,
    this.correctRecoil  = 0,
    this.depthRateCombo = 0,
    this.averageDepth   = 0.0,
    this.averageFrequency = 0.0,
    this.correctRebound = false,
    this.userHeartRate,
    this.userTemperature,
    required this.sessionDuration,
    this.totalGrade  = 0.0,
    this.sessionStart,
    this.sessionEnd,
    this.note,
  });

  // ── Derived helpers ────────────────────────────────────────────────────────

  String get durationFormatted {
    final m = sessionDuration ~/ 60;
    final s = sessionDuration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get dateFormatted {
    if (sessionStart == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${sessionStart!.day} ${months[sessionStart!.month - 1]} '
        '${sessionStart!.year}';
  }

  String get dateTimeFormatted {
    if (sessionStart == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = sessionStart!.hour.toString().padLeft(2, '0');
    final m = sessionStart!.minute.toString().padLeft(2, '0');
    return '${sessionStart!.day} ${months[sessionStart!.month - 1]} '
        '${sessionStart!.year} • $h:$m';
  }

  // ── Build from BLE end-ping (summary-only fallback) ────────────────────────

  factory SessionSummary.fromBleData(
      Map<String, dynamic> data, {
        required DateTime sessionStart,
        required int      sessionDuration,
        required double   totalGrade,
      }) {
    return SessionSummary(
      compressionCount: data['totalCompressions'] as int?    ?? 0,
      correctDepth:     data['correctDepth']      as int?    ?? 0,
      correctFrequency: data['correctFrequency']  as int?    ?? 0,
      correctRecoil:    data['correctRecoil']     as int?    ?? 0,
      depthRateCombo:   data['depthRateCombo']    as int?    ?? 0,
      averageDepth:     (data['depth']            as num?)?.toDouble() ?? 0.0,
      averageFrequency: (data['frequency']        as num?)?.toDouble() ?? 0.0,
      userHeartRate:    data['userHeartRate']     as int?,
      userTemperature:  (data['userTemperature']  as num?)?.toDouble(),
      sessionDuration:  sessionDuration,
      totalGrade:       totalGrade,
      sessionStart:     sessionStart,
    );
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id:               json['id']                    as int?,
      compressionCount: (json['compression_count']    as num).toInt(),
      correctDepth:     (json['correct_depth']        as num).toInt(),
      correctFrequency: (json['correct_frequency']    as num).toInt(),
      correctRecoil:    (json['correct_recoil']       as num?)?.toInt()    ?? 0,
      depthRateCombo:   (json['depth_rate_combo']     as num?)?.toInt()    ?? 0,
      averageDepth:     (json['average_depth']        as num?)?.toDouble() ?? 0.0,
      averageFrequency: (json['average_frequency']    as num?)?.toDouble() ?? 0.0,
      correctRebound:    json['correct_rebound']      as bool?             ?? false,
      userHeartRate:    (json['user_heart_rate']      as num?)?.toInt(),
      userTemperature:  (json['user_temperature']     as num?)?.toDouble(),
      sessionDuration:  (json['session_duration']     as num).toInt(),
      totalGrade:       (json['total_grade']          as num?)?.toDouble() ?? 0.0,
      sessionStart: json['session_start'] != null
          ? DateTime.tryParse(json['session_start'] as String)
          : null,
      sessionEnd: json['session_end'] != null
          ? DateTime.tryParse(json['session_end'] as String)
          : null,
      note: json['note'] as String?,
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
    if (userHeartRate   != null) 'user_heart_rate':  userHeartRate,
    if (userTemperature != null) 'user_temperature': userTemperature,
    'session_duration':   sessionDuration,
    'total_grade':        totalGrade,
    if (sessionStart != null) 'session_start': sessionStart!.toIso8601String(),
    if (sessionEnd   != null) 'session_end':   sessionEnd!.toIso8601String(),
    if (note         != null) 'note':          note,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// USER STATS — computed client-side from session list
// ─────────────────────────────────────────────────────────────────────────────

class UserStats {
  final int     sessionCount;
  final double  averageGrade;
  final double  bestGrade;
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

  String get sessionCountFormatted =>
      sessionCount == 0 ? '—' : '$sessionCount';
}