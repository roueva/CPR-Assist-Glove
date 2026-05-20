// ─────────────────────────────────────────────────────────────────────────────
// cpr_chart_helpers.dart
//
// Shared chart infrastructure used by both SessionResultsScreen and
// SessionCompareScreen. Public symbols only — no private class dependencies.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cpr_assist/core/core.dart';

import '../screens/session_service.dart';
import '../services/compression_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const double kCprDefaultWindowSecs  = 10.0;
const double kCprRecoilThresholdCm  = 0.5;

const List<double> kCprWindowOptions = [5, 10, 15, 20, 30, 60];

// ─────────────────────────────────────────────────────────────────────────────
// Time formatting
// ─────────────────────────────────────────────────────────────────────────────

String fmtChartTime(double secs) {
  final m = (secs ~/ 60).toString();
  final s = (secs % 60).toInt().toString().padLeft(2, '0');
  return '$m:$s';
}


double cprChartGridInterval(double minX, double maxX) {
  final span = (maxX - minX).abs();

  if (span <= 10) return 2;
  if (span <= 20) return 5;
  if (span <= 60) return 10;
  if (span <= 180) return 30;
  return 60;
}

FlGridData cprChartGridData({
  required double minX,
  required double maxX,
  double? horizontalInterval,
}) {
  return FlGridData(
    show: true,
    drawVerticalLine: true,
    horizontalInterval: horizontalInterval,
    verticalInterval: cprChartGridInterval(minX, maxX),
    getDrawingHorizontalLine: (_) => FlLine(
      color: AppColors.divider,
      strokeWidth: AppSpacing.dividerThickness,
    ),
    getDrawingVerticalLine: (_) => FlLine(
      color: AppColors.divider.withValues(alpha: 0.45),
      strokeWidth: AppSpacing.dividerThickness,
    ),
  );
}

Color cprChartBackgroundColor() {
  return AppColors.screenBgGrey.withValues(alpha: 0.5);
}

// ─────────────────────────────────────────────────────────────────────────────
// CprWindowDropdown
// ─────────────────────────────────────────────────────────────────────────────

class CprWindowDropdown extends StatelessWidget {
  final double? value; // null = "All"
  final double  sessionLength;
  final void Function(double?) onChanged;

  const CprWindowDropdown({
    super.key,
    required this.value,
    required this.sessionLength,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = value == null ? 'All' : '${value!.toInt()}s';
    return GestureDetector(
      onTapDown: (details) async {
        final box    = context.findRenderObject() as RenderBox;
        final offset = box.localToGlobal(Offset.zero);
        final result = await showMenu<double?>(
          context: context,
          color: AppColors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd)),
          elevation: 4,
          position: RelativeRect.fromLTRB(
            offset.dx - 60,
            offset.dy + box.size.height + 4,
            offset.dx + box.size.width,
            0,
          ),
          items: [
            ...kCprWindowOptions
                .where((o) => o <= sessionLength || sessionLength == 0)
                .map((o) => PopupMenuItem<double?>(
              value: o,
              height: 36,
              child: Text('${o.toInt()} sec',
                  style: AppTypography.body(
                      size: 13,
                      color: value == o
                          ? AppColors.primary
                          : AppColors.textPrimary)),
            )),
            PopupMenuItem<double?>(
              value: -1.0,
              height: 36,
              child: Text('All',
                  style: AppTypography.body(
                      size: 13,
                      color: value == null
                          ? AppColors.primary
                          : AppColors.textPrimary)),
            ),
          ],
        );
        if (result != null) onChanged(result == -1.0 ? null : result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xxs + 1),
        decoration: AppDecorations.dropdownPill(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTypography.badge(
                    size: 10, color: AppColors.primary)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more_rounded,
                size: 12, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CprScrollBar
// ─────────────────────────────────────────────────────────────────────────────

class CprScrollBar extends StatelessWidget {
  final double windowStart;
  final double sessionLength;
  final double windowSecs;

  const CprScrollBar({
    super.key,
    required this.windowStart,
    required this.sessionLength,
    required this.windowSecs,
  });

  @override
  Widget build(BuildContext context) {
    if (sessionLength <= windowSecs) return const SizedBox(height: 6);
    final progress =
    (windowStart / (sessionLength - windowSecs)).clamp(0.0, 1.0);
    final thumbFrac = (windowSecs / sessionLength).clamp(0.05, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: LayoutBuilder(builder: (ctx, c) {
        final trackW = c.maxWidth;
        final thumbW = trackW * thumbFrac;
        final thumbL = (trackW - thumbW) * progress;
        return Stack(children: [
          Container(height: 4, decoration: AppDecorations.scrollTrack()),
          Positioned(
            left: thumbL,
            child: Container(
                width: thumbW,
                height: 4,
                decoration: AppDecorations.scrollThumb()),
          ),
        ]);
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// buildCprTimeAxis — non-overlapping time axis labels
// ─────────────────────────────────────────────────────────────────────────────

AxisTitles buildCprTimeAxis({
  required double minX,
  required double maxX,
  required double sessionLength,
  required double windowStart,
  required double? windowSecs,
  int maxLabels = 6,
}) {
  final span = maxX - minX;
  if (span <= 0) {
    return const AxisTitles(sideTitles: SideTitles(showTitles: false));
  }

  final niceIntervals = [1, 2, 5, 10, 15, 20, 30, 60, 120, 300];
  final rawInterval   = span / (maxLabels - 1);
  double interval     = niceIntervals.last.toDouble();
  for (final n in niceIntervals) {
    if (n >= rawInterval) {
      interval = n.toDouble();
      break;
    }
  }

  final edgeTol    = interval * 0.1;
  final minEdgeGap = interval * 0.5;
  final lastGrid   = ((maxX - edgeTol) / interval).floor() * interval;
  final first      = (minX / interval).ceil() * interval;

  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 18,
      interval: interval,
      getTitlesWidget: (value, meta) {
        // Outside visible range
        if (value < minX - edgeTol || value > maxX + edgeTol) {
          return const SizedBox.shrink();
        }

        // Right edge — always suppress to avoid overlap with scroll bar end
        if (value > maxX - edgeTol) {
          return const SizedBox.shrink();
        }

        // Left edge — show only if at the true start
        if (value < minX + edgeTol) {
          final atStart = windowSecs == null || windowStart <= 0.001;
          if (!atStart) return const SizedBox.shrink();
        }

        // Interior grid labels
        final offset = (value - first) % interval;
        final onGrid = offset < 0.5 || (interval - offset) < 0.5;
        if (!onGrid) return const SizedBox.shrink();

        return SideTitleWidget(
          meta: meta,
          space: 4,
          child: Text(
            fmtChartTime(value),
            style: AppTypography.caption(color: AppColors.textDisabled),
          ),
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// buildCprDepthLeftAxis — left axis for depth charts with target highlights
// ─────────────────────────────────────────────────────────────────────────────

AxisTitles buildCprDepthLeftAxis({
  required double targetMin,
  required double targetMax,
  double reservedSize = 28,
}) {
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: reservedSize,
      interval: 1,
      getTitlesWidget: (v, meta) {
        if (v < 0 || v > 8) return const SizedBox.shrink();
        if ((v - v.roundToDouble()).abs() > 0.01) return const SizedBox.shrink();
        final isTarget =
            (v - targetMin).abs() < 0.05 || (v - targetMax).abs() < 0.05;
        return Text(
          v.toInt().toString(),
          style: AppTypography.caption(
            color: isTarget ? AppColors.success : AppColors.textDisabled,
          ).copyWith(
              fontWeight: isTarget ? FontWeight.bold : FontWeight.normal),
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// buildCprRateLeftAxis — left axis for rate charts with target highlights
// ─────────────────────────────────────────────────────────────────────────────

AxisTitles buildCprRateLeftAxis({
  double rateMin = 100,
  double rateMax = 120,
  double reservedSize = 28,
}) {
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: reservedSize,
      interval: 20,
      getTitlesWidget: (v, _) {
        if (v != 80 && v != 100 && v != 120 && v != 140) {
          return const SizedBox.shrink();
        }
        final isTarget = (v - rateMin).abs() < 0.5 || (v - rateMax).abs() < 0.5;
        return Text(
          v.toInt().toString(),
          style: AppTypography.caption(
            color: isTarget ? AppColors.success : AppColors.textDisabled,
          ).copyWith(
              fontWeight: isTarget ? FontWeight.bold : FontWeight.normal),
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// buildCprWaveform — valley→peak waveform spots from compression events
// Shared between session results depth chart and compare depth chart.
// ─────────────────────────────────────────────────────────────────────────────

List<FlSpot> buildCprWaveform(List<dynamic> events) {
  // events must have .timestampSec, .depth, .valleyDepth
  if (events.isEmpty) return [];
  final spots = <FlSpot>[];
  for (int i = 0; i < events.length; i++) {
    final e      = events[i];
    final t      = (e.timestampSec as double);
    final rawDepth = e.depth as double;
    if (!rawDepth.isFinite || rawDepth <= 0) continue;  // skip unmeasured comp
    final peak   = rawDepth.clamp(0.0, 10.0);
    final rawVal = e.valleyDepth as double;
    final valley = rawVal > 0
        ? rawVal.clamp(0.0, (peak - 0.05).clamp(0.0, 10.0))
        : 0.0;

    double halfCycle = 0.28;
    if (i > 0) {
      halfCycle =
          (t - (events[i - 1].timestampSec as double)) / 2.0;
      halfCycle = halfCycle.clamp(0.15, 0.42);
    } else if (i < events.length - 1) {
      halfCycle =
          ((events[i + 1].timestampSec as double) - t) / 2.0;
      halfCycle = halfCycle.clamp(0.15, 0.42);
    }

    final preT  = (t - halfCycle).clamp(0.0, double.infinity);
    final postT = t + halfCycle;

    if (spots.isEmpty || preT > spots.last.x + 0.01) {
      spots.add(FlSpot(preT, valley));
    }
    spots.add(FlSpot(t, peak));
    spots.add(FlSpot(postT, valley));
  }
  return spots;
}

// ── Series model ──────────────────────────────────────────────────────────
class CprSeries {
  final String label;          // "S3" (compare) or "" (single)
  final Color  color;
  final List<FlSpot> spots;
  final List<dynamic>? comps;  // compression events for tooltip #, nullable
  const CprSeries({required this.label, required this.color,
    required this.spots, this.comps});
}

// ── Band/threshold constants (the magic numbers, named once) ──────────────
const double kCprRateClampLo = 60.0;
const double kCprRateClampHi = 200.0;
const double kCprHrClampLo   = 40.0;
const double kCprHrClampHi   = 200.0;

// ── Shared spot builders — the ONE place each rule lives ──────────────────
// M28: capture stores every snapshot with its signalQuality; the display
// filters, it does not hard-drop. Plot all real HR readings; low-signal
// points are visually de-emphasized by the dot builder (see _HeartRateChartCard),
// never removed — an empty/sparse chart would hide real fatigue data.
List<FlSpot> buildHrSpots(List<dynamic> vitals) => vitals
    .where((v) => v.heartRate > 0)
    .map((v) => FlSpot(v.timestampSec as double,
    (v.heartRate as double).clamp(kCprHrClampLo, kCprHrClampHi)))
    .toList();

List<FlSpot> buildRateSpots(List<dynamic> events) => events.map((c) {
  final r = (c.instantaneousRate as double) > 0
      ? c.instantaneousRate as double : c.frequency as double;
  return FlSpot(c.timestampSec as double, r.clamp(kCprRateClampLo, kCprRateClampHi));
}).toList();

List<FlSpot> buildDepthTrendSpots(List<dynamic> events, {int window = 5}) {
  if (events.length < window) return [];
  final out = <FlSpot>[];
  for (int i = window - 1; i < events.length; i++) {
    double sum = 0;
    int cnt = 0;
    for (int j = i - window + 1; j <= i; j++) {
      final d = events[j].depth as double;
      if (d.isFinite && d > 0) {        // skip unmeasured (NaN sentinel) comps
        sum += d;
        cnt++;
      }
    }
    if (cnt == 0) continue;             // whole window unmeasured — no point
    out.add(FlSpot(events[i].timestampSec as double,
        (sum / cnt).clamp(0.0, 10.0)));
  }
  return out;
}

List<FlSpot> buildPostureSpots(List<dynamic> events) => events
    .where((c) => (c.wristAlignmentAngle as double) > 0)
    .map((c) => FlSpot(c.timestampSec as double,
    (c.wristAlignmentAngle as double).clamp(0.0, 45.0)))
    .toList();

// ── Shared grade colour/label (kills the 4 copies — item 4) ───────────────
Color cprGradeColor(double g) {
  if (g >= 90) return AppColors.success;
  if (g >= 75) return AppColors.primaryAlt;
  if (g >= 55) return AppColors.warning;
  return AppColors.error;
}
String cprGradeLabel(double g) {
  if (g >= 90) return 'Excellent';
  if (g >= 75) return 'Good';
  if (g >= 55) return 'Fair';
  return 'Poor';
}
double cprDepthMin(String scenario) =>
    scenario == 'pediatric' ? CprTargets.depthMinPediatric : CprTargets.depthMin;
double cprDepthMax(String scenario) =>
    scenario == 'pediatric' ? CprTargets.depthMaxPediatric : CprTargets.depthMax;

// ─────────────────────────────────────────────────────────────────────────────
// CprChartTooltip — white tooltip with time header, session label,
//                   compression number (when available), and value
// ─────────────────────────────────────────────────────────────────────────────

/// Finds the index of the compression whose timestampSec is closest to [t].
int _nearestCompIndex(List<dynamic> comps, double t) {
  if (comps.isEmpty) return 0;
  int lo = 0, hi = comps.length - 1;
  while (lo < hi) {
    final mid = (lo + hi) ~/ 2;
    if ((comps[mid].timestampSec as double) < t) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  if (lo > 0) {
    final dLo   = ((comps[lo].timestampSec as double) - t).abs();
    final dPrev = ((comps[lo - 1].timestampSec as double) - t).abs();
    if (dPrev < dLo) return lo - 1;
  }
  return lo;
}

LineTouchTooltipData buildCprTooltip({
  required String Function(int barIndex, FlSpot spot) valueLabel,
  List<List<dynamic>>? compressionsPerBar,
  List<SessionSummary>? sessions,
  Color Function(int barIndex, FlSpot spot)? valueColorBuilder,
  bool dark = false,
}) {
  final bg       = dark ? AppColors.tooltipDark : AppColors.white;
  final divColor = dark ? AppColors.textOnDark.withValues(alpha: 0.12) : AppColors.divider;

  return LineTouchTooltipData(
    getTooltipColor:    (_) => bg,
    tooltipBorder:      BorderSide(color: divColor),
    tooltipBorderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
    tooltipPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
    getTooltipItems: (spots) {
      return spots.asMap().entries.map((e) {
        final barIdx  = e.key;
        final spot    = e.value;
        final isFirst = barIdx == 0;

        // Session label
        final sNum = sessions != null && barIdx < sessions.length
            ? sessions[barIdx].sessionNumber ?? barIdx + 1
            : barIdx + 1;
        final sLabel = 'S$sNum';

        // Compression number
        String compStr = '';
        if (compressionsPerBar != null &&
            barIdx < compressionsPerBar.length &&
            compressionsPerBar[barIdx].isNotEmpty) {
          final ci = _nearestCompIndex(compressionsPerBar[barIdx], spot.x);
          compStr = '#${ci + 1}';
        }

        // Slot color for the label
        final labelColor = dark
            ? AppColors.textOnDark.withValues(alpha: 0.7)
            : AppColors.textSecondary;
        final defaultValueColor = dark ? AppColors.textOnDark : AppColors.textPrimary;
        final valueColor = valueColorBuilder != null
            ? valueColorBuilder(barIdx, spot)
            : defaultValueColor;
        final subColor   = dark
            ? AppColors.textOnDark.withValues(alpha: 0.45)
            : AppColors.textDisabled;

        final val = valueLabel(barIdx, spot);

        // Time header on first row only
        if (isFirst) {
          return LineTooltipItem('', const TextStyle(), children: [
            TextSpan(
              text: '${fmtChartTime(spot.x)}\n',
              style: AppTypography.caption(color: subColor)
                  .copyWith(fontWeight: FontWeight.w600, height: 1.8),
            ),
            TextSpan(
              text: compStr.isNotEmpty ? '$sLabel  $compStr' : sLabel,
              style: AppTypography.caption(color: labelColor).copyWith(height: 1.6),
            ),
            TextSpan(
              text: '    $val',
              style: AppTypography.label(color: valueColor),
            ),
          ]);
        }

        return LineTooltipItem('', const TextStyle(), children: [
          TextSpan(
            text: compStr.isNotEmpty ? '$sLabel  $compStr' : sLabel,
            style: AppTypography.caption(color: labelColor).copyWith(height: 1.6),
          ),
          TextSpan(
            text: '    $val',
            style: AppTypography.label(color: valueColor),
          ),
        ]);
      }).toList();
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CprScrollableChart — the ONE scrollable multi-series line chart.
// Single-session passes 1 series; compare passes N. Owns horizontal-scroll
// state; window size is controlled by the parent card's dropdown.
// ─────────────────────────────────────────────────────────────────────────────

class CprScrollableChart extends StatefulWidget {
  final List<CprSeries> series;
  final double  minY;
  final double  maxY;
  final double  sessionLength;
  final double? windowSecs;            // null = All
  final double  windowStart;
  final void Function(double) onWindowStartChanged;
  final List<SessionSummary>? sessions; // tooltip S# labels (compare)
  final AxisTitles leftAxis;
  final List<HorizontalRangeAnnotation> bands;
  final List<HorizontalLine> guideLines;
  final double? horizontalGridInterval;
  final String Function(int barIndex, FlSpot spot) tooltipValue;
  final Color Function(int barIndex, FlSpot spot)? tooltipValueColor;
  final double  leftReserved;
  final double  height;
  final bool    curved;
  final FlDotPainter Function(int barIndex, FlSpot spot)? dotBuilder;
  final bool Function(double effectiveWindow)? showDotsWhen;

  const CprScrollableChart({
    super.key,
    required this.series,
    required this.minY,
    required this.maxY,
    required this.sessionLength,
    required this.windowSecs,
    required this.windowStart,
    required this.onWindowStartChanged,
    required this.leftAxis,
    required this.tooltipValue,
    this.sessions,
    this.bands = const [],
    this.guideLines = const [],
    this.horizontalGridInterval,
    this.tooltipValueColor,
    this.leftReserved = 28.0,
    this.height = 140.0,
    this.curved = true,
    this.dotBuilder,
    this.showDotsWhen,
  });

  @override
  State<CprScrollableChart> createState() => _CprScrollableChartState();
}

class _CprScrollableChartState extends State<CprScrollableChart> {
  double get _effectiveWindow => widget.windowSecs ?? widget.sessionLength;
  double get _windowEnd => widget.windowSecs == null
      ? widget.sessionLength
      : widget.windowStart + widget.windowSecs!;
  bool get _canScroll =>
      widget.windowSecs != null && widget.sessionLength > widget.windowSecs!;

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_canScroll) return;
    final secsPerPx =
        (widget.sessionLength - _effectiveWindow) / 260.0;
    final newStart = (widget.windowStart - d.delta.dx * secsPerPx)
        .clamp(0.0, widget.sessionLength - _effectiveWindow);
    widget.onWindowStartChanged(newStart);
  }

  int _barIndexOf(FlSpot spot) {
    for (int i = 0; i < widget.series.length; i++) {
      if (widget.series[i].spots.contains(spot)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.series.every((s) => s.spots.isEmpty)) {
      return const SizedBox.shrink();
    }
    final minX = widget.windowStart;
    final maxX = _windowEnd;

    final bars = [
      for (int i = 0; i < widget.series.length; i++)
        LineChartBarData(
          spots:    widget.series[i].spots,
          color:    widget.series[i].color,
          barWidth: widget.series.length > 1 ? 1.5 : 2,
          isCurved: widget.curved,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          preventCurveOvershootingThreshold: 0.5,
          dotData: widget.dotBuilder == null
              ? const FlDotData(show: false)
              : FlDotData(
            show: true,
            checkToShowDot: (spot, _) {
              final inWindow = spot.x >= minX && spot.x <= maxX;
              final allowed = widget.showDotsWhen
                  ?.call(_effectiveWindow) ??
                  true;
              return inWindow && allowed;
            },
            getDotPainter: (spot, _, __, ___) =>
                widget.dotBuilder!(_barIndexOf(spot), spot),
          ),
          belowBarData: BarAreaData(show: false),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onHorizontalDragUpdate: _canScroll ? _onDragUpdate : null,
          child: SizedBox(
            height: context.isLandscape ? widget.height * 0.7 : widget.height,
            child: LineChart(LineChartData(
              minX: minX, maxX: maxX,
              minY: widget.minY, maxY: widget.maxY,
              clipData: const FlClipData.all(),
              backgroundColor: cprChartBackgroundColor(),
              lineBarsData: bars,
              rangeAnnotations:
              RangeAnnotations(horizontalRangeAnnotations: widget.bands),
              extraLinesData:
              ExtraLinesData(horizontalLines: widget.guideLines),
              gridData: cprChartGridData(
                minX: minX, maxX: maxX,
                horizontalInterval: widget.horizontalGridInterval,
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: buildCprTooltip(
                  sessions: widget.sessions,
                  compressionsPerBar: widget.series.any((s) => s.comps != null)
                      ? [for (final s in widget.series) s.comps ?? const []]
                      : null,
                  valueLabel: widget.tooltipValue,
                  valueColorBuilder: widget.tooltipValueColor,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: buildCprTimeAxis(
                  minX: minX, maxX: maxX,
                  sessionLength: widget.sessionLength,
                  windowStart: widget.windowStart,
                  windowSecs: widget.windowSecs,
                ),
                leftTitles: widget.leftAxis,
              ),
            )),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: widget.leftReserved),
          child: CprScrollBar(
            windowStart:   widget.windowStart,
            sessionLength: widget.sessionLength,
            windowSecs:    _effectiveWindow,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CprChartCard — shared chart card wrapper used by session results,
// compare screen, and leaderboard stats tab.
// ─────────────────────────────────────────────────────────────────────────────

class CprChartCard extends StatelessWidget {
  final String  title;
  final String  subtitle;
  final Color   lineColor;
  final Widget  child;
  final Widget? dropdown;
  final Widget? legend;

  const CprChartCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.lineColor,
    required this.child,
    this.dropdown,
    this.legend,
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
          height: context.isLandscape ? context.screenHeight * 0.90 : null,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: context.isLandscape
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: AppSpacing.xs,
                      height: AppSpacing.iconMd,
                      decoration: AppDecorations.accentBar(color: lineColor),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: AppTypography.subheading(size: 13)),
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
                context.isLandscape ? Expanded(child: child) : child,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: AppSpacing.xs,
                height: AppSpacing.iconMd,
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
                  decoration: AppDecorations.iconChipPrimary(),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.xs),
            legend!,
          ],
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}