// ─────────────────────────────────────────────────────────────────────────────
// PulseCheckEvent
//
// Emergency mode only. One pulse check window result.
// Created when PULSE_CHECK_RESULT (0x05) fires.
// Stored in SessionDetail.pulseChecks[].
//
// File location: features/training/services/pulse_check_event.dart
// ─────────────────────────────────────────────────────────────────────────────

class PulseCheckEvent {
  /// Session ms when the pulse check window started.
  final int timestampMs;

  /// Which 2-minute interval triggered this check (starts at 1).
  final int intervalNumber;

  /// True if [intervalNumber] came from the firmware's own PULSE_CHECK_START
  /// field (the reliable case). False means no matching START was seen for
  /// this window (e.g. a dropped BLE packet) and intervalNumber instead
  /// fell back to a locally-counted value, which can desync from the
  /// glove's own numbering — this flag makes that visible in the data.
  final bool intervalFromStart;

  /// 3-way classification per spec v3.0:
  /// 0 = ABSENT  — no pulse detected
  /// 1 = UNCERTAIN — weak signal, verify manually
  /// 2 = PRESENT — pulse detected
  final int classification;

  /// Raw Detector A peak count (all peaks, no refractory gate).
  /// Evidence count for thesis analysis.
  final int detectorACount;

  /// Confirmed Detector B beat count (physiologically constrained rate).
  final int detectorBCount;

  /// True when classification == 2 (PRESENT).
  bool get detected => classification == 2;
  bool get isUncertain => classification == 1;
  bool get isAbsent => classification == 0;

  /// BPM — 0.0 if not detected.
  final double detectedBpm;

  /// Signal quality 0–100. Result is always shown, not gated on this value —
  /// results screens label it "Unreliable" below 40, "Acceptable" at 40–79,
  /// "Strong" at ≥ 80.
  final int confidence;

  /// Perfusion index at time of check (0–100).
  final int perfusionIndex;

  /// "continue" or "stop_cpr". The decision-UI write path was deliberately
  /// removed; this field is kept read-only so older session records still render.
  final String? userDecision;

  /// PPG waveform samples captured during this pulse check window.
  /// Normalised 0.0–1.0, sampled at ~10 Hz from fingertip MAX30102 ppgRaw.
  /// Empty if session was loaded from storage without waveform data.
  final List<double> ppgSamples;

  /// Best patient SpO₂ reading during this pulse check window (%).
  /// 0.0 if not available.
  final double patientSpO2;

  /// Measured no-flow gap (s) that contained this pulse-check prompt,
  /// reconstructed post-session from the compression timeline by
  /// SessionDetail.applyPauseModel. Capped at maxCompliantPauseSec (15 s) for
  /// display (time past the 10 s allowance also surfaces as unplanned pause).
  /// 0.0 if the rescuer never paused for this prompt.
  final double durationSec;

  /// True when the measured pause was >= 3 s (rescuer actually stopped,
  /// matching firmware WINDOW_PAUSE_COMPLIANT_MS) AND <= maxCompliantPauseSec
  /// (15 s). Same rule as VentilationEvent.compliant.
  final bool compliant;

  /// Self-detection guard's reference source at window close (FIRMWARE_PLAN
  /// Block C, PULSE_CHECK_RESULT byte 9). Data capture only, no effect on
  /// classification: 0=NONE (no usable reference), 1=LIVE, 2=PAUSED.
  final int refSource;

  PulseCheckEvent({
    required this.timestampMs,
    required this.intervalNumber,
    this.intervalFromStart = false,
    this.classification  = 0,
    this.detectorACount  = 0,
    this.detectorBCount  = 0,
    this.detectedBpm     = 0.0,
    this.confidence      = 0,
    this.perfusionIndex  = 0,
    this.userDecision,
    this.ppgSamples = const [],
    this.patientSpO2 = 0.0,
    this.durationSec = 0.0,
    this.compliant   = false,
    this.refSource   = 0,
  });

  double get timestampSec => timestampMs / 1000.0;

  factory PulseCheckEvent.fromJson(Map<String, dynamic> json) {
    return PulseCheckEvent(
      timestampMs:    (json['ts']               as num).toInt(),
      intervalNumber: (json['interval_number']  as num).toInt(),
      intervalFromStart: json['interval_from_start'] as bool? ?? false,
      // classification is primary; fall back to bool detected for old records
      classification: (json['classification']   as num?)?.toInt()
          ?? ((json['detected'] as bool? ?? false) ? 2 : 0),
      detectorACount: (json['detector_a_count'] as num?)?.toInt()    ?? 0,
      detectorBCount: (json['detector_b_count'] as num?)?.toInt()    ?? 0,
      detectedBpm:    (json['detected_bpm']     as num?)?.toDouble() ?? 0.0,
      confidence:     (json['confidence']       as num?)?.toInt()    ?? 0,
      perfusionIndex: (json['perfusion_index']  as num?)?.toInt()    ?? 0,
      userDecision:    json['user_decision']    as String?,
      patientSpO2: (json['patient_spo2'] as num?)?.toDouble() ?? 0.0,
      durationSec: (json['duration_sec'] as num?)?.toDouble() ?? 0.0,
      compliant:    json['compliant']    as bool?             ?? false,
      ppgSamples: (json['ppg_samples'] as List<dynamic>?)
          ?.map((v) => (v as num).toDouble()).toList() ?? const [],
      refSource: (json['ref_source'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':               timestampMs,
    'interval_number':  intervalNumber,
    'interval_from_start': intervalFromStart,
    'classification':   classification,
    'detected':         detected,          // keep for backend backward compat
    'detected_bpm':     detectedBpm,
    'confidence':       confidence,
    'perfusion_index':  perfusionIndex,
    'detector_a_count': detectorACount,
    'detector_b_count': detectorBCount,
    if (userDecision != null) 'user_decision': userDecision,
    if (patientSpO2 > 0) 'patient_spo2': patientSpO2,
    'duration_sec': durationSec,
    'compliant':    compliant,
    if (ppgSamples.isNotEmpty) 'ppg_samples': ppgSamples,
    'ref_source': refSource,
  };

  PulseCheckEvent copyWith({double? durationSec, bool? compliant, String? userDecision}) =>
      PulseCheckEvent(
        timestampMs:    timestampMs,
        intervalNumber: intervalNumber,
        intervalFromStart: intervalFromStart,
        classification: classification,
        detectorACount: detectorACount,
        detectorBCount: detectorBCount,
        detectedBpm:    detectedBpm,
        confidence:     confidence,
        perfusionIndex: perfusionIndex,
        userDecision:   userDecision ?? this.userDecision,
        ppgSamples:     ppgSamples,
        patientSpO2:    patientSpO2,
        durationSec:    durationSec ?? this.durationSec,
        compliant:      compliant   ?? this.compliant,
        refSource:      refSource,
      );
}