import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  final String  label;
  final double? heartRate;
  final double? temperature;
  final double? spO2;
  final int?    signalQuality; // 0–100; shown as signal dots on rescuer card

  const VitalsCard({
    super.key,
    required this.label,
    this.heartRate,
    this.temperature,
    this.spO2,
    this.signalQuality,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.poppins(
            size:   20,
            weight: FontWeight.bold,
            color:  AppColors.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            vertical:   AppSpacing.cardPadding,
            horizontal: AppSpacing.cardPadding,
          ),
          decoration: AppDecorations.card(),
            child: Row(
              children: [
                Expanded(
                  child: _VitalItem(
                    value: heartRate != null
                        ? '${heartRate!.toStringAsFixed(0)} bpm'
                        : '--',
                    label: 'HEART RATE',
                  ),
                ),
                Container(
                  width:  AppSpacing.dividerThickness,
                  height: AppSpacing.iconXl,
                  color:  AppColors.divider,
                ),
                Expanded(
                  child: _VitalItem(
                    value: spO2 != null
                        ? '${spO2!.toStringAsFixed(0)}%'
                        : '--',
                    label: 'SpO₂',
                    alignRight: false,
                  ),
                ),
                Container(
                  width:  AppSpacing.dividerThickness,
                  height: AppSpacing.iconXl,
                  color:  AppColors.divider,
                ),
                Expanded(
                  child: _VitalItem(
                    value: temperature != null
                        ? '${temperature!.toStringAsFixed(1)}°C'
                        : '--',
                    label:      'TEMPERATURE',
                    alignRight: true,
                  ),
                ),

                if (signalQuality != null) ...[
                  Container(
                    width:  AppSpacing.dividerThickness,
                    height: AppSpacing.iconXl,
                    color:  AppColors.divider,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(4, (i) {
                            final filled = (signalQuality! / 25).ceil() > i;
                            return Container(
                              width:  4,
                              height: 6 + (i * 3.0),
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: filled ? AppColors.success : AppColors.divider,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text('SIGNAL', style: AppTypography.poppins(size: 9, weight: FontWeight.w600, color: AppColors.textDisabled)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
        ),
      ],
    );
  }
}

class _VitalItem extends StatelessWidget {
  final String value;
  final String label;
  final bool   alignRight;

  const _VitalItem({
    required this.value,
    required this.label,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left:  alignRight ? AppSpacing.md : 0,
        right: alignRight ? 0 : AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.poppins(
              size:   20,
              weight: FontWeight.w600,
              color:  AppColors.vitalsValue,
            ),
          ),
          Text(
            label,
            style: AppTypography.poppins(
              size:   12,
              weight: FontWeight.w600,
              color:  AppColors.textDisabled,
            ),
          ),
        ],
      ),
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

class LiveCprMetricsCard extends StatelessWidget {
  final double      depth;
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
    required this.frequency,
    required this.cprTime,
    required this.compressionCount,
    required this.isSessionActive,
    this.recoilAchieved = false,   // ADD
    this.imuCalibrated    = true,
    this.showFatigueBadge = false,
    this.fatigueScore     = 0,
    required this.scenario,
    this.compressionInCycle = 0,
    this.isNoFeedback      = false,
  });

  // Depth feedback — adult AHA target: 5–6 cm
  _FeedbackState _depthFeedback(double d) {
    if (d <= 0)                       return _FeedbackState.idle;
    if (d < scenario.targetDepthMinCm) return _FeedbackState.bad;
    if (d <= scenario.targetDepthMaxCm) return _FeedbackState.good;
    return                              _FeedbackState.warn;
  }

  // Frequency feedback — adult AHA guideline: 100–120 CPM
  _FeedbackState _freqFeedback(double f) {
    if (f <= 0)   return _FeedbackState.idle;
    if (f < 100)  return _FeedbackState.bad;
    if (f <= 120) return _FeedbackState.good;
    return         _FeedbackState.warn;
  }

  Widget _buildCoachingHint(_FeedbackState depthState, _FeedbackState freqState) {
    String? message;
    Color   color = AppColors.cprOrange;

    final depthTarget = scenario == CprScenario.pediatric ? '4–5 cm' : '5–6 cm';

    if (depthState == _FeedbackState.bad) {
      message = 'Push deeper — aim for $depthTarget';
    } else if (depthState == _FeedbackState.warn) {
      message = 'Ease up slightly — too deep';
    } else if (freqState == _FeedbackState.bad) {
      message = 'Speed up — aim for ${scenario.targetRateMin}–${scenario.targetRateMax} per min';
    } else if (freqState == _FeedbackState.warn) {
      message = 'Slow down — you\'re above ${scenario.targetRateMax} per min';
    } else if (depthState == _FeedbackState.good && freqState == _FeedbackState.good) {
      message = 'Great technique — keep it up!';
      color   = AppColors.cprGreen;
    }

    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        0,
        AppSpacing.cardPadding,
        AppSpacing.sm,
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
    final depthState = _depthFeedback(depth);
    final freqState  = _freqFeedback(frequency);

    return Container(
      decoration: BoxDecoration(
        color:        AppColors.primaryDark,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _SessionDot(isActive: isSessionActive),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  cprTime.mmss,
                  style: AppTypography.poppins(
                    size:   38,
                    weight: FontWeight.w700,
                    color:  AppColors.textOnDark,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      compressionCount.toString(),
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
                    // Cycle counter — only when session active and in a cycle
                    if (isSessionActive && compressionInCycle > 0) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '$compressionInCycle / 30',
                        style: AppTypography.badge(
                          size:  9,
                          color: compressionInCycle >= 26
                              ? AppColors.cprOrange
                              : AppColors.textOnDark.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Separator
          Container(
            height: AppSpacing.dividerThickness,
            color:  AppColors.textOnDark.withValues(alpha: 0.08),
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
                        child: _FrequencyGauge(frequency: frequency, state: freqState),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _DepthColumn(
                          depth:          depth,
                          state:          depthState,
                          recoilAchieved: recoilAchieved,
                          scenario:       scenario,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Coaching hint — shown when something is off ───────────────────
          if (isSessionActive && !isNoFeedback)
            _buildCoachingHint(depthState, freqState),

          // ── Fatigue indicator ─────────────────────────────────────────────────
          if (showFatigueBadge && isSessionActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding, 0,
                AppSpacing.cardPadding, AppSpacing.xs,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color:        AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.trending_down_rounded,
                        size: 14, color: AppColors.warning),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Depth declining — press harder',
                        style: AppTypography.label(size: 11, color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── C) Status bar — active sessions only ─────────────────────────
          if (isSessionActive && !isNoFeedback)
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
                      state:    freqState,
                      goodText: 'GOOD RATE',
                      badText:  'TOO SLOW',
                      warnText: 'TOO FAST',
                    ),
                  ),
                  Container(
                    width:  AppSpacing.dividerThickness,
                    height: 20,
                    color:  AppColors.textOnDark.withValues(alpha: 0.15),
                  ),
                  Expanded(
                    child: _FeedbackLabel(
                      state:      depthState,
                      goodText:   'GOOD DEPTH',
                      badText:    'TOO SHALLOW',
                      warnText:   'TOO DEEP',
                      alignRight: true,
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
    final color = widget.isActive ? AppColors.cprGreen : AppColors.textDisabled;
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

enum _FeedbackState { idle, good, bad, warn }

extension _FeedbackStateX on _FeedbackState {
  Color get color {
    switch (this) {
      case _FeedbackState.good: return AppColors.cprGreen;
      case _FeedbackState.bad:  return AppColors.cprRed;
      case _FeedbackState.warn: return AppColors.cprOrange;
      case _FeedbackState.idle: return AppColors.textOnDark;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeedbackLabel
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackLabel extends StatelessWidget {
  final _FeedbackState state;
  final String         goodText;
  final String         badText;
  final String         warnText;
  final bool           alignRight;

  const _FeedbackLabel({
    required this.state,
    required this.goodText,
    required this.badText,
    required this.warnText,
    this.alignRight = false,
  });

  String get _text {
    switch (state) {
      case _FeedbackState.good: return goodText;
      case _FeedbackState.bad:  return badText;
      case _FeedbackState.warn: return warnText;
      case _FeedbackState.idle: return '';
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

  static const double _arcWidth  = 200.0;
  static const double _arcHeight = 110.0;

  const _FrequencyGauge({required this.frequency, required this.state});

  @override
  Widget build(BuildContext context) {
    final valueColor = state == _FeedbackState.idle
        ? AppColors.textOnDark.withValues(alpha: 0.4)
        : state.color;

    return SizedBox(
      width: _arcWidth,
      child: Column(
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
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              SvgPicture.asset(
                'assets/icons/frequency_arc.svg',
                width:  _arcWidth,
                height: _arcHeight,
              ),
              RotatingArrow(frequency: frequency),
            ],
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DepthColumn
// ─────────────────────────────────────────────────────────────────────────────

class _DepthColumn extends StatelessWidget {
  final double         depth;
  final _FeedbackState state;
  final bool           recoilAchieved;
  final CprScenario    scenario;

  static const double _barWidth  = AppSpacing.depthBarWidth;
  static const double _barHeight = AppSpacing.depthBarHeight;

  const _DepthColumn({
    required this.depth,
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
            child:  AnimatedDepthBar(
              depth:          depth,
              recoilAchieved: recoilAchieved,
              targetDepthCm:  scenario.targetDepthMinCm,  // ADD — already available on _DepthColumn via LiveCprMetricsCard

            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            depth > 0 ? '${depth.toStringAsFixed(1)} cm' : '--',
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