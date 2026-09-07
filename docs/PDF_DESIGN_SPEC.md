# PDF Design Spec — App Design Language vs. export_service.dart

Reference doc, not a narrative. Section 1 documents the design system as it is
actually used across the six session-results/compare screens. Section 2
documents what `export_service.dart` does today and where it diverges.
Inventory only — no implementation plan.

Sources read in full:
`session_results.dart`, `session_results_layout.dart`,
`session_results_charts.dart`, `session_results_training_tabs.dart`,
`session_compare_screen.dart`, `session_compare_charts.dart`,
`app_typography.dart`, `app_spacing.dart`, `app_colors.dart`,
`app_decorations.dart` (all under `CPR-Assist-App/cpr_assist/lib/`, theme
files under `lib/core/theme/`, screens under
`lib/features/training/widgets/`).

Two supporting widgets used constantly on these screens —
`CprChartCard`/`CprScrollableChart` (from `cpr_chart_helpers.dart`) and
`_ExpandableSectionCard`/`_NoteCard` (from `session_results_shared.dart`) —
are outside the ten files above and were **not** read for this doc. Where
their internals matter, this doc describes only what's observable from call
sites (title/subtitle/legend/dropdown arguments) and flags the gap.

---

## Section 1 — App Design Language

### 1.1 Type scale

All styles are `AppTypography` semantic builders (`app_typography.dart:55-165`),
themselves built on two primitive families — `inter()` (default) and
`poppins()` (nav, some headline moments) — via `TextStyle` factories, never
raw `TextStyle(...)`.

| Style | Size/weight/letter-spacing (default) | Role on these screens |
|---|---|---|
| `numericDisplay()` | 32 / w800 / -1.0 (size overridden per use) | The single "big number" idiom: grade % in the hero ring (`session_results_layout.dart:246`, size dynamic 24-48 via `lerpDouble`), grade % in `_GradeInfoDialog`'s ring (size 26, `:911`), sub-metric tile % (size 13, `:1137`), hero stat tile value (size 26, `session_results_training_tabs.dart:242`), grid stat tile value (size 19, `:292`), BPM readout in the emergency outcome card (size 22-60, `session_results_layout.dart:539`). Always the largest, boldest element in its container — this is the "headline metric" token. |
| `heading()` | 18 / w800 / -0.3 (size often overridden to 16) | Screen-level titles: AppBar title (`session_results.dart:332`, size 16), "Your Grade" dialog title (`session_results_layout.dart:874`, size 16), Compare Sessions AppBar (`session_compare_screen.dart:143`, size 16). |
| `subheading()` | 15 / w600 / -0.1 | Section labels: grade-info dialog section labels ("Formula", "Your 3 biggest factors", `:839`), category tile titles ("Depth"/"Rate"/"Recoil", `session_results_training_tabs.dart:1035`, size 13), legend-card session grade (`session_compare_screen.dart:367`). |
| `body()` / `bodyMedium()` / `bodyBold()` | 14 / w400·w500·w700 / height 1.5 | Paragraph text and value-emphasis text: grade dialog intro copy (`body`, size 13), category-tile value/notes (`bodyBold`, size 11-13), motivational line under the grade ring uses `subheading` not `body` (see above) — `bodyBold` is the "emphasized inline value" token, e.g. `_TileRow` value column (`:1101`). |
| `label()` | 12 / w600 / letter-spacing 0.3 | Compact all-purpose label: legend-card session number ("S1", `session_compare_screen.dart:340`), tab labels on the compare screen (`:219`), zone-bar target label uses `badge` not `label` (see below) — `label` is reached for wherever `caption` (below) would read too light. |
| `badge()` | 11 / w800 / letter-spacing 1.2 | Uppercase/tracked micro-text: mode chip text ("Pediatric"/"Adult", `session_results.dart:350`), sub-ring labels ("DEPTH"/"RATE"/"RECOIL", `session_results_layout.dart:720`), tab-bar labels (`:657`), timeline tip pills (`session_results_training_tabs.dart:1971`), zone-bar target label (`:319`). The "small shouty" token — always paired with a bright/semantic color, never plain text-secondary. |
| `caption()` | 11 / w400 / height 1.4 | The default secondary/metadata token: AppBar subtitle date (`session_results.dart:334`), grid-tile label (`session_results_training_tabs.dart:280`), timeline row subtitle (`:1957`), legend-card date (`session_compare_screen.dart:346`). Highest-frequency style on both screens by a wide margin. |
| `poppins(...)` (primitive, used directly) | caller-specified | Reserved for a few "louder" one-offs outside the semantic set: emergency outcome headline (size 20-22, w700, `session_results_layout.dart:507`), sub-ring percentage (size 13-18, w700, `:711`), "NEW PERSONAL BEST" banner text (size 13, w800, `:1292`). |

Sizes are frequently **overridden per call** via the builder's optional
`size:` param (e.g. `AppTypography.caption()` always defaults to 11, but call
sites pass 9, 10, 13 freely) — the *style* (weight/letter-spacing/color
default) is the stable contract, not the literal pixel size. No screen ever
constructs a bare `TextStyle(...)`; every text style traces to an
`AppTypography` call.

### 1.2 Spacing rhythm

Every gap, padding, and inset on these six screens is an `AppSpacing`
constant — zero raw numeric `SizedBox`/`EdgeInsets` values for spacing
(icon/dot pixel sizes like `width: 6, height: 6` for a bullet dot, or `30`/`38`
for timeline dot diameters, are treated as one-off decorative sizes, not
spacing, and are the only literals that appear).

Base scale (`app_spacing.dart:16-22`): `xxs=2, xs=4, sm=8, md=16, lg=24,
xl=32, xxl=48` — a clean ×2 progression from 2 up to 16, then ×1.5/×1.33
after. Observed usage on these screens:

| Token | px | Typical role here |
|---|---|---|
| `xxs` (2) | Tightest gaps: icon-to-badge margin (`session_results.dart:341`), value-to-note baseline gap. |
| `xs` (4) | Icon-to-label gap within a stat tile, chip vertical padding, inter-line gaps inside a card (label → value). |
| `sm` (8) | The default "related items" gap: hero-tile row gap, grid spacing (`_OverviewGrid`'s `mainAxisSpacing`/`crossAxisSpacing`), legend-strip card gap, tab-bar chip padding. |
| `md` (16) | The default **screen/card outer padding** — every tab body (`Padding(padding: const EdgeInsets.all(AppSpacing.md), ...)`), the AppBar-to-content margin, card internal padding for larger cards. This is the single most common value on both screens. |
| `lg` (24) | Grade-card internal padding (`session_results_layout.dart:393`), dialog padding. |
| `xl` (32) | End-of-tab bottom spacer (`session_results_training_tabs.dart:532`), "no-feedback" card offset. |
| `xxl` (48) | One place only: emergency outcome card's collapse animation offset (`session_results_layout.dart:574`). |

Component-named tokens (`app_spacing.dart:28-73`) used here: `cardRadius`
(14, the default card corner), `cardRadiusSm` (8), `cardRadiusMd` (10),
`cardRadiusLg` (20, hero/grade cards), `chipRadius`/`buttonRadiusLg` (999,
fully-rounded pills), `iconSm`/`iconMd` (18/24), `headerHeight` (60, AppBar
toolbar height). The rhythm is consistent and intentional — a value is
picked by *semantic slot* (card padding vs. icon size vs. radius), not by
eyeballing a number.

### 1.3 Card anatomy

Three distinct card species recur:

**1. Standard white card** (`AppDecorations.card()`, `app_decorations.dart:13-28`)
— radius `cardRadius` (14) by default, background white, no border, a single
soft `BoxShadow` (10 blur, `Offset(0,2)`, default 5% black opacity, callers
sometimes raise it to 10%). Used for the tab-content shell
(`session_results_layout.dart:183-189`, shadow only — the shape itself is a
plain `Container` decoration) and the compare-screen legend card
(`_LegendCard`, `session_compare_screen.dart:323`, shadow opacity 0.10, plus
a conditional 1.5px colored border when active).

**2. Tinted flat card** (`AppDecorations.tintedCard()`, `:31-37`) — radius
`cardRadius`, `screenBgGrey` fill, **no border, no shadow**. This is the
"quiet" card species — used for grid stat tiles (`_GridStatTile`,
`session_results_training_tabs.dart:274`) and category tiles
(`_CategoryTile`, `:1025`, with `cardRadiusMd` override).

**3. Dark solid card** (`AppDecorations.gradeCard()`/`primaryAltCard()`/
`primaryGradientCard()`, various `cprCardBg`/`primaryAlt`/`primary` fills) —
radius `cardRadiusLg` (20) for hero moments, `cardRadius` (14) for smaller
ones, no border, sometimes a shadow (`primaryAltCard` has one, `gradeCard`
does not). Used for the collapsing grade card (`session_results_layout.dart:384-388`),
hero stat tiles (`session_results_training_tabs.dart:233-235`), the
emergency outcome card.

All three species share: circular (never per-corner unless deliberately a
"top accent" strip) `BorderRadius`, padding always an `AppSpacing` value
(`sm`/`md`/`lg` depending on card size), and — critically — **borders and
shadows are mutually exclusive design choices per species**, not layered
together except in the one explicit `accentCard()`/legend-active-border
cases.

### 1.4 Stat tile / metric tile construction

Two recurring tile patterns, both `Column`s, both `crossAxisAlignment.start`:

**Grid stat tile** (`_GridStatTile`, `session_results_training_tabs.dart:253-327`):
```
Container(padding: EdgeInsets.symmetric(h: sm, v: sm+xs), decoration: tintedCard())
  Column(start):
    Text(label, caption(textSecondary))
    SizedBox(height: xxs)
    Row(baseline-aligned):
      Text(value, numericDisplay(size:19))
      [optional] SizedBox(width: xs) + Flexible(Text(note, caption(disabled)))
    [optional zone bar]:
      SizedBox(height: xs)
      SizedBox(height:16, child: CustomPaint(_ZoneBarPainter))
      SizedBox(height: xxs)
      Center(Text(targetLabel, badge(size:9, disabled)))
```
The zone-bar (`_ZoneBarPainter`, `:350-434`) is a custom-painted horizontal
range indicator: a 4px-thick grey track (full width, `AppColors.divider`),
a 4px target-zone overlay at 22% success-color opacity, boundary tick marks
(1.5px, 60% success opacity), and a 5px-radius filled dot (2px white core)
at the current value's position — colored by the tile's semantic state
color, with a 35%-opacity connector line back to the nearest zone boundary
when out of range.

**Hero stat tile** (`_HeroStatTile`, `:220-251`): icon (`iconMd`, on-dark) →
`xs` gap → value (`numericDisplay(26)`) → `xxs` gap → label (`caption`,
on-dark). Used in pairs (`Duration`/`Compressions`) at the top of the
Overview tab, on the dark `gradeCard()` background.

Both patterns put the **numeric value in `numericDisplay`, everything else
in `caption`** — that two-style pairing (one loud, one quiet, no middle
ground) is the tile idiom across the whole app, repeated in `_SubMetricTile`
(`session_results_layout.dart:1092-1157`) and the compare screen's stat rows.

### 1.5 Section header treatment

There is no single `_sectionTitle`-style widget shared by all screens (the
"expandable section" pattern — `_ExpandableSectionCard`, defined in
`session_results_shared.dart`, not read for this doc — supplies
icon+iconColor+title+subtitle+expand/collapse for Metrics-tab cards; its
exact internal typography wasn't verified against source). Where a bare
label needs an accent, the idiom is a **3px-wide, 12-32px-tall colored bar**
immediately left of the text (`_gradeInfoSectionLabel`,
`session_results_layout.dart:828-842`; `_buildWeightRow`'s highlight bar,
`:1043-1051`), text styled `subheading(size:12)`, gap `xs` between bar and
text. This accent-bar-plus-label pattern is the closest thing to a
consistent "section header" convention on these screens.

### 1.6 Chart conventions

All charts on both screens go through a shared `CprChartCard` +
`CprScrollableChart` pair (`cpr_chart_helpers.dart`, not read in full for
this doc — the following is everything observable from ~15 call sites
across `session_results_charts.dart` and `session_compare_charts.dart`):

- **Target band fill**: `HorizontalRangeAnnotation`, color = semantic color
  (`success`/`warning`) at **8-10% opacity** (`.withValues(alpha: 0.08)` on
  compare charts, `0.09-0.10` on single-session charts — effectively the
  same value, minor drift between the two files).
- **Guide/target lines**: `HorizontalLine`, semantic color at **50% opacity**
  (60% for the one wrist-alignment/HR-danger line), `strokeWidth: 1`,
  dashed (`dashArray: [4,4]` typical, `[3,5]`/`[6,4]` for a couple of
  distinguished lines).
- **Dots**: `FlDotCirclePainter`, radius **2.5-3px**, `strokeWidth: 1`,
  white stroke (or translucent-white for de-emphasized low-signal points).
  Color varies by state — in-target = success, near/borderline = warning,
  far-out = error — decided per-chart by a `dotBuilder` callback keyed to
  the metric's own target range, not a fixed 3-state palette. Dots only
  render below a data-density threshold (`showDotsWhen: (w) => w < 20-30`
  seconds of visible window) — dense series show line-only.
- **Line weight**: not explicitly set at call sites (default from
  `CprScrollableChart`, not verified — no `strokeWidth` param appears at
  any of the ~15 call sites read).
- **Left axis**: `reservedSize` 25-32px depending on chart (28 typical),
  labels via `AppTypography.caption()`, with the in-target tick **bolded
  and recolored to the semantic accent** while other ticks stay
  `textDisabled` (`session_results_charts.dart:373-383`, `:483-495`).
- **Legend**: only on compare charts (multi-session) — `_compareLegendDots`
  (`session_compare_charts.dart:658-677`): `Wrap(spacing: md, runSpacing: xxs)`
  of `[8×8 dot via AppDecorations.sessionDot(color), SizedBox(width: xxs), Text(caption)]`
  per session. Single-session charts carry no in-chart legend — the
  `CprChartCard.title`/`subtitle` strings state the convention in prose
  instead (e.g. "Green band = 100–120 cpm").
- **Caption/subtitle style**: chart title and subtitle are plain
  `CprChartCard` constructor strings, not independently styled at the call
  site — their typography lives inside `CprChartCard` (not read).

### 1.7 Color roles as actually used

Beyond the raw palette (`app_colors.dart`), the roles actually exercised on
these six screens:

- **`success`/`warning`/`error`** (light-surface semantic triad) — the
  workhorse for *all* in/near/out-of-target coloring: zone-bar dots, chart
  bands and guides, category-tile scores, grid-tile dot colors. `success`
  = in target, `warning` = borderline/needs improvement, `error` = clearly
  out of range or unplanned pause. This exact 3-tier mapping repeats at
  every threshold decision across both screens.
- **`feedbackGood`/`feedbackWarn`/`feedbackBad`/`feedbackInfo`** — the
  *dark-surface* counterparts, reserved for text/icons/rings painted
  directly on `cprCardBg`/`primaryAlt` (grade ring color, sub-ring color,
  outcome-card accent). Never mixed with the light-surface triad on the
  same surface.
- **`primary`/`primaryAlt`** — brand identity, not a state: icons, active
  tab indicator, bookend timeline dots (session start/end always
  `primaryAlt` regardless of outcome), legend accents.
  **`primaryAlt.withValues(alpha: 0.3)`** doubles as the bookend timeline
  dot's glow shadow color.
  **`primaryLight`/`screenBgGrey`** — the two "quiet background" tints;
  `tintedCard()` uses `screenBgGrey`, chip/icon-circle backgrounds use
  `primaryLight` — a role distinction (card body vs. small accent chip)
  that isn't obvious from the color names alone.
- **`textDisabled`** — doubles as both "disabled UI state" *and* "no
  data / not applicable" (e.g. a stat's dot color when its zone bar has no
  value, or `_ttfColor` for zero time-to-first). Not just for disabled
  controls — it's the app's "neutral/unknown" role too.
  **`divider`** — reused as the zone-bar track color and the timeline
  connector-line color, beyond its literal "divider" name.
- **`pbGoldDark`/`pbGoldLight`/`pbGoldText`** — exclusively the personal-best
  banner and (reused, at 80% alpha) rescuer-swap timeline dots — a
  "special achievement" role, not used for any grading state.
- **`compareSlot2/3/4`** (`primary` doubles as slot 1) — the only place a
  color's role is purely positional/arbitrary (which session in a
  comparison), unrelated to any metric's meaning.

---

## Section 2 — What export_service.dart Does Instead

`export_service.dart` — `CPR-Assist-App/cpr_assist/lib/features/training/services/export_service.dart`,
6734 lines.

### 2.1 Type scale

**Zero** `AppTypography` references (`grep -c "AppTypography\."` → 0). Every
text style is a bare `pw.TextStyle(font: ..., fontSize: N, color: ...)`
constructed inline.

Actual counts (not the ~130-site/12-size figure quoted — verified by grep):

- `fontSize:` appears **117** times.
- **17 distinct values**: `8` (36×), `7` (29×), `9` (19×), `10` (6×), `6`
  (4×), `11` (4×), `20` (3×), `13` (3×), `6.5` (2×), `22` (2×), `14` (2×),
  `8.5` (1×), `32` (1×), `28` (1×), `16` (1×), `15` (1×), `12` (1×).

No weight/letter-spacing convention parallels `AppTypography`'s semantic
builders — `pw.FontWeight`/letter-spacing are set ad hoc per call, so two
sites using the same `fontSize: 8` may differ in weight or spacing with no
shared name tying them together the way `caption()` or `label()` do. The
three fonts loaded (`roboto`, `robotoBold`, `robotoMedium`,
`_buildSingleSessionPdf:2187-2190`) stand in for Inter/Poppins — a
reasonable PDF-safe substitution, but the *role* mapping (which weight for
a value vs. a label) isn't centralized anywhere the way it is in
`app_typography.dart`.

### 2.2 Spacing rhythm

No `AppSpacing` references. Padding is raw `pw.EdgeInsets` numerics
throughout; sampled distinct values (from `EdgeInsets.all/symmetric/only/fromLTRB`
arguments): **12** (23×), **6** (15×), **10** (15×), **8** (12×), **5** (9×),
**4** (9×), **14** (9×), **2** (6×), **3** (5×), **18** (5×), **32** (4×),
**28** (4×), **16** (4×), **0** (3×), **20** (2×), plus one-offs at 48, 40,
36, 22, 1 — **20 distinct values** with no visible progression, versus the
app's clean `2/4/8/16/24/32/48` doubling scale. Some values do coincide
with `AppSpacing` tokens by chance (8=`sm`, 16=`md`, 4=`xs`) but there's no
mechanism enforcing that coincidence, and values like 5, 3, 14, 18, 22
have no `AppSpacing` counterpart at all.

`SizedBox(height/width: N)` spacers follow the same pattern — no grep
performed here specifically, but every spacer call site seen while reading
the chart/timeline code (`export_service.dart:2345`, `:2369`, etc.) uses a
bare literal.

### 2.3 Card / container construction

`pw.BoxDecoration` usage:

- **Radius**: `BorderRadius.circular(N)` at **13 distinct values** — `8`
  (9×), `4` (9×), `3` (6×), `10` (6×), `12` (3×), `999`/`99` (pill-style,
  2× each), `1.5`, `6`, `5`, `2`, `14`, `1` (1× each). `8` and `10` line up
  with `cardRadiusSm`/`cardRadiusMd`; `14` (used once) matches `cardRadius`;
  but the file has no equivalent of `cardRadiusLg` (20) anywhere, and the
  4/3/2/1/1.5/5/6 values have no app-side counterpart — they read as
  chart-specific micro-decorations (accent bars, dividers) rather than
  card radii, but there's no naming to distinguish "this is a card" from
  "this is a hairline accent" the way `AppSpacing.cardRadius` vs.
  `AppSpacing.radiusXs` does.
- **Border**: `width: 0.5` (14×) and `width: 0.8` (2×) — thin hairline
  borders throughout, generally on `_kDivider`. This part *does* echo the
  app's restrained divider treatment, just via a bare literal (`0.5`)
  instead of an `AppDecorations`/`AppSpacing` call.
- **Background fill**: sourced from the bridged `_k*` constants (see 2.5),
  so card fills are color-correct even without a shared decoration
  builder — but there's no `export_service.dart` equivalent of
  `AppDecorations.card()`/`tintedCard()`; every card's shadow-vs-border
  choice, fill color, and radius is decided independently at each call
  site rather than drawn from a small fixed set of "card species."

### 2.4 Chart conventions — `_buildTimeChart`/`_paintPlot` (`:6091-6455` approx.) vs. app charts

| Aspect | App (`CprScrollableChart` call sites) | `export_service.dart` (`_paintPlot`) |
|---|---|---|
| Gridlines | Not explicitly set by callers (default, unverified) | Explicit: `setLineWidth(0.4)`, `_kDivider`, drawn for every Y tick (`:6329`) |
| Target band fill | 8-10% opacity | `_kSuccess.shade(0.12)` fill, `.shade(0.5)` edge line at `width: 0.5` — roughly double the app's band opacity, plus an edge stroke the app's `HorizontalRangeAnnotation` doesn't have |
| Guide/dashed lines | 50-60% opacity, `strokeWidth: 1`, dash `[4,4]`/`[6,4]`/`[3,5]` | `setLineWidth(0.6)`, dash drawn manually as 4pt-on/7pt-off segments (`:6375-6383`) — comparable weight and intent, different dash cadence |
| Line weight | Not set at call sites (app default) | `_ChartLine.width` defaults to **1.2** (`:6670-6673`), explicit per-series |
| Area fill under line | Not used on app charts (bands serve that role) | `l.color.shade(0.08)` fill under the first line only (`:6391`) — an idiom the app doesn't have |
| Dot size | radius 2.5-3px | `drawEllipse(..., 2.0, 2.0)` — radius 2.0, slightly smaller |
| Dot state coloring | per-chart `dotBuilder` keyed to that metric's own target | per-chart `dotColor` callback, same idea — e.g. force chart flags `f > 600` red, posture chart flags per-line thresholds — structurally parallel to the app's approach |
| Legend | dot+label `Wrap`, single-session charts have none (prose subtitle instead) | Every PDF chart has an explicit legend row (swatch + `AppTypography`-less caption text) — the PDF is *more* legend-heavy than the single-session app screens, since a static page can't carry a live tooltip |
| Caption/helper text | Chart title/subtitle only, styled inside `CprChartCard` (unverified) | A separate styled caption **box** below the legend (`_kBrandLight.shade(0.3)` background, `:6293`) explaining how to read the chart — the app has no equivalent; the PDF caption box is a print-specific affordance for a reader with no live tooltip |
| Chart card wrapper | `CprChartCard` (unverified internals) | `pw.Container(padding: EdgeInsets.fromLTRB(12,12,12,8), decoration: BoxDecoration(color: _kBgGrey, borderRadius: circular(8)))` (`:6176-6181`) — radius 8 matches `cardRadiusSm`, not the app's usual chart-card treatment (`AppDecorations.chartArea()` uses `cardRadiusMd`=10, rounded top corners only) |

Net: the PDF's chart painter is a **structurally faithful reimplementation**
of the same idea (band + dashed guides + colored dots + legend), built
independently against the low-level `PdfGraphics` canvas rather than
against `CprScrollableChart` (which can't run outside Flutter) — the
opacities, dash cadences, and dot radii are all close-but-not-identical to
the app's, because they were tuned by eye against the PDF renderer rather
than copied from a shared constant.

### 2.5 Color usage — already aligned

Confirmed: colors are bridged, not hardcoded. `_pdf()` helper
(`export_service.dart:56-60`) converts a Flutter `Color` to `PdfColor`, and
20 `_k*` constants (`:62-84`) wrap the same `AppColors` tokens the app
screens use — `_kBrandBlue = _pdf(AppColors.primary)`,
`_kSuccess = _pdf(AppColors.success)`, `_kTextPrimary = _pdf(AppColors.textPrimary)`,
etc. `AppColors.` appears 26 times, `_pdf(` 27 times, in the constant-
definition block only — chart/card code always goes through the `_k*`
names afterward. This is the one category with no gap: a color change in
`app_colors.dart` propagates to the PDF automatically. (The PDF also uses
`.shade(0.NN)` — the `pdf` package's own opacity/lightness helper — as a
one-off substitute for `AppColors`' `.withValues(alpha:)`, since `PdfColor`
isn't a Flutter `Color`; this is a mechanical necessity, not a design
divergence.)

### 2.6 Punch-list — sizes/values needing a token mapping

**Font sizes → `AppTypography` role** (by frequency; a given `fontSize: N`
site maps to different roles depending on context, so this groups by
*likely* role, not a 1:1 rule):

| export_service.dart fontSize | Closest app equivalent | Likely role(s) observed |
|---|---|---|
| 6, 6.5 | *(none — below `caption`'s 11)* | axis tick labels, chart micro-text |
| 7 | *(none)* | chart legend text, timeline subtitle |
| 8, 8.5 | ~`caption()` (11, but used at 8-9 elsewhere via override) | captions, table cells, secondary metadata |
| 9 | `badge(size:9)` (exact match — app uses 9 for sub-ring/zone-bar labels) | section labels, small values |
| 10 | between `caption`/`label` | table headers, mid-weight labels |
| 11 | `caption()`/`label()` default (11 exact) | body-adjacent text |
| 12 | `label()` default (12 exact) | — |
| 13 | `subheading(size:13)` (app uses 13 for category-tile titles) | card titles |
| 14 | `body()`/`heading()` variants | body text |
| 15, 16 | `subheading()` default (15) / `heading(size:16)` (app's AppBar title size) | headings |
| 20, 22 | between `heading()` (18) and `appTitle()` (22, exact match at 22) | hero numbers, page title |
| 28, 32 | `displayLg()` (28, exact) / `numericDisplay()` default (32, exact) | grade %, hero metric |

**Padding/spacing → `AppSpacing` token**:

| export_service.dart value | AppSpacing token |
|---|---|
| 2 | `xxs` |
| 4 | `xs` |
| 8 | `sm` |
| 16 | `md` |
| 32 | `xl` |
| 3, 5, 6, 10, 12, 14, 18, 20, 22, 28, 36, 40, 48 | no exact token — nearest is either a rounding choice (12→`sm`+`xs`, 20→between `sm*2.5` and `lg`) or a genuinely PDF-specific value (28 = `kLeftGutter`, the chart's Y-axis label column width, not a spacing concept in the app at all) |

**Radius → `AppSpacing` token**:

| export_service.dart value | AppSpacing token |
|---|---|
| 8 | `cardRadiusSm` |
| 10 | `cardRadiusMd` |
| 14 | `cardRadius` |
| 999, 99 | `chipRadius`/`buttonRadiusLg` (999 exact; 99 is a near-pill the app doesn't use) |
| 1, 1.5, 2, 3, 4, 5, 6, 12 | no token — `12` is close to `inputRadius`/`buttonRadius` but used here for unrelated shapes; the rest are sub-`radiusXs`(2)-scale accents with no named equivalent |
