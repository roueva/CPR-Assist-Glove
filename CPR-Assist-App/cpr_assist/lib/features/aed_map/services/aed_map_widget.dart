import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location/location.dart' as loc;

import '../../../core/core.dart';
import '../../../models/aed_models.dart';
import '../../../providers/app_providers.dart';
import '../../../services/app_initialization_manager.dart';
import '../../../services/network/network_service.dart';
import '../widgets/aed_map_display.dart';
import 'cache_service.dart';
import 'location_service.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'map_service.dart';
import 'navigation_controller.dart' as nav;
import 'aed_cluster_renderer.dart';
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart'
as cluster_pkg;
import '../controllers/aed_location_controller.dart';
import '../controllers/aed_routing_coordinator.dart';

class AEDMapWidget extends ConsumerStatefulWidget {
  const AEDMapWidget({super.key});

  @override
  ConsumerState<AEDMapWidget> createState() => _AEDMapWidgetState();
}

class _AEDMapWidgetState extends ConsumerState<AEDMapWidget>
    with WidgetsBindingObserver {
  // ── Map infrastructure ────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  MapViewController? _mapViewController;
  final Completer<void> _mapReadyCompleter = Completer<void>();

  // ── Services ──────────────────────────────────────────────────────────────
  final LocationService _locationService = LocationService();

  // ── Controllers ───────────────────────────────────────────────────────────
  late AEDLocationController _locationController;
  late AEDRoutingCoordinator _routingCoordinator;
  nav.NavigationController? _navigationController;

  // ── Clustering ────────────────────────────────────────────────────────────
  Set<Marker> _aedMarkers = {};
  cluster_pkg.ClusterManager<AEDClusterItem>? _clusterManager;
  Timer? _clusterUpdateDebounce;
  List<AEDClusterItem>? _pendingClusterItems;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isLocationAvailable = true;

  // ── App state flags ───────────────────────────────────────────────────────
  bool _isInitializingApp      = false;
  bool _hasPerformedInitialZoom = false;
  bool _hasFetchedFreshAEDs    = false;
  bool _freshDataLoaded        = false;
  bool _isLoadingAEDs          = false;
  bool _wasOffline             = false;

  // ── Timers ────────────────────────────────────────────────────────────────
  Timer?    _transportModeDebouncer;
  DateTime? _lastResumeTime;
  DateTime? _lastBackgroundTime;
  DateTime? _lastProgrammaticCameraMove;

  // ══════════════════════════════════════════════════════════════════════════
  // INIT & DISPOSE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMapRenderer();
    NetworkService.addConnectivityListener(_onConnectivityChanged);

    _navigationController = nav.NavigationController(
      onStateChanged: () => setState(() {}),
      onRecenterButtonVisibilityChanged: (visible) => setState(() {}),
    );

    _routingCoordinator = AEDRoutingCoordinator(
      ref: ref,
      callbacks: AEDRoutingCallbacks(
        onStateChanged:       () { if (mounted) setState(() {}); },
        onArrived:            _onArrived,
        onOffRoute:           _showOffRouteBanner,
        onCloserAEDFound:     _showCloserAEDSnackbar,
        onStopNavigationGPS:  () => _locationController.stopGPSTracking(),
        onStartNavigationGPS: () =>
            _locationController.startGPSTracking(isNavigating: true),
      ),
    );
    _routingCoordinator.navigationController = _navigationController;

    _locationController = AEDLocationController(
      locationService: _locationService,
      ref: ref,
      callbacks: AEDLocationCallbacks(
        onLocationUpdate: _handleLocationUpdate,
        onFirstRealGPSFix: _handleFirstRealGPSFix,
        onShowLocationBanner: (newLoc, oldLoc) =>
            _locationController.showLocationUpdatedBanner(
                context, newLoc, oldLoc),
        onLocationAvailabilityChanged: (available) {
          if (mounted) setState(() => _isLocationAvailable = available);
          if (available) _locationController.setupLocationAfterEnable();
        },
        onZoomRequested: ({bool force = false, LatLng? knownLocation}) =>
            _zoomToUserAndAEDsIfReady(force: force, knownLocation: knownLocation),
        onResortRequested: _resortAEDs,
      ),
    );

    _locationController.startLocationServiceMonitoring();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isInitializingApp) _initializeApp();
    });

    // Safety valve — complete map ready after 15s no matter what.
    Future.delayed(const Duration(seconds: 15), () {
      if (!_mapReadyCompleter.isCompleted && mounted) {
        debugPrint('⚠️ Forcing map ready completion after 15s timeout');
        _mapReadyCompleter.complete();
      }
    });
  }

  void _initializeMapRenderer() {
    if (GoogleMapsFlutterPlatform.instance is GoogleMapsFlutterAndroid) {
      (GoogleMapsFlutterPlatform.instance as GoogleMapsFlutterAndroid)
          .useAndroidViewSurface = true;
    }
  }

  @override
  void dispose() {
    NetworkService.removeConnectivityListener(_onConnectivityChanged);
    _transportModeDebouncer?.cancel();
    _clusterUpdateDebounce?.cancel();

    _locationController.dispose();
    _routingCoordinator.dispose();
    _navigationController?.dispose();

    _aedMarkers.clear();
    _routingCoordinator.preloadedRoutes.clear();

    _mapController?.dispose();
    _mapViewController = null;
    _clusterManager   = null;

    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.completeError('Widget disposed');
    }

    CacheService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP STARTUP
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _initializeApp() async {
    if (_isInitializingApp) return;
    _isInitializingApp = true;

    try {
      final aedRepository = ref.read(aedServiceProvider);
      final apiKey = NetworkService.googleMapsApiKey;
      _routingCoordinator.setApiKey(apiKey);

      _clusterManager = cluster_pkg.ClusterManager<AEDClusterItem>(
        [],
        _onMarkersUpdated,
        markerBuilder: (cluster) =>
            AEDClusterManager.buildMarkerForCluster(cluster),
        stopClusteringZoom: 13,
        extraPercent: 0.5,
        levels: const [1, 4.25, 6.75, 8.25, 11.5, 14.5, 16.0, 16.5, 20.0],
      );

      final result = await AppInitializationManager.initializeApp(aedRepository);

      // Capture context-dependent objects before the async gap.
      final capturedContext = context;

      _mapReadyCompleter.future.then((_) async {
        if (!mounted) return;

        // Step 1: Seed cached location.
        if (result.userLocation != null) {
          await _handleLocationUpdate(result.userLocation!,
              fromCache: result.isLocationCached);
          if (result.isLocationCached) {
            if (mounted) setState(() {});
          }
        }

        // Step 2: Sort AEDs.
        List<AED> aedListForStartup = result.aedList;
        if (result.aedList.isNotEmpty && result.userLocation != null) {
          aedListForStartup = aedRepository.sortAEDsByDistance(
            result.aedList,
            result.userLocation,
            ref.read(mapStateProvider).navigation.transportMode,
          );
        }
        if (aedListForStartup.isNotEmpty) {
          ref.read(mapStateProvider.notifier).setAEDs(aedListForStartup);
        }

        // Step 3: Zoom.
        await _zoomToUserAndAEDsIfReady(
          knownLocation: result.userLocation,
          knownAEDs: aedListForStartup,
        );

        if (mounted && result.isLocationCached) setState(() {});

        // Step 4: Load markers.
        await Future.delayed(AppConstants.mapAnimationDelay);
        if (!mounted) return;
        if (aedListForStartup.isNotEmpty) {
          _loadAEDsProgressively(aedListForStartup);
        }

        // Step 5: GPS.
        final hasPermission  = await _locationService.hasPermission;
        final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

        if (!mounted) return;

        if (hasPermission && isServiceEnabled) {
          await _locationController.startGPSTracking(isNavigating: false);
        } else if (!hasPermission &&
            !_locationController.hasRequestedPermission) {
          if (!mounted) return;
          await _locationController.requestLocationPermission(
            mapReadyFuture:    _mapReadyCompleter.future,
            mapViewController: _mapViewController,
            context:           capturedContext,
          );
        } else if (hasPermission && !isServiceEnabled) {
          if (!mounted) return;
          final locService = loc.Location();
          final enabled = await locService.requestService();
          if (enabled && mounted) {
            await Future.delayed(const Duration(milliseconds: 500));
            await _locationController.setupLocationAfterEnable();
          }
        }

        // Step 6: Fetch fresh AEDs.
        if (result.isConnected) {
          Future.delayed(AppConstants.routePreloadDelay, () {
            if (mounted) _fetchFreshAEDsInBackground();
          });
        }
      });
    } catch (e, stack) {
      debugPrint('❌ App initialization error: $e\n$stack');
    } finally {
      _isInitializingApp = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MAP CREATED
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _onMapCreated(GoogleMapController controller) async {
    debugPrint('🗺️ Map created');
    _mapController = controller;
    _clusterManager?.setMapId(controller.mapId);

    if (_pendingClusterItems != null) {
      _clusterManager?.setItems(_pendingClusterItems!);
      _clusterManager?.updateMap();
      _pendingClusterItems = null;
    }

    _mapViewController = MapViewController(controller, context);
    _routingCoordinator.mapViewController = _mapViewController;

    _navigationController?.initialize(controller);
    _routingCoordinator.navigationController = _navigationController;

    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.complete();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION UPDATE HANDLERS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _handleLocationUpdate(LatLng location,
      {bool fromCache = false}) async {
    final mapNotifier     = ref.read(mapStateProvider.notifier);
    final currentState    = ref.read(mapStateProvider);
    final LatLng? previousLocation = currentState.userLocation;
    final bool wasLocationNull     = previousLocation == null;

    mapNotifier.updateUserLocation(location);

    _routingCoordinator.isUsingCachedLocation =
        _locationController.isUsingCachedLocation;

    if (wasLocationNull) {
      _locationController.cacheUserRegion(location);

      if (currentState.aedList.isNotEmpty) {
        final aedRepository = ref.read(aedServiceProvider);
        final sortedForZoom = aedRepository.sortAEDsByDistance(
          currentState.aedList,
          location,
          currentState.navigation.transportMode,
        );
        ref.read(mapStateProvider.notifier).setAEDs(sortedForZoom);
        _routingCoordinator.scheduleRoutePreloading();

        await _zoomToUserAndAEDsIfReady(
          knownLocation: location,
          knownAEDs: sortedForZoom,
        );
      }

      if (currentState.navigation.hasStarted &&
          _navigationController?.isActive == true) {
        _navigationController!.updateUserLocation(location);
      }
      return;
    }

    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null) {
      await _routingCoordinator.handleNavigationLocationUpdate(location);
    }

    if (mounted) setState(() {});
  }

  Future<void> _handleFirstRealGPSFix(LatLng location) async {
    debugPrint('🛰️ First real GPS fix — clearing stale distances and resorting');
    CacheService.clearDistanceCache();

    final currentState  = ref.read(mapStateProvider);
    final aedRepository = ref.read(aedServiceProvider);
    final freshSorted   = aedRepository.sortAEDsByDistance(
      currentState.aedList,
      location,
      currentState.navigation.transportMode,
    );

    ref.read(mapStateProvider.notifier).setAEDs(freshSorted);

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    _hasPerformedInitialZoom = false;
    await _zoomToUserAndAEDsIfReady(
      force: true,
      knownLocation: location,
      knownAEDs: freshSorted,
    );

    if (mounted) setState(() {});
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ZOOM
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _zoomToUserAndAEDsIfReady({
    bool force = false,
    LatLng? knownLocation,
    List<AED>? knownAEDs,
  }) async {
    if (_hasPerformedInitialZoom && !force) return;
    if (_mapViewController == null) return;

    final currentState = ref.read(mapStateProvider);
    final userLocation = knownLocation ?? currentState.userLocation;
    final aeds = (knownAEDs != null && knownAEDs.isNotEmpty)
        ? knownAEDs
        : currentState.aedList;

    if (userLocation == null || aeds.isEmpty) return;

    final targets = aeds.take(2).map((a) => a.location).toList();
    _hasPerformedInitialZoom = true;

    if (targets.isEmpty) {
      await _mapViewController!.zoomToAED(userLocation);
    } else {
      await _mapViewController!.zoomToUserAndClosestAEDs(userLocation, targets);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // AED DATA MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchFreshAEDsInBackground() async {
    if (_hasFetchedFreshAEDs) return;
    _hasFetchedFreshAEDs = true;

    try {
      final aedRepository = ref.read(aedServiceProvider);
      final currentState  = ref.read(mapStateProvider);
      final mapNotifier   = ref.read(mapStateProvider.notifier);

      final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);
      if (freshAEDs.isEmpty || !mounted) return;

      if (!aedRepository.haveAEDsChanged(currentState.aedList, freshAEDs)) {
        debugPrint('✅ AED data unchanged');
        if (mounted && _locationController.isUsingCachedLocation) {
          setState(() {});
        }
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) _routingCoordinator.preloadTopRoutes();
        });
        return;
      }

      if (mounted && _locationController.isUsingCachedLocation) {
        setState(() {});
      }

      final sorted = aedRepository.sortAEDsByDistance(
        freshAEDs,
        currentState.userLocation,
        currentState.navigation.transportMode,
      );

      _freshDataLoaded = true;
      mapNotifier.setAEDs(sorted);
      if (!_hasPerformedInitialZoom) await _zoomToUserAndAEDsIfReady();
      _addMarkersToMap(sorted);

      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _routingCoordinator.preloadTopRoutes();
      });
    } catch (e) {
      debugPrint('⚠️ Background AED fetch failed: $e');
    }
  }

  void _loadAEDsProgressively(List<AED> allAEDs) {
    _isLoadingAEDs = true;
    const firstBatch = 50;
    const batchSize  = 200;
    const batchDelay = Duration(milliseconds: 50);

    ref.read(mapStateProvider.notifier).setAEDs(allAEDs.take(firstBatch).toList());

    Future(() async {
      int loaded = firstBatch;
      while (loaded < allAEDs.length) {
        await Future.delayed(batchDelay);
        if (!mounted) return;
        if (_freshDataLoaded && loaded > firstBatch) break;
        final end = (loaded + batchSize).clamp(0, allAEDs.length);
        ref.read(mapStateProvider.notifier).setAEDs(allAEDs.sublist(0, end));
        loaded += batchSize;
      }
      if (!mounted) return;
      _isLoadingAEDs = false;
      _addMarkersToMap(allAEDs);
    });
  }

  void _addMarkersToMap(List<AED> aeds) {
    final items = aeds
        .map((aed) => AEDClusterItem(
        aed, _routingCoordinator.showNavigationPreviewForAED))
        .toList();

    if (_mapController == null) {
      _pendingClusterItems = items;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _clusterManager?.setItems(items);
      _clusterUpdateDebounce?.cancel();
      _clusterUpdateDebounce = Timer(
        const Duration(milliseconds: 150),
            () { _clusterManager?.updateMap(); },
      );
    });
  }

  void _onMarkersUpdated(Set<Marker> markers) {
    if (mounted) setState(() => _aedMarkers = markers);
  }

  void _resortAEDs() {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation == null || currentState.aedList.isEmpty) return;

    final aedRepository = ref.read(aedServiceProvider);
    final newSorted = aedRepository.sortAEDsByDistance(
      currentState.aedList,
      currentState.userLocation!,
      currentState.navigation.transportMode,
    );

    final checkCount = newSorted.length < 5 ? newSorted.length : 5;
    bool topChanged = false;
    for (int i = 0; i < checkCount; i++) {
      if (currentState.aedList[i].id != newSorted[i].id) {
        topChanged = true;
        break;
      }
    }

    if (topChanged) {
      ref.read(mapStateProvider.notifier).updateAEDs(newSorted);

      final top10Changed = newSorted.length >= 10 &&
          currentState.aedList.length >= 10 &&
          !newSorted
              .take(10)
              .map((a) => a.id)
              .toSet()
              .containsAll(
              currentState.aedList.take(10).map((a) => a.id).toSet());

      if (top10Changed) _routingCoordinator.scheduleRoutePreloading();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONNECTIVITY
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _onConnectivityChanged(bool isConnected) async {
    final currentState = ref.read(mapStateProvider);
    if (!mounted) return;

    if (currentState.isOffline && isConnected) {
      debugPrint('🟢 Connection restored!');
      _wasOffline = false;
      ref.read(mapStateProvider.notifier).setOffline(false);

      final apiKey = NetworkService.googleMapsApiKey;
      _routingCoordinator.setApiKey(apiKey);

      await Future.delayed(Duration.zero);
      if (!mounted) return;

      final aedRepository  = ref.read(aedServiceProvider);
      final updatedState   = ref.read(mapStateProvider);

      try {
        final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);
        if (!mounted) return;

        final sortedAEDs = aedRepository.sortAEDsByDistance(
          freshAEDs,
          updatedState.userLocation ?? currentState.userLocation,
          updatedState.navigation.transportMode,
        );
        ref.read(mapStateProvider.notifier).setAEDs(sortedAEDs);

        if (updatedState.navigation.isActive &&
            updatedState.navigation.destination != null &&
            updatedState.userLocation != null) {
          if (updatedState.navigation.hasStarted) {
            await _routingCoordinator.recalculateActiveRoute();
          } else {
            await _routingCoordinator.showNavigationPreviewForAED(
                updatedState.navigation.destination!);
          }
        }

        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) _routingCoordinator.preloadTopRoutes();
        });
      } catch (e) {
        debugPrint('❌ Error updating AEDs on connectivity restore: $e');
      }
    } else if (!currentState.isOffline && !isConnected) {
      debugPrint('🔴 Connection lost');
      _wasOffline = true;
      ref.read(mapStateProvider.notifier).setOffline(true);

      if (currentState.navigation.isActive) {
        await _routingCoordinator.switchNavigationToOfflineMode();
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CAMERA EVENTS
  // ══════════════════════════════════════════════════════════════════════════

  void _onCameraMoveStarted() {
    if (_lastProgrammaticCameraMove != null &&
        DateTime.now().difference(_lastProgrammaticCameraMove!) <
            const Duration(milliseconds: AppConstants.programmaticMoveDurationMs)) {
      return;
    }

    if (ref.read(mapStateProvider).navigation.hasStarted) {
      _navigationController?.onCameraMoveStarted();
    }
  }

  void _onCameraMoved(CameraPosition position) {
    _clusterManager?.onCameraMove(position);

    if (_lastProgrammaticCameraMove != null &&
        DateTime.now().difference(_lastProgrammaticCameraMove!) <
            const Duration(milliseconds: AppConstants.programmaticMoveDurationMs)) {
      return;
    }

    if (ref.read(mapStateProvider).navigation.hasStarted) {
      _navigationController?.onCameraMoved();
    }
  }

  void _onCameraIdle() async {
    if (_isLoadingAEDs) return;
    if (_lastProgrammaticCameraMove != null &&
        DateTime.now().difference(_lastProgrammaticCameraMove!) <
            const Duration(milliseconds: 800)) {
      return;
    }

    if (_mapController != null) {
      _clusterManager?.updateMap();
    }
  }

  void _recenterNavigation() {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null) {
      _navigationController?.recenterAndResumeTracking(currentState.userLocation!);
    }
  }

  Future<void> _recenterMapToUserAndAEDs(
      {bool allowLocationPrompt = false}) async {
    if (allowLocationPrompt) {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        final enabled =
        await _locationController.promptAndEnableLocationService();
        if (!enabled) return;
        return;
      }
    }

    final currentState = ref.read(mapStateProvider);

    LatLng? freshLocation;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 3));
      freshLocation = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      freshLocation = currentState.userLocation;
    }

    if (!mounted) return;

    if (freshLocation != null) {
      final aedRepository = ref.read(aedServiceProvider);
      final updatedState  = ref.read(mapStateProvider);
      final freshSorted   = aedRepository.sortAEDsByDistance(
        updatedState.aedList,
        freshLocation,
        updatedState.navigation.transportMode,
      );
      if (freshSorted.length >= 2) {
        await _zoomToUserAndAEDsIfReady(
          force: true,
          knownLocation: freshLocation,
          knownAEDs: freshSorted,
        );
      }
      return;
    }

    final userLocation = await _locationService.getCurrentLocationWithUI(
      context: context,
      showPermissionDialog: allowLocationPrompt,
      showErrorMessages:    allowLocationPrompt,
    );

    if (!mounted) return;

    if (userLocation != null) {
      await _handleLocationUpdate(userLocation);
      final aedRepository = ref.read(aedServiceProvider);
      final updatedState  = ref.read(mapStateProvider);
      final freshSorted   = aedRepository.sortAEDsByDistance(
        updatedState.aedList,
        userLocation,
        updatedState.navigation.transportMode,
      );
      if (freshSorted.length >= 2) {
        await _zoomToUserAndAEDsIfReady(force: true);
      }
      return;
    }

    final state = ref.read(mapStateProvider);
    if (state.navigation.hasStarted && state.navigation.destination != null) {
      await _mapViewController?.zoomToAED(state.navigation.destination!);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NAVIGATION UI CALLBACKS
  // ══════════════════════════════════════════════════════════════════════════

  void _onArrived() {
    _navigationController?.cancelNavigation();
    ref.read(mapStateProvider.notifier).cancelNavigation();
    _locationController.startGPSTracking(isNavigating: false);

    UIHelper.showSnackbar(
      context,
      message:         'You have arrived at the AED',
      icon:            Icons.check_circle,
      backgroundColor: AppColors.success,
      duration:        const Duration(seconds: 4),
    );
  }

  void _showOffRouteBanner() {
    if (!mounted) return;
    UIHelper.showSnackbar(
      context,
      message:         'Recalculating route...',
      icon:            Icons.warning_amber_rounded,
      backgroundColor: AppColors.warning,
      duration:        const Duration(seconds: 2),
    );
  }

  void _showCloserAEDSnackbar(AED closerAED, double distance) {
    if (!mounted) return;
    UIHelper.clearSnackbars(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline,
                color: AppColors.textOnDark, size: AppSpacing.iconMd),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Closer AED found (${LocationService.formatDistance(distance)})',
                style: AppTypography.bodyMedium(color: AppColors.textOnDark),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration:        const Duration(seconds: 6),
        behavior:        SnackBarBehavior.floating,
        action: SnackBarAction(
          label:     'Switch',
          textColor: AppColors.textOnDark,
          onPressed: () => _routingCoordinator.switchToCloserAED(closerAED),
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusSm)),
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _resumeApp();
    } else if (state == AppLifecycleState.paused) {
      _pauseApp();
    }
  }

  void _resumeApp() async {
    final now = DateTime.now();
    if (_lastResumeTime != null &&
        now.difference(_lastResumeTime!).inSeconds < 2) {
      return;
    }
    _lastResumeTime = now;

    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final hasPermission    = await _locationService.hasPermission;
    final shouldHaveLocation = isServiceEnabled && hasPermission;

    if (!_isLocationAvailable && shouldHaveLocation) {
      setState(() => _isLocationAvailable = true);
      await _locationController.setupLocationAfterEnable();
    } else if (_isLocationAvailable && !shouldHaveLocation) {
      setState(() => _isLocationAvailable = false);
    }

    if (!mounted) return;

    final isConnected  = await NetworkService.isConnected();
    final currentState = ref.read(mapStateProvider);

    if (_wasOffline && isConnected) {
      _wasOffline = false;
      ref.read(mapStateProvider.notifier).setOffline(false);

      final aedRepository = ref.read(aedServiceProvider);
      final freshAEDs     = await aedRepository.fetchAEDs(forceRefresh: true);

      if (!mounted) return;

      if (freshAEDs.isNotEmpty) {
        final sortedAEDs = aedRepository.sortAEDsByDistance(
          freshAEDs,
          currentState.userLocation,
          currentState.navigation.transportMode,
        );
        ref.read(mapStateProvider.notifier).setAEDs(sortedAEDs);
      }
    } else if (!_wasOffline && !isConnected) {
      _wasOffline = true;
      ref.read(mapStateProvider.notifier).setOffline(true);
    }

    final shouldCheckUpdates = _lastBackgroundTime != null &&
        now.difference(_lastBackgroundTime!).inMinutes > 2 &&
        currentState.aedList.isNotEmpty;

    if (shouldCheckUpdates && isConnected) {
      final aedRepository = ref.read(aedServiceProvider);
      try {
        final newAEDs   = await aedRepository.fetchAEDs(forceRefresh: false);
        if (!mounted) return;

        final changed = aedRepository.haveAEDsChanged(currentState.aedList, newAEDs);
        if (changed) {
          final sortedAEDs = aedRepository.sortAEDsByDistance(
            newAEDs,
            currentState.userLocation,
            currentState.navigation.transportMode,
          );
          ref.read(mapStateProvider.notifier).updateAEDs(sortedAEDs);
        }
      } catch (e) {
        debugPrint('⚠️ Error checking AED updates: $e');
      }
    }

    if (_lastBackgroundTime != null &&
        DateTime.now().difference(_lastBackgroundTime!).inMinutes >= 5) {
      _hasFetchedFreshAEDs = false;
    }
  }

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

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapStateProvider);

    return AEDMapDisplay(
      config: AEDMapConfig(
        isLoading:             mapState.isLoading,
        aedMarkers:            _aedMarkers,
        userLocation:          mapState.userLocation,
        userLocationAvailable: _isLocationAvailable,
        mapController:         _mapController,
        navigationLine:        mapState.navigation.route,
        estimatedTime:         mapState.navigation.estimatedTime,
        selectedAED:           mapState.navigation.destination,
        aedLocations:          mapState.aedList.map((aed) => aed.location).toList(),
        selectedMode:          mapState.navigation.transportMode,
        aeds:                  mapState.aedList,
        isRefreshingAEDs:      mapState.isRefreshing,
        hasSelectedRoute:      mapState.navigation.isActive,
        navigationMode:        mapState.navigation.isActive,
        distance:              mapState.navigation.distance,
        isOffline:             mapState.isOffline,
        preloadedRoutes:       _routingCoordinator.preloadedRoutes,
        isPreloadingRoutes:    false,
        currentBearing:        _navigationController?.currentHeading,
        isFollowingUser:       _navigationController?.isActive ?? false,
        showRecenterButton:    _navigationController?.showRecenterButton ?? false,
        hasStartedNavigation:  mapState.navigation.hasStarted,
        isUsingCachedLocation: !_locationController.hasRealGPSFix,
        isManuallySearchingGPS: _locationController.isManuallySearchingGPS,
        gpsSearchSuccess:      _locationController.gpsSearchSuccess,
        isLocationStale:       _locationController.isLocationStale(),
        locationAge: _locationController.locationLastUpdated != null
            ? DateTime.now()
            .difference(_locationController.locationLastUpdated!)
            .inHours
            : null,
      ),
      onSmallMapTap:       _routingCoordinator.showNavigationPreviewForAED,
      onPreviewNavigation: _routingCoordinator.showNavigationPreviewForAED,
      userLocationAvailable: _isLocationAvailable,
      onStartNavigation: (aedLocation) async {
        await _routingCoordinator.startNavigation(
          aedLocation,
          isUsingCachedOrStaleLocation:
          _locationController.isUsingCachedLocation ||
              _locationController.isLocationStale(),
          isStale:          _locationController.isLocationStale(),
          isTooOld:         _locationController.isLocationTooOld(),
          locationService:  _locationService,
          context:          context,
        );
      },
      onManualGPSSearch: () => _locationController.startManualGPSSearch(() {
        if (mounted) setState(() {});
      }),
      onCameraMoved:         _onCameraMoved,
      onCameraMoveStarted:   _onCameraMoveStarted,
      onCameraIdle:          _onCameraIdle,
      onRecenterNavigation:  _recenterNavigation,
      onTransportModeSelected: (mode) {
        _transportModeDebouncer?.cancel();
        _transportModeDebouncer =
            Timer(AppConstants.routePreloadDelay, () async {
              if (!mounted) return;
              await _routingCoordinator.onTransportModeChanged(
                mode,
                context: context,
                aedRepository: ref.read(aedServiceProvider),
              );
            });
      },
      onRecenterPressed:  () =>
          _recenterMapToUserAndAEDs(allowLocationPrompt: true),
      onMapCreated:       _onMapCreated,
      onCancelNavigation: () =>
          _routingCoordinator.cancelNavigation(_mapController),
      onExternalNavigation: (destination) =>
          _routingCoordinator.openExternalNavigation(destination, context),
    );
  }
}