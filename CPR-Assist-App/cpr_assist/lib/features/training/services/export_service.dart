import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:cpr_assist/features/training/services/session_detail.dart';
import 'package:cpr_assist/features/training/services/compression_event.dart';
import 'package:cpr_assist/features/training/services/ventilation_event.dart';
import 'package:cpr_assist/features/training/services/pulse_check_event.dart';
import 'package:cpr_assist/features/training/services/rescuer_vital_snapshot.dart';

import 'certificate_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExportService
//
// Architecture:
//   Every data shape has ONE _build*() function.
//   share*() and download*() are thin wrappers that call the same builder.
//   All file I/O goes through _shareFile() or _saveToDevice().
//   All CSV text is encoded with utf8.encode() — never codeUnits.
//
// Public API — PDFs:
//   exportSingleSessionPdf / downloadSingleSessionPdf
//   exportMultiSessionPdf  / downloadMultiSessionPdf
//   exportCertificate
//
// Public API — Summary CSV (one row per session):
//   exportSessionsAsCsv    / downloadSessionsAsCsv
//   exportSingleSessionCsv / downloadSingleSessionCsv
//
// Public API — Raw CSVs (one row per event):
//   exportRawCompressionsCsv  / downloadRawCompressionsCsv
//   exportRawRescuerVitalsCsv / downloadRawRescuerVitalsCsv
//   exportRawVentilationsCsv  / downloadRawVentilationsCsv
//   exportRawPulseChecksCsv   / downloadRawPulseChecksCsv
//
// Public API — ZIP (all raw streams in one file):
//   exportRawDataZip / downloadRawDataZip
// ─────────────────────────────────────────────────────────────────────────────

// ── PDF brand colours — mirror app_colors.dart exactly ───────────────────────

const _kBrandBlue    = PdfColor.fromInt(0xFF1E4D96); // AppColors.primary
const _kBrandMid     = PdfColor.fromInt(0xFF2D62B8); // AppColors.primaryAlt
const _kBrandDark    = PdfColor.fromInt(0xFF335484); // dark header surface
const _kBrandLight   = PdfColor.fromInt(0xFFEDF4F9); // AppColors.primaryLight
const _kSuccess      = PdfColor.fromInt(0xFF2E7D32); // AppColors.success
const _kSuccessLight = PdfColor.fromInt(0xFFE6F5E8); // AppColors.successBg
const _kWarning      = PdfColor.fromInt(0xFFF57C00); // AppColors.warning
const _kWarningLight = PdfColor.fromInt(0xFFFFF3E0); // AppColors.warningBg
const _kError        = PdfColor.fromInt(0xFFD32F2F); // AppColors.error
const _kErrorLight   = PdfColor.fromInt(0xFFFDF0F0); // AppColors.errorBg
const _kEmgGreen     = PdfColor.fromInt(0xFF1B7A3F); // AppColors.emergencyMode
const _kEmgGreenBg   = PdfColor.fromInt(0xFFE6F4EC); // AppColors.emergencyModeBg
const _kPediatric    = PdfColor.fromInt(0xFF057692); // AppColors.pediatric
const _kPediatricBg  = PdfColor.fromInt(0xFFE0F7FA); // AppColors.pediatricLight
const _kTextPrimary  = PdfColor.fromInt(0xFF111827); // AppColors.textPrimary
const _kTextSecond   = PdfColor.fromInt(0xFF4B5563); // AppColors.textSecondary
const _kTextDisabled = PdfColor.fromInt(0xFF9CA3AF); // AppColors.textDisabled
const _kDivider      = PdfColor.fromInt(0xFFE8EEF6); // AppColors.divider
const _kWhite        = PdfColors.white;
const _kBgGrey       = PdfColor.fromInt(0xFFF2F6FC); // AppColors.screenBgGrey
const _kBgCard       = PdfColor.fromInt(0xFFF8FAFC);

class ExportService {
  ExportService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API — PDFs
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> exportSingleSessionPdf(
      SessionDetail detail, { String? username }) async {
    try {
      final bytes = await _buildSingleSessionPdf(detail, username: username);
      final name  = 'cpr_session_${_stamp(detail.sessionStart)}.pdf';
      return _shareFile(bytes, name, 'CPR Assist — Session Report', 'application/pdf');
    } catch (e) { debugPrint('ExportService PDF single share: $e'); return false; }
  }

  static Future<bool> downloadSingleSessionPdf(
      SessionDetail detail, { String? username }) async {
    try {
      final bytes = await _buildSingleSessionPdf(detail, username: username);
      final name  = 'cpr_session_${_stamp(detail.sessionStart)}.pdf';
      return _saveToDevice(bytes, name);
    } catch (e) { debugPrint('ExportService PDF single download: $e'); return false; }
  }

  static Future<bool> exportMultiSessionPdf(
      List<SessionSummary> sessions, { String? username }) async {
    if (sessions.isEmpty) return false;
    try {
      final bytes = await _buildMultiSessionPdf(sessions, username: username);
      final name  = 'cpr_sessions_${sessions.length}_${_dateStamp()}.pdf';
      return _shareFile(bytes, name, 'CPR Assist — Session History Report', 'application/pdf');
    } catch (e) { debugPrint('ExportService PDF multi share: $e'); return false; }
  }

  static Future<bool> downloadMultiSessionPdf(
      List<SessionSummary> sessions, { String? username }) async {
    if (sessions.isEmpty) return false;
    try {
      final bytes = await _buildMultiSessionPdf(sessions, username: username);
      final name  = 'cpr_sessions_${sessions.length}_${_dateStamp()}.pdf';
      return _saveToDevice(bytes, name);
    } catch (e) { debugPrint('ExportService PDF multi download: $e'); return false; }
  }

  static Future<bool> exportCertificate({
    required String username,
    required CertificateMilestone milestone,
  }) async {
    try {
      final bytes = await _buildCertificatePdf(username: username, milestone: milestone);
      final name  = 'cpr_cert_${milestone.id}_${_dateStamp()}.pdf';
      return _shareFile(bytes, name, 'CPR Assist — ${milestone.title} Certificate', 'application/pdf');
    } catch (e) { debugPrint('ExportService certificate: $e'); return false; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API — SUMMARY CSV
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> exportSingleSessionCsv(
      SessionSummary s, {
        SessionDetail? detail,
      }) async {
    try {
      final csv = _buildSingleSessionMetricsCsv(s, detail: detail);
      final name = 'cpr_session_metrics_${_stamp(s.sessionStart)}.csv';
      return _shareFile(
        _csvBytes(csv),
        name,
        'CPR Assist — Session Metrics',
        'text/csv',
      );
    } catch (e) {
      debugPrint('ExportService single metrics CSV share: $e');
      return false;
    }
  }

  static Future<bool> downloadSingleSessionCsv(
      SessionSummary s, {
        SessionDetail? detail,
      }) async {
    try {
      final csv = _buildSingleSessionMetricsCsv(s, detail: detail);
      final name = 'cpr_session_metrics_${_stamp(s.sessionStart)}.csv';
      return _saveToDevice(_csvBytes(csv), name);
    } catch (e) {
      debugPrint('ExportService single metrics CSV download: $e');
      return false;
    }
  }

  static Future<bool> exportSessionsAsCsv(
      List<SessionSummary> sessions, { String filename = 'cpr_assist_sessions' }) async {
    if (sessions.isEmpty) return false;
    try {
      final csv  = _buildSummaryCsv(sessions);
      final name = '${filename}_${_dateStamp()}.csv';
      return _shareFile(_csvBytes(csv), name, 'CPR Assist — Session Data', 'text/csv');
    } catch (e) { debugPrint('ExportService CSV share: $e'); return false; }
  }

  static Future<bool> downloadSessionsAsCsv(
      List<SessionSummary> sessions, { String filename = 'cpr_assist_sessions' }) async {
    if (sessions.isEmpty) return false;
    try {
      final csv  = _buildSummaryCsv(sessions);
      final name = '${filename}_${_dateStamp()}.csv';
      return _saveToDevice(utf8.encode(csv), name);
    } catch (e) { debugPrint('ExportService CSV download: $e'); return false; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API — RAW CSVs
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> exportRawCompressionsCsv(SessionDetail d) async {
    if (d.compressions.isEmpty) return false;
    try {
      final csv  = _buildCompressionsCsv(d);
      final name = 'cpr_compressions_${_stamp(d.sessionStart)}.csv';
      return _shareFile(_csvBytes(csv), name, 'CPR Assist — Raw Compressions', 'text/csv');
    } catch (e) { debugPrint('ExportService compressions share: $e'); return false; }
  }

  static Future<bool> downloadRawCompressionsCsv(SessionDetail d) async {
    if (d.compressions.isEmpty) return false;
    try {
      final csv  = _buildCompressionsCsv(d);
      final name = 'cpr_compressions_${_stamp(d.sessionStart)}.csv';
      return _saveToDevice(_csvBytes(csv), name);
    } catch (e) { debugPrint('ExportService compressions download: $e'); return false; }
  }

  static Future<bool> exportRawRescuerVitalsCsv(SessionDetail d) async {
    if (d.rescuerVitals.isEmpty) return false;
    try {
      final csv  = _buildRescuerVitalsCsv(d);
      final name = 'cpr_rescuer_vitals_${_stamp(d.sessionStart)}.csv';
      return _shareFile(_csvBytes(csv), name, 'CPR Assist — Rescuer Vitals', 'text/csv');
    } catch (e) { debugPrint('ExportService vitals share: $e'); return false; }
  }

  static Future<bool> downloadRawRescuerVitalsCsv(SessionDetail d) async {
    if (d.rescuerVitals.isEmpty) return false;
    try {
      final csv  = _buildRescuerVitalsCsv(d);
      final name = 'cpr_rescuer_vitals_${_stamp(d.sessionStart)}.csv';
      return _saveToDevice(_csvBytes(csv), name);
    } catch (e) { debugPrint('ExportService vitals download: $e'); return false; }
  }

  static Future<bool> exportRawVentilationsCsv(SessionDetail d) async {
    if (d.ventilations.isEmpty) return false;
    try {
      final csv  = _buildVentilationsCsv(d);
      final name = 'cpr_ventilations_${_stamp(d.sessionStart)}.csv';
      return _shareFile(_csvBytes(csv), name, 'CPR Assist — Ventilations', 'text/csv');
    } catch (e) { debugPrint('ExportService ventilations share: $e'); return false; }
  }

  static Future<bool> downloadRawVentilationsCsv(SessionDetail d) async {
    if (d.ventilations.isEmpty) return false;
    try {
      final csv  = _buildVentilationsCsv(d);
      final name = 'cpr_ventilations_${_stamp(d.sessionStart)}.csv';
      return _saveToDevice(_csvBytes(csv), name);
    } catch (e) { debugPrint('ExportService ventilations download: $e'); return false; }
  }

  static Future<bool> exportRawPulseChecksCsv(SessionDetail d) async {
    if (d.pulseChecks.isEmpty) return false;
    try {
      final csv  = _buildPulseChecksCsv(d);
      final name = 'cpr_pulse_checks_${_stamp(d.sessionStart)}.csv';
      return _shareFile(_csvBytes(csv), name, 'CPR Assist — Pulse Checks', 'text/csv');
    } catch (e) { debugPrint('ExportService pulse checks share: $e'); return false; }
  }

  static Future<bool> downloadRawPulseChecksCsv(SessionDetail d) async {
    if (d.pulseChecks.isEmpty) return false;
    try {
      final csv  = _buildPulseChecksCsv(d);
      final name = 'cpr_pulse_checks_${_stamp(d.sessionStart)}.csv';
      return _saveToDevice(_csvBytes(csv), name);
    } catch (e) { debugPrint('ExportService pulse checks download: $e'); return false; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API — ZIP (all raw streams)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> exportRawDataZip(SessionDetail d) async {
    try {
      final bytes = await _buildRawDataZip(d);
      if (bytes == null) return false;
      final name = 'cpr_raw_${_stamp(d.sessionStart)}.zip';
      return _shareFile(bytes, name, 'CPR Assist — Raw Session Data', 'application/zip');
    } catch (e) { debugPrint('ExportService ZIP share: $e'); return false; }
  }

  static Future<bool> downloadRawDataZip(SessionDetail d) async {
    try {
      final bytes = await _buildRawDataZip(d);
      if (bytes == null) return false;
      final name = 'cpr_raw_${_stamp(d.sessionStart)}.zip';
      return _saveToDevice(bytes, name);
    } catch (e) { debugPrint('ExportService ZIP download: $e'); return false; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CSV BUILDERS — one per data shape, used by both share and download
  // ═══════════════════════════════════════════════════════════════════════════


  // ── Single Session Metrics CSV ───────────────────────────────────────────────
// Sectioned summary for one session.
// Not raw data. Raw timestamp/event data stays in the raw ZIP exports.

  static String _buildSingleSessionMetricsCsv(
      SessionSummary s, {
        SessionDetail? detail,
      }) {
    final sb = StringBuffer();

    final isPediatric = s.scenario == 'pediatric';
    final isTraining = s.isTraining;

    final depthMin = isPediatric
        ? CprTargets.depthMinPediatric
        : CprTargets.depthMin;
    final depthMax = isPediatric
        ? CprTargets.depthMaxPediatric
        : CprTargets.depthMax;

    final depthTarget = '${depthMin.toStringAsFixed(1)}-${depthMax.toStringAsFixed(1)} cm';
    final rateTarget =
        '${CprTargets.rateMin.toStringAsFixed(0)}-${CprTargets.rateMax.toStringAsFixed(0)} BPM';
    const ccfTarget = '≥80%';

    final n = s.compressionCount > 0 ? s.compressionCount.toDouble() : 0.0;

    String pctFromCount(int count) {
      if (n <= 0) return '';
      return '${(count / n * 100).toStringAsFixed(1)}%';
    }

    String pctValue(double value) {
      return '${value.toStringAsFixed(1)}%';
    }

    String fmtNum(double value, {int digits = 1, String suffix = ''}) {
      if (value <= 0) return '';
      return '${value.toStringAsFixed(digits)}$suffix';
    }

    String fmtNullable(double? value, {int digits = 1, String suffix = ''}) {
      if (value == null || value <= 0) return '';
      return '${value.toStringAsFixed(digits)}$suffix';
    }

    String fmtIntOrBlank(int value) {
      return value > 0 ? value.toString() : '';
    }

    String fmtDelta(double start, double end, {int digits = 1, String suffix = ''}) {
      if (start <= 0 || end <= 0) return '';
      final delta = end - start;
      final sign = delta > 0 ? '+' : '';
      return '$sign${delta.toStringAsFixed(digits)}$suffix';
    }

    void blankLine() => sb.writeln(',');

    void section(String title) {
      blankLine();
      sb.writeln(title);
    }

    void metricHeader() {
      sb.writeln('Metric,Target,Value');
    }

    void qualityHeader() {
      sb.writeln('Metric,Target,Count,Percentage');
    }

    void row2(String metric, String value) {
      sb.writeln('${_esc(metric)},${_esc(value)}');
    }

    void row3(String metric, String target, String value) {
      sb.writeln('${_esc(metric)},${_esc(target)},${_esc(value)}');
    }

    void row4(String metric, String target, String count, String percentage) {
      sb.writeln('${_esc(metric)},${_esc(target)},${_esc(count)},${_esc(percentage)}');
    }

    // Detail-only calculations.
    final allTargetsMetCount = detail?.compressions
        .where((c) => c.isPerfectFor(
      depthMin: depthMin,
      depthMax: depthMax,
    ))
        .length;

    final avgWristAlignment = detail != null && detail.compressions.isNotEmpty
        ? detail.compressions
        .map((c) => c.wristAlignmentAngle)
        .reduce((a, b) => a + b) /
        detail.compressions.length
        : 0.0;

    final ventilationPauseTime = detail != null && detail.ventilations.isNotEmpty
        ? detail.ventilations
        .map((v) => v.durationSec)
        .reduce((a, b) => a + b)
        : 0.0;

    final rateVariability = detail?.rateVariability ?? 0.0;
    final timeToFirstCompression = detail?.timeToFirstCompression ?? 0.0;
    final correctVentilations = detail?.correctVentilations ?? 0;
    final patientSpO2LastCheck = detail?.patientSpO2LastCheck;

    final lastPulseCheck = detail != null && detail.pulseChecks.isNotEmpty
        ? detail.pulseChecks.last
        : null;

    // Rescuer vitals start/end.
    final rescuerVitals = detail?.rescuerVitals ?? [];

    final hrVitals = rescuerVitals.where((v) => v.heartRate > 0).toList();
    final spO2Vitals = rescuerVitals.where((v) => v.spO2 > 0).toList();
    final tempVitals = rescuerVitals.where((v) => v.temperature > 0).toList();

    final startHR = hrVitals.isNotEmpty ? hrVitals.first.heartRate : 0.0;
    final endHR = hrVitals.isNotEmpty ? hrVitals.last.heartRate : 0.0;

    final startSpO2 = spO2Vitals.isNotEmpty ? spO2Vitals.first.spO2 : 0.0;
    final endSpO2 = spO2Vitals.isNotEmpty ? spO2Vitals.last.spO2 : 0.0;

    final startTemp = tempVitals.isNotEmpty ? tempVitals.first.temperature : 0.0;
    final endTemp = tempVitals.isNotEmpty ? tempVitals.last.temperature : 0.0;

    final avgSignalQuality = rescuerVitals.isNotEmpty
        ? rescuerVitals.map((v) => v.signalQuality).reduce((a, b) => a + b) /
        rescuerVitals.length
        : 0.0;

    // ── Title ────────────────────────────────────────────────────────────────
    sb.writeln('CPR Assist - Session Metrics Summary');

    // ── INFO ─────────────────────────────────────────────────────────────────
    section('INFO');
    sb.writeln('Metric,Value');
    row2('Session ID', s.id?.toString() ?? 'local');
    row2('Date & Time', _fmtDt(s.sessionStart));
    row2(
      'Mode',
      s.mode == 'emergency'
          ? 'Emergency'
          : s.mode == 'training_no_feedback'
          ? 'Training (No Feedback)'
          : 'Training',
    );
    row2('Scenario', isPediatric ? 'Pediatric' : 'Adult');
    row2('Duration', _mmss(s.sessionDuration));
    if (s.note != null && s.note!.isNotEmpty) {
      row2('Note', s.note!);
    }

    // ── GRADE ────────────────────────────────────────────────────────────────
    if (isTraining) {
      section('GRADE');
      metricHeader();
      row3('Total Grade (%)', '', s.totalGrade.toStringAsFixed(1));
    }

    // ── COMPRESSION TOTALS ───────────────────────────────────────────────────
    section('COMPRESSION TOTALS');
    metricHeader();
    row3('Total Compressions', '', s.compressionCount.toString());
    row3('Leaning Events', '0', s.leaningCount.toString());
    row3('Over-Force Events', '0', s.overForceCount.toString());

    // ── COMPRESSION QUALITY ──────────────────────────────────────────────────
    section('COMPRESSION QUALITY');
    qualityHeader();
    row4(
      'Depth Target Met',
      depthTarget,
      s.correctDepth.toString(),
      pctFromCount(s.correctDepth),
    );
    row4(
      'Rate Target Met',
      rateTarget,
      s.correctFrequency.toString(),
      pctFromCount(s.correctFrequency),
    );
    row4(
      'Recoil Target Met',
      'Full recoil',
      s.correctRecoil.toString(),
      pctFromCount(s.correctRecoil),
    );
    row4(
      'Posture Target Met',
      'Align ≤${CprTargets.alignmentMaxDeg.toStringAsFixed(0)}° / Flex ≤${CprTargets.flexionMaxDeg.toStringAsFixed(0)}°',
      s.correctPosture.toString(),
      pctFromCount(s.correctPosture),
    );
    row4(
      'Depth + Rate Target Met',
      'Depth + rate targets',
      s.depthRateCombo.toString(),
      pctFromCount(s.depthRateCombo),
    );
    row4(
      'All Targets Met',
      'Depth + rate + recoil + posture',
      allTargetsMetCount?.toString() ?? '',
      allTargetsMetCount != null ? pctFromCount(allTargetsMetCount) : '',
    );

    // ── AVERAGES & DISTRIBUTION ──────────────────────────────────────────────
    section('AVERAGES & DISTRIBUTION');
    metricHeader();
    row3('Average Depth', depthTarget, fmtNum(s.averageDepth, digits: 2, suffix: ' cm'));
    row3('Average Effective Depth', '', fmtNum(s.averageEffectiveDepth, digits: 2, suffix: ' cm'));
    row3('Peak Depth', '', fmtNum(s.peakDepth, digits: 2, suffix: ' cm'));
    row3('Depth SD', '', fmtNum(s.depthSD, digits: 2, suffix: ' cm'));
    row3('Depth Consistency', '', pctValue(s.depthConsistency));
    row3('Average Rate', rateTarget, fmtNum(s.averageFrequency, digits: 1, suffix: ' BPM'));
    row3('Rate Consistency', '', pctValue(s.frequencyConsistency));
    row3('Rate Variability', '', fmtNum(rateVariability, digits: 0, suffix: ' ms'));
    if (avgWristAlignment > 0) {
      row3(
        'Average Wrist Alignment',
        '≤${CprTargets.alignmentMaxDeg.toStringAsFixed(0)}°',
        '${avgWristAlignment.toStringAsFixed(1)}°',
      );
    }

    // ── FLOW & TIMING ────────────────────────────────────────────────────────
    section('FLOW & TIMING');
    metricHeader();
    final ccfPct = s.handsOnRatio * 100;
    row3('CCF', ccfTarget, pctValue(ccfPct));
    row3('Time to First Compression', '', fmtNum(timeToFirstCompression, digits: 1, suffix: ' s'));
    row3('No-Flow Intervals', '', s.noFlowIntervals.toString());
    row3('No-Flow Time', '', fmtNum(s.noFlowTime, digits: 1, suffix: ' s'));
    row3('Unplanned Pauses', '0', s.unplannedPauseCount.toString());
    row3('Unplanned Pause Time', '0 s', fmtNum(s.unplannedPauseTime, digits: 1, suffix: ' s'));

    // ── VENTILATION ──────────────────────────────────────────────────────────
    section('VENTILATION');
    metricHeader();
    row3('Ventilation Windows Recorded', '', s.ventilationCount.toString());
    row3('Ventilation Target Met Windows', '', fmtIntOrBlank(correctVentilations));
    row3('Ventilation Target Met (%)', 'Window timing', fmtNum(s.ventilationCompliance, digits: 1, suffix: '%'));
    row3('Total Ventilation Pause Time', '', fmtNum(ventilationPauseTime, digits: 1, suffix: ' s'));

    // ── PULSE CHECKS ─────────────────────────────────────────────────────────
    section('PULSE CHECKS');
    metricHeader();
    row3('Pulse Checks Prompted', '', s.pulseChecksPrompted.toString());
    row3('Pulse Checks Done', '', s.pulseChecksComplied.toString());
    row3('ROSC Detected', '', _yn(s.pulseDetectedFinal));

    if (lastPulseCheck != null) {
      const classLabels = ['ABSENT', 'UNCERTAIN', 'PRESENT'];
      final cls = lastPulseCheck.classification.clamp(0, 2);

      row3('Last Pulse Classification', '', classLabels[cls]);
      row3(
        'Last Detected BPM',
        '',
        lastPulseCheck.detectedBpm > 0
            ? '${lastPulseCheck.detectedBpm.toStringAsFixed(1)} BPM'
            : '',
      );
      row3('Last Pulse Confidence', '', '${lastPulseCheck.confidence}%');
      row3(
        'Patient SpO2 Last Check',
        '',
        lastPulseCheck.patientSpO2 > 0
            ? '${lastPulseCheck.patientSpO2.toStringAsFixed(1)}%'
            : '',
      );
    } else {
      row3('Last Pulse Classification', '', '');
      row3('Last Detected BPM', '', '');
      row3('Last Pulse Confidence', '', '');
      row3(
        'Patient SpO2 Last Check',
        '',
        patientSpO2LastCheck != null
            ? '${patientSpO2LastCheck.toStringAsFixed(1)}%'
            : '',
      );
    }

    // ── FATIGUE & RESCUER ────────────────────────────────────────────────────
    section('FATIGUE & RESCUER');
    metricHeader();
    row3(
      'Fatigue Onset',
      '',
      s.fatigueOnsetIndex > 0 ? 'Compression #${s.fatigueOnsetIndex}' : '',
    );
    row3('Rescuer Swaps', '', s.rescuerSwapCount.toString());

    row3('Rescuer HR at Start', '', fmtNum(startHR, digits: 1, suffix: ' BPM'));
    row3('Rescuer HR at End', '', fmtNum(endHR, digits: 1, suffix: ' BPM'));
    row3('Rescuer HR Change', '', fmtDelta(startHR, endHR, digits: 1, suffix: ' BPM'));

    row3('Rescuer SpO2 at Start', '', fmtNum(startSpO2, digits: 1, suffix: '%'));
    row3('Rescuer SpO2 at End', '', fmtNum(endSpO2, digits: 1, suffix: '%'));
    row3('Rescuer SpO2 Change', '', fmtDelta(startSpO2, endSpO2, digits: 1, suffix: '%'));

    row3('Rescuer Skin Temp at Start', '', fmtNum(startTemp, digits: 2, suffix: ' C'));
    row3('Rescuer Skin Temp at End', '', fmtNum(endTemp, digits: 2, suffix: ' C'));
    row3('Rescuer Skin Temp Change', '', fmtDelta(startTemp, endTemp, digits: 2, suffix: ' C'));

    row3('Average Signal Quality', '', fmtNum(avgSignalQuality, digits: 1));
    row3('Rescuer HR at Last Pause', '', fmtNullable(s.rescuerHRLastPause, digits: 1, suffix: ' BPM'));
    row3('Rescuer SpO2 at Last Pause', '', fmtNullable(s.rescuerSpO2LastPause, digits: 1, suffix: '%'));
    row3('Patient Temperature', '', fmtNullable(s.patientTemperature, digits: 1, suffix: ' C'));

    return sb.toString();
  }


  // ── Summary CSV ────────────────────────────────────────────────────────────
  // Headers use human-readable Title Case with units in parentheses.
  // Dates formatted as "YYYY-MM-DD HH:MM:SS" so Excel auto-detects them.
  // Booleans are YES/NO. Percentages are plain numbers (e.g. 78.3, not "78.3%").
  // Section comment rows (starting with #) group columns visually in Excel.

// ── Multi-Session Metrics CSV ────────────────────────────────────────────────
// Sectioned comparison table.
// One metric per row. Sessions are columns.
// Raw timestamp/event data stays in the raw ZIP exports.

  static String _buildSummaryCsv(List<SessionSummary> sessions) {
    final sb = StringBuffer();

    final sessionLabels = List.generate(
      sessions.length,
          (i) => 'Session ${i + 1}',
    );

    String pctFromCount(int count, int total) {
      if (total <= 0) return '';
      return '${(count / total * 100).toStringAsFixed(1)}%';
    }

    String pctValue(double value) {
      return '${value.toStringAsFixed(1)}%';
    }

    String fmtNum(double value, {int digits = 1, String suffix = ''}) {
      if (value <= 0) return '';
      return '${value.toStringAsFixed(digits)}$suffix';
    }

    String fmtNullable(double? value, {int digits = 1, String suffix = ''}) {
      if (value == null || value <= 0) return '';
      return '${value.toStringAsFixed(digits)}$suffix';
    }

    String modeLabel(SessionSummary s) {
      if (s.mode == 'emergency') return 'Emergency';
      if (s.mode == 'training_no_feedback') return 'Training (No Feedback)';
      return 'Training';
    }

    String scenarioLabel(SessionSummary s) {
      return s.scenario == 'pediatric' ? 'Pediatric' : 'Adult';
    }

    String depthTargetLabel(SessionSummary s) {
      final isPediatric = s.scenario == 'pediatric';
      final min = isPediatric
          ? CprTargets.depthMinPediatric
          : CprTargets.depthMin;
      final max = isPediatric
          ? CprTargets.depthMaxPediatric
          : CprTargets.depthMax;

      return '${min.toStringAsFixed(1)}-${max.toStringAsFixed(1)} cm';
    }

    String genericDepthTarget() {
      return 'Adult ${CprTargets.depthMin.toStringAsFixed(1)}-${CprTargets.depthMax.toStringAsFixed(1)} cm / '
          'Pediatric ${CprTargets.depthMinPediatric.toStringAsFixed(1)}-${CprTargets.depthMaxPediatric.toStringAsFixed(1)} cm';
    }

    String rateTarget() {
      return '${CprTargets.rateMin.toStringAsFixed(0)}-${CprTargets.rateMax.toStringAsFixed(0)} BPM';
    }

    String postureTarget() {
      return 'Align ≤${CprTargets.alignmentMaxDeg.toStringAsFixed(0)}° / '
          'Flex ≤${CprTargets.flexionMaxDeg.toStringAsFixed(0)}°';
    }

    void blankLine() => sb.writeln(',');

    void section(String title) {
      blankLine();
      sb.writeln(title);
      sb.writeln([
        'Metric',
        'Target',
        ...sessionLabels,
      ].join(','));
    }

    void row(
        String metric,
        String target,
        List<String> values,
        ) {
      sb.writeln([
        _esc(metric),
        _esc(target),
        ...values.map(_esc),
      ].join(','));
    }

    // ── Title ────────────────────────────────────────────────────────────────
    sb.writeln('CPR Assist - Multi-Session Metrics Summary');
    sb.writeln('Generated,${_fmtDt(DateTime.now())}');
    sb.writeln('Sessions,${sessions.length}');

    // ── INFO ─────────────────────────────────────────────────────────────────
    section('INFO');

    row(
      'Session ID',
      '',
      sessions.map((s) => s.id?.toString() ?? 'local').toList(),
    );

    row(
      'Date & Time',
      '',
      sessions.map((s) => _fmtDt(s.sessionStart)).toList(),
    );

    row(
      'Mode',
      '',
      sessions.map(modeLabel).toList(),
    );

    row(
      'Scenario',
      '',
      sessions.map(scenarioLabel).toList(),
    );

    row(
      'Duration',
      '',
      sessions.map((s) => _mmss(s.sessionDuration)).toList(),
    );

    row(
      'Depth Target',
      '',
      sessions.map(depthTargetLabel).toList(),
    );

    // ── GRADE ────────────────────────────────────────────────────────────────
    section('GRADE');

    row(
      'Total Grade (%)',
      '',
      sessions
          .map((s) => s.isEmergency ? '' : s.totalGrade.toStringAsFixed(1))
          .toList(),
    );

    // ── COMPRESSION TOTALS ───────────────────────────────────────────────────
    section('COMPRESSION TOTALS');

    row(
      'Total Compressions',
      '',
      sessions.map((s) => s.compressionCount.toString()).toList(),
    );

    row(
      'Leaning Events',
      '0',
      sessions.map((s) => s.leaningCount.toString()).toList(),
    );

    row(
      'Over-Force Events',
      '0',
      sessions.map((s) => s.overForceCount.toString()).toList(),
    );

    // ── COMPRESSION QUALITY - COUNTS ─────────────────────────────────────────
    section('COMPRESSION QUALITY - COUNTS');

    row(
      'Depth Target Met',
      genericDepthTarget(),
      sessions.map((s) => s.correctDepth.toString()).toList(),
    );

    row(
      'Rate Target Met',
      rateTarget(),
      sessions.map((s) => s.correctFrequency.toString()).toList(),
    );

    row(
      'Recoil Target Met',
      'Full recoil',
      sessions.map((s) => s.correctRecoil.toString()).toList(),
    );

    row(
      'Posture Target Met',
      postureTarget(),
      sessions.map((s) => s.correctPosture.toString()).toList(),
    );

    row(
      'Depth + Rate Target Met',
      'Depth + rate targets',
      sessions.map((s) => s.depthRateCombo.toString()).toList(),
    );

    // Important:
    // All Targets Met cannot be computed reliably from SessionSummary unless
    // you store it in the database/model. It needs per-compression detail.
    row(
      'All Targets Met',
      'Depth + rate + recoil + posture',
      sessions.map((_) => '').toList(),
    );

    // ── COMPRESSION QUALITY - PERCENTAGES ────────────────────────────────────
    section('COMPRESSION QUALITY - PERCENTAGES');

    row(
      'Depth Target Met',
      genericDepthTarget(),
      sessions
          .map((s) => pctFromCount(s.correctDepth, s.compressionCount))
          .toList(),
    );

    row(
      'Rate Target Met',
      rateTarget(),
      sessions
          .map((s) => pctFromCount(s.correctFrequency, s.compressionCount))
          .toList(),
    );

    row(
      'Recoil Target Met',
      'Full recoil',
      sessions
          .map((s) => pctFromCount(s.correctRecoil, s.compressionCount))
          .toList(),
    );

    row(
      'Posture Target Met',
      postureTarget(),
      sessions
          .map((s) => pctFromCount(s.correctPosture, s.compressionCount))
          .toList(),
    );

    row(
      'Depth + Rate Target Met',
      'Depth + rate targets',
      sessions
          .map((s) => pctFromCount(s.depthRateCombo, s.compressionCount))
          .toList(),
    );

    row(
      'All Targets Met',
      'Depth + rate + recoil + posture',
      sessions.map((_) => '').toList(),
    );

    // ── AVERAGES & DISTRIBUTION ──────────────────────────────────────────────
    section('AVERAGES & DISTRIBUTION');

    row(
      'Average Depth',
      genericDepthTarget(),
      sessions
          .map((s) => fmtNum(s.averageDepth, digits: 2, suffix: ' cm'))
          .toList(),
    );

    row(
      'Average Effective Depth',
      '',
      sessions
          .map((s) => fmtNum(s.averageEffectiveDepth, digits: 2, suffix: ' cm'))
          .toList(),
    );

    row(
      'Peak Depth',
      '',
      sessions
          .map((s) => fmtNum(s.peakDepth, digits: 2, suffix: ' cm'))
          .toList(),
    );

    row(
      'Depth SD',
      '',
      sessions
          .map((s) => fmtNum(s.depthSD, digits: 2, suffix: ' cm'))
          .toList(),
    );

    row(
      'Depth Consistency',
      '',
      sessions.map((s) => pctValue(s.depthConsistency)).toList(),
    );

    row(
      'Average Rate',
      rateTarget(),
      sessions
          .map((s) => fmtNum(s.averageFrequency, digits: 1, suffix: ' BPM'))
          .toList(),
    );

    row(
      'Rate Consistency',
      '',
      sessions.map((s) => pctValue(s.frequencyConsistency)).toList(),
    );

    // ── FLOW & TIMING ────────────────────────────────────────────────────────
    section('FLOW & TIMING');

    row(
      'CCF',
      '≥80%',
      sessions
          .map((s) => pctValue(s.handsOnRatio * 100))
          .toList(),
    );

    row(
      'No-Flow Intervals',
      '',
      sessions.map((s) => s.noFlowIntervals.toString()).toList(),
    );

    row(
      'No-Flow Time',
      '',
      sessions
          .map((s) => fmtNum(s.noFlowTime, digits: 1, suffix: ' s'))
          .toList(),
    );

    row(
      'Unplanned Pauses',
      '0',
      sessions.map((s) => s.unplannedPauseCount.toString()).toList(),
    );

    row(
      'Unplanned Pause Time',
      '0 s',
      sessions
          .map((s) => fmtNum(s.unplannedPauseTime, digits: 1, suffix: ' s'))
          .toList(),
    );

    row(
      'Time to First Compression',
      '',
      sessions.map((_) => '').toList(),
    );

    // ── VENTILATION ──────────────────────────────────────────────────────────
    section('VENTILATION');

    row(
      'Ventilation Windows Recorded',
      '',
      sessions.map((s) => s.ventilationCount.toString()).toList(),
    );

    row(
      'Ventilation Target Met Windows',
      '',
      sessions.map((s) {
        if (s.ventilationCount <= 0) return '';
        final count = (s.ventilationCompliance / 100 * s.ventilationCount).round();
        return count.toString();
      }).toList(),
    );

    row(
      'Ventilation Target Met (%)',
      'Window timing',
      sessions
          .map((s) => s.ventilationCount > 0
          ? pctValue(s.ventilationCompliance)
          : '')
          .toList(),
    );

    // ── PULSE CHECKS ─────────────────────────────────────────────────────────
    section('PULSE CHECKS');

    row(
      'Pulse Checks Prompted',
      '',
      sessions.map((s) => s.pulseChecksPrompted.toString()).toList(),
    );

    row(
      'Pulse Checks Done',
      '',
      sessions.map((s) => s.pulseChecksComplied.toString()).toList(),
    );

    row(
      'ROSC Detected',
      '',
      sessions.map((s) => _yn(s.pulseDetectedFinal)).toList(),
    );

    // ── FATIGUE & RESCUER ────────────────────────────────────────────────────
    section('FATIGUE & RESCUER');

    row(
      'Fatigue Onset',
      '',
      sessions
          .map((s) => s.fatigueOnsetIndex > 0
          ? 'Compression #${s.fatigueOnsetIndex}'
          : '')
          .toList(),
    );

    row(
      'Rescuer Swaps',
      '',
      sessions.map((s) => s.rescuerSwapCount.toString()).toList(),
    );

    row(
      'Rescuer HR at Last Pause',
      '',
      sessions
          .map((s) => fmtNullable(s.rescuerHRLastPause, digits: 1, suffix: ' BPM'))
          .toList(),
    );

    row(
      'Rescuer SpO2 at Last Pause',
      '',
      sessions
          .map((s) => fmtNullable(s.rescuerSpO2LastPause, digits: 1, suffix: '%'))
          .toList(),
    );

    row(
      'Patient Temperature',
      '',
      sessions
          .map((s) => fmtNullable(s.patientTemperature, digits: 1, suffix: ' C'))
          .toList(),
    );

    return sb.toString();
  }


  // ── Raw Compressions CSV ── Unified timeline ─────────────────────────────
  // One row per event in chronological order. Event Type identifies each row.
  // Filter in Python: df[df['Event Type']=='COMPRESSION']

  static String _buildCompressionsCsv(SessionDetail d) {
    final isPediatric = d.scenario == 'pediatric';
    final depthMin    = isPediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;
    final depthMax    = isPediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;
    final isEmergency = d.mode == 'emergency';
    final nc          = d.compressions.length;

    // Unplanned pause = gap > 2 s not overlapping any planned window
    bool isPlannedGap(double a, double b) {
      return d.ventilations.any((v) {
        final vs = v.timestampMs / 1000.0;
        return a < vs + v.durationSec && b > vs;
      }) ||
          d.pulseChecks.any((p) {
            final ps = p.timestampMs / 1000.0;
            return a < ps + 10.0 && b > ps;
          });
    }

    // Summary stats — use SessionDetail values that match the session results screen.
    // depthConsistency / frequencyConsistency come from the glove's own real-time
    // counter (correctDepth / totalCompressions * 100) via SESSION_END, which is
    // what the results screen displays. Recomputing from the compressions array
    // gives different results due to peak-capture timing differences.
    final avgDepth  = d.averageDepth;
    final avgRate   = d.averageFrequency;
    // Convert consistency % back to count for display (n = pct/100 * total)
    final inDepthN  = nc > 0 ? (d.depthConsistency     / 100 * nc).round() : 0;
    final inRateN   = nc > 0 ? (d.frequencyConsistency / 100 * nc).round() : 0;

    // Unplanned pauses
    int unpN = 0;
    void scanGap(double a, double b) {
      if (b-a > 2.0 && !isPlannedGap(a,b)) { unpN++; }
    }
    if (nc > 0) {
      scanGap(0, d.compressions.first.timestampMs/1000.0);
      for (int i=1;i<nc;i++) {
        scanGap(d.compressions[i-1].timestampMs/1000.0, d.compressions[i].timestampMs/1000.0);
      }
      scanGap(d.compressions.last.timestampMs/1000.0, d.sessionDuration.toDouble());
    }

    final sb = StringBuffer();

    // ── HEADER ───────────────────────────────────────────────────────────
    sb.writeln('CPR Assist - Raw Session Timeline');
    sb.writeln(',');
    sb.writeln('Session ID,${d.id ?? "local"}');
    sb.writeln('Date & Time,${_fmtDt(d.sessionStart)}');
    sb.writeln('Mode,${d.mode == "emergency" ? "Emergency" : d.mode == "training_no_feedback" ? "Training (No Feedback)" : "Training"}');
    sb.writeln(
      'Scenario,${isPediatric ? "Pediatric" : "Adult"},'
          'Correct Depth Target,${depthMin.toStringAsFixed(1)}-${depthMax.toStringAsFixed(1)} cm',
    );
    if (d.note != null && d.note!.isNotEmpty) {
      sb.writeln('Note,${_esc(d.note!)}');
    }
    sb.writeln(',');

    sb.writeln('SUMMARY');
    sb.writeln('Duration,${_mmss(d.sessionDuration)}');
    sb.writeln('Total Compressions,$nc');
    sb.writeln('Time to First Compression (s),${d.timeToFirstCompression.toStringAsFixed(2)}');
    sb.writeln('Correct Depth Compressions,$inDepthN');
    sb.writeln('Correct Rate Compressions,$inRateN');
    sb.writeln('Correct Recoil Compressions,${d.correctRecoil}');
    sb.writeln('Avg Depth (cm),${avgDepth.toStringAsFixed(2)}');
    sb.writeln('Avg Rate (BPM),${avgRate.toStringAsFixed(1)}');
    sb.writeln('CCF (%),${(d.handsOnRatio * 100).toStringAsFixed(1)}');
    sb.writeln('No-Flow Intervals,${d.noFlowIntervals}');
    sb.writeln('No-Flow Time (s),${d.noFlowTime.toStringAsFixed(1)}');
    sb.writeln('Total Unplanned Pauses,${d.unplannedPauseCount}');
    if (d.unplannedPauseTime > 0) {
      sb.writeln(
        'Total Unplanned Pause Time (s),${d.unplannedPauseTime.toStringAsFixed(1)}',
      );
    }
    if (d.rescuerSwapCount > 0) sb.writeln('Rescuer Swaps,${d.rescuerSwapCount}');
    if (d.fatigueOnsetIndex > 0) {
      sb.writeln('Fatigue Onset Compression #,${d.fatigueOnsetIndex}');
    }
    if (isEmergency && d.pulseChecks.isNotEmpty) {
      sb.writeln('Pulse Checks,${d.pulseChecks.length}');
      sb.writeln('Final Outcome,${d.pulseDetectedFinal?"ROSC DETECTED":"NO ROSC"}');
    }
    sb.writeln(',');

    // ── Column headers ────────────────────────────────────────────────────
// This CSV exports one row per compression.
// Each row contains the peak compression values and the release/recoil values
// for the same compression, so the file is easier to read and analyze.
    final headers = [
      'A/A',
      'Compression #',

      // Timing
      'Peak Time (ms)',
      'Release Time (ms)',
      'Inter-compression Interval (ms)',
      'Unplanned Pause After (ms)',

      // Depth
      'Peak Depth (cm)',
      'Effective Depth (cm)',
      'Recoil Depth (cm)',
      'Depth Target Met (${depthMin.toStringAsFixed(1)}-${depthMax.toStringAsFixed(1)} cm)',

      // Compression phases
      'Downstroke Duration (ms)',
      'Recoil Duration (ms)',
      'Recoil Target Met (Full Recoil)',
      'Leaning Detected',

      // Force
      'Force (N)',
      'Over Force Detected',

      // Rate
      'Instant Rate (BPM)',
      'Rolling Rate (BPM)',
      'Rate Target Met (${CprTargets.rateMin.toStringAsFixed(0)}-${CprTargets.rateMax.toStringAsFixed(0)} BPM)',

      // Posture
      'Wrist Alignment (deg)',
      'Wrist Flexion (deg)',
      'Axis Deviation (deg)',
      'Posture Target Met (Align ≤${CprTargets.alignmentMaxDeg.toStringAsFixed(0)}° / Flex ≤${CprTargets.flexionMaxDeg.toStringAsFixed(0)}°)',

      // Overall
      'All Targets Met',
    ];

    String fmtNum(double value, {int digits = 1}) {
      return value > 0 ? value.toStringAsFixed(digits) : '';
    }

    String fmtInt(int value) {
      return value > 0 ? value.toString() : '';
    }

    List<String> mkCompressionRow({
      required int rowNum,
      required int compressionNum,

      required String peakTimeMs,
      required String releaseTimeMs,
      required String interCompressionInterval,
      required String unplannedPauseAfter,

      required String peakDepth,
      required String effectiveDepth,
      required String recoilDepth,
      required String depthTargetMet,

      required String downstrokeDuration,
      required String recoilDuration,
      required String recoilTargetMet,
      required String leaningDetected,

      required String force,
      required String overForceDetected,

      required String instantRate,
      required String rollingRate,
      required String rateTargetMet,

      required String wristAlignment,
      required String wristFlexion,
      required String axisDeviation,
      required String postureTargetMet,

      required String allTargetsMet,
    }) {
      return [
        '$rowNum',
        '$compressionNum',

        peakTimeMs,
        releaseTimeMs,
        interCompressionInterval,
        unplannedPauseAfter,

        peakDepth,
        effectiveDepth,
        recoilDepth,
        depthTargetMet,

        downstrokeDuration,
        recoilDuration,
        recoilTargetMet,
        leaningDetected,

        force,
        overForceDetected,

        instantRate,
        rollingRate,
        rateTargetMet,

        wristAlignment,
        wristFlexion,
        axisDeviation,
        postureTargetMet,

        allTargetsMet,
      ];
    }

// ── Write DATA ────────────────────────────────────────────────────────
    sb.writeln('DATA');
    sb.writeln(headers.join(','));

    for (int i = 0; i < d.compressions.length; i++) {
      final c = d.compressions[i];
      final compressionNum = i + 1;

      final peakMs = c.peakTimestampMs > 0 ? c.peakTimestampMs : c.timestampMs;
      final valleyMs = c.valleyTimestampMs;

      final instantRate = c.instantaneousRate;
      final rollingRate = c.frequency;
      final rateForTarget = instantRate > 0 ? instantRate : rollingRate;

      final depthTargetMet =
          c.depth >= depthMin && c.depth <= depthMax;

      final rateTargetMet =
          rateForTarget >= CprTargets.rateMin &&
              rateForTarget <= CprTargets.rateMax;

      final hasRecoilData =
          valleyMs > 0 ||
              c.valleyDepth > 0 ||
              c.recoilPhaseDurationMs > 0 ||
              c.leaningDetected;

      // Inter-compression interval: peak-to-peak interval.
      String interCompressionInterval = '';
      if (i > 0) {
        final prev = d.compressions[i - 1];
        final prevPeakMs = prev.peakTimestampMs > 0
            ? prev.peakTimestampMs
            : prev.timestampMs;

        final interval = peakMs - prevPeakMs;
        if (interval > 0) {
          interCompressionInterval = interval.toString();
        }
      }

      // Unplanned pause AFTER this compression.
      String pauseAfter = '';
      if (i < nc - 1) {
        final currentTime = (valleyMs > 0 ? valleyMs : peakMs) / 1000.0;

        final next = d.compressions[i + 1];
        final nextPeakMs = next.peakTimestampMs > 0
            ? next.peakTimestampMs
            : next.timestampMs;
        final nextTime = nextPeakMs / 1000.0;

        if (nextTime - currentTime > 2.0 &&
            !isPlannedGap(currentTime, nextTime)) {
          pauseAfter = ((nextTime - currentTime) * 1000).toStringAsFixed(0);
        }
      }

      final allTargetsMet =
          depthTargetMet &&
              rateTargetMet &&
              c.recoilAchieved &&
              c.postureOk;

      sb.writeln(mkCompressionRow(
        rowNum: i + 1,
        compressionNum: compressionNum,

        peakTimeMs: peakMs > 0 ? peakMs.toString() : '',
        releaseTimeMs: valleyMs > 0 ? valleyMs.toString() : '',
        interCompressionInterval: interCompressionInterval,
        unplannedPauseAfter: pauseAfter,

        peakDepth: c.depth.toStringAsFixed(2),
        effectiveDepth: c.effectiveDepth > 0
            ? c.effectiveDepth.toStringAsFixed(2)
            : '',
        recoilDepth: c.valleyDepth > 0
            ? c.valleyDepth.toStringAsFixed(2)
            : '',
        depthTargetMet: _yn(depthTargetMet),

        downstrokeDuration: fmtInt(c.downstrokePhaseDurationMs),
        recoilDuration: fmtInt(c.recoilPhaseDurationMs),
        recoilTargetMet: hasRecoilData ? _yn(c.recoilAchieved) : '',
        leaningDetected: hasRecoilData ? _yn(c.leaningDetected) : '',

        force: fmtNum(c.force, digits: 1),
        overForceDetected: _yn(c.overForce),

        instantRate: fmtNum(instantRate, digits: 1),
        rollingRate: fmtNum(rollingRate, digits: 1),
        rateTargetMet: _yn(rateTargetMet),

        wristAlignment: c.wristAlignmentAngle.toStringAsFixed(1),
        wristFlexion: c.wristFlexionAngle.toStringAsFixed(1),
        axisDeviation: c.compressionAxisDev.toStringAsFixed(1),
        postureTargetMet: _yn(c.postureOk),

        allTargetsMet: _yn(allTargetsMet),
      ).join(','));
    }

    return sb.toString();
  }


  // ── Raw Rescuer Vitals CSV ─────────────────────────────────────────────────

  static String _buildRescuerVitalsCsv(SessionDetail d) {
    final n = d.rescuerVitals.length;

    final withHR = d.rescuerVitals.where((v) => v.heartRate > 0).toList();
    final withSpO2 = d.rescuerVitals.where((v) => v.spO2 > 0).toList();
    final withTemp = d.rescuerVitals.where((v) => v.temperature > 0).toList();
    final withRmssd = d.rescuerVitals.where((v) => v.rmssd > 0).toList();
    final withPi = d.rescuerVitals.where((v) => v.rescuerPi > 0).toList();
    final withFatigue = d.rescuerVitals.where((v) => v.fatigueScore > 0).toList();

    double avgOf(List<double> values) {
      if (values.isEmpty) return 0.0;
      return values.reduce((a, b) => a + b) / values.length;
    }

    String fmtDouble(double value, {int digits = 1}) {
      return value > 0 ? value.toStringAsFixed(digits) : '';
    }

    String fmtDelta(double start, double end, {int digits = 1}) {
      if (start <= 0 || end <= 0) return '';
      final delta = end - start;
      final sign = delta > 0 ? '+' : '';
      return '$sign${delta.toStringAsFixed(digits)}';
    }

    double firstValue(List<dynamic> list, double Function(dynamic v) getter) {
      if (list.isEmpty) return 0.0;
      return getter(list.first);
    }

    double lastValue(List<dynamic> list, double Function(dynamic v) getter) {
      if (list.isEmpty) return 0.0;
      return getter(list.last);
    }

    final avgHR = avgOf(withHR.map((v) => v.heartRate).toList());
    final avgSpO2 = avgOf(withSpO2.map((v) => v.spO2).toList());
    final avgTemp = avgOf(withTemp.map((v) => v.temperature).toList());
    final avgRmssd = avgOf(withRmssd.map((v) => v.rmssd.toDouble()).toList());
    final avgPi = avgOf(withPi.map((v) => v.rescuerPi.toDouble()).toList());
    final avgFatigue = avgOf(withFatigue.map((v) => v.fatigueScore.toDouble()).toList());

    final startHR = firstValue(withHR, (v) => v.heartRate);
    final endHR = lastValue(withHR, (v) => v.heartRate);

    final startSpO2 = firstValue(withSpO2, (v) => v.spO2);
    final endSpO2 = lastValue(withSpO2, (v) => v.spO2);

    final startTemp = firstValue(withTemp, (v) => v.temperature);
    final endTemp = lastValue(withTemp, (v) => v.temperature);

    final maxFatigue = withFatigue.isNotEmpty
        ? withFatigue.map((v) => v.fatigueScore).reduce((a, b) => a > b ? a : b)
        : 0;


    String contextForMs(int timestampMs) {
      final t = timestampMs / 1000.0;

      final inVentilation = d.ventilations.any((v) {
        final start = v.timestampMs / 1000.0;
        final end = start + v.durationSec;
        return t >= start && t <= end;
      });

      if (inVentilation) return 'ventilation';

      final inPulseCheck = d.pulseChecks.any((p) {
        final start = p.timestampMs / 1000.0;
        final end = start + 10.0;
        return t >= start && t <= end;
      });

      if (inPulseCheck) return 'pulse_check';

      if (d.compressions.isEmpty) return 'no_compressions';

      final firstCompressionSec = d.compressions.first.timestampMs / 1000.0;
      final lastCompressionSec = d.compressions.last.timestampMs / 1000.0;

      if (t < firstCompressionSec) return 'before_first_compression';
      if (t > lastCompressionSec + 2.0) return 'after_last_compression';

      return 'active_cpr';
    }

    final sb = StringBuffer();

    sb.writeln('CPR Assist - Raw Rescuer Vitals');
    sb.writeln(',');
    sb.writeln('Session ID,${d.id ?? "local"}');
    sb.writeln('Date & Time,${_fmtDt(d.sessionStart)}');
    sb.writeln('Mode,${d.mode == "emergency" ? "Emergency" : d.mode == "training_no_feedback" ? "Training (No Feedback)" : "Training"}');
    sb.writeln('Scenario,${d.scenario == "pediatric" ? "Pediatric" : "Adult"}');
    if (d.note != null && d.note!.isNotEmpty) {
      sb.writeln('Note,${_esc(d.note!)}');
    }
    sb.writeln(',');

    sb.writeln('SUMMARY');
    sb.writeln('Duration,${_mmss(d.sessionDuration)}');
    sb.writeln('Total Vital Snapshots,$n');

    sb.writeln('Start Heart Rate (BPM),${fmtDouble(startHR, digits: 1)}');
    sb.writeln('End Heart Rate (BPM),${fmtDouble(endHR, digits: 1)}');
    sb.writeln('Heart Rate Change (BPM),${fmtDelta(startHR, endHR, digits: 1)}');

    sb.writeln('Start Rescuer SpO2 (%),${fmtDouble(startSpO2, digits: 1)}');
    sb.writeln('End Rescuer SpO2 (%),${fmtDouble(endSpO2, digits: 1)}');
    sb.writeln('Rescuer SpO2 Change (%),${fmtDelta(startSpO2, endSpO2, digits: 1)}');

    sb.writeln('Start Rescuer Wrist Temp (C),${fmtDouble(startTemp, digits: 2)}');
    sb.writeln('End Rescuer Wrist Temp (C),${fmtDouble(endTemp, digits: 2)}');
    sb.writeln('Rescuer Wrist Temp Change (C),${fmtDelta(startTemp, endTemp, digits: 2)}');

    if (avgHR > 0) sb.writeln('Avg Heart Rate (BPM),${avgHR.toStringAsFixed(1)}');
    if (avgSpO2 > 0) sb.writeln('Avg Rescuer SpO2 (%),${avgSpO2.toStringAsFixed(1)}');
    if (avgTemp > 0) sb.writeln('Avg Rescuer Wrist Temp (C),${avgTemp.toStringAsFixed(2)}');
    if (avgRmssd > 0) sb.writeln('Avg RMSSD (ms),${avgRmssd.toStringAsFixed(1)}');
    if (avgPi > 0) sb.writeln('Avg Perfusion Index (0-100),${avgPi.toStringAsFixed(1)}');
    if (avgFatigue > 0) sb.writeln('Avg Fatigue Score,${avgFatigue.toStringAsFixed(1)}');
    if (maxFatigue > 0) sb.writeln('Max Fatigue Score,$maxFatigue');

    sb.writeln(',');
    sb.writeln('DATA');

    sb.writeln([
      'A/A',
      'Elapsed (ms)',
      'Context',
      'Heart Rate (BPM)',
      'Rescuer SpO2 (%)',
      'Rescuer Wrist Temp (C)',
      'Signal Quality (0-100)',
      'RMSSD (ms)',
      'Perfusion Index (0-100)',
      'Estimated Fatigue Score (0-100)',
    ].join(','));

    for (var i = 0; i < n; i++) {
      final v = d.rescuerVitals[i];

      sb.writeln([
        i + 1,
        v.timestampMs,
        contextForMs(v.timestampMs),
        v.heartRate > 0 ? v.heartRate.toStringAsFixed(1) : '',
        v.spO2 > 0 ? v.spO2.toStringAsFixed(1) : '',
        v.temperature > 0 ? v.temperature.toStringAsFixed(2) : '',
        v.signalQuality,
        v.rmssd > 0 ? v.rmssd : '',
        v.rescuerPi > 0 ? v.rescuerPi : '',
        v.fatigueScore,
      ].join(','));
    }

    return sb.toString();
  }


  // ── Raw Ventilations CSV ─────────────────────────────────────────────────

  static String _buildVentilationsCsv(SessionDetail d) {
    final n = d.ventilations.length;
    final compliantN = d.ventilations.where((v) => v.compliant).length;
    final avgDur = n > 0
        ? d.ventilations.map((v) => v.durationSec).reduce((a, b) => a + b) / n
        : 0.0;
    final compliancePct = n > 0 ? compliantN / n * 100 : 0.0;

    final sb = StringBuffer();

    sb.writeln('CPR Assist - Raw Ventilation Windows');
    sb.writeln(',');
    sb.writeln('Session ID,${d.id ?? "local"}');
    sb.writeln('Date & Time,${_fmtDt(d.sessionStart)}');
    sb.writeln('Mode,${d.mode == "emergency" ? "Emergency" : d.mode == "training_no_feedback" ? "Training (No Feedback)" : "Training"}');
    sb.writeln('Scenario,${d.scenario == "pediatric" ? "Pediatric" : "Standard Adult"}');
    if (d.note != null && d.note!.isNotEmpty) {
      sb.writeln('Note,${_esc(d.note!)}');
    }

    sb.writeln(',');
    sb.writeln('SUMMARY');
    sb.writeln('Duration,${_mmss(d.sessionDuration)}');
    sb.writeln('Total Ventilation Windows,$n');
    sb.writeln('Ventilation Target Met Windows,$compliantN');
    sb.writeln('Ventilation Compliance (%),${compliancePct.toStringAsFixed(1)}');
    sb.writeln('Avg Window Duration (s),${avgDur.toStringAsFixed(2)}');

    sb.writeln(',');
    sb.writeln('DATA');
    sb.writeln([
      'A/A',
      'Elapsed (ms)',
      '30:2 Cycle #',
      'Window Duration (s)',
      'Ventilation Target Met',
    ].join(','));

    for (var i = 0; i < n; i++) {
      final v = d.ventilations[i];

      sb.writeln([
        i + 1,
        v.timestampMs,
        v.cycleNumber,
        v.durationSec.toStringAsFixed(2),
        _yn(v.compliant),
      ].join(','));
    }

    return sb.toString();
  }


  // ── Raw Pulse Checks CSV ─────────────────────────────────────────────────

  static String _buildPulseChecksCsv(SessionDetail d) {
    const classLabels = ['ABSENT', 'UNCERTAIN', 'PRESENT'];

    final n = d.pulseChecks.length;
    final presentN = d.pulseChecks.where((p) => p.classification == 2).length;
    final uncertainN = d.pulseChecks.where((p) => p.classification == 1).length;
    final absentN = d.pulseChecks.where((p) => p.classification == 0).length;

    final sb = StringBuffer();

    sb.writeln('CPR Assist - Raw Pulse Check Results');
    sb.writeln(',');
    sb.writeln('Session ID,${d.id ?? "local"}');
    sb.writeln('Date & Time,${_fmtDt(d.sessionStart)}');
    sb.writeln('Mode,${d.mode == "emergency" ? "Emergency" : d.mode == "training_no_feedback" ? "Training (No Feedback)" : "Training"}');
    sb.writeln('Scenario,${d.scenario == "pediatric" ? "Pediatric" : "Standard Adult"}');
    if (d.note != null && d.note!.isNotEmpty) {
      sb.writeln('Note,${_esc(d.note!)}');
    }

    sb.writeln(',');
    sb.writeln('SUMMARY');
    sb.writeln('Duration,${_mmss(d.sessionDuration)}');
    sb.writeln('Final Result,${d.pulseDetectedFinal ? "ROSC DETECTED" : "NO ROSC"}');
    sb.writeln('Total Pulse Checks,$n');
    sb.writeln('Pulse Present,$presentN');
    sb.writeln('Pulse Uncertain,$uncertainN');
    sb.writeln('Pulse Absent,$absentN');

    sb.writeln(',');
    sb.writeln('DATA');
    sb.writeln([
      'A/A',
      'Elapsed (ms)',
      '2-Min Interval',
      'Pulse Classification',
      'Class Code',
      'Detected BPM',
      'Confidence (0-100)',
      'Perfusion Index (0-100)',
      'Patient SpO2 (%)',
      'Detector A Peaks',
      'Detector B Beats',
      'Rescuer Decision',
      'PPG Samples (#)',
      'PPG Waveform',
    ].join(','));

    for (var i = 0; i < n; i++) {
      final p = d.pulseChecks[i];
      final cls = p.classification.clamp(0, 2);
      final label = classLabels[cls];

      final decision = p.userDecision == 'continue'
          ? 'Continue CPR'
          : p.userDecision == 'stop_cpr'
          ? 'Stop CPR'
          : p.userDecision ?? '';

      sb.writeln([
        i + 1,
        p.timestampMs,
        p.intervalNumber,
        _esc(label),
        cls,
        p.detectedBpm > 0 ? p.detectedBpm.toStringAsFixed(1) : '',
        p.confidence,
        p.perfusionIndex,
        p.patientSpO2 > 0 ? p.patientSpO2.toStringAsFixed(1) : '',
        p.detectorACount,
        p.detectorBCount,
        _esc(decision),
        p.ppgSamples.length,
        _esc(p.ppgSamples.map((s) => s.toStringAsFixed(4)).join(';')),
      ].join(','));
    }

    return sb.toString();
  }


  // ── ZIP builder ────────────────────────────────────────────────────────────

  static Future<Uint8List?> _buildRawDataZip(SessionDetail d) async {
    final archive = Archive();
    var hasAny = false;

    void addCsv(String filename, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(filename, bytes.length, bytes));
      hasAny = true;
    }

    if (d.compressions.isNotEmpty) {
      addCsv('compressions.csv', _buildCompressionsCsv(d));
    }
    if (d.rescuerVitals.isNotEmpty) {
      addCsv('rescuer_vitals.csv', _buildRescuerVitalsCsv(d));
    }
    if (d.ventilations.isNotEmpty) {
      addCsv('ventilations.csv', _buildVentilationsCsv(d));
    }
    if (d.pulseChecks.isNotEmpty) {
      addCsv('pulse_checks.csv', _buildPulseChecksCsv(d));
    }

    // README inside the ZIP
    final modeLabel = d.mode == 'emergency' ? 'Emergency'
        : d.mode == 'training_no_feedback' ? 'Training (No Feedback)' : 'Training';

    final sessionLabel =
        'CPR Assist - Raw Data Export\n'
        '================================================\n'
        'Session ID   : ${d.id ?? "local (not synced)"}\n'
        'Date & Time  : ${_fmtDt(d.sessionStart)}\n'
        'Mode         : $modeLabel\n'
        'Scenario     : ${d.scenario == "pediatric" ? "Pediatric" : "Adult"}\n'
        'Duration     : ${_mmss(d.sessionDuration)} (${d.sessionDuration} s)\n'
        '================================================\n\n'

        'FILES\n'
        '  compressions.csv   - One row per compression with depth, recoil, rate, force, posture, and pause metrics\n'
        '  rescuer_vitals.csv - ${d.rescuerVitals.length} rescuer vital snapshots (HR, SpO2, HRV, temperature, fatigue)\n'
        '  ventilations.csv   - ${d.ventilations.length} ventilation windows\n'
        '  pulse_checks.csv   - ${d.pulseChecks.length} pulse check results\n\n'

        'GENERAL FORMAT\n'
        '  Each CSV file contains three parts:\n\n'
        '  1) HEADER BLOCK\n'
        '     This appears at the top of the file.\n'
        '     It identifies the exported session.\n'
        '     Example fields include Session ID, Date & Time, Mode, Scenario, and Note.\n\n'
        '  2) SUMMARY BLOCK\n'
        '     This starts after the line SUMMARY.\n'
        '     It contains already-calculated session-level metrics.\n'
        '     Use this block for quick reporting without recalculating values manually.\n\n'
        '  3) DATA BLOCK\n'
        '     This starts after the line DATA.\n'
        '     This is the main analysis table.\n'
        '     Use this block for detailed analysis, charts, validation, and statistics.\n\n'
        '  Blank values mean that the value was not available or could not be calculated.\n\n'

        'FORMAT - compressions.csv\n'
        '  compressions.csv uses one row per compression.\n'
        '  Each row contains the peak compression values and the release/recoil values for the same compression.\n'
        '  This means one row can be used to evaluate depth, recoil, rate, force, posture, pauses, and overall quality.\n\n'

        'STRUCTURE - compressions.csv\n'
        '  HEADER BLOCK:\n'
        '    Identifies the session and export context.\n'
        '    Use it to know which session the data belongs to.\n\n'
        '  SUMMARY BLOCK:\n'
        '    Contains session-level compression results.\n'
        '    Examples: duration, total compressions, average depth, average rate, CCF, no-flow time, unplanned pauses, rescuer swaps, fatigue onset, and final outcome when available.\n'
        '    Use it for quick reports and overview statistics.\n\n'
        '  DATA BLOCK:\n'
        '    Contains one row per compression.\n'
        '    Use it for detailed per-compression analysis.\n\n'

        'COLUMN GUIDE - compressions.csv DATA block\n'
        '  A/A                         - Row number in the DATA table\n'
        '  Compression #               - Compression number in the session\n'
        '  Peak Time (ms)              - Time from session start to the deepest point of the compression\n'
        '  Release Time (ms)           - Time from session start to the release/recoil point after the compression\n'
        '  Inter-compression Interval  - Time between this compression peak and the previous compression peak\n'
        '  Unplanned Pause After (ms)  - Long gap after this compression, excluding planned ventilation or pulse-check pauses\n'
        '  Peak Depth (cm)             - Maximum compression depth reached during this compression\n'
        '  Effective Depth (cm)        - Angle-corrected or usable compression depth used for quality analysis\n'
        '  Recoil Depth (cm)           - Remaining depth after release; lower values indicate better chest recoil\n'
        '  Depth Target Met            - YES if peak depth is within the adult or pediatric target range\n'
        '  Downstroke Duration (ms)    - Time from compression start to peak depth\n'
        '  Recoil Duration (ms)        - Time from peak depth to release/recoil\n'
        '  Recoil Target Met           - YES if full or acceptable recoil was detected\n'
        '  Leaning Detected            - YES if the rescuer did not fully release pressure after the compression\n'
        '  Force (N)                   - Peak force applied during the compression, in Newtons\n'
        '  Over Force Detected         - YES if force exceeded the configured safety or quality threshold\n'
        '  Instant Rate (BPM)          - Rate calculated from the current compression interval\n'
        '  Rolling Rate (BPM)          - Smoothed compression rate used for stable feedback\n'
        '  Rate Target Met             - YES if the compression rate is within the target CPR range\n'
        '  Wrist Alignment (deg)       - Wrist or hand alignment deviation from the desired compression posture\n'
        '  Wrist Flexion (deg)         - Wrist flexion or extension angle during compression\n'
        '  Axis Deviation (deg)        - Deviation of compression direction from the ideal vertical axis\n'
        '  Posture Target Met          - YES if wrist alignment, wrist flexion, and compression-axis direction are acceptable\n'
        '  All Targets Met             - YES if depth, rate, recoil, and posture are all correct for this compression\n\n'

        'COLUMN GUIDE - rescuer_vitals.csv DATA block\n'
        '  A/A                       - Row number in the DATA table\n'
        '  Elapsed (ms)              - Time from session start when the snapshot was recorded\n'
        '  Context                   - active_cpr, ventilation, pulse_check, before_first_compression, after_last_compression, or no_compressions\n'
        '  Heart Rate (BPM)          - Rescuer heart rate from the wrist sensor\n'
        '  Rescuer SpO2 (%)          - Rescuer oxygen saturation from the wrist sensor\n'
        '  Rescuer Wrist Temp (C)    - Rescuer wrist temperature\n'
        '  Signal Quality (0-100)    - Sensor signal quality for the snapshot\n'
        '  RMSSD (ms)                - Within-session HRV-related fatigue indicator, not an absolute clinical value\n'
        '  Perfusion Index (0-100)   - Wrist blood-flow/perfusion signal index\n'
        '  Estimated Fatigue Score (0-100)     - Composite fatigue estimate based on rescuer physiological and CPR-performance trends\n\n'

        'COLUMN GUIDE - ventilations.csv DATA block\n'
        '  Elapsed (ms)           - Start time of the ventilation window\n'
        '  30:2 Cycle #           - CPR cycle number associated with the ventilation window\n'
        '  Window Duration (s)    - Length of the ventilation pause/window\n'
        '  Ventilation Target Met - YES if the ventilation window timing was acceptable\n\n'

        'COLUMN GUIDE - pulse_checks.csv DATA block\n'
        '  Elapsed (ms)            - Time when the pulse check was recorded\n'
        '  2-Min Interval          - CPR interval or check number\n'
        '  Pulse Classification    - ABSENT, UNCERTAIN, or PRESENT\n'
        '  Class Code              - 0 = absent, 1 = uncertain, 2 = present\n'
        '  Detected BPM            - Estimated patient pulse or beat rate if detected\n'
        '  Confidence (0-100)      - Confidence score for the pulse classification\n'
        '  Perfusion Index (0-100) - Patient PPG signal/perfusion strength\n'
        '  Patient SpO2 (%)        - Patient oxygen saturation if available\n'
        '  Detector A Peaks        - Raw peak count from the patient PPG signal\n'
        '  Detector B Beats        - Physiologically-gated beat count used for BPM\n'
        '  Rescuer Decision        - User decision after the pulse check\n'
        '  PPG Samples (#)         - Number of waveform samples stored\n'
        '  PPG Waveform            - Normalized 0.0-1.0 waveform, semicolon-delimited\n\n'

        'HOW TO LOCATE THE DATA TABLE IN PYTHON\n'
        '  The CSV files contain descriptive text before the actual DATA table.\n'
        '  Do not read them as normal CSV files from the first line.\n'
        '  First find the line that says DATA, then read the next line as the table header.\n\n'
        '  Python:\n'
        '    import pandas as pd\n'
        '    from pathlib import Path\n\n'
        '    path = Path("compressions.csv")\n'
        '    lines = path.read_text(encoding="utf-8").splitlines()\n\n'
        '    data_line_index = lines.index("DATA")\n'
        '    header_line_index = data_line_index + 1\n\n'
        '    df = pd.read_csv(path, skiprows=header_line_index)\n\n'
        '  After this, df contains only the compression DATA table.\n'
        '  Each row in df is one compression.\n'
        '  The header block and SUMMARY block are intentionally skipped.\n\n'

        'IMPORTANT NOTES\n'
        '  These exports are intended for CPR performance review, training analysis, and research validation.\n'
        '  Sensor-derived physiological values should not be treated as standalone clinical diagnoses.\n'
        '  Patient pulse and SpO2 values depend on signal quality and should be interpreted together with confidence and perfusion index.\n';


    final readmeBytes = utf8.encode(sessionLabel);
    archive.addFile(ArchiveFile('README.txt', readmeBytes.length, readmeBytes));

    if (!hasAny) return null;

    final zipBytes = ZipEncoder().encode(archive);
    return zipBytes != null ? Uint8List.fromList(zipBytes) : null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — SINGLE SESSION
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildSingleSessionPdf(
      SessionDetail s, { String? username }) async {

    final doc          = pw.Document();
    final roboto       = await PdfGoogleFonts.robotoRegular();
    final robotoBold   = await PdfGoogleFonts.robotoBold();
    final robotoMedium = await PdfGoogleFonts.robotoMedium();
    final noto         = await PdfGoogleFonts.notoSansRegular();
    final theme        = pw.ThemeData.withFont(
        base: roboto, bold: robotoBold, fontFallback: [noto]);

    final isTraining  = s.isTraining;
    final isPediatric = s.scenario == 'pediatric';
    final depthMin    = isPediatric ? CprTargets.depthMinPediatric : CprTargets.depthMin;
    final depthMax    = isPediatric ? CprTargets.depthMaxPediatric : CprTargets.depthMax;
    final n           = s.compressionCount > 0 ? s.compressionCount.toDouble() : 1.0;

    // Derived biometric values
    final patSpO2 = s.patientSpO2LastCheck;
    final hasBio  = s.rescuerHRLastPause != null ||
        s.rescuerSpO2LastPause != null ||
        s.patientTemperature != null ||
        patSpO2 != null ||
        s.rescuerWristTempStart != null ||
        s.rescuerWristTempEnd != null;

    final hasForceData  = s.compressions.any((c) => c.force > 0);
    final hasPostureData = s.compressions.any(
            (c) => c.wristAlignmentAngle > 0 || c.wristFlexionAngle.abs() > 0);
    final hasVitals = s.rescuerVitals.isNotEmpty;

    // Average force
    final avgForce = s.compressions.isEmpty ? 0.0
        : s.compressions.map((c) => c.force).reduce((a, b) => a + b) /
        s.compressions.length;

    doc.addPage(pw.MultiPage(
      theme:      theme,
      pageFormat: PdfPageFormat.a4,
      margin:     const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      header: (ctx) => _pageHeader(
        robotoBold, robotoMedium,
        title:    isTraining ? 'Training Session Report' : 'Emergency Session Record',
        subtitle: s.dateTimeFormatted,
        username: username,
        sessionId: s.id?.toString(),
        mode:    isTraining ? 'TRAINING' : 'EMERGENCY',
        modeColor: isTraining ? _kWarning : _kEmgGreen,
        modeBg:    isTraining ? _kWarningLight : _kEmgGreenBg,
        scenarioBadge: isPediatric ? 'PEDIATRIC' : 'ADULT',
        scenarioColor: isPediatric ? _kPediatric : _kBrandBlue,
        scenarioBg:    isPediatric ? _kPediatricBg : _kBrandLight,
      ),
      footer: (ctx) => _pageFooter(roboto, ctx),
      build: (ctx) => [

        // ── Grade hero (training only) ─────────────────────────────────────
        if (isTraining) ...[
          _gradeHero(robotoBold, robotoMedium, s.totalGrade, s.scenario),
          pw.SizedBox(height: 16),
        ],

        // ── Emergency outcome hero ─────────────────────────────────────────
        if (!isTraining) ...[
          _emergencyOutcomeHero(robotoBold, robotoMedium, s),
          pw.SizedBox(height: 16),
        ],

        // ── 5-tile summary strip ───────────────────────────────────────────
        _summaryStrip(robotoBold, robotoMedium, [
          _Cell('Duration',       s.durationFormatted),
          _Cell('Compressions',   '${s.compressionCount}'),
          _Cell('Avg Rate',       s.averageFrequency > 0
              ? '${s.averageFrequency.round()} BPM' : '—'),
          _Cell('Avg Depth',      s.averageDepth > 0
              ? '${s.averageDepth.toStringAsFixed(1)} cm' : '—'),
          _Cell('CCF',            '${(s.handsOnRatio * 100).round()}%'),
        ]),
        pw.SizedBox(height: 20),

        // ── Quality breakdown grid (training only) ─────────────────────────
        if (isTraining) ...[
          _sectionTitle(robotoBold, 'Quality Breakdown'),
          pw.SizedBox(height: 10),
          _qualityGrid(robotoBold, robotoMedium, roboto, s, n),
          pw.SizedBox(height: 20),
        ],

        // ── Two-column metrics panel ───────────────────────────────────────
        _sectionTitle(robotoBold, 'Session Metrics'),
        pw.SizedBox(height: 8),
        _twoColumnMetrics(robotoMedium, roboto, s, depthMin, depthMax),
        pw.SizedBox(height: 20),

        // ── Depth chart ────────────────────────────────────────────────────
        if (s.compressions.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Compression Depth Over Time'),
          pw.SizedBox(height: 8),
          _chartCard(
            child: pw.SizedBox(
              height: 100,
              child: pw.CustomPaint(painter: (canvas, size) =>
                  _paintDepthChart(canvas, size, s.compressions, depthMin, depthMax)),
            ),
            legendItems: [
              _LegendItem('Depth (cm)', _kBrandBlue),
              _LegendItem('Target ${depthMin.toStringAsFixed(0)}-${depthMax.toStringAsFixed(0)} cm', _kSuccess),
            ],
            font: roboto,
          ),
          pw.SizedBox(height: 14),
        ],

        // ── Rate chart ─────────────────────────────────────────────────────
        if (s.compressions.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Compression Rate Over Time'),
          pw.SizedBox(height: 8),
          _chartCard(
            child: pw.SizedBox(
              height: 100,
              child: pw.CustomPaint(painter: (canvas, size) =>
                  _paintRateChart(canvas, size, s.compressions)),
            ),
            legendItems: [
              _LegendItem('Rate (BPM)', _kBrandMid),
              _LegendItem('Target 100-120 BPM', _kSuccess),
            ],
            font: roboto,
          ),
          pw.SizedBox(height: 14),
        ],

        // ── Force chart ────────────────────────────────────────────────────
        if (hasForceData) ...[
          _sectionTitle(robotoBold, 'Compression Force Over Time'),
          pw.SizedBox(height: 8),
          _chartCard(
            child: pw.SizedBox(
              height: 90,
              child: pw.CustomPaint(painter: (canvas, size) =>
                  _paintForceChart(canvas, size, s.compressions, avgForce)),
            ),
            legendItems: [
              _LegendItem('Force (N)', _kBrandMid),
              _LegendItem('600 N danger threshold', _kError),
              _LegendItem('Average ${avgForce.toStringAsFixed(0)} N', _kTextDisabled),
            ],
            font: roboto,
          ),
          pw.SizedBox(height: 14),
        ],

        // ── Posture chart ──────────────────────────────────────────────────
        if (hasPostureData) ...[
          _sectionTitle(robotoBold, 'Wrist Posture Over Time'),
          pw.SizedBox(height: 8),
          _chartCard(
            child: pw.SizedBox(
              height: 90,
              child: pw.CustomPaint(painter: (canvas, size) =>
                  _paintPostureChart(canvas, size, s.compressions)),
            ),
            legendItems: [
              _LegendItem('Wrist alignment (°)', _kBrandBlue),
              _LegendItem('Wrist flexion (°)', _kBrandMid),
              _LegendItem('15° / 10° targets', _kSuccess),
            ],
            font: roboto,
          ),
          pw.SizedBox(height: 20),
        ],

        // ── Rescuer vitals chart ───────────────────────────────────────────
        if (hasVitals) ...[
          _sectionTitle(robotoBold, 'Rescuer Vitals Over Time'),
          pw.SizedBox(height: 8),
          _chartCard(
            child: pw.SizedBox(
              height: 90,
              child: pw.CustomPaint(painter: (canvas, size) =>
                  _paintVitalsChart(canvas, size, s.rescuerVitals)),
            ),
            legendItems: [
              _LegendItem('Heart Rate (BPM)', _kError),
              _LegendItem('Estimated Fatigue Score (0-100)', _kWarning),
            ],
            font: roboto,
          ),
          pw.SizedBox(height: 20),
        ],

        // ── Ventilation cycles table ───────────────────────────────────────
        if (s.ventilations.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Ventilation Windows'),
          pw.SizedBox(height: 8),
          _ventilationTable(robotoBold, robotoMedium, roboto, s.ventilations),
          pw.SizedBox(height: 20),
        ],

        // ── Pulse check table (emergency only) ────────────────────────────
        if (s.pulseChecks.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Pulse Check Results'),
          pw.SizedBox(height: 8),
          _pulseCheckTable(robotoBold, robotoMedium, roboto, s.pulseChecks),
          pw.SizedBox(height: 20),
        ],

        // ── Biometrics ─────────────────────────────────────────────────────
        if (hasBio) ...[
          _sectionTitle(robotoBold, 'Biometrics & Environment'),
          pw.SizedBox(height: 8),
          _biometricsPanel(robotoBold, robotoMedium, roboto, s, patSpO2),
          pw.SizedBox(height: 20),
        ],

        // ── Session note ───────────────────────────────────────────────────
        if (s.note != null && s.note!.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Session Note'),
          pw.SizedBox(height: 8),
          pw.Container(
            width:   double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color:        _kBgGrey,
              borderRadius: pw.BorderRadius.circular(8),
              border:       pw.Border.all(color: _kDivider, width: 0.5),
            ),
            child: pw.Text(s.note!,
                style: pw.TextStyle(font: roboto, fontSize: 10, color: _kTextPrimary)),
          ),
        ],
      ],
    ));

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — MULTI SESSION
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildMultiSessionPdf(
      List<SessionSummary> sessions, { String? username }) async {

    final doc          = pw.Document();
    final roboto       = await PdfGoogleFonts.robotoRegular();
    final robotoBold   = await PdfGoogleFonts.robotoBold();
    final robotoMedium = await PdfGoogleFonts.robotoMedium();
    final noto         = await PdfGoogleFonts.notoSansRegular();
    final theme        = pw.ThemeData.withFont(
        base: roboto, bold: robotoBold, fontFallback: [noto]);

    final trainingSessions  = sessions.where((s) => s.isTraining && s.totalGrade > 0).toList();
    final emergencySessions = sessions.where((s) => s.isEmergency).toList();
    final totalCompressions = sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);
    final adultSessions     = sessions.where((s) => s.scenario != 'pediatric').length;
    final pediatricSessions = sessions.length - adultSessions;

    final avgGrade  = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a + b) / trainingSessions.length;
    final bestGrade = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);
    final worstGrade = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a < b ? a : b);

    // Trend delta: first graded session vs last graded session
    final trendDelta = trainingSessions.length >= 2
        ? trainingSessions.last.totalGrade - trainingSessions.first.totalGrade
        : 0.0;

    // Average CCF across training sessions
    final avgCCF = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.handsOnRatio).reduce((a, b) => a + b) / trainingSessions.length;

    // Emergency ROSC rate
    final roscCount = emergencySessions.where((s) => s.pulseDetectedFinal).length;

    // Date range label
    final sortedByDate = [...sessions]
      ..sort((a, b) => (a.sessionStart ?? DateTime(2000))
          .compareTo(b.sessionStart ?? DateTime(2000)));
    final dateRange = sortedByDate.isEmpty ? ''
        : '${sortedByDate.first.dateFormatted} - ${sortedByDate.last.dateFormatted}';

    doc.addPage(pw.MultiPage(
      theme:      theme,
      pageFormat: PdfPageFormat.a4,
      margin:     const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      header: (ctx) => _pageHeader(
        robotoBold, robotoMedium,
        title:    'CPR Training History Report',
        subtitle: '$dateRange  ·  ${sessions.length} sessions',
        username: username,
      ),
      footer: (ctx) => _pageFooter(roboto, ctx),
      build: (ctx) => [

        // ── Overview strip ─────────────────────────────────────────────────
        _summaryStrip(robotoBold, robotoMedium, [
          _Cell('Sessions',     '${sessions.length}'),
          _Cell('Training',     '${trainingSessions.length}'),
          _Cell('Emergency',    '${emergencySessions.length}'),
          _Cell('Compressions', totalCompressions > 999
              ? '${(totalCompressions / 1000).toStringAsFixed(1)}k'
              : '$totalCompressions'),
          _Cell('Avg CCF',      '${(avgCCF * 100).round()}%'),
        ]),
        pw.SizedBox(height: 20),

        // ── Scenario breakdown ─────────────────────────────────────────────
        if (pediatricSessions > 0) ...[
          pw.Row(children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                  color: _kBrandLight, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text('Adult: $adultSessions sessions',
                  style: pw.TextStyle(font: robotoMedium, fontSize: 9, color: _kBrandBlue)),
            ),
            pw.SizedBox(width: 8),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                  color: _kPediatricBg, borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Text('Pediatric: $pediatricSessions sessions',
                  style: pw.TextStyle(font: robotoMedium, fontSize: 9, color: _kPediatric)),
            ),
          ]),
          pw.SizedBox(height: 14),
        ],

        // ── Training progress ──────────────────────────────────────────────
        if (trainingSessions.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Training Performance'),
          pw.SizedBox(height: 10),

          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Stats panel
              pw.SizedBox(
                width: 140,
                child: _statPanel(robotoBold, robotoMedium, [
                  _Cell('Average Grade',  '${avgGrade.toStringAsFixed(1)}%'),
                  _Cell('Best Grade',     '${bestGrade.toStringAsFixed(1)}%'),
                  _Cell('Worst Grade',    '${worstGrade.toStringAsFixed(1)}%'),
                  _Cell('Sessions Graded', '${trainingSessions.length}'),
                  if (trendDelta != 0) _Cell('Trend',
                      '${trendDelta >= 0 ? '+' : ''}${trendDelta.toStringAsFixed(1)}%'),
                ]),
              ),
              pw.SizedBox(width: 12),
              // Grade trend chart
              pw.Expanded(
                child: _gradeSparklinePanel(roboto, robotoMedium, robotoBold,
                    trainingSessions, trendDelta),
              ),
            ],
          ),
          pw.SizedBox(height: 20),

          // ── Average metrics grid ─────────────────────────────────────────
          _sectionTitle(robotoBold, 'Average Metrics Across Training Sessions'),
          pw.SizedBox(height: 10),
          _avgMetricsGrid(robotoBold, robotoMedium, roboto, trainingSessions),
          pw.SizedBox(height: 20),

          // ── 2×2 metric trend charts ──────────────────────────────────────
          if (trainingSessions.length >= 2) ...[
            _sectionTitle(robotoBold, 'Metric Trends'),
            pw.SizedBox(height: 10),
            _metricTrendGrid(roboto, robotoMedium, robotoBold, trainingSessions),
            pw.SizedBox(height: 20),
          ],
        ],

        // ── Emergency summary ──────────────────────────────────────────────
        if (emergencySessions.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Emergency Sessions'),
          pw.SizedBox(height: 8),
          _emergencySessionsSummary(robotoBold, robotoMedium, roboto,
              emergencySessions, roscCount),
          pw.SizedBox(height: 20),
        ],

        // ── All sessions table ─────────────────────────────────────────────
        _sectionTitle(robotoBold, 'All Sessions'),
        pw.SizedBox(height: 8),
        _sessionTable(robotoBold, robotoMedium, roboto, sessions),
      ],
    ));

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — CERTIFICATE (unchanged from original)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildCertificatePdf({
    required String username,
    required CertificateMilestone milestone,
  }) async {
    final doc          = pw.Document();
    final roboto       = await PdfGoogleFonts.robotoRegular();
    final robotoBold   = await PdfGoogleFonts.robotoBold();
    final robotoMedium = await PdfGoogleFonts.robotoMedium();
    final noto         = await PdfGoogleFonts.notoSansRegular();
    final theme        = pw.ThemeData.withFont(
        base: roboto, bold: robotoBold, fontFallback: [noto]);

    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December',
    ];
    final dateStr = milestone.earnedDate != null
        ? '${milestone.earnedDate!.day} '
        '${months[milestone.earnedDate!.month - 1]} '
        '${milestone.earnedDate!.year}'
        : _dateStampFull();

    doc.addPage(pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Stack(children: [
        pw.Container(decoration: pw.BoxDecoration(
          border:       pw.Border.all(color: _kBrandBlue, width: 3),
          borderRadius: pw.BorderRadius.circular(8),
        )),
        pw.Positioned(left: 8, right: 8, top: 8, bottom: 8,
          child: pw.Container(decoration: pw.BoxDecoration(
            border:       pw.Border.all(color: _kBrandBlue.shade(0.35), width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          )),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 36),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CPR Assist', style: pw.TextStyle(
                      font: robotoBold, fontSize: 13, color: _kBrandBlue)),
                  pw.Text('AUTH Biomedical Engineering · Prof. P. Bamidis',
                      style: pw.TextStyle(font: roboto, fontSize: 9, color: _kTextDisabled)),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Container(height: 1, color: _kBrandBlue.shade(0.3)),
              pw.SizedBox(height: 24),
              pw.Text('Certificate of Achievement', style: pw.TextStyle(
                  font: roboto, fontSize: 13, color: _kTextSecond, letterSpacing: 3),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 8),
              pw.Text(milestone.title, style: pw.TextStyle(
                  font: robotoBold, fontSize: 32, color: _kBrandBlue),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 24),
              pw.Text('This certifies that', style: pw.TextStyle(
                  font: roboto, fontSize: 12, color: _kTextSecond)),
              pw.SizedBox(height: 8),
              pw.Text(username, style: pw.TextStyle(
                  font: robotoBold, fontSize: 22, color: _kTextPrimary)),
              pw.SizedBox(height: 8),
              pw.Text('has successfully completed the requirement:',
                  style: pw.TextStyle(font: roboto, fontSize: 11, color: _kTextSecond)),
              pw.SizedBox(height: 4),
              pw.Text(milestone.subtitle, style: pw.TextStyle(
                  font: robotoMedium, fontSize: 13, color: _kTextPrimary),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 24),
              pw.Container(height: 1, color: _kDivider),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('Date', style: pw.TextStyle(
                        font: roboto, fontSize: 9, color: _kTextDisabled)),
                    pw.SizedBox(height: 2),
                    pw.Text(dateStr, style: pw.TextStyle(
                        font: robotoBold, fontSize: 11, color: _kTextPrimary)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                    pw.Text('CPR Assist Training System', style: pw.TextStyle(
                        font: robotoBold, fontSize: 10, color: _kBrandBlue)),
                    pw.SizedBox(height: 2),
                    pw.Text('Aristotle University of Thessaloniki',
                        style: pw.TextStyle(font: roboto, fontSize: 9, color: _kTextDisabled)),
                  ]),
                  pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text('Research Ethics Approval', style: pw.TextStyle(
                        font: roboto, fontSize: 9, color: _kTextDisabled)),
                    pw.SizedBox(height: 2),
                    pw.Text('ΕΗΔΕ — AUTH', style: pw.TextStyle(
                        font: robotoBold, fontSize: 11, color: _kTextPrimary)),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ]),
    ));

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF BUILDING BLOCKS
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Page header ────────────────────────────────────────────────────────────

  static pw.Widget _pageHeader(
      pw.Font bold, pw.Font medium, {
        required String title,
        required String subtitle,
        String?   username,
        String?   sessionId,
        String?   mode,
        PdfColor? modeColor,
        PdfColor? modeBg,
        String?   scenarioBadge,
        PdfColor? scenarioColor,
        PdfColor? scenarioBg,
      }) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _kDivider, width: 1))),
      padding: const pw.EdgeInsets.only(bottom: 12),
      margin:  const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(children: [
                  pw.Container(width: 4, height: 20,
                      decoration: pw.BoxDecoration(
                          color: _kBrandBlue, borderRadius: pw.BorderRadius.circular(2))),
                  pw.SizedBox(width: 8),
                  pw.Text(title, style: pw.TextStyle(
                      font: bold, fontSize: 15, color: _kTextPrimary)),
                  if (mode != null) ...[
                    pw.SizedBox(width: 10),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: pw.BoxDecoration(
                          color: modeBg ?? _kBrandLight,
                          borderRadius: pw.BorderRadius.circular(999),
                          border: pw.Border.all(color: modeColor ?? _kBrandBlue, width: 0.8)),
                      child: pw.Text(mode, style: pw.TextStyle(
                          font: bold, fontSize: 8, color: modeColor ?? _kBrandBlue)),
                    ),
                  ],
                  if (scenarioBadge != null) ...[
                    pw.SizedBox(width: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: pw.BoxDecoration(
                          color: scenarioBg ?? _kBrandLight,
                          borderRadius: pw.BorderRadius.circular(999),
                          border: pw.Border.all(color: scenarioColor ?? _kBrandBlue, width: 0.8)),
                      child: pw.Text(scenarioBadge, style: pw.TextStyle(
                          font: bold, fontSize: 8, color: scenarioColor ?? _kBrandBlue)),
                    ),
                  ],
                ]),
                pw.SizedBox(height: 3),
                pw.Text(subtitle, style: pw.TextStyle(
                    font: medium, fontSize: 9, color: _kTextSecond)),
              ],
            ),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('CPR Assist',
                style: pw.TextStyle(font: bold, fontSize: 11, color: _kBrandBlue)),
            if (username != null)
              pw.Text(username, style: pw.TextStyle(
                  font: medium, fontSize: 9, color: _kTextDisabled)),
            if (sessionId != null)
              pw.Text('ID: $sessionId', style: pw.TextStyle(
                  font: medium, fontSize: 8, color: _kTextDisabled)),
          ]),
        ],
      ),
    );
  }

  // ── Page footer ────────────────────────────────────────────────────────────

  static pw.Widget _pageFooter(pw.Font font, pw.Context ctx) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _kDivider, width: 1))),
      padding: const pw.EdgeInsets.only(top: 8),
      margin:  const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by CPR Assist  ·  AUTH BME Thesis  ·  Prof. P. Bamidis',
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
        ],
      ),
    );
  }

  // ── Grade hero (training) ──────────────────────────────────────────────────

  static pw.Widget _gradeHero(
      pw.Font bold, pw.Font medium, double grade, String scenario) {
    final color = _gradeColor(grade);
    final label = grade >= 90 ? 'Excellent!'
        : grade >= 75 ? 'Good job!'
        : grade >= 55 ? 'Keep it up!'
        : 'Keep practicing!';
    final fillFlex  = (grade.clamp(0.0, 100.0)).round().clamp(1, 99);
    final emptyFlex = (100 - fillFlex).clamp(1, 99);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
            colors: [_kBrandBlue, _kBrandDark],
            begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(children: [
        pw.Container(
          width: 90, height: 90,
          decoration: pw.BoxDecoration(
              shape:  pw.BoxShape.circle,
              color:  _kWhite.shade(0.12),
              border: pw.Border.all(color: _kWhite.shade(0.3), width: 2)),
          child: pw.Center(
            child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
              pw.Text('${grade.toStringAsFixed(0)}%',
                  style: pw.TextStyle(font: bold, fontSize: 24, color: _kWhite)),
              pw.Text(label,
                  style: pw.TextStyle(font: medium, fontSize: 8, color: _kWhite.shade(0.8))),
            ]),
          ),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Overall Grade',
                  style: pw.TextStyle(font: medium, fontSize: 9, color: _kWhite.shade(0.7))),
              pw.Text('${grade.toStringAsFixed(1)}%',
                  style: pw.TextStyle(font: bold, fontSize: 9, color: _kWhite)),
            ]),
            pw.SizedBox(height: 6),
            pw.Stack(children: [
              pw.Container(height: 7, decoration: pw.BoxDecoration(
                  color: _kWhite.shade(0.2), borderRadius: pw.BorderRadius.circular(4))),
              pw.Row(children: [
                pw.Expanded(flex: fillFlex, child: pw.Container(
                    height: 7,
                    decoration: pw.BoxDecoration(
                        color: color, borderRadius: pw.BorderRadius.circular(4)))),
                pw.Expanded(flex: emptyFlex, child: pw.SizedBox(height: 7)),
              ]),
            ]),
            pw.SizedBox(height: 8),
            // Grade scale labels
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('0%', style: pw.TextStyle(font: medium, fontSize: 8, color: _kWhite.shade(0.5))),
              pw.Text('55%', style: pw.TextStyle(font: medium, fontSize: 8, color: _kWhite.shade(0.5))),
              pw.Text('75%', style: pw.TextStyle(font: medium, fontSize: 8, color: _kWhite.shade(0.5))),
              pw.Text('90%', style: pw.TextStyle(font: medium, fontSize: 8, color: _kWhite.shade(0.5))),
              pw.Text('100%', style: pw.TextStyle(font: medium, fontSize: 8, color: _kWhite.shade(0.5))),
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── Emergency outcome hero ─────────────────────────────────────────────────

  static pw.Widget _emergencyOutcomeHero(
      pw.Font bold, pw.Font medium, SessionDetail s) {
    final rosc       = s.pulseDetectedFinal;
    final hadChecks  = s.pulseChecks.isNotEmpty;
    final outcomeText = rosc ? 'ROSC DETECTED'
        : hadChecks ? 'NO ROSC'
        : 'NO PULSE DATA';
    final headerBg = rosc ? _kEmgGreen : _kBrandDark;

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
          color:        headerBg,
          borderRadius: pw.BorderRadius.circular(12)),
      child: pw.Row(children: [
        pw.Container(
          width: 120,
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Text(outcomeText, style: pw.TextStyle(
                font: bold, fontSize: 13, color: _kWhite),
                textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 4),
            pw.Text('Emergency Outcome', style: pw.TextStyle(
                font: medium, fontSize: 8, color: _kWhite.shade(0.7)),
                textAlign: pw.TextAlign.center),
          ]),
        ),
        pw.Container(width: 1, height: 60, color: _kWhite.shade(0.2)),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _miniStat(bold, medium, '${s.compressionCount}', 'Compressions'),
              _miniStat(bold, medium, '${s.pulseChecksPrompted}', 'Pulse Checks'),
              _miniStat(bold, medium, s.durationFormatted, 'Duration'),
              if (s.patientTemperature != null)
                _miniStat(bold, medium,
                    '${s.patientTemperature!.toStringAsFixed(1)}  C', 'Patient Temp'),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
      ]),
    );
  }

  static pw.Widget _miniStat(pw.Font bold, pw.Font medium, String value, String label) =>
      pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 16, color: _kWhite)),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(font: medium, fontSize: 7, color: _kWhite.shade(0.65)),
            textAlign: pw.TextAlign.center),
      ]);

  // ── Summary strip ──────────────────────────────────────────────────────────

  static pw.Widget _summaryStrip(
      pw.Font bold, pw.Font medium, List<_Cell> cells) {
    return pw.Container(
      decoration: pw.BoxDecoration(
          color: _kBrandDark, borderRadius: pw.BorderRadius.circular(10)),
      child: pw.Row(
        children: cells.map((c) {
          final isLast = cells.last == c;
          return pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: pw.BoxDecoration(
                  border: isLast ? null : const pw.Border(
                      right: pw.BorderSide(color: _kWhite, width: 0.15))),
              child: pw.Column(children: [
                pw.Text(c.value, style: pw.TextStyle(
                    font: bold, fontSize: 18, color: _kWhite),
                    textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 3),
                pw.Text(c.label, style: pw.TextStyle(
                    font: medium, fontSize: 8, color: _kWhite.shade(0.6)),
                    textAlign: pw.TextAlign.center),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Quality breakdown grid ─────────────────────────────────────────────────

  static pw.Widget _qualityGrid(
      pw.Font bold, pw.Font medium, pw.Font font,
      SessionDetail s, double n) {
    final metrics = [
      _Metric('Depth Consistency',
          '${(s.correctDepth / n * 100).round()}%',
          _gradeColorForPct(s.correctDepth / n)),
      _Metric('Rate Consistency',
          '${(s.correctFrequency / n * 100).round()}%',
          _gradeColorForPct(s.correctFrequency / n)),
      _Metric('Full Recoil',
          '${(s.correctRecoil / n * 100).round()}%',
          _gradeColorForPct(s.correctRecoil / n)),
      _Metric('Depth + Rate',
          '${(s.depthRateCombo / n * 100).round()}%',
          _gradeColorForPct(s.depthRateCombo / n)),
      _Metric('Correct Posture',
          '${(s.correctPosture / n * 100).round()}%',
          _gradeColorForPct(s.correctPosture / n)),
      _Metric('Ventilation',
          s.ventilationCount > 0
              ? '${s.ventilationCompliance.round()}%' : 'N/A',
          s.ventilationCount > 0
              ? _gradeColorForPct(s.ventilationCompliance / 100)
              : _kTextDisabled),
    ];
    return _metricTileGrid(bold, font, metrics);
  }

  // ── Two-column metrics table ───────────────────────────────────────────────
  // Left: Depth | Right: Rate, timing, safety

  static pw.Widget _twoColumnMetrics(
      pw.Font medium, pw.Font font,
      SessionDetail s, double depthMin, double depthMax) {

    final leftRows = <_Row>[
      if (s.averageDepth > 0)
        _Row('Average Depth', '${s.averageDepth.toStringAsFixed(1)} cm',
            note: 'Target: ${depthMin.toStringAsFixed(0)}-${depthMax.toStringAsFixed(0)} cm'),
      if (s.averageEffectiveDepth > 0)
        _Row('Effective Depth (angle-corrected)', '${s.averageEffectiveDepth.toStringAsFixed(1)} cm'),
      if (s.peakDepth > 0)
        _Row('Peak Depth', '${s.peakDepth.toStringAsFixed(1)} cm'),
      if (s.depthSD > 0)
        _Row('Depth SD', '${s.depthSD.toStringAsFixed(2)} cm', note: 'Lower = more consistent'),
      if (s.depthConsistency > 0)
        _Row('Depth Consistency', '${s.depthConsistency.toStringAsFixed(0)}%'),
      if (s.tooDeepCount > 0)
        _Row('Too Deep (>${depthMax.toStringAsFixed(0)} cm)', '${s.tooDeepCount}×', isAlert: true),
      if (s.overForceCount > 0)
        _Row('Over-Force Events', '${s.overForceCount}×', isAlert: true),
      if (s.leaningCount > 0)
        _Row('Leaning Detected', '${s.leaningCount}×', isAlert: true),
    ];

    final rightRows = <_Row>[
      if (s.averageFrequency > 0)
        _Row('Average Rate', '${s.averageFrequency.round()} BPM', note: 'Target: 100-120 BPM'),
      if (s.frequencyConsistency > 0)
        _Row('Rate Consistency', '${s.frequencyConsistency.toStringAsFixed(0)}%'),
      if (s.rateVariability > 0)
        _Row('Rate Variability (SD)', '${s.rateVariability.toStringAsFixed(0)} ms',
            note: 'Inter-compression interval SD'),
      _Row('CCF (Hands-On Time)', '${(s.handsOnRatio * 100).round()}%', note: 'Target ≥ 80%'),
      if (s.noFlowTime > 0)
        _Row('No-Flow Time', '${s.noFlowTime.toStringAsFixed(1)} s',
            note: '${s.noFlowIntervals} gap(s) > 2 s'),
      if (s.unplannedPauseCount > 0 || s.unplannedPauseTime > 0)
        _Row(
          'Unplanned Pauses',
          '${s.unplannedPauseCount}',
          note: '${s.unplannedPauseTime.toStringAsFixed(1)} s not explained by ventilation/pulse checks',
          isAlert: s.unplannedPauseCount > 0,
        ),
      if (s.timeToFirstCompression > 0)
        _Row('Time to First Compression', '${s.timeToFirstCompression.toStringAsFixed(1)} s'),
      if (s.consecutiveGoodPeak > 0)
        _Row('Best Streak', '${s.consecutiveGoodPeak} perfect compressions'),
      if (s.fatigueOnsetIndex > 0)
        _Row('Fatigue Onset', 'Compression #${s.fatigueOnsetIndex}', isAlert: true),
      if (s.rescuerSwapCount > 0)
        _Row('Rescuer Swaps', '${s.rescuerSwapCount}'),
      if (s.ventilationCount > 0) ...[
        _Row('Ventilation Windows', '${s.ventilationCount}'),
        _Row('Ventilation Compliance', '${s.ventilationCompliance.round()}%'),
        if (s.correctVentilations > 0)
          _Row('Compliant Ventilations', '${s.correctVentilations}/${s.ventilationCount}'),
      ],
    ];

    // Render two side-by-side detail tables
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _miniDetailTable(medium, font, 'DEPTH & FORCE', leftRows)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: _miniDetailTable(medium, font, 'RATE & TIMING', rightRows)),
      ],
    );
  }

  static pw.Widget _miniDetailTable(
      pw.Font medium, pw.Font font, String header, List<_Row> rows) {
    if (rows.isEmpty) return pw.SizedBox.shrink();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: pw.BoxDecoration(
              color: _kBrandLight, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text(header, style: pw.TextStyle(
              font: medium, fontSize: 8, color: _kBrandBlue)),
        ),
        pw.Table(
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(1.4),
          },
          children: rows.asMap().entries.map((e) {
            final isAlt = e.key.isOdd;
            final r     = e.value;
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                  color: isAlt ? _kBgGrey : _kWhite),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(r.label, style: pw.TextStyle(
                          font: medium, fontSize: 8,
                          color: r.isAlert ? _kError : _kTextPrimary)),
                      if (r.note != null)
                        pw.Text(r.note!, style: pw.TextStyle(
                            font: font, fontSize: 7, color: _kTextDisabled)),
                    ],
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text(r.value,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: medium, fontSize: 9,
                          color: r.isAlert ? _kError : _kTextPrimary)),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Ventilation table ──────────────────────────────────────────────────────

  static pw.Widget _ventilationTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<VentilationEvent> ventilations) {
    return pw.Table(
      border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5)),
      columnWidths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FixedColumnWidth(60),  // was index 3 — Duration
        3: const pw.FixedColumnWidth(52),  // was index 4 — Compliant
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kBrandDark),
          children: [
            _tableCell(bold, 'Cycle', isHeader: true, isDark: true),
            _tableCell(bold, 'At (elapsed)', isHeader: true, isDark: true),
            _tableCell(bold, 'Duration', isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Compliant', isHeader: true, isDark: true, align: pw.TextAlign.center),
          ],
        ),
        ...ventilations.asMap().entries.map((e) {
          final i   = e.key;
          final v   = e.value;
          final alt = i.isOdd;
          final elapsedSec = v.timestampMs / 1000;
          final m   = (elapsedSec ~/ 60).toString();
          final s   = (elapsedSec % 60).toStringAsFixed(0).padLeft(2, '0');
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: alt ? _kBgGrey : _kWhite),
            children: [
              _tableCell(font, '${v.cycleNumber}', color: _kTextSecond),
              _tableCell(font, '$m:$s'),
              _tableCell(font, '${v.durationSec.toStringAsFixed(1)} s', align: pw.TextAlign.right),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: pw.Center(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: pw.BoxDecoration(
                        color: v.compliant ? _kSuccessLight : _kErrorLight,
                        borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text(v.compliant ? '✓' : '✗',
                        style: pw.TextStyle(font: bold, fontSize: 8,
                            color: v.compliant ? _kSuccess : _kError)),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ── Pulse check table ──────────────────────────────────────────────────────

  static pw.Widget _pulseCheckTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<PulseCheckEvent> checks) {
    const classLabels = ['ABSENT', 'UNCERTAIN', 'PRESENT'];
    const classColors = [_kError, _kWarning, _kSuccess];
    const classBgs    = [_kErrorLight, _kWarningLight, _kSuccessLight];

    return pw.Column(children: [
      pw.Table(
        border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5)),
        columnWidths: {
          0: const pw.FixedColumnWidth(24),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(2),
          3: const pw.FlexColumnWidth(1.2),
          4: const pw.FlexColumnWidth(1),
          5: const pw.FlexColumnWidth(1.2),
          6: const pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _kBrandDark),
            children: [
              _tableCell(bold, '#', isHeader: true, isDark: true),
              _tableCell(bold, 'At', isHeader: true, isDark: true),
              _tableCell(bold, 'Result', isHeader: true, isDark: true),
              _tableCell(bold, 'BPM', isHeader: true, isDark: true, align: pw.TextAlign.right),
              _tableCell(bold, 'Conf.', isHeader: true, isDark: true, align: pw.TextAlign.right),
              _tableCell(bold, 'SpO₂', isHeader: true, isDark: true, align: pw.TextAlign.right),
              _tableCell(bold, 'Decision', isHeader: true, isDark: true),
            ],
          ),
          ...checks.asMap().entries.map((e) {
            final i    = e.key;
            final p    = e.value;
            final alt  = i.isOdd;
            final cls  = p.classification.clamp(0, 2);
            final elapsed = p.timestampMs / 1000;
            final m    = (elapsed ~/ 60).toString();
            final s    = (elapsed % 60).toStringAsFixed(0).padLeft(2, '0');
            return pw.TableRow(
              decoration: pw.BoxDecoration(color: alt ? _kBgGrey : _kWhite),
              children: [
                _tableCell(font, '${i + 1}', color: _kTextSecond),
                _tableCell(font, '$m:$s'),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: pw.BoxDecoration(
                        color: classBgs[cls],
                        borderRadius: pw.BorderRadius.circular(4)),
                    child: pw.Text(classLabels[cls],
                        style: pw.TextStyle(font: bold, fontSize: 7,
                            color: classColors[cls])),
                  ),
                ),
                _tableCell(font,
                    p.detectedBpm > 0 ? '${p.detectedBpm.toStringAsFixed(0)}' : '—',
                    align: pw.TextAlign.right),
                _tableCell(font, '${p.confidence}%', align: pw.TextAlign.right),
                _tableCell(font,
                    p.patientSpO2 > 0 ? '${p.patientSpO2.toStringAsFixed(0)}%' : '—',
                    align: pw.TextAlign.right),
                _tableCell(font, _esc(p.userDecision ?? '—')),
              ],
            );
          }),
        ],
      ),
    ]);
  }

  // ── Biometrics panel ───────────────────────────────────────────────────────

  static pw.Widget _biometricsPanel(
      pw.Font bold, pw.Font medium, pw.Font font,
      SessionDetail s, double? patSpO2) {

    // Row 1: Rescuer
    final rescuerItems = <_Metric>[];
    if (s.rescuerHRLastPause != null)
      rescuerItems.add(_Metric('Rescuer HR (last pause)',
          '${s.rescuerHRLastPause!.toStringAsFixed(0)} BPM', _kBrandBlue));
    if (s.rescuerSpO2LastPause != null)
      rescuerItems.add(_Metric('Rescuer SpO₂ (last pause)',
          '${s.rescuerSpO2LastPause!.toStringAsFixed(0)}%', _kBrandBlue));

    // RMSSD from last vital snapshot with data
    final lastVitalWithRmssd = s.rescuerVitals.lastWhere(
            (v) => v.rmssd > 0, orElse: () => const RescuerVitalSnapshot(timestampMs: 0));
    if (lastVitalWithRmssd.rmssd > 0)
      rescuerItems.add(_Metric('HRV RMSSD',
          '${lastVitalWithRmssd.rmssd} ms', _kBrandBlue));
    final lastFatigue = s.rescuerVitals.isEmpty ? 0
        : s.rescuerVitals.last.fatigueScore;
    if (lastFatigue > 0)
      rescuerItems.add(_Metric('Final Fatigue Score',
          '$lastFatigue / 100',
          lastFatigue >= 70 ? _kError : lastFatigue >= 40 ? _kWarning : _kSuccess));

    // Row 2: Patient & environment
    final patientItems = <_Metric>[];
    if (s.patientTemperature != null)
      patientItems.add(_Metric('Patient Temperature',
          '${s.patientTemperature!.toStringAsFixed(1)}  C', _kTextPrimary));
    if (patSpO2 != null)
      patientItems.add(_Metric('Patient SpO₂ (best)',
          '${patSpO2.toStringAsFixed(0)}%', _kTextPrimary));
    if (s.rescuerWristTempStart != null)
      rescuerItems.add(_Metric('Wrist Temp (start)',
          '${s.rescuerWristTempStart!.toStringAsFixed(1)}  C', _kTextSecond));
    if (s.rescuerWristTempEnd != null)
      rescuerItems.add(_Metric('Wrist Temp (end)',
          '${s.rescuerWristTempEnd!.toStringAsFixed(1)}  C', _kTextSecond));

    if (rescuerItems.isEmpty && patientItems.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(children: [
      if (rescuerItems.isNotEmpty) ...[
        _bioRow(bold, font, 'RESCUER', rescuerItems, _kBrandLight),
        pw.SizedBox(height: 6),
      ],
      if (patientItems.isNotEmpty)
        _bioRow(bold, font, 'PATIENT & ENVIRONMENT', patientItems, _kBgGrey),
    ]);
  }

  static pw.Widget _bioRow(
      pw.Font bold, pw.Font font, String label,
      List<_Metric> items, PdfColor bg) {
    return pw.Container(
      decoration: pw.BoxDecoration(
          color: bg, borderRadius: pw.BorderRadius.circular(8)),
      padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 7, color: _kTextDisabled)),
        pw.SizedBox(height: 6),
        pw.Row(
          children: items.map((m) => pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(m.value, style: pw.TextStyle(font: bold, fontSize: 14, color: m.color)),
              pw.SizedBox(height: 1),
              pw.Text(m.label, style: pw.TextStyle(font: font, fontSize: 7, color: _kTextSecond)),
            ]),
          )).toList(),
        ),
      ]),
    );
  }

  // ── Average metrics grid (multi-session) ──────────────────────────────────

  static pw.Widget _avgMetricsGrid(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions) {
    if (sessions.isEmpty) return pw.SizedBox.shrink();

    double avg(double Function(SessionSummary) fn) =>
        sessions.map(fn).reduce((a, b) => a + b) / sessions.length;

    final avgDepth = avg((s) => s.averageDepth);
    final avgRate  = avg((s) => s.averageFrequency);
    final avgCCF   = avg((s) => s.handsOnRatio);

    final metrics = [
      _Metric('Avg Depth', '${avgDepth.toStringAsFixed(1)} cm',
          _gradeColorForPct(avgDepth >= 5.0 && avgDepth <= 6.0 ? 1.0
              : avgDepth >= 4.5 ? 0.7 : 0.3)),
      _Metric('Avg Rate', '${avgRate.round()} BPM',
          _gradeColorForPct(avgRate >= 100 && avgRate <= 120 ? 1.0 : 0.5)),
      _Metric('Depth Consistency',
          '${avg((s) => s.depthConsistency).round()}%',
          _gradeColorForPct(avg((s) => s.depthConsistency) / 100)),
      _Metric('Rate Consistency',
          '${avg((s) => s.frequencyConsistency).round()}%',
          _gradeColorForPct(avg((s) => s.frequencyConsistency) / 100)),
      _Metric('Hands-On (CCF)',
          '${(avgCCF * 100).round()}%',
          _gradeColorForPct(avgCCF)),
      _Metric('Full Recoil',
          sessions.first.compressionCount > 0
              ? '${avg((s) => s.compressionCount > 0
              ? s.correctRecoil / s.compressionCount * 100 : 0).round()}%' : '—',
          _gradeColorForPct(sessions.first.compressionCount > 0
              ? avg((s) => s.compressionCount > 0
              ? s.correctRecoil / s.compressionCount : 0) : 0)),
    ];
    return _metricTileGrid(bold, font, metrics);
  }

  // ── 2×2 metric trend chart grid ───────────────────────────────────────────

  static pw.Widget _metricTrendGrid(
      pw.Font font, pw.Font medium, pw.Font bold,
      List<SessionSummary> sessions) {

    pw.Widget trendChart({
      required String title,
      required List<double> values,
      required double targetMin,
      required double targetMax,
      required PdfColor lineColor,
      required String unit,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
            color: _kBgGrey, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(title,
              style: pw.TextStyle(font: bold, fontSize: 9, color: _kTextPrimary)),
          pw.SizedBox(height: 6),
          pw.SizedBox(
            height: 60,
            child: pw.CustomPaint(painter: (canvas, size) =>
                _paintGenericSparkline(canvas, size, values,
                    targetMin: targetMin, targetMax: targetMax,
                    lineColor: lineColor)),
          ),
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(sessions.first.dateFormatted,
                style: pw.TextStyle(font: font, fontSize: 7, color: _kTextDisabled)),
            pw.Text(sessions.last.dateFormatted,
                style: pw.TextStyle(font: font, fontSize: 7, color: _kTextDisabled)),
          ]),
          pw.SizedBox(height: 2),
          pw.Row(children: [
            pw.Container(width: 8, height: 2,
                decoration: pw.BoxDecoration(
                    color: lineColor, borderRadius: pw.BorderRadius.circular(1))),
            pw.SizedBox(width: 4),
            pw.Text('$unit  |  Target: ${targetMin.toStringAsFixed(0)}-${targetMax.toStringAsFixed(0)}',
                style: pw.TextStyle(font: font, fontSize: 7, color: _kTextSecond)),
          ]),
        ]),
      );
    }

    return pw.Column(children: [
      pw.Row(children: [
        pw.Expanded(child: trendChart(
            title: 'Avg Depth (cm)', unit: 'cm',
            values: sessions.map((s) => s.averageDepth).toList(),
            targetMin: 5.0, targetMax: 6.0, lineColor: _kBrandBlue)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: trendChart(
            title: 'Avg Rate (BPM)', unit: 'BPM',
            values: sessions.map((s) => s.averageFrequency).toList(),
            targetMin: 100, targetMax: 120, lineColor: _kBrandMid)),
      ]),
      pw.SizedBox(height: 8),
      pw.Row(children: [
        pw.Expanded(child: trendChart(
            title: 'Hands-On CCF (%)', unit: '%',
            values: sessions.map((s) => s.handsOnRatio * 100).toList(),
            targetMin: 80, targetMax: 100, lineColor: _kSuccess)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: trendChart(
            title: 'Recoil (%)', unit: '%',
            values: sessions.map((s) => s.compressionCount > 0
                ? s.correctRecoil / s.compressionCount * 100 : 0.0).toList(),
            targetMin: 80, targetMax: 100, lineColor: _kWarning)),
      ]),
    ]);
  }

  // ── Emergency sessions summary (multi-session) ────────────────────────────

  static pw.Widget _emergencySessionsSummary(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions, int roscCount) {
    final roscRate = sessions.isEmpty ? 0.0 : roscCount / sessions.length * 100;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
          color: roscCount > 0 ? _kEmgGreenBg : _kErrorLight,
          borderRadius: pw.BorderRadius.circular(8),
          border: pw.Border.all(
              color: roscCount > 0 ? _kEmgGreen : _kError, width: 0.8)),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _statPanelCell(bold, font, '${sessions.length}', 'Emergency Sessions'),
          _statPanelCell(bold, font, '$roscCount', 'ROSC Detected'),
          _statPanelCell(bold, font, '${roscRate.toStringAsFixed(0)}%', 'ROSC Rate'),
          _statPanelCell(bold, font,
              '${sessions.fold<int>(0, (sum, s) => sum + s.compressionCount)}',
              'Total Compressions'),
        ],
      ),
    );
  }

  static pw.Widget _statPanelCell(
      pw.Font bold, pw.Font font, String value, String label) {
    return pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
      pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 18, color: _kTextPrimary)),
      pw.SizedBox(height: 2),
      pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, color: _kTextSecond),
          textAlign: pw.TextAlign.center),
    ]);
  }

  // ── Metric tile grid ───────────────────────────────────────────────────────

  static pw.Widget _metricTileGrid(
      pw.Font bold, pw.Font font, List<_Metric> metrics) {
    const cols = 3;
    final rows = <pw.Widget>[];
    for (var i = 0; i < metrics.length; i += cols) {
      final rowItems = metrics.skip(i).take(cols).toList();
      rows.add(pw.Row(children: [
        ...rowItems.map((m) => pw.Expanded(
          child: pw.Container(
            margin:  const pw.EdgeInsets.only(right: 6, bottom: 6),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
                color: _kBgCard,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _kDivider, width: 0.5)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(m.value, style: pw.TextStyle(font: bold, fontSize: 17, color: m.color)),
              pw.SizedBox(height: 2),
              pw.Text(m.label, style: pw.TextStyle(font: font, fontSize: 8, color: _kTextSecond)),
            ]),
          ),
        )),
        if (rowItems.length < cols)
          for (var p = 0; p < cols - rowItems.length; p++)
            pw.Expanded(child: pw.SizedBox()),
      ]));
    }
    return pw.Column(children: rows);
  }

  // ── Stat panel ────────────────────────────────────────────────────────────

  static pw.Widget _statPanel(
      pw.Font bold, pw.Font medium, List<_Cell> cells) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
          color: _kBrandLight, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: cells.map((c) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(c.label, style: pw.TextStyle(font: medium, fontSize: 9, color: _kTextSecond)),
            pw.SizedBox(height: 2),
            pw.Text(c.value, style: pw.TextStyle(font: bold, fontSize: 16, color: _kBrandBlue)),
          ]),
        )).toList(),
      ),
    );
  }

  // ── Grade sparkline panel ─────────────────────────────────────────────────

  static pw.Widget _gradeSparklinePanel(
      pw.Font font, pw.Font medium, pw.Font bold,
      List<SessionSummary> sessions, double trendDelta) {
    if (sessions.length < 2) {
      return pw.Container(height: 100, padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
              color: _kBgGrey, borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Center(child: pw.Text('Not enough sessions for trend',
              style: pw.TextStyle(font: font, fontSize: 10, color: _kTextDisabled))));
    }

    final grades = sessions.map((s) => s.totalGrade).toList();
    final trendColor = trendDelta >= 3 ? _kSuccess
        : trendDelta <= -3 ? _kError : _kWarning;
    final trendLabel = trendDelta >= 0
        ? '+${trendDelta.toStringAsFixed(1)}%'
        : '${trendDelta.toStringAsFixed(1)}%';

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
          color: _kBgGrey, borderRadius: pw.BorderRadius.circular(8)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Grade Trend  (Training Sessions)',
                style: pw.TextStyle(font: bold, fontSize: 10, color: _kTextPrimary)),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: pw.BoxDecoration(
                  color: trendColor.shade(0.15),
                  borderRadius: pw.BorderRadius.circular(999)),
              child: pw.Text(trendLabel,
                  style: pw.TextStyle(font: bold, fontSize: 9, color: trendColor)),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.SizedBox(
          height: 80,
          child: pw.CustomPaint(painter: (canvas, size) =>
              _paintGradeSparkline(canvas, size, grades)),
        ),
        pw.SizedBox(height: 4),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(sessions.first.dateFormatted,
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
          pw.Text(sessions.last.dateFormatted,
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
        ]),
      ]),
    );
  }

  // ── All-sessions table ────────────────────────────────────────────────────

  static pw.Widget _sessionTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions) {
    return pw.Table(
      border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5)),
      columnWidths: {
        0: const pw.FixedColumnWidth(22),
        1: const pw.FlexColumnWidth(1.8),
        2: const pw.FixedColumnWidth(62),
        3: const pw.FixedColumnWidth(52),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(1),
        7: const pw.FlexColumnWidth(1),
        8: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kBrandDark),
          children: [
            _tableCell(bold, '#',            isHeader: true, isDark: true),
            _tableCell(bold, 'Date',         isHeader: true, isDark: true),
            _tableCell(bold, 'Mode',         isHeader: true, isDark: true),
            _tableCell(bold, 'Scenario',     isHeader: true, isDark: true),
            _tableCell(bold, 'Duration',     isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Compr.',       isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Depth',        isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'CCF',          isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Grade',        isHeader: true, isDark: true, align: pw.TextAlign.right),
          ],
        ),
        ...sessions.asMap().entries.map((e) {
          final i          = e.key;
          final s          = e.value;
          final isAlt      = i.isOdd;
          final gradeColor = s.isEmergency ? _kTextDisabled : _gradeColor(s.totalGrade);
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isAlt ? _kBgGrey : _kWhite),
            children: [
              _tableCell(font, '${sessions.length - i}', color: _kTextSecond),
              _tableCell(font, s.dateFormatted),
              _tableModeCell(bold, s),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: pw.BoxDecoration(
                      color: s.scenario == 'pediatric' ? _kPediatricBg : _kBrandLight,
                      borderRadius: pw.BorderRadius.circular(3)),
                  child: pw.Text(s.scenario == 'pediatric' ? 'Ped.' : 'Adult',
                      style: pw.TextStyle(font: bold, fontSize: 7,
                          color: s.scenario == 'pediatric' ? _kPediatric : _kBrandBlue)),
                ),
              ),
              _tableCell(font, s.durationFormatted, align: pw.TextAlign.right),
              _tableCell(font, '${s.compressionCount}', align: pw.TextAlign.right),
              _tableCell(font,
                  s.averageDepth > 0 ? '${s.averageDepth.toStringAsFixed(1)} cm' : '—',
                  align: pw.TextAlign.right),
              _tableCell(font, '${(s.handsOnRatio * 100).round()}%',
                  align: pw.TextAlign.right,
                  color: s.handsOnRatio >= 0.80 ? _kSuccess : _kWarning),
              _tableCell(bold,
                  s.isEmergency ? '—' : '${s.totalGrade.toStringAsFixed(1)}%',
                  align: pw.TextAlign.right, color: gradeColor),
            ],
          );
        }),
      ],
    );
  }

  // ── Chart card wrapper ─────────────────────────────────────────────────────

  static pw.Widget _chartCard({
    required pw.Widget        child,
    required List<_LegendItem> legendItems,
    required pw.Font          font,
  }) {
    return pw.Container(
      width:   double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: pw.BoxDecoration(
        color:        _kBgCard,
        borderRadius: pw.BorderRadius.circular(8),
        border:       pw.Border.all(color: _kDivider, width: 0.5),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        child,
        pw.SizedBox(height: 6),
        pw.Row(
          children: legendItems.map((item) => pw.Padding(
            padding: const pw.EdgeInsets.only(right: 14),
            child: pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(width: 10, height: 3,
                    decoration: pw.BoxDecoration(
                        color: item.color, borderRadius: pw.BorderRadius.circular(2))),
                pw.SizedBox(width: 4),
                pw.Text(item.label,
                    style: pw.TextStyle(font: font, fontSize: 8, color: _kTextSecond)),
              ],
            ),
          )).toList(),
        ),
      ]),
    );
  }

  // ── Section title ──────────────────────────────────────────────────────────

  static pw.Widget _sectionTitle(pw.Font bold, String title) {
    return pw.Row(children: [
      pw.Container(width: 3, height: 14,
          decoration: pw.BoxDecoration(
              color: _kBrandBlue, borderRadius: pw.BorderRadius.circular(2))),
      pw.SizedBox(width: 6),
      pw.Text(title, style: pw.TextStyle(font: bold, fontSize: 11, color: _kTextPrimary)),
    ]);
  }

  // ── Table cell helpers ─────────────────────────────────────────────────────

  static pw.Widget _tableCell(
      pw.Font font, String text, {
        bool         isHeader = false,
        bool         isDark   = false,
        pw.TextAlign align    = pw.TextAlign.left,
        PdfColor?    color,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(text, textAlign: align,
          style: pw.TextStyle(
            font:     font,
            fontSize: isHeader ? 8 : 9,
            color: color ?? (isDark ? _kWhite
                : (isHeader ? _kTextPrimary : _kTextSecond)),
          )),
    );
  }

  static pw.Widget _tableModeCell(pw.Font bold, SessionSummary s) {
    final label = s.isEmergency ? 'Emergency'
        : s.isNoFeedback  ? 'No-Feedback'
        : 'Training';
    final color = s.isEmergency ? _kEmgGreen : _kWarning;
    final bg    = s.isEmergency ? _kEmgGreenBg : _kWarningLight;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: pw.BoxDecoration(
            color: bg, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Text(label,
            style: pw.TextStyle(font: bold, fontSize: 8, color: color)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANVAS PAINTERS
  // All painters are static functions matching the pdf package's CustomPainter
  // typedef: Function(PdfGraphics canvas, PdfPoint size)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Grade sparkline with colored grade-band background zones.
  static void _paintGradeSparkline(
      PdfGraphics canvas, PdfPoint size, List<double> grades) {
    if (grades.length < 2) return;

    final n = grades.length;

    double xOf(int i) => i / (n - 1) * size.x;
    double yOf(double g) => size.y - (g / 100).clamp(0.0, 1.0) * size.y;

    // Grade band backgrounds (bottom to top: <55 red, 55-75 orange, 75-90 blue, ≥90 green)
    void band(double lo, double hi, PdfColor color) {
      canvas.setFillColor(color.shade(0.08));
      canvas.drawRect(0, yOf(hi), size.x, yOf(lo) - yOf(hi));
      canvas.fillPath();
    }
    band(0,   55,  _kError);
    band(55,  75,  _kWarning);
    band(75,  90,  _kBrandBlue);
    band(90,  100, _kSuccess);

    // Fill under line
    canvas.setFillColor(_kBrandBlue.shade(0.12));
    canvas.moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(grades[i]));
    canvas.lineTo(xOf(n - 1), size.y);
    canvas.lineTo(0, size.y);
    canvas.closePath();
    canvas.fillPath();

    // Line
    canvas.setStrokeColor(_kBrandBlue);
    canvas.setLineWidth(1.5);
    canvas.moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(grades[i]));
    canvas.strokePath();

    // Dots — colored by grade band
    for (int i = 0; i < n; i++) {
      final g     = grades[i];
      final color = g >= 90 ? _kSuccess : g >= 75 ? _kBrandBlue : g >= 55 ? _kWarning : _kError;
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(g), 3.0, 3.0);
      canvas.fillPath();
    }
  }

  /// Generic sparkline with target band — used for depth, rate, CCF, recoil trends.
  static void _paintGenericSparkline(
      PdfGraphics canvas, PdfPoint size, List<double> values, {
        required double   targetMin,
        required double   targetMax,
        required PdfColor lineColor,
      }) {
    if (values.length < 2) return;

    final n      = values.length;
    final allMin = values.reduce((a, b) => a < b ? a : b);
    final allMax = values.reduce((a, b) => a > b ? a : b);
    // lo/hi: always bracket both data range AND target range, with a guard so hi > lo
    final lo = (allMin < targetMin * 0.85 ? allMin * 0.9 : targetMin * 0.8).clamp(0.0, double.infinity);
    final hi = (allMax > targetMax * 1.1  ? allMax * 1.1 : targetMax * 1.15) + 0.001; // +epsilon guards hi==lo

    double xOf(int i) => i / (n - 1) * size.x;
    double yOf(double v) => size.y - ((v - lo) / (hi - lo)).clamp(0.0, 1.0) * size.y;

    // Target band
    canvas.setFillColor(_kSuccess.shade(0.12));
    final bandTop    = yOf(targetMax);
    final bandHeight = yOf(targetMin) - bandTop;
    if (bandHeight > 0) {
      canvas.drawRect(0, bandTop, size.x, bandHeight);
      canvas.fillPath();
      canvas.setStrokeColor(_kSuccess.shade(0.4));
      canvas.setLineWidth(0.5);
      canvas.moveTo(0, bandTop); canvas.lineTo(size.x, bandTop); canvas.strokePath();
      canvas.moveTo(0, bandTop + bandHeight); canvas.lineTo(size.x, bandTop + bandHeight);
      canvas.strokePath();
    }

    // Fill
    canvas.setFillColor(lineColor.shade(0.1));
    canvas.moveTo(xOf(0), yOf(values[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(values[i]));
    canvas.lineTo(xOf(n - 1), size.y);
    canvas.lineTo(0, size.y);
    canvas.closePath(); canvas.fillPath();

    // Line
    canvas.setStrokeColor(lineColor);
    canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOf(values[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(values[i]));
    canvas.strokePath();

    // Dots — colored by in/out target
    for (int i = 0; i < n; i++) {
      final v     = values[i];
      final color = (v >= targetMin && v <= targetMax) ? _kSuccess : _kWarning;
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(v), 2.5, 2.5);
      canvas.fillPath();
    }
  }

  /// Depth chart — colored dots and target band.
  static void _paintDepthChart(
      PdfGraphics canvas, PdfPoint size,
      List<CompressionEvent> compressions,
      double targetMin, double targetMax) {
    if (compressions.isEmpty) return;

    const maxDepth = 9.0;
    final n = compressions.length;

    double xOf(int i) => i / (n == 1 ? 1 : n - 1) * size.x;
    double yOf(double d) => size.y - (d / maxDepth).clamp(0.0, 1.0) * size.y;

    // Target band
    canvas.setFillColor(_kSuccess.shade(0.12));
    final bandTop    = yOf(targetMax);
    final bandHeight = yOf(targetMin) - bandTop;
    canvas.drawRect(0, bandTop, size.x, bandHeight);
    canvas.fillPath();
    canvas.setStrokeColor(_kSuccess.shade(0.5));
    canvas.setLineWidth(0.5);
    canvas.moveTo(0, bandTop); canvas.lineTo(size.x, bandTop); canvas.strokePath();
    canvas.moveTo(0, bandTop + bandHeight); canvas.lineTo(size.x, bandTop + bandHeight); canvas.strokePath();

    final depths = compressions.map((c) => c.depth).toList();

    // Fill
    canvas.setFillColor(_kBrandBlue.shade(0.08));
    canvas.moveTo(xOf(0), yOf(depths[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(depths[i]));
    canvas.lineTo(xOf(n - 1), size.y);
    canvas.lineTo(0, size.y);
    canvas.closePath(); canvas.fillPath();

    // Line
    canvas.setStrokeColor(_kBrandBlue);
    canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOf(depths[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(depths[i]));
    canvas.strokePath();

    // Colored dots
    for (int i = 0; i < n; i++) {
      final d     = depths[i];
      final color = d >= targetMin && d <= targetMax ? _kSuccess
          : (d >= targetMin * 0.85 && d <= targetMax * 1.1) ? _kWarning : _kError;
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(d), 2.0, 2.0);
      canvas.fillPath();
    }
  }

  /// Rate chart — colored dots, 100-120 BPM target band.
  static void _paintRateChart(
      PdfGraphics canvas, PdfPoint size,
      List<CompressionEvent> compressions) {
    if (compressions.isEmpty) return;

    const targetMin = 100.0;
    const targetMax = 120.0;
    const minY = 60.0;
    const maxY = 160.0;
    final n = compressions.length;

    double xOf(int i) => i / (n == 1 ? 1 : n - 1) * size.x;
    double yOf(double r) => size.y - ((r - minY) / (maxY - minY)).clamp(0.0, 1.0) * size.y;

    // Band
    canvas.setFillColor(_kSuccess.shade(0.12));
    final bandTop    = yOf(targetMax);
    final bandHeight = yOf(targetMin) - bandTop;
    canvas.drawRect(0, bandTop, size.x, bandHeight); canvas.fillPath();
    canvas.setStrokeColor(_kSuccess.shade(0.5)); canvas.setLineWidth(0.5);
    canvas.moveTo(0, bandTop); canvas.lineTo(size.x, bandTop); canvas.strokePath();
    canvas.moveTo(0, bandTop + bandHeight); canvas.lineTo(size.x, bandTop + bandHeight); canvas.strokePath();

    final rates = compressions
        .map((c) => c.instantaneousRate > 0 ? c.instantaneousRate : c.frequency)
        .toList();

    // Fill
    canvas.setFillColor(_kBrandMid.shade(0.08));
    canvas.moveTo(xOf(0), yOf(rates[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(rates[i]));
    canvas.lineTo(xOf(n - 1), size.y); canvas.lineTo(0, size.y);
    canvas.closePath(); canvas.fillPath();

    // Line
    canvas.setStrokeColor(_kBrandMid); canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOf(rates[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(rates[i]));
    canvas.strokePath();

    // Colored dots
    for (int i = 0; i < n; i++) {
      final r     = rates[i];
      final color = r >= targetMin && r <= targetMax ? _kSuccess
          : (r >= 85 && r <= 135) ? _kWarning : _kError;
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(r), 2.0, 2.0);
      canvas.fillPath();
    }
  }

  /// Force chart — 600 N danger line, average line.
  static void _paintForceChart(
      PdfGraphics canvas, PdfPoint size,
      List<CompressionEvent> compressions, double avgForce) {
    if (compressions.isEmpty) return;

    const dangerN = 600.0;
    const maxN    = 700.0;
    final n       = compressions.length;
    final forces  = compressions.map((c) => c.force).toList();
    final lo      = 0.0;
    final hi      = forces.any((f) => f > dangerN) ? maxN : dangerN * 1.1;

    double xOf(int i) => i / (n == 1 ? 1 : n - 1) * size.x;
    double yOf(double f) => size.y - ((f - lo) / (hi - lo)).clamp(0.0, 1.0) * size.y;

    // Danger threshold line — dashed via short segments
    canvas.setStrokeColor(_kError.shade(0.6)); canvas.setLineWidth(0.8);
    { var dx = 0.0; while (dx < size.x) {
      canvas.moveTo(dx, yOf(dangerN));
      canvas.lineTo((dx + 4.0) < size.x ? dx + 4.0 : size.x, yOf(dangerN));
      canvas.strokePath(); dx += 7.0; } }

    // Average line
    canvas.setStrokeColor(_kTextDisabled.shade(0.6)); canvas.setLineWidth(0.6);
    canvas.moveTo(0, yOf(avgForce)); canvas.lineTo(size.x, yOf(avgForce)); canvas.strokePath();

    // Fill
    canvas.setFillColor(_kBrandMid.shade(0.07));
    canvas.moveTo(xOf(0), yOf(forces[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(forces[i]));
    canvas.lineTo(xOf(n - 1), size.y); canvas.lineTo(0, size.y);
    canvas.closePath(); canvas.fillPath();

    // Line
    canvas.setStrokeColor(_kBrandMid); canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOf(forces[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(forces[i]));
    canvas.strokePath();

    // Colored dots — red if over danger
    for (int i = 0; i < n; i++) {
      final f     = forces[i];
      final color = f > dangerN ? _kError : _kBrandMid;
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(f), 2.0, 2.0);
      canvas.fillPath();
    }
  }

  /// Posture chart — wrist alignment + flexion angle over time.
  static void _paintPostureChart(
      PdfGraphics canvas, PdfPoint size,
      List<CompressionEvent> compressions) {
    if (compressions.isEmpty) return;

    const maxAngle = 45.0;
    const alignTarget = 15.0;
    const flexTarget  = 10.0;
    final n           = compressions.length;

    double xOf(int i) => i / (n == 1 ? 1 : n - 1) * size.x;
    double yOf(double a) => size.y - (a / maxAngle).clamp(0.0, 1.0) * size.y;

    // Target lines — dashed via short segments
    canvas.setStrokeColor(_kSuccess.shade(0.5)); canvas.setLineWidth(0.5);
    for (final targetY in [yOf(alignTarget), yOf(flexTarget)]) {
      var dx = 0.0; while (dx < size.x) {
        canvas.moveTo(dx, targetY);
        canvas.lineTo((dx + 3.0) < size.x ? dx + 3.0 : size.x, targetY);
        canvas.strokePath(); dx += 5.0; } }

    // Wrist alignment line (blue)
    final alignAngles = compressions.map((c) => c.wristAlignmentAngle).toList();
    canvas.setStrokeColor(_kBrandBlue); canvas.setLineWidth(1.0);
    canvas.moveTo(xOf(0), yOf(alignAngles[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(alignAngles[i]));
    canvas.strokePath();

    // Wrist flexion line (mid blue, absolute value)
    final flexAngles = compressions.map((c) => c.wristFlexionAngle.abs()).toList();
    canvas.setStrokeColor(_kBrandMid); canvas.setLineWidth(1.0);
    canvas.moveTo(xOf(0), yOf(flexAngles[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(flexAngles[i]));
    canvas.strokePath();
  }

  /// Rescuer vitals chart — HR (red) and fatigue score (orange) over time.
  static void _paintVitalsChart(
      PdfGraphics canvas, PdfPoint size,
      List<RescuerVitalSnapshot> vitals) {
    if (vitals.length < 2) return;

    final n   = vitals.length;
    // HR: 40-200 BPM. Fatigue: 0-100.
    // Normalize both to 0-1 for the same axis, with labels explained in legend.
    final hrs      = vitals.map((v) => v.heartRate).toList();
    final fatigues = vitals.map((v) => v.fatigueScore.toDouble()).toList();

    final hrMax    = hrs.reduce((a, b) => a > b ? a : b).clamp(80.0, 200.0);
    final hrMin    = hrs.reduce((a, b) => a < b ? a : b).clamp(40.0, hrMax - 20);

    double xOf(int i)      => i / (n - 1) * size.x;
    double yOfHR(double h) => size.y - ((h - hrMin) / (hrMax - hrMin)).clamp(0.0, 1.0) * size.y;
    double yOfFat(double f)=> size.y - (f / 100).clamp(0.0, 1.0) * size.y;

    // HR line (red)
    canvas.setStrokeColor(_kError); canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOfHR(hrs[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOfHR(hrs[i]));
    canvas.strokePath();

    // Fatigue line (orange) — draw segment by segment to simulate dashes
    canvas.setStrokeColor(_kWarning); canvas.setLineWidth(1.0);
    for (int i = 1; i < n; i++) {
      if (i.isOdd) { // draw every other segment to get a dashed effect
        canvas.moveTo(xOf(i - 1), yOfFat(fatigues[i - 1]));
        canvas.lineTo(xOf(i), yOfFat(fatigues[i]));
        canvas.strokePath(); } }

    // Dots
    for (int i = 0; i < n; i++) {
      canvas.setFillColor(_kError);
      canvas.drawEllipse(xOf(i), yOfHR(hrs[i]), 1.8, 1.8); canvas.fillPath();
      canvas.setFillColor(_kWarning);
      canvas.drawEllipse(xOf(i), yOfFat(fatigues[i]), 1.8, 1.8); canvas.fillPath();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILE I/O HELPERS
  // All file operations go through these two functions only.
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> _shareFile(
      List<int> bytes, String filename, String subject, String mimeType) async {
    try {
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(Uint8List.fromList(bytes));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType, name: filename)],
        subject: subject,
      );
      return true;
    } catch (e) {
      debugPrint('ExportService _shareFile: $e');
      return false;
    }
  }

  static Future<bool> _saveToDevice(List<int> bytes, String filename) async {
    try {
      if (Platform.isAndroid) {
        const downloadsPath = '/storage/emulated/0/Download';
        final dir  = Directory(downloadsPath);
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('$downloadsPath/$filename');
        await file.writeAsBytes(Uint8List.fromList(bytes));
        await OpenFilex.open(file.path);
        debugPrint('ExportService saved → ${file.path}');
        return true;
      } else {
        // iOS: use share sheet which offers "Save to Files"
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(Uint8List.fromList(bytes));
        final mime = filename.endsWith('.pdf')  ? 'application/pdf'
            : filename.endsWith('.zip') ? 'application/zip'
            : 'text/csv';
        await Share.shareXFiles(
          [XFile(file.path, mimeType: mime, name: filename)],
          subject: 'CPR Assist — Save File',
        );
        return true;
      }
    } catch (e) {
      debugPrint('ExportService _saveToDevice: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SMALL HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static String _dateStamp() {
    final d = DateTime.now();
    return '${d.year}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
  }

  static String _stamp(DateTime? dt) {
    if (dt == null) return _dateStamp();
    return '${dt.year}'
        '${dt.month.toString().padLeft(2, '0')}'
        '${dt.day.toString().padLeft(2, '0')}'
        '_${dt.hour.toString().padLeft(2, '0')}'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  static String _dateStampFull() {
    final d = DateTime.now();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  static PdfColor _gradeColor(double grade) {
    if (grade >= 90) return _kSuccess;
    if (grade >= 75) return const PdfColor.fromInt(0xFF1976D2);
    if (grade >= 55) return _kWarning;
    return _kError;
  }

  static PdfColor _gradeColorForPct(double pct) {
    if (pct >= 0.80) return _kSuccess;
    if (pct >= 0.60) return _kWarning;
    return _kError;
  }

  /// CSV-safe string escaping — wraps in quotes if value contains comma, quote, or newline.
  static String _esc(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// UTF-8 BOM + content — makes Excel on Windows open CSV in UTF-8 automatically.
  /// Without this, Excel defaults to Windows-1252 and garbles °, -, >=, etc.
  static List<int> _csvBytes(String content) {
    const bom = [0xEF, 0xBB, 0xBF]; // UTF-8 Byte Order Mark
    return [...bom, ...utf8.encode(content)];
  }

  /// Format a DateTime for Excel: "2026-04-26 16:07:00" — no T, no Z, no milliseconds.
  /// Excel auto-detects this as a date when the column is formatted as Date/Time.
  static String _fmtDt(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final y = local.year;
    final mo = local.month.toString().padLeft(2, '0');
    final d  = local.day.toString().padLeft(2, '0');
    final h  = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s  = local.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }

  /// Boolean flag as YES/NO — more readable than 0/1 in Excel.
  static String _yn(bool v) => v ? 'YES' : 'NO';

  /// Format elapsed seconds as MM:SS for human readability.
  static String _mmss(int totalSec) {
    final m = totalSec ~/ 60;
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal data models
// ─────────────────────────────────────────────────────────────────────────────

class _Cell {
  final String label;
  final String value;
  const _Cell(this.label, this.value);
}

class _Metric {
  final String   label;
  final String   value;
  final PdfColor color;
  const _Metric(this.label, this.value, this.color);
}

class _Row {
  final String  label;
  final String  value;
  final String? note;
  final bool    isAlert;
  const _Row(this.label, this.value, {this.note, this.isAlert = false});
}

class _LegendItem {
  final String   label;
  final PdfColor color;
  const _LegendItem(this.label, this.color);
}