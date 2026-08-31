// Grading invariant tests for SessionService.calculateGradeFromDetail.
// Pure Dart — no device, no network, no BLE.
//
// Scope (TASKS.md session 6 / FIRMWARE_PLAN Block J):
//   - component weights sum to 1.00 on both the standard_adult and
//     pediatric branches
//   - the isEmergency sentinel forces 0.0 regardless of every other field
//   - the compressionCount < 10 floor forces 0.0
//   - the ventilationCount == 0 case scores ventilation as 100, not 0

import 'package:flutter_test/flutter_test.dart';
import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:cpr_assist/features/training/services/session_detail.dart';
import 'package:cpr_assist/services/network/network_service.dart';

/// Builds a "perfect" SessionDetail: every scored component maxed out, so
/// a correctly-weighted formula must return exactly 100.0.
SessionDetail _perfectSession({
  required int compressionCount,
  String mode = 'training',
  String scenario = 'standard_adult',
  int ventilationCount = 0,
  double ventilationCompliance = 100.0,
}) {
  return SessionDetail(
    sessionStart: DateTime(2026, 1, 1),
    mode: mode,
    scenario: scenario,
    compressionCount: compressionCount,
    correctDepth: compressionCount,
    correctFrequency: compressionCount,
    correctRecoil: compressionCount,
    depthRateCombo: compressionCount,
    correctPosture: compressionCount,
    handsOnRatio: 1.0,
    averageDepth: 5.5,
    averageFrequency: 110,
    timeToFirstCompression: 2.0, // < 5s -> timeScore 100
    ventilationCount: ventilationCount,
    ventilationCompliance: ventilationCompliance,
    sessionDuration: 120,
  );
}

void main() {
  final service = SessionService(NetworkService());

  group('component weights sum to 1.00', () {
    test('standard_adult branch: perfect session grades exactly 100', () {
      final s = _perfectSession(compressionCount: 30, scenario: 'standard_adult');
      expect(service.calculateGradeFromDetail(s), closeTo(100.0, 1e-9));
    });

    test('pediatric branch: perfect session grades exactly 100', () {
      final s = _perfectSession(compressionCount: 30, scenario: 'pediatric');
      expect(service.calculateGradeFromDetail(s), closeTo(100.0, 1e-9));
    });

    test('unknown scenario falls through to the default (adult) branch', () {
      final s = _perfectSession(compressionCount: 30, scenario: 'not_a_real_scenario');
      expect(service.calculateGradeFromDetail(s), closeTo(100.0, 1e-9));
    });
  });

  group('isEmergency sentinel', () {
    test('mode == emergency forces 0.0 even with a perfect session', () {
      final s = _perfectSession(compressionCount: 30, mode: 'emergency');
      expect(service.calculateGradeFromDetail(s), 0.0);
    });
  });

  group('compressionCount < 10 floor', () {
    test('9 compressions forces 0.0 even with a perfect session', () {
      final s = _perfectSession(compressionCount: 9);
      expect(service.calculateGradeFromDetail(s), 0.0);
    });

    test('10 compressions is not floored', () {
      final s = _perfectSession(compressionCount: 10);
      expect(service.calculateGradeFromDetail(s), closeTo(100.0, 1e-9));
    });
  });

  group('ventilationCount == 0 case', () {
    test('zero detected ventilations scores 100 on that component, not 0', () {
      final s = _perfectSession(
        compressionCount: 30,
        ventilationCount: 0,
        ventilationCompliance: 0.0, // would tank the grade if actually used
      );
      expect(service.calculateGradeFromDetail(s), closeTo(100.0, 1e-9));
    });

    test('with ventilations detected, low compliance actually lowers the grade', () {
      final s = _perfectSession(
        compressionCount: 30,
        ventilationCount: 5,
        ventilationCompliance: 0.0,
      );
      // Standard adult: ventScore weight is 0.12, so grade drops by 0.12 * 100.
      expect(service.calculateGradeFromDetail(s), closeTo(88.0, 1e-9));
    });
  });
}
