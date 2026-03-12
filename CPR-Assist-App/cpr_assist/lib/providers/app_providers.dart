import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/aed_map/services/aed_service.dart';
import '../models/aed_models.dart';
import '../services/ble/ble_connection.dart';
import '../services/network/network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// INFRASTRUCTURE PROVIDERS  (must be overridden in main())
// ─────────────────────────────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

final cacheAvailabilityProvider = Provider<bool>((ref) {
  throw UnimplementedError('cacheAvailabilityProvider must be overridden in main()');
});

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

final networkServiceProvider = Provider<NetworkService>((ref) {
  return NetworkService(); // singleton
});

/// BLE connection — owns the glove link for the app lifetime.
/// Battery & charging notifiers live on [BLEConnection] directly;
/// no separate DecryptedData class is needed.
final bleConnectionProvider = Provider<BLEConnection>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);

  final connection = BLEConnection(
    prefs: prefs,
    onStatusUpdate: (status) => debugPrint('BLE: $status'),
  );

  ref.onDispose(connection.dispose);
  return connection;
});

final aedServiceProvider = Provider<AEDService>((ref) {
  final network = ref.watch(networkServiceProvider);
  return AEDService(network);
});

// ─────────────────────────────────────────────────────────────────────────────
// APP MODE
// ─────────────────────────────────────────────────────────────────────────────

/// Whether the app is in Emergency (no login required) or Training (login required) mode.
enum AppMode { emergency, training }

final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode>((ref) {
  return AppModeNotifier();
});

class AppModeNotifier extends StateNotifier<AppMode> {
  AppModeNotifier() : super(AppMode.emergency);

  void setMode(AppMode mode) => state = mode;

  void toggleMode() =>
      state = state == AppMode.emergency ? AppMode.training : AppMode.emergency;
}

/// True while a CPR session is active — disables mode switching.
final cprSessionActiveProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
// AUTHENTICATION
// ─────────────────────────────────────────────────────────────────────────────

final authStateProvider =
StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final network = ref.watch(networkServiceProvider);
  final prefs   = ref.watch(sharedPreferencesProvider);
  return AuthNotifier(network, prefs);
});

class AuthState {
  final bool isLoggedIn;
  final int?    userId;
  final String? username;
  final String? email;
  final bool    isLoading;

  const AuthState({
    required this.isLoggedIn,
    this.userId,
    this.username,
    this.email,
    this.isLoading = false,
  });

  AuthState copyWith({
    bool?   isLoggedIn,
    int?    userId,
    String? username,
    String? email,
    bool?   isLoading,
  }) =>
      AuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        userId:     userId     ?? this.userId,
        username:   username   ?? this.username,
        email:      email      ?? this.email,
        isLoading:  isLoading  ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final NetworkService     _network;
  final SharedPreferences  _prefs;

  AuthNotifier(this._network, this._prefs)
      : super(const AuthState(isLoggedIn: false));

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);
    final authenticated = await _network.ensureAuthenticated();
    state = state.copyWith(
      isLoggedIn: authenticated,
      userId:     await _network.getUserId(),
      username:   _prefs.getString('username'),
      email: _prefs.getString('email'),
      isLoading:  false,
    );
  }

  Future<void> login(String token, int userId, String username) async {
    state = state.copyWith(isLoading: true);
    await _network.saveToken(token);
    await _network.saveUserId(userId);
    await _prefs.setBool('isLoggedIn', true);
    await _prefs.setString('username', username);
    state = state.copyWith(
      isLoggedIn: true,
      userId:     userId,
      username:   username,
      isLoading:  false,
    );
    unawaited(_fetchAndStoreEmail());
  }

  Future<void> logout() async {
    await _network.removeToken();
    await _prefs.remove('isLoggedIn');
    await _prefs.remove('username');
    await _prefs.remove('user_id');
    state = const AuthState(isLoggedIn: false);
  }

  Future<void> updateUsername(String newUsername) async {
    await _prefs.setString('username', newUsername);
    state = state.copyWith(username: newUsername);
  }

  Future<void> updateEmail(String newEmail) async {
    await _prefs.setString('email', newEmail);
    state = state.copyWith(email: newEmail);
  }

  Future<void> _fetchAndStoreEmail() async {
    try {
      final response = await _network.get('/auth/profile', requiresAuth: true);
      if (response['success'] == true) {
        final email = response['data']?['email'] as String?;
        if (email != null) {
          await _prefs.setString('email', email);
          state = state.copyWith(email: email);
        }
      }
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AED MAP STATE
// ─────────────────────────────────────────────────────────────────────────────

final mapStateProvider =
StateNotifierProvider<MapStateNotifier, AEDMapState>((ref) {
  return MapStateNotifier();
});

class AEDMapState {
  final List<AED> aedList;
  final LatLng? userLocation;
  final bool isLoading;
  final bool isRefreshing;
  final bool isOffline;
  final NavigationState navigation;

  const AEDMapState({
    this.aedList       = const [],
    this.userLocation,
    this.isLoading     = false,
    this.isRefreshing  = false,
    this.isOffline     = false,
    this.navigation    = const NavigationState(),
  });

  AEDMapState copyWith({
    List<AED>?       aedList,
    LatLng?          userLocation,
    bool?            isLoading,
    bool?            isRefreshing,
    bool?            isOffline,
    NavigationState? navigation,
  }) =>
      AEDMapState(
        aedList:      aedList      ?? this.aedList,
        userLocation: userLocation ?? this.userLocation,
        isLoading:    isLoading    ?? this.isLoading,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        isOffline:    isOffline    ?? this.isOffline,
        navigation:   navigation   ?? this.navigation,
      );
}

class NavigationState {
  final bool     isActive;
  final bool     hasStarted;
  final LatLng?  destination;
  final Polyline? route;
  final String   estimatedTime;
  final double   distance;
  final String   transportMode;
  final double?  originalDistance;
  final int?     originalDurationMinutes;

  const NavigationState({
    this.isActive               = false,
    this.hasStarted             = false,
    this.destination,
    this.route,
    this.estimatedTime          = '',
    this.distance               = 0,
    this.transportMode          = 'walking',
    this.originalDistance,
    this.originalDurationMinutes,
  });

  NavigationState copyWith({
    bool?     isActive,
    bool?     hasStarted,
    LatLng?   destination,
    Polyline? route,
    String?   estimatedTime,
    double?   distance,
    String?   transportMode,
    double?   originalDistance,
    int?      originalDurationMinutes,
  }) =>
      NavigationState(
        isActive:               isActive               ?? this.isActive,
        hasStarted:             hasStarted             ?? this.hasStarted,
        destination:            destination            ?? this.destination,
        route:                  route                  ?? this.route,
        estimatedTime:          estimatedTime          ?? this.estimatedTime,
        distance:               distance               ?? this.distance,
        transportMode:          transportMode          ?? this.transportMode,
        originalDistance:       originalDistance       ?? this.originalDistance,
        originalDurationMinutes: originalDurationMinutes ?? this.originalDurationMinutes,
      );
}

class MapStateNotifier extends StateNotifier<AEDMapState> {
  MapStateNotifier() : super(const AEDMapState());

  bool get isInNavigationMode =>  state.navigation.hasStarted;
  bool get isInPreviewMode    =>  state.navigation.isActive && !state.navigation.hasStarted;

  void updateUserLocation(LatLng location) =>
      state = state.copyWith(userLocation: location);

  void setAEDs(List<AED> aeds) =>
      state = state.copyWith(aedList: aeds, isLoading: false, isRefreshing: false);

  void setLoading(bool v)     => state = state.copyWith(isLoading: v);
  void setRefreshing(bool v)  => state = state.copyWith(isRefreshing: v);
  void setOffline(bool v)     => state = state.copyWith(isOffline: v);
  void updateAEDs(List<AED> aeds) => state = state.copyWith(aedList: aeds);

  void showNavigationPreview(LatLng destination) => state = state.copyWith(
    navigation: state.navigation.copyWith(
      isActive: true, destination: destination, hasStarted: false,
    ),
  );

  void startNavigation(LatLng destination) => state = state.copyWith(
    navigation: state.navigation.copyWith(
      isActive: true, destination: destination, hasStarted: true,
    ),
  );

  void updateRoute(Polyline? route, String estimatedTime, double distance) =>
      state = state.copyWith(
        navigation: state.navigation.copyWith(
          route: route, estimatedTime: estimatedTime, distance: distance,
        ),
      );

  void setOriginalRouteMetrics({
    required double originalDistance,
    required int    originalDurationMinutes,
  }) =>
      state = state.copyWith(
        navigation: state.navigation.copyWith(
          originalDistance: originalDistance,
          originalDurationMinutes: originalDurationMinutes,
        ),
      );

  void updateTransportMode(String mode) => state = state.copyWith(
    navigation: state.navigation.copyWith(transportMode: mode),
  );

  void cancelNavigation() =>
      state = state.copyWith(navigation: const NavigationState());
}