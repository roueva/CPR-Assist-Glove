import 'package:flutter/material.dart';
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
  final Function(LatLng)? onPreviewNavigation;


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
    required this.userLocationAvailable,
    this.onPreviewNavigation,
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
            _buildRecenterButton(),
            if (!widget.config.isLoading &&
                widget.config.aedLocations.isNotEmpty &&
                !widget.config.navigationMode &&
                !widget.config.hasSelectedRoute)
              _buildAEDListPanel(),
            if (widget.config.hasSelectedRoute)
              _buildNavigationSheet(),
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
      bottom: 70,
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
        children: TransportMode.values.map((mode) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildTransportButton(mode),
          );
        }).toList(),
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
        shape: const CircleBorder(), // 👈 ensures circular shape on all platforms
        elevation: 2,
        child: const Icon(Icons.my_location, color: Colors.black),
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

  Widget _buildNavigationSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.10,
      maxChildSize: 0.35,
      builder: (context, scrollController) {
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

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            children: [
              /// Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              /// Title row: Address + Close
              Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      selectedAedInfo.address,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Positioned(
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close Navigation',
                        onPressed: widget.onCancelNavigation,
                      )
                  )
                ],
              ),

              const SizedBox(height: 12),

              /// ETA, Distance, Mode
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildInfoColumn(Icons.access_time, widget.config.estimatedTime, "ETA"),
                  _buildInfoColumn(
                      Icons.straighten,
                      widget.config.distance != null
                          ? LocationService.formatDistance(widget.config.distance!)
                          : "N/A",
                      "Distance"),
                  _buildInfoColumn(
                    TransportModeUtils.fromString(widget.config.selectedMode).icon,
                    TransportModeUtils.fromString(widget.config.selectedMode).label,
                    "Mode",
                  ),
                ],
              ),

              const SizedBox(height: 16),

              /// Buttons row
              Row(
                children: [
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
                          ? () => widget.onStartNavigation(widget.config.selectedAED!)
                          : null,
                      child: const Text("Start Navigation", style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.map_outlined),
                    tooltip: "Open in Maps",
                    onPressed: widget.config.selectedAED != null
                        ? () => widget.onExternalNavigation?.call(widget.config.selectedAED!)
                        : null,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
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
                    LocationService.shortenAddress(aed.address),
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

  Widget _buildAEDSheetContent(ScrollController scrollController) {
    if (widget.config.aedLocations.isEmpty) {
      return const Center(child: Text("No AEDs available"));
    }

    final hasUserLocation = widget.config.userLocation != null;
    final sortedAEDs = widget.config.aeds;

    AED? nearestAED;
    int? nearestDistance;
    List<_AEDWithDistance> aedsWithDistances = [];

    if (hasUserLocation && sortedAEDs.isNotEmpty) {
      nearestAED = sortedAEDs.first;
      nearestDistance = LocationService.distanceBetween(
        widget.config.userLocation!,
        nearestAED.location,
      ).round();

      if (sortedAEDs.length > 1) {
        final otherAEDs = sortedAEDs.sublist(1);
        aedsWithDistances = otherAEDs.map((aed) {
          final distance = LocationService.distanceBetween(
            widget.config.userLocation!,
            aed.location,
          ).round();
          return _AEDWithDistance(aed: aed, distance: distance);
        }).toList();
      }
    }

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
              style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(
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
      ),
    );
  }

  /// 🚗 Walking & Driving Mode Buttons
  Widget _buildTransportButton(TransportMode mode) {
    final isActive = widget.config.selectedMode == mode.name;

    return FloatingActionButton(
      heroTag: "transport_${mode.name}",
      backgroundColor: isActive ? Colors.orange : Colors.blue,
      onPressed: widget.config.selectedAED != null
          ? () => widget.onTransportModeSelected(mode.name)
          : null,
      mini: true,
      child: Icon(mode.icon, color: Colors.white, size: 20),
    );
  }
}
