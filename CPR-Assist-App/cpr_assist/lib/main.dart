import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'services/decrypted_data.dart'; // Import DecryptedData

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  final DecryptedData decryptedDataHandler = DecryptedData(); // Create a shared instance of DecryptedData

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CPR Assist App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(decryptedDataHandler: decryptedDataHandler), // Use HomeScreen as the initial screen
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
