import 'dart:async';
import 'package:flutter/foundation.dart';

class CPRSessionManager {
  final _stopwatch = Stopwatch();
  Timer? _sessionTimer;
  Timer? _frequencyResetTimer;

  bool _isSessionActive = false;
  int _currentCompressionCount = 0;
  double _currentFrequency = 0.0;
  Duration _sessionDuration = Duration.zero;

  // How long with no frequency data before we reset to zero
  static const _frequencyResetDelay = Duration(seconds: 3);

  final ValueNotifier<CPRSessionState> stateNotifier = ValueNotifier(
    CPRSessionState.initial(),
  );

  bool get isSessionActive => _isSessionActive;
  Duration get sessionDuration => _sessionDuration;
  int get compressionCount => _currentCompressionCount;
  double get currentFrequency => _currentFrequency;

  void startSession() {
    print('🟢 Session started - resetting all metrics');

    _stopwatch.reset();
    _stopwatch.start();
    _isSessionActive = true;

    _currentCompressionCount = 0;
    _currentFrequency = 0.0;
    _sessionDuration = Duration.zero;

    _sessionTimer?.cancel();
    _frequencyResetTimer?.cancel();

    // UI timer — only emit if duration actually changed (every 100ms is fine,
    // but we skip emitting if nothing else changed)
    _sessionTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isSessionActive) {
        _sessionDuration = _stopwatch.elapsed;
        _emitState();
      }
    });

    _emitState();
  }

  void stopSession() {
    print('🔴 Session stopped');

    _stopwatch.stop();
    _isSessionActive = false;
    _sessionDuration = _stopwatch.elapsed;

    _sessionTimer?.cancel();
    _sessionTimer = null;

    // Cancel frequency reset — freeze the last known frequency value
    // so the UI can show final metrics without zeroing out
    _frequencyResetTimer?.cancel();
    _frequencyResetTimer = null;

    print('📊 Final: $_currentCompressionCount compressions '
        'in ${_formatDuration(_sessionDuration)}');

    _emitState(isEndPing: true);
  }

  void updateMetrics({
    required double depth,
    required double frequency,
    required int compressionCount,
  }) {
    // Accept count updates even on the last packet after stopSession
    // (the glove end-ping carries the final count)
    if (compressionCount > _currentCompressionCount) {
      _currentCompressionCount = compressionCount;
      print('🔢 Compression count: $_currentCompressionCount');
    }

    if (!_isSessionActive) return;

    if (frequency > 0) {
      _currentFrequency = frequency;

      // Cancel any pending reset — glove is still active
      _frequencyResetTimer?.cancel();

      // Schedule a new reset: if no non-zero frequency arrives
      // within 3 seconds, the rescuer has stopped compressing
      _frequencyResetTimer = Timer(_frequencyResetDelay, () {
        if (_isSessionActive && _currentFrequency > 0) {
          print('⏰ No compressions for 3s — resetting frequency to 0');
          _currentFrequency = 0.0;
          _emitState();
        }
      });

      print('📊 Frequency: ${_currentFrequency.toStringAsFixed(1)} CPM');
    }
    // If frequency == 0, we do nothing — let the timer handle the reset.
    // This avoids zeroing out prematurely on a single dropped packet.
  }

  void _emitState({bool isEndPing = false}) {
    stateNotifier.value = CPRSessionState(
      isActive: _isSessionActive,
      compressionCount: _currentCompressionCount,
      frequency: _isSessionActive ? _currentFrequency : 0.0,
      duration: _sessionDuration,
      isEndPing: isEndPing,
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void dispose() {
    _sessionTimer?.cancel();
    _frequencyResetTimer?.cancel();
    stateNotifier.dispose();
  }
}

class CPRSessionState {
  final bool isActive;
  final int compressionCount;
  final double frequency;
  final Duration duration;
  final bool isEndPing;

  const CPRSessionState({
    required this.isActive,
    required this.compressionCount,
    required this.frequency,
    required this.duration,
    this.isEndPing = false,
  });

  factory CPRSessionState.initial() {
    return const CPRSessionState(
      isActive: false,
      compressionCount: 0,
      frequency: 0.0,
      duration: Duration.zero,
    );
  }
}