import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../training/services/certificate_service.dart';
import 'forgot_password_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProfileEditorScreen — "My Account"
//
// Class name kept as ProfileEditorScreen so all existing
// context.push(const ProfileEditorScreen()) calls continue to work.
// ─────────────────────────────────────────────────────────────────────────────

class ProfileEditorScreen extends ConsumerWidget {
  const ProfileEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth     = ref.watch(authStateProvider);
    final sessions = ref.watch(sessionSummariesProvider).valueOrNull ?? [];

    // Highest earned certificate title — computed client-side
    final earned  = CertificateService.compute(sessions)
        .where((c) => c.earned)
        .toList();
    final topCert = earned.isNotEmpty ? earned.last : null;

    // Member since — ISO date stored in prefs after login
    String? memberSince;
    if (auth.createdAt != null) {
      try {
        memberSince = DateFormat('MMMM yyyy')
            .format(DateTime.parse(auth.createdAt!).toLocal());
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: _buildAppBar(context),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [

          // ── Identity ─────────────────────────────────────────────────────
          _IdentityHeader(
            username:    auth.username,
            email:       auth.email,
            topCert:     topCert,
            memberSince: memberSince,
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Actions ──────────────────────────────────────────────────────
          _AccountCard(children: [
            _AccountRow(
              icon:  Icons.lock_outline_rounded,
              label: 'Change Password',
              onTap: () => context.push(const ForgotPasswordScreen()),
            ),
            const _Divider(),
            _AccountRow(
              icon:       Icons.person_remove_outlined,
              iconColor:  AppColors.emergencyRed,
              label:      'Delete Account',
              subtitle:   'Permanently removes your account and all data',
              labelColor: AppColors.emergencyRed,
              onTap:      () => _confirmDeleteAccount(context, ref),
            ),
          ]),

        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor:           AppColors.surfaceWhite,
      foregroundColor:           AppColors.textPrimary,
      elevation:                 0,
      scrolledUnderElevation:    0,
      toolbarHeight:             AppSpacing.headerHeight,
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: AppColors.primary,
        ),
        onPressed: () => context.pop(),
      ),
      title: Text('My Account', style: AppTypography.heading(size: 18)),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
        child: Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(
      BuildContext context, WidgetRef ref) async {
    final confirmed = await AppDialogs.confirmDeleteAccount(context);
    if (confirmed != true || !context.mounted) return;
    final container = ProviderScope.containerOf(context);
    final service   = container.read(sessionServiceProvider);
    final ok        = await service.deleteAccount();
    if (!context.mounted) return;
    if (ok) {
      await container.read(authStateProvider.notifier).logout();
      if (context.mounted) UIHelper.showSuccess(context, 'Account deleted');
    } else {
      UIHelper.showError(context, 'Failed to delete account. Try again.');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _IdentityHeader
// ─────────────────────────────────────────────────────────────────────────────

class _IdentityHeader extends StatelessWidget {
  final String?               username;
  final String?               email;
  final CertificateMilestone? topCert;
  final String?               memberSince;

  const _IdentityHeader({
    required this.username,
    required this.email,
    required this.topCert,
    required this.memberSince,
  });

  @override
  Widget build(BuildContext context) {
    final name = username ?? 'User';

    return Column(
      children: [

        const SizedBox(height: AppSpacing.xl),

        // Avatar
        Container(
          width:  92,
          height: 92,
          decoration: AppDecorations.avatarCircle3d(),
          child: Center(
            child: Text(
              name.initials,
              style: AppTypography.heading(size: 34, color: AppColors.primary),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Name
        Text(
          name,
          style: AppTypography.heading(size: 20),
          textAlign: TextAlign.center,
          overflow:  TextOverflow.ellipsis,
          maxLines:  1,
        ),

        // Email
        if (email != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            email!,
            style: AppTypography.body(size: 13, color: AppColors.textDisabled),
            textAlign: TextAlign.center,
            overflow:  TextOverflow.ellipsis,
            maxLines:  1,
          ),
        ],

        // Certificate title chip
        if (topCert != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + AppSpacing.xs,
              vertical:   AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color:        AppColors.primaryLight,
              borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
              border:       Border.all(
                color: AppColors.primaryMid,
                width: AppSpacing.dividerThickness,
              ),
            ),
            child: Text(
              '${topCert!.emoji}  ${topCert!.title}',
              style: AppTypography.label(size: 12, color: AppColors.primary),
            ),
          ),
        ],

        // Member since
        if (memberSince != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Member since $memberSince',
            style: AppTypography.caption(),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: AppSpacing.xl),

        // Divider separating identity from actions
        const Divider(
          height:    AppSpacing.dividerThickness,
          thickness: AppSpacing.dividerThickness,
          color:     AppColors.divider,
        ),

        const SizedBox(height: AppSpacing.lg),

      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AccountCard — borderless on white, relies on subtle shadow
// ─────────────────────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final List<Widget> children;
  const _AccountCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border:       Border.all(color: AppColors.divider),
      ),
      child: Column(children: children),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Divider
// ─────────────────────────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height:    AppSpacing.dividerThickness,
      thickness: AppSpacing.dividerThickness,
      color:     AppColors.divider,
      indent:    AppSpacing.iconBoxSize + AppSpacing.md + AppSpacing.sm,
      endIndent: 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AccountRow
// ─────────────────────────────────────────────────────────────────────────────

class _AccountRow extends StatelessWidget {
  final IconData     icon;
  final Color?       iconColor;
  final String       label;
  final Color?       labelColor;
  final String?      subtitle;
  final VoidCallback onTap;

  const _AccountRow({
    required this.icon,
    this.iconColor,
    required this.label,
    this.labelColor,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;

    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.cardPadding - AppSpacing.xxs,
        ),
        child: Row(
          children: [

            Container(
              width:  AppSpacing.iconBoxSize,
              height: AppSpacing.iconBoxSize,
              decoration: AppDecorations.iconRounded(
                bg:     color.withValues(alpha: 0.1),
                radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
              ),
              child: Icon(icon, color: color, size: AppSpacing.iconSm),
            ),

            const SizedBox(width: AppSpacing.sm),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.bodyMedium(
                      size:  14,
                      color: labelColor ?? AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle!, style: AppTypography.caption()),
                  ],
                ],
              ),
            ),

            const Icon(
              Icons.chevron_right_rounded,
              size:  AppSpacing.iconSm,
              color: AppColors.textDisabled,
            ),

          ],
        ),
      ),
    );
  }
}