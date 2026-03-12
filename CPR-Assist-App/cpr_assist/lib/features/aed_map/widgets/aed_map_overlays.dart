import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;
import 'package:flutter_compass/flutter_compass.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:cpr_assist/core/core.dart';
import 'aed_map_display.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AEDMapStatusBar
// Wifi indicator + user location chip at the top of the map.
// ─────────────────────────────────────────────────────────────────────────────

class AEDMapStatusBar extends StatelessWidget {
  final AEDMapConfig config;
  final bool userLocationAvailable;

  const AEDMapStatusBar({
    super.key,
    required this.config,
    required this.userLocationAvailable,
  });

  @override
  Widget build(BuildContext context) {
    if (config.isLoading) return const SizedBox.shrink();

    Widget iconWidget;
    if (config.isRefreshingAEDs) {
      iconWidget = const SizedBox(
        width: AEDMapUIConstants.connectivityIconSize,
        height: AEDMapUIConstants.connectivityIconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.info),
        ),
      );
    } else if (config.isOffline) {
      iconWidget = const Icon(
        Icons.wifi_off,
        color: AppColors.warning,
        size: AEDMapUIConstants.connectivityIconSize,
      );
    } else {
      iconWidget = const Icon(
        Icons.wifi,
        color: AppColors.success,
        size: AEDMapUIConstants.connectivityIconSize,
      );
    }

    return Stack(
      children: [
        // User location chip — top-center
        Positioned(
          top: context.padding.top + AppSpacing.xs,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: (config.userLocation != null && !config.isUsingCachedLocation)
                  ? 1.0
                  : 0.0,
              duration: AppConstants.mapAnimationDelay,
              child: config.userLocation != null
                  ? _UserLocationChip(location: config.userLocation!)
                  : const SizedBox.shrink(),
            ),
          ),
        ),

        // Wifi status — top-right
        Positioned(
          top: context.padding.top + AppSpacing.xs,
          right: AppSpacing.sm + AppSpacing.xs,
          child: Tooltip(
            message: config.isOffline
                ? 'No internet connection'
                : config.isRefreshingAEDs
                ? 'Refreshing AED data…'
                : 'Connected',
            child: iconWidget,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _UserLocationChip
// ─────────────────────────────────────────────────────────────────────────────

class _UserLocationChip extends StatelessWidget {
  final LatLng location;

  const _UserLocationChip({required this.location});

  String get _coordText =>
      '${location.latitude.toStringAsFixed(4)}, '
          '${location.longitude.toStringAsFixed(4)}';

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Your current location coordinates',
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: _coordText));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.cardSpacing,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceWhite.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowMedium,
                blurRadius: AppSpacing.xs,
                offset: Offset(0, AppSpacing.xxs),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.my_location,
                size: AppSpacing.md,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.cardSpacing),
              Text(_coordText, style: AppTypography.label(color: AppColors.primary)),
              const SizedBox(width: AppSpacing.cardSpacing),
              Icon(
                Icons.copy,
                size: AppSpacing.sm + AppSpacing.xs,
                color: AppColors.primary.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDMapTypeToggle
// Satellite / normal map toggle button — top-left.
// ─────────────────────────────────────────────────────────────────────────────

class AEDMapTypeToggle extends StatelessWidget {
  final MapType currentMapType;
  final VoidCallback onToggle;

  const AEDMapTypeToggle({
    super.key,
    required this.currentMapType,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape;
    final double top = isLandscape
        ? AppSpacing.xxs + AppSpacing.xxs         // 4 — nearly flush to top
        : context.padding.top + AppSpacing.cardSpacing;
    final double left = isLandscape
        ? AEDMapUIConstants.landscapePanelWidth + AppSpacing.sm
        : AppSpacing.sm;

    return Positioned(
      left: left,
      top: top,
      child: Tooltip(
        message: currentMapType == MapType.normal
            ? 'Switch to Satellite View'
            : 'Switch to Map View',
        child: Material(
          elevation: AppSpacing.xs,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () {
              onToggle();
              HapticFeedback.lightImpact();
            },
            customBorder: const CircleBorder(),
            child: Container(
              width: AppSpacing.buttonSizeMd,
              height: AppSpacing.buttonSizeMd,
              decoration: AppDecorations.mapControl(),
              child: Icon(
                currentMapType == MapType.normal ? Icons.satellite_alt : Icons.map,
                size: AppSpacing.iconMd,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDCompassIndicator
// Rotating navigation arrow shown during GPS-less navigation.
// ─────────────────────────────────────────────────────────────────────────────

class AEDCompassIndicator extends StatelessWidget {
  final LatLng? userLocation;
  final LatLng? destination;

  const AEDCompassIndicator({
    super.key,
    required this.userLocation,
    required this.destination,
  });

  double _bearingToDestination(LatLng from, LatLng to) {
    final lat1 = from.latitude * (pi / 180);
    final lat2 = to.latitude * (pi / 180);
    final dLng = (to.longitude - from.longitude) * (pi / 180);
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * (180 / pi) + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: AppSpacing.xxs,
      left: AppSpacing.sm,
      child: StreamBuilder<CompassEvent>(
        stream: FlutterCompass.events,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();

          final compassBearing = snapshot.data!.heading ?? 0.0;
          double bearing = 0.0;
          if (userLocation != null && destination != null) {
            bearing = _bearingToDestination(userLocation!, destination!);
          }

          double relative = bearing - compassBearing;
          if (relative > 180) relative -= 360;
          if (relative < -180) relative += 360;

          return Material(
            elevation: AppSpacing.sm,
            shape: const CircleBorder(),
            child: Container(
              width: AEDMapUIConstants.compassControlSize,
              height: AEDMapUIConstants.compassControlSize,
              decoration: AppDecorations.mapControl(),
              child: Transform.rotate(
                angle: relative * (pi / 180),
                child: const Icon(
                  Icons.navigation,
                  color: AppColors.primary,
                  size: AppSpacing.iconLg - AppSpacing.xs,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDRecenterButton
// Floating recenter / "my location" button.
// ─────────────────────────────────────────────────────────────────────────────

class AEDRecenterButton extends StatelessWidget {
  final bool isSearchingGPS;
  final VoidCallback onPressed;
  final double? top;
  final double? bottom;
  final double? right;
  final double? left;
  final double size;

  const AEDRecenterButton({
    super.key,
    required this.isSearchingGPS,
    required this.onPressed,
    this.top,
    this.bottom,
    this.right,
    this.left,
    this.size = AEDMapUIConstants.recenterButtonSize,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom ?? (top == null ? AEDMapUIConstants.recenterButtonBottom : null),
      right: right,
      left: left,
      child: Tooltip(
        message: 'Re-center map',
        child: Material(
          elevation: AppSpacing.sm,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onPressed();
            },
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: AppDecorations.mapControl(),
              child: isSearchingGPS
                  ? const Padding(
                padding: EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              )
                  : const Icon(
                Icons.my_location,
                color: AppColors.primary,
                size: AppSpacing.iconMd,
              ),
            ),
          ),
        ),
      ),
    );
  }
}