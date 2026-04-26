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
import 'export_bottom_sheet.dart';
import 'session_history.dart';

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

  // ── Mode / scenario helpers ─────────────────────────────────────────────────
  bool get _isEmergency =>
      (widget._detail?.isEmergency ?? widget._summary?.isEmergency) ?? true;

  String get _scenario =>
      widget._detail?.scenario ?? widget._summary?.scenario ?? 'standard_adult';

  bool get _isPediatric => _scenario == 'pediatric';

  bool get _isNoFeedback =>
      widget._detail?.isNoFeedback ?? widget._summary?.isNoFeedback ?? false;

  double get _targetDepthMin =>
      _isPediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;

  double get _targetDepthMax =>
      _isPediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;

  String get _targetDepthLabel =>
      '${_targetDepthMin.toStringAsFixed(0)}–${_targetDepthMax.toStringAsFixed(0)} cm';

  // ── Data helpers ────────────────────────────────────────────────────────────
  double get _grade =>
      widget._detail?.totalGrade ?? widget._summary?.totalGrade ?? 0;

  int get _compressionCount =>
      widget._detail?.compressionCount ?? widget._summary?.compressionCount ?? 0;

  String get _durationFormatted =>
      widget._detail?.durationFormatted ?? widget._summary?.durationFormatted ?? '—';

  double get _averageFrequency =>
      widget._detail?.averageFrequency ?? widget._summary?.averageFrequency ?? 0;

  double get _averageDepth =>
      widget._detail?.averageDepth ?? widget._summary?.averageDepth ?? 0;

  String get _dateTimeFormatted =>
      widget._detail?.dateTimeFormatted ?? widget._summary?.dateTimeFormatted ?? '—';

  int get _correctDepth =>
      widget._detail?.correctDepth ?? widget._summary?.correctDepth ?? 0;

  int get _correctFrequency =>
      widget._detail?.correctFrequency ?? widget._summary?.correctFrequency ?? 0;

  int get _correctRecoil =>
      widget._detail?.correctRecoil ?? widget._summary?.correctRecoil ?? 0;

  double get _depthPct =>
      _compressionCount > 0 ? (_correctDepth / _compressionCount * 100) : 0;

  double get _ratePct =>
      _compressionCount > 0 ? (_correctFrequency / _compressionCount * 100) : 0;

  double get _recoilPct =>
      _compressionCount > 0 ? (_correctRecoil / _compressionCount * 100) : 0;

  double get _avgWristAngle {
    final c = widget._detail?.compressions;
    if (c == null || c.isEmpty) return 0.0;
    return c.map((e) => e.wristAlignmentAngle).reduce((a, b) => a + b) / c.length;
  }

  double? get _rescuerHR =>
      widget._detail?.rescuerHRLastPause ?? widget._summary?.rescuerHRLastPause;

  double? get _rescuerSpO2 =>
      widget._detail?.rescuerSpO2LastPause ?? widget._summary?.rescuerSpO2LastPause;

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
        summary: summary, detail: widget._detail);
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
        || widget._detail != null;

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
    final hasGraphs = widget._detail != null &&
        widget._detail!.compressions.isNotEmpty;

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
        sessionStart: widget._detail?.sessionStart ?? widget._summary?.sessionStart,
      ),
      isPersonalBest: _isPersonalBest,
      tabController: _tabController,
      tabs: [
        _TrainingOverviewTab(
          detail:       widget._detail,
          summary:      widget._summary,
          note:         _note,
          canEditNote:  canEditNote,
          onEditNote:   _editNote,
          scenario:     _scenario,
          currentGrade: _grade,
        ),
        _TrainingMetricsTab(
          detail:           widget._detail,
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
          detail:         widget._detail,
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
    final lastPulseCheck = widget._detail?.pulseChecks.lastOrNull;

    return _CollapsingTrainingLayout(
      isEmergency:       true,
      pulseDetected:     widget._detail?.pulseDetectedFinal,
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
      tabs: [
        _EmergencySummaryTab(
          detail:         widget._detail,
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
          detail:      widget._detail,
          summary:     widget._summary,
          isPediatric: _isPediatric,
          rescuerHR:   _rescuerHR,
          rescuerSpO2: _rescuerSpO2,
        ),
        _EmergencyTimelineTab(
          detail: widget._detail,
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _CollapsingTrainingLayout
//
// White background fills the whole body. On top of it a white grade card that
// collapses as the user scrolls down:
//   • Expanded  → full card: big ring, motivational, sub-rings, PB banner
//   • Collapsed → slim 48px sticky bar: grade% + depth/rate/recoil pills
//
// The tab bar sits between the card and the tab content.
// ═════════════════════════════════════════════════════════════════════════════

class _CollapsingTrainingLayout extends StatefulWidget {
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
  final double       avgDepth;
  final String       targetDepthLabel;
  final VoidCallback onGradeInfo;
  final TabController tabController;
  final List<Widget> tabs;
  final Widget personalBest;
  final bool isPersonalBest;
  final bool isEmergency;
  final bool? pulseDetected;
  final double? pulseDetectedBpm;
  final bool? pulseUncertain;

  const _CollapsingTrainingLayout({
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
    required this.avgDepth,
    required this.targetDepthLabel,
    required this.onGradeInfo,
    required this.tabController,
    required this.tabs,
    required this.personalBest,
    required this.isPersonalBest,
    this.isEmergency = false,
    this.pulseDetected,
    this.pulseDetectedBpm,
    this.pulseUncertain,
  });

  @override
  State<_CollapsingTrainingLayout> createState() =>
      _CollapsingTrainingLayoutState();
}

class _CollapsingTrainingLayoutState
    extends State<_CollapsingTrainingLayout> {

  static const double _cardMax = 460.0;
  static const double _cardMin = 180.0;
  static const double _pbMax   = 68.0;

  double _collapseProgress = 0.0;

  Color get _gradeColor {
    final g = widget.grade;
    if (g >= 90) return AppColors.feedbackGood;
    if (g >= 75) return AppColors.feedbackInfo;
    if (g >= 55) return AppColors.feedbackWarn;
    return AppColors.feedbackBad;
  }

  static Color _ringColor(double pct) {
    if (pct >= 80) return AppColors.feedbackGood;
    if (pct >= 60) return AppColors.feedbackWarn;
    return AppColors.feedbackBad;
  }

  @override
  Widget build(BuildContext context) {
    final p     = _collapseProgress;
    final double noFeedbackOffset = widget.isNoFeedback ? 32.0 : 0.0;
    final double effectiveCardMin = _cardMin + noFeedbackOffset;
    final double effectiveCardMax = _cardMax + noFeedbackOffset;
    final double cardH = (effectiveCardMax - p * (effectiveCardMax - effectiveCardMin)).clamp(effectiveCardMin, effectiveCardMax);
    final double innerH = cardH - noFeedbackOffset;
    final pbH   = widget.isPersonalBest
        ? ((1.0 - p * 2.0).clamp(0.0, 1.0)) * _pbMax
        : 0.0;

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Column(
        children: [
          // ── Grade card + PB banner — drag here collapses the card ─────
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (d) {
              final maxScroll = (_cardMax - _cardMin) + _pbMax;
              final raw = _collapseProgress - d.delta.dy / maxScroll;
              final clamped = raw.clamp(0.0, 1.0);
              if ((clamped - _collapseProgress).abs() > 0.001) {
                setState(() => _collapseProgress = clamped);
              }
            },
            child: Column(
              children: [
                SizedBox(
                  height: cardH,
                  child: widget.isEmergency
                      ? _buildOutcomeCard(p)
                      : _buildGradeCard(p, innerH),
                ),
                if (!widget.isEmergency)
                  ClipRect(
                    child: SizedBox(
                      height: pbH,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md, AppSpacing.xxs,
                            AppSpacing.md, AppSpacing.sm),
                        child: widget.personalBest,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Tab bar — always static, never moves ──────────────────────
          _TabBarWidget(
            tabController: widget.tabController,
            isEmergency: widget.isEmergency,
          ),

          // ── Tab content — fully independent scroll ────────────────────
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md,
                  MediaQuery.paddingOf(context).bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(AppSpacing.cardRadius),
                  ),
                  boxShadow: AppDecorations.card().boxShadow,
                ),
                child: TabBarView(
                  controller: widget.tabController,
                  children: widget.tabs.map((tab) =>
                      SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom),
                        child: tab,
                      ),
                  ).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeCard(double progress, double availableH) {
    final double cardTop      = widget.isNoFeedback ? 32.0 : 0.0;
    final double ringSize     = lerpDouble(180, 90,  progress)!;
    final double fontSize     = lerpDouble(48,  24,  progress)!;
    final double strokeW      = lerpDouble(12,   7,  progress)!;
    final double helpH        = lerpDouble(32,   0,  progress)!;
    final double helpOpacity  = (1.0 - progress * 4.0).clamp(0.0, 1.0);
    final double labelFont    = lerpDouble(15,  11,  progress)!;
    final double labelGap     = lerpDouble(AppSpacing.md, AppSpacing.md, progress)!;
    final double ringsOpacity = (1.0 - progress * 1.6).clamp(0.0, 1.0);
    final double ringsH       = lerpDouble(130,  0,  progress)!;

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Stack(
        children: [
          if (widget.isNoFeedback)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Padding(
                padding: const EdgeInsets.only(
                    top: AppSpacing.sm, bottom: AppSpacing.xs),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                    decoration: AppDecorations.chip(
                      color: AppColors.primary,
                      bg:    AppColors.primaryLight,
                    ),
                    child: Text('No-Feedback Mode',
                        style: AppTypography.badge(
                            size: 9, color: AppColors.primary)),
                  ),
                ),
              ),
            ),
          Positioned(
            top:    cardTop,
            left:   AppSpacing.md,
            right:  AppSpacing.md,
            bottom: AppSpacing.md,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cprCardBg,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.lg,
                      AppSpacing.lg, AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: helpH,
                        child: Opacity(
                          opacity: helpOpacity,
                          child: Align(
                            alignment: Alignment.topRight,
                            child: GestureDetector(
                              onTap: widget.onGradeInfo,
                              child: Container(
                                width: 28, height: 28,
                                decoration: AppDecorations.iconCircle(
                                    bg: AppColors.textOnDark
                                        .withValues(alpha: 0.15)),
                                child: const Icon(
                                    Icons.help_outline_rounded,
                                    size: 15,
                                    color: AppColors.textOnDark),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: ringSize, height: ringSize,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                value:           widget.grade / 100,
                                strokeWidth:     strokeW,
                                strokeCap:       StrokeCap.round,
                                backgroundColor: AppColors.textOnDark
                                    .withValues(alpha: 0.15),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    _gradeColor),
                              ),
                            ),
                            Text(
                              '${widget.grade.toStringAsFixed(0)}%',
                              style: AppTypography.numericDisplay(
                                  size: fontSize,
                                  color: AppColors.textOnDark),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: labelGap),
                      Text(
                        widget.motivational,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.subheading(
                            size: labelFont,
                            color: AppColors.textOnDark.withValues(alpha: 0.85)),
                      ),
                      SizedBox(height: lerpDouble(AppSpacing.md, 0, progress)!),                      SizedBox(
                        height: ringsH,
                        child: Opacity(
                          opacity: ringsOpacity,
                          child: ClipRect(
                            child: OverflowBox(
                              maxHeight: 130,
                              alignment: Alignment.topCenter,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(height: lerpDouble(AppSpacing.lg, 0, progress)!),
                                  Row(
                                    children: [
                                      Expanded(child: Center(child: _SubRing(
                                          label: 'DEPTH',
                                          value: widget.depthPct,
                                          color: _ringColor(widget.depthPct)))),
                                      Expanded(child: Center(child: _SubRing(
                                          label: 'RATE',
                                          value: widget.ratePct,
                                          color: _ringColor(widget.ratePct)))),
                                      Expanded(child: Center(child: _SubRing(
                                          label: 'RECOIL',
                                          value: widget.recoilPct,
                                          color: _ringColor(widget.recoilPct)))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeCard(double progress) {
    final bool?   detected   = widget.pulseDetected;
    final double? bpm        = widget.pulseDetectedBpm;
    final bool    uncertain  = widget.pulseUncertain ?? false;
    final bool    noCheck    = detected == null;

    final Color ringColor = noCheck    ? AppColors.textDisabled
        : uncertain                    ? AppColors.feedbackWarn
        : detected                     ? AppColors.feedbackGood
        :                                AppColors.feedbackBad;

    final IconData outcomeIcon = noCheck    ? Icons.help_outline_rounded
        : uncertain                         ? Icons.help_outline_rounded
        : detected                         ? Icons.favorite_rounded
        :                                     Icons.heart_broken_rounded;

    final String outcomeLabel = noCheck   ? 'No pulse check performed'
        : uncertain                       ? 'Uncertain'
        : detected                       ? 'Pulse Detected'
        :                                   'No Pulse Detected';

    final double ringSize    = lerpDouble(160, 80,  progress)!;
    final double iconSize    = lerpDouble(48,  22,  progress)!;
    final double strokeW     = lerpDouble(12,   7,  progress)!;
    final double labelFont   = lerpDouble(15,  11,  progress)!;
    final double labelGap    = lerpDouble(AppSpacing.md, AppSpacing.sm, progress)!;
    final double ringsOpacity = (1.0 - progress * 1.6).clamp(0.0, 1.0);
    final double ringsH      = lerpDouble(130, 0,   progress)!;
    final double bpmFont     = lerpDouble(20,  0,   progress)!;

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md,
              AppSpacing.md, AppSpacing.md),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cprCardBg,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.lg,
                    AppSpacing.lg, AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: ringSize, height: ringSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              value: 1.0,
                              strokeWidth: strokeW,
                              strokeCap: StrokeCap.round,
                              backgroundColor: AppColors.textOnDark
                                  .withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(outcomeIcon,
                                  color: AppColors.textOnDark,
                                  size: iconSize),
                              if (bpm != null && bpm > 0 && bpmFont > 4)
                                Text(
                                  '${bpm.round()} bpm',
                                  style: AppTypography.numericDisplay(
                                      size: bpmFont.clamp(10, 20),
                                      color: AppColors.textOnDark),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: labelGap),
                    Text(
                      outcomeLabel,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.subheading(
                          size: labelFont,
                          color: AppColors.textOnDark.withValues(alpha: 0.85)),
                    ),
                    SizedBox(height: lerpDouble(AppSpacing.xs, 0, progress)!),
                    SizedBox(
                      height: ringsH,
                      child: Opacity(
                        opacity: ringsOpacity,
                        child: ClipRect(
                          child: OverflowBox(
                            maxHeight: 130,
                            alignment: Alignment.topCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: lerpDouble(AppSpacing.lg, 0, progress)!),
                                Row(
                                  children: [
                                    Expanded(child: Center(child: _SubRing(
                                        label: 'DEPTH',
                                        value: widget.depthPct,
                                        color: _ringColor(widget.depthPct)))),
                                    Expanded(child: Center(child: _SubRing(
                                        label: 'RATE',
                                        value: widget.ratePct,
                                        color: _ringColor(widget.ratePct)))),
                                    Expanded(child: Center(child: _SubRing(
                                        label: 'RECOIL',
                                        value: widget.recoilPct,
                                        color: _ringColor(widget.recoilPct)))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ),
    );
  }
}

// ── Tab bar widget — rendered at top of NestedScrollView body ──────────────
class _TabBarWidget extends StatelessWidget {
  final TabController tabController;
  final bool isEmergency;
  const _TabBarWidget({
    required this.tabController,
    this.isEmergency = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cardRadius),
          ),
          boxShadow: AppDecorations.card().boxShadow,
        ),
        child: TabBar(
          controller: tabController,
          labelColor:           AppColors.primary,
          unselectedLabelColor: AppColors.textDisabled,
          indicatorColor:       AppColors.primary,
          indicatorWeight:      2.5,
          dividerColor:         AppColors.divider,
          labelStyle:           AppTypography.badge(size: 11, color: AppColors.primary),
          unselectedLabelStyle: AppTypography.badge(size: 11, color: AppColors.textDisabled),
          tabs: [
            Tab(text: isEmergency ? 'SUMMARY'  : 'OVERVIEW'),
            Tab(text: isEmergency ? 'PATIENT'  : 'METRICS'),
            Tab(text: isEmergency ? 'TIMELINE' : 'CHARTS'),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _SubRing — metric ring used in the expanded grade card
// ═════════════════════════════════════════════════════════════════════════════

class _SubRing extends StatelessWidget {
  final String label;
  final double value; // 0–100
  final Color  color;

  const _SubRing({
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
      width: 75, height: 75,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value:           value / 100,
              strokeWidth:     9,
              strokeCap:       StrokeCap.round,
              backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
              valueColor:      AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '${value.round()}%',
            style: AppTypography.poppins(
                size: 18, weight: FontWeight.w700,
                color: AppColors.textOnDark),
          ),
        ],
      ),
    ),
        const SizedBox(height: AppSpacing.sm),
        Text(label,
            style: AppTypography.badge(
                size: 9, color: AppColors.textOnDark.withValues(alpha: 0.7))),
      ],
    );
  }
}
// ═════════════════════════════════════════════════════════════════════════════
// _GradeInfoSheet — rich grade explanation dialog
// ═════════════════════════════════════════════════════════════════════════════

class _GradeInfoSheet {
  static void show(
      BuildContext context, {
        required bool   isPediatric,
        required double grade,
        required double depthPct,
        required double ratePct,
        required double recoilPct,
        required int    correctDepth,
        required int    correctFrequency,
        required int    correctRecoil,
        required int    compressionCount,
      }) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder:      (_) => _GradeInfoDialog(
        isPediatric:      isPediatric,
        grade:            grade,
        depthPct:         depthPct,
        ratePct:          ratePct,
        recoilPct:        recoilPct,
        correctDepth:     correctDepth,
        correctFrequency: correctFrequency,
        correctRecoil:    correctRecoil,
        compressionCount: compressionCount,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GradeInfoDialog
// ─────────────────────────────────────────────────────────────────────────────

class _GradeInfoDialog extends StatelessWidget {
  final bool   isPediatric;
  final double grade;
  final double depthPct;
  final double ratePct;
  final double recoilPct;
  final int    correctDepth;
  final int    correctFrequency;
  final int    correctRecoil;
  final int    compressionCount;

  const _GradeInfoDialog({
    required this.isPediatric,
    required this.grade,
    required this.depthPct,
    required this.ratePct,
    required this.recoilPct,
    required this.correctDepth,
    required this.correctFrequency,
    required this.correctRecoil,
    required this.compressionCount,
  });

  Color get _gradeColor {
    if (grade >= 90) return AppColors.success;
    if (grade >= 75) return AppColors.statTileBg;
    if (grade >= 55) return AppColors.warning;
    return AppColors.error;
  }

  static Color _metricColor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.error;
  }

  List<_GradeWeightRow> get _weights => isPediatric
      ? const [
    _GradeWeightRow('Depth consistency',     '4–5 cm target',          28, true),
    _GradeWeightRow('Rate consistency',       '100–120 BPM',            18, true),
    _GradeWeightRow('Full recoil',            'Complete decompression', 18, true),
    _GradeWeightRow('Ventilation compliance', '30:2 ratio',             12, false),
    _GradeWeightRow('Depth + rate combined',  'Both correct together',   8, false),
    _GradeWeightRow('Posture',                'Wrist alignment < 15°',   8, false),
    _GradeWeightRow('Time to first comp',     'Under 10 seconds',        4, false),
    _GradeWeightRow('Hands-on ratio',         'Minimal pauses',          4, false),
  ]
      : const [
    _GradeWeightRow('Depth consistency',     '5–6 cm target',           25, true),
    _GradeWeightRow('Rate consistency',       '100–120 BPM',             20, true),
    _GradeWeightRow('Full recoil',            'Complete decompression',  20, true),
    _GradeWeightRow('Ventilation compliance', '30:2 ratio',              12, false),
    _GradeWeightRow('Depth + rate combined',  'Both correct together',    8, false),
    _GradeWeightRow('Posture',                'Wrist alignment < 15°',    8, false),
    _GradeWeightRow('Hands-on ratio',         'Minimal pauses',           5, false),
    _GradeWeightRow('Time to first comp',     'Under 10 seconds',         2, false),
  ];

  static Widget _gradeInfoSectionLabel(String text, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 3, height: 12,
          margin: const EdgeInsets.only(right: AppSpacing.xs),
          decoration: BoxDecoration(
            color:        accentColor,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
        ),
        Text(text, style: AppTypography.subheading(size: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical: AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header: title + close ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: _gradeColor.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(Icons.emoji_events_outlined,
                        size: AppSpacing.iconSm, color: _gradeColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Your Grade',
                        style: AppTypography.heading(size: 16)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Main grade ring ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: SizedBox(
                width: 110, height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: CircularProgressIndicator(
                        value: grade / 100,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: _gradeColor.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation(_gradeColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${grade.round()}%',
                            style: AppTypography.numericDisplay(
                                size: 26, color: _gradeColor)),
                        Text(isPediatric ? 'Pediatric' : 'Adult',
                            style: AppTypography.caption(
                                color: AppColors.textDisabled)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Scrollable body ────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Intro
                    Text(
                      'Your score is a weighted average of 8 quality factors '
                          'measured across every compression in the session.',
                      style: AppTypography.body(
                          size: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Formula section label
                    _gradeInfoSectionLabel('Formula', _gradeColor),
                    const SizedBox(height: AppSpacing.xs),

                    // Formula table
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(
                            AppSpacing.cardRadiusMd),
                        border: Border.all(color: AppColors.divider),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                      child: Column(
                        children: [
                          for (int i = 0; i < _weights.length; i++) ...[
                            _buildWeightRow(_weights[i]),
                            if (i < _weights.length - 1)
                              const Divider(
                                  height: 1, color: AppColors.divider),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // Sub-metrics section label + explanation
                    _gradeInfoSectionLabel(
                        'Your 3 biggest factors', _gradeColor),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'These three factors account for ${isPediatric
                          ? 64
                          : 65}% of your grade. '
                          'Each ring shows what percentage of your compressions '
                          'were correct for that metric.',
                      style: AppTypography.body(
                          size: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    // 3 sub-metric tiles
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SubMetricTile(
                      label:       'Depth',
                      pct:         depthPct,
                      color:       _metricColor(depthPct),
                      count:       correctDepth,
                      total:       compressionCount,
                      whatItMeans: isPediatric ? 'reached the 4–5 cm target' : 'hit the 5–6 cm target',
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _SubMetricTile(
                      label:       'Rate',
                      pct:         ratePct,
                      color:       _metricColor(ratePct),
                      count:       correctFrequency,
                      total:       compressionCount,
                      whatItMeans: 'stayed in 100–120 BPM',
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _SubMetricTile(
                      label:       'Recoil',
                      pct:         recoilPct,
                      color:       _metricColor(recoilPct),
                      count:       correctRecoil,
                      total:       compressionCount,
                      whatItMeans: 'had full chest recoil',
                    ),
                  ],
                ),
                  ],
                ),
              ),
            ),

            // ── Got it button ──────────────────────────────────────────────
            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: Text('Got it', style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightRow(_GradeWeightRow w) {
    final color = w.isHighlight ? AppColors.primary : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          if (w.isHighlight)
            Container(
              width: 3, height: 32,
              margin: const EdgeInsets.only(right: AppSpacing.xs),
              decoration: BoxDecoration(
                color:        AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            const SizedBox(width: AppSpacing.xs + 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w.label,
                    style: AppTypography.caption(color: color)),
                const SizedBox(height: 2),
                Text(w.target,
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)
                        .copyWith(fontSize: 10)),
              ],
            ),
          ),
          Text('${w.weight}%',
              style: AppTypography.bodyBold(size: 13, color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GradeWeightRow — immutable data only, no widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GradeWeightRow {
  final String label;
  final String target;
  final int    weight;
  final bool   isHighlight;

  const _GradeWeightRow(this.label, this.target, this.weight, this.isHighlight);
}

// ─────────────────────────────────────────────────────────────────────────────
// _SubMetricTile — mini ring + score + label + target + weight% of grade
// ─────────────────────────────────────────────────────────────────────────────
class _SubMetricTile extends StatelessWidget {
  final String label;
  final double pct;
  final Color  color;
  final int    count;
  final int    total;
  final String whatItMeans;

  const _SubMetricTile({
    required this.label,
    required this.pct,
    required this.color,
    required this.count,
    required this.total,
    required this.whatItMeans,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical:   AppSpacing.sm),
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 52, height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CircularProgressIndicator(
                      value:           pct / 100,
                      strokeWidth:     5,
                      strokeCap:       StrokeCap.round,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor:      AlwaysStoppedAnimation(color),
                    ),
                  ),
                  Text('${pct.round()}%',
                      style: AppTypography.numericDisplay(
                          size: 13, color: color)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(label,
                style: AppTypography.bodyBold(
                    size: 12, color: AppColors.textPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text('$count / $total \n$whatItMeans',
                style: AppTypography.caption(color: AppColors.textDisabled),
                textAlign: TextAlign.center,
                maxLines: 3),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// TAB 1 — Training Overview
// ═════════════════════════════════════════════════════════════════════════════

class _TrainingOverviewTab extends ConsumerWidget {
  final SessionDetail?  detail;
  final SessionSummary? summary;
  final String?         note;
  final bool            canEditNote;
  final VoidCallback    onEditNote;
  final String          scenario;
  final double          currentGrade;

  const _TrainingOverviewTab({
    required this.detail,
    required this.summary,
    required this.note,
    required this.canEditNote,
    required this.onEditNote,
    required this.scenario,
    required this.currentGrade,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = detail;
    final s = summary;

    final compressions    = d?.compressionCount ?? s?.compressionCount ?? 0;
    final duration        = d?.durationFormatted ?? s?.durationFormatted ?? '—';
    final noFlowTime      = d?.noFlowTime ?? 0.0;
    final handsOnPct      = d?.handsOnPct ?? '—';
    final handsOnOk       = (d?.handsOnRatio ?? 0) >= 0.80;
    final noFlowIntervals = d?.noFlowIntervals ?? s?.noFlowIntervals ?? 0;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Hero row: Duration + Compressions ──────────────────────────
          Row(
            children: [
              Expanded(
                child: _HeroStatTile(
                  icon:  Icons.schedule_rounded,
                  label: 'Duration',
                  value: duration,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _HeroStatTile(
                  icon:  Icons.favorite_rounded,
                  label: 'Compressions',
                  value: '$compressions',
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Quality grid: 2×2 ──────────────────────────────────────────
          _OverviewGrid(
            compressions:    compressions,
            noFlowTime:      noFlowTime,
            noFlowIntervals: noFlowIntervals,
            handsOnPct:      handsOnPct,
            handsOnOk:       handsOnOk,
            detail:          d,
            summary:         s,
          ),

          // ── Sync banner — only shows when needed ───────────────────────
          if (d?.syncedToBackend == false) ...[
            const SizedBox(height: AppSpacing.sm),
            _UnsyncedBanner(isLoggedIn: ref.watch(authStateProvider).isLoggedIn),
          ],
          const SizedBox(height: AppSpacing.sm),

          // ── Note card ──────────────────────────────────────────────────
          _NoteCard(note: note, canEdit: canEditNote, onTap: onEditNote),
          const SizedBox(height: AppSpacing.sm),

          // ── Past sessions link ─────────────────────────────────────────
          const _PastSessionsButton(),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OverviewGrid — 3-column stat grid with icons
// ─────────────────────────────────────────────────────────────────────────────

class _OverviewGrid extends StatelessWidget {
  final int     compressions;
  final double  noFlowTime;
  final int     noFlowIntervals;
  final String  handsOnPct;
  final bool    handsOnOk;
  final SessionDetail?  detail;
  final SessionSummary? summary;

  const _OverviewGrid({
    required this.compressions,
    required this.noFlowTime,
    required this.noFlowIntervals,
    required this.handsOnPct,
    required this.handsOnOk,
    required this.detail,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final avgDepth = detail?.averageDepth    ?? summary?.averageDepth    ?? 0.0;
    final avgFreq  = detail?.averageFrequency ?? summary?.averageFrequency ?? 0.0;

    final depthOk    = avgDepth >= 5.0 && avgDepth <= 6.0;
    final depthHigh  = avgDepth > 6.0;
    final rateOk     = avgFreq >= 100 && avgFreq <= 120;
    final handsDouble = double.tryParse(
        handsOnPct.replaceAll('%', '').trim()) ?? 0.0;

    final tiles = [
      _GridStatTile(
        label:       'Avg Depth',
        value:       avgDepth > 0 ? '${avgDepth.toStringAsFixed(1)} cm' : '—',
        dotColor:    depthOk ? AppColors.success
            : depthHigh ? AppColors.error : AppColors.warning,
        zoneBar: avgDepth > 0 ? _ZoneBarConfig(
          minVal: 0, maxVal: 8,
          targetMin: 5.0, targetMax: 6.0,
          currentVal: avgDepth,
          dotColor: depthOk ? AppColors.success
              : depthHigh ? AppColors.error : AppColors.warning,
          targetLabel: '5–6 cm',
        ) : null,
      ),
      _GridStatTile(
        label:    'Avg Rate',
        value:    avgFreq > 0 ? '${avgFreq.round()} bpm' : '—',
        dotColor: rateOk ? AppColors.success
            : (avgFreq >= 90 && avgFreq <= 130) ? AppColors.warning : AppColors.error,
        zoneBar: avgFreq > 0 ? _ZoneBarConfig(
          minVal: 60, maxVal: 160,
          targetMin: 100, targetMax: 120,
          currentVal: avgFreq,
          dotColor: rateOk ? AppColors.success
              : (avgFreq >= 90 && avgFreq <= 130) ? AppColors.warning : AppColors.error,
          targetLabel: '100–120',
        ) : null,
      ),
      _GridStatTile(
        label:    'Hands-On',
        value:    handsOnPct,
        dotColor: handsOnOk ? AppColors.success : AppColors.warning,
        zoneBar: handsOnPct != '—' ? _ZoneBarConfig(
          minVal: 0, maxVal: 100,
          targetMin: 80, targetMax: 100,
          currentVal: handsDouble,
          dotColor: handsOnOk ? AppColors.success : AppColors.warning,
          targetLabel: '≥ 80%',
        ) : null,
      ),
      _GridStatTile(
        label:    'Pause Time',
        value:    noFlowTime > 0 ? '${noFlowTime.toStringAsFixed(1)}s' : '0s',
        note:     '$noFlowIntervals pause(s)',
        dotColor: noFlowTime <= 5 ? AppColors.success
            : AppColors.warning,
        zoneBar: _ZoneBarConfig(
          minVal: 0, maxVal: 15,
          targetMin: 0, targetMax: 5,
          currentVal: noFlowTime.clamp(0.0, 15.0),
          dotColor: noFlowTime <= 5 ? AppColors.success
              : AppColors.warning,
          targetLabel: '< 5s',
        ),
      ),
    ];

    return GridView.count(
      crossAxisCount:   2,
      shrinkWrap:       true,
      physics:          const NeverScrollableScrollPhysics(),
      mainAxisSpacing:  AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.3,
      padding:          EdgeInsets.zero,
      children: tiles,
    );
  }
}

class _HeroStatTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;

  const _HeroStatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cprCardBg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: AppSpacing.iconMd, color: AppColors.textOnDark),
            const SizedBox(height: AppSpacing.xs),
            Text(value,
                style: AppTypography.numericDisplay(
                    size: 26, color: AppColors.textOnDark)),
            const SizedBox(height: AppSpacing.xxs),
            Text(label,
                style: AppTypography.caption(color: AppColors.textOnDark)),
          ],
      ),
    );
  }
}

class _GridStatTile extends StatelessWidget {
  final String         label;
  final String         value;
  final String?        note;
  final Color          dotColor;
  final _ZoneBarConfig? zoneBar;

  const _GridStatTile({
    required this.label,
    required this.value,
    required this.dotColor,
    this.note,
    this.zoneBar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm + AppSpacing.xs),
      decoration: AppDecorations.tintedCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label
            Text(label,
                style: AppTypography.caption(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xxs),
            // Value + inline note on same row
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: AppTypography.numericDisplay(
                        size: 19, color: AppColors.textPrimary)),
                if (note != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Text(note!,
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
                ],
              ],
            ),
            // Zone bar
            if (zoneBar != null) ...[
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 16,
                child: CustomPaint(
                  painter: _ZoneBarPainter(config: zoneBar!),
                  size: const Size(double.infinity, 16),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Center(
                child: Text(zoneBar!.targetLabel,
                    style: AppTypography.badge(
                        size: 9, color: AppColors.textDisabled)),
              ),
            ],
          ],
      ),
    );
  }
}

// ── Zone bar config ────────────────────────────────────────────────────────
class _ZoneBarConfig {
  final double minVal;
  final double maxVal;
  final double targetMin;
  final double targetMax;
  final double currentVal;
  final Color  dotColor;
  final String targetLabel;

  const _ZoneBarConfig({
    required this.minVal,
    required this.maxVal,
    required this.targetMin,
    required this.targetMax,
    required this.currentVal,
    required this.dotColor,
    required this.targetLabel,
  });
}

class _ZoneBarPainter extends CustomPainter {
  final _ZoneBarConfig config;
  const _ZoneBarPainter({required this.config});

  double _norm(double v) =>
      ((v - config.minVal) / (config.maxVal - config.minVal)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height / 2;
    final trackH = 4.0;
    final dotR   = 5.0;
    final range  = size.width;
    final usable = range - dotR * 2;

    final norm = _norm(config.currentVal);
    final dotX = dotR + norm * usable;

    final zoneLeft  = dotR + _norm(config.targetMin) * usable;
    final effectiveRight = config.targetMax >= config.maxVal
        ? range - dotR
        : dotR + _norm(config.targetMax) * usable;

    // ── Track background (always grey) ──────────────────────────────────
    canvas.drawLine(
      Offset(dotR, trackY),
      Offset(range - dotR, trackY),
      Paint()
        ..color = AppColors.divider
        ..strokeCap = StrokeCap.round
        ..strokeWidth = trackH,
    );

    // ── Target zone highlight ────────────────────────────────────────────
    canvas.drawLine(
      Offset(zoneLeft, trackY),
      Offset(effectiveRight, trackY),
      Paint()
        ..color = AppColors.success.withValues(alpha: 0.22)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = trackH,
    );

    // ── Out-of-zone segment (dot to nearest boundary, when outside) ──────
    final inZone = config.currentVal >= config.targetMin &&
        config.currentVal <= config.targetMax;
    if (!inZone) {
      final nearEdge = config.currentVal < config.targetMin
          ? zoneLeft
          : effectiveRight;
      canvas.drawLine(
        Offset(dotX, trackY),
        Offset(nearEdge, trackY),
        Paint()
          ..color = config.dotColor.withValues(alpha: 0.35)
          ..strokeCap = StrokeCap.butt
          ..strokeWidth = trackH,
      );
    }

    // ── Target boundary ticks ────────────────────────────────────────────
    final tickPaint = Paint()
      ..color = AppColors.success.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    for (final x in [
      zoneLeft,
      if (config.targetMax < config.maxVal) dotR + _norm(config.targetMax) * usable,
    ]) {
      canvas.drawLine(Offset(x, trackY - 5), Offset(x, trackY + 5), tickPaint);
    }

    // ── Current value dot ────────────────────────────────────────────────
    canvas.drawCircle(Offset(dotX, trackY), dotR,
        Paint()..color = config.dotColor);
    canvas.drawCircle(Offset(dotX, trackY), 2.0,
        Paint()..color = AppColors.white);
  }

  @override
  bool shouldRepaint(_ZoneBarPainter old) =>
      old.config.currentVal != config.currentVal ||
          old.config.dotColor != config.dotColor ||
          old.config.minVal != config.minVal ||
          old.config.maxVal != config.maxVal;
}
// ═════════════════════════════════════════════════════════════════════════════
// TAB 2 — Training Metrics
// ═════════════════════════════════════════════════════════════════════════════

class _TrainingMetricsTab extends StatelessWidget {
  final SessionDetail? detail;
  final int            compressionCount;
  final String         targetDepthLabel;
  final double         targetDepthMin;
  final double         targetDepthMax;
  final double         averageDepth;
  final double         avgWristAngle;
  final String Function(int) pctFn;
  final double?        rescuerHR;
  final double?        rescuerSpO2;
  final bool           hasBiometrics;

  const _TrainingMetricsTab({
    required this.detail,
    required this.compressionCount,
    required this.targetDepthLabel,
    required this.targetDepthMin,
    required this.targetDepthMax,
    required this.averageDepth,
    required this.avgWristAngle,
    required this.pctFn,
    required this.rescuerHR,
    required this.rescuerSpO2,
    required this.hasBiometrics,
  });

  @override
  Widget build(BuildContext context) {
    final d = detail;
    if (d == null) {
      return _SummaryOnlyMetrics(
        compressionCount: compressionCount,
        averageDepth:     averageDepth,
      );
    }

    final hasBody = hasBiometrics
        || d.ambientTempStart != null
        || d.rescuerVitals.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Card 1: Compression Quality ────────────────────────────────
          _MetricsSectionCard(
            icon:      Icons.favorite_rounded,
            iconColor: AppColors.primary,
            title:     'Compression Quality',
            subtitle:  '${d.compressionCount} compressions · ${d.durationFormatted}',
            child: _CompressionQualityCard(
              detail:           d,
              compressionCount: compressionCount,
              targetDepthMin:   targetDepthMin,
              targetDepthMax:   targetDepthMax,
              targetDepthLabel: targetDepthLabel,
              avgWristAngle:    avgWristAngle,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Card 2: Session Timeline ────────────────────────────────────
          _MetricsSectionCard(
            icon:      Icons.timeline_rounded,
            iconColor: AppColors.primaryAlt,
            title:     'Session Timeline',
            subtitle:  '',
            startOpen: false,
            child:     _SessionTimelineSection(detail: d),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Card 3: Rescuer Vitals (conditional) ───────────────────────
          if (hasBody) ...[
            _MetricsSectionCard(
              icon:      Icons.monitor_heart_outlined,
              iconColor: AppColors.primary,
              title:     'Rescuer Vitals',
              subtitle:  'Wrist HR · SpO₂ · temperature · fatigue',
              startOpen: false,
              child:     _RescuerVitalsSection(
                rescuerHR:   rescuerHR,
                rescuerSpO2: rescuerSpO2,
                detail:      d,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}
class _MetricsSectionCard extends StatefulWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final Widget   child;
  final bool     startOpen;

  const _MetricsSectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
    this.startOpen = true,
  });

  @override
  State<_MetricsSectionCard> createState() => _MetricsSectionCardState();
}

class _MetricsSectionCardState extends State<_MetricsSectionCard> {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                      bg:     widget.iconColor.withValues(alpha: 0.10),
                      radius: AppSpacing.cardRadiusSm,
                    ),
                    child: Icon(widget.icon,
                        color: widget.iconColor, size: AppSpacing.iconSm),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: AppTypography.subheading(size: 14)),
                        if (widget.subtitle.isNotEmpty)
                          Text(widget.subtitle,
                              style: AppTypography.caption()),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconSm),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              children: [
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: widget.child,
                ),
              ],
            ),
            crossFadeState:
            _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _CompressionQualityCard
// ─────────────────────────────────────────────────────────────────────────────

class _CompressionQualityCard extends StatelessWidget {
  final SessionDetail detail;
  final int           compressionCount;
  final double        targetDepthMin;
  final double        targetDepthMax;
  final String        targetDepthLabel;
  final double        avgWristAngle;

  const _CompressionQualityCard({
    required this.detail,
    required this.compressionCount,
    required this.targetDepthMin,
    required this.targetDepthMax,
    required this.targetDepthLabel,
    required this.avgWristAngle,
  });

  double _pct(int correct) {
    final total = detail.compressionCount > 0
        ? detail.compressionCount : compressionCount;
    return total > 0 ? correct / total * 100 : 0.0;
  }

  static Color _scoreColor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final depthPct   = _pct(detail.correctDepth);
    final ratePct    = _pct(detail.correctFrequency);
    final recoilPct  = _pct(detail.correctRecoil);
    final posturePct = _pct(detail.correctPosture);

    // Derive min/max instantaneous rate from per-compression data
    double? rateMin;
    double? rateMax;
    if (detail.compressions.isNotEmpty) {
      for (final c in detail.compressions) {
        final r = c.instantaneousRate > 0 ? c.instantaneousRate : c.frequency;
        if (r > 0) {
          rateMin = rateMin == null ? r : (r < rateMin ? r : rateMin);
          rateMax = rateMax == null ? r : (r > rateMax ? r : rateMax);
        }
      }
    }

    final total = detail.compressionCount > 0
        ? detail.compressionCount : compressionCount;
    final comboPct = total > 0
        ? detail.depthRateCombo / total * 100 : 0.0;

    return Column(
      children: [
        // ── Row 1: Depth | Rate ─────────────────────────────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _CategoryTile(
                label: 'Depth',
                score: depthPct,
                rows: [
                  _TileRow('Avg',
                      detail.averageDepth > 0
                          ? '${detail.averageDepth.toStringAsFixed(1)} cm' : '—',
                      color: detail.averageDepth > 0
                          ? (detail.averageDepth >= targetDepthMin &&
                          detail.averageDepth <= targetDepthMax
                          ? AppColors.success : AppColors.warning)
                          : null),
                  if (detail.peakDepth > 0)
                    _TileRow('Peak',
                        '${detail.peakDepth.toStringAsFixed(1)} cm'),
                  if (detail.tooDeepCount > 0)
                    _TileRow('Too deep', '${detail.tooDeepCount}×',
                        color: AppColors.error),
                ],
                onTap: () => _MetricDetailSheet.show(context,
                  label: 'Depth',
                  icon: Icons.compress_rounded,
                  score: depthPct,
                  accentColor: _scoreColor(depthPct),
                  sections: [
                    _DetailSection('Your numbers', rows: [
                      _DetailRow2('Average depth',
                          detail.averageDepth > 0
                              ? '${detail.averageDepth.toStringAsFixed(1)} cm' : '—',
                          sub: 'Target: $targetDepthLabel',
                          color: detail.averageDepth >= targetDepthMin &&
                              detail.averageDepth <= targetDepthMax
                              ? AppColors.success : AppColors.warning),
                      _DetailRow2('Correct compressions',
                          '${detail.correctDepth} / $total',
                          sub: '${depthPct.round()}% in target range'),
                      if (detail.peakDepth > 0)
                        _DetailRow2('Peak depth',
                            '${detail.peakDepth.toStringAsFixed(1)} cm',
                            sub: 'Deepest single compression'),
                      if (detail.tooDeepCount > 0)
                        _DetailRow2('Too deep', '${detail.tooDeepCount}×',
                            sub: 'Exceeded ${targetDepthMax.toStringAsFixed(0)} cm. Risk of rib injury',
                            color: AppColors.error),
                      if (detail.depthSD > 0)
                        _DetailRow2('Std deviation',
                            '${detail.depthSD.toStringAsFixed(2)} cm',
                            sub: 'Lower = more consistent depth'),
                      if (detail.depthConsistency > 0)
                        _DetailRow2('Consistency score',
                            '${detail.depthConsistency.round()}%',
                            sub: 'How uniform your depth was throughout'),
                    ]),
                    _DetailSection('What this means',
                        body: 'Depth is the most critical factor in CPR. '
                            'Compressions must reach $targetDepthLabel to generate enough '
                            'cardiac output to perfuse the brain and vital organs. '
                            'Too shallow compressions reduce cardiac output, while too deep risk rib fractures.'),
                    _DetailSection('How to improve', bullets: [
                      if (detail.averageDepth > 0 && detail.averageDepth < targetDepthMin)
                        'Your average depth was ${detail.averageDepth.toStringAsFixed(1)} cm, below the ${targetDepthMin.toStringAsFixed(0)} cm target. Push further down by locking your elbows and leaning in with body weight.'
                      else if (detail.averageDepth > targetDepthMax)
                        'Your average depth was ${detail.averageDepth.toStringAsFixed(1)} cm, above ${targetDepthMax.toStringAsFixed(0)} cm. Ease up slightly on the downstroke to stay in range.'
                      else
                        'Your average depth was on target. Focus on keeping it consistent throughout the session.',
                      if (detail.tooDeepCount > 0)
                        '${detail.tooDeepCount} compression(s) exceeded ${targetDepthMax.toStringAsFixed(0)} cm. Rib fracture risk increases above this threshold.',
                      if (detail.depthSD > 0.5)
                        'Your depth varied significantly (SD ${detail.depthSD.toStringAsFixed(2)} cm). Aim for the same controlled push every time.',
                      'Straight, locked elbows transfer force more efficiently than bent arms.',
                    ]),
                  ],
                ),
              )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _CategoryTile(
                label: 'Rate',
                score: ratePct,
                rows: [
                  _TileRow('Avg',
                      detail.averageFrequency > 0
                          ? '${detail.averageFrequency.round()} bpm' : '—',
                      color: detail.averageFrequency > 0
                          ? (detail.averageFrequency >= CprTargets.rateMin &&
                          detail.averageFrequency <= CprTargets.rateMax
                          ? AppColors.success : AppColors.warning)
                          : null),
                  if (rateMin != null)
                    _TileRow('Min', '${rateMin.round()} bpm',
                        color: rateMin < CprTargets.rateMin
                            ? AppColors.warning : null),
                  if (rateMax != null)
                    _TileRow('Max', '${rateMax.round()} bpm',
                        color: rateMax > CprTargets.rateMax
                            ? AppColors.warning : null),
                ],
                onTap: () => _MetricDetailSheet.show(context,
                  label: 'Rate',
                  icon: Icons.speed_rounded,
                  score: ratePct,
                  accentColor: _scoreColor(ratePct),
                  sections: [
                    _DetailSection('Your numbers', rows: [
                      _DetailRow2('Average rate',
                          detail.averageFrequency > 0
                              ? '${detail.averageFrequency.round()} bpm' : '—',
                          sub: 'Target: 100–120 bpm',
                          color: detail.averageFrequency >= CprTargets.rateMin &&
                              detail.averageFrequency <= CprTargets.rateMax
                              ? AppColors.success : AppColors.warning),
                      _DetailRow2('Correct compressions',
                          '${detail.correctFrequency} / $total',
                          sub: '${ratePct.round()}% in target range'),
                      if (rateMin != null)
                        _DetailRow2('Minimum rate', '${rateMin.round()} bpm',
                            sub: 'Slowest instantaneous rate recorded',
                            color: rateMin < CprTargets.rateMin
                                ? AppColors.warning : null),
                      if (rateMax != null)
                        _DetailRow2('Maximum rate', '${rateMax.round()} bpm',
                            sub: 'Fastest instantaneous rate recorded',
                            color: rateMax > CprTargets.rateMax
                                ? AppColors.warning : null),
                      if (detail.frequencyConsistency > 0)
                      _DetailRow2('Rhythm consistency',
                          '${detail.frequencyConsistency.round()}%',
                          sub: 'How steady your rate was throughout'),
                    ]),
                    _DetailSection('What this means',
                        body: 'Rate controls how often the heart is mechanically pumped. '
                            'Too fast (> 120 bpm) reduces cardiac fill time between compressions. '
                            'Too slow (< 100 bpm) reduces overall output. '
                            '100–120 bpm is the AHA 2020 recommendation.'),
                    _DetailSection('How to improve', bullets: [
                      if (detail.averageFrequency > 0 && detail.averageFrequency < CprTargets.rateMin)
                        'Your average rate was ${detail.averageFrequency.round()} bpm, below the 100 bpm minimum. Speed up and use the metronome from the glove.'
                      else if (detail.averageFrequency > CprTargets.rateMax)
                        'Your average rate was ${detail.averageFrequency.round()} bpm, above the 120 bpm maximum. Slow down slightly. Rushing reduces cardiac fill time between compressions.'
                      else
                        'Your average rate was on target. Focus on keeping it steady throughout.',
                      if (rateMin != null && rateMin < 80)
                        'Some compressions dropped to ${rateMin.round()} bpm. Avoid pausing or slowing mid-sequence.',
                      if (rateMax != null && rateMax > 140)
                        'Some compressions spiked to ${rateMax.round()} bpm. Avoid rushing bursts between slower compressions.',
                      'Count compressions out loud or use the glove metronome to hold a steady rhythm.',
                    ]),
                  ],
                ),
              )),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // ── Depth + Rate combined banner ────────────────────────────────
        if (detail.depthRateCombo > 0 && total > 0)
          _DepthRateBanner(
            combo: detail.depthRateCombo,
            total: total,
            onTap: () => _MetricDetailSheet.show(context,
              label: 'Depth + Rate',
              icon: Icons.join_inner_rounded,
              score: comboPct,
              accentColor: _scoreColor(comboPct),
              sections: [
                _DetailSection('Your numbers', rows: [
                  _DetailRow2('Both correct simultaneously',
                      '${detail.depthRateCombo} / $total',
                      sub: '${comboPct.round()}% of all compressions'),
                ]),
                _DetailSection('What this means',
                    body: 'This counts compressions where both depth AND rate were '
                        'correct at the same time.'
                        'You can score well on each individually while still missing '
                        'this target if they don\'t align on the same compressions.'),
                _DetailSection('How to improve', bullets: [
                  if (total > 0 && comboPct < 50)
                    'Only ${comboPct.round()}% had both correct at once. Lock in rate first using the metronome, then add depth.'
                  else if (comboPct < 80)
                    'You are close at ${comboPct.round()}%. Small drifts in rate or depth are breaking the combined score.'
                  else
                    'Strong combined score. The main risk is fatigue causing one to drift while you focus on the other.',
                  'Rate and depth are independent. Adjust one at a time.',
                  'Use the metronome so rhythm becomes automatic, freeing mental focus for maintaining depth.',
                ]),
              ],
            ),
          ),

        if (detail.depthRateCombo > 0 && total > 0)
          const SizedBox(height: AppSpacing.sm),

        // ── Row 2: Recoil | Posture ─────────────────────────────────────
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _CategoryTile(
                label: 'Recoil',
                score: recoilPct,
                rows: detail.leaningCount == 0 && detail.overForceCount == 0
                    ? [_TileRow('Perfect recoil ✓', '', color: AppColors.success)]
                    : [
                  _TileRow('Leaning',
                      detail.leaningCount > 0
                          ? '${detail.leaningCount}×' : '0',
                      color: detail.leaningCount > 0
                          ? AppColors.warning : AppColors.textDisabled),
                  _TileRow('Over-force',
                      detail.overForceCount > 0
                          ? '${detail.overForceCount}×' : '0',
                      color: detail.overForceCount > 0
                          ? AppColors.error : AppColors.textDisabled),
                ],
                onTap: () => _MetricDetailSheet.show(context,
                  label: 'Recoil',
                  icon: Icons.sync_rounded,
                  score: recoilPct,
                  accentColor: _scoreColor(recoilPct),
                  sections: [
                    _DetailSection('Your numbers', rows: [
                      _DetailRow2('Full recoil',
                          '${detail.correctRecoil} / $total',
                          sub: '${recoilPct.round()}% with complete chest release'),
                      _DetailRow2('Leaning events',
                          detail.leaningCount > 0
                              ? '${detail.leaningCount}×' : 'None',
                          sub: 'Chest not fully released before next compression',
                          color: detail.leaningCount > 0
                              ? AppColors.warning : AppColors.success),
                      _DetailRow2('Over-force events',
                          detail.overForceCount > 0
                              ? '${detail.overForceCount}×' : 'None',
                          sub: 'Excessive downward force detected',
                          color: detail.overForceCount > 0
                              ? AppColors.error : AppColors.success),
                    ]),
                    _DetailSection('What this means',
                        body: 'Full chest recoil allows the heart to refill with blood '
                            'between compressions. Leaning, even slightly, reduces '
                            'venous return and can cut CPR effectiveness by up to 30%. '
                            'Complete release is as important as the compression itself.'),
                    _DetailSection('How to improve', bullets: [
                      if (detail.leaningCount == 0 && detail.overForceCount == 0) ...[
                        'Perfect recoil this session! The main challenge is maintaining this as fatigue sets in.',
                        'Stay conscious of fully lifting your weight after each push, especially in the second half of the session.',
                      ] else ...[
                        if (detail.leaningCount > 0)
                          'You had ${detail.leaningCount} leaning event(s). After each compression, fully lift your weight off the chest. The chest must physically rise before the next push.',
                        if (detail.overForceCount > 0)
                          'You had ${detail.overForceCount} over-force event(s). Let body weight do the work. Reduce hand pressure on the downstroke.',
                        'Avoid resting your hands on the sternum between compressions.',
                        'Think of each compression as two phases: push down, then fully release.',
                      ],
                    ]),
                  ],
                ),
              )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _CategoryTile(
                label: 'Posture',
                score: posturePct,
                rows: avgWristAngle > 0
                    ? [
                  _TileRow('Wrist angle',
                      '${avgWristAngle.toStringAsFixed(1)}°',
                      color: avgWristAngle <= 15 ? AppColors.success
                          : avgWristAngle <= 25  ? AppColors.warning
                          : AppColors.error),
                  _TileRow(
                      avgWristAngle <= 15 ? 'Good alignment'
                          : avgWristAngle <= 25 ? 'Slight tilt'
                          : 'Significant tilt',
                      '',
                      color: avgWristAngle <= 15 ? AppColors.success
                          : avgWristAngle <= 25  ? AppColors.warning
                          : AppColors.error),
                ]
                    : [
                  _TileRow('Correct',
                      '${posturePct.round()}%'),
                ],
                onTap: () => _MetricDetailSheet.show(context,
                  label: 'Posture',
                  icon: Icons.accessibility_new_rounded,
                  score: posturePct,
                  accentColor: _scoreColor(posturePct),
                  sections: [
                    _DetailSection('Your numbers', rows: [
                      _DetailRow2('Correct posture',
                          '${detail.correctPosture} / $total',
                          sub: '${posturePct.round()}% with good alignment'),
                      if (avgWristAngle > 0)
                        _DetailRow2('Avg wrist angle',
                            '${avgWristAngle.toStringAsFixed(1)}°',
                            sub: avgWristAngle <= 15
                                ? 'Within optimal range (< 15°)'
                                : avgWristAngle <= 25
                                ? 'Slight tilt. Try to straighten.'
                                : 'Significant tilt. Needs correction.',
                            color: avgWristAngle <= 15 ? AppColors.success
                                : avgWristAngle <= 25  ? AppColors.warning
                                : AppColors.error),
                    ]),
                    _DetailSection('What this means',
                        body: 'Wrist alignment affects the direction of compression force. '
                            'A tilted wrist (> 15°) redirects force laterally rather than '
                            'straight down, reducing effective depth and increasing wrist '
                            'injury risk. Correct posture ensures maximum force reaches the sternum.'),
                    _DetailSection('How to improve', bullets: [
                      if (avgWristAngle > 0 && avgWristAngle <= 15) ...[
                        'Great wrist alignment at ${avgWristAngle.toStringAsFixed(1)} degrees. Keep it up!',
                        'Posture tends to drift under fatigue, so stay mindful as the session progresses.',
                      ] else if (avgWristAngle > 15 && avgWristAngle <= 25) ...[
                        'Your wrist angle averaged ${avgWristAngle.toStringAsFixed(1)} degrees, a slight tilt. Check your wrist position before starting compressions.',
                        'Keep wrists neutral, inline with your forearm, not bent forward or back.',
                        'Interlace fingers and lift them off the chest.',
                      ] else if (avgWristAngle > 25) ...[
                        'Your wrist angle averaged ${avgWristAngle.toStringAsFixed(1)} degrees, a significant tilt. This redirects force away from the sternum and reduces effective depth.',
                        'Focus on straightening your wrists before each compression.',
                        'Position yourself directly above the sternum, shoulders over hands, elbows locked.',
                      ] else ...[
                        'Keep wrists neutral, inline with your forearm.',
                        'Position yourself directly above the sternum with elbows locked and arms perpendicular to the chest.',
                      ],
                    ]),
                  ],
                ),
              )),
            ],
          ),
        ),

        // ── Best streak ─────────────────────────────────────────────────
        if (detail.consecutiveGoodPeak > 0) ...[
          const SizedBox(height: AppSpacing.md),
          _BestStreakBanner(
            count: detail.consecutiveGoodPeak,
            onTap: () => _MetricDetailSheet.show(context,
              label: 'Best Streak',
              icon: Icons.local_fire_department_rounded,
              score: total > 0
                  ? detail.consecutiveGoodPeak / total * 100 : 0,
              accentColor: AppColors.success,
              scoreLabel: '${detail.consecutiveGoodPeak}/$total',
              sections: [
                _DetailSection('Your numbers', rows: [
                  _DetailRow2('Best streak',
                      '${detail.consecutiveGoodPeak} compressions',
                      sub: 'Longest unbroken run of perfect compressions'),
                  _DetailRow2('Total compressions', '$total'),
                ]),
                _DetailSection('What "perfect" means',
                    body: 'A compression counts toward the streak only when depth, '
                        'rate, recoil, AND posture are all correct simultaneously. '
                        'It is the hardest metric to sustain and reflects true '
                        'overall CPR quality under fatigue.'),
                _DetailSection('How to improve', bullets: [
                  if (total > 0 && detail.consecutiveGoodPeak < total ~/ 4)
                    'Your best streak of ${detail.consecutiveGoodPeak} is less than a quarter of your total compressions. Focus on keeping all four metrics correct at the same time, not just one or two.'
                  else if (detail.consecutiveGoodPeak < total ~/ 2)
                    'Your best streak covers about ${(detail.consecutiveGoodPeak / total * 100).round()}% of your session. You have the technique, but consistency breaks down over time.'
                  else
                    'Your best streak covers over half the session. Excellent consistency. The goal is to maintain this under fatigue.',
                  if (detail.fatigueOnsetIndex > 0)
                    'Fatigue was detected at compression ${detail.fatigueOnsetIndex}. This is likely where your streak broke. Request a rescuer swap earlier next time.'
                  else
                    'No fatigue was detected. If your streak still broke, focus on the specific metric that failed first.',
                  'Depth drifts first under fatigue. Watch the depth indicator as the session progresses.',
                ]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TileRow — a single data row on the card face
// ─────────────────────────────────────────────────────────────────────────────

class _TileRow {
  final String label;
  final String value;
  final Color? color;
  const _TileRow(this.label, this.value, {this.color});
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategoryTile
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final String         label;
  final double         score;
  final List<_TileRow> rows;
  final VoidCallback   onTap;

  const _CategoryTile({
    required this.label,
    required this.score,
    required this.rows,
    required this.onTap,
  });

  Color get _accent {
    if (score >= 80) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
          decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title + info icon ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(label,
                      style: AppTypography.subheading(size: 13)),
                ),
                Icon(Icons.info_outline_rounded,
                    size: AppSpacing.iconSm - 2,
                    color: AppColors.primary.withValues(alpha: 0.40)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // ── Score gauge ───────────────────────────────────────────
            ClipRRect(
              borderRadius:
              BorderRadius.circular(AppSpacing.buttonRadiusLg),
              child: LinearProgressIndicator(
                value: score / 100,
                minHeight: 4,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(_accent),
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${score.round()}%',
                  style: AppTypography.badge(size: 9, color: _accent)),
            ),

            // ── Data rows ─────────────────────────────────────────────
            if (rows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              const Divider(height: 1, thickness: 1, color: AppColors.divider),
              const SizedBox(height: AppSpacing.xxs),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: r.value.isEmpty
                  // Label-only row (dot + coloured text, e.g. "Perfect recoil ✓")
                      ? Row(
                    children: [
                      Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(
                            right: AppSpacing.xs,
                            top: AppSpacing.xxs + 1),
                        decoration: BoxDecoration(
                          color: r.color ?? AppColors.textDisabled,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(r.label,
                            style: AppTypography.caption(
                                color: r.color ??
                                    AppColors.textDisabled)),
                      ),
                    ],
                  )
                  // Normal label : value row
                      : Row(
                    children: [
                      Expanded(
                        child: Text(r.label,
                            style: AppTypography.caption(
                                color: AppColors.textDisabled)),
                      ),
                      Text(r.value,
                          style: AppTypography.bodyBold(
                              size: 11,
                              color: r.color ??
                                  AppColors.textSecondary)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DepthRateBanner
// ─────────────────────────────────────────────────────────────────────────────

class _DepthRateBanner extends StatelessWidget {
  final int          combo;
  final int          total;
  final VoidCallback onTap;

  const _DepthRateBanner({
    required this.combo,
    required this.total,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct   = total > 0 ? (combo / total * 100).round() : 0;
    final color = pct >= 80 ? AppColors.success
        : pct >= 60         ? AppColors.warning
        : AppColors.error;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadiusMd),
        child: Row(
          children: [
            Container(
              width: AppSpacing.iconLg, height: AppSpacing.iconLg,
              decoration: AppDecorations.iconRounded(
                  bg: color.withValues(alpha: 0.10),
                  radius: AppSpacing.cardRadiusSm),
              child: Icon(Icons.join_inner_rounded,
                  size: AppSpacing.iconSm, color: color),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('Depth + Rate',
                  style: AppTypography.subheading(size: 12)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$pct%',
                    style: AppTypography.numericDisplay(
                        size: 18, color: color)),
                Text('$combo / $total',
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
              ],
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.info_outline_rounded,
                size: AppSpacing.iconXs,
                color: AppColors.primary.withValues(alpha: 0.40)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BestStreakBanner
// ─────────────────────────────────────────────────────────────────────────────

class _BestStreakBanner extends StatelessWidget {
  final int          count;
  final VoidCallback onTap;
  const _BestStreakBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + AppSpacing.xs),
        decoration: AppDecorations.successCard(radius: AppSpacing.cardRadiusMd),
        child: Row(
          children: [
            Text('$count',
                style: AppTypography.numericDisplay(
                    size: 28, color: AppColors.success)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('best streak of compressions',
                  style: AppTypography.subheading(
                      size: 12, color: AppColors.success)),
            ),
            Icon(Icons.local_fire_department_rounded,
                color: AppColors.success.withValues(alpha: 0.35),
                size: AppSpacing.iconXl),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.info_outline_rounded,
                size: AppSpacing.iconXs,
                color: AppColors.success.withValues(alpha: 0.55)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailSection / _DetailRow2 — data classes for popup sections
// ─────────────────────────────────────────────────────────────────────────────

class _DetailSection {
  final String           title;
  final String?          body;
  final List<_DetailRow2> rows;
  final List<String>     bullets;
  const _DetailSection(this.title, {
    this.body,
    this.rows    = const [],
    this.bullets = const [],
  });
}

class _DetailRow2 {
  final String  label;
  final String  value;
  final String? sub;
  final Color?  color;
  const _DetailRow2(this.label, this.value, {this.sub, this.color});
}

// ─────────────────────────────────────────────────────────────────────────────
// _MetricDetailSheet
// ─────────────────────────────────────────────────────────────────────────────

class _MetricDetailSheet {
  static void show(
      BuildContext context, {
        required String               label,
        required IconData             icon,
        required Color                accentColor,
        required List<_DetailSection> sections,
        double?  score,
        String?  scoreLabel,
        String?  scoreSubLabel,
        Color?   scoreSubColor,
        Widget?  heroWidget,
      }) {
    showDialog<void>(
      context: context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _MetricDetailDialog(
        label:          label,
        icon:           icon,
        score:          score,
        accentColor:    accentColor,
        sections:       sections,
        scoreLabel:     scoreLabel,
        scoreSubLabel:  scoreSubLabel,
        scoreSubColor:  scoreSubColor,
        heroWidget:     heroWidget,
      ),
    );
  }
}

class _MetricDetailDialog extends StatelessWidget {
  final String              label;
  final IconData            icon;
  final double?              score;
  final Color               accentColor;
  final List<_DetailSection> sections;
  final String?             scoreLabel;
  final Widget?              heroWidget;
  final String?  scoreSubLabel;
  final Color?   scoreSubColor;

  const _MetricDetailDialog({
    required this.label,
    required this.icon,
    required this.score,
    required this.accentColor,
    required this.sections,
    this.scoreLabel,
    this.heroWidget,
    this.scoreSubLabel,
    this.scoreSubColor,
  });


  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical:   AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Top bar: title + close ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: accentColor.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(icon,
                        size: AppSpacing.iconSm, color: accentColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(label,
                        style: AppTypography.heading(size: 16)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Score ring ───────────────────────────────────────────────
// ── Hero: ring OR custom widget ──────────────────────────────────
        if (heroWidget != null)
    Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: heroWidget!,
    )
    else if (score != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100, height: 100,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value: score! / 100,
                          strokeWidth: 8,
                          strokeCap: StrokeCap.round,
                          backgroundColor: accentColor.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                        ),
                      ),
                      Text(scoreLabel ?? '${score!.round()}%',
                          style: AppTypography.numericDisplay(
                              size: scoreLabel != null ? 20 : 26,
                              color: accentColor)),
                    ],
                  ),
                ),
                if (scoreSubLabel != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(scoreSubLabel!,
                      textAlign: TextAlign.center,
                      style: AppTypography.caption(
                          color: scoreSubColor ?? AppColors.textDisabled)),
                ],
              ],
            ),
          ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Scrollable body ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < sections.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.md),
                      _buildSection(sections[i]),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: Text('Got it',
                  style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(_DetailSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title with accent bar
        if (section.title.isNotEmpty) ...[
          Row(
            children: [
              Container(
                width: 3, height: 12,
                margin: const EdgeInsets.only(right: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(AppSpacing.xxs),
                ),
              ),
              Text(section.title,
                  style: AppTypography.subheading(size: 12)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
        ],

        // Metric rows — each labelled, explained, value colour-coded
        if (section.rows.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius:
              BorderRadius.circular(AppSpacing.cardRadiusMd),
              border: Border.all(
                color: AppColors.cprCardBg.withValues(alpha: 0.12),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
            child: Column(
              children: [
                for (int i = 0; i < section.rows.length; i++) ...[
                  _buildMetricRow(section.rows[i]),
                  if (i < section.rows.length - 1)
                    const Divider(height: 1, color: AppColors.divider),
                ],
              ],
            ),
          ),

        // Body paragraph (what/why)
        if (section.body != null) ...[
          if (section.rows.isNotEmpty) const SizedBox(height: AppSpacing.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.screenBgGrey,
              borderRadius:
              BorderRadius.circular(AppSpacing.cardRadiusMd),
            ),
            child: Text(section.body!,
                style: AppTypography.body(
                    size: 13, color: AppColors.textSecondary)),
          ),
        ],

        // Bullet tips
        if (section.bullets.isNotEmpty) ...[
          if (section.rows.isNotEmpty || section.body != null)
            const SizedBox(height: AppSpacing.xs),
          ...section.bullets.map((b) => Padding(
            padding:
            const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(
                      top: AppSpacing.xxs + 2,
                      right: AppSpacing.xs),
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(b,
                      style: AppTypography.body(
                          size: 13,
                          color: AppColors.textSecondary)),
                ),
              ],
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildMetricRow(_DetailRow2 m) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.label,
                    style: AppTypography.bodyMedium(size: 13)),
                if (m.sub != null)
                  Text(m.sub!,
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(m.value,
              style: AppTypography.bodyBold(
                  size: 13,
                  color: m.color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SessionTimelineSection
// Contains: session start, first compression, fatigue, pauses,
//           ventilation cycles, rescuer swap prompts, session end.
// ─────────────────────────────────────────────────────────────────────────────

class _TLEvent {
  final String   time;
  final String   title;
  final String   subtitle;
  final Color    dotColor;
  final IconData icon;
  final String?  tip;
  final String?  badge;
  final Color?   badgeColor;
  final double   _sortKey;
  final bool     isGrayedOut;
  final bool isIgnored;
  final Color?   borderColor;

  const _TLEvent({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.dotColor,
    required this.icon,
    required double sortKey,
    this.tip,
    this.badge,
    this.badgeColor,
    this.isGrayedOut = false,
    this.isIgnored = false,
    this.borderColor,
  }) : _sortKey = sortKey;
}

class _SessionTimelineSection extends StatelessWidget {
  final SessionDetail detail;
  const _SessionTimelineSection({required this.detail});

  String _fmt(double secs) {
    final m = (secs ~/ 60).toString();
    final s = (secs % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  List<_TLEvent> _build() {
    final events = <_TLEvent>[];

    // Session start
    final ttf = detail.timeToFirstCompression;
    events.add(_TLEvent(
      sortKey:  0,
      time:     '0:00',
      title:    'Session started',
      subtitle: ttf > 0
          ? 'First compression at ${ttf.toStringAsFixed(1)} s'
          : 'Compressions begun immediately',
      dotColor: AppColors.primaryAlt,
      icon:     Icons.play_arrow_rounded,
      tip:      ttf > 5 ? 'Start faster. Target < 5 s.' : null,
    ));

    // Fatigue onset
    if (detail.fatigueOnsetIndex > 0 &&
        detail.compressions.length >= detail.fatigueOnsetIndex) {
      final t = detail.compressions[detail.fatigueOnsetIndex - 1].timestampSec;
      events.add(_TLEvent(
        sortKey:  t,
        time:     _fmt(t),
        title:    'Fatigue onset',
        subtitle: 'Detected at compression #${detail.fatigueOnsetIndex}',
        dotColor: AppColors.warning,
        icon:     Icons.trending_down_rounded,
      ));
    }

    // No-flow pauses
    double? lastTs;
    for (final c in detail.compressions) {
      final ts = c.timestampSec;
      if (lastTs != null) {
        final gap = ts - lastTs;
        if (gap > 2.0) {
          events.add(_TLEvent(
            sortKey:  lastTs,
            time:     _fmt(lastTs),
            title:    'Unplanned pause',
            subtitle: '${gap.toStringAsFixed(1)} s with no compressions',
            dotColor: AppColors.error,
            icon:     Icons.pause_circle_outline_rounded,
            tip:      'Keep pauses under 2 s',
          ));
        }
      }
      lastTs = ts;
    }

    // Ventilation cycles
    for (final v in detail.ventilations) {
      final t     = v.timestampSec;
      final given = v.compliant;
      events.add(_TLEvent(
        sortKey:    t,
        time:       _fmt(t),
        title:      'Ventilation · cycle ${v.cycleNumber}',
        subtitle:   given
            ? '${v.durationSec.toStringAsFixed(1)} s pause'
            : 'Prompt ignored · CPR continued',
        dotColor:   AppColors.primaryAlt,
        icon:       Icons.air_rounded,
        isGrayedOut: !given,
        isIgnored:  !given,
      ));
    }

    // Pulse check events
    for (final p in detail.pulseChecks) {
      final t         = p.timestampSec;
      final completed = p.userDecision != null;

      final dotColor = p.detected    ? AppColors.success
          : p.isUncertain            ? AppColors.warning
          :                            AppColors.error;

      events.add(_TLEvent(
        sortKey:     t,
        time:        _fmt(t),
        title:       'Pulse check #${p.intervalNumber}',
        subtitle:    !completed
            ? 'Prompt ignored · CPR continued'
            : p.detected && p.detectedBpm > 0
            ? '${p.detectedBpm.round()} bpm · ${p.confidence}% confidence'
            : p.isUncertain
            ? 'Weak signal · Verify manually'
            : 'No pulse found',
        dotColor:    dotColor,
        icon:        !completed          ? Icons.monitor_heart_outlined
            : p.detected                 ? Icons.favorite_rounded
            : p.isUncertain              ? Icons.help_outline_rounded
            :                              Icons.heart_broken_rounded,
        isGrayedOut: !completed,
        isIgnored:   !completed,
        tip:         p.isUncertain ? 'Weak signal. Verify manually.' : null,
      ));
    }

    // Rescuer swap prompts
    for (int i = 0; i < detail.rescuerSwapCount; i++) {
      final approxT = (i + 1) * 120.0;
      final isFatigueDriven = i == 0 &&
          detail.fatigueOnsetIndex > 0 &&
          detail.compressions.length >= detail.fatigueOnsetIndex &&
          detail.compressions[detail.fatigueOnsetIndex - 1].timestampSec < approxT;
      events.add(_TLEvent(
        sortKey:  approxT,
        time:     _fmt(approxT),
        title:    'Rescuer swap · alert ${i + 1}',
        subtitle: isFatigueDriven
            ? 'Triggered by fatigue detection'
            : '2-minute interval prompt',
        dotColor: AppColors.pbGoldDark.withValues(alpha: 0.8),
        icon:     Icons.swap_horiz_rounded,
      ));
    }

    events.sort((a, b) => a._sortKey.compareTo(b._sortKey));

    // Session end
    events.add(_TLEvent(
      sortKey:  detail.sessionDuration.toDouble(),
      time:     detail.durationFormatted,
      title:    'Session ended',
      subtitle: () {
        final unplanned = detail.unplannedPauseCount;
        final parts = ['${detail.compressionCount} compressions'];
        if (unplanned > 0) {
          parts.add('$unplanned unplanned pause${unplanned == 1 ? '' : 's'}');
        }
        return parts.join(' · ');
      }(),
      dotColor: AppColors.primaryAlt,
      icon:     Icons.stop_rounded,
    ));

    return events;
  }




  @override
  Widget build(BuildContext context) {
    final events = _build();

    // activeCprTime = pure hands-on time (no pauses of any kind)
    final activeCprTime = detail.sessionDuration - detail.noFlowTime;
    final compliantVentCount =
        detail.ventilations.where((v) => v.compliant).length;

    // True unplanned pause seconds (excludes ventilation + pulse check gaps)
    double unplannedSecs = 0;
    void sumGap(double gapStart, double gapEnd) {
      final dur = gapEnd - gapStart;
      if (dur <= 2.0) return;
      final inVent = detail.ventilations.any((v) {
        final vs = v.timestampSec;
        return gapStart < (vs + v.durationSec) && gapEnd > vs;
      });
      final inPulse = detail.pulseChecks.any((p) {
        return gapStart < (p.timestampSec + 10.0) && gapEnd > p.timestampSec;
      });
      if (!inVent && !inPulse) unplannedSecs += dur;
    }
    if (detail.compressions.isNotEmpty) {
      sumGap(0, detail.compressions.first.timestampSec);
      for (int i = 1; i < detail.compressions.length; i++) {
        sumGap(detail.compressions[i - 1].timestampSec,
            detail.compressions[i].timestampSec);
      }
      sumGap(detail.compressions.last.timestampSec,
          detail.sessionDuration.toDouble());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < events.length; i++)
          _TimelineRow(event: events[i], isLast: i == events.length - 1),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1, thickness: 1, color: AppColors.divider),
        const SizedBox(height: AppSpacing.sm),
        _TimelineStatGrid(
          detail:             detail,
          activeCprTime:      activeCprTime,
          noFlowTime:     unplannedSecs,
          noFlowIntervals: detail.unplannedPauseCount,
          compliantVentCount: compliantVentCount,
        ),
      ],
    );
  }}


class _StatChip {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  const _StatChip(this.icon, this.label, this.value, this.color);
}

class _TimelineRow extends StatelessWidget {
  final _TLEvent event;
  final bool     isLast;
  const _TimelineRow({required this.event, required this.isLast});


  static const double _dotSize      = 30.0;
  static const double _dotBookend   = 38.0;
  static const double _lineWidth    = 2.0;
  static const double _timeColWidth = 34.0;

  @override
  Widget build(BuildContext context) {
    final isBookend = event.icon == Icons.play_arrow_rounded ||
        event.icon == Icons.stop_rounded;

    final textColor = event.isGrayedOut
        ? AppColors.textDisabled
        : AppColors.textPrimary;
    final subtitleColor = event.isGrayedOut
        ? AppColors.textDisabled.withValues(alpha: 0.6)
        : AppColors.textSecondary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: _timeColWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs + AppSpacing.xxs),
              child: Text(
                event.time,
                style: AppTypography.caption(color: AppColors.textDisabled),
                textAlign: TextAlign.right,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Dot + connector
          Column(
            children: [
              if (isBookend)
                SizedBox(
                  width:  _dotSize,
                  height: _dotBookend,
                  child: Center(
                    child: Container(
                      width:  _dotBookend,
                      height: _dotBookend,
                      decoration: BoxDecoration(
                        color: AppColors.primaryAlt,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryAlt.withValues(alpha: 0.30),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(event.icon,
                          color: AppColors.textOnDark,
                          size:  AppSpacing.iconSm),
                    ),
                  ),
                )
              else if (event.isIgnored)
                SizedBox(
                  width:  _dotSize,
                  height: _dotSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width:  _dotSize,
                        height: _dotSize,
                        decoration: BoxDecoration(
                          color: AppColors.screenBgGrey.withValues(alpha: 0.70),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.textDisabled.withValues(alpha: 0.70),
                            width: 1.2,
                          ),
                        ),
                        child: Icon(event.icon,
                            color: AppColors.textDisabled.withValues(alpha: 0.70),
                            size: AppSpacing.iconSm - 4),
                      ),
                      CustomPaint(
                        size: Size(_dotSize, _dotSize),
                        painter: _StrikethroughDotPainter(),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width:  _dotSize,
                  height: _dotSize,
                  decoration: BoxDecoration(
                    color: event.dotColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(event.icon,
                      color: event.dotColor,
                      size:  AppSpacing.iconSm - 2),
                ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: _lineWidth,
                    color: AppColors.divider,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),

          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  top:    AppSpacing.xxs + 2,
                  bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: (isBookend
                          ? AppTypography.bodyBold(size: 14)
                          : AppTypography.bodyMedium(size: 13)
                      ).copyWith(color: textColor)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(event.subtitle,
                      style: AppTypography.caption()
                          .copyWith(color: subtitleColor)),
                  if (event.tip != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical:   AppSpacing.xxs + 1),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                            AppSpacing.buttonRadiusLg),
                      ),
                      child: Text(event.tip!,
                          style: AppTypography.badge(
                              size: 9, color: AppColors.warning)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrikethroughDotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Clip to circle so the line doesn't poke outside
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    final paint = Paint()
      ..color = AppColors.textDisabled.withValues(alpha: 0.70)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    // Top-right to bottom-left
    canvas.drawLine(
      Offset(size.width * 0.78, size.height * 0.18),
      Offset(size.width * 0.22, size.height * 0.82),
      paint,
    );
  }

  @override
  bool shouldRepaint(_StrikethroughDotPainter _) => false;
}

class _TimelineStatGrid extends StatelessWidget {
  final SessionDetail detail;
  final double activeCprTime;
  final double noFlowTime;
  final int    noFlowIntervals;
  final int    compliantVentCount;

  const _TimelineStatGrid({
    required this.detail,
    required this.activeCprTime,
    required this.noFlowTime,
    required this.noFlowIntervals,
    required this.compliantVentCount,
  });

  static String _fmtDuration(double secs) {
    final m = (secs ~/ 60).toString();
    final s = (secs % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // ── Pulse chip ──────────────────────────────────────────────────────────
    _StatChip? pulseChip;
    if (detail.pulseChecks.isNotEmpty) {
      final total = detail.pulseChecks.length;
      final completed = detail.pulseChecks.where((p) => p.userDecision != null).length;
      final lastDetected = detail.pulseChecks.lastWhere(
            (p) => p.detected && p.detectedBpm > 0,
        orElse: () => detail.pulseChecks.first,
      );
      final hasDetection = lastDetected.detected && lastDetected.detectedBpm > 0;
      final mainVal = hasDetection
          ? '${lastDetected.detectedBpm.round()} bpm on #${lastDetected.intervalNumber}'
          : '${total}×';
      final complianceNote = ' · $completed/$total completed';
      pulseChip = _StatChip(
        Icons.monitor_heart_outlined,
        'Pulse checks',
        '$mainVal$complianceNote',
        hasDetection ? const Color(0xFF1B5E20) : AppColors.textSecondary,
      );
    }

    // ── Colors ──────────────────────────────────────────────────────────────
    final unplanned = detail.unplannedPauseCount;
    final pauseColor = (noFlowTime > 5 || unplanned > 2)
        ? const Color(0xFF7B3F00)    // dark burnt orange
        : const Color(0xFF2E7D32);   // dark green
    final ventColor = compliantVentCount == detail.ventilations.length
        ? const Color(0xFF0D47A1)    // dark blue
        : const Color(0xFF7B3F00);   // dark burnt orange

    // ── Chip list ───────────────────────────────────────────────────────────
    final stats = <_StatChip>[
      _StatChip(Icons.timer_outlined,   'Total time',
          detail.durationFormatted,         const Color(0xFF374151)),
      _StatChip(Icons.favorite_rounded, 'Active CPR',
          _fmtDuration(activeCprTime),      const Color(0xFF1E3A6E)),
      _StatChip(Icons.compress_rounded, 'Compressions',
          '${detail.compressionCount}',     const Color(0xFF1F2937)),
      if (unplanned > 0)
        _StatChip(Icons.pause_rounded,  'Unplanned pauses',
            '${noFlowTime.toStringAsFixed(1)} s ($unplanned×)',
            pauseColor),
      if (detail.ventilations.isNotEmpty)
        _StatChip(Icons.air_rounded,    'Ventilations',
            '$compliantVentCount / ${detail.ventilations.length} completed',
            ventColor),
      if (pulseChip != null) pulseChip,
    ];

    final rows = <List<_StatChip>>[];
    for (int i = 0; i < stats.length; i += 2) {
      rows.add([stats[i], if (i + 1 < stats.length) stats[i + 1]]);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: Column(
        children: rows.map((row) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            children: [
              Expanded(child: _buildChip(row[0])),
              if (row.length > 1) ...[
                Container(width: 1, height: 32, color: AppColors.divider),
                Expanded(child: _buildChip(row[1])),
              ] else
                const Expanded(child: SizedBox()),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildChip(_StatChip s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Row(
        children: [
          Icon(s.icon, size: AppSpacing.iconSm - 4, color: s.color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label,
                    style: AppTypography.caption(
                        color: const Color(0xFF4B5563)),
                    overflow: TextOverflow.ellipsis),
                Text(s.value,
                    style: AppTypography.bodyBold(size: 12, color: s.color),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// _RescuerVitalsSection
// ─────────────────────────────────────────────────────────────────────────────

class _RescuerVitalsSection extends StatelessWidget {
  final double?       rescuerHR;
  final double?       rescuerSpO2;
  final SessionDetail detail;


  const _RescuerVitalsSection({
    required this.rescuerHR,
    required this.rescuerSpO2,
    required this.detail,
  });

  int get _fatigueScore => SessionDetail.computeFatigueScore(
    detail.rescuerVitals,
    detail.compressions,
  );

  String get _fatigueLabel {
    final s = _fatigueScore;
    if (s == 0)  return 'none detected';
    if (s < 30)  return 'low';
    if (s < 60)  return 'moderate';
    return 'high';
  }

  Color get _fatigueColor {
    final s = _fatigueScore;
    if (s == 0)  return AppColors.textDisabled;
    if (s < 30)  return AppColors.success;
    if (s < 60)  return AppColors.warning;
    return AppColors.error;
  }

  double? get _rescuerTemp {
    final valid = detail.rescuerVitals.where((v) => v.temperature > 0);
    return valid.isEmpty ? null : valid.last.temperature;
  }

  int get _lastRMSSD {
    if (detail.rescuerVitals.isEmpty) return 0;
    return detail.rescuerVitals.last.rmssd;
  }

  int get _lastPI {
    if (detail.rescuerVitals.isEmpty) return 0;
    return detail.rescuerVitals.last.rescuerPi;
  }

  void _showFatigueDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _FatigueDetailDialog(
        score:       _fatigueScore,
        label:       _fatigueLabel,
        color:       _fatigueColor,
        vitals:      detail.rescuerVitals,
        compressions: detail.compressions,
        onset:       detail.fatigueOnsetIndex,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onset  = detail.fatigueOnsetIndex;
    final rmssd  = _lastRMSSD;
    final pi     = _lastPI;
    final temp   = _rescuerTemp;
    final ambient = detail.ambientTempStart;

    final hrColor = rescuerHR == null  ? AppColors.textDisabled
        : rescuerHR! < 60             ? AppColors.primary
        : rescuerHR! <= 100           ? AppColors.success
        : rescuerHR! <= 130           ? AppColors.warning
        :                               AppColors.error;
    final hrSub = rescuerHR == null ? 'no data'
        : rescuerHR! < 60           ? 'low'
        : rescuerHR! <= 100         ? 'normal'
        : rescuerHR! <= 130         ? 'elevated'
        :                             'high';

    final spo2Color = rescuerSpO2 == null ? AppColors.textDisabled
        : rescuerSpO2! >= 95             ? AppColors.success
        : rescuerSpO2! >= 90             ? AppColors.warning
        :                                  AppColors.error;
    final spo2Sub = rescuerSpO2 == null ? 'no data'
        : rescuerSpO2! >= 95            ? 'normal'
        : rescuerSpO2! >= 90            ? 'low-normal'
        :                                 'low';

    final rmssdSub = rmssd == 0 ? 'no data'
        : rmssd >= 30           ? 'normal variability'
        : rmssd >= 15           ? 'reduced'
        :                         'low';
    final rmssdColor = rmssd == 0    ? AppColors.textDisabled
        : rmssd >= 30                ? AppColors.success
        : rmssd >= 15                ? AppColors.warning
        :                              AppColors.error;

    final piSub = pi == 0 ? 'no data'
        : pi >= 40         ? 'normal'
        : pi >= 20         ? 'mild reduction'
        :                    'low — vasoconstriction';
    final piColor = pi == 0  ? AppColors.textDisabled
        : pi >= 40           ? AppColors.success
        : pi >= 20           ? AppColors.warning
        :                      AppColors.error;

    final tempSub = temp == null ? 'no data'
        : temp <= 35.0 ? 'low'
        : temp <= 37.5 ? 'normal range'
        : temp <= 38.5 ? 'mildly elevated'
        :                'elevated';
    final tempColor = temp == null ? AppColors.textDisabled
        : temp <= 35.0 ? AppColors.primary
        : temp <= 37.5 ? AppColors.success
        : temp <= 38.5 ? AppColors.warning
        :                AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Fatigue score ──────────────────────────────────────────────────
        if (detail.rescuerVitals.isNotEmpty) ...[
          _VitalInfoTile.wide(
            icon:    Icons.local_fire_department_rounded,
            label:   'Fatigue Score',
            value:   '$_fatigueScore',
            unit:    '/ 100',
            sub:     _fatigueLabel,
            color:   _fatigueColor,
            progress: _fatigueScore / 100,
            bottomNote: onset > 0
                ? 'First detected at compression #$onset'
                : 'No fatigue detected this session',
            bottomNoteColor: onset > 0 ? AppColors.warning : AppColors.success,
            bottomNoteIcon: onset > 0
                ? Icons.bolt_rounded
                : Icons.check_circle_outline_rounded,
              onInfo: () => _showFatigueDetail(context),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── HR + SpO2 row ──────────────────────────────────────────────────
        if (rescuerHR != null || rescuerSpO2 != null) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xxs, bottom: AppSpacing.xs),
            child: Text('AT LAST PAUSE',
                style: AppTypography.badge(
                    size: 10, color: AppColors.textDisabled)),
          ),
          Row(
            children: [
              if (rescuerHR != null)
                Expanded(child: _VitalInfoTile(
                  icon:  Icons.favorite_rounded,
                  label: 'Heart rate',
                  value: '${rescuerHR!.round()}',
                  unit:  'bpm',
                  sub:   hrSub,
                  color: hrColor,
                    onInfo: () => showDialog<void>(
                      context: context,
                      barrierColor: AppColors.overlayDark,
                      builder: (_) => _HeartRateDetailDialog(
                        hr:     rescuerHR!,
                        hrSub:  hrSub,
                        hrColor: hrColor,
                        vitals: detail.rescuerVitals,
                      ),
                    ),
                )),
              if (rescuerHR != null && rescuerSpO2 != null)
                const SizedBox(width: AppSpacing.sm),
              if (rescuerSpO2 != null)
                Expanded(child: _VitalInfoTile(
                  icon:  Icons.air_rounded,
                  label: 'SpO₂',
                  value: '${rescuerSpO2!.round()}',
                  unit:  '%',
                  sub:   spo2Sub,
                  color: spo2Color,
                    onInfo: () => showDialog<void>(
                      context: context,
                      barrierColor: AppColors.overlayDark,
                      builder: (_) => _SpO2DetailDialog(
                        spo2:     rescuerSpO2!,
                        spo2Sub:  spo2Sub,
                        spo2Color: spo2Color,
                      ),
                    ),
                )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],


        // ── Wrist temp + Room temp row ─────────────────────────────────────
        if (temp != null || ambient != null)
          Row(
            children: [
              if (temp != null)
                Expanded(child: _VitalInfoTile(
                  icon:  Icons.watch_rounded,
                  label: 'Wrist temp',
                  value: temp.toStringAsFixed(1),
                  unit:  '°C',
                  sub:   tempSub,
                  color: tempColor,
                  onInfo: () => showDialog<void>(
                    context: context,
                    barrierColor: AppColors.overlayDark,
                      builder: (_) => _WristTempDetailDialog(
                        temp:      temp,
                        tempSub:   tempSub,
                        tempColor: tempColor,
                        vitals:    detail.rescuerVitals,
                      ),
                  ),
                )),
              if (temp != null && ambient != null)
                const SizedBox(width: AppSpacing.sm),
              if (ambient != null)
                Expanded(child: _VitalInfoTile(
                  icon:  Icons.device_thermostat_rounded,
                  label: 'Room temp',
                  value: ambient.toStringAsFixed(1),
                  unit:  '°C',
                  sub:   'at session start',
                  color: AppColors.textSecondary,
                  onInfo: () => showDialog<void>(
                    context: context,
                    barrierColor: AppColors.overlayDark,
                    builder: (_) => _RoomTempDetailDialog(
                      ambientStart: detail.ambientTempStart,
                      ambientEnd:   detail.ambientTempEnd,
                    ),
                  ),
                )),
            ],
          ),
      ],
    );
  }

  void _showInfo(
      BuildContext context,
      String label,
      IconData icon,
      Color color,
      String body, {
        List<_DetailRow2> rows = const [],
        String? footer,
      }) {
    _MetricDetailSheet.show(
      context,
      label:       label,
      icon:        icon,
      accentColor: color,
      sections: [
        _DetailSection('', body: body, rows: rows),
        if (footer != null)
          _DetailSection('', body: footer),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FatigueDetailDialog
// ─────────────────────────────────────────────────────────────────────────────

class _FatigueDetailDialog extends StatelessWidget {
  final int                        score;
  final String                     label;
  final Color                      color;
  final List<RescuerVitalSnapshot> vitals;
  final List<CompressionEvent>     compressions;
  final int                        onset;

  const _FatigueDetailDialog({
    required this.score,
    required this.label,
    required this.color,
    required this.vitals,
    required this.compressions,
    required this.onset,
  });

  // ── Signal data helpers ──────────────────────────────────────────────────

  double get _firstHR   => vitals.isNotEmpty ? vitals.first.heartRate : 0;
  double get _lastHR    => vitals.isNotEmpty ? vitals.last.heartRate  : 0;
  int    get _firstRMSSD => vitals.isNotEmpty ? vitals.first.rmssd    : 0;
  int    get _lastRMSSD  => vitals.isNotEmpty ? vitals.last.rmssd     : 0;

  double get _peakDepth {
    if (compressions.isEmpty) return 0;
    return compressions.map((c) => c.depth).reduce((a, b) => a > b ? a : b);
  }

  double get _lastAvgDepth {
    if (compressions.length < 5) return 0;
    final last = compressions.sublist(compressions.length - 5);
    return last.map((c) => c.depth).reduce((a, b) => a + b) / 5;
  }

  // ── Sub-score helpers ────────────────────────────────────────────────────

  double get _hrSubScore => _firstHR > 0
      ? ((_lastHR - _firstHR) / 40.0).clamp(0.0, 1.0) * 100
      : 0.0;

  double get _rmssdSubScore => _firstRMSSD > 0
      ? ((_firstRMSSD - _lastRMSSD) / _firstRMSSD.toDouble()).clamp(0.0, 1.0) * 100
      : 0.0;

  double get _depthSubScore {
    if (compressions.length < 5) return 0.0;
    return ((_peakDepth - _lastAvgDepth) / 2.0).clamp(0.0, 1.0) * 100;
  }

  static Widget _sectionLabel(String text, Color accentColor) {
    return Row(
      children: [
        Container(
          width: 3, height: 12,
          margin: const EdgeInsets.only(right: AppSpacing.xs),
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
        ),
        Text(text, style: AppTypography.subheading(size: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hrDiff    = _lastHR - _firstHR;
    final rmssdDiff = _lastRMSSD - _firstRMSSD;
    final depthDiff = _lastAvgDepth > 0 ? _lastAvgDepth - _peakDepth : 0.0;

    final hasHR    = _firstHR > 0 && _lastHR > 0;
    final hasRMSSD = _firstRMSSD > 0 && _lastRMSSD > 0;
    final hasDepth = compressions.length >= 5 && _peakDepth > 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical:   AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: color.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(Icons.local_fire_department_rounded,
                        size: AppSpacing.iconSm, color: color),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Fatigue Score',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Ring + sub-labels ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 100, height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CircularProgressIndicator(
                            value: score / 100,
                            strokeWidth: 8,
                            strokeCap: StrokeCap.round,
                            backgroundColor: color.withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        ),
                        Text('$score / 100',
                            style: AppTypography.numericDisplay(
                                size: 20, color: color)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(label,
                      style: AppTypography.caption(color: color)),
                  const SizedBox(height: AppSpacing.sm),
                  if (onset > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded,
                            size: AppSpacing.iconXs,
                            color: AppColors.warning),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('First detected at compression #$onset',
                            style: AppTypography.caption(
                                color: AppColors.warning)),
                      ],
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: AppSpacing.iconXs,
                            color: AppColors.success),
                        const SizedBox(width: AppSpacing.xxs),
                        Text('No fatigue detected this session',
                            style: AppTypography.caption(
                                color: AppColors.success)),
                      ],
                    ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Body ─────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // Intro
                    Text(
                      'A weighted score combining three physiological signals. '
                          'Each signal is compared from the start to the end of the session. '
                          'The more each deteriorated, the higher its contribution to the score.',
                      style: AppTypography.body(
                          size: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Formula label
                    _sectionLabel('Formula', color),
                    const SizedBox(height: AppSpacing.xs),

                    // Signal table
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                        border: Border.all(color: AppColors.divider),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                      child: Column(
                        children: [
                          _buildSignalRow(
                            icon:     Icons.favorite_rounded,
                            label:    'Heart rate trend',
                            sub:      'Rising HR = cardiovascular stress',
                            weight:   40,
                            subScore: _hrSubScore,
                            valueText: hasHR
                                ? '${_firstHR.round()} → ${_lastHR.round()} bpm'
                                : '—',
                            diffText: hasHR
                                ? '${hrDiff >= 0 ? '+' : ''}${hrDiff.round()} bpm'
                                : null,
                            diffColor: hrDiff > 10
                                ? AppColors.warning
                                : AppColors.success,
                            isHighlight: true,
                          ),
                          const Divider(height: 1, color: AppColors.divider),
                          _buildSignalRow(
                            icon:     Icons.show_chart_rounded,
                            label:    'HRV decline (RMSSD)',
                            sub:      'Falling variability = autonomic stress',
                            weight:   35,
                            subScore: _rmssdSubScore,
                            valueText: hasRMSSD
                                ? '$_firstRMSSD → $_lastRMSSD ms'
                                : '—',
                            diffText: hasRMSSD
                                ? '${rmssdDiff >= 0 ? '+' : ''}${rmssdDiff} ms'
                                : null,
                            diffColor: rmssdDiff < -5
                                ? AppColors.warning
                                : AppColors.success,
                            isHighlight: true,
                          ),
                          const Divider(height: 1, color: AppColors.divider),
                          _buildSignalRow(
                            icon:     Icons.compress_rounded,
                            label:    'Depth trend',
                            sub:      'Declining depth = physical fatigue',
                            weight:   25,
                            subScore: _depthSubScore,
                            valueText: hasDepth
                                ? '${_peakDepth.toStringAsFixed(1)} → ${_lastAvgDepth.toStringAsFixed(1)} cm'
                                : '—',
                            diffText: hasDepth
                                ? '${depthDiff >= 0 ? '+' : ''}${depthDiff.toStringAsFixed(1)} cm'
                                : null,
                            diffColor: depthDiff < -0.5
                                ? AppColors.warning
                                : AppColors.success,
                            isHighlight: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: Text('Got it', style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalRow({
    required IconData icon,
    required String   label,
    required String   sub,
    required int      weight,
    required double   subScore,
    required String   valueText,
    required String?  diffText,
    required Color    diffColor,
    required bool     isHighlight,
  }) {
    final rowColor = isHighlight ? AppColors.primary : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Accent bar
          if (isHighlight)
            Container(
              width: 3, height: 40,
              margin: const EdgeInsets.only(right: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            const SizedBox(width: AppSpacing.xs + 3),

          // Icon
          Padding(
            padding: const EdgeInsets.only(top: 2, right: AppSpacing.xs),
            child: Icon(icon, size: AppSpacing.iconXs, color: rowColor),
          ),

          // Label + sub + start→end
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.caption(color: rowColor)),
                const SizedBox(height: 2),
                Text(sub,
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)
                        .copyWith(fontSize: 10)),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Text(valueText,
                        style: AppTypography.bodyBold(
                            size: 11, color: AppColors.textSecondary)),
                    if (diffText != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 1),
                        decoration: BoxDecoration(
                          color: diffColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                              AppSpacing.buttonRadiusLg),
                        ),
                        child: Text(diffText,
                            style: AppTypography.badge(
                                size: 9, color: diffColor)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Weight % + sub-score bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$weight%',
                  style: AppTypography.bodyBold(
                      size: 13, color: rowColor)),
              const SizedBox(height: AppSpacing.xxs),
              SizedBox(
                width: 40,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                      AppSpacing.buttonRadiusLg),
                  child: LinearProgressIndicator(
                    value: subScore / 100,
                    minHeight: 4,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        subScore > 50 ? AppColors.warning : AppColors.success),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HeartRateDetailDialog
// ─────────────────────────────────────────────────────────────────────────────

class _HeartRateDetailDialog extends StatelessWidget {
  final double                     hr;
  final String                     hrSub;
  final Color                      hrColor;
  final List<RescuerVitalSnapshot> vitals;

  const _HeartRateDetailDialog({
    required this.hr,
    required this.hrSub,
    required this.hrColor,
    required this.vitals,
  });

  bool get _hasVitals => vitals.length >= 2;

  int get _firstRMSSD => _hasVitals ? vitals.first.rmssd : 0;
  int get _lastRMSSD  => _hasVitals ? vitals.last.rmssd  : 0;
  int get _firstPI    => _hasVitals ? vitals.first.rescuerPi : 0;
  int get _lastPI     => _hasVitals ? vitals.last.rescuerPi  : 0;

  Color _rmssdColor(int v) {
    if (v == 0)   return AppColors.textDisabled;
    if (v >= 30)  return AppColors.success;
    if (v >= 15)  return AppColors.warning;
    return AppColors.error;
  }

  Color _piColor(int v) {
    if (v == 0)  return AppColors.textDisabled;
    if (v >= 40) return AppColors.success;
    if (v >= 20) return AppColors.warning;
    return AppColors.error;
  }

  static Widget _sectionLabel(String text, Color color) => Row(
    children: [
      Container(
        width: 3, height: 12,
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
        ),
      ),
      Expanded(child: Text(text, style: AppTypography.subheading(size: 12))),
    ],
  );

  Widget _startEndTable({
    required String startLabel,
    required String startValue,
    required String endValue,
    required int    diff,
    required String unit,
    required Color  endColor,
  }) {
    final diffText = '${diff >= 0 ? '+' : ''}$diff $unit';
    final diffColor = diff > 0 ? AppColors.success : AppColors.warning;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
        border: Border.all(
            color: AppColors.cprCardBg.withValues(alpha: 0.12), width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      child: Column(
        children: [
          // Start row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text('Session start',
                    style: AppTypography.bodyMedium(size: 13))),
                Text(startValue,
                    style: AppTypography.bodyBold(
                        size: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // End row + diff pill
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text('Session end',
                    style: AppTypography.bodyMedium(size: 13))),
                Text(endValue,
                    style: AppTypography.bodyBold(size: 13, color: endColor)),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: 2),
                  decoration: BoxDecoration(
                    color: diffColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
                  ),
                  child: Text(diffText,
                      style: AppTypography.badge(size: 9, color: diffColor)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rmssdDiff = _lastRMSSD - _firstRMSSD;
    final piDiff    = _lastPI    - _firstPI;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical:   AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: hrColor.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(Icons.favorite_rounded,
                        size: AppSpacing.iconSm, color: hrColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Heart Rate',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Hero value ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: '${hr.round()}',
                        style: AppTypography.numericDisplay(
                            size: 48, color: hrColor),
                      ),
                      TextSpan(
                        text: ' bpm',
                        style: AppTypography.bodyMedium(
                            size: 16,
                            color: hrColor.withValues(alpha: 0.7)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(hrSub,
                      style: AppTypography.subheading(
                          size: 13, color: hrColor)),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Body ─────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Heart Rate explanation ───────────────────────────
                    _sectionLabel('Heart Rate', hrColor),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.screenBgGrey,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                      ),
                      child: Text(
                            'During compressions, motion artifacts drop signal quality to near zero, so '
                            'the value shown is from the last ventilation pause.\n'
                            'Normal resting HR is 60–100 bpm. '
                            'Elevated HR during CPR is expected and reflects cardiovascular effort.',
                        style: AppTypography.body(
                            size: 13, color: AppColors.textSecondary),
                      ),
                    ),

                    // ── RMSSD ────────────────────────────────────────────
                    if (_hasVitals && _firstRMSSD > 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      _sectionLabel('HRV — Heart Rate Variability (RMSSD)',
                          _rmssdColor(_lastRMSSD)),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.screenBgGrey,
                          borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                        ),
                        child: Text(
                          'Measures variation between consecutive heartbeats (ms). '
                              'Higher = more relaxed and adaptive. '
                              'A declining RMSSD during CPR is an early sign of physical fatigue.',
                          style: AppTypography.body(
                              size: 13, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _startEndTable(
                        startLabel: 'Session start',
                        startValue: '$_firstRMSSD ms',
                        endValue:   '$_lastRMSSD ms',
                        diff:       rmssdDiff,
                        unit:       'ms',
                        endColor:   _rmssdColor(_lastRMSSD),
                      ),
                    ],

                    // ── Perfusion Index ──────────────────────────────────
                    if (_hasVitals && _firstPI > 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      _sectionLabel('Perfusion Index',
                          _piColor(_lastPI)),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.screenBgGrey,
                          borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                        ),
                        child: Text(
                          'Ratio of pulsatile to non-pulsatile blood flow at the wrist. '
                              'A declining value means vasoconstriction, '
                              'blood being redirected away from the extremities under load.',
                          style: AppTypography.body(
                              size: 13, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _startEndTable(
                        startLabel: 'Session start',
                        startValue: '$_firstPI / 100',
                        endValue:   '$_lastPI / 100',
                        diff:       piDiff,
                        unit:       '',
                        endColor:   _piColor(_lastPI),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'See the Charts tab for your heart rate trend over the full session.',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: Text('Got it', style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpO2DetailDialog
// ─────────────────────────────────────────────────────────────────────────────

class _SpO2DetailDialog extends StatelessWidget {
  final double spo2;
  final String spo2Sub;
  final Color  spo2Color;

  const _SpO2DetailDialog({
    required this.spo2,
    required this.spo2Sub,
    required this.spo2Color,
  });

  static Widget _sectionLabel(String text, Color color) => Row(
    children: [
      Container(
        width: 3, height: 12,
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
        ),
      ),
      Expanded(child: Text(text,
          style: AppTypography.subheading(size: 12))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical:   AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: spo2Color.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(Icons.air_rounded,
                        size: AppSpacing.iconSm, color: spo2Color),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Blood Oxygen (SpO₂)',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Hero value ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: '${spo2.round()}',
                        style: AppTypography.numericDisplay(
                            size: 48, color: spo2Color),
                      ),
                      TextSpan(
                        text: ' %',
                        style: AppTypography.bodyMedium(
                            size: 16,
                            color: spo2Color.withValues(alpha: 0.7)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(spo2Sub,
                      style: AppTypography.subheading(
                          size: 13, color: spo2Color)),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Body ─────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _sectionLabel('Blood Oxygen Saturation', spo2Color),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.screenBgGrey,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                      ),
                      child: Text(
                        'SpO₂ is the percentage of haemoglobin in your blood actively '
                            'carrying oxygen.\n'
                            'The reading shown is from the last ventilation pause, '
                            'when wrist signal quality is highest.'
                            'A minor drop during intense physical activity is normal.',
                        style: AppTypography.body(
                            size: 13, color: AppColors.textSecondary),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),
                    _sectionLabel('What the values mean', spo2Color),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                        border: Border.all(
                            color: AppColors.cprCardBg.withValues(alpha: 0.12),
                            width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                      child: Column(
                        children: [
                          _buildRangeRow('95–100%', 'Normal',
                              AppColors.success, isLast: false),
                          const Divider(height: 1, color: AppColors.divider),
                          _buildRangeRow('90–94%', 'Low-normal',
                              AppColors.warning, isLast: false),
                          const Divider(height: 1, color: AppColors.divider),
                          _buildRangeRow('Below 90%', 'Hypoxia',
                              AppColors.error, isLast: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: Text('Got it', style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeRow(String range, String meaning, Color color,
      {required bool isLast}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Text(range,
              style: AppTypography.bodyMedium(size: 13))),
          Text(meaning,
              style: AppTypography.caption(color: color)),
        ],
      ),
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// _WristTempDetailDialog
// ─────────────────────────────────────────────────────────────────────────────

class _WristTempDetailDialog extends StatelessWidget {
  final double                     temp;
  final String                     tempSub;
  final Color                      tempColor;
  final List<RescuerVitalSnapshot> vitals;

  const _WristTempDetailDialog({
    required this.temp,
    required this.tempSub,
    required this.tempColor,
    required this.vitals,
  });

  double? get _firstTemp {
    final v = vitals.where((s) => s.temperature > 0);
    return v.isEmpty ? null : v.first.temperature;
  }

  double? get _lastTemp {
    final v = vitals.where((s) => s.temperature > 0);
    return v.isEmpty ? null : v.last.temperature;
  }

  static Widget _sectionLabel(String text, Color color) => Row(
    children: [
      Container(
        width: 3, height: 12,
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
        ),
      ),
      Expanded(child: Text(text, style: AppTypography.subheading(size: 12))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final first     = _firstTemp;
    final last      = _lastTemp;
    final heroVal   = (last ?? temp).toStringAsFixed(1);
    final hasTrend  = first != null && last != null && (last - first).abs() >= 0.1;
    final diff      = hasTrend ? last! - first! : 0.0;
    final diffColor = diff > 0.5 ? AppColors.warning : AppColors.success;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical:   AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: tempColor.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(Icons.watch_rounded,
                        size: AppSpacing.iconSm, color: tempColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Wrist Temperature',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Hero: last measured ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: heroVal,
                        style: AppTypography.numericDisplay(
                            size: 48, color: tempColor),
                      ),
                      TextSpan(
                        text: ' °C',
                        style: AppTypography.bodyMedium(
                            size: 16,
                            color: tempColor.withValues(alpha: 0.7)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text('last measured',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Body ─────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _sectionLabel('What this measures', tempColor),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.screenBgGrey,
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                      ),
                      child: Text(
                        'Skin temperature at the rescuer\'s wrist, measured continuously '
                            'by the glove sensor. It rises during sustained physical exertion '
                            'as blood flow to the extremities increases ',
                        style: AppTypography.body(
                            size: 13, color: AppColors.textSecondary),
                      ),
                    ),

                    if (first != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _sectionLabel('During session', tempColor),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                          border: Border.all(
                              color: AppColors.cprCardBg.withValues(alpha: 0.12),
                              width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xxs),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm),
                              child: Row(
                                children: [
                                  Expanded(child: Text('Session start',
                                      style: AppTypography.bodyMedium(size: 13))),
                                  Text('${first.toStringAsFixed(1)} °C',
                                      style: AppTypography.bodyBold(
                                          size: 13,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: AppColors.divider),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm),
                              child: Row(
                                children: [
                                  Expanded(child: Text('Session end',
                                      style: AppTypography.bodyMedium(size: 13))),
                                  Text('${last!.toStringAsFixed(1)} °C',
                                      style: AppTypography.bodyBold(
                                          size: 13, color: tempColor)),
                                  if (hasTrend) ...[
                                    const SizedBox(width: AppSpacing.xs),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: diffColor.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(
                                            AppSpacing.buttonRadiusLg),
                                      ),
                                      child: Text(
                                        '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)} °C',
                                        style: AppTypography.badge(
                                            size: 9, color: diffColor),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: Text('Got it', style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoomTempDetailDialog
// ─────────────────────────────────────────────────────────────────────────────

class _RoomTempDetailDialog extends StatelessWidget {
  final double? ambientStart;
  final double? ambientEnd;

  const _RoomTempDetailDialog({
    required this.ambientStart,
    required this.ambientEnd,
  });

  @override
  Widget build(BuildContext context) {
    final lastVal = ambientEnd ?? ambientStart;
    if (lastVal == null) return const SizedBox.shrink();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dialogInsetH,
          vertical:   AppSpacing.dialogInsetV),
      child: Container(
        decoration: AppDecorations.dialog(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: AppColors.textSecondary.withValues(alpha: 0.10),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(Icons.device_thermostat_rounded,
                        size: AppSpacing.iconSm,
                        color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Room Temperature',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Hero ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: lastVal.toStringAsFixed(1),
                        style: AppTypography.numericDisplay(
                            size: 48, color: AppColors.textSecondary),
                      ),
                      TextSpan(
                        text: ' °C',
                        style: AppTypography.bodyMedium(
                            size: 16,
                            color: AppColors.textSecondary.withValues(alpha: 0.7)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(ambientEnd != null ? 'at session end' : 'at session start',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.screenBgGrey,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
                ),
                child: Text(
                  'Ambient air temperature recorded by the glove sensor. '
                      'Warmer environments increase rescuer fatigue and may affect sensor accuracy.',
                  style: AppTypography.body(
                      size: 13, color: AppColors.textSecondary),
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48)),
              child: Text('Got it', style: AppTypography.buttonSecondary()),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VitalInfoTile
// Vital metric tile with an [i] tap for explanation.
// Use _VitalInfoTile.wide() for the full-width fatigue card.
// ─────────────────────────────────────────────────────────────────────────────

class _VitalInfoTile extends StatelessWidget {
  final IconData  icon;
  final String    label;
  final String    value;
  final String    unit;
  final String    sub;
  final Color     color;
  final VoidCallback onInfo;
  final bool      _wide;
  final double?   progress;
  final String?   bottomNote;
  final Color?    bottomNoteColor;
  final IconData? bottomNoteIcon;

  const _VitalInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
    required this.color,
    required this.onInfo,
    this.progress,
    this.bottomNote,
    this.bottomNoteColor,
    this.bottomNoteIcon,
  }) : _wide = false;

  const _VitalInfoTile.wide({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
    required this.color,
    required this.onInfo,
    this.progress,
    this.bottomNote,
    this.bottomNoteColor,
    this.bottomNoteIcon,
  }) : _wide = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _wide ? double.infinity : null,
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      decoration: AppDecorations.tintedCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row with icon + [i]
          Row(
            children: [
              Icon(icon, size: AppSpacing.iconXs, color: AppColors.textDisabled),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(label,
                    style: AppTypography.caption(color: AppColors.textSecondary)),
              ),
              GestureDetector(
                onTap: onInfo,
                child: Icon(Icons.info_outline_rounded,
                    size: AppSpacing.iconXs,
                    color: AppColors.primary.withValues(alpha: 0.45)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Value + unit
          RichText(
            text: TextSpan(children: [
              TextSpan(
                text: value,
                style: AppTypography.numericDisplay(size: 24, color: color),
              ),
              TextSpan(
                text: '  $unit',
                style: AppTypography.bodyMedium(
                    size: 12, color: color.withValues(alpha: 0.7)),
              ),
            ]),
          ),
          const SizedBox(height: AppSpacing.xxs),

          // Sub label
          Text(sub,
              style: AppTypography.caption(
                  color: color.withValues(alpha: 0.75))),

          // Progress bar (fatigue only)
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],

          // Bottom note (onset line)
          if (bottomNote != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                if (bottomNoteIcon != null) ...[
                  Icon(bottomNoteIcon,
                      size: AppSpacing.iconXs,
                      color: bottomNoteColor ?? AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Expanded(
                  child: Text(bottomNote!,
                      style: AppTypography.caption(
                          color: bottomNoteColor ?? AppColors.textSecondary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VitalReadingTile — individual vital tile (HR, SpO2, temp)
// ─────────────────────────────────────────────────────────────────────────────

class _VitalReadingTile extends StatelessWidget {
  final String   label;
  final String   value;
  final String   unit;
  final String   sub;
  final Color    color;
  final IconData icon;

  const _VitalReadingTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + icon
          Row(
            children: [
              Icon(icon, size: AppSpacing.iconXs,
                  color: AppColors.textDisabled),
              const SizedBox(width: AppSpacing.xxs),
              Text(label,
                  style: AppTypography.caption(
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Big value + unit
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppTypography.numericDisplay(
                      size: 24, color: color),
                ),
                TextSpan(
                  text: ' $unit',
                  style: AppTypography.bodyMedium(
                      size: 12, color: color.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          // Status label
          Text(sub,
              style: AppTypography.caption(
                  color: color.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SummaryOnlyMetrics
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryOnlyMetrics extends StatelessWidget {
  final int    compressionCount;
  final double averageDepth;

  const _SummaryOnlyMetrics({
    required this.compressionCount,
    required this.averageDepth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_rounded,
                size: AppSpacing.iconXl, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text('Detailed metrics not available',
                style: AppTypography.subheading(
                    color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Full metrics are only available for sessions loaded '
                  'from the glove.\nHistory sessions show summary data only.',
              textAlign: TextAlign.center,
              style: AppTypography.caption(color: AppColors.textDisabled),
            ),
          ],
        ),
      ),
    );
  }
}


// ═════════════════════════════════════════════════════════════════════════════
// TAB 3 — Charts
// ═════════════════════════════════════════════════════════════════════════════

class _TrainingChartsTab extends StatelessWidget {
  final SessionDetail? detail;
  final bool           hasGraphs;
  final double         targetDepthMin;
  final double         targetDepthMax;

  const _TrainingChartsTab({
    required this.detail,
    required this.hasGraphs,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasGraphs) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart_rounded,
                  size: AppSpacing.iconXl, color: AppColors.textDisabled),
              const SizedBox(height: AppSpacing.md),
              Text('No chart data available',
                  style: AppTypography.subheading(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Charts are available immediately after a live session.\n'
                    'History sessions do not carry the full compression stream.',
                textAlign: TextAlign.center,
                style: AppTypography.caption(color: AppColors.textDisabled),
              ),
            ],
          ),
        ),
      );
    }

    final d      = detail!;
    final events = d.compressions;

    // ── Chart 2 — Rate ────────────────────────────────────────────────────
    // frequency (rolling avg) as main smooth line
    final rateSpots = events
        .map((e) => FlSpot(
      e.timestampSec,
      (e.frequency > 0 ? e.frequency : e.instantaneousRate)
          .clamp(0.0, 250.0),
    ))
        .toList();
    // instantaneousRate as faint second series
    final instRateSpots = events
        .where((e) => e.instantaneousRate > 0)
        .map((e) => FlSpot(e.timestampSec, e.instantaneousRate.clamp(0.0, 250.0)))
        .toList();

    // ── Chart 3 — Fatigue trend ───────────────────────────────────────────
    List<FlSpot> fatigueTrend = [];
    if (events.length >= 5) {
      for (int i = 4; i < events.length; i++) {
        final avg = (events[i - 4].depth + events[i - 3].depth +
            events[i - 2].depth + events[i - 1].depth + events[i].depth) /
            5.0;
        fatigueTrend.add(FlSpot(events[i].timestampSec, avg.clamp(0.0, 10.0)));
      }
    }

    // ── Chart 4 — Rescuer HR ──────────────────────────────────────────────
    final hrSpots = d.rescuerVitals
        .where((v) => v.heartRate > 0 && v.signalQuality >= 40)
        .map((v) => FlSpot(v.timestampSec, v.heartRate.clamp(0.0, 250.0)))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Chart 1 — Depth & Recoil ─────────────────────────────────
          _ChartCard(
            title:     'Compression Depth & Recoil',
            subtitle:  'Bar bottom = recoil depth · top = peak depth · '
                'green = full recoil · red = incomplete',
            lineColor: AppColors.primary,
            child: _DepthRecoilChart(
              events:         events,
              targetDepthMin: targetDepthMin,
              targetDepthMax: targetDepthMax,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Chart 2 — Compression Rate ────────────────────────────────
          _ChartCard(
            title:     'Compression Rate',
            subtitle:  'Target 100–120 BPM · line = rolling avg · dots = per-compression',
            lineColor: AppColors.success,
            child: _GraphCard(
              title:           'Rate',
              unit:            'BPM',
              minY:            70,
              maxY:            150,
              targetMin:       CprTargets.rateMin,
              targetMax:       CprTargets.rateMax,
              spots:           rateSpots,
              spots2:          instRateSpots,
              lineColor:       AppColors.success,
              lineColor2:      AppColors.success.withValues(alpha: 0.35),
              leftLabels:      const ['70', '100', '120', '150'],
              leftLabelValues: const [70, 100, 120, 150],
              targetLabel:     '100–120 BPM',
            ),
          ),

          // ── Chart 3 — Depth Trend / Fatigue ──────────────────────────
          if (fatigueTrend.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _ChartCard(
              title:    'Depth Trend',
              subtitle: '5-compression rolling average — declining line indicates fatigue',
              lineColor: AppColors.warning,
              child: _GraphCard(
                title:           'Depth Trend',
                unit:            'cm',
                minY:            0,
                maxY:            8,
                targetMin:       targetDepthMin,
                targetMax:       targetDepthMax,
                spots:           fatigueTrend,
                lineColor:       AppColors.warning,
                leftLabels:      const ['0', '3', '5', '6', '8'],
                leftLabelValues: const [0, 3, 5, 6, 8],
                targetLabel:     '${targetDepthMin.toStringAsFixed(0)}–'
                    '${targetDepthMax.toStringAsFixed(0)} cm',
              ),
            ),
          ],

          // ── Chart 4 — Rescuer Heart Rate ──────────────────────────────
          if (hrSpots.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _ChartCard(
              title:    'Rescuer Heart Rate',
              subtitle: 'Rising trend indicates increasing physical load',
              lineColor: AppColors.warning,
              child: _GraphCard(
                title:           'Rescuer HR',
                unit:            'bpm',
                minY:            40,
                maxY:            180,
                targetMin:       0,
                targetMax:       0,
                spots:           hrSpots,
                lineColor:       AppColors.warning,
                leftLabels:      const ['40', '80', '120', '150', '180'],
                leftLabelValues: const [40, 80, 120, 150, 180],
                targetLabel:     '',
                showTargetBand:  false,
                referenceLineY:  150,
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _DepthRecoilChart — bar chart showing peak depth and valley per compression
// ═════════════════════════════════════════════════════════════════════════════

class _DepthRecoilChart extends StatelessWidget {
  final List<CompressionEvent> events;
  final double targetDepthMin;
  final double targetDepthMax;

  const _DepthRecoilChart({
    required this.events,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    final hasValley = events.any((e) => e.valleyDepth > 0);
    final barWidth  = events.length > 80 ? 2.0
        : events.length > 40 ? 3.0
        : 4.0;

    final bars = events.asMap().entries.map((entry) {
      final e     = entry.value;
      final color = e.recoilAchieved ? AppColors.success : AppColors.error;
      final from  = hasValley ? e.valleyDepth.clamp(0.0, 8.0) : 0.0;
      final to    = e.depth.clamp(from + 0.1, 8.0); // always at least 0.1 tall
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            fromY:        from,
            toY:          to,
            color:        color.withValues(alpha: 0.85),
            width:        barWidth,
            borderRadius: BorderRadius.circular(1),
          ),
        ],
      );
    }).toList();

    final xInterval = events.length > 60 ? 20.0
        : events.length > 30 ? 10.0
        : 5.0;

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: 8,
          barGroups: bars,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color:       AppColors.divider,
              strokeWidth: AppSpacing.dividerThickness,
            ),
          ),
          borderData: FlBorderData(show: false),
          rangeAnnotations: RangeAnnotations(
            horizontalRangeAnnotations: [
              HorizontalRangeAnnotation(
                y1:    targetDepthMin,
                y2:    targetDepthMax,
                color: AppColors.success.withValues(alpha: 0.08),
              ),
              if (hasValley)
                HorizontalRangeAnnotation(
                  y1:    0,
                  y2:    0.5,
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
            ],
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y:           targetDepthMin,
                color:       AppColors.success.withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray:   [4, 4],
              ),
              HorizontalLine(
                y:           targetDepthMax,
                color:       AppColors.success.withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray:   [4, 4],
              ),
              if (hasValley)
                HorizontalLine(
                  y:           0.5,
                  color:       AppColors.primary.withValues(alpha: 0.3),
                  strokeWidth: 1,
                  dashArray:   [3, 5],
                  label: HorizontalLineLabel(
                    show:          true,
                    alignment:     Alignment.topLeft,
                    labelResolver: (_) => 'recoil threshold',
                    style: AppTypography.caption(
                        color: AppColors.primary.withValues(alpha: 0.6)),
                  ),
                ),
            ],
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 28,
                interval:     2,
                getTitlesWidget: (value, _) {
                  if (value % 2 == 0) {
                    return Text(value.toInt().toString(),
                        style: AppTypography.caption(
                            color: AppColors.textDisabled));
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 18,
                interval:     xInterval,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= events.length) {
                    return const SizedBox.shrink();
                  }
                  final secs = events[idx].timestampSec.toInt();
                  final mm   = (secs ~/ 60).toString();
                  final ss   = (secs % 60).toString().padLeft(2, '0');
                  return Text('$mm:$ss',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled));
                },
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final e    = events[group.x];
                final secs = e.timestampMs ~/ 1000;
                final mm   = (secs ~/ 60).toString();
                final ss   = (secs % 60).toString().padLeft(2, '0');
                final recoilLabel = e.recoilAchieved
                    ? '✓ Recoil OK'
                    : '✗ Recoil failed';
                final valleyStr = hasValley
                    ? '\nValley: ${e.valleyDepth.toStringAsFixed(1)} cm'
                    : '';
                return BarTooltipItem(
                  'Peak: ${e.depth.toStringAsFixed(1)} cm'
                      '$valleyStr\n$recoilLabel\n$mm:$ss',
                  AppTypography.caption(color: AppColors.textOnDark),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String  title;
  final String  subtitle;
  final Color   lineColor;
  final Widget  child;

  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.lineColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
      Container(
      width: 4,
        height: AppSpacing.md,
        decoration: AppDecorations.accentBar(color: lineColor),
      ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.subheading(size: 13)),
                    Text(subtitle, style: AppTypography.caption()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMERGENCY TAB 1 — Summary
// ═════════════════════════════════════════════════════════════════════════════

class _EmergencySummaryTab extends ConsumerWidget {
  final SessionDetail?  detail;
  final SessionSummary? summary;
  final String?         note;
  final bool            canEditNote;
  final VoidCallback    onEditNote;
  final VoidCallback    onExport;
  final bool            isPediatric;
  final double          targetDepthMin;
  final double          targetDepthMax;

  const _EmergencySummaryTab({
    required this.detail,
    required this.summary,
    required this.note,
    required this.canEditNote,
    required this.onEditNote,
    required this.onExport,
    required this.isPediatric,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = detail;
    final s = summary;

    final compressions    = d?.compressionCount ?? s?.compressionCount ?? 0;
    final duration        = d?.durationFormatted ?? s?.durationFormatted ?? '—';
    final avgDepth        = d?.averageDepth      ?? s?.averageDepth      ?? 0.0;
    final avgFreq         = d?.averageFrequency  ?? s?.averageFrequency  ?? 0.0;
    final noFlowTime      = d?.noFlowTime        ?? 0.0;
    final handsOnPct      = d?.handsOnPct        ?? '—';
    final handsOnOk       = (d?.handsOnRatio     ?? 0) >= 0.80;
    final noFlowIntervals = d?.unplannedPauseCount ?? 0;
    final handsDouble     = double.tryParse(
        handsOnPct.replaceAll('%', '').trim()) ?? 0.0;

    final depthOk   = avgDepth >= targetDepthMin && avgDepth <= targetDepthMax;
    final depthHigh = avgDepth > targetDepthMax;
    final rateOk    = avgFreq >= 100 && avgFreq <= 120;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Hero row ────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _HeroStatTile(
                icon:  Icons.schedule_rounded,
                label: 'Duration',
                value: duration,
              )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _HeroStatTile(
                icon:  Icons.favorite_rounded,
                label: 'Compressions',
                value: '$compressions',
              )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Quality grid ─────────────────────────────────────────────
          GridView.count(
            crossAxisCount:   2,
            shrinkWrap:       true,
            physics:          const NeverScrollableScrollPhysics(),
            mainAxisSpacing:  AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.3,
            padding:          EdgeInsets.zero,
            children: [
              _GridStatTile(
                label:    'Avg Depth',
                value:    avgDepth > 0
                    ? '${avgDepth.toStringAsFixed(1)} cm' : '—',
                dotColor: depthOk  ? AppColors.success
                    : depthHigh    ? AppColors.error
                    : AppColors.warning,
                zoneBar: avgDepth > 0 ? _ZoneBarConfig(
                  minVal: 0, maxVal: 8,
                  targetMin: targetDepthMin,
                  targetMax: targetDepthMax,
                  currentVal: avgDepth,
                  dotColor: depthOk ? AppColors.success
                      : depthHigh   ? AppColors.error
                      : AppColors.warning,
                  targetLabel:
                  '${targetDepthMin.toStringAsFixed(0)}–${targetDepthMax.toStringAsFixed(0)} cm',
                ) : null,
              ),
              _GridStatTile(
                label:    'Avg Rate',
                value:    avgFreq > 0 ? '${avgFreq.round()} bpm' : '—',
                dotColor: rateOk ? AppColors.success
                    : (avgFreq >= 90 && avgFreq <= 130)
                    ? AppColors.warning : AppColors.error,
                zoneBar: avgFreq > 0 ? _ZoneBarConfig(
                  minVal: 60, maxVal: 160,
                  targetMin: 100, targetMax: 120,
                  currentVal: avgFreq,
                  dotColor: rateOk ? AppColors.success
                      : (avgFreq >= 90 && avgFreq <= 130)
                      ? AppColors.warning : AppColors.error,
                  targetLabel: '100–120',
                ) : null,
              ),
              _GridStatTile(
                label:    'Hands-On',
                value:    handsOnPct,
                dotColor: handsOnOk ? AppColors.success : AppColors.warning,
                zoneBar: handsOnPct != '—' ? _ZoneBarConfig(
                  minVal: 0, maxVal: 100,
                  targetMin: 80, targetMax: 100,
                  currentVal: handsDouble,
                  dotColor: handsOnOk
                      ? AppColors.success : AppColors.warning,
                  targetLabel: '≥ 80%',
                ) : null,
              ),
              _GridStatTile(
                label:    'Pause Time',
                value:    noFlowTime > 0
                    ? '${noFlowTime.toStringAsFixed(1)}s' : '0s',
                note:     '$noFlowIntervals pause(s)',
                dotColor: noFlowTime <= 5
                    ? AppColors.success : AppColors.warning,
                zoneBar: _ZoneBarConfig(
                  minVal: 0, maxVal: 15,
                  targetMin: 0, targetMax: 5,
                  currentVal: noFlowTime.clamp(0.0, 15.0),
                  dotColor: noFlowTime <= 5
                      ? AppColors.success : AppColors.warning,
                  targetLabel: '< 5s',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Ventilation (conditional) ────────────────────────────────
          if (d != null && d.ventilationCount > 0) ...[
            _SectionCard(
              title:     'Ventilation',
              icon:      Icons.air_rounded,
              iconColor: AppColors.primaryAlt,
              startOpen: true,
              child:     _VentilationSection(detail: d),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── Sync banner ──────────────────────────────────────────────
          if (d?.syncedToBackend == false) ...[
            _UnsyncedBanner(
                isLoggedIn: ref.watch(authStateProvider).isLoggedIn),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── Note ─────────────────────────────────────────────────────
          _NoteCard(note: note, canEdit: canEditNote, onTap: onEditNote),
          const SizedBox(height: AppSpacing.sm),

          _ExportButton(onTap: onExport, label: 'Export Emergency Report'),
          const SizedBox(height: AppSpacing.xs),
          const _PastSessionsButton(),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMERGENCY TAB 2 — Patient
// ═════════════════════════════════════════════════════════════════════════════

class _EmergencyPatientTab extends StatelessWidget {
  final SessionDetail?  detail;
  final SessionSummary? summary;
  final bool            isPediatric;
  final double?         rescuerHR;
  final double?         rescuerSpO2;

  const _EmergencyPatientTab({
    required this.detail,
    required this.summary,
    required this.isPediatric,
    required this.rescuerHR,
    required this.rescuerSpO2,
  });

  @override
  Widget build(BuildContext context) {
    final d = detail;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Pulse checks ─────────────────────────────────────────────
          if (d != null && d.pulseChecks.isNotEmpty) ...[
            _SectionCard(
              title:     'Pulse Checks',
              icon:      Icons.monitor_heart_outlined,
              iconColor: AppColors.success,
              startOpen: true,
              child:     _PulseChecksSection(detail: d),
            ),
            const SizedBox(height: AppSpacing.sm),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.tintedCard(),
              child: Row(
                children: [
                  Icon(Icons.monitor_heart_outlined,
                      size: AppSpacing.iconSm,
                      color: AppColors.textDisabled),
                  const SizedBox(width: AppSpacing.sm),
                  Text('No pulse checks were performed',
                      style: AppTypography.body(
                          size: 13, color: AppColors.textDisabled)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── Patient & environment ────────────────────────────────────
          if (d != null && (d.patientTemperature != null ||
              d.ambientTempStart != null || isPediatric)) ...[
            _SectionCard(
              title:     'Patient & Environment',
              icon:      Icons.person_outline_rounded,
              iconColor: AppColors.primary,
              startOpen: true,
              child:     _PatientEnvironmentSection(
                detail:      d,
                isPediatric: isPediatric,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── Rescuer vitals ───────────────────────────────────────────
          if (rescuerHR != null || rescuerSpO2 != null) ...[
            _SectionCard(
              title:     'Rescuer Vitals',
              icon:      Icons.watch_rounded,
              iconColor: AppColors.primaryAlt,
              startOpen: false,
              child:     _BiometricsSection(
                detail:      d,
                summary:     summary,
                rescuerHR:   rescuerHR,
                rescuerSpO2: rescuerSpO2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMERGENCY TAB 3 — Timeline
// ═════════════════════════════════════════════════════════════════════════════

class _EmergencyTimelineTab extends StatelessWidget {
  final SessionDetail? detail;

  const _EmergencyTimelineTab({required this.detail});

  @override
  Widget build(BuildContext context) {
    final d = detail;

    if (d == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timeline_rounded,
                  size: AppSpacing.iconXl,
                  color: AppColors.textDisabled),
              const SizedBox(height: AppSpacing.md),
              Text('Timeline not available',
                  style: AppTypography.subheading(
                      color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Full timeline is only available for sessions '
                    'loaded directly from the glove.',
                textAlign: TextAlign.center,
                style: AppTypography.caption(
                    color: AppColors.textDisabled),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCard(
            title:     'Session Timeline',
            icon:      Icons.timeline_rounded,
            iconColor: AppColors.primaryAlt,
            startOpen: true,
            child:     _SessionTimelineSection(detail: d),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PulseChecksSection
// ─────────────────────────────────────────────────────────────────────────────

class _PulseChecksSection extends StatelessWidget {
  final SessionDetail detail;
  const _PulseChecksSection({required this.detail});

  @override
  Widget build(BuildContext context) {
    final detected = detail.pulseDetectedFinal;
    final color    = detected ? AppColors.success : AppColors.textSecondary;
    final lastCheck = detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.last : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Final outcome banner ────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusMd),
          ),
          child: Row(
            children: [
              Icon(
                detected
                    ? Icons.favorite_rounded
                    : Icons.heart_broken_rounded,
                color: color, size: AppSpacing.iconSm,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  detected ? 'Pulse Detected' : 'No Pulse Detected',
                  style: AppTypography.subheading(
                      size: 14, color: color),
                ),
              ),
              if (lastCheck != null && lastCheck.detectedBpm > 0)
                Text(
                  '${lastCheck.detectedBpm.round()} bpm',
                  style: AppTypography.numericDisplay(
                      size: 18, color: color),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Individual checks ───────────────────────────────────────────
        ...detail.pulseChecks.map((pc) {
          final c = pc.detected    ? AppColors.success
              : pc.isUncertain     ? AppColors.warning
              :                      AppColors.textSecondary;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _DetailRow(
              icon:       Icons.sensors_rounded,
              label:      'Check #${pc.intervalNumber}',
              value:      pc.detected   ? 'Present'
                  : pc.isUncertain      ? 'Uncertain'
                  :                       'Absent',
              note:       pc.detectedBpm > 0
                  ? '${pc.detectedBpm.toStringAsFixed(0)} bpm · ${pc.confidence}% confidence'
                  : null,
              iconColor:  c,
              valueColor: c,
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PatientEnvironmentSection
// ─────────────────────────────────────────────────────────────────────────────

class _PatientEnvironmentSection extends StatelessWidget {
  final SessionDetail detail;
  final bool          isPediatric;
  const _PatientEnvironmentSection({
    required this.detail,
    required this.isPediatric,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          icon:      Icons.person_outline_rounded,
          label:     'Patient Type',
          value:     isPediatric ? 'Pediatric' : 'Adult',
          iconColor: AppColors.primary,
        ),
        if (detail.patientTemperature != null)
          _DetailRow(
            icon:      Icons.thermostat_rounded,
            label:     'Patient Skin Temperature',
            value:     '${detail.patientTemperature!.toStringAsFixed(1)} °C',
            note:      'Fingertip sensor',
            iconColor: AppColors.error,
          ),
        if (detail.ambientTempStart != null)
          _DetailRow(
            icon:      Icons.device_thermostat_rounded,
            label:     'Room Temperature',
            value:     '${detail.ambientTempStart!.toStringAsFixed(1)} °C',
            note:      'At session start',
            iconColor: AppColors.textSecondary,
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMERGENCY HEADER
// ═════════════════════════════════════════════════════════════════════════════

class _EmergencyHeader extends StatelessWidget {
  final String  durationFormatted;
  final int     compressionCount;
  final bool    isPediatric;
  final String  handsOnPct;
  final bool    handsOnOk;
  final double  avgBpm;
  final double  avgDepth;
  final String  targetDepthLabel;
  final double  targetDepthMin;
  final double  targetDepthMax;
  final double  noFlowTime;

  const _EmergencyHeader({
    required this.durationFormatted,
    required this.compressionCount,
    required this.isPediatric,
    required this.handsOnPct,
    required this.handsOnOk,
    required this.avgBpm,
    required this.avgDepth,
    required this.targetDepthLabel,
    required this.targetDepthMin,
    required this.targetDepthMax,
    required this.noFlowTime,
  });

  @override
  Widget build(BuildContext context) {
    final depthOk = avgDepth >= targetDepthMin && avgDepth <= targetDepthMax;
    final rateOk  = avgBpm >= CprTargets.rateMin && avgBpm <= CprTargets.rateMax;

    return Container(
      width: double.infinity,
        decoration: AppDecorations.emergencyGradient(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        children: [
          // Icon + label row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52, height: 52,
                decoration: AppDecorations.iconCircle(
                    bg: AppColors.textOnDark.withValues(alpha: 0.15)),
                child: const Icon(Icons.emergency_rounded,
                    color: AppColors.textOnDark, size: AppSpacing.iconMd),
              ),
              const SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CPR Session Complete',
                      style: AppTypography.poppins(
                          size: 18, weight: FontWeight.w700,
                          color: AppColors.textOnDark)),
                  if (isPediatric)
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.xxs),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                      decoration: AppDecorations.chip(
                        color: AppColors.textOnDark,
                        bg:    AppColors.textOnDark.withValues(alpha: 0.2),
                      ),
                      child: Text('👶 PEDIATRIC CPR',
                          style: AppTypography.badge(
                              size: 9, color: AppColors.textOnDark)),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Main stat strip: Duration / Compressions / CCF
          Container(
            decoration: AppDecorations.darkStatTile(),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _SummaryCell(value: durationFormatted,   label: 'DURATION'),
                  _VDivider(),
                  _SummaryCell(value: '$compressionCount', label: 'COMPRESSIONS'),
                  _VDivider(),
                  _SummaryCell(value: handsOnPct,          label: 'HANDS-ON'),
                  _VDivider(),
                  _SummaryCell(
                    value: noFlowTime > 0
                        ? '${noFlowTime.toStringAsFixed(0)}s' : '0s',
                    label: 'PAUSE TIME',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Quality tiles: 2×2 grid
          Row(
            children: [
              _EmergencyTile(
                label:   'AVG DEPTH',
                value:   avgDepth > 0
                    ? '${avgDepth.toStringAsFixed(1)} cm' : '—',
                ok:      depthOk,
                note:    targetDepthLabel,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EmergencyTile(
                label:   'AVG RATE',
                value:   avgBpm > 0 ? '${avgBpm.round()} bpm' : '—',
                ok:      rateOk,
                note:    '100–120 bpm',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _EmergencyTile(
                label:   'HANDS-ON TIME',
                value:   handsOnPct,
                ok:      handsOnOk,
                note:    'Target ≥ 80%',
              ),
              const SizedBox(width: AppSpacing.sm),
              _EmergencyTile(
                label:   'PAUSE TIME',
                value:   noFlowTime > 0
                    ? '${noFlowTime.toStringAsFixed(1)}s' : '0s',
                ok:      noFlowTime <= 5,
                note:    'Unplanned pauses',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmergencyTile extends StatelessWidget {
  final String  label;
  final String  value;
  final bool    ok;
  final String? note;

  const _EmergencyTile({
    required this.label,
    required this.value,
    required this.ok,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppColors.feedbackGood : AppColors.warning;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm, horizontal: AppSpacing.sm),
        decoration: AppDecorations.chip(
          color: color,
          bg:    AppColors.textOnDark.withValues(alpha: 0.10),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTypography.poppins(
                    size: 20, weight: FontWeight.w700, color: color)),
            const SizedBox(height: AppSpacing.xxs),
            Text(label, textAlign: TextAlign.center,
                style: AppTypography.badge(
                    size: 8, color: AppColors.textOnDark.withValues(alpha: 0.7))),
            if (note != null)
              Text(note!, textAlign: TextAlign.center,
                  style: AppTypography.caption(
                      color: AppColors.textOnDark.withValues(alpha: 0.55))),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _PulseResultCard — prominent ROSC/pulse card for Emergency
// ═════════════════════════════════════════════════════════════════════════════

class _PulseResultCard extends StatelessWidget {
  final SessionDetail detail;
  const _PulseResultCard({required this.detail});

  @override
  Widget build(BuildContext context) {
    final detected = detail.pulseDetectedFinal;
    final color    = detected ? AppColors.success : AppColors.textSecondary;
    final lastCheck = detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.last : null;

    return Container(
      decoration: detected
          ? AppDecorations.successCard()
          : AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Container(
                width: AppSpacing.iconLg,
                height: AppSpacing.iconLg,
                decoration: AppDecorations.iconRounded(
                    bg: color.withValues(alpha: 0.12),
                    radius: AppSpacing.cardRadiusSm),
                child: Icon(
                  detected
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: color,
                  size: AppSpacing.iconSm,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pulse Check Result',
                        style: AppTypography.subheading(size: 13)),
                    Text(
                      '${detail.pulseChecksPrompted} check(s) prompted · '
                          '${detail.pulseChecksComplied} completed',
                      style: AppTypography.caption(),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Big ROSC status
          Center(
            child: Column(
              children: [
                Text(
                  detected ? '✓ Pulse Detected' : '✗ No Pulse Detected',
                  style: AppTypography.poppins(
                      size: 20, weight: FontWeight.w700, color: color),
                ),
                if (lastCheck != null && lastCheck.detectedBpm > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${lastCheck.detectedBpm.toStringAsFixed(0)} BPM',
                    style: AppTypography.numericDisplay(
                        size: 36, color: color),
                  ),
                  Text(
                    '${lastCheck.confidence}% confidence',
                    style: AppTypography.caption(),
                  ),
                ],
              ],
            ),
          ),

          // Individual checks
          if (detail.pulseChecks.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: AppSpacing.sm),
            ...detail.pulseChecks.map((pc) {
              final c = pc.detected
                  ? AppColors.success
                  : pc.isUncertain ? AppColors.warning : AppColors.textSecondary;
              return _DetailRow(
                icon:       Icons.sensors_rounded,
                label:      'Check #${pc.intervalNumber}',
                value:      pc.detected ? 'Present'
                    : pc.isUncertain ? 'Uncertain' : 'Absent',
                note:       pc.detectedBpm > 0
                    ? '${pc.detectedBpm.toStringAsFixed(0)} BPM · ${pc.confidence}% confidence'
                    : null,
                iconColor:  c,
                valueColor: c,
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _SectionCard — expandable section used in Emergency + Metrics tab
// ═════════════════════════════════════════════════════════════════════════════

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
      decoration: AppDecorations.tintedCard(),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.cardPadding),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: AppDecorations.iconRounded(
                        bg:     widget.iconColor.withValues(alpha: 0.10),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(widget.icon,
                        size: AppSpacing.iconSm, color: widget.iconColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(widget.title,
                      style: AppTypography.subheading(size: 14))),
                  AnimatedRotation(
                    turns:    _open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size:  AppSpacing.iconSm),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild:  const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                children: [
                  const Divider(height: 1, thickness: 1, color: AppColors.divider),
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

// ═════════════════════════════════════════════════════════════════════════════
// Content sections
// ═════════════════════════════════════════════════════════════════════════════


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

class _EmergencyQualitySection extends StatelessWidget {
  final SessionDetail? detail;
  final int            compressionCount;
  final String         targetDepthLabel;
  final double         targetDepthMin;
  final double         targetDepthMax;
  final double         averageDepth;
  final double         averageFrequency;
  final int            correctRecoil;

  const _EmergencyQualitySection({
    required this.detail,
    required this.compressionCount,
    required this.targetDepthLabel,
    required this.targetDepthMin,
    required this.targetDepthMax,
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
          value: averageDepth > 0 ? '${averageDepth.toStringAsFixed(1)} cm' : '—',
          note:  'Target: $targetDepthLabel',
          valueColor: averageDepth >= targetDepthMin && averageDepth <= targetDepthMax
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:  Icons.speed_rounded,
          label: 'Average Rate',
          value: averageFrequency > 0 ? '${averageFrequency.round()} BPM' : '—',
          note:  'Target: 100–120 BPM',
          valueColor: averageFrequency >= CprTargets.rateMin &&
              averageFrequency <= CprTargets.rateMax
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:       Icons.touch_app_outlined,
          label:      'Chest Compression Fraction',
          value:      detail?.handsOnPct ?? '—',
          note:       'Target ≥ 80% (AHA/ERC 2020)',
          valueColor: (detail?.handsOnRatio ?? 0) >= 0.80
              ? AppColors.success : AppColors.warning,
        ),
        _DetailRow(
          icon:  Icons.sync_rounded,
          label: 'Full Recoil',
          value: compressionCount > 0
              ? '${(correctRecoil / compressionCount * 100).round()}%' : '—',
          note:  'Compressions with complete decompression',
          valueColor: compressionCount > 0 &&
              (correctRecoil / compressionCount) >= 0.80
              ? AppColors.success : AppColors.warning,
        ),
        if ((detail?.noFlowTime ?? 0) > 0)
          _DetailRow(
            icon:       Icons.pause_circle_outline_rounded,
            label:      'No-Flow Time',
            value:      '${detail!.noFlowTime.toStringAsFixed(1)}s',
            note:       'Unplanned pauses > 2 s',
            valueColor: detail!.noFlowTime > 5
                ? AppColors.warning : AppColors.success,
          ),
        if ((detail?.leaningCount ?? 0) > 0)
          _DetailRow(
            icon:       Icons.warning_amber_rounded,
            label:      'Leaning Events',
            value:      '${detail!.leaningCount}×',
            note:       'Incomplete decompression',
            iconColor:  AppColors.warning,
            valueColor: AppColors.warning,
          ),
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
            note:      'Fingertip sensor',
            iconColor: AppColors.error,
          ),
        if (detail?.ambientTempStart != null)
          _DetailRow(
            icon:      Icons.thermostat_rounded,
            label:     'Room Temperature',
            value:     '${detail!.ambientTempStart!.toStringAsFixed(1)}°C',
            note:      'Ambient at session start',
            iconColor: AppColors.textSecondary,
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _PersonalBestComparison — gamified banner
// ═════════════════════════════════════════════════════════════════════════════

class _PersonalBestComparison extends ConsumerWidget {
  final double currentGrade;
  final String   scenario;
  final DateTime? sessionStart;

  const _PersonalBestComparison({
    required this.currentGrade,
    required this.scenario,
    this.sessionStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(sessionSummariesProvider);
    return summaries.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
        data: (sessions) {
          final training = sessions
              .where((s) => s.isTraining && s.totalGrade > 0)
              .where((s) => sessionStart == null ||
              s.sessionStart?.millisecondsSinceEpoch != sessionStart!.millisecondsSinceEpoch)
              .toList();

          if (training.isEmpty) {
            return _PBBanner(isNewBest: true, currentGrade: currentGrade, bestGrade: currentGrade, diff: 0);
          }
          final best = training.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);
          final isNewBest = currentGrade > 0 && currentGrade >= best;
          return _PBBanner(
            isNewBest:    isNewBest,
            currentGrade: currentGrade,
            bestGrade:    best,
            diff:         currentGrade - best,
          );
        },
    );
  }
}

class _PBBanner extends StatefulWidget {
  final bool   isNewBest;
  final double currentGrade;
  final double bestGrade;
  final double diff;

  const _PBBanner({
    required this.isNewBest,
    required this.currentGrade,
    required this.bestGrade,
    required this.diff,
  });

  @override
  State<_PBBanner> createState() => _PBBannerState();
}

class _PBBannerState extends State<_PBBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;
  late final Animation<double>   _fade;
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    if (widget.isNewBest) {
      // Small delay so the grade card settles first
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _ctrl.forward();
          _confetti.play();
        }
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _confetti.dispose();
    super.dispose();
  }

  Widget build(BuildContext context) {
    if (!widget.isNewBest) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            alignment: Alignment.center,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.pbGoldDark, AppColors.pbGoldLight, AppColors.pbGoldDark],
                  stops: [0.0, 0.5, 1.0],
                ),
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.pbGoldLight.withValues(alpha: 0.40),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'NEW PERSONAL BEST',
                    style: AppTypography.poppins(
                      size: 13,
                      weight: FontWeight.w800,
                      color: AppColors.pbGoldText,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Text('🏆', style: TextStyle(fontSize: 18)),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            numberOfParticles: 18,
            gravity: 0.3,
            colors: const [
              AppColors.pbGoldLight,
              AppColors.pbGoldDark,
              AppColors.feedbackGood,
              AppColors.feedbackInfo,
              AppColors.primary,
            ],
            shouldLoop: false,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// _GraphCard — fl_chart line graph
// ═════════════════════════════════════════════════════════════════════════════

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
  final bool           invertTarget;
  final bool           showTargetBand;
  final double?        referenceLineY;
  final List<FlSpot>?  spots2;
  final Color?         lineColor2;

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
    this.invertTarget   = false,
    this.showTargetBand = true,
    this.referenceLineY,
    this.spots2,
    this.lineColor2,
  });

  double _niceInterval(double maxX) {
    if (maxX <= 30)  return 10;
    if (maxX <= 60)  return 15;
    if (maxX <= 120) return 30;
    return 60;
  }

  @override
  Widget build(BuildContext context) {
    final maxX     = spots.isEmpty ? 60.0 : spots.last.x;
    final interval = _niceInterval(maxX);

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: maxX,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.divider,
              strokeWidth: AppSpacing.dividerThickness,
            ),
          ),
          borderData: FlBorderData(show: false),
          rangeAnnotations: RangeAnnotations(
            horizontalRangeAnnotations: [
              if (showTargetBand)
                HorizontalRangeAnnotation(
                  y1:    invertTarget ? minY      : targetMin,
                  y2:    invertTarget ? targetMax : targetMax,
                  color: AppColors.success.withValues(alpha: 0.08),
                ),
            ],
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (showTargetBand) ...[
                HorizontalLine(
                  y:           targetMin,
                  color:       AppColors.success.withValues(alpha: 0.4),
                  strokeWidth: AppSpacing.dividerThickness,
                  dashArray:   [4, 4],
                ),
                HorizontalLine(
                  y:           targetMax,
                  color:       AppColors.success.withValues(alpha: 0.4),
                  strokeWidth: AppSpacing.dividerThickness,
                  dashArray:   [4, 4],
                ),
              ],
              if (referenceLineY != null)
                HorizontalLine(
                  y:           referenceLineY!,
                  color:       AppColors.warning.withValues(alpha: 0.5),
                  strokeWidth: AppSpacing.dividerThickness,
                  dashArray:   [6, 4],
                  label: HorizontalLineLabel(
                    show:          true,
                    alignment:     Alignment.topRight,
                    labelResolver: (_) => 'High effort',
                    style: AppTypography.caption(color: AppColors.warning),
                  ),
                ),
            ],
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 28,
                interval:     (maxY - minY) / (leftLabelValues.length - 1),
                getTitlesWidget: (value, _) {
                  final idx = leftLabelValues.indexWhere(
                          (v) => (v - value).abs() < 0.6);
                  if (idx < 0) return const SizedBox.shrink();
                  return Text(leftLabels[idx],
                      style: AppTypography.caption(
                          color: AppColors.textDisabled));
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 18,
                interval:     interval,
                getTitlesWidget: (value, _) {
                  final secs = value.toInt();
                  final mm   = (secs ~/ 60).toString();
                  final ss   = (secs % 60).toString().padLeft(2, '0');
                  return Text('$mm:$ss',
                      style: AppTypography.caption(
                          color: AppColors.textDisabled));
                },
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots:           spots,
              isCurved:        true,
              curveSmoothness: 0.3,
              color:           lineColor,
              barWidth:        2,
              dotData:         const FlDotData(show: false),
              belowBarData: BarAreaData(
                show:  true,
                color: lineColor.withValues(alpha: 0.06),
              ),
            ),
            if (spots2 != null && spots2!.isNotEmpty)
              LineChartBarData(
                spots:           spots2!,
                isCurved:        true,
                curveSmoothness: 0.3,
                color:           lineColor2 ?? lineColor.withValues(alpha: 0.35),
                barWidth:        1.5,
                dotData:         const FlDotData(show: false),
                dashArray:       [4, 4],
                belowBarData:    BarAreaData(show: false),
              ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final secs = s.x.toInt();
                final mm   = (secs ~/ 60).toString();
                final ss   = (secs % 60).toString().padLeft(2, '0');
                return LineTooltipItem(
                  '${s.y.toStringAsFixed(1)} $unit\n$mm:$ss',
                  AppTypography.caption(color: AppColors.textOnDark),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared small widgets
// ═════════════════════════════════════════════════════════════════════════════

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
                    size: 18, color: AppColors.textOnDark)),
            const SizedBox(height: AppSpacing.xxs),
            Text(label,
                style: AppTypography.badge(
                    size: 8,
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
                  size: 14,
                  color: valueColor ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

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
    return GestureDetector(
      onTap: canEdit ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: AppDecorations.tintedCard(),
        child: Row(
          children: [
            Icon(
              note != null ? Icons.sticky_note_2_outlined : Icons.add_comment_outlined,
              color: AppColors.primary,
              size:  AppSpacing.iconSm,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                note ?? 'Add a session note…',
                style: note != null
                    ? AppTypography.body(size: 13, color: AppColors.textPrimary)
                    : AppTypography.body(size: 13, color: AppColors.textDisabled),
              ),
            ),
            if (canEdit)
              const Icon(Icons.edit_outlined,
                  color: AppColors.textDisabled, size: AppSpacing.iconSm),
          ],
        ),
      ),
    );
  }
}

class _UnsyncedBanner extends StatelessWidget {
  final bool isLoggedIn;
  const _UnsyncedBanner({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadius),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: AppSpacing.iconSm, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isLoggedIn
                  ? 'Saved locally. Will sync when back online.'
                  : 'Saved locally. Log in to sync this session.',
              style: AppTypography.caption(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveSessionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.primaryCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Save this session',
              style: AppTypography.subheading(size: 13)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This session was conducted without an account. Sign in to save it permanently.',
            style: AppTypography.caption(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnDark,
                shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(AppSpacing.buttonRadius)),
              ),
// _SaveSessionBanner
              onPressed: () => context.push(const LoginScreen()),
              child: Text('Log In / Sign Up',
                  style: AppTypography.buttonPrimary()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final VoidCallback onTap;
  final String       label;
  const _ExportButton({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon:  const Icon(Icons.upload_file_outlined,
            size: AppSpacing.iconSm, color: AppColors.primary),
        label: Text(label, style: AppTypography.buttonSecondary()),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _PastSessionsButton extends StatelessWidget {
  const _PastSessionsButton();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      // _PastSessionsButton
      onPressed: () => context.push(const SessionHistoryScreen()),
      child: Text('View All Sessions →',
          style: AppTypography.buttonSecondary()),
    );
  }
}