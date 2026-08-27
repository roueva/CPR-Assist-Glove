import 'package:flutter/foundation.dart';

/// Off by default. Enable per-run with:
///   flutter run --dart-define=VERBOSE_MAP_LOGS=true
const bool kVerboseMapLogs =
    bool.fromEnvironment('VERBOSE_MAP_LOGS', defaultValue: false);

/// Drop-in [debugPrint] replacement for high-volume, per-item logging
/// (route-preload loops, distance-accuracy batches) that would otherwise
/// flood the console on every trigger. Lifecycle and error logs should stay
/// on plain [debugPrint] — this is only for the noisy, per-item ones.
void verboseDebugPrint(String message) {
  if (kVerboseMapLogs) debugPrint(message);
}
