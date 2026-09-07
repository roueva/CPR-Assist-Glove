// =============================================================================
// tmp117.cpp — TI TMP117 High-Accuracy Digital Temperature Sensor
// I²C address 0x48 (ADD0 strapped to GND), 16-bit two's complement,
// LSB = 0.0078125°C. Register map: TEMP_RESULT=0x00, DEVICE_ID=0x0F
// (TI datasheet Table 3; DEVICE_ID reset value 0x0117).
//
// Runs its default continuous-conversion mode from power-on with no
// configuration write needed — same minimal-driver style as max30205.cpp.
// Before the first conversion completes (~1 s after power-on with default
// averaging), TEMP_RESULT reads its POR default, which the sanity check
// below rejects.
// =============================================================================
#include "tmp117.h"
#include <Wire.h>

static bool _ok = false;

bool tmp117Init() {
  Wire.beginTransmission(TMP117_I2C_ADDR);
  Wire.write(TMP117_REG_DEVICE_ID);
  if (Wire.endTransmission(false) != 0) {
    _ok = false;
    return false;
  }

  Wire.requestFrom((uint8_t)TMP117_I2C_ADDR, (uint8_t)2);
  if (Wire.available() < 2) {
    _ok = false;
    return false;
  }
  uint8_t msb = Wire.read();
  uint8_t lsb = Wire.read();
  uint16_t deviceId = ((uint16_t)msb << 8) | lsb;

  _ok = (deviceId == TMP117_DEVICE_ID_VALUE);
  return _ok;
}

bool tmp117Ok() {
  return _ok;
}

bool tmp117ReadCelsius(float& out) {
  if (!_ok) return false;

  Wire.beginTransmission(TMP117_I2C_ADDR);
  Wire.write(TMP117_REG_TEMP_RESULT);
  if (Wire.endTransmission(false) != 0) return false;

  Wire.requestFrom((uint8_t)TMP117_I2C_ADDR, (uint8_t)2);
  if (Wire.available() < 2) return false;

  uint8_t msb = Wire.read();
  uint8_t lsb = Wire.read();
  int16_t raw = (int16_t)((msb << 8) | lsb);
  float temp = raw * TMP117_RESOLUTION;

  // Sanity check: human skin/wrist 15–42°C — also filters the POR default
  // (0x8000) before the first conversion completes.
  if (temp < 15.0f || temp > 42.0f) return false;
  out = temp;
  return true;
}
