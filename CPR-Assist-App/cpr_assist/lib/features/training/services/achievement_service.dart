import 'package:cpr_assist/features/training/screens/session_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Achievement model + service
// Computed entirely client-side from sessionSummariesProvider.
// No backend table needed.
// ─────────────────────────────────────────────────────────────────────────────

class Achievement {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final bool   unlocked;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.unlocked,
  });
}

class AchievementService {
  AchievementService._();

  static List<Achievement> compute(List<SessionSummary> sessions) {
    final training = sessions.where((s) => s.isTraining).toList();
    final goodSessions = training.where((s) => s.totalGrade >= 75).toList();
    final totalCompressions =
    sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);

    // Consecutive streak (newest-first, sessions already sorted that way)
    int streak = 0;
    for (final s in training) {
      if (s.totalGrade >= 75) streak++;
      else break;
    }

    final bestGrade = training.isEmpty
        ? 0.0
        : training.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);

    final hasAdult      = training.any((s) => s.scenario == 'standard_adult');
    final hasPediatric  = training.any((s) => s.scenario == 'pediatric');
    final hasNoFeedback = training.any((s) => s.isNoFeedback);

    return [
      Achievement(
        id:          'first_session',
        title:       'First Response',
        description: 'Complete your first training session',
        emoji:       '🏁',
        unlocked:    training.isNotEmpty,
      ),
      Achievement(
        id:          'first_good',
        title:       'Good Technique',
        description: 'Score 75% or higher in a training session',
        emoji:       '✅',
        unlocked:    goodSessions.isNotEmpty,
      ),
      Achievement(
        id:          'five_sessions',
        title:       'Regular Rescuer',
        description: 'Complete 5 training sessions',
        emoji:       '💪',
        unlocked:    training.length >= 5,
      ),
      Achievement(
        id:          'ten_sessions',
        title:       'Dedicated Trainer',
        description: 'Complete 10 training sessions',
        emoji:       '🎯',
        unlocked:    training.length >= 10,
      ),
      Achievement(
        id:          'perfect_score',
        title:       'Perfect Technique',
        description: 'Score 90% or higher in a training session',
        emoji:       '⭐',
        unlocked:    bestGrade >= 90,
      ),
      Achievement(
        id:          'streak_3',
        title:       'Hat Trick',
        description: '3 consecutive sessions with grade ≥ 75%',
        emoji:       '🔥',
        unlocked:    streak >= 3,
      ),
      Achievement(
        id:          'streak_5',
        title:       'On Fire',
        description: '5 consecutive sessions with grade ≥ 75%',
        emoji:       '🔥🔥',
        unlocked:    streak >= 5,
      ),
      Achievement(
        id:          'compressions_500',
        title:       'Chest Press Beginner',
        description: 'Perform 500 total compressions',
        emoji:       '🫀',
        unlocked:    totalCompressions >= 500,
      ),
      Achievement(
        id:          'compressions_2000',
        title:       'Chest Press Pro',
        description: 'Perform 2,000 total compressions',
        emoji:       '💗',
        unlocked:    totalCompressions >= 2000,
      ),
      Achievement(
        id:          'pediatric_trained',
        title:       'Child Saver',
        description: 'Complete a Pediatric scenario session',
        emoji:       '👶',
        unlocked:    hasPediatric,
      ),
      Achievement(
        id:          'nofeedback_trained',
        title:       'Blind Trust',
        description: 'Complete a No-Feedback training session',
        emoji:       '🙈',
        unlocked:    hasNoFeedback,
      ),
      Achievement(
        id:          'all_scenarios',
        title:       'All-Round Rescuer',
        description: 'Train in Adult, Pediatric, and No-Feedback modes',
        emoji:       '🌟',
        unlocked:    hasAdult && hasPediatric && hasNoFeedback,
      ),
    ];
  }
}