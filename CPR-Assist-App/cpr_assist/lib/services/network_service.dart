import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


class NetworkService {
  static String get baseUrl {
    String? url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception("❌ BASE_URL is missing from .env");
    }
    return url;
  }


  Future<void> testConnection() async {
    try {
      final response = await http.get(Uri.parse('${NetworkService.baseUrl}/api/test'));
      print("🚀 Server Test Response: ${response.body}");
    } catch (e) {
      print("❌ Failed to connect to Railway server: $e");
    }
  }

  Future<void> testRailwayConnection() async {
    try {
      final response = await http.get(Uri.parse('${NetworkService.baseUrl}/api/test'));
      print("🚀 Railway Test Response: ${response.body}");
    } catch (e) {
      print("❌ Railway connection failed: $e");
    }
  }


  // 🔹 TOKEN MANAGEMENT 🔹
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  static Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
  }

  static Future<void> removeToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token'); // ✅ Only remove the JWT token
    await prefs.remove('user_id');   // ✅ Remove user ID as well
  }


  // 🔹 AUTHENTICATION 🔹
  static Future<bool> refreshToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) {
      print('❌ No token found, cannot refresh.');
      return false;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final newToken = jsonResponse["token"];
      final userId = jsonResponse["user_id"];

      if (newToken != null && userId != null) {
        await saveToken(newToken);
        await saveUserId(userId);
        return true;
      }
    }
    return false;
  }

  static Future<bool> isTokenValid() async {
    final token = await getToken();
    if (token == null) return false;

    try {
      return !JwtDecoder.isExpired(token);
    } catch (e) {
      return false;
    }
  }

  static Future<bool> ensureAuthenticated() async {
    if (await isTokenValid()) {
      print("✅ Token is still valid.");
      return true;
    }

    print("❌ Token expired. Attempting to refresh...");
    bool refreshed = await refreshToken();

    if (!refreshed) {
      await removeToken();
      return false;
    }

    print("🔄 Token refreshed successfully.");
    return true;
  }

  // 🔹 GENERIC NETWORK REQUESTS 🔹
  static Future<dynamic> post(String endpoint, Map<String, dynamic> body, {bool requiresAuth = false}) async {
    try {
      return await _makeRequest('POST', endpoint, body: body, requiresAuth: requiresAuth);
    } catch (e) {
      throw Exception('Error during POST request: $e');
    }
  }

  static Future<dynamic> get(String endpoint, {bool requiresAuth = false}) async {
    try {
      return await _makeRequest('GET', endpoint, requiresAuth: requiresAuth);
    } catch (e) {
      throw Exception('Error during GET request: $e');
    }
  }

  static Future<dynamic> _makeRequest(String method, String endpoint, {Map<String, dynamic>? body, bool requiresAuth = false}) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final token = await getToken();

    if (requiresAuth && (token == null || token.isEmpty)) {
      throw Exception("Unauthorized: Missing authentication token.");
    }

    final headers = {
      'Content-Type': 'application/json',
      if (requiresAuth) 'Authorization': 'Bearer $token',
    };

    http.Response response;

    try {
      if (method == 'POST') {
        response = await http.post(url, headers: headers, body: jsonEncode(body));
      } else if (method == 'GET') {
        response = await http.get(url, headers: headers);
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }

      return _handleResponse(response, endpoint, method, body: body, requiresAuth: requiresAuth);
    } catch (e) {
      throw Exception('Network request failed.');
    }
  }

  static dynamic _handleResponse(http.Response response, String endpoint, String method, {Map<String, dynamic>? body, bool requiresAuth = false}) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    if (response.statusCode == 401 && requiresAuth) {
      final refreshed = await refreshToken();

      if (refreshed) {
        return await _makeRequest(method, endpoint, body: body, requiresAuth: requiresAuth);
      } else {
        await removeToken();
        throw Exception('401 Unauthorized and token refresh failed.');
      }
    }

    final Map<String, dynamic> jsonResponse = jsonDecode(response.body);
    final errorMessage = jsonResponse.containsKey('errors')
        ? jsonResponse['errors']
        : jsonResponse.containsKey('error')
        ? jsonResponse['error']
        : jsonResponse.containsKey('message')
        ? jsonResponse['message']
        : 'Unknown error';

    throw Exception('HTTP Error ${response.statusCode}: $errorMessage');
  }

  // 🔹 FETCH AED LOCATIONS 🔹
  static Future<List<dynamic>> fetchAEDLocations() async {
    try {
      final response = await get('/aed', requiresAuth: false);

      if (response is Map<String, dynamic> && response.containsKey("data")) {
        return response["data"];
      } else {
        throw Exception("Invalid response format from backend");
      }
    } catch (e) {
      print("❌ Error fetching AED locations: $e");
      return [];
    }
  }

  static String get googleMapsApiKey {
    String? key = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception("❌ GOOGLE_MAPS_API_KEY is missing from .env");
    }
    return key;
  }


  static Future<String?> fetchGoogleMapsApiKey() async {
    try {
      final response = await get('/api/maps-key', requiresAuth: false);
      if (response is Map<String, dynamic> && response.containsKey('apiKey')) {
        return response['apiKey'];
      }
    } catch (e) {
      print("❌ Error fetching Google Maps API Key: $e");
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getExternal(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      print("❌ Failed external request: ${response.body}");
      return null;
    } catch (e) {
      print("❌ Error in external GET request: $e");
      return null;
    }
  }
}
