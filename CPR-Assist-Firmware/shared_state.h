#pragma once
// =============================================================================
// shared_state.h — Thread-safe shared data between sensor task and comms task
//
// Sensor task (Core 1) writes. Comms task (Core 0) reads.
// Protected by a portMUX_TYPE spinlock. Always acquire before read or write.
//
// Usage:
//   portENTER_CRITICAL(&gStateMux);
//   // read or write gState fields
//   portEXIT_CRITICAL(&gStateMux);
//
// Both tasks use portENTER_CRITICAL / portEXIT_CRITICAL.
// The _ISR variants are only for true ISR context (not used here).
// =============================================================================

#include <freertos/FreeRTOS.h>
#include <freertos/portmacro.h>
#include <stdint.h>

// ── Operating modes ───────────────────────────────────────────────────────────
enum class GloveMode : uint8_t {
  Emergency = 0,
  Training = 1,
  NoFeedback = 2
};

enum class Scenario : uint8_t {
  Adult = 0,
  Pediatric = 1
};

// ── Shared live data (written by sensor task at 100Hz) ────────────────────────
struct SharedState {
  // ── Core compression
  float depth;              // cm, instantaneous
  float lastPeakDepthCm;    // most recent completed compression's locked peak (cm)
  // Chunk 4 — selector telemetry. lastPeakDepthCm above is the final selected
  // depth; these two describe HOW it was produced for app-side display and
  // for thesis analysis. Both updated atomically with lastPeakDepthCm.
  uint8_t lastPeakConfidence;   // 0–100, overall confidence in lastPeakDepthCm
  uint8_t lastPeakDepthSource;  // DepthSource enum value (see depth.cpp)
  float frequency;          // BPM, instantaneous (last 2 compressions)
  float force;              // N
  float instantaneousRate;  // BPM, last-2-comp
  int32_t compressionCount;
  uint32_t compressionInCycle;  // resets at ventilation

  // ── Posture
  float wristAlignmentAngle;       // degrees — palm absolute pitch
  float wristFlexionAngle;         // degrees — palm minus wrist pitch
  float compressionAxisDeviation;  // degrees — palm roll
  float depthTrend;                // cm — 5-comp rolling avg of peak depths

  // ── Per-compression flags
  bool recoilAchieved;
  bool leaningDetected;
  bool overForceFlag;
  bool postureOk;
  uint16_t ventilationCount;
  bool fatigueFlag;
  uint8_t rescuerFatigueScore;  // 0–100
  bool imuCalibrated;
  bool wristDropped;
  float valleyDepth;  // cm

  uint32_t peakTimestampMs;    // ms since session start when peak was locked
  uint32_t valleyTimestampMs;  // ms since session start when valley was confirmed

  // ── Patient vitals (valid during pulse check only)
  float heartRatePatient;
  float spO2Patient;
  float ppgRaw;                            // 0–1
  uint8_t ppgSignalQuality;                // 0–100
  uint8_t perfusionIndex;                  // 0–100
  float patientTemperature;                // °C
  uint8_t detectorACount;                  // patient pulse check — raw peaks, no refractory gate
  uint8_t detectorBCount;                  // patient pulse check — refractory-gated confirmed beats
  float patientTemperatureLastPulseCheck;  // °C — last value captured with finger on sensor during a pulse check

  // ── Rescuer vitals (continuous)
  float heartRateUser;           // BPM
  float spO2User;                // %
  uint8_t rescuerSignalQuality;  // 0–100
  uint8_t rescuerRMSSD;          // ms, 0–200
  float rescuerTemperature;      // °C
  float rescuerHumidity;         // %
  uint8_t rescuerPI;             // 0–100

  // ── Session state
  bool sessionActive;
  bool pulseCheckActive;
  GloveMode currentMode;
  Scenario currentScenario;
  bool     audioFeedbackEnabled;     // DFPlayer voice + click cues
  bool     hapticFeedbackEnabled;    // Vibration motor (metronome, clicks, alerts)
  bool     visualFeedbackEnabled;    // NeoPixel depth bar, rate LED, status
  uint8_t batteryPercentage;  // 0–100
  bool isCharging;


  bool inVentilationWindow;  // true during 30:2 ventilation pause

  // ── Session summary fields (written at session end for SESSION_END packet)
  uint32_t totalCompressions;
  uint32_t timeToFirstCompressionMs;  // ms from SESSION_START to first compression peak
  uint32_t sessionStartMs;            // millis() at SESSION_START (for relative timestamps)
  uint32_t correctDepth;
  uint32_t correctFrequency;
  uint32_t correctRecoil;
  float averageDepth;  // cm — mean of all graded compression peak depths
  uint32_t depthRateCombo;
  uint32_t correctPosture;
  uint32_t leaningCount;
  uint32_t overForceCount;
  uint32_t tooDeepCount;
  uint32_t totalVentilations;
  uint32_t correctVentilations;
  uint32_t pulseChecksPrompted;
  uint32_t pulseChecksComplied;
  uint32_t fatigueOnsetIndex;
  float peakDepth;           // cm
  float compressionDepthSD;  // cm
  float rescuerHRLastPause;
  float rescuerSpO2LastPause;
  float rescuerTemperatureStart;
  float rescuerTemperatureEnd;
  bool pulseDetected;
  uint16_t noFlowIntervals;
  uint8_t rescuerSwapCount;

  // ── Target overrides (from app commands)
  float targetDepthMinMM;  // default from scenario
  float targetDepthMaxMM;
  float targetRateMin;  // BPM
  float targetRateMax;
  uint8_t ventilationCompressions;  // default 30
  uint8_t ventilationBreaths;       // default 2
};

// ── Global instance and lock ──────────────────────────────────────────────────
extern SharedState gState;
extern portMUX_TYPE gStateMux;

// ── Convenience snapshot — copies the whole struct atomically ─────────────────
inline SharedState snapshotState() {
  SharedState copy;
  portENTER_CRITICAL(&gStateMux);
  copy = gState;
  portEXIT_CRITICAL(&gStateMux);
  return copy;
}

// ── Diagnostic mode globals (written by onAppCommand, read by bleSendLiveStream)
// Not under gStateMux because both writers are on commsTask (BLE callbacks) and
// the reader is also commsTask (bleSendLiveStream). Single-core access, no race.
extern volatile bool diagActive;
extern volatile uint8_t diagActionResult;
extern volatile uint8_t diagI2cScanResult;
extern volatile uint8_t diagPalmWhoAmI;
extern volatile uint8_t diagWristWhoAmI;
