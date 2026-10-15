# Firmware Work Plan

Everything outstanding on the firmware, in dependency order. Companion to
`docs/TASKS.md` (app-side work) and `CORRECTIONS.md` (hardware gate).

**One session per block. Commit between each.** Do not batch — a previous
attempt to run eight items in one session skipped two of them and reversed an
explicit instruction on a third.

**Every block: report first, edit second.** Read the diff before approving.

Project rules are in `/CLAUDE.md` and load automatically. Don't restate them.

---

## A. Battery

**Done** — `cc53193`.

Isolated, touches nothing else. Do it first.

The current implementation is wrong in two independent ways: the ADC reading
itself, and the voltage-to-percent curve.

```
Rework battery measurement in battery.cpp and config.h. No builds.

1. ADC accuracy — battery.cpp:26 uses adc * (3.3f/4095.0f), which assumes a
   linear ADC with 3.3V full scale. The ESP32 ADC1 is nonlinear and at default
   attenuation full scale is ~2.45V, not 3.3V. The divider puts a full 4.2V
   cell at 2.1V on the pin, exactly where nonlinearity is worst. Replace the
   whole sampling block with analogReadMilliVolts(PIN_BAT_ADC), which uses the
   factory eFuse calibration. Average 4 reads, no delay() —
   analogReadMilliVolts already averages internally. Keep BAT_ADC_DIVIDER.

2. Replace the linear voltage->percent map with a piecewise-linear LiPo curve.
   Put the table in config.h as a named const array, not literals in the .cpp.
   Breakpoints (volts -> percent):
   4.20->100, 4.06->85, 3.98->75, 3.92->65, 3.87->55, 3.82->45,
   3.79->35, 3.75->25, 3.71->15, 3.65->8, 3.45->0
   Interpolate linearly between adjacent points, clamp outside the range.

3. config.h — raise BAT_VOLTAGE_MIN from 3.0f to 3.45f. The PowerBoost 500C
   cuts out around 3.2V, so the bottom of the current scale is unreachable —
   the glove dies while the gauge still claims 15%. Update the comment to
   say why.

4. Add an EMA to the reported percentage, and clamp it monotonically
   non-increasing while not charging, so it never rises during discharge.

5. Charging — when batteryCharging() is true, freeze the last discharge
   percentage rather than reporting the charger-elevated voltage. Report the
   charging state through the existing isCharging flag as now.

6. Update firmware/SIGNALS.md's batteryPercentage row to describe the new
   derivation.

Report the diff. Do not change PIN_BAT_ADC, BAT_ADC_DIVIDER, or anything in
CLAUDE.md's "Do not touch" list.
```

**Verify by hand:** multimeter on the cell, compare reported voltage at full,
mid, and near-empty. If `analogReadMilliVolts` still reads off by a consistent
factor, `BAT_ADC_DIVIDER` needs measuring against the actual resistors rather
than the nominal 2.0.

---

## B. Naming and duplication

**Done** — `bdcbc8d`.

```
Cleanup pass. Report the diff per file. No builds.

1. force.cpp — replace duplicated literals with the macros they shadow:
   700.0f -> FORCE_CONF_RANGE_MAX_N, and the 30/600 in the calibration-gating
   ranges -> FORCE_BASELINE_MIN / FORCE_CONF_RANGE_MAX_N. Leave any literal
   that does NOT exactly match an existing macro as-is, and list those
   separately so I can decide whether to name them.
2. config.h — delete the commented-out FORCE_C0/C1/C2 quadratic coefficients.
3. depth.cpp — add a short block comment above the rate-tracking section
   stating what _gradeRate, _instantRate and rollingRate() each are for, and
   which two reach BLE. This is the confusion that caused the frequency
   comment bug.
4. Rename max30102PatientContact() -> max30102PatientContactProbe() and
   max30102PatientContactOk() -> max30102PatientContactCached(). Update all
   call sites and both header comments. If cpr_glove.ino's explanatory
   paragraph at ~1216-1225 becomes redundant, shorten it.
5. max30205ReadCelsius() — change from a 0.0f sentinel return to
   bool max30205ReadCelsius(float& out), matching gxht30Read()'s pattern.
   Update all call sites.
6. CLAUDE.md — add under "How to work":
   "Any change to a BLE-facing field must update firmware/SIGNALS.md in the
   same commit."

Do NOT touch: validDepth's 20-125mm gate (the divergence from
IMU_CONF_DEPTH_MAX_MM is deliberate and already commented), grading, the depth
selector, the force model, or pulse-check gating policy.
```

---

## C. Wrist dropout + pulse-check provenance

**Done** — `450d11a` + `f273fcb`.

Both touch normally-protected code. Review the diff carefully.

```
Two changes, both in areas normally protected. I am explicitly authorising
these. Report the diff per file, no builds.

1. WRIST DROPOUT — restore the detection that was lost when
   getAdaptiveDepthMM() was deleted. It has never actually worked in shipped
   firmware: imuWristDropped() has always returned false, so BLE byte 51
   always transmits 0 and imuCombineDual()'s dropout path never fires.

   Reinstate the original logic in imuCombineDual(): increment
   _wristDropoutCount when wristMM <= 0.0f AND gravWrist.cycles >=
   GRAV_MIN_CYCLES_WRIST. Any good stroke resets the counter to 0. Reaching
   WRIST_DROPOUT_LIMIT latches _wristDropped = true.

   Two questions before you write it, answer first:
   a. The original latch was one-way for the whole power cycle, never
      cleared. Should it clear on depthSessionReset()? Give the argument each
      way. Do not decide for me.
   b. imuAccumulate()/imuEndCycle() gate gravity-EMA updates on
      !_wristDropped. Once the latch can actually fire, confirm that stops a
      bad wrist from feeding its own readings back into gravWrist, and show
      me those lines.

   Do not change the confidence weighting or the fusion maths itself. Only
   restore the dropout detection and its latch.

2. PULSE-CHECK PROVENANCE — the self-detection guard's reference source
   (live / paused / none) is currently only printed to Serial under
   BLE_DEBUG_SERIAL, which is 0 in study builds, so it is discarded exactly
   when it matters. For a thesis claiming pulse-check reliability, every
   Uncertain is otherwise indistinguishable from every other Uncertain, and
   this cannot be recovered retroactively.

   Add it to the PULSE_CHECK_RESULT event packet as a uint8 enum in a
   currently-unused byte.

   Report first, before editing: which byte offset is free in
   PULSE_CHECK_RESULT, and what the enum values should be. Wait for my
   go-ahead, then implement firmware side, app parse side in
   ble_data_processor.dart, and the SIGNALS.md row.

   Data capture only. Do NOT change pulse-check gating policy — passive
   contact-plus-pause, no rescuer prompt to pause. That stays exactly as is.
```

**Decision needed on C1a.** Clearing the latch per session means a genuinely
dead sensor gets three more strokes of bad data every session. Not clearing it
means one noisy patch disables the wrist IMU until reboot. Leaning toward
clearing on session reset — a study participant shouldn't inherit the previous
participant's dropout — but that's a hardware judgement call.

---

## D. Diagnostic frame

**Done** — `f273fcb`.

The last real structural change in the firmware.

Bytes 52–55, 86–87, 102–107 are aliased between live data and diagnostics. It
works only because the app guards `diagActive` at five separate parse sites.
Miss one guard, or add one field in that range, and the app reads an FSR ADC
value as a float with no error.

```
Restructure diagnostic mode onto its own EVENT_CHANNEL packet. Report the
plan before editing anything. No builds.

PROBLEM: ble_manager.cpp:185's comment says the diag block "overwrites
reserved bytes." They are not reserved — they carry residualLoadDepthCm
(52-55), inVentilationWindow (86), lastPeakDepthCm (102-105),
lastPeakConfidence (106) and lastPeakDepthSource (107). The aliasing is held
together entirely by diagActive guards in ble_data_processor.dart.

PLAN:
1. Add packet type 0x0D DIAG_FRAME to EVENT_CHANNEL. Report the proposed byte
   layout before implementing it.
2. Move every field currently in the diag overlay into it: raw FSR ADC,
   diagPalmWhoAmI, diagWristWhoAmI, diagI2cScanMask, diagActionResult,
   diagPalmAccelMag, diagWristAccelMag.
3. Wire max30102DiagRescuerFiltered() and max30102DiagRescuerDc() into the new
   packet. These are currently dead, and they are why the app's
   diagRescuerPpgFiltered field reads patient temperature instead of rescuer
   PPG — bytes 70-71 are never written by the diag block.
4. Delete the entire diag overlay block from bleSendLiveStream(). LIVE_STREAM
   becomes single-purpose.
5. Remove all five diagActive guards from ble_data_processor.dart's
   LIVE_STREAM parser, and add a DIAG_FRAME parser.
6. Update glove_diagnostic_sheet.dart to consume the new packet.
7. Update firmware/SIGNALS.md — delete the diagnostic-overlay table, add a
   DIAG_FRAME section.

Test path afterwards: open the diagnostic sheet DURING an active session and
confirm live depth and recoil values stay correct. That is the exact case the
old aliasing corrupted.
```

---

## E. Remaining names, numbers, and dead fields

**Done** — `9c4f381`.

Block B only covered literals duplicating an existing macro. These are the
rest.

```
Report first, then apply. No builds.

MAGIC NUMBERS — promote to named constants in config.h. For each, propose a
name and show me the list BEFORE editing.

depth.cpp: 0.3f (live-depth hysteresis, :419), 0.15f (live-depth noise floor,
:423), 0.10f (display noise floor, :434), 20.0f/125.0f (validDepth gate,
:636), 40.0f/160.0f (validRate physiological range, :219), 0.55f/1.80f
(rate-jump plausibility, :676), 5 (fatigue baseline lock, :230 — duplicates
FATIGUE_DEPTH_TREND_SAMPLES, reference it instead), 0.6f/0.4f (_instantRate
EMA weights, :682), 250 (COMP_MIN_INTERVAL_MS, :43).

force.cpp: 50.0f (boot-baseline ceiling, :81), 0.5f (baseline-adapt
multiplier, :122), 5 x2 (min fit samples, :194 and :224), 2.0f (outlier
residual multiplier, :221), 0.70f/3.50f (k acceptance range, :233), 0.15f
(fallback k, :205), 30.0f (rangeMargin, :314), 0.25f/0.85f/0.50f/0.70f
(baseline-drift penalties, :336-337), and the 20/100/40/80 calibration gating
values that do not match an existing macro.

NAME MISMATCHES:
- imuResetCF() only ARMS a deferred reset (_pendingCFReset), fired later on
  300ms of stillness. Rename to imuArmCFReset(), or document it in imu.h,
  which currently has no comment on it.
- bleDrainEventQueue() sends exactly one item per call. Rename to
  bleSendNextEvent(), since bleFlushEventQueue() is the one that empties.

DEAD FIELD:
- StoredCompression::reserved[3] (depth.h) is written every compression at
  depth.cpp:805 and never serialized — storage.cpp's packer writes 17 named
  bytes then advances by STORAGE_COMPRESSION_SIZE (20). Confirm removing it
  changes nothing on disk, report, then delete.

SESSION_END NAMING — firmware and app disagree on two fields:
- s.patientTemperatureLastPulseCheck -> app calls it patientTemperature,
  dropping the qualifier. A reader of the app alone would assume it is live.
- s.rescuerTemperatureStart/End -> app calls them rescuerWristTempStart/End.
  Pick one name per field and make both sides match.

APP-SIDE LEFTOVERS:
- live_cpr_screen.dart:634 reads data['valleyDepth'] from the broadcast map,
  but ble_connection.dart's map builder has never included that key. Always
  null -> 0.0. Fix or delete.
- AnimatedDepthBar.residualLoadDepthCm (depth_bar.dart) is accepted as a
  constructor parameter and never read in build(). Wire it or remove it.
- The old feedbackEnabled had the shape "parsed, put in the map, never read
  back." Grep for other fields with that same shape and list them.
```

---

## F. Commit the BLE spec, then reconcile

**In progress.** Spec committed (`aca3b32`, now `CPR_Assist_BLE_Spec_v3_2.md`).
Reconciliation report: `docs/BLE_SPEC_RECONCILIATION.md`. Apply pass pending.

`CPR_Assist_BLE_Spec_v3_1.md` **is not in the repo.** It is referenced
throughout the code and it is a thesis appendix. Its absence is why the signal
dictionary had to infer the spec from the app parser.

**Commit it first, by hand.** An uncommitted thesis appendix is one dead
laptop from gone.

```
Reconcile CPR_Assist_BLE_Spec_v3_1.md against firmware/SIGNALS.md, row by
row. Report every disagreement before changing the spec. No builds.

Known already:
- Spec section 3 marks bytes 52-55, 86, 102-107 as reserved. Firmware writes
  live data to all of them. (These may have moved if block D is done first —
  check current state, do not assume.)
- The 0x04 PULSE_CHECK_START row still says checks occur "every 2 minutes of
  active CPR time." That constraint was removed. The same wrong sentence is
  in the thesis.
- residualLoadDepthCm was renamed from valleyDepth after the spec was
  written.

When code and spec disagree, the CODE is authoritative. Fix the spec, not the
firmware. Add a v3.2 changelog entry listing every change.
```

---

## G. Thread safety

**Done** — `b936418` (audit, `firmware/THREADING.md`) + `e8c414f`/`a920bcf`
(diag-globals fix). Items 3, 5, 6 of the audit need hardware to close.

Never audited. Two cores share `gState`. This is the most likely source of a
bug that appears only under load — i.e. during a participant session.

```
Read-only audit. Do not edit. Write findings to firmware/THREADING.md.

Files: cpr_glove.ino, shared_state.h, ble_manager.cpp, depth.cpp, imu.cpp

1. Every read and write of gState — is each under gStateMux, or explicitly
   documented as single-core? shared_state.h:154-157 claims the diag globals
   are safe because both writer and reader are on commsTask. Verify that
   claim against actual call sites.
2. snapshotState() — does it copy atomically? Can a reader see a torn
   multi-field state, e.g. lastPeakDepthCm from one compression paired with
   lastPeakConfidence from the next?
3. Task priorities and stack sizes as configured. Report headroom for each.
   Flag anything close to its limit.
4. depthFinalizeLastValley() is called before snapshotState() in
   stopSession(). Confirm that ordering holds on every path out of a session,
   including error and disconnect paths.
5. Any blocking call (delay, I2C transaction, LittleFS write) on a task that
   also services BLE. Report each with its worst-case duration.
6. What happens if the BLE stack disconnects mid-notification.
```

---

## H. Metrics mapping

**Dropped** — thesis finished (2026-10-15). Kept below as record.

`SIGNALS.md` says what the firmware **produces**. Nothing says whether that is
what the study **needs**. `residualDepthX10` was the warning — declared,
documented with a literature citation, never implemented, unnoticed for
months.

**This is mostly your work, not Claude Code's.** Write down every number that
appears in your results: every table, figure, and statistical test in the
thesis and the paper. Then map each to a row in `SIGNALS.md`.

Three outcomes, all useful:
- **Metric with no signal** → you cannot compute it. Find out now, not during
  analysis.
- **Signal with no metric** → firmware computes and transmits something
  nothing uses. Deletion candidate.
- **Metric mapped to a defective row** → anything using `correctRecoil`
  inherits the structural `<= totalCompressions - 1`; anything calling
  `residualLoadDepthCm` a depth is misdescribed.

Claude Code can help with the second direction once you have the list:

```
Given docs/METRICS.md (the list of numbers that appear in my results), check
every row of firmware/SIGNALS.md and report which signals no metric consumes.
Report only. Do not delete anything.
```

Output goes in the paper's methods section, so the work counts twice.

---

## I. Hardware validation

**Pending hardware.**

**Not a Claude Code task.** Everything since the defense — the pulse-check
redesign, the force calibration, the depth selector, and all of blocks A–G —
is committed and unvalidated on hardware.

The checklist in `CORRECTIONS.md` is the real gate. Nothing below matters
until it is done.

- [ ] Contact threshold measured
- [ ] PPG waveform verified against a reference
- [ ] Compression-detection chatter test at the threshold boundary
- [ ] Wrist dropout actually fires when the wrist IMU is disconnected (new —
      block C)
- [ ] Battery curve checked against a multimeter at full, mid, empty (block A)
- [ ] Diagnostic sheet open during an active session, live values stay correct
      (block D)
- [ ] One full run: glove → app → backend → export
- [ ] Full discharge run from full charge to cutoff, logging voltage and
      elapsed time. Gives a real runtime number and validates the curve.
      Device endurance belongs in the thesis anyway.

---

## J. Golden vector

**Highest-value item in this document.** Everything above is a snapshot that
goes stale the moment someone edits a file. This is the only thing that keeps
working on its own.

```
Build a regression fixture from a real session.

1. I will capture the raw BLE bytes of one real session and commit them to
   test/fixtures/.
2. Write a test that feeds those bytes through ble_data_processor.dart and
   asserts the full parsed output, field by field.
3. Write a second test that feeds the parsed session through
   session_service.dart's grading and asserts the final grade and every
   sub-score.
4. Both must run under flutter test with no device and no network.

This converts every fix in this plan from a one-time observation into a
permanent check.
```

Do this **before** the study, not after.

---

## K. Pre-study flags

**Pending hardware.**

Last thing before the first participant. Verify on the flashed firmware, not
in the source.

- [ ] `FORCE_CALIB_LOCK = 1` — `config.h:370`
- [ ] `K_STUDY_LOCKED = 3.15f` — `config.h:208` (left-hand study glove;
      `K_POPULATION_DEFAULT` 1.30f is the Emergency fallback, not the study value)
- [ ] `DEPTH_PIPELINE_LOG = 0` — `config.h:264`
- [ ] `DEPTH_SELECTOR_LOG = 0` — `config.h:268`
- [ ] `BLE_DEBUG_SERIAL = 0` — `config.h:259`
- [ ] `STUDY_BUILD = 1` — `config.h:278`, flipped last (see TASKS.md §6)
- [ ] `FORCE_TEST_LOG = 0`, `IMU_TEST_LOG = 0`

`MANIKIN_CALIBRATION_LOG` no longer exists — renamed `DEPTH_PIPELINE_LOG`
(`config.h:264`). Fix any checklist still naming it.

---

## What "done" means

Blocks A–F make the firmware **clean**: nothing dead, nothing misnamed, every
value traceable to a one-sentence derivation.

Block I makes it **trustworthy**. That is a different property, and it is the
one the study depends on.

Correct, clearly named, and validated on hardware is the target. A slightly
ugly constant you have measured beats a beautifully named one you have not.
