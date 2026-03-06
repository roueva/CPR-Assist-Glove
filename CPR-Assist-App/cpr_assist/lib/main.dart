import 'package:cpr_assist/screens/main_navigation.dart';
import 'package:cpr_assist/services/aed_map/aed_cluster_renderer.dart';
import 'package:cpr_assist/services/aed_map/cache_service.dart';
import 'package:cpr_assist/services/network_service.dart';
// ✅ ADD
import 'package:cpr_assist/utils/availability_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/aed_markers.dart';
import 'dart:developer' as developer;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/app_providers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WakelockPlus.enable();

  await CustomIcons.loadIcons();
  await AEDClusterManager.prewarmIconCache();
  await dotenv.load(fileName: ".env");
  await AvailabilityParser.loadRules();

  final prefs = await SharedPreferences.getInstance();
  final networkService = NetworkService();
  await networkService.initialize(prefs);

  bool cachesInitialized = false;
  String? cacheError;
  try {
    await CacheService.initializeAllCaches();
    cachesInitialized = true;
    print("✅ Caches initialized");
  } catch (e) {
    cacheError = e.toString();
    print("❌ Cache initialization failed: $e");
  }

  NetworkService.startConnectivityMonitoring();
  filterLogs();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      cacheAvailabilityProvider.overrideWithValue(cachesInitialized),
    ],
  );

  final authNotifier = container.read(authStateProvider.notifier);
  await authNotifier.checkAuthStatus();

  final isLoggedIn = container.read(authStateProvider).isLoggedIn;
  print(isLoggedIn ? "✅ User is logged in" : "ℹ️ No user logged in (optional)");

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MyApp(
        cacheError: cacheError,
      ),
    ),
  );
}

// ===== APP CLASS =====

class MyApp extends ConsumerStatefulWidget {
  final String? cacheError;

  const MyApp({
    super.key,
    this.cacheError,
  });

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.cacheError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offline mode limited - some features may be unavailable'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    NetworkService.stopConnectivityMonitoring();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bleConnectionProvider);
    return MaterialApp(
      title: 'CPR Assist App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      home: const MainNavigationScreen(),
      // ✅ REMOVED routes - use Navigator.push instead
    );
  }
}

// ===== UTILITY FUNCTIONS =====

void filterLogs() {
  if (!const bool.fromEnvironment('dart.vm.product')) {
    return;
  }

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;

    if (message.contains("FrameEvents") ||
        message.contains("updateAcquireFence") ||
        message.contains("ProxyAndroidLoggerBackend") ||
        message.contains("Too many Flogger logs") ||
        message.contains("Flogger")) {
      return;
    }

    developer.log(message);
  };
}