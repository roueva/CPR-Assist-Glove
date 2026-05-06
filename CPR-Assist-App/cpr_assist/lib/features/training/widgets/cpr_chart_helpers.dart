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
            horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius:
          BorderRadius.circular(AppSpacing.buttonRadiusLg),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25)),
        ),
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
          Container(
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2))),
          Positioned(
            left: thumbL,
            child: Container(
                width: thumbW,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2))),
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
    final peak   = (e.depth as double).clamp(0.0, 10.0);
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
  final bg       = dark ? const Color(0xFF0A0E1A) : AppColors.white;
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