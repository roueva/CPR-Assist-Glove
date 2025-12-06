import 'dart:async';
import 'dart:math';
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
  final Map<String, RouteResult> _preloadedRoutes = {};
  bool _hasPerformedInitialZoom = false;
  DateTime? _lastResortTime;
  Timer? _transportModeDebouncer;
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
  bool _hasZoomedToFreshGPS = false;
  DateTime? _lastClusterUpdateTime;
  String? _lastVisibleBounds;
  bool _isGPSStreamActive = false;
  DateTime? _lastRouteUpdateTime;
  LatLng? _lastRouteUpdateLocation;
  DateTime? _lastOffRouteBannerTime;
  String _lastFetchReason = '';
  bool _isCurrentlyNavigating = false;
  bool _isClusteringInProgress = false;

  static const bool _enableDebugLogs = false; // ✅ Set to false for production

  void _debugLog(String message) {
    if (_enableDebugLogs) {
      print(message);
    }
  }

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
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _initializeApp();
      }
    });

    // ✅ Safety timeout: If map doesn't load in 15 seconds, force complete
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
    print("🚀 Starting app initialization...");

    // Initialize using the manager
    final aedRepository = ref.read(aedServiceProvider);
    final networkService = ref.read(networkServiceProvider);
    final result = await AppInitializationManager.initializeApp(aedRepository, networkService);

    // Store API key
    _googleMapsApiKey = result.apiKey;

    // Initialize navigation controller
    _navigationController = nav.NavigationController(
      onStateChanged: () => setState(() {}),
      onRecenterButtonVisibilityChanged: (visible) => setState(() {}),
    );

    // Initialize route preloader if we have API key
    if (_googleMapsApiKey != null) {
      _routePreloader = RoutePreloader(_googleMapsApiKey!, (status) {});
    }

    // ✅ FIX: Load data IMMEDIATELY without waiting for map
    print("📦 Loading initial data (NOT waiting for map)...");

    if (result.aedList.isNotEmpty) {
      final mapNotifier = ref.read(mapStateProvider.notifier);
      mapNotifier.setAEDs(result.aedList);

      if (result.userLocation != null) {
        _updateUserLocation(
          result.userLocation!,
          fromCache: result.isLocationCached,
        );
        _locationLastUpdated = result.locationAge;
        _isUsingCachedLocation = result.isLocationCached;
      }
    }

    // ✅ Start GPS immediately (don't wait for map)
    final hasLocation = await AppInitializationManager.isLocationAvailable();
    if (hasLocation) {
      _startGPSAcquisition();
    } else {
      // ✅ Request permission AFTER map is ready
      _mapReadyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print("⚠️ Map timeout - requesting permission anyway");
        },
      ).then((_) {
        if (mounted) {
          _requestLocationPermission();
        }
      });
    }

    // ✅ Load fresh AEDs immediately if connected
    if (result.isConnected) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _startProgressiveAEDLoading(forceRefresh: true);
        }
      });
    }

    // ✅ NOW wait for map to zoom (non-blocking for data)
    if (result.shouldZoom && result.userLocation != null && result.aedList.length >= 2) {
      _mapReadyCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => print("⚠️ Map timeout - skipping zoom"),
      ).then((_) async {
        if (!mounted || _mapViewController == null) return;

        if (!_hasPerformedInitialZoom) {
          final closestAEDs = result.aedList.take(2).map((aed) => aed.location).toList();
          await _mapViewController!.zoomToUserAndClosestAEDs(
            result.userLocation!,
            closestAEDs,
          );
          _hasPerformedInitialZoom = true;

          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted && _mapController != null) {
            _currentZoom = await _mapController!.getZoomLevel();
            await _updateClusters();

            Future.delayed(const Duration(seconds: 5), () {
              if (mounted && !_hasZoomedToFreshGPS && _clusteringZoomThreshold == 16.0) {
                _setClusteringThreshold(_currentZoom);
              }
            });
          }
        }
      }).catchError((error) {
        print("⚠️ Zoom error: $error");
      });
    }

    print("✅ App initialization complete");
  }


  Future<void> _setClusteringThreshold(double zoomLevel) async {

    _clusteringZoomThreshold = zoomLevel;

    if (mounted) {
      await _updateClusters();
    }
  }



  void _startGPSAcquisition() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _debugLog("🔍 Starting GPS acquisition (non-blocking)...");

    if (_isGPSStreamActive) {
      print("⚠️ GPS stream already active, skipping");
      return;
    }

    _isGPSStreamActive = true;
    print("🔍 Starting GPS acquisition (non-blocking)...");

    _locationService.startProgressiveLocationTracking(
      onLocationUpdate: (location) async {
        _debugLog("✅ Fresh GPS location: $location");
        _locationLastUpdated = DateTime.now();
        _isUsingCachedLocation = false;

        final currentState = ref.read(mapStateProvider);
        final cachedLocation = currentState.userLocation;

        bool isSignificantlyDifferent = false;
        if (cachedLocation != null) {
          final distance = LocationService.distanceBetween(cachedLocation, location);
          isSignificantlyDifferent = distance > 100;
          _debugLog("📏 Distance from cached: ${distance.toStringAsFixed(0)}m");
        }

        // ✅ CRITICAL: Update location FIRST
        _updateUserLocation(location);

        // ✅ CRITICAL: Re-sort AEDs with fresh location
        if (currentState.aedList.isNotEmpty && cachedLocation != null && isSignificantlyDifferent) {
          print("🔄 Re-sorting AEDs with fresh GPS location...");
          final aedRepository = ref.read(aedServiceProvider);
          final resortedAEDs = aedRepository.sortAEDsByDistance(
            currentState.aedList,
            location,
            currentState.navigation.transportMode,
          );

          // Update state with re-sorted AEDs
          ref.read(mapStateProvider.notifier).setAEDs(resortedAEDs);
          print("✅ AEDs re-sorted - new closest: ${resortedAEDs.first.address}");
        }

        // ✅ Get FRESH state after re-sorting
        final updatedState = ref.read(mapStateProvider);

        // ✅ ALWAYS zoom to fresh GPS if we haven't zoomed to it yet
        if (!_hasZoomedToFreshGPS &&
            _mapViewController != null &&
            updatedState.aedList.length >= 2) {

          if (_hasPerformedInitialZoom && isSignificantlyDifferent && mounted) {
            _showLocationUpdatedBanner(location, cachedLocation);
          }

          // ✅ Use the NEWLY SORTED AEDs
          final closestAEDs = updatedState.aedList.take(2).map((aed) => aed.location).toList();

          print("🎯 Zooming to fresh GPS + 2 closest AEDs:");
          print("   1. ${updatedState.aedList[0].address}");
          print("   2. ${updatedState.aedList[1].address}");

          await _mapViewController!.zoomToUserAndClosestAEDs(
            location,
            closestAEDs,
          );

          _hasPerformedInitialZoom = true;
          _hasZoomedToFreshGPS = true;

          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted && _mapController != null) {
            try {
              _currentZoom = await _mapController!.getZoomLevel();
              await _setClusteringThreshold(_currentZoom);
            } catch (e) {
              _debugLog("⚠️ Error getting zoom: $e");
            }
          }
        } else {
          _debugLog("📍 GPS updated, no zoom (fresh GPS already acquired)");
        }
      },
      isNavigating: _isCurrentlyNavigating,
      distanceFilter: _isCurrentlyNavigating ? 0 : 10,  // ✅ 0 when navigating, 10 when not
    );
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

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.my_location, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF194E9D),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
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
      final currentState = ref.read(mapStateProvider);
      _locationService.startProgressiveLocationTracking(
        onLocationUpdate: _updateUserLocation,
        isNavigating: currentState.navigation.hasStarted,
        distanceFilter: currentState.navigation.hasStarted ? 0 : 10,
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
        _debugLog("❌ User declined location - staying at cached location");
        // Re-trigger the zoom just to be safe, as it's already zoomed
        if (_mapViewController != null && currentState.aedList.length >= 2) {
          final closestAEDs = currentState.aedList.take(2).map((aed) => aed.location).toList();
          await _mapViewController!.zoomToUserAndClosestAEDs(
            currentState.userLocation!, // Use cached location
            closestAEDs,
          );
        }
      } else {
        _debugLog("❌ User declined location & no cache - showing Greece view");
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
      _debugLog("📦 Loading AED data...");

      List<AED> allAEDs;
      allAEDs = await aedRepository.fetchAEDs(forceRefresh: forceRefresh);

      if (allAEDs.isEmpty) {
        _debugLog("⚠️ No AEDs loaded");
        setState(() => _isLoadingMarkers = false);
        return;
      }

      _debugLog("✅ Loaded ${allAEDs.length} AED records");

      // STEP 2: Sort by distance if we have user location
      if (currentState.userLocation != null) {
        allAEDs = aedRepository.sortAEDsByDistance(
          allAEDs,
          currentState.userLocation!,
          currentState.navigation.transportMode,
        );
        print("📍 Sorted ${allAEDs.length} AEDs by distance");
      }

      // STEP 3: Load markers in batches (NON-BLOCKING)
      await _loadMarkersInBatches(allAEDs, mapNotifier, aedRepository);

      // ✅ NOW trigger route preloading AFTER progressive loading is done
      if (forceRefresh && _googleMapsApiKey != null && currentState.userLocation != null) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            _preloadTopRoutes();
          }
        });
      }

    } catch (e) {
      _debugLog("❌ Error in progressive loading: $e");
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
        _debugLog("⏸️ User zoomed out (zoom: $_currentZoom) - pausing AED loading");
        // Load remaining in background without updates
        final remainingAEDs = allAEDs;
        mapNotifier.setAEDs(remainingAEDs);
        _debugLog("📊 Loaded all ${remainingAEDs.length} AEDs in background");
        break;
      }

      final endIndex = (i + batchSize < allAEDs.length) ? i + batchSize : allAEDs.length;
      final batch = allAEDs.sublist(0, endIndex);

      // Update state with AED list
      mapNotifier.setAEDs(batch);
      // Only log every 200 AEDs
      if (i % 200 == 0 || endIndex == allAEDs.length) {
      }

      // Zoom after first batch
      if (!hasPerformedFirstZoom && i == 0) {
        final currentState = ref.read(mapStateProvider);
        if (currentState.userLocation != null && _mapViewController != null && batch.length >= 2) {

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

                // ✅ Use helper method (won't set if already set by GPS)
                await _setClusteringThreshold(_currentZoom);
                hasPerformedInitialClustering = true;
              } catch (e) {
                _debugLog("⚠️ Error getting initial zoom: $e");
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
      if (i % 50 == 0 && i > 0) {
        await Future.delayed(const Duration(milliseconds: 16));  // ✅ One frame
      }
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

        // ✅ Update clusters with new data
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await _updateClusters();
        }

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
    _mapViewController = MapViewController(controller, context);

    // Initialize navigation controller
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_navigationController != null && mounted) {
        _navigationController!.initialize(controller);
        print("✅ NavigationController initialized with map controller");
      }
    });

    // Get initial zoom level
    try {
      _currentZoom = await controller.getZoomLevel();
      print("🗺️ Initial zoom: $_currentZoom");
    } catch (e) {
      print("⚠️ Could not get initial zoom: $e");
      _currentZoom = 12.0; // Default
    }

    // ✅ Complete the future if not already done
    if (!_mapReadyCompleter.isCompleted) {
      print("✅ Completing map ready completer");
      _mapReadyCompleter.complete();
    } else {
      print("⚠️ Map ready completer already completed");
    }

    // Load cached view (non-blocking)
    try {
      await _loadCachedMapView();
    } catch (e) {
      print("⚠️ Error loading cached map view: $e");
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
    _positionSubscription?.cancel();
    _positionSubscription = null;
    print("🛑 Cancelled any existing location streams");
    try {
      print("🔍 Setting up location after enable...");

      if (!await _locationService.hasPermission) {
        print("❌ No permission after enable");
        return;
      }

      // ✅ Reset zoom flags so we can zoom to fresh GPS
      _hasPerformedInitialZoom = false;
      _hasZoomedToFreshGPS = false;

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
        _locationService.startProgressiveLocationTracking(
          onLocationUpdate: (location) async {  // ✅ Make this async
            print("✅ Got location from stream: $location");

            // ✅ ADD: Re-sort AEDs if this is significantly different from cached
            final currentState = ref.read(mapStateProvider);
            if (currentState.userLocation != null && currentState.aedList.isNotEmpty) {
              final distance = LocationService.distanceBetween(currentState.userLocation!, location);

              if (distance > 100) {
                print("🔄 Re-sorting AEDs with fresh location (${distance.toStringAsFixed(0)}m from cached)");
                final aedRepository = ref.read(aedServiceProvider);
                final resortedAEDs = aedRepository.sortAEDsByDistance(
                  currentState.aedList,
                  location,
                  currentState.navigation.transportMode,
                );

                ref.read(mapStateProvider.notifier).setAEDs(resortedAEDs);
                print("✅ AEDs re-sorted after location services enabled");
              }
            }

            _updateUserLocation(location);

            if (!_hasPerformedInitialZoom) {
              _performInitialZoomIfReady();
            }
          },
          isNavigating: false,
          distanceFilter: 10,  // ✅ Use 10m when not navigating
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

    // ✅ Skip insignificant updates when NOT navigating
    if (!wasLocationNull && !fromCache && !currentState.navigation.hasStarted) {
      final distance = LocationService.distanceBetween(previousLocation, location);

      if (distance < 5) {
        // Not navigating and tiny movement - skip update
        _locationLastUpdated = DateTime.now();
        return;
      }
    }

    // Update location in state first
    mapNotifier.updateUserLocation(location);
    _navigationController?.updateUserLocation(location);

    // Handle first-time location
    if (wasLocationNull) {
      _cacheUserRegion(location);

      // Resort AEDs if we have any
      if (currentState.aedList.isNotEmpty) {
        _resortAEDs();
        // ✅ First-time location - always preload
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

    // Update route if actively navigating
// ✅ ALWAYS update camera FIRST during active navigation (smooth following)
    if (currentState.navigation.hasStarted &&
        _navigationController != null &&
        _navigationController!.isActive) {
      _navigationController!.updateUserLocation(location);
    }

// ✅ ALWAYS calculate and update distance/time with EVERY location update
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null) {

      // Calculate remaining distance along route (INSTANT, NO API CALL)
      final mapNotifier = ref.read(mapStateProvider.notifier);
      double remainingDistance;
      String estimatedTime;

      if (currentState.navigation.route != null &&
          currentState.navigation.route!.points.isNotEmpty) {
        // Use actual route polyline for accurate calculation
        final routeCalc = _calculateRemainingRouteDistance(
          location,
          currentState.navigation.route!.points,
          currentState.navigation.destination!,
        );

        remainingDistance = routeCalc.distance;
        estimatedTime = _calculateSmartETA(
          remainingDistance,
          currentState.navigation.route!,
          currentState.navigation.transportMode,
        );
      } else {
        // Fallback to straight-line distance
        remainingDistance = LocationService.distanceBetween(
            location,
            currentState.navigation.destination!
        );
        estimatedTime = LocationService.calculateOfflineETA(
          remainingDistance,
          currentState.navigation.transportMode,
        );
      }

      // ✅ Update UI IMMEDIATELY with every location change
      mapNotifier.updateRoute(
        currentState.navigation.route,
        estimatedTime,
        remainingDistance,
      );

      // ✅ Smartly fetch new route only when needed (not every update)
      await _updateNavigationRoute(location, currentState.navigation.destination!);
    }

    // Cache location for next app start
    if (mounted) {
      final currentState = ref.read(mapStateProvider);
      CacheService.saveLastAppState(currentState);
    }
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

      if (shouldFetchRoute) {
        print("🔄 Fetching updated route (reason: $_lastFetchReason)...");
        _lastRouteUpdateTime = DateTime.now();
        _lastRouteUpdateLocation = currentLocation;

        try {
          final routeService = RouteService(_googleMapsApiKey!);
          final newRoute = await routeService.fetchRoute(
            currentLocation,
            destination,
            currentState.navigation.transportMode,
          );

          if (newRoute != null && mounted) {
            print("✅ Updated route: ${newRoute.distanceText} (${newRoute.duration})");

            // ✅ CRITICAL: Parse and store the NEW original metrics
            final newOriginalDurationMinutes = _parseDurationToMinutes(newRoute.duration);

            // Update with real route data
            mapNotifier.updateRoute(
              newRoute.polyline,
              newRoute.duration,
              newRoute.actualDistance ?? LocationService.distanceBetween(currentLocation, destination),
            );

            // ✅ ADD THIS: Update the original metrics for future calculations
            mapNotifier.setOriginalRouteMetrics(
              originalDistance: newRoute.actualDistance ?? 0,
              originalDurationMinutes: newOriginalDurationMinutes,
            );

            // Cache the new route
            CacheService.setCachedRoute(
              currentLocation,
              destination,
              currentState.navigation.transportMode,
              newRoute,
            );
          }
        } catch (e) {
          print("⚠️ Error updating navigation route: $e");
        }
      }
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
    final lat1 = from.latitude * (3.14159 / 180);
    final lat2 = to.latitude * (3.14159 / 180);
    final dLon = (to.longitude - from.longitude) * (3.14159 / 180);

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);

    final bearing = atan2(y, x) * (180 / 3.14159);
    return (bearing + 360) % 360; // Normalize to 0-360
  }

  /// Helper: Parse Google Maps duration string to minutes
  int _parseDurationToMinutes(String duration) {
    try {
      // Handle formats like "10 mins", "1 hour 5 mins", "2 hours"
      int totalMinutes = 0;

      // Extract hours
      final hourMatch = RegExp(r'(\d+)\s*hour').firstMatch(duration.toLowerCase());
      if (hourMatch != null) {
        totalMinutes += int.parse(hourMatch.group(1)!) * 60;
      }

      // Extract minutes
      final minMatch = RegExp(r'(\d+)\s*min').firstMatch(duration.toLowerCase());
      if (minMatch != null) {
        totalMinutes += int.parse(minMatch.group(1)!);
      }

      return totalMinutes;
    } catch (e) {
      print("⚠️ Error parsing duration: $e");
      return 0;
    }
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

    // REASON 3: Moved significant distance OR enough time passed (not AND)
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

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Recalculating route...',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
      ),
    );
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

    // ✅ FIX: Just update zoom value, DON'T trigger cluster updates
    if (_mapController != null) {
      try {
        final currentZoom = await _mapController!.getZoomLevel();

        // Just store the zoom value silently
        if ((currentZoom - _currentZoom).abs() > 0.8) {
          _currentZoom = currentZoom;
          // Don't call _debouncedClusterUpdate() here!
        }
      } catch (e) {
        // Ignore errors during rapid movements
      }
    }

    // ✅ Clustering happens ONLY in _onCameraIdle, not here
  }

  void _onCameraIdle() async {
    if (_mapController != null) {
      try {
        final newZoom = await _mapController!.getZoomLevel();

        // Always update clusters when camera stops
        final zoomChanged = (newZoom - _currentZoom).abs() > 0.3;

        if (zoomChanged) {
          print("🗺️ Zoom changed from $_currentZoom to $newZoom");
          _currentZoom = newZoom;
        }

        // ✅ Update clusters whenever camera stops (zoom or pan)
        print("🔄 Updating clusters after camera stop...");
        _debouncedClusterUpdate();  // ✅ Call it HERE instead of direct _updateClusters()

      } catch (e) {
        print("⚠️ Error in _onCameraIdle: $e");
      }
    }
  }

  void _debouncedClusterUpdate() {
    _clusterUpdateDebouncer?.cancel();
    _clusterUpdateDebouncer = null;
    _clusterUpdateDebouncer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        print("⏱️ Debounced cluster update triggered");
        _updateClusters();
      }
    });
  }

  Future<void> _updateClusters() async {
    // ✅ Throttle cluster updates to max once per 500ms
    final now = DateTime.now();
    if (_lastClusterUpdateTime != null &&
        now.difference(_lastClusterUpdateTime!) < const Duration(milliseconds: 500)) {
      _debugLog("⏸️ Skipping cluster update (throttled)");
      return;
    }
    _lastClusterUpdateTime = now;

    final currentState = ref.read(mapStateProvider);
    if (currentState.aedList.isEmpty || _mapController == null) {
      return;
    }

    // ✅ Skip if already clustering (prevent race conditions)
    if (_isClusteringInProgress) {
      _debugLog("⏸️ Skipping cluster update (already in progress)");
      return;
    }
    _isClusteringInProgress = true;

    try {
      // ✅ Check if markers actually changed
      final newMarkerCount = currentState.aedList.length;
      if (_clusterMarkers.isNotEmpty && _clusterMarkers.length == newMarkerCount) {
        final visibleRegion = await _mapController!.getVisibleRegion();
        final visibleBounds = '${visibleRegion.southwest.latitude}_${visibleRegion.northeast.latitude}';

        if (_lastVisibleBounds == visibleBounds) {
          _debugLog("⏸️ Skipping cluster update (markers unchanged)");
          _isClusteringInProgress = false;
          return;
        }
        _lastVisibleBounds = visibleBounds;
      }

      final selectedAEDLocation = currentState.navigation.destination;

      final visibleRegion = await _mapController!.getVisibleRegion();

      List<AED> aedsToCluster;
      if (_currentZoom < 8.0) {
        aedsToCluster = currentState.aedList;
        _debugLog("🌍 Low zoom ($_currentZoom) - clustering ALL AEDs");
      } else {
        aedsToCluster = currentState.aedList.where((aed) {
          return aed.location.latitude >= visibleRegion.southwest.latitude &&
              aed.location.latitude <= visibleRegion.northeast.latitude &&
              aed.location.longitude >= visibleRegion.southwest.longitude &&
              aed.location.longitude <= visibleRegion.northeast.longitude;
        }).toList();
      }

      AED? selectedAED;
      if (selectedAEDLocation != null && currentState.navigation.isActive) {
        try {
          selectedAED = aedsToCluster.firstWhere(
                (aed) =>
            aed.location.latitude == selectedAEDLocation.latitude &&
                aed.location.longitude == selectedAEDLocation.longitude,
          );
          aedsToCluster.remove(selectedAED);
          _debugLog("   → Excluding selected AED (${selectedAED.id}) from clustering.");
        } catch (e) {
          _debugLog("   → Selected AED not found in visible list, proceeding.");
          selectedAED = null;
        }
      }

      await Future.delayed(Duration.zero);

      final clusters = SimpleClusterManager.clusterAEDs(
        aedsToCluster,
        _currentZoom,
        _clusteringZoomThreshold,
      );

      _debugLog("📍 Created ${clusters.length} clusters");

      final Set<Marker> newMarkers = {};
      for (final cluster in clusters) {
        final marker = await ClusterMarkerBuilder.buildMarker(
          cluster,
          _showNavigationPreviewForAED,
        );
        newMarkers.add(marker);
      }

      if (selectedAED != null) {
        _debugLog("   → Manually re-adding selected AED as individual marker.");
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
      }
    } catch (e) {
      print("⚠️ Error updating clusters: $e");
    } finally {
      _isClusteringInProgress = false;
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

    // 2. If we got a location
    if (userLocation != null) {
      _updateUserLocation(userLocation);

      final aedList = ref.read(mapStateProvider).aedList;

      if (_mapViewController != null && aedList.length >= 2) {
        print("🎯 Recentering to user + 2 closest AEDs");
        final closestAEDs = aedList.take(2).map((aed) => aed.location).toList();

        // ✅ 1. Perform the zoom
        await _mapViewController!.zoomToUserAndClosestAEDs(
          userLocation,
          closestAEDs,
        );

        // ✅ 2. Force update the threshold to the new zoom level
        if (mounted && _mapController != null) {
          try {
            // Wait a tiny bit for the camera to strictly settle
            await Future.delayed(const Duration(milliseconds: 100));
            final newZoom = await _mapController!.getZoomLevel();

            // Apply the fix so they don't cluster
            await _setClusteringThreshold(newZoom);
          } catch (e) {
            print("Error setting threshold after recenter: $e");
          }
        }
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
    final currentState = ref.read(mapStateProvider);  // ✅ ADD THIS LINE
    final mapNotifier = ref.read(mapStateProvider.notifier);

    // ✅ FIX: If we already have AEDs loaded and this is a resume, skip cache loading
    if (isRefresh && currentState.aedList.isNotEmpty) {
      print("✅ AEDs already loaded (${currentState.aedList.length}), skipping cache reload");

      mapNotifier.setRefreshing(true);  // ✅ REMOVED duplicate declaration

      try {
        final aedRepository = ref.read(aedServiceProvider);
        final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: true);

        if (freshAEDs.isNotEmpty) {
          final sortedAEDs = aedRepository.sortAEDsByDistance(
            freshAEDs,
            currentState.userLocation,
            currentState.navigation.transportMode,
          );
          mapNotifier.setAEDs(sortedAEDs);
          print("✅ Refreshed ${sortedAEDs.length} AEDs");
        }
      } catch (e) {
        print("❌ Error refreshing AEDs: $e");
      } finally {
        mapNotifier.setRefreshing(false);
      }

      return;  // ✅ Exit early - don't continue to cache loading
    }

    // Original cache loading logic continues below...
    if (isRefresh) {
      mapNotifier.setRefreshing(true);
    } else {
      mapNotifier.setLoading(true);
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
    final userLocation = currentState.userLocation;

    if (userLocation == null || _routePreloader == null || _googleMapsApiKey == null) return;

    print("🚀 Starting route preloading for top 10 AEDs...");

    try {
      final sortedAEDs = currentState.aedList;

      if (sortedAEDs.isEmpty) {
        print("⚠️ No AEDs to preload");
        return;
      }

      final updatedAEDIds = <int>{};

      // ✅ Preload for BOTH transport modes
      for (final mode in ['walking', 'driving']) {
        print("🚀 Preloading routes for $mode mode...");

        await _routePreloader!.preloadRoutesForClosestAEDs(
          aeds: sortedAEDs,              // ✅ Named parameter
          userLocation: userLocation,     // ✅ Named parameter
          transportMode: mode,            // ✅ Named parameter
          onRouteLoaded: (originalAed, route) {
            if (mounted && route.actualDistance != null) {
              // Store in preloaded routes (use composite key with mode)
              final routeKey = '${originalAed.id}_$mode';
              _preloadedRoutes[routeKey] = route;
              _limitPreloadedRoutesSize();

              // ✅ Save with transport mode
              CacheService.setDistance('aed_${originalAed.id}_$mode', route.actualDistance!);

              updatedAEDIds.add(originalAed.id);

              print("✅ Cached route for AED ${originalAed.id} ($mode): ${route.distanceText}");
            }
          },
        );
      }

      // Save all cached distances
      await CacheService.saveDistanceCache();

      // If any routes were preloaded, trigger UI update
      if (updatedAEDIds.isNotEmpty && mounted) {
        setState(() {
          // Force rebuild to show new cached data
        });
      }
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

    // ✅ FIX: If using cached/stale location, get fresh HIGH accuracy fix first
    if (currentLocation != null && (_isUsingCachedLocation || isStale)) {
      print("⚠️ Using cached/stale location - getting fresh GPS fix before navigation...");

      try {
        // Show loading indicator
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
                  Text('Getting precise location...'),
                ],
              ),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
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
            ScaffoldMessenger.of(context).clearSnackBars();
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

    // ✅ CRITICAL: Cancel old stream IMMEDIATELY
    if (_positionSubscription != null) {
      _positionSubscription!.cancel();
      _positionSubscription = null;
      print("🛑 Cancelled old location stream");
    }

    // ✅ Wait a tiny bit for cleanup
    await Future.delayed(const Duration(milliseconds: 100));

    // ✅ Start fresh HIGH accuracy stream with NO distance filter
    _locationService.startProgressiveLocationTracking(
      onLocationUpdate: _updateUserLocation,
      isNavigating: true,  // ✅ HIGH accuracy
      distanceFilter: 0,   // ✅ Update EVERY time GPS reports new position
    );

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

      try {
        final routeService = RouteService(_googleMapsApiKey!);
        routeResult = await routeService.fetchRoute(
            currentLocation, aedLocation, currentState.navigation.transportMode
        );

        if (routeResult != null) {
          print("✅ Fresh route fetched: ${routeResult.distanceText} (${routeResult.duration})");

          CacheService.setCachedRoute(
              currentLocation, aedLocation,
              currentState.navigation.transportMode, routeResult
          );

          // Clear loading
          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
          }
        }
      } catch (e) {
        print("❌ Error fetching route: $e");

        // Clear loading indicator on error
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
        }
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

  void _cancelNavigation() {
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

    _isCurrentlyNavigating = false;

    // ✅ ADD THIS: Properly cancel and restart location stream
    _positionSubscription?.cancel();
    _positionSubscription = null;

    // Wait a bit before restarting to ensure clean transition
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted && !_isCurrentlyNavigating) {
        _locationService.startProgressiveLocationTracking(
          onLocationUpdate: _updateUserLocation,
          isNavigating: false,  // MEDIUM accuracy + 10m filter
          distanceFilter: 10,
        );
        print("🔋 GPS stream restarted in normal mode");
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

    // Resume location stream if paused
    if (_positionSubscription?.isPaused ?? false) {
      _positionSubscription?.resume();
      print("▶️ Resumed location stream");
    }

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
    final now = DateTime.now();
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

    print("✅ Resume complete");
  }

  void _pauseApp() async {
    print("⏸️ App paused - saving state");
    _lastBackgroundTime = DateTime.now();
    _positionSubscription?.pause();

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
      await CacheService.saveLastAppState(currentState);
      print("💾 Saved app state");
    }
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
                      mapNotifier.updateAEDsAndMarkers(improvedAEDs);
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
            if (currentState.navigation.destination != null &&
                currentState.userLocation != null) {

              if (currentState.navigation.hasStarted) {
                // ACTIVE NAVIGATION: Fetch new route
                print("🔄 Transport mode changed during navigation - recalculating route...");

                if (mounted) {
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.directions, color: Colors.white, size: 20),
                          const SizedBox(width: 12),
                          Text(
                            'Switched to ${mode == "walking" ? "walking" : "driving"} mode',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF194E9D),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }

                try {
                  final routeService = RouteService(_googleMapsApiKey!);
                  final newRoute = await routeService.fetchRoute(
                    currentState.userLocation!,
                    currentState.navigation.destination!,
                    mode,
                  );

                  if (newRoute != null && mounted) {
                    print("✅ New route fetched: ${newRoute.distanceText} (${newRoute.duration})");

                    final updatedState = ref.read(mapStateProvider);

                    // ✅ Parse the new duration
                    final newOriginalDurationMinutes = _parseDurationToMinutes(newRoute.duration);

                    ref.read(mapStateProvider.notifier).updateRoute(
                      newRoute.polyline,
                      newRoute.duration,
                      newRoute.actualDistance ?? LocationService.distanceBetween(
                        updatedState.userLocation!,
                        updatedState.navigation.destination!,
                      ),
                    );

                    // ✅ Update original metrics for new mode
                    ref.read(mapStateProvider.notifier).setOriginalRouteMetrics(
                      originalDistance: newRoute.actualDistance ?? 0,
                      originalDurationMinutes: newOriginalDurationMinutes,
                    );

                    CacheService.setCachedRoute(
                      updatedState.userLocation!,
                      updatedState.navigation.destination!,
                      mode,
                      newRoute,
                    );
                  }
                } catch (e) {
                  print("❌ Error fetching new route: $e");
                }

              } else if (currentState.navigation.isActive) {
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
    // Cancel all timers and subscriptions
    NetworkService.removeConnectivityListener(_onConnectivityChanged);
    NetworkService.stopConnectivityMonitoring();
    _positionSubscription?.cancel();
    _manualGPSSubscription?.cancel();
    _navigationController?.dispose();

    // ✅ OLD STATE CLEANUP
    _transportModeDebouncer?.cancel();
    _clusterUpdateDebouncer?.cancel();
    // Cleanup location service
    _locationService.dispose();
    LocationService.stopLocationServiceMonitoring();

    // Clear all caches
    _preloadedRoutes.clear();

    // Reset static variables
    _lastResortTime = null;

    _isGPSStreamActive = false;
    _lastRouteUpdateTime = null;
    _lastRouteUpdateLocation = null;
    _lastOffRouteBannerTime = null;

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