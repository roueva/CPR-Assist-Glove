#pragma once
// =============================================================================
// ble_manager.h — BLE GATT server, packet builders, command handler
// =============================================================================
#include "config.h"
#include "shared_state.h"
#include "selftest.h"

// ── Event queue item (for async EVENT_CHANNEL sends) ─────────────────────────
enum class BLEEventType : uint8_t {
  SessionStart,
  SessionEnd,
  VentilationWindow,
  PulseCheckStart,
  PulseCheckResult,
  ModeChange,
  TwoMinAlert,
  FatigueAlert,
  PendingLocalData,
  LocalSessionChunk,
  SelftestResult,
  ScenarioChange
};

struct BLEEventItem {
  BLEEventType type;
  uint8_t data[EVENT_CHANNEL_SIZE];
};

// ── Init & connection ─────────────────────────────────────────────────────────
void bleInit();
bool bleConnected();

// ── Packet senders (called from comms task) ───────────────────────────────────
void bleSendLiveStream(const SharedState& s);
void bleQueueEvent(const BLEEventItem& item);  // thread-safe enqueue
void bleDrainEventQueue();                     // send one item per call
void bleFlushEventQueue();                     // discard all queued events (called on reconnect)

// ── Packet builders ───────────────────────────────────────────────────────────
BLEEventItem bleBuildSessionStart(GloveMode mode, Scenario sc);
BLEEventItem bleBuildSessionEnd(const SharedState& s);
BLEEventItem bleBuildVentilationWindow(uint16_t cycleNum, uint8_t breathsExpected);
BLEEventItem bleBuildPulseCheckStart(uint16_t intervalNum, uint32_t elapsedMs);
BLEEventItem bleBuildPulseCheckResult(uint8_t classification, float bpm,
                                      uint8_t confidence, uint8_t detA, uint8_t detB);
BLEEventItem bleBuildModeChange(GloveMode mode, uint8_t trigger);
BLEEventItem bleBuildTwoMinAlert(uint8_t alertNum);
BLEEventItem bleBuildFatigueAlert(uint8_t score);
BLEEventItem bleBuildPendingLocalData(uint8_t count);
BLEEventItem bleBuildLocalSessionChunk(uint8_t sessIdx, uint8_t chunkIdx,
                                       uint8_t totalChunks, const uint8_t* payload92);
BLEEventItem bleBuildSelftestResult(const SelfTestResult& r);
BLEEventItem bleBuildScenarioChange(Scenario sc, uint8_t trigger);

// ── Callbacks (set by session manager) ───────────────────────────────────────
// Called when the app sends a command over EVENT_CHANNEL
extern void onAppCommand(uint8_t cmd, const uint8_t* data, size_t len);
extern void onBLEConnect();
extern void onBLEDisconnect();
