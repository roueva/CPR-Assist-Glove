import 'dart:math' show sqrt;
import 'dart:math' as math;
import 'package:cpr_assist/features/training/services/rescuer_vital_snapshot.dart';

import '../../../core/utils/app_constants.dart';
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

  /// "standard_adult" | "pediatric"
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

  /// Total seconds without active chest compressions.
  /// Includes planned ventilation and pulse-check pauses.
  final double noFlowTime;

  /// Count of no-compression gaps > 2 seconds.
  /// Includes planned ventilation and pulse-check pauses.
  final int noFlowIntervals;

  /// Total seconds of no-compression gaps > 2 seconds that do NOT overlap
  /// ventilation windows or pulse-check windows.
  final double unplannedPauseTime;

  /// Count of no-compression gaps > 2 seconds that do NOT overlap
  /// ventilation windows or pulse-check windows.
  final int unplannedPauseCount;

  final double rateVariability;        // std deviation of inter-compression intervals (ms)
  final double timeToFirstCompression; // seconds from SESSION_START to first compression
  final int    consecutiveGoodPeak;    // longest unbroken streak of perfect compressions

  // ── Glove-side fatigue & swap ─────────────────────────────────────────────
  final int fatigueOnsetIndex;  // compression index of first fatigue (0 = none)
  final int rescuerSwapCount;   // TWO_MIN_ALERT events fired this session

  /// Session-relative timestamp (ms) of the FATIGUE_ALERT event.
  /// Null if fatigue was not detected this session.
  /// Independent from fatigueOnsetIndex — the firmware fires both at the same
  /// moment, but onsetIndex counts compressions and this counts ms.
  final int? fatigueAlertTimestampMs;

  /// Fatigue score (0–100) at the moment FATIGUE_ALERT fired. Null if not fired.
  final int? fatigueAlertScore;

  /// Session-relative timestamps (ms) of each TWO_MIN_ALERT event.
  /// Length should equal rescuerSwapCount; if shorter, the firmware fired more
  /// alerts than the app captured (e.g. session was reconstructed from offline storage).
  final List<int> twoMinAlertTimestampsMs;

  // ── Ventilation ───────────────────────────────────────────────────────────
  final int    ventilationCount;
  final double ventilationCompliance; // % (0–100)

  // ── Pulse check (Emergency only) ──────────────────────────────────────────
  final int  pulseChecksPrompted;
  final int  pulseChecksComplied;
  final bool pulseDetectedFinal;

  /// Last valid patient SpO₂ from pulse check windows. Null if never captured.
  double? get patientSpO2LastCheck {
    for (final check in pulseChecks.reversed) {
      if (check.patientSpO2 > 0) {
        return check.patientSpO2;
      }
    }
    return null;
  }

  // ── Patient biometrics ────────────────────────────────────────────────────
  final double? patientTemperature;

  // ── Rescuer biometrics (from SESSION_END last-pause readings) ─────────────
  final double? rescuerHRLastPause;    // BPM at last ventilation or pulse check pause
  final double? rescuerSpO2LastPause;  // % at last pause

  // ── Rescuer wrist temperature snapshots (from SESSION_END) ────────────────
  final double? rescuerWristTempStart; // °C at SESSION_START
  final double? rescuerWristTempEnd;   // °C at SESSION_END

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
    this.unplannedPauseTime      = 0.0,
    this.unplannedPauseCount     = 0,
    this.timeToFirstCompression  = 0.0,
    this.consecutiveGoodPeak     = 0,
    this.fatigueOnsetIndex       = 0,
    this.rescuerSwapCount        = 0,
    this.fatigueAlertTimestampMs,
    this.fatigueAlertScore,
    this.twoMinAlertTimestampsMs = const [],
    this.ventilationCount        = 0,
    this.ventilationCompliance   = 0.0,
    this.pulseChecksPrompted     = 0,
    this.pulseChecksComplied     = 0,
    this.pulseDetectedFinal      = false,
    this.patientTemperature,
    this.rescuerHRLastPause,
    this.rescuerSpO2LastPause,
    this.rescuerWristTempStart,
    this.rescuerWristTempEnd,
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

 /// App-computed fatigue score 0–100.
  /// Returns 0 if insufficient data (< 2 vital snapshots).
  static int computeFatigueScore(
      List<RescuerVitalSnapshot> vitals,
      List<CompressionEvent> compressions,
      ) {
    if (vitals.length < 2) return 0;

    // ── 1. HR trend ───────────────────────────────────────────────
    final firstHR = vitals.first.heartRate;
    final lastHR  = vitals.last.heartRate;
    final hrScore = ((lastHR - firstHR) / 40.0).clamp(0.0, 1.0) * 100;

    // ── 2. RMSSD decline ─────────────────────────────────────────
    final firstRMSSD = vitals.first.rmssd.toDouble();
    final lastRMSSD  = vitals.last.rmssd.toDouble();
    final rmssdScore = firstRMSSD > 0
        ? ((firstRMSSD - lastRMSSD) / firstRMSSD).clamp(0.0, 1.0) * 100
        : 0.0;

    // ── 3. Depth trend ────────────────────────────────────────────
    double depthScore = 0.0;
    // Exclude unmeasured compressions (NaN depth sentinel set by
    // BLEConnection when a compression was counted but no valid depth
    // packet arrived) so a single dropout cannot NaN the fatigue score.
    final _finiteComps =
    compressions.where((c) => c.depth.isFinite && c.depth > 0).toList();
    if (_finiteComps.length >= 5) {
      final peakDepth = _finiteComps
          .map((c) => c.depth)
          .reduce((a, b) => a > b ? a : b);
      final lastFive = _finiteComps.sublist(_finiteComps.length - 5);
      final lastAvg  =
          lastFive.map((c) => c.depth).reduce((a, b) => a + b) / 5;
      depthScore = ((peakDepth - lastAvg) / 2.0).clamp(0.0, 1.0) * 100;
    }

    return (hrScore * 0.40 + rmssdScore * 0.35 + depthScore * 0.25).round();
  }



  /// The single authoritative pause/ventilation computation. Recomputes
  /// noFlowTime / unplannedPause* from the compression timeline and stamps
  /// each ventilation's measured no-flow duration + compliance.
  ///
  /// Called once per session by BOTH the live BLE path (via SessionService)
  /// and the offline-storage path (OfflineSessionParser) so every session,
  /// regardless of origin, is scored by identical code and is comparable.
  /// Firmware-stored ventilation windowMs is intentionally NOT used: it
  /// measures a different quantity (prompt→close window incl. grace + resume
  /// latency) and does not implement the AHA excess rule.
  static SessionDetail applyPauseModel(SessionDetail d) {
    final pm = _calculatePauseMetrics(
      compressions:        d.compressions,
      ventilations:        d.ventilations,
      pulseChecks:         d.pulseChecks,
      sessionDurationSecs: d.sessionDuration,
    );

    final measuredVents = d.ventilations.map((v) {
      final dur = pm.ventDurationByTsMs[v.timestampMs];
      if (dur == null) {
        // Prompt fired but no qualifying no-flow gap → rescuer never paused
        // for this ventilation. Zero duration, non-compliant.
        return v.copyWith(durationSec: 0.0, compliant: false);
      }
      // The ventilation event represents only the compliant portion. Any
      // overrun beyond the allowance is surfaced separately as an unplanned
      // pause (Behavior Y), so the displayed vent duration is capped here to
      // avoid double-representing the same hands-off time.
      final cappedDur = dur <= AppConstants.maxAcceptablePauseSec
          ? dur
          : AppConstants.maxAcceptablePauseSec;
      // Compliant only when the rescuer ACTUALLY paused (>= 3 s, matching
      // firmware WINDOW_PAUSE_COMPLIANT_MS) AND did not overrun the 10 s
      // allowance. A sub-3 s blip is too short to have delivered breaths.
      return v.copyWith(
        durationSec: cappedDur,
        compliant:   dur >= AppConstants.minCompliantPauseSec &&
            dur <= AppConstants.maxAcceptablePauseSec,
      );
    }).toList();

    // Same rule as ventilation, applied to pulse checks. pulseDurationByTsMs
    // is keyed by (timestampSec * 1000).round() in _calculatePauseMetrics.
    final measuredPulses = d.pulseChecks.map((p) {
      final key = (p.timestampSec * 1000).round();
      final dur = pm.pulseDurationByTsMs[key];
      if (dur == null) {
        return p.copyWith(durationSec: 0.0, compliant: false);
      }
      final cappedDur = dur <= AppConstants.maxAcceptablePauseSec
          ? dur
          : AppConstants.maxAcceptablePauseSec;
      return p.copyWith(
        durationSec: cappedDur,
        compliant:   dur >= AppConstants.minCompliantPauseSec &&
            dur <= AppConstants.maxAcceptablePauseSec,
      );
    }).toList();

    final handsOn = d.sessionDuration > 0
        ? (1.0 - pm.noFlowTime / d.sessionDuration).clamp(0.0, 1.0)
        : 1.0;

    final localVtCount     = measuredVents.length;
    final localVtCompliant = measuredVents.where((v) => v.compliant).length;
    final vtCompliance = localVtCount > 0
        ? localVtCompliant / localVtCount * 100.0
        : 0.0;

    return d._copyWithPause(
      ventilations:          measuredVents,
      pulseChecks:           measuredPulses,
      noFlowTime:            pm.noFlowTime,
      noFlowIntervals:       pm.noFlowIntervals,
      unplannedPauseTime:    pm.unplannedPauseTime,
      unplannedPauseCount:   pm.unplannedPauseCount,
      handsOnRatio:          handsOn,
      ventilationCompliance: vtCompliance,
      correctVentilations:   localVtCompliant,
    );
  }


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
    required DateTime?                  sessionEnd,
    required int                        sessionDurationSecs,
    required double                     totalGrade,
    String mode     = 'emergency',
    String scenario = 'standard_adult',
    int? fatigueAlertTimestampMs,
    int? fatigueAlertScore,
    List<int> twoMinAlertTimestampsMs = const [],
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
    double unplannedPauseTime = 0.0;
    int unplannedPauseCount = 0;

    // Pause/ventilation-duration metrics are applied as a single post-step
    // by SessionDetail.applyPauseModel() (the one source of truth, shared
    // with the offline-storage path). Build raw here; do not compute inline.
    // noFlowTime / handsOnRatio / unplanned* stay at constructor defaults
    // until applyPauseModel runs.

    if (events.isNotEmpty) {
      final n = events.length;

      final isPediatric = scenario == 'pediatric';
      final depthMin = isPediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;
      final depthMax = isPediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;
      // Consistency (uses instantaneousRate via isFrequencyInTarget getter)
      final inDepth = events.where((e) => e.isDepthInTargetFor(depthMin: depthMin, depthMax: depthMax)).length;
      final inFreq  = events.where((e) => e.isFrequencyInTarget).length;
      depthConsistency     = inDepth / n * 100;
      frequencyConsistency = inFreq  / n * 100;

      // Time to first compression
      final firmwareTTF = summaryPacket['timeToFirstCompressionMs'] as int? ?? 0;
      timeToFirst = (firmwareTTF > 0 && firmwareTTF < 65535)
          ? firmwareTTF / 1000.0
          : (events.isNotEmpty ? events.first.timestampSec : 0.0);

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

      // Averages — exclude events whose depth could not be measured
      // (NaN sentinel set in BLEConnection when a compression was counted
      // but no valid depth packet arrived). Prevents fake values from
      // dragging the session average down.
      final _depthVals =
      events.map((e) => e.depth).where((d) => d.isFinite && d > 0).toList();
      avgDepth = _depthVals.isNotEmpty
          ? _depthVals.reduce((a, b) => a + b) / _depthVals.length
          : 0.0;

      // Use instantaneousRate when available; fall back to frequency for older data
      final rates = events
          .map((e) => e.instantaneousRate > 0 ? e.instantaneousRate : e.frequency)
          .where((r) => r > 0)
          .toList();

      avgFrequency = rates.isNotEmpty
          ? rates.reduce((a, b) => a + b) / rates.length
          : 0.0;

      final effectiveDepths = events
          .map((e) => e.effectiveDepth > 0 ? e.effectiveDepth : e.depth)
          .where((d) => d.isFinite && d > 0)
          .toList();

      avgEffectiveDepth = effectiveDepths.isNotEmpty
          ? effectiveDepths.reduce((a, b) => a + b) / effectiveDepths.length
          : 0.0;

      // Depth standard deviation — same filtered set as avgDepth so a single
      // unmeasured compression cannot inflate or deflate the SD.
      if (_depthVals.length > 1) {
        final depthVariance = _depthVals
            .map((d) => (d - avgDepth) * (d - avgDepth))
            .reduce((a, b) => a + b) /
            _depthVals.length;
        depthSD = sqrt(depthVariance);
      } else {
        depthSD = 0.0;
      }

      // Consecutive good streak
      int streak = 0;
      for (final e in events) {
        if (e.isPerfectFor(depthMin: depthMin, depthMax: depthMax)) {
          streak++;
          if (streak > consecutiveGoodPeak) consecutiveGoodPeak = streak;
        } else {
          streak = 0;
        }
      }
    }

    return SessionDetail(
      sessionStart:           sessionStart,
      sessionEnd:             sessionEnd,
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
      averageDepth:           avgDepth,
      averageFrequency:       avgFrequency,
      averageEffectiveDepth:  avgEffectiveDepth,
      peakDepth:              (summaryPacket['peakDepth']          as num?)?.toDouble() ?? 0.0,
      depthSD:                (summaryPacket['compressionDepthSD'] as num?)?.toDouble() ?? depthSD,
      depthConsistency:       depthConsistency,
      frequencyConsistency:   frequencyConsistency,
      handsOnRatio:           handsOnRatio,
      noFlowTime:             noFlowTime,
      noFlowIntervals:        noFlowIntervals,
      unplannedPauseTime:     unplannedPauseTime,
      unplannedPauseCount:    unplannedPauseCount,
      rateVariability:        rateVariability,
      timeToFirstCompression: timeToFirst,
      consecutiveGoodPeak:    consecutiveGoodPeak,
      fatigueOnsetIndex:      summaryPacket['fatigueOnsetIndex']   as int?    ?? 0,
      rescuerSwapCount:       summaryPacket['rescuerSwapCount']    as int?    ?? 0,
      fatigueAlertTimestampMs: fatigueAlertTimestampMs,
      fatigueAlertScore:       fatigueAlertScore,
      twoMinAlertTimestampsMs: twoMinAlertTimestampsMs,
      correctVentilations:    summaryPacket['correctVentilations'] as int? ?? 0,
      ventilationCount:       summaryPacket['totalVentilations']   as int? ?? ventilationEvents.length,
      ventilationCompliance:  0.0,   // computed in applyPauseModel
      pulseChecksPrompted:    summaryPacket['pulseChecksPrompted'] as int?    ?? 0,
      pulseChecksComplied:    summaryPacket['pulseChecksComplied'] as int?    ?? 0,
      pulseDetectedFinal:     (summaryPacket['pulseDetected']      as int?    ?? 0) == 1,
      patientTemperature:     (summaryPacket['patientTemperature'] as num?)?.toDouble(),
      rescuerHRLastPause:     (summaryPacket['rescuerHRLastPause'] as num?)?.toDouble(),
      rescuerSpO2LastPause:   (summaryPacket['rescuerSpO2LastPause'] as num?)?.toDouble(),
      rescuerWristTempStart:  (summaryPacket['rescuerWristTempStart'] as num?)?.toDouble(),
      rescuerWristTempEnd:    (summaryPacket['rescuerWristTempEnd']   as num?)?.toDouble(),
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
      sessionStart: DateTime.parse(json['session_start'] as String).toUtc(),
      sessionEnd:   json['session_end'] != null
          ? DateTime.tryParse(json['session_end'] as String)
          : null,
      mode:                   json['mode']                      as String? ?? 'emergency',
      scenario:               json['scenario']                  as String? ?? 'standard_adult',
      compressionCount:       (json['compression_count'] as num?)?.toInt() ?? 0,
      correctDepth:           (json['correct_depth'] as num?)?.toInt() ?? 0,
      correctFrequency:       (json['correct_frequency'] as num?)?.toInt() ?? 0,
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
      unplannedPauseTime:     (json['unplanned_pause_time'] as num?)?.toDouble() ?? 0.0,
      unplannedPauseCount:    (json['unplanned_pause_count'] as num?)?.toInt() ?? 0,
      rateVariability:        (json['rate_variability']         as num?)?.toDouble() ?? 0.0,
      timeToFirstCompression: (json['time_to_first_comp']       as num?)?.toDouble() ?? 0.0,
      consecutiveGoodPeak:    (json['consecutive_good_peak']    as num?)?.toInt()    ?? 0,
      fatigueOnsetIndex:      (json['fatigue_onset_index']      as num?)?.toInt()    ?? 0,
      rescuerSwapCount:       (json['rescuer_swap_count']       as num?)?.toInt()    ?? 0,
      fatigueAlertTimestampMs: (json['fatigue_alert_timestamp_ms'] as num?)?.toInt(),
      fatigueAlertScore:       (json['fatigue_alert_score']        as num?)?.toInt(),
      twoMinAlertTimestampsMs: ((json['two_min_alert_timestamps_ms'] as List<dynamic>?) ?? [])
          .map((e) => (e as num).toInt())
          .toList(),
      ventilationCount:       (json['ventilation_count']        as num?)?.toInt()    ?? 0,
      ventilationCompliance:  (json['ventilation_compliance']   as num?)?.toDouble() ?? 0.0,
      pulseChecksPrompted:    (json['pulse_checks_prompted']    as num?)?.toInt()    ?? 0,
      pulseChecksComplied:    (json['pulse_checks_complied']    as num?)?.toInt()    ?? 0,
      pulseDetectedFinal:      json['pulse_detected_final']     as bool?             ?? false,
      patientTemperature:     (json['patient_temperature']      as num?)?.toDouble(),
      rescuerHRLastPause:     (json['rescuer_hr_last_pause']    as num?)?.toDouble(),
      rescuerSpO2LastPause:   (json['rescuer_spo2_last_pause']  as num?)?.toDouble(),
      rescuerWristTempStart:
      (json['rescuer_wrist_temp_start'] as num?)?.toDouble(),
      rescuerWristTempEnd:
      (json['rescuer_wrist_temp_end'] as num?)?.toDouble(),
      sessionDuration: (json['session_duration'] as num?)?.toInt() ?? 0,
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

  static double _fin(double v) => v.isFinite ? v : 0.0;
  static double? _finN(double? v) => (v != null && v.isFinite) ? v : null;

  // ── Serialisation — sent to backend via POST /sessions/detail ────────────
  Map<String, dynamic> toJson() => {
    if (id != null) 'id':              id,
    'session_start':            sessionStart
        .toUtc()
        .copyWith(millisecond: 0, microsecond: 0)
        .toIso8601String(),
    if (sessionEnd != null) 'session_end': sessionEnd!
        .toUtc()
        .toIso8601String(),
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
    'average_depth':            _fin(averageDepth),
    'average_frequency':        _fin(averageFrequency),
    'average_effective_depth':  _fin(averageEffectiveDepth),
    'peak_depth':               _fin(peakDepth),
    'depth_sd':                 _fin(depthSD),
    'depth_consistency':        _fin(depthConsistency),
    'freq_consistency':         _fin(frequencyConsistency),
    'hands_on_ratio':           _fin(handsOnRatio),
    'no_flow_time':             _fin(noFlowTime),
    'no_flow_intervals':        noFlowIntervals,
    'unplanned_pause_time':     _fin(unplannedPauseTime),
    'unplanned_pause_count':    unplannedPauseCount,
    'rate_variability':         _fin(rateVariability),
    'time_to_first_comp':       _fin(timeToFirstCompression),
    'consecutive_good_peak':    consecutiveGoodPeak,
    'fatigue_onset_index':      fatigueOnsetIndex,
    'rescuer_swap_count':       rescuerSwapCount,
    if (fatigueAlertTimestampMs != null) 'fatigue_alert_timestamp_ms': fatigueAlertTimestampMs,
    if (fatigueAlertScore       != null) 'fatigue_alert_score':        fatigueAlertScore,
    if (twoMinAlertTimestampsMs.isNotEmpty)
      'two_min_alert_timestamps_ms': twoMinAlertTimestampsMs,
    'ventilation_count':        ventilationCount,
    'ventilation_compliance':   _fin(ventilationCompliance),
    'pulse_checks_prompted':    pulseChecksPrompted,
    'pulse_checks_complied':    pulseChecksComplied,
    'pulse_detected_final':     pulseDetectedFinal,
    if (_finN(patientTemperature) != null)
      'patient_temperature': _finN(patientTemperature),

    if (_finN(patientSpO2LastCheck) != null)
      'patient_spo2_last_check': _finN(patientSpO2LastCheck),

    if (_finN(rescuerHRLastPause) != null)
      'rescuer_hr_last_pause': _finN(rescuerHRLastPause),

    if (_finN(rescuerSpO2LastPause) != null) 'rescuer_spo2_last_pause': _finN(rescuerSpO2LastPause),
    if (_finN(rescuerWristTempStart) != null) 'rescuer_wrist_temp_start': _finN(rescuerWristTempStart),
    if (_finN(rescuerWristTempEnd)   != null) 'rescuer_wrist_temp_end':   _finN(rescuerWristTempEnd),
    'session_duration':         sessionDuration,
    'total_grade':              _fin(totalGrade),
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
  SessionDetail withId(int newId) => _copyWith(id: newId, syncedToBackend: true);
  SessionDetail withGrade(double newGrade) => _copyWith(totalGrade: newGrade);

  static const Object _noNoteChange = Object();

  SessionDetail _copyWith({
    int? id,
    bool? syncedToBackend,
    double? totalGrade,
    Object? note = _noNoteChange,
  }) =>
      SessionDetail(
        id:                     id ?? this.id,
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
        unplannedPauseTime:     unplannedPauseTime,
        unplannedPauseCount:    unplannedPauseCount,
        rateVariability:        rateVariability,
        timeToFirstCompression: timeToFirstCompression,
        consecutiveGoodPeak:    consecutiveGoodPeak,
        fatigueOnsetIndex:      fatigueOnsetIndex,
        rescuerSwapCount:       rescuerSwapCount,
        fatigueAlertTimestampMs: fatigueAlertTimestampMs,
        fatigueAlertScore:       fatigueAlertScore,
        twoMinAlertTimestampsMs: twoMinAlertTimestampsMs,
        ventilationCount:       ventilationCount,
        ventilationCompliance:  ventilationCompliance,
        pulseChecksPrompted:    pulseChecksPrompted,
        pulseChecksComplied:    pulseChecksComplied,
        pulseDetectedFinal:     pulseDetectedFinal,
        patientTemperature:     patientTemperature,
        rescuerHRLastPause:     rescuerHRLastPause,
        rescuerSpO2LastPause:   rescuerSpO2LastPause,
        rescuerWristTempStart:  rescuerWristTempStart,
        rescuerWristTempEnd:    rescuerWristTempEnd,
        sessionDuration:        sessionDuration,
        totalGrade:             totalGrade ?? this.totalGrade,
        compressions:           compressions,
        ventilations:           ventilations,
        pulseChecks:            pulseChecks,
        rescuerVitals:          rescuerVitals,
        syncedToBackend:        syncedToBackend ?? this.syncedToBackend,
        note: identical(note, _noNoteChange) ? this.note : note as String?,
      );

  SessionDetail _copyWithPause({
    required List<VentilationEvent> ventilations,
    required List<PulseCheckEvent>  pulseChecks,
    required double noFlowTime,
    required int    noFlowIntervals,
    required double unplannedPauseTime,
    required int    unplannedPauseCount,
    required double handsOnRatio,
    required double ventilationCompliance,
    required int    correctVentilations,
  }) =>
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
        unplannedPauseTime:     unplannedPauseTime,
        unplannedPauseCount:    unplannedPauseCount,
        rateVariability:        rateVariability,
        timeToFirstCompression: timeToFirstCompression,
        consecutiveGoodPeak:    consecutiveGoodPeak,
        fatigueOnsetIndex:      fatigueOnsetIndex,
        rescuerSwapCount:       rescuerSwapCount,
        fatigueAlertTimestampMs: fatigueAlertTimestampMs,
        fatigueAlertScore:       fatigueAlertScore,
        twoMinAlertTimestampsMs: twoMinAlertTimestampsMs,
        ventilationCount:       ventilationCount,
        ventilationCompliance:  ventilationCompliance,
        pulseChecksPrompted:    pulseChecksPrompted,
        pulseChecksComplied:    pulseChecksComplied,
        pulseDetectedFinal:     pulseDetectedFinal,
        patientTemperature:     patientTemperature,
        rescuerHRLastPause:     rescuerHRLastPause,
        rescuerSpO2LastPause:   rescuerSpO2LastPause,
        rescuerWristTempStart:  rescuerWristTempStart,
        rescuerWristTempEnd:    rescuerWristTempEnd,
        sessionDuration:        sessionDuration,
        totalGrade:             totalGrade,
        compressions:           compressions,
        ventilations:           ventilations,
        pulseChecks:            pulseChecks,
        rescuerVitals:          rescuerVitals,
        syncedToBackend:        syncedToBackend,
        note:                   note,
      );

}



class PauseMetrics {
  final double noFlowTime;
  final int noFlowIntervals;
  final double unplannedPauseTime;
  final int unplannedPauseCount;
  final Map<int, double> ventDurationByTsMs;
  final Map<int, double> pulseDurationByTsMs;

  const PauseMetrics({
    required this.noFlowTime,
    required this.noFlowIntervals,
    required this.unplannedPauseTime,
    required this.unplannedPauseCount,
    this.ventDurationByTsMs  = const {},
    this.pulseDurationByTsMs = const {},
  });
}

PauseMetrics _calculatePauseMetrics({
  required List<CompressionEvent> compressions,
  required List<VentilationEvent> ventilations,
  required List<PulseCheckEvent> pulseChecks,
  required int sessionDurationSecs,
}) {
  if (sessionDurationSecs <= 0) {
    return const PauseMetrics(
      noFlowTime: 0.0,
      noFlowIntervals: 0,
      unplannedPauseTime: 0.0,
      unplannedPauseCount: 0,
    );
  }

  if (compressions.isEmpty) {
    return PauseMetrics(
      noFlowTime: sessionDurationSecs.toDouble(),
      noFlowIntervals: 1,
      unplannedPauseTime: sessionDurationSecs.toDouble(),
      unplannedPauseCount: 1,
    );
  }

  const thresholdSec = 2.0;

  double noFlowTime = 0.0;
  int noFlowIntervals = 0;
  double unplannedPauseTime = 0.0;
  int unplannedPauseCount = 0;

  final Map<int, double> ventDur  = {};
  final Map<int, double> pulseDur = {};

  // Associates a gap with a ventilation/pulse prompt and returns the planned
  // allowance, also recording the measured gap duration against that prompt.
  double? plannedAllowanceForGap(double gapStartSec, double gapEndSec) {
    const tol = AppConstants.plannedWindowAssocToleranceSec;
    final gapSec = gapEndSec - gapStartSec;
    bool planned = false;

    for (final v in ventilations) {
      if (v.timestampSec >= gapStartSec - tol &&
          v.timestampSec <= gapEndSec) {
        // Longest containing gap wins if multiple prompts map oddly.
        ventDur[v.timestampMs] =
            math.max(ventDur[v.timestampMs] ?? 0.0, gapSec);
        planned = true;
      }
    }
    for (final p in pulseChecks) {
      final pts = (p.timestampSec * 1000).round();
      if (p.timestampSec >= gapStartSec - tol &&
          p.timestampSec <= gapEndSec) {
        pulseDur[pts] = math.max(pulseDur[pts] ?? 0.0, gapSec);
        planned = true;
      }
    }

    return planned ? AppConstants.maxAcceptablePauseSec : null;
  }

  void scanGap(double startSec, double endSec) {
    final gapSec = endSec - startSec;
    if (gapSec <= thresholdSec) return;

    noFlowTime += gapSec;
    noFlowIntervals++;

    final allowance = plannedAllowanceForGap(startSec, endSec);

    if (allowance == null) {
      unplannedPauseTime += gapSec;
      unplannedPauseCount++;
    } else if (gapSec > allowance) {
      // Planned pause that overran the allowance. The portion beyond the
      // allowance is a genuine compression interruption (perfusion harm
      // occurs regardless of rescuer intent), so it counts as a distinct
      // unplanned pause — both time AND count (Behavior Y).
      unplannedPauseTime += (gapSec - allowance);
      unplannedPauseCount++;
    }
  }

  scanGap(0.0, compressions.first.timestampSec);

  for (int i = 1; i < compressions.length; i++) {
    scanGap(
      compressions[i - 1].timestampSec,
      compressions[i].timestampSec,
    );
  }

  scanGap(
    compressions.last.timestampSec,
    sessionDurationSecs.toDouble(),
  );

  return PauseMetrics(
    noFlowTime: noFlowTime,
    noFlowIntervals: noFlowIntervals,
    unplannedPauseTime: unplannedPauseTime,
    unplannedPauseCount: unplannedPauseCount,
    ventDurationByTsMs:  ventDur,
    pulseDurationByTsMs: pulseDur,
  );
}