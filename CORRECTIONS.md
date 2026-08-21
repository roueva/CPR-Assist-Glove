# Post-defense corrections

## Firmware
- [ ] Contact-plus-pause gating for circulation check (passive only, never prompts)
- [ ] Remove audio/haptic prompt from pulse check trigger
- [ ] Low-SQI must report "Uncertain", not "Absent"
- [ ] Rescuer-pulse discriminator using simultaneous wrist HR
- [ ] `imu.cpp:4` comment says ±8g/0x5C, should be ±4g/0x4A
- [ ] `config.h:142` comment says ±2g, confirm ±4g and fix comment
- [ ] Before user study: MANIKIN_CALIBRATION_LOG=0, BLE_DEBUG_SERIAL=0
- [ ] ADDRESSED — PENDING HARDWARE VALIDATION. Patient PPG FIFO overflowed:
      max30102UpdatePatient was folded into the 500 ms rescuer vitals block,
      but the 32-sample FIFO holds only 320 ms at 100 Hz, so a 500 ms drain
      dropped ~1/3 of every batch and the synthetic clock (_pSampleClockMs
      += 10/sample) ran ~40% slow, inflating patient hrBpm and distorting
      RR_MIN/MAX refractory windows feeding detB / max30102ClassifyPulse.
      Fix landed: patient PPG now drains on its own LIVE_STREAM_INTERVAL_MS
      (100 ms) timer, gated on pulseCheckActive || diagActive, separate
      from the 500 ms rescuer block. Also fixes the transmitted waveform,
      which was updating at 2 Hz (below Nyquist for a 1–1.7 Hz pulse) while
      sent over BLE at 10 Hz. Not hardware-validated — see hardware
      checklist below. Same commit also fixed the patient-temperature
      contact check (was `ppgRaw > 0.08f`, a stale threshold on the wrong
      signal that read contactOk=true with no contact; now uses
      max30102PatientContactOk(), the same per-sample IR-DC gate the rest
      of the pulse pipeline already uses).
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
      (depth integral is the validated output — see mutex note at cpr_glove.ino:1307).
- [ ] HARDWARE — validate the patient PPG 100 ms drain fix above: confirm the
      waveform sent to the app renders as an actual pulse trace, not a
      staircase, and that patient HR (heartRatePatient) is no longer
      inflated relative to a known-good reference (pulse oximeter or manual
      count) during a pulse-check window.

## App
- [ ] Demote PulseCheckOverlay from full-screen blocking to non-blocking card
- [ ] Remove compliance metrics from pulse check UI
- [ ] Fix two overclaiming strings in UI
- [ ] CCF benchmark display ≥80% → ≥60%

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
- [ ] Open design decision: aed_map_cards.dart:170 still tints the ETA
      time/icon with `AppColors.aedNavGreen`/`AppColors.primary` (walking/
      driving), while the route polyline itself now draws in `success`/
      `primaryAlt` (see buildRoutePolyline in route_service.dart). Both are
      visible on screen at once — the card and its own route line no longer
      match. Decide whether card accents should follow the polyline swap or
      are intentionally a separate palette.

## Notes
- M24 remains closed. kCmdStart/kCmdStop (0xF3/0xF4) stay commented on the
  app side. The firmware handler at cpr_glove.ino:200-206 is live and wired
  to startSession()/stopSession(), but the app deliberately has no caller —
  session start/stop is owned by the glove's physical button. Adding a
  sendStart/sendStop caller is a BLE behaviour change against locked
  Spec v3.1 and needs an explicit decision, not an uncommenting.