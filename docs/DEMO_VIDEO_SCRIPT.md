# Demo Video Script — CPR Assist Glove

Booth-loop / supplementary-material cut. 3:30 runtime, English narration.
Built from `docs/DEMO_VIDEO_INVENTORY.md` (Pass 1, corrected). Everything shown here
exists in the current code; nothing aspirational is scripted.

## Production notes — read before filming

- **Audio sourcing.** There is no app-side audio. The compression metronome is a
  haptic pulse in the glove (felt, not heard). Spoken coaching cues ("press harder,"
  "give two breaths," "check pulse") play through the glove's own onboard speaker,
  not the phone. This means: (1) a phone screen recording will be **silent** and
  contributes no usable audio, (2) any device audio in the final video has to come
  from the **camera's on-set microphone** capturing the glove speaking in the room,
  and (3) narration must duck or pause during those beats so the glove's cues are
  audible on camera, per the rows marked **[GLOVE AUDIO — narration drops out]** below.
- **Screen recordings are silent overlays.** Mute the screen-recording audio track
  entirely before compositing; do not let it fight the camera audio.
- **Sync points are load-bearing.** Rows marked **[SYNC]** are the actual argument
  for the device — a compression bottoming out at the same instant the depth bar
  glows green. Film these as one continuous take of the phone screen and the
  compression together if at all possible; do not rely on fixing sync in the edit.
- **Simulation labeling.** The one 112-related shot is scripted as the Training-mode
  simulation dialog only. It carries its own on-screen "Training Simulation"
  label — keep it in frame. The Emergency-mode banner (which pre-fills the phone
  dialer with 112 but does not place a call) is not shown in this cut, to avoid
  any ambiguity for viewers who only catch a few seconds.
- **No live fatigue indicator exists today.** None is scripted. See footnote after
  the shot list if this becomes worth revisiting.
- **No participant faces, no real patient data.** Manikin only.

---

## Script

| Time | Main frame (camera) | Inset / cutaway | On-screen text | Narration |
|---|---|---|---|---|
| 0:00–0:15 | Wide shot: a rescuer kneeling beside a manikin, glove already on the compressing hand. Static beat, no motion yet. | — | Title card, lower third: "CPR Assist Glove — MSc Thesis, Aristotle University of Thessaloniki" | "Compression quality is what determines survival in cardiac arrest, and it's exactly what a rescuer can't judge by feel. This is a wearable feedback system built to close that gap." |
| 0:15–0:30 | Close-up, hands-on-glove: the compression glove on the wrist and hand, static, well lit. Optional macro on the sensor housing. | CUTAWAY (3s, full frame): header BLE pill transitioning scanning → connected, with live battery percentage visible. | Label callout: "Two motion sensors · force sensor · pulse, oxygen and temperature sensors" | "Two motion sensors, a force sensor, and biometric sensors are built into the glove. It pairs with the phone automatically over Bluetooth. There's no device list to search — it connects as soon as it's in range." |
| 0:30–0:35 | Rescuer's hands settle onto the manikin's chest, about to begin compressions. | — | — | (silence — let the moment land before compressions start) |
| 0:35–1:05 | Continuous compressions on the manikin, steady rate, camera holding a three-quarter angle that keeps both hands and the phone in frame. | **Inset**, top-left, ~15–18% frame height: live depth bar (color-coded track, RELEASE/DEPTH pills) and the frequency arc gauge with numeric BPM readout. | — | "Depth and rate are read directly off the glove, in real time. The bar fills as the compression deepens, and turns green only inside the clinical target range." |
| 1:05–1:15 | **[SYNC]** Single compression bottoming out, held for one full beat, camera as close as the rig allows on the hand-to-chest contact. | **Inset stays live, same position.** At the exact instant of full depth, the DEPTH pill on the bar glows green. This beat must be filmed as one take, not composited after the fact. | On-screen freeze-frame label at the sync instant: "Depth confirmed" | (no narration during the sync beat itself — let it read visually) "That's the moment the two have to agree." |
| 1:15–1:25 | Compressions continue, slightly faster or slower on purpose for one or two strokes to show the rate gauge responding. | Inset: frequency arc gauge sweeping between its red and green zones, coaching pill switching TOO FAST / GOOD. | — | "Rate gets the same live treatment. Drift outside the target band and the glove and the app both flag it, on the spot." |
| 1:25–1:45 | Camera pulls back slightly as compressions continue toward a 30-count; on the 30th, hands lift for ventilation. | **CUTAWAY, full frame**, timed to the lift: the ventilation overlay taking over the phone screen, breathing circle, "Cycle 1" pill, pause timer counting up in tenths. | — | "After thirty compressions, the app opens a ventilation window automatically. It's reading the glove's own timing, not guessing from the phone." |
| 1:45–1:55 | Compressions resume immediately as the overlay closes. | CUTAWAY confirms: overlay dismissing itself as compressions restart, no tap required. | — | "It closes itself the moment compressions restart." |
| 1:55–2:15 | Rescuer pauses, hand resting on the manikin's wrist/neck area for a circulation check (staged, no real pulse reading exists on a manikin — frame it as the gesture only). | **CUTAWAY, full frame**: the pulse-check card, live PPG waveform scrolling, "Circulation check in progress." | — | "During a pause, the app can also read the patient's circulation. It never renders a verdict live. That's deliberate. The glove can't yet tell the patient's pulse from the rescuer's own, so it isn't offered as something to act on in the moment." **[GLOVE AUDIO — narration drops out for the last 2s if the glove's own spoken pulse-check cue is audible on camera]** |
| 2:15–2:35 | Compressions resume briefly, then stop; rescuer sits back. | **CUTAWAY, full frame**: session ending, screen transitioning into the results screen. Training-mode grade ring animating in, or Emergency-mode outcome card, whichever was actually recorded. | On-screen label: "Session ends → results, no manual save step" | "When the session ends, everything is already scored." |
| 2:35–2:55 | Static: phone held up, screen visible. | **CUTAWAY, full frame**: results Metrics/Charts tab, scrolling to the wrist-alignment chart and the rescuer heart-rate trend. | Label: "Posture: differential between the two wrist sensors, not a single reading" | "Posture is scored from a difference between the two motion sensors on the glove, not from either one alone. Physical load on the rescuer is tracked too, from their own pulse and skin readings through the session, separate from the technique score." |
| 2:55–3:05 | Quick handheld pan across a room: AED wall unit briefly in frame (if available), otherwise cut this beat. | **CUTAWAY, full frame, quick montage** (~3s each): AED map with a marker tap and a resolving ETA; then the Training-mode 112 dialog, clearly reading "Training Simulation" in its header, held long enough to read. | Watermark on the 112 shot: "SIMULATION — no call is placed" | "The app also finds the nearest defibrillator, and walks a rescuer through the emergency call. That call flow is shown here as the training simulation only." |
| 3:05–3:15 | — | **CUTAWAY, full frame, quick montage** (~2–3s each): session history list, two sessions selected into the comparison screen, achievements screen with a certificate tile, settings screen with the vibration/LED sliders. | — | "Past sessions are kept on the phone, and can be compared side by side, exported, or shared as a PDF." |
| 3:15–3:30 | Wide shot returning to the rescuer and manikin, matching the opening frame. | — | End card: device name, institution, "Pending hardware validation — user study in preparation" | "The goal isn't a score for its own sake. It's giving a rescuer the same feedback a trained instructor would, in real time, with no one else in the room." |

**Total runtime: 3:30. Word count: ≈390 words of narration across 3.5 minutes (≈112 wpm average, under the 150 wpm ceiling with margin for the two audio-drop beats.)**

---

## Footnote — fatigue indicator

No live fatigue indicator exists in the app today (verified against the code, not
just absent by omission — the data already reaches the metrics-card widget but the
widget never renders it). If one gets built before filming, it would slot into the
**1:15–1:25 rate segment** as a second inset element (a small badge, not a full bar,
to stay legible at 15–18% frame height), and would need one clause of narration
added there. Nothing else in this script depends on it.

---

## Shot list — camera footage to capture in one session

Film in roughly this order to minimize resets:

1. **Opening/closing wide shot** — rescuer kneeling beside manikin, glove on hand, static beat before starting. Film once, use for both 0:00–0:15 and 3:15–3:30 (same setup, so they visually match).
2. **Glove close-up** — hand and glove only, well lit, camera close enough to read the sensor housing. Static, ~10s, several takes for grading options.
3. **Hands settling onto manikin chest** — the beat just before compressions start. ~5s.
4. **Continuous compression run, three-quarter angle** — both the compressing hand and the phone (held or mounted where the operator can see it) in frame simultaneously. This is the longest, most important take — get at least 90 seconds unbroken, several times, at a steady rate in the 100–120/min range so a clean full-depth compression can be selected for the sync shot.
5. **Extreme close-up on a single compression bottoming out** — hand-to-chest contact only, timed to a full-depth stroke. This must be shot as the SAME take as its paired phone screen recording (see below) — coordinate a countdown with whoever is filming the screen.
6. **Rate variation beat** — one or two strokes deliberately faster or slower than target, same three-quarter angle as #4.
7. **30-compression cycle into ventilation pause** — compressions continuing to a 30-count, then hands lifting off. ~20s.
8. **Compressions resuming after the ventilation pause** — hands returning to the chest. ~5s.
9. **Circulation-check pause gesture** — hand resting near the manikin's wrist/neck, staged (no real physiological signal from a manikin). ~10s.
10. **Compressions resuming briefly, then stopping, rescuer sitting back** — the session-end beat. ~10s.
11. **Phone held up static shot** — for the results-screen cutaway framing (just the operator's hand/arm holding the phone steady, screen itself is the screen recording). ~10s.
12. **Room pan past an AED wall unit**, if one is available on location — optional, cuttable.

## App flows to screen-record, in order

Record on the actual glove-paired phone, not the simulator, so the depth bar and
gauge move on real sensor data. Suggested order, matching the script's use order:

1. **App launch → BLE connect** — cold launch through the header pill going scanning → connected, with battery % visible once connected.
2. **Live CPR session start through a steady compression run** — the segment that will be composited as the small inset over camera footage. Record this at the same time as shot list item #4 if the rig allows a synced clapperboard moment; otherwise record it separately and plan to re-time it to the camera footage in editing, matching cadence by ear/eye since there is no shared audio track to sync on.
3. **The exact full-depth compression** used for the sync shot (item #5 above) — record this as its own short, isolated clip so it can be cut precisely against the camera close-up.
4. **A brief rate excursion** (compression rate drifting out of target and the gauge/pill responding) — for the 1:15–1:25 beat.
5. **A full 30-compression cycle into the ventilation overlay opening, and its auto-dismiss** on compressions resuming.
6. **A pulse-check card opening and closing** — Emergency mode, with the PPG waveform visibly scrolling.
7. **Session end → results screen transition**, whichever mode was actually recorded (Training grade ring or Emergency outcome card).
8. **Results screen, scrolled to the Metrics/Charts tab** — specifically the wrist-alignment chart and the rescuer heart-rate trend chart.
9. **AED map: a marker tap and the ETA card resolving** from estimate to a real route.
10. **Training-mode 112 simulation dialog** — opened from the AED map banner in Training mode, header visible reading "Training Simulation." Do not record the Emergency-mode banner tap.
11. **Session history list → multi-select → comparison screen.**
12. **Achievements screen** — scrolled to show a certificate tile.
13. **Settings screen** — vibration and LED brightness sliders.

Record each flow as its own clean clip with a couple of seconds of static padding at
the start and end, so cuts have room to breathe in the edit.
