import 'dart:math' as math;

import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../services/export_service.dart';
import '../services/achievement_service.dart';
import '../services/certificate_service.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements  = ref.watch(achievementsProvider);
    final certificates  = ref.watch(certificatesProvider);
    final streak        = ref.watch(currentStreakProvider);
    final authState     = ref.watch(authStateProvider);
    final username      = authState.username ?? 'Participant';
    final unlocked      = achievements.where((a) => a.unlocked).length;

    // Most recently unlocked achievement (for the banner)
    final lastUnlocked  = achievements
        .where((a) => a.unlocked)
        .lastOrNull;

    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.white,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Achievements', style: AppTypography.heading(size: 18)),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          top:    AppSpacing.sm,
          bottom: AppSpacing.md + bottomPad,
        ),
        children: [
          // ── Unlock banner (most recent) ──────────────────────────────────
          if (lastUnlocked != null)
            _UnlockBanner(achievement: lastUnlocked),

          // ── Hero progress card ───────────────────────────────────────────
          _HeroProgressCard(
            unlocked:     unlocked,
            total:        achievements.length,
            streak:       streak,
            certificates: certificates,
          ),

          // ── Achievements list ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Achievements',
                    style: AppTypography.heading(size: 16)),
                Text('$unlocked of ${achievements.length} unlocked',
                    style: AppTypography.caption(
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              children: [
                // Unlocked group
                ...achievements
                    .where((a) => a.unlocked)
                    .map((a) => _AchievementRow(achievement: a)),
                if (achievements.any((a) => a.unlocked) &&
                    achievements.any((a) => !a.unlocked))
                  const Padding(
                    padding:
                    EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Divider(
                        color: AppColors.divider,
                        thickness: 1,
                        height: 1),
                  ),
                // Locked group
                ...achievements
                    .where((a) => !a.unlocked)
                    .map((a) => _AchievementRow(achievement: a)),
              ],
            ),
          ),

          // ── Certificates section ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.xl, AppSpacing.md, AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width:      AppSpacing.iconLg,
                      height:     AppSpacing.iconLg,
                      decoration: AppDecorations.iconCircle(
                          bg: AppColors.warning.withValues(alpha: 0.12)),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: AppColors.warning,
                          size:  AppSpacing.iconSm),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Certificates',
                        style: AppTypography.heading(size: 16)),
                  ],
                ),
                Text(
                  '${certificates.where((c) => c.earned).length}'
                      ' of ${certificates.length} earned',
                  style: AppTypography.caption(
                      color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Column(
              children: certificates
                  .map((c) => _CertificateCard(
                cert:     c,
                username: username,
                sessions: ref
                    .watch(sessionSummariesProvider)
                    .valueOrNull
                    ?.where((s) => s.isTraining && s.totalGrade >= 75)
                    .length ?? 0,
              ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// Unlock banner
// ─────────────────────────────────────────────────────────────────────────────

class _UnlockBanner extends StatelessWidget {
  const _UnlockBanner({required this.achievement});
  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:     const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding:    const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xxs),
      decoration: AppDecorations.achievementUnlockBanner(),
      child: Row(
        children: [
          Text(achievement.emoji,
              style: const TextStyle(fontSize: AppSpacing.iconMd)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${achievement.title} unlocked!',
                    style: AppTypography.label(
                        size: 13, color: AppColors.success)),
                const SizedBox(height: AppSpacing.xxs),
                Text(achievement.description,
                    style: AppTypography.caption(
                        color: AppColors.success
                            .withValues(alpha: 0.75))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero progress card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroProgressCard extends StatelessWidget {
  const _HeroProgressCard({
    required this.unlocked,
    required this.total,
    required this.streak,
    required this.certificates,
  });

  final int                      unlocked;
  final int                      total;
  final int                      streak;
  final List<CertificateMilestone> certificates;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : unlocked / total;

    return Container(
      margin:  const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Progress ring
              _ProgressRing(fraction: pct, unlocked: unlocked, total: total),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _headline(pct),
                      style: AppTypography.subheading(size: 14),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _subtitle(pct, unlocked, total),
                      style: AppTypography.caption(
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _StatPill(
                          label: streak > 0 ? '$streak streak' : 'No streak',
                          icon:  streak > 0
                              ? Icons.local_fire_department_rounded
                              : Icons.local_fire_department_outlined,
                          color: streak > 0
                              ? AppColors.warning
                              : AppColors.textDisabled,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Certificate tier chips
          Row(
            children: certificates.map((c) {
              final isNext = !c.earned &&
                  certificates
                      .where((x) => !x.earned)
                      .first
                      .id == c.id;
              return Expanded(
                child: _TierChip(
                  cert:   c,
                  isNext: isNext,
                ),
              );
            }).expand((w) => [w, const SizedBox(width: AppSpacing.xs)]).toList()
              ..removeLast(),
          ),
        ],
      ),
    );
  }

  String _headline(double pct) {
    if (pct == 0) return 'Just getting started';
    if (pct < 0.3) return 'Building momentum';
    if (pct < 0.6) return 'Making good progress';
    if (pct < 1.0) return 'Almost there!';
    return 'All achievements unlocked!';
  }

  String _subtitle(double pct, int u, int t) {
    if (u == 0) return 'Complete your first training session to begin';
    if (u == t) return 'You\'ve unlocked every achievement — impressive!';
    return '$u achievements unlocked — keep training consistently';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress ring (custom painter)
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.fraction,
    required this.unlocked,
    required this.total,
  });

  final double fraction;
  final int    unlocked;
  final int    total;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  64,
      height: 64,
      child:  Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(64, 64),
            painter: _RingPainter(fraction: fraction),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$unlocked',
                style: AppTypography.numericDisplay(
                    size: 18, color: AppColors.textPrimary),
              ),
              Text(
                'of $total',
                style: AppTypography.caption(
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction});
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeW = 5.0;
    final center  = Offset(size.width / 2, size.height / 2);
    final radius  = (size.width - strokeW) / 2;

    // Track
    canvas.drawCircle(
      center, radius,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..color       = AppColors.divider,
    );

    if (fraction <= 0) return;

    // Fill arc
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap   = StrokeCap.round
        ..color       = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tier chip
// ─────────────────────────────────────────────────────────────────────────────

class _TierChip extends StatelessWidget {
  const _TierChip({required this.cert, required this.isNext});
  final CertificateMilestone cert;
  final bool                 isNext;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color textColor;
    final Color border;

    if (cert.earned) {
      bg        = AppColors.successBg;
      textColor = AppColors.success;
      border    = AppColors.success.withValues(alpha: 0.35);
    } else if (isNext) {
      bg        = AppColors.primaryLight;
      textColor = AppColors.primary;
      border    = AppColors.primary.withValues(alpha: 0.25);
    } else {
      bg        = AppColors.screenBgGrey;
      textColor = AppColors.textDisabled;
      border    = AppColors.divider;
    }

    return Container(
      padding:    const EdgeInsets.symmetric(
          vertical: AppSpacing.xs + AppSpacing.xxs,
          horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
        border:       Border.all(color: border),
      ),
      child: Column(
        children: [
          Text(cert.earned ? cert.emoji : '🔒',
              style: TextStyle(
                  fontSize: 13,
                  color: cert.earned || isNext ? null : AppColors.textDisabled)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            cert.title.replaceAll('CPR ', ''),
            style: AppTypography.caption(color: textColor),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            cert.earned ? 'Earned' : isNext ? 'Next' : 'Locked',
            style: AppTypography.caption(color: textColor.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String  label;
  final IconData icon;
  final Color   color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs + 1),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppSpacing.iconXs, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(label,
              style: AppTypography.caption(color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Achievement row
// ─────────────────────────────────────────────────────────────────────────────

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.achievement});
  final Achievement achievement;

  bool get _isStreak =>
      achievement.id == 'streak_3' || achievement.id == 'streak_5';

  @override
  Widget build(BuildContext context) {
    final bool earned = achievement.unlocked;

    return Container(
      margin:  const EdgeInsets.only(bottom: AppSpacing.cardSpacing),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xxs),
      decoration: earned
          ? AppDecorations.achievementItemEarned(isStreak: _isStreak)
          : AppDecorations.achievementItemLocked(),
      child: Row(
        children: [
          // Icon box
          Container(
            width:  40,
            height: 40,
            decoration: BoxDecoration(
              color: earned
                  ? (_isStreak
                  ? AppColors.warning.withValues(alpha: 0.15)
                  : AppColors.success.withValues(alpha: 0.12))
                  : AppColors.screenBgGrey,
              borderRadius:
              BorderRadius.circular(AppSpacing.cardRadiusSm + 2),
            ),
            child: Center(
              child: Text(
                earned ? achievement.emoji : '🔒',
                style: TextStyle(
                  fontSize: earned ? 20 : 16,
                  color: earned ? null : AppColors.textDisabled,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: AppTypography.label(
                      size:  13,
                      color: earned
                          ? AppColors.textPrimary
                          : AppColors.textDisabled),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  achievement.description,
                  style: AppTypography.caption(
                      color: earned
                          ? AppColors.textSecondary
                          : AppColors.textDisabled),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Right indicator
          if (earned)
            Container(
              width:  20,
              height: 20,
              decoration: BoxDecoration(
                color: _isStreak
                    ? AppColors.warningBg
                    : AppColors.successBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isStreak
                      ? AppColors.warning.withValues(alpha: 0.6)
                      : AppColors.success.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check_rounded,
                size:  12,
                color: _isStreak ? AppColors.warning : AppColors.success,
              ),
            )
          else
            Container(
              width:  20,
              height: 20,
              decoration: BoxDecoration(
                color:  AppColors.screenBgGrey,
                shape:  BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  size: 10, color: AppColors.textDisabled),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Certificate card
// ─────────────────────────────────────────────────────────────────────────────

class _CertificateCard extends ConsumerWidget {
  const _CertificateCard({
    required this.cert,
    required this.username,
    required this.sessions,
  });

  final CertificateMilestone cert;
  final String               username;
  final int                  sessions; // qualifying sessions count

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin:     const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: AppDecorations.certificateCardV2(earned: cert.earned),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Medal icon box
                Container(
                  width:  48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: cert.earned
                        ? AppColors.warningBg
                        : AppColors.screenBgGrey,
                    borderRadius:
                    BorderRadius.circular(AppSpacing.cardRadiusSm + 2),
                  ),
                  child: Center(
                    child: Text(
                      cert.earned ? cert.emoji : '🔒',
                      style: TextStyle(
                        fontSize: cert.earned ? 24 : 20,
                        color: cert.earned
                            ? null
                            : AppColors.textDisabled,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cert.title,
                        style: AppTypography.subheading(
                          size:  14,
                          color: cert.earned
                              ? AppColors.textPrimary
                              : AppColors.textDisabled,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        cert.subtitle,
                        style: AppTypography.caption(
                          color: cert.earned
                              ? AppColors.textSecondary
                              : AppColors.textDisabled,
                        ),
                      ),
                      if (cert.earned && cert.earnedDate != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Earned ${_formatDate(cert.earnedDate!)}',
                          style: AppTypography.caption(
                              color: AppColors.warning),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            decoration: cert.earned
                ? AppDecorations.certFooterEarned()
                : AppDecorations.certFooterLocked(),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical:   AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    cert.earned
                        ? 'Certificate ready to download'
                        : _progressHint(),
                    style: AppTypography.caption(
                      color: cert.earned
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                if (cert.earned)
                  GestureDetector(
                    onTap: () async {
                      final ok = await ExportService.exportCertificate(
                        username:  username,
                        milestone: cert,
                      );
                      if (!ok && context.mounted) {
                        UIHelper.showError(
                            context, 'Could not generate certificate.');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical:   AppSpacing.xs,
                      ),
                      decoration: AppDecorations.chip(
                        color: AppColors.warning,
                        bg:    AppColors.warning.withValues(alpha: 0.12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_rounded,
                              size:  12,
                              color: AppColors.warning),
                          const SizedBox(width: AppSpacing.xxs),
                          Text('Download PDF',
                              style: AppTypography.badge(
                                  size:  11,
                                  color: AppColors.warning)),
                        ],
                      ),
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline_rounded,
                          size:  12,
                          color: AppColors.textDisabled),
                      const SizedBox(width: AppSpacing.xxs),
                      Text('Locked',
                          style: AppTypography.caption(
                              color: AppColors.textDisabled)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _progressHint() {
    switch (cert.id) {
      case 'competency':
        return '$sessions of 10 qualifying sessions completed';
      case 'proficiency':
        return '$sessions of 20 qualifying sessions completed';
      case 'excellence':
        return 'Aim for 90%+ in your next session';
      case 'all_round':
        return 'Try a Pediatric or No-Feedback session next';
      default:
        return cert.subtitle;
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}