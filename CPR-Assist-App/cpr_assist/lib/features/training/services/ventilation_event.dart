// ─────────────────────────────────────────────────────────────────────────────
// VentilationEvent
//
// One 30:2 ventilation cycle. Created when VENTILATION_WINDOW (0x03) fires.
// Stored in SessionDetail.ventilations[].
//
// NOTE: the firmware does not currently count actual breaths given —
// the glove has no breath sensor. Only the *target* count (always 2 for adult)
// is sent over BLE, and that's a live-UI instruction (handled separately by
// VentilationOverlay), not a per-window measurement. The "ventilationsGiven"
// field was removed because it was never populated.
//
// File location: features/training/services/ventilation_event.dart
// ─────────────────────────────────────────────────────────────────────────────

class VentilationEvent {
  /// Session ms when ventilation window opened.
  final int timestampMs;

  /// Which 30:2 cycle this is (starts at 1).
  final int cycleNumber;

  /// Seconds spent in this ventilation window.
  final double durationSec;

  /// True if at least one pause > 1 s was detected in this window
  /// (firmware-derived: compsDuringWindow <= 2 AND windowMs >= COMPLIED_MIN_MS).
  final bool compliant;

  const VentilationEvent({
    required this.timestampMs,
    required this.cycleNumber,
    this.durationSec = 0.0,
    this.compliant   = false,
  });

  double get timestampSec => timestampMs / 1000.0;

  factory VentilationEvent.fromJson(Map<String, dynamic> json) {
    return VentilationEvent(
      timestampMs:  (json['ts']            as num).toInt(),
      cycleNumber:  (json['cycle_number']  as num).toInt(),
      durationSec:  (json['duration_sec']  as num?)?.toDouble() ?? 0.0,
      compliant:     json['compliant']     as bool?             ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':           timestampMs,
    'cycle_number': cycleNumber,
    'duration_sec': durationSec,
    'compliant':    compliant,
  };
}