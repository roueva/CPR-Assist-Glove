import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../utils/app_constants.dart';

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  // ✅ SINGLE declaration - late final
  late final SharedPreferences _prefs;

  // ✅ Initialize method (call from main.dart)
  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
  }

  static StreamController<bool>? _connectivityController;
  static bool _lastConnectivityState = true;
  static Timer? _connectivityTimer;
  static final List<Function(bool)> _connectivityListeners = [];

  static String get baseUrl {
    String? url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception("❌ BASE_URL is missing from .env");
    }
    return url;
  }

  static Future<bool> isConnected() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> canReachBackend() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
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
      _connectivityController?.stream ?? const Stream.empty();

  static void addConnectivityListener(Function(bool) listener) {
    if (!_connectivityListeners.contains(listener)) {
      _connectivityListeners.add(listener);
    }
  }

  static void removeConnectivityListener(Function(bool) listener) {
    _connectivityListeners.remove(listener);
  }

  static void clearAllListeners() {
    _connectivityListeners.clear();
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
    await _prefs.remove('jwt_token');
    await _prefs.remove('user_id');
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
    ).timeout(const Duration(seconds: 10));

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

  Future<dynamic> put(String endpoint, Map<String, dynamic> body,
      {bool requiresAuth = false}) async {
    try {
      return await _makeRequest('PUT', endpoint,
          body: body, requiresAuth: requiresAuth);
    } catch (e) {
      throw Exception('Error during PUT request: $e');
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
      } else if (method == 'PUT') {
        response = await http.put(url, headers: headers, body: jsonEncode(body));
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }

      return await _handleResponse(response, endpoint, method, body: body, requiresAuth: requiresAuth);
    } on TimeoutException {
      throw Exception('Request timed out — check your connection.');
    } on SocketException {
      throw Exception('No internet connection.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network request failed: $e');
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

  Future<T?> _retryOperation<T>(
      Future<T> Function() operation, {
        int maxRetries = 3,
        Duration initialDelay = const Duration(seconds: 2),
      }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        return await operation();
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        // Only retry on network-level errors, not HTTP errors
        if (e is! SocketException && e is! TimeoutException) rethrow;

        final backoffDelay = initialDelay * (1 << i);
        print("⚠️ Retry ${i + 1}/$maxRetries after error: $e (waiting ${backoffDelay.inSeconds}s)");
        await Future.delayed(backoffDelay);
      }
    }
    return null;
  }

  Future<List<dynamic>> fetchAEDLocations() async {
    return await _retryOperation<List<dynamic>>(() async {
      try {
        final url = Uri.parse('$baseUrl/aed');
        final response = await http.get(
          url,
          headers: {'Accept': 'application/json'},
        ).timeout(AppConstants.networkTimeout);
        if (response.statusCode == 200) {
          final lastUpdated = response.headers['x-data-last-updated'];
          final totalAEDs = response.headers['x-total-aeds'];

          if (lastUpdated != null) {
            print("🕒 Backend last synced from iSaveLives: $lastUpdated");

            try {
              final backendSyncTime = DateTime.parse(lastUpdated);
              await _prefs.setInt(_lastSyncKey, backendSyncTime.millisecondsSinceEpoch);
              print("💾 Saved backend sync timestamp: $backendSyncTime");
            } catch (e) {
              print("⚠️ Error parsing backend sync time: $e");
            }
          }

          if (totalAEDs != null) {
            print("📊 Total AEDs from backend: $totalAEDs");
          }

          final List<dynamic> data = jsonDecode(response.body);
          print("✅ Fetched ${data.length} AEDs from backend");
          return data;
        } else {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        print("❌ Error fetching AED locations: $e");
        rethrow;
      }
    }) ?? [];
  }

  static const String _lastSyncKey = 'last_sync_timestamp';

  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastSyncKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    } catch (e) {
      print("⚠️ Error getting last sync time: $e");
    }
    return null;
  }

  static Future<String> getFormattedSyncTime() async {
    final syncTime = await getLastSyncTime();

    if (syncTime == null) return 'Never synced';

    final now = DateTime.now();
    final difference = now.difference(syncTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w ago';
    }
  }

  static String? get googleMapsApiKey {
    final key = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (key == null || key.isEmpty) {
      print("❌ GOOGLE_MAPS_API_KEY is missing from .env");
      return null;
    }
    return key;
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