import 'dart:async';
import 'package:cpr_assist/services/aed_map/aed_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/aed_models.dart';
import '../../providers/network_service_provider.dart';
import '../../utils/app_constants.dart';
import 'app_initialization_manager.dart';
import 'cache_service.dart';
import 'location_service.dart';
import '../network_service.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'map_service.dart';
import 'route_service.dart';
import '../../screens/aed_map_display.dart';
import '../../providers/aed_service_provider.dart';
import 'navigation_controller.dart' as nav;
import 'aed_cluster_renderer.dart';

class AEDMapWidget extends ConsumerStatefulWidget {
  const AEDMapWidget({super.key});

  @override
  ConsumerState<AEDMapWidget> createState() => _AEDMapWidgetState();
}

class _AEDMapWidgetState extends ConsumerState<AEDMapWidget> with WidgetsBindingObserver {
  GoogleMapController? _mapController;
  String? _googleMapsApiKey;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSubscription;
  final Completer<void> _mapReadyCompleter = Completer<void>();
  MapViewController? _mapViewController;
  bool _isLocationAvailable = true;
  DateTime? _lastBackgroundTime;
  bool _wasOffline = false;
  final Map<int, RouteResult> _preloadedRoutes = {};
  bool _hasPerformedInitialZoom = false;
  DateTime? _lastResortTime;
  Timer? _transportModeDebouncer;
  Timer? _improvementTimer;
  nav.NavigationController? _navigationController;
  RoutePreloader? _routePreloader;
  DateTime? _lastCloserAEDNotification;
  DateTime? _locationLastUpdated;
  bool _isUsingCachedLocation = false;
  bool _isManuallySearchingGPS = false;
  bool _gpsSearchSuccess = false;
  StreamSubscription<Position>? _manualGPSSubscription;
  bool _isLoadingMarkers = false;
  double _currentZoom = 12.0;
  Set<Marker> _clusterMarkers = {};
  Timer? _clusterUpdateDebouncer;
  double _clusteringZoomThreshold = 16.0;


  // ==================== APP STARTUP & INITIALIZATION ====================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMapRenderer();
    NetworkService.startConnectivityMonitoring();
    NetworkService.addConnectivityListener(_onConnectivityChanged);
    _startLocationServiceMonitoring();


    // Start app initialization without blocking UI
    Future.delayed(const Duration(milliseconds: 100), _initializeApp);
  }


  void _initializeMapRenderer() {
    if (GoogleMapsFlutterPlatform.instance is GoogleMapsFlutterAndroid) {
      (GoogleMapsFlutterPlatform.instance as GoogleMapsFlutterAndroid)
          .useAndroidViewSurface = true;
    }
  }

  Future<void> _initializeApp() async {
    // Initialize using the manager
    final aedRepository = ref.read(aedServiceProvider);
    final networkService = ref.read(networkServiceProvider);
    final result = await AppInitializationManager.initializeApp(aedRepository, networkService);

    print("✅ Initialization complete");
    print("   → Location: ${result.hasLocation}");
    print("   → AEDs: ${result.aedList.length}");
    print("   → Connected: ${result.isConnected}");

    // Store API key
    _googleMapsApiKey = result.apiKey;

    // Initialize navigation controller
    _navigationController = nav.NavigationController(
      onStateChanged: () => setState(() {}),
      onRecenterButtonVisibilityChanged: (visible) => setState(() {}),
    );

    // Initialize route preloader if we have API key
    if (_googleMapsApiKey != null) {
      _routePreloader = RoutePreloader(_googleMapsApiKey!, (status) {
        print("Preloader status: $status");
      });
    }

    // Wait for map to be ready
    _mapReadyCompleter.future.then((_) async {
      print("✅ Map ready");

      // Update state with cached data
      if (result.aedList.isNotEmpty) {
        final mapNotifier = ref.read(mapStateProvider.notifier);
        mapNotifier.setAEDs(result.aedList);
        // ✅ Only update location if it's not null
        if (result.userLocation != null) {
          _updateUserLocation(
            result.userLocation!,  // ← Add the ! operator to assert non-null
            fromCache: result.isLocationCached,
          );
          _locationLastUpdated = result.locationAge;
          _isUsingCachedLocation = result.isLocationCached;
        }

        // Zoom to cached location if available
        if (result.shouldZoom && _mapViewController != null) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted && !_hasPerformedInitialZoom) {
            final closestAEDs = result.aedList.take(2).map((aed) => aed.location).toList();
            await _mapViewController!.zoomToUserAndClosestAEDs(
              result.userLocation!,
              closestAEDs,
            );
            _hasPerformedInitialZoom = true;

            // Update clusters
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted && _mapController != null) {
              _currentZoom = await _mapController!.getZoomLevel();
              // ✅ SET THE THRESHOLD
              _clusteringZoomThreshold = _currentZoom;
              print("👍 Initial clustering threshold set to: $_clusteringZoomThreshold");
              await _updateClusters();
            }
          }
        }
      }

      // Start GPS acquisition in background
      final hasLocation = await AppInitializationManager.isLocationAvailable();
      if (hasLocation) {
        _startGPSAcquisition();
      } else {
        _requestLocationPermission();
      }

      // Load fresh AEDs in background
      if (result.isConnected) {
        Future.delayed(const Duration(milliseconds: 500), () {
          // If we are connected on init, we want to force a fresh load.
          _startProgressiveAEDLoading(forceRefresh: result.isConnected);
        });
      }
    });
  }


  void _startGPSAcquisition() {
    print("🔍 Starting GPS acquisition (non-blocking)...");

    _locationService.startLocationTracking(
      onLocationUpdate: (location) {
        print("✅ Fresh GPS location: $location");

        // Update location
        _updateUserLocation(location);

        // ❌ REMOVE AUTO RE-ZOOM - Only zoom if we haven't done initial zoom yet
        final currentState = ref.read(mapStateProvider);
        if (!_hasPerformedInitialZoom && _mapViewController != null && currentState.aedList.length >= 2) {
          print("🎯 Performing INITIAL zoom to fresh GPS location + 2 closest AEDs");

          final closestAEDs = currentState.aedList.take(2).map((aed) => aed.location).toList();
          _mapViewController!.zoomToUserAndClosestAEDs(
            location,
            closestAEDs,
          ).then((_) async {
            _hasPerformedInitialZoom = true;

            // Update clusters after initial zoom
            await Future.delayed(const Duration(milliseconds: 500));
            if (mounted && _mapController != null) {
              try {
                _currentZoom = await _mapController!.getZoomLevel();
                // ✅ SET THE THRESHOLD
                _clusteringZoomThreshold = _currentZoom;
                print("👍 GPS clustering threshold set to: $_clusteringZoomThreshold");
                print("📍 Zoom level after GPS zoom: $_currentZoom");
                await _updateClusters();
              } catch (e) {
                print("⚠️ Error getting zoom: $e");
              }
            }
          });
        } else {
          print("📍 GPS updated, no auto-zoom (already zoomed: $_hasPerformedInitialZoom)");
        }
      },
      distanceFilter: AppConstants.locationDistanceFilterHigh,
    );
  }

  Future<void> _requestLocationPermission() async {
    await _mapReadyCompleter.future;

    // Load cached AEDs first
    await _loadCachedDataSilently();

    // Then show permission request
    final location = await _locationService.getCurrentLocationWithUI(
      context: context,
      showPermissionDialog: true,
      showErrorMessages: true,
    );

    if (location != null) {
      _updateUserLocation(location);
      _locationService.startLocationTracking(
        onLocationUpdate: _updateUserLocation,
        distanceFilter: AppConstants.locationDistanceFilterHigh,
      );
      setState(() => _isLocationAvailable = true);

      // Now load fresh data if connected
      final isConnected = await NetworkService.isConnected();
      if (isConnected) {
        await _fetchAEDsWithPriority(isRefresh: true);
      }
    } else {
      // User declined location
      setState(() => _isLocationAvailable = false);

      // ✅ CHECK: Stay at cached location if it exists
      final currentState = ref.read(mapStateProvider);

      if (currentState.userLocation != null) {
        print("❌ User declined location - staying at cached location");
        // Re-trigger the zoom just to be safe, as it's already zoomed
        if (_mapViewController != null && currentState.aedList.length >= 2) {
          final closestAEDs = currentState.aedList.take(2).map((aed) => aed.location).toList();
          await _mapViewController!.zoomToUserAndClosestAEDs(
            currentState.userLocation!, // Use cached location
            closestAEDs,
          );
        }
      } else {
        print("❌ User declined location & no cache - showing Greece view");
        await _mapViewController?.showDefaultGreeceView();
      }

      // Still fetch AEDs if connected
      final isConnected = await NetworkService.isConnected();
      if (isConnected) {
        await _fetchAEDsWithPriority(isRefresh: true);
      }
    }
  }


  Future<void> _startProgressiveAEDLoading({bool forceRefresh = false}) async {
    if (_isLoadingMarkers) return;

    setState(() => _isLoadingMarkers = true);

    try {
      final mapNotifier = ref.read(mapStateProvider.notifier);
      final aedRepository = ref.read(aedServiceProvider);
      final currentState = ref.read(mapStateProvider);

      // STEP 1: Load AED data (non-blocking)
      print("📦 Loading AED data...");

      List<AED> allAEDs;
      allAEDs = await aedRepository.fetchAEDs(forceRefresh: forceRefresh);

      if (allAEDs.isEmpty) {
        print("⚠️ No AEDs loaded");
        setState(() => _isLoadingMarkers = false);
        return;
      }

      print("✅ Loaded ${allAEDs.length} AED records");

      // STEP 2: Sort by distance if we have user location
      if (currentState.userLocation != null) {
        allAEDs = aedRepository.sortAEDsByDistance(
          allAEDs,
          currentState.userLocation!,
          currentState.navigation.transportMode,
        );
        print("📍 Sorted ${allAEDs.length} AEDs by distance");
      }

      // STEP 3: Load markers in batches of 10 (NON-BLOCKING)
      await _loadMarkersInBatches(allAEDs, mapNotifier, aedRepository);

      print("✅ Progressive loading completed");

    } catch (e) {
      print("❌ Error in progressive loading: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingMarkers = false);
      }
    }
  }

  /// Load markers in small batches with smooth animation
  Future<void> _loadMarkersInBatches(
      List<AED> allAEDs,
      dynamic mapNotifier,
      AEDService aedRepository,
      ) async {
    const batchSize = 50;  // ← Increased to 50 for faster loading
    bool hasPerformedFirstZoom = false;
    bool hasPerformedInitialClustering = false;

    for (int i = 0; i < allAEDs.length; i += batchSize) {
      if (!mounted) break;

      // ✅ STOP LOADING if user zoomed out too far (they're not looking at details anyway!)
      if (_currentZoom < 10.0) {
        print("⏸️ User zoomed out (zoom: $_currentZoom) - pausing AED loading");
        // Load remaining in background without updates
        final remainingAEDs = allAEDs;
        mapNotifier.setAEDs(remainingAEDs);
        print("📊 Loaded all ${remainingAEDs.length} AEDs in background");
        break;
      }

      final endIndex = (i + batchSize < allAEDs.length) ? i + batchSize : allAEDs.length;
      final batch = allAEDs.sublist(0, endIndex);

      // Update state with AED list
      mapNotifier.setAEDs(batch);
      // Only log every 200 AEDs
      if (i % 200 == 0 || endIndex == allAEDs.length) {
        print("📊 Loaded $endIndex/${allAEDs.length} AEDs");
      }

      // Zoom after first batch
      if (!hasPerformedFirstZoom && i == 0) {
        final currentState = ref.read(mapStateProvider);
        if (currentState.userLocation != null && _mapViewController != null && batch.length >= 2) {
          print("🎯 Zooming to user + 2 closest AEDs (first batch)");

          await Future.delayed(const Duration(milliseconds: 200));

          if (mounted && _mapViewController != null && !_hasPerformedInitialZoom) {
            final closestAEDs = batch.take(2).map((aed) => aed.location).toList();
            await _mapViewController!.zoomToUserAndClosestAEDs(
              currentState.userLocation!,
              closestAEDs,
            );
            _hasPerformedInitialZoom = true;

            await Future.delayed(const Duration(milliseconds: 300));
            if (mounted && _mapController != null) {
              try {
                _currentZoom = await _mapController!.getZoomLevel();
                // ✅ SET THE THRESHOLD
                _clusteringZoomThreshold = _currentZoom;
                print("👍 Batch load clustering threshold set to: $_clusteringZoomThreshold");
                print("📍 Initial zoom level after animation: $_currentZoom");
                await _updateClusters();
                hasPerformedInitialClustering = true;
              } catch (e) {
                print("⚠️ Error getting initial zoom: $e");
              }
            }
          }

          hasPerformedFirstZoom = true;
        }
      }

      // Update clusters less frequently - only every 200 AEDs
      if (hasPerformedInitialClustering && i > 0 && i % 200 == 0) {
        if (mounted && _currentZoom >= 10.0) {  // Only if still zoomed in
          await _updateClusters();
        }
      }

      // Minimal delay - just yield to UI
      await Future.delayed(const Duration(milliseconds: 1));
    }

    // Final clustering
    print("✅ All AEDs loaded - performing final clustering");
    if (mounted) {
      await _updateClusters();
    }
  }

  Future<void> _loadCachedDataSilently() async {
    try {
      // Use the priority loading method for immediate cached AED display
      await _fetchAEDsWithPriority(isRefresh: false);
    } catch (e) {
      print("⚠️ Error loading cached data: $e");
    }
  }

  Future<void> _loadCachedMapView() async {
    if (_mapController == null) return;

    try {
      final cachedRegion = await CacheService.getLastMapRegion();
      if (cachedRegion != null) {
        print("📍 Loading cached map region: ${cachedRegion.target}");
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(cachedRegion),
        );
      } else {
        print("📍 No cached region, using Greece center");
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            const CameraPosition(
              target: AppConstants.greeceCenter,
              zoom: AppConstants.greeceZoom,
            ),
          ),
        );
      }
    } catch (e) {
      print("⚠️ Error loading cached map view: $e");
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

      // Fetch fresh API key and data
      if (_googleMapsApiKey == null) {
        await _fetchGoogleMapsApiKey();  // ← Add await
      }

      // ✅ Wait a frame for state to propagate
      await Future.delayed(Duration.zero);

      _fetchAEDsWithPriority(isRefresh: true);

      // Now recalculate with fresh state
      final updatedState = ref.read(mapStateProvider);  // ← Read fresh state

      if (updatedState.navigation.isActive &&
          updatedState.navigation.destination != null &&
          updatedState.userLocation != null) {

        // If navigating, recalculate active route
        if (updatedState.navigation.hasStarted) {
          _recalculateActiveRoute();
        }
        // If just previewing, refresh the preview with new online state
        else {
          await _showNavigationPreviewForAED(updatedState.navigation.destination!);
        }
      }
    }
    // Connection lost
    else if (!currentlyOffline && !isConnected) {
      print("🔴 Connection lost - switching to offline mode");
      _wasOffline = true;
      ref.read(mapStateProvider.notifier).setOffline(true);

      // Update any active navigation to offline mode
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

    // Try to get fresh route
    if (_googleMapsApiKey != null && !currentState.isOffline) {
      try {
        final routeService = RouteService(_googleMapsApiKey!);
        final routeResult = await routeService.fetchRoute(
          currentState.userLocation!,
          currentState.navigation.destination!,
          currentState.navigation.transportMode,
        );

        if (routeResult != null && mounted) {
          final mapNotifier = ref.read(mapStateProvider.notifier);
          mapNotifier.updateRoute(
            routeResult.polyline,
            routeResult.duration,
            routeResult.actualDistance ?? LocationService.distanceBetween(
              currentState.userLocation!,
              currentState.navigation.destination!,
            ),
          );
        }
      } catch (e) {
        print("❌ Error recalculating route: $e");
      }
    }
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


  Future<void> _fetchGoogleMapsApiKey() async {
    _googleMapsApiKey = await NetworkService.fetchGoogleMapsApiKey();
    if (_googleMapsApiKey == null) {
      print("❌ Failed to fetch Google Maps API Key.");
    } else {
      // Initialize route preloader only
      _routePreloader = RoutePreloader(_googleMapsApiKey!, (status) {
        print("Preloader status: $status");
      });
    }
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    _mapViewController = MapViewController(controller, context);

    // Initialize navigation controller
    Future.delayed(const Duration(milliseconds: 100), () {
      _navigationController?.initialize(controller);
      print("✅ NavigationController initialized with map controller");
    });

    // Get initial zoom level
    try {
      _currentZoom = await controller.getZoomLevel();
      print("🗺️ Initial zoom: $_currentZoom");
    } catch (e) {
      _currentZoom = 12.0; // Default
    }

    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.complete();
    }

    await _loadCachedMapView();
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
    try {
      print("🔍 Setting up location after enable...");

      if (!await _locationService.hasPermission) {
        print("❌ No permission after enable");
        return;
      }

      // ✅ Load cached location FIRST (instant)
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

          print("📍 [GPS ON] Using cached location: $cachedLocation (age: ${_locationLastUpdated != null ? DateTime.now().difference(_locationLastUpdated!).inMinutes : '?'} min)");
          _updateUserLocation(cachedLocation, fromCache: true);
        }
      }

      print("🔍 Starting location stream immediately (non-blocking)");

      // Start GPS stream in background - will update when fix is acquired
      Future.delayed(Duration.zero, () {
        _locationService.startLocationTracking(
          onLocationUpdate: (location) {
            print("✅ Got location from stream: $location");
            _updateUserLocation(location);  // No fromCache parameter = fresh
            if (!_hasPerformedInitialZoom) {
              _performInitialZoomIfReady();
            }
          },
          distanceFilter: AppConstants.locationDistanceFilterHigh,
        );
      });

      print("✅ Location stream started - UI remains responsive");
    } catch (e) {
      print("❌ Error setting up location after enable: $e");
    }
  }


  Future<void> _preloadBothTransportModes(LatLng userLocation, LatLng aedLocation) async {
    if (_googleMapsApiKey == null || !await NetworkService.isConnected()) return;

    print("🚗🚶 Preloading both walking and driving routes...");

    // Get current state to access AED list
    final currentState = ref.read(mapStateProvider);

    for (final mode in ['walking', 'driving']) {
      // Check if already cached
      final cached = CacheService.getCachedRoute(userLocation, aedLocation, mode);
      if (cached != null) {
        print("✅ $mode route already cached");
        continue;
      }

      // Fetch and cache
      try {
        final routeService = RouteService(_googleMapsApiKey!);
        final route = await routeService.fetchRoute(userLocation, aedLocation, mode);

        if (route != null) {
          CacheService.setCachedRoute(userLocation, aedLocation, mode, route);
          if (route.actualDistance != null) {
            // Find the AED from state
            final aed = currentState.aedList.firstWhere(
                  (a) => a.location.latitude == aedLocation.latitude &&
                  a.location.longitude == aedLocation.longitude,
              orElse: () => currentState.aedList.first,
            );
            CacheService.setDistance('aed_${aed.id}_$mode', route.actualDistance!);
          }
          print("✅ Cached $mode route");
        }

        await Future.delayed(const Duration(milliseconds: 300)); // Rate limit
      } catch (e) {
        print("❌ Error caching $mode route: $e");
      }
    }
  }


  Map<String, String> getAEDEstimations(int aedId, LatLng userLocation, LatLng aedLocation) {
    // Try cached estimations first
    final walkingDist = CacheService.getDistance('aed_${aedId}_walking_est');
    final drivingDist = CacheService.getDistance('aed_${aedId}_driving_est');

    if (walkingDist != null && drivingDist != null) {
      return {
        'walking_distance': LocationService.formatDistance(walkingDist),
        'walking_time': LocationService.calculateOfflineETA(walkingDist, 'walking'),
        'driving_distance': LocationService.formatDistance(drivingDist),
        'driving_time': LocationService.calculateOfflineETA(drivingDist, 'driving'),
      };
    }

    // Calculate on the fly
    final walkingDistance = AEDService.calculateEstimatedDistance(userLocation, aedLocation, 'walking');
    final drivingDistance = AEDService.calculateEstimatedDistance(userLocation, aedLocation, 'driving');

    return {
      'walking_distance': LocationService.formatDistance(walkingDistance),
      'walking_time': LocationService.calculateOfflineETA(walkingDistance, 'walking'),
      'driving_distance': LocationService.formatDistance(drivingDistance),
      'driving_time': LocationService.calculateOfflineETA(drivingDistance, 'driving'),
    };
  }


// ✅ NEW METHOD - Single zoom logic
  Future<void> _performInitialZoomIfReady() async {
    final currentState = ref.read(mapStateProvider);

    if (currentState.userLocation != null &&
        currentState.aedList.isNotEmpty &&
        !_hasPerformedInitialZoom) {

      print("🎯 Performing initial zoom to user + closest AEDs");

      await _mapViewController?.zoomToUserAndClosestAEDs(
        currentState.userLocation!,
        currentState.aedList.take(2).map((aed) => aed.location).toList(), // Only 2 closest
      );

      _hasPerformedInitialZoom = true;
    }
  }




  Future<void> _updateUserLocation(LatLng location, {bool fromCache = false}) async {
    if (!fromCache) {
      _locationLastUpdated = DateTime.now();
      _isUsingCachedLocation = false;
    }
    final mapNotifier = ref.read(mapStateProvider.notifier);
    final currentState = ref.read(mapStateProvider);
    final LatLng? previousLocation = currentState.userLocation;
    final bool wasLocationNull = previousLocation == null;

    // Update location in state first
    mapNotifier.updateUserLocation(location);
    _navigationController?.updateUserLocation(location);

    // Handle first-time location
    if (wasLocationNull) {
      _cacheUserRegion(location);

      // Resort AEDs if we have any
      if (currentState.aedList.isNotEmpty) {
        _resortAEDs();
        _scheduleRoutePreloading();
      }
      return;
    }

    // Handle subsequent location updates
    final distance = LocationService.distanceBetween(previousLocation, location);

    // Resort if moved significantly (throttled to every 10 seconds)
    if (distance > AppConstants.locationSignificantMovement) {
      final now = DateTime.now();
      if (_lastResortTime == null || now.difference(_lastResortTime!).inSeconds >= 10) {
        _lastResortTime = now;
        _resortAEDs();
        _scheduleRoutePreloading();
      }
    }

    // Check if a closer AED is available during active navigation
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null &&
        currentState.aedList.length > 1) {
      _checkForCloserAED(location, currentState);
    }

    // Cache location for next app start
    if (mounted) {
      final currentState = ref.read(mapStateProvider);
      CacheService.saveLastAppState(currentState);
    }
  }

  bool _isLocationStale() {
    if (!_isUsingCachedLocation || _locationLastUpdated == null) {
      return false;
    }
    final age = DateTime.now().difference(_locationLastUpdated!).inHours;
    return age < 5; // Only consider "stale but usable" if < 5 hours
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

    ScaffoldMessenger.of(context).clearSnackBars(); // Clear any existing snackbars

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

    // Cancel current navigation
    _navigationController?.cancelNavigation();

    // Start navigation to new AED
    _startNavigation(newAED.location);

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Expanded(
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
    // Only notify navigation controller if navigating
    if (ref.read(mapStateProvider).navigation.hasStarted) {
      _navigationController?.onCameraMoveStarted();
    }
    print("📷 Camera move STARTED");
  }

  void _onCameraMoved() async {
    // Only notify navigation controller if navigating
    if (ref.read(mapStateProvider).navigation.hasStarted) {
      _navigationController?.onCameraMoved();
    }

    if (_mapController != null) {
      try {
        final currentZoom = await _mapController!.getZoomLevel();

        // Detect zoom changes - INCREASE threshold to reduce updates
        if ((currentZoom - _currentZoom).abs() > 0.8) {  // ← Changed from 0.3 to 0.8
          print("📷 Camera MOVING - Zoom: $_currentZoom → $currentZoom");
          _currentZoom = currentZoom;

          // Debounce cluster updates
          _debouncedClusterUpdate();
        }
      } catch (e) {
        // Ignore errors during rapid movements
      }
    }
  }

  void _onCameraIdle() async {
    if (_mapController != null) {
      try {
        final newZoom = await _mapController!.getZoomLevel();

        print("🎥 Camera STOPPED - Zoom: $newZoom");

        // Always update clusters when camera stops
        final zoomChanged = (newZoom - _currentZoom).abs() > 0.01;

        if (zoomChanged) {
          print("🗺️ Zoom changed from $_currentZoom to $newZoom");
          _currentZoom = newZoom;
        }

        // Update clusters whenever camera stops (zoom or pan)
        print("🔄 Updating clusters after camera stop...");
        await _updateClusters();

      } catch (e) {
        print("⚠️ Error in _onCameraIdle: $e");
      }
    }
  }

  void _debouncedClusterUpdate() {
    _clusterUpdateDebouncer?.cancel();
    _clusterUpdateDebouncer = Timer(const Duration(milliseconds: 500), () {  // ← Changed from 300ms to 500ms
      if (mounted) {
        print("⏱️ Debounced cluster update triggered");
        _updateClusters();
      }
    });
  }

  Future<void> _updateClusters() async {
    final currentState = ref.read(mapStateProvider);
    if (currentState.aedList.isEmpty || _mapController == null) {
      print("⚠️ No AEDs to cluster or no map controller");
      return;
    }

    // ✅ REQUEST 2: Get the location of the selected AED, if any
    final selectedAEDLocation = currentState.navigation.destination;

    try {
      // Get visible map bounds
      final visibleRegion = await _mapController!.getVisibleRegion();

      List<AED> aedsToCluster;
      if (_currentZoom < 8.0) {
        aedsToCluster = currentState.aedList;
        print("🌍 Low zoom ($_currentZoom) - clustering ALL AEDs");
      } else {
        aedsToCluster = currentState.aedList.where((aed) {
          return aed.location.latitude >= visibleRegion.southwest.latitude &&
              aed.location.latitude <= visibleRegion.northeast.latitude &&
              aed.location.longitude >= visibleRegion.southwest.longitude &&
              aed.location.longitude <= visibleRegion.northeast.longitude;
        }).toList();
      }

      // ✅ REQUEST 2: If an AED is selected, find it and remove it
      //    from the list that gets clustered.
      AED? selectedAED;
      if (selectedAEDLocation != null && currentState.navigation.isActive) {
        try {
          selectedAED = aedsToCluster.firstWhere(
                (aed) =>
            aed.location.latitude == selectedAEDLocation.latitude &&
                aed.location.longitude == selectedAEDLocation.longitude,
          );
          // Remove it from the list to be clustered
          aedsToCluster.remove(selectedAED);
          print("   → Excluding selected AED (${selectedAED.id}) from clustering.");
        } catch (e) {
          // Selected AED is not in the visible list, which is fine.
          print("   → Selected AED not found in visible list, proceeding.");
          selectedAED = null;
        }
      }

      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
      print("🗺️ CLUSTERING START");
      print("📊 Total AEDs: ${currentState.aedList.length}");
      print("👁️ AEDs to cluster: ${aedsToCluster.length}");
      print("🔍 Current zoom: $_currentZoom");
      print("👍 Threshold: $_clusteringZoomThreshold"); // Log threshold
      print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

      await Future.delayed(Duration.zero);

      // Cluster the *remaining* AEDs
      final clusters = SimpleClusterManager.clusterAEDs(
        aedsToCluster,
        _currentZoom,
        _clusteringZoomThreshold, // ✅ REQUEST 1: Pass the threshold
      );

      print("📍 Created ${clusters.length} clusters");

      int individualCount = 0;
      int clusterCount = 0;
      for (final cluster in clusters) {
        if (cluster.isCluster) {
          clusterCount++;
        } else {
          individualCount++;
        }
      }
      print("   → Individual AEDs: $individualCount");
      print("   → Clustered groups: $clusterCount");

      // Build markers
      final Set<Marker> newMarkers = {};
      for (final cluster in clusters) {
        final marker = await ClusterMarkerBuilder.buildMarker(
          cluster,
          _showNavigationPreviewForAED,
        );
        newMarkers.add(marker);
      }

      // ✅ REQUEST 2: Manually add the selected AED back as an individual marker
      if (selectedAED != null) {
        print("   → Manually re-adding selected AED as individual marker.");
        final selectedClusterPoint =
        ClusterPoint(selectedAED.location, [selectedAED]);
        final selectedMarker = await ClusterMarkerBuilder.buildMarker(
          selectedClusterPoint,
          _showNavigationPreviewForAED,
        );
        newMarkers.add(selectedMarker);
      }

      if (mounted) {
        setState(() {
          _clusterMarkers = newMarkers;
        });
        print("✅ CLUSTERS UPDATED - ${newMarkers.length} markers on map");
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
      }
    } catch (e) {
      print("⚠️ Error updating clusters: $e");
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

    // 1. ALWAYS try to get location. This will prompt if services are off or permissions are denied.
    final userLocation = await _locationService.getCurrentLocationWithUI(
      context: context,
      showPermissionDialog: allowLocationPrompt, // This will be 'true' from your build method
      showErrorMessages: allowLocationPrompt,  // This will be 'true'
    );

    // 2. If we got a location (it was on, or user just enabled it)
    if (userLocation != null) {
      _updateUserLocation(userLocation); // Update state with the fresh location

      // Re-read the AED list from the state
      final aedList = ref.read(mapStateProvider).aedList;

      if (_mapViewController != null && aedList.length >= 2) {
        print("🎯 Recentering to user + 2 closest AEDs");
        final closestAEDs = aedList.take(2).map((aed) => aed.location).toList();
        await _mapViewController!.zoomToUserAndClosestAEDs(
          userLocation,
          closestAEDs,
        );
      } else if (_mapController != null) { // ✅ FIX: Use _mapController directly
        // Fallback: just zoom to user if no AEDs
        print("🎯 Recentering to user");
        await _mapController!.animateCamera( // Use animateCamera
          CameraUpdate.newLatLngZoom(userLocation, 16.0), // 16.0 is a default zoom
        );
      }
      return; // We are done
    }

    // --- User Denied Location (userLocation is null) ---

    // 3. If location is null, check if we are in compass navigation
    final currentState = ref.read(mapStateProvider);
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null) {
      if (_mapViewController != null) {
        await _mapViewController!.zoomToAED(currentState.navigation.destination!);
      }
      return;
    }

    // 4. ✅ FIX: Check for cached location BEFORE falling back to Greece
    final cachedLocation = ref.read(mapStateProvider).userLocation;
    if (cachedLocation != null) {
      print("❌ User denied location - staying at cached location");
      // Re-zoom to the cached location + 2 AEDs, in case user panned away
      final aedList = ref.read(mapStateProvider).aedList;
      if (_mapViewController != null && aedList.length >= 2) {
        final closestAEDs = aedList.take(2).map((aed) => aed.location).toList();
        await _mapViewController!.zoomToUserAndClosestAEDs(
          cachedLocation, // Use cached location
          closestAEDs,
        );
      } else if (_mapController != null) { // Fallback to just cached location
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(cachedLocation, 16.0),
        );
      }
      return; // IMPORTANT: return here
    }

    // 5. True Fallback: No location, no cache, show Greece.
    if (_mapViewController != null) {
      await _mapViewController!.showDefaultGreeceView();
    }
  }

  // ==================== AED DATA MANAGEMENT ====================

  /// Loads AEDs with priority - closest ones first, then background loading
  Future<void> _fetchAEDsWithPriority({bool isRefresh = false}) async {
    final mapNotifier = ref.read(mapStateProvider.notifier);

    if (isRefresh) {
      mapNotifier.setRefreshing(true);
    } else {
      mapNotifier.setLoading(true); // Set loading for initial load
    }

    try {
      final aedRepository = ref.read(aedServiceProvider);

      // STEP 1: Load cached AEDs immediately for instant display
      if (!isRefresh) {
        print("🔍 STEP 1: Attempting to load cached AEDs...");
        final cachedAEDs = await CacheService.getAEDs();
        if (cachedAEDs != null) {
          final cachedAEDList = cachedAEDs
              .map((aed) => AED.fromMap(aed as Map<String, dynamic>))
              .whereType<AED>()
              .toList();

          if (cachedAEDList.isNotEmpty) {
            print("📦 Showing cached AEDs immediately (${cachedAEDList.length} AEDs)");

            final currentState = ref.read(mapStateProvider);
            final userLocation = currentState.userLocation;

            List<AED> sortedCachedAEDs;

            if (userLocation != null) {
              // 🔥 CRITICAL FIX: Calculate estimated distances for cached AEDs
              // Calculate distances in batches to avoid blocking
              _calculateDistancesInBatches(
                cachedAEDList,
                userLocation,
                currentState.navigation.transportMode,
              );

              sortedCachedAEDs = aedRepository.sortAEDsByDistance(
                  cachedAEDList,
                  userLocation,
                  currentState.navigation.transportMode
              );

              print("📏 Applied estimated distances to ${cachedAEDList.length} cached AEDs");
            } else {
              sortedCachedAEDs = cachedAEDList;
            }

            mapNotifier.setAEDs(sortedCachedAEDs);
            print("✅ Cached AEDs loaded and displayed with distances");
          } else {
            print("📦 Cached AEDs list is empty");
          }
        } else {
          // No cached AEDs found at all
          print("📦 No cached AEDs found");

          // Show error if offline and no cache
          final currentState = ref.read(mapStateProvider);
          if (currentState.isOffline && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No cached data available. Please connect to internet.'),
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }

      // STEP 2: Fetch fresh AEDs in background (non-blocking)
      final currentState = ref.read(mapStateProvider);
      if (!currentState.isOffline) {
        // We now call the progressive loader and pass the isRefresh flag.
        _startProgressiveAEDLoading(forceRefresh: isRefresh);
      }
    } catch (error) {
      print("❌ Error in priority AED loading: $error");
    } finally {
      mapNotifier.setRefreshing(false);
      mapNotifier.setLoading(false);
    }
  }

  Future<void> _calculateDistancesInBatches(
      List<AED> aeds,
      LatLng userLocation,
      String transportMode,
      ) async {
    const batchSize = 100;
    final multiplier = AEDService.getTransportModeMultiplier(transportMode);

    for (int i = 0; i < aeds.length; i += batchSize) {
      final batch = aeds.skip(i).take(batchSize).toList();

      for (final aed in batch) {
        final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
        final estimatedDistance = straightDistance * multiplier;
        CacheService.setDistance('aed_${aed.id}', estimatedDistance);
      }

      // Yield to UI thread every batch
      await Future.delayed(const Duration(microseconds: 1));
    }
  }


  void _resortAEDs() {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation == null || currentState.aedList.isEmpty) return;

    final aedRepository = ref.read(aedServiceProvider);
    final newSorted = aedRepository.sortAEDsByDistance(
        currentState.aedList,
        currentState.userLocation!,
        currentState.navigation.transportMode
    );

    // Only update if order actually changed
    bool orderChanged = false;
    for (int i = 0; i < currentState.aedList.length && i < newSorted.length; i++) {
      if (currentState.aedList[i].id != newSorted[i].id) {
        orderChanged = true;
        break;
      }
    }

    if (orderChanged) {
      print("📍 AED order changed - updating list");
      final mapNotifier = ref.read(mapStateProvider.notifier);
      mapNotifier.updateAEDsAndMarkers(newSorted);
    }
  }


  Future<void> _preloadTopRoutes() async {
    final currentState = ref.read(mapStateProvider);
    if (_routePreloader == null ||
        currentState.userLocation == null ||
        currentState.aedList.isEmpty) {
      return;
    }

    await _routePreloader!.preloadRoutesForClosestAEDs(
      aeds: currentState.aedList,
      userLocation: currentState.userLocation!,
      transportMode: currentState.navigation.transportMode,
      onRouteLoaded: (aed, route) {
        if (mounted) {
          setState(() {
            _preloadedRoutes[aed.id] = route;
            _limitPreloadedRoutesSize();
          });
        }
      },
    );
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
    const maxRoutes = 10; // Prevent memory bloat
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

// ==================== NAVIGATION & ROUTING ====================

  Future<void> _showNavigationPreviewForAED(LatLng aedLocation) async {
    final currentState = ref.read(mapStateProvider);
    final mapNotifier = ref.read(mapStateProvider.notifier);

    LatLng? currentLocation = currentState.userLocation;

    // If no location at all, show compass-only preview
    if (currentLocation == null) {
      mapNotifier.showNavigationPreview(aedLocation);
      if (_mapViewController != null) {
        await _mapViewController!.zoomToAED(aedLocation);
      }
      return;
    }

    // Show preview panel
    mapNotifier.showNavigationPreview(aedLocation);

    // Find the AED
    final aed = currentState.aedList.firstWhere(
          (aed) => aed.location.latitude == aedLocation.latitude &&
          aed.location.longitude == aedLocation.longitude,
      orElse: () => AED(id: -1, foundation: '', address: '', location: aedLocation),
    );

    final isStale = _isLocationStale();
    final isTooOld = _isLocationTooOld();

    if (!isTooOld && !currentState.isOffline && _googleMapsApiKey != null) {
      Future.delayed(Duration.zero, () {
        _preloadBothTransportModes(currentLocation, aedLocation);
      });
    }

    RouteResult? routeResult;

    // --- *** NEW LOGIC *** ---
    // Decide if we should fetch a fresh route first.
    // We do this if we are ONLINE, have an API key, and the location isn't "too old".
    final bool shouldFetchFresh = !currentState.isOffline &&
        _googleMapsApiKey != null &&
        !isTooOld;

    if (shouldFetchFresh) {
      print("🌎 Online: Attempting to fetch fresh route first...");
      try {
        final routeService = RouteService(_googleMapsApiKey!);
        routeResult = await routeService.fetchRoute(
            currentLocation, aedLocation, currentState.navigation.transportMode
        );

        if (routeResult != null) {
          print("✅ Fetched fresh route.");
          // Cache the new route
          CacheService.setCachedRoute(
              currentLocation, aedLocation,
              currentState.navigation.transportMode, routeResult
          );
          if (routeResult.actualDistance != null) {
            CacheService.setDistance('aed_${aed.id}', routeResult.actualDistance!);
          }
        } else {
          print("⚠️ Fresh route fetch failed (null result).");
        }
      } catch (e) {
        print("❌ Error fetching fresh route: $e");
      }
    }

    // If we didn't fetch a fresh route (or the fetch failed),
    // *now* we try to get one from the cache.
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
      }
    }
    // --- *** END NEW LOGIC *** ---

    // Show route if available (always gray when offline or using cached location)
    if (routeResult != null && !isTooOld) {
      // Show gray line if offline OR using cached location, blue if fresh and online
      final shouldShowGray = _isUsingCachedLocation || currentState.isOffline;

      final polyline = shouldShowGray
          ? Polyline(
        polylineId: routeResult.polyline.polylineId,
        points: routeResult.polyline.points,
        color: Colors.grey,
        width: 4,
      )
          : routeResult.polyline;

      mapNotifier.updateRoute(
        polyline,
        routeResult.duration,
        routeResult.actualDistance ?? LocationService.distanceBetween(
            currentLocation, aedLocation
        ),
      );

      if (_mapViewController != null) {
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

    RouteResult? routeResult;

    // Try cached route first (exact match)
    routeResult = CacheService.getCachedRoute(
        currentLocation, aedLocation, currentState.navigation.transportMode
    );

    // If no exact match, try nearby cached routes (within 1km)
    routeResult ??= CacheService.getCachedRouteNearby(
      currentLocation,
      aedLocation,
      currentState.navigation.transportMode,
      maxDistanceMeters: 1000,
    );

    // Only fetch fresh route if location is fresh AND online AND no cached route
    if (routeResult == null && !isStale && !currentState.isOffline &&
        _googleMapsApiKey != null) {
      try {
        final routeService = RouteService(_googleMapsApiKey!);
        routeResult = await routeService.fetchRoute(
            currentLocation, aedLocation, currentState.navigation.transportMode
        );

        if (routeResult != null) {
          CacheService.setCachedRoute(
              currentLocation, aedLocation,
              currentState.navigation.transportMode, routeResult
          );
        }
      } catch (e) {
        print("❌ Error fetching route: $e");
      }
    }

    // Determine if we should show the route
    if (routeResult != null && !routeResult.isOffline) {
      // Show gray line if offline OR using stale/cached location
      final shouldShowGray = _isUsingCachedLocation || currentState.isOffline || isStale;

      final polyline = shouldShowGray
          ? Polyline(
        polylineId: routeResult.polyline.polylineId,
        points: routeResult.polyline.points,
        color: Colors.grey,
        width: 4,
      )
          : routeResult.polyline;

      mapNotifier.updateRoute(
        polyline,
        routeResult.duration,
        routeResult.actualDistance ?? LocationService.distanceBetween(
            currentLocation, aedLocation
        ),
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

      print("🧭 Starting navigation with stale/offline route");
    }
  }

  void _cancelNavigation() {
    _navigationController?.cancelNavigation();

    // Restart normal location tracking
    _locationService.startLocationTracking(
      onLocationUpdate: _updateUserLocation,
      distanceFilter: AppConstants.locationDistanceFilterHigh,
    );

    final currentState = ref.read(mapStateProvider);
    final wasInFullNavigation = currentState.navigation.hasStarted;
    final mapNotifier = ref.read(mapStateProvider.notifier);

    if (wasInFullNavigation) {
      // Coming from FULL NAVIGATION - go back to preview mode
      mapNotifier.showNavigationPreview(currentState.navigation.destination!);

      // Reset camera bearing/tilt but keep zoom/position
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
      // Coming from PREVIEW MODE - just close panel, keep current camera position
      mapNotifier.cancelNavigation();
      // ✅ DON'T change camera position - keep current zoom
    }

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
    if (_positionSubscription?.isPaused ?? false) {
      _positionSubscription?.resume();
    }

    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final hasPermission = await _locationService.hasPermission;
    final shouldHaveLocation = isServiceEnabled && hasPermission;

    // ✅ Handle location state changes properly
    if (!_isLocationAvailable && shouldHaveLocation) {
      print("📍 Location became available during resume");
      _hasPerformedInitialZoom = false;
      setState(() {
        _isLocationAvailable = true;
      });
      await _setupLocationAfterEnable();
    } else if (_isLocationAvailable && !shouldHaveLocation) {
      print("📍 Location became unavailable during resume");
      setState(() {
        _isLocationAvailable = false;
      });
    } else {
      setState(() {
        _isLocationAvailable = shouldHaveLocation;
      });
    }

    if (!mounted) return;

    // Connectivity check logic (unchanged)
    final isConnected = await NetworkService.isConnected();
    if (_wasOffline && isConnected) {
      _wasOffline = false;
      ref.read(mapStateProvider.notifier).setOffline(false);
      await _fetchAEDsWithPriority(isRefresh: true);
    }

    // Update check logic (unchanged)
    final now = DateTime.now();
    final shouldCheckUpdates = _lastBackgroundTime == null ||
        now.difference(_lastBackgroundTime!).inMinutes > 2;

    if (shouldCheckUpdates && isConnected) {
      final aedRepository = ref.read(aedServiceProvider);
      final newAEDs = await aedRepository.fetchAEDs(forceRefresh: false);
      final currentState = ref.read(mapStateProvider);
      final changed = aedRepository.haveAEDsChanged(currentState.aedList, newAEDs);

      if (changed) {
        final mapNotifier = ref.read(mapStateProvider.notifier);
        mapNotifier.updateAEDsAndMarkers(newAEDs);
      }
    }
  }


  void _pauseApp() {
    _lastBackgroundTime = DateTime.now();
    _positionSubscription?.pause();
  }

// ==================== WIDGET BUILD ====================

  @override
  Widget build(BuildContext context) {
    ref.read(mapStateProvider.notifier);
    final mapState = ref.watch(mapStateProvider);

    return AEDMapDisplay(
      config: AEDMapConfig(
        isLoading: mapState.isLoading,
        aedMarkers: _clusterMarkers,
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
            _preloadedRoutes.clear();

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
                  mode // Use 'mode' (the new mode)
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
                      mapNotifier.updateAEDsAndMarkers(improvedAEDs);
                    }
                  },
                );
              }
              _scheduleRoutePreloading();
            }

            // 5. ✅ FIX: Update route if in PREVIEW *or* NAVIGATION
            if (currentState.navigation.isActive && // Was hasStarted
                currentState.navigation.destination != null &&
                currentState.userLocation != null) {
              // This will now read the correct, updated state
              _showNavigationPreviewForAED(currentState.navigation.destination!);
            }
          });
        },

      onRecenterPressed: () => _recenterMapToUserAndAEDs(allowLocationPrompt: true),
      onMapCreated: _onMapCreated,
      onCancelNavigation: _cancelNavigation,
      onExternalNavigation: _openExternalNavigation,
    );
  }

  @override
  void dispose() {
    // Cancel all timers and subscriptions
    NetworkService.removeConnectivityListener(_onConnectivityChanged);
    NetworkService.stopConnectivityMonitoring();
    _positionSubscription?.cancel();
    _navigationController?.dispose();

    // ✅ OLD STATE CLEANUP
    _transportModeDebouncer?.cancel();
    _improvementTimer?.cancel();
    _locationService.dispose();

    // Clear all caches
    _preloadedRoutes.clear();

    // Reset static variables
    _lastResortTime = null;

    // Dispose controllers
    _mapController?.dispose();
    _mapViewController = null;
    _clusterMarkers.clear();

    _clusterUpdateDebouncer?.cancel();


    CacheService.dispose();

    // Complete any pending operations
    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.completeError("Widget disposed");
    }

    // Remove observers
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }
}