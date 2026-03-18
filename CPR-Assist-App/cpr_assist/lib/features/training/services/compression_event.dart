import 'dart:math' show cos, pi;

// ─────────────────────────────────────────────────────────────────────────────
// CprTargets — AHA 2020 / ERC 2021 quality thresholds
// Used by CompressionEvent getters and SessionService grade formula.
// Scenario-specific overrides are applied in SessionService — these are the
// standard adult defaults.
// ─────────────────────────────────────────────────────────────────────────────

class CprTargets {
  CprTargets._();

  // Standard adult defaults — overridden per scenario in SessionService
  static const double depthMin         = 5.0;   // cm
  static const double depthMax         = 6.0;   // cm
  static const double rateMin          = 100.0; // BPM
  static const double rateMax          = 120.0; // BPM
  static const double alignmentMaxDeg  = 15.0;  // degrees from vertical
  static const double flexionMaxDeg    = 10.0;  // degrees ±
  static const double overForceNewtons = 600.0; // N — rib fracture risk

  // Pediatric overrides — used by SessionService when scenario = 'pediatric'
  static const double depthMinPediatric = 4.0;
  static const double depthMaxPediatric = 5.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// CompressionEvent — one detected compression from the glove
//
// Sources:
//   BLE: created in BLEConnection._handleLiveStream() from ParsedBLEData
//   Backend: hydrated via fromJson() when fetching session detail
//
// JSON key naming matches session.js backend column aliases exactly.
// ─────────────────────────────────────────────────────────────────────────────

class CompressionEvent {
  // ── Timing ────────────────────────────────────────────────────────────────
  /// Milliseconds from session start. X-axis for all graphs.
  final int timestampMs;

  // ── Core depth & rate ─────────────────────────────────────────────────────
  /// Peak depth of this compression (cm).
  final double depth;

  /// Instantaneous rate from last two IBIs (BPM).
  /// Used for per-compression grading — more reactive than [frequency].
  final double instantaneousRate;

  /// 5-compression rolling average rate (BPM).
  /// Used for smooth display on the rate gauge.
  final double frequency;

  // ── Force ─────────────────────────────────────────────────────────────────
  /// Peak force of this compression (Newtons). Stored, not displayed raw.
  final double force;

  // ── Quality flags ─────────────────────────────────────────────────────────
  /// True if depth < 0.5 cm AND force < 5 N before next compression.
  final bool recoilAchieved;

  /// True if force exceeded 600 N (rib fracture risk threshold).
  final bool overForce;

  /// True if wristAlignmentAngle < 15° AND wristFlexionAngle within ±10°.
  final bool postureOk;

  /// True if inter-compression force stayed > 5 N for > 200 ms.
  final bool leaningDetected;

  // ── Posture ───────────────────────────────────────────────────────────────
  /// 3D compression vector deviation from vertical (degrees). Target: < 15°.
  final double wristAlignmentAngle;

  /// Wrist flexion/extension angle from ulnar IMU (degrees, ±45°).
  /// Negative = flexed forward, positive = extended back. Target: ±10°.
  /// Thesis-novel metric.
  final double wristFlexionAngle;

  /// Compression axis deviation angle. Used to compute [effectiveDepth].
  final double compressionAxisDev;

  /// depth × cos(compressionAxisDev) — sternum-corrected depth (cm).
  /// Thesis-novel metric.
  final double effectiveDepth;

  // ── Training-only metrics ─────────────────────────────────────────────────
  /// Time from compression start to peak depth (ms). Training mode only.
  /// 0 when not available (Emergency mode or older firmware).
  final int downstrokeTimeMs;

  const CompressionEvent({
    required this.timestampMs,
    required this.depth,
    required this.instantaneousRate,
    this.frequency         = 0.0,
    this.force             = 0.0,
    required this.recoilAchieved,
    this.overForce         = false,
    this.postureOk         = false,
    this.leaningDetected   = false,
    this.wristAlignmentAngle = 0.0,
    this.wristFlexionAngle   = 0.0,
    this.compressionAxisDev  = 0.0,
    this.effectiveDepth      = 0.0,
    this.downstrokeTimeMs    = 0,
  });

  // ── Derived quality checks ────────────────────────────────────────────────

  bool get isDepthInTarget =>
      depth >= CprTargets.depthMin && depth <= CprTargets.depthMax;

  /// Uses [instantaneousRate] for per-compression accuracy per spec v3.0.
  /// Falls back to [frequency] if instantaneousRate is 0 (warmup phase).
  bool get isFrequencyInTarget {
    final rate = instantaneousRate > 0 ? instantaneousRate : frequency;
    return rate >= CprTargets.rateMin && rate <= CprTargets.rateMax;
  }

  bool get isPostureOk =>
      wristAlignmentAngle <= CprTargets.alignmentMaxDeg &&
          wristFlexionAngle.abs() <= CprTargets.flexionMaxDeg;

  /// True if depth, rate, recoil, and posture are all within target.
  bool get isPerfect =>
      isDepthInTarget && isFrequencyInTarget && recoilAchieved && postureOk;

  double get timestampSec => timestampMs / 1000.0;

  // ── BLE factory — called in BLEConnection._handleLiveStream() ─────────────
  //
  // [packet] is the Map<String,dynamic> broadcast by BLEConnection.
  // [sessionStartMs] is the wall-clock ms when SESSION_START was received.
  //
  factory CompressionEvent.fromBlePacket(
      Map<String, dynamic> packet, {
        required int sessionStartMs,
      }) {
    final absoluteTs  = packet['timestamp']             as int?  ?? 0;
    final axisDevDeg  = (packet['compressionAxisDeviation'] as num?)?.toDouble() ?? 0.0;
    final rawDepth    = (packet['depth']                as num?)?.toDouble() ?? 0.0;
    final instRate    = (packet['instantaneousRate']    as num?)?.toDouble() ?? 0.0;

    return CompressionEvent(
      timestampMs:          absoluteTs - sessionStartMs,
      depth:                rawDepth,
      instantaneousRate:    instRate,
      frequency:            (packet['frequency']             as num?)?.toDouble() ?? 0.0,
      force:                (packet['force']                 as num?)?.toDouble() ?? 0.0,
      recoilAchieved:        packet['recoilAchieved']        as bool?             ?? false,
      overForce:             packet['overForceFlag']         as bool?             ?? false,
      postureOk:             packet['postureOk']             as bool?             ?? false,
      leaningDetected:       packet['leaningDetected']       as bool?             ?? false,
      wristAlignmentAngle:  (packet['wristAlignmentAngle']   as num?)?.toDouble() ?? 0.0,
      wristFlexionAngle:    (packet['wristFlexionAngle']     as num?)?.toDouble() ?? 0.0,
      compressionAxisDev:   axisDevDeg,
      effectiveDepth:       rawDepth * cos(axisDevDeg * pi / 180.0),
      downstrokeTimeMs:     (packet['downstrokeTimeMs']      as num?)?.toInt()    ?? 0,
    );
  }

  // ── JSON factory — called when hydrating from backend ─────────────────────
  //
  // Key names match the aliases returned by GET /sessions/:id/detail.
  // Tolerant of missing fields for backward compatibility with older records.
  //
  factory CompressionEvent.fromJson(Map<String, dynamic> json) {
    final axisDevDeg = (json['axis_dev']         as num?)?.toDouble() ?? 0.0;
    final rawDepth   = (json['depth']             as num?)?.toDouble() ?? 0.0;

    return CompressionEvent(
      timestampMs:         (json['ts']                   as num).toInt(),
      depth:               rawDepth,
      instantaneousRate:   (json['instantaneous_rate']   as num?)?.toDouble() ?? 0.0,
      frequency:           (json['freq']                 as num?)?.toDouble() ?? 0.0,
      force:               (json['force']                as num?)?.toDouble() ?? 0.0,
      recoilAchieved:       json['recoil']               as bool?             ?? false,
      overForce:            json['over_force']           as bool?             ?? false,
      postureOk:            json['posture_ok']           as bool?             ?? false,
      leaningDetected:      json['leaning']              as bool?             ?? false,
      wristAlignmentAngle: (json['wrist_angle']          as num?)?.toDouble() ?? 0.0,
      wristFlexionAngle:   (json['wrist_flexion']        as num?)?.toDouble() ?? 0.0,
      compressionAxisDev:  axisDevDeg,
      effectiveDepth:      (json['effective_depth']      as num?)?.toDouble()
          ?? rawDepth * cos(axisDevDeg * pi / 180.0),
      downstrokeTimeMs:    (json['downstroke_time_ms']   as num?)?.toInt()    ?? 0,
    );
  }

  // ── Serialisation — sent to backend via POST /sessions/detail ─────────────
  //
  // Keys must match the column aliases in session.js compressions INSERT.
  //
  Map<String, dynamic> toJson() => {
    'ts':                  timestampMs,
    'depth':               depth,
    'instantaneous_rate':  instantaneousRate,
    'freq':                frequency,
    'force':               force,
    'recoil':              recoilAchieved,
    'over_force':          overForce,
    'posture_ok':          postureOk,
    'leaning':             leaningDetected,
    'wrist_angle':         wristAlignmentAngle,
    'wrist_flexion':       wristFlexionAngle,
    'axis_dev':            compressionAxisDev,
    'effective_depth':     effectiveDepth,
    'peak_force':          force,        // reuse force as peak_force — glove sends peak
    'downstroke_time_ms':  downstrokeTimeMs,
  };
}