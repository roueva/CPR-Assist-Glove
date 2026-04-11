import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import 'depth_bar.dart';
import 'rotating_arrow.dart';

// ─────────────────────────────────────────────────────────────────────────────
// live_cpr_widgets.dart
//
// Exports:
//   • VitalsCard         — patient or rescuer vitals (original style)
//   • LiveCprMetricsCard — dark CPR hub with live feedback
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// VitalsCard — original style: blue Poppins title, plain value + label columns
// ─────────────────────────────────────────────────────────────────────────────

class VitalsCard extends StatelessWidget {
  final String label;
  final double? heartRate;
  final double? temperature;
  final double? spO2;

  // pulseConfidence: for patient card — gates HR/SpO₂ display (requires ≥ 40)
  // null = rescuer card (no gating)
  final int? pulseConfidence;
  final int? rescuerSignalQuality;

  const VitalsCard({
    super.key,
    required this.label,
    this.heartRate,
    this.temperature,
    this.spO2,
    this.pulseConfidence,
    this.rescuerSignalQuality,
  });

  @override
  Widget build(BuildContext context) {
    // Patient card: HR and SpO₂ only shown when pulse check confidence >= 40
    final bool hasValidPulse = pulseConfidence == null ||
        pulseConfidence! >= 40;
    final bool hasGoodSignal = rescuerSignalQuality == null ||
        rescuerSignalQuality! >= 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Row(
            children: [
              Text(
                label,
                style: AppTypography.poppins(
                  size:   20,
                  weight: FontWeight.bold,
                  color:  AppColors.primary,
                ),
              ),
              // Confidence badge — patient card only, when a check has run
              if (pulseConfidence != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: hasValidPulse
                        ? AppColors.successBg
                        : AppColors.warningBg,
                    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  ),
                  child: Text(
                    '$pulseConfidence% confidence',
                    style: AppTypography.poppins(
                      size: 9,
                      weight: FontWeight.w600,
                      color: hasValidPulse
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ),
              ],
              // Signal quality badge — rescuer card only
              if (rescuerSignalQuality != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs, vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: rescuerSignalQuality! >= 40
                        ? AppColors.successBg
                        : AppColors.warningBg,
                    borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  ),
                  child: Text(
                    rescuerSignalQuality! >= 40 ? 'Good signal' : 'Poor signal',
                    style: AppTypography.poppins(
                      size: 9,
                      weight: FontWeight.w600,
                      color: rescuerSignalQuality! >= 40
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Opacity(
          opacity: hasGoodSignal ? 1.0 : 0.45,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md,
              horizontal: AppSpacing.sm,
            ),
            decoration: AppDecorations.card(),
            child: Row(
              children: [
                Expanded(
                  child: _VitalItem(
                    icon: Icons.favorite_rounded,
                    iconColor: heartRate != null && hasValidPulse
                        ? AppColors.primary
                        : AppColors.textDisabled,
                    value: heartRate != null && hasValidPulse
                        ? heartRate!.toStringAsFixed(0)
                        : '--',
                    unit: heartRate != null && hasValidPulse ? 'BPM' : '',
                    label: 'HEART RATE',
                  ),
                ),
                _Divider(),
                Expanded(
                  child: _VitalItem(
                    icon: Icons.air_rounded,
                    iconColor: spO2 != null && hasValidPulse
                        ? AppColors.primary
                        : AppColors.textDisabled,
                    value: spO2 != null && hasValidPulse
                        ? spO2!.toStringAsFixed(0)
                        : '--',
                    unit: spO2 != null && hasValidPulse ? '%' : '',
                    label: 'SpO₂',
                  ),
                ),
                _Divider(),
                Expanded(
                  child: _VitalItem(
                    icon: Icons.thermostat_rounded,
                    iconColor: temperature != null
                        ? AppColors.primary
                        : AppColors.textDisabled,
                    value: temperature != null
                        ? temperature!.toStringAsFixed(1)
                        : '--',
                    unit: temperature != null ? '°C' : '',
                    label: 'TEMP',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width:  AppSpacing.dividerThickness,
    height: AppSpacing.vitalsItemHeight,
    color:  AppColors.divider,
  );
}

class _VitalItem extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   value;
  final String   unit;
  final String   label;

  const _VitalItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon
        Icon(icon, size: AppSpacing.iconSm, color: iconColor),
        const SizedBox(height: AppSpacing.xxs),
        // Value + unit on same line
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: AppTypography.poppins(
                  size:   22,
                  weight: FontWeight.w700,
                  color:  AppColors.vitalsValue,
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: AppTypography.poppins(
                    size:   11,
                    weight: FontWeight.w500,
                    color:  AppColors.textDisabled,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        // Label
        Text(
          label,
          style: AppTypography.poppins(
            size:   9,
            weight: FontWeight.w600,
            color:  AppColors.textDisabled,
          ),
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// LiveCprMetricsCard
//
// Dark-blue hub. Three zones:
//   A) Header — session dot + timer (large) + compression count
//   B) Gauge row — frequency arc + depth bar, both color-coded
//   C) Status bar — only visible during an active session
// ─────────────────────────────────────────────────────────────────────────────

class LiveCprMetricsCard extends StatefulWidget {
  final double      depth;
  final double peakDepth;
  final double      frequency;
  final Duration    cprTime;
  final int         compressionCount;
  final bool recoilAchieved;   // ADD
  final bool        isSessionActive;
  final bool        imuCalibrated;
  final bool        showFatigueBadge;
  final int         fatigueScore;
  final CprScenario scenario;
  final int compressionInCycle;
  final bool isNoFeedback;

  const LiveCprMetricsCard({
    super.key,
    required this.depth,
    required this.peakDepth,
    required this.frequency,
    required this.cprTime,
    required this.compressionCount,
    required this.isSessionActive,
    this.recoilAchieved    = false,
    this.imuCalibrated     = true,
    this.showFatigueBadge  = false,
    this.fatigueScore      = 0,
    required this.scenario,
    this.compressionInCycle = 0,
    this.isNoFeedback       = false,
  });

  @override
  State<LiveCprMetricsCard> createState() => _LiveCprMetricsCardState();
}

class _LiveCprMetricsCardState extends State<LiveCprMetricsCard> {
  // Consecutive compression counters for coaching throttle
  int _consecutiveGood      = 0;
  int _consecutiveTooShallow = 0;
  int _consecutiveTooDeep   = 0;
  int _consecutiveTooSlow   = 0;
  int _consecutiveTooFast   = 0;
  int _lastCompressionCount = 0;

  static const int _kCoachingThreshold = 5;

  @override
  void didUpdateWidget(covariant LiveCprMetricsCard old) {
    super.didUpdateWidget(old);
    if (!old.isSessionActive && widget.isSessionActive) {
      _consecutiveGood       = 0;
      _lastCompressionCount  = 0;
      _consecutiveTooShallow = 0;
      _consecutiveTooDeep    = 0;
      _consecutiveTooSlow    = 0;
      _consecutiveTooFast    = 0;
    }
  }

  _FeedbackState _depthFeedback(double d) {
    if (d <= 0)                                    return _FeedbackState.idle;
    if (d < widget.scenario.targetDepthMinCm)       return _FeedbackState.tooLittle;
    if (d <= widget.scenario.targetDepthMaxCm)      return _FeedbackState.good;
    return                                          _FeedbackState.tooMuch;
  }

  // Frequency: too slow = orange (tooLittle), too fast = red (tooMuch)
  _FeedbackState _freqFeedback(double f) {
    if (f <= 0)   return _FeedbackState.idle;
    if (f < 100)  return _FeedbackState.tooLittle;
    if (f <= 120) return _FeedbackState.good;
    return         _FeedbackState.tooMuch;
  }

  void _updateConsecutiveCounts(
      _FeedbackState depthState, _FeedbackState freqState) {
    // Only count when a new compression arrives (compressionCount changed)
    // Called once per build when session active — counts accumulate
    if (depthState == _FeedbackState.good && freqState == _FeedbackState.good) {
      _consecutiveGood++;
      _consecutiveTooShallow = 0;
      _consecutiveTooDeep    = 0;
      _consecutiveTooSlow    = 0;
      _consecutiveTooFast    = 0;
    } else {
      _consecutiveGood = 0;
      if (depthState == _FeedbackState.tooLittle) {
        _consecutiveTooShallow++;
        _consecutiveTooDeep = 0;
      } else if (depthState == _FeedbackState.tooMuch) {
        _consecutiveTooDeep++;
        _consecutiveTooShallow = 0;
      }
      if (freqState == _FeedbackState.tooLittle) {
        _consecutiveTooSlow++;
        _consecutiveTooFast = 0;
      } else if (freqState == _FeedbackState.tooMuch) {
        _consecutiveTooFast++;
        _consecutiveTooSlow = 0;
      }
    }
  }

  Widget _buildCoachingHint(
      _FeedbackState depthState, _FeedbackState freqState) {
    final depthTarget = widget.scenario == CprScenario.pediatric
        ? '4–5 cm' : '5–6 cm';
    final rateMin = widget.scenario.targetRateMin;
    final rateMax = widget.scenario.targetRateMax;

    String? message;
    Color   color = AppColors.cprOrange;

    // Only show after threshold consecutive bad compressions
    if (_consecutiveTooShallow >= _kCoachingThreshold) {
      message = 'Push deeper — aim for $depthTarget';
      color   = AppColors.cprOrange;
    } else if (_consecutiveTooDeep >= _kCoachingThreshold) {
      message = 'Ease up — you\'re going too deep';
      color   = AppColors.cprRed;
    } else if (_consecutiveTooSlow >= _kCoachingThreshold) {
      message = 'Speed up — aim for $rateMin–$rateMax per min';
      color   = AppColors.cprOrange;
    } else if (_consecutiveTooFast >= _kCoachingThreshold) {
      message = 'Slow down — above $rateMax per min';
      color   = AppColors.cprRed;
    } else if (_consecutiveGood >= _kCoachingThreshold) {
      message = 'Great technique — keep it up!';
      color   = AppColors.cprGreenBright;
    }

    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding, 0,
        AppSpacing.cardPadding, AppSpacing.sm,
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.label(size: 12, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final depthState = _depthFeedback(widget.depth);
    final freqState  = _freqFeedback(widget.frequency);
    if (widget.isSessionActive && !widget.isNoFeedback &&
        widget.compressionCount != _lastCompressionCount) {
      _lastCompressionCount = widget.compressionCount;
      _updateConsecutiveCounts(depthState, freqState);
    }

    return Container(
      decoration: BoxDecoration(
        color:        AppColors.cprCardBg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusLg),
        boxShadow: const [
          BoxShadow(
            color:      AppColors.shadowMedium,
            blurRadius: 16,
            offset:     Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

// ── A) Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.cardPadding,
              AppSpacing.cardPadding,
              AppSpacing.cardPadding,
              AppSpacing.sm,
            ),
            child: IntrinsicHeight(
              child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Timer block (first) ────────────────────────────────
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
                ),
                decoration: AppDecorations.cprStatBlock(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.cprTime.mmss,
                        style: AppTypography.poppins(
                          size:   32,
                          weight: FontWeight.w700,
                          color:  AppColors.textOnDark,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SessionDot(isActive: widget.isSessionActive),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'CPR TIME',
                            style: AppTypography.badge(
                              size:  9,
                              color: AppColors.textOnDark.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
              ),
            ),

            const SizedBox(width: AppSpacing.sm),

            // ── Compressions block (second) ───────────────────────
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm,
                ),
                decoration: AppDecorations.cprStatBlock(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.compressionCount.toString(),
                      style: AppTypography.poppins(
                        size:   32,
                        weight: FontWeight.w700,
                        color:  AppColors.textOnDark,
                      ),
                    ),
                    Text(
                      'COMPRESSIONS',
                      style: AppTypography.badge(
                        size:  9,
                        color: AppColors.textOnDark.withValues(alpha: 0.55),
                      ),
                    ),
                    if (widget.isSessionActive && widget.compressionInCycle > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          // Counter label
                          Text(
                            '${widget.compressionInCycle}/30',
                            style: AppTypography.badge(
                              size:  9,
                              color: widget.compressionInCycle >= 26
                                  ? AppColors.cprOrange
                                  : AppColors.textOnDark.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          // Progress bar fills remaining space
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppSpacing.xxs),
                              child: LinearProgressIndicator(
                                value:           widget.compressionInCycle / 30,
                                minHeight:       4,
                                backgroundColor: AppColors.textOnDark.withValues(alpha: 0.15),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  widget.compressionInCycle >= 26
                                      ? AppColors.cprOrange
                                      : AppColors.cprGreenBright,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    ),
// ── Calibration strip — shown during first seconds of session ─────
          if (widget.isSessionActive && !widget.imuCalibrated)
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding, AppSpacing.xs,
                AppSpacing.cardPadding, 0,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical:   AppSpacing.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width:  AppSpacing.iconSm,
                    height: AppSpacing.iconSm,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Calibrating...',
                    style: AppTypography.label(size: 11, color: AppColors.warning),
                  ),
                ],
              ),
            ),

          // ── B) Gauge row ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.cardPadding,
              AppSpacing.md,
              AppSpacing.cardPadding,
              AppSpacing.sm,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.center,
                        child: _FrequencyGauge(frequency: widget.frequency, state: freqState),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _DepthColumn(
                          depth:          widget.depth,
                          peakDepth:      widget.peakDepth,
                          state:          depthState,
                          recoilAchieved: widget.recoilAchieved,
                          scenario:       widget.scenario,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Coaching hint — shown when something is off ───────────────────
          if (widget.isSessionActive && !widget.isNoFeedback)
            _buildCoachingHint(depthState, freqState),

          // ── C) Status bar — active sessions only ─────────────────────────
          if (widget.isSessionActive && !widget.isNoFeedback)
            Container(
              margin: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + AppSpacing.xs,
                vertical:   AppSpacing.sm,
              ),
              decoration: AppDecorations.darkInnerContainer(),
              child: Row(
                children: [
                  Expanded(
                    child: _FeedbackLabel(
                      state:         freqState,
                      goodText:      'GOOD RATE',
                      tooLittleText: 'TOO SLOW',
                      tooMuchText:   'TOO FAST',
                    ),
                  ),
                  Container(
                    width:  AppSpacing.dividerThickness,
                    height: 20,
                    color:  AppColors.textOnDark.withValues(alpha: 0.15),
                  ),
                  Expanded(
                    child: _FeedbackLabel(
                      state:         depthState,
                      goodText:      'GOOD DEPTH',
                      tooLittleText: 'TOO SHALLOW',
                      tooMuchText:   'TOO DEEP',
                      alignRight:    true,
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(height: AppSpacing.cardPadding),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SessionDot — pulsing green when active, grey when idle
// ─────────────────────────────────────────────────────────────────────────────

class _SessionDot extends StatefulWidget {
  final bool isActive;
  const _SessionDot({required this.isActive});

  @override
  State<_SessionDot> createState() => _SessionDotState();
}

class _SessionDotState extends State<_SessionDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.isActive) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _SessionDot old) {
    super.didUpdateWidget(old);
    if (widget.isActive == old.isActive) return;
    if (widget.isActive) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? AppColors.cprGreenBright : AppColors.textDisabled;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width:  AppSpacing.sessionDotSize,
        height: AppSpacing.sessionDotSize,
          decoration: AppDecorations.sessionDot(
            color: color,
            glow:  widget.isActive,
          ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeedbackState
// ─────────────────────────────────────────────────────────────────────────────

enum _FeedbackState { idle, good, tooLittle, tooMuch }

extension _FeedbackStateX on _FeedbackState {
  // tooLittle = orange (needs more effort — correctable)
  // tooMuch   = red    (dangerous — back off)
  Color get color {
    switch (this) {
      case _FeedbackState.good:      return AppColors.cprGreenBright;
      case _FeedbackState.tooLittle: return AppColors.cprOrange;
      case _FeedbackState.tooMuch:   return AppColors.cprRed;
      case _FeedbackState.idle:      return AppColors.textOnDark;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeedbackLabel
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackLabel extends StatelessWidget {
  final _FeedbackState state;
  final String         goodText;
  final String         tooLittleText;
  final String         tooMuchText;
  final bool           alignRight;

  const _FeedbackLabel({
    required this.state,
    required this.goodText,
    required this.tooLittleText,
    required this.tooMuchText,
    this.alignRight = false,
  });

  String get _text {
    switch (state) {
      case _FeedbackState.good:      return goodText;
      case _FeedbackState.tooLittle: return tooLittleText;
      case _FeedbackState.tooMuch:   return tooMuchText;
      case _FeedbackState.idle:      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = state.color;

    return Padding(
      padding: EdgeInsets.only(
        left:  alignRight ? AppSpacing.sm : 0,
        right: alignRight ? 0 : AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment:
        alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!alignRight) ...[
            Container(
              width:  AppSpacing.xs,
              height: AppSpacing.md,
              decoration: BoxDecoration(
                color:        color,
                borderRadius: BorderRadius.circular(AppSpacing.xxs),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            _text,
            style: AppTypography.badge(size: 10, color: color),
          ),
          if (alignRight) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              width:  AppSpacing.xs,
              height: AppSpacing.md,
              decoration: BoxDecoration(
                color:        color,
                borderRadius: BorderRadius.circular(AppSpacing.xxs),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FrequencyGauge
// ─────────────────────────────────────────────────────────────────────────────

class _FrequencyGauge extends StatelessWidget {
  final double         frequency;
  final _FeedbackState state;

  const _FrequencyGauge({required this.frequency, required this.state});

  @override
  Widget build(BuildContext context) {
    final valueColor = state == _FeedbackState.idle
        ? AppColors.textOnDark.withValues(alpha: 0.4)
        : state.color;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FREQUENCY',
          textAlign: TextAlign.center,
          style: AppTypography.badge(
            size:  10,
            color: AppColors.textOnDark.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Arc fills all available width; height driven by aspect ratio
        AspectRatio(
          aspectRatio: 1.1, // slightly wider than tall — adjust this to make taller/shorter
          child: FrequencyArcGauge(frequency: frequency),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          frequency > 0 ? frequency.toStringAsFixed(0) : '--',
          style: AppTypography.poppins(
            size:   28,
            weight: FontWeight.w700,
            color:  valueColor,
          ),
        ),
        Text(
          'CPM',
          style: AppTypography.badge(
            size:  9,
            color: AppColors.textOnDark.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DepthColumn
// ─────────────────────────────────────────────────────────────────────────────

class _DepthColumn extends StatelessWidget {
  final double         depth;
  final double         peakDepth;
  final _FeedbackState state;
  final bool           recoilAchieved;
  final CprScenario    scenario;

  static const double _barWidth  = AppSpacing.depthBarWidth;
  static const double _barHeight = AppSpacing.depthBarHeight;

  const _DepthColumn({
    required this.depth,
    required this.peakDepth,
    required this.state,
    required this.scenario,
    this.recoilAchieved = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = state == _FeedbackState.idle
        ? AppColors.textOnDark.withValues(alpha: 0.4)
        : state.color;

    return SizedBox(
      width: AppSpacing.depthBarWidth,
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'DEPTH',
            textAlign: TextAlign.center,
            style: AppTypography.badge(
              size:  10,
              color: AppColors.textOnDark.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width:  _barWidth,
            height: _barHeight,
            child: AnimatedDepthBar(
              depth:             depth,
              recoilAchieved:    recoilAchieved && depth > 0,
              targetDepthCm:     scenario.targetDepthMinCm,
              targetDepthMaxCm:  scenario.targetDepthMaxCm,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            peakDepth > 0 ? '${peakDepth.toStringAsFixed(1)} cm' : '--',
            style: AppTypography.poppins(
              size:   22,
              weight: FontWeight.w700,
              color:  valueColor,
            ),
          ),
          Text(
            'CM',
            style: AppTypography.badge(
              size:  9,
              color: AppColors.textOnDark.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}