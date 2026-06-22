#pragma once
// =============================================================================
// imu.h — LSM6DSOX dual-IMU driver
// Complementary filter, in-motion gravity estimator, posture angles
// =============================================================================
#include <Wire.h>
#include "config.h"

// ── Raw IMU reading ───────────────────────────────────────────────────────────
struct IMURaw {
  float ax, ay, az;  // mg  (milli-g)
  float gx, gy, gz;  // deg/s
};

// ── Complementary filter state ────────────────────────────────────────────────
struct CompFilter {
  float pitch       = 0.0f;
  float roll        = 0.0f;
  bool  initialised = false;
  // Gravity unit vector in sensor body frame (g units).
  // Set at first stable accel reading, EMA-tracked between compressions.
  // Used by worldVertAccel for orientation-agnostic gravity removal.
  float grav_x = 0.0f;
  float grav_y = 0.0f;
  float grav_z = 0.0f;  // all zero = uninitialised; worldVertAccel returns 0 when gMag < 0.01
};

// ── In-motion gravity estimator ───────────────────────────────────────────────
struct GravityEstimate {
  float ax_g = 0.0f, ay_g = 0.0f, az_g = 0.0f;
  bool ready = false;
  int cycles = 0;
  double sumAx = 0, sumAy = 0, sumAz = 0;
  int nSamples = 0;
};

// ── Integration state ─────────────────────────────────────────────────────────
// Extended for Chunk 4 confidence metrics and Chunk 1 Aase boundary correction.
struct IntegState {
  float velocityMS    = 0.0f;
  float depthM        = 0.0f;
  float peakDepthM    = 0.0f;
  bool  peakLocked    = false;
  bool  peakJustLocked = false;

  // ── Chunk 1 Change 3 — divergence flag (replaces silent 0.12 m clamp) ──
  // Set true if the integrator reaches the sanity limit during a stroke.
  // Downstream code MUST check this and exclude diverged strokes from output.
  bool  diverged      = false;

  // ── Chunk 1 Change 2 — Aase boundary-correction telemetry ──────────────
  float vResidualAtRelease = 0.0f;

  // ── Zhang 2024 two-anchor boundary correction ──────────────────────────
  // Velocity captured at compression onset (t_start anchor). Combined with
  // vResidualAtRelease (t_end anchor) to linearly detrend the velocity curve.
  // In RELEASED state velocity is held at 0, so this is always 0 — kept
  // explicit for correctness and documentation.
  float vAtCompressionStart = 0.0f;

  // ── Chunk 1 Change 4 — previous-sample acceleration for trapezoidal int ──
  // Holds a[k-1] so v_new = v_old + 0.5*(a_prev + a_curr)*dt.
  // Reset to 0 at the start of each stroke.
  float aPrevMS2      = 0.0f;

  // ── Chunk 4 Change 17 — tilt-change accumulator ────────────────────────
  // Min/max of orientation pitch+roll seen during the current stroke. The
  // span (max - min) at stroke end goes into the confidence metric.
  // Updated by depth.cpp at every COMPRESSING sample.
  float tiltMinDeg    =  9999.0f;
  float tiltMaxDeg    = -9999.0f;
};

uint8_t imuReadWhoAmI(uint8_t tcaChannel, uint8_t i2cAddr);


// ── Public API ────────────────────────────────────────────────────────────────
bool imuInit();  // init both IMUs, returns false if palm fails
bool imuPalmOk();
bool imuWristOk();

IMURaw imuReadPalm();
IMURaw imuReadWrist();

void imuUpdateFilters(const IMURaw& palm, const IMURaw& wrist, float dt);
void imuUpdateFiltersGyroOnly(const IMURaw& palm, const IMURaw& wrist, float dt);
void imuAccumulate(const IMURaw& palm, const IMURaw& wrist);
void imuEndCycle(bool validForce);  // update gravity EMA at end of compression

float imuGetPalmPitchDeg();     // wristAlignmentAngle
float imuGetWristFlexionDeg();  // palm pitch - wrist pitch
float imuGetPalmRollDeg();      // compressionAxisDeviation

float imuGetMotionAccelPalm();  // m/s² along compression axis
float imuGetMotionAccelWrist();

void integrateCompression(IntegState& s, float a_ms2, float dt);
void resetIntegration(IntegState& s);

float getAdaptiveDepthMM(float palmMM, float wristMM);  // wrist dropout + blending

bool imuIsCalibrated();  // true once gravity converged
bool imuWristDropped();


// ── Chunk 1 Change 1/2 — refactored motion accel using CF orientation ──────
// Returns motion acceleration in m/s² along the world-vertical axis, computed
// by rotating raw accel into the world frame via the complementary filter's
// pitch/roll, then taking the Z-component and subtracting 9.81. Replaces the
// gravity-EMA + dot-product approach. Lee/Park 2021 (Biosensors 11:35) flow.
float imuGetWorldVertAccelPalm();
float imuGetWorldVertAccelWrist();

// ── Chunk 1 Change 2 — Aase boundary-correction helper ─────────────────────
// Called once at the moment of force-release to back-correct peakDepthM for
// linear bias accumulated during the stroke. Captures vResidualAtRelease
// before zeroing velocity.
void imuApplyBoundaryCorrection(IntegState& s, uint32_t strokeDurationMs);

// ── Chunk 4 Change 17 — per-stroke IMU confidence ──────────────────────────
// Returns confidence in [0.0, 1.0] for the just-completed stroke. Combines:
//   - divergence flag (hard fail → 0)
//   - residual velocity magnitude
//   - tilt change during stroke
//   - peak depth plausibility
// Called once at stroke completion, before the selector.
float imuConfidence(const IntegState& s);

// ── Chunk 4 Change 19 — confidence-weighted dual-IMU combine ───────────────
// Returns best-available IMU depth combining palm and wrist. If one is
// high-confidence and the other low, prefers the high. If both agree,
// averages them. Replaces the old diff-based weighting in getAdaptiveDepthMM.
struct DualIMUResult {
  float depthMM;
  float combinedConfidence;
  bool  usedPalm;
  bool  usedWrist;
};
DualIMUResult imuCombineDual(float palmMM, float wristMM,
                             float palmConf, float wristConf);

// ── Mahony 2008 adaptive CF gain ──────────────────────────────────────────
// Call at session start to trigger fast CF convergence to the new hand
// orientation. Uses CF_ALPHA_FAST for 60 ticks (~0.6s).
void imuTriggerFastConverge();

void imuResetCF();

// Expose integration states for use in depth.cpp
extern IntegState integPalm;
extern IntegState integWrist;
extern CompFilter cfPalm;
extern CompFilter cfWrist;
extern GravityEstimate gravPalm;
extern GravityEstimate gravWrist;