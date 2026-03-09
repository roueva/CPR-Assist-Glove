import 'package:cpr_assist/widgets/profile_editor_screen.dart';
import 'package:cpr_assist/widgets/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../screens/login_screen.dart';
import '../services/decrypted_data.dart';
import '../widgets/app_theme.dart';
import 'app_dialogs.dart';
import 'help_about_screen.dart';
import 'leaderboard_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOW TO USE
// ─────────────────────────────────────────────────────────────────────────────
//
// 1. In MainNavigationScreen, wrap your Scaffold with a GlobalKey:
//
//    final _drawerKey = GlobalKey<ScaffoldState>();
//
//    Scaffold(
//      key: _drawerKey,
//      endDrawer: AccountDrawer(decryptedDataHandler: _decryptedDataHandler),
//      appBar: UniversalHeader.forMainScreens(
//        decryptedDataHandler: _decryptedDataHandler,
//        currentIndex: _currentIndex,
//        onAccountTap: () => _drawerKey.currentState?.openEndDrawer(),
//      ),
//      ...
//    )
//
// 2. In UniversalHeader, pass onAccountTap to the AccountAvatarButton
//    and call it onTap instead of opening a bottom sheet.
//
// ─────────────────────────────────────────────────────────────────────────────


// ─────────────────────────────────────────────────────────────────────────────
// ACCOUNT AVATAR BUTTON  (AppBar action — unchanged API for UniversalHeader)
// ─────────────────────────────────────────────────────────────────────────────

class AccountAvatarButton extends ConsumerWidget {
  final VoidCallback onTap;

  const AccountAvatarButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: kPrimaryMid,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: authState.isLoggedIn
              ? Text(
            getInitials(authState.username),
            style: const TextStyle(
              color: kPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          )
              : const Icon(Icons.person_outline, color: kPrimary, size: 20),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCOUNT DRAWER
// ─────────────────────────────────────────────────────────────────────────────

class AccountDrawer extends ConsumerStatefulWidget {
  final DecryptedData decryptedDataHandler;

  const AccountDrawer({super.key, required this.decryptedDataHandler});

  @override
  ConsumerState<AccountDrawer> createState() => _AccountDrawerState();
}

class _AccountDrawerState extends ConsumerState<AccountDrawer> {

  // ── Navigation helpers ────────────────────────────────────────────────────

  void _closeAndPush(Widget screen) {
    Navigator.of(context).pop(); // close drawer
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _handleLogout() async {
    Navigator.of(context).pop(); // close drawer first for cleaner UX
    final confirmed = await AppDialogs.confirmLogout(context);
    if (confirmed != true) return;

    await ref.read(authStateProvider.notifier).logout();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          dataStream: widget.decryptedDataHandler.dataStream,
          decryptedDataHandler: widget.decryptedDataHandler,
        ),
      ),
          (route) => false,
    );
  }

  // ── Mode switch ───────────────────────────────────────────────────────────

  Future<void> _handleModeSwitch() async {
    final currentMode = ref.read(appModeProvider);
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
    final isGoingToTraining = currentMode == AppMode.emergency;

    // Training requires login
    if (isGoingToTraining && !isLoggedIn) {
      Navigator.of(context).pop(); // close drawer
      final shouldLogin = await AppDialogs.promptLogin(context);
      if (shouldLogin != true) return;
      if (!mounted) return;
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            dataStream: widget.decryptedDataHandler.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(); // close drawer

    final confirmed = isGoingToTraining
        ? await AppDialogs.confirmSwitchToTraining(context)
        : await AppDialogs.confirmSwitchToEmergency(context);

    if (confirmed == true && mounted) {
      final targetMode =
      isGoingToTraining ? AppMode.training : AppMode.emergency;
      ref.read(appModeProvider.notifier).setMode(targetMode);
      HapticFeedback.lightImpact();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final currentMode = ref.watch(appModeProvider);
    final isCprActive = ref.watch(cprSessionActiveProvider);
    final isLoggedIn = authState.isLoggedIn;
    final isTraining = currentMode == AppMode.training;
    final screenWidth = MediaQuery.of(context).size.width;

    return Drawer(
      width: screenWidth * 0.82,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 24,
              offset: Offset(-4, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [

              // ── Profile header ─────────────────────────────────────────────
              _ProfileHeader(
                username: authState.username,
                isLoggedIn: isLoggedIn,
                isTraining: isTraining,
                onEditTap: isLoggedIn
                    ? () => _closeAndPush(const ProfileEditorScreen())
                    : null,
              ),

              const _DrawerDivider(),

              // ── Stats (logged in only) ─────────────────────────────────────
              if (isLoggedIn) ...[
                _StatsRow(),
                const _DrawerDivider(),
              ],

              // ── Scrollable menu items ──────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [

                    // Mode toggle
                    _DrawerItem(
                      icon: isTraining
                          ? Icons.emergency_outlined
                          : Icons.school_outlined,
                      iconColor: isTraining ? kPrimary : kTraining,
                      label: isTraining
                          ? 'Switch to Emergency Mode'
                          : 'Switch to Training Mode',
                      labelColor: isTraining ? kPrimary : kTraining,
                      isDisabled: isCprActive,
                      disabledHint: 'CPR active',
                      onTap: isCprActive ? null : _handleModeSwitch,
                    ),

                    const _DrawerDivider(),

                    // Leaderboard (logged in only)
                    if (isLoggedIn)
                      _DrawerItem(
                        icon: Icons.leaderboard_outlined,
                        label: 'Leaderboard',
                        onTap: () => _closeAndPush(
                          LeaderboardScreen(
                              currentUsername: authState.username),
                        ),
                      ),

                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () => _closeAndPush(const SettingsScreen()),
                    ),

                    _DrawerItem(
                      icon: Icons.help_outline_rounded,
                      label: 'Help & About',
                      onTap: () => _closeAndPush(const HelpAboutScreen()),
                    ),

                    const _DrawerDivider(),

                    // Auth action
                    if (isLoggedIn)
                      _DrawerItem(
                        icon: Icons.logout_rounded,
                        iconColor: kEmergency,
                        label: 'Log Out',
                        labelColor: kEmergency,
                        onTap: _handleLogout,
                        showChevron: false,
                      )
                    else
                      _DrawerItem(
                        icon: Icons.login_rounded,
                        iconColor: kPrimary,
                        label: 'Log In',
                        labelColor: kPrimary,
                        onTap: () => _closeAndPush(
                          LoginScreen(
                            dataStream:
                            widget.decryptedDataHandler.dataStream,
                            decryptedDataHandler:
                            widget.decryptedDataHandler,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Version footer ─────────────────────────────────────────────
              const _VersionFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String? username;
  final bool isLoggedIn;
  final bool isTraining;
  final VoidCallback? onEditTap;

  const _ProfileHeader({
    required this.username,
    required this.isLoggedIn,
    required this.isTraining,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        children: [
          // Avatar with edit badge
          Stack(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPrimaryLight,
                  border: Border.all(color: kPrimaryMid, width: 2),
                ),
                child: Center(
                  child: isLoggedIn
                      ? Text(
                    getInitials(username),
                    style: const TextStyle(
                      color: kPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  )
                      : const Icon(Icons.person_outline,
                      color: kPrimary, size: 30),
                ),
              ),
              if (onEditTap != null)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onEditTap,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: kPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.edit,
                          color: Colors.white, size: 11),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn ? (username ?? 'User') : 'Not logged in',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                // Mode badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: isTraining ? kTrainingBg : kPrimaryLight,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isTraining
                          ? kTraining.withOpacity(0.3)
                          : kPrimary.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTraining
                            ? Icons.school_outlined
                            : Icons.emergency_outlined,
                        size: 11,
                        color: isTraining ? kTraining : kPrimary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isTraining ? 'Training Mode' : 'Emergency Mode',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isTraining ? kTraining : kPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // TODO: replace — values with actual data from provider/backend
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          _StatCard(
              icon: Icons.history_rounded, label: 'Sessions', value: '—'),
          const SizedBox(width: 8),
          _StatCard(
              icon: Icons.bar_chart_rounded, label: 'Avg Score', value: '—'),
          const SizedBox(width: 8),
          _StatCard(
              icon: Icons.leaderboard_outlined, label: 'Rank', value: '—'),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: kPrimaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: kPrimary),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kTextDark)),
            const SizedBox(height: 2),
            Text(label,
                style: kLabel(size: 9, color: kTextLight),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAWER ITEM
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final Color? labelColor;
  final bool isDisabled;
  final String? disabledHint;
  final bool showChevron;
  final VoidCallback? onTap;

  const _DrawerItem({
    required this.icon,
    this.iconColor,
    required this.label,
    this.labelColor,
    this.isDisabled = false,
    this.disabledHint,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.4 : 1.0,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              // Icon box
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (iconColor ?? kTextMid).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon,
                    size: 18, color: iconColor ?? kTextMid),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: labelColor ?? kTextDark,
                  ),
                ),
              ),
              if (isDisabled && disabledHint != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kTrainingBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    disabledHint!,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: kTraining),
                  ),
                )
              else if (showChevron)
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: kTextLight),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _DrawerDivider extends StatelessWidget {
  const _DrawerDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
        height: 1,
        thickness: 1,
        color: kDivider,
        indent: 20,
        endIndent: 20);
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'CPR Assist v1.0.0',
        style: kLabel(size: 11, color: kTextLight),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthGuard — kept here for backward compatibility
// ─────────────────────────────────────────────────────────────────────────────

class AuthGuard extends ConsumerWidget {
  final Widget child;
  final bool requiresAuth;
  final String deniedMessage;
  final String deniedTitle;

  const AuthGuard({
    super.key,
    required this.child,
    this.requiresAuth = false,
    this.deniedMessage = 'This feature requires a user account.',
    this.deniedTitle = 'Login Required',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!requiresAuth) return child;
    final isLoggedIn = ref.watch(authStateProvider).isLoggedIn;
    if (!isLoggedIn) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: kPrimary),
              const SizedBox(height: 16),
              Text(deniedTitle,
                  style: kHeading(size: 20)),
              const SizedBox(height: 8),
              Text(deniedMessage,
                  textAlign: TextAlign.center,
                  style: kBody(size: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                icon: const Icon(Icons.login),
                label: const Text('Log In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }
}