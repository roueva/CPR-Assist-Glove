# Route / ETA Preload Delay Audit

Read-only. No files edited. Scope: the eight verification items plus F1–F3,
as requested, around why polylines/ETA/distance arrive minutes late and only
after a second tap.

Files read in full: `main.dart`, `network_service.dart`, `aed_map_widget.dart`,
`aed_routing_coordinator.dart`, `aed_service.dart`, `app_initialization_manager.dart`,
`app_providers.dart` (`AEDMapState`/`NavigationState`), `main_navigation.dart`,
`aed_map_screen.dart`, plus the `flutter_dotenv` 6.0.0 package source
(`lib/src/dotenv.dart`, `lib/src/errors.dart`) from the pub cache, since item 4
turns on its actual behavior, not assumption.

**Verdict up front: hypothesis confirmed, and worse than stated.** It's not
just that `setApiKey` loses a one-time race at startup — the only other call
site is provably unreachable on a normally-online session, so
`_googleMapsApiKey` is `null` for the *entire* session, permanently, not just
until dotenv finishes loading a moment later.

---

## 1 — `main.dart` / `aed_map_widget.dart`: the race, confirmed

`main.dart:43-45`:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  dotenvReady = dotenv.load(fileName: '.env');
  await dotenvReady;
  ...
```
Confirmed: assigned inside a post-frame callback registered **after** `runApp(...)` (main.dart:36-41) returns.

`aed_map_widget.dart:124-126`, inside `initState`:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted && !_isInitializingApp) _initializeApp();
});
```
Confirmed: registered from `initState`, which itself runs during the initial
widget-tree build. I traced *why* this reliably ends up second, since it's
not obvious from source order alone: `runApp()` calls
`scheduleAttachRootWidget`, which defers the actual tree build via
`Timer.run(...)` — it does **not** build synchronously inside the `runApp()`
call. So the real sequence is: `runApp()` returns almost immediately → `main()`
continues and registers its own post-frame callback (the dotenv one) →
*then*, on a later event-loop turn, the deferred `attachRootWidget` finally
builds the tree, which is when `AedMapScreen` → `AEDMapWidget.initState()`
actually runs and registers *its* callback. I confirmed `AEDMapWidget` is
built eagerly, not lazily: `MainNavigationScreen` (`main_navigation.dart:40-44`)
builds `_screens = [AedMapScreen(...), ...]` as a plain list in `initState`
and hands it straight to a `PageView` (not `.builder`), and `AedMapScreen`
(`aed_map_screen.dart:66`) embeds `const AEDMapWidget()` directly — no gate,
no `FutureBuilder`. So the map widget's `initState` really does run during
the very first frame, just chronologically after `main()`'s callback was
already queued. Net effect: main's dotenv callback is *reliably* first in the
post-frame queue, `_initializeApp`'s is reliably second — that part of the
hypothesis holds, and it also means **F2 is safe from a `LateInitializationError`**
(see F2 below) since `dotenvReady` is guaranteed already assigned, if not yet
resolved, by the time `_initializeApp` reads it.

`aed_map_widget.dart:179-187`, inside `_initializeApp`:
```dart
Future<void> _initializeApp() async {
    if (_isInitializingApp) return;
    _isInitializingApp = true;

    try {
      final aedRepository = ref.read(aedServiceProvider);
      String? apiKey;
      try {
        apiKey = NetworkService.googleMapsApiKey;
      } catch (_) {
        apiKey = null; // dotenv not loaded yet — will be set later
      }
      _routingCoordinator.setApiKey(apiKey);
```
Confirmed: `ref.read(...)` is synchronous, both `try` bodies are synchronous —
there is no `await` anywhere between the top of `_initializeApp` and the
`setApiKey` call. (Note: the task text says `aed_map_widget.dart:189` for this
call — in the file as it currently stands it's line 187; same statement,
number drifted by a couple lines, not a discrepancy in substance.)

---

## 2 — Every `setApiKey` call site

```
aed_routing_coordinator.dart:110   void setApiKey(String? key) { ... }   ← the method
aed_map_widget.dart:187            _routingCoordinator.setApiKey(apiKey);   ← inside _initializeApp, dotenv not yet loaded
aed_map_widget.dart:624            _routingCoordinator.setApiKey(apiKey);   ← inside _onConnectivityChanged
```

Enclosing condition for the second site, `aed_map_widget.dart:614-625`:
```dart
Future<void> _onConnectivityChanged(bool isConnected) async {
  final currentState = ref.read(mapStateProvider);
  if (!mounted) return;

  if (currentState.isOffline && isConnected) {
    debugPrint('🟢 Connection restored!');
    _wasOffline = false;
    ref.read(mapStateProvider.notifier).setOffline(false);

    final apiKey = NetworkService.googleMapsApiKey;
    _routingCoordinator.setApiKey(apiKey);
    ...
```
It only runs when `currentState.isOffline && isConnected` — i.e. only on the
transition *back* from a state the app had already marked offline. Confirmed
exactly two call sites, nothing else in `lib/` calls `setApiKey`.

---

## 3 — `network_service.dart`: can `_onConnectivityChanged` ever fire on an always-online session?

```dart
static bool _lastConnectivityState = true;
...
_connectivityTimer = Timer.periodic(interval, (_) async {
  final connected = await isConnected();
  if (connected != _lastConnectivityState) {
    _lastConnectivityState = connected;
    _connectivityController?.add(connected);
    for (final listener in _connectivityListeners) {
      listener(connected);
    }
  }
});
```
Confirmed: `_lastConnectivityState` initializes to `true`, and listeners are
only invoked `if (connected != _lastConnectivityState)`.

**Plainly: no.** On a session that is online at launch and stays online,
every periodic check computes `connected == true == _lastConnectivityState`,
so the `if` is never true, no listener (including `_onConnectivityChanged`,
registered via `NetworkService.addConnectivityListener(_onConnectivityChanged)`
in `aed_map_widget.dart` `initState`) is ever invoked. Combined with item 2:
**on a normally-online session, `setApiKey` is called exactly once, ever** —
at `aed_map_widget.dart:187`, with `apiKey == null`. `_googleMapsApiKey` is
`null` for the life of the session, not just "for a moment at startup."

---

## 4 — `dotenv.env` before `load()` completes: throws, does not return `{}`

`network_service.dart:127-134`:
```dart
static String? get googleMapsApiKey {
  final key = dotenv.env['GOOGLE_MAPS_API_KEY'];
  if (key == null || key.isEmpty) {
    debugPrint('GOOGLE_MAPS_API_KEY missing from .env');
    return null;
  }
  return key;
}
```

I checked the actual `flutter_dotenv` 6.0.0 source (pub cache,
`lib/src/dotenv.dart:39-44`) rather than assume:
```dart
Map<String, String> get env {
  if (!_isInitialized) {
    throw NotInitializedError();
  }
  return _envMap;
}
```
`_isInitialized` only flips to `true` at the end of `load()`
(`dotenv.dart:154`). So **it throws** — `NotInitializedError extends Error`
(`errors.dart:1`) — it does *not* silently hand back an empty map. That
answers the question directly: the bare `catch (_)` at
`aed_map_widget.dart:184` **is reachable**, and on every normal cold start it
*is* hit — `NetworkService.googleMapsApiKey` throws `NotInitializedError`
inside `dotenv.env[...]`, which propagates up through the getter (no
try/catch inside `googleMapsApiKey` itself) to `_initializeApp`'s inner
`try`, gets caught, and `apiKey` is set to `null`. Dart's bare `catch`
(no `on` clause) catches `Error` subtypes too, not just `Exception`, so this
works as the comment implies — it's not dead code, it's exactly what fires
every time.

---

## 5 — The slow path that eventually produces real routes

Every call site of `AEDService.improveDistanceAccuracyInBackground`:

| Site | Key source | Callback calls `updatePreloadedRoutesFromCache`? |
|---|---|---|
| `aed_map_widget.dart:394` (`_handleFirstRealGPSFix`) | `NetworkService.googleMapsApiKey` re-read at line 388 | **yes** (line 402) |
| `aed_map_widget.dart:503` (`_fetchFreshAEDsInBackground`) | re-read at line 497 | **yes** (line 511) |
| `aed_map_widget.dart:596` (`_resortAEDs`) | re-read at line 588 | **no** — callback only does `ref.read(mapStateProvider.notifier).updateAEDs(updated)`. Separate, pre-existing inconsistency, not part of this bug, flagging only because you asked me to trace every call site. |
| `aed_map_widget.dart:782` (`_recenterMapToUserAndAEDs`) | re-read at line 778 | **yes** (line 792) |
| `aed_routing_coordinator.dart:742` (`onTransportModeChanged`) | the coordinator's own `_googleMapsApiKey` field, gated `if (_googleMapsApiKey != null)` at line 741 | **yes** (line 755) — but this one's dead too, since `_googleMapsApiKey` is permanently null per item 3 |
| `app_initialization_manager.dart:252` (`AppInitializationManager.improveDistanceAccuracy`) | passed-in `apiKey` param | n/a — **this wrapper has zero callers anywhere in `lib/`**, unrelated dead code, not part of this bug |

So: **four of five real call sites re-read `NetworkService.googleMapsApiKey`
directly**, bypassing the coordinator's broken field entirely — this is
exactly the path that eventually gets a real key and does real work.

Traced what "real work" means, in `aed_service.dart:174-234`:
```dart
Future<void> improveDistanceAccuracyInBackground(
    List<AED> aeds, LatLng userLocation, String transportMode,
    String? apiKey, Function(List<AED>) onUpdated) async {
  if (aeds.isEmpty || apiKey == null || apiKey.isEmpty) return;
  ...
  // 3. Fetch from Directions API.
  final routeService = RouteService(apiKey);
  final routeResult = await routeService.fetchRoute(userLocation, aed.location, transportMode);
  if (routeResult?.actualDistance != null) {
    CacheService.setCachedRoute(userLocation, aed.location, transportMode, routeResult!);
    CacheService.setDistance(cacheKey, routeResult.actualDistance!, isRoad: true);
    ...
```
It fetches a **full route** (with polyline) from the Directions API and calls
`CacheService.setCachedRoute(...)` — the same in-memory route cache that
`updatePreloadedRoutesFromCache` reads from via `CacheService.getCachedRoute`.
Confirmed: this file never references `AEDRoutingCoordinator` or
`_googleMapsApiKey` at all — it populates `preloadedRoutes` (indirectly, via
`updatePreloadedRoutesFromCache`) entirely independently of the broken field.

---

## 6 — `_routePreloader` construction and `preloadTopRoutes()` gating

`aed_routing_coordinator.dart:110-116`:
```dart
void setApiKey(String? key) {
  _googleMapsApiKey = key;
  if (key != null) {
    _routeHelper   = RouteHelper(key);
    _routePreloader = RoutePreloader(key, (status) {});
  }
}
```
Confirmed: `_routePreloader` (and `_routeHelper`) are constructed *only*
inside `setApiKey`, gated on `key != null`.

`aed_routing_coordinator.dart:820-828`:
```dart
Future<void> preloadTopRoutes() async {
  final currentState = _ref.read(mapStateProvider);
  final userLocation = currentState.userLocation;

  if (userLocation == null ||
      _routePreloader == null ||
      _googleMapsApiKey == null) {
    return;
  }
  ...
```
Confirmed: early-returns on either being null.

**This is a second, independent casualty of the same bug**, beyond what was
asked but directly relevant: since `setApiKey(null)` is the only call that
ever runs (item 3), `_routePreloader` and `_routeHelper` never get
constructed either. That means:
- `preloadTopRoutes()` — the dedicated route-preloading mechanism, scheduled
  via `scheduleRoutePreloading()` after AED sorts/zooms — is a **permanent
  no-op** for the whole session, not just delayed.
- `showNavigationPreviewForAED`'s own fresh-fetch step (`_routeHelper!.fetchAndCache(...)`,
  gated `_googleMapsApiKey != null` at line 159) **never runs** either — a tap
  on any AED can *only* ever hit RAM cache (`preloadedRoutes`) or disk cache
  (`CacheService.getCachedRoute`/`getCachedRouteNearby`); it can never itself
  go fetch a fresh route over the network.

So the *only* thing putting real routes into cache all session is the
"slow path" from item 5 — and that path only runs on specific trigger events
(first real GPS fix, the delayed background AED refetch, a significant
resort-triggering move, or manual recenter), not on an AED tap. This lines
up precisely with the reported symptom.

---

## 7 — `showNavigationPreviewForAED` does not self-upgrade

Read the full method (`aed_routing_coordinator.dart:122-256`). It is a
one-shot `async` function invoked only from tap callbacks
(`onSmallMapTap`, `onPreviewNavigation`, `switchToCloserAED`,
`onTransportModeChanged`'s post-preview branch). Nothing anywhere —
no listener, no stream subscription, no callback — re-invokes it when
`preloadedRoutes` is mutated later by `updatePreloadedRoutesFromCache`.
`updatePreloadedRoutesFromCache` itself only writes into the `preloadedRoutes`
map and logs a debug count; it doesn't touch `mapStateProvider` or call
`_callbacks.onStateChanged()` (except from the `onTransportModeChanged`
caller specifically, and even there that's just `setState(() {})` on the
widget — it doesn't re-run route resolution, since `navigation.route` in
Riverpod state was already set, once, by whichever `updateRoute(...)` call
originally rendered the estimate).

Confirmed: an open preview panel showing a grey/offline estimate has no path
back to a real route except the user closing and reopening it — which is
exactly the reported workaround ("only after backing out and re-tapping").

**One nuance for precision:** there are two different "grey" states in this
method, and only one of them is the bug:
- `routeResult != null && shouldShowGray` (cache hit, but tinted grey because
  `isUsingCachedLocation`/offline) — this **is** a real polyline with real
  distance/duration, `navigation.route` gets set to non-null. Not the
  reported symptom.
- `routeResult == null` entirely (no RAM/disk cache hit at tap time, and the
  fresh-fetch step is permanently disabled per item 6) → straight-line
  estimate, `mapNotifier.updateRoute(null, estimatedTime, estimatedDistance)`
  — `navigation.route` stays `null`. **This is the reported symptom**, and
  it's the condition F3 needs to detect.

---

## 8 — `InitializationResult.apiKey`: read by nobody

`app_initialization_manager.dart:117`: `apiKey: apiKey` is set on
`InitializationResult` from `NetworkService.googleMapsApiKey`, read at
roughly the same synchronous, pre-dotenv moment as item 1's call
(`_run` doesn't await anything before this either).

I grepped every `.apiKey` reference in `lib/` — the only other hits are the
constructor-parameter declarations in `InitializationResult`'s and
`RouteService`/`RouteHelper`'s own class bodies (`this.apiKey`). **Nothing
reads `result.apiKey`.** `_initializeApp` receives `result` at line 199 —
*after* the (already-lost) `setApiKey` call at line 187 — so even if
something did read `result.apiKey`, it would arrive too late to help the
existing call site anyway. This field is inert; not a contributing cause,
not something to wire up as part of this fix.

---

## F1 — `main.dart`: start `dotenv.load()` before `runApp` — real improvement, not a fix by itself

**Current (lines 36-45):**
```dart
runApp(
  UncontrolledProviderScope(
    container: container,
    child: const MyApp(),
  ),
);

WidgetsBinding.instance.addPostFrameCallback((_) async {
  dotenvReady = dotenv.load(fileName: '.env');
  await dotenvReady;
  ...
```

**Proposed:**
```dart
dotenvReady = dotenv.load(fileName: '.env');

runApp(
  UncontrolledProviderScope(
    container: container,
    child: const MyApp(),
  ),
);

WidgetsBinding.instance.addPostFrameCallback((_) async {
  await dotenvReady;
  ...
```
Safe: `dotenv.load()` only needs `WidgetsFlutterBinding.ensureInitialized()`
(already called at the top of `main()`) — it doesn't depend on `runApp` or
the widget tree existing, and assigning a `Future` doesn't block, so this
doesn't delay time-to-first-frame. The `late final Future<void> dotenvReady;`
top-level var (`main.dart:79`) is now assigned strictly before any widget
exists, which is strictly *safer* than today (today it's assigned inside a
post-frame callback, i.e. after every `initState()` in the first frame has
already run — fine today only because nothing reads it synchronously from
`initState`).

**But — I want to correct the framing before you apply this: F1 is not "the
fix," it's a head start.** The actual bug (items 1–3 above) is that
`setApiKey` is called with zero `await`s between the postFrameCallback firing
and the read — a **structural** race, not a "starts a moment too late" issue.
Moving the `dotenv.load()` *start* earlier narrows the window in which that
race can be lost (a local asset read of a few bytes will very likely
complete before the first frame finishes rendering and postFrameCallbacks
fire), but there is no ordering guarantee between "asset read completes" and
"first frame renders" — it's still two independent async operations racing
each other, just with a better head start for one side. **F2 is what
actually removes the race** (by explicitly waiting on `dotenvReady` instead
of hoping it already resolved). Apply both — F1 as a genuine latency
improvement (routes/ETA become available sooner even after F2, since the
`.then()` in F2 fires as soon as loading finishes rather than waiting for the
next event that happens to call `setApiKey`), F2 as the correctness fix — but
don't treat F1 alone as sufficient.

---

## F2 — `aed_map_widget.dart:179-187`: defer `setApiKey` until dotenv is ready

**Current:**
```dart
try {
  final aedRepository = ref.read(aedServiceProvider);
  String? apiKey;
  try {
    apiKey = NetworkService.googleMapsApiKey;
  } catch (_) {
    apiKey = null; // dotenv not loaded yet — will be set later
  }
  _routingCoordinator.setApiKey(apiKey);
```

**Proposed:**
```dart
try {
  final aedRepository = ref.read(aedServiceProvider);
  unawaited(dotenvReady.then((_) {
    if (!mounted) return;
    _routingCoordinator.setApiKey(NetworkService.googleMapsApiKey);
  }));
```

**Imports:** confirmed already present — `import 'dart:async';` at
`aed_map_widget.dart:1` (for `unawaited`), `import '../../../main.dart';` at
line 9 (for `dotenvReady`). No new imports needed.

**Confirmed safe from `LateInitializationError`:** per item 1's trace,
`dotenvReady` is always assigned (main's postFrameCallback fires first)
before `_initializeApp` runs, regardless of whether F1 lands — F1 just makes
it resolve sooner, F2 is what makes waiting for it correct either way.

**Confirmed nothing later in `_initializeApp` depends on the key
synchronously:** everything after this point in `_initializeApp` — cluster
manager setup, `AppInitializationManager.initializeApp(...)`, and all six
numbered steps inside `_mapReadyCompleter.future.then(...)` (seed location,
sort AEDs, zoom, load markers, GPS, scheduled fresh-AED fetch) — reads AED
data, location, and GPS state, never `_routingCoordinator._googleMapsApiKey`
or `_routeHelper`/`_routePreloader`. Step 6's `_fetchFreshAEDsInBackground`
re-reads `NetworkService.googleMapsApiKey` itself (item 5), independent of
the coordinator's field. `unawaited(...)` firing asynchronously — realistically
within milliseconds of `.env` finishing its load, well before a user could
plausibly tap an AED — is fine.

**One more thing this incidentally fixes, worth knowing before you apply it:**
because `setApiKey` will now actually run with a real key at some point in
every session, `_routeHelper` and `_routePreloader` (item 6) get constructed
too — `preloadTopRoutes()` stops being a permanent no-op, and
`showNavigationPreviewForAED`'s own fresh-fetch step becomes reachable for
the first time all session. That's a bigger behavior change than "the API
key becomes non-null a bit sooner" — it turns two previously-dead code paths
live. Worth a moment's thought on whether `preloadTopRoutes()` (which does a
`Future.wait` fetch over up to `AppConstants.maxPreloadedRoutes` AEDs, for
both transport modes) firing on every `scheduleRoutePreloading()` trigger for
the first time this session is desired volume of Directions API calls — I
didn't see anything guarding against duplicate/overlapping preload runs
beyond `_isRouteFetchInProgress` (which only guards `updateNavigationRoute`,
not `preloadTopRoutes`), but that's pre-existing code, not something F1/F2
change the shape of — flagging only because it's about to start running for
the first time.

---

## F3 — `updatePreloadedRoutesFromCache`: upgrade an open preview in place

**Current (`aed_routing_coordinator.dart:928-949`):**
```dart
void updatePreloadedRoutesFromCache(List<AED> aeds, String transportMode) {
  final currentState = _ref.read(mapStateProvider);
  if (currentState.userLocation == null) return;

  int updatedCount = 0;
  for (final aed in aeds.take(20)) {
    final cachedRoute = CacheService.getCachedRoute(
      currentState.userLocation!,
      aed.location,
      transportMode,
    );
    if (cachedRoute != null) {
      preloadedRoutes['${aed.id}_$transportMode'] = cachedRoute;
      updatedCount++;
    }
  }

  if (updatedCount > 0) {
    debugPrint(
        '♻️ Updated $updatedCount preloaded routes from cache ($transportMode)');
  }
}
```

**Proposed** — one correction to how you phrased the trigger condition:
`preloadedRoutes` is keyed by AED id (`'${aed.id}_$mode'`), not by `LatLng`,
so "contains a route for `navigation.destination`" needs an id lookup, not a
map-key check against the `LatLng` itself. Doing it inline in the existing
loop (where we already have `aed.location` to compare) avoids a second cache
read and an extra `_findAED`-style scan:
```dart
void updatePreloadedRoutesFromCache(List<AED> aeds, String transportMode) {
  final currentState = _ref.read(mapStateProvider);
  if (currentState.userLocation == null) return;

  final nav = currentState.navigation;
  final bool previewNeedsUpgrade = nav.isActive &&
      !nav.hasStarted &&
      nav.route == null &&
      nav.destination != null;

  int updatedCount = 0;
  bool destinationNowCached = false;

  for (final aed in aeds.take(20)) {
    final cachedRoute = CacheService.getCachedRoute(
      currentState.userLocation!,
      aed.location,
      transportMode,
    );
    if (cachedRoute != null) {
      preloadedRoutes['${aed.id}_$transportMode'] = cachedRoute;
      updatedCount++;

      if (previewNeedsUpgrade &&
          aed.location.latitude == nav.destination!.latitude &&
          aed.location.longitude == nav.destination!.longitude) {
        destinationNowCached = true;
      }
    }
  }

  if (updatedCount > 0) {
    debugPrint(
        '♻️ Updated $updatedCount preloaded routes from cache ($transportMode)');
  }

  if (destinationNowCached) {
    unawaited(showNavigationPreviewForAED(nav.destination!));
  }
}
```
`unawaited` needed since `updatePreloadedRoutesFromCache` stays `void`/sync
(none of its 4 callers await it today — see item 5's table — so making it
`async` would be a bigger, unrequested signature change); `dart:async` is
already imported in this file.

**Re-entrancy / infinite-loop check, traced explicitly:**

I enumerated every call site of both methods (grep, not inference):
- `updatePreloadedRoutesFromCache` is called from exactly 4 places, all
  *async background callbacks* of `improveDistanceAccuracyInBackground* —
  `aed_map_widget.dart:402/511/792` and `aed_routing_coordinator.dart:755`.
  None of these run from inside `showNavigationPreviewForAED`'s own call
  stack; they're triggered independently by GPS-fix/AED-refresh/recenter/
  mode-change events.
- `showNavigationPreviewForAED` never calls `updatePreloadedRoutesFromCache`,
  directly or indirectly (checked `preloadBothTransportModes` too — it only
  calls `CacheService.setDistance`). So there's no A→B→A cycle in the call
  graph.
- After the new call succeeds, `showNavigationPreviewForAED` sets a real
  polyline via `mapNotifier.updateRoute(polyline, ...)` (since Step 1's RAM
  check now hits — we just wrote to `preloadedRoutes` above it), so
  `nav.route` becomes non-null and `previewNeedsUpgrade`'s gate closes for
  any subsequent call. **Not** a tight loop.

**The one real risk, not a crash but worth knowing:** the gate is
`nav.route == null`, and there's a second path that leaves `route` null
*without* it meaning "no route cached yet" — the `isTooOld` branch
(`mapNotifier.updateRoute(null, '', 0)`, `aed_routing_coordinator.dart:222-223`).
If a preview is open on a genuinely too-old cached location (not the
API-key bug — a real "no fresh GPS in N hours" case), `destinationNowCached`
can still flip true on some later background refresh (the destination AED's
route was cached earlier, e.g. by a previous session), and F3 will call
`showNavigationPreviewForAED` again — which will immediately re-hit the
`isTooOld` branch and set `route` back to `null`, leaving the gate open for
the *next* background refresh too. That's not infinite recursion (each call
is triggered by a distinct external event — a resort, an AED refetch, a
recenter — not by itself), but it does mean a stale-location preview could
re-trigger `showNavigationPreviewForAED` (and its `force: true` camera
re-zoom) repeatedly across a session, which is a minor UX annoyance
(map re-centering itself while the user's trying to pan around) rather than
a bug. Whether that's acceptable probably depends on how often
`updatePreloadedRoutesFromCache` actually runs in practice during an active
preview — worth a quick manual check once this is applied, not something I'd
block on.

---

## Summary of files touched by F1–F3

| File | Items |
|---|---|
| `lib/main.dart` | F1 |
| `lib/features/aed_map/services/aed_map_widget.dart` | F2 |
| `lib/features/aed_map/controllers/aed_routing_coordinator.dart` | F3 |

Nothing has been edited. Waiting for approval before applying any of the above.
