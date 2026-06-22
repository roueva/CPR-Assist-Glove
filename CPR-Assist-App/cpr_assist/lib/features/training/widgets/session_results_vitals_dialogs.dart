part of 'session_results.dart';

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

  static void show(
      BuildContext context, {
        required int                        score,
        required String                     label,
        required Color                      color,
        required List<RescuerVitalSnapshot> vitals,
        required List<CompressionEvent>     compressions,
        required int                        onset,
      }) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _FatigueDetailDialog(
        score:        score,
        label:        label,
        color:        color,
        vitals:       vitals,
        compressions: compressions,
        onset:        onset,
      ),
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
      backgroundColor: AppColors.transparent,
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
                    onPressed: () => context.pop(),
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
                      decoration: AppDecorations.infoBox(),
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
              onPressed: () => context.pop(),
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
  final bool                       isEmergency;

  const _HeartRateDetailDialog({
    required this.hr,
    required this.hrSub,
    required this.hrColor,
    required this.vitals,
    this.isEmergency = false,
  });

  static void show(BuildContext context, {
    required double hr,
    required String hrSub,
    required Color  hrColor,
    required List<RescuerVitalSnapshot> vitals,
    bool isEmergency = false,
  }) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _HeartRateDetailDialog(
        hr:          hr,
        hrSub:       hrSub,
        hrColor:     hrColor,
        vitals:      vitals,
        isEmergency: isEmergency,
      ),
    );
  }
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
      backgroundColor: AppColors.transparent,
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
                    onPressed: () => context.pop(),
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
                      decoration: AppDecorations.greyInfoBox(),
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
                        decoration: AppDecorations.greyInfoBox(),
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
                        decoration: AppDecorations.greyInfoBox(),
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

                    if (!isEmergency) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'See the Charts tab for your heart rate trend over the full session.',
                        style: AppTypography.caption(
                            color: AppColors.textDisabled),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            TextButton(
              onPressed: () => context.pop(),
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

  static void show(BuildContext context, {
    required double spo2,
    required String spo2Sub,
    required Color  spo2Color,
  }) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _SpO2DetailDialog(
        spo2:      spo2,
        spo2Sub:   spo2Sub,
        spo2Color: spo2Color,
      ),
    );
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
      Expanded(child: Text(text,
          style: AppTypography.subheading(size: 12))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.transparent,
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
                    onPressed: () => context.pop(),
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
                      decoration: AppDecorations.greyInfoBox(),
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
              onPressed: () => context.pop(),
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

  static void show(BuildContext context, {
    required double temp,
    required String tempSub,
    required Color  tempColor,
    required List<RescuerVitalSnapshot> vitals,
  }) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _WristTempDetailDialog(
        temp:      temp,
        tempSub:   tempSub,
        tempColor: tempColor,
        vitals:    vitals,
      ),
    );
  }

  double? get _firstTemp {
    final v = vitals.where((s) => s.temperature > 0);
    return v.isEmpty ? null : v.first.temperature;
  }

  double? get _lastTemp {
    final v = vitals.where((s) => s.temperature > 0);
    return v.isEmpty ? null : v.last.temperature;
  }

  @override
  Widget build(BuildContext context) {
    final first     = _firstTemp;
    final last      = _lastTemp;
    final heroVal   = (last ?? temp).toStringAsFixed(1);
    final hasTrend  = first != null && last != null && (last - first).abs() >= 0.1;
    final diff      = hasTrend ? last! - first! : 0.0;
    final diffColor = diff > 0.5 ? AppColors.warning : AppColors.success;

    return Dialog(
      backgroundColor: AppColors.transparent,
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
                    onPressed: () => context.pop(),
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
                      decoration: AppDecorations.greyInfoBox(),
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
              onPressed: () => context.pop(),
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
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
      decoration: AppDecorations.greyInfoBox(),
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
    return _EmptyState(
      icon:  Icons.bar_chart_rounded,
      title: 'Detailed metrics not available',
      body:  'Full metrics are only available for sessions loaded '
          'from the glove.\nHistory sessions show summary data only.',
    );
  }
}
