// =============================================================================
// button.cpp — Button gesture FSM
// Active LOW button on GPIO27 with 10kΩ pull-up.
// States: IDLE → PRESSED → released (count taps or detect hold)
// =============================================================================
#include "button.h"
#include <Arduino.h>

enum class BtnState { IDLE,
                      PRESSED,
                      WAIT_NEXT_TAP };

static BtnState _state = BtnState::IDLE;
static unsigned long _pressStartMs = 0;
static unsigned long _lastReleaseMs = 0;
static int _tapCount = 0;
static bool _longFired = false;

void buttonInit() {
  pinMode(PIN_BUTTON, INPUT_PULLUP);
}

ButtonEvent buttonUpdate() {
  bool pressed = (digitalRead(PIN_BUTTON) == LOW);
  unsigned long now = millis();

  switch (_state) {

    case BtnState::IDLE:
      if (pressed) {
        // Debounce: wait BTN_DEBOUNCE_MS before accepting
        delay(BTN_DEBOUNCE_MS);
        if (digitalRead(PIN_BUTTON) == LOW) {
          _state = BtnState::PRESSED;
          _pressStartMs = millis();
          _longFired = false;
        }
      }
      break;

    case BtnState::PRESSED:
      if (!pressed) {
        // Released — this counts as a tap
        _tapCount++;
        _lastReleaseMs = now;
        _state = BtnState::WAIT_NEXT_TAP;
      } else {
        // Still held — check for long press
        if (!_longFired && (now - _pressStartMs) >= BTN_LONG_PRESS_MS) {
          _longFired = true;
          _tapCount = 0;
          _state = BtnState::IDLE;
          return ButtonEvent::LongPress;
        }
      }
      break;

    case BtnState::WAIT_NEXT_TAP:
      if (pressed) {
        // Another tap started within the window
        delay(BTN_DEBOUNCE_MS);
        if (digitalRead(PIN_BUTTON) == LOW) {
          _state = BtnState::PRESSED;
          _pressStartMs = millis();
          _longFired = false;
        }
      } else {
        // No new press — check if window has expired
        unsigned long window = (_tapCount >= 2)
                                 ? BTN_TRIPLE_TAP_WINDOW_MS
                                 : BTN_DOUBLE_TAP_WINDOW_MS;

        if ((now - _lastReleaseMs) >= window) {
          // Window expired — resolve what we have
          int taps = _tapCount;
          _tapCount = 0;
          _state = BtnState::IDLE;

          if (taps == 2) return ButtonEvent::DoubleTap;
          if (taps >= 3) return ButtonEvent::TripleTap;
          // Single tap: ignore (single tap has no assigned action)
        }
      }
      break;
  }

  return ButtonEvent::None;
}
