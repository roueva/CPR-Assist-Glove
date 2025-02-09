import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/login_screen.dart';
import '../services/decrypted_data.dart';

class AccountMenu extends StatefulWidget {
  final DecryptedData decryptedDataHandler;

  const AccountMenu({super.key, required this.decryptedDataHandler});

  @override
  _AccountMenuState createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  String username = "Account"; // Default display when not logged in

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (isLoggedIn) {
      final savedUsername = prefs.getString('username') ?? 'User';
      setState(() {
        username = savedUsername;
      });
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('username');

    setState(() {
      username = "Account"; // ✅ Reset UI state
    });

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

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: const Icon(Icons.account_circle),
      onSelected: (value) {
        if (value == 1) {
          // Account settings can be handled here in the future
        } else if (value == 2) {
          _confirmLogout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 1,
          child: Row(
            children: [
              const Icon(Icons.account_circle),
              const SizedBox(width: 10),
              Text(username), // ✅ Shows correct username
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 2,
          child: Row(
            children: const [
              Icon(Icons.logout),
              SizedBox(width: 10),
              Text("Log Out"),
            ],
          ),
        ),
      ],
    );
  }
}
