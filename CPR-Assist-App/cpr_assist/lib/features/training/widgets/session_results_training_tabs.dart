part of 'session_results.dart';


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
  final double targetDepthMin;
  final double targetDepthMax;

  const _TrainingOverviewTab({
    required this.detail,
    required this.summary,
    required this.note,
    required this.canEditNote,
    required this.onEditNote,
    required this.scenario,
    required this.currentGrade,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = detail;
    final s = summary;

    final compressions    = d?.compressionCount ?? s?.compressionCount ?? 0;
    final duration        = d?.durationFormatted ?? s?.durationFormatted ?? '—';
    final pauseCount      = d?.unplannedPauseCount ?? 0;
    final pauseTime       = d?.unplannedPauseTime  ?? 0.0;
    final noFlowSecs      = d?.noFlowTime  ?? 0.0;
    final ttf             = d?.timeToFirstCompression ?? 0.0;

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
            unplannedTime:   pauseTime,
            unplannedCount:  pauseCount,
            noFlowSecs:      noFlowSecs,
            ttf:             ttf,
            detail:          d,
            summary:         s,
            targetDepthMin: targetDepthMin,
            targetDepthMax: targetDepthMax,
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
  final double  unplannedTime;
  final int     unplannedCount;
  final double  noFlowSecs;
  final double  ttf;
  final SessionDetail?  detail;
  final SessionSummary? summary;
  final double targetDepthMin;
  final double targetDepthMax;


  const _OverviewGrid({
    required this.compressions,
    required this.unplannedTime,
    required this.unplannedCount,
    required this.noFlowSecs,
    required this.ttf,
    required this.detail,
    required this.summary,
    this.targetDepthMin = 5.0,
    this.targetDepthMax = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    final avgDepth = detail?.averageDepth    ?? summary?.averageDepth    ?? 0.0;
    final avgFreq  = detail?.averageFrequency ?? summary?.averageFrequency ?? 0.0;

    final depthOk    = avgDepth >= targetDepthMin && avgDepth <= targetDepthMax;
    final depthHigh  = avgDepth > targetDepthMax;
    final rateOk     = avgFreq >= 100 && avgFreq <= 120;
    final ttfColor = ttf <= 0 ? AppColors.textDisabled
        : ttf <= 10 ? AppColors.success
        : ttf <= 20 ? AppColors.warning
        : AppColors.error;

    final tiles = [
      _GridStatTile(
        label:       'Avg Depth',
        value:       avgDepth > 0 ? '${avgDepth.toStringAsFixed(1)} cm' : '—',
        dotColor:    depthOk ? AppColors.success
            : depthHigh ? AppColors.error : AppColors.warning,
        zoneBar: avgDepth > 0 ? _ZoneBarConfig(
          minVal: 0, maxVal: 8,
          targetMin: targetDepthMin, targetMax: targetDepthMax,
          currentVal: avgDepth,
          dotColor: depthOk ? AppColors.success
              : depthHigh ? AppColors.error : AppColors.warning,
          targetLabel: '${targetDepthMin.toStringAsFixed(0)}–${targetDepthMax.toStringAsFixed(0)} cm',
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
        label:    'Time to 1st Comp',
        value:    ttf > 0 ? '${ttf.toStringAsFixed(1)} s' : '—',
        dotColor: ttfColor,
        zoneBar: ttf > 0 ? _ZoneBarConfig(
          minVal: 0, maxVal: 30,
          targetMin: 0, targetMax: 10,
          currentVal: ttf.clamp(0.0, 30.0),
          dotColor: ttfColor,
          targetLabel: '< 10 s',
        ) : null,
      ),
      _GridStatTile(
        label:    'Unplanned Pauses',
        value:    unplannedTime > 0 ? '${unplannedTime.toStringAsFixed(1)}s' : '0s',
        note:     unplannedCount > 0
            ? '$unplannedCount× · no-flow ${noFlowSecs.toStringAsFixed(0)}s'
            : (noFlowSecs > 0
            ? 'no-flow ${noFlowSecs.toStringAsFixed(0)}s' : null),
        dotColor: unplannedTime <= AppConstants.maxAcceptablePauseSec
            ? AppColors.success : AppColors.warning,
        zoneBar: _ZoneBarConfig(
          minVal: 0, maxVal: 15,
          targetMin: 0, targetMax: AppConstants.maxAcceptablePauseSec,
          currentVal: unplannedTime.clamp(0.0, 15.0),
          dotColor: unplannedTime <= AppConstants.maxAcceptablePauseSec
              ? AppColors.success : AppColors.warning,
          targetLabel: '< ${AppConstants.maxAcceptablePauseSec.toStringAsFixed(0)}s',
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
      decoration: AppDecorations.gradeCard(),
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
            // Numeric value — never clipped. Sub-pixel rounding sometimes
            // pushes this row 0.5–1 px over its parent's 140px constraint;
            // wrapping the secondary `note` in Flexible lets it shrink (and
            // ellipsize) rather than overflowing the whole Row.
            Text(value,
                style: AppTypography.numericDisplay(
                    size: 19, color: AppColors.textPrimary)),
            if (note != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                        color: AppColors.textDisabled)),
              ),
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
        || d.rescuerWristTempStart != null
        || d.rescuerVitals.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Card 1: Compression Quality ────────────────────────────────
          _ExpandableSectionCard(
            icon:      Icons.favorite_rounded,
            iconColor: AppColors.primary,
            title:     'Compression Quality',
            subtitle:  '${d.compressionCount} compressions · ${d.durationFormatted}',
            startOpen: true,
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
          _ExpandableSectionCard(
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
            _ExpandableSectionCard(
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
      backgroundColor: AppColors.transparent,
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
                    onPressed: () => context.pop(),
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
              onPressed: () => context.pop(),
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
  final bool          isEmergency;
  const _SessionTimelineSection({
    required this.detail,
    this.isEmergency = false,
  });

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

    // Mirror _calculatePauseMetrics exactly (single source of truth): scan the
    // leading gap, every inter-compression gap, and the trailing gap. A fully
    // unplanned gap → one "Unplanned pause" event. A planned gap that overran
    // → the excess shows as its own "Unplanned pause" event (Behavior Y), so
    // the timeline can never disagree with the stat chips.
    void scanTimelineGap(double gapStart, double gapEnd) {
      final gap = gapEnd - gapStart;
      if (gap <= 2.0) return;
      const tol = AppConstants.plannedWindowAssocToleranceSec;
      final isPlanned = detail.ventilations.any((v) =>
      v.timestampSec >= gapStart - tol &&
          v.timestampSec <= gapEnd) ||
          detail.pulseChecks.any((p) =>
          p.timestampSec >= gapStart - tol &&
              p.timestampSec <= gapEnd);
      if (!isPlanned) {
        events.add(_TLEvent(
          sortKey:  gapStart,
          time:     _fmt(gapStart),
          title:    'Unplanned pause',
          subtitle: '${gap.toStringAsFixed(1)} s with no compressions',
          dotColor: AppColors.error,
          icon:     Icons.pause_circle_outline_rounded,
          tip:      'Keep pauses under ${AppConstants.maxAcceptablePauseSec.toStringAsFixed(0)} s',
        ));
      } else if (gap > AppConstants.maxAcceptablePauseSec) {
        final excess = gap - AppConstants.maxAcceptablePauseSec;
        events.add(_TLEvent(
          sortKey:  gapEnd - 0.001,
          time:     _fmt(gapStart + AppConstants.maxAcceptablePauseSec),
          title:    'Unplanned pause',
          subtitle: '${excess.toStringAsFixed(1)} s over the '
              '${AppConstants.maxAcceptablePauseSec.toStringAsFixed(0)} s allowance',
          dotColor: AppColors.error,
          icon:     Icons.pause_circle_outline_rounded,
          tip:      'Resume compressions within '
              '${AppConstants.maxAcceptablePauseSec.toStringAsFixed(0)} s of a ventilation or pulse check',
        ));
      }
    }

    if (detail.compressions.isNotEmpty) {
      scanTimelineGap(0.0, detail.compressions.first.timestampSec);
      for (int i = 1; i < detail.compressions.length; i++) {
        scanTimelineGap(
          detail.compressions[i - 1].timestampSec,
          detail.compressions[i].timestampSec,
        );
      }
      scanTimelineGap(
        detail.compressions.last.timestampSec,
        detail.sessionDuration.toDouble(),
      );
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
      // Compliant = rescuer actually paused >= 3 s for the check (same rule
      // as ventilation), not merely whether a UI button was tapped.
      final completed = p.compliant;

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
        dotColor:    completed ? dotColor : AppColors.textDisabled,
        icon:        !completed          ? Icons.monitor_heart_outlined
            : p.detected                 ? Icons.favorite_rounded
            : p.isUncertain              ? Icons.help_outline_rounded
            :                              Icons.heart_broken_rounded,
        isGrayedOut: !completed,
        isIgnored:   !completed,
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
          unplannedTime:      detail.unplannedPauseTime,
          unplannedCount:     detail.unplannedPauseCount,
          compliantVentCount: compliantVentCount,
          isEmergency:        isEmergency,
        ),
      ],
    );
  }
}

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
  final double unplannedTime;
  final int    unplannedCount;
  final int    compliantVentCount;
  final bool   isEmergency;

  const _TimelineStatGrid({
    required this.detail,
    required this.activeCprTime,
    required this.unplannedTime,
    required this.unplannedCount,
    required this.compliantVentCount,
    this.isEmergency = false,
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
      final completed = detail.pulseChecks.where((p) => p.compliant).length;
      final lastDetected = detail.pulseChecks.lastWhere(
            (p) => p.detected && p.detectedBpm > 0,
        orElse: () => detail.pulseChecks.first,
      );
      final hasDetection = lastDetected.detected && lastDetected.detectedBpm > 0;
      final complianceNote = '$completed/$total completed';
      pulseChip = _StatChip(
        Icons.monitor_heart_outlined,
        'Pulse checks',
        '$complianceNote',
        hasDetection ? AppColors.success : AppColors.textSecondary,
      );
    }

    // ── Colors ──────────────────────────────────────────────────────────────
    final pauseColor = (unplannedTime > AppConstants.maxAcceptablePauseSec ||
        unplannedCount > AppConstants.maxAcceptableUnplannedPauseCount)
        ? AppColors.warning : AppColors.success;
    final ventColor = compliantVentCount == detail.ventilations.length
        ? AppColors.primary : AppColors.warning;



    // ── Chip list ───────────────────────────────────────────────────────────
    final stats = <_StatChip>[
      _StatChip(Icons.timer_outlined,   'Total time',
          detail.durationFormatted,         AppColors.textSecondary),
      if (unplannedCount > 0 && !isEmergency)
        _StatChip(Icons.favorite_rounded, 'Active CPR',
            _fmtDuration(activeCprTime),    AppColors.primary),
      _StatChip(Icons.compress_rounded, 'Compressions',
          '${detail.compressionCount}',     AppColors.textPrimary),
      if (unplannedCount > 0)
        _StatChip(Icons.pause_rounded,  'Unplanned pauses',
            '${unplannedTime.toStringAsFixed(1)} s ($unplannedCount×)',
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
                        color: AppColors.textSecondary),
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
  final bool          isEmergency;


  const _RescuerVitalsSection({
    required this.rescuerHR,
    required this.rescuerSpO2,
    required this.detail,
    this.isEmergency = false,
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


  void _showFatigueDetail(BuildContext context) {
    _FatigueDetailDialog.show(
      context,
      score:        _fatigueScore,
      label:        _fatigueLabel,
      color:        _fatigueColor,
      vitals:       detail.rescuerVitals,
      compressions: detail.compressions,
      onset:        detail.fatigueOnsetIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onset  = detail.fatigueOnsetIndex;
    final temp   = _rescuerTemp;

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

        // ── HR + SpO2 row ──────────────────────────────────────────────────
        if (rescuerHR != null || rescuerSpO2 != null) ...[
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
                  onInfo: () => _HeartRateDetailDialog.show(context,
                    hr:          rescuerHR!,
                    hrSub:       hrSub,
                    hrColor:     hrColor,
                    vitals:      detail.rescuerVitals,
                    isEmergency: isEmergency,
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
                  onInfo: () => _SpO2DetailDialog.show(context,
                    spo2:      rescuerSpO2!,
                    spo2Sub:   spo2Sub,
                    spo2Color: spo2Color,
                  ),
                )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
// ── Wrist temp tile (full width) ───────────────────────────────────
        if (temp != null) ...[
          _VitalInfoTile.wide(
            icon:    Icons.watch_rounded,
            label:   'Rescuer wrist temp',
            value:   temp.toStringAsFixed(1),
            unit:    '°C',
            sub:     tempSub,
            color:   tempColor,
            onInfo:  () => _WristTempDetailDialog.show(context,
              temp:      temp,
              tempSub:   tempSub,
              tempColor: tempColor,
              vitals:    detail.rescuerVitals,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        // ── Fatigue score ──────────────────────────────────────────────────
        if (detail.rescuerVitals.isNotEmpty) ...[
          _VitalInfoTile.wide(
            icon:    Icons.local_fire_department_rounded,
            label:   'Fatigue Score',
            value:   '$_fatigueScore',
            unit:    '/ 100',
            sub:     _fatigueLabel,
            color:   _fatigueColor,
            progress: _fatigueScore / 100.0,
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
      ],
    );
  }
}
