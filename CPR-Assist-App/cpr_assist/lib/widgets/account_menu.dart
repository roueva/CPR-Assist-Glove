import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import '../providers/app_providers.dart';
import '../screens/login_screen.dart';
import '../services/decrypted_data.dart';

class AccountMenu extends ConsumerStatefulWidget {
  final DecryptedData decryptedDataHandler;

  const AccountMenu({super.key, required this.decryptedDataHandler});

  @override
  ConsumerState<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends ConsumerState<AccountMenu> {
  String username = "Account"; // Default display when not logged in

  @override
  void initState() {
    super.initState();
    // ✅ Get username from auth provider
    final authState = ref.read(authStateProvider);
    if (authState.isLoggedIn && authState.username != null) {
      username = authState.username!;
    }
  }

  Future<void> _logout() async {
    // ✅ Use the auth provider instead of manual state management
    await ref.read(authStateProvider.notifier).logout();

    setState(() {
      username = "Account"; // Reset UI state
    });

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => LoginScreen(
            dataStream: widget.decryptedDataHandler.dataStream,
            decryptedDataHandler: widget.decryptedDataHandler,
          ),
        ),
            (route) => false,
      );
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      _logout();
    }
  }

  Future<void> _handleModeSwitch() async {
    final currentMode = ref.read(appModeProvider);
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;

    // If switching TO training mode, require login
    if (currentMode == AppMode.emergency && !isLoggedIn) {
      final shouldShowLogin = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Login Required'),
          content: const Text(
            'Training Mode requires a user account to save your practice sessions and track progress over time.\n\n'
                'Would you like to log in or create an account?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log In'),
            ),
          ],
        ),
      );

      if (shouldShowLogin == true) {
        final loggedIn = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(
              dataStream: widget.decryptedDataHandler.dataStream,
              decryptedDataHandler: widget.decryptedDataHandler,
            ),
          ),
        );

        if (loggedIn != true) return; // User canceled login
      } else {
        return; // User canceled mode switch
      }
    }

    // Show confirmation dialog as specified in thesis
    final targetMode = currentMode == AppMode.emergency
        ? AppMode.training
        : AppMode.emergency;

    final shouldSwitch = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Switch to ${targetMode == AppMode.training ? "Training" : "Emergency"} Mode?'),
        content: Text(
          targetMode == AppMode.training
              ? 'Training Mode: Practice CPR with real-time feedback and performance analysis. Your sessions will be saved and graded.'
              : 'Emergency Mode: Use during real cardiac arrest situations. No performance grading or session recording.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Switch to ${targetMode == AppMode.training ? "Training" : "Emergency"}'),
          ),
        ],
      ),
    );

    if (shouldSwitch == true) {
      ref.read(appModeProvider.notifier).setMode(targetMode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Switched to ${targetMode == AppMode.training ? "Training" : "Emergency"} Mode',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: _buildIconButton("assets/icons/account.svg"),
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
        onSelected: (value) async {
          if (value == 1) {
            // Mode switching
            await _handleModeSwitch();
          } else if (value == 2) {
            // Settings placeholder
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Settings coming soon')),
            );
          } else if (value == 3) {
            _confirmLogout();
          }
        },
        itemBuilder: (context) {
          final currentMode = ref.watch(appModeProvider);
          // ✅ Removed unused isLoggedIn variable

          return [
            // User Account Info
            PopupMenuItem(
              enabled: false,
              child: Row(
                children: [
                  SvgPicture.asset(
                    "assets/icons/account.svg",
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF194E9D),
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    username,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),

            // Mode Switching (with CPR session check)
            PopupMenuItem(
              value: 1,
              enabled: !ref.watch(cprSessionActiveProvider),
              child: Opacity(
                opacity: ref.watch(cprSessionActiveProvider) ? 0.5 : 1.0,
                child: Row(
                  children: [
                    Icon(
                      currentMode == AppMode.emergency
                          ? Icons.school_outlined
                          : Icons.emergency_outlined,
                      size: 20,
                      color: const Color(0xFF194E9D),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      currentMode == AppMode.emergency
                          ? "Switch to Training Mode"
                          : "Switch to Emergency Mode",
                    ),
                  ],
                ),
              ),
            ),

            const PopupMenuDivider(),

            // Settings
            const PopupMenuItem(
              value: 2,
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 20),
                  SizedBox(width: 10),
                  Text("Settings"),
                ],
              ),
            ),

            const PopupMenuDivider(),

            // Logout
            const PopupMenuItem(
              value: 3,
              child: Row(
                children: [
                  Icon(Icons.logout, size: 20, color: Colors.red),
                  SizedBox(width: 10),
                  Text("Log Out", style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ];
        },
    );
  }

  /// Helper
  Widget _buildIconButton(String assetPath) {
    return SvgPicture.asset(
      assetPath,
      width: 22,   // ✅ Correct size
      height: 22,
    );
  }
}

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
              const Icon(
                Icons.lock_outline,
                size: 64,
                color: Color(0xFF194E9D),
              ),
              const SizedBox(height: 16),
              Text(
                deniedTitle,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF194E9D),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                deniedMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                icon: const Icon(Icons.login),
                label: const Text('Log In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF194E9D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
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
