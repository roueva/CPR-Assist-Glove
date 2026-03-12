import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uni_links/uni_links.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:developer' as developer;
import 'package:cpr_assist/core/core.dart';
import 'features/account/screens/reset_password_screen.dart';
import 'features/aed_map/services/aed_cluster_renderer.dart';
import 'features/aed_map/services/cache_service.dart';
import 'features/aed_map/widgets/aed_markers.dart';
import 'features/aed_map/widgets/availability_parser.dart';
import 'providers/app_providers.dart';
import 'services/network/network_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WakelockPlus.enable();

  await CustomIcons.loadIcons();
  await AEDClusterManager.prewarmIconCache();
  await dotenv.load(fileName: '.env');
  await AvailabilityParser.loadRules();

  final prefs = await SharedPreferences.getInstance();
  final networkService = NetworkService();
  await networkService.initialize(prefs);

  bool cachesInitialized = false;
  String? cacheError;
  try {
    await CacheService.initializeAllCaches();
    cachesInitialized = true;
  } catch (e) {
    cacheError = e.toString();
  }

  NetworkService.startConnectivityMonitoring(
    interval: AppConstants.connectivityCheckInterval,
  );
  _filterLogs();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      cacheAvailabilityProvider.overrideWithValue(cachesInitialized),
    ],
  );

  await container.read(authStateProvider.notifier).checkAuthStatus();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(cacheError: cacheError),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Root widget
// ─────────────────────────────────────────────────────────────────────────────

class MyApp extends ConsumerStatefulWidget {
  final String? cacheError;
  const MyApp({super.key, this.cacheError});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  StreamSubscription? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.cacheError != null) {
      // Show after first frame — no inline ScaffoldMessenger calls.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          UIHelper.showWarning(
            context,
            'Offline mode limited — some features may be unavailable',
          );
        }
      });
    }
    _handleIncomingLinks();
  }

  @override
  void dispose() {
    NetworkService.stopConnectivityMonitoring();
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _handleIncomingLinks() async {
    // Cold start — app was fully closed when the link was tapped
    try {
      final initialLink = await getInitialLink();
      if (initialLink != null && mounted) {
        _processLink(initialLink);
      }
    } catch (_) {}

    // Warm start — app was already running
    _linkSub = linkStream.listen((link) {
      if (link != null && mounted) _processLink(link);
    });
  }

  void _processLink(String link) {
    final uri = Uri.parse(link);
    // Matches: cpr-assist://reset-password?token=abc123
    if (uri.host == 'reset-password') {
      final token = uri.queryParameters['token'] ?? '';
      if (token.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.push(ResetPasswordScreen(token: token));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep BLE provider alive at root so the glove connection persists
    // across tab switches without re-initialising.
    ref.watch(bleConnectionProvider);

    return MaterialApp(
      title: 'CPR Assist',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,   // ← single token-driven theme; no inline ThemeData
      home: const MainNavigationScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log filtering (release builds only)
// ─────────────────────────────────────────────────────────────────────────────

void _filterLogs() {
  if (!const bool.fromEnvironment('dart.vm.product')) return;

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (message.contains('FrameEvents') ||
        message.contains('updateAcquireFence') ||
        message.contains('ProxyAndroidLoggerBackend') ||
        message.contains('Too many Flogger logs') ||
        message.contains('Flogger')) {
      return;
    }
    developer.log(message);
  };
}