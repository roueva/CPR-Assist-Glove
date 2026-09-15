# AED availability pipeline audit

Read-only. No source files were changed to produce this document. Line
numbers are current as of this audit (2026-09-16); some have drifted a few
lines from the numbers in `TASKS.md` due to unrelated edits since it was
written — the referenced functions are unchanged.

Files read in full:
`CPR-Assist-Server/services/availabilityParser.js`,
`CPR-Assist-Server/services/aedService.js`,
`CPR-Assist-Server/routes/aed.js`,
`CPR-Assist-Server/scripts/parse_aed_data.py`,
`CPR-Assist-Server/server.js` (startup/cron section),
`CPR-Assist-App/.../widgets/availability_parser.dart`,
`CPR-Assist-App/.../services/aed_service.dart`,
`CPR-Assist-App/.../services/cache_service.dart` (relevant sections),
`CPR-Assist-App/cpr_assist/pubspec.yaml`.

The Dart and JS parsers are confirmed **not duplicates**, per the task
framing: `availabilityParser.js`/`parse_aed_data.py` build and refresh the
*rules* cache (server-side, LLM-parsed, stored in Postgres
`availability_cache`); `availability_parser.dart` *evaluates* those rules
against the current time on-device. Different jobs, correctly separated.

---

## 1. Python interpreter spawn in production — does refresh fail loudly or silently?

`availabilityParser.js:189-269` (`runPythonParser`). On `win32` it only
tries `python`; everywhere else (Railway, Linux) it tries
`python3.11` → `python3` → `python`, probing each with `spawnSync(cmd,
['--version'])` and taking the first with exit status 0.

If none succeed, `pythonCmd` stays `null` and the promise rejects with
`Error('No Python interpreter found...')` (line 209). That rejection
propagates up through `parseAvailability()` (line 332), which wraps the
whole method in try/catch (lines 298-347): the catch does
`console.error('❌ Error in availability parsing:', error)` and then
**returns the old cache** as if that were a valid result.

That return value is in turn discarded by the caller,
`aedService.parseAvailabilityAfterSync` (`aedService.js:241-256`), which is
itself invoked **fire-and-forget** from `syncAEDs` (line 218:
`.catch(e => console.error(...))`) — its result is never awaited or used.

**Verdict: fails loudly to server logs only, silently to every client.**
Two `console.error` lines are the only trace. No exception reaches any
HTTP response, no flag is set anywhere in the database, and the main AED
sync (locations/coordinates, which already committed before this
fire-and-forget call) succeeds regardless. Nothing in `routes/aed.js`
distinguishes "parser never ran because Python was missing" from "parser
ran and found nothing new to parse" — both leave `availability_cache`
exactly as it was.

## 2. When does the rules cache actually refresh?

Two independent triggers, both server-side, and they're the *only*
triggers:

- **Cron**, `server.js:251-280`: `node-cron` scheduled `0 3 * * 0,3`
  (Sunday and Wednesday, 3:00 AM, `Europe/Athens`) — fetches from
  iSaveLives, calls `syncAEDs`, which fire-and-forgets
  `parseAvailabilityAfterSync`.
- **Startup, conditionally**, `server.js:284-302`: only if
  `aed_locations` is completely empty (`count === 0`). Otherwise it logs
  `"Database has N AEDs - skipping initial sync"` and does nothing.
- **Manual**, `routes/aed.js:48-90`: `POST /aed/sync`, unauthenticated,
  same `syncAEDs` → fire-and-forget parse path.

**On the app side: never automatically, and only once per cold start.**
`AvailabilityParser.loadRules()` is called exactly once, in
`main.dart:61`, as `unawaited(AvailabilityParser.loadRules())` during app
init. There is no call anywhere else in the app — not on map open, not on
a timer, not on reconnect, not on pull-to-refresh. Confirmed by a
project-wide search: `main.dart` is the only call site. If the app is
opened once and left running (backgrounded/foregrounded repeatedly without
a process restart), the availability rules loaded at that first launch are
used for the entire lifetime of that process, however many days that is.

## 3. If refresh fails, does the app show stale data as current? Is there a "last updated" notion?

**Yes it shows stale data as current, and no, there is no user-visible
"last updated" anywhere in the AED feature.**

The server does track this: `GET /aed/availability` sets
`X-Last-Updated` from `aed_sync_log` (`routes/aed.js:216`), and
`GET /aed/` sets `X-Data-Last-Updated` similarly. But
`AvailabilityParser._fetchFromBackend()` (`availability_parser.dart:89-109`)
reads only `response.body` — it never inspects `response.headers`, so
that timestamp is fetched by the server and thrown away by the client.

On the AED-location side, `CacheService` does persist
`aed_last_updated`/`route_last_updated` timestamps
(`cache_service.dart:39-82`) with a 7-day TTL
(`isAEDCacheExpired`/`getCacheAge`). But a project-wide search found
`getCacheMetadata`/`aed_last_updated` referenced only inside
`cache_service.dart` itself — nothing in any AED map screen or widget
reads it. The timestamp is written and never displayed.

Net effect: whether the availability map came from a fresh backend fetch,
a 6-day-old `SharedPreferences` cache, or (see Q4) the broken bundled-asset
fallback, the UI presents it identically. There is no "data as of ..."
indicator, no dimming, nothing that would tell a user the AED they're
being routed to might have a schedule that changed a week ago.

## 4. No cache at all (first launch, offline) — what does the map show?

`loadRules()` (`availability_parser.dart:51-81`) has three tiers:

1. Backend fetch — fails (offline).
2. `SharedPreferences` cache — fails (`cachedData`/`timestamp` are
   `null` on a true first launch).
3. Bundled asset fallback:
   `rootBundle.loadString('assets/data/parsed_availability_map.json')`.

**Tier 3 is dead code.** The file does not exist anywhere under
`CPR-Assist-App/cpr_assist/assets/`, and it is not declared in
`pubspec.yaml`'s `assets:` list (checked the full list, no `assets/data/`
entry at all). `rootBundle.loadString` on a path Flutter never bundled
throws, which is caught by the outer `catch (_) { _availabilityMap =
null; }` (lines 78-80) wrapping the entire method — so the failure is
silent by design, not a crash.

With `_availabilityMap == null`, every call to `parseAvailability()` hits
the first guard (line 168) and returns `isOpen: false, isUncertain: true,
displayText: ''` — an intentionally empty display, which per the class's
own comment is meant to "signal UI to hide the section." So the concrete
answer: **on a true cold, offline first launch, every AED's availability
section is silently hidden.** Not wrong data, not an error state — just
absent. That's a reasonable fail-safe outcome by accident, but the
"last resort: bundled asset" tier documented in the code comment doesn't
actually exist and never has (its target file isn't in the repo either),
so this fallback path is untested and has presumably never fired
successfully.

## 5. Does `_parseCache` invalidate on a day boundary?

`_parseCache` declared at `availability_parser.dart:47`. The memoization
key (line 155):

```dart
final cacheKey = '${availability ?? ""}|${now.year}${now.month}${now.day}${now.hour}${now.minute}';
```

Includes year/month/day/hour/minute, so a lookup at 23:55 and one at 00:05
produce different keys (different day, hour, and minute all change) —
**the specific 23:55→00:05 scenario in the task prompt is handled
correctly**, and more generally every entry expires after at most one
minute regardless of what boundary it crosses.

**Separate, lower-severity defect found in the same key while checking
this:** the components aren't delimited or zero-padded, so
`month`+`day`+`hour`+`minute` can collide across different dates that
happen to concatenate to the same digit string — e.g. `month=1, day=15,
hour=3, minute=0` and `month=11, day=5, hour=3, minute=0` both produce
`"1153 0"` → `"11530"`. For this to actually return a wrong cached status,
the app process would need to stay alive across both colliding dates
(here, ~10 months apart) with the same availability string queried on
both — the 5000-entry `.clear()` bound and normal app/session lifetimes
make this very unlikely to manifest in practice, but it's a latent
correctness bug in the key construction, not by design.

## 6. Local Greek time vs UTC, and DST

Every time computation in the evaluator uses `DateTime.now()`
(`availability_parser.dart:154, 230`) and reads `.hour`/`.weekday`/`.month`
directly — Dart's `DateTime.now()` returns device-local wall-clock time,
not UTC, and there is no explicit UTC conversion anywhere in this file.

**DST is handled transparently, correctly, with no app-side logic
needed:** because the comparisons are all against wall-clock
hour/minute (not elapsed durations), the platform's own timezone/DST
database is what makes `DateTime.now()` return the right local hour on
either side of a clock change — the app doesn't need to know DST
happened, and doesn't try to.

**The one real assumption, not a bug but worth stating explicitly:**
this is correct precisely because it assumes the *device's* local
timezone is Greece. That's true for the overwhelming majority of real
usage (Greek residents, or any phone with automatic network-based
timezone detection while physically in Greece), but a device manually
pinned to a different timezone while the user is in Greece — or any
emulator/test device left on its default UTC — would evaluate opening
hours against the wrong clock with no indication anything was off, since
there's no server-side Greek-time authority to cross-check against.

## 7. `_isGreekHoliday` / `_calculateOrthodoxEaster` — Dart-only, runtime, not cached

Confirmed correct. Both are pure `static` functions in
`availability_parser.dart` (lines 380-408 and 411-422 respectively),
computed from `DateTime.now().year` at call time — nothing about them is
fetched, cached, or server-provided. This is the right design: Orthodox
Easter (and the movable feasts derived from it — Clean Monday, Good
Friday, Easter Monday, Holy Spirit Monday) shifts every year and is pure
calendar math, so computing it on-device at evaluation time is simpler and
more robust than trying to keep a server-side table in sync, and there's
no reason it would ever need historical/cached values.

Checked for a year-rollover edge case (movable holidays derived by
`.subtract()`/`.add()` from `easter`, then compared by month+day only,
ignoring year — line 404): not a bug. The algorithm's Orthodox Easter
falls between roughly April 3 and May 8, so the earliest derived holiday
(Clean Monday, 48 days before) lands no earlier than mid-February of the
*same* year — never rolls into December of the previous year — so
comparing month+day without year is safe here.

---

## Summary of defects found

| # | Where | Defect | Status |
|---|---|---|---|
| A | `availability_parser.dart:69-77` | Bundled-asset fallback (`assets/data/parsed_availability_map.json`) references a file that doesn't exist and isn't declared in `pubspec.yaml`. Dead code, silently swallowed by the outer catch. | **Fixed** 2026-09-16 — dead tier-3 fallback removed. `loadRules()` now falls straight from cache to `null`; unused `flutter/services.dart` import dropped too. |
| B | `availability_parser.dart:89-109` | `_fetchFromBackend` discards `X-Last-Updated`/response headers entirely; server already computes and sends this. | **Fixed** 2026-09-16 — `_fetchFromBackend` now captures the header into a new `availability_rules_last_updated` SharedPreferences key on a successful fetch; `AvailabilityParser.getLastUpdated()` exposes it. Not yet read by any UI — that's item C. |
| C | `cache_service.dart` + AED map UI | `aed_last_updated`/`route_last_updated` are written but never read by any screen/widget — no staleness ever shown to the user. | **Decided 2026-09-16 — won't show for now.** No UI change. `AvailabilityParser.getLastUpdated()` (from B) stays unconsumed. |
| D | `availability_parser.dart:155` | `_parseCache` key concatenates year/month/day/hour/minute without delimiters or padding — collision-prone across dates, though practically unlikely to manifest within one app session. | **Fixed** 2026-09-16 — key now joins date components with `-`. |
| E | `main.dart:61` / whole app | Availability rules load once at cold start and never refresh again for the life of the process. | **Decided 2026-09-16 — acceptable as-is.** Server only updates twice a week anyway; once-per-launch judged sufficient. No code change. |
| F | `availabilityParser.js:189-269` | A missing Python interpreter on Railway degrades to two `console.error` lines with zero visibility anywhere else — no alert, no DB flag, no way to know except reading server logs. | **Fixed** 2026-09-16 — `aed_sync_log` gained a nullable `availability_parse_error` column. `syncAEDs` captures the row's id and passes it to `parseAvailabilityAfterSync`, which now sets the column on failure and clears it on success. `availabilityParser.js`'s `parseAvailability()` no longer swallows the error internally (it had been returning the old cache instead of throwing, which meant the failure never reached the caller at all) — it now rethrows so the caller's try/catch actually fires. `GET /aed/last-sync` now returns `availabilityParseError` alongside `lastSync`, queryable without a DB console. |

A, B, D, and F fixed. C and E are deliberate no-change decisions, not deferrals.
