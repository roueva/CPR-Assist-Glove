import 'dart:async';

class FakeBleStreamService {
  static final StreamController<Map<String, dynamic>> _controller =
  StreamController.broadcast();

  static Stream<Map<String, dynamic>> get stream => _controller.stream;

  static Timer? _depthTimer;

  static double _depth = 3.0; // Neutral starting value
  static double _frequency = 110.0;
  static int _lastCompressionTime = DateTime.now().millisecondsSinceEpoch;

  /// Enable manual simulation
  static void startManualMode() {
    _emit(); // Emit initial state
  }

  /// Simulate compression over 1 second
  static void simulatePress() {
    _depthTimer?.cancel();

    const int steps = 2;
    const Duration interval = Duration(milliseconds: 50); // total = 300ms
    int tick = 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final timeBetween = now - _lastCompressionTime;
    _lastCompressionTime = now;
    _frequency = (60000 / timeBetween).clamp(80, 140);

    _depthTimer = Timer.periodic(interval, (timer) {
      tick++;
      _depth = 6.0 * (tick / steps);

      if (tick >= steps) {
        _depth = 6.0;
        timer.cancel();
      }

      _emit();
    });
  }

  /// Simulate release over 1 second
  static void simulateRelease() {
    _depthTimer?.cancel();

    const int steps = 2; // 1000ms / 50ms
    const Duration interval = Duration(milliseconds: 50);
    int tick = 0;
    final double startDepth = _depth;

    _depthTimer = Timer.periodic(interval, (timer) {
      tick++;
      _depth = startDepth * (1 - tick / steps);

      if (tick >= steps || _depth <= 0.05) {
        _depth = 0.0;
        timer.cancel();
      }

      _emit();
    });
  }

  static void _emit() {
    _controller.add({
      'depth': _depth,
      'weight': _depth,
      'frequency': _frequency,
    });
  }

  static void stop() {
    _depthTimer?.cancel();
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
