#pragma once
#include <Arduino.h>
// =============================================================================
// battery.h — Battery voltage ADC + charging detection
// =============================================================================
#include "config.h"

void batteryInit();
void batteryUpdate();      // call every ~1s from comms task
uint8_t batteryPercent();  // 0–100
bool batteryCharging();
float batteryVoltage();
