import 'dart:async';
import 'package:cpr_assist/services/aed_map/aed_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/aed_models.dart';
import '../../utils/app_constants.dart';
import '../../utils/safe_fonts.dart';
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
  bool _isPerformingInitialZoom = false;
  DateTime? _lastResortTime;
  Timer? _transportModeDebouncer;
  Timer? _improvementTimer;
  nav.NavigationController? _navigationController;
  RoutePreloader? _routePreloader;
  DateTime? _lastBackgroundImprovement;
  DateTime? _lastCloserAEDNotification;
  final bool _hasShownOfflineDialog = false;
  DateTime? _locationLastUpdated;
  bool _isUsingCachedLocation = false;
  bool _isManuallySearchingGPS = false;
  bool _gpsSearchSuccess = false;
  StreamSubscription<Position>? _manualGPSSubscription;



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
    SafeFonts.initializeFontCache();
    await CacheService.initializeAllCaches();

    // Check location availability first
    final isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    final hasLocationPermission = await _locationService.hasPermission;
    final hasLocation = isLocationEnabled && hasLocationPermission;

    print("🔍 Location enabled: $isLocationEnabled");
    print("🔍 Has permission: $hasLocationPermission");
    print("🔍 Has location: $hasLocation");

    // Check internet connectivity
    final isConnected = await NetworkService.isConnected();

    // Initialize navigation controller
    _navigationController = nav.NavigationController(
      onStateChanged: () => setState(() {}),
      onRecenterButtonVisibilityChanged: (visible) => setState(() {}),
    );

    if (hasLocation) {
      print("🔍 [INIT] Has location - starting flow");
      await _mapReadyCompleter.future;
      print("🔍 [INIT] Map ready completed");

      // Load AEDs immediately
      if (isConnected) {
        print("🔍 [INIT] Starting _loadFreshDataWithRoutes");
        await _loadFreshDataWithRoutes();
        print("🔍 [INIT] _loadFreshDataWithRoutes completed");
      } else {
        print("🔍 [INIT] Starting _loadCachedDataWithEstimations");
        await _loadCachedDataWithEstimations();
        print("🔍 [INIT] _loadCachedDataWithEstimations completed");
      }

      print("🔍 [INIT] Starting background location setup (no await)");
      // Start location acquisition in background (don't await - fire and forget)
      _tryInitialLocationSetup().then((location) {
        print("🔍 [INIT] Background location callback: $location");
        if (location != null) {
          print("✅ Location acquired in background");
        }
      });
      print("🔍 [INIT] Initialization complete - UI should be responsive");
    }else {
      // No location permission
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
        if (isConnected) {
          await _fetchAEDsWithPriority(isRefresh: true);
        }
      } else {
        // ✅ ADD THIS: User declined location - show Greece view
        print("❌ User declined location - showing Greece view");
        await _mapViewController?.showDefaultGreeceView();
        setState(() => _isLocationAvailable = false);

        // Still fetch AEDs if connected (just without user location)
        if (isConnected) {
          await _fetchAEDsWithPriority(isRefresh: true);
        }
      }
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

    Future.delayed(const Duration(milliseconds: 100), () {
      _navigationController?.initialize(controller);
      print("✅ NavigationController initialized with map controller");
    });


    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.complete();
    }
    await _loadCachedMapView();
  }

  Future<void> _loadFreshDataWithRoutes() async {
    await _fetchGoogleMapsApiKey();
    await _fetchAEDsWithPriority(isRefresh: true);

    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null && _googleMapsApiKey != null) {
      // Preload actual routes for closest AEDs
      _preloadActualRoutes(currentState.userLocation!, currentState.aedList);
    }
  }

  Future<void> _loadCachedDataWithEstimations() async {
    await _fetchAEDsWithPriority(isRefresh: false);

    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null) {
      // Show distance/time estimations without route lines
      _calculateEstimationsForAEDs(currentState.userLocation!, currentState.aedList);
    }
  }

  Future<LatLng?> _tryInitialLocationSetup() async {
    print("🔍 [LOCATION] _tryInitialLocationSetup called");

    final hasPermission = await _locationService.hasPermission;
    print("🔍 [LOCATION] Has permission: $hasPermission");

    if (!hasPermission) {
      print("❌ [LOCATION] No location permission");
      await _mapViewController?.showDefaultGreeceView();
      setState(() => _isLocationAvailable = false);
      return null;
    }

    // Load cached location FIRST (instant)
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

        print("📍 [LOCATION] Using cached location: $cachedLocation (age: ${_locationLastUpdated != null ? DateTime.now().difference(_locationLastUpdated!).inMinutes : '?'} min)");
        _updateUserLocation(cachedLocation, fromCache: true);  // ← Add parameter
      }
    }

    print("🔍 [LOCATION] Starting location stream in background (non-blocking)");
    setState(() => _isLocationAvailable = true);

    // Start stream in background - this will update when GPS gets a fix
    Future.delayed(Duration.zero, () {
      _locationService.startLocationTracking(
        onLocationUpdate: (location) {
          print("✅ [LOCATION] Got GPS location: $location");
          _updateUserLocation(location);  // ← No parameter = fresh location
          if (!_hasPerformedInitialZoom) {
            _performInitialZoomIfReady();
          }
        },
        distanceFilter: AppConstants.locationDistanceFilterHigh,
      );
    });

    return null;
  }

  void _startLowAccuracyLocationStream() {
    // Defer stream creation to next frame to avoid blocking
    Future.delayed(Duration.zero, () {
      print("🔍 [LOCATION] Creating position stream on next frame");

      _locationService.getPositionStream(distanceFilter: 50)
          .listen(
            (position) {
          final location = LatLng(position.latitude, position.longitude);
          print("✅ [LOCATION] Got location: $location");

          _updateUserLocation(location);

          if (!_hasPerformedInitialZoom) {
            _performInitialZoomIfReady();
          }

          // Upgrade to high accuracy after first fix
          Future.delayed(const Duration(seconds: 2), () {
            print("🔍 [LOCATION] Upgrading to high accuracy");
            _locationService.startLocationTracking(
              onLocationUpdate: _updateUserLocation,
              distanceFilter: AppConstants.locationDistanceFilterHigh,
            );
          });
        },
        cancelOnError: false,
      );
    });
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

  Future<void> _preloadActualRoutes(LatLng userLocation, List<AED> aeds) async {
    if (aeds.isEmpty || _googleMapsApiKey == null) return;

    final closestAEDs = aeds.take(5).toList();

    for (final aed in closestAEDs) {
      // Preload both walking and driving routes
      for (final mode in ['walking', 'driving']) {
        try {
          final routeService = RouteService(_googleMapsApiKey!);
          final route = await routeService.fetchRoute(userLocation, aed.location, mode);

          if (route != null) {
            // Cache the route
            CacheService.setCachedRoute(userLocation, aed.location, mode, route);
            // Cache the distance
            if (route.actualDistance != null) {
              CacheService.setDistance('aed_${aed.id}', route.actualDistance!);
            }
          }

          await Future.delayed(const Duration(milliseconds: 500)); // Rate limiting
        } catch (e) {
          print("❌ Error preloading $mode route for AED ${aed.id}: $e");
        }
      }
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

  void _calculateEstimationsForAEDs(LatLng userLocation, List<AED> aeds) {
    for (final aed in aeds) {
      // Calculate walking estimation
      final walkingDistance = AEDService.calculateEstimatedDistance(userLocation, aed.location, 'walking');
      final walkingTime = LocationService.calculateOfflineETA(walkingDistance, 'walking');

      // Calculate driving estimation
      final drivingDistance = AEDService.calculateEstimatedDistance(userLocation, aed.location, 'driving');
      final drivingTime = LocationService.calculateOfflineETA(drivingDistance, 'driving');

      // Cache these estimations
      CacheService.setDistance('aed_${aed.id}_walking_est', walkingDistance);
      CacheService.setDistance('aed_${aed.id}_driving_est', drivingDistance);

      print("📏 AED ${aed.id}: Walking ${LocationService.formatDistance(walkingDistance)} ($walkingTime), Driving ${LocationService.formatDistance(drivingDistance)} ($drivingTime)");
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

      // Try initial zoom if we haven't zoomed yet
      if (!_hasPerformedInitialZoom && currentState.aedList.isNotEmpty && _mapViewController != null) {
        print("🎯 Performing initial zoom from first location update");
        Future.delayed(AppConstants.zoomAnimationDelay, () async {
          if (mounted && _mapViewController != null) {
            await _mapViewController?.zoomToUserAndClosestAEDs(
              location,
              currentState.aedList.map((aed) => aed.location).toList(),
            );
            _hasPerformedInitialZoom = true;
          }
        });
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
    _navigationController?.onCameraMoveStarted();
  }

  void _onCameraMoved() {
    _navigationController?.onCameraMoved();
  }

  void _onCameraIdle() {
    // Keep empty or add custom logic
  }


  void _recenterNavigation() {
    final currentState = ref.read(mapStateProvider);
    if (currentState.userLocation != null) {
      _navigationController?.recenterAndResumeTracking(currentState.userLocation!);
    }
  }

  /// Recenters the map to show both the user's current location and nearby AEDs.
  Future<void> _recenterMapToUserAndAEDs({bool allowLocationPrompt = false}) async {
    final currentState = ref.read(mapStateProvider);

    // 1. If in compass-only navigation (no location), zoom to AED
    if (currentState.navigation.hasStarted &&
        currentState.navigation.destination != null &&
        currentState.userLocation == null) {
      if (_mapViewController != null) {
        await _mapViewController!.zoomToAED(currentState.navigation.destination!);
      }
      return;
    }

    // 2. Check if we have location and if it's usable
    if (currentState.userLocation != null && _mapViewController != null) {
      final isTooOld = _isLocationTooOld();

      if (isTooOld) {
        // Location is too old (>5 hours) - show general city view
        print("📍 Location too old - showing city view");
        await _mapViewController!.showDefaultGreeceView();
        return;
      }

      // Location is fresh or stale but usable (<5 hours) - zoom to user + 2 closest AEDs
      final closestAEDs = currentState.aedList.take(2).map((aed) => aed.location).toList();
      await _mapViewController!.zoomToUserAndClosestAEDs(
        currentState.userLocation!,
        closestAEDs,
      );
      return;
    }

    // 3. No location - try to get it if allowed
    if (allowLocationPrompt) {
      final userLocation = await _locationService.getCurrentLocationWithUI(
        context: context,
        showPermissionDialog: true,
        showErrorMessages: true,
      );

      if (userLocation != null) {
        _updateUserLocation(userLocation);

        if (_mapViewController != null) {
          final closestAEDs = currentState.aedList.take(2).map((aed) => aed.location).toList();
          await _mapViewController!.zoomToUserAndClosestAEDs(
            userLocation,
            closestAEDs,
          );
        }
        return;
      }
    }

    // 4. Fallback: show Greece view with all AEDs
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
          final cachedAEDList = aedRepository.convertToAEDList(cachedAEDs);

          if (cachedAEDList.isNotEmpty) {
            print("📦 Showing cached AEDs immediately (${cachedAEDList.length} AEDs)");

            final currentState = ref.read(mapStateProvider);
            final userLocation = currentState.userLocation;

            List<AED> sortedCachedAEDs;

            if (userLocation != null) {
              // 🔥 CRITICAL FIX: Calculate estimated distances for cached AEDs
              for (final aed in cachedAEDList) {
                final straightDistance = LocationService.distanceBetween(userLocation, aed.location);
                final multiplier = AEDService.getTransportModeMultiplier(currentState.navigation.transportMode);
                final estimatedDistance = straightDistance * multiplier;
                CacheService.setDistance('aed_${aed.id}', estimatedDistance);
              }

              sortedCachedAEDs = aedRepository.sortAEDsByDistance(
                  cachedAEDList,
                  userLocation,
                  currentState.navigation.transportMode
              );

              print("📏 Applied estimated distances to ${cachedAEDList.length} cached AEDs");
            } else {
              sortedCachedAEDs = cachedAEDList;
            }

            final cachedMarkers = aedRepository.createMarkers(
              sortedCachedAEDs,
              _showNavigationPreviewForAED,
            );
            mapNotifier.setAEDs(sortedCachedAEDs, cachedMarkers);
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
        _fetchFreshAEDsInBackground(aedRepository, isRefresh);
      }

    } catch (error) {
      print("❌ Error in priority AED loading: $error");
    } finally {
      mapNotifier.setRefreshing(false);
      mapNotifier.setLoading(false);
    }
  }

  /// Fetches fresh AEDs in background without blocking UI
  Future<void> _fetchFreshAEDsInBackground(AEDService aedRepository, bool isRefresh) async {
    try {
      print("🔄 Fetching fresh AEDs in background...");

      await Future.delayed(Duration.zero);

      final freshAEDs = await aedRepository.fetchAEDs(forceRefresh: isRefresh);

      // Only update if we got different/better data
      final currentState = ref.read(mapStateProvider);
      final currentAEDCount = currentState.aedList.length;

      // PREVENT DUPLICATE SAVES: Don't update if we have the same data and it's not a forced refresh
      if (freshAEDs.length != currentAEDCount || (isRefresh && currentAEDCount == 0)) {
        print("✅ Background AED update complete (${freshAEDs.length} AEDs)");

        final userLocation = currentState.userLocation;
        final sortedFreshAEDs = userLocation != null
            ? aedRepository.sortAEDsByDistance(freshAEDs, userLocation, currentState.navigation.transportMode)
            : freshAEDs;

        final freshMarkers = aedRepository.createMarkers(
          sortedFreshAEDs,
          _showNavigationPreviewForAED,
        );

        if (mounted) {
          final mapNotifier = ref.read(mapStateProvider.notifier);
          mapNotifier.setAEDs(sortedFreshAEDs, freshMarkers);
          _triggerInitialZoomIfReady();
        }

        // Start background improvements (non-blocking)
        if (userLocation != null && _googleMapsApiKey != null) {
          _startBackgroundImprovements(aedRepository, sortedFreshAEDs, userLocation);
        }
      } else {
        print("✅ Fresh AEDs same as cached - no update needed");
      }
    } catch (error) {
      print("⚠️ Background AED fetch failed: $error");
    }
  }

  /// Starts background improvements without affecting UI
  void _startBackgroundImprovements(AEDService aedRepository, List<AED> aeds, LatLng userLocation) {
    // Throttle background improvements to prevent main thread blocking
    final now = DateTime.now();
    if (_lastBackgroundImprovement != null &&
        now.difference(_lastBackgroundImprovement!).inMinutes < 5)  {
      print("⚠️ Skipping background improvements - too recent");
      return; // Skip if we did this less than 30 seconds ago
    }
    _lastBackgroundImprovement = now;

    final currentState = ref.read(mapStateProvider);

    // Start background distance accuracy improvement
    aedRepository.improveDistanceAccuracyInBackground(
      aeds,
      userLocation,
      currentState.navigation.transportMode,
      _googleMapsApiKey,
          (improvedAEDs) {
        if (mounted) {
          final improvedMarkers = aedRepository.createMarkers(improvedAEDs, _showNavigationPreviewForAED);
          final mapNotifier = ref.read(mapStateProvider.notifier);
          mapNotifier.updateAEDsAndMarkers(improvedAEDs, improvedMarkers);
        }
      },
    );

    // Schedule route preloading
    _scheduleRoutePreloading();
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
      final markers = aedRepository.createMarkers(newSorted, _showNavigationPreviewForAED);
      final mapNotifier = ref.read(mapStateProvider.notifier);
      mapNotifier.updateAEDsAndMarkers(newSorted, markers);
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

  /// Triggers zoom if we have both location and AEDs but haven't zoomed yet
  void _triggerInitialZoomIfReady() {
    final currentState = ref.read(mapStateProvider);
    if (_isPerformingInitialZoom || _hasPerformedInitialZoom ||
        currentState.userLocation == null || currentState.aedList.isEmpty ||
        _mapViewController == null) {
      return;
    }

    _isPerformingInitialZoom = true; // Prevent concurrent calls
    print("🎯 Triggering initial zoom");

    Future.delayed(const Duration(milliseconds: 300), () async {
      if (mounted && !_hasPerformedInitialZoom) {
        await _mapViewController?.zoomToUserAndClosestAEDs(
          currentState.userLocation!,
          currentState.aedList.map((aed) => aed.location).toList(),
        );
        _hasPerformedInitialZoom = true;
      }
      _isPerformingInitialZoom = false;
    });
  }


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
      orElse: () => AED(id: -1, name: '', address: '', location: aedLocation),
    );

    final isStale = _isLocationStale();
    final isTooOld = _isLocationTooOld();

    if (!isTooOld && !currentState.isOffline && _googleMapsApiKey != null) {
      Future.delayed(Duration.zero, () {
        _preloadBothTransportModes(currentLocation, aedLocation);
      });
    }

    RouteResult? routeResult;

// Try exact cache match first, then nearby cache
    routeResult = CacheService.getCachedRoute(
        currentLocation, aedLocation, currentState.navigation.transportMode
    );

// If no exact match, try nearby cached routes (within 1km)
    routeResult ??= CacheService.getCachedRouteNearby(
        currentLocation,
        aedLocation,
        currentState.navigation.transportMode,
        maxDistanceMeters: 1000, // 1km proximity
      );

// If no cached route and location is fresh and online, fetch new route
    if (routeResult == null && !isStale && _googleMapsApiKey != null && !currentState.isOffline) {
      final routeService = RouteService(_googleMapsApiKey!);
      routeResult = await routeService.fetchRoute(
          currentLocation, aedLocation, currentState.navigation.transportMode
      );

      if (routeResult != null) {
        CacheService.setCachedRoute(
            currentLocation, aedLocation,
            currentState.navigation.transportMode, routeResult
        );
        if (routeResult.actualDistance != null) {
          CacheService.setDistance('aed_${aed.id}', routeResult.actualDistance!);
        }
      }
    }

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
        final markers = aedRepository.createMarkers(newAEDs, _showNavigationPreviewForAED);
        final mapNotifier = ref.read(mapStateProvider.notifier);
        mapNotifier.updateAEDsAndMarkers(newAEDs, markers);
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
        aedMarkers: mapState.markers,
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
          final currentState = ref.read(mapStateProvider);

          // 1. Update transport mode in state
          mapNotifier.updateTransportMode(mode);
          _preloadedRoutes.clear();

          // 2. Re-sort AEDs (this is widget-specific, not navigation-specific)
          if (currentState.userLocation != null) {
            final aedRepository = ref.read(aedServiceProvider);
            final resorted = aedRepository.sortAEDsByDistance(
                currentState.aedList,
                currentState.userLocation!,
                mode
            );
            final markers = aedRepository.createMarkers(resorted, _showNavigationPreviewForAED);
            mapNotifier.updateAEDsAndMarkers(resorted, markers);

            // Background improvements (non-blocking)
            if (_googleMapsApiKey != null) {
              aedRepository.improveDistanceAccuracyInBackground(
                resorted,
                currentState.userLocation!,
                mode,
                _googleMapsApiKey,
                    (improvedAEDs) {
                  if (mounted) {
                    final improvedMarkers = aedRepository.createMarkers(improvedAEDs, _showNavigationPreviewForAED);
                    mapNotifier.updateAEDsAndMarkers(improvedAEDs, improvedMarkers);
                  }
                },
              );
            }
            _scheduleRoutePreloading();
          }

          // 3. Update navigation route ONLY if we're actively navigating
          if (currentState.navigation.hasStarted &&
              currentState.navigation.destination != null &&
              currentState.userLocation != null) {
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