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

  /// Minimum depth reached after this compression's peak before next downstroke.
  /// ~0–0.5 cm = full recoil. > 0.5 cm = incomplete recoil.
  /// 0.0 when not available (older firmware or history without valley data).
  final double valleyDepth;

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

  /// Peak force seen during this compression's downstroke (N).
  /// Tracked client-side from LIVE_STREAM `force` updates.
  final double peakForce;

  /// Session ms when peak depth was locked by the IMU (firmware peakTimestampMs).
  /// Absolute timestamp from session start. Use with valleyTimestampMs to
  /// compute exact compression phase durations.
  final int peakTimestampMs;

  /// Session ms when valley (full recoil point) was confirmed.
  /// Difference from next peakTimestampMs = relaxation phase duration.
  final int valleyTimestampMs;

  const CompressionEvent({
    required this.timestampMs,
    required this.depth,
    required this.instantaneousRate,
    this.frequency         = 0.0,
    this.force             = 0.0,
    this.valleyDepth       = 0.0,
    required this.recoilAchieved,
    this.overForce         = false,
    this.postureOk         = false,
    this.leaningDetected   = false,
    this.wristAlignmentAngle = 0.0,
    this.wristFlexionAngle   = 0.0,
    this.compressionAxisDev  = 0.0,
    this.effectiveDepth      = 0.0,
    this.downstrokeTimeMs    = 0,
    this.peakForce         = 0.0,
    this.peakTimestampMs   = 0,
    this.valleyTimestampMs = 0,
  });

  // ── Derived quality checks ────────────────────────────────────────────────

  bool isDepthInTargetFor({required double depthMin, required double depthMax}) =>
      depth >= depthMin && depth <= depthMax;

  bool isPerfectFor({required double depthMin, required double depthMax}) =>
      isDepthInTargetFor(depthMin: depthMin, depthMax: depthMax) &&
          isFrequencyInTarget &&
          recoilAchieved &&
          postureOk;

  /// Uses [instantaneousRate] for per-compression accuracy per spec v3.0.
  /// Falls back to [frequency] if instantaneousRate is 0 (warmup phase).
  bool get isFrequencyInTarget {
    final rate = instantaneousRate > 0 ? instantaneousRate : frequency;
    return rate >= CprTargets.rateMin && rate <= CprTargets.rateMax;
  }

  bool get isPostureOk =>
      wristAlignmentAngle <= CprTargets.alignmentMaxDeg &&
          wristFlexionAngle.abs() <= CprTargets.flexionMaxDeg;

  double get timestampSec => timestampMs / 1000.0;

  /// Duration from compression-start timestamp to peak timestamp.
  /// Returns 0 if timestampMs already represents the peak timestamp.
  int get downstrokePhaseDurationMs =>
      peakTimestampMs > timestampMs ? peakTimestampMs - timestampMs : 0;

  /// Duration of recoil phase: peak → valley (ms).
  int get recoilPhaseDurationMs =>
      valleyTimestampMs > peakTimestampMs ? valleyTimestampMs - peakTimestampMs : 0;

  // ── JSON factory — called when hydrating from backend ─────────────────────
  //
  // Key names match the aliases returned by GET /sessions/:id/detail.
  // Tolerant of missing fields for backward compatibility with older records.
  //
  factory CompressionEvent.fromJson(Map<String, dynamic> json) {
    final axisDevDeg = (json['axis_dev'] as num?)?.toDouble() ?? 0.0;
    final rawDepth = (json['depth'] as num?)?.toDouble() ?? 0.0;
    final storedEffectiveDepth =
        (json['effective_depth'] as num?)?.toDouble() ?? 0.0;
    final computedEffectiveDepth =
        rawDepth * cos(axisDevDeg * pi / 180.0);

    return CompressionEvent(
      timestampMs: (json['ts'] as num?)?.toInt() ?? 0,
      depth: rawDepth,
      instantaneousRate:
      (json['instantaneous_rate'] as num?)?.toDouble() ?? 0.0,
      frequency: (json['freq'] as num?)?.toDouble() ?? 0.0,
      force: (json['force'] as num?)?.toDouble() ?? 0.0,
      peakForce: (json['peak_force'] as num?)?.toDouble() ?? 0.0,
      valleyDepth: (json['valley_depth'] as num?)?.toDouble() ?? 0.0,
      recoilAchieved: json['recoil'] as bool? ?? false,
      overForce: json['over_force'] as bool? ?? false,
      postureOk: json['posture_ok'] as bool? ?? false,
      leaningDetected: json['leaning'] as bool? ?? false,
      wristAlignmentAngle:
      (json['wrist_angle'] as num?)?.toDouble() ?? 0.0,
      wristFlexionAngle:
      (json['wrist_flexion'] as num?)?.toDouble() ?? 0.0,
      compressionAxisDev: axisDevDeg,
      effectiveDepth: storedEffectiveDepth > 0
          ? storedEffectiveDepth
          : computedEffectiveDepth,
      downstrokeTimeMs:
      (json['downstroke_time_ms'] as num?)?.toInt() ?? 0,
      peakTimestampMs: (json['peak_ts'] as num?)?.toInt() ?? 0,
      valleyTimestampMs: (json['valley_ts'] as num?)?.toInt() ?? 0,
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
    'valley_depth':        valleyDepth,
    'recoil':              recoilAchieved,
    'over_force':          overForce,
    'posture_ok':          postureOk,
    'leaning':             leaningDetected,
    'wrist_angle':         wristAlignmentAngle,
    'wrist_flexion':       wristFlexionAngle,
    'axis_dev':            compressionAxisDev,
    'effective_depth':     effectiveDepth,
    'peak_force':          peakForce > 0 ? peakForce : force,
    'downstroke_time_ms':  downstrokeTimeMs,
    'peak_ts':   peakTimestampMs,
    'valley_ts': valleyTimestampMs,
  };
}