import 'package:flutter/material.dart';
import 'package:cpr_assist/core/core.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/compression_event.dart';
import '../services/session_detail.dart';


// ─────────────────────────────────────────────────────────────────────────────
// SessionGraphs
//
// Two stacked line charts rendered on the white bottom section of GradeCard:
//   1. Depth over time   — with 5–6 cm target band
//   2. Rate over time    — with 100–120 BPM target band
//
// Only rendered when session.compressions is non-empty.
//
// File location: features/training/widgets/session_graphs.dart
// ─────────────────────────────────────────────────────────────────────────────

class SessionGraphs extends StatelessWidget {
  final SessionDetail session;

  const SessionGraphs({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final events = session.compressions;
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GraphCard(
          title: 'Compression Depth',
          unit: 'cm',
          minY: 0,
          maxY: 9,
          targetMin: CprTargets.depthMin,
          targetMax: CprTargets.depthMax,
          spots: events
              .map((e) => FlSpot(e.timestampSec, e.depth))
              .toList(),
          lineColor: AppColors.primary,
          leftLabels: const ['0', '3', '6', '9'],
          leftLabelValues: const [0, 3, 6, 9],
          targetLabel: '5–6 cm',
        ),
        const SizedBox(height: AppSpacing.md),
        _GraphCard(
          title: 'Compression Rate',
          unit: 'BPM',
          minY: 60,
          maxY: 160,
          targetMin: CprTargets.rateMin,
          targetMax: CprTargets.rateMax,
          spots: events
              .map((e) => FlSpot(e.timestampSec, e.frequency))
              .toList(),
          lineColor: AppColors.success,
          leftLabels: const ['60', '100', '120', '160'],
          leftLabelValues: const [60, 100, 120, 160],
          targetLabel: '100–120 BPM',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GraphCard — individual chart with target band
// ─────────────────────────────────────────────────────────────────────────────

class _GraphCard extends StatelessWidget {
  final String title;
  final String unit;
  final double minY;
  final double maxY;
  final double targetMin;
  final double targetMax;
  final List<FlSpot> spots;
  final Color lineColor;
  final List<String> leftLabels;
  final List<double> leftLabelValues;
  final String targetLabel;

  const _GraphCard({
    required this.title,
    required this.unit,
    required this.minY,
    required this.maxY,
    required this.targetMin,
    required this.targetMax,
    required this.spots,
    required this.lineColor,
    required this.leftLabels,
    required this.leftLabelValues,
    required this.targetLabel,
  });

  @override
  Widget build(BuildContext context) {
    final maxX = spots.isEmpty ? 60.0 : spots.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ─────────────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: AppSpacing.xxs + AppSpacing.xs, // 6
              height: AppSpacing.md,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(AppSpacing.xxs),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTypography.subheading(size: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: AppDecorations.chip(
                color: lineColor,
                bg: lineColor.withValues(alpha: 0.08),
              ),
              child: Text(
                'Target: $targetLabel',
                style: AppTypography.badge(size: 9, color: lineColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Chart ──────────────────────────────────────────────────────────
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: maxX,

              // ── Target band ────────────────────────────────────────────
              betweenBarsData: [],
              rangeAnnotations: RangeAnnotations(
                horizontalRangeAnnotations: [
                  HorizontalRangeAnnotation(
                    y1: targetMin,
                    y2: targetMax,
                    color: lineColor.withValues(alpha: 0.10),
                  ),
                ],
              ),

              // ── Grid ──────────────────────────────────────────────────
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxY - minY) / 3,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: AppColors.divider,
                  strokeWidth: AppSpacing.dividerThickness,
                ),
              ),

              // ── Border ─────────────────────────────────────────────────
              borderData: FlBorderData(show: false),

              // ── Axes ──────────────────────────────────────────────────
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: _niceInterval(maxX),
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min && value != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          '${value.toInt()}s',
                          style: AppTypography.caption(
                            color: AppColors.textDisabled,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final idx = leftLabelValues.indexOf(value);
                      if (idx == -1) return const SizedBox.shrink();
                      return Text(
                        leftLabels[idx],
                        style: AppTypography.caption(
                          color: AppColors.textDisabled,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // ── Line ──────────────────────────────────────────────────
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: lineColor,
                  barWidth: 2,
                  dotData: FlDotData(
                    show: spots.length < 30, // only show dots on short sessions
                    getDotPainter: (spot, pct, bar, idx) =>
                        FlDotCirclePainter(
                          radius: 3,
                          color: lineColor,
                          strokeWidth: 1.5,
                          strokeColor: AppColors.surfaceWhite,
                        ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: lineColor.withValues(alpha: 0.06),
                  ),
                ),
              ],

              // ── Touch ─────────────────────────────────────────────────
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.primaryDark,
                  tooltipRoundedRadius: AppSpacing.cardRadiusSm,
                  getTooltipItems: (spots) => spots
                      .map(
                        (s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)} $unit',
                      AppTypography.badge(
                        size: 10,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  )
                      .toList(),
                ),
              ),
            ),
          ),
        ),

        // ── Target boundary lines (drawn as horizontal dashed indicators) ─
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            _TargetLine(color: lineColor, label: '${targetMin.toStringAsFixed(0)} $unit'),
            const Spacer(),
            _TargetLine(color: lineColor, label: '${targetMax.toStringAsFixed(0)} $unit'),
          ],
        ),
      ],
    );
  }

  double _niceInterval(double maxX) {
    if (maxX <= 30) return 10;
    if (maxX <= 60) return 15;
    if (maxX <= 120) return 30;
    return 60;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TargetLine — small label showing target boundary value
// ─────────────────────────────────────────────────────────────────────────────

class _TargetLine extends StatelessWidget {
  final Color color;
  final String label;

  const _TargetLine({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSpacing.md,
          height: AppSpacing.dividerThickness,
          color: color.withValues(alpha: 0.4),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.caption(color: color.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}