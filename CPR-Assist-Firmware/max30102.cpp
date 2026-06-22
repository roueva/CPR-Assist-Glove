// =============================================================================
// max30102.cpp — Dual MAX30102 HR/SpO2 driver (ADAPTIVE ENGINE)
// -----------------------------------------------------------------------------
// Replaces the old SparkFun checkForBeat() approach with a real signal-
// processing pipeline validated on this exact hardware:
//   raw IR → DC tracker → AC → Butterworth bandpass 0.6-3.5 Hz → envelope
//          → adaptive peak detector → RR buffer → HR / RMSSD / composite SQI
//
// Works at this hardware's actual AC level (~30-300 counts) instead of the
// SparkFun library's assumed >5000 counts.
//
// Public function signatures are UNCHANGED — the rest of the firmware and the
// BLE layer do not need any modification.
// =============================================================================
#include "max30102.h"
#include "tca.h"
#include <Wire.h>
#include <math.h>

#include <MAX30105.h>
#include <spo2_algorithm.h>

static MAX30105 _rescuer;
static MAX30105 _patient;
static bool _rescuerOk = false;
static bool _patientOk = false;

// ── Tunables (validated on bench) ────────────────────────────────────────────
#define CONTACT_IR_MIN 30000   // IR DC below this = sensor not covered
#define PEAK_THRESH_PCT 0.40f  // peak must exceed 40% of envelope
#define ENV_FLOOR 15.0f        // envelope never below this (noise guard)
#define RR_MIN_MS 300          // reject beats < 300 ms apart (>200 BPM)
#define RR_MAX_MS 2000         // reject beats > 2 s apart (<30 BPM)
#define RMSSD_WINDOW_MS 60000UL
#define RMSSD_MIN_INTERVALS 20

// SQI scaling: envScore reaches 1.0 when envelope ≥ DC * this fraction.
// Bench: rescuer good contact env≈250 at DC≈138000 → ratio≈0.0018.
//        patient good contact env≈40  at DC≈130000 → ratio≈0.0003.
// We scale each sensor to its own observed "good" level.
//0.0002
#define ENV_DC_FRAC_R 0.0018f
#define ENV_DC_FRAC_P 0.0002f

// ── Butterworth bandpass 0.6-3.5 Hz @ 100 Hz (2 cascaded biquads) ────────────
static const float BPF_B1[3] = { 0.06745527f, 0.0f, -0.06745527f };
static const float BPF_A1[3] = { 1.0f, -1.91119707f, 0.93254473f };
static const float BPF_B2[3] = { 0.06745527f, 0.0f, -0.06745527f };
static const float BPF_A2[3] = { 1.0f, -1.78284155f, 0.86508946f };

// ── Per-sensor pipeline state ────────────────────────────────────────────────
struct PpgState {
  float dc = 0.0f;
  bool dcInit = false;
  float z1_1 = 0, z1_2 = 0, z2_1 = 0, z2_2 = 0;
  float filtered = 0.0f;
  float envelope = 0.0f;
  float prevF = 0.0f, prevPrevF = 0.0f;
  uint32_t lastBeatMs = 0;

  uint16_t rrBuf[32] = { 0 };
  uint32_t rrTs[32] = { 0 };
  int rrHead = 0;
  int rrCount = 0;

  float hrBpm = 0.0f;
  float rmssdMs = 0.0f;
  uint8_t sqi = 0;

  float dcWin[100] = { 0 };
  int dcWinIdx = 0;
  int dcWinFill = 0;

  uint32_t recentBeat[16] = { 0 };
  int recentHead = 0;

  // SpO2
  uint32_t irBuf[100], redBuf[100];
  int bufFill = 0;
  uint8_t spo2Ticks = 0;
  int32_t spo2Val = 0, hrAlgoVal = 0;
  int8_t spo2Valid = 0, hrAlgoValid = 0;

  // Patient detector counts
  uint8_t detA = 0, detB = 0;
  uint16_t rawPeakCount = 0;  // pre-refractory raw threshold crossings
};

static PpgState _pR;  // rescuer
static PpgState _pP;  // patient

static uint32_t _pSampleClockMs = 0;

// ── Init ─────────────────────────────────────────────────────────────────────
static bool initOne(MAX30105& sensor, uint8_t ch) {
  tcaSelect(ch);
  delay(50);
  if (!sensor.begin(Wire, I2C_SPEED_FAST)) return false;
  sensor.softReset();
  delay(100);
  // LED=0x24 (~7mA), avg=1 (no averaging — keeps AC visible), mode=2 (Red+IR),
  // rate=100Hz, pulseWidth=411 (longest = best SNR), ADC=4096.
  sensor.setup(0x24, 1, 2, 100, 411, 4096);
  return true;
}

bool max30102Init() {
  _rescuerOk = initOne(_rescuer, TCA_CH_MAX30102_R);
  _patientOk = initOne(_patient, TCA_CH_MAX30102_P);
  return _rescuerOk || _patientOk;
}

static void resetState(PpgState& s, bool keepDet) {
  s.dc = 0;
  s.dcInit = false;
  s.z1_1 = s.z1_2 = s.z2_1 = s.z2_2 = 0;
  s.filtered = 0;
  s.envelope = 0;
  s.prevF = 0;
  s.prevPrevF = 0;
  s.lastBeatMs = 0;
  s.rrHead = 0;
  s.rrCount = 0;
  s.hrBpm = 0;
  s.rmssdMs = 0;
  s.sqi = 0;
  s.dcWinIdx = 0;
  s.dcWinFill = 0;
  s.recentHead = 0;
  s.bufFill = 0;
  s.spo2Ticks = 0;
  s.spo2Valid = 0;
  s.hrAlgoValid = 0;
  for (int i = 0; i < 16; i++) s.recentBeat[i] = 0;
  if (!keepDet) {
    s.detA = 0;
    s.detB = 0;
    s.rawPeakCount = 0;
  }
}

void max30102ResetPatientDetectors() {
  resetState(_pP, false);
  _pSampleClockMs = 0;
}
void max30102ResetRescuerBeats() {
  resetState(_pR, true);
}

bool max30102RescuerOk() {
  return _rescuerOk;
}
bool max30102PatientOk() {
  return _patientOk;
}

// ── Biquad (direct form II transposed) ───────────────────────────────────────
static inline float biquad(float x, const float b[3], const float a[3],
                           float& z1, float& z2) {
  float y = b[0] * x + z1;
  z1 = b[1] * x - a[1] * y + z2;
  z2 = b[2] * x - a[2] * y;
  return y;
}

// ── Core per-sample pipeline ─────────────────────────────────────────────────
// Returns true if contact OK (sample processed), false if no contact.
static bool processSample(PpgState& s, uint32_t rawIR, uint32_t rawRed,
                          uint32_t nowMs, float envDcFrac) {
  if (rawIR < CONTACT_IR_MIN) return false;

  // DC tracker — fast on big jumps, slow in steady state
  if (!s.dcInit) {
    s.dc = (float)rawIR;
    s.dcInit = true;
  } else {
    float jump = fabsf((float)rawIR - s.dc) / s.dc;
    float alpha = (jump > 0.05f) ? 0.05f : 0.005f;
    s.dc = (1.0f - alpha) * s.dc + alpha * (float)rawIR;
    if (jump > 0.10f) s.envelope *= 0.5f;
  }
  float ac = (float)rawIR - s.dc;

  // DC stability window
  s.dcWin[s.dcWinIdx] = s.dc;
  s.dcWinIdx = (s.dcWinIdx + 1) % 100;
  if (s.dcWinFill < 100) s.dcWinFill++;

  // Bandpass
  float y1 = biquad(ac, BPF_B1, BPF_A1, s.z1_1, s.z1_2);
  s.filtered = biquad(y1, BPF_B2, BPF_A2, s.z2_1, s.z2_2);

  // Envelope (fast attack, faster decay, floored)
  float absF = fabsf(s.filtered);
  if (absF > s.envelope) s.envelope = 0.6f * s.envelope + 0.4f * absF;
  else s.envelope = 0.97f * s.envelope + 0.03f * absF;
  if (s.envelope < ENV_FLOOR) s.envelope = ENV_FLOOR;

 // Peak detection
  bool beat = false;
  float thr = s.envelope * PEAK_THRESH_PCT;
  bool rawPeak = (s.prevF > s.prevPrevF && s.prevF > s.filtered && s.prevF > thr);
  if (rawPeak) s.rawPeakCount++;   // detA: every threshold crossing, no refractory
  if (rawPeak && (nowMs - s.lastBeatMs) > RR_MIN_MS) {
    uint32_t rr = nowMs - s.lastBeatMs;
    if (rr >= RR_MIN_MS && rr <= RR_MAX_MS && s.lastBeatMs > 0) {
      s.rrBuf[s.rrHead] = (uint16_t)rr;
      s.rrTs[s.rrHead] = nowMs;
      s.rrHead = (s.rrHead + 1) % 32;
      if (s.rrCount < 32) s.rrCount++;
    }
    s.lastBeatMs = nowMs;
    beat = true;
    s.recentBeat[s.recentHead] = nowMs;
    s.recentHead = (s.recentHead + 1) % 16;
  }
  s.prevPrevF = s.prevF;
  s.prevF = s.filtered;

  // SpO2 ring buffer
  if (s.bufFill < 100) {
    s.irBuf[s.bufFill] = rawIR;
    s.redBuf[s.bufFill] = rawRed;
    s.bufFill++;
  } else {
    for (int i = 0; i < 99; i++) {
      s.irBuf[i] = s.irBuf[i + 1];
      s.redBuf[i] = s.redBuf[i + 1];
    }
    s.irBuf[99] = rawIR;
    s.redBuf[99] = rawRed;
  }
  s.spo2Ticks++;
  if (s.spo2Ticks >= 25 && s.bufFill >= 100) {
    s.spo2Ticks = 0;
    maxim_heart_rate_and_oxygen_saturation(
      s.irBuf, 100, s.redBuf,
      &s.spo2Val, &s.spo2Valid, &s.hrAlgoVal, &s.hrAlgoValid);
  }

  // HR — median of last 8 RR
  if (beat && s.rrCount >= 3) {
    uint16_t r[8];
    int nn = s.rrCount < 8 ? s.rrCount : 8;
    for (int i = 0; i < nn; i++) r[i] = s.rrBuf[(s.rrHead - 1 - i + 32) % 32];
    for (int i = 1; i < nn; i++) {
      uint16_t k = r[i];
      int j = i - 1;
      while (j >= 0 && r[j] > k) {
        r[j + 1] = r[j];
        j--;
      }
      r[j + 1] = k;
    }
    s.hrBpm = 60000.0f / (float)r[nn / 2];
  }

  // RMSSD — 60 s window
  if (beat && s.rrCount >= RMSSD_MIN_INTERVALS) {
    double sumSq = 0;
    int nd = 0;
    uint16_t prev = 0;
    for (int i = 0; i < s.rrCount; i++) {
      int idx = (s.rrHead - 1 - i + 32) % 32;
      if (nowMs - s.rrTs[idx] > RMSSD_WINDOW_MS) break;
      if (prev > 0) {
        float d = (float)s.rrBuf[idx] - (float)prev;
        sumSq += d * d;
        nd++;
      }
      prev = s.rrBuf[idx];
    }
    if (nd >= RMSSD_MIN_INTERVALS - 1) s.rmssdMs = sqrtf((float)(sumSq / nd));
  }

  // Composite SQI
  float envScore = constrain(s.envelope / (s.dc * envDcFrac), 0.0f, 1.0f);
  float regScore = 0;
  if (s.rrCount >= 5) {
    uint16_t f5[5];
    for (int i = 0; i < 5; i++) f5[i] = s.rrBuf[(s.rrHead - 1 - i + 32) % 32];
    float m = 0;
    for (int i = 0; i < 5; i++) m += f5[i];
    m /= 5.0f;
    float v = 0;
    for (int i = 0; i < 5; i++) {
      float d = f5[i] - m;
      v += d * d;
    }
    float sd = sqrtf(v / 5.0f);
    float cv = (m > 0) ? sd / m : 1.0f;
    regScore = constrain(1.0f - (cv - 0.05f) / 0.30f, 0.0f, 1.0f);
  }
  float stabScore = 0;
  if (s.dcWinFill >= 100) {
    float m = 0;
    for (int i = 0; i < 100; i++) m += s.dcWin[i];
    m /= 100.0f;
    float v = 0;
    for (int i = 0; i < 100; i++) {
      float d = s.dcWin[i] - m;
      v += d * d;
    }
    float sd = sqrtf(v / 100.0f);
    float rel = (m > 0) ? sd / m : 1.0f;
    stabScore = constrain(1.0f - rel / 0.02f, 0.0f, 1.0f);
  }
  int rN = 0;
  for (int i = 0; i < 16; i++)
    if (s.recentBeat[i] > 0 && nowMs - s.recentBeat[i] < 10000) rN++;
  float beatScore = constrain(rN / 8.0f, 0.0f, 1.0f);

  float q = envScore * 0.40f + regScore * 0.30f + stabScore * 0.20f + beatScore * 0.10f;
  s.sqi = (uint8_t)(q * 100.0f);
  return true;
}

// ── Rescuer FIFO drain — MUST be called every ~10 ms (matches 100 Hz ODR) ────
// The MAX30102 FIFO is 32 samples deep; at 100 Hz it fills in 320 ms, so any
// poll slower than that drops samples AND collapses RR timing. We drain every
// comms tick and derive a per-sample timestamp from the sensor's nominal
// 10 ms period instead of millis(), so RR intervals stay accurate even when
// several samples arrive in one burst.
static uint8_t _rNoContactStreak = 0;
static uint32_t _rSampleClockMs = 0;

void max30102ServiceRescuer() {
  if (!_rescuerOk) return;
  tcaSelect(TCA_CH_MAX30102_R);
  _rescuer.check();

  bool anyContact = false;
  if (_rSampleClockMs == 0) _rSampleClockMs = millis();

  while (_rescuer.available()) {
    uint32_t ir = _rescuer.getIR();
    uint32_t red = _rescuer.getRed();
    _rescuer.nextSample();
    // Advance a synthetic 10 ms-per-sample clock so bursts don't collapse RR.
    _rSampleClockMs += 10;
    if (processSample(_pR, ir, red, _rSampleClockMs, ENV_DC_FRAC_R))
      anyContact = true;
  }

  if (anyContact) {
    _rNoContactStreak = 0;
  } else {
    // Tolerate brief dropouts (hand vibration during CPR). Only wipe the
    // RR history after a sustained loss (~1.5 s of empty drains).
    if (_rNoContactStreak < 255) _rNoContactStreak++;
    if (_rNoContactStreak >= 150) {  // 150 × 10 ms ≈ 1.5 s
      resetState(_pR, true);
      _rSampleClockMs = 0;
    }
  }
}

// ── Rescuer value read — call at any slow cadence (e.g. 500 ms) ──────────────
void max30102UpdateRescuer(float& hrBpm, float& spO2, uint8_t& sigQuality,
                           uint8_t& rmsspx, uint8_t& pi) {
  if (!_rescuerOk) {
    hrBpm = spO2 = 0;
    sigQuality = rmsspx = pi = 0;
    return;
  }

  bool stale = (_rNoContactStreak >= 150);
  if (stale) {
    hrBpm = spO2 = 0;
    sigQuality = rmsspx = pi = 0;
    return;
  }

  hrBpm = _pR.hrBpm;
  sigQuality = _pR.sqi;
  spO2 = (_pR.spo2Valid && _pR.spo2Val >= 70 && _pR.spo2Val <= 100)
           ? (float)_pR.spo2Val
           : 0.0f;
  float qi = (_pR.dc > 0) ? (_pR.envelope / _pR.dc) * 100.0f : 0.0f;
  pi = (uint8_t)constrain(qi * 10.0f, 0.0f, 255.0f);
  rmsspx = (_pR.rmssdMs > 0)
             ? (uint8_t)constrain(_pR.rmssdMs, 0.0f, 200.0f)
             : 0;
}


// ── Patient update (call only during pulse-check window) ─────────────────────
void max30102UpdatePatient(float& hrBpm, float& spO2, float& ppgRaw,
                           uint8_t& sigQuality, uint8_t& pi,
                           uint8_t& detectorACount, uint8_t& detectorBCount) {
  if (!_patientOk) {
    hrBpm = spO2 = ppgRaw = 0;
    sigQuality = pi = 0;
    detectorACount = detectorBCount = 0;
    return;
  }
  tcaSelect(TCA_CH_MAX30102_P);
  _patient.check();

  bool anyContact = false;
  uint32_t irSum = 0;
  int irCount = 0;
if (_pSampleClockMs == 0) _pSampleClockMs = millis();
  while (_patient.available()) {
    uint32_t ir = _patient.getIR();
    uint32_t red = _patient.getRed();
    _patient.nextSample();
    _pSampleClockMs += 10;
    irSum += ir;
    irCount++;
    uint32_t before = _pP.lastBeatMs;
    if (processSample(_pP, ir, red, _pSampleClockMs, ENV_DC_FRAC_P)) {
      anyContact = true;
      if (_pP.lastBeatMs != before) {
        _pP.detB++;
      }
    }
  }

  ppgRaw = (irCount > 0)
    ? constrain((float)(irSum / (uint32_t)irCount) / 262144.0f, 0.0f, 1.0f)
    : 0.0f;
  _pP.detA = (uint8_t)constrain(_pP.rawPeakCount, 0, 255);
  detectorACount = _pP.detA;
  detectorBCount = _pP.detB;

  if (!anyContact) {
    hrBpm = spO2 = 0;
    sigQuality = pi = 0;
    return;
  }

  hrBpm = (_pP.hrBpm >= 40.0f && _pP.hrBpm <= 180.0f) ? _pP.hrBpm : 0.0f;
  sigQuality = _pP.sqi;
  spO2 = (_pP.spo2Valid && _pP.spo2Val >= 70 && _pP.spo2Val <= 100)
           ? (float)_pP.spo2Val
           : 0.0f;
  float qi = (_pP.dc > 0) ? (_pP.envelope / _pP.dc) * 100.0f : 0.0f;
  pi = (uint8_t)constrain(qi * 10.0f, 0.0f, 255.0f);
}

// ── Pulse classification (unchanged logic, now fed by reliable SQI) ──────────
// 0=Absent 1=Uncertain 2=Present
uint8_t max30102ClassifyPulse(float hrBpm, uint8_t sigQuality,
                              uint8_t detA, uint8_t detB) {
  // Hard rejection: too few confirmed beats or signal too weak.
  // detB ≥ 4 over a 10 s window = ≥ 24 BPM sustained (below brady floor).
  if (sigQuality < 40 || detB < 2) return 0;  // Absent

  const float ratio = (detA > 0) ? (float)detB / (float)detA : 0.0f;
  const bool rateOk = (hrBpm >= 30.0f && hrBpm <= 180.0f);
  const bool signalOk = (sigQuality >= 60);
  const bool agreement = (detB <= 4) ? (ratio >= 0.60f) : (ratio >= 0.70f);

  if (rateOk && signalOk && agreement) return 2;  // Present
  return 1;                                       // Uncertain
}

float max30102DiagRescuerFiltered() {
  return _rescuerOk ? _pR.filtered : 0.0f;
}
float max30102DiagRescuerDc() {
  return _rescuerOk ? _pR.dc : 0.0f;
}