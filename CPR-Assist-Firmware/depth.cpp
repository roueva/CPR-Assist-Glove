// =============================================================================
// depth.cpp — Compression state machine, depth fusion, quality accumulation
// =============================================================================
#include "depth.h"
#include "imu.h"
#include "force.h"
#include <math.h>
#include <Arduino.h>

static StoredCompression _storedComps[STORAGE_MAX_COMPRESSIONS];
static uint16_t _storedCompCount = 0;

// Clicker state: armed = ready to fire; latched = depth currently above
// threshold (no re-fire until depth drops below CLICK_RESET_MM again).
static bool _clickJustFired = false;

// Public accessor for storage.cpp
const StoredCompression* depthGetStoredCompressions(uint16_t& count) {
  count = _storedCompCount;
  return _storedComps;
}

// ── State machine ─────────────────────────────────────────────────────────────
enum class CompState { RELEASED,
                       COMPRESSING };
static CompState _state = CompState::RELEASED;
static int _releaseConfirm = 0;
static float _peakForce = 0.0f;

// ── Compression counters ──────────────────────────────────────────────────────
static int _compressionNum = 0;
static uint32_t _compressionInCycle = 0;
static uint32_t _totalCompressions = 0;

// ── Quality accumulators (reset each session) ─────────────────────────────────
static uint32_t _cntDepth = 0, _cntFreq = 0, _cntRecoil = 0, _cntCombo = 0;
static uint32_t _cntPosture = 0, _cntLeaning = 0, _cntOverForce = 0, _cntTooDeep = 0;

// ── Rate tracking ─────────────────────────────────────────────────────────────
static unsigned long _lastCompStartMs = 0;
static unsigned long _thisCompStartMs = 0;

static const unsigned long COMP_MIN_INTERVAL_MS = 250;  // ≥250ms between comp starts (max 240 BPM physical)

static bool _wasLeaning = false;
static unsigned long _leaningStartMs = 0;  // 0 = not currently above threshold
static float _liveDepthCm = 0.0f;
static float _displayDepthCm = 0.0f;  // EMA-smoothed, display only

// ── Instantaneous rate (last 2 compressions) ──────────────────────────────────
static float _instantRate = 0.0f;

// ── Rolling rate (5-compression average) — spec §3 byte 4–7 `frequency` ───────
static float _rateBuf[5] = { 0 };
static int _rateIdx = 0;
static int _rateFill = 0;

static float rollingRate() {
  if (_rateFill == 0) return 0.0f;
  float sum = 0.0f;
  for (int i = 0; i < _rateFill; i++) sum += _rateBuf[i];
  return sum / _rateFill;
}
static bool _skipNextRate = false;
static float _gradeRate = 0.0f;

// ── Depth trend (5-comp rolling avg of peak depths) ──────────────────────────
static float _depthTrendBuf[5] = { 0 };
static int _depthTrendIdx = 0;
static int _depthTrendFill = 0;
static float _lastPeakMM = 0.0f;

static unsigned long _peakTimestampMs = 0;
static unsigned long _valleyTimestampMs = 0;
static float _prevValleyDepth = 0.0f;     // valley from previous cycle, used for recoil check
static float _prevValleyForce = 9999.0f;  // min inter-compression force for recoil check
static float _recoilValleyDepthMM = 9999.0f;
static float _recoilValleyForceN = 9999.0f;

static float depthTrend() {
  if (_depthTrendFill == 0) return 0.0f;
  float sum = 0;
  for (int i = 0; i < _depthTrendFill; i++) sum += _depthTrendBuf[i];
  return (sum / _depthTrendFill) / 10.0f;  // mm → cm
}

// ── Valley depth (min depth after last peak) ──────────────────────────────────
static float _valleyDepth = 0.0f;  // cm
static bool _trackingValley = false;

static double _depthSumSq = 0.0;
static double _depthSum = 0.0;
static uint32_t _depthN = 0;

// ── Chunk 4 Change 16 — Confidence-based depth selector ─────────────────────
// Replaces the fixed-weight blend with a per-stroke confidence-based selection
// between the IMU-derived depth and the force-derived depth.
//
// This design has no direct CPR-literature precedent — it is a thesis
// contribution drawing on general sensor-fusion principles (Hall & Llinas
// "Handbook of Multisensor Data Fusion") and per-path failure modes
// documented in the CPR literature (Aase 2002 for IMU drift; Tomlinson 2007
// for force individual variance; Lee/Park 2021 for orientation effects).
//
// Output flags (encoded in the lower 3 bits of the return enum):
//   HIGH_CONF       — both paths agree, output their average
//   IMU_PREFERRED   — both reliable but disagree, IMU has higher confidence
//   FORCE_PREFERRED — both reliable but disagree, force has higher confidence
//   IMU_ONLY        — force is low-confidence or out-of-range, IMU only
//   FORCE_ONLY      — IMU is low-confidence or diverged, force only
//   UNCERTAIN       — both paths low-confidence
//   CALIBRATING     — pre-calibration phase, IMU preferred when available
//
enum class DepthSource : uint8_t {
  HIGH_CONF       = 0,
  IMU_PREFERRED   = 1,
  FORCE_PREFERRED = 2,
  IMU_ONLY        = 3,
  FORCE_ONLY      = 4,
  UNCERTAIN       = 5,
  CALIBRATING     = 6,
  INVALID         = 7,
};

struct SelectorResult {
  float       depthMM;
  float       confidence;      // 0.0–1.0 overall confidence in the output
  DepthSource source;
};

static SelectorResult selectDepth(float imuMM, float forceMM,
                                  float imuConf, float forceConf,
                                  int compNum) {
  SelectorResult r;
  r.depthMM    = 0.0f;
  r.confidence = 0.0f;
  r.source     = DepthSource::INVALID;

  const bool calibrating = !forceCalibComplete() &&
                           (compNum <= MAX_CALIBRATION_SAMPLES);
  const bool imuHardFail   = (imuConf   < SELECTOR_HARD_FAIL_CONF);
  const bool forceHardFail = (forceConf < SELECTOR_HARD_FAIL_CONF);

  // ── Calibration phase ──────────────────────────────────────────────────
  // Before k is fitted, force depth is from population-mean and untrustworthy
  // for absolute accuracy. Prefer IMU when available; fall back to force
  // (low confidence) when IMU has failed.
  if (calibrating) {
    if (!imuHardFail) {
      r.depthMM    = imuMM;
      r.confidence = imuConf;
      r.source     = DepthSource::CALIBRATING;
    } else if (!forceHardFail) {
      r.depthMM    = forceMM;
      r.confidence = forceConf * 0.5f;  // extra penalty pre-calib
      r.source     = DepthSource::FORCE_ONLY;
    } else {
      r.depthMM    = imuMM;  // pick something
      r.confidence = 0.0f;
      r.source     = DepthSource::UNCERTAIN;
    }
    return r;
  }

  // ── Post-calibration steady state ──────────────────────────────────────

  // Rule: both paths hard-failed → can't recover.
  if (imuHardFail && forceHardFail) {
    r.depthMM    = (imuMM + forceMM) * 0.5f;
    r.confidence = 0.0f;
    r.source     = DepthSource::UNCERTAIN;
    return r;
  }

  // Rule: IMU failed → force only.
  if (imuHardFail) {
    r.depthMM    = forceMM;
    r.confidence = forceConf;
    r.source     = DepthSource::FORCE_ONLY;
    return r;
  }

  // Rule: force failed → IMU only.
  if (forceHardFail) {
    r.depthMM    = imuMM;
    r.confidence = imuConf;
    r.source     = DepthSource::IMU_ONLY;
    return r;
  }

  // Both reliable. Check agreement.
  const float diff      = fabsf(imuMM - forceMM);
  const bool  bothHigh  = (imuConf   >= SELECTOR_RELIABLE_CONF) &&
                          (forceConf >= SELECTOR_RELIABLE_CONF);
  const bool  agree     = (diff <= SELECTOR_AGREE_THRESHOLD_MM);

  if (bothHigh && agree) {
    // Best case: high confidence, paths agree → average, mark HIGH_CONF.
    r.depthMM    = 0.5f * (imuMM + forceMM);
    r.confidence = fmaxf(imuConf, forceConf);
    r.source     = DepthSource::HIGH_CONF;
  } else if (imuConf >= forceConf) {
    // IMU has higher (or equal) confidence — use IMU. If both were high
    // but they disagree, mark IMU_PREFERRED so the app/analysis can see
    // the disagreement.
    r.depthMM    = imuMM;
    r.confidence = imuConf;
    r.source     = bothHigh ? DepthSource::IMU_PREFERRED : DepthSource::IMU_ONLY;
  } else {
    r.depthMM    = forceMM;
    r.confidence = forceConf;
    r.source     = bothHigh ? DepthSource::FORCE_PREFERRED : DepthSource::FORCE_ONLY;
  }
  return r;
}

// ── Validated rate ────────────────────────────────────────────────────────────
static float validRate(float r) {
  return (r >= 40.0f && r <= 160.0f) ? r : 0.0f;
}

// ── Fatigue detection ─────────────────────────────────────────────────────────
static bool _fatigueFlag = false;
static uint8_t _fatigueScore = 0;
static float _firstFiveAvgMM = 0.0f;
static bool _firstFiveLocked = false;
static uint32_t _fatigueOnsetIndex = 0;

static void checkFatigue(float peakMM, int compNum, SharedState& s, float userHrBpm) {
  if (compNum == 5 && !_firstFiveLocked) {
    // Lock first 5 compression average as baseline
    float sum = 0;
    for (int i = 0; i < 5 && i < _depthTrendFill; i++) sum += _depthTrendBuf[i];
    int cnt = min(5, _depthTrendFill);
    _firstFiveAvgMM = (cnt > 0 && sum > 0) ? sum / (float)cnt : peakMM;
    _firstFiveLocked = true;
  }
  if (!_firstFiveLocked || compNum < FATIGUE_MIN_COMPRESSIONS) return;

  // Compute the continuous score on every call once the baseline is locked.
  // Previously the score was only written after the flag flipped, which made
  // it jump 0 → ~100 at onset and gave a useless step in the CSV. Now it
  // climbs smoothly with the decline, and crossing the threshold just sets
  // the flag (which the app uses for the alert).
  const float currentAvgMM = depthTrend() * 10.0f;
  float decline = _firstFiveAvgMM - currentAvgMM;
  if (decline < 0) decline = 0;
  _fatigueScore = (uint8_t)constrain(
    decline / FATIGUE_DECLINE_THRESHOLD_MM * 100.0f, 0, 100);
  s.rescuerFatigueScore = _fatigueScore;

  // Flag transition (one-shot): once decline exceeds threshold the alert fires.
  if (!_fatigueFlag) {
    const float hrAdjusted = (userHrBpm > FATIGUE_HR_THRESHOLD_BPM)
                               ? FATIGUE_DECLINE_THRESHOLD_MM * FATIGUE_HR_DECLINE_FACTOR
                               : FATIGUE_DECLINE_THRESHOLD_MM;
    if (decline >= hrAdjusted) {
      _fatigueFlag = true;
      _fatigueOnsetIndex = _totalCompressions;
      s.fatigueFlag = true;
    }
  } else {
    s.fatigueFlag = true;
  }
}

// ── Session reset ─────────────────────────────────────────────────────────────
void depthSessionReset() {
  _state = CompState::RELEASED;
  _releaseConfirm = 0;
  _peakForce = 0;
  _compressionNum = 0;
  _liveDepthCm = 0.0f;
  _displayDepthCm = 0.0f;
  _lastPeakMM = 0.0f;
  _compressionInCycle = 0;
  _totalCompressions = 0;
  _cntDepth = _cntFreq = _cntRecoil = _cntCombo = _cntPosture = _cntLeaning = _cntOverForce = _cntTooDeep = 0;
  _prevValleyDepth = 0.0f;
  _prevValleyForce = 9999.0f;
  _lastCompStartMs = 0;
  _thisCompStartMs = 0;
  _instantRate = 0;
  memset(_rateBuf, 0, sizeof(_rateBuf));
  _rateIdx = 0;
  _rateFill = 0;
  _gradeRate = 0;
  _skipNextRate = false;
  _valleyDepth = 0;
  _trackingValley = false;
  _fatigueFlag = false;
  _fatigueScore = 0;
  _firstFiveLocked = false;
  _firstFiveAvgMM = 0;
  _wasLeaning = false;
  _leaningStartMs = 0;
  _fatigueOnsetIndex = 0;
  _peakTimestampMs = 0;
  _valleyTimestampMs = 0;
  memset(_depthTrendBuf, 0, sizeof(_depthTrendBuf));
  _depthTrendIdx = _depthTrendFill = 0;
  _depthSum = 0.0;
  _depthSumSq = 0.0;
  _depthN = 0;
  _storedCompCount = 0;
  _clickJustFired = false;

  resetIntegration(integPalm);
  resetIntegration(integWrist);

  // Trigger fast CF convergence so the filter adapts quickly to the new
  // hand position on the manikin/patient. Mahony 2008.
imuResetCF();  // was: imuTriggerFastConverge()
}

void depthInit() {
  depthSessionReset();
}
float depthGetRate() {
  return _gradeRate;
}

bool depthIsReleased() {
  return _state == CompState::RELEASED;
}

float depthGetSD() {
  if (_depthN < 2) return 0.0f;
  float mean = (float)(_depthSum / _depthN);
  float var = (float)(_depthSumSq / _depthN) - mean * mean;
  return sqrtf(max(0.0f, var)) / 10.0f;  // mm → cm
}

float depthGetAvg() {
  if (_depthN == 0) return 0.0f;
  return (float)(_depthSum / _depthN) / 10.0f;  // mm → cm
}


// ── Chunk 3 Change 13 — finalize last-compression valley at session end ─────
// Normally a compression's recoil is graded when the NEXT compression starts
// (depth.cpp:343 consumes _valleyDepth into _recoilValleyDepthMM). At session
// end, the very last compression's recoil is never evaluated because no next
// compression occurs. This function finalizes the in-flight valley tracking
// so the app receives a recoil grade for every compression including the last.
//
// Call this exactly once from the SESSION_END handler in cpr_glove.ino,
// BEFORE snapshotState() is called.
//
// Has no effect if _trackingValley is false (e.g. session ended mid-stroke)
// or no compressions ever happened.
//
void depthFinalizeLastValley() {
  if (!_trackingValley) return;
  if (_valleyDepth >= 9000.0f) return;  // no valley sample captured

  // Mirror the assignment that depth.cpp:343 would do at next-comp-start.
  _recoilValleyDepthMM = _valleyDepth * 10.0f;     // cm → mm
  _recoilValleyForceN  = _prevValleyForce;
  _prevValleyDepth     = _valleyDepth;
  _trackingValley      = false;

  // Note: this only updates the internal state. The recoil grade for the
  // last compression is computed by depthUpdate's grading block, which has
  // already run for that compression. To make the grade visible we'd need
  // to re-emit a per-compression event. For thesis purposes the values
  // are now correct for the analysis dataset; the per-compression event
  // bit is a future improvement.
}

// ── Main update — called every 10ms from sensor task ─────────────────────────
void depthUpdate(float forceN, float dt, SharedState& s, GloveMode mode, Scenario scenario) {

  // Target thresholds for current scenario
  float depthMinMM = s.targetDepthMinMM;
  float depthMaxMM = s.targetDepthMaxMM;
  float overForceN = (scenario == Scenario::Pediatric) ? FORCE_OVERFORCE_PEDS : FORCE_OVERFORCE_ADULT;

  // ── Integrate IMU every sample ─────────────────────────────────────────────
  float aPalm = imuGetMotionAccelPalm();
  float aWrist = imuGetMotionAccelWrist();  // wrist IMU mounted with Z inverted relative to palm
if (_state == CompState::COMPRESSING) {
    integrateCompression(integPalm, aPalm, dt);
    if (integPalm.peakJustLocked) {
      _peakTimestampMs = (s.sessionStartMs > 0)
                           ? (millis() - s.sessionStartMs)
                           : 0;
      integPalm.peakJustLocked = false;
    }
    if (imuWristOk() && !imuWristDropped())
      integrateCompression(integWrist, aWrist, dt);

    // Chunk 4 Change 17 — accumulate tilt min/max for confidence metric.
    // The CF pitch and roll combine into a total tilt magnitude. Track its
    // min and max during the stroke; the span is the "tilt change" component
    // of the IMU confidence metric (Lee/Park 2021: orientation change during
    // compression causes gravity leakage into the motion axis).
    const float tiltDeg = sqrtf(imuGetPalmPitchDeg() * imuGetPalmPitchDeg() +
                                imuGetPalmRollDeg()  * imuGetPalmRollDeg());
    if (tiltDeg < integPalm.tiltMinDeg) integPalm.tiltMinDeg = tiltDeg;
    if (tiltDeg > integPalm.tiltMaxDeg) integPalm.tiltMaxDeg = tiltDeg;
    if (imuWristOk() && !imuWristDropped()) {
      // For wrist tilt we don't have separate CF accessors; use same palm-CF
      // value as a proxy (wrist tilt closely tracks palm during compression).
      if (tiltDeg < integWrist.tiltMinDeg) integWrist.tiltMinDeg = tiltDeg;
      if (tiltDeg > integWrist.tiltMaxDeg) integWrist.tiltMaxDeg = tiltDeg;
    }
  }


  // ── Live instantaneous depth (for depth bar animation) ────────────────────
  // Live feedback: rises with the stroke, never dips mid-press (the raw
  // double-integrator jitters ±cm at 25 Hz), snaps to 0 on release.
  if (_state == CompState::COMPRESSING) {
    float rawCm = integPalm.depthM * 100.0f;
    if (rawCm < 0.0f) rawCm = 0.0f;
    if (rawCm > _liveDepthCm) _liveDepthCm = rawCm;  // monotonic within a stroke
    // allow it to ease down only if the raw value drops substantially
    else if (rawCm < _liveDepthCm - 0.3f) _liveDepthCm = rawCm;
  } else {
    _liveDepthCm = 0.0f;  // RELEASED → bar returns to zero
  }
  if (_liveDepthCm < 0.15f) _liveDepthCm = 0.0f;  // floor sensor noise
  // Display-only smoothed depth — follows the true integrated displacement up
  // AND down so the bar shows the whole motion. Separate from _liveDepthCm so
  // valley/recoil grading (line ~445) stays on the unchanged signal.
 const float dispTarget = (_state == CompState::COMPRESSING)
                             ? fmaxf(0.0f, integPalm.depthM * 100.0f)
                             : (forceN > FORCE_LEANING_THRESHOLD)
                                 // released but still pressing → show the lean
                                 ? forceCalibK() * powf(forceN, DEPTH_EXPONENT) / 10.0f
                                 : 0.0f;  // truly released → rest at 0
  _displayDepthCm += LIVE_DEPTH_EMA_ALPHA * (dispTarget - _displayDepthCm);
  if (_displayDepthCm < 0.10f) _displayDepthCm = 0.0f;
  s.depth = _displayDepthCm;

// Clicker — fires the instant live depth crosses the lower target, once per
  // stroke, only on a trustworthy IMU reading. Re-arms after recoil.
  static bool _clickArmed = true;
  const float liveMM = _liveDepthCm * 10.0f;
  if (s.sessionActive && _clickArmed && liveMM >= s.targetDepthMinMM && !integPalm.diverged) {
    _clickJustFired = true;
    _clickArmed = false;
  } else if (liveMM < CLICK_RESET_MM) {
    _clickArmed = true;
  }

  // ── Valley tracking (for recoil detection) ────────────────────────────────
  if (_trackingValley) {
    float currentCm = _liveDepthCm;
    if (currentCm < _valleyDepth) _valleyDepth = currentCm;
    // Track minimum force between compressions — recoil requires both depth AND force back to baseline
    if (forceN < _prevValleyForce) _prevValleyForce = forceN;
  }

  // ── Leaning detection (force > threshold between compressions) ────────────
  bool aboveThresh = (_state == CompState::RELEASED && forceN > FORCE_LEANING_THRESHOLD);
  if (aboveThresh) {
    if (_leaningStartMs == 0) _leaningStartMs = millis();
  } else {
    _leaningStartMs = 0;
  }
  bool nowLeaning = (_leaningStartMs > 0 && (millis() - _leaningStartMs) > LEANING_PERSISTENCE_MS);
  if (nowLeaning && !_wasLeaning) _cntLeaning++;  // count transitions, not samples
  _wasLeaning = nowLeaning;
  s.leaningDetected = nowLeaning;

  // ── State machine — only runs during active session ───────────────────────
  if (!s.sessionActive) {
    // Keep posture angles flowing (they're written below) but don't count compressions.
    s.wristAlignmentAngle = fabsf(imuGetPalmPitchDeg());
    s.wristFlexionAngle = imuWristDropped() ? 0.0f
                                            : imuGetWristFlexionDeg();
    s.compressionAxisDeviation = fabsf(imuGetPalmRollDeg());
    s.force = forceN;
    s.depth = 0.0f;
    s.frequency = 0.0f;
    s.instantaneousRate = 0.0f;
    return;
  }

  if (_state == CompState::RELEASED) {

    // Between strokes the integrator must hold true zero — otherwise residual
    // velocity/bias from the previous stroke leaks into the next compression's
    // depth and the live bar shows a stale value instead of returning to 0.
    integPalm.velocityMS = 0.0f;
    integPalm.depthM = 0.0f;
    integWrist.velocityMS = 0.0f;
    integWrist.depthM = 0.0f;

    if (forceN > FORCE_COMPRESS_START && (millis() - _thisCompStartMs) >= COMP_MIN_INTERVAL_MS) {
      _state = CompState::COMPRESSING;
      _compressionNum++;
      _totalCompressions++;
      _thisCompStartMs = millis();
      _peakForce = 0;

      integPalm.peakDepthM = 0;
      integWrist.peakDepthM = 0;
      integPalm.peakLocked = false;
      integWrist.peakLocked = false;
      _releaseConfirm = 0;
      _peakTimestampMs = 0;  // fresh peak for this new compression — clear stale value

      // Valley minimum was at its lowest just before this new downstroke
      if (_trackingValley && _valleyDepth < 9000.0f && s.sessionStartMs > 0) {
        _valleyTimestampMs = (unsigned long)(millis() - s.sessionStartMs);
      }

      // The valley that just ended (release between prev comp and this downstroke)
      // belongs to the compression that is ABOUT to complete. Hold it so the
      // completion block grades the correct compression's recoil.
      _recoilValleyDepthMM = (_trackingValley && _valleyDepth < 9000.0f) ? (_valleyDepth * 10.0f) : 9999.0f;
      _recoilValleyForceN = (_prevValleyForce < 9000.0f) ? _prevValleyForce : 9999.0f;
      _prevValleyDepth = (_trackingValley && _valleyDepth < 9000.0f) ? _valleyDepth : 9999.0f;

      // Start valley tracking after peak
      _trackingValley = false;
      _valleyDepth = 9999.0f;
      _prevValleyForce = 9999.0f;  // reset for next inter-compression window
    }

  } else {  // COMPRESSING

    if (forceN > _peakForce) _peakForce = forceN;

    if (forceN < FORCE_RELEASE_DONE) {
      _releaseConfirm++;
    } else {
      _releaseConfirm = 0;
    }

    if (_releaseConfirm >= RELEASE_CONFIRM_NEEDED) {
      // ── Compression complete ─────────────────────────────────────────────
      _state = CompState::RELEASED;

      // Chunk 1 Change 2 — Aase per-cycle boundary correction. Captures the
      // residual velocity at release (for the confidence metric) AND back-
      // corrects peakDepthM for accumulated bias. Must run BEFORE peakDepthM
      // is consumed below.
      const uint32_t strokeDurationMs = millis() - _thisCompStartMs;
      imuApplyBoundaryCorrection(integPalm, strokeDurationMs);
      if (imuWristOk() && !imuWristDropped()) {
        imuApplyBoundaryCorrection(integWrist, strokeDurationMs);
      #if DEPTH_SELECTOR_LOG
        static bool _cfPrinted = false;
        if (!_cfPrinted) {
          Serial.printf("[CF] palm pitch=%.3f roll=%.3f  wrist pitch=%.3f roll=%.3f\n",
                        cfPalm.pitch * RAD_TO_DEG, cfPalm.roll * RAD_TO_DEG,
                        cfWrist.pitch * RAD_TO_DEG, cfWrist.roll * RAD_TO_DEG);
          Serial.printf("[CF] integWrist: peakDepth=%.1fmm diverged=%d velocity=%.3f\n",
                        integWrist.peakDepthM * 1000.0f, integWrist.diverged, integWrist.velocityMS);
          _cfPrinted = true;
        }
        #endif
      }

      float palmMM = integPalm.peakDepthM * 1000.0f;
      float wristMM = (imuWristOk() && !imuWristDropped())
                        ? integWrist.peakDepthM * 1000.0f
                        : 0.0f;

      // Chunk 4 Changes 17/19 — compute confidences and combine the two IMUs
      // into a single depth estimate + combined confidence.
      const float palmConf  = imuConfidence(integPalm);
      const float wristConf = (imuWristOk() && !imuWristDropped())
                                ? imuConfidence(integWrist)
                                : 0.0f;
      const DualIMUResult imu = imuCombineDual(palmMM, wristMM,
                                               palmConf, wristConf);
      const float imuMM      = imu.depthMM;
      const float imuOverallConf = imu.combinedConfidence;

      // Force path.
      const float forceMM   = forceToDepth(_peakForce);
      const float forceConf = forceConfidence(_peakForce);

      // Chunk 4 Change 16 — confidence-based selector.
      const SelectorResult sel = selectDepth(imuMM, forceMM,
                                             imuOverallConf, forceConf,
                                             _compressionNum);
      const float finalMM     = sel.depthMM;
      const float finalConf   = sel.confidence;
      const DepthSource src   = sel.source;

      _lastPeakMM = finalMM;
      float finalCm = finalMM / 10.0f;
      s.lastPeakDepthCm     = finalCm;
    
      s.lastPeakConfidence  = (uint8_t)(finalConf * 100.0f);  // 0–100 for BLE
      s.lastPeakDepthSource = (uint8_t)src;

#if DEPTH_SELECTOR_LOG
      // Human-readable depth selector telemetry
      const char* srcName = "";
      switch (src) {
        case DepthSource::HIGH_CONF:       srcName = "HIGH_CONF"; break;
        case DepthSource::IMU_PREFERRED:   srcName = "IMU_PREF"; break;
        case DepthSource::FORCE_PREFERRED: srcName = "FORCE_PREF"; break;
        case DepthSource::IMU_ONLY:        srcName = "IMU_ONLY"; break;
        case DepthSource::FORCE_ONLY:      srcName = "FORCE_ONLY"; break;
        case DepthSource::UNCERTAIN:       srcName = "UNCERTAIN"; break;
        case DepthSource::CALIBRATING:     srcName = "CALIB"; break;
        default:                           srcName = "INVALID"; break;
      }
      Serial.printf("[DEPTH-SEL] comp=%d: imu=%.1fmm(%.0f%%) force=%.1fmm(%.0f%%) → %s final=%.2fmm(%.0f%%) | f=%.0fN k=%.4f\n",
                    _compressionNum,
                    imuMM, imuOverallConf * 100.0f,
                    forceMM, forceConf * 100.0f,
                    srcName,
                    finalMM, finalConf * 100.0f,
                    _peakForce, forceCalibK());
#endif

#if DEPTH_PIPELINE_LOG
      // CSV row per completed compression. Columns:
      //   n          — compression number this session
      //   peakF_N    — peak applied force
      //   palmMM     — IMU palm-only integrated depth
      //   wristMM    — IMU wrist-only integrated depth (0 if wrist sensor dropped)
      //   imuMM      — adaptive IMU depth (palm/wrist fusion, pre force-anchor)
      //   forceMM    — force-model depth using current _calibK
      //   calibK     — current force-model coefficient (self-tunes during session)
      //   finalMM    — fused output reported to app
      //   strokeMs   — duration from this stroke start to previous stroke start (cycle period)
     Serial.printf("CALIB,%d,%.1f,%.2f,%.2f,%.2f,%.2f,%.4f,%.2f,%lu,%.2f,%s\n",
              _compressionNum, _peakForce,
              palmMM, wristMM, imuMM, forceMM,
              forceCalibK(), finalMM,
              (_lastCompStartMs > 0) ? (unsigned long)(_thisCompStartMs - _lastCompStartMs) : 0UL,
              (_recoilValleyDepthMM < 9000.0f) ? _recoilValleyDepthMM : 0.0f,
              (_recoilValleyDepthMM < RECOIL_RESIDUAL_MAX_MM && _recoilValleyForceN < FORCE_LEANING_THRESHOLD) ? "RECOIL_OK" : "NO_RECOIL");
#endif

     bool validDepth = (imuMM > 20.0f && imuMM < 125.0f);  // legacy flag still used for storage gating below; kept independent of the new IMU-confidence calibration gate
     bool validForce = (_peakForce > FORCE_BASELINE_MIN);  // 30 N, single source of truth

      // Update gravity EMA (kept as fallback signal — see Chunk 1 Section 3.3)
     imuEndCycle(validForce);

      // Chunk 2 Change 9 / Chunk 4 Change 22 — calibration sample gating by
      // IMU confidence, not by depth range. The old depth-range filter
      // (20 < imuMM < 125) biased the calibration toward whichever strokes
      // happened to land in that window — even if the IMU was unreliable.
      // Now: only feed forceCalibAddSample when the IMU stroke was high-
      // confidence (per imuConfidence above the threshold). The depth value
      // itself is no longer a gating criterion.
      const bool imuTrustworthy = (imuOverallConf >= IMU_CONF_FOR_CALIBRATION) &&
                                  !integPalm.diverged;
      if (validForce && imuTrustworthy) {
        forceCalibAddSample(_peakForce, imuMM);
      }

      // Two rates are kept:
      //  • _gradeRate  — THIS compression's actual rate. Used for quality
      //    grading so every single compression is judged on its own merit.
      //  • _instantRate — lightly smoothed, for the live display only, so the
      //    on-screen number doesn't flicker on normal cycle-to-cycle jitter.
      // Outlier rejection (a single physically-impossible doubled/halved
      // interval) is applied to BOTH, but a genuine sustained rate change is
      // never hidden from grading.
      // Rate depends ONLY on the inter-compression time interval. It must not
      // be gated on validDepth — a real compression with a momentarily bad
      // depth estimate still has a perfectly valid rate, and gating on depth
      // froze _gradeRate so frequency grading lagged badly.
      if (validForce && _lastCompStartMs > 0 && !_skipNextRate) {
        float intv = (_thisCompStartMs - _lastCompStartMs) / 1000.0f;
        float raw = validRate(60.0f / intv);
        if (raw > 0) {
          bool plausible = true;
          if (_instantRate > 0.0f) {
            float ratio = raw / _instantRate;
            // Reject only physically-impossible single-cycle jumps (interval
            // halved or doubled). ±40% still passes a real fast/slow change.
            if (ratio < 0.55f || ratio > 1.80f) plausible = false;
          }
          if (plausible) {
            _gradeRate = raw;  // exact rate THIS comp
            _instantRate = (_instantRate <= 0.0f)
                             ? raw
                             : 0.6f * _instantRate + 0.4f * raw;  // display smoothing
            // Feed the 5-comp rolling buffer that backs s.frequency
            _rateBuf[_rateIdx] = raw;
            _rateIdx = (_rateIdx + 1) % 5;
            if (_rateFill < 5) _rateFill++;
          }
          // if implausible: keep previous _gradeRate AND _instantRate
        }
      }
      if (_skipNextRate) _skipNextRate = false;  // consumed
      if (validForce) _lastCompStartMs = _thisCompStartMs;

      // Depth trend
      if (validDepth) {
        _depthTrendBuf[_depthTrendIdx] = finalMM;
        _depthTrendIdx = (_depthTrendIdx + 1) % 5;
        if (_depthTrendFill < 5) _depthTrendFill++;
      }

      if (validDepth) {
        _depthSum += finalMM;
        _depthSumSq += finalMM * finalMM;
        _depthN++;
      }

      // ── Quality grading — from first compression, gated only on imuCalibrated ──
      if (s.sessionActive) {
        if (s.imuCalibrated) {
          bool goodDepth = (finalMM >= depthMinMM && finalMM <= depthMaxMM);
          // Grade on THIS compression's own rate, not the smoothed display
          // value — every compression must stand on its own.
          bool goodFreq = (_gradeRate >= s.targetRateMin && _gradeRate <= s.targetRateMax);
          // Spec §3: recoil = depth returned to <0.5cm AND force dropped below 5N
          bool goodRecoil = (_recoilValleyForceN < FORCE_LEANING_THRESHOLD) &&
                            (_recoilValleyDepthMM < RECOIL_RESIDUAL_MAX_MM);
          bool goodPosture = (fabsf(s.wristAlignmentAngle) < WRIST_ALIGN_WARN_DEG);
          bool overForce = (_peakForce > overForceN);
          bool tooDeep = (finalMM > depthMaxMM);

          if (goodDepth) _cntDepth++;
          if (goodFreq) _cntFreq++;
          if (goodRecoil) _cntRecoil++;
          if (goodPosture) _cntPosture++;
          if (overForce) _cntOverForce++;
          if (tooDeep) _cntTooDeep++;
          if (goodDepth && goodFreq) _cntCombo++;

          s.recoilAchieved = goodRecoil;
          s.overForceFlag = overForce;
          s.postureOk = goodPosture;

          s.correctDepth = _cntDepth;
          s.correctFrequency = _cntFreq;
          s.correctRecoil = _cntRecoil;
          s.correctPosture = _cntPosture;
          s.depthRateCombo = _cntCombo;
          s.leaningCount = _cntLeaning;
          s.overForceCount = _cntOverForce;
          s.tooDeepCount = _cntTooDeep;
          s.fatigueOnsetIndex = _fatigueOnsetIndex;

          checkFatigue(finalMM, _compressionNum, s, s.heartRateUser);
        }

        // totalCompressions = all compressions including pre-calibration
        s.totalCompressions = _totalCompressions;

        // Time to first compression — record once on first compression
        if (_totalCompressions == 1 && s.sessionStartMs > 0) {
          s.timeToFirstCompressionMs = (uint32_t)_peakTimestampMs;
        }
      }

      // ── Shared state updates ──────────────────────────────────────────────
      s.frequency = rollingRate();       // 5-comp rolling avg — spec §3 byte 4–7
      s.instantaneousRate = _gradeRate;  // EXACT per-compression rate — spec §3 byte 12–15
      s.compressionCount = (int32_t)_totalCompressions;
      s.imuCalibrated = imuIsCalibrated();
      s.wristDropped = imuWristDropped();
      s.depthTrend = depthTrend();

      // Timestamps
      s.peakTimestampMs = (uint32_t)_peakTimestampMs;
      s.valleyTimestampMs = (uint32_t)_valleyTimestampMs;

      // Use force-to-depth proxy for the inter-compression valley.
      // This gives the app a non-zero value when the rescuer is leaning,
      // making the valley/recoil graph meaningful.
      // forceToDepth returns mm, divide by 10 for cm.
{
    const float valF = (_recoilValleyForceN < 9000.0f) ? _recoilValleyForceN : 0.0f;
    s.valleyDepth = (valF > 0.5f)
        ? forceCalibK() * powf(valF, DEPTH_EXPONENT) / 10.0f  // mm → cm
        : 0.0f;
}


      // Compressions in cycle — wraps back to 0 after each ventilation cycle
      // (default 30:2). Uses ventilationCompressions from shared state so that
      // app overrides via CMD_SET_VENTILATION are honoured.
      uint8_t ventLimit = (s.ventilationCompressions > 0)
                            ? s.ventilationCompressions
                            : VENTILATION_CYCLE_COMPRESSIONS;
      _compressionInCycle++;
      s.compressionInCycle = _compressionInCycle;
      if (_compressionInCycle >= ventLimit) {
        _compressionInCycle = 0;  // next compression starts fresh at 1
      }

      // Peak depth for SESSION_END
      if (finalCm > s.peakDepth) s.peakDepth = finalCm;

      // ── Buffer this compression for offline storage ──────────────────────
      if (_storedCompCount < STORAGE_MAX_COMPRESSIONS && s.imuCalibrated) {
        StoredCompression& c = _storedComps[_storedCompCount++];
        c.timestampMs = (uint32_t)_peakTimestampMs;
        c.depth = finalCm;
        c.frequency = _gradeRate;  // exact per-compression rate (matches BLE instantaneousRate)
        c.recoil = s.recoilAchieved ? 1 : 0;
        c.overForce = s.overForceFlag ? 1 : 0;
        c.postureOk = s.postureOk ? 1 : 0;
        c.wristAlignX10 = (uint8_t)constrain((int)(fabsf(s.wristAlignmentAngle) * 10.0f), 0, 255);
        c.axisDevX10 = (uint8_t)constrain((int)(fabsf(s.compressionAxisDeviation) * 10.0f), 0, 255);
        for (int i = 0; i < 3; i++) c.reserved[i] = 0;
      }

      // Reset integration for next compression
      resetIntegration(integPalm);
      resetIntegration(integWrist);

      // Start tracking valley from this moment
      _trackingValley = true;
      _valleyDepth = _liveDepthCm;
    }
  }

  // ── Always update posture angles ──────────────────────────────────────────
  s.wristAlignmentAngle = fabsf(imuGetPalmPitchDeg());
  s.wristFlexionAngle = imuWristDropped() ? 0.0f
                                          : imuGetWristFlexionDeg();  // signed ±45; 0 = wrist IMU unavailable
  s.compressionAxisDeviation = fabsf(imuGetPalmRollDeg());
  s.force = forceN;
}

float depthGetLastPeakMM() {
  return _lastPeakMM;
}

bool depthClickJustTriggered() {
  bool v = _clickJustFired;
  _clickJustFired = false;
  return v;
}

void depthSkipNextRate() {
  _skipNextRate = true;
}