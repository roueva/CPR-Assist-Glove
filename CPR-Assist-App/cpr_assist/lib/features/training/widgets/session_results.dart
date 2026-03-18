import 'package:cpr_assist/features/training/widgets/session_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/session_provider.dart';
import '../screens/session_service.dart';
import '../services/compression_event.dart';
import '../services/session_detail.dart';

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

  @override
  void initState() {
    super.initState();
    _note = widget._detail?.note ?? widget._summary?.note;
  }

  // ── Mode helpers ───────────────────────────────────────────────────────────
  bool get _isEmergency =>
      (widget._detail?.isEmergency ?? widget._summary?.isEmergency) ?? true;

  String get _scenario =>
      widget._detail?.scenario ?? widget._summary?.scenario ?? 'standard_adult';

  bool get _isPediatric => _scenario == 'pediatric';

  double get _targetDepthMin => _isPediatric
      ? CprTargets.depthMinPediatric
      : CprTargets.depthMin;
  double get _targetDepthMax => _isPediatric
      ? CprTargets.depthMaxPediatric
      : CprTargets.depthMax;
  String get _targetDepthLabel =>
      '${_targetDepthMin.toStringAsFixed(0)}–${_targetDepthMax.toStringAsFixed(0)} cm';

  // ── Derived helpers ────────────────────────────────────────────────────────
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

  int get _depthRateCombo =>
      widget._detail?.depthRateCombo ?? widget._summary?.depthRateCombo ?? 0;

  // Rescuer biometrics — use new field names only
  double? get _rescuerHR   =>
      widget._detail?.rescuerHRLastPause   ?? widget._summary?.rescuerHRLastPause;
  double? get _rescuerSpO2 =>
      widget._detail?.rescuerSpO2LastPause ?? widget._summary?.rescuerSpO2LastPause;

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

  // ── Note editing ───────────────────────────────────────────────────────────
  Future<void> _editNote() async {
    final controller = TextEditingController(text: _note ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _NoteDialog(controller: controller),
    );
    if (result == null) return;

    final sessionId = widget._detail?.id ?? widget._summary?.id;
    if (sessionId != null) {
      final service = ref.read(sessionServiceProvider);
      await service.updateNote(sessionId, result.isEmpty ? null : result);
    }
    setState(() => _note = result.isEmpty ? null : result);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasGraphs   = widget._detail != null &&
        widget._detail!.compressions.isNotEmpty;
    final canEditNote = (widget._detail?.id ?? widget._summary?.id) != null;
    final title       = widget._sessionNumber != null
        ? 'Session ${widget._sessionNumber}'
        : _isEmergency ? 'Emergency Session' : 'Session Results';

    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.primaryLight,
        elevation:              0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text(
          title,
          style: AppTypography.heading(size: 20, color: AppColors.primary),
        ),
        actions: [
          // Mode badge in app bar
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical:   AppSpacing.xxs,
                ),
                decoration: AppDecorations.chip(
                  color: _isEmergency ? AppColors.emergencyRed : AppColors.warning,
                  bg:    _isEmergency ? AppColors.emergencyBg  : AppColors.warningBg,
                ),
                child: Text(
                  _isEmergency ? 'EMERGENCY' : 'TRAINING',
                  style: AppTypography.badge(
                    size:  10,
                    color: _isEmergency ? AppColors.emergencyRed : AppColors.warning,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── ① Gradient header ─────────────────────────────────────────
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryAlt],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xl,
              ),
              child: Column(
                children: [
                  // Grade circle — Training only
                  if (!_isEmergency) ...[
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width:  148,
                          height: 148,
                          child: CircularProgressIndicator(
                            value:           _grade / 100,
                            strokeWidth:     10,
                            strokeCap:       StrokeCap.round,
                            backgroundColor: AppColors.textOnDark.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AppColors.textOnDark,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_grade.toStringAsFixed(0)}%',
                              style: AppTypography.numericDisplay(
                                size: 38, color: AppColors.textOnDark,
                              ),
                            ),
                            Text(
                              _motivationalLabel,
                              style: AppTypography.label(
                                size:  11,
                                color: AppColors.textOnDark.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Emergency header — icon instead of grade circle
                  if (_isEmergency) ...[
                    Container(
                      width:  80,
                      height: 80,
                      decoration: BoxDecoration(
                        color:  AppColors.textOnDark.withValues(alpha: 0.15),
                        shape:  BoxShape.circle,
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
                        size:   20,
                        weight: FontWeight.w700,
                        color:  AppColors.textOnDark,
                      ),
                    ),
                    if (_isPediatric) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs,
                        ),
                        decoration: AppDecorations.chip(
                          color: AppColors.textOnDark,
                          bg:    AppColors.textOnDark.withValues(alpha: 0.2),
                        ),
                        child: Text(
                          'PEDIATRIC CPR',
                          style: AppTypography.badge(
                            size: 10, color: AppColors.textOnDark,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // ── Summary row ──────────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color:        AppColors.textOnDark.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          _SummaryCell(value: _durationFormatted,       label: 'DURATION'),
                          _VDivider(),
                          _SummaryCell(value: '$_compressionCount',     label: 'COMPRESSIONS'),
                          _VDivider(),
                          _SummaryCell(
                            value: _averageFrequency > 0
                                ? '${_averageFrequency.round()}'
                                : '—',
                            label: 'AVG BPM',
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Quality breakdown — Training only ────────────────────
                  if (!_isEmergency) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QUALITY BREAKDOWN',
                          style: AppTypography.badge(
                            size:  10,
                            color: AppColors.textOnDark.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        GridView.count(
                          shrinkWrap:   true,
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing:  AppSpacing.sm,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.4,
                          children: [
                            _StatTile(label: 'CORRECT DEPTH',     value: _pct(_correctDepth)),
                            _StatTile(label: 'CORRECT FREQUENCY', value: _pct(_correctFrequency)),
                            _StatTile(label: 'CORRECT RECOIL',    value: _pct(_correctRecoil)),
                            _StatTile(label: 'DEPTH + RATE',      value: _pct(_depthRateCombo)),
                          ],
                        ),
                      ],
                    ),
                  ],

                  // ── Factual breakdown — Emergency only ───────────────────
                  if (_isEmergency) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSION OVERVIEW',
                          style: AppTypography.badge(
                            size:  10,
                            color: AppColors.textOnDark.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        GridView.count(
                          shrinkWrap:      true,
                          crossAxisCount:  2,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing:  AppSpacing.sm,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.4,
                          children: [
                            _StatTile(label: 'CORRECT DEPTH',  value: _pct(_correctDepth)),
                            _StatTile(label: 'CORRECT RATE',   value: _pct(_correctFrequency)),
                            _StatTile(label: 'CORRECT RECOIL', value: _pct(_correctRecoil)),
                            _StatTile(
                              label: 'SCENARIO',
                              value: _isPediatric ? 'Pediatric' : 'Adult',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── ② White body ──────────────────────────────────────────────
            Container(
              width:   double.infinity,
              color:   AppColors.surfaceWhite,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Graphs (detail mode only) ────────────────────────────
                  if (hasGraphs) ...[
                    Text(
                      'PERFORMANCE OVER TIME',
                      style: AppTypography.badge(
                        size:  10, color: AppColors.textDisabled,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _SessionGraphs(
                      session:        widget._detail!,
                      targetDepthMin: _targetDepthMin,
                      targetDepthMax: _targetDepthMax,
                    ),
                    const _HDivider(),
                  ],

                  // ── Metrics ──────────────────────────────────────────────
                  Text(
                    'METRICS',
                    style: AppTypography.badge(
                      size: 10, color: AppColors.textDisabled,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  _DetailRow(
                    icon:  Icons.compress_rounded,
                    label: 'Average Depth',
                    value: _averageDepth > 0
                        ? '${_averageDepth.toStringAsFixed(1)} cm'
                        : '—',
                    note: 'Target: $_targetDepthLabel',
                  ),

                  if (widget._detail != null) ...[
                    _DetailRow(
                      icon:  Icons.straighten_rounded,
                      label: 'Depth Consistency',
                      value: widget._detail!.depthConsistency > 0
                          ? '${widget._detail!.depthConsistency.round()}%'
                          : '—',
                      note: 'Compressions within $_targetDepthLabel',
                    ),
                    _DetailRow(
                      icon:  Icons.speed_rounded,
                      label: 'Rate Consistency',
                      value: widget._detail!.frequencyConsistency > 0
                          ? '${widget._detail!.frequencyConsistency.round()}%'
                          : '—',
                      note: 'Compressions within 100–120 BPM',
                    ),
                    _DetailRow(
                      icon:  Icons.show_chart_rounded,
                      label: 'Depth Variability (SD)',
                      value: widget._detail!.depthSD > 0
                          ? '${widget._detail!.depthSD.toStringAsFixed(2)} cm'
                          : '—',
                      note: 'Lower is more consistent',
                    ),

                    const _HDivider(),

                    // ── Posture ──────────────────────────────────────────
                    Text(
                      'POSTURE',
                      style: AppTypography.badge(
                        size: 10, color: AppColors.textDisabled,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    _DetailRow(
                      icon:  Icons.accessibility_new_rounded,
                      label: 'Correct Posture',
                      value: _compressionCount > 0
                          ? '${(widget._detail!.correctPosture / _compressionCount * 100).round()}%'
                          : '—',
                      note: 'Wrist alignment within 15°',
                    ),
                    if (widget._detail!.leaningCount > 0)
                      _DetailRow(
                        icon:       Icons.warning_amber_rounded,
                        label:      'Leaning Detected',
                        value:      '${widget._detail!.leaningCount}×',
                        note:       'Incomplete decompression between compressions',
                        iconColor:  AppColors.warning,
                        valueColor: AppColors.warning,
                      ),
                    if (widget._detail!.overForceCount > 0)
                      _DetailRow(
                        icon:       Icons.fitness_center_rounded,
                        label:      'Over-Force Events',
                        value:      '${widget._detail!.overForceCount}×',
                        note:       'Force exceeded safe threshold',
                        iconColor:  AppColors.error,
                        valueColor: AppColors.error,
                      ),

                    const _HDivider(),

                    // ── Flow ─────────────────────────────────────────────
                    Text(
                      'FLOW',
                      style: AppTypography.badge(
                        size: 10, color: AppColors.textDisabled,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    _DetailRow(
                      icon:       Icons.touch_app_outlined,
                      label:      'Hands-On Time',
                      value:      widget._detail!.handsOnPct,
                      note:       'Time actively compressing',
                      valueColor: _flowColor(widget._detail!.handsOnRatio * 100),
                    ),
                    _DetailRow(
                      icon:       Icons.pause_circle_outline_rounded,
                      label:      'No-Flow Time',
                      value:      widget._detail!.noFlowTime > 0
                          ? '${widget._detail!.noFlowTime.toStringAsFixed(1)}s'
                          : '0s',
                      note:       '${widget._detail!.noFlowIntervals} unplanned pause(s) > 2 s',
                      valueColor: widget._detail!.noFlowTime > 5
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    _DetailRow(
                      icon:       Icons.timer_outlined,
                      label:      'Time to First Compression',
                      value:      widget._detail!.timeToFirstCompression > 0
                          ? '${widget._detail!.timeToFirstCompression.toStringAsFixed(1)}s'
                          : '—',
                      note:       'From session start to first compression',
                      valueColor: widget._detail!.timeToFirstCompression > 5
                          ? AppColors.warning
                          : AppColors.success,
                    ),

                    // ── Fatigue (Training only) ───────────────────────────
                    if (!_isEmergency &&
                        widget._detail!.rescuerSwapCount > 0) ...[
                      const _HDivider(),
                      Text(
                        'FATIGUE & ENDURANCE',
                        style: AppTypography.badge(
                          size: 10, color: AppColors.textDisabled,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _DetailRow(
                        icon:  Icons.swap_horiz_rounded,
                        label: 'Rescuer Swap Prompts',
                        value: '${widget._detail!.rescuerSwapCount}×',
                        note:  'Times 2-minute alert fired',
                      ),
                      if (widget._detail!.fatigueOnsetIndex > 0)
                        _DetailRow(
                          icon:       Icons.trending_down_rounded,
                          label:      'Fatigue Onset',
                          value:      'Compression #${widget._detail!.fatigueOnsetIndex}',
                          note:       'When physiological fatigue was first detected',
                          iconColor:  AppColors.warning,
                          valueColor: AppColors.warning,
                        ),
                    ],

                    // ── Pulse check results (Emergency only) ─────────────
                    if (_isEmergency &&
                        widget._detail!.pulseChecks.isNotEmpty) ...[
                      const _HDivider(),
                      Text(
                        'PULSE CHECKS',
                        style: AppTypography.badge(
                          size: 10, color: AppColors.textDisabled,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _DetailRow(
                        icon:  Icons.sensors_rounded,
                        label: 'Checks Prompted',
                        value: '${widget._detail!.pulseChecksPrompted}',
                      ),
                      _DetailRow(
                        icon:  Icons.check_circle_outline_rounded,
                        label: 'Checks Completed',
                        value: '${widget._detail!.pulseChecksComplied}',
                      ),
                      ...widget._detail!.pulseChecks.map((pc) {
                        final color = pc.detected
                            ? AppColors.success
                            : pc.isUncertain
                            ? AppColors.warning
                            : AppColors.textSecondary;
                        final label = pc.detected
                            ? 'Pulse Present'
                            : pc.isUncertain
                            ? 'Uncertain'
                            : 'No Pulse';
                        return _DetailRow(
                          icon:       Icons.favorite_border_rounded,
                          label:      'Check #${pc.intervalNumber}',
                          value:      label,
                          note:       pc.detectedBpm > 0
                              ? '${pc.detectedBpm.toStringAsFixed(0)} BPM  ·  ${pc.confidence}% confidence'
                              : null,
                          iconColor:  color,
                          valueColor: color,
                        );
                      }),
                    ],
                  ],

                  // ── Biometrics ────────────────────────────────────────────
                  if (_hasBiometrics) ...[
                    const _HDivider(),
                    Text(
                      'RESCUER BIOMETRICS',
                      style: AppTypography.badge(
                        size: 10, color: AppColors.textDisabled,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (_rescuerHR != null)
                      _DetailRow(
                        icon:      Icons.monitor_heart_outlined,
                        label:     'Heart Rate (last pause)',
                        value:     '${_rescuerHR!.toStringAsFixed(0)} bpm',
                        iconColor: AppColors.primary,
                      ),
                    if (_rescuerSpO2 != null)
                      _DetailRow(
                        icon:  Icons.air_rounded,
                        label: 'SpO₂ (last pause)',
                        value: '${_rescuerSpO2!.toStringAsFixed(0)}%',
                      ),
                  ],

                  // ── Session date ─────────────────────────────────────────
                  const _HDivider(),
                  _DetailRow(
                    icon:  Icons.calendar_today_outlined,
                    label: 'Session Date',
                    value: _dateTimeFormatted,
                  ),

                  // ── Note ─────────────────────────────────────────────────
                  const SizedBox(height: AppSpacing.sm),
                  _NoteCard(
                    note:    _note,
                    canEdit: canEditNote,
                    onTap:   _editNote,
                  ),

                  const SizedBox(height: AppSpacing.md),
                  const _PastSessionsButton(),
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
// _SessionGraphs — depth + rate graphs, scenario-aware target bands
// ─────────────────────────────────────────────────────────────────────────────

class _SessionGraphs extends StatelessWidget {
  final SessionDetail session;
  final double        targetDepthMin;
  final double        targetDepthMax;

  const _SessionGraphs({
    required this.session,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context) {
    final events = session.compressions;
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GraphCard(
          title:      'Compression Depth',
          unit:       'cm',
          minY:       0,
          maxY:       9,
          targetMin:  targetDepthMin,
          targetMax:  targetDepthMax,
          // Use instantaneousRate for Y but depth for X — depth graph
          spots: events
              .map((e) => FlSpot(e.timestampSec, e.depth))
              .toList(),
          lineColor:       AppColors.primary,
          leftLabels:      const ['0', '3', '6', '9'],
          leftLabelValues: const [0, 3, 6, 9],
          targetLabel:     '${targetDepthMin.toStringAsFixed(0)}–${targetDepthMax.toStringAsFixed(0)} cm',
        ),
        const SizedBox(height: AppSpacing.md),
        _GraphCard(
          title:     'Compression Rate',
          unit:      'BPM',
          minY:      60,
          maxY:      160,
          targetMin: CprTargets.rateMin,
          targetMax: CprTargets.rateMax,
          // Use instantaneousRate — per-compression accuracy per spec v3.0
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
        ),
      ],
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
            _TargetLine(
                color: lineColor,
                label: '${targetMin.toStringAsFixed(0)} $unit'),
            const Spacer(),
            _TargetLine(
                color: lineColor,
                label: '${targetMax.toStringAsFixed(0)} $unit'),
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

class _NoteDialog extends StatelessWidget {
  final TextEditingController controller;
  const _NoteDialog({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Session Note', style: AppTypography.heading(size: 18)),
      content: TextField(
        controller:  controller,
        maxLines:    5,
        autofocus:   true,
        decoration: InputDecoration(
          hintText:  'What did you notice?',
          hintStyle: AppTypography.caption(color: AppColors.textDisabled),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: context.pop,
          child: Text('Cancel',
              style: AppTypography.label(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text('Save',
              style: AppTypography.label(color: AppColors.primary)),
        ),
      ],
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
                  Text('View all your training history',
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
      decoration: BoxDecoration(
        color:        AppColors.textOnDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// gradeColor — shared utility used by SessionCard in session_history.dart
// ─────────────────────────────────────────────────────────────────────────────

Color gradeColor(double grade) {
  if (grade >= 90) return AppColors.success;
  if (grade >= 75) return AppColors.primary;
  if (grade >= 55) return AppColors.warning;
  return AppColors.error;
}