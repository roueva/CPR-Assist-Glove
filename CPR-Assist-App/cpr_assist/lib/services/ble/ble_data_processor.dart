import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;

/// Handles raw BLE data decryption and parsing
class BLEDataProcessor {
  final encrypt.Key _aesKey = encrypt.Key(Uint8List.fromList([
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
  ]));

  late final encrypt.Encrypter _aesEncrypter;

  BLEDataProcessor() {
    _aesEncrypter = encrypt.Encrypter(
      encrypt.AES(_aesKey, mode: encrypt.AESMode.ecb, padding: null),
    );
  }

  /// Parse raw BLE packet into structured data
  ParsedBLEData? parsePacket(List<int> data) {
    if (data.length != 48) {
      print("❌ Incorrect data length: ${data.length}. Expected 48 bytes.");
      return null;
    }

    try {
      // Bypass decryption — treat raw BLE data as plaintext
      final Uint8List combinedData = Uint8List.fromList(data);
      final buffer = ByteData.sublistView(combinedData);

      // Extract core metrics
      final depth = buffer.getFloat32(0, Endian.little);
      final frequency = buffer.getFloat32(4, Endian.little);
      final angle = buffer.getFloat32(8, Endian.little);
      final compressionCount = buffer.getInt32(12, Endian.little);

      final sessionActive = buffer.getUint8(16) != 0;
      final packetType = buffer.getUint8(18);

      final batteryPercentage = buffer.getUint8(46);
      final isCharging = buffer.getUint8(47) == 1;

      // Validate battery data
      final validBattery = batteryPercentage > 0 && batteryPercentage <= 100;

      // Parse based on packet type
      final isStartPing = packetType == 2 && sessionActive;
      final isEndPing = packetType == 2 && !sessionActive;
      final isContinuousData = packetType == 1;

      double heartRatePatient = 0.0;
      double temperaturePatient = 0.0;
      double heartRateUser = 0.0;
      double temperatureUser = 0.0;

      int correctDepth = 0;
      int correctFrequency = 0;
      int correctRecoil = 0;
      int depthRateCombo = 0;
      int totalCompressions = 0;

      if (isContinuousData) {
        heartRatePatient = buffer.getFloat32(20, Endian.little);
        temperaturePatient = buffer.getFloat32(24, Endian.little);
        heartRateUser = buffer.getFloat32(28, Endian.little);
        temperatureUser = buffer.getFloat32(32, Endian.little);
      } else if (isEndPing) {
        correctDepth = buffer.getUint16(20, Endian.little);
        correctFrequency = buffer.getUint16(22, Endian.little);
        correctRecoil = buffer.getUint16(24, Endian.little);
        depthRateCombo = buffer.getUint16(26, Endian.little);
        totalCompressions = buffer.getUint16(28, Endian.little);
      }

      return ParsedBLEData(
        depth: depth,
        frequency: frequency,
        angle: angle,
        compressionCount: compressionCount,
        isStartPing: isStartPing,
        isEndPing: isEndPing,
        isContinuousData: isContinuousData,
        batteryPercentage: validBattery ? batteryPercentage : null,
        isCharging: validBattery ? isCharging : null,
        heartRatePatient: heartRatePatient,
        temperaturePatient: temperaturePatient,
        heartRateUser: heartRateUser,
        temperatureUser: temperatureUser,
        correctDepth: correctDepth,
        correctFrequency: correctFrequency,
        correctRecoil: correctRecoil,
        depthRateCombo: depthRateCombo,
        totalCompressions: totalCompressions,
      );
    } catch (e) {
      print("❌ Failed to parse BLE data: $e");
      return null;
    }
  }
}

/// Structured BLE packet data
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

  ParsedBLEData({
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