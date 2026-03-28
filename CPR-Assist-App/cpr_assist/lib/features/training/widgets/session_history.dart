import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../account/screens/login_screen.dart';
import '../../account/screens/registration_screen.dart';
import '../screens/session_service.dart';
import '../services/export_service.dart';
import 'export_bottom_sheet.dart';
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
  if (grade >= 75) return AppColors.info;
  if (grade >= 55) return AppColors.warning;
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

  bool             _selectionMode = false;
  Set<String>      _selectedIds   = {};

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds   = {id};
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds   = {};
    });
  }

  void _selectAll(List<SessionSummary> all) {
    setState(() {
      _selectedIds = all
          .where((s) => s.id != null)
          .map((s) => s.id.toString())
          .toSet();
    });
  }

  static const _filters = ['All', 'Recent', 'Emergency', 'Training', 'No-Feedback', 'Excellent', 'Good'];

  List<SessionSummary> _apply(List<SessionSummary> all) {
    switch (_filter) {
      case 'Excellent': return all.where((s) => s.totalGrade >= 90).toList();
      case 'Good':      return all.where((s) => s.totalGrade >= 75 && s.totalGrade < 90).toList();
      case 'Recent':    return all.take(10).toList();
      case 'Emergency': return all.where((s) => s.isEmergency).toList();
      case 'No-Feedback': return all.where((s) => s.isNoFeedback).toList();
      case 'Training':    return all.where((s) => s.isTraining && !s.isNoFeedback).toList();
      default:          return all;
    }
  }

  Future<void> _exportSelected() async {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final selected  = summaries
        .where((s) => s.id != null && _selectedIds.contains(s.id.toString()))
        .toList();
    if (selected.isEmpty) return;

    UIHelper.showSnackbar(context,
        message: 'Preparing export…', icon: Icons.download_outlined);

    bool ok = false;
    try {
      ok = await ExportService.exportSessionsAsCsv(selected);
    } catch (_) {}

    if (!mounted) return;
    if (ok) {
      UIHelper.showSuccess(context, 'Export ready');
    } else {
      UIHelper.showError(context, 'Export failed. Please try again.');
    }
    _clearSelection();
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.delete_outline_rounded,
      iconColor:    AppColors.emergencyRed,
      iconBg:       AppColors.emergencyBg,
      title:        'Delete ${_selectedIds.length} sessions?',
      message:      'This permanently removes the selected sessions.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.emergencyRed,
      cancelLabel:  'Cancel',
    );
    if (confirmed != true || !mounted) return;
    final service = ref.read(sessionServiceProvider);
    for (final id in _selectedIds) {
      await service.deleteSession(int.parse(id));
    }
    ref.invalidate(sessionSummariesProvider);
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(sessionSummariesProvider);

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
        appBar: _selectionMode
            ? AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnDark,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textOnDark),
            onPressed: _clearSelection,
          ),
          title: Text(
            '${_selectedIds.length} selected',
            style: AppTypography.heading(size: 18, color: AppColors.textOnDark),
          ),
            actions: [
              // Select all
              IconButton(
                icon:    const Icon(Icons.select_all_rounded, color: AppColors.textOnDark),
                tooltip: 'Select all',
                onPressed: () {
                  final all = ref.read(sessionSummariesProvider).valueOrNull ?? [];
                  _selectAll(all);
                },
              ),
              IconButton(
                icon:    const Icon(Icons.download_outlined, color: AppColors.textOnDark),
                tooltip: 'Export selected',
                onPressed: _selectedIds.isEmpty ? null : () => _exportSelected(),
              ),
              IconButton(
                icon:    const Icon(Icons.delete_outline_rounded, color: AppColors.textOnDark),
                tooltip: 'Delete selected',
                onPressed: _selectedIds.isEmpty ? null : () => _deleteSelected(context),
              ),
            ],
        )
            : AppBar(
          backgroundColor: AppColors.primaryLight,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
            onPressed: context.pop,
          ),
          title: Text(
            'Session History',
            style: AppTypography.heading(size: 20, color: AppColors.primary),
          ),
          actions: [
            IconButton(
              icon:    const Icon(Icons.download_outlined, color: AppColors.primary),
              tooltip: 'Export all sessions',
              onPressed: () {
                final all = summaries.valueOrNull ?? [];
                if (all.isEmpty) return;
                ExportBottomSheet.showForMultipleSessions(context, sessions: all);
              },
            ),
          ],
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
          data: (all) {
            if (all.isEmpty) {
              final isLoggedIn = ref.watch(authStateProvider).isLoggedIn;
              return _EmptyState(isLoggedIn: isLoggedIn);
            }
            return _SessionsList(
              all:           all,
              filtered:      _apply(all),
              filter:        _filter,
              filters:       _filters,
              onFilter:      (f) => setState(() => _filter = f),
              selectionMode: _selectionMode,
              selectedIds:   _selectedIds,
              onLongPress:   _enterSelectionMode,
              onToggle:      _toggleSelection,
            );
          },
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
  // ADD these:
  final bool                    selectionMode;
  final Set<String>             selectedIds;
  final void Function(String)   onLongPress;
  final void Function(String)   onToggle;

  const _SessionsList({
    required this.all,
    required this.filtered,
    required this.filter,
    required this.filters,
    required this.onFilter,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggle,
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
            itemBuilder: (context, i) {
              final session   = filtered[i];
              final idStr     = session.id?.toString() ?? '';
              final isSelected = selectionMode && selectedIds.contains(idStr);
              final idx          = all.indexOf(session);
              final sessionNumber = session.sessionNumber ?? (all.length - all.indexOf(session));
              // Previous session in chronological order = next item in the list (older)
              final prevGrade = (idx + 1 < all.length && all[idx + 1].isTraining)
                  ? all[idx + 1].totalGrade
                  : null;

              final card = SessionCard(
                session:       session,
                sessionNumber: sessionNumber,
                prevGrade:     prevGrade,
                selectionMode: selectionMode,
                isSelected:    isSelected,
                onLongPress:   session.id != null
                    ? () => _showContextMenu(
                  context,
                  session:       session,
                  sessionNumber: sessionNumber,
                  onSelect:      () => onLongPress(idStr),
                )
                    : null,
                onToggle:      session.id != null
                    ? () => onToggle(idStr)
                    : null,
              );

              // Don't wrap in Dismissible during selection mode
              if (selectionMode || session.id == null) return card;

              return Dismissible(
                key:       ValueKey(session.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding:   const EdgeInsets.only(right: AppSpacing.lg),
                    margin:    const EdgeInsets.only(bottom: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color:        AppColors.emergencyBg,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.emergencyRed, size: AppSpacing.iconMd),
                  ),
                  confirmDismiss: (_) => AppDialogs.showDestructiveConfirm(
                    context,
                    icon:         Icons.delete_outline_rounded,
                    iconColor:    AppColors.emergencyRed,
                    iconBg:       AppColors.emergencyBg,
                    title:        'Delete Session?',
                    message:      'This permanently deletes this session.',
                    confirmLabel: 'Delete',
                    confirmColor: AppColors.emergencyRed,
                    cancelLabel:  'Cancel',
                  ),
                  onDismissed: (_) async {
                    final c       = ProviderScope.containerOf(context);
                    final service = c.read(sessionServiceProvider);
                    final ok = await service.deleteSession(session.id!);
                    if (ok) {
                      c.invalidate(sessionSummariesProvider);
                    } else {
                      if (context.mounted) {
                        UIHelper.showError(context, 'Failed to delete. Check your connection.');
                      }
                    }
                  },
                  child: card,
                );
              },
          ),
        ),
      ],
    );
  }
}

Future<void> _showContextMenu(
    BuildContext context, {
      required SessionSummary session,
      required int            sessionNumber,
      required VoidCallback   onSelect,
    }) async {
  await showModalBottomSheet<void>(
    context:          context,
    useRootNavigator: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin:     const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              width:      40,
              height:     4,
              decoration: BoxDecoration(
                color:        AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline_rounded),
            title:   const Text('Select'),
            onTap: () {
              context.pop();
              onSelect();
            },
          ),
          ListTile(
            leading: const Icon(Icons.notes_rounded),
            title:   Text(
              session.note?.isNotEmpty == true ? 'Edit note' : 'Add note',
            ),
            onTap: () async {
              final container = ProviderScope.containerOf(context);
              context.pop();
              final result = await AppDialogs.showNoteEditor(
                context,
                initialNote: session.note,
              );
              if (result == null) return;
              final service = container.read(sessionServiceProvider);
              final ok = await service.updateNote(
                session.id!,
                result.isEmpty ? null : result,
              );
              if (ok) {
                container.invalidate(sessionSummariesProvider);
                if (context.mounted) {
                  UIHelper.showSuccess(context, 'Note saved');
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.download_outlined,
              color: AppColors.primary,
            ),
            title: const Text('Export this session'),
            onTap: () async {
              context.pop();
              await ExportService.exportSingleSessionCsv(session);
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.emergencyRed,
            ),
            title: const Text(
              'Delete',
              style: TextStyle(color: AppColors.emergencyRed),
            ),
            onTap: () async {
              final container = ProviderScope.containerOf(context);
              context.pop();
              final confirmed = await AppDialogs.showDestructiveConfirm(
                context,
                icon:         Icons.delete_outline_rounded,
                iconColor:    AppColors.emergencyRed,
                iconBg:       AppColors.emergencyBg,
                title:        'Delete Session?',
                message:      'This permanently removes Session $sessionNumber.',
                confirmLabel: 'Delete',
                confirmColor: AppColors.emergencyRed,
                cancelLabel:  'Cancel',
              );
              if (confirmed != true) return;
              final service = container.read(sessionServiceProvider);
              final ok = await service.deleteSession(session.id!);
              if (ok) {
                container.invalidate(sessionSummariesProvider);
                if (context.mounted) {
                  UIHelper.showSuccess(context, 'Session deleted');
                }
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

// ── Stats header ───────────────────────────────────────────────────────────

class _StatsHeader extends StatelessWidget {
  final List<SessionSummary> sessions;
  const _StatsHeader({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final trainingSessions = sessions.where((s) => s.isTraining).toList();
    final avg = trainingSessions.isEmpty
        ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a + b) /
        trainingSessions.length;
    final total =
    sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);
    final avgDisplay = trainingSessions.isEmpty ? 'No data' : '${avg.toStringAsFixed(0)}%';

    return Container(
      margin:  const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.primaryDarkCard(),
      child: Row(
        children: [
          Expanded(child: _StatItem('Total Sessions', '${sessions.length}')),
          Expanded(child: _StatItem('Avg Training Grade', avgDisplay)),
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
  final bool isLoggedIn;
  const _EmptyState({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    if (!isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width:  AppSpacing.iconXl + AppSpacing.lg,
                height: AppSpacing.iconXl + AppSpacing.lg,
                decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
                child: const Icon(Icons.history_rounded,
                    size: AppSpacing.iconLg, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('No sessions saved yet',
                  style: AppTypography.subheading(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Emergency sessions are saved locally on this device.\nLog in to track progress and sync across devices.',
                textAlign: TextAlign.center,
                style: AppTypography.body(color: AppColors.textDisabled),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.push(const LoginScreen()),
                  child: const Text('Log In'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => context.push(const RegistrationScreen()),
                child: const Text('Create an account'),
              ),
            ],
          ),
        ),
      );
    }

    // Logged in, no sessions yet
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width:  AppSpacing.iconXl + AppSpacing.lg,
              height: AppSpacing.iconXl + AppSpacing.lg,
              decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
              child: const Icon(Icons.fitness_center_rounded,
                  size: AppSpacing.iconLg, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No Sessions Yet',
                style: AppTypography.subheading(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Complete your first training or emergency session\nto see your performance data here.',
              textAlign: TextAlign.center,
              style: AppTypography.body(color: AppColors.textDisabled),
            ),
          ],
        ),
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

class SessionCard extends ConsumerWidget {
  final SessionSummary session;
  final int            sessionNumber;
  final double?        prevGrade;
  // ADD:
  final bool           selectionMode;
  final bool           isSelected;
  final VoidCallback?  onLongPress;
  final VoidCallback?  onToggle;

  const SessionCard({
    super.key,
    required this.session,
    required this.sessionNumber,
    this.prevGrade,
    this.selectionMode = false,
    this.isSelected    = false,
    this.onLongPress,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = gradeColor(session.totalGrade);
    final canDelete = session.id != null;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin:     const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: isSelected
          ? AppDecorations.card().copyWith(
        border: Border.all(color: AppColors.primary, width: 2),
      )
          : AppDecorations.card(),
      child: Material(
        color:        AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onLongPress: onLongPress,
          onTap: selectionMode
              ? onToggle   // in selection mode, tap toggles
              : () async {
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
                  mainAxisAlignment: selectionMode
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.spaceBetween,
                  children: [
                    if (selectionMode) ...[
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected ? AppColors.primary : AppColors.textDisabled,
                        size:  AppSpacing.iconSm,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Text(
                        'Session $sessionNumber',
                        style: AppTypography.subheading(color: AppColors.primary),
                      ),
                    ),
                    session.isEmergency
                        ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.chipPaddingH,
                        vertical:   AppSpacing.chipPaddingV,
                      ),
                      decoration: AppDecorations.chip(
                        color: AppColors.emergencyRed,
                        bg:    AppColors.emergencyBg,
                      ),
                      child: Text(
                        'EMERGENCY',
                        style: AppTypography.label(color: AppColors.emergencyRed),
                      ),
                    )
                        : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Trend arrow — only for training sessions with a previous grade
                        if (!session.isEmergency && prevGrade != null) ...[
                          Icon(
                            session.totalGrade > prevGrade!
                                ? Icons.arrow_upward_rounded
                                : session.totalGrade < prevGrade!
                                ? Icons.arrow_downward_rounded
                                : Icons.remove_rounded,
                            size:  AppSpacing.iconSm - 4,
                            color: session.totalGrade > prevGrade!
                                ? AppColors.success
                                : session.totalGrade < prevGrade!
                                ? AppColors.error
                                : AppColors.textDisabled,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                        ],
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
// For training sessions: show consistency metrics
                if (session.isTraining) ...[
                  Row(
                    children: [
                      _QuickStat(Icons.compress_rounded,   'Compressions', '${session.compressionCount}'),
                      _QuickStat(Icons.straighten_rounded, 'Depth',        '${session.depthConsistency.toStringAsFixed(0)}%'),
                      _QuickStat(Icons.speed_rounded,      'Rate',         '${session.frequencyConsistency.toStringAsFixed(0)}%'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _QuickStat(Icons.timer_outlined,     'Duration',     session.durationFormatted),
                      _QuickStat(Icons.trending_up_rounded,'Avg Depth',    '${session.averageDepth.toStringAsFixed(1)} cm'),
                      _QuickStat(Icons.av_timer_rounded,   'Avg Rate',     '${session.averageFrequency.toStringAsFixed(0)} bpm'),
                    ],
                  ),
                ] else ...[
                  // Emergency: compressions, duration, avg depth
                  Row(
                    children: [
                      _QuickStat(Icons.compress_rounded,   'Compressions', '${session.compressionCount}'),
                      _QuickStat(Icons.timer_outlined,     'Duration',     session.durationFormatted),
                      _QuickStat(Icons.trending_up_rounded,'Avg Depth',    '${session.averageDepth.toStringAsFixed(1)} cm'),
                    ],
                  ),
                ],

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

    if (!canDelete) return card;

    return Dismissible(
      key:       ValueKey('session_${session.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await AppDialogs.showDestructiveConfirm(
          context,
          icon:         Icons.delete_outline_rounded,
          iconColor:    AppColors.emergencyRed,
          iconBg:       AppColors.emergencyBg,
          title:        'Delete Session?',
          message:      'This will permanently remove Session $sessionNumber from your history.',
          confirmLabel: 'Delete',
          confirmColor: AppColors.emergencyRed,
          cancelLabel:  'Cancel',
        ) == true;
      },
      onDismissed: (_) async {
        final service = ref.read(sessionServiceProvider);
        try {
          await service.deleteSession(session.id!);
          ref.invalidate(sessionSummariesProvider);
        } catch (_) {
          if (context.mounted) {
            UIHelper.showError(context, 'Failed to delete session');
          }
        }
      },
      background: Container(
        margin:     const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color:        AppColors.error,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: AppColors.textOnDark, size: AppSpacing.iconMd),
            const SizedBox(height: AppSpacing.xxs),
            Text('Delete', style: AppTypography.label(size: 11, color: AppColors.textOnDark))
          ],
        ),
      ),
      child: card,
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