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
    extends ConsumerState<SessionResultsScreen>
    with SingleTickerProviderStateMixin {

  String? _note;
  List<String> _previouslyUnlockedIds  = [];
  List<String> _previouslyEarnedCertIds = [];
  late TabController _tabController;
  SessionDetail? _fetchedDetail;
  bool _isFetchingDetail = false;

  // ── Init ────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _note = widget._detail?.note ?? widget._summary?.note;
    _tabController = TabController(length: 3, vsync: this);

    if (widget._detail != null && !_isEmergency) {
      _previouslyUnlockedIds   = _computePreviouslyUnlocked();
      _previouslyEarnedCertIds = _computePreviouslyEarnedCerts();
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkNewAchievements());
    }

    // If opened from summary and has a backend id, fetch full detail immediately
    if (widget._detail == null && widget._summary?.id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchDetail());
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  bool get _isPersonalBest {
    final summaries = ref.watch(sessionSummariesProvider).valueOrNull ?? [];
    final training = summaries
        .where((s) => s.isTraining && s.totalGrade > 0)
        .where((s) {
      final start = widget._detail?.sessionStart ?? widget._summary?.sessionStart;
      return start == null ||
          s.sessionStart?.millisecondsSinceEpoch != start.millisecondsSinceEpoch;
    })
        .toList();
    if (training.isEmpty) return _grade > 0;
    final best = training.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);
    return _grade > 0 && _grade >= best;
  }

  // ── Achievement helpers ─────────────────────────────────────────────────────
  List<String> _computePreviouslyUnlocked() {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start = widget._detail!.sessionStart;
    final previous = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch != start.millisecondsSinceEpoch,
    ).toList();
    return AchievementService.compute(previous)
        .where((a) => a.unlocked).map((a) => a.id).toList();
  }

  List<String> _computePreviouslyEarnedCerts() {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start = widget._detail!.sessionStart;
    final previous = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch != start.millisecondsSinceEpoch,
    ).toList();
    return CertificateService.compute(previous)
        .where((c) => c.earned).map((c) => c.id).toList();
  }

  List<String> _computePreviouslyUnlockedFrom(SessionDetail detail) {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start = detail.sessionStart;
    final previous = summaries.where((s) =>
    s.sessionStart == null ||
        s.sessionStart!.millisecondsSinceEpoch != start.millisecondsSinceEpoch,
    ).toList();
    return AchievementService.compute(previous)
        .where((a) => a.unlocked).map((a) => a.id).toList();
  }

  List<String> _computePreviouslyEarnedCertsFrom(SessionDetail detail) {
    final summaries = ref.read(sessionSummariesProvider).valueOrNull ?? [];
    final start = detail.sessionStart;
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
        if (mounted) UIHelper.showSnackbar(context,
            message: '${a.emoji} Achievement unlocked: ${a.title}',
            icon: Icons.emoji_events_rounded);
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
        if (mounted) UIHelper.showSnackbar(context,
            message: '${c.emoji} Certificate earned: ${c.title}!',
            icon: Icons.workspace_premium_rounded);
      });
    }
  }

  Future<void> _fetchDetail() async {
    final id = widget._summary?.id;
    if (id == null || _isFetchingDetail) return;
    setState(() => _isFetchingDetail = true);
    try {
      final service = ref.read(sessionServiceProvider);
      final detail  = await service.fetchDetail(id);
      if (!mounted) return;
      setState(() {
        _fetchedDetail      = detail;
        _isFetchingDetail   = false;
        _note               = detail.note ?? _note;
      });
      // Run achievement check now that we have real detail
      if (!detail.isEmergency) {
        _previouslyUnlockedIds   = _computePreviouslyUnlockedFrom(detail);
        _previouslyEarnedCertIds = _computePreviouslyEarnedCertsFrom(detail);
        _checkNewAchievements();
      }
    } catch (_) {
      if (mounted) setState(() => _isFetchingDetail = false);
    }
  }

  // ── Mode / scenario helpers ─────────────────────────────────────────────────
  bool get _isEmergency =>
      (widget._detail?.isEmergency ?? _fetchedDetail?.isEmergency ?? widget._summary?.isEmergency) ?? true;

  String get _scenario =>
      widget._detail?.scenario ?? _fetchedDetail?.scenario ?? widget._summary?.scenario ?? 'standard_adult';

  bool get _isPediatric => _scenario == 'pediatric';

  bool get _isNoFeedback =>
      widget._detail?.isNoFeedback ?? _fetchedDetail?.isNoFeedback ?? widget._summary?.isNoFeedback ?? false;

  SessionDetail? get _effectiveDetail => widget._detail ?? _fetchedDetail;

  double get _targetDepthMin =>
      _isPediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;

  double get _targetDepthMax =>
      _isPediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;

  String get _targetDepthLabel =>
      '${_targetDepthMin.toStringAsFixed(0)}–${_targetDepthMax.toStringAsFixed(0)} cm';

  // ── Data helpers ────────────────────────────────────────────────────────────
  double get _grade =>
      widget._detail?.totalGrade ?? _fetchedDetail?.totalGrade ?? widget._summary?.totalGrade ?? 0;

  int get _compressionCount =>
      widget._detail?.compressionCount ?? _fetchedDetail?.compressionCount ?? widget._summary?.compressionCount ?? 0;


  String get _durationFormatted =>
      widget._detail?.durationFormatted ?? _fetchedDetail?.durationFormatted ?? widget._summary?.durationFormatted ?? '—';

  double get _averageFrequency =>
      widget._detail?.averageFrequency ?? _fetchedDetail?.averageFrequency ?? widget._summary?.averageFrequency ?? 0;

  double get _averageDepth =>
      widget._detail?.averageDepth ?? _fetchedDetail?.averageDepth ?? widget._summary?.averageDepth ?? 0;

  String get _dateTimeFormatted =>
      widget._detail?.dateTimeFormatted ?? _fetchedDetail?.dateTimeFormatted ?? widget._summary?.dateTimeFormatted ?? '—';

  int get _correctDepth =>
      widget._detail?.correctDepth ?? _fetchedDetail?.correctDepth ?? widget._summary?.correctDepth ?? 0;

  int get _correctFrequency =>
      widget._detail?.correctFrequency ?? _fetchedDetail?.correctFrequency ?? widget._summary?.correctFrequency ?? 0;

  int get _correctRecoil =>
      widget._detail?.correctRecoil ?? _fetchedDetail?.correctRecoil ?? widget._summary?.correctRecoil ?? 0;

  double get _depthPct =>
      _compressionCount > 0 ? (_correctDepth / _compressionCount * 100) : 0;

  double get _ratePct =>
      _compressionCount > 0 ? (_correctFrequency / _compressionCount * 100) : 0;

  double get _recoilPct =>
      _compressionCount > 0 ? (_correctRecoil / _compressionCount * 100) : 0;

  double get _avgWristAngle {
    final c = widget._detail?.compressions ?? _fetchedDetail?.compressions;
    if (c == null || c.isEmpty) return 0.0;
    return c.map((e) => e.wristAlignmentAngle).reduce((a, b) => a + b) / c.length;
  }

  double? get _rescuerHR =>
      widget._detail?.rescuerHRLastPause
          ?? _fetchedDetail?.rescuerHRLastPause
          ?? widget._summary?.rescuerHRLastPause;

  double? get _rescuerSpO2 =>
      widget._detail?.rescuerSpO2LastPause ?? _fetchedDetail?.rescuerSpO2LastPause ?? widget._summary?.rescuerSpO2LastPause;

  bool get _hasBiometrics => _rescuerHR != null || _rescuerSpO2 != null;

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
    final summary = widget._summary ??
        (widget._detail != null ? SessionSummary.fromDetail(widget._detail!) : null);
    if (summary == null) return;
    await ExportBottomSheet.showForSingleSession(context,
        summary: summary, detail: widget._detail ?? _fetchedDetail);
  }

  Future<void> _confirmDeleteSession() async {
    final sessionId = widget._detail?.id ?? widget._summary?.id;
    if (sessionId == null) return;
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

  Future<void> _editNote() async {
    final result = await AppDialogs.showNoteEditor(context, initialNote: _note);
    if (result == null) return;
    final sessionId = widget._detail?.id ?? widget._summary?.id;
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
      final updatedDetail = widget._detail?.withNote(newNote);
      if (updatedDetail != null) await SessionLocalStorage.saveLocal(updatedDetail);
      ref.invalidate(sessionSummariesProvider);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final canEditNote = (widget._detail?.id ?? widget._summary?.id) != null
        || _effectiveDetail != null;

    // AppBar title
    String title;
    if (widget._sessionNumber != null) {
      title = 'Session ${widget._sessionNumber}';
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
      bottom: _isFetchingDetail
          ? const PreferredSize(
        preferredSize: Size.fromHeight(2),
        child: LinearProgressIndicator(minHeight: 2),
      )
          : null,
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
        if (widget._detail != null || widget._summary != null)
          IconButton(
            icon: const Icon(Icons.download_outlined, color: AppColors.primary),
            tooltip: 'Export',
            onPressed: _exportSession,
          ),
        if ((widget._detail?.id ?? widget._summary?.id) != null)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.textSecondary),
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
    final hasGraphs = _effectiveDetail != null &&
        _effectiveDetail!.compressions.isNotEmpty;

    return _CollapsingTrainingLayout(
      grade:             _grade,
      isPediatric:       _isPediatric,
      isNoFeedback:      _isNoFeedback,
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
      ),
      personalBest: _PersonalBestComparison(
        currentGrade: _grade,
        scenario:     _scenario,
        sessionStart: _effectiveDetail?.sessionStart ?? widget._summary?.sessionStart,
      ),
      isPersonalBest: _isPersonalBest,
      tabController: _tabController,
      tabs: [
        _TrainingOverviewTab(
          detail:       _effectiveDetail,
          summary:      widget._summary,
          note:         _note,
          canEditNote:  canEditNote,
          onEditNote:   _editNote,
          scenario:     _scenario,
          currentGrade: _grade,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
        _TrainingMetricsTab(
          detail:           _effectiveDetail,
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
          detail:         _effectiveDetail,
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
    final lastPulseCheck = _effectiveDetail?.pulseChecks.lastOrNull;

    return _CollapsingTrainingLayout(
      isEmergency:       true,
      pulseDetected: (_effectiveDetail?.pulseChecksPrompted ?? 0) > 0
          ? _effectiveDetail?.pulseDetectedFinal
          : null,
      pulseDetectedBpm:  lastPulseCheck?.detectedBpm,
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
      handsOnPct:           _effectiveDetail?.handsOnPct ?? '—',
      pulseCheckSamples:    _effectiveDetail?.pulseChecks.lastOrNull?.ppgSamples,
      pulseCheckInterval:   _effectiveDetail?.pulseChecks.lastOrNull?.intervalNumber,
      pulseCheckConfidence: _effectiveDetail?.pulseChecks.lastOrNull?.confidence,
      tabs: [
        _EmergencySummaryTab(
          detail:         _effectiveDetail,
          summary:        widget._summary,
          note:           _note,
          canEditNote:    canEditNote,
          onEditNote:     _editNote,
          onExport:       _exportSession,
          isPediatric:    _isPediatric,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
        _EmergencyPatientTab(
          detail:      _effectiveDetail,
          summary:     widget._summary,
          isPediatric: _isPediatric,
          rescuerHR:   _rescuerHR,
          rescuerSpO2: _rescuerSpO2,
        ),
        _EmergencyTimelineTab(
          detail:        _effectiveDetail,
          targetDepthMin: _targetDepthMin,
          targetDepthMax: _targetDepthMax,
        ),
      ],
    );
  }
}
