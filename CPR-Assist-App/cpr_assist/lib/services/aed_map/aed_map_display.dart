import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../models/aed.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/map_utils.dart';



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
  final int currentBatch;
  final String selectedMode;
  final List<AED> aeds;
  final bool isRefreshingAEDs;
  final bool hasSelectedRoute;
  final bool navigationMode;
  final double? distance;

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
    this.currentBatch = 3,
    this.selectedMode = "walking",
    this.aeds = const [],
    this.isRefreshingAEDs = false,
    this.hasSelectedRoute = false,
    this.navigationMode = false,
    this.distance,
  });
}

class AEDMapDisplay extends StatefulWidget {
  final AEDMapConfig config;
  final Function(LatLng) onSmallMapTap;
  final Function(LatLng) onStartNavigation;
  final Function(String) onTransportModeSelected;
  final Function() onBatchUpdate;
  final Function(GoogleMapController) onMapCreated;
  final VoidCallback onRecenterPressed;
  final VoidCallback? onCancelNavigation;
  final Function(LatLng)? onExternalNavigation;
  final bool userLocationAvailable;

  const AEDMapDisplay({
    super.key,
    required this.config,
    required this.onSmallMapTap,
    required this.onStartNavigation,
    required this.onTransportModeSelected,
    required this.onBatchUpdate,
    required this.onMapCreated,
    required this.onRecenterPressed,
    this.onCancelNavigation,
    this.onExternalNavigation,
    required this.userLocationAvailable
  });

  @override
  State<AEDMapDisplay> createState() => _AEDMapDisplayState();
}

class _AEDMapDisplayState extends State<AEDMapDisplay> with WidgetsBindingObserver {
  String? _mapStyle;
  bool _hasAnimatedInitialCamera = false;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.config.navigationMode) {
      // Resume compass mode when app comes back to foreground
      _enableCompassMode();
    }
  }

  void _enableCompassMode() {
    setState(() {});
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

    return MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: Stack(
          children: [
          _buildGoogleMap(),
            if (widget.config.isRefreshingAEDs) _buildLoadingIndicator(),
            if (widget.config.selectedAED != null && !widget.config.navigationMode)
            _buildTransportButtons(),
            _buildRecenterButton(),
            if (widget.config.hasSelectedRoute && !widget.config.navigationMode)
              _buildCloseButton(),
            if (!widget.config.isLoading &&
                widget.config.aedLocations.isNotEmpty &&
                !widget.config.navigationMode &&
                !widget.config.hasSelectedRoute)
              _buildAEDListPanel(),
            if (widget.config.hasSelectedRoute)
              _buildNavigationPanel(),
          ],
        )
    );
  }


  Widget _buildGoogleMap() {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height * 0.05,
        ),
        child: GoogleMap(
          onMapCreated: (controller) {
            widget.onMapCreated(controller);
            _animateToUserLocation(controller);
          },
          initialCameraPosition: CameraPosition(
            target: widget.config.userLocation ?? const LatLng(20.0, 20.0),
            zoom: widget.config.userLocation != null ? 16 : 2,
          ),
          markers: widget.config.aedMarkers,
          myLocationEnabled: widget.userLocationAvailable,
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

  Widget _buildLoadingIndicator() {
    return Positioned(
      bottom: 16,
      right: 16,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildTransportButtons() {
    return Positioned(
      bottom: 90,
      right: 16,
      child: Column(
        children: [
          _buildTransportButton(Icons.directions_walk, "walking"),
          const SizedBox(height: 12),
          _buildTransportButton(Icons.directions_car, "driving"),
        ],
      ),
    );
  }


  Widget _buildRecenterButton() {
    return Positioned(
      top: 4,
      right: 4,
      child: FloatingActionButton(
        heroTag: "recenter_button",
        backgroundColor: Colors.white,
        onPressed: widget.onRecenterPressed,
        mini: true,
        child: const Icon(Icons.my_location, color: Colors.black),
      ),
    );
  }

  Widget _buildCloseButton() {
    return Positioned(
      top: 16,
      left: 16,
      child: FloatingActionButton(
        heroTag: "close_preview_button",
        backgroundColor: Colors.white,
        onPressed: widget.onCancelNavigation,
        mini: true,
        child: const Icon(Icons.close, color: Colors.black),
      ),
    );
  }

  Widget _buildAEDListPanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.12,
      minChildSize: 0.12,
      maxChildSize: 0.5,
      builder: (context, scrollController) {
        return _buildAEDSheetContent(scrollController);
      },
    );
  }

  Widget _buildNavigationPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: _buildNavigationPreview(),
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
        margin: EdgeInsets.only(bottom: 6, top: isFirst ? 0.8 : 0),
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
                    _shortenAddress(aed.address),
                    style: GoogleFonts.inter(
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
                      style: GoogleFonts.poppins(
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
                  style: GoogleFonts.inter(
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

  String _shortenAddress(String fullAddress) {
    // Take only the first part before the first comma
    final parts = fullAddress.split(',');
    if (parts.isNotEmpty) {
      return parts.first.trim();
    }
    return fullAddress;
  }

  Widget _buildAEDSheetContent(ScrollController scrollController) {
    if (widget.config.aedLocations.isEmpty) {
      return const Center(child: Text("No AEDs available"));
    }

    // Only show nearest AED if we have user location
    final hasUserLocation = widget.config.userLocation != null;
    final List<AED> sortedAEDs = widget.config.aeds;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black26)],
      ),
      padding: const EdgeInsets.all(16),
      child: ListView(
        controller: scrollController,
          children: [
            /// Grab Handle
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

            /// Main content (controlled via IF/ELSE)
            if (hasUserLocation) ...[
              /// Section: Nearest Defibrillator
              Text(
                "Nearest Defibrillator",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2C2C2C),
                ),
              ),
              const SizedBox(height: 8),
              _buildAEDCard(
                aed: sortedAEDs.first,
                distance: Geolocator.distanceBetween(
                  widget.config.userLocation!.latitude,
                  widget.config.userLocation!.longitude,
                  sortedAEDs.first.location.latitude,
                  sortedAEDs.first.location.longitude,
                ).round(),
                onTap: () => widget.onSmallMapTap(sortedAEDs.first.location),
                showButton: true,
                isFirst: true,
              ),
              const SizedBox(height: 12),

              /// Section: Other
              Text(
                "Other",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2C2C2C),
                ),
              ),
              const SizedBox(height: 8),

              ...List.generate(sortedAEDs.length - 1, (i) {
                final aed = sortedAEDs[i + 1];
                final distance = Geolocator.distanceBetween(
                  widget.config.userLocation!.latitude,
                  widget.config.userLocation!.longitude,
                  aed.location.latitude,
                  aed.location.longitude,
                ).round();

                return _buildAEDCard(
                  aed: aed,
                  distance: distance,
                  onTap: () => widget.onSmallMapTap(aed.location),
                  showButton: true,
                );
              }),
            ] else ...[
              /// Fallback: No location
              Text(
                "List of AEDs",
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2C2C2C),
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(sortedAEDs.length, (i) {
                return _buildAEDCard(
                  aed: sortedAEDs[i],
                  distance: null, // no location = no distance
                  onTap: () => widget.onSmallMapTap(sortedAEDs[i].location),
                  showButton: true,
                );
              }),
            ],
          ],
      ),
    );
  }

  // 🗺️ Navigation Preview interface (Google Maps style)
  Widget _buildNavigationPreview() {
    // Find the selected AED info
    AED? selectedAedInfo;

    if (widget.config.selectedAED != null) {
      for (final aed in widget.config.aeds) {
        if (aed.location.latitude == widget.config.selectedAED!.latitude &&
            aed.location.longitude == widget.config.selectedAED!.longitude) {
          selectedAedInfo = aed;
          break;
        }
      }
    }

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [BoxShadow(color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, -2))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bar indicator
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // AED address
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: selectedAedInfo != null
                  ? Text(
                selectedAedInfo.address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
                  : const Text(
                "Selected AED",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Time and distance row
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Time indicator
                  Column(
                    children: [
                      const Icon(Icons.access_time, color: Colors.blue),
                      const SizedBox(height: 4),
                      Text(
                        widget.config.estimatedTime,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "ETA",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  // Distance indicator
                  Column(
                    children: [
                      const Icon(Icons.straighten, color: Colors.blue),
                      const SizedBox(height: 4),
                      Text(
                        widget.config.distance != null
                            ? widget.config.distance! < 1000
                            ? "${widget.config.distance!.round()} m"
                            : "${(widget.config.distance! / 1000)
                            .toStringAsFixed(1)} km"
                            : "N/A",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "Distance",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                  // Mode indicator
                  Column(
                    children: [
                      Icon(
                        widget.config.selectedMode == "walking"
                            ? Icons.directions_walk
                            : Icons.directions_car,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.config.selectedMode == "walking"
                            ? "Walking"
                            : "Driving",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        "Mode",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Buttons row
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 14),
              child: Row(
                children: [
                  // Start navigation button
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: widget.config.selectedAED != null
                          ? () =>
                          widget.onStartNavigation(widget.config.selectedAED!)
                          : null,
                      child: const Text(
                        "Start Navigation",
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // External maps button
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    onPressed: widget.config.selectedAED != null
                        ? () =>
                        widget.onExternalNavigation?.call(
                            widget.config.selectedAED!)
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                    ),
                    tooltip: "Open in Maps",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🚗 Walking & Driving Mode Buttons
  Widget _buildTransportButton(IconData icon, String mode) {
    final isActive = widget.config.selectedMode == mode;
    return FloatingActionButton(
      heroTag: "transport_$mode",
      backgroundColor: isActive ? Colors.orange : Colors.blue,
      onPressed: () =>
      widget.config.selectedAED != null
          ? widget.onTransportModeSelected(mode)
          : null,
      mini: true,
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}