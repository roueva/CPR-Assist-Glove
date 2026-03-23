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

// ─────────────────────────────────────────────────────────────────────────────
// SessionService  —  grade calculation + save/fetch + detail assembly
//
// REPLACE the entire SessionService class in session_service.dart
// (from line 16 `class SessionService {` through line 200 closing `}`)
// with this block. Leave SessionSummary, UserStats untouched below it.
// ─────────────────────────────────────────────────────────────────────────────

class SessionService {
  final NetworkService _network;

  SessionService(this._network);

  // ── Fetch ──────────────────────────────────────────────────────────────────

  /// Fetch all session summaries for list views (history, leaderboard).
  /// Fetch all session summaries for list views (history, leaderboard).
  /// Uses the paginated /sessions/summary endpoint with a high limit to get all records.
  Future<List<SessionSummary>> fetchSummaries() async {
    final response = await _network.get(
      '/sessions/summary?limit=100&offset=0',
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

  /// Delete one session by ID. Sub-tables deleted via ON DELETE CASCADE.
  Future<bool> deleteSession(int sessionId) async {
    try {
      await _network.delete('/sessions/$sessionId', requiresAuth: true);
      return true;
    } catch (e) {
      debugPrint('deleteSession failed: $e');
      return false;
    }
  }

  /// Delete all sessions for the current user.
  Future<bool> deleteAllSessions() async {
    try {
      await _network.delete('/sessions/all', requiresAuth: true);
      return true;
    } catch (e) {
      debugPrint('deleteAllSessions failed: $e');
      return false;
    }
  }

  /// Fetch global leaderboard for a scenario.
  /// Returns the ranked list + current user's own rank entry (may be null
  /// if user hasn't qualified with ≥3 sessions yet).
  Future<(List<LeaderboardEntry>, LeaderboardEntry?)> fetchGlobalLeaderboard({
    String scenario = 'standard_adult',
  }) async {
    final response = await _network.get(
      '/leaderboard/global?scenario=$scenario',
      requiresAuth: true,
    );
    if (response['success'] != true) {
      throw Exception(response['message'] ?? 'Failed to fetch leaderboard');
    }
    final entries = (response['data'] as List<dynamic>)
        .map((j) => LeaderboardEntry.fromJson(j as Map<String, dynamic>))
        .toList();
    final myRankJson = response['my_rank'] as Map<String, dynamic>?;
    final myRank     = myRankJson != null
        ? LeaderboardEntry.fromJson(myRankJson)
        : null;
    return (entries, myRank);
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
  //
  // Training mode only — Emergency sessions always return 0.0.
  // Formula weights differ per scenario per BLE Spec v3.0 Section 7.
  //
  // Standard Adult weights:
  //   Depth consistency       20%
  //   Frequency consistency   18%
  //   Correct recoil          15%
  //   Depth + rate combo      12%
  //   Hands-on ratio (CCF)    10%
  //   Ventilation compliance  10%
  //   Posture consistency      5%
  //   Force safety             5%
  //   Time to first comp       5%
  //   Fatigue penalty         −5 pts  (if fatigueOnsetIndex > 0)
  //
  // Pediatric adjustments:
  //   Depth consistency       25%  (+5 — harder to maintain narrower target)
  //   Force safety            10%  (+5 — smaller chest, higher injury risk)
  //   Time to first comp      10%  (+5 — pediatric urgency)
  //   Frequency consistency   13%  (−5)
  //   Hands-on ratio          5%   (−5)
  //   Correct recoil          10%  (−5 — reduced to balance total to 100%)
  //
  // Timed Endurance adjustments:
  //   Depth consistency       25%
  //   Fatigue penalty        −10 pts
  //   Time to first comp removed (not relevant)
  //   Remaining weights redistributed proportionally

  double calculateGradeFromDetail(SessionDetail s) {
    // Emergency sessions never have a grade
    if (s.isEmergency) return 0.0;
    if (s.compressionCount == 0) return 0.0;

    final n = s.compressionCount.toDouble();

    final depthScore       = s.correctDepth     / n * 100;
    final freqScore        = s.correctFrequency / n * 100;
    final recoilScore      = s.correctRecoil    / n * 100;
    final comboScore       = s.depthRateCombo   / n * 100;
    final handsOnScore     = s.handsOnRatio * 100;
    // No ventilation windows in session = not penalised
    final ventScore        = s.ventilationCount > 0
        ? s.ventilationCompliance
        : 100.0;
    final postureScore     = s.correctPosture   / n * 100;
    final forceSafetyScore = (1 - s.overForceCount / n) * 100;
    final double timeScore;
    if      (s.timeToFirstCompression < 5)  { timeScore = 100; }
    else if (s.timeToFirstCompression < 10) { timeScore = 80;  }
    else                                     { timeScore = 50;  }

    double grade;

    switch (s.scenario) {
      case 'pediatric':
      // Depth and safety weighted higher; time to first comp increased;
      // freq and CCF slightly reduced to make room.
        grade =
            (depthScore       * 0.25) +
                (freqScore        * 0.13) +
                (recoilScore      * 0.10) +
                (comboScore       * 0.12) +
                (handsOnScore     * 0.05) +
                (ventScore        * 0.10) +
                (postureScore     * 0.05) +
                (forceSafetyScore * 0.10) +
                (timeScore        * 0.10) -
                (s.fatigueOnsetIndex > 0 ? 5.0 : 0.0);

      case 'timed_endurance':
      // Fatigue management is the primary goal — no time-to-first penalty,
      // heavier fatigue penalty, higher depth weight.
        grade =
            (depthScore       * 0.30) +
                (freqScore        * 0.18) +
                (recoilScore      * 0.15) +
                (comboScore       * 0.12) +
                (handsOnScore     * 0.10) +
                (ventScore        * 0.10) +
                (postureScore     * 0.05) +
                (forceSafetyScore * 0.05) -
                (s.fatigueOnsetIndex > 0 ? 10.0 : 0.0);

      default:
      // standard_adult (default)
        grade =
            (depthScore       * 0.20) +
                (freqScore        * 0.18) +
                (recoilScore      * 0.15) +
                (comboScore       * 0.12) +
                (handsOnScore     * 0.10) +
                (ventScore        * 0.10) +
                (postureScore     * 0.05) +
                (forceSafetyScore * 0.05) +
                (timeScore        * 0.05) -
                (s.fatigueOnsetIndex > 0 ? 5.0 : 0.0);
    }

    return grade.clamp(0.0, 100.0);
  }

  /// Legacy grade calc from a [SessionSummary] — kept for backward compat.
  double calculateGrade(SessionSummary session) {
    if (session.isEmergency) return 0.0;
    if (session.compressionCount == 0) return 0.0;
    final d = session.correctDepth     / session.compressionCount;
    final f = session.correctFrequency / session.compressionCount;
    final r = session.correctRecoil    / session.compressionCount;
    final c = session.depthRateCombo   / session.compressionCount;
    return ((d * 35) + (f * 30) + (r * 20) + (c * 15)).clamp(0.0, 100.0);
  }

  // ── Assemble SessionDetail from BLE data ───────────────────────────────────
  //
  // Called by live_cpr_screen.dart when SESSION_END arrives.
  // [summaryPacket] is the Map broadcast by BLEConnection._handleEventPacket().
  // [mode] and [scenario] come from the app's provider state — they reflect
  // what was active at session end (including any glove-initiated changes).
  //
  // Two-pass approach: first build without grade to compute app-side metrics,
  // then calculate grade from those metrics and rebuild with the final value.
  // This avoids passing partially-computed values into the grading formula.

  SessionDetail assembleDetail({
    required Map<String, dynamic>       summaryPacket,
    required List<CompressionEvent>     events,
    required List<VentilationEvent>     ventilationEvents,
    required List<PulseCheckEvent>      pulseCheckEvents,
    required List<RescuerVitalSnapshot> rescuerVitalSnapshots,
    required DateTime                   sessionStart,
    required int                        sessionDurationSecs,
    String mode     = 'emergency',
    String scenario = 'standard_adult',
  }) {
    // Pass 1: build with grade = 0 to get all computed metrics
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
      scenario:              scenario,
    );

    // Pass 2: grade from computed metrics, then rebuild
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
      scenario:              scenario,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION SUMMARY MODEL
//
// Lightweight projection used for list views, leaderboard, and history cards.
// Full detail lives in SessionDetail.
//
// REPLACE the entire SessionSummary class in session_service.dart
// (lines 208–343 in the original) with this block.
// Leave SessionService, UserStats, and everything above/below untouched.
// ─────────────────────────────────────────────────────────────────────────────

class SessionSummary {
  final int?     id;

  // ── Mode & scenario ────────────────────────────────────────────────────────
  final String mode;      // "emergency" | "training" | "training_no_feedback"
  final String scenario;  // "standard_adult" | "pediatric" | etc.

  // ── Core counts ───────────────────────────────────────────────────────────
  final int compressionCount;
  final int correctDepth;
  final int correctFrequency;
  final int correctRecoil;
  final int depthRateCombo;
  final int correctPosture;
  final int leaningCount;
  final int overForceCount;
  final int noFlowIntervals;
  final int rescuerSwapCount;
  final int fatigueOnsetIndex;

  // ── Averages & peaks ──────────────────────────────────────────────────────
  final double averageDepth;
  final double averageFrequency;
  final double averageEffectiveDepth;
  final double peakDepth;
  final double depthSD;
  final double depthConsistency;
  final double frequencyConsistency;

  // ── Ventilation ───────────────────────────────────────────────────────────
  final int    ventilationCount;
  final double ventilationCompliance;

  // ── Pulse check (Emergency only) ──────────────────────────────────────────
  final bool pulseDetectedFinal;
  final int  pulseChecksPrompted;
  final int  pulseChecksComplied;

  // ── Biometrics ────────────────────────────────────────────────────────────
  final double? patientTemperature;
  final double? rescuerHRLastPause;
  final double? rescuerSpO2LastPause;

  // ── Timing & grade ────────────────────────────────────────────────────────
  final int       sessionDuration; // seconds
  final double    totalGrade;      // 0–100; always 0.0 for Emergency
  final DateTime? sessionStart;
  final DateTime? sessionEnd;
  final String?   note;

  const SessionSummary({
    this.id,
    this.mode                 = 'emergency',
    this.scenario             = 'standard_adult',
    required this.compressionCount,
    required this.correctDepth,
    required this.correctFrequency,
    this.correctRecoil        = 0,
    this.depthRateCombo       = 0,
    this.correctPosture       = 0,
    this.leaningCount         = 0,
    this.overForceCount       = 0,
    this.noFlowIntervals      = 0,
    this.rescuerSwapCount     = 0,
    this.fatigueOnsetIndex    = 0,
    this.averageDepth         = 0.0,
    this.averageFrequency     = 0.0,
    this.averageEffectiveDepth = 0.0,
    this.peakDepth            = 0.0,
    this.depthSD              = 0.0,
    this.depthConsistency     = 0.0,
    this.frequencyConsistency = 0.0,
    this.ventilationCount     = 0,
    this.ventilationCompliance = 0.0,
    this.pulseDetectedFinal   = false,
    this.pulseChecksPrompted  = 0,
    this.pulseChecksComplied  = 0,
    this.patientTemperature,
    this.rescuerHRLastPause,
    this.rescuerSpO2LastPause,
    required this.sessionDuration,
    this.totalGrade           = 0.0,
    this.sessionStart,
    this.sessionEnd,
    this.note,
  });

  // ── Convenience getters ───────────────────────────────────────────────────

  bool get isEmergency  => mode == 'emergency';
  bool get isTraining   => mode == 'training' || mode == 'training_no_feedback';
  bool get isNoFeedback => mode == 'training_no_feedback';

  String get durationFormatted {
    final m = sessionDuration ~/ 60;
    final s = sessionDuration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get dateFormatted {
    if (sessionStart == null) return '—';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${sessionStart!.day} ${months[sessionStart!.month - 1]} '
        '${sessionStart!.year}';
  }

  String get dateTimeFormatted {
    if (sessionStart == null) return '—';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = sessionStart!.hour.toString().padLeft(2, '0');
    final m = sessionStart!.minute.toString().padLeft(2, '0');
    return '${sessionStart!.day} ${months[sessionStart!.month - 1]} '
        '${sessionStart!.year} • $h:$m';
  }

  // ── Build from BLE end-ping (summary-only fallback) ───────────────────────

  factory SessionSummary.fromBleData(
      Map<String, dynamic> data, {
        required DateTime sessionStart,
        required int      sessionDuration,
        required double   totalGrade,
        String mode     = 'emergency',
        String scenario = 'standard_adult',
      }) {
    return SessionSummary(
      mode:             mode,
      scenario:         scenario,
      compressionCount: data['totalCompressions']   as int?    ?? 0,
      correctDepth:     data['correctDepth']         as int?    ?? 0,
      correctFrequency: data['correctFrequency']     as int?    ?? 0,
      correctRecoil:    data['correctRecoil']        as int?    ?? 0,
      depthRateCombo:   data['depthRateCombo']       as int?    ?? 0,
      averageDepth:     (data['depth']               as num?)?.toDouble() ?? 0.0,
      averageFrequency: (data['frequency']           as num?)?.toDouble() ?? 0.0,
      peakDepth:        (data['peakDepth']           as num?)?.toDouble() ?? 0.0,
      rescuerHRLastPause:   (data['rescuerHRLastPause']   as num?)?.toDouble(),
      rescuerSpO2LastPause: (data['rescuerSpO2LastPause'] as num?)?.toDouble(),
      sessionDuration:  sessionDuration,
      totalGrade:       mode == 'emergency' ? 0.0 : totalGrade,
      sessionStart:     sessionStart,
    );
  }

  /// Build a lightweight summary from a full SessionDetail.
  /// Used when merging local unsynced sessions into the session list.
  factory SessionSummary.fromDetail(SessionDetail d) => SessionSummary(
    id:                    d.id,
    mode:                  d.mode,
    scenario:              d.scenario,
    compressionCount:      d.compressionCount,
    correctDepth:          d.correctDepth,
    correctFrequency:      d.correctFrequency,
    correctRecoil:         d.correctRecoil,
    depthRateCombo:        d.depthRateCombo,
    correctPosture:        d.correctPosture,
    leaningCount:          d.leaningCount,
    overForceCount:        d.overForceCount,
    noFlowIntervals:       d.noFlowIntervals,
    rescuerSwapCount:      d.rescuerSwapCount,
    fatigueOnsetIndex:     d.fatigueOnsetIndex,
    averageDepth:          d.averageDepth,
    averageFrequency:      d.averageFrequency,
    averageEffectiveDepth: d.averageEffectiveDepth,
    peakDepth:             d.peakDepth,
    depthSD:               d.depthSD,
    depthConsistency:      d.depthConsistency,
    frequencyConsistency:  d.frequencyConsistency,
    ventilationCount:      d.ventilationCount,
    ventilationCompliance: d.ventilationCompliance,
    pulseDetectedFinal:    d.pulseDetectedFinal,
    pulseChecksPrompted:   d.pulseChecksPrompted,
    pulseChecksComplied:   d.pulseChecksComplied,
    patientTemperature:    d.patientTemperature,
    rescuerHRLastPause:    d.rescuerHRLastPause,
    rescuerSpO2LastPause:  d.rescuerSpO2LastPause,
    sessionDuration:       d.sessionDuration,
    totalGrade:            d.totalGrade,
    sessionStart:          d.sessionStart,
    sessionEnd:            d.sessionEnd,
    note:                  d.note,
  );

  // ── JSON factory — hydrate from backend GET /sessions/summaries ───────────

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id:                    json['id']                       as int?,
      mode:                  json['mode']                     as String? ?? 'emergency',
      scenario:              json['scenario']                 as String? ?? 'standard_adult',
      compressionCount:      (json['compression_count']       as num).toInt(),
      correctDepth:          (json['correct_depth']           as num).toInt(),
      correctFrequency:      (json['correct_frequency']       as num).toInt(),
      correctRecoil:         (json['correct_recoil']          as num?)?.toInt()    ?? 0,
      depthRateCombo:        (json['depth_rate_combo']        as num?)?.toInt()    ?? 0,
      correctPosture:        (json['correct_posture']         as num?)?.toInt()    ?? 0,
      leaningCount:          (json['leaning_count']           as num?)?.toInt()    ?? 0,
      overForceCount:        (json['over_force_count']        as num?)?.toInt()    ?? 0,
      noFlowIntervals:       (json['no_flow_intervals']       as num?)?.toInt()    ?? 0,
      rescuerSwapCount:      (json['rescuer_swap_count']      as num?)?.toInt()    ?? 0,
      fatigueOnsetIndex:     (json['fatigue_onset_index']     as num?)?.toInt()    ?? 0,
      averageDepth:          (json['average_depth']           as num?)?.toDouble() ?? 0.0,
      averageFrequency:      (json['average_frequency']       as num?)?.toDouble() ?? 0.0,
      averageEffectiveDepth: (json['average_effective_depth'] as num?)?.toDouble() ?? 0.0,
      peakDepth:             (json['peak_depth']              as num?)?.toDouble() ?? 0.0,
      depthSD:               (json['depth_sd']                as num?)?.toDouble() ?? 0.0,
      depthConsistency:      (json['depth_consistency']   as num?)?.toDouble() ?? 0.0,
      frequencyConsistency:  (json['freq_consistency']    as num?)?.toDouble() ?? 0.0,
      ventilationCount:      (json['ventilation_count']       as num?)?.toInt()    ?? 0,
      ventilationCompliance: (json['ventilation_compliance']  as num?)?.toDouble() ?? 0.0,
      pulseDetectedFinal:     json['pulse_detected_final']    as bool?             ?? false,
      pulseChecksPrompted:   (json['pulse_checks_prompted']   as num?)?.toInt()    ?? 0,
      pulseChecksComplied:   (json['pulse_checks_complied']   as num?)?.toInt()    ?? 0,
      patientTemperature:    (json['patient_temperature']     as num?)?.toDouble(),
      rescuerHRLastPause:    (json['rescuer_hr_last_pause']   as num?)?.toDouble(),
      rescuerSpO2LastPause:  (json['rescuer_spo2_last_pause'] as num?)?.toDouble(),
      sessionDuration:       (json['session_duration']        as num).toInt(),
      totalGrade:            (json['total_grade']             as num?)?.toDouble() ?? 0.0,
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
    'mode':                   mode,
    'scenario':               scenario,
    'compression_count':      compressionCount,
    'correct_depth':          correctDepth,
    'correct_frequency':      correctFrequency,
    'correct_recoil':         correctRecoil,
    'depth_rate_combo':       depthRateCombo,
    'correct_posture':        correctPosture,
    'leaning_count':          leaningCount,
    'over_force_count':       overForceCount,
    'no_flow_intervals':      noFlowIntervals,
    'rescuer_swap_count':     rescuerSwapCount,
    'fatigue_onset_index':    fatigueOnsetIndex,
    'average_depth':          averageDepth,
    'average_frequency':      averageFrequency,
    'average_effective_depth': averageEffectiveDepth,
    'peak_depth':             peakDepth,
    'depth_sd':               depthSD,
    'depth_consistency':      depthConsistency,
    'freq_consistency':       frequencyConsistency,
    'ventilation_count':      ventilationCount,
    'ventilation_compliance': ventilationCompliance,
    'pulse_detected_final':   pulseDetectedFinal,
    'pulse_checks_prompted':  pulseChecksPrompted,
    'pulse_checks_complied':  pulseChecksComplied,
    if (patientTemperature   != null) 'patient_temperature':    patientTemperature,
    if (rescuerHRLastPause   != null) 'rescuer_hr_last_pause':  rescuerHRLastPause,
    if (rescuerSpO2LastPause != null) 'rescuer_spo2_last_pause': rescuerSpO2LastPause,
    'session_duration':       sessionDuration,
    'total_grade':            totalGrade,
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
    // Only training sessions have meaningful grades
    final trainingSessions = sessions
        .where((s) => s.isTraining && s.totalGrade > 0)
        .toList();
    final grades = trainingSessions.isEmpty
        ? [0.0]
        : trainingSessions.map((s) => s.totalGrade).toList();
    final avg  = grades.reduce((a, b) => a + b) / grades.length;
    final best = grades.reduce((a, b) => a > b ? a : b);
    return UserStats(
      sessionCount: sessions.length,           // total includes Emergency
      averageGrade: trainingSessions.isEmpty ? 0 : avg,
      bestGrade:    trainingSessions.isEmpty ? 0 : best,
      bestSession:  trainingSessions.isEmpty
          ? null
          : trainingSessions.firstWhere((s) => s.totalGrade == best),
    );
  }

  String get averageGradeFormatted =>
      sessionCount == 0 ? '—' : '${averageGrade.toStringAsFixed(1)}%';

  String get sessionCountFormatted =>
      sessionCount == 0 ? '—' : '$sessionCount';
}

// ─────────────────────────────────────────────────────────────────────────────
// LeaderboardEntry — matches GET /leaderboard/global response shape
// ─────────────────────────────────────────────────────────────────────────────

class LeaderboardEntry {
  final int    rank;
  final String username;
  final double avgGrade;
  final double bestGrade;
  final int    sessionCount;
  final bool   isCurrentUser;

  const LeaderboardEntry({
    required this.rank,
    required this.username,
    required this.avgGrade,
    required this.bestGrade,
    required this.sessionCount,
    required this.isCurrentUser,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) =>
      LeaderboardEntry(
        rank:          j['rank']            as int,
        username:      j['username']        as String,
        avgGrade:      (j['avg_grade']      as num).toDouble(),
        bestGrade:     (j['best_grade']     as num?)?.toDouble() ?? 0.0,
        sessionCount:  j['session_count']   as int,
        isCurrentUser: j['is_current_user'] as bool? ?? false,
      );
}