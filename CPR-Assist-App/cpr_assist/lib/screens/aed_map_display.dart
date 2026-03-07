import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/aed_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback, rootBundle;

import '../services/aed_map/aed_service.dart';
import '../services/aed_map/cache_service.dart';
import '../services/aed_map/location_service.dart';
import '../services/aed_map/route_service.dart';
import '../services/network_service.dart';
import '../utils/app_constants.dart';
import '../utils/availability_parser.dart';
import '../utils/safe_fonts.dart';
import 'aed_webview_screen.dart';

class AEDMapConfig {
  final bool isLoading;
  final Set<Marker> aedMarkers;
  final LatLng? userLocation;
  final bool userLocationAvailable;
  final GoogleMapController? mapController;
  final Polyline? navigationLine;
  final String estimatedTime;
  final LatLng? selectedAED;
  final List<LatLng> aedLocations;
  final String selectedMode;
  final List<AED> aeds;
  final bool isRefreshingAEDs;
  final bool hasSelectedRoute;
  final bool navigationMode;
  final VoidCallback? onRecenterNavigation;
  final double? distance;
  final bool isOffline;
  final Map<String, RouteResult> preloadedRoutes;
  final bool isPreloadingRoutes;
  final double? currentBearing;
  final bool hasStartedNavigation;
  final bool isFollowingUser;
  final bool showRecenterButton;
  final int? locationAge; // in HOURS
  final bool isUsingCachedLocation;
  final bool isManuallySearchingGPS;
  final bool gpsSearchSuccess;
  final bool isLocationStale;


  const AEDMapConfig({
    required this.isLoading,
    required this.aedMarkers,
    required this.userLocation,
    required this.userLocationAvailable,
    this.mapController,
    this.navigationLine,
    this.estimatedTime = "",
    this.selectedAED,
    this.aedLocations = const [],
    this.selectedMode = "walking",
    this.aeds = const [],
    this.isRefreshingAEDs = false,
    this.hasSelectedRoute = false,
    this.navigationMode = false,
    this.onRecenterNavigation,
    this.distance,
    this.isOffline = false,
    this.preloadedRoutes = const {},
    this.isPreloadingRoutes = false,
    this.currentBearing,
    this.hasStartedNavigation = false,
    this.isFollowingUser = true,
    this.showRecenterButton = false,
    this.locationAge,
    this.isUsingCachedLocation = false,
    this.isManuallySearchingGPS = false,
    this.gpsSearchSuccess = false,
    this.isLocationStale = false,
  });
}

class AEDMapDisplay extends StatefulWidget {
  final AEDMapConfig config;
  final Function(LatLng) onSmallMapTap;
  final Function(LatLng) onStartNavigation;
  final Function(String) onTransportModeSelected;
  final Function(GoogleMapController) onMapCreated;
  final VoidCallback onRecenterPressed;
  final VoidCallback? onCancelNavigation;
  final Function(LatLng)? onExternalNavigation;
  final bool userLocationAvailable;
  final Function(LatLng)? onPreviewNavigation;
  final void Function(CameraPosition position)? onCameraMoved;
  final VoidCallback? onCameraMoveStarted;
  final VoidCallback? onCameraIdle;
  final VoidCallback? onRecenterNavigation;
  final VoidCallback? onManualGPSSearch;


  const AEDMapDisplay({
    super.key,
    required this.config,
    required this.onSmallMapTap,
    required this.onStartNavigation,
    required this.onTransportModeSelected,
    required this.onMapCreated,
    required this.onRecenterPressed,
    this.onCancelNavigation,
    this.onExternalNavigation,
    required this.userLocationAvailable,
    this.onPreviewNavigation,
    this.onCameraMoved,
    this.onCameraMoveStarted,
    this.onCameraIdle,
    this.onRecenterNavigation,
    this.onManualGPSSearch,
  });

  @override
  State<AEDMapDisplay> createState() => _AEDMapDisplayState();
}

class _AEDWithDistance {
  final AED aed;
  final int distance;

  _AEDWithDistance({required this.aed, required this.distance});
}


class _AEDMapDisplayState extends State<AEDMapDisplay> with WidgetsBindingObserver {
  String? _mapStyle;
  MapType _currentMapType = MapType.normal;
  bool _hasScrolledUnderHeader = false;
  StreamSubscription<CompassEvent>? _compassSubscription;
  final Map<int, Map<String, dynamic>> _cachedAEDDistances = {};
  late Future<String> _syncTimeFuture;
  final GlobalKey _aedListKey = GlobalKey();
  final GlobalKey _navigationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _syncTimeFuture = NetworkService.getFormattedSyncTime();
    WidgetsBinding.instance.addObserver(this);

    // ✅ ADD: Start compass stream only when navigating
    if (widget.config.hasStartedNavigation && widget.config.navigationLine == null) {
      _startCompassStream();
    }
  }

  @override
  void didUpdateWidget(AEDMapDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle compass stream
    if (widget.config.hasStartedNavigation &&
        widget.config.navigationLine == null &&
        !oldWidget.config.hasStartedNavigation) {
      _startCompassStream();
    } else if (!widget.config.hasStartedNavigation &&
        oldWidget.config.hasStartedNavigation) {
      _compassSubscription?.cancel();
      _compassSubscription = null;
    }

    // ✅ Clear distance cache when transport mode changes
    if (widget.config.selectedMode != oldWidget.config.selectedMode) {
      setState(() {
        _cachedAEDDistances.clear();
      });
    }

    // ✅ ADD: Clear cache when user moves significantly
    if (widget.config.userLocation != null &&
        oldWidget.config.userLocation != null) {
      final distance = LocationService.distanceBetween(
        widget.config.userLocation!,
        oldWidget.config.userLocation!,
      );

      if (distance > 100) {  // User moved more than 100m
        setState(() {
          _cachedAEDDistances.clear();
        });
      }
    }
  }

  void _startCompassStream() {
    _compassSubscription?.cancel();
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (mounted) {
        setState(() {}); // Force rebuild
      }
    });
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  /// ✅ Load Custom Map Style
  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_style.json').timeout(
        const Duration(seconds: 5),  // ✅ ADD TIMEOUT
        onTimeout: () {
          print("⚠️ Map style load timeout");
          return "";  // Return empty string on timeout
        },
      );

      if (mounted) {  // ✅ ADD MOUNTED CHECK
        setState(() {
          _mapStyle = style;
        });
      }
    } catch (e) {
      print("Error loading map style: $e");
      if (mounted && _mapStyle == null) {
        setState(() {
          _mapStyle = "";
        });
      }
    }
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.hybrid
          : MapType.normal;
    });
    HapticFeedback.lightImpact();
  }

  void _showShareDialog(AED aed) {
    final String googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=${aed.location.latitude},${aed.location.longitude}';

    final String shareText =
        '🚨 AED Location: ${aed.name}\n'
        '📍 ${aed.address ?? "No address"}\n'
        '🗺️ $googleMapsUrl';

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF194E9D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.share,
                      color: Color(0xFF194E9D),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share AED Location',
                          style: SafeFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          aed.name,
                          style: SafeFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // QR Code
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    QrImageView(
                      data: googleMapsUrl,
                      version: QrVersions.auto,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan to open in Google Maps',
                      style: SafeFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Share Options
              Row(
                children: [
                  Expanded(
                    child: _buildShareButton(
                      icon: Icons.copy,
                      label: 'Copy Link',
                      color: Colors.blue.shade600,
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: googleMapsUrl));
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Link copied to clipboard',
                                    style: SafeFonts.inter(fontSize: 14),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.green.shade600,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              margin: const EdgeInsets.all(16),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildShareButton(
                      icon: Icons.share,
                      label: 'Share',
                      color: Colors.green.shade600,
                      onTap: () async {
                        Navigator.pop(context);
                        await Share.share(
                          shareText,
                          subject: 'AED Location: ${aed.name}',
                        );
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Close button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: SafeFonts.inter(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: SafeFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ ADD: Show minimal loading only if style hasn't loaded yet
    if (_mapStyle == null) {
      return const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(),
        ),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Stack(
            children: [
              _buildGoogleMap(),
              _buildStatusBar(),
              _buildMapTypeToggle(),

              if (!widget.config.hasSelectedRoute)
                orientation == Orientation.portrait ? _buildAEDListPanel() : _buildAEDSideListPanel(),

              if (widget.config.hasSelectedRoute && !widget.config.hasStartedNavigation)
                _buildNavigationPanel(isSidePanel: orientation == Orientation.landscape),

              if (widget.config.hasStartedNavigation)
                _buildActiveNavigationPanel(isSidePanel: orientation == Orientation.landscape),
            ],
          ),
        );
      },
    );
  }


  Widget _buildGoogleMap() {
    final padding = MediaQuery.of(context).orientation == Orientation.portrait
        ? EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.04)
        : EdgeInsets.zero;

    return Positioned.fill(
      child: Padding(
        padding: padding,
        child: GoogleMap(
          onMapCreated: (controller) {
            widget.onMapCreated(controller);
          },

          initialCameraPosition: CameraPosition(
            target: widget.config.userLocation ?? const LatLng(39.0742, 21.8243),
            zoom: widget.config.userLocation != null ? 16 : 6,
          ),

          onCameraMoveStarted: () {
            widget.onCameraMoveStarted?.call();  // NO if statement!
          },

          onCameraMove: (CameraPosition position) {
            widget.onCameraMoved?.call(position);
          },

          onCameraIdle: () {
            widget.onCameraIdle?.call();  // NO if statement!
          },

          // ADD THE STYLE HERE INSTEAD
          style: _mapStyle?.isNotEmpty == true ? _mapStyle : null,
          mapType: _currentMapType,
          markers: widget.config.aedMarkers,
          myLocationEnabled: widget.userLocationAvailable && widget.config.userLocation != null,
          myLocationButtonEnabled: false,
          polylines: widget.config.navigationLine != null
              ? {widget.config.navigationLine!}
              : {},
          mapToolbarEnabled: false,
          compassEnabled: true,
          zoomControlsEnabled: false,
          rotateGesturesEnabled: true,
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          tiltGesturesEnabled: true,

          // ENABLE OFFLINE MAP TILES
          liteModeEnabled: false,           // Ensure full map functionality
          trafficEnabled: false,            // Disable traffic (requires internet)
          buildingsEnabled: true,           // Keep buildings for context
          indoorViewEnabled: false,         // Disable indoor maps (requires internet)

          // Add caching hint for better offline support
          cameraTargetBounds: CameraTargetBounds.unbounded,
          minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    if (widget.config.isLoading) return const SizedBox.shrink();

    Widget iconWidget;

    if (widget.config.isRefreshingAEDs) {
      iconWidget = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      );
    } else if (widget.config.isOffline) {
      iconWidget = const Icon(Icons.wifi_off, color: Colors.orange, size: 22);
    } else {
      iconWidget = const Icon(Icons.wifi, color: Colors.green, size: 22);
    }

    return Stack(
      children: [
        // ✅ NEW: User location at top-center
        if (widget.config.userLocation != null)
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 0,
            right: 0,
            child: Center(
              child: _buildUserLocationChip(),
            ),
          ),

        // Existing wifi status at top-right
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          right: 10,
          child: Tooltip(
            message: widget.config.isOffline
                ? 'No internet connection'
                : 'Connected to internet',
            child: iconWidget,
          ),
        ),
      ],
    );
  }

// ✅ ADD NEW METHOD
  Widget _buildUserLocationChip() {
    final userLoc = widget.config.userLocation!;

    // Format coordinates (truncate to 4 decimal places)
    final latStr = userLoc.latitude.toStringAsFixed(4);
    final lngStr = userLoc.longitude.toStringAsFixed(4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.my_location,
            size: 14,
            color: Color(0xFF194E9D),
          ),
          const SizedBox(width: 6),
          Text(
            '$latStr, $lngStr',
            style: SafeFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF194E9D),
            ),
          ),
          // TODO: Future enhancement - fetch address from geocoding API
          // and show address instead of coordinates when available
        ],
      ),
    );
  }


  Widget _buildMapTypeToggle() {
    final orientation = MediaQuery.of(context).orientation;

    // Replace the top calculation with:
    final double top = orientation == Orientation.portrait
        ? MediaQuery.of(context).padding.top + 6
        : 3.0;

// Replace the landscape left with your panel constant:
    final double left = orientation == Orientation.landscape
        ? AEDMapUIConstants.landscapePanelWidth + 8
        : 8;

    return Positioned(
      left: left,
      top: top,
      child: Tooltip(
        message: _currentMapType == MapType.normal
            ? 'Switch to Satellite View'
            : 'Switch to Map View',
        child: Material(
          elevation: 4,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: _toggleMapType,
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _currentMapType == MapType.normal
                    ? Icons.satellite_alt
                    : Icons.map,
                size: 24,
                color: const Color(0xFF194E9D),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKSLButton() {
    return Tooltip(
      message: 'Kids Save Lives — global initiative to teach CPR to schoolchildren',
      child: Material(
        elevation: 6,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: () => _showKSLDialog(),
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              'assets/icons/kids_save_lives_logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  void _showKSLDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/icons/kids_save_lives_logo.png',
                height: 60,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              Text(
                'Kids Save Lives',
                style: SafeFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A global initiative supported by the European Resuscitation Council to teach CPR to schoolchildren worldwide. AED data in this app is provided by iSaveLives.gr.',
                textAlign: TextAlign.center,
                style: SafeFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Close',
                        style: SafeFonts.inter(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AEDWebViewScreen(
                              url: 'https://kidssavelives.org',
                              title: 'Kids Save Lives',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF194E9D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Visit Website',
                        style: SafeFonts.inter(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContainer({
    required Widget child,
    required BorderRadius borderRadius,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias, // ← Change to antiAlias for smooth rounded corners
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: child, // Remove unnecessary Stack wrapper
    );
  }

  Widget _buildAEDListContent(ScrollController scrollController) {
    return SafeArea(
      top: false,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Add padding to the top of the actual panel
          Padding(
            padding: const EdgeInsets.only(top: 56),
            child: _buildPanelContainer(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: _buildAEDSheetContent(scrollController),
            ),
          ),

          // Kids Save Lives icon
          Positioned(
            top: 8,
            left: 8,
            child: _buildKSLButton(),
          ),

          // Button positioned at the top
          Positioned(
            top: 8, // Position from the very top of the safe area
            right: 8,
            child: Material(
              elevation: 8,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onRecenterPressed();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: (widget.config.isUsingCachedLocation && widget.userLocationAvailable)
                      ? const Padding( // ✅ Show a spinner
                    padding: EdgeInsets.all(10.0), // Give it some padding
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF194E9D),
                      ),
                    ),
                  )
                      : const Icon( // ✅ Show the icon
                    Icons.my_location,
                    color: Color(0xFF194E9D),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAEDSideContent(ScrollController scrollController) {
    return SafeArea(
      top: false,
      left: false,
      child: _buildPanelContainer(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
          topLeft: Radius.circular(16),
        ),
        child: _buildAEDListViewContent(scrollController),
      ),
    );
  }

  Widget _buildAEDListViewContent(ScrollController scrollController) {
    return RawScrollbar(
      controller: scrollController,
      thumbVisibility: false,  // Only shows when scrolling
      thickness: 6,
      radius: const Radius.circular(2),
      thumbColor: AppColors.clusterGreen.withValues(alpha: 0.5),
      fadeDuration: const Duration(milliseconds: 300),
      timeToFade: const Duration(milliseconds: 600),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
        children: [
          // Add draggable handle for landscape
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // ✅ ADD THIS ROW instead of just Text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.config.userLocation != null ? "Nearby AEDs" : "AED List",
                style: SafeFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2C2C2C),
                ),
              ),
              // Show last sync time
              if (widget.config.aeds.isNotEmpty && widget.config.aeds.first.lastUpdated != null)
                Text(
                  "Updated ${widget.config.aeds.first.formattedLastUpdated}",
                  style: SafeFonts.inter(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          ...widget.config.aeds.map((aed) {
            int? distance;

            if (widget.config.userLocation != null) {
              // First try to get cached distance (which includes estimated distances)
              final cachedDistance = CacheService.getDistance('aed_${aed.id}');

              if (cachedDistance != null) {
                distance = cachedDistance.round();
              } else {
                // Fallback: calculate straight-line with multiplier
                final straightDistance = LocationService.distanceBetween(
                    widget.config.userLocation!,
                    aed.location
                );
                final multiplier = AEDService.getTransportModeMultiplier(
                    widget.config.selectedMode
                );
                distance = (straightDistance * multiplier).round();

                // Cache this calculation
                CacheService.setDistance('aed_${aed.id}', distance.toDouble());
              }
            }

            return _buildAEDCard(
              aed: aed,
              distance: distance,
              onTap: () => widget.onSmallMapTap(aed.location),
              showButton: true,
              isFirst: false,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAEDListPanel() {
    return _buildDraggableSheet(
      key: _aedListKey,
      contentBuilder: (scrollController) => _buildAEDListContent(scrollController),
      initialSize: AEDMapUIConstants.portraitListInitial,
      minSize: AEDMapUIConstants.portraitListMin,
      maxSize: AEDMapUIConstants.portraitListMax,
      isPortrait: true,
    );
  }

  Widget _buildAEDSideListPanel() {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: AEDMapUIConstants.landscapePanelWidth,
          child: DraggableScrollableSheet(
            key: _aedListKey,
            initialChildSize: AEDMapUIConstants.landscapeListInitial,
            minChildSize: AEDMapUIConstants.landscapeListMin,
            maxChildSize: AEDMapUIConstants.landscapeListMax,
            builder: (context, scrollController) {
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  setState(() {});
                  return true;
                },
                child: _buildAEDSideContent(scrollController),
              );
            },
          ),
        ),

        if (!widget.config.hasStartedNavigation)  // ✅ Show unless actively navigating
          Positioned(
            left: AEDMapUIConstants.landscapeButtonOffset,
            bottom: AEDMapUIConstants.recenterButtonBottom,
            child: Material(
              elevation: 8,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onRecenterPressed();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: AEDMapUIConstants.recenterButtonSize,
                  height: AEDMapUIConstants.recenterButtonSize,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Color(0xFF194E9D),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDraggableSheet({
    Key? key,
    required Widget Function(ScrollController) contentBuilder,
    required double initialSize,
    required double minSize,
    required double maxSize,
    bool isPortrait = true,
  }) {
    return Stack(
      children: [
        // The draggable sheet
        DraggableScrollableSheet(
          key: key,
          initialChildSize: initialSize,
          minChildSize: minSize,
          maxChildSize: maxSize,
          builder: (context, scrollController) {
            return NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                setState(() {
                });
                return true;
              },
              child: contentBuilder(scrollController),
            );
          },
        ),
      ],
    );
  }


  Widget _buildNavigationPanel({required bool isSidePanel}) {
    if (widget.config.selectedAED == null) {
      return const SizedBox.shrink();
    }

    final selectedAedInfo = widget.config.aeds.firstWhere(
          (aed) =>
      aed.location.latitude == widget.config.selectedAED?.latitude &&
          aed.location.longitude == widget.config.selectedAED?.longitude,
      orElse: () => AED(
        id: -1,
        foundation: 'Unknown AED',
        address: "Selected AED",
        location: widget.config.selectedAED!,
      ),
    );

    final isOfflineRoute = widget.config.navigationLine?.points.isEmpty ?? true;

    // BUILD THE CONTENT FIRST
    Widget buildNavigationContent(ScrollController scrollController) {
      return SafeArea(
        top: false,
        left: isSidePanel ? false : true,
        child: _buildPanelContainer(
          borderRadius: isSidePanel
              ? const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            topLeft: Radius.circular(16),
          )
              : const BorderRadius.vertical(top: Radius.circular(16)),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Title with close button
              Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 48),
                    child: Text(
                      selectedAedInfo.name, // Shows foundation name instead of address
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close Navigation',
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onCancelNavigation?.call();
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Status banners (GPS/Internet)
              if ((isOfflineRoute && widget.config.isOffline) || !widget.userLocationAvailable)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF4F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF194E9D).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!widget.userLocationAvailable)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.location_off, size: 14, color: Color(0xFF194E9D)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  "GPS unavailable - compass navigation only",
                                  style: SafeFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF194E9D),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (widget.config.isOffline)
                        Row(
                          children: [
                            const Icon(Icons.wifi_off, size: 14, color: Color(0xFF194E9D)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Offline - using cached data and estimates",
                                style: SafeFonts.inter(
                                  fontSize: 11,
                                  color: const Color(0xFF194E9D),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

              // Cached location banner
              if (widget.config.isUsingCachedLocation && widget.userLocationAvailable)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade300),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Using cached location, getting current position...',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                        ),
                      ),
                    ],
                  ),
                ),

              // ✅ BUTTONS FIRST (easier to access)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: widget.config.selectedAED != null
                          ? () {
                        if (widget.config.hasStartedNavigation) {
                          widget.onCancelNavigation?.call();
                        } else {
                          widget.onStartNavigation(widget.config.selectedAED!);
                        }
                      }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF194E9D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.config.hasStartedNavigation ? Icons.stop : Icons.navigation,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.config.hasStartedNavigation ? "Stop Navigation" : "Start Navigation",
                            style: SafeFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ✅ NEW: Share button
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF4F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: IconButton(
                      onPressed: selectedAedInfo.id != -1
                          ? () => _showShareDialog(selectedAedInfo)
                          : null,
                      tooltip: 'Share AED Location',
                      icon: const Icon(
                        Icons.share,
                        color: Color(0xFF194E9D),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF4F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: IconButton(
                      onPressed: widget.config.selectedAED != null
                          ? () => widget.onExternalNavigation?.call(widget.config.selectedAED!)
                          : null,
                      tooltip: 'Open in External Maps',
                      icon: const Icon(
                        Icons.open_in_new,
                        color: Color(0xFF194E9D),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ✅ ETA/DISTANCE/MODE TABLE (in the middle)
              if (widget.userLocationAvailable && widget.config.userLocation != null) ...[
                Builder(
                  builder: (context) {
                    final isTooOld = widget.config.locationAge != null && widget.config.locationAge! >= 5;
                    final showEmpty = isTooOld;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          // ETA
                          Expanded(
                            child: _buildCompactInfoColumn(
                              Icons.access_time,
                              widget.config.estimatedTime,
                              "ETA",
                              isOffline: isOfflineRoute || widget.config.isOffline,
                              isEmpty: showEmpty,
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.grey.shade300),
                          // Distance
                          Expanded(
                            child: _buildCompactInfoColumn(
                              Icons.near_me,  // Changed icon
                              widget.config.distance != null
                                  ? LocationService.formatDistance(widget.config.distance!)
                                  : "N/A",
                              "Distance",
                              isOffline: isOfflineRoute || widget.config.isOffline,
                              isEmpty: showEmpty,
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.grey.shade300),
                          // 3. TRANSPORT MODE (UPDATED DESIGN)
// 3. TRANSPORT MODE (VERTICAL & CLEAN)
                          Expanded(
                            child: _TransportModeSelector(
                              selectedMode: widget.config.selectedMode,
                              onModeSelected: (newMode) {
                                HapticFeedback.selectionClick();
                                widget.onTransportModeSelected(newMode);
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 12),

// ✅ CHANGED: Only show if availability parsing is available AND has data
              if (AvailabilityParser.isAvailable() &&
                  selectedAedInfo.availability != null &&
                  selectedAedInfo.availability!.isNotEmpty)
                _ExpandableAvailability(
                  parsedStatus: AvailabilityParser.parseAvailability(
                    selectedAedInfo.availability,
                  ),
                  rawAvailabilityText: selectedAedInfo.availability!,
                ),

              const SizedBox(height: 12),

              // ✅ WEB INFO LINK
              if (selectedAedInfo.id != -1 && selectedAedInfo.hasWebpage)
                Row(
                  children: [
                    // View AED Details Button
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => AEDWebViewScreen(
                                url: selectedAedInfo.aedWebpage!,
                                title: selectedAedInfo.name,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF4F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF194E9D).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Color(0xFF194E9D),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "View AED Details",
                                  style: SafeFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF194E9D),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.open_in_browser,
                                color: Color(0xFF194E9D),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // ✅ Report Icon Button (no dialog, direct link)
// ... inside the Row, after SizedBox(width: 8) ...

// ✅ Report Icon Button (BORDER REMOVED)
                    Tooltip(
                      message: "Report Issue",
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick(); // Add haptic feedback
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const AEDWebViewScreen(
                                url: 'https://kidssavelives.gr/epikoinonia/',
                                title: 'Report Issue',
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(100), // Circular ripple
                        child: Padding(
                          // Keep padding so the touch target is easy to hit
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.flag_outlined,
                            // Keep the orange color so it stands out as an "action/alert"
                            color: Colors.orange.shade600,
                            // Slightly larger since it has no box around it now
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }
    if (isSidePanel) {
      return Stack(
        children: [
          // The draggable navigation panel
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 380,
            child: DraggableScrollableSheet(
              key: _navigationKey,
              initialChildSize: 1,
              minChildSize: 0.3,
              maxChildSize: 1.0,
              builder: (context, scrollController) {
                return NotificationListener<DraggableScrollableNotification>(
                  onNotification: (notification) {
                    setState(() {
                    });
                    return true;
                  },
                  child: buildNavigationContent(scrollController),
                );
              },
            ),
          ),

          // Static recenter button positioned beside the panel
          Positioned(
            left: AEDMapUIConstants.landscapeButtonOffset,
            bottom: AEDMapUIConstants.recenterButtonBottom,
            child: Material(
              elevation: 8,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onRecenterPressed();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.my_location,
                    color: Color(0xFF194E9D),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      return Stack(
        children: [
          DraggableScrollableSheet(
            key: _navigationKey,
            initialChildSize: AEDMapUIConstants.portraitNavInitial,
            minChildSize: AEDMapUIConstants.portraitNavMin,
            maxChildSize: AEDMapUIConstants.portraitNavMax,   // Increased max size
            builder: (context, scrollController) {
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  setState(() {
                  });
                  return true;
                },
                child: buildNavigationContent(scrollController),
              );
            },
          ),
        ],
      );
    }
  }


  Widget _buildActiveNavigationPanel({required bool isSidePanel}) {
    if (widget.config.selectedAED == null) {
      return const SizedBox.shrink();
    }

    final selectedAedInfo = widget.config.aeds.firstWhere(
          (aed) =>
      aed.location.latitude == widget.config.selectedAED?.latitude &&
          aed.location.longitude == widget.config.selectedAED?.longitude,
      orElse: () => AED(
        id: -1,
        foundation: 'Unknown AED',
        address: "Selected AED",
        location: widget.config.selectedAED!,
      ),
    );

    final isOfflineRoute = widget.config.navigationLine?.points.isEmpty ?? true;

    Widget buildActiveNavigationContent(ScrollController scrollController) {
      return SafeArea(
        top: false,
        left: isSidePanel ? false : true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Add padding to the top of the actual panel (same as AED list)
            Padding(
              padding: const EdgeInsets.only(top: 56),
              child: _buildPanelContainer(
                borderRadius: isSidePanel
                    ? const BorderRadius.only(
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  topLeft: Radius.circular(16),
                )
                    : const BorderRadius.vertical(top: Radius.circular(16)),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade400,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                    // Navigation header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.navigation,
                            color: Colors.green.shade700,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Navigating to AED",
                                style: SafeFonts.inter(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Text(
                                selectedAedInfo.name,
                                style: SafeFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Stop Navigation',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.onCancelNavigation?.call();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Enhanced offline warning
                    if (isOfflineRoute || widget.config.isOffline)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.wifi_off, size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Offline navigation - estimated route",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ✅ Availability Status (INSIDE ListView children)
                    if (AvailabilityParser.isAvailable() &&
                        selectedAedInfo.availability != null &&
                        selectedAedInfo.availability!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _ExpandableAvailability(
                          parsedStatus: AvailabilityParser.parseAvailability(
                            selectedAedInfo.availability,
                          ),
                          rawAvailabilityText: selectedAedInfo.availability!,
                        ),
                      ),

                    // Main navigation info - ETA, Distance, Mode
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          // ETA
                          Expanded(
                            child: _buildCompactInfoColumn(
                              Icons.access_time,
                              widget.config.estimatedTime,
                              "ETA",
                              isOffline: isOfflineRoute || widget.config.isOffline,
                            ),
                          ),

                          // Divider
                          Container(
                            width: 1,
                            height: 50,
                            color: Colors.grey.shade300,
                          ),

                          // Distance
                          Expanded(
                            child: _buildCompactInfoColumn(
                              Icons.near_me,
                              widget.config.distance != null
                                  ? LocationService.formatDistance(widget.config.distance!)
                                  : "N/A",
                              "Distance",
                              isOffline: isOfflineRoute || widget.config.isOffline,
                            ),
                          ),

                          // Divider
                          Container(
                            width: 1,
                            height: 50,
                            color: Colors.grey.shade300,
                          ),

                          // Transport Mode
// 3. TRANSPORT MODE (VERTICAL & CLEAN)
                          Expanded(
                            child: _TransportModeSelector(
                              selectedMode: widget.config.selectedMode,
                              onModeSelected: (newMode) {
                                HapticFeedback.selectionClick();
                                widget.onTransportModeSelected(newMode);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ✅ AED Details Card + Report Icon Row
                    const SizedBox(height: 16),

                    // ✅ SIMPLE AED DETAILS + REPORT (SAME AS PREVIEW PANEL)
                    if (selectedAedInfo.id != -1 && selectedAedInfo.hasWebpage)
                      Row(
                        children: [
                          // View AED Details Button (Simple Design)
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => AEDWebViewScreen(
                                      url: selectedAedInfo.aedWebpage!,
                                      title: selectedAedInfo.name,
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDF4F9),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF194E9D).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      color: Color(0xFF194E9D),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        "View AED Details",
                                        style: SafeFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF194E9D),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.open_in_browser,
                                      color: Color(0xFF194E9D),
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // ✅ Report Icon Button
// ... inside the Row, after SizedBox(width: 8) ...

// ✅ Report Icon Button (BORDER REMOVED)
                          Tooltip(
                            message: "Report Issue",
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick(); // Add haptic feedback
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const AEDWebViewScreen(
                                      url: 'https://kidssavelives.gr/epikoinonia/',
                                      title: 'Report Issue',
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(100), // Circular ripple
                              child: Padding(
                                // Keep padding so the touch target is easy to hit
                                padding: const EdgeInsets.all(12),
                                child: Icon(
                                  Icons.flag_outlined,
                                  // Keep the orange color so it stands out as an "action/alert"
                                  color: Colors.orange.shade600,
                                  // Slightly larger since it has no box around it now
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],  // ← ListView.children closes
                ),  // ← ListView closes
              ),  // ← _buildPanelContainer closes
            ),  // ← Padding closes

            // ✅ ADD RECENTER BUTTON HERE
            if (widget.config.showRecenterButton)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onRecenterNavigation?.call();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Recenter",
                        style: SafeFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF194E9D),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Show compass if navigation has started AND we have no route line to display
            if (widget.config.hasStartedNavigation && widget.config.navigationLine == null)
              _buildCompassIndicator(),
          ],
        ),
      );
    }

    if (isSidePanel) {
      return Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: AEDMapUIConstants.landscapePanelWidth,
        child: DraggableScrollableSheet(
          initialChildSize: AEDMapUIConstants.portraitActiveNavInitial,
          minChildSize: AEDMapUIConstants.portraitActiveNavMin,
          maxChildSize: AEDMapUIConstants.portraitActiveNavMax,
          builder: (context, scrollController) {
            return buildActiveNavigationContent(scrollController);
          },
        ),
      );
    } else {
      return DraggableScrollableSheet(
        initialChildSize: AEDMapUIConstants.portraitActiveNavInitial,
        minChildSize: AEDMapUIConstants.portraitActiveNavMin,
        maxChildSize: AEDMapUIConstants.portraitActiveNavMax,
        builder: (context, scrollController) {
          return buildActiveNavigationContent(scrollController);
        },
      );
    }
  }


  double _calculateBearingToDestination(LatLng from, LatLng to) {
    final lat1Rad = from.latitude * (pi / 180);
    final lat2Rad = to.latitude * (pi / 180);
    final deltaLngRad = (to.longitude - from.longitude) * (pi / 180);

    final y = sin(deltaLngRad) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(deltaLngRad);

    final bearingRad = atan2(y, x);
    final bearingDeg = bearingRad * (180 / pi);

    return (bearingDeg + 360) % 360; // Normalize to 0-360
  }

  Widget _buildCompassIndicator() {
    return Positioned(
      top: 2,
      left: 8,
      child: StreamBuilder<CompassEvent>(
        stream: FlutterCompass.events,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();

          final compassBearing = snapshot.data!.heading ?? 0.0;
          double bearingToDestination;

          if (widget.config.userLocation != null) {
            bearingToDestination = _calculateBearingToDestination(
              widget.config.userLocation!,
              widget.config.selectedAED!,
            );
          } else {
            bearingToDestination = 0.0;
          }

          double relativeAngle = bearingToDestination - compassBearing;
          if (relativeAngle > 180) relativeAngle -= 360;
          if (relativeAngle < -180) relativeAngle += 360;

          return Material(
            elevation: 8,
            shape: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Transform.rotate(
                angle: relativeAngle * (pi / 180),
                child: const Icon(
                  Icons.navigation,
                  color: Color(0xFF194E9D),
                  size: 28,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCompactInfoColumn(
      IconData icon,
      String value,
      String label, {
        bool isOffline = false,
        bool isEmpty = false,  // NEW parameter
      }) {
    final textColor = (isOffline || isEmpty) ? Colors.grey.shade600 : Colors.black;
    final iconColor = (isOffline || isEmpty) ? Colors.grey.shade500 : const Color(0xFF194E9D);
    final displayValue = isEmpty ? "--" : value;

    return Column(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 4),
        Text(
          displayValue,
          style: SafeFonts.inter(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: textColor,
          ),
        ),
        Text(
          label,
          style: SafeFonts.inter(
            color: Colors.grey.shade600,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildAEDCard({
    required AED aed,
    required int? distance,
    required VoidCallback onTap,
    bool showButton = false,
    bool isFirst = false,
  }) {
    final selectedMode = widget.config.selectedMode;
    final userLocation = widget.config.userLocation;

    // ✅ CHECK CACHE FIRST
    if (_cachedAEDDistances.containsKey(aed.id)) {
      final cached = _cachedAEDDistances[aed.id]!;

      // Only recalculate if mode or location changed significantly
      if (cached['mode'] == selectedMode &&
          userLocation != null &&
          cached['location'] != null) {
        final cachedLoc = cached['location'] as LatLng;
        if (LocationService.distanceBetween(cachedLoc, userLocation) < 50) {
          // Use cached values
          return _buildAEDCardInternal(
            aed: aed,
            displayDistance: cached['displayDistance'],
            displayTime: cached['displayTime'],
            isRealData: cached['isRealData'],
            onTap: onTap,
            showButton: showButton,
            isFirst: isFirst,
          );
        }
      }
    }

    // Calculate fresh
    String? displayDistance;
    String? displayTime;
    bool isRealData = false;

    // 1. Check preloaded routes
    final routeKey = '${aed.id}_$selectedMode';
    final preloadedRoute = widget.config.preloadedRoutes[routeKey];
    if (preloadedRoute != null && !preloadedRoute.isOffline) {
      displayDistance = preloadedRoute.distanceText ??
          LocationService.formatDistance(preloadedRoute.actualDistance ?? 0);
      displayTime = preloadedRoute.duration;
      isRealData = true;
    }

    // 2. Check cached real distance
    if (!isRealData && userLocation != null) {
      final cachedRealDistance = CacheService.getDistance('aed_${aed.id}_$selectedMode');
      if (cachedRealDistance != null) {
        displayDistance = LocationService.formatDistance(cachedRealDistance);
        displayTime = LocationService.calculateOfflineETA(cachedRealDistance, selectedMode);
        isRealData = true;
      }
    }

    // 3. Fallback to estimation
    if (displayDistance == null || displayTime == null) {
      final estimatedDistance = CacheService.getDistance('aed_${aed.id}')?.round() ?? distance;

      if (estimatedDistance != null) {
        displayDistance = LocationService.formatDistance(estimatedDistance.toDouble());
        displayTime = LocationService.calculateOfflineETA(
          estimatedDistance.toDouble(),
          selectedMode,
        );
      }
    }

    // ✅ CACHE THE RESULT
    _cachedAEDDistances[aed.id] = {
      'mode': selectedMode,
      'location': userLocation,
      'displayDistance': displayDistance,
      'displayTime': displayTime,
      'isRealData': isRealData,
    };

    return _buildAEDCardInternal(
      aed: aed,
      displayDistance: displayDistance,
      displayTime: displayTime,
      isRealData: isRealData,
      onTap: onTap,
      showButton: showButton,
      isFirst: isFirst,
    );
  }

// ✅ ADD THIS NEW METHOD (extract the UI logic):
  Widget _buildAEDCardInternal({
    required AED aed,
    required String? displayDistance,
    required String? displayTime,
    required bool isRealData,
    required VoidCallback onTap,
    bool showButton = false,
    bool isFirst = false,
  }) {
    final availabilityStatus = AvailabilityParser.parseAvailability(aed.availability);
    final selectedMode = widget.config.selectedMode;

    // Only show green border if we have valid availability data
    final bool isOpenNow = AvailabilityParser.isAvailable() &&
        !availabilityStatus.isUncertain &&
        availabilityStatus.isOpen;

    // Colors based on data quality
    final Color distanceColor = isRealData ? const Color(0xFF444444) : const Color(0xFF727272);
    final Color distanceIconColor = Colors.grey.shade600;

    final IconData timeIcon = selectedMode == 'walking' ? Icons.directions_walk : Icons.directions_car;
    final Color timeColor = isRealData
        ? (selectedMode == 'walking' ? AppColors.clusterGreen : AppColors.primary)
        : const Color(0xFF727272);
    final Color timeIconColor = isRealData ? timeColor : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 6, top: isFirst ? 8.0 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF4F9),
          borderRadius: BorderRadius.circular(8),
          border: isOpenNow
              ? Border.all(color: AppColors.clusterGreen, width: 1)
              : null,
          boxShadow: isOpenNow
              ? [
            BoxShadow(
              color: AppColors.clusterGreen.withValues(alpha: 0.15),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Foundation name
                    Text(
                      aed.name,
                      style: SafeFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF444444),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Address if different
                    if (aed.address != null && aed.address != aed.foundation)
                      Text(
                        LocationService.shortenAddress(aed.address!),
                        style: SafeFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF666666),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Distance + Time Row
                    if (widget.userLocationAvailable &&
                        (displayDistance != null || displayTime != null))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            // Distance
                            if (displayDistance != null) ...[
                              Icon(Icons.near_me, size: 11, color: distanceIconColor),
                              const SizedBox(width: 3),
                              Text(
                                displayDistance,
                                style: SafeFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: distanceColor,
                                ),
                              ),
                            ],
                            // Time
                            if (displayTime != null) ...[
                              if (displayDistance != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 1,
                                  height: 10,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Icon(timeIcon, size: 11, color: timeIconColor),
                              const SizedBox(width: 3),
                              Text(
                                displayTime,
                                style: SafeFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: timeColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showButton)
              ElevatedButton.icon(
                onPressed: () => widget.onStartNavigation(aed.location),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF194E9D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  elevation: 0,
                ),
                icon: SvgPicture.asset(
                  'assets/icons/compass.svg',
                  width: 13,
                  height: 13,
                  colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
                label: Text(
                  "Start",
                  style: SafeFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAEDSheetContent(ScrollController scrollController) {
    if (widget.config.aedLocations.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
        children: [
          Center(
            child: Container(
              width: 56,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFBFBFBF),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Text(
            "AED Locations",
            style: SafeFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 20),

          // Empty state based on connectivity
          if (widget.config.isOffline)
            _buildEmptyStateOffline()
          else
            _buildEmptyStateLoading(),
        ],
      );
    }

    final hasUserLocation = widget.config.userLocation != null;
    final sortedAEDs = widget.config.aeds;

    AED? nearestAED;
    int? nearestDistance;
    List<_AEDWithDistance> aedsWithDistances = [];

    if (hasUserLocation && sortedAEDs.isNotEmpty) {
      nearestAED = sortedAEDs.first;
      nearestDistance = CacheService.getDistance('aed_${nearestAED.id}')?.round() ??
          LocationService.distanceBetween(
            widget.config.userLocation!,
            nearestAED.location,
          ).round();

      if (sortedAEDs.length > 1) {
        final otherAEDs = sortedAEDs.sublist(1);
        aedsWithDistances = otherAEDs.map((aed) {
          final distance = CacheService.getDistance('aed_${aed.id}')?.round() ??
              LocationService.distanceBetween(
                widget.config.userLocation!,
                aed.location,
              ).round();
          return _AEDWithDistance(aed: aed, distance: distance);
        }).toList();
      }
    }

    // ✅ WRAP LISTVIEW IN RAWSCROLLBAR
    return Column(
      children: [
        // 🔹 Drag handle – now completely independent from scrolling
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 56,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFBFBFBF),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),

        // 🔹 The scrollable part
        Expanded(
          child: RawScrollbar(
            controller: scrollController,
            thumbVisibility: false,
            thickness: 8,
            radius: const Radius.circular(8),
            thumbColor: const Color(0xFF006636).withValues(alpha: 0.6),
            padding: const EdgeInsets.only(right: 4, top: 0, bottom: 16),
            child: (hasUserLocation && nearestAED != null)
                ? NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (notification is ScrollUpdateNotification) {
                  final bool shouldShowShadow = notification.metrics.pixels > 5; // ✅ Add threshold

                  if (shouldShowShadow != _hasScrolledUnderHeader) {
                    setState(() {
                      _hasScrolledUnderHeader = shouldShowShadow;
                    });
                  }
                } else if (notification is ScrollEndNotification) {
                  // ✅ Reset shadow when scroll ends at top
                  if (notification.metrics.pixels <= 5 && _hasScrolledUnderHeader) {
                    setState(() {
                      _hasScrolledUnderHeader = false;
                    });
                  }
                }
                return false;
              },
              child: CustomScrollView(  // ✅ ONLY ONE NotificationListener wrapping CustomScrollView
                controller: scrollController,
                slivers: [
                  // ⭐ PINNED TITLE WITH CONDITIONAL SHADOW
                  SliverAppBar(
                    pinned: true,
                    automaticallyImplyLeading: false,
                    toolbarHeight: 44,
                    elevation: _hasScrolledUnderHeader ? 4 : 0,  // ✅ CHANGED: Conditional
                    shadowColor: Colors.black26,
                    backgroundColor: Colors.white,
                    surfaceTintColor: Colors.transparent,
                    // ✅ REMOVED: forceElevated (we control elevation manually now)

                    flexibleSpace: Container(
                      color: Colors.white,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            "Nearest Defibrillator",
                            style: SafeFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2C2C2C),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 🔹 Nearest AED card – this SCROLLS
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: _buildAEDCard(
                        aed: nearestAED,
                        distance: nearestDistance,
                        onTap: () => widget.onSmallMapTap(nearestAED!.location),
                        showButton: true,
                        isFirst: true,
                      ),
                    ),
                  ),

                  // 🔹 "Other" header + sync time – also scrolls
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "Other",
                            style: SafeFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2C2C2C),
                            ),
                          ),
                          FutureBuilder<String>(
                            future: _syncTimeFuture,
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Text(
                                  "AEDs updated: ${snapshot.data}",
                                  style: SafeFonts.inter(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 🔹 Remaining AEDs (scroll under pinned title)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        final entry = aedsWithDistances[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildAEDCard(
                            aed: entry.aed,
                            distance: entry.distance,
                            onTap: () => widget.onPreviewNavigation?.call(entry.aed.location),
                            showButton: true,
                          ),
                        );
                      },
                      childCount: aedsWithDistances.length,
                    ),
                  ),
                ],
              ),
            )
                : ListView(
              // 👇 fallback when no userLocation (no pinning needed)
              controller: scrollController,
              padding: const EdgeInsets.only(left: 16, right: 16, top: 0),
              children: [
                Text(
                  "List of AEDs",
                  style: SafeFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2C2C2C),
                  ),
                ),
                const SizedBox(height: 8),
                ...sortedAEDs.map((aed) {
                  return _buildAEDCard(
                    aed: aed,
                    distance: null,
                    onTap: () => widget.onSmallMapTap(aed.location),
                    showButton: true,
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateOffline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.wifi_off,
            size: 48,
            color: Colors.orange.shade600,
          ),
          const SizedBox(height: 12),
          Text(
            "No Internet Connection",
            style: SafeFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "AED locations require an internet connection to load. Please check your connection and try again.",
            textAlign: TextAlign.center,
            style: SafeFonts.inter(
              fontSize: 14,
              color: Colors.orange.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateLoading() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            "Loading AED Locations",
            style: SafeFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Please wait while we fetch nearby defibrillator locations...",
            textAlign: TextAlign.center,
            style: SafeFonts.inter(
              fontSize: 14,
              color: const Color(0xFF727272),
            ),
          ),
        ],
      ),
    );
  }
}
class _ExpandableAvailability extends StatefulWidget {
  final AvailabilityStatus parsedStatus;
  final String rawAvailabilityText;

  const _ExpandableAvailability({
    required this.parsedStatus,
    required this.rawAvailabilityText,
  });

  @override
  State<_ExpandableAvailability> createState() =>
      _ExpandableAvailabilityState();
}

class _ExpandableAvailabilityState extends State<_ExpandableAvailability> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.parsedStatus;
    final rawText = widget.rawAvailabilityText;

    Color statusColor;
    IconData icon;

    if (status.isUncertain) {
      statusColor = Colors.grey.shade600;
      icon = Icons.schedule;
    } else if (status.isOpen) {
      statusColor = AppColors.clusterGreen;
      icon = Icons.check_circle_outline;
    } else {
      statusColor = Colors.red.shade600;
      icon = Icons.cancel_outlined;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: statusColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: status.displayText,
                        style: SafeFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      if (status.detailText != null && !status.isUncertain) ...[
                        TextSpan(
                          text: ' · ${status.detailText}',
                          style: SafeFonts.inter(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // The new arrow button
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.grey.shade600,
                size: 20,
              ),
            ],
          ),
        ),
        // The expandable content
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 4, right: 24),
            child: Text(
              rawText,
              // Use .copyWith() to modify the TextStyle
              style: SafeFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade700,
              ).copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

class _TransportModeSelector extends StatelessWidget {
  final String selectedMode;
  final Function(String) onModeSelected;

  const _TransportModeSelector({
    required this.selectedMode,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isWalking = selectedMode == 'walking';
    // Cluster Green for the Icon to match your request
    const iconColor = Color(0xFF006636);

    return PopupMenuButton<String>(
      onSelected: onModeSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 45), // Drops down below the text
      tooltip: 'Change Mode',
      itemBuilder: (context) => [
        _buildMenuItem(context, 'walking', Icons.directions_walk, "Walking"),
        _buildMenuItem(context, 'driving', Icons.directions_car, "Driving"),
      ],
      // The visual trigger
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. The Icon (Green, No Border)
            Icon(
              isWalking ? Icons.directions_walk : Icons.directions_car,
              color: iconColor,
              size: 20, // Same size as neighbor icons
            ),
            const SizedBox(height: 4),

            // 2. The Value Text (Black, Bold)
            Text(
              isWalking ? "Walking" : "Driving",
              style: SafeFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black, // Match neighbor text color
              ),
            ),

            // 3. The Label + Tiny Arrow (Grey)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Mode",
                  style: SafeFonts.inter(
                    color: Colors.grey.shade600,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down, // Small indicator that it's clickable
                  size: 14,
                  color: Colors.grey.shade500,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
      BuildContext context, String value, IconData icon, String label) {
    final isSelected = selectedMode == value;
    const color = Color(0xFF006636);

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? color : Colors.grey.shade600,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: SafeFonts.inter(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : Colors.grey.shade800,
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check, color: color, size: 16),
          ]
        ],
      ),
    );
  }
}