import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CPRSessionManager
//
// Owns all mutable session state: compression count, frequency, elapsed time.
// Consumers listen to [stateNotifier] — never poll internal fields directly.
//
// Lifecycle:
//   startSession() → BLE start-ping arrives
//   updateMetrics() → called for every BLE data packet during session
//   stopSession()  → BLE end-ping arrives; emits a final isEndPing=true state
//   dispose()      → called by the owning widget/provider
//
// Frequency reset:
//   If no non-zero frequency packet arrives within [_frequencyResetDelay],
//   frequency is zeroed out so the UI doesn't show stale data.
//   On stopSession() the reset timer is cancelled — the final frequency is
//   frozen so grade calculations can read the last known value.
// ─────────────────────────────────────────────────────────────────────────────

class CPRSessionManager {
  final _stopwatch = Stopwatch();
  Timer? _sessionTimer;
  Timer? _frequencyResetTimer;

  bool     _isSessionActive       = false;
  int      _currentCompressionCount = 0;
  double   _currentFrequency      = 0.0;
  Duration _sessionDuration       = Duration.zero;

  /// How long with no incoming frequency data before zeroing out the display.
  static const Duration _frequencyResetDelay = Duration(seconds: 3);

  final ValueNotifier<CPRSessionState> stateNotifier = ValueNotifier(
    CPRSessionState.initial(),
  );

  // ── Public read-only getters ───────────────────────────────────────────────

  bool     get isSessionActive   => _isSessionActive;
  Duration get sessionDuration   => _sessionDuration;
  int      get compressionCount  => _currentCompressionCount;
  double   get currentFrequency  => _currentFrequency;

  // ── Session control ────────────────────────────────────────────────────────

  void startSession() {
    debugPrint('CPRSessionManager: session started — resetting all metrics');

    _stopwatch
      ..reset()
      ..start();

    _isSessionActive        = true;
    _currentCompressionCount = 0;
    _currentFrequency       = 0.0;
    _sessionDuration        = Duration.zero;

    _sessionTimer?.cancel();
    _frequencyResetTimer?.cancel();

    // Tick every 100 ms so the session timer UI stays smooth
    _sessionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isSessionActive) {
        _sessionDuration = _stopwatch.elapsed;
        _emitState();
      }
    });

    _emitState();
  }

  void stopSession() {
    debugPrint('CPRSessionManager: session stopped');

    _stopwatch.stop();
    _isSessionActive = false;
    _sessionDuration = _stopwatch.elapsed;

    _sessionTimer?.cancel();
    _sessionTimer = null;

    // Cancel frequency reset so the last known value is preserved for grading
    _frequencyResetTimer?.cancel();
    _frequencyResetTimer = null;

    debugPrint(
      'CPRSessionManager: final — '
          '$_currentCompressionCount compressions '
          'in ${_sessionDuration.mmss}',
    );

    _emitState(isEndPing: true);
  }

  /// Called for every decoded BLE data packet during a session.
  ///
  /// [compressionCount] updates are accepted even after [stopSession] because
  /// the glove's end-ping carries the definitive final count.
  void updateMetrics({
    required double depth,
    required double frequency,
    required int    compressionCount,
  }) {
    if (compressionCount > _currentCompressionCount) {
      _currentCompressionCount = compressionCount;
      debugPrint('CPRSessionManager: compression count → $_currentCompressionCount');
    }

    if (!_isSessionActive) return;

    if (frequency > 0) {
      _currentFrequency = frequency;

      // Reset any pending zero-out — the glove is still active
      _frequencyResetTimer?.cancel();

      // Schedule a new reset: if no non-zero frequency arrives in time,
      // the rescuer has paused compressions
      _frequencyResetTimer = Timer(_frequencyResetDelay, () {
        if (_isSessionActive && _currentFrequency > 0) {
          debugPrint('CPRSessionManager: no compressions for 3 s — zeroing frequency');
          _currentFrequency = 0.0;
          _emitState();
        }
      });

      debugPrint(
        'CPRSessionManager: frequency → '
            '${_currentFrequency.toStringAsFixed(1)} CPM',
      );
    }
    // frequency == 0 is intentionally ignored — let the timer handle zeroing
    // so a single dropped BLE packet doesn't blank the gauge prematurely.
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _emitState({bool isEndPing = false}) {
    stateNotifier.value = CPRSessionState(
      isActive:         _isSessionActive,
      compressionCount: _currentCompressionCount,
      // Show 0 on the UI once the session has stopped (grading reads the
      // frozen _currentFrequency directly via the getter)
      frequency:        _isSessionActive ? _currentFrequency : 0.0,
      duration:         _sessionDuration,
      isEndPing:        isEndPing,
    );
  }

  void dispose() {
    _sessionTimer?.cancel();
    _frequencyResetTimer?.cancel();
    stateNotifier.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CPRSessionState — immutable snapshot emitted by CPRSessionManager
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class CPRSessionState {
  final bool     isActive;
  final int      compressionCount;
  final double   frequency;
  final Duration duration;
  /// True only on the final packet — triggers grade calculation downstream.
  final bool     isEndPing;

  const CPRSessionState({
    required this.isActive,
    required this.compressionCount,
    required this.frequency,
    required this.duration,
    this.isEndPing = false,
  });

  factory CPRSessionState.initial() => const CPRSessionState(
    isActive:         false,
    compressionCount: 0,
    frequency:        0.0,
    duration:         Duration.zero,
  );

  /// Convenience — formatted elapsed time for UI display (e.g. '02:45')
  String get formattedDuration => duration.mmss;
}