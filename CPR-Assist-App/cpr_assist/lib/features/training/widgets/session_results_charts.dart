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

          // Chart 3 — Depth trend
          if (events.length >= 5) ...[
            const SizedBox(height: AppSpacing.md),
            _DepthTrendChartCard(
              events:         events,
              targetDepthMin: targetDepthMin,
              targetDepthMax: targetDepthMax,
            ),
          ],

// Chart 4 — Wrist alignment
          if (events.any((e) => e.wristAlignmentAngle > 0)) ...[
            const SizedBox(height: AppSpacing.md),
            _WristAlignmentChartCard(events: events),
          ],

// Chart 5 — Rescuer HR
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

// ── _DepthRecoilChartCard ──────────────────────────────────────────────────
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
    final tMin  = widget.targetDepthMin;
    final tMax  = widget.targetDepthMax;
    final spots = buildCprWaveform(widget.events);

    if (spots.isEmpty) {
      return CprChartCard(
        title:    'Compression Depth',
        subtitle: 'Depth per compression · Target depth and recoil',
        lineColor: AppColors.primary,
        child: const SizedBox.shrink(),
      );
    }

    return CprChartCard(
      title:    'Compression Depth',
      subtitle: 'Depth per compression · Target depth and recoil',
      lineColor: AppColors.primary,
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: CprScrollableChart(
        series: [
          CprSeries(
            label: '',
            color: AppColors.primary,
            spots: spots,
            comps: widget.events,
          ),
        ],
        minY: 0,
        maxY: 8,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        leftReserved: 28,
        horizontalGridInterval: 1,
        bands: [
          HorizontalRangeAnnotation(
            y1: tMin, y2: tMax,
            color: AppColors.success.withValues(alpha: 0.09),
          ),
          HorizontalRangeAnnotation(
            y1: 0, y2: kCprRecoilThresholdCm,
            color: AppColors.warning.withValues(alpha: 0.10),
          ),
        ],
        guideLines: [
          HorizontalLine(y: tMax,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: tMin,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: kCprRecoilThresholdCm,
              color: AppColors.warning.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [3, 5]),
        ],
        leftAxis: buildCprDepthLeftAxis(
          targetMin: tMin,
          targetMax: tMax,
          reservedSize: 28,
        ),
        tooltipValue: (_, spot) {
          final isPeak = spot.y > 3.0;
          return '${spot.y.toStringAsFixed(1)} cm ${isPeak ? 'depth' : 'recoil'}';
        },
        tooltipValueColor: (_, spot) {
          final isPeak = spot.y > 3.0;
          if (isPeak) {
            return (spot.y >= tMin && spot.y <= tMax)
                ? AppColors.success : AppColors.error;
          }
          return AppColors.textDisabled;
        },
      ),
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
    return CprChartCard(
      title:    'Compression Rate',
      subtitle: 'Green band = 100–120 cpm',
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
      child: CprScrollableChart(
        series: [
          CprSeries(
            label: '',
            color: AppColors.success,
            spots: buildRateSpots(widget.events),
            comps: widget.events,
          ),
        ],
        minY: 80,
        maxY: 140,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        curved: false,
        leftReserved: 28,
        horizontalGridInterval: 10,
        bands: [
          HorizontalRangeAnnotation(
            y1: CprTargets.rateMin, y2: CprTargets.rateMax,
            color: AppColors.success.withValues(alpha: 0.09),
          ),
        ],
        guideLines: [
          HorizontalLine(y: CprTargets.rateMax,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: CprTargets.rateMin,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
        ],
        leftAxis: buildCprRateLeftAxis(),
        showDotsWhen: (w) => w < 30.0,
        dotBuilder: (_, spot) => FlDotCirclePainter(
          radius: 3,
          color: spot.y >= CprTargets.rateMin && spot.y <= CprTargets.rateMax
              ? AppColors.success
              : AppColors.warning,
          strokeWidth: 1,
          strokeColor: AppColors.white,
        ),
        tooltipValue: (_, spot) => '${spot.y.round()} cpm',
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
    return CprChartCard(
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
      child: CprScrollableChart(
        series: [
          CprSeries(
            label: '',
            color: AppColors.warning,
            spots: buildDepthTrendSpots(widget.events, window: 5),
            comps: widget.events,
          ),
        ],
        minY: 0,
        maxY: 9,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        leftReserved: 28,
        horizontalGridInterval: 1,
        bands: [
          HorizontalRangeAnnotation(
            y1: widget.targetDepthMin, y2: widget.targetDepthMax,
            color: AppColors.success.withValues(alpha: 0.09),
          ),
        ],
        guideLines: [
          HorizontalLine(y: widget.targetDepthMax,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: widget.targetDepthMin,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
        ],
        leftAxis: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 1,
            getTitlesWidget: (value, meta) {
              if (value < 0 || value > 8) return const SizedBox.shrink();
              if ((value - value.roundToDouble()).abs() > 0.01) {
                return const SizedBox.shrink();
              }
              final isTarget =
                  (value - widget.targetDepthMin).abs() < 0.05 ||
                      (value - widget.targetDepthMax).abs() < 0.05;
              return Text(
                value.toInt().toString(),
                textAlign: TextAlign.center,
                style: AppTypography.caption(
                  color: isTarget
                      ? AppColors.success
                      : AppColors.textDisabled,
                ).copyWith(
                    fontWeight:
                    isTarget ? FontWeight.bold : FontWeight.normal),
              );
            },
          ),
        ),
        showDotsWhen: (w) => w < 20.0,
        dotBuilder: (_, spot) => FlDotCirclePainter(
          radius: 2.5,
          color: spot.y >= widget.targetDepthMin &&
              spot.y <= widget.targetDepthMax
              ? AppColors.success
              : AppColors.warning,
          strokeWidth: 1,
          strokeColor: AppColors.white,
        ),
        tooltipValue: (_, spot) => '${spot.y.toStringAsFixed(1)} cm',
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _WristAlignmentChartCard
// ═════════════════════════════════════════════════════════════════════════════

class _WristAlignmentChartCard extends StatefulWidget {
  final List<CompressionEvent> events;
  final bool compact;

  const _WristAlignmentChartCard({
    required this.events,
    this.compact = false,
  });

  @override
  State<_WristAlignmentChartCard> createState() =>
      _WristAlignmentChartCardState();
}

class _WristAlignmentChartCardState extends State<_WristAlignmentChartCard> {
  double _windowStart = 0.0;
  double? _windowSecs;

  double get _sessionLength =>
      widget.events.isEmpty ? 0 : widget.events.last.timestampSec;

  @override
  Widget build(BuildContext context) {
    return CprChartCard(
      title: 'Wrist Alignment',
      subtitle: 'Wrist deviation angle during compressions',
      lineColor: AppColors.primary,
      dropdown: CprWindowDropdown(
        value: _windowSecs,
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
      child: Builder(builder: (_) {
        final maxAngle = buildPostureSpots(widget.events)
            .map((s) => s.y)
            .fold(0.0, (a, b) => a > b ? a : b);
        final chartMaxY = (maxAngle + 5).clamp(20.0, 45.0);
        return CprScrollableChart(
          series: [
            CprSeries(
              label: '',
              color: AppColors.primary,
              spots: buildPostureSpots(widget.events),
              comps: widget.events,
            ),
          ],
          minY: 0,
          maxY: chartMaxY,
          sessionLength: _sessionLength,
          windowSecs:    _windowSecs,
          windowStart:   _windowStart,
          onWindowStartChanged: (v) => setState(() => _windowStart = v),
          leftReserved: 32,
          horizontalGridInterval: 5,
          guideLines: [
            HorizontalLine(
              y: CprTargets.alignmentMaxDeg,
              color: AppColors.warning.withValues(alpha: 0.6),
              strokeWidth: 1, dashArray: [6, 4],
            ),
          ],
          leftAxis: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 5,
              getTitlesWidget: (v, _) {
                if (v < 0 || v > chartMaxY) return const SizedBox.shrink();
                if ((v % 5).abs() > 0.01) return const SizedBox.shrink();
                final isTarget =
                    (v - CprTargets.alignmentMaxDeg).abs() < 0.5;
                return Text(
                  '${v.toInt()}°',
                  style: AppTypography.caption(
                    color: isTarget
                        ? AppColors.warning
                        : AppColors.textDisabled,
                  ).copyWith(
                    fontWeight:
                    isTarget ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              },
            ),
          ),
          showDotsWhen: (w) => w < 20.0,
          dotBuilder: (_, spot) => FlDotCirclePainter(
            radius: 2.5,
            color: spot.y <= CprTargets.alignmentMaxDeg
                ? AppColors.primary
                : AppColors.warning,
            strokeWidth: 1,
            strokeColor: AppColors.white,
          ),
          tooltipValue: (_, spot) => '${spot.y.toStringAsFixed(0)}°',
        );
      }),
    );
  }
}

// M28: a spot is "low signal" if its nearest vital snapshot had
// signalQuality < 40. Matched by timestamp (spots and vitals are not
// index-aligned: buildHrSpots drops rows with heartRate <= 0).
bool _hrSignalLow(List<RescuerVitalSnapshot> vitals, double xSec) {
  if (vitals.isEmpty) return false;
  RescuerVitalSnapshot? nearest;
  double best = double.infinity;
  for (final v in vitals) {
    final d = (v.timestampSec - xSec).abs();
    if (d < best) {
      best = d;
      nearest = v;
    }
  }
  return nearest != null && nearest.signalQuality < 40;
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
    return CprChartCard(
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
      child: CprScrollableChart(
        series: [
          CprSeries(
            label: '',
            color: AppColors.warning,
            spots: buildHrSpots(widget.vitals),
            comps: widget.vitals,   // M28: lets dotBuilder read signalQuality
          ),
        ],
        minY: 40,
        maxY: 180,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        leftReserved: 25,
        guideLines: [
          HorizontalLine(
            y: 150,
            color: AppColors.warning.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              labelResolver: (_) => 'high effort',
              style: AppTypography.badge(
                  size: 9, color: AppColors.warning.withValues(alpha: 0.8)),
            ),
          ),
        ],
        leftAxis: AxisTitles(
          sideTitles: SideTitles(
            showTitles:   true,
            reservedSize: 25,
            interval:     40,
            getTitlesWidget: (v, _) {
              if (v == 40 || v == 80 || v == 120 || v == 160) {
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
        tooltipValue: (_, spot) {
          final lowSig = _hrSignalLow(widget.vitals, spot.x);
          return '${spot.y.round()} BPM${lowSig ? ' (low signal)' : ''}';
        },
        showDotsWhen: (_) => true,
        dotBuilder: (_, spot) {
          final lowSig = _hrSignalLow(widget.vitals, spot.x);
          final base = spot.y >= 160
              ? AppColors.error
              : spot.y >= 140
              ? AppColors.warning
              : AppColors.success;
          // M28: low-signal points stay visible but de-emphasized — smaller,
          // translucent, hollow — so the trend line is continuous while
          // unreliable samples are clearly distinguishable.
          return FlDotCirclePainter(
            radius: lowSig ? 1.5 : 2.5,
            color: lowSig ? base.withValues(alpha: 0.25) : base,
            strokeWidth: 1,
            strokeColor: lowSig
                ? AppColors.white.withValues(alpha: 0.4)
                : AppColors.white,
          );
        },
      ),
    );
  }
}