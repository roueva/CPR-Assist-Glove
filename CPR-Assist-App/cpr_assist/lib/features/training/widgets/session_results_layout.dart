part of 'session_results.dart';


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
  final String ventilationRatioLabel;
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
  final List<double>? pulseCheckSamples;
  final int?          pulseCheckInterval;
  final int?          pulseCheckConfidence;
  final String        handsOnPct;

  const _CollapsingTrainingLayout({
    required this.grade,
    required this.isPediatric,
    required this.isNoFeedback,
    required this.ventilationRatioLabel,
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
    this.pulseCheckSamples,
    this.pulseCheckInterval,
    this.pulseCheckConfidence,
    this.handsOnPct = '—',
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
    final isLandscape = context.isLandscape;
    final p = _collapseProgress;
    final double noFeedbackOffset = widget.isNoFeedback ? 32.0 : 0.0;
    final double landscapeMax = context.screenHeight * 0.40;
    final double effectiveCardMin = isLandscape ? 0.0 : _cardMin + noFeedbackOffset;
    final double effectiveCardMax = isLandscape ? landscapeMax : _cardMax + noFeedbackOffset;
    final double landscapeProgress = isLandscape
        ? (_collapseProgress * 1.5).clamp(0.0, 1.0)   // collapses faster in landscape
        : p;
    final double cardH = (effectiveCardMax - landscapeProgress * (effectiveCardMax - effectiveCardMin))
        .clamp(effectiveCardMin, effectiveCardMax);
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
              final maxScroll = isLandscape
                  ? (context.screenHeight * 0.40)   // landscape: drag the card's own max height
                  : (_cardMax - _cardMin) + _pbMax; // portrait: original
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
            child: _TabBarWidget(
              tabController: widget.tabController,
              isEmergency: widget.isEmergency,
            ),
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
                      ScrollConfiguration(
                        behavior: const ScrollBehavior().copyWith(
                          overscroll: false,
                        ),
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom),
                          child: tab,
                        ),
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

    final isLandscape = context.isLandscape;
    final double landscapeRingsOpacity = (1.0 - progress * 1.6).clamp(0.0, 1.0);
    final double landscapeRingsScale = (1.0 - progress * 2.0).clamp(0.0, 1.0);


    final gradeRing = SizedBox(
      width:  isLandscape ? (availableH * 0.65).clamp(48.0, 100.0) : ringSize,
      height: isLandscape ? (availableH * 0.65).clamp(48.0, 100.0) : ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CircularProgressIndicator(
              value:           widget.grade / 100,
              strokeWidth:     isLandscape ? 7 : strokeW,
              strokeCap:       StrokeCap.round,
              backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
              valueColor:      AlwaysStoppedAnimation<Color>(_gradeColor),
            ),
          ),
          Text(
            '${widget.grade.toStringAsFixed(0)}%',
            style: AppTypography.numericDisplay(
                size: isLandscape ? ((availableH * 0.65).clamp(48.0, 100.0) * 0.22).clamp(11.0, 22.0) : fontSize,
                color: AppColors.textOnDark),
          ),
        ],
      ),
    );

    final subRings = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SubRing(label: 'DEPTH',  value: widget.depthPct,  color: _ringColor(widget.depthPct)),
        _SubRing(label: 'RATE',   value: widget.ratePct,   color: _ringColor(widget.ratePct)),
        _SubRing(label: 'RECOIL', value: widget.recoilPct, color: _ringColor(widget.recoilPct)),
      ],
    );

    final cardContent = isLandscape
        ? Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            gradeRing,
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.motivational,
              textAlign: TextAlign.center,
              style: AppTypography.subheading(
                  size: 11,
                  color: AppColors.textOnDark.withValues(alpha: 0.85)),
            ),
          ],
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Opacity(
            opacity: landscapeRingsOpacity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SubRing(label: 'DEPTH',  value: widget.depthPct,  color: _ringColor(widget.depthPct),  small: true),
                _SubRing(label: 'RATE',   value: widget.ratePct,   color: _ringColor(widget.ratePct),   small: true),
                _SubRing(label: 'RECOIL', value: widget.recoilPct, color: _ringColor(widget.recoilPct), small: true),
              ],
            ),
          ),
        ),
      ],
    )
        : Column(
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
                      bg: AppColors.textOnDark.withValues(alpha: 0.15)),
                  child: const Icon(Icons.help_outline_rounded,
                      size: 15, color: AppColors.textOnDark),
                ),
              ),
            ),
          ),
        ),
        gradeRing,
        SizedBox(height: labelGap),
        Text(
          widget.motivational,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.subheading(
              size: labelFont,
              color: AppColors.textOnDark.withValues(alpha: 0.85)),
        ),
        SizedBox(height: lerpDouble(AppSpacing.md, 0, progress)!),
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
                    subRings,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

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
                  child: cardContent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildOutcomeCard(double progress) {
    final bool?   detected  = widget.pulseDetected;
    final double? bpm       = widget.pulseDetectedBpm;
    final bool    uncertain = widget.pulseUncertain ?? false;
    final bool    noCheck   = detected == null;

    // ── Colors ──────────────────────────────────────────────────────────────
    final Color cardBg = noCheck
        ? AppColors.cprCardBg
        : uncertain
        ? AppColors.cprCardBg
        : detected == true
        ? AppColors.emergencyModeDark
        : AppColors.emergencyDark;

    final Color accentColor = noCheck
        ? AppColors.textDisabled
        : uncertain
        ? AppColors.feedbackWarn
        : detected
        ? AppColors.feedbackGood
        : AppColors.feedbackBad;

    // ── Animated sizes ──────────────────────────────────────────────────────
    final double headlineFont  = lerpDouble(22, 20, progress)!;
    final double iconSize      = lerpDouble(35, 30, progress)!;
    final double waveH         = lerpDouble(72,  0, progress)!;
    final double waveOpacity   = (1.0 - progress * 2.0).clamp(0.0, 1.0);
    final double bpmFont       = lerpDouble(45, 40, progress)!;
    final double bpmOpacity    = 1.0;
    final double statsOpacity  = (1.0 - progress * 1.6).clamp(0.0, 1.0);
    final double statsH        = lerpDouble(88,  0, progress)!;
    final double labelFont     = lerpDouble(14, 11, progress)!;

    // ── Labels ──────────────────────────────────────────────────────────────
    final String headline = noCheck
        ? 'No Pulse Check'
        : uncertain
        ? 'Weak Signal'
        : detected == true
        ? 'Pulse Detected'
        : 'No Pulse Detected';

    final String? subheadline = noCheck
        ? 'No check was performed during this session'
        : uncertain
        ? 'Could not confirm pulse'
        : detected == true
        ? null
        : 'No return of spontaneous circulation';

    final IconData icon = noCheck
        ? Icons.remove_circle_outline_rounded
        : uncertain
        ? Icons.help_outline_rounded
        : detected == true
        ? Icons.favorite_rounded
        : Icons.heart_broken_rounded;

    // ── PPG waveform — use stored samples if available, else synthetic ──────
    final ppgSamples = widget.pulseCheckSamples;
    final bool hasRealWave = ppgSamples != null && ppgSamples.length >= 10;

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [

                  // ── Icon + headline ────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _OutcomeHeartIcon(
                        icon:      icon,
                        color:     accentColor,
                        size:      iconSize,
                        animate:   detected == true && progress < 0.1,
                        bpm:       bpm,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          headline,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.poppins(
                            size:   headlineFont.clamp(13.0, 30.0),
                            weight: FontWeight.w700,
                            color:  AppColors.textOnDark,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (subheadline != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subheadline,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(
                        color: AppColors.textOnDark.withValues(alpha: 0.65),
                      ),
                    ),
                  ],

                  // ── BPM number ─────────────────────────────────────────────
                  if (detected == true && bpm != null && bpm > 0) ...[
                    SizedBox(height: lerpDouble(AppSpacing.sm, AppSpacing.xs, progress)!),
                    Opacity(
                      opacity: bpmOpacity,
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: bpm.round().toString(),
                            style: AppTypography.numericDisplay(
                              size:  bpmFont.clamp(22.0, 60.0),
                              color: AppColors.textOnDark,
                            ),
                          ),
                          TextSpan(
                            text: ' BPM',
                            style: AppTypography.badge(
                              size:  (bpmFont * 0.30).clamp(10.0, 18.0),
                              color: AppColors.textOnDark.withValues(alpha: 0.7),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],

                  // ── PPG waveform — real samples only ───────────────────────
                  if (!noCheck && hasRealWave) ...[
                    SizedBox(height: lerpDouble(AppSpacing.md, 0, progress)!),
                    SizedBox(
                      height: waveH.clamp(0.0, 96.0),
                      child: Opacity(
                        opacity: waveOpacity,
                        child: ClipRect(
                          child: _StoredPpgWave(
                            samples:  ppgSamples!,
                            color:    accentColor,
                            detected: detected == true,
                          ),
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: lerpDouble(AppSpacing.xxl, 0, progress)!),

                  // ── Cycle + confidence chips ────────────────────────────────
                  if (!noCheck && widget.pulseCheckInterval != null) ...[
                    Opacity(
                      opacity: (1.0 - progress * 3.0).clamp(0.0, 1.0),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          _OutcomeChip(
                            label: 'Cycle #${widget.pulseCheckInterval}',
                            color: accentColor,
                          ),
                          if (widget.pulseCheckConfidence != null &&
                              widget.pulseCheckConfidence! > 0)
                            _OutcomeChip(
                              label: '${widget.pulseCheckConfidence}% signal quality',
                              color: accentColor,
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: lerpDouble(AppSpacing.sm, 0, progress)!),
                  ],

                  // ── 3 stat tiles ───────────────────────────────────────────
                  SizedBox(
                    height: statsH.clamp(0.0, 88.0),
                    child: Opacity(
                      opacity: statsOpacity,
                      child: ClipRect(
                        child: OverflowBox(
                          maxHeight: 88,
                          alignment: Alignment.topCenter,
                          child: _OutcomeStatRow(
                            handsOnPct:       widget.handsOnPct,
                            durationFormatted: widget.durationFormatted,
                            compressionCount:  widget.compressionCount,
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
            Tab(text: isEmergency ? 'VITAL SIGNS'  : 'METRICS'),
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
  final double value;
  final Color  color;
  final bool   small;

  const _SubRing({
    required this.label,
    required this.value,
    required this.color,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final double size = small ? 58 : 75;
    final double fontSize = small ? 13 : 18;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size, height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: CircularProgressIndicator(
                  value:           value / 100,
                  strokeWidth:     small ? 7 : 9,
                  strokeCap:       StrokeCap.round,
                  backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
                  valueColor:      AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Text(
                '${value.round()}%',
                style: AppTypography.poppins(
                    size: fontSize, weight: FontWeight.w700,
                    color: AppColors.textOnDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
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
        required String ventilationRatioLabel,
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
        ventilationRatioLabel: ventilationRatioLabel,
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
  final String ventilationRatioLabel;

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
    required this.ventilationRatioLabel,
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
      ? [
    const _GradeWeightRow('Depth consistency',     '4–5 cm target',          28, true),
    const _GradeWeightRow('Rate consistency',       '100–120 BPM',            18, true),
    const _GradeWeightRow('Full recoil',            'Complete decompression', 18, true),
    _GradeWeightRow('Ventilation compliance', ventilationRatioLabel,    12, false),
    const _GradeWeightRow('Depth + rate combined',  'Both correct together',   8, false),
    const _GradeWeightRow('Posture',                'Wrist alignment < 15°',   8, false),
    const _GradeWeightRow('Time to first comp',     'Under 10 seconds',        4, false),
    const _GradeWeightRow('Hands-on ratio',         'Minimal pauses',          4, false),
  ]
      : [
    const _GradeWeightRow('Depth consistency',     '5–6 cm target',           25, true),
    const _GradeWeightRow('Rate consistency',       '100–120 BPM',             20, true),
    const _GradeWeightRow('Full recoil',            'Complete decompression',  20, true),
    _GradeWeightRow('Ventilation compliance', ventilationRatioLabel,     12, false),
    const _GradeWeightRow('Depth + rate combined',  'Both correct together',    8, false),
    const _GradeWeightRow('Posture',                'Wrist alignment < 15°',    8, false),
    const _GradeWeightRow('Hands-on ratio',         'Minimal pauses',           5, false),
    const _GradeWeightRow('Time to first comp',     'Under 10 seconds',         2, false),
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
      backgroundColor: AppColors.transparent,
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
                color: AppColors.pbGoldLight,
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
                  Text('🏆', style: AppTypography.body(size: 18)),
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
                  Text('🏆', style: AppTypography.body(size: 18)),
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