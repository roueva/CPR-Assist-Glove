import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/training/screens/session_service.dart';
import 'app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SESSION PROVIDERS
// ─────────────────────────────────────────────────────────────────────────────

/// SessionService instance — depends on NetworkService for backend calls.
final sessionServiceProvider = Provider<SessionService>((ref) {
  final network = ref.watch(networkServiceProvider);
  return SessionService(network);
});

/// Async provider — fetches session summaries from the backend.
/// Returns an empty list when the user is not logged in.
/// Automatically re-fetches whenever login state changes.
final sessionSummariesProvider = FutureProvider<List<SessionSummary>>((ref) async {
  final isLoggedIn = ref.watch(authStateProvider).isLoggedIn;
  if (!isLoggedIn) return [];

  final service = ref.read(sessionServiceProvider);
  try {
    return await service.fetchSummaries();
  } catch (e) {
    debugPrint('sessionSummariesProvider: fetch error — $e');
    return [];
  }
});
