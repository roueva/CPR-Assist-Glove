# Firmware Signal Dictionary

Read-only audit. No firmware or app files were edited.


Files actually present and read: `config.h`, `shared_state.h`, `depth.cpp/.h`,
`force.cpp/.h`, `imu.cpp/.h`, `max30102.cpp/.h`, `max30205.cpp/.h`,
`gxht30.cpp/.h`, `battery.cpp/.h`, `ble_manager.cpp/.h`, `cpr_glove.ino`.
`storage.cpp` and `selftest.cpp` were opened only to verify two cross-file
claims (marked below) — they were not otherwise audited.

---

## 1. LIVE_STREAM (108 bytes, 10 Hz, `ble_manager.cpp:bleSendLiveStream`)

| Firmware variable | Unit | Derivation | BLE byte(s) | App field | UI label |
|---|---|---|---|---|---|
| `gState.depth` | cm | `_displayDepthCm`, an EMA of the live depth estimate. While compressing: always IMU-integrated palm depth (`fmaxf(0, integPalm.depthM*100)`) — tried switching to the force model once calibrated, reverted 2026-09-16: `forceN` is sampled instantaneously and peak force during a stroke is a brief, narrow spike, so the EMA filter structurally undershoots it (confirmed on hardware: final graded depth 5.2cm, correct, bar still showing orange/below-band). The unsmoothed IMU integral rises continuously through the downstroke and doesn't have that problem. Between strokes (leaning on the chest), the force model is used whenever `forceN > FORCE_LEANING_THRESHOLD` (5N) — a coarse "you're pressing" indicator, not compared against target thresholds, so this branch was unaffected by the above and unchanged all session. 0 when truly released. The depth-reached click (`_clickJustFired`) reads the separate `_liveDepthCm`, NOT this value — tried unifying them 2026-09-16 too, also reverted (see fixes-applied log): `_displayDepthCm` doesn't zero on release when leaning, so the click never re-armed. Written in `depth.cpp:431-460`. | 0-3 f32 | `depth` | depth bar |
| `gState.frequency` | BPM | 5-compression rolling average from `rollingRate()` (`depth.cpp:58-63,756`). ~~**DEFECT**~~ — comment was stale, not the derivation; fixed, see "Fixes applied" item 3 below. | 4-7 f32 | `frequency` | rate gauge (display) |
| `gState.force` | N | Last `forceRead()` value, filtered force in Newtons (`depth.cpp:823`). | 8-11 f32 | `force` | none (internal) |
| `gState.instantaneousRate` | BPM | `_gradeRate`: the exact rate from the single most-recently-completed compression's own inter-compression interval (`depth.cpp:679,757`). | 12-15 f32 | `instantaneousRate` | grading only |
| `gState.compressionCount` | count | `_totalCompressions`, incremented on every compression start including pre-calibration (`depth.cpp:495,758`). | 16-19 i32 | `compressionCount` | compression counter |
| `gState.compressionInCycle` | count | Compressions since the last ventilation wrap, mod `ventilationCompressions` (`depth.cpp:785-789`). | 20-23 i32 | `compressionInCycle` | 30:2 cycle indicator |
| `gState.wristAlignmentAngle` | deg | `fabsf(imuGetPalmPitchDeg())` — palm-IMU CF pitch, absolute value (`depth.cpp:819`, `imu.cpp:369-371`). | 24-27 f32 | `wristAlignmentAngle` | alignment indicator |
| `gState.wristFlexionAngle` | deg, ±45 | `cfPalm.pitch - cfWrist.pitch` in degrees, or 0 if wrist IMU dropped (`imu.cpp:376-378`, `depth.cpp:820-821`). | 28-31 f32 | `wristFlexionAngle` | flexion indicator |
| `gState.compressionAxisDeviation` | deg | `fabsf(imuGetPalmRollDeg())` — palm-IMU CF roll (`depth.cpp:822`). | 32-35 f32 | `compressionAxisDeviation` | axis deviation indicator |
| `gState.depthTrend` | cm | 5-compression rolling average of peak depths, mm→cm (`depth.cpp:80-85,761`). | 36-39 f32 | `depthTrend` | trend line |
| `gState.recoilAchieved` | bool | `_recoilValleyForceN < FORCE_LEANING_THRESHOLD && _recoilValleyDepthMM < RECOIL_RESIDUAL_MAX_MM` (`depth.cpp:715-716,729`). | 40 u8 | `recoilAchieved` | recoil flag |
| `gState.leaningDetected` | bool | Force > `FORCE_LEANING_THRESHOLD` while released, sustained ≥`LEANING_PERSISTENCE_MS` (`depth.cpp:457-466`). | 41 u8 | `leaningDetected` | leaning flag |
| `gState.overForceFlag` | bool | Peak force this compression > scenario overforce limit (`depth.cpp:718,730`). | 42 u8 | `overForceFlag` | over-force flag |
| `gState.postureOk` | bool | `fabsf(wristAlignmentAngle) < WRIST_ALIGN_WARN_DEG` (`depth.cpp:717,731`). | 43 u8 | `postureOk` | posture flag |
| `gState.ventilationCount` | count | `_ventCycleNum`, incremented each ventilation window open (`cpr_glove.ino:1032,1042`). | 44-47 u32 | `ventilationCount` | ventilation counter |
| `gState.fatigueFlag` | bool | One-shot latch when depth decline ≥ threshold (`depth.cpp:253-264`). | 48 u8 | `fatigueFlag` | fatigue flag |
| `gState.rescuerFatigueScore` | 0-100 | `decline / FATIGUE_DECLINE_THRESHOLD_MM * 100`, clamped (`depth.cpp:245-250`). | 49 u8 | `rescuerFatigueScore` | fatigue meter |
| `gState.imuCalibrated` | bool | `cfPalm.initialised && gravPalm.cycles >= GRAV_MIN_CYCLES_PALM` (`imu.cpp:643-648`). | 50 u8 | `imuCalibrated` | calibration indicator |
| `gState.wristDropped` | bool | `_wristDropped` latch after `WRIST_DROPOUT_LIMIT` consecutive zero-depth wrist strokes (`imu.cpp:617-626`). | 51 u8 | `wristDropped` | wrist-dropout flag |
| `gState.valleyDepth` | cm | **Not** the IMU-measured valley. It's the residual inter-compression *force*, run back through the force→depth power law, mm→cm (`depth.cpp:771-776`). Deliberate — comment states this is so leaning shows non-zero on the graph. The *grading* boolean `recoilAchieved` uses a different, IMU-based signal (`_recoilValleyDepthMM`) that is never itself transmitted. | 52-55 f32 | `valleyDepth` | recoil/valley graph |
| `gState.heartRatePatient` | BPM | Median of last-8 RR intervals, patient MAX30102 channel, gated `>0` contact (`max30102.cpp:264,453`). Sent only when `pulseCheckActive \|\| diagActive`, else zeroed (`ble_manager.cpp:141-150`). | 56-59 f32 | `heartRatePatient` | patient HR |
| `gState.spO2Patient` | % | `maxim_heart_rate_and_oxygen_saturation()` on patient channel, gated valid + 70-100% (`max30102.cpp:455-457`). | 60-63 f32 | `spO2Patient` | patient SpO2 |
| `gState.ppgRaw` | 0-1 | AC-coupled, bandpass-filtered patient waveform re-centred on 0.5 (`max30102.cpp:432-434`). | 64-67 f32 | `ppgRaw` | PPG waveform |
| `gState.ppgSignalQuality` | 0-100 | Composite SQI: env/regularity/stability/beat-count weighted sum, patient channel (`max30102.cpp:285-323,454`). | 68 u8 | `ppgSignalQuality` | signal quality bar |
| `gState.perfusionIndex` | 0-100 | `(envelope/dc)*100*10`, clamped, patient channel (`max30102.cpp:458-459`). | 69 u8 | `perfusionIndex` | perfusion indicator |
| `gState.patientTemperature` | °C | `max30205ReadCelsius()`, gated on patient contact (`cpr_glove.ino:1506-1528`). | 70-71 u16×100 | `patientTemperature` | patient temp |
| `gState.heartRateUser` | BPM | Same pipeline as patient, rescuer MAX30102 channel, continuous (`max30102.cpp:383`). | 72-75 f32 | `heartRateUser` | rescuer HR |
| `gState.spO2User` | % | Rescuer-channel SpO2, same gating as patient (`max30102.cpp:385-387`). | 76-79 f32 | `spO2User` | rescuer SpO2 |
| `gState.rescuerSignalQuality` | 0-100 | Composite SQI, rescuer channel (`max30102.cpp:384`). | 80 u8 | `rescuerSignalQuality` | rescuer signal quality |
| `gState.rescuerRMSSD` | ms, 0-200 | RMSSD over 60 s RR window, rescuer channel, clamped (`max30102.cpp:390-392`). | 81 u8 | `rescuerRMSSD` | HRV indicator |
| `gState.rescuerTemperature` | °C | `gxht30Read()` wrist temp, refreshed every 500 ms (`cpr_glove.ino:1452-1465`). | 82-83 u16×100 | `rescuerTemperature` | rescuer temp |
| `gState.rescuerPI` | 0-100 | `(envelope/dc)*100*10`, clamped, rescuer channel (`max30102.cpp:389`). | 84 u8 | `rescuerPI` | rescuer perfusion |
| `gState.rescuerHumidity` | % | `gxht30Read()` humidity (`cpr_glove.ino:1465`). | 85 u8 | `rescuerHumidity` | humidity |
| `gState.inVentilationWindow` | bool | `_inVentWindow` mirror (`cpr_glove.ino:1044,1118`). | 86 u8 | `inVentilationWindow` | ventilation-window flag |
| — reserved — | — | Always 0 (buffer is zero-initialised, byte never written in normal mode). | 87 u8 | (unused) | — |
| `gState.sessionActive` | bool | Session running flag (`cpr_glove.ino:418,486`). | 88 u8 | `sessionActive` | session state |
| `gState.pulseCheckActive` | bool | Pulse-check window open flag (`cpr_glove.ino:1193,1268`). Do-not-touch gating (CLAUDE.md) — passive contact+pause only. | 89 u8 | `pulseCheckActive` | pulse-check indicator |
| `gState.currentMode` | enum | `GloveMode` (0 Emergency/1 Training/2 NoFeedback). | 90 u8 | `currentMode` | mode indicator |
| `audioFeedbackEnabled\|hapticFeedbackEnabled\|visualFeedbackEnabled` | 3-bit mask | `(audio?1:0)\|(haptic?2:0)\|(visual?4:0)` (`ble_manager.cpp:168-170`). **DEFECT** (cross-file) — `ble_data_processor.dart:215` reads this byte as `feedbackEnabled = b.getUint8(91) == 1`. Firmware's own default state sets all three flags true, so byte 91 = 0x07, and the app's equality-to-1 check reads `feedbackEnabled` as **false** in the normal all-on case. Only the audio-only combination (0x01) reads true. | 91 u8 (bitmask) | `feedbackEnabled` (bool) | (feedback-enabled indicator, if used) |
| `gState.batteryPercentage` | 0-100 | `batteryPercent()` — `analogReadMilliVolts()` (factory-calibrated, avg of 4) → `BAT_ADC_DIVIDER` → piecewise-linear LiPo curve (`BAT_LIPO_CURVE`, config.h) → EMA-smoothed, clamped monotonically non-increasing while discharging, frozen at last discharge value while charging. On the charging→not-charging edge, the gauge waits `BAT_CHARGE_SETTLE_MS` (5 s, LiPo surface-charge relaxation) then re-seeds the EMA and its monotonic-clamp reference from a fresh curve lookup, so it recovers to the true post-charge level instead of resuming from the pre-charge value (`battery.cpp`, `cpr_glove.ino:1538`). | 92 u8 | `batteryPercentage` | battery indicator |
| `gState.isCharging` | bool | `digitalRead(PIN_CHARGE_DETECT)==HIGH` (`battery.cpp:27`). | 93 u8 | `isCharging` | charging indicator |
| `gState.peakTimestampMs` | ms | ms since session start when the IMU integrator locked this compression's peak (`depth.cpp:385-387,764`). | 94-97 u32 | `peakTimestampMs` | (analysis) |
| `gState.valleyTimestampMs` | ms | ms since session start when the valley minimum was captured (`depth.cpp:507-508,765`). | 98-101 u32 | `valleyTimestampMs` | (analysis) |
| `gState.lastPeakDepthCm` | cm | The selector's chosen depth (`selectDepth()` output) for the just-completed compression (`depth.cpp:583-589`). | 102-105 f32 | `lastPeakDepthCm` | depth readout |
| `gState.lastPeakConfidence` | 0-100 | `selectDepth()` confidence ×100 (`depth.cpp:591`). | 106 u8 | `lastPeakConfidence` | confidence badge |
| `gState.lastPeakDepthSource` | enum 0-7 | `DepthSource` from `selectDepth()` (`depth.cpp:592`). | 107 u8 | `lastPeakDepthSource` | source badge |

### Diagnostic-mode data

No longer a LIVE_STREAM overlay. Moved to its own EVENT_CHANNEL packet,
`DIAG_FRAME` — see "Block D fixes" at the end of this document for the byte
layout and why the overlay design (aliasing bytes 52-55/86-87/102-107, which
carry real fields in normal mode) was replaced.

---

## 2. EVENT_CHANNEL packets (96 bytes, on-event, `ble_manager.cpp`)

Only fields with a non-trivial derivation are listed; pass-through enum/count
bytes are omitted for brevity (all matched their app-side field one-for-one on
inspection).

| Firmware variable | Unit | Derivation | BLE byte(s) | App field |
|---|---|---|---|---|
| `s.patientTemperatureLastPulseCheck` | °C | Last patient temp captured *while in contact during a pulse check* — persists after the window closes, unlike the live `patientTemperature` (`shared_state.h:79`, `cpr_glove.ino:1527`). | SESSION_END 66-69 f32 | `patientTemperature` (in `_event` ctor). **DEFECT** (naming) — app field name drops the "last pulse check" qualifier the firmware name carries; a reader of `ble_data_processor.dart` alone would assume this is a live/instantaneous reading. | 
| `s.rescuerTemperatureStart` / `s.rescuerTemperatureEnd` | °C | Wrist temp captured at `startSession()`/`stopSession()` (`cpr_glove.ino:445,488`). | SESSION_END 82-85 / 86-89 f32 | `rescuerWristTempStart` / `rescuerWristTempEnd`. Naming disagreement (firmware omits "Wrist", app adds it) — harmless but inconsistent. |
| `s.timeToFirstCompressionMs` | ms | Set once, on the first compression of the session, from `_peakTimestampMs` (`depth.cpp:750-752`). | SESSION_END 93-94 u16 | `timeToFirstCompressionMs` |
| `r.reasonCodes[8]` | code enum | Per-sensor selftest failure reason, parallel to the pass/warn/critical bitmasks (`selftest.h:19-27`, out of primary scope). | SELFTEST_RESULT 8-15 | `selftestReasonCodes` |

`SESSION_START`, `VENTILATION_WINDOW`, `PULSE_CHECK_START`, `PULSE_CHECK_RESULT`,
`MODE_CHANGE`, `TWO_MIN_ALERT`, `FATIGUE_ALERT`, `PENDING_LOCAL_DATA`,
`LOCAL_SESSION_CHUNK`, `SCENARIO_CHANGE`: byte layouts in `ble_manager.cpp`
match `ble_data_processor.dart`'s parser byte-for-byte and field-for-field. No
defects found in these packets themselves.

---

## 3. Internal-only signals (not on BLE)

| Firmware variable | Unit | Derivation | Consumer |
|---|---|---|---|
| `s.rescuerSQLastPause` | 0-100 | SQI paired with `rescuerHRLastPause`, captured at the same moment (`shared_state.h:132`, `cpr_glove.ino:1205,1298`). | `max30102ClassifyPulse()` self-detection guard (`cpr_glove.ino:1297-1318`) only. Explicitly documented in `shared_state.h:126-131` as "not part of the transmitted SESSION_END summary." Not a defect — correctly internal. |
| `_recoilValleyDepthMM` | mm | IMU-measured residual depth at valley (`depth.cpp:514`). | Feeds `recoilAchieved` grading (`depth.cpp:715-716`) and would feed `StoredCompression.residualDepthX10` — see §A, that write never happens. Never itself reaches BLE (contrast with the force-derived `valleyDepth` that does — see LIVE_STREAM table above). |
| `battery.cpp: _voltage` (`batteryVoltage()`) | V | Raw battery voltage before percentage mapping (`battery.cpp:26,40-42`). | Nothing — see §A, dead accessor. Only the derived percentage is ever transmitted. |

---

## A. Dead variables / functions

Declared and defined, but never called/read from anywhere else in the
firmware (verified by grep across all `.cpp`/`.h`/`.ino` in `CPR-Assist-Firmware/`).

| Symbol | Declared | Defined | Notes |
|---|---|---|---|
| `StoredCompression::residualDepthX10` | `depth.h:20` | never written | The struct field exists with a detailed comment ("Change 23 — IMU-measured residual depth at valley... Tomlinson 2007 mean residual depth was 3±2mm") but the only code that populates a `StoredCompression` (`depth.cpp:795-806`) never assigns it. `storage.cpp`'s serializer (`storage.cpp:246-256`) also never reads it. Fully vestigial — declared, never written, never read. |
| `StoredCompression::reserved[3]` | `depth.h:21` | `depth.cpp:805` (written to 0) | Written every compression, but `storage.cpp`'s manual byte-packer (`storage.cpp:246-256`) only serializes bytes for `timestampMs`/`depth`/`frequency`/`recoil`/`overForce`/`postureOk`/`wristAlignX10`/`axisDevX10` (17 bytes) then advances by `STORAGE_COMPRESSION_SIZE` (20) — the 3 reserved bytes (and `residualDepthX10`) are never read out of the struct. Classic "written but never read." |
| `getAdaptiveDepthMM()` | `imu.h:100` | `imu.cpp:617-639` | Its own header comment (`imu.cpp:609-616`) says it's a "backward-compatibility wrapper" kept so `depth.cpp` wouldn't need changes — but `depth.cpp` already calls `imuCombineDual()` directly (`depth.cpp:570-571`). The migration this function was staged for already happened; the wrapper was never deleted. |
| `imuGetWorldVertAccelPalm()` / `imuGetWorldVertAccelWrist()` | `imu.h:111-112` | `imu.cpp:308-309` | Header comment says these are the new public accessors "for forward-looking clarity," replacing `imuGetMotionAccelPalm/Wrist`. Nothing calls the new names; `depth.cpp` still calls the old ones (`depth.cpp:380-381,398-399`), which read the same underlying `_aPalm`/`_aWrist` statics directly. |
| `imuTriggerFastConverge()` | `imu.h:145` | `imu.cpp:360-366` | Superseded — `depth.cpp:313` calls `imuResetCF()` instead, with an inline comment `// was: imuTriggerFastConverge()`. |
| ~~`max30102DiagRescuerFiltered()` / `max30102DiagRescuerDc()`~~ | `max30102.h:63-64` | `max30102.cpp:532-537` | **No longer dead — fixed in Block D.** Originally: intended to feed a rescuer-channel diagnostic overlay (matches the app's `diagRescuerPpgFiltered` field, `ble_data_processor.dart:207`), but `ble_manager.cpp`'s diag block never called either. Now called directly from `bleBuildDiagFrame()` (`ble_manager.cpp`), which replaced the old LIVE_STREAM diag overlay entirely — see "Block D fixes" below. |
| `forceCalibLocked()` | `force.h:39` | `force.cpp:181-183` | Never called; `_calibLocked` is only read/written internally in `force.cpp` (`forceCalibAddSample`, `forceCalibCompute`). |
| `forceCalibLock()` | `force.h:40` | `force.cpp:185-187` | Never called; `forceCalibCompute()` sets `_calibLocked = true` directly (`force.cpp:238`) instead of calling this setter. |
| `forceResetCalibration()` | `force.h:18` | `force.cpp:262-278` | Never called. Its own comment (`force.cpp:263-267`) already flags this: "Locked builds never reset calibration, even if a future caller is wired up." No caller exists in either build configuration. |
| `batteryVoltage()` | `battery.h:12` | `battery.cpp:40-42` | Never called. Only `batteryPercent()` and `batteryCharging()` are consumed (`cpr_glove.ino:1538-1539`); raw voltage is computed and discarded every 5 s. |
| `depthGetRate()` | `depth.h:35` | `depth.cpp:319-321` | Never called. `s.frequency`/`s.instantaneousRate` are populated directly inside `depth.cpp`, not through this accessor. |
| `PULSE_CHECK_INTERVAL_MS` | `config.h:433` | — | Self-documented: `// unused, retained pending cleanup`. |
| `PULSE_CHECK_DURATION_MS`, `PULSE_CHECK_MAX_WINDOW_MS`, `PULSE_CHECK_RESUME_PROMPT_MS` | `config.h:473-475` | — | "Legacy names kept as aliases... Do NOT use these in new code" — grepped, and indeed nothing does; only the `WINDOW_*` names they alias are used. |

---

## B. Functions whose name doesn't match what they do

| Function | Issue |
|---|---|
| ~~`imuResetCF()`~~ (`imu.cpp:600-607`) | **Fixed in Block E** — renamed to `imuArmCFReset()`, and `imu.h` now carries the doc comment it lacked. Originally: name implied an immediate reset, but it actually only **arms a deferred reset** (`_pendingCFReset = true`) that fires later, once 300 ms of stillness is detected in `imuUpdateFilters()` (`imu.cpp:314-332`). |
| `getAdaptiveDepthMM()` (`imu.cpp:617-639`) | **Symbol deleted** (pre-existing "Fixes applied" #7, before Block C/D/E) — this row now describes code that no longer exists. Left as historical record per this doc's convention. |
| ~~`max30102PatientContact()` vs `max30102PatientContactOk()`~~ (`max30102.h:30,42`) | **Fixed in Block B** — renamed to `max30102PatientContactProbe()` / `max30102PatientContactCached()` respectively, names now carry the contract the old names didn't. Originally: two very similarly-named functions with materially different contracts (`...Contact()` a stateless one-shot probe; `...ContactOk()` cached state only valid once a window is open) — the naming made it easy to reach for the wrong one. |
| ~~`bleDrainEventQueue()`~~ (`ble_manager.cpp:247-265`) | **Fixed in Block E** — renamed to `bleSendNextEvent()`. Originally: "Drain" conventionally implies emptying the queue; the function sent exactly one queued item per call (by design), over-promising relative to `bleFlushEventQueue()`, which *does* empty it. |

---

## C. Sentinels

| Sentinel | Where set | Where checked | Can the check actually see it? |
|---|---|---|---|
| `9999.0f` / `<9000.0f` guard on `_prevValleyForce` (`depth.cpp:76,280,521`) | Reset to 9999 at session start and at every RELEASED→COMPRESSING transition. | `depth.cpp:515` (`_recoilValleyForceN = (_prevValleyForce < 9000.0f) ? ... : 9999.0f`) | Yes — correctly paired. The only way the check sees the sentinel is if valley-tracking never ran a single sample between compressions, which is exactly the "first compression, no prior release" case it's meant to catch. |
| `9999.0f` / `<9000.0f` on `_recoilValleyDepthMM`, `_recoilValleyForceN` (`depth.cpp:77-78,514-516`) | Set to 9999 whenever `_trackingValley` was false or `_valleyDepth` was still ≥9000 at the moment of the next compression start. | `depth.cpp:632` (CSV log), `depth.cpp:715-716` (`goodRecoil` grading) | Yes — both consumers guard with the same `<9000.0f`/`<RECOIL_RESIDUAL_MAX_MM` pattern, so a sentinel value correctly reads as "no valid recoil data," never as a spuriously good or bad recoil. |
| `_valleyDepth` sentinel **inconsistency** — declared/reset to `0.0f` in `depthSessionReset()` (`depth.cpp:88,289`), but set to `9999.0f` at every subsequent RELEASED→COMPRESSING transition (`depth.cpp:520`) | Two different "no valley yet" representations for the same variable depending on *when* you ask. | `depthFinalizeLastValley()`: `if (_valleyDepth >= 9000.0f) return;` (`depth.cpp:355`) | **Only accidentally safe.** If a session ends with zero completed compressions, `_valleyDepth` is still its session-reset value of `0.0f`, which does *not* satisfy `>= 9000.0f` — the sentinel check would be bypassed. It happens not to matter today only because `depthFinalizeLastValley()` first checks `if (!_trackingValley) return;` (`depth.cpp:354`), and `_trackingValley` is independently `false` until the first compression completes. If that guard is ever removed or reordered, this sentinel mismatch becomes live. |
| `tiltMinDeg = 9999.0f` / `tiltMaxDeg = -9999.0f` (`imu.h:70-71`, reset `imu.cpp:504-505`) | Reset at the start of every stroke (`resetIntegration()`), updated every COMPRESSING sample by `depth.cpp:398-406`. | `imuConfidence()`: `if (s.tiltMaxDeg > -9000.0f && s.tiltMinDeg < 9000.0f) tiltSpan = ...` else `tiltSpan = 0.0f` (`imu.cpp:686-689`) | Paired, but the failure mode is a silent *full-credit* default (`cTilt = 1.0f` when `tiltSpan` stays 0), not an exclusion. In practice unreachable — a stroke needs `RELEASE_CONFIRM_NEEDED` (6) samples of low force after `FORCE_COMPRESS_START`, so at least one COMPRESSING sample always runs and updates the accumulator — but the confidence function has no explicit "never measured" branch distinct from "measured zero tilt change." |

---

## D. Magic numbers in `depth.cpp` / `force.cpp` not defined in `config.h`

**Blocks E and this pass fixed all rows in both tables** — promoted to named
`config.h` constants, listed inline per row below (this promotion isn't
covered by the "Block E fixes" section further down — that entry is about
SESSION_END field renames only, a separate piece of the same block).
`validDepth`'s 20-125mm gate stays deliberately independent of
`IMU_CONF_DEPTH_MIN/MAX_MM`, named but not aligned, per explicit
instruction. Tables kept below, struck through, as historical record of
what each literal was and why.

### depth.cpp — fully resolved

| Value | Location | Purpose |
|---|---|---|
| ~~`250` (ms)~~ | `COMP_MIN_INTERVAL_MS`, `depth.cpp:43` | Minimum time between compression starts (240 BPM physical cap). Now `config.h`, same name. |
| ~~`0.3f` (cm)~~ | `depth.cpp:419` | Live-depth "ease down" hysteresis band. Now `LIVE_DEPTH_EASE_DOWN_CM`. |
| ~~`0.15f` (cm)~~ | `depth.cpp:423` | Live-depth noise floor. Now `LIVE_DEPTH_NOISE_FLOOR_CM`. |
| ~~`0.10f` (cm)~~ | `depth.cpp:434` | Display-depth noise floor. Now `DISPLAY_DEPTH_NOISE_FLOOR_CM`. |
| ~~`20.0f`, `125.0f` (mm)~~ | `depth.cpp:636` | `validDepth` range gate for storage/trend. Now `VALID_DEPTH_MIN_MM`/`VALID_DEPTH_MAX_MM` — named but deliberately **not** aligned with `IMU_CONF_DEPTH_MIN/MAX_MM` (80.0f); the asymmetry was and remains intentional. |
| ~~`40.0f`, `160.0f` (BPM)~~ | `validRate()`, `depth.cpp:219` | Physiological sanity range for any rate value. Now `VALID_RATE_MIN_BPM`/`VALID_RATE_MAX_BPM`. |
| ~~`0.55f`, `1.80f` (ratio)~~ | `depth.cpp:676` | Single-cycle rate-jump plausibility bounds. Now `RATE_JUMP_MIN_RATIO`/`RATE_JUMP_MAX_RATIO`. |
| ~~`5` (compressions)~~ | `depth.cpp:230` | Fatigue baseline lock — now references the existing `FATIGUE_DEPTH_TREND_SAMPLES` directly instead of duplicating its value. |
| ~~`0.6f`, `0.4f`~~ | `depth.cpp:682` | `_rateJumpReference` (renamed from `_instantRate`, see Block E) EMA weights. Now `RATE_JUMP_EMA_OLD_WEIGHT`/`RATE_JUMP_EMA_NEW_WEIGHT`. |

### force.cpp — fully resolved

| Value | Location | Purpose |
|---|---|---|
| ~~`50.0f` (N)~~ | `force.cpp:81` | Boot-baseline sanity ceiling. Now `FORCE_BOOT_BASELINE_CEILING_N`. |
| ~~`700.0f` (N)~~ | `force.cpp:108` | ADC-glitch rejection ceiling. Now references `FORCE_CONF_RANGE_MAX_N` directly instead of duplicating the literal. |
| ~~`0.5f` (factor)~~ | `force.cpp:122` | In-session baseline-adapt eligibility multiplier. Now `FORCE_BASELINE_ADAPT_LEANING_FRAC`. |
| ~~`30.0f`/`600.0f`/`20.0f`/`100.0f`~~ and ~~`100.0f`/`600.0f`/`40.0f`/`80.0f`~~ | `force.cpp:154-158` | `LOW_FORCE_MODE` vs. real-manikin calibration-sample gating ranges. Block E fixed the force bounds (`FORCE_BASELINE_MIN`, `FORCE_CALIB_GATE_MIN_N`/`MAX_N`) but left the depth bounds raw — out of that block's stated scope. Fixed this pass: `depthMin`/`depthMax` are now `FORCE_CALIB_GATE_LOWFORCE_DEPTH_MIN_MM`/`MAX_MM` (20/100) and `FORCE_CALIB_GATE_DEPTH_MIN_MM`/`MAX_MM` (40/80). |
| ~~`5` (samples) ×2~~ | `force.cpp:194,224` | Minimum sample counts for fitting and for outlier-filtered refit. Now two distinct constants, `FORCE_CALIB_MIN_SAMPLES_TO_FIT`/`FORCE_CALIB_MIN_INLIERS_TO_REFIT` (kept separate since they're different gates that happened to share a value). |
| ~~`2.0f` (factor)~~ | `force.cpp:221` | Outlier-rejection residual multiplier. Now `FORCE_CALIB_OUTLIER_RESIDUAL_MULT`. |
| ~~`0.70f`, `3.50f`~~ | `force.cpp:233` | k acceptance range. Now `FORCE_CALIB_K_MIN`/`FORCE_CALIB_K_MAX`. |
| ~~`0.15f`~~ | `force.cpp:205` | Fallback k when `computeK()`'s denominator is ≤0. Now `FORCE_CALIB_K_FALLBACK`. |
| ~~`30.0f` (N)~~ | `forceConfidence()`, `force.cpp:314` | `rangeMargin` for the linear confidence taper. Now `FORCE_CONF_RANGE_MARGIN_N`. |
| ~~`0.25f`, `0.85f`, `0.50f`, `0.70f`~~ | `force.cpp:336-337` | Baseline-drift confidence-penalty thresholds/factors. Now `FORCE_CONF_DRIFT_MODERATE_THRESHOLD`/`_PENALTY`, `FORCE_CONF_DRIFT_HEAVY_THRESHOLD`/`_PENALTY`. |

---

## Summary of defects requiring attention

**All 5 items below are now resolved** — kept as historical record of what
the original audit found; each line names where the fix landed.

1. ~~**`shared_state.h:44`**~~ — `frequency`'s comment ("instantaneous (last 2 compressions)") contradicted its actual derivation, a 5-compression rolling average (`depth.cpp:53,756`). **Fixed** — see "Fixes applied" item 3 below (pre-dates this session's Blocks C/D/E).
2. ~~**BLE byte 91 / `feedbackEnabled`**~~ — firmware packed a 3-bit per-channel mask; the app parsed it as `== 1`, false whenever more than just audio feedback was enabled. **Fixed** — `ble_data_processor.dart:202-204` now decodes the mask bit-by-bit (`feedbackMask & 0x01/0x02/0x04`), matching `ble_manager.cpp:168-170`.
3. ~~**Diagnostic overlay bytes 70-71 / `diagRescuerPpgFiltered`**~~ — app expected rescuer-channel filtered PPG data here; firmware's diag block never wrote these bytes, and `max30102DiagRescuerFiltered/Dc` were never called. **Fixed in Block D** — both functions are now wired into `bleBuildDiagFrame()` (`ble_manager.cpp:430,433`); see the DIAG_FRAME section below for the full byte layout.
4. ~~**`cpr_glove.ino:1590`**~~ — `#if MANIKIN_CALIBRATION_LOG` referenced a macro that doesn't exist (renamed to `DEPTH_PIPELINE_LOG`). **Fixed** — see "Fixes applied" item 4 below (pre-dates this session's Blocks C/D/E).
5. ~~**`StoredCompression::residualDepthX10`**~~ — declared with a literature-referenced comment describing intended behavior, never implemented. **Resolved by removal, not implementation** — the field (and the adjacent unused `reserved[3]`) is no longer in `StoredCompression` (`depth.h:8-17`); it was deleted as dead code in the "remove dead symbols" pass rather than wired up. If this metric still matters for the thesis analysis, it needs to be re-added and implemented from scratch, not recovered.

Everything in CLAUDE.md's "Do not touch" list (grading formula, depth selector,
force model, palm-only posture, pulse-check gating) was read for this audit
but not modified, and no defects are reported against that logic itself —
only against comments/wiring adjacent to it (e.g. `frequency`'s stale doc
comment, which is metadata, not the selector/grading code).

---

## Follow-up (source re-verified against depth.cpp and ble_manager.cpp)

### 1. `s.valleyDepth` derivation (depth.cpp:767-776)

**Already in the table, correctly.** Re-read against current line numbers:

```
767  // Use force-to-depth proxy for the inter-compression valley.
768  // This gives the app a non-zero value when the rescuer is leaning,
769  // making the valley/recoil graph meaningful.
770  // forceToDepth returns mm, divide by 10 for cm.
771  {
772    const float valF = (_recoilValleyForceN < 9000.0f) ? _recoilValleyForceN : 0.0f;
773    s.valleyDepth = (valF > 0.5f)
774        ? forceCalibK() * powf(valF, DEPTH_EXPONENT) / 10.0f  // mm → cm
775        : 0.0f;
776  }
```

My original table recorded exactly this: unit **cm**, derivation "the residual
inter-compression *force* (`_recoilValleyForceN`), run back through the
force→depth power law, mm→cm," explicitly flagged as *not* the IMU valley
minimum, with a note that `recoilAchieved` grading instead uses
`_recoilValleyDepthMM` (IMU-derived), which is never itself transmitted. No
correction needed here — confirmed accurate.

### 2. `_prevValleyDepth` — missed, adding to Section A now

Checked: it is written at exactly the three sites you named and **read
nowhere**.

```
depth.cpp:75:  static float _prevValleyDepth = 0.0f;   // valley from previous cycle, used for recoil check
depth.cpp:279: _prevValleyDepth = 0.0f;                // depthSessionReset()
depth.cpp:360: _prevValleyDepth = _valleyDepth;         // depthFinalizeLastValley()
depth.cpp:516: _prevValleyDepth = (_trackingValley && _valleyDepth < 9000.0f) ? _valleyDepth : 9999.0f;  // RELEASED→COMPRESSING transition
```

Grepped the full firmware tree for `_prevValleyDepth` — those four lines
(one declaration, three writes) are the *only* occurrences. There is no
read. This is a plain miss in my original report: it satisfies the DEAD
definition ("written but never read") as literally as `StoredCompression::reserved[3]`
does, and I should have caught it since I was already tracing every write
site of its sibling variable `_prevValleyForce`. Its own declaration comment
("used for recoil check") is itself wrong — `_recoilValleyDepthMM` is the
variable actually consumed by the recoil check (`depth.cpp:715-716`), not
this one.

**Added to Section A:**

| Symbol | Declared | Defined | Notes |
|---|---|---|---|
| `_prevValleyDepth` | `depth.cpp:75` | written `depth.cpp:279,360,516` | Declared "used for recoil check," but `recoilAchieved`/`goodRecoil` grading (`depth.cpp:715-716`) reads `_recoilValleyDepthMM`, not this variable. No read site exists anywhere in the tree. Fully dead — three separate writers, zero readers. |

### 3. depth.cpp:359 vs depth.cpp:515 — a second, distinct sentinel inconsistency

Checked both sites directly:

```
515 (RELEASED→COMPRESSING transition, depthUpdate):
      _recoilValleyForceN = (_prevValleyForce < 9000.0f) ? _prevValleyForce : 9999.0f;

359 (depthFinalizeLastValley):
  _recoilValleyForceN  = _prevValleyForce;
```

This is **not** the same inconsistency as the one already in Section C
(which was about `_valleyDepth` defaulting to `0.0f` in `depthSessionReset()`
vs. `9999.0f` at the transition site). This is a separate asymmetry: two
call sites assign `_recoilValleyForceN` from `_prevValleyForce`, and only one
of them guards against the sentinel. I did not catch this one originally —
I traced the `_recoilValleyDepthMM`/`_valleyDepth` sentinel chain for Section
C but didn't separately check whether `_recoilValleyForceN`'s two assignment
sites used the same guard.

Is it live? `depthFinalizeLastValley()` already returns early at line 355 if
`_valleyDepth >= 9000.0f`, which only happens once `_trackingValley` has been
true for at least one `depthUpdate()` tick. `_prevValleyForce` is updated in
the same `if (_trackingValley) {...}` block (`depth.cpp:449-454`) that
updates `_valleyDepth`, on every tick, from a real `forceN` sample (always
≪9000). So in the current code, by the time line 355's guard has already
passed, `_prevValleyForce` has almost certainly also been pulled below 9000
in that same tick — the missing guard at line 359 is safe *incidentally*,
because it happens to piggyback on line 355's check of a different variable,
not because it defends itself. If `_valleyDepth` and `_prevValleyForce`
updates were ever decoupled (e.g., force reads gated independently of depth
tracking), line 359 would transmit the raw `9999.0f` sentinel as a real N
value with no guard to catch it. Recorded as a new, separate row in Section C
below.

**Added to Section C:**

| Sentinel | Where set | Where checked | Can the check actually see it? |
|---|---|---|---|
| `_recoilValleyForceN = _prevValleyForce` guarded at one call site, not the other | `depth.cpp:515` guards with `(_prevValleyForce < 9000.0f) ? _prevValleyForce : 9999.0f`; `depth.cpp:359` (`depthFinalizeLastValley`) assigns unguarded: `_recoilValleyForceN = _prevValleyForce;` | Consumed by `goodRecoil` grading (`depth.cpp:715-716`, only reachable via the 515 path) and by `depthFinalizeLastValley`'s own internal state (359 path, see Q4 — never graded again regardless). | Currently safe only by coincidence: `_prevValleyForce` and `_valleyDepth` are updated together every tick inside the same `if (_trackingValley)` block, so `depthFinalizeLastValley`'s own line-355 guard on `_valleyDepth` incidentally also guarantees `_prevValleyForce` is real by the time line 359 runs. Not independently defended — a latent trap if the two updates are ever decoupled. |

### 4. `depthFinalizeLastValley()` — yes, `correctRecoil` drops one real observation per session

Traced the full attribution chain. The state machine attributes recoil
quality *forward*: the valley/pause measured between compression N−1's
release and compression N's downstroke is captured at N's own
RELEASED→COMPRESSING transition (`depth.cpp:511-513`, comment: "belongs to
the compression that is ABOUT to complete") and held in
`_recoilValleyDepthMM`/`_recoilValleyForceN` until N's own RELEASE_CONFIRM
fires the grading block (`depth.cpp:715-716`), which increments `_cntRecoil`
→ `s.correctRecoil` right then.

For a session with compressions 1..M, that means:
- Compressions 2..M each get graded on a real inter-compression pause (the
  one immediately preceding them). That's correct.
- **Correction to my prior turn:** I previously claimed `depthSessionReset()`
  not clearing `_recoilValleyDepthMM`/`_recoilValleyForceN` lets compression 1
  of session 2+ leak the previous session's trailing values into its grade.
  That claim is wrong and is retracted. `depth.cpp:514-515` runs at the
  RELEASED→COMPRESSING transition of *every* compression, including the
  first, and both assignments are gated on state that `depthSessionReset()`
  *does* reset: line 514's ternary is gated on `_trackingValley` (reset to
  `false`), and line 515's ternary is gated on `_prevValleyForce < 9000.0f`
  (reset to `9999.0f`, which fails that guard). So at compression 1's own
  transition, `_recoilValleyDepthMM` and `_recoilValleyForceN` are
  unconditionally overwritten with the `9999.0f` sentinel *before* grading
  ever reads them (`depth.cpp:715-716`) — whatever a previous session left
  in those variables is clobbered first, never read. There is no
  cross-session leak.
- The real, structural effect: because no preceding pause exists before a
  session's first compression, `_recoilValleyDepthMM`/`_recoilValleyForceN`
  are fixed at the sentinel for compression 1 every single session, and the
  sentinel never satisfies `_recoilValleyForceN < FORCE_LEANING_THRESHOLD &&
  _recoilValleyDepthMM < RECOIL_RESIDUAL_MAX_MM` (`depth.cpp:715-716`) no
  matter how the rescuer performs. Compression 1 is therefore *always*
  graded `goodRecoil = false`, purely structurally — `correctRecoil <=
  totalCompressions - 1` holds for every session, not just an occasional one.
- The pause *after* compression M (before the session ends) is a genuine
  recoil observation with no compression M+1 to attribute it to within this
  session. `depthFinalizeLastValley()` exists to capture it — but by the time
  `cpr_glove.ino` calls it (`stopSession()`, before `snapshotState()`),
  compression M's own grading block has *already run and already returned*
  (M completed and incremented counters back when its own RELEASE_CONFIRM
  fired, which is necessarily before `SESSION_END`/`stopSession()` can be
  reached). The function's own comment concedes exactly this
  (`depth.cpp:363-368`): "the recoil grade for the last compression is
  computed by depthUpdate's grading block, which has already run... To make
  the grade visible we'd need to re-emit a per-compression event... the
  per-compression event bit is a future improvement." The values it writes
  (`_recoilValleyDepthMM`, `_recoilValleyForceN`, `_prevValleyDepth`) have no
  reader afterward — grading won't run again this session, `_prevValleyDepth`
  is dead regardless (Q2), and `_recoilValleyDepthMM`/`_recoilValleyForceN`
  are simply overwritten again at the next session's first compression
  (`depth.cpp:514-515`) with no reader in between.

**So: yes, structurally, for two independent reasons — not the cross-session
leak I originally proposed.** Over a full session, M compressions occur and
exactly M recoil gradings happen (1 per compression, so `correctRecoil ≤
totalCompressions` stays arithmetically sane) — but compression 1's grading
is structurally forced to `false` (no preceding pause exists to measure, full
stop), and the one real recoil observation that has no compression to
attribute a grade against (the trailing pause after the session's actual
last compression) is computed by `depthFinalizeLastValley()` and then
discarded. Net effect: `correctRecoil` reflects at least one fewer genuine
recoil observation than the rescuer actually produced in the session, and
the function named specifically to fix the trailing case ("finalize last
valley") does not — by its own author's admission in the adjacent comment —
currently make it into any transmitted counter.

**Added to the summary-of-defects list**, since this affects a number that
reaches the thesis dataset (`correctRecoil` in SESSION_END), not just
internal telemetry.

### 5. ble_manager.cpp bytes 52-55, 86, 102-107 — normal (non-diag) mode, confirmed from source

Re-read `bleSendLiveStream()` end to end. In normal mode (`diagActive ==
false`), before the `if (diagActive)` overlay block runs at all, these bytes
are written exactly once, unconditionally:

```
ble_manager.cpp:134   packF32(buf, 52, s.valleyDepth);       // bytes 52-55, float32, cm
ble_manager.cpp:161   buf[86] = s.inVentilationWindow ? 1 : 0;  // byte 86, bool
ble_manager.cpp:162   // byte 87 reserved = 0x00               // byte 87, always 0 (buf is zero-inited)
ble_manager.cpp:176   packF32(buf, 102, s.lastPeakDepthCm);   // bytes 102-105, float32, cm
ble_manager.cpp:182   buf[106] = s.lastPeakConfidence;        // byte 106, uint8, 0-100
ble_manager.cpp:183   buf[107] = s.lastPeakDepthSource;       // byte 107, uint8, enum 0-7
```

The `if (diagActive)` block (`ble_manager.cpp:186-210`) only executes when
`diagActive == true`, and *only then* does it overwrite 52-53/54/55, 86, 87,
and 102-103/104-105/106/107 with diagnostic data. In normal mode all six
fields above stand as written.

`ble_data_processor.dart`'s parser, confirmed line-by-line:

```
dart:169  final valleyDepth = diagActive ? 0.0 : b.getFloat32(52, Endian.little);
dart:208  final inVentilationWindow  = !diagActive && b.getUint8(86) == 1;
dart:221  final lastPeakDepthCm = diagActive ? 0.0 : b.getFloat32(102, Endian.little);
dart:225  final lastPeakConfidence  = diagActive ? 0 : b.getUint8(106);
dart:226  final lastPeakDepthSource = diagActive ? 0 : b.getUint8(107);
```

Byte 87 has no normal-mode field on the app side (nothing to read — it's
genuinely reserved/0 in normal mode); the app only ever reads it as
`diagActionResult` (`dart:181`), gated by the caller already knowing
`diagActive`. This matches firmware exactly.

**Confirmed correct — no defect in this byte range in normal mode.** One
documentation-only nit while re-checking: `ble_data_processor.dart:170`
comments "bytes 53-55 reserved" directly under the `valleyDepth` line, but
bytes 53-55 are three of the four bytes *of* the `valleyDepth` float32
(52-55), not reserved — the comment is stale/wrong, though the code on the
next line reads all 4 bytes correctly via `getFloat32(52, ...)` so there is
no functional bug, only a misleading comment in the app file.

### Summary of what changed

- **Missed and now added to Section A:** `_prevValleyDepth` (dead — written
  3 places, read nowhere).
- **Missed and now added to Section C:** the `_recoilValleyForceN` guard
  asymmetry between `depth.cpp:359` and `depth.cpp:515`.
- **Missed and now added to the defects summary:** `depthFinalizeLastValley()`
  does not make the last compression's trailing recoil observation count
  toward `correctRecoil` — confirmed via full state-machine trace, not just
  the function's own comment.
- **Checked and already correct:** item 1 (`valleyDepth` derivation) and
  item 5 (bytes 52-55/86/102-107 in normal mode) were both already recorded
  accurately in the original table.

---

## Fixes applied

Firmware and app code edited per explicit instruction (this document itself
is left as the historical record of what was found — references to the old
`valleyDepth` name above describe the pre-fix code and are not retroactively
renamed).

1. **`_prevValleyDepth` deleted** — declaration (`depth.cpp:75` at time of
   audit) and all three writes (`depthSessionReset()`, `depthFinalizeLastValley()`,
   the RELEASED→COMPRESSING transition). No read site existed anywhere.
2. **`depth.cpp:359` sentinel guard added** — `_recoilValleyForceN` inside
   `depthFinalizeLastValley()` now uses the same `(_prevValleyForce < 9000.0f)
   ? _prevValleyForce : 9999.0f` guard its twin at the RELEASED→COMPRESSING
   transition already had, instead of an unguarded direct assignment.
3. **`shared_state.h` `frequency` comment fixed** — was "instantaneous (last 2
   compressions)", now "5-compression rolling average," matching `depth.cpp`'s
   actual `rollingRate()` implementation and the app's own (correct) comment.
4. **`cpr_glove.ino:1590` macro fixed** — `#if MANIKIN_CALIBRATION_LOG` (a macro
   that no longer exists) changed to `#if DEPTH_PIPELINE_LOG`, so the CSV
   header print now actually fires when that flag is enabled.
5. **`ble_data_processor.dart:170` comment fixed** — "bytes 53-55 reserved"
   corrected to state they're 3 of the 4 bytes of the adjacent float32, not
   reserved.
6. **`valleyDepth` renamed to `residualLoadDepthCm`** everywhere — firmware
   (`shared_state.h`, `depth.cpp`, `ble_manager.cpp`, `cpr_glove.ino`) and app
   (`ble_data_processor.dart`, `ble_connection.dart`, `compression_event.dart`,
   `cpr_chart_helpers.dart`, `dev_preview_screen.dart`, `depth_bar.dart`,
   `live_cpr_widgets.dart`, `live_cpr_screen.dart`, `export_service.dart`).
   The backend/storage JSON key `'valley_depth'` in `compression_event.dart`
   was deliberately left unchanged (it's a persisted wire/column contract per
   that file's own comment — "Keys must match the column aliases in
   session.js compressions INSERT" — not a Dart identifier the rename
   instruction covered). Stale doc-comments directly on the renamed field
   (e.g. `compression_event.dart`'s "Minimum depth reached after this
   compression's peak" and `ble_data_processor.dart`'s "minimum depth after
   last peak") were corrected in the same edit, since leaving them would have
   recreated the exact name/comment mismatch this rename was fixing.
7. **Eight dead symbols deleted**: `getAdaptiveDepthMM()`,
   `imuGetWorldVertAccelPalm()`/`imuGetWorldVertAccelWrist()`,
   `imuTriggerFastConverge()`, `forceCalibLocked()`, `forceCalibLock()`,
   `forceResetCalibration()`, `batteryVoltage()`, `depthGetRate()`,
   `PULSE_CHECK_INTERVAL_MS`, and the three legacy `PULSE_CHECK_*` aliases.
   Comments elsewhere that named these symbols (`imu.h`'s note on
   `imuCombineDual` replacing "the old diff-based weighting in
   getAdaptiveDepthMM", `depth.cpp`'s `imuResetCF(); // was:
   imuTriggerFastConverge()`) were updated so nothing points at a deleted
   symbol.

### Correction to the Follow-up section above

Per explicit correction: the Q4 write-up's claim that `depthSessionReset()`
not clearing `_recoilValleyDepthMM`/`_recoilValleyForceN` lets a session's
first compression leak the previous session's trailing values was wrong and
has been retracted in place (see "Correction to my prior turn" inline above).
`depth.cpp:514-515` (current-file line numbers shifted since some of today's
deletions landed above this point) unconditionally overwrites both variables
at every RELEASED→COMPRESSING transition, gated on state
`depthSessionReset()` *does* reset (`_trackingValley`, `_prevValleyForce`),
so there is no cross-session leak. The real, corrected effect: compression 1
of every session is structurally always graded `goodRecoil = false` (no
preceding pause exists to measure), so `correctRecoil <= totalCompressions -
1` holds for every session — not a cross-session artifact of some sessions
only. `depthSessionReset()` itself was not modified, per instruction.

### Newly discovered while making these edits (not fixed — out of scope for this pass)

- **Wrist-dropout detection was already non-functional before this pass, not
  because of it.** The only code that ever incremented `_wristDropoutCount`
  or set `_wristDropped = true` lived inside `getAdaptiveDepthMM()` — which,
  per Section A, had zero callers anywhere in the firmware even before its
  deletion. So `imuWristDropped()` was already unconditionally `false` in the
  shipped firmware; deleting the dead function did not change any runtime
  behavior, it just removed an already-unreachable side effect along with
  the unreachable function. Flagging this because it's a real gap (a
  permanently-stuck bad wrist IMU is never excluded by `imuCombineDual()`'s
  dropout path) that this pass did not introduce and was not asked to fix.
- **`live_cpr_screen.dart:634`** reads `data['valleyDepth']` from the
  `Map<String, dynamic>` broadcast on `BLEConnection.dataStream` — but that
  map's builder (`ble_connection.dart:622-687`) never includes a
  `'valleyDepth'` (or now `'residualLoadDepthCm'`) key at all. This lookup
  has always returned `null` → defaulted to `0.0`, independent of today's
  rename. Left the string literal as `'valleyDepth'` since it's an
  already-broken key into a map that never carried it, not "the matching app
  field" the rename instruction meant — renaming it wouldn't fix the
  underlying gap (the key still wouldn't exist in the map) and touching it
  wasn't requested. Not fixed.
- **`AnimatedDepthBar.residualLoadDepthCm`** (`depth_bar.dart`, formerly
  `valleyDepth`) is accepted as a constructor parameter but never read inside
  the widget's `build()` — it doesn't reach `_DepthBarPainter` or affect
  anything drawn. Pre-existing, unrelated to the rename. Not fixed.

---

## Round 2 corrections and remaining items (three deviations flagged, plus item 8)

1. **Item 4 was done wrong the first time.** Instructed to delete the whole
   `#if MANIKIN_CALIBRATION_LOG ... #endif` block in `cpr_glove.ino`;
   instead it was repointed to `#if DEPTH_PIPELINE_LOG`. Corrected: the block
   (the `#if`, the `Serial.println`, and the `#endif`) is now deleted
   entirely, no macro repoint.
2. **Item 7 (`StoredCompression::residualDepthX10`) was skipped, now done.**
   Verified first, per instruction: `STORAGE_COMPRESSION_SIZE` (`config.h:559`)
   is an independent `#define ... 20`, never derived from
   `sizeof(StoredCompression)`. `storage.cpp`'s writer (`storage.cpp:245-257`)
   manually packs 17 named bytes per compression and advances by that macro;
   it never reads `residualDepthX10`. No deserializer anywhere reconstructs a
   `StoredCompression` from disk — the only disk-reading function,
   `storageReadChunk()`, streams raw bytes for BLE transfer. Deleting the
   field changes zero bytes of the on-disk format; existing stored sessions
   are unaffected. Deleted the field and its comment from `depth.h`.
   `reserved[3]` was left unchanged (not asked to resize it).
3. **Item 8 (BLE byte 91) was skipped, now done.** Firmware
   (`ble_manager.cpp:168-170`) was already correct — packs a 3-bit mask,
   `(audio?1:0)|(haptic?2:0)|(visual?4:0)`. The app's
   `feedbackEnabled = b.getUint8(91) == 1` was the bug. Replaced with
   `audioFeedbackEnabled`/`hapticFeedbackEnabled`/`visualFeedbackEnabled`,
   each reading its own bit. Checked every consumer first: the old
   `feedbackEnabled` field had none beyond its own plumbing (declared in
   `ble_data_processor.dart`, put into the broadcast map in
   `ble_connection.dart:671`) — nothing in `lib/features/` ever read it back
   out. All 6 call sites across those two files updated; no UI/session code
   needed touching because none existed.

### Wrist-dropout investigation (report only, no code changed)

- `getAdaptiveDepthMM()` (pre-deletion, from `git show HEAD:CPR-Assist-Firmware/imu.cpp`):
  incremented `_wristDropoutCount` only when `wristMM <= 0.0f` **and** the
  wrist's gravity estimate had already converged (`gravWrist.cycles >=
  GRAV_MIN_CYCLES_WRIST`, 6) — so early-session warm-up zeros didn't count.
  Any single stroke with `wristMM > 0` reset the counter to 0 (not
  cumulative across separate episodes — must be consecutive). Three
  consecutive post-convergence zero-strokes (`WRIST_DROPOUT_LIMIT`, 3) set
  `_wristDropped = true`. Nothing anywhere ever reset `_wristDropped` back
  to `false` afterward — a one-way latch for the rest of the power cycle.
- **Where it would belong now:** `imuCombineDual()`'s existing
  `if (!_wristOk || _wristDropped || wristMM <= 0.0f)` branch
  (`imu.cpp:519`) is structurally the same bailout condition the old
  function used — it's the natural, minimal-diff home for the counter.
  It would need `gravWrist.cycles` (already a global in `imu.cpp`, no new
  parameter required) to reproduce the "only count post-convergence" guard.
  This branch sits directly inside the confidence-weighted dual-IMU combine
  that CLAUDE.md's "Do not touch" list covers ("The confidence-based depth
  selector in depth.cpp... population defaults are intentional") — `imuCombineDual()`
  is the selector's supporting machinery, so implementing this needs your
  explicit sign-off, not just a green light on the concept.
- **What `imuCombineDual()` does today with a zero/garbage wrist reading,
  given `imuWristDropped()` is always `false`:**
  - `wristMM <= 0.0f` (true zero/negative, e.g. divergence-clamped) is
    already caught per-stroke by the same `imu.cpp:519` branch regardless of
    `_wristDropped` — this specific case was never actually depending on the
    dropout latch to be safe.
  - A **positive but implausible** reading (in-range-looking noise, a
    consistent bias from a loose mount, or a value outside [5, 80] mm) is
    handled per-stroke by the plausibility gate and `imuConfidence()` alone —
    there is no persistent memory of "this sensor has been wrong for the
    last N strokes." A wrist IMU that produces confident-looking garbage
    every stroke is never excluded; each stroke is judged in isolation.
  - The bigger unaddressed consequence: `imuAccumulate()`/`imuEndCycle()`
    gate gravity-EMA updates on `!_wristDropped` (`imu.cpp:345,351`, current
    line numbers). With the latch permanently `false`, a persistently bad
    wrist IMU keeps feeding its own (bad) readings into `gravWrist`'s EMA
    forever — compounding rather than isolating the fault — instead of being
    cut off from recalibrating itself once flagged.
- **App consumption of `wristDropped` (byte 51):** grepped `lib/features/`
  — zero matches. `ble_data_processor.dart` parses it and
  `ble_connection.dart:648` puts it into the broadcast map, but nothing in
  any screen, widget, or session-recording path reads it back out. Same
  "plumbed but never consumed" shape as the old `feedbackEnabled` bool.

---

## Block C fixes — wrist dropout + pulse-check provenance

Firmware and app code edited per explicit instruction (`FIRMWARE_PLAN.md`
Block C, both items explicitly authorised — normally-protected code). As
with "Fixes applied" above, prior sections describing pre-fix code are left
as historical record and not retroactively edited in place.

1. **Wrist dropout detection restored.** The counter/latch logic described
   in "Wrist-dropout investigation" above (previously only inside the
   deleted `getAdaptiveDepthMM()`) is now live inside `imuCombineDual()`
   (`imu.cpp`), gated the same way: `wristMM <= 0.0f` only counts once
   `gravWrist.cycles >= GRAV_MIN_CYCLES_WRIST`, any good stroke resets the
   counter, `WRIST_DROPOUT_LIMIT` consecutive bad strokes sets
   `_wristDropped = true`. LIVE_STREAM byte 51 (`wristDropped`, table row
   above) now reflects a live detector instead of a permanently-`false`
   value — the row's derivation text is otherwise still accurate; only its
   line citation (`imu.cpp:617-626`, the old dead function) is now stale,
   since the logic lives in `imuCombineDual()` instead. Confidence
   weighting and fusion math were not touched.
2. **Latch is session-scoped, not power-cycle-scoped.** Decision made
   explicitly, not inferred: `_wristDropped` and its counter are cleared by
   a new `imuResetWristDropout()`, called from `depthSessionReset()`.
   Rationale given: a study participant must not inherit the previous
   participant's latch.
3. **New sticky per-session record — `SESSION_END` byte 95,
   `wristDroppedDuringSession`.** Because the live latch now clears every
   session, a separate flag (`_wristDroppedDuringSession` in `imu.cpp`,
   cleared only by the same `imuResetWristDropout()`) records whether the
   dropout fired at any point during the session, so the transmitted
   session record still states whether the wrist was trusted even after
   the live flag has cleared for the next session. Byte 95 was previously
   reserved/always-0 — confirmed unused against both `ble_manager.cpp` and
   `ble_data_processor.dart` before use.
4. **New `PULSE_CHECK_RESULT` byte 9 — `pulseCheckRefSource`.** The
   self-detection guard's reference source (`refSource` in
   `cpr_glove.ino`, previously a `Serial.printf`-only string under
   `BLE_DEBUG_SERIAL`, which is 0 in study builds — i.e. previously
   discarded exactly when the thesis needed it) is now also encoded
   numerically as `refSourceCode` (`PULSE_REF_SOURCE_NONE/LIVE/PAUSED` =
   0/1/2, `config.h`) and transmitted. Byte 9 was free — confirmed unused
   against `ble_data_processor.dart`'s existing parser before use.
   Data-capture only: does not change the passive contact-plus-pause
   pulse-check gating policy.

New/updated rows:

| Firmware variable | Unit | Derivation | BLE byte(s) | App field |
|---|---|---|---|---|
| `s.wristDroppedDuringSession` | bool (u8) | `_wristDroppedDuringSession` — latches true the same moment `_wristDropped` does inside `imuCombineDual()`; cleared only by `imuResetWristDropout()` at `depthSessionReset()` (`imu.cpp`). | SESSION_END 95 u8 | `wristDroppedDuringSession` |
| `refSourceCode` | enum 0-2 | Self-detection guard's reference source at pulse-check-window close: 0=NONE (guard ran with no usable reference), 1=LIVE (`snap.heartRateUser`/`rescuerSignalQuality`), 2=PAUSED (`snap.rescuerHRLastPause`/`rescuerSQLastPause`) (`cpr_glove.ino`). | PULSE_CHECK_RESULT 9 u8 | `pulseCheckRefSource` |

---

## Block D fixes — diagnostic frame

Firmware and app code edited per explicit instruction (`FIRMWARE_PLAN.md`
Block D). As with Blocks B/C above, prior sections describing pre-fix code
are left as historical record and not retroactively edited in place, with
one exception: the "Diagnostic-mode overlay" table under §1 LIVE_STREAM was
deleted outright (not just annotated), per explicit instruction, since it
described a byte-aliasing scheme that no longer exists and would actively
mislead a future reader using this document as a live wire reference — unlike
Blocks B/C's fixes, which corrected behavior of fields that still exist at
the same bytes.

**Problem this fixes:** `bleSendLiveStream()`'s diag block overwrote bytes
that carry real fields in normal mode — `residualLoadDepthCm` (52-55),
`inVentilationWindow` (86), `lastPeakDepthCm`/`lastPeakConfidence`/
`lastPeakDepthSource` (102-107) — held together entirely by five matching
`diagActive` guards in `ble_data_processor.dart`. Missing one guard, or
adding a field in that byte range without checking for the overlay, would
have the app silently read diagnostic data (e.g. a raw FSR ADC count) as one
of those normal-mode fields with no error.

**Fix:** diagnostic telemetry moved to its own EVENT_CHANNEL packet type,
`DIAG_FRAME` (`PKT_DIAG_FRAME 0x0D`), queued independently of LIVE_STREAM.
LIVE_STREAM is now single-purpose — the `if (diagActive) { ... }` overlay
block and its "must NOT be overwritten" guard comment are deleted from
`bleSendLiveStream()` (`ble_manager.cpp`), and all five `diagActive` guards
are deleted from `ble_data_processor.dart`'s LIVE_STREAM parser (three of
them — `lastPeakDepthCm`/`lastPeakConfidence`/`lastPeakDepthSource` — become
unconditional reads; `inVentilationWindow` likewise; `residualLoadDepthCm`
likewise).

**`DIAG_FRAME` byte layout** (`bleBuildDiagFrame()`, `ble_manager.cpp`):

| Byte | Field | Type | Source |
|---|---|---|---|
| 0 | packet type | u8 | `PKT_DIAG_FRAME` |
| 1-2 | raw FSR ADC | i16 LE | `analogRead(PIN_FSR_ADC)`, sampled at push time |
| 3 | `diagPalmWhoAmI` | u8 | cached, set on `CMD_DIAG_START` |
| 4 | `diagWristWhoAmI` | u8 | cached, set on `CMD_DIAG_START` |
| 5 | `diagI2cScanResult` | u8 | cached, set on `CMD_DIAG_ACTION`/`DIAG_ACTION_I2C_SCAN` |
| 6 | `diagActionResult` | u8 | cached, set on any diag action |
| 7-8 | palm motion accel ×100 (mg) | i16 LE | `imuGetMotionAccelPalm()`, sampled at push time |
| 9-10 | wrist motion accel ×100 (mg) | i16 LE | `imuGetMotionAccelWrist()`, sampled at push time |
| 11-12 | rescuer PPG filtered (counts) | i16 LE | `max30102DiagRescuerFiltered()` — doc'd ±300, i16 ample |
| 13-16 | rescuer PPG DC (counts) | **u32 LE** | `max30102DiagRescuerDc()` |
| 17-95 | unused | — | zero-filled by `makeItem()` |

The DC field is **u32, not f32**, per explicit correction during review: `dc`
tracks the raw IR ADC count directly (`s.dc = rawIR` EMA, `max30102.cpp:183-188`)
— an integer quantity with no sub-count precision to represent, so f32 would
imply precision the sensor doesn't have. It also can't fit i16/u16: bench
comment elsewhere in this file records good-contact DC around 138,000,
already established as the reason this field was mis-sized in the first
place (see `diagRescuerPpgFiltered` entry in the now-deleted overlay table
above — the app was reading the wrong bytes entirely, so the width question
never previously surfaced).

**Wiring the two previously-dead diag accessors:** `max30102DiagRescuerFiltered()`
and `max30102DiagRescuerDc()` (`max30102.cpp:532-537`) had zero callers before
this fix — see §A. They are now called directly inside `bleBuildDiagFrame()`.
This is also the fix for the app-side defect this document already flagged:
`ble_data_processor.dart`'s old `diagRescuerPpgFiltered` field was reading
bytes 70-71, which the diag overlay never wrote (they carried stale
`patientTemperature` data instead). `DIAG_FRAME` bytes 11-16 now carry the
real values.

**Cadence — 4Hz, approved as proposed:** queued from `cpr_glove.ino`'s main
loop (next to the `LIVE_STREAM_INTERVAL_MS` block) at `DIAG_FRAME_INTERVAL_MS`
(250ms, `config.h`), only while `diagActive`. Chosen over matching
LIVE_STREAM's 10Hz to stay light on `EVENT_CHANNEL`'s single-item queue
(`bleDrainEventQueue()` sends one item per call with a 20ms gap,
`ble_manager.cpp`), since diag mode is bench-only and never concurrent with a
live session needing that bandwidth for session-lifecycle/pulse-check events.

**App-side merge — `ble_connection.dart`, approved as proposed:**
`DIAG_FRAME` arrives on its own cadence via `_handleEventPacket()`, which now
caches its nine fields into instance state (`_diagRawFsrAdc` etc.) and
returns — no separate `dataStream` push. Those cached values are folded into
the single combined map still built on every LIVE_STREAM tick
(`_handleLivePacket()`), so `dataStream`'s shape and 10Hz cadence are
unchanged for consumers. `glove_diagnostic_sheet.dart` needed **zero
changes** — it already reads these exact map keys (`d['diagRawFsrAdc']`
etc.) and has no idea they now arrive via two independently-timed BLE
packets instead of one.

**Dead `diagActive` plumbing deleted, confirmed safe first:** removing the
five guards left `parseLiveStream()`'s `{bool diagActive = false}` parameter
and `ParsedBLEData.diagActive` field with nothing left to gate. Grepped
`lib/` for `.diagActive` and `'diagActive'` before deleting: the only reader
of `ParsedBLEData.diagActive` was `ble_connection.dart:688`
(`'diagActive': parsed.diagActive` in the broadcast map), and the map key
`'diagActive'` itself has zero readers anywhere in `lib/features/` — same
"plumbed but never consumed" shape as `wristDropped`/`feedbackEnabled`
documented earlier in this file. Deleted the parameter and the field.
`ble_connection.dart`'s own `_diagActive` instance bool (tracks
`sendDiagStart()`/`sendDiagStop()` app-side state, unrelated to the deleted
packet-parser field) stays — it still gates when `DIAG_FRAME` is meaningful
to look at, and is now also the source of the `'diagActive'` map key that
survives.

---

## Block E fixes — SESSION_END naming defects (rows above are now stale)

Both naming defects recorded in the LIVE_STREAM/EVENT_CHANNEL tables above (§1
row for `s.patientTemperatureLastPulseCheck`, §2 row for
`s.rescuerTemperatureStart`/`s.rescuerTemperatureEnd`) describe app-side field
names that no longer exist — fixed as part of the Block E naming pass. Per
this doc's own convention, those rows are left as historical record rather
than edited in place; this entry is the correction.

- `patientTemperature` (in `ParsedBLEData._event`) renamed to
  `patientTemperatureLastPulseCheck`, and split from the LIVE_STREAM field of
  the same old name — they were previously the same Dart field serving two
  different firmware concepts (see "Wrist-dropout investigation"-era Block C
  fixes section above for the equivalent pattern). `ble_connection.dart`'s
  SESSION_END map key and the watchdog-synthesised fallback map, and
  `session_detail.dart`'s read, all updated to match.
- App's `rescuerWristTempStart`/`rescuerWristTempEnd` renamed to
  `rescuerTemperatureStart`/`rescuerTemperatureEnd`, matching firmware's own
  name (chosen over the reverse because the app's own live field,
  `rescuerTemperature`, already omits "Wrist" — firmware was the consistent
  side, the app's SESSION_END fields were the outlier). Same three call
  sites updated. `SessionDetail`'s own field names
  (`rescuerWristTempStart`/`rescuerWristTempEnd`) were deliberately left
  unchanged — internal Dart/JSON-column identifiers, not BLE wire names, same
  precedent as the `valley_depth` JSON key note earlier in this document.

No firmware bytes changed for either fix — SESSION_END 66-69 and 82-89 keep
their existing layout; only the app-side names were brought in line with
what the firmware already correctly calls them.
