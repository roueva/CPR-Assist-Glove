#pragma once
// =============================================================================
// max30205.h — MAX30205 patient skin temperature (I²C, TCA channel 2)
// =============================================================================
#include "config.h"

bool max30205Init();
float max30205ReadCelsius();  // returns 0 if not ready or out of range
bool max30205Ok();
