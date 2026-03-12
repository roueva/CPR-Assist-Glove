import 'package:flutter/foundation.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEDataProcessor
//
// Parses raw BLE packets that arrive as plaintext directly from the glove.
// NO decryption — the hardware sends data already readable.
//
// Packet layout (48 bytes, little-endian):
//   [0..3]   float32  depth
//   [4..7]   float32  frequency
//   [8..11]  float32  angle
//   [12..15] int32    compressionCount
//   [16]     uint8    sessionActive (1 = true)
//   [17]     uint8    (reserved)
//   [18]     uint8    packetType  (1 = continuous, 2 = ping)
//   [19]     uint8    (reserved)
//   — packetType 1 (continuous) —
//   [20..23] float32  heartRatePatient
//   [24..27] float32  temperaturePatient
//   [28..31] float32  heartRateUser
//   [32..35] float32  temperatureUser
//   — packetType 2 + !sessionActive (end ping) —
//   [20..21] uint16   correctDepth
//   [22..23] uint16   correctFrequency
//   [24..25] uint16   correctRecoil
//   [26..27] uint16   depthRateCombo
//   [28..29] uint16   totalCompressions
//   —
//   [46]     uint8    batteryPercentage
//   [47]     uint8    isCharging (1 = true)
// ─────────────────────────────────────────────────────────────────────────────

class BLEDataProcessor {
  const BLEDataProcessor();

  /// Parse a raw BLE packet into structured data.
  /// Returns null if the packet is malformed or the wrong length.
  ParsedBLEData? parsePacket(List<int> data) {
    if (data.length != AppConstants.blePacketSize) {
      debugPrint(
        'BLEDataProcessor: incorrect packet length ${data.length} '
            '(expected ${AppConstants.blePacketSize})',
      );
      return null;
    }

    try {
      final buffer = ByteData.sublistView(Uint8List.fromList(data));

      // ── Core fields (always present) ──────────────────────────────────────
      final depth             = buffer.getFloat32(0,  Endian.little);
      final frequency         = buffer.getFloat32(4,  Endian.little);
      final angle             = buffer.getFloat32(8,  Endian.little);
      final compressionCount  = buffer.getInt32  (12, Endian.little);
      final sessionActive     = buffer.getUint8  (16) != 0;
      final packetType        = buffer.getUint8  (18);

      // ── Battery (always present) ──────────────────────────────────────────
      final rawBattery   = buffer.getUint8(46);
      final isCharging   = buffer.getUint8(47) == 1;
      final validBattery = rawBattery > 0 && rawBattery <= 100;

      // ── Packet type flags ─────────────────────────────────────────────────
      final isStartPing      = packetType == 2 && sessionActive;
      final isEndPing        = packetType == 2 && !sessionActive;
      final isContinuousData = packetType == 1;

      // ── Type-specific fields ──────────────────────────────────────────────
      double heartRatePatient    = 0;
      double temperaturePatient  = 0;
      double heartRateUser       = 0;
      double temperatureUser     = 0;
      int correctDepth           = 0;
      int correctFrequency       = 0;
      int correctRecoil          = 0;
      int depthRateCombo         = 0;
      int totalCompressions      = 0;

      if (isContinuousData) {
        heartRatePatient   = buffer.getFloat32(20, Endian.little);
        temperaturePatient = buffer.getFloat32(24, Endian.little);
        heartRateUser      = buffer.getFloat32(28, Endian.little);
        temperatureUser    = buffer.getFloat32(32, Endian.little);
      } else if (isEndPing) {
        correctDepth      = buffer.getUint16(20, Endian.little);
        correctFrequency  = buffer.getUint16(22, Endian.little);
        correctRecoil     = buffer.getUint16(24, Endian.little);
        depthRateCombo    = buffer.getUint16(26, Endian.little);
        totalCompressions = buffer.getUint16(28, Endian.little);
      }

      return ParsedBLEData(
        depth:             depth,
        frequency:         frequency,
        angle:             angle,
        compressionCount:  compressionCount,
        isStartPing:       isStartPing,
        isEndPing:         isEndPing,
        isContinuousData:  isContinuousData,
        batteryPercentage: validBattery ? rawBattery : null,
        isCharging:        validBattery ? isCharging : null,
        heartRatePatient:  heartRatePatient,
        temperaturePatient: temperaturePatient,
        heartRateUser:     heartRateUser,
        temperatureUser:   temperatureUser,
        correctDepth:      correctDepth,
        correctFrequency:  correctFrequency,
        correctRecoil:     correctRecoil,
        depthRateCombo:    depthRateCombo,
        totalCompressions: totalCompressions,
      );
    } catch (e) {
      debugPrint('BLEDataProcessor: parse error — $e');
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ParsedBLEData — immutable value object
// ─────────────────────────────────────────────────────────────────────────────

class ParsedBLEData {
  final double depth;
  final double frequency;
  final double angle;
  final int compressionCount;
  final bool isStartPing;
  final bool isEndPing;
  final bool isContinuousData;
  final int? batteryPercentage;
  final bool? isCharging;
  final double heartRatePatient;
  final double temperaturePatient;
  final double heartRateUser;
  final double temperatureUser;
  final int correctDepth;
  final int correctFrequency;
  final int correctRecoil;
  final int depthRateCombo;
  final int totalCompressions;

  const ParsedBLEData({
    required this.depth,
    required this.frequency,
    required this.angle,
    required this.compressionCount,
    required this.isStartPing,
    required this.isEndPing,
    required this.isContinuousData,
    this.batteryPercentage,
    this.isCharging,
    required this.heartRatePatient,
    required this.temperaturePatient,
    required this.heartRateUser,
    required this.temperatureUser,
    required this.correctDepth,
    required this.correctFrequency,
    required this.correctRecoil,
    required this.depthRateCombo,
    required this.totalCompressions,
  });
}