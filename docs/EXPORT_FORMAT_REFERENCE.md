# Raw Export Format Reference

Read-only. No edits, no commits.

**Provenance disclaimer — read this first.** I did not run the app. CLAUDE.md
forbids running `flutter run`/`flutter build` in this session, and there is
no simulator, hardware glove, or captured real session available to me. So:

- The **filenames, HEADER block, SUMMARY block, and DATA column-header row**
  below are traced literally from `export_service.dart` — every string is
  quoted verbatim from source with a line number, not paraphrased. This part
  is exact.
- The **3 sample DATA rows per file** are hand-built: I picked illustrative
  sensor values and ran them through the exact formatting code (`toFixed`,
  the blank-if-`<=0` ternaries, `_yn`, etc.) that the source actually uses,
  so the *shape* (column count, delimiter placement, decimal precision,
  blank-vs-value logic) is correct — but the *numbers themselves are
  invented*, not captured. Don't feed these specific numbers into any
  statistical check; only rely on them for column positions and formatting.
- If you need real bytes, run one real session through the app and export
  the ZIP — I can review that actual file against what's below once you have
  it.

---

## 1. The ZIP

**Filename pattern** (`export_service.dart:285`, `:294`, identical for
share and download):
```
cpr_raw_${_stamp(d.sessionStart)}.zip
```
`_stamp(dt)` (`export_service.dart:6419-6426`) formats the session's
**local** start time as `YYYYMMDD_HHMM` (24-hour, no seconds). Example for a
session starting 2026-08-30 14:07 local:
```
cpr_raw_20260830_1407.zip
```

**Files inside** (`export_service.dart:1916-1927`, each added *only if that
event list is non-empty* — `hasAny` tracks whether anything was added at
all):
```
compressions.csv     — only if d.compressions is non-empty
rescuer_vitals.csv   — only if d.rescuerVitals is non-empty
ventilations.csv     — only if d.ventilations is non-empty
pulse_checks.csv     — only if d.pulseChecks is non-empty
README.txt           — always added (line 2169), regardless of the above
```

**Protocol-relevant warning.** Your Day-1/Day-8 sessions are a straight
2-minute compression bout (no 30:2 ventilation cycles per `Steps.txt`, and
pulse checks are an Emergency-mode-only feature per the "Do not touch" rule
in CLAUDE.md — training/no-feedback sessions never trigger
`PULSE_CHECK_START`). For those sessions, `d.ventilations` and
`d.pulseChecks` will almost certainly be **empty lists**, which means
`ventilations.csv` and `pulse_checks.csv` **will not exist in the ZIP at
all** — the ZIP will contain only `compressions.csv`, `rescuer_vitals.csv`,
and `README.txt`. Your parser needs to treat those two files as optional,
not assume all four are always present.

**README.txt is not fully traced here** — I read enough of it
(`export_service.dart:1929-1984`) to confirm its "COMMON HEADER FIELDS"
section, but did not trace every glossary line for every file. One
mismatch I did catch: the README's documented header fields
(`export_service.dart:1965`) list an **"Export Type"** field as if it were a
literal `Export Type,<value>` row in every CSV's header block. **It is not.**
None of the four `_build*Csv` functions write any such line — the actual
first line of every file is a plain banner string (e.g. `CPR Assist - Raw
Session Timeline`), not a comma-delimited field. If your parser looks for a
literal `Export Type` row, it won't find one — key off the banner text
instead (it differs per file, see each header below) or off the filename.

---

## 2. Mode field — literal source, not the display label

You specifically asked me not to use the display label — good call, because
there are **two different label mappings** in this codebase and they
disagree:

- `AppMode.label` (`app_providers.dart:157-163`, used in UI chips/history):
  `'Emergency'` / `'Training'` / **`'No-Feedback'`**
- The CSV header block's `Mode` field — an independent inline ternary,
  copy-pasted identically at `export_service.dart:1310` (compressions),
  `:1690` (rescuer vitals), `:1774` (ventilations), `:1830` (pulse checks),
  and again at `:1930-1931` for the README's `modeLabel`:
  ```dart
  d.mode == "emergency" ? "Emergency"
    : d.mode == "training_no_feedback" ? "Training (No Feedback)"
    : "Training"
  ```
  reading `d.mode`, the raw `SessionDetail.mode` string
  (`session_detail.dart:34`, sourced from `AppMode.sessionModeString` at
  `app_providers.dart:148-154`, which is itself the literal value POSTed to
  Postgres's `mode` column).

**The literal `Mode` value written into every CSV header block:**

| `d.mode` (raw) | Literal CSV `Mode` value |
|---|---|
| `emergency` | `Emergency` |
| `training` | `Training` |
| `training_no_feedback` | `Training (No Feedback)` |

Note this is **not** `'No-Feedback'` (the UI label) and **not**
`'training_no_feedback'` (the raw string) — it's the third string,
`'Training (No Feedback)'`, independently written 5 times across the file.
Currently all 5 copies match, but they're 5 hand-copies of the same ternary,
not one shared function — a future edit to one and not the others would
silently desync the CSV export from the UI or from itself. Parse against the
table above, not against `AppMode.label`.

---

## 3. Where the participant note appears

**Label:** `Note` (exact key, capital N, no colon — e.g. `Note,P07-D1-GUIDED`).

**Present in all four files**, each with the identical guard
`if (d.note != null && d.note!.isNotEmpty)`:
- `compressions.csv` — `export_service.dart:1315-1317`
- `rescuer_vitals.csv` — `export_service.dart:1692-1694`
- `ventilations.csv` — `export_service.dart:1776-1778`
- `pulse_checks.csv` — `export_service.dart:1832-1834`

So: **no file omits it** — but the line itself is omitted (not blank, entirely
absent) whenever the note is `null` or an empty string. A parser reading the
header block line-by-line must not assume a fixed line count/position for
`Note` — search for a line starting with `Note,` rather than indexing to a
fixed row.

Value is escaped via `_esc()` (`export_service.dart:6445-6450`): wrapped in
double quotes with internal quotes doubled, **only if** the note contains a
comma, a double quote, or a newline. A code like `P07-D1-GUIDED` has none of
those, so it will appear completely bare: `Note,P07-D1-GUIDED` — no quotes.

---

## 4. Missing vs. zero — `compressions.csv` column-by-column

This is the important one for your bias concern. Traced from
`export_service.dart:1551-1588` (the `mkCompressionRow(...)` call) plus the
two local helpers `fmtNum`/`fmtInt` (`export_service.dart:1395-1401`):
```dart
String fmtNum(double value, {int digits = 1}) =>
    value > 0 ? value.toStringAsFixed(digits) : '';
String fmtInt(int value) => value > 0 ? value.toString() : '';
```

| Column | Blanks when `<= 0`? | Notes |
|---|---|---|
| Row # | No | Always `i+1` |
| Compression # | No | Always `i+1` |
| Peak Time (ms) | Blanks — but on `<= 0`, not really "missing": guarded by `c.peakTimestampMs > 0 ? ... : ''` (`:1555`, via `peakMs`) | A peak at exactly `0` ms (the very first instant of the session) would read as blank, indistinguishable from "no peak detected." Edge case, not a real-world concern in practice. |
| Release Time (ms) | Yes — `valleyMs > 0 ? ... : ''` (`:1556`) | Blank means no recoil/valley was ever locked for this compression (still mid-descent when session ended, or recoil detection failed) — genuinely "not recorded," not zero. |
| Inter-compression Interval (ms) | Yes, structurally, not via `fmtNum` — blank for the first compression (`i == 0`) or if the computed interval is `<= 0` (`:1502-1513`) | |
| Unplanned Pause After (ms) | Yes, structurally — blank unless a gap `> 2.0 s` was detected after this compression (`:1516-1537`) | Blank here means "no pause," which **is** a meaningful zero, not a sensor gap — different semantics from the sensor-value columns below. |
| **Peak Depth (cm)** | **No** — `c.depth.toStringAsFixed(2)` unconditionally (`:1560`), no `> 0` guard anywhere | A true zero-depth reading prints literally as `0.00`. This is the one depth-like column that never hides a zero. |
| Depth Target Met | No | Always `YES`/`NO` |
| Estimated Effective Depth (cm) | **Yes** — `c.effectiveDepth > 0 ? ... : ''` (`:1562-1564`) | |
| Downstroke Duration (ms) | **Yes** — via `fmtInt` (`:1566`) | |
| Recoil Depth (cm) | **Yes** — `c.residualLoadDepthCm > 0 ? ... : ''` (`:1568-1570`) | |
| Recoil Duration (ms) | Yes, structurally — blank unless `valleyTimestampMs > peakMs > 0` (`:1540-1543`) | |
| Recoil Target Met | Yes, structurally — blank unless `hasRecoilData` (a compound OR of 4 conditions, `:1495-1499`), else `YES`/`NO` | Not a `<=0` pattern on itself, but gated by other columns' zero-checks |
| Leaning Detected | Same gate as Recoil Target Met | |
| **Force (N)** | **Yes** — `fmtNum(c.peakForce > 0 ? c.peakForce : c.force, digits: 1)` (`:1575`) | Two-stage: falls back to `c.force` if `peakForce <= 0`, but if *both* are `<= 0` the cell is blank, not `0.0`. |
| Over Force Detected | No | Always `YES`/`NO` |
| **Instant Rate (BPM)** | **Yes** — `fmtNum(instantRate, digits: 1)` (`:1578`) | Always blank for the very first compression in the file (no prior IBI to compute from) |
| **Rolling Rate (BPM)** | **Yes** — `fmtNum(rollingRate, digits: 1)` (`:1579`) | |
| Rate Target Met | No | Always `YES`/`NO` — evaluated against `rateForTarget = instantRate > 0 ? instantRate : rollingRate`, which itself can be `0` (out of target) even though the printed Instant/Rolling Rate cells are blank |
| **Wrist Alignment (deg)** | **No** — `c.wristAlignmentAngle.toStringAsFixed(1)` unconditionally (`:1582`) | A true `0.0°` reading prints as `0.0`, not blank — this and the two below are the posture columns that never hide a zero |
| **Wrist Flexion (deg)** | **No** — unconditional (`:1583`) | Can be negative; `toStringAsFixed` prints the sign |
| **Axis Deviation (deg)** | **No** — unconditional (`:1584`) | |
| Posture Target Met | No | Always `YES`/`NO` |
| All Targets Met | No | Always `YES`/`NO` |

**Bottom line for your parser:** treat a blank as "not recorded" for
Effective Depth, Downstroke Duration, Recoil Depth, Force, Instant Rate, and
Rolling Rate — a mean computed by `pandas`-style `NaN`-skipping on those
columns is correct. **Peak Depth, Wrist Alignment, Wrist Flexion, and Axis
Deviation never blank on zero** — a blank cell in those four columns cannot
occur from the formatting logic at all (row always populates them), so if
you ever see one blank there, something upstream failed to serialize the row
entirely, not a legitimate sensor zero.

The same `<=0`-blanks-else-formats pattern recurs in the other three files;
I flagged the two most bias-relevant instances while tracing them: in
`rescuer_vitals.csv`, Heart Rate / SpO2 / Wrist Temperature blank on `<= 0`,
but **Signal Quality, RMSSD, Perfusion Index, and Fatigue Score do not** —
wait, correction, re-checked exactly: `rmssd` and `rescuerPi` **do** blank on
`<=0` (`export_service.dart:1748-1749`, inline ternary, not through a named
helper), while **Signal Quality and Fatigue Score never blank**
(`:1747`, `:1750`, printed as raw unconditional ints) — so a genuine
`fatigueScore == 0` at session start prints as literal `0`, not blank. In
`pulse_checks.csv`, `detectedBpm` and `patientSpO2` blank on `<=0`
(`:1887`, `:1890`), but `confidence`, `perfusionIndex`, `detectorACount`,
`detectorBCount` are all raw unconditional ints (`:1888-1889`, `:1891-1892`)
— a `perfusionIndex == 0` prints as `0`, not blank.

---

## 5. Units and encoding — `compressions.csv`

| Column | Unit | Suffix in the cell itself |
|---|---|---|
| Row # / Compression # | count | bare integer |
| Peak Time / Release Time / Inter-compression Interval / Unplanned Pause After / Downstroke Duration / Recoil Duration | milliseconds | bare integer (unit is in the **header name**, e.g. `Peak Time (ms)`; the cell itself is just `850`, never `850 ms`) |
| Peak Depth / Estimated Effective Depth / Recoil Depth | centimeters | bare decimal, 2 places (unit in header name, e.g. `Peak Depth (cm)`) |
| Force | newtons | bare decimal, 1 place (`Force (N)`) |
| Instant Rate / Rolling Rate | BPM | bare decimal, 1 place |
| Wrist Alignment / Wrist Flexion / Axis Deviation | degrees | bare decimal, 1 place (`(deg)` in header, degree symbol `°` appears only inside the **Posture Target Met header text**, e.g. `Posture Target Met (Align ≤15° / Flex ≤10°)` — never in a data cell) |
| Depth/Rate/Recoil/Posture/Over-Force/All Targets Met, Leaning Detected | boolean | literal `YES` / `NO` — never `1`/`0`, never `%` |

**No column uses a `%` sign or unit suffix inside the data cell itself** in
`compressions.csv` — every unit lives only in the column header text. (The
`%`-suffixed values you'll see are in the SUMMARY block, e.g. `CCF (%),94.2`
— the header there also carries the unit, the value is still bare.)

**Encoding:** UTF-8 **with a leading BOM** (`0xEF 0xBB 0xBF`), added by
`_csvBytes()` (`export_service.dart:6452-6457`) specifically because
"Excel on Windows... defaults to Windows-1252 and garbles °, -, >=, etc."
— confirmed: the header row does contain literal `≤`/`≥`/`°` characters, so
your parser must decode as UTF-8 and strip/expect the BOM as the first 3
bytes of the file. (Confirm whether `_csvBytes` is actually the write path
used for the ZIP entries specifically — I traced it as the general CSV-byte
helper in this file; if you want I can re-verify the exact call site that
feeds `addCsv()` uses it rather than plain `utf8.encode`.) Actually — checked:
`addCsv()` (`export_service.dart:1910-1911`) calls `utf8.encode(content)`
directly, **not** `_csvBytes()` — so the ZIP's internal CSVs are **plain
UTF-8, no BOM**. (`_csvBytes` with the BOM is used elsewhere, for
standalone single-CSV share/download, not for the files packed inside the
ZIP.) This matters: if you were assuming a BOM on the ZIP's CSVs, don't —
strip that assumption for the ZIP path specifically.

**Line ending:** `StringBuffer.writeln()` in Dart appends a bare `\n` (LF),
not `\r\n` — Dart does not do platform-dependent line-ending translation on
`writeln`, and nothing in this code path calls `Platform.lineTerminator` or
similar. Every line in every CSV, including on a Windows-built app, ends in
LF only.

---

## 6. CCF target — `ccfTarget` grep results

Only **one** definition of a variable actually named `ccfTarget` exists in
the whole file:
```
export_service.dart:327:    const ccfTarget = '≥60%';
```
used once, at `export_service.dart:555`, in a PDF report row: `row3('CCF',
ccfTarget, pctValue(ccfPct))`.

**Your `'≥80%'` sighting is real, but it isn't CCF — it's a different
metric.** `export_service.dart:3978`:
```dart
target: 'target ≥ 80%',
```
sits inside a **"Avg recoil"** tile (`export_service.dart:3974-3986`, label:
`'Avg recoil'`), part of the single-session PDF's target-tile row —
completely separate code from the CCF row. There's a second, independent CCF
target string elsewhere in the same file too, consistent with the `60%`
value: `export_service.dart:3693`:
```dart
_Row('CCF (Hands-On Time)', '${(s.handsOnRatio * 100).round()}%', note: 'Target ≥ 60%'),
```

**So: no CCF inconsistency exists.** Every CCF-labeled target in this file
says `60%` (`ccfTarget` at :327/:555, and the `_Row` note at :3693). The
`80%` you found is the recoil-percentage target on an adjacent tile in the
same PDF layout, not a second value for CCF. If your copy of the file truly
has `80%` written against something labeled `CCF` rather than `Avg recoil`,
that copy differs from what's on disk now — worth a `diff` against a fresh
`git show HEAD:.../export_service.dart` before assuming it's a live bug.

---

## 7. Timestamp formats

**`Date & Time` in every header block** — `_fmtDt()`
(`export_service.dart:6459-6471`):
```
YYYY-MM-DD HH:MM:SS
```
in the device's **local** time zone (`dt.toLocal()`), 24-hour, zero-padded,
**no `T` separator, no `Z`, no milliseconds, no UTC offset**. Example:
`2026-08-30 14:07:00`. The doc comment above it is explicit about why: "no T,
no Z, no milliseconds... Excel auto-detects this as a date."

**`Peak Time (ms)` / `Release Time (ms)` in the DATA rows** — these are
**not** timestamps in the epoch sense at all. They're `CompressionEvent.
peakTimestampMs` / `.valleyTimestampMs`, documented in
`compression_event.dart:104-111` as "Session ms when peak depth was locked...
Absolute timestamp from session start" — i.e., **milliseconds elapsed since
that session's `SESSION_START`**, not Unix epoch, not wall-clock. Same for
every other `(ms)` column in all four files (`Elapsed Time (ms)` in
rescuer-vitals/ventilations/pulse-checks is the same session-relative clock,
sourced from `v.timestampMs` / `p.timestampMs`, both documented as
"session ms"). To reconstruct wall-clock time for any DATA row, you'd add the
row's `(ms)` value to the header block's `Date & Time` (after parsing it as
local time and converting to whatever epoch representation you're working
in) — the export gives you no other anchor.

---

## Literal reconstructions

Everything above the `DATA` line is exact source text with the placeholders
filled in for one illustrative session: `Session ID = 142`, `sessionStart =
2026-08-30 14:07:00` local, `mode = training`, `scenario = standard_adult`,
`note = "P07-D1-GUIDED"`, `duration = 120 s`. Everything from the column
header row down (the DATA header row itself is exact; the 3 rows under it
are invented, format-correct sample values — see the disclaimer at the top).

### `compressions.csv`

```
CPR Assist - Raw Session Timeline
,
Session ID,142
Date & Time,2026-08-30 14:07:00
Mode,Training
Scenario,Adult,Correct Depth Target,5.0-6.0 cm
Note,P07-D1-GUIDED
,
SUMMARY
Duration,2:00
Total Compressions,170
Time to First Compression (s),0.81
Correct Depth Compressions,132
Correct Rate Compressions,145
Correct Recoil Compressions,150
Avg Depth (cm),5.60
Avg Rate (BPM),108.3
CCF (%),94.2
No-Flow Intervals,2
No-Flow Time (s),6.4
Total Unplanned Pauses,1
Total Unplanned Pause Time (s),3.1
,
DATA
Row #,Compression #,Peak Time (ms),Release Time (ms),Inter-compression Interval (ms),Unplanned Pause After (ms),Peak Depth (cm),Depth Target Met (5.0-6.0 cm),Estimated Effective Depth (cm),Downstroke Duration (ms),Recoil Depth (cm),Recoil Duration (ms),Recoil Target Met (Full Recoil),Leaning Detected,Force (N),Over Force Detected,Instant Rate (BPM),Rolling Rate (BPM),Rate Target Met (100-120 BPM),Wrist Alignment (deg),Wrist Flexion (deg),Axis Deviation (deg),Posture Target Met (Align ≤15° / Flex ≤10°),All Targets Met
1,1,850,1120,,,5.80,YES,5.75,180,0.20,270,YES,NO,420.0,NO,,,NO,8.2,-3.1,2.0,YES,NO
2,2,1450,1720,600,,6.30,NO,6.25,170,0.15,270,YES,NO,480.0,NO,100.0,98.5,YES,17.5,4.0,3.5,NO,NO
3,3,2080,2340,630,,5.50,YES,5.48,160,0.60,260,NO,YES,410.0,NO,95.2,97.8,NO,10.0,-2.0,1.5,YES,NO
```

Notice row 1 has two independent blank-pairs (`Inter-compression Interval` +
`Unplanned Pause After` both blank because it's the first compression; then
`Instant Rate` + `Rolling Rate` both blank for the same reason) — that's
where the `,,,` runs come from. Don't mistake three consecutive commas for a
malformed row; count columns against the header, not against comma-run
length.

### `rescuer_vitals.csv`

```
CPR Assist - Raw Rescuer Vitals
,
Session ID,142
Date & Time,2026-08-30 14:07:00
Mode,Training
Scenario,Adult
Note,P07-D1-GUIDED
,
SUMMARY
Duration,2:00
Total Vital Snapshots,24
Start Heart Rate (BPM),88.4
End Heart Rate (BPM),95.0
Heart Rate Change (BPM),+6.6
Start Rescuer SpO2 (%),97.2
End Rescuer SpO2 (%),96.5
Rescuer SpO2 Change (%),-0.7
Start Rescuer Wrist Temp (C),32.15
End Rescuer Wrist Temp (C),33.10
Rescuer Wrist Temp Change (C),+0.95
Avg Heart Rate (BPM),91.6
Avg Rescuer SpO2 (%),97.0
Avg Rescuer Wrist Temp (C),32.60
Avg RMSSD (ms),44.8
Avg Perfusion Index (0-100),5.6
Avg Fatigue Score,9.4
Max Fatigue Score,22
,
DATA
Row #,Elapsed Time (ms),Context,Rescuer Heart Rate (BPM),Rescuer SpO2 (%),Rescuer Wrist Temperature (°C),Rescuer Signal Quality (0-100),RMSSD (ms),Rescuer Perfusion Index (0-100),Estimated Fatigue Score (0-100)
1,5000,active_cpr,88.4,97.2,32.15,82,54,6,0
2,10000,active_cpr,92.1,96.8,32.40,79,48,6,8
3,15000,ventilation,93.5,97.0,32.55,75,45,5,12
```

Note `Scenario` here says `Adult` (`export_service.dart:1691`), not
`Standard Adult` — see next file.

**Also note:** `RescuerVitalSnapshot.humidity` exists in the Dart model
(`rescuer_vital_snapshot.dart:38`) and in the Postgres
`session_rescuer_vitals.humidity` column, but the CSV `DATA` header
(`export_service.dart:1724-1735`) has **no humidity column at all** — it is
silently dropped from this export despite being captured and stored
everywhere else in the pipeline.

**`Context` column values** are one of five literals from
`contextForMs()` (`export_service.dart:1654-1682`):
`ventilation`, `pulse_check`, `no_compressions`, `before_first_compression`,
`after_last_compression`, `active_cpr` — exactly these strings, lower-case,
underscored.

### `ventilations.csv`

```
CPR Assist - Raw Ventilation Windows
,
Session ID,142
Date & Time,2026-08-30 14:07:00
Mode,Training
Scenario,Standard Adult
Note,P07-D1-GUIDED
,
SUMMARY
Duration,2:00
Total Ventilation Windows,3
Ventilation Target Met Windows,2
Ventilation Compliance (%),66.7
Avg Window Duration (s),4.18
,
DATA
Row #,Elapsed Time (ms),30:2 Cycle #,Window Duration (s),Ventilation Timing Target Met
1,34000,1,4.20,YES
2,64000,2,3.85,YES
3,94000,3,4.50,NO
```

**Flag this precisely, since you're writing a parser:** this file's
`Scenario` line literally says **`Standard Adult`**
(`export_service.dart:1775`), while `compressions.csv` and
`rescuer_vitals.csv` say plain **`Adult`** (`:1312`, `:1691`). Same true
value, two different literal strings depending on which file you're
reading. `pulse_checks.csv` matches ventilations (`Standard Adult`,
`:1831`). If your parser normalizes `Scenario` across files, branch on
`.contains("Pediatric")` rather than an exact string match, or you'll get a
false mismatch between `compressions.csv` and the other three.

### `pulse_checks.csv`

Realistically **will not appear** for your protocol sessions (see the ZIP
section above — pulse checks are Emergency-only). Format traced anyway,
mode set to `Emergency` in this example since that's the only mode where
this file is ever non-empty in practice:

```
CPR Assist - Raw Pulse Check Results
,
Session ID,142
Date & Time,2026-08-30 14:07:00
Mode,Emergency
Scenario,Standard Adult
Note,P07-D1-GUIDED
,
SUMMARY
Duration,2:00
Final Result,NO ROSC
Total Pulse Checks,3
Pulse Present,1
Pulse Uncertain,1
Pulse Absent,1
,
DATA
Row #,Elapsed Time (ms),Pulse Check #,Pulse Result,Pulse Result Code,Estimated Patient Pulse Rate (BPM),Signal Quality (0-100),Perfusion Index (0-100),Patient SpO2 (%),Raw IR Peak Count,Confirmed Beat Count,Beat Agreement Ratio,Rescuer Decision,PPG Sample Count,PPG Waveform
1,42000,1,PRESENT,2,76.5,88,4,98.2,14,13,0.93,Continue CPR,3,0.1234;0.1500;0.1789
2,102000,2,UNCERTAIN,1,,45,1,,9,3,0.33,,2,0.0980;0.1020
3,162000,3,ABSENT,0,,20,0,,6,0,0.00,Stop CPR,2,0.0500;0.0480
```

Two things worth flagging here:

1. **Column-7 name vs. field mismatch.** The header says `Signal Quality
   (0-100)` but the value written into that cell is `p.confidence`
   (`export_service.dart:1888`) — the `PulseCheckEvent.confidence` field,
   not any field literally named "signal quality." Whether that's the
   intended semantic (detection confidence *as* the signal-quality proxy) or
   a mislabeled column, I can't tell from the export code alone — it's
   accurate to say the header and the underlying Dart field name disagree.
2. **`PPG Waveform` is semicolon-delimited, not comma-delimited**
   (`export_service.dart:1896`, `.join(';')`), and each sample is
   `toStringAsFixed(4)` — plain digits and a decimal point, so `_esc()`
   never quotes it (no comma/quote/newline ever appears in it). Split that
   final field on `;`, not `,`, and expect it to be the very last column
   with no trailing comma-based ambiguity. Real waveforms will have far more
   than 2–3 samples — a 3-second pulse-check window at typical PPG sample
   rates will run into the hundreds; the row above is truncated for
   readability only.
