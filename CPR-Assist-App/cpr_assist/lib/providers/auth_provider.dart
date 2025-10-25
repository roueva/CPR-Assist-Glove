import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/network_service.dart';
import 'network_service_provider.dart';

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return AuthNotifier(networkService);
});

class AuthState {
  final bool isLoggedIn;
  final int? userId;
  final bool isLoading;

  AuthState({
    required this.isLoggedIn,
    this.userId,
    this.isLoading = false,
  });

  AuthState copyWith({
    bool? isLoggedIn,
    int? userId,
    bool? isLoading,
  }) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      userId: userId ?? this.userId,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final NetworkService _networkService;

  AuthNotifier(this._networkService) : super(AuthState(isLoggedIn: false));

  Future<void> checkAuthStatus() async {
    state = state.copyWith(isLoading: true);

    final isAuthenticated = await _networkService.ensureAuthenticated();
    final userId = await _networkService.getUserId();

    state = state.copyWith(
      isLoggedIn: isAuthenticated,
      userId: userId,
      isLoading: false,
    );
  }

  Future<void> logout() async {
    await _networkService.removeToken();
    state = AuthState(isLoggedIn: false);
  }

  Future<void> login(String token, int userId) async {
    state = state.copyWith(isLoading: true);

    await _networkService.saveToken(token);
    await _networkService.saveUserId(userId);

    state = state.copyWith(
      isLoggedIn: true,
      userId: userId,
      isLoading: false,
    );
  }
}

