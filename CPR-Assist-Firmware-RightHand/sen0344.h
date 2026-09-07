#pragma once
// =============================================================================
// sen0344.h — DFRobot SEN0344 rescuer HR/SpO2 (Fermion MAX30102 breakout,
// onboard algorithm MCU, I²C address 0x57, direct bus — no TCA).
//
// Requires the "DFRobot_BloodOxygen_S" Arduino library (Library Manager),
// same install pattern as this project's existing MAX3010x / spo2_algorithm
// dependencies for max30102.cpp.
//
// Unlike the left-hand board's raw MAX30102 pipeline, this module only
// exposes pre-computed HR + SpO2 — no raw waveform, so there is no SQI,
// RMSSD, or perfusion index to derive here. sen0344Update()'s sigQuality
// output is a simple binary valid/invalid flag (100 if the module returned
// a plausible reading, else 0), enough for fatigue-HR gating but not a
// signal-quality measurement.
// =============================================================================
#include "config.h"

bool sen0344Init();
bool sen0344Ok();

// Call at any slow cadence (matches the left-hand board's 500 ms rescuer
// vitals tick — this module has no FIFO to drain, it's poll/response).
void sen0344Update(float& hrBpm, float& spO2, uint8_t& sigQuality);
