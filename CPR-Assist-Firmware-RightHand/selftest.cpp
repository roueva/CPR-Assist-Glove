// =============================================================================
// selftest.cpp — Sensor self-test (Spec §6.5 / SELFTEST_RESULT) — RIGHT-HAND
// VARIANT (no TCA9548A — every device sits directly on the I²C bus).
//
// Design: actively re-probe each device over I²C (do NOT trust the static
// _ok flags set at boot — they don't reflect "now"). If a sensor's static
// flag is false, attempt one re-init before failing.
//
// The patient channel (MAX30102 patient + MAX30205) is not populated on
// this board. Their probes report NOT_PRESENT without touching the bus at
// all — MAX30205_ADDR (0x48) and MAX30102_ADDR (0x57) are the same
// addresses TMP117 and SEN0344 legitimately own here, and with no mux to
// isolate a channel, any probe traffic to those addresses under the old
// patient-sensor protocol would land on the real TMP117/SEN0344 chips. See
// the do-not-touch note in config.h.
//
// Caller (cpr_glove.ino:runSelftest) must hold gI2CMutex for the whole call.
// This function must only be invoked when no session/pulse/vent window is
// active — a 300–500 ms mutex hold otherwise corrupts depth integration.
// =============================================================================
#include "selftest.h"
#include "imu.h"
#include "force.h"
#include "sen0344.h"
#include "tmp117.h"
#include "audio.h"
#include "config.h"
#include <Wire.h>

// ── Direct-bus helpers (no TCA) ──────────────────────────────────────────────
static bool pingDevice(uint8_t deviceAddr) {
  Wire.beginTransmission(deviceAddr);
  return (Wire.endTransmission() == 0);
}

static uint8_t readReg8(uint8_t deviceAddr, uint8_t reg) {
  Wire.beginTransmission(deviceAddr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return 0xFF;
  Wire.requestFrom(deviceAddr, (uint8_t)1);
  return Wire.available() ? Wire.read() : 0xFF;
}

// ── Per-sensor probes ────────────────────────────────────────────────────────
struct SensorResult {
  uint8_t bit;
  bool pass;
  bool crit;
  uint8_t reason;
};

static SensorResult probeIMU(bool isPalm) {
  const uint8_t bit = isPalm ? SELFTEST_BIT_IMU1 : SELFTEST_BIT_IMU2;
  const uint8_t addr = isPalm ? LSM6DSOX_ADDR_PALM : LSM6DSOX_ADDR_WRIST;

  if (!pingDevice(addr)) {
    return { bit, false, true, SELFTEST_REASON_NO_I2C_ACK };
  }
  uint8_t whoAmI = readReg8(addr, LSM6DSOX_WHO_AM_I);
  if (whoAmI == 0xFF) {
    return { bit, false, true, SELFTEST_REASON_NO_I2C_ACK };
  }
  if (whoAmI != 0x6C) {
    return { bit, false, true, SELFTEST_REASON_WRONG_ID };
  }
  bool moduleOk = isPalm ? imuPalmOk() : imuWristOk();
  if (!moduleOk) {
    return { bit, false, true, SELFTEST_REASON_BAD_READING };
  }
  return { bit, true, false, SELFTEST_REASON_OK };
}

static SensorResult probeForce() {
  if (!forceBaselineReady()) {
    // Try to reinit baseline — user may have stilled the glove now.
    for (int i = 0; i < 50 && !forceBaselineReady(); i++) {
      forceInit();
      delay(10);
    }
    if (!forceBaselineReady()) {
      return { SELFTEST_BIT_FORCE, false, true, SELFTEST_REASON_BASELINE_FAIL };
    }
  }
  // Take 5 samples (50 ms total) and check the minimum. The force sensor
  // is on its own ADC, not I²C — but forceRead() applies a median filter so
  // a single bad sample doesn't fail us.
  float minF = 1e6f;
  for (int i = 0; i < 5; i++) {
    float f = forceRead();
    if (f < minF) minF = f;
    delay(10);
  }
  if (minF >= -2.0f && minF < 50.0f) {
    return { SELFTEST_BIT_FORCE, true, false, SELFTEST_REASON_OK };
  }
  return { SELFTEST_BIT_FORCE, false, true, SELFTEST_REASON_BAD_READING };
}

static SensorResult probeSEN0344() {
  if (!pingDevice(SEN0344_I2C_ADDR)) {
    return { SELFTEST_BIT_MAX_R, false, false, SELFTEST_REASON_NO_I2C_ACK };
  }
  if (!sen0344Ok()) {
    sen0344Init();  // retry — maybe the sensor was reseated / just powered up
    if (!sen0344Ok()) {
      return { SELFTEST_BIT_MAX_R, false, false, SELFTEST_REASON_BAD_READING };
    }
  }
  return { SELFTEST_BIT_MAX_R, true, false, SELFTEST_REASON_OK };
}

static SensorResult probeTMP117() {
  if (!pingDevice(TMP117_I2C_ADDR)) {
    return { SELFTEST_BIT_HUMIDITY, false, false, SELFTEST_REASON_NO_I2C_ACK };
  }
  if (!tmp117Ok()) {
    tmp117Init();  // retry in case sensor was reseated
    if (!tmp117Ok()) {
      return { SELFTEST_BIT_HUMIDITY, false, false, SELFTEST_REASON_NO_I2C_ACK };
    }
  }
  float t = 0.0f;
  if (tmp117ReadCelsius(t) && t >= 10.0f && t <= 50.0f) {
    return { SELFTEST_BIT_HUMIDITY, true, false, SELFTEST_REASON_OK };
  }
  return { SELFTEST_BIT_HUMIDITY, false, false, SELFTEST_REASON_BAD_READING };
}

// Patient channel — not populated on this board. Report NOT_PRESENT without
// any bus I/O (see file header note on the 0x48 / 0x57 address collision).
static SensorResult probeMAX30102PatientAbsent() {
  return { SELFTEST_BIT_MAX_P, false, false, SELFTEST_REASON_NOT_PRESENT };
}
static SensorResult probeMAX30205Absent() {
  return { SELFTEST_BIT_TEMP, false, false, SELFTEST_REASON_NOT_PRESENT };
}

static SensorResult probeAudio() {
  // DFPlayer is on UART, not I²C. audioOk() returns the boot-time flag; we
  // don't have a generic "ping" frame, so we trust the flag. (Real audio
  // playback test lives in the diagnostic panel's "Play audio" action.)
  if (audioOk()) {
    return { SELFTEST_BIT_AUDIO, true, false, SELFTEST_REASON_OK };
  }
  return { SELFTEST_BIT_AUDIO, false, false, SELFTEST_REASON_NO_UART_REPLY };
}

// ── Public API ───────────────────────────────────────────────────────────────
SelfTestResult selftestRun(uint8_t battPct) {
  SelfTestResult r;
  memset(&r, 0, sizeof(r));
  r.batteryPct = battPct;

  r.i2cScanMask = selftestI2CScan();
  r.palmWhoAmI = imuReadWhoAmI(LSM6DSOX_ADDR_PALM);
  r.wristWhoAmI = imuReadWhoAmI(LSM6DSOX_ADDR_WRIST);

  // Bit index in reasonCodes[] matches the bit position in
  // passMask/warnMask/criticalMask. Sensors 0–2 are critical, 3–7 are warn.
  SensorResult sensors[] = {
    probeIMU(true),                  // [0] IMU palm             — critical
    probeIMU(false),                 // [1] IMU wrist            — critical
    probeForce(),                    // [2] Force                — critical
    probeMAX30102PatientAbsent(),    // [3] patient HR/SpO2      — warn, not present
    probeSEN0344(),                  // [4] SEN0344 rescuer HR/SpO2 — warn
    probeMAX30205Absent(),           // [5] patient temp         — warn, not present
    probeTMP117(),                   // [6] TMP117 rescuer temp  — warn
    probeAudio(),                    // [7] DFPlayer audio       — warn
  };
  for (int i = 0; i < 8; i++) {
    const SensorResult& s = sensors[i];
    if (s.pass) {
      r.passMask |= s.bit;
    } else if (i < 3) {
      r.criticalMask |= s.bit;
    } else {
      r.warnMask |= s.bit;
    }
    r.reasonCodes[i] = s.reason;
  }

  return r;
}

// ── I²C scan ─────────────────────────────────────────────────────────────────
// Probes each direct-bus address. Returns a bitmask: bit N = 1 if a device
// responded. bits4-5 always 0 (no patient sensors on this board).
uint8_t selftestI2CScan() {
  const uint8_t addrs[] = {
    LSM6DSOX_ADDR_PALM, LSM6DSOX_ADDR_WRIST, SEN0344_I2C_ADDR, TMP117_I2C_ADDR
  };
  uint8_t result = 0;
  for (int i = 0; i < 4; i++) {
    if (pingDevice(addrs[i])) result |= (1 << i);
  }
  return result;
}
