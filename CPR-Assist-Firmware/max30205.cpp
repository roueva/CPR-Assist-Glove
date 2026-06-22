// =============================================================================
// max30205.cpp — MAX30205 Human Body Temperature Sensor
// I²C address 0x48, 16-bit two's complement, LSB = 0.00390625°C
// =============================================================================
#include "max30205.h"
#include "tca.h"
#include <Wire.h>

#define MAX30205_REG_TEMP 0x00
#define MAX30205_REG_CONFIG 0x01

static bool _ok = false;

bool max30205Init() {
  tcaSelect(TCA_CH_MAX30205);
  delay(20);

  // Ping the device
  Wire.beginTransmission(MAX30205_ADDR);
  if (Wire.endTransmission() != 0) {
    _ok = false;
    return false;
  }

  // Write config: continuous conversion, comparator mode, OS active high
  Wire.beginTransmission(MAX30205_ADDR);
  Wire.write(MAX30205_REG_CONFIG);
  Wire.write(0x00);  // normal mode, continuous conversion
  if (Wire.endTransmission() != 0) {
    _ok = false;
    return false;
  }

  _ok = true;
  return true;
}

bool max30205Ok() {
  return _ok;
}

float max30205ReadCelsius() {
  if (!_ok) return 0.0f;

  tcaSelect(TCA_CH_MAX30205);

  Wire.beginTransmission(MAX30205_ADDR);
  Wire.write(MAX30205_REG_TEMP);
  if (Wire.endTransmission(false) != 0) return 0.0f;

  Wire.requestFrom((uint8_t)MAX30205_ADDR, (uint8_t)2);
  if (Wire.available() < 2) return 0.0f;

  uint8_t msb = Wire.read();
  uint8_t lsb = Wire.read();
  int16_t raw = (int16_t)((msb << 8) | lsb);
  float temp = raw * 0.00390625f;

  // Sanity check: human skin 25–42°C
  if (temp < 15.0f || temp > 42.0f) return 0.0f;
  return temp;
}
