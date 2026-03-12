import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../../../features/training/widgets/grade_dialog.dart';
import '../../training/screens/session_service.dart';
import '../../training/services/session_detail.dart';
import '../widgets/live_cpr_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LiveCPRScreen
//
// Card order (priority):
//   1. Patient Vitals  — top, most clinically urgent
//   2. CPR Metrics     — dominant card
//   3. Your Vitals     — bottom, secondary monitoring
// ─────────────────────────────────────────────────────────────────────────────

class LiveCPRScreen extends ConsumerStatefulWidget {
  final Function(int) onTabTapped;
  const LiveCPRScreen({super.key, required this.onTabTapped});

  @override
  ConsumerState<LiveCPRScreen> createState() => _LiveCPRScreenState();
}

class _LiveCPRScreenState extends ConsumerState<LiveCPRScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Display state ──────────────────────────────────────────────────────────

  bool     _isSessionActive         = false;
  bool     _hasHandledEndPing       = false;
  int      _displayCompressionCount = 0;
  Duration _displaySessionDuration  = Duration.zero;
  double   _displayDepth            = 0.0;
  double   _displayFrequency        = 0.0;

  // ── Vitals ─────────────────────────────────────────────────────────────────

  double? _heartRatePatient;
  double? _temperaturePatient;
  double? _heartRateUser;
  double? _temperatureUser;

  DateTime? _sessionStartTime;

  @override
  void dispose() {
    super.dispose();
  }

  // ── BLE data handler ───────────────────────────────────────────────────────

  void _updateDisplayValues(Map<String, dynamic> data) {
    final isStartPing   = data['startPing']       == true;
    final isEndPing     = data['endPing']         == true;
    final sessionActive = data['isSessionActive'] == true;

    _updateVitals(data);

    if (isStartPing) {
      setState(() {
        _isSessionActive         = true;
        _displayDepth            = 0.0;
        _displayFrequency        = 0.0;
        _displayCompressionCount = 0;
        _displaySessionDuration  = Duration.zero;
        _sessionStartTime        = DateTime.now();
        _hasHandledEndPing       = false;
      });
      return;
    }

    if (isEndPing && !_hasHandledEndPing) {
      setState(() {
        _isSessionActive   = false;
        _displayDepth      = 0.0;
        _displayFrequency  = 0.0;
        _hasHandledEndPing = true;
      });
      _handleSessionEnd(data);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSessionActive = sessionActive;
      if (data.containsKey('compressionCount')) {
        _displayCompressionCount = data['compressionCount'] as int;
      }
      if (data.containsKey('sessionDuration')) {
        _displaySessionDuration = data['sessionDuration'] as Duration;
      }
      if (_isSessionActive) {
        if (data.containsKey('depth')) {
          _displayDepth = (data['depth'] as num).toDouble();
        }
        if (data.containsKey('frequency')) {
          _displayFrequency = (data['frequency'] as num).toDouble();
        }
      }
    });
  }

  void _updateVitals(Map<String, dynamic> data) {
    double? readPositiveDouble(String key) {
      final raw = data[key];
      if (raw == null) return null;
      final v = (raw as num).toDouble();
      return v > 0 ? v : null;
    }

    final hrP   = readPositiveDouble('heartRatePatient');
    final tempP = readPositiveDouble('temperaturePatient');
    final hrU   = readPositiveDouble('heartRateUser');
    final tempU = readPositiveDouble('temperatureUser');

    if (hrP   != null && hrP   != _heartRatePatient   ||
        tempP  != null && tempP != _temperaturePatient ||
        hrU    != null && hrU   != _heartRateUser      ||
        tempU  != null && tempU != _temperatureUser) {
      setState(() {
        if (hrP   != null) _heartRatePatient   = hrP;
        if (tempP != null) _temperaturePatient  = tempP;
        if (hrU   != null) _heartRateUser       = hrU;
        if (tempU != null) _temperatureUser     = tempU;
      });
    }
  }

  // ── Session end + save ─────────────────────────────────────────────────────

  Future<void> _handleSessionEnd(Map<String, dynamic> data) async {
    final currentMode = ref.read(appModeProvider);
    final isLoggedIn  = ref.read(authStateProvider).isLoggedIn;
    final service     = SessionService(ref.read(networkServiceProvider));
    final bleConn     = ref.read(bleConnectionProvider);

    final detail = service.assembleDetail(
      summaryPacket:       data,
      events:              List.from(bleConn.compressionEvents),
      sessionStart:        _sessionStartTime ?? DateTime.now(),
      sessionDurationSecs: _displaySessionDuration.inSeconds,
    );

    if (currentMode == AppMode.emergency && !isLoggedIn) {
      if (!mounted) return;
      final confirmed = await AppDialogs.promptLogin(
        context,
        reason: 'Log in to save this session and track your progress.',
      );
      if (confirmed != true || !mounted) return;
      final nowLoggedIn = ref.read(authStateProvider).isLoggedIn;
      if (!nowLoggedIn) return;
    }

    final saved = await service.saveDetail(detail);
    if (!mounted) return;

    if (saved) {
      if (currentMode == AppMode.training) {
        _showGradeDialog(detail);
      } else {
        UIHelper.showSuccess(context, 'Session saved');
      }
    } else {
      UIHelper.showError(context, 'Failed to save session. Please check your connection.');
    }
  }

  void _showGradeDialog(SessionDetail session) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.overlayDark,
      builder: (_) => GradeDialog(session: session),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bleConnection = ref.watch(bleConnectionProvider);
    final currentMode   = ref.watch(appModeProvider);

    return ColoredBox(
      color: AppColors.screenBgGrey,
      child: Column(
        children: [
          if (currentMode == AppMode.training)
            const _TrainingModeBanner(),

          Expanded(
            child: StreamBuilder<Map<String, dynamic>>(
              stream: bleConnection.dataStream,
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _updateDisplayValues(snapshot.data!);
                  });
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      // 1. Patient vitals — most clinically urgent
                      VitalsCard(
                        label:       'Patient Vitals',
                        heartRate:   _heartRatePatient,
                        temperature: _temperaturePatient,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 2. CPR metrics — dominant card
                      LiveCprMetricsCard(
                        depth:            _displayDepth,
                        frequency:        _displayFrequency,
                        cprTime:          _displaySessionDuration,
                        compressionCount: _displayCompressionCount,
                        isSessionActive:  _isSessionActive,
                      ),
                      const SizedBox(height: AppSpacing.md),

                      // 3. Rescuer vitals — secondary monitoring
                      VitalsCard(
                        label:       'Your Vitals',
                        heartRate:   _heartRateUser,
                        temperature: _temperatureUser,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Training mode banner
// ─────────────────────────────────────────────────────────────────────────────

class _TrainingModeBanner extends StatelessWidget {
  const _TrainingModeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      decoration: AppDecorations.successCard(radius: 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.school_outlined,
            size:  AppSpacing.iconSm,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Training Mode — Performance will be graded',
            style: AppTypography.label(
              size:  13,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}