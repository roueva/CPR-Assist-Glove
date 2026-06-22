// =============================================================================
// battery.cpp
// =============================================================================
#include "battery.h"
#include <Arduino.h>

static uint8_t _pct = 100;
static bool _charging = false;
static float _voltage = 4.2f;

void batteryInit() {
  pinMode(PIN_CHARGE_DETECT, INPUT);
  batteryUpdate();
}

void batteryUpdate() {
  // Average 16 ADC samples to reduce noise
  uint32_t sum = 0;
  for (int i = 0; i < 16; i++) {
    sum += analogRead(PIN_BAT_ADC);
    delay(1);
  }
  float adc = sum / 16.0f;

  // Vbat = ADC_reading × (3.3 / 4095) × BAT_ADC_DIVIDER
  _voltage = adc * (3.3f / 4095.0f) * BAT_ADC_DIVIDER;
  _charging = (digitalRead(PIN_CHARGE_DETECT) == HIGH);

  // Map voltage to percentage
  float pct = (_voltage - BAT_VOLTAGE_MIN) / (BAT_VOLTAGE_MAX - BAT_VOLTAGE_MIN) * 100.0f;
  _pct = (uint8_t)constrain(pct, 0.0f, 100.0f);
}

uint8_t batteryPercent() {
  return _pct;
}
bool batteryCharging() {
  return _charging;
}
float batteryVoltage() {
  return _voltage;
}
