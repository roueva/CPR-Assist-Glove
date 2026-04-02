import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../services/export_service.dart';

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final achievements = ref.watch(achievementsProvider);
    final streak = ref.watch(currentStreakProvider);
    ref.watch(authStateProvider);
    final unlocked     = achievements.where((a) => a.unlocked).length;

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.headerBg,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('Achievements', style: AppTypography.heading(size: 18)),
      ),
        body: ListView(
          padding: EdgeInsets.only(
            bottom: AppSpacing.md + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // ── Progress header ─────────────────────────────────────────────────
            Container(
              margin:     const EdgeInsets.all(AppSpacing.md),
              padding:    const EdgeInsets.all(AppSpacing.lg),
              decoration: AppDecorations.primaryDarkCard(),
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 32)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$unlocked / ${achievements.length} unlocked',
                            style: AppTypography.subheading(
                                color: AppColors.textOnDark)),
                        const SizedBox(height: AppSpacing.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.xxs),
                          child: LinearProgressIndicator(
                            value: achievements.isEmpty
                                ? 0
                                : unlocked / achievements.length,
                            backgroundColor:
                            AppColors.textOnDark.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.cprGreen),
                            minHeight: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        streak > 0 ? '$streak 🔥' : '—',
                        style: AppTypography.numericDisplay(
                            size: 22, color: AppColors.textOnDark),
                      ),
                      Text(
                        'streak',
                        style: AppTypography.label(
                            size: 10,
                            color: AppColors.textOnDark.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Achievement grid ─────────────────────────────────────────────────
            GridView.builder(
              shrinkWrap:  true,
              physics:     const NeverScrollableScrollPhysics(),
              padding:     const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:   2,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing:  AppSpacing.sm,
                childAspectRatio: 0.95,
              ),
              itemCount: achievements.length,
              itemBuilder: (context, i) {
                final a        = achievements[i];
                return Container(
                  padding:    const EdgeInsets.all(AppSpacing.md),
                    decoration: AppDecorations.achievementCard(unlocked: a.unlocked),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(a.unlocked ? a.emoji : '🔒',
                          style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: AppSpacing.xs),
                      Text(a.title,
                          style:     AppTypography.label(size: 12, color: a.unlocked ? AppColors.primary : AppColors.textDisabled),
                          textAlign: TextAlign.center,
                          maxLines:  2,
                          overflow:  TextOverflow.ellipsis),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(a.description,
                          style:     AppTypography.caption(color: a.unlocked ? AppColors.textSecondary : AppColors.textDisabled),
                          textAlign: TextAlign.center,
                          maxLines:  2,
                          overflow:  TextOverflow.ellipsis),
                    ],
                  ),
                );
              },
            ),

            // ── Certificates section ─────────────────────────────────────────────
            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width:  AppSpacing.iconLg,
                    height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconCircle(
                        bg: AppColors.warning.withValues(alpha: 0.12)),
                    child: const Icon(Icons.workspace_premium_rounded,
                        color: AppColors.warning, size: AppSpacing.iconSm),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Certificates', style: AppTypography.heading(size: 18)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CertificatesList(),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
    );
  }
}

class _CertificatesList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certificates = ref.watch(certificatesProvider);
    final authState    = ref.watch(authStateProvider);
    final username     = authState.username ?? 'Participant';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: certificates.map((cert) {
          return Container(
            margin:     const EdgeInsets.only(bottom: AppSpacing.sm),
            padding:    const EdgeInsets.all(AppSpacing.md),
            decoration: AppDecorations.certificateCard(earned: cert.earned),
            child: Row(
              children: [
                Text(
                  cert.earned ? cert.emoji : '🔒',
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: AppSpacing.md),
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
                if (cert.earned) ...[
                  const SizedBox(width: AppSpacing.sm),
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
                              size: 12, color: AppColors.warning),
                          const SizedBox(width: AppSpacing.xxs),
                          Text('PDF',
                              style: AppTypography.badge(
                                  size: 11, color: AppColors.warning)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}