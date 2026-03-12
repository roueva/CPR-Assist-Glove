import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

import '../screens/session_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SESSION CARD WIDGETS  (shared)
//
// Used by:
//   - PastSessionsScreen  (full history list)
//   - LeaderboardScreen   (_PersonalTab — personal best + recent sessions)
//
// Exports:
//   - SessionCard          Tappable card for a list; opens SessionDetailsSheet.
//   - PersonalBestCard     Gradient highlight card for the best session.
//   - SessionDetailsSheet  Bottom sheet with full session breakdown.
//   - gradeColor()         Shared grade → colour helper.
// ─────────────────────────────────────────────────────────────────────────────

// ── Shared grade colour helper ─────────────────────────────────────────────

Color gradeColor(double grade) {
  if (grade >= 90) return AppColors.success;
  if (grade >= 70) return AppColors.info;
  if (grade >= 50) return AppColors.warning;
  return AppColors.error;
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION CARD
// ─────────────────────────────────────────────────────────────────────────────

class SessionCard extends StatelessWidget {
  final SessionSummary session;
  final int sessionNumber;

  const SessionCard({
    super.key,
    required this.session,
    required this.sessionNumber,
  });

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(session.totalGrade);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm + AppSpacing.xs),
      decoration: AppDecorations.card(),
      child: Material(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Session $sessionNumber',
                      style: AppTypography.subheading(color: AppColors.primary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.chipPaddingH,
                        vertical:   AppSpacing.chipPaddingV,
                      ),
                      decoration: AppDecorations.chip(
                        color: color,
                        bg:    color.withValues(alpha: 0.12),
                      ),
                      child: Text(
                        '${session.totalGrade.toStringAsFixed(0)}%',
                        style: AppTypography.label(color: color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Date ───────────────────────────────────────────────────
                Text(
                  session.dateTimeFormatted,
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),

                // ── Quick stats ────────────────────────────────────────────
                Row(
                  children: [
                    _QuickStat(Icons.compress_rounded,
                        'Compressions', '${session.compressionCount}'),
                    _QuickStat(Icons.timer_outlined,
                        'Duration', session.durationFormatted),
                    _QuickStat(Icons.speed_rounded,
                        'Correct Depth', '${session.correctDepth}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.overlayLight,
      builder: (_) => SessionDetailsSheet(
        session:       session,
        sessionNumber: sessionNumber,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PERSONAL BEST CARD
// Gradient highlight — used at the top of the personal tab in the leaderboard
// and optionally at the top of PastSessionsScreen.
// ─────────────────────────────────────────────────────────────────────────────

class PersonalBestCard extends StatelessWidget {
  final SessionSummary session;

  const PersonalBestCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl - AppSpacing.xs),
      decoration: AppDecorations.podiumGradientCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label row ────────────────────────────────────────────────────
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Personal Best',
                style: AppTypography.label(
                    color: AppColors.textOnDark.withValues(alpha: 0.7)),
              ),
              const Spacer(),
              Text(
                session.dateFormatted,
                style: AppTypography.caption(
                    color: AppColors.textOnDark.withValues(alpha: 0.55)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),

          // ── Score ─────────────────────────────────────────────────────────
          Text(
            '${session.totalGrade.toStringAsFixed(1)}%',
            style: AppTypography.numericDisplay(
              size: 40,
              color: AppColors.textOnDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),

          // ── Pills ─────────────────────────────────────────────────────────
          Row(
            children: [
              _Pill('${session.averageFrequency.toStringAsFixed(0)} bpm'),
              const SizedBox(width: AppSpacing.sm),
              _Pill('${session.averageDepth.toStringAsFixed(1)} cm'),
              const SizedBox(width: AppSpacing.sm),
              _Pill(session.durationFormatted),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION DETAILS SHEET
// ─────────────────────────────────────────────────────────────────────────────

class SessionDetailsSheet extends StatelessWidget {
  final SessionSummary session;
  final int sessionNumber;

  const SessionDetailsSheet({
    super.key,
    required this.session,
    required this.sessionNumber,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: context.screenHeight * 0.8,
      decoration: AppDecorations.bottomSheet(),
      child: Column(
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          Container(
            width:  AppSpacing.dragHandleWidth,
            height: AppSpacing.dragHandleHeight,
            margin: const EdgeInsets.only(top: AppSpacing.sm + AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppSpacing.xxs),
            ),
          ),

          // ── Header ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl - AppSpacing.xs),
            child: Column(
              children: [
                Text(
                  'Session $sessionNumber Details',
                  style: AppTypography.heading(
                      size: 20, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  session.dateTimeFormatted,
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl - AppSpacing.xs),
              child: Column(
                children: [
                  // Grade banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.xl - AppSpacing.xs),
                    decoration: AppDecorations.primaryDarkCard(),
                    child: Column(
                      children: [
                        Text(
                          '${session.totalGrade.toStringAsFixed(0)}%',
                          style: AppTypography.numericDisplay(
                              size: 32, color: AppColors.textOnDark),
                        ),
                        Text(
                          'OVERALL GRADE',
                          style: AppTypography.label(
                              size: 13, color: AppColors.textOnDark),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl - AppSpacing.xs),

                  // Performance metrics
                  _DetailCard(
                    title: 'Performance Metrics',
                    rows: [
                      _DetailRow('Total Compressions', '${session.compressionCount}'),
                      _DetailRow('Correct Depth',      '${session.correctDepth}'),
                      _DetailRow('Correct Frequency',  '${session.correctFrequency}'),
                      _DetailRow('Correct Recoil',     '${session.correctRecoil}'),
                      _DetailRow('Avg Depth',          '${session.averageDepth.toStringAsFixed(1)} cm'),
                      _DetailRow('Avg Frequency',      '${session.averageFrequency.toStringAsFixed(0)} bpm'),
                      _DetailRow('Session Duration',   session.durationFormatted),
                    ],
                  ),

                  // Vitals — only shown if present
                  if (
                      session.userHeartRate    != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _DetailCard(
                      title: 'Vital Signs',
                      rows: [
                       // if (session.patientHeartRate != null)
                         // _DetailRow('Patient Heart Rate',
                         //     '${session.patientHeartRate} bpm'),
                       // if (session.patientTemperature != null)
                         // _DetailRow('Patient Temperature',
                        //      '${session.patientTemperature}°C'),
                        if (session.userHeartRate != null)
                          _DetailRow('Your Heart Rate',
                              '${session.userHeartRate} bpm'),
                        if (session.userTemperature != null)
                          _DetailRow('Your Temperature',
                              '${session.userTemperature}°C'),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl - AppSpacing.xs),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _QuickStat(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon,
              size: AppSpacing.iconSm - AppSpacing.xxs,
              color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppTypography.bodyMedium(size: 13)),
                Text(label,
                    style: AppTypography.caption(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  const _Pill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.chipPaddingH - AppSpacing.xxs,
        vertical:   AppSpacing.chipPaddingV,
      ),
      decoration: BoxDecoration(
        color: AppColors.textOnDark.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
      ),
      child: Text(
        label,
        style: AppTypography.label(size: 12, color: AppColors.textOnDark),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;
  const _DetailCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.subheading(color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          ...rows,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.body(color: AppColors.textSecondary)),
          Text(value, style: AppTypography.bodyBold(size: 13)),
        ],
      ),
    );
  }
}