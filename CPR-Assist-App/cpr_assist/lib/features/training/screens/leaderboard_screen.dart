import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../widgets/session_history.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LeaderboardScreen
//
// Tab bar: Global | Friends | My Sessions
//
// Global  — real data from GET /leaderboard/global, filterable by scenario.
// Friends — placeholder (no backend friends system yet).
// My Sessions — real data via sessionSummariesProvider + SessionCard.
// ─────────────────────────────────────────────────────────────────────────────

class LeaderboardScreen extends ConsumerStatefulWidget {
  final String? currentUsername;
  const LeaderboardScreen({super.key, this.currentUsername});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Scenario filter for the Global tab
  String _scenario = 'standard_adult';

  static const _scenarioOptions = {
    'standard_adult': 'Adult',
    'pediatric':      'Pediatric',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.surfaceWhite,
        foregroundColor:        AppColors.textPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight - AppSpacing.sm,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('Leaderboard', style: AppTypography.heading(size: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AppSpacing.xxl + AppSpacing.xxs),
          child: Column(
            children: [
              const Divider(height: 1, color: AppColors.divider),
              TabBar(
                controller:           _tabController,
                labelColor:           AppColors.primary,
                unselectedLabelColor: AppColors.textDisabled,
                indicatorColor:       AppColors.primary,
                indicatorWeight:      2.5,
                labelStyle: AppTypography.label(
                    size: 13, color: AppColors.primary),
                unselectedLabelStyle: AppTypography.label(
                    size: 13, color: AppColors.textDisabled),
                tabs: const [
                  Tab(text: 'Global'),
                  Tab(text: 'Friends'),
                  Tab(text: 'My Sessions'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GlobalTab(
            scenario:        _scenario,
            scenarioOptions: _scenarioOptions,
            onScenarioChanged: (s) => setState(() => _scenario = s),
          ),
          const _FriendsTab(),
          const _MyStatsTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL TAB — real data from /leaderboard/global
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalTab extends ConsumerWidget {
  final String                    scenario;
  final Map<String, String>       scenarioOptions;
  final void Function(String)     onScenarioChanged;

  const _GlobalTab({
    required this.scenario,
    required this.scenarioOptions,
    required this.onScenarioChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaderboardAsync = ref.watch(globalLeaderboardProvider(scenario));

    return leaderboardAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: AppSpacing.iconXl + AppSpacing.md,
                  color: AppColors.textDisabled),
              const SizedBox(height: AppSpacing.md),
              Text('Could not load leaderboard',
                  style: AppTypography.subheading(
                      color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Text(e.toString(),
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(
                      color: AppColors.textDisabled)),
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: () =>
                    ref.invalidate(globalLeaderboardProvider(scenario)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (data) {
        final (entries, myRank) = data;

        return Stack(
          children: [
            ListView(
              padding: EdgeInsets.only(
                bottom: myRank != null
                    ? AppSpacing.xxl + AppSpacing.xl + AppSpacing.md
                    : AppSpacing.md,
              ),
              children: [
                // ── Scenario toggle ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color:        AppColors.screenBgGrey,
                      borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: scenarioOptions.entries.map((e) {
                        final isSelected = e.key == scenario;
                        return GestureDetector(
                          onTap: () => onScenarioChanged(e.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical:   AppSpacing.sm - AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary : AppColors.transparent,
                              borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                            ),
                            child: Text(
                              e.value,
                              style: AppTypography.label(
                                size:  13,
                                color: isSelected
                                    ? AppColors.textOnDark
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // ── Empty state ──────────────────────────────────────────────
                if (entries.isEmpty) ...[
                  const SizedBox(height: AppSpacing.xxl),
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.leaderboard_outlined,
                            size:  AppSpacing.iconXl + AppSpacing.md,
                            color: AppColors.textDisabled),
                        const SizedBox(height: AppSpacing.md),
                        Text('No rankings yet',
                            style: AppTypography.subheading(color: AppColors.textSecondary)),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Complete 3 or more Training sessions\nto appear on the leaderboard.',
                          textAlign: TextAlign.center,
                          style: AppTypography.body(color: AppColors.textDisabled),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          decoration: AppDecorations.card(),
                          child: const Column(
                            children: [
                              _InfoRow(icon: Icons.looks_one_rounded,   label: 'Minimum 3 Training sessions required'),
                              _InfoRow(icon: Icons.looks_two_rounded,   label: 'Each session must be ≥ 30 compressions'),
                              _InfoRow(icon: Icons.looks_3_rounded,     label: 'Your best session score is used for ranking'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // ── Podium (top 3) ─────────────────────────────────────────
                  if (entries.length >= 3)
                    _Podium(entries: entries.take(3).toList()),

                  // ── Rankings list (4th+) ───────────────────────────────────
                  if (entries.length > 3) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xl, AppSpacing.sm,
                          AppSpacing.xl, AppSpacing.xs),
                      child: Text('RANKINGS',
                          style: AppTypography.label(size: 11)),
                    ),
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                      decoration: AppDecorations.card(),
                      child: Column(
                        children: entries.skip(3).map((entry) {
                          final isLast =
                              entry == entries.last;
                          return Column(
                            children: [
                              _LeaderRow(entry: entry),
                              if (!isLast)
                                const Divider(
                                    height: 1,
                                    color: AppColors.divider,
                                    indent: 60,
                                    endIndent: AppSpacing.md),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],

                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              ],
            ),

            // ── My rank footer (pinned to bottom) ────────────────────────────
            if (myRank != null)
              Positioned(
                bottom: 0,
                left:   0,
                right:  0,
                child:  _MyRankFooter(entry: myRank),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PODIUM
// ─────────────────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  const _Podium({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.length < 3) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.sm + AppSpacing.xs),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm, AppSpacing.xl, AppSpacing.sm, AppSpacing.xl),
      decoration: AppDecorations.podiumGradientCard(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _PodiumSpot(entry: entries[1], height: 80)),
          Expanded(
              child: _PodiumSpot(entry: entries[0], height: 106, isFirst: true)),
          Expanded(child: _PodiumSpot(entry: entries[2], height: 64)),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  final LeaderboardEntry entry;
  final double           height;
  final bool             isFirst;

  const _PodiumSpot({
    required this.entry,
    required this.height,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = isFirst
        ? AppSpacing.avatarLg - AppSpacing.sm + AppSpacing.xxs
        : AppSpacing.avatarMd + AppSpacing.xxs;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFirst) const Text('👑', style: TextStyle(fontSize: 20)),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width:  avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.textOnDark.withValues(alpha: 0.15),
            border: Border.all(
              color: AppColors.textOnDark.withValues(alpha: 0.4),
              width: isFirst ? 2.5 : 2,
            ),
          ),
          child: Center(
            child: Text(
              entry.username.initials,
              style: AppTypography.heading(
                  size:  isFirst ? 18 : 14,
                  color: AppColors.textOnDark),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          entry.username,
          style: AppTypography.bodyMedium(
              size:  isFirst ? 13 : 11,
              color: AppColors.textOnDark),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${entry.avgGrade.toStringAsFixed(1)}%',
          style: AppTypography.body(
              size:  isFirst ? 13 : 11,
              color: AppColors.textOnDark.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.textOnDark
                .withValues(alpha: isFirst ? 0.2 : 0.1),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.cardRadiusSm),
            ),
          ),
          child: Center(
            child: Text(
              entry.rank == 1
                  ? '🥇'
                  : entry.rank == 2
                  ? '🥈'
                  : '🥉',
              style: const TextStyle(fontSize: 22),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEADER ROW
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderRow extends StatelessWidget {
  final LeaderboardEntry entry;
  const _LeaderRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isMe = entry.isCurrentUser;
    return Container(
      color: isMe
          ? AppColors.primaryLight.withValues(alpha: 0.4)
          : AppColors.transparent,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm + AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppSpacing.iconLg - AppSpacing.xxs,
            child: Text('#${entry.rank}',
                style: AppTypography.label(color: AppColors.textDisabled),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width:  AppSpacing.avatarSm + AppSpacing.xs,
            height: AppSpacing.avatarSm + AppSpacing.xs,
            decoration: AppDecorations.iconCircle(
              bg: isMe ? AppColors.primaryLight : AppColors.screenBgGrey,
            ),
            child: Center(
              child: Text(
                entry.username.initials,
                style: AppTypography.label(size: 12, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(entry.username,
                        style: AppTypography.bodyMedium(
                            size: 14,
                            color: isMe
                                ? AppColors.primary
                                : AppColors.textPrimary)),
                    if (isMe) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical:   AppSpacing.xxs,
                        ),
                        decoration: AppDecorations.chip(
                            color: AppColors.primary,
                            bg: AppColors.primaryLight),
                        child: Text('You',
                            style: AppTypography.badge(
                                size: 9, color: AppColors.primary)),
                      ),
                    ],
                  ],
                ),
                Text('${entry.sessionCount} sessions',
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
              ],
            ),
          ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.chipPaddingH - AppSpacing.xxs,
              vertical:   AppSpacing.chipPaddingV,
            ),
            decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadiusSm),
            child: Text(
              '${entry.avgGrade.toStringAsFixed(1)}%',
              style: AppTypography.bodyBold(size: 13, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            width: 80,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
              child: LinearProgressIndicator(
                value:            (entry.avgGrade / 100).clamp(0.0, 1.0),
                backgroundColor:  AppColors.divider,
                valueColor:       AlwaysStoppedAnimation<Color>(
                  entry.avgGrade >= 90 ? AppColors.success
                      : entry.avgGrade >= 75 ? AppColors.info
                      : entry.avgGrade >= 55 ? AppColors.warning
                      : AppColors.error,
                ),
              ),
            ),
          ),
        ],
      ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY RANK FOOTER
// ─────────────────────────────────────────────────────────────────────────────

class _MyRankFooter extends StatelessWidget {
  final LeaderboardEntry entry;
  const _MyRankFooter({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
              color:      AppColors.shadowMedium,
              blurRadius: 12,
              offset:     Offset(0, -3)),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical:   AppSpacing.sm + AppSpacing.xs,
      ),
        child: Row(
          children: [
            Container(
              width:  AppSpacing.iconXl + AppSpacing.sm,
              height: AppSpacing.iconXl + AppSpacing.sm,
              decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
              child: Center(
                child: Text(
                  entry.username.initials,
                  style: AppTypography.label(size: 13, color: AppColors.primary)
                      .copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You · ${entry.sessionCount} sessions',
                style: AppTypography.caption(color: AppColors.textDisabled)),
            Text(
              '${entry.avgGrade.toStringAsFixed(1)}% avg grade',
              style: AppTypography.bodyMedium(size: 13),
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              width:  120,
              height: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                child: LinearProgressIndicator(
                  value:           (entry.avgGrade / 100).clamp(0.0, 1.0),
                  backgroundColor: AppColors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    entry.avgGrade >= 90 ? AppColors.success
                        : entry.avgGrade >= 75 ? AppColors.info
                        : entry.avgGrade >= 55 ? AppColors.warning
                        : AppColors.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical:   AppSpacing.xs,
              ),
              decoration: AppDecorations.chip(
                color: AppColors.primary,
                bg:    AppColors.primaryLight,
              ),
              child:
              Text(
                '#${entry.rank}',
                style: AppTypography.bodyBold(size: 15, color: AppColors.primary),
              ),
            ),
          ],
        ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// FRIENDS TAB — placeholder until friends backend is implemented
// ─────────────────────────────────────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  const _FriendsTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar (non-functional placeholder)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            readOnly: true,
            onTap: () => UIHelper.showSnackbar(
              context,
              message: 'Friends feature coming soon',
              icon: Icons.group_outlined,
            ),
            decoration: InputDecoration(
              hintText:   'Search by username…',
              prefixIcon: const Icon(Icons.search_rounded,
                  size: AppSpacing.iconSm, color: AppColors.textDisabled),
              suffixIcon: GestureDetector(
                onTap: () => UIHelper.showSnackbar(
                  context,
                  message: 'Friends feature coming soon',
                  icon: Icons.group_add_outlined,
                ),
                child: const Icon(Icons.person_add_outlined,
                    size: AppSpacing.iconSm, color: AppColors.primary),
              ),
            ),
          ),
        ),
        // Coming soon body
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width:  AppSpacing.iconXl + AppSpacing.lg,
                  height: AppSpacing.iconXl + AppSpacing.lg,
                  decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
                  child: const Icon(
                    Icons.group_outlined,
                    size:  AppSpacing.iconLg,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Friends Coming Soon',
                    style: AppTypography.subheading(size: 18)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Search for friends and compare scores\nin a future update.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body(color: AppColors.textDisabled),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY STATS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _MyStatsTab extends ConsumerWidget {
  const _MyStatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);

    return summaries.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: AppSpacing.iconXl + AppSpacing.md,
                color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text('Could not load stats',
                style: AppTypography.subheading(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => ref.invalidate(sessionSummariesProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.bar_chart_rounded,
                    size: AppSpacing.iconXl + AppSpacing.md,
                    color: AppColors.textDisabled),
                const SizedBox(height: AppSpacing.md),
                Text('No stats yet',
                    style: AppTypography.subheading(color: AppColors.textDisabled)),
                const SizedBox(height: AppSpacing.xs),
                Text('Complete training sessions to build your stats',
                    textAlign: TextAlign.center,
                    style: AppTypography.body(color: AppColors.textDisabled)),
              ],
            ),
          );
        }

        final stats = UserStats.fromSessions(sessions);
        final trainingSessions = sessions.where((s) => s.isTraining).toList();
        final recentGrades = trainingSessions
            .take(10)
            .toList()
            .reversed
            .toList();

        // Streak: consecutive sessions ending with grade >= 75
        int streak = 0;
        for (final s in trainingSessions) {
          if (s.totalGrade >= 75) {
            streak++;
          } else {
            break;
          }
        }

        // Total compressions across all sessions
        final totalCompressions =
        sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // ── Personal best card ─────────────────────────────────────────
            if (stats.bestSession != null && stats.bestSession!.isTraining) ...[
              PersonalBestCard(session: stats.bestSession!),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── Summary stat tiles ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppDecorations.primaryDarkCard(),
              child: Row(
                children: [
                  Expanded(
                    child: _StatsTile(
                      icon:  Icons.history_rounded,
                      value: '${sessions.length}',
                      label: 'Total Sessions',
                    ),
                  ),
                  Expanded(
                    child: _StatsTile(
                      icon:  Icons.compress_rounded,
                      value: totalCompressions > 999
                          ? '${(totalCompressions / 1000).toStringAsFixed(1)}k'
                          : '$totalCompressions',
                      label: 'Compressions',
                    ),
                  ),
                  Expanded(
                    child: _StatsTile(
                      icon:  Icons.local_fire_department_rounded,
                      value: streak > 0 ? '$streak' : '—',
                      label: 'Good streak',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Grade history sparkline ────────────────────────────────────
            if (recentGrades.length >= 2) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: AppDecorations.card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Grade Trend',
                            style: AppTypography.subheading(size: 14)),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Emergency sessions are not graded and do not appear here.',
                          style: AppTypography.caption(color: AppColors.textDisabled),
                        ),
                        Text('Last ${recentGrades.length} training sessions (graded only)',
                            style: AppTypography.caption()),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 80,
                      child: CustomPaint(
                        painter: _GradeSparklinePainter(
                          grades: recentGrades
                              .map((s) => s.totalGrade)
                              .toList(),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(recentGrades.first.dateFormatted,
                            style: AppTypography.caption()),
                        Text(recentGrades.last.dateFormatted,
                            style: AppTypography.caption()),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            // ── Avg grade breakdown ────────────────────────────────────────
        if (trainingSessions.isNotEmpty)
        Container(              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Training Averages',
                      style: AppTypography.subheading(size: 14)),
                  const SizedBox(height: AppSpacing.md),
                  _AverageRow(
                    label: 'Avg Grade',
                    value: stats.averageGradeFormatted,
                    color: gradeColor(stats.averageGrade),
                  ),
                  const Divider(height: AppSpacing.lg, color: AppColors.divider),
                  _AverageRow(
                    label: 'Best Grade',
                    value: stats.sessionCount > 0
                        ? '${stats.bestGrade.toStringAsFixed(1)}%'
                        : '—',
                    color: gradeColor(stats.bestGrade),
                  ),
                  if (trainingSessions.isNotEmpty) ...[
                    const Divider(height: AppSpacing.lg, color: AppColors.divider),
                    _AverageRow(
                      label: 'Avg Depth',
                      value: '${(trainingSessions.map((s) => s.averageDepth).reduce((a, b) => a + b) / trainingSessions.length).toStringAsFixed(1)} cm',
                      color: AppColors.primary,
                    ),
                    const Divider(height: AppSpacing.lg, color: AppColors.divider),
                    _AverageRow(
                      label: 'Avg Rate',
                      value: '${(trainingSessions.map((s) => s.averageFrequency).reduce((a, b) => a + b) / trainingSessions.length).round()} BPM',
                      color: AppColors.primary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatsTile extends StatelessWidget {
  final IconData icon;
  final String   value;
  final String   label;
  const _StatsTile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: AppSpacing.iconSm, color: AppColors.textOnDark.withValues(alpha: 0.7)),
        const SizedBox(height: AppSpacing.xs),
        Text(value,
            style: AppTypography.numericDisplay(size: 20, color: AppColors.textOnDark)),
        const SizedBox(height: AppSpacing.xxs),
        Text(label,
            textAlign: TextAlign.center,
            style: AppTypography.label(size: 10,
                color: AppColors.textOnDark.withValues(alpha: 0.6))),
      ],
    );
  }
}

class _AverageRow extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _AverageRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.body(size: 14)),
        Text(value,
            style: AppTypography.bodyBold(size: 14, color: color)),
      ],
    );
  }
}

class _GradeSparklinePainter extends CustomPainter {
  final List<double> grades;
  const _GradeSparklinePainter({required this.grades});

  @override
  void paint(Canvas canvas, Size size) {
    if (grades.length < 2) return;

    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final minG = grades.reduce((a, b) => a < b ? a : b).clamp(0.0, 100.0);
    final maxG = grades.reduce((a, b) => a > b ? a : b).clamp(0.0, 100.0);
    final range = (maxG - minG).abs() < 5 ? 20.0 : (maxG - minG) * 1.2;
    final midG  = (minG + maxG) / 2;
    final lo    = (midG - range / 2).clamp(0.0, 100.0);
    final hi    = lo + range;

    double xOf(int i) => i / (grades.length - 1) * size.width;
    double yOf(double g) => size.height - ((g - lo) / (hi - lo)).clamp(0.0, 1.0) * size.height;

    final path = Path()..moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < grades.length; i++) {
      path.lineTo(xOf(i), yOf(grades[i]));
    }

    // Fill area under line
    final fillPath = Path.from(path)
      ..lineTo(xOf(grades.length - 1), size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Draw dots at each point
    final dotPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;
    for (int i = 0; i < grades.length; i++) {
      canvas.drawCircle(Offset(xOf(i), yOf(grades[i])), 3.5, dotPaint);
      canvas.drawCircle(
        Offset(xOf(i), yOf(grades[i])), 3.5,
        Paint()..color = AppColors.surfaceWhite..style = PaintingStyle.stroke..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GradeSparklinePainter old) =>
      old.grades != grades;
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.iconSm, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label,
                style: AppTypography.bodyMedium(size: 13)),
          ),
        ],
      ),
    );
  }
}