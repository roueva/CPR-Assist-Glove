import 'dart:typed_data';

import 'package:cpr_assist/features/training/services/session_detail.dart';
import 'package:cpr_assist/features/training/services/compression_event.dart';
import 'package:cpr_assist/features/training/services/ventilation_event.dart';
import 'package:cpr_assist/features/training/services/pulse_check_event.dart';

/// Parses a binary session file from the glove's LittleFS storage
/// per BLE Spec v3.0 §8.2 (format version 5).
class OfflineSessionParser {
  static const int _magic = 0xC9A1;
  static const int _headerSize = 104;
  static const int _compressionSize = 20;
  static const int _ventilationSize = 12;
  static const int _pulseCheckSize  = 13;

  static SessionDetail parse(List<int> bytes) {
    if (bytes.length < _headerSize) {
      throw FormatException('Offline session too small: ${bytes.length} bytes');
    }
    final b = ByteData.sublistView(Uint8List.fromList(bytes));

    // Header
    final magic = b.getUint16(0, Endian.little);
    if (magic != _magic) {
      throw FormatException('Bad magic 0x${magic.toRadixString(16)}');
    }
    final version = b.getUint8(2);
    if (version != 5) {
      throw FormatException('Unsupported format version $version');
    }

    final sessionStartMs = b.getUint64(3, Endian.little);
    final sessionEndMs   = b.getUint64(11, Endian.little);
    final modeRaw        = b.getUint8(19);
    final scenarioRaw    = b.getUint8(20);

    final totalCompressions = b.getUint32(21, Endian.little);
    final correctDepth      = b.getUint32(25, Endian.little);
    final correctFrequency  = b.getUint32(29, Endian.little);
    final correctRecoil     = b.getUint32(33, Endian.little);
    final depthRateCombo    = b.getUint32(37, Endian.little);
    final correctPosture    = b.getUint32(41, Endian.little);
    final leaningCount      = b.getUint32(45, Endian.little);
    final overForceCount    = b.getUint32(49, Endian.little);
    final tooDeepCount      = b.getUint32(53, Endian.little);
    final totalVentilations = b.getUint32(57, Endian.little);
    final correctVentilations = b.getUint32(61, Endian.little);
    final fatigueOnsetIndex = b.getUint32(65, Endian.little);
    final peakDepth         = b.getFloat32(69, Endian.little);
    final depthSD           = b.getFloat32(73, Endian.little);
    final patientTemp       = b.getFloat32(77, Endian.little);
    final rescuerTempStart  = b.getFloat32(81, Endian.little);
    final rescuerTempEnd    = b.getFloat32(85, Endian.little);
    final rescuerHRLastPause   = b.getFloat32(89, Endian.little);
    final rescuerSpO2LastPause = b.getFloat32(93, Endian.little);
    final pulseDetected     = b.getUint8(97) == 1;
    final noFlowIntervals   = b.getUint8(98);
    final rescuerSwapCount  = b.getUint8(99);
    final compArrayLen      = b.getUint16(100, Endian.little);
    final ventArrayLen      = b.getUint8(102);
    final pulseArrayLen     = b.getUint8(103);

    // Compression array
    int off = _headerSize;
    final compressions = <CompressionEvent>[];
    for (int i = 0; i < compArrayLen; i++) {
      final ts        = b.getUint32(off + 0, Endian.little);
      final depth     = b.getFloat32(off + 4, Endian.little);
      final frequency = b.getFloat32(off + 8, Endian.little);
      final recoil    = b.getUint8(off + 12) == 1;
      final overForce = b.getUint8(off + 13) == 1;
      final postureOk = b.getUint8(off + 14) == 1;
      final wristAlignX10 = b.getUint8(off + 15);
      final axisDevX10    = b.getUint8(off + 16);
      compressions.add(CompressionEvent(
        timestampMs:         ts,
        depth:               depth,
        instantaneousRate:   frequency,
        frequency:           frequency,
        recoilAchieved:      recoil,
        overForce:           overForce,
        postureOk:           postureOk,
        wristAlignmentAngle: wristAlignX10 / 10.0,
        compressionAxisDev:  axisDevX10 / 10.0,
        peakTimestampMs:     ts,  // stored peak timestamp
      ));
      off += _compressionSize;
    }

    // Ventilation array
    final ventilations = <VentilationEvent>[];
    for (int i = 0; i < ventArrayLen; i++) {
      ventilations.add(VentilationEvent(
        timestampMs: b.getUint32(off + 0, Endian.little),
        cycleNumber: b.getUint16(off + 4, Endian.little),
        durationSec: b.getUint32(off + 7, Endian.little) / 1000.0,
        compliant: b.getUint8(off + 11) == 1,
      ));

      off += _ventilationSize;
    }

    // Pulse check array
    final pulseChecks = <PulseCheckEvent>[];
    for (int i = 0; i < pulseArrayLen; i++) {
      pulseChecks.add(PulseCheckEvent(
        timestampMs:    b.getUint32(off + 0, Endian.little),
        intervalNumber: b.getUint8(off + 4),
        classification: b.getUint8(off + 5),
        detectedBpm:    b.getFloat32(off + 6, Endian.little),
        confidence:     b.getUint8(off + 10),
        detectorACount: b.getUint8(off + 11),
        detectorBCount: b.getUint8(off + 12),
      ));
      off += _pulseCheckSize;
    }

    final start = DateTime.fromMillisecondsSinceEpoch(sessionStartMs);
    final end   = DateTime.fromMillisecondsSinceEpoch(sessionEndMs);
    final durationSec = (end.difference(start).inSeconds).clamp(0, 1 << 30);

    return SessionDetail(
      sessionStart:    start,
      sessionEnd:      end,
      mode:            _modeFromInt(modeRaw),
      scenario:        _scenarioFromInt(scenarioRaw),
      compressionCount:    totalCompressions,
      correctDepth:        correctDepth,
      correctFrequency:    correctFrequency,
      correctRecoil:       correctRecoil,
      depthRateCombo:      depthRateCombo,
      correctPosture:      correctPosture,
      leaningCount:        leaningCount,
      overForceCount:      overForceCount,
      tooDeepCount:        tooDeepCount,
      correctVentilations: correctVentilations,
      averageDepth:        _avg(compressions.map((c) => c.depth).toList()),
      averageFrequency:    _avg(compressions.map((c) => c.instantaneousRate).toList()),
      peakDepth:           peakDepth,
      depthSD:             depthSD,
      fatigueOnsetIndex:   fatigueOnsetIndex,
      ventilationCount:    totalVentilations,
      patientTemperature:  (patientTemp > 10 && patientTemp < 50) ? patientTemp : null,
      rescuerHRLastPause:  rescuerHRLastPause > 0 ? rescuerHRLastPause : null,
      rescuerSpO2LastPause: rescuerSpO2LastPause > 0 ? rescuerSpO2LastPause : null,
      rescuerWristTempStart: (rescuerTempStart > 10 && rescuerTempStart < 50) ? rescuerTempStart : null,
      rescuerWristTempEnd:   (rescuerTempEnd   > 10 && rescuerTempEnd   < 50) ? rescuerTempEnd   : null,
      noFlowIntervals:     noFlowIntervals,
      rescuerSwapCount:    rescuerSwapCount,
      pulseDetectedFinal:  pulseDetected,
      sessionDuration:     durationSec,
      compressions:        compressions,
      ventilations:        ventilations,
      pulseChecks:         pulseChecks,
      syncedToBackend:     false,
    );
  }

  static String _modeFromInt(int v) {
    switch (v) {
      case 1: return 'training';
      case 2: return 'training_no_feedback';
      default: return 'emergency';
    }
  }

  static String _scenarioFromInt(int v) {
    switch (v) {
      case 1: return 'pediatric';
      default: return 'standard_adult';
    }
  }

  static double _avg(List<double> xs) {
    if (xs.isEmpty) return 0.0;
    final positives = xs.where((x) => x > 0).toList();
    if (positives.isEmpty) return 0.0;
    return positives.reduce((a, b) => a + b) / positives.length;
  }
}