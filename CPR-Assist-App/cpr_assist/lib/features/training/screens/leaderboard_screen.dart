import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../services/achievement_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cpr_assist/features/training/widgets/cpr_chart_helpers.dart';
import 'package:cpr_assist/features/training/screens/achievements_screen.dart';

import '../widgets/session_results.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LeaderboardScreen
//
// Tab bar: Global | Friends | My Stats
//
// Global  — real data from GET /leaderboard/global, filterable by scenario.
// Friends — placeholder (no backend friends system yet).
// My Stats — real data via sessionSummariesProvider + SessionCard.
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
        backgroundColor:        AppColors.white,
        foregroundColor:        AppColors.textPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight - AppSpacing.sm,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('Leaderboard', style: AppTypography.heading(size: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Align(
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  color:        AppColors.screenBgGrey,
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                  border:       Border.all(color: AppColors.divider),
                ),
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _scenarioOptions.entries.map((e) {
                    final isSelected = e.key == _scenario;
                    return GestureDetector(
                      onTap: () => setState(() => _scenario = e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm + AppSpacing.xxs,
                          vertical:   AppSpacing.xxxs,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.transparent,
                          borderRadius:
                          BorderRadius.circular(AppSpacing.buttonRadiusLg),
                        ),
                        child: Text(
                          e.value,
                          style: AppTypography.label(
                            size:  12,
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
          ),
        ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppSpacing.xxl + AppSpacing.xxs),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(
                    controller:           _tabController,
                    labelColor:           AppColors.primary,
                    unselectedLabelColor: AppColors.textDisabled,
                    indicatorColor:       AppColors.primary,
                    indicatorWeight:      2.5,
                    dividerColor:         Colors.transparent,
                    labelStyle: AppTypography.label(size: 13, color: AppColors.primary),
                    unselectedLabelStyle: AppTypography.label(size: 13, color: AppColors.textDisabled),
                    tabs: const [
                      Tab(text: 'Global'),
                      Tab(text: 'Friends'),
                      Tab(text: 'My Stats'),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _GlobalTab(
            scenario:        _scenario,
            scenarioOptions: _scenarioOptions,
          ),
        _FriendsTab(scenario: _scenario),
          _MyStatsTab(scenario: _scenario),
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

  const _GlobalTab({
    required this.scenario,
    required this.scenarioOptions,
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
                top:    AppSpacing.md,
                bottom: (myRank != null
                    ? AppSpacing.xxl + AppSpacing.xl + AppSpacing.md
                    : AppSpacing.md) + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
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
                        Text(
                          'No ${scenarioOptions[scenario] ?? ''} rankings yet',
                          style: AppTypography.subheading(color: AppColors.textSecondary),
                        ),
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('RANKINGS',
                              style: AppTypography.label(size: 11)),
                          Text('${entries.length - 3} more · ${scenarioOptions[scenario] ?? ''}',
                              style: AppTypography.caption(color: AppColors.textDisabled)),
                        ],
                      ),
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
          AppSpacing.sm, AppSpacing.xl, AppSpacing.sm, 0),
      clipBehavior: Clip.hardEdge,
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
              color: entry.isCurrentUser
                  ? AppColors.pbGoldDark
                  : AppColors.textOnDark.withValues(alpha: 0.4),
              width: entry.isCurrentUser ? 2.5 : (isFirst ? 2.5 : 2.0),
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

  static Color _gradeColor(double g) {
    if (g >= 90) return AppColors.success;
    if (g >= 75) return AppColors.primaryAlt;
    if (g >= 55) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final isMe = entry.isCurrentUser;
    return Container(
      decoration: isMe ? BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.5),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ) : null,
      padding: EdgeInsets.only(
        left:   isMe ? AppSpacing.md - 3 : AppSpacing.md,
        right:  AppSpacing.md,
        top:    AppSpacing.sm + AppSpacing.xs,
        bottom: AppSpacing.sm + AppSpacing.xs,
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppSpacing.iconLg - AppSpacing.xxs,
            child: Text('#${entry.rank}',
                style: AppTypography.label(
                    color: isMe ? AppColors.primary : AppColors.textDisabled),
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
                  ],
                ),
                Text('${entry.sessionCount} training sessions',
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
            decoration: AppDecorations.chip(
              color: _gradeColor(entry.avgGrade),
              bg:    _gradeColor(entry.avgGrade).withValues(alpha: 0.10),
            ),
            child: Text('${entry.avgGrade.toStringAsFixed(1)}%',
                style: AppTypography.bodyBold(size: 12, color: _gradeColor(entry.avgGrade))),
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
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.divider)),
        boxShadow: [
          BoxShadow(
              color:      AppColors.shadowMedium,
              blurRadius: 12,
              offset:     Offset(0, -3)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.sm + AppSpacing.xs + MediaQuery.paddingOf(context).bottom,
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
            Text('You · ${entry.sessionCount} training sessions',
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
                        : entry.avgGrade >= 75 ? AppColors.primaryAlt
                        : entry.avgGrade >= 55 ? AppColors.warning
                        : AppColors.error,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('YOUR RANK',
              style: AppTypography.badge(size: 9, color: AppColors.textDisabled)),
          const SizedBox(height: AppSpacing.xxs),
          Text('#${entry.rank}',
              style: AppTypography.heading(size: 18, color: AppColors.primary)),
        ],
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
  final String scenario;
  const _FriendsTab({required this.scenario});

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
  final String scenario;
  const _MyStatsTab({required this.scenario});

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
                style: AppTypography.subheading(
                    color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => ref.invalidate(sessionSummariesProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (sessions) {
        final training = sessions
            .where((s) => s.isTraining && s.scenario ==
            (scenario == 'standard_adult'
                ? 'standard_adult'
                : 'pediatric'))
            .toList()
            .cast<SessionSummary>();

        int streak = 0;
        for (final s in training) {
          if (s.totalGrade >= 75) {
            streak++;
          } else {
            break;
          }
        }

        if (training.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.bar_chart_rounded,
                      size: AppSpacing.iconXl + AppSpacing.md,
                      color: AppColors.textDisabled),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No ${scenario == 'standard_adult' ? 'Adult' : 'Pediatric'} stats yet',
                    style: AppTypography.subheading(
                        color: AppColors.textDisabled),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Complete training sessions in this scenario\nto see your stats.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body(
                        color: AppColors.textDisabled),
                  ),
                ],
              ),
            ),
          );
        }

        final avgGrade = training
            .map((s) => s.totalGrade)
            .reduce((a, b) => a + b) /
            training.length;
        final bestSession = training.reduce(
                (a, b) => a.totalGrade > b.totalGrade ? a : b);
        final totalCompressions = training
            .fold<int>(0, (sum, s) => sum + s.compressionCount);
        final totalSecs = training
            .fold<int>(0, (sum, s) => sum + s.sessionDuration);

        // Trend: compare last 3 vs previous 3
        String trendLabel = 'Stable';
        Color  trendColor = AppColors.primary;
        IconData trendIcon = Icons.remove_rounded;
        if (training.length >= 6) {
          final last3 = training.take(3)
              .map((s) => s.totalGrade).reduce((a, b) => a + b) / 3;
          final prev3 = training.skip(3).take(3)
              .map((s) => s.totalGrade).reduce((a, b) => a + b) / 3;
          final delta = last3 - prev3;
          if (delta > 2) {
            trendLabel = 'Improving';
            trendColor = AppColors.success;
            trendIcon  = Icons.trending_up_rounded;
          } else if (delta < -2) {
            trendLabel = 'Declining';
            trendColor = AppColors.warning;
            trendIcon  = Icons.trending_down_rounded;
          }
        }

        // Skill breakdown (averaged across scenario sessions)
        // Skill breakdown averages (for breakdown card)
        final avgDepth = training.map((s) => s.averageDepth).reduce((a,b)=>a+b) / training.length;
        final avgRate  = training.map((s) => s.averageFrequency).reduce((a,b)=>a+b) / training.length;
        final avgCCF   = training.map((s) => s.handsOnRatio * 100).reduce((a,b)=>a+b) / training.length;
        final avgRecoil = training.map((s) => s.compressionCount > 0
            ? s.correctRecoil / s.compressionCount * 100 : 0.0)
            .reduce((a,b)=>a+b) / training.length;

        // Depth and rate accuracy as % of sessions in target range
        final targetMin = scenario == 'standard_adult' ? 5.0 : 4.0;
        final targetMax = scenario == 'standard_adult' ? 6.0 : 5.0;
        const targetRateMin = 100.0;
        const targetRateMax = 120.0;
        final depthAccuracy = (avgDepth >= targetMin &&
            avgDepth <= targetMax)
            ? 100.0
            : avgDepth < targetMin
            ? (avgDepth / targetMin * 100).clamp(0.0, 100.0)
            : (targetMax / avgDepth * 100).clamp(0.0, 100.0);
        final rateAccuracy =
        (avgRate >= targetRateMin && avgRate <= targetRateMax)
            ? 100.0
            : avgRate < targetRateMin
            ? (avgRate / targetRateMin * 100).clamp(0.0, 100.0)
            : (targetRateMax / avgRate * 100).clamp(0.0, 100.0);

        // Best single-session per metric (for Personal Records)
        SessionSummary? bestDepthSession;
        SessionSummary? bestRateSession;
        SessionSummary? bestRecoilSession;
        if (training.isNotEmpty) {
          bestDepthSession  = training.reduce((a, b) =>
          (a.compressionCount > 0 ? a.correctDepth  / a.compressionCount : 0) >
              (b.compressionCount > 0 ? b.correctDepth  / b.compressionCount : 0) ? a : b);
          bestRateSession   = training.reduce((a, b) =>
          (a.compressionCount > 0 ? a.correctFrequency / a.compressionCount : 0) >
              (b.compressionCount > 0 ? b.correctFrequency / b.compressionCount : 0) ? a : b);
          bestRecoilSession = training.reduce((a, b) =>
          (a.compressionCount > 0 ? a.correctRecoil / a.compressionCount : 0) >
              (b.compressionCount > 0 ? b.correctRecoil / b.compressionCount : 0) ? a : b);
        }

        // Next milestone
        final achievements = AchievementService.compute(training);
        Achievement? nextAchievement;
        double bestFraction = -1;
        for (final a in achievements.where((a) => !a.unlocked)) {
          double fraction;
          switch (a.id) {
            case 'five_sessions':       fraction = (training.length / 5).clamp(0.0, 0.99); break;
            case 'ten_sessions':        fraction = (training.length / 10).clamp(0.0, 0.99); break;
            case 'compressions_500':    fraction = (totalCompressions / 500).clamp(0.0, 0.99); break;
            case 'compressions_2000':   fraction = (totalCompressions / 2000).clamp(0.0, 0.99); break;
            case 'streak_3':            fraction = (streak / 3).clamp(0.0, 0.99); break;
            case 'streak_5':            fraction = (streak / 5).clamp(0.0, 0.99); break;
            case 'perfect_score':       fraction = (avgGrade / 90).clamp(0.0, 0.99); break;
            default:                    fraction = 0.0;
          }
          if (fraction > bestFraction) {
            bestFraction = fraction;
            nextAchievement = a;
          }
        }

        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md,
            AppSpacing.md + MediaQuery.paddingOf(context).bottom,
          ),
          children: [

            // ── Hero card ────────────────────────────────────────────────
            _StatsHeroCard(
              avgGrade:   avgGrade,
              trendLabel: trendLabel,
              trendColor: trendColor,
              trendIcon:  trendIcon,
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Effort row ───────────────────────────────────────────────
            _EffortRow(
              sessions:    training.length,
              compressions: totalCompressions,
              totalSecs:    totalSecs,
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Skill breakdown ──────────────────────────────────────────
            _SkillBreakdownCard(
              depth:        depthAccuracy.clamp(0.0, 100.0),
              rate:         rateAccuracy.clamp(0.0, 100.0),
              recoil:       avgRecoil.clamp(0.0, 100.0),
              ccf:          avgCCF.clamp(0.0, 100.0),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Grade trend chart ────────────────────────────────────────
            _GradeTrendCard(sessions: training),
            const SizedBox(height: AppSpacing.md),

            // ── Personal records ─────────────────────────────────────────
            _PersonalRecordsCard(
              bestSession:      bestSession,
              allSessions:      training,
              bestDepthSession:  bestDepthSession,
              bestRateSession:   bestRateSession,
              bestRecoilSession: bestRecoilSession,
            ),

            // ── Next milestone ───────────────────────────────────────────
            if (nextAchievement != null) ...[
              const SizedBox(height: AppSpacing.md),
              _NextMilestoneCard(
                achievement:      nextAchievement,
                trainingCount:    training.length,
                totalCompressions: totalCompressions,
                currentStreak:    streak,
              ),
            ],

            const SizedBox(height: AppSpacing.md),
          ],
        );
      },
    );
  }
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


// ─────────────────────────────────────────────────────────────────────────────
// STATS HERO CARD
// ─────────────────────────────────────────────────────────────────────────────

class _StatsHeroCard extends StatelessWidget {
  final double   avgGrade;
  final String   trendLabel;
  final Color    trendColor;
  final IconData trendIcon;

  const _StatsHeroCard({
    required this.avgGrade,
    required this.trendLabel,
    required this.trendColor,
    required this.trendIcon,
  });

  Color get _gradeColor {
    if (avgGrade >= 90) return AppColors.feedbackGood;
    if (avgGrade >= 75) return AppColors.feedbackInfo;
    if (avgGrade >= 55) return AppColors.feedbackWarn;
    return AppColors.feedbackBad;
  }

  Color get _trendFeedbackColor {
    if (trendLabel == 'Improving') return AppColors.feedbackGood;
    if (trendLabel == 'Declining') return AppColors.feedbackBad;
    return AppColors.textOnDark.withValues(alpha: 0.55);
  }

  @override
  Widget build(BuildContext context) {
    final level      = AchievementService.gradeLevel(avgGrade);
    final levelColor = AchievementService.gradeLevelColorDark(avgGrade);
    final nextName   = AchievementService.nextLevelName(avgGrade);
    final nextThresh = AchievementService.nextLevelThreshold(avgGrade);
    final gap        = (nextThresh - avgGrade).clamp(0.0, 100.0);
    final chipColor  = _trendFeedbackColor;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.gradeCard(),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Grade ring ────────────────────────────────────────────────
              SizedBox(
                width:  AppSpacing.avatarXl,
                height: AppSpacing.avatarXl,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value:           (avgGrade / 100).clamp(0.0, 1.0),
                        strokeWidth:     7,
                        strokeCap:       StrokeCap.round,
                        backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
                        valueColor:      AlwaysStoppedAnimation<Color>(_gradeColor),
                      ),
                    ),
                    Text(
                      '${avgGrade.toStringAsFixed(1)}%',
                      style: AppTypography.numericDisplay(
                          size: 16, color: AppColors.textOnDark),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              // ── Right side ────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level,
                        style: AppTypography.heading(
                            size: 20, color: AppColors.textOnDark)),
                    if (nextName != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '+${gap.toStringAsFixed(1)}%',
                              style: AppTypography.bodyMedium(
                                  size: 13, color: levelColor),
                            ),
                            TextSpan(
                              text: ' to $nextName',
                              style: AppTypography.body(
                                  size: 13,
                                  color: AppColors.textOnDark
                                      .withValues(alpha: 0.55)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // ── Trend chip ───────────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical:   AppSpacing.xxs,
                      ),
                      decoration: AppDecorations.darkTrendPill(chipColor).copyWith(
                        border: Border.all(color: Colors.transparent, width: 0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendIcon, size: 10, color: chipColor),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(trendLabel,
                              style: AppTypography.badge(size: 10, color: chipColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // ── Info button ───────────────────────────────────────────────────
          Positioned(
            top:   0,
            right: 0,
            child: GestureDetector(
              onTap: () => AppDialogs.showLevelInfo(context, avgGrade: avgGrade),
              child: Container(
                width:  28,
                height: 28,
                decoration: AppDecorations.iconCircle(
                    bg: AppColors.textOnDark.withValues(alpha: 0.15)),
                child: const Icon(Icons.help_outline_rounded,
                    size: 15, color: AppColors.textOnDark),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// EFFORT ROW
// ─────────────────────────────────────────────────────────────────────────────

class _EffortRow extends StatelessWidget {
  final int sessions;
  final int compressions;
  final int totalSecs;

  const _EffortRow({
    required this.sessions,
    required this.compressions,
    required this.totalSecs,
  });

  String get _fmtTime {
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }

  String _fmtCompressions(int n) =>
      n > 999 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg, horizontal: AppSpacing.md),
      decoration: AppDecorations.gradeCard(),
      child: Row(
        children: [
          _EffortTile(value: '$sessions',                label: 'SESSIONS'),
          _VertDivider(),
          _EffortTile(value: _fmtCompressions(compressions), label: 'COMPRESSIONS'),
          _VertDivider(),
          _EffortTile(value: _fmtTime,                   label: 'CPR TIME'),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.textOnDark.withValues(alpha: 0.15),
    );
  }
}

class _EffortTile extends StatelessWidget {
  final String   value;
  final String   label;

  const _EffortTile({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: AppTypography.numericDisplay(
                  size: 20, color: AppColors.textOnDark)),
          const SizedBox(height: AppSpacing.xxs),
          Text(label,
              style: AppTypography.badge(
                  size: 9,
                  color: AppColors.textOnDark.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SKILL BREAKDOWN
// ─────────────────────────────────────────────────────────────────────────────

class _SkillBreakdownCard extends StatelessWidget {
  final double depth;
  final double rate;
  final double recoil;
  final double ccf;

  const _SkillBreakdownCard({
    required this.depth,
    required this.rate,
    required this.recoil,
    required this.ccf,
  });

  @override
  Widget build(BuildContext context) {

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSpacing.xs,
                height: AppSpacing.iconMd,
                decoration: AppDecorations.accentBar(color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Skill breakdown', style: AppTypography.subheading(size: 14)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SkillRow(label: 'Depth',    value: depth),
          _SkillRow(label: 'Rate',     value: rate),
          _SkillRow(label: 'Recoil',   value: recoil),
          _SkillRow(label: 'Hands-on', value: ccf),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final String label;
  final double value;

  const _SkillRow({required this.label, required this.value});

  Color get _color {
    if (value >= 85) return AppColors.success;
    if (value >= 70) return AppColors.primaryAlt;
    if (value >= 50) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        children: [
      Row(
      children: [
      SizedBox(
      width: 80,
        child: Text(label, style: AppTypography.body(size: 13)),
      ),
      const Spacer(),
      SizedBox(
        width: 36,
        child: Text(
          '${value.toStringAsFixed(0)}%',
          textAlign: TextAlign.right,
          style: AppTypography.bodyBold(size: 13, color: _color),
        ),
      ),
      ],
    ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
            child: LinearProgressIndicator(
              value:           (value / 100).clamp(0.0, 1.0),
              minHeight:       8,
              backgroundColor: AppColors.divider,
              valueColor:      AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GRADE TREND CHART
// ─────────────────────────────────────────────────────────────────────────────

class _GradeTrendCard extends StatefulWidget {
  final List<SessionSummary> sessions;
  const _GradeTrendCard({required this.sessions});

  @override
  State<_GradeTrendCard> createState() => _GradeTrendCardState();
}

class _GradeTrendCardState extends State<_GradeTrendCard> {
  int? _window = 10;
  int  _scrollIdx = 0;

  List<SessionSummary> get _sorted => widget.sessions.reversed.toList();
  int get _total => _sorted.length;
  int get _effectiveWindow => _window ?? _total;

  bool get _isFixed    => _window == 5;
  bool get _canScroll  => !_isFixed && _window != null && _total > _effectiveWindow;
  bool get _showDots   => _window != null && _effectiveWindow < 20;

  void _onWindowChanged(int? w) => setState(() {
    _window    = w;
    _scrollIdx = 0;
  });

  void _onDrag(DragUpdateDetails d) {
    if (!_canScroll) return;
    final pxPerSession = 260.0 / _effectiveWindow;
    final delta = (-d.delta.dx / pxPerSession).round();
    setState(() {
      _scrollIdx =
      (_scrollIdx + delta).clamp(0, _total - _effectiveWindow);
    });
  }

  List<SessionSummary> get _windowSessions {
    final sorted = _sorted;
    if (_window == null) return sorted;
    if (_isFixed) {
      return sorted.length <= 5
          ? sorted
          : sorted.sublist(sorted.length - 5);
    }
    return sorted.skip(_scrollIdx).take(_effectiveWindow).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    if (sorted.length < 2) return const SizedBox.shrink();

    final windowSessions = _windowSessions;
    final spots = windowSessions.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.totalGrade))
        .toList();

    final grades   = windowSessions.map((s) => s.totalGrade).toList();
    final minGrade = grades.reduce((a, b) => a < b ? a : b);
    final yMin     = (minGrade - 8).clamp(0.0, 70.0);
    const yMax     = 100.0;

    // ── Window dropdown ───────────────────────────────────────────────────────
    final windowDropdown = Builder(
      builder: (chipContext) => GestureDetector(
        onTapDown: (details) async {
          final box     = chipContext.findRenderObject() as RenderBox;
          final boxSize = box.size;
          final offset  = box.localToGlobal(Offset.zero);
          final screenW = MediaQuery.sizeOf(chipContext).width;

          final result = await showMenu<int>(
            context:   chipContext,
            color:     AppColors.white,
            shape:     RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd)),
            elevation: 4,
            position:  RelativeRect.fromLTRB(
              offset.dx,
              offset.dy + boxSize.height + 4,
              screenW - offset.dx - boxSize.width,
              0,
            ),
            items: [
              PopupMenuItem<int>(
                value:  5,
                height: 36,
                child:  Text('Last 5',
                    style: AppTypography.body(
                        size:  13,
                        color: _window == 5
                            ? AppColors.primary
                            : AppColors.textPrimary)),
              ),
              PopupMenuItem<int>(
                value:  10,
                height: 36,
                child:  Text('10 sessions',
                    style: AppTypography.body(
                        size:  13,
                        color: _window == 10
                            ? AppColors.primary
                            : AppColors.textPrimary)),
              ),
              PopupMenuItem<int>(
                value:  20,
                height: 36,
                child:  Text('20 sessions',
                    style: AppTypography.body(
                        size:  13,
                        color: _window == 20
                            ? AppColors.primary
                            : AppColors.textPrimary)),
              ),
              PopupMenuItem<int>(
                value:  -1, // sentinel for "All"
                height: 36,
                child:  Text('All',
                    style: AppTypography.body(
                        size:  13,
                        color: _window == null
                            ? AppColors.primary
                            : AppColors.textPrimary)),
              ),
            ],
          );

          if (result != null) {
            _onWindowChanged(result == -1 ? null : result);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 3),
          decoration: BoxDecoration(
            color:        AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
            border:       Border.all(
                color: AppColors.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _window == null  ? 'All'
                    : _window == 5 ? 'Last 5'
                    : '$_window',
                style: AppTypography.badge(
                    size: 10, color: AppColors.primary),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded,
                  size: 12, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );

    return CprChartCard(
      title:     'Grade Trend',
      subtitle:  '$_total training sessions',
      lineColor: AppColors.primary,
      dropdown:  windowDropdown,
      child: GestureDetector(
        onHorizontalDragUpdate: _onDrag,
        child: Column(
          children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: SizedBox(
                  height: 140,
                  child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (windowSessions.length - 1).toDouble(),
                  minY:      yMin,
                  maxY:      yMax,
                  clipData:  const FlClipData.none(),
                  backgroundColor:
                  AppColors.screenBgGrey.withValues(alpha: 0.5),
                  gridData: FlGridData(
                    show:             true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color:       AppColors.divider,
                      strokeWidth: AppSpacing.dividerThickness,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  rangeAnnotations: RangeAnnotations(
                    horizontalRangeAnnotations: [
                      HorizontalRangeAnnotation(
                        y1:    79,
                        y2:    81,
                        color: AppColors.success.withValues(alpha: 0.08),
                      ),
                    ],
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y:           80,
                        color:       AppColors.success.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray:   [4, 4],
                        label:       HorizontalLineLabel(show: false),
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles:   true,
                        reservedSize: 28,
                        interval:     10,
                        getTitlesWidget: (v, meta) {
                          if (v % 10 != 0) return const SizedBox.shrink();
                          if (v < yMin || v > yMax) {
                            return const SizedBox.shrink();
                          }
                          final is80 = (v - 80).abs() < 0.5;
                          return Text(
                            '${v.toInt()}',
                            style: AppTypography.caption(
                              color: is80
                                  ? AppColors.success
                                  : AppColors.textDisabled,
                            ).copyWith(
                              fontWeight: is80
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          );
                        },
                      ),
                    ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles:   true,
                          reservedSize: 18,
                          interval:     1,
                            getTitlesWidget: (value, meta) {
                              final idx = value.round();
                              if (idx < 0 || idx >= windowSessions.length) {
                                return const SizedBox.shrink();
                              }
                              final n = windowSessions.length;

                              // Density: how many labels to show based on window size
                              final int step;
                              if (n <= 5) {
                                step = 1;        // all 5
                              } else if (n <= 10) {
                                step = 2;        // every 2nd ≈ 5 labels
                              } else {
                                step = ((n - 1) / 6).ceil().clamp(1, 999); // ~6 labels
                              }

                              if (idx % step != 0) return const SizedBox.shrink();

                              final date = windowSessions[idx].sessionStart;
                              if (date == null) return const SizedBox.shrink();

                              final currentYear = windowSessions.last.sessionStart?.year
                                  ?? DateTime.now().year;
                              final showYear = date.year != currentYear;
                              final label = showYear
                                  ? '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year.toString().substring(2)}'
                                  : '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

                              return SideTitleWidget(
                                meta:  meta,
                                space: 4,
                                child: Text(label,
                                    style: AppTypography.caption(color: AppColors.textDisabled)),
                              );
                            },
                        ),
                      ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots:            spots,
                      isCurved:         true,
                      curveSmoothness:  0.3,
                      preventCurveOverShooting: true,
                      color:            AppColors.primary,
                      barWidth:         2,
                      dotData: FlDotData(
                        show: _showDots,
                        getDotPainter: (spot, _, __, ___) =>
                            FlDotCirclePainter(
                              radius:      3.0,
                              color:       spot.y >= 80
                                  ? AppColors.success
                                  : AppColors.primary,
                              strokeWidth: 1.5,
                              strokeColor: AppColors.white,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show:  true,
                        color: AppColors.primary.withValues(alpha: 0.06),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchSpotThreshold: 24,
                    getTouchedSpotIndicator: (_, idxs) => idxs
                        .map((_) => TouchedSpotIndicatorData(
                      FlLine(
                        color: AppColors.primary
                            .withValues(alpha: 0.25),
                        strokeWidth: 1,
                      ),
                      const FlDotData(show: false),
                    ))
                        .toList(),
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor:      (_) => AppColors.white,
                      tooltipBorder:        const BorderSide(
                          color: AppColors.divider),
                      tooltipBorderRadius:  BorderRadius.circular(
                          AppSpacing.cardRadiusSm),
                      tooltipPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical:   AppSpacing.xs),
                      getTooltipItems: (touchedSpots) =>
                          touchedSpots.map((s) {
                            final idx = s.x
                                .toInt()
                                .clamp(0, windowSessions.length - 1);
                            final session = windowSessions[idx];
                            final d       = session.sessionStart;
                            final dateStr = d != null
                                ? '${_monthAbbr(d.month)} ${d.day} ${d.year}'
                                '  •  '
                                '${d.hour.toString().padLeft(2, '0')}:'
                                '${d.minute.toString().padLeft(2, '0')}'
                                : '';
                            final ok = session.totalGrade >= 80;
                            return LineTooltipItem(
                              '',
                              const TextStyle(),
                              children: [
                                TextSpan(
                                  text:  '$dateStr\n',
                                  style: AppTypography.caption(
                                      color: AppColors.textSecondary),
                                ),
                                TextSpan(
                                  text: '${session.totalGrade
                                      .toStringAsFixed(1)}%',
                                  style: AppTypography.bodyBold(
                                    size:  14,
                                    color: ok
                                        ? AppColors.success
                                        : AppColors.primary,
                                  ),
                                ),
                                TextSpan(
                                  text:  '  grade',
                                  style: AppTypography.caption(
                                      color: AppColors.textSecondary),
                                ),
                              ],
                            );
                          }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            ),
            if (_canScroll) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: CprScrollBar(
                  windowStart:   _scrollIdx.toDouble(),
                  sessionLength: (_total - 1).toDouble(),
                  windowSecs:    _effectiveWindow.toDouble(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _monthAbbr(int m) => const [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
// PERSONAL RECORDS
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalRecordsCard extends ConsumerWidget {
  final SessionSummary bestSession;
  final List<SessionSummary> allSessions;
  final SessionSummary? bestDepthSession;
  final SessionSummary? bestRateSession;
  final SessionSummary? bestRecoilSession;

  const _PersonalRecordsCard({
    required this.bestSession,
    required this.allSessions,
    required this.bestDepthSession,
    required this.bestRateSession,
    required this.bestRecoilSession,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    allSessions.indexOf(bestSession);
    final longestSession = allSessions.reduce(
            (a, b) => a.sessionDuration > b.sessionDuration ? a : b);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppSpacing.xs,
                height: AppSpacing.iconMd,
                decoration: AppDecorations.accentBar(color: AppColors.pbGoldDark),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Personal records', style: AppTypography.subheading(size: 14)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Best session hero
        GestureDetector(
          onTap: () {
            allSessions.indexOf(bestSession);
            openSessionResults(context, ref, summary: bestSession);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.pbGoldDark, AppColors.pbGoldLight],
                begin:  Alignment.topLeft,
                end:    Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BEST SESSION EVER',
                          style: AppTypography.badge(
                              size: 10, color: AppColors.pbGoldText)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${bestSession.totalGrade.toStringAsFixed(1)}%',
                        style: AppTypography.numericDisplay(
                            size: 36, color: AppColors.pbGoldText),
                      ),
                      Text(
                        'Session #${bestSession.sessionNumber ?? (allSessions.length - (allSessions.contains(bestSession) ? allSessions.indexOf(bestSession) : 0))}'
                            '  ·  ${bestSession.dateTimeFormatted}',
                        style: AppTypography.caption(
                            color: AppColors.pbGoldText.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          const Icon(Icons.touch_app_rounded,
                              size: 11, color: AppColors.pbGoldText),
                          const SizedBox(width: AppSpacing.xxs),
                          Text('Tap to view session',
                              style: AppTypography.caption(
                                  color: AppColors.pbGoldText
                                      .withValues(alpha: 0.6))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Text('🏆', style: TextStyle(fontSize: 44)),
              ],
            ),
          ),
        ),

          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.divider),

          _RecordRow(
            label:         'Best depth accuracy',
            value:         bestDepthSession != null
                ? '${(bestDepthSession!.correctDepth / bestDepthSession!.compressionCount * 100).clamp(0,100).toStringAsFixed(0)}%'
                : '—',
            session:       bestDepthSession,
            sessionNumber: bestDepthSession != null
                ? (bestDepthSession!.sessionNumber ?? (allSessions.length - allSessions.indexOf(bestDepthSession!)))
                : null,
            allSessions:   allSessions,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _RecordRow(
            label:         'Best rate accuracy',
            value:         bestRateSession != null
                ? '${(bestRateSession!.correctFrequency / bestRateSession!.compressionCount * 100).clamp(0,100).toStringAsFixed(0)}%'
                : '—',
            session:       bestRateSession,
            sessionNumber: bestRateSession != null
                ? (bestRateSession!.sessionNumber ?? (allSessions.length - allSessions.indexOf(bestRateSession!)))
                : null,
            allSessions:   allSessions,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _RecordRow(
            label:         'Best recoil session',
            value:         bestRecoilSession != null
                ? '${(bestRecoilSession!.correctRecoil / bestRecoilSession!.compressionCount * 100).clamp(0,100).toStringAsFixed(0)}%'
                : '—',
            session:       bestRecoilSession,
            sessionNumber: bestRecoilSession != null
                ? (bestRecoilSession!.sessionNumber ?? (allSessions.length - allSessions.indexOf(bestRecoilSession!)))
                : null,
            allSessions:   allSessions,
          ),
          const Divider(height: 1, color: AppColors.divider),
          _RecordRow(
            label:       'Longest session',
            value:       longestSession.durationFormatted,
            session:     longestSession,
            sessionNumber: longestSession.sessionNumber ?? (allSessions.length - allSessions.indexOf(longestSession)),
            allSessions: allSessions,
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends ConsumerWidget {
  final String         label;
  final String         value;
  final int?           sessionNumber;
  final SessionSummary? session;
  final List<SessionSummary> allSessions;
  final String? subtitle;

  const _RecordRow({
    required this.label,
    required this.value,
    this.sessionNumber,
    this.session,
    this.allSessions = const [],
    this.subtitle,
  });


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canTap = session != null;
    return GestureDetector(
      onTap: canTap
          ? () {
        allSessions.indexOf(session!);
        openSessionResults(context, ref, summary: session!);
      }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
        Expanded(
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: AppTypography.body(size: 13)),
                if (sessionNumber != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text('#$sessionNumber',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
                ],
              ],
            ),
            if (subtitle != null)
              Text(subtitle!,
                  style: AppTypography.caption(
                      color: AppColors.textDisabled)),
          ],
        ),
      ),
            Text(value,
                style: AppTypography.bodyBold(
                    size: 13, color: AppColors.textPrimary)),
            if (canTap) ...[
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right_rounded,
                  size: AppSpacing.iconSm,
                  color: AppColors.textDisabled),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NEXT MILESTONE
// ─────────────────────────────────────────────────────────────────────────────

class _NextMilestoneCard extends ConsumerWidget {
  final Achievement achievement;
  final int         trainingCount;
  final int         totalCompressions;
  final int         currentStreak;

  const _NextMilestoneCard({
    required this.achievement,
    required this.trainingCount,
    required this.totalCompressions,
    required this.currentStreak,
  });

  // Returns (current, target) for a progress bar, or null if not applicable.
  (int, int)? get _progress {
    switch (achievement.id) {
      case 'five_sessions':   return (trainingCount, 5);
      case 'ten_sessions':    return (trainingCount, 10);
      case 'compressions_500':  return (totalCompressions, 500);
      case 'compressions_2000': return (totalCompressions, 2000);
      case 'streak_3': return (currentStreak, 3);
      case 'streak_5': return (currentStreak, 5);
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prog = _progress;

    return GestureDetector(
      onTap: () => context.push(const AchievementsScreen()),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: AppDecorations.card(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width:  AppSpacing.avatarMd + AppSpacing.xs,
              height: AppSpacing.avatarMd + AppSpacing.xs,
              decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
              child: Center(
                child: Text(achievement.emoji,
                    style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Next achievement',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
                  Text(achievement.title,
                      style: AppTypography.bodyMedium(size: 14)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(achievement.description,
                      style: AppTypography.caption(
                          color: AppColors.textSecondary)),
                  if (prog != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius:
                            BorderRadius.circular(AppSpacing.chipRadius),
                            child: LinearProgressIndicator(
                              value: (prog.$1 / prog.$2).clamp(0.0, 1.0),
                              minHeight: 5,
                              backgroundColor: AppColors.divider,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text('${prog.$1} / ${prog.$2}',
                            style: AppTypography.caption(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}








//For dev

// ─────────────────────────────────────────────────────────────────────────────
// Simulated leaderboard preview (dev only)
// ─────────────────────────────────────────────────────────────────────────────

class SimulatedLeaderboardPreview extends StatefulWidget {
  const SimulatedLeaderboardPreview({super.key});
  @override
  State<SimulatedLeaderboardPreview> createState() =>
      _SimulatedLeaderboardPreviewState();
}

class _SimulatedLeaderboardPreviewState
    extends State<SimulatedLeaderboardPreview>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;
  String _scenario = 'standard_adult';

  static const _scenarioOptions = {
    'standard_adult': 'Adult',
    'pediatric':      'Pediatric',
  };

  static final _adultEntries = [
    const LeaderboardEntry(rank: 1, username: 'maria_k',   avgGrade: 94.2, bestGrade: 97.1, sessionCount: 18, isCurrentUser: false),
    const LeaderboardEntry(rank: 2, username: 'nikos_p',   avgGrade: 88.7, bestGrade: 92.4, sessionCount: 12, isCurrentUser: false),
    const LeaderboardEntry(rank: 3, username: 'stavros_d', avgGrade: 84.1, bestGrade: 89.0, sessionCount: 10, isCurrentUser: false),
    const LeaderboardEntry(rank: 4, username: 'eleni_v',   avgGrade: 79.3, bestGrade: 83.2, sessionCount:  5, isCurrentUser: false),
    const LeaderboardEntry(rank: 5, username: 'anti_r',    avgGrade: 73.8, bestGrade: 78.5, sessionCount:  7, isCurrentUser: true),
    const LeaderboardEntry(rank: 6, username: 'kostas_m',  avgGrade: 68.0, bestGrade: 71.0, sessionCount:  4, isCurrentUser: false),
  ];

  static final _pediatricEntries = [
    const LeaderboardEntry(rank: 1, username: 'nikos_p',   avgGrade: 91.5, bestGrade: 95.0, sessionCount:  9, isCurrentUser: false),
    const LeaderboardEntry(rank: 2, username: 'You',       avgGrade: 87.3, bestGrade: 90.1, sessionCount:  5, isCurrentUser: true),
    const LeaderboardEntry(rank: 3, username: 'eleni_v',   avgGrade: 81.0, bestGrade: 84.2, sessionCount:  6, isCurrentUser: false),
    const LeaderboardEntry(rank: 4, username: 'maria_k',   avgGrade: 76.4, bestGrade: 80.0, sessionCount:  4, isCurrentUser: false),
  ];

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
    final entries = _scenario == 'standard_adult' ? _adultEntries : _pediatricEntries;
    final myRank  = entries.firstWhere((e) => e.isCurrentUser);

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.white,
        foregroundColor:        AppColors.textPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight - AppSpacing.sm,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('Leaderboard (simulated)',
            style: AppTypography.heading(size: 18)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(AppSpacing.xxl + AppSpacing.xxs),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(
                    controller:           _tabController,
                    labelColor:           AppColors.primary,
                    unselectedLabelColor: AppColors.textDisabled,
                    indicatorColor:       AppColors.primary,
                    indicatorWeight:      2.5,
                    dividerColor:         Colors.transparent,
                    labelStyle: AppTypography.label(size: 13, color: AppColors.primary),
                    unselectedLabelStyle: AppTypography.label(size: 13, color: AppColors.textDisabled),
                    tabs: const [
                      Tab(text: 'Global'),
                      Tab(text: 'Friends'),
                      Tab(text: 'My Stats'),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(
              bottom: AppSpacing.xxl + AppSpacing.xl + AppSpacing.md +
                  MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              // Scenario toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    decoration: BoxDecoration(
                      color:        AppColors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                      border: Border.all(color: AppColors.divider),
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xxs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _scenarioOptions.entries.map((e) {
                        final isSelected = e.key == _scenario;
                        return GestureDetector(
                          onTap: () => setState(() => _scenario = e.key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical:   AppSpacing.sm - AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.transparent,
                              borderRadius: BorderRadius.circular(
                                  AppSpacing.buttonRadiusLg),
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
              ),
              // Podium
              _Podium(entries: entries.take(3).toList()),
              // Rankings
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.sm, AppSpacing.xl, AppSpacing.xs),
                child: Text('RANKINGS',
                    style: AppTypography.label(size: 11)),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: AppDecorations.card(),
                child: Column(
                  children: entries.skip(3).map((entry) {
                    final isLast = entry == entries.last;
                    return Column(
                      children: [
                        _LeaderRow(entry: entry),
                        if (!isLast)
                          const Divider(
                              height: 1,
                              color:  AppColors.divider,
                              indent: 60,
                              endIndent: AppSpacing.md),
                      ],
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _MyRankFooter(entry: myRank),
          ),
        ],
      ),
    );
  }
}