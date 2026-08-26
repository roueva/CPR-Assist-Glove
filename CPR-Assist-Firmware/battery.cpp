// =============================================================================
// battery.cpp
// =============================================================================
#include "battery.h"
#include <Arduino.h>

static uint8_t _pct = 100;
static bool _charging = false;
static bool _wasCharging = false;
static float _voltage = 4.2f;
static float _pctEma = 100.0f;
static bool _emaInit = false;
static bool _settling = false;
static unsigned long _settleStartMs = 0;

// Piecewise-linear interpolation over BAT_LIPO_CURVE (descending voltage order).
static float batteryCurveLookup(float volts) {
  if (volts >= BAT_LIPO_CURVE[0].volts) return BAT_LIPO_CURVE[0].percent;
  if (volts <= BAT_LIPO_CURVE[BAT_LIPO_CURVE_LEN - 1].volts) {
    return BAT_LIPO_CURVE[BAT_LIPO_CURVE_LEN - 1].percent;
  }
  for (size_t i = 0; i < BAT_LIPO_CURVE_LEN - 1; i++) {
    const BatCurvePoint& hi = BAT_LIPO_CURVE[i];
    const BatCurvePoint& lo = BAT_LIPO_CURVE[i + 1];
    if (volts <= hi.volts && volts >= lo.volts) {
      float t = (volts - lo.volts) / (hi.volts - lo.volts);
      return lo.percent + t * (hi.percent - lo.percent);
    }
  }
  return BAT_LIPO_CURVE[BAT_LIPO_CURVE_LEN - 1].percent;
}

void batteryInit() {
  pinMode(PIN_CHARGE_DETECT, INPUT);
  batteryUpdate();
}

void batteryUpdate() {
  // analogReadMilliVolts() applies the factory eFuse ADC calibration, so it
  // is accurate across the ADC's nonlinear range — unlike a raw analogRead()
  // scaled by an assumed linear 3.3V full scale. It already averages
  // internally; average 4 reads on top for additional noise reduction.
  uint32_t sumMv = 0;
  for (int i = 0; i < 4; i++) {
    sumMv += analogReadMilliVolts(PIN_BAT_ADC);
  }
  float mv = sumMv / 4.0f;

  _voltage = (mv / 1000.0f) * BAT_ADC_DIVIDER;
  _charging = (digitalRead(PIN_CHARGE_DETECT) == HIGH);

  if (_charging) {
    // Charger elevates cell voltage above its resting discharge curve —
    // reporting it would show a false jump. Freeze the last discharge value.
    _wasCharging = true;
    _settling = false;  // charging again cancels any pending settle
    _pct = (uint8_t)constrain(_pctEma, 0.0f, 100.0f);
    return;
  }

  if (_wasCharging) {
    // Just unplugged — the rail is still elevated by surface charge from the
    // charger; don't trust a curve lookup yet.
    _wasCharging = false;
    _settling = true;
    _settleStartMs = millis();
  }

  if (_settling) {
    if (millis() - _settleStartMs < BAT_CHARGE_SETTLE_MS) {
      // Still settling — keep reporting the frozen pre-charge value and
      // discard this read rather than feeding it into the EMA.
      _pct = (uint8_t)constrain(_pctEma, 0.0f, 100.0f);
      return;
    }
    // Settle window elapsed — re-seed from a fresh reading. This resets the
    // monotonic clamp's reference too, since _pctEma (not a separate
    // variable) is what the clamp below compares against.
    _settling = false;
    _pctEma = batteryCurveLookup(_voltage);
    _emaInit = true;
    _pct = (uint8_t)constrain(_pctEma, 0.0f, 100.0f);
    return;
  }

  float rawPct = batteryCurveLookup(_voltage);
  if (!_emaInit) {
    _pctEma = rawPct;
    _emaInit = true;
  } else {
    _pctEma = BAT_PCT_EMA_ALPHA * rawPct + (1.0f - BAT_PCT_EMA_ALPHA) * _pctEma;
  }
  // Never let the reported percentage rise while discharging.
  if (_pctEma > _pct) _pctEma = _pct;

  _pct = (uint8_t)constrain(_pctEma, 0.0f, 100.0f);
}

uint8_t batteryPercent() {
  return _pct;
}
bool batteryCharging() {
  return _charging;
}
