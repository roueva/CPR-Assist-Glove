import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../account/screens/login_screen.dart';
import '../../account/screens/registration_screen.dart';
import '../screens/session_service.dart';
import '../services/export_service.dart';
import '../services/session_detail.dart';
import '../services/session_local_storage.dart';
import 'cpr_chart_helpers.dart';
import 'export_bottom_sheet.dart';
import 'session_results.dart';
import 'session_compare_screen.dart';

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

Color gradeColor(double grade) => cprGradeColor(grade);

// ─────────────────────────────────────────────────────────────────────────────
// SessionHistoryScreen
// ─────────────────────────────────────────────────────────────────────────────

class SessionHistoryScreen extends ConsumerStatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  ConsumerState<SessionHistoryScreen> createState() =>
      _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends ConsumerState<SessionHistoryScreen>
    with TickerProviderStateMixin {
  late TabController _modeTabController;

  String _filter     = 'All';
  int    _modeIndex  = 0; // 0=All, 1=Training, 2=Emergency
  String _sortOrder  = 'newest';
  String _searchQuery = '';

  bool             _selectionMode = false;
  Set<String>      _selectedIds   = {};

  @override
  void initState() {
    super.initState();
    _modeTabController = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_modeTabController.indexIsChanging) {
          setState(() {
            _modeIndex = _modeTabController.index;
            _filter    = 'All';
            // Reset grade sort when switching to Emergency — no grades there
            if (_modeTabController.index == 2 &&
                (_sortOrder == 'grade_high' || _sortOrder == 'grade_low')) {
              _sortOrder = 'newest';
            }
          });
        }
      });
  }

  @override
  void dispose() {
    _modeTabController.dispose();
    super.dispose();
  }

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
  void _deselectAll() {
    setState(() {
      _selectedIds = {};
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

  List<SessionSummary> _apply(List<SessionSummary> all) {
    // 1. Mode tab pre-filter
    List<SessionSummary> base;
    switch (_modeIndex) {
      case 1: base = all.where((s) => s.isTraining).toList(); break;
      case 2: base = all.where((s) => s.isEmergency).toList(); break;
      default: base = List.of(all);
    }

    // 2. Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      base = base.where((s) =>
      s.dateTimeFormatted.toLowerCase().contains(q) ||
          (s.note?.toLowerCase().contains(q) ?? false) ||
          (s.sessionNumber?.toString().contains(q) ?? false)
      ).toList();
    }

    // 3. Pill filter
    switch (_filter) {
      case 'Pediatric':
        base = base.where((s) => s.scenario == 'pediatric').toList();
        break;
      case 'Adult':
        base = base.where((s) => s.scenario != 'pediatric').toList();
        break;
      case 'No-Feedback':
        base = base.where((s) => s.isNoFeedback).toList();
        break;
      default:
        break;
    }

    // 4. Sort
    switch (_sortOrder) {
      case 'oldest':
        base.sort((a, b) => (a.sessionStart ?? DateTime(0)).compareTo(b.sessionStart ?? DateTime(0)));
        break;
      case 'grade_high':
        base.sort((a, b) => b.totalGrade.compareTo(a.totalGrade));
        break;
      case 'grade_low':
        base.sort((a, b) => a.totalGrade.compareTo(b.totalGrade));
        break;
      case 'duration_desc':
        base.sort((a, b) => b.sessionDuration.compareTo(a.sessionDuration));
        break;
      case 'duration_asc':
        base.sort((a, b) => a.sessionDuration.compareTo(b.sessionDuration));
        break;
      default: // newest
        base.sort((a, b) => (b.sessionStart ?? DateTime(0)).compareTo(a.sessionStart ?? DateTime(0)));
    }

    return base;
  }

  List<String> get _filtersForMode {
    switch (_modeIndex) {
      case 1: // Training
        return ['All', 'Adult', 'Pediatric', 'No-Feedback'];
      case 2: // Emergency
        return ['All', 'Adult', 'Pediatric'];
      default: // All
        return ['All', 'Adult', 'Pediatric', 'No-Feedback'];
    }
  }

  Future<void> _exportSelected() async {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final selected  = summaries
        .where((s) => s.id != null && _selectedIds.contains(s.id.toString()))
        .toList();
    if (selected.isEmpty) return;
    _clearSelection();

    // Single session — fetch full detail so Raw CSV tab is available
    if (selected.length == 1) {
      final summary = selected.first;
      SessionDetail? detail;
      try {
        detail = await ref.read(sessionServiceProvider).fetchDetailForSummary(summary);
      } catch (e) {
        debugPrint('fetchDetailForSummary for export failed: $e');
        if (mounted) {
          UIHelper.showWarning(
            context,
            "Couldn't load full session — only summary CSV will be available.",
          );
        }
      }
      if (!mounted) return;
      await ExportBottomSheet.showForSingleSession(
        context,
        summary: summary,
        detail:  detail,
      );
      return;
    }

    // Multiple sessions — summary PDF + CSV only
    await ExportBottomSheet.showForMultipleSessions(context, sessions: selected);
  }


  Future<void> _deleteSelected(BuildContext context) async {
    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon:         Icons.delete_outline_rounded,
      iconColor:    AppColors.emergency,
      iconBg:       AppColors.errorBg,
      title:        'Delete ${_selectedIds.length} sessions?',
      message:      'This permanently removes the selected sessions.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.emergency,
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

  void _compareSelected() {
    final all      = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final selected = all
        .where((s) => s.id != null && _selectedIds.contains(s.id.toString()))
        .toList();
    if (selected.length < 2) return;

    // All sessions must share the same mode and scenario
    final firstMode     = selected.first.mode;
    final firstScenario = selected.first.scenario;
    final mismatch = selected.any(
          (s) => s.mode != firstMode || s.scenario != firstScenario,
    );
    if (mismatch) {
      UIHelper.showSnackbar(
        context,
        message: 'Sessions must be the same mode and scenario to compare.',
        icon: Icons.warning_amber_rounded,
      );
      return;
    }

    context.push(SessionCompareScreen(sessions: selected));
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(sessionSummariesProvider);

    return Scaffold(
      backgroundColor: AppColors.white,
        appBar: _selectionMode
            ? AppBar(
          backgroundColor: AppColors.cprCardBg,
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
              Builder(builder: (ctx) {
                final all = ref.read(sessionSummariesProvider).valueOrNull ?? [];
                final allSelected = all
                    .where((s) => s.id != null)
                    .every((s) => _selectedIds.contains(s.id.toString()));
                return IconButton(
                  icon: Icon(
                    allSelected
                        ? Icons.deselect_rounded
                        : Icons.select_all_rounded,
                    color: AppColors.textOnDark,
                  ),
                  tooltip: allSelected ? 'Deselect all' : 'Select all',
                  onPressed: () {
                    if (allSelected) {
                      _deselectAll();
                    } else {
                      _selectAll(all);
                    }
                  },
                );
              }),
              if (_selectedIds.length >= 2 && _selectedIds.length <= 4)
                IconButton(
                  icon:    const Icon(Icons.compare_arrows_rounded, color: AppColors.textOnDark),
                  tooltip: 'Compare sessions',
                  onPressed: _compareSelected,
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
          backgroundColor: AppColors.white,
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.primary),
                color: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                ),
                onSelected: (value) async {
                  final all = summaries.valueOrNull ?? [];
                  if (all.isEmpty) return;
                  if (value == 'export') {
                    ExportBottomSheet.showForMultipleSessions(context, sessions: all);
                  } else if (value == 'delete') {
                    final confirmed = await AppDialogs.showDestructiveConfirm(
                      context,
                      icon:         Icons.delete_outline_rounded,
                      iconColor:    AppColors.emergency,
                      iconBg:       AppColors.errorBg,
                      title:        'Delete all sessions?',
                      message:      'This permanently removes all ${all.length} sessions.',
                      confirmLabel: 'Delete All',
                      confirmColor: AppColors.emergency,
                      cancelLabel:  'Cancel',
                    );
                    if (confirmed != true || !mounted) return;
                    final service = ref.read(sessionServiceProvider);
                    for (final s in all) {
                      if (s.id != null) await service.deleteSession(s.id!);
                    }
                    ref.invalidate(sessionSummariesProvider);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'export',
                    child: Row(
                      children: [
                        const Icon(Icons.download_outlined,
                            size: AppSpacing.iconSm, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Export all',
                            style: AppTypography.body(color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded,
                            size: AppSpacing.iconSm, color: AppColors.emergency),
                        const SizedBox(width: AppSpacing.sm),
                        Text('Delete all',
                            style: AppTypography.body(color: AppColors.emergency)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
        ),
      body: SafeArea(
        top: false,
        child: summaries.when(
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
            final isLoggedIn = ref
                .watch(authStateProvider)
                .isLoggedIn;
            return RefreshIndicator(
              onRefresh: () async {
                final isLoggedIn = ref
                    .read(authStateProvider)
                    .isLoggedIn;
                if (isLoggedIn) {
                  final service = ref.read(sessionServiceProvider);
                  final locals = await SessionLocalStorage.loadAll();
                  final pending = locals
                      .where((d) => !d.syncedToBackend)
                      .toList();
                  for (final detail in pending) {
                    final id = await service.saveDetail(detail);
                    if (id != null) await SessionLocalStorage.markSynced(
                        detail);
                  }
                }
                ref.invalidate(sessionSummariesProvider);
              },
              color: AppColors.primary,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: context.screenHeight * 0.7,
                    child: _EmptyState(
                      isLoggedIn: isLoggedIn,
                      onRefresh: () async {
                        final isLoggedIn = ref
                            .read(authStateProvider)
                            .isLoggedIn;
                        if (isLoggedIn) {
                          final service = ref.read(sessionServiceProvider);
                          final locals = await SessionLocalStorage.loadAll();
                          final pending = locals.where((d) =>
                          !d.syncedToBackend).toList();
                          for (final detail in pending) {
                            final id = await service.saveDetail(detail);
                            if (id != null) await SessionLocalStorage
                                .markSynced(detail);
                          }
                        }
                        ref.invalidate(sessionSummariesProvider);
                      },
                    ),
                  ),
                ],
              ),
            );
          }
          return _SessionsList(
            all: all,
            filtered: _apply(all),
            filter: _filter,
            filters: _filtersForMode,
            onFilter: (f) => setState(() => _filter = f),
            sortOrder: _sortOrder,
            onSortChanged: (v) => setState(() => _sortOrder = v),
            searchQuery: _searchQuery,
            onSearchChanged: (v) => setState(() => _searchQuery = v),
            modeTabController: _modeTabController,
            selectionMode: _selectionMode,
            selectedIds: _selectedIds,
            onLongPress: _enterSelectionMode,
            onToggle: _toggleSelection,
            onRefresh: () => ref.invalidate(sessionSummariesProvider),
          );
        },
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
  final String                  sortOrder;
  final void Function(String)   onSortChanged;
  final String                  searchQuery;
  final void Function(String)   onSearchChanged;
  final TabController           modeTabController;
  final VoidCallback            onRefresh;
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
    required this.sortOrder,
    required this.onSortChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.modeTabController,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _EvictionWarningBanner(sessionCount: all.length),
        _StatsHeader(sessions: filtered),

        // ── Mode tabs ──────────────────────────────────────────────────────
        Container(
          color: AppColors.white,
          child: TabBar(
            controller: modeTabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.0,
            dividerColor: AppColors.divider.withValues(alpha: 0.45),
            labelStyle: AppTypography.label(color: AppColors.primary),
            unselectedLabelStyle: AppTypography.caption(
              color: AppColors.textSecondary,
            ),
            tabs: const [
              Tab(text: 'ALL'),
              Tab(text: 'TRAINING'),
              Tab(text: 'EMERGENCY'),
            ],
          ),
        ),

        // ── Filters + search/sort + list background ────────────────────────
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.screenBgGrey,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                _FilterBar(
                  filters: filters,
                  selected: filter,
                  onSelect: onFilter,
                ),

                _SearchSortRow(
                  count:           filtered.length,
                  sortOrder:       sortOrder,
                  onSortChanged:   onSortChanged,
                  searchQuery:     searchQuery,
                  onSearchChanged: onSearchChanged,
                  showGradeSort:   modeTabController.index != 2,
                ),

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => onRefresh(),
                    color: AppColors.primary,
                    child: filtered.isEmpty
                        ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: Text(
                              'No sessions match this filter.',
                              style: AppTypography.body(
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                        : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.md + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final session = filtered[i];
                        final idStr = session.id?.toString() ?? '';
                        final isSelected =
                            selectionMode && selectedIds.contains(idStr);
                        final idx = all.indexOf(session);
                        final sessionNumber =
                            session.sessionNumber ?? (all.length - idx);
                        final prevGrade =
                        (idx + 1 < all.length && all[idx + 1].isTraining)
                            ? all[idx + 1].totalGrade
                            : null;

                        return SessionCard(
                          session: session,
                          sessionNumber: sessionNumber,
                          prevGrade: prevGrade,
                          selectionMode: selectionMode,
                          isSelected: isSelected,
                          onLongPress:
                          session.id != null ? () => onLongPress(idStr) : null,
                          onToggle:
                          session.id != null ? () => onToggle(idStr) : null,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
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
              decoration: AppDecorations.dragHandle(),
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
              color: AppColors.emergency,
            ),
            title: const Text(
              'Delete',
              style: TextStyle(color: AppColors.emergency),
            ),
            onTap: () async {
              final container = ProviderScope.containerOf(context);
              context.pop();
              final confirmed = await AppDialogs.showDestructiveConfirm(
                context,
                icon:         Icons.delete_outline_rounded,
                iconColor:    AppColors.emergency,
                iconBg:       AppColors.errorBg,
                title:        'Delete Session?',
                message:      'This permanently removes Session $sessionNumber.',
                confirmLabel: 'Delete',
                confirmColor: AppColors.emergency,
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
    final totalCompressions =
    sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);

    final totalSeconds =
    sessions.fold<int>(0, (sum, s) => sum + s.sessionDuration);

    final timeDisplay = _formatDuration(totalSeconds);
    final totalDisplay = _formatCount(totalCompressions);

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.statsHeaderCard(),
      child: Row(
        children: [
          Expanded(child: _StatItem('Sessions', '${sessions.length}')),
          Expanded(child: _StatItem('CPR Time', timeDisplay)),
          Expanded(child: _StatItem('Compressions', totalDisplay)),
        ],
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  static String _formatDuration(int seconds) {
    if (seconds <= 0) return '—';

    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;

    if (hours > 0) {
      final remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}m';
    }

    return '${minutes}m';
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
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        itemCount: filters.length,
        itemBuilder: (context, i) {
          final f = filters[i];
          final isSelected = f == selected;

          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child:
            FilterChip(
              label: Text(f),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) => onSelect(f),

              elevation: 0,
              pressElevation: 0,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),

              backgroundColor: AppColors.white,
              selectedColor: AppColors.primary,

              side: BorderSide(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : AppColors.divider.withValues(alpha: 0.75),
                width: 1,
              ),

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),

              labelStyle: isSelected
                  ? AppTypography.label(
                size: 12,
                color: AppColors.textOnDark,
              )
                  : AppTypography.label(
                size: 12,
                color: AppColors.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchSortRow extends StatefulWidget {
  final int                    count;
  final String                 sortOrder;
  final void Function(String)  onSortChanged;
  final String                 searchQuery;
  final void Function(String)  onSearchChanged;
  final bool                   showGradeSort;


  const _SearchSortRow({
    required this.count,
    required this.sortOrder,
    required this.onSortChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.showGradeSort,
  });

  @override
  State<_SearchSortRow> createState() => _SearchSortRowState();
}

class _SearchSortRowState extends State<_SearchSortRow> {
  bool _showSearch = false;
  late final TextEditingController _ctrl;
  final _sortLayerLink = LayerLink();
  OverlayEntry? _sortOverlay;
  bool get _sortOpen => _sortOverlay != null;


  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.searchQuery);
  }

  @override
  void dispose() {
    _sortOverlay?.remove();
    _ctrl.dispose();
    super.dispose();
  }


  void _openSortOverlay() {
    _sortOverlay?.remove();
    String liveSortOrder = widget.sortOrder;
    _sortOverlay = OverlayEntry(
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closeSortOverlay,
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.transparent)),
            CompositedTransformFollower(
              link:           _sortLayerLink,
              showWhenUnlinked: false,
              targetAnchor:   Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset:         const Offset(0, 6),
              child: Material(
                color: Colors.transparent,
                child: _SortPopup(
                  current:       liveSortOrder,
                  showGradeSort: widget.showGradeSort,
                  onSelect: (v) {
                    widget.onSortChanged(v);
                    liveSortOrder = v;              // update local copy
                    _sortOverlay?.markNeedsBuild(); // rebuild overlay with new value
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_sortOverlay!);
    setState(() {});
  }

  void _closeSortOverlay() {
    _sortOverlay?.remove();
    _sortOverlay = null;
    setState(() {});
  }



  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${widget.count} session${widget.count == 1 ? '' : 's'}',
                style: AppTypography.caption(color: AppColors.textSecondary),
              ),
              const Spacer(),
              // Search toggle
              GestureDetector(
                onTap: () => setState(() {
                  _showSearch = !_showSearch;
                  if (!_showSearch) {
                    _ctrl.clear();
                    widget.onSearchChanged('');
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Icon(
                    Icons.search_rounded,
                    size:  AppSpacing.iconSm,
                    color: _showSearch ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Sort dropdown
      CompositedTransformTarget(
        link: _sortLayerLink,
          child: GestureDetector(
            onTap: _sortOpen ? _closeSortOverlay : _openSortOverlay,
            child: Builder(builder: (_) {
              final active = widget.sortOrder != 'newest' || _sortOpen;
              final fg = active ? AppColors.primary : AppColors.textSecondary;
              return SizedBox(
                width: 130,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded, size: AppSpacing.iconSm, color: fg),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Sort: ${_sortLabel(widget.sortOrder)}',
                          style: AppTypography.caption(color: fg)),
                    ],
                  ),
                ),
              );
            }),
          ),
      ),
            ],
          ),
          if (_showSearch) ...[
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller:    _ctrl,
              autofocus:     true,
              onChanged:     widget.onSearchChanged,
              style:         AppTypography.body(size: 12),
              decoration: InputDecoration(
                hintText:        'Search by date or note…',
                hintStyle:       AppTypography.body(
                    size: 12, color: AppColors.textDisabled),
                prefixIcon:      const Icon(Icons.search_rounded,
                    size: AppSpacing.iconSm, color: AppColors.textSecondary),
                suffixIcon: _ctrl.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: AppSpacing.iconSm, color: AppColors.textSecondary),
                  onPressed: () {
                    _ctrl.clear();
                    widget.onSearchChanged('');
                    setState(() {});
                  },
                )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm),
                filled:          true,
                fillColor:       AppColors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  borderSide:   BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  borderSide:   BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  borderSide:   BorderSide.none,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _sortLabel(String order) {
    switch (order) {
      case 'oldest':        return 'Date ↑';
      case 'grade_high':    return 'Grade ↓';
      case 'grade_low':     return 'Grade ↑';
      case 'duration_desc': return 'Duration ↓';
      case 'duration_asc':  return 'Duration ↑';
      default:              return 'Date ↓';
    }
  }
}

// ── Empty / error states ───────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool isLoggedIn;
  final VoidCallback onRefresh;   // ← add this
  const _EmptyState({required this.isLoggedIn, required this.onRefresh});

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
            const SizedBox(height: AppSpacing.lg),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded,
                  size: AppSpacing.iconSm, color: AppColors.primary),
              label: Text('Refresh',
                  style: AppTypography.label(color: AppColors.primary)),
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

  String _formatDurationShort(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = gradeColor(session.totalGrade);

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin:     const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: isSelected
          ? AppDecorations.selectedCard().copyWith(
        border: Border.all(color: AppColors.primary, width: 2),
      )
          : AppDecorations.card(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Material(
          color: AppColors.white,
          child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onLongPress: onLongPress,
          onTap: selectionMode
              ? onToggle
              : () => openSessionResults(context, ref, summary: session),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Colour accent bar ─────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppSpacing.cardRadius),
                  topRight: Radius.circular(AppSpacing.cardRadius),
                ),
                child: Container(
                  height: 4,
                  color: session.isEmergency
                      ? AppColors.emergencyMode
                      : session.isNoFeedback
                      ? AppColors.primaryAlt
                      : AppColors.primary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header: selection tick · title · badges · right ──
                    Row(
                      children: [
                        if (selectionMode) ...[
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textDisabled,
                            size: AppSpacing.iconSm,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
              Expanded(
                child: Text(
                  'Session $sessionNumber',
                  style: AppTypography.subheading(
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
                        const SizedBox(width: AppSpacing.sm),
                        _SessionOutcome(
                          session:   session,
                          prevGrade: prevGrade,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        _ModeBadge(
                          label: session.isEmergency ? 'Emergency' : 'Training',
                          color: session.isEmergency
                              ? AppColors.emergencyMode
                              : AppColors.primary,
                          bg: session.isEmergency
                              ? AppColors.emergencyModeBg
                              : AppColors.primaryLight,
                        ),

                        if (!session.isEmergency && session.isNoFeedback)
                          _ModeBadge(
                            label: 'No feedback',
                            color: AppColors.primaryAlt,
                            bg: AppColors.primaryAlt.withValues(alpha: 0.10),
                          ),

                        _ModeBadge(
                          label: session.scenario == 'pediatric' ? 'Pediatric' : 'Adult',
                          color: session.scenario == 'pediatric'
                              ? AppColors.pediatric
                              : AppColors.textSecondary,
                          bg: session.scenario == 'pediatric'
                              ? AppColors.pediatricLight
                              : AppColors.screenBgGrey,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xs),

                    // ── Subtitle: date · time · duration ───────────────
                    Text(
                      '${session.relativeDateLabel} · ${session.timeLabel} · ${_formatDurationShort(session.sessionDuration)}',
                      style: AppTypography.caption(
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── 3 metrics ──────────────────────────────────────
                    Row(
                      children: [
                        _CardMetric(
                          value: '${session.compressionCount}',
                          label: 'Compressions',
                          color: AppColors.textPrimary,
                        ),
                        _CardMetric(
                          value: session.averageDepth > 0
                              ? '${session.averageDepth.toStringAsFixed(1)} cm'
                              : '—',
                          label: 'Avg Depth',
                          color: session.averageDepth >= 5.0 &&
                              session.averageDepth <= 6.0
                              ? AppColors.success
                              : session.averageDepth > 0
                              ? AppColors.warning
                              : AppColors.textDisabled,
                        ),
                        _CardMetric(
                          value: session.averageFrequency > 0
                              ? '${session.averageFrequency.round()} bpm'
                              : '—',
                          label: 'Avg Rate',
                          color: session.averageFrequency >= 100 &&
                              session.averageFrequency <= 120
                              ? AppColors.success
                              : session.averageFrequency > 0
                              ? AppColors.warning
                              : AppColors.textDisabled,
                        ),
                      ],
                    ),

                    // ── Note snippet ──────────────────────────────────
                    if ((session.note ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.divider.withValues(alpha: 0.50),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: 13,
                            color: AppColors.textSecondary.withValues(alpha: 0.80),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              session.note!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption(
                                color: AppColors.textSecondary.withValues(alpha: 0.95),
                              ).copyWith(
                                fontSize: 11,
                                height: 1.15,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
    return card;
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

// Mode-aware prominent right element: grade (training) or pulse outcome
// (emergency). Mirrors the _LegendCard pattern in session_compare_screen.
class _SessionOutcome extends StatelessWidget {
  final SessionSummary session;
  final double?         prevGrade;
  const _SessionOutcome({required this.session, this.prevGrade});

  @override
  Widget build(BuildContext context) {
    if (session.isEmergency) {
      final detected = session.pulseDetectedFinal;
      final prompted = session.pulseChecksPrompted > 0;
      final text  = detected
          ? 'Pulse Detected'
          : prompted ? 'No Pulse' : 'Pulse Uncertain';
      final color = detected
          ? AppColors.success
          : prompted ? AppColors.error : AppColors.textDisabled;
      return Text(text,
          style: AppTypography.label(color: color),
          textAlign: TextAlign.end);
    }

    // Training
    if (session.totalGrade <= 0) {
      return Text('—',
          style: AppTypography.label(color: AppColors.textDisabled));
    }
    final c = gradeColor(session.totalGrade);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prevGrade != null) ...[
          Icon(
            session.totalGrade > prevGrade!
                ? Icons.arrow_upward_rounded
                : session.totalGrade < prevGrade!
                ? Icons.arrow_downward_rounded
                : Icons.remove_rounded,
            size: AppSpacing.iconSm - 4,
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
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('${session.totalGrade.toStringAsFixed(0)}%',
              style: AppTypography.label(color: c)),
        ),
      ],
    );
  }
}

class _CardMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _CardMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyBold(
              size: 15,
              color: color,
            ).copyWith(
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              color: AppColors.textSecondary,
            ).copyWith(
              fontSize: 11,
              height: 1.1,
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
      decoration: AppDecorations.pill(
        bg:     AppColors.textOnDark.withValues(alpha: 0.15),
        radius: AppSpacing.buttonRadiusLg,
      ),
      child: Text(
        label,
        style: AppTypography.label(size: 12, color: AppColors.textOnDark),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _ModeBadge({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.caption(
          color: color,
        ).copyWith(
          fontSize: 10.5,
          height: 1.05,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EvictionWarningBanner
// ─────────────────────────────────────────────────────────────────────────────

class _EvictionWarningBanner extends StatelessWidget {
  final int sessionCount;
  const _EvictionWarningBanner({required this.sessionCount});

  @override
  Widget build(BuildContext context) {
    const int cap = 500;
    if (sessionCount < 450) return const SizedBox.shrink();
    final int remaining = cap - sessionCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.warningCard(),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: AppSpacing.iconMd),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              remaining <= 0
                  ? 'Session limit reached (500). Oldest sessions will be removed automatically when new ones are saved.'
                  : '$remaining sessions remaining before the oldest are automatically removed (500 session limit).',
              style: AppTypography.body(size: 13, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortPopup extends StatelessWidget {
  final String                current;
  final bool                  showGradeSort;
  final void Function(String) onSelect;

  const _SortPopup({
    required this.current,
    required this.showGradeSort,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('date',     'Date',     Icons.calendar_today_rounded),
      if (showGradeSort)
        ('grade',  'Grade',    Icons.workspace_premium_rounded),
      ('duration', 'Duration', Icons.timer_outlined),
    ];

    String _resolveValue(String chip) {
      switch (chip) {
        case 'date':
          return (current == 'oldest') ? 'newest' : 'oldest';
        case 'grade':
          return (current == 'grade_high') ? 'grade_low' : 'grade_high';
        case 'duration':
          return (current == 'duration_desc') ? 'duration_asc' : 'duration_desc';
        default: return 'newest';
      }
    }

    String? _activeChip() {
      if (current == 'newest' || current == 'oldest') return 'date';
      if (current == 'grade_high' || current == 'grade_low') return 'grade';
      if (current == 'duration_desc' || current == 'duration_asc') return 'duration';
      return null;
    }

    IconData? _arrowIcon(String chip) {
      if (_activeChip() != chip) return null;
      switch (chip) {
        case 'date':     return current == 'newest' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
        case 'grade':    return current == 'grade_high' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
        case 'duration': return current == 'duration_desc' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
        default: return null;
      }
    }

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color:        AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
        boxShadow: const [
          BoxShadow(
            color:      AppColors.shadowMedium,
            blurRadius: 20,
            offset:     Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < chips.length; i++) ...[
                _SortOption(
                  label:    chips[i].$2,
                  selected: _activeChip() == chips[i].$1,
                  arrow:    _arrowIcon(chips[i].$1),
                  onTap:    () => onSelect(_resolveValue(chips[i].$1)),
                ),
                if (i < chips.length - 1)
                  const Divider(height: 1, color: AppColors.divider),
              ],
            ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String     label;
  final bool       selected;
  final IconData?  arrow;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.selected,
    required this.arrow,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AppColors.primaryLight : AppColors.white,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Text(
              label,
              style: AppTypography.body(
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ).copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: AppSpacing.iconSm,
              child: arrow != null
                  ? Icon(arrow, size: AppSpacing.iconSm, color: AppColors.primary)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}