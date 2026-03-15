import 'dart:math' show sqrt;

import 'package:cpr_assist/features/training/services/rescuer_vital_snapshot.dart';

import '../../../core/utils/app_extensions.dart';
import 'compression_event.dart';
import 'ventilation_event.dart';
import 'pulse_check_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionDetail  —  Complete session record per BLE Spec v2.0 Section 7.5
//
// Flow:
//   BLE start-ping  → BLE service clears all event lists
//   BLE live stream → events accumulated in BLEConnection
//   BLE end-ping    → SessionDetail.fromBleSession() assembles everything
//   Grade screen    → receives SessionDetail, renders results
//   Backend         → SessionDetail.toJson() posted to /sessions/detail
//   History screen  → SessionDetail.fromJson() hydrated from backend
// ─────────────────────────────────────────────────────────────────────────────

class SessionDetail {
  // ── Identity ──────────────────────────────────────────────────────────────
  final int?      id;
  final DateTime  sessionStart;
  final DateTime? sessionEnd;

  // ── Mode ──────────────────────────────────────────────────────────────────
  /// "emergency" | "training" | "training_no_feedback"
  final String mode;

  // ── Glove-side totals (from SESSION_END) ──────────────────────────────────
  final int compressionCount;
  final int correctDepth;
  final int correctFrequency;
  final int correctRecoil;
  final int depthRateCombo;
  final int correctPosture;
  final int leaningCount;
  final int overForceCount;
  final int tooDeepCount;

  // ── App-computed averages ─────────────────────────────────────────────────
  final double averageDepth;           // cm
  final double averageFrequency;       // BPM
  final double averageEffectiveDepth;  // cm (angle-corrected)
  final double averageForce;           // Newtons

  // ── Glove-side peak ───────────────────────────────────────────────────────
  final double peakDepth;              // cm

  // ── App-computed quality metrics ──────────────────────────────────────────
  final double depthConsistency;       // % compressions in 5–6 cm
  final double frequencyConsistency;   // % in 100–120 BPM
  final double handsOnRatio;           // active time / total time (0–1)
  final double noFlowTime;             // seconds of gaps > 2 s
  final double rateVariability;        // std deviation of inter-comp intervals
  final double timeToFirstCompression; // seconds from session start
  final int    consecutiveGoodPeak;    // best unbroken streak of perfect compressions

  // ── Glove-side fatigue ────────────────────────────────────────────────────
  final int fatigueOnsetIndex;         // 0 = no fatigue this session

  // ── Ventilation ───────────────────────────────────────────────────────────
  final int    ventilationCount;
  final double ventilationCompliance;  // % (0–100)

  // ── Pulse check (Emergency only) ──────────────────────────────────────────
  final int  pulseChecksPrompted;
  final int  pulseChecksComplied;
  final bool pulseDetectedFinal;

  // ── Patient / rescuer biometrics ──────────────────────────────────────────
  final double? patientTemperature;
  final int?    userHeartRate;
  final double? userTemperature;

  // ── Session timing ─────────────────────────────────────────────────────────
  final int sessionDuration; // seconds

  // ── Grade ─────────────────────────────────────────────────────────────────
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
    required this.compressionCount,
    required this.correctDepth,
    required this.correctFrequency,
    required this.correctRecoil,
    required this.depthRateCombo,
    this.correctPosture          = 0,
    this.leaningCount            = 0,
    this.overForceCount          = 0,
    this.tooDeepCount            = 0,
    required this.averageDepth,
    required this.averageFrequency,
    this.averageEffectiveDepth   = 0.0,
    this.averageForce            = 0.0,
    this.peakDepth               = 0.0,
    this.depthConsistency        = 0.0,
    this.frequencyConsistency    = 0.0,
    this.handsOnRatio            = 1.0,
    this.noFlowTime              = 0.0,
    this.rateVariability         = 0.0,
    this.timeToFirstCompression  = 0.0,
    this.consecutiveGoodPeak     = 0,
    this.fatigueOnsetIndex       = 0,
    this.ventilationCount        = 0,
    this.ventilationCompliance   = 0.0,
    this.pulseChecksPrompted     = 0,
    this.pulseChecksComplied     = 0,
    this.pulseDetectedFinal      = false,
    this.patientTemperature,
    this.userHeartRate,
    this.userTemperature,
    required this.sessionDuration,
    this.totalGrade              = 0.0,
    this.compressions            = const [],
    this.ventilations            = const [],
    this.pulseChecks             = const [],
    this.rescuerVitals           = const [],
    this.syncedToBackend         = false,
    this.note,
  });

  // ── Derived helpers ───────────────────────────────────────────────────────

  /// "3:42"
  String get durationFormatted => Duration(seconds: sessionDuration).mmss;

  /// "8 Mar 2026 • 14:35"
  String get dateTimeFormatted =>
      '${sessionStart.ddMmmYyyy} • ${sessionStart.hhmm}';

  /// e.g. "15%"
  String get noFlowPct => '${((1.0 - handsOnRatio) * 100).round()}%';

  /// e.g. "85%"
  String get handsOnPct => '${(handsOnRatio * 100).round()}%';

  // ── Factory: assemble from BLE session ────────────────────────────────────

  factory SessionDetail.fromBleSession({
    required Map<String, dynamic>       summaryPacket,
    required List<CompressionEvent>     events,
    required List<VentilationEvent>     ventilationEvents,
    required List<PulseCheckEvent>      pulseCheckEvents,
    required List<RescuerVitalSnapshot> rescuerVitalSnapshots,
    required DateTime                   sessionStart,
    required int                        sessionDurationSecs,
    required double                     totalGrade,
    String mode = 'emergency',
  }) {
    // ── App-computed metrics from compression stream ───────────────────────

    double depthConsistency     = 0.0;
    double frequencyConsistency = 0.0;
    double timeToFirst          = 0.0;
    double noFlowTime           = 0.0;
    double handsOnRatio         = 1.0;
    double rateVariability      = 0.0;
    double avgEffectiveDepth    = 0.0;
    double avgForce             = 0.0;
    double avgDepth             = 0.0;
    double avgFrequency         = 0.0;
    int    consecutiveGoodPeak  = 0;

    if (events.isNotEmpty) {
      final n = events.length;

      // Consistency
      final inDepth = events.where((e) => e.isDepthInTarget).length;
      final inFreq  = events.where((e) => e.isFrequencyInTarget).length;
      depthConsistency     = inDepth / n * 100;
      frequencyConsistency = inFreq  / n * 100;

      // Time to first compression
      timeToFirst = events.first.timestampSec;

      // No-flow time (gaps > 2 s between consecutive compressions)
      const noFlowThreshold = 2.0;
      for (int i = 1; i < n; i++) {
        final gap =
            (events[i].timestampMs - events[i - 1].timestampMs) / 1000.0;
        if (gap > noFlowThreshold) noFlowTime += gap;
      }
      // Count time before first compression and after last compression
      if (timeToFirst > noFlowThreshold) noFlowTime += timeToFirst;
      final afterLast = sessionDurationSecs - events.last.timestampSec;
      if (afterLast > noFlowThreshold) noFlowTime += afterLast;

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
        final mean = intervals.reduce((a, b) => a + b) / intervals.length;
        final variance = intervals
            .map((x) => (x - mean) * (x - mean))
            .reduce((a, b) => a + b) /
            intervals.length;
        rateVariability = sqrt(variance);
      }

      // Averages
      avgDepth          = events.map((e) => e.depth).reduce((a, b) => a + b) / n;
      avgFrequency      = events.map((e) => e.frequency).reduce((a, b) => a + b) / n;
      avgEffectiveDepth = events.map((e) => e.effectiveDepth).reduce((a, b) => a + b) / n;
      avgForce          = events.map((e) => e.force).reduce((a, b) => a + b) / n;

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
    final vtCompliance =
    vtCount > 0 ? vtCompliant / vtCount * 100.0 : 0.0;

    return SessionDetail(
      sessionStart:           sessionStart,
      mode:                   mode,
      compressionCount:       summaryPacket['totalCompressions'] as int?    ?? 0,
      correctDepth:           summaryPacket['correctDepth']      as int?    ?? 0,
      correctFrequency:       summaryPacket['correctFrequency']  as int?    ?? 0,
      correctRecoil:          summaryPacket['correctRecoil']     as int?    ?? 0,
      depthRateCombo:         summaryPacket['depthRateCombo']    as int?    ?? 0,
      correctPosture:         summaryPacket['correctPosture']    as int?    ?? 0,
      leaningCount:           summaryPacket['leaningCount']      as int?    ?? 0,
      overForceCount:         summaryPacket['overForceCount']    as int?    ?? 0,
      tooDeepCount:           summaryPacket['tooDeepCount']      as int?    ?? 0,
      averageDepth:           avgDepth,
      averageFrequency:       avgFrequency,
      averageEffectiveDepth:  avgEffectiveDepth,
      averageForce:           avgForce,
      peakDepth:              (summaryPacket['peakDepth'] as num?)?.toDouble() ?? 0.0,
      depthConsistency:       depthConsistency,
      frequencyConsistency:   frequencyConsistency,
      handsOnRatio:           handsOnRatio,
      noFlowTime:             noFlowTime,
      rateVariability:        rateVariability,
      timeToFirstCompression: timeToFirst,
      consecutiveGoodPeak:    consecutiveGoodPeak,
      fatigueOnsetIndex:      summaryPacket['fatigueOnsetIndex'] as int?    ?? 0,
      ventilationCount:       summaryPacket['totalVentilations'] as int?    ?? vtCount,
      ventilationCompliance:  vtCompliance,
      pulseChecksPrompted:    summaryPacket['pulseChecksPrompted'] as int?  ?? 0,
      pulseChecksComplied:    summaryPacket['pulseChecksComplied'] as int?  ?? 0,
      pulseDetectedFinal:     (summaryPacket['pulseDetected']     as int?   ?? 0) == 1,
      patientTemperature:     (summaryPacket['patientTemperature'] as num?)?.toDouble(),
      userHeartRate:          summaryPacket['userHeartRate']      as int?,
      userTemperature:        (summaryPacket['userTemperature']   as num?)?.toDouble(),
      sessionDuration:        sessionDurationSecs,
      totalGrade:             totalGrade,
      compressions:           events,
      ventilations:           ventilationEvents,
      pulseChecks:            pulseCheckEvents,
      rescuerVitals:          rescuerVitalSnapshots,
      syncedToBackend:        false,
    );
  }

  // ── JSON ──────────────────────────────────────────────────────────────────

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    return SessionDetail(
      id:           json['id']           as int?,
      sessionStart: DateTime.parse(json['session_start'] as String),
      sessionEnd:   json['session_end'] != null
          ? DateTime.tryParse(json['session_end'] as String)
          : null,
      mode:                   json['mode']                     as String? ?? 'emergency',
      compressionCount:       (json['compression_count']       as num).toInt(),
      correctDepth:           (json['correct_depth']           as num).toInt(),
      correctFrequency:       (json['correct_frequency']       as num).toInt(),
      correctRecoil:          (json['correct_recoil']          as num?)?.toInt()    ?? 0,
      depthRateCombo:         (json['depth_rate_combo']        as num?)?.toInt()    ?? 0,
      correctPosture:         (json['correct_posture']         as num?)?.toInt()    ?? 0,
      leaningCount:           (json['leaning_count']           as num?)?.toInt()    ?? 0,
      overForceCount:         (json['over_force_count']        as num?)?.toInt()    ?? 0,
      tooDeepCount:           (json['too_deep_count']          as num?)?.toInt()    ?? 0,
      averageDepth:           (json['average_depth']           as num?)?.toDouble() ?? 0.0,
      averageFrequency:       (json['average_frequency']       as num?)?.toDouble() ?? 0.0,
      averageEffectiveDepth:  (json['average_effective_depth'] as num?)?.toDouble() ?? 0.0,
      averageForce:           (json['average_force']           as num?)?.toDouble() ?? 0.0,
      peakDepth:              (json['peak_depth']              as num?)?.toDouble() ?? 0.0,
      depthConsistency:       (json['depth_consistency']       as num?)?.toDouble() ?? 0.0,
      frequencyConsistency:   (json['freq_consistency']        as num?)?.toDouble() ?? 0.0,
      handsOnRatio:           (json['hands_on_ratio']          as num?)?.toDouble() ?? 1.0,
      noFlowTime:             (json['no_flow_time']            as num?)?.toDouble() ?? 0.0,
      rateVariability:        (json['rate_variability']        as num?)?.toDouble() ?? 0.0,
      timeToFirstCompression: (json['time_to_first_comp']      as num?)?.toDouble() ?? 0.0,
      consecutiveGoodPeak:    (json['consecutive_good_peak']   as num?)?.toInt()    ?? 0,
      fatigueOnsetIndex:      (json['fatigue_onset_index']     as num?)?.toInt()    ?? 0,
      ventilationCount:       (json['ventilation_count']       as num?)?.toInt()    ?? 0,
      ventilationCompliance:  (json['ventilation_compliance']  as num?)?.toDouble() ?? 0.0,
      pulseChecksPrompted:    (json['pulse_checks_prompted']   as num?)?.toInt()    ?? 0,
      pulseChecksComplied:    (json['pulse_checks_complied']   as num?)?.toInt()    ?? 0,
      pulseDetectedFinal:      json['pulse_detected_final']    as bool?             ?? false,
      patientTemperature:     (json['patient_temperature']     as num?)?.toDouble(),
      userHeartRate:          (json['user_heart_rate']         as num?)?.toInt(),
      userTemperature:        (json['user_temperature']        as num?)?.toDouble(),
      sessionDuration:        (json['session_duration']        as num).toInt(),
      totalGrade:             (json['total_grade']             as num?)?.toDouble() ?? 0.0,
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

  Map<String, dynamic> toJson() => {
    if (id != null) 'id':              id,
    'session_start':           sessionStart.toIso8601String(),
    if (sessionEnd != null) 'session_end': sessionEnd!.toIso8601String(),
    'mode':                    mode,
    'compression_count':       compressionCount,
    'correct_depth':           correctDepth,
    'correct_frequency':       correctFrequency,
    'correct_recoil':          correctRecoil,
    'depth_rate_combo':        depthRateCombo,
    'correct_posture':         correctPosture,
    'leaning_count':           leaningCount,
    'over_force_count':        overForceCount,
    'too_deep_count':          tooDeepCount,
    'average_depth':           averageDepth,
    'average_frequency':       averageFrequency,
    'average_effective_depth': averageEffectiveDepth,
    'average_force':           averageForce,
    'peak_depth':              peakDepth,
    'depth_consistency':       depthConsistency,
    'freq_consistency':        frequencyConsistency,
    'hands_on_ratio':          handsOnRatio,
    'no_flow_time':            noFlowTime,
    'rate_variability':        rateVariability,
    'time_to_first_comp':      timeToFirstCompression,
    'consecutive_good_peak':   consecutiveGoodPeak,
    'fatigue_onset_index':     fatigueOnsetIndex,
    'ventilation_count':       ventilationCount,
    'ventilation_compliance':  ventilationCompliance,
    'pulse_checks_prompted':   pulseChecksPrompted,
    'pulse_checks_complied':   pulseChecksComplied,
    'pulse_detected_final':    pulseDetectedFinal,
    if (patientTemperature != null) 'patient_temperature': patientTemperature,
    if (userHeartRate      != null) 'user_heart_rate':     userHeartRate,
    if (userTemperature    != null) 'user_temperature':    userTemperature,
    'session_duration':        sessionDuration,
    'total_grade':             totalGrade,
    'compressions':    compressions.map((e)  => e.toJson()).toList(),
    'ventilations':    ventilations.map((e)  => e.toJson()).toList(),
    'pulse_checks':    pulseChecks.map((e)   => e.toJson()).toList(),
    'rescuer_vitals':  rescuerVitals.map((e) => e.toJson()).toList(),
    'synced_to_backend': syncedToBackend,
    if (note != null) 'note': note,
  };

  // ── Copy helpers ──────────────────────────────────────────────────────────

  SessionDetail markSynced() => _copyWith(syncedToBackend: true);

  SessionDetail withNote(String? newNote) => _copyWith(note: newNote);

  SessionDetail _copyWith({bool? syncedToBackend, String? note}) =>
      SessionDetail(
        id: id, sessionStart: sessionStart, sessionEnd: sessionEnd,
        mode: mode, compressionCount: compressionCount,
        correctDepth: correctDepth, correctFrequency: correctFrequency,
        correctRecoil: correctRecoil, depthRateCombo: depthRateCombo,
        correctPosture: correctPosture, leaningCount: leaningCount,
        overForceCount: overForceCount, tooDeepCount: tooDeepCount,
        averageDepth: averageDepth, averageFrequency: averageFrequency,
        averageEffectiveDepth: averageEffectiveDepth, averageForce: averageForce,
        peakDepth: peakDepth, depthConsistency: depthConsistency,
        frequencyConsistency: frequencyConsistency, handsOnRatio: handsOnRatio,
        noFlowTime: noFlowTime, rateVariability: rateVariability,
        timeToFirstCompression: timeToFirstCompression,
        consecutiveGoodPeak: consecutiveGoodPeak,
        fatigueOnsetIndex: fatigueOnsetIndex,
        ventilationCount: ventilationCount,
        ventilationCompliance: ventilationCompliance,
        pulseChecksPrompted: pulseChecksPrompted,
        pulseChecksComplied: pulseChecksComplied,
        pulseDetectedFinal: pulseDetectedFinal,
        patientTemperature: patientTemperature,
        userHeartRate: userHeartRate, userTemperature: userTemperature,
        sessionDuration: sessionDuration, totalGrade: totalGrade,
        compressions: compressions, ventilations: ventilations,
        pulseChecks: pulseChecks, rescuerVitals: rescuerVitals,
        syncedToBackend: syncedToBackend ?? this.syncedToBackend,
        note: note ?? this.note,
      );
}