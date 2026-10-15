**CPR Assist Glove**

Complete BLE & Data Specification

*Firmware • App • Backend • Data Models • Local Storage*

| **Version** | **Status** | **Date** | **Author** |
| --- | --- | --- | --- |
| 3.3 | Final Draft | October 2026 | Evanthia Rouka, AUTH BME |

# **1. System Overview**

This document is the definitive specification for all data exchanged between the CPR Assist Glove and the Flutter mobile application. It covers BLE architecture, packet layouts, session lifecycle, computed metrics, the grading formula, app screen behaviour, backend schema, and local storage for offline operation.

Version 3.0 supersedes v2.0. Changes from v2.0: LIVE_STREAM expanded to 100 bytes; EVENT_CHANNEL expanded to 96 bytes; additional LIVE_STREAM fields (depthTrend, rescuerFatigueScore, imuCalibrated, wristDropped, rescuerRMSSD, rescuerPI); additional EVENT_CHANNEL packet types (0x0B SELFTEST_RESULT, 0x0C SCENARIO_CHANGE); additional app→glove commands (0xF7–0xFD); temperature encoding changed to uint16 fixed-point; sessionElapsedMs removed from LIVE_STREAM.

Version 3.1 supersedes v3.0. This release reconciles the specification with the as-built firmware and app, which already agree with each other on the items below; only this document was behind. Changes from v3.0: LIVE_STREAM is 108 bytes (not 100) — compression peak/valley timestamps added at bytes 94–101 and rescuer humidity documented at byte 85. SESSION_END byte 66–69 redefined as the last carotid skin temperature captured during a pulse check (patientTemperatureLastPulseCheck), not a generic patient temperature. SESSION_END bytes 70–73 are reserved (rescuer wrist temperature start/end live at bytes 82–89). SESSION_END ambientTempStart/ambientTempEnd renamed to rescuerWristTempStart/rescuerWristTempEnd (the GXHT30 measures wrist skin temperature with skin contact — there is no ambient/room air sensor). SESSION_END bytes 93–94 added as timeToFirstCompressionMs (uint16, saturates at 65535). Rescuer fatigue score redefined as a depth-decline proxy (RMSSD is not an input). Clarified that the patient pulse-check confidence field and signal-quality value are the same quantity, and that rescuer perfusion index and rescuer signal quality share a common AC/DC source. Grading formula (§9) reconciled with the as-built app: §9.1/§9.2 weights corrected to the depth-weighted scheme actually implemented, the force-safety term and fatigue penalty removed from the grade (over-force and fatigue remain standalone session metrics and live warnings, not grade modifiers), and the timed-endurance scenario removed entirely (only standard_adult and pediatric are supported). Local-storage sessionFormatVersion corrected from 3 to 5 to match firmware STORAGE_FORMAT_VERSION and the app's offline parser. Secondary (wrist) IMU description corrected: posture is computed from the palm IMU only in the current configuration — the wrist IMU is not fused.

Version 3.2 supersedes v3.1. This release documents the DIAG_FRAME packet (0x0D), which has been implemented in firmware and parsed by the app since the diagnostics tool was added but was never described in this specification. Changes from v3.1: new section 4.14 defining DIAG_FRAME (0x0D), a glove-to-app engineering telemetry frame sent at 4 Hz only while the diagnostics sheet is open; DIAG_FRAME added to the packet type reference in 4.1 and to the appendix quick reference. DIAG_FRAME carries two build-provenance fields, buildFlags (byte 17) and buildStamp (bytes 18-21), which report the compile-time configuration of the flashed firmware so that a study build can be verified on the device rather than inferred from source. App-to-glove commands 0xF3 START and 0xF4 STOP are marked reserved and not implemented app-side: the constants exist in the app but are commented out, and session start and stop are driven by the physical button only. No change to LIVE_STREAM or to any existing EVENT_CHANNEL packet layout.

Version 3.3 supersedes v3.2. This release reconciles the specification with the as-built firmware and app, which already agree with each other on every item below. No firmware behaviour changed. Changes from v3.2, row by row in docs/BLE_SPEC_RECONCILIATION.md: LIVE_STREAM bytes 52–55 (residualLoadDepthCm), 86 (inVentilationWindow) and 102–107 (lastPeakDepthCm, lastPeakConfidence, lastPeakDepthSource) documented, as they were never reserved. Byte 91 documented as a 3-bit feedback mask. Patient vitals documented as also sent while diagnostics are active, and patient temperature as zero outside a pulse-check window. compressionAxisDeviation source corrected to palm-IMU roll. fatigueFlag and wristDropped definitions corrected. PULSE_CHECK_START trigger rewritten as the passive contact-plus-pause gate, and its intervalNumber redefined as a pulse-check count. PULSE_CHECK_RESULT close condition corrected, byte 9 refSource documented, and the self-detection downgrade described. SESSION_END byte 95 (wristDroppedDuringSession) documented, and correctVentilations, pulseChecksPrompted and pulseChecksComplied redefined. SESSION_END inactivity timeout corrected. SELFTEST_RESULT bytes 5–15 and its extra triggers documented. 0xF7 CALIBRATE behaviour corrected. Commands 0xFE, 0xFF, 0xEB, 0xED, 0xEC and 0xEE added. DIAG_FRAME byte 6 redefined as the last diagnostic action or button event. Session lifecycle steps 7–9 and the pulse-check card rewritten. VentilationEvent model corrected to the app's measured-duration fields. Local storage file name, meta file, header field order, compression padding and pulse-check entry size (13 bytes) corrected. Posture: wristAlignmentAngle documented as absolute palm pitch with a 30° target, postureOk as alignment only, and wristFlexionAngle as a display guide that is not scored. The firmware already used this rule. The app's labels, charts and exports, which stated 15° alignment and ±10° flexion, were corrected to match. The graded correctPosture count is unchanged. Session start (§5.1 step 2) and imuCalibrated corrected: there is no 500 ms gravity baseline. §9 now states the < 10 compression rule, the app-side ventilation compliance source, and grade bands instead of letter labels. §11 rewritten from CPR-Assist-Server/db.js. Stored ventilation byte renamed compressionsDuringWindow (was ventilationsGiven), same position.

## **1.1 Hardware Summary**

| **Component** | **Role** |
| --- | --- |
| ESP32-DevKitC-32UE | Main MCU + BLE 4.2 radio |
| LSM6DSOX #1 (ulnar-hand, below pinky) | Primary IMU — compression depth, wrist flexion/extension angle. |
| LSM6DSOX #2 (wrist-side) via TCA9548A | Secondary IMU — present for redundancy and dropout detection. In the current firmware configuration, posture angles (wrist alignment, compression-axis deviation) are derived from the palm IMU (#1) only; the wrist IMU is NOT fused into the posture estimate because in bench testing it added noise without improving accuracy. The hardware path is retained so wrist-IMU fusion can be re-enabled later without a board change. |
| FlexiForce A401 + MCP6002 op-amp | Compression force sensor (calibrated, Newtons). Gating signal for depth calculation and recoil/leaning detection. |
| MAX30102 (fingertip) | Patient HR, SpO2, raw PPG waveform, perfusion index. Active only during pulse check windows. |
| MAX30102 (wrist) | Rescuer HR, SpO2, RMSSD, perfusion index. Streamed continuously; displayed when signal quality ≥ 40. |
| MAX30205 | Patient skin temperature. Sampled every 5 seconds. |
| GXHT30 | Rescuer wrist SKIN temperature + relative humidity (skin contact on wrist — NOT an ambient/room air sensor). Sampled every 5 seconds. |
| DFPlayer Mini + SD card | Audio feedback — pre-recorded MP3 prompts. ESP32 controls via UART. |
| Vibration motor | Haptic feedback. Driven directly by ESP32 GPIO. |
| NeoPixel LED strip | Visual feedback — depth bar, rate metronome, mode indicator, alerts. |
| Physical button | Single press: SESSION_START / SESSION_END. Hold 2 s: cycle mode. Double press: cycle scenario (adult/pediatric). |
| ESP32 internal flash (LittleFS) | Local session storage when BLE is not connected. ≥ 512 KB partition. Holds up to 20 sessions. |

# **2. BLE Architecture**

## **2.1 Two-Characteristic Design**

The BLE GATT service exposes exactly two characteristics. This design separates high-frequency live data from low-frequency event data, prevents MTU fragmentation on the live stream, and keeps feedback latency below 20 ms.

| **Characteristic** | **UUID** | **Type** | **Rate** | **Purpose** |
| --- | --- | --- | --- | --- |
| LIVE_STREAM | 19b10001-e8f2-537e-4f6c-d104768a1214 | Notify | 10 Hz | All live sensor data — depth, rate, force, posture, vitals |
| EVENT_CHANNEL | 19b10002-e8f2-537e-4f6c-d104768a1214 | Notify + Write | On event | Session lifecycle, commands, offline sync |

## **2.2 Connection Requirements**

- App must negotiate MTU 247 on connect: device.requestMtu(247)

- Subscribe to LIVE_STREAM notifications immediately after MTU negotiation

- Subscribe to EVENT_CHANNEL notifications; also enable write-without-response

- LIVE_STREAM packet: 108 bytes fixed. EVENT_CHANNEL packet: 96 bytes fixed. All unused bytes = 0x00

- On connect, check for PENDING_LOCAL_DATA (0x09) event from glove before starting any session

**NOTE: ***LIVE_STREAM is 108 bytes at 10 Hz = 1,080 bytes/s. EVENT_CHANNEL is 96 bytes, on-event. Both fit within MTU 247. Well within BLE 4.2 capacity.*

# **3. LIVE_STREAM Packet (108 bytes, 10 Hz)**

Sent continuously at 10 Hz whenever the glove is on and BLE is connected. All multi-byte values are little-endian. The packet is divided into logical groups below.

| **Bytes** | **Type** | **Field** | **Unit/Range** | **Description** |
| --- | --- | --- | --- | --- |
| ── CORE COMPRESSION (bytes 0–23) |  |  |  |  |
| 0–3 | float32 | depth | cm (0.0–15.0) | Instantaneous hand displacement from calibrated resting position. Rises on downstroke, falls on upstroke. Primary source for live depth bar animation. |
| 4–7 | float32 | frequency | BPM (0–250) | 5-compression rolling-average rate in BPM. Used for the rate arrow/gauge. Smoother than instantaneous rate. Zero if fewer than 2 compressions recorded. |
| 8–11 | float32 | force | N (0–1000) | FlexiForce A401 calibrated force. Continuous — zero between compressions. Used internally for recoil detection, leaning detection, and over-force flagging. NOT displayed as a raw number in the UI. |
| 12–15 | float32 | instantaneousRate | BPM (0–250) | Rate computed from the interval between the last two compressions only. Used for per-compression grade calculation. More reactive than frequency field. |
| 16–19 | int32 | compressionCount | count (0–999999) | Running total of compressions since SESSION_START. |
| 20–23 | int32 | compressionInCycle | 0–30 | Position within the current 30:2 compression cycle. Resets to 0 after each VENTILATION_WINDOW. Drives the cycle progress indicator in the app. |
| ── POSTURE & ALIGNMENT (bytes 24–35) |  |  |  |  |
| 24–27 | float32 | wristAlignmentAngle | degrees (0–90) | Absolute palm-IMU pitch from the palm complementary filter. Palm IMU only; the wrist IMU is not fused. Target: < WRIST_ALIGN_WARN_DEG (30°). This is the only term of postureOk. |
| 28–31 | float32 | wristFlexionAngle | degrees (−45–45) | Palm pitch minus wrist-IMU pitch. 0 when the wrist IMU has dropped out. Display guide ±10°. Not part of postureOk and not scored. Thesis-novel metric. |
| 32–35 | float32 | compressionAxisDeviation | degrees (0–90) | Absolute palm-IMU roll from the palm complementary filter. Palm IMU only; the wrist IMU is not fused. Used by app to compute effectiveDepth = depth × cos(angle). Thesis-novel metric. |
| ── FATIGUE & DEPTH TREND (bytes 36–47) |  |  |  |  |
| 36–39 | float32 | depthTrend | cm (0.0–15.0) | 5-compression rolling average of peak depth. Streamed continuously. App uses this to render the fatigue trend line on the depth graph and to drive the FATIGUE warning badge without waiting for SESSION_END. |
| 40 | uint8 | recoilAchieved | 0 or 1 | 1 = full chest recoil on last compression: depth returned to < 0.5 cm AND force dropped below 5 N before next compression began. |
| 41 | uint8 | leaningDetected | 0 or 1 | 1 = rescuer is leaning on chest between compressions. Triggered when force between compressions remains above 5 N for > 200 ms without a new downstroke starting. |
| 42 | uint8 | overForceFlag | 0 or 1 | 1 = last compression exceeded 600 N (rib fracture risk threshold). Triggers immediate audio + haptic warning. |
| 43 | uint8 | postureOk | 0 or 1 | 1 = wristAlignmentAngle < WRIST_ALIGN_WARN_DEG (30°). Alignment only; flexion is not a term. Counted into SESSION_END correctPosture. |
| 44–47 | uint32 | ventilationCount | count (0–9999) | Running total of ventilation windows completed since SESSION_START. |
| ── FATIGUE FLAGS (bytes 48–55) |  |  |  |  |
| 48 | uint8 | fatigueFlag | 0 or 1 | One-shot latch. 1 = the 5-comp rolling average depth has declined by at least FATIGUE_DECLINE_THRESHOLD_MM (10 mm) from the average of the session's first 5 compressions. Elevated rescuer HR (with signal quality ≥ 40) lowers the threshold. Triggers FATIGUE_ALERT event once per session. |
| 49 | uint8 | rescuerFatigueScore | 0–100 | Depth-decline fatigue proxy: (firstFiveCompressionAvgDepthMM − currentDepthTrendMM) / FATIGUE_DECLINE_THRESHOLD_MM × 100, clamped 0–100. Elevated rescuer HR lowers the trigger threshold but is NOT a term in the score. RMSSD is streamed separately (byte 81) and is NOT an input to this score. 0 = no decline detected, 100 = severe decline. Stored in RescuerVitalSnapshot. |
| 50 | uint8 | imuCalibrated | 0 or 1 | 1 = palm complementary filter initialised AND at least GRAV_MIN_CYCLES_PALM (3) gravity cycles counted. The cycle count is not reset per session, so after the first 3 compressions since power-on this stays 1, dropping to 0 only briefly while the filter re-initialises at session start. App shows a calibrating indicator when 0. |
| 51 | uint8 | wristDropped | 0 or 1 | 1 = wrist-side IMU (LSM6DSOX #2) latched as dropped after WRIST_DROPOUT_LIMIT (3) consecutive strokes with zero wrist depth once its gravity baseline is established. Cleared on session reset. App shows a sensor warning when 1. |
| 52–55 | float32 | residualLoadDepthCm | cm | Residual load between compressions, expressed as a depth: the inter-compression force run back through the force→depth model. NOT an IMU-measured depth and NOT the recoil residual used for recoilAchieved. Non-zero while leaning, so the app can show leaning on the depth graph. |
| ── PATIENT VITALS (bytes 56–71) — sent only while pulseCheckActive = 1 or diagnostics are active; all six fields are 0 otherwise |  |  |  |  |
| 56–59 | float32 | heartRatePatient | BPM (0–300) | Patient HR from fingertip MAX30102. Non-zero only during pulse check windows (pulseCheckActive = 1). Zero at all other times. |
| 60–63 | float32 | spO2Patient | % (0–100) | Patient SpO2 from fingertip MAX30102. Non-zero only during pulse check window. 0.0 if no signal. |
| 64–67 | float32 | ppgRaw | amplitude (0–1) | Normalised raw PPG waveform amplitude from fingertip MAX30102. Streams continuously during pulse check window to drive the live waveform animation in the app. Zero outside pulse check. |
| 68 | uint8 | ppgSignalQuality | 0–100 | Signal quality for patient MAX30102 readings. App greys out waveform if below 40. Only meaningful during pulse check window. |
| 69 | uint8 | perfusionIndex | 0–100 | Perfusion index from fingertip MAX30102 (pulsatile/non-pulsatile ratio × 100). Higher values during CPR suggest effective circulation. Only valid during pulse check window. |
| 70–71 | uint16 | patientTemperature | °C × 100 (uint16) | Patient skin temperature from MAX30205. Encoded as integer × 100 (e.g. 3650 = 36.50°C). Gated on patient-sensor contact. Zero outside a pulse-check window, so the app never shows a stale frozen value. The last value captured during a pulse check persists only in SESSION_END bytes 66–69. App divides by 100.0 to recover float. |
| ── RESCUER VITALS (bytes 72–83) |  |  |  |  |
| 72–75 | float32 | heartRateUser | BPM (0–250) | Rescuer HR from wrist MAX30102. Streamed continuously. App displays value only when rescuerSignalQuality ≥ 40. |
| 76–79 | float32 | spO2User | % (0–100) | Rescuer SpO2 from wrist MAX30102. Same continuous streaming + quality-gated display rule as heartRateUser. |
| 80 | uint8 | rescuerSignalQuality | 0–100 | Signal quality for wrist MAX30102 readings. App shows rescuer HR and SpO2 only when this value ≥ 40. During compressions expect 0–30 typically. |
| 81 | uint8 | rescuerRMSSD | ms (0–200) | HRV RMSSD clamped to uint8 (0–200 ms). Within-session relative fatigue indicator. Not an absolute clinical value due to wrist PPG noise floor. Stored in RescuerVitalSnapshot. |
| 82–83 | uint16 | rescuerTemperature | °C × 100 (uint16) | Rescuer wrist SKIN temperature from GXHT30 (sensor has skin contact on the wrist). This is NOT ambient/room air temperature — there is no ambient air sensor on the glove. Same uint16 fixed-point encoding as patientTemperature. Updated every 5 seconds. |
| 84 | uint8 | rescuerPI | 0–100 | Rescuer perfusion index from wrist MAX30102. Declining PI during a session indicates vasoconstriction or physical fatigue. Stored in RescuerVitalSnapshot. |
| 85 | uint8 | rescuerHumidity | % (0–100) | Relative humidity at the wrist from GXHT30, clamped to 0–100. Sampled with the same 5-second cadence as rescuerTemperature. Stored in RescuerVitalSnapshot. |
| 86 | uint8 | inVentilationWindow | 0 or 1 | 1 = a 30:2 ventilation window is currently open (between VENTILATION_WINDOW and its close). |
| 87 | uint8 | reserved | 0x00 | Reserved. Always 0x00. |
| ── SESSION STATE (bytes 88–93) |  |  |  |  |
| 88 | uint8 | sessionActive | 0 or 1 | 1 = session is running. 0 = idle or ended. |
| 89 | uint8 | pulseCheckActive | 0 or 1 | 1 = glove is currently inside a pulse check window. ppgRaw, heartRatePatient, spO2Patient, ppgSignalQuality, perfusionIndex fields are valid. |
| 90 | uint8 | currentMode | 0 / 1 / 2 | 0 = Emergency, 1 = Training, 2 = Training-No-Feedback. |
| 91 | uint8 | feedbackMask | bitmask | Per-channel feedback state. Bit 0 = audio, bit 1 = haptic, bit 2 = visual (NeoPixel). Bits 3–7 = 0. 0x07 = all on, 0x00 = all suppressed (Training-No-Feedback mode). Decode bit by bit, never as a 0/1 boolean. |
| 92 | uint8 | batteryPercentage | 0–100 | Estimated battery charge from ESP32 ADC voltage reading on battery rail. |
| 93 | uint8 | isCharging | 0 or 1 | 1 = USB charging detected. |
| ── COMPRESSION TIMESTAMPS (bytes 94–101) |  |  |  |  |
| 94–97 | uint32 | peakTimestampMs | ms (0–4294967295) | Milliseconds since SESSION_START at which the most recent compression peak was locked. Used by the app to place each CompressionEvent precisely on the time axis under packet loss. 0 until the first peak. |
| 98–101 | uint32 | valleyTimestampMs | ms (0–4294967295) | Milliseconds since SESSION_START at which the most recent valley (full release) was confirmed. With peakTimestampMs this gives the app the downstroke interval per compression. 0 until the first valley. |
| ── LAST COMPRESSION DEPTH (bytes 102–107) |  |  |  |  |
| 102–105 | float32 | lastPeakDepthCm | cm | Depth of the last completed compression as chosen by the confidence-based depth selector. This is the graded per-compression depth, distinct from the live animation value at bytes 0–3. |
| 106 | uint8 | lastPeakConfidence | 0–100 | Selector confidence in lastPeakDepthCm × 100. |
| 107 | uint8 | lastPeakDepthSource | enum 0–7 | Which selector path produced lastPeakDepthCm: 0 HIGH_CONF, 1 IMU_PREFERRED, 2 FORCE_PREFERRED, 3 IMU_ONLY, 4 FORCE_ONLY, 5 UNCERTAIN, 6 CALIBRATING, 7 INVALID. |

**NOTE: ***Force field (bytes 8–11) is present in every packet for internal use but must NOT be displayed as a raw Newton value in the app UI. Force is patient-relative and not clinically comparable between patients.*

**NOTE: ***Rescuer vitals (bytes 72–83) stream continuously. The app should display them only when rescuerSignalQuality ≥ 40. During active compressions, expect quality of 0–30 due to motion artefact. The app should grey out these fields with a **"**weak signal**"** label rather than hiding them.*

**NOTE: ***Temperature encoding: both patientTemperature (bytes 70–71) and rescuerTemperature (bytes 82–83) are sent as uint16 with value = celsius × 100. Example: 36.50°C → send 3650 as little-endian uint16. App divides by 100.0. This avoids float alignment issues in the 2-byte slots.*

# **4. EVENT_CHANNEL Packets (96 bytes, on-event)**

Byte 0 of every frame is the packetType discriminator. The app writes commands to EVENT_CHANNEL using the same 96-byte frame structure. Unused bytes are always 0x00.

## **4.1 Packet Type Reference**

| **Byte 0** | **Name** | **Direction** | **Sent When** |
| --- | --- | --- | --- |
| 0x01 | SESSION_START | Glove → App | Physical button pressed (single press while idle). Clears all session counters. The firmware also accepts 0xF3 START, but the app does not send it (see 0xF3 below). |
| 0x02 | SESSION_END | Glove → App | Button pressed during active session, or SESSION_INACTIVITY_TIMEOUT_MS (120 s) since the last compression. The timeout is suspended while a pulse-check or ventilation window is open. The firmware also accepts 0xF4 STOP, but the app does not send it (see 0xF4 below). |
| 0x03 | VENTILATION_WINDOW | Glove → App | Exactly at the 30th compression in each cycle. Glove cues audio + haptic. App shows BREATHE overlay. |
| 0x04 | PULSE_CHECK_START | Glove → App | Emergency mode only. Passive gate, no timer and no prompt: opens when the rescuer has paused compressions and the patient (fingertip) sensor has held contact for PULSE_GATE_CONTACT_DEBOUNCE_MS (500 ms). One check per carotid palpation: the gate re-arms only after contact is lost. Glove streams patient PPG while the window is open. |
| 0x05 | PULSE_CHECK_RESULT | Glove → App | When the pulse-check window closes: WINDOW_RESUME_COMP_COUNT (2) compressions after a real pause, a non-compliant dismiss (5 compressions with no pause), or the WINDOW_MAX_BACKSTOP_MS (100 s) backstop. Carries classification, BPM, confidence, detector counts, and the self-detection reference source. |
| 0x06 | MODE_CHANGE | Glove → App | Physical button held 2 s cycles mode. Also sent in response to app 0xF1 MODE_SET command. |
| 0x07 | TWO_MIN_ALERT | Glove → App | Every 2 minutes of active session time. Triggers rescuer-switch banner in app + haptic + audio on glove. Fires in both Emergency and Training modes. |
| 0x08 | FATIGUE_ALERT | Glove → App | When fatigueFlag first becomes 1 (5-comp rolling avg declines ≥ 10 mm from the first-5-compression average, see LIVE_STREAM byte 48). Fires once per session maximum. |
| 0x09 | PENDING_LOCAL_DATA | Glove → App | Sent on BLE connection if glove has locally stored sessions. byte[1] = number of pending sessions (0–255). |
| 0x0A | LOCAL_SESSION_CHUNK | Glove → App | Data chunk for a locally stored session being transmitted after app sends 0xF5 REQUEST_SESSION. |
| 0x0B | SELFTEST_RESULT | Glove → App | Sent after glove completes self-test: on 0xFC RUN_SELFTEST and after 0xF7 CALIBRATE. The automatic run 1.5 s after BLE connect is currently disabled in firmware (runSelftest() commented out, "TEMP: disabled while debugging TCA"). If 0xFC or 0xF7 arrives during a session, pulse check, or ventilation window, the glove skips the test and replies at once with every reason code set to NOT_TESTED (0xFF). Carries pass/warn/critical bitmasks, battery %, I2C scan, WHO_AM_I values, and per-sensor reason codes. |
| 0x0C | SCENARIO_CHANGE | Glove → App | Glove button double-press cycles scenario (adult/pediatric). Also sent in response to app 0xFD SET_SCENARIO command. |
| 0x0D | DIAG_FRAME | Glove → App | Engineering telemetry. Queued at 4 Hz while the app's glove diagnostics sheet is open (diagActive) and at no other time. Carries raw sensor values, I2C scan results, and firmware build provenance. Not part of any session record and never written to the backend. |
| 0xF1 | APP → MODE_SET | App → Glove | App sets mode: byte[1] = 0x00 Emergency / 0x01 Training / 0x02 Training-No-Feedback. |
| 0xF2 | APP → FEEDBACK_SET | App → Glove | App toggles feedback: byte[1] = 0x01 on / 0x00 off. Suppresses vibration, audio, NeoPixels. |
| 0xF3 | APP → START | App → Glove | **Reserved — not implemented app-side.** Defined here for completeness. The constant exists in the app but is commented out, and the app never writes this command; sessions are started by the physical button only. |
| 0xF4 | APP → STOP | App → Glove | **Reserved — not implemented app-side.** As 0xF3; sessions are ended by the physical button only. |
| 0xF5 | APP → REQUEST_SESSION | App → Glove | App requests a locally stored session. byte[1] = session index (0-based). |
| 0xF6 | APP → CONFIRM_RECEIVED | App → Glove | App confirms a local session was fully received and saved. byte[1] = session index. Glove deletes that session from flash. |
| 0xF7 | APP → CALIBRATE | App → Glove | Idle only. Glove re-runs the force-sensor baseline until it converges (2 s timeout; the glove must be held still), then runs the self-test and replies with SELFTEST_RESULT (0x0B). Refused during a session, pulse check, or ventilation window (NOT_TESTED reply, see 0x0B). Never sends SESSION_START. |
| 0xF8 | APP → SET_TARGET_DEPTH | App → Glove | App overrides depth target range. byte[1] = min cm × 10, byte[2] = max cm × 10 (e.g. 50, 60 for standard adult 5–6 cm; 40, 50 for pediatric). |
| 0xF9 | APP → SET_TARGET_RATE | App → Glove | App overrides rate target range. byte[1] = min BPM, byte[2] = max BPM. |
| 0xFA | APP → SYNC_TIME | App → Glove | App sends current Unix timestamp for RTC sync. bytes[1–8] = uint64 ms since epoch (little-endian). |
| 0xFB | APP → SET_VENTILATION | App → Glove | App sets compression:ventilation ratio. byte[1] = compressions per cycle (default 30). byte[2] = ventilations expected (default 2). |
| 0xFC | APP → RUN_SELFTEST | App → Glove | App triggers glove self-test. Glove responds with SELFTEST_RESULT (0x0B). |
| 0xFD | APP → SET_SCENARIO | App → Glove | App sets scenario. byte[1] = 0x00 standard adult / 0x01 pediatric. Glove responds with SCENARIO_CHANGE (0x0C) to confirm. |
| 0xFE | APP → SET_FEEDBACK_CH | App → Glove | Per-channel feedback. byte[1] = bitmask: bit 0 audio, bit 1 haptic, bit 2 visual. Reflected in LIVE_STREAM byte 91. |
| 0xFF | APP → SET_VOLUME | App → Glove | byte[1] = audio volume 0–30. Optional byte[2] = vibration motor intensity 0–100. |
| 0xEB | APP → SET_LED_BRIGHTNESS | App → Glove | byte[1] = NeoPixel master brightness 0–255 (0 = LEDs off). |
| 0xED | APP → DIAG_START | App → Glove | Enter diagnostic mode (diagActive). Glove reads both IMU WHO_AM_I registers and starts queuing DIAG_FRAME (0x0D) at 4 Hz. |
| 0xEC | APP → DIAG_STOP | App → Glove | Exit diagnostic mode. DIAG_FRAME stops. |
| 0xEE | APP → DIAG_ACTION | App → Glove | One-shot test action, byte[1] = action: 0x01 play audio (optional byte[2] = track), 0x02 fire motor, 0x03 LED test, 0x04 I2C scan, 0x05 set volume, 0x06 set brightness. Acknowledged in DIAG_FRAME byte 6. |

## **4.2 SESSION_START (0x01)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x01 |
| 1 | mode | 0 = Emergency │ 1 = Training │ 2 = Training-No-Feedback |
| 2 | scenario | 0 = standard adult │ 1 = pediatric |
| 3–95 | reserved | 0x00 |

## **4.3 SESSION_END (0x02) — Full Session Summary**

The authoritative glove-side summary. averageDepth, averageFrequency, handsOnRatio, noFlowTime, and grade are all computed client-side by the app from the accumulated compressionEvents[] list for accuracy (glove-side averaging is unreliable under packet loss).

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType (uint8) | 0x02 |
| 1 | mode (uint8) | 0 = Emergency, 1 = Training, 2 = Training-No-Feedback |
| 2–5 | totalCompressions (uint32) | Total compressions this session |
| 6–9 | correctDepth (uint32) | Compressions with peak depth within target range (5–6 cm adult, 4–5 cm pediatric) |
| 10–13 | correctFrequency (uint32) | Compressions with instantaneous rate within 100–120 BPM |
| 14–17 | correctRecoil (uint32) | Compressions with full recoil (depth < 0.5 cm AND force < 5 N before next press) |
| 18–21 | depthRateCombo (uint32) | Compressions correct on BOTH depth AND rate simultaneously |
| 22–25 | correctPosture (uint32) | Compressions where postureOk flag was 1 |
| 26–29 | leaningCount (uint32) | Total compressions where leaningDetected = 1 |
| 30–33 | overForceCount (uint32) | Compressions exceeding 600 N (rib fracture risk) |
| 34–37 | tooDeepCount (uint32) | Compressions with peak depth > 6 cm (adult) or > 5 cm (pediatric) |
| 38–41 | totalVentilations (uint32) | Total ventilation windows triggered (30:2 cycles completed) |
| 42–45 | correctVentilations (uint32) | Ventilation windows where the rescuer paused for at least WINDOW_PAUSE_COMPLIANT_MS (3 s) with no compression, counted after a VENTILATION_GRACE_MS (2.5 s) grace period, and was not dismissed as non-compliant |
| 46–49 | pulseChecksPrompted (uint32) | Emergency mode only. Number of pulse-check windows opened by the passive contact-plus-pause gate. The glove never prompts the rescuer; the name is historical. |
| 50–53 | pulseChecksComplied (uint32) | Emergency mode only. Pulse-check windows that closed with patient signal quality ≥ 40, i.e. a classifiable signal. |
| 54–57 | fatigueOnsetIndex (uint32) | Compression index when fatigue first detected. 0 = no fatigue this session. |
| 58–61 | peakDepth (float32) | Maximum single compression depth this session in cm |
| 62–65 | compressionDepthSD (float32) | Standard deviation of per-compression peak depths (cm). App-side depthSD uses this if non-zero. |
| 66–69 | patientTemperatureLastPulseCheck (float32) | Last MAX30205 carotid skin temperature captured with the fingertip on the patient during a pulse check window (°C). NOT a continuous patient temperature — only updated inside pulse-check windows. 0.0 = no valid pulse-check reading. |
| 70–73 | reserved | 0x00. (Rescuer wrist temperature start/end are carried at bytes 82–89, not here.) |
| 74–77 | rescuerHRLastPause (float32) | Rescuer HR at last ventilation or pulse check pause (wrist MAX30102). |
| 78–81 | rescuerSpO2LastPause (float32) | Rescuer SpO2 at last pause (%). |
| 82–85 | rescuerWristTempStart (float32) | Rescuer wrist SKIN temperature at SESSION_START from GXHT30 (°C). NOT ambient air — the GXHT30 has skin contact on the wrist. 0.0 if unavailable. |
| 86–89 | rescuerWristTempEnd (float32) | Rescuer wrist SKIN temperature at SESSION_END from GXHT30 (°C). 0.0 if unavailable. |
| 90 | pulseDetected (uint8) | 1 = pulse detected at last pulse check. Emergency mode only. |
| 91 | noFlowIntervals (uint8) | Glove-side count of unplanned pauses > 2 s, saturating at 255. ADVISORY ONLY — the app recomputes noFlowIntervals from the compression event list and that app value is authoritative (glove-side counting is unreliable under packet loss). This byte is retained for cross-checking, not for display. |
| 92 | rescuerSwapCount (uint8) | Number of TWO_MIN_ALERT events fired this session (proxy for rescuer swap reminders). |
| 93–94 | timeToFirstCompressionMs (uint16) | Milliseconds from SESSION_START to the first compression peak, little-endian. Saturates at 65535. If 0 or 65535, the app falls back to the first CompressionEvent timestamp. |
| 95 | wristDroppedDuringSession (uint8) | 1 = the wrist IMU dropout latch (LIVE_STREAM byte 51) fired at any point in this session. |

**NOTE: ***SESSION_END is 96 bytes. The temperature fields at bytes 66–69 and 82–89 are full float32 (4 bytes each) — not fixed-point. Bytes 70–73 are reserved. Only LIVE_STREAM temperature fields use the uint16 fixed-point encoding.*

## **4.4 VENTILATION_WINDOW (0x03)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x03 |
| 1–2 | cycleNumber (uint16) | Which 30:2 cycle this is. Starts at 1. |
| 3 | ventilationsExpected (uint8) | Always 2 for standard adult. May differ for pediatric if SET_VENTILATION was used. |
| 4–95 | reserved | 0x00 |

## **4.5 PULSE_CHECK_START (0x04)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x04 |
| 1–2 | intervalNumber (uint16) | Pulse-check number within this session, starting at 1. Counts windows opened, not time intervals; the name is historical. |
| 3–6 | sessionElapsedMs (uint32) | Milliseconds since SESSION_START when pulse check triggered. |
| 7–95 | reserved | 0x00 |

## **4.6 PULSE_CHECK_RESULT (0x05)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x05 |
| 1 | classification (uint8) | 0 = ABSENT (no pulse) │ 1 = UNCERTAIN (weak signal, verify manually) │ 2 = PRESENT (pulse detected). App uses 2 as "detected". Low signal quality yields UNCERTAIN, never ABSENT. Self-detection guard: PRESENT is downgraded to UNCERTAIN when the patient rate agrees with the rescuer's own wrist HR within PULSE_SELF_DETECT_BPM_TOL (10 BPM), since the fingertip may be reading the rescuer's pulse. The guard only downgrades. |
| 2–5 | detectedBPM (float32) | BPM. 0.0 if classification = ABSENT. |
| 6 | confidencePct (uint8) | 0–100. This is the patient PPG signal-quality value (ppgSignalQuality) — "confidence" and "signal quality" refer to the same single quantity here, not two independent metrics. App shows result only when ≥ 40. |
| 7 | detectorACount (uint8) | Raw Detector A peak count (all peaks, no refractory gate). Evidence count for thesis analysis. |
| 8 | detectorBCount (uint8) | Confirmed Detector B beat count (physiologically constrained rate). |
| 9 | refSource (uint8) | Which rescuer-HR reference the self-detection guard used: 0 = NONE (no reference passed signal quality ≥ 40, guard did not run), 1 = LIVE (rescuer reading at window close), 2 = PAUSED (rescuer reading captured at window open). Data capture only. It has no effect on gating or classification beyond the guard described at byte 1. |
| 10–95 | reserved | 0x00 |

## **4.7 MODE_CHANGE (0x06)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x06 |
| 1 | newMode (uint8) | 0 = Emergency │ 1 = Training │ 2 = Training-No-Feedback |
| 2 | triggeredBy (uint8) | 0 = glove button hold │ 1 = app command 0xF1 |
| 3–95 | reserved | 0x00 |

## **4.8 TWO_MIN_ALERT (0x07)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x07 |
| 1 | alertNumber (uint8) | How many times this alert has fired this session (1 = first alert at 2 min, 2 = second at 4 min, etc.). |
| 2–95 | reserved | 0x00 |

## **4.9 FATIGUE_ALERT (0x08)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x08 |
| 1 | fatigueScore (uint8) | 0–100 depth-decline fatigue proxy at time of alert (see LIVE_STREAM byte 49 for the formula). Not a physiological composite. |
| 2–95 | reserved | 0x00 |

## **4.10 PENDING_LOCAL_DATA (0x09)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x09 |
| 1 | pendingCount (uint8) | Number of unsent sessions stored on glove flash (0–20). |
| 2–95 | reserved | 0x00 |

## **4.11 LOCAL_SESSION_CHUNK (0x0A)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x0A |
| 1 | sessionIndex (uint8) | Which stored session (0-based, 0–19). |
| 2 | chunkIndex (uint8) | 0-based index of this chunk. |
| 3 | totalChunks (uint8) | Total number of chunks for this session. |
| 4–95 | chunkData (uint8[92]) | 92 bytes of session binary data for this chunk. Last chunk may be partially filled; remaining bytes = 0x00. |

## **4.12 SELFTEST_RESULT (0x0B)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x0B |
| 1 | passMask (uint8) | Bitmask of sensors that passed self-test. Bit 0: IMU1, Bit 1: IMU2, Bit 2: force sensor, Bit 3: fingertip MAX30102, Bit 4: wrist MAX30102, Bit 5: MAX30205, Bit 6: GXHT30, Bit 7: DFPlayer. |
| 2 | warnMask (uint8) | Bitmask of sensors with warnings (present but degraded signal). |
| 3 | criticalMask (uint8) | Bitmask of sensors that failed or are absent. |
| 4 | batteryPct (uint8) | Battery percentage at time of self-test (0–100). |
| 5 | i2cScanMask (uint8) | I2C devices found, same bit layout as DIAG_FRAME byte 5. |
| 6 | palmWhoAmI (uint8) | Palm LSM6DSOX WHO_AM_I. Expected 0x6C. |
| 7 | wristWhoAmI (uint8) | Wrist LSM6DSOX WHO_AM_I. Expected 0x6C. |
| 8–15 | reasonCodes (uint8[8]) | One reason code per sensor, same bit order as passMask (byte 8 = bit 0 … byte 15 = bit 7). 0x00 OK, 0x01 no I2C ACK, 0x02 TCA9548A failure, 0x03 wrong chip ID, 0x04 implausible reading, 0x05 baseline never converged, 0x06 no DFPlayer UART reply, 0x07 I2C mutex timeout, 0xFF not tested. |
| 16–95 | reserved | 0x00 |

## **4.13 SCENARIO_CHANGE (0x0C)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x0C |
| 1 | scenario (uint8) | 0 = standard adult │ 1 = pediatric |
| 2 | triggeredBy (uint8) | 0 = glove button double-press │ 1 = app command 0xFD |
| 3–95 | reserved | 0x00 |

## **4.14 DIAG_FRAME (0x0D)**

Engineering telemetry for the glove diagnostics sheet. The glove queues this frame at 4 Hz (DIAG_FRAME_INTERVAL_MS = 250) only while diagnostics are active, and never during a normal session. DIAG_FRAME is not part of any session record, is not persisted to local storage, and is never written to the backend. It exists so that raw sensor behaviour and firmware build identity can be inspected on a connected device.

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0x0D |
| 1–2 | rawFsrAdc (int16 LE) | Raw ADC reading from the FlexiForce A401 conditioning circuit, before any calibration is applied. Used to detect a stuck-at-zero or stuck-at-maximum sensor. |
| 3 | palmWhoAmI (uint8) | WHO_AM_I register value read from the palm LSM6DSOX. Expected 0x6C. |
| 4 | wristWhoAmI (uint8) | WHO_AM_I register value read from the wrist LSM6DSOX. Expected 0x6C. |
| 5 | i2cScanResult (uint8) | Bitmask of I2C devices found on the TCA9548A multiplexer. Bit 0: palm LSM6DSOX (IMU). Bit 1: wrist LSM6DSOX (IMU). Bit 2: MAX30205 (patient temperature). Bit 3: GXHT30 (rescuer temperature/humidity). Bit 4: MAX30102 rescuer (wrist). Bit 5: MAX30102 patient (fingertip). Bits 6–7 reserved. |
| 6 | actionResult (uint8) | Last diagnostic event. 0x01–0x06 = acknowledgement of the matching 0xEE DIAG_ACTION code. 0x10 | n (0x10–0x1F) = a physical button event, n = button event type. 0x00 = nothing since DIAG_START. |
| 7–8 | palmAccelMag (int16 LE) | Palm IMU motion acceleration magnitude × 100, in milli-g. Divide by 100 in the app. |
| 9–10 | wristAccelMag (int16 LE) | Wrist IMU motion acceleration magnitude × 100, in milli-g. Divide by 100 in the app. |
| 11–12 | rescuerPpgFiltered (int16 LE) | Filtered AC component of the rescuer (wrist) MAX30102 PPG waveform, in raw sensor counts. Bench-observed range approximately ±300. |
| 13–16 | rescuerPpgDc (uint32 LE) | DC baseline of the rescuer PPG signal, in raw IR counts. Bench-observed up to approximately 138000, which overflows both int16 and uint16, hence uint32. The sensor has no sub-count precision, so an integer type is used rather than float32. A value at or near zero indicates the sensor is not seeing tissue. |
| 17 | buildFlags (uint8) | Compile-time configuration of the flashed firmware. Bit 0: STUDY_BUILD. Bit 1: BLE_DEBUG_SERIAL. Bit 2: DEPTH_PIPELINE_LOG. Bit 3: DEPTH_SELECTOR_LOG. Bit 4: FORCE_TEST_LOG. Bit 5: IMU_TEST_LOG. Bits 6–7 reserved. See the note below. |
| 18–21 | buildStamp (uint32 LE) | Compile date and time of the firmware, bit-packed rather than an epoch value. Bits 0–6: year minus 2000. Bits 7–10: month, 1–12. Bits 11–15: day, 1–31. Bits 16–20: hour, 0–23. Bits 21–26: minute, 0–59. Bits 27–31 reserved. Derived from the compiler's \_\_DATE\_\_ and \_\_TIME\_\_ macros. |
| 22–95 | reserved | 0x00 |

**NOTE: ***buildFlags and buildStamp exist to make the flashed build verifiable on the device. A compile-time guard in config.h refuses to build when STUDY_BUILD is 1 and any debug log flag is also 1, so bit 0 being set implies bits 1–5 are clear. The remaining bits are transmitted anyway so that the diagnostics sheet reports the observed configuration directly rather than inferring it from the guard, which would fail silently if the guard were ever edited or bypassed. Before each participant session, the build type and stamp shown in the diagnostics sheet should be checked against the build that was intended to be flashed.*

**NOTE: ***\_\_DATE\_\_ and \_\_TIME\_\_ are expanded when the translation unit containing the builder is compiled. Under an incremental build the stamp may therefore report when that file last changed rather than when the image was linked. A clean rebuild before flashing guarantees the stamp matches the flash.*

## **4.15 App→Glove Commands: SET_TARGET_DEPTH (0xF8) and SET_TARGET_RATE (0xF9)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0xF8 (depth) or 0xF9 (rate) |
| 1 | minValue (uint8) | For 0xF8: min depth cm × 10 (e.g. 50 = 5.0 cm). For 0xF9: min BPM (e.g. 100). |
| 2 | maxValue (uint8) | For 0xF8: max depth cm × 10 (e.g. 60 = 6.0 cm). For 0xF9: max BPM (e.g. 120). |
| 3–95 | reserved | 0x00 |

## **4.16 App→Glove: SYNC_TIME (0xFA)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0xFA |
| 1–8 | unixTimestampMs (uint64) | Current Unix timestamp in milliseconds (little-endian). Glove stores this for session timestamp accuracy in LittleFS. |
| 9–95 | reserved | 0x00 |

## **4.17 App→Glove: SET_VENTILATION (0xFB)**

| **Bytes** | **Field** | **Notes** |
| --- | --- | --- |
| 0 | packetType | 0xFB |
| 1 | compressionsPerCycle (uint8) | Compressions before ventilation window (default 30). |
| 2 | ventilationsExpected (uint8) | Ventilations expected per window (default 2). |
| 3–95 | reserved | 0x00 |

# **5. Session Lifecycle**

## **5.1 Normal CPR Flow**

| **Step** | **Trigger** | **Glove Action** | **App Action** |
| --- | --- | --- | --- |
| 1 | Button press or app 0xF3 | Sends SESSION_START (0x01). Clears all counters. | Starts client-side session timer. Clears compressionEvents[]. Records sessionStartTime. |
| 2 | Session start | Arms a complementary-filter reset that fires after ~300 ms of stillness (palm accel within 3% of 1 g), then fast-converges. No force trigger. imuCalibrated may read 0 briefly. | Shows calibrating indicator while imuCalibrated = 0. |
| 3 | First compression > threshold | LIVE_STREAM begins. compressionCount increments. | Depth bar animates. Rate gauge updates. Accumulates CompressionEvents. |
| 4 | 30th compression in cycle | Sends VENTILATION_WINDOW (0x03). Audio + haptic cue. Resets compressionInCycle to 0. | Shows BREATHE overlay with cycle number. Starts ventilation timer. The glove counts the window compliant if the rescuer pauses ≥ 3 s after a 2.5 s grace period. |
| 5 | Compressions resume after ventilation | Resumes normal LIVE_STREAM. | Hides BREATHE overlay. Logs VentilationEvent. Increments cycle counter. |
| 6 | Every 2 min of active CPR time | Sends TWO_MIN_ALERT (0x07). Haptic + audio prompt. | Shows non-blocking rescuer-switch banner for 10 s. Auto-dismisses. |
| 7 | Rescuer pauses and holds the fingertip sensor on the carotid for 500 ms (Emergency only, passive, never prompted) | Sends PULSE_CHECK_START (0x04). Streams patient PPG fields in LIVE_STREAM. | Shows a non-blocking pulse-check card in the Live CPR screen with the live PPG waveform from ppgRaw. Nothing behind it is blocked. |
| 8 | Window closes (2 compressions after a real pause, non-compliant dismiss, or 100 s backstop) | Sends PULSE_CHECK_RESULT (0x05). Stops patient PPG fields. | Card shows "check recorded". Classification, BPM and confidence are stored in the session record and shown on the results screen, never on the live card. |
| 9 | 120 s since the last compression, outside any pulse-check or ventilation window | Sends SESSION_END (0x02) automatically. | Triggers end flow. |
| 10 | Button press or app 0xF4 | Sends SESSION_END (0x02) with full summary. | Stops timer. Assembles SessionDetail. Triggers end flow. |

## **5.2 Session End Flow (App)**

- Stop client-side session timer.

- Assemble SessionDetail from LIVE_STREAM compression event list + SESSION_END summary packet.

- Compute: averageDepth, averageFrequency, averageEffectiveDepth, handsOnRatio, noFlowTime, rateVariability, consecutiveGoodPeak from compressions[].

- Calculate grade client-side using formula in Section 9. Emergency sessions always receive grade 0.

- Save to SharedPreferences immediately: key = session_local_<timestamp>, value = SessionDetail.toJson().

- If Emergency mode AND user not logged in: show AppDialogs.promptSaveSession() once. Dismissed = session stays local only. No second prompt.

- If Training mode: navigate to Session Results screen immediately, regardless of backend status.

- Attempt POST to /sessions/detail. If offline, queue for background sync. Show sync badge on results screen if not yet synced.

- If pulse was detected (Emergency mode): show recovery checklist before results screen.

## **5.3 Pulse Check — Training Mode**

Pulse check is SKIPPED entirely in Training mode. Manikins have no real pulse. TWO_MIN_ALERT (0x07) still fires every 2 minutes (rescuer-switch reminder) in both modes. PULSE_CHECK_START (0x04) is silently discarded by the app when currentMode = 1 or 2.

## **5.4 Training-No-Feedback Mode**

Mode 2 is a blind assessment mode. The glove suppresses all feedback channels (DFPlayer audio, vibration motor, NeoPixel LEDs) when feedbackEnabled = 0. The app continues to display all live metrics normally. Use case: test whether a trained rescuer can maintain quality without any real-time prompts.

# **6. Complete Metrics Reference**

| **Metric** | **Source** | **Channel** | **Notes** |
| --- | --- | --- | --- |
| Instantaneous depth (cm) | IMU fusion + FlexiForce | LIVE | Continuous 10 Hz — drives depth bar |
| Depth trend (5-comp avg, cm) | Firmware computed | LIVE | 5-comp rolling avg. Drives fatigue trend line on graph. |
| Average depth | App-computed | — | Mean of compression[].depth |
| Depth consistency % | App-computed | — | correctDepth / totalCompressions |
| Effective depth (angle-corrected) | App-computed | — | depth × cos(compressionAxisDeviation) |
| Too-deep count | Firmware computed | END | Compressions > 6 cm (adult) or > 5 cm (pediatric) |
| Compression depth SD (cm) | Firmware computed | END | Standard deviation of per-compression peak depths |
| Instantaneous rate (BPM) | Compression timestamps | LIVE | Per-compression, last 2 IBIs |
| Rolling average rate (BPM) | 5-comp average | LIVE | Drives rate arrow smoothly |
| Rate consistency % | App-computed | — | correctFrequency / totalCompressions |
| Time to first compression | App-computed | — | Session start → first compression |
| Rate variability | App-computed | — | Std deviation of inter-compression intervals (ms) |
| Instantaneous force (N) | FlexiForce A401 | LIVE | Internal use — not displayed as raw value |
| Over-force flag (> 600 N) | Firmware computed | LIVE | Per-compression boolean |
| Over-force count | Firmware computed | END | Total compressions exceeding 600 N |
| Recoil achieved (bool) | Depth + Force | LIVE | depth < 0.5 cm AND force < 5 N |
| Recoil consistency % | App-computed | — | correctRecoil / totalCompressions |
| Leaning detected (bool) | Force sensor | LIVE | Force > 5 N persists > 200 ms between compressions |
| Leaning count | Firmware computed | END | Total compressions with leaning |
| Wrist alignment angle (°) | Palm IMU (pitch) | LIVE | Absolute palm pitch. Target < 30°. |
| Wrist flexion angle (°) | Ulnar-side IMU | LIVE | Forward/back wrist bend under load. Thesis-novel. |
| Compression axis deviation (°) | Palm IMU (roll) | LIVE | Used to compute effective depth. Thesis-novel. |
| Posture OK flag | Firmware computed | LIVE | Alignment < 30°. Flexion is not a term. |
| Posture consistency % | App-computed | — | correctPosture / totalCompressions |
| Compression count | Firmware computed | LIVE | Running total |
| Compression in cycle (0–30) | Firmware computed | LIVE | Position in current 30:2 cycle |
| Hands-on ratio (CCF) | App-computed | — | Chest Compression Fraction = 1 − (noFlowTime / sessionDurationSecs), clamped 0–1. Derived FROM noFlowTime, so its accuracy depends entirely on the no-flow definition below. |
| No-flow time (s) | App-computed | — | Sum of every inter-compression gap > 2.0 s, PLUS the gap from session start to the first compression, PLUS the gap from the last compression to session end. INCLUDES planned ventilation and pulse-check pauses. |
| No-flow intervals | App-computed (glove value advisory) | — | Count of the > 2 s gaps that make up no-flow time. The app value (recomputed from the compression list) is authoritative; the glove SESSION_END byte 91 value is advisory cross-check only. |
| Unplanned pause time / count | App-computed | — | Subset of no-flow gaps that do NOT overlap a ventilation window or a pulse-check window. This is the clinically meaningful "rescuer stopped without reason" measure; display this pair (time with count), never mix it with total no-flow. |
| Ventilation count | Firmware computed | LIVE | Running total ventilation windows |
| Ventilation compliance % | App-computed | — | correctVentilations / totalVentilations |
| Depth + rate combo % | App-computed | — | Both correct simultaneously |
| Consecutive good streak | App-computed | — | Live counter of unbroken correct compressions |
| Fatigue flag | Firmware computed | LIVE | 5-comp rolling avg declines ≥ 10 mm from the first-5-compression average |
| Rescuer fatigue score (0–100) | Firmware computed | LIVE | Depth-decline proxy only: decline of 5-comp depth trend vs first-5 average. HR shifts the trigger threshold; RMSSD is NOT an input. |
| IMU calibrated flag | Firmware computed | LIVE | 0 until 3 gravity cycles since power-on, and briefly during the filter re-init at session start |
| Wrist dropped flag | Firmware computed | LIVE | Latched after 3 consecutive zero-depth wrist strokes. Cleared on session reset. |
| Patient HR (BPM) | Fingertip MAX30102 | LIVE | Valid during pulse check only |
| Patient SpO2 (%) | Fingertip MAX30102 | LIVE | Valid during pulse check only |
| PPG raw waveform | Fingertip MAX30102 | LIVE | Drives live waveform animation during pulse check |
| PPG signal quality (patient) | MAX30102 internal | LIVE/EVENT | 0–100 from PPG AC/DC ratio (qi × 20, clamped). App greys display if < 40. SAME value reported as "confidence" in PULSE_CHECK_RESULT — one quantity, two names. |
| Perfusion index (patient) | Fingertip MAX30102 | LIVE | 0–100. Derived from the SAME PPG AC/DC ratio as patient signal quality (pi = qi), so the two are linearly dependent by construction — not independent metrics. Rising PI suggests effective circulation. |
| Patient temperature (°C) | MAX30205 | LIVE/END | LIVE_STREAM bytes 70–71: contact-gated MAX30205 reading, uint16 fixed-point, zero outside a pulse-check window. SESSION_END bytes 66–69: last value captured during a pulse check (patientTemperatureLastPulseCheck), float32. |
| Pulse classification | Firmware computed | EVENT | 0=absent / 1=uncertain / 2=present. In PULSE_CHECK_RESULT. |
| Rescuer HR (BPM) | Wrist MAX30102 | LIVE | Continuous — shown when quality ≥ 40 |
| Rescuer SpO2 (%) | Wrist MAX30102 | LIVE | Continuous — shown when quality ≥ 40 |
| Rescuer RMSSD (ms) | Wrist MAX30102 | LIVE | HRV indicator — relative fatigue trend within session only |
| Rescuer perfusion index | Wrist MAX30102 | LIVE | 0–100. Derived from the SAME wrist PPG AC/DC ratio as rescuer signal quality, so the two are strongly correlated by construction. Declining PI = vasoconstriction / fatigue. |
| Rescuer signal quality | MAX30102 internal | LIVE | 0–100 composite (0.5 × PI-in-range + 0.3 × beat-count + 0.2 × SpO2-validity). Shares the AC/DC ratio input with rescuer PI. |
| Rescuer temperature (°C) | GXHT30 | LIVE/END | Wrist SKIN temperature (skin contact), NOT ambient air. LIVE_STREAM bytes 82–83 uint16 fixed-point; SESSION_END bytes 82–89 carry start/end as float32 (rescuerWristTempStart/End). |
| Rescuer humidity (%) | GXHT30 | LIVE | 0–100 relative humidity at the wrist. LIVE_STREAM byte 85. Stored per RescuerVitalSnapshot. |
| Fatigue onset index | Firmware computed | END | Compression index of first fatigue detection. 0 = none. |
| Battery percentage | ESP32 ADC | LIVE | 0–100 % |
| Charging status | ESP32 GPIO | LIVE | 0/1 |
| Rescuer swap count | Firmware computed | END | TWO_MIN_ALERT events fired this session |

# **7. Data Models**

## **7.1 CompressionEvent**

One instance per detected compression. Accumulated in real-time from LIVE_STREAM. Stored in SessionDetail.compressions[].

| **Field** | **Type** | **Description** |
| --- | --- | --- |
| timestampMs | int | Milliseconds from session start. X-axis for all graphs. |
| depth | double | Peak depth of this compression (cm) |
| instantaneousRate | double | Rate from last two IBIs (BPM). Used for per-compression grading. |
| frequency | double | 5-comp rolling avg rate (BPM). Used for smooth display. |
| force | double | Peak force of this compression (Newtons) — stored, not displayed raw |
| recoilAchieved | bool | True if depth < 0.5 cm AND force < 5 N before next compression |
| overForce | bool | True if force exceeded 600 N |
| postureOk | bool | Firmware flag: wristAlignmentAngle < 30°. Flexion is not a term. |
| leaningDetected | bool | True if inter-compression force stayed > 5 N for > 200 ms |
| wristAlignmentAngle | double | 3D compression vector deviation from vertical (degrees) |
| wristFlexionAngle | double | Wrist bend angle from ulnar IMU (degrees, ±45°). Thesis-novel. |
| compressionAxisDev | double | Axis deviation angle — used to compute effectiveDepth. Thesis-novel. |
| effectiveDepth | double | depth × cos(compressionAxisDev) — sternum-corrected depth (cm) |
| downstrokeTimeMs | int | Time from compression start to peak depth (ms). 0 if not available. |

## **7.2 VentilationEvent**

One instance per 30:2 cycle. Stored in SessionDetail.ventilations[].

| **Field** | **Type** | **Description** |
| --- | --- | --- |
| timestampMs | int | Session ms when ventilation window opened |
| cycleNumber | int | Which 30:2 cycle (starts at 1) |
| durationSec | double | The measured no-flow gap containing this prompt, computed by the app after the session from the compression timeline, capped at maxCompliantPauseSec (15 s). Not a firmware value. |
| compliant | bool | App-side: true when the uncapped measured gap is between minCompliantPauseSec (3 s) and maxCompliantPauseSec (15 s). The 10 s guideline target stays maxAcceptablePauseSec: a compliant 10–15 s pause is marked "over target", and time past 10 s is still reported as unplanned pause time. A pause past 15 s keeps durationSec = 15 and compliant = false, which is how the app marks it as overran. Drives ventilationCompliance. Independent of the glove's correctVentilations count (SESSION_END bytes 42–45). |

The app model has no breath-count field. The glove's stored ventilation array (§8.2) carries compressionsDuringWindow, and the offline parser does not read it.

## **7.3 PulseCheckEvent (Emergency mode only)**

One instance per pulse check window. Stored in SessionDetail.pulseChecks[].

| **Field** | **Type** | **Description** |
| --- | --- | --- |
| timestampMs | int | Session ms when pulse check window started |
| intervalNumber | int | Pulse-check number within the session, starting at 1 (name is historical) |
| classification | int | 0 = ABSENT │ 1 = UNCERTAIN │ 2 = PRESENT |
| detectorACount | int | Raw Detector A peak count (all peaks, no refractory gate) |
| detectorBCount | int | Confirmed Detector B beat count (physiological constraint) |
| detectedBpm | double | BPM — 0.0 if not detected |
| confidence | int | 0–100. Same value as the patient PPG signal quality (ppgSignalQuality). The field is named "confidence" for historical reasons; it is not a separate metric. |
| perfusionIndex | int | 0–100 perfusion index at time of check |
| userDecision | String? | "continue" or "stop_cpr" — set by the user's button tap |

## **7.4 RescuerVitalSnapshot**

Sampled from LIVE_STREAM every 5 seconds while a session is active, REGARDLESS of signal quality. signalQuality is recorded on each row so the display layer can grey-out or hide low-quality entries while keeping the post-session vitals graph continuous and showing where sensor contact was lost. Stored in SessionDetail.rescuerVitals[].

| **Field** | **Type** | **Description** |
| --- | --- | --- |
| timestampMs | int | Session ms of this snapshot |
| heartRate | double | BPM — wrist MAX30102 |
| spO2 | double | % — wrist MAX30102 |
| temperature | double | °C — wrist SKIN temperature from GXHT30 (decoded from uint16 fixed-point). Not ambient air. |
| humidity | double | % — relative humidity at the wrist from GXHT30 (0–100), sampled with temperature. |
| signalQuality | int | 0–100 at time of snapshot. Low values indicate the row should be displayed greyed-out, not discarded. |
| rmssd | int | RMSSD ms (0–200). Within-session relative fatigue indicator only. |
| rescuerPi | int | Rescuer perfusion index 0–100. Declining = vasoconstriction. |
| fatigueScore | int | Depth-decline fatigue proxy 0–100 (see LIVE_STREAM byte 49). Not a physiological composite; RMSSD is not an input. |
| pauseType | String | "active", "ventilation", or "pulse_check" — context when sampled |

## **7.5 SessionDetail — Complete Model**

The full session record. Built by the app on session end. Saved locally to SharedPreferences and POSTed to the backend.

| **Field** | **Type / Source** | **Description** |
| --- | --- | --- |
| id | int? / backend | Assigned on backend save |
| sessionStart | DateTime / app | When SESSION_START received |
| sessionEnd | DateTime? / app | When SESSION_END received |
| sessionDuration | int / app | Seconds — client-side timer |
| mode | String / glove | "emergency" │ "training" │ "training_no_feedback" |
| scenario | String / app | "standard_adult" │ "pediatric" |
| compressionCount | int / glove | From SESSION_END totalCompressions |
| correctDepth | int / glove | From SESSION_END |
| correctFrequency | int / glove | From SESSION_END |
| correctRecoil | int / glove | From SESSION_END |
| depthRateCombo | int / glove | From SESSION_END |
| correctPosture | int / glove | From SESSION_END |
| leaningCount | int / glove | From SESSION_END |
| overForceCount | int / glove | Compressions > 600 N |
| tooDeepCount | int / glove | Compressions > depth max |
| correctVentilations | int / glove | From SESSION_END |
| averageDepth | double / app | Mean of compression[].depth |
| averageFrequency | double / app | Mean of compression[].instantaneousRate |
| averageEffectiveDepth | double / app | Mean of compression[].effectiveDepth |
| peakDepth | double / glove | Maximum single compression depth (cm) |
| depthSD | double / glove+app | From SESSION_END compressionDepthSD if non-zero; else app-computed |
| depthConsistency | double / app | % compressions within target depth range |
| frequencyConsistency | double / app | % compressions within 100–120 BPM |
| handsOnRatio | double / app | Active compression time / total time (0–1) |
| noFlowTime | double / app | Total seconds of unplanned gaps > 2 s |
| noFlowIntervals | int / glove+app | Count of unplanned gaps. Glove from SESSION_END; app also computes. |
| rateVariability | double / app | Std deviation of inter-compression intervals (ms) |
| timeToFirstCompression | double / app | Seconds from SESSION_START to first compression |
| consecutiveGoodPeak | int / app | Peak unbroken streak of fully correct compressions |
| fatigueOnsetIndex | int / glove | Compression index of first fatigue. 0 = none. |
| rescuerSwapCount | int / glove | TWO_MIN_ALERT events fired this session |
| ventilationCount | int / glove | Total ventilation windows triggered |
| ventilationCompliance | double / app | % cycles with ≥ 1 detected breath attempt |
| pulseChecksPrompted | int / glove | Emergency only |
| pulseChecksComplied | int / glove | Emergency only |
| pulseDetectedFinal | bool / glove | Pulse at last check. Emergency only. |
| patientTemperature | double? / glove | Last MAX30205 reading (°C) |
| rescuerHRLastPause | double? / glove | Rescuer HR at last ventilation or pulse check pause |
| rescuerSpO2LastPause | double? / glove | Rescuer SpO2 at last pause (%) |
| rescuerWristTempStart | double? / glove | GXHT30 wrist skin temperature at SESSION_START (°C). Not ambient air. |
| rescuerWristTempEnd | double? / glove | GXHT30 wrist skin temperature at SESSION_END (°C). Not ambient air. |
| totalGrade | double / app | 0–100 calculated client-side (Training mode only; 0 for Emergency) |
| compressions | List<CompressionEvent> | Per-compression event list |
| ventilations | List<VentilationEvent> | Per-cycle ventilation events |
| pulseChecks | List<PulseCheckEvent> | Emergency only |
| rescuerVitals | List<RescuerVitalSnapshot> | Quality-gated rescuer vital snapshots |
| syncedToBackend | bool / app | False until POST /sessions/detail succeeds |

# **8. Local Storage — Offline Sessions**

## **8.1 LittleFS Configuration**

- Partition: minimum 512 KB dedicated to LittleFS in the ESP32 partition table

- Maximum stored sessions: 20. When full, oldest session is overwritten (circular buffer).

- Each session stored as a binary file: /sessions/sNN.bin, NN = two-digit slot index 00–19

- A metadata file /sessions/meta.bin, 41 bytes: bytes 0–19 slot state (0 = empty, 1 = pending), bytes 20–39 insertion sequence per slot (uint8, wraps), byte 40 next sequence number. The oldest slot is the one with the largest age (seqCounter − seq, mod 256). A confirmed session is deleted at once and its slot returns to empty.

- Sessions with fewer than STORAGE_MIN_COMPRESSIONS_TO_SAVE (3) compressions are not saved.

## **8.2 Binary Session Format**

All data stored in little-endian binary. No JSON. The header is 104 bytes, then 20 bytes per compression, 12 per ventilation, 13 per pulse check. A 2-minute session of 200 compressions is about 4.2 KB. Arrays are capped at 600 compressions, 20 ventilations and 10 pulse checks.

| **Field** | **Type** | **Description** |
| --- | --- | --- |
| SESSION HEADER |  |  |
| sessionMagic | uint16 | 0xC9A1 — magic number for integrity validation |
| sessionFormatVersion | uint8 | Schema version = 5. App checks this on sync; the offline session parser rejects any value ≠ 5. |
| sessionStartMs | uint64 | Unix timestamp in ms at SESSION_START. |
| sessionEndMs | uint64 | Unix timestamp in ms at SESSION_END. |
| mode | uint8 | 0 = Emergency, 1 = Training, 2 = Training-No-Feedback |
| scenario | uint8 | 0 = standard adult, 1 = pediatric |
| totalCompressions | uint32 |  |
| correctDepth | uint32 |  |
| correctFrequency | uint32 |  |
| correctRecoil | uint32 |  |
| depthRateCombo | uint32 |  |
| correctPosture | uint32 |  |
| leaningCount | uint32 |  |
| overForceCount | uint32 |  |
| tooDeepCount | uint32 |  |
| totalVentilations | uint32 |  |
| correctVentilations | uint32 |  |
| fatigueOnsetIndex | uint32 | Compression index of first fatigue. 0 = none. |
| peakDepth | float32 | Maximum depth this session (cm) |
| compressionDepthSD | float32 | Std deviation of per-compression depths (cm) |
| patientTemperatureLastPulseCheck | float32 | Byte 77. Last carotid skin temperature captured during a pulse check (°C). Same value as SESSION_END bytes 66–69. |
| rescuerWristTempStart | float32 | Byte 81. Rescuer wrist skin temperature at session start (°C). Not ambient air. |
| rescuerWristTempEnd | float32 | Byte 85. Rescuer wrist skin temperature at session end (°C). Not ambient air. |
| rescuerHRLastPause | float32 | Byte 89. Rescuer HR at last pause (BPM) |
| rescuerSpO2LastPause | float32 | Byte 93. Rescuer SpO2 at last pause (%) |
| pulseDetected | uint8 | 1 = pulse detected. Emergency only. |
| noFlowIntervals | uint8 | Count of unplanned pauses > 2 s |
| rescuerSwapCount | uint8 | TWO_MIN_ALERT events fired |
| compressionArrayLen | uint16 | Number of entries in per-compression array |
| ventilationArrayLen | uint8 | Number of VentilationEvent entries |
| pulseCheckArrayLen | uint8 | Byte 103. Number of PulseCheckEvent entries (Emergency only). Header ends at byte 103 (104 bytes). |
| PER-COMPRESSION ARRAY (20 bytes × compressionArrayLen) |  |  |
| timestampMs | uint32 | Milliseconds from session start |
| depth | float32 | Peak depth (cm) |
| frequency | float32 | Instantaneous rate (BPM) |
| recoilAchieved | uint8 | 1 = full recoil achieved |
| overForce | uint8 | 1 = force exceeded 600 N |
| postureOk | uint8 | 1 = wrist alignment within target range |
| wristAlignmentAngle_x10 | uint8 | wristAlignmentAngle × 10, clamped to uint8 (0–90° → 0–255). App divides by 10.0. |
| compressionAxisDev_x10 | uint8 | compressionAxisDeviation × 10, clamped to uint8. |
| reserved | uint8[3] | 0x00 (17 named bytes + 3 = 20) |
| VENTILATION ARRAY (12 bytes × ventilationArrayLen) |  |  |
| timestampMs | uint32 | Session ms when ventilation window opened |
| cycleNumber | uint16 | Which 30:2 cycle (starts at 1) |
| compressionsDuringWindow | uint8 | Number of compressions made while the window was open, saturating at 255. Not a breath count. Renamed from ventilationsGiven in v3.3; same byte, no format change. The app does not read it. |
| durationMs | uint32 | Total ms spent in ventilation window. The app does not read it; it recomputes duration from the compression timeline. |
| compliant | uint8 | 1 = the glove counted this window in correctVentilations (pause ≥ 3 s after the 2.5 s grace period). The app does not read it. |
| PULSE CHECK ARRAY (13 bytes × pulseCheckArrayLen) |  |  |
| timestampMs | uint32 | Session ms when pulse check window opened |
| intervalNumber | uint8 | Pulse-check number within the session, starting at 1 (name is historical) |
| classification | uint8 | 0=absent / 1=uncertain / 2=present |
| detectedBPM | float32 | BPM. 0.0 if not detected. |
| confidence | uint8 | 0–100. Same value as ppgSignalQuality (patient PPG signal quality), not a separate metric. |
| detectorACount | uint8 | Same as PULSE_CHECK_RESULT byte 7. |
| detectorBCount | uint8 | Same as PULSE_CHECK_RESULT byte 8. |

## **8.3 Offline Sync Flow**

- On BLE connect: glove reads metadata, counts slots in the pending state, sends PENDING_LOCAL_DATA (0x09) with count.

- App shows "X sessions stored on glove — syncing" banner.

- App sends 0xF5 REQUEST_SESSION with byte[1] = session index (0-based).

- Glove responds with LOCAL_SESSION_CHUNK (0x0A) packets: byte[1] = session index, byte[2] = chunk index, byte[3] = total chunks, bytes[4–95] = 92 bytes of session data per chunk.

- App reassembles chunks, parses binary into SessionDetail, saves locally, attempts POST to backend.

- App sends 0xF6 CONFIRM_RECEIVED with session index. Glove deletes the session file and returns the slot to empty.

- Repeat for all pending sessions sequentially.

# **9. Grading Formula (Training Mode Only)**

Grade is always computed client-side by the app. The glove never calculates or sends a grade. Score range: 0–100. Pulse check compliance is excluded from Training mode. Emergency sessions always receive grade 0.0. Sessions with fewer than 10 compressions also receive grade 0.0.

## **9.1 Standard Adult Weights**

| **Component** | **Weight** | **Min.** | **Formula** |
| --- | --- | --- | --- |
| Depth consistency | 25% | 0% | correctDepth / totalCompressions × 100 |
| Frequency consistency | 20% | 0% | correctFrequency / totalCompressions × 100 |
| Correct recoil | 20% | 0% | correctRecoil / totalCompressions × 100 |
| Depth + rate combo | 8% | 0% | depthRateCombo / totalCompressions × 100 |
| Hands-on ratio (CCF) | 5% | 0% | handsOnRatio × 100 |
| Ventilation compliance | 12% | 0% | SessionDetail.ventilationCompliance: share of ventilation prompts whose measured pause was 3–15 s (§7.2). Computed by the app from the compression timeline; the glove's own correctVentilations count is not used. 100% if no ventilation windows occurred (e.g. compression-only). |
| Posture consistency | 8% | 0% | correctPosture / totalCompressions × 100 |
| Time to first compression | 2% | 0% | 100 if < 5 s │ 80 if 5–10 s │ 50 if > 10 s |

Weights sum to 100%. The grade is a straight weighted sum of the above components, clamped to 0–100. There is no separate force-safety term and no fatigue penalty deduction in the grade; over-force and fatigue are surfaced to the user as standalone session metrics and live warnings, not as grade modifiers.

## **9.2 Pediatric Weights**

Applies when scenario = "pediatric". Depth weighted higher for the smaller chest and narrower target window. Total = 100%.

| **Component** | **Weight** | **Change vs Adult** |
| --- | --- | --- |
| Depth consistency | 28% | +3% — harder to maintain narrower target (4–5 cm) |
| Frequency consistency | 18% | −2% |
| Correct recoil | 18% | −2% |
| Depth + rate combo | 8% | unchanged |
| Hands-on ratio (CCF) | 4% | −1% |
| Ventilation compliance | 12% | unchanged |
| Posture consistency | 8% | unchanged |
| Time to first compression | 4% | +2% — pediatric urgency |

As with the adult weights, there is no force-safety term and no fatigue penalty. Weights sum to 100%.

## **9.3 Grade Bands**

There are no letter grades. The app uses three thresholds on the 0–100 grade, for colour and for the PDF verdict text.

| **Score Range** | **PDF verdict** | **Colour** |
| --- | --- | --- |
| 90–100 | Outstanding! | success |
| 75–89 | Great work! | primaryAlt |
| 55–74 | Keep it up! | warning |
| 0–54 | Keep practising! | error |

# **10. App Screen Behaviour**

## **10.1 Live CPR Screen — Overlays ****&**** Events**

| **Overlay / Event** | **Trigger ****&**** Behaviour** |
| --- | --- |
| BREATHE overlay | On VENTILATION_WINDOW (0x03). Full-width flash banner. Shows cycle counter e.g. "Cycle 3 — Give 2 breaths". Auto-dismisses when compressions resume or compressionInCycle resets. |
| IMU calibrating indicator | While imuCalibrated = 0. Small badge on depth bar: "Calibrating…". Auto-hides when imuCalibrated = 1. |
| Wrist sensor warning | While wristDropped = 1. Badge on posture display: "Wrist sensor lost". Audio alert once. |
| Pulse check card | On PULSE_CHECK_START (0x04), Emergency mode only. Non-blocking card in the Live CPR screen's scrolling content, not a modal. Shows "Pulse Check #N", elapsed time, and the live PPG waveform from ppgRaw. On PULSE_CHECK_RESULT the card shows "Circulation check recorded". No classification, BPM, confidence or decision prompt on the live card; those are stored and shown on the results screen. |
| Rescuer-switch banner | On TWO_MIN_ALERT (0x07). Non-blocking top banner: "2 minutes — consider switching rescuer". Dismiss button. Auto-hides after 10 s. Fires in both Emergency and Training modes. |
| Fatigue warning badge | On FATIGUE_ALERT (0x08). Small badge overlaid on depth bar: "Depth declining — press harder". Stays until depthTrend recovers above fatigue threshold. |
| Recovery checklist | After pulse detected + user taps "Stop CPR". Full-screen checklist: (1) Place in recovery position, (2) Monitor breathing, (3) EMS status confirmed. "Done" ends session and navigates to results summary. |
| Mode change banner | On MODE_CHANGE (0x06). UIHelper.showInfo banner shows new mode name. If switching to Training while not logged in, AppDialogs.promptLogin is shown. If dismissed, reverts to Emergency and writes 0xF1 Emergency back to glove. |
| Scenario change banner | On SCENARIO_CHANGE (0x0C). UIHelper.showInfo banner shows new scenario name. App updates depth targets accordingly. |
| Post-session login prompt | After Emergency mode session ends and user is not logged in: non-blocking AppDialogs.promptSaveSession shown once. Dismiss = session stays local only, no second prompt. |
| Offline sync badge | Shown on session results screen if syncedToBackend = false. Badge reads "Saved locally — will sync when online". |
| Pending sessions banner | On BLE connect when glove sends PENDING_LOCAL_DATA (0x09). Banner: "X session(s) stored on glove — syncing now". Triggers automatic sequential download of all pending sessions. |
| Self-test result | Shown on first connect and after 0xFC RUN_SELFTEST. If criticalMask != 0: modal warning listing failed sensors. If warnMask != 0: non-blocking banner. If all pass: brief "Glove ready" toast. |

## **10.2 Session Results Screen — Graphs**

Shown after Training mode session ends. All graphs share the same X-axis (seconds from session start). Built with fl_chart LineChart.

| **Graph** | **Colour** | **Annotations ****&**** Target Band** |
| --- | --- | --- |
| Compression Depth | AppColors.primary | Green target band: 5–6 cm (adult) or 4–5 cm (pediatric). Orange dashed secondary line: depthTrend (fatigue trend). Grey vertical bands: ventilation windows. Red vertical bands: unplanned pauses > 2 s. |
| Effective Depth | AppColors.accent | Same target band as depth. Shows angle-corrected depth alongside raw depth for comparison. Thesis-novel visualisation. |
| Compression Rate | AppColors.success | Green target band: 100–120 BPM. Amber vertical bands: pulse check windows. Rate variability shown as shaded area ±1 std dev. |
| Patient HR | AppColors.error | Scatter plot. Points only during pulse check windows. Points labelled with BPM. Perfusion index shown as secondary axis. |
| Rescuer HR | AppColors.warning | Line plot from RescuerVitalSnapshot[]. Greyed out points where signalQuality < 40. Fatigue onset index marked with vertical dashed line. RMSSD shown as secondary axis. |
| Posture Quality | AppColors.cprOrange | wristAlignmentAngle over time with a target line at CprTargets.alignmentMaxDeg (30°). Points above the line are marked. |

## **10.3 Mode ****&**** Scenario Switching**

- App UI: settings screen or mode toggle on live CPR screen header. Writes 0xF1 MODE_SET to EVENT_CHANNEL.

- Glove button hold 2 s: cycles Emergency → Training → Training-No-Feedback → Emergency. Glove sends MODE_CHANGE (0x06). App shows UIHelper.showInfo banner.

- Glove button double-press: cycles adult → pediatric → adult. Glove sends SCENARIO_CHANGE (0x0C). App updates depth targets (SET_TARGET_DEPTH sent automatically).

- Training mode requires a logged-in account. If mode switches to Training and user is not logged in, show AppDialogs.promptLogin. If dismissed, revert to Emergency and write 0xF1 MODE_SET Emergency back to glove.

- Training-No-Feedback: app shows "No-Feedback Mode" label. feedbackMask = 0x00 confirmed by LIVE_STREAM byte[91].

## **10.4 Local Session Storage — App Side**

- Every session saved to SharedPreferences immediately on end: key = session_local_<timestamp>, value = SessionDetail.toJson().

- On app launch and on BLE/network reconnect: scan for sessions where syncedToBackend = false. POST each to /sessions/detail. Mark syncedToBackend = true on success.

- sessionSummariesProvider merges backend sessions + unsynced local sessions into a single sorted list by sessionStart.

- AppConstants.maxLocalSessions = 20. Oldest local sessions evicted if limit is reached.

# **11. Backend Schema**

Source of truth: CPR-Assist-Server/db.js. Tables are created with CREATE TABLE IF NOT EXISTS and extended with ADD COLUMN IF NOT EXISTS on every start.

## **11.1 cpr_sessions Table (all columns)**

| **Column** | **Type / Default** | **Notes** |
| --- | --- | --- |
| id | BIGSERIAL PK |  |
| user_id | BIGINT NOT NULL | FK users(id) ON DELETE CASCADE |
| mode | VARCHAR(25) / 'emergency' | "emergency" │ "training" │ "training_no_feedback" |
| scenario | VARCHAR(40) / 'standard_adult' | "standard_adult" │ "pediatric" |
| session_start | TIMESTAMPTZ NOT NULL | Unique per user (upsert key with user_id) |
| session_end | TIMESTAMPTZ |  |
| compression_count | INT / 0 |  |
| correct_depth | INT / 0 |  |
| correct_frequency | INT / 0 |  |
| correct_recoil | INT / 0 |  |
| depth_rate_combo | INT / 0 |  |
| correct_posture | INT / 0 | Firmware postureOk count (alignment < 30°) |
| leaning_count | INT / 0 |  |
| over_force_count | INT / 0 |  |
| too_deep_count | INT / 0 |  |
| correct_ventilations | INT / 0 | App-computed (3–15 s pauses) |
| average_depth | FLOAT / 0 | cm |
| average_frequency | FLOAT / 0 | BPM |
| average_effective_depth | FLOAT / 0 | cm, angle-corrected |
| peak_depth | FLOAT / 0 | cm |
| depth_sd | FLOAT / 0 | cm |
| depth_consistency | FLOAT / 0 | % |
| freq_consistency | FLOAT / 0 | % |
| hands_on_ratio | FLOAT / 1 | 0–1, CCF |
| no_flow_time | FLOAT / 0 | s, all gaps > 2 s including planned pauses (§6) |
| no_flow_intervals | INT / 0 | App-computed count of those gaps (authoritative) |
| no_flow_intervals_firmware | INT / 0 | Glove SESSION_END byte 91, advisory |
| unplanned_pause_time | FLOAT / 0 | s, gaps outside or beyond planned windows |
| unplanned_pause_count | INT / 0 |  |
| rate_variability | FLOAT / 0 | ms |
| time_to_first_comp | FLOAT / 0 | s |
| consecutive_good_peak | INT / 0 | longest unbroken correct streak |
| fatigue_onset_index | INT / 0 | 0 = no fatigue |
| rescuer_swap_count | INT / 0 | TWO_MIN_ALERT count |
| ventilation_count | INT / 0 |  |
| ventilation_compliance | FLOAT / 0 | 0–100 % |
| pulse_checks_prompted | INT / 0 | Windows opened by the passive gate |
| pulse_checks_complied | INT / 0 | Windows closed with SQI ≥ 40 |
| pulse_detected_final | BOOLEAN / false |  |
| wrist_dropped_during_session | BOOLEAN / false | SESSION_END byte 95 |
| patient_temperature | FLOAT / NULL | °C, last carotid skin temp during a pulse check |
| patient_spo2_last_check | FLOAT / NULL | % |
| rescuer_hr_last_pause | FLOAT / NULL | BPM |
| rescuer_spo2_last_pause | FLOAT / NULL | % |
| rescuer_wrist_temp_start | FLOAT / NULL | °C wrist skin |
| rescuer_wrist_temp_end | FLOAT / NULL | °C wrist skin |
| user_heart_rate | FLOAT / NULL | Legacy |
| user_temperature | FLOAT / NULL | Legacy |
| session_duration | INT / 0 | s |
| total_grade | FLOAT / 0 | 0–100, 0 for Emergency |
| note | VARCHAR(500) |  |
| fatigue_alert_timestamp_ms | INTEGER |  |
| fatigue_alert_score | INTEGER |  |
| two_min_alert_timestamps_ms | INTEGER[] |  |
| two_min_alert_numbers | INTEGER[] |  |
| mode_change_timestamps_ms / _values / _triggers | INTEGER[] ×3 | One entry per MODE_CHANGE |
| scenario_change_timestamps_ms / _values / _triggers | INTEGER[] ×3 | One entry per SCENARIO_CHANGE |

## **11.2 Sub-Tables**

All have id BIGSERIAL PK, session_id BIGINT NOT NULL (FK cpr_sessions ON DELETE CASCADE), timestamp_ms INT NOT NULL, and an index on (session_id, timestamp_ms).

session_compressions: depth, frequency, instantaneous_rate, force, recoil_achieved, over_force, posture_ok, leaning_detected, wrist_alignment_angle, wrist_flexion_angle, compression_axis_dev, effective_depth, peak_force, downstroke_time_ms, peak_ts, valley_ts, valley_depth (= residualLoadDepthCm)

session_ventilations: cycle_number, duration_sec, compliant

session_pulse_checks: interval_number, interval_from_start, classification, detected, detected_bpm, confidence, perfusion_index, detector_a_count, detector_b_count, ref_source, user_decision, patient_spo2, ppg_samples (JSONB)

session_rescuer_vitals: heart_rate, spo2, rmssd, rescuer_pi, temperature, fatigue_score, signal_quality, pause_type, humidity

## **11.3 Endpoints**

| **Method** | **Path** | **Purpose** |
| --- | --- | --- |
| POST | /sessions/detail | Save full SessionDetail including sub-lists. Upsert on (user_id, session_start). |
| GET | /sessions/summaries | All summary-level fields for the current user, ordered by session_start DESC. |
| GET | /sessions/summary | Paginated summary list (limit, offset query params). |
| GET | /sessions/best | Single best Training session by total_grade. |
| GET | /sessions/:id/detail | Full SessionDetail with all sub-lists. |
| PATCH | /sessions/:id/note | Update the note field only. |
| DELETE | /sessions/:id | Delete one session (CASCADE removes sub-tables). |
| DELETE | /sessions/all | Delete all sessions for current user. |
| GET | /leaderboard/global | Ranked list by avg_grade for scenario (query param). Returns top N + current user rank. |

# **12. Firmware Implementation Checklist**

| **#** | **Task** | **Priority** | **Blocks** |
| --- | --- | --- | --- |
| 1 | Implement LIVE_STREAM characteristic (UUID 19b10001-…) — notify, 108-byte fixed frame at 10 Hz | Critical | All live UI |
| 2 | Implement EVENT_CHANNEL characteristic (UUID 19b10002-…) — notify + write, 96-byte fixed frame | Critical | Session lifecycle |
| 3 | Implement BLE write handler: parse 0xF1–0xF4, 0xF5–0xF6, 0xF7–0xFD | Critical | App control |
| 4 | Negotiate MTU 247 on connect; confirm 108-byte + 96-byte frames fit | Critical | Packet integrity |
| 5 | IMU fusion: fuse dual LSM6DSOX with FlexiForce A401 to compute depth (cm) at 10 Hz | Critical | depth field |
| 6 | Compute instantaneousRate from last 2 compression timestamps; compute 5-comp rolling avg as frequency field | Critical | frequency / instantaneousRate |
| 7 | Compute depthTrend: 5-comp rolling avg of peak depths. Stream continuously in LIVE_STREAM bytes 36–39. | High | fatigue trend line |
| 8 | Compute wristAlignmentAngle as absolute palm-IMU pitch (°) | High | posture metrics |
| 9 | Compute wristFlexionAngle from ulnar-side IMU (wrist bending forward/back in degrees) | High | wristFlexionAngle |
| 10 | Compute compressionAxisDeviation as absolute palm-IMU roll | High | effectiveDepth |
| 11 | Set postureOk = 1 when wristAlignmentAngle < WRIST_ALIGN_WARN_DEG (30°) | High | postureOk flag |
| 12 | Set recoilAchieved = 1 when depth < 0.5 cm AND force < 5 N before next compression starts | High | recoilAchieved |
| 13 | Set leaningDetected = 1 when inter-compression force stays > 5 N for > 200 ms without new downstroke | High | leaningDetected |
| 14 | Set overForceFlag = 1 when compression force exceeds 600 N; increment overForceCount in SESSION_END | High | overForceFlag |
| 15 | Set fatigueFlag = 1 when depthTrend declines ≥ FATIGUE_DECLINE_THRESHOLD_MM (10 mm) from the first-5-compression average; send FATIGUE_ALERT (0x08) once per session | High | fatigueFlag |
| 16 | Compute rescuerFatigueScore (0–100): depth-decline proxy = (firstFiveCompressionAvgDepthMM − currentDepthTrendMM) / FATIGUE_DECLINE_THRESHOLD_MM × 100, clamped 0–100. Elevated rescuer HR lowers the trigger threshold only; RMSSD is NOT an input. Stream in LIVE_STREAM byte 49. | High | rescuerFatigueScore |
| 17 | Set imuCalibrated = 1 once the palm filter is initialised and 3 gravity cycles have been counted (count kept across sessions) | High | imuCalibrated |
| 18 | Latch wristDropped = 1 after WRIST_DROPOUT_LIMIT (3) consecutive zero-depth wrist strokes once the wrist gravity baseline is established; clear on session reset | High | wristDropped |
| 19 | Track tooDeepCount: increment when peak depth > 6 cm (adult) or > 5 cm (pediatric) | Medium | tooDeepCount in SESSION_END |
| 20 | Implement VENTILATION_WINDOW (0x03): send at 30th compression of each cycle; reset compressionInCycle; count the window in correctVentilations on a ≥ 3 s pause after a 2.5 s grace period | High | ventilation flow |
| 21 | Implement TWO_MIN_ALERT (0x07): send every 120 s of active session time; trigger haptic + audio | High | rescuer swap banner |
| 22 | Implement PULSE_CHECK_START (0x04): Emergency mode only, passive gate on rescuer pause + 500 ms sustained patient-sensor contact, one check per palpation, never prompted | High | pulse check card |
| 23 | Implement PULSE_CHECK_RESULT (0x05): on window close; include classification (0/1/2), BPM, confidence, detectorACount, detectorBCount, refSource | High | pulse check result |
| 24 | Wrist MAX30102: stream heartRateUser, spO2User, rescuerSignalQuality, rescuerRMSSD, rescuerPI continuously | High | rescuer vitals |
| 25 | Fingertip MAX30102: zero ppgRaw, heartRatePatient, spO2Patient outside pulse check windows | High | patient vitals gating |
| 26 | Temperature encoding: send patientTemperature (bytes 70–71) and rescuerTemperature (bytes 82–83) in LIVE_STREAM as uint16 = celsius × 100. In SESSION_END send as float32. | High | temperature fields |
| 27 | Physical button: single press = SESSION_START / SESSION_END; hold 2 s = cycle mode + send MODE_CHANGE (0x06); double-press = cycle scenario + send SCENARIO_CHANGE (0x0C) | High | session control |
| 28 | Training-No-Feedback mode: suppress DFPlayer, vibration motor, all NeoPixels when feedbackEnabled = 0 | High | Training-No-Feedback |
| 29 | Auto-end: if 120 s pass since the last compression, outside any pulse-check or ventilation window, send SESSION_END (0x02) | High | zombie session prevention |
| 30 | SESSION_START (0x01): include mode (byte[1]) and scenario (byte[2]) | High | session metadata |
| 31 | Implement 0xF7 CALIBRATE: idle only; re-run force baseline until converged (2 s timeout), then self-test and reply SELFTEST_RESULT | High | force calibration |
| 32 | Implement 0xF8 SET_TARGET_DEPTH and 0xF9 SET_TARGET_RATE: override feedback thresholds | High | scenario-specific feedback |
| 33 | Implement 0xFA SYNC_TIME: receive uint64 Unix timestamp from app; use for LittleFS session timestamps | Medium | session timestamps |
| 34 | Implement 0xFB SET_VENTILATION: receive compressions-per-cycle and ventilations-expected overrides | Medium | ventilation ratio |
| 35 | Implement 0xFC RUN_SELFTEST: test all sensors; send SELFTEST_RESULT (0x0B) with pass/warn/critical bitmasks and battery % | Medium | self-test |
| 36 | Implement 0xFD SET_SCENARIO: receive scenario byte; send SCENARIO_CHANGE (0x0C) to confirm; apply depth/feedback thresholds | High | pediatric mode |
| 37 | Implement LittleFS on internal flash; define partition scheme with ≥ 512 KB for data | High | local storage |
| 38 | On session end: write full session binary (header + arrays) to LittleFS with magic number 0xC9A1 | High | offline sessions |
| 39 | On BLE connect: count stored sessions; if > 0 send PENDING_LOCAL_DATA (0x09) with count in byte[1] | High | offline sync trigger |
| 40 | Implement LOCAL_SESSION_CHUNK (0x0A) streaming: on 0xF5 REQUEST_SESSION, stream stored binary in 92-byte chunks | High | offline data transfer |
| 41 | On 0xF6 CONFIRM_RECEIVED: delete the confirmed session and mark its slot empty in meta.bin; enforce max 20 stored sessions (evict oldest) | High | storage management |
| 42 | Set all reserved bytes to 0x00 always | Low | — |

# **Appendix — Quick Reference**

## **CPR Target Ranges (ERC 2021 / AHA 2020)**

| **Parameter** | **Standard Adult Target** | **Pediatric Target** | **Out-of-range Feedback** |
| --- | --- | --- | --- |
| Depth | 5–6 cm | 4–5 cm | Too shallow: "Press harder" │ Too deep: "Ease off" |
| Rate | 100–120 BPM | 100–120 BPM | Too slow: "Press faster" │ Too fast: "Slow down" |
| Recoil | Full release | Full release | "Lift hands fully between compressions" |
| Force | < 600 N | < 400 N | Over-force: "Ease off — rib fracture risk" |
| Ventilations | 2 per 30 compressions | 2 per 30 | "Give 2 breaths now" |
| Wrist angle | Palm tilt < 30° (design threshold, not a guideline value) | < 30° | "Straighten your arms" |
| Wrist flexion | Display guide ±10°, not scored | Display guide ±10° | "Lock your wrists" |

## **BLE UUID Reference**

| **Characteristic** | **UUID** |
| --- | --- |
| GATT Service | 19b10000-e8f2-537e-4f6c-d104768a1214 |
| LIVE_STREAM | 19b10001-e8f2-537e-4f6c-d104768a1214 |
| EVENT_CHANNEL | 19b10002-e8f2-537e-4f6c-d104768a1214 |

## **Packet Type Byte Quick Reference**

| **Byte** | **Name** | **Direction** | **Channel** |
| --- | --- | --- | --- |
| 0x01 | SESSION_START | Glove → App | EVENT_CHANNEL notify |
| 0x02 | SESSION_END | Glove → App | EVENT_CHANNEL notify |
| 0x03 | VENTILATION_WINDOW | Glove → App | EVENT_CHANNEL notify |
| 0x04 | PULSE_CHECK_START | Glove → App | EVENT_CHANNEL notify |
| 0x05 | PULSE_CHECK_RESULT | Glove → App | EVENT_CHANNEL notify |
| 0x06 | MODE_CHANGE | Glove → App | EVENT_CHANNEL notify |
| 0x07 | TWO_MIN_ALERT | Glove → App | EVENT_CHANNEL notify |
| 0x08 | FATIGUE_ALERT | Glove → App | EVENT_CHANNEL notify |
| 0x09 | PENDING_LOCAL_DATA | Glove → App | EVENT_CHANNEL notify |
| 0x0A | LOCAL_SESSION_CHUNK | Glove → App | EVENT_CHANNEL notify |
| 0x0B | SELFTEST_RESULT | Glove → App | EVENT_CHANNEL notify |
| 0x0C | SCENARIO_CHANGE | Glove → App | EVENT_CHANNEL notify |
| 0x0D | DIAG_FRAME | Glove → App | EVENT_CHANNEL notify |
| 0xF1 | APP → MODE_SET | App → Glove | EVENT_CHANNEL write |
| 0xF2 | APP → FEEDBACK_SET | App → Glove | EVENT_CHANNEL write |
| 0xF3 | APP → START | App → Glove | EVENT_CHANNEL write — reserved, not implemented app-side |
| 0xF4 | APP → STOP | App → Glove | EVENT_CHANNEL write — reserved, not implemented app-side |
| 0xF5 | APP → REQUEST_SESSION | App → Glove | EVENT_CHANNEL write |
| 0xF6 | APP → CONFIRM_RECEIVED | App → Glove | EVENT_CHANNEL write |
| 0xF7 | APP → CALIBRATE | App → Glove | EVENT_CHANNEL write |
| 0xF8 | APP → SET_TARGET_DEPTH | App → Glove | EVENT_CHANNEL write |
| 0xF9 | APP → SET_TARGET_RATE | App → Glove | EVENT_CHANNEL write |
| 0xFA | APP → SYNC_TIME | App → Glove | EVENT_CHANNEL write |
| 0xFB | APP → SET_VENTILATION | App → Glove | EVENT_CHANNEL write |
| 0xFC | APP → RUN_SELFTEST | App → Glove | EVENT_CHANNEL write |
| 0xFD | APP → SET_SCENARIO | App → Glove | EVENT_CHANNEL write |
| 0xFE | APP → SET_FEEDBACK_CH | App → Glove | EVENT_CHANNEL write |
| 0xFF | APP → SET_VOLUME | App → Glove | EVENT_CHANNEL write |
| 0xEB | APP → SET_LED_BRIGHTNESS | App → Glove | EVENT_CHANNEL write |
| 0xED | APP → DIAG_START | App → Glove | EVENT_CHANNEL write |
| 0xEC | APP → DIAG_STOP | App → Glove | EVENT_CHANNEL write |
| 0xEE | APP → DIAG_ACTION | App → Glove | EVENT_CHANNEL write |
| N/A | LIVE_STREAM (continuous) | Glove → App | LIVE_STREAM characteristic notify |