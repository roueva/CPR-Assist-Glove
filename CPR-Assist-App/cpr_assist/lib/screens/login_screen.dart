import 'package:flutter/material.dart';
import '../services/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';
import 'registration_screen.dart';
import '../services/decrypted_data.dart'; // Import DecryptedData handler
import '../widgets/account_menu.dart'; // Import AccountMenu widget

class LoginScreen extends StatefulWidget {
  final Stream<Map<String, dynamic>> dataStream;
  final DecryptedData decryptedDataHandler;

  const LoginScreen({
    super.key,
    required this.dataStream,
    required this.decryptedDataHandler,
  });

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus(); // Dismiss keyboard
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Send login request to backend
      final response = await NetworkService.post('/auth/login', {
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
      });

      if (response['token'] != null && response['user_id'] != null) {
        await NetworkService.saveToken(response['token']);  // ✅ Store token
        await NetworkService.saveUserId(response['user_id']);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('username', _usernameController.text.trim());

        print('✅ User logged in successfully.');

        // ✅ Return to previous screen or redirect to HomeScreen
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true); // ✅ Go back to previous screen
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HomeScreen(
                decryptedDataHandler: widget.decryptedDataHandler,
                isLoggedIn: true, // ✅ Ensure HomeScreen updates login state
              ),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = response['message'] ?? 'Login failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error. Please check your connection and try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // Dismiss keyboard on tap
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Login'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context, false); // ✅ Explicitly return `false`
            },
          ),
          actions: [
            AccountMenu(decryptedDataHandler: widget.decryptedDataHandler), // Add account menu
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a username';
                    }
                    if (value.length < 4) {
                      return 'Username must be at least 4 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                  ),
                  obscureText: !_isPasswordVisible,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  onPressed: _login,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Login'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegistrationScreen(
                          dataStream: widget.dataStream,
                          decryptedDataHandler: widget.decryptedDataHandler,
                        ),
                      ),
                    );
                  },
                  child: const Text('Register New Account'),
                ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
