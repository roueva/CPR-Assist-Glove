import 'dart:async';

import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../services/compression_event.dart';
import '../services/session_detail.dart';
import '../widgets/grade_card.dart';
import 'past_sessions_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GradeScreen  (Training CPR results)
//
// Login rules:
//   - Always reachable — no login gate on entry.
//   - After a session ends and the user is NOT logged in, show a single
//     non-blocking post-session prompt (AppDialogs.promptLogin).
//   - If they confirm and login succeeds → retry save.
//   - If they dismiss → discard silently. Never block the results UI.
// ─────────────────────────────────────────────────────────────────────────────

class GradeScreen extends ConsumerStatefulWidget {
  /// Raw BLE data stream — no decryption. Data arrives ready to parse.
  final Stream<Map<String, dynamic>> dataStream;

  const GradeScreen({
    super.key,
    required this.dataStream,
  });

  @override
  ConsumerState<GradeScreen> createState() => _GradeScreenState();
}

class _GradeScreenState extends ConsumerState<GradeScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  SessionDetail? _currentSession;
  Duration _sessionDuration = Duration.zero;
  DateTime? _sessionStartTime;
  StreamSubscription<Map<String, dynamic>>? _dataSub;

  late final SessionService _service;

  @override
  void initState() {
    super.initState();
    _service = SessionService(ref.read(networkServiceProvider));
    _listenToDataStream();
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    super.dispose();
  }

  // ── BLE data stream ────────────────────────────────────────────────────────

  void _listenToDataStream() {
    _dataSub = widget.dataStream.listen((data) {
      if (!mounted) return;
      if (data['startPing'] == true) {
        setState(() => _sessionStartTime = DateTime.now());
      }
      if (data.containsKey('sessionDuration')) {
        _sessionDuration = data['sessionDuration'] as Duration;
      }
      if (data['endPing'] == true) {
        _handleEndPing(data);
      }
    });
  }

  void _handleEndPing(Map<String, dynamic> data) {
    // Get the accumulated compression events from the BLE connection
    final events = ref.read(bleConnectionProvider).compressionEvents;

    final detail = _service.assembleDetail(
      summaryPacket:       data,
      events:              List<CompressionEvent>.from(events),
      sessionStart:        _sessionStartTime ?? DateTime.now(),
      sessionDurationSecs: _sessionDuration.inSeconds,
    );

    setState(() => _currentSession = detail);
    _saveSession(detail);
  }

  // ── Session save + post-session login prompt ───────────────────────────────

  Future<void> _saveSession(SessionDetail session) async {
    final isLoggedIn = ref.read(authStateProvider).isLoggedIn;

    if (!isLoggedIn) {
      // Non-blocking — results remain visible behind the dialog.
      final confirmed = await AppDialogs.promptLogin(
        context,
        reason: 'Log in to save this session and track your progress.',
      );
      if (!mounted) return;
      if (confirmed != true) return;

      final nowLoggedIn = ref.read(authStateProvider).isLoggedIn;
      if (!nowLoggedIn) return;
    }

    final success = await _service.saveDetail(session);
    if (!mounted) return;

    if (success) {
      UIHelper.showSuccess(context, 'Session saved');
    } else {
      UIHelper.showError(context, 'Failed to save session. Please try again.');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            if (_currentSession != null)
              GradeCard(session: _currentSession!)
            else
              const _EmptyState(),
            const SizedBox(height: AppSpacing.md),
            const _PastSessionsButton(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state — shown before any session completes
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          Container(
            width: AppSpacing.iconXl + AppSpacing.md,
            height: AppSpacing.iconXl + AppSpacing.md,
            decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
            child: const Icon(
              Icons.monitor_heart_outlined,
              color: AppColors.primary,
              size: AppSpacing.iconLg,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('No results yet', style: AppTypography.subheading()),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Complete a training session to\nsee your grade and stats here.',
            textAlign: TextAlign.center,
            style: AppTypography.body(color: AppColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Past sessions entry button
// ─────────────────────────────────────────────────────────────────────────────

class _PastSessionsButton extends StatelessWidget {
  const _PastSessionsButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(const PastSessionsScreen()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.buttonPaddingV,
          horizontal: AppSpacing.cardPadding,
        ),
        decoration: AppDecorations.card(),
        child: Row(
          children: [
            Container(
              width: AppSpacing.iconXl,
              height: AppSpacing.iconXl,
              decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
              child: const Icon(
                Icons.history_rounded,
                color: AppColors.primary,
                size: AppSpacing.iconMd,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Past Sessions',
                      style: AppTypography.bodyMedium(size: 15)),
                  Text('View all your training history',
                      style: AppTypography.caption()),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
              size: AppSpacing.iconMd,
            ),
          ],
        ),
      ),
    );
  }
}