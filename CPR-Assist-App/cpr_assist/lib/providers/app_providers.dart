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
  return NetworkService();
});

/// BLE connection — owns the glove link for the app lifetime.
final bleConnectionProvider = Provider<BLEConnection>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final connection = BLEConnection(
    prefs: prefs,
    onStatusUpdate: (status) => debugPrint('BLE: $status'),
  );
  ref.onDispose(connection.dispose);
  // Re-sync mode + scenario every time the glove reconnects from a reboot.
  connection.setReconnectSyncCallback(() {
    final mode     = ref.read(appModeProvider);
    final scenario = ref.read(scenarioProvider);
    connection.sendSyncTime();
    connection.sendModeSet(mode.bleValue);
    connection.sendSetScenario(scenario.bleValue);
    connection.sendSetTargetDepth(
      minMm: scenario.targetDepthMinMm,
      maxMm: scenario.targetDepthMaxMm,
    );
    connection.sendSetTargetRate(
      minBpm: scenario.targetRateMin,
      maxBpm: scenario.targetRateMax,
    );
    final settings = ref.read(settingsProvider);
    final feedbackOn = settings.hapticFeedback || settings.audioFeedback;
    connection.sendFeedbackSet(enabled: feedbackOn);
  });
  return connection;
});


final aedServiceProvider = Provider<AEDService>((ref) {
  final network = ref.watch(networkServiceProvider);
  return AEDService(network);
});

// ─────────────────────────────────────────────────────────────────────────────
// APP MODE
//
// Three glove modes, matching the BLE spec byte values exactly:
//   emergency           (0) — no login required, no grade, full feedback
//   training            (1) — login required, graded, full feedback
//   trainingNoFeedback  (2) — login required, graded, all feedback suppressed
//
// Mode can be changed by:
//   - App UI (mode toggle / settings)
//   - Glove button hold 1s → MODE_CHANGE (0x06) event received by BLEConnection
//
// When the glove fires MODE_CHANGE, live_cpr_screen.dart calls
// ref.read(appModeProvider.notifier).setModeFromGlove(byte) to sync app state.
// ─────────────────────────────────────────────────────────────────────────────

enum AppMode {
  emergency,
  training,
  trainingNoFeedback;

  /// Convert to the BLE spec integer (byte value sent in SESSION_START / MODE_CHANGE).
  int get bleValue {
    switch (this) {
      case AppMode.emergency:          return 0;
      case AppMode.training:           return 1;
      case AppMode.trainingNoFeedback: return 2;
    }
  }

  /// Convert to the string stored in SessionDetail.mode and sent to backend.
  String get sessionModeString {
    switch (this) {
      case AppMode.emergency:          return 'emergency';
      case AppMode.training:           return 'training';
      case AppMode.trainingNoFeedback: return 'training_no_feedback';
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case AppMode.emergency:          return 'Emergency';
      case AppMode.training:           return 'Training';
      case AppMode.trainingNoFeedback: return 'No-Feedback';
    }
  }

  bool get isEmergency  => this == AppMode.emergency;
  bool get isTraining   => this == AppMode.training || this == AppMode.trainingNoFeedback;
  bool get isNoFeedback => this == AppMode.trainingNoFeedback;

  /// Construct from glove BLE byte. Clamps unknown values to emergency.
  static AppMode fromBleValue(int value) {
    switch (value) {
      case 1:  return AppMode.training;
      case 2:  return AppMode.trainingNoFeedback;
      default: return AppMode.emergency;
    }
  }
}

final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode>((ref) {
  return AppModeNotifier();
});

class AppModeNotifier extends StateNotifier<AppMode> {
  AppModeNotifier() : super(AppMode.emergency);

  void setMode(AppMode mode) => state = mode;

  /// Called when glove fires MODE_CHANGE (0x06).
  /// Syncs app state to what the hardware is actually running.
  void setModeFromGlove(int bleValue) => state = AppMode.fromBleValue(bleValue);

  /// Cycle forward through all three modes (for app-side mode toggle button).
  void cycleMode() {
    switch (state) {
      case AppMode.emergency:          state = AppMode.training;           break;
      case AppMode.training:           state = AppMode.trainingNoFeedback; break;
      case AppMode.trainingNoFeedback: state = AppMode.emergency;          break;
    }
  }
}

/// True while a CPR session is active — disables mode and scenario switching.
final cprSessionActiveProvider = StateProvider<bool>((ref) => false);

// ─────────────────────────────────────────────────────────────────────────────
// CPR SCENARIO
//
// Scenario is an app-side concept that maps to numeric depth/rate targets
// sent to the glove via 0xF8 SET_TARGET_DEPTH and 0xF9 SET_TARGET_RATE.
// The glove itself only knows the numeric thresholds, not the scenario label.
//
// Scenario can be changed by:
//   - App UI: Adult/Pediatric toggle on the live CPR screen (Emergency mode)
//             or scenario selector before a Training session starts
//   - Glove button long press (2s) → SCENARIO_CHANGE (0x0C) event
//
// When the glove fires SCENARIO_CHANGE, live_cpr_screen.dart calls
// ref.read(scenarioProvider.notifier).setFromGlove(byte).
//
// Scenario switching is allowed during idle (no active session).
// During an active session it is locked to protect session record integrity.
// ─────────────────────────────────────────────────────────────────────────────

enum CprScenario {
  standardAdult,
  pediatric,
  timedEndurance;

  /// Byte value sent in SCENARIO_CHANGE (0x0C) and 0xFD SET_SCENARIO.
  int get bleValue {
    switch (this) {
      case CprScenario.standardAdult:  return 0;
      case CprScenario.pediatric:      return 1;
      case CprScenario.timedEndurance: return 2;
    }
  }

  /// String stored in SessionDetail.scenario and sent to backend.
  String get sessionScenarioString {
    switch (this) {
      case CprScenario.standardAdult: return 'standard_adult';
      case CprScenario.pediatric:     return 'pediatric';
      case CprScenario.timedEndurance: return 'timed_endurance';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case CprScenario.standardAdult:  return 'Adult';
      case CprScenario.pediatric:      return 'Pediatric';
      case CprScenario.timedEndurance: return 'Timed';
    }
  }

  /// Short description shown on the live CPR screen toggle.
  String get description {
    switch (this) {
      case CprScenario.standardAdult: return 'Adult — 5–6 cm';
      case CprScenario.pediatric:     return 'Pediatric — 4–5 cm';
      case CprScenario.timedEndurance: return 'Timed — 2 min endurance';
    }
  }

  /// Depth target range in mm for this scenario.
  int get targetDepthMinMm {
    switch (this) {
      case CprScenario.pediatric:      return 40;
      case CprScenario.timedEndurance:
      case CprScenario.standardAdult:  return 50;
    }
  }
  int get targetDepthMaxMm {
    switch (this) {
      case CprScenario.pediatric:      return 50;
      case CprScenario.timedEndurance:
      case CprScenario.standardAdult:  return 60;
    }
  }

  /// Depth target range in cm (for display and grading).
  double get targetDepthMinCm => targetDepthMinMm / 10.0;
  double get targetDepthMaxCm => targetDepthMaxMm / 10.0;

  /// Rate targets are the same for both scenarios (100–120 BPM per AHA/ERC).
  int get targetRateMin => 100;
  int get targetRateMax => 120;

  /// Construct from glove BLE byte. Unknown values default to standardAdult.
  static CprScenario fromBleValue(int value) {
    switch (value) {
      case 1:  return CprScenario.pediatric;
      case 2:  return CprScenario.timedEndurance;
      default: return CprScenario.standardAdult;
    }
  }

  /// Construct from the scenario string stored in SessionDetail / backend.
  static CprScenario fromString(String value) {
    switch (value) {
      case 'pediatric':       return CprScenario.pediatric;
      case 'timed_endurance': return CprScenario.timedEndurance;
      default:                return CprScenario.standardAdult;
    }
  }
}

final scenarioProvider = StateNotifierProvider<ScenarioNotifier, CprScenario>((ref) {
  final defaultScenario = ref.watch(settingsProvider).defaultScenario;
  return ScenarioNotifier(defaultScenario);
});

class ScenarioNotifier extends StateNotifier<CprScenario> {
  ScenarioNotifier(String defaultScenario)
      : super(CprScenario.fromString(defaultScenario));

  void setScenario(CprScenario s) => state = s;

  /// Toggle between adult and pediatric and timed endurance.
  void toggle() {
    switch (state) {
      case CprScenario.standardAdult:  state = CprScenario.pediatric;      break;
      case CprScenario.pediatric:      state = CprScenario.timedEndurance;  break;
      case CprScenario.timedEndurance: state = CprScenario.standardAdult;   break;
    }
  }

  /// Called when glove fires SCENARIO_CHANGE (0x0C).
  void setFromGlove(int bleValue) => state = CprScenario.fromBleValue(bleValue);
}

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
  final bool    isLoggedIn;
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
      email:      _prefs.getString('email'),
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
  final bool      isActive;
  final bool      hasStarted;
  final LatLng?   destination;
  final Polyline? route;
  final String    estimatedTime;
  final double    distance;
  final String    transportMode;
  final double?   originalDistance;
  final int?      originalDurationMinutes;

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

  bool get isInNavigationMode => state.navigation.hasStarted;
  bool get isInPreviewMode    => state.navigation.isActive && !state.navigation.hasStarted;

  void updateUserLocation(LatLng location) =>
      state = state.copyWith(userLocation: location);

  void setAEDs(List<AED> aeds) =>
      state = state.copyWith(aedList: aeds, isLoading: false, isRefreshing: false);

  void setLoading(bool v)    => state = state.copyWith(isLoading: v);
  void setRefreshing(bool v) => state = state.copyWith(isRefreshing: v);
  void setOffline(bool v)    => state = state.copyWith(isOffline: v);
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
          originalDistance:       originalDistance,
          originalDurationMinutes: originalDurationMinutes,
        ),
      );

  void updateTransportMode(String mode) => state = state.copyWith(
    navigation: state.navigation.copyWith(transportMode: mode),
  );

  void cancelNavigation() =>
      state = state.copyWith(navigation: const NavigationState());
}

// ─────────────────────────────────────────────────────────────────────────────
// APP SETTINGS
//
// All user-configurable toggles persisted via SharedPreferences.
// Keys are intentionally prefixed with 'settings_' to avoid collisions.
// ─────────────────────────────────────────────────────────────────────────────

class AppSettings {
  final bool   hapticFeedback;
  final bool   audioFeedback;
  final bool   keepScreenOn;
  final bool   autoSwitchToCPR;
  final bool   showDepthGuide;
  final bool   showRateGuide;
  final bool   notifyOnDisconnect;
  final String compressionUnit; // 'cm' | 'in'
  final bool   showChecklist;   // true = show pre-session checklist before training
  final String defaultScenario; // 'standard_adult' | 'pediatric' | 'timed_endurance'

  const AppSettings({
    this.hapticFeedback      = true,
    this.audioFeedback       = true,
    this.keepScreenOn        = true,
    this.autoSwitchToCPR     = true,
    this.showDepthGuide      = true,
    this.showRateGuide       = true,
    this.notifyOnDisconnect  = true,
    this.compressionUnit     = 'cm',
    this.showChecklist       = true,
    this.defaultScenario = 'standard_adult',
  });

  AppSettings copyWith({
    bool?   hapticFeedback,
    bool?   audioFeedback,
    bool?   keepScreenOn,
    bool?   autoSwitchToCPR,
    bool?   showDepthGuide,
    bool?   showRateGuide,
    bool?   notifyOnDisconnect,
    String? compressionUnit,
    bool?   showChecklist,
    String? defaultScenario,
  }) =>
      AppSettings(
        hapticFeedback:     hapticFeedback     ?? this.hapticFeedback,
        audioFeedback:      audioFeedback      ?? this.audioFeedback,
        keepScreenOn:       keepScreenOn       ?? this.keepScreenOn,
        autoSwitchToCPR:    autoSwitchToCPR    ?? this.autoSwitchToCPR,
        showDepthGuide:     showDepthGuide     ?? this.showDepthGuide,
        showRateGuide:      showRateGuide      ?? this.showRateGuide,
        notifyOnDisconnect: notifyOnDisconnect ?? this.notifyOnDisconnect,
        compressionUnit:    compressionUnit    ?? this.compressionUnit,
        showChecklist:      showChecklist      ?? this.showChecklist,
        defaultScenario:    defaultScenario    ?? this.defaultScenario,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _prefs;

  static const _kHaptic      = 'settings_hapticFeedback';
  static const _kAudio       = 'settings_audioFeedback';
  static const _kScreenOn    = 'settings_keepScreenOn';
  static const _kAutoSwitch  = 'settings_autoSwitchToCPR';
  static const _kDepthGuide  = 'settings_showDepthGuide';
  static const _kRateGuide   = 'settings_showRateGuide';
  static const _kDisconnect  = 'settings_notifyOnDisconnect';
  static const _kUnit        = 'settings_compressionUnit';
  static const _kChecklist = 'settings_showChecklist';
  static const _kDefaultScenario = 'settings_defaultScenario';

  SettingsNotifier(this._prefs) : super(_load(_prefs));

  static AppSettings _load(SharedPreferences p) => AppSettings(
    hapticFeedback:     p.getBool(_kHaptic)     ?? true,
    audioFeedback:      p.getBool(_kAudio)      ?? true,
    keepScreenOn:       p.getBool(_kScreenOn)   ?? true,
    autoSwitchToCPR:    p.getBool(_kAutoSwitch) ?? true,
    showDepthGuide:     p.getBool(_kDepthGuide) ?? true,
    showRateGuide:      p.getBool(_kRateGuide)  ?? true,
    notifyOnDisconnect: p.getBool(_kDisconnect) ?? true,
    compressionUnit:    p.getString(_kUnit)     ?? 'cm',
    showChecklist: p.getBool(_kChecklist) ?? true,
    defaultScenario: p.getString(_kDefaultScenario) ?? 'standard_adult',
  );

  Future<void> setHapticFeedback(bool v)     async {
    state = state.copyWith(hapticFeedback: v);
    await _prefs.setBool(_kHaptic, v);
  }
  Future<void> setAudioFeedback(bool v)      async {
    state = state.copyWith(audioFeedback: v);
    await _prefs.setBool(_kAudio, v);
  }
  Future<void> setKeepScreenOn(bool v)       async {
    state = state.copyWith(keepScreenOn: v);
    await _prefs.setBool(_kScreenOn, v);
  }
  Future<void> setAutoSwitchToCPR(bool v)    async {
    state = state.copyWith(autoSwitchToCPR: v);
    await _prefs.setBool(_kAutoSwitch, v);
  }
  Future<void> setShowDepthGuide(bool v)     async {
    state = state.copyWith(showDepthGuide: v);
    await _prefs.setBool(_kDepthGuide, v);
  }
  Future<void> setShowRateGuide(bool v)      async {
    state = state.copyWith(showRateGuide: v);
    await _prefs.setBool(_kRateGuide, v);
  }
  Future<void> setNotifyOnDisconnect(bool v) async {
    state = state.copyWith(notifyOnDisconnect: v);
    await _prefs.setBool(_kDisconnect, v);
  }
  Future<void> setCompressionUnit(String v)  async {
    state = state.copyWith(compressionUnit: v);
    await _prefs.setString(_kUnit, v);
  }
  Future<void> setShowChecklist(bool v) async {
    state = state.copyWith(showChecklist: v);
    await _prefs.setBool(_kChecklist, v);
  }
  Future<void> setDefaultScenario(String v) async {
    state = state.copyWith(defaultScenario: v);
    await _prefs.setString(_kDefaultScenario, v);
  }
  Future<void> resetToDefaults() async {
    state = const AppSettings();
    await _prefs.remove(_kHaptic);
    await _prefs.remove(_kAudio);
    await _prefs.remove(_kScreenOn);
    await _prefs.remove(_kAutoSwitch);
    await _prefs.remove(_kDepthGuide);
    await _prefs.remove(_kRateGuide);
    await _prefs.remove(_kDisconnect);
    await _prefs.remove(_kUnit);
    await _prefs.remove(_kChecklist);
    await _prefs.remove(_kDefaultScenario);
  }
}

final settingsProvider =
StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});

/// Set to true by Settings before sending RUN_SELFTEST.
/// BLEConnection checks this flag when SELFTEST_RESULT arrives and
/// only shows the dialog when it is true, then resets it.
final selftestRequestedProvider = StateProvider<bool>((ref) => false);