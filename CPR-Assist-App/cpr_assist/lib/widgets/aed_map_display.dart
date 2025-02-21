import 'package:flutter/cupertino.dart';
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
  LatLng? _etaBubblePosition;
  bool _bubbleAboveLine = true;


  @override
  void initState() {
    super.initState();
    _loadMapStyle();
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
    }
  }

  /// 📍 Find the Center Point of the Visible Part of the Route
  Future<LatLng?> _getVisibleRouteCenter() async {
    if (widget.navigationLine == null || widget.navigationLine!.points.isEmpty) {
      return null;
    }

    // ✅ Get the visible region from the map
    LatLngBounds visibleRegion = await widget.mapController!.getVisibleRegion();

    // ✅ Get route points that are within the visible region
    List<LatLng> visiblePoints = widget.navigationLine!.points.where((point) {
      return visibleRegion.contains(point);
    }).toList();

    if (visiblePoints.isEmpty) {
      // Return midpoint if no visible points
      return widget.navigationLine!.points[widget.navigationLine!.points.length ~/ 2];
    }

    // ✅ Find the midpoint of the visible segment
    return visiblePoints[visiblePoints.length ~/ 2];
  }

  /// 📍 Update ETA Bubble Position (Attach to Visible Route Center)
  Future<void> _updateETABubblePosition() async {
    LatLng? visibleCenter = await _getVisibleRouteCenter();
    if (visibleCenter == null) return;

    widget.mapController?.getScreenCoordinate(visibleCenter).then((coord) {
      final screenHeight = MediaQuery.of(context).size.height;

      setState(() {
        // 📌 Position Above or Below Route Line
        _bubbleAboveLine = coord.y > screenHeight / 2;

        // 💡 Slight offset to avoid overlapping
        double offset = _bubbleAboveLine ? -0.0002 : 0.0002;

        _etaBubblePosition = LatLng(
          visibleCenter.latitude + offset,
          visibleCenter.longitude,
        );
      });
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
                onCameraMove: (position) {
                  _updateETABubblePosition(); // 🟡 Update Position on Zoom/Pan
                },
                onCameraIdle: () {
                  _updateETABubblePosition(); // ✅ Finalize Position on Stop
                },
                onMapCreated: (controller) {
                  widget.onMapCreated(controller);
                  _updateETABubblePosition(); // 🟡 Set Position Initially

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
                initialCameraPosition: CameraPosition(
                  target: widget.userLocation ?? const LatLng(37.9838, 23.7275),
                  zoom: 15,
                ),
                markers: widget.aedMarkers,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                polylines:
                widget.navigationLine != null ? {widget.navigationLine!} : {},
              ),

              if (widget.estimatedTime.isNotEmpty) _buildETABubble(),

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

        // 📍 Scrollable Small AED Maps
        SizedBox(
          height: 120,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (scrollNotification) {
              if (scrollNotification.metrics.pixels ==
                  scrollNotification.metrics.maxScrollExtent) {
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

  /// 🎨 Render ETA Bubble Attached to Route
  Widget _buildETABubble() {
    if (_etaBubblePosition == null) return const SizedBox.shrink();

    return FutureBuilder<ScreenCoordinate>(
      future: widget.mapController?.getScreenCoordinate(_etaBubblePosition!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final coord = snapshot.data!;

        return Positioned(
          left: coord.x.toDouble() - 60,
          top: coord.y.toDouble() - (_bubbleAboveLine ? 110 : -15),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 📍 Bubble Container
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.blue, size: 16),
                    const SizedBox(width: 5),
                    Text(
                      'ETA: ${widget.estimatedTime}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),

              // 🎨 Connector Arrow (Google Maps Style)
              Positioned(
                bottom: _bubbleAboveLine ? -5 : null,
                top: _bubbleAboveLine ? null : -5,
                left: 12,
                child: CustomPaint(
                  size: const Size(15, 10),
                  painter: BubbleConnectorPainter(
                    isAbove: _bubbleAboveLine,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
