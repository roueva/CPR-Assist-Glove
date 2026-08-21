# Post-defense corrections

## Firmware
- [ ] Contact-plus-pause gating for circulation check (passive only, never prompts)
- [ ] Remove audio/haptic prompt from pulse check trigger
- [ ] Low-SQI must report "Uncertain", not "Absent"
- [ ] Rescuer-pulse discriminator using simultaneous wrist HR
- [ ] `imu.cpp:4` comment says ±8g/0x5C, should be ±4g/0x4A
- [ ] `config.h:142` comment says ±2g, confirm ±4g and fix comment
- [ ] Before user study: MANIKIN_CALIBRATION_LOG=0, BLE_DEBUG_SERIAL=0
- [ ] Patient PPG FIFO overflows: max30102UpdatePatient drains at 500 ms
      (cpr_glove.ino:1430) but the 32-sample FIFO holds only 320 ms.
      ~36% of samples dropped; synthetic clock (_pSampleClockMs += 10) runs
      ~40% slow, inflating patient hrBpm and distorting RR_MIN/MAX refractory
      windows, which contaminates detB feeding max30102ClassifyPulse.
      Fix: drain patient at ≤200 ms during the window, or detect FIFO
      overflow and advance the clock accordingly.
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

## Notes
- M24 remains closed. kCmdStart/kCmdStop (0xF3/0xF4) stay commented on the
  app side. The firmware handler at cpr_glove.ino:200-206 is live and wired
  to startSession()/stopSession(), but the app deliberately has no caller —
  session start/stop is owned by the glove's physical button. Adding a
  sendStart/sendStop caller is a BLE behaviour change against locked
  Spec v3.1 and needs an explicit decision, not an uncommenting.