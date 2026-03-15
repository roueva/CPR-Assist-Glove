// ─────────────────────────────────────────────────────────────────────────────
// VentilationEvent
//
// One 30:2 ventilation cycle. Created when VENTILATION_WINDOW (0x03) fires.
// Stored in SessionDetail.ventilations[].
//
// File location: features/training/services/ventilation_event.dart
// ─────────────────────────────────────────────────────────────────────────────

class VentilationEvent {
  /// Session ms when ventilation window opened.
  final int timestampMs;

  /// Which 30:2 cycle this is (starts at 1).
  final int cycleNumber;

  /// Breath attempts counted (pauses > 1 s, 0–2+).
  final int ventilationsGiven;

  /// Seconds spent in this ventilation window.
  final double durationSec;

  /// True if at least one pause > 1 s was detected in this window.
  final bool compliant;

  const VentilationEvent({
    required this.timestampMs,
    required this.cycleNumber,
    this.ventilationsGiven = 0,
    this.durationSec       = 0.0,
    this.compliant         = false,
  });

  double get timestampSec => timestampMs / 1000.0;

  factory VentilationEvent.fromJson(Map<String, dynamic> json) {
    return VentilationEvent(
      timestampMs:       (json['ts']                 as num).toInt(),
      cycleNumber:       (json['cycle_number']        as num).toInt(),
      ventilationsGiven: (json['ventilations_given']  as num?)?.toInt()    ?? 0,
      durationSec:       (json['duration_sec']        as num?)?.toDouble() ?? 0.0,
      compliant:          json['compliant']            as bool?             ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'ts':                 timestampMs,
    'cycle_number':       cycleNumber,
    'ventilations_given': ventilationsGiven,
    'duration_sec':       durationSec,
    'compliant':          compliant,
  };
}