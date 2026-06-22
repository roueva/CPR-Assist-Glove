#pragma once
// =============================================================================
// config.h — CPR Assist Glove Firmware v1.0
// All compile-time constants. Change values here only.
// =============================================================================

// ── Firmware version ──────────────────────────────────────────────────────────
#define FW_VERSION_MAJOR 1
#define FW_VERSION_MINOR 0

// ── GPIO pin assignments ──────────────────────────────────────────────────────
#define PIN_SDA 21
#define PIN_SCL 22
#define PIN_FSR_ADC 34        // ADC1_CH6 — MCP6002 VOUT
#define PIN_BUTTON 27         // Active LOW, 10kΩ pull-up
#define PIN_MOTOR 32          // PWM → 2N2222 base
#define PIN_NEOPIXEL 19   // was 18 — rerouted, GPIO18 damaged by overvoltage incident       // WS2812B data, 100Ω series
#define PIN_DFPLAYER_TX 16    // ESP32 TX → DFPlayer RX (via 1kΩ)
#define PIN_DFPLAYER_RX 17    // ESP32 RX ← DFPlayer TX
#define PIN_EN_CONTROL 26     // PowerBoost EN. MCU keeps INPUT (Hi-Z) ONLY. Physical switch shorts to GND for off. Never drive from MCU.
#define PIN_CHARGE_DETECT 33  // HIGH = USB charging
#define PIN_BAT_ADC 35        // ADC1_CH7 — BAT_MID voltage divider

// ── I²C ───────────────────────────────────────────────────────────────────────
#define I2C_FREQ 400000  // 400 kHz fast mode
#define TCA_ADDRESS 0x70

// TCA9548A channel assignments
#define TCA_CH_IMU_PALM 0    // LSM6DSOX palm  — 0x6B
#define TCA_CH_IMU_WRIST 1   // LSM6DSOX wrist — 0x6A
#define TCA_CH_MAX30205 2    // Patient skin temp
#define TCA_CH_GXHT30 3      // Rescuer temp + humidity
#define TCA_CH_MAX30102_R 4  // MAX30102 rescuer HR/SpO2
#define TCA_CH_MAX30102_P 5  // MAX30102 patient HR/SpO2

// Sensor I²C addresses
#define LSM6DSOX_ADDR_PALM 0x6B
#define LSM6DSOX_ADDR_WRIST 0x6A
#define MAX30205_ADDR 0x48
#define GXHT30_ADDR 0x44
#define MAX30102_ADDR 0x57  // same address, separated by TCA channel

// ── BLE ───────────────────────────────────────────────────────────────────────
#define BLE_DEVICE_NAME "CPR_Glove"
#define BLE_SERVICE_UUID "19b10000-e8f2-537e-4f6c-d104768a1214"
#define BLE_LIVE_STREAM_UUID "19b10001-e8f2-537e-4f6c-d104768a1214"
#define BLE_EVENT_CHAN_UUID "19b10002-e8f2-537e-4f6c-d104768a1214"
#define BLE_MTU 247
#define LIVE_STREAM_SIZE 108
#define EVENT_CHANNEL_SIZE 96
#define LIVE_STREAM_INTERVAL_MS 100  // 10 Hz — reduces BLE congestion; still smooth enough for display

// EVENT_CHANNEL packet types (glove → app)
#define PKT_SESSION_START 0x01
#define PKT_SESSION_END 0x02
#define PKT_VENTILATION_WINDOW 0x03
#define PKT_PULSE_CHECK_START 0x04
#define PKT_PULSE_CHECK_RESULT 0x05
#define PKT_MODE_CHANGE 0x06
#define PKT_TWO_MIN_ALERT 0x07
#define PKT_FATIGUE_ALERT 0x08
#define PKT_PENDING_LOCAL_DATA 0x09
#define PKT_LOCAL_SESSION_CHUNK 0x0A
#define PKT_SELFTEST_RESULT 0x0B
#define PKT_SCENARIO_CHANGE 0x0C

// EVENT_CHANNEL commands (app → glove)
#define CMD_MODE_SET 0xF1
#define CMD_FEEDBACK_SET 0xF2
#define CMD_START 0xF3
#define CMD_STOP 0xF4
#define CMD_REQUEST_SESSION 0xF5
#define CMD_CONFIRM_RECEIVED 0xF6
#define CMD_CALIBRATE 0xF7
#define CMD_SET_TARGET_DEPTH 0xF8
#define CMD_SET_TARGET_RATE 0xF9
#define CMD_SYNC_TIME 0xFA
#define CMD_SET_VENTILATION 0xFB
#define CMD_RUN_SELFTEST 0xFC
#define CMD_SET_SCENARIO        0xFD   // payload: byte 1 = scenario (0=adult, 1=pediatric)
#define CMD_SET_FEEDBACK_CH     0xFE
#define CMD_SET_VOLUME          0xFF   // payload: byte 1 = audio volume 0–30,
                                       //          byte 2 = motor intensity 0–100 (optional)
#define CMD_SET_LED_BRIGHTNESS  0xEB   // payload: byte 1 = NeoPixel master brightness 0–255 (0 = LEDs off)

#define CMD_DIAG_START  0xED    // App → Glove: enter diagnostic mode
#define CMD_DIAG_STOP   0xEC   // App → Glove: exit diagnostic mode
// byte[1] = action code:
#define CMD_DIAG_ACTION 0xEE  // App → Glove: trigger a one-shot test action
//   0x01 = play audio track 1
//   0x02 = fire motor 500ms
//   0x03 = LED chase test (R→G→B→white)
//   0x04 = run I2C scan (result sent back via LIVE_STREAM diag bytes)
//   0x05 = set audio volume (byte[2] = 0–30)
//   0x06 = set LED brightness (byte[2] = 0–255)

// Selftest sensor bit positions (passMask / warnMask / criticalMask)
#define SELFTEST_BIT_IMU1 (1 << 0)      // LSM6DSOX palm    — critical
#define SELFTEST_BIT_IMU2 (1 << 1)      // LSM6DSOX wrist   — critical
#define SELFTEST_BIT_FORCE (1 << 2)     // FlexiForce+MCP   — critical
#define SELFTEST_BIT_MAX_P (1 << 3)     // MAX30102 patient — warn
#define SELFTEST_BIT_MAX_R (1 << 4)     // MAX30102 rescuer — warn
#define SELFTEST_BIT_TEMP (1 << 5)      // MAX30205         — warn
#define SELFTEST_BIT_HUMIDITY (1 << 6)  // GXHT30           — warn
#define SELFTEST_BIT_AUDIO (1 << 7)     // DFPlayer Mini    — warn

// ── Diagnostic mode ──────────────────────────────────────────────────────────
// When diagActive = true, LIVE_STREAM reserved bytes carry diagnostic data:
// Bytes 52–55:  int16 rawFsrAdc (52–53), uint8 palmWhoAmI (54), uint8 wristWhoAmI (55)
// Bytes 86–87:  uint8 i2cScanResult (86), uint8 diagActionResult (87)
// Bytes 102–107: float32 palmAccelMag (102–105), reserved (106–107)
// palmWhoAmI / wristWhoAmI: 0x6C = correct LSM6DSOX, 0x00 = no response, 0xFF = read error
// i2cScanResult: bitmask — bit0=CH0(palmIMU), bit1=CH1(wristIMU), bit2=CH2(MAX30205),
//                           bit3=CH3(GXHT30), bit4=CH4(MAX30102_R), bit5=CH5(MAX30102_P)
// diagActionResult: 0x00=idle, 0x01=audio_ok, 0x02=motor_fired, 0x03=led_ok, 0x04=scan_done
#define DIAG_ACTION_PLAY_AUDIO 0x01
#define DIAG_ACTION_FIRE_MOTOR 0x02
#define DIAG_ACTION_LED_TEST 0x03
#define DIAG_ACTION_I2C_SCAN 0x04
#define DIAG_ACTION_SET_VOLUME 0x05
#define DIAG_ACTION_SET_BRIGHTNESS 0x06

// DFPlayer volume range: 0–30. Default = 22.
#define DFPLAYER_DEFAULT_VOLUME 22
// NeoPixel brightness: 0–255. Default = 180.
#define NEOPIXEL_DEFAULT_BRIGHTNESS 180

// ── IMU ───────────────────────────────────────────────────────────────────────
#define LSM6DSOX_WHO_AM_I 0x0F
#define LSM6DSOX_CTRL1_XL 0x10
#define LSM6DSOX_CTRL2_G 0x11
#define LSM6DSOX_CTRL3_C 0x12
#define LSM6DSOX_OUTX_L_A 0x28
#define LSM6DSOX_OUTY_L_A 0x2A
#define LSM6DSOX_OUTZ_L_A 0x2C
#define LSM6DSOX_OUTX_L_G 0x22
#define LSM6DSOX_OUTY_L_G 0x24
#define LSM6DSOX_OUTZ_L_G 0x26

// CTRL1_XL register: ODR=104Hz, FS=±4g, LPF2=ON.
// ±2g (0x40) was initially tested but clips at CPR peak accel (~25–30 m/s² > 19.6 m/s²
// ±2g ceiling). Switched to ±4g + hardware LPF2 (0x4A): halved quantization noise
// from LPF2 compensates for the wider range; no clipping risk.
// Sensitivity for ±4g: 0.122 mg/LSB (ST LSM6DSOX datasheet).
// bits[7:4]=0100(104Hz), bits[3:2]=10(±4g), bit1=1(LPF2 ON)
#define IMU_CTRL1_XL_VALUE 0x4A
#define ACCEL_SENSITIVITY 0.122f


// CTRL2_G = 0x50 → ODR=208Hz, FS=±250dps
#define IMU_CTRL2_G_VALUE 0x40  // ODR=104Hz, FS=±250dps — matches accel ODR, no aliasing
// Gyro sensitivity: ±250dps → 8.75 mdps/LSB
#define GYRO_SENSITIVITY (8.75f / 1000.0f)

#define SAMPLE_RATE 100.0f
#define SAMPLE_DT (1.0f / SAMPLE_RATE)
#define CF_ALPHA      0.98f   // standard — 0.5s time constant at 100Hz
#define CF_ALPHA_FAST 0.85f   // fast-converge gain — used for ~60 ticks at session start (Mahony 2008)
// Was 50 mg (~0.49 m/s²) — zeroed motion accel through most of every stroke,
// fully decorrelating depth from force. 12 mg keeps a small drift guard.

// Accelerometer bias deadband — values below this are zeroed. Sized between
// LSM6DSOX typical zero-g offset (~30 mg) and the validated 50 mg from
// thesis_depth.ino. 30 mg balances bias suppression against signal preservation.
// Note: less critical once CF-driven gravity removal is active (rotation matrix
// continuously projects out gravity, so static bias becomes a smaller share of
// the residual). Literature: integration bias is dominant drift source
// (Song 2015 U-CPR; Tomlinson 2021 review; Aase 2002 boundary method).
#define ACC_DEADBAND_MS2 (10.0f * 9.81f / 1000.0f)  // 10 mg ≈ 0.098 m/s² — CF gravity removal is continuous; 30 mg was removing signal

#define GRAV_EMA_ALPHA 0.85f
#define GRAV_MIN_CYCLES_PALM 3
#define GRAV_MIN_CYCLES_WRIST 6

#define WRIST_DROPOUT_LIMIT 3


#define UNPLANNED_PAUSE_THRESHOLD_MS 2000UL     // 2 seconds — AHA/ERC standard
#define SESSION_INACTIVITY_TIMEOUT_MS 120000UL  // 120 seconds


// Force-to-depth coefficient — population mean k for human chest stiffness.
// Derived from Tomlinson et al. 2007 (n=91 OHCA): F38 = 27.5 kg ≈ 270 N
// → depth = k * 270^0.6 = k * 27.84, solving for 38 mm gives k ≈ 1.365.
// Cross-check at F25: k * 136.3^0.6 = k * 18.92, solving for 25 mm gives k ≈ 1.32.
// We use 1.35 as the rounded population mean. Per-session calibration refines
// this for the specific surface (manikin or patient) via forceCalibCompute().

// When you find k set FORCE_CALIB_LOCK to 1
#define K_POPULATION_DEFAULT 1.7131f //little anne manikin 2.9612, 2.8710, 2.7046, 2.9585, 3.0136, 2.6200, 2.5847, 2.9615
// #define K_POPULATION_DEFAULT 2.0624f  //qcpr
// #define K_POPULATION_DEFAULT 1.35f


// ── Force sensor ──────────────────────────────────────────────────────────────
// Exponential model: F = FORCE_EXP_A * (expf(FORCE_EXP_B * V_rel) - 1.0f) + FORCE_EXP_C
// V_rel = V_measured - FORCE_BASELINE_V
// Calibrated 2026 — R²=0.9995, RMSE=5.14N, MaxErr=7.90N
#define FORCE_BASELINE_V  0.4008f
#define FORCE_EXP_A       114.882626f
#define FORCE_EXP_B       1.056205f
#define FORCE_EXP_C       5.212799f

// Old quadratic coefficients — kept for reference, no longer used
// #define FORCE_C0 7.46f
// #define FORCE_C1 61.55f
// #define FORCE_C2 77.80f

#define FORCE_COMPRESS_START 30.0f  // N — compression begins
#define FORCE_RELEASE_DONE 20.0f    // N — release confirmed
#define FORCE_BASELINE_MIN 30.0f    // N — below this → zero depth
#define FORCE_BASELINE_SAMPLES 50
#define RELEASE_CONFIRM_NEEDED 6
// Force→depth power-law exponent. Derived from Tomlinson et al., Resuscitation
// 2007 (n=91 OOHCA), anchored on F25=13.9kg→25mm and F38=27.5kg→38mm.
// The chest is CONCAVE (exponent < 1): NOT the stiffness-progressivity factor γ.
#define DEPTH_EXPONENT 0.6f

// =============================================================================
// DEV FLAGS — all Serial debug output is controlled here.
//
// Session-time flags (require an active session):
//   BLE_DEBUG_SERIAL    — live BLE packet stream (~1 Hz)
//   DEPTH_PIPELINE_LOG  — per-compression CSV: palmMM, wristMM, imuMM,
//                         forceMM, k, finalMM, strokeMs. Use to extract k.
//   DEPTH_SELECTOR_LOG  — same compression, different view: confidence % and
//                         selector source (HIGH_CONF / IMU_PREF / etc.).
//
// Bench-test flags (no session needed, standalone tests):
//   FORCE_TEST_LOG — prints ADC/voltage/force every 250ms. Use with scale.
//   IMU_TEST_LOG   — type 'g' to run 1s integration window. Move glove.
//
// ┌─────────────────────┬───────────────┬──────────────┬──────────────────┐
// │ Flag                │ Development   │ Manikin calib│ Participant study │
// ├─────────────────────┼───────────────┼──────────────┼──────────────────┤
// │ BLE_DEBUG_SERIAL    │ 1             │ 0            │ 0                │
// │ DEPTH_PIPELINE_LOG  │ 1             │ 1  ← get k   │ 0                │
// │ DEPTH_SELECTOR_LOG  │ 1             │ 1  ← verify  │ 0                │
// │ FORCE_TEST_LOG      │ bench only    │ 0            │ 0                │
// │ IMU_TEST_LOG        │ bench only    │ 0            │ 0                │
// └─────────────────────┴───────────────┴──────────────┴──────────────────┘
//
// ALL flags must be 0 for participant sessions — Serial output adds latency.
// =============================================================================

// 1 = print [LIVE] packet stream and [EVENT] hex dumps to Serial (~1 Hz)
#define BLE_DEBUG_SERIAL    0

// 1 = print CALIB CSV per compression (pipeline view: palmMM, wristMM, imuMM,
//     forceMM, current k, finalMM). Also gates the [DBG-DEPTH] raw print.
//     Works on any surface — name MANIKIN was misleading, this is surface-agnostic.
#define DEPTH_PIPELINE_LOG  1

// 1 = print [DEPTH-SEL] per compression (confidence view: imuConf%, forceConf%,
//     selector decision, finalMM, finalConf%). Different data from DEPTH_PIPELINE_LOG.
#define DEPTH_SELECTOR_LOG  1

// 1 = print FTEST adc/voltage/force every 250ms. No session needed.
//     Use with kitchen scale and known weights to verify force sensor reads.
#define FORCE_TEST_LOG      0

// 1 = type 'g' in Serial Monitor to start a 1-second IMU integration window.
//     Move glove a known distance; it reports palmMM / wristMM measured.
#define IMU_TEST_LOG        0


#define FORCE_BASELINE_ADAPT_ALPHA 0.002f  // how fast baseline drifts down (per sample at 100Hz ≈ 5min to fully adapt)

// LOW_FORCE_MODE: true = foam/hand testing. false = real manikin CPR.
#define LOW_FORCE_MODE true

// ── CPR targets ───────────────────────────────────────────────────────────────
// Adult
#define TARGET_DEPTH_MIN_ADULT 50.0f  // mm
#define TARGET_DEPTH_MAX_ADULT 60.0f  // mm
#define TARGET_RATE_MIN 100.0f        // BPM
#define TARGET_RATE_MAX 120.0f        // BPM
#define FORCE_OVERFORCE_ADULT 600.0f  // N

// Pediatric
#define TARGET_DEPTH_MIN_PEDS 40.0f  // mm
#define TARGET_DEPTH_MAX_PEDS 50.0f  // mm
#define FORCE_OVERFORCE_PEDS 400.0f  // N

// Leaning: residual force between compressions
#define FORCE_LEANING_THRESHOLD 5.0f  // N (spec §3, recoilAchieved / leaningDetected)
#define RECOIL_RESIDUAL_MAX_MM 5.0f  // mm — residual depth must drop below this for valid recoil (spec §3: <0.5cm)
#define LEANING_PERSISTENCE_MS 200UL  // ms — force must stay > threshold this long

// Recoil: valley depth after peak
#define RECOIL_VALLEY_MAX_MM 5.0f  // mm — below this = good recoil

// Wrist alignment
#define WRIST_ALIGN_WARN_DEG 30.0f  // degrees

// ── Calibration ───────────────────────────────────────────────────────────────
// Number of high-confidence (force, IMU-depth) pairs required before fitting k.
// 20 samples gives the 2× mean-residual outlier filter enough headroom.
// In practice on a real manikin with proper technique, k is fitted by
// compression ~20–25 (≈15–20 seconds). Softer surfaces or weak compressions
// (below 200 N) take longer as those samples are rejected.
#define MAX_CALIBRATION_SAMPLES 20

// When 1, k is permanently locked after the first successful fit and never
// refitted in subsequent sessions. Use this for participant studies so all
// subjects use the same k derived from your pre-study manikin calibration.
// Workflow: run one calibration session with DEPTH_PIPELINE_LOG=1, find the
// first CALIB line where calibK ≠ 1.3500, record that value, then set this
// to 1 and optionally hardcode K_POPULATION_DEFAULT to that value.
// 0 = normal operation (k refits every session from scratch).
#define FORCE_CALIB_LOCK 0



// ── Confidence-based selector configuration ──────────────────────────────────
// Selector design follows Chunk 4 of the literature audit. No direct CPR-paper
// precedent for this exact selector; design draws on general sensor fusion
// principles (Hall & Llinas, Handbook of Multisensor Data Fusion) and per-path
// failure modes documented in Tomlinson 2021, Zhang 2024, Lee/Park 2021.

// IMU per-stroke confidence components, all in [0.0, 1.0]:

// Residual velocity at release (post-stroke). After Aase boundary correction
// captures the residual, |v_residual| below this = high confidence (clean
// integration), above this = low confidence. Literature: Zhang 2024 uses
// pressure-derived end timestamp for detrending; the residual velocity is
// the direct measure of integration drift.
#define IMU_CONF_VRES_GOOD_MS  0.08f   // |v_residual| ≤ 0.08 m/s = full credit
#define IMU_CONF_VRES_FAIL_MS  0.30f   // |v_residual| ≥ 0.30 m/s = zero credit

// Tilt change during stroke (after CF-driven gravity, computed as max-min of
// CF pitch+roll during the COMPRESSING window). Larger tilt = more gravity
// leakage into motion axis (Lee/Park 2021; Song 2015 limitation).
#define IMU_CONF_TILT_GOOD_DEG 13.0f   // normal CPR hand wobble is 5–15°
#define IMU_CONF_TILT_FAIL_DEG 35.0f   // only fail on grossly unstable technique

// Peak depth plausibility. Physiological CPR adult range 20–80 mm (AHA/ERC
// guidelines: target 50–60 mm, lower bound from Hellevuo 2013 complications).
#define IMU_CONF_DEPTH_MIN_MM  20.0f
#define IMU_CONF_DEPTH_MAX_MM  80.0f


// ── IMU axis mounting constants ───────────────────────────────────────────────
// Determined empirically: glove flat on table palm-down, reading dominant axis.
// Palm IMU: gravity on +Y (ay ≈ +846 mg at rest)
// Wrist IMU: gravity on +X (ax ≈ +928 mg at rest)
// These match the physical PCB mounting and never change.
#define IMU_PALM_VERT_AXIS   1      // 0=X, 1=Y, 2=Z
#define IMU_PALM_VERT_SIGN   1.0f   // +1 or -1
#define IMU_WRIST_VERT_AXIS  0      // 0=X, 1=Y, 2=Z
#define IMU_WRIST_VERT_SIGN  1.0f   // +1 or -1


// Force per-stroke confidence components:

// Force operating range. Below 30 N, the force model returns 0 (FORCE_BASELINE_MIN).
// Above 700 N is well past adult overforce (600 N) and likely an ADC glitch.
// In-range = high confidence (subject to calibration status).
#define FORCE_CONF_RANGE_MIN_N 30.0f
#define FORCE_CONF_RANGE_MAX_N 700.0f

// Confidence weight when k-fit is not yet complete (using population mean).
// Per Tomlinson 2007, individual k varies 0.7–2.0 across patients, so the
// population mean has substantial uncertainty. Confidence ≤0.4 in pre-calibration
// phase keeps the selector preferring IMU when both paths are present.
#define FORCE_CONF_PRECALIB    0.4f
#define FORCE_CONF_POSTCALIB   0.9f

// Selector thresholds:

// Disagreement threshold for cross-path checking (mm). Both paths must agree
// within this for "high confidence" output. Literature: Zhang 2024 reports
// CCD detection error ≤5 mm; 8 mm is conservatively above noise floor.
#define SELECTOR_AGREE_THRESHOLD_MM 8.0f

// Hard-fail confidence below which a path is excluded entirely.
#define SELECTOR_HARD_FAIL_CONF 0.20f

// "Reliable" confidence threshold for the agreement check.
#define SELECTOR_RELIABLE_CONF  0.45f

// Threshold for using a stroke to teach force calibration (Change 22).
// Higher than RELIABLE_CONF — we only want excellent IMU strokes teaching k.
#define IMU_CONF_FOR_CALIBRATION 0.55f  // only high-confidence IMU strokes teach k


// Pulse check classification results
#define PULSE_ABSENT 0
#define PULSE_UNCERTAIN 1
#define PULSE_PRESENT 2

// Clicker: fires once when live depth crosses the lower target threshold.
// Hysteresis prevents repeat clicks while the user is at depth. Click can fire
// again only after depth has returned below CLICK_RESET_MM.
#define CLICK_RESET_MM 20.0f  // mm — depth must drop below this to re-arm

#define LIVE_DEPTH_EMA_ALPHA 0.5f  // bar smoothing; lower = smoother but laggier

// ── Compression quality tracking ─────────────────────────────────────────────
// Consecutive bad compressions before audio fires
#define AUDIO_BAD_COMP_THRESHOLD 3
// Consecutive good compressions before "good job" audio
#define AUDIO_GOOD_COMP_THRESHOLD 10
// Cooldown in compressions after "good job"
#define AUDIO_GOOD_COOLDOWN 30
// Min compressions between any quality audio cue
#define AUDIO_MIN_GAP_COMPS 5

// Fatigue: depth trend decline triggers alert
#define FATIGUE_DEPTH_TREND_SAMPLES 5
#define FATIGUE_DECLINE_THRESHOLD_MM 10.0f  // mm decline from first 5 to last 5 comps
#define FATIGUE_MIN_COMPRESSIONS 30

#define FATIGUE_HR_THRESHOLD_BPM 140.0f  // rescuer HR above which fatigue is more likely
#define FATIGUE_HR_DECLINE_FACTOR 0.5f   // depth decline threshold halved when HR is high

// ── Ventilation ───────────────────────────────────────────────────────────────
#define VENTILATION_CYCLE_COMPRESSIONS 30  // app can override via CMD_SET_VENTILATION
#define VENTILATION_BREATHS_EXPECTED 2

// Ventilation window timing
// Ventilation now uses the shared WINDOW_* mechanism above (decision: vent
// behaves exactly like pulse check). These remain only for the grace period,
// which ventilation needs because the rescuer is mid-rhythm when the prompt
// fires (reflex over-shoot must not count as "resumed").
#define VENTILATION_GRACE_MS 2500UL  // reflex comps in this window after the prompt don't count

// ── Pulse check ───────────────────────────────────────────────────────────────
#define PULSE_CHECK_INTERVAL_MS 120000UL  // every 2 min in Emergency

// ── Shared pulse-check / ventilation window behaviour ───────────────────────
// Both windows use the SAME mechanism: stay open until the rescuer either
// resumes (≥ WINDOW_RESUME_COMP_COUNT comps AFTER a real pause) or proves
// non-compliant (≥ WINDOW_NONCOMPLIANT_COMP_COUNT comps with no real pause).
#define WINDOW_PAUSE_COMPLIANT_MS 3000UL  // ≥3 s with no new compression = a real pause = compliant
#define WINDOW_NONCOMPLIANT_COMP_COUNT 5  // this many comps with no pause = non-compliant dismiss
#define WINDOW_RESUME_COMP_COUNT 2        // comps after a real pause that close the window normally
#define WINDOW_RESUME_PROMPT_MS 10000UL   // play "resume compressions" once at this elapsed time
#define WINDOW_MAX_BACKSTOP_MS 100000UL    // hard close even if rescuer never does anything

// Legacy names kept as aliases so existing pulse-check code referencing the
// old identifiers still compiles. Do NOT use these in new code.
#define PULSE_CHECK_DURATION_MS WINDOW_PAUSE_COMPLIANT_MS
#define PULSE_CHECK_MAX_WINDOW_MS WINDOW_MAX_BACKSTOP_MS
#define PULSE_CHECK_RESUME_PROMPT_MS WINDOW_RESUME_PROMPT_MS

// ── Two-minute swap alert ─────────────────────────────────────────────────────
#define TWO_MIN_ALERT_INTERVAL_MS 120000UL  // every 2 min per AHA 2020

// ── Selftest ──────────────────────────────────────────────────────────────────
#define SELFTEST_DELAY_MS 1500UL  // after BLE connect

// ── Button gestures ───────────────────────────────────────────────────────────
#define BTN_DEBOUNCE_MS 50
#define BTN_LONG_PRESS_MS 2000
#define BTN_DOUBLE_TAP_WINDOW_MS 400
#define BTN_TRIPLE_TAP_WINDOW_MS 600

// ── NeoPixel ──────────────────────────────────────────────────────────────────
#define NEO_NUM_LEDS 8
#define NEO_MAX_BRIGHTNESS 50      // 0–255, ~120mA peak at 50
#define NEO_DIM_BRIGHTNESS 15      // 30% — status LED during active session
#define NEO_UPDATE_INTERVAL_MS 50  // 20 Hz update

// LED index assignments
#define NEO_LED_DEPTH_START 0  // LEDs 0–5: depth bar
#define NEO_LED_DEPTH_END 5
#define NEO_LED_RATE 6    // LED 6: rate indicator
#define NEO_LED_STATUS 7  // LED 7: mode/status

// ── Motor ─────────────────────────────────────────────────────────────────────
#define MOTOR_METRONOME_MS 80  // ms ON per metronome tick
#define MOTOR_SHORT_MS 80
#define MOTOR_MEDIUM_MS 150
#define MOTOR_LONG_MS 300
#define MOTOR_VENT_ON_MS 200
#define MOTOR_VENT_OFF_MS 200
#define MOTOR_VENT_REPS 3

// ── Audio ─────────────────────────────────────────────────────────────────────
// Track numbers (DFPlayer 0001.mp3 … 0026.mp3)
#define AUDIO_PRESS_HARDER 1
#define AUDIO_PRESS_FASTER 2
#define AUDIO_SLOW_DOWN 3
#define AUDIO_GOOD_JOB 4
#define AUDIO_EASE_OFF_DEEP 5
#define AUDIO_LIFT_HANDS 6
#define AUDIO_STRAIGHTEN_ARMS 7
#define AUDIO_EASE_FORCE 8
#define AUDIO_GIVE_TWO_BREATHS 9
#define AUDIO_RESUME_COMPRESSIONS 10
#define AUDIO_CHECK_PULSE 11
#define AUDIO_NO_PULSE 12
#define AUDIO_PULSE_DETECTED 13
#define AUDIO_PULSE_UNCERTAIN 14
#define AUDIO_FATIGUE_SWITCH 15
#define AUDIO_TWO_MIN_SWITCH 16
#define AUDIO_SESSION_STARTED 17
#define AUDIO_SESSION_ENDED 18
#define AUDIO_MODE_EMERGENCY 19
#define AUDIO_MODE_TRAINING 20
#define AUDIO_MODE_NOFEEDBACK 21
#define AUDIO_SCENARIO_ADULT 22
#define AUDIO_SCENARIO_PEDS 23
#define AUDIO_GLOVE_READY 24
#define AUDIO_SENSOR_WARNING 25
#define AUDIO_SENSOR_ERROR 26
#define AUDIO_DEPTH_CLICK 27  // short tick played when depth target reached

// Audio priority (higher = more important)
#define AUDIO_PRI_QUALITY 1
#define AUDIO_PRI_MODE_CHANGE 2
#define AUDIO_PRI_FATIGUE 3
#define AUDIO_PRI_SWAP 4
#define AUDIO_PRI_VENTILATION 5
#define AUDIO_PRI_PULSE_CHECK 6
#define AUDIO_PRI_SYSTEM 7
#define AUDIO_PRI_CLICK 1  // same level as quality cues; play only if nothing higher is active

#define DFPLAYER_MIN_VOLUME 0
#define DFPLAYER_MAX_VOLUME 30

// ── Battery ───────────────────────────────────────────────────────────────────
#define BAT_VOLTAGE_MIN 3.0f  // V → 0%
#define BAT_VOLTAGE_MAX 4.2f  // V → 100%
#define BAT_ADC_DIVIDER 2.0f  // voltage divider ratio

// ── LittleFS offline storage ──────────────────────────────────────────────────
#define STORAGE_MAX_SESSIONS 20
#define STORAGE_MAGIC 0xC9A1
#define STORAGE_FORMAT_VERSION 5
#define STORAGE_MIN_COMPRESSIONS_TO_SAVE 3  // reject zero/near-empty sessions
// Max per-session sizes — total max session file ≈ 4400 bytes for a long session.
// 20 slots × 4400 ≈ 88 KB. LittleFS partition is typically ≥ 512 KB.
#define STORAGE_HEADER_SIZE 104       // fixed header (magic + version + summary)
#define STORAGE_MAX_COMPRESSIONS 600  // ≈ 5 min @ 120 BPM, covers median OOHCA duration
#define STORAGE_COMPRESSION_SIZE 20   // bytes per compression (spec §8.2)
#define STORAGE_MAX_VENTILATIONS 20
#define STORAGE_VENTILATION_SIZE 12  // bytes (spec §8.2)
#define STORAGE_MAX_PULSE_CHECKS 10
#define STORAGE_PULSE_CHECK_SIZE 13  // bytes (spec §8.2)
#define STORAGE_MAX_FILE_SIZE (STORAGE_HEADER_SIZE \
                               + STORAGE_MAX_COMPRESSIONS * STORAGE_COMPRESSION_SIZE \
                               + STORAGE_MAX_VENTILATIONS * STORAGE_VENTILATION_SIZE \
                               + STORAGE_MAX_PULSE_CHECKS * STORAGE_PULSE_CHECK_SIZE)
#define STORAGE_CHUNK_PAYLOAD 92  // bytes 4–95 of LOCAL_SESSION_CHUNK (spec §4.11)

// ── FreeRTOS ──────────────────────────────────────────────────────────────────
#define TASK_SENSOR_CORE 1
#define TASK_SENSOR_PRIORITY 5
#define TASK_SENSOR_STACK 8192

#define TASK_COMMS_CORE 0
#define TASK_COMMS_PRIORITY 3
#define TASK_COMMS_STACK 12288

#define EVENT_QUEUE_DEPTH 32

