#pragma once
// =============================================================================
// button.h — Single button gesture detection
// Gestures:
//   Long press (2s hold) → start/stop session
//   Double-tap           → cycle mode
//   Triple-tap           → cycle scenario
// =============================================================================
#include "config.h"

enum class ButtonEvent {
  None,
  LongPress,  // 2s hold → start/stop
  DoubleTap,  // cycle mode
  TripleTap   // cycle scenario
};

void buttonInit();
ButtonEvent buttonUpdate();  // call every 10ms from comms task; returns event or None
