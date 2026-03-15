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

  /// True if glove detected a pulse.
  final bool detected;

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
    this.detected       = false,
    this.detectedBpm    = 0.0,
    this.confidence     = 0,
    this.perfusionIndex = 0,
    this.userDecision,
  });

  double get timestampSec => timestampMs / 1000.0;

  factory PulseCheckEvent.fromJson(Map<String, dynamic> json) {
    return PulseCheckEvent(
      timestampMs:    (json['ts']               as num).toInt(),
      intervalNumber: (json['interval_number']  as num).toInt(),
      detected:        json['detected']         as bool? ?? false,
      detectedBpm:    (json['detected_bpm']     as num?)?.toDouble() ?? 0.0,
      confidence:     (json['confidence']       as num?)?.toInt()    ?? 0,
      perfusionIndex: (json['perfusion_index']  as num?)?.toInt()    ?? 0,
      userDecision:    json['user_decision']    as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':              timestampMs,
    'interval_number': intervalNumber,
    'detected':        detected,
    'detected_bpm':    detectedBpm,
    'confidence':      confidence,
    'perfusion_index': perfusionIndex,
    if (userDecision != null) 'user_decision': userDecision,
  };
}