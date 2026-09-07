#include "motor.h"
#include "config.h"
#include <Arduino.h>

// LEDC PWM for vibration motor on PIN_MOTOR (GPIO32 via 2N2222).
// ESP32 Arduino core 3.x uses pin-based API (ledcAttach/ledcWrite by pin),
// not the old channel-based ledcSetup/ledcAttachPin pair.
static const uint32_t kMotorPwmFreqHz  = 5000;   // 5 kHz — silent, smooth
static const uint8_t  kMotorPwmResBits = 8;      // 0–255 duty

static uint8_t _dutyOn = 255;                    // default: full strength

void motorInit() {
  ledcAttach(PIN_MOTOR, kMotorPwmFreqHz, kMotorPwmResBits);
  ledcWrite(PIN_MOTOR, 0);
}

void motorStop() {
  ledcWrite(PIN_MOTOR, 0);
}

void motorPulse(uint32_t durationMs) {
  ledcWrite(PIN_MOTOR, _dutyOn);
  vTaskDelay(pdMS_TO_TICKS(durationMs));
  ledcWrite(PIN_MOTOR, 0);
}

void motorPattern(uint32_t onMs, uint32_t offMs, int reps) {
  for (int i = 0; i < reps; i++) {
    ledcWrite(PIN_MOTOR, _dutyOn);
    vTaskDelay(pdMS_TO_TICKS(onMs));
    ledcWrite(PIN_MOTOR, 0);
    if (i < reps - 1) vTaskDelay(pdMS_TO_TICKS(offMs));
  }
}

void motorMetronomeTick() {
  motorPulse(MOTOR_METRONOME_MS);
}

void motorSetIntensity(uint8_t pct) {
  if (pct > 100) pct = 100;
  _dutyOn = (uint8_t)((uint16_t)pct * 255 / 100);
}