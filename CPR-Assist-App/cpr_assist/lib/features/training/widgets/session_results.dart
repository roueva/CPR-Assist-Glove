import 'dart:ui';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/session_provider.dart';
import '../../account/screens/login_screen.dart';
import '../screens/session_service.dart';
import '../services/achievement_service.dart';
import '../services/certificate_service.dart';
import '../services/compression_event.dart';
import '../services/rescuer_vital_snapshot.dart';
import '../services/session_detail.dart';
import '../services/session_local_storage.dart';
import 'cpr_chart_helpers.dart';
import 'export_bottom_sheet.dart';
import 'session_history.dart';

part 'session_results_shared.dart';
part 'session_results_vitals_dialogs.dart';
part 'session_results_charts.dart';
part 'session_results_emergency.dart';
part 'session_results_layout.dart';
part 'session_results_training_tabs.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionResultsScreen
//
// Training mode  → 3-tab layout: Overview / Metrics / Charts
//   Header: gamified grade card with score ring + sub-metric rings (no letter
//           grades), personal best banner, scenario badge
//
// Emergency mode → single-scroll layout: incident header, pulse/ROSC card,
//   CPR quality summary, timeline, ventilation, biometrics
//
// Both modes: date/time prominent, note card, export, delete, past-sessions
// ─────────────────────────────────────────────────────────────────────────────

class SessionResultsScreen extends ConsumerStatefulWidget {
  final SessionDetail detail;
  final int?          sessionNumber;

  const SessionResultsScreen({
    super.key,
    required this.detail,
    this.sessionNumber,
  });

  @override
  ConsumerState<SessionResultsScreen> createState() =>
      _SessionResultsScreenState();
}

class _SessionResultsScreenState
    extends ConsumerState<SessionResultsScreen>
    with SingleTickerProviderStateMixin {


  String? _note;
  List<String> _previouslyUnlockedIds  = [];
  List<String> _previouslyEarnedCertIds = [];
  late TabController _tabController;

  SessionDetail get _d => widget.detail;

  // ── Init ────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _note = _d.note;
    _tabController = TabController(length: 3, vsync: this);

    if (!_isEmergency) {
      _previouslyUnlockedIds   = _computePreviouslyUnlocked();
      _previouslyEarnedCertIds = _computePreviouslyEarnedCerts();
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNewAchievements());
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  bool get _isPersonalBest {
    final summaries = ref.watch(sessionSummariesProvider).valueOrNull ?? [];
    final start = _d.sessionStart;
    final training = summaries
        .where((s) => s.isTraining && s.totalGrade > 0)
        .where((s) =>
    s.sessionStart?.millisecondsSinceEpoch != start.millisecondsSinceEpoch)
        .toList();
    if (training.isEmpty) return _grade > 0;
    final best = training.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);
    return _grade > 0 && _grade >= best;
  }


  // ── Achievement helpers ─────────────────────────────────────────────────────
  List<String> _computePreviouslyUnlocked() {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start = _d.sessionStart;
    final previous = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch != start.millisecondsSinceEpoch,
    ).toList();
    return AchievementService.compute(previous)
        .where((a) => a.unlocked).map((a) => a.id).toList();
  }

  List<String> _computePreviouslyEarnedCerts() {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start = _d.sessionStart;
    final previous = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch != start.millisecondsSinceEpoch,
    ).toList();
    return CertificateService.compute(previous)
        .where((c) => c.earned).map((c) => c.id).toList();
  }

  void _checkNewAchievements() {
    if (!mounted) return;
    final achievements  = ref.read(achievementsProvider);
    final newlyUnlocked = achievements
        .where((a) => a.unlocked && !_previouslyUnlockedIds.contains(a.id))
        .toList();
    for (int i = 0; i < newlyUnlocked.length; i++) {
      final a = newlyUnlocked[i];
      Future.delayed(Duration(milliseconds: 600 + i * 900), () {
        if (mounted) {
          UIHelper.showSnackbar(context,
            message: '${a.emoji} Achievement unlocked: ${a.title}',
            icon: Icons.emoji_events_rounded);
        }
      });
    }
    final certs    = ref.read(certificatesProvider);
    final newCerts = certs
        .where((c) => c.earned && !_previouslyEarnedCertIds.contains(c.id))
        .toList();
    for (int i = 0; i < newCerts.length; i++) {
      final c = newCerts[i];
      Future.delayed(
          Duration(milliseconds: 1200 + newlyUnlocked.length * 900 + i * 1000), () {
        if (mounted) {
          UIHelper.showSnackbar(context,
            message: '${c.emoji} Certificate earned: ${c.title}!',
            icon: Icons.workspace_premium_rounded);
        }
      });
    }
  }

// ── Mode / scenario helpers ─────────────────────────────────────────────────
  bool   get _isEmergency  => _d.isEmergency;
  String get _scenario     => _d.scenario;

  String get _ventilationRatioLabel {
    switch (_d.ventilationRatio) {
      case 'compressions_only': return 'No ventilations';
      case '15:2':              return '15:2 ratio';
      default:                  return '30:2 ratio';
    }
  }

  bool   get _isPediatric  => _scenario == 'pediatric';
  bool   get _isNoFeedback => _d.isNoFeedback;

  double get _targetDepthMin =>
      _isPediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;

  double get _targetDepthMax =>
      _isPediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;

  String get _targetDepthLabel =>
      '${_targetDepthMin.toStringAsFixed(0)}–${_targetDepthMax.toStringAsFixed(0)} cm';

  // ── Data helpers ────────────────────────────────────────────────────────────
  double get _grade             => _d.totalGrade;
  int    get _compressionCount  => _d.compressionCount;
  String get _durationFormatted => _d.durationFormatted;
  double get _averageFrequency  => _d.averageFrequency;
  double get _averageDepth      => _d.averageDepth;
  String get _dateTimeFormatted => _d.dateTimeFormatted;
  int    get _correctDepth      => _d.correctDepth;
  int    get _correctFrequency  => _d.correctFrequency;
  int    get _correctRecoil     => _d.correctRecoil;

  double get _depthPct =>
      _compressionCount > 0 ? (_correctDepth / _compressionCount * 100) : 0;

  double get _ratePct =>
      _compressionCount > 0 ? (_correctFrequency / _compressionCount * 100) : 0;

  double get _recoilPct =>
      _compressionCount > 0 ? (_correctRecoil / _compressionCount * 100) : 0;

  double get _avgWristAngle {
    final c = _d.compressions;
    if (c.isEmpty) return 0.0;
    return c.map((e) => e.wristAlignmentAngle).reduce((a, b) => a + b) / c.length;
  }

  double? get _rescuerHR    => _d.rescuerHRLastPause;
  double? get _rescuerSpO2  => _d.rescuerSpO2LastPause;
  bool    get _hasBiometrics => _rescuerHR != null || _rescuerSpO2 != null;

  String get _motivationalLabel {
    if (_grade >= 90) return 'Outstanding performance!';
    if (_grade >= 75) return 'Great work, keep it up!';
    if (_grade >= 55) return 'Good effort, room to grow!';
    return 'Keep practicing, you\'ll get there!';
  }

  String _pct(int value) {
    if (_compressionCount == 0) return '—';
    return '${(value / _compressionCount * 100).round()}%';
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  Future<void> _exportSession() async {
    await ExportBottomSheet.showForSingleSession(
      context,
      summary: SessionSummary.fromDetail(_d),
      detail:  _d,
    );
  }

  Future<void> _confirmDeleteSession() async {
    final confirmed = await AppDialogs.showDestructiveConfirm(context,
      icon:         Icons.delete_outline_rounded,
      iconColor:    AppColors.emergency,
      iconBg:       AppColors.errorBg,
      title:        'Delete Session?',
      message:      'This permanently deletes this session and all its data.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.emergency,
      cancelLabel:  'Cancel',
    );
    if (confirmed != true || !mounted) return;

    final service = ref.read(sessionServiceProvider);
    // Build a summary view of the current detail. deleteSummary handles all
    // three cases: backend+local, backend-only, local-only (id == null).
    final summary = SessionSummary.fromDetail(_d);
    final ok = await service.deleteSummary(summary);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(sessionSummariesProvider);
      context.pop();
      UIHelper.showSuccess(context, 'Session deleted');
    } else {
      UIHelper.showError(context, 'Failed to delete. Check your connection.');
    }
  }

  Future<void> _editNote() async {
    final result = await AppDialogs.showNoteEditor(context, initialNote: _note);
    if (result == null) return;
    final sessionId = _d.id;
    if (sessionId != null) {
      final service = ref.read(sessionServiceProvider);
      final ok = await service.updateNote(sessionId, result.isEmpty ? null : result);
      if (!mounted) return;
      if (ok) {
        ref.invalidate(sessionSummariesProvider);
        setState(() => _note = result.isEmpty ? null : result);
        UIHelper.showSuccess(context, 'Note saved');
      } else {
        UIHelper.showError(context, 'Failed to save note. Check your connection.');
      }
    } else {
      final newNote = result.isEmpty ? null : result;
      setState(() => _note = newNote);
      await SessionLocalStorage.saveLocal(_d.withNote(newNote));
      ref.invalidate(sessionSummariesProvider);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const canEditNote = true;  // always have a detail now

    // AppBar title
    String title;
    if (widget.sessionNumber != null) {
      title = 'Session ${widget.sessionNumber}';
    } else if (_isEmergency) {
      title = 'Emergency Session';
    } else if (_isNoFeedback) {
      title = 'Training Results';
    } else if (_isPediatric) {
      title = 'Pediatric Training';
    } else {
      title = 'Training Results';
    }

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: _buildAppBar(title),
      body: _isEmergency
          ? _buildEmergencyBody(canEditNote)
          : _buildTrainingBody(canEditNote),
    );
  }

  // ── AppBar ───────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(String title) {
    return AppBar(
      backgroundColor:        AppColors.white,
      elevation:              0,
      scrolledUnderElevation: 0,
      toolbarHeight:          AppSpacing.headerHeight,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
        onPressed: context.pop,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTypography.heading(size: 16, color: AppColors.textPrimary)),
          Text(_dateTimeFormatted,
              style: AppTypography.caption(color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        // Adult / Pediatric chip
        Center(
          child: Container(
            margin: const EdgeInsets.only(right: AppSpacing.xxs),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            decoration: AppDecorations.chip(
              color: AppColors.primary,
              bg: AppColors.primaryLight,
            ),
            child: Text(
              _isPediatric ? 'Pediatric' : 'Adult',
              style: AppTypography.badge(size: 9, color: AppColors.primary),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.download_outlined, color: AppColors.primary),
          tooltip: 'Export',
          onPressed: _exportSession,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary),
          tooltip: 'Delete',
          onPressed: _confirmDeleteSession,
        ),
      ],
    );
  }
  // ════════════════════════════════════════════════════════════════════════════
  // TRAINING BODY — collapsing grade card + 3 tabs
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildTrainingBody(bool canEditNote) {
    final hasGraphs = _d.compressions.isNotEmpty;

    return _CollapsingTrainingLayout(
      grade:             _grade,
      isPediatric:       _isPediatric,
      isNoFeedback:      _isNoFeedback,
      ventilationRatioLabel: _ventilationRatioLabel,
      motivational:      _motivationalLabel,
      depthPct:          _depthPct,
      ratePct:           _ratePct,
      recoilPct:         _recoilPct,
      durationFormatted: _durationFormatted,
      compressionCount:  _compressionCount,
      avgBpm:            _averageFrequency,
      avgDepth:          _averageDepth,
      targetDepthLabel:  _targetDepthLabel,
      onGradeInfo: () => _GradeInfoSheet.show(
        context,
        isPediatric:      _isPediatric,
        grade:            _grade,
        depthPct:         _depthPct,
        ratePct:          _ratePct,
        recoilPct:        _recoilPct,
        correctDepth:     _correctDepth,
        correctFrequency: _correctFrequency,
        correctRecoil:    _correctRecoil,
        compressionCount: _compressionCount,
        ventilationRatioLabel: _ventilationRatioLabel,
      ),
      personalBest: _PersonalBestComparison(
        currentGrade: _grade,
        scenario:     _scenario,
        sessionStart: _d.sessionStart,
      ),
      isPersonalBest: _isPersonalBest,
      tabController: _tabController,
      tabs: [
        _TrainingOverviewTab(
          detail:       _d,
          summary:      SessionSummary.fromDetail(_d),
          note:         _note,
          canEditNote:  canEditNote,
          onEditNote:   _editNote,
          scenario:     _scenario,
          currentGrade: _grade,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
        _TrainingMetricsTab(
          detail:           _d,
          compressionCount: _compressionCount,
          targetDepthLabel: _targetDepthLabel,
          targetDepthMin:   _targetDepthMin,
          targetDepthMax:   _targetDepthMax,
          averageDepth:     _averageDepth,
          avgWristAngle:    _avgWristAngle,
          pctFn:            _pct,
          rescuerHR:        _rescuerHR,
          rescuerSpO2:      _rescuerSpO2,
          hasBiometrics:    _hasBiometrics,
        ),
        _TrainingChartsTab(
          detail:         _d,
          hasGraphs:      hasGraphs,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // EMERGENCY BODY — single scroll
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildEmergencyBody(bool canEditNote) {
    final lastPulseCheck = _d.pulseChecks.lastOrNull;

    return _CollapsingTrainingLayout(
      isEmergency:       true,
      pulseDetected: _d.pulseChecksPrompted > 0
          ? _d.pulseDetectedFinal
          : null,
      pulseDetectedBpm:  lastPulseCheck?.detectedBpm,
      ventilationRatioLabel: _ventilationRatioLabel,
      pulseUncertain:    lastPulseCheck?.isUncertain,
      grade:             0,
      isPediatric:       _isPediatric,
      isNoFeedback:      false,
      motivational:      '',
      depthPct:          _depthPct,
      ratePct:           _ratePct,
      recoilPct:         _recoilPct,
      durationFormatted: _durationFormatted,
      compressionCount:  _compressionCount,
      avgBpm:            _averageFrequency,
      avgDepth:          _averageDepth,
      targetDepthLabel:  _targetDepthLabel,
      onGradeInfo:       () {},
      personalBest:      const SizedBox.shrink(),
      isPersonalBest:    false,
      tabController:     _tabController,
      handsOnPct:           _d.handsOnPct,
      pulseCheckSamples:    lastPulseCheck?.ppgSamples,
      pulseCheckInterval:   lastPulseCheck?.intervalNumber,
      pulseCheckConfidence: lastPulseCheck?.confidence,
      tabs: [
        _EmergencySummaryTab(
          detail:         _d,
          summary:        SessionSummary.fromDetail(_d),
          note:           _note,
          canEditNote:    canEditNote,
          onEditNote:     _editNote,
          onExport:       _exportSession,
          isPediatric:    _isPediatric,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
        _EmergencyPatientTab(
          detail:      _d,
          summary:        SessionSummary.fromDetail(_d),
          isPediatric: _isPediatric,
          rescuerHR:   _rescuerHR,
          rescuerSpO2: _rescuerSpO2,
        ),
        _EmergencyTimelineTab(
          detail:        _d,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Navigation helper — opens SessionResultsScreen with the full detail.
// Fetches the detail before navigating. On failure, shows an error toast.
// ─────────────────────────────────────────────────────────────────────────────
Future<void> openSessionResults(
    BuildContext context,
    WidgetRef ref, {
      required SessionSummary summary,
    }) async {
  final service = ref.read(sessionServiceProvider);
  try {
    final detail = await service.fetchDetailForSummary(summary);
    if (!context.mounted) return;
    await context.push(SessionResultsScreen(detail: detail));
  } catch (e, st) {
    debugPrint('openSessionResults failed: $e\n$st');
    if (context.mounted) {
      UIHelper.showError(context, 'Could not load session details.');
    }
  }
}
