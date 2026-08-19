# CPR Assist Glove — working rules

## Repo layout
- `firmware/` — ESP32 Arduino/C++
- `CPR-Assist-App/cpr_assist/` — Flutter app (package com.roueva.cpr_assist)
- backend — Node.js/Express + PostgreSQL (Railway)

## How to work
- Surgical edits only. Never rewrite a whole file unless explicitly asked.
- Read the actual source before proposing anything. Grep before asserting.
- One batch at a time. Wait for confirmation before the next.
- Run `flutter analyze` after every Flutter batch. Zero new issues.

## Flutter design tokens — hard rules, no exceptions
Single import: `import 'package:cpr_assist/core/core.dart'`
- No `Color(0xFF...)` or `Colors.*` → `AppColors.*`
- No raw numbers for padding/radius/size → `AppSpacing.*`
- No inline `TextStyle(...)` → `AppTypography.*()`
- No inline `BoxDecoration(...)` → `AppDecorations.*()`
- No `ScaffoldMessenger` in widgets → `UIHelper.*`
- No inline `showDialog()` → `AppDialogs.*`
- No `Navigator.of(context).push(...)` → `context.push()`
- No `MediaQuery.sizeOf(context)` → `context.screenWidth` / `context.screenHeight`
- No magic numbers → `AppConstants.*` / `AEDMapUIConstants.*`
- Every screen pads for the phone bottom navigation bar
If a token doesn't exist yet, add it to the core file first, then use it.

## Auth rules
- Login is NOT required to use the app.
- Emergency mode: fully usable logged out. Never interrupt an active session.
  Prompt once, non-blocking, only after the session ends.
- Training mode: requires login. `AppDialogs.confirmSwitchToTraining` gated by
  `AppDialogs.promptLogin`. Dismissed → stay in Emergency.
- No login wall on launch, AED map, guide screen, or anywhere else.
- Account/profile screens handle the unauthenticated state gracefully.

## Locked — do not redesign
- Force model is exponential: FORCE_BASELINE_V=0.4008f, FORCE_EXP_A=114.882626f,
  FORCE_EXP_B=1.056205f, FORCE_EXP_C=5.212799f.

## Clinical facts
- The glove NEVER prompts the rescuer to pause for a pulse check.
  A circulation check opens passively when the rescuer has already paused AND
  the fingertip sensor detects carotid skin contact. Minimum 2 min between checks.
- Rhythm check (AED/ECG) ≠ circulation check (manual palpation). Distinct.
- CCF benchmark is ≥60% per AHA 2025, not ≥80%.