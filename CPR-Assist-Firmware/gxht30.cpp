// =============================================================================
// gxht30.cpp — GXHT30 Temperature + Humidity Sensor
// Uses SHT3x single-shot high-repeatability command (0x2C 0x06).
// 6-byte response: temp MSB, temp LSB, CRC, hum MSB, hum LSB, CRC
// =============================================================================
#include <Arduino.h>
#include "gxht30.h"
#include "tca.h"
#include <Wire.h>

static bool _ok = false;

// CRC-8 check per SHT3x datasheet (polynomial 0x31, init 0xFF)
static uint8_t crc8(uint8_t* data, int len) {
  uint8_t crc = 0xFF;
  for (int i = 0; i < len; i++) {
    crc ^= data[i];
    for (int b = 0; b < 8; b++)
      crc = (crc & 0x80) ? (crc << 1) ^ 0x31 : (crc << 1);
  }
  return crc;
}

bool gxht30Init() {
  tcaSelect(TCA_CH_GXHT30);
  delay(20);

  // Soft reset command
  Wire.beginTransmission(GXHT30_ADDR);
  Wire.write(0x30);
  Wire.write(0xA2);
  if (Wire.endTransmission() != 0) {
    _ok = false;
    return false;
  }
  delay(20);

  // Try a measurement to confirm it's alive
  float t, h;
  _ok = true;
  if (!gxht30Read(t, h)) {
    _ok = false;
    return false;
  }
  return true;
}

bool gxht30Ok() {
  return _ok;
}

bool gxht30Read(float& tempC, float& humidityPct) {
  if (!_ok) return false;

  tcaSelect(TCA_CH_GXHT30);

  // Single-shot, high repeatability
  Wire.beginTransmission(GXHT30_ADDR);
  Wire.write(0x2C);
  Wire.write(0x06);
  if (Wire.endTransmission() != 0) return false;
  delay(20);  // measurement time

  Wire.requestFrom((uint8_t)GXHT30_ADDR, (uint8_t)6);
  if (Wire.available() < 6) return false;

  uint8_t buf[6];
  for (int i = 0; i < 6; i++) buf[i] = Wire.read();

  // CRC check
  if (crc8(buf, 2) != buf[2] || crc8(buf + 3, 2) != buf[5]) return false;

  uint16_t rawT = (buf[0] << 8) | buf[1];
  uint16_t rawH = (buf[3] << 8) | buf[4];

  tempC = -45.0f + 175.0f * rawT / 65535.0f;
  humidityPct = 100.0f * rawH / 65535.0f;

  // Sanity: rescuer wrist temp 15–42°C, humidity 0–100%
  if (tempC < 15.0f || tempC > 42.0f) return false;
  humidityPct = constrain(humidityPct, 0.0f, 100.0f);
  return true;
}
