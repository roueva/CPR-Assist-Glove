import 'package:cpr_assist/features/training/screens/session_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CertificateMilestone — earned milestone that can generate a PDF certificate.
// Computed entirely client-side from sessionSummariesProvider.
// ─────────────────────────────────────────────────────────────────────────────

class CertificateMilestone {
  final String    id;
  final String    title;
  final String    subtitle;
  final String    emoji;
  final bool      earned;
  final DateTime? earnedDate; // date of the session that completed this milestone

  const CertificateMilestone({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.earned,
    this.earnedDate,
  });
}

class CertificateService {
  CertificateService._();

  static List<CertificateMilestone> compute(List<SessionSummary> sessions) {
    final training    = sessions.where((s) => s.isTraining).toList();
    final goodSessions = training
        .where((s) => s.totalGrade >= 75)
        .toList()
      ..sort((a, b) => (a.sessionStart ?? DateTime(0))
          .compareTo(b.sessionStart ?? DateTime(0)));

    final bestGrade = training.isEmpty
        ? 0.0
        : training.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);

    // Sessions with ≥ 90% sorted chronologically
    final excellentSessions = training
        .where((s) => s.totalGrade >= 90)
        .toList()
      ..sort((a, b) => (a.sessionStart ?? DateTime(0))
          .compareTo(b.sessionStart ?? DateTime(0)));

    // All-scenario: need one good session in each of adult, pediatric, no-feedback
    final goodAdult = goodSessions.where((s) =>
    s.scenario == 'standard_adult' && !s.isNoFeedback).toList();
    final goodPediatric  = goodSessions.where((s) => s.scenario == 'pediatric').toList();
    final goodNoFeedback = goodSessions.where((s) => s.isNoFeedback).toList();

    // Date of the session that pushed good-count past a threshold
    DateTime? nthGoodDate(int n) => goodSessions.length >= n
        ? goodSessions[n - 1].sessionStart
        : null;

    return [
      CertificateMilestone(
        id:         'foundations',
        title:      'CPR Foundations',
        subtitle:   '5 training sessions with grade ≥ 75%',
        emoji:      '📜',
        earned:     goodSessions.length >= 5,
        earnedDate: nthGoodDate(5),
      ),
      CertificateMilestone(
        id:         'competency',
        title:      'CPR Competency',
        subtitle:   '10 training sessions with grade ≥ 75%',
        emoji:      '🎓',
        earned:     goodSessions.length >= 10,
        earnedDate: nthGoodDate(10),
      ),
      CertificateMilestone(
        id:         'proficiency',
        title:      'CPR Proficiency',
        subtitle:   '20 training sessions with grade ≥ 75%',
        emoji:      '🏅',
        earned:     goodSessions.length >= 20,
        earnedDate: nthGoodDate(20),
      ),
      CertificateMilestone(
        id:         'excellence',
        title:      'CPR Excellence',
        subtitle:   'Score 90% or higher in a training session',
        emoji:      '⭐',
        earned:     bestGrade >= 90,
        earnedDate: excellentSessions.isNotEmpty
            ? excellentSessions.first.sessionStart
            : null,
      ),
      CertificateMilestone(
        id:         'all_round',
        title:      'All-Round Rescuer',
        subtitle:   'Pass Adult, Pediatric, and No-Feedback with ≥ 75%',
        emoji:      '🌟',
        earned:     goodAdult.isNotEmpty &&
            goodPediatric.isNotEmpty &&
            goodNoFeedback.isNotEmpty,
        earnedDate: (goodAdult.isNotEmpty &&
            goodPediatric.isNotEmpty &&
            goodNoFeedback.isNotEmpty)
            ? [
          goodAdult.last.sessionStart,
          goodPediatric.last.sessionStart,
          goodNoFeedback.last.sessionStart,
        ].whereType<DateTime>()
            .reduce((a, b) => a.isAfter(b) ? a : b)
            : null,
      ),
    ];
  }
}