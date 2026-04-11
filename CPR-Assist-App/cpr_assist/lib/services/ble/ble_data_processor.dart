import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEDataProcessor  —  BLE Spec v3.0
//
// The glove exposes exactly two BLE characteristics:
//
//   LIVE_STREAM   UUID 19b10001-e8f2-537e-4f6c-d104768a1214
//     100 bytes fixed, 10 Hz notify.
//     Drives depth bar, rate gauge, posture indicator, vitals, PPG waveform.
//     Drives depth bar, rate gauge, posture indicator, vitals, PPG waveform.
//
//   EVENT_CHANNEL UUID 19b10002-e8f2-537e-4f6c-d104768a1214
//   96 bytes fixed, on-event notify + write.
//     Session lifecycle, commands, offline sync.
//
// All multi-byte values are little-endian.
// No decryption — data arrives already readable.
//
// Callers:
//   BLEConnection subscribes to each characteristic separately and routes:
//     LIVE_STREAM data  → parseLiveStream()
//     EVENT_CHANNEL data → parseEventChannel()
// ─────────────────────────────────────────────────────────────────────────────

// ── Packet sizes ──────────────────────────────────────────────────────────────

const int kLiveStreamSize   = 100;
const int kEventChannelSize = 96;

// ── EVENT_CHANNEL glove→app packet type bytes ────────────────────────────────

const int kPacketSessionStart      = 0x01;
const int kPacketSessionEnd        = 0x02;
const int kPacketVentilationWindow = 0x03;
const int kPacketPulseCheckStart   = 0x04;
const int kPacketPulseCheckResult  = 0x05;
const int kPacketModeChange        = 0x06;
const int kPacketTwoMinAlert       = 0x07;
const int kPacketFatigueAlert      = 0x08;
const int kPacketPendingLocalData  = 0x09;
const int kPacketLocalSessionChunk = 0x0A;
const int kPacketSelftestResult    = 0x0B;
const int kPacketScenarioChange = 0x0C;
const int kCmdSetScenario = 0xFD;


// ── EVENT_CHANNEL app→glove command bytes ────────────────────────────────────

const int kCmdModeSet          = 0xF1;
const int kCmdFeedbackSet      = 0xF2;
const int kCmdStart            = 0xF3;
const int kCmdStop             = 0xF4;
const int kCmdRequestSession   = 0xF5;
const int kCmdConfirmReceived  = 0xF6;
const int kCmdCalibrate        = 0xF7;
const int kCmdSetTargetDepth   = 0xF8;
const int kCmdSetTargetRate    = 0xF9;
const int kCmdSyncTime         = 0xFA;
const int kCmdSetVentilation   = 0xFB;
const int kCmdRunSelftest      = 0xFC;

// ─────────────────────────────────────────────────────────────────────────────

class BLEDataProcessor {
  const BLEDataProcessor();

  // ── LIVE_STREAM parser (100 bytes, 10 Hz) ────────────────────────────────
  //
  // Byte layout per spec v3.0 Section 3:
  //   0– 3  float32  depth               cm
  //   4– 7  float32  frequency           BPM (5-comp rolling avg)
  //   8–11  float32  force               N (internal)
  //  12–15  float32  instantaneousRate   BPM (last 2 compressions)
  //  16–19  int32    compressionCount
  //  20–23  int32    compressionInCycle  0–30
  //  24–27  float32  wristAlignmentAngle degrees
  //  28–31  float32  wristFlexionAngle   degrees ±45
  //  32–35  float32  compressionAxisDeviation degrees
  //  36–39  float32  depthTrend          cm (5-comp rolling avg)
  //  40     uint8    recoilAchieved      0/1
  //  41     uint8    leaningDetected     0/1
  //  42     uint8    overForceFlag       0/1
  //  43     uint8    postureOk           0/1
  //  44–47  uint32   ventilationCount
  //  48     uint8    fatigueFlag         0/1
  //  49     uint8    rescuerFatigueScore 0–100
  //  50     uint8    imuCalibrated       0/1
  //  51     uint8    wristDropped        0/1
  //  52–55  uint8[4] reserved
  //  56–59  float32  heartRatePatient    BPM (pulse check only)
  //  60–63  float32  spO2Patient         % (pulse check only)
  //  64–67  float32  ppgRaw              0–1 (pulse check only)
  //  68     uint8    ppgSignalQuality    0–100
  //  69     uint8    perfusionIndex      0–100 (pulse check only)
  //  70–71  uint16   patientTemperature  °C × 100 fixed-point (e.g. 3650 = 36.50°C)
  //  72–75  float32  heartRateUser       BPM
  //  76–79  float32  spO2User            %
  //  80     uint8    rescuerSignalQuality 0–100
  //  81     uint8    rescuerRMSSD        ms clamped 0–200
  //  82–83  uint16   rescuerTemperature  °C × 100 fixed-point
  //  84     uint8    rescuerPI           0–100
  //  85–87  uint8[3] reserved
  //  88     uint8    sessionActive       0/1
  //  89     uint8    pulseCheckActive    0/1
  //  90     uint8    currentMode         0/1/2
  //  91     uint8    feedbackEnabled     0/1
  //  92     uint8    batteryPercentage   0–100
  //  93     uint8    isCharging          0/1
  //  94–99  uint8[4] reserved
  //
  // NOTE on temperature encoding (bytes 70–71 and 82–83):
  //   Both temperatures are sent as uint16 fixed-point: value = celsius × 100.
  //   Example: 36.50°C → firmware sends 3650 as little-endian uint16.
  //   App reads with getUint16() and divides by 100.0 to recover the float.
  //   This fits cleanly in 2 bytes with no overlap into neighbouring fields.
  //   Firmware must use: uint16_t raw = (uint16_t)(celsius * 100);

  ParsedBLEData? parseLiveStream(List<int> data) {
    if (data.length != kLiveStreamSize) {
      debugPrint(
        'BLEDataProcessor: LIVE_STREAM wrong length ${data.length} '
            '(expected $kLiveStreamSize)',
      );
      return null;
    }

    try {
      final b = ByteData.sublistView(Uint8List.fromList(data));

      // ── CORE COMPRESSION ──────────────────────────────────────────────────
      final depth              = b.getFloat32(0,  Endian.little);
      final frequency          = b.getFloat32(4,  Endian.little);
      final force              = b.getFloat32(8,  Endian.little);
      final instantaneousRate  = b.getFloat32(12, Endian.little);
      final compressionCount   = b.getInt32  (16, Endian.little);
      final compressionInCycle = b.getInt32  (20, Endian.little);

      // ── POSTURE & ALIGNMENT ───────────────────────────────────────────────
      final wristAlignmentAngle     = b.getFloat32(24, Endian.little);
      final wristFlexionAngle       = b.getFloat32(28, Endian.little);
      final compressionAxisDeviation = b.getFloat32(32, Endian.little);
      final depthTrend              = b.getFloat32(36, Endian.little);

      // ── PER-COMPRESSION FLAGS ─────────────────────────────────────────────
      final recoilAchieved   = b.getUint8(40) == 1;
      final leaningDetected  = b.getUint8(41) == 1;
      final overForceFlag    = b.getUint8(42) == 1;
      final postureOk        = b.getUint8(43) == 1;
      final ventilationCount = b.getUint32(44, Endian.little);

      // ── FATIGUE & IMU STATUS ──────────────────────────────────────────────
      final fatigueFlag         = b.getUint8(48) == 1;
      final rescuerFatigueScore = b.getUint8(49);
      final imuCalibrated       = b.getUint8(50) == 1;
      final wristDropped        = b.getUint8(51) == 1;
      // bytes 52–55 reserved

      // ── PATIENT VITALS ────────────────────────────────────────────────────
      final heartRatePatient  = b.getFloat32(56, Endian.little);
      final spO2Patient       = b.getFloat32(60, Endian.little);
      final ppgRaw            = b.getFloat32(64, Endian.little);
      final ppgSignalQuality  = b.getUint8(68);
      final perfusionIndex    = b.getUint8(69);
      // Temperatures encoded as uint16 fixed-point: value × 100
      // e.g. 36.50°C is stored as 3650. Divide by 100.0 to recover.
      // This uses exactly 2 bytes with no overlap into neighbouring fields.
      final patientTemperatureRaw = b.getUint16(70, Endian.little) / 100.0;

      // ── RESCUER VITALS ────────────────────────────────────────────────────
      final heartRateUser        = b.getFloat32(72, Endian.little);
      final spO2User             = b.getFloat32(76, Endian.little);
      final rescuerSignalQuality = b.getUint8(80);
      final rescuerRMSSD         = b.getUint8(81);
      // rescuerTemperature: read float32 at byte 82 (safe aligned read)
      final rescuerTemperatureRaw = b.getUint16(82, Endian.little) / 100.0;

      final rescuerPI            = b.getUint8(84);
      // bytes 85–87 reserved

      // ── SESSION STATE ─────────────────────────────────────────────────────
      final sessionActive     = b.getUint8(88) == 1;
      final pulseCheckActive  = b.getUint8(89) == 1;
      final currentMode       = b.getUint8(90);
      final feedbackEnabled   = b.getUint8(91) == 1;
      final batteryPercentage = b.getUint8(92);
      final isCharging        = b.getUint8(93) == 1;
      // bytes 94–99 reserved

      // ── Derived: effective depth ──────────────────────────────────────────
      final axisRad    = compressionAxisDeviation * 3.141592653589793 / 180.0;
      final effectiveDepth = depth * _cos(axisRad);

      // ── Sanitise optional readings ────────────────────────────────────────
      final patientTemp = (patientTemperatureRaw > 10.0 && patientTemperatureRaw < 50.0)
          ? patientTemperatureRaw
          : null;
      final rescuerTemp = (rescuerTemperatureRaw > 10.0 && rescuerTemperatureRaw < 50.0)
          ? rescuerTemperatureRaw
          : null;
      final battPct = (batteryPercentage > 0 && batteryPercentage <= 100)
          ? batteryPercentage
          : null;

      return ParsedBLEData(
        isLiveStream:      true,
        isContinuousData:  sessionActive,
        // Core
        depth:             depth,
        frequency:         frequency,
        force:             force,
        instantaneousRate: instantaneousRate,
        compressionCount:  compressionCount,
        compressionInCycle: compressionInCycle,
        // Posture
        wristAlignmentAngle:      wristAlignmentAngle,
        wristFlexionAngle:        wristFlexionAngle,
        compressionAxisDeviation: compressionAxisDeviation,
        depthTrend:               depthTrend,
        effectiveDepth:           effectiveDepth,
        // Flags
        recoilAchieved:      recoilAchieved,
        leaningDetected:     leaningDetected,
        overForceFlag:       overForceFlag,
        postureOk:           postureOk,
        fatigueFlag:         fatigueFlag,
        rescuerFatigueScore: rescuerFatigueScore,
        imuCalibrated:       imuCalibrated,
        wristDropped:        wristDropped,
        ventilationCount:    ventilationCount,
        // Patient vitals
        heartRatePatient:   heartRatePatient,
        spO2Patient:        spO2Patient,
        ppgRaw:             ppgRaw,
        ppgSignalQuality:   ppgSignalQuality,
        perfusionIndex:     perfusionIndex,
        patientTemperature: patientTemp,
        // Rescuer vitals
        heartRateUser:         heartRateUser,
        spO2User:              spO2User,
        rescuerSignalQuality:  rescuerSignalQuality,
        rescuerRMSSD:          rescuerRMSSD,
        rescuerTemperature:    rescuerTemp,
        rescuerPI:             rescuerPI,
        // Session state
        sessionActive:      sessionActive,
        pulseCheckActive:   pulseCheckActive,
        currentMode:        currentMode,
        feedbackEnabled:    feedbackEnabled,
        batteryPercentage:  battPct,
        isCharging:         battPct != null ? isCharging : null,
      );
    } catch (e) {
      debugPrint('BLEDataProcessor: LIVE_STREAM parse error — $e');
      return null;
    }
  }

// ── EVENT_CHANNEL parser (96 bytes, on-event) ────────────────────────────
  // Byte 0 is always the packetType discriminator.
  // All unused bytes are 0x00.

  ParsedBLEData? parseEventChannel(List<int> data) {
    if (data.length != kEventChannelSize) {
      debugPrint(
        'BLEDataProcessor: EVENT_CHANNEL wrong length ${data.length} '
            '(expected $kEventChannelSize)',
      );
      return null;
    }

    try {
      final b          = ByteData.sublistView(Uint8List.fromList(data));
      final packetType = b.getUint8(0);

      switch (packetType) {

      // ── 0x01 SESSION_START ───────────────────────────────────────────────
      // byte[1] = mode  0=Emergency 1=Training 2=No-Feedback
        case kPacketSessionStart:
          return ParsedBLEData._event(
            isStartPing: true,
            currentMode: b.getUint8(1),
          );

      // ── 0x02 SESSION_END ─────────────────────────────────────────────────
      // Full session summary. Byte layout per spec v3.0 Section 4.3.
      //   1      uint8   mode
      //   2– 5   uint32  totalCompressions
      //   6– 9   uint32  correctDepth
      //  10–13   uint32  correctFrequency
      //  14–17   uint32  correctRecoil
      //  18–21   uint32  depthRateCombo
      //  22–25   uint32  correctPosture
      //  26–29   uint32  leaningCount
      //  30–33   uint32  overForceCount
      //  34–37   uint32  tooDeepCount
      //  38–41   uint32  totalVentilations
      //  42–45   uint32  correctVentilations
      //  46–49   uint32  pulseChecksPrompted
      //  50–53   uint32  pulseChecksComplied
      //  54–57   uint32  fatigueOnsetIndex
      //  58–61   float32 peakDepth
      //  62–65   float32 compressionDepthSD
      //  66–69   float32 patientTemperature
      //  70–73   float32 rescuerTemperature
      //  74–77   float32 rescuerHRLastPause
      //  78–81   float32 rescuerSpO2LastPause
      //  82–85   float32 ambientTempStart
      //  86–89   float32 ambientTempEnd
      //  90      uint8   pulseDetected
      //  91      uint8   noFlowIntervals
      //  92      uint8   rescuerSwapCount
      //  93–95   reserved
        case kPacketSessionEnd:
          final patTempEnd  = b.getFloat32(66, Endian.little);
          final resTempEnd  = b.getFloat32(70, Endian.little);
          final ambTmpStart = b.getFloat32(82, Endian.little);
          final ambTmpEnd   = b.getFloat32(86, Endian.little);
          return ParsedBLEData._event(
            isEndPing:           true,
            currentMode:         b.getUint8(1),
            totalCompressions:   b.getUint32(2,  Endian.little),
            correctDepth:        b.getUint32(6,  Endian.little),
            correctFrequency:    b.getUint32(10, Endian.little),
            correctRecoil:       b.getUint32(14, Endian.little),
            depthRateCombo:      b.getUint32(18, Endian.little),
            correctPosture:      b.getUint32(22, Endian.little),
            leaningCount:        b.getUint32(26, Endian.little),
            overForceCount:      b.getUint32(30, Endian.little),
            tooDeepCount:        b.getUint32(34, Endian.little),
            totalVentilations:   b.getUint32(38, Endian.little),
            correctVentilations: b.getUint32(42, Endian.little),
            pulseChecksPrompted: b.getUint32(46, Endian.little),
            pulseChecksComplied: b.getUint32(50, Endian.little),
            fatigueOnsetIndex:   b.getUint32(54, Endian.little),
            peakDepth:           b.getFloat32(58, Endian.little),
            compressionDepthSD:  b.getFloat32(62, Endian.little),
            patientTemperature:  (patTempEnd  > 10 && patTempEnd  < 50) ? patTempEnd  : null,
            rescuerTemperatureEnd: (resTempEnd > 10 && resTempEnd < 50) ? resTempEnd  : null,
            rescuerHRLastPause:  b.getFloat32(74, Endian.little),
            rescuerSpO2LastPause: b.getFloat32(78, Endian.little),
            ambientTempStart:    (ambTmpStart > 5 && ambTmpStart < 55) ? ambTmpStart : null,
            ambientTempEnd:      (ambTmpEnd   > 5 && ambTmpEnd   < 55) ? ambTmpEnd   : null,
            pulseDetected:       b.getUint8(90),
            noFlowIntervalsEnd:  b.getUint8(91),
            rescuerSwapCountEnd: b.getUint8(92),
          );

      // ── 0x03 VENTILATION_WINDOW ──────────────────────────────────────────
      // byte[1–2] uint16 cycleNumber  (starts at 1)
      // byte[3]   uint8  ventilationsExpected (always 2 for adult)
        case kPacketVentilationWindow:
          return ParsedBLEData._event(
            isVentilationWindow:      true,
            cycleNumber:              b.getUint16(1, Endian.little),
            ventilationsExpected:     b.getUint8(3),
          );

      // ── 0x04 PULSE_CHECK_START ───────────────────────────────────────────
      // byte[1–2] uint16 intervalNumber
        case kPacketPulseCheckStart:
          return ParsedBLEData._event(
            isPulseCheckStart: true,
            intervalNumber:    b.getUint16(1, Endian.little),
          );

      // ── 0x05 PULSE_CHECK_RESULT ──────────────────────────────────────────
      // byte[1]   uint8   classification  0=absent 1=uncertain 2=present
      // byte[2–5] float32 detectedBPM
      // byte[6]   uint8   confidencePct   0–100
      // byte[7]   uint8   detectorACount
      // byte[8]   uint8   detectorBCount
        case kPacketPulseCheckResult:
          return ParsedBLEData._event(
            isPulseCheckResult: true,
            pulseClassification: b.getUint8(1),
            detectedBPM:         b.getFloat32(2, Endian.little),
            confidencePct:       b.getUint8(6),
            detectorACount:      b.getUint8(7),
            detectorBCount:      b.getUint8(8),
          );

      // ── 0x06 MODE_CHANGE ─────────────────────────────────────────────────
      // byte[1] uint8 newMode      0/1/2
      // byte[2] uint8 triggeredBy  0=button 1=app command
        case kPacketModeChange:
          return ParsedBLEData._event(
            isModeChange:       true,
            currentMode:        b.getUint8(1),
            modeChangeTrigger:  b.getUint8(2),
          );

      // ── 0x07 TWO_MIN_ALERT ───────────────────────────────────────────────
      // byte[1] uint8 alertNumber  (how many times fired this session)
        case kPacketTwoMinAlert:
          return ParsedBLEData._event(
            isTwoMinAlert:    true,
            twoMinAlertNumber: b.getUint8(1),
          );

      // ── 0x08 FATIGUE_ALERT ───────────────────────────────────────────────
      // byte[1] uint8 fatigueScore  0–100
        case kPacketFatigueAlert:
          return ParsedBLEData._event(
            isFatigueAlert:      true,
            fatigueAlertScore:   b.getUint8(1),
          );

      // ── 0x09 PENDING_LOCAL_DATA ──────────────────────────────────────────
      // byte[1] uint8 pendingCount  0–20
        case kPacketPendingLocalData:
          return ParsedBLEData._event(
            isPendingLocalData:  true,
            pendingSessionCount: b.getUint8(1),
          );

      // ── 0x0A LOCAL_SESSION_CHUNK ─────────────────────────────────────────
      // byte[1] sessionIndex  byte[2] chunkIndex  byte[3] totalChunks
      // bytes[4–79] = 76 bytes of session data
        case kPacketLocalSessionChunk:
          return ParsedBLEData._event(
            isLocalSessionChunk: true,
            localSessionIndex:   b.getUint8(1),
            localChunkIndex:     b.getUint8(2),
            localTotalChunks:    b.getUint8(3),
            // Chunk data occupies bytes 4–79 (76 bytes) per spec v3.0.
// Bytes 80–95 are reserved. Update range if firmware expands chunk size.
            localChunkData: data.sublist(4, 80),
          );

      // ── 0x0B SELFTEST_RESULT ─────────────────────────────────────────────
      // byte[1] passMask    byte[2] warnMask  byte[3] criticalMask
      // byte[4] batteryPct
        case kPacketSelftestResult:
          return ParsedBLEData._event(
            isSelftestResult:    true,
            selftestPassMask:    b.getUint8(1),
            selftestWarnMask:    b.getUint8(2),
            selftestCriticalMask: b.getUint8(3),
            selftestBatteryPct:  b.getUint8(4),
          );

      // ── 0x0C SCENARIO_CHANGE ─────────────────────────────────────────────────
// byte[1] uint8 scenario      0=adult 1=pediatric
// byte[2] uint8 triggeredBy   0=button 1=app command
        case kPacketScenarioChange:
          return ParsedBLEData._event(
            isScenarioChange:      true,
            scenarioFromGlove:     b.getUint8(1),
            scenarioChangeTrigger: b.getUint8(2),
          );

        default:
          debugPrint(
            'BLEDataProcessor: unknown EVENT_CHANNEL type '
                '0x${packetType.toRadixString(16).padLeft(2, '0')}',
          );
          return null;
      }
    } catch (e) {
      debugPrint('BLEDataProcessor: EVENT_CHANNEL parse error — $e');
      return null;
    }
  }

  // ── cos approximation (avoids dart:math import in data layer) ────────────
  // Taylor series: cos(x) ≈ 1 - x²/2 + x⁴/24 — accurate to < 0.001 for 0–π/2
  static double _cos(double radians) {
    final x2 = radians * radians;
    return 1.0 - x2 / 2.0 + (x2 * x2) / 24.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ParsedBLEData — immutable value object
//
// Holds fields from BOTH characteristics. Fields unused by a given packet
// type default to 0 / false / null.
//
// Constructor is private-ish: use the named constructor ParsedBLEData._event()
// for EVENT_CHANNEL packets; the main constructor is for LIVE_STREAM.
// ─────────────────────────────────────────────────────────────────────────────

class ParsedBLEData {
  // ── Source / event flags ──────────────────────────────────────────────────
  final bool isLiveStream;
  final bool isStartPing;
  final bool isEndPing;
  final bool isScenarioChange;
  final int? scenarioFromGlove;      // 0=adult 1=pediatric
  final int? scenarioChangeTrigger;  // 0=button 1=app command
  final bool isContinuousData;      // true when sessionActive = 1 in LIVE_STREAM
  final bool isVentilationWindow;
  final bool isPulseCheckStart;
  final bool isPulseCheckResult;
  final bool isModeChange;
  final bool isTwoMinAlert;
  final bool isFatigueAlert;
  final bool isPendingLocalData;
  final bool isLocalSessionChunk;
  final bool isSelftestResult;

  // ── LIVE_STREAM: core compression ────────────────────────────────────────
  final double depth;
  final double frequency;           // 5-comp rolling avg (for display)
  final double force;               // Newtons (internal)
  final double instantaneousRate;   // per-compression rate (for grading)
  final int    compressionCount;
  final int    compressionInCycle;  // 0–30

  // ── LIVE_STREAM: posture & alignment ─────────────────────────────────────
  final double wristAlignmentAngle;
  final double wristFlexionAngle;
  final double compressionAxisDeviation;
  final double depthTrend;          // 5-comp rolling avg depth
  final double effectiveDepth;      // depth × cos(axisDeviation)

  // ── LIVE_STREAM: per-compression flags ───────────────────────────────────
  final bool recoilAchieved;
  final bool leaningDetected;
  final bool overForceFlag;
  final bool postureOk;
  final bool fatigueFlag;
  final int  rescuerFatigueScore;   // 0–100 physiological score
  final bool imuCalibrated;         // false during warmup (first 3 compressions)
  final bool wristDropped;          // true if wrist IMU dropped out
  final int  ventilationCount;      // running total since SESSION_START

  // ── LIVE_STREAM: patient vitals ───────────────────────────────────────────
  final double  heartRatePatient;
  final double  spO2Patient;
  final double  ppgRaw;
  final int     ppgSignalQuality;
  final int     perfusionIndex;
  final double? patientTemperature;

  // ── LIVE_STREAM: rescuer vitals ───────────────────────────────────────────
  final double  heartRateUser;
  final double  spO2User;
  final int     rescuerSignalQuality;
  final int     rescuerRMSSD;       // HRV ms clamped 0–200
  final double? rescuerTemperature;
  final int     rescuerPI;          // perfusion index 0–100

  // ── LIVE_STREAM: session state ────────────────────────────────────────────
  final bool  sessionActive;
  final bool  pulseCheckActive;
  final int   currentMode;          // 0=Emergency 1=Training 2=No-Feedback
  final bool  feedbackEnabled;
  final int?  batteryPercentage;
  final bool? isCharging;

  // ── SESSION_END summary fields ────────────────────────────────────────────
  final int    totalCompressions;
  final int    correctDepth;
  final int    correctFrequency;
  final int    correctRecoil;
  final int    depthRateCombo;
  final int    correctPosture;
  final int    leaningCount;
  final int    overForceCount;
  final int    tooDeepCount;
  final int    totalVentilations;
  final int    correctVentilations;
  final int    pulseChecksPrompted;
  final int    pulseChecksComplied;
  final int    fatigueOnsetIndex;
  final double peakDepth;
  final double compressionDepthSD;
  final int?   pulseDetected;       // 1 = pulse present at last check
  final int    noFlowIntervalsEnd;  // count of unplanned pauses > 2 s
  final int    rescuerSwapCountEnd; // TWO_MIN_ALERT events fired
  // Rescuer vitals captured at last pause
  final double? rescuerHRLastPause;
  final double? rescuerSpO2LastPause;
  final double? rescuerTemperatureEnd;
  final double? ambientTempStart;
  final double? ambientTempEnd;

  // ── VENTILATION_WINDOW fields ─────────────────────────────────────────────
  final int? cycleNumber;
  final int? ventilationsExpected;

  // ── PULSE_CHECK_START fields ──────────────────────────────────────────────
  final int? intervalNumber;

  // ── PULSE_CHECK_RESULT fields ─────────────────────────────────────────────
  final int?    pulseClassification; // 0=absent 1=uncertain 2=present
  final double? detectedBPM;
  final int?    confidencePct;
  final int?    detectorACount;
  final int?    detectorBCount;

  // ── MODE_CHANGE fields ────────────────────────────────────────────────────
  final int? modeChangeTrigger; // 0=button 1=app command

  // ── TWO_MIN_ALERT fields ──────────────────────────────────────────────────
  final int? twoMinAlertNumber;

  // ── FATIGUE_ALERT fields ──────────────────────────────────────────────────
  final int? fatigueAlertScore;

  // ── PENDING_LOCAL_DATA fields ─────────────────────────────────────────────
  final int? pendingSessionCount;

  // ── LOCAL_SESSION_CHUNK fields ────────────────────────────────────────────
  final int?        localSessionIndex;
  final int?        localChunkIndex;
  final int?        localTotalChunks;
  final List<int>?  localChunkData;

  // ── SELFTEST_RESULT fields ────────────────────────────────────────────────
  final int? selftestPassMask;
  final int? selftestWarnMask;
  final int? selftestCriticalMask;
  final int? selftestBatteryPct;

  const ParsedBLEData({
    this.isLiveStream          = false,
    this.isStartPing           = false,
    this.isEndPing             = false,
    this.isContinuousData      = false,
    this.isScenarioChange      = false,
    this.scenarioFromGlove,
    this.scenarioChangeTrigger,
    this.isVentilationWindow   = false,
    this.isPulseCheckStart     = false,
    this.isPulseCheckResult    = false,
    this.isModeChange          = false,
    this.isTwoMinAlert         = false,
    this.isFatigueAlert        = false,
    this.isPendingLocalData    = false,
    this.isLocalSessionChunk   = false,
    this.isSelftestResult      = false,
    this.depth                 = 0,
    this.frequency             = 0,
    this.force                 = 0,
    this.instantaneousRate     = 0,
    this.compressionCount      = 0,
    this.compressionInCycle    = 0,
    this.wristAlignmentAngle   = 0,
    this.wristFlexionAngle     = 0,
    this.compressionAxisDeviation = 0,
    this.depthTrend            = 0,
    this.effectiveDepth        = 0,
    this.recoilAchieved        = false,
    this.leaningDetected       = false,
    this.overForceFlag         = false,
    this.postureOk             = false,
    this.fatigueFlag           = false,
    this.rescuerFatigueScore   = 0,
    this.imuCalibrated         = false,
    this.wristDropped          = false,
    this.ventilationCount      = 0,
    this.heartRatePatient      = 0,
    this.spO2Patient           = 0,
    this.ppgRaw                = 0,
    this.ppgSignalQuality      = 0,
    this.perfusionIndex        = 0,
    this.patientTemperature,
    this.heartRateUser         = 0,
    this.spO2User              = 0,
    this.rescuerSignalQuality  = 0,
    this.rescuerRMSSD          = 0,
    this.rescuerTemperature,
    this.rescuerPI             = 0,
    this.sessionActive         = false,
    this.pulseCheckActive      = false,
    this.currentMode           = 0,
    this.feedbackEnabled       = true,
    this.batteryPercentage,
    this.isCharging,
    this.totalCompressions     = 0,
    this.correctDepth          = 0,
    this.correctFrequency      = 0,
    this.correctRecoil         = 0,
    this.depthRateCombo        = 0,
    this.correctPosture        = 0,
    this.leaningCount          = 0,
    this.overForceCount        = 0,
    this.tooDeepCount          = 0,
    this.totalVentilations     = 0,
    this.correctVentilations   = 0,
    this.pulseChecksPrompted   = 0,
    this.pulseChecksComplied   = 0,
    this.fatigueOnsetIndex     = 0,
    this.peakDepth             = 0,
    this.compressionDepthSD    = 0,
    this.pulseDetected,
    this.noFlowIntervalsEnd    = 0,
    this.rescuerSwapCountEnd   = 0,
    this.rescuerHRLastPause,
    this.rescuerSpO2LastPause,
    this.rescuerTemperatureEnd,
    this.ambientTempStart,
    this.ambientTempEnd,
    this.cycleNumber,
    this.ventilationsExpected,
    this.intervalNumber,
    this.pulseClassification,
    this.detectedBPM,
    this.confidencePct,
    this.detectorACount,
    this.detectorBCount,
    this.modeChangeTrigger,
    this.twoMinAlertNumber,
    this.fatigueAlertScore,
    this.pendingSessionCount,
    this.localSessionIndex,
    this.localChunkIndex,
    this.localTotalChunks,
    this.localChunkData,
    this.selftestPassMask,
    this.selftestWarnMask,
    this.selftestCriticalMask,
    this.selftestBatteryPct,
  });

  /// Named constructor for EVENT_CHANNEL packets.
  /// All LIVE_STREAM fields default to 0/false so callers only specify
  /// what the packet actually carries.
  const ParsedBLEData._event({
    bool   isStartPing           = false,
    bool   isEndPing             = false,
    bool   isScenarioChange      = false,
    int?   scenarioFromGlove,
    int?   scenarioChangeTrigger,
    bool   isVentilationWindow   = false,
    bool   isPulseCheckStart     = false,
    bool   isPulseCheckResult    = false,
    bool   isModeChange          = false,
    bool   isTwoMinAlert         = false,
    bool   isFatigueAlert        = false,
    bool   isPendingLocalData    = false,
    bool   isLocalSessionChunk   = false,
    bool   isSelftestResult      = false,
    int    currentMode           = 0,
    int    totalCompressions     = 0,
    int    correctDepth          = 0,
    int    correctFrequency      = 0,
    int    correctRecoil         = 0,
    int    depthRateCombo        = 0,
    int    correctPosture        = 0,
    int    leaningCount          = 0,
    int    overForceCount        = 0,
    int    tooDeepCount          = 0,
    int    totalVentilations     = 0,
    int    correctVentilations   = 0,
    int    pulseChecksPrompted   = 0,
    int    pulseChecksComplied   = 0,
    int    fatigueOnsetIndex     = 0,
    double peakDepth             = 0,
    double compressionDepthSD    = 0,
    int?   pulseDetected,
    int    noFlowIntervalsEnd    = 0,
    int    rescuerSwapCountEnd   = 0,
    double? patientTemperature,
    double? rescuerTemperatureEnd,
    double? rescuerHRLastPause,
    double? rescuerSpO2LastPause,
    double? ambientTempStart,
    double? ambientTempEnd,
    int?   cycleNumber,
    int?   ventilationsExpected,
    int?   intervalNumber,
    int?   pulseClassification,
    double? detectedBPM,
    int?   confidencePct,
    int?   detectorACount,
    int?   detectorBCount,
    int?   modeChangeTrigger,
    int?   twoMinAlertNumber,
    int?   fatigueAlertScore,
    int?   pendingSessionCount,
    int?   localSessionIndex,
    int?   localChunkIndex,
    int?   localTotalChunks,
    List<int>? localChunkData,
    int?   selftestPassMask,
    int?   selftestWarnMask,
    int?   selftestCriticalMask,
    int?   selftestBatteryPct,
  }) : this(
    isStartPing:           isStartPing,
    isEndPing:             isEndPing,
    isScenarioChange:      isScenarioChange,
    scenarioFromGlove:     scenarioFromGlove,
    scenarioChangeTrigger: scenarioChangeTrigger,
    isVentilationWindow:   isVentilationWindow,
    isPulseCheckStart:     isPulseCheckStart,
    isPulseCheckResult:    isPulseCheckResult,
    isModeChange:          isModeChange,
    isTwoMinAlert:         isTwoMinAlert,
    isFatigueAlert:        isFatigueAlert,
    isPendingLocalData:    isPendingLocalData,
    isLocalSessionChunk:   isLocalSessionChunk,
    isSelftestResult:      isSelftestResult,
    currentMode:           currentMode,
    totalCompressions:     totalCompressions,
    correctDepth:          correctDepth,
    correctFrequency:      correctFrequency,
    correctRecoil:         correctRecoil,
    depthRateCombo:        depthRateCombo,
    correctPosture:        correctPosture,
    leaningCount:          leaningCount,
    overForceCount:        overForceCount,
    tooDeepCount:          tooDeepCount,
    totalVentilations:     totalVentilations,
    correctVentilations:   correctVentilations,
    pulseChecksPrompted:   pulseChecksPrompted,
    pulseChecksComplied:   pulseChecksComplied,
    fatigueOnsetIndex:     fatigueOnsetIndex,
    peakDepth:             peakDepth,
    compressionDepthSD:    compressionDepthSD,
    pulseDetected:         pulseDetected,
    noFlowIntervalsEnd:    noFlowIntervalsEnd,
    rescuerSwapCountEnd:   rescuerSwapCountEnd,
    patientTemperature:    patientTemperature,
    rescuerTemperatureEnd: rescuerTemperatureEnd,
    rescuerHRLastPause:    rescuerHRLastPause,
    rescuerSpO2LastPause:  rescuerSpO2LastPause,
    ambientTempStart:      ambientTempStart,
    ambientTempEnd:        ambientTempEnd,
    cycleNumber:           cycleNumber,
    ventilationsExpected:  ventilationsExpected,
    intervalNumber:        intervalNumber,
    pulseClassification:   pulseClassification,
    detectedBPM:           detectedBPM,
    confidencePct:         confidencePct,
    detectorACount:        detectorACount,
    detectorBCount:        detectorBCount,
    modeChangeTrigger:     modeChangeTrigger,
    twoMinAlertNumber:     twoMinAlertNumber,
    fatigueAlertScore:     fatigueAlertScore,
    pendingSessionCount:   pendingSessionCount,
    localSessionIndex:     localSessionIndex,
    localChunkIndex:       localChunkIndex,
    localTotalChunks:      localTotalChunks,
    localChunkData:        localChunkData,
    selftestPassMask:      selftestPassMask,
    selftestWarnMask:      selftestWarnMask,
    selftestCriticalMask:  selftestCriticalMask,
    selftestBatteryPct:    selftestBatteryPct,
  );
}