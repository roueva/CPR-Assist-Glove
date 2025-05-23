import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/aed.dart';
import '../network_service.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'aed_map_display.dart';
import 'aed_map_services.dart';
import '../../utils/map_utils.dart';
import 'package:flutter_compass/flutter_compass.dart';

// Main widget
class AEDMapWidget extends StatefulWidget {
  const AEDMapWidget({super.key});

  @override
  _AEDMapWidgetState createState() => _AEDMapWidgetState();
}

class _AEDMapWidgetState extends State<AEDMapWidget> with WidgetsBindingObserver {
  AEDMapState _state = const AEDMapState(
    navigation: NavigationState(), // Initialize navigation state
  );
  GoogleMapController? _mapController;
  bool _mapIsReady = false;
  String? _googleMapsApiKey;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSubscription;
  final Completer<void> _mapReadyCompleter = Completer<void>();
  double? _currentHeading; // User's compass direction
  StreamSubscription<CompassEvent>? _compassSubscription;
  MapViewController? _mapViewController;   // Map animation controller
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;  // Location service status subscription
  bool _isLocationAvailable = true;
  List<AED> _lastFetchedAEDs = [];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeMapRenderer();

    // Delay the prompt slightly for better UX
    Future.delayed(const Duration(milliseconds: 500), _initializeApp);
  }

  // Updated initialization flow
  Future<void> _initializeApp() async {
    setState(() => _state = _state.copyWith(isLoading: true));

    try {
      // 1. Load resources first
      await Future.wait([
        _fetchGoogleMapsApiKey(),
        _waitForMapReady(),
        _fetchAEDLocations(),
      ]);

    } finally {
      setState(() => _state = _state.copyWith(isLoading: false));
    }
  }


  void _initializeMapRenderer() {
    if (GoogleMapsFlutterPlatform.instance is GoogleMapsFlutterAndroid) {
      (GoogleMapsFlutterPlatform.instance as GoogleMapsFlutterAndroid)
          .useAndroidViewSurface = true;
    }
  }

  Future<void> _fetchGoogleMapsApiKey() async {
    _googleMapsApiKey = await NetworkService.fetchGoogleMapsApiKey();
    if (_googleMapsApiKey == null) {
      print("❌ Failed to fetch Google Maps API Key.");
    }
  }

  Future<void> _waitForMapReady() {
    if (_mapIsReady) {
      return Future.value();
    }
    // Use a timeout to avoid blocking forever
    return _mapReadyCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        print("⚠️ Map ready timeout");
        // If map isn't ready after timeout, proceed anyway
        if (!_mapReadyCompleter.isCompleted) {
          _mapReadyCompleter.complete();
        }
      },
    );
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    _mapViewController = MapViewController(controller, context); // Pass context here
    _mapIsReady = true;

    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.complete();
    }

    // 🛰️ Now delay location request
    Future.delayed(const Duration(milliseconds: 300), () async {
      final currentLocation = await _locationService.getCurrentLatLng();
      if (currentLocation != null) {
        _updateUserLocation(currentLocation);

        _positionSubscription = _locationService.listenToPositionUpdates(
          _updateUserLocation,
          distanceFilter: 10,
        );

        await _mapViewController?.zoomToUserAndClosestAEDs(
          currentLocation,
          _state.aedList.map((aed) => aed.location).toList(),
        );
      } else {
        await _mapViewController?.showDefaultGreeceView();
      }
    });
  }


// In _updateUserLocation method:
  void _updateUserLocation(LatLng location) {
    final LatLng? previousLocation = _state.userLocation;
    setState(() {
      _state = _state.copyWith(userLocation: location);
      _isLocationAvailable = true;
    });
    if (_state.navigation.isActive && _currentHeading != null) {
      _animateCameraToUserWithHeading(location, _currentHeading!);
    }

    if (previousLocation == null) {
      _resortAEDs();
      return;
    }

    final distance = LocationService.distanceBetween(previousLocation, location);
    if (distance > 10) {
      _resortAEDs();

      // ✅ Only enable navigation camera if real navigation has started
      if (_state.aedList.isNotEmpty && _state.navigation.hasStarted) {
        _mapViewController?.enableNavigationMode(
          _state.userLocation!,
          _currentHeading,
        );
      }
    }
  }

  Future<void> _fetchAEDLocations({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() => _state = _state.copyWith(isRefreshing: true));
    } else {
      setState(() => _state = _state.copyWith(isLoading: true));
    }

    try {
      final aedRepository = AEDRepository();
      final aeds = await aedRepository.fetchAEDs(forceRefresh: isRefresh);

      _lastFetchedAEDs = aeds; // ✅ Store latest

      final userLocation = _state.userLocation;
      final sortedAEDs = userLocation != null
          ? aedRepository.sortAEDsByDistance(aeds, userLocation)
          : aeds;
      final markers = aedRepository.createMarkers(
        sortedAEDs,
        _showNavigationPreviewForAED, // ✅ Preview only
      );

      setState(() {
        _state = _state.copyWith(
          aedList: sortedAEDs,
          markers: markers,
          isLoading: false,
          isRefreshing: false,
        );
      });
    } catch (error) {
      print("❌ Error fetching AEDs: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to fetch AED locations.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _state = _state.copyWith(
            isLoading: false,
            isRefreshing: false,
          );
        });
      }
    }
  }

  void _resortAEDs() {
    if (_state.userLocation == null) return;

    final aedRepository = AEDRepository();
    final sorted = aedRepository.sortAEDsByDistance(_state.aedList, _state.userLocation);

    setState(() {
      _state = _state.copyWith(aedList: sorted);
    });
  }

  Future<void> _showNavigationPreviewForAED(LatLng aedLocation) async {
    final currentLocation = await _locationService.getCurrentLatLng();
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get current location')),
      );
      return;
    }

    setState(() {
      _state = _state.copyWith(
        navigation: _state.navigation.copyWith(
          isActive: true,
          destination: aedLocation,
          route: null,
          estimatedTime: '',
          distance: null,
          hasStarted: false,
        ),
      );
    });

    // ✅ FIX: Add this line to actually fetch the route
    final routeResult = await _calculateRoute(
      currentLocation,
      aedLocation,
      _state.navigation.transportMode,
    );

    if (routeResult != null) {
      setState(() {
        _state = _state.copyWith(
          navigation: _state.navigation.copyWith(
            route: routeResult.polyline,
            estimatedTime: routeResult.duration,
            distance: LocationService.distanceBetween(currentLocation, aedLocation),
          ),
        );
      });

      await _mapViewController?.zoomToUserAndAED(
        userLocation: currentLocation,
        aedLocation: aedLocation,
        polylinePoints: routeResult.points,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not generate route')),
      );
    }
  }


  Future<RouteResult?> _calculateRoute(LatLng origin, LatLng destination, String mode) async {
    if (!_mapIsReady || _mapController == null || !mounted) return null;

    final routeService = RouteService(_googleMapsApiKey ?? '');
    return await routeService.fetchRoute(origin, destination, mode);
  }

  void _startNavigation(LatLng aedLocation) async {
    if (!await _locationService.hasPermission &&
        !await _locationService.requestPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required')));
      return;
    }

    final currentLocation = await _locationService.getCurrentLatLng();
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')));
      return;
    }

    _compassSubscription?.cancel(); // prevent duplicates
    _compassSubscription = FlutterCompass.events?.listen((event) {
      _currentHeading = event.heading;
      if (_state.navigation.isActive && _state.userLocation != null) {
        _animateCameraToUserWithHeading(_state.userLocation!, _currentHeading!);
      }
    });


    setState(() {
      _state = _state.copyWith(
        navigation: _state.navigation.copyWith(
          isActive: true,
          destination: aedLocation,
          hasStarted: true,
        ),
      );
    });

    final routeResult = await _calculateRoute(
      currentLocation,
      aedLocation,
      _state.navigation.transportMode,
    );

    if (routeResult != null) {
      final distance = LocationService.distanceBetween(currentLocation, aedLocation);

      setState(() {
        _state = _state.copyWith(
          navigation: _state.navigation.copyWith(
            route: routeResult.polyline,
            estimatedTime: routeResult.duration,
            distance: distance,
          ),
        );
      });

      await _mapViewController?.zoomToUserAndAED(
        userLocation: currentLocation,
        aedLocation: aedLocation,
        polylinePoints: routeResult.points,
      );
    }
  }

  void _animateCameraToUserWithHeading(LatLng location, double heading) {
    _mapController?.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: location,
          zoom: 17.5,       // Not max zoom, feels a little softer
          tilt: 45.0,       // Enough for perspective without extreme angle
          bearing: heading, // Use compass heading for direction
        ),
      ),
    );
  }

  void _cancelNavigation() {
    _compassSubscription?.cancel();
    _positionSubscription?.cancel();
    _positionSubscription = _locationService.listenToPositionUpdates(
      _updateUserLocation,
      distanceFilter: 10,
    );

    setState(() {
      _state = _state.copyWith(
        navigation: const NavigationState(),
      );
    });

    if (_state.userLocation != null) {
      _mapViewController?.zoomToUserAndClosestAEDs(
        _state.userLocation!,
        _state.aedList.map((aed) => aed.location).toList(),
      );
    } else {
      _mapViewController?.showDefaultGreeceView();
    }
  }


  void _openExternalNavigation(LatLng destination) async {
    if (_state.userLocation == null) return;

    // Convert the transport mode to match Google Maps expectations
    final String googleMapsMode = _state.navigation.transportMode == 'walking' ? 'walking' :
    _state.navigation.transportMode == 'bicycling' ? 'bicycling' : 'driving';

    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=${_state.userLocation!.latitude},${_state.userLocation!.longitude}&destination=${destination.latitude},${destination.longitude}&travelmode=$googleMapsMode'
    );

    try {
      // Use url_launcher to open external maps app
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      } else {
        throw 'Could not launch maps app';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open external navigation'))
        );
      }
    }
  }


  void _recenterMapToUserAndAEDs() async {
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isServiceEnabled) {
      // 🛰️ No location service available!
      final granted = await _locationService.requestPermission();
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission required')),
        );
        return;
      }
      // Permission granted: get fresh location
    }

    final position = await _locationService.getCurrentPosition();
    if (position == null) {
      await _mapViewController?.showDefaultGreeceView();
      return;
    }

    _updateUserLocation(LatLng(position.latitude, position.longitude));

    await _mapViewController?.zoomToUserAndClosestAEDs(
      _state.userLocation!,
      _state.aedList.map((aed) => aed.location).toList(),
    );
  }


  void _updateBatch() {
    final int totalAEDs = _state.aedList.length;
    final int newBatch = _state.currentBatch + 3 <= totalAEDs
        ? _state.currentBatch + 3
        : totalAEDs;

    setState(() {
      _state = _state.copyWith(currentBatch: newBatch);
    });
  }


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

    // 🛰️ Check if GPS is available
    final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    setState(() {
      _isLocationAvailable = isServiceEnabled;
    });

    // 👇 New silent AED refresh logic
    final aedRepository = AEDRepository();
    final newAEDs = await aedRepository.fetchAEDs(forceRefresh: true);
    final changed = aedRepository.haveAEDsChanged(_lastFetchedAEDs, newAEDs);

    if (changed) {
      _lastFetchedAEDs = newAEDs; // ✅ Update the cache
      final markers = aedRepository.createMarkers(newAEDs, _startNavigation);
      setState(() {
        _state = _state.copyWith(
          aedList: newAEDs,
          markers: markers,
        );
      });
    }
  }


  void _pauseApp() {
    // Pause location updates to save battery
    _positionSubscription?.pause();
  }

  @override
  Widget build(BuildContext context) {
    return AEDMapDisplay(
      config: AEDMapConfig(
        isLoading: _state.isLoading,
        aedMarkers: _state.markers,
        userLocation: _state.userLocation,
        userLocationAvailable: _isLocationAvailable,
        mapController: _mapController,
        navigationLine: _state.navigation.route,
        estimatedTime: _state.navigation.estimatedTime,
        selectedAED: _state.navigation.destination,
        aedLocations: _state.aedList.map((aed) => aed.location).toList(),
        currentBatch: _state.currentBatch,
        selectedMode: _state.navigation.transportMode,
        aeds: _state.aedList,
        isRefreshingAEDs: _state.isRefreshing,
        hasSelectedRoute: _state.navigation.isActive,
        navigationMode: _state.navigation.isActive,
        distance: _state.navigation.distance,
      ),
      onSmallMapTap: _showNavigationPreviewForAED,
      onPreviewNavigation: _showNavigationPreviewForAED,
      userLocationAvailable: _isLocationAvailable,
      onStartNavigation: _startNavigation,
      onTransportModeSelected: (mode) {
        setState(() {
          _state = _state.copyWith(
              navigation: _state.navigation.copyWith(transportMode: mode)
          );
        });
        if (_state.navigation.isActive &&
            _state.navigation.destination != null &&
            _state.userLocation != null) {
          _calculateRoute(_state.userLocation!, _state.navigation.destination!, mode).then((routeResult) {
            if (routeResult != null) {
              setState(() {
                _state = _state.copyWith(
                  navigation: _state.navigation.copyWith(
                    route: routeResult.polyline,
                    estimatedTime: routeResult.duration,
                    distance: LocationService.distanceBetween(
                      _state.userLocation!,
                      _state.navigation.destination!,
                    ),
                  ),
                );
              });

              _mapViewController?.zoomToUserAndAED(
                userLocation: _state.userLocation!,
                aedLocation: _state.navigation.destination!,
                polylinePoints: routeResult.points,
              );
            }
          });
        }
      },
      onRecenterPressed: _recenterMapToUserAndAEDs,
      onBatchUpdate: _updateBatch,
      onMapCreated: _onMapCreated,
      onCancelNavigation: _cancelNavigation,
      onExternalNavigation: _openExternalNavigation,
    );
  }


  @override
  void dispose() {
    _positionSubscription?.cancel();
    _compassSubscription?.cancel();
    _serviceStatusSubscription?.cancel();
    _mapController?.dispose();
    if (!_mapReadyCompleter.isCompleted) {
      _mapReadyCompleter.completeError("Widget disposed");
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}