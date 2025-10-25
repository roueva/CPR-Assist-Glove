import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/aed_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;

import '../services/aed_map/aed_service.dart';
import '../services/aed_map/cache_service.dart';
import '../services/aed_map/location_service.dart';
import '../services/aed_map/route_service.dart';
import '../utils/safe_fonts.dart';
import 'aed_webview_screen.dart';

class AppColors {
  static const Color primary = Color(0xFF194E9D);
  static const Color secondary = Color(0xFFEDF4F9);
  static const Color success = Colors.green;
  static const Color warning = Colors.orange;
  static const Color error = Colors.red;
  static const Color textPrimary = Color(0xFF2C2C2C);
  static const Color textSecondary = Color(0xFF727272);
  static const Color cardBackground = Color(0xFFEDF4F9);
}

// Custom painter for colored arc at top of circle
class _CompassArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF194E9D).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Draw arc at top (30 degrees on each side of top = 60 degrees total)
    canvas.drawArc(
      rect,
      -1.57 - 0.52, // Start angle (top - 30 degrees)
      1.04, // Sweep angle (60 degrees)
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  final Map<int, RouteResult> preloadedRoutes;
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
  final VoidCallback? onCameraMoved;
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
  bool _hasAnimatedInitialCamera = false;


  final GlobalKey _aedListKey = GlobalKey();
  final GlobalKey _navigationKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  /// ✅ Load Custom Map Style
  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_style.json');
      setState(() {
        _mapStyle = style;
      });
    } catch (e) {
      print("Error loading map style: $e");
      if (mounted && _mapStyle == null) {
        setState(() {
          _mapStyle = ""; // Empty string to indicate load attempted
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mapStyle == null) {
      return const Center(child: CircularProgressIndicator());
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
            _animateToUserLocation(controller);
          },

          onCameraMoveStarted: () {
            if (widget.config.hasStartedNavigation) {
              widget.onCameraMoveStarted?.call();
            }
          },

          onCameraMove: (CameraPosition position) {
            if (widget.config.hasStartedNavigation) {
              widget.onCameraMoved?.call();
            }
          },

          onCameraIdle: () {
            if (widget.config.hasStartedNavigation) {
              widget.onCameraIdle?.call();
            }
          },

          initialCameraPosition: CameraPosition(
            target: widget.config.userLocation ?? const LatLng(39.0742, 21.8243), // Greece center
            zoom: widget.config.userLocation != null ? 16 : 6,
          ),

          // ADD THE STYLE HERE INSTEAD
          style: _mapStyle?.isNotEmpty == true ? _mapStyle : null,
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
          minMaxZoomPreference: const MinMaxZoomPreference(6.0, 20.0),
        ),
      ),
    );
  }

  void _animateToUserLocation(GoogleMapController controller) {
    if (!_hasAnimatedInitialCamera && widget.config.userLocation != null) {
      _hasAnimatedInitialCamera = true;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && widget.config.userLocation != null) {
          controller.animateCamera(
            CameraUpdate.newCameraPosition(CameraPosition(
              target: widget.config.userLocation!,
              zoom: 16,
            )),
          );
        }
      });
    }
  }

  Widget _buildStatusBar() {
    if (widget.config.isLoading) return const SizedBox.shrink();

    Widget iconWidget;

    if (widget.config.isRefreshingAEDs) {
      iconWidget = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      );
    } else if (widget.config.isOffline) {
      iconWidget = const Icon(Icons.wifi_off, color: Colors.orange, size: 20);
    } else {
      iconWidget = const Icon(Icons.wifi, color: Colors.green, size: 20);
    }

    return Positioned(
      top: 4,
      right: 10,
      child: iconWidget,
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
    return ListView(
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
        Text(
          widget.config.userLocation != null ? "Nearby AEDs" : "AED List",
          style: SafeFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2C2C2C),
          ),
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
    );
  }

  Widget _buildAEDListPanel() {
    return _buildDraggableSheet(
      key: _aedListKey,
      contentBuilder: (scrollController) => _buildAEDListContent(scrollController),
      initialSize: 0.20,
      minSize: 0.20,
      maxSize: 0.55,
      isPortrait: true,
    );
  }


  Widget _buildAEDSideListPanel() {
    return Stack(
      children: [
        // The draggable panel
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 380,
          child: DraggableScrollableSheet(
            key: _aedListKey,
            initialChildSize: 0.3,
            minChildSize: 0.3,
            maxChildSize: 1.0,
            builder: (context, scrollController) {
              return NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  setState(() {
                  });
                  return true;
                },
                child: _buildAEDSideContent(scrollController),
              );
            },
          ),
        ),

        // Static recenter button positioned beside the panel
        if (!widget.config.hasSelectedRoute)
          Positioned(
            left: 390,
            bottom: 10,
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
        name: 'Unknown AED',
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
                      selectedAedInfo.address,
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
              if (widget.config.isUsingCachedLocation)
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
                  const SizedBox(width: 12),
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
                              Icons.straighten,
                              widget.config.distance != null
                                  ? LocationService.formatDistance(widget.config.distance!)
                                  : "N/A",
                              "Distance",
                              isOffline: isOfflineRoute || widget.config.isOffline,
                              isEmpty: showEmpty,
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.grey.shade300),
                          // Transport Mode
                          Expanded(
                            child: GestureDetector(
                              onHorizontalDragEnd: (_) {
                                final isWalking = widget.config.selectedMode == 'walking';
                                final newMode = isWalking ? 'driving' : 'walking';
                                widget.onTransportModeSelected(newMode);
                              },
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: widget.config.selectedMode == 'walking'
                                          ? Colors.orange
                                          : Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      widget.config.selectedMode == 'walking'
                                          ? Icons.directions_walk
                                          : Icons.directions_car,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.config.selectedMode == 'walking' ? 'Walking' : 'Driving',
                                    style: SafeFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    "Mode",
                                    style: SafeFonts.inter(
                                      color: Colors.grey.shade500,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 12),

// ✅ WEB INFO LINK (opens in-app WebView)
              if (selectedAedInfo.id != -1)
                InkWell(
                  onTap: () {
                    // ✅ PLACEHOLDER: Use a demo URL until backend provides real ones
                    final urlString = selectedAedInfo.infoUrl ?? 'https://kidssavelives.gr/aed/1o-gel-panoramatos/';

                    // Open in-app WebView instead of external browser
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AEDWebViewScreen(
                          url: urlString,
                          title: 'AED Details',
                        ),
                      ),
                    );
                  },
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
                            selectedAedInfo.infoUrl != null && selectedAedInfo.infoUrl!.isNotEmpty
                                ? "View AED Details"
                                : "View AED Details (Demo)",
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
                          Icons.open_in_browser, // Changed icon to indicate in-app view
                          color: Color(0xFF194E9D),
                          size: 14,
                        ),
                      ],
                    ),
                  ),
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
            left: 390,
            bottom: 10,
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
            initialChildSize: 0.48,  // Increased to show content above padding
            minChildSize: 0.20,    // Increased to show content above padding
            maxChildSize: 0.6,     // Increased max size
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
        name: 'Unknown AED',
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
                                LocationService.shortenAddress(selectedAedInfo.address),
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
                              Icons.straighten,
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

                          // Transport Mode (read-only during navigation)
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: widget.config.selectedMode == 'walking'
                                        ? Colors.orange
                                        : Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    widget.config.selectedMode == 'walking'
                                        ? Icons.directions_walk
                                        : Icons.directions_car,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.config.selectedMode == 'walking' ? 'Walking' : 'Driving',
                                  style: SafeFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                Text(
                                  "Mode",
                                  style: SafeFonts.inter(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ✅ ADD RECENTER BUTTON HERE - positioned same as AED list button
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

            // ✅ ADD COMPASS ARROW ON THE LEFT
            if (!widget.userLocationAvailable || widget.config.isUsingCachedLocation && widget.config.isLocationStale)
              Positioned(
                top: 2,
                left: 8,
                child: StreamBuilder<CompassEvent>(
                  stream: FlutterCompass.events,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();

                    final compassBearing = snapshot.data!.heading ?? 0.0;
                    double bearingToDestination;

                    // Calculate actual bearing if we have user location
                    if (widget.config.userLocation != null) {
                      bearingToDestination = _calculateBearingToDestination(
                        widget.config.userLocation!,
                        widget.config.selectedAED!,
                      );
                    } else {
                      // No location - just show north reference
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
                          angle: relativeAngle * (3.14159 / 180),
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
              ),

          ],
        ),
      );
    }


    if (isSidePanel) {
      return Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 380,
        child: DraggableScrollableSheet(
          initialChildSize: 0.2,
          minChildSize: 0.2,
          maxChildSize: 0.4,
          builder: (context, scrollController) {
            return buildActiveNavigationContent(scrollController);
          },
        ),
      );
    } else {
      return DraggableScrollableSheet(
        initialChildSize: 0.25,
        minChildSize: 0.25,
        maxChildSize: 0.4,
        builder: (context, scrollController) {
          return buildActiveNavigationContent(scrollController);
        },
      );
    }
  }


  double _calculateBearingToDestination(LatLng from, LatLng to) {
    final lat1Rad = from.latitude * (3.14159 / 180);
    final lat2Rad = to.latitude * (3.14159 / 180);
    final deltaLngRad = (to.longitude - from.longitude) * (3.14159 / 180);

    final y = sin(deltaLngRad) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(deltaLngRad);

    final bearingRad = atan2(y, x);
    final bearingDeg = bearingRad * (180 / 3.14159);

    return (bearingDeg + 360) % 360; // Normalize to 0-360
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
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 6, top: isFirst ? 8.0 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEDF4F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            /// Address + Distance
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocationService.shortenAddress(aed.address),
                    style: SafeFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF444444),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (distance != null)
                    Text(
                      LocationService.formatDistance(distance.toDouble()),
                      style: SafeFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF727272),
                      ),
                    ),
                ],
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

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16), // Move padding to ListView and ensure no bottom
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

        if (hasUserLocation && nearestAED != null) ...[
          Text(
            "Nearest Defibrillator",
            style: SafeFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 8),
          _buildAEDCard(
            aed: nearestAED,
            distance: nearestDistance,
            onTap: () => widget.onSmallMapTap(nearestAED!.location),
            showButton: true,
            isFirst: true,
          ),
          const SizedBox(height: 12),
          Text(
            "Other",
            style: SafeFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          ...aedsWithDistances.map((entry) {
            return _buildAEDCard(
              aed: entry.aed,
              distance: entry.distance,
              onTap: () => widget.onPreviewNavigation?.call(entry.aed.location),
              showButton: true,
            );
          }),
        ] else ...[
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