#pragma once
#include <Arduino.h>
// =============================================================================
// selftest.h — Sensor self-test, builds pass/warn/critical masks
// =============================================================================
#include "config.h"

// Reason codes for SelfTestResult.reasonCodes[i] (i = same bit index as masks)
#define SELFTEST_REASON_OK 0x00
#define SELFTEST_REASON_NO_I2C_ACK 0x01     // device address didn't ACK
#define SELFTEST_REASON_TCA_FAIL 0x02       // TCA9548A itself didn't respond / channel switch failed
#define SELFTEST_REASON_WRONG_ID 0x03       // chip responded but WHO_AM_I/PART_ID is wrong
#define SELFTEST_REASON_BAD_READING 0x04    // reading is implausible (e.g. force > 50N at rest)
#define SELFTEST_REASON_BASELINE_FAIL 0x05  // calibration baseline never converged
#define SELFTEST_REASON_NO_UART_REPLY 0x06  // DFPlayer didn't acknowledge UART frame
#define SELFTEST_REASON_MUTEX_TIMEOUT 0x07  // sensorTask didn't release I²C mutex in time
#define SELFTEST_REASON_NOT_TESTED 0xFF     // skipped (e.g. audio: needs user confirm)

struct SelfTestResult {
  uint8_t passMask;
  uint8_t warnMask;
  uint8_t criticalMask;
  uint8_t batteryPct;
  uint8_t i2cScanMask;     // bit N = device responded on TCA channel N (0–5)
  uint8_t palmWhoAmI;      // 0x6C = correct, 0x00 = no ACK, 0xFF = bus error
  uint8_t wristWhoAmI;     // same encoding
  uint8_t reasonCodes[8];  // one byte per sensor bit (parallel to passMask), see codes below
};

SelfTestResult selftestRun(uint8_t battPct);

uint8_t selftestI2CScan();
