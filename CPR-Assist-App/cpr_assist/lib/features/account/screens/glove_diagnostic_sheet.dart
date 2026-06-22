import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../../../services/ble/ble_connection.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for one diagnostic sample row
// ─────────────────────────────────────────────────────────────────────────────

class _DiagSample {
  final int    timestampMs;
  final double force;
  final double depth;
  final int    rawFsrAdc;
  final double palmAccelMag;
  final double wristAccelMag;
  final double palmWristAngle;
  final double wristFlexion;
  final double hrPatient;
  final double spO2Patient;
  final int patientPI;
  final double ppgRaw;
  final int    ppgQuality;
  final double hrUser;
  final double spO2User;
  final int    rescuerQuality;
  final double rescuerPpgFiltered;
  final double patientTempC;
  final double rescuerTempC;
  final double rescuerHumidity;
  final int    batteryPct;
  final bool   isCharging;
  final int    palmWhoAmI;
  final int    wristWhoAmI;
  final int    i2cScanMask;

  _DiagSample({
    required this.timestampMs,
    required this.force,
    required this.depth,
    required this.rawFsrAdc,
    required this.palmAccelMag,
    required this.wristAccelMag,
    required this.palmWristAngle,
    required this.wristFlexion,
    required this.hrPatient,
    required this.spO2Patient,
    required this.patientPI,
    required this.ppgRaw,
    required this.ppgQuality,
    required this.hrUser,
    required this.spO2User,
    required this.rescuerQuality,
    required this.rescuerPpgFiltered,
    required this.patientTempC,
    required this.rescuerTempC,
    required this.rescuerHumidity,
    required this.batteryPct,
    required this.isCharging,
    required this.palmWhoAmI,
    required this.wristWhoAmI,
    required this.i2cScanMask,
  });

  List<String> toCsvRow() => [
    timestampMs.toString(),
    force.toStringAsFixed(2),
    depth.toStringAsFixed(2),
    rawFsrAdc.toString(),
    palmAccelMag.toStringAsFixed(4),
    wristAccelMag.toStringAsFixed(4),
    palmWristAngle.toStringAsFixed(1),
    wristFlexion.toStringAsFixed(1),
    hrPatient.toStringAsFixed(1),
    spO2Patient.toStringAsFixed(1),
    ppgRaw.toStringAsFixed(4),
    ppgQuality.toString(),
    patientPI.toString(),
    hrUser.toStringAsFixed(1),
    spO2User.toStringAsFixed(1),
    rescuerQuality.toString(),
    rescuerPpgFiltered.toStringAsFixed(4),
    patientTempC.toStringAsFixed(2),
    rescuerTempC.toStringAsFixed(2),
    rescuerHumidity.toStringAsFixed(1),
    batteryPct.toString(),
    isCharging ? '1' : '0',
    '0x${palmWhoAmI.toRadixString(16).padLeft(2,'0')}',
    '0x${wristWhoAmI.toRadixString(16).padLeft(2,'0')}',
    '0b${i2cScanMask.toRadixString(2).padLeft(6,'0')}',
  ];

  static String csvHeader() =>
      'timestamp_ms,force_N,depth_cm,raw_fsr_adc,palm_accel_mag_ms2,wrist_accel_mag_ms2,'
          'palm_wrist_angle_deg,wrist_flexion_deg,'
          'hr_patient_bpm,spo2_patient_pct,ppg_raw,ppg_quality,patient_pi,'
          'hr_user_bpm,spo2_user_pct,rescuer_quality,rescuer_ppg_filtered,'
          'patient_temp_C,rescuer_temp_C,rescuer_humidity_pct,'
          'battery_pct,is_charging,'
          'palm_who_am_i,wrist_who_am_i,i2c_scan_mask';
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared rolling buffer — lives for the lifetime of the diagnostic sheet so
// the "Download full log" button can dump everything seen across all
// component screens. Each component-screen state appends to this; the sheet
// reads on demand.
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalDiagBuffer {
  _GlobalDiagBuffer._();
  static final _GlobalDiagBuffer instance = _GlobalDiagBuffer._();

  static const int _maxRows = 3000;   // 2 minutes at 25 Hz
  final List<_DiagSample> _samples = [];

  void add(_DiagSample s) {
    _samples.add(s);
    if (_samples.length > _maxRows) _samples.removeAt(0);
  }

  void clear() => _samples.clear();

  List<_DiagSample> snapshot() => List<_DiagSample>.unmodifiable(_samples);
}

// ─────────────────────────────────────────────────────────────────────────────
// Component descriptor
// ─────────────────────────────────────────────────────────────────────────────

enum _DiagComponent {
  // Critical sensors
  fsr, imuPalm, imuWrist,
  // The combined compression-detection pipeline — most important test.
  // Verifies force + IMU + fusion all produce believable compressions.
  depthCombined,
  // Biosensors
  max30102Patient, max30102Rescuer,
  max30205, gxht30,
  // Feedback hardware
  dfplayer, motor, neopixel,
  // System
  battery, i2cBus, button,
}

extension _DiagComponentExt on _DiagComponent {
  String get label => switch (this) {
    _DiagComponent.fsr             => 'Compression Force Sensor',
    _DiagComponent.imuPalm         => 'Motion Sensor (Palm)',
    _DiagComponent.imuWrist        => 'Motion Sensor (Wrist)',
    _DiagComponent.depthCombined   => 'Compression Depth Pipeline',
    _DiagComponent.max30102Patient => 'Patient Pulse & Oxygen Sensor',
    _DiagComponent.max30102Rescuer => 'Rescuer Pulse & Oxygen Sensor',
    _DiagComponent.max30205        => 'Patient Temperature Sensor',
    _DiagComponent.gxht30          => 'Rescuer Temperature Sensor',
    _DiagComponent.dfplayer        => 'Audio Feedback',
    _DiagComponent.motor           => 'Vibration Feedback',
    _DiagComponent.neopixel        => 'LED Depth Bar',
    _DiagComponent.battery         => 'Battery',
    _DiagComponent.i2cBus          => 'Sensor Bus',
    _DiagComponent.button          => 'Mode Button',
  };

  bool get isCritical => switch (this) {
    _DiagComponent.fsr || _DiagComponent.imuPalm ||
    _DiagComponent.imuWrist || _DiagComponent.depthCombined => true,
    _ => false,
  };

  bool get hasCsvExport => switch (this) {
    _DiagComponent.dfplayer || _DiagComponent.motor ||
    _DiagComponent.neopixel || _DiagComponent.button => false,
    _ => true,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// GloveDiagnosticSheet — entry sheet showing all components
// ─────────────────────────────────────────────────────────────────────────────

class GloveDiagnosticSheet extends ConsumerStatefulWidget {
  final BLEConnection ble;
  const GloveDiagnosticSheet({super.key, required this.ble});

  @override
  ConsumerState<GloveDiagnosticSheet> createState() => _GloveDiagnosticSheetState();
}

class _GloveDiagnosticSheetState extends ConsumerState<GloveDiagnosticSheet> {
  // Last selftest mask (from provider or already-received packet)
  int _passMask    = 0;
  int _warnMask    = 0;
  int _critMask    = 0;
  int _battPct     = 0;
  int        _i2cScanMask    = 0;
  int        _palmWhoAmI     = 0;
  int        _wristWhoAmI    = 0;
  List<int>  _reasonCodes    = const [0, 0, 0, 0, 0, 0, 0, 0];
  bool _didRunQuickTest = false;
  StreamSubscription? _selfSub;
  StreamSubscription? _liveSub;
  bool _hasLogData = false;
  final Map<_DiagComponent, bool> _manualPassed = {};
  final Map<_DiagComponent, bool> _manualFailed = {};

  @override
  void initState() {
    super.initState();
    _runQuickSelftest();
    _GlobalDiagBuffer.instance.clear();
    _liveSub = widget.ble.dataStream.listen(_onLiveData);
  }

  @override
  void dispose() {
    _selfSub?.cancel();
    _liveSub?.cancel();
    super.dispose();
  }

  void _runQuickSelftest() {
    // Subscribe BEFORE sending the command so we never miss the result.
    _selfSub?.cancel();
    _selfSub = widget.ble.dataStream
        .where((d) => d['isSelftestResult'] == true)
        .take(1)
        .listen((d) {
      if (!mounted) return;
      setState(() {
        _passMask = (d['selftestPassMask']     as int?) ?? 0;
        _warnMask = (d['selftestWarnMask']     as int?) ?? 0;
        _critMask = (d['selftestCriticalMask'] as int?) ?? 0;
        _battPct  = (d['selftestBatteryPct']   as int?) ?? 0;
        _i2cScanMask = (d['selftestI2cScanMask'] as int?) ?? 0;
        _palmWhoAmI  = (d['selftestPalmWhoAmI']  as int?) ?? 0;
        _wristWhoAmI = (d['selftestWristWhoAmI'] as int?) ?? 0;
        _reasonCodes = ((d['selftestReasonCodes'] as List?) ?? const [])
            .cast<int>();
        if (_reasonCodes.length < 8) {
          _reasonCodes = List<int>.from(_reasonCodes)
            ..addAll(List<int>.filled(8 - _reasonCodes.length, 0));
        }
        _didRunQuickTest = true;
      });
    });
    widget.ble.sendRunSelftest();

    // Failsafe — if no result in 3s, mark "unknown" so UI doesn't hang.
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_didRunQuickTest) {
        setState(() { _didRunQuickTest = true; });
      }
    });
  }

  void _onLiveData(Map<String, dynamic> d) {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _GlobalDiagBuffer.instance.add(_DiagSample(
      timestampMs:        now,
      force:              (d['force']                   as double?) ?? 0.0,
      depth:              (d['depth']                   as double?) ?? 0.0,
      rawFsrAdc:          (d['diagRawFsrAdc']           as int?)    ?? 0,
      palmAccelMag:       (d['diagPalmAccelMag']        as double?) ?? 0.0,
      wristAccelMag:      (d['diagWristAccelMag']       as double?) ?? 0.0,
      rescuerPpgFiltered: (d['diagRescuerPpgFiltered']  as double?) ?? 0.0,
      palmWristAngle:     (d['wristAlignmentAngle']     as double?) ?? 0.0,
      wristFlexion:       (d['wristFlexionAngle']       as double?) ?? 0.0,
      hrPatient:          (d['heartRatePatient']        as double?) ?? 0.0,
      spO2Patient:        (d['spO2Patient']             as double?) ?? 0.0,
      ppgRaw:             (d['ppgRaw']                  as double?) ?? 0.0,
      ppgQuality:         (d['ppgSignalQuality']        as int?)    ?? 0,
      patientPI:          (d['perfusionIndex']          as int?)    ?? 0,
      hrUser:             (d['heartRateUser']           as double?) ?? 0.0,
      spO2User:           (d['spO2User']               as double?) ?? 0.0,
      rescuerQuality:     (d['rescuerSignalQuality']    as int?)    ?? 0,
      patientTempC:       (d['patientTemperature']      as double?) ?? 0.0,
      rescuerTempC:       (d['rescuerTemperature']      as double?) ?? 0.0,
      rescuerHumidity:    ((d['rescuerHumidity'] as int?) ?? 0).toDouble(),
      batteryPct:         (d['batteryPercentage']       as int?)    ?? 0,
      isCharging:         (d['isCharging']              as bool?)   ?? false,
      palmWhoAmI:         (d['diagPalmWhoAmI']          as int?)   ?? 0,
      wristWhoAmI:        (d['diagWristWhoAmI']         as int?)   ?? 0,
      i2cScanMask:        (d['diagI2cScanMask']         as int?)   ?? 0,
    ));
    if (!_hasLogData) setState(() => _hasLogData = true);
  }

  void _showAllResultsDialog() {
    const names = [
      'Motion sensor (Palm)',
      'Motion sensor (Wrist)',
      'Compression force sensor',
      'Patient pulse sensor',
      'Rescuer pulse sensor',
      'Patient temperature sensor',
      'Rescuer temperature sensor',
      'Audio feedback',
    ];

    String reasonText(int code) => switch (code) {
      0x01 => 'No I²C ACK — check solder / power',
      0x02 => 'TCA9548A channel did not respond',
      0x03 => 'Chip ID wrong (address conflict or wrong part)',
      0x04 => 'Reading out of plausible range',
      0x05 => 'Calibration baseline failed',
      0x06 => 'DFPlayer UART no reply — check TX/RX',
      0x07 => 'Sensor task did not release I²C mutex',
      0xFF => 'Not tested',
      _    => '',
    };

    final failed = <SelftestRow>[];
    final warns  = <SelftestRow>[];
    final passed = <SelftestRow>[];

    for (int i = 0; i < names.length; i++) {
      final reason = (i < _reasonCodes.length) ? _reasonCodes[i] : 0;
      final detail = reasonText(reason);
      if (_critMask & (1 << i) != 0) {
        failed.add(SelftestRow(name: names[i], reason: detail));
      } else if (_warnMask & (1 << i) != 0) {
        warns.add(SelftestRow(name: names[i], reason: detail));
      } else if (_passMask & (1 << i) != 0) {
        passed.add(SelftestRow(name: names[i]));
      }
    }

    AppDialogs.showSelftestResults(
      context,
      failed:     failed,
      warns:      warns,
      passed:     passed,
      batteryPct: _battPct,
    );
  }

  // Maps each component to a selftest bit (null = not in selftest mask)
  int? _selftestBit(_DiagComponent c) => switch (c) {
    _DiagComponent.imuPalm         => 0,
    _DiagComponent.imuWrist        => 1,
    _DiagComponent.fsr             => 2,
    _DiagComponent.max30102Patient => 3,
    _DiagComponent.max30102Rescuer => 4,
    _DiagComponent.max30205        => 5,
    _DiagComponent.gxht30          => 6,
    _DiagComponent.dfplayer        => 7,
    _ => null,
  };

  // PASS / WARN / FAIL / UNKNOWN from selftest masks
  ({Color color, IconData icon, String label}) _statusFor(_DiagComponent c) {
    if (_manualFailed[c] == true) {
      return (color: AppColors.error, icon: Icons.cancel_rounded, label: 'FAIL');
    }
    if (_manualPassed[c] == true) {
      return (color: AppColors.success, icon: Icons.check_circle_rounded, label: 'PASS');
    }
    final bit = _selftestBit(c);
    if (!_didRunQuickTest || bit == null) {
      return (color: AppColors.textDisabled, icon: Icons.help_outline_rounded, label: '—');
    }
    if (_critMask & (1 << bit) != 0) {
      return (color: AppColors.error, icon: Icons.cancel_rounded, label: 'FAIL');
    }
    if (_warnMask & (1 << bit) != 0) {
      return (color: AppColors.warning, icon: Icons.warning_amber_rounded, label: 'WARN');
    }
    if (_passMask & (1 << bit) != 0) {
      return (color: AppColors.success, icon: Icons.check_circle_rounded, label: 'PASS');
    }
    return (color: AppColors.textDisabled, icon: Icons.help_outline_rounded, label: '—');
  }

  // Depth combined doesn't have a single selftest bit — it rolls up the
  // status of FSR + both IMUs. If any of those failed, depth is FAIL.
  // If they're all PASS, we report UNKNOWN until the user runs the
  // guided test inside the component screen (where actual compression
  // events can be measured).
  ({Color color, IconData icon, String label}) _statusForDepthCombined() {
    if (!_didRunQuickTest) {
      return (color: AppColors.textDisabled, icon: Icons.help_outline_rounded, label: '—');
    }
    const upstream = [0 /* IMU palm */, 1 /* IMU wrist */, 2 /* FSR */];
    final anyCrit = upstream.any((b) => _critMask & (1 << b) != 0);
    if (anyCrit) {
      return (color: AppColors.error, icon: Icons.cancel_rounded, label: 'BLOCKED');
    }
    return (color: AppColors.textDisabled, icon: Icons.play_circle_outline_rounded, label: 'TEST');
  }

  // Download a CSV with all signals captured since the diagnostic sheet
  // was opened. Uses share_plus so the user can pick where it goes
  // (mail, Files, Drive, etc.) — OpenFilex alone leaves the file in a
  // temp directory the user can't reach on most phones.
  Future<void> _downloadFullLog() async {
    final samples = _GlobalDiagBuffer.instance.snapshot();
    if (samples.isEmpty) {
      UIHelper.showInfo(context,
          'No data captured yet. Open a component to start streaming.');
      return;
    }
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final name = 'cpr_glove_diag_full_$ts.csv';
    final sb   = StringBuffer()..writeln(_DiagSample.csvHeader());
    for (final s in samples) {
      sb.writeln(s.toCsvRow().join(','));
    }
    final bytes = Uint8List.fromList(sb.toString().codeUnits);
    try {
      if (Platform.isAndroid) {
        const downloadsPath = '/storage/emulated/0/Download';
        final dir = Directory(downloadsPath);
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('$downloadsPath/$name');
        await file.writeAsBytes(bytes);
        if (mounted) UIHelper.showSuccess(context, 'Saved to Downloads: $name');
        await OpenFilex.open(file.path);
      } else {
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv', name: name)],
          subject: 'CPR Assist — Glove diagnostic full log',
        );
      }
    } catch (e) {
      if (mounted) UIHelper.showError(context, 'Export failed: $e');
    }
  }

  void _openComponent(_DiagComponent component) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ComponentTestScreen(
          ble:           widget.ble,
          component:     component,
          onManualPass:  () => setState(() => _manualPassed[component] = true),
          onManualFail:  () => setState(() => _manualFailed[component] = true),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, ctrl) => Container(
        decoration: AppDecorations.card().copyWith(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSpacing.cardRadius)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Glove Diagnostics', style: AppTypography.heading(size: 18)),
                        if (_didRunQuickTest)
                          Text(
                            'Battery: $_battPct% \nTap a component to run live tests',
                            style: AppTypography.caption(),
                          )
                        else
                          Text('Running quick check…', style: AppTypography.caption()),
                      ],
                    ),
                  ),
                  IconButton(
                    icon:    const Icon(Icons.download_rounded),
                    color:   _hasLogData ? AppColors.primary : AppColors.textDisabled,
                    tooltip: _hasLogData
                        ? 'Download full diagnostic log'
                        : 'No data yet — open a component first',
                    onPressed: _hasLogData ? _downloadFullLog : null,
                  ),
                  IconButton(
                    icon:    const Icon(Icons.refresh_rounded),
                    color:   AppColors.primary,
                    tooltip: 'Re-run quick check',
                    onPressed: () {
                      setState(() { _didRunQuickTest = false; });
                      _runQuickSelftest();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
            // Component list
            Expanded(
              child: ListView(
                controller: ctrl,
                padding: EdgeInsets.only(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.sm + bottomInset,
                ),
                children: [
                  _diagSectionLabel('Quick Check'),
                  _AllComponentsTile(
                    status: _statusFor(_DiagComponent.imuPalm),  // any component as placeholder
                    passMask: _passMask,
                    warnMask: _warnMask,
                    critMask: _critMask,
                    battPct:  _battPct,
                    didRun:   _didRunQuickTest,
                    onTap:    () => _showAllResultsDialog(),
                  ),
                  _diagSectionLabel('Critical Sensors'),
                  ...[_DiagComponent.fsr, _DiagComponent.imuPalm, _DiagComponent.imuWrist]
                      .map((c) => _ComponentTile(
                    component: c,
                    status:    _statusFor(c),
                    onTap:     () => _openComponent(c),
                  )),
                  const Divider(height: 1, color: AppColors.divider),
                  _diagSectionLabel('Compression Pipeline'),
                  _ComponentTile(
                    component: _DiagComponent.depthCombined,
                    status:    _statusForDepthCombined(),
                    onTap:     () => _openComponent(_DiagComponent.depthCombined),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  _diagSectionLabel('Biosensors'),
                  ...[
                    _DiagComponent.max30102Patient, _DiagComponent.max30102Rescuer,
                    _DiagComponent.max30205, _DiagComponent.gxht30,
                  ].map((c) => _ComponentTile(
                    component: c,
                    status:    _statusFor(c),
                    onTap:     () => _openComponent(c),
                  )),
                  const Divider(height: 1, color: AppColors.divider),
                  _diagSectionLabel('Feedback Hardware'),
                  ...[_DiagComponent.dfplayer, _DiagComponent.motor, _DiagComponent.neopixel]
                      .map((c) => _ComponentTile(
                    component: c,
                    status:    _statusFor(c),
                    onTap:     () => _openComponent(c),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _diagSectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md, AppSpacing.md, AppSpacing.lg, AppSpacing.xs,
    ),
    child: Row(
      children: [
        Container(
          width: 4, height: 18,
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          label.toUpperCase(),
          style: AppTypography.overline(color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ComponentTile
// ─────────────────────────────────────────────────────────────────────────────

class _ComponentTile extends StatelessWidget {
  final _DiagComponent component;
  final ({Color color, IconData icon, String label}) status;
  final VoidCallback onTap;

  const _ComponentTile({
    required this.component,
    required this.status,
    required this.onTap,
  });


  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical:   AppSpacing.sm + AppSpacing.xxs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(component.label,
                              style: AppTypography.bodyMedium(size: 14)),
                        ],
                      ),
                    ),
                    // Status pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(status.icon, color: status.color, size: 12),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(status.label,
                              style: AppTypography.badge(color: status.color)),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppColors.textDisabled,
                        size:  AppSpacing.iconSm),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AllComponentsTile — runs the quick selftest and opens a result dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AllComponentsTile extends StatelessWidget {
  final ({Color color, IconData icon, String label}) status;
  final int  passMask;
  final int  warnMask;
  final int  critMask;
  final int  battPct;
  final bool didRun;
  final VoidCallback onTap;

  const _AllComponentsTile({
    required this.status,
    required this.passMask,
    required this.warnMask,
    required this.critMask,
    required this.battPct,
    required this.didRun,
    required this.onTap,
  });

  int _popcount(int n) {
    int c = 0;
    while (n != 0) { c += n & 1; n >>= 1; }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final passCount = _popcount(passMask);
    final warnCount = _popcount(warnMask);
    final critCount = _popcount(critMask);
    final tested    = passCount + warnCount + critCount;
    const total     = 8;

    final summary = !didRun
        ? (color: AppColors.textDisabled, icon: Icons.hourglass_empty_rounded, label: 'RUNNING')
        : (critCount > 0)
        ? (color: AppColors.error, icon: Icons.cancel_rounded, label: 'FAIL')
        : (warnCount > 0)
        ? (color: AppColors.warning, icon: Icons.warning_amber_rounded, label: 'WARN')
        : (color: AppColors.success, icon: Icons.check_circle_rounded, label: 'PASS');

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, vertical: AppSpacing.xs,
      ),
      decoration: AppDecorations.card().copyWith(
        // Hairline tint matching status — soft cue that this is the headline tile
        color: summary.color.withValues(alpha: 0.04),
      ),
      child: InkWell(
        onTap:        didRun ? onTap : null,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width:  AppSpacing.iconBoxSize,
                    height: AppSpacing.iconBoxSize,
                    decoration: AppDecorations.iconRounded(
                      bg:     summary.color.withValues(alpha: 0.15),
                      radius: AppSpacing.cardRadiusSm,
                    ),
                    child: Icon(summary.icon,
                        color: summary.color, size: AppSpacing.iconSm),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick check',
                            style: AppTypography.bodyMedium(size: 15)),
                        Text(
                          didRun
                              ? '$tested / $total sensors tested'
                              : 'Running quick check…',
                          style: AppTypography.caption(),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: summary.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                    ),
                    child: Text(summary.label,
                        style: AppTypography.badge(color: summary.color)),
                  ),
                ],
              ),
              if (didRun) ...[
                const SizedBox(height: AppSpacing.md),
                // Three little stat chips
                Row(
                  children: [
                    Expanded(child: _StatChip(
                      label: 'Passed', count: passCount, color: AppColors.success,
                    )),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _StatChip(
                      label: 'Warn',   count: warnCount, color: AppColors.warning,
                    )),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _StatChip(
                      label: 'Failed', count: critCount, color: AppColors.error,
                    )),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tap to see full results',
                  style: AppTypography.caption(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;
  const _StatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: count > 0
            ? color.withValues(alpha: 0.10)
            : AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
      ),
      child: Column(
        children: [
          Text('$count',
              style: AppTypography.heading(size: 18,
                  color: count > 0 ? color : AppColors.textDisabled)),
          Text(label,
              style: AppTypography.caption(
                  color: count > 0 ? color : AppColors.textDisabled)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ComponentTestScreen — full-screen live test for one component
// ─────────────────────────────────────────────────────────────────────────────

class _ComponentTestScreen extends ConsumerStatefulWidget {
  final BLEConnection    ble;
  final _DiagComponent   component;
  final VoidCallback?    onManualPass;
  final VoidCallback? onManualFail;

  const _ComponentTestScreen({
    required this.ble,
    required this.component,
    this.onManualPass,
    this.onManualFail,
  });

  @override
  ConsumerState<_ComponentTestScreen> createState() => _ComponentTestScreenState();
}

class _ComponentTestScreenState extends ConsumerState<_ComponentTestScreen> {
  StreamSubscription? _dataSub;
  final List<_DiagSample> _buffer = [];
  _DiagSample? _latest;
  List<Widget>? _cachedBody;
  int _lastBodyRebuildMs = 0;
  bool _bodyDirty = true;

  // Action feedback
  String? _actionFeedback;
  bool    _actionPending = false;

  // Button press counter (for button test)
  int  _buttonPressCount = 0;
  int  _lastDiagAction   = 0;

  @override
  void initState() {
    super.initState();
    widget.ble.sendDiagStart();
    _dataSub = widget.ble.dataStream.listen(_onData);
  }

  @override
  void dispose() {
    widget.ble.sendDiagStop();
    _dataSub?.cancel();
    super.dispose();
  }

  void _onData(Map<String, dynamic> d) {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sample = _DiagSample(
      timestampMs:     now,
      force:           (d['force']            as double?) ?? 0.0,
      depth:           (d['depth']            as double?) ?? 0.0,
      rawFsrAdc:       (d['diagRawFsrAdc']    as int?)    ?? 0,
      palmAccelMag:    (d['diagPalmAccelMag']  as double?) ?? 0.0,
      wristAccelMag:   (d['diagWristAccelMag'] as double?) ?? 0.0,
      rescuerPpgFiltered: (d['diagRescuerPpgFiltered'] as double?) ?? 0.0,
      palmWristAngle:  (d['wristAlignmentAngle'] as double?) ?? 0.0,
      wristFlexion:    (d['wristFlexionAngle']   as double?) ?? 0.0,
      hrPatient:       (d['heartRatePatient']    as double?) ?? 0.0,
      spO2Patient:     (d['spO2Patient']         as double?) ?? 0.0,
      ppgRaw:          (d['ppgRaw']              as double?) ?? 0.0,
      ppgQuality:      (d['ppgSignalQuality']    as int?)    ?? 0,
      patientPI:       (d['perfusionIndex']      as int?)    ?? 0,
      hrUser:          (d['heartRateUser']        as double?) ?? 0.0,
      spO2User:        (d['spO2User']             as double?) ?? 0.0,
      rescuerQuality:  (d['rescuerSignalQuality'] as int?)    ?? 0,
      patientTempC:    (d['patientTemperature']   as double?) ?? 0.0,
      rescuerTempC:    (d['rescuerTemperature']   as double?) ?? 0.0,
      rescuerHumidity: ((d['rescuerHumidity'] as int?) ?? 0).toDouble(),
      batteryPct:      (d['batteryPercentage']    as int?)    ?? 0,
      isCharging:      (d['isCharging']           as bool?)   ?? false,
      palmWhoAmI:      (d['diagPalmWhoAmI']        as int?)   ?? 0,
      wristWhoAmI:     (d['diagWristWhoAmI']       as int?)   ?? 0,
      i2cScanMask:     (d['diagI2cScanMask']       as int?)   ?? 0,
    );

    // Track button presses via diagActionResult changing
    final actionResult = (d['diagActionResult'] as int?) ?? 0;
    if (widget.component == _DiagComponent.button &&
        actionResult != _lastDiagAction &&
        actionResult >= 0x10 && actionResult <= 0x1F) {
      _buttonPressCount++;
      _buttonPressTimes.add(now);
      if (_buttonPressTimes.length > 20) _buttonPressTimes.removeAt(0);
      _lastDiagAction = actionResult;
    }

    _buffer.add(sample);
    if (_buffer.length > AppConstants.diagCsvMaxRows) _buffer.removeAt(0);
    _GlobalDiagBuffer.instance.add(sample);

    // Dismiss action feedback after result changes
    if (_actionPending && actionResult != 0) {
      _actionPending = false;
      _actionFeedback = _actionResultLabel(actionResult);
      _bodyDirty = true;
      if (mounted) setState(() {});
      return;   // ← add this
    }

    _latest = sample;
    final nowMs = sample.timestampMs;
    if (nowMs - _lastBodyRebuildMs >= 200) {
      _lastBodyRebuildMs = nowMs;
      _bodyDirty = true;
      if (mounted) setState(() {});
    }
  }

  String _csvHeaderFor(_DiagComponent c) {
    switch (c) {
      case _DiagComponent.fsr:
        return 'timestamp_ms,force_N,depth_cm,raw_fsr_adc';
      case _DiagComponent.imuPalm:
        return 'timestamp_ms,palm_accel_mag_ms2,palm_wrist_angle_deg,wrist_flexion_deg,palm_who_am_i';
      case _DiagComponent.imuWrist:
        return 'timestamp_ms,wrist_accel_mag_ms2,palm_wrist_angle_deg,wrist_flexion_deg,wrist_who_am_i';
      case _DiagComponent.depthCombined:
        return 'timestamp_ms,force_N,depth_cm,raw_fsr_adc,palm_accel_mag_ms2,wrist_accel_mag_ms2';
      case _DiagComponent.max30102Patient:
        return 'timestamp_ms,hr_patient_bpm,spo2_patient_pct,ppg_raw,ppg_quality,patient_pi';
      case _DiagComponent.max30102Rescuer:
        return 'timestamp_ms,hr_user_bpm,spo2_user_pct,rescuer_ppg_filtered,rescuer_quality';
      case _DiagComponent.max30205:
        return 'timestamp_ms,patient_temp_C';
      case _DiagComponent.gxht30:
        return 'timestamp_ms,rescuer_temp_C,rescuer_humidity_pct';
      case _DiagComponent.battery:
        return 'timestamp_ms,battery_pct,is_charging';
      case _DiagComponent.i2cBus:
        return 'timestamp_ms,i2c_scan_mask';
      default:
        return _DiagSample.csvHeader();
    }
  }

  List<String> _csvRowFor(_DiagComponent c, _DiagSample s) {
    switch (c) {
      case _DiagComponent.fsr:
        return [s.timestampMs.toString(), s.force.toStringAsFixed(2),
          s.depth.toStringAsFixed(2), s.rawFsrAdc.toString()];
      case _DiagComponent.imuPalm:
        return [s.timestampMs.toString(), s.palmAccelMag.toStringAsFixed(4),
          s.palmWristAngle.toStringAsFixed(1), s.wristFlexion.toStringAsFixed(1),
          '0x${s.palmWhoAmI.toRadixString(16).padLeft(2,'0')}'];
      case _DiagComponent.imuWrist:
        return [s.timestampMs.toString(), s.wristAccelMag.toStringAsFixed(4),
          s.palmWristAngle.toStringAsFixed(1), s.wristFlexion.toStringAsFixed(1),
          '0x${s.wristWhoAmI.toRadixString(16).padLeft(2,'0')}'];
      case _DiagComponent.depthCombined:
        return [s.timestampMs.toString(), s.force.toStringAsFixed(2),
          s.depth.toStringAsFixed(2), s.rawFsrAdc.toString(),
          s.palmAccelMag.toStringAsFixed(4), s.wristAccelMag.toStringAsFixed(4)];
      case _DiagComponent.max30102Patient:
        return [s.timestampMs.toString(), s.hrPatient.toStringAsFixed(1),
          s.spO2Patient.toStringAsFixed(1), s.ppgRaw.toStringAsFixed(4),
          s.ppgQuality.toString(), s.patientPI.toString()];
      case _DiagComponent.max30102Rescuer:
        return [s.timestampMs.toString(), s.hrUser.toStringAsFixed(1),
          s.spO2User.toStringAsFixed(1), s.rescuerPpgFiltered.toStringAsFixed(4),
          s.rescuerQuality.toString()];
      case _DiagComponent.max30205:
        return [s.timestampMs.toString(), s.patientTempC.toStringAsFixed(2)];
      case _DiagComponent.gxht30:
        return [s.timestampMs.toString(), s.rescuerTempC.toStringAsFixed(2),
          s.rescuerHumidity.toStringAsFixed(1)];
      case _DiagComponent.battery:
        return [s.timestampMs.toString(), s.batteryPct.toString(),
          s.isCharging ? '1' : '0'];
      case _DiagComponent.i2cBus:
        return [s.timestampMs.toString(),
          '0b${s.i2cScanMask.toRadixString(2).padLeft(6,'0')}'];
      default:
        return s.toCsvRow();
    }
  }

  String _actionResultLabel(int r) => switch (r) {
    0x01 => '✓ Audio played',
    0x02 => '✓ Motor fired',
    0x03 => '✓ LED test ran',
    0x04 => '✓ I²C scan done',
    _    => '✓ Done',
  };

  Future<void> _exportCsv() async {
    if (_buffer.isEmpty) {
      UIHelper.showInfo(context, 'No samples captured yet.');
      return;
    }
    final name = 'diag_${widget.component.name}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final sb = StringBuffer()..writeln(_csvHeaderFor(widget.component));
    for (final row in _buffer) {
      sb.writeln(_csvRowFor(widget.component, row).join(','));
    }
    final bytes = Uint8List.fromList(sb.toString().codeUnits);
    try {
      if (Platform.isAndroid) {
        // Direct save to Downloads — bypasses the share sheet on Android
        // because the share-sheet flow on some phones doesn't include a
        // "Save to device" target, and people expect Downloads.
        const downloadsPath = '/storage/emulated/0/Download';
        final dir = Directory(downloadsPath);
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('$downloadsPath/$name');
        await file.writeAsBytes(bytes);
        if (mounted) {
          UIHelper.showSuccess(context, 'Saved to Downloads: $name');
        }
        await OpenFilex.open(file.path);
      } else {
        // iOS: share sheet (which includes "Save to Files")
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv', name: name)],
          subject: 'CPR Assist — Glove diagnostic ${widget.component.name}',
        );
      }
    } catch (e) {
      if (mounted) {
        UIHelper.showError(context, 'Export failed: $e');
      }
    }
  }

  Future<void> _sendAction(int actionCode, {int param = 0}) async {
    setState(() {
      _actionPending  = true;
      _actionFeedback = null;
      _bodyDirty = true;
    });
    await widget.ble.sendDiagAction(actionCode, param: param);
  }

  List<double> _lastN(Iterable<double> src, {int n = 250}) {
    final list = List<double>.unmodifiable(src.toList());
    if (list.length <= n) return list;
    return list.sublist(list.length - n);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final c = widget.component;
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.white,
        foregroundColor:        AppColors.textPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Text(c.label, style: AppTypography.heading(size: 16)),
        actions: [
          if (c.hasCsvExport)
            IconButton(
              icon:    const Icon(Icons.download_rounded),
              color:   AppColors.primary,
              tooltip: 'Export CSV',
              onPressed: _exportCsv,
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
        ),
      ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.lg,
            ),
        children: [
          if (_actionFeedback != null) _ActionFeedbackBanner(message: _actionFeedback!),
          ..._getBody(c),
        ],
      ),
        ),
    );
  }

  List<Widget> _getBody(_DiagComponent c) {
    if (_bodyDirty || _cachedBody == null) {
      _cachedBody = _buildBody(c);
      _bodyDirty = false;
    }
    return _cachedBody!;
  }

  List<Widget> _buildBody(_DiagComponent c) {
    return switch (c) {
      _DiagComponent.fsr             => _buildFsr(),
      _DiagComponent.imuPalm         => _buildImu(palm: true),
      _DiagComponent.imuWrist        => _buildImu(palm: false),
      _DiagComponent.depthCombined   => _buildDepthCombined(),
      _DiagComponent.max30102Patient => _buildPpgPatient(),
      _DiagComponent.max30102Rescuer => _buildPpgRescuer(),
      _DiagComponent.max30205        => _buildTempPatient(),
      _DiagComponent.gxht30          => _buildGxht30(),
      _DiagComponent.dfplayer        => _buildDfplayer(),
      _DiagComponent.motor           => _buildMotor(),
      _DiagComponent.neopixel        => _buildNeopixel(),
      _DiagComponent.battery         => _buildBattery(),
      _DiagComponent.i2cBus          => _buildI2cBus(),
      _DiagComponent.button          => _buildButton(),
    };
  }

  // ── FSR ───────────────────────────────────────────────────────────────────

  List<Widget> _buildFsr() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    final rawOk = s != null && s.rawFsrAdc > 10 && s.rawFsrAdc < 4085;
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Raw ADC', s == null ? '—' : '${s.rawFsrAdc}', unit: '/ 4095'),
        _DiagRow('Force', s == null ? '—' : s.force.toStringAsFixed(1), unit: 'N'),
        _DiagRow('Depth (force model)', s == null ? '—' : s.depth.toStringAsFixed(1), unit: 'cm'),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('ADC not stuck at 0', s != null && s.rawFsrAdc > 10,
            hint: 'ADC=0 → broken GND or op-amp power fault'),
        _CheckRow('ADC not stuck at max', s != null && s.rawFsrAdc < 4085,
            hint: 'ADC=4095 → VREF short or op-amp fault'),
        _CheckRow('Force reads ≈ 0 at rest', s != null && s.force < 2.0,
            hint: 'Non-zero at rest → baseline not calibrated or sensor pre-loaded'),
        _CheckRow('Raw in sane range', rawOk,
            hint: 'Should be 50–500 at rest depending on op-amp gain'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: 'Press the force sensor with your finger. Aim for at least '
            '${AppConstants.diagFsrTestMinForceN.toStringAsFixed(0)} N peak.',
        icon:        Icons.pan_tool_rounded,
        window:      AppConstants.diagTestWindow,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          if (window.isEmpty) {
            return (passed: false, message: 'No samples received');
          }
          final peak = window.fold<double>(0, (m, x) => x.force > m ? x.force : m);
          if (peak >= AppConstants.diagFsrTestMinForceN) {
            return (passed: true, message: 'Peak ${peak.toStringAsFixed(1)} N ✓');
          }
          return (passed: false,
          message: 'Only reached ${peak.toStringAsFixed(1)} N — sensor unresponsive or unloaded');
        },
      ),
      _MultiTraceSparkline(
        title: 'Force (N, last 10 s)',
        traces: [
          _Trace(
            label: 'Force',
            color: AppColors.primary,
            points: _lastN(snapshot.map((s) => s.force)),
          ),
        ],
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Force', unit: 'N',     value: (s) => s.force,     fractionDigits: 1),
          _HistoryColumn(header: 'ADC',   unit: '',      value: (s) => s.rawFsrAdc.toDouble(), fractionDigits: 0),
          _HistoryColumn(header: 'Depth', unit: 'cm',    value: (s) => s.depth,     fractionDigits: 1),
        ],
      ),
      _HintCard(
        'Press the force sensor with your finger and watch the ADC and Force values rise. '
            'If ADC stays at 0: check MCP6002 power (pin 8 → 3.3V) and GND. '
            'If ADC stays at 4095: check VREF divider (10kΩ + 2kΩ). '
            'If Force reads non-zero at rest: run Recalibrate sensors from Settings.',
      ),
    ];
  }

  // ── IMU ───────────────────────────────────────────────────────────────────

  List<Widget> _buildImu({required bool palm}) {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    final whoAmI   = palm ? s?.palmWhoAmI  : s?.wristWhoAmI;
    final whoOk    = whoAmI == AppConstants.lsm6dsoxWhoAmIExpected;
    final accelMag = palm ? (s?.palmAccelMag ?? 0.0) : (s?.wristAccelMag ?? 0.0);
    final gravOk   = accelMag > 9.0 && accelMag < 10.5;
    final label    = palm ? 'Palm' : 'Wrist';
    final angleVal = palm ? (s?.palmWristAngle ?? 0.0) : (s?.wristFlexion ?? 0.0);
    final angleLabel = palm ? 'Alignment angle' : 'Wrist flexion';
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('WHO_AM_I register',
            whoAmI == null ? '—' : '0x${whoAmI.toRadixString(16).padLeft(2,'0').toUpperCase()}'),
        _DiagRow('Accel magnitude', s == null ? '—' : accelMag.toStringAsFixed(3), unit: 'm/s²'),
        _DiagRow('Wrist alignment angle', s == null ? '—' : '${s.palmWristAngle.toStringAsFixed(1)}°'),
        _DiagRow('Wrist flexion', s == null ? '—' : '${s.wristFlexion.toStringAsFixed(1)}°'),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('WHO_AM_I = 0x6C (LSM6DSOX)', whoOk,
            hint: 'Wrong value → I²C mismatch, address conflict, or SDA/SCL swap'),
        _CheckRow('IMU responding', whoAmI != null && whoAmI != 0x00 && whoAmI != 0xFF,
            hint: '0x00 = no ACK / 0xFF = bus error → check solder on SDA/SCL, TCA channel ${palm ? 0 : 1}'),
        _CheckRow('Gravity ≈ 9.81 m/s² at rest', gravOk,
            hint: 'Far from 9.81 → chip not calibrated or axes swapped'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: palm
            ? 'Tilt the glove sideways at least 30° from flat.'
            : 'Bend your wrist forward at least 30°.',
        icon:        Icons.screen_rotation_rounded,
        window:      AppConstants.diagTestWindow,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          if (window.length < 2) return (passed: false, message: 'No samples');
          final angles = window.map((s) =>
          palm ? s.palmWristAngle : s.wristFlexion).toList();
          final minA = angles.reduce((a, b) => a < b ? a : b);
          final maxA = angles.reduce((a, b) => a > b ? a : b);
          final swing = (maxA - minA).abs();
          if (swing >= AppConstants.diagImuTestMinSwingDeg) {
            return (passed: true,
            message: 'Angle swing ${swing.toStringAsFixed(0)}° ✓');
          }
          return (passed: false,
          message: 'Only ${swing.toStringAsFixed(0)}° detected — IMU unresponsive or axis swap');
        },
      ),
      _MultiTraceSparkline(
        title: '$label IMU — accel + angle',
        traces: [
          _Trace(
            label: 'Accel (m/s²)',
            color: AppColors.warning,
            points:_lastN(snapshot.map((s) =>
            palm ? s.palmAccelMag : s.wristAccelMag)),
          ),
          _Trace(
            label: '$angleLabel (°)',
            color: AppColors.primary,
            points:_lastN(snapshot.map((s) =>
            palm ? s.palmWristAngle : s.wristFlexion)),
          ),
        ],
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Accel', unit: 'm/s²',
              value: (s) => palm ? s.palmAccelMag : s.wristAccelMag, fractionDigits: 2),
          _HistoryColumn(header: 'Angle', unit: '°',
              value: (s) => palm ? s.palmWristAngle : s.wristFlexion, fractionDigits: 1),
        ],
      ),
      _HintCard(
        '$label IMU on I²C address 0x${palm ? '6B' : '6A'} via TCA channel ${palm ? 0 : 1}. '
            'WHO_AM_I should always return 0x6C. '
            'If 0x00: no device responding — check SDA/SCL solder on the TCA output for channel ${palm ? 0 : 1}. '
            'If wrong value: possible address collision or wrong chip variant.',
      ),
    ];
  }

  // ── PPG Patient ───────────────────────────────────────────────────────────

  List<Widget> _buildPpgPatient() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Signal quality', s == null ? '—' : '${s.ppgQuality}', unit: '/ 100'),
        _DiagRow('Heart rate', s == null ? '—' : s.hrPatient.toStringAsFixed(0), unit: 'BPM'),
        _DiagRow('SpO₂', s == null ? '—' : s.spO2Patient.toStringAsFixed(1), unit: '%'),
        _DiagRow('Perfusion index', s == null ? '—' : '${s.patientPI}', unit: '/ 100'),
        _DiagRow('PPG raw', s == null ? '—' : s.ppgRaw.toStringAsFixed(4)),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('I²C response (CH5, 0x57)',
            (s?.i2cScanMask ?? 0) & (1 << AppConstants.diagI2cBitMax30102P) != 0,
            hint: 'No ACK → solder fault on SDA/SCL to TCA CH5'),
        _CheckRow('Quality > 0 with finger', s != null && s.ppgQuality > 0,
            hint: 'Always 0 → LED not firing or photodiode dead'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: 'Cover the patient PPG sensor with your fingertip and hold '
            'still. Quality should reach at least '
            '${AppConstants.diagPpgPatientTestMinQuality} within 15 s.',
        icon:        Icons.fingerprint_rounded,
        window:      AppConstants.diagTestWindowLong,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          if (window.isEmpty) return (passed: false, message: 'No samples');
          final maxQ = window.fold<int>(0, (m, x) => x.ppgQuality > m ? x.ppgQuality : m);
          if (maxQ >= AppConstants.diagPpgPatientTestMinQuality) {
            return (passed: true, message: 'Quality reached $maxQ ✓');
          }
          return (passed: false,
          message: 'Quality only reached $maxQ — check contact and LED current');
        },
      ),
      _MultiTraceSparkline(
        title: 'PPG raw + quality',
        traces: [
          _Trace(
            label:  'Raw (×100)',
            color:  AppColors.emergency,
            points:_lastN(snapshot.map((s) => s.ppgRaw * 100)),
          ),
          _Trace(
            label:  'Quality',
            color:  AppColors.primary,
            points: _lastN(snapshot.map((s) => s.ppgQuality.toDouble())),
            minY:   0,
            maxY:   100,
          ),
        ],
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Q', unit: '', value: (s) => s.ppgQuality.toDouble(), fractionDigits: 0),
          _HistoryColumn(header: 'HR', unit: 'BPM', value: (s) => s.hrPatient, fractionDigits: 0),
          _HistoryColumn(header: 'SpO₂', unit: '%', value: (s) => s.spO2Patient, fractionDigits: 1),
        ],
      ),
      _HintCard(
        'Place your fingertip firmly on the MAX30102 sensor (TCA channel 5, I²C 0x57). '
            'Signal quality should rise to ≥ ${AppConstants.diagPpgPatientTestMinQuality}. '
            'If quality stays at 0: check VIN, GND, SDA, SCL on TCA CH5.',
      ),
    ];
  }

  // ── PPG Rescuer ───────────────────────────────────────────────────────────

  List<Widget> _buildPpgRescuer() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Signal quality', s == null ? '—' : '${s.rescuerQuality}', unit: '/ 100'),
        _DiagRow('Heart rate', s == null ? '—' : s.hrUser.toStringAsFixed(0), unit: 'BPM'),
        _DiagRow('SpO₂', s == null ? '—' : s.spO2User.toStringAsFixed(1), unit: '%'),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('I²C response (CH4, 0x57)',
            (s?.i2cScanMask ?? 0) & (1 << AppConstants.diagI2cBitMax30102R) != 0,
            hint: 'No ACK → solder fault on TCA CH4'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: 'Wear the glove on your wrist and hold still for 15 s. '
            'Heart rate should appear between '
            '${AppConstants.diagPpgRescuerTestMinBpm.toStringAsFixed(0)} and '
            '${AppConstants.diagPpgRescuerTestMaxBpm.toStringAsFixed(0)} BPM.',
        icon:        Icons.favorite_rounded,
        window:      AppConstants.diagTestWindowLong,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          if (window.isEmpty) return (passed: false, message: 'No samples');
          // Find the max HR seen, but only from samples with quality > 30
          double bestHr = 0;
          for (final s in window) {
            if (s.rescuerQuality > 30 && s.hrUser > bestHr) bestHr = s.hrUser;
          }
          if (bestHr >= AppConstants.diagPpgRescuerTestMinBpm &&
              bestHr <= AppConstants.diagPpgRescuerTestMaxBpm) {
            return (passed: true, message: 'HR ${bestHr.toStringAsFixed(0)} BPM ✓');
          }
          return (passed: false,
          message: 'HR not detected (best ${bestHr.toStringAsFixed(0)}) — check glove contact');
        },
      ),
      _MultiTraceSparkline(
        title: 'Rescuer PPG (filtered) + HR',
        traces: [
          _Trace(
            label:  'PPG filt',
            color:  AppColors.emergency,
            points:_lastN(snapshot.map((s) => s.rescuerPpgFiltered)),
          ),
          _Trace(
            label:  'HR (BPM)',
            color:  AppColors.primary,
            points:_lastN(snapshot.map((s) => s.hrUser)),
            minY:   0,
            maxY:   200,
          ),
        ],
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Q', unit: '', value: (s) => s.rescuerQuality.toDouble(), fractionDigits: 0),
          _HistoryColumn(header: 'HR', unit: 'BPM', value: (s) => s.hrUser, fractionDigits: 0),
          _HistoryColumn(header: 'SpO₂', unit: '%', value: (s) => s.spO2User, fractionDigits: 1),
        ],
      ),
      _HintCard(
        'Rescuer PPG on TCA channel 4, I²C 0x57. '
            'Wear the glove and check if HR appears. '
            'Quality drops to 0 during compressions — this is expected.',
      ),
    ];
  }

  // ── MAX30205 ──────────────────────────────────────────────────────────────

  List<Widget> _buildTempPatient() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    final tempOk = s != null && s.patientTempC > 15.0 && s.patientTempC < 45.0;
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Patient temperature', s == null ? '—' : s.patientTempC.toStringAsFixed(2), unit: '°C'),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('I²C response (CH2, 0x48)',
            (s?.i2cScanMask ?? 0) & (1 << AppConstants.diagI2cBitMax30205) != 0,
            hint: 'No ACK → VIN/GND/SDA/SCL on MAX30205'),
        _CheckRow('Temperature in plausible range', tempOk,
            hint: 'Outside 15–45°C → read error or sensor cold-boot issue'),
        _CheckRow('Reading ≠ 0.00°C', s != null && s.patientTempC != 0.0,
            hint: '0°C = read failure, check I²C and power'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: 'Hold the MAX30205 sensor against your skin. Temperature '
            'should rise by at least '
            '${AppConstants.diagTempPatientTestMinRiseC.toStringAsFixed(0)} °C within 10 s.',
        icon:        Icons.touch_app_rounded,
        window:      AppConstants.diagTestWindowLong,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          if (window.length < 5) return (passed: false, message: 'Not enough samples');
          final start = window.first.patientTempC;
          final maxT  = window.fold<double>(start, (m, x) => x.patientTempC > m ? x.patientTempC : m);
          final rise  = maxT - start;
          if (rise >= AppConstants.diagTempPatientTestMinRiseC) {
            return (passed: true,
            message: '+${rise.toStringAsFixed(1)} °C (${start.toStringAsFixed(1)}→${maxT.toStringAsFixed(1)}) ✓');
          }
          return (passed: false,
          message: 'Rise only ${rise.toStringAsFixed(1)} °C — check sensor contact');
        },
      ),
      _MultiTraceSparkline(
        title: 'Patient temp (°C)',
        traces: [
          _Trace(
            label:  'Temp',
            color:  AppColors.primary,
            points:_lastN(snapshot.map((s) => s.patientTempC)),
          ),
        ],
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Temp', unit: '°C', value: (s) => s.patientTempC, fractionDigits: 2),
        ],
      ),
      _HintCard(
        'MAX30205 on TCA channel 2, I²C 0x48. Reading 0.00 °C = I²C not responding.',
      ),
    ];
  }

  // ── GXHT30 ───────────────────────────────────────────────────────────────

  List<Widget> _buildGxht30() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Rescuer wrist temp', s == null ? '—' : s.rescuerTempC.toStringAsFixed(2), unit: '°C'),
        _DiagRow('Rescuer humidity', s == null ? '—' : s.rescuerHumidity.toStringAsFixed(1), unit: '%RH'),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('I²C response (CH3, 0x44)',
            (s?.i2cScanMask ?? 0) & (1 << AppConstants.diagI2cBitGxht30) != 0,
            hint: 'No ACK → check SDA/SCL to TCA CH3 and 3.3V power'),
        _CheckRow('Humidity in range', s != null && s.rescuerHumidity > 0 && s.rescuerHumidity <= 100,
            hint: '0% or >100% → read error'),
        _CheckRow('Temp not 0°C', s != null && s.rescuerTempC != 0.0,
            hint: '0.00°C = I²C read failure'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: 'Breathe on the GXHT30 sensor for ~5 s. Humidity should '
            'rise by at least '
            '${AppConstants.diagHumidityTestMinRise.toStringAsFixed(0)} %RH.',
        icon:        Icons.air_rounded,
        window:      AppConstants.diagTestWindow,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          if (window.length < 5) return (passed: false, message: 'Not enough samples');
          final start = window.first.rescuerHumidity;
          final maxH  = window.fold<double>(start, (m, x) => x.rescuerHumidity > m ? x.rescuerHumidity : m);
          final rise  = maxH - start;
          if (rise >= AppConstants.diagHumidityTestMinRise) {
            return (passed: true,
            message: '+${rise.toStringAsFixed(0)} %RH (${start.toStringAsFixed(0)}→${maxH.toStringAsFixed(0)}) ✓');
          }
          return (passed: false,
          message: 'Rise only ${rise.toStringAsFixed(0)} %RH — sensor unresponsive');
        },
      ),
      _MultiTraceSparkline(
        title: 'Rescuer temp + humidity',
        traces: [
          _Trace(
            label:  'Temp (°C)',
            color:  AppColors.primary,
            points:_lastN(snapshot.map((s) => s.rescuerTempC)),
          ),
          _Trace(
            label:  'Hum (%)',
            color:  AppColors.success,
            points: _lastN(snapshot.map((s) => s.rescuerHumidity)),
            minY:   0,
            maxY:   100,
          ),
        ],
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Temp', unit: '°C', value: (s) => s.rescuerTempC, fractionDigits: 2),
          _HistoryColumn(header: 'Hum', unit: '%', value: (s) => s.rescuerHumidity, fractionDigits: 0),
        ],
      ),
      _HintCard(
        'GXHT30 on TCA channel 3, I²C 0x44. When worn on wrist: expect temp 30–36°C, humidity 50–80%RH.',
      ),
    ];
  }

  // ── DFPlayer ─────────────────────────────────────────────────────────────

  List<Widget> _buildDfplayer() {
    return [
      _DiagCard(title: 'Audio Test', children: [
        _ActionButton(
          label:    'Play track 10',
          subtitle: 'Should play audio cue from speaker',
          icon:     Icons.play_circle_outline_rounded,
          pending:  _actionPending,
          onTap:    () => _sendAction(0x01, param: 10),
        ),
      ]),
      _DiagCard(title: 'Did you hear audio?', children: [
        _ConfirmRow('Yes. Audio is working', onYes: () {
          widget.onManualPass?.call();
          setState(() { _actionFeedback = '✓ Audio confirmed'; });
        }),
        _ConfirmRow('No', onNo: () {
          widget.onManualFail?.call();
          setState(() { _actionFeedback = '✗ No audio. Check speaker wires and DFPlayer UART'; });
        }),
      ]),
      _HintCard(
        'Audio feedback plays spoken compression cues and rhythm guidance during CPR. '
            'If silent: check the speaker is connected and the SD card is inserted in the DFPlayer module.',
      ),
    ];
  }

  // ── Motor ─────────────────────────────────────────────────────────────────

  List<Widget> _buildMotor() {
    return [
      _DiagCard(title: 'Motor Test', children: [
        _ActionButton(
          label:    'Fire motor (500ms)',
          subtitle: 'Should feel a strong vibration burst',
          icon:     Icons.vibration_rounded,
          pending:  _actionPending,
          onTap:    () => _sendAction(0x02),
        ),
      ]),
      _DiagCard(title: 'Did you feel vibration?', children: [
        _ConfirmRow('Yes. Vibration felt', onYes: () {
          widget.onManualPass?.call();
          setState(() { _actionFeedback = '✓ Motor confirmed'; });
        }),
        _ConfirmRow('No', onNo: () {
          widget.onManualFail?.call();
          setState(() { _actionFeedback = '✗ No vibration. Check motor circuit'; });
        }),
      ]),
      _HintCard(
        'Vibration feedback gives the rescuer a tactile pulse to maintain compression rhythm. '
            'If no vibration is felt: check that the motor is securely connected to the circuit board.',
      ),
    ];
  }

  // ── NeoPixel ─────────────────────────────────────────────────────────────

  List<Widget> _buildNeopixel() {
    return [
      _DiagCard(title: 'LED Test', children: [
        _ActionButton(
          label:    'Run LED chase test',
          subtitle: 'Red → Green → Blue → White chase across all 8 LEDs',
          icon:     Icons.light_mode_rounded,
          pending:  _actionPending,
          onTap:    () => _sendAction(0x03),
        ),
      ]),
      _DiagCard(title: 'What did you see?', children: [
        _ConfirmRow('All 8 LEDs lit correctly', onYes: () {
          widget.onManualPass?.call();
          setState(() { _actionFeedback = '✓ All LEDs OK'; });
        }),
        _ConfirmRow('Some LEDs wrong colour or off', onNo: () {
          widget.onManualFail?.call();
          setState(() { _actionFeedback = '✗ LED issue. Check data line or individual LED'; });
        }),
      ]),
      _HintCard(
        'The LED bar on the glove shows compression depth in real time — deeper compressions light more LEDs. '
            'If some LEDs are off or the wrong colour, one or more LEDs on the strip may need replacing.',
      ),
    ];
  }

  // ── Battery ───────────────────────────────────────────────────────────────

  List<Widget> _buildBattery() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Battery', s == null ? '—' : '${s.batteryPct}', unit: '%'),
        _DiagRow('Charging', s == null ? '—' : (s.isCharging ? 'Yes (USB)' : 'No')),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('Battery % > 0', s != null && s.batteryPct > 0,
            hint: 'Always 0 → ADC on GPIO35 not reading, or divider fault'),
        _CheckRow('Battery % ≤ 100', s != null && s.batteryPct <= 100,
            hint: '>100% → ADC calibration error'),
        _CheckRow('Charging detected when USB plugged', s != null && s.isCharging,
            hint: 'Plug USB now — should flip to Yes within a second'),
      ]),
      _MultiTraceSparkline(
        title: 'Battery (%)',
        traces: [
          _Trace(
            label:  '%',
            color:  AppColors.success,
            points:_lastN(snapshot.map((s) => s.batteryPct.toDouble())),
            minY:   0,
            maxY:   100,
          ),
        ],
        targetBand: (AppConstants.batteryLow.toDouble(), 100.0),
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Bat', unit: '%', value: (s) => s.batteryPct.toDouble(), fractionDigits: 0),
          _HistoryColumn(header: 'Chg', unit: '', value: (s) => s.isCharging ? 1.0 : 0.0, fractionDigits: 0),
        ],
      ),
      _HintCard(
        'Battery ADC on GPIO35 via 100kΩ+100kΩ divider. Charging detect on GPIO33 (HIGH = USB charging).',
      ),
    ];
  }

  // ── I2C Bus ───────────────────────────────────────────────────────────────

// History of last 3 I²C scans (mask + timestamp)
  final List<(int, int)> _i2cScanHistory = [];

  List<Widget> _buildI2cBus() {
    final s = _latest;
    final mask = s?.i2cScanMask ?? 0;

    // Capture each unique scan result into history
    if (s != null && (_i2cScanHistory.isEmpty || _i2cScanHistory.last.$2 != mask)) {
      _i2cScanHistory.add((s.timestampMs, mask));
      if (_i2cScanHistory.length > 3) _i2cScanHistory.removeAt(0);
    }

    const channels = [
      (ch: 0, label: 'CH0 → Palm IMU (0x6B)',    bit: AppConstants.diagI2cBitPalmImu),
      (ch: 1, label: 'CH1 → Wrist IMU (0x6A)',   bit: AppConstants.diagI2cBitWristImu),
      (ch: 2, label: 'CH2 → MAX30205 (0x48)',     bit: AppConstants.diagI2cBitMax30205),
      (ch: 3, label: 'CH3 → GXHT30 (0x44)',       bit: AppConstants.diagI2cBitGxht30),
      (ch: 4, label: 'CH4 → MAX30102 R (0x57)',   bit: AppConstants.diagI2cBitMax30102R),
      (ch: 5, label: 'CH5 → MAX30102 P (0x57)',   bit: AppConstants.diagI2cBitMax30102P),
    ];

    return [
      _DiagCard(title: 'Scan', children: [
        _ActionButton(
          label:    'Run I²C scan',
          subtitle: 'Check all 6 TCA channels now',
          icon:     Icons.search_rounded,
          pending:  _actionPending,
          onTap:    () => _sendAction(0x04),
        ),
      ]),
      _DiagCard(title: 'Latest Results', children: [
        for (final ch in channels)
          _CheckRow(
            ch.label,
            mask & (1 << ch.bit) != 0,
            hint: 'No response → check TCA channel ${ch.ch} SDA/SCL and sensor power',
          ),
      ]),
      if (_i2cScanHistory.length > 1)
        _DiagCard(title: 'Recent Scans', children: [
          for (final entry in _i2cScanHistory.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 2,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      'T-${((DateTime.now().millisecondsSinceEpoch - entry.$1) / 1000).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'mask = 0b${entry.$2.toRadixString(2).padLeft(6, '0')}'
                          '  (${_popcount(entry.$2)}/6 channels)',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      _HintCard(
        'TCA9548A at 0x70 on SDA/SCL (GPIO21/22). I²C bus at 400kHz. '
            'If TCA itself not responding: check 3.3V power and 10kΩ RST pull-up.',
      ),
    ];
  }

  int _popcount(int n) {
    int c = 0;
    while (n != 0) { c += n & 1; n >>= 1; }
    return c;
  }

  // ── Button ────────────────────────────────────────────────────────────────

// Track press timestamps for the history view
  final List<int> _buttonPressTimes = [];

  List<Widget> _buildButton() {
    final required = AppConstants.diagButtonTestRequiredPresses;
    return [
      _DiagCard(title: 'Live State', children: [
        _DiagRow('Press events detected', '$_buttonPressCount'),
      ]),
      _DiagCard(title: 'Static Checks', children: [
        _CheckRow('Press events received', _buttonPressCount > 0,
            hint: 'No events → GPIO27 not pulling LOW, or button wiring fault'),
        _CheckRow('Button on GPIO27, active LOW', true,
            hint: '10kΩ pull-up to 3.3V required'),
      ]),
      _GuidedCheck(
        title:       'Live Stimulus Test',
        instruction: 'Press the physical button on the glove $required times within 10 s.',
        icon:        Icons.touch_app_rounded,
        window:      AppConstants.diagTestWindowLong,
        samplesProvider: () => _buffer,
        evaluate: (window) {
          // Count distinct diagActionResult transitions within the window
          // by sampling the button-press counter at start and end.
          final winStartMs = window.isNotEmpty ? window.first.timestampMs : 0;
          final inWindow = _buttonPressTimes.where((t) => t >= winStartMs).length;
          if (inWindow >= required) {
            return (passed: true, message: '$inWindow / $required presses ✓');
          }
          return (passed: false,
          message: 'Only $inWindow / $required — button may be unresponsive');
        },
      ),
      if (_buttonPressTimes.isNotEmpty)
        _DiagCard(title: 'Last Presses', children: [
          for (final t in _buttonPressTimes.reversed.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 2,
              ),
              child: Text(
                'T-${((DateTime.now().millisecondsSinceEpoch - t) / 1000).toStringAsFixed(1)}s',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ]),
      _HintCard(
        'Button on GPIO27 with 10kΩ pull-up to 3.3V. Long press (>2s) cycles mode.',
      ),
    ];
  }

  // ── Depth Combined (compression pipeline integration test) ────────────────
  // The most useful test: does the whole compression-detection pipeline
  // actually report compressions when the user presses the FSR?
  //
  // We count force-peak transitions app-side (rise above threshold → fall
  // below release threshold). This is independent of the firmware's session
  // state machine, so we don't need CMD_START or any session at all. The
  // FSR + IMU + fusion still produce a `depth` value in real time (via the
  // force model fallback even without a session), so we plot that too.

  int  _compTestPeakCount   = 0;
  bool _compTestInRise      = false;
  int  _compTestStartBufLen = 0;

  void _onForceSampleForDepthTest(_DiagSample s) {
    // Only count when widget.component == depthCombined and the user is
    // running the guided test (started by _GuidedCheck). We use the
    // _compTestStartBufLen marker to detect "test in progress".
    if (widget.component != _DiagComponent.depthCombined) return;
    if (_compTestStartBufLen == 0) return;
    if (!_compTestInRise && s.force >= AppConstants.diagDepthTestPeakForceN) {
      _compTestInRise = true;
      _compTestPeakCount++;
    } else if (_compTestInRise && s.force < AppConstants.diagDepthTestReleaseN) {
      _compTestInRise = false;
    }
  }

  List<Widget> _buildDepthCombined() {
    final snapshot = List<_DiagSample>.unmodifiable(_buffer);
    final s = _latest;
    // Check upstream sensors before allowing the test
    final fsrOk   = s != null && s.rawFsrAdc > 10 && s.rawFsrAdc < 4085;
    final palmOk  = s != null && s.palmWhoAmI  == AppConstants.lsm6dsoxWhoAmIExpected;
    final wristOk = s != null && s.wristWhoAmI == AppConstants.lsm6dsoxWhoAmIExpected;
    final allUpstreamOk = fsrOk && palmOk && wristOk;

    return [
      _DiagCard(title: 'Live Readings', children: [
        _DiagRow('Depth (fused)',  s == null ? '—' : s.depth.toStringAsFixed(1), unit: 'cm'),
        _DiagRow('Force',          s == null ? '—' : s.force.toStringAsFixed(1), unit: 'N'),
      ]),
      _DiagCard(title: 'Upstream Sensors', children: [
        _CheckRow('FSR (Force Sensor) responding',    fsrOk,
            hint: 'Open the Force Sensor test to debug'),
        _CheckRow('Palm IMU responding',  palmOk,
            hint: 'Open the IMU — Palm test to debug'),
        _CheckRow('Wrist IMU responding', wristOk,
            hint: 'Open the IMU — Wrist test to debug'),
      ]),
      if (!allUpstreamOk)
        _HintCard(
          'Cannot run compression test — fix the upstream sensors above first. '
              'Compression detection fuses force + IMU; both must work.',
        )
      else
        _GuidedCheck(
          title:       'Compression Detection Test',
          instruction: 'Press the glove against a firm surface '
              '${AppConstants.diagDepthTestRequiredPeaks} times. '
              'Each press should peak above '
              '${AppConstants.diagDepthTestPeakForceN.toStringAsFixed(0)} N. '
              'You have 30 s.',
          icon:        Icons.compress_rounded,
          window:      const Duration(seconds: 30),
          samplesProvider: () => _buffer,
          evaluate: (window) {
            // Recount cleanly within the captured window (don't trust the
            // running counter — it could include presses from before Start).
            int peaks  = 0;
            bool rising = false;
            for (final s in window) {
              if (!rising && s.force >= AppConstants.diagDepthTestPeakForceN) {
                rising = true;
                peaks++;
              } else if (rising && s.force < AppConstants.diagDepthTestReleaseN) {
                rising = false;
              }
            }
            final maxDepth = window.fold<double>(0,
                    (m, x) => x.depth > m ? x.depth : m);
            final maxForce = window.fold<double>(0,
                    (m, x) => x.force > m ? x.force : m);
            final req = AppConstants.diagDepthTestRequiredPeaks;
            if (peaks >= req) {
              return (passed: true,
              message: '$peaks/$req peaks, max ${maxForce.toStringAsFixed(0)} N, '
                  'max depth ${maxDepth.toStringAsFixed(1)} cm ✓');
            }
            return (passed: false,
            message: 'Only $peaks/$req peaks — pipeline incomplete '
                '(force peaked at ${maxForce.toStringAsFixed(0)} N)');
          },
        ),
      _MultiTraceSparkline(
        title: 'Depth + Force (last 10 s)',
        traces: [
          _Trace(
            label:  'Depth (cm)',
            color:  AppColors.primary,
            points:_lastN(snapshot.map((s) => s.depth)),
          ),
          _Trace(
            label:  'Force (N)',
            color:  AppColors.warning,
            points:_lastN(snapshot.map((s) => s.force)),
          ),
        ],
        targetBand: (5.0, 6.0),   // adult depth target
      ),
      _HistoryCard(
        title:   'Recent Samples',
        samples: snapshot,
        columns: [
          _HistoryColumn(header: 'Depth', unit: 'cm', value: (s) => s.depth, fractionDigits: 1),
          _HistoryColumn(header: 'Force', unit: 'N',  value: (s) => s.force, fractionDigits: 1),
        ],
      ),
      _HintCard(
        'This test verifies the full compression-detection pipeline: '
            'FSR analog → ADC → force conversion → IMU integration → fusion → depth. '
            'If force peaks but depth stays at 0: IMU integration is broken. '
            'If both stay flat: FSR not registering pressure.',
      ),
    ];
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DiagCard extends StatelessWidget {
  final String       title;
  final List<Widget> children;
  const _DiagCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    decoration: AppDecorations.card(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
          child: Text(title, style: AppTypography.bodyMedium(size: 13, color: AppColors.textSecondary)),
        ),
        ...children,
      ],
    ),
  );
}

class _DiagRow extends StatelessWidget {
  final String  label;
  final String  value;
  final String? unit;
  const _DiagRow(this.label, this.value, {this.unit});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.caption())),
        Text(
          unit != null ? '$value $unit' : value,
          style: AppTypography.bodyMedium(size: 13, color: AppColors.textPrimary),
        ),
      ],
    ),
  );
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool   passed;
  final String hint;
  const _CheckRow(this.label, this.passed, {required this.hint});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: passed ? AppColors.success : AppColors.error,
          size: 18,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.bodyMedium(size: 13)),
              if (!passed)
                Text(hint, style: AppTypography.caption(color: AppColors.error)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String     label;
  final String     subtitle;
  final IconData   icon;
  final bool       pending;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label, required this.subtitle,
    required this.icon,  required this.pending, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: pending ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: AppSpacing.iconBoxSize, height: AppSpacing.iconBoxSize,
            decoration: AppDecorations.iconRounded(
              bg: AppColors.primary.withValues(alpha: 0.1),
              radius: AppSpacing.cardRadiusSm + AppSpacing.xxs,
            ),
            child: pending
                ? const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : Icon(icon, color: AppColors.primary, size: AppSpacing.iconSm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,    style: AppTypography.bodyMedium(size: 14, color: AppColors.primary)),
                Text(subtitle, style: AppTypography.caption()),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConfirmRow extends StatelessWidget {
  final String      label;
  final VoidCallback? onYes;
  final VoidCallback? onNo;
  const _ConfirmRow(this.label, {this.onYes, this.onNo});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onYes ?? onNo,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            onYes != null ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
            color: onYes != null ? AppColors.success : AppColors.error,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.bodyMedium(size: 13))),
        ],
      ),
    ),
  );
}

class _HintCard extends StatelessWidget {
  final String text;
  const _HintCard(this.text);

  @override
  Widget build(BuildContext context) => Container(
    margin:  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadius),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 16),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: AppTypography.caption())),
      ],
    ),
  );
}

class _ActionFeedbackBanner extends StatelessWidget {
  final String message;
  const _ActionFeedbackBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    margin:  const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
    decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadius),
    child: Text(message, style: AppTypography.bodyMedium(size: 13, color: AppColors.success)),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _HistoryCard — rolling table of the last N samples (default 6)
// Each row shows time-since-now and 1–3 numeric columns.
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryColumn {
  final String header;
  final String unit;
  final double Function(_DiagSample s) value;
  final int fractionDigits;
  const _HistoryColumn({
    required this.header,
    required this.unit,
    required this.value,
    this.fractionDigits = 2,
  });
}

class _HistoryCard extends StatelessWidget {
  final String                 title;
  final List<_DiagSample>      samples;
  final List<_HistoryColumn>   columns;
  final int                    rows;
  const _HistoryCard({
    required this.title,
    required this.samples,
    required this.columns,
    this.rows = AppConstants.diagHistoryRows,
  });

  @override
  Widget build(BuildContext context) {
    if (samples.isEmpty) {
      return _DiagCard(title: title, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Waiting for data…',
            style: AppTypography.caption(),
          ),
        ),
      ]);
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Take the last `rows` samples in newest-first order
    final tail  = samples.length <= rows
        ? List<_DiagSample>.from(samples.reversed)
        : samples.sublist(samples.length - rows).reversed.toList();

    return _DiagCard(title: title, children: [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            const SizedBox(width: 44, child: Text('Δt',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textDisabled))),
            for (final c in columns)
              Expanded(
                child: Text(
                  '${c.header}${c.unit.isEmpty ? '' : ' (${c.unit})'}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textDisabled,
                  ),
                ),
              ),
          ],
        ),
      ),
      const Divider(height: AppSpacing.dividerThickness, color: AppColors.divider),
      for (int i = 0; i < tail.length; i++) ...[
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: 3,
          ),
          decoration: BoxDecoration(
            color: i.isEven
                ? AppColors.screenBgGrey.withValues(alpha: 0.5)
                : AppColors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  _fmtRel(nowMs - tail[i].timestampMs),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize:   12,
                    color:      AppColors.textSecondary,
                  ),
                ),
              ),
              for (final c in columns)
                Expanded(
                  child: Text(
                    c.value(tail[i]).toStringAsFixed(c.fractionDigits),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize:   12,
                      color:      AppColors.textPrimary,
                      fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
     const SizedBox(height: AppSpacing.xs),
    ]);
  }

  static String _fmtRel(int ms) {
    if (ms < 1000) return '${ms}ms';
    final s = ms / 1000;
    if (s < 10)  return '-${s.toStringAsFixed(1)}s';
    return '-${s.toStringAsFixed(0)}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MultiTraceSparkline — strip-chart with 1–3 traces overlaid, shared X axis,
// optional Y-axis target band. Each trace has its own min/max so we don't
// need a single dominant axis.
// ─────────────────────────────────────────────────────────────────────────────

class _Trace {
  final String       label;
  final Color        color;
  final List<double> points;
  /// Optional Y-axis range; null = auto-fit to points.
  final double? minY;
  final double? maxY;
  const _Trace({
    required this.label,
    required this.color,
    required this.points,
    this.minY,
    this.maxY,
  });
}

class _MultiTraceSparkline extends StatelessWidget {
  final String      title;
  final List<_Trace> traces;
  final double      height;
  /// Optional [low, high] target band drawn behind the lines.
  final (double, double)? targetBand;
  const _MultiTraceSparkline({
    required this.title,
    required this.traces,
    this.height     = 100,
    this.targetBand,
  });

  @override
  Widget build(BuildContext context) {
    final anyData = traces.any((t) => t.points.length >= 2);
    return Container(
      margin:     const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      padding:    const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTypography.badge(color: AppColors.textSecondary))),
              // Legend
              for (final t in traces) ...[
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(t.label, style: AppTypography.caption(color: t.color)),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: height,
            child: anyData
                ? CustomPaint(
              size: Size.infinite,
              painter: _MultiTracePainter(traces: traces, band: targetBand),
            )
                : Center(child: Text('—', style: AppTypography.caption())),
          ),
        ],
      ),
    );
  }
}

class _MultiTracePainter extends CustomPainter {
  final List<_Trace>      traces;
  final (double, double)? band;
  const _MultiTracePainter({required this.traces, this.band});


  @override
  void paint(Canvas canvas, Size size) {
    // Reserve a small gutter on the right for Y-axis labels.
    const double rightGutter = 32;
    final plotWidth = size.width - rightGutter;

    // Optional target band first (behind everything).
    if (band != null) {
      final firstWithData = traces.firstWhere(
            (t) => t.points.length >= 2,
        orElse: () => const _Trace(label: '', color: AppColors.transparent, points: []),
      );
      if (firstWithData.points.length >= 2) {
        final (lo, hi) = band!;
        final tMin = firstWithData.minY ??
            firstWithData.points.reduce((a, b) => a < b ? a : b);
        final tMax = firstWithData.maxY ??
            firstWithData.points.reduce((a, b) => a > b ? a : b);
        final range = (tMax - tMin).abs();
        if (range > 0) {
          final yLo = size.height - (lo - tMin) / range * size.height;
          final yHi = size.height - (hi - tMin) / range * size.height;
          final bandPaint = Paint()..color = AppColors.success.withValues(alpha: 0.08);
          canvas.drawRect(
            Rect.fromLTRB(0,
                yHi.clamp(0, size.height),
                plotWidth,
                yLo.clamp(0, size.height)),
            bandPaint,
          );
        }
      }
    }

    // Faint horizontal grid (3 lines: 25%, 50%, 75%)
    final gridPaint = Paint()
      ..color       = AppColors.divider.withValues(alpha: 0.4)
      ..strokeWidth = 0.5;
    for (final f in [0.25, 0.5, 0.75]) {
      final y = size.height * f;
      canvas.drawLine(Offset(0, y), Offset(plotWidth, y), gridPaint);
    }

    // Plot each trace
    for (final t in traces) {
      if (t.points.length < 2) continue;
      final pts = t.points;
      final minV = t.minY ?? pts.reduce((a, b) => a < b ? a : b);
      final maxV = t.maxY ?? pts.reduce((a, b) => a > b ? a : b);
      final range = (maxV - minV).abs();
      if (range == 0) continue;

      final paint = Paint()
        ..color       = t.color
        ..strokeWidth = 1.5
        ..style       = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < pts.length; i++) {
        final x = i / (pts.length - 1) * plotWidth;
        final y = size.height - (pts[i] - minV) / range * size.height;
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }

    // Y-axis min/max labels on the right (use the first trace's range)
    final first = traces.firstWhere(
          (t) => t.points.length >= 2,
      orElse: () => const _Trace(label: '', color: AppColors.transparent, points: []),
    );
    if (first.points.length >= 2) {
      final minV = first.minY ?? first.points.reduce((a, b) => a < b ? a : b);
      final maxV = first.maxY ?? first.points.reduce((a, b) => a > b ? a : b);
      _drawAxisLabel(canvas, plotWidth + 4, 2,           _fmtAxis(maxV));
      _drawAxisLabel(canvas, plotWidth + 4, size.height - 12, _fmtAxis(minV));
    }
  }

  String _fmtAxis(double v) {
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    if (v.abs() >= 10)  return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  void _drawAxisLabel(Canvas canvas, double x, double y, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize:   9,
          color:      AppColors.textDisabled,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(_MultiTracePainter old) => old.traces != traces;
}

// ─────────────────────────────────────────────────────────────────────────────
// _GuidedCheck — "tap Start, do an action, see if it worked"
// The widget owns its own capture window; the parent provides:
//   • instruction text and an icon
//   • a duration
//   • a closure that, given the list of samples captured during the window,
//     returns (passed: bool, message: String). The message is shown after
//     the test completes.
// ─────────────────────────────────────────────────────────────────────────────

class _GuidedCheck extends StatefulWidget {
  final String   title;
  final String   instruction;
  final IconData icon;
  final Duration window;
  final List<_DiagSample> Function() samplesProvider;
  final ({bool passed, String message}) Function(List<_DiagSample>) evaluate;
  const _GuidedCheck({
  required this.title,
  required this.instruction,
  required this.icon,
  required this.window,
  required this.samplesProvider,
  required this.evaluate,
  });

  @override
  State<_GuidedCheck> createState() => _GuidedCheckState();
}

class _GuidedCheckState extends State<_GuidedCheck> {
  bool      _running        = false;
  Timer?    _countdownTimer;
  int       _remainingMs    = 0;
  int       _startBufferLen = 0;
  ({bool passed, String message})? _result;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() {
      _running        = true;
      _result         = null;
      _remainingMs    = widget.window.inMilliseconds;
      _startBufferLen = widget.samplesProvider().length;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) { t.cancel(); return; }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _remainingMs -= 100);
        if (_remainingMs <= 0) {
          t.cancel();
          _finish();
        }
      });
    });
  }

  void _finish() {
    final all = widget.samplesProvider();
    final window = all.skip(_startBufferLen).toList();
    setState(() {
      _running = false;
      _result  = widget.evaluate(window);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DiagCard(title: widget.title, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: AppColors.primary, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(widget.instruction, style: AppTypography.bodyMedium(size: 13)),
            ),
          ],
        ),
      ),
      if (_running)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: 1 - _remainingMs / widget.window.inMilliseconds,
                backgroundColor: AppColors.divider,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${(_remainingMs / 1000).toStringAsFixed(1)}s remaining',
                style: AppTypography.caption(),
              ),
            ],
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm,
          ),
          child: Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: ElevatedButton.icon(
                  onPressed: _start,
                  icon:      Icon(_result == null ? Icons.play_arrow_rounded
                      : Icons.replay_rounded),
                  label:     Text(_result == null ? 'Start test' : 'Retry'),
                  style:     ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (_result != null)
                Flexible(
                  child: Row(
                    children: [
                      Icon(
                        _result!.passed
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: _result!.passed
                            ? AppColors.success
                            : AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          _result!.message,
                          style: AppTypography.bodyMedium(
                            size: 13,
                            color: _result!.passed
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ]);
  }
}