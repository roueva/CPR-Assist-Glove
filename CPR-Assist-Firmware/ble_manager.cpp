// =============================================================================
// ble_manager.cpp — BLE GATT server (Spec v3.0)
// =============================================================================
#include "ble_manager.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <freertos/queue.h>
#include <string.h>
#include <math.h>
#include "imu.h"
#include "max30102.h"

static BLEServer* _server = nullptr;
static BLECharacteristic* _liveChar = nullptr;
static BLECharacteristic* _eventChar = nullptr;
static volatile bool _connected = false;
static QueueHandle_t _eventQueue = nullptr;

// ── Pack helpers ──────────────────────────────────────────────────────────────
static void packU16(uint8_t* b, int off, uint16_t v) {
  b[off] = v & 0xFF;
  b[off + 1] = (v >> 8) & 0xFF;
}
static void packU32(uint8_t* b, int off, uint32_t v) {
  b[off] = v & 0xFF;
  b[off + 1] = (v >> 8) & 0xFF;
  b[off + 2] = (v >> 16) & 0xFF;
  b[off + 3] = (v >> 24) & 0xFF;
}
static void packF32(uint8_t* b, int off, float v) {
  uint32_t raw;
  memcpy(&raw, &v, 4);
  packU32(b, off, raw);
}

// ── BLE callbacks ─────────────────────────────────────────────────────────────
class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    _connected = true;
    Serial.println("[BLE] onConnect fired — _connected=true");
    onBLEConnect();
  }
  void onDisconnect(BLEServer*) override {
    _connected = false;
    Serial.println("[BLE] onDisconnect fired — re-advertising");
    onBLEDisconnect();
    BLEDevice::startAdvertising();
  }
};

class EventCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String v = c->getValue();
    if (v.length() == 0) return;
    onAppCommand((uint8_t)v[0],
                 (const uint8_t*)v.c_str(),
                 v.length());
  }
};

// ── Init ──────────────────────────────────────────────────────────────────────
void bleInit() {
  _eventQueue = xQueueCreate(EVENT_QUEUE_DEPTH, sizeof(BLEEventItem));

  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setMTU(BLE_MTU);

  _server = BLEDevice::createServer();
  _server->setCallbacks(new ServerCB());

  BLEService* svc = _server->createService(BLEUUID(BLE_SERVICE_UUID), 15);

  _liveChar = svc->createCharacteristic(BLE_LIVE_STREAM_UUID,
                                        BLECharacteristic::PROPERTY_NOTIFY);
  _liveChar->addDescriptor(new BLE2902());

  _eventChar = svc->createCharacteristic(BLE_EVENT_CHAN_UUID,
                                         BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_WRITE_NR);
  _eventChar->addDescriptor(new BLE2902());
  _eventChar->setCallbacks(new EventCB());

  svc->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(BLE_SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  BLEDevice::startAdvertising();
}

bool bleConnected() {
  return _connected;
}

// ── LIVE_STREAM packet assembly (108 bytes) ───────────────────────────────────
void bleSendLiveStream(const SharedState& s) {
  static uint32_t _skipCount = 0;
  if (!_connected || !_liveChar) {
    if ((++_skipCount % 250) == 0) {
      Serial.printf("[BLE] live skip — connected=%d liveChar=%p\n",
                    _connected ? 1 : 0, _liveChar);
    }
    return;
  }

  uint8_t buf[LIVE_STREAM_SIZE] = { 0 };

  // CORE COMPRESSION (0–23)
  packF32(buf, 0, s.depth);
  packF32(buf, 4, s.frequency);
  packF32(buf, 8, s.force);
  packF32(buf, 12, s.instantaneousRate);
  packU32(buf, 16, (uint32_t)s.compressionCount);
  packU32(buf, 20, (uint32_t)s.compressionInCycle);

  // POSTURE (24–39)
  packF32(buf, 24, s.wristAlignmentAngle);
  packF32(buf, 28, s.wristFlexionAngle);
  packF32(buf, 32, s.compressionAxisDeviation);
  packF32(buf, 36, s.depthTrend);

  // FLAGS (40–55)
  buf[40] = s.recoilAchieved ? 1 : 0;
  buf[41] = s.leaningDetected ? 1 : 0;
  buf[42] = s.overForceFlag ? 1 : 0;
  buf[43] = s.postureOk ? 1 : 0;
  packU32(buf, 44, (uint32_t)s.ventilationCount);
  buf[48] = s.fatigueFlag ? 1 : 0;
  buf[49] = s.rescuerFatigueScore;
  buf[50] = s.imuCalibrated ? 1 : 0;
  buf[51] = s.wristDropped ? 1 : 0;
  packF32(buf, 52, s.residualLoadDepthCm);

  // PATIENT VITALS (56–71) — valid during pulse check ONLY. All patient
  // fields (incl. temperature) are zeroed outside a pulse-check window so
  // the app never receives a stale frozen reading. The "last valid"
  // persistence lives only in patientTemperatureLastPulseCheck (SESSION_END
  // byte 66), which is its proper home.
  if (s.pulseCheckActive || diagActive) {
    packF32(buf, 56, s.heartRatePatient);
    packF32(buf, 60, s.spO2Patient);
    packF32(buf, 64, s.ppgRaw);
    buf[68] = s.ppgSignalQuality;
    buf[69] = s.perfusionIndex;
    // patientTemperature: uint16 fixed-point °C×100. App divides by 100.0.
    uint16_t patTempFixed = (uint16_t)(s.patientTemperature * 100.0f);
    packU16(buf, 70, patTempFixed);
  }

  // RESCUER VITALS (72–87)
  packF32(buf, 72, s.heartRateUser);
  packF32(buf, 76, s.spO2User);
  buf[80] = s.rescuerSignalQuality;
  buf[81] = s.rescuerRMSSD;
  uint16_t resTempFixed = (uint16_t)(s.rescuerTemperature * 100.0f);
  packU16(buf, 82, resTempFixed);
  buf[84] = s.rescuerPI;
  buf[85] = (uint8_t)constrain((int)s.rescuerHumidity, 0, 100);  // 0–100 %
  buf[86] = s.inVentilationWindow ? 1 : 0;
  // byte 87 reserved = 0x00

  // SESSION STATE (88–99)
  buf[88] = s.sessionActive ? 1 : 0;
  buf[89] = s.pulseCheckActive ? 1 : 0;
  buf[90] = (uint8_t)s.currentMode;
  buf[91] = (s.audioFeedbackEnabled  ? 0x01 : 0)
          | (s.hapticFeedbackEnabled ? 0x02 : 0)
          | (s.visualFeedbackEnabled ? 0x04 : 0);
  buf[92] = s.batteryPercentage;
  buf[93] = s.isCharging ? 1 : 0;
  // COMPRESSION TIMESTAMPS (94–101)
  packU32(buf, 94, s.peakTimestampMs);
  packU32(buf, 98, s.valleyTimestampMs);
  packF32(buf, 102, s.lastPeakDepthCm);  // last completed compression's locked peak (cm)
  // Chunk 4 Change 20 — confidence telemetry for the lastPeakDepthCm value:
  //   byte 106: lastPeakConfidence (0–100, overall confidence in the depth)
  //   byte 107: lastPeakDepthSource (DepthSource enum value, 0–7)
  // These let the app display confidence flags ("high/uncertain/...") and
  // let the thesis analysis pipeline see which path produced each number.
  buf[106] = s.lastPeakConfidence;
  buf[107] = s.lastPeakDepthSource;

#if BLE_DEBUG_SERIAL
  static uint32_t _liveLogCount = 0;
  // Throttle: LIVE_STREAM is 10 Hz (Spec v3.1). Log 1 in 25 (~0.4 Hz) to keep Serial readable.
  if ((_liveLogCount++ % 25) == 0) {
    Serial.printf(
      "[LIVE] d=%.1fcm f=%.0fN rate=%.0f cnt=%lu inCyc=%lu "
      "recoil=%d lean=%d over=%d resLoad=%.2fcm | "
      "rHR=%.0f rSpO2=%.0f rSQ=%u rTemp=%.1f rHum=%u | "
      "pulseAct=%d sessAct=%d mode=%u\n",
      s.depth, s.force, s.instantaneousRate,
      (unsigned long)s.compressionCount, (unsigned long)s.compressionInCycle,
      s.recoilAchieved ? 1 : 0, s.leaningDetected ? 1 : 0,
      s.overForceFlag ? 1 : 0, s.residualLoadDepthCm,
      s.heartRateUser, s.spO2User, s.rescuerSignalQuality,
      s.rescuerTemperature, (unsigned)s.rescuerHumidity,
      s.pulseCheckActive ? 1 : 0, s.sessionActive ? 1 : 0,
      (unsigned)s.currentMode);
  }
#endif

  _liveChar->setValue(buf, LIVE_STREAM_SIZE);
  _liveChar->notify();
}

// ── Event queue ───────────────────────────────────────────────────────────────
void bleQueueEvent(const BLEEventItem& item) {
  if (_eventQueue) xQueueSend(_eventQueue, &item, pdMS_TO_TICKS(50));
}

void bleFlushEventQueue() {
  if (_eventQueue) xQueueReset(_eventQueue);
}

void bleDrainEventQueue() {
  if (!_connected || !_eventChar || !_eventQueue) return;
  BLEEventItem item;
  if (xQueueReceive(_eventQueue, &item, 0) == pdTRUE) {
    _eventChar->setValue(item.data, EVENT_CHANNEL_SIZE);

#if BLE_DEBUG_SERIAL
    Serial.printf("[EVENT] type=0x%02X bytes: ", item.data[0]);
    // Print the first 16 bytes — enough to see SESSION_START/END,
    // VENTILATION_WINDOW cycle, pulse-check fields, etc.
    for (int i = 0; i < 16 && i < EVENT_CHANNEL_SIZE; i++)
      Serial.printf("%02X ", item.data[i]);
    Serial.println();
#endif

    _eventChar->notify();
    vTaskDelay(pdMS_TO_TICKS(20));  // brief gap for app BLE stack
  }
}

// ── Packet builders ───────────────────────────────────────────────────────────
static BLEEventItem makeItem(BLEEventType t) {
  BLEEventItem item;
  item.type = t;
  memset(item.data, 0, EVENT_CHANNEL_SIZE);
  return item;
}

BLEEventItem bleBuildSessionStart(GloveMode mode, Scenario sc) {
  auto item = makeItem(BLEEventType::SessionStart);
  item.data[0] = PKT_SESSION_START;
  item.data[1] = (uint8_t)mode;
  item.data[2] = (uint8_t)sc;
  return item;
}

BLEEventItem bleBuildSessionEnd(const SharedState& s) {
  auto item = makeItem(BLEEventType::SessionEnd);
  uint8_t* b = item.data;
  b[0] = PKT_SESSION_END;
  b[1] = (uint8_t)s.currentMode;
  packU32(b, 2, s.totalCompressions);
  packU32(b, 6, s.correctDepth);
  packU32(b, 10, s.correctFrequency);
  packU32(b, 14, s.correctRecoil);
  packU32(b, 18, s.depthRateCombo);
  packU32(b, 22, s.correctPosture);
  packU32(b, 26, s.leaningCount);
  packU32(b, 30, s.overForceCount);
  packU32(b, 34, s.tooDeepCount);
  packU32(b, 38, s.totalVentilations);
  packU32(b, 42, s.correctVentilations);
  packU32(b, 46, s.pulseChecksPrompted);
  packU32(b, 50, s.pulseChecksComplied);
  packU32(b, 54, s.fatigueOnsetIndex);
  packF32(b, 58, s.peakDepth);
  packF32(b, 62, s.compressionDepthSD);
  packF32(b, 66, s.patientTemperatureLastPulseCheck);
  // bytes 70–73 reserved (rescuer wrist temp at start/end captured separately at 82–89)
  packF32(b, 74, s.rescuerHRLastPause);
  packF32(b, 78, s.rescuerSpO2LastPause);
  packF32(b, 82, s.rescuerTemperatureStart);
  packF32(b, 86, s.rescuerTemperatureEnd);

  b[90] = s.pulseDetected ? 1 : 0;
  b[91] = (uint8_t)constrain((int)s.noFlowIntervals, 0, 255);
  b[92] = s.rescuerSwapCount;
  // bytes 93–94: timeToFirstCompressionMs as uint16 LE (max 65535ms)
  uint16_t ttf = (uint16_t)constrain((int)s.timeToFirstCompressionMs, 0, 65535);
  b[93] = (uint8_t)(ttf & 0xFF);
  b[94] = (uint8_t)((ttf >> 8) & 0xFF);
  b[95] = s.wristDroppedDuringSession ? 1 : 0;
  return item;
}

BLEEventItem bleBuildVentilationWindow(uint16_t cycleNum, uint8_t breathsExpected) {
  auto item = makeItem(BLEEventType::VentilationWindow);
  item.data[0] = PKT_VENTILATION_WINDOW;
  packU16(item.data, 1, cycleNum);
  item.data[3] = breathsExpected;
  return item;
}

BLEEventItem bleBuildPulseCheckStart(uint16_t intervalNum, uint32_t elapsedMs) {
  auto item = makeItem(BLEEventType::PulseCheckStart);
  item.data[0] = PKT_PULSE_CHECK_START;
  packU16(item.data, 1, intervalNum);
  // bytes 3–6: elapsedMs uint32 (unaligned — byte-by-byte)
  item.data[3] = (elapsedMs)&0xFF;
  item.data[4] = (elapsedMs >> 8) & 0xFF;
  item.data[5] = (elapsedMs >> 16) & 0xFF;
  item.data[6] = (elapsedMs >> 24) & 0xFF;
  return item;
}

BLEEventItem bleBuildPulseCheckResult(uint8_t classification, float bpm,
                                      uint8_t confidence, uint8_t detA, uint8_t detB,
                                      uint8_t refSource) {
  auto item = makeItem(BLEEventType::PulseCheckResult);
  item.data[0] = PKT_PULSE_CHECK_RESULT;
  item.data[1] = classification;
  packF32(item.data, 2, bpm);
  item.data[6] = confidence;
  item.data[7] = detA;
  item.data[8] = detB;
  // byte 9 — self-detection guard reference source (FIRMWARE_PLAN Block C):
  // 0=NONE 1=LIVE 2=PAUSED. Data capture only, no effect on gating.
  item.data[9] = refSource;
  return item;
}

BLEEventItem bleBuildModeChange(GloveMode mode, uint8_t trigger) {
  auto item = makeItem(BLEEventType::ModeChange);
  item.data[0] = PKT_MODE_CHANGE;
  item.data[1] = (uint8_t)mode;
  item.data[2] = trigger;
  return item;
}

BLEEventItem bleBuildTwoMinAlert(uint8_t alertNum) {
  auto item = makeItem(BLEEventType::TwoMinAlert);
  item.data[0] = PKT_TWO_MIN_ALERT;
  item.data[1] = alertNum;
  return item;
}

BLEEventItem bleBuildFatigueAlert(uint8_t score) {
  auto item = makeItem(BLEEventType::FatigueAlert);
  item.data[0] = PKT_FATIGUE_ALERT;
  item.data[1] = score;
  return item;
}

BLEEventItem bleBuildPendingLocalData(uint8_t count) {
  auto item = makeItem(BLEEventType::PendingLocalData);
  item.data[0] = PKT_PENDING_LOCAL_DATA;
  item.data[1] = count;
  return item;
}

BLEEventItem bleBuildLocalSessionChunk(uint8_t sessIdx, uint8_t chunkIdx,
                                       uint8_t totalChunks, const uint8_t* payload92) {
  auto item = makeItem(BLEEventType::LocalSessionChunk);
  item.data[0] = PKT_LOCAL_SESSION_CHUNK;
  item.data[1] = sessIdx;
  item.data[2] = chunkIdx;
  item.data[3] = totalChunks;
  memcpy(&item.data[4], payload92, STORAGE_CHUNK_PAYLOAD);  // 92 bytes payload (spec §4.11)
  return item;
}

BLEEventItem bleBuildSelftestResult(const SelfTestResult& r) {
  auto item = makeItem(BLEEventType::SelftestResult);
  item.data[0] = PKT_SELFTEST_RESULT;
  item.data[1] = r.passMask;
  item.data[2] = r.warnMask;
  item.data[3] = r.criticalMask;
  item.data[4] = r.batteryPct;
  item.data[5] = r.i2cScanMask;
  item.data[6] = r.palmWhoAmI;
  item.data[7] = r.wristWhoAmI;
  // Bytes 8–15: reason codes (one per sensor bit, indices 0–7)
  for (int i = 0; i < 8; i++) item.data[8 + i] = r.reasonCodes[i];
  return item;
}

BLEEventItem bleBuildScenarioChange(Scenario sc, uint8_t trigger) {
  auto item = makeItem(BLEEventType::ScenarioChange);
  item.data[0] = PKT_SCENARIO_CHANGE;
  item.data[1] = (uint8_t)sc;
  item.data[2] = trigger;
  return item;
}

// ── DIAG_FRAME — diagnostic-mode telemetry, own packet (FIRMWARE_PLAN Block D) ─
// Replaces the old LIVE_STREAM diag overlay, which aliased bytes that carry
// real fields (residualLoadDepthCm 52-55, inVentilationWindow 86,
// lastPeakDepthCm/Confidence/Source 102-107) in normal mode. Queued at
// DIAG_FRAME_INTERVAL_MS from cpr_glove.ino's main loop while diagActive.
//
//   byte 0     packet type (PKT_DIAG_FRAME)
//   byte 1-2   raw FSR ADC                        i16 LE
//   byte 3     diagPalmWhoAmI                      u8
//   byte 4     diagWristWhoAmI                     u8
//   byte 5     diagI2cScanResult                   u8
//   byte 6     diagActionResult                     u8
//   byte 7-8   palm motion accel × 100 (mg)        i16 LE
//   byte 9-10  wrist motion accel × 100 (mg)       i16 LE
//   byte 11-12 rescuer PPG filtered AC (counts)    i16 LE — doc'd ±300, ample
//   byte 13-16 rescuer PPG DC (counts)             u32 LE — raw IR count,
//              an integer quantity (bench-observed up to ~138000, overflows
//              i16/u16); u32 not f32 since the sensor has no sub-count
//              precision to represent.
//   byte 17-95 unused (zero-filled by makeItem())
BLEEventItem bleBuildDiagFrame() {
  auto item = makeItem(BLEEventType::DiagFrame);
  uint8_t* b = item.data;
  b[0] = PKT_DIAG_FRAME;

  int16_t rawAdc = (int16_t)analogRead(PIN_FSR_ADC);
  packU16(b, 1, (uint16_t)rawAdc);

  b[3] = diagPalmWhoAmI;
  b[4] = diagWristWhoAmI;
  b[5] = diagI2cScanResult;
  b[6] = diagActionResult;

  int16_t palmMg  = (int16_t)constrain((int)(imuGetMotionAccelPalm()  * 100.0f), -32768, 32767);
  int16_t wristMg = (int16_t)constrain((int)(imuGetMotionAccelWrist() * 100.0f), -32768, 32767);
  packU16(b, 7, (uint16_t)palmMg);
  packU16(b, 9, (uint16_t)wristMg);

  int16_t rescuerFiltered = (int16_t)constrain((int)max30102DiagRescuerFiltered(), -32768, 32767);
  packU16(b, 11, (uint16_t)rescuerFiltered);

  packU32(b, 13, (uint32_t)max30102DiagRescuerDc());

  return item;
}
