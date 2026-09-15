#pragma once
// =============================================================================
// max30205.h — MAX30205 patient skin temperature (I²C, TCA channel 2)
// =============================================================================
#include "config.h"

bool max30205Init();
bool max30205ReadCelsius(float& out);  // false if not ready or out of range
bool max30205Ok();
