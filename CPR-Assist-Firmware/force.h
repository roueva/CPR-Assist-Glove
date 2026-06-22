#pragma once
// =============================================================================
// force.h — FlexiForce A401 + MCP6002 force sensor
// =============================================================================
#include "config.h"

bool forceInit();                  // baseline calibration (blocks ~2.5s)
float forceRead();                 // returns calibrated force in N, median filtered
float forceToDepth(float forceN);  // power-law force→depth model using calibrated k
bool forceBaselineReady();

// Calibration (called from depth.cpp at session start)
void forceCalibAddSample(float forceN, float imuDepthMM);
bool forceCalibComplete();
void forceCalibCompute();  // fits k from collected samples
float forceCalibK();
void forceUpdateBaseline(float rawForceN);  // call at 100Hz from sensorTask when no session active
void forceResetCalibration();   // wipe baseline + k, forces re-learn

// ── Chunk 4 Change 18 — per-stroke force-path confidence ───────────────────
// Returns confidence in [0.0, 1.0] reflecting how trustworthy the force-derived
// depth is for the most recent compression. Consumed by selectDepth() in
// depth.cpp.
//
// Components:
//   - Peak force within calibrated operating range
//   - k-fit calibration status (pre-calib uses population mean = lower conf)
//   - Baseline stability
//
float forceConfidence(float peakForceN);

void forceSetSessionActive(bool active);  // call from startSession / stopSession

#if FORCE_TEST_LOG
void forceTestRead(int& rawAdc, float& voltage, float& rawForceN,
                   float& baseline, float& filteredN);
#endif

bool forceCalibLocked();
void forceCalibLock();