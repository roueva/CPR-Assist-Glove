part of 'session_results.dart';


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

    final ttf      = d?.timeToFirstCompression ?? 0.0;
    final ttfColor = ttf <= 0 ? AppColors.textDisabled
        : ttf <= 10  ? AppColors.success
        : ttf <= 20  ? AppColors.warning
        : AppColors.error;
    final ttfValue = ttf > 0 ? '${ttf.toStringAsFixed(1)} s' : '—';

    final effectiveCprTime = d != null
        ? d.sessionDuration - d.noFlowTime
        : 0.0;
    final effectiveSecs = effectiveCprTime.round();
    final effectiveFormatted =
        '${effectiveSecs ~/ 60}:${(effectiveSecs % 60).toString().padLeft(2, '0')}';

    final ttfOk = ttf > 0 && ttf <= 10;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Row 1: Duration + Compressions ──────────────────────────
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

          // ── Row 2: Avg Depth + Avg Rate ──────────────────────────────
          Row(
            children: [
              Expanded(child: _GridStatTile(
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
              )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _GridStatTile(
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
              )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Row 3: Pause Time + Time to 1st Compression ──────────────
          Row(
            children: [
              Expanded(child: _GridStatTile(
                label:    'Pause Time',
                value:    noFlowTime > 0
                    ? '${noFlowTime.toStringAsFixed(1)}s' : '0s',
                note:     noFlowIntervals > 0
                    ? '$noFlowIntervals pause(s)' : null,
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
              )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _GridStatTile(
                label:    'Time to 1st Comp',
                value:    ttfValue,
                dotColor: ttfColor,
                zoneBar: ttf > 0 ? _ZoneBarConfig(
                  minVal: 0, maxVal: 30,
                  targetMin: 0, targetMax: 10,
                  currentVal: ttf.clamp(0.0, 30.0),
                  dotColor: ttfColor,
                  targetLabel: '< 10 s',
                ) : null,
              )),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Sync banner ──────────────────────────────────────────────
          if (d?.syncedToBackend == false) ...[
            _UnsyncedBanner(
                isLoggedIn: ref.watch(authStateProvider).isLoggedIn),
            const SizedBox(height: AppSpacing.sm),
          ],

          // ── Note ─────────────────────────────────────────────────────
          _NoteCard(note: note, canEdit: canEditNote, onTap: onEditNote),
          const SizedBox(height: AppSpacing.sm),

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

          // ── PATIENT VITALS ────────────────────────────────────────────
          if (d != null) ...[
            _EmergencySectionHeader(
              icon:      Icons.person_outline_rounded,
              iconColor: AppColors.emergency,
              title:     'Patient',
              subtitle:  isPediatric ? 'Pediatric' : 'Adult',
            ),
            const SizedBox(height: AppSpacing.sm),
            _PatientVitalsGrid(
              detail:      d,
              isPediatric: isPediatric,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(color: AppColors.divider, height: 1),
            const SizedBox(height: AppSpacing.lg),
          ],


          // ── RESCUER VITALS ────────────────────────────────────────────
          if (d != null && (rescuerHR != null || rescuerSpO2 != null ||
              d.rescuerVitals.isNotEmpty)) ...[
            _EmergencySectionHeader(
              icon:      Icons.watch_rounded,
              iconColor: AppColors.primaryAlt,
              title:     'Rescuer',
            ),
            const SizedBox(height: AppSpacing.sm),
            _RescuerVitalsSection(
              rescuerHR:   rescuerHR,
              rescuerSpO2: rescuerSpO2,
              detail:      d,
            ),
            const SizedBox(height: AppSpacing.md),
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
  final double         targetDepthMin;
  final double         targetDepthMax;

  const _EmergencyTimelineTab({
    required this.detail,
    required this.targetDepthMin,
    required this.targetDepthMax,
  });

  @override
  Widget build(BuildContext context) {
    final d = detail;

    if (d == null) {
      return const _EmptyState(
        icon:  Icons.timeline_rounded,
        title: 'Timeline not available',
        body:  'Full timeline is only available for sessions '
            'loaded directly from the glove.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Timeline ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
          child: _ExpandableSectionCard(
            title:     'Session Timeline',
            icon:      Icons.timeline_rounded,
            iconColor: AppColors.primaryAlt,
            startOpen: true,
            child:     _SessionTimelineSection(detail: d),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Compression charts — collapsible, full-width inside card ──
        if (d.compressions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: _ExpandableSectionCard(
              title:     'Compression Data',
              icon:      Icons.show_chart_rounded,
              iconColor: AppColors.primary,
              startOpen: false,
              child: _EmergencyChartsSection(
                detail:         d,
                targetDepthMin: targetDepthMin,
                targetDepthMax: targetDepthMax,
              ),
            ),
          ),
        ],

      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmergencyChartsSection — compression depth + rate graphs for emergency tab 3
// ─────────────────────────────────────────────────────────────────────────────
class _EmergencyChartsSection extends StatelessWidget {
  final SessionDetail detail;
  final double        targetDepthMin;
  final double        targetDepthMax;
  final bool compact;


  const _EmergencyChartsSection({
    required this.detail,
    required this.targetDepthMin,
    required this.targetDepthMax,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final events = detail.compressions;
    if (events.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DepthRecoilChartCard(
          events:         events,
          targetDepthMin: targetDepthMin,
          targetDepthMax: targetDepthMax,
          compact:        true,
        ),
        const SizedBox(height: AppSpacing.sm),
        _RateScrollChartCard(
          events:  events,
          compact: true,
        ),
        if (events.length >= 5) ...[
          const SizedBox(height: AppSpacing.sm),
          _DepthTrendChartCard(
            events:         events,
            targetDepthMin: targetDepthMin,
            targetDepthMax: targetDepthMax,
            compact:        true,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmergencySectionHeader — plain non-collapsible section label
// ─────────────────────────────────────────────────────────────────────────────

class _EmergencySectionHeader extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String?  subtitle;

  const _EmergencySectionHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: AppDecorations.iconRounded(
              bg: iconColor.withValues(alpha: 0.10),
              radius: AppSpacing.cardRadiusSm),
          child: Icon(icon, size: AppSpacing.iconSm, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.subheading(size: 14)),
              if (subtitle != null)
                Text(subtitle!, style: AppTypography.caption()),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PatientVitalsGrid — 2×2 grid of patient vital tiles
// ─────────────────────────────────────────────────────────────────────────────
class _PatientVitalsGrid extends StatelessWidget {
  final SessionDetail detail;
  final bool          isPediatric;
  const _PatientVitalsGrid({
    required this.detail,
    required this.isPediatric,
  });

  @override
  Widget build(BuildContext context) {
    final detected  = detail.pulseDetectedFinal;
    final bpm       = detail.pulseChecks
        .where((p) => p.detected && p.detectedBpm > 0)
        .fold<double?>(null, (_, p) => p.detectedBpm);
    final temp      = detail.patientTemperature;
    final spo2      = detail.patientSpO2LastCheck;
    final perfIdx   = detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.last.perfusionIndex : 0;
    final lastCheck = detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.last : null;

    final pulseColor = detected ? AppColors.success : AppColors.textSecondary;
    final spo2Color  = spo2 == null  ? AppColors.textDisabled
        : spo2 >= 95                 ? AppColors.success
        : spo2 >= 90                 ? AppColors.warning
        : AppColors.error;
    final tempColor  = temp == null  ? AppColors.textDisabled
        : temp < 35.0                ? AppColors.primary
        : temp <= 37.5               ? AppColors.success
        : AppColors.warning;
    final piColor    = perfIdx <= 0  ? AppColors.textDisabled
        : perfIdx >= 40              ? AppColors.success
        : perfIdx >= 20              ? AppColors.warning
        : AppColors.error;

    // Which check number had the detection
    final detectedCheck = detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.lastWhere(
            (p) => p.detected,
        orElse: () => detail.pulseChecks.last)
        : null;
    final detectedAtNumber = (detectedCheck != null && detectedCheck.detected)
        ? detectedCheck.intervalNumber : null;

    final detectedAtTime = (detectedCheck != null && detectedCheck.detected)
        ? () {
      final abs = detail.sessionStart.add(
          Duration(milliseconds: detectedCheck.timestampMs));
      final h = abs.hour.toString().padLeft(2, '0');
      final m = abs.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        // ── Big tappable Pulse card ────────────────────────────────────
        GestureDetector(
          onTap: () => _PulseDetailDialog.show(
            context,
            detail:     detail,
            pulseColor: pulseColor,
            bpm:        bpm,
            spo2:       spo2,
            spo2Color:  spo2Color,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: AppDecorations.tintedCard(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: icon + label + info icon
                Row(
                  children: [
                    Container(
                      width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                      decoration: AppDecorations.iconRounded(
                          bg: pulseColor.withValues(alpha: 0.10),
                          radius: AppSpacing.cardRadiusSm),
                      child: Icon(
                          detected
                              ? Icons.favorite_rounded
                              : Icons.heart_broken_rounded,
                          size: AppSpacing.iconSm, color: pulseColor),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('Patient Pulse',
                          style: AppTypography.subheading(size: 14)),
                    ),
                    Icon(Icons.info_outline_rounded,
                        size: AppSpacing.iconXs,
                        color: AppColors.primary.withValues(alpha: 0.45)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),

                // BPM + status row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: detected && bpm != null
                              ? bpm!.round().toString() : '—',
                          style: AppTypography.numericDisplay(
                              size: 28, color: pulseColor),
                        ),
                        if (detected && bpm != null)
                          TextSpan(
                            text: '  bpm',
                            style: AppTypography.bodyMedium(
                                size: 12,
                                color: pulseColor.withValues(alpha: 0.7)),
                          ),
                      ]),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          detected && detectedAtTime != null
                              ? 'Detected at $detectedAtTime'
                              : detected
                              ? 'Signal detected'
                              : 'No pulse detected',
                          style: AppTypography.caption(color: pulseColor),
                        ),
                        if (lastCheck != null && lastCheck.confidence > 0)
                          Text(
                            'Signal quality: ${lastCheck.confidence}%',
                            style: AppTypography.caption(
                                color: AppColors.textDisabled),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Perfusion Index + Skin Temp ────────────────────────────────
        Row(
          children: [
            Expanded(child: _VitalInfoTile(
              icon:  Icons.water_drop_outlined,
              label: 'Perfusion Index',
              value: perfIdx > 0 ? '$perfIdx' : '—',
              unit:  perfIdx > 0 ? '/ 100' : '',
              sub:   perfIdx <= 0 ? 'No data'
                  : perfIdx >= 40 ? 'Good perfusion'
                  : perfIdx >= 20 ? 'Reduced'
                  : 'Poor',
              color: piColor,
              onInfo: () => _PerfusionIndexDialog.show(
                  context, perfIdx: perfIdx, color: piColor),
            )),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _VitalInfoTile(
              icon:  Icons.thermostat_rounded,
              label: 'Skin Temp',
              value: temp != null ? temp.toStringAsFixed(1) : '—',
              unit:  temp != null ? '°C' : '',
              sub:   temp == null ? 'No data'
                  : temp < 35.0   ? 'Below normal'
                  : temp <= 37.5  ? 'Normal'
                  : 'Elevated',
              color: tempColor,
              onInfo: () => _PatientSkinTempDialog.show(
                  context, temp: temp, color: tempColor),
            )),
          ],
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _PulseDetailDialog — full pulse info + all checks
// ─────────────────────────────────────────────────────────────────────────────

class _PulseDetailDialog extends StatelessWidget {
  final SessionDetail detail;
  final Color         pulseColor;
  final double?       bpm;
  final double?       spo2;
  final Color         spo2Color;

  const _PulseDetailDialog({
    required this.detail,
    required this.pulseColor,
    required this.bpm,
    required this.spo2,
    required this.spo2Color,
  });

  static void show(
      BuildContext context, {
        required SessionDetail detail,
        required Color         pulseColor,
        required double?       bpm,
        required double?       spo2,
        required Color         spo2Color,
      }) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) => _PulseDetailDialog(
        detail:     detail,
        pulseColor: pulseColor,
        bpm:        bpm,
        spo2:       spo2,
        spo2Color:  spo2Color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detected  = detail.pulseDetectedFinal;
    final lastCheck = detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.last : null;

    final lastPi = lastCheck?.perfusionIndex ?? 0;
    final piColor = lastPi <= 0      ? AppColors.textDisabled
        : lastPi >= 40               ? AppColors.success
        : lastPi >= 20               ? AppColors.warning
        :                              AppColors.error;
    final piLabel = lastPi <= 0      ? '—'
        : lastPi >= 40               ? 'Good'
        : lastPi >= 20               ? 'Reduced'
        :                              'Poor';

    final lastSpo2 = lastCheck?.patientSpO2 ?? 0.0;
    final spo2Val  = lastSpo2 > 0 ? lastSpo2 : spo2;
    final effectiveSpo2Color = spo2Val == null ? AppColors.textDisabled
        : spo2Val >= 95              ? AppColors.success
        : spo2Val >= 90              ? AppColors.warning
        :                              AppColors.error;
    final spo2Label = spo2Val == null ? '—'
        : spo2Val >= 95              ? 'Normal'
        : spo2Val >= 90              ? 'Low-normal'
        :                              'Low';

    final confColor = lastCheck == null || lastCheck.confidence == 0
        ? AppColors.textDisabled
        : lastCheck.confidence >= 80 ? AppColors.success
        : lastCheck.confidence >= 40 ? AppColors.warning
        :                              AppColors.error;
    final confLabel = lastCheck == null || lastCheck.confidence == 0 ? '—'
        : lastCheck.confidence >= 80 ? 'Strong'
        : lastCheck.confidence >= 40 ? 'Acceptable'
        :                              'Unreliable';

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

            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.md, AppSpacing.sm, 0),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.iconLg, height: AppSpacing.iconLg,
                    decoration: AppDecorations.iconRounded(
                        bg: pulseColor.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusSm),
                    child: Icon(
                        detected
                            ? Icons.favorite_rounded
                            : Icons.heart_broken_rounded,
                        size: AppSpacing.iconSm, color: pulseColor),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Patient Pulse',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Hero ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: AppSpacing.iconXl, height: AppSpacing.iconXl,
                    decoration: AppDecorations.iconRounded(
                        bg: pulseColor.withValues(alpha: 0.12),
                        radius: AppSpacing.cardRadiusMd),
                    child: Icon(
                        detected ? Icons.favorite_rounded
                            : Icons.heart_broken_rounded,
                        size: AppSpacing.iconMd, color: pulseColor),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detected ? 'Pulse Detected' : 'No Pulse Detected',
                    style: AppTypography.subheading(size: 14, color: pulseColor),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(children: [
                      TextSpan(
                        text: detected && bpm != null
                            ? bpm!.round().toString() : '—',
                        style: AppTypography.numericDisplay(
                            size: 48, color: pulseColor),
                      ),
                      if (detected && bpm != null)
                        TextSpan(
                          text: ' bpm',
                          style: AppTypography.bodyMedium(
                              size: 16,
                              color: pulseColor.withValues(alpha: 0.7)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lastCheck != null && lastCheck.confidence > 0
                        ? 'Signal quality: ${lastCheck.confidence}%  ·  $confLabel'
                        : detected
                        ? 'Signal confirmed'
                        : (lastCheck?.isUncertain == true
                        ? 'Weak signal, verify manually'
                        : 'No pulse signal detected'),
                    style: AppTypography.caption(
                        color: lastCheck != null && lastCheck.confidence > 0
                            ? confColor
                            : pulseColor.withValues(alpha: 0.65)),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Scrollable body ────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── How it works ───────────────────────────────────
                    _sectionLabel('How it works', pulseColor),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: AppDecorations.greyInfoBox(),
                      child: Text(
                        'The rescuer places the glove\'s fingertip sensor '
                            'against the patient\'s carotid artery or another '
                            'pulse point. The optical sensor detects pulsatile '
                            'blood flow beneath the skin. Signal quality reflects '
                            'how stable the contact was — always verify manually.',
                        style: AppTypography.body(
                            size: 13, color: AppColors.textSecondary),
                      ),
                    ),

                    // ── Signal quality guide ───────────────────────────
                    const SizedBox(height: AppSpacing.md),
                    _sectionLabel('Signal quality guide', pulseColor),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius:
                        BorderRadius.circular(AppSpacing.cardRadiusMd),
                        border: Border.all(
                            color: AppColors.cprCardBg
                                .withValues(alpha: 0.12),
                            width: 1.5),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs),
                      child: Column(
                        children: [
                          _buildRangeRow('≥ 80%', 'Strong, reliable',
                              AppColors.success),
                          const Divider(height: 1, color: AppColors.divider),
                          _buildRangeRow('40–79%', 'Acceptable, use with care',
                              AppColors.warning),
                          const Divider(height: 1, color: AppColors.divider),
                          _buildRangeRow('< 40%', 'Unreliable, verify manually',
                              AppColors.error),
                        ],
                      ),
                    ),

                    // ── All checks ─────────────────────────────────────
                    if (detail.pulseChecks.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _sectionLabel('All Checks This Session', pulseColor),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius:
                          BorderRadius.circular(AppSpacing.cardRadiusMd),
                          border: Border.all(
                              color: AppColors.cprCardBg
                                  .withValues(alpha: 0.12),
                              width: 1.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xxs),
                        child: Column(
                          children: [
                            for (int i = 0;
                            i < detail.pulseChecks.length;
                            i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1, color: AppColors.divider),
                              Builder(builder: (_) {
                                final pc   = detail.pulseChecks[i];
                                final abs  = detail.sessionStart.add(
                                    Duration(
                                        milliseconds: pc.timestampMs));
                                final hh   = abs.hour
                                    .toString().padLeft(2, '0');
                                final mm   = abs.minute
                                    .toString().padLeft(2, '0');
                                final timeStr = '$hh:$mm';
                                final c = pc.detected
                                    ? AppColors.success
                                    : pc.isUncertain
                                    ? AppColors.warning
                                    : AppColors.textSecondary;
                                final outcome = pc.detected
                                    ? 'Present'
                                    : pc.isUncertain
                                    ? 'Uncertain'
                                    : 'Absent';
                                final sub = [
                                  if (pc.detectedBpm > 0)
                                    '${pc.detectedBpm.round()} bpm',
                                  if (pc.confidence > 0)
                                    '${pc.confidence}% quality',
                                  if (pc.perfusionIndex > 0)
                                    'PI ${pc.perfusionIndex}',
                                ].join(' · ');
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: AppSpacing.sm),
                                  child: Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 8, height: 8,
                                        margin: const EdgeInsets.only(
                                            right: AppSpacing.sm, top: 3),
                                        decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Check #${pc.intervalNumber}',
                                              style: AppTypography
                                                  .bodyMedium(size: 13),
                                            ),
                                            if (sub.isNotEmpty)
                                              Text(sub,
                                                  style: AppTypography
                                                      .caption(color:
                                                  AppColors
                                                      .textDisabled)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                        children: [
                                          Text(outcome,
                                              style: AppTypography.bodyBold(
                                                  size: 12, color: c)),
                                          Text(timeStr,
                                              style: AppTypography.caption(
                                                  color: AppColors
                                                      .textDisabled)),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
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

  Widget _buildRangeRow(String range, String meaning, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: AppSpacing.sm),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(
            width: 56,
            child: Text(range,
                style: AppTypography.bodyMedium(size: 13)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(meaning,
                textAlign: TextAlign.right,
                softWrap: true,
                style: AppTypography.caption(color: color)),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _MiniMetricTile — compact metric display used inside _PulseDetailDialog hero
// ─────────────────────────────────────────────────────────────────────────────

class _MiniMetricTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final String   sub;
  final Color    color;

  const _MiniMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical:   AppSpacing.sm),
        decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadiusMd),
        child: Row(
          children: [
            Icon(icon, size: AppSpacing.iconXs, color: AppColors.textDisabled),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.caption(
                          color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis),
                  Text(value,
                      style: AppTypography.bodyBold(size: 13, color: color),
                      overflow: TextOverflow.ellipsis),
                  Text(sub,
                      style: AppTypography.caption(
                          color: color.withValues(alpha: 0.70)),
                      overflow: TextOverflow.ellipsis),
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
// _PerfusionIndexDialog
// ─────────────────────────────────────────────────────────────────────────────

class _PerfusionIndexDialog extends StatelessWidget {
  final int   perfIdx;
  final Color color;

  const _PerfusionIndexDialog({
    required this.perfIdx,
    required this.color,
  });

  static void show(BuildContext context,
      {required int perfIdx, required Color color}) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) =>
          _PerfusionIndexDialog(perfIdx: perfIdx, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = perfIdx <= 0  ? 'No data'
        : perfIdx >= 40         ? 'Good perfusion'
        : perfIdx >= 20         ? 'Reduced perfusion'
        :                         'Poor perfusion';

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

            // ── Header ────────────────────────────────────────────────
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
                    child: Icon(Icons.water_drop_outlined,
                        size: AppSpacing.iconSm, color: color),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Perfusion Index',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Value hero ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: perfIdx > 0 ? '$perfIdx' : '—',
                        style: AppTypography.numericDisplay(
                            size: 48, color: color),
                      ),
                      if (perfIdx > 0)
                        TextSpan(
                          text: ' / 100',
                          style: AppTypography.bodyMedium(
                              size: 16,
                              color: color.withValues(alpha: 0.7)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(label,
                      style: AppTypography.subheading(
                          size: 13, color: color)),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: AppDecorations.greyInfoBox(),
                    child: Text(
                      'The perfusion index is the ratio of pulsatile to non-pulsatile '
                          'blood flow, measured at the patient\'s carotid artery during '
                          'the pulse check pause. A higher value indicates a stronger '
                          'pulse signal. \nIn cardiac arrest this is typically close to zero.',
                      style: AppTypography.body(
                          size: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Container(
                        width: 3, height: 12,
                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius:
                          BorderRadius.circular(AppSpacing.xxs),
                        ),
                      ),
                      Text('Interpretation',
                          style: AppTypography.subheading(size: 12)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius:
                      BorderRadius.circular(AppSpacing.cardRadiusMd),
                      border: Border.all(color: AppColors.cprCardBg.withValues(alpha: 0.12), width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs),
                    child: Column(
                      children: [
                        _buildRangeRow('40 or above', 'Good peripheral perfusion',
                            AppColors.success),
                        const Divider(height: 1, color: AppColors.divider),
                        _buildRangeRow('20 to 39', 'Reduced peripheral flow',
                            AppColors.warning),
                        const Divider(height: 1, color: AppColors.divider),
                        _buildRangeRow('Below 20',
                            'Minimal peripheral circulation',
                            AppColors.error),
                      ],
                    ),
                  ),
                ],
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
// _PatientSkinTempDialog
// ─────────────────────────────────────────────────────────────────────────────

class _PatientSkinTempDialog extends StatelessWidget {
  final double? temp;
  final Color   color;

  const _PatientSkinTempDialog({
    required this.temp,
    required this.color,
  });

  static void show(BuildContext context,
      {required double? temp, required Color color}) {
    showDialog<void>(
      context:      context,
      barrierColor: AppColors.overlayDark,
      builder: (_) =>
          _PatientSkinTempDialog(temp: temp, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = temp == null  ? 'No data'
        : temp! < 35.0          ? 'Below normal'
        : temp! <= 37.5         ? 'Normal'
        :                         'Elevated';

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

            // ── Header ────────────────────────────────────────────────
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
                    child: Icon(Icons.thermostat_rounded,
                        size: AppSpacing.iconSm, color: color),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text('Patient Skin Temperature',
                      style: AppTypography.heading(size: 16))),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSecondary,
                        size: AppSpacing.iconMd),
                    padding: EdgeInsets.zero,
                    constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // ── Value hero ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: temp != null
                            ? temp!.toStringAsFixed(1) : '—',
                        style: AppTypography.numericDisplay(
                            size: 48, color: color),
                      ),
                      if (temp != null)
                        TextSpan(
                          text: ' °C',
                          style: AppTypography.bodyMedium(
                              size: 16,
                              color: color.withValues(alpha: 0.7)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(label,
                      style: AppTypography.subheading(
                          size: 13, color: color)),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),

            // ── Body ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: AppDecorations.greyInfoBox(),
                    child: Text(
                      'Skin temperature at the patient\'s neck, recorded by the '
                          'glove sensor when the rescuer presses their finger against '
                          'the carotid artery. In cardiac arrest, low values may indicate '
                          'hypothermia or prolonged circulatory failure.',
                      style: AppTypography.body(
                          size: 13, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Container(
                        width: 3, height: 12,
                        margin: const EdgeInsets.only(right: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius:
                          BorderRadius.circular(AppSpacing.xxs),
                        ),
                      ),
                      Text('Interpretation',
                          style: AppTypography.subheading(size: 12)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius:
                      BorderRadius.circular(AppSpacing.cardRadiusMd),
                      border: Border.all(color: AppColors.cprCardBg.withValues(alpha: 0.12), width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs),
                    child: Column(
                      children: [
                        _buildRangeRow('35 to 37.5 °C', 'Normal range',
                            AppColors.success),
                        const Divider(height: 1, color: AppColors.divider),
                        _buildRangeRow('Below 35 °C',
                            'Below normal, possible hypothermia',
                            AppColors.primary),
                        const Divider(height: 1, color: AppColors.divider),
                        _buildRangeRow('Above 37.5 °C',
                            'Elevated, possible fever',
                            AppColors.warning),
                      ],
                    ),
                  ),
                ],
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

Widget _buildRangeRow(String range, String meaning, Color color,
    {bool isLast = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      children: [
        Container(
          width: 8, height: 8,
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(
          width: 100,
          child: Text(range, style: AppTypography.bodyMedium(size: 13)),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(meaning,
              textAlign: TextAlign.right,
              softWrap: true,
              style: AppTypography.caption(color: color)),
        ),
      ],
    ),
  );
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
            note: 'Glove sensor, carotid contact',
            iconColor: AppColors.error,
          ),
        if (detail.rescuerWristTempStart != null)
          _DetailRow(
            icon:      Icons.device_thermostat_rounded,
            label:     'Room Temperature',
            value:     '${detail.rescuerWristTempStart!.toStringAsFixed(1)} °C',
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


class _WaveformPainter extends CustomPainter {
  final Color color;
  final bool  active;
  const _WaveformPainter({required this.color, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = active ? color.withValues(alpha: 0.7) : color.withValues(alpha: 0.25)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final mid = h / 2;

    // A single representative PPG-like waveform cycle, repeated 3 times
    final path = Path();
    path.moveTo(0, mid);

    // Repeat the pattern across width
    final cycles = 3;
    final cycleW = w / cycles;

    for (int i = 0; i < cycles; i++) {
      final x0 = i * cycleW;
      // Flat baseline
      path.lineTo(x0 + cycleW * 0.25, mid);
      // Upstroke
      path.cubicTo(
        x0 + cycleW * 0.30, mid,
        x0 + cycleW * 0.35, mid - h * 0.7,
        x0 + cycleW * 0.40, mid - h * 0.85,
      );
      // Peak and downstroke with dicrotic notch
      path.cubicTo(
        x0 + cycleW * 0.45, mid - h * 0.7,
        x0 + cycleW * 0.50, mid - h * 0.1,
        x0 + cycleW * 0.55, mid - h * 0.2,
      );
      path.cubicTo(
        x0 + cycleW * 0.58, mid - h * 0.15,
        x0 + cycleW * 0.60, mid - h * 0.05,
        x0 + cycleW * 0.65, mid,
      );
      // Return to baseline
      path.lineTo(x0 + cycleW, mid);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.color != color || old.active != active;
}

// ── Small info chip ──────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: AppTypography.badge(size: 10, color: color)),
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
            note: 'Glove sensor, carotid contact',
            iconColor: AppColors.error,
          ),
        if (detail?.rescuerWristTempStart != null)
          _DetailRow(
            icon:      Icons.thermostat_rounded,
            label:     'Room Temperature',
            value:     '${detail!.rescuerWristTempStart!.toStringAsFixed(1)}°C',
            note:      'Rescuer wrist temp at session start',
            iconColor: AppColors.textSecondary,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OutcomeHeartIcon — single-beat animation on ROSC
// ─────────────────────────────────────────────────────────────────────────────

class _OutcomeHeartIcon extends StatefulWidget {
  final IconData icon;
  final Color    color;
  final double   size;
  final bool     animate;
  final double?  bpm;

  const _OutcomeHeartIcon({
    required this.icon,
    required this.color,
    required this.size,
    required this.animate,
    this.bpm,
  });

  @override
  State<_OutcomeHeartIcon> createState() => _OutcomeHeartIconState();
}

class _OutcomeHeartIconState extends State<_OutcomeHeartIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    // Duration = one beat period based on detected BPM, min 400ms max 1200ms
    final bpm      = (widget.bpm ?? 70).clamp(40.0, 150.0);
    final periodMs = (60000 / bpm).round().clamp(400, 1200);
    _ctrl = AnimationController(
      vsync:    this,
      duration: Duration(milliseconds: periodMs),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.35)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 70),
    ]).animate(_ctrl);

    if (widget.animate) {
      // One beat after a short delay, then stop
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _StoredPpgWave — renders real captured ppgSamples using _PpgPainter
// ─────────────────────────────────────────────────────────────────────────────

class _StoredPpgWave extends StatelessWidget {
  final List<double> samples;
  final Color        color;
  final bool         detected;

  const _StoredPpgWave({
    required this.samples,
    required this.color,
    required this.detected,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PpgResultPainter(
        samples:  samples,
        color:    color,
        detected: detected,
      ),
      size: const Size(double.infinity, 96),
    );
  }
}

class _PpgResultPainter extends CustomPainter {
  final List<double> samples;
  final Color        color;
  final bool         detected;

  const _PpgResultPainter({
    required this.samples,
    required this.color,
    required this.detected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color      = detected
          ? color.withValues(alpha: 0.85)
          : color.withValues(alpha: 0.35)
      ..strokeWidth = 2.0
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    final path   = Path();
    final w      = size.width;
    final h      = size.height;
    final count  = samples.length;
    final xStep  = w / (count - 1).toDouble();

    for (int i = 0; i < count; i++) {
      // Flip: sample 1.0 = top of waveform → y near 0
      final y = h - (samples[i].clamp(0.0, 1.0) * h * 0.85) - h * 0.07;
      final x = i * xStep;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PpgResultPainter old) =>
      old.samples != samples || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// _SyntheticPpgWave — fallback when no real samples stored
// ─────────────────────────────────────────────────────────────────────────────

class _SyntheticPpgWave extends StatelessWidget {
  final Color  color;
  final bool   detected;
  final double bpm;

  const _SyntheticPpgWave({
    required this.color,
    required this.detected,
    required this.bpm,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _WaveformPainter(color: color, active: detected),
      size: const Size(double.infinity, 56),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OutcomeChip — small pill for cycle # and confidence
// ─────────────────────────────────────────────────────────────────────────────

class _OutcomeChip extends StatelessWidget {
  final String label;
  final Color  color;
  const _OutcomeChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs + 1),
      decoration: BoxDecoration(
        color:        color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
      ),
      child: Text(label,
          style: AppTypography.badge(
              size: 10, color: AppColors.textOnDark.withValues(alpha: 0.9))),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OutcomeStatRow — CCF / Duration / Compressions tiles
// ─────────────────────────────────────────────────────────────────────────────

class _OutcomeStatRow extends StatelessWidget {
  final String handsOnPct;
  final String durationFormatted;
  final int    compressionCount;

  const _OutcomeStatRow({
    required this.handsOnPct,
    required this.durationFormatted,
    required this.compressionCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.darkStatTile(),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _SummaryCell(value: handsOnPct,              label: 'HANDS-ON'),
            _VDivider(),
            _SummaryCell(value: durationFormatted,       label: 'DURATION'),
            _VDivider(),
            _SummaryCell(value: '$compressionCount',     label: 'COMPRESSIONS'),
          ],
        ),
      ),
    );
  }
}
