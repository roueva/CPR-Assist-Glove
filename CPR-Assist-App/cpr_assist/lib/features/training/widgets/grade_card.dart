import 'package:flutter/material.dart';
import 'package:cpr_assist/core/core.dart';
import '../services/session_detail.dart';
import 'session_graphs.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GradeCard
//
// Full training session results card. Shown inside GradeDialog after a session
// ends. Scrollable internally since it may exceed screen height on small phones.
//
// Layout (top → bottom):
//   ① Gradient header — grade circle, motivational label, 3-col summary row
//   ② Quality breakdown — 4 stat tiles showing % of compressions on target
//   ③ White body — graphs, flow metrics, rescuer biometrics, session date
//
// File location: features/training/widgets/grade_card.dart
// ─────────────────────────────────────────────────────────────────────────────

class GradeCard extends StatelessWidget {
  final SessionDetail session;

  const GradeCard({super.key, required this.session});

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _motivationalLabel {
    final g = session.totalGrade;
    if (g >= 90) return 'Excellent!';
    if (g >= 75) return 'Good job!';
    if (g >= 55) return 'Keep it up!';
    return 'Keep practicing!';
  }

  /// Compressions on target as a percentage string, e.g. "83%"
  String _pct(int value) {
    if (session.compressionCount == 0) return '—';
    return '${(value / session.compressionCount * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final hasGraphs     = session.compressions.isNotEmpty;
    final hasBiometrics = session.userHeartRate != null ||
        session.userTemperature != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── ① Gradient header ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryAlt],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              children: [
                // ── Grade circle ─────────────────────────────────────────────
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 148,
                      height: 148,
                      child: CircularProgressIndicator(
                        value: session.totalGrade / 100,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                        AppColors.textOnDark.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.textOnDark,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${session.totalGrade.toStringAsFixed(0)}%',
                          style: AppTypography.numericDisplay(
                            size: 38,
                            color: AppColors.textOnDark,
                          ),
                        ),
                        Text(
                          _motivationalLabel,
                          style: AppTypography.label(
                            size: 11,
                            color: AppColors.textOnDark.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Summary row ──────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.textOnDark.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _SummaryCell(
                          value: session.durationFormatted,
                          label: 'DURATION',
                        ),
                        _VDivider(),
                        _SummaryCell(
                          value: '${session.compressionCount}',
                          label: 'COMPRESSIONS',
                        ),
                        _VDivider(),
                        _SummaryCell(
                          value: session.averageFrequency > 0
                              ? '${session.averageFrequency.round()}'
                              : '—',
                          label: 'AVG BPM',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Quality breakdown grid ───────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'QUALITY BREAKDOWN',
                      style: AppTypography.badge(
                        size: 10,
                        color: AppColors.textOnDark.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 2,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.sm,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.4,
                      children: [
                        _StatTile(
                          label: 'CORRECT DEPTH',
                          value: _pct(session.correctDepth),
                        ),
                        _StatTile(
                          label: 'CORRECT FREQUENCY',
                          value: _pct(session.correctFrequency),
                        ),
                        _StatTile(
                          label: 'CORRECT RECOIL',
                          value: _pct(session.correctRecoil),
                        ),
                        _StatTile(
                          label: 'DEPTH + RATE',
                          value: _pct(session.depthRateCombo),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── ② White body ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            color: AppColors.surfaceWhite,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Graphs ──────────────────────────────────────────────────
                if (hasGraphs) ...[
                  Text(
                    'PERFORMANCE OVER TIME',
                    style: AppTypography.badge(
                      size: 10,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SessionGraphs(session: session),
                  const _Divider(),
                ],

                // ── Depth & consistency details ──────────────────────────────
                Text(
                  'METRICS',
                  style: AppTypography.badge(
                    size: 10,
                    color: AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                _DetailRow(
                  icon: Icons.compress_rounded,
                  label: 'Average Depth',
                  value: session.averageDepth > 0
                      ? '${session.averageDepth.toStringAsFixed(1)} cm'
                      : '—',
                  note: 'Target: 5–6 cm',
                ),
                _DetailRow(
                  icon: Icons.straighten_rounded,
                  label: 'Depth Consistency',
                  value: session.depthConsistency > 0
                      ? '${session.depthConsistency.round()}%'
                      : '—',
                  note: 'Compressions within 5–6 cm',
                ),
                _DetailRow(
                  icon: Icons.speed_rounded,
                  label: 'Rate Consistency',
                  value: session.frequencyConsistency > 0
                      ? '${session.frequencyConsistency.round()}%'
                      : '—',
                  note: 'Compressions within 100–120 BPM',
                ),

                const _Divider(),

                // ── Flow metrics ─────────────────────────────────────────────
                Text(
                  'FLOW',
                  style: AppTypography.badge(
                    size: 10,
                    color: AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                _DetailRow(
                  icon: Icons.touch_app_outlined,
                  label: 'Hands-On Time',
                  value: session.handsOnPct,
                  note: 'Time actively compressing',
                  valueColor: _flowColor(session.handsOnRatio * 100),
                ),
                _DetailRow(
                  icon: Icons.pause_circle_outline_rounded,
                  label: 'No-Flow Time',
                  value: session.noFlowTime > 0
                      ? '${session.noFlowTime.toStringAsFixed(1)}s'
                      : '0s',
                  note: 'Pauses > 2 s between compressions',
                  valueColor: session.noFlowTime > 5
                      ? AppColors.warning
                      : AppColors.success,
                ),
                _DetailRow(
                  icon: Icons.timer_outlined,
                  label: 'Time to First Compression',
                  value: session.timeToFirstCompression > 0
                      ? '${session.timeToFirstCompression.toStringAsFixed(1)}s'
                      : '—',
                  note: 'From session start to first compression',
                  valueColor: session.timeToFirstCompression > 5
                      ? AppColors.warning
                      : AppColors.success,
                ),

                // ── Biometrics ───────────────────────────────────────────────
                if (hasBiometrics) ...[
                  const _Divider(),
                  Text(
                    'RESCUER BIOMETRICS',
                    style: AppTypography.badge(
                      size: 10,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (session.userHeartRate != null)
                    _DetailRow(
                      icon: Icons.monitor_heart_outlined,
                      label: 'Your Heart Rate',
                      value: '${session.userHeartRate} bpm',
                      iconColor: AppColors.primary,
                    ),
                  if (session.userTemperature != null)
                    _DetailRow(
                      icon: Icons.thermostat_outlined,
                      label: 'Your Temperature',
                      value: '${session.userTemperature!.toStringAsFixed(1)}°C',
                    ),
                ],

                // ── Session date ──────────────────────────────────────────────
                const _Divider(),
                _DetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Session Date',
                  value: session.dateTimeFormatted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _flowColor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.error;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryCell — one column in the 3-col summary row
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: AppTypography.numericDisplay(
                size: 20,
                color: AppColors.textOnDark,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              style: AppTypography.badge(
                size: 9,
                color: AppColors.textOnDark.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VDivider — vertical separator inside the summary row
// ─────────────────────────────────────────────────────────────────────────────

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.dividerThickness,
      color: AppColors.textOnDark.withValues(alpha: 0.2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatTile — one cell in the quality breakdown grid
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.textOnDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: AppTypography.numericDisplay(
              size: 18,
              color: AppColors.textOnDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.badge(
              size: 9,
              color: AppColors.textOnDark.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailRow — one labelled row in the white body section
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Color iconColor;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.iconColor = AppColors.primary,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + AppSpacing.xxs),
      child: Row(
        children: [
          Container(
            width: AppSpacing.iconLg,
            height: AppSpacing.iconLg,
            decoration: AppDecorations.iconRounded(
              bg: iconColor.withValues(alpha: 0.10),
              radius: AppSpacing.cardRadiusSm,
            ),
            child: Icon(icon, color: iconColor, size: AppSpacing.iconSm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyMedium(size: 13)),
                if (note != null)
                  Text(
                    note!,
                    style: AppTypography.caption(color: AppColors.textDisabled),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyBold(
              size: 14,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Divider — standard section separator in the white body
// ─────────────────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Divider(
        height: AppSpacing.dividerThickness,
        color: AppColors.divider,
      ),
    );
  }
}