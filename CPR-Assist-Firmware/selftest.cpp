// =============================================================================
// selftest.cpp — Sensor self-test (Spec §6.5 / SELFTEST_RESULT)
//
// Design: actively re-probe each device over I²C (do NOT trust the static
// _ok flags set at boot — they don't reflect "now"). If a sensor's static
// flag is false, attempt one re-init before failing. Always leave the TCA
// in an all-deselected state on exit so the next bus user starts clean.
//
// Caller (cpr_glove.ino:runSelftest) must hold gI2CMutex for the whole call.
// This function must only be invoked when no session/pulse/vent window is
// active — a 300–500 ms mutex hold otherwise corrupts depth integration.
// =============================================================================
#include "selftest.h"
#include "imu.h"
#include "force.h"
#include "max30102.h"
#include "max30205.h"
#include "gxht30.h"
#include "audio.h"
#include "tca.h"
#include "config.h"
#include <Wire.h>

// MAX30102 PART_ID register and expected value (per datasheet)
#define MAX30102_REG_PART_ID 0xFF
#define MAX30102_PART_ID_VAL 0x15

// ── TCA helpers ──────────────────────────────────────────────────────────────
// Verifies the TCA9548A itself is alive on the bus. Returns true if the chip
// ACKs its address. This is the first check — if it fails, nothing else can
// work and we report TCA_FAIL for every sensor.
static bool probeTCA() {
  Wire.beginTransmission(TCA_ADDRESS);
  uint8_t err = Wire.endTransmission();
  return (err == 0);
}

// Pings a device on a TCA channel. Switches channel, waits for settle,
// then sends a zero-byte transaction to deviceAddr. Returns true on ACK.
static bool pingDevice(uint8_t channel, uint8_t deviceAddr) {
  if (!tcaSelect(channel)) return false;  // tcaSelect already adds 300 µs
  Wire.beginTransmission(deviceAddr);
  return (Wire.endTransmission() == 0);
}

// Reads one register from a device on a TCA channel. Returns 0xFF on bus
// error (caller can distinguish from a legitimate 0xFF by also calling
// pingDevice first).
static uint8_t readReg(uint8_t channel, uint8_t deviceAddr, uint8_t reg) {
  if (!tcaSelect(channel)) return 0xFF;
  Wire.beginTransmission(deviceAddr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return 0xFF;
  Wire.requestFrom(deviceAddr, (uint8_t)1);
  return Wire.available() ? Wire.read() : 0xFF;
}

// ── Per-sensor probes ────────────────────────────────────────────────────────
// Each returns (passBit, warnBit, criticalBit, reasonCode) packed in a
// SensorResult struct. The caller OR's bits into the SelfTestResult.

struct SensorResult {
  uint8_t bit;
  bool pass;
  bool crit;
  uint8_t reason;
};

static SensorResult probeIMU(bool isPalm) {
  const uint8_t bit = isPalm ? SELFTEST_BIT_IMU1 : SELFTEST_BIT_IMU2;
  const uint8_t ch = isPalm ? TCA_CH_IMU_PALM : TCA_CH_IMU_WRIST;
  const uint8_t addr = isPalm ? LSM6DSOX_ADDR_PALM : LSM6DSOX_ADDR_WRIST;

  // 1. Can we even select the channel?
  if (!tcaSelect(ch)) {
    return { bit, false, true, SELFTEST_REASON_TCA_FAIL };
  }
  // 2. Does the device ACK?
  if (!pingDevice(ch, addr)) {
    return { bit, false, true, SELFTEST_REASON_NO_I2C_ACK };
  }
  // 3. Is it the right chip?
  uint8_t whoAmI = readReg(ch, addr, LSM6DSOX_WHO_AM_I);
  if (whoAmI == 0xFF) {
    return { bit, false, true, SELFTEST_REASON_NO_I2C_ACK };
  }
  if (whoAmI != 0x6C) {
    return { bit, false, true, SELFTEST_REASON_WRONG_ID };
  }
  // 4. Does the firmware's IMU module also think it's healthy?
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
  // is on its own ADC, no TCA involvement — but forceRead() applies a
  // median filter so a single bad sample doesn't fail us.
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

static SensorResult probeMAX30102(bool isPatient) {
  const uint8_t bit = isPatient ? SELFTEST_BIT_MAX_P : SELFTEST_BIT_MAX_R;
  const uint8_t ch = isPatient ? TCA_CH_MAX30102_P : TCA_CH_MAX30102_R;
  if (!tcaSelect(ch)) {
    return { bit, false, false, SELFTEST_REASON_TCA_FAIL };
  }
  if (!pingDevice(ch, MAX30102_ADDR)) {
    // Try one reinit — maybe the sensor was reseated.
    max30102Init();
    if (!pingDevice(ch, MAX30102_ADDR)) {
      return { bit, false, false, SELFTEST_REASON_NO_I2C_ACK };
    }
  }
  // Verify chip ID — catches "wrong device at this address" (e.g. an
  // EEPROM at 0x57 instead of the MAX30102).
  uint8_t partId = readReg(ch, MAX30102_ADDR, MAX30102_REG_PART_ID);
  if (partId != MAX30102_PART_ID_VAL) {
    return { bit, false, false, SELFTEST_REASON_WRONG_ID };
  }
  return { bit, true, false, SELFTEST_REASON_OK };
}

static SensorResult probeMAX30205() {
  if (!tcaSelect(TCA_CH_MAX30205)) {
    return { SELFTEST_BIT_TEMP, false, false, SELFTEST_REASON_TCA_FAIL };
  }
  if (!pingDevice(TCA_CH_MAX30205, MAX30205_ADDR)) {
    max30205Init();  // retry init in case sensor was reseated
    if (!pingDevice(TCA_CH_MAX30205, MAX30205_ADDR)) {
      return { SELFTEST_BIT_TEMP, false, false, SELFTEST_REASON_NO_I2C_ACK };
    }
  }
  // Read a real temperature — distinguishes "ACK but no conversion" from
  // a fully working sensor.
  float t = max30205ReadCelsius();
  if (t >= 10.0f && t <= 50.0f) {
    return { SELFTEST_BIT_TEMP, true, false, SELFTEST_REASON_OK };
  }
  return { SELFTEST_BIT_TEMP, false, false, SELFTEST_REASON_BAD_READING };
}

static SensorResult probeGXHT30() {
  if (!tcaSelect(TCA_CH_GXHT30)) {
    return { SELFTEST_BIT_HUMIDITY, false, false, SELFTEST_REASON_TCA_FAIL };
  }
  if (!pingDevice(TCA_CH_GXHT30, GXHT30_ADDR)) {
    gxht30Init();  // retry init in case sensor was reseated
    if (!pingDevice(TCA_CH_GXHT30, GXHT30_ADDR)) {
      return { SELFTEST_BIT_HUMIDITY, false, false, SELFTEST_REASON_NO_I2C_ACK };
    }
  }
  float t, h;
  if (gxht30Read(t, h)) {
    return { SELFTEST_BIT_HUMIDITY, true, false, SELFTEST_REASON_OK };
  }
  return { SELFTEST_BIT_HUMIDITY, false, false, SELFTEST_REASON_BAD_READING };
}

static SensorResult probeAudio() {
  // DFPlayer is on UART, not I²C — no TCA / mutex involvement. audioOk()
  // returns the boot-time flag; we don't have a generic "ping" frame, so
  // we trust the flag. (Real audio playback test lives in the diagnostic
  // panel's "Play audio" action — that's user-confirmed.)
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

  // Step 1: probe the TCA itself. If it's dead, everything downstream is
  // unreachable — short-circuit and report TCA_FAIL for all six I²C bits.
  if (!probeTCA()) {
    const uint8_t i2cBits = SELFTEST_BIT_IMU1 | SELFTEST_BIT_IMU2
                            | SELFTEST_BIT_MAX_P | SELFTEST_BIT_MAX_R
                            | SELFTEST_BIT_TEMP | SELFTEST_BIT_HUMIDITY;
    r.criticalMask |= (SELFTEST_BIT_IMU1 | SELFTEST_BIT_IMU2);  // IMUs critical
    r.warnMask |= (SELFTEST_BIT_MAX_P | SELFTEST_BIT_MAX_R
                   | SELFTEST_BIT_TEMP | SELFTEST_BIT_HUMIDITY);
    r.i2cScanMask = 0;
    for (int i = 0; i < 6; i++) r.reasonCodes[i] = SELFTEST_REASON_TCA_FAIL;
    // Force + audio are NOT on the TCA — test them independently.
    SensorResult force = probeForce();
    if (force.pass) r.passMask |= force.bit;
    else r.criticalMask |= force.bit;
    r.reasonCodes[2] = force.reason;
    SensorResult audio = probeAudio();
    if (audio.pass) r.passMask |= audio.bit;
    else r.warnMask |= audio.bit;
    r.reasonCodes[7] = audio.reason;
    return r;
  }

  // Step 2: I²C scan (informational, populates r.i2cScanMask)
  r.i2cScanMask = selftestI2CScan();
  r.palmWhoAmI = imuReadWhoAmI(TCA_CH_IMU_PALM, LSM6DSOX_ADDR_PALM);
  r.wristWhoAmI = imuReadWhoAmI(TCA_CH_IMU_WRIST, LSM6DSOX_ADDR_WRIST);

  // Step 3: per-sensor probes. Bit index in reasonCodes[] matches the
  // bit position in passMask/warnMask/criticalMask.
  SensorResult sensors[] = {
    probeIMU(true),        // [0] IMU palm        — critical
    probeIMU(false),       // [1] IMU wrist       — critical
    probeForce(),          // [2] Force           — critical
    probeMAX30102(true),   // [3] MAX30102 patient — warn
    probeMAX30102(false),  // [4] MAX30102 rescuer — warn
    probeMAX30205(),       // [5] MAX30205 patient temp — warn
    probeGXHT30(),         // [6] GXHT30 rescuer T+H — warn
    probeAudio(),          // [7] DFPlayer audio  — warn
  };
  // Sensors 0–2 are critical, 3–7 are warn-level.
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

  // Step 4: defensive TCA deselect. If any of the above left a channel
  // selected (e.g. probeGXHT30 left CH3 selected), the next user of the
  // bus would land on whatever device sits there. Force a known-good
  // all-deselected state.
  tcaDisable();

  return r;
}

// ── I²C scan ─────────────────────────────────────────────────────────────────
// Probes each TCA channel for the expected device. Returns a bitmask:
// bit N = 1 if a device responded on channel N (0–5).
// Uses tcaSelect() helper (which adds the 300 µs settle) instead of raw
// Wire transactions, so we benefit from any future fixes to channel
// switching. Always leaves the TCA all-deselected.
uint8_t selftestI2CScan() {
  const uint8_t channels[] = {
    TCA_CH_IMU_PALM, TCA_CH_IMU_WRIST, TCA_CH_MAX30205,
    TCA_CH_GXHT30, TCA_CH_MAX30102_R, TCA_CH_MAX30102_P
  };
  const uint8_t expectedAddr[] = {
    LSM6DSOX_ADDR_PALM, LSM6DSOX_ADDR_WRIST, MAX30205_ADDR,
    GXHT30_ADDR, MAX30102_ADDR, MAX30102_ADDR
  };
  uint8_t result = 0;
  for (int i = 0; i < 6; i++) {
    if (!tcaSelect(channels[i])) continue;  // TCA write failed → skip
    Wire.beginTransmission(expectedAddr[i]);
    if (Wire.endTransmission() == 0) result |= (1 << i);
    delayMicroseconds(50);
  }
  tcaDisable();
  return result;
}