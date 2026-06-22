#pragma once
// =============================================================================
// depth.h — Compression state machine, depth fusion, quality tracking
// =============================================================================
#include "config.h"
#include "shared_state.h"

struct StoredCompression {
  uint32_t timestampMs;
  float depth;
  float frequency;
  uint8_t recoil;
  uint8_t overForce;
  uint8_t postureOk;
  uint8_t wristAlignX10;
  uint8_t axisDevX10;
  // Change 23 — IMU-measured residual depth at valley (mm × 10).
  // Lets analysis distinguish "force says recoil OK" from "IMU says recoil OK".
  // Tomlinson 2007 mean residual depth was 3 ± 2 mm; we expect most values 0–5.
  uint8_t residualDepthX10;
  uint8_t reserved[3];   // reduced from [4] to [3]
} __attribute__((packed));


const StoredCompression* depthGetStoredCompressions(uint16_t& count);

void depthInit();
// Called every 10ms from sensor task. Updates shared state.
void depthUpdate(float forceN, float dt, SharedState& s, GloveMode mode, Scenario scenario);

// Per-session reset
void depthSessionReset();

// Rolling rate (BPM)
float depthGetRate();

void depthSkipNextRate();

float depthGetSD();          // returns SD in cm
float depthGetLastPeakMM();  // peak depth of the most recently completed compression

float depthGetAvg();  // returns mean depth in cm

// Chunk 3 Change 13 — call before SESSION_END snapshot to finalize the last
// compression's recoil valley tracking. See depth.cpp comment.
void depthFinalizeLastValley();

// True for exactly one depthUpdate() call — the moment live depth crosses
// the lower target threshold (e.g. 5.0 cm adult) on the way down. Used to
// drive the clicker. Auto-resets when depth returns below CLICK_RESET_MM.
bool depthClickJustTriggered();

bool depthIsReleased();  // true when CompState == RELEASED (hand stationary)
