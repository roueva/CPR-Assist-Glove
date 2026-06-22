import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/app_constants.dart';
import '../features/aed_map/services/aed_service.dart';
import '../features/training/screens/session_service.dart';
import '../features/training/services/session_local_storage.dart';
import '../models/aed_models.dart';
import '../services/ble/ble_connection.dart';
import '../services/network/network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// INFRASTRUCTURE PROVIDERS  (must be overridden in main())
// ─────────────────────────────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
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
    // Only sync mode if non-default — avoids overwriting glove state on first connect
    if (mode != AppMode.emergency) connection.sendModeSet(mode.bleValue);
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
    connection.sendSetFeedbackChannels(
      audio:  settings.audioVolume       > 0,
      haptic: settings.hapticIntensity   > 0,
      visual: settings.gloveLedBrightness > 0,
    );
    connection.sendSetIntensity(
      audioVolume:  settings.audioVolume,
      motorPercent: settings.hapticIntensity,
    );
    // Always sync LED brightness — glove boots at NEOPIXEL_DEFAULT_BRIGHTNESS (180)
    // which may not match the user's saved preference.
    connection.sendSetLedBrightness(settings.gloveLedBrightness);

    // Ventilation cycle
    final ventRatio = settings.ventilationRatio;
    int ventComps = 30, ventBreaths = 2;
    if      (ventRatio == '15:2')              { ventComps = 15; ventBreaths = 2; }
    else if (ventRatio == 'compressions_only') { ventComps = 0;  ventBreaths = 0; }
    connection.sendSetVentilation(
      compressionsPerCycle: ventComps,
      ventilationsPerPause: ventBreaths,
    );
    // Persistent offline-session handler — runs regardless of which screen is
    // visible. When the glove sends PENDING_LOCAL_DATA on connect, BLEConnection
    // parses each chunk and calls this. The live screen may override this with its
    // own handler (which also shows a snackbar); that is fine — the live screen
    // clears it in dispose() and this provider-level handler takes over again.
    connection.onOfflineSessionParsed = (detail, sessionIndex) async {
      final service = SessionService(ref.read(networkServiceProvider));
      if (detail.mode != 'emergency') {
        detail = detail.withGrade(service.calculateGradeFromDetail(detail));
      }
      await service.saveLocalOnly(detail);
      final isLoggedIn = ref.read(authStateProvider).isLoggedIn;
      if (isLoggedIn) {
        final savedId = await service.saveDetail(detail);
        if (savedId != null) {
          detail = detail.withId(savedId);
          await SessionLocalStorage.markSynced(detail);
        }
      }
      await connection.sendConfirmReceived(sessionIndex);
      debugPrint('BLE: offline session $sessionIndex saved '
          '(${detail.compressionCount} compressions)');
    };

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
      case AppMode.emergency: state = AppMode.training; break;
      case AppMode.training:
      case AppMode.trainingNoFeedback: state = AppMode.emergency; break;
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
  pediatric;

  /// Byte value sent in SCENARIO_CHANGE (0x0C) and 0xFD SET_SCENARIO.
  int get bleValue {
    switch (this) {
      case CprScenario.standardAdult:  return 0;
      case CprScenario.pediatric:      return 1;
    }
  }

  /// String stored in SessionDetail.scenario and sent to backend.
  String get sessionScenarioString {
    switch (this) {
      case CprScenario.standardAdult: return 'standard_adult';
      case CprScenario.pediatric:     return 'pediatric';
    }
  }

  /// Human-readable label for UI.
  String get label {
    switch (this) {
      case CprScenario.standardAdult:  return 'Adult';
      case CprScenario.pediatric:      return 'Pediatric';
    }
  }

  /// Short description shown on the live CPR screen toggle.
  String get description {
    switch (this) {
      case CprScenario.standardAdult: return 'Adult — 5–6 cm';
      case CprScenario.pediatric:     return 'Pediatric — 4–5 cm';
    }
  }

  /// Depth target range in mm for this scenario.
  int get targetDepthMinMm {
    switch (this) {
      case CprScenario.pediatric:      return 40;
      case CprScenario.standardAdult:  return 50;
    }
  }
  int get targetDepthMaxMm {
    switch (this) {
      case CprScenario.pediatric:      return 50;
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
      default: return CprScenario.standardAdult;
    }
  }

  /// Construct from the scenario string stored in SessionDetail / backend.
  static CprScenario fromString(String value) {
    switch (value) {
      case 'pediatric':       return CprScenario.pediatric;
      default:                return CprScenario.standardAdult;
    }
  }
}

final scenarioProvider = StateNotifierProvider<ScenarioNotifier, CprScenario>((ref) {
  return ScenarioNotifier(CprScenario.standardAdult);
});

class ScenarioNotifier extends StateNotifier<CprScenario> {
  ScenarioNotifier(CprScenario initial) : super(initial);

  void setScenario(CprScenario s) => state = s;

  /// Toggle between adult and pediatric and timed endurance.
  void toggle() {
    state = state == CprScenario.standardAdult
        ? CprScenario.pediatric
        : CprScenario.standardAdult;
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
  final bool isLoggedIn;
  final int? userId;
  final String? username;
  final String? email;
  final String? createdAt;
  final bool isLoading;

  const AuthState({
    required this.isLoggedIn,
    this.userId,
    this.username,
    this.email,
    this.createdAt,
    this.isLoading = false,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    int? userId,
    String? username,
    String? email,
    String? createdAt,
    bool? isLoading,
  }) =>
      AuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        userId: userId ?? this.userId,
        username: username ?? this.username,
        email: email ?? this.email,
        createdAt: createdAt ?? this.createdAt,
        isLoading: isLoading ?? this.isLoading,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final NetworkService     _network;
  final SharedPreferences  _prefs;

  AuthNotifier(this._network, this._prefs)
      : super(const AuthState(isLoggedIn: false));

  Future<void> checkAuthStatus() async {
    final token = await _network.getToken();
    if (token == null) {
      // No token stored — definitely not logged in, no need to hit network
      state = const AuthState(isLoggedIn: false);
      return;
    }
    state = state.copyWith(isLoading: true);
    final authenticated = await _network.ensureAuthenticated();
    state = state.copyWith(
      isLoggedIn: authenticated,
      userId:     await _network.getUserId(),
      username:   _prefs.getString('username'),
      email:      _prefs.getString('email'),
      createdAt:  _prefs.getString('created_at'),
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
    await _prefs.remove('email');
    await _prefs.remove('created_at');
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
        final data = response['data'];
        final email     = data?['email']      as String?;
        final createdAt = data?['created_at'] as String?;
        if (email != null) {
          await _prefs.setString('email', email);
          state = state.copyWith(email: email);
        }
        if (createdAt != null) {
          await _prefs.setString('created_at', createdAt);
          state = state.copyWith(createdAt: createdAt);
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

  void cancelNavigation() => state = state.copyWith(
    navigation: NavigationState(transportMode: state.navigation.transportMode),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// APP SETTINGS
//
// All user-configurable toggles persisted via SharedPreferences.
// Keys are intentionally prefixed with 'settings_' to avoid collisions.
// ─────────────────────────────────────────────────────────────────────────────

class AppSettings {
  final bool   keepScreenOn;
  final bool   autoSwitchToCPR;
  final bool   notifyOnDisconnect;
  final int  gloveLedBrightness;   // 0–255
  /// Ventilation cycle: '30:2', '15:2', or 'compressions_only'.
  final String ventilationRatio;
  final int audioVolume;     // 0–30 (DFPlayer scale)
  final int hapticIntensity; // 0–100
  final bool syncWifiOnly;

  const AppSettings({
    this.keepScreenOn          = true,
    this.autoSwitchToCPR       = true,
    this.notifyOnDisconnect    = true,
    this.gloveLedBrightness  = AppConstants.diagLedBrightnessDefault,
    this.ventilationRatio      = '30:2',
    this.audioVolume           = AppConstants.audioVolumeDefault,
    this.hapticIntensity       = AppConstants.hapticIntensityDefault,
    this.syncWifiOnly          = false,
  });

  AppSettings copyWith({
    bool?   hapticFeedback,
    bool?   audioFeedback,
    bool?   visualFeedback,
    bool?   keepScreenOn,
    bool?   autoSwitchToCPR,
    bool?   notifyOnDisconnect,
    int? gloveLedBrightness,
    String? ventilationRatio,
    int? audioVolume,
    int? hapticIntensity,
    bool? syncWifiOnly,
  }) =>
      AppSettings(
        keepScreenOn:          keepScreenOn          ?? this.keepScreenOn,
        autoSwitchToCPR:       autoSwitchToCPR       ?? this.autoSwitchToCPR,
        notifyOnDisconnect:    notifyOnDisconnect    ?? this.notifyOnDisconnect,
        gloveLedBrightness:  gloveLedBrightness  ?? this.gloveLedBrightness,
        ventilationRatio: ventilationRatio ?? this.ventilationRatio,
        audioVolume:      audioVolume      ?? this.audioVolume,
        hapticIntensity:  hapticIntensity  ?? this.hapticIntensity,
        syncWifiOnly:     syncWifiOnly     ?? this.syncWifiOnly,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _prefs;

  static const _kHaptic         = 'settings_hapticFeedback';
  static const _kAudio          = 'settings_audioFeedback';
  static const _kVisual         = 'settings_visualFeedback';
  static const _kScreenOn       = 'settings_keepScreenOn';
  static const _kScenario = 'settings_scenario';
  static const _kAutoSwitch     = 'settings_autoSwitchToCPR';
  static const _kDisconnect     = 'settings_notifyOnDisconnect';
  static const _kLedBrightness  = 'settings_gloveLedBrightness';
  static const _kVentRatio = 'settings_ventilationRatio';
  static const _kAudioVol     = 'settings_audioVolume';
  static const _kHapticInt    = 'settings_hapticIntensity';
  static const _kSyncWifi = 'settings_syncWifiOnly';

  SettingsNotifier(this._prefs) : super(_load(_prefs));

  static AppSettings _load(SharedPreferences p) => AppSettings(
    keepScreenOn:          p.getBool(_kScreenOn)       ?? true,
    autoSwitchToCPR:       p.getBool(_kAutoSwitch)     ?? true,
    notifyOnDisconnect:    p.getBool(_kDisconnect)     ?? true,
    gloveLedBrightness:  p.getInt(_kLedBrightness)  ?? AppConstants.diagLedBrightnessDefault,
    ventilationRatio: p.getString(_kVentRatio) ?? '30:2',
    audioVolume: p.getInt(_kAudioVol) ?? AppConstants.audioVolumeDefault,
    hapticIntensity: p.getInt(_kHapticInt) ?? AppConstants.hapticIntensityDefault,
    syncWifiOnly: p.getBool(_kSyncWifi) ?? false,
  );

  Future<void> setHapticFeedback(bool v)     async { state = state.copyWith(hapticFeedback: v);        await _prefs.setBool(_kHaptic, v); }
  Future<void> setAudioFeedback(bool v)      async { state = state.copyWith(audioFeedback: v);         await _prefs.setBool(_kAudio, v); }
  Future<void> setVisualFeedback(bool v)     async { state = state.copyWith(visualFeedback: v);        await _prefs.setBool(_kVisual, v); }
  Future<void> setKeepScreenOn(bool v)       async { state = state.copyWith(keepScreenOn: v);          await _prefs.setBool(_kScreenOn, v); }
  Future<void> setAutoSwitchToCPR(bool v)    async { state = state.copyWith(autoSwitchToCPR: v);       await _prefs.setBool(_kAutoSwitch, v); }
  Future<void> setNotifyOnDisconnect(bool v) async { state = state.copyWith(notifyOnDisconnect: v);    await _prefs.setBool(_kDisconnect, v); }

  Future<void> setVentilationRatio(String v) async {
    state = state.copyWith(ventilationRatio: v);
    await _prefs.setString(_kVentRatio, v);
  }

// Audio volume — Live: state only, Persist: state + disk
  void setAudioVolumeLive(int v) {
    state = state.copyWith(
      audioVolume: v.clamp(AppConstants.audioVolumeMin, AppConstants.audioVolumeMax),
    );
  }
  Future<void> setAudioVolumePersist(int v) async {
    state = state.copyWith(
      audioVolume: v.clamp(AppConstants.audioVolumeMin, AppConstants.audioVolumeMax),
    );
    await _prefs.setInt(_kAudioVol, v);
  }

// Haptic intensity
  void setHapticIntensityLive(int v) {
    state = state.copyWith(hapticIntensity: v.clamp(0, 100));
  }
  Future<void> setHapticIntensityPersist(int v) async {
    state = state.copyWith(hapticIntensity: v.clamp(0, 100));
    await _prefs.setInt(_kHapticInt, v);
  }

// LED brightness
  void setGloveLedBrightnessLive(int v) {
    state = state.copyWith(
      gloveLedBrightness: v.clamp(
        AppConstants.diagLedBrightnessMin,
        AppConstants.diagLedBrightnessMax,
      ),
    );
  }
  Future<void> setGloveLedBrightnessPersist(int v) async {
    state = state.copyWith(
      gloveLedBrightness: v.clamp(
        AppConstants.diagLedBrightnessMin,
        AppConstants.diagLedBrightnessMax,
      ),
    );
    await _prefs.setInt(_kLedBrightness, v);
  }

  Future<void> setSyncWifiOnly(bool v) async { state = state.copyWith(syncWifiOnly: v); await _prefs.setBool(_kSyncWifi, v); }

  Future<void> resetToDefaults() async {
    state = const AppSettings();
    for (final k in [
      _kScreenOn, _kAutoSwitch,
      _kDisconnect, _kLedBrightness, _kVentRatio, _kAudioVol, _kHapticInt, _kSyncWifi,
    ]) { await _prefs.remove(k); }
  }
}

final settingsProvider =
StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});


/// Set to true once CacheService.initializeAllCaches() completes.
final cacheInitializedProvider = StateProvider<bool>((ref) => false);

/// Non-null if CacheService.initializeAllCaches() threw an error.
final cacheErrorProvider = StateProvider<String?>((ref) => null);

/// Set to true by Settings before sending RUN_SELFTEST.
/// BLEConnection checks this flag when SELFTEST_RESULT arrives and
/// only shows the dialog when it is true, then resets it.
final selftestRequestedProvider = StateProvider<bool>((ref) => false);

/// Set true immediately before sending CMD_CALIBRATE so the
/// SELFTEST_RESULT that calibration always emits is shown as a
/// calibration outcome, not a generic sensor warning.
final calibrationPendingProvider = StateProvider<bool>((ref) => false);