import 'dart:async';
import 'dart:math';

class MockBLEData {
  final _random = Random();
  double correctAngleDuration = 0; // Track total time where angle is correct

  Stream<Map<String, dynamic>> generateSensorData() async* {
    while (true) {
      await Future.delayed(const Duration(milliseconds: 200)); // Simulate 5 Hz updates

      double depth = 4.0 + _random.nextDouble() * 3.0; // Depth: 4–7 cm
      int frequency = 80 + _random.nextInt(60);        // Frequency: 80–140 BPM
      int angle = _random.nextInt(30);                // Angle: 0–30 degrees
      int heartRate = 70 + _random.nextInt(40);        // HR: 70–110 BPM
      double temperature = 36.0 + _random.nextDouble() * 1.5; // Temp: 36.0–37.5°C

      // Track correct angle duration (0-15 degrees)
      if (angle >= 0 && angle <= 15) {
        correctAngleDuration += 0.2; // Increment by 0.2 seconds per tick
      }

      yield {
        "depth": depth,                // Compression depth in cm
        "frequency": frequency,        // Compression frequency in BPM
        "angle": angle,                // Current hand angle
        "correct_angle_duration": correctAngleDuration, // Total correct angle duration (secs)
        "heart_rate": heartRate,       // Heart rate (bpm)
        "temperature": temperature,    // Temperature (°C)
      };
    }
  }
}
