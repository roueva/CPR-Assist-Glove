# Location-Staleness Audit

Read-only. No files edited. Scope: the seven items (A1–A7) requested for the
cached-location-flag collapse, plus the "newly reachable" flag check.

Files read in full: `aed_location_controller.dart`, `aed_map_widget.dart`,
`aed_map_panels.dart`, `aed_map_cards.dart`, `aed_map_overlays.dart`,
`aed_map_display.dart`, `aed_routing_coordinator.dart`, `cache_service.dart`,
`app_initialization_manager.dart`, `app_constants.dart` (location section).

**Premise check confirmed:** `processLocationUpdate` is called from exactly
three places (`_onRawLocationUpdate`, `requestLocationPermission`,
`startManualGPSSearch`'s listener) and all three pass `fromCache: false`
(or omit it). The `else` branch of `processLocationUpdate` that sets
`_isUsingCachedLocation = true` is therefore never reached by any current
caller — the field really is dead, and `isLocationStale()` /
`isLocationTooOld()` really are unreachable as a result (their first line
gates on `_isUsingCachedLocation`, which is always `false`).

---

## A1 — `aed_location_controller.dart`: collapse the dead flag

**Current (lines 62, 74, 79, 85, 93, 287, 292):**
```dart
bool _isUsingCachedLocation = false;
bool _hasRealGPSFix = false;
...
bool get isUsingCachedLocation => _isUsingCachedLocation;
...
bool isLocationStale() {
  if (!_isUsingCachedLocation || _locationLastUpdated == null) return false;
  ...
}
bool isLocationTooOld() {
  if (!_isUsingCachedLocation || _locationLastUpdated == null) return false;
  ...
}
void markRealGPSFix(LatLng location) {
  _hasRealGPSFix = true;
  _isUsingCachedLocation = false;         // assignment 1
  ...
}
...
if (!fromCache) {
  ...
  _isUsingCachedLocation = false;         // assignment 2
  ...
} else {
  _isUsingCachedLocation = true;          // assignment 3 (the dead one)
}
```

**Proposed:**
```dart
bool _hasRealGPSFix = false;
...
bool get isUsingCachedLocation => !_hasRealGPSFix;
...
void markRealGPSFix(LatLng location) {
  _hasRealGPSFix = true;
  ...
}
...
if (!fromCache) {
  ...
  // no _isUsingCachedLocation assignment — delete this line
  ...
} else {
  // no _isUsingCachedLocation assignment — delete this line
}
```
Delete the field declaration (line 62) and all three assignments (93, 287, 292).
The two guard lines (79, 85) aren't simply deleted — they're rewritten under A2
below, since `isLocationStale`/`isLocationTooOld` still need a "do we have a
real fix" gate; it's just expressed via `_hasRealGPSFix` now.

**Readers of the getter, across `lib/`:**

| Site | Current behavior (flag always `false`) | Behavior after A1 |
|---|---|---|
| `aed_map_widget.dart:325-326` — `_routingCoordinator.isUsingCachedLocation = _locationController.isUsingCachedLocation;` (inside `_handleLocationUpdate`) | always sets `false` | correctly tracks `!hasRealGPSFix` |
| `aed_map_widget.dart:472` — `if (mounted && _locationController.isUsingCachedLocation) setState(() {});` (in `_fetchFreshAEDsInBackground`, "AED data unchanged" branch) | dead condition, never fires | now fires while still on a cached fix |
| `aed_map_widget.dart:481` — same guard, a few lines later | dead condition, never fires | now fires while still on a cached fix |
| `aed_map_widget.dart:1008` — `isUsingCachedOrStaleLocation: _locationController.isUsingCachedLocation \|\| _locationController.isLocationStale()` (passed into `startNavigation`) | always `false \|\| false` | now can be `true`, which makes `startNavigation` fetch a fresh high-accuracy fix before navigating (`aed_routing_coordinator.dart:274-297`) — previously unreachable |

All four are `bool`-typed reads of a `bool` getter — the signature doesn't
change, so all four still compile. No other file references
`AEDLocationController.isUsingCachedLocation`.

**One thing worth flagging directly:** `AEDMapConfig.isUsingCachedLocation` —
the field actually driving the "Locating…" chip, the `AEDCard` grey-out, and
the status-bar location chip — is **not** wired to this getter at all. It's
set independently at `aed_map_widget.dart:991`:
```dart
isUsingCachedLocation: !_locationController.hasRealGPSFix,
```
i.e. it's already computed from `hasRealGPSFix` directly, bypassing the dead
flag entirely. A1 makes the *controller's own* getter agree with what the
config was already doing — it does not change what `AEDMapConfig` shows. See
the "newly reachable" section at the bottom: this means the "Locating…" chip
claim doesn't hold up.

---

## A2 — `aed_location_controller.dart`: real gating + named constants

**Current (lines 78-87):**
```dart
bool isLocationStale() {
  if (!_isUsingCachedLocation || _locationLastUpdated == null) return false;
  final age = DateTime.now().difference(_locationLastUpdated!).inHours;
  return age >= 1 && age < 5;
}

bool isLocationTooOld() {
  if (!_isUsingCachedLocation || _locationLastUpdated == null) return false;
  return DateTime.now().difference(_locationLastUpdated!).inHours >= 5;
}
```

**Proposed:**
```dart
bool isLocationStale() {
  if (_hasRealGPSFix || _locationLastUpdated == null) return false;
  final age = DateTime.now().difference(_locationLastUpdated!).inHours;
  return age >= AppConstants.locationFreshHours &&
      age < AppConstants.locationStaleHours;
}

bool isLocationTooOld() {
  if (_hasRealGPSFix || _locationLastUpdated == null) return false;
  return DateTime.now().difference(_locationLastUpdated!).inHours >=
      AppConstants.locationStaleHours;
}
```

**`app_constants.dart` (around line 284):**
```dart
  // ═══════════════════════════════════════════════════════
  // LOCATION STALENESS
  // ═══════════════════════════════════════════════════════

  static const int locationStaleHours = 5;
```
→
```dart
  // ═══════════════════════════════════════════════════════
  // LOCATION STALENESS
  // ═══════════════════════════════════════════════════════

  static const int locationFreshHours = 1;
  static const int locationStaleHours = 5;
```
`locationStaleHours` already exists and is already used at
`aed_map_panels.dart:890`, so no import changes needed anywhere; `core.dart`
already re-exports it.

**Contradiction check:** none. The inversion is exact — old gate was "return
false unless using cached location," new gate is "return false unless we
lack a real fix," and `isUsingCachedLocation` is being redefined as
`!_hasRealGPSFix`, so these are the same condition.

---

## A3 — `processLocationUpdate` signature + cold-start call site

**Current `processLocationUpdate` (lines 281-293):**
```dart
Future<void> processLocationUpdate(LatLng location,
    {bool fromCache = false}) async {
  final bool isFirstRealGPSFix = !fromCache && !_hasRealGPSFix;

  if (!fromCache) {
    _locationLastUpdated = DateTime.now();
    _isUsingCachedLocation = false;
    if (!_hasRealGPSFix) {
      _hasRealGPSFix = true;
    }
  } else {
    _isUsingCachedLocation = true;
  }
```

**Proposed:**
```dart
Future<void> processLocationUpdate(LatLng location,
    {bool fromCache = false, DateTime? cachedAt}) async {
  final bool isFirstRealGPSFix = !fromCache && !_hasRealGPSFix;

  if (!fromCache) {
    _locationLastUpdated = DateTime.now();
    if (!_hasRealGPSFix) {
      _hasRealGPSFix = true;
    }
  } else {
    _locationLastUpdated = cachedAt;
  }
```

**Current cold-start seed, `aed_map_widget.dart:208-215` (inside `_initializeApp`):**
```dart
// Step 1: Seed cached location.
if (result.userLocation != null) {
  await _handleLocationUpdate(result.userLocation!,
      fromCache: result.isLocationCached);
  if (result.isLocationCached) {
    if (mounted) setState(() {});
  }
}
```

**Proposed:**
```dart
// Step 1: Seed cached location.
if (result.userLocation != null) {
  await _locationController.processLocationUpdate(result.userLocation!,
      fromCache: result.isLocationCached, cachedAt: result.locationAge);
  if (result.isLocationCached) {
    if (mounted) setState(() {});
  }
}
```
`result.locationAge` is `DateTime?` on `InitializationResult`
(`app_initialization_manager.dart:34`, populated from
`CachedLocationData.age`, which is the cache's stored timestamp, not a
duration) — despite the field's name, it's exactly the "cached at" instant
`processLocationUpdate`'s new `cachedAt` parameter wants. Type matches.

**Verification — does `processLocationUpdate(fromCache: true, previousLocation: null)` avoid the banner, tiny-move skip, and first-fix path?**

Traced step by step with `previousLocation == null` (true at cold start, since Step 1 runs before any AED/state population) and `fromCache: true`:

- `isFirstRealGPSFix = !fromCache && !_hasRealGPSFix` → `false` (short-circuits on `!fromCache`). First-fix path (`_callbacks.onFirstRealGPSFix`) is **not** triggered. ✅
- Banner block is gated `if (!wasLocationNull && !fromCache)` → `wasLocationNull` is `true`, so it's skipped regardless of the `fromCache` term. ✅
- Tiny-move-skip block has the same `if (!wasLocationNull && !fromCache)` gate → skipped. ✅
- Delegates to `_callbacks.onLocationUpdate(location, fromCache: fromCache)`, i.e. `_handleLocationUpdate(location, fromCache: true)`. This is the same call the old code made directly — same behavior, since `_handleLocationUpdate` doesn't currently look at `fromCache` at all (see A6). Its `aedList.isEmpty` branch is taken (AED list isn't populated until Step 2 of `_initializeApp`, which runs after this), so it just calls `cacheUserRegion` and returns — identical to today.
- Back in `processLocationUpdate`, the re-sort block is also gated on `!wasLocationNull` → skipped. ✅

So A3 is safe for the traced cold-start path. **One thing A3 does *not* fix on its own** — the tail of `processLocationUpdate` unconditionally calls `CacheService.saveLastAppState(...)` once `mapNotifier.updateUserLocation` (inside `_handleLocationUpdate`) has made `latestState.userLocation` non-null. Routing the cold-start seed through `processLocationUpdate` means this now fires on `fromCache: true` too, re-stamping the seeded cache position with `DateTime.now()` — which defeats the point of tracking `cachedAt`. That's exactly what A4 catches; A3 and A4 need to land together.

---

## A4 — Guard `saveLastAppState` in `processLocationUpdate`

**Current (tail of `processLocationUpdate`, lines 342-349):**
```dart
    // ── Persist app state ─────────────────────────────────────────────────
    final latestState = _ref.read(mapStateProvider);
    if (latestState.userLocation != null) {
      CacheService.saveLastAppState(
        latestState.userLocation!,
        latestState.navigation.transportMode,
      );
    }
```

**Proposed:**
```dart
    // ── Persist app state ─────────────────────────────────────────────────
    if (!fromCache) {
      final latestState = _ref.read(mapStateProvider);
      if (latestState.userLocation != null) {
        CacheService.saveLastAppState(
          latestState.userLocation!,
          latestState.navigation.transportMode,
        );
      }
    }
```
Confirmed necessary (see A3 above) — without this guard, seeding the cold
start from cache would immediately overwrite `last_app_state`'s timestamp
with "now," so the *next* cold start would see a 0-hour-old cache and never
show stale/too-old, permanently defeating A2/A3.

---

## A5 — Guard `saveLastAppState` in `_pauseApp`

**Current, `aed_map_widget.dart:947-957`:**
```dart
void _pauseApp() {
  _lastBackgroundTime = DateTime.now();

  final currentState = ref.read(mapStateProvider);
  if (currentState.userLocation != null) {
    CacheService.saveLastAppState(
      currentState.userLocation!,
      currentState.navigation.transportMode,
    );
  }
}
```

**Proposed:**
```dart
void _pauseApp() {
  _lastBackgroundTime = DateTime.now();

  final currentState = ref.read(mapStateProvider);
  if (currentState.userLocation != null && _locationController.hasRealGPSFix) {
    CacheService.saveLastAppState(
      currentState.userLocation!,
      currentState.navigation.transportMode,
    );
  }
}
```
Same class of bug as A4, different call site: if the app is backgrounded
before the first real GPS fix arrives (permission not yet granted, GPS still
off, or just a fast background within the first frame), `mapStateProvider`
already holds the seeded cached position, and this call would re-stamp it as
fresh. Gating on `hasRealGPSFix` makes this consistent with A4.

---

## A6 — Delete `fromCache` from `_handleLocationUpdate` — **does not compile as stated**

**Current, `aed_map_widget.dart:316-317`:**
```dart
Future<void> _handleLocationUpdate(LatLng location,
    {bool fromCache = false}) async {
```
Confirmed the parameter is never read inside the body (checked all 48 lines
of the method) — it's dead weight *inside* `_handleLocationUpdate` itself,
independent of A3.

**Problem:** `_handleLocationUpdate` is assigned directly to
`AEDLocationCallbacks.onLocationUpdate` at `aed_map_widget.dart:106`
(`onLocationUpdate: _handleLocationUpdate`). That field's declared type,
`aed_location_controller.dart:17`, is:
```dart
final Future<void> Function(LatLng location, {bool fromCache}) onLocationUpdate;
```
and `processLocationUpdate` calls it with an explicit named argument
(`aed_location_controller.dart:320`):
```dart
await _callbacks.onLocationUpdate(location, fromCache: fromCache);
```
Dart's function-type assignability requires the assigned closure to accept
every named parameter the declared type promises to callers. If
`_handleLocationUpdate` drops `{bool fromCache = false}` from its own
signature, `onLocationUpdate: _handleLocationUpdate` stops type-checking —
`Future<void> Function(LatLng)` is not assignable to
`Future<void> Function(LatLng, {bool fromCache})`. This is a real
compile error, not a style nit.

**Only two call sites of `_handleLocationUpdate` exist in `lib/`:** the
callback wiring above, and the direct cold-start call at
`aed_map_widget.dart:210` — which A3 replaces with a call to
`_locationController.processLocationUpdate` instead. So after A3 lands,
`_handleLocationUpdate` really is only ever invoked *through* the callback,
which is exactly the path that still requires the `fromCache` parameter to
exist on the closure, even though the method body never reads it.

**To actually do what A6 wants, three things have to move together, not one:**
1. Drop `{bool fromCache}` from the `AEDLocationCallbacks.onLocationUpdate` typedef.
2. Drop `fromCache: fromCache` from the call in `processLocationUpdate`.
3. Drop `{bool fromCache = false}` from `_handleLocationUpdate`.

That's a bigger, three-file change than "delete the unused parameter,"
and it removes information from the callback type that some *other*
future caller could plausibly want. **Recommend leaving A6 out** unless you
want that three-site change — the parameter is harmless as dead weight, and
removing just the one declaration as originally scoped won't build.

---

## A7 — `aed_map_panels.dart`: fourth status chip for "too old"

**Current `_buildStatusBanners`, lines 796-837** (inside `_AEDNavigationPanelState`
— this is the only `_buildStatusBanners` in the file; `AEDActiveNavigationPanel`
has its own separate, simpler `_buildOfflineBanner` and doesn't call this one):
```dart
Widget _buildStatusBanners(bool isOfflineRoute) {
  final showNoGps = !widget.userLocationAvailable;
  final showOffline  = widget.config.isOffline;
  final showCached = widget.config.isUsingCachedLocation && widget.userLocationAvailable;

  if (!showNoGps && !showOffline && !showCached) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (showNoGps)
          const _StatusChip(
            icon: Icons.location_off,
            label: 'No GPS',
            color: AppColors.primary,
            bg: AppColors.primaryLight,
            tooltip: 'Showing compass direction only',
          ),
        if (showOffline)
          const _StatusChip(
            icon: Icons.wifi_off,
            label: 'Offline',
            color: AppColors.warning,
            bg: AppColors.warningBg,
            tooltip: 'No internet connection · distances are estimates',
          ),
        if (showCached)
          const _StatusChip(
            icon: Icons.refresh,
            label: 'Locating…',
            color: AppColors.primary,
            bg: AppColors.primaryLight,
            isSpinner: true,
            tooltip: 'Using cached location, getting current GPS position…',
          ),
      ],
    ),
  );
}
```

**Proposed:**
```dart
Widget _buildStatusBanners(bool isOfflineRoute) {
  final showNoGps = !widget.userLocationAvailable;
  final showOffline = widget.config.isOffline;
  final showTooOld = widget.config.locationAge != null &&
      widget.config.locationAge! >= AppConstants.locationStaleHours;
  final showCached = widget.config.isUsingCachedLocation &&
      widget.userLocationAvailable &&
      !showTooOld;

  if (!showNoGps && !showOffline && !showCached && !showTooOld) {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        if (showNoGps)
          const _StatusChip(
            icon: Icons.location_off,
            label: 'No GPS',
            color: AppColors.primary,
            bg: AppColors.primaryLight,
            tooltip: 'Showing compass direction only',
          ),
        if (showOffline)
          const _StatusChip(
            icon: Icons.wifi_off,
            label: 'Offline',
            color: AppColors.warning,
            bg: AppColors.warningBg,
            tooltip: 'No internet connection · distances are estimates',
          ),
        if (showCached)
          const _StatusChip(
            icon: Icons.refresh,
            label: 'Locating…',
            color: AppColors.primary,
            bg: AppColors.primaryLight,
            isSpinner: true,
            tooltip: 'Using cached location, getting current GPS position…',
          ),
        if (showTooOld)
          const _StatusChip(
            icon: Icons.location_disabled,
            label: 'Location outdated',
            color: AppColors.warning,
            bg: AppColors.warningBg,
            tooltip: 'Cached location may no longer be accurate',
          ),
      ],
    ),
  );
}
```
Uses only `AppColors`/`AppSpacing` tokens already imported in this file (no
new import needed), no raw colors, no inline `TextStyle` (`_StatusChip`
already encapsulates its own `AppTypography.label`), no magic numbers
(`AppConstants.locationStaleHours`, already used one line away at
`_buildInfoRow` (line 890) for the same threshold).

**Not specified by the task, my own call, flag for confirmation:** the chip
`label` ("Location outdated") and `tooltip` text weren't given — I picked
something consistent with the sibling chips' tone. Also, since `showCached`
and `showTooOld` are now mutually exclusive by construction, only one of
"Locating…" / "Location outdated" can ever show at once, as requested.

---

## The "three newly-reachable paths" flag

I checked all three named paths. **Two are genuinely new; one already fires today and isn't affected by this change at all.**

1. **"Locating…" chip — already live, not newly reachable.** `showCached`
   reads `widget.config.isUsingCachedLocation`, which — per the A1 note above
   — is independently wired to `!_locationController.hasRealGPSFix` at
   `aed_map_widget.dart:991`, not to the dead `_isUsingCachedLocation` flag.
   That means this chip has been showing correctly (whenever
   `userLocationAvailable` and no real fix yet) all along, regardless of
   whether A1–A4 land. Nothing about A1–A7 changes when it appears. The
   premise that it's "reachable for the first time" doesn't hold — worth a
   quick sanity check on your end in case you'd separately observed it
   *not* appearing and that's what prompted this task.

2. **Blanked ETA/distance (`AEDCompactInfoColumn(isEmpty: true)`) —
   genuinely new.** `_buildInfoRow`'s `isTooOld` (line 889-890) is driven by
   `widget.config.locationAge`, which comes from `_locationController.locationLastUpdated`
   (`aed_map_widget.dart:995-999`). Before A3, `_locationLastUpdated` is never
   set on the `fromCache: true` path, so `locationAge` is always `null` for a
   cached-only session and this branch can't fire. After A3 it can. I didn't
   find anything else guarding it further — once `locationAge` is real and
   `>= locationStaleHours`, both the ETA and Distance columns go to `--`
   unconditionally, even if `widget.config.distance` and
   `widget.config.estimatedTime` hold stale-but-present values from a
   previous fix. That looks like exactly the intended effect, not a bug —
   flagging only because it's untested code path, not because I see a
   problem in it.

3. **Compass-only navigation — genuinely new, and worth a closer look.**
   `AEDRoutingCoordinator.startNavigation`'s `isTooOld` short-circuit
   (`aed_routing_coordinator.dart:302-308`) is fed by
   `_locationController.isLocationTooOld()`
   (`aed_map_widget.dart:1011`), dead until A2/A3 land. One thing to note:
   this branch runs *before* the "get a fresh high-accuracy fix" block above
   it (lines 274-297) has a chance to help — that block only fires on
   `isUsingCachedOrStaleLocation` (cached or *stale*, not too-old), and if
   the fresh fix succeeds, `currentLocation` is reassigned from the live GPS
   read, not from `_locationController`'s cached state, so `isTooOld` (which
   is a value computed once, up in `aed_map_widget.dart:1011`, from the
   *pre*-fresh-fix state) could still be `true` even though a good fix was
   just obtained. In other words: if the cached location is old enough to be
   "too old," `startNavigation` will always fall into compass-only mode on
   the first tap, even when the just-fetched fresh GPS fix (lines 280-297)
   succeeded a moment earlier and is sitting in `mapStateProvider` unused.
   That looks like a genuine gap that only becomes visible once this whole
   flag is un-deadened — I did not touch it, flagging for your judgment since
   it's outside the seven items you listed.

---

## Summary of files touched by A1–A7

| File | Items |
|---|---|
| `lib/features/aed_map/controllers/aed_location_controller.dart` | A1, A2, A3, A4 |
| `lib/features/aed_map/services/aed_map_widget.dart` | A3 (call site), A5, A6 (blocked, see above) |
| `lib/core/utils/app_constants.dart` | A2 (new constant) |
| `lib/features/aed_map/widgets/aed_map_panels.dart` | A7 |

Nothing has been edited. Waiting for approval before applying any of the above.
