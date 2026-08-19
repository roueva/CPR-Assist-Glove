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