import 'dart:math' show cos, pi;

// ─────────────────────────────────────────────────────────────────────────────
// CompressionEvent
// ─────────────────────────────────────────────────────────────────────────────

class CprTargets {
  CprTargets._();
  static const double depthMin         = 5.0;
  static const double depthMax         = 6.0;
  static const double rateMin          = 100.0;
  static const double rateMax          = 120.0;
  static const double alignmentMaxDeg  = 15.0;
  static const double overForceNewtons = 600.0;
}

class CompressionEvent {
  final int    timestampMs;
  final double depth;
  final double frequency;
  final double force;
  final bool   recoilAchieved;
  final bool   overForce;
  final bool   postureOk;
  final bool   leaningDetected;
  final double wristAlignmentAngle;
  final double compressionAxisDev;
  final double effectiveDepth;

  const CompressionEvent({
    required this.timestampMs,
    required this.depth,
    required this.frequency,
    this.force               = 0.0,
    required this.recoilAchieved,
    this.overForce           = false,
    this.postureOk           = false,
    this.leaningDetected     = false,
    this.wristAlignmentAngle = 0.0,
    this.compressionAxisDev  = 0.0,
    this.effectiveDepth      = 0.0,
  });

  bool get isDepthInTarget =>
      depth >= CprTargets.depthMin && depth <= CprTargets.depthMax;

  bool get isFrequencyInTarget =>
      frequency >= CprTargets.rateMin && frequency <= CprTargets.rateMax;

  bool get isPerfect =>
      isDepthInTarget && isFrequencyInTarget && recoilAchieved && postureOk;

  double get timestampSec => timestampMs / 1000.0;

  factory CompressionEvent.fromBlePacket(
      Map<String, dynamic> packet, {
        required int sessionStartMs,
      }) {
    final absoluteTs = packet['timestamp'] as int? ?? 0;
    final axisDevDeg = (packet['compressionAxisDeviation'] as num?)?.toDouble() ?? 0.0;
    final rawDepth   = (packet['depth'] as num?)?.toDouble() ?? 0.0;
    return CompressionEvent(
      timestampMs:         absoluteTs - sessionStartMs,
      depth:               rawDepth,
      frequency:           (packet['frequency'] as num?)?.toDouble()       ?? 0.0,
      force:               (packet['force']     as num?)?.toDouble()       ?? 0.0,
      recoilAchieved:       packet['recoilAchieved']   as bool?            ?? false,
      overForce:            packet['overForceFlag']    as bool?            ?? false,
      postureOk:            packet['postureOk']        as bool?            ?? false,
      leaningDetected:      packet['leaningDetected']  as bool?            ?? false,
      wristAlignmentAngle: (packet['wristAlignmentAngle'] as num?)?.toDouble() ?? 0.0,
      compressionAxisDev:  axisDevDeg,
      effectiveDepth:      rawDepth * cos(axisDevDeg * pi / 180.0),
    );
  }

  factory CompressionEvent.fromJson(Map<String, dynamic> json) {
    return CompressionEvent(
      timestampMs:         (json['ts']              as num).toInt(),
      depth:               (json['depth']            as num).toDouble(),
      frequency:           (json['freq']             as num).toDouble(),
      force:               (json['force']            as num?)?.toDouble()  ?? 0.0,
      recoilAchieved:       json['recoil']           as bool?              ?? false,
      overForce:            json['over_force']       as bool?              ?? false,
      postureOk:            json['posture_ok']       as bool?              ?? false,
      leaningDetected:      json['leaning']          as bool?              ?? false,
      wristAlignmentAngle: (json['wrist_angle']      as num?)?.toDouble()  ?? 0.0,
      compressionAxisDev:  (json['axis_dev']         as num?)?.toDouble()  ?? 0.0,
      effectiveDepth:      (json['effective_depth']  as num?)?.toDouble()  ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':              timestampMs,
    'depth':           depth,
    'freq':            frequency,
    'force':           force,
    'recoil':          recoilAchieved,
    'over_force':      overForce,
    'posture_ok':      postureOk,
    'leaning':         leaningDetected,
    'wrist_angle':     wristAlignmentAngle,
    'axis_dev':        compressionAxisDev,
    'effective_depth': effectiveDepth,
  };
}