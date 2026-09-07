#pragma once
#include <Arduino.h>
// =============================================================================
// max30102.h — MAX30102 patient channel — RIGHT-HAND VARIANT
//
// This board has no patient sensor hardware (fingertip-on-carotid channel).
// The functions below are kept byte-identical to the left-hand board's
// do-not-touch patient-vitals / pulse-check-gating logic (see CLAUDE.md).
// max30102Init() is simply never called from cpr_glove.ino on this board,
// so _patientOk stays false and every function here takes its existing
// "sensor not OK" fallback path — the pulse-check gate never opens.
//
// The rescuer channel (continuous wrist HR/SpO2) lived here on the
// left-hand board; on this board it's the SEN0344 module — see sen0344.h.
// =============================================================================
#include "config.h"

bool max30102Init();  // init patient sensor only — see note above; never called on this board
bool max30102PatientOk();

// Patient: call only during pulse check window.
void max30102UpdatePatient(float& hrBpm, float& spO2, float& ppgRaw,
                           uint8_t& sigQuality, uint8_t& pi,
                           uint8_t& detectorACount, uint8_t& detectorBCount);

// Contact state from the most recent max30102UpdatePatient() call (its
// internal anyContact, surfaced). Does not poll — reads cached state, so
// it's free to call every loop tick. Check max30102PatientContactUpdateMs()
// against your own window's start time before trusting this — it may be a
// stale reading from before max30102UpdatePatient() was being called at all.
bool max30102PatientContactCached();

// millis() at which max30102PatientContactCached()'s value was last written.
unsigned long max30102PatientContactUpdateMs();

// Reset patient detector counts — call once at the START of each pulse check window.
void max30102ResetPatientDetectors();

// Lightweight patient contact probe for the pulse-check gate. Raw IR DC
// level only — no bandpass, no envelope, no beat detection — and does not
// touch the state max30102UpdatePatient() uses. Safe to call before a
// window opens (or after one closes) without disturbing the pipeline.
bool max30102PatientContactProbe();

// Classification: 0=Absent, 1=Uncertain, 2=Present.
// rescuerHrBpm/rescuerSigQuality are a rescuer wrist HR/SQI reference, used
// only to downgrade a Present to Uncertain when the two channels can't be
// told apart (self-detection guard, see PULSE_SELF_DETECT_BPM_TOL in
// config.h). Never upgrades, never touches Absent/Uncertain. Pure function —
// ignorant of where the reference came from; the caller decides whether to
// pass a live reading, a paused snapshot, or a fallback chain of both (see
// cpr_glove.ino). Pass rescuerSigQuality=0 (or any out-of-range HR) to
// disable the guard, e.g. when no rescuer reading is available.
uint8_t max30102ClassifyPulse(float hrBpm, uint8_t sigQuality,
                              uint8_t detA, uint8_t detB,
                              float rescuerHrBpm, uint8_t rescuerSigQuality);
