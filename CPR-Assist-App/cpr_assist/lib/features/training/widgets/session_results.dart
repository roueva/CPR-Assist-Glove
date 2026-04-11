import 'package:cpr_assist/features/training/widgets/session_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../screens/session_service.dart';
import '../services/achievement_service.dart';
import '../services/certificate_service.dart';
import '../services/compression_event.dart';
import '../services/session_detail.dart';
import '../services/session_local_storage.dart';
import 'export_bottom_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionResultsScreen
//
// Two named constructors:
//   fromDetail — post-session (has full compression stream → graphs enabled)
//   fromSummary — history view (summary only → graphs hidden)
//
// Mode-aware rendering:
//   Emergency → no grade circle, factual summary header, pulse check section
//   Training  → grade circle + motivational label + full quality breakdown
// ─────────────────────────────────────────────────────────────────────────────

class SessionResultsScreen extends ConsumerStatefulWidget {
  final SessionDetail?  _detail;
  final SessionSummary? _summary;
  final int?            _sessionNumber;

  const SessionResultsScreen.fromDetail({
    super.key,
    required SessionDetail detail,
  })  : _detail        = detail,
        _summary       = null,
        _sessionNumber = null;

  const SessionResultsScreen.fromSummary({
    super.key,
    required SessionSummary summary,
    int? sessionNumber,
  })  : _detail        = null,
        _summary       = summary,
        _sessionNumber = sessionNumber;

  @override
  ConsumerState<SessionResultsScreen> createState() =>
      _SessionResultsScreenState();
}

class _SessionResultsScreenState
    extends ConsumerState<SessionResultsScreen> {
  String? _note;
  List<String> _previouslyUnlockedIds = [];
  List<String> _previouslyEarnedCertIds = [];

  @override
  void initState() {
    super.initState();
    _note = widget._detail?.note ?? widget._summary?.note;

    if (widget._detail != null && !_isEmergency) {
      // Snapshot which achievements were unlocked BEFORE this session
      // by computing against all sessions except the one just completed
      _previouslyUnlockedIds = _computePreviouslyUnlocked();
      _previouslyEarnedCertIds = _computePreviouslyEarnedCerts();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkNewAchievements();
      });
    }
  }

  List<String> _computePreviouslyUnlocked() {
    // Get current summaries from provider synchronously (may be empty if not yet loaded)
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    // Exclude the session that just ended (match by sessionStart)
    final start = widget._detail!.sessionStart;
    final previous = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch !=
            start.millisecondsSinceEpoch).toList();
    return AchievementService.compute(previous)
        .where((a) => a.unlocked)
        .map((a) => a.id)
        .toList();
  }

  List<String> _computePreviouslyEarnedCerts() {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start     = widget._detail!.sessionStart;
    final previous  = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch !=
            start.millisecondsSinceEpoch).toList();
    return CertificateService.compute(previous)
        .where((c) => c.earned)
        .map((c) => c.id)
        .toList();
  }

  void _checkNewAchievements() {
    if (!mounted) return;
    final achievements   = ref.read(achievementsProvider);
    final newlyUnlocked  = achievements
        .where((a) => a.unlocked && !_previouslyUnlockedIds.contains(a.id))
        .toList();

    for (int i = 0; i < newlyUnlocked.length; i++) {
      final a = newlyUnlocked[i];
      Future.delayed(Duration(milliseconds: 600 + i * 900), () {
        if (mounted) {
          UIHelper.showSnackbar(
            context,
            message: '${a.emoji} Achievement unlocked: ${a.title}',
            icon: Icons.emoji_events_rounded,
          );
        }
      });
    }
    // Certificate milestone toasts
    final certs = ref.read(certificatesProvider);
    final newCerts = certs
        .where((c) => c.earned && !_previouslyEarnedCertIds.contains(c.id))
        .toList();
    for (int i = 0; i < newCerts.length; i++) {
      final c = newCerts[i];
      Future.delayed(
        Duration(milliseconds: 1200 + newlyUnlocked.length * 900 + i * 1000),
            () {
          if (mounted) {
            UIHelper.showSnackbar(
              context,
              message: '${c.emoji} Certificate earned: ${c.title}!',
              icon: Icons.workspace_premium_rounded,
            );
          }
        },
      );
    }
  }

  // ── Mode helpers ───────────────────────────────────────────────────────────
  bool get _isEmergency =>
      (widget._detail?.isEmergency ?? widget._summary?.isEmergency) ?? true;

  String get _scenario =>
      widget._detail?.scenario ?? widget._summary?.scenario ?? 'standard_adult';

  bool get _isPediatric => _scenario == 'pediatric';

  double get _targetDepthMin =>
      _isPediatric
          ? CprTargets.depthMinPediatric
          : CprTargets.depthMin;

  double get _targetDepthMax =>
      _isPediatric
          ? CprTargets.depthMaxPediatric
          : CprTargets.depthMax;

  String get _targetDepthLabel =>
      '${_targetDepthMin.toStringAsFixed(0)}–${_targetDepthMax.toStringAsFixed(
          0)} cm';

  // ── Derived helpers ────────────────────────────────────────────────────────
  double get _grade =>
      widget._detail?.totalGrade ?? widget._summary?.totalGrade ?? 0;

  int get _compressionCount =>
      widget._detail?.compressionCount ?? widget._summary?.compressionCount ??
          0;

  String get _durationFormatted =>
      widget._detail?.durationFormatted ?? widget._summary?.durationFormatted ??
          '—';

  double get _averageFrequency =>
      widget._detail?.averageFrequency ?? widget._summary?.averageFrequency ??
          0;

  double get _averageDepth =>
      widget._detail?.averageDepth ?? widget._summary?.averageDepth ?? 0;

  String get _dateTimeFormatted =>
      widget._detail?.dateTimeFormatted ?? widget._summary?.dateTimeFormatted ??
          '—';

  int get _correctDepth =>
      widget._detail?.correctDepth ?? widget._summary?.correctDepth ?? 0;

  int get _correctFrequency =>
      widget._detail?.correctFrequency ?? widget._summary?.correctFrequency ??
          0;

  int get _correctRecoil =>
      widget._detail?.correctRecoil ?? widget._summary?.correctRecoil ?? 0;

  int get _depthRateCombo =>
      widget._detail?.depthRateCombo ?? widget._summary?.depthRateCombo ?? 0;

  double get _avgWristAngle {
    final c = widget._detail?.compressions;
    if (c == null || c.isEmpty) return 0.0;
    return c.map((e) => e.wristAlignmentAngle).reduce((a, b) => a + b) / c.length;
  }

  // Rescuer biometrics — use new field names only
  double? get _rescuerHR =>
      widget._detail?.rescuerHRLastPause ?? widget._summary?.rescuerHRLastPause;

  double? get _rescuerSpO2 =>
      widget._detail?.rescuerSpO2LastPause ??
          widget._summary?.rescuerSpO2LastPause;

  bool get _hasBiometrics => _rescuerHR != null || _rescuerSpO2 != null;

  String get _motivationalLabel {
    if (_grade >= 90) return 'Excellent!';
    if (_grade >= 75) return 'Good job!';
    if (_grade >= 55) return 'Keep it up!';
    return 'Keep practicing!';
  }

  String _pct(int value) {
    if (_compressionCount == 0) return '—';
    return '${(value / _compressionCount * 100).round()}%';
  }

  Color _flowColor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.error;
  }

  Future<void> _exportSession() async {
    final summary = widget._summary ??
        (widget._detail != null
            ? SessionSummary.fromDetail(widget._detail!)
            : null);
    if (summary == null) return;

    await ExportBottomSheet.showForSingleSession(
      context,
      summary: summary,
      detail:  widget._detail,
    );
  }


  Future<void> _confirmDeleteSession() async {
    final sessionId = widget._detail?.id ?? widget._summary?.id;
    if (sessionId == null) return;

    final confirmed = await AppDialogs.showDestructiveConfirm(
      context,
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.emergencyRed,
      iconBg: AppColors.emergencyBg,
      title: 'Delete Session?',
      message: 'This permanently deletes this session and all its data.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.emergencyRed,
      cancelLabel: 'Cancel',
    );

    if (confirmed != true || !mounted) return;

    final service = ref.read(sessionServiceProvider);
    final ok = await service.deleteSession(sessionId);
    if (!mounted) return;

    if (ok) {
      ref.invalidate(sessionSummariesProvider);
      context.pop();
      UIHelper.showSuccess(context, 'Session deleted');
    } else {
      UIHelper.showError(context, 'Failed to delete. Check your connection.');
    }
  }

  // ── Note editing ───────────────────────────────────────────────────────────
  Future<void> _editNote() async {
    final result = await AppDialogs.showNoteEditor(
      context,
      initialNote: _note,
    );
    if (result == null) return;

    final sessionId = widget._detail?.id ?? widget._summary?.id;
    if (sessionId != null) {
      final service = ref.read(sessionServiceProvider);
      final ok = await service.updateNote(
          sessionId, result.isEmpty ? null : result);
      if (!mounted) return;
      if (ok) {
        ref.invalidate(sessionSummariesProvider);
        setState(() => _note = result.isEmpty ? null : result);
        UIHelper.showSuccess(context, 'Note saved');
      } else {
        UIHelper.showError(
            context, 'Failed to save note. Check your connection.');
      }
    } else {
      // No backend ID — update UI state and persist to local SharedPreferences
      final newNote = result.isEmpty ? null : result;
      setState(() => _note = newNote);
      final updatedDetail = widget._detail?.withNote(newNote);
      if (updatedDetail != null) {
        await SessionLocalStorage.saveLocal(updatedDetail);
      }
      ref.invalidate(sessionSummariesProvider);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasDetail = widget._detail != null;
    final hasGraphs = hasDetail && widget._detail!.compressions.isNotEmpty;
    // Allow note editing for both saved (has id) and local-only sessions (has detail)
    final canEditNote = (widget._detail?.id ?? widget._summary?.id) != null
        || widget._detail != null;
    final title = widget._sessionNumber != null
        ? 'Session ${widget._sessionNumber}'
        : _isEmergency ? 'Emergency Session' : 'Session Results';

    final isNoFeedback =
        widget._detail?.isNoFeedback ?? widget._summary?.isNoFeedback ?? false;

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor: AppColors.primaryLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(
              Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text(title,
            style: AppTypography.heading(size: 18, color: AppColors.primary)),
        actions: [
          // Mode chip
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
              decoration: AppDecorations.chip(
                color: _isEmergency ? AppColors.emergencyRed : AppColors
                    .warning,
                bg: _isEmergency ? AppColors.emergencyBg : AppColors.warningBg,
              ),
              child: Text(
                _isEmergency ? 'EMERGENCY'
                    : isNoFeedback ? 'NO-FEEDBACK'
                    : _isPediatric ? 'PEDIATRIC'
                    : 'TRAINING',
                style: AppTypography.badge(
                  size: 10,
                  color: _isEmergency ? AppColors.emergencyRed : AppColors
                      .warning,
                ),
              ),
            ),
          ),
          if (widget._detail != null || widget._summary != null)
            IconButton(
              icon: const Icon(
                  Icons.download_outlined, color: AppColors.primary),
              tooltip: 'Export',
              onPressed: _exportSession,
            ),
          if ((widget._detail?.id ?? widget._summary?.id) != null)
            IconButton(
              icon: const Icon(
                  Icons.delete_outline_rounded, color: AppColors.emergencyRed),
              tooltip: 'Delete',
              onPressed: _confirmDeleteSession,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────────
            _isEmergency
                ? _EmergencyHeader(
              durationFormatted: _durationFormatted,
              compressionCount: _compressionCount,
              isPediatric: _isPediatric,
              correctDepthPct: _compressionCount > 0 ? (_correctDepth /
                  _compressionCount * 100).round() : 0,
              correctRatePct: _compressionCount > 0 ? (_correctFrequency /
                  _compressionCount * 100).round() : 0,
              handsOnPct: widget._detail?.handsOnPct ?? '—',
              handsOnOk: widget._detail != null &&
                  widget._detail!.handsOnRatio >= 0.80,
              timeToFirst: widget._detail?.timeToFirstCompression,
              avgBpm: _averageFrequency,
              avgDepth: _averageDepth,
              targetDepthLabel: _targetDepthLabel,
            )
                : _TrainingHeader(
              grade: _grade,
              isPediatric: _isPediatric,
              isNoFeedback: isNoFeedback,
              motivational: _motivationalLabel,
              depthPct: _compressionCount > 0 ? (_correctDepth /
                  _compressionCount * 100) : 0,
              ratePct: _compressionCount > 0 ? (_correctFrequency /
                  _compressionCount * 100) : 0,
              recoilPct: _compressionCount > 0 ? (_correctRecoil /
                  _compressionCount * 100) : 0,
              durationFormatted: _durationFormatted,
              compressionCount: _compressionCount,
              avgBpm: _averageFrequency,
              onGradeInfo: () =>
                  AppDialogs.showAlert(
                    context,
                    title: 'How is the grade calculated?',
                    message: _isPediatric
                        ? 'Pediatric grading:\n\n'
                        '• Depth consistency (25%) — within 4–5 cm\n'
                        '• Rate consistency (13%) — 100–120 BPM\n'
                        '• Full recoil (10%)\n'
                        '• Depth + rate combined (12%)\n'
                        '• Hands-on ratio (5%)\n'
                        '• Ventilation compliance (10%)\n'
                        '• Posture (5%)\n'
                        '• Force safety (10%)\n'
                        '• Time to first compression (10%)\n'
                        '• Fatigue penalty (−5 pts)'
                        : 'Adult grading:\n\n'
                        '• Depth consistency (20%) — within 5–6 cm\n'
                        '• Rate consistency (18%) — 100–120 BPM\n'
                        '• Full recoil (15%)\n'
                        '• Depth + rate combined (12%)\n'
                        '• Hands-on ratio (10%)\n'
                        '• Ventilation compliance (10%)\n'
                        '• Posture (5%)\n'
                        '• Force safety (5%)\n'
                        '• Time to first compression (5%)\n'
                        '• Fatigue penalty (−5 pts)',
                  ),
            ),

            // ── Body ─────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [

                  // Personal best — training only
                  if (!_isEmergency) ...[
                    _PersonalBestComparison(
                        currentGrade: _grade, scenario: _scenario),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Graphs
                  if (hasGraphs) ...[
                    _SectionCard(
                      title: 'Performance Over Time',
                      icon: Icons.show_chart_rounded,
                      startOpen: true,
                      child: _TappableGraphs(
                        session: widget._detail!,
                        targetDepthMin: _targetDepthMin,
                        targetDepthMax: _targetDepthMax,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Emergency — pulse check
                  if (_isEmergency && hasDetail &&
                      widget._detail!.pulseChecks.isNotEmpty) ...[
                    _SectionCard(
                      title: 'Pulse Check Results',
                      icon: Icons.sensors_rounded,
                      iconColor: AppColors.primary,
                      startOpen: true,
                      child: _PulseChecksSection(detail: widget._detail!),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Emergency — EMS handover
                  if (_isEmergency && hasDetail) ...[
                    _SectionCard(
                      title: 'CPR Quality Summary',
                      icon: Icons.medical_services_rounded,
                      iconColor: AppColors.emergencyRed,
                      startOpen: true,
                      child: _EmergencyQualitySection(
                        detail: widget._detail!,
                        compressionCount: _compressionCount,
                        targetDepthLabel: _targetDepthLabel,
                        averageDepth: _averageDepth,
                        averageFrequency: _averageFrequency,
                        correctRecoil: _correctRecoil,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Training — compression quality
                  if (!_isEmergency && hasDetail) ...[
                    _SectionCard(
                      title: 'Compression Quality',
                      icon: Icons.compress_rounded,
                      startOpen: true,
                      child: _CompressionQualitySection(
                        detail: widget._detail!,
                        compressionCount: _compressionCount,
                        targetDepthLabel: _targetDepthLabel,
                        averageDepth: _averageDepth,
                        avgWristAngle: _avgWristAngle,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Flow
                    _SectionCard(
                      title: 'Flow & Timing',
                      icon: Icons.timer_outlined,
                      startOpen: false,
                      child: _FlowSection(detail: widget._detail!),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Ventilation — both modes if data exists
                  if (hasDetail && widget._detail!.ventilationCount > 0) ...[
                    _SectionCard(
                      title: 'Ventilation',
                      icon: Icons.air_rounded,
                      iconColor: AppColors.info,
                      startOpen: false,
                      child: _VentilationSection(detail: widget._detail!),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Fatigue & endurance — training
                  if (!_isEmergency && hasDetail &&
                      (widget._detail!.rescuerSwapCount > 0 ||
                          widget._detail!.fatigueOnsetIndex > 0)) ...[
                    _SectionCard(
                      title: 'Fatigue & Endurance',
                      icon: Icons.local_fire_department_rounded,
                      iconColor: AppColors.cprOrange,
                      startOpen: false,
                      child: _FatigueSection(detail: widget._detail!),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Biometrics
                  if (_hasBiometrics || (hasDetail && (
                      widget._detail!.patientTemperature != null ||
                          widget._detail!.ambientTempStart != null))) ...[
                    _SectionCard(
                      title: 'Biometrics',
                      icon: Icons.monitor_heart_outlined,
                      iconColor: AppColors.primary,
                      startOpen: false,
                      child: _BiometricsSection(
                        detail: widget._detail,
                        summary: widget._summary,
                        rescuerHR: _rescuerHR,
                        rescuerSpO2: _rescuerSpO2,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Session metadata
                  _SectionCard(
                    title: 'Session Info',
                    icon: Icons.info_outline_rounded,
                    iconColor: AppColors.textSecondary,
                    startOpen: false,
                    child: Column(
                      children: [
                        _DetailRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'Date & Time',
                          value: _dateTimeFormatted,
                        ),
                        if (widget._detail?.syncedToBackend == false)
                          const _UnsyncedBanner(),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Note
                  _NoteCard(
                    note: _note,
                    canEdit: canEditNote,
                    onTap: _editNote,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  const _PastSessionsButton(),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TrainingHeader
// ─────────────────────────────────────────────────────────────────────────────

class _TrainingHeader extends StatelessWidget {
  final double       grade;
  final bool         isPediatric;
  final bool         isNoFeedback;
  final String       motivational;
  final double       depthPct;
  final double       ratePct;
  final double       recoilPct;
  final String       durationFormatted;
  final int          compressionCount;
  final double       avgBpm;
  final VoidCallback onGradeInfo;

  const _TrainingHeader({
    required this.grade,
    required this.isPediatric,
    required this.isNoFeedback,
    required this.motivational,
    required this.depthPct,
    required this.ratePct,
    required this.recoilPct,
    required this.durationFormatted,
    required this.compressionCount,
    required this.avgBpm,
    required this.onGradeInfo,
  });

  Color get _gradeColor {
    if (grade >= 90) return AppColors.success;
    if (grade >= 75) return AppColors.info;
    if (grade >= 55) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primaryAlt],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        children: [
          // ── Grade circle + ? button ────────────────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width:  160,
                height: 160,
                child: CircularProgressIndicator(
                  value:           grade / 100,
                  strokeWidth:     12,
                  strokeCap:       StrokeCap.round,
                  backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
                  valueColor:      AlwaysStoppedAnimation<Color>(_gradeColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${grade.toStringAsFixed(0)}%',
                    style: AppTypography.numericDisplay(
                      size: 42, color: AppColors.textOnDark,
                    ),
                  ),
                  Text(
                    motivational,
                    style: AppTypography.label(
                      size:  12,
                      color: AppColors.textOnDark.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              // ? button — top right of circle
              Positioned(
                top:   0,
                right: 0,
                child: GestureDetector(
                  onTap: onGradeInfo,
                  child: Container(
                    width:  28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textOnDark.withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.help_outline_rounded,
                      size:  16,
                      color: AppColors.textOnDark,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // Scenario / mode pill — below circle
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            decoration: BoxDecoration(
              color:        AppColors.textOnDark.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
              border: Border.all(
                  color: AppColors.textOnDark.withValues(alpha: 0.2)),
            ),
            child: Text(
              isNoFeedback
                  ? 'No-Feedback Training'
                  : isPediatric ? 'Pediatric' : 'Standard Adult',
              style: AppTypography.badge(
                  size: 10, color: AppColors.textOnDark),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── 3 sub-rings: Depth / Rate / Recoil ────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _MetricRing(
                label:   'DEPTH',
                value:   depthPct,
                color:   depthPct >= 80
                    ? AppColors.success
                    : depthPct >= 60
                    ? AppColors.warning
                    : AppColors.error,
              ),
              _MetricRing(
                label:   'RATE',
                value:   ratePct,
                color:   ratePct >= 80
                    ? AppColors.success
                    : ratePct >= 60
                    ? AppColors.warning
                    : AppColors.error,
              ),
              _MetricRing(
                label:   'RECOIL',
                value:   recoilPct,
                color:   recoilPct >= 80
                    ? AppColors.success
                    : recoilPct >= 60
                    ? AppColors.warning
                    : AppColors.error,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Stat bar ──────────────────────────────────────────────────
          Container(
            decoration: AppDecorations.darkStatTile(),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _SummaryCell(value: durationFormatted,          label: 'DURATION'),
                  _VDivider(),
                  _SummaryCell(value: '$compressionCount',        label: 'COMPRESSIONS'),
                  _VDivider(),
                  _SummaryCell(
                    value: avgBpm > 0 ? '${avgBpm.round()}' : '—',
                    label: 'AVG BPM',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MetricRing — small circular sub-grade
// ─────────────────────────────────────────────────────────────────────────────

class _MetricRing extends StatelessWidget {
  final String label;
  final double value; // 0–100
  final Color  color;

  const _MetricRing({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width:  72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value:           value / 100,
                strokeWidth:     6,
                strokeCap:       StrokeCap.round,
                backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
                valueColor:      AlwaysStoppedAnimation<Color>(color),
              ),
              Text(
                '${value.round()}%',
                style: AppTypography.poppins(
                  size:   14,
                  weight: FontWeight.w700,
                  color:  AppColors.textOnDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.badge(
              size: 9, color: AppColors.textOnDark.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmergencyHeader
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencyHeader extends StatelessWidget {
  final String  durationFormatted;
  final int     compressionCount;
  final bool    isPediatric;
  final int     correctDepthPct;
  final int     correctRatePct;
  final String  handsOnPct;
  final bool    handsOnOk;
  final double? timeToFirst;
  final double  avgBpm;
  final double  avgDepth;
  final String  targetDepthLabel;

  const _EmergencyHeader({
    required this.durationFormatted,
    required this.compressionCount,
    required this.isPediatric,
    required this.correctDepthPct,
    required this.correctRatePct,
    required this.handsOnPct,
    required this.handsOnOk,
    this.timeToFirst,
    required this.avgBpm,
    required this.avgDepth,
    required this.targetDepthLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.emergencyRed, AppColors.emergencyDark],
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        children: [
          // Icon + title
          Container(
            width:  80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.textOnDark.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.emergency_rounded,
              color: AppColors.textOnDark,
              size:  AppSpacing.iconXl,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'CPR Session Complete',
            style: AppTypography.poppins(
                size: 20, weight: FontWeight.w700, color: AppColors.textOnDark),
          ),
          if (isPediatric) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
              decoration: AppDecorations.chip(
                color: AppColors.textOnDark,
                bg:    AppColors.textOnDark.withValues(alpha: 0.2),
              ),
              child: Text('PEDIATRIC CPR',
                  style: AppTypography.badge(
                      size: 10, color: AppColors.textOnDark)),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          // Duration + compressions stat bar
          Container(
            decoration: AppDecorations.darkStatTile(),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _SummaryCell(value: durationFormatted,   label: 'DURATION'),
                  _VDivider(),
                  _SummaryCell(value: '$compressionCount', label: 'COMPRESSIONS'),
                  _VDivider(),
                  _SummaryCell(
                    value: avgBpm > 0 ? '${avgBpm.round()}' : '—',
                    label: 'AVG BPM',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // 4 key quality tiles
          Row(
            children: [
              _EmergencyTile(
                label: 'CORRECT DEPTH',
                value: '$correctDepthPct%',
                ok:    correctDepthPct >= 70,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EmergencyTile(
                label: 'CORRECT RATE',
                value: '$correctRatePct%',
                ok:    correctRatePct >= 70,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _EmergencyTile(
                label: 'HANDS-ON TIME',
                value: handsOnPct,
                ok:    handsOnOk,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EmergencyTile(
                label: 'TIME TO FIRST',
                value: timeToFirst != null && timeToFirst! > 0
                    ? '${timeToFirst!.toStringAsFixed(1)}s'
                    : '—',
                ok:    timeToFirst != null && timeToFirst! <= 10,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyTile extends StatelessWidget {
  final String label;
  final String value;
  final bool   ok;

  const _EmergencyTile({
    required this.label,
    required this.value,
    required this.ok,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.success : AppColors.warning;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color:        AppColors.textOnDark.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
          border: Border.all(
              color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.poppins(
                size:   22,
                weight: FontWeight.w700,
                color:  color,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.badge(
                  size:  9,
                  color: AppColors.textOnDark.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionCard — expandable section
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatefulWidget {
  final String    title;
  final IconData  icon;
  final Color     iconColor;
  final bool      startOpen;
  final Widget    child;

  const _SectionCard({
    required this.title,
    required this.icon,
    this.iconColor = AppColors.primary,
    this.startOpen = false,
    required this.child,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.startOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          // Header row — always visible
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.cardPadding),
              child: Row(
                children: [
                  Container(
                    width:  32,
                    height: 32,
                    decoration: AppDecorations.iconRounded(
                      bg:     widget.iconColor.withValues(alpha: 0.1),
                      radius: AppSpacing.cardRadiusSm,
                    ),
                    child: Icon(
                      widget.icon,
                      size:  AppSpacing.iconSm,
                      color: widget.iconColor,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.subheading(size: 14),
                    ),
                  ),
                  AnimatedRotation(
                    turns:    _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary,
                      size:  AppSpacing.iconSm,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          AnimatedCrossFade(
            firstChild:  const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                children: [
                  const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.divider),
                  const SizedBox(height: AppSpacing.sm),
                  widget.child,
                ],
              ),
            ),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TappableGraphs — wraps SessionGraphs, each graph tappable for full-screen
// ─────────────────────────────────────────────────────────────────────────────

class _TappableGraphs extends StatelessWidget {
  final SessionDetail session;
  final double        targetDepthMin;
  final double        targetDepthMax;

  const _TappableGraphs({
    required this.session,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  void _showFullScreen(BuildContext context, Widget graph, String title) {
    context.push(Scaffold(
      backgroundColor: AppColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor:        AppColors.surfaceWhite,
        elevation:              0,
        scrolledUnderElevation: 0,
        title: Text(title, style: AppTypography.heading(size: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(child: graph),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final events = session.compressions;
    if (events.isEmpty) return const SizedBox.shrink();

    final depthGraph = _GraphCard(
      title:      'Compression Depth',
      unit:       'cm',
      minY:       0,
      maxY:       9,
      targetMin:  targetDepthMin,
      targetMax:  targetDepthMax,
      spots: events.map((e) => FlSpot(e.timestampSec, e.depth)).toList(),
      lineColor:       AppColors.primary,
      leftLabels:      const ['0', '3', '6', '9'],
      leftLabelValues: const [0, 3, 6, 9],
      targetLabel:
      '${targetDepthMin.toStringAsFixed(0)}–${targetDepthMax.toStringAsFixed(0)} cm',
    );

    final rateGraph = _GraphCard(
      title:     'Compression Rate',
      unit:      'BPM',
      minY:      60,
      maxY:      160,
      targetMin: CprTargets.rateMin,
      targetMax: CprTargets.rateMax,
      spots: events
          .map((e) => FlSpot(
        e.timestampSec,
        e.instantaneousRate > 0 ? e.instantaneousRate : e.frequency,
      ))
          .toList(),
      lineColor:       AppColors.success,
      leftLabels:      const ['60', '100', '120', '160'],
      leftLabelValues: const [60, 100, 120, 160],
      targetLabel:     '100–120 BPM',
    );

// Build fatigue trend spots: 5-compression rolling avg of depth
    List<FlSpot> fatigueTrendSpots = [];
    if (session.fatigueOnsetIndex > 0 && events.length >= 5) {
      for (int i = 4; i < events.length; i++) {
        final avg = (events[i-4].depth + events[i-3].depth + events[i-2].depth +
            events[i-1].depth + events[i].depth) / 5.0;
        fatigueTrendSpots.add(FlSpot(events[i].timestampSec, avg));
      }
    }

    final fatigueGraph = fatigueTrendSpots.isNotEmpty
        ? _GraphCard(
      title:           'Depth Trend (Fatigue)',
      unit:            'cm',
      minY:            0,
      maxY:            9,
      targetMin:       targetDepthMin,
      targetMax:       targetDepthMax,
      spots:           fatigueTrendSpots,
      lineColor:       AppColors.cprOrange,
      leftLabels:      const ['0', '3', '6', '9'],
      leftLabelValues: const [0, 3, 6, 9],
      targetLabel:     '${targetDepthMin.toStringAsFixed(0)}–${targetDepthMax.toStringAsFixed(0)} cm',
    )
        : null;

    return Column(
      children: [
        GestureDetector(
          onTap: () => _showFullScreen(context, depthGraph, 'Compression Depth'),
          child: Stack(
            children: [
              depthGraph,
              Positioned(
                top: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  ),
                  child: const Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: () => _showFullScreen(context, rateGraph, 'Compression Rate'),
          child: Stack(
            children: [
              rateGraph,
              Positioned(
                top: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  ),
                  child: const Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.success),
                ),
              ),
            ],
          ),
        ),
        if (fatigueGraph != null) ...[
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () => _showFullScreen(context, fatigueGraph, 'Depth Trend (Fatigue)'),
            child: Stack(
              children: [
                fatigueGraph,
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                    ),
                    child: const Icon(Icons.fullscreen_rounded, size: 16, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section content widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CompressionQualitySection extends StatelessWidget {
  final SessionDetail detail;
  final int           compressionCount;
  final String        targetDepthLabel;
  final double        averageDepth;
  final double        avgWristAngle;

  const _CompressionQualitySection({
    required this.detail,
    required this.compressionCount,
    required this.targetDepthLabel,
    required this.averageDepth,
    required this.avgWristAngle,
  });

  String _pct(int v) => compressionCount > 0
      ? '${(v / compressionCount * 100).round()}%'
      : '—';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Depth group
        const _GroupLabel('Depth'),
        _DetailRow(
          icon:  Icons.compress_rounded,
          label: 'Average Depth',
          value: averageDepth > 0
              ? '${averageDepth.toStringAsFixed(1)} cm'
              : '—',
          note:  'Target: $targetDepthLabel',
        ),
        if (detail.peakDepth > 0)
          _DetailRow(
            icon:  Icons.keyboard_double_arrow_down_rounded,
            label: 'Peak Depth',
            value: '${detail.peakDepth.toStringAsFixed(1)} cm',
            note:  'Maximum single compression',
          ),
        _DetailRow(
          icon:  Icons.straighten_rounded,
          label: 'Depth Consistency',
          value: detail.depthConsistency > 0
              ? '${detail.depthConsistency.round()}%'
              : '—',
          note:  'Compressions within target',
          valueColor: detail.depthConsistency >= 80
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:  Icons.show_chart_rounded,
          label: 'Depth Variability (SD)',
          value: detail.depthSD > 0
              ? '${detail.depthSD.toStringAsFixed(2)} cm'
              : '—',
          note:  'Lower = more consistent',
        ),
        if (detail.averageEffectiveDepth > 0)
          _DetailRow(
            icon:  Icons.architecture_rounded,
            label: 'Effective Depth',
            value: '${detail.averageEffectiveDepth.toStringAsFixed(1)} cm',
            note:  'Angle-corrected — accounts for wrist tilt',
          ),

        const SizedBox(height: AppSpacing.sm),
        // Rate group
        const _GroupLabel('Rate'),
        _DetailRow(
          icon:  Icons.speed_rounded,
          label: 'Rate Consistency',
          value: detail.frequencyConsistency > 0
              ? '${detail.frequencyConsistency.round()}%'
              : '—',
          note:  'Within 100–120 BPM',
          valueColor: detail.frequencyConsistency >= 80
              ? AppColors.success : AppColors.warning,
        ),
        if (detail.rateVariability > 0)
          _DetailRow(
            icon:  Icons.graphic_eq_rounded,
            label: 'Rate Variability',
            value: '${detail.rateVariability.toStringAsFixed(0)} ms',
            note:  'SD of inter-compression intervals',
            valueColor: detail.rateVariability < 100
                ? AppColors.success : AppColors.warning,
          ),

        const SizedBox(height: AppSpacing.sm),
        // Recoil + Force group
        const _GroupLabel('Recoil & Force'),
        _DetailRow(
          icon:  Icons.sync_rounded,
          label: 'Full Recoil',
          value: _pct(detail.correctRecoil),
          note:  'Complete chest decompression',
          valueColor: compressionCount > 0 &&
              (detail.correctRecoil / compressionCount) >= 0.80
              ? AppColors.success : AppColors.warning,
        ),
        if (detail.leaningCount > 0)
          _DetailRow(
            icon:       Icons.warning_amber_rounded,
            label:      'Leaning Detected',
            value:      '${detail.leaningCount}×',
            note:       'Incomplete decompression',
            iconColor:  AppColors.warning,
            valueColor: AppColors.warning,
          ),
        if (detail.overForceCount > 0)
          _DetailRow(
            icon:       Icons.fitness_center_rounded,
            label:      'Over-Force Events',
            value:      '${detail.overForceCount}×',
            note:       'Force exceeded safe threshold',
            iconColor:  AppColors.error,
            valueColor: AppColors.error,
          ),
        if (detail.tooDeepCount > 0)
          _DetailRow(
            icon:       Icons.arrow_downward_rounded,
            label:      'Too Deep',
            value:      '${detail.tooDeepCount}×',
            note:       'Exceeded maximum depth',
            iconColor:  AppColors.error,
            valueColor: AppColors.error,
          ),

        const SizedBox(height: AppSpacing.sm),
        // Posture group
        const _GroupLabel('Posture'),
        _DetailRow(
          icon:  Icons.accessibility_new_rounded,
          label: 'Correct Posture',
          value: compressionCount > 0
              ? '${(detail.correctPosture / compressionCount * 100).round()}%'
              : '—',
          note: 'Wrist alignment within 15°',
        ),
        if (avgWristAngle > 0)
          _DetailRow(
            icon:  Icons.straighten_rounded,
            label: 'Avg Wrist Alignment',
            value: '${avgWristAngle.toStringAsFixed(1)}°',
            note: avgWristAngle <= 15
                ? 'Good — within target range'
                : avgWristAngle <= 25
                ? 'Try keeping arms straighter'
                : 'Significant tilt — lock elbows, arms perpendicular',
            valueColor: avgWristAngle <= 15
                ? AppColors.success
                : avgWristAngle <= 25
                ? AppColors.warning
                : AppColors.error,
          ),
        if (detail.consecutiveGoodPeak > 0)
          _DetailRow(
            icon:      Icons.local_fire_department_rounded,
            label:     'Best Streak',
            value:     '${detail.consecutiveGoodPeak} compressions',
            note:      'Longest perfect run',
            iconColor: AppColors.success,
          ),
      ],
    );
  }
}

class _FlowSection extends StatelessWidget {
  final SessionDetail detail;
  const _FlowSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          icon:       Icons.touch_app_outlined,
          label:      'Hands-On Time',
          value:      detail.handsOnPct,
          note:       'Target ≥ 80%',
          valueColor: detail.handsOnRatio >= 0.80
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:       Icons.pause_circle_outline_rounded,
          label:      'No-Flow Time',
          value:      detail.noFlowTime > 0
              ? '${detail.noFlowTime.toStringAsFixed(1)}s'
              : '0s',
          note:       '${detail.noFlowIntervals} unplanned pause(s) > 2 s',
          valueColor: detail.noFlowTime > 5
              ? AppColors.warning : AppColors.success,
        ),
        _DetailRow(
          icon:       Icons.timer_outlined,
          label:      'Time to First Compression',
          value:      detail.timeToFirstCompression > 0
              ? '${detail.timeToFirstCompression.toStringAsFixed(1)}s'
              : '—',
          note:       'From session start',
          valueColor: detail.timeToFirstCompression > 5
              ? AppColors.warning : AppColors.success,
        ),
      ],
    );
  }
}

class _VentilationSection extends StatelessWidget {
  final SessionDetail detail;
  const _VentilationSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          icon:  Icons.air_rounded,
          label: 'Ventilation Cycles',
          value: '${detail.ventilationCount}',
        ),
        _DetailRow(
          icon:       Icons.check_circle_outline_rounded,
          label:      'Compliance',
          value:      '${detail.ventilationCompliance.round()}%',
          valueColor: detail.ventilationCompliance >= 80
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:  Icons.vaccines_rounded,
          label: 'Correct Ventilations',
          value: '${detail.correctVentilations}',
        ),
      ],
    );
  }
}

class _FatigueSection extends StatelessWidget {
  final SessionDetail detail;
  const _FatigueSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (detail.rescuerSwapCount > 0)
          _DetailRow(
            icon:  Icons.swap_horiz_rounded,
            label: 'Rescuer Swap Prompts',
            value: '${detail.rescuerSwapCount}×',
            note:  '2-minute alert count',
          ),
        if (detail.fatigueOnsetIndex > 0)
          _DetailRow(
            icon:       Icons.trending_down_rounded,
            label:      'Fatigue Onset',
            value:      'Compression #${detail.fatigueOnsetIndex}',
            note:       'When physiological fatigue first detected',
            iconColor:  AppColors.warning,
            valueColor: AppColors.warning,
          ),
        if (detail.consecutiveGoodPeak > 0)
          _DetailRow(
            icon:      Icons.local_fire_department_rounded,
            label:     'Best Streak',
            value:     '${detail.consecutiveGoodPeak} compressions',
            note:      'Longest unbroken run of perfect compressions',
            iconColor: AppColors.success,
          ),
      ],
    );
  }
}

class _EmergencyQualitySection extends StatelessWidget {
  final SessionDetail detail;
  final int           compressionCount;
  final String        targetDepthLabel;
  final double        averageDepth;
  final double        averageFrequency;
  final int           correctRecoil;

  const _EmergencyQualitySection({
    required this.detail,
    required this.compressionCount,
    required this.targetDepthLabel,
    required this.averageDepth,
    required this.averageFrequency,
    required this.correctRecoil,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          icon:  Icons.compress_rounded,
          label: 'Average Depth',
          value: averageDepth > 0
              ? '${averageDepth.toStringAsFixed(1)} cm'
              : '—',
          note:  'Target: $targetDepthLabel',
          valueColor: averageDepth >= 5.0 && averageDepth <= 6.0
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:  Icons.speed_rounded,
          label: 'Average Rate',
          value: averageFrequency > 0
              ? '${averageFrequency.round()} BPM'
              : '—',
          note:  'Target: 100–120 BPM',
          valueColor: averageFrequency >= 100 && averageFrequency <= 120
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:       Icons.compress_rounded,
          label:      'Chest Compression Fraction',
          value:      detail.handsOnPct,
          note:       'Target ≥ 80% (AHA/ERC 2020)',
          valueColor: detail.handsOnRatio >= 0.80
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:  Icons.sync_rounded,
          label: 'Full Recoil',
          value: compressionCount > 0
              ? '${(correctRecoil / compressionCount * 100).round()}%'
              : '—',
          note:  'Compressions with complete decompression',
          valueColor: compressionCount > 0 &&
              (correctRecoil / compressionCount) >= 0.80
              ? AppColors.success : AppColors.warning,
        ),
        if (detail.noFlowTime > 0)
          _DetailRow(
            icon:       Icons.pause_circle_outline_rounded,
            label:      'No-Flow Time',
            value:      '${detail.noFlowTime.toStringAsFixed(1)}s',
            note:       'Unplanned pauses > 2 s',
            valueColor: detail.noFlowTime > 5
                ? AppColors.warning : AppColors.success,
          ),
      ],
    );
  }
}

class _PulseChecksSection extends StatelessWidget {
  final SessionDetail detail;
  const _PulseChecksSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          icon:  Icons.sensors_rounded,
          label: 'Checks Prompted',
          value: '${detail.pulseChecksPrompted}',
        ),
        _DetailRow(
          icon:  Icons.check_circle_outline_rounded,
          label: 'Checks Completed',
          value: '${detail.pulseChecksComplied}',
        ),
        ...detail.pulseChecks.map((pc) {
          final color = pc.detected
              ? AppColors.success
              : pc.isUncertain
              ? AppColors.warning
              : AppColors.textSecondary;
          return _DetailRow(
            icon:       Icons.favorite_border_rounded,
            label:      'Check #${pc.intervalNumber}',
            value:      pc.detected ? 'Present'
                : pc.isUncertain ? 'Uncertain'
                : 'Absent',
            note: pc.detectedBpm > 0
                ? '${pc.detectedBpm.toStringAsFixed(0)} BPM · ${pc.confidence}% confidence'
                : null,
            iconColor:  color,
            valueColor: color,
          );
        }),
      ],
    );
  }
}

class _BiometricsSection extends StatelessWidget {
  final SessionDetail?  detail;
  final SessionSummary? summary;
  final double?         rescuerHR;
  final double?         rescuerSpO2;

  const _BiometricsSection({
    required this.detail,
    required this.summary,
    required this.rescuerHR,
    required this.rescuerSpO2,
  });

  @override
  Widget build(BuildContext context) {
    final patientTemp = detail?.patientTemperature ?? summary?.patientTemperature;

    return Column(
      children: [
        if (rescuerHR != null)
          _DetailRow(
            icon:      Icons.monitor_heart_outlined,
            label:     'Rescuer HR (last pause)',
            value:     '${rescuerHR!.toStringAsFixed(0)} bpm',
            iconColor: AppColors.primary,
          ),
        if (rescuerSpO2 != null)
          _DetailRow(
            icon:  Icons.air_rounded,
            label: 'Rescuer SpO₂ (last pause)',
            value: '${rescuerSpO2!.toStringAsFixed(0)}%',
          ),
        if (patientTemp != null)
          _DetailRow(
            icon:      Icons.thermostat_rounded,
            label:     'Patient Skin Temperature',
            value:     '${patientTemp.toStringAsFixed(1)}°C',
            note:      'Measured via fingertip sensor',
            iconColor: AppColors.error,
          ),
        if (detail?.ambientTempStart != null)
          _DetailRow(
            icon:      Icons.thermostat_rounded,
            label:     'Room Temperature',
            value:     '${detail!.ambientTempStart!.toStringAsFixed(1)}°C',
            note:      'Ambient — measured at session start',
            iconColor: AppColors.textSecondary,
          ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: AppTypography.badge(
                size: 10, color: AppColors.textDisabled),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(
              height: AppSpacing.dividerThickness,
              color:  AppColors.divider,
            ),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _GraphCard
// ─────────────────────────────────────────────────────────────────────────────

class _GraphCard extends StatelessWidget {
  final String       title;
  final String       unit;
  final double       minY;
  final double       maxY;
  final double       targetMin;
  final double       targetMax;
  final List<FlSpot> spots;
  final Color        lineColor;
  final List<String> leftLabels;
  final List<double> leftLabelValues;
  final String       targetLabel;

  const _GraphCard({
    required this.title,
    required this.unit,
    required this.minY,
    required this.maxY,
    required this.targetMin,
    required this.targetMax,
    required this.spots,
    required this.lineColor,
    required this.leftLabels,
    required this.leftLabelValues,
    required this.targetLabel,
  });

  double _niceInterval(double maxX) {
    if (maxX <= 30)  return 10;
    if (maxX <= 60)  return 15;
    if (maxX <= 120) return 30;
    return 60;
  }

  @override
  Widget build(BuildContext context) {
    final maxX = spots.isEmpty ? 60.0 : spots.last.x;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width:  AppSpacing.xs + AppSpacing.xxs,
              height: AppSpacing.md,
              decoration: BoxDecoration(
                color:        lineColor,
                borderRadius: BorderRadius.circular(AppSpacing.xxs),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(title, style: AppTypography.subheading(size: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical:   AppSpacing.xxs,
              ),
              decoration: AppDecorations.chip(
                color: lineColor,
                bg:    lineColor.withValues(alpha: 0.08),
              ),
              child: Text(
                'Target: $targetLabel',
                style: AppTypography.badge(size: 9, color: lineColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: maxX,
              rangeAnnotations: RangeAnnotations(
                horizontalRangeAnnotations: [
                  HorizontalRangeAnnotation(
                    y1:    targetMin,
                    y2:    targetMax,
                    color: lineColor.withValues(alpha: 0.10),
                  ),
                ],
              ),
              gridData: FlGridData(
                show:             true,
                drawVerticalLine: false,
                horizontalInterval: (maxY - minY) / 3,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color:       AppColors.divider,
                  strokeWidth: AppSpacing.dividerThickness,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles:   true,
                    reservedSize: 22,
                    interval:     _niceInterval(maxX),
                    getTitlesWidget: (value, meta) {
                      if (value == meta.min && value != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          '${value.toInt()}s',
                          style: AppTypography.caption(
                              color: AppColors.textDisabled),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles:   true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      final idx = leftLabelValues.indexOf(value);
                      if (idx == -1) return const SizedBox.shrink();
                      return Text(
                        leftLabels[idx],
                        style: AppTypography.caption(
                            color: AppColors.textDisabled),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots:           spots,
                  isCurved:        true,
                  curveSmoothness: 0.3,
                  color:           lineColor,
                  barWidth:        2,
                  dotData: FlDotData(
                    show: spots.length < 30,
                    getDotPainter: (spot, pct, bar, idx) =>
                        FlDotCirclePainter(
                          radius:      3,
                          color:       lineColor,
                          strokeWidth: 1.5,
                          strokeColor: AppColors.surfaceWhite,
                        ),
                  ),
                  belowBarData: BarAreaData(
                    show:  true,
                    color: lineColor.withValues(alpha: 0.06),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor:      (_) => AppColors.primaryDark,
                  tooltipRoundedRadius: AppSpacing.cardRadiusSm,
                  getTooltipItems: (spots) => spots
                      .map((s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(1)} $unit',
                    AppTypography.badge(
                      size:  10,
                      color: AppColors.textOnDark,
                    ),
                  ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            _TargetLine(color: lineColor, label: '${targetMin.toStringAsFixed(0)} $unit'),
            const Spacer(),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Note card + dialog
// ─────────────────────────────────────────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final String?      note;
  final bool         canEdit;
  final VoidCallback onTap;

  const _NoteCard({
    required this.note,
    required this.canEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:        canEdit ? onTap : null,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        width:      double.infinity,
        padding:    const EdgeInsets.all(AppSpacing.md),
        decoration: AppDecorations.card(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notes_rounded,
                color: AppColors.primary, size: AppSpacing.iconSm),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Note', style: AppTypography.subheading()),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    note?.isNotEmpty == true ? note! : 'Tap to add a note…',
                    style: AppTypography.bodyMedium(
                      color: note?.isNotEmpty == true
                          ? AppColors.textPrimary
                          : AppColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            if (canEdit)
              const Icon(Icons.edit_outlined,
                  size: AppSpacing.iconSm, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Past sessions button
// ─────────────────────────────────────────────────────────────────────────────

class _PastSessionsButton extends StatelessWidget {
  const _PastSessionsButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(const SessionHistoryScreen()),
      child: Container(
        width:      double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical:   AppSpacing.buttonPaddingV,
          horizontal: AppSpacing.cardPadding,
        ),
        decoration: AppDecorations.card(),
        child: Row(
          children: [
            Container(
              width:      AppSpacing.iconXl,
              height:     AppSpacing.iconXl,
              decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
              child: const Icon(Icons.history_rounded,
                  color: AppColors.primary, size: AppSpacing.iconMd),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Past Sessions',
                      style: AppTypography.bodyMedium(size: 15)),
                  Text('View your session history',
                      style: AppTypography.caption()),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: AppSpacing.iconMd),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private UI helpers
// ─────────────────────────────────────────────────────────────────────────────

class _TargetLine extends StatelessWidget {
  final Color  color;
  final String label;
  const _TargetLine({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width:  AppSpacing.md,
          height: AppSpacing.dividerThickness,
          color:  color.withValues(alpha: 0.4),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label,
            style: AppTypography.caption(color: color.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: AppTypography.numericDisplay(
                    size: 20, color: AppColors.textOnDark)),
            const SizedBox(height: AppSpacing.xxs),
            Text(label,
                style: AppTypography.badge(
                    size: 9,
                    color: AppColors.textOnDark.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.dividerThickness,
      color: AppColors.textOnDark.withValues(alpha: 0.2),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: AppDecorations.darkStatTile(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: AppTypography.numericDisplay(
                  size: 18, color: AppColors.textOnDark)),
          const SizedBox(height: AppSpacing.xxs),
          Text(label,
              textAlign: TextAlign.center,
              style: AppTypography.badge(
                  size: 9,
                  color: AppColors.textOnDark.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final String?  note;
  final Color    iconColor;
  final Color?   valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.iconColor  = AppColors.primary,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width:  AppSpacing.iconLg,
            height: AppSpacing.iconLg,
            decoration: AppDecorations.iconRounded(
              bg:     iconColor.withValues(alpha: 0.10),
              radius: AppSpacing.cardRadiusSm,
            ),
            child: Icon(icon, color: iconColor, size: AppSpacing.iconSm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyMedium(size: 13)),
                if (note != null)
                  Text(note!,
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
              ],
            ),
          ),
          Text(value,
              style: AppTypography.bodyBold(
                  size:  14,
                  color: valueColor ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unsynced session banner
// ─────────────────────────────────────────────────────────────────────────────

class _UnsyncedBanner extends StatelessWidget {
  const _UnsyncedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      decoration: AppDecorations.tintedCard(
        radius: AppSpacing.cardRadius,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size:  AppSpacing.iconSm,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Saved locally — will sync when you log in and reconnect.',
              style: AppTypography.caption(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _HDivider extends StatelessWidget {
  const _HDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Divider(
          height: AppSpacing.dividerThickness, color: AppColors.divider),
    );
  }
}

class _PersonalBestComparison extends ConsumerWidget {
  final double currentGrade;
  final String scenario;

  const _PersonalBestComparison({
    required this.currentGrade,
    required this.scenario,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);

    return summaries.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        final trainingSessions = sessions
            .where((s) => s.isTraining && s.totalGrade > 0)
            .toList();

        if (trainingSessions.isEmpty) return const SizedBox.shrink();

        final best = trainingSessions
            .map((s) => s.totalGrade)
            .reduce((a, b) => a > b ? a : b);

        final isNewBest = currentGrade > 0 && currentGrade >= best;
        final diff      = currentGrade - best;

        return Container(
          padding:    const EdgeInsets.all(AppSpacing.md),
          decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadius),
          child: Row(
            children: [
              Icon(
                isNewBest
                    ? Icons.emoji_events_rounded
                    : Icons.bar_chart_rounded,
                color: isNewBest ? AppColors.warning : AppColors.primary,
                size:  AppSpacing.iconMd,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isNewBest ? '🏆 New Personal Best!' : 'Personal Best',
                      style: AppTypography.label(
                        color: isNewBest
                            ? AppColors.warning
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      isNewBest
                          ? '${currentGrade.toStringAsFixed(1)}% — your best score yet!'
                          : 'Your best is ${best.toStringAsFixed(1)}%  '
                          '(${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}% vs this session)',
                      style: AppTypography.body(size: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}