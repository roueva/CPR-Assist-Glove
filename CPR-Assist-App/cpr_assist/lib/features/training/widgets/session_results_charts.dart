part of 'session_results.dart';




// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 — Charts
// ═════════════════════════════════════════════════════════════════════════════

class _TrainingChartsTab extends StatelessWidget {
  final SessionDetail? detail;
  final bool           hasGraphs;
  final double         targetDepthMin;
  final double         targetDepthMax;

  const _TrainingChartsTab({
    required this.detail,
    required this.hasGraphs,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasGraphs) {
      return _EmptyState(
        icon:  Icons.show_chart_rounded,
        title: 'No chart data available',
        body:              'History sessions do not carry the full compression stream.',
      );
    }

    final d      = detail!;
    final events = d.compressions;


    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Chart 1 — Depth waveform (already correct, keep as-is)
          _DepthRecoilChartCard(
            events:         events,
            targetDepthMin: targetDepthMin,
            targetDepthMax: targetDepthMax,
          ),
          const SizedBox(height: AppSpacing.md),

          // Chart 2 — Rate (new _RateScrollChart, not _GraphCard)
          _RateScrollChartCard(events: events),

          // Chart 3 — Depth trend (new _DepthTrendFullChart)
          if (events.length >= 5) ...[
            const SizedBox(height: AppSpacing.md),
            _DepthTrendChartCard(
              events:         events,
              targetDepthMin: targetDepthMin,
              targetDepthMax: targetDepthMax,
            ),
          ],

          // Chart 4 — Rescuer HR (new _HeartRateFullChart)
          if (d.rescuerVitals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _HeartRateChartCard(
              vitals:            d.rescuerVitals,
              sessionLengthSecs: events.isEmpty ? 0 : events.last.timestampSec,
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CHARTS — drop-in replacement for everything from
//   "// ── Chart 3 — Fatigue trend" comment inside _TrainingChartsTab.build()
//   down through the end of _HeartRateFullChart
//
// Changes vs previous version:
//   • Shared CprWindowDropdown widget — pretty, includes "All" option
//   • Shared CprScrollBar widget
//   • All charts use full cached spots + minX/maxX viewport (no filtering)
//   • Depth chart: axis labels for 5/6 cm explicit on left axis, recoil label
//     inside band, no peak shrinking, prettier scrollbar, black tooltip,
//     compression # in tooltip, peak=depth colour, valley=recoil colour
//   • Depth chart: passes targetDepthMin/Max through so pediatric works
//   • Rate chart: minY=80 maxY=140, same no-filter approach, 10s default window
//   • Rate chart: prettier dropdown + scroll
//   • Depth trend: axis starts near target range, dots per point, filled area
//     fixed, scroll + dropdown (full session default), black tooltip
//   • Heart rate: dots per point, scroll + dropdown (full session default),
//     black tooltip
//   • All charts: non-overlapping time axis labels that push apart on scroll
// ═════════════════════════════════════════════════════════════════════════════



// _DepthRecoilChart
// ═════════════════════════════════════════════════════════════════════════════


class _DepthRecoilChartCard extends StatefulWidget {
  final List<CompressionEvent> events;
  final double targetDepthMin;
  final double targetDepthMax;
  final bool   compact;

  const _DepthRecoilChartCard({
    required this.events,
    required this.targetDepthMin,
    required this.targetDepthMax,
    this.compact = false,
  });

  @override
  State<_DepthRecoilChartCard> createState() => _DepthRecoilChartCardState();
}

class _DepthRecoilChartCardState extends State<_DepthRecoilChartCard> {
  double  _windowStart = 0.0;
  double? _windowSecs  = kCprDefaultWindowSecs;

  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;
  double get _effectiveWindow => _windowSecs ?? _sessionLength;

  void _onWindowChanged(double? v) {
    setState(() {
      _windowSecs = v;
      if (v != null && _sessionLength > v) {
        _windowStart = _windowStart.clamp(0.0, _sessionLength - v);
      } else {
        _windowStart = 0.0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title:    'Compression Depth',
      subtitle: 'Green band = target depth \nAmber band = recoil achieved',
      lineColor: AppColors.primary,
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: _DepthRecoilChart(
        events:         widget.events,
        targetDepthMin: widget.targetDepthMin,
        targetDepthMax: widget.targetDepthMax,
        windowStart:    _windowStart,
        windowSecs:     _windowSecs,
        compact:        widget.compact,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
      ),
    );
  }
}

class _DepthRecoilChart extends StatefulWidget {
  final List<CompressionEvent> events;
  final double targetDepthMin;
  final double targetDepthMax;
  final double  windowStart;
  final double? windowSecs;
  final bool    compact;
  final void Function(double) onWindowStartChanged;

  const _DepthRecoilChart({
    required this.events,
    required this.targetDepthMin,
    required this.targetDepthMax,
    required this.windowStart,
    required this.windowSecs,
    required this.onWindowStartChanged,
    this.compact = false,
  });

  @override
  State<_DepthRecoilChart> createState() => _DepthRecoilChartState();
}

class _DepthRecoilChartState extends State<_DepthRecoilChart> {
  List<FlSpot>? _cachedWaveform;

  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;
  double get _effectiveWindow => widget.windowSecs ?? _sessionLength;
  double get _windowEnd =>
      widget.windowSecs == null ? _sessionLength : widget.windowStart + widget.windowSecs!;
  bool get _canScroll =>
      widget.windowSecs != null && _sessionLength > widget.windowSecs!;

  @override
  void didUpdateWidget(_DepthRecoilChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) _cachedWaveform = null;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canScroll) return;
    final secsPerPx = (_sessionLength - _effectiveWindow) / 260.0;
    final newStart = (widget.windowStart - d.delta.dx * secsPerPx)
        .clamp(0.0, _sessionLength - _effectiveWindow);
    widget.onWindowStartChanged(newStart);
  }

  // ── Tooltip ───────────────────────────────────────────────────────────────

  LineTouchData _buildTouchData() {
    return LineTouchData(
      touchSpotThreshold: 24,
      getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
          .map((_) => TouchedSpotIndicatorData(
        FlLine(
            color: AppColors.primary.withValues(alpha: 0.25),
            strokeWidth: 1),
        FlDotData(show: false),
      ))
          .toList(),
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppColors.white,
        tooltipBorder: const BorderSide(color: AppColors.divider),
        tooltipBorderRadius: BorderRadius.circular(10),
        tooltipPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((s) {
            CompressionEvent? nearest;
            double minDist = double.infinity;
            for (final e in widget.events) {
              final dist = (e.timestampSec - s.x).abs();
              if (dist < minDist) {
                minDist = dist;
                nearest = e;
              }
            }
            if (nearest == null) return null;

            final compIdx = widget.events.indexOf(nearest) + 1;
            final secs    = nearest.timestampSec.toInt();
            final mm      = (secs ~/ 60).toString();
            final ss      = (secs % 60).toString().padLeft(2, '0');

            final distToPeak   = (s.y - nearest.depth).abs();
            final valleyY      =
            nearest.valleyDepth > 0 ? nearest.valleyDepth : 0.0;
            final distToValley = (s.y - valleyY).abs();
            final isPeak       = distToPeak <= distToValley;

            if (isPeak) {
              final depthOk = nearest.depth >= widget.targetDepthMin &&
                  nearest.depth <= widget.targetDepthMax;
              final depthColor =
              depthOk ? AppColors.success : AppColors.error;
              return LineTooltipItem('', const TextStyle(), children: [
                TextSpan(
                  text: '$mm:$ss  •  #$compIdx\n',
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
                TextSpan(
                  text: '${nearest.depth.toStringAsFixed(1)} cm',
                  style: AppTypography.bodyBold(size: 14, color: depthColor),
                ),
                TextSpan(
                  text: '  depth',
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
              ]);
            } else {
              final recoilOk = nearest.recoilAchieved;
              final recoilColor =
              recoilOk ? AppColors.success : AppColors.error;
              final valleyStr =
              valleyY > 0 ? valleyY.toStringAsFixed(1) : '0.0';
              return LineTooltipItem('', const TextStyle(), children: [
                TextSpan(
                  text: '$mm:$ss  •  #$compIdx\n',
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
                TextSpan(
                  text: '$valleyStr cm',
                  style:
                  AppTypography.bodyBold(size: 14, color: recoilColor),
                ),
                TextSpan(
                  text: '  recoil',
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
              ]);
            }
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) return const SizedBox.shrink();

    _cachedWaveform ??= buildCprWaveform(widget.events);
    final allSpots = _cachedWaveform!;
    final minX = widget.windowStart;
    const double kReserved = 25.0;
    final maxX = _windowEnd;
    final tMin = widget.targetDepthMin;
    final tMax = widget.targetDepthMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ─────────────────────────────────────────────────
        GestureDetector(
          onHorizontalDragUpdate: _canScroll ? _onDragUpdate : null,
          child: SizedBox(
            height: context.isLandscape ? 80 : (widget.compact ? 110 : 140),
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 8,
                minX: minX,
                maxX: maxX,
                clipData: const FlClipData.all(),
                backgroundColor: AppColors.screenBgGrey.withValues(alpha: 0.5),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppColors.divider,
                    strokeWidth: AppSpacing.dividerThickness,
                  ),
                ),
                borderData: FlBorderData(show: false),
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    HorizontalRangeAnnotation(
                      y1: tMin,
                      y2: tMax,
                      color: AppColors.success.withValues(alpha: 0.09),
                    ),
                    HorizontalRangeAnnotation(
                      y1: 0,
                      y2: kCprRecoilThresholdCm,
                      color: AppColors.warning.withValues(alpha: 0.10),
                    ),
                  ],
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: tMax,
                      color: AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                    HorizontalLine(
                      y: tMin,
                      color: AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                    HorizontalLine(
                      y: kCprRecoilThresholdCm,
                      color: AppColors.warning.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [3, 5],
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: kReserved,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value > 8) return const SizedBox.shrink();
                        if ((value - value.roundToDouble()).abs() > 0.01) {
                          return const SizedBox.shrink();
                        }
                        final isTarget = (value - tMin).abs() < 0.05 ||
                            (value - tMax).abs() < 0.05;
                        return Text(
                          value.toInt().toString(),
                          textAlign: TextAlign.center,
                          style: AppTypography.caption(
                            color: isTarget ? AppColors.success : AppColors.textDisabled,
                          ).copyWith(fontWeight: isTarget ? FontWeight.bold : FontWeight.normal),
                        );
                      },
                    ),
                  ),
                  bottomTitles:
                  buildCprTimeAxis(
                    minX: minX,
                    maxX: maxX,
                    maxLabels: 7,
                    sessionLength: _sessionLength,
                    windowStart: widget.windowStart,
                    windowSecs: widget.windowSecs,
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: allSpots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    preventCurveOverShooting: true,
                    preventCurveOvershootingThreshold: 0.5,
                    color: AppColors.primary,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withValues(alpha: 0.05),
                    ),
                  ),
                ],
                lineTouchData: _buildTouchData(),
              ),
            ),
          ),
        ),
        // scrollbar left-padded to sit under the plot area only
        Padding(
          padding: const EdgeInsets.only(left: kReserved),
          child: CprScrollBar(
            windowStart: widget.windowStart,
            sessionLength: _sessionLength,
            windowSecs: _effectiveWindow,
          ),
        ),
      ],
    );
  }
}

// ── _RateScrollChartCard ───────────────────────────────────────────────────
class _RateScrollChartCard extends StatefulWidget {
  final List<CompressionEvent> events;
  final bool compact;

  const _RateScrollChartCard({required this.events, this.compact = false});
  @override
  State<_RateScrollChartCard> createState() => _RateScrollChartCardState();
}


class _RateScrollChartCardState extends State<_RateScrollChartCard> {
  double  _windowStart = 0.0;
  double? _windowSecs  = kCprDefaultWindowSecs;
  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;
  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title:    'Compression Rate',
      subtitle: 'Green band = 100–120 BPM',
      lineColor: AppColors.success,
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged: (v) => setState(() {
          _windowSecs = v;
          if (v != null && _sessionLength > v) {
            _windowStart = _windowStart.clamp(0.0, _sessionLength - v);
          } else {
            _windowStart = 0.0;
          }
        }),
      ),
      child: _RateScrollChart(
        events:       widget.events,
        windowStart:  _windowStart,
        windowSecs:   _windowSecs,
        compact:      widget.compact,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
      ),
    );
  }
}

// ── _DepthTrendChartCard ───────────────────────────────────────────────────
class _DepthTrendChartCard extends StatefulWidget {
  final List<CompressionEvent> events;
  final double targetDepthMin;
  final double targetDepthMax;
  final bool compact;

  const _DepthTrendChartCard({
    required this.events,
    required this.targetDepthMin,
    required this.targetDepthMax,
    this.compact = false,
  });
  @override
  State<_DepthTrendChartCard> createState() => _DepthTrendChartCardState();
}


class _DepthTrendChartCardState extends State<_DepthTrendChartCard> {
  double  _windowStart = 0.0;
  double? _windowSecs;
  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;
  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title:    'Depth Trend',
      subtitle: '5-compression rolling average',
      lineColor: AppColors.warning,
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged: (v) => setState(() {
          _windowSecs = v;
          if (v != null && _sessionLength > v) {
            _windowStart = _windowStart.clamp(0.0, _sessionLength - v);
          } else {
            _windowStart = 0.0;
          }
        }),
      ),
      child: _DepthTrendFullChart(
        events:         widget.events,
        targetDepthMin: widget.targetDepthMin,
        targetDepthMax: widget.targetDepthMax,
        windowStart:    _windowStart,
        windowSecs:     _windowSecs,
        compact:        widget.compact,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
      ),
    );
  }
}

// ── _HeartRateChartCard ────────────────────────────────────────────────────
class _HeartRateChartCard extends StatefulWidget {
  final List<RescuerVitalSnapshot> vitals;
  final double sessionLengthSecs;
  const _HeartRateChartCard({
    required this.vitals,
    required this.sessionLengthSecs,
  });
  @override
  State<_HeartRateChartCard> createState() => _HeartRateChartCardState();
}


class _HeartRateChartCardState extends State<_HeartRateChartCard> {
  double  _windowStart = 0.0;
  double? _windowSecs;
  double get _sessionLength =>
      widget.vitals.isEmpty ? 0 : widget.sessionLengthSecs;
  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title:    'Rescuer Heart Rate',
      subtitle: 'Rising trend = increasing physical load',
      lineColor: AppColors.warning,
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged: (v) => setState(() {
          _windowSecs = v;
          if (v != null && _sessionLength > v) {
            _windowStart = _windowStart.clamp(0.0, _sessionLength - v);
          } else {
            _windowStart = 0.0;
          }
        }),
      ),
      child: _HeartRateFullChart(
        vitals:            widget.vitals,
        sessionLengthSecs: widget.sessionLengthSecs,
        windowStart:       _windowStart,
        windowSecs:        _windowSecs,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _RateScrollChart
// ═════════════════════════════════════════════════════════════════════════════

class _RateScrollChart extends StatefulWidget {
  final List<CompressionEvent> events;
  final double  windowStart;
  final double? windowSecs;
  final void Function(double) onWindowStartChanged;
  final bool compact;

  const _RateScrollChart({
    required this.events,
    required this.windowStart,
    required this.windowSecs,
    required this.onWindowStartChanged,
    this.compact = false,
  });

  @override
  State<_RateScrollChart> createState() => _RateScrollChartState();
}

class _RateScrollChartState extends State<_RateScrollChart> {
  List<FlSpot>? _cachedSpots;

  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;
  double get _effectiveWindow => widget.windowSecs ?? _sessionLength;
  double get _windowEnd =>
      widget.windowSecs == null ? _sessionLength : widget.windowStart + widget.windowSecs!;
  bool get _canScroll =>
      widget.windowSecs != null && _sessionLength > widget.windowSecs!;

  @override
  void didUpdateWidget(_RateScrollChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) _cachedSpots = null;
  }

  List<FlSpot> _buildSpots() {
    return widget.events.asMap().entries.map((entry) {
      final bpm = entry.value.frequency > 0
          ? entry.value.frequency
          : entry.value.instantaneousRate;
      return FlSpot(entry.value.timestampSec, bpm.clamp(60.0, 200.0));
    }).toList();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canScroll) return;
    final secsPerPx = (_sessionLength - _effectiveWindow) / 260.0;
    final newStart = (widget.windowStart - d.delta.dx * secsPerPx)
        .clamp(0.0, _sessionLength - _effectiveWindow);
    widget.onWindowStartChanged(newStart);
  }

  LineTouchData _buildTouchData() {
    return LineTouchData(
      touchSpotThreshold: 20,
      getTouchedSpotIndicator: (barData, spotIndexes) => spotIndexes
          .map((_) => TouchedSpotIndicatorData(
        FlLine(
            color: AppColors.success.withValues(alpha: 0.3),
            strokeWidth: 1),
        FlDotData(show: false),
      ))
          .toList(),
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppColors.white,
        tooltipBorder: const BorderSide(color: AppColors.divider),
        tooltipBorderRadius: BorderRadius.circular(10),
        tooltipPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((s) {
            // Find nearest event by timestamp (x is now timestampSec)
            CompressionEvent? nearest;
            double minDist = double.infinity;
            int nearestIdx = 0;
            for (int i = 0; i < widget.events.length; i++) {
              final dist = (widget.events[i].timestampSec - s.x).abs();
              if (dist < minDist) {
                minDist = dist;
                nearest = widget.events[i];
                nearestIdx = i;
              }
            }
            if (nearest == null) return null;
            final secs = nearest.timestampSec.toInt();
            final mm   = (secs ~/ 60).toString();
            final ss   = (secs % 60).toString().padLeft(2, '0');
            final bpm  = (nearest.frequency > 0
                ? nearest.frequency
                : nearest.instantaneousRate)
                .round();
            final bpmOk = bpm >= CprTargets.rateMin.toInt() &&
                bpm <= CprTargets.rateMax.toInt();
            return LineTooltipItem('', const TextStyle(), children: [
              TextSpan(
                text: '$mm:$ss  •  #${nearestIdx + 1}\n',
                style: AppTypography.caption(color: AppColors.textSecondary),
              ),
              TextSpan(
                text: '$bpm',
                style: AppTypography.bodyBold(
                    size: 14,
                    color: bpmOk
                        ? AppColors.success
                        : AppColors.error),
              ),
              TextSpan(
                text: '  BPM',
                style: AppTypography.caption(color: AppColors.textSecondary),
              ),
            ]);
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.events.isEmpty) return const SizedBox.shrink();
    _cachedSpots ??= _buildSpots();
    final allSpots = _cachedSpots!;
    final minX     = widget.windowStart;
    final maxX     = _windowEnd;

    return Column(
      children: [
        GestureDetector(
          onHorizontalDragUpdate: _canScroll ? _onDragUpdate : null,
          child: SizedBox(
            height: context.isLandscape ? 80 : (widget.compact ? 120 : 160),
            child: LineChart(
              LineChartData(
                minY: 80,
                maxY: 140,
                minX: minX,
                maxX: maxX,
                clipData: const FlClipData.all(),
                backgroundColor: AppColors.screenBgGrey.withValues(alpha: 0.5),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color:       AppColors.divider,
                    strokeWidth: AppSpacing.dividerThickness,
                  ),
                ),
                borderData: FlBorderData(show: false),
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    HorizontalRangeAnnotation(
                      y1:    CprTargets.rateMin,
                      y2:    CprTargets.rateMax,
                      color: AppColors.success.withValues(alpha: 0.09),
                    ),
                  ],
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y:           CprTargets.rateMax,
                      color:       AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray:   [4, 4],
                      label: HorizontalLineLabel(show: false),
                    ),
                    HorizontalLine(
                      y:           CprTargets.rateMin,
                      color:       AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray:   [4, 4],
                      label: HorizontalLineLabel(show: false),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles:   true,
                      reservedSize: 25,
                      interval:     20,
                      getTitlesWidget: (value, _) {
                        if (value == 80 ||
                            value == 100 ||
                            value == 120 ||
                            value == 140) {
                          final isTarget = value == CprTargets.rateMin || value == CprTargets.rateMax;
                          return Text(
                            value.toInt().toString(),
                            textAlign: TextAlign.left,
                            style: AppTypography.caption(
                              color: isTarget ? AppColors.success : AppColors.textDisabled,
                            ).copyWith(fontWeight: isTarget ? FontWeight.bold : FontWeight.normal),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: buildCprTimeAxis(
                    minX: minX,
                    maxX: maxX,
                    maxLabels: 7,
                    sessionLength: _sessionLength,
                    windowStart: widget.windowStart,
                    windowSecs: widget.windowSecs,
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots:           allSpots,
                    isCurved:        true,
                    curveSmoothness: 0.3,
                    preventCurveOverShooting:          true,
                    preventCurveOvershootingThreshold: 2.0,
                    color:    AppColors.success,
                    barWidth: 2,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) {
                        final showDots = _effectiveWindow < 30.0;
                        return showDots && spot.x >= minX && spot.x <= maxX;
                      },
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                            radius:      3.0,
                            color: spot.y >= CprTargets.rateMin &&
                                spot.y <= CprTargets.rateMax
                                ? AppColors.success
                                : AppColors.warning,
                            strokeWidth: 1,
                            strokeColor: AppColors.white,
                          ),
                    ),
                  ),
                ],
                lineTouchData: _buildTouchData(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 25), // matches reservedSize
          child: CprScrollBar(
            windowStart:   widget.windowStart,
            sessionLength: _sessionLength,
            windowSecs:    _effectiveWindow,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _DepthTrendFullChart
// ═════════════════════════════════════════════════════════════════════════════

class _DepthTrendFullChart extends StatefulWidget {
  final List<CompressionEvent> events;
  final double targetDepthMin;
  final double targetDepthMax;
  final double windowStart;
  final double? windowSecs;
  final void Function(double) onWindowStartChanged;
  final bool compact;

  const _DepthTrendFullChart({
    required this.events,
    required this.targetDepthMin,
    required this.targetDepthMax,
    required this.windowStart,
    required this.windowSecs,
    required this.onWindowStartChanged,
    this.compact = false,
  });

  @override
  State<_DepthTrendFullChart> createState() => _DepthTrendFullChartState();
}

class _DepthTrendFullChartState extends State<_DepthTrendFullChart> {
  double  _windowStart = 0.0;
  double? _windowSecs; // null = all
  List<FlSpot>? _cachedSpots;

  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;
  double get _effectiveWindow => widget.windowSecs ?? _sessionLength;
  double get _windowEnd =>
      widget.windowSecs == null ? _sessionLength : widget.windowStart + widget.windowSecs!;
  bool get _canScroll =>
      widget.windowSecs != null && _sessionLength > widget.windowSecs!;

  @override
  void didUpdateWidget(_DepthTrendFullChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) _cachedSpots = null;
  }

  List<FlSpot> _buildTrend() {
    const window = 5;
    if (widget.events.length < window) return [];
    final spots = <FlSpot>[];
    for (int i = window - 1; i < widget.events.length; i++) {
      double sum = 0;
      for (int j = i - window + 1; j <= i; j++) {
        sum += widget.events[j].depth;
      }
      spots.add(FlSpot(
          widget.events[i].timestampSec, (sum / window).clamp(0.0, 10.0)));
    }
    return spots;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canScroll) return;
    final secsPerPx = (_sessionLength - _effectiveWindow) / 260.0;
    final newStart = (widget.windowStart - d.delta.dx * secsPerPx)
        .clamp(0.0, _sessionLength - _effectiveWindow);
    widget.onWindowStartChanged(newStart);
  }

  @override
  Widget build(BuildContext context) {
    _cachedSpots ??= _buildTrend();
    final allSpots = _cachedSpots!;
    if (allSpots.isEmpty) return const SizedBox.shrink();

    final minX = widget.windowStart;
    final maxX = _windowEnd;
    final tMin = widget.targetDepthMin;
    final tMax = widget.targetDepthMax;

    // Y axis: show just below tMin to just above tMax
    final yMin = (tMin - 1.5).clamp(0.0, double.infinity);
    final yMax = tMax + 1.5;

    return Column(
      children: [
        GestureDetector(
          onHorizontalDragUpdate: _canScroll ? _onDragUpdate : null,
          child: SizedBox(
            height: context.isLandscape ? 80 : (widget.compact ? 110 : 140),
            child: LineChart(
              LineChartData(
                minY: yMin,
                maxY: yMax,
                minX: minX,
                maxX: maxX,
                clipData: const FlClipData.all(),
                backgroundColor: AppColors.screenBgGrey.withValues(alpha: 0.5),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: AppSpacing.dividerThickness),
                ),
                borderData: FlBorderData(show: false),
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    HorizontalRangeAnnotation(
                      y1:    tMin,
                      y2:    tMax,
                      color: AppColors.success.withValues(alpha: 0.09),
                    ),
                  ],
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y:           tMax,
                      color:       AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray:   [4, 4],
                      label: HorizontalLineLabel(show: false),
                    ),
                    HorizontalLine(
                      y:           tMin,
                      color:       AppColors.success.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray:   [4, 4],
                      label: HorizontalLineLabel(show: false),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles:   true,
                      reservedSize: 25,
                      getTitlesWidget: (value, meta) {
                        final isTargetMin = (value - tMin).abs() < 0.05;
                        final isTargetMax = (value - tMax).abs() < 0.05;
                        final isLow  = (value - (tMin - 1.0)).abs() < 0.05;
                        final isHigh = (value - (tMax + 1.0)).abs() < 0.05;
                        if (!isTargetMin && !isTargetMax && !isLow && !isHigh) {
                          return const SizedBox.shrink();
                        }
                        final isTarget = isTargetMin || isTargetMax;
                        return Text(
                          value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
                          textAlign: TextAlign.center,
                          style: AppTypography.caption(
                            color: isTarget ? AppColors.success : AppColors.textDisabled,
                          ).copyWith(fontWeight: isTarget ? FontWeight.bold : FontWeight.normal),
                        );
                      },
                    ),
                  ),
                  bottomTitles: buildCprTimeAxis(
                    minX: minX,
                    maxX: maxX,
                    maxLabels: 7,
                    sessionLength: _sessionLength,
                    windowStart: widget.windowStart,
                    windowSecs: widget.windowSecs,
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots:           allSpots,
                    isCurved:        true,
                    curveSmoothness: 0.4,
                    color:           AppColors.warning,
                    barWidth:        2,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) {
                        final showDots = _effectiveWindow < 20.0;
                        return showDots && spot.x >= minX && spot.x <= maxX;
                      },
                      getDotPainter: (spot, percent, barData, index) {
                        final ok = spot.y >= tMin && spot.y <= tMax;
                        return FlDotCirclePainter(
                          radius:      2.5,
                          color:       ok
                              ? AppColors.success
                              : AppColors.warning,
                          strokeWidth: 1,
                          strokeColor: AppColors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.white,
                    tooltipBorder: const BorderSide(color: AppColors.divider),
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    getTooltipItems: (spots) => spots.map((s) {
                      final secs = s.x.toInt();
                      final mm   = (secs ~/ 60).toString();
                      final ss   = (secs % 60).toString().padLeft(2, '0');
                      final ok   = s.y >= tMin && s.y <= tMax;
                      // Find nearest compression index
                      int compIdx = 0;
                      double minDist = double.infinity;
                      for (int i = 0; i < widget.events.length; i++) {
                        final dist = (widget.events[i].timestampSec - s.x).abs();
                        if (dist < minDist) { minDist = dist; compIdx = i + 1; }
                      }
                      return LineTooltipItem('', const TextStyle(),
                          children: [
                            TextSpan(
                              text: '$mm:$ss  •  #$compIdx\n',
                              style: AppTypography.caption(color: AppColors.textSecondary),
                            ),
                            TextSpan(
                              text: '${s.y.toStringAsFixed(1)} cm',
                              style: AppTypography.bodyBold(
                                  size: 14,
                                  color: ok
                                      ? AppColors.success
                                      : AppColors.error),
                            ),
                            TextSpan(
                              text: '  avg depth',
                              style: AppTypography.caption(color: AppColors.textSecondary),
                            ),
                          ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 25), // matches reservedSize
          child: CprScrollBar(
            windowStart:   widget.windowStart,
            sessionLength: _sessionLength,
            windowSecs:    _effectiveWindow,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _HeartRateFullChart
// ═════════════════════════════════════════════════════════════════════════════

class _HeartRateFullChart extends StatefulWidget {
  final List<RescuerVitalSnapshot> vitals;
  final double sessionLengthSecs;
  final double windowStart;
  final double? windowSecs;
  final void Function(double) onWindowStartChanged;

  const _HeartRateFullChart({
    required this.vitals,
    required this.sessionLengthSecs,
    required this.windowStart,
    required this.windowSecs,
    required this.onWindowStartChanged,
  });

  @override
  State<_HeartRateFullChart> createState() => _HeartRateFullChartState();
}

class _HeartRateFullChartState extends State<_HeartRateFullChart> {
  List<FlSpot>? _cachedSpots;

  double get _sessionLength =>
      widget.vitals.isEmpty ? 0 : widget.sessionLengthSecs;
  double get _effectiveWindow => widget.windowSecs ?? _sessionLength;
  double get _windowEnd =>
      widget.windowSecs == null ? _sessionLength : widget.windowStart + widget.windowSecs!;
  bool get _canScroll =>
      widget.windowSecs != null && _sessionLength > widget.windowSecs!;

  @override
  void didUpdateWidget(_HeartRateFullChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vitals != widget.vitals) _cachedSpots = null;
  }

  List<FlSpot> _buildSpots() => widget.vitals
      .where((v) => v.heartRate > 0 && v.signalQuality >= 40)
      .map((v) => FlSpot(v.timestampSec, v.heartRate.clamp(40.0, 200.0)))
      .toList();

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canScroll) return;
    final secsPerPx = (_sessionLength - _effectiveWindow) / 260.0;
    final newStart = (widget.windowStart - d.delta.dx * secsPerPx)
        .clamp(0.0, _sessionLength - _effectiveWindow);
    widget.onWindowStartChanged(newStart);
  }

  @override
  Widget build(BuildContext context) {
    _cachedSpots ??= _buildSpots();
    final allSpots = _cachedSpots!;
    if (allSpots.isEmpty) return const SizedBox.shrink();

    final minX = widget.windowStart;
    final maxX = _windowEnd;

    return Column(
      children: [
        GestureDetector(
          onHorizontalDragUpdate: _canScroll ? _onDragUpdate : null,
          child: SizedBox(
            height: context.isLandscape ? 100 : 140,
            child: LineChart(
              LineChartData(
                minY: 40,
                maxY: 180,
                minX: minX,
                maxX: maxX,
                clipData: const FlClipData.all(),
                backgroundColor: AppColors.screenBgGrey.withValues(alpha: 0.5),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: AppSpacing.dividerThickness),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y:           150,
                      color:       AppColors.warning.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray:   [6, 4],
                      label: HorizontalLineLabel(
                        show:          true,
                        alignment:     Alignment.topRight,
                        labelResolver: (_) => 'high effort',
                        style: AppTypography.badge(
                            size: 9,
                            color:
                            AppColors.warning.withValues(alpha: 0.8)),
                      ),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles:   true,
                      reservedSize: 25,
                      interval:     40,
                      getTitlesWidget: (v, _) {
                        if (v == 40 ||
                            v == 80 ||
                            v == 120 ||
                            v == 160) {

                          return Text(
                            v.toInt().toString(),
                            textAlign: TextAlign.left,
                            style: AppTypography.caption(color: AppColors.textDisabled),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: buildCprTimeAxis(
                    minX: minX,
                    maxX: maxX,
                    maxLabels: 7,
                    sessionLength: _sessionLength,
                    windowStart: widget.windowStart,
                    windowSecs: widget.windowSecs,
                  ),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots:           allSpots,
                    isCurved:        true,
                    curveSmoothness: 0.35,
                    color:           AppColors.warning,
                    barWidth:        2,
                    dotData: FlDotData(
                      show: true,
                      checkToShowDot: (spot, _) =>
                      spot.x >= minX && spot.x <= maxX,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                            radius:      2.5,
                            color: spot.y >= 160
                                ? AppColors.error
                                : spot.y >= 140
                                ? AppColors.warning
                                : AppColors.success,
                            strokeWidth: 1,
                            strokeColor: AppColors.white,
                          ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.white,
                    tooltipBorder: const BorderSide(color: AppColors.divider),
                    tooltipBorderRadius: BorderRadius.circular(10),
                    tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    getTooltipItems: (spots) => spots.map((s) {
                      final secs = s.x.toInt();
                      final mm   = (secs ~/ 60).toString();
                      final ss   = (secs % 60).toString().padLeft(2, '0');
                      final bpmColor = s.y >= 160
                          ? AppColors.error
                          : s.y >= 140
                          ? AppColors.warning
                          : AppColors.success;
                      return LineTooltipItem('', const TextStyle(),
                          children: [
                            TextSpan(
                              text: '$mm:$ss\n',
                              style: AppTypography.caption(color: AppColors.textSecondary),
                            ),
                            TextSpan(
                              text: '${s.y.round()}',
                              style: AppTypography.bodyBold(size: 14, color: bpmColor),
                            ),
                            TextSpan(
                              text: '  BPM',
                              style: AppTypography.caption(color: AppColors.textDisabled),
                            ),
                          ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 25), // matches reservedSize
          child: CprScrollBar(
            windowStart:   widget.windowStart,
            sessionLength: _sessionLength,
            windowSecs:    _effectiveWindow,
          ),
        ),
      ],
    );
  }
}


class _ChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color lineColor;
  final Widget  child;
  final Widget? dropdown;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.lineColor,
    required this.child,
    this.dropdown,
  });

  void _showExpanded(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.all(AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: SizedBox(
          height: context.isLandscape
              ? context.screenHeight * 0.90
              : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: context.isLandscape ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(
            children: [
            Container(
            width: 4,
              height: AppSpacing.md,
              decoration: AppDecorations.accentBar(color: lineColor),
            ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.subheading(size: 13)),
                    Text(subtitle,
                        style: AppTypography.caption(), maxLines: 2),
                  ],
                ),
              ),
              if (dropdown != null) ...[
            const SizedBox(width: AppSpacing.xs),
          dropdown!,
          ],
          const SizedBox(width: AppSpacing.xs),
      IconButton(
        icon: const Icon(Icons.close_rounded, size: 20),
        color: AppColors.textSecondary,
        onPressed: () => context.pop(),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
      ],
    ),
                const SizedBox(height: AppSpacing.md),
                context.isLandscape
                    ? Expanded(child: child)
                    : child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title row: accent bar | title+subtitle | dropdown | expand ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: AppSpacing.md,
                decoration: AppDecorations.accentBar(color: lineColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.subheading(size: 13)),
                    Text(subtitle,
                        style: AppTypography.caption(), maxLines: 2),
                  ],
                ),
              ),
              if (dropdown != null) ...[
                const SizedBox(width: AppSpacing.xs),
                dropdown!,
              ],
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: () => _showExpanded(context),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius:
                    BorderRadius.circular(AppSpacing.cardRadiusSm),
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}