import 'package:cpr_assist/screens/main_navigation.dart';
import 'package:cpr_assist/services/network_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/aed_markers.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'services/decrypted_data.dart';
import 'services/ble_connection.dart';
import 'dart:developer' as developer;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'providers/shared_preferences_provider.dart';
import 'providers/auth_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';



// ===== PROVIDERS =====

// DecryptedData Provider
final decryptedDataProvider = Provider<DecryptedData>((ref) {
  return DecryptedData();
});

// BLE Connection Provider
final bleConnectionProvider = Provider<BLEConnection>((ref) {
  final decryptedDataHandler = ref.watch(decryptedDataProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  return BLEConnection(
    decryptedDataHandler: decryptedDataHandler,
    prefs: prefs,
    onStatusUpdate: (status) {},
  );
});

// Simple auth state provider for backward compatibility
final simpleAuthStateProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.isLoggedIn;
});

// Navigator Key Provider (if you still need global navigation)
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>((ref) {
  return GlobalKey<NavigatorState>();
});

// ===== MAIN FUNCTION =====

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CustomIcons.loadIcons();

  // ✅ Load .env from the correct location
  await dotenv.load(fileName: ".env");

  // ✅ Keep screen awake
  WakelockPlus.enable();


  NetworkService.startConnectivityMonitoring();

  filterLogs();

  final prefs = await SharedPreferences.getInstance();

  // ✅ Check if the user is logged in when the app starts
  bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  if (isLoggedIn) {
    print("🔄 User is logged in. Verifying token...");

    // Create NetworkService instance with SharedPreferences
    final networkService = NetworkService(prefs);
    bool authenticated = await networkService.ensureAuthenticated();

    if (!authenticated) {
      print("❌ Token expired. Logging user out...");
      await prefs.setBool('isLoggedIn', false);
      isLoggedIn = false;
    }
  } else {
    print("❌ No user is logged in.");
  }

  runApp(
    ProviderScope(
      overrides: [
        // Override the SharedPreferences provider with the actual instance
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyApp(),
    ),
  );
}

// ===== APP CLASS =====

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch providers to get current values
    final isLoggedIn = ref.watch(simpleAuthStateProvider);
    final decryptedDataHandler = ref.watch(decryptedDataProvider);
    final navigatorKey = ref.watch(navigatorKeyProvider);

    // Initialize BLE connection (this will create it when first accessed)
    ref.watch(bleConnectionProvider);

    return MaterialApp(
      title: 'CPR Assist App',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey: navigatorKey,
      home: MainNavigationScreen(
        decryptedDataHandler: decryptedDataHandler,
        isLoggedIn: isLoggedIn,
      ),
      routes: {
        '/login': (context) => LoginScreen(
          dataStream: decryptedDataHandler.dataStream,
          decryptedDataHandler: decryptedDataHandler,
        ),
        '/register': (context) => RegistrationScreen(
          dataStream: decryptedDataHandler.dataStream,
          decryptedDataHandler: decryptedDataHandler,
        ),
      },
    );
  }
}

// ===== UTILITY FUNCTIONS =====

/// **🔇 Filter Unwanted Logs**
void filterLogs() {
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (message.contains("FrameEvents") ||
        message.contains("updateAcquireFence") ||
        message.contains("ProxyAndroidLoggerBackend") ||
        message.contains("Too many Flogger logs") ||
        message.contains("Flogger")) {
      return; // ✅ Suppress logs
    }
    developer.log(message);
  };
}