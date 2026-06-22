// =============================================================================
// imu.cpp — LSM6DSOX dual-IMU driver
// Core algorithm from Anti's depth estimation v2.0 snippet.
// Adapted: ±4g range (0x4A) with hardware LPF2, modular structure, no Serial output.
// =============================================================================
#include <Arduino.h>
#include "imu.h"
#include "tca.h"
#include <math.h>

// ── Module state ──────────────────────────────────────────────────────────────
static bool _palmOk = false;
static bool _wristOk = false;
static bool _wristDropped = false;
static int _wristDropoutCount = 0;

CompFilter cfPalm, cfWrist;
GravityEstimate gravPalm, gravWrist;
IntegState integPalm, integWrist;

// Cached last motion accel values (written by imuUpdateFilters)
static float _aPalm = 0.0f;
static float _aWrist = 0.0f;

// Adaptive CF gain counter — Mahony 2008 variable-gain complementary filter.
// Set to >0 at session start to use CF_ALPHA_FAST for rapid convergence.
static uint8_t _cfFastConvergeTicksLeft = 0;

// Deferred CF reset state — armed by imuResetCF(), fires after stillness.
static bool _pendingCFReset = false;
static uint8_t _stillTicks = 0;

uint8_t imuReadWhoAmI(uint8_t tcaChannel, uint8_t i2cAddr) {
  Wire.beginTransmission(TCA_ADDRESS);
  Wire.write(1 << tcaChannel);
  if (Wire.endTransmission() != 0) return 0xFF;  // TCA error
  delayMicroseconds(300);                        // ← TCA channel switch settle time
  Wire.beginTransmission(i2cAddr);
  Wire.write(LSM6DSOX_WHO_AM_I);
  if (Wire.endTransmission(false) != 0) return 0x00;  // no ACK
  Wire.requestFrom(i2cAddr, (uint8_t)1);
  if (Wire.available()) return Wire.read();
  return 0xFF;
}

// ── I²C helpers ───────────────────────────────────────────────────────────────
static uint8_t readReg(uint8_t addr, uint8_t reg) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(addr, (uint8_t)1);
  return Wire.available() ? Wire.read() : 0xFF;
}

static void writeReg(uint8_t addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
  delay(10);
}

static int16_t readAxis(uint8_t addr, uint8_t regLow) {
  Wire.beginTransmission(addr);
  Wire.write(regLow);
  Wire.endTransmission(false);
  Wire.requestFrom(addr, (uint8_t)2);
  if (Wire.available() < 2) return 0;
  uint8_t lo = Wire.read();
  uint8_t hi = Wire.read();
  return (int16_t)((hi << 8) | lo);
}

// ── Sensor init ───────────────────────────────────────────────────────────────
static bool initOne(uint8_t ch, uint8_t addr) {
  tcaSelect(ch);
  delay(10);
  uint8_t who = readReg(addr, LSM6DSOX_WHO_AM_I);
  if (who != 0x6C) return false;

  writeReg(addr, LSM6DSOX_CTRL3_C, 0x01);  // soft reset
  delay(50);

  writeReg(addr, LSM6DSOX_CTRL1_XL, IMU_CTRL1_XL_VALUE);
  delay(20);

  writeReg(addr, LSM6DSOX_CTRL2_G, IMU_CTRL2_G_VALUE);
  delay(20);

// Chunk 1 Change 6 (optional) — enable LSM6DSOX built-in analog anti-aliasing
// filter via CTRL1_XL bit 1 (LPF2). Provides ~ODR/2 cutoff with sharp roll-off,
// reducing aliasing in the integration band. Cost: negligible (one register
// write at boot, no runtime cost).
// IMU_CTRL1_XL_VALUE is 0x4A = 0100 1010: ODR=104Hz, FS=±4g, LPF2=ON.
// LPF2 is currently ENABLED. To disable: change to 0x48 (clears bit 1).
return true;
}

bool imuInit() {
  _palmOk  = initOne(TCA_CH_IMU_PALM,  LSM6DSOX_ADDR_PALM);
  _wristOk = initOne(TCA_CH_IMU_WRIST, LSM6DSOX_ADDR_WRIST);
  // Boot diagnostic — print raw accel from both IMUs
  delay(50);
  IMURaw p = imuReadPalm();
  IMURaw w = imuReadWrist();
  Serial.printf("[IMU-BOOT] palm raw: ax=%.1f ay=%.1f az=%.1f mg\n", p.ax, p.ay, p.az);
  Serial.printf("[IMU-BOOT] wrist raw: ax=%.1f ay=%.1f az=%.1f mg\n", w.ax, w.ay, w.az);
  return _palmOk;
}

bool imuPalmOk() {
  return _palmOk;
}
bool imuWristOk() {
  return _wristOk;
}

// ── Read ──────────────────────────────────────────────────────────────────────
static IMURaw readOne(uint8_t ch, uint8_t addr) {
  tcaSelect(ch);
  delayMicroseconds(300);
  IMURaw r;
  r.ax = readAxis(addr, LSM6DSOX_OUTX_L_A) * ACCEL_SENSITIVITY;
  r.ay = readAxis(addr, LSM6DSOX_OUTY_L_A) * ACCEL_SENSITIVITY;
  r.az = readAxis(addr, LSM6DSOX_OUTZ_L_A) * ACCEL_SENSITIVITY;
  r.gx = readAxis(addr, LSM6DSOX_OUTX_L_G) * GYRO_SENSITIVITY;
  r.gy = readAxis(addr, LSM6DSOX_OUTY_L_G) * GYRO_SENSITIVITY;
  r.gz = readAxis(addr, LSM6DSOX_OUTZ_L_G) * GYRO_SENSITIVITY;
  return r;
}

IMURaw imuReadPalm() {
  return readOne(TCA_CH_IMU_PALM, LSM6DSOX_ADDR_PALM);
}
IMURaw imuReadWrist() {
  return readOne(TCA_CH_IMU_WRIST, LSM6DSOX_ADDR_WRIST);
}

// ── Complementary filter ──────────────────────────────────────────────────────
static void updateCF(CompFilter& cf, const IMURaw& raw, float dt) {
  const float ax_g = raw.ax / 1000.0f;
  const float ay_g = raw.ay / 1000.0f;
  const float az_g = raw.az / 1000.0f;
  const float gx_rads = raw.gx * DEG_TO_RAD;
  const float gy_rads = raw.gy * DEG_TO_RAD;

  const float mag = sqrtf(ax_g*ax_g + ay_g*ay_g + az_g*az_g);
  const bool  accelValid = (mag > 0.85f && mag < 1.15f);

  if (!cf.initialised) {
    if (!accelValid) return;
    cf.pitch  = atan2f(ax_g, sqrtf(ay_g*ay_g + az_g*az_g));
    cf.roll   = atan2f(ay_g, sqrtf(ax_g*ax_g + az_g*az_g));
    cf.grav_x = ax_g;
    cf.grav_y = ay_g;
    cf.grav_z = az_g;
    cf.initialised = true;
    return;
  }

  // Gyro integration always runs
  cf.pitch += gy_rads * dt;
  cf.roll  += gx_rads * dt;

  // Accel correction only when sensor is near-stationary (not during compression)
  if (accelValid) {
    const float accel_pitch = atan2f(ax_g, sqrtf(ay_g*ay_g + az_g*az_g));
    const float accel_roll  = atan2f(ay_g, sqrtf(ax_g*ax_g + az_g*az_g));
    const float alpha = (_cfFastConvergeTicksLeft > 0) ? CF_ALPHA_FAST : CF_ALPHA;
    if (_cfFastConvergeTicksLeft > 0) _cfFastConvergeTicksLeft--;
    cf.pitch = alpha * cf.pitch + (1.0f - alpha) * accel_pitch;
    cf.roll  = alpha * cf.roll  + (1.0f - alpha) * accel_roll;

    // Track gravity direction EMA in body frame
    const float ga = 0.98f;
    cf.grav_x = ga * cf.grav_x + (1.0f - ga) * ax_g;
    cf.grav_y = ga * cf.grav_y + (1.0f - ga) * ay_g;
    cf.grav_z = ga * cf.grav_z + (1.0f - ga) * az_g;
  }
}

static void updateCFWrist(CompFilter& cf, const IMURaw& raw, float dt) {
  const float ax_g = raw.ax / 1000.0f;
  const float ay_g = raw.ay / 1000.0f;
  const float az_g = raw.az / 1000.0f;
  // Wrist: gravity on +X → pitch is rotation about Z, roll about Y
  const float gz_rads = raw.gz * DEG_TO_RAD;
  const float gy_rads = raw.gy * DEG_TO_RAD;

  const float mag = sqrtf(ax_g*ax_g + ay_g*ay_g + az_g*az_g);
  const bool accelValid = (mag > 0.85f && mag < 1.15f);

  if (!cf.initialised) {
    if (!accelValid) return;
    cf.pitch  = atan2f(ax_g, sqrtf(ay_g*ay_g + az_g*az_g));
    cf.roll   = atan2f(ay_g, sqrtf(ax_g*ax_g + az_g*az_g));
    cf.grav_x = ax_g;
    cf.grav_y = ay_g;
    cf.grav_z = az_g;
    cf.initialised = true;
    return;
  }

  cf.pitch += gz_rads * dt;
  cf.roll  += gy_rads * dt;

  if (accelValid) {
    const float accel_pitch = atan2f(ax_g, sqrtf(ay_g*ay_g + az_g*az_g));
    const float accel_roll  = atan2f(ay_g, sqrtf(ax_g*ax_g + az_g*az_g));
    const float alpha = (_cfFastConvergeTicksLeft > 0) ? CF_ALPHA_FAST : CF_ALPHA;
    cf.pitch = alpha * cf.pitch + (1.0f - alpha) * accel_pitch;
    cf.roll  = alpha * cf.roll  + (1.0f - alpha) * accel_roll;
    const float ga = 0.98f;
    cf.grav_x = ga * cf.grav_x + (1.0f - ga) * ax_g;
    cf.grav_y = ga * cf.grav_y + (1.0f - ga) * ay_g;
    cf.grav_z = ga * cf.grav_z + (1.0f - ga) * az_g;
  }
}

// ── Gravity accumulator ───────────────────────────────────────────────────────
static void gravAccum(GravityEstimate& g, const IMURaw& raw) {
  g.sumAx += raw.ax;
  g.sumAy += raw.ay;
  g.sumAz += raw.az;
  g.nSamples++;
}


static void gravCycleUpdate(GravityEstimate& g) {
  if (g.nSamples < 5) {
    g.sumAx = g.sumAy = g.sumAz = 0;
    g.nSamples = 0;
    return;
  }

  float mAx = (float)(g.sumAx / g.nSamples) / 1000.0f;
  float mAy = (float)(g.sumAy / g.nSamples) / 1000.0f;
  float mAz = (float)(g.sumAz / g.nSamples) / 1000.0f;
  float mag = sqrtf(mAx * mAx + mAy * mAy + mAz * mAz);

  if (mag < 0.5f || mag > 2.0f) {
    g.sumAx = g.sumAy = g.sumAz = 0;
    g.nSamples = 0;
    return;
  }

  if (!g.ready) {
    g.ax_g = mAx; g.ay_g = mAy; g.az_g = mAz;
    g.ready = true;
  } else {
    g.ax_g = GRAV_EMA_ALPHA * g.ax_g + (1.0f - GRAV_EMA_ALPHA) * mAx;
    g.ay_g = GRAV_EMA_ALPHA * g.ay_g + (1.0f - GRAV_EMA_ALPHA) * mAy;
    g.az_g = GRAV_EMA_ALPHA * g.az_g + (1.0f - GRAV_EMA_ALPHA) * mAz;
  }
  g.cycles++;
  g.sumAx = g.sumAy = g.sumAz = 0;
  g.nSamples = 0;
}

// ── Motion acceleration via CF-driven world-frame projection (Chunk 1 Change 1)
// ─────────────────────────────────────────────────────────────────────────────
// Replaces the gravity-EMA + dot-product approach. Rotates raw acceleration
// into the world frame using the complementary filter's pitch/roll, then
// subtracts gravity from the Z component to get true vertical motion.
//
// Literature anchor: Lee/Park 2021 (Biosensors 11:35) — "Because ag(t)
// changes depending on inclination of the acceleration sensor, the orientation
// of the sensor must be known [continuously]. We obtained sensor orientation
// with a gradient descent algorithm from Madgwick et al. The orientation is
// expressed as Euler angles. Real-time gravity acceleration is obtained using
// the rotation matrix by setting the z-axis of acceleration parallel to gravity.
// The movement acceleration of the CC in real-time can be obtained by removing
// the gravity component."
//
// We use the complementary filter (CF) instead of Madgwick for embedded
// simplicity. The CF tracks pitch and roll at 100 Hz; the rotation handles
// gravity removal continuously, including during the stroke. This fixes the
// stale-gravity problem of the previous between-cycle EMA approach.
//
static float worldVertAccel(const IMURaw& raw, const CompFilter& cf) {
  if (!cf.initialised) return 0.0f;

  const float gMag = sqrtf(cf.grav_x*cf.grav_x + cf.grav_y*cf.grav_y + cf.grav_z*cf.grav_z);
  if (gMag < 0.01f) return 0.0f;

  // Raw accel in m/s²
  const float ax = (raw.ax / 1000.0f) * 9.81f;
  const float ay = (raw.ay / 1000.0f) * 9.81f;
  const float az = (raw.az / 1000.0f) * 9.81f;

  // Gravity unit vector in body frame
  const float gx = cf.grav_x / gMag;
  const float gy = cf.grav_y / gMag;
  const float gz = cf.grav_z / gMag;

  // Project raw accel onto gravity direction → gives gravity component
  // Subtract 9.81 → pure motion accel along compression axis
  const float gravComponent = ax*gx + ay*gy + az*gz;
  float a_motion = gravComponent - 9.81f;

  if (fabsf(a_motion) < ACC_DEADBAND_MS2) a_motion = 0.0f;
  return a_motion;
}

// Chunk 1 Change 1 — public accessors for the world-frame vertical accel.
// Same semantics as the old imuGetMotionAccelPalm/Wrist — kept for source
// compatibility. New name in the .h for forward-looking clarity.
float imuGetWorldVertAccelPalm()  { return _aPalm; }
float imuGetWorldVertAccelWrist() { return _aWrist; }

// ── Public update (called every sample in sensor task) ────────────────────────

void imuUpdateFilters(const IMURaw& palm, const IMURaw& wrist, float dt) {
  // Deferred CF reset: wait for stillness before capturing gravity reference.
  if (_pendingCFReset) {
    const float magP = sqrtf(palm.ax*palm.ax + palm.ay*palm.ay + palm.az*palm.az) / 1000.0f;
    // "Still" = accel magnitude within 3% of 1g (no compression happening)
    if (magP > 0.97f && magP < 1.03f) {
      _stillTicks++;
      if (_stillTicks >= 30) {   // ~300ms at 100Hz of continuous stillness
        cfPalm.initialised  = false;
        cfWrist.initialised = false;
        resetIntegration(integPalm);
        resetIntegration(integWrist);
        _pendingCFReset = false;
        _stillTicks = 0;
        _cfFastConvergeTicksLeft = 60;
      }
    } else {
      _stillTicks = 0;  // motion resets the still counter
    }
  }

  updateCF(cfPalm, palm, dt);
  updateCFWrist(cfWrist, wrist, dt);
  _aPalm  = worldVertAccel(palm, cfPalm);
  _aWrist = worldVertAccel(wrist, cfWrist);
}

void imuUpdateFiltersGyroOnly(const IMURaw& palm, const IMURaw& wrist, float dt) {
  cfPalm.pitch  += palm.gy  * DEG_TO_RAD * dt;
  cfPalm.roll   += palm.gx  * DEG_TO_RAD * dt;
  cfWrist.pitch += wrist.gz * DEG_TO_RAD * dt;
  cfWrist.roll  += wrist.gy * DEG_TO_RAD * dt;
  _aPalm  = worldVertAccel(palm,  cfPalm);
  _aWrist = worldVertAccel(wrist, cfWrist);
}

void imuAccumulate(const IMURaw& palm, const IMURaw& wrist) {
  gravAccum(gravPalm, palm);
  if (_wristOk && !_wristDropped) gravAccum(gravWrist, wrist);
}

void imuEndCycle(bool validForce) {
  if (!validForce) return;
  gravCycleUpdate(gravPalm);
  if (_wristOk && !_wristDropped) gravCycleUpdate(gravWrist);
}

void imuTriggerFastConverge() {
  // Called at session start. The hand has just been repositioned on the
  // manikin — use CF_ALPHA_FAST for 60 ticks (~0.6s) to converge quickly
  // to the new hand orientation before the first compression.
  // Literature: Mahony 2008 — variable gain complementary filter.
  _cfFastConvergeTicksLeft = 60;
}

// ── Angle outputs ─────────────────────────────────────────────────────────────
float imuGetPalmPitchDeg() {
  return cfPalm.pitch * RAD_TO_DEG;
}
float imuGetPalmRollDeg() {
  return cfPalm.roll * RAD_TO_DEG;
}

float imuGetWristFlexionDeg() {
  return (cfPalm.pitch - cfWrist.pitch) * RAD_TO_DEG;
}

float imuGetMotionAccelPalm() {
  return _aPalm;
}
float imuGetMotionAccelWrist() {
  return _aWrist;
}

// ── Compression integration (Chunk 1 Changes 2, 3, 4) ────────────────────────
// Trapezoidal integration, divergence-flag-instead-of-clamp, and prep for
// Aase boundary correction (the correction itself happens at force-release,
// not here — see imuApplyBoundaryCorrection below).
//
// Literature anchors:
//   - Trapezoidal integration: Zhang 2024 (IEEE Sensors J. 24:3779) uses
//     trapezoidal explicitly. Strictly more accurate than Euler at equal cost.
//   - Divergence-as-invalidation: Tomlinson 2021 review — drift is the
//     dominant integration error source; published methods invalidate or
//     flag, they do NOT silently clamp. Our previous 0.12 m clamp was masking
//     integrator runaway as plausible 12 cm reports.
//   - Per-cycle boundary conditions: Aase & Myklebust 2002 (via Zhang 2024
//     citation) — "set velocity and displacement to zero at the moment of
//     force-release; capture residual velocity to back-correct the
//     just-completed stroke for accumulated bias."
//
void integrateCompression(IntegState& s, float a_ms2, float dt) {
  // Don't continue integrating once diverged.
  if (s.diverged) return;

  // Trapezoidal integration (Change 4):
  //   v_new = v_old + 0.5 * (a_prev + a_curr) * dt
  s.velocityMS += 0.5f * (s.aPrevMS2 + a_ms2) * dt;
  s.aPrevMS2    = a_ms2;

  // Velocity clamp at ±1.2 m/s — physical limit (120 BPM × 6 cm peak-to-peak
  // ≈ 1.2 m/s peak velocity). Above this is by definition non-physiological.
  s.velocityMS = constrain(s.velocityMS, -1.20f, 1.20f);

  // Position integration (trapezoidal would need v_prev too; we use Euler
  // here because position is the time-integral of velocity, and v itself
  // is already trapezoidal — second-order errors are minimal). Sign
  // convention: positive depth = downward motion (compression).
  s.depthM += s.velocityMS * dt;

  // Divergence detection (Change 3):
  // Replace the old silent clamp at 0.12 m with an explicit flag. Downstream
  // (depth.cpp at stroke completion) checks this and excludes the stroke
  // from the output / from force calibration.
  if (s.depthM > 0.12f) {
    s.diverged = true;
    s.depthM   = 0.12f;  // pin to avoid huge transient values; downstream
                         // knows to ignore this stroke.
    return;
  }
  if (s.depthM < 0.0f) s.depthM = 0.0f;

  // Peak-lock logic (preserved from previous fix). Once locked, peak is
  // immutable for the rest of the stroke.
  if (!s.peakLocked) {
    if (s.depthM > s.peakDepthM) {
      s.peakDepthM = s.depthM;
    } else if (s.velocityMS < -0.02f && s.peakDepthM > 0.01f) {
      // Velocity reversed below -2 cm/s with a real peak above 1 cm → lock.
      // From this point the integrator continues to update depthM for
      // recoil/valley tracking but peakDepthM is frozen.
      s.peakLocked    = true;
      s.peakJustLocked = true;
      s.velocityMS    = 0.0f;
    }
  }
}


// ── Aase per-cycle boundary correction (Chunk 1 Change 2) ────────────────────
// Called exactly once at the moment of force-release, BEFORE peakDepthM is
// consumed by downstream (depth.cpp:367).
//
// Theory: at force-release the hand is momentarily stationary by physical
// necessity (downward velocity reaches zero before the recoil upward phase
// begins). Any non-zero residual velocity v_res in the integrator at this
// moment is by definition accumulated bias over the stroke duration T.
//
// The position contribution of a linear bias drift over time T is approximately
//   delta_x_bias ≈ 0.5 * v_res * T   (triangular integration area)
//
// We back-correct peakDepthM by this amount and capture v_res for the
// confidence metric.
//
// Literature: Aase & Myklebust 2002, "CPR algorithm" (cited via Zhang 2024
// IEEE Sensors J. 24:3779). Zhang implements an analogous detrending using
// linear interpolation between zero-velocity points at known timestamps
// from a pressure sensor.
//
void imuApplyBoundaryCorrection(IntegState& s, uint32_t strokeDurationMs) {
  if (s.diverged) { s.vResidualAtRelease = 0.0f; return; }

  s.vResidualAtRelease = s.velocityMS;

  if (strokeDurationMs < 50 || s.peakDepthM < 0.005f) {
    s.velocityMS = 0.0f;
    return;
  }

  const float strokeS = strokeDurationMs / 1000.0f;

  // Triangular drift area: 0.5 * v_res * T.
  // For a constant acceleration bias, this exactly cancels the accumulated
  // position error (the area under a triangular velocity profile = 0.5*v*T).
  // Literature: Aase & Myklebust 2002, Zhang 2024.
  const float biasM = 0.5f * s.velocityMS * strokeS;

  s.peakDepthM = fmaxf(0.0f, s.peakDepthM - biasM);
  s.velocityMS = 0.0f;
}

void resetIntegration(IntegState& s) {
  s.velocityMS            = 0.0f;
  s.depthM                = 0.0f;
  s.peakDepthM            = 0.0f;
  s.peakLocked            = false;
  s.peakJustLocked        = false;
  s.diverged              = false;
  s.vResidualAtRelease    = 0.0f;
  s.vAtCompressionStart   = 0.0f;
  s.aPrevMS2              = 0.0f;
  s.tiltMinDeg            =  9999.0f;
  s.tiltMaxDeg            = -9999.0f;
}

// ── Dual-IMU confidence-weighted combine (Chunk 4 Change 19) ─────────────────
// Replaces the old diff-based weighting (0.85/0.15, 0.70/0.30, 0.50/0.50)
// with a principled confidence-weighted combination.
//
// Strategy:
//   - If wrist is dropped, use palm only.
//   - If either IMU's confidence is below hard-fail, use the other.
//   - If both are healthy and confidences are similar, average them.
//   - If both are healthy but one is much higher confidence, weight toward it.
//
// The combined depth and a combined confidence are returned together.
//
DualIMUResult imuCombineDual(float palmMM, float wristMM,
                             float palmConf, float wristConf) {
  DualIMUResult r;

  // Plausibility gate — declared first so all branches below can use it.
  // Override confidence to 0 for non-physiological values. AHA adult CPR
  // range: 5–80mm. Outside this the integrator has failed regardless of
  // what the confidence components compute. Threshold matches
  // IMU_CONF_DEPTH_MAX_MM in config.h so there is one place to tune it.
  const float palmConfGated  = (palmMM  >= 5.0f && palmMM  <= 80.0f) ? palmConf  : 0.0f;
const float wristConfGated = (wristMM >= 5.0f && wristMM <= 80.0f) ? wristConf : 0.0f;

  // Wrist unavailable — palm only.
  if (!_wristOk || _wristDropped || wristMM <= 0.0f) {
    r.depthMM            = palmMM;
    r.combinedConfidence = palmConfGated;
    r.usedPalm           = true;
    r.usedWrist          = false;
    return r;
  }

  // Both available. Decide weighting using gated confidences.
  const bool palmReliable  = (palmConfGated  >= SELECTOR_HARD_FAIL_CONF);
  const bool wristReliable = (wristConfGated >= SELECTOR_HARD_FAIL_CONF);

  if (palmReliable && !wristReliable) {
    r.depthMM            = palmMM;
    r.combinedConfidence = palmConfGated;
    r.usedPalm = true; r.usedWrist = false;
    return r;
  }
  if (wristReliable && !palmReliable) {
    r.depthMM            = wristMM;
    r.combinedConfidence = wristConfGated;
    r.usedPalm = false; r.usedWrist = true;
    return r;
  }

  // Both reliable or both unreliable — blend or fall back.
  const float total = palmConfGated + wristConfGated;
  if (total > 0.001f) {
    const float agreement = 1.0f - fminf(1.0f, fabsf(palmMM - wristMM) /
                                              SELECTOR_AGREE_THRESHOLD_MM);

    if (agreement <= 0.0f) {
      // Sensors disagree beyond threshold — return the higher-confidence one.
      if (palmConfGated >= wristConfGated) {
        r.depthMM            = palmMM;
        r.combinedConfidence = palmConfGated;
        r.usedPalm = true; r.usedWrist = false;
      } else {
        r.depthMM            = wristMM;
        r.combinedConfidence = wristConfGated;
        r.usedPalm = false; r.usedWrist = true;
      }
      return r;
    }

    // Agreement within threshold — confidence-weighted blend.
    const float wPalm  = palmConfGated  / total;
    const float wWrist = wristConfGated / total;
    r.depthMM            = wPalm * palmMM + wWrist * wristMM;
    r.combinedConfidence = fmaxf(palmConfGated, wristConfGated) * agreement;
    r.usedPalm = true; r.usedWrist = true;
  } else {
    // Both zero confidence after plausibility gating — neither sensor is
    // trustworthy. Return whichever value is in physiological range
    // (preferring wrist), at zero confidence so the selector falls back to force.
    const bool palmOk  = (palmMM  >= 5.0f && palmMM  <= 80.0f);
const bool wristOk = (wristMM >= 5.0f && wristMM <= 80.0f);
    if (wristOk)     { r.depthMM = wristMM; r.usedPalm = false; r.usedWrist = true; }
    else if (palmOk) { r.depthMM = palmMM;  r.usedPalm = true;  r.usedWrist = false; }
    else             { r.depthMM = 0.0f;    r.usedPalm = false; r.usedWrist = false; }
    r.combinedConfidence = 0.0f;
  }

  return r;
}


void imuResetCF() {
  // Don't re-zero immediately — arm a deferred reset that fires once the
  // glove has been still (hand flat on chest) for ~300ms. This guarantees
  // the gravity reference is captured with the hand in compression position,
  // not mid-air while the user is still positioning.
  _pendingCFReset = true;
  _stillTicks = 0;
}

// ── Backward-compatibility wrapper ───────────────────────────────────────────
// depth.cpp currently calls getAdaptiveDepthMM(palmMM, wristMM). To minimize
// the depth.cpp diff, keep this function as a thin wrapper that calls the
// new combine. It loses the confidence return value, so depth.cpp should
// gradually migrate to imuCombineDual. For now, it computes confidences
// internally so existing call sites continue working.
//
// (depth.cpp will be updated in Section 5 to use imuCombineDual directly.)
float getAdaptiveDepthMM(float palmMM, float wristMM) {
  if (!_wristOk || _wristDropped) return palmMM;
  bool wristConverged = (gravWrist.cycles >= GRAV_MIN_CYCLES_WRIST);
  if (wristMM <= 0.0f) {
    if (wristConverged) {
      _wristDropoutCount++;
      if (_wristDropoutCount >= WRIST_DROPOUT_LIMIT) _wristDropped = true;
    }
    return palmMM;
  }
  _wristDropoutCount = 0;

  // For the wrapper, we don't have IntegState access here, so we can't
  // compute confidence. Use a degraded version: agreement-only weighting,
  // similar to the old code but cleaner.
  const float diff = fabsf(palmMM - wristMM);
  const float agreement = 1.0f - fminf(1.0f, diff / SELECTOR_AGREE_THRESHOLD_MM);
  // When they agree, average; when they disagree, weight toward palm
  // (the more rigidly-mounted IMU, per design assumption).
  const float wPalm  = 0.5f + (1.0f - agreement) * 0.3f;
  const float wWrist = 1.0f - wPalm;
  return wPalm * palmMM + wWrist * wristMM;
}


// ── Status ────────────────────────────────────────────────────────────────────
bool imuIsCalibrated() {
  // CF needs ~1 second to converge. Use CF initialised flag plus a
  // post-init cycle count. The old gravity EMA cycle count is no longer
  // the primary calibration signal — left in place for compatibility.
  return cfPalm.initialised && (gravPalm.cycles >= GRAV_MIN_CYCLES_PALM);
}


// ── IMU per-stroke confidence (Chunk 4 Change 17) ────────────────────────────
// Returns a scalar confidence in [0.0, 1.0] reflecting how trustworthy the
// just-completed stroke's depth estimate is. Used by the selector in depth.cpp.
//
// Four components, combined multiplicatively (any one near 0 drops total to ~0):
//   1. Divergence flag — hard fail if true.
//   2. Residual velocity magnitude — drift indicator (Zhang 2024 principle).
//   3. Tilt change during stroke — gravity-leakage indicator (Lee/Park 2021).
//   4. Peak depth plausibility — physiological range check (AHA/ERC, Hellevuo 2013).
//
// Each component returns [0, 1] independently; final = product. This is
// strict — a stroke must pass ALL checks to score high. Alternative would
// be additive/averaged combination; multiplicative was chosen because a
// single failure mode is usually decisive (a diverged stroke isn't
// "partially trustworthy").
//
float imuConfidence(const IntegState& s) {
  // 1. Hard fail on divergence.
  if (s.diverged) return 0.0f;

  // 2. Residual velocity component.
  // Below GOOD = full credit (1.0). Above FAIL = no credit (0.0).
  // Linear ramp between.
  const float vMag = fabsf(s.vResidualAtRelease);
  float cVres;
  if (vMag <= IMU_CONF_VRES_GOOD_MS) {
    cVres = 1.0f;
  } else if (vMag >= IMU_CONF_VRES_FAIL_MS) {
    cVres = 0.0f;
  } else {
    cVres = 1.0f - (vMag - IMU_CONF_VRES_GOOD_MS) /
                   (IMU_CONF_VRES_FAIL_MS - IMU_CONF_VRES_GOOD_MS);
  }

  // 3. Tilt change component. Uses min/max accumulated during stroke.
  float tiltSpan = 0.0f;
  if (s.tiltMaxDeg > -9000.0f && s.tiltMinDeg < 9000.0f) {
    tiltSpan = s.tiltMaxDeg - s.tiltMinDeg;
  }
  float cTilt;
  if (tiltSpan <= IMU_CONF_TILT_GOOD_DEG) {
    cTilt = 1.0f;
  } else if (tiltSpan >= IMU_CONF_TILT_FAIL_DEG) {
    cTilt = 0.0f;
  } else {
    cTilt = 1.0f - (tiltSpan - IMU_CONF_TILT_GOOD_DEG) /
                   (IMU_CONF_TILT_FAIL_DEG - IMU_CONF_TILT_GOOD_DEG);
  }

  // 4. Peak depth plausibility (binary — in physiological range or not).
  const float peakMM = s.peakDepthM * 1000.0f;
  const float cDepth = (peakMM >= IMU_CONF_DEPTH_MIN_MM &&
                        peakMM <= IMU_CONF_DEPTH_MAX_MM) ? 1.0f : 0.2f;
  // Note: not zero for out-of-range — a 18 mm stroke is suspicious but
  // not as certainly-broken as a diverged one. 0.2 keeps it as a hint
  // rather than a hard exclusion.

  return cVres * cTilt * cDepth;
}


bool imuWristDropped() {
  return _wristDropped;
}