#pragma once
// =============================================================================
// neopixel.h — WS2812B LED strip (8 LEDs, GPIO18)
// LEDs 0–5: depth bar
// LED 6:    rate indicator
// LED 7:    status / mode
// =============================================================================
#include "config.h"
#include "shared_state.h"

void neoInit();
// Main update — call every NEO_UPDATE_INTERVAL_MS from comms task
void neoUpdate(const SharedState& s);

// One-shot event animations (called from session/mode logic)
void neoSessionStart();
void neoSessionEnd();
void neoModeChange(GloveMode mode);
void neoScenarioChange(Scenario sc);
void neoSelftestAnimation();
void neoSetBrightness(uint8_t brightness);  // 0–255
uint8_t neoGetBrightness();
void neoDiagLedTest();
