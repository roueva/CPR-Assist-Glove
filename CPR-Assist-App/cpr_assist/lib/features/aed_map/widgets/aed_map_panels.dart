import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'package:cpr_assist/core/core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../models/aed_models.dart';
import '../services/cache_service.dart';
import '../services/location_service.dart';
import 'aed_map_cards.dart';
import 'aed_map_display.dart';
import 'aed_map_overlays.dart';
import 'availability_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AEDListPanel  (portrait)
// ─────────────────────────────────────────────────────────────────────────────

class AEDListPanel extends StatefulWidget {
  final AEDMapConfig config;
  final bool userLocationAvailable;
  final Map<int, Map<String, dynamic>> distanceCache;
  final Future<String> syncTimeFuture;
  final Function(LatLng) onSmallMapTap;
  final Function(LatLng) onStartNavigation;
  final Function(LatLng)? onPreviewNavigation;
  final VoidCallback onRecenterPressed;
  final VoidCallback? onKSLTap;

  const AEDListPanel({
    super.key,
    required this.config,
    required this.userLocationAvailable,
    required this.distanceCache,
    required this.syncTimeFuture,
    required this.onSmallMapTap,
    required this.onStartNavigation,
    this.onPreviewNavigation,
    required this.onRecenterPressed,
    this.onKSLTap,
  });

  @override
  State<AEDListPanel> createState() => _AEDListPanelState();
}

class _AEDListPanelState extends State<AEDListPanel> {
  bool _hasScrolledUnderHeader = false;
  bool _showScrollToTop = false;
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const ValueKey('list_portrait'),
      controller: _sheetController,
      initialChildSize: AEDMapUIConstants.portraitListInitial,
      minChildSize: AEDMapUIConstants.portraitListMin,
      maxChildSize: AEDMapUIConstants.portraitListMax,
      builder: (context, scrollController) {
        return SafeArea(
          top: false,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Panel body — offset so KSL / recenter buttons sit above it
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxl + AppSpacing.md),
                child: _PanelContainer(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.sheetRadius),
                  ),
                  child: _buildSheetContent(scrollController),
                ),
              ),

              // KSL logo
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.sm,
                child: _KSLButton(onTap: widget.onKSLTap ?? () {}),
              ),

              // Recenter button
              AEDRecenterButton(
                isSearchingGPS: widget.config.isUsingCachedLocation &&
                    widget.userLocationAvailable,
                onPressed: widget.onRecenterPressed,
                top: AppSpacing.sm,
                right: AppSpacing.sm,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetContent(ScrollController scrollController) {
    if (widget.config.aedLocations.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        children: [
          const AEDDragHandle(wide: true),
          Text('AED Locations', style: AppTypography.heading()),
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),
          if (widget.config.isOffline)
            const AEDEmptyStateOffline()
          else
            const AEDEmptyStateLoading(),
        ],
      );
    }

    final hasUserLocation = widget.config.userLocation != null;
    final sortedAEDs = widget.config.aeds;

    // Split nearest vs rest
    AED? nearestAED;
    List<({AED aed, int? distance})> others = [];

    if (hasUserLocation && sortedAEDs.isNotEmpty) {
      nearestAED = sortedAEDs.first;
      others = sortedAEDs.sublist(1).map((aed) {
        final d = CacheService.getDistance('aed_${aed.id}')?.round() ??
            LocationService.distanceBetween(
                widget.config.userLocation!, aed.location)
                .round();
        return (aed: aed, distance: d);
      }).toList();
    }

    if (!hasUserLocation || nearestAED == null) {
      // No location — flat list
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        children: [
          const AEDDragHandle(wide: true),
          Text('AED List', style: AppTypography.heading()),
          const SizedBox(height: AppSpacing.sm),
          ...sortedAEDs.map((aed) => AEDCard(
            aed: aed,
            config: widget.config,
            userLocationAvailable: widget.userLocationAvailable,
            distanceCache: widget.distanceCache,
            onTap: () => widget.onSmallMapTap(aed.location),
            onStart: () => widget.onStartNavigation(aed.location),
            showButton: true,
          )),
        ],
      );
    }

    // Has location — pinned "Nearest" header + scrollable list
    return Column(
      children: [
        GestureDetector(
          onVerticalDragUpdate: (details) {
            final screenHeight = MediaQuery.sizeOf(context).height;
            final currentSize = _sheetController.size;
            final delta = -details.delta.dy / screenHeight;
            final newSize = (currentSize + delta).clamp(
              AEDMapUIConstants.portraitListMin,
              AEDMapUIConstants.portraitListMax,
            );
            _sheetController.jumpTo(newSize);
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 300) {
              // Fast swipe down → collapse
              _sheetController.animateTo(
                AEDMapUIConstants.portraitListMin,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            } else if (velocity < -300) {
              // Fast swipe up → expand
              _sheetController.animateTo(
                AEDMapUIConstants.portraitListMax,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          },
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              const AEDDragHandle(wide: true),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.md,
                  right: AppSpacing.xs,
                  top: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Nearest AED', style: AppTypography.heading()),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is ScrollUpdateNotification) {
                    final over5 = n.metrics.pixels > 5;
                    final over200 = n.metrics.pixels >
                        AEDMapUIConstants.scrollToTopThreshold;
                    if (over5 != _hasScrolledUnderHeader ||
                        over200 != _showScrollToTop) {
                      setState(() {
                        _hasScrolledUnderHeader = over5;
                        _showScrollToTop = over200;
                      });
                    }
                  }
                  if (n is ScrollEndNotification &&
                      n.metrics.pixels <= 5 &&
                      _hasScrolledUnderHeader) {
                    setState(() => _hasScrolledUnderHeader = false);
                  }
                  return false;
                },
                child: RawScrollbar(
                  controller: scrollController,
                  thumbVisibility: false,
                  thickness: AppSpacing.xxs + AppSpacing.xxs,
                  radius: const Radius.circular(AppSpacing.xs),
                  thumbColor: AppColors.scrollThumb.withValues(alpha: 0.9),
                  fadeDuration: AppConstants.mapAnimationDelay,
                  timeToFade: const Duration(milliseconds: 600),
                  padding: const EdgeInsets.only(
                      right: AppSpacing.xxs, bottom: AppSpacing.md),
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // Nearest card
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                          child: AEDCard(
                            aed: nearestAED,
                            config: widget.config,
                            userLocationAvailable: widget.userLocationAvailable,
                            distanceCache: widget.distanceCache,
                            onTap: () =>
                                widget.onSmallMapTap(nearestAED!.location),
                            onStart: () =>
                                widget.onStartNavigation(nearestAED!.location),
                            showButton: true,
                            isFirst: true,
                          ),
                        ),
                      ),

                      // "Other" header + sync time
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.md,
                            right: AppSpacing.md,
                            top: AppSpacing.sm + AppSpacing.xs,
                            bottom: AppSpacing.sm,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Other', style: AppTypography.heading()),
                              FutureBuilder<String>(
                                future: widget.syncTimeFuture,
                                builder: (context, snap) => snap.hasData
                                    ? Text(
                                  'AEDs updated: ${snap.data}',
                                  style: AppTypography.caption(
                                      color: AppColors.textSecondary),
                                )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Remaining AEDs
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                              (context, i) {
                            final entry = others[i];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md),
                              child: AEDCard(
                                aed: entry.aed,
                                config: widget.config,
                                userLocationAvailable:
                                widget.userLocationAvailable,
                                distanceCache: widget.distanceCache,
                                onTap: () => widget.onPreviewNavigation
                                    ?.call(entry.aed.location),
                                onStart: () => widget
                                    .onStartNavigation(entry.aed.location),
                                showButton: true,
                              ),
                            );
                          },
                          childCount: others.length,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Scroll-to-top FAB
              if (_showScrollToTop)
                Positioned(
                  bottom: AppSpacing.sm + AppSpacing.xs,
                  right: AppSpacing.sm + AppSpacing.xs,
                  child: AnimatedOpacity(
                    opacity: _showScrollToTop ? 1.0 : 0.0,
                    duration: AppConstants.mapAnimationDelay,
                    child: Material(
                      elevation: AppSpacing.xs,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => scrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                        ),
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: AppSpacing.xl + AppSpacing.xs,
                          height: AppSpacing.xl + AppSpacing.xs,
                          decoration: AppDecorations.mapControl(),
                          child: const Icon(
                            Icons.keyboard_arrow_up,
                            color: AppColors.primary,
                            size: AppSpacing.md + AppSpacing.cardSpacing,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDSideListPanel  (landscape)
// ─────────────────────────────────────────────────────────────────────────────

class AEDSideListPanel extends StatelessWidget {
  final AEDMapConfig config;
  final bool userLocationAvailable;
  final Map<int, Map<String, dynamic>> distanceCache;
  final Function(LatLng) onSmallMapTap;
  final Function(LatLng) onStartNavigation;
  final VoidCallback onRecenterPressed;

  const AEDSideListPanel({
    super.key,
    required this.config,
    required this.userLocationAvailable,
    required this.distanceCache,
    required this.onSmallMapTap,
    required this.onStartNavigation,
    required this.onRecenterPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: AEDMapUIConstants.landscapePanelWidth,
          child: DraggableScrollableSheet(
            key: const ValueKey('list_landscape'),
            initialChildSize: AEDMapUIConstants.landscapeListInitial,
            minChildSize: AEDMapUIConstants.landscapeListMin,
            maxChildSize: AEDMapUIConstants.landscapeListMax,
            builder: (context, scrollController) {
              return SafeArea(
                top: false,
                left: false,
                child: _PanelContainer(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppSpacing.sheetRadius),
                    bottomRight: Radius.circular(AppSpacing.sheetRadius),
                    topLeft: Radius.circular(AppSpacing.sheetRadius),
                  ),
                  child: _buildSideContent(scrollController),
                ),
              );
            },
          ),
        ),
        if (!config.hasStartedNavigation)
          AEDRecenterButton(
            isSearchingGPS: false,
            onPressed: onRecenterPressed,
            left: AEDMapUIConstants.landscapeButtonOffset,
            bottom: AEDMapUIConstants.recenterButtonBottom,
          ),
      ],
    );
  }

  Widget _buildSideContent(ScrollController scrollController) {
    return RawScrollbar(
      controller: scrollController,
      thumbVisibility: false,
      thickness: AppSpacing.xxs + AppSpacing.xxs,
      radius: const Radius.circular(AppSpacing.xs),
      thumbColor: AppColors.scrollThumb.withValues(alpha: 0.9),
      fadeDuration: AppConstants.mapAnimationDelay,
      timeToFade: const Duration(milliseconds: 600),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.sm + AppSpacing.xs),
        children: [
          const AEDDragHandle(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                config.userLocation != null ? 'Nearby AEDs' : 'AED List',
                style: AppTypography.heading(),
              ),
              if (config.aeds.isNotEmpty &&
                  config.aeds.first.lastUpdated != null)
                Text(
                  'Updated ${config.aeds.first.formattedLastUpdated}',
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          ...config.aeds.map(
                (aed) => AEDCard(
              aed: aed,
              config: config,
              userLocationAvailable: userLocationAvailable,
              distanceCache: distanceCache,
              onTap: () => onSmallMapTap(aed.location),
              onStart: () => onStartNavigation(aed.location),
              showButton: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDNavigationPanel  (route selected, not yet started)
// ─────────────────────────────────────────────────────────────────────────────

class AEDNavigationPanel extends StatefulWidget {
  final AEDMapConfig config;
  final bool userLocationAvailable;
  final bool isSidePanel;
  final Map<int, Map<String, dynamic>> distanceCache;
  final Function(LatLng) onStartNavigation;
  final VoidCallback? onCancelNavigation;
  final Function(LatLng)? onExternalNavigation;
  final Function(String) onTransportModeSelected;
  final VoidCallback onRecenterPressed;
  final void Function(AED aed) onShowShareDialog;
  final void Function(String url, String title) onOpenWebView;

  const AEDNavigationPanel({
    super.key,
    required this.config,
    required this.userLocationAvailable,
    required this.isSidePanel,
    required this.distanceCache,
    required this.onStartNavigation,
    this.onCancelNavigation,
    this.onExternalNavigation,
    required this.onTransportModeSelected,
    required this.onRecenterPressed,
    required this.onShowShareDialog,
    required this.onOpenWebView,
  });

  @override
  State<AEDNavigationPanel> createState() => _AEDNavigationPanelState();
}

class _AEDNavigationPanelState extends State<AEDNavigationPanel> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.config.selectedAED == null) return const SizedBox.shrink();

    final aed = _findSelectedAED();
    final isOfflineRoute = widget.config.navigationLine?.points.isEmpty ?? true;

// WITH:
    Widget content(ScrollController sc) => SafeArea(
      top: false,
      left: widget.isSidePanel ? false : true,
      child: _PanelContainer(
        borderRadius: widget.isSidePanel
            ? const BorderRadius.only(
          topRight: Radius.circular(AppSpacing.sheetRadius),
          bottomRight: Radius.circular(AppSpacing.sheetRadius),
          topLeft: Radius.circular(AppSpacing.sheetRadius),
        )
            : const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.sheetRadius)),
        child: Column(
          children: [
            // ── Fixed header ──────────────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                final screenHeight = MediaQuery.sizeOf(context).height;
                final delta = -details.delta.dy / screenHeight;
                final newSize = (_sheetController.size + delta).clamp(
                  AEDMapUIConstants.portraitNavMin,
                  AEDMapUIConstants.portraitNavMax,
                );
                _sheetController.jumpTo(newSize);
              },
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 300) {
                  _sheetController.animateTo(
                    AEDMapUIConstants.portraitNavMin,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                } else if (velocity < -300) {
                  _sheetController.animateTo(
                    AEDMapUIConstants.portraitNavMax,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  const AEDDragHandle(wide: true),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.xs,
                      top: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                aed.name,
                                textAlign: TextAlign.center,
                                style: AppTypography.heading(size: 17),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (aed.address != null && aed.address!.isNotEmpty)
                                Text(
                                  aed.address!,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.caption(color: AppColors.textDisabled),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary),
                          tooltip: 'Close',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.onCancelNavigation?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Scrollable body ───────────────────────────────
            Expanded(
              child: CustomScrollView(
                controller: sc,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm + AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusBanners(isOfflineRoute),
                          _buildActionRow(context, aed, isOfflineRoute),
                          const SizedBox(height: AppSpacing.md),
                          if (widget.userLocationAvailable &&
                              widget.config.userLocation != null)
                            _buildInfoRow(isOfflineRoute),
                          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                          _buildAvailability(aed),
                          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                          _buildWebLinks(context, aed),
                          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.isSidePanel) {
      return Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: AEDMapUIConstants.landscapePanelWidth,
            child: DraggableScrollableSheet(
              initialChildSize: 1,
              minChildSize: 0.3,
              maxChildSize: 1.0,
              builder: (context, sc) => content(sc),
            ),
          ),
          AEDRecenterButton(
            isSearchingGPS: false,
            onPressed: widget.onRecenterPressed,
            left: AEDMapUIConstants.landscapeButtonOffset,
            bottom: AEDMapUIConstants.recenterButtonBottom,
          ),
        ],
      );
    }

    return DraggableScrollableSheet(
      key: const ValueKey('nav_portrait'),
      controller: _sheetController,
      initialChildSize: AEDMapUIConstants.portraitNavInitial,
      minChildSize: AEDMapUIConstants.portraitNavMin,
      maxChildSize: AEDMapUIConstants.portraitNavMax,
      builder: (context, sc) => content(sc),
    );
  }

  AED _findSelectedAED() => widget.config.aeds.firstWhere(
        (a) =>
    a.location.latitude == widget.config.selectedAED?.latitude &&
        a.location.longitude == widget.config.selectedAED?.longitude,
    orElse: () => AED(
      id: -1,
      foundation: 'Unknown AED',
      address: 'Selected AED',
      location: widget.config.selectedAED!,
    ),
  );

  Widget _buildStatusBanners(bool isOfflineRoute) {
    final showBanner = (isOfflineRoute && widget.config.isOffline) || !widget.userLocationAvailable;
    final showCachedBanner =
        widget.config.isUsingCachedLocation && widget.userLocationAvailable;

    if (!showBanner && !showCachedBanner) return const SizedBox.shrink();

    return Column(
      children: [
        if (showBanner)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + AppSpacing.xs,
                vertical: AppSpacing.sm + AppSpacing.xxs),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: AppDecorations.primaryCard(
                radius: AppSpacing.cardRadiusMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.userLocationAvailable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.cardSpacing),
                    child: Row(
                      children: [
                        const Icon(Icons.location_off,
                            size: AppSpacing.iconXs,
                            color: AppColors.primary),
                        const SizedBox(width: AppSpacing.cardSpacing),
                        Expanded(
                          child: Text(
                            'No GPS · compass direction only',
                            style: AppTypography.caption(
                                color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.config.isOffline)
                  Row(
                    children: [
                      const Icon(Icons.wifi_off,
                          size: AppSpacing.iconXs,
                          color: AppColors.primary),
                      const SizedBox(width: AppSpacing.cardSpacing),
                      Expanded(
                        child: Text(
                          'No internet · distances are estimates',
                          style: AppTypography.caption(
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (showCachedBanner)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: AppDecorations.primaryCard(
                radius: AppSpacing.cardRadiusMd),
            child: Row(
              children: [
                const SizedBox(
                  width: AppSpacing.md,
                  height: AppSpacing.md,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Using cached location, getting current position…',
                    style: AppTypography.caption(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionRow(
      BuildContext context, AED aed, bool isOfflineRoute) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ElevatedButton.icon(
            onPressed: widget.config.selectedAED != null
                ? () {
              if (widget.config.hasStartedNavigation) {
                widget.onCancelNavigation?.call();
              } else {
                widget.onStartNavigation(widget.config.selectedAED!);
              }
            }
                : null,
            icon: Icon(
              widget.config.hasStartedNavigation ? Icons.stop : Icons.navigation,
              size: AppSpacing.iconSm + AppSpacing.xxs,
            ),
            label: Text(
              widget.config.hasStartedNavigation
                  ? 'Stop Navigation'
                  : 'Start Navigation',
              style: AppTypography.buttonPrimary(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Share button
        _IconActionButton(
          icon: Icons.share,
          tooltip: 'Share AED Location',
          enabled: aed.id != -1,
          onTap: () => widget.onShowShareDialog(aed),
        ),
        const SizedBox(width: AppSpacing.sm),
        // External maps button
        _IconActionButton(
          icon: Icons.open_in_new,
          tooltip: 'Open in External Maps',
          enabled: widget.config.selectedAED != null,
          onTap: () => widget.onExternalNavigation?.call(widget.config.selectedAED!),
        ),
      ],
    );
  }

  Widget _buildInfoRow(bool isOfflineRoute) {
    final isTooOld = widget.config.locationAge != null &&
        widget.config.locationAge! >= AppConstants.locationStaleHours;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(color: AppColors.screenBgGrey),
      child: Row(
        children: [
          Expanded(
            child: AEDCompactInfoColumn(
              icon: Icons.access_time,
              value: widget.config.estimatedTime,
              label: 'ETA',
              isOffline: isOfflineRoute || widget.config.isOffline,
              isEmpty: isTooOld,
            ),
          ),
          Container(
              width: AppSpacing.dividerThickness,
              height: AppSpacing.xxl - AppSpacing.xs,
              color: AppColors.divider),
          Expanded(
            child: AEDCompactInfoColumn(
              icon: Icons.near_me,
              value: widget.config.distance != null
                  ? LocationService.formatDistance(widget.config.distance!)
                  : 'N/A',
              label: 'Distance',
              isOffline: isOfflineRoute || widget.config.isOffline,
              isEmpty: isTooOld,
            ),
          ),
          Container(
              width: AppSpacing.dividerThickness,
              height: AppSpacing.xxl - AppSpacing.xs,
              color: AppColors.divider),
          Expanded(
            child: _TransportModeSelector(
              selectedMode: widget.config.selectedMode,
              onModeSelected: widget.onTransportModeSelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailability(AED aed) {
    if (!AvailabilityParser.isAvailable() ||
        aed.availability == null ||
        aed.availability!.isEmpty) {
      return const SizedBox.shrink();
    }
    return _ExpandableAvailability(
      parsedStatus: AvailabilityParser.parseAvailability(aed.availability),
      rawAvailabilityText: aed.availability!,
    );
  }

  Widget _buildWebLinks(BuildContext context, AED aed) {
    if (aed.id == -1 || !aed.hasWebpage) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => widget.onOpenWebView(aed.aedWebpage!, aed.name),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
              decoration: AppDecorations.primaryCard(
                  radius: AppSpacing.cardRadiusMd),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary,
                      size: AppSpacing.iconSm),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'View AED Details',
                      style: AppTypography.bodyMedium(color: AppColors.primary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.open_in_browser,
                      color: AppColors.primary,
                      size: AppSpacing.iconXs),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Tooltip(
          message: 'Report Issue',
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onOpenWebView(
                  'https://kidssavelives.gr/epikoinonia/', 'Report Issue');
            },
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
              child: Icon(Icons.flag_outlined,
                  color: AppColors.warning, size: AppSpacing.iconMd),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AEDActiveNavigationPanel  (navigation started)
// ─────────────────────────────────────────────────────────────────────────────

class AEDActiveNavigationPanel extends StatefulWidget  {
  final AEDMapConfig config;
  final bool userLocationAvailable;
  final bool isSidePanel;
  final Function(String) onTransportModeSelected;
  final VoidCallback? onCancelNavigation;
  final VoidCallback? onRecenterNavigation;
  final void Function(String url, String title) onOpenWebView;

  const AEDActiveNavigationPanel({
    super.key,
    required this.config,
    required this.userLocationAvailable,
    required this.isSidePanel,
    required this.onTransportModeSelected,
    this.onCancelNavigation,
    this.onRecenterNavigation,
    required this.onOpenWebView,
  });

  @override
  State<AEDActiveNavigationPanel> createState() => _AEDActiveNavigationPanel();
}

class _AEDActiveNavigationPanel extends State<AEDActiveNavigationPanel> {
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    if (widget.config.selectedAED == null) return const SizedBox.shrink();
    final aed = _findSelectedAED();
    final isOfflineRoute = widget.config.navigationLine?.points.isEmpty ?? true;

    Widget content(ScrollController sc) => SafeArea(
      top: false,
      left: widget.isSidePanel ? false : true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl + AppSpacing.md),
            child: _PanelContainer(
              borderRadius: widget.isSidePanel
                  ? const BorderRadius.only(
                topRight: Radius.circular(AppSpacing.sheetRadius),
                bottomRight: Radius.circular(AppSpacing.sheetRadius),
                topLeft: Radius.circular(AppSpacing.sheetRadius),
              )
                  : const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.sheetRadius)),
              child: Column(
                children: [
                  // ── Fixed header ──────────────────────────────────
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: (details) {
                      final screenHeight = MediaQuery.sizeOf(context).height;
                      final delta = -details.delta.dy / screenHeight;
                      final newSize = (_sheetController.size + delta).clamp(
                        AEDMapUIConstants.portraitActiveNavMin,
                        AEDMapUIConstants.portraitActiveNavMax,
                      );
                      _sheetController.jumpTo(newSize);
                    },
                    onVerticalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity > 300) {
                        _sheetController.animateTo(
                          AEDMapUIConstants.portraitActiveNavMin,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      } else if (velocity < -300) {
                        _sheetController.animateTo(
                          AEDMapUIConstants.portraitActiveNavMax,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        const AEDDragHandle(wide: true),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: AppSpacing.md,
                            right: AppSpacing.xs,
                            top: AppSpacing.sm,
                            bottom: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: AppDecorations.iconCircle(
                                    bg: AppColors.successBg),
                                child: const Icon(
                                  Icons.navigation,
                                  color: AppColors.success,
                                  size: AppSpacing.iconSm + AppSpacing.xxs,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Navigating to AED',
                                      style: AppTypography.caption(
                                          color: AppColors.textSecondary),
                                    ),
                                    Text(
                                      aed.name,
                                      style: AppTypography.bodyBold(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (aed.address != null &&
                                        aed.address!.isNotEmpty)
                                      Text(
                                        aed.address!,
                                        style: AppTypography.caption(
                                            color: AppColors.textDisabled),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: AppColors.textSecondary),
                                tooltip: 'Stop Navigation',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  widget.onCancelNavigation?.call();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Scrollable body ───────────────────────────────
                  Expanded(
                    child: CustomScrollView(
                      controller: sc,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.sm + AppSpacing.xs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: AppSpacing.md),
                                if (isOfflineRoute || widget.config.isOffline)
                                  _buildOfflineBanner(),
                                _buildAvailability(aed),
                                _buildInfoRow(isOfflineRoute),
                                const SizedBox(height: AppSpacing.md),
                                _buildWebLinks(context, aed),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Recenter chip and Compass stay exactly as before
          if (widget.config.showRecenterButton)
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: Material(
                elevation: AppSpacing.sm,
                borderRadius:
                BorderRadius.circular(AppSpacing.buttonRadiusLg),
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    widget.onRecenterNavigation?.call();
                  },
                  borderRadius:
                  BorderRadius.circular(AppSpacing.buttonRadiusLg),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + AppSpacing.xs,
                        vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(
                          AppSpacing.buttonRadiusLg),
                    ),
                    child: Text(
                      'Recenter',
                      style: AppTypography.buttonSecondary(),
                    ),
                  ),
                ),
              ),
            ),

          // Compass
          if (widget.config.hasStartedNavigation &&
              widget.config.navigationLine == null)
            AEDCompassIndicator(
              userLocation: widget.config.userLocation,
              destination: widget.config.selectedAED,
            ),
        ],
      ),
    );

    if (widget.isSidePanel) {
      return Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: AEDMapUIConstants.landscapePanelWidth,
        child: DraggableScrollableSheet(
          key: const ValueKey('active_nav_landscape'),
          initialChildSize: AEDMapUIConstants.portraitActiveNavInitial,
          minChildSize: AEDMapUIConstants.portraitActiveNavMin,
          maxChildSize: AEDMapUIConstants.portraitActiveNavMax,
          builder: (context, sc) => content(sc),
        ),
      );
    }

    return DraggableScrollableSheet(
      key: const ValueKey('active_nav_portrait'),
      controller: _sheetController,
      initialChildSize: AEDMapUIConstants.portraitActiveNavInitial,
      minChildSize: AEDMapUIConstants.portraitActiveNavMin,
      maxChildSize: AEDMapUIConstants.portraitActiveNavMax,
      builder: (context, sc) => content(sc),
    );
  }

  AED _findSelectedAED() => widget.config.aeds.firstWhere(
        (a) =>
    a.location.latitude == widget.config.selectedAED?.latitude &&
        a.location.longitude == widget.config.selectedAED?.longitude,
    orElse: () => AED(
      id: -1,
      foundation: 'Unknown AED',
      address: 'Selected AED',
      location: widget.config.selectedAED!,
    ),
  );


  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration:
      AppDecorations.warningCard(radius: AppSpacing.cardRadiusSm),
      child: Row(
        children: [
          const Icon(Icons.wifi_off,
              size: AppSpacing.md, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No internet · distances are estimates',
              style: AppTypography.caption(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailability(AED aed) {
    if (!AvailabilityParser.isAvailable() ||
        aed.availability == null ||
        aed.availability!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: _ExpandableAvailability(
        parsedStatus: AvailabilityParser.parseAvailability(aed.availability),
        rawAvailabilityText: aed.availability!,
      ),
    );
  }

  Widget _buildInfoRow(bool isOfflineRoute) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
      decoration: AppDecorations.card(color: AppColors.screenBgGrey),
      child: Row(
        children: [
          Expanded(
            child: AEDCompactInfoColumn(
              icon: Icons.access_time,
              value: widget.config.estimatedTime,
              label: 'ETA',
              isOffline: isOfflineRoute || widget.config.isOffline,
            ),
          ),
          Container(
              width: AppSpacing.dividerThickness,
              height: AppSpacing.xxl - AppSpacing.xs,
              color: AppColors.divider),
          Expanded(
            child: AEDCompactInfoColumn(
              icon: Icons.near_me,
              value: widget.config.distance != null
                  ? LocationService.formatDistance(widget.config.distance!)
                  : 'N/A',
              label: 'Distance',
              isOffline: isOfflineRoute || widget.config.isOffline,
            ),
          ),
          Container(
              width: AppSpacing.dividerThickness,
              height: AppSpacing.xxl - AppSpacing.xs,
              color: AppColors.divider),
          Expanded(
            child: _TransportModeSelector(
              selectedMode: widget.config.selectedMode,
              onModeSelected: widget.onTransportModeSelected,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebLinks(BuildContext context, AED aed) {
    if (aed.id == -1 || !aed.hasWebpage) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => widget.onOpenWebView(aed.aedWebpage!, aed.name),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + AppSpacing.xs),
              decoration: AppDecorations.primaryCard(
                  radius: AppSpacing.cardRadiusMd),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary,
                      size: AppSpacing.iconSm),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'View AED Details',
                      style: AppTypography.bodyMedium(
                          color: AppColors.primary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.open_in_browser,
                      color: AppColors.primary,
                      size: AppSpacing.iconXs),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Tooltip(
          message: 'Report Issue',
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onOpenWebView(
                  'https://kidssavelives.gr/epikoinonia/', 'Report Issue');
            },
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
              child: Icon(Icons.flag_outlined,
                  color: AppColors.warning, size: AppSpacing.iconMd),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private shared widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Consistent panel container with clip + shadow.
class _PanelContainer extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const _PanelContainer({required this.child, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            blurRadius: AppSpacing.sm,
            color: AppColors.shadowMedium,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Square icon action button (share, external maps).
class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback? onTap;

  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppSpacing.xxl + AppSpacing.xxs,
      width: AppSpacing.xxl + AppSpacing.xxs,
      decoration: AppDecorations.primaryCard(radius: AppSpacing.buttonRadius),
      child: IconButton(
        onPressed: enabled ? onTap : null,
        tooltip: tooltip,
        icon: Icon(
          icon,
          color: enabled ? AppColors.primary : AppColors.textDisabled,
          size: AppSpacing.iconSm + AppSpacing.xxs,
        ),
      ),
    );
  }
}

/// KSL logo button.
class _KSLButton extends StatelessWidget {
  final VoidCallback onTap;

  const _KSLButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Kids Save Lives Foundation',
      child: GestureDetector(
        onTap: onTap,
        child: Image.asset(
          'assets/icons/kids_save_lives_logo.png',
          width: AEDMapUIConstants.logoSize + AppSpacing.sm + AppSpacing.xxs,
          height: AEDMapUIConstants.logoSize + AppSpacing.sm + AppSpacing.xxs,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ExpandableAvailability  (unchanged widget, kept here to avoid new file)
// ─────────────────────────────────────────────────────────────────────────────

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
    Color statusColor;
    IconData icon;

    if (status.isUncertain) {
      statusColor = AppColors.textSecondary;
      icon = Icons.schedule;
    } else if (status.isOpen) {
      statusColor = AppColors.clusterGreen;
      icon = Icons.check_circle_outline;
    } else {
      statusColor = AppColors.error;
      icon = Icons.cancel_outlined;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
          child: Row(
            children: [
              Icon(icon, size: AppSpacing.md, color: statusColor),
              const SizedBox(width: AppSpacing.cardSpacing),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: status.displayText,
                        style: AppTypography.bodyMedium(color: statusColor),
                      ),
                      if (status.detailText != null && !status.isUncertain)
                        TextSpan(
                          text: ' · ${status.detailText}',
                          style: AppTypography.body(
                              color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                color: AppColors.textDisabled,
                size: AppSpacing.md + AppSpacing.xs,
              ),
            ],
          ),
        ),
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.md + AppSpacing.cardSpacing,
              top: AppSpacing.xs,
              right: AppSpacing.lg,
            ),
            child: Text(
              widget.rawAvailabilityText,
              style: AppTypography.caption(color: AppColors.textSecondary)
                  .copyWith(fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TransportModeSelector  (unchanged widget, kept here)
// ─────────────────────────────────────────────────────────────────────────────

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

    return PopupMenuButton<String>(
      onSelected: (mode) {
        HapticFeedback.selectionClick();
        onModeSelected(mode);
      },
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
      offset: const Offset(0, AppSpacing.xxl - AppSpacing.xxs),
      tooltip: 'Change Mode',
      itemBuilder: (context) => [
        _menuItem(context, 'walking', Icons.directions_walk, 'Walking'),
        _menuItem(context, 'driving', Icons.directions_car, 'Driving'),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isWalking ? Icons.directions_walk : Icons.directions_car,
              color: AppColors.aedNavGreen,
              size: AppSpacing.iconSm + AppSpacing.xxs,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isWalking ? 'Walking' : 'Driving',
              style: AppTypography.bodyBold(),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Mode',
                    style: AppTypography.label(
                        color: AppColors.textSecondary)),
                const SizedBox(width: AppSpacing.xxs),
                const Icon(Icons.arrow_drop_down,
                    size: AppSpacing.iconXs,
                    color: AppColors.textDisabled),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      BuildContext context, String value, IconData icon, String label) {
    final isSelected = selectedMode == value;
    return PopupMenuItem<String>(
      value: value,
      height: AppSpacing.xxl - AppSpacing.xs,
      child: Row(
        children: [
          Icon(icon,
              color:
              isSelected ? AppColors.aedNavGreen : AppColors.textSecondary,
              size: AppSpacing.iconSm + AppSpacing.xxs),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Text(
            label,
            style: isSelected
                ? AppTypography.bodyBold(color: AppColors.aedNavGreen)
                : AppTypography.body(color: AppColors.textSecondary),
          ),
          if (isSelected) ...[
            const Spacer(),
            const Icon(Icons.check,
                color: AppColors.aedNavGreen,
                size: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}