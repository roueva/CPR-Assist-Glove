#pragma once
// =============================================================================
// storage.h — LittleFS offline session storage
// Up to 20 sessions. Evict oldest when full.
// Sync on BLE reconnect via PENDING_LOCAL_DATA / LOCAL_SESSION_CHUNK.
// =============================================================================
#include "config.h"
#include "shared_state.h"

bool storageInit();
uint8_t storagePendingCount();

// Save a completed session. Returns slot index (0–19) or -1 on failure.
int storageSaveSession(const SharedState& s, uint32_t durationSec, uint64_t unixTsMs);
// Read a session chunk for BLE transfer (bytes 4–79, 76 bytes payload)
// chunkIndex: 0-based. Returns total chunks for this session, or 0 on error.
uint8_t storageReadChunk(uint8_t sessionIndex, uint8_t chunkIndex, uint8_t* outBuf92);

// Mark a session as synced (called after CONFIRM_RECEIVED)
void storageMarkSynced(uint8_t sessionIndex);

// Total chunks needed to transfer one session
uint8_t storageTotalChunks(uint8_t sessionIndex);


struct StoredVentilation {
  uint32_t timestampMs;
  uint16_t cycleNumber;
  uint8_t ventilationsGiven;
  uint32_t durationMs;
  uint8_t compliant;
} __attribute__((packed));

struct StoredPulseCheck {
  uint32_t timestampMs;
  uint8_t intervalNumber;
  uint8_t classification;
  float detectedBPM;
  uint8_t confidence;
  uint8_t detectorACount;
  uint8_t detectorBCount;
} __attribute__((packed));

const StoredVentilation* getStoredVentilations(uint8_t& count);
const StoredPulseCheck* getStoredPulseChecks(uint8_t& count);
