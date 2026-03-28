import 'dart:math' show sqrt;

import 'package:cpr_assist/features/training/services/rescuer_vital_snapshot.dart';

import '../../../core/utils/app_extensions.dart';
import 'compression_event.dart';
import 'ventilation_event.dart';
import 'pulse_check_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionDetail  —  Complete session record  (BLE Spec v3.0 Section 8.5)
//
// Flow:
//   BLE SESSION_START  → BLEConnection clears all event lists
//   BLE LIVE_STREAM    → compressions accumulated in BLEConnection
//   BLE EVENT_CHANNEL  → ventilations, pulseChecks, rescuerVitals accumulated
//   BLE SESSION_END    → SessionDetail.fromBleSession() assembles everything
//   Results screen     → receives SessionDetail, renders summary / graphs
//   Backend            → SessionDetail.toJson() POSTed to /sessions/detail
//   History screen     → SessionDetail.fromJson() hydrated from backend
//
// Emergency mode: totalGrade is always 0.0. Never displayed.
// Training mode:  totalGrade computed by SessionService.calculateGrade().
// ─────────────────────────────────────────────────────────────────────────────

class SessionDetail {
  // ── Identity ──────────────────────────────────────────────────────────────
  final int?      id;
  final DateTime  sessionStart;
  final DateTime? sessionEnd;

  // ── Mode & scenario ───────────────────────────────────────────────────────
  /// "emergency" | "training" | "training_no_feedback"
  final String mode;

  /// "standard_adult" | "standard_adult_nofeedback" | "pediatric" | "timed_endurance"
  final String scenario;

  // ── Glove-side totals (from SESSION_END packet) ───────────────────────────
  final int compressionCount;
  final int correctDepth;
  final int correctFrequency;
  final int correctRecoil;
  final int depthRateCombo;
  final int correctPosture;
  final int leaningCount;
  final int overForceCount;
  final int tooDeepCount;
  final int correctVentilations;

  // ── App-computed averages ─────────────────────────────────────────────────
  final double averageDepth;           // cm
  final double averageFrequency;       // BPM (from instantaneousRate)
  final double averageEffectiveDepth;  // cm (angle-corrected)

  // ── Glove-side peaks & SD ─────────────────────────────────────────────────
  final double peakDepth;   // cm — maximum single compression this session
  final double depthSD;     // cm — standard deviation of per-compression depths

  // ── App-computed quality metrics ──────────────────────────────────────────
  final double depthConsistency;       // % compressions within target depth range
  final double frequencyConsistency;   // % compressions within target rate range
  final double handsOnRatio;           // active compression time / total time (0–1)
  final double noFlowTime;             // total seconds of unplanned gaps > 2 s
  final int    noFlowIntervals;        // count of unplanned gaps > 2 s
  final double rateVariability;        // std deviation of inter-compression intervals (ms)
  final double timeToFirstCompression; // seconds from SESSION_START to first compression
  final int    consecutiveGoodPeak;    // longest unbroken streak of perfect compressions

  // ── Glove-side fatigue & swap ─────────────────────────────────────────────
  final int fatigueOnsetIndex;  // compression index of first fatigue (0 = none)
  final int rescuerSwapCount;   // TWO_MIN_ALERT events fired this session

  // ── Ventilation ───────────────────────────────────────────────────────────
  final int    ventilationCount;
  final double ventilationCompliance; // % (0–100)

  // ── Pulse check (Emergency only) ──────────────────────────────────────────
  final int  pulseChecksPrompted;
  final int  pulseChecksComplied;
  final bool pulseDetectedFinal;

  // ── Patient biometrics ────────────────────────────────────────────────────
  final double? patientTemperature;

  // ── Rescuer biometrics (from SESSION_END last-pause readings) ─────────────
  final double? rescuerHRLastPause;    // BPM at last ventilation or pulse check pause
  final double? rescuerSpO2LastPause;  // % at last pause

  // ── Ambient temperature (from SESSION_END) ────────────────────────────────
  final double? ambientTempStart; // °C at SESSION_START
  final double? ambientTempEnd;   // °C at SESSION_END

  // ── Session timing ────────────────────────────────────────────────────────
  final int sessionDuration; // seconds

  // ── Grade (Training mode only — always 0.0 for Emergency) ────────────────
  final double totalGrade; // 0–100

  // ── Sub-lists ─────────────────────────────────────────────────────────────
  final List<CompressionEvent>     compressions;
  final List<VentilationEvent>     ventilations;
  final List<PulseCheckEvent>      pulseChecks;
  final List<RescuerVitalSnapshot> rescuerVitals;

  // ── Local sync state ──────────────────────────────────────────────────────
  final bool syncedToBackend;

  // ── User note ─────────────────────────────────────────────────────────────
  final String? note;

  const SessionDetail({
    this.id,
    required this.sessionStart,
    this.sessionEnd,
    this.mode                    = 'emergency',
    this.scenario                = 'standard_adult',
    required this.compressionCount,
    required this.correctDepth,
    required this.correctFrequency,
    required this.correctRecoil,
    required this.depthRateCombo,
    this.correctPosture          = 0,
    this.leaningCount            = 0,
    this.overForceCount          = 0,
    this.tooDeepCount            = 0,
    this.correctVentilations     = 0,
    required this.averageDepth,
    required this.averageFrequency,
    this.averageEffectiveDepth   = 0.0,
    this.peakDepth               = 0.0,
    this.depthSD                 = 0.0,
    this.depthConsistency        = 0.0,
    this.frequencyConsistency    = 0.0,
    this.handsOnRatio            = 1.0,
    this.noFlowTime              = 0.0,
    this.noFlowIntervals         = 0,
    this.rateVariability         = 0.0,
    this.timeToFirstCompression  = 0.0,
    this.consecutiveGoodPeak     = 0,
    this.fatigueOnsetIndex       = 0,
    this.rescuerSwapCount        = 0,
    this.ventilationCount        = 0,
    this.ventilationCompliance   = 0.0,
    this.pulseChecksPrompted     = 0,
    this.pulseChecksComplied     = 0,
    this.pulseDetectedFinal      = false,
    this.patientTemperature,
    this.rescuerHRLastPause,
    this.rescuerSpO2LastPause,
    this.ambientTempStart,
    this.ambientTempEnd,
    required this.sessionDuration,
    this.totalGrade              = 0.0,
    this.compressions            = const [],
    this.ventilations            = const [],
    this.pulseChecks             = const [],
    this.rescuerVitals           = const [],
    this.syncedToBackend         = false,
    this.note,
  });

  // ── Convenience getters ───────────────────────────────────────────────────

  bool get isEmergency       => mode == 'emergency';
  bool get isTraining        => mode == 'training' || mode == 'training_no_feedback';
  bool get isNoFeedback      => mode == 'training_no_feedback';

  /// "3:42"
  String get durationFormatted => Duration(seconds: sessionDuration).mmss;

  /// "8 Mar 2026 • 14:35"
  String get dateTimeFormatted =>
      '${sessionStart.ddMmmYyyy} • ${sessionStart.hhmm}';

  /// "15%"
  String get noFlowPct => '${((1.0 - handsOnRatio) * 100).round()}%';

  /// "85%"
  String get handsOnPct => '${(handsOnRatio * 100).round()}%';

  // ── Factory: assemble from live BLE session ───────────────────────────────
  //
  // Called by SessionService.assembleDetail() when SESSION_END arrives.
  // [summaryPacket] is the ParsedBLEData fields broadcast by BLEConnection.
  // All app-computed metrics are derived here from the accumulated event lists.
  //
  factory SessionDetail.fromBleSession({
    required Map<String, dynamic>       summaryPacket,
    required List<CompressionEvent>     events,
    required List<VentilationEvent>     ventilationEvents,
    required List<PulseCheckEvent>      pulseCheckEvents,
    required List<RescuerVitalSnapshot> rescuerVitalSnapshots,
    required DateTime                   sessionStart,
    required int                        sessionDurationSecs,
    required double                     totalGrade,
    String mode     = 'emergency',
    String scenario = 'standard_adult',
  }) {
    // ── App-computed metrics from compression stream ─────────────────────────

    double depthConsistency     = 0.0;
    double frequencyConsistency = 0.0;
    double timeToFirst          = 0.0;
    double noFlowTime           = 0.0;
    int    noFlowIntervals      = 0;
    double handsOnRatio         = 1.0;
    double rateVariability      = 0.0;
    double avgEffectiveDepth    = 0.0;
    double avgDepth             = 0.0;
    double avgFrequency         = 0.0;   // mean of instantaneousRate
    double depthSD              = 0.0;
    int    consecutiveGoodPeak  = 0;

    if (events.isNotEmpty) {
      final n = events.length;

      // Consistency (uses instantaneousRate via isFrequencyInTarget getter)
      final inDepth = events.where((e) => e.isDepthInTarget).length;
      final inFreq  = events.where((e) => e.isFrequencyInTarget).length;
      depthConsistency     = inDepth / n * 100;
      frequencyConsistency = inFreq  / n * 100;

      // Time to first compression
      timeToFirst = events.first.timestampSec;

      // No-flow time + interval count (gaps > 2 s between consecutive compressions)
      const noFlowThreshold = 2.0;
      if (timeToFirst > noFlowThreshold) {
        noFlowTime += timeToFirst;
        noFlowIntervals++;
      }
      for (int i = 1; i < n; i++) {
        final gap = (events[i].timestampMs - events[i - 1].timestampMs) / 1000.0;
        if (gap > noFlowThreshold) {
          noFlowTime += gap;
          noFlowIntervals++;
        }
      }
      final afterLast = sessionDurationSecs - events.last.timestampSec;
      if (afterLast > noFlowThreshold) {
        noFlowTime += afterLast;
        noFlowIntervals++;
      }

      handsOnRatio = sessionDurationSecs > 0
          ? (1.0 - noFlowTime / sessionDurationSecs).clamp(0.0, 1.0)
          : 1.0;

      // Rate variability — std deviation of inter-compression intervals (ms)
      if (n > 1) {
        final intervals = <double>[];
        for (int i = 1; i < n; i++) {
          intervals.add(
              (events[i].timestampMs - events[i - 1].timestampMs).toDouble());
        }
        final mean     = intervals.reduce((a, b) => a + b) / intervals.length;
        final variance = intervals
            .map((x) => (x - mean) * (x - mean))
            .reduce((a, b) => a + b) /
            intervals.length;
        rateVariability = sqrt(variance);
      }

      // Averages
      avgDepth = events.map((e) => e.depth).reduce((a, b) => a + b) / n;

      // Use instantaneousRate when available; fall back to frequency for older data
      final rateSource = events.first.instantaneousRate > 0
          ? events.map((e) => e.instantaneousRate)
          : events.map((e) => e.frequency);
      avgFrequency = rateSource.reduce((a, b) => a + b) / n;

      avgEffectiveDepth =
          events.map((e) => e.effectiveDepth).reduce((a, b) => a + b) / n;

      // Depth standard deviation
      final depthVariance = events
          .map((e) => (e.depth - avgDepth) * (e.depth - avgDepth))
          .reduce((a, b) => a + b) /
          n;
      depthSD = sqrt(depthVariance);

      // Consecutive good streak
      int streak = 0;
      for (final e in events) {
        if (e.isPerfect) {
          streak++;
          if (streak > consecutiveGoodPeak) consecutiveGoodPeak = streak;
        } else {
          streak = 0;
        }
      }
    }

    // Ventilation compliance
    final vtCount     = ventilationEvents.length;
    final vtCompliant = ventilationEvents.where((v) => v.compliant).length;
    final vtCompliance = vtCount > 0 ? vtCompliant / vtCount * 100.0 : 0.0;

    return SessionDetail(
      sessionStart:           sessionStart,
      mode:                   mode,
      scenario:               scenario,
      compressionCount:       summaryPacket['totalCompressions']  as int?    ?? 0,
      correctDepth:           summaryPacket['correctDepth']        as int?    ?? 0,
      correctFrequency:       summaryPacket['correctFrequency']    as int?    ?? 0,
      correctRecoil:          summaryPacket['correctRecoil']       as int?    ?? 0,
      depthRateCombo:         summaryPacket['depthRateCombo']      as int?    ?? 0,
      correctPosture:         summaryPacket['correctPosture']      as int?    ?? 0,
      leaningCount:           summaryPacket['leaningCount']        as int?    ?? 0,
      overForceCount:         summaryPacket['overForceCount']      as int?    ?? 0,
      tooDeepCount:           summaryPacket['tooDeepCount']        as int?    ?? 0,
      correctVentilations:    summaryPacket['correctVentilations'] as int?    ?? vtCompliant,
      averageDepth:           avgDepth,
      averageFrequency:       avgFrequency,
      averageEffectiveDepth:  avgEffectiveDepth,
      peakDepth:              (summaryPacket['peakDepth']          as num?)?.toDouble() ?? 0.0,
      depthSD:                (summaryPacket['compressionDepthSD'] as num?)?.toDouble() ?? depthSD,
      depthConsistency:       depthConsistency,
      frequencyConsistency:   frequencyConsistency,
      handsOnRatio:           handsOnRatio,
      noFlowTime:             noFlowTime,
      noFlowIntervals:        (summaryPacket['noFlowIntervals']    as int?)   ?? noFlowIntervals,
      rateVariability:        rateVariability,
      timeToFirstCompression: timeToFirst,
      consecutiveGoodPeak:    consecutiveGoodPeak,
      fatigueOnsetIndex:      summaryPacket['fatigueOnsetIndex']   as int?    ?? 0,
      rescuerSwapCount:       summaryPacket['rescuerSwapCount']    as int?    ?? 0,
      ventilationCount:       summaryPacket['totalVentilations']   as int?    ?? vtCount,
      ventilationCompliance:  vtCompliance,
      pulseChecksPrompted:    summaryPacket['pulseChecksPrompted'] as int?    ?? 0,
      pulseChecksComplied:    summaryPacket['pulseChecksComplied'] as int?    ?? 0,
      pulseDetectedFinal:     (summaryPacket['pulseDetected']      as int?    ?? 0) == 1,
      patientTemperature:     (summaryPacket['patientTemperature'] as num?)?.toDouble(),
      rescuerHRLastPause:     (summaryPacket['rescuerHRLastPause'] as num?)?.toDouble(),
      rescuerSpO2LastPause:   (summaryPacket['rescuerSpO2LastPause'] as num?)?.toDouble(),
      ambientTempStart:       (summaryPacket['ambientTempStart']   as num?)?.toDouble(),
      ambientTempEnd:         (summaryPacket['ambientTempEnd']     as num?)?.toDouble(),
      sessionDuration:        sessionDurationSecs,
      // Emergency sessions never have a grade — enforced here and on the backend
      totalGrade:             mode == 'emergency' ? 0.0 : totalGrade,
      compressions:           events,
      ventilations:           ventilationEvents,
      pulseChecks:            pulseCheckEvents,
      rescuerVitals:          rescuerVitalSnapshots,
      syncedToBackend:        false,
    );
  }

  // ── JSON factory — hydrate from backend GET /sessions/:id/detail ──────────
  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    return SessionDetail(
      id:           json['id']          as int?,
      sessionStart: DateTime.parse(json['session_start'] as String),
      sessionEnd:   json['session_end'] != null
          ? DateTime.tryParse(json['session_end'] as String)
          : null,
      mode:                   json['mode']                      as String? ?? 'emergency',
      scenario:               json['scenario']                  as String? ?? 'standard_adult',
      compressionCount:       (json['compression_count']        as num).toInt(),
      correctDepth:           (json['correct_depth']            as num).toInt(),
      correctFrequency:       (json['correct_frequency']        as num).toInt(),
      correctRecoil:          (json['correct_recoil']           as num?)?.toInt()    ?? 0,
      depthRateCombo:         (json['depth_rate_combo']         as num?)?.toInt()    ?? 0,
      correctPosture:         (json['correct_posture']          as num?)?.toInt()    ?? 0,
      leaningCount:           (json['leaning_count']            as num?)?.toInt()    ?? 0,
      overForceCount:         (json['over_force_count']         as num?)?.toInt()    ?? 0,
      tooDeepCount:           (json['too_deep_count']           as num?)?.toInt()    ?? 0,
      correctVentilations:    (json['correct_ventilations']     as num?)?.toInt()    ?? 0,
      averageDepth:           (json['average_depth']            as num?)?.toDouble() ?? 0.0,
      averageFrequency:       (json['average_frequency']        as num?)?.toDouble() ?? 0.0,
      averageEffectiveDepth:  (json['average_effective_depth']  as num?)?.toDouble() ?? 0.0,
      peakDepth:              (json['peak_depth']               as num?)?.toDouble() ?? 0.0,
      depthSD:                (json['depth_sd']                 as num?)?.toDouble() ?? 0.0,
      depthConsistency:       (json['depth_consistency']        as num?)?.toDouble() ?? 0.0,
      frequencyConsistency:   (json['freq_consistency']         as num?)?.toDouble() ?? 0.0,
      handsOnRatio:           (json['hands_on_ratio']           as num?)?.toDouble() ?? 1.0,
      noFlowTime:             (json['no_flow_time']             as num?)?.toDouble() ?? 0.0,
      noFlowIntervals:        (json['no_flow_intervals']        as num?)?.toInt()    ?? 0,
      rateVariability:        (json['rate_variability']         as num?)?.toDouble() ?? 0.0,
      timeToFirstCompression: (json['time_to_first_comp']       as num?)?.toDouble() ?? 0.0,
      consecutiveGoodPeak:    (json['consecutive_good_peak']    as num?)?.toInt()    ?? 0,
      fatigueOnsetIndex:      (json['fatigue_onset_index']      as num?)?.toInt()    ?? 0,
      rescuerSwapCount:       (json['rescuer_swap_count']       as num?)?.toInt()    ?? 0,
      ventilationCount:       (json['ventilation_count']        as num?)?.toInt()    ?? 0,
      ventilationCompliance:  (json['ventilation_compliance']   as num?)?.toDouble() ?? 0.0,
      pulseChecksPrompted:    (json['pulse_checks_prompted']    as num?)?.toInt()    ?? 0,
      pulseChecksComplied:    (json['pulse_checks_complied']    as num?)?.toInt()    ?? 0,
      pulseDetectedFinal:      json['pulse_detected_final']     as bool?             ?? false,
      patientTemperature:     (json['patient_temperature']      as num?)?.toDouble(),
      rescuerHRLastPause:     (json['rescuer_hr_last_pause']    as num?)?.toDouble(),
      rescuerSpO2LastPause:   (json['rescuer_spo2_last_pause']  as num?)?.toDouble(),
      ambientTempStart:       (json['ambient_temp_start']       as num?)?.toDouble(),
      ambientTempEnd:         (json['ambient_temp_end']         as num?)?.toDouble(),
      sessionDuration:        (json['session_duration']         as num).toInt(),
      totalGrade:             (json['total_grade']              as num?)?.toDouble() ?? 0.0,
      compressions: (json['compressions'] as List<dynamic>? ?? [])
          .map((e) => CompressionEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      ventilations: (json['ventilations'] as List<dynamic>? ?? [])
          .map((e) => VentilationEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      pulseChecks: (json['pulse_checks'] as List<dynamic>? ?? [])
          .map((e) => PulseCheckEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      rescuerVitals: (json['rescuer_vitals'] as List<dynamic>? ?? [])
          .map((e) => RescuerVitalSnapshot.fromJson(e as Map<String, dynamic>))
          .toList(),
      syncedToBackend: json['synced_to_backend'] as bool? ?? true,
      note:            json['note']              as String?,
    );
  }

  // ── Serialisation — sent to backend via POST /sessions/detail ────────────
  Map<String, dynamic> toJson() => {
    if (id != null) 'id':              id,
    'session_start':            sessionStart.toIso8601String(),
    if (sessionEnd != null) 'session_end': sessionEnd!.toIso8601String(),
    'mode':                     mode,
    'scenario':                 scenario,
    'compression_count':        compressionCount,
    'correct_depth':            correctDepth,
    'correct_frequency':        correctFrequency,
    'correct_recoil':           correctRecoil,
    'depth_rate_combo':         depthRateCombo,
    'correct_posture':          correctPosture,
    'leaning_count':            leaningCount,
    'over_force_count':         overForceCount,
    'too_deep_count':           tooDeepCount,
    'correct_ventilations':     correctVentilations,
    'average_depth':            averageDepth,
    'average_frequency':        averageFrequency,
    'average_effective_depth':  averageEffectiveDepth,
    'peak_depth':               peakDepth,
    'depth_sd':                 depthSD,
    'depth_consistency':        depthConsistency,
    'freq_consistency':         frequencyConsistency,
    'hands_on_ratio':           handsOnRatio,
    'no_flow_time':             noFlowTime,
    'no_flow_intervals':        noFlowIntervals,
    'rate_variability':         rateVariability,
    'time_to_first_comp':       timeToFirstCompression,
    'consecutive_good_peak':    consecutiveGoodPeak,
    'fatigue_onset_index':      fatigueOnsetIndex,
    'rescuer_swap_count':       rescuerSwapCount,
    'ventilation_count':        ventilationCount,
    'ventilation_compliance':   ventilationCompliance,
    'pulse_checks_prompted':    pulseChecksPrompted,
    'pulse_checks_complied':    pulseChecksComplied,
    'pulse_detected_final':     pulseDetectedFinal,
    if (patientTemperature   != null) 'patient_temperature':    patientTemperature,
    if (rescuerHRLastPause   != null) 'rescuer_hr_last_pause':  rescuerHRLastPause,
    if (rescuerSpO2LastPause != null) 'rescuer_spo2_last_pause': rescuerSpO2LastPause,
    if (ambientTempStart     != null) 'ambient_temp_start':     ambientTempStart,
    if (ambientTempEnd       != null) 'ambient_temp_end':       ambientTempEnd,
    'session_duration':         sessionDuration,
    'total_grade':              totalGrade,
    'compressions':    compressions.map((e)  => e.toJson()).toList(),
    'ventilations':    ventilations.map((e)  => e.toJson()).toList(),
    'pulse_checks':    pulseChecks.map((e)   => e.toJson()).toList(),
    'rescuer_vitals':  rescuerVitals.map((e) => e.toJson()).toList(),
    'synced_from_local': false,
    'synced_to_backend': syncedToBackend,
    if (note != null) 'note': note,
  };

  // ── Copy helpers ──────────────────────────────────────────────────────────

  SessionDetail markSynced() => _copyWith(syncedToBackend: true);

  SessionDetail withNote(String? newNote) => _copyWith(note: newNote);

  SessionDetail _copyWith({bool? syncedToBackend, String? note}) =>
      SessionDetail(
        id:                     id,
        sessionStart:           sessionStart,
        sessionEnd:             sessionEnd,
        mode:                   mode,
        scenario:               scenario,
        compressionCount:       compressionCount,
        correctDepth:           correctDepth,
        correctFrequency:       correctFrequency,
        correctRecoil:          correctRecoil,
        depthRateCombo:         depthRateCombo,
        correctPosture:         correctPosture,
        leaningCount:           leaningCount,
        overForceCount:         overForceCount,
        tooDeepCount:           tooDeepCount,
        correctVentilations:    correctVentilations,
        averageDepth:           averageDepth,
        averageFrequency:       averageFrequency,
        averageEffectiveDepth:  averageEffectiveDepth,
        peakDepth:              peakDepth,
        depthSD:                depthSD,
        depthConsistency:       depthConsistency,
        frequencyConsistency:   frequencyConsistency,
        handsOnRatio:           handsOnRatio,
        noFlowTime:             noFlowTime,
        noFlowIntervals:        noFlowIntervals,
        rateVariability:        rateVariability,
        timeToFirstCompression: timeToFirstCompression,
        consecutiveGoodPeak:    consecutiveGoodPeak,
        fatigueOnsetIndex:      fatigueOnsetIndex,
        rescuerSwapCount:       rescuerSwapCount,
        ventilationCount:       ventilationCount,
        ventilationCompliance:  ventilationCompliance,
        pulseChecksPrompted:    pulseChecksPrompted,
        pulseChecksComplied:    pulseChecksComplied,
        pulseDetectedFinal:     pulseDetectedFinal,
        patientTemperature:     patientTemperature,
        rescuerHRLastPause:     rescuerHRLastPause,
        rescuerSpO2LastPause:   rescuerSpO2LastPause,
        ambientTempStart:       ambientTempStart,
        ambientTempEnd:         ambientTempEnd,
        sessionDuration:        sessionDuration,
        totalGrade:             totalGrade,
        compressions:           compressions,
        ventilations:           ventilations,
        pulseChecks:            pulseChecks,
        rescuerVitals:          rescuerVitals,
        syncedToBackend:        syncedToBackend ?? this.syncedToBackend,
        note:                   note ?? this.note,
      );
}