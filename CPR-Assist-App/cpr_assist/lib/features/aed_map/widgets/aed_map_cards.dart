import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../models/aed_models.dart';
import '../services/aed_service.dart';
import '../services/cache_service.dart';
import '../services/location_service.dart';
import 'aed_map_display.dart';
import 'availability_parser.dart';


// ─────────────────────────────────────────────────────────────────────────────
// AEDCard
// Tinted list item showing name, address, distance, ETA and a Start button.
// ─────────────────────────────────────────────────────────────────────────────

class AEDCard extends StatelessWidget {
  final AED aed;
  final AEDMapConfig config;
  final bool userLocationAvailable;
  final Map<int, Map<String, dynamic>> distanceCache;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final bool showButton;
  final bool isFirst;

  const AEDCard({
    super.key,
    required this.aed,
    required this.config,
    required this.userLocationAvailable,
    required this.distanceCache,
    required this.onTap,
    required this.onStart,
    this.showButton = false,
    this.isFirst = false,
  });

  // ── Distance / time resolution ───────────────────────────────────────────

  ({String? distance, String? time, bool isRealData}) _resolve() {
    final selectedMode = config.selectedMode;
    final userLocation = config.userLocation;

    // 1. Cache hit (mode + location still valid)
    if (distanceCache.containsKey(aed.id)) {
      final cached = distanceCache[aed.id]!;
      if (cached['mode'] == selectedMode && userLocation != null) {
        final cachedLoc = cached['location'] as LatLng?;
        if (cachedLoc != null &&
            LocationService.distanceBetween(cachedLoc, userLocation) <
                AppConstants.locationMinMovement * AppSpacing.md) {
          // still close enough — use cache
          return (
          distance: cached['displayDistance'] as String?,
          time: cached['displayTime'] as String?,
          isRealData: cached['isRealData'] as bool? ?? false,
          );
        }
      }
    }

    String? displayDistance;
    String? displayTime;
    bool isRealData = false;

    // 2. Preloaded real route
    final routeKey = '${aed.id}_$selectedMode';
    final preloaded = config.preloadedRoutes[routeKey];
    if (preloaded != null && !preloaded.isOffline) {
      displayDistance = preloaded.distanceText ??
          LocationService.formatDistance(preloaded.actualDistance ?? 0);
      displayTime = preloaded.duration;
      isRealData = true;
    }

    // 3. Cached real distance
    if (!isRealData && userLocation != null) {
      final cached = CacheService.getDistance('aed_${aed.id}_$selectedMode');
      if (cached != null) {
        displayDistance = LocationService.formatDistance(cached);
        displayTime     = LocationService.calculateOfflineETA(cached, selectedMode);
        isRealData      = false;
      }
    }

    // 4. Straight-line estimate
    if (displayDistance == null && userLocation != null) {
      final est = CacheService.getDistance('aed_${aed.id}') ??
          (LocationService.distanceBetween(userLocation, aed.location) *
              AEDService.getTransportModeMultiplier(selectedMode));
      displayDistance = LocationService.formatDistance(est);
      displayTime = LocationService.calculateOfflineETA(est, selectedMode);
    }


    return (distance: displayDistance, time: displayTime, isRealData: isRealData);
  }

  @override
  Widget build(BuildContext context) {
    final r = _resolve();
    return _AEDCardInternal(
      aed: aed,
      displayDistance: r.distance,
      displayTime: r.time,
      isRealData: r.isRealData,
      selectedMode: config.selectedMode,
      userLocationAvailable: userLocationAvailable,
      onTap: onTap,
      onStart: onStart,
      showButton: showButton,
      isFirst: isFirst,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AEDCardInternal — pure UI, no business logic
// ─────────────────────────────────────────────────────────────────────────────

class _AEDCardInternal extends StatelessWidget {
  final AED aed;
  final String? displayDistance;
  final String? displayTime;
  final bool isRealData;
  final String selectedMode;
  final bool userLocationAvailable;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final bool showButton;
  final bool isFirst;

  const _AEDCardInternal({
    required this.aed,
    required this.displayDistance,
    required this.displayTime,
    required this.isRealData,
    required this.selectedMode,
    required this.userLocationAvailable,
    required this.onTap,
    required this.onStart,
    this.showButton = false,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final availabilityStatus =
    AvailabilityParser.parseAvailability(aed.availability);

    final bool isOpenNow = AvailabilityParser.isAvailable() &&
        !availabilityStatus.isUncertain &&
        availabilityStatus.isOpen;

    final Color distanceColor =
    isRealData ? AppColors.textPrimary : AppColors.textDisabled;
    const Color distanceIconColor = AppColors.textSecondary;

    final IconData timeIcon = selectedMode == 'walking'
        ? Icons.directions_walk
        : Icons.directions_car;

    final Color timeColor = isRealData
        ? (selectedMode == 'walking' ? AppColors.aedNavGreen : AppColors.primary)
        : AppColors.textDisabled;
    final Color timeIconColor = isRealData ? timeColor : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(
          bottom: AppSpacing.cardSpacing,
          top: isFirst ? AppSpacing.sm : 0,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + AppSpacing.xs,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        decoration: AppDecorations.tintedCard(
          radius: AEDMapUIConstants.aedCardBorderRadius,
        ).copyWith(
          border: isOpenNow
              ? Border.all(color: AppColors.aedOpenBorder)
              : null,
          boxShadow: isOpenNow
              ? [
            BoxShadow(
              color: AppColors.aedOpenBorder.withValues(alpha: 0.15),
              blurRadius: AppSpacing.xs,
            ),
          ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name
                    Text(
                      aed.name,
                      style: AppTypography.bodyBold(color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Address
                    if (aed.address != null && aed.address != aed.foundation)
                      Text(
                        LocationService.shortenAddress(aed.address!),
                        style: AppTypography.caption(color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    // Distance + time row
                    if (userLocationAvailable &&
                        (displayDistance != null || displayTime != null))
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Row(
                          children: [
                            if (displayDistance != null) ...[
                              const Icon(Icons.near_me,
                                  size: AppSpacing.iconXs,
                                  color: distanceIconColor),
                              const SizedBox(width: AppSpacing.xxs + AppSpacing.xxs),
                              Text(
                                displayDistance!,
                                style: AppTypography.label(color: distanceColor),
                              ),
                            ],
                            if (displayTime != null) ...[
                              if (displayDistance != null) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Container(
                                  width: AppSpacing.dividerThickness,
                                  height: AppSpacing.sm + AppSpacing.xxs,
                                  color: AppColors.textDisabled,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                              ],
                              Icon(timeIcon,
                                  size: AppSpacing.iconXs,
                                  color: timeIconColor),
                              const SizedBox(width: AppSpacing.xxs + AppSpacing.xxs),
                              Text(
                                displayTime!,
                                style: AppTypography.label(color: timeColor),
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
                onPressed: onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(0, 36),          // ← 36 is Flutter's default min height
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                  ),
                  elevation: 0,
                ),
                icon: SvgPicture.asset(
                  'assets/icons/compass.svg',
                  width: AppSpacing.iconXs - AppSpacing.xxs,
                  height: AppSpacing.iconXs - AppSpacing.xxs,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textOnDark,
                    BlendMode.srcIn,
                  ),
                ),
                label: Text(
                  'Start',
                  style: AppTypography.buttonSmall(color: AppColors.textOnDark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDEmptyStateOffline
// ─────────────────────────────────────────────────────────────────────────────

class AEDEmptyStateOffline extends StatelessWidget {
  const AEDEmptyStateOffline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
      decoration: AppDecorations.warningCard(),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_off,
            size: AppSpacing.iconXl,
            color: AppColors.warning,
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          Text(
            'No Internet Connection',
            style: AppTypography.subheading(color: AppColors.warning),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'AED locations require an internet connection to load. '
                'Please check your connection and try again.',
            textAlign: TextAlign.center,
            style: AppTypography.body(color: AppColors.warning),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDEmptyStateLoading
// ─────────────────────────────────────────────────────────────────────────────

class AEDEmptyStateLoading extends StatelessWidget {
  const AEDEmptyStateLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
      child: Column(
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Loading AED Locations',
            style: AppTypography.subheading(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Please wait while we fetch nearby defibrillator locations…',
            textAlign: TextAlign.center,
            style: AppTypography.body(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDCompactInfoColumn
// Shared column used in navigation / active navigation panels for ETA, Distance.
// ─────────────────────────────────────────────────────────────────────────────

class AEDCompactInfoColumn extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool isOffline;
  final bool isEmpty;

  const AEDCompactInfoColumn({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.isOffline = false,
    this.isEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor =
    (isOffline || isEmpty) ? AppColors.textDisabled : AppColors.textPrimary;
    final Color iconColor =
    (isOffline || isEmpty) ? AppColors.textDisabled : AppColors.primary;
    final String displayValue = isEmpty ? '--' : value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: AppSpacing.iconSm + AppSpacing.xxs),
        const SizedBox(height: AppSpacing.xs),
        Text(
          displayValue,
          style: AppTypography.bodyBold(color: textColor),
        ),
        Text(
          label,
          style: AppTypography.label(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDDragHandle
// Reusable drag handle pill shown at the top of bottom sheets / side panels.
// ─────────────────────────────────────────────────────────────────────────────

class AEDDragHandle extends StatelessWidget {
  /// Use [wide] for the wider variant (56 px) in the AED sheet.
  final bool wide;

  const AEDDragHandle({super.key, this.wide = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: wide
            ? AppSpacing.dragHandleWidthWide
            : AppSpacing.dragHandleWidth,
        height: AppSpacing.dragHandleHeight,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm + AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.textHint,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
        ),
      ),
    );
  }
}