import 'package:flutter/material.dart';
import '../widgets/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD SCREEN
// ─────────────────────────────────────────────────────────────────────────────
// Structure:
//   - Tab bar: Global | Friends | Personal Best
//   - Each tab shows a ranked list of users / sessions
//   - Podium view for top 3 on Global tab
//   - "Your rank" sticky card at the bottom
//
// All data here is placeholder — wire up to your backend when ready.
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

  // ── Placeholder data ───────────────────────────────────────────────────────
  final List<_LeaderEntry> _globalEntries = [
    _LeaderEntry(rank: 1, username: 'Maria K.', score: 98.4, sessions: 42, badge: '🥇'),
    _LeaderEntry(rank: 2, username: 'Nikos P.', score: 96.1, sessions: 38, badge: '🥈'),
    _LeaderEntry(rank: 3, username: 'Elena T.', score: 94.7, sessions: 55, badge: '🥉'),
    _LeaderEntry(rank: 4, username: 'Giorgos M.', score: 92.3, sessions: 29),
    _LeaderEntry(rank: 5, username: 'Sofia D.', score: 91.0, sessions: 33),
    _LeaderEntry(rank: 6, username: 'Alexis B.', score: 89.5, sessions: 21),
    _LeaderEntry(rank: 7, username: 'Katerina V.', score: 87.2, sessions: 18),
    _LeaderEntry(rank: 8, username: 'Petros N.', score: 85.9, sessions: 44),
    _LeaderEntry(rank: 9, username: 'Anna L.', score: 84.1, sessions: 12),
    _LeaderEntry(rank: 10, username: 'Kostas F.', score: 82.7, sessions: 27),
  ];

  final List<_LeaderEntry> _friendEntries = [
    _LeaderEntry(rank: 1, username: 'Nikos P.', score: 96.1, sessions: 38, badge: '🥇'),
    _LeaderEntry(rank: 2, username: 'Sofia D.', score: 91.0, sessions: 33, badge: '🥈'),
    _LeaderEntry(rank: 3, username: 'Alexis B.', score: 89.5, sessions: 21, badge: '🥉'),
  ];

  final List<_PersonalBestEntry> _personalBest = [
    _PersonalBestEntry(date: '8 Mar 2026',  score: 91.2, rate: 108, depth: 5.4, duration: '3:12'),
    _PersonalBestEntry(date: '5 Mar 2026',  score: 88.7, rate: 112, depth: 5.1, duration: '2:55'),
    _PersonalBestEntry(date: '1 Mar 2026',  score: 85.3, rate: 104, depth: 5.6, duration: '3:40'),
    _PersonalBestEntry(date: '25 Feb 2026', score: 80.1, rate: 99,  depth: 4.8, duration: '2:20'),
    _PersonalBestEntry(date: '20 Feb 2026', score: 76.4, rate: 118, depth: 5.0, duration: '2:05'),
  ];

  // Current user's rank on global leaderboard (placeholder)
  final _myEntry = _LeaderEntry(rank: 24, username: 'You', score: 78.4, sessions: 7);

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
      backgroundColor: kBgGrey,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: kTextDark,
        elevation: 0,
        toolbarHeight: 52,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Leaderboard', style: kHeading(size: 18)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(
            children: [
              Container(height: 1, color: kDivider),
              TabBar(
                controller: _tabController,
                labelColor: kPrimary,
                unselectedLabelColor: kTextLight,
                indicatorColor: kPrimary,
                indicatorWeight: 2.5,
                labelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
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
          _GlobalTab(entries: _globalEntries, myEntry: _myEntry),
          _FriendsTab(entries: _friendEntries),
          _PersonalTab(entries: _personalBest),
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
          padding: const EdgeInsets.only(bottom: 80),
          children: [

            // ── Podium ───────────────────────────────────────────────────────
            _Podium(entries: top3),

            // ── Rest of list ─────────────────────────────────────────────────
            if (rest.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Text('RANKINGS', style: kLabel(size: 11)),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: rest.asMap().entries.map((e) {
                    final isLast = e.key == rest.length - 1;
                    return Column(
                      children: [
                        _LeaderRow(entry: e.value),
                        if (!isLast)
                          const Divider(
                              height: 1,
                              color: kDivider,
                              indent: 60,
                              endIndent: 16),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),

        // ── Sticky "your rank" footer ─────────────────────────────────────
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A4F9E), Color(0xFF2563C0)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place
          Expanded(child: _PodiumSpot(entry: entries[1], height: 80)),
          // 1st place
          Expanded(child: _PodiumSpot(entry: entries[0], height: 106, isFirst: true)),
          // 3rd place
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

  const _PodiumSpot(
      {required this.entry, required this.height, this.isFirst = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFirst)
          const Text('👑', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        // Avatar
        Container(
          width: isFirst ? 54 : 44,
          height: isFirst ? 54 : 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.15),
            border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: isFirst ? 2.5 : 2),
          ),
          child: Center(
            child: Text(
              getInitials(entry.username),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: isFirst ? 18 : 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.username,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: isFirst ? 13 : 11,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 2),
        Text(
          '${entry.score.toStringAsFixed(1)}%',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: isFirst ? 13 : 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isFirst ? 0.2 : 0.1),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Center(
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w800,
                fontSize: isFirst ? 20 : 16,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '#${entry.rank}',
              style: kLabel(size: 12, color: kTextLight),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          // Avatar
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
                color: kPrimaryLight, shape: BoxShape.circle),
            child: Center(
              child: Text(
                getInitials(entry.username),
                style: const TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name + sessions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.username,
                    style: kBody(size: 14, color: kTextDark)
                        .copyWith(fontWeight: FontWeight.w600)),
                Text('${entry.sessions} sessions',
                    style: kLabel(size: 11, color: kTextLight)),
              ],
            ),
          ),
          // Score
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${entry.score.toStringAsFixed(1)}%',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kPrimary),
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: kDivider)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -3)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kPrimaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '#${entry.rank}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your rank',
                    style: kLabel(size: 11, color: kTextLight)),
                Text('${entry.sessions} sessions · ${entry.score.toStringAsFixed(1)}% avg',
                    style: kBody(size: 13, color: kTextDark)
                        .copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text('Top 24%',
              style:
              kLabel(size: 12, color: kSuccess).copyWith(fontSize: 12)),
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
            const Icon(Icons.group_outlined, size: 56, color: kTextLight),
            const SizedBox(height: 16),
            Text('No friends yet', style: kHeading(size: 16, color: kTextLight)),
            const SizedBox(height: 6),
            Text('Add friends to compare scores',
                style: kBody(size: 13, color: kTextLight)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: entries.asMap().entries.map((e) {
              final isLast = e.key == entries.length - 1;
              return Column(
                children: [
                  _LeaderRow(entry: e.value),
                  if (!isLast)
                    const Divider(height: 1, color: kDivider, indent: 60),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Add friends coming soon')),
            );
          },
          icon: const Icon(Icons.person_add_outlined, size: 18),
          label: const Text('Add Friends'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kPrimary,
            side: const BorderSide(color: kPrimaryMid, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PERSONAL BEST TAB
// ─────────────────────────────────────────────────────────────────────────────

class _PersonalTab extends StatelessWidget {
  final List<_PersonalBestEntry> entries;
  const _PersonalTab({required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Best session highlight
        if (entries.isNotEmpty) _BestSessionCard(entry: entries.first),
        const SizedBox(height: 12),

        // History list
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('SESSION HISTORY', style: kLabel(size: 11)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            children: entries.asMap().entries.map((e) {
              final isLast = e.key == entries.length - 1;
              return Column(
                children: [
                  _SessionRow(entry: e.value, rank: e.key + 1),
                  if (!isLast)
                    const Divider(
                        height: 1, color: kDivider, indent: 16, endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _BestSessionCard extends StatelessWidget {
  final _PersonalBestEntry entry;
  const _BestSessionCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A4F9E), Color(0xFF2563C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text('Personal Best',
                  style: kLabel(size: 12, color: Colors.white70)),
              const Spacer(),
              Text(entry.date,
                  style: kLabel(size: 11, color: Colors.white54)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${entry.score.toStringAsFixed(1)}%',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: -1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill(label: '${entry.rate} bpm'),
              const SizedBox(width: 8),
              _StatPill(label: '${entry.depth} cm'),
              const SizedBox(width: 8),
              _StatPill(label: entry.duration),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  const _StatPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final _PersonalBestEntry entry;
  final int rank;
  const _SessionRow({required this.entry, required this.rank});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Text('#$rank', style: kLabel(size: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.date,
                    style: kBody(size: 13, color: kTextDark)
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(
                    '${entry.rate} bpm · ${entry.depth} cm · ${entry.duration}',
                    style: kLabel(size: 11, color: kTextLight)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: kPrimaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${entry.score.toStringAsFixed(1)}%',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODELS (placeholder)
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

class _PersonalBestEntry {
  final String date;
  final double score;
  final int rate;
  final double depth;
  final String duration;

  const _PersonalBestEntry({
    required this.date,
    required this.score,
    required this.rate,
    required this.depth,
    required this.duration,
  });
}