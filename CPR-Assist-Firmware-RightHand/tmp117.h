#pragma once
// =============================================================================
// tmp117.h — TI TMP117 rescuer temperature (I²C, direct bus — no TCA)
// Replaces GXHT30 on this board. No humidity output.
// =============================================================================
#include "config.h"

bool tmp117Init();
bool tmp117Ok();
bool tmp117ReadCelsius(float& out);
