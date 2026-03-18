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

  /// Signal quality 0–100. App shows result only when ≥ 40.
  final int confidence;

  /// Perfusion index at time of check (0–100).
  final int perfusionIndex;

  /// "continue" or "stop_cpr" — set by the user's button tap.
  final String? userDecision;

  const PulseCheckEvent({
    required this.timestampMs,
    required this.intervalNumber,
    this.classification  = 0,
    this.detectorACount  = 0,
    this.detectorBCount  = 0,
    this.detectedBpm     = 0.0,
    this.confidence      = 0,
    this.perfusionIndex  = 0,
    this.userDecision,
  });

  double get timestampSec => timestampMs / 1000.0;

  factory PulseCheckEvent.fromJson(Map<String, dynamic> json) {
    return PulseCheckEvent(
      timestampMs:    (json['ts']               as num).toInt(),
      intervalNumber: (json['interval_number']  as num).toInt(),
      // classification is primary; fall back to bool detected for old records
      classification: (json['classification']   as num?)?.toInt()
          ?? ((json['detected'] as bool? ?? false) ? 2 : 0),
      detectorACount: (json['detector_a_count'] as num?)?.toInt()    ?? 0,
      detectorBCount: (json['detector_b_count'] as num?)?.toInt()    ?? 0,
      detectedBpm:    (json['detected_bpm']     as num?)?.toDouble() ?? 0.0,
      confidence:     (json['confidence']       as num?)?.toInt()    ?? 0,
      perfusionIndex: (json['perfusion_index']  as num?)?.toInt()    ?? 0,
      userDecision:    json['user_decision']    as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':               timestampMs,
    'interval_number':  intervalNumber,
    'classification':   classification,
    'detected':         detected,          // keep for backend backward compat
    'detected_bpm':     detectedBpm,
    'confidence':       confidence,
    'perfusion_index':  perfusionIndex,
    'detector_a_count': detectorACount,
    'detector_b_count': detectorBCount,
    if (userDecision != null) 'user_decision': userDecision,
  };
}