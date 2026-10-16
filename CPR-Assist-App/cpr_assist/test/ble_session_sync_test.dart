// Parser test for the glove-session sync fields.
// Pure Dart — no device, no network, no BLE. Builds 96-byte frames from the
// layouts in ble_manager.cpp (bleBuildSessionStart / bleBuildSessionEnd /
// bleBuildPendingLocalData) and asserts parseEventChannel() returns them.

import 'package:flutter_test/flutter_test.dart';
import 'package:cpr_assist/services/ble/ble_data_processor.dart';

List<int> _frame(int type) => List<int>.filled(96, 0)..[0] = type;

void main() {
  test('SESSION_START bytes 3–10 carry the glove start time (uint64 LE)', () {
    // 2026-10-16 09:30:00.123 UTC — above 2^32, so both halves are exercised.
    const startMs = 1792143000123;
    final f = _frame(0x01)..[1] = 1..[2] = 0;
    for (int i = 0; i < 8; i++) {
      f[3 + i] = (startMs >> (8 * i)) & 0xFF;
    }
    final p = const BLEDataProcessor().parseEventChannel(f)!;
    expect(p.isStartPing, isTrue);
    expect(p.gloveStartUnixMs, startMs);
  });

  test('SESSION_START from older firmware reads as 0 (not synced)', () {
    final p = const BLEDataProcessor().parseEventChannel(_frame(0x01))!;
    expect(p.gloveStartUnixMs, 0);
  });

  test('SESSION_END byte 70 is the flash slot plus 1', () {
    final f = _frame(0x02)..[70] = 7 + 1;
    final p = const BLEDataProcessor().parseEventChannel(f)!;
    expect(p.isEndPing, isTrue);
    expect(p.storageSlotPlus1, 8);
  });

  test('SESSION_END byte 70 = 0 never names a slot (older firmware / not saved)', () {
    final p = const BLEDataProcessor().parseEventChannel(_frame(0x02))!;
    expect(p.storageSlotPlus1, 0);
  });

  test('PENDING_LOCAL_DATA bytes 2–4 are a 20-bit slot mask', () {
    // Slots 0, 2, 9 and 19 pending.
    const mask = (1 << 0) | (1 << 2) | (1 << 9) | (1 << 19);
    final f = _frame(0x09)
      ..[1] = 4
      ..[2] = mask & 0xFF
      ..[3] = (mask >> 8) & 0xFF
      ..[4] = (mask >> 16) & 0xFF;
    final p = const BLEDataProcessor().parseEventChannel(f)!;
    expect(p.pendingSessionCount, 4);
    expect(p.pendingSlotMask, mask);
  });
}
