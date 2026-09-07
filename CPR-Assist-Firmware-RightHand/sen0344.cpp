// =============================================================================
// sen0344.cpp — DFRobot SEN0344 rescuer HR/SpO2 driver
// Wraps DFRobot_BloodOxygen_S_I2C (vendor library) — the module runs its own
// MAX30102 signal-processing algorithm onboard and hands back a finished
// HR + SpO2 pair over I²C; there is no raw waveform to read.
// =============================================================================
#include "sen0344.h"
#include <Wire.h>
#include <DFRobot_BloodOxygen_S.h>  // DFRobot_BloodOxygen_S_I2C class lives in this header

static DFRobot_BloodOxygen_S_I2C _sen(&Wire, SEN0344_I2C_ADDR);
static bool _ok = false;

bool sen0344Init() {
  _ok = _sen.begin();
  if (_ok) _sen.sensorStartCollect();
  return _ok;
}

bool sen0344Ok() {
  return _ok;
}

void sen0344Update(float& hrBpm, float& spO2, uint8_t& sigQuality) {
  if (!_ok) {
    hrBpm = spO2 = 0.0f;
    sigQuality = 0;
    return;
  }

  _sen.getHeartbeatSPO2();
  int hr = _sen._sHeartbeatSPO2.Heartbeat;
  int sp = _sen._sHeartbeatSPO2.SPO2;

  // This module has no exposed finger-presence/contact flag (unlike the
  // left-hand board's raw pipeline, which gates on raw IR DC level — see
  // CONTACT_IR_MIN in max30102.cpp). The vendor library's own I2C parsing
  // reports SPO2 as -1 when it has no valid lock (DFRobot_BloodOxygen_S_I2C
  // decodes byte 0 of the read to -1 on an invalid/no-finger sample) — that's
  // the only "no contact" signal this hardware gives us, so HR is gated on
  // SpO2 validity too: a genuine pulse lock should produce both together,
  // while ambient-noise HR without a real pulse is unlikely to also produce
  // a coherent, in-range SpO2 at the same time. Without this, the onboard
  // algorithm can report a plausible-looking but bogus HR (e.g. ~120 BPM)
  // with nothing touching the sensor, since HR alone has no explicit
  // invalid sentinel from the library.
  bool spValid = (sp >= 70 && sp <= 100);
  bool hrValid = spValid && (hr >= 30 && hr <= 180);

  hrBpm = hrValid ? (float)hr : 0.0f;
  spO2 = spValid ? (float)sp : 0.0f;
  // Binary valid/invalid only — this module exposes no true signal-quality
  // metric (see sen0344.h). Good enough for fatigue-HR gating, not a
  // replacement for the raw pipeline's composite SQI.
  sigQuality = hrValid ? 100 : 0;
}
