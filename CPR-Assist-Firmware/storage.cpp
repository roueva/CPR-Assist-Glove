// =============================================================================
// storage.cpp — LittleFS offline session storage (Spec v3.0 §8.2, format v4)
// Session binary layout:
//   HEADER (104 bytes, see writeHeader())
//     0–1   uint16  magic 0xC9A1
//     2     uint8   format version
//     3–10  uint64  sessionStartMs (unix ms)
//     11–18 uint64  sessionEndMs (unix ms)
//     19    uint8   mode
//     20    uint8   scenario
//     21–24 uint32  totalCompressions
//     25–28 uint32  correctDepth
//     29–32 uint32  correctFrequency
//     33–36 uint32  correctRecoil
//     37–40 uint32  depthRateCombo
//     41–44 uint32  correctPosture
//     45–48 uint32  leaningCount
//     49–52 uint32  overForceCount
//     53–56 uint32  tooDeepCount
//     57–60 uint32  totalVentilations
//     61–64 uint32  correctVentilations
//     65–68 uint32  fatigueOnsetIndex
//     69–72 float32 peakDepth
//     73–76 float32 compressionDepthSD
//     77–80 float32 patientTemperature
//     81–84 float32 rescuerTemperatureStart
//     85–88 float32 rescuerTemperatureEnd
//     89–92 float32 rescuerHRLastPause
//     93–96 float32 rescuerSpO2LastPause
//     97    uint8   pulseDetected
//     98    uint8   noFlowIntervals
//     99    uint8   rescuerSwapCount
//     100–101 uint16 compressionArrayLen
//     102   uint8   ventilationArrayLen
//     103   uint8   pulseCheckArrayLen
//   COMPRESSION ARRAY (compressionArrayLen × 20 bytes)
//   VENTILATION ARRAY (ventilationArrayLen × 12 bytes)
//   PULSE CHECK ARRAY (pulseCheckArrayLen × 12 bytes)
// Meta:  /sessions/meta.bin — 20 bytes, one per slot (0=empty,1=pending,2=synced)
// =============================================================================
#include "storage.h"
#include "depth.h"
#include <LittleFS.h>
#include <string.h>

// Meta file layout (40 bytes for STORAGE_MAX_SESSIONS=20):
//   bytes 0–19:  state per slot (0=empty, 1=pending). State 2 is retired
//                in v5+ — confirmed sessions are deleted immediately so
//                their slot returns to 0.
//   bytes 20–39: insertion sequence per slot (uint8 wraparound). The slot
//                with the lowest "age" (computed as _seqCounter - seq[slot],
//                modulo 256) is the OLDEST. Empty slots ignore this field.
//   byte 40:     _seqCounter — next sequence number to assign.
#define META_STATE_SIZE STORAGE_MAX_SESSIONS
#define META_SEQ_SIZE STORAGE_MAX_SESSIONS
#define META_TOTAL_SIZE (META_STATE_SIZE + META_SEQ_SIZE + 1)

static uint8_t _meta[META_STATE_SIZE];  // 0 = empty, 1 = pending
static uint8_t _seq[META_SEQ_SIZE];     // insertion sequence per slot
static uint8_t _seqCounter = 1;         // next seq to assign (0 reserved = unused)
static bool _ready = false;

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
static void packU64(uint8_t* b, int off, uint64_t v) {
  for (int i = 0; i < 8; i++) b[off + i] = (uint8_t)((v >> (8 * i)) & 0xFF);
}
static void packF32(uint8_t* b, int off, float v) {
  uint32_t raw;
  memcpy(&raw, &v, 4);
  packU32(b, off, raw);
}

static String slotPath(uint8_t idx) {
  char p[32];
  snprintf(p, sizeof(p), "/sessions/s%02d.bin", idx);
  return String(p);
}

static void loadMeta() {
  // Always start clean — partial reads must not leave uninitialised bytes.
  memset(_meta, 0, sizeof(_meta));
  memset(_seq, 0, sizeof(_seq));
  _seqCounter = 1;

  File f = LittleFS.open("/sessions/meta.bin", "r");
  if (!f) return;
  uint8_t buf[META_TOTAL_SIZE] = { 0 };
  size_t n = f.read(buf, META_TOTAL_SIZE);
  f.close();

  if (n == META_TOTAL_SIZE) {
    memcpy(_meta, buf, META_STATE_SIZE);
    memcpy(_seq, buf + META_STATE_SIZE, META_SEQ_SIZE);
    _seqCounter = buf[META_STATE_SIZE + META_SEQ_SIZE];
    if (_seqCounter == 0) _seqCounter = 1;
  } else if (n == STORAGE_MAX_SESSIONS) {
    // Legacy v4 meta (state byte only). Migrate: copy state, leave seq=0
    // (treated as "unknown age" — fine, they'll get evicted first).
    memcpy(_meta, buf, STORAGE_MAX_SESSIONS);
  }
  // Anything else: keep zeroed.

  // Sanity: any state byte that isn't 0/1 is corruption — treat as empty.
  // (State 2 from old firmware also gets demoted to empty, freeing the slot.)
  for (int i = 0; i < META_STATE_SIZE; i++) {
    if (_meta[i] != 0 && _meta[i] != 1) _meta[i] = 0;
  }
}

static void saveMeta() {
  uint8_t buf[META_TOTAL_SIZE];
  memcpy(buf, _meta, META_STATE_SIZE);
  memcpy(buf + META_STATE_SIZE, _seq, META_SEQ_SIZE);
  buf[META_STATE_SIZE + META_SEQ_SIZE] = _seqCounter;
  File f = LittleFS.open("/sessions/meta.bin", "w");
  if (!f) return;
  f.write(buf, META_TOTAL_SIZE);
  f.close();
}


bool storageInit() {
  if (!LittleFS.begin(true)) return false;
  LittleFS.mkdir("/sessions");
  loadMeta();
  // Reconcile meta vs actual files (a brown-out mid-save can leave either
  // a pending meta entry with no file, or an orphan file with no meta).
  bool dirty = false;
  for (int i = 0; i < META_STATE_SIZE; i++) {
    bool exists = LittleFS.exists(slotPath(i));
    if (_meta[i] == 1 && !exists) {
      _meta[i] = 0;
      _seq[i] = 0;
      dirty = true;  // ghost pending
    } else if (_meta[i] == 0 && exists) {
      LittleFS.remove(slotPath(i));  // orphan file
    }
  }
  if (dirty) saveMeta();
  _ready = true;
  return true;
}

uint8_t storagePendingCount() {
  if (!_ready) return 0;
  uint8_t cnt = 0;
  for (int i = 0; i < META_STATE_SIZE; i++)
    if (_meta[i] == 1) cnt++;
  return cnt;
}

int storageSaveSession(const SharedState& s, uint32_t durationSec, uint64_t unixTsMs) {
  if (!_ready) return -1;
  // Don't persist trivial sessions — empty or sub-threshold sessions
  // are usually accidental button presses or inactivity-timeout artifacts.
  // (Constant defined in config.h)
  if (s.totalCompressions < STORAGE_MIN_COMPRESSIONS_TO_SAVE) {
    return -1;
  }

  // Choose slot: first empty → otherwise evict the OLDEST pending.
  // "Oldest" = largest age = (_seqCounter - _seq[i]) mod 256.
  int slot = -1;
  for (int i = 0; i < META_STATE_SIZE; i++) {
    if (_meta[i] == 0) {
      slot = i;
      break;
    }
  }
  if (slot < 0) {
    uint8_t maxAge = 0;
    for (int i = 0; i < META_STATE_SIZE; i++) {
      uint8_t age = (uint8_t)(_seqCounter - _seq[i]);  // wraparound subtract
      if (age >= maxAge) {
        maxAge = age;
        slot = i;
      }
    }
    if (slot < 0) slot = 0;  // defensive
  }

  // Pull buffered events from depth.cpp / cpr_glove.ino
  uint16_t compCount = 0;
  const StoredCompression* comps = depthGetStoredCompressions(compCount);
  uint8_t ventCount = 0;
  const StoredVentilation* vents = getStoredVentilations(ventCount);
  uint8_t pulseCount = 0;
  const StoredPulseCheck* pulses = getStoredPulseChecks(pulseCount);

  const uint32_t bodyBytes = (uint32_t)compCount * STORAGE_COMPRESSION_SIZE
                             + (uint32_t)ventCount * STORAGE_VENTILATION_SIZE
                             + (uint32_t)pulseCount * STORAGE_PULSE_CHECK_SIZE;
  const uint32_t totalBytes = STORAGE_HEADER_SIZE + bodyBytes;

  // Build a stack buffer big enough for the worst case
  static uint8_t buf[STORAGE_MAX_FILE_SIZE];
  memset(buf, 0, totalBytes);

  // ── HEADER ─────────────────────────────────────────────────────────────────
  buf[0] = 0xA1;
  buf[1] = 0xC9;  // magic (LE)
  buf[2] = STORAGE_FORMAT_VERSION;
  packU64(buf, 3, unixTsMs);                                     // session start (ms epoch)
  packU64(buf, 11, unixTsMs + (uint64_t)durationSec * 1000ULL);  // end
  buf[19] = (uint8_t)s.currentMode;
  buf[20] = (uint8_t)s.currentScenario;
  packU32(buf, 21, s.totalCompressions);
  packU32(buf, 25, s.correctDepth);
  packU32(buf, 29, s.correctFrequency);
  packU32(buf, 33, s.correctRecoil);
  packU32(buf, 37, s.depthRateCombo);
  packU32(buf, 41, s.correctPosture);
  packU32(buf, 45, s.leaningCount);
  packU32(buf, 49, s.overForceCount);
  packU32(buf, 53, s.tooDeepCount);
  packU32(buf, 57, s.totalVentilations);
  packU32(buf, 61, s.correctVentilations);
  packU32(buf, 65, s.fatigueOnsetIndex);
  packF32(buf, 69, s.peakDepth);
  packF32(buf, 73, s.compressionDepthSD);
  packF32(buf, 77, s.patientTemperatureLastPulseCheck);
  packF32(buf, 81, s.rescuerTemperatureStart);
  packF32(buf, 85, s.rescuerTemperatureEnd);
  packF32(buf, 89, s.rescuerHRLastPause);
  packF32(buf, 93, s.rescuerSpO2LastPause);
  buf[97] = s.pulseDetected ? 1 : 0;
  buf[98] = (uint8_t)constrain((int)s.noFlowIntervals, 0, 255);
  buf[99] = s.rescuerSwapCount;
  packU16(buf, 100, compCount);
  buf[102] = ventCount;
  buf[103] = pulseCount;

  // ── COMPRESSION ARRAY ──────────────────────────────────────────────────────
  uint32_t off = STORAGE_HEADER_SIZE;
  for (uint16_t i = 0; i < compCount; i++) {
    const StoredCompression& c = comps[i];
    packU32(buf, off + 0, c.timestampMs);
    packF32(buf, off + 4, c.depth);
    packF32(buf, off + 8, c.frequency);
    buf[off + 12] = c.recoil;
    buf[off + 13] = c.overForce;
    buf[off + 14] = c.postureOk;
    buf[off + 15] = c.wristAlignX10;
    buf[off + 16] = c.axisDevX10;
    // bytes off+17, off+18, off+19 reserved
    off += STORAGE_COMPRESSION_SIZE;
  }

  // ── VENTILATION ARRAY ──────────────────────────────────────────────────────
  for (uint8_t i = 0; i < ventCount; i++) {
    const StoredVentilation& v = vents[i];
    packU32(buf, off + 0, v.timestampMs);
    packU16(buf, off + 4, v.cycleNumber);
    buf[off + 6] = v.ventilationsGiven;
    packU32(buf, off + 7, v.durationMs);
    buf[off + 11] = v.compliant;
    off += STORAGE_VENTILATION_SIZE;
  }

  // ── PULSE CHECK ARRAY ──────────────────────────────────────────────────────
  for (uint8_t i = 0; i < pulseCount; i++) {
    const StoredPulseCheck& p = pulses[i];
    packU32(buf, off + 0, p.timestampMs);
    buf[off + 4] = p.intervalNumber;
    buf[off + 5] = p.classification;
    packF32(buf, off + 6, p.detectedBPM);
    buf[off + 10] = p.confidence;
    buf[off + 11] = p.detectorACount;
    buf[off + 12] = p.detectorBCount;
    off += STORAGE_PULSE_CHECK_SIZE;
  }

  // Write to LittleFS — if the write truncates we must not mark the slot
  // pending; the app would otherwise pull a corrupt file and the slot
  // would stay stuck until 19 newer sessions evicted it.
  File f = LittleFS.open(slotPath(slot), "w");
  if (!f) return -1;
  size_t written = f.write(buf, totalBytes);
  f.close();
  if (written != totalBytes) {
    LittleFS.remove(slotPath(slot));
    return -1;
  }

  _meta[slot] = 1;                        // pending
  _seq[slot] = _seqCounter++;             // wraparound is fine
  if (_seqCounter == 0) _seqCounter = 1;  // skip 0 (reserved = unused)
  saveMeta();
  return slot;
}

// ── Read a chunk for BLE transfer ────────────────────────────────────────────
// Returns total chunks (so caller knows when done). 0 = error/empty.
uint8_t storageReadChunk(uint8_t sessionIndex, uint8_t chunkIndex, uint8_t* outBuf92) {
  if (!_ready || sessionIndex >= META_STATE_SIZE) return 0;
  if (_meta[sessionIndex] == 0) return 0;

  File f = LittleFS.open(slotPath(sessionIndex), "r");
  if (!f) return 0;
  size_t fileSize = f.size();
  uint8_t total = (uint8_t)((fileSize + STORAGE_CHUNK_PAYLOAD - 1) / STORAGE_CHUNK_PAYLOAD);
  if (chunkIndex >= total) {
    f.close();
    return 0;
  }

  size_t offset = (size_t)chunkIndex * STORAGE_CHUNK_PAYLOAD;
  f.seek(offset);
  memset(outBuf92, 0, STORAGE_CHUNK_PAYLOAD);
  size_t remaining = fileSize - offset;
  size_t toRead = (remaining > STORAGE_CHUNK_PAYLOAD) ? STORAGE_CHUNK_PAYLOAD : remaining;
  f.read(outBuf92, toRead);
  f.close();
  return total;
}

uint8_t storageTotalChunks(uint8_t sessionIndex) {
  if (!_ready || sessionIndex >= META_STATE_SIZE) return 0;
  if (_meta[sessionIndex] == 0) return 0;
  File f = LittleFS.open(slotPath(sessionIndex), "r");
  if (!f) return 0;
  size_t fileSize = f.size();
  f.close();
  return (uint8_t)((fileSize + STORAGE_CHUNK_PAYLOAD - 1) / STORAGE_CHUNK_PAYLOAD);
}

void storageMarkSynced(uint8_t sessionIndex) {
  if (!_ready || sessionIndex >= META_STATE_SIZE) return;
  LittleFS.remove(slotPath(sessionIndex));  // free flash immediately
  _meta[sessionIndex] = 0;                  // slot is reusable now
  _seq[sessionIndex] = 0;
  saveMeta();
}