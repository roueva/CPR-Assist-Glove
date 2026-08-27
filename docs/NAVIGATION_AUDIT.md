# Navigation & Location Audit

> **Correction — 2026-08-28:** the "Location too old (≥5h, cached)" scenario
> below (marked ✅) was disproved by a later audit. `isLocationTooOld()` — and
> `isLocationStale()` alongside it — gate on `_isUsingCachedLocation`, which is
> never set `true` by any reachable path in this codebase, so both always
> return `false` and the scenario described here was unreachable, not
> verified-working. See `LOCATION_STALENESS_AUDIT.md` for the full trace and
> the fix.

Read-only. No files edited. Scope: `CPR-Assist-App/cpr_assist/lib/features/aed_map/**`
(map widget, routing coordinator, navigation controller, location controller,
location/route/map services, and the panel/overlay widgets).

Files read in full: `aed_map_widget.dart`, `aed_routing_coordinator.dart`,
`navigation_controller.dart`, `aed_location_controller.dart`, `location_service.dart`,
`map_service.dart`, `route_service.dart`, `aed_service.dart`, `aed_cluster_renderer.dart`,
`aed_map_display.dart`, `aed_map_panels.dart`, `aed_map_cards.dart`, `aed_map_overlays.dart`,
`app_constants.dart`. Also inspected the `google_maps_cluster_manager_2` package source
(v3.2.0, from pub cache) to check what its cluster-tap default actually does.

---

## Bug 1 — Tapping a clustered AED marker on the map does nothing

**File:** `lib/features/aed_map/services/aed_cluster_renderer.dart:128-134`

```dart
// Multiple AEDs — use your green circle icon
return Marker(
  markerId: MarkerId(cluster.getId()),
  position: cluster.location,
  icon: await getClusterIcon(cluster.count),
  onTap: () {}, // zoom-in tap handled separately
);
```

The comment claims tapping a cluster bubble zooms in "separately." I checked every call
site and the package source (`google_maps_cluster_manager_2` 3.2.0,
`ClusterManager` in `cluster_manager.dart`) — there is no such handler anywhere.
The package's own default marker builder (`_basicMarkerBuilder`) only
`print()`s the cluster in debug mode; it never zooms. This app supplies its
own `markerBuilder` (`AEDClusterManager.buildMarkerForCluster`), and for any
marker that represents more than one AED, `onTap` is a literal no-op.

**Effect:** any AED currently grouped into a cluster bubble (anything within
~80 m of another AED — `AppConstants.aedClusterRadius`) is untappable on the
map. No zoom, no route preview, nothing visibly happens. Clustering is active
at every zoom level below `stopClusteringZoom: 12`, i.e. essentially any
zoomed-out view of AEDs beyond the immediate area — which is exactly where
"AEDs that aren't in the top 3" tend to sit relative to the ones already
merged into a cluster.

**This is very likely the cause of "no route for AEDs not in the top 3"** if
the AEDs in question are being tapped on the map itself. Tapping the *same*
AEDs from the list panel is unaffected (see below) — the list never gates on
rank.

Confirmed **not** broken: individual (non-clustered) markers correctly call
`item.onTap(item.aed.location)` → `AEDRoutingCoordinator.showNavigationPreviewForAED`,
and every list-panel card (`AEDListPanel`'s "Nearest" card, the `others`
`SliverList`, and `AEDSideListPanel`) wires `onTap`/`onPreviewNavigation` to
the same function regardless of the AED's position in the sorted list —
`aed_map_panels.dart:157,283,336,494`. I traced `showNavigationPreviewForAED`
end to end (RAM cache → fresh Directions fetch → disk cache → offline
straight-line estimate) and found no rank-based gate there either.

**Suggested fix (not applied):** give the cluster marker a real `onTap` —
either zoom the camera into the cluster's bounds (there's already
`MapViewController.getBoundsFromPoints`/`getClosestAEDsToPoint` to build on),
or, since these clusters are usually just 2-3 close-together AEDs, zoom to
`stopClusteringZoom` centered on `cluster.location`.

---

## Bug 2 — Recenter button and KSL logo disappear during route preview (portrait)

**File:** `lib/features/aed_map/widgets/aed_map_panels.dart` — `AEDNavigationPanel`
(shown when `hasSelectedRoute && !hasStartedNavigation`, i.e. after tapping an
AED but before pressing "Start Navigation").

| Panel | State | Recenter button | KSL logo |
|---|---|---|---|
| `AEDListPanel` | browsing | ✅ top-right (`aed_map_panels.dart:90`) | ✅ top-left (`:86`) |
| `AEDNavigationPanel`, portrait | preview | ❌ none | ❌ none |
| `AEDNavigationPanel`, landscape/side | preview | ✅ (`:764`) | ❌ none |
| `AEDActiveNavigationPanel` | live turn-by-turn | ⚠️ conditional "Recenter" chip only when the user has panned away (`:1225`, gated on `showRecenterButton`) | ❌ none |

In portrait — the common case — `AEDNavigationPanel.build`'s `content()`
closure (`:591-747`) has no recenter button and no KSL button at all; the
`Stack`/`AEDRecenterButton` pairing only exists in the `isSidePanel` branch
(`:749-772`), and even that branch never adds the KSL logo. So today: once
you tap an AED, both controls vanish and don't come back until you either
cancel back to the list or start live navigation (where a *different*,
intentionally-conditional recenter chip takes over).

This matches what was reported: the recenter button and KSL logo should
stay visible through the preview ("active navigation" — route selected, not
yet started) and only disappear once live turn-by-turn navigation begins.
The live-navigation panel's behavior (no permanent recenter button, no KSL,
only the pan-away "Recenter" chip) already matches the intended "hidden in
live" state and does not need to change.

**Suggested fix (not applied):** add the same `_KSLButton` (top-left) +
`AEDRecenterButton` (top-right) pairing used in `AEDListPanel` to
`AEDNavigationPanel`'s portrait `content()`, and add the `_KSLButton` to its
existing landscape/side-panel branch. `onRecenterPressed` is already threaded
through to this widget (`aed_map_panels.dart:518`); `onKSLTap` would need to
be threaded down the same way `AEDListPanel` receives it
(`aed_map_display.dart:307` → would need to add `onKSLTap:` to the
`AEDNavigationPanel(...)` construction at `:320-332`).

---

## Scenario walkthrough

Everything below was traced from the actual code paths, not assumed from
naming. ✅ = looks correct. ⚠️ = works but has a rough edge worth knowing
about. 🛑 = confirmed bug (the two above).

### Startup / location acquisition

- **Cold start, cached location + cached AEDs available** — `_initializeApp`
  seeds `userLocation` from cache (`fromCache: true`), sorts and displays AEDs
  immediately, zooms to user+2 closest, then starts the real GPS stream. ✅
- **Cold start, no cache at all (first-ever launch)** — no `userLocation`
  yet, map falls back to `AppConstants.greeceCenter` at `greeceZoom` until a
  real fix arrives (`aed_map_display.dart:369-373`). ✅
- **First real GPS fix arrives after a cached fix** —
  `_handleFirstRealGPSFix` clears the stale distance cache, re-sorts with the
  real location, force-zooms, and kicks off background road-distance
  improvement for the top AEDs. ✅
- **Permission denied** — `requestLocationPermission` leaves
  `_isLocationAvailable = false`; app stays usable at the Greece/cached view,
  `myLocationEnabled` on the map is gated on `userLocationAvailable`. ✅
- **Permission granted, GPS service off** — `_initializeApp` step 5 detects
  `hasPermission && !isServiceEnabled` and prompts via `Location().requestService()`.
  If the user declines, the app just... stays without location; there's no
  explicit "GPS still off" UI state distinct from "no permission" in this
  path, but nothing crashes. ⚠️ minor — the "No GPS" chip in
  `AEDNavigationPanel._buildStatusBanners` covers this either way.
- **Location services toggled off mid-session (OS-level)** —
  `startLocationServiceMonitoring`'s stream fires `onLocationAvailabilityChanged(false)`,
  UI reflects it via `_isLocationAvailable`. Toggled back on →
  `setupLocationAfterEnable()` restarts the GPS stream. ✅
- **Location stale (1h–5h old, cached)** — `isLocationStale()` → true;
  surfaced as a "Locating…" spinner chip in the preview panel
  (`_buildStatusBanners`, `showCached`). ✅
- **Location too old (≥5h, cached)** — `isLocationTooOld()` → true. Preview:
  `showNavigationPreviewForAED` skips the fetch and clears the route
  (`updateRoute(null, '', 0)`) rather than showing a stale/wrong route. Start:
  `startNavigation` routes into compass-only mode instead of GPS-tracked
  navigation. Both are deliberate, sane fallbacks. ✅

### Tapping / previewing an AED

- **Tap nearest AED card** — `onSmallMapTap` → `showNavigationPreviewForAED`.
  RAM-cache hit is near-instant (usually preloaded); cache miss triggers a
  live Directions fetch. ✅
- **Tap "Other" AED card (any rank, not just top 3)** — same function via
  `onPreviewNavigation`. Confirmed not rank-gated. ✅
- **Tap a clustered AED marker on the map** — 🛑 **Bug 1** — no-op.
- **Tap an unclustered AED marker on the map** — works, same as list cards. ✅
- **No GPS at all when previewing** — `showNavigationPreviewForAED` shows the
  AED location only, no distance/route (`currentLocation == null` branch). ✅
- **Offline when previewing** — skips the live fetch, falls back to disk
  cache, and if that also misses, shows a straight-line distance/ETA
  estimate with **no polyline** (`route: null`). This is intentional (you
  can't draw a real road route without a route), but it means an offline
  preview never shows a line at all, only numbers — worth confirming that's
  the desired UX, since it can look identical to a "nothing happened" tap at
  a glance. ⚠️
- **Preview zoom while a previous camera animation is still running** —
  `MapViewController.zoomToUserAndAED` has `if (_isAnimating) return;` with no
  `force` escape hatch (unlike `zoomToUserAndClosestAEDs`, which does accept
  `force`). Rapidly tapping between AEDs, or tapping right after the initial
  overview zoom, can silently drop a camera move. The route/ETA still update
  correctly since those don't depend on the camera call — only the
  "fit user + AED in view" framing can be skipped. ⚠️

### Starting / running live navigation

- **Start with fresh GPS** — caches route, sets `originalRouteMetrics` for
  smart ETA decay, starts the compass-tracking camera. ✅
- **Start with cached/stale location** — `startNavigation` fetches one
  fresh high-accuracy fix first (`locationService.getCurrentPosition`,
  10 s timeout) before computing the route, showing a "Getting precise
  location..." loading toast. ✅
- **Start with location too old / no GPS** — compass-only mode
  (`startCompassOnlyMode`), `AEDCompassIndicator` shown instead of a route
  line, matches `hasStartedNavigation && navigationLine == null` in
  `AEDActiveNavigationPanel`. ✅
- **Off-route detection** — `calculateRemainingRouteDistance` finds the
  closest point on the cached polyline; beyond `offRouteDistanceThreshold`
  (25 m) it's flagged, triggers a re-fetch and (rate-limited to once per 10s)
  a "Recalculating route..." banner. ✅
- **Closer AED appears mid-route** — `_checkForCloserAED` compares current
  destination distance vs. the list's current nearest, with a same-AED
  tolerance and a 100 m threshold, rate-limited to one notification per
  60 s. Reasonable. ✅
- **Arrival** — triggered purely by proximity to destination
  (`navigationArrivalRadius = 30 m`) inside `handleNavigationLocationUpdate`,
  independent of route state — works even in compass-only/offline mode since
  it's a straight-line distance check. ✅
- **Connectivity lost during navigation** — `_onConnectivityChanged` calls
  `switchNavigationToOfflineMode()`, which recomputes distance/ETA from
  straight-line + multiplier and clears the route line. Camera/compass
  tracking keeps running throughout (it doesn't depend on connectivity). ✅
- **Connectivity restored during navigation** — `recalculateActiveRoute()`
  re-fetches the real route and re-checks for a closer AED. ✅
- **Transport mode changed mid-navigation** — re-fetches the route for the
  new mode and updates `originalRouteMetrics`; mid-preview (not yet started)
  it just re-runs the preview. ✅
- **Cancel navigation from preview** — returns to the list view. **This is
  where Bug 2 lives** — the recenter/KSL controls should have already been
  visible in the state being cancelled *out of*.
- **Cancel from live navigation** — stops GPS high-accuracy tracking
  (`onStopNavigationGPS`), stops the camera ticker, clears
  `_previousUserLocation`/`_targetPosition`. ✅

### Recenter / camera

- **Manual recenter tap (list state)** — `_recenterMapToUserAndAEDs` grabs
  one fresh high-accuracy fix (5 s timeout, falls back to last known on
  timeout), re-sorts AEDs, re-zooms, then improves distances in the
  background. ✅
- **Recenter during live navigation** — `recenterAndResumeTracking` recentres
  the camera and clears `userControlling` state to resume compass-follow;
  gated on `showRecenterButton`, which only turns on after the
  `NavigationController` detects the user has manually panned/dragged the
  map (`onCameraMoveStarted`/`onCameraMoved`). ✅
- **Recenter during preview (route selected, not started)** — 🛑 same as
  Bug 2: the button isn't there to press in portrait.

---

## Secondary / lower-priority notes (not requested fixes, just noticed in passing)

- `AEDRoutingCoordinator._isLocationTooOld(AEDMapState state)` ignores its
  `state` parameter entirely and just returns the coordinator's own
  `isLocationTooOld` field — not a bug (the field is kept in sync
  externally), but the parameter is dead and slightly misleading to read.
- `MapViewController.zoomToUserAndAED` / `zoomToRouteWithEndpoints` have no
  `force` override on `_isAnimating`, unlike `zoomToUserAndClosestAEDs`. See
  the "Preview zoom while a previous animation is running" note above.
- `RoutePreloader.preloadRoutesForClosestAEDs` runs the up-to-10-AED,
  two-transport-mode preload sequentially with a 1-2 s delay between each
  call (`route_service.dart:435-441`) — worst case around 20-40 s to finish
  warming the cache for all 10. Doesn't block anything user-facing (previews
  still fetch live on a cache miss), but it's why the first minute or two
  after a fresh AED fetch has thinner RAM-cache coverage than it will
  eventually have.
