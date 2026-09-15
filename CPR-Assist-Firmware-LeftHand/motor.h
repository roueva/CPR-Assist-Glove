#pragma once
#include <Arduino.h>
// =============================================================================
// motor.h — Vibration motor patterns (GPIO32, PWM via 2N2222)
// =============================================================================
#include "config.h"

void motorInit();
void motorPulse(uint32_t durationMs);                        // single pulse
void motorPattern(uint32_t onMs, uint32_t offMs, int reps);  // repeating pattern
void motorMetronomeTick();                                   // 80ms burst for rate guidance
void motorStop();
void motorSetIntensity(uint8_t pct);  // 0–100, sets PWM duty for all subsequent pulses
