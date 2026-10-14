# Work Plan

Six sessions. In order. One Claude Code session each — do not batch, context rot
makes the later items unreliable.

Every audit is two passes: read-only first, I review the findings, then apply only
what I approve. Never audit and edit in the same pass.

Project rules live in `/CLAUDE.md` and load automatically. Don't restate them.

\---

## 0\. Health check

Dart and packages were updated. Nothing below is trustworthy until the analyzer is
clean.

```
Health check only. Report findings, fix nothing.

Run and report full output:
  flutter --version
  flutter pub get
  flutter analyze
  flutter pub outdated

Then report:
1. Every analyzer error and warning, grouped by file, with counts.
2. Every deprecation warning, and which package version introduced it.
3. Any dependency now behind a major version.
4. Whether flutter build apk --debug still succeeds.

Do not fix anything. I want to see the damage first.
```

**Exit:** `flutter analyze` clean. Fix errors before session 1 — a broken analyzer
makes every later audit unreliable.

\---

## 1\. Firmware signal dictionary

The most important session. The table is the deliverable, and building it *is* the
audit. It goes into the paper's methods section afterwards.

```
Read-only audit of the ESP32 firmware. Do not edit any file.

Goal: a signal dictionary. One row per quantity the firmware produces and streams.

Files: config.h, shared\_state.h, depth.cpp/.h, force.cpp/.h, imu.cpp/.h,
max30102.cpp/.h, max30205.cpp/.h, gxht30.cpp/.h, battery.cpp/.h,
ble\_manager.cpp/.h, cpr\_glove.ino
Cross-reference: CPR\_Assist\_BLE\_Spec\_v3\_1.md, ble\_data\_processor.dart

Table columns:
| Firmware variable | Unit | Derivation (ONE sentence) | BLE byte(s) | App field | UI label |

Rules:
- Read the actual source for every row. Never infer from a name or a comment.
- Names disagree across the four columns -> mark DEFECT, say which is wrong.
- Cannot state the derivation in one plain sentence -> mark DEFECT.
- Written but never read -> mark DEAD.
- BLE byte carries data the spec calls reserved -> mark UNDOCUMENTED.

Then list separately:
A. Every dead variable, with file:line for the declaration and every write.
B. Every function whose name does not match what it does.
C. Every sentinel (9999.0f etc) and whether each comparison is paired with a
   write that can actually produce it.
D. Every magic number in depth.cpp and force.cpp not defined in config.h.

Write to firmware/SIGNALS.md
```

**Sanity check the report.** These are already known. If the report misses them,
it didn't read the files — rerun it.

* `valleyDepth` (`depth.cpp:766–771`) is a force-to-depth proxy, not the IMU depth
minimum. Called a depth in firmware, spec, app, thesis. → `residualLoadDepthCm`.
* `\_prevValleyDepth` — written `depth.cpp:279`, `:360`, `:516`, read nowhere.
* Five bytes the spec calls reserved but firmware writes: 52–55 `valleyDepth`,
86 `inVentilationWindow`, 102–105 `lastPeakDepthCm`, 106 `lastPeakConfidence`,
107 `lastPeakDepthSource`. Firmware and app agree; the spec is behind.
* `ble\_manager.cpp:185` says "overwrite reserved bytes" for diag mode. They aren't
reserved. Works only because the app guards `diagActive` at five parse sites.
Best fix: a dedicated `0x0D DIAG\_FRAME` EVENT\_CHANNEL packet.
* `depthFinalizeLastValley()` (`depth.cpp:353`) — its own comment at `:365–368`
admits the per-compression event was already emitted, so `correctRecoil` is one
short every session. Fix it or state it in the methods.
* `depth.cpp:359` missing the sentinel guard its twin at `:515` has.
* Spec `0x04 PULSE\_CHECK\_START` and the thesis both still claim pulse checks are
two minutes apart. That constraint was removed.
* `ble\_connection.dart:1056`, `:1060` — dead commented-out stubs.

Apply pass:

```
Apply pass. Using firmware/SIGNALS.md, fix only the rows I marked APPROVED.
Minimal change per row — rename or delete, do not restructure.
Show me the diff after each file.
```

**Exit:** `SIGNALS.md` committed, every row either clean or explained.

\---

## 2\. Navigation

```
Rewrite the AED navigation camera to a single-driver model.
Files: navigation\_controller.dart, location\_service.dart, app\_constants.dart

PROBLEM: two camera drivers fight. \_updateCameraToLocation (:253) animates on GPS
over 800ms. \_updateCameraWithCompass (:377) animates on compass. Both call
animateCamera on the same controller, and each call cancels the in-flight
animation. Compass fires more often than GPS, so it repeatedly kills the position
animation. That is the jerkiness.

FIX — do this, not a patch:
- Hold \_targetPosition (written by GPS) and \_targetBearing (written by compass) as
  state. Neither writer touches the camera.
- One Ticker at 60fps interpolates current -> target for position and bearing,
  then calls moveCamera. Never animateCamera.
- Bearing interpolation uses the shortest arc and normalizes to 0-360.

Same pass:
1. Delete \_predictionTimer — declared :26, cancelled :251-252, never started.
2. \_updateSpeedAndBearing (:234) computes neither. It calls \_calculateDistance and
   discards the result. Rename to \_updateLocationHistory.
3. \_interpolateBearing (:370) can return negative. from=1,to=350 gives -0.65.
   Normalize the return.
4. The gate at :351 uses .abs() with no +/-180 wrap, unlike \_interpolateBearing
   directly below it. Use the same wrapped delta in both.
5. \_handleCompassAccuracy (:364) logs and does nothing. Delete or wire a prompt.

location\_service.dart:
6. ~~Remove the `location` package entirely, keep `geolocator`.~~ **Checked
   2026-08-31 — don't.** All three `loc.Location()` call sites
   (`location\_service.dart:61`, `aed\_location\_controller.dart:412`,
   `aed\_map\_widget.dart:266`) do the identical single thing:
   `requestService()`, the native inline "Turn on Location?" system dialog.
   `geolocator` has no equivalent — its only option, `openLocationSettings()`,
   sends the user to the Settings app instead. Permissions and the GPS stream
   are already 100% `geolocator`; `location` isn't duplicating either one.
   Keep both packages.
7. AppConstants.locationFilterHigh is dead: passed :313, discarded because the
   navigating branch hardcodes distanceFilter: 0 at :281.
8. :274 computes `accuracy` and logs "HIGH", but the navigating branch ignores it
   and uses bestForNavigation. Only the else branch reads it.
9. \_upgradeToTargetAccuracy cancels at :267 then awaits at :269. Two rapid calls
   both assign \_positionSubscription; the first leaks. Add a re-entrancy guard.

Show me the diff for navigation\_controller.dart before touching location\_service.
```

**Exit:** tested walking outdoors, not on an emulator. Camera follows without
stutter · no rotation jitter standing still · no spin at the 0°/360° boundary ·
pan shows the recenter button and stops following · recenter resumes · GPS lost
then regained doesn't jump.

\---

## 3\. AED availability

The Dart and JS parsers are **not** duplicates. JS builds and refreshes the rules
cache; Dart evaluates rules at runtime. Do not merge them.

```
Read-only audit. Do not edit.
Files: availabilityParser.js, aedService.js, parse\_aed\_data.py,
availability\_parser.dart, aed\_service.dart, cache\_service.dart

1. availabilityParser.js:191-267 spawns a Python interpreter in production,
   trying python3.11 -> python3 -> python. Trace what happens on Railway if no
   interpreter is present. Does refresh fail loudly or silently?
2. When does the rules cache actually refresh? App start, timer, map open, never?
   Trace it end to end and state the answer.
3. If refresh fails, does the app show stale data as if current? Is there any
   "last updated" notion?
4. availability\_parser.dart:89-110 falls through to cache when the backend is
   unreachable. With no cache at all — first launch, offline — what does the map
   show?
5. \_parseCache (:47) — does it invalidate on a day boundary? A cached "Open" from
   23:55 must not be returned at 00:05.
6. Opening hours are local Greek time. Confirm evaluation uses local time, not
   UTC. Check the DST switch.
7. \_isGreekHoliday (:380) and \_calculateOrthodoxEaster (:411) exist only in Dart.
   Confirm that is correct (runtime evaluation, not a cached rule) and say so.

Write to docs/AVAILABILITY\_AUDIT.md
```

**Exit:** refresh trigger documented, stale state visible in the UI, Python
dependency either removed or made to fail loudly.

\---

## 4\. Study materials

Questionnaires, demographics, and consent forms are in the repo.

```
Read-only review. Do not edit.
Files: C:\\Users\\evaro\\Documents\\Studies\\BME\_studies\\Thesis\\Code\_thesis\\3 Validation\\3. User Testing\\\_User Testing

For each instrument, report:
1. What it measures, and whether it is a validated instrument or custom-written.
   Name the source for validated ones (NASA-TLX, SUS, etc).
2. Every question that is leading, double-barrelled, or ambiguous — quote it and
   say why.
3. Response scales: consistent points and anchors across instruments? Any
   mismatch between scale direction and how it will be scored?
4. Demographics: anything collected that the analysis will not use, and anything
   the analysis needs that is not collected.
5. Consent form vs ethics approval EHDE 99737/2026 — do the stated data handling,
   retention, and withdrawal terms match?
6. Anything identifying that should be pseudonymised at collection.
7. Order effects: is anything asked before the session that primes the answer
   after it?

Write to docs/STUDY\_MATERIALS\_REVIEW.md
```

**Exit:** every instrument sourced or justified, consent matches approval.

\---

## 5\. UI redesigns + violations

**After the study, not before.** These screens work now. Rewriting them before
testing means participants use days-old code and you debug UI instead of
collecting data. The study is what the paper needs.

Fold the token violations into each redesign — you're rewriting the files anyway,
so a separate sweep would only create conflicts.

* **Guide** — `guide\_screen.dart` (2215 lines), full hub redesign. Deepest nesting
in the codebase; check scroll on a mid-range phone. Verify content against AHA
2025. Violations: `:88`, `:121`, `:134` raw hex → named overlay colours in
`app\_colors.dart`; `:352`, `:434`, `:1113` `Color(0x26000000)` →
`AppColors.shadowSoft`; `:1154` → `AppColors.scrimStrong`; `:476`
`Colors.transparent`; `:47`, `:554` → `context.safeBottom`.
* **Achievements** — unlock conditions must match the grading definitions. Guest
state. `:31` → `context.safeBottom`.
* **Quiz** — verify answers against AHA 2025. `:179`, `:401` → `context.safeBottom`.
* **Certificates** — `certificate\_service.dart` (114 lines). Guest or absent name.
* **Export PDF** — the chart canvas smear bug is CLOSED, confirmed 2026-08-30
(26 save / 26 restore, balanced — every `setFillColor`/`setStrokeColor` call
individually wrapped, no orphans). Still open: add a header comment declaring
the `pw.` token exemption, or a future audit re-flags it and someone breaks
the PDF. Test with a 1-compression and a 500-compression session.

Violations elsewhere:

* `aed\_cluster\_renderer.dart:79` `Colors.white`
* `Colors.black12` — `leaderboard\_screen.dart:144`, `:2147`,
`session\_history.dart:676`, `session\_compare\_screen.dart:195`
* `Colors.transparent` — `app\_dialogs.dart` (8 sites), `export\_bottom\_sheet.dart:52, 68`, `simulation\_112\_dialog.dart:72`, `app\_theme.dart:66`,
`leaderboard\_screen.dart:160, 1108, 2163`, `session\_history.dart:1097, 1105`,
`session\_compare\_screen.dart:214`. Add `AppColors.transparent` and sweep, so the
rule becomes grep-enforceable.
* `Navigator.` — `glove\_diagnostic\_sheet.dart:443`, `universal\_header.dart:383`,
`:489`. `main\_navigation.dart:55` is probably the legitimate
capture-before-async-gap pattern — verify, then comment it.
* `leaderboard\_screen.dart:1403` → `chipContext.screenWidth`
* `session\_compare\_screen.dart:2558` → `context.screenHeight \* 0.75`
* Friends tab is a dead placeholder with a non-functional search bar
(`leaderboard\_screen.dart:658–695`). Hide it or make it honest before the study.
* Known issue, not urgent — `session\_history.dart`'s `\_apply()` sort switch:
on the "All" mode tab, `case 'grade\_low'`/`'grade\_high'` compares `totalGrade`
across a mixed list, so Emergency sessions' `0.0` sentinel participates in the
sort ordering. No incorrect value is ever displayed — the card branches on
`isEmergency` first — but Emergency sessions always sort as lowest-grade.
Decide whether to exclude them from grade sorts or leave as-is.

Then add CI so none of it returns. All five must output nothing:

```
grep -rP '(?<!\[A-Za-z])Colors\\.' lib/ --include=\*.dart | grep -v '/core/'
grep -rn 'Color(0x'          lib/ --include=\*.dart | grep -v app\_colors.dart
grep -rn 'MediaQuery'        lib/ --include=\*.dart | grep -v app\_extensions.dart
grep -rn 'Navigator\\.'       lib/ --include=\*.dart | grep -v -e app\_extensions.dart -e main.dart
grep -rn 'ScaffoldMessenger' lib/ --include=\*.dart | grep -v ui\_helper.dart
```

\---

## 6\. Study gate

Nothing optional. Run immediately before the first participant.

**Firmware flashed and verified** (left-hand study glove —
`CPR-Assist-Firmware-LeftHand/config.h`; the right-hand variant is
currently a bench-only build, `FORCE\_CALIB\_LOCK=0` by its own design —
not part of this gate unless that changes):

* \[ ] `STUDY\_BUILD = 1` — `config.h:278` (currently 0). Its own `#error`
  guard requires the five log flags below to already be 0 — flip this
  *last*, after the CALIB-line hardware check in `CORRECTIONS.md` (which
  needs `DEPTH\_PIPELINE\_LOG` live to read), not before.
* \[ ] `FORCE\_CALIB\_LOCK = 1` — `config.h:370` (already 1)
* \[ ] `K\_STUDY\_LOCKED = 3.15f` — `config.h:208` (already 3.15 on this
  glove; 3.45 is the right-hand glove's value, don't check against it)
* \[ ] `DEPTH\_PIPELINE\_LOG = 0` — `config.h:264` (currently 1 — leave at 1
  until the CALIB-line check passes, see `STUDY\_BUILD` above)
* \[ ] `DEPTH\_SELECTOR\_LOG = 0` — `config.h:268` (currently 1, same
  sequencing)
* \[ ] `BLE\_DEBUG\_SERIAL = 0` — `config.h:259` (already 0)
* \[ ] `FORCE\_TEST\_LOG = 0`, `IMU\_TEST\_LOG = 0` — `config.h:272`, `:276`
  (already 0, 0)

`MANIKIN\_CALIBRATION\_LOG` no longer exists — renamed `DEPTH\_PIPELINE\_LOG`
(`config.h:264`). Fix any checklist still naming it.

**Hardware (needs the physical glove):**

* \[ ] Contact threshold measured
* \[ ] PPG waveform verified against a reference
* \[ ] Compression-detection chatter test at the threshold boundary
* \[ ] Full run: glove → app → backend → export

**App:**

* \[ ] Navigation tested walking outdoors
* \[x] Friends tab resolved — honest "Coming Soon" placeholder with a
  disabled search bar now (`leaderboard\_screen.dart`), not the earlier
  dead non-functional one. Confirmed in code 2026-10-14.
* \[ ] `dev\_preview\_screen.dart` reachable only in debug builds — the menu
  entry is gated behind `kDebugMode` (`account\_menu.dart:318`), so it's
  unreachable via navigation in a release build. That is *not* the same as
  "excluded from the release build" — the file still compiles into the
  release binary as dead code. Decide if gated-unreachable is sufficient or
  if you want it stripped from release builds entirely.
* \[ ] No debug screens reachable — confirmed `dev\_preview\_screen.dart` is
  the only `kDebugMode`-gated screen in `lib/`. `glove\_diagnostic\_sheet.dart`
  is production glove-diagnostic functionality, not a debug screen, and
  isn't gated — leave it reachable.

**Known bugs (fix before the study):**

`CORRECTIONS.md` is the authoritative pre-study gate — firmware/hardware
corrections and their validation state live there, not here. This list is
app-side bugs only; the two are not merged, since `CORRECTIONS.md` gets
archived once the study starts and this file doesn't.

* [x] M1 — `SessionLocalStorage.migrateLegacyUnscopedData()`: index was
persisted once after the loop while per-key writes/removes committed
inside it, so a partial failure orphaned migrated sessions permanently.
Fixed — confirmed in code 2026-10-14: the index is now written *before*
the per-key removal loop (`session\_local\_storage.dart:270` vs `:271-273`),
so a crash mid-loop leaves migrated records reachable and retry is
idempotent (comment at `:268-269` states this explicitly). The per-record
`jsonDecode` is now inside its own try/catch (`:257-265`); the outer
`jsonDecode(raw)` for the legacy key list itself is still unguarded
directly but the whole function is wrapped in an outer try/catch
(`:247-278`) that logs and bails instead of crashing.
* R2 — `flutter\_foreground\_task` creates a second `FlutterEngine`
unconditionally on service start (`ForegroundTask.kt:41-49`), so two engines
are live during any BLE CPR session. Geolocator counts engines process-wide
and refuses to stop its native location service while a second one is
attached, leaving the OS location indicator on after navigation is
cancelled. Dart-side subscription does cancel correctly, so no data is
collected. **Confirm on a profile build with no glove connected before
fixing** — the observed log line may have been a hot-reload artifact.
* [x] A10 — `AEDRoutingCoordinator.isUsingCachedLocation` and
`.isLocationTooOld` were plain fields, cached mirrors of
`AEDLocationController` state, synced only inside `\_handleLocationUpdate`.
Anything reading them between location updates — e.g.
`showNavigationPreviewForAED`'s `shouldShowGray` — saw a stale snapshot, not
live state. Replaced both with injected callbacks
(`final bool Function() isUsingCachedLocation;`) reading the controller
directly; dead `\_isLocationTooOld(state)` removed. Fixed 2026-08-28.
* [x] A11 — `startNavigation`'s mid-navigation fresh GPS fix bypassed
`markRealGPSFix`, leaving `hasRealGPSFix` false despite a confirmed fix.
Fixed 2026-08-28.

**Do before the study, not after:**
Capture one real session's raw BLE bytes, freeze as a test fixture, assert the
parsed output and the final grade. Highest-value item here. It turns every fix
above into a permanent check instead of a one-time observation.

