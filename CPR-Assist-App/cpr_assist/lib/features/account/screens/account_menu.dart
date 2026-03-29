import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../../features/account/screens/profile_editor_screen.dart';
import '../../../features/account/screens/settings_screen.dart';
import '../../../features/account/screens/help_about_screen.dart';
import '../../../features/account/screens/login_screen.dart';
import '../../../providers/session_provider.dart';
import '../../dev/dev_preview_screen.dart';
import '../../training/screens/achievements_screen.dart';
import '../../training/screens/leaderboard_screen.dart';
import '../../training/screens/session_service.dart';
import '../../training/widgets/session_history.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AccountPanel
//
// A custom right-to-left slide-in panel controlled exclusively by tapping the
// account avatar button in UniversalHeader.
//
// ⚠️  Intentionally NOT a Drawer — no swipe gesture, no hamburger icon.
//     Open/close is driven entirely by [AccountPanelController].
//
// Usage (in your main scaffold):
//
//   final _panelController = AccountPanelController();
//
//   Scaffold(
//     appBar: UniversalHeader.forMainScreens(
//       onAccountTap: _panelController.open,
//     ),
//     body: Stack(
//       children: [
//         _pageContent,
//         AccountPanel(controller: _panelController),
//       ],
//     ),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class AccountPanelController extends ChangeNotifier {
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  void open()   { _isOpen = true;  notifyListeners(); }
  void close()  { _isOpen = false; notifyListeners(); }
  void toggle() => _isOpen ? close() : open();
}

// ─────────────────────────────────────────────────────────────────────────────

class AccountPanel extends ConsumerStatefulWidget {
  final AccountPanelController controller;

  const AccountPanel({
    super.key,
    required this.controller,
  });

  @override
  ConsumerState<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends ConsumerState<AccountPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double>   _slideAnim;
  late Animation<double>   _fadeAnim;

  static const Duration _duration      = Duration(milliseconds: 280);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: _duration);
    _slideAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (widget.controller.isOpen) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  void _close() => widget.controller.close();

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _animController.dispose();
    super.dispose();
  }

  // ── Navigation helpers ─────────────────────────────────────────────────────

  Future<void> _push(Widget screen) async {
    _close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await context.push(screen);
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    _close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final confirmed = await AppDialogs.confirmLogout(context);
    if (confirmed != true || !mounted) return;

    await ref.read(authStateProvider.notifier).logout();
    // Panel closes itself, AuthState update rebuilds the panel to show "Log In"
  }

  Future<void> _handleDeleteAccount() async {
    _close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    final confirmed = await AppDialogs.confirmDeleteAccount(context);
    if (confirmed != true || !mounted) return;

    final container = ProviderScope.containerOf(context);
    final service   = container.read(sessionServiceProvider);
    final ok        = await service.deleteAccount();
    if (!mounted) return;

    if (ok) {
      await container.read(authStateProvider.notifier).logout();
      if (mounted) UIHelper.showSuccess(context, 'Account deleted');
    } else {
      if (mounted) UIHelper.showError(context, 'Failed to delete account. Try again.');
    }
  }


  // ── Mode switch ────────────────────────────────────────────────────────────
  //
  // Rule: Emergency mode is always accessible without login.
  //       Training mode requires a logged-in account.
  //       No login prompt is shown during an active CPR session.

  Future<void> _handleModeSwitch() async {
    final currentMode    = ref.read(appModeProvider);
    final isLoggedIn     = ref.read(authStateProvider).isLoggedIn;
    final goingToTraining = currentMode == AppMode.emergency;

    _close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    if (goingToTraining && !isLoggedIn) {
      // Training requires login — show non-blocking prompt then stop.
      // User stays in Emergency mode if they dismiss.
      final shouldLogin = await AppDialogs.promptLogin(context);
      if (shouldLogin != true || !mounted) return;
      await context.push(const LoginScreen());
      return;
    }

    if (!mounted) return;
    final ctx = context;
    final confirmed = goingToTraining
        ? await AppDialogs.confirmSwitchToTraining(ctx)
        : await AppDialogs.confirmSwitchToEmergency(ctx);

    if (confirmed == true && mounted) {
      ref.read(appModeProvider.notifier).setMode(
        goingToTraining ? AppMode.training : AppMode.emergency,
      );
      HapticFeedback.lightImpact();
      // Show checklist only when entering Training — once, as a reminder
      if (goingToTraining && mounted) {
        await Future.delayed(const Duration(milliseconds: 350));
        if (mounted) AppDialogs.showTrainingChecklist(context);
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (_, __) {
        if (_animController.value == 0 && !widget.controller.isOpen) {
          return const SizedBox.shrink();
        }

        return Stack(
          children: [
            // ── Scrim ──────────────────────────────────────────────────────
            FadeTransition(
              opacity: _fadeAnim,
              child: GestureDetector(
                onTap: _close,
                child: const ColoredBox(
                  color: AppColors.overlayDark,
                  child: SizedBox.expand(),
                ),
              ),
            ),

            // ── Panel ──────────────────────────────────────────────────────
            Positioned(
              top:    0,
              bottom: 0,
              right:  0,
              width: context.screenWidth * AppConstants.accountPanelWidthFraction,
              child: FractionalTranslation(
                translation: Offset(_slideAnim.value, 0),
                child: _PanelContent(
                  onClose:         _close,
                  onModeSwitch:    _handleModeSwitch,
                  onLogout:        _handleLogout,
                  onDeleteAccount: _handleDeleteAccount,
                  onPush:          _push,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PanelContent — the actual drawer content
// ─────────────────────────────────────────────────────────────────────────────

class _PanelContent extends ConsumerWidget {
  final VoidCallback                  onClose;
  final VoidCallback                  onModeSwitch;
  final VoidCallback                  onLogout;
  final Future<void> Function(Widget) onPush;
  final VoidCallback onDeleteAccount;

  const _PanelContent({
    required this.onClose,
    required this.onModeSwitch,
    required this.onLogout,
    required this.onPush,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState   = ref.watch(authStateProvider);
    final currentMode = ref.watch(appModeProvider);
    final isCprActive = ref.watch(cprSessionActiveProvider);
    final isLoggedIn  = authState.isLoggedIn;
    final isTraining  = currentMode.isTraining;

    return Container(
        decoration: AppDecorations.sidePanel(),
      child: SafeArea(
        child: Column(
          children: [
            // ── Profile header ─────────────────────────────────────────────
            _ProfileHeader(
              username:   authState.username,
              isLoggedIn: isLoggedIn,
              isTraining: isTraining,
              onEditTap:  isLoggedIn
                  ? () => onPush(const ProfileEditorScreen())
                  : null,
              onClose: onClose,
            ),

            const _PanelDivider(),

            // ── Stats row (logged-in only) ─────────────────────────────────
            if (isLoggedIn) ...[
              const _StatsRow(),
              const _PanelDivider(),
            ],

            // ── Pending sync banner ────────────────────────────────────────
            if (isLoggedIn)
              _SyncPendingRow(onPush: onPush),

            // ── Menu items ─────────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Mode switch
                  _PanelItem(
                    icon:      isTraining
                        ? Icons.emergency_outlined
                        : Icons.school_outlined,
                    iconColor: isTraining ? AppColors.primary : AppColors.warning,
                    label:     isTraining
                        ? 'Switch to Emergency Mode'
                        : 'Switch to Training Mode',
                    labelColor:   isTraining ? AppColors.primary : AppColors.warning,
                    isDisabled:   isCprActive,
                    disabledHint: 'CPR active',
                    onTap: isCprActive ? null : onModeSwitch,
                  ),

                  const _PanelDivider(),

                  // Leaderboard
                  if (isLoggedIn)
                    _PanelItem(
                      icon:  Icons.leaderboard_outlined,
                      label: 'Leaderboard',
                      onTap: () => onPush(
                        LeaderboardScreen(currentUsername: authState.username),
                      ),
                    ),

                  // My Sessions: all logged-in users
                  if (isLoggedIn)
                    _PanelItem(
                      icon:  Icons.history_rounded,
                      label: 'My Sessions',
                      onTap: () => onPush(const SessionHistoryScreen()),
                    ),

                  if (isLoggedIn)
                    _PanelItem(
                      icon:  Icons.emoji_events_outlined,
                      label: 'Achievements',
                      onTap: () => onPush(const AchievementsScreen()),
                    ),

                  _PanelItem(
                    icon:  Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => onPush(const SettingsScreen()),
                  ),

                  _PanelItem(
                    icon:  Icons.help_outline_rounded,
                    label: 'Help & About',
                    onTap: () => onPush(const HelpAboutScreen()),
                  ),

                  const _PanelDivider(),

                  if (isLoggedIn)
                    _PanelItem(
                      icon:        Icons.logout_rounded,
                      iconColor:   AppColors.emergencyRed,
                      label:       'Log Out',
                      labelColor:  AppColors.emergencyRed,
                      onTap:       onLogout,
                      showChevron: false,
                    )
                  else
                    _PanelItem(
                      icon:       Icons.login_rounded,
                      iconColor:  AppColors.primary,
                      label:      'Log In',
                      labelColor: AppColors.primary,
                      onTap: () => onPush(
                        const LoginScreen(),
                      ),
                    ),
                  if (isLoggedIn)
                    _PanelItem(
                      icon:        Icons.delete_forever_rounded,
                      iconColor:   AppColors.emergencyRed,
                      label:       'Delete Account',
                      labelColor:  AppColors.emergencyRed,
                      showChevron: false,
                      onTap:       onDeleteAccount,
                    ),
                  const _PanelDivider(),
                  _PanelItem(
                    icon:       Icons.developer_mode_rounded,
                    iconColor:  AppColors.textDisabled,
                    label:      'UI Preview',
                    labelColor: AppColors.textDisabled,
                    onTap: () => onPush(const DevPreviewScreen()),
                  ),
                ],
              ),
            ),

            // ── Version footer ─────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.only(
                bottom: AppSpacing.md + MediaQuery.paddingOf(context).bottom,
              ),
              child: Text(
                'CPR Assist v1.0.0',
                style: AppTypography.caption(),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProfileHeader
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String?       username;
  final bool          isLoggedIn;
  final bool          isTraining;
  final VoidCallback? onEditTap;
  final VoidCallback  onClose;

  const _ProfileHeader({
    required this.username,
    required this.isLoggedIn,
    required this.isTraining,
    required this.onClose,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = isTraining ? AppColors.warning  : AppColors.primary;
    final modeBg    = isTraining ? AppColors.warningBg : AppColors.primaryLight;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // ── Avatar ────────────────────────────────────────────────────────
          Stack(
            children: [
              Container(
                width:  AppSpacing.avatarLg,
                height: AppSpacing.avatarLg,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  color:  AppColors.primaryLight,
                  border: Border.all(
                    color: AppColors.primaryMid,
                    width: AppSpacing.xxs,
                  ),
                ),
                child: Center(
                  child: isLoggedIn
                      ? Text(
                    username.initials,
                    style: AppTypography.heading(
                      size:  22,
                      color: AppColors.primary,
                    ),
                  )
                      : const Icon(
                    Icons.person_outline,
                    color: AppColors.primary,
                    size:  AppSpacing.iconLg,
                  ),
                ),
              ),
              // Edit badge
              if (onEditTap != null)
                Positioned(
                  bottom: 0,
                  right:  0,
                  child: GestureDetector(
                    onTap: onEditTap,
                    child: Container(
                      width:  AppSpacing.lg,
                      height: AppSpacing.lg,
                      decoration: BoxDecoration(
                        color:  AppColors.primary,
                        shape:  BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surfaceWhite,
                          width: AppSpacing.xxs,
                        ),
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        color: AppColors.textOnDark,
                        size:  AppSpacing.iconXs,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(width: AppSpacing.md),

          // ── Name + mode badge ─────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn ? (username ?? 'User') : 'Not logged in',
                  style: AppTypography.heading(size: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.chipPaddingH,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: AppDecorations.chip(color: modeColor, bg: modeBg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTraining
                            ? Icons.school_outlined
                            : Icons.emergency_outlined,
                        size:  AppSpacing.iconXs,
                        color: modeColor,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        isTraining ? 'Training Mode' : 'Emergency Mode',
                        style: AppTypography.badge(size: 10, color: modeColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Close button ──────────────────────────────────────────────────
          GestureDetector(
            onTap: onClose,
            child: Container(
              width:  AppSpacing.touchTargetMin,
              height: AppSpacing.touchTargetMin,
              decoration: AppDecorations.iconCircle(bg: AppColors.screenBgGrey),
              child: const Icon(
                Icons.close_rounded,
                size:  AppSpacing.iconSm,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatsRow
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);
    final stats     = summaries.whenOrNull(data: (s) => UserStats.fromSessions(s));
    final streak    = ref.watch(currentStreakProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
      ),
      child: Row(
        children: [
          _StatCard(
            icon:  Icons.history_rounded,
            label: 'Sessions',
            value: stats?.sessionCountFormatted ?? '—',
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            icon:  Icons.bar_chart_rounded,
            label: 'Avg Score',
            value: (stats == null || stats.averageGrade == 0)
                ? '—'
                : stats.averageGradeFormatted,
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            icon:  Icons.leaderboard_outlined,
            label: 'Best',
            value: stats != null && stats.sessionCount > 0
                ? '${stats.bestGrade.toStringAsFixed(0)}%'
                : '—',
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            icon:  Icons.local_fire_department_rounded,
            label: 'Streak',
            value: streak > 0 ? '$streak 🔥' : '—',
          ),
        ],
      ),
    );
  }
}

class _SyncPendingRow extends ConsumerWidget {
  final Future<void> Function(Widget) onPush;
  const _SyncPendingRow({required this.onPush});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);
    final pending = summaries.valueOrNull
        ?.where((s) => s.id == null)
        .length ?? 0;

    if (pending == 0) return const SizedBox.shrink();

    return Column(
      children: [
        InkWell(
          onTap: () => ref.invalidate(sessionSummariesProvider),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical:   AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  width:  AppSpacing.touchTargetMin - AppSpacing.sm,
                  height: AppSpacing.touchTargetMin - AppSpacing.sm,
                  decoration: AppDecorations.iconRounded(
                    bg:     AppColors.warning.withValues(alpha: 0.1),
                    radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
                  ),
                  child: const Icon(
                    Icons.cloud_upload_outlined,
                    size:  AppSpacing.iconSm,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: AppSpacing.cardPadding - AppSpacing.xxs),
                Expanded(
                  child: Text(
                    '$pending session${pending == 1 ? '' : 's'} pending sync',
                    style: AppTypography.bodyMedium(
                      size:  14,
                      color: AppColors.warning,
                    ),
                  ),
                ),
                const Icon(
                  Icons.sync_rounded,
                  size:  AppSpacing.iconSm,
                  color: AppColors.warning,
                ),
              ],
            ),
          ),
        ),
        const _PanelDivider(),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical:   AppSpacing.sm + AppSpacing.xs,
          horizontal: AppSpacing.xs,
        ),
        decoration: AppDecorations.tintedCard(),
        child: Column(
          children: [
            Icon(icon, size: AppSpacing.iconSm, color: AppColors.primary),
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: AppTypography.subheading(size: 15)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              style: AppTypography.badge(size: 9, color: AppColors.textDisabled),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PanelItem
// ─────────────────────────────────────────────────────────────────────────────

class _PanelItem extends StatelessWidget {
  final IconData      icon;
  final Color?        iconColor;
  final String        label;
  final Color?        labelColor;
  final bool          isDisabled;
  final String?       disabledHint;
  final bool          showChevron;
  final VoidCallback? onTap;

  const _PanelItem({
    required this.icon,
    this.iconColor,
    required this.label,
    this.labelColor,
    this.isDisabled   = false,
    this.disabledHint,
    this.showChevron  = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor  = iconColor  ?? AppColors.textSecondary;
    final effectiveLabelColor = labelColor ?? AppColors.textPrimary;

    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical:   AppSpacing.cardPadding - AppSpacing.xxs,
          ),
          child: Row(
            children: [
              // Icon box
              Container(
                width:  AppSpacing.touchTargetMin - AppSpacing.sm, // 36
                height: AppSpacing.touchTargetMin - AppSpacing.sm,
                decoration: AppDecorations.iconRounded(
                  bg:     effectiveIconColor.withValues(alpha: 0.1),
                  radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
                ),
                child: Icon(
                  icon,
                  size:  AppSpacing.iconSm,
                  color: effectiveIconColor,
                ),
              ),
              const SizedBox(width: AppSpacing.cardPadding - AppSpacing.xxs),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium(
                    size:  15,
                    color: effectiveLabelColor,
                  ),
                ),
              ),
              // Disabled hint badge
              if (isDisabled && disabledHint != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: AppDecorations.chip(
                    color: AppColors.warning,
                    bg:    AppColors.warningBg,
                  ),
                  child: Text(
                    disabledHint!,
                    style: AppTypography.badge(size: 9, color: AppColors.warning),
                  ),
                )
              else if (showChevron)
                const Icon(
                  Icons.chevron_right_rounded,
                  size:  AppSpacing.iconSm,
                  color: AppColors.textDisabled,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PanelDivider
// ─────────────────────────────────────────────────────────────────────────────

class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height:    AppSpacing.dividerThickness,
      thickness: AppSpacing.dividerThickness,
      color:     AppColors.divider,
      indent:    AppSpacing.md,
      endIndent: AppSpacing.md,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AccountAvatarButton
//
// Reads auth state directly — no onTap param required.
// The header passes the panel open callback separately.
// ─────────────────────────────────────────────────────────────────────────────

class AccountAvatarButton extends ConsumerWidget {
  const AccountAvatarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return Container(
      width:  AppSpacing.touchTargetMin - AppSpacing.sm, // 36
      height: AppSpacing.touchTargetMin - AppSpacing.sm,
      decoration: AppDecorations.iconCircle(bg: AppColors.primaryMid),
      child: Center(
        child: authState.isLoggedIn
            ? Text(
          authState.username.initials,
          style: AppTypography.label(size: 13, color: AppColors.primary)
              .copyWith(
            fontWeight:    FontWeight.w800,
            letterSpacing: 0.3,
          ),
        )
            : const Icon(
          Icons.person_outline,
          color: AppColors.primary,
          size:  AppSpacing.iconSm + AppSpacing.xxs,
        ),
      ),
    );
  }
}