# CPR Assist

Wearable CPR feedback system. ESP32 firmware + Flutter/Riverpod app +
Node/PostgreSQL backend on Railway, over BLE. MSc thesis, AUTH. A user study with
ethics approval is pending hardware validation, so correctness outranks features.

Work plan and session prompts: `docs/TASKS.md`. Read it when I name a task.

## How to work

- Read the actual file before claiming anything about it. Never infer behaviour
  from a filename, a comment, or an instruction earlier in this session.
- Surgical edits. Do not rewrite a file unless I ask for a rewrite.
- Show me the diff for one file before moving to the next.
- If you think something in "Do not touch" is wrong, say so and stop. Do not fix it.
- Audits are read-only. Write findings to a file, edit nothing, wait for approval.
- Do not add features, abstractions, or error handling I did not ask for.
- Never run flutter run or flutter build. I run those in my own terminal.
  Long-lived builds get killed by the session supervisor and leave orphaned
  JVMs behind. Edit the files, show me the diff, and stop.
- Any change to a BLE-facing field must update firmware/SIGNALS.md in the
  same commit.
- A new BLE field is a FIVE-layer change: firmware, parser, Flutter model,
  Postgres column and INSERT, and the read-back SELECT. Trace it all the way
  to a re-fetched session in the same session. Stopping early produces a
  field that looks implemented and records nothing.

## Do not touch

These are final and correct by design. Report a suspected problem; never fix one.

- Grading — `session_service.dart:240–259`. No force-safety term, no fatigue
  penalty, no timed_endurance scenario. Over-force and fatigue are standalone
  metrics and live warnings only.
- The confidence-based depth selector in `depth.cpp`. It replaced fixed-weight
  fusion. Population defaults are intentional.
- The exponential force model in `force.cpp`.
- Posture from the palm IMU only. `wristAlignmentAngle` = palm pitch,
  `compressionAxisDeviation` = palm roll. The wrist IMU is not fused.
- Patient vitals gated by `pulseCheckActive` — `ble_manager.cpp:141`.
- Pulse check gating: passive contact-plus-pause only. The glove never prompts the
  rescuer to pause. Low SQI → Uncertain, never Absent.

When code and `CPR_Assist_BLE_Spec_v3_1.md` disagree, the code is authoritative.
Fix the spec.

## Design tokens — no exceptions

Single import: `import 'package:cpr_assist/core/core.dart'`

| Never | Use |
|---|---|
| `Color(0xFF...)`, `Colors.xxx` | `AppColors.xxx` |
| raw numbers for padding/radius/size | `AppSpacing.xxx` |
| inline `TextStyle(...)` | `AppTypography.xxx()` |
| inline `BoxDecoration(...)` | `AppDecorations.xxx()` |
| `ScaffoldMessenger` in widgets | `UIHelper.xxx()` |
| inline `showDialog()` | `AppDialogs.xxx()` |
| `Navigator.of(context)` | `context.push()` / `context.pop()` |
| `MediaQuery.sizeOf(context).width` | `context.screenWidth` |
| `MediaQuery.paddingOf(context).bottom` | `context.safeBottom` |
| magic numbers | `AppConstants.xxx`, `AEDMapUIConstants.xxx` |

If a token doesn't exist yet, add it to the core file first, then use it.
Every screen must clear the phone's bottom navigation bar.

**Exception:** `export_service.dart` uses `pw.TextStyle` / `pw.BoxDecoration` from
the pdf package. Flutter tokens cannot apply there. Colours already bridge via
`_pdf(AppColors.x)`. Leave it alone.

## Auth

Login is not required to use the app.

- **Emergency mode** — no login gate, ever. Never interrupt an active session.
  After it ends, prompt once, non-blocking.
- **Training mode** — requires login. On switch attempt while logged out, show
  `AppDialogs.confirmSwitchToTraining` blocked by `AppDialogs.promptLogin`.
  Dismissing leaves the user in Emergency.
- No login prompt anywhere else. Not on launch, the AED map, or the guide.
- Account and profile screens work logged out.

## Stack notes

- Flutter/Riverpod, `flutter_blue_plus`, `google_maps_flutter`, `geolocator`.
  **No go_router** — `context.push` wraps `Navigator` + `MaterialPageRoute`
  (`app_extensions.dart:118`).
- Firmware: Arduino/C++, ESP32, FreeRTOS. Two LSM6DSOX IMUs, FlexiForce A401,
  MAX30102 ×2, MAX30205, GXHT30, via a TCA I2C mux.
- Backend: Express + PostgreSQL on Railway. Timestamps are TIMESTAMPTZ.

## Thesis prose style

Short plain sentences. No em dashes. No semicolons as connectors. No bullet points
or lists in body prose. Requirement-first paragraph openings. Flowing prose.