# BLE Spec Reconciliation — `CPR_Assist_BLE_Spec_v3_2.md` vs code

Read-only. No file edited. Code is authoritative (CLAUDE.md), so every row
below is a proposed **spec** change unless marked CODE.

Sources read: `CPR-Assist-Firmware-LeftHand/ble_manager.cpp` (every packet
builder), `config.h` (thresholds, packet/command codes), `storage.cpp`
(binary layout), the sketch `C:\Users\evaro\Documents\Arduino\cpr_glove_new\cpr_glove_new.ino`
(event triggers, command handlers), `ble_data_processor.dart` and
`offline_session_parser.dart` (app side), `firmware/SIGNALS.md`.

Scope: spec §3, §4, §5, §8 in full. §6, §7, §10, §12 only where they repeat
a claim already found wrong in §3–§5. §9 (grading) and §11 (backend) not
audited, since grading is on the do-not-touch list and §11 needs the backend
schema.

Mark each row APPROVED / REJECTED. The apply pass touches only approved rows
and adds a v3.3 changelog entry listing them.

---

## 1. LIVE_STREAM (§3)

Firmware and app agree on every byte below. Only the spec is behind.

| # | Bytes | Spec says | Code does | Proposed spec change |
|---|---|---|---|---|
| L1 | 52–55 | reserved, always 0 | `float32 residualLoadDepthCm` (`ble_manager.cpp:135`). Force→depth proxy of residual load between compressions, not an IMU depth. | Document the field, with the "not an IMU depth" caveat. |
| L2 | 86 | reserved | `uint8 inVentilationWindow` 0/1 (`:162`) | Document. Byte 87 stays reserved. |
| L3 | 102–107 | reserved | `float32 lastPeakDepthCm` 102–105 (depth selector output), `uint8 lastPeakConfidence` 106 (0–100), `uint8 lastPeakDepthSource` 107 (`DepthSource` enum 0–7) (`:177-184`) | Document all three, plus the enum values. |
| L4 | 91 | `feedbackEnabled` 0/1 | 3-bit mask: bit0 audio, bit1 haptic, bit2 visual (`:169-171`). App decodes per bit. | Rename to `feedbackMask`, document bits. |
| L5 | 56–71 | Patient vitals valid only when `pulseCheckActive` | Also sent when `diagActive` (`:142`) | Add "or while diagnostics are active". |
| L6 | 70–71 | patientTemperature "updated every 5 s, last valid reading persists between updates" | Zeroed outside a pulse-check window, by design (`:137-141`). The persisting value is SESSION_END 66–69. | Replace with "zero outside a pulse-check window". |
| L7 | 24–27 | wristAlignmentAngle "3D deviation… fused from both IMUs… target < 15°" | `fabsf(palm pitch)`, palm IMU only (CLAUDE.md, SIGNALS.md). Warn threshold `WRIST_ALIGN_WARN_DEG` = **30°** (`config.h:328`). | Palm pitch, absolute, palm IMU only. Threshold 30°. |
| L8 | 32–35 | compressionAxisDeviation "from wrist-side IMU" | `fabsf(palm roll)`, palm IMU | Palm roll, palm IMU. |
| L9 | 43 | postureOk = alignment < 15° AND flexion within ±10° | `fabsf(wristAlignmentAngle) < WRIST_ALIGN_WARN_DEG` (30°). Flexion is not a term. | Correct the definition. |
| L10 | 48 | fatigueFlag = rolling avg dropped > 1 cm from **session peak** | One-shot latch when decline from the **first-5-compression baseline** ≥ `FATIGUE_DECLINE_THRESHOLD_MM` (10 mm) | Correct the definition. Same fix at §4.1 0x08, §6 row "Fatigue flag", §12 item 15. |
| L11 | 51 | wristDropped = I2C read fails or NaN | Latch after `WRIST_DROPOUT_LIMIT` consecutive zero-depth wrist strokes. Clears on session reset (Block C). | Correct the definition. Same at §12 item 18. |
| L12 | 50 | imuCalibrated "requires 3+ compressions" | `cfPalm.initialised && gravPalm.cycles >= GRAV_MIN_CYCLES_PALM` (3) | Consistent. Optionally name the constant. No change needed. |

## 2. EVENT_CHANNEL (§4)

| # | Packet / bytes | Spec says | Code does | Proposed spec change |
|---|---|---|---|---|
| E1 | 0x04 PULSE_CHECK_START, §4.1 row | "Every 2 minutes of active CPR time, Emergency only, when force drops to 0" | Passive gate: rescuer paused + sustained patient-sensor contact ≥ `PULSE_GATE_CONTACT_DEBOUNCE_MS` (500 ms), Emergency only, one check per carotid palpation (sketch `:1201-1260`). No timer. | Rewrite trigger. |
| E2 | 0x04 bytes 1–2 | intervalNumber = "which 2-minute interval" | `_pulseCheckCount`: 1-based count of checks this session | Rename meaning to "pulse check number". Same in §7.3 and §8.2 pulse array. |
| E3 | 0x05 §4.1 row | "After 10-second pulse check window completes" | Window closes on `WINDOW_RESUME_COMP_COUNT` (2) compressions after a pause, non-compliant dismiss, or `WINDOW_MAX_BACKSTOP_MS` (100 s) backstop | Rewrite close condition. |
| E4 | 0x05 byte 9 | reserved | `refSource` self-detection reference: 0 NONE, 1 LIVE, 2 PAUSED (`ble_manager.cpp:326`, `config.h:73-75`). App parses it (`pulseCheckRefSource`). | Document. Note: data capture only, no gating effect. |
| E5 | 0x05 byte 1 classification | ABSENT/UNCERTAIN/PRESENT | Same. Plus self-detection downgrade Present→Uncertain (CORRECTIONS.md) | Add one sentence on the downgrade and that byte 9 records its reference. |
| E6 | 0x02 SESSION_END byte 95 | reserved | `wristDroppedDuringSession` 0/1 (`:290`). App parses it. | Document. |
| E7 | 0x02 §4.1 row | "120 s inactivity with no compressions at any point in session" | 120 s since the **last** compression, suspended while a pulse-check or ventilation window is open (sketch `:1053`) | Correct. Same at §5.1 step 9. |
| E8 | 0x02 bytes 42–45 correctVentilations | rescuer paused ≥ 1 s | Pause ≥ `WINDOW_PAUSE_COMPLIANT_MS` (**3 s**) after a 2.5 s grace period | Correct. Same at §5.1 step 4, §7.2, §8.2, §10.1, §12 item 20. |
| E9 | 0x02 bytes 46–49 pulseChecksPrompted | "2-min pulse check windows triggered" | Pulse-check windows opened by the passive gate | Correct wording. |
| E10 | 0x02 bytes 50–53 pulseChecksComplied | "times rescuer stopped compressions" | Windows that closed with patient SQI ≥ 40, i.e. a classifiable signal (sketch `:1412-1419`) | Correct definition. |
| E11 | 0x0B SELFTEST_RESULT bytes 5–15 | reserved | 5 `i2cScanMask`, 6 `palmWhoAmI`, 7 `wristWhoAmI`, 8–15 per-sensor `reasonCodes[8]` (`:377-381`). App parses all. | Document, with the reason-code enum from `selftest.h`. |
| E12 | 0x0B trigger | "triggered by 0xFC or on power-on" | Also sent after 0xF7 CALIBRATE, and as an all-NOT_TESTED reply when 0xFC/0xF7 arrive mid-session | Add both. |
| E13 | 0xF7 CALIBRATE | "500 ms silent gravity baseline… sends SESSION_START when complete if session was active" | Idle only. Re-runs `forceInit()` until the force baseline converges (2 s timeout), then selftest, replies SELFTEST_RESULT. Refused mid-session. Never sends SESSION_START. | Rewrite. Same at §12 item 31. |
| E14 | Commands missing from §4.1 | — | 0xFE SET_FEEDBACK_CH (bit mask), 0xFF SET_VOLUME (byte1 audio 0–30, byte2 motor intensity), 0xEB SET_LED_BRIGHTNESS, 0xED DIAG_START, 0xEC DIAG_STOP, 0xEE DIAG_ACTION. All in `config.h:91-99` and app `kCmd*`. | Add six rows. |
| E15 | 0xF3/0xF4 | Reserved app-side | Matches (CORRECTIONS.md note M24) | No change. |

## 3. Session lifecycle (§5)

| # | Step | Spec says | Code does | Proposed spec change |
|---|---|---|---|---|
| S1 | 5.1 step 7 | "2-min mark, force drops to 0… full-screen pulse check overlay" | Passive gate (E1). App shows a non-blocking card in the Live CPR screen (CORRECTIONS.md, `pulse_check_overlay.dart`). | Rewrite. |
| S2 | 5.1 step 8 | "After 10 s… two buttons Continue CPR / Stop CPR" | Window close as E3. Result is stored and shown on the results screen, not on the live card (CORRECTIONS.md App section). | Rewrite. Same in §10.1 "Pulse check overlay" row. **Verify the buttons and "60 s auto-end" claim against the app before editing**, as I did not trace that UI. |
| S3 | 5.1 step 2 | "500 ms gravity baseline" | Not traced in this pass | Leave, flag for a later check. |
| S4 | 5.3 | Pulse check skipped in Training | Firmware gates on `GloveMode::Emergency` (sketch `:1201`) | Consistent. No change. |

## 4. Local storage (§8)

| # | Item | Spec says | Code does | Proposed spec change |
|---|---|---|---|---|
| F1 | File name | `/sessions/sess_<index>.bin` | `/sessions/s%02d.bin` (`storage.cpp:85`) | Correct. |
| F2 | Meta file | write pointer, total, synced flags[20], uint64 timestamps ×20 | 41 bytes: state[20] (0 empty, 1 pending), insertion seq[20], seqCounter (`storage.cpp:46-55`). Confirmed sessions are deleted, not flagged. | Rewrite. |
| F3 | Header temperature fields | patientTemperature, rescuerTemperature, rescuerHRLastPause, rescuerSpO2LastPause, wristTempStart, wristTempEnd (6 floats) | patientTemperatureLastPulseCheck @77, rescuerTemperatureStart @81, rescuerTemperatureEnd @85, rescuerHRLastPause @89, rescuerSpO2LastPause @93 (5 floats, different order). Header = 104 bytes. | Replace with the code order, add byte offsets. |
| F4 | Compression entry | 5 u8 fields then reserved u8[4] (sums to 21) | 17 named bytes + 3 unused = 20 (`STORAGE_COMPRESSION_SIZE`) | reserved u8[3]. |
| F5 | Pulse-check entry | 12 bytes, last byte reserved | **13** bytes: + detectorACount @11, detectorBCount @12 (`storage.cpp:278-279`). App parser uses 13. | Correct size and fields. |
| F6 | Vent entry `ventilationsGiven` | "pauses > 1 s detected (0–2+)" | Holds the number of **compressions** during the window (`compsDuringWindow`, sketch `:1186`) | Correct spec text. See CODE note C1. |
| F7 | Save threshold | — | Sessions with < `STORAGE_MIN_COMPRESSIONS_TO_SAVE` (3) compressions are not saved | Add. |
| F8 | Size estimate | ~5–7 KB per 2-min session | 104 + 20 B/compression: 200 comps ≈ 4.2 KB. Cap 600 compressions. | Correct estimate, add the cap. |

## 5. Code-side findings (not spec edits — report only)

| # | Where | Finding |
|---|---|---|
| C1 | sketch `:1186`, `StoredVentilation::ventilationsGiven` | Field name says breaths, value is compressions during the window. Fix by rename (storage layout unchanged) or leave and document. A rename touches firmware, offline parser, model, DB column if any — five-layer rule applies. |
| C2 | `storage.cpp:38` header comment | Says pulse array is 12 bytes. It is 13. Stale comment. |
| C3 | `ble_manager.cpp:188` comment | "LIVE_STREAM is 10 Hz (Spec v3.1)". Spec is v3.2. Cosmetic. |
| C4 | `CLAUDE.md` | Names `CPR_Assist_BLE_Spec_v3_1.md`. The file is `_v3_2.md`. |
| C5 | App posture graph (§10.2 claims 0–15° green band) | If the app draws a 15° band while the firmware warns at 30°, the two disagree. Not verified in the app. |

---

Nothing above has been edited. Awaiting approval.

---

## 6. Addendum 2026-10-15 — §9 grading and §11 backend

Read-only. Sources: `calculateGradeFromDetail` (`session_service.dart`),
`SessionDetail.applyPauseModel`, `CPR-Assist-Server/db.js`.

### §9 Grading — weights and time bands match the code. Three gaps:

| # | Spec says | Code does | Proposed spec change |
|---|---|---|---|
| G1 | — | Fewer than 10 compressions → grade 0 (`session_service.dart:285`) | Add the rule. |
| G2 | Ventilation = correctVentilations / totalVentilations | `ventilationCompliance` from the app's measured pauses (3–15 s), which also overwrites correctVentilations. The glove's own count is not used. | Say where the number comes from; point to §7.2. |
| G3 | Labels A–D: "Excellent!", "Good job!", "Keep it up!", "Keep practicing!" at 90/75/55 | Same 90/75/55 bands, but no letters. The PDF uses "Outstanding!", "Great work!", "Keep it up!", "Keep practising!" (`export_service.dart:3341`); the leaderboard uses the bands for colour only. | Replace §9.3 with the bands and the PDF wording. |

### §11 Backend — spec is far behind `db.js`. Session timestamps are TIMESTAMPTZ (spec says TIMESTAMP).

| Table | In `db.js`, missing from spec |
|---|---|
| cpr_sessions | no_flow_intervals_firmware, unplanned_pause_time, unplanned_pause_count, wrist_dropped_during_session, patient_spo2_last_check, fatigue_alert_timestamp_ms, fatigue_alert_score, two_min_alert_timestamps_ms, two_min_alert_numbers, mode_change_timestamps_ms/values/triggers, scenario_change_timestamps_ms/values/triggers |
| session_compressions | valley_depth (= residualLoadDepthCm), peak_ts, valley_ts |
| session_pulse_checks | interval_from_start, ref_source, patient_spo2, ppg_samples (JSONB) |
| session_rescuer_vitals | humidity |

Also: spec `no_flow_time` note says "unplanned gaps > 2 s", but §6 defines
no-flow as all gaps > 2 s including planned pauses; unplanned is its own
column. Endpoints (§11.3) not checked.

Proposed: rewrite §11.1–11.2 from `db.js` as-is. Spec only, no DB change.
