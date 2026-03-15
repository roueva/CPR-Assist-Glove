import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BLEDataProcessor  —  BLE Spec v2.0
//
// The glove exposes two BLE characteristics:
//
//   LIVE_STREAM  (UUID 19b10001-...)  88 bytes, 10 Hz, notify
//     Drives depth bar, rate gauge, posture, vitals, PPG waveform.
//
//   EVENT_CHANNEL (UUID 19b10002-...) 80 bytes, on-event, notify + write
//     Session lifecycle: SESSION_START, SESSION_END, VENTILATION_WINDOW,
//     PULSE_CHECK_START, PULSE_CHECK_RESULT, MODE_CHANGE, TWO_MIN_ALERT,
//     FATIGUE_ALERT, PENDING_LOCAL_DATA, LOCAL_SESSION_CHUNK.
//
// All multi-byte values are little-endian.
// No decryption — data arrives already readable.
// ─────────────────────────────────────────────────────────────────────────────

// ── Packet type constants (byte 0 of EVENT_CHANNEL) ──────────────────────────

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

// ── Packet sizes ──────────────────────────────────────────────────────────────

const int kLiveStreamSize   = 88;
const int kEventChannelSize = 80;

class BLEDataProcessor {
  const BLEDataProcessor();

  // ── LIVE_STREAM parser (88 bytes) ─────────────────────────────────────────

  /// Parse a LIVE_STREAM packet. Returns null if malformed.
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

      // ── CORE COMPRESSION (bytes 0–23) ─────────────────────────────────────
      final depth             = b.getFloat32(0,  Endian.little);
      final frequency         = b.getFloat32(4,  Endian.little);
      final force             = b.getFloat32(8,  Endian.little);
      final instantaneousRate = b.getFloat32(12, Endian.little);
      final compressionCount  = b.getInt32  (16, Endian.little);
      final compressionInCycle= b.getInt32  (20, Endian.little);

      // ── POSTURE & ALIGNMENT (bytes 24–35) ────────────────────────────────
      final wristAlignmentAngle    = b.getFloat32(24, Endian.little);
      final wristFlexionAngle      = b.getFloat32(28, Endian.little);
      final compressionAxisDeviation = b.getFloat32(32, Endian.little);

      // ── PER-COMPRESSION FLAGS (bytes 36–43) ──────────────────────────────
      final recoilAchieved   = b.getUint8(36) == 1;
      final leaningDetected  = b.getUint8(37) == 1;
      final overForceFlag    = b.getUint8(38) == 1;
      final postureOk        = b.getUint8(39) == 1;
      final ventilationCount = b.getUint32(40, Endian.little);

      // ── FATIGUE (bytes 44–47) ─────────────────────────────────────────────
      final fatigueFlag = b.getUint8(44) == 1;

      // ── PATIENT VITALS (bytes 48–63) ──────────────────────────────────────
      final heartRatePatient   = b.getFloat32(48, Endian.little);
      final spO2Patient        = b.getFloat32(52, Endian.little);
      final ppgRaw             = b.getFloat32(56, Endian.little);
      final ppgSignalQuality   = b.getUint8(60);
      final perfusionIndex     = b.getUint8(61);
      // bytes 62–63: float32_lo patientTemperature (split across 2 bytes in spec,
      // treat as the low 2 bytes of a 4-byte float — read as full float32 at 60,
      // but the spec lays it at 62 as a partial float. Read conservatively as
      // a uint16 reinterpreted — safer to read full float32 at byte 60 instead.
      // The spec lists ppgSignalQuality at 60 (uint8) and perfusionIndex at 61
      // (uint8), then patientTemperature at 62 as "float32_lo" meaning only 2 bytes.
      // We treat it as a float32 at byte 60 to avoid misalignment issues.
      // TODO: confirm byte-exact layout with firmware before ship.
      final patientTemperature = b.getFloat32(48 + 14, Endian.little); // bytes 62–65 (safe read)

      // ── RESCUER VITALS (bytes 64–75) ──────────────────────────────────────
      final heartRateUser       = b.getFloat32(64, Endian.little);
      final spO2User            = b.getFloat32(68, Endian.little);
      final rescuerSignalQuality = b.getUint8(72);
      // bytes 73–75: float32_lo rescuerTemperature (3 bytes — partial float)
      // Read full float32 from byte 72 to get the temperature component safely.
      // TODO: confirm with firmware.
      final rescuerTemperature  = b.getFloat32(72, Endian.little); // bytes 72–75

      // ── SESSION STATE (bytes 76–87) ────────────────────────────────────────
      final sessionActive     = b.getUint8(76) == 1;
      final pulseCheckActive  = b.getUint8(77) == 1;
      final currentMode       = b.getUint8(78);
      final feedbackEnabled   = b.getUint8(79) == 1;
      final batteryPercentage = b.getUint8(80);
      final isCharging        = b.getUint8(81) == 1;

      // Effective depth = depth × cos(compressionAxisDeviation in radians)
      final axisRad = compressionAxisDeviation * 3.141592653589793 / 180.0;
      // Using a Taylor approximation for cos: 1 - x²/2 + x⁴/24 (accurate for 0–90°)
      final cosAxis = _cos(axisRad);
      final effectiveDepth = depth * cosAxis;

      return ParsedBLEData(
        // Source flags
        isLiveStream:       true,
        isStartPing:        false,
        isEndPing:          false,
        isContinuousData:   sessionActive,
        isVentilationWindow: false,
        isPulseCheckStart:  false,
        isPulseCheckResult: false,
        isTwoMinAlert:      false,
        isFatigueAlert:     false,
        isPendingLocalData: false,
        // Core
        depth:              depth,
        frequency:          frequency,
        force:              force,
        instantaneousRate:  instantaneousRate,
        compressionCount:   compressionCount,
        compressionInCycle: compressionInCycle,
        angle:              wristAlignmentAngle,
        // Posture
        wristAlignmentAngle:     wristAlignmentAngle,
        wristFlexionAngle:       wristFlexionAngle,
        compressionAxisDeviation: compressionAxisDeviation,
        effectiveDepth:          effectiveDepth,
        // Flags
        recoilAchieved:  recoilAchieved,
        leaningDetected: leaningDetected,
        overForceFlag:   overForceFlag,
        postureOk:       postureOk,
        fatigueFlag:     fatigueFlag,
        ventilationCount: ventilationCount,
        // Patient vitals
        heartRatePatient:  heartRatePatient,
        spO2Patient:       spO2Patient,
        ppgRaw:            ppgRaw,
        ppgSignalQuality:  ppgSignalQuality,
        perfusionIndex:    perfusionIndex,
        patientTemperature: patientTemperature > 0 ? patientTemperature : null,
        // Rescuer vitals
        heartRateUser:        heartRateUser,
        spO2User:             spO2User,
        rescuerSignalQuality: rescuerSignalQuality,
        rescuerTemperature:   rescuerTemperature,
        temperatureUser:      rescuerTemperature,
        temperaturePatient:   patientTemperature > 0 ? patientTemperature : 0,
        // Session state
        sessionActive:    sessionActive,
        pulseCheckActive: pulseCheckActive,
        currentMode:      currentMode,
        feedbackEnabled:  feedbackEnabled,
        batteryPercentage: batteryPercentage > 0 && batteryPercentage <= 100
            ? batteryPercentage
            : null,
        isCharging: batteryPercentage > 0 ? isCharging : null,
        // SESSION_END fields — not present in LIVE_STREAM
        correctDepth:      0,
        correctFrequency:  0,
        correctRecoil:     0,
        depthRateCombo:    0,
        totalCompressions: 0,
        correctPosture:    0,
        leaningCount:      0,
        overForceCount:    0,
        tooDeepCount:      0,
        totalVentilations: ventilationCount,
        correctVentilations: 0,
        pulseChecksPrompted: 0,
        pulseChecksComplied: 0,
        pulseDetected:     null,
        fatigueOnsetIndex: 0,
        peakDepth:         0,
      );
    } catch (e) {
      debugPrint('BLEDataProcessor: LIVE_STREAM parse error — $e');
      return null;
    }
  }

  // ── EVENT_CHANNEL parser (80 bytes) ───────────────────────────────────────

  /// Parse an EVENT_CHANNEL packet. Returns null if malformed.
  ParsedBLEData? parseEventChannel(List<int> data) {
    if (data.length != kEventChannelSize) {
      debugPrint(
        'BLEDataProcessor: EVENT_CHANNEL wrong length ${data.length} '
            '(expected $kEventChannelSize)',
      );
      return null;
    }

    try {
      final b           = ByteData.sublistView(Uint8List.fromList(data));
      final packetType  = b.getUint8(0);

      switch (packetType) {
      // ── SESSION_START (0x01) ───────────────────────────────────────────
        case kPacketSessionStart:
          return ParsedBLEData._event(
            isStartPing: true,
            currentMode: b.getUint8(1),
          );

      // ── SESSION_END (0x02) ────────────────────────────────────────────
        case kPacketSessionEnd:
          return ParsedBLEData._event(
            isEndPing:         true,
            currentMode:       b.getUint8(1),
            totalCompressions: b.getUint32(2,  Endian.little),
            correctDepth:      b.getUint32(6,  Endian.little),
            correctFrequency:  b.getUint32(10, Endian.little),
            correctRecoil:     b.getUint32(14, Endian.little),
            depthRateCombo:    b.getUint32(18, Endian.little),
            correctPosture:    b.getUint32(22, Endian.little),
            leaningCount:      b.getUint32(26, Endian.little),
            overForceCount:    b.getUint32(30, Endian.little),
            tooDeepCount:      b.getUint32(34, Endian.little),
            totalVentilations: b.getUint32(38, Endian.little),
            correctVentilations: b.getUint32(42, Endian.little),
            pulseChecksPrompted: b.getUint32(46, Endian.little),
            pulseChecksComplied: b.getUint32(50, Endian.little),
            fatigueOnsetIndex:   b.getUint32(54, Endian.little),
            peakDepth:           b.getFloat32(58, Endian.little),
            patientTemperature:  b.getFloat32(62, Endian.little),
            rescuerTemperature:  b.getFloat32(66, Endian.little),
            heartRateUser:       b.getFloat32(70, Endian.little),
            spO2User:            b.getFloat32(74, Endian.little),
            pulseDetected:       b.getUint8(78),
          );

      // ── VENTILATION_WINDOW (0x03) ──────────────────────────────────────
        case kPacketVentilationWindow:
          return ParsedBLEData._event(
            isVentilationWindow: true,
            cycleNumber:  b.getUint16(1, Endian.little),
          );

      // ── PULSE_CHECK_START (0x04) ───────────────────────────────────────
        case kPacketPulseCheckStart:
          return ParsedBLEData._event(
            isPulseCheckStart: true,
            intervalNumber:    b.getUint16(1, Endian.little),
            sessionElapsedMs:  b.getUint32(3, Endian.little),
          );

      // ── PULSE_CHECK_RESULT (0x05) ──────────────────────────────────────
        case kPacketPulseCheckResult:
          return ParsedBLEData._event(
            isPulseCheckResult: true,
            pulseDetected:      b.getUint8(1),
            detectedBPM:        b.getFloat32(2, Endian.little),
            confidencePct:      b.getUint8(6),
          );

      // ── MODE_CHANGE (0x06) ─────────────────────────────────────────────
        case kPacketModeChange:
          return ParsedBLEData._event(
            currentMode: b.getUint8(1),
          );

      // ── TWO_MIN_ALERT (0x07) ───────────────────────────────────────────
        case kPacketTwoMinAlert:
          return const ParsedBLEData._event(isTwoMinAlert: true);

      // ── FATIGUE_ALERT (0x08) ───────────────────────────────────────────
        case kPacketFatigueAlert:
          return const ParsedBLEData._event(isFatigueAlert: true);

      // ── PENDING_LOCAL_DATA (0x09) ──────────────────────────────────────
        case kPacketPendingLocalData:
          return ParsedBLEData._event(
            isPendingLocalData: true,
            pendingSessionCount: b.getUint8(1),
          );

        default:
          debugPrint(
              'BLEDataProcessor: unknown EVENT_CHANNEL packet type 0x${packetType.toRadixString(16)}');
          return null;
      }
    } catch (e) {
      debugPrint('BLEDataProcessor: EVENT_CHANNEL parse error — $e');
      return null;
    }
  }

  // ── Legacy shim — called by existing BLEConnection._handlePacket ──────────

  /// Auto-detects packet type by length and routes to the correct parser.
  /// 88 bytes → LIVE_STREAM, 80 bytes → EVENT_CHANNEL.
  /// Keeps BLEConnection working without requiring it to know which
  /// characteristic the packet came from.
  ParsedBLEData? parsePacket(List<int> data) {
    if (data.length == kLiveStreamSize)   return parseLiveStream(data);
    if (data.length == kEventChannelSize) return parseEventChannel(data);
    debugPrint(
      'BLEDataProcessor: unknown packet length ${data.length} — skipped',
    );
    return null;
  }

  // ── cos approximation (no dart:math import needed in data layer) ───────────

  static double _cos(double radians) {
    // Taylor series: cos(x) ≈ 1 - x²/2 + x⁴/24 — accurate to < 0.001 for 0–π/2
    final x2 = radians * radians;
    return 1.0 - x2 / 2.0 + (x2 * x2) / 24.0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ParsedBLEData — immutable value object
// Holds fields from BOTH LIVE_STREAM and EVENT_CHANNEL packets.
// Unused fields default to 0 / false / null.
// ─────────────────────────────────────────────────────────────────────────────

class ParsedBLEData {
  // ── Source flags ──────────────────────────────────────────────────────────
  final bool isLiveStream;
  final bool isStartPing;
  final bool isEndPing;
  final bool isContinuousData;
  final bool isVentilationWindow;
  final bool isPulseCheckStart;
  final bool isPulseCheckResult;
  final bool isTwoMinAlert;
  final bool isFatigueAlert;
  final bool isPendingLocalData;

  // ── Core compression (LIVE_STREAM) ────────────────────────────────────────
  final double depth;
  final double frequency;
  final double force;
  final double instantaneousRate;
  final int    compressionCount;
  final int    compressionInCycle;

  /// Legacy alias — equals wristAlignmentAngle.
  final double angle;

  // ── Posture (LIVE_STREAM) ─────────────────────────────────────────────────
  final double wristAlignmentAngle;
  final double wristFlexionAngle;
  final double compressionAxisDeviation;
  final double effectiveDepth;

  // ── Per-compression flags (LIVE_STREAM) ───────────────────────────────────
  final bool recoilAchieved;
  final bool leaningDetected;
  final bool overForceFlag;
  final bool postureOk;
  final bool fatigueFlag;
  final int  ventilationCount;

  // ── Patient vitals (LIVE_STREAM) ──────────────────────────────────────────
  final double  heartRatePatient;
  final double  spO2Patient;
  final double  ppgRaw;
  final int     ppgSignalQuality;
  final int     perfusionIndex;
  final double? patientTemperature;

  // ── Rescuer vitals (LIVE_STREAM) ──────────────────────────────────────────
  final double heartRateUser;
  final double spO2User;
  final int    rescuerSignalQuality;
  final double rescuerTemperature;

  /// Legacy alias — equals rescuerTemperature.
  final double temperatureUser;
  final double temperaturePatient;

  // ── Session state (LIVE_STREAM) ───────────────────────────────────────────
  final bool sessionActive;
  final bool pulseCheckActive;
  final int  currentMode;
  final bool feedbackEnabled;
  final int? batteryPercentage;
  final bool? isCharging;

  // ── SESSION_END summary fields (EVENT_CHANNEL 0x02) ──────────────────────
  final int    correctDepth;
  final int    correctFrequency;
  final int    correctRecoil;
  final int    depthRateCombo;
  final int    totalCompressions;
  final int    correctPosture;
  final int    leaningCount;
  final int    overForceCount;
  final int    tooDeepCount;
  final int    totalVentilations;
  final int    correctVentilations;
  final int    pulseChecksPrompted;
  final int    pulseChecksComplied;
  final int?   pulseDetected;
  final int    fatigueOnsetIndex;
  final double peakDepth;

  // ── VENTILATION_WINDOW fields (EVENT_CHANNEL 0x03) ────────────────────────
  final int? cycleNumber;

  // ── PULSE_CHECK_START fields (EVENT_CHANNEL 0x04) ─────────────────────────
  final int? intervalNumber;
  final int? sessionElapsedMs;

  // ── PULSE_CHECK_RESULT fields (EVENT_CHANNEL 0x05) ────────────────────────
  final double? detectedBPM;
  final int?    confidencePct;

  // ── PENDING_LOCAL_DATA fields (EVENT_CHANNEL 0x09) ────────────────────────
  final int? pendingSessionCount;

  // ── Rescuer vitals from SESSION_END ──────────────────────────────────────
  final double? rescuerTemperatureEnd;
  final double? spO2UserEnd;

  const ParsedBLEData({
    this.isLiveStream        = false,
    this.isStartPing         = false,
    this.isEndPing           = false,
    this.isContinuousData    = false,
    this.isVentilationWindow = false,
    this.isPulseCheckStart   = false,
    this.isPulseCheckResult  = false,
    this.isTwoMinAlert       = false,
    this.isFatigueAlert      = false,
    this.isPendingLocalData  = false,
    this.depth               = 0,
    this.frequency           = 0,
    this.force               = 0,
    this.instantaneousRate   = 0,
    this.compressionCount    = 0,
    this.compressionInCycle  = 0,
    this.angle               = 0,
    this.wristAlignmentAngle = 0,
    this.wristFlexionAngle   = 0,
    this.compressionAxisDeviation = 0,
    this.effectiveDepth      = 0,
    this.recoilAchieved      = false,
    this.leaningDetected     = false,
    this.overForceFlag       = false,
    this.postureOk           = false,
    this.fatigueFlag         = false,
    this.ventilationCount    = 0,
    this.heartRatePatient    = 0,
    this.spO2Patient         = 0,
    this.ppgRaw              = 0,
    this.ppgSignalQuality    = 0,
    this.perfusionIndex      = 0,
    this.patientTemperature,
    this.heartRateUser       = 0,
    this.spO2User            = 0,
    this.rescuerSignalQuality = 0,
    this.rescuerTemperature  = 0,
    this.temperatureUser     = 0,
    this.temperaturePatient  = 0,
    this.sessionActive       = false,
    this.pulseCheckActive    = false,
    this.currentMode         = 0,
    this.feedbackEnabled     = true,
    this.batteryPercentage,
    this.isCharging,
    this.correctDepth        = 0,
    this.correctFrequency    = 0,
    this.correctRecoil       = 0,
    this.depthRateCombo      = 0,
    this.totalCompressions   = 0,
    this.correctPosture      = 0,
    this.leaningCount        = 0,
    this.overForceCount      = 0,
    this.tooDeepCount        = 0,
    this.totalVentilations   = 0,
    this.correctVentilations = 0,
    this.pulseChecksPrompted = 0,
    this.pulseChecksComplied = 0,
    this.pulseDetected,
    this.fatigueOnsetIndex   = 0,
    this.peakDepth           = 0,
    this.cycleNumber,
    this.intervalNumber,
    this.sessionElapsedMs,
    this.detectedBPM,
    this.confidencePct,
    this.pendingSessionCount,
    this.rescuerTemperatureEnd,
    this.spO2UserEnd,
  });

  /// Convenience constructor for EVENT_CHANNEL packets — all LIVE_STREAM
  /// fields default to zero/false so callers only specify what they need.
  const ParsedBLEData._event({
    bool isStartPing          = false,
    bool isEndPing            = false,
    bool isVentilationWindow  = false,
    bool isPulseCheckStart    = false,
    bool isPulseCheckResult   = false,
    bool isTwoMinAlert        = false,
    bool isFatigueAlert       = false,
    bool isPendingLocalData   = false,
    int  currentMode          = 0,
    int  totalCompressions    = 0,
    int  correctDepth         = 0,
    int  correctFrequency     = 0,
    int  correctRecoil        = 0,
    int  depthRateCombo       = 0,
    int  correctPosture       = 0,
    int  leaningCount         = 0,
    int  overForceCount       = 0,
    int  tooDeepCount         = 0,
    int  totalVentilations    = 0,
    int  correctVentilations  = 0,
    int  pulseChecksPrompted  = 0,
    int  pulseChecksComplied  = 0,
    int? pulseDetected,
    int  fatigueOnsetIndex    = 0,
    double peakDepth          = 0,
    double? patientTemperature,
    double rescuerTemperature = 0,
    double heartRateUser      = 0,
    double spO2User           = 0,
    int?   cycleNumber,
    int?   intervalNumber,
    int?   sessionElapsedMs,
    double? detectedBPM,
    int?    confidencePct,
    int?    pendingSessionCount,
  }) : this(
    isStartPing:          isStartPing,
    isEndPing:            isEndPing,
    isVentilationWindow:  isVentilationWindow,
    isPulseCheckStart:    isPulseCheckStart,
    isPulseCheckResult:   isPulseCheckResult,
    isTwoMinAlert:        isTwoMinAlert,
    isFatigueAlert:       isFatigueAlert,
    isPendingLocalData:   isPendingLocalData,
    currentMode:          currentMode,
    totalCompressions:    totalCompressions,
    correctDepth:         correctDepth,
    correctFrequency:     correctFrequency,
    correctRecoil:        correctRecoil,
    depthRateCombo:       depthRateCombo,
    correctPosture:       correctPosture,
    leaningCount:         leaningCount,
    overForceCount:       overForceCount,
    tooDeepCount:         tooDeepCount,
    totalVentilations:    totalVentilations,
    correctVentilations:  correctVentilations,
    pulseChecksPrompted:  pulseChecksPrompted,
    pulseChecksComplied:  pulseChecksComplied,
    pulseDetected:        pulseDetected,
    fatigueOnsetIndex:    fatigueOnsetIndex,
    peakDepth:            peakDepth,
    patientTemperature:   patientTemperature,
    rescuerTemperature:   rescuerTemperature,
    temperatureUser:      rescuerTemperature,
    heartRateUser:        heartRateUser,
    spO2User:             spO2User,
    cycleNumber:          cycleNumber,
    intervalNumber:       intervalNumber,
    sessionElapsedMs:     sessionElapsedMs,
    detectedBPM:          detectedBPM,
    confidencePct:        confidencePct,
    pendingSessionCount:  pendingSessionCount,
  );
}