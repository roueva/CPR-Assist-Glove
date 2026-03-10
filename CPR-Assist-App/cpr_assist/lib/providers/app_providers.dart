import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/decrypted_data.dart';
import '../services/ble_connection.dart';
import '../services/network_service.dart';
import '../services/aed_map/aed_service.dart';
import '../models/aed_models.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ============================================================================
// INFRASTRUCTURE PROVIDERS (Foundation layer)
// ============================================================================

/// SharedPreferences - Must be overridden in main()
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

final cacheAvailabilityProvider = Provider<bool>((ref) {
  throw UnimplementedError('Cache availability must be overridden in main()');
});

// ============================================================================
// ENUMS
// ============================================================================

/// App operating mode
enum AppMode {
  emergency,  // Real cardiac arrest - no performance tracking
  training,   // Practice CPR with feedback and grading
}

// ============================================================================
// SERVICE PROVIDERS (Business logic layer)
// ============================================================================

/// Network Service - Singleton instance
final networkServiceProvider = Provider<NetworkService>((ref) {
  return NetworkService(); // ✅ Returns singleton instance
});

/// Decrypted Data Handler (BLE data processing)
final decryptedDataProvider = Provider<DecryptedData>((ref) {
  return DecryptedData();
});

/// BLE Connection Service
final bleConnectionProvider = Provider<BLEConnection>((ref) {
  final decryptedDataHandler = ref.watch(decryptedDataProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  return BLEConnection(
    decryptedDataHandler: decryptedDataHandler,
    prefs: prefs,
    onStatusUpdate: (status) {
      print("🔵 BLE Status: $status");
    },
  );
});

/// AED Service
final aedServiceProvider = Provider<AEDService>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return AEDService(networkService);
});

// ============================================================================
// STATE PROVIDERS (Application state layer)
// ============================================================================

/// Authentication State
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return AuthNotifier(networkService, prefs);
});

/// App Mode Provider (Emergency vs Training)
final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode>((ref) {
  return AppModeNotifier();
});

class AppModeNotifier extends StateNotifier<AppMode> {
  AppModeNotifier() : super(AppMode.emergency);

  void setMode(AppMode mode) {
    state = mode;
  }

  void toggleMode() {
    state = state == AppMode.emergency ? AppMode.training : AppMode.emergency;
  }
}

/// CPR Session Active Provider (to disable mode switching during CPR)
final cprSessionActiveProvider = StateProvider<bool>((ref) => false);

/// AED Map State
final mapStateProvider = StateNotifierProvider<MapStateNotifier, AEDMapState>((ref) {
  return MapStateNotifier(); // ✅ No ref parameter
});

// ============================================================================
// STATE CLASSES
// ============================================================================

class AuthState {
  final bool isLoggedIn;
  final int? userId;
  final String? username;
  final bool isLoading;
  final String? email;

  AuthState({
    required this.isLoggedIn,
    this.userId,
    this.username,
    this.isLoading = false,
    this.email,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    int? userId,
    String? username,
    bool? isLoading,
    String? email,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      isLoading: isLoading ?? this.isLoading,
      email: email ?? this.email,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final NetworkService _networkService;
  final SharedPreferences _prefs;

  AuthNotifier(this._networkService, this._prefs)
      : super(AuthState(isLoggedIn: false));

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    final isAuthenticated = await _networkService.ensureAuthenticated();
    final userId = await _networkService.getUserId();
    final username = _prefs.getString('username');

    state = state.copyWith(
      isLoggedIn: isAuthenticated,
      userId: userId,
      username: username,
      isLoading: false,
    );
  }

  Future<void> logout() async {
    await _networkService.removeToken();
    await _prefs.remove('isLoggedIn');
    await _prefs.remove('username');
    await _prefs.remove('user_id');

    state = AuthState(isLoggedIn: false);
  }

  Future<void> login(String token, int userId, String username) async {
    state = state.copyWith(isLoading: true);

    await _networkService.saveToken(token);
    await _networkService.saveUserId(userId);
    await _prefs.setBool('isLoggedIn', true);
    await _prefs.setString('username', username);

    state = state.copyWith(
      isLoggedIn: true,
      userId: userId,
      username: username,
      isLoading: false,
    );
  }

  // Update username locally and in SharedPreferences.
  // Call this AFTER your backend PUT /auth/profile succeeds.
  Future<void> updateUsername(String newUsername) async {
    await _prefs.setString('username', newUsername);
    state = state.copyWith(username: newUsername);
  }

  // Update email locally and in SharedPreferences.
  Future<void> updateEmail(String newEmail) async {
    await _prefs.setString('email', newEmail);
    state = state.copyWith(email: newEmail);
  }
}

// AED Map State
class AEDMapState {
  final List<AED> aedList;
  final LatLng? userLocation;
  final bool isLoading;
  final bool isRefreshing;
  final bool isOffline;
  final NavigationState navigation;

  const AEDMapState({
    this.aedList = const [],
    this.userLocation,
    this.isLoading = false,
    this.isRefreshing = false,
    this.isOffline = false,
    this.navigation = const NavigationState(),
  });

  AEDMapState copyWith({
    List<AED>? aedList,
    LatLng? userLocation,
    bool? isLoading,
    bool? isRefreshing,
    bool? isOffline,
    NavigationState? navigation,
  }) {
    return AEDMapState(
      aedList: aedList ?? this.aedList,
      userLocation: userLocation ?? this.userLocation,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isOffline: isOffline ?? this.isOffline,
      navigation: navigation ?? this.navigation,
    );
  }
}

class NavigationState {
  final bool isActive;
  final bool hasStarted;
  final LatLng? destination;
  final Polyline? route;
  final String estimatedTime;
  final double distance;
  final String transportMode;
  final double? originalDistance;
  final int? originalDurationMinutes;

  const NavigationState({
    this.isActive = false,
    this.hasStarted = false,
    this.destination,
    this.route,
    this.estimatedTime = '',
    this.distance = 0,
    this.transportMode = 'walking',
    this.originalDistance,
    this.originalDurationMinutes,
  });

  NavigationState copyWith({
    bool? isActive,
    bool? hasStarted,
    LatLng? destination,
    Polyline? route,
    String? estimatedTime,
    double? distance,
    String? transportMode,
    double? originalDistance,
    int? originalDurationMinutes,
  }) {
    return NavigationState(
      isActive: isActive ?? this.isActive,
      hasStarted: hasStarted ?? this.hasStarted,
      destination: destination ?? this.destination,
      route: route ?? this.route,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      distance: distance ?? this.distance,
      transportMode: transportMode ?? this.transportMode,
      originalDistance: originalDistance ?? this.originalDistance,
      originalDurationMinutes: originalDurationMinutes ?? this.originalDurationMinutes,
    );
  }
}

class MapStateNotifier extends StateNotifier<AEDMapState> {
  MapStateNotifier() : super(const AEDMapState()); // ✅ No ref parameter

  bool get isInNavigationMode => state.navigation.hasStarted;
  bool get isInPreviewMode => state.navigation.isActive && !state.navigation.hasStarted;

  void updateUserLocation(LatLng location) {
    state = state.copyWith(userLocation: location);
  }

  void setAEDs(List<AED> aeds) {
    state = state.copyWith(
      aedList: aeds,
      isLoading: false,
      isRefreshing: false,
    );
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setRefreshing(bool refreshing) {
    state = state.copyWith(isRefreshing: refreshing);
  }

  void setOffline(bool offline) {
    state = state.copyWith(isOffline: offline);
  }

  void showNavigationPreview(LatLng destination) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        isActive: true,
        destination: destination,
        hasStarted: false,
      ),
    );
  }

  void startNavigation(LatLng destination) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        isActive: true,
        destination: destination,
        hasStarted: true,
      ),
    );
  }

  void updateRoute(Polyline? route, String estimatedTime, double distance) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        route: route,
        estimatedTime: estimatedTime,
        distance: distance,
      ),
    );
  }

  void setOriginalRouteMetrics({
    required double originalDistance,
    required int originalDurationMinutes,
  }) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        originalDistance: originalDistance,
        originalDurationMinutes: originalDurationMinutes,
      ),
    );
  }

  void updateTransportMode(String mode) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(transportMode: mode),
    );
  }

  void cancelNavigation() {
    state = state.copyWith(navigation: const NavigationState());
  }

  void updateAEDsAndMarkers(List<AED> aeds) {
    state = state.copyWith(aedList: aeds);
  }
}