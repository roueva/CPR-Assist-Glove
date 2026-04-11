import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import 'package:flutter_svg/svg.dart';

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
import '../../training/services/session_local_storage.dart';
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



  // ── Mode switch ────────────────────────────────────────────────────────────
  //
  // Rule: Emergency mode is always accessible without login.
  //       Training mode requires a logged-in account.
  //       No login prompt is shown during an active CPR session.

  Future<void> _handleModeSwitch() async {
    final currentMode     = ref.read(appModeProvider);
    final isLoggedIn      = ref.read(authStateProvider).isLoggedIn;
    final goingToTraining = !currentMode.isTraining;

    if (goingToTraining && !isLoggedIn) {
      if (!mounted) return;
      final shouldLogin = await AppDialogs.promptLogin(context);
      if (shouldLogin != true || !mounted) return;
      _close();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (mounted) await context.push(const LoginScreen());
      return;
    }

    // Switch immediately — no confirmation needed
    ref.read(appModeProvider.notifier).setMode(
      goingToTraining ? AppMode.training : AppMode.emergency,
    );
    HapticFeedback.lightImpact();

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
                  onModeSwitch: _handleModeSwitch,
                  onLogout:     _handleLogout,
                  onPush:       _push,
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
  final VoidCallback                  onModeSwitch;
  final VoidCallback                  onLogout;
  final Future<void> Function(Widget) onPush;

  const _PanelContent({
    required this.onModeSwitch,
    required this.onLogout,
    required this.onPush,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState  = ref.watch(authStateProvider);
    final currentMode = ref.watch(appModeProvider);
    final isLoggedIn  = authState.isLoggedIn;
    final isTraining  = currentMode.isTraining;

    return Container(
      decoration: AppDecorations.sidePanel(),
      child: SafeArea(
        child: Column(
          children: [
            // ── Profile header — tinted bg to separate from nav bar ────────
          _ProfileHeader(
          username:      authState.username,
          isLoggedIn:    isLoggedIn,
          isTraining:    isTraining,
          onEditTap:     isLoggedIn
              ? () => onPush(const ProfileEditorScreen())
              : () => onPush(const LoginScreen()),
          onModeSwitchTap: onModeSwitch,
        ),

            // ── Stats row (logged-in only, no surrounding dividers) ────────
            if (isLoggedIn) ...[
              const SizedBox(height: AppSpacing.xs),
              _StatsRow(onPush: onPush, username: authState.username),
            ],

            // ── Pending sync banner ────────────────────────────────────────
            if (isLoggedIn)
              const _SyncPendingRow(),

            // ── Menu items ─────────────────────────────────────────────────
            const _PanelDivider(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (isLoggedIn) ...[
                    _PanelItem(
                      icon:  Icons.leaderboard_outlined,
                      label: 'Leaderboard',
                      onTap: () => onPush(
                          LeaderboardScreen(currentUsername: authState.username)),
                    ),
                    _PanelItem(
                      icon:  Icons.history_rounded,
                      label: 'My Sessions',
                      onTap: () => onPush(const SessionHistoryScreen()),
                    ),
                    _PanelItem(
                      icon:  Icons.emoji_events_outlined,
                      label: 'Achievements',
                      onTap: () => onPush(const AchievementsScreen()),
                    ),
                    const _PanelDivider(),
                  ],
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
                      onTap:      () => onPush(const LoginScreen()),
                    ),
                  _PanelItem(
                    icon:       Icons.developer_mode_rounded,
                    iconColor:  AppColors.textDisabled,
                    label:      'UI Preview',
                    labelColor: AppColors.textDisabled,
                    onTap:      () => onPush(const DevPreviewScreen()),
                  ),
                ],
              ),
            ),

            // ── Version footer ─────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.only(
                bottom: AppSpacing.sm + MediaQuery.paddingOf(context).bottom,
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
  final VoidCallback? onModeSwitchTap;

  const _ProfileHeader({
    required this.username,
    required this.isLoggedIn,
    required this.isTraining,
    this.onEditTap,
    this.onModeSwitchTap,
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = isTraining ? AppColors.warning : AppColors.primary;
    final modeLabel = isTraining ? 'Training' : 'Emergency';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md,
      ),
      child: Row(
        children: [
          // ── Avatar ──────────────────────────────────────────────────────
          GestureDetector(
            onTap: onEditTap,
            child: Stack(
              children: [
                Container(
                  width:  AppSpacing.avatarLg,
                  height: AppSpacing.avatarLg,
                  decoration: AppDecorations.avatarCircle3d(),
                  child: Center(
                    child: isLoggedIn
                        ? Text(
                      username.initials,
                      style: AppTypography.heading(
                          size: 22, color: AppColors.primary),
                    )
                        : const Icon(Icons.person_outline,
                        color: AppColors.primary, size: AppSpacing.iconLg),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // ── Name + username ─────────────────────────────────────────────
          Expanded(
            child: GestureDetector(
              onTap: onEditTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoggedIn ? (username ?? 'User') : 'Guest',
                    style: AppTypography.heading(
                      size: (username != null && username!.length > 14) ? 13 : 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (isLoggedIn && username != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '@${username!.toLowerCase().replaceAll(' ', '_')}',
                      style: AppTypography.body(
                          size: 12, color: AppColors.textDisabled),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else if (!isLoggedIn) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text('Tap to log in',
                        style: AppTypography.body(
                            size: 12, color: AppColors.textDisabled)),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // ── Mode switch button ───────────────────────────────────────────
          // Icon + label + swap arrow — clearly tappable, no border/fill
      GestureDetector(
        onTap: onModeSwitchTap,
        child: SizedBox(
          width: AppSpacing.touchTargetMin + AppSpacing.md, // 52px — fits "Emergency"
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Fixed-size box so icon never shifts position
                SizedBox(
                  width:  AppSpacing.iconMd + AppSpacing.md,  // 40px
                  height: AppSpacing.iconMd + AppSpacing.md,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Center(
                          child: ModeIcon(
                            isTraining: isTraining,
                            size:  AppSpacing.iconMd,
                            color: modeColor,
                          ),
                        ),
                      ),
                      // Swap arrow in white circle — bottom-right
                      Positioned(
                        bottom: 0,
                        right:  0,
                        child: Container(
                          width:  AppSpacing.md,
                          height: AppSpacing.md,
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceWhite,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.swap_horiz_rounded,
                            size:  AppSpacing.iconXs,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  modeLabel,
                  style: AppTypography.badge(size: 9, color: AppColors.textDisabled),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
  final Future<void> Function(Widget) onPush;
  final String? username;

  const _StatsRow({required this.onPush, required this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);
    final stats     = summaries.whenOrNull(data: (s) => UserStats.fromSessions(s));

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md,
      ),
      child: Row(
        children: [
          _StatCard(
            icon:  Icons.history_rounded,
            label: 'Sessions',
            value: stats?.sessionCountFormatted ?? '—',
            onTap: () => onPush(const SessionHistoryScreen()),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            icon:  Icons.bar_chart_rounded,
            label: 'Avg Score',
            value: (stats == null || stats.averageGrade == 0)
                ? '—'
                : stats.averageGradeFormatted,
            onTap: () => onPush(LeaderboardScreen(currentUsername: username)),
          ),
          const SizedBox(width: AppSpacing.sm),
          _StatCard(
            icon:      Icons.local_fire_department_rounded,
            iconColor: AppColors.primary,
            label:     'Best',
            value:     stats != null && stats.sessionCount > 0
                ? '${stats.bestGrade.toStringAsFixed(0)}%'
                : '—',
              onTap: () => onPush(const SessionHistoryScreen()), // TODO: open best session directly
          ),
        ],
      ),
    );
  }
}

class _SyncPendingRow extends ConsumerStatefulWidget {
  const _SyncPendingRow();

  @override
  ConsumerState<_SyncPendingRow> createState() => _SyncPendingRowState();
}

class _SyncPendingRowState extends ConsumerState<_SyncPendingRow> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    final container = ProviderScope.containerOf(context);
    final service   = container.read(sessionServiceProvider);
    final locals    = await SessionLocalStorage.loadAll();
    final pending   = locals.where((d) => !d.syncedToBackend).toList();

    int synced = 0;
    for (final detail in pending) {
      final ok = await service.saveDetail(detail);
      final savedId = await service.saveDetail(detail);
      if (savedId != null) {
        await SessionLocalStorage.markSynced(detail);
        synced++;
      }
    }

    if (!mounted) return;
    setState(() => _syncing = false);

    if (synced > 0) {
      ref.invalidate(sessionSummariesProvider);
      UIHelper.showSuccess(context, '$synced session${synced == 1 ? '' : 's'} synced');
    } else {
      UIHelper.showWarning(context, 'Sync failed. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaries = ref.watch(sessionSummariesProvider);
    final pending   = summaries.valueOrNull
        ?.where((s) => s.id == null)
        .length ?? 0;

    if (pending == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.xs,
        ),
        decoration: AppDecorations.warningCard(),
        child: Row(
          children: [
            _syncing
                ? const SizedBox(
              width:  AppSpacing.iconSm,
              height: AppSpacing.iconSm,
              child:  CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
              ),
            )
                : const Icon(
              Icons.cloud_upload_outlined,
              size:  AppSpacing.iconSm,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '$pending unsynced session${pending == 1 ? '' : 's'}',
                style: AppTypography.badge(size: 11, color: AppColors.warning),
              ),
            ),
            GestureDetector(
              onTap: _syncing ? null : _syncNow,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical:   AppSpacing.xxs + AppSpacing.xxs,
                ),
                decoration: AppDecorations.chip(
                  color: AppColors.warning,
                  bg:    AppColors.warning.withValues(alpha: 0.15),
                ),
                child: Text(
                  _syncing ? '...' : 'Sync',
                  style: AppTypography.badge(size: 10, color: AppColors.warning),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData      icon;
  final Color?        iconColor;
  final String        label;
  final String        value;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical:   AppSpacing.sm + AppSpacing.xs,
            horizontal: AppSpacing.xs,
          ),
          decoration: AppDecorations.tintedCard(),
          child: Column(
            children: [
              Icon(icon, size: AppSpacing.iconSm,
                  color: iconColor ?? AppColors.primary),
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
    this.showChevron  = true,
    this.onTap,
    this.isDisabled   = false,
    this.disabledHint,
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
                width:  AppSpacing.iconBoxSize,
                height: AppSpacing.iconBoxSize,
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
    final authState  = ref.watch(authStateProvider);
    final isTraining = ref.watch(appModeProvider).isTraining;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width:  AppSpacing.iconBoxSize,
          height: AppSpacing.iconBoxSize,
          decoration: AppDecorations.iconCircle(bg: AppColors.primaryMid),
          child: Center(
            child: authState.isLoggedIn
                ? Text(
              authState.username.initials,
              style: AppTypography.label(size: 13, color: AppColors.primary)
                  .copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.3),
            )
                : const Icon(Icons.person_outline,
                color: AppColors.primary,
                size:  AppSpacing.iconSm + AppSpacing.xxs),
          ),
        ),
        // Mode badge — bottom-right corner
        Positioned(
          bottom: -AppSpacing.xxs,
          right:  -AppSpacing.xxs,
          child: Container(
            width:  AppSpacing.md + AppSpacing.xxs,  // 18px
            height: AppSpacing.md + AppSpacing.xxs,
            decoration: BoxDecoration(
              color:  isTraining ? AppColors.warningBg : AppColors.primaryLight,
              shape:  BoxShape.circle,
              border: Border.all(color: AppColors.headerBg, width: AppSpacing.xxs),
            ),
            child: ModeIcon(
              isTraining: isTraining,
              size:  1,
              color: isTraining ? AppColors.warning : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ModeIcon
//
// Reusable SVG icon for Emergency / Training mode.
// Uses assets/icons/emergency.svg and assets/icons/training.svg.
// Color is applied via colorFilter to respect the design token system.
// ─────────────────────────────────────────────────────────────────────────────

class ModeIcon extends StatelessWidget {
  final bool   isTraining;
  final double size;
  final Color  color;

  const ModeIcon({
    super.key,
    required this.isTraining,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      isTraining
          ? 'assets/icons/training.svg'
          : 'assets/icons/emergency.svg',
      width:       size,
      height:      size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}