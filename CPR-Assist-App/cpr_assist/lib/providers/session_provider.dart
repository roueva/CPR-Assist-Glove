import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../services/session_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SESSION PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// SessionService instance
final sessionServiceProvider = Provider<SessionService>((ref) {
  final network = ref.watch(networkServiceProvider);
  return SessionService(network);
});

/// Async provider — fetches session summaries from backend.
/// Auto-refreshes when auth state changes (login/logout).
final sessionSummariesProvider =
FutureProvider<List<SessionSummary>>((ref) async {
  // Re-fetch whenever login state changes
  final isLoggedIn = ref.watch(authStateProvider).isLoggedIn;
  if (!isLoggedIn) return [];

  final service = ref.read(sessionServiceProvider);
  return service.fetchSummaries();
});

/// Derived provider — computes UserStats from session list.
final userStatsProvider = Provider<AsyncValue<UserStats>>((ref) {
  return ref.watch(sessionSummariesProvider).whenData(
        (sessions) => UserStats.fromSessions(sessions),
  );
});