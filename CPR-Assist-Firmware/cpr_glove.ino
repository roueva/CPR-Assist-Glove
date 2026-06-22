// =============================================================================
// cpr_glove.ino — CPR Assist Glove Firmware v1.0
// AUTH Biomedical Engineering — Evanthia Rouka
//
// Two FreeRTOS tasks:
//   sensorTask  (Core 1, priority 5) — 100Hz: IMU, force, depth, posture
//   commsTask   (Core 0, priority 3) — BLE, audio, NeoPixel, button, battery
//
// Shared state protected by portMUX_TYPE spinlock.
// =============================================================================

#include <Arduino.h>
#include <Wire.h>
#include <LittleFS.h>

#include "config.h"
#include "shared_state.h"
#include "tca.h"
#include "imu.h"
#include "force.h"
#include "depth.h"
#include "max30102.h"
#include "max30205.h"
#include "gxht30.h"
#include "battery.h"
#include "button.h"
#include "neopixel.h"
#include "motor.h"
#include "audio.h"
#include "storage.h"
#include "selftest.h"
#include "ble_manager.h"

// ── Global shared state ───────────────────────────────────────────────────────
SharedState gState;
portMUX_TYPE gStateMux = portMUX_INITIALIZER_UNLOCKED;
SemaphoreHandle_t gI2CMutex = nullptr;

// Diagnostic mode state (declared in shared_state.h)
volatile bool diagActive = false;
volatile uint8_t diagActionResult = 0x00;
volatile uint8_t diagI2cScanResult = 0x00;
volatile uint8_t diagPalmWhoAmI = 0x00;
volatile uint8_t diagWristWhoAmI = 0x00;

// ── Session runtime state (comms task only) ───────────────────────────────────
static bool _sessionRunning = false;
static unsigned long _sessionStartMs = 0;
static uint64_t _sessionUnixTsMs = 0;      // wall-clock ms since epoch, from CMD_SYNC_TIME. 0 = never synced this power cycle.
static unsigned long _timeSyncMillis = 0;  // millis() when CMD_SYNC_TIME last arrived; 0 = never synced this power cycle
static unsigned long _lastTwoMinMs = 0;
static unsigned long _lastPulseCheckMs = 0;
static uint8_t _twoMinCount = 0;
static uint16_t _pulseCheckCount = 0;
static bool _inPulseCheck = false;
static unsigned long _pulseCheckStartMs = 0;
static uint32_t _pulseCheckOpenAtCount = 0;  // compressionCount when window opened
static bool _pulseResumePromptPlayed = false;
static bool _pulsePauseSeen = false;
static bool _pulseResultSent = false;
static unsigned long _pulseCheckWarmupEndMs = 0;
static uint16_t _ventCycleNum = 0;
static bool _inVentWindow = false;
static uint32_t _ventWindowOpenAtCount = 0;
static unsigned long _ventLongestGapMs = 0;
static unsigned long _ventWindowOpenMs = 0;
static uint32_t _ventCompsAtGraceEnd = 0;
static bool _ventResumePromptPlayed = false;
static bool _ventPauseSeen = false;
static bool _selftestPending = false;
static unsigned long _connectMs = 0;
static bool _selftestDone = false;

// Audio quality tracking
static int _consecutiveTooShallow = 0;  // depth below targetMin
static int _consecutiveTooDeep = 0;     // depth above targetMax
static int _consecutiveBadFreq = 0;
static int _consecutiveBadRecoil = 0;
static int _consecutiveBadPosture = 0;
static int _consecutiveGood = 0;
static int _goodCooldown = 0;
static int _audioGapCount = 0;  // compressions since last quality audio

// Metronome
static unsigned long _lastMetronomeMs = 0;

// Compression count tracking for ventilation
static uint32_t _lastCompCount = 0;
static uint32_t _lastCycleCount = 0;
static uint8_t _lastCompInCycle = 0;

static int _consecutiveBadForce = 0;

static bool _fatigueSent = false;

static volatile bool _pendingStart = false;
static volatile bool _pendingStop = false;
static volatile bool _pendingSelftest = false;
static volatile bool _pendingCalibrate = false;

static volatile bool _pendingModeChange = false;
static volatile GloveMode _pendingMode = GloveMode::Emergency;
static volatile bool _pendingScenarioChange = false;
static volatile Scenario _pendingScenario = Scenario::Adult;

#if IMU_TEST_LOG
static bool _imuTestActive = false;
static unsigned long _imuTestStartMs = 0;
static float _imuTestPalmPeakMM = 0;
static float _imuTestWristPeakMM = 0;
static float _imuTestPalmEndMM = 0;
static float _imuTestWristEndMM = 0;
#endif

// Confirms can arrive rapidly when the app finishes syncing several pending
// sessions. Use a bitmask so back-to-back confirms (one per session index)
// can't clobber each other. STORAGE_MAX_SESSIONS=20 fits easily in 32 bits.
static volatile uint32_t _pendingConfirmMask = 0;

// Session-request queue: app can ask for multiple sessions back-to-back
// (PENDING_LOCAL_DATA→REQUEST_SESSION pattern). Small FIFO to avoid losing
// requests if a previous send is still streaming.
#define SESSION_REQ_QUEUE 4
static volatile uint8_t _sessReqQ[SESSION_REQ_QUEUE] = { 0 };
static volatile uint8_t _sessReqHead = 0;  // next write position
static volatile uint8_t _sessReqTail = 0;  // next read position

// Active outbound chunk stream — drip-fed below so commsTask stays responsive.
// _chunkSendCursor == 0 means idle. Otherwise it's the next chunk index to send + 1.
static volatile uint8_t _chunkSendIdx = 0;
static volatile uint8_t _chunkSendCursor = 0;
static volatile uint8_t _chunkSendTotal = 0;
static unsigned long _lastChunkSendMs = 0;

static unsigned long _lastCompressionMs = 0;
static bool _inUnplannedPause = false;


static StoredVentilation _storedVents[STORAGE_MAX_VENTILATIONS];
static uint8_t _storedVentCount = 0;
static StoredPulseCheck _storedPulses[STORAGE_MAX_PULSE_CHECKS];
static uint8_t _storedPulseCount = 0;

// ── BLE callbacks (called from BLE ISR context — keep minimal) ────────────────
void onBLEConnect() {
  _connectMs = millis();
  _selftestDone = false;
  _selftestPending = true;
  // Flush stale events from the disconnected period — the app re-syncs
  // persisted sessions via PENDING_LOCAL_DATA, so replaying mid-session
  // vent/pulse-check events would only confuse it.
  bleFlushEventQueue();
}

void onBLEDisconnect() {}

void onAppCommand(uint8_t cmd, const uint8_t* data, size_t len) {
  switch (cmd) {

    case CMD_MODE_SET:
      {
        if (len < 2) break;
        GloveMode newMode = (GloveMode)data[1];
        portENTER_CRITICAL(&gStateMux);
        gState.currentMode = newMode;
        const bool fbOn = (newMode != GloveMode::NoFeedback);
        gState.audioFeedbackEnabled = fbOn;
        gState.hapticFeedbackEnabled = fbOn;
        gState.visualFeedbackEnabled = fbOn;
        portEXIT_CRITICAL(&gStateMux);
        bleQueueEvent(bleBuildModeChange(newMode, 1));  // trigger=1 (app command)
        const uint8_t modeAudio[] = { AUDIO_MODE_EMERGENCY, AUDIO_MODE_TRAINING, AUDIO_MODE_NOFEEDBACK };
        audioPlay(modeAudio[(int)newMode], AUDIO_PRI_MODE_CHANGE);
        _pendingMode = newMode;
        _pendingModeChange = true;
        break;
      }

    case CMD_SET_SCENARIO:
      {
        if (len < 2) break;
        Scenario sc = (Scenario)data[1];
        portENTER_CRITICAL(&gStateMux);
        gState.currentScenario = sc;
        gState.targetDepthMinMM = (sc == Scenario::Pediatric) ? TARGET_DEPTH_MIN_PEDS : TARGET_DEPTH_MIN_ADULT;
        gState.targetDepthMaxMM = (sc == Scenario::Pediatric) ? TARGET_DEPTH_MAX_PEDS : TARGET_DEPTH_MAX_ADULT;
        portEXIT_CRITICAL(&gStateMux);
        bleQueueEvent(bleBuildScenarioChange(sc, 1));
        audioPlay((sc == Scenario::Pediatric) ? AUDIO_SCENARIO_PEDS : AUDIO_SCENARIO_ADULT,
                  AUDIO_PRI_MODE_CHANGE);
        _pendingScenario = sc;
        _pendingScenarioChange = true;
        break;
      }

    case CMD_START:
      if (!_sessionRunning) _pendingStart = true;
      break;

    case CMD_STOP:
      if (_sessionRunning) _pendingStop = true;
      break;

    case CMD_RUN_SELFTEST:
      // Read-only diagnostic — never affects sensor baselines.
      if (!_sessionRunning && !_inPulseCheck && !_inVentWindow) {
        _pendingSelftest = true;
      } else {
        SelfTestResult r;
        memset(&r, 0, sizeof(r));
        r.batteryPct = snapshotState().batteryPercentage;
        for (int i = 0; i < 8; i++) r.reasonCodes[i] = SELFTEST_REASON_NOT_TESTED;
        bleQueueEvent(bleBuildSelftestResult(r));
      }
      break;

    case CMD_CALIBRATE:
      // Destructive — resets force baseline. User must hold the glove still.
      // Runs forceInit() until the baseline converges (or 2 s timeout), then
      // runs selftest and reports back. Same session/pulse/vent guards as above.
      if (!_sessionRunning && !_inPulseCheck && !_inVentWindow) {
        _pendingCalibrate = true;
      } else {
        SelfTestResult r;
        memset(&r, 0, sizeof(r));
        r.batteryPct = snapshotState().batteryPercentage;
        for (int i = 0; i < 8; i++) r.reasonCodes[i] = SELFTEST_REASON_NOT_TESTED;
        bleQueueEvent(bleBuildSelftestResult(r));
      }
      break;

    case CMD_CONFIRM_RECEIVED:
      if (len >= 2 && data[1] < STORAGE_MAX_SESSIONS) {
        _pendingConfirmMask |= (1u << data[1]);
      }
      break;

    case CMD_SET_TARGET_DEPTH:
      if (len >= 3) {
        portENTER_CRITICAL(&gStateMux);
        gState.targetDepthMinMM = (float)data[1];  // byte encodes depth in mm directly
        gState.targetDepthMaxMM = (float)data[2];
        portEXIT_CRITICAL(&gStateMux);
      }
      break;

    case CMD_SET_TARGET_RATE:
      if (len >= 3) {
        portENTER_CRITICAL(&gStateMux);
        gState.targetRateMin = (float)data[1];
        gState.targetRateMax = (float)data[2];
        portEXIT_CRITICAL(&gStateMux);
      }
      break;

    case CMD_SET_VENTILATION:
      if (len >= 3) {
        portENTER_CRITICAL(&gStateMux);
        gState.ventilationCompressions = data[1];
        gState.ventilationBreaths = data[2];
        portEXIT_CRITICAL(&gStateMux);
      }
      break;

    case CMD_SYNC_TIME:
      if (len >= 9) {
        _sessionUnixTsMs = (uint64_t)data[1]
                           | ((uint64_t)data[2] << 8)
                           | ((uint64_t)data[3] << 16)
                           | ((uint64_t)data[4] << 24)
                           | ((uint64_t)data[5] << 32)
                           | ((uint64_t)data[6] << 40)
                           | ((uint64_t)data[7] << 48)
                           | ((uint64_t)data[8] << 56);
        _timeSyncMillis = millis();  // anchor for projecting session start onto wall clock
      }
      break;

    case CMD_FEEDBACK_SET:
      // Legacy single-byte all-channels command. Kept for backwards compatibility.
      if (len >= 2) {
        const bool on = (data[1] != 0);
        portENTER_CRITICAL(&gStateMux);
        gState.audioFeedbackEnabled = on;
        gState.hapticFeedbackEnabled = on;
        gState.visualFeedbackEnabled = on;
        portEXIT_CRITICAL(&gStateMux);
      }
      break;

    case CMD_SET_FEEDBACK_CH:
      // Per-channel feedback bitmask. bit0=audio bit1=haptic bit2=visual
      if (len >= 2) {
        const uint8_t m = data[1];
        portENTER_CRITICAL(&gStateMux);
        gState.audioFeedbackEnabled = (m & 0x01) != 0;
        gState.hapticFeedbackEnabled = (m & 0x02) != 0;
        gState.visualFeedbackEnabled = (m & 0x04) != 0;
        portEXIT_CRITICAL(&gStateMux);
      }
      break;

    case CMD_SET_VOLUME:
      if (len >= 2) audioSetVolume(data[1]);
      if (len >= 3) motorSetIntensity(data[2]);
      break;



    case CMD_DIAG_START:
      {
        diagActive = true;
        diagActionResult = 0x00;
        diagI2cScanResult = 0x00;
        // I2C reads — must hold mutex (sensorTask is at 100Hz on the same bus)
        if (gI2CMutex && xSemaphoreTake(gI2CMutex, pdMS_TO_TICKS(100)) == pdTRUE) {
          diagPalmWhoAmI = imuReadWhoAmI(TCA_CH_IMU_PALM, LSM6DSOX_ADDR_PALM);
          diagWristWhoAmI = imuReadWhoAmI(TCA_CH_IMU_WRIST, LSM6DSOX_ADDR_WRIST);
          xSemaphoreGive(gI2CMutex);
        }
        break;
      }

    case CMD_DIAG_STOP:
      diagActive = false;
      diagActionResult = 0x00;
      break;

    case CMD_DIAG_ACTION:
      if (len < 2) break;
      switch (data[1]) {
       case DIAG_ACTION_PLAY_AUDIO: {
          uint8_t track = (len >= 3 && data[2] > 0) ? data[2] : 10;
          audioPlay(track, 10);
          diagActionResult = 0x01;
          break;
        }
        case DIAG_ACTION_FIRE_MOTOR:
          motorPulse(500);
          diagActionResult = 0x02;
          break;
        case DIAG_ACTION_LED_TEST:
          neoDiagLedTest();
          diagActionResult = 0x03;
          break;
        case DIAG_ACTION_I2C_SCAN:
          if (gI2CMutex && xSemaphoreTake(gI2CMutex, pdMS_TO_TICKS(200)) == pdTRUE) {
            diagI2cScanResult = selftestI2CScan();
            xSemaphoreGive(gI2CMutex);
          }
          diagActionResult = 0x04;
          break;
        case DIAG_ACTION_SET_VOLUME:
          if (len >= 3) audioSetVolume(data[2]);
          diagActionResult = 0x05;
          break;
        case DIAG_ACTION_SET_BRIGHTNESS:
          if (len >= 3) neoSetBrightness(data[2]);
          diagActionResult = 0x06;
          break;
      }
      break;
  }
}

// ── Session control ───────────────────────────────────────────────────────────
static void startSession() {
  _sessionRunning = true;
  forceSetSessionActive(true);
  _sessionStartMs = millis();
  _lastTwoMinMs = millis();
  _lastPulseCheckMs = millis();
  _twoMinCount = 0;
  _pulseCheckCount = 0;
  _inPulseCheck = false;
  _pulseResultSent = false;
  _ventCycleNum = 0;
  _inVentWindow = false;
  _lastCompressionMs = millis();
  _inUnplannedPause = false;
  _ventWindowOpenAtCount = 0;
  _lastMetronomeMs = millis();
  _lastCompCount = 0;
  _lastCycleCount = 0;
  _fatigueSent = false;
  _consecutiveBadForce = 0;
  _consecutiveTooShallow = _consecutiveTooDeep = 0;
  _consecutiveBadFreq = _consecutiveBadRecoil = 0;
  _consecutiveBadPosture = _consecutiveGood = _goodCooldown = _audioGapCount = 0;
  _storedVentCount = 0;
  _storedPulseCount = 0;

  // Refresh rescuer wrist temp once at session start so the SESSION_END
  // "start" value isn't a stale/zero leftover.
  {
    float rT = 0, rH = 0;
    if (gI2CMutex && xSemaphoreTake(gI2CMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
      bool ok = gxht30Read(rT, rH);
      xSemaphoreGive(gI2CMutex);
      if (ok) {
        portENTER_CRITICAL(&gStateMux);
        gState.rescuerTemperature = rT;
        gState.rescuerHumidity = rH;
        portEXIT_CRITICAL(&gStateMux);
      }
    }
  }

  portENTER_CRITICAL(&gStateMux);
  gState.sessionActive = true;
  gState.compressionInCycle = 0;
  gState.timeToFirstCompressionMs = 0;
  gState.sessionStartMs = millis();
  gState.ventilationCount = 0;
  gState.inVentilationWindow = false;
  gState.peakDepth = 0.0f;
  gState.averageDepth = 0.0f;
  gState.peakTimestampMs = 0;
  gState.valleyTimestampMs = 0;
  gState.recoilAchieved = false;
  gState.leaningDetected = false;
  gState.overForceFlag = false;
  gState.postureOk = true;
  gState.valleyDepth = 0.0f;
  gState.depth = 0.0f;
  gState.lastPeakDepthCm = 0.0f;
  gState.force = 0.0f;
  gState.compressionDepthSD = 0.0f;
  gState.noFlowIntervals = 0;
  gState.pulseChecksPrompted = 0;
  gState.pulseChecksComplied = 0;
  gState.pulseDetected = false;
  gState.rescuerSwapCount = 0;
  gState.fatigueFlag = false;
  gState.rescuerFatigueScore = 0;
  gState.fatigueOnsetIndex = 0;
  gState.rescuerTemperatureStart = gState.rescuerTemperature;
  gState.totalVentilations = 0;
  gState.correctVentilations = 0;
  gState.totalCompressions = 0;
  gState.correctDepth = 0;
  gState.correctFrequency = 0;
  gState.correctRecoil = 0;
  gState.correctPosture = 0;
  gState.depthRateCombo = 0;
  gState.leaningCount = 0;
  gState.overForceCount = 0;
  gState.tooDeepCount = 0;
  gState.compressionCount = 0;
  gState.frequency = 0.0f;
  gState.instantaneousRate = 0.0f;
  gState.depthTrend = 0.0f;
  portEXIT_CRITICAL(&gStateMux);

  depthSessionReset();

  SharedState snap = snapshotState();
  bleQueueEvent(bleBuildSessionStart(snap.currentMode, snap.currentScenario));
  max30102ResetRescuerBeats();
  audioPlay(AUDIO_SESSION_STARTED, AUDIO_PRI_SYSTEM);
  motorPattern(MOTOR_SHORT_MS, MOTOR_SHORT_MS, 3);
  neoSessionStart();
}

static void stopSession() {
  _sessionRunning = false;
  forceSetSessionActive(false);
  _fatigueSent = false;

  // Chunk 3 Change 13 — finalize valley tracking for the last compression
  // so its recoil status is captured in the snapshot, not lost on session end.
  depthFinalizeLastValley();

  float sd = depthGetSD();    // compute before acquiring lock
  float avg = depthGetAvg();  // new function

  portENTER_CRITICAL(&gStateMux);
  gState.sessionActive = false;
  gState.averageDepth = avg;
  gState.rescuerTemperatureEnd = gState.rescuerTemperature;
  gState.compressionDepthSD = sd;
  gState.inVentilationWindow = false;
  portEXIT_CRITICAL(&gStateMux);

  SharedState snap = snapshotState();
  // Always emit SESSION_END so the app can leave the live screen — even for
  // trivial sessions (< STORAGE_MIN_COMPRESSIONS_TO_SAVE). The app inspects
  // totalCompressions and decides whether to save. Storage-side suppression
  // (storageSaveSession) still applies — we don't burn flash on garbage.
  if (bleConnected()) {
    bleQueueEvent(bleBuildSessionEnd(snap));
  }
  uint32_t dur = (millis() - _sessionStartMs) / 1000;
  // Compute the real wall-clock session START time.
  // _sessionUnixTsMs is ms-since-epoch captured at the last CMD_SYNC_TIME,
  // and _timeSyncMillis is the millis() at that same moment. The session
  // began at _sessionStartMs (millis). Project that millis delta onto wall-
  // clock time so standalone sessions get a correct timestamp as long as
  // the glove was synced at least once this power cycle. If never synced
  // (_timeSyncMillis==0), store 0 — the app's offline parser substitutes
  // the sync-receipt time and flags the session as approximate.
  uint64_t startUnixMs;
  if (_sessionUnixTsMs > 0 && _timeSyncMillis > 0) {
    // Signed 32-bit subtraction handles millis() wraparound naturally (49.7 d).
    int32_t deltaMs = (int32_t)((uint32_t)_sessionStartMs - (uint32_t)_timeSyncMillis);
    startUnixMs = _sessionUnixTsMs + (int64_t)deltaMs;
  } else {
    startUnixMs = 0;  // unknown — app fills in on sync
  }
  storageSaveSession(snap, dur, startUnixMs);

  audioPlay(AUDIO_SESSION_ENDED, AUDIO_PRI_SYSTEM);
  motorPattern(MOTOR_LONG_MS, MOTOR_MEDIUM_MS, 2);
  neoSessionEnd();
}

static void runSelftest() {
  neoSelftestAnimation();
  // Selftest must be invoked only when no session/pulse/vent is active —
  // gated by both the dispatcher and the command handler. With those gates
  // in place, holding gI2CMutex for ~500 ms is safe: sensorTask will
  // briefly block on its next acquisition (10 ms slot) and resume cleanly
  // once selftest releases.
  SelfTestResult r;
  memset(&r, 0, sizeof(r));
  r.batteryPct = snapshotState().batteryPercentage;

  bool gotMutex =
    gI2CMutex && xSemaphoreTake(gI2CMutex, pdMS_TO_TICKS(1000)) == pdTRUE;
  if (gotMutex) {
    r = selftestRun(r.batteryPct);
    xSemaphoreGive(gI2CMutex);
  } else {
    // Couldn't acquire the I²C mutex within 1 s — sensorTask is wedged
    // somewhere. Report a clear, distinct reason so the user can see
    // it's a firmware concurrency issue, not a hardware fault.
    for (int i = 0; i < 8; i++) r.reasonCodes[i] = SELFTEST_REASON_MUTEX_TIMEOUT;
    r.criticalMask = SELFTEST_BIT_IMU1 | SELFTEST_BIT_IMU2 | SELFTEST_BIT_FORCE;
    r.warnMask = SELFTEST_BIT_MAX_P | SELFTEST_BIT_MAX_R
                 | SELFTEST_BIT_TEMP | SELFTEST_BIT_HUMIDITY | SELFTEST_BIT_AUDIO;
  }

  bleQueueEvent(bleBuildSelftestResult(r));

  if (r.criticalMask) audioPlay(AUDIO_SENSOR_ERROR, AUDIO_PRI_SYSTEM);
  else if (r.warnMask) audioPlay(AUDIO_SENSOR_WARNING, AUDIO_PRI_SYSTEM);
  else audioPlay(AUDIO_GLOVE_READY, AUDIO_PRI_SYSTEM);
}

static void runCalibration() {
  neoSelftestAnimation();
  // Calibrate = reset force baseline + IMU gravity init, then run full
  // selftest so the user sees the post-calibration state. User must hold
  // the glove still during this ~2-3 second window. Same I²C-mutex hold
  // strategy as runSelftest: a single ~1 s window covers the whole thing.
  SelfTestResult r;
  memset(&r, 0, sizeof(r));
  r.batteryPct = snapshotState().batteryPercentage;

  bool gotMutex =
    gI2CMutex && xSemaphoreTake(gI2CMutex, pdMS_TO_TICKS(3000)) == pdTRUE;
  if (gotMutex) {
    // Force baseline: clear stored baseline and re-run init for up to 2 s
    // or until baseline converges (whichever comes first). forceInit()
    // returns true when calibration is settled.
    int retries = 0;
    while (!forceBaselineReady() && retries < 200) {
      forceInit();
      delay(10);
      retries++;
    }
    // Now run the full selftest so the user can see everything is OK.
    r = selftestRun(r.batteryPct);
    xSemaphoreGive(gI2CMutex);
  } else {
    for (int i = 0; i < 8; i++) r.reasonCodes[i] = SELFTEST_REASON_MUTEX_TIMEOUT;
    r.criticalMask = SELFTEST_BIT_IMU1 | SELFTEST_BIT_IMU2 | SELFTEST_BIT_FORCE;
  }
  bleQueueEvent(bleBuildSelftestResult(r));

  if (r.criticalMask) audioPlay(AUDIO_SENSOR_ERROR, AUDIO_PRI_SYSTEM);
  else if (r.warnMask) audioPlay(AUDIO_SENSOR_WARNING, AUDIO_PRI_SYSTEM);
  else audioPlay(AUDIO_GLOVE_READY, AUDIO_PRI_SYSTEM);
}

// ── Quality audio logic (called once per compression) ─────────────────────────
static void handleQualityAudio(const SharedState& s) {
  if (!s.audioFeedbackEnabled) return;
  if (!s.imuCalibrated) return;
  if (_goodCooldown > 0) _goodCooldown--;
  if (_audioGapCount < AUDIO_MIN_GAP_COMPS) {
    _audioGapCount++;
    return;
  }

  bool goodRecoil = s.recoilAchieved;
  bool goodPosture = s.postureOk;
  bool goodFreq = (s.frequency >= s.targetRateMin && s.frequency <= s.targetRateMax);
  bool overForce = s.overForceFlag;
  float lastPeakMM = depthGetLastPeakMM();
  bool goodDepthAbs = (lastPeakMM >= s.targetDepthMinMM && lastPeakMM <= s.targetDepthMaxMM);
  bool tooDeep = (lastPeakMM > s.targetDepthMaxMM);

  // Track consecutive bad counts — too-shallow and too-deep tracked separately
  // so the audio cue priority can address them with the correct prompt.
  if (goodDepthAbs) {
    _consecutiveTooShallow = 0;
    _consecutiveTooDeep = 0;
  } else if (tooDeep) {
    _consecutiveTooDeep++;
    _consecutiveTooShallow = 0;
  } else {
    // too shallow (lastPeakMM < targetMin)
    _consecutiveTooShallow++;
    _consecutiveTooDeep = 0;
  }
  goodFreq ? _consecutiveBadFreq = 0 : _consecutiveBadFreq++;
  goodRecoil ? _consecutiveBadRecoil = 0 : _consecutiveBadRecoil++;
  goodPosture ? _consecutiveBadPosture = 0 : _consecutiveBadPosture++;
  overForce ? _consecutiveBadForce++ : _consecutiveBadForce = 0;

  bool allGood = goodDepthAbs && goodFreq && goodRecoil && goodPosture;
  allGood ? _consecutiveGood++ : _consecutiveGood = 0;

  // Priority order: over-force > too deep > recoil > posture > freq > too shallow
  uint8_t track = 0;
  if (overForce && _consecutiveBadForce >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_EASE_FORCE;
  else if (tooDeep && _consecutiveTooDeep >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_EASE_OFF_DEEP;
  else if (!goodRecoil && _consecutiveBadRecoil >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_LIFT_HANDS;
  else if (!goodPosture && _consecutiveBadPosture >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_STRAIGHTEN_ARMS;
  else if (!goodFreq && s.frequency < s.targetRateMin && _consecutiveBadFreq >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_PRESS_FASTER;
  else if (!goodFreq && s.frequency > s.targetRateMax && _consecutiveBadFreq >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_SLOW_DOWN;
  else if (!goodDepthAbs && lastPeakMM < s.targetDepthMinMM && _consecutiveTooShallow >= AUDIO_BAD_COMP_THRESHOLD)
    track = AUDIO_PRESS_HARDER;

  if (track) {
    audioPlay(track, AUDIO_PRI_QUALITY);
    _audioGapCount = 0;
    return;
  }

  // "Good job" after 10 consecutive correct compressions with cooldown
  if (_consecutiveGood >= AUDIO_GOOD_COMP_THRESHOLD && _goodCooldown == 0) {
    audioPlay(AUDIO_GOOD_JOB, AUDIO_PRI_QUALITY);
    _goodCooldown = AUDIO_GOOD_COOLDOWN;
    _audioGapCount = 0;
  }
}

// ── SENSOR TASK (Core 1, 100Hz) ───────────────────────────────────────────────
static void sensorTask(void* pv) {
  unsigned long lastMicros = micros();

  while (true) {
    unsigned long nowMicros = micros();
    float dt = (nowMicros - lastMicros) / 1e6f;
    lastMicros = nowMicros;
    if (dt <= 0 || dt > 0.05f) dt = SAMPLE_DT;

    float force = forceRead();

#if FORCE_TEST_LOG
    static unsigned long _lastForceTestMs = 0;
    if (millis() - _lastForceTestMs >= 250) {
      _lastForceTestMs = millis();
      int rawAdc;
      float volts, rawN, base, filtN;
      forceTestRead(rawAdc, volts, rawN, base, filtN);
      Serial.printf("FTEST adc=%4d  V=%.3f  rawF=%6.1fN  base=%5.1fN  filtF=%6.1fN\n",
                    rawAdc, volts, rawN, base, filtN);
    }
#endif

    if (_sessionRunning) {
      static unsigned long _lastForceLog = 0;
      if (millis() - _lastForceLog > 500) {
        _lastForceLog = millis();
      }
    }

    // Hold the mutex ONLY across the I²C transactions. All CPU-only work
    // (filters, gravity accumulate, depth math) runs after the give so
    // commsTask is never starved waiting for shared I²C access.
    xSemaphoreTake(gI2CMutex, portMAX_DELAY);
    IMURaw palm = imuReadPalm();
    IMURaw wrist;
    bool wristRead = false;
    if (imuWristOk() && !imuWristDropped()) {
      wrist = imuReadWrist();
      wristRead = true;
    }
    xSemaphoreGive(gI2CMutex);

    // Freeze CF accel correction during any hand motion (COMPRESSING or RELEASING).
    // Only run full accel-corrected CF update when truly stationary (RELEASED).
    // During motion, gyro-only propagation prevents motion accel from corrupting
    // the gravity rotation estimate (Foxlin 2005, Madgwick 2010).
    if (!depthIsReleased()) {
      imuUpdateFiltersGyroOnly(palm, wrist, dt);
    } else {
      imuUpdateFilters(palm, wrist, dt);
    }

    // Gate gravity accumulation: only update when hand is not in a stroke
    // and force is low. This keeps the gravity estimate clean.

#if IMU_TEST_LOG
    // IMU isolation: when armed, integrate continuously for 1s, capture
    // both running peak and final value, then auto-disarm.
    if (_imuTestActive) {
      float aPalmTest = imuGetMotionAccelPalm();
      float aWristTest = imuGetMotionAccelWrist();
      integrateCompression(integPalm, aPalmTest, dt);
      if (imuWristOk() && !imuWristDropped())
        integrateCompression(integWrist, aWristTest, dt);

      float pMM = integPalm.depthM * 1000.0f;
      float wMM = integWrist.depthM * 1000.0f;
      if (pMM > _imuTestPalmPeakMM) _imuTestPalmPeakMM = pMM;
      if (wMM > _imuTestWristPeakMM) _imuTestWristPeakMM = wMM;

      if (millis() - _imuTestStartMs >= 1000) {
        _imuTestPalmEndMM = pMM;
        _imuTestWristEndMM = wMM;
        Serial.printf("ITEST palmPeak=%.1fmm  wristPeak=%.1fmm  "
                      "palmEnd=%.1fmm  wristEnd=%.1fmm  aPalmFinal=%.2f  aWristFinal=%.2f\n",
                      _imuTestPalmPeakMM, _imuTestWristPeakMM,
                      _imuTestPalmEndMM, _imuTestWristEndMM,
                      aPalmTest, aWristTest);
        _imuTestActive = false;
        resetIntegration(integPalm);
        resetIntegration(integWrist);
      }
    }
#endif

    {
      SharedState _snap = snapshotState();
      bool _inStroke = (_snap.sessionActive && (_snap.depth > 0.1f || force > FORCE_COMPRESS_START * 0.5f));
      if (!_inStroke) {
        imuAccumulate(palm, wrist);
      }
    }

    // Make a local copy of mode/scenario for depth (avoid holding lock during computation)
    GloveMode mode;
    Scenario sc;
    portENTER_CRITICAL(&gStateMux);
    mode = gState.currentMode;
    sc = gState.currentScenario;
    portEXIT_CRITICAL(&gStateMux);

    // Run depth state machine — writes directly into gState via pointer
    // We pass a local scratch then merge to avoid holding the lock
    SharedState local = snapshotState();
    depthUpdate(force, dt, local, mode, sc);

    portENTER_CRITICAL(&gStateMux);
    // Merge depth-computed fields back
    gState.depth = local.depth;
    gState.force = local.force;
    gState.frequency = local.frequency;
    gState.instantaneousRate = local.instantaneousRate;
    gState.compressionCount = local.compressionCount;
    gState.compressionInCycle = local.compressionInCycle;
    gState.wristAlignmentAngle = local.wristAlignmentAngle;
    gState.wristFlexionAngle = local.wristFlexionAngle;
    gState.compressionAxisDeviation = local.compressionAxisDeviation;
    gState.depthTrend = local.depthTrend;
    gState.recoilAchieved = local.recoilAchieved;
    gState.leaningDetected = local.leaningDetected;
    gState.overForceFlag = local.overForceFlag;
    gState.postureOk = local.postureOk;
    gState.fatigueFlag = local.fatigueFlag;
    gState.rescuerFatigueScore = local.rescuerFatigueScore;
    gState.imuCalibrated = local.imuCalibrated;
    gState.wristDropped = local.wristDropped;
    gState.valleyDepth = local.valleyDepth;
    gState.totalCompressions = local.totalCompressions;
    gState.correctDepth = local.correctDepth;
    gState.correctFrequency = local.correctFrequency;
    gState.correctRecoil = local.correctRecoil;
    gState.depthRateCombo = local.depthRateCombo;
    gState.correctPosture = local.correctPosture;
    gState.leaningCount = local.leaningCount;
    gState.overForceCount = local.overForceCount;
    gState.tooDeepCount = local.tooDeepCount;
    gState.fatigueOnsetIndex = local.fatigueOnsetIndex;
    gState.peakDepth = local.peakDepth;
    gState.peakTimestampMs = local.peakTimestampMs;
    gState.valleyTimestampMs = local.valleyTimestampMs;
    gState.timeToFirstCompressionMs = local.timeToFirstCompressionMs;
    gState.lastPeakDepthCm     = local.lastPeakDepthCm;
    gState.lastPeakConfidence  = local.lastPeakConfidence;
    gState.lastPeakDepthSource = local.lastPeakDepthSource;
    portEXIT_CRITICAL(&gStateMux);

    // Maintain 100Hz: delay remainder of 10ms slot
    unsigned long elapsed = (micros() - nowMicros);
    long remaining = 10000L - (long)elapsed;
    if (remaining > 1000) delayMicroseconds(remaining - 500);
  }
}

// ── COMMS TASK (Core 0, ~various rates) ──────────────────────────────────────
static void commsTask(void* pv) {
  unsigned long lastLiveMs = 0;
  unsigned long lastNeoMs = 0;
  unsigned long lastBatMs = 0;
  unsigned long lastVitalsMs = 0;

  while (true) {
    unsigned long now = millis();

    if (_pendingModeChange) {
      _pendingModeChange = false;
      GloveMode m = _pendingMode;
      motorPulse(MOTOR_MEDIUM_MS);
      neoModeChange(m);
    }

    // ── Offline session chunk drip-feed ─────────────────────────────────────
    // Two concerns: (1) never block commsTask — a full session is up to 136
    // chunks at ~50 ms apart = 7 s, and during a live session commsTask must
    // keep ticking (audio, NeoPixel, LIVE_STREAM, button). (2) never overrun
    // EVENT_QUEUE_DEPTH — bleQueueEvent has a 50 ms timeout but if the queue
    // is full we drop chunks. So: one chunk per ~50 ms.
    //
    // Start a new stream when idle and there's a queued request.
    if (_chunkSendCursor == 0 && _sessReqHead != _sessReqTail) {
      uint8_t idx = _sessReqQ[_sessReqTail];
      _sessReqTail = (_sessReqTail + 1) % SESSION_REQ_QUEUE;
      uint8_t total = storageTotalChunks(idx);
      if (total > 0) {
        _chunkSendIdx = idx;
        _chunkSendTotal = total;
        _chunkSendCursor = 1;  // cursor-1 is the next chunk index
        _lastChunkSendMs = 0;  // fire first chunk immediately
      }
    }

    // Stream one chunk every ~50 ms.
    if (_chunkSendCursor > 0 && (now - _lastChunkSendMs) >= 50) {
      uint8_t c = _chunkSendCursor - 1;
      uint8_t payload[STORAGE_CHUNK_PAYLOAD];
      uint8_t total = storageReadChunk(_chunkSendIdx, c, payload);
      if (total > 0 && total == _chunkSendTotal) {
        bleQueueEvent(bleBuildLocalSessionChunk(_chunkSendIdx, c, total, payload));
        _lastChunkSendMs = now;
        _chunkSendCursor = (c + 1 < total) ? (c + 2) : 0;  // 0 = done
      } else {
        _chunkSendCursor = 0;  // read error → abort
      }
    }

    if (_pendingScenarioChange) {
      _pendingScenarioChange = false;
      Scenario sc = _pendingScenario;
      motorPattern(MOTOR_SHORT_MS, MOTOR_SHORT_MS, 2);
      neoScenarioChange(sc);
    }

    if (_pendingConfirmMask != 0) {
      // Snapshot and clear atomically so a new confirm arriving mid-loop
      // doesn't get dropped.
      uint32_t m;
      portENTER_CRITICAL(&gStateMux);
      m = _pendingConfirmMask;
      _pendingConfirmMask = 0;
      portEXIT_CRITICAL(&gStateMux);
      for (int i = 0; i < STORAGE_MAX_SESSIONS; i++) {
        if (m & (1u << i)) storageMarkSynced(i);
      }
    }

    if (_pendingStart) {
      _pendingStart = false;
      startSession();
    }
    if (_pendingStop) {
      _pendingStop = false;
      stopSession();
    }
    if (_pendingSelftest) {
      _pendingSelftest = false;
      // Belt-and-braces — a session could have started between the command
      // arriving and the dispatcher running. The dispatcher above already
      // gates, but worth a second check given how disruptive a mid-session
      // mutex hold would be.
      if (!_sessionRunning && !_inPulseCheck && !_inVentWindow) {
        runSelftest();
      }
    }

    if (_pendingCalibrate) {
      _pendingCalibrate = false;
      if (!_sessionRunning && !_inPulseCheck && !_inVentWindow) {
        runCalibration();
      }
    }

    // ── Selftest (1.5s after BLE connect) — TEMP DISABLED while debugging TCA
    if (_selftestPending && !_selftestDone && bleConnected()) {
      if (now - _connectMs >= SELFTEST_DELAY_MS) {
        _selftestDone = true;
        _selftestPending = false;
        // runSelftest();   // TEMP: disabled

        // Check for pending offline sessions  (KEEP this — unrelated to selftest)
        uint8_t pending = storagePendingCount();
        if (pending > 0) {
          bleQueueEvent(bleBuildPendingLocalData(pending));
        }
      }
    }

    // ── Button ─────────────────────────────────────────────────────────────
    ButtonEvent btn = buttonUpdate();
    if (diagActive && btn != ButtonEvent::None) {
      diagActionResult = 0x10 | (uint8_t)btn;  // 0x10..0x1F for button events
    }
    if (btn == ButtonEvent::LongPress) {
      if (_sessionRunning) stopSession();
      else startSession();
    } else if (btn == ButtonEvent::DoubleTap) {
      // Cycle mode
      SharedState snap = snapshotState();
      GloveMode next = (GloveMode)(((int)snap.currentMode + 1) % 3);
      portENTER_CRITICAL(&gStateMux);
      gState.currentMode = next;
      const bool fbOn = (next != GloveMode::NoFeedback);
      gState.audioFeedbackEnabled = fbOn;
      gState.hapticFeedbackEnabled = fbOn;
      gState.visualFeedbackEnabled = fbOn;
      portEXIT_CRITICAL(&gStateMux);
      bleQueueEvent(bleBuildModeChange(next, 0));  // trigger=0 (button)
      const uint8_t audioTrack[] = { AUDIO_MODE_EMERGENCY, AUDIO_MODE_TRAINING, AUDIO_MODE_NOFEEDBACK };
      audioPlay(audioTrack[(int)next], AUDIO_PRI_MODE_CHANGE);
      motorPulse(MOTOR_MEDIUM_MS);
      neoModeChange(next);
    } else if (btn == ButtonEvent::TripleTap) {
      // Cycle scenario (works in and out of session)
      SharedState snap = snapshotState();
      Scenario next = (snap.currentScenario == Scenario::Adult)
                        ? Scenario::Pediatric
                        : Scenario::Adult;
      portENTER_CRITICAL(&gStateMux);
      gState.currentScenario = next;
      gState.targetDepthMinMM = (next == Scenario::Pediatric) ? TARGET_DEPTH_MIN_PEDS : TARGET_DEPTH_MIN_ADULT;
      gState.targetDepthMaxMM = (next == Scenario::Pediatric) ? TARGET_DEPTH_MAX_PEDS : TARGET_DEPTH_MAX_ADULT;
      portEXIT_CRITICAL(&gStateMux);
      bleQueueEvent(bleBuildScenarioChange(next, 0));
      audioPlay((next == Scenario::Pediatric) ? AUDIO_SCENARIO_PEDS : AUDIO_SCENARIO_ADULT,
                AUDIO_PRI_MODE_CHANGE);
      motorPattern(MOTOR_SHORT_MS, MOTOR_SHORT_MS, 2);
      neoScenarioChange(next);
    }

    // ── Session events ──────────────────────────────────────────────────────
    if (_sessionRunning) {
      SharedState snap = snapshotState();

      // Ventilation window: compressionInCycle just reset to 0 after hitting limit
      if (snap.compressionCount > _lastCompCount) {
        _lastCompCount = snap.compressionCount;
        _lastCompressionMs = millis();
        if (_inUnplannedPause) {
          _inUnplannedPause = false;
          _lastMetronomeMs = millis();
          depthSkipNextRate();  // first comp after a no-flow pause spans the gap
        }
        handleQualityAudio(snap);
      }

      // Inactivity timeout — separate block, not inside the compression detection
      if ((millis() - _lastCompressionMs) > SESSION_INACTIVITY_TIMEOUT_MS && !_inPulseCheck && !_inVentWindow) {
        stopSession();
      }

      // Detect unplanned pause — but NOT at the planned ventilation boundary.
      // When compressionInCycle is at/over the vent limit (or just wrapped to 0),
      // the rescuer is correctly pausing to ventilate; that is not a no-flow event.
      uint8_t _vc = snap.ventilationCompressions;
      bool _atVentBoundary = (_vc > 0 && (snap.compressionInCycle == 0 || snap.compressionInCycle >= _vc));
      if (!_inPulseCheck && !_inVentWindow && _sessionRunning && !_atVentBoundary && (millis() - _lastCompressionMs) > UNPLANNED_PAUSE_THRESHOLD_MS && !_inUnplannedPause) {
        _inUnplannedPause = true;
        portENTER_CRITICAL(&gStateMux);
        gState.noFlowIntervals++;
        portEXIT_CRITICAL(&gStateMux);
      }

      // Ventilation window detection: fires on whichever edge arrives first —
      // the exact reach (compressionInCycle == ventComps, if the comms task
      // catches that 10 ms window) OR the wrap-to-zero on the next completed
      // compression. The wrap is the reliable fallback because depth.cpp resets
      // compressionInCycle to 0 on the next compression; if the rescuer pauses
      // to ventilate correctly, no next compression comes and the reach edge
      // is the only one that fires. Both edges are gated on compressionCount
      // changing so the window only opens once per cycle.
      uint8_t ventComps = snap.ventilationCompressions;

// Dual-edge trigger: fires on the exact reach (compressionInCycle == ventComps)
// OR on the wrap-to-zero that follows it. The wrap is the reliable signal
// because depth.cpp resets to 0 on the *next* compression — the limit value
// only exists for one 10 ms tick and the comms task (running on Core 0 at
// lower priority) can easily miss it if the sensor task completes two
// compressions between comms ticks.
bool cycleReached = (ventComps > 0
    && snap.compressionCount > 0
    && snap.compressionCount != _lastCycleCount
    && ((_lastCompInCycle > 0 && snap.compressionInCycle == 0)            // wrap edge
        || (snap.compressionInCycle >= ventComps && _lastCompInCycle < ventComps))); // reach edge

      _lastCompInCycle = snap.compressionInCycle;
      if (!_inVentWindow && cycleReached) {
        _lastCycleCount = snap.compressionCount;
        _ventCycleNum++;
        _lastMetronomeMs = millis();
        _inVentWindow = true;
        _ventWindowOpenMs = millis();
        _ventWindowOpenAtCount = snap.compressionCount;
        _ventCompsAtGraceEnd = UINT32_MAX;  // reset grace latch for this new window
        _ventPauseSeen = false;
        _ventResumePromptPlayed = false;
        _ventLongestGapMs = 0;  // longest no-comp gap seen this window
        portENTER_CRITICAL(&gStateMux);
        gState.ventilationCount = _ventCycleNum;
        gState.totalVentilations = _ventCycleNum;
        gState.inVentilationWindow = true;
        gState.rescuerHRLastPause = gState.heartRateUser;
        gState.rescuerSpO2LastPause = gState.spO2User;
        portEXIT_CRITICAL(&gStateMux);
        bleQueueEvent(bleBuildVentilationWindow(_ventCycleNum, snap.ventilationBreaths));
        if (snap.audioFeedbackEnabled) audioPlay(AUDIO_GIVE_TWO_BREATHS, AUDIO_PRI_VENTILATION);
        if (snap.hapticFeedbackEnabled) motorPattern(MOTOR_VENT_ON_MS, MOTOR_VENT_OFF_MS, MOTOR_VENT_REPS);
        if (_storedVentCount < STORAGE_MAX_VENTILATIONS) {
          StoredVentilation& v = _storedVents[_storedVentCount++];
          v.timestampMs = millis() - _sessionStartMs;
          v.cycleNumber = _ventCycleNum;
          v.ventilationsGiven = 0;  // updated when window closes
          v.durationMs = 0;
          v.compliant = 0;
        }
      }
      // Ventilation window — SAME mechanism as pulse check (decision: unified).
      // Closes when EITHER:
      //   (a) ≥ WINDOW_NONCOMPLIANT_COMP_COUNT comps with no real pause
      //       → non-compliant dismiss, OR
      //   (b) a real pause (≥ WINDOW_PAUSE_COMPLIANT_MS no compression) occurred
      //       AND the rescuer then did ≥ WINDOW_RESUME_COMP_COUNT comps
      //       → compliant close, OR
      //   (c) WINDOW_MAX_BACKSTOP_MS elapsed → hard close.
      // The grace period still applies so mid-rhythm reflex comps right after
      // the prompt don't instantly trip the non-compliant counter.
      if (_inVentWindow) {
        unsigned long windowMs = millis() - _ventWindowOpenMs;
        unsigned long sinceLastComp = millis() - _lastCompressionMs;
        uint32_t compsSinceOpen = snap.compressionCount - _ventWindowOpenAtCount;
        bool pastGrace = (windowMs >= VENTILATION_GRACE_MS);

        // A real pause = ≥ WINDOW_PAUSE_COMPLIANT_MS with no new compression
        // while the window is open. Latch it once it ever happens.
        // Track the LONGEST no-compression gap anywhere in the window. A real
        // ventilation pause counts even if stray rhythm-carryover comps occur
        // before or after it (those just reset sinceLastComp, not the max).
        if (sinceLastComp > _ventLongestGapMs) _ventLongestGapMs = sinceLastComp;
        if (!_ventPauseSeen && _ventLongestGapMs >= WINDOW_PAUSE_COMPLIANT_MS) {
          _ventPauseSeen = true;
        }

        // Latch compression count at the moment grace ends, so resume comps
        // are counted only AFTER grace (reflex over-shoot excluded).
        if (pastGrace && _ventCompsAtGraceEnd == UINT32_MAX)
          _ventCompsAtGraceEnd = snap.compressionCount;
        uint32_t compsAfterGrace =
          (pastGrace && _ventCompsAtGraceEnd != UINT32_MAX)
            ? (snap.compressionCount - _ventCompsAtGraceEnd)
            : 0;

       // Only declare non-compliant AFTER the grace period and using
        // post-grace compressions — reflex comps in the first 2.5 s must not
        // count, and the rescuer must get the full chance to register a pause.
        bool nonCompliantDismiss =
          pastGrace && !_ventPauseSeen && (compsAfterGrace >= WINDOW_NONCOMPLIANT_COMP_COUNT);
        bool compliantClose =
          _ventPauseSeen && (compsAfterGrace >= WINDOW_RESUME_COMP_COUNT);
        bool backstopClose = (windowMs >= WINDOW_MAX_BACKSTOP_MS);

        // Resume-compressions voice prompt: once, at WINDOW_RESUME_PROMPT_MS,
        // if still in the window.
        if (!_ventResumePromptPlayed && windowMs >= WINDOW_RESUME_PROMPT_MS) {
          _ventResumePromptPlayed = true;
          if (snap.audioFeedbackEnabled && (backstopClose || nonCompliantDismiss)) audioPlay(AUDIO_RESUME_COMPRESSIONS, AUDIO_PRI_VENTILATION);
        }

        if (nonCompliantDismiss || compliantClose || backstopClose) {
          _inVentWindow = false;
          uint32_t compsDuringWindow =
            snap.compressionCount - _ventWindowOpenAtCount;
          bool complied = _ventPauseSeen && !nonCompliantDismiss;
          portENTER_CRITICAL(&gStateMux);
          gState.inVentilationWindow = false;
          if (complied) gState.correctVentilations++;
          portEXIT_CRITICAL(&gStateMux);
          if (_storedVentCount > 0) {
            StoredVentilation& v = _storedVents[_storedVentCount - 1];
            v.durationMs = windowMs;
            v.ventilationsGiven = (uint8_t)constrain((int)compsDuringWindow, 0, 255);
            v.compliant = complied ? 1 : 0;
          }
          if (snap.audioFeedbackEnabled) audioPlay(AUDIO_RESUME_COMPRESSIONS, AUDIO_PRI_VENTILATION);
          _lastCompressionMs = millis();
          depthSkipNextRate();
          // The next compression's interval spans the entire pause, producing
          // a meaningless slow rate. Discard it so it never reaches grading.
        }
      }

      // Pulse check (Emergency mode only)
      if (snap.currentMode == GloveMode::Emergency) {
        if (!_inPulseCheck && (now - _lastPulseCheckMs) >= PULSE_CHECK_INTERVAL_MS) {
          _lastPulseCheckMs = now;
          _pulseCheckCount++;
          _lastMetronomeMs = millis();
          _inPulseCheck = true;
          _pulseResultSent = false;
          _pulseCheckOpenAtCount = snap.compressionCount;
          _pulseResumePromptPlayed = false;
          _pulsePauseSeen = false;
          portENTER_CRITICAL(&gStateMux);
          gState.pulseCheckActive = true;
          gState.pulseChecksPrompted++;
          portEXIT_CRITICAL(&gStateMux);
          bleQueueEvent(bleBuildPulseCheckStart(
            _pulseCheckCount,
            (uint32_t)(now - _sessionStartMs)));
          if (snap.audioFeedbackEnabled) audioPlay(AUDIO_CHECK_PULSE, AUDIO_PRI_PULSE_CHECK);
          if (snap.hapticFeedbackEnabled) motorPulse(MOTOR_LONG_MS);
        max30102ResetPatientDetectors();
          _pulseCheckStartMs = now;
          _pulseCheckWarmupEndMs = now + 2000UL;
          portENTER_CRITICAL(&gStateMux);
          gState.rescuerHRLastPause = gState.heartRateUser;
          gState.rescuerSpO2LastPause = gState.spO2User;
          portEXIT_CRITICAL(&gStateMux);
        }

        // Resume-compressions voice prompt: once, at WINDOW_RESUME_PROMPT_MS.
if (_inPulseCheck && !_pulseResumePromptPlayed && (now - _pulseCheckStartMs) >= WINDOW_RESUME_PROMPT_MS) {
            _pulseResumePromptPlayed = true;
          if (snap.audioFeedbackEnabled) audioPlay(AUDIO_RESUME_COMPRESSIONS, AUDIO_PRI_PULSE_CHECK);
        }

        // Window CLOSE — IDENTICAL logic to the ventilation window:
        //   (a) ≥ WINDOW_NONCOMPLIANT_COMP_COUNT comps, no real pause → dismiss
        //   (b) a real pause (≥ WINDOW_PAUSE_COMPLIANT_MS) occurred AND
        //       ≥ WINDOW_RESUME_COMP_COUNT comps after → compliant close
        //   (c) WINDOW_MAX_BACKSTOP_MS elapsed → hard close.
        // Never closes on a fixed timer alone; never closes because a beat
        // was found — the result is computed AT close, waveform keeps
        // streaming until the window actually closes.
        {
          unsigned long pcWindowMs = now - _pulseCheckStartMs;
          unsigned long sinceLastComp = millis() - _lastCompressionMs;
          uint32_t compsSinceOpen = (_inPulseCheck)
                                      ? (snap.compressionCount - _pulseCheckOpenAtCount)
                                      : 0;

          if (!_pulsePauseSeen && _inPulseCheck && sinceLastComp >= WINDOW_PAUSE_COMPLIANT_MS) {
            _pulsePauseSeen = true;
          }

          bool pcNonCompliant =
            !_pulsePauseSeen && (compsSinceOpen >= WINDOW_NONCOMPLIANT_COMP_COUNT);
          bool pcCompliantClose =
            _pulsePauseSeen && (compsSinceOpen >= WINDOW_RESUME_COMP_COUNT);
          bool pcBackstop = (pcWindowMs >= WINDOW_MAX_BACKSTOP_MS);

          bool pcClose =
            _inPulseCheck && !_pulseResultSent && (pcNonCompliant || pcCompliantClose || pcBackstop);

          if (pcClose) {
            _pulseResultSent = true;
            _inPulseCheck = false;
            portENTER_CRITICAL(&gStateMux);
            gState.pulseCheckActive = false;
            _lastCompressionMs = millis();
            portEXIT_CRITICAL(&gStateMux);

            snap = snapshotState();

            // Patient HR computed from refractory-gated beat count over the
            // ACTUAL elapsed window (decision 1a) — NOT the fixed constant —
            // because the window now closes at a variable time.
            const float windowSecs = (float)pcWindowMs / 1000.0f;
            const float estimatedBpm = (windowSecs > 0.5f && snap.detectorBCount > 0)
                                         ? (float)snap.detectorBCount * 60.0f / windowSecs
                                         : 0.0f;

            uint8_t cls = max30102ClassifyPulse(
              estimatedBpm, snap.ppgSignalQuality,
              snap.detectorACount, snap.detectorBCount);

            bleQueueEvent(bleBuildPulseCheckResult(
              cls, estimatedBpm, snap.ppgSignalQuality,
              snap.detectorACount, snap.detectorBCount));

            if (_storedPulseCount < STORAGE_MAX_PULSE_CHECKS) {
              StoredPulseCheck& p = _storedPulses[_storedPulseCount++];
              p.timestampMs = _pulseCheckStartMs - _sessionStartMs;
              p.intervalNumber = (uint8_t)constrain((int)_pulseCheckCount, 0, 255);
              p.classification = cls;
              p.detectedBPM = estimatedBpm;
              p.confidence = snap.ppgSignalQuality;
              p.detectorACount = snap.detectorACount;
              p.detectorBCount = snap.detectorBCount;
            }

            // "Complied" = user actually held the carotid sensor long enough
            // to get a usable signal (regardless of whether a pulse was found).
            // Distinguishes real attempts from windows where the rescuer ignored
            // the prompt.
            if (snap.ppgSignalQuality >= 40) {
              portENTER_CRITICAL(&gStateMux);
              gState.pulseChecksComplied++;
              portEXIT_CRITICAL(&gStateMux);
            }

            const uint8_t audioMap[] = { AUDIO_NO_PULSE, AUDIO_PULSE_UNCERTAIN, AUDIO_PULSE_DETECTED };
            uint8_t clsIdx = (cls > 2) ? 1 : cls;  // safety: clamp unexpected values to "Uncertain"
            if (snap.audioFeedbackEnabled) audioPlay(audioMap[clsIdx], AUDIO_PRI_PULSE_CHECK);

            if (cls == PULSE_PRESENT) {
              portENTER_CRITICAL(&gStateMux);
              gState.pulseDetected = true;
              portEXIT_CRITICAL(&gStateMux);
            }
          }
        }
      }

      // Two-minute swap alert
      if ((now - _lastTwoMinMs) >= TWO_MIN_ALERT_INTERVAL_MS) {
        _lastTwoMinMs = now;
        _twoMinCount++;
        _lastMetronomeMs = millis();  // reset metronome after swap pulse
        portENTER_CRITICAL(&gStateMux);
        gState.rescuerSwapCount = _twoMinCount;
        portEXIT_CRITICAL(&gStateMux);
        bleQueueEvent(bleBuildTwoMinAlert(_twoMinCount));
        if (snap.audioFeedbackEnabled) audioPlay(AUDIO_TWO_MIN_SWITCH, AUDIO_PRI_SWAP);
        if (snap.hapticFeedbackEnabled) motorPulse(MOTOR_LONG_MS);
      }

      // Fatigue alert — send once when fatigue flag first appears
      if (!_fatigueSent && snap.fatigueFlag) {
        _fatigueSent = true;
        _lastTwoMinMs = millis();  // restart the 2-min cycle from the fatigue swap
        bleQueueEvent(bleBuildFatigueAlert(snap.rescuerFatigueScore));
        if (snap.audioFeedbackEnabled) audioPlay(AUDIO_FATIGUE_SWITCH, AUDIO_PRI_FATIGUE);
        if (snap.hapticFeedbackEnabled) motorPulse(MOTOR_LONG_MS);
      }

      // Rate metronome (feedback enabled, not in pulse check or vent)
      bool _inAnyPause = _inPulseCheck || _inVentWindow;
      if (snap.hapticFeedbackEnabled && !_inAnyPause && _sessionRunning) {
        float targetBpm = (snap.targetRateMin + snap.targetRateMax) / 2.0f;
        uint32_t metPeriodMs = (uint32_t)(60000.0f / targetBpm);
        if (now - _lastMetronomeMs >= metPeriodMs) {
          _lastMetronomeMs = now;
          motorMetronomeTick();
        }
      }
    }

    // ── Clicker — fires once per compression at depth threshold crossing ────
    // Runs every comms tick (~10 ms) so latency from threshold crossing to
    // click is ≤ 10 ms + DFPlayer command time (~50 ms).
    if (depthClickJustTriggered()) {
      SharedState clickSnap = snapshotState();
      if (clickSnap.sessionActive) {
        if (clickSnap.audioFeedbackEnabled) audioClick();
        if (clickSnap.hapticFeedbackEnabled) motorPulse(20);
      }
    }

    // ── LIVE_STREAM at 25Hz ─────────────────────────────────────────────────
    if (bleConnected() && (now - lastLiveMs) >= LIVE_STREAM_INTERVAL_MS) {
      lastLiveMs = now;
      SharedState snap = snapshotState();
      bleSendLiveStream(snap);
    }

    // ── NeoPixel at 20Hz ────────────────────────────────────────────────────
    if (now - lastNeoMs >= NEO_UPDATE_INTERVAL_MS) {
      lastNeoMs = now;
      SharedState snap = snapshotState();
      neoUpdate(snap);
    }

    // Drain the rescuer PPG FIFO at ~200 ms. The 32-sample FIFO holds 320 ms
    // of data at 100 Hz, so 200 ms never overflows it, and the synthetic
    // per-sample clock inside max30102ServiceRescuer() keeps RR timing exact
    // across the burst. Draining slower than this is required so we do NOT
    // contend with sensorTask's 100 Hz IMU read on gI2CMutex (which would
    // inflate sensorTask's dt and corrupt the depth integral).
    static unsigned long lastRescuerDrainMs = 0;
    if (now - lastRescuerDrainMs >= 200) {
      lastRescuerDrainMs = now;
      xSemaphoreTake(gI2CMutex, portMAX_DELAY);
      max30102ServiceRescuer();
      xSemaphoreGive(gI2CMutex);
    }

    // ── Vitals (rescuer: every 500ms; patient: only during pulse check) ─────
    if (now - lastVitalsMs >= 500) {
      lastVitalsMs = now;
      float hr = 0, spo2 = 0;
      uint8_t sq = 0, rmssd = 0, pi = 0;
      // All I²C reads first, under the mutex only.
      xSemaphoreTake(gI2CMutex, portMAX_DELAY);
      max30102UpdateRescuer(hr, spo2, sq, rmssd, pi);
      float rTemp = 0, rHum = 0;
      bool gxOk = gxht30Read(rTemp, rHum);
      xSemaphoreGive(gI2CMutex);

      // Then write shared state — spinlock NEVER held while holding the mutex.
      portENTER_CRITICAL(&gStateMux);
      gState.heartRateUser = hr;
      gState.spO2User = spo2;
      gState.rescuerSignalQuality = sq;
      gState.rescuerRMSSD = rmssd;
      gState.rescuerPI = pi;
      if (gxOk) {
        gState.rescuerTemperature = rTemp;
        gState.rescuerHumidity = rHum;
      }
      portEXIT_CRITICAL(&gStateMux);
      // Patient temp: ONLY meaningful during pulse check, when the glove
      // fingertip (carrying the MAX30205) is placed on the patient's carotid.



      SharedState snap = snapshotState();
      if (snap.pulseCheckActive || diagActive) {
        // 1. Read PPG (HR + SpO2 + signal quality)
        float phr = 0, pspo2 = 0, ppg = 0;
        uint8_t psq = 0, ppi = 0, detA = 0, detB = 0;
        xSemaphoreTake(gI2CMutex, portMAX_DELAY);
        max30102UpdatePatient(phr, pspo2, ppg, psq, ppi, detA, detB);

        // Suppress beat counts during BPF warmup — filter needs ~2s to settle.
        if (millis() < _pulseCheckWarmupEndMs) {
          detA = 0;
          detB = 0;
          max30102ResetPatientDetectors();
        }

        // 2. Read carotid skin temp from MAX30205 (same fingertip)
        float patTemp = max30205ReadCelsius();
        xSemaphoreGive(gI2CMutex);

        portENTER_CRITICAL(&gStateMux);
        gState.heartRatePatient = phr;
        gState.spO2Patient = pspo2;
        gState.ppgRaw = ppg;
        gState.ppgSignalQuality = psq;
        gState.perfusionIndex = ppi;
        gState.detectorACount = detA;
        gState.detectorBCount = detB;

        // Patient temp validity: skin contact confirmed by IR DC level (sensor covered),
        // independent of PPG pulsatility — a pulseless patient still has warm skin.
        bool contactOk = (gState.ppgRaw > 0.08f);  // ppgRaw is IR/262144, 0.08 ≈ 21000 raw
        if (contactOk && patTemp > 0) {
          gState.patientTemperature = patTemp;
          gState.patientTemperatureLastPulseCheck = patTemp;
        }
        portEXIT_CRITICAL(&gStateMux);
      }
    }

    // ── Battery every 5s ────────────────────────────────────────────────────
    if (now - lastBatMs >= 5000) {
      lastBatMs = now;
      batteryUpdate();
      portENTER_CRITICAL(&gStateMux);
      gState.batteryPercentage = batteryPercent();
      gState.isCharging = batteryCharging();
      portEXIT_CRITICAL(&gStateMux);
    }

    // ── BLE event queue ─────────────────────────────────────────────────────
    bleDrainEventQueue();

    // ── Audio update (playback-finished detection) ───────────────────────────
    audioUpdate();

    vTaskDelay(pdMS_TO_TICKS(10));  // 100Hz equivalent for comms loop
  }
}

void i2cBusRecover(uint8_t sdaPin, uint8_t sclPin) {
  pinMode(sclPin, OUTPUT_OPEN_DRAIN);
  pinMode(sdaPin, INPUT_PULLUP);
  delayMicroseconds(10);

  // If SDA is stuck low, clock up to 9 pulses to free it
  for (int i = 0; i < 9; i++) {
    if (digitalRead(sdaPin) == HIGH) break;
    digitalWrite(sclPin, LOW);
    delayMicroseconds(5);
    digitalWrite(sclPin, HIGH);
    delayMicroseconds(5);
  }

  // Generate a STOP condition: SDA low → high while SCL is high
  pinMode(sdaPin, OUTPUT_OPEN_DRAIN);
  digitalWrite(sdaPin, LOW);
  delayMicroseconds(5);
  digitalWrite(sclPin, HIGH);
  delayMicroseconds(5);
  digitalWrite(sdaPin, HIGH);
  delayMicroseconds(5);

  pinMode(sdaPin, INPUT);
  pinMode(sclPin, INPUT);
}

// ── setup() ──────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n[CPR Glove] Booting firmware v1.0...");
// PIN_EN_CONTROL (GPIO26) must NEVER be driven by the MCU. The physical
// switch shorts PowerBoost EN to GND for power-off; the external pull-up
// (recommend 10k, not 100k) restores EN high on switch-open. Keep this pin
// permanently high-impedance so the GPIO can never latch EN low and block
// a restart. Do not add digitalWrite() to this pin anywhere.
#if MANIKIN_CALIBRATION_LOG
  Serial.println(F("CALIB,n,peakF_N,palmMM,wristMM,imuMM,forceMM,calibK,finalMM,strokeMs"));
#endif
  pinMode(PIN_EN_CONTROL, INPUT);
  // Initialise shared state
  memset(&gState, 0, sizeof(gState));
  gState.currentMode = GloveMode::Emergency;
  gState.currentScenario = Scenario::Adult;
  gState.audioFeedbackEnabled = true;
  gState.hapticFeedbackEnabled = true;
  gState.visualFeedbackEnabled = true;
  gState.targetDepthMinMM = TARGET_DEPTH_MIN_ADULT;
  gState.targetDepthMaxMM = TARGET_DEPTH_MAX_ADULT;
  gState.targetRateMin = TARGET_RATE_MIN;
  gState.targetRateMax = TARGET_RATE_MAX;
  gState.ventilationCompressions = VENTILATION_CYCLE_COMPRESSIONS;
  gState.ventilationBreaths = VENTILATION_BREATHS_EXPECTED;

  // I²C

  gI2CMutex = xSemaphoreCreateMutex();
  if (gI2CMutex == nullptr) {
    Serial.println("[CRITICAL] I2C mutex alloc failed — halting");
    while (true) { delay(1000); }
  }

  // ── I²C bus recovery: unstick any slave holding SDA low ──────────────────
  // A peripheral mid-transaction (after a brown-out or aborted reset) may be
  // pulling SDA low. The only escape is to manually clock SCL 9 times so the
  // slave finishes its byte and releases SDA, then issue a STOP.
  pinMode(PIN_SCL, OUTPUT_OPEN_DRAIN);
  pinMode(PIN_SDA, INPUT_PULLUP);
  digitalWrite(PIN_SCL, HIGH);
  delayMicroseconds(10);
  if (digitalRead(PIN_SDA) == LOW) {
    Serial.println("[BOOT] SDA stuck LOW at startup — recovering bus...");
    for (int i = 0; i < 16; i++) {
      digitalWrite(PIN_SCL, LOW);
      delayMicroseconds(5);
      digitalWrite(PIN_SCL, HIGH);
      delayMicroseconds(5);
      if (digitalRead(PIN_SDA) == HIGH) {
        Serial.printf("[BOOT] SDA released after %d clock(s)\n", i + 1);
        break;
      }
    }

    pinMode(PIN_SDA, OUTPUT_OPEN_DRAIN);
    digitalWrite(PIN_SDA, LOW);
    delayMicroseconds(5);
    digitalWrite(PIN_SCL, HIGH);
    delayMicroseconds(5);
    digitalWrite(PIN_SDA, HIGH);
    delayMicroseconds(5);
    Serial.printf("[BOOT] SDA final state: %s\n",
                  digitalRead(PIN_SDA) == HIGH ? "HIGH (ok)" : "STILL LOW (HW issue)");
  } else {
    Serial.println("[BOOT] SDA idle HIGH — bus clean.");
  }
  pinMode(PIN_SDA, INPUT);  // hand back to Wire
  pinMode(PIN_SCL, INPUT);


  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(I2C_FREQ);
  delay(100);

  // ── TCA9548A probe — diagnose immediately if it doesn't respond ──────────
  Wire.beginTransmission(TCA_ADDRESS);
  uint8_t tcaErr = Wire.endTransmission();
  Serial.printf("[BOOT] TCA9548A @ 0x%02X probe: err=%u (0=OK, 2=NACK, 5=timeout)\n",
                TCA_ADDRESS, tcaErr);
  if (tcaErr != 0) {
    // Try clearing channel state and probing again
    Wire.beginTransmission(TCA_ADDRESS);
    Wire.write(0);
    uint8_t e2 = Wire.endTransmission();
    Serial.printf("[BOOT] TCA9548A retry after disable: err=%u\n", e2);
  }
  // Peripherals
  neoInit();
  motorInit();
  buttonInit();
  batteryInit();

  // Storage
  if (!storageInit()) Serial.println("[WARN] LittleFS failed — offline storage unavailable");

  // Audio
  audioInit();

  // Sensors
  bool palmOk = imuInit();
  if (!palmOk) Serial.println("[CRITICAL] Palm IMU failed!");

  depthInit();

  // Force baseline (blocking — 50 samples × 10ms = ~500ms)
  Serial.println("[BOOT] Force baseline calibration...");
  {
    int _forceRetry = 0;
    while (!forceBaselineReady() && _forceRetry < 200) {
      forceInit();
      delay(10);
      _forceRetry++;
    }
    if (!forceBaselineReady()) Serial.println("[WARN] Force baseline failed — using default");
  }

  // Optical sensors
  max30102Init();
  max30205Init();
  gxht30Init();

  // BLE
  bleInit();

  Serial.println("[BOOT] Done. Advertising as CPR_Glove.");

  // Start tasks
  xTaskCreatePinnedToCore(sensorTask, "SensorTask",
                          TASK_SENSOR_STACK, nullptr, TASK_SENSOR_PRIORITY, nullptr, TASK_SENSOR_CORE);

  xTaskCreatePinnedToCore(commsTask, "CommsTask",
                          TASK_COMMS_STACK, nullptr, TASK_COMMS_PRIORITY, nullptr, TASK_COMMS_CORE);
}

void loop() {
#if IMU_TEST_LOG
  while (Serial.available()) {
    char c = Serial.read();
    if (c == 'g' || c == 'G') {
      if (!imuIsCalibrated()) {
        Serial.println(F("ITEST WAIT — IMU gravity not converged yet, try again in a few seconds"));
      } else {
        resetIntegration(integPalm);
        resetIntegration(integWrist);
        _imuTestPalmPeakMM = 0;
        _imuTestWristPeakMM = 0;
        _imuTestStartMs = millis();
        _imuTestActive = true;
        Serial.println(F("ITEST GO — move glove now, 1 second window"));
      }
    }
  }
#endif
  // Everything runs in FreeRTOS tasks. loop() is unused.
  vTaskDelay(portMAX_DELAY);
}

// Accessors for storage.cpp
const StoredVentilation* getStoredVentilations(uint8_t& count) {
  count = _storedVentCount;
  return _storedVents;
}
const StoredPulseCheck* getStoredPulseChecks(uint8_t& count) {
  count = _storedPulseCount;
  return _storedPulses;
}
