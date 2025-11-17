import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NetworkService {
  final SharedPreferences _prefs;
  static StreamController<bool>? _connectivityController;
  static bool _lastConnectivityState = true;
  static Timer? _connectivityTimer;
  static final List<Function(bool)> _connectivityListeners = [];
  NetworkService(this._prefs);

  static String get baseUrl {
    String? url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception("❌ BASE_URL is missing from .env");
    }
    return url;
  }

  static Future<void> testConnection() async {
    try {
      final response = await http.get(Uri.parse('${NetworkService.baseUrl}/api/test'));
      print("🚀 Server Test Response: ${response.body}");
    } catch (e) {
      print("❌ Failed to connect to Railway server: $e");
    }
  }

  static Future<bool> isConnected() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Quick DNS lookup instead of full HTTP request
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Add this for your app-specific connectivity
  static Future<bool> canReachBackend() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'), // ← Add a lightweight health endpoint
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static void startConnectivityMonitoring({Duration interval = const Duration(seconds: 10)}) {
    _connectivityTimer?.cancel();
    _connectivityController ??= StreamController<bool>.broadcast();

    _connectivityTimer = Timer.periodic(interval, (timer) async {
      final isConnected = await NetworkService.isConnected();

      if (isConnected != _lastConnectivityState) {
        _lastConnectivityState = isConnected;
        _connectivityController?.add(isConnected);

        // Notify all listeners
        for (final listener in _connectivityListeners) {
          listener(isConnected);
        }
      }
    });
  }

  static void stopConnectivityMonitoring() {
    _connectivityTimer?.cancel();
    _connectivityController?.close();
    _connectivityController = null;
    _connectivityListeners.clear();
  }

  static Stream<bool> get connectivityStream =>
      _connectivityController?.stream ?? Stream.empty();

  static void addConnectivityListener(Function(bool) listener) {
    _connectivityListeners.add(listener);
  }

  static void removeConnectivityListener(Function(bool) listener) {
    _connectivityListeners.remove(listener);
  }

  static bool get lastKnownConnectivityState => _lastConnectivityState;

  // 🔹 TOKEN MANAGEMENT 🔹
  Future<int?> getUserId() async {
    return _prefs.getInt('user_id');
  }

  Future<void> saveUserId(int userId) async {
    await _prefs.setInt('user_id', userId);
  }

  Future<String?> getToken() async {
    return _prefs.getString('jwt_token');
  }

  Future<void> saveToken(String token) async {
    await _prefs.setString('jwt_token', token);
  }

  Future<void> removeToken() async {
    await _prefs.remove('jwt_token'); // ✅ Only remove the JWT token
    await _prefs.remove('user_id');   // ✅ Remove user ID as well
  }

  // 🔹 AUTHENTICATION 🔹
  Future<bool> refreshToken() async {
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

  Future<bool> isTokenValid() async {
    final token = await getToken();
    if (token == null) return false;

    try {
      // ✅ Check both format AND expiration
      return !JwtDecoder.isExpired(token);
    } catch (e) {
      return false;
    }
  }


  Future<bool> ensureAuthenticated() async {
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
  Future<dynamic> post(String endpoint, Map<String, dynamic> body, {bool requiresAuth = false}) async {
    try {
      return await _makeRequest('POST', endpoint, body: body, requiresAuth: requiresAuth);
    } catch (e) {
      throw Exception('Error during POST request: $e');
    }
  }

  Future<dynamic> get(String endpoint, {bool requiresAuth = false}) async {
    try {
      return await _makeRequest('GET', endpoint, requiresAuth: requiresAuth);
    } catch (e) {
      throw Exception('Error during GET request: $e');
    }
  }

  Future<dynamic> _makeRequest(String method, String endpoint, {Map<String, dynamic>? body, bool requiresAuth = false}) async {
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

  dynamic _handleResponse(http.Response response, String endpoint, String method, {Map<String, dynamic>? body, bool requiresAuth = false}) async {
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
  Future<List<dynamic>> fetchAEDLocations() async {
    try {
      final response = await get('/aed/', requiresAuth: false);
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

  static String? get googleMapsApiKey {
    String? key = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception("❌ GOOGLE_MAPS_API_KEY is missing from .env");
    }
    return key;
  }

  // 🔹 GET CACHE/SYNC INFO 🔹
  Future<Map<String, dynamic>?> getAEDCacheInfo() async {
    try {
      final response = await get('/aed/cache/info', requiresAuth: false);

      if (response is Map<String, dynamic> && response.containsKey("cache")) {
        return response["cache"];
      }
      return null;
    } catch (e) {
      print("❌ Error fetching cache info: $e");
      return null;
    }
  }


  static Future<String?> fetchGoogleMapsApiKey() async {
    try {
      final url = Uri.parse('$baseUrl/api/maps-key'); // <--- Find this line

      // ADD THIS PRINT STATEMENT:
      print("🐞 DEBUG: Attempting to fetch key from: $url");
      final response = await http.get(
        Uri.parse('$baseUrl/api/maps-key'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        if (jsonResponse is Map<String, dynamic> && jsonResponse.containsKey('apiKey')) {
          return jsonResponse['apiKey'];
        }
      } else {
        // ADD THIS ELSE BLOCK:
        print("❌ Server returned non-200 status: ${response.statusCode}");
        print("❌ Server response body: ${response.body}");
      }

    } catch (e) {
      print("❌ FULL ERROR fetching Google Maps API Key: $e");
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