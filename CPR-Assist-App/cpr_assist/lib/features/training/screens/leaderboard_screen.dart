import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../widgets/session_history.dart';
// ─────────────────────────────────────────────────────────────────────────────
// LeaderboardScreen
//
// Tab bar: Global | Friends | My Sessions
// Global & Friends: placeholder data until backend leaderboard endpoint is wired.
// My Sessions: real data via sessionSummariesProvider + shared SessionCard.
// ─────────────────────────────────────────────────────────────────────────────

class LeaderboardScreen extends StatefulWidget {
  final String? currentUsername;
  const LeaderboardScreen({super.key, this.currentUsername});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Placeholder leaderboard data (replace with provider when API is ready) ─
  final _global = [
    const _LeaderEntry(rank: 1,  username: 'Maria K.',    score: 98.4, sessions: 42, badge: '🥇'),
    const _LeaderEntry(rank: 2,  username: 'Nikos P.',    score: 96.1, sessions: 38, badge: '🥈'),
    const _LeaderEntry(rank: 3,  username: 'Elena T.',    score: 94.7, sessions: 55, badge: '🥉'),
    const _LeaderEntry(rank: 4,  username: 'Giorgos M.',  score: 92.3, sessions: 29),
    const _LeaderEntry(rank: 5,  username: 'Sofia D.',    score: 91.0, sessions: 33),
    const _LeaderEntry(rank: 6,  username: 'Alexis B.',   score: 89.5, sessions: 21),
    const _LeaderEntry(rank: 7,  username: 'Katerina V.', score: 87.2, sessions: 18),
    const _LeaderEntry(rank: 8,  username: 'Petros N.',   score: 85.9, sessions: 44),
    const _LeaderEntry(rank: 9,  username: 'Anna L.',     score: 84.1, sessions: 12),
    const _LeaderEntry(rank: 10, username: 'Kostas F.',   score: 82.7, sessions: 27),
  ];

  final _friends = [
    const _LeaderEntry(rank: 1, username: 'Nikos P.',  score: 96.1, sessions: 38, badge: '🥇'),
    const _LeaderEntry(rank: 2, username: 'Sofia D.',  score: 91.0, sessions: 33, badge: '🥈'),
    const _LeaderEntry(rank: 3, username: 'Alexis B.', score: 89.5, sessions: 21, badge: '🥉'),
  ];

  static const _me = _LeaderEntry(rank: 24, username: 'You', score: 78.4, sessions: 7);

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
        backgroundColor: AppColors.surfaceWhite,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight - AppSpacing.sm,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('Leaderboard', style: AppTypography.heading(size: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(
              AppSpacing.xxl + AppSpacing.xxs),
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
          _GlobalTab(entries: _global, myEntry: _me),
          _FriendsTab(entries: _friends),
          const _PersonalTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL TAB
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalTab extends StatelessWidget {
  final List<_LeaderEntry> entries;
  final _LeaderEntry myEntry;
  const _GlobalTab({required this.entries, required this.myEntry});

  @override
  Widget build(BuildContext context) {
    final top3 = entries.take(3).toList();
    final rest = entries.skip(3).toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(
              bottom: AppSpacing.xxl + AppSpacing.xl),
          children: [
            _Podium(entries: top3),
            if (rest.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.sm,
                    AppSpacing.xl, AppSpacing.xs + AppSpacing.xxs),
                child: Text('RANKINGS',
                    style: AppTypography.label(size: 11)),
              ),
              Container(
                margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md),
                decoration: AppDecorations.card(),
                child: Column(
                  children: rest.asMap().entries.map((e) {
                    final isLast = e.key == rest.length - 1;
                    return Column(
                      children: [
                        _LeaderRow(entry: e.value),
                        if (!isLast)
                          const Divider(
                            height: 1,
                            color: AppColors.divider,
                            indent: 60,
                            endIndent: AppSpacing.md,
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          ],
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _MyRankFooter(entry: myEntry),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PODIUM
// ─────────────────────────────────────────────────────────────────────────────

class _Podium extends StatelessWidget {
  final List<_LeaderEntry> entries;
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
          Expanded(child: _PodiumSpot(entry: entries[0], height: 106, isFirst: true)),
          Expanded(child: _PodiumSpot(entry: entries[2], height: 64)),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  final _LeaderEntry entry;
  final double height;
  final bool isFirst;
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
        if (isFirst)
          const Text('👑', style: TextStyle(fontSize: 20)),
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
                color: AppColors.textOnDark,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          entry.username,
          style: AppTypography.bodyMedium(
            size:  isFirst ? 13 : 11,
            color: AppColors.textOnDark,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${entry.score.toStringAsFixed(1)}%',
          style: AppTypography.body(
            size:  isFirst ? 13 : 11,
            color: AppColors.textOnDark.withValues(alpha: 0.8),
          ),
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
              '#${entry.rank}',
              style: AppTypography.numericDisplay(
                size:  isFirst ? 20 : 16,
                color: AppColors.textOnDark.withValues(alpha: 0.9),
              ),
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
  final _LeaderEntry entry;
  const _LeaderRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
            child: Center(
              child: Text(
                entry.username.initials,
                style: AppTypography.label(
                    size: 12, color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.username,
                    style: AppTypography.bodyMedium(size: 14)),
                Text('${entry.sessions} sessions',
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.chipPaddingH - AppSpacing.xxs,
              vertical:   AppSpacing.chipPaddingV,
            ),
            decoration: AppDecorations.tintedCard(
                radius: AppSpacing.cardRadiusSm),
            child: Text(
              '${entry.score.toStringAsFixed(1)}%',
              style: AppTypography.bodyBold(
                  size: 13, color: AppColors.primary),
            ),
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
  final _LeaderEntry entry;
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
            offset:     Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical:   AppSpacing.sm + AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.chipPaddingH - AppSpacing.xxs,
              vertical:   AppSpacing.chipPaddingV + AppSpacing.xxs,
            ),
            decoration: AppDecorations.tintedCard(
                radius: AppSpacing.cardRadiusSm),
            child: Text(
              '#${entry.rank}',
              style: AppTypography.bodyBold(
                  size: 14, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your rank',
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
                Text(
                  '${entry.sessions} sessions · '
                      '${entry.score.toStringAsFixed(1)}% avg',
                  style: AppTypography.bodyMedium(size: 13),
                ),
              ],
            ),
          ),
          Text('Top 24%',
              style: AppTypography.label(
                  size: 12, color: AppColors.success)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FRIENDS TAB
// ─────────────────────────────────────────────────────────────────────────────

class _FriendsTab extends StatelessWidget {
  final List<_LeaderEntry> entries;
  const _FriendsTab({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.group_outlined,
                size:  AppSpacing.iconXl + AppSpacing.sm,
                color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text('No friends yet',
                style: AppTypography.subheading(
                    color: AppColors.textDisabled)),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Text('Add friends to compare scores',
                style: AppTypography.body(color: AppColors.textDisabled)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Container(
          decoration: AppDecorations.card(),
          child: Column(
            children: entries.asMap().entries.map((e) {
              final isLast = e.key == entries.length - 1;
              return Column(
                children: [
                  _LeaderRow(entry: e.value),
                  if (!isLast)
                    const Divider(
                        height: 1, color: AppColors.divider, indent: 60),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () => UIHelper.showSnackbar(
            context,
            message: 'Add friends coming soon',
            icon: Icons.person_add_outlined,
          ),
          icon: const Icon(Icons.person_add_outlined,
              size: AppSpacing.iconSm),
          label: const Text('Add Friends'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(
                color: AppColors.primaryMid, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(AppSpacing.buttonRadius),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MY SESSIONS TAB
// Watches the real sessionSummariesProvider — same data as PastSessionsScreen.
// Uses shared SessionCard and PersonalBestCard widgets.
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalTab extends ConsumerWidget {
  const _PersonalTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);

    return summaries.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          valueColor:
          AlwaysStoppedAnimation<Color>(AppColors.primary),
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
            Text('Could not load sessions',
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
        if (sessions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded,
                    size:  AppSpacing.iconXl + AppSpacing.md,
                    color: AppColors.textDisabled),
                const SizedBox(height: AppSpacing.md),
                Text('No sessions yet',
                    style: AppTypography.subheading(
                        color: AppColors.textDisabled)),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text('Complete a CPR session to see it here',
                    style: AppTypography.body(
                        color: AppColors.textDisabled)),
              ],
            ),
          );
        }

        // Best session = highest grade
        final trainingSessions = sessions.where((s) => s.isTraining).toList();
        final best = trainingSessions.isEmpty ? null : trainingSessions.reduce(
                (a, b) => a.totalGrade >= b.totalGrade ? a : b);

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          // +1 for the PersonalBestCard at index 0
          itemCount: sessions.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              if (best == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: PersonalBestCard(session: best),
              );
            }
            final session = sessions[i - 1];
            return SessionCard(
              session:       session,
              sessionNumber: i,
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Leaderboard data model (placeholder — replace with backend model when ready)
// ─────────────────────────────────────────────────────────────────────────────

class _LeaderEntry {
  final int rank;
  final String username;
  final double score;
  final int sessions;
  final String? badge;
  const _LeaderEntry({
    required this.rank,
    required this.username,
    required this.score,
    required this.sessions,
    this.badge,
  });
}