# Post-defense corrections

## Firmware
- [ ] Contact-plus-pause gating for circulation check (passive only, never prompts)
- [ ] Remove audio/haptic prompt from pulse check trigger
- [x] Low-SQI must report "Uncertain", not "Absent"
- [x] BLOCKING BEFORE USER STUDY — K_POPULATION_DEFAULT does not match the
      thesis's stated k values, in either mode. The thesis states the
      firmware starts at k=1.30 and that the user study runs with k=3.45
      locked. Neither value exists in the code:
        - K_POPULATION_DEFAULT is 1.7131f, not 1.30.
        - 1.35f is commented out directly below K_POPULATION_DEFAULT — an
          earlier value, not the current one, and not 1.30 either.
        - The (since-rewritten) FORCE_CALIB_LOCK workflow comment referenced
          "calibK ≠ 1.3500" as the value to compare a fresh fit against —
          another 1.35, not 1.30.
        - FORCE_CALIB_LOCK is 0 — k is NOT locked. The
          "3.45 locked" claim in the thesis describes a state the firmware
          is not currently built to.
        - 3.45 does not appear anywhere in the firmware.
        - The eight Little Anne manikin values annotated beside
          K_POPULATION_DEFAULT (2.9612, 2.8710, 2.7046,
          2.9585, 3.0136, 2.6200, 2.5847, 2.9615) average 2.83, not 3.45 —
          so even if 3.45 were meant to derive from those runs, it isn't
          their mean, and there are eight of them, not the ten the thesis
          implies.
      Root cause: K_POPULATION_DEFAULT is being asked to serve two
      incompatible roles — the literature-derived population-mean fallback
      for uncalibrated human chests in Emergency mode (Tomlinson 2007,
      k≈1.35 rounded, per the Tomlinson-derivation comment above
      K_POPULATION_DEFAULT), and the slot for a hardcoded locked manikin k
      per the calibrate-then-lock workflow documented in the comments above
      K_POPULATION_DEFAULT and around FORCE_CALIB_LOCK.
      Whoever last set it to 1.7131f (the Little Anne bench-derived value)
      overwrote the literature fallback without introducing a separate
      constant for the locked-study role, so neither the thesis's 1.30
      startup value nor its 3.45 locked value is actually compiled in.
      PROPOSED FIX, pending confirmation — do not implement without
      sign-off: split the two roles into separate constants —
      K_POPULATION_DEFAULT 1.30f (Tomlinson population mean, used in
      Emergency/uncalibrated mode) and a new K_STUDY_LOCKED 3.45f (used
      only when FORCE_CALIB_LOCK = 1) — each with full derivation
      provenance in its comment. Needs a decision on where 3.45 actually
      comes from (which/how many calibration runs) before it can be
      written down with an honest comment.
      RESOLVED — confirmed the thesis values are correct and the firmware
      had drifted. K_POPULATION_DEFAULT is now 1.30f, with
      its comment carrying only the Tomlinson 2007 derivation. A new
      K_STUDY_LOCKED 3.45f holds the Little Anne study k —
      averaged from 10 independent runs of ~30 compressions each — and is
      wired in as _calibK's initial/reset value in force.cpp whenever
      FORCE_CALIB_LOCK is 1. FORCE_CALIB_LOCK flipped to 1.
      The surrounding workflow comments above K_POPULATION_DEFAULT/
      K_STUDY_LOCKED and around FORCE_CALIB_LOCK
      were rewritten to describe the two constants' separate roles instead
      of the old hardcode-k-into-K_POPULATION_DEFAULT workflow.
- [ ] ADDRESSED — PENDING HARDWARE VALIDATION. Rescuer-pulse discriminator
      using simultaneous wrist HR. Problem: the patient sensor is a
      fingertip pressed against the carotid, with the rescuer's own perfused
      fingertip immediately behind it — nothing stopped the glove reporting
      the rescuer's own pulse as the patient's. In cardiac arrest the
      patient's true signal is usually absent by definition while an
      adrenalised rescuer has strong peripheral perfusion, making self-
      detection the most likely false positive.
      Fix landed: max30102ClassifyPulse (max30102.cpp) takes one rescuer
      hrBpm/sigQuality pair and downgrades Present → Uncertain when the
      patient and rescuer rates agree within PULSE_SELF_DETECT_BPM_TOL
      (config.h, 10 BPM). Downgrade only — never upgrades, never touches
      Absent or an already-Uncertain result. Guarded: does not fire if the
      rescuer HR is zero/out of physiological range (30-180 BPM, same bound
      as the patient rateOk check) or rescuer sigQuality is below
      PULSE_MIN_SIGNAL_QUALITY (40, the same threshold the patient hard-
      rejection check uses) — a missing or unreliable reference leaves the
      classification untouched. The classifier itself is pure and ignorant
      of where the reference came from.
      Reference selection lives at the call site (cpr_glove.ino, window
      close): prefers the live rescuer reading (snap.heartRateUser /
      snap.rescuerSignalQuality, contemporaneous with this close) but falls
      back to the paused snapshot (rescuerHRLastPause / the new
      rescuerSQLastPause, both captured at window-open while the rescuer's
      hand was still) when live fails the quality gate. This matters because
      the window's usual close path (WINDOW_RESUME_COMP_COUNT, only 2 comps)
      fires right as the rescuer's wrist starts moving again — exactly when
      the live channel is most likely motion-corrupted and would otherwise
      make the guard silently no-op in the common case. On a backstop close
      the paused snapshot can be the full window old, but a backstop close
      already means the rescuer never resumed and contact never cleanly
      broke — the least trustworthy classification this system produces
      regardless of this guard, so a stale reference nudging that toward
      Uncertain is correct, not a defect.
      rescuerSQLastPause (shared_state.h) is a new internal-only field, not
      part of the transmitted SESSION_END summary or storage.cpp's persisted
      layout — pairs an SQI with the existing rescuerHRLastPause/
      rescuerSpO2LastPause snapshot so the paused reference can be
      quality-gated the same way the live one is.
      SPEC LIMITATION: PKT_PULSE_CHECK_RESULT (Spec v3.1, locked) has no
      spare field, so the downgrade reason cannot be transmitted over BLE.
      The app currently cannot distinguish a self-detection downgrade from
      an ordinary weak-signal Uncertain — clinically these are different
      (one means "this might be your own pulse", the other means "signal
      too poor to tell") and worth a spec revision later to add a reason
      code. For now it's only visible in Serial under the existing
      BLE_DEBUG_SERIAL flag: cpr_glove.ino logs
      `[PULSE] self-detect ref: source=live|paused|none patient=...bpm
      ref=...bpm(sq=...) cls=...` at every window close, so source=none
      (no usable reference at all — the discriminator silently no-opped)
      is distinguishable on hardware from source=live/paused with cls
      unchanged (reference was available but didn't agree).
- [ ] OPEN — not fixed. gState.heartRateUser is published every 500ms with
      no quality gate: max30102UpdateRescuer (max30102.cpp) writes
      _pR.hrBpm unconditionally, and it's only zeroed after ~1.5s of
      sustained no-contact (_rNoContactStreak >= 150). Between those, a
      motion-corrupted value (e.g. mid-compression) can sit in
      gState.heartRateUser looking like a valid reading. The self-detection
      guard above works around this itself (checks rescuerSignalQuality
      before trusting it), but other consumers of heartRateUser —
      including, on the app side, the live rescuer vitals card — may be
      trusting it blindly without checking rescuerSignalQuality alongside
      it. Needs a sweep of every reader of heartRateUser (firmware and app)
      to confirm each one either checks signal quality or has a reason not
      to.
- [x] `imu.cpp`'s file-header comment said ±8g/0x5C; now correctly reads
      ±4g/0x4A, matching `IMU_CTRL1_XL_VALUE`. Confirmed fixed 2026-08-30.
- [x] The comment above `IMU_CTRL1_XL_VALUE` in `config.h` said ±2g; now
      correctly reads ±4g. Confirmed fixed 2026-08-30.
- [ ] Before user study: MANIKIN_CALIBRATION_LOG=0, BLE_DEBUG_SERIAL=0
- [ ] ADDRESSED — PENDING HARDWARE VALIDATION. Patient PPG FIFO overflowed:
      max30102UpdatePatient was folded into the 500 ms rescuer vitals block,
      but the 32-sample FIFO holds only 320 ms at 100 Hz, so a 500 ms drain
      dropped ~1/3 of every batch and the synthetic clock (_pSampleClockMs
      += 10/sample) ran ~40% slow, inflating patient hrBpm and distorting
      RR_MIN/MAX refractory windows feeding detB / max30102ClassifyPulse.
      Fix landed: patient PPG now drains on its own LIVE_STREAM_INTERVAL_MS
      (100 ms) timer, gated on pulseCheckActive || diagActive, separate
      from the 500 ms rescuer block. This fixes the hrBpm inflation and
      RR-window distortion. It does NOT fix the transmitted waveform —
      that turned out to be a separate bug (see next item). Not
      hardware-validated — see hardware checklist below. Same commit also
      fixed the patient-temperature contact check (was `ppgRaw > 0.08f`, a
      stale threshold on the wrong signal that read contactOk=true with no
      contact; now uses max30102PatientContactOk(), the same per-sample
      IR-DC gate the rest of the pulse pipeline already uses).
- [ ] ADDRESSED — PENDING HARDWARE VALIDATION. PPG waveform rendered as a
      staircase / flat line, not a pulse. Root cause was NOT the 2 Hz vs
      10 Hz drain rate (that was a wrong diagnosis, corrected above) — it
      was that ppgRaw (max30102.cpp) was a batch-averaged raw-IR/262144 DC
      ratio with no meaningful pulsatile content: envelope ≈ 40 counts on
      a ≈130000 DC baseline, i.e. real variation ≈0.00015 out of the 0–1
      range, invisible after any scaling. Fix landed: ppgRaw now streams
      `0.5 + 0.5*(_pP.filtered / (_pP.envelope * 2.5))`, the AC-coupled
      bandpass-filtered value centred on 0.5, clamped to [0,1], falling
      back to 0.5 when there's no fresh envelope this drain. Checked both
      app-side PPG painters: pulse_check_overlay.dart's live _PpgPainter
      auto-scales (unaffected either way); session_results_emergency.dart's
      _PpgResultPainter uses a fixed 0–1 axis and needed real pulsatility
      to render anything — this is the painter the staircase symptom was
      actually about.
- [ ] BLOCKING BEFORE USER STUDY — bench the contact threshold on real geometry.
      PULSE_GATE_CONTACT_IR_MIN currently inherits CONTACT_IR_MIN (30000),
      tuned for a finger covering the sensor, not a fingertip pressed outward
      against neck skin. Measure patient IR DC in four states: sensor in air,
      resting on clothing/bench, pressed on human neck, pressed on manikin neck.
      Set threshold at the midpoint of the actual gap. Needs max30102DiagPatientDc().
      NOTE: if the manikin's plastic neck reads below threshold, the gate never
      opens during the study. Must be checked before any session is run.
- [ ] Chatter test: pause → contact → one window opens; hold through resume prompt;
      resume compressions → closes; pause again without lifting → NO second window;
      lift and replace → second window opens.
- [ ] Confirm the 200 ms pause-time contact probe doesn't inflate sensorTask dt
      (depth integral is the validated output — see the `sensorTask()`
      gI2CMutex-contention notes in `cpr_glove.ino`).
- [ ] HARDWARE — validate both patient PPG fixes above, separately:
      (1) 100 ms drain: patient HR (heartRatePatient) is no longer inflated
      relative to a known-good reference (pulse oximeter or manual count)
      during a pulse-check window.
      (2) ppgRaw waveform formula: the waveform sent to the app — both live
      (pulse_check_overlay.dart) and in stored session results
      (session_results_emergency.dart's _PpgResultPainter) — renders as a
      visible pulse trace, not a flat line or a staircase.
      (3) Mid-window contact-loss freeze — FIXED, confirm on hardware.
      _pP.filtered/_pP.envelope are left as running state on contact loss
      (deliberately not reset/decayed — they're what the peak detector's
      40%-of-envelope threshold and the SQI envelope score depend on, and
      contact loss inside a window is often transient), so ppgRaw now
      explicitly overrides to 0.5f in max30102UpdatePatient's
      `if (!anyContact)` branch instead of computing from stale values.
      SQI/hrBpm/spO2 were already protected by that same branch — traced
      and confirmed not reachable into max30102ClassifyPulse (sigQuality
      and hrBpm both zero out well before the window's 500ms contact-loss
      debounce elapses). On hardware: confirm a deliberate mid-window
      contact loss shows as a flat trace at mid-axis (not frozen, not a
      drop to 0) and that the waveform resumes cleanly — no discontinuity
      or stuck value — when contact returns.
- [ ] HARDWARE — on the first study session, confirm from the serial log
      (DEPTH_PIPELINE_LOG's CALIB line, calibK field) that k reads 3.45 at
      boot and stays 3.45 for the full two-minute session under real
      compressions — never drifts, never reverts toward the population
      mean. This is the empirical check that FORCE_CALIB_LOCK actually
      holds in practice, not just by code-path analysis.
- [ ] HARDWARE — validate the rescuer-pulse self-detection discriminator.
      With the glove on and the fingertip (patient) sensor pressed against
      your OWN neck (both channels reading the same person), confirm the
      pulse-check result is Uncertain, not Present. If it still reports
      Present, check cpr_glove.ino's Serial log under BLE_DEBUG_SERIAL —
      `[PULSE] self-detect ref: source=... patient=...bpm ref=...bpm(sq=...)
      cls=...` — at window close. source=none means no rescuer reference
      (live or paused) cleared PULSE_MIN_SIGNAL_QUALITY, so the guard never
      ran; source=live/paused with ref far from patient means it ran but the
      rates genuinely didn't agree.

## App
- [x] PulseCheckOverlay is now a non-blocking card in the Live CPR screen's
      scrollable content column, not a modal — confirmed via the widget's own
      file-header comment in `pulse_check_overlay.dart`. Fixed 2026-08-30.
- [x] Compliance metrics removed from the pulse check UI — classification,
      BPM, and confidence are stored in the session record and shown only on
      the results screen, never on the live card. Confirmed 2026-08-30.
- [x] CCF benchmark display now reads ≥60% everywhere it's graded against
      (`export_service.dart`, `session_compare_screen.dart`). Confirmed
      2026-08-30. `quiz_screen.dart`'s "Target is ≥60%, ideally ≥80%" is
      separate educational copy, not this defect — flagged separately, not
      changed.

## Token audit
- [x] Baseline recorded — 198 real violations
      (424 raw minus 226 pw.* PDF-package hits; script over-counts, see note)
- [x] Ratchet in place — tool/token_ratchet.sh, BASELINE=424 (raw number)
- [ ] 25 real violations fixed: Color(0x) 6, Colors.* 17, Navigator.of 1, MediaQuery 1
- NOTE: audit script does not exclude pw.TextStyle/pw.BoxDecoration.
  Subtract ~226 from any raw total. Ratchet uses the raw number, which is
  fine for regression detection.
- Inline TextStyle/BoxDecoration in Flutter code (~171 across 24 files) =
  ACCEPTED DEBT. Fix opportunistically when already editing a file.
  Not a standalone task.

## Features (in order)
- [ ] F1 settings audit
- [ ] F2 help & about
- [ ] G1 forgot/reset password UI polish
- [ ] H1 achievements / H2 certificates / H3 quiz
- [ ] I1 icons / I2 tooltips
- [ ] L2 alert 112 via url_launcher
- [ ] K2 standalone glove verification
- [ ] Export PDF: saveContext/restoreContext in gradeSparkline, genericSparkline,
      radar polygon, both trainingHero ring painters

## HTTP error handling — still substring-matches in three screens
`network_service.dart` now throws `HttpStatusException` (carries a real
`statusCode`) instead of a bare `Exception` for non-2xx responses, and
`SessionService.deleteSession` was switched to check `e.statusCode` instead
of `e.toString().contains('404')`.
- [ ] `login_screen.dart`, `registration_screen.dart`, `reset_password_screen.dart`
      still parse the status code out of the exception's string form via
      `e.toString().contains('401')` etc. They still work today because
      `HttpStatusException.toString()` was deliberately kept in the same
      `HTTP <code>: <message>` shape the old `Exception('HTTP $code: $msg')`
      produced — but they're one string-format change away from silently
      breaking, and none of them branch on `e.statusCode` even though the
      type is now available. Migrate to `e is HttpStatusException` checks
      when those screens are next touched.

## UI
- [ ] Open design decision: `_AEDCardInternal`'s `timeColor`
      (`aed_map_cards.dart`) still tints the ETA
      time/icon with `AppColors.aedNavGreen`/`AppColors.primary` (walking/
      driving), while the route polyline itself now draws in `success`/
      `primaryAlt` (see buildRoutePolyline in route_service.dart). Both are
      visible on screen at once — the card and its own route line no longer
      match. Decide whether card accents should follow the polyline swap or
      are intentionally a separate palette.
- [ ] Per-event pause rows can't distinguish a 45 s overrun from a clean
      10 s pause. VentilationEvent/PulseCheckEvent display `durationSec`
      capped at `maxAcceptablePauseSec` (10 s) with a compliant marker, so
      a pause that ran 4.5x over shows identically to an honest 10 s pause
      in the in-app timeline (`_SessionTimelineSection` in
      `session_results_training_tabs.dart`),
      the PDF ventilation log (`_ventilationTable` in `export_service.dart`),
      and the PDF timeline (`_buildSessionTimeline` in `export_service.dart`).
      The overrun IS correctly
      counted in the session-level unplannedPauseTime/unplannedPauseCount
      aggregate via `SessionDetail.applyPauseModel`,
      but nothing links that summary back to the specific row that caused
      it. Proposed fix: carry the true (uncapped) duration alongside
      cappedDur and suppress the success marker on rows that overran.
      Also fix the imprecise note in `_twoColumnMetrics`
      (`export_service.dart`) — it reads
      "not explained by ventilation/pulse checks", but this time IS
      associated with a ventilation/pulse-check window, just in excess of
      the allowance; that wording is wrong for that portion.

## Analyzer cleanup — unused_element_parameter (2026-08-25)
- [x] Reviewed all 24 `unused_element_parameter` warnings from the analyzer
      cleanup pass. Left all 24 in place — none are inert dead code.
      - `reason` (`_SelftestRow` in `app_dialogs.dart`) is a lint false
        positive: it IS passed at call sites in
        `glove_diagnostic_sheet.dart`'s selftest-row construction, via the
        `SelftestRow` typedef, and its value renders in
        `_SelftestResultsDialog`'s failure-detail text
        (`app_dialogs.dart`). The `unused_element_parameter` lint
        appears not to resolve constructor calls made through a type alias.
        Deleting it would silently drop the failure-reason text from the UI.
      - The other 23 are optional parameters genuinely wired into real
        internal logic (rendering, layout, behavior branches) on shared
        private widgets/data classes — e.g. `isDisabled`/`disabledHint` on
        `_PanelItem` (account_menu.dart, full dim + hint UI implemented),
        `rows` on `_HistoryCard` (glove_diagnostic_sheet.dart, default used
        by all 8 call sites), `focusNode` on `_AppTextField`
        (login_screen.dart, wired into TextFormField), `width`/`height` on
        PDF chart/table helper classes (export_service.dart), `badge`/
        `badgeColor`/`borderColor`/`isEmergency` on timeline event widgets
        (session_results_training_tabs.dart), and similar in
        session_results_charts.dart, session_results_emergency.dart,
        session_results_shared.dart, session_results_vitals_dialogs.dart,
        settings_screen.dart, guide_screen.dart, leaderboard_screen.dart,
        pulse_check_overlay.dart. No current caller overrides the default,
        but the code path is live, not cruft.
      Deleting all 24 would strip working (if currently unexercised)
      capability rather than remove dead weight — left for a deliberate
      decision rather than blind lint-driven deletion.

## Notes
- M24 remains closed. kCmdStart/kCmdStop (0xF3/0xF4) stay commented on the
  app side. The CMD_START/CMD_STOP cases in `onAppCommand()` are live and
  wired to startSession()/stopSession(), but the app deliberately has no caller —
  session start/stop is owned by the glove's physical button. Adding a
  sendStart/sendStop caller is a BLE behaviour change against locked
  Spec v3.1 and needs an explicit decision, not an uncommenting.
- Unresolved comment ambiguities from the firmware comment audit — could not
  tell whether the comment or the code drifted, left as-is pending judgement:
  - `validDepth`'s "used for storage gating" comment (`depth.cpp`) may be true at one remove (feeds stored depth SD) rather than wrong; not clearly one or the other.
  - `imuGetWristFlexionDeg()`'s two call sites in `depth.cpp` — "signed ±45" isn't enforced anywhere; unclear if that's a dropped clamp or just an expected range.
  - `depthUpdate()`'s live-depth comment in `depth.cpp` — "jitters ±cm at 25 Hz" matches neither the 100 Hz update rate nor the 20 Hz NeoPixel render rate; unclear which was meant.