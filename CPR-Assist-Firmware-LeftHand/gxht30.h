#pragma once
// =============================================================================
// gxht30.h — GXHT30 rescuer temperature + humidity (I²C, TCA channel 3)
// Compatible with SHT30 register protocol.
// =============================================================================
#include "config.h"

bool gxht30Init();
bool gxht30Ok();
bool gxht30Read(float& tempC, float& humidityPct);
