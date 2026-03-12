// ─────────────────────────────────────────────────────────────────────────────
// CompressionEvent
//
// A single compression captured during a training session.
// The glove streams one of these per compression over BLE in real-time.
// Accumulated by the BLE service into a List<CompressionEvent> and then
// handed off to SessionDetail when the end-ping arrives.
//
// File location: features/training/models/compression_event.dart
// ─────────────────────────────────────────────────────────────────────────────

/// CPR target ranges (ERC 2021 guidelines)
class CprTargets {
  CprTargets._();

  static const double depthMin  = 5.0;  // cm
  static const double depthMax  = 6.0;  // cm
  static const double rateMin   = 100.0; // BPM
  static const double rateMax   = 120.0; // BPM
}

class CompressionEvent {
  /// Milliseconds since session start — used as the X axis on graphs.
  final int timestampMs;

  /// Compression depth in centimetres (e.g. 5.4).
  final double depth;

  /// Instantaneous compression rate at this moment (BPM).
  final double frequency;

  /// Whether full chest recoil was achieved after this compression.
  final bool recoilAchieved;

  const CompressionEvent({
    required this.timestampMs,
    required this.depth,
    required this.frequency,
    required this.recoilAchieved,
  });

  // ── Derived ────────────────────────────────────────────────────────────────

  bool get isDepthInTarget =>
      depth >= CprTargets.depthMin && depth <= CprTargets.depthMax;

  bool get isFrequencyInTarget =>
      frequency >= CprTargets.rateMin && frequency <= CprTargets.rateMax;

  bool get isPerfect => isDepthInTarget && isFrequencyInTarget && recoilAchieved;

  /// Seconds from session start — convenience for graph labels.
  double get timestampSec => timestampMs / 1000.0;

  // ── BLE parsing ────────────────────────────────────────────────────────────

  /// Parse a single BLE compression packet into a [CompressionEvent].
  /// [sessionStartMs] is the epoch ms when the session began.
  factory CompressionEvent.fromBlePacket(
      Map<String, dynamic> packet, {
        required int sessionStartMs,
      }) {
    final absoluteTs = packet['timestamp'] as int? ?? 0;
    return CompressionEvent(
      timestampMs:   absoluteTs - sessionStartMs,
      depth:         (packet['depth']       as num?)?.toDouble() ?? 0.0,
      frequency:     (packet['frequency']   as num?)?.toDouble() ?? 0.0,
      recoilAchieved: packet['recoil']      as bool?             ?? false,
    );
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  factory CompressionEvent.fromJson(Map<String, dynamic> json) {
    return CompressionEvent(
      timestampMs:    (json['ts']       as num).toInt(),
      depth:          (json['depth']    as num).toDouble(),
      frequency:      (json['freq']     as num).toDouble(),
      recoilAchieved:  json['recoil']  as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':     timestampMs,
    'depth':  depth,
    'freq':   frequency,
    'recoil': recoilAchieved,
  };
}