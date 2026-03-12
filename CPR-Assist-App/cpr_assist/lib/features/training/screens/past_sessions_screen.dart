import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../widgets/session_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PastSessionsScreen
//
// Shows the logged-in user's full training history.
// Reachable from GradeScreen and LeaderboardScreen — no login gate here,
// but the data provider itself requires auth to fetch.
// ─────────────────────────────────────────────────────────────────────────────

class PastSessionsScreen extends ConsumerStatefulWidget {
  const PastSessionsScreen({super.key});

  @override
  ConsumerState<PastSessionsScreen> createState() => _PastSessionsScreenState();
}

class _PastSessionsScreenState extends ConsumerState<PastSessionsScreen> {
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
        backgroundColor: AppColors.primaryLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
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

// ─────────────────────────────────────────────────────────────────────────────
// Sessions list — stats header + filter chips + cards
// ─────────────────────────────────────────────────────────────────────────────

class _SessionsList extends StatelessWidget {
  final List<SessionSummary> all;
  final List<SessionSummary> filtered;
  final String filter;
  final List<String> filters;
  final void Function(String) onFilter;

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
        _FilterBar(
          filters:  filters,
          selected: filter,
          onSelect: onFilter,
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: filtered.length,
            itemBuilder: (context, i) => SessionCard(
              session:       filtered[i],
              // Preserve descending numbering relative to the full list
              sessionNumber: all.indexOf(filtered[i]) + 1,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats header
// ─────────────────────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(AppSpacing.xl - AppSpacing.xs),
      decoration: AppDecorations.primaryDarkCard(),
      child: Row(
        children: [
          Expanded(child: _StatItem('Total Sessions',  '${sessions.length}')),
          Expanded(child: _StatItem('Average Grade',   '${avg.toStringAsFixed(0)}%')),
          Expanded(child: _StatItem('Compressions',    '$total')),
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
        Text(value,
            style: AppTypography.numericDisplay(
                size: 20, color: AppColors.textOnDark)),
        const SizedBox(height: AppSpacing.xs),
        Text(label,
            textAlign: TextAlign.center,
            style: AppTypography.label(
                size: 11, color: AppColors.textOnDark)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final void Function(String) onSelect;

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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: filters.length,
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.history_rounded,
              size: AppSpacing.iconXl + AppSpacing.md,
              color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.md),
          Text('No Training Sessions Yet',
              style:
              AppTypography.subheading(color: AppColors.textSecondary)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
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
            const Icon(Icons.error_outline_rounded,
                size: AppSpacing.iconXl + AppSpacing.md,
                color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text('Something went wrong',
                style: AppTypography.subheading(
                    color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Text(message,
                textAlign: TextAlign.center,
                style: AppTypography.body(color: AppColors.textDisabled)),
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