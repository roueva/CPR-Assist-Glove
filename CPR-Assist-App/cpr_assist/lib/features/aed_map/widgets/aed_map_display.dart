import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../models/aed_models.dart';
import '../../../services/network/network_service.dart';
import '../screens/aed_webview_screen.dart';
import '../services/location_service.dart';
import 'aed_map_overlays.dart';
import 'aed_map_panels.dart';
import '../services/route_service.dart';


/// Configuration object passed from AEDMapWidget down to all display widgets.
/// All fields are read-only snapshots of state — no logic here.
class AEDMapConfig {
  // Core state
  final bool isLoading;
  final bool isRefreshingAEDs;
  final bool isOffline;

  // Location
  final LatLng? userLocation;
  final bool userLocationAvailable;
  final bool isUsingCachedLocation;
  final bool isManuallySearchingGPS;
  final bool? gpsSearchSuccess;
  final bool isLocationStale;
  final int? locationAge; // hours

  // AED data
  final Set<Marker> aedMarkers;
  final List<LatLng> aedLocations;
  final List<AED> aeds;

  // Navigation state
  final bool hasSelectedRoute;   // route preview active
  final bool hasStartedNavigation; // turn-by-turn active
  final bool navigationMode;     // = hasSelectedRoute (alias)
  final LatLng? selectedAED;
  final Polyline? navigationLine;
  final String estimatedTime;
  final double? distance;
  final String selectedMode;     // 'walking' | 'driving'

  // Map controller
  final GoogleMapController? mapController;

  // Navigation camera
  final double? currentBearing;
  final bool isFollowingUser;
  final bool showRecenterButton;

  // Route preloading
  final Map<String, RouteResult> preloadedRoutes;
  final bool isPreloadingRoutes;

  const AEDMapConfig({
    required this.isLoading,
    required this.isRefreshingAEDs,
    required this.isOffline,
    required this.userLocation,
    required this.userLocationAvailable,
    required this.isUsingCachedLocation,
    required this.isManuallySearchingGPS,
    this.gpsSearchSuccess,
    required this.isLocationStale,
    this.locationAge,
    required this.aedMarkers,
    required this.aedLocations,
    required this.aeds,
    required this.hasSelectedRoute,
    required this.hasStartedNavigation,
    required this.navigationMode,
    this.selectedAED,
    this.navigationLine,
    required this.estimatedTime,
    this.distance,
    required this.selectedMode,
    this.mapController,
    this.currentBearing,
    required this.isFollowingUser,
    required this.showRecenterButton,
    required this.preloadedRoutes,
    required this.isPreloadingRoutes,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDMapDisplay
// Orchestrates the Google Map + all overlay / panel sub-widgets.
// All business logic stays in the parent screen.
// ─────────────────────────────────────────────────────────────────────────────

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
  final void Function(CameraPosition)? onCameraMoved;
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

class _AEDMapDisplayState extends State<AEDMapDisplay>
    with WidgetsBindingObserver {
  String? _mapStyle;
  MapType _currentMapType = MapType.normal;

  /// Per-AED distance/time cache — keyed by aed.id.
  final Map<int, Map<String, dynamic>> _distanceCache = {};

  late final Future<String> _syncTimeFuture;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMapStyle();
    _syncTimeFuture = NetworkService.getFormattedSyncTime();
  }

  @override
  void didUpdateWidget(AEDMapDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Invalidate cache when transport mode changes
    if (widget.config.selectedMode != oldWidget.config.selectedMode) {
      setState(() => _distanceCache.clear());
    }

    // Invalidate cache when user moves significantly
    if (widget.config.userLocation != null &&
        oldWidget.config.userLocation != null) {
      final moved = LocationService.distanceBetween(
        widget.config.userLocation!,
        oldWidget.config.userLocation!,
      );
      if (moved > AppConstants.cacheInvalidationDistance) {
        setState(() => _distanceCache.clear());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Map style ──────────────────────────────────────────────────────────────

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle
          .loadString('assets/map_style.json')
          .timeout(AppConstants.mapStyleLoadTimeout, onTimeout: () => '');
      if (mounted) setState(() => _mapStyle = style);
    } catch (_) {
      if (mounted) setState(() => _mapStyle = '');
    }
  }

  // ── Map type toggle ────────────────────────────────────────────────────────

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal
          ? MapType.hybrid
          : MapType.normal;
    });
    HapticFeedback.lightImpact();
  }

  // ── KSL dialog ─────────────────────────────────────────────────────────────

  void _showKSLDialog() {
    AppDialogs.showKSLInfo(
      context,
      onVisitWebsite: () => context.push(
        const AEDWebViewScreen(
          url: 'https://kidssavelives.gr/',
          title: 'Kids Save Lives',
        ),
      ),
    );
  }

  // ── Share dialog ───────────────────────────────────────────────────────────

  void _showShareDialog(AED aed) {
    AppDialogs.showAEDShare(
      context,
      aedName: aed.name,
      latitude: aed.location.latitude,
      longitude: aed.location.longitude,
    );
  }

  // ── WebView helper ─────────────────────────────────────────────────────────

  void _openWebView(String url, String title) {
    context.push(AEDWebViewScreen(url: url, title: title));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Wait for map style to resolve before showing the map
    if (_mapStyle == null) {
      return const Center(
        child: SizedBox(
          width: AppSpacing.buttonSizeMd,
          height: AppSpacing.buttonSizeMd,
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;

        return MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Stack(
            children: [
              // ── Google Map ───────────────────────────────────────────────
              _buildGoogleMap(isPortrait),

              // ── Overlays ─────────────────────────────────────────────────
              AEDMapStatusBar(
                config: widget.config,
                userLocationAvailable: widget.userLocationAvailable,
              ),

              AEDMapTypeToggle(
                currentMapType: _currentMapType,
                onToggle: _toggleMapType,
              ),

              // ── Panels ───────────────────────────────────────────────────
              if (!widget.config.hasSelectedRoute)
                isPortrait
                    ? AEDListPanel(
                  config: widget.config,
                  userLocationAvailable: widget.userLocationAvailable,
                  distanceCache: _distanceCache,
                  syncTimeFuture: _syncTimeFuture,
                  onSmallMapTap: widget.onSmallMapTap,
                  onStartNavigation: widget.onStartNavigation,
                  onPreviewNavigation: widget.onPreviewNavigation,
                  onRecenterPressed: widget.onRecenterPressed,
                  onKSLTap: _showKSLDialog,
                )
                    : AEDSideListPanel(
                  config: widget.config,
                  userLocationAvailable: widget.userLocationAvailable,
                  distanceCache: _distanceCache,
                  onSmallMapTap: widget.onSmallMapTap,
                  onStartNavigation: widget.onStartNavigation,
                  onRecenterPressed: widget.onRecenterPressed,
                ),

              if (widget.config.hasSelectedRoute &&
                  !widget.config.hasStartedNavigation)
                AEDNavigationPanel(
                  config: widget.config,
                  userLocationAvailable: widget.userLocationAvailable,
                  isSidePanel: !isPortrait,
                  distanceCache: _distanceCache,
                  onStartNavigation: widget.onStartNavigation,
                  onCancelNavigation: widget.onCancelNavigation,
                  onExternalNavigation: widget.onExternalNavigation,
                  onTransportModeSelected: widget.onTransportModeSelected,
                  onRecenterPressed: widget.onRecenterPressed,
                  onShowShareDialog: _showShareDialog,
                  onOpenWebView: _openWebView,
                ),

              if (widget.config.hasStartedNavigation)
                AEDActiveNavigationPanel(
                  config: widget.config,
                  userLocationAvailable: widget.userLocationAvailable,
                  isSidePanel: !isPortrait,
                  onTransportModeSelected: widget.onTransportModeSelected,
                  onCancelNavigation: widget.onCancelNavigation,
                  onRecenterNavigation: widget.onRecenterNavigation,
                  onOpenWebView: _openWebView,
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Google Map ─────────────────────────────────────────────────────────────

  Widget _buildGoogleMap(bool isPortrait) {
    final padding = isPortrait
        ? EdgeInsets.only(bottom: context.screenHeight * 0.04)
        : EdgeInsets.zero;

    return Positioned.fill(
      child: Padding(
        padding: padding,
        child: GoogleMap(
          onMapCreated: widget.onMapCreated,
          initialCameraPosition: CameraPosition(
            target: widget.config.userLocation ?? AppConstants.greeceCenter,
            zoom: widget.config.userLocation != null
                ? AppConstants.defaultZoom
                : AppConstants.greeceZoom,
          ),
          onCameraMoveStarted: widget.onCameraMoveStarted,
          onCameraMove: widget.onCameraMoved,
          onCameraIdle: widget.onCameraIdle,
          style: (_mapStyle?.isNotEmpty ?? false) ? _mapStyle : null,
          mapType: _currentMapType,
          markers: widget.config.aedMarkers,
          myLocationEnabled: widget.userLocationAvailable &&
              widget.config.userLocation != null,
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
          liteModeEnabled: false,
          trafficEnabled: false,
          buildingsEnabled: true,
          indoorViewEnabled: false,
          cameraTargetBounds: CameraTargetBounds.unbounded,
          minMaxZoomPreference: const MinMaxZoomPreference(3.0, 20.0),
        ),
      ),
    );
  }
}