import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkService {
  //static const String baseUrl = 'https://cpr-assist-app.up.railway.app';
  static String get baseUrl => 'http://192.168.2.18:3000'; // Local IP
 // static String get baseUrl => 'http://192.168.0.121:3000'; // captaincoach

  // Get the token from SharedPreferences
  static Future<String?> getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  // Save token in SharedPreferences
  static Future<void> saveToken(String token) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  // Remove token from SharedPreferences
  static Future<void> removeToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_id');
  }

  // Save user ID to SharedPreferences
  static Future<void> saveUserId(int userId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
  }

  // Get user ID from SharedPreferences
  static Future<int?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  // POST request method
  static Future<dynamic> post(String endpoint, Map<String, dynamic> body, {bool requiresAuth = false}) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = {
        'Content-Type': 'application/json',
        if (requiresAuth) 'Authorization': 'Bearer ${await getToken()}',
      };

      // Debugging logs
      print('POST Request URL: $url');
      print('POST Request Headers: $headers');
      print('POST Request Body: ${jsonEncode(body)}');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      return _handleResponse(response);
    } catch (e) {
      print('Error during POST request: $e');
      throw Exception('Network error: $e');
    }
  }

  // GET request method
  static Future<dynamic> get(String endpoint, {bool requiresAuth = false}) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = {
        if (requiresAuth) 'Authorization': 'Bearer ${await getToken()}',
      };

      final response = await http.get(url, headers: headers);

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Handle HTTP responses
  static dynamic _handleResponse(http.Response response) {
    print('Response Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      print('Token expired or unauthorized access.');
      throw Exception('401 Unauthorized');
    } else {
      final errorMessage = jsonDecode(response.body)['errors']
          ?? jsonDecode(response.body)['error']
          ?? 'Unknown error';
      throw Exception('HTTP Error ${response.statusCode}: $errorMessage');
    }
  }
}
