import 'package:flutter/material.dart';
import 'package:cpr_assist/core/core.dart';
import 'package:cpr_assist/features/training/screens/session_service.dart';

class GradeCard extends StatelessWidget {
  final SessionSummary session;

  const GradeCard({super.key, required this.session});

  // ── Derived helpers ────────────────────────────────────────────────────────

  String get _motivationalLabel {
    final g = session.totalGrade;
    if (g >= 90) return 'Excellent!';
    if (g >= 75) return 'Good job!';
    if (g >= 55) return 'Keep it up!';
    return 'Keep practicing!';
  }

  String _pct(int value) {
    if (session.compressionCount == 0) return '—';
    return '${(value / session.compressionCount * 100).round()}%';
  }

  @override
  Widget build(BuildContext context) {
    final hasHeartRate = session.patientHeartRate != null ||
        session.userHeartRate != null;
    final hasTemp = session.patientTemperature != null ||
        session.userTemperature != null;
    final hasBiometrics = hasHeartRate || hasTemp;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Gradient top ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            decoration: AppDecorations.primaryGradientCard(
              radius: 0, // clipped by ClipRRect above
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              children: [
                // ── Grade circle ─────────────────────────────────────────
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: session.totalGrade / 100,
                        strokeWidth: 10,
                        backgroundColor:
                        AppColors.textOnDark.withValues(alpha: 0.2),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.textOnDark,
                        ),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${session.totalGrade.toStringAsFixed(0)}%',
                          style: AppTypography.numericDisplay(
                            size: 36,
                            color: AppColors.textOnDark,
                          ),
                        ),
                        Text(
                          _motivationalLabel,
                          style: AppTypography.label(
                            size: 11,
                            color: AppColors.textOnDark.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Summary row ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.textOnDark.withValues(alpha: 0.1),
                    borderRadius:
                    BorderRadius.circular(AppSpacing.cardRadiusSm),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        _SummaryCell(
                          value: session.durationFormatted,
                          label: 'DURATION',
                        ),
                        _VerticalDivider(),
                        _SummaryCell(
                          value: '${session.compressionCount}',
                          label: 'COMPRESSIONS',
                        ),
                        _VerticalDivider(),
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

                const SizedBox(height: AppSpacing.md),

                // ── Quality breakdown grid ───────────────────────────────
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
                      childAspectRatio: 2.2,
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

          // ── White bottom section ─────────────────────────────────────────
          Container(
            width: double.infinity,
            color: AppColors.surfaceWhite,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avg depth ──────────────────────────────────────────
                _DetailRow(
                  icon: Icons.compress_rounded,
                  label: 'Average Depth',
                  value: session.averageDepth > 0
                      ? '${session.averageDepth.toStringAsFixed(1)} cm'
                      : '—',
                  note: 'Target: 5–6 cm',
                ),

                if (hasBiometrics) ...[
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.divider,
                  ),
                  Text(
                    'BIOMETRICS',
                    style: AppTypography.badge(
                      size: 10,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (session.patientHeartRate != null)
                    _DetailRow(
                      icon: Icons.favorite_outline_rounded,
                      label: 'Patient Heart Rate',
                      value: '${session.patientHeartRate} bpm',
                      iconColor: AppColors.error,
                    ),
                  if (session.userHeartRate != null)
                    _DetailRow(
                      icon: Icons.monitor_heart_outlined,
                      label: 'Your Heart Rate',
                      value: '${session.userHeartRate} bpm',
                      iconColor: AppColors.primary,
                    ),
                  if (session.patientTemperature != null)
                    _DetailRow(
                      icon: Icons.thermostat_rounded,
                      label: 'Patient Temperature',
                      value: '${session.patientTemperature!.toStringAsFixed(1)}°C',
                    ),
                  if (session.userTemperature != null)
                    _DetailRow(
                      icon: Icons.thermostat_outlined,
                      label: 'Your Temperature',
                      value: '${session.userTemperature!.toStringAsFixed(1)}°C',
                    ),
                ],

                // ── Session date ───────────────────────────────────────
                if (session.sessionStart != null) ...[
                  const Divider(
                    height: AppSpacing.lg,
                    color: AppColors.divider,
                  ),
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Session Date',
                    value: session.dateTimeFormatted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryCell
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;

  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VerticalDivider
// ─────────────────────────────────────────────────────────────────────────────

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.dividerThickness,
      color: AppColors.textOnDark.withValues(alpha: 0.2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatTile
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
        color: AppColors.textOnDark.withValues(alpha: 0.1),
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
// _DetailRow
// ─────────────────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Color iconColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: AppSpacing.iconLg,
            height: AppSpacing.iconLg,
            decoration: AppDecorations.iconRounded(
              bg: iconColor.withValues(alpha: 0.1),
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
                  Text(note!,
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
              ],
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyBold(
              size: 14,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}