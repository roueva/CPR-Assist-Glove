import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../screens/session_service.dart';
import '../services/session_detail.dart';
import '../services/compression_event.dart';
import 'cpr_chart_helpers.dart';
import 'export_bottom_sheet.dart';

part 'session_compare_charts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionCompareScreen — side-by-side comparison of 2–4 sessions
// Entry: SessionHistoryScreen selection mode → Compare icon
// ─────────────────────────────────────────────────────────────────────────────

class SessionCompareScreen extends ConsumerStatefulWidget {
  final List<SessionSummary> sessions;

  const SessionCompareScreen({super.key, required this.sessions})
      : assert(sessions.length >= 2);

  // One distinct color per slot — chosen to be distinguishable from each other
  // and from AHA target-band green/red
  static const _slotColors = [
    AppColors.primary,        // slot 1 — brand blue
    AppColors.compareSlot2,   // slot 2 — deep orange
    AppColors.compareSlot3,   // slot 3 — teal-green
    AppColors.compareSlot4,   // slot 4 — amber
  ];

  @override
  ConsumerState<SessionCompareScreen> createState() =>
      _SessionCompareScreenState();
}

class _SessionCompareScreenState
    extends ConsumerState<SessionCompareScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  // Detail map: session id → detail (null while loading)
  final Map<int, SessionDetail?> _details = {};
  final Map<int, bool>           _loading = {};

  // Which session slots are currently "active" — all on by default
  late Set<int> _activeIndices;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _activeIndices = Set.from(List.generate(widget.sessions.length, (i) => i));
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAllDetails());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllDetails() async {
    final service = ref.read(sessionServiceProvider);
    await Future.wait(widget.sessions.map((s) async {
      final id = s.id;
      if (id == null) return;
      setState(() => _loading[id] = true);
      try {
        final d = await service.fetchDetail(id);
        if (mounted) setState(() {
          _details[id] = d;
          _loading[id] = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loading[id] = false);
      }
    }));
  }

  void _toggleSession(int index) {
    setState(() {
      // Must keep at least 2 active
      if (_activeIndices.contains(index) && _activeIndices.length <= 1) return;
      if (_activeIndices.contains(index)) {
        _activeIndices.remove(index);
      } else {
        _activeIndices.add(index);
      }
    });
  }

  bool get _anyLoading => _loading.values.any((v) => v);

  @override
  Widget build(BuildContext context) {
    // Sort chronologically so all tabs see oldest → newest
    final sessions = [...widget.sessions]
      ..sort((a, b) => (a.sessionStart ?? DateTime(0))
          .compareTo(b.sessionStart ?? DateTime(0)));
    final slotColors = SessionCompareScreen._slotColors;

    final activeSessions  = [
      for (int i = 0; i < widget.sessions.length; i++)
        if (_activeIndices.contains(i)) widget.sessions[i]
    ];
    final activeColors    = [
      for (int i = 0; i < widget.sessions.length; i++)
        if (_activeIndices.contains(i)) slotColors[i]
    ];

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.white,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: context.pop,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Compare Sessions',
                style: AppTypography.heading(
                    size: 16, color: AppColors.textPrimary)),
        Text(
          '${sessions.first.isEmergency ? 'Emergency' : sessions.first.isNoFeedback ? 'No-Feedback' : 'Training'} · ${sessions.length} sessions',
          style: AppTypography.caption(color: AppColors.textSecondary),
        ),
          ],
        ),
        actions: [
          // ── Adult/Pediatric pill — same as SessionResultsScreen ──
          if (widget.sessions.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: AppSpacing.xxs),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                decoration: AppDecorations.chip(
                  color: AppColors.primary,
                  bg: AppColors.primaryLight,
                ),
                child: Text(
                  widget.sessions.first.scenario == 'pediatric' ? 'Pediatric' : 'Adult',
                  style: AppTypography.badge(size: 9, color: AppColors.primary),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.download_rounded, color: AppColors.textPrimary),
            tooltip: 'Export comparison',
            onPressed: () => ExportBottomSheet.showForMultipleSessions(
              context, sessions: widget.sessions,
            ),
          ),
        ],
      ),
        body: Column(
          children: [
            // ── Session cards — always visible above tabs ──────────────────────
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: _LegendStrip(
                  sessions:      sessions,
                  slotColors:    slotColors,
                  activeIndices: _activeIndices,
                  onToggle:      _toggleSession),
            ),
            const Divider(height: 1, color: AppColors.white),

            // ── Tab bar ────────────────────────────────────────────────────────
      DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_anyLoading)
              const LinearProgressIndicator(minHeight: 2)
            else
              const SizedBox(height: 2),
            TabBar(
              controller: _tabController,
              labelColor:           AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor:       AppColors.primary,
              indicatorWeight:      2.0,
              dividerColor:         Colors.transparent,
              labelStyle:           AppTypography.label(color: AppColors.primary),
              unselectedLabelStyle: AppTypography.caption(color: AppColors.textSecondary),
              tabs: const [
                Tab(text: 'OVERVIEW'),
                Tab(text: 'METRICS'),
                Tab(text: 'CHARTS'),
              ],
            ),
          ],
        ),
      ),
            // ── Tab content — fills remaining space ────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _OverviewTab(
                    sessions:   activeSessions,
                    details:    _details,
                    slotColors: activeColors,
                  ),
                  _MetricsTab(
                    sessions:   activeSessions,
                    details:    _details,
                    slotColors: activeColors,
                  ),
                  _ChartsTab(
                    sessions:   activeSessions,
                    details:    _details,
                    slotColors: activeColors,
                  ),
                ],
              ),
            ),

            // ── Native bottom bar clearance ────────────────────────────────────
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Session legend strip
// ─────────────────────────────────────────────────────────────────────────────

class _LegendStrip extends StatelessWidget {
  final List<SessionSummary> sessions;
  final List<Color>          slotColors;
  final Set<int>             activeIndices;
  final void Function(int)   onToggle;

  const _LegendStrip({
    required this.sessions,
    required this.slotColors,
    required this.activeIndices,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < sessions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: _LegendCard(
              session:  sessions[i],
              color:    slotColors[i],
              index:    i,
              isActive: activeIndices.contains(i),
              onToggle: () => onToggle(i),
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendCard extends StatelessWidget {
  final SessionSummary session;
  final Color          color;
  final int            index;
  final bool           isActive;
  final VoidCallback   onToggle;

  const _LegendCard({
    required this.session,
    required this.color,
    required this.index,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedOpacity(
        opacity:  isActive ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: AppDecorations.card(shadowOpacity: 0.10).copyWith(
            border: isActive
                ? Border.all(color: color, width: 1.5)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 3, color: isActive ? color : AppColors.divider),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'S${session.sessionNumber ?? index + 1}',
                      style: AppTypography.label(color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      session.dateFormatted,
                      style: AppTypography.caption(color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (session.sessionStart != null)
                      Text(
                            () {
                          final h = session.sessionStart!.hour.toString().padLeft(2, '0');
                          final m = session.sessionStart!.minute.toString().padLeft(2, '0');
                          return '$h:$m';
                        }(),
                        style: AppTypography.caption(color: AppColors.textDisabled),
                      ),
                    const SizedBox(height: AppSpacing.xs),

                    SizedBox(
                      height: 30,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: session.isTraining && session.totalGrade > 0
                            ? Text(
                          '${session.totalGrade.toStringAsFixed(0)}%',
                          style: AppTypography.subheading(
                            color: cprGradeColor(session.totalGrade),
                          ),
                        )
                            : session.isEmergency
                            ? Text(
                          session.pulseDetectedFinal
                              ? 'Pulse Detected'
                              : session.pulseChecksPrompted > 0
                              ? 'No Pulse Detected'
                              : 'Pulse Uncertain',
                          style: AppTypography.label(
                            color: session.pulseDetectedFinal
                                ? AppColors.success
                                : session.pulseChecksPrompted > 0
                                ? AppColors.error
                                : AppColors.textDisabled,
                          ),
                        )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — Overview
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _OverviewTab({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  Widget build(BuildContext context) {
    final allTraining = sessions.every((s) => s.isTraining);
    final anyEmergency = sessions.any((s) => s.isEmergency);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Score rings (training only) ──────────────────────────────────
          if (allTraining) ...[
            _ScoreRingsCard(sessions: sessions, slotColors: slotColors),
            const SizedBox(height: AppSpacing.md),
            _TrendBanner(sessions: sessions),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Key stats strip ──────────────────────────────────────────────
          _KeyStatsCard(sessions: sessions, slotColors: slotColors),
          const SizedBox(height: AppSpacing.md),

          if (anyEmergency) ...[
            _EmergencyOutcomeCard(
              sessions: sessions,
              details: details,
              slotColors: slotColors,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Radar chart (training only) ──────────────────────────────────
          if (allTraining) ...[
            _RadarCard(sessions: sessions, slotColors: slotColors),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Fatigue thirds ───────────────────────────────────────────────
          _PhaseComparisonCard(
              sessions: sessions, details: details, slotColors: slotColors),
          const SizedBox(height: AppSpacing.md),

        ],
      ),
    );
  }
}

// ── Score rings ──────────────────────────────────────────────────────────────

class _ScoreRingsCard extends StatelessWidget {
  final List<SessionSummary> sessions;
  final List<Color>          slotColors;

  const _ScoreRingsCard(
      {required this.sessions, required this.slotColors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overall Grade',
              style: AppTypography.subheading(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text('Side-by-side score comparison',
              style: AppTypography.caption(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (int i = 0; i < sessions.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ScoreRingTile(
                    session:   sessions[i],
                    color:     slotColors[i],
                    index:     i,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreRingTile extends StatelessWidget {
  final SessionSummary session;
  final Color          color;
  final int            index;

  const _ScoreRingTile({
    required this.session,
    required this.color,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final grade    = session.totalGrade;
    final hasGrade = session.isTraining && grade > 0;
    final pct      = (grade / 100).clamp(0.0, 1.0);

    return Column(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: hasGrade ? pct : 0,
                  strokeWidth: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      hasGrade ? cprGradeColor(grade) : AppColors.divider),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasGrade
                        ? '${grade.toStringAsFixed(0)}%'
                        : '—',
                    style: AppTypography.subheading(
                        color: hasGrade
                            ? cprGradeColor(grade)
                            : AppColors.textDisabled),
                  ),
                  if (hasGrade)
                    Text(
                      cprGradeLabel(grade),
                      style: AppTypography.caption(
                          color: AppColors.textDisabled),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: AppSpacing.sm,
              height: AppSpacing.sm,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'S${session.sessionNumber ?? index + 1}',
              style: AppTypography.label(color: AppColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmergencyOutcomeCard extends StatelessWidget {
  final List<SessionSummary> sessions;
  final Map<int, SessionDetail?> details;
  final List<Color> slotColors;

  const _EmergencyOutcomeCard({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  Widget build(BuildContext context) {
    final emergencySessions = sessions.where((s) => s.isEmergency).toList();

    if (emergencySessions.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Emergency Outcome',
            style: AppTypography.subheading(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Pulse check result and CPR flow summary',
            style: AppTypography.caption(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),

          for (int i = 0; i < emergencySessions.length; i++) ...[
            _EmergencyOutcomeRow(
              session: emergencySessions[i],
              detail: details[emergencySessions[i].id],
              color: slotColors[sessions.indexOf(emergencySessions[i])],
              index: sessions.indexOf(emergencySessions[i]),
            ),
            if (i < emergencySessions.length - 1)
              const Divider(height: AppSpacing.lg, color: AppColors.divider),
          ],
        ],
      ),
    );
  }
}

class _EmergencyOutcomeRow extends StatelessWidget {
  final SessionSummary session;
  final SessionDetail? detail;
  final Color color;
  final int index;

  const _EmergencyOutcomeRow({
    required this.session,
    required this.detail,
    required this.color,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final hasPulseChecks = detail?.pulseChecks.isNotEmpty ?? false;
    final lastPulse = hasPulseChecks ? detail!.pulseChecks.last : null;

    final String pulseText;
    final Color pulseColor;

    if (lastPulse != null) {
      if (lastPulse.classification == 2) {
        pulseText = 'Pulse detected';
        pulseColor = AppColors.success;
      } else if (lastPulse.classification == 1) {
        pulseText = 'Uncertain';
        pulseColor = AppColors.warning;
      } else {
        pulseText = 'No pulse';
        pulseColor = AppColors.error;
      }
    } else if (session.pulseDetectedFinal) {
      pulseText = 'Pulse detected';
      pulseColor = AppColors.success;
    } else if (session.pulseChecksPrompted > 0) {
      pulseText = 'No pulse';
      pulseColor = AppColors.error;
    } else {
      pulseText = 'Not checked';
      pulseColor = AppColors.textDisabled;
    }

    final compliance = session.pulseChecksPrompted > 0
        ? session.pulseChecksComplied / session.pulseChecksPrompted * 100
        : null;

    return Row(
      children: [
        Container(
          width: AppSpacing.sm,
          height: AppSpacing.sm,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),

        Expanded(
          child: Text(
            'S${session.sessionNumber ?? index + 1}',
            style: AppTypography.label(color: AppColors.textPrimary),
          ),
        ),

        Expanded(
          flex: 2,
          child: Text(
            pulseText,
            textAlign: TextAlign.center,
            style: AppTypography.label(color: pulseColor),
          ),
        ),

        Expanded(
          flex: 2,
          child: Text(
            compliance != null
                ? '${compliance.toStringAsFixed(0)}% checks'
                : '—',
            textAlign: TextAlign.end,
            style: AppTypography.caption(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Key stats strip ───────────────────────────────────────────────────────────

class _KeyStatsCard extends StatelessWidget {
  final List<SessionSummary> sessions;
  final List<Color>          slotColors;

  const _KeyStatsCard(
      {required this.sessions, required this.slotColors});

  @override
  Widget build(BuildContext context) {
    const metrics = ['Duration', 'Comps', 'Avg Depth', 'Avg Rate'];

    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Text('Key Stats',
                style: AppTypography.subheading(
                    color: AppColors.textPrimary)),
          ),
          // Column header row — metric labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const SizedBox(width: AppSpacing.iconBoxSize + AppSpacing.xs),
                for (final m in metrics)
                  Expanded(
                    child: Text(m,
                        style: AppTypography.caption(
                            color: AppColors.textDisabled),
                        textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1, color: AppColors.divider),
          for (int i = 0; i < sessions.length; i++)
            _KeyStatsRow(
              session:   sessions[i],
              color:     slotColors[i],
              index:     i,
              isLast:    i == sessions.length - 1,
            ),
        ],
      ),
    );
  }
}

class _KeyStatsRow extends StatelessWidget {
  final SessionSummary session;
  final Color          color;
  final int            index;
  final bool           isLast;

  const _KeyStatsRow({
    required this.session,
    required this.color,
    required this.index,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final duration = Duration(seconds: session.sessionDuration).mmss;
    final depth    = session.averageDepth > 0
        ? '${session.averageDepth.toStringAsFixed(1)}cm'
        : '—';
    final rate = session.averageFrequency > 0
        ? '${session.averageFrequency.round()} cpm'
        : '—';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              // Slot identifier
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppSpacing.sm,
                    height: AppSpacing.sm,
                    decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  SizedBox(
                    width: AppSpacing.iconBoxSize - AppSpacing.sm - AppSpacing.xxs,
                    child: Text(
                      'S${session.sessionNumber ?? index + 1}',
                      style: AppTypography.label(
                          color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.xs),
              // Values
              Expanded(child: Text(duration,
                  style: AppTypography.label(color: AppColors.textPrimary),
                  textAlign: TextAlign.center)),
              Expanded(child: Text('${session.compressionCount}',
                  style: AppTypography.label(color: AppColors.textPrimary),
                  textAlign: TextAlign.center)),
              Expanded(child: Text(depth,
                  style: AppTypography.label(
                      color: session.averageDepth >= 5.0 &&
                          session.averageDepth <= 6.0
                          ? AppColors.success
                          : session.averageDepth > 0
                          ? AppColors.warning
                          : AppColors.textDisabled),
                  textAlign: TextAlign.center)),
              Expanded(child: Text(rate,
                  style: AppTypography.label(
                      color: session.averageFrequency >= 100 &&
                          session.averageFrequency <= 120
                          ? AppColors.success
                          : session.averageFrequency > 0
                          ? AppColors.warning
                          : AppColors.textDisabled),
                  textAlign: TextAlign.center)),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
              height: 1,
              indent: AppSpacing.md,
              endIndent: AppSpacing.md,
              color: AppColors.divider),
      ],
    );
  }
}

// ── Posture snapshot ──────────────────────────────────────────────────────────

class _PostureCard extends StatelessWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _PostureCard({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  Widget build(BuildContext context) {
    final sessionsWithDetail = sessions
        .where((s) => s.id != null && details[s.id] != null)
        .toList();
    if (sessionsWithDetail.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Posture',
                    style: AppTypography.subheading(
                        color: AppColors.textPrimary)),
                const SizedBox(height: AppSpacing.xxs),
                Text('Wrist alignment & good-posture rate',
                    style: AppTypography.caption(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(
                  flex: 2,
                  child: Text('Wrist °',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled),
                      textAlign: TextAlign.center),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Posture %',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled),
                      textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1, color: AppColors.divider),
          for (int i = 0; i < sessionsWithDetail.length; i++) ...[
            _buildPostureRow(sessionsWithDetail[i],
                sessions.indexOf(sessionsWithDetail[i]), slotColors),
            if (i < sessionsWithDetail.length - 1)
              const Divider(
                  height: 1,
                  indent: AppSpacing.md,
                  endIndent: AppSpacing.md,
                  color: AppColors.divider),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildPostureRow(
      SessionSummary s, int slotIdx, List<Color> colors) {
    final d    = details[s.id!]!;
    final comps = d.compressions;

    final avgAngle = comps.isEmpty
        ? 0.0
        : comps.map((c) => c.wristAlignmentAngle).reduce((a, b) => a + b) /
        comps.length;
    final postureGoodPct = comps.isEmpty
        ? 0.0
        : comps.where((c) => c.postureOk).length / comps.length * 100;

    final angleColor = avgAngle <= 10
        ? AppColors.success
        : avgAngle <= 15
        ? AppColors.warning
        : AppColors.error;
    final postureColor = postureGoodPct >= 80
        ? AppColors.success
        : postureGoodPct >= 60
        ? AppColors.warning
        : AppColors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: AppSpacing.sm,
                  height: AppSpacing.sm,
                  decoration: BoxDecoration(
                      color: colors[slotIdx], shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text('S${s.sessionNumber ?? slotIdx + 1}',
                    style: AppTypography.label(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('${avgAngle.toStringAsFixed(1)}°',
                style: AppTypography.label(color: angleColor),
                textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('${postureGoodPct.toStringAsFixed(0)}%',
                style: AppTypography.label(color: postureColor),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _TrendBanner — dark gradient card showing grade progression arc
// Visually distinct from all other white cards in the Overview tab.
// ─────────────────────────────────────────────────────────────────────────────

class _TrendBanner extends StatelessWidget {
  final List<SessionSummary> sessions;
  const _TrendBanner({required this.sessions});

  @override
  Widget build(BuildContext context) {
    final sortedSessions = [...sessions]
      ..sort((a, b) => (a.sessionStart ?? DateTime(0))
          .compareTo(b.sessionStart ?? DateTime(0)));
    final grades = sortedSessions.map((s) => s.totalGrade).toList();
    final first  = grades.first;
    final last   = grades.last;
    final diff   = last - first;

    final bool improved = diff > 2;
    final bool declined = diff < -2;

    final double bestGrade = grades.reduce((a, b) => a > b ? a : b);
    final int    bestIdx   = grades.indexOf(bestGrade);
    final double worstGrade = grades.reduce((a, b) => a < b ? a : b);

    // ── Semantic color set (all tokens, all readable on dark surface) ──────
    final Color lineColor  = improved ? AppColors.trendImproving
        : declined ? AppColors.trendDeclining
        : AppColors.trendNeutral;
    final Color darkBadge  = improved ? AppColors.trendImprovingDark
        : declined ? AppColors.trendDecliningDark
        : AppColors.trendNeutralDark;
    final Color calloutBg  = improved ? AppColors.trendImprovingBg
        : declined ? AppColors.trendDecliningBg
        : AppColors.trendNeutralBg;

    final IconData icon     = improved ? Icons.trending_up_rounded
        : declined ? Icons.trending_down_rounded
        : Icons.remove_rounded;
    final spread = grades.reduce((a, b) => a > b ? a : b) -
        grades.reduce((a, b) => a < b ? a : b);

    final String stateLabel = improved ? 'IMPROVING'
        : declined ? 'NEEDS WORK'
        : spread < 5 ? 'STABLE'
        : 'FLUCTUATING';

    final String deltaStr   = improved
        ? '+${diff.toStringAsFixed(0)} pts'
        : declined
        ? '−${diff.abs().toStringAsFixed(0)} pts'
        : '±${diff.abs().toStringAsFixed(0)} pts';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.cprCardBg, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Left — icon + label + delta
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GRADE TREND',
                        style: AppTypography.badge(
                            size: 10,
                            color: AppColors.textOnDark.withValues(alpha: 0.55)),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(icon, size: 26, color: lineColor),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            deltaStr,
                            style: AppTypography.numericDisplay(
                                size: 22, color: AppColors.textOnDark),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '${first.toStringAsFixed(0)}% → ${last.toStringAsFixed(0)}%',
                        style: AppTypography.body(
                            size: 12,
                            color: AppColors.textOnDark.withValues(alpha: 0.6)
                        ),
                      ),
                    ],
                  ),
                ),

                // Right — state pill + stats
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs),
                      decoration: AppDecorations.trendPill(calloutBg),
                      child: Text(
                        stateLabel,
                        style: AppTypography.badge(size: 11, color: lineColor),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _StatPill(
                      icon: '★',
                      label: 'Best',
                      value: '${bestGrade.toStringAsFixed(0)}%',
                      color: AppColors.pbGoldLight,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    _StatPill(
                      icon: '↓',
                      label: 'Low',
                      value: '${worstGrade.toStringAsFixed(0)}%',
                      color: AppColors.textOnDark.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Chart ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs, AppSpacing.xs,
                AppSpacing.xs, AppSpacing.md),
            child: SizedBox(
              height: 90,
              child: CustomPaint(
                painter: _TrendChartPainter(
                  grades:    grades,
                  sessions:  sessions,
                  bestIdx:   bestIdx,
                  lineColor: lineColor,
                  darkBadge: darkBadge,
                  calloutBg: calloutBg,
                ),
                size: const Size(double.infinity, 90),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small inline stat row for the header right column ─────────────────────────

class _StatPill extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final Color  color;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: AppTypography.caption(color: color)),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          '$label ',
          style: AppTypography.caption(
              color: AppColors.textOnDark.withValues(alpha: 0.45)),
        ),
        Text(value,
            style: AppTypography.label(size: 11, color: AppColors.textOnDark)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TrendChartPainter — smooth area chart on dark surface
// ─────────────────────────────────────────────────────────────────────────────

class _TrendChartPainter extends CustomPainter {
  final List<double>         grades;
  final List<SessionSummary> sessions;
  final int                  bestIdx;
  final Color                lineColor;
  final Color                darkBadge;
  final Color                calloutBg;

  // Dynamic range: floor at 0, pad 10 pts above max
  static const double _kBottomPad = 16.0;
  static const double _kTopPad    = 24.0;
  static const double _kLeftPad   = 28.0;
  static const double _kRightPad  = 28.0;

  const _TrendChartPainter({
    required this.grades,
    required this.sessions,
    required this.bestIdx,
    required this.lineColor,
    required this.darkBadge,
    required this.calloutBg,
  });

  double get _minGrade =>
      (grades.reduce((a, b) => a < b ? a : b) - 10).clamp(0.0, 90.0);
  double get _maxGrade =>
      (grades.reduce((a, b) => a > b ? a : b) + 10).clamp(10.0, 100.0);

  double _y(double grade, double chartH) {
    final pct = (grade - _minGrade) / (_maxGrade - _minGrade);
    return _kTopPad + chartH * (1.0 - pct);
  }

  double _x(int i, double width) {
    if (grades.length == 1) return width / 2;
    return _kLeftPad +
        (i / (grades.length - 1)) * (width - _kLeftPad - _kRightPad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chartH = size.height - _kTopPad - _kBottomPad;

    final pts = List.generate(
      grades.length,
          (i) => Offset(_x(i, size.width), _y(grades[i], chartH)),
    );

    final linePath = _buildSmoothPath(pts);

    // ── Area fill — very subtle glow under the line ───────────────────────
    final areaPath = Path()..addPath(linePath, Offset.zero);
    areaPath.lineTo(pts.last.dx,  _kTopPad + chartH);
    areaPath.lineTo(pts.first.dx, _kTopPad + chartH);
    areaPath.close();

    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.25),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, _kTopPad, size.width, chartH))
        ..style = PaintingStyle.fill,
    );

    // ── Line ─────────────────────────────────────────────────────────────
    canvas.drawPath(
      linePath,
      Paint()
        ..color       = lineColor
        ..strokeWidth = 2.0
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round
        ..strokeJoin  = StrokeJoin.round,
    );

    // ── Dots + labels ─────────────────────────────────────────────────────
    for (int i = 0; i < pts.length; i++) {
      final pt     = pts[i];
      final isBest = i == bestIdx;
      final label  = '${grades[i].toStringAsFixed(0)}%';
      final sLabel = 'S${sessions[i].sessionNumber ?? i + 1}';

      if (isBest) {
        // Glowing filled dot
        canvas.drawCircle(
          pt, 7,
          Paint()..color = lineColor.withValues(alpha: 0.25),
        );
        canvas.drawCircle(pt, 5, Paint()..color = lineColor);
        // Gold star badge above
        _drawBadge(canvas,
          center: pt, text: '★ $label',
          bg: darkBadge, fg: AppColors.pbGoldLight, above: true,
          fontSize: 12,
        );
      } else {
        // Subtle hollow dot on dark surface
        canvas.drawCircle(pt, 4,
            Paint()
              ..color = AppColors.cprCardBg
              ..style = PaintingStyle.fill);
        canvas.drawCircle(pt, 4,
            Paint()
              ..color       = lineColor.withValues(alpha: 0.7)
              ..strokeWidth = 1.5
              ..style       = PaintingStyle.stroke);
        // Small translucent callout — above or below based on position
        final putBelow = pt.dy < (_kTopPad + chartH * 0.45);
        _drawCallout(canvas,
          center: pt, text: label,
          bg: calloutBg, fg: lineColor,
          below: putBelow,
          fontSize: 12,
        );
      }

      // Session label at bottom
      _drawText(canvas,
        text:     sLabel,
        center:   Offset(pt.dx, size.height - 5),
        fontSize: 11,
        color:    AppColors.textOnDark.withValues(alpha: 0.55),
      );
    }
  }

  Path _buildSmoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;
    for (int i = 0; i < pts.length - 1; i++) {
      final cp1 = Offset(
        pts[i].dx + (pts[i + 1].dx - pts[i].dx) * 0.45,
        pts[i].dy,
      );
      final cp2 = Offset(
        pts[i + 1].dx - (pts[i + 1].dx - pts[i].dx) * 0.45,
        pts[i + 1].dy,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy,
          pts[i + 1].dx, pts[i + 1].dy);
    }
    return path;
  }

  void _drawCallout(Canvas canvas, {
    required Offset center,
    required String text,
    required Color  bg,
    required Color  fg,
    required bool   below,
    double fontSize = 8,
  }) {
    const w = 40.0, h = 18.0, r = 5.0, gap = 7.0;
    final top = below ? center.dy + gap : center.dy - gap - h;
    canvas.drawRRect(
      RRect.fromLTRBR(center.dx - w / 2, top,
          center.dx + w / 2, top + h, const Radius.circular(r)),
      Paint()..color = bg,
    );
    _drawText(canvas,
      text:     text,
      center:   Offset(center.dx, top + h / 2 + 1),
      fontSize: fontSize,
      color:    fg,
      bold:     true,
    );
  }

  void _drawBadge(Canvas canvas, {
    required Offset center,
    required String text,
    required Color  bg,
    required Color  fg,
    required bool   above,
    double fontSize = 8.5,
  }) {
    const w = 54.0, h = 20.0, r = 6.0, gap = 8.0;
    final top = above ? center.dy - gap - h : center.dy + gap;
    canvas.drawRRect(
      RRect.fromLTRBR(center.dx - w / 2, top,
          center.dx + w / 2, top + h, const Radius.circular(r)),
      Paint()..color = bg,
    );
    _drawText(canvas,
      text:     text,
      center:   Offset(center.dx, top + h / 2 + 1),
      fontSize: fontSize,
      color:    fg,
      bold:     true,
    );
  }

  void _drawText(Canvas canvas, {
    required String text,
    required Offset center,
    required double fontSize,
    required Color  color,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily:  'Inter',
          fontSize:    fontSize,
          color:       color,
          fontWeight:  bold ? FontWeight.w700 : FontWeight.w400,
          height:      1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_TrendChartPainter old) =>
      old.grades.length != grades.length ||
          old.bestIdx   != bestIdx   ||
          old.lineColor != lineColor;
}

class _RadarCard extends StatefulWidget {
  final List<SessionSummary> sessions;
  final List<Color>          slotColors;
  const _RadarCard({required this.sessions, required this.slotColors});

  @override
  State<_RadarCard> createState() => _RadarCardState();
}

class _RadarCardState extends State<_RadarCard> {
  static const _labels    = ['Depth', 'Rate', 'Recoil', 'Hands-on', 'Posture'];
  static const _labelsFull = [
    'Depth consistency',
    'Rate consistency',
    'Full recoil',
    'Hands-on ratio',
    'Posture',
  ];

  // Which axis is currently selected — null = none
  int? _touchedAxis;

  List<double> _axes(SessionSummary s) {
    final n       = s.compressionCount > 0 ? s.compressionCount.toDouble() : 1;
    final recoil  = s.correctRecoil / n * 100;
    final hands   = s.handsOnRatio * 100;
    final posture = s.compressionCount > 0
        ? (s.correctPosture / s.compressionCount * 100).clamp(0.0, 100.0)
        : 0.0;
    return [
      s.depthConsistency.clamp(0, 100),
      s.frequencyConsistency.clamp(0, 100),
      recoil.clamp(0, 100),
      hands.clamp(0, 100),
      posture,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Performance Radar',
              style: AppTypography.subheading(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _touchedAxis == null
                ? 'Consistency across key metrics'
                : _labelsFull[_touchedAxis!],
            style: AppTypography.caption(color: _touchedAxis == null
                ? AppColors.textSecondary
                : AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 240,
            child: RadarChart(
              RadarChartData(
                radarShape:      RadarShape.polygon,
                tickCount:       4,
                ticksTextStyle:  const TextStyle(
                    color: AppColors.transparent, fontSize: 0),
                tickBorderData: const BorderSide(color: AppColors.textSecondary, width: 0.5),
                gridBorderData: const BorderSide(color: AppColors.textSecondary, width: 0.5),
                radarBorderData: const BorderSide(
                    color: AppColors.textSecondary, width: 0.5),
                radarBackgroundColor: AppColors.transparent,
                titleTextStyle:  AppTypography.caption(
                    color: AppColors.textSecondary),
                getTitle: (i, _) => RadarChartTitle(
                  text: _labels[i],
                  angle: 0,
                ),
                radarTouchData: RadarTouchData(
                  touchCallback: (event, response) {
                    if (!event.isInterestedForInteractions) return;
                    final idx = response?.touchedSpot?.touchedDataSetIndex;
                    if (idx == null) {
                      if (_touchedAxis != null) {
                        setState(() => _touchedAxis = null);
                      }
                      return;
                    }
                    // touchedDataSetIndex is the dataset; we want the entry index
                    final entryIdx =
                        response?.touchedSpot?.touchedRadarEntryIndex;
                    if (entryIdx != null && entryIdx != _touchedAxis) {
                      setState(() => _touchedAxis = entryIdx);
                    }
                  },
                ),
                dataSets: [
                  for (int i = 0; i < widget.sessions.length; i++)
                    RadarDataSet(
                      fillColor:   widget.slotColors[i].withValues(alpha: 0.15),
                      borderColor: widget.slotColors[i],
                      borderWidth: 2,
                      entryRadius: _touchedAxis != null ? 0 : 3,
                      dataEntries: _axes(widget.sessions[i])
                          .map((v) => RadarEntry(value: v))
                          .toList(),
                    ),
                ],
              ),
            ),
          ),

          // ── Touch overlay — shown when an axis is selected ────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _touchedAxis != null
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: _touchedAxis == null
                ? const SizedBox(width: double.infinity)
                : _buildAxisDetail(_touchedAxis!),
          ),

          const SizedBox(height: AppSpacing.md),
          // ── Legend dots ────────────────────────────────────────────────────
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (int i = 0; i < widget.sessions.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: AppSpacing.sm,
                    height: AppSpacing.sm,
                    decoration: BoxDecoration(
                        color: widget.slotColors[i], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text('S${widget.sessions[i].sessionNumber ?? i + 1}',
                      style: AppTypography.caption(
                          color: AppColors.textSecondary)),
                ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAxisDetail(int axisIdx) {
    final allValues = [
      for (int i = 0; i < widget.sessions.length; i++)
        _axes(widget.sessions[i])[axisIdx],
    ];
    final best = allValues.reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
      ),
      child: Row(
        children: [
          for (int i = 0; i < widget.sessions.length; i++) ...[
            if (i > 0)
              Container(
                  width: 1,
                  height: 32,
                  color: AppColors.primary.withValues(alpha: 0.15)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: BoxDecoration(
                            color: widget.slotColors[i],
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'S${widget.sessions[i].sessionNumber ?? i + 1}',
                        style: AppTypography.caption(
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${allValues[i].toStringAsFixed(0)}%',
                    style: AppTypography.label(
                      color: allValues[i] == best
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _PhaseComparisonCard extends StatelessWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _PhaseComparisonCard({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  // Returns [early_depth, mid_depth, late_depth, early_rate, mid_rate, late_rate]
  List<double> _phases(SessionDetail d) {
    final c = d.compressions;
    if (c.isEmpty) return [0, 0, 0, 0, 0, 0];
    final third = (c.length / 3).ceil();

    double avgDepth(List<CompressionEvent> sl) => sl.isEmpty
        ? 0
        : sl.map((e) => e.depth).reduce((a, b) => a + b) / sl.length;
    double avgRate(List<CompressionEvent> sl) => sl.isEmpty
        ? 0
        : sl.map((e) => e.instantaneousRate > 0
        ? e.instantaneousRate
        : e.frequency)
        .reduce((a, b) => a + b) /
        sl.length;

    final early = c.take(third).toList();
    final mid   = c.skip(third).take(third).toList();
    final late  = c.skip(third * 2).toList();

    return [
      avgDepth(early), avgDepth(mid), avgDepth(late),
      avgRate(early),  avgRate(mid),  avgRate(late),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final withDetail = sessions
        .where((s) => s.id != null && details[s.id] != null)
        .toList();
    if (withDetail.isEmpty) return const SizedBox.shrink();

    // Determine depth targets per session scenario
    bool isPediatric(SessionSummary s) => s.scenario == 'pediatric';

    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Phase Comparison',
                    style: AppTypography.subheading(
                        color: AppColors.textPrimary)),
                const SizedBox(height: AppSpacing.xxs),
                Text('Key metrics across early, mid & late compressions',
                    style: AppTypography.caption(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          // Column headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                for (final phase in ['Early', 'Mid', 'Late'])
                  Expanded(
                    flex: 2,
                    child: Text(phase,
                        style: AppTypography.caption(
                            color: AppColors.textDisabled),
                        textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1, color: AppColors.divider),
          for (int i = 0; i < withDetail.length; i++) ...[
            _buildSessionPhaseRows(
              withDetail[i],
              sessions.indexOf(withDetail[i]),
              slotColors,
              isPediatric(withDetail[i]),
            ),
            if (i < withDetail.length - 1)
              const Divider(height: 1, color: AppColors.divider),
          ],
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildSessionPhaseRows(
      SessionSummary s,
      int slotIdx,
      List<Color> colors,
      bool pediatric,
      ) {
    final phases = _phases(details[s.id!]!);
    final color  = colors[slotIdx];
    final dMin   = pediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;
    final dMax   = pediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;

    Color depthColor(double v) {
      if (v >= dMin && v <= dMax) return AppColors.success;
      if (v >= dMin - 0.5 && v <= dMax + 0.5) return AppColors.warning;
      return AppColors.error;
    }
    Color rateColor(double v) {
      if (v >= CprTargets.rateMin && v <= CprTargets.rateMax) return AppColors.success;
      if (v >= CprTargets.rateMin - 10 && v <= CprTargets.rateMax + 10) return AppColors.warning;
      return AppColors.error;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session label
          Row(children: [
            Container(
              width: AppSpacing.sm, height: AppSpacing.sm,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text('S${s.sessionNumber ?? slotIdx + 1}',
                style: AppTypography.label(color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: AppSpacing.xxs),
          // Depth row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Avg Depth (cm)',
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
              ),
              for (int t = 0; t < 3; t++)
                Expanded(
                  flex: 2,
                  child: Text(phases[t].toStringAsFixed(1),
                      style: AppTypography.label(
                          color: phases[t] > 0
                              ? depthColor(phases[t])
                              : AppColors.textDisabled),
                      textAlign: TextAlign.center),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Rate row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Avg Rate (cpm)',
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
              ),
              for (int t = 0; t < 3; t++)
                Expanded(
                  flex: 2,
                  child: Text(
                      phases[t + 3] > 0
                          ? phases[t + 3].toStringAsFixed(0)
                          : '—',
                      style: AppTypography.label(
                          color: phases[t + 3] > 0
                              ? rateColor(phases[t + 3])
                              : AppColors.textDisabled),
                      textAlign: TextAlign.center),
                ),
            ],
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — Metrics
// ─────────────────────────────────────────────────────────────────────────────

class _MetricsTab extends StatelessWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _MetricsTab({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  Widget build(BuildContext context) {

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
      child: Column(
        children: [
// ── Session Info ─────────────────────────────────────────────────
        _MetricGroup(
        title: 'Session Info',
        sessions: sessions,
        slotColors: slotColors,
        rows: [
          _MetricRowDef(
            label:   'Duration',
            infoText: 'Total time the session was active from start to stop, including all compressions, pauses, and ventilation breaks.',
            values:  sessions.map((s) => s.sessionDuration.toDouble()).toList(),
            format:  (v) => v != null ? Duration(seconds: v.toInt()).mmss : '—',
            colorFn: (_) => AppColors.textPrimary,
          ),
          _MetricRowDef(
            label:   'Compressions',
            values:  sessions.map((s) => s.compressionCount.toDouble()).toList(),
            format:  (v) => v != null ? v.toInt().toString() : '—',
            colorFn: (_) => AppColors.textPrimary,
            infoText: 'Total number of chest compressions delivered during the session. A typical 2-minute CPR cycle contains roughly 200–240 compressions at the correct rate.',
          ),
          _MetricRowDef(
            label: 'Best Streak',
            infoText: 'Longest consecutive run of compressions where both depth and rate were correct at the same time. A higher streak means the rescuer sustained quality under pressure.',
            values: sessions.map((s) {
              final d = s.id != null ? details[s.id] : null;
              return (d?.consecutiveGoodPeak ?? 0).toDouble();
            }).toList(),
            format:  (v) => (v != null && v > 0) ? '${v.toInt()} comps' : '—',
            colorFn: (_) => AppColors.textPrimary,
            bestHighlight: true,
          ),
          if (sessions.any((s) => s.isTraining))
            _MetricRowDef(
              label: 'Total Grade',
              infoText: 'The overall training score for this session. Reflects what percentage of compressions met the correct depth, rate, and recoil targets. Only available for training sessions.',
              values: sessions.map((s) =>
              s.isEmergency ? null : s.totalGrade).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
              colorFn: (v) => v == null
                  ? AppColors.textDisabled : cprGradeColor(v),
              bestHighlight: true,
            ),
        ],
      ),
        const SizedBox(height: AppSpacing.md),

        // ── Depth ─────────────────────────────────────────────────────────
        _MetricGroup(
          title: 'Depth',
          sessions: sessions,
          slotColors: slotColors,
          rows: [
            _MetricRowDef(
              label: 'Avg Depth',
              hint: sessions.first.scenario == 'pediatric'
                  ? '4–5 cm (pediatric)'
                  : '5–6 cm (adult)',
              infoText: 'Mean compression depth across all compressions in the session. The sternum must be pressed 5–6 cm for adults (4–5 cm for pediatric) to generate enough blood flow.',
              values: sessions.map((s) => s.averageDepth).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(1)} cm' : '—',
              colorFn: (v) {
                if (v == null) return AppColors.textDisabled;
                final isPed = sessions.first.scenario == 'pediatric';
                final min = isPed ? 4.0 : 5.0;
                final max = isPed ? 5.0 : 6.0;
                if (v >= min && v <= max) return AppColors.success;
                if (v >= min - 0.5 && v <= max + 0.5) return AppColors.warning;
                return AppColors.error;
              },
            ),
            _MetricRowDef(
              label: 'Peak Depth',
              infoText: 'The deepest single compression recorded in the session. Useful for checking whether over-compression occurred. Compressions beyond 6 cm risk rib or organ injury.',
              values: sessions.map((s) => s.peakDepth).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(1)} cm' : '—',
              colorFn: (_) => AppColors.textPrimary,
            ),
            _MetricRowDef(
              label: 'Depth SD',
              infoText: 'Standard deviation of all compression depths. A lower value means more consistent force applied across the session. Above 1.0 suggests large variation between compressions.',
              hint:  '< 0.5 = consistent',
              values: sessions.map((s) => s.depthSD).toList(),
              format: (v) => v != null ? v.toStringAsFixed(2) : '—',
              colorFn: (v) => v == null
                  ? AppColors.textDisabled
                  : v <= 0.5 ? AppColors.success
                  : v <= 1.0 ? AppColors.warning
                  : AppColors.error,
              lowerIsBetter: true,
              bestHighlight: true,
            ),
            _MetricRowDef(
              label: 'Depth Consistency %',
              infoText: 'Percentage of compressions that landed within the target depth range. Inconsistent depth means some compressions are too shallow to circulate blood effectively.',
              hint:  '≥ 80%',
              values: sessions.map((s) => s.depthConsistency).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
              colorFn: _pctColor,
              bestHighlight: true,
            ),
            _MetricRowDef(
              label: 'Full Recoil %',
              infoText: 'Percentage of compressions where the chest fully released before the next push. Leaning prevents heart refilling and can reduce CPR effectiveness by up to 30%.',
              hint:  '≥ 80%',
              values: sessions.map((s) => s.compressionCount > 0
                  ? s.correctRecoil / s.compressionCount * 100
                  : 0.0).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
              colorFn: _pctColor,
              bestHighlight: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Rate ─────────────────────────────────────────────────────────
        _MetricGroup(
          title: 'Rate',
          sessions: sessions,
          slotColors: slotColors,
          rows: [
            _MetricRowDef(
              label: 'Avg Rate',
              infoText: 'Mean compression rate across the session in compressions per minute. Too slow reduces cardiac output and too fast reduces the time the heart has to refill between compressions.',
              hint:  '100–120 cpm',
              values: sessions.map((s) => s.averageFrequency).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(0)} cpm' : '—',
              colorFn: (v) => v == null
                  ? AppColors.textDisabled
                  : (v >= 100 && v <= 120) ? AppColors.success
                  : (v >= 90 && v <= 130) ? AppColors.warning
                  : AppColors.error,
            ),
            _MetricRowDef(
              label: 'Rate Consistency %',
              infoText: 'Percentage of compressions delivered within the 100–120 cpm target range. An inconsistent rhythm reduces the predictability and effectiveness of blood circulation.',
              hint:  '≥ 80%',
              values: sessions.map((s) => s.frequencyConsistency).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
              colorFn: _pctColor,
              bestHighlight: true,
            ),
            _MetricRowDef(
              label: 'Rate Variability',
              hint:  '≤ 80 ms',
              infoText: 'Standard deviation of the time intervals between consecutive compressions, measured in milliseconds. A lower value means a steadier rhythm. High variability means the rescuer is rushing some compressions and slowing others.',
              values: sessions.map((s) {
                final d = s.id != null ? details[s.id] : null;
                return d?.rateVariability ?? 0.0;
              }).toList(),
              format: (v) => (v != null && v > 0)
                  ? '${v.toStringAsFixed(0)} ms' : '—',
              colorFn: (v) {
                if (v == null || v == 0) return AppColors.textDisabled;
                if (v <= 80) return AppColors.success;
                if (v <= 150) return AppColors.warning;
                return AppColors.error;
              },
              lowerIsBetter: true,
              bestHighlight: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Timing & Flow ────────────────────────────────────────────────
        _MetricGroup(
          title: 'Timing & Flow',
          sessions: sessions,
          slotColors: slotColors,
          rows: [
            _MetricRowDef(
              label: 'Hands-on Ratio',
              infoText: 'Chest Compression Fraction (CCF): The proportion of total session time that active compressions were being delivered. Time spent on pauses, ventilation, and pulse checks reduces this. AHA recommends ≥ 80%.',
              hint:  '≥ 80% (CCF)',
              values: sessions.map((s) => s.handsOnRatio * 100).toList(),
              format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
              colorFn: (v) => _pctColor(v, target: 80),
              bestHighlight: true,
            ),
            _MetricRowDef(
              label: 'Unplanned Pauses',
              hint:  'Gaps > 1.5 s',
              infoText: 'Number of gaps > 1.5 s between compressions that were not a scheduled ventilation or pulse check break. Each pause should stay under 10s. Even short unplanned pauses reduce blood flow to the brain.',
              values: sessions.map((s) {
                final d = s.id != null ? details[s.id] : null;
                return (d?.noFlowIntervals ?? s.noFlowIntervals).toDouble();
              }).toList(),
              format: (v) => (v != null && v > 0)
                  ? '${v.toInt()} times' : 'None',
              colorFn: (v) => v == null
                  ? AppColors.textDisabled
                  : v == 0 ? AppColors.success
                  : v <= 3 ? AppColors.warning
                  : AppColors.error,
              lowerIsBetter: true,
              bestHighlight: true,
            ),
            _MetricRowDef(
              label: 'No-flow Time',
              infoText: 'Total accumulated seconds without active compressions, excluding planned ventilation and pulse check breaks. Each individual pause should stay under 10s to prevent blood flow from stopping for too long.',
              values: sessions.map((s) {
                final d = s.id != null ? details[s.id] : null;
                return d?.noFlowTime ?? 0.0;
              }).toList(),
              format: (v) => (v != null && v > 0)
                  ? '${v.toStringAsFixed(1)} s' : '—',
              colorFn: (v) => v == null
                  ? AppColors.textDisabled
                  : v <= 5 ? AppColors.success
                  : v <= 10 ? AppColors.warning
                  : AppColors.error,
              lowerIsBetter: true,
            ),
            _MetricRowDef(
              label: 'Time to First',
              infoText: 'Time from session start until the first compression was delivered. Every second without compressions reduces survival probability. Target is under 5 seconds.',
              target: '< 5s',
              values: sessions.map((s) {
                final d = s.id != null ? details[s.id] : null;
                return d?.timeToFirstCompression ?? 0.0;
              }).toList(),
              format: (v) => (v != null && v > 0)
                  ? '${v.toStringAsFixed(1)} s' : '—',
              colorFn: (v) => (v == null || v == 0)
                  ? AppColors.textDisabled
                  : v <= 5 ? AppColors.success
                  : AppColors.warning,
              lowerIsBetter: true,
            ),
            _MetricRowDef(
              label: 'Fatigue Onset',
              infoText: 'The compression number at which depth began dropping consistently, indicating physical fatigue. A lower number means fatigue set in earlier. If this appears before compression 60, consider a rescuer swap at 2 minutes.',
              values: sessions.map((s) {
                final d = s.id != null ? details[s.id] : null;
                return (d?.fatigueOnsetIndex ?? 0).toDouble();
              }).toList(),
              format: (v) => (v != null && v > 0)
                  ? '#${v.toInt()}' : 'None',
              colorFn: (_) => AppColors.textPrimary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Posture ──────────────────────────────────────────────────────
        _MetricGroup(
          title: 'Posture',
          sessions: sessions,
          slotColors: slotColors,
          rows: [
            _MetricRowDef(
              label:  'Avg Wrist Angle',
              values: sessions.map((s) {
                final d = s.id != null ? details[s.id] : null;
                if (d == null || d.compressions.isEmpty) return null;
                return d.compressions
                    .map((c) => c.wristAlignmentAngle)
                    .reduce((a, b) => a + b) /
                    d.compressions.length;
              }).toList(),
              format:  (v) => v != null ? '${v.toStringAsFixed(1)}°' : '—',
              colorFn: (v) {
                if (v == null) return AppColors.textDisabled;
                if (v <= 10)   return AppColors.success;
                if (v <= 15)   return AppColors.warning;
                return AppColors.error;
              },
              target: '< 15°',
              lowerIsBetter: true,
              bestHighlight: true,
              infoText: 'Mean wrist deviation angle measured by the glove during compressions. Straight locked arms positioned directly over the sternum give the lowest angle and the most efficient force transfer.',
            ),
            _MetricRowDef(
              label:  'Good Posture %',
              values: sessions.map((s) => s.compressionCount > 0
                  ? s.correctPosture / s.compressionCount * 100
                  : 0.0).toList(),
              format:  (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
              colorFn: _pctColor,
              target:  '≥ 80%',
              bestHighlight: true,
              infoText: 'Percentage of compressions where wrist alignment angle was below 15° and wrist flexion was within ±10° at the same time. Both conditions must be met for a compression to count as correct posture.',
            ),
          ],
        ),

        // ── Ventilation (conditional) ─────────────────────────────────
          if (sessions.any((s) => s.ventilationCount > 0)) ...[
            const SizedBox(height: AppSpacing.md),
            _MetricGroup(
              title: 'Ventilation',
              sessions: sessions,
              slotColors: slotColors,
              rows: [
                _MetricRowDef(
                  label: 'Count',
                  infoText: 'Total number of ventilation cycles recorded during the session. In standard CPR, a cycle is prompted every 30 compressions (30:2 ratio).',
                  values: sessions.map((s) =>
                      s.ventilationCount.toDouble()).toList(),
                  format: (v) => v != null ? v.toInt().toString() : '—',
                  colorFn: (_) => AppColors.textPrimary,
                ),
                _MetricRowDef(
                  label: '30:2 Compliance',
                  infoText: 'Percentage of ventilation cycles where the rescuer actually paused and delivered breaths as prompted. Skipping ventilation cycles reduces oxygen delivery to the patient.',
                  values: sessions.map((s) => s.ventilationCount > 0
                      ? s.ventilationCompliance : null).toList(),
                  format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
                  colorFn: _pctColor,
                  bestHighlight: true,
                ),
              ],
            ),
          ],

    // ── Pulse Checks (emergency) ──────────────────────────────────
    if (sessions.any((s) => s.pulseChecksPrompted > 0)) ...[
    const SizedBox(height: AppSpacing.md),
      _MetricGroup(
        title: 'Pulse Checks',
        sessions: sessions,
        slotColors: slotColors,
        rows: [
          _MetricRowDef(
            label:  'Prompted',
            values: sessions.map((s) => s.pulseChecksPrompted.toDouble()).toList(),
            format: (v) => v != null ? v.toInt().toString() : '—',
            colorFn: (_) => AppColors.textPrimary,
            infoText: 'Number of times the glove signalled the rescuer to pause and check for a pulse. In standard protocol, a check is prompted at every 2-minute interval.',
          ),
          _MetricRowDef(
            label:  'Complied',
            values: sessions.map((s) => s.pulseChecksComplied.toDouble()).toList(),
            format: (v) => v != null ? v.toInt().toString() : '—',
            colorFn: (_) => AppColors.textPrimary,
            bestHighlight: true,
            infoText: 'Number of prompted pulse checks where the rescuer actually stopped and performed the check. Skipping a check means a potential ROSC could be missed.',
          ),
          _MetricRowDef(
            label:  'Compliance %',
            values: sessions.map((s) => s.pulseChecksPrompted > 0
                ? s.pulseChecksComplied / s.pulseChecksPrompted * 100
                : null).toList(),
            format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
            colorFn: _pctColor,
            target:  '100%',
            bestHighlight: true,
            infoText: 'Percentage of prompted pulse checks that the rescuer actually completed. Target is 100% — every prompted check should be performed.',
          ),
          _MetricRowDef(
            label:  'Pulse Detected',
            values: sessions.map((s) => s.pulseDetectedFinal ? 1.0 : 0.0).toList(),
            format: (v) => v == 1.0 ? 'Yes' : 'No',
            colorFn: (v) => v == 1.0
                ? AppColors.success
                : AppColors.textDisabled,
            infoText: 'Whether a pulse was detected at the final pulse check of the session, indicating possible return of spontaneous circulation (ROSC).',
          ),
        ],
      ),
    ],

    // ── Rescuer Vitals ────────────────────────────────────────────
          if (sessions.any((s) =>
          s.rescuerHRLastPause != null ||
              (s.id != null && (details[s.id]?.rescuerVitals.isNotEmpty ?? false)))) ...[
            const SizedBox(height: AppSpacing.md),
            _MetricGroup(
              title: 'Rescuer Vitals',
              sessions: sessions,
              slotColors: slotColors,
              rows: [
                _MetricRowDef(
                  label:  'HR at Last Pause',
                  values: sessions.map((s) => s.rescuerHRLastPause).toList(),
                  format: (v) => v != null ? '${v.toStringAsFixed(0)} bpm' : '—',
                  colorFn: (v) => v == null
                      ? AppColors.textDisabled
                      : v <= 140 ? AppColors.success
                      : v <= 160 ? AppColors.warning
                      : AppColors.error,
                  target: '≤ 140 bpm',
                  lowerIsBetter: true,
                  infoText: 'Rescuer heart rate at the most recent pause. CPR is vigorous physical work — a rise to 140–160 bpm is expected. Above 160 bpm suggests significant cardiovascular strain and the rescuer should be swapped if possible.',
                ),
                _MetricRowDef(
                  label:  'HR Change',
                  values: sessions.map((s) {
                    final d = s.id != null ? details[s.id] : null;
                    if (d == null || d.rescuerVitals.length < 2) return null;
                    final first = d.rescuerVitals.first.heartRate;
                    final last  = d.rescuerVitals.last.heartRate;
                    return last - first;
                  }).toList(),
                  format:  (v) => v != null
                      ? '${v >= 0 ? '+' : ''}${v!.toStringAsFixed(0)} bpm'
                      : '—',
                  colorFn: (v) => v == null
                      ? AppColors.textDisabled
                      : v <= 30  ? AppColors.success
                      : v <= 50  ? AppColors.warning
                      : AppColors.error,
                  target: '< +30 bpm',
                  lowerIsBetter: true,
                  infoText: 'Rise in rescuer heart rate from first to last vital snapshot. A rise of up to 30 bpm is normal for 2 minutes of CPR. Above 50 bpm indicates significant cardiovascular strain during the session.',
                ),
                _MetricRowDef(
                  label:  'SpO₂ at Last Pause',
                  values: sessions.map((s) => s.rescuerSpO2LastPause).toList(),
                  format: (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
                  colorFn: (v) => v == null
                      ? AppColors.textDisabled
                      : v >= 94 ? AppColors.success
                      : v >= 90 ? AppColors.warning
                      : AppColors.error,
                  target: '≥ 94%',
                  bestHighlight: true,
                  infoText: 'Rescuer blood oxygen saturation at the most recent pause. A drop below 94% during CPR is a warning sign of respiratory strain. Below 90% requires immediate action.',
                ),
                _MetricRowDef(
                  label:  'Wrist Temp',
                  values: sessions.map((s) {
                    final d = s.id != null ? details[s.id] : null;
                    if (d == null || d.rescuerVitals.isEmpty) return null;
                    final last = d.rescuerVitals.last;
                    return last.temperature > 0 ? last.temperature : null;
                  }).toList(),
                  format: (v) => v != null ? '${v.toStringAsFixed(1)} °C' : '—',
                  colorFn: (v) => v == null
                      ? AppColors.textDisabled
                      : v <= 37.5 ? AppColors.success
                      : v <= 38.5 ? AppColors.warning
                      : AppColors.error,
                  target: '≤ 37.5 °C',
                  infoText: 'Rescuer skin temperature at the wrist measured at end of session. Rising temperature reflects physical exertion. Normal skin range: 36.0–37.5 °C.',
                ),
                _MetricRowDef(
                  label:  'Fatigue Score',
                  values: sessions.map((s) {
                    final d = s.id != null ? details[s.id] : null;
                    if (d == null || d.rescuerVitals.isEmpty) return null;
                    return d.rescuerVitals.last.fatigueScore.toDouble();
                  }).toList(),
                  format: (v) => v != null ? v.toStringAsFixed(0) : '—',
                  colorFn: (v) => v == null
                      ? AppColors.textDisabled
                      : v < 30 ? AppColors.success
                      : v < 60 ? AppColors.warning
                      : AppColors.error,
                  target: '< 30',
                  lowerIsBetter: true,
                  bestHighlight: true,
                  infoText: 'Composite physiological fatigue score (0–100) from HR trend, RMSSD decline, and depth decline.\n'
                      '0–29: Low → rescuer performing well.\n'
                      '30–59: Moderate → monitor closely.\n'
                      '60+: High → swap recommended if possible.',                ),
                _MetricRowDef(
                  label:  'HRV (RMSSD)',
                  values: sessions.map((s) {
                    final d = s.id != null ? details[s.id] : null;
                    if (d == null || d.rescuerVitals.isEmpty) return null;
                    final last = d.rescuerVitals.last;
                    return last.rmssd > 0 ? last.rmssd.toDouble() : null;
                  }).toList(),
                  format: (v) => v != null ? '${v.toStringAsFixed(0)} ms' : '—',
                  colorFn: (v) => v == null
                      ? AppColors.textDisabled
                      : v >= 40 ? AppColors.success
                      : v >= 20 ? AppColors.warning
                      : AppColors.error,
                  target: '≥ 40 ms',
                  bestHighlight: true,
                    infoText: 'How much the time between the rescuer\'s heartbeats varies, in milliseconds. A higher value means the heart is adapting well under exertion. When this drops below 20 ms during CPR, it signals the nervous system is under significant stress and fatigue is setting in. Used here as a relative within-session indicator only.',
                ),
                _MetricRowDef(
                  label:  'Rescuer Swaps',
                  values: sessions.map((s) {
                    final d = s.id != null ? details[s.id] : null;
                    return (d?.rescuerSwapCount ?? s.rescuerSwapCount).toDouble();
                  }).toList(),
                  format:  (v) => v != null ? v.toInt().toString() : '—',
                  colorFn: (_) => AppColors.textPrimary,
                  infoText: 'Number of two-minute swap alerts fired during the session. The glove fires one alert every 120 seconds of active session time regardless of compression quality, following the AHA recommendation to swap rescuers every 2 minutes to maintain quality.',
                ),
              ],
            ),
          ],

    // ── Patient Vitals (emergency) ────────────────────────────────
          if (sessions.any((s) => s.isEmergency) &&
              sessions.any((s) =>
              s.patientTemperature != null ||
                  (s.id != null && (details[s.id]?.pulseChecks.isNotEmpty ?? false)))) ...[
            const SizedBox(height: AppSpacing.md),
            _MetricGroup(
              title: 'Patient Vitals',
              sessions: sessions,
              slotColors: slotColors,
                rows: [
                  _MetricRowDef(
                    label:  'Pulse at Last Check',
                    values: sessions.map((s) {
                      final d = s.id != null ? details[s.id] : null;
                      if (d == null || d.pulseChecks.isEmpty) return null;
                      return d.pulseChecks.last.classification.toDouble();
                    }).toList(),
                    format: (v) {
                      if (v == null) return '—';
                      if (v == 2.0)  return 'Present';
                      if (v == 1.0)  return 'Uncertain';
                      return 'Absent';
                    },
                    colorFn: (v) => v == null
                        ? AppColors.textDisabled
                        : v == 2.0 ? AppColors.success
                        : v == 1.0 ? AppColors.warning
                        : AppColors.error,
                    infoText: 'Result of the final pulse check. \nPresent = pulse detected (possible ROSC). \nUncertain = weak signal, manual verification needed. \nAbsent = no pulse, CPR needed.',
                  ),
                  _MetricRowDef(
                    label:  'Confidence',
                    values: sessions.map((s) {
                      final d = s.id != null ? details[s.id] : null;
                      if (d == null || d.pulseChecks.isEmpty) return null;
                      return d.pulseChecks.last.confidence.toDouble();
                    }).toList(),
                    format:  (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
                    colorFn: (v) => v == null
                        ? AppColors.textDisabled
                        : v >= 70 ? AppColors.success
                        : v >= 40 ? AppColors.warning
                        : AppColors.error,
                    target: '≥ 70%',
                    bestHighlight: true,
                    infoText: 'Signal quality confidence of the pulse detection at the last check. The app only shows pulse results when confidence is ≥ 40%. Above 70% is considered reliable.',
                  ),
                  _MetricRowDef(
                    label:  'Detected BPM',
                    values: sessions.map((s) {
                      final d = s.id != null ? details[s.id] : null;
                      if (d == null || d.pulseChecks.isEmpty) return null;
                      final bpm = d.pulseChecks.last.detectedBpm;
                      return bpm > 0 ? bpm : null;
                    }).toList(),
                    format:  (v) => v != null ? '${v.toStringAsFixed(0)} bpm' : '—',
                    colorFn: (v) => v == null ? AppColors.textDisabled : AppColors.success,
                    infoText: 'Patient heart rate detected during the final pulse check in beats per minute. Only present when pulse classification is Present. Normal adult range: 60–100 bpm.',
                  ),
                  _MetricRowDef(
                    label:  'CPR Continued',
                    values: sessions.map((s) {
                      final d = s.id != null ? details[s.id] : null;
                      if (d == null || d.pulseChecks.isEmpty) return null;
                      final dec = d.pulseChecks.last.userDecision;
                      if (dec == null) return null;
                      return dec == 'stop_cpr' ? 0.0 : 1.0;
                    }).toList(),
                    format: (v) {
                      if (v == null) return '—';
                      return v == 0.0 ? 'No' : 'Yes';
                    },
                    colorFn: (v) => v == null
                        ? AppColors.textDisabled
                        : AppColors.textPrimary,
                    infoText: 'Whether CPR was continued after the final pulse check. If the rescuer continued compressions the session recorded "continued", if they stopped, it recorded "stopped". ',
                  ),
                  _MetricRowDef(
                    label:  'Patient SpO₂',
                    values: sessions.map((s) {
                      final d = s.id != null ? details[s.id] : null;
                      return d?.patientSpO2LastCheck;
                    }).toList(),
                    format:  (v) => v != null ? '${v.toStringAsFixed(0)}%' : '—',
                    colorFn: (v) => v == null
                        ? AppColors.textDisabled
                        : v >= 94 ? AppColors.success
                        : v >= 90 ? AppColors.warning
                        : AppColors.error,
                    target: '≥ 94%',
                    bestHighlight: true,
                    infoText: 'Best patient SpO₂ reading recorded across all pulse check windows. A value ≥ 94% suggests adequate oxygenation is being maintained by CPR.',
                  ),
                  _MetricRowDef(
                    label:  'Patient Temp',
                    values: sessions.map((s) => s.patientTemperature).toList(),
                    format:  (v) => v != null ? '${v.toStringAsFixed(1)} °C' : '—',
                    colorFn: (v) => v == null
                        ? AppColors.textDisabled
                        : (v >= 36.0 && v <= 37.5) ? AppColors.success
                        : AppColors.warning,
                    infoText: 'Patient skin temperature from the temperature sensor. Hypothermia (< 35 °C) is common in cardiac arrest and negatively affects resuscitation outcomes.',
                  ),
                ],
            ),
          ],
        ],
      ),
    );
  }

  Color _pctColor(double? v, {double target = 80}) {
    if (v == null) return AppColors.textDisabled;
    if (v >= target)       return AppColors.success;
    if (v >= target - 15)  return AppColors.warning;
    return AppColors.error;
  }
}

// ── Metric group card ──────────────────────────────────────────────────────

class _MetricRowDef {
  final String           label;
  final String?          hint;
  final List<double?>    values;
  final String Function(double?) format;
  final Color Function(double?)  colorFn;
  final String?          target;
  final bool             bestHighlight;
  final bool             lowerIsBetter;
  final String?          infoText;

  const _MetricRowDef({
    required this.label,
    this.hint,
    required this.values,
    required this.format,
    required this.colorFn,
    this.target,
    this.bestHighlight  = false,
    this.lowerIsBetter  = false,
    this.infoText,
  });
}

class _MetricGroup extends StatelessWidget {
  final String               title;
  final List<SessionSummary> sessions;
  final List<Color>          slotColors;
  final List<_MetricRowDef>  rows;

  const _MetricGroup({
    required this.title,
    required this.sessions,
    required this.slotColors,
    required this.rows,
  });

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.transparent,
        insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.dialogInsetH,
            vertical:   AppSpacing.dialogInsetV),
          child: Container(
            decoration: AppDecorations.dialog(),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
                  decoration: AppDecorations.dialogHeader(),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppColors.textOnDark,
                          size: AppSpacing.iconSm),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(title,
                            style: AppTypography.subheading(
                                color: AppColors.textOnDark)),
                      ),
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: Icon(Icons.close_rounded,
                              color: AppColors.textOnDark,
                              size: AppSpacing.iconSm),
                        ),
                      ),
                    ],
                  ),
                ),
                // Content — scrollable
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final row in rows)
                          if (row.infoText != null) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 14,
                                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(row.label,
                                            style: AppTypography.bodyBold(
                                                size: 13,
                                                color: AppColors.textPrimary)),
                                      ),
                                      if (row.hint != null) ...[
                                        const SizedBox(width: AppSpacing.xs),
                                        Text('· ${row.hint}',
                                            style: AppTypography.caption(
                                                color: AppColors.textDisabled)),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(row.infoText!,
                                      style: AppTypography.body(
                                          size: 13,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: AppTypography.subheading(
                          color: AppColors.textPrimary)),
                ),
                if (rows.any((r) => r.infoText != null))
                  GestureDetector(
                    onTap: () => _showInfo(context),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size:  AppSpacing.iconSm,
                      color: AppColors.primary.withValues(alpha: 0.40),
                    ),
                  ),
              ],
            ),
          ),
          // ── Column headers (colored dots) ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                for (int i = 0; i < sessions.length; i++)
                  Expanded(
                    flex: 2,
                    child: Center(
                      child: Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color:  slotColors[i],
                            shape: BoxShape.circle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: AppSpacing.xs),
          for (int i = 0; i < rows.length; i++)
            _buildRow(context, rows[i], isLast: i == rows.length - 1),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _MetricRowDef row, {bool isLast = false}) {
    int? bestIdx;
    if (row.bestHighlight) {
      final valid = row.values
          .asMap()
          .entries
          .where((e) => e.value != null)
          .map((e) => MapEntry(e.key, e.value!))
          .toList();
      if (valid.isNotEmpty) {
        bestIdx = row.lowerIsBetter
            ? valid.reduce((a, b) => a.value < b.value ? a : b).key
            : valid.reduce((a, b) => a.value > b.value ? a : b).key;
      }
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.label,
                      style: AppTypography.caption(
                          color: AppColors.textSecondary)),
                  if (row.hint != null)
                    Text(row.hint!,
                        style: AppTypography.caption(
                            color: AppColors.textDisabled)),
                  if (row.target != null)
                    Text(row.target!,
                        style: AppTypography.caption(
                            color: AppColors.textDisabled)),
                ],
              ),
            ),
            for (int i = 0; i < row.values.length; i++)
              Expanded(
                flex: 2,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs),
                  padding: EdgeInsets.symmetric(
                    vertical: AppSpacing.xxs,
                    horizontal: bestIdx == i ? AppSpacing.xs : 0,
                  ),
                  decoration: bestIdx == i
                      ? AppDecorations.primaryCard(radius: AppSpacing.cardRadiusSm)
                      : null,
                  child: Text(
                    row.format(row.values[i]),
                    style: AppTypography.label(
                        color: row.colorFn(row.values[i])),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (!isLast)
        const Divider(
            height: 1,
            indent:    AppSpacing.md,
            endIndent: AppSpacing.md,
            color:     AppColors.divider),
    ]);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — Charts
// Uses the same chart infrastructure as session_results_charts.dart:
//   • Time-based x axis (seconds from session start)
//   • Window dropdown + drag-to-scroll
//   • Pretty scroll bar
//   • Per-session target bands derived from scenario
// ─────────────────────────────────────────────────────────────────────────────


class _ChartsTab extends StatelessWidget {
  final List<SessionSummary>     sessions;
  final Map<int, SessionDetail?> details;
  final List<Color>              slotColors;

  const _ChartsTab({
    required this.sessions,
    required this.details,
    required this.slotColors,
  });

  @override
  Widget build(BuildContext context) {
    final withDetail = sessions
        .where((s) => s.id != null && details[s.id] != null)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
      child: Column(
        children: [
          if (withDetail.isEmpty)
            _NoDetailPlaceholder()
          else ...[
            _CompareDepthChart(
              sessions:   withDetail,
              details:    details,
              slotColors: slotColors,
            ),
            const SizedBox(height: AppSpacing.md),
            _CompareRateChart(
              sessions:   withDetail,
              details:    details,
              slotColors: slotColors,
            ),
            const SizedBox(height: AppSpacing.md),
            _CompareDepthTrendChart(
              sessions:   withDetail,
              details:    details,
              slotColors: slotColors,
            ),
            const SizedBox(height: AppSpacing.md),
            _ComparePostureChart(
              sessions:   withDetail,
              details:    details,
              slotColors: slotColors,
            ),
            // Rescuer HR — only if any session has vitals
            if (withDetail.any((s) => (details[s.id]?.rescuerVitals.isNotEmpty ?? false))) ...[
              const SizedBox(height: AppSpacing.md),
              _CompareHrChartCard(
                sessions:   withDetail,
                details:    details,
                slotColors: slotColors,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

