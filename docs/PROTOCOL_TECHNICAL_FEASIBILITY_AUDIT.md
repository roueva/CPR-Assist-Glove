# Protocol Technical Feasibility Audit

Read-only. No edits, no commits. Answers six questions about whether the
firmware/app as they exist today can actually run the three-session protocol
(Day 1 baseline, Day 1 guided, Day 8 follow-up) the way the approved study
describes it.

---

## 1. Feedback-off recording mode

**Yes, it exists**, as a firmware `GloveMode` value, not a "scenario." (Note:
`Scenario` in this codebase means Adult/Pediatric depth targets — an
orthogonal concept. The mode that suppresses feedback is `GloveMode`.)

**Firmware side.**

- `shared_state.h:22-26` — `enum class GloveMode : uint8_t { Emergency, Training, NoFeedback }`.
- `shared_state.h:95-97` — three independent booleans drive every feedback
  channel: `audioFeedbackEnabled`, `hapticFeedbackEnabled`,
  `visualFeedbackEnabled`.
- `cpr_glove.ino:164-180` (`CMD_MODE_SET` handler) — on receiving a mode-set
  command over BLE: `const bool fbOn = (newMode != GloveMode::NoFeedback);`
  then all three flags are set to `fbOn`. This is the single mechanism that
  ties mode selection to feedback suppression.
- A second, independent path exists: `cpr_glove.ino:295-305`
  (`CMD_SET_FEEDBACK_CH`) lets the app set the three channels individually via
  a bitmask, and `CMD_FEEDBACK_SET` (`cpr_glove.ino:283-293`) sets all three
  at once — but neither is what the app actually uses for mode switching (see
  app side below); `CMD_MODE_SET` alone is sufficient and is what's wired up.
- **Consumption of the flags, verified per module:**
  - `motor.cpp` and `audio.cpp` are pure drivers — no mode awareness at all.
    Gating happens entirely at the call site in `cpr_glove.ino`.
  - `cpr_glove.ino:596` — `handleQualityAudio()` (the "too shallow / too fast
    / good job" voice-cue logic) returns immediately if
    `!s.audioFeedbackEnabled`.
  - `cpr_glove.ino:1430-1436` — the per-compression metronome haptic tick
    only fires `if (snap.hapticFeedbackEnabled && ...)`.
  - `cpr_glove.ino:1443-1447` — the per-compression depth click (audio +
    short vibration) is gated per-channel by
    `clickSnap.audioFeedbackEnabled` / `clickSnap.hapticFeedbackEnabled`.
  - `neopixel.cpp:213-218` (`neoUpdate()`) — hard early return, clearing and
    showing all-off, whenever `s.currentMode == GloveMode::NoFeedback`, on
    top of the per-channel `visualFeedbackEnabled` checks inside
    `updateDepthBar()` (`neopixel.cpp:120`), `updateRateLED()`
    (`neopixel.cpp:170`), and `updateStatusLED()` (`neopixel.cpp:186`).

- **Exception — not fully silent.** Session-start and session-end cues are
  **not** gated by any of the three flags and fire in every mode, including
  NoFeedback:
  - `cpr_glove.ino:468-470` (`startSession()`): `audioPlay(AUDIO_SESSION_STARTED, ...)`,
    `motorPattern(MOTOR_SHORT_MS, MOTOR_SHORT_MS, 3)`, `neoSessionStart()`
    (1 s all-white LED flash, `neopixel.cpp:243-248`).
  - `cpr_glove.ino:520-522` (`stopSession()`): `audioPlay(AUDIO_SESSION_ENDED, ...)`,
    `motorPattern(MOTOR_LONG_MS, MOTOR_MEDIUM_MS, 2)`, `neoSessionEnd()`
    (1 s fade-out, `neopixel.cpp:250-261`).
  - Mode/scenario-change confirmation pulses (button-triggered:
    `cpr_glove.ino:832-876`, `957-1003`) and self-test/calibration result
    tones (`cpr_glove.ino:553-555`, `589-591`) are likewise unconditional.
  - Net effect: a NoFeedback session is silent and dark *during* compressions
    (no metronome, no depth bar, no voice corrections), but the participant
    still gets one audio chime + one vibration burst + one white LED flash at
    the moment the session starts, and again when it ends. If "no haptic, no
    LED, no audio" needs to be literal for the entire session including its
    boundaries, this is a gap.

**How it's selected.** Over BLE, via `CMD_MODE_SET` sending the `GloveMode`
byte (0=Emergency, 1=Training, 2=NoFeedback) — not a config flag baked into
firmware, not a build-time setting.

**App side (UI control).**

- `app_providers.dart:120-136` — `AppMode` enum
  (`emergency`/`training`/`trainingNoFeedback`) documents itself: *"trainingNoFeedback
  (2) — login required, graded, all feedback suppressed."*
- The control is a chip labelled "No feedback" in the live-session status bar
  (`live_cpr_screen.dart:1162-1201`), gated by `if (!isEmergency) ...` — **it
  only renders once the app is already in Training mode**, i.e. it is a
  toggle *within* Training, not a top-level mode choice reachable from
  Emergency.
- Tapping it (`live_cpr_screen.dart:885-893`) toggles
  `AppMode.training ↔ AppMode.trainingNoFeedback` and immediately calls
  `bleConnection.sendModeSet(next.bleValue)`, which is what reaches
  `CMD_MODE_SET` above.
- The toggle is disabled (`onTap: null`) whenever `sessionLocked` is true
  (`live_cpr_screen.dart:885-886`, `1165-1167`) — **it cannot be flipped
  mid-session**, only before a session starts (while idle in Training mode).
- The in-app info dialog for this state (`live_cpr_screen.dart:1126-1128`)
  says verbatim: *"No-Feedback mode suppresses all glove feedback — audio,
  vibration and LEDs. Your session is still fully recorded and graded."*

**Conclusion:** the mode exists, is reachable only from an already-selected,
already-logged-in Training session (idle, not mid-session), and correctly
silences the corrective/live feedback loop. It does not silence the
session-start/session-end chime, buzz, and LED flash.

---

## 2. Recording while logged out

**Yes — Emergency-mode sessions record and persist locally without an
account; Training (and therefore NoFeedback, since it's reachable only from
Training) requires login and cannot start otherwise.**

- **Login gate on Training, exactly as CLAUDE.md describes.**
  `live_cpr_screen.dart:856-878` (`onModeToggle`): if switching from
  Emergency to Training while `!isLoggedIn`
  (`authStateProvider.isLoggedIn`), `AppDialogs.promptLogin` is shown first;
  declining or failing to end up logged in aborts the switch (`return`) and
  the app stays in Emergency. Only once logged in does
  `AppDialogs.confirmSwitchToTraining` show as a plain confirmation.
  Declining the login prompt leaves the user in Emergency, matching
  CLAUDE.md's "Dismissing leaves the user in Emergency."
- **The glove's own button can't bypass this.** If the physical button cycles
  the glove into Training while the app is logged out,
  `live_cpr_screen.dart:486-494` detects `newMode.isTraining &&
  !isLoggedIn`, immediately sends `CMD_MODE_SET(Emergency)` back to the
  glove, resets app state to Emergency, and shows "Training mode requires an
  account." plus the login prompt. No local path into Training exists while
  logged out.
- **Emergency-mode data still fully populated.** Depth/force sensing
  (`depth.cpp`, `force.cpp`) have no `currentMode`/`GloveMode` checks
  anywhere — grep confirms zero matches in either file — so compression
  count, depth, rate, recoil, posture, etc. are computed identically
  regardless of mode. The only mode-conditioned field is the grade:
  `SessionDetail.fromBleSession()` and `session.js` both force
  `total_grade = 0` for `mode == 'emergency'`
  (`live_cpr_screen.dart:130-133`: *"Emergency sessions always stay at grade
  0"*), everything else (compressionCount, correctDepth, correctFrequency,
  correctRecoil, averageDepth, depthConsistency, posture fields, etc.) is
  computed the same way as Training. **So yes: the three protocol sessions
  could run in Emergency mode instead of Training, and depth/rate/recoil
  would be recorded identically — only the 0–100 grade would be absent (and
  Emergency sessions never show the live feedback UI framing NoFeedback does,
  though the actual glove feedback in Emergency mode is full — audio, LED,
  haptic — per `neopixel.cpp:204` mapping `GloveMode::Emergency → COL_EMERALD`,
  a "live" mode color, not suppressed).** Using Emergency mode to dodge the
  login requirement would sacrifice grading and the "session recorded in
  Training/NoFeedback mode" label the protocol's own analysis plan keys off
  of (`session.js`'s `mode` column, `'emergency' | 'training' |
  'training_no_feedback'`).
- **Local persistence.** `session_local_storage.dart:19-27` — every
  `SessionDetail` is written to `SharedPreferences` under a per-owner key;
  `_defaultOwner = 'anon'` (`session_local_storage.dart:20`) is the bucket
  used when nobody is logged in. `authStateProvider`'s `ownerId` getter
  (`app_providers.dart:351`) returns `userId?.toString() ?? 'anon'` —
  confirming the mapping.
- **Where the save call happens.** `live_cpr_screen.dart:699-796`
  (`_handleSessionEnd`): line 775, `await
  service.saveLocalOnly(detail, ownerId: preLoginOwnerId)` **always** runs
  first, regardless of login state, writing to `SessionLocalStorage`. Only
  afterward (lines 781-799), if in Emergency and not logged in, the app
  offers a one-time non-blocking login prompt (*"Log in to save this session
  and track your progress."*), matching CLAUDE.md's "After it ends, prompt
  once, non-blocking." If the user stays logged out, the code returns after
  pushing the results screen — no backend save is attempted.
  `session_service.dart:105-117` (`saveDetail`) always calls `_network.post`
  with `requiresAuth: true`, so it cannot succeed unauthenticated; the
  explicit fallback is `saveLocalOnly` (comment at
  `session_service.dart:120`: *"Used when Emergency mode ends and the user
  declines to log in."*).
- **Retrievable afterward — yes, and reattached on login.**
  `SessionLocalStorage.loadAll(ownerId: 'anon')` returns everything saved
  under that bucket (`session_local_storage.dart:80-105`), and
  `migrateOwner()` (`session_local_storage.dart:205-232`) — invoked on
  login — moves every 'anon' record to the newly-authenticated owner id so
  it isn't orphaned. The session is visible in session history / results
  either way, just under the 'anon' bucket until a login happens.

**Bottom line for protocol planning:** Training/NoFeedback sessions need a
logged-in study account before `CMD_START`-time; there's no way around that
without code changes. Emergency mode needs no login and records the same
compression metrics, but drops the grade and the training/training_no_feedback
mode label the protocol's Day-1-baseline-vs-guided comparison is built on.

---

## 3. Participant code round-trip (session notes field)

**Field exists, is a free-text string, capped well above what's needed — but
it is a post-session-only field, not something settable before or during a
session.**

- **Backend.** `session.js:716-746` (`PATCH /sessions/:id/note`): validates
  `note` is a string or null, rejects if `note.length > 500`
  (`session.js:727`). No character-set restriction beyond that length check.
- **Model.** `session_detail.dart:183` — `final String? note;` — plain
  nullable Dart `String`, no format validation anywhere in `toJson()` /
  `fromJson()`.
- **UI.** The only editor is `_NoteEditorDialog`
  (`app_dialogs.dart:1197-1265`), reached via `AppDialogs.showNoteEditor`.
  `TextField` at `app_dialogs.dart:1245-1248`: `maxLines: 4, maxLength: 300`
  — a client-side cap of 300 characters (tighter than the backend's 500), no
  `inputFormatters` restricting character set. A code like `P07-D1-BASE` (11
  chars, alphanumeric + hyphens) fits with enormous headroom on both ends and
  will not be truncated or rejected.
- **When it can be set — this is the finding.** `grep` for
  `showNoteEditor(` across the whole app finds exactly two call sites:
  `session_results.dart:266` and `session_history.dart` (list-item action).
  Both are **post-session** screens — the results screen shown immediately
  after `SESSION_END`, or the historical list. There is no note field
  anywhere in the pre-session setup flow or on the live CPR screen itself —
  it cannot be entered "before or during" a session as the protocol plan
  assumes. It can only be typed in immediately after the session ends (on
  the results screen) or edited later from history.
- **Persistence path, both branches verified** (`session_results.dart:265-287`):
  - If the session already has a backend `id` (synced): `updateNote()` calls
    `PATCH /sessions/:id/note` with `requiresAuth: true`
    (`session_service.dart:129-141`) — requires login and connectivity.
  - If `id == null` (local-only, unsynced — e.g. Emergency + never logged
    in): the edit is written straight to `SessionLocalStorage.saveLocal`
    (`session_results.dart:283-284`) with no network/login requirement at
    all.
- **Survives into every path:** `SessionDetail.toJson()` includes
  `if (note != null) 'note': note` (`session_detail.dart:776`), so it rides
  along into the POST `/sessions/detail` body, the Postgres `note` column
  (`session.js:733`, `cpr_sessions.note`), `SessionLocalStorage`'s JSON blob,
  and every CSV export that stamps session metadata (`export_service.dart`
  lines 1316, 1693, 1777, 1833 all write `Note,${_esc(d.note!)}` when
  present).

**Practical consequence for the codes you want to use:** `P07-D1-BASE`,
`P07-D1-GUIDED`, `P07-D8` will all round-trip fine character-wise, but the
researcher will need to type each one into the results screen (or edit it in
history afterward) right after each of the three sessions ends — the field
can't be pre-filled or set while the glove is running.

---

## 4. Getting data off the device

**Yes, export works without an account, and includes everything asked for.**

- Every export function in `export_service.dart` (e.g.
  `exportRawCompressionsCsv`, `exportRawRescuerVitalsCsv`,
  `exportRawVentilationsCsv`, `exportRawPulseChecksCsv`,
  `exportRawDataZip`) takes a `SessionDetail detail` object directly as its
  parameter (confirmed call sites in `export_bottom_sheet.dart:582-633`) —
  none of them re-fetch from the backend or check `authStateProvider`. They
  operate on whatever `SessionDetail` the app already has in memory/local
  storage, so a purely local (never-synced, never-logged-in) session can be
  exported exactly like a synced one.
- **Per-compression CSV** (`_buildCompressionsCsv`, `export_service.dart:1270`
  onward) has one row per compression with columns including (header list at
  `export_service.dart:1352-1393`): Peak Depth (cm), Depth Target Met,
  Estimated Effective Depth, Recoil Depth (cm), Recoil Duration (ms), Recoil
  Target Met (Full Recoil), Leaning Detected, Force (N), Over Force Detected,
  Instant Rate (BPM), Rolling Rate (BPM), Rate Target Met, plus posture
  columns (Wrist Alignment, Wrist Flexion, Axis Deviation). This is a strict
  superset of "per-compression depth, rate, recoil flag."
- **Session-notes field is included** in the metadata header block of every
  raw CSV: `export_service.dart:1316` (compressions), `:1693` (rescuer
  vitals), `:1777` (ventilations), `:1833` (pulse checks) — each writes
  `Note,${_esc(d.note!)}` when `d.note != null`.
- A ZIP bundling all four raw CSVs exists too (`exportRawDataZip` /
  `downloadRawDataZip`, wired at `export_bottom_sheet.dart:632-633`).

---

## 5. Session identity without the notes field

If the notes field is ever blank, mistyped, or lost, every raw CSV export
still opens with this metadata block (`export_service.dart:1303-1314`, and
mirrored at the top of the rescuer-vitals/ventilations/pulse-checks CSVs):

- **Session ID** — `d.id ?? "local"` (the Postgres integer id once synced;
  the literal string `"local"` for a session never pushed to the backend).
- **Date & Time** — `d.sessionStart`, formatted (`_fmtDt`), i.e. the exact
  session-start timestamp — this is also the field the backend keys
  `ON CONFLICT (user_id, session_start)` on (`session.js:297`), so it is
  already the de-facto unique identifier per user.
- **Mode** — Emergency / Training / Training (No Feedback), from `d.mode`.
- **Scenario** — Adult / Pediatric, from `d.scenario`.

An analyst working from raw exports alone (no notes) can therefore always
distinguish sessions by **(session id or "local") + exact start timestamp +
mode + scenario** — sufficient to reconstruct which of a participant's
sessions is which *as long as the file itself is correctly attributed to a
participant*, since none of these four fields carry the participant code —
that link exists only through the notes field (§3) or through
whatever external record (filename, folder) the researcher keeps outside the
app.

---

## 6. Rescuer vitals write path

Full trace, BLE → local → Postgres → export.

**BLE — continuous, unconditional on mode.**
- `shared_state.h:82-83` — `heartRateUser` (BPM), `spO2User` (%) — plus (per
  the earlier grep) `rescuerFatigueScore`, `rescuerSignalQuality`,
  `rescuerRMSSD`, `rescuerTemperature`, `rescuerPI`, `rescuerHumidity` all
  live in the same `SharedState` struct read by the LIVE_STREAM builder.
- `cpr_glove.ino:1501-1502` — `gState.heartRateUser = hr; gState.spO2User = spo2;`
  set from the wrist MAX30102 read, independent of `currentMode`.
- `ble_manager.cpp:153-160` — packed into the **LIVE_STREAM** packet:
  `heartRateUser` (byte 72, f32), `spO2User` (byte 76, f32),
  `rescuerFatigueScore` (byte 49), `rescuerSignalQuality` (byte 80),
  `rescuerRMSSD` (byte 81), `rescuerTemperature` (bytes 82-83, fixed-point),
  `rescuerPI` (byte 84), `rescuerHumidity` (byte 85) — none of these byte
  packs are conditioned on `GloveMode` or the `pulseCheckActive` gate (that
  gate applies only to the separate *patient*-vitals block per CLAUDE.md).
  This packet streams continuously during any active session.
- `ble_manager.cpp:276-284` — **SESSION_END** packet also carries session-level
  snapshots: `rescuerHRLastPause` (byte 74), `rescuerSpO2LastPause` (byte 78),
  `rescuerTemperatureStart` (byte 82), `rescuerTemperatureEnd` (byte 86),
  `rescuerSwapCount` (byte 92).
- `cpr_glove.ino:1078-1079`, `1236-1237` — `rescuerHRLastPause` /
  `rescuerSpO2LastPause` are latched from the live `heartRateUser`/`spO2User`
  values at ventilation-window and pulse-check-window boundaries.
- Diagnostic-only channel: `ble_manager.cpp:406-433` packs raw rescuer PPG
  (filtered AC + DC counts) into the **DIAG** response packet
  (`max30102DiagRescuerFiltered()`/`max30102DiagRescuerDc()`) — a
  developer/self-test path, not part of normal session recording.

**App — accumulation into `SessionDetail`.**
- `ble_connection.dart:627-649` — every 5 seconds while `_sessionActive`
  ("regardless of signal quality" — explicit in the comment), a
  `RescuerVitalSnapshot` is appended with `heartRate`, `spO2`, `rmssd`,
  `rescuerPi`, `temperature`, `fatigueScore`, `signalQuality`, `humidity`,
  and a derived `pauseType` (`pulse_check` / `ventilation` / `active`). No
  mode check, no login check gates this — it runs identically in Emergency,
  Training, and NoFeedback.
- Session-level snapshot fields (`rescuerHRLastPause`,
  `rescuerSpO2LastPause`, `rescuerWristTempStart`, `rescuerWristTempEnd`) are
  copied from the SESSION_END packet into `SessionDetail` in
  `session_detail.dart:585-588` (`fromBleSession`) / `:666-671`
  (`fromJson`).
- Also live-displayed: `live_cpr_screen.dart:939-944` renders a `VitalsCard`
  labelled **"Your Vitals"** with `_heartRateUser`, `_spO2User`,
  `_rescuerTemperature`, `_rescuerSignalQuality` in real time during the
  session — so the rescuer's own vitals are shown on-screen live, not just
  logged silently.

**Local storage.** `SessionLocalStorage.saveLocal` (`session_local_storage.dart:36-75`)
JSON-encodes the *entire* `SessionDetail.toJson()`, which includes
`'rescuer_vitals': rescuerVitals.map((e) => e.toJson()).toList()`
(`session_detail.dart:774`) — so the full per-5-second vitals timeline is
written to `SharedPreferences` for every session, synced or not.

**Postgres.** `session.js`:
- Session-level columns on `cpr_sessions`: `user_heart_rate`,
  `user_temperature` (from the legacy `/summary` insert,
  `session.js:82-104`), and on the `/detail` upsert (`session.js:269-295`):
  `rescuer_hr_last_pause`, `rescuer_spo2_last_pause`,
  `rescuer_wrist_temp_start`, `rescuer_wrist_temp_end`.
- Full per-sample timeline: `session_rescuer_vitals` table, inserted per row
  in the loop at `session.js:514-536` — columns `heart_rate`, `spo2`,
  `rmssd`, `rescuer_pi`, `temperature`, `fatigue_score`, `signal_quality`,
  `pause_type`, `humidity`, keyed by `session_id` and `timestamp_ms`.
  Read back verbatim in `GET /sessions/:id/detail`
  (`session.js:681-696`).

**Export.** `export_service.dart` — `_buildRescuerVitalsCsv` (from
`d.rescuerVitals`, header block at `export_service.dart:1597` onward) writes
one row per 5-second snapshot with heart rate, SpO2, RMSSD, perfusion index,
temperature, fatigue score, signal quality, pause type, and humidity, plus
the same session-metadata header (ID/timestamp/mode/scenario/note) as the
compressions CSV. Reachable via `exportRawRescuerVitalsCsv` /
`downloadRawRescuerVitalsCsv` (`export_bottom_sheet.dart:592-593`), and
bundled into `exportRawDataZip` (`export_bottom_sheet.dart:632-633`).

**Summary of every place rescuer physiological data lives:** wrist
MAX30102/temperature sensor reads → `SharedState` (firmware, continuously)
→ LIVE_STREAM BLE packet (every stream tick, all modes) + SESSION_END BLE
packet (session-boundary snapshots) → `ble_connection.dart`'s 5-second
`RescuerVitalSnapshot` accumulator and live "Your Vitals" UI card →
`SessionDetail.rescuerVitals` / snapshot fields → `SessionLocalStorage`
(SharedPreferences, always) → Postgres `session_rescuer_vitals` table +
`cpr_sessions` snapshot columns (only if/when synced) → raw rescuer-vitals
CSV / ZIP export (from whichever copy — local or synced — is in memory).
