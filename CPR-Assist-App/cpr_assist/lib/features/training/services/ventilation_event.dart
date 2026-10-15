// ─────────────────────────────────────────────────────────────────────────────
// VentilationEvent
//
// One 30:2 ventilation cycle. Created when VENTILATION_WINDOW (0x03) fires.
// Stored in SessionDetail.ventilations[].
//
// NOTE: durationSec is the *measured* no-flow gap that contains this prompt
// (computed post-session from the compression timeline), not a firmware value,
// capped at maxCompliantPauseSec. "compliant" is true when the uncapped
// measured gap is within [minCompliantPauseSec, maxCompliantPauseSec]
// (SessionDetail.applyPauseModel).
//
// File location: features/training/services/ventilation_event.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cpr_assist/core/core.dart';

class VentilationEvent {
  /// Session ms when ventilation window opened.
  final int timestampMs;

  /// Which 30:2 cycle this is (starts at 1).
  final int cycleNumber;

  /// Seconds spent in this ventilation window.
  final double durationSec;

  /// True if the measured pause was 3–15 s (minCompliantPauseSec to
  /// maxCompliantPauseSec).
  /// App-derived (see file header), not read from the glove.
  final bool compliant;

  const VentilationEvent({
    required this.timestampMs,
    required this.cycleNumber,
    this.durationSec = 0.0,
    this.compliant   = false,
  });

  double get timestampSec => timestampMs / 1000.0;

  /// Paused, but far past the allowance. durationSec is capped at
  /// maxCompliantPauseSec, so a non-compliant row at the cap overran.
  bool get overran =>
      !compliant && durationSec >= AppConstants.maxCompliantPauseSec;

  /// Compliant, but past the 10 s target (within the lenient ceiling).
  bool get overTarget =>
      compliant && durationSec > AppConstants.maxAcceptablePauseSec;

  /// Paused, but too briefly to have delivered breaths.
  bool get tooShort => !compliant && durationSec > 0 && !overran;

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

  VentilationEvent copyWith({double? durationSec, bool? compliant}) =>
      VentilationEvent(
        timestampMs: timestampMs,
        cycleNumber: cycleNumber,
        durationSec: durationSec ?? this.durationSec,
        compliant:   compliant   ?? this.compliant,
      );
}