import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/network_service.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import '../widgets/aed_map_view.dart';



class AEDMapWidget extends StatefulWidget {
  const AEDMapWidget({super.key});

  @override
  _AEDMapWidgetState createState() => _AEDMapWidgetState();
}

class _AEDMapWidgetState extends State<AEDMapWidget> {
  Set<Marker> _aedMarkers = {};
  bool _isLoading = true;
  LatLng? _userLocation;
  GoogleMapController? _mapController;
  List<LatLng> _aedLocations = []; // List of AEDs for small maps
  Polyline? _navigationLine; // Route line from user to AED
  String? _googleMapsApiKey; // Store API key


  @override
  void initState() {
    super.initState();
    _initializeMap();
    _fetchGoogleMapsApiKey(); // ✅ Fetch API key once
  }

  void _initializeMapRenderer() {
    WidgetsFlutterBinding.ensureInitialized(); // ✅ Ensure Flutter is ready
    Future.delayed(Duration(milliseconds: 300), () { // ✅ Slight delay to ensure stability
      if (GoogleMapsFlutterPlatform.instance is GoogleMapsFlutterAndroid) {
        (GoogleMapsFlutterPlatform.instance as GoogleMapsFlutterAndroid).useAndroidViewSurface = true;
      }
    });
  }

  /// **🌍 Initialize Map**
  Future<void> _initializeMap() async {
    _initializeMapRenderer(); // ✅ Enable Hybrid Composition for Android

    await _fetchGoogleMapsApiKey(); // ✅ Ensure API Key is loaded before AED data
    if (_googleMapsApiKey == null) {
      print("❌ Google Maps API Key is missing. Cannot proceed.");
      return;
    }

    await _fetchUserLocation();
    await _fetchAEDLocations();

    // ✅ Ensure we update the map only when both user and AED locations are available
    if (_userLocation != null && _aedLocations.isNotEmpty) {
      _updateMapView();
    }
  }

  int _currentBatch = 3; // Number of AEDs to show initially

  void _updateBatch() {
    setState(() {
      if (_currentBatch + 3 <= _aedLocations.length) {
        _currentBatch += 3;
      } else {
        _currentBatch =
            _aedLocations.length; // Prevent exceeding the list length
      }
    });
  }

  Future<void> _fetchGoogleMapsApiKey() async {
    _googleMapsApiKey = await NetworkService.fetchGoogleMapsApiKey();
    if (_googleMapsApiKey == null) {
      print("❌ Failed to fetch Google Maps API Key.");
    }
  }

  /// **📍 Get User's Location**
  Future<void> _fetchUserLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        );

        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (error) {
      print("❌ Error getting user location: $error");
    }
  }

  /// **🗺️ Fetch AED Locations**
  Future<void> _fetchAEDLocations() async {
    try {
      List<dynamic> aeds = await NetworkService.fetchAEDLocations();
      print("✅ Fetched ${aeds.length} AEDs");

      Set<Marker> markers = {};
      List<LatLng> locations = [];

      for (var aed in aeds) {
        LatLng aedPosition = LatLng(aed["latitude"], aed["longitude"]);
        markers.add(
          Marker(
            markerId: MarkerId(aed["id"].toString()),
            position: aedPosition,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: aed["name"] ?? "AED Location",
              snippet: aed["address"] ?? "No address available",
            ),
          ),
        );
        locations.add(aedPosition);
      }

      // ✅ Sort locations from closest to furthest **immediately** when fetching
      if (_userLocation != null) {
        locations.sort((a, b) {
          double distanceA = Geolocator.distanceBetween(_userLocation!.latitude, _userLocation!.longitude, a.latitude, a.longitude);
          double distanceB = Geolocator.distanceBetween(_userLocation!.latitude, _userLocation!.longitude, b.latitude, b.longitude);
          return distanceA.compareTo(distanceB);
        });
      }

      setState(() {
        _aedMarkers = markers;
        _aedLocations = locations; // ✅ Ensure closest AEDs are first
        _isLoading = false;
      });

      _updateMapView(); // ✅ Update big map once sorted AEDs are available
    } catch (error) {
      print("❌ Error fetching AEDs: $error");
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// **🗺️ Update Map View to Show AEDs**
  void _updateMapView() {
    if (_userLocation == null || _aedLocations.isEmpty || _mapController == null) return;

    // ✅ Ensure at least two AEDs are included
    List<LatLng> includedPoints = [_userLocation!];
    int numAEDsToInclude = _aedLocations.length >= 2 ? 2 : 1;

    for (int i = 0; i < numAEDsToInclude && i < _aedLocations.length; i++) {
      includedPoints.add(_aedLocations[i]);
    }

    if (includedPoints.length < 2) {
      print("⚠ Not enough AEDs to adjust the map view.");
      return;
    }

    // ✅ Calculate exact bounds (remove excessive padding)
    double minLat = includedPoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = includedPoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = includedPoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = includedPoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // ✅ Move the camera **with minimal zoom-out, only just enough**
    Future.delayed(Duration(milliseconds: 300), () {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50)); // Reduced padding
    });
  }


  /// **📍 Handle Small Map Click**
  LatLng? _selectedAED; // Store selected AED for map update

  Future<void> _onSmallMapTap(LatLng aedLocation, {String mode = "walking"}) async {
    if (_userLocation == null) return; // Prevent crashes

    setState(() {
      _selectedAED = aedLocation;
    });

    // ✅ Fetch actual route from Google Directions API
    await _fetchRoute(_userLocation!, aedLocation, mode); // ✅ Mode now updates dynamically

    // ✅ Adjust the big map to fit both points **exactly** (no extra padding)
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        _userLocation!.latitude < aedLocation.latitude ? _userLocation!.latitude : aedLocation.latitude,
        _userLocation!.longitude < aedLocation.longitude ? _userLocation!.longitude : aedLocation.longitude,
      ),
      northeast: LatLng(
        _userLocation!.latitude > aedLocation.latitude ? _userLocation!.latitude : aedLocation.latitude,
        _userLocation!.longitude > aedLocation.longitude ? _userLocation!.longitude : aedLocation.longitude,
      ),
    );

    Future.delayed(Duration(milliseconds: 300), () {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 20)); // ✅ Less padding
    });
  }


  String _selectedMode = "walking"; // ✅ Track selected mode globally

  String _estimatedTime = "";

  Future<void> _fetchRoute(LatLng origin, LatLng destination, String mode) async {
    if (_googleMapsApiKey == null) {
      print("❌ Missing API Key.");
      return;
    }

    final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json?"
            "origin=${origin.latitude},${origin.longitude}"
            "&destination=${destination.latitude},${destination.longitude}"
            "&mode=$mode"
            "&key=$_googleMapsApiKey"
    );

    try {
      final response = await NetworkService.getExternal(url.toString());

      if (response != null && response['status'] == 'OK') {
        List<LatLng> routePoints = _decodePolyline(response["routes"][0]["overview_polyline"]["points"]);
        String durationText = response["routes"][0]["legs"][0]["duration"]["text"];

        setState(() {
          _estimatedTime = durationText; // ✅ Store estimated time first

          // ✅ Set navigation polyline first
          _navigationLine = Polyline(
            polylineId: PolylineId(mode),
            points: routePoints,
            color: _selectedMode == "driving" ? Colors.blue : Colors.green,
            width: 5,
          );

          // ✅ Remove previous estimated time marker before adding a new one
          _aedMarkers.removeWhere((marker) => marker.markerId.value == "route_info");

          // ✅ Add the estimated time marker dynamically
          _aedMarkers = Set.from(_aedMarkers)..add(
            Marker(
              markerId: const MarkerId("route_info"),
              position: routePoints[routePoints.length ~/ 2],  // ✅ Use midpoint
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
              infoWindow: InfoWindow(
                title: "⏳ $_estimatedTime",
                snippet: "ETA via $_selectedMode",
              ),
            ),
          );
        });

        // ✅ Auto-adjust zoom to fit route
        _adjustZoomToFitRoute(routePoints);
      } else {
        print("❌ Failed to fetch route.");
      }
    } catch (e) {
      print("❌ Error fetching route: $e");
    }
  }


  void _adjustZoomToFitRoute(List<LatLng> routePoints) {
    if (routePoints.isEmpty || _mapController == null) return;

    double minLat = routePoints.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    double maxLat = routePoints.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    double minLng = routePoints.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    double maxLng = routePoints.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // ✅ Ensure zoom adjustment happens before UI updates
    Future.delayed(Duration(milliseconds: 300), () {
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80)); // ✅ Adjusted zoom to fit route
    });
  }


  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polylinePoints = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polylinePoints.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polylinePoints;
  }


  /// **🚗 Open Navigation to AED**
  void _startNavigation(LatLng aedLocation) async {
    final Uri googleMapsUri = Uri.parse(
      "https://www.google.com/maps/dir/?api=1&origin=${_userLocation!
          .latitude},${_userLocation!.longitude}&destination=${aedLocation
          .latitude},${aedLocation.longitude}&travelmode=walking",
    );

    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri);
    } else {
      print("❌ Could not launch Google Maps");
    }
  }

// Replace your previous `build()` method with:
  @override
  Widget build(BuildContext context) {
    return AEDMapDisplay(
      isLoading: _isLoading,
      aedMarkers: _aedMarkers,
      userLocation: _userLocation,
      mapController: _mapController,
      navigationLine: _navigationLine,
      estimatedTime: _estimatedTime,
      selectedAED: _selectedAED,
      aedLocations: _aedLocations,
      currentBatch: _currentBatch,
      selectedMode: _selectedMode,
      onSmallMapTap: _onSmallMapTap,
      onStartNavigation: _startNavigation,
      onTransportModeSelected: (mode) {
        setState(() {
          _selectedMode = mode;
        });
        if (_selectedAED != null) {
          _fetchRoute(_userLocation!, _selectedAED!, mode);
        }
      },
      onBatchUpdate: _updateBatch,
      googleMapsApiKey: _googleMapsApiKey,
    );
  }
}