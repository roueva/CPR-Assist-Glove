  import 'package:flutter/material.dart';
  import 'package:google_maps_flutter/google_maps_flutter.dart';
  import 'package:flutter/services.dart' show rootBundle;

  class AEDMapDisplay extends StatefulWidget {
    final bool isLoading;
    final Set<Marker> aedMarkers;
    final LatLng? userLocation;
    final GoogleMapController? mapController;
    final Polyline? navigationLine;
    final String estimatedTime;
    final LatLng? selectedAED;
    final List<LatLng> aedLocations;
    final int currentBatch;
    final String selectedMode;
    final Function(LatLng) onSmallMapTap;
    final Function(LatLng) onStartNavigation;
    final Function(String) onTransportModeSelected;
    final Function() onBatchUpdate;
    final String? googleMapsApiKey;
    final Function(GoogleMapController) onMapCreated;
  
    const AEDMapDisplay({
      super.key,
      required this.isLoading,
      required this.aedMarkers,
      required this.userLocation,
      required this.mapController,
      required this.navigationLine,
      required this.estimatedTime,
      required this.selectedAED,
      required this.aedLocations,
      required this.currentBatch,
      required this.selectedMode,
      required this.onSmallMapTap,
      required this.onStartNavigation,
      required this.onTransportModeSelected,
      required this.onBatchUpdate,
      required this.googleMapsApiKey,
      required this.onMapCreated,
    });
  
    @override
    State<AEDMapDisplay> createState() => _AEDMapDisplayState();
  }
  
  class MapStyleLoader {
    static String? mapStyle;
  
    static Future<void> loadMapStyle() async {
      mapStyle = await rootBundle.loadString('assets/map_style.json');
    }
  }
  
  class _AEDMapDisplayState extends State<AEDMapDisplay> {
    String? _mapStyle;
    bool _bubbleAboveLine = true;
    LatLng? _routeMidpoint;
    bool _isUpdatingPosition = false;
  
    @override
    void initState() {
      super.initState();
      _loadMapStyle();
    }
  
    @override
    void didUpdateWidget(AEDMapDisplay oldWidget) {
      super.didUpdateWidget(oldWidget);
      // Update midpoint when navigation line changes
      if (oldWidget.navigationLine != widget.navigationLine) {
        _calculateMidpoint();
      }
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
  
    /// Calculate midpoint - separated from update bubble position
    void _calculateMidpoint() {
      if (widget.navigationLine == null ||
          widget.navigationLine!.points.isEmpty ||
          widget.mapController == null) {
        _routeMidpoint = null;
        return;
      }
  
      // Simple midpoint calculation - doesn't need async
      final points = widget.navigationLine!.points;
      _routeMidpoint = points[points.length ~/ 2];
    }
  
  
    /// Update bubble position without setState recursion
    void _updateETABubblePosition() {
      if (_isUpdatingPosition || widget.mapController == null || _routeMidpoint == null) return;
  
      _isUpdatingPosition = true;
  
      widget.mapController!.getScreenCoordinate(_routeMidpoint!).then((coord) {
        if (!mounted) {
          _isUpdatingPosition = false;
          return;
        }
  
        final screenHeight = MediaQuery.of(context).size.height;
        final newBubblePosition = coord.y > screenHeight / 2;
  
        if (newBubblePosition != _bubbleAboveLine) {
          setState(() {
            _bubbleAboveLine = newBubblePosition;
          });
        }
  
        _isUpdatingPosition = false;
      }).catchError((e) {
        _isUpdatingPosition = false;
        print("Error updating bubble position: $e");
      });
    }
  
    @override
    Widget build(BuildContext context) {
      if (_mapStyle == null) {
        return const Center(child: CircularProgressIndicator());
      }
  
      return Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                widget.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GoogleMap(
                  onMapCreated: (controller) {
                    widget.onMapCreated(controller);
                    _calculateMidpoint();
  
                    if (widget.userLocation != null) {
                      controller.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: widget.userLocation!,
                            zoom: 16,
                          ),
                        ),
                      );
                    }
                  },
                  onCameraMove: (_) {
                    // Only update on camera move end to reduce load
                  },
                  onCameraIdle: () {
                    _updateETABubblePosition();
                  },
                  initialCameraPosition: CameraPosition(
                    target: widget.userLocation ?? const LatLng(37.9838, 23.7275),
                    zoom: 15,
                  ),
                  markers: widget.aedMarkers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  polylines: widget.navigationLine != null ? {widget.navigationLine!} : {},
                ),
  
                // Only show ETA bubble if we have navigation and time
                if (widget.estimatedTime.isNotEmpty &&
                    widget.navigationLine != null &&
                    _routeMidpoint != null)
  
                if (widget.selectedAED != null)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTransportButton(Icons.directions_walk, "walking"),
                        const SizedBox(width: 20),
                        _buildTransportButton(Icons.directions_car, "driving"),
                      ],
                    ),
                  ),
              ],
            ),
          ),
  
          // Scrollable Small AED Maps
          SizedBox(
            height: 120,
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (scrollNotification) {
                if (scrollNotification.metrics.pixels == scrollNotification.metrics.maxScrollExtent) {
                  widget.onBatchUpdate();
                }
                return true;
              },
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.currentBatch,
                itemBuilder: (context, index) {
                  if (index >= widget.aedLocations.length) {
                    return const SizedBox.shrink();
                  }
                  return _buildSmallMap(index);
                },
              ),
            ),
          ),
        ],
      );
    }
  
    /// 📍 Small AED Map Preview
    Widget _buildSmallMap(int index) {
      final LatLng aedLocation = widget.aedLocations[index];
  
      if (widget.googleMapsApiKey == null) {
        return const Center(child: Text("⚠ Error Loading Map"));
      }
  
      final String staticMapUrl =
          "https://maps.googleapis.com/maps/api/staticmap?"
          "center=${aedLocation.latitude},${aedLocation.longitude}"
          "&zoom=15"
          "&size=300x300"
          "&maptype=roadmap"
          "&markers=color:red%7Clabel:A%7C${aedLocation.latitude},${aedLocation.longitude}"
          "&key=${widget.googleMapsApiKey}";
  
      return GestureDetector(
        onTap: () => widget.onSmallMapTap(aedLocation),
        child: Container(
          width: 120,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 5)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.network(
                  staticMapUrl,
                  fit: BoxFit.cover,
                  width: 120,
                  height: 120,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                        child: Icon(Icons.map, size: 40, color: Colors.grey));
                  },
                ),
                Positioned(
                  bottom: 5,
                  right: 5,
                  child: FloatingActionButton.small(
                    heroTag: 'nav-${aedLocation.latitude}-${aedLocation.longitude}',
                    onPressed: () => widget.onStartNavigation(aedLocation),
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.navigation, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  
    /// 🚗 Walking & Driving Mode Buttons
    Widget _buildTransportButton(IconData icon, String mode) {
      return FloatingActionButton(
        heroTag: "transport_$mode",
        backgroundColor:
        widget.selectedMode == mode ? Colors.orange : Colors.blue,
        onPressed: () {
          if (widget.selectedAED != null) {
            widget.onTransportModeSelected(mode);
          }
        },
        mini: true,
        child: Icon(icon, color: Colors.white, size: 20),
      );
    }
  

  }
  /// 🎨 Paints the Arrow Connector for ETA Bubble
  class BubbleConnectorPainter extends CustomPainter {
    final bool isAbove;
    final Color color;
  
    BubbleConnectorPainter({
      required this.isAbove,
      required this.color,
    });
  
    @override
    void paint(Canvas canvas, Size size) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
  
      final path = Path();
      if (isAbove) {
        // 🎨 Arrow Pointing Down
        path.moveTo(0, 0);
        path.lineTo(size.width / 2, size.height);
        path.lineTo(size.width, 0);
      } else {
        // 🎨 Arrow Pointing Up
        path.moveTo(0, size.height);
        path.lineTo(size.width / 2, 0);
        path.lineTo(size.width, size.height);
      }
      path.close();
  
      canvas.drawPath(path, paint);
    }
  
    @override
    bool shouldRepaint(CustomPainter oldDelegate) => false;
  }
