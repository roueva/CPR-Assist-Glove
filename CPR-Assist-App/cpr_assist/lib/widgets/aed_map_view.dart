  import 'package:flutter/material.dart';
  import 'package:google_maps_flutter/google_maps_flutter.dart';

  class AEDMapDisplay extends StatelessWidget {
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
    });



    @override
    Widget build(BuildContext context) {
      return Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : GoogleMap(
                  onMapCreated: (controller) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      mapController?.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: userLocation ?? const LatLng(37.9838, 23.7275),
                            zoom: 15,
                          ),
                        ),
                      );
                    });
                  },
                  initialCameraPosition: CameraPosition(
                    target: userLocation ?? const LatLng(37.9838, 23.7275),
                    zoom: 15,
                  ),
                  markers: aedMarkers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  polylines: navigationLine != null ? {navigationLine!} : {},
                ),

                if (estimatedTime.isNotEmpty) _buildRouteInfoBubble(),

                if (selectedAED != null)
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
                  onBatchUpdate();
                }
                return true;
              },
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: currentBatch,
                itemBuilder: (context, index) {
                  if (index >= aedLocations.length) return const SizedBox.shrink();
                  return _buildSmallMap(index);
                },
              ),
            ),
          ),
        ],
      );
    }

    Widget _buildSmallMap(int index) {
      final LatLng aedLocation = aedLocations[index];

      if (googleMapsApiKey == null) {
        return const Center(child: Text("⚠ Error Loading Map"));
      }

      final String staticMapUrl =
          "https://maps.googleapis.com/maps/api/staticmap?"
          "center=${aedLocation.latitude},${aedLocation.longitude}"
          "&zoom=15"
          "&size=300x300"
          "&maptype=roadmap"
          "&markers=color:red%7Clabel:A%7C${aedLocation.latitude},${aedLocation.longitude}"
          "&key=$googleMapsApiKey";

      return GestureDetector(
        onTap: () => onSmallMapTap(aedLocation),
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
                    return const Center(child: Icon(Icons.map, size: 40, color: Colors.grey));
                  },
                ),
                Positioned(
                  bottom: 5,
                  right: 5,
                  child: FloatingActionButton.small(
                    onPressed: () => onStartNavigation(aedLocation),
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

    Widget _buildTransportButton(IconData icon, String mode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FloatingActionButton(
          heroTag: "transport_$mode",
          backgroundColor: selectedMode == mode ? Colors.orange : (mode == "driving" ? Colors.blue : Colors.green),
          onPressed: () {
            if (selectedAED != null) {
              onTransportModeSelected(mode);
            }
          },
          mini: true,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );
    }

    Widget _buildRouteInfoBubble() {
      if (estimatedTime.isEmpty || navigationLine == null || navigationLine!.points.isEmpty) {
        return const SizedBox.shrink();
      }

      return FutureBuilder<ScreenCoordinate>(
        future: mapController?.getScreenCoordinate(
          navigationLine!.points[navigationLine!.points.length ~/ 2],
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done || !snapshot.hasData) {
            return const SizedBox.shrink();
          }
          final screenCoordinate = snapshot.data!;

          return Positioned(
            left: screenCoordinate.x.toDouble() - 50,
            top: screenCoordinate.y.toDouble() - 70,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.black12),
                boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 5)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.blue, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    'ETA: $estimatedTime',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
