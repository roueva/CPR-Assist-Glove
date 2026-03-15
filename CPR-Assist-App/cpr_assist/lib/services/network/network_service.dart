import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NetworkService
//
// Pure service layer — no colors, no spacing, no UI widgets.
// All debug output goes through debugPrint (stripped in release builds).
// ─────────────────────────────────────────────────────────────────────────────

class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  late final SharedPreferences _prefs;

  Future<void> initialize(SharedPreferences prefs) async {
    _prefs = prefs;
  }

  // ── Connectivity monitoring ───────────────────────────────────────────────

  static StreamController<bool>? _connectivityController;
  static bool _lastConnectivityState = true;
  static Timer? _connectivityTimer;
  static final List<void Function(bool)> _connectivityListeners = [];

  static void startConnectivityMonitoring({
    Duration interval = AppConstants.connectivityCheckInterval,
  }) {
    _connectivityTimer?.cancel();
    _connectivityController ??= StreamController<bool>.broadcast();

    _connectivityTimer = Timer.periodic(interval, (_) async {
      final connected = await isConnected();
      if (connected != _lastConnectivityState) {
        _lastConnectivityState = connected;
        _connectivityController?.add(connected);
        for (final listener in _connectivityListeners) {
          listener(connected);
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

  static bool get lastKnownConnectivityState => _lastConnectivityState;

  static void addConnectivityListener(void Function(bool) listener) {
    if (!_connectivityListeners.contains(listener)) _connectivityListeners.add(listener);
  }

  static void removeConnectivityListener(void Function(bool) listener) {
    _connectivityListeners.remove(listener);
  }

  static void clearAllListeners() => _connectivityListeners.clear();

  // ── Connectivity checks ───────────────────────────────────────────────────

  static Future<bool> isConnected() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none) || results.isEmpty) {
        return false;
      }

      final lookup = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canReachBackend() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Base URL & API keys ───────────────────────────────────────────────────

  static String get baseUrl {
    final url = dotenv.env['BASE_URL'];
    if (url == null || url.isEmpty) throw Exception('BASE_URL missing from .env');
    return url;
  }

  static String? get googleMapsApiKey {
    final key = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (key == null || key.isEmpty) {
      debugPrint('GOOGLE_MAPS_API_KEY missing from .env');
      return null;
    }
    return key;
  }

  // ── Token management ──────────────────────────────────────────────────────

  Future<int?> getUserId() async => _prefs.getInt('user_id');
  Future<void> saveUserId(int userId) async => _prefs.setInt('user_id', userId);

  Future<String?> getToken() async => _prefs.getString('jwt_token');
  Future<void> saveToken(String token) async => _prefs.setString('jwt_token', token);
  Future<void> removeToken() async {
    await _prefs.remove('jwt_token');
    await _prefs.remove('user_id');
  }

  Future<bool> isTokenValid() async {
    final token = await getToken();
    if (token == null) return false;
    try {
      return !JwtDecoder.isExpired(token);
    } catch (_) {
      return false;
    }
  }

  Future<bool> refreshToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      ).timeout(AppConstants.apiTimeout);

      if (response.statusCode == 200) {
        final body   = jsonDecode(response.body) as Map<String, dynamic>;
        final newTok = body['token'] as String?;
        final uid    = body['user_id'] as int?;
        if (newTok != null && uid != null) {
          await saveToken(newTok);
          await saveUserId(uid);
          return true;
        }
      }
    } catch (e) {
      debugPrint('refreshToken error: $e');
    }
    return false;
  }

  Future<bool> ensureAuthenticated() async {
    if (await isTokenValid()) return true;
    try {
      final refreshed = await refreshToken();
      if (!refreshed) await removeToken();
      return refreshed;
    } on SocketException {
      // Offline — don't wipe the token, the user is just not connected
      return false;
    }
  }

  // ── Generic HTTP ──────────────────────────────────────────────────────────

  Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {bool requiresAuth = false}) =>
      _makeRequest('POST', endpoint, body: body, requiresAuth: requiresAuth);

  Future<dynamic> get(String endpoint, {bool requiresAuth = false}) =>
      _makeRequest('GET', endpoint, requiresAuth: requiresAuth);

  Future<dynamic> put(String endpoint, Map<String, dynamic> body,
      {bool requiresAuth = false}) =>
      _makeRequest('PUT', endpoint, body: body, requiresAuth: requiresAuth);

  Future<dynamic> patch(String endpoint, Map<String, dynamic> body,
      {bool requiresAuth = false}) =>
      _makeRequest('PATCH', endpoint, body: body, requiresAuth: requiresAuth);

  Future<dynamic> _makeRequest(
      String method,
      String endpoint, {
        Map<String, dynamic>? body,
        bool requiresAuth = false,
      }) async {
    final url   = Uri.parse('$baseUrl$endpoint');
    final token = await getToken();

    if (requiresAuth && (token == null || token.isEmpty)) {
      throw Exception('Unauthorized: missing token.');
    }

    final headers = {
      'Content-Type': 'application/json',
      if (requiresAuth) 'Authorization': 'Bearer $token',
    };

    try {
      final http.Response response;
      switch (method) {
        case 'POST':
          response = await http.post(url, headers: headers, body: jsonEncode(body))
              .timeout(AppConstants.apiTimeout);
        case 'PUT':
          response = await http.put(url, headers: headers, body: jsonEncode(body))
              .timeout(AppConstants.apiTimeout);
        case 'PATCH':
          response = await http.patch(url, headers: headers, body: jsonEncode(body))
              .timeout(AppConstants.apiTimeout);
        default:
          response = await http.get(url, headers: headers)
              .timeout(AppConstants.apiTimeout);
      }
      return _handleResponse(response, endpoint, method,
          body: body, requiresAuth: requiresAuth);
    } on TimeoutException {
      throw Exception('Request timed out — check your connection.');
    } on SocketException {
      throw Exception('No internet connection.');
    }
  }

  Future<dynamic> _handleResponse(
      http.Response response,
      String endpoint,
      String method, {
        Map<String, dynamic>? body,
        bool requiresAuth = false,
      }) async {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    }

    if (response.statusCode == 401 && requiresAuth) {
      final refreshed = await refreshToken();
      if (refreshed) {
        return _makeRequest(method, endpoint, body: body, requiresAuth: requiresAuth);
      }
      await removeToken();
      throw Exception('401 Unauthorized — token refresh failed.');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final msg  = json['errors'] ?? json['error'] ?? json['message'] ?? 'Unknown error';
    throw Exception('HTTP ${response.statusCode}: $msg');
  }

  // ── Retry wrapper ─────────────────────────────────────────────────────────

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
        if (e is! SocketException && e is! TimeoutException) rethrow;
        final delay = initialDelay * (1 << i);
        debugPrint('Retry ${i + 1}/$maxRetries after $e (wait ${delay.inSeconds}s)');
        await Future.delayed(delay);
      }
    }
    return null;
  }

  // ── AED fetch ─────────────────────────────────────────────────────────────

  Future<List<dynamic>> fetchAEDLocations() async {
    return await _retryOperation<List<dynamic>>(() async {
      final response = await http.get(
        Uri.parse('$baseUrl/aed'),
        headers: {'Accept': 'application/json'},
      ).timeout(AppConstants.networkTimeout);

      if (response.statusCode == 200) {
        final lastUpdated = response.headers['x-data-last-updated'];
        if (lastUpdated != null) {
          try {
            final ts = DateTime.parse(lastUpdated).millisecondsSinceEpoch;
            await _prefs.setInt(_lastSyncKey, ts);
          } catch (_) {}
        }
        return jsonDecode(response.body) as List<dynamic>;
      }

      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }) ?? [];
  }

  // ── Sync timestamp helpers ────────────────────────────────────────────────

  static const String _lastSyncKey = 'last_sync_timestamp';

  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts    = prefs.getInt(_lastSyncKey);
      if (ts != null) return DateTime.fromMillisecondsSinceEpoch(ts);
    } catch (_) {}
    return null;
  }

  static Future<String> getFormattedSyncTime() async {
    final syncTime = await getLastSyncTime();
    if (syncTime == null) return 'Never synced';

    final diff = DateTime.now().difference(syncTime);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inHours   < 1)  return '${diff.inMinutes}m ago';
    if (diff.inDays    < 1)  return '${diff.inHours}h ago';
    if (diff.inDays    < 7)  return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  // ── External GET ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getExternal(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('getExternal error: $e');
    }
    return null;
  }
}