// =============================================================================
// force.cpp — FlexiForce A401 + MCP6002 op-amp
// Algorithm from Anti's snippet — unchanged except modularised.
// =============================================================================
#include "force.h"
#include <Arduino.h>
#include <math.h>

static float _baseline = 0.0f;
static bool _baselineReady = false;
static float _calibK = K_POPULATION_DEFAULT;  // population-mean k (Tomlinson 2007), refined per-session by forceCalibCompute()
#if FORCE_CALIB_LOCK
static bool _calibComplete = true;   // k pre-locked at K_POPULATION_DEFAULT, never refit
#else
static bool _calibComplete = false;
#endif

static int _baselineCnt = 0;
static float _baselineSum = 0.0f;

static float _bootBaseline = 0.0f;  // captured at boot — never exceeded
static bool _sessionActive = false;

static float _calibForces[MAX_CALIBRATION_SAMPLES];
static float _calibDepths[MAX_CALIBRATION_SAMPLES];
static int _calibCount = 0;

static bool _calibLocked = false;


// Median filter (3-sample)
static float _medBuf[3] = { 0, 0, 0 };
static int _medIdx = 0;

// Chunk 2 Change 11 (optional) — IIR low-pass after median filter.
// 1-pole IIR at ~10 Hz cutoff (at 100 Hz sample rate, alpha=0.5).
// Approximates the Zhang 2024 Butterworth-LPF approach with minimal compute.
// Removes broadband noise that the median filter can't catch.
static float _lpfState = 0.0f;

static float median3(float a, float b, float c) {
  if (a > b) {
    float t = a;
    a = b;
    b = t;
  }
  if (b > c) {
    float t = b;
    b = c;
    c = t;
  }
  if (a > b) {
    float t = a;
    a = b;
    b = t;
  }
  return b;
}

// ── Baseline calibration — call repeatedly until forceBaselineReady() ─────────
bool forceInit() {
  if (_baselineReady) return true;

  int raw = analogRead(PIN_FSR_ADC);
  float v = (raw / 4095.0f) * 3.3f;

  // float f = FORCE_C0 + FORCE_C1 * v + FORCE_C2 * v * v;
// // If exponential instead of float f:
float v_rel = v - FORCE_BASELINE_V;
  float f = FORCE_EXP_A * (expf(FORCE_EXP_B * v_rel) - 1.0f) + FORCE_EXP_C;

  if (f < 0) f = 0;

  _baselineSum += f;
  _baselineCnt++;
  if (_baselineCnt >= FORCE_BASELINE_SAMPLES) {
    float candidate = _baselineSum / FORCE_BASELINE_SAMPLES;
    // If baseline is unrealistically high, the sensor was under load at boot.
    // Reset and try again — this loop will re-run on next call.
    if (candidate > 50.0f) {
      _baselineSum = 0;
      _baselineCnt = 0;
      return false;
    }
    _baseline = candidate;
    _bootBaseline = candidate;
    _baselineReady = true;
  }
  return _baselineReady;
}

bool forceBaselineReady() {
  return _baselineReady;
}

// ── Read (call at 100Hz) ──────────────────────────────────────────────────────
float forceRead() {
  if (!_baselineReady) return 0.0f;

  int raw = analogRead(PIN_FSR_ADC);
  float v = (raw / 4095.0f) * 3.3f;
  // float f = FORCE_C0 + FORCE_C1 * v + FORCE_C2 * v * v;
//   // If exponential instead of float f
float v_rel = v - FORCE_BASELINE_V;
  float f = FORCE_EXP_A * (expf(FORCE_EXP_B * v_rel) - 1.0f) + FORCE_EXP_C;

  if (f > 700.0f) f = 0.0f;  // ADC glitch rejection

  // Adaptive baseline update.
  //  - Out of session: track resting force whenever below current baseline.
  //  - In session: also track, but ONLY when raw force is clearly a full
  //    release (well under the leaning threshold relative to baseline). This
  //    lets FSR creep over a long session decay out so the recoil/leaning
  //    threshold stays reachable, while a real lean (force above
  //    FORCE_LEANING_THRESHOLD) never feeds the baseline. ADAPT_ALPHA is
  //    already slow (~5 min time constant) so per-compression releases cannot
  //    drag the baseline meaningfully within one cycle.
  if (f < _baseline) {
    if (!_sessionActive) {
      forceUpdateBaseline(f);
    } else if ((f - _baseline) < (FORCE_LEANING_THRESHOLD * 0.5f)) {
      forceUpdateBaseline(f);
    }
  }

  f = max(0.0f, f - _baseline);

  _medBuf[_medIdx] = f;
  _medIdx = (_medIdx + 1) % 3;
  const float med = median3(_medBuf[0], _medBuf[1], _medBuf[2]);

  // Chunk 2 Change 11 — IIR LPF (1-pole, ~10 Hz cutoff at 100 Hz)
  _lpfState = 0.5f * _lpfState + 0.5f * med;
  return _lpfState;
}

// ── Force → depth power law ───────────────────────────────────────────────────
float forceToDepth(float forceN) {
  if (forceN < FORCE_BASELINE_MIN) return 0.0f;
  return _calibK * powf(forceN, DEPTH_EXPONENT);
}

// ── In-session calibration ────────────────────────────────────────────────────
void forceCalibAddSample(float forceN, float imuDepthMM) {
#if FORCE_CALIB_LOCK
  if (_calibLocked) return;  // Stop accepting samples if locked
#endif
  if (_calibComplete || _calibCount >= MAX_CALIBRATION_SAMPLES) return;

#if LOW_FORCE_MODE
  const float forceMin = 30.0f, forceMax = 600.0f;
  const float depthMin = 20.0f, depthMax = 100.0f;
#else
  const float forceMin = 100.0f, forceMax = 600.0f;
const float depthMin = 40.0f, depthMax = 80.0f;
#endif

  if (forceN < forceMin || forceN > forceMax) return;
  if (imuDepthMM < depthMin || imuDepthMM > depthMax) return;

  _calibForces[_calibCount] = forceN;
  _calibDepths[_calibCount] = imuDepthMM;
  _calibCount++;

  if (_calibCount >= MAX_CALIBRATION_SAMPLES) forceCalibCompute();
}

bool forceCalibComplete() {
  return _calibComplete;
}

// Chunk X Change Y — K-locking for controlled studies
// When FORCE_CALIB_LOCK = 1, k is fitted once and never refitted.
// Useful for validating on a single surface with all subjects using identical k.

bool forceCalibLocked() {
  return _calibLocked;
}

void forceCalibLock() {
  _calibLocked = true;
}

float forceCalibK() {
  return _calibK;
}

void forceCalibCompute() {
  if (_calibCount < 5) return;

  // Fit k: minimise sum of (depth - k*force^exp)^2
  auto computeK = [&](bool* mask) -> float {
    float num = 0, den = 0;
    for (int i = 0; i < _calibCount; i++) {
      if (mask && !mask[i]) continue;
      float fp = powf(_calibForces[i], DEPTH_EXPONENT);
      num += _calibDepths[i] * fp;
      den += fp * fp;
    }
    return (den > 0) ? num / den : 0.15f;
  };

  float k = computeK(nullptr);

  // Outlier rejection: discard samples with residual > 2× mean
  float residuals[MAX_CALIBRATION_SAMPLES], meanRes = 0;
  for (int i = 0; i < _calibCount; i++) {
    residuals[i] = fabsf(_calibDepths[i] - k * powf(_calibForces[i], DEPTH_EXPONENT));
    meanRes += residuals[i];
  }
  meanRes /= _calibCount;

  bool inlier[MAX_CALIBRATION_SAMPLES];
  int nIn = 0;
  for (int i = 0; i < _calibCount; i++) {
    inlier[i] = (residuals[i] <= 2.0f * meanRes);
    if (inlier[i]) nIn++;
  }
  if (nIn >= 5) k = computeK(inlier);

// Physiological k range per Tomlinson 2007 — individual k varies roughly
  // 0.7–2.0 across the human chest-stiffness spread (derived from F25
  // std dev ±6.6 kg). If the fit lands outside this range, the calibration
  // data is suspect — revert to the population mean and let the next
  // session's calibration try again.
 if (k < 0.70f || k > 3.50f) k = K_POPULATION_DEFAULT;
  _calibK = k;
  Serial.printf("[FORCE-CALIB] k fitted = %.4f from %d samples\n", _calibK, _calibCount);
  _calibComplete = true;
#if FORCE_CALIB_LOCK
  _calibLocked = true;  // Lock k after first fit
  Serial.printf("[FORCE-CALIB] K-LOCKED at %.4f after %d samples\n", k, _calibCount);
#endif
}

void forceSetSessionActive(bool active) {
  _sessionActive = active;
}

// ── Adaptive baseline — call at 100Hz when no session is running ──────────────
void forceUpdateBaseline(float rawForceN) {
  if (!_baselineReady) return;

  // Only adapt downward — baseline can never rise above boot value
  if (rawForceN < _baseline) {
    _baseline = _baseline * (1.0f - FORCE_BASELINE_ADAPT_ALPHA)
                + rawForceN * FORCE_BASELINE_ADAPT_ALPHA;
  }

  // Safety clamp: never go negative, never exceed boot baseline
  if (_baseline < 0.0f) _baseline = 0.0f;
  if (_baseline > _bootBaseline) _baseline = _bootBaseline;
}

void forceResetCalibration() {
  _baselineReady = false;
  _lpfState = 0.0f;
  _baselineSum   = 0;
  _baselineCnt   = 0;
  _baseline      = 0;
  _bootBaseline  = 0;
  _calibComplete = false;
  _calibCount    = 0;
  _calibK        = K_POPULATION_DEFAULT;  // physiological default until next session re-learns
}


// ── Chunk 4 Change 18 — per-stroke force confidence ──────────────────────────
// Returns confidence in [0.0, 1.0] reflecting how trustworthy the force-derived
// depth is for the most recent compression.
//
// Components (combined multiplicatively):
//   1. Peak force is in the calibrated range [FORCE_CONF_RANGE_MIN_N,
//      FORCE_CONF_RANGE_MAX_N]. Out of range = extrapolating the power law,
//      drop confidence sharply.
//   2. k-fit status: if forceCalibCompute has run successfully this session
//      (_calibComplete true), trust the per-session k. If not, we're using
//      the population mean K_POPULATION_DEFAULT, which has substantial
//      individual variance (Tomlinson 2007: k ranges 0.7–2.0 across the
//      population). Reflect this in lower pre-calib confidence.
//   3. Baseline stability: if the adaptive baseline has drifted significantly
//      from its boot value, force near baseline is less reliable. This is
//      a soft check — affects confidence at low force, not at peak.
//
// Returns 0.0 to 1.0.
//
float forceConfidence(float peakForceN) {
  // 1. In-range check.
  if (peakForceN < FORCE_CONF_RANGE_MIN_N) {
    // Below the calibrated minimum — force model returns 0 here anyway.
    // Confidence is zero, force path has no signal to contribute.
    return 0.0f;
  }
  if (peakForceN > FORCE_CONF_RANGE_MAX_N) {
    // Above the operating range — likely an ADC glitch or extreme over-force.
    // forceRead() at line 85 already glitch-rejects > 700 N, but defend.
    return 0.0f;
  }
  // Linear taper near the edges of the operating range for graceful behavior.
  float cRange = 1.0f;
  const float rangeMargin = 30.0f;
  if (peakForceN < FORCE_CONF_RANGE_MIN_N + rangeMargin) {
    cRange = (peakForceN - FORCE_CONF_RANGE_MIN_N) / rangeMargin;
  } else if (peakForceN > FORCE_CONF_RANGE_MAX_N - rangeMargin) {
    cRange = (FORCE_CONF_RANGE_MAX_N - peakForceN) / rangeMargin;
  }
  if (cRange < 0.0f) cRange = 0.0f;

  // 2. Calibration status. Pre-calib = population mean k, lower confidence
  //    because individual variance is large per Tomlinson 2007.
  const float cCalib = _calibComplete ? FORCE_CONF_POSTCALIB
                                      : FORCE_CONF_PRECALIB;

  // 3. Baseline stability. _baseline drifts downward over a session due to
  //    FlexiForce creep (drift < 5% per logarithmic time scale per datasheet).
  //    If it has drifted significantly from boot baseline, the force path is
  //    still trustworthy at peak — just less so near baseline. Since this
  //    function is called with peakForceN (well above baseline by definition),
  //    the baseline-stability term has a mild effect.
  float cBaseline = 1.0f;
  if (_bootBaseline > 1.0f) {
    const float drift = fabsf(_bootBaseline - _baseline) / _bootBaseline;
    if (drift > 0.25f) cBaseline = 0.85f;  // significant drift — slight penalty
    if (drift > 0.50f) cBaseline = 0.70f;  // heavy drift — larger penalty
  }

  return cRange * cCalib * cBaseline;
}

// ─── DEV: Force test exposure ─────────────────────────────────────────────
// Returns the raw filtered force WITHOUT median filtering and current
// baseline, so FORCE_TEST_LOG can show the pipeline stages.
#if FORCE_TEST_LOG
void forceTestRead(int& rawAdc, float& voltage, float& rawForceN,
                   float& baseline, float& filteredN) {
  rawAdc = analogRead(PIN_FSR_ADC);
  voltage = (rawAdc / 4095.0f) * 3.3f;

  // rawForceN = FORCE_C0 + FORCE_C1 * voltage + FORCE_C2 * voltage * voltage;
//   // If exponential instead of rawforceN:
float v_rel = voltage - FORCE_BASELINE_V;
  rawForceN = FORCE_EXP_A * (expf(FORCE_EXP_B * v_rel) - 1.0f) + FORCE_EXP_C;


  if (rawForceN > 700.0f) rawForceN = 0.0f;
  baseline = _baseline;
  filteredN = max(0.0f, rawForceN - _baseline);
}
#endif
