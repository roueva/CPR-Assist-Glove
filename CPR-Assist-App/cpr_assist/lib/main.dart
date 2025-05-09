import 'package:cpr_assist/screens/main_layout.dart';
import 'package:cpr_assist/services/network_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'custom_icons.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'services/decrypted_data.dart';
import 'services/ble_connection.dart';
import 'dart:developer' as developer;
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CustomIcons.loadIcons();

  // ✅ Load .env from the correct location
    await dotenv.load(fileName: ".env");

  filterLogs(); // ✅ Suppress unwanted logs before app starts

  final decryptedDataHandler = DecryptedData();
  final prefs = await SharedPreferences.getInstance();

  // ✅ Check if the user is logged in when the app starts
  bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  if (isLoggedIn) {
    print("🔄 User is logged in. Verifying token...");
    bool authenticated = await NetworkService.ensureAuthenticated();

    if (!authenticated) {
      print("❌ Token expired. Logging user out...");
      await prefs.setBool('isLoggedIn', false);
      isLoggedIn = false;
    }
  } else {
    print("❌ No user is logged in.");
  }

  runApp(MyApp(
    decryptedDataHandler: decryptedDataHandler,
    prefs: prefs,
  ));
}

class MyApp extends StatefulWidget {
  final DecryptedData decryptedDataHandler;
  final SharedPreferences prefs;

  const MyApp({
    super.key,
    required this.decryptedDataHandler,
    required this.prefs,
  });

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    globalBLEConnection = BLEConnection(
      decryptedDataHandler: widget.decryptedDataHandler,
      prefs: widget.prefs,
      onStatusUpdate: (status) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CPR Assist App',
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorKey: navigatorKey,
      home: MainNavigationScreen(
      decryptedDataHandler: widget.decryptedDataHandler,
      isLoggedIn: widget.prefs.getBool('isLoggedIn') ?? false,
    ),
      routes: {
        '/login': (context) => LoginScreen(
          dataStream: widget.decryptedDataHandler.dataStream,
          decryptedDataHandler: widget.decryptedDataHandler,
        ),
        '/register': (context) => RegistrationScreen(
          dataStream: widget.decryptedDataHandler.dataStream,
          decryptedDataHandler: widget.decryptedDataHandler,
        ),
      },
    );
  }
}

// ✅ Global Navigator Key for Context Access
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ✅ Global BLE Connection Instance
late BLEConnection globalBLEConnection;

/// **🔇 Filter Unwanted Logs**
void filterLogs() {
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (message.contains("FrameEvents") ||
        message.contains("updateAcquireFence") ||
        message.contains("ProxyAndroidLoggerBackend") ||
        message.contains("Too many Flogger logs")) {
      return; // ✅ Suppress logs
    }
    developer.log(message);
  };
}
