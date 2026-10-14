# Thread-safety audit — `gState` across sensorTask / commsTask

Read-only audit per `FIRMWARE_PLAN.md` block G. Nothing edited. Scope:
`cpr_glove.ino`, `shared_state.h`, `ble_manager.cpp`, `depth.cpp`, `imu.cpp`
(left-hand study glove, `~/Documents/Arduino/cpr_glove_new/`; `depth.cpp`,
`imu.cpp`, `ble_manager.cpp`, `shared_state.h` are byte-identical to the
tracked copies in `CPR-Assist-Firmware-LeftHand/`, confirmed by diff).

Two app tasks: `sensorTask` (Core 1, priority 5, 8192-byte stack,
`cpr_glove.ino:1751`) and `commsTask` (Core 0, priority 3, 12288-byte stack,
`cpr_glove.ino:1754`). A third, undocumented actor shows up below.

---

## 1. Every `gState` read/write — under `gStateMux`, or documented single-core?

**Mostly yes, with one confirmed wrong claim.**

- `depth.cpp` and `imu.cpp` never touch `gState` directly. `depthUpdate()`
  takes a `SharedState&` that `sensorTask` fills from `snapshotState()`
  (a local copy, not the live struct) and merges back under one
  `portENTER_CRITICAL` block (`cpr_glove.ino:772-811`). Verified
  field-by-field: every one of the 36 fields `depthUpdate()` writes on its
  parameter (`compressionAxisDeviation`, `compressionCount`,
  `compressionInCycle`, `correctDepth/Frequency/Posture/Recoil`, `depth`,
  `depthRateCombo`, `depthTrend`, `fatigueFlag`, `fatigueOnsetIndex`,
  `force`, `frequency`, `imuCalibrated`, `instantaneousRate`,
  `lastPeakConfidence/DepthCm/DepthSource`, `leaningCount/Detected`,
  `overForceCount/Flag`, `peakDepth`, `peakTimestampMs`, `postureOk`,
  `recoilAchieved`, `rescuerFatigueScore`, `residualLoadDepthCm`,
  `timeToFirstCompressionMs`, `tooDeepCount`, `totalCompressions`,
  `valleyTimestampMs`, `wristAlignmentAngle`, `wristDropped`,
  `wristDroppedDuringSession`, `wristFlexionAngle`) appears in the merge-back
  list. No silent-drop gap. This is good design, not an accident — the
  comment at `cpr_glove.ino:766-767` states the intent explicitly.
- Every direct `gState.x = ...` in `onAppCommand()` (`cpr_glove.ino:161-`)
  is wrapped in `portENTER_CRITICAL`/`portEXIT_CRITICAL` — `CMD_MODE_SET`,
  `CMD_SET_SCENARIO`, `CMD_SET_TARGET_DEPTH`, `CMD_SET_TARGET_RATE`,
  `CMD_SET_VENTILATION`, `CMD_FEEDBACK_SET`, `CMD_SET_FEEDBACK_CH`. Confirmed
  clean.
- **DEFECT — the diag-globals comment at `shared_state.h:166-168` is
  false.** It claims:

  > Not under gStateMux because both writers are on commsTask (BLE
  > callbacks) and the reader is also commsTask. Single-core access, no race.

  The five globals it covers (`diagActive`, `diagActionResult`,
  `diagI2cScanResult`, `diagPalmWhoAmI`, `diagWristWhoAmI`) are written at
  `cpr_glove.ino:316-363` inside `onAppCommand()`, called directly and
  synchronously from `EventCB::onWrite()` (`ble_manager.cpp:55-61`) — a
  `BLECharacteristicCallbacks` override invoked by the ESP32 `BLEDevice`
  (Bluedroid) stack's own internal GATT callback task, never from inside
  `commsTask`'s `while(true)` loop. Contrast this with every *other*
  `onAppCommand` case: `CMD_MODE_SET`, `CMD_START`, `CMD_STOP`, etc. all set
  a `_pending*` flag and let `commsTask` do the actual work on its own loop
  iteration (`cpr_glove.ino:892-900` dispatches `_pendingStart`/
  `_pendingStop` this way). `CMD_DIAG_START`/`CMD_DIAG_STOP` are the only
  commands that skip that pattern and write the globals directly inside the
  callback. The reader, `bleBuildDiagFrame()` (`ble_manager.cpp:465-468`),
  *is* called from `commsTask` (`cpr_glove.ino:1461`) — so the reader side
  of the comment is right, the writer side is not. This makes it a genuine
  three-task shared state (sensorTask does not touch it, but the BLE stack's
  own task and commsTask both do) with zero synchronization.

  Practical exposure is narrow — all five fields are single-byte
  (`bool`/`uint8_t`), so no torn read of an individual field — but the
  five-field write at `CMD_DIAG_START` (`diagActive = true` then
  `diagActionResult = 0x00` then `diagI2cScanResult = 0x00` then, after an
  I²C mutex acquisition, `diagPalmWhoAmI`/`diagWristWhoAmI`) is not atomic
  as a group. `commsTask`'s DIAG_FRAME send at 4 Hz
  (`DIAG_FRAME_INTERVAL_MS`) can read `diagActive == true` with
  `diagPalmWhoAmI`/`diagWristWhoAmI` still at their previous session's
  stale values, or `0x00`, mid-sequence. Low severity (diagnostic-only path,
  gated behind a manual `CMD_DIAG_START`, never active during a graded
  session), but the comment's safety reasoning should be fixed regardless —
  it currently tells a future reader something false about where the write
  comes from.

## 2. Does `snapshotState()` copy atomically?

**Yes.** `shared_state.h:158-164` — one `portENTER_CRITICAL`, one
struct-copy, one `portEXIT_CRITICAL`. No reader can observe a torn mix of
one compression's `lastPeakDepthCm` with the next's `lastPeakConfidence` —
both are always copied together inside the same critical section.

## 3. Task priorities and stack sizes — headroom

Configured values (`config.h:674-680`):

| Task | Core | Priority | Stack |
|---|---|---|---|
| `sensorTask` | 1 | 5 | 8192 B |
| `commsTask` | 0 | 3 | 12288 B |

**Cannot report actual headroom — no runtime measurement exists.**
`uxTaskGetStackHighWaterMark` is not called anywhere in the firmware. This
is a gap, not a defect: the configured sizes may be generous or tight, but
nothing in the code answers the question. Recommend adding a one-line log
(`uxTaskGetStackHighWaterMark(NULL)` at the top of each task's loop, printed
every N seconds under a debug flag) before relying on these numbers for the
study.

One structural note worth flagging alongside priority: `sensorTask` shares
Core 1 with the Arduino `loopTask` (which on this core is close to idle —
`loop()` only services the `IMU_TEST_LOG` serial command parser,
`cpr_glove.ino:1757-1789`), while `commsTask` shares Core 0 with the
Bluedroid BLE stack's own internal task(s) — the same task identified in
finding 1 as the real writer of the diag globals. `commsTask`'s priority
(3) relative to Bluedroid's internal task priority is not set by this
firmware and wasn't traced further; it doesn't change any finding above; a Core 0
contention check would need runtime tracing (not static reading) and belongs
with the Core 0 calibration-contention note below.

## 4. `depthFinalizeLastValley()` before `snapshotState()` in every `stopSession()` path

**Confirmed correct on all three paths.** `stopSession()` is one function
(`cpr_glove.ino:473-523`); `depthFinalizeLastValley()` runs at line 480,
`snapshotState()` for the SESSION_END packet at line 493 — always in that
order, because there's only one `stopSession()` body. All three call sites
— `_pendingStop` dispatch (`cpr_glove.ino:899`), the long-press button
handler (`:940`), and the inactivity timeout (`:1025`) — are inside
`commsTask`'s own loop (`commsTask` spans `cpr_glove.ino:821-1595`; all
three line numbers fall inside that range). No cross-task race on the
ordering itself. (The known one-compression-short `correctRecoil` gap from
`depthFinalizeLastValley()`'s own header comment, `depth.cpp:362-379`, is a
correctness issue already tracked from the session-1 audit, not a threading
one — not re-reported here.)

## 5. Blocking calls on a task that also services BLE

Three found, all on `commsTask` (the task that also runs `bleSendLiveStream`,
`bleSendNextEvent`, NeoPixel updates, and button polling):

- **`storageSaveSession()` → LittleFS write, every `stopSession()`.**
  `cpr_glove.ino:518`, inside `storage.cpp:283-291`. Worst case
  `STORAGE_MAX_FILE_SIZE` = 104 + 600×20 + 20×12 + 10×13 = **12,474 bytes**
  (the comment at `config.h:658-659` says "≈4400 bytes for a long session" —
  that estimate is stale; 600 compressions alone is 12,000 bytes). Duration
  is **unmeasured** — nothing times the `f.write()` call. This runs
  unconditionally at every session end, with no guard comparable to the two
  below, and blocks all of `commsTask` (including draining the
  already-queued SESSION_END event) for however long the flash write takes.
- **`runCalibration()` → up to ~3 s mutex hold + `delay(10)` loop.**
  `cpr_glove.ino:558-583`. Holds `gI2CMutex` for up to 3000 ms
  (`xSemaphoreTake(gI2CMutex, pdMS_TO_TICKS(3000))`), then runs up to 200
  iterations of `forceInit(); delay(10);` (`:573-576`) — a direct `delay()`
  call inside `commsTask`, not a yield. The code's own comment
  acknowledges this ("~2-3 second window... user must hold the glove
  still"). Gated: only reachable via `_pendingCalibrate`, itself only set
  when `!_sessionRunning && !_inPulseCheck && !_inVentWindow`
  (`cpr_glove.ino:225`), so it cannot fire mid-session. Documented
  trade-off, not a defect — flagged because block G's prompt asked for
  worst-case duration on every blocking call, and this is the largest one
  in the codebase.
- **`runSelftest()` → up to 1 s mutex hold.** `cpr_glove.ino:525-553`,
  same gating as calibration. Smaller, same category.

All three are correctly excluded from firing during an active session
(the calibration/selftest pair explicitly; the storage write only runs
after `sessionActive` is already false). The LittleFS write is the one
item here actually worth timing on hardware, since unlike the other two it
has no acknowledged-tradeoff comment and no size estimate that's currently
accurate.

## 6. BLE stack disconnects mid-notification

No crash path found by static reading. `bleSendNextEvent()`
(`ble_manager.cpp:219-235`) and `bleSendLiveStream()`
(`ble_manager.cpp:99-102`) both check `_connected` before calling
`notify()`. `_eventQueue` is deliberately **not** flushed on disconnect —
`onBLEDisconnect()` is empty (`cpr_glove.ino:159`) — but **is** flushed on
the next `onBLEConnect()` (`cpr_glove.ino:156`, `bleFlushEventQueue()`),
with a comment explaining why: stale mid-session events from the
disconnected period would confuse the app, which re-syncs persisted
sessions via `PENDING_LOCAL_DATA` instead. That's a deliberate, documented
design, not a defect.

One narrow window this audit can't rule out from source alone: `_connected`
is `volatile bool`, written by `ServerCB::onDisconnect()`
(`ble_manager.cpp:46-51`) — which, like the diag-globals writer in finding
1, runs on the BLE stack's own callback task, not `commsTask`. There is a
TOCTOU gap between `commsTask`'s `if (!_connected ...)` check and the
following `_eventChar->notify()` call where the stack could disconnect in
between. Whether the underlying `BLEDevice` library's `notify()` degrades
gracefully (no-op) or blocks/throws when called a few microseconds after
disconnect isn't answerable by reading this firmware's source — it's a
property of the Arduino `BLEDevice` library's internal state handling.
Worth a disconnect-during-notify stress test on hardware if this hasn't
been exercised; not reportable as a confirmed defect from code alone.

---

## Summary

| # | Finding | Status |
|---|---|---|
| 1 | `shared_state.h:166-168`'s safety comment for the diag globals is wrong — the writer (`onAppCommand`'s `CMD_DIAG_START`/`CMD_DIAG_STOP` cases) runs on the BLE stack's own callback task, not `commsTask`. Five-field write sequence not atomic as a group. | **DEFECT** — low severity, diagnostic-only path |
| 2 | `snapshotState()` is atomic | Verified safe |
| 3 | Task priorities/stacks as configured; no runtime headroom measurement exists | Gap — needs hardware instrumentation |
| 4 | `depthFinalizeLastValley()` ordering holds on all 3 `stopSession()` call sites | Verified safe |
| 5 | Three blocking calls on `commsTask`: LittleFS session write (unmeasured, ~12.5KB worst case, unguarded), calibration (~3s, gated), selftest (~1s, gated) | Documented for the record; LittleFS write is the one worth timing |
| 6 | No static-analysis-confirmed crash on mid-notification disconnect; one TOCTOU window flagged as unanswerable from source | Needs hardware stress test to close |

Nothing in this file has been edited. Awaiting review before any apply pass.
