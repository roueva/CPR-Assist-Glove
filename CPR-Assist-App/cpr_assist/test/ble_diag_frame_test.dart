// Parser test for the 0x0D DIAG_FRAME EVENT_CHANNEL packet.
// Pure Dart — no device, no network, no BLE. Builds a synthetic 96-byte
// frame byte-for-byte from ble_manager.cpp's bleBuildDiagFrame() layout
// comment and asserts BLEDataProcessor.parseEventChannel() returns every
// field back exactly.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cpr_assist/services/ble/ble_data_processor.dart';
import 'package:cpr_assist/features/account/screens/glove_diagnostic_sheet.dart'
    show buildTypeLabel, buildStampLabel, activeDebugFlagsLabel;

void main() {
  // Known field values, chosen to be unambiguous (non-zero, and for
  // signed/negative fields, actually negative) so a sign or byte-order bug
  // would fail the exact-match assertions below.
  const rawFsrAdc          = 2048;   // int16
  const palmWhoAmI         = 0x6C;   // u8
  const wristWhoAmI        = 0x6C;   // u8
  const i2cScanMask        = 0x3F;   // u8, 6 bits
  const actionResult       = 0x10;   // u8
  const palmAccelRaw       = 981;    // int16, → 9.81 m/s² after /100.0
  const wristAccelRaw      = -250;   // int16, → -2.50 m/s² after /100.0 (negative)
  const rescuerPpgFiltered = -150;   // int16 (negative)
  const rescuerPpgDc       = 138000; // u32 — bench-observed high end, exceeds u16
  const buildFlags         = 0x2A;   // u8, bits 1,3,5 (BLE_DEBUG_SERIAL,
                                      // DEPTH_SELECTOR_LOG, IMU_TEST_LOG)

  // Bit-packed buildStamp for 2026-08-31 14:07 (year-2000=26, month=8,
  // day=31, hour=14, minute=7), per ble_manager.cpp's diagBuildStamp():
  //   bits 0-6 year-2000, 7-10 month, 11-15 day, 16-20 hour, 21-26 minute
  const buildYear   = 26;
  const buildMonth  = 8;
  const buildDay    = 31;
  const buildHour   = 14;
  const buildMinute = 7;
  final buildStamp = buildYear |
      (buildMonth << 7) |
      (buildDay << 11) |
      (buildHour << 16) |
      (buildMinute << 21);

  Uint8List buildDiagFrameBytes() {
    final bytes = Uint8List(kEventChannelSize); // zero-filled, matches makeItem()
    final b = ByteData.sublistView(bytes);
    b.setUint8(0, kPacketDiagFrame);
    b.setInt16(1, rawFsrAdc, Endian.little);
    b.setUint8(3, palmWhoAmI);
    b.setUint8(4, wristWhoAmI);
    b.setUint8(5, i2cScanMask);
    b.setUint8(6, actionResult);
    b.setInt16(7, palmAccelRaw, Endian.little);
    b.setInt16(9, wristAccelRaw, Endian.little);
    b.setInt16(11, rescuerPpgFiltered, Endian.little);
    b.setUint32(13, rescuerPpgDc, Endian.little);
    b.setUint8(17, buildFlags);
    b.setUint32(18, buildStamp, Endian.little);
    // bytes 22-95 stay 0 — reserved
    return bytes;
  }

  test('96-byte frame parses to exactly the known field values', () {
    final frame  = buildDiagFrameBytes();
    expect(frame.length, kEventChannelSize);

    final parsed = const BLEDataProcessor().parseEventChannel(frame);

    expect(parsed, isNotNull);
    expect(parsed!.isDiagFrame, isTrue);
    expect(parsed.diagRawFsrAdc, rawFsrAdc);
    expect(parsed.diagPalmWhoAmI, palmWhoAmI);
    expect(parsed.diagWristWhoAmI, wristWhoAmI);
    expect(parsed.diagI2cScanMask, i2cScanMask);
    expect(parsed.diagActionResult, actionResult);
    expect(parsed.diagPalmAccelMag, closeTo(palmAccelRaw / 100.0, 1e-9));
    expect(parsed.diagWristAccelMag, closeTo(wristAccelRaw / 100.0, 1e-9));
    expect(parsed.diagRescuerPpgFiltered, closeTo(rescuerPpgFiltered.toDouble(), 1e-9));
    expect(parsed.diagRescuerPpgDc, closeTo(rescuerPpgDc.toDouble(), 1e-9));
    expect(parsed.diagBuildFlags, buildFlags);
    expect(parsed.diagBuildStamp, buildStamp);
  });

  test('buildStamp round-trips through the display unpacker', () {
    final frame  = buildDiagFrameBytes();
    final parsed = const BLEDataProcessor().parseEventChannel(frame);

    expect(buildStampLabel(parsed!.diagBuildStamp), '2026-08-31 14:07');
  });

  test('buildFlags round-trips through the display helpers', () {
    final frame  = buildDiagFrameBytes();
    final parsed = const BLEDataProcessor().parseEventChannel(frame);

    // bit0 (STUDY_BUILD) is 0 in 0x2A → DEV build.
    expect(buildTypeLabel(parsed!.diagBuildFlags), 'DEV');
    // bits 1,3,5 set → BLE_DEBUG_SERIAL, DEPTH_SELECTOR_LOG, IMU_TEST_LOG.
    expect(
      activeDebugFlagsLabel(parsed.diagBuildFlags!),
      'BLE_DEBUG_SERIAL, DEPTH_SELECTOR_LOG, IMU_TEST_LOG',
    );
  });

  test('STUDY_BUILD bit flips buildTypeLabel to STUDY', () {
    expect(buildTypeLabel(0x01), 'STUDY');
    expect(buildTypeLabel(0x00), 'DEV');
    expect(buildTypeLabel(null), '—');
  });
}
