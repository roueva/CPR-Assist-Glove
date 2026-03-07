import 'dart:async';
import 'dart:math';
import 'package:cpr_assist/services/aed_map/aed_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/aed_models.dart';
import '../../providers/app_providers.dart';
import '../../screens/ui_helper.dart';
import '../../utils/app_constants.dart';
import '../app_initialization_manager.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../network_service.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'map_service.dart';
import 'route_service.dart';
import '../../screens/aed_map_display.dart';
import 'navigation_controller.dart' as nav;
import 'aed_cluster_renderer.dart';
import 'package:google_maps_cluster_manager_2/google_maps_cluster_manager_2.dart' as cluster_pkg;
import 'package:location/location.dart' as loc;

class AEDMapWidget extends ConsumerStatefulWidget {
  const AEDMapWidget({super.key});

  @override
  ConsumerState<AEDMapWidget> createState() => _AEDMapWidgetState();
}

class _AEDMapWidgetState extends ConsumerState<AEDMapWidget> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  String? _googleMapsApiKey;
  final LocationService _locationService = LocationService();
  DateTime? _lastResumeTime;


  // ✅ ADD: New controllers
  late GPSController _gpsController;
  late RouteHelper _routeHelper;

  // Keep these (UI state)
  final Completer<void> _mapReadyCompleter = Completer<void>();
  MapViewController? _mapViewController;
  bool _isLocationAvailable = true;
  DateTime? _lastBackgroundTime;

  bool _wasOffline = false;
  String _lastFetchReason = '';


  // Navigation & routes
  final Map<String, RouteResult> _preloadedRoutes = {};
  nav.NavigationController? _navigationController;
  RoutePreloader? _routePreloader;
  List<AEDClusterItem>? _pendingClusterItems;

  // Clustering
  Set<Marker> _aedMarkers = {};  // rename from _clusterMarkers
  double _currentZoom = 12.0;    // still needed for tap zoom jump
  cluster_pkg.ClusterManager<AEDClusterItem>? _clusterManager;
  Timer? _clusterUpdateDebounce;


  // Location state
  DateTime? _locationLastUpdated;
  bool _isUsingCachedLocation = false;
  bool _isManuallySearchingGPS = false;
  bool _gpsSearchSuccess = false;
  bool _isSettingUpLocation = false;
  StreamSubscription<Position>? _manualGPSSubscription;

  // Flags
  bool _hasPerformedInitialZoom = false;
  bool _hasRequestedPermission = false;
  bool _isInitializingApp = false;
  bool _isCurrentlyNavigating = false;
  bool _isRouteFetchInProgress = false;
  bool _hasFetchedFreshAEDs = false;
  bool _freshDataLoaded = false;
  bool _isLoadingAEDs = false;

  // Timers & throttling
  DateTime? _lastResortTime;
  DateTime? _lastCloserAEDNotification;
  DateTime? _lastProgrammaticCameraMove;
  DateTime? _lastRouteUpdateTime;
  LatLng? _lastRouteUpdateLocation;
  DateTime? _lastOffRouteBannerTime;
  Timer? _transportModeDebouncer;


  // ==================== APP STARTUP & INITIALIZATION ====================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMapRenderer();
    NetworkService.addConnectivityListener(_onConnectivityChanged);
    _startLocationServiceMonitoring();

    _gpsController = GPSController(
      _locationService,
      onLocationUpdate: _updateUserLocation,
    );
    _routeHelper = RouteHelper(null);
    _navigationController = nav.NavigationController(
      onStateChanged: () => setState(() {}),
      onRecenterButtonVisibilityChanged: (visible) => setState(() {}),
    );

    // Only schedule ONCE
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isInitializingApp) {
        _initializeApp();
      }
    });

    Future.delayed(const Duration(seconds: 15), () {
      if (!_mapReadyCompleter.isCompleted && mounted) {
        print("⚠️ EMERGENCY: Forcing map ready completion after 15s timeout");
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

  Future<void> _initializeApp() async {
    if (_isInitializingApp) {
      print("⚠️ Already initializing, skipping");
      return;
    }
    _isInitializingApp = true;

    try {
      final aedRepository = ref.read(aedServiceProvider);

      _googleMapsApiKey = NetworkService.googleMapsApiKey;

      if (_googleMapsApiKey != null) {
        _routePreloader = RoutePreloader(_googleMapsApiKey!, (status) {});
        _routeHelper = RouteHelper(_googleMapsApiKey);
      }

      _clusterManager = cluster_pkg.ClusterManager<AEDClusterItem>(
        [],
        _onMarkersUpdated,
        markerBuilder: (cluster) => AEDClusterManager.buildMarkerForCluster(cluster),
        stopClusteringZoom: 13,
        extraPercent: 0.5,
        levels: [1, 4.25, 6.75, 8.25, 11.5, 14.5, 16.0, 16.5, 20.0],
      );

      final result = await AppInitializationManager.initializeApp(aedRepository);

      // Wait for map to be ready, then run the full startup sequence in order
      _mapReadyCompleter.future.then((_) async {
        if (!mounted) return;

        // Step 1: Set cached location in state
        if (result.userLocation != null) {
          _updateUserLocation(
            result.userLocation!,
            fromCache: result.isLocationCached,
          );
          _locationLastUpdated = result.locationAge;
          _isUsingCachedLocation = result.isLocationCached;
        }

        // Step 2: Sort AEDs before zoom so targets match what the user will see in the list
        List<AED> aedListForStartup = result.aedList;
        if (result.aedList.isNotEmpty && result.userLocation != null) {
          final aedRepository = ref.read(aedServiceProvider);
          aedListForStartup = aedRepository.sortAEDsByDistance(
            result.aedList,
            result.userLocation,
            ref.read(mapStateProvider).navigation.transportMode,
          );
        }
        if (aedListForStartup.isNotEmpty) {
          ref.read(mapStateProvider.notifier).setAEDs(aedListForStartup);
        }

// Step 3: Zoom first, THEN load markers — targets now match the sorted list
        await _zoomToUserAndAEDsIfReady(
          knownLocation: result.userLocation,
          knownAEDs: aedListForStartup,
        );

        // Zoom succeeded with cached location — clear the spinner
// GPS will update it further if it gets a better fix
        if (mounted && result.isLocationCached) {
          setState(() {
            _isUsingCachedLocation = false;
          });
          print("✅ Cached location confirmed good — cleared spinner");
        }

// Step 4: Now load markers after camera has settled
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;

        if (aedListForStartup.isNotEmpty) {
          _loadAEDsProgressively(aedListForStartup);
        }

        if (!mounted) return;

        // Step 4: Start GPS after zoom is done
        final hasPermission = await _locationService.hasPermission;
        final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

        if (hasPermission && isServiceEnabled) {
          await _startGPSTracking(isNavigating: false);
        } else if (!hasPermission && !_hasRequestedPermission) {
          _hasRequestedPermission = true;
          _requestLocationPermission();
        } else if (hasPermission && !isServiceEnabled) {
          print("🔔 GPS off but permission granted — showing native prompt");
          if (mounted) {
            final locService = loc.Location();
            final enabled = await locService.requestService();
            if (enabled && mounted) {
              await Future.delayed(const Duration(milliseconds: 500));
              await _setupLocationAfterEnable();
            }
          }
        }

        // Step 5: Fetch fresh AEDs from network last
        if (result.isConnected) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _fetchFreshAEDsInBackground();
          });
        }
      });

      print("✅ App initialization complete");
    } catch (e, stack) {
      print("❌ App initialization error: $e\n$stack");
    } finally {
      _isInitializingApp = false;
    }
  }

  /// Starts GPS with appropriate accuracy for current mode
  Future<void> _startGPSTracking({bool isNavigating = false}) async {
    await _gpsController.start(isNavigating: isNavigating);

    // Update our tracking flag
    _isCurrentlyNavigating = isNavigating;

    print("✅ GPS tracking started (navigating: $isNavigating)");
  }

  /// Stops GPS tracking completely
  Future<void> _stopGPSTracking() async {
    await _gpsController.stop();
    _isCurrentlyNavigating = false;
    print("✅ GPS tracking stopped");
  }

  void _showLocationUpdatedBanner(LatLng newLocation, LatLng? oldLocation) {
    if (!mounted) return;

    String message = "Updated to current location";

    if (oldLocation != null) {
      final distance = LocationService.distanceBetween(oldLocation, newLocation);
      if (distance > 1000) {
        message = "Location updated (${(distance / 1000).toStringAsFixed(1)} km away)";
      } else {
        message = "Location updated (${distance.toStringAsFixed(0)} m away)";
      }
    }

    UIHelper.clearSnackbars(context);
    UIHelper.showSnackbar(
      context,
      message: message,
      icon: Icons.my_location,
    );
  }

  Future<void> _requestLocationPermission() async {
    await _mapReadyCompleter.future;

    final granted = await _locationService.requestPermission();

    if (granted) {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

      if (isServiceEnabled) {
        final location = await _locationService.getCurrentLatLng();
        if (location != null && mounted) {
          _updateUserLocation(location);
        }
        await _startGPSTracking(isNavigating: false);
      } else {
        print("⚠️ App permission granted but GPS off - waiting for GPS enable");
        setState(() => _isLocationAvailable = false);
        if (_mapViewController != null) {
          await _mapViewController!.showDefaultGreeceView();
        }
      }

      // Fetch AEDs regardless of GPS state
      if (await NetworkService.isConnected()) {
        _fetchFreshAEDsInBackground();
      }
    }
  }

  Future<void> _fetchFreshAEDsInBackground() async {
    if (_hasFetchedFreshAEDs) {
      print("⏭️ Fresh AED fetch already done, skipping");
      return;
    }
    _hasFetchedFreshAEDs = true;
    try {
      final aedRepository = ref.read(aedServiceProvider);
      final currentState = ref.read(mapStateProvider);
      final mapNotifier = ref.read(mapStateProvider.notifier);

      final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);
      if (freshAEDs.isEmpty || !mounted) return;

      if (!aedRepository.haveAEDsChanged(currentState.aedList, freshAEDs)) {
        print("✅ AED data unchanged - skipping reload");

        // Clear cached spinner even when data is unchanged
        if (mounted && _isUsingCachedLocation) {
          setState(() {
            _isUsingCachedLocation = false;
          });
        }

        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) _preloadTopRoutes();
        });
        return;
      }

      // Routes preloaded successfully — location is good enough, clear spinner
      if (mounted && _isUsingCachedLocation) {
        setState(() {
          _isUsingCachedLocation = false;
        });
      }

      final sorted = aedRepository.sortAEDsByDistance(
        freshAEDs,
        currentState.userLocation,
        currentState.navigation.transportMode,
      );

      _freshDataLoaded = true;
      mapNotifier.setAEDs(sorted);
      if (!_hasPerformedInitialZoom) await _zoomToUserAndAEDsIfReady();
      print("✅ Fresh AEDs updated: ${sorted.length}");
// Don't call _loadAEDsProgressively again — the first call's _addMarkersToMap
// will still complete with the cached list. Just update the cluster items directly.
      _addMarkersToMap(sorted);

      // Trigger preloading after fresh data
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _preloadTopRoutes();
      });
    } catch (e) {
      print("⚠️ Background AED fetch failed: $e");
    }
  }

  /// Single source of truth for "zoom to user + 2 closest AEDs"
  /// Call this whenever location OR aed list becomes newly available
  Future<void> _zoomToUserAndAEDsIfReady({
    bool force = false,
    LatLng? knownLocation,
    List<AED>? knownAEDs,
  }) async {
    print("🔍 _zoomToUserAndAEDsIfReady called (force=$force)");

    if (_hasPerformedInitialZoom && !force) {
      print("⏭️ Skipping zoom — already done and force=false");
      return;
    }
    if (_mapViewController == null) {
      print("❌ Skipping zoom — _mapViewController is null");
      return;
    }

    final currentState = ref.read(mapStateProvider);
    final userLocation = knownLocation ?? currentState.userLocation;
    final aeds = (knownAEDs != null && knownAEDs.isNotEmpty)
        ? knownAEDs
        : currentState.aedList;

    print("📍 userLocation: $userLocation");
    print("📍 aeds count: ${aeds.length}");

    if (userLocation == null || aeds.isEmpty) {
      print("❌ Skipping zoom — userLocation=$userLocation, aeds empty=${aeds.isEmpty}");
      return;
    }

// Use the first 2 AEDs from the already-sorted list as zoom targets.
// These are the top of the list as the user will see them — either the 2 closest
// open AEDs (after sortAEDsByDistance runs) or the 2 closest by straight line
// at startup before sorting has happened. Either way, the map matches the list.
    final targets = aeds.take(2).map((a) => a.location).toList();
    print("🎯 targets: $targets");

    _hasPerformedInitialZoom = true;

    if (targets.isEmpty) {
      print("🗺️ Zooming to AED only (no targets)");
      await _mapViewController!.zoomToAED(userLocation);
    } else {
      print("🗺️ Calling zoomToUserAndClosestAEDs...");
      await _mapViewController!.zoomToUserAndClosestAEDs(userLocation, targets);
      print("✅ zoomToUserAndClosestAEDs returned");
    }
  }

  Future<void> _onConnectivityChanged(bool isConnected) async {
    final currentState = ref.read(mapStateProvider);

    if (!mounted) return;

    final currentlyOffline = currentState.isOffline;

    // Connection restored
    if (currentlyOffline && isConnected) {
      print("🟢 Connection restored! Updating data...");
      _wasOffline = false;

      // Update offline state FIRST
      ref.read(mapStateProvider.notifier).setOffline(false);

      // Ensure we have API key from .env
      if (_googleMapsApiKey == null) {
        _googleMapsApiKey = NetworkService.googleMapsApiKey;
        print("🔑 Loaded API key from .env: ${_googleMapsApiKey != null ? 'Success' : 'Failed'}");
      }

      // ✅ Wait for state to propagate
      await Future.delayed(Duration.zero);

      // ✅ FIX: Fetch AND sort correctly with current transport mode
      final aedRepository = ref.read(aedServiceProvider);
      final updatedState = ref.read(mapStateProvider);

      try {
        // Fetch fresh AEDs
        final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);

        // ✅ Sort with CURRENT transport mode
        final sortedAEDs = aedRepository.sortAEDsByDistance(
          freshAEDs,
          updatedState.userLocation ?? currentState.userLocation,
          updatedState.navigation.transportMode,
        );

        // ✅ Update state with correctly sorted AEDs
        ref.read(mapStateProvider.notifier).setAEDs(sortedAEDs);
        print("✅ Updated with ${sortedAEDs.length} fresh AEDs (sorted by ${updatedState.navigation.transportMode})");

        // Recalculate routes if navigating
        if (updatedState.navigation.isActive &&
            updatedState.navigation.destination != null &&
            updatedState.userLocation != null) {

          if (updatedState.navigation.hasStarted) {
            _recalculateActiveRoute();
          } else {
            await _showNavigationPreviewForAED(updatedState.navigation.destination!);
          }
        }

        // ✅ Preload top 10 routes (with cooldown)
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            print("🚀 Scheduling route preload for top 10 AEDs...");
            _preloadTopRoutes();
          }
        });

      } catch (e) {
        print("❌ Error updating AEDs on connectivity restore: $e");
      }
    }
    // Connection lost
    else if (!currentlyOffline && !isConnected) {
      print("🔴 Connection lost - switching to offline mode");
      _wasOffline = true;
      ref.read(mapStateProvider.notifier).setOffline(true);

      if (currentState.navigation.isActive) {
        _switchNavigationToOfflineMode();
      }
    }
  }

  Future<void> _recalculateActiveRoute() async {
    final currentState = ref.read(mapStateProvider);

    if (currentState.navigation.destination == null ||
        currentState.userLocation == null) {
      return;
    }

    print("🔄 Recalculating active route after connection restore...");

    // Use the new unified update method
    await _updateNavigationRoute(
      currentState.userLocation!,
      currentState.navigation.destination!,
    );

    // Still check for closer AEDs
    if (currentState.userLocation != null && currentState.aedList.length > 1) {
      _checkForCloserAED(currentState.userLocation!, currentState);
    }
  }

  Future<void> _switchNavigationToOfflineMode() async {
    final currentState = ref.read(mapStateProvider);
    if (currentState.navigation.destination == null ||
        currentState.userLocation == null) {
      return;
    }

    // Create offline route
    final estimatedDistance = AEDService.calculateEstimatedDistance(
      currentState.userLocation!,
      currentState.navigation.destination!,
      currentState.navigation.transportMode,
    );
    final estimatedTime = LocationService.calculateOfflineETA(
      estimatedDistance,
      currentState.navigation.transportMode,
    );

    final mapNotifier = ref.read(mapStateProvider.notifier);
    mapNotifier.updateRoute(
      null, // No polyline for offline
      estimatedTime,
      estimatedDistance,
    );

    print("🔴 Switched to offline navigation mode");
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    print("🗺️ Map created callback triggered");

    _mapController = controller;
    _clusterManager?.setMapId(controller.mapId);
    // Apply any items that arrived before the map was ready
    if (_pendingClusterItems != null) {
      _clusterManager?.setItems(_pendingClusterItems!);
      _clusterManager?.updateMap();
      _pendingClusterItems = null;
    }
    _mapViewController = MapViewController(controller, context);

    // ✅ Initialize navigation controller IMMEDIATELY, not in delayed future
    if (_navigationController != null) {
      _navigationController!.initialize(controller);
      print("✅ NavigationController initialized with map controller");
    }

// Get initial zoom level
    try {
      _currentZoom = await controller.getZoomLevel();
      print("🗺️ Initial zoom: $_currentZoom");
    } catch (e) {
      print("⚠️ Could not get initial zoom: $e");
      _currentZoom = 12.0;
    }

// Complete AFTER initial setup
    if (!_mapReadyCompleter.isCompleted) {
      print("✅ Completing map ready completer");
      _mapReadyCompleter.complete();
    }
  }

  // ==================== LOCATION ACQUISITION & MONITORING ====================

  void _startLocationServiceMonitoring() {
    // Listen to location service changes
    LocationService.startLocationServiceMonitoring();
    LocationService.locationServiceStream?.listen((isEnabled) async {
      if (!mounted) return;

      final hasPermission = await _locationService.hasPermission;
      final shouldHaveLocation = isEnabled && hasPermission;

      if (!_isLocationAvailable && shouldHaveLocation) {
        print("📍 Location services became available");

        // Reset zoom flag so we can zoom to user + AEDs
        _hasPerformedInitialZoom = false;

        setState(() {
          _isLocationAvailable = true;
        });
        await _setupLocationAfterEnable();

      }else if (_isLocationAvailable && !shouldHaveLocation) {
        print("📍 Location services became unavailable");
        setState(() {
          _isLocationAvailable = false;
        });
      }
    });
  }

  Future<void> _setupLocationAfterEnable() async {
    if (_isSettingUpLocation) {
      print("⏭️ Location setup already in progress, skipping");
      return;
    }
    _isSettingUpLocation = true;

    try {
      await _stopGPSTracking();
      print("🛑 Stopped existing GPS streams");
      print("🔍 Setting up location after enable...");

      if (!await _locationService.hasPermission) {
        print("❌ No permission after enable");
        return;
      }

      _hasPerformedInitialZoom = false;

      final cachedAppState = await CacheService.getLastAppState();
      if (cachedAppState != null) {
        final cachedLat = cachedAppState['latitude'] as double?;
        final cachedLng = cachedAppState['longitude'] as double?;

        if (cachedLat != null && cachedLng != null) {
          final cachedLocation = LatLng(cachedLat, cachedLng);
          final timestamp = cachedAppState['timestamp'] as int?;

          if (timestamp != null) {
            _locationLastUpdated = DateTime.fromMillisecondsSinceEpoch(timestamp);
            _isUsingCachedLocation = true;
          }

          print("📍 [GPS ON] Using cached location: $cachedLocation");
          _updateUserLocation(cachedLocation, fromCache: true);
          await _zoomToUserAndAEDsIfReady();
        }
      }

      print("🔍 Starting GPS tracking...");
      final serviceNowEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceNowEnabled) {
        await _startGPSTracking(isNavigating: false);
        print("✅ GPS tracking started");
      } else {
        print("⚠️ GPS still off — skipping stream start");
      }
    } catch (e) {
      print("❌ Error setting up location after enable: $e");
    } finally {
      _isSettingUpLocation = false;
    }
  }

  Future<void> _preloadBothTransportModes(LatLng userLocation, LatLng aedLocation) async {
    if (_googleMapsApiKey == null || !await NetworkService.isConnected()) return;

    print("🚗🚶 Preloading both walking and driving routes...");

    final currentState = ref.read(mapStateProvider);

    for (final mode in ['walking', 'driving']) {
      // Check if already cached
      final cached = CacheService.getCachedRoute(userLocation, aedLocation, mode);
      if (cached != null) {
        print("✅ $mode route already cached");
        continue;
      }

      // ✅ Use RouteHelper for consistency
      final route = await _routeHelper.fetchAndCache(
        origin: userLocation,
        destination: aedLocation,
        transportMode: mode,
      );

      if (route != null && route.actualDistance != null) {
        // Find the AED from state
        final aed = currentState.aedList.firstWhere(
              (a) => a.location.latitude == aedLocation.latitude &&
              a.location.longitude == aedLocation.longitude,
          orElse: () => currentState.aedList.first,
        );
        CacheService.setDistance('aed_${aed.id}_$mode', route.actualDistance!);
        print("✅ Cached $mode route");
      }

      await Future.delayed(const Duration(milliseconds: 300)); // Rate limit
    }
  }

  /// Helper: Parse Google Maps duration string to minutes
  int _parseDurationToMinutes(String duration) {
    return RouteHelper.parseDurationToMinutes(duration);
  }

  Future<void> _updateUserLocation(LatLng location, {bool fromCache = false}) async {
    final wasUsingCached = _isUsingCachedLocation;

    if (!fromCache) {
      _locationLastUpdated = DateTime.now();
      _isUsingCachedLocation = false;
    } else {
      _isUsingCachedLocation = true;
    }

    final mapNotifier = ref.read(mapStateProvider.notifier);
    final currentState = ref.read(mapStateProvider);
    final LatLng? previousLocation = currentState.userLocation;
    final bool wasLocationNull = previousLocation == null;

    // ✅ ADD: Show banner if location changed significantly
    if (!wasLocationNull && !fromCache) {
      final distance = LocationService.distanceBetween(previousLocation, location);
      if (distance > 100 && _hasPerformedInitialZoom && mounted) {
        _showLocationUpdatedBanner(location, previousLocation);
      }
    }

    if (!wasLocationNull && !fromCache && !currentState.navigation.hasStarted) {
      final distance = LocationService.distanceBetween(previousLocation, location);
      if (distance < 5 && !_isUsingCachedLocation) {
        // Only skip tiny movements when we already have a real GPS fix
        _locationLastUpdated = DateTime.now();
        return;
      }
    }

    // Update location in state first
    mapNotifier.updateUserLocation(location);

    final isFirstGPSFix = _isUsingCachedLocation && !fromCache;
    if (isFirstGPSFix) {
      // Skip resort on the immediate cached→GPS transition,
      // let the 10s throttle handle it after GPS stabilizes
      _lastResortTime = DateTime.now();
    }

    // Handle first-time location
    if (wasLocationNull) {
      _cacheUserRegion(location);
      if (currentState.aedList.isNotEmpty) {
        final aedRepository = ref.read(aedServiceProvider);
        final sortedForZoom = aedRepository.sortAEDsByDistance(
          currentState.aedList,
          location,
          currentState.navigation.transportMode,
        );
        ref.read(mapStateProvider.notifier).setAEDs(sortedForZoom);
        _scheduleRoutePreloading();
        await _zoomToUserAndAEDsIfReady(
          knownLocation: location,
          knownAEDs: sortedForZoom,
        );
      }
      // Still handle navigation if it was started before first fix
      if (currentState.navigation.hasStarted && _navigationController?.isActive == true) {
        _navigationController!.updateUserLocation(location);
      }
      return;
    }

// Handle upgrade from cached → fresh GPS (zoom to actual location)
    if (!fromCache && wasUsingCached) {
      final distance = LocationService.distanceBetween(previousLocation, location);
      if (distance > 30) {
        // Sort directly here rather than relying on _resortAEDs state propagation
        final aedRepository = ref.read(aedServiceProvider);
        final freshSorted = aedRepository.sortAEDsByDistance(
          currentState.aedList,
          location,
          currentState.navigation.transportMode,
        );

        // Update state with freshly sorted list
        ref.read(mapStateProvider.notifier).setAEDs(freshSorted);

        await Future.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;

        _hasPerformedInitialZoom = false;
        await _zoomToUserAndAEDsIfReady(
          force: true,
          knownLocation: location,
          knownAEDs: freshSorted,  // pass directly, don't read from state
        );
      }
    }

    // Handle subsequent location updates
    final distance = LocationService.distanceBetween(previousLocation, location);

    // Resort if moved significantly (throttled to every 10 seconds)
    if (distance > AppConstants.locationSignificantMovement) {
      final now = DateTime.now();
      if (_lastResortTime == null || now.difference(_lastResortTime!).inSeconds >= 10) {
        _lastResortTime = now;

        // ✅ Get AED list BEFORE resorting
        final previousClosest = currentState.aedList.isNotEmpty ? currentState.aedList.first.id : null;

        _resortAEDs();

        // ✅ Only preload if closest AED actually changed AND cooldown passed
        final updatedState = ref.read(mapStateProvider);
        final newClosest = updatedState.aedList.isNotEmpty ? updatedState.aedList.first.id : null;

        if (newClosest != null && newClosest != previousClosest) {
          // ✅ Check if new closest is SIGNIFICANTLY closer (hysteresis)
          if (previousClosest != null) {
            final oldAED = currentState.aedList.firstWhere((aed) => aed.id == previousClosest);
            final newAED = updatedState.aedList.first;

            final oldDistance = LocationService.distanceBetween(location, oldAED.location);
            final newDistance = LocationService.distanceBetween(location, newAED.location);

            // ✅ Only log/process if new AED is at least 50m closer
            if ((oldDistance - newDistance) >= 50) {
              print("📍 Closest AED changed significantly: $previousClosest → $newClosest (${(oldDistance - newDistance).toStringAsFixed(0)}m closer)");
              // Could trigger selective route preload here if needed
            } else {
              print("📍 Closest AED nominally changed but difference too small (${(oldDistance - newDistance).toStringAsFixed(0)}m)");
              // ✅ Don't do anything special, but DON'T return - let navigation updates continue
            }
          } else {
            // No previous closest (first time)
            print("📍 Closest AED set: $newClosest");
          }
        }
      }
    }

    // Check if a closer AED is available during active navigation
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null &&
        currentState.aedList.length > 1) {
      _checkForCloserAED(location, currentState);
    }

    // Arrival detection
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null) {
      final distToDestination = LocationService.distanceBetween(
        location,
        currentState.navigation.destination!,
      );
      if (distToDestination < 30 && mounted) {
        _onArrived();
      }
    }

    // Update route if actively navigating
// ✅ ALWAYS update camera FIRST during active navigation (smooth following)
    // Camera update is synchronous and immediate
    if (currentState.navigation.hasStarted &&
        _navigationController != null &&
        _navigationController!.isActive) {
      _navigationController!.updateUserLocation(location);
    }

// Route/ETA update is deferred so it doesn't compete with camera move
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null) {
      final shouldUpdateETA = _lastRouteUpdateLocation == null ||
          LocationService.distanceBetween(_lastRouteUpdateLocation!, location) > 10;

      if (shouldUpdateETA) {
        Future.microtask(() async {
          if (!mounted) return;
          final state = ref.read(mapStateProvider);
          final mapNotifier = ref.read(mapStateProvider.notifier);
          double remainingDistance;
          String estimatedTime;

          if (state.navigation.route != null &&
              state.navigation.route!.points.isNotEmpty) {
            final routeCalc = _calculateRemainingRouteDistance(
              location,
              state.navigation.route!.points,
              state.navigation.destination!,
            );
            remainingDistance = routeCalc.distance;
            estimatedTime = _calculateSmartETA(
              remainingDistance,
              state.navigation.route!,
              state.navigation.transportMode,
            );
          } else {
            remainingDistance = LocationService.distanceBetween(
                location, state.navigation.destination!);
            estimatedTime = LocationService.calculateOfflineETA(
              remainingDistance,
              state.navigation.transportMode,
            );
          }

          mapNotifier.updateRoute(
              state.navigation.route, estimatedTime, remainingDistance);
          await _updateNavigationRoute(location, state.navigation.destination!);
        });
      }
    }

    // Cache location for next app start
    if (mounted) {
      final latestState = ref.read(mapStateProvider);
      CacheService.saveLastAppState(
        latestState.userLocation!,
        latestState.navigation.transportMode,
      );
    }
  }


  void _onArrived() {
    _navigationController?.cancelNavigation();
    ref.read(mapStateProvider.notifier).cancelNavigation();
    _startGPSTracking(isNavigating: false);

    UIHelper.showSnackbar(
      context,
      message: 'You have arrived at the AED',
      icon: Icons.check_circle,
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 4),
    );
  }

  /// Updates route, distance, and ETA during active navigation
  /// Uses smart interpolation - only fetches route when necessary
  Future<void> _updateNavigationRoute(LatLng currentLocation, LatLng destination) async {
    final currentState = ref.read(mapStateProvider);
    final mapNotifier = ref.read(mapStateProvider.notifier);

    // ✅ Check if user is off-route (for visual feedback)
    bool isOffRoute = false;
    double distanceFromRoute = 0;

    if (currentState.navigation.route != null &&
        currentState.navigation.route!.points.isNotEmpty) {
      final routeCalc = _calculateRemainingRouteDistance(
        currentLocation,
        currentState.navigation.route!.points,
        currentState.navigation.destination!,
      );

      isOffRoute = routeCalc.isOffRoute;
      distanceFromRoute = routeCalc.distanceFromRoute;

      if (isOffRoute) {
        print("⚠️ User is off-route by ${distanceFromRoute.toStringAsFixed(0)}m");

        if (mounted && _shouldShowOffRouteBanner()) {
          _showOffRouteBanner();
          _lastOffRouteBannerTime = DateTime.now();
        }
      }
    }

    // ✅ SMART FETCH LOGIC: Only fetch route when NECESSARY
    if (!currentState.isOffline && _googleMapsApiKey != null) {
      final shouldFetchRoute = _shouldFetchNewRoute(
        currentLocation,
        isOffRoute,
        distanceFromRoute,
      );

      // ✅ Guard against parallel fetches
      if (shouldFetchRoute && !_isRouteFetchInProgress) {
        _isRouteFetchInProgress = true;  // ✅ Lock

        print("🔄 Fetching updated route (reason: $_lastFetchReason)...");
        _lastRouteUpdateTime = DateTime.now();
        _lastRouteUpdateLocation = currentLocation;

        try {
          final newRoute = await _routeHelper.fetchAndCache(
            origin: currentLocation,
            destination: destination,
            transportMode: currentState.navigation.transportMode,
          );

          if (newRoute != null && mounted) {
            print("✅ Updated route: ${newRoute.distanceText} (${newRoute.duration})");

            final newOriginalDurationMinutes = RouteHelper.parseDurationToMinutes(newRoute.duration);

            mapNotifier.updateRoute(
              newRoute.polyline,
              newRoute.duration,
              newRoute.actualDistance ?? LocationService.distanceBetween(currentLocation, destination),
            );

            mapNotifier.setOriginalRouteMetrics(
              originalDistance: newRoute.actualDistance ?? 0,
              originalDurationMinutes: newOriginalDurationMinutes,
            );
          }
        } catch (e) {
          print("⚠️ Route fetch error: $e");
        } finally {
          _isRouteFetchInProgress = false;  // ✅ Unlock
        }
      } else if (shouldFetchRoute && _isRouteFetchInProgress) {
        print("⏸️ Route fetch already in progress, skipping");
      }
      // ✅ CRITICAL: Don't add another "if (shouldFetchRoute)" block here!
    }

    // ✅ Update bearing toward next waypoint
    if (currentState.navigation.route != null &&
        currentState.navigation.route!.points.isNotEmpty) {
      final nextPoint = _getNextWaypointAhead(
          currentLocation,
          currentState.navigation.route!.points
      );

      if (nextPoint != null && _navigationController != null) {
        _calculateBearing(currentLocation, nextPoint);
      }
    }
  }

  /// Gets the next waypoint ahead of user on the route
  LatLng? _getNextWaypointAhead(LatLng currentLocation, List<LatLng> routePoints) {
    if (routePoints.length < 2) return null;

    // Find closest point on route
    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < routePoints.length; i++) {
      final dist = LocationService.distanceBetween(currentLocation, routePoints[i]);
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    // Return a point 50-100m ahead (about 5-10 route points)
    final lookAheadIndex = (closestIndex + 8).clamp(0, routePoints.length - 1);
    return routePoints[lookAheadIndex];
  }

  /// Calculate bearing from point A to point B
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * (pi / 180);
    final lat2 = to.latitude * (pi / 180);
    final dLon = (to.longitude - from.longitude) * (pi / 180);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * (180 / pi);
    return (bearing + 360) % 360;
  }

  /// Smart logic to determine if we need a new route (like Google Maps)
  bool _shouldFetchNewRoute(LatLng currentLocation, bool isOffRoute, double distanceFromRoute) {
    final now = DateTime.now();

    // REASON 1: User is significantly off-route (>25m)
    if (isOffRoute && distanceFromRoute > 25) {
      _lastFetchReason = 'Off-route by ${distanceFromRoute.toStringAsFixed(0)}m';
      return true;
    }

    // REASON 2: First navigation update (no previous fetch)
    if (_lastRouteUpdateTime == null) {
      _lastFetchReason = 'Initial route fetch';
      return true;
    }

    final timeSinceLastFetch = now.difference(_lastRouteUpdateTime!);
    final distanceSinceLastFetch = _lastRouteUpdateLocation != null
        ? LocationService.distanceBetween(_lastRouteUpdateLocation!, currentLocation)
        : 0.0;

    // REASON 3: Moved significant distance OR enough time passed
    if (distanceSinceLastFetch > 100 || timeSinceLastFetch.inSeconds > 30) {
      _lastFetchReason = 'Moved ${distanceSinceLastFetch.toStringAsFixed(0)}m or ${timeSinceLastFetch.inSeconds}s passed';
      return true;
    }

    // REASON 4: Long time passed (5 minutes) - check for traffic updates
    if (timeSinceLastFetch.inMinutes >= 5) {
      _lastFetchReason = 'Periodic check (${timeSinceLastFetch.inMinutes} min)';
      return true;
    }

    // DON'T FETCH: User is on-route and recent update
    return false;
  }

  /// Calculate more accurate ETA using route profile and current progress
  /// Calculate more accurate ETA using route profile and current progress
  String _calculateSmartETA(double remainingDistance, Polyline route, String transportMode) {
    final currentState = ref.read(mapStateProvider);

    // Use stored original metrics if available
    final originalDistance = currentState.navigation.originalDistance;
    final originalDurationMinutes = currentState.navigation.originalDurationMinutes;

    // ✅ FIX: Null-safe checks
    if (originalDistance != null &&
        originalDurationMinutes != null &&
        originalDistance > 0 &&
        originalDurationMinutes > 0 &&
        remainingDistance > 0) {

      // Calculate progress percentage
      final progressPercent = 1.0 - (remainingDistance / originalDistance);

      // Use proportional time calculation
      final remainingMinutes = (originalDurationMinutes * (1.0 - progressPercent)).ceil();

      if (remainingMinutes < 1) {
        return "< 1min";
      } else if (remainingMinutes < 60) {
        return "${remainingMinutes}min";
      } else {
        final hours = remainingMinutes ~/ 60;
        final minutes = remainingMinutes % 60;
        return minutes > 0 ? "${hours}h ${minutes}min" : "${hours}h";
      }
    }

    // Fallback to simple calculation
    return LocationService.calculateOfflineETA(remainingDistance, transportMode);
  }

  bool _shouldShowOffRouteBanner() {
    if (_lastOffRouteBannerTime == null) return true;
    final timeSinceBanner = DateTime.now().difference(_lastOffRouteBannerTime!);
    return timeSinceBanner.inSeconds >= 10; // Max once per 10 seconds
  }

  void _showOffRouteBanner() {
    if (!mounted) return;

    UIHelper.showSnackbar(
      context,
      message: 'Recalculating route...',
      icon: Icons.warning_amber_rounded,
      backgroundColor: Colors.orange.shade700,
      duration: const Duration(seconds: 2),
    );
  }

  bool _isLocationStale() {
    if (!_isUsingCachedLocation || _locationLastUpdated == null) {
      return false;
    }
    final age = DateTime.now().difference(_locationLastUpdated!).inHours;
    return age >= 1 && age < 5;
  }

  bool _isLocationTooOld() {
    if (!_isUsingCachedLocation || _locationLastUpdated == null) {
      return false;
    }
    return DateTime.now().difference(_locationLastUpdated!).inHours >= 5;
  }

  void startManualGPSSearch() {
    if (_isManuallySearchingGPS) return;

    setState(() {
      _isManuallySearchingGPS = true;
      _gpsSearchSuccess = false;
    });

    // This WILL block, but user explicitly requested it
    Future.delayed(const Duration(milliseconds: 200), () {
      _manualGPSSubscription = _locationService.getPositionStream(
        distanceFilter: 10,
        accuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) => sink.close(),
      ).listen(
            (position) {
          final location = LatLng(position.latitude, position.longitude);
          _updateUserLocation(location);

          setState(() {
            _isManuallySearchingGPS = false;
            _gpsSearchSuccess = true;
          });

          // Auto-hide success after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _gpsSearchSuccess = false);
          });

          _manualGPSSubscription?.cancel();
        },
        onError: (error) {
          print("GPS search error: $error");
          if (mounted) setState(() => _isManuallySearchingGPS = false);
        },
      );
    });
  }

  void stopManualGPSSearch() {
    _manualGPSSubscription?.cancel();
    setState(() {
      _isManuallySearchingGPS = false;
      _gpsSearchSuccess = false;
    });
  }


  void _checkForCloserAED(LatLng currentLocation, AEDMapState currentState) {
    final currentDestination = currentState.navigation.destination!;

    // Get distance to current destination
    final currentDistance = LocationService.distanceBetween(currentLocation, currentDestination);

    // Find the closest AED
    final closestAED = currentState.aedList.first;
    final closestDistance = LocationService.distanceBetween(currentLocation, closestAED.location);

    // Check if closest AED is different and significantly closer (at least 100m closer)
    final isSameDestination = LocationService.distanceBetween(
        closestAED.location,
        currentDestination
    ) < 10; // Within 10m = same location

    if (!isSameDestination && (currentDistance - closestDistance) > 100) {
      _showCloserAEDSnackbar(closestAED, closestDistance);
    }
  }

  void _showCloserAEDSnackbar(AED closerAED, double distance) {
    // Prevent spam - only show once every 60 seconds
    final now = DateTime.now();
    if (_lastCloserAEDNotification != null &&
        now.difference(_lastCloserAEDNotification!).inSeconds < 60) {
      return;
    }
    _lastCloserAEDNotification = now;

    if (!mounted) return;

    UIHelper.clearSnackbars(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Closer AED found (${LocationService.formatDistance(distance)})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF194E9D),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Switch',
          textColor: Colors.white,
          onPressed: () {
            _switchToCloserAED(closerAED);
          },
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _switchToCloserAED(AED newAED) async {
    final currentState = ref.read(mapStateProvider);

    if (currentState.userLocation == null) return;

    print("🔄 Switching navigation to closer AED: ${newAED.address}");

    _navigationController?.cancelNavigation();
    await _showNavigationPreviewForAED(newAED.location);

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Switched to closer AED',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  // ==================== MAP CAMERA CONTROLS ====================

  void _onCameraMoveStarted() {
    // ✅ CRITICAL: Ignore if this was a programmatic move (we just moved camera)
    if (_lastProgrammaticCameraMove != null &&
        DateTime.now().difference(_lastProgrammaticCameraMove!) < const Duration(milliseconds: 500)) {
      print("📷 Camera move STARTED (programmatic - ignoring)");
      return;
    }

    // Only notify navigation controller if navigating AND user actually touched
    if (ref.read(mapStateProvider).navigation.hasStarted) {
      _navigationController?.onCameraMoveStarted();
    }
    print("📷 Camera move STARTED (user interaction)");
  }

  void _onCameraMoved(CameraPosition position) {
    // critical for clusters
    _clusterManager?.onCameraMove(position);

    // keep your “ignore programmatic move” logic if you want
    if (_lastProgrammaticCameraMove != null &&
        DateTime.now().difference(_lastProgrammaticCameraMove!) < const Duration(milliseconds: 500)) {
      return;
    }

    if (ref.read(mapStateProvider).navigation.hasStarted) {
      _navigationController?.onCameraMoved();
    }

    _currentZoom = position.zoom;
  }


  void _onCameraIdle() async {
    if (_isLoadingAEDs) return;
    if (_lastProgrammaticCameraMove != null &&
        DateTime.now().difference(_lastProgrammaticCameraMove!) < const Duration(milliseconds: 800)) {
      return; // Skip cluster update during programmatic moves
    }
    if (_mapController != null) {
      try {
        _currentZoom = await _mapController!.getZoomLevel();
      } catch (e) {
        // ignore
      }
      _clusterManager?.updateMap();  // only call when controller exists
    }
  }


  void _recenterNavigation() {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null) {
      _navigationController?.recenterAndResumeTracking(currentState.userLocation!);
    }
  }

  /// Recenters the map to show both the user's current location and nearby AEDs.
  Future<void> _recenterMapToUserAndAEDs({bool allowLocationPrompt = false}) async {
    if (allowLocationPrompt) {
      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        final locService = loc.Location();
        final enabled = await locService.requestService();
        if (!enabled) return;
        await Future.delayed(const Duration(milliseconds: 500));
        await _setupLocationAfterEnable();
        return;
      }
    }
    final currentState = ref.read(mapStateProvider);

// Always get the freshest GPS position for recenter
    LatLng? freshLocation;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 3));
      freshLocation = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      freshLocation = currentState.userLocation; // fall back if GPS times out
    }

    if (freshLocation != null) {
      final aedRepository = ref.read(aedServiceProvider);
      final updatedState = ref.read(mapStateProvider);
      final freshSorted = aedRepository.sortAEDsByDistance(
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
    // No location yet — ask for one
    final userLocation = await _locationService.getCurrentLocationWithUI(
      context: context,
      showPermissionDialog: allowLocationPrompt,
      showErrorMessages: allowLocationPrompt,
    );

    if (userLocation != null) {
      _updateUserLocation(userLocation);
      final aedRepository = ref.read(aedServiceProvider);
      final updatedState = ref.read(mapStateProvider);
      final freshSorted = aedRepository.sortAEDsByDistance(
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
      return;
    }

    print("📍 Recenter cancelled - keeping current map position");
  }

  // ==================== AED DATA MANAGEMENT ====================

  void _onMarkersUpdated(Set<Marker> markers) {
    print("🗺️ Markers updated: ${markers.length}");
    if (mounted) setState(() => _aedMarkers = markers);
  }

  void _loadAEDsProgressively(List<AED> allAEDs) {
    _isLoadingAEDs = true;
    const firstBatch = 50;
    const batchSize = 200;
    const batchDelay = Duration(milliseconds: 50);

    ref.read(mapStateProvider.notifier).setAEDs(allAEDs.take(firstBatch).toList());

    Future(() async {
      int loaded = firstBatch;
      while (loaded < allAEDs.length) {
        await Future.delayed(batchDelay);
        if (!mounted) return;
        // If fresh sorted data arrived, stop updating state but still finish loading markers
        if (_freshDataLoaded && loaded > firstBatch) break;
        final end = (loaded + batchSize).clamp(0, allAEDs.length);
        ref.read(mapStateProvider.notifier).setAEDs(allAEDs.sublist(0, end));
        loaded += batchSize;
      }

      if (!mounted) return;
      // Always add all markers regardless of whether state updates were skipped
      _isLoadingAEDs = false;
      _addMarkersToMap(allAEDs);
      print("✅ All ${allAEDs.length} AED markers added");
    });
  }


  void _addMarkersToMap(List<AED> aeds) {
    final items = aeds
        .map((aed) => AEDClusterItem(aed, _showNavigationPreviewForAED))
        .toList();

    if (_mapController == null) {
      _pendingClusterItems = items;
      return;
    }

    // Yield to the frame scheduler before the heavy setItems call
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _clusterManager?.setItems(items);
      _clusterUpdateDebounce?.cancel();
      _clusterUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
        _clusterManager?.updateMap();
      });
    });
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
      print("📍 Top AED order changed — updating list");
      ref.read(mapStateProvider.notifier).updateAEDsAndMarkers(newSorted);

      // Check if top 3 changed — if so, new closest AEDs need routes preloaded
      // Replace the top3Changed check with top10Changed:
      final top10Changed = newSorted.length >= 10 &&
          currentState.aedList.length >= 10 &&
          !newSorted.take(10).map((a) => a.id)
              .toSet()
              .containsAll(currentState.aedList.take(10).map((a) => a.id).toSet());

      if (top10Changed) {
        print("📍 Top 10 AEDs changed — scheduling route preload with eviction");
        _scheduleRoutePreloading();
      }
    }
  }

  Future<void> _preloadTopRoutes() async {
    final currentState = ref.read(mapStateProvider);
    final userLocation = currentState.userLocation;

    if (userLocation == null || _routePreloader == null || _googleMapsApiKey == null) return;

    final top10 = currentState.aedList.take(10).toList();

    print("🚀 Starting route preloading for top 10 AEDs...");

    try {
      for (final mode in ['walking', 'driving']) {
        await _routePreloader!.preloadRoutesForClosestAEDs(
          aeds: top10,
          userLocation: userLocation,
          transportMode: mode,
          onRouteLoaded: (originalAed, route) {
            if (mounted && route.actualDistance != null) {
              final routeKey = '${originalAed.id}_$mode';
              _preloadedRoutes[routeKey] = route;
              _limitPreloadedRoutesSize();
              CacheService.setDistance('aed_${originalAed.id}_$mode', route.actualDistance!);
            }
          },
        );
      }
      await CacheService.saveDistanceCache();
    } catch (e) {
      print("❌ Error preloading routes: $e");
    }
  }


  void _scheduleRoutePreloading() {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null && currentState.aedList.isNotEmpty && _googleMapsApiKey != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _preloadTopRoutes();
        }
      });
    }
  }

  void _limitPreloadedRoutesSize() {
    const maxRoutes = 25; // Prevent memory bloat
    if (_preloadedRoutes.length > maxRoutes) {
      // Remove oldest entries (simple FIFO)
      final keysToRemove = _preloadedRoutes.keys.take(_preloadedRoutes.length - maxRoutes);
      for (final key in keysToRemove) {
        _preloadedRoutes.remove(key);
      }
      print("🗑️ Trimmed preloaded routes to $maxRoutes entries");
    }
  }

  /// Caches the user's general region for offline map positioning
  void _cacheUserRegion(LatLng userLocation) {
    // Determine general region based on user location
    final generalRegion = _determineGeneralRegion(userLocation);

    // Cache with a moderate zoom level (city-level view)
    CacheService.saveLastMapRegion(
      center: generalRegion,
      zoom: 12.0, // City-level zoom, not specific location
    );

    print("📍 Cached user's general region: ${generalRegion.latitude.toStringAsFixed(2)}, ${generalRegion.longitude.toStringAsFixed(2)}");
  }

  /// Determines a general region center based on user location
  LatLng _determineGeneralRegion(LatLng userLocation) {
    // Round to 2 decimal places for general region (roughly 1km precision)
    final roundedLat = (userLocation.latitude * 100).round() / 100;
    final roundedLng = (userLocation.longitude * 100).round() / 100;

    return LatLng(roundedLat, roundedLng);
  }

// ==================== NAVIGATION & ROUTING ====================

  Future<void> _showNavigationPreviewForAED(LatLng aedLocation) async {
    _lastProgrammaticCameraMove = DateTime.now();  // ✅ ADD THIS LINE

    final currentState = ref.read(mapStateProvider);
    final mapNotifier = ref.read(mapStateProvider.notifier);

    LatLng? currentLocation = currentState.userLocation;

    // 1. Handle Compass Mode (No GPS)
    if (currentLocation == null) {
      mapNotifier.showNavigationPreview(aedLocation);
      if (_mapViewController != null) {
        await _mapViewController!.zoomToAED(aedLocation);
      }
      return;
    }

    // 2. Setup UI
    mapNotifier.showNavigationPreview(aedLocation);

    // Find the AED
    final aed = currentState.aedList.firstWhere(
          (aed) => aed.location.latitude == aedLocation.latitude &&
          aed.location.longitude == aedLocation.longitude,
      orElse: () => AED(id: -1, foundation: '', address: '', location: aedLocation),
    );

    final isTooOld = _isLocationTooOld();

    // Prefetch background data (optional visual update)
    if (!isTooOld && !currentState.isOffline && _googleMapsApiKey != null) {
      Future.delayed(Duration.zero, () {
        _preloadBothTransportModes(currentLocation, aedLocation);
      });
    }

    RouteResult? routeResult;

    // ✅ STEP 1: Check immediate preload (RAM) - use composite key!
    final routeKey = '${aed.id}_${currentState.navigation.transportMode}';
    if (_preloadedRoutes.containsKey(routeKey)) {
      print("🚀 Using preloaded route for AED ${aed.id} (${currentState.navigation.transportMode})");
      routeResult = _preloadedRoutes[routeKey];

      // No need to update color - it's already correct for this mode!
    }

    // ✅ STEP 2: Determine if we need to fetch fresh
    // We add (routeResult == null) so we DON'T fetch if we already have it from Step 1
    final bool shouldFetchFresh = routeResult == null &&
        !currentState.isOffline &&
        _googleMapsApiKey != null &&
        !isTooOld;

    if (shouldFetchFresh) {
      print("🌎 Online: Attempting to fetch fresh route first...");
      routeResult = await _routeHelper.fetchAndCache(
        origin: currentLocation,
        destination: aedLocation,
        transportMode: currentState.navigation.transportMode,
      );

      if (routeResult != null && routeResult.actualDistance != null) {
        CacheService.setDistance('aed_${aed.id}_${currentState.navigation.transportMode}', routeResult.actualDistance!);  // ✅ ADDED MODE
      }
    }

    // ✅ STEP 3: Fallback to Disk Cache if both RAM and Network failed
    if (routeResult == null) {
      if (shouldFetchFresh) {
        print("🔄 Falling back to cache after failed fetch...");
      } else {
        print("🔌 Offline or location too old. Checking cache...");
      }

      // Try exact cache match first
      routeResult = CacheService.getCachedRoute(
          currentLocation, aedLocation, currentState.navigation.transportMode
      );

      // If no exact match, try nearby cached routes
      routeResult ??= CacheService.getCachedRouteNearby(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
        maxDistanceMeters: 1000, // 1km proximity
      );

      if (routeResult != null) {
        print("✅ Found cached route.");

        // ✅ FIX: Update cached route color to match current mode
        routeResult = RouteResult(
          polyline: Polyline(
            polylineId: routeResult.polyline.polylineId,
            points: routeResult.polyline.points,
            color: currentState.navigation.transportMode == "walking" ? Colors.green : Colors.blue,
            patterns: currentState.navigation.transportMode == "walking"
                ? [PatternItem.dash(15), PatternItem.gap(8)]
                : [],
            width: 4,
          ),
          duration: routeResult.duration,
          points: routeResult.points,
          isOffline: routeResult.isOffline,
          actualDistance: routeResult.actualDistance,
          distanceText: routeResult.distanceText,
        );
      }
    }

    // --- RENDER LOGIC ---

// Show route if available (always gray when offline or using cached location)
    if (routeResult != null && !isTooOld) {
      final shouldShowGray = _isUsingCachedLocation || currentState.isOffline;

      final polyline = shouldShowGray
          ? Polyline(
        polylineId: routeResult.polyline.polylineId,
        points: routeResult.polyline.points,
        color: Colors.grey,
        width: 4,
      )
          : Polyline(
        polylineId: routeResult.polyline.polylineId,
        points: routeResult.polyline.points,
        // ✅ FIX: Always use current transport mode color
        color: currentState.navigation.transportMode == "walking" ? Colors.green : Colors.blue,
        patterns: currentState.navigation.transportMode == "walking"
            ? [PatternItem.dash(15), PatternItem.gap(8)]
            : [],
        width: 4,
      );

      mapNotifier.updateRoute(
        polyline,
        routeResult.duration,
        routeResult.actualDistance ?? LocationService.distanceBetween(
            currentLocation, aedLocation
        ),
      );

      if (_mapViewController != null) {
        _lastProgrammaticCameraMove = DateTime.now();  // ✅ ADD THIS
        await _mapViewController!.zoomToUserAndAED(
          userLocation: currentLocation,
          aedLocation: aedLocation,
          polylinePoints: routeResult.points,
        );
      }
    } else if (isTooOld) {
      // Location too old - no line, show "--"
      mapNotifier.updateRoute(null, "", 0);
    } else {
      // No route available - show estimation only
      final estimatedDistance = AEDService.calculateEstimatedDistance(
          currentLocation, aedLocation, currentState.navigation.transportMode
      );
      final estimatedTime = LocationService.calculateOfflineETA(
          estimatedDistance, currentState.navigation.transportMode
      );

      // Cache estimations
      if (aed.id != -1) {
        final walkingEst = AEDService.calculateEstimatedDistance(
            currentLocation, aedLocation, 'walking'
        );
        final drivingEst = AEDService.calculateEstimatedDistance(
            currentLocation, aedLocation, 'driving'
        );
        CacheService.setDistance('aed_${aed.id}_walking_est', walkingEst);
        CacheService.setDistance('aed_${aed.id}_driving_est', drivingEst);
      }

      mapNotifier.updateRoute(
        null, // No polyline
        estimatedTime,
        estimatedDistance,
      );

      if (_mapViewController != null) {
        _lastProgrammaticCameraMove = DateTime.now();  // ✅ ADD THIS
        await _mapViewController!.zoomToUserAndAED(
          userLocation: currentLocation,
          aedLocation: aedLocation,
          polylinePoints: [],
        );
      }
    }
  }

  void _startNavigation(LatLng aedLocation) async {
    final currentState = ref.read(mapStateProvider);
    LatLng? currentLocation = currentState.userLocation;

    // Check if location is stale or too old
    final isStale = _isLocationStale();
    final isTooOld = _isLocationTooOld();

    // ✅ FIX: If using cached/stale location, get fresh HIGH accuracy fix first
    if (currentLocation != null && (_isUsingCachedLocation || isStale)) {
      print("⚠️ Using cached/stale location - getting fresh GPS fix before navigation...");

      try {
        // Show loading indicator
        if (mounted) {
          UIHelper.showLoading(context, 'Getting precise location...');
        }

        // Get fresh HIGH accuracy position (may take 2-5 seconds)
        final freshPosition = await _locationService.getCurrentPosition(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );

        if (freshPosition != null) {
          currentLocation = LatLng(freshPosition.latitude, freshPosition.longitude);
          _updateUserLocation(currentLocation); // Update state with fresh location
          _isUsingCachedLocation = false;
          _locationLastUpdated = DateTime.now();
          print("✅ Got fresh HIGH accuracy location: $currentLocation");

          if (mounted) {
            UIHelper.clearSnackbars(context);
          }
        } else {
          print("⚠️ Could not get fresh location, using existing");
        }
      } catch (e) {
        print("⚠️ Error getting fresh location: $e");
        // Continue with existing location
      }
    }

    // If no location OR location is too old, start compass-only navigation
    if (currentLocation == null || isTooOld) {
      print("🧭 Starting compass-only navigation (no location or location too old)");

      final mapNotifier = ref.read(mapStateProvider.notifier);
      mapNotifier.startNavigation(aedLocation);

      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(aedLocation, 15.0),
      );

      if (_navigationController != null && _mapController != null) {
        if (!_navigationController!.isActive) {
          _navigationController!.initialize(_mapController!);
        }
        _navigationController?.startCompassOnlyMode(aedLocation);
      } else {
        print("⚠️ Navigation controller or map controller not ready");
      }
      return;
    }

    // Initialize navigation controller
    if (_navigationController == null || _mapController == null) {
      print("❌ Controllers not ready");
      return;
    }

    if (!_navigationController!.isActive) {
      _navigationController!.initialize(_mapController!);
    }

    // Start navigation with camera tracking (location is usable)
    await _navigationController?.startNavigation(
      currentLocation,
      aedLocation,
      isOffline: currentState.isOffline || isStale,
    );

    final mapNotifier = ref.read(mapStateProvider.notifier);
    mapNotifier.startNavigation(aedLocation);

    // ✅ Set flag FIRST before restarting stream
    _isCurrentlyNavigating = true;

    // ✅ Use GPS controller
    await _startGPSTracking(isNavigating: true);
    print("🎯 Location stream restarted: HIGH accuracy, 5m updates, real-time distance/time");

    RouteResult? routeResult;

    // ✅ Only try cache if location hasn't changed much recently
    final bool locationRecentlyChanged = _locationLastUpdated != null &&
        DateTime.now().difference(_locationLastUpdated!) < const Duration(seconds: 10);

    if (!locationRecentlyChanged) {
      // Safe to use cache
      routeResult = CacheService.getCachedRoute(
          currentLocation, aedLocation, currentState.navigation.transportMode
      );

      if (routeResult != null) {
        print("📦 Using cached route (location stable)");
      }
    }

    // ✅ Always fetch fresh if location just changed OR no cache
    if (routeResult == null && !currentState.isOffline && _googleMapsApiKey != null) {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Calculating route...'),
              ],
            ),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      print("🌐 Fetching fresh route...");

      routeResult = await _routeHelper.fetchAndCache(
        origin: currentLocation,
        destination: aedLocation,
        transportMode: currentState.navigation.transportMode,
      );

      if (mounted) {
        UIHelper.clearSnackbars(context);
      }
    }

    // ✅ FALLBACK: Try nearby cached routes if still no route (reduce to 500m for accuracy)
    if (routeResult == null) {
      routeResult = CacheService.getCachedRouteNearby(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
        maxDistanceMeters: 500,  // ✅ Reduced from 1km for better accuracy
      );

      if (routeResult != null) {
        print("📦 Using nearby cached route (within 500m)");
      }
    }

    // ✅ Display the route or show offline estimation
    if (routeResult != null && !routeResult.isOffline) {
      final shouldShowGray = _isUsingCachedLocation || currentState.isOffline || isStale;

      final polyline = shouldShowGray
          ? Polyline(
        polylineId: routeResult.polyline.polylineId,
        points: routeResult.polyline.points,
        color: Colors.grey,
        width: 4,
      )
          : routeResult.polyline;

      // ✅ Store the ORIGINAL duration in minutes for later calculation
      final originalDurationMinutes = _parseDurationToMinutes(routeResult.duration);
      print("🕒 Parsed duration: '${routeResult.duration}' → $originalDurationMinutes minutes");
      print("📏 Original distance: ${routeResult.actualDistance} meters");

      mapNotifier.updateRoute(
        polyline,
        routeResult.duration,
        routeResult.actualDistance ?? LocationService.distanceBetween(
            currentLocation, aedLocation
        ),
      );

      // ✅ Store original values for proportional calculations
      mapNotifier.setOriginalRouteMetrics(
        originalDistance: routeResult.actualDistance ?? 0,
        originalDurationMinutes: originalDurationMinutes,
      );
    } else {
      // No route available - create offline estimation
      final estimatedDistance = AEDService.calculateEstimatedDistance(
          currentLocation, aedLocation, currentState.navigation.transportMode
      );
      final estimatedTime = LocationService.calculateOfflineETA(
          estimatedDistance, currentState.navigation.transportMode
      );

      mapNotifier.updateRoute(
        null, // No polyline for offline
        estimatedTime,
        estimatedDistance,
      );

      print("🧭 Starting navigation with offline estimation");
    }

    _lastRouteUpdateTime = DateTime.now();
    _lastRouteUpdateLocation = currentLocation;
    print("✅ Navigation started - route updates enabled");
  }

  Future<void> _cancelNavigation() async {
    _navigationController?.cancelNavigation();

    final currentState = ref.read(mapStateProvider);
    final wasInFullNavigation = currentState.navigation.hasStarted;
    final mapNotifier = ref.read(mapStateProvider.notifier);

    if (wasInFullNavigation) {
      mapNotifier.showNavigationPreview(currentState.navigation.destination!);

      if (currentState.userLocation != null) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: currentState.userLocation!,
              zoom: 16.0,
              bearing: 0.0,
              tilt: 0.0,
            ),
          ),
        );
      }
    } else {
      mapNotifier.cancelNavigation();
    }

    // ✅ Use GPS controller to switch back to normal tracking
    await _stopGPSTracking();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_isCurrentlyNavigating) {
        _startGPSTracking(isNavigating: false);
      }
    });

    if (mounted) setState(() {});
  }

  // In AEDMapWidget, replace _openExternalNavigation with:
  void _openExternalNavigation(LatLng destination) async {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation == null) return;

    final success = await RouteService.openExternalNavigation(
      origin: currentState.userLocation!,
      destination: destination,
      transportMode: currentState.navigation.transportMode,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open external navigation'))
      );
    }
  }

// ==================== APP LIFECYCLE ====================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // App is in the foreground
      _resumeApp();
    } else if (state == AppLifecycleState.paused) {
      // App is in the background
      _pauseApp();
    }
  }

  void _resumeApp() async {
    print("🔄 App resumed from background");
    final now = DateTime.now();
    if (_lastResumeTime != null && now.difference(_lastResumeTime!).inSeconds < 2) {
      print("⏭️ Resume debounced");
      return;
    }
    _lastResumeTime = now;

    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final hasPermission = await _locationService.hasPermission;
    final shouldHaveLocation = isServiceEnabled && hasPermission;

    // ✅ Handle location state changes
    if (!_isLocationAvailable && shouldHaveLocation) {
      print("📍 Location became available during resume");
      setState(() {
        _isLocationAvailable = true;
      });
      // Only setup location if it wasn't available before
      await _setupLocationAfterEnable();
    } else if (_isLocationAvailable && !shouldHaveLocation) {
      print("📍 Location became unavailable during resume");
      setState(() {
        _isLocationAvailable = false;
      });
    }

    if (!mounted) return;

    // ✅ FIX: Only refresh if connection STATE CHANGED
    final isConnected = await NetworkService.isConnected();
    final currentState = ref.read(mapStateProvider);

    if (_wasOffline && isConnected) {
      print("🟢 Connection restored during resume");
      _wasOffline = false;
      ref.read(mapStateProvider.notifier).setOffline(false);

      // ✅ Only fetch NEW data, don't reload from cache
      final aedRepository = ref.read(aedServiceProvider);
      final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);

      if (freshAEDs.isNotEmpty) {
        final sortedAEDs = aedRepository.sortAEDsByDistance(
          freshAEDs,
          currentState.userLocation,
          currentState.navigation.transportMode,
        );
        ref.read(mapStateProvider.notifier).setAEDs(sortedAEDs);
        print("✅ Refreshed ${sortedAEDs.length} AEDs after connection restore");
      }
    } else if (!_wasOffline && !isConnected) {
      _wasOffline = true;
      ref.read(mapStateProvider.notifier).setOffline(true);
      print("🔴 Connection lost during resume");
    }

    // ✅ FIX: Only check for updates if enough time passed AND we have AEDs
    final shouldCheckUpdates = _lastBackgroundTime != null &&
        now.difference(_lastBackgroundTime!).inMinutes > 2 &&
        currentState.aedList.isNotEmpty;

    if (shouldCheckUpdates && isConnected) {
      print("🔄 Checking for AED updates (background > 2 min)");
      final aedRepository = ref.read(aedServiceProvider);

      try {
        final newAEDs = await aedRepository.fetchAEDs(forceRefresh: false);
        final changed = aedRepository.haveAEDsChanged(currentState.aedList, newAEDs);

        if (changed && mounted) {
          print("🆕 AED data changed - updating");
          final sortedAEDs = aedRepository.sortAEDsByDistance(
            newAEDs,
            currentState.userLocation,
            currentState.navigation.transportMode,
          );
          ref.read(mapStateProvider.notifier).updateAEDsAndMarkers(sortedAEDs);
        } else {
          print("✅ AED data unchanged");
        }
      } catch (e) {
        print("⚠️ Error checking AED updates: $e");
      }
    }
// Only allow fresh fetch again if at least 5 minutes have passed
    if (_lastBackgroundTime != null &&
        DateTime.now().difference(_lastBackgroundTime!).inMinutes >= 5) {
      _hasFetchedFreshAEDs = false;
    }
    print("✅ Resume complete");
  }

  void _pauseApp() async {
    print("⏸️ App paused - saving state");
    _lastBackgroundTime = DateTime.now();

    // ✅ Save current zoom level
    if (_mapController != null) {
      try {
        _currentZoom = await _mapController!.getZoomLevel();
        print("💾 Saved zoom: $_currentZoom");
      } catch (e) {
        print("⚠️ Could not save zoom: $e");
      }
    }

    // ✅ Save current camera position
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null) {
      CacheService.saveLastAppState(
        currentState.userLocation!,
        currentState.navigation.transportMode,
      );
    }
  }
// ==================== WIDGET BUILD ====================

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapStateProvider);

    return AEDMapDisplay(
      config: AEDMapConfig(
        isLoading: mapState.isLoading,
        aedMarkers: _aedMarkers,
        userLocation: mapState.userLocation,
        userLocationAvailable: _isLocationAvailable,
        mapController: _mapController,
        navigationLine: mapState.navigation.route,
        estimatedTime: mapState.navigation.estimatedTime,
        selectedAED: mapState.navigation.destination,
        aedLocations: mapState.aedList.map((aed) => aed.location).toList(),
        selectedMode: mapState.navigation.transportMode,
        aeds: mapState.aedList,
        isRefreshingAEDs: mapState.isRefreshing,
        hasSelectedRoute: mapState.navigation.isActive,
        navigationMode: mapState.navigation.isActive,
        distance: mapState.navigation.distance,
        isOffline: mapState.isOffline,
        preloadedRoutes: _preloadedRoutes,
        isPreloadingRoutes: _routePreloader?.isPreloading ?? false,
        currentBearing: _navigationController?.currentHeading,
        isFollowingUser: _navigationController?.isActive ?? false,
        showRecenterButton: _navigationController?.showRecenterButton ?? false,
        hasStartedNavigation: mapState.navigation.hasStarted,
        isUsingCachedLocation: _isUsingCachedLocation,
        isManuallySearchingGPS: _isManuallySearchingGPS,
        gpsSearchSuccess: _gpsSearchSuccess,
        isLocationStale: _isLocationStale(),
        locationAge: _locationLastUpdated != null
            ? DateTime.now().difference(_locationLastUpdated!).inHours
            : null,
      ),
      onSmallMapTap: _showNavigationPreviewForAED,
      onPreviewNavigation: _showNavigationPreviewForAED,
      userLocationAvailable: _isLocationAvailable,
      onStartNavigation: _startNavigation,
      onManualGPSSearch: startManualGPSSearch,
      onCameraMoved: _onCameraMoved,
      onCameraMoveStarted: _onCameraMoveStarted,
      onCameraIdle: _onCameraIdle,
      onRecenterNavigation: _recenterNavigation,
        onTransportModeSelected: (mode) {
          _transportModeDebouncer?.cancel();
          _transportModeDebouncer = Timer(const Duration(milliseconds: 500), () async {
            if (!mounted) return;

            final mapNotifier = ref.read(mapStateProvider.notifier);

            // 1. Update transport mode in state FIRST
            mapNotifier.updateTransportMode(mode);

            // 2. Give Riverpod a chance to update the state
            await Future.delayed(Duration.zero);

            // 3. NOW, read the FRESH state
            final currentState = ref.read(mapStateProvider);

            // 4. Re-sort AEDs
            if (currentState.userLocation != null) {
              final aedRepository = ref.read(aedServiceProvider);
              final resorted = aedRepository.sortAEDsByDistance(
                  currentState.aedList,
                  currentState.userLocation!,
                  mode
              );
              mapNotifier.updateAEDsAndMarkers(resorted);

              // Background improvements (non-blocking)
              if (_googleMapsApiKey != null) {
                aedRepository.improveDistanceAccuracyInBackground(
                  resorted,
                  currentState.userLocation!,
                  mode,
                  _googleMapsApiKey,
                      (improvedAEDs) {
                    if (mounted) {
                      final currentState = ref.read(mapStateProvider);
                      final reSorted = ref.read(aedServiceProvider).sortAEDsByDistance(
                        improvedAEDs,
                        currentState.userLocation,
                        mode,
                      );
                      mapNotifier.updateAEDsAndMarkers(reSorted);
                      _updatePreloadedRoutesFromCache(improvedAEDs, mode);

                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted) setState(() {});
                      });
                    }
                  },
                );
              }
            }

            // 5. Update route when transport mode changes
            if (ref.read(mapStateProvider).navigation.destination != null &&
                currentState.userLocation != null) {

              if (ref.read(mapStateProvider).navigation.hasStarted) {
                // ACTIVE NAVIGATION: Fetch new route
                print("🔄 Transport mode changed during navigation - recalculating route...");

                if (mounted) {
                  UIHelper.clearSnackbars(context);
                  UIHelper.showSnackbar(
                    context,
                    message: 'Switched to ${mode == "walking" ? "walking" : "driving"} mode',
                    icon: Icons.directions,
                    duration: const Duration(seconds: 2),
                  );
                }

                final newRoute = await _routeHelper.fetchAndCache(
                  origin: currentState.userLocation!,
                  destination: ref.read(mapStateProvider).navigation.destination!,
                  transportMode: mode,
                );

                if (newRoute != null && mounted) {
                  print("✅ New route fetched: ${newRoute.distanceText} (${newRoute.duration})");

                  final newOriginalDurationMinutes = RouteHelper.parseDurationToMinutes(newRoute.duration);

                  ref.read(mapStateProvider.notifier).updateRoute(
                    newRoute.polyline,
                    newRoute.duration,
                    newRoute.actualDistance ?? LocationService.distanceBetween(
                      currentState.userLocation!,
                      ref.read(mapStateProvider).navigation.destination!,
                    ),
                  );

                  ref.read(mapStateProvider.notifier).setOriginalRouteMetrics(
                    originalDistance: newRoute.actualDistance ?? 0,
                    originalDurationMinutes: newOriginalDurationMinutes,
                  );
                }

              } else if (ref.read(mapStateProvider).navigation.isActive) {
                // PREVIEW MODE: Just update the preview
                print("🔄 Transport mode changed in preview - updating...");
                _showNavigationPreviewForAED(currentState.navigation.destination!);
              }
            }

            // ✅✅✅ ADD THIS: Trigger route preload for new transport mode
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (mounted && _googleMapsApiKey != null && currentState.userLocation != null) {
                print("🔄 Preloading routes for $mode mode...");
                _preloadTopRoutes();
              }
            });

          });
        },

      onRecenterPressed: () => _recenterMapToUserAndAEDs(allowLocationPrompt: true),
      onMapCreated: _onMapCreated,
      onCancelNavigation: _cancelNavigation,
      onExternalNavigation: _openExternalNavigation,
    );
  }

  void _updatePreloadedRoutesFromCache(List<AED> aeds, String transportMode) {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation == null) return;

    int updatedCount = 0;

    // Update preloaded routes from cache for top 20 AEDs
    for (final aed in aeds.take(20)) {
      // Check if we have a cached route
      final cachedRoute = CacheService.getCachedRoute(
        currentState.userLocation!,
        aed.location,
        transportMode,
      );

      if (cachedRoute != null) {
        final routeKey = '${aed.id}_$transportMode';  // ✅ Use composite key
        _preloadedRoutes[routeKey] = cachedRoute;
        updatedCount++;
      }
    }

    if (updatedCount > 0) {
      print("♻️ Updated $updatedCount preloaded routes from cache ($transportMode)");
      // Trigger UI rebuild
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    // ✅ Call synchronous cleanup
    NetworkService.removeConnectivityListener(_onConnectivityChanged);
    // ✅ Cancel timers first
    _transportModeDebouncer?.cancel();
    _manualGPSSubscription?.cancel();

    // ✅ Dispose controllers synchronously (they handle async internally)
    _gpsController.dispose();
    _navigationController?.dispose();
    _locationService.dispose();

    // ✅ Stop monitoring
    LocationService.stopLocationServiceMonitoring();

    // ✅ Clear caches
    _preloadedRoutes.clear();
    _aedMarkers.clear();

    // ✅ Dispose map controller
    _mapController?.dispose();
    _mapViewController = null;
    _clusterManager = null;

    _clusterUpdateDebounce?.cancel();

    CacheService.dispose();

    // ✅ Complete pending operations
    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.completeError("Widget disposed");
    }

    // ✅ Remove observers
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }
}

class RouteDistanceCalculation {
  final double distance;
  final bool isOffRoute;
  final double distanceFromRoute;

  RouteDistanceCalculation({
    required this.distance,
    required this.isOffRoute,
    required this.distanceFromRoute,
  });
}

/// Calculates remaining distance along the actual route polyline
RouteDistanceCalculation _calculateRemainingRouteDistance(
    LatLng currentLocation,
    List<LatLng> routePoints,
    LatLng destination,
    ) {
  if (routePoints.isEmpty) {
    return RouteDistanceCalculation(
      distance: LocationService.distanceBetween(currentLocation, destination),
      isOffRoute: false,
      distanceFromRoute: 0,
    );
  }

  // Find closest point on route to current location
  int closestIndex = 0;
  double minDistance = double.infinity;

  for (int i = 0; i < routePoints.length; i++) {
    final dist = LocationService.distanceBetween(currentLocation, routePoints[i]);
    if (dist < minDistance) {
      minDistance = dist;
      closestIndex = i;
    }
  }

  // Check if user is significantly off-route (> 25 meters from any point)
  final isOffRoute = minDistance > 25;

  // Calculate remaining distance from closest point to destination
  double remainingDistance = 0;

  // Add distance from current location to closest point on route
  remainingDistance += minDistance;

  // Add up distances between all remaining route points
  for (int i = closestIndex; i < routePoints.length - 1; i++) {
    remainingDistance += LocationService.distanceBetween(
      routePoints[i],
      routePoints[i + 1],
    );
  }

  return RouteDistanceCalculation(
    distance: remainingDistance,
    isOffRoute: isOffRoute,
    distanceFromRoute: minDistance,
  );
}