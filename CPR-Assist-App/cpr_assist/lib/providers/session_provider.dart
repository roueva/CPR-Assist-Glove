import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/training/screens/session_service.dart';
import '../features/training/services/achievement_service.dart';
import '../features/training/services/certificate_service.dart';
import '../features/training/services/session_local_storage.dart';
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
final sessionSummariesProvider =
FutureProvider<List<SessionSummary>>((ref) async {
  final isLoggedIn = ref.watch(authStateProvider).isLoggedIn;

  // Always load local sessions (available even when not logged in)
  final localDetails = await SessionLocalStorage.loadAll();
  final localSummaries = localDetails
      .map((d) => SessionSummary.fromDetail(d))
      .toList();

  if (!isLoggedIn) return localSummaries;

  // Merge with backend
  final service = ref.read(sessionServiceProvider);
  List<SessionSummary> backendSessions;
  try {
    backendSessions = await service.fetchSummaries();
  } catch (e) {
    debugPrint('sessionSummariesProvider: fetch error — $e');
    backendSessions = [];
  }

  // Deduplicate: prefer backend version (has id) over local
  final backendStarts = backendSessions
      .map((s) => s.sessionStart != null
      ? s.sessionStart!.millisecondsSinceEpoch ~/ 1000
      : null)
      .whereType<int>()
      .toSet();
  final onlyLocal = localSummaries.where((s) =>
  s.sessionStart == null ||
      !backendStarts.contains(s.sessionStart!.millisecondsSinceEpoch ~/ 1000),
  ).toList();

  final merged = [...backendSessions, ...onlyLocal]
    ..sort((a, b) => (b.sessionStart ?? DateTime(0))
        .compareTo(a.sessionStart ?? DateTime(0)));

  return merged;
});

/// Global leaderboard for a given scenario.
/// Key is the scenario string: 'standard_adult' or 'pediatric'.
/// Re-fetches when auth state changes.
typedef _LeaderboardData = (List<LeaderboardEntry>, LeaderboardEntry?);

final globalLeaderboardProvider =
FutureProvider.family<_LeaderboardData, String>((ref, scenario) async {
  final isLoggedIn = ref.watch(authStateProvider).isLoggedIn;
  if (!isLoggedIn) return (<LeaderboardEntry>[], null);
  final service = ref.read(sessionServiceProvider);
  return service.fetchGlobalLeaderboard(scenario: scenario);
});

final currentStreakProvider = Provider<int>((ref) {
  final summaries = ref.watch(sessionSummariesProvider).valueOrNull ?? [];
  final training = summaries.where((s) => s.isTraining && s.totalGrade > 0).toList();
  int streak = 0;
  for (final s in training) {
    if (s.totalGrade >= 75) streak++;
    else break;
  }
  return streak;
});

final achievementsProvider = Provider<List<Achievement>>((ref) {
  final summaries = ref.watch(sessionSummariesProvider).valueOrNull ?? [];
  return AchievementService.compute(summaries);
});

final certificatesProvider = Provider<List<CertificateMilestone>>((ref) {
  final summaries = ref.watch(sessionSummariesProvider).valueOrNull ?? [];
  return CertificateService.compute(summaries);
});