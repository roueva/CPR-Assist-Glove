#pragma once
// =============================================================================
// tca.h — TCA9548A I²C Multiplexer
// =============================================================================
#include <Wire.h>
#include "config.h"

// Select a single TCA channel (0–7). Disables all others.
inline bool tcaSelect(uint8_t ch) {
  if (ch > 7) return false;
  Wire.beginTransmission(TCA_ADDRESS);
  Wire.write(1 << ch);
  uint8_t err = Wire.endTransmission();
  delayMicroseconds(300);
  return (err == 0);
}

// Disable all TCA channels
inline void tcaDisable() {
  Wire.beginTransmission(TCA_ADDRESS);
  Wire.write(0x00);
  Wire.endTransmission();
  delayMicroseconds(300);
}

// Ping a specific device on a channel. Returns true if device ACKs.
inline bool tcaPing(uint8_t ch, uint8_t deviceAddr) {
  tcaSelect(ch);
  Wire.beginTransmission(deviceAddr);
  return (Wire.endTransmission() == 0);
}
