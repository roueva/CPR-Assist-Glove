// ─────────────────────────────────────────────────────────────────────────────
// RescuerVitalSnapshot
//
// Sampled from LIVE_STREAM whenever rescuerSignalQuality >= 40.
// Stored in SessionDetail.rescuerVitals[].
//
// File location: features/training/services/rescuer_vital_snapshot.dart
// ─────────────────────────────────────────────────────────────────────────────

class RescuerVitalSnapshot {
  /// Session ms of this snapshot.
  final int timestampMs;

  /// BPM from wrist MAX30102.
  final double heartRate;

  /// SpO2 % from wrist MAX30102.
  final double spO2;

  /// °C from GXHT30.
  final double temperature;

  /// Signal quality 0–100 at time of snapshot.
  final int signalQuality;

  /// Context when sampled: "active", "ventilation", or "pulse_check".
  final String pauseType;

  /// HRV RMSSD in ms (0–200, clamped uint8 from glove).
  /// Within-session relative fatigue indicator. Not absolute clinical value.
  final int rmssd;

  /// Rescuer perfusion index 0–100 (wrist MAX30102).
  /// Dropping PI during session indicates vasoconstriction/fatigue.
  final int rescuerPi;

  /// Composite physiological fatigue score 0–100 at time of snapshot.
  final int fatigueScore;

  const RescuerVitalSnapshot({
    required this.timestampMs,
    this.heartRate     = 0.0,
    this.spO2          = 0.0,
    this.temperature   = 0.0,
    this.signalQuality = 0,
    this.pauseType     = 'active',
    this.rmssd        = 0,
    this.rescuerPi    = 0,
    this.fatigueScore = 0,
  });

  double get timestampSec => timestampMs / 1000.0;

  factory RescuerVitalSnapshot.fromJson(Map<String, dynamic> json) {
    return RescuerVitalSnapshot(
      timestampMs:   (json['ts']             as num).toInt(),
      heartRate:     (json['heart_rate']     as num?)?.toDouble() ?? 0.0,
      spO2:          (json['spo2']           as num?)?.toDouble() ?? 0.0,
      temperature:   (json['temperature']    as num?)?.toDouble() ?? 0.0,
      signalQuality: (json['signal_quality'] as num?)?.toInt()    ?? 0,
      pauseType:      json['pause_type']     as String?           ?? 'active',
      rmssd:        (json['rmssd']         as num?)?.toInt() ?? 0,
      rescuerPi:    (json['rescuer_pi']    as num?)?.toInt() ?? 0,
      fatigueScore: (json['fatigue_score'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':             timestampMs,
    'heart_rate':     heartRate,
    'spo2':           spO2,
    'temperature':    temperature,
    'signal_quality': signalQuality,
    'pause_type':     pauseType,
    'rmssd':        rmssd,
    'rescuer_pi':   rescuerPi,
    'fatigue_score': fatigueScore,
  };
}