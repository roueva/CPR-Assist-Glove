part of 'session_compare_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// session_compare_charts.dart
//
// Per-metric comparison charts for SessionCompareScreen, all built on the
// shared CprScrollableChart. Split out of session_compare_screen.dart purely
// for file size; no logic differs. Private symbols stay accessible via
// part/part of.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Depth waveform — valley→peak per session, consolidated via CprScrollableChart
// ─────────────────────────────────────────────────────────────────────────────

class _CompareDepthChart extends StatefulWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _CompareDepthChart({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  State<_CompareDepthChart> createState() => _CompareDepthChartState();
}

class _CompareDepthChartState extends State<_CompareDepthChart> {
  double  _windowStart = 0.0;
  double? _windowSecs  = kCprDefaultWindowSecs;

  double get _sessionLength => widget.sessions
      .map((s) {
    final d = widget.details[s.id];
    return d == null || d.compressions.isEmpty
        ? 0.0
        : d.compressions.last.timestampSec;
  })
      .fold(0.0, (a, b) => a > b ? a : b);

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
    final tMin = cprDepthMin(widget.sessions.first.scenario);
    final tMax = cprDepthMax(widget.sessions.first.scenario);

    final series = <CprSeries>[];
    for (int i = 0; i < widget.sessions.length; i++) {
      final d = widget.details[widget.sessions[i].id];
      if (d == null) continue;
      final waveform = buildCprWaveform(d.compressions);
      if (waveform.isEmpty) continue;
      series.add(CprSeries(
        label: 'S${widget.sessions[i].sessionNumber ?? i + 1}',
        color: widget.slotColors[i],
        spots: waveform,
        comps: d.compressions,
      ));
    }
    if (series.isEmpty) return const SizedBox.shrink();

    return CprChartCard(
      title:    'Compression Depth',
      subtitle: 'Green band = target depth · Amber band = recoil',
      lineColor: AppColors.primary,
      legend: _compareLegendDots(widget.sessions, widget.slotColors),
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: CprScrollableChart(
        series:        series,
        sessions:      widget.sessions,
        minY:          0,
        maxY:          9,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        leftReserved:  28,
        horizontalGridInterval: 1,
        bands: [
          HorizontalRangeAnnotation(
            y1: tMin, y2: tMax,
            color: AppColors.success.withValues(alpha: 0.08),
          ),
          HorizontalRangeAnnotation(
            y1: 0, y2: kCprRecoilThresholdCm,
            color: AppColors.warning.withValues(alpha: 0.08),
          ),
        ],
        guideLines: [
          HorizontalLine(y: tMin,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: tMax,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
        ],
        leftAxis: buildCprDepthLeftAxis(
          targetMin: tMin,
          targetMax: tMax,
          reservedSize: 28,
        ),
        tooltipValue: (_, spot) {
          final isPeak = spot.y > kCprRecoilThresholdCm;
          return '${spot.y.toStringAsFixed(1)} cm ${isPeak ? 'p' : 'r'}';
        },
        tooltipValueColor: (_, spot) => spot.y > kCprRecoilThresholdCm
            ? AppColors.textPrimary
            : AppColors.textDisabled,
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Rate chart — per-compression rate, consolidated via CprScrollableChart
// ─────────────────────────────────────────────────────────────────────────────

class _CompareRateChart extends StatefulWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _CompareRateChart({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  State<_CompareRateChart> createState() => _CompareRateChartState();
}

class _CompareRateChartState extends State<_CompareRateChart> {
  double  _windowStart = 0.0;
  double? _windowSecs  = kCprDefaultWindowSecs;

  double get _sessionLength => widget.sessions
      .map((s) {
    final d = widget.details[s.id];
    return d == null || d.compressions.isEmpty
        ? 0.0
        : d.compressions.last.timestampSec;
  })
      .fold(0.0, (a, b) => a > b ? a : b);

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
    final series = <CprSeries>[];
    for (int i = 0; i < widget.sessions.length; i++) {
      final d = widget.details[widget.sessions[i].id];
      if (d == null || d.compressions.isEmpty) continue;
      series.add(CprSeries(
        label: 'S${widget.sessions[i].sessionNumber ?? i + 1}',
        color: widget.slotColors[i],
        spots: buildRateSpots(d.compressions),
        comps: d.compressions,
      ));
    }
    if (series.isEmpty) return const SizedBox.shrink();

    return CprChartCard(
      title:    'Compression Rate',
      subtitle: 'Green band = 100–120 cpm',
      lineColor: AppColors.success,
      legend: _compareLegendDots(widget.sessions, widget.slotColors),
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: CprScrollableChart(
        series:        series,
        sessions:      widget.sessions,
        minY:          80,
        maxY:          140,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        curved:        false,
        leftReserved:  28,
        horizontalGridInterval: 10,
        bands: [
          HorizontalRangeAnnotation(
            y1: CprTargets.rateMin, y2: CprTargets.rateMax,
            color: AppColors.success.withValues(alpha: 0.08),
          ),
        ],
        guideLines: [
          HorizontalLine(y: CprTargets.rateMin,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: CprTargets.rateMax,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
        ],
        leftAxis: buildCprRateLeftAxis(),
        showDotsWhen: (w) => w <= 20.0,
        dotBuilder: (barIdx, spot) => FlDotCirclePainter(
          radius: 3,
          color: spot.y >= CprTargets.rateMin && spot.y <= CprTargets.rateMax
              ? widget.slotColors[barIdx]
              : AppColors.error,
          strokeWidth: 1,
          strokeColor: AppColors.white,
        ),
        tooltipValue: (_, spot) => '${spot.y.round()} cpm',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Depth trend — 5-compression rolling avg, consolidated via CprScrollableChart
// ─────────────────────────────────────────────────────────────────────────────

class _CompareDepthTrendChart extends StatefulWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _CompareDepthTrendChart({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  State<_CompareDepthTrendChart> createState() =>
      _CompareDepthTrendChartState();
}

class _CompareDepthTrendChartState extends State<_CompareDepthTrendChart> {
  double  _windowStart = 0.0;
  double? _windowSecs; // null = All

  double get _sessionLength => widget.sessions
      .map((s) {
    final d = widget.details[s.id];
    return d == null || d.compressions.isEmpty
        ? 0.0
        : d.compressions.last.timestampSec;
  })
      .fold(0.0, (a, b) => a > b ? a : b);

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
    final tMin = cprDepthMin(widget.sessions.first.scenario);
    final tMax = cprDepthMax(widget.sessions.first.scenario);

    final series = <CprSeries>[];
    for (int i = 0; i < widget.sessions.length; i++) {
      final d = widget.details[widget.sessions[i].id];
      if (d == null) continue;
      final spots = buildDepthTrendSpots(d.compressions, window: 5);
      if (spots.isEmpty) continue;
      series.add(CprSeries(
        label: 'S${widget.sessions[i].sessionNumber ?? i + 1}',
        color: widget.slotColors[i],
        spots: spots,
        comps: d.compressions,
      ));
    }
    if (series.isEmpty) return const SizedBox.shrink();

    return CprChartCard(
      title:    'Depth Trend',
      subtitle: '5-compression rolling average',
      lineColor: AppColors.warning,
      legend: _compareLegendDots(widget.sessions, widget.slotColors),
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: CprScrollableChart(
        series:        series,
        sessions:      widget.sessions,
        minY:          0,
        maxY:          9,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        leftReserved:  28,
        horizontalGridInterval: 10,
        bands: [
          HorizontalRangeAnnotation(
            y1: tMin, y2: tMax,
            color: AppColors.success.withValues(alpha: 0.08),
          ),
        ],
        guideLines: [
          HorizontalLine(y: tMin,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
          HorizontalLine(y: tMax,
              color: AppColors.success.withValues(alpha: 0.5),
              strokeWidth: 1, dashArray: [4, 4]),
        ],
        leftAxis: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: 1,
            getTitlesWidget: (v, meta) {
              if (v < 0 || v > 8) return const SizedBox.shrink();
              if ((v - v.roundToDouble()).abs() > 0.01) {
                return const SizedBox.shrink();
              }
              final isTarget =
                  (v - tMin).abs() < 0.05 || (v - tMax).abs() < 0.05;
              return Text(
                v.toStringAsFixed(1),
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
        showDotsWhen: (w) => w <= 20.0,
        dotBuilder: (barIdx, spot) => FlDotCirclePainter(
          radius: 3,
          color: spot.y >= tMin && spot.y <= tMax
              ? widget.slotColors[barIdx]
              : AppColors.warning,
          strokeWidth: 1,
          strokeColor: AppColors.white,
        ),
        tooltipValue: (_, spot) => '${spot.y.toStringAsFixed(1)} cm',
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Posture / wrist alignment — consolidated via CprScrollableChart
// ─────────────────────────────────────────────────────────────────────────────

class _ComparePostureChart extends StatefulWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _ComparePostureChart({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  State<_ComparePostureChart> createState() => _ComparePostureChartState();
}

class _ComparePostureChartState extends State<_ComparePostureChart> {
  double  _windowStart = 0.0;
  double? _windowSecs;

  double get _sessionLength {
    double max = 0;
    for (final s in widget.sessions) {
      final d = widget.details[s.id];
      if (d != null && d.compressions.isNotEmpty) {
        final t = d.compressions.last.timestampSec;
        if (t > max) max = t;
      }
    }
    return max;
  }

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
    final series = <CprSeries>[];
    double maxAngle = 0;
    for (int i = 0; i < widget.sessions.length; i++) {
      final d = widget.details[widget.sessions[i].id];
      if (d == null || d.compressions.isEmpty) continue;
      if (d.compressions.every((c) => c.wristAlignmentAngle == 0)) continue;
      final spots = buildPostureSpots(d.compressions);
      if (spots.isEmpty) continue;
      final sMax = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);
      if (sMax > maxAngle) maxAngle = sMax;
      series.add(CprSeries(
        label: 'S${widget.sessions[i].sessionNumber ?? i + 1}',
        color: widget.slotColors[i],
        spots: spots,
        comps: d.compressions,
      ));
    }
    if (series.isEmpty) return const SizedBox.shrink();

    final double chartMaxY = (maxAngle + 5).clamp(20.0, 45.0);

    return CprChartCard(
      title:    'Wrist Alignment',
      subtitle: 'Lower = arms better aligned over sternum',
      lineColor: AppColors.warning,
      legend: _compareLegendDots(widget.sessions, widget.slotColors),
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: CprScrollableChart(
        series:        series,
        sessions:      widget.sessions,
        minY:          0,
        maxY:          chartMaxY,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        curved:        true,
        leftReserved:  32,
        horizontalGridInterval: 10,
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
        showDotsWhen: (w) => w <= 20.0,
        dotBuilder: (barIdx, spot) => FlDotCirclePainter(
          radius: 3,
          color: spot.y <= CprTargets.alignmentMaxDeg
              ? widget.slotColors[barIdx]
              : AppColors.warning,
          strokeWidth: 1,
          strokeColor: AppColors.white,
        ),
        tooltipValue: (_, spot) => '${spot.y.toStringAsFixed(0)}°',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rescuer HR — one line per session, consolidated via CprScrollableChart.
// Uses buildHrSpots → applies the >=40 signal-quality filter (matches
// single-session; fixes the prior compare-only discrepancy).
// ─────────────────────────────────────────────────────────────────────────────

class _CompareHrChartCard extends StatefulWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _CompareHrChartCard({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  State<_CompareHrChartCard> createState() => _CompareHrChartCardState();
}

class _CompareHrChartCardState extends State<_CompareHrChartCard> {
  double  _windowStart = 0.0;
  double? _windowSecs;

  double get _sessionLength {
    double max = 0;
    for (final s in widget.sessions) {
      final d = widget.details[s.id];
      if (d != null && d.rescuerVitals.isNotEmpty) {
        final t = d.rescuerVitals.last.timestampSec;
        if (t > max) max = t;
      }
    }
    return max;
  }

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
    final series = <CprSeries>[];
    double maxHr = 180;
    for (int i = 0; i < widget.sessions.length; i++) {
      final d = widget.details[widget.sessions[i].id];
      if (d == null || d.rescuerVitals.isEmpty) continue;
      final spots = buildHrSpots(d.rescuerVitals);
      if (spots.isEmpty) continue;
      final sMax = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
      if (sMax + 10 > maxHr) maxHr = sMax + 10;
      series.add(CprSeries(
        label: 'S${widget.sessions[i].sessionNumber ?? i + 1}',
        color: widget.slotColors[i],
        spots: spots,
      ));
    }
    if (series.isEmpty) return const SizedBox.shrink();

    return CprChartCard(
      title:    'Rescuer Heart Rate',
      subtitle: 'Rising trend = increasing physical load',
      lineColor: AppColors.warning,
      legend: _compareLegendDots(widget.sessions, widget.slotColors),
      dropdown: CprWindowDropdown(
        value:         _windowSecs,
        sessionLength: _sessionLength,
        onChanged:     _onWindowChanged,
      ),
      child: CprScrollableChart(
        series:        series,
        sessions:      widget.sessions,
        minY:          50,
        maxY:          maxHr,
        sessionLength: _sessionLength,
        windowSecs:    _windowSecs,
        windowStart:   _windowStart,
        onWindowStartChanged: (v) => setState(() => _windowStart = v),
        leftReserved:  28,
        guideLines: [
          HorizontalLine(
            y: 160,
            color: AppColors.error.withValues(alpha: 0.4),
            strokeWidth: 1,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              labelResolver: (_) => 'swap rescuer',
              style: AppTypography.badge(
                  size: 9, color: AppColors.error.withValues(alpha: 0.7)),
            ),
          ),
        ],
        horizontalGridInterval: 30,
        leftAxis: AxisTitles(
          sideTitles: SideTitles(
            showTitles:   true,
            reservedSize: 28,
            interval:     30,
            getTitlesWidget: (v, _) {
              if (v % 30 != 0) return const SizedBox.shrink();
              return Text(
                v.toInt().toString(),
                style: AppTypography.caption(color: AppColors.textDisabled),
              );
            },
          ),
        ),
        showDotsWhen: (w) => w <= 20.0,
        dotBuilder: (_, spot) => FlDotCirclePainter(
          radius: 3,
          color: spot.y >= 160
              ? AppColors.error
              : spot.y >= 140
              ? AppColors.warning
              : AppColors.success,
          strokeWidth: 1,
          strokeColor: AppColors.white,
        ),
        tooltipValue: (_, spot) {
          final bpm = spot.y.round();
          final tag = bpm >= 160 ? ' ▲' : bpm >= 140 ? ' ↑' : '';
          return '$bpm bpm$tag';
        },
      ),
    );
  }
}

// Shared session-dots legend for all compare chart cards.
Widget _compareLegendDots(
    List<SessionSummary> sessions, List<Color> slotColors) {
  return Wrap(
    spacing: AppSpacing.md,
    runSpacing: AppSpacing.xxs,
    children: [
      for (int i = 0; i < sessions.length; i++)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width:  AppSpacing.sm,
            height: AppSpacing.sm,
            decoration: AppDecorations.sessionDot(color: slotColors[i]),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text('S${sessions[i].sessionNumber ?? i + 1}',
              style: AppTypography.caption(color: AppColors.textSecondary)),
        ]),
    ],
  );
}


class _NoDetailPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin:     const EdgeInsets.only(top: AppSpacing.xl),
      padding:    const EdgeInsets.all(AppSpacing.xl),
      decoration: AppDecorations.card(),
      child: Column(children: [
        const Icon(Icons.hourglass_top_rounded,
            color: AppColors.textDisabled, size: AppSpacing.iconXl),
        const SizedBox(height: AppSpacing.md),
        Text('Loading chart data…',
            style: AppTypography.subheading(
                color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.xs),
        Text('Per-compression data is being fetched.',
            style: AppTypography.caption(color: AppColors.textDisabled),
            textAlign: TextAlign.center),
      ]),
    );
  }
}