import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../screens/session_service.dart';
import 'session_results.dart';

// ─────────────────────────────────────────────────────────────────────────────
// session_history.dart
//
// Exports:
//   SessionHistoryScreen  — full screen: filter chips, stats header, card list
//   SessionCard           — tappable list tile; pushes SessionResultsScreen
//   PersonalBestCard      — gradient highlight used in LeaderboardScreen
//   gradeColor()          — shared grade → colour helper
//
// Entry points:
//   - SessionResultsScreen ("View Past Sessions" button at bottom)
//   - LeaderboardScreen   (_PersonalTab)
// ─────────────────────────────────────────────────────────────────────────────

// ── Shared grade colour helper ─────────────────────────────────────────────

Color gradeColor(double grade) {
  if (grade >= 90) return AppColors.success;
  if (grade >= 70) return AppColors.info;
  if (grade >= 50) return AppColors.warning;
  return AppColors.error;
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionHistoryScreen
// ─────────────────────────────────────────────────────────────────────────────

class SessionHistoryScreen extends ConsumerStatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  ConsumerState<SessionHistoryScreen> createState() =>
      _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends ConsumerState<SessionHistoryScreen> {
  String _filter = 'All';

  static const _filters = ['All', 'Recent', 'Excellent', 'Good'];

  List<SessionSummary> _apply(List<SessionSummary> all) {
    switch (_filter) {
      case 'Excellent': return all.where((s) => s.totalGrade >= 90).toList();
      case 'Good':      return all.where((s) => s.totalGrade >= 70 && s.totalGrade < 90).toList();
      case 'Recent':    return all.take(10).toList();
      default:          return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(sessionSummariesProvider);

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:       AppColors.primaryLight,
        elevation:             0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppColors.primary,
          ),
          onPressed: context.pop,
        ),
        title: Text(
          'Training History',
          style: AppTypography.heading(size: 20, color: AppColors.primary),
        ),
      ),
      body: summaries.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
        error: (e, _) => _ErrorState(
          message: e.toString(),
          onRetry: () => ref.invalidate(sessionSummariesProvider),
        ),
        data: (all) => all.isEmpty
            ? const _EmptyState()
            : _SessionsList(
          all:      all,
          filtered: _apply(all),
          filter:   _filter,
          filters:  _filters,
          onFilter: (f) => setState(() => _filter = f),
        ),
      ),
    );
  }
}

// ── Sessions list — stats header + filter chips + cards ────────────────────

class _SessionsList extends StatelessWidget {
  final List<SessionSummary>    all;
  final List<SessionSummary>    filtered;
  final String                  filter;
  final List<String>            filters;
  final void Function(String)   onFilter;

  const _SessionsList({
    required this.all,
    required this.filtered,
    required this.filter,
    required this.filters,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatsHeader(sessions: all),
        _FilterBar(filters: filters, selected: filter, onSelect: onFilter),
        Expanded(
          child: ListView.builder(
            padding:   const EdgeInsets.all(AppSpacing.md),
            itemCount: filtered.length,
            itemBuilder: (context, i) => SessionCard(
              session:       filtered[i],
              sessionNumber: all.indexOf(filtered[i]) + 1,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Stats header ───────────────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  final List<SessionSummary> sessions;
  const _StatsHeader({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final avg = sessions.isEmpty
        ? 0.0
        : sessions.map((s) => s.totalGrade).reduce((a, b) => a + b) /
        sessions.length;
    final total =
    sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);

    return Container(
      margin:  const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.primaryDarkCard(),
      child: Row(
        children: [
          Expanded(child: _StatItem('Total Sessions', '${sessions.length}')),
          Expanded(child: _StatItem('Average Grade',  '${avg.toStringAsFixed(0)}%')),
          Expanded(child: _StatItem('Compressions',   '$total')),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.numericDisplay(
            size: 20, color: AppColors.textOnDark,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.label(
            size: 11, color: AppColors.textOnDark,
          ),
        ),
      ],
    );
  }
}

// ── Filter bar ─────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final List<String>           filters;
  final String                 selected;
  final void Function(String)  onSelect;

  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.touchTargetLarge,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding:         const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount:       filters.length,
        itemBuilder: (context, i) {
          final f          = filters[i];
          final isSelected = f == selected;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              label:           Text(f),
              selected:        isSelected,
              onSelected:      (_) => onSelect(f),
              backgroundColor: AppColors.surfaceWhite,
              selectedColor:   AppColors.primary,
              labelStyle: isSelected
                  ? AppTypography.label(color: AppColors.textOnDark)
                  : AppTypography.label(color: AppColors.primary),
            ),
          );
        },
      ),
    );
  }
}

// ── Empty / error states ───────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.history_rounded,
            size:  AppSpacing.iconXl + AppSpacing.md,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Training Sessions Yet',
            style: AppTypography.subheading(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Complete your first training session\nto see your progress here',
            textAlign: TextAlign.center,
            style: AppTypography.body(color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String       message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size:  AppSpacing.iconXl + AppSpacing.md,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Something went wrong',
              style: AppTypography.subheading(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body(color: AppColors.textDisabled),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SessionCard
// Tappable list tile. Tapping pushes SessionResultsScreen (fromSummary).
// Used by SessionHistoryScreen and LeaderboardScreen.
// ─────────────────────────────────────────────────────────────────────────────

class SessionCard extends ConsumerWidget  {
  final SessionSummary session;
  final int            sessionNumber;

  const SessionCard({
    super.key,
    required this.session,
    required this.sessionNumber,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = gradeColor(session.totalGrade);

    return Container(
      margin:     const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: AppDecorations.card(),
      child: Material(
        color:        AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onTap: () async {
            if (session.id == null) {
              context.push(SessionResultsScreen.fromSummary(
                  summary: session, sessionNumber: sessionNumber));
              return;
            }
            // Show loading, then fetch full detail for graph
            final service = ProviderScope.containerOf(context).read(sessionServiceProvider);
            try {
              final detail = await service.fetchDetail(session.id!);
              if (context.mounted) {
                context.push(SessionResultsScreen.fromDetail(detail: detail));
              }
            } catch (_) {
              if (context.mounted) {
                context.push(SessionResultsScreen.fromSummary(
                    summary: session, sessionNumber: sessionNumber));
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────
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

                // ── Date ─────────────────────────────────────────────────
                Text(
                  session.dateTimeFormatted,
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Quick stats ──────────────────────────────────────────
                Row(
                  children: [
                    _QuickStat(
                      Icons.compress_rounded,
                      'Compressions',
                      '${session.compressionCount}',
                    ),
                    _QuickStat(
                      Icons.timer_outlined,
                      'Duration',
                      session.durationFormatted,
                    ),
                    _QuickStat(
                      Icons.speed_rounded,
                      'Correct Depth',
                      '${session.correctDepth}',
                    ),
                  ],
                ),

                // ── Note snippet ─────────────────────────────────────────────────────
                if (session.note?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      const Icon(
                        Icons.notes_rounded,
                        size:  AppSpacing.iconSm - 4,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          session.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PersonalBestCard
// Gradient highlight — used at the top of the personal tab in the leaderboard.
// ─────────────────────────────────────────────────────────────────────────────

class PersonalBestCard extends StatelessWidget {
  final SessionSummary session;
  const PersonalBestCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.podiumGradientCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label row ──────────────────────────────────────────────────
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Personal Best',
                style: AppTypography.label(
                  color: AppColors.textOnDark.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                session.dateFormatted,
                style: AppTypography.caption(
                  color: AppColors.textOnDark.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Score ───────────────────────────────────────────────────────
          Text(
            '${session.totalGrade.toStringAsFixed(1)}%',
            style: AppTypography.numericDisplay(
              size:  40,
              color: AppColors.textOnDark,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Pills ───────────────────────────────────────────────────────
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
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _QuickStat(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon,
            size:  AppSpacing.iconSm - AppSpacing.xxs,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppTypography.bodyMedium(size: 13)),
                Text(
                  label,
                  style: AppTypography.caption(color: AppColors.textSecondary),
                ),
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
        horizontal: AppSpacing.chipPaddingH,
        vertical:   AppSpacing.chipPaddingV,
      ),
      decoration: BoxDecoration(
        color:        AppColors.textOnDark.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
      ),
      child: Text(
        label,
        style: AppTypography.label(size: 12, color: AppColors.textOnDark),
      ),
    );
  }
}