# Demo Video — Pass 1 Inventory (read-only)

Read-only inventory of the live source tree, for the conference demo video shot script.
No files were modified. All paths relative to `CPR-Assist-App/cpr_assist/lib/` unless
marked `[firmware]` (relative to `CPR-Assist-Firmware/`). Every claim below is cited to a
file and line range from the actual code, not from documentation or memory. Anything not
independently verified is marked **UNVERIFIED**.

There is **no go_router** in this app — `context.push()` wraps `Navigator.push` +
`MaterialPageRoute` (`BuildContextNavigation.push`). The navigation root is
`MainNavigationScreen` (`core/widgets/main_navigation.dart:16-115`), a 3-tab `PageView`
(AED Map / Live CPR / Guide, `main_navigation.dart:40-44`) plus a slide-in `AccountPanel`
overlay (`main_navigation.dart:106`, toggled from the header avatar,
`main_navigation.dart:96`). Everything else is pushed with `context.push()` or shown via
`showDialog` / `showModalBottomSheet`.

---

## 1. Every screen

### Root shell

| Screen | File | What the user sees | How they reach it |
|---|---|---|---|
| `MainNavigationScreen` | `core/widgets/main_navigation.dart:16` | 3-tab shell, bottom nav bar, `UniversalHeader` | `main.dart:201`, `MaterialApp.home` |
| `AccountPanel` | `features/account/screens/account_menu.dart:58` | Right-to-left slide-in panel (not a `Drawer`) | Tap avatar icon in header, `main_navigation.dart:96` |

### Tab 0 — AED Map

| Screen / dialog | File | What it is | Trigger |
|---|---|---|---|
| `AedMapScreen` | `features/aed_map/screens/aed_map_screen.dart:22-110` | Emergency-call banner (`AppColors.emergency`) fixed above a full-bleed clustered Google Map (`AEDMapWidget`) | Bottom-nav index 0 |
| `Simulation112Dialog` | `features/training/widgets/simulation_112_dialog.dart:12` | 7-step scripted 112 dispatcher call, header reads "112 Emergency Call" / subtitle **"Training Simulation"** (`simulation_112_dialog.dart:100-104`) | Banner tap **in Training mode only** (`aed_map_screen.dart:46-52, 82`). In Emergency mode the same banner instead calls `tel:112` via `launchUrl` + `HapticFeedback.heavyImpact()` (`aed_map_screen.dart:41-44`). **Correction from the user:** a `tel:` URI opens the Android dialer with 112 pre-filled — it does not place the call. Safe to film normally; the user will film it with the phone in airplane mode as an extra precaution. |
| `AedWebviewScreen` | `features/aed_map/screens/aed_webview_screen.dart` | In-app WebView used for the "Kids Save Lives" info page (`https://kidssavelives.gr/`), opened from an info dialog in `aed_map_display.dart:225-234`. Not used for AED data itself. | KSL info button on the map |

Note: `simulation_112_dialog.dart:6-9` carries a stale header comment claiming it's "used inside the Guide screen." Verified by grep — the **only** live call sites are `aed_map_screen.dart:50` and `dev_preview_screen.dart:1045` (the internal dev widget catalogue, not a real user flow). The Guide screen never opens this dialog.

**AED map mechanics** (for filming): AED data comes from the project's own Railway/Postgres backend (`aed_service.dart:53-91`, `GET $baseUrl/aed`), cache-first with stale-cache fallback. Tapping a marker opens an `AEDCard` (`aed_map_cards.dart:20-120`) with a 4-tier distance/ETA resolution — preloaded real route → cached road distance → straight-line estimate → resolving live (`_resolve()`, lines 46-103) — so a card's numbers can visibly upgrade a few seconds after the map loads. Directions are either in-app turn-by-turn navigation (`AEDRoutingCoordinator`/`NavigationController`, wired in `aed_map_widget.dart:81-123, 806-844`) or an external handoff to Google Maps (`route_service.dart:198-218`, `LaunchMode.externalApplication`). Location permission uses standard `geolocator` gating (`location_service.dart:21-44, 69-96`), degrading gracefully (map still shows AEDs) if denied.

### Tab 1 — Live CPR

| Screen | File | What it is | Trigger |
|---|---|---|---|
| `LiveCPRScreen` | `features/live_cpr/screens/live_cpr_screen.dart:38` | Single screen, internal state machine (idle → active → overlays → ended) | Bottom-nav index 1 |
| `SessionResultsScreen` | `features/training/widgets/session_results.dart:42` | Pushed automatically on session end | `live_cpr_screen.dart:793` / `:819` |
| `LoginScreen` | `features/account/screens/login_screen.dart` | Standard email/password login form (`login_screen.dart:100`, `authStateProvider.notifier.login(...)`) | Mode-switch-to-Training while logged out, or post-Emergency-session login offer |

**Mode/scenario switching — exact guard code** (verifies the CLAUDE.md rule):
- `account_menu.dart:139-167` (`_handleModeSwitch`) and `live_cpr_screen.dart:856-884` (inline `onModeToggle`) both run the identical pattern:
  `isLoggedIn = ref.read(authStateProvider).isLoggedIn` → if switching to Training **and** not logged in: `AppDialogs.promptLogin` → push `LoginScreen` → re-check login state, return early if still logged out → **then** `AppDialogs.confirmSwitchToTraining` / `confirmSwitchToEmergency` (`app_dialogs.dart:60, 130`).
- Net effect: no unauthenticated path reaches Training. The literal call order is *prompt-login-then-confirm*, not *confirm-blocked-by-login* — functionally equivalent, wording difference only.
- The toggle is disabled entirely while a session is active (`live_cpr_screen.dart`, scenario/mode chips disabled during session — status bar section `:1084-1237`).
- A "No-Feedback" sub-mode exists inside Training — suppresses glove audio/vibration/LED per its own info dialog text (`live_cpr_screen.dart:1126-1128`) but still records and grades.
- Grepped `promptLogin|confirmSwitchToTraining|isLoggedIn|authStateProvider` across the whole `lib/` tree: **no login gate found anywhere else** — not on AED map, Guide, Quiz, or app launch. `account_menu.dart:233-260,405` renders a "Guest" label rather than blocking.
- Additional login-adjacent flow not in the original rule list: ending an **Emergency** session while logged out offers a **dismissible, non-blocking** login prompt to optionally claim/save the session (`live_cpr_screen.dart:782-816`) — consistent with "prompt once, non-blocking."

### Tab 2 — Guide

Hub-and-detail reference, `guide_screen.dart` (2606 lines), no login required, entirely static content (no network calls), sourced "ERC Guidelines 2025" (`guide_screen.dart:7-40` header comment cross-checked against hub `onTap` targets — full screen bodies not exhaustively read).

- **Chain of Survival** — 4-link timeline screen (recognition/call → CPR & AED → advanced care → recovery).
- **Compressions & Breathing** — tabbed (HANDS / RATE & DEPTH / BREATHING), includes `_RateGaugeBar` / `_DepthGaugeBar` visual gauges and a "Stayin' Alive" 103 BPM tip.
- **AED** — tabbed (USE IT / PADS / SPECIAL CASES), includes a `_PadPlacementSVG` schematic and special-case cards (pacemaker, wet skin, pregnant, hairy chest, pediatric).
- **Quick Steps** — 8-step sequential checklist (scene safety → responsiveness → call 112 → send for AED → 30 compressions → 2 breaths → continue 30:2 → AED when available).
- **Special Situations** — adult-vs-pediatric comparison table + drowning/pregnancy/opioid-overdose/hypothermia cards.
- **Stop & Recovery** — stop criteria + recovery position instructions.
- **Knowledge Quiz** — `context.push(const QuizScreen())` from the hub's "Test your knowledge" card (`guide_screen.dart:152-160`). `quiz_screen.dart` header (`:5-11`) states "No login required. No backend. Self-contained." 10 hard-coded multiple-choice questions (depth 5-6cm, rate 100-120/min, full recoil, 30:2 ratio, hand placement, infant depth, compression-fraction definition, immediate-AED-use, ~1s breath duration, step order), each tagged "AHA/ERC 2020" (`quiz_screen.dart:26-112`). Immediate per-answer feedback with explanation text, running score, restart option. **No quiz → achievement tie-in**: grepped `achievement_service.dart` for "quiz" — zero matches.

### Account panel destinations

Logged-in only: Leaderboard, My Sessions, Achievements, edit-profile row. Always visible: Settings, Help & About (body content **UNVERIFIED** — not deep-read by any fork), Log In/Out, and a **"UI Preview" entry with no debug-build gate found** — this opens `DevPreviewScreen`, an internal widget catalogue. **Do not film this** — it isn't part of the real user experience, it's a dev tool. Deep link `reset-password?token=...` pushes `ResetPasswordScreen` (`main.dart:153-166`). NFC tag `open?tab=cpr` switches to the Live CPR tab (`nfcTabNotifier`).

### From session results

`SessionHistoryScreen` ("View All Sessions →"), `ExportBottomSheet` (export icon), delete/note dialogs, `_GradeInfoDialog` (Training only, "?" icon on the grade ring, shown to match the exact grading weights below). From History: multi-select (2–4 sessions, **not fixed at 2**) → `SessionCompareScreen`.

### Glove maintenance / diagnostics

`GloveDiagnosticSheet` (`features/account/screens/glove_diagnostic_sheet.dart`, 2743 lines) — reached from Settings → "Run sensor check" (`settings_screen.dart:219-224`), opened as a modal bottom sheet. This is a hardware bring-up/QA tool, not a lightweight status screen:
- Auto-runs a BLE self-test on open (`_runQuickSelftest`, lines 284-314).
- "Quick Check" summary tile: pass/warn/fail counts across 8 tested components (`_AllComponentsTile`, lines 740-902); tap opens a dialog listing per-sensor failure reason codes (I²C ACK failure, wrong chip ID, calibration failure, etc., lines 362-372).
- Per-component tiles (force sensor, both IMUs, depth pipeline, both pulse/SpO2 sensors, both temp sensors, audio, vibration, LED bar, battery, I²C bus, mode button) — each opens a guided live test screen with sparkline, pass/fail evaluation, and CSV export.
- Header shows live battery % and a "Download full diagnostic log" button exporting every streamed raw signal since the sheet opened.
- **Good potential cutaway**: the top-level PASS/WARN/FAIL summary tile reads as a clean "hardware integrity check" shot; the per-component detail is too dense for a lay conference audience.

---

## 2. User flows, in the order a real user hits them

1. **Launch** — loads prefs, starts connectivity monitoring, applies the wakelock setting, loads `.env`, warms AED caches, checks auth in the background. Lands on the AED Map tab (`main.dart:21-72`).
2. **BLE pairing/connection** — no dedicated pairing screen. Connection is a persistent background service (`BLEConnection`) kept alive at the app root (`main.dart:183`, comment: "Keep BLE provider alive at root so the glove connection persists across tab switches"). Auto-scans and auto-reconnects with exponential backoff. User-visible state lives entirely in a small pill in the global header (`_BleAndBatteryPill`, `core/widgets/universal_header.dart:155-230`) present on every main-tab screen: connected (shows live battery %/charging), scanning, "tap to retry" (Bluetooth found no glove), Bluetooth off, disconnected. Tapping the pill opens a `_GloveStatusDialog`. There is **no manual device-picker UI** anywhere in the app — pairing is fully automatic.
3. **Mode selection** — Emergency ⇄ Training, gated as described above.
4. **Live session** — `SESSION_START` resets display state and starts a 1s elapsed timer; real-time feedback per §3.
5. **Session end** — always saves locally first; a session under ~10 compressions or a mid-session disconnect produces a distinct "nothing recorded" / "too short" / "saving partial session" message (`live_cpr_screen.dart:715-745`); Emergency + logged-out gets the one-time non-blocking login offer; then a backend save attempt; then push to results.
6. **Results** — Training: 3-tab (Overview/Metrics/Charts) grade-card layout. Emergency: 3-tab (Summary/Vital Signs/Timeline) outcome-card layout. Achievement/certificate unlock toasts fire here (Training only — `session_results.dart:42-88` runs `_checkNewAchievements` only when `!_isEmergency`).
7. **History** — filter chips, mode badges, search, sort (date/grade/duration), multi-select for comparison.
8. **Comparison** — 2-4 sessions, color-coded per slot, Overview + Metrics tabs.
9. **Export** — PDF, CSV, or raw-data CSV/ZIP; single-session or multi-session summary.
10. **Secondary screens** — AED Map, Guide, Quiz, Achievements, Leaderboard (Global = real backend data + requires ≥3 sessions for a rank; Friends = **explicitly a placeholder, no backend friends system yet** per code comment, `leaderboard_screen.dart:20`; My Stats = real), Account/Settings, Glove Diagnostics.

---

## 3. Real-time feedback during a live session

- **Depth bar** (`live_cpr/widgets/depth_bar.dart`) — pure `CustomPainter`, 0–8 cm mapped linearly to widget height (not a normalized score; real BLE centimeter value, `depth_bar.dart:20,30,94`). RELEASE pill (0–1 cm) and DEPTH pill (target–targetMax, e.g. 5–6 cm adult / narrower pediatric band passed in via `CprScenario`) glow green when hit. Track fill: amber below target, green in target, red above max (`depth_bar.dart:227-274`). Live value comes from BLE field `data['depth']` (`live_cpr_screen.dart:651`); a separate fused per-compression peak value drives pill/grading logic.
- **Frequency gauge** (`rotating_arrow.dart`, `FrequencyArcGauge`) — 120° arc, red 60–100 CPM / green 100–120 CPM / red 120–160 CPM zones, numeric CPM readout, `--` when idle.
- **Status-bar coaching pills** — GOOD / TOO SLOW / TOO FAST (rate) and GOOD / TOO SHALLOW / TOO DEEP (depth), **latched** state (3 consecutive bad compressions to flip, 2 good to clear) to prevent flicker (`live_cpr_widgets.dart:329-408`). A one-line text coaching hint appears only after 5 consecutive same-problem compressions (`live_cpr_widgets.dart:411-452`).
- **30:2 cycle progress bar** — "N/30" label, turns amber at ≥26/30, full bar shown during a ventilation window (`live_cpr_widgets.dart:555-592`).
- **Ventilation overlay** (`training/widgets/ventilation_overlay.dart`) — full-screen modal scrim, appears when BLE flag `isVentilationWindow` is set **and** the settings ventilation ratio isn't "compressions only" (`live_cpr_screen.dart:457-466`). Breathing circle with an outward ripple once per second, "Cycle N" and "Pause detected" pills, pause-duration counter in tenths turning red past 8 s, footer "Closes automatically when compressions resume." **Visibility is firmware-driven** — the app only mirrors the flag closing when it goes false (`live_cpr_screen.dart:631-639`); it does not independently decide the 30:2 timing.
- **Pulse-check card** (`training/widgets/pulse_check_overlay.dart`) — explicitly **not a modal**; file header states there is "no decision to make: the glove can't yet distinguish the patient's pulse from the rescuer's own, so the measurement is never presented as something to act on" (lines 10-14). Live: a scrolling PPG waveform (renders "No signal" text rather than a fabricated flat line, lines 395-428) and a pulsing "Circulation check in progress" → static "recorded" icon. **No classification, BPM, or confidence is shown live** — the 3-way ABSENT/UNCERTAIN/PRESENT result (`pulse_check_event.dart:25-29`) only appears afterward, on the results screen. Matches the project's passive-only, no-rescuer-prompted-pause rule; no code path prompts the rescuer to pause.
- **Vitals cards** — Patient Vitals card only populates after a pulse check completes, greys out between checks; confidence badge gates HR/SpO2 display at ≥40% confidence. Rescuer's own vitals card shows a separate signal-quality badge.
- **Two-minute rescuer-swap banner** — slides in on BLE `isTwoMinAlert`, auto-dismisses after a 10 s countdown.
- **Fatigue — confirmed UI gap, verified directly against the code**: `FATIGUE_ALERT` sets `_showFatigueBadge`/`_fatigueScore` (`live_cpr_screen.dart:70-71, 471-472`) and both are passed into `LiveCprMetricsCard` as `showFatigueBadge`/`fatigueScore` (`live_cpr_screen.dart:931-932`, declared as fields in `live_cpr_widgets.dart:286-287, 302-303`) — **but grep confirms neither field is read anywhere else in that widget file.** There is currently **no live on-screen fatigue indicator**. Do not script one; the fatigue score only surfaces post-session, on the results Metrics tab and in the Compare screen's rescuer-HR trend chart.
- **Glove-side feedback (audio/vibration/LED) is real but never mirrored on-screen.** The glove has its own independent feedback loop: an onboard speaker with pre-recorded voice cues (press harder/faster, slow down, ease off, lift hands, straighten arms, ease force, give two breaths, check pulse, pulse present/absent/uncertain, fatigue-switch, two-min-switch, a short "click" when depth target is reached — `[firmware] config.h:576-612`), a haptic motor that ticks once per compression-rate period as the rate metronome (`[firmware] motor.cpp:37`, `cpr_glove.ino:1428-1435`), and a physical NeoPixel LED depth bar. None of this is re-rendered in the app UI — it only surfaces as Settings sliders (volume/vibration-intensity/LED-brightness, each drag-to-0 disables that channel) and in the Glove Diagnostic Sheet's component tests. **Film the glove's own audio/haptic/LED off the hardware, not the screen** — the app depth bar and the glove's physical LED bar move independently in sync but are not the same rendering.
- **`Simulation112Dialog`** — see §1; confirmed visually marked "Training Simulation" in its own on-screen subtitle, reachable only from the AED Map banner in Training mode.
- **Mode/scenario status bar** — Emergency/Training label (tap-to-toggle, disabled mid-session), "No feedback" chip, Adult/Pediatric scenario label (disabled mid-session), each with an info-icon explanation dialog.
- **Cross-screen indicator**: the bottom-nav Live CPR tab icon pulses red/grey when a session is active and the user has navigated away from that tab (`main_navigation.dart:161-165, 196-272`).
- Elapsed timer (mm:ss) and raw compression count are shown continuously in the metrics card alongside the above.

---

## 4. Metrics computed and displayed

### Grading — `calculateGradeFromDetail`, `session_service.dart:282-332`

Read directly, in full. Training-only: Emergency sessions and sessions under 10 compressions always return `0.0` (lines 284-285) — there is no letter grade anywhere in this function, only a single `double` clamped 0–100 (line 331), stored as `totalGrade`.

Eight weighted 0–100 component scores, each computed from session-wide counts: Depth consistency, Rate consistency, Full-recoil consistency, Depth+Rate combo, Hands-on ratio, Ventilation compliance (**zero detected ventilation windows scores 100, not penalized** — deliberate, because the app can't distinguish compression-only CPR from a missed detection, comment at lines 274-280), Posture consistency, Time-to-first-compression (tiered: <5s→100, <10s→80, else→50).

Two weight sets selected by scenario (lines 306-329):
- **standard_adult**: Depth 25% / Rate 20% / Recoil 20% / Combo 8% / Hands-on 5% / Ventilation 12% / Posture 8% / Time 2%
- **pediatric**: Depth 28% / Rate 18% / Recoil 18% / Combo 8% / Hands-on 4% / Ventilation 12% / Posture 8% / Time 4%

Confirmed by direct read: no force-safety term and no fatigue penalty anywhere in this function — `overForceCount` and fatigue fields exist on the session record but are never referenced here. Over-force and fatigue are tracked and displayed as standalone metrics only, consistent with the project's own "do not touch" description of this function. The in-app `_GradeInfoDialog` (opened via "?" on the results grade ring) shows the same weights.

### Per-compression metrics (`compression_event.dart:79-93`)

Depth, instantaneous/rolling rate, force/peak force, recoil achieved, over-force flag (>600 N adult / >400 N pediatric, computed firmware-side, app just displays it), leaning detected, posture-OK flag, `wristAlignmentAngle` (3D compression-vector deviation from vertical, target <15°), `compressionAxisDeviation` (used to compute `effectiveDepth = depth × cos(axisDeviation)`, a sternum-corrected depth — code comment tags this **"Thesis-novel metric,"** line 92-93), `wristFlexionAngle` (±45° range, target ±10°, also tagged **"Thesis-novel metric,"** line 85). **Corrected against firmware:** `[firmware] shared_state.h:51` documents this as `palm minus wrist pitch` — a **two-IMU differential** (palm pitch − wrist pitch), computed in `[firmware] depth.cpp:479, 827`, not a reading from a single IMU. The user is separately fixing a BLE-spec doc that states this incorrectly. Narration must describe it as a differential between the two IMUs, not attribute it to either sensor alone — this is distinct from the palm-IMU-only posture pair (`wristAlignmentAngle`/`compressionAxisDeviation`) named in the project's "do not touch" rules, since it is the only metric in the app that deliberately fuses both IMUs. `residualLoadDepthCm` (force-to-depth proxy for incomplete recoil).

### Session-level metrics

Hands-on ratio, no-flow time/intervals, unplanned-pause time/count, rescuer-swap count, fatigue-onset index + fatigue-alert timestamp/score, depth/frequency consistency & standard deviation, rate variability, time-to-first-compression, ventilation count/compliance/correct-count, pulse-check counters and per-event detail (classification, detector A/B counts, BPM, confidence — labeled Unreliable <40 / Acceptable 40-79 / Strong ≥80 — perfusion index, PPG samples), patient temperature/SpO2, rescuer HR/SpO2/wrist-temp snapshots each tagged by pause type (active/ventilation/pulse-check), rescuer HRV (RMSSD), rescuer perfusion index, rescuer humidity ("rising humidity = sweating = fatigue indicator"), and a composite rescuer `fatigueScore` (0-100) built from those channels — separate from and not fed into the grade.

### Results screens

Both Emergency and Training results share one 3-tab layout shell with date/time, note card, export, delete, and a "past sessions" link (`session_results_layout.dart:660-662`, header comment `session_results.dart:29-40`):
- **Training** — "gamified" layout: circular grade ring (color thresholds ≥90/75/55) + 3 sub-rings (Depth/Rate/Recoil %), "NEW PERSONAL BEST" banner, scenario badge, tabs **Overview / Metrics / Charts**. Metrics tab: per-category quality tiles, best-streak banner, session timeline (start, fatigue onset, pauses, ventilation cycles, pulse checks, rescuer swaps, end), rescuer vitals section. Charts tab: compression depth, compression rate (green band 100-120), 5-compression rolling depth trend, wrist alignment, rescuer heart-rate trend ("rising trend = increasing physical load").
- **Emergency** — single-scroll-style layout: incident header, pulse/ROSC outcome card (Pulse Detected / No Pulse Detected / Weak Signal / No Pulse Check, with a heartbeat icon animation and the stored PPG waveform), CPR quality summary, tabs **Summary / Vital Signs / Timeline**.

### History, Compare, Export, Achievements, Leaderboard, Certificates

- **History** (`session_history.dart`) — sortable (date/grade/duration), filterable, mode badges, personal-best card, multi-select → Compare (2-4 sessions, not fixed at 2). Logged-out empty state offers Login/Register buttons.
- **Compare** (`session_compare_screen.dart`, 2719 lines) — Overview tab (score rings per session, key-stats row, trend line chart across selected sessions, radar/spider "consistency" chart, early/mid/late within-session phase-comparison card) and Metrics tab (detailed per-metric group rows). Reached only from History's multi-select action.
- **Export** (`export_bottom_sheet.dart`, `export_service.dart`) — PDF, per-session/all-sessions CSV, or raw-data (individual per-stream CSVs or a bundled ZIP of compressions/vitals/ventilations/pulse-checks). The PDF includes a training hero (grade ring + sub-rings) or emergency hero (ROSC banner + stat pills), a two-column metrics table, ventilation/pulse-check/biometrics tables, a multi-session-capable radar table, and phase-comparison cards/tables.
- **Certificates** (`certificate_service.dart`) — computed **entirely client-side** from local session history, no backend endpoint. 5 milestones (5 sessions ≥75%, 10 sessions, 20 sessions, one session ≥90%, one good session in each of standard_adult/pediatric/no-feedback scenarios), each with a separate "Certificate of Achievement" PDF export.
- **Achievements** (`achievement_service.dart`) — also fully client-side, 10 tracked achievements (first session, ≥75% grade, session-count milestones, ≥90% grade, 3- and 5-session quality streaks, total-compression milestones, one pediatric session, one no-feedback session, one-of-each-scenario).
- **Leaderboard** (`leaderboard_screen.dart`) — 3 tabs: **Global** (real backend data, `GET /leaderboard/global?scenario=`, requires ≥3 sessions to get a rank), **Friends** (code comment explicitly labels this **"placeholder — no backend friends system yet,"** line 20 — do not depict as functional), **My Stats** (real, local).

---

## 5. Genuinely novel or non-obvious (flagged for the demo)

1. **Confidence-based sensor fusion for compression depth**, not a fixed weighted blend — per-stroke selection between IMU-derived and force-derived depth across multiple outcome states `[firmware] depth.cpp`. This is a project "do not touch" item — describe it in narration, don't show the code.
2. **Force→depth is a calibrated power-law model, not linear** `[firmware] force.cpp` — also a "do not touch" item.
3. **Sternum-corrected "effective depth"** (`effectiveDepth = depth × cos(compressionAxisDeviation)`) and **wrist flexion angle** (palm pitch minus wrist pitch, a two-IMU differential — `[firmware] shared_state.h:51`) are explicitly tagged "Thesis-novel metric" in the code comments (`compression_event.dart:85, 92`) — a second posture axis alongside the palm-IMU grading angle, and the only metric in the app that fuses both IMUs.
4. **A rescuer physiological fatigue score derived from the rescuer's own wrist sensors** — HRV (RMSSD), perfusion index, skin-humidity trend, composited into a 0-100 score, snapshotted throughout the session and tagged by pause type. It only appears post-session (results Metrics tab, Compare's rescuer-HR trend chart) — there is no live on-screen fatigue indicator (verified gap, §3).
5. **The pulse check never renders a live verdict** — confirmed in code, not just policy. Classification, BPM, and confidence only appear retrospectively on the results screen.
6. **The glove has a complete, independent feedback loop** (spoken audio cues, haptic rate metronome, physical NeoPixel LED depth bar) that is never re-rendered on-screen — the on-glove audio channel in particular gives more granular real-time coaching (it covers posture and over-force) than the app screen does, which only surfaces depth and rate live. Worth filming directly off the hardware.
7. **Grading deliberately excludes over-force and fatigue as scoring inputs** — the score measures technique, not stamina or patient danger; both are shown only as standalone live-session and post-session metrics.
8. **Ventilation-compliance scoring quirk**: zero detected ventilation windows scores 100/100 — a deliberate false-negative-avoidance design choice, not a bug.
9. **Mode/scenario changes are locked out mid-session**, including from the glove's own physical mode button — an attempted change mid-CPR is logged but ignored, so grading targets can't shift under a participant mid-session.
10. **AED-map emergency banner is one UI element with two behaviors**: in Emergency mode it opens the phone dialer with 112 pre-filled (does not place the call itself), in Training mode it opens an explicitly-labeled simulation dialog — a clean way to demonstrate the safety design without depicting a real emergency call.
11. **Certificates and achievements are both fully client-side**, computed from local session history with no backend round-trip.
12. **No manual BLE device-picker exists anywhere** — pairing is fully automatic scan-and-reconnect with only a small header pill and a "tap to retry" fallback, a deliberate hands-free design choice for an emergency-use device.

---

## 6. Gaps not verified this pass

Full bodies of: `help_about_screen.dart`, `registration_screen.dart`, `forgot_password_screen.dart`, `reset_password_screen.dart` (beyond its deep-link entry point), `profile_editor_screen.dart` (beyond confirming no login wall), all 6 Guide detail-screen bodies beyond their hub `onTap` targets, `aed_map_panels.dart`, `aed_webview_screen.dart` internals, `certificate_service.dart` PDF layout, most of `GloveDiagnosticSheet` past its first ~1350 lines (individual per-component test bodies), and the raw BLE parsing layer `ble_data_processor.dart` (only how `live_cpr_screen.dart` consumes its output was checked).

None of these gaps are load-bearing for the script's core argument (the live CPR session, the depth/rate feedback loop, and the results/grading), but they should not be scripted as specific shots without a quick direct check first.
