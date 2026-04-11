import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  final prefs = await SharedPreferences.getInstance();
  final networkService = NetworkService();
  networkService.initialize(prefs);
  await dotenv.load(fileName: '.env');  // ← moved here
  _filterLogs();

  final wakelockPref = prefs.getBool('settings_keepScreenOn') ?? true;
  if (wakelockPref) { unawaited(WakelockPlus.enable()); }
  else { unawaited(WakelockPlus.disable()); }

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const MyApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    NetworkService.startConnectivityMonitoring(  // dotenv gone, this stays
      interval: AppConstants.connectivityCheckInterval,
    );
    unawaited(CustomIcons.loadIcons());
    unawaited(AEDClusterManager.prewarmIconCache());
    unawaited(AvailabilityParser.loadRules());
    unawaited(container.read(authStateProvider.notifier).checkAuthStatus());

    try {
      await CacheService.initializeAllCaches();
      container.read(cacheInitializedProvider.notifier).state = true;
    } catch (e) {
      container.read(cacheErrorProvider.notifier).state = e.toString();
    }
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Exposes tab switching to NFC and deep link handlers outside the widget tree.
final ValueNotifier<int> nfcTabNotifier = ValueNotifier<int>(-1);

// ─────────────────────────────────────────────────────────────────────────────
// Root widget
// ─────────────────────────────────────────────────────────────────────────────

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  StreamSubscription? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handleIncomingLinks();

    // ADD this:
    ref.listenManual<String?>(cacheErrorProvider, (_, error) {
      if (error != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            UIHelper.showWarning(
              context,
              'Offline mode limited — some features may be unavailable',
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    NetworkService.stopConnectivityMonitoring();
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  final _appLinks = AppLinks();

  Future<void> _handleIncomingLinks() async {
    // Cold start — add a delay to ensure the navigator is ready
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null && mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) _processLink(initialUri);
      }
    } catch (_) {}

    // Warm start — app already running, no delay needed
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (mounted) _processLink(uri);
    });
  }

  void _processLink(Uri uri) {
    if (uri.host == 'reset-password') {
      final token = uri.queryParameters['token'] ?? '';
      if (token.isNotEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => ResetPasswordScreen(token: token),
            ),
          );
        });
      }
      return;
    }

    // NFC glove tap — switch to Live CPR tab
    if (uri.host == 'open') {
      final tab = uri.queryParameters['tab'] ?? '';
      if (tab == 'cpr') {
        Future.delayed(const Duration(milliseconds: 400), () {
          nfcTabNotifier.value = 1; // 1 = Live CPR tab
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep BLE provider alive at root so the glove connection persists
    // across tab switches without re-initialising.
    ref.watch(bleConnectionProvider);

    ref.listen<bool>(
      settingsProvider.select((s) => s.keepScreenOn),
          (_, keepOn)  {
        if (keepOn) {
          WakelockPlus.enable();
        } else {
          WakelockPlus.disable();
        }
      },
    );

    return MaterialApp(
      title: 'CPR Assist',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,   // ← single token-driven theme; no inline ThemeData
      navigatorKey: navigatorKey,
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