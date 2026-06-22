import 'package:flutter/foundation.dart';
import '../../../services/network/network_service.dart';
import '../services/compression_event.dart';
import '../services/rescuer_vital_snapshot.dart';
import '../services/session_local_storage.dart';
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
  /// Paginates through all pages until the server returns fewer than [pageSize] records.
  Future<List<SessionSummary>> fetchSummaries({int pageSize = 50}) async {
    final all = <SessionSummary>[];
    int offset = 0;

    while (true) {
      final response = await _network.get(
        '/sessions/summary?limit=$pageSize&offset=$offset',
        requiresAuth: true,
      );
      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to fetch sessions');
      }
      final List<dynamic> raw = response['data'] ?? [];
      all.addAll(raw.map((json) => SessionSummary.fromJson(json)));

      // If we got fewer than pageSize, we've reached the last page
      if (raw.length < pageSize) break;
      offset += pageSize;
    }

    return all;
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

  /// Resolves a SessionSummary into a full SessionDetail.
  /// - Backend session (id != null): calls GET /sessions/:id/detail.
  /// - Local-only session (id == null): looks up by sessionStart in local storage.
  /// Throws if no matching detail can be located.
  Future<SessionDetail> fetchDetailForSummary(SessionSummary summary) async {
    if (summary.id != null) {
      try {
        return await fetchDetail(summary.id!);
      } catch (_) {
        // Backend returned 404 or error — fall through to local storage
      }
    }
    final start = summary.sessionStart;
    if (start == null) {
      throw Exception('Local session has no start time');
    }
    final all = await SessionLocalStorage.loadAll();
    int trunc(DateTime t) =>
        t.toUtc().copyWith(millisecond: 0, microsecond: 0).millisecondsSinceEpoch;
    return all.firstWhere(
          (d) => trunc(d.sessionStart) == trunc(start),
      orElse: () => throw Exception('Local session not found'),
    );
  }

  // ── Save ───────────────────────────────────────────────────────────────────


  /// Saves a completed SessionDetail to the backend.
  /// Returns the backend session id on success, null on failure.
  /// Returns the backend session id on success, null on failure.
  Future<int?> saveDetail(SessionDetail detail) async {
    try {
      final response = await _network.post(
        '/sessions/detail',
        detail.toJson(),
        requiresAuth: true,
      );
      return (response['data']?['id'] as num?)?.toInt();
    } catch (e) {
      debugPrint('saveDetail failed: $e');
      return null;
    }
  }

  /// Save a session locally only, without hitting the backend.
  /// Used when Emergency mode ends and the user declines to log in.
  Future<bool> saveLocalOnly(SessionDetail detail) async {
    // SessionLocalStorage handles the SharedPreferences write.
    // The sync-on-reconnect logic will pick this up later if the user logs in.
    return SessionLocalStorage.saveLocal(detail);
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

  /// Delete one session by backend ID. Sub-tables deleted via ON DELETE CASCADE.
  /// Returns true on success. Returns false on network/HTTP failure.
  /// Used internally by [deleteSummary] — UI code should call deleteSummary instead.
  Future<bool> deleteSession(int sessionId) async {
    try {
      await _network.delete('/sessions/$sessionId', requiresAuth: true);
      return true;
    } catch (e) {
      debugPrint('deleteSession failed: $e');
      return false;
    }
  }

  /// Delete all sessions for the current user on the backend.
  /// Used internally by [deleteAllSummaries] — UI code should call deleteAllSummaries instead.
  Future<bool> deleteAllSessions() async {
    try {
      await _network.delete('/sessions/all', requiresAuth: true);
      return true;
    } catch (e) {
      debugPrint('deleteAllSessions failed: $e');
      return false;
    }
  }

  /// Single entry point for deleting a session from the UI.
  ///
  /// Handles all three cases consistently:
  ///   1. Backend + local copy   → DELETE backend, then deleteByStart locally
  ///   2. Backend only           → DELETE backend (local copy already absent)
  ///   3. Local only (id == null)→ deleteByStart locally; no network call
  ///
  /// Returns true if the session is gone from both stores after the call.
  /// Returns false only when a backend-tracked session could not be deleted
  /// from the backend (network error). In that case the local copy is left
  /// intact so a retry can succeed later.
  Future<bool> deleteSummary(SessionSummary summary) async {
    final start = summary.sessionStart;

    // Local-only session — nothing to delete on the backend
    if (summary.id == null) {
      if (start != null) {
        await SessionLocalStorage.deleteByStart(start);
      }
      return true;
    }

    // Backend-tracked session — delete remotely first, then clean local copy
    final ok = await deleteSession(summary.id!);
    if (!ok) return false;

    if (start != null) {
      await SessionLocalStorage.deleteByStart(start);
    }
    return true;
  }

  /// Single entry point for deleting all sessions (logged-in users only).
  /// Wipes the backend, then clears the local cache. Returns true on success.
  Future<bool> deleteAllSummaries() async {
    final ok = await deleteAllSessions();
    if (!ok) return false;
    await SessionLocalStorage.deleteAll();
    return true;
  }

  /// Delete the current user's account and all associated data.
  Future<bool> deleteAccount() async {
    try {
      await _network.delete('/auth/account', requiresAuth: true);
      return true;
    } catch (e) {
      debugPrint('deleteAccount failed: $e');
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

  // ── Grade calculation ──────────────────────────────────────────────────────
  //
  // Training mode only — Emergency sessions always return 0.0.
  // Formula weights differ per scenario per BLE Spec v3.0 Section 7.
  //
  // Standard Adult weights:
  //   Depth consistency       25%
  //   Rate consistency        20%
  //   Full recoil             20%
  //   Depth + rate combo       8%
  //   Ventilation compliance  12%
  //   Posture consistency      8%
  //   Hands-on ratio           5%
  //   Time to first comp       2%
  //
  // Pediatric adjustments:
  //   Depth consistency       28%  (narrower 4–5 cm target)
  //   Rate consistency        18%
  //   Full recoil             18%
  //   Depth + rate combo       8%
  //   Ventilation compliance  12%
  //   Posture consistency      8%
  //   Hands-on ratio           4%
  //   Time to first comp       4%  (pediatric urgency)

  double calculateGradeFromDetail(SessionDetail s) {
    // Emergency sessions never have a grade
    if (s.isEmergency) return 0.0;
    if (s.compressionCount < 10) return 0.0;

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
    final double timeScore;
    if      (s.timeToFirstCompression < 5)  { timeScore = 100; }
    else if (s.timeToFirstCompression < 10) { timeScore = 80;  }
    else                                     { timeScore = 50;  }

    double grade;

    switch (s.scenario) {
      case 'pediatric':

        grade =
            (depthScore   * 0.28) +
                (freqScore    * 0.18) +
                (recoilScore  * 0.18) +
                (comboScore   * 0.08) +
                (handsOnScore * 0.04) +
                (ventScore    * 0.12) +
                (postureScore * 0.08) +
                (timeScore    * 0.04);
      default:
      // standard_adult (default)
        grade =
            (depthScore   * 0.25) +
                (freqScore    * 0.20) +
                (recoilScore  * 0.20) +
                (comboScore   * 0.08) +
                (handsOnScore * 0.05) +
                (ventScore    * 0.12) +
                (postureScore * 0.08) +
                (timeScore    * 0.02);
    }

    return grade.clamp(0.0, 100.0);
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
    DateTime?                           sessionEnd,
    // ── Alert timestamps from BLEConnection ─────────────────────────────────
    int?      fatigueAlertTimestampMs,
    int?      fatigueAlertScore,
    List<int> twoMinAlertTimestampsMs = const [],
    String mode     = 'emergency',
    String scenario = 'standard_adult',
    String ventilationRatio = '30:2',
  }) {
    // Build raw (fromBleSession no longer computes pause logic inline).
    final raw = SessionDetail.fromBleSession(
      summaryPacket:         summaryPacket,
      events:                events,
      ventilationRatio: ventilationRatio,
      ventilationEvents:     ventilationEvents,
      pulseCheckEvents:      pulseCheckEvents,
      rescuerVitalSnapshots: rescuerVitalSnapshots,
      sessionStart:          sessionStart,
      sessionEnd:            sessionEnd,
      sessionDurationSecs:   sessionDurationSecs,
      totalGrade:            0,
      mode:                  mode,
      scenario:              scenario,
      fatigueAlertTimestampMs: fatigueAlertTimestampMs,
      fatigueAlertScore:       fatigueAlertScore,
      twoMinAlertTimestampsMs: twoMinAlertTimestampsMs,
    );

    // Single authoritative pause/ventilation computation.
    final withPause = SessionDetail.applyPauseModel(raw);

    // Grade now sees correct handsOnRatio + ventilationCompliance.
    final grade = calculateGradeFromDetail(withPause);

    return withPause.withGrade(grade);
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
  final int? sessionNumber;

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

  final double noFlowTime;
  final int noFlowIntervals;
  final double unplannedPauseTime;
  final int unplannedPauseCount;

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
  final double handsOnRatio;        // 0.0–1.0

  // ── Ventilation ───────────────────────────────────────────────────────────
  final int    ventilationCount;
  final double ventilationCompliance;
  final int    correctVentilations;

  // ── Pulse check (Emergency only) ──────────────────────────────────────────
  final bool pulseDetectedFinal;
  final int  pulseChecksPrompted;
  final int  pulseChecksComplied;

  // ── Biometrics ────────────────────────────────────────────────────────────
  final double? patientTemperature;
  final double? patientSpO2LastCheck;
  final double? rescuerHRLastPause;
  final double? rescuerSpO2LastPause;
  final double? rescuerWristTempStart;
  final double? rescuerWristTempEnd;

  // ── Timing & grade ────────────────────────────────────────────────────────
  final int       sessionDuration; // seconds
  final double    totalGrade;      // 0–100; always 0.0 for Emergency
  final double    timeToFirstCompression;  // seconds
  final double    rateVariability;          // ms
  final int       consecutiveGoodPeak;
  final DateTime? sessionStart;
  final DateTime? sessionEnd;
  final String?   note;

  const SessionSummary({
    this.id,
    this.sessionNumber,
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
    this.noFlowTime           = 0.0,
    this.noFlowIntervals      = 0,
    this.unplannedPauseTime   = 0.0,
    this.unplannedPauseCount  = 0,
    this.rescuerSwapCount     = 0,
    this.fatigueOnsetIndex    = 0,
    this.averageDepth         = 0.0,
    this.averageFrequency     = 0.0,
    this.averageEffectiveDepth = 0.0,
    this.peakDepth            = 0.0,
    this.depthSD              = 0.0,
    this.depthConsistency     = 0.0,
    this.frequencyConsistency = 0.0,
    this.handsOnRatio         = 0.0,
    this.ventilationCount     = 0,
    this.ventilationCompliance = 0.0,
    this.pulseDetectedFinal   = false,
    this.pulseChecksPrompted  = 0,
    this.pulseChecksComplied  = 0,
    this.patientTemperature,
    this.patientSpO2LastCheck,
    this.rescuerHRLastPause,
    this.rescuerSpO2LastPause,
    this.rescuerWristTempStart,
    this.rescuerWristTempEnd,
    required this.timeToFirstCompression,
    required this.rateVariability,
    required this.consecutiveGoodPeak,
    required this.correctVentilations,
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

  /// Stable session key for client-side maps and selection state.
  ///
  /// Equal to sessionStart truncated to whole seconds, expressed as
  /// ms-since-epoch. Matches the truncation backend `session.js` applies
  /// before INSERT/UPSERT, and matches `SessionLocalStorage.keyMsFromStart`
  /// so the same physical session has identical keys in every store.
  ///
  /// Returns 0 if sessionStart is null — sessionStart should always be
  /// present on a real session, so this fallback only kicks in for malformed
  /// data and prevents a crash rather than masking a bug silently.
  int get selKey {
    final s = sessionStart;
    if (s == null) return 0;
    return s.copyWith(millisecond: 0, microsecond: 0).millisecondsSinceEpoch;
  }

  String get durationFormatted {
    final m = sessionDuration ~/ 60;
    final s = sessionDuration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get dateFormatted {
    if (sessionStart == null) return '—';
    final d = sessionStart!.toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String get dateTimeFormatted {
    if (sessionStart == null) return '—';
    final d = sessionStart!.toLocal();
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year} • $h:$m';
  }

  /// History-list friendly: "Today", "Yesterday", "12 May", or
  /// "12 May 2024" only when not the current year.
  String get relativeDateLabel {
    final d = sessionStart?.toLocal();
    if (d == null) return '—';
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that  = DateTime(d.year, d.month, d.day);
    final diff  = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    final base = '${d.day} ${months[d.month - 1]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  String get timeLabel {
    final d = sessionStart?.toLocal();
    if (d == null) return '';
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
    noFlowTime:            d.noFlowTime,
    noFlowIntervals:       d.noFlowIntervals,
    unplannedPauseTime:    d.unplannedPauseTime,
    unplannedPauseCount:   d.unplannedPauseCount,
    rescuerSwapCount:      d.rescuerSwapCount,
    fatigueOnsetIndex:     d.fatigueOnsetIndex,

    averageDepth:          d.averageDepth,
    averageFrequency:      d.averageFrequency,
    averageEffectiveDepth: d.averageEffectiveDepth,
    peakDepth:             d.peakDepth,
    depthSD:               d.depthSD,
    depthConsistency:      d.depthConsistency,
    frequencyConsistency:  d.frequencyConsistency,
    handsOnRatio:          d.handsOnRatio,

    ventilationCount:      d.ventilationCount,
    ventilationCompliance: d.ventilationCompliance,
    correctVentilations:   d.correctVentilations,

    pulseDetectedFinal:    d.pulseDetectedFinal,
    pulseChecksPrompted:   d.pulseChecksPrompted,
    pulseChecksComplied:   d.pulseChecksComplied,

    patientTemperature:    d.patientTemperature,
    patientSpO2LastCheck:  d.patientSpO2LastCheck,
    rescuerHRLastPause:    d.rescuerHRLastPause,
    rescuerSpO2LastPause:  d.rescuerSpO2LastPause,
    rescuerWristTempStart: d.rescuerWristTempStart,
    rescuerWristTempEnd:   d.rescuerWristTempEnd,

    sessionDuration:        d.sessionDuration,
    totalGrade:             d.totalGrade,
    timeToFirstCompression: d.timeToFirstCompression,
    rateVariability:        d.rateVariability,
    consecutiveGoodPeak:    d.consecutiveGoodPeak,
    sessionStart:          d.sessionStart,
    sessionEnd:            d.sessionEnd,
    note:                  d.note,
  );

  // ── JSON factory — hydrate from backend GET /sessions/summaries ───────────

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id:                    json['id']                       as int?,
      sessionNumber: (json['session_number'] as num?)?.toInt(),
      mode:                  json['mode']                     as String? ?? 'emergency',
      scenario:              json['scenario']                 as String? ?? 'standard_adult',
      compressionCount:      (json['compression_count']       as num?)?.toInt() ?? 0,
      correctDepth:          (json['correct_depth']           as num?)?.toInt() ?? 0,
      correctFrequency:      (json['correct_frequency']       as num?)?.toInt() ?? 0,
      sessionDuration:       (json['session_duration']        as num?)?.toInt() ?? 0,
      correctRecoil:         (json['correct_recoil']          as num?)?.toInt()    ?? 0,
      depthRateCombo:        (json['depth_rate_combo']        as num?)?.toInt()    ?? 0,
      correctPosture:        (json['correct_posture']         as num?)?.toInt()    ?? 0,
      leaningCount:          (json['leaning_count']           as num?)?.toInt()    ?? 0,
      overForceCount:        (json['over_force_count']        as num?)?.toInt()    ?? 0,
      noFlowTime:            (json['no_flow_time']            as num?)?.toDouble() ?? 0.0,
      noFlowIntervals:       (json['no_flow_intervals']       as num?)?.toInt()    ?? 0,
      unplannedPauseTime:    (json['unplanned_pause_time']    as num?)?.toDouble() ?? 0.0,
      unplannedPauseCount:   (json['unplanned_pause_count']   as num?)?.toInt()    ?? 0,
      rescuerSwapCount:      (json['rescuer_swap_count']      as num?)?.toInt()    ?? 0,
      fatigueOnsetIndex:     (json['fatigue_onset_index']     as num?)?.toInt()    ?? 0,
      averageDepth:          (json['average_depth']           as num?)?.toDouble() ?? 0.0,
      averageFrequency:      (json['average_frequency']       as num?)?.toDouble() ?? 0.0,
      averageEffectiveDepth: (json['average_effective_depth'] as num?)?.toDouble() ?? 0.0,
      peakDepth:             (json['peak_depth']              as num?)?.toDouble() ?? 0.0,
      depthSD:               (json['depth_sd']                as num?)?.toDouble() ?? 0.0,
      depthConsistency:      (json['depth_consistency']   as num?)?.toDouble() ?? 0.0,
      frequencyConsistency:  (json['freq_consistency']    as num?)?.toDouble() ?? 0.0,
      handsOnRatio:          (json['hands_on_ratio'] as num?)?.toDouble() ?? 0.0,
      ventilationCount:      (json['ventilation_count']       as num?)?.toInt()    ?? 0,
      ventilationCompliance: (json['ventilation_compliance']  as num?)?.toDouble() ?? 0.0,
      correctVentilations: (json['correct_ventilations'] as num?)?.toInt() ?? 0,
      pulseDetectedFinal:     json['pulse_detected_final']    as bool?             ?? false,
      pulseChecksPrompted:   (json['pulse_checks_prompted']   as num?)?.toInt()    ?? 0,
      pulseChecksComplied:   (json['pulse_checks_complied']   as num?)?.toInt()    ?? 0,
      patientTemperature:    (json['patient_temperature']        as num?)?.toDouble(),
      patientSpO2LastCheck:  (json['patient_spo2_last_check']    as num?)?.toDouble(),
      rescuerHRLastPause:    (json['rescuer_hr_last_pause']      as num?)?.toDouble(),
      rescuerSpO2LastPause:  (json['rescuer_spo2_last_pause']    as num?)?.toDouble(),
      rescuerWristTempStart: (json['rescuer_wrist_temp_start'] as num?)?.toDouble(),
      rescuerWristTempEnd:   (json['rescuer_wrist_temp_end']   as num?)?.toDouble(),
      totalGrade:            (json['total_grade']             as num?)?.toDouble() ?? 0.0,
      timeToFirstCompression: (json['time_to_first_comp']      as num?)?.toDouble() ?? 0.0,
      rateVariability:        (json['rate_variability']        as num?)?.toDouble() ?? 0.0,
      consecutiveGoodPeak:    (json['consecutive_good_peak']   as num?)?.toInt()    ?? 0,
      sessionStart: json['session_start'] != null
          ? DateTime.tryParse(json['session_start'] as String)?.toUtc()
          : null,
      sessionEnd: json['session_end'] != null
          ? DateTime.tryParse(json['session_end'] as String)?.toUtc()
          : null,
      note: json['note'] as String?,
    );
  }
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
      (sessionCount == 0 || averageGrade == 0) ? '—' : '${averageGrade.toStringAsFixed(1)}%';

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