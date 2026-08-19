#pragma once
#include <Arduino.h>
// =============================================================================
// max30102.h — Dual MAX30102 via TCA9548A
// Channel 4 = rescuer (wrist, continuous)
// Channel 5 = patient (fingertip, pulse check window only)
// Uses SparkFun MAX3010x library for HR/SpO2 algorithm.
// =============================================================================
#include "config.h"

bool max30102Init();  // init both sensors, returns false if both fail
bool max30102RescuerOk();
bool max30102PatientOk();
void max30102ServiceRescuer();

// Rescuer: call every loop tick. Updates HR, SpO2, signal quality.
void max30102UpdateRescuer(float& hrBpm, float& spO2, uint8_t& sigQuality,
                           uint8_t& rmsspx, uint8_t& pi);

// Patient: call only during pulse check window.
void max30102UpdatePatient(float& hrBpm, float& spO2, float& ppgRaw,
                           uint8_t& sigQuality, uint8_t& pi,
                           uint8_t& detectorACount, uint8_t& detectorBCount);

// Contact state from the most recent max30102UpdatePatient() call (its
// internal anyContact, surfaced). Does not poll — reads cached state, so
// it's free to call every loop tick. Check max30102PatientContactUpdateMs()
// against your own window's start time before trusting this — it may be a
// stale reading from before max30102UpdatePatient() was being called at all.
bool max30102PatientContactOk();

// millis() at which max30102PatientContactOk()'s value was last written.
unsigned long max30102PatientContactUpdateMs();

// Reset patient detector counts — call once at the START of each pulse check window.
void max30102ResetPatientDetectors();

// Lightweight patient contact probe for the pulse-check gate. Raw IR DC
// level only — no bandpass, no envelope, no beat detection — and does not
// touch the state max30102UpdatePatient() uses. Safe to call before a
// window opens (or after one closes) without disturbing the pipeline.
bool max30102PatientContact();

// Clear rescuer beat-detection state. Call at session start so the first beat
// after a long idle isn't rejected by the 2000ms inter-beat limit.
void max30102ResetRescuerBeats();

// Classification: 0=Absent, 1=Uncertain, 2=Present
uint8_t max30102ClassifyPulse(float hrBpm, uint8_t sigQuality,
                              uint8_t detA, uint8_t detB);

// Diagnostic — last filtered (band-passed) IR sample from rescuer pipeline.
// Returns 0 if rescuer not OK. Range typically ±300 counts during pulse.
float max30102DiagRescuerFiltered();
float max30102DiagRescuerDc();
