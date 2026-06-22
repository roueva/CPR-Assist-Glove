import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/cupertino.dart';
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

import 'package:cpr_assist/core/core.dart';
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

// ── PDF colours — derived from app_colors.dart at runtime so the PDF
//    tracks the design system automatically (no hand-copied hex). ──────────────

PdfColor _pdf(Color c) => PdfColor(
  (c.r * 255).round() / 255,
  (c.g * 255).round() / 255,
  (c.b * 255).round() / 255,
);

final _kBrandBlue    = _pdf(AppColors.primary);
final _kBrandMid     = _pdf(AppColors.primaryAlt);
final _kBrandDark    = _pdf(AppColors.cprCardBg);      // dark header surface
final _kBrandLight   = _pdf(AppColors.primaryLight);
final _kSuccess      = _pdf(AppColors.success);
final _kSuccessLight = _pdf(AppColors.successBg);
final _kWarning      = _pdf(AppColors.warning);
final _kWarningLight = _pdf(AppColors.warningBg);
final _kError        = _pdf(AppColors.error);
final _kErrorLight   = _pdf(AppColors.errorBg);
final _kNoFeedback   = _pdf(AppColors.noFeedback);
final _kNoFeedbackBg = _pdf(AppColors.noFeedbackBg);
final _kAdultBg      = _pdf(AppColors.primaryMid);  // stronger than primaryLight for pills
final _kEmgGreen     = _pdf(AppColors.emergencyMode);
final _kEmgGreenBg   = _pdf(AppColors.emergencyModeBg);
final _kPediatric    = _pdf(AppColors.pediatric);
final _kPediatricBg  = _pdf(AppColors.pediatricLight);
final _kTextPrimary  = _pdf(AppColors.textPrimary);
final _kTextSecond   = _pdf(AppColors.textSecondary);
final _kTextDisabled = _pdf(AppColors.textDisabled);
final _kDivider      = _pdf(AppColors.divider);
final _kWhite        = PdfColors.white;
final _kBgGrey       = _pdf(AppColors.screenBgGrey);

class ExportService {
  ExportService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API — PDFs
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> exportSingleSessionPdf(
      SessionDetail detail, { String? username, int? sessionNumber }) async {
    try {
      final bytes = await _buildSingleSessionPdf(detail,
          username: username, sessionNumber: sessionNumber);
      final name  = 'cpr_session_${_stamp(detail.sessionStart)}.pdf';
      return _shareFile(bytes, name, 'CPR Assist — Session Report', 'application/pdf');
    } catch (e) { debugPrint('ExportService PDF single share: $e'); return false; }
  }

  static Future<bool> downloadSingleSessionPdf(
      SessionDetail detail, { String? username, int? sessionNumber }) async {
    try {
      final bytes = await _buildSingleSessionPdf(detail,
          username: username, sessionNumber: sessionNumber);
      final name  = 'cpr_session_${_stamp(detail.sessionStart)}.pdf';
      return _saveToDevice(bytes, name);
    } catch (e) { debugPrint('ExportService PDF single download: $e'); return false; }
  }

  static Future<bool> exportMultiSessionPdf(
      List<SessionSummary> sessions, { String? username, List<SessionDetail?>? details }) async {
    if (sessions.isEmpty) return false;
    try {
      final bytes = await _buildMultiSessionPdf(sessions, username: username, details: details);
      final name  = 'cpr_sessions_${sessions.length}_${_dateStamp()}.pdf';
      return _shareFile(bytes, name, 'CPR Assist — Session History Report', 'application/pdf');
    } catch (e) { debugPrint('ExportService PDF multi share: $e'); return false; }
  }

  static Future<bool> downloadMultiSessionPdf(
      List<SessionSummary> sessions, { String? username, List<SessionDetail?>? details }) async {
    if (sessions.isEmpty) return false;
    try {
      final bytes = await _buildMultiSessionPdf(sessions, username: username, details: details);
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
      return _saveToDevice(_csvBytes(csv), name);
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
    const timeToFirstCompressionTarget = '≤10 s';

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

    void valueHeader() {
      sb.writeln('Metric,Value');
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

    final startTemp = tempVitals.isNotEmpty
        ? tempVitals.first.temperature
        : (s.rescuerWristTempStart ?? 0.0);
    final endTemp   = tempVitals.isNotEmpty
        ? tempVitals.last.temperature
        : (s.rescuerWristTempEnd ?? 0.0);

    final avgSignalQuality = rescuerVitals.isNotEmpty
        ? rescuerVitals.map((v) => v.signalQuality).reduce((a, b) => a + b) /
        rescuerVitals.length
        : 0.0;

    // ── Title ────────────────────────────────────────────────────────────────
    sb.writeln('CPR Assist - Session Metrics Summary');

    // ── INFO ─────────────────────────────────────────────────────────────────
    section('INFO');
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
      row3('Best Streak (consecutive perfect compressions)', '',
          fmtIntOrBlank(s.consecutiveGoodPeak));
    }

    if (s.mode == 'emergency') {
      final outcome = detail != null && detail.pulseChecks.isEmpty
          ? 'NO PULSE DATA'
          : (s.pulseDetectedFinal ? 'ROSC DETECTED' : 'NO ROSC');
      row2('Outcome', outcome);
    }

    // ── COMPRESSION TOTALS ───────────────────────────────────────────────────
    section('COMPRESSION TOTALS');
    valueHeader();
    row2('Total Compressions', s.compressionCount.toString());
    row2('Leaning Events', s.leaningCount.toString());
    row2('Over-Force Events', s.overForceCount.toString());

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
      '',
      s.depthRateCombo.toString(),
      pctFromCount(s.depthRateCombo),
    );
    row4(
      'All Targets Met',
      '',
      allTargetsMetCount?.toString() ?? '',
      allTargetsMetCount != null ? pctFromCount(allTargetsMetCount) : '',
    );

    // ── AVERAGES & DISTRIBUTION ──────────────────────────────────────────────
    section('AVERAGES & DISTRIBUTION');
    valueHeader();
    row2('Average Depth', fmtNum(s.averageDepth, digits: 2, suffix: ' cm'));
    row2('Average Effective Depth', fmtNum(s.averageEffectiveDepth, digits: 2, suffix: ' cm'));
    row2('Peak Depth', fmtNum(s.peakDepth, digits: 2, suffix: ' cm'));
    row2('Depth SD', fmtNum(s.depthSD, digits: 2, suffix: ' cm'));
    row2('Depth Consistency', pctValue(s.depthConsistency));
    row2('Average Rate', fmtNum(s.averageFrequency, digits: 1, suffix: ' BPM'));
    row2('Rate Consistency', pctValue(s.frequencyConsistency));
    row2('Rate Variability', fmtNum(rateVariability, digits: 0, suffix: ' ms'));

    if (avgWristAlignment > 0) {
      row2(
        'Average Wrist Alignment',
        '${avgWristAlignment.toStringAsFixed(1)}°',
      );
    }

    // ── FLOW & TIMING ────────────────────────────────────────────────────────
    section('FLOW & TIMING');
    metricHeader();
    final ccfPct = s.handsOnRatio * 100;
    row3('CCF', ccfTarget, pctValue(ccfPct));
    row3(
      'Time to First Compression',
      timeToFirstCompressionTarget,
      fmtNum(timeToFirstCompression, digits: 1, suffix: ' s'),
    );
    row3('No-Flow Intervals', '', s.noFlowIntervals.toString());
    row3('No-Flow Time', '', fmtNum(s.noFlowTime, digits: 1, suffix: ' s'));
    row3('Unplanned Pauses', 'Ideal: 0', s.unplannedPauseCount.toString());
    row3('Unplanned Pause Time', '≤10 s', fmtNum(s.unplannedPauseTime, digits: 1, suffix: ' s'));

    // ── VENTILATION ──────────────────────────────────────────────────────────
    section('VENTILATION');
    valueHeader();
    row2('Ventilation Windows Recorded', s.ventilationCount.toString());
    row2('Ventilation Target Met Windows', fmtIntOrBlank(correctVentilations));
    row2('Ventilation Target Met (%)', fmtNum(s.ventilationCompliance, digits: 1, suffix: '%'));
    row2('Total Ventilation Pause Time', fmtNum(ventilationPauseTime, digits: 1, suffix: ' s'));

    // ── PULSE CHECKS ─────────────────────────────────────────────────────────
    section('PULSE CHECKS');
    valueHeader();
    row2('Pulse Checks Prompted', s.pulseChecksPrompted.toString());
    row2('Pulse Checks Done', s.pulseChecksComplied.toString());
    row2('ROSC Detected', _yn(s.pulseDetectedFinal));

    if (detail != null && detail.pulseChecks.isNotEmpty) {
      final present   = detail.pulseChecks.where((p) => p.classification == 2).length;
      final uncertain = detail.pulseChecks.where((p) => p.classification == 1).length;
      final absent    = detail.pulseChecks.where((p) => p.classification == 0).length;
      row2('Pulse Present Count', present.toString());
      row2('Pulse Uncertain Count', uncertain.toString());
      row2('Pulse Absent Count', absent.toString());
    }

    if (lastPulseCheck != null) {
      const classLabels = ['ABSENT', 'UNCERTAIN', 'PRESENT'];
      final cls = lastPulseCheck.classification.clamp(0, 2);

      row2('Last Pulse Classification', classLabels[cls]);
      row2(
        'Last Detected BPM',
        lastPulseCheck.detectedBpm > 0
            ? '${lastPulseCheck.detectedBpm.toStringAsFixed(1)} BPM'
            : '',
      );
      row2('Last Pulse Confidence', '${lastPulseCheck.confidence}%');
      row2(
        'Patient SpO2 Last Check',
        lastPulseCheck.patientSpO2 > 0
            ? '${lastPulseCheck.patientSpO2.toStringAsFixed(1)}%'
            : '',
      );
    } else {
      row2('Last Pulse Classification', '');
      row2('Last Detected BPM', '');
      row2('Last Pulse Confidence', '');
      row2(
        'Patient SpO2 Last Check',
        patientSpO2LastCheck != null
            ? '${patientSpO2LastCheck.toStringAsFixed(1)}%'
            : '',
      );
    }

    // ── FATIGUE & RESCUER ────────────────────────────────────────────────────
    section('FATIGUE & RESCUER');
    valueHeader();
    row2(
      'Fatigue Onset',
      s.fatigueOnsetIndex > 0 ? 'Compression #${s.fatigueOnsetIndex}' : '',
    );
    row2('Rescuer Swaps', s.rescuerSwapCount.toString());

    final fatigueVitals = rescuerVitals.where((v) => v.fatigueScore > 0).toList();
    if (fatigueVitals.isNotEmpty) {
      final finalFatigue = fatigueVitals.last.fatigueScore;
      final maxFatigue   = fatigueVitals.map((v) => v.fatigueScore)
          .reduce((a, b) => a > b ? a : b);
      row2('Final Fatigue Score', '$finalFatigue');
      row2('Max Fatigue Score', '$maxFatigue');
    }

    row2('Rescuer HR at Start', fmtNum(startHR, digits: 1, suffix: ' BPM'));
    row2('Rescuer HR at End', fmtNum(endHR, digits: 1, suffix: ' BPM'));
    row2('Rescuer HR Change', fmtDelta(startHR, endHR, digits: 1, suffix: ' BPM'));

    row2('Rescuer SpO2 at Start', fmtNum(startSpO2, digits: 1, suffix: '%'));
    row2('Rescuer SpO2 at End', fmtNum(endSpO2, digits: 1, suffix: '%'));
    row2('Rescuer SpO2 Change', fmtDelta(startSpO2, endSpO2, digits: 1, suffix: '%'));

    row2('Rescuer Skin Temp at Start', fmtNum(startTemp, digits: 2, suffix: ' °C'));
    row2('Rescuer Skin Temp at End', fmtNum(endTemp, digits: 2, suffix: ' °C'));
    row2('Rescuer Skin Temp Change', fmtDelta(startTemp, endTemp, digits: 2, suffix: ' °C'));

    row2('Average Signal Quality', fmtNum(avgSignalQuality, digits: 1));
    row2('Rescuer HR at Last Pause', fmtNullable(s.rescuerHRLastPause, digits: 1, suffix: ' BPM'));
    row2('Rescuer SpO2 at Last Pause', fmtNullable(s.rescuerSpO2LastPause, digits: 1, suffix: '%'));
    row2('Patient Temperature', fmtNullable(s.patientTemperature, digits: 1, suffix: ' °C'));

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

    // Aggregate statistics on a list of values, ignoring zeros/NaN.
    ({double mean, double median, double min, double max, double sd, int n})
    aggregate(List<double> raw) {
      final values = raw.where((v) => v > 0 && v.isFinite).toList();
      if (values.isEmpty) {
        return (mean: 0, median: 0, min: 0, max: 0, sd: 0, n: 0);
      }
      values.sort();
      final n      = values.length;
      final mean   = values.reduce((a, b) => a + b) / n;
      final median = n.isOdd
          ? values[n ~/ 2]
          : (values[n ~/ 2 - 1] + values[n ~/ 2]) / 2;
      final min    = values.first;
      final max    = values.last;
      final variance = values
          .map((v) => (v - mean) * (v - mean))
          .reduce((a, b) => a + b) / n;
      final sd = variance > 0 ? math.sqrt(variance) : 0.0;
      return (mean: mean, median: median, min: min, max: max, sd: sd, n: n);
    }

    String fmtAgg(double v, {int digits = 1}) =>
        v > 0 ? v.toStringAsFixed(digits) : '';

    String modeLabel(SessionSummary s) {
      if (s.mode == 'emergency') return 'Emergency';
      if (s.mode == 'training_no_feedback') return 'Training (No Feedback)';
      return 'Training';
    }

    String scenarioLabel(SessionSummary s) {
      return s.scenario == 'pediatric' ? 'Pediatric' : 'Adult';
    }

    String emergencyOutcomeLabel(SessionSummary s) {
      if (!s.isEmergency) return '';
      return s.pulseDetectedFinal ? 'ROSC DETECTED' : 'NO ROSC';
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

    // ── OUTCOME ───────────────────────────────────────────────────────────────
    section('OUTCOME');

    row(
      'Total Grade (%)',
      '',
      sessions
          .map((s) => s.isTraining ? s.totalGrade.toStringAsFixed(1) : '')
          .toList(),
    );

    row(
      'Emergency Outcome',
      '',
      sessions.map(emergencyOutcomeLabel).toList(),
    );

    row(
      'ROSC Detected',
      '',
      sessions
          .map((s) => s.isEmergency ? _yn(s.pulseDetectedFinal) : '')
          .toList(),
    );

    row(
      'Best Streak (consecutive perfect compressions)',
      '',
      sessions
          .map((s) => s.isTraining && s.consecutiveGoodPeak > 0
          ? s.consecutiveGoodPeak.toString()
          : '')
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
      '',
      sessions.map((s) => s.leaningCount.toString()).toList(),
    );

    row(
      'Over-Force Events',
      '',
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
      '',
      sessions.map((s) => s.depthRateCombo.toString()).toList(),
    );

    // ── COMPRESSION QUALITY - PERCENTAGES ────────────────────────────────────
    section('COMPRESSION QUALITY - PERCENTAGES');

    row(
      'Depth Target Met',
      '',
      sessions
          .map((s) => pctFromCount(s.correctDepth, s.compressionCount))
          .toList(),
    );

    row(
      'Rate Target Met',
      '',
      sessions
          .map((s) => pctFromCount(s.correctFrequency, s.compressionCount))
          .toList(),
    );

    row(
      'Recoil Target Met',
      '',
      sessions
          .map((s) => pctFromCount(s.correctRecoil, s.compressionCount))
          .toList(),
    );

    row(
      'Posture Target Met',
      '',
      sessions
          .map((s) => pctFromCount(s.correctPosture, s.compressionCount))
          .toList(),
    );

    row(
      'Depth + Rate Target Met',
      '',
      sessions
          .map((s) => pctFromCount(s.depthRateCombo, s.compressionCount))
          .toList(),
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

    row(
      'Rate Variability',
      'Lower',
      sessions
          .map((s) => fmtNum(s.rateVariability, digits: 0, suffix: ' ms'))
          .toList(),
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
      'Ideal: 0',
      sessions.map((s) => s.unplannedPauseCount.toString()).toList(),
    );

    row(
      'Unplanned Pause Time',
      '≤10 s',
      sessions
          .map((s) => fmtNum(s.unplannedPauseTime, digits: 1, suffix: ' s'))
          .toList(),
    );

    row(
      'Time to First Compression',
      '≤10 s',
      sessions
          .map((s) => fmtNum(s.timeToFirstCompression, digits: 1, suffix: ' s'))
          .toList(),
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
        return s.correctVentilations.toString();
      }).toList(),
    );

    row(
      'Ventilation Target Met (%)',
      '',
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
      sessions
          .map((s) => s.isEmergency ? s.pulseChecksPrompted.toString() : '')
          .toList(),
    );

    row(
      'Pulse Checks Done',
      '',
      sessions
          .map((s) => s.isEmergency ? s.pulseChecksComplied.toString() : '')
          .toList(),
    );

    row(
      'ROSC Detected',
      '',
      sessions
          .map((s) => s.isEmergency ? _yn(s.pulseDetectedFinal) : '')
          .toList(),
    );

    // ── FATIGUE & RESCUER ────────────────────────────────────────────────────
    section('FATIGUE & RESCUER');

    row(
      'Fatigue Onset',
      '',
      sessions
          .map((s) => s.fatigueOnsetIndex > 0
          ? '#${s.fatigueOnsetIndex}'
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
      'Rescuer Wrist Temp at Start',
      '',
      sessions
          .map((s) => fmtNullable(s.rescuerWristTempStart, digits: 2, suffix: ' °C'))
          .toList(),
    );

    row(
      'Rescuer Wrist Temp at End',
      '',
      sessions
          .map((s) => fmtNullable(s.rescuerWristTempEnd, digits: 2, suffix: ' °C'))
          .toList(),
    );

    row(
      'Patient Temperature',
      '',
      sessions
          .map((s) => fmtNullable(s.patientTemperature, digits: 1, suffix: ' °C'))
          .toList(),
    );

    // ── AGGREGATE ─────────────────────────────────────────────────────────────
    blankLine();
    sb.writeln('AGGREGATE');
    sb.writeln('Statistics across all ${sessions.length} sessions (missing values excluded)');
    sb.writeln('Metric,N,Mean,Median,Min,Max,SD');

    void aggRow(String label, List<double> values, {int digits = 1}) {
      final a = aggregate(values);
      sb.writeln([
        _esc(label),
        a.n.toString(),
        fmtAgg(a.mean,   digits: digits),
        fmtAgg(a.median, digits: digits),
        fmtAgg(a.min,    digits: digits),
        fmtAgg(a.max,    digits: digits),
        fmtAgg(a.sd,     digits: digits),
      ].join(','));
    }

    // Grade — training only
    final trainingGrades = sessions
        .where((s) => s.isTraining)
        .map((s) => s.totalGrade)
        .toList();
    if (trainingGrades.isNotEmpty) {
      aggRow('Total Grade (%) [training only]', trainingGrades, digits: 1);
    }

    aggRow('Total Compressions',
        sessions.map((s) => s.compressionCount.toDouble()).toList(),
        digits: 0);

    aggRow('Session Duration (s)',
        sessions.map((s) => s.sessionDuration.toDouble()).toList(),
        digits: 0);

    aggRow('Average Depth (cm)',
        sessions.map((s) => s.averageDepth).toList(),
        digits: 2);

    aggRow('Average Rate (BPM)',
        sessions.map((s) => s.averageFrequency).toList(),
        digits: 1);

    aggRow('Depth Consistency (%)',
        sessions.map((s) => s.depthConsistency).toList(),
        digits: 1);

    aggRow('Rate Consistency (%)',
        sessions.map((s) => s.frequencyConsistency).toList(),
        digits: 1);

    aggRow('CCF (%)',
        sessions.map((s) => s.handsOnRatio * 100).toList(),
        digits: 1);

    aggRow('Time to First Compression (s)',
        sessions.map((s) => s.timeToFirstCompression).toList(),
        digits: 1);

    aggRow('No-Flow Time (s)',
        sessions.map((s) => s.noFlowTime).toList(),
        digits: 1);

    aggRow('Rate Variability (ms)',
        sessions.map((s) => s.rateVariability).toList(),
        digits: 0);

    aggRow('Ventilation Compliance (%)',
        sessions
            .where((s) => s.ventilationCount > 0)
            .map((s) => s.ventilationCompliance)
            .toList(),
        digits: 1);

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

    // A gap is "planned" if a ventilation/pulse-check prompt occurred at or
    // shortly before it started — same association rule as
    // SessionDetail._calculatePauseMetrics (single source of truth).
    bool isPlannedGap(double a, double b) {
      const tol = AppConstants.plannedWindowAssocToleranceSec;
      return d.ventilations.any((v) {
        final vs = v.timestampMs / 1000.0;
        return vs >= a - tol && vs <= b;
      }) ||
          d.pulseChecks.any((p) {
            final ps = p.timestampMs / 1000.0;
            return ps >= a - tol && ps <= b;
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
      'Row #',
      'Compression #',

      // Timing
      'Peak Time (ms)',
      'Release Time (ms)',
      'Inter-compression Interval (ms)',
      'Unplanned Pause After (ms)',

      // Depth
      'Peak Depth (cm)',
      'Depth Target Met (${depthMin.toStringAsFixed(1)}-${depthMax.toStringAsFixed(1)} cm)',
      'Estimated Effective Depth (cm)',

// Compression phases
      'Downstroke Duration (ms)',

// Recoil
      'Recoil Depth (cm)',
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
      required String depthTargetMet,
      required String effectiveDepth,

      required String downstrokeDuration,

      required String recoilDepth,
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
        depthTargetMet,
        effectiveDepth,

        downstrokeDuration,

        recoilDepth,
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

        final gapSec = nextTime - currentTime;
        if (gapSec > 2.0) {
          if (!isPlannedGap(currentTime, nextTime)) {
            pauseAfter = (gapSec * 1000).toStringAsFixed(0);
          } else if (gapSec > AppConstants.maxAcceptablePauseSec) {
            // Planned pause overran — record only the unplanned excess so the
            // per-row column is consistent with the summary total (Behavior Y).
            pauseAfter = ((gapSec - AppConstants.maxAcceptablePauseSec) * 1000)
                .toStringAsFixed(0);
          }
        }
      }

      // Recoil duration: peak of compression N → valley locked at start of compression N+1
      String recoilDur = '';
      if (c.valleyTimestampMs > 0 && peakMs > 0 && c.valleyTimestampMs > peakMs) {
        recoilDur = (c.valleyTimestampMs - peakMs).toString();
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
        depthTargetMet: _yn(depthTargetMet),
        effectiveDepth: c.effectiveDepth > 0
            ? c.effectiveDepth.toStringAsFixed(2)
            : '',

        downstrokeDuration: fmtInt(c.downstrokeTimeMs),

        recoilDepth: c.valleyDepth > 0
            ? c.valleyDepth.toStringAsFixed(2)
            : '',
        recoilDuration: recoilDur,
        recoilTargetMet: hasRecoilData ? _yn(c.recoilAchieved) : '',
        leaningDetected: hasRecoilData ? _yn(c.leaningDetected) : '',

        force: fmtNum(c.peakForce > 0 ? c.peakForce : c.force, digits: 1),
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
        final end = start + AppConstants.maxAcceptablePauseSec;
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
      'Row #',
      'Elapsed Time (ms)',
      'Context',
      'Rescuer Heart Rate (BPM)',
      'Rescuer SpO2 (%)',
      'Rescuer Wrist Temperature (°C)',
      'Rescuer Signal Quality (0-100)',
      'RMSSD (ms)',
      'Rescuer Perfusion Index (0-100)',
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
      'Row #',
      'Elapsed Time (ms)',
      '30:2 Cycle #',
      'Window Duration (s)',
      'Ventilation Timing Target Met',
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
      'Row #',
      'Elapsed Time (ms)',
      'Pulse Check #',
      'Pulse Result',
      'Pulse Result Code',
      'Estimated Patient Pulse Rate (BPM)',
      'Signal Quality (0-100)',
      'Perfusion Index (0-100)',
      'Patient SpO2 (%)',
      'Raw IR Peak Count',
      'Confirmed Beat Count',
      'Beat Agreement Ratio',
      'Rescuer Decision',
      'PPG Sample Count',
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

      final beatAgreementRatio = p.detectorACount > 0
          ? p.detectorBCount / p.detectorACount
          : 0.0;
      

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
        beatAgreementRatio.toStringAsFixed(2),
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
        '  compressions.csv   - One row per chest compression with depth, recoil, rate, force, posture, and pause metrics\n'
        '  rescuer_vitals.csv - ${d.rescuerVitals.length} rescuer vital snapshots for fatigue and physiological monitoring\n'
        '  ventilations.csv   - ${d.ventilations.length} ventilation timing windows\n'
        '  pulse_checks.csv   - ${d.pulseChecks.length} patient pulse-check results\n\n'

        'GENERAL CSV STRUCTURE\n'
        '  Each CSV file contains three parts:\n\n'
        '  1) HEADER BLOCK\n'
        '     Appears at the top of the file.\n'
        '     Identifies the exported session and export context.\n\n'
        '  2) SUMMARY BLOCK\n'
        '     Starts after the line SUMMARY.\n'
        '     Contains already-calculated session-level metrics.\n'
        '     Use this block for quick reporting without recalculating values manually.\n\n'
        '  3) DATA BLOCK\n'
        '     Starts after the line DATA.\n'
        '     Contains the detailed row-level table.\n'
        '     Use this block for detailed analysis, charts, validation, and statistics.\n\n'
        '  Blank values mean that the value was not available, not applicable, or could not be calculated.\n\n'

        'COMMON HEADER FIELDS\n'
        '  Export Type   - Shows which raw CSV file this is, such as raw compressions, raw rescuer vitals, raw ventilations, or raw pulse checks\n'
        '  Session ID    - Unique session identifier. If the session has not synced to the backend, it appears as local (not synced)\n'
        '  Date & Time   - Session start date and time\n'
        '  Mode          - Session mode, such as Training, Training without Feedback, or Emergency\n'
        '  Scenario      - Adult or Pediatric CPR scenario\n'
        '  Note          - User or session note, if available\n\n'

        '================================================\n'
        'compressions.csv\n'
        '================================================\n'
        'PURPOSE\n'
        '  Stores detailed compression-by-compression CPR quality data.\n'
        '  This is the main file for analyzing compression depth, rate, recoil, force, posture, pauses, and overall CPR quality.\n\n'

        'SUMMARY BLOCK FIELDS\n'
        '  Duration                         - Total session duration\n'
        '  Total Compressions               - Total number of compressions recorded\n'
        '  Time to First Compression (s)    - Time from session start until the first compression\n'
        '  Correct Depth Compressions       - Number of compressions within the target depth range\n'
        '  Correct Rate Compressions        - Number of compressions within the target rate range\n'
        '  Correct Recoil Compressions      - Number of compressions with acceptable chest recoil\n'
        '  Avg Depth (cm)                   - Average compression depth across the session\n'
        '  Avg Rate (BPM)                   - Average compression rate across the session\n'
        '  CCF (%)                          - Chest compression fraction. This is the percentage of session time spent actively compressing\n'
        '  No-Flow Intervals                - Number of detected intervals without compressions\n'
        '  No-Flow Time (s)                 - Total time without compressions\n'
        '  Total Unplanned Pauses           - Number of long pauses not explained by planned ventilation or pulse-check windows\n'
        '  Total Unplanned Pause Time (s)   - Total duration of unplanned pauses, when available\n'
        '  Rescuer Swaps                    - Number of rescuer swaps, when detected\n'
        '  Fatigue Onset Compression #      - Compression number where fatigue was first detected, when available\n'
        '  Pulse Checks                     - Number of pulse checks, only shown for emergency sessions when pulse checks exist\n'
        '  Final Outcome                    - Final emergency outcome, only shown for emergency sessions when pulse checks exist\n\n'

        'DATA BLOCK\n'
        '  One row represents one chest compression.\n\n'

        'DATA COLUMN GUIDE\n'
        '  Row #                       - Row number in the DATA table\n'
        '  Compression #               - Compression number in the session\n'
        '  Peak Time (ms)              - Time from session start to the deepest point of the compression\n'
        '  Release Time (ms)           - Time from session start to the release or recoil point after the compression\n'
        '  Inter-compression Interval  - Time between this compression peak and the previous compression peak\n'
        '  Unplanned Pause After (ms)  - Long gap after this compression, excluding planned ventilation or pulse-check pauses\n'
        '  Peak Depth (cm)             - Maximum compression depth reached during this compression\n'
        '  Depth Target Met            - YES if peak depth is within the adult or pediatric target range\n'
        '  Estimated Effective Depth   - Estimated usable or corrected compression depth used for quality analysis\n'
        '  Downstroke Duration (ms)    - Time from compression start to peak depth\n'
        '  Recoil Depth (cm)           - Remaining depth after release. Lower values indicate better chest recoil\n'
        '  Recoil Duration (ms)        - Time from peak depth to release or recoil\n'
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

        '================================================\n'
        'rescuer_vitals.csv\n'
        '================================================\n'
        'PURPOSE\n'
        '  Stores rescuer physiological snapshots recorded during the session.\n'
        '  This file is mainly used for fatigue monitoring and for comparing CPR quality with rescuer physiological state.\n\n'

        'SUMMARY BLOCK FIELDS\n'
        '  Duration                         - Total session duration\n'
        '  Total Vital Snapshots            - Number of rescuer vital snapshots recorded\n'
        '  Start Heart Rate (BPM)           - Rescuer heart rate at the first available snapshot\n'
        '  End Heart Rate (BPM)             - Rescuer heart rate at the last available snapshot\n'
        '  Heart Rate Change (BPM)          - Difference between end heart rate and start heart rate\n'
        '  Start Rescuer SpO2 (%)           - Rescuer oxygen saturation at the first available snapshot\n'
        '  End Rescuer SpO2 (%)             - Rescuer oxygen saturation at the last available snapshot\n'
        '  Rescuer SpO2 Change (%)          - Difference between end SpO2 and start SpO2\n'
        '  Start Rescuer Wrist Temp (°C)     - Rescuer wrist temperature at the first available snapshot\n'
        '  End Rescuer Wrist Temp (°C)       - Rescuer wrist temperature at the last available snapshot\n'
        '  Rescuer Wrist Temp Change (°C)    - Difference between end wrist temperature and start wrist temperature\n'
        '  Avg Heart Rate (BPM)             - Average rescuer heart rate, when available\n'
        '  Avg Rescuer SpO2 (%)             - Average rescuer oxygen saturation, when available\n'
        '  Avg Rescuer Wrist Temp (°C)       - Average rescuer wrist temperature, when available\n'
        '  Avg RMSSD (ms)                   - Average RMSSD value, when available\n'
        '  Avg Perfusion Index (0-100)      - Average rescuer perfusion index, when available\n'
        '  Avg Fatigue Score                - Average estimated fatigue score, when available\n'
        '  Max Fatigue Score                - Highest estimated fatigue score, when available\n\n'

        'DATA BLOCK\n'
        '  One row represents one rescuer vital snapshot.\n'
        '  The Context column explains what was happening when the snapshot was recorded.\n\n'

        'DATA COLUMN GUIDE\n'
        '  Row #                             - Row number in the DATA table\n'
        '  Elapsed Time (ms)                 - Time from session start when the snapshot was recorded\n'
        '  Context                           - Session context at the time of the snapshot\n'
        '  Rescuer Heart Rate (BPM)          - Rescuer heart rate from the wrist PPG sensor\n'
        '  Rescuer SpO2 (%)                  - Rescuer oxygen saturation from the wrist PPG sensor\n'
        '  Rescuer Wrist Temperature (°C)     - Rescuer wrist temperature\n'
        '  Rescuer Signal Quality (0-100)    - Wrist PPG signal quality for the snapshot\n'
        '  RMSSD (ms)                        - Within-session HRV-related fatigue indicator. This is not an absolute clinical diagnosis\n'
        '  Rescuer Perfusion Index (0-100)   - Wrist blood-flow or perfusion signal index\n'
        '  Estimated Fatigue Score (0-100)   - Composite fatigue estimate based on rescuer physiological and CPR-performance trends\n\n'

        'CONTEXT VALUES\n'
        '  active_cpr                  - Snapshot was recorded during active compressions\n'
        '  ventilation                 - Snapshot was recorded during a ventilation window\n'
        '  pulse_check                 - Snapshot was recorded during a pulse-check window\n'
        '  before_first_compression    - Snapshot was recorded before the first compression\n'
        '  after_last_compression      - Snapshot was recorded after the final compression\n'
        '  no_compressions             - No compression data existed for the session\n\n'

        '================================================\n'
        'ventilations.csv\n'
        '================================================\n'
        'PURPOSE\n'
        '  Stores ventilation timing windows.\n'
        '  This file checks whether ventilation pauses happened at the expected time and whether their duration was acceptable.\n'
        '  It does not prove that an effective breath was delivered.\n\n'

        'SUMMARY BLOCK FIELDS\n'
        '  Duration                          - Total session duration\n'
        '  Total Ventilation Windows         - Number of ventilation windows recorded\n'
        '  Ventilation Target Met Windows    - Number of ventilation windows with acceptable timing\n'
        '  Ventilation Compliance (%)        - Percentage of ventilation windows with acceptable timing\n'
        '  Avg Window Duration (s)           - Average ventilation window duration\n\n'

        'DATA BLOCK\n'
        '  One row represents one ventilation window.\n'
        '  The row describes when the window started, which 30:2 cycle it belongs to, and whether the timing target was met.\n\n'

        'DATA COLUMN GUIDE\n'
        '  Row #                           - Row number in the DATA table\n'
        '  Elapsed Time (ms)               - Start time of the ventilation window\n'
        '  30:2 Cycle #                    - CPR cycle number associated with the ventilation window\n'
        '  Window Duration (s)             - Length of the ventilation pause or window\n'
        '  Ventilation Timing Target Met   - YES if the ventilation window timing was acceptable\n\n'

        '================================================\n'
        'pulse_checks.csv\n'
        '================================================\n'
        'PURPOSE\n'
        '  Stores patient pulse-check results.\n'
        '  This file helps review whether the system classified the pulse as absent, uncertain, or present, and why.\n\n'

        'SUMMARY BLOCK FIELDS\n'
        '  Duration              - Total session duration\n'
        '  Final Result          - Final pulse outcome for the session\n'
        '  Total Pulse Checks    - Total number of pulse checks recorded\n'
        '  Pulse Present         - Number of pulse checks classified as present\n'
        '  Pulse Uncertain       - Number of pulse checks classified as uncertain\n'
        '  Pulse Absent          - Number of pulse checks classified as absent\n\n'

        'DATA BLOCK\n'
        '  One row represents one pulse check.\n'
        '  The row contains the final classification, patient pulse estimate, confidence, signal quality, detector counts, user decision, and optional PPG waveform.\n\n'

        'DATA COLUMN GUIDE\n'
        '  Row #                                 - Row number in the DATA table\n'
        '  Elapsed Time (ms)                     - Time from session start when the pulse check result was recorded\n'
        '  Pulse Check #                         - CPR pulse-check number or interval number\n'
        '  Pulse Result                          - Final result: ABSENT, UNCERTAIN, or PRESENT\n'
        '  Pulse Result Code                     - 0 = absent, 1 = uncertain, 2 = present\n'
        '  Estimated Patient Pulse Rate (BPM)    - Patient pulse rate estimated from the heart-rate algorithm, when valid\n'
        '  Signal Quality (0-100)                - Patient PPG signal quality used by the pulse classifier, if stored\n'
        '  Perfusion Index (0-100)               - Patient PPG signal or perfusion strength\n'
        '  Patient SpO2 (%)                      - Patient oxygen saturation, if available\n'
        '  Raw IR Peak Count                     - Raw pulse peaks detected from the patient MAX30102 IR signal during the pulse-check window\n'
        '  Confirmed Beat Count                  - Peaks that passed the physiological refractory timing gate. This rejects implausible peaks caused by noise or dicrotic artifacts\n'
        '  Beat Agreement Ratio                  - Confirmed Beat Count divided by Raw IR Peak Count. Lower values suggest noisy or unstable pulse detection\n'
        '  Rescuer Decision                      - User decision after the pulse check, such as Continue CPR or Stop CPR\n'
        '  PPG Sample Count                      - Number of waveform samples stored for this pulse check\n'
        '  PPG Waveform                          - Normalized 0.0 to 1.0 waveform values separated with semicolons\n\n'

        'PULSE DETECTION NOTES\n'
        '  Raw IR Peak Count is the sensitive detector. It counts raw peaks from the patient IR PPG signal and may over-count in noisy conditions.\n'
        '  Confirmed Beat Count is the specific detector. It only counts peaks that pass the refractory timing gate used in firmware.\n'
        '  Beat Agreement Ratio helps explain the pulse result. A high ratio means most raw peaks were confirmed. A low ratio suggests noise, motion artifact, unstable contact, or dicrotic-wave over-counting.\n'
        '  Pulse Result should be interpreted together with Estimated Patient Pulse Rate, Signal Quality, Perfusion Index, and the detector counts.\n\n'

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
        '  After this, df contains only the DATA table.\n'
        '  The HEADER and SUMMARY blocks are intentionally skipped.\n\n'

        'IMPORTANT NOTES\n'
        '  These exports are intended for CPR performance review, training analysis, and research validation.\n'
        '  Sensor-derived physiological values should not be treated as standalone clinical diagnoses.\n'
        '  Patient pulse and SpO2 values depend on signal quality and should be interpreted together with confidence, perfusion index, and detector agreement.\n'
        '  Ventilation timing windows indicate timing compliance only. They do not prove that an effective breath was delivered.\n';


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
      SessionDetail s, { String? username, int? sessionNumber }) async {

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

    final patSpO2    = s.patientSpO2LastCheck;
    final hasBio     = s.rescuerHRLastPause != null ||
        s.rescuerSpO2LastPause != null ||
        s.patientTemperature != null ||
        patSpO2 != null ||
        s.rescuerWristTempStart != null ||
        s.rescuerWristTempEnd != null;

    final hasForceData   = s.compressions.any((c) => c.force > 0);
    final hasPostureData = s.compressions.any(
            (c) => c.wristAlignmentAngle > 0 || c.wristFlexionAngle.abs() > 0);
    final hasVitals      = s.rescuerVitals.isNotEmpty;

    final avgForce = s.compressions.isEmpty ? 0.0
        : s.compressions.map((c) => c.force).reduce((a, b) => a + b) /
        s.compressions.length;

    // ── Derived pcts for hero rings ──────────────────────────────────────────
    final depthPct  = s.compressionCount > 0
        ? (s.correctDepth    / n * 100).clamp(0.0, 100.0) : 0.0;
    final ratePct   = s.compressionCount > 0
        ? (s.correctFrequency / n * 100).clamp(0.0, 100.0) : 0.0;
    final recoilPct = s.compressionCount > 0
        ? (s.correctRecoil   / n * 100).clamp(0.0, 100.0) : 0.0;
    final posturePct = s.compressionCount > 0
        ? (s.correctPosture  / n * 100).clamp(0.0, 100.0) : 0.0;

    print('[PDF] sessionStart = ${s.sessionStart}');
    print('[PDF] dateTimeFormatted = ${s.dateTimeFormatted}');
    debugPrint('PDF note: ${s.note}');

    doc.addPage(pw.MultiPage(
      maxPages: 100,
      pageTheme: pw.PageTheme(
        theme:      theme,
        pageFormat: PdfPageFormat.a4,
        margin:     const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        buildBackground: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _kBgGrey),
        ),
      ),
        header: (ctx) => _pageHeader(
          robotoBold, robotoMedium,
          title:    isTraining
              ? 'CPR Training Session Report'
              : 'CPR Emergency Session Record',
          subtitle: '${s.dateTimeFormatted}  ·  ${s.durationFormatted}',
          username: username,
          sessionNumber: sessionNumber,
          note:     s.note,
          pills: [
            if (s.scenario == 'pediatric')
              _HeaderPillSpec('PEDIATRIC', _kPediatric, _kPediatricBg)
            else
              _HeaderPillSpec('ADULT', _kBrandBlue, _kAdultBg),
            if (s.isNoFeedback)
              _HeaderPillSpec('NO FEEDBACK', _kNoFeedback, _kNoFeedbackBg),
          ],
        ),
      footer: (ctx) => _pageFooter(roboto, ctx),

      build: (ctx) => [
        // ── 1. Hero card ───────────────────────────────────────────────────
        if (isTraining)
          _buildTrainingHero(robotoBold, robotoMedium, roboto,
              s.totalGrade, depthPct, ratePct, recoilPct, posturePct)
        else
          _buildEmergencyHero(robotoBold, robotoMedium, roboto, s),
        pw.SizedBox(height: 18),

        // ── 3. Headline Metrics grid (training only) ───────────────────────
        if (isTraining) ...[
          _sectionTitle(robotoBold, 'Headline Metrics'),
          pw.SizedBox(height: 10),
          _buildMetricGrid(robotoBold, robotoMedium, roboto, s, depthMin, depthMax),
          pw.SizedBox(height: 20),

          // ── 4. Quality Breakdown bar table ──────────────────────────────
          _sectionTitle(robotoBold, 'Quality Breakdown'),
          pw.SizedBox(height: 10),
          _buildQualityBarTable(robotoBold, robotoMedium, roboto, s, n,
              depthMin, depthMax),
          pw.SizedBox(height: 20),
        ],

        // ── 5. Reading guide (moved here, just before the charts) ──────────
        _buildMethodologyBox(roboto, robotoBold),
        pw.NewPage(),

        // ── Depth chart ────────────────────────────────────────────────────
        if (s.compressions.isNotEmpty) ...[
          _buildTimeChart(
            font: roboto, fontBold: robotoBold,
            title: 'Compression Depth Over Time',
            subtitle: 'Per-compression peak depth, measured from baseline to maximum.',
            caption: 'Green band = AHA target depth '
                '(${depthMin.toStringAsFixed(0)}–${depthMax.toStringAsFixed(0)} cm). '
                'Dots: green = in target, amber = close but off, red = out of range. '
                'Watch for a downward drift across the session — that indicates fatigue.',
            lines: [
              _ChartLine(
                  _series(s.compressions,
                          (c) => c.timestampSec, (c) => c.depth),
                  _kBrandBlue, fill: true),
            ],
            minY: 0, maxY: 9, yTickInterval: 3,
            yLabel: (v) => v.toStringAsFixed(0),
            band: _ChartBand(depthMin, depthMax,
                _kSuccess.shade(0.12), _kSuccess.shade(0.5)),
            legend: [
              _LegendItem('Depth (cm)', _kBrandBlue),
              _LegendItem(
                  'Target ${depthMin.toStringAsFixed(0)}-${depthMax.toStringAsFixed(0)} cm',
                  _kSuccess),
            ],
            plotHeight: 100,
            dotColor: (_, d) => d >= depthMin && d <= depthMax
                ? _kSuccess
                : (d >= depthMin * 0.85 && d <= depthMax * 1.1)
                ? _kWarning : _kError,
          ),
          pw.SizedBox(height: 14),
        ],

        // ── Phase depth chart ──────────────────────────────────────────────
        if (s.compressions.length >= 30) ...[
          _sectionTitle(robotoBold, 'Depth by Phase'),
          pw.SizedBox(height: 4),
          pw.Text(
              'Average depth in the first / middle / last third of the session — '
                  'a downward trend across thirds is the classic fatigue signature.',
              style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
          pw.SizedBox(height: 10),
          _buildPhaseDepthCard(robotoBold, robotoMedium, roboto,
              s.compressions, depthMin, depthMax),
          pw.SizedBox(height: 18),
        ],

        // ── Rate chart ─────────────────────────────────────────────────────
        if (s.compressions.isNotEmpty) ...[
          _buildTimeChart(
            font: roboto, fontBold: robotoBold,
            title: 'Compression Rate Over Time',
            subtitle: 'Instantaneous rate, computed from inter-compression intervals.',
            caption: 'Green band = AHA target rate (100–120 BPM). '
                'Rates above 120 reduce diastolic filling time; '
                'rates below 100 reduce coronary perfusion pressure. '
                'Aim to stay in the green band throughout the session.',
            lines: [
              _ChartLine(
                  _series(s.compressions, (c) => c.timestampSec,
                          (c) => c.instantaneousRate > 0
                          ? c.instantaneousRate : c.frequency),
                  _kBrandMid, fill: true),
            ],
            minY: 60, maxY: 160, yTickInterval: 20,
            yLabel: (v) => v.toStringAsFixed(0),
            band: _ChartBand(100, 120,
                _kSuccess.shade(0.12), _kSuccess.shade(0.5)),
            legend: [
              _LegendItem('Rate (BPM)', _kBrandMid),
              _LegendItem('Target 100-120 BPM', _kSuccess),
            ],
            plotHeight: 100,
            dotColor: (_, r) => r >= 100 && r <= 120
                ? _kSuccess
                : (r >= 85 && r <= 135) ? _kWarning : _kError,
          ),
          pw.SizedBox(height: 14),
        ],

        // ── Force chart ────────────────────────────────────────────────────
        if (hasForceData) ...[
          _buildTimeChart(
            font: roboto, fontBold: robotoBold,
            title: 'Compression Force Over Time',
            subtitle: 'Peak force per compression, measured at the FlexiForce sensor.',
            caption: 'Red dashed line at 600 N = injury threshold. '
                'Forces above this risk rib fractures. '
                'Lower forces are not necessarily bad — depth is the clinical target, '
                'force just measures how hard you push to achieve it.',
            lines: [
              _ChartLine(
                  _series(s.compressions,
                          (c) => c.timestampSec, (c) => c.force),
                  _kBrandMid, fill: true),
            ],
            minY: 0,
            maxY: s.compressions.any((c) => c.force > 600) ? 700 : 660,
            yTickInterval: 100,
            yLabel: (v) => v.toStringAsFixed(0),
            guides: [
              _ChartGuide(600, _kError.shade(0.6)),
              _ChartGuide(avgForce, _kTextDisabled.shade(0.6)),
            ],
            legend: [
              _LegendItem('Force (N)', _kBrandMid),
              _LegendItem('600 N danger threshold', _kError),
              _LegendItem('Average ${avgForce.toStringAsFixed(0)} N', _kTextDisabled),
            ],
            plotHeight: 90,
            dotColor: (_, f) => f > 600 ? _kError : _kBrandMid,
          ),
          pw.SizedBox(height: 14),
        ],

        // ── Posture chart ──────────────────────────────────────────────────
        if (hasPostureData) ...[
          _buildTimeChart(
            font: roboto, fontBold: robotoBold,
            title: 'Wrist Posture Over Time',
            subtitle: 'Alignment (palm tilt) and flexion (wrist bend) per compression.',
            caption: 'Both should stay under 15° (alignment) and 10° (flexion). '
                'Bent wrists reduce force transfer to the chest and increase rescuer '
                'fatigue. Keep elbows locked and shoulders directly over wrists.',
            lines: [
              _ChartLine(
                  _series(s.compressions, (c) => c.timestampSec,
                          (c) => c.wristAlignmentAngle),
                  _kBrandBlue),
              _ChartLine(
                  _series(s.compressions, (c) => c.timestampSec,
                          (c) => c.wristFlexionAngle.abs()),
                  _kBrandMid),
            ],
            minY: 0, maxY: 45, yTickInterval: 15,
            yLabel: (v) => '${v.toStringAsFixed(0)}°',
            guides: [
              _ChartGuide(15, _kSuccess.shade(0.5)),
              _ChartGuide(10, _kSuccess.shade(0.5)),
            ],
            legend: [
              _LegendItem('Wrist alignment (°)', _kBrandBlue),
              _LegendItem('Wrist flexion (°)', _kBrandMid),
              _LegendItem('15° / 10° targets', _kSuccess),
            ],
            plotHeight: 90,
          ),
          pw.SizedBox(height: 20),
        ],

        // ── Rescuer vitals chart ───────────────────────────────────────────
        if (hasVitals) ...[
          _buildTimeChart(
            font: roboto, fontBold: robotoBold,
            title: 'Rescuer Vitals Over Time',
            subtitle: 'Heart rate (PPG) and composite fatigue score during pauses.',
            caption: 'Heart rate climbs and fatigue score rises with sustained CPR. '
                'A fatigue score above 70 is a recommended cue to swap rescuers. '
                'Vitals are sampled during ventilation and pulse-check windows.',
            lines: [
              _ChartLine(
                // M28: plot all real HR readings for a continuous trend;
                // signal quality is preserved per-row in the CSV export.
                  _series(s.rescuerVitals,
                          (v) => v.timestampSec, (v) => v.heartRate,
                      where: (v) => v.heartRate > 0),
                  _kError),
              _ChartLine(
                // M28: fatigueScore is a composite that does not depend on
                // PPG signal quality the way raw HR does — plot all rows.
                  _series(s.rescuerVitals,
                          (v) => v.timestampSec,
                          (v) => v.fatigueScore.toDouble()),
                  _kWarning),
            ],
            minY: 0, maxY: 200, yTickInterval: 50,
            yLabel: (v) => v.toStringAsFixed(0),
            legend: [
              _LegendItem('Heart Rate (BPM)', _kError),
              _LegendItem('Estimated Fatigue Score (0-100)', _kWarning),
            ],
            plotHeight: 90,
          ),
          pw.SizedBox(height: 20),
        ],

        // ── 12. Detailed metrics (appendix — full numerical breakdown) ────
        _sectionTitle(robotoBold, 'Detailed Metrics'),
        pw.SizedBox(height: 8),
        _twoColumnMetrics(robotoMedium, roboto, s, depthMin, depthMax),
        pw.SizedBox(height: 20),

// ── 12b. Session Timeline ──────────────────────────────────────────
        pw.NewPage(),
        _sectionTitle(robotoBold, 'Session Timeline'),
        pw.SizedBox(height: 4),
        pw.Text(
            'Chronological log of session events — '
                'starts, pauses, ventilations, pulse checks, fatigue, and end.',
            style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
        pw.SizedBox(height: 10),
        pw.SizedBox(
          width: double.infinity,
          child: _buildSessionTimeline(robotoBold, robotoMedium, roboto, s),
        ),
        pw.SizedBox(height: 20),

// ── Ventilation table ──────────────────────────────────────────────
        if (s.ventilations.isNotEmpty) ...[
          _sectionTitle(robotoBold, 'Ventilation Windows'),
          pw.SizedBox(height: 8),
          _ventilationTable(robotoBold, robotoMedium, roboto, s.ventilations),
          pw.SizedBox(height: 20),
        ],

        // ── Pulse check table ──────────────────────────────────────────────
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
                style: pw.TextStyle(font: roboto, fontSize: 10,
                    color: _kTextPrimary)),
          ),
        ],
      ],
    ));

    return doc.save();
  }


  static pw.Widget _buildVerdictCard(
      pw.Font bold, pw.Font medium, pw.Font font,
      double depthPct, double ratePct,
      double recoilPct, double posturePct,
      double depthMin, double depthMax) {

    final dims = <(String, double, String)>[
      ('Depth',   depthPct,
      'Aim for ${depthMin.toStringAsFixed(0)}–${depthMax.toStringAsFixed(0)} cm — '
          'press firmly and let the chest fully rebound.'),
      ('Rate',    ratePct,
      'Aim for 100–120 BPM — try a metronome or sing '
          '"Stayin\' Alive" at 1 beat per compression.'),
      ('Recoil',  recoilPct,
      'Release fully between compressions — lift your '
          'palms an extra centimetre before pressing down again.'),
      ('Posture', posturePct,
      'Keep shoulders directly over your wrists. '
          'Lock your elbows and use your bodyweight, not your arms.'),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    final weakest = dims.first;
    final color   = _pctColor(weakest.$2 / 100);
    final bg      = color.shade(0.85);

    if (weakest.$2 >= 80) {
      // Strong all-round — encouragement instead
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: pw.BoxDecoration(
          color: _kSuccessLight,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Row(children: [
          pw.Container(width: 4, height: 32,
              decoration: pw.BoxDecoration(color: _kSuccess,
                  borderRadius: pw.BorderRadius.circular(2))),
          pw.SizedBox(width: 10),
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Strong performance across all metrics',
                  style: pw.TextStyle(font: bold, fontSize: 11, color: _kSuccess)),
              pw.SizedBox(height: 2),
              pw.Text('Consistent quality — keep practising at this level.',
                  style: pw.TextStyle(font: font, fontSize: 9, color: _kTextSecond)),
            ],
          )),
        ]),
      );
    }

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(width: 4, height: 44,
            decoration: pw.BoxDecoration(color: color,
                borderRadius: pw.BorderRadius.circular(2))),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              pw.Text('What to work on next: ',
                  style: pw.TextStyle(font: bold, fontSize: 11, color: _kTextPrimary)),
              pw.Text('${weakest.$1} (${weakest.$2.toStringAsFixed(0)}%)',
                  style: pw.TextStyle(font: bold, fontSize: 11, color: color)),
            ]),
            pw.SizedBox(height: 3),
            pw.Text(weakest.$3,
                style: pw.TextStyle(font: font, fontSize: 9, color: _kTextSecond)),
          ],
        )),
      ]),
    );
  }

  static pw.Widget _buildMethodologyBox(pw.Font font, pw.Font bold) {
    pw.Widget item(String k, String v) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.RichText(text: pw.TextSpan(children: [
        pw.TextSpan(text: '$k  ',
            style: pw.TextStyle(font: bold, fontSize: 8,
                color: _kTextPrimary)),
        pw.TextSpan(text: v,
            style: pw.TextStyle(font: font, fontSize: 8,
                color: _kTextSecond)),
      ])),
    );
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _kBrandLight,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('How to read this report',
              style: pw.TextStyle(font: bold, fontSize: 9,
                  color: _kBrandBlue)),
          pw.SizedBox(height: 6),
          item('Target band',
              'Green shaded region on each chart = AHA-recommended range.'),
          item('Depth',
              '5–6 cm adult · 4–5 cm pediatric. Rate 100–120 min⁻¹.'),
          item('X-axis',
              'Elapsed session time (m:ss) from first compression.'),
          item('Recoil',
              '% of compressions with full chest release between presses.'),
          item('Hands-on (CCF)',
              '% of session time actively compressing (AHA target ≥ 80%).'),
        ],
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — MULTI SESSION
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildMultiSessionPdf(
      List<SessionSummary> sessions, {
        String? username,
        List<SessionDetail?>? details,
      }) async {

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

    final avgGrade   = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a + b)
        / trainingSessions.length;
    final bestGrade  = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);
    final worstGrade = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a < b ? a : b);

    final trendDelta = trainingSessions.length >= 2
        ? trainingSessions.last.totalGrade - trainingSessions.first.totalGrade
        : 0.0;

    final avgCCF = trainingSessions.isEmpty ? 0.0
        : trainingSessions.map((s) => s.handsOnRatio).reduce((a, b) => a + b)
        / trainingSessions.length;

    final roscCount = emergencySessions.where((s) => s.pulseDetectedFinal).length;

    final sortedByDate = [...sessions]
      ..sort((a, b) => (a.sessionStart ?? DateTime(2000))
          .compareTo(b.sessionStart ?? DateTime(2000)));
    final dateRange = sortedByDate.isEmpty ? ''
        : '${sortedByDate.first.dateFormatted} - ${sortedByDate.last.dateFormatted}';

    // ── Slot colours (mirrors compare screen, derived from AppColors) ──────
    final slotColors = [
      _pdf(AppColors.primary),      // brand blue  — slot 1
      _pdf(AppColors.compareSlot2), // deep orange — slot 2
      _pdf(AppColors.compareSlot3), // teal        — slot 3
      _pdf(AppColors.compareSlot4), // amber       — slot 4
    ];

    doc.addPage(pw.MultiPage(
      maxPages: 100,
      pageTheme: pw.PageTheme(
        theme:      theme,
        pageFormat: PdfPageFormat.a4,
        margin:     const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
        buildBackground: (ctx) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _kBgGrey),
        ),
      ),
        header: (ctx) => _pageHeader(
          robotoBold, robotoMedium,
          title:    'CPR Session History Report',
          subtitle: '$dateRange  ·  ${sessions.length} sessions',
          username: username,
          pills: [
            if (sessions.any((x) => x.scenario != 'pediatric'))
              _HeaderPillSpec('ADULT', _kBrandBlue, _kAdultBg),
            if (sessions.any((x) => x.scenario == 'pediatric'))
              _HeaderPillSpec('PEDIATRIC', _kPediatric, _kPediatricBg),
            if (sessions.any((x) => x.isNoFeedback))
              _HeaderPillSpec('NO FEEDBACK', _kNoFeedback, _kNoFeedbackBg),
          ],
        ),
      footer: (ctx) => _pageFooter(roboto, ctx),
      build: (ctx) => [

        // ── Comparison hero — score rings per slot ─────────────────────────
        _buildCompareHero(robotoBold, robotoMedium, roboto, sessions, slotColors),
        pw.SizedBox(height: 12),

// ── Slot legend with date + mode ───────────────────────────────────
        _buildSlotLegend(robotoBold, robotoMedium, roboto, sessions, slotColors),
        pw.SizedBox(height: 20),

        // ── Trend banner (kept — useful in comparison too) ─────────────────
        if (trainingSessions.length >= 2) ...[
          _buildTrendBannerCard(robotoBold, robotoMedium, roboto,
              trainingSessions, trendDelta, avgGrade, bestGrade, worstGrade),
          pw.SizedBox(height: 20),
        ],

// ── Comparison metrics table ───────────────────────────────────────
        _sectionTitle(robotoBold, 'Side-by-Side Metrics'),
        pw.SizedBox(height: 4),
        pw.Text(
            'Every key metric, slot-by-slot. The best value in each row is highlighted.',
            style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
        pw.SizedBox(height: 10),
        _buildComparisonMetricsTable(robotoBold, robotoMedium, roboto,
            sessions, details, slotColors),
        pw.SizedBox(height: 20),

// ── Performance radar — polygon per slot ───────────────────────────
        if (sessions.any((s) => s.isTraining)) ...[
          _sectionTitle(robotoBold, 'Performance Profile'),
          pw.SizedBox(height: 4),
          pw.Text(
              'Each axis = % of compressions in target. '
                  'Bigger polygon = stronger session. '
                  'Compare shapes to see where each session is strong vs weak.',
              style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
          pw.SizedBox(height: 10),
          _buildRadarBarTable(robotoBold, robotoMedium, roboto,
              sessions, slotColors),
          pw.SizedBox(height: 20),
        ],

// ── Page break before chart-heavy section ──────────────────────────
        pw.NewPage(),

// ── Overlaid charts ────────────────────────────────────────────────
        _sectionTitle(robotoBold, 'Compression Depth Comparison'),
        pw.SizedBox(height: 10),
        _buildOverlaidComparisonChart(
          font: roboto, fontBold: robotoBold,
          title: 'Depth Over Time',
          subtitle: 'All sessions overlaid on the same time axis.',
          caption: 'Green band = target depth. '
              'Drift downward across the session indicates fatigue.',
          sessions: sessions, details: details, slotColors: slotColors,
          yExtractor: (c) => c.depth,
          minY: 0, maxY: 9, yTickInterval: 3,
          yLabel: (v) => v.toStringAsFixed(0),
          band: _ChartBand(
              sessions.first.scenario == 'pediatric' ? 4.0 : 5.0,
              sessions.first.scenario == 'pediatric' ? 5.0 : 6.0,
              _kSuccess.shade(0.12), _kSuccess.shade(0.5)),
        ),
        pw.SizedBox(height: 16),

        _sectionTitle(robotoBold, 'Compression Rate Comparison'),
        pw.SizedBox(height: 10),
        _buildOverlaidComparisonChart(
          font: roboto, fontBold: robotoBold,
          title: 'Rate Over Time',
          subtitle: null,
          caption: 'Green band = target rate (100–120 BPM).',
          sessions: sessions, details: details, slotColors: slotColors,
          yExtractor: (c) => c.instantaneousRate > 0
              ? c.instantaneousRate : c.frequency,
          minY: 60, maxY: 160, yTickInterval: 20,
          yLabel: (v) => v.toStringAsFixed(0),
          band: _ChartBand(100, 120,
              _kSuccess.shade(0.12), _kSuccess.shade(0.5)),
        ),
        pw.SizedBox(height: 16),

// Force — only if any session has force data
        if (details != null && details.any((d) =>
        d != null && d.compressions.any((c) => c.force > 0))) ...[
          _sectionTitle(robotoBold, 'Force Comparison'),
          pw.SizedBox(height: 10),
          _buildOverlaidComparisonChart(
            font: roboto, fontBold: robotoBold,
            title: 'Force Over Time',
            subtitle: null,
            caption: 'Red dashed line = 600 N injury threshold.',
            sessions: sessions, details: details, slotColors: slotColors,
            yExtractor: (c) => c.force,
            minY: 0, maxY: 700, yTickInterval: 100,
            yLabel: (v) => v.toStringAsFixed(0),
            guides: [_ChartGuide(600, _kError.shade(0.6))],
          ),
          pw.SizedBox(height: 16),
        ],

// Phase comparison (kept — useful here)
        if (details != null && details.any((d) => d != null &&
            d.compressions.length >= 9)) ...[
          _sectionTitle(robotoBold, 'Phase Breakdown'),
          pw.SizedBox(height: 4),
          pw.Text(
              'Early / mid / late depth — flat across thirds = consistent stamina.',
              style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
          pw.SizedBox(height: 10),
          _buildMultiPhaseTable(robotoBold, robotoMedium, roboto,
              sessions, details, slotColors),
          pw.SizedBox(height: 20),
        ],

        // ── Session journey timeline ───────────────────────────────────────
        _sectionTitle(robotoBold, 'Training Journey'),
        pw.SizedBox(height: 4),
        pw.Text(
            'Chronological view of every session — '
                'dot colour = grade, delta = change vs previous training session.',
            style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
        pw.SizedBox(height: 12),
        _buildMultiSessionTimeline(robotoBold, robotoMedium, roboto, sessions),
        pw.SizedBox(height: 20),

        // ── All sessions table (kept as data appendix) ─────────────────────
        _sectionTitle(robotoBold, 'All Sessions (Numerical)'),
        pw.SizedBox(height: 4),
        pw.Text(
            'Full numerical breakdown of every session — useful for export and analysis.',
            style: pw.TextStyle(font: roboto, fontSize: 8, color: _kTextSecond)),
        pw.SizedBox(height: 10),
        _buildAllSessionsTable(robotoBold, robotoMedium, roboto,
            sessions, slotColors),
      ],
    ));

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — CERTIFICATE
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


  static pw.Widget _headerPill(pw.Font bold, String label,
      PdfColor color, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(999),
      ),
      child: pw.Text(label, style: pw.TextStyle(
          font: bold, fontSize: 8.5, color: color, letterSpacing: 0.3)),
    );
  }
  
  // ── Page header ────────────────────────────────────────────────────────────

  static pw.Widget _pageHeader(
      pw.Font bold, pw.Font medium, {
        required String title,
        required String subtitle,
        String?   username,
        int?      sessionNumber,
        String?   note,
        List<_HeaderPillSpec> pills = const [],
      }) {

    // pills built outside table so pw.Row is never inside a table cell
    final pillsWidget = pw.Wrap(
      spacing: 5,
      runSpacing: 4,
      children: [
        for (final p in pills)
          _headerPill(bold, p.label, p.color, p.bg),
      ],
    );

    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [

        // Line 1 — centred title
        pw.Center(
          child: pw.Text(title,
              style: pw.TextStyle(
                  font: bold, fontSize: 20, color: _kTextPrimary)),
        ),
        pw.SizedBox(height: 8),

        // Line 2 — date/time left | username right
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(children: [
              pw.Text(subtitle,
                  style: pw.TextStyle(
                      font: medium, fontSize: 9, color: _kTextSecond)),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(username ?? '',
                    style: pw.TextStyle(
                        font: bold, fontSize: 9, color: _kTextPrimary)),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 3),

        // Line 3 — pills left | ID right
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(children: [
              pillsWidget,
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: sessionNumber != null
                    ? pw.Text('Session #$sessionNumber',
                    style: pw.TextStyle(
                        font: medium, fontSize: 9, color: _kTextDisabled))
                    : pw.SizedBox(),
              ),
            ]),
          ],
        ),

        // Line 4 — note
        if (note != null && note.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(10),
              1: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                children: [
                  pw.Container(
                    width: 2,
                    height: 10,
                    margin: const pw.EdgeInsets.only(top: 1),
                    decoration: pw.BoxDecoration(
                      color: _kDivider,
                      borderRadius: pw.BorderRadius.circular(1),
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 6),
                    child: pw.Text(
                      note,
                      style: pw.TextStyle(
                        font: medium,
                        fontSize: 9,
                        color: _kTextSecond,
                        lineSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],

        pw.SizedBox(height: 10),
        pw.Container(height: 1, color: _kDivider),
        pw.SizedBox(height: 12),
      ],
    );
  }

// ── Pill helper ────────────────────────────────────────────────────────────────
  static pw.Widget _pill(pw.Font bold, String label, PdfColor color, PdfColor bg) {
    return pw.ClipRRect(
      horizontalRadius: 999,
      verticalRadius: 999,
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        color: bg,
        child: pw.Text(label,
            style: pw.TextStyle(font: bold, fontSize: 8, color: color)),
      ),
    );
  }
  // ── Page footer ────────────────────────────────────────────────────────────

  static pw.Widget _pageFooter(pw.Font font, pw.Context ctx) {
    return pw.Container(
      decoration: pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _kDivider, width: 1))),
      padding: const pw.EdgeInsets.only(top: 8),
      margin:  const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by CPR Assist',
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
        ],
      ),
    );
  }


  static pw.Widget _buildCompareHero(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions, List<PdfColor> slotColors) {

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_kBrandBlue, _kBrandDark],
          begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('COMPARING ${sessions.length} SESSIONS',
              style: pw.TextStyle(font: bold, fontSize: 8,
                  color: _kWhite.shade(0.6), letterSpacing: 1.2)),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < sessions.length; i++)
                pw.Expanded(child: _compareSlotRing(
                    bold, medium, font, sessions[i], slotColors[i], i + 1)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _compareSlotRing(
      pw.Font bold, pw.Font medium, pw.Font font,
      SessionSummary s, PdfColor slotColor, int slotNum) {

    final isEmg     = s.isEmergency;
    final value     = isEmg
        ? (s.pulseChecksPrompted > 0 ? 'CPR' : 'CPR')
        : '${s.totalGrade.toStringAsFixed(0)}%';
    final ringPct   = isEmg ? 0.0 : (s.totalGrade / 100).clamp(0.0, 1.0);
    final ringColor = isEmg ? _kEmgGreen : slotColor;

    return pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
      // Slot number tag
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: pw.BoxDecoration(
          color: slotColor,
          borderRadius: pw.BorderRadius.circular(99),
        ),
        child: pw.Text('SLOT $slotNum',
            style: pw.TextStyle(font: bold, fontSize: 7,
                color: _kWhite, letterSpacing: 0.5)),
      ),
      pw.SizedBox(height: 8),
      // Ring
      pw.SizedBox(
        width: 70, height: 70,
        child: pw.Stack(alignment: pw.Alignment.center, children: [
          pw.SizedBox(
            width: 70, height: 70,
            child: pw.CustomPaint(painter: (c, size) {
              const pi = 3.14159265;
              final cx = size.x / 2;
              final cy = size.y / 2;
              final rx = size.x / 2 - 4;
              final ry = size.y / 2 - 4;
              c.saveContext();
              c.setStrokeColor(_kWhite.shade(0.2));
              c.setLineWidth(6);
              c.drawEllipse(cx, cy, rx, ry);
              c.strokePath();
              c.restoreContext();
              final steps = (ringPct * 60).round().clamp(0, 60);
              if (steps > 0) {
                c.saveContext();
                c.setStrokeColor(ringColor);
                c.setLineWidth(6);
                double angle(int s) => -pi / 2 + s * (2 * pi / 60);
                c.moveTo(cx + rx * math.cos(angle(0)),
                    cy + ry * math.sin(angle(0)));
                for (int i = 1; i <= steps; i++) {
                  c.lineTo(cx + rx * math.cos(angle(i)),
                      cy + ry * math.sin(angle(i)));
                }
                c.strokePath();
                c.restoreContext();
              }
            }),
          ),
          pw.Text(value,
              style: pw.TextStyle(font: bold, fontSize: 14,
                  color: _kWhite)),
        ]),
      ),
      pw.SizedBox(height: 6),
      pw.Text(isEmg ? 'EMERGENCY' : 'TRAINING',
          style: pw.TextStyle(font: bold, fontSize: 6,
              color: _kWhite.shade(0.7), letterSpacing: 0.6)),
    ]);
  }

  static pw.Widget _buildSlotLegend(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions, List<PdfColor> slotColors) {

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kWhite,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: pw.Row(children: [
        for (int i = 0; i < sessions.length; i++) ...[
          if (i > 0) pw.Container(width: 0.5, height: 28, color: _kDivider),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8),
              child: pw.Row(children: [
                pw.Container(width: 10, height: 10,
                    decoration: pw.BoxDecoration(
                        color: slotColors[i], shape: pw.BoxShape.circle)),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SLOT ${i + 1}',
                          style: pw.TextStyle(font: bold, fontSize: 6,
                              color: _kTextDisabled, letterSpacing: 0.5)),
                      pw.SizedBox(height: 1),
                      pw.Text(sessions[i].dateFormatted,
                          style: pw.TextStyle(font: medium, fontSize: 9,
                              color: _kTextPrimary)),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        '${sessions[i].isEmergency ? 'Emergency' : 'Training'}'
                            ' · '
                            '${sessions[i].scenario == 'pediatric'
                            ? 'Pediatric' : 'Adult'}',
                        style: pw.TextStyle(font: font, fontSize: 7,
                            color: _kTextSecond),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Training hero — grade ring + 4 sub-rings ───────────────────────────────

  static pw.Widget _buildTrainingHero(
      pw.Font bold, pw.Font medium, pw.Font font,
      double grade, double depthPct, double ratePct,
      double recoilPct, double posturePct) {

    final gradeColor = _gradeColor(grade);
    final label      = grade >= 90 ? 'Outstanding!'
        : grade >= 75 ? 'Great work!'
        : grade >= 55 ? 'Keep it up!'
        : 'Keep practising!';

    // Build dim list for verdict (still uses 4 dims for accuracy)
    final dims = <(String, double, String)>[
      ('Depth',   depthPct,
      'Press firmly — aim for the centre of the target depth band.'),
      ('Rate',    ratePct,
      'Pace yourself — 100–120 BPM, think "Stayin\' Alive".'),
      ('Recoil',  recoilPct,
      'Release fully between compressions — lift your palms a centimetre.'),
      ('Posture', posturePct,
      'Lock elbows, shoulders over wrists. Use bodyweight, not arms.'),
    ]..sort((a, b) => a.$2.compareTo(b.$2));

    final weakest   = dims.first;
    final allStrong = weakest.$2 >= 80;
    final verdict   = allStrong
        ? 'Consistent across all metrics — strong overall performance.'
        : 'Work on next: ${weakest.$1} (${weakest.$2.toStringAsFixed(0)}%) — ${weakest.$3}';

    // ── Big grade ring (centred) ───────────────────────────────────────────
    final mainRing = pw.SizedBox(
      width: 108, height: 108,
      child: pw.Stack(alignment: pw.Alignment.center, children: [
        pw.SizedBox(
          width: 108, height: 108,
          child: pw.CustomPaint(painter: (c, size) {
            const pi = 3.14159265;
            final cx = size.x / 2;
            final cy = size.y / 2;
            final rx = size.x / 2 - 6;
            final ry = size.y / 2 - 6;
            // Background ring
            c.saveContext();
            c.setStrokeColor(_kWhite.shade(0.18));
            c.setLineWidth(9);
            c.drawEllipse(cx, cy, rx, ry);
            c.strokePath();
            c.restoreContext();
            // Grade arc
            final steps = (grade / 100 * 72).round().clamp(0, 72);
            if (steps > 0) {
              c.saveContext();
              c.setStrokeColor(gradeColor);
              c.setLineWidth(9);
              double angle(int s) => -pi / 2 + s * (2 * pi / 72);
              c.moveTo(cx + rx * math.cos(angle(0)),
                  cy + ry * math.sin(angle(0)));
              for (int i = 1; i <= steps; i++) {
                c.lineTo(cx + rx * math.cos(angle(i)),
                    cy + ry * math.sin(angle(i)));
              }
              c.strokePath();
              c.restoreContext();
            }
          }),
        ),
        pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text('${grade.toStringAsFixed(0)}%',
              style: pw.TextStyle(font: bold, fontSize: 28, color: _kWhite)),
          pw.SizedBox(height: 2),
          pw.Text(label,
              style: pw.TextStyle(font: medium, fontSize: 8,
                  color: _kWhite.shade(0.8)),
              textAlign: pw.TextAlign.center),
        ]),
      ]),
    );

    // ── Sub-ring builder (3 sub-rings: DEPTH / RATE / RECOIL) ─────────────
    pw.Widget subRing(String label, double pct) {
      final pctInt = pct.round().clamp(0, 100);
      final col    = _pctColor(pct / 100);
      return pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(
            width: 56, height: 56,
            child: pw.Stack(alignment: pw.Alignment.center, children: [
              pw.SizedBox(
                width: 56, height: 56,
                child: pw.CustomPaint(painter: (c, size) {
                  const pi = 3.14159265;
                  final cx = size.x / 2;
                  final cy = size.y / 2;
                  final rx = size.x / 2 - 4;
                  final ry = size.y / 2 - 4;
                  // bg
                  c.saveContext();
                  c.setStrokeColor(_kWhite.shade(0.18));
                  c.setLineWidth(5);
                  c.drawEllipse(cx, cy, rx, ry);
                  c.strokePath();
                  c.restoreContext();
                  // filled arc
                  final steps = (pct / 100 * 48).round().clamp(0, 48);
                  if (steps > 0) {
                    c.saveContext();
                    c.setStrokeColor(col);
                    c.setLineWidth(5);
                    double angle(int s) => -pi / 2 + s * (2 * pi / 48);
                    c.moveTo(cx + rx * math.cos(angle(0)),
                        cy + ry * math.sin(angle(0)));
                    for (int i = 1; i <= steps; i++) {
                      c.lineTo(cx + rx * math.cos(angle(i)),
                          cy + ry * math.sin(angle(i)));
                    }
                    c.strokePath();
                    c.restoreContext();
                  }
                }),
              ),
              pw.Text('$pctInt%',
                  style: pw.TextStyle(font: bold, fontSize: 11, color: _kWhite)),
            ]),
          ),
          pw.SizedBox(height: 5),
          pw.Text(label,
              style: pw.TextStyle(font: medium, fontSize: 8,
                  color: _kWhite.shade(0.75),
                  letterSpacing: 0.6)),
        ],
      );
    }

    // ── Compose ───────────────────────────────────────────────────────────
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [_kBrandBlue, _kBrandDark],
          begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Main grade ring centred
          mainRing,
          pw.SizedBox(height: 18),
          // 3 sub-rings centred row
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              subRing('DEPTH',  depthPct),
              pw.SizedBox(width: 28),
              subRing('RATE',   ratePct),
              pw.SizedBox(width: 28),
              subRing('RECOIL', recoilPct),
            ],
          ),
          pw.SizedBox(height: 16),
          // Divider
          pw.Container(height: 1, color: _kWhite.shade(0.2)),
          pw.SizedBox(height: 10),
          // Verdict line
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Container(width: 3, height: 28,
                decoration: pw.BoxDecoration(
                    color: allStrong ? _kSuccess : _pctColor(weakest.$2 / 100),
                    borderRadius: pw.BorderRadius.circular(1.5))),
            pw.SizedBox(width: 9),
            pw.Expanded(
              child: pw.Text(verdict,
                  style: pw.TextStyle(font: medium, fontSize: 9,
                      color: _kWhite.shade(0.92), lineSpacing: 2)),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Emergency hero — ROSC banner + 4 stat pills ───────────────────────────

  static pw.Widget _buildEmergencyHero(
      pw.Font bold, pw.Font medium, pw.Font font, SessionDetail s) {

    final rosc        = s.pulseDetectedFinal;
    final hadChecks   = s.pulseChecks.isNotEmpty;
    final outcomeText = rosc ? 'ROSC DETECTED'
        : hadChecks ? 'NO ROSC'
        : 'NO PULSE DATA';
    final outcomeColor = rosc ? _kEmgGreen : _kError;
    final outcomeBg    = rosc ? _kEmgGreenBg : _kErrorLight;

    final lastCheck = s.pulseChecks.isEmpty ? null : s.pulseChecks.last;

    pw.Widget statPill(String label, String value, PdfColor color) =>
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: pw.BoxDecoration(
              color: _kWhite.shade(0.08),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: _kWhite.shade(0.15), width: 0.5),
            ),
            child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
              pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 15,
                  color: color), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 2),
              pw.Text(label, style: pw.TextStyle(font: font, fontSize: 7,
                  color: _kWhite.shade(0.6)), textAlign: pw.TextAlign.center),
            ]),
          ),
        );

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: _kBrandDark,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Outcome banner row
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: pw.BoxDecoration(
              color: outcomeBg.shade(0.25),
              borderRadius: const pw.BorderRadius.only(
                topLeft:  pw.Radius.circular(12),
                topRight: pw.Radius.circular(12),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 10, height: 10,
                  decoration: pw.BoxDecoration(
                      color: outcomeColor, shape: pw.BoxShape.circle),
                ),
                pw.SizedBox(width: 10),
                pw.Text(outcomeText,
                    style: pw.TextStyle(font: bold, fontSize: 16,
                        color: outcomeColor)),
                pw.Spacer(),
                pw.Text('Emergency Session Record',
                    style: pw.TextStyle(font: medium, fontSize: 8,
                        color: _kWhite.shade(0.5))),
              ],
            ),
          ),
          // Stat pills row
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: pw.Row(
              children: [
                statPill('Time to 1st Comp.',
                    s.timeToFirstCompression > 0
                        ? '${s.timeToFirstCompression.toStringAsFixed(1)}s'
                        : '—',
                    s.timeToFirstCompression <= 10 && s.timeToFirstCompression > 0
                        ? _kSuccess : _kWarning),
                statPill('Compressions', '${s.compressionCount}', _kWhite),
                statPill('Duration',     s.durationFormatted,    _kWhite),
                statPill('Pulse Checks', '${s.pulseChecksPrompted}', _kWhite),
                // Add a final compression count + pulse outcome already shown above.
                // Now add patient vitals if any.
                if (s.patientSpO2LastCheck != null)
                  statPill('Patient SpO₂',
                      '${s.patientSpO2LastCheck!.toStringAsFixed(0)}%',
                      s.patientSpO2LastCheck! >= 95 ? _kSuccess
                          : s.patientSpO2LastCheck! >= 85 ? _kWarning : _kError),
                if (s.patientTemperature != null)
                  statPill('Patient Temp',
                      '${s.patientTemperature!.toStringAsFixed(1)} °C', _kWhite)

                else if (lastCheck != null && lastCheck.detectedBpm > 0)
                  statPill('Detected BPM',
                      '${lastCheck.detectedBpm.toStringAsFixed(0)}', _kSuccess)
                else
                  statPill('CCF', '${(s.handsOnRatio * 100).round()}%', _kWhite),
              ],
            ),
          ),
        ],
      ),
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
                    '${s.patientTemperature!.toStringAsFixed(1)} °C', 'Patient Temp'),
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
                  border: isLast ? null : pw.Border(
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


// ── Quality bar table — horizontal proportion bars per metric ──────────────

  static pw.Widget _buildQualityBarTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      SessionDetail s, double n,
      double depthMin, double depthMax) {

    // Each entry: [label, target string, pct 0-100]
    final rows = <(String, String, double, PdfColor)>[
      ('Depth in target',
      '${depthMin.toStringAsFixed(0)}–${depthMax.toStringAsFixed(0)} cm',
      n > 0 ? s.correctDepth / n * 100 : 0,
      _pctColor(n > 0 ? s.correctDepth / n : 0)),
      ('Rate in target',
      '100–120 BPM',
      n > 0 ? s.correctFrequency / n * 100 : 0,
      _pctColor(n > 0 ? s.correctFrequency / n : 0)),
      ('Full recoil',
      'No leaning',
      n > 0 ? s.correctRecoil / n * 100 : 0,
      _pctColor(n > 0 ? s.correctRecoil / n : 0)),
      ('Correct posture',
      '≤15° align / ≤10° flex',
      n > 0 ? s.correctPosture / n * 100 : 0,
      _pctColor(n > 0 ? s.correctPosture / n : 0)),
      ('Depth + rate',
      'Both correct',
      n > 0 ? s.depthRateCombo / n * 100 : 0,
      _pctColor(n > 0 ? s.depthRateCombo / n : 0)),
      if (s.ventilationCount > 0)
        ('Ventilation compliance',
        '30:2 timing',
        s.ventilationCompliance,
        _pctColor(s.ventilationCompliance / 100)),
    ];
    rows.sort((a, b) => a.$3.compareTo(b.$3));

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kBgGrey,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _kDivider, width: 0.5),
      ),
      child: pw.Column(
        children: rows.asMap().entries.map((entry) {
          final i = entry.key;
          final (label, target, pct, color) = entry.value;
          final isLast = i == rows.length - 1;
          final pctClamped = pct.clamp(0.0, 100.0);
          final fillFlex   = pctClamped.round().clamp(1, 99);
          final emptyFlex  = (100 - fillFlex).clamp(1, 99);

          return pw.Column(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: pw.Row(
                children: [
                  // Label + target
                  pw.SizedBox(
                    width: 142,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(label,
                            style: pw.TextStyle(font: medium, fontSize: 9,
                                color: _kTextPrimary)),
                        pw.SizedBox(height: 1),
                        pw.Text(target,
                            style: pw.TextStyle(font: font, fontSize: 7,
                                color: _kTextDisabled)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  // Bar
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Stack(children: [
                          pw.Container(
                            height: 8,
                            decoration: pw.BoxDecoration(
                              color: _kDivider,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                          ),
                          pw.Row(children: [
                            pw.Expanded(
                              flex: fillFlex,
                              child: pw.Container(
                                height: 8,
                                decoration: pw.BoxDecoration(
                                  color: color,
                                  borderRadius: pw.BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            pw.Expanded(
                              flex: emptyFlex,
                              child: pw.SizedBox(height: 8),
                            ),
                          ]),
                        ]),
                        pw.SizedBox(height: 2),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('0%', style: pw.TextStyle(font: font,
                                fontSize: 6, color: _kTextDisabled)),
                            pw.Text('${pct.toStringAsFixed(0)}%',
                                style: pw.TextStyle(font: bold, fontSize: 8,
                                    color: color)),
                            pw.Text('100%', style: pw.TextStyle(font: font,
                                fontSize: 6, color: _kTextDisabled)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!isLast)
              pw.Container(height: 0.5, color: _kDivider),
          ]);
        }).toList(),
      ),
    );
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

  // ── Metric tile (single) ───────────────────────────────────────────────────
//
// Layout per tile (white card, brand-blue left accent bar):
//   ┌──┬──────────────────────────────┐
//   │  │ LABEL                        │
//   │  │ VALUE • status dot           │
//   │  │ ───────●──── (zone bar)      │
//   │  │ target: 5–6 cm               │
//   └──┴──────────────────────────────┘

  static pw.Widget _metricTile({
    required pw.Font   bold,
    required pw.Font   medium,
    required pw.Font   font,
    required String    label,
    required String    value,
    required PdfColor  statusColor,
    required String    target,
    double?            currentVal,   // value position on zone bar
    double?            zoneMin,      // bar full range
    double?            zoneMax,
    double?            targetMin,    // target band within zone
    double?            targetMax,
    bool               isAlert = false,
  }) {
    return pw.SizedBox(
        height: 64,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            color: _kWhite,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        // Left accent bar
        pw.Container(width: 3,
            decoration: pw.BoxDecoration(
                color: statusColor,
                borderRadius: const pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(8),
                    bottomLeft: pw.Radius.circular(8)))),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Label row
                pw.Text(label.toUpperCase(),
                    style: pw.TextStyle(font: medium, fontSize: 7,
                        color: _kTextDisabled, letterSpacing: 0.4)),
                pw.SizedBox(height: 2),
                // Value + status dot
                pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(value,
                          style: pw.TextStyle(font: bold, fontSize: 15,
                              color: isAlert ? _kError : _kTextPrimary)),
                      pw.SizedBox(width: 6),
                      pw.Container(width: 6, height: 6,
                          decoration: pw.BoxDecoration(
                              color: statusColor, shape: pw.BoxShape.circle)),
                    ]),
                pw.SizedBox(height: 6),
                // Zone bar (optional)
                if (currentVal != null && zoneMin != null && zoneMax != null)
                  pw.SizedBox(
                    height: 6,
                    child: pw.CustomPaint(painter: (c, size) {
                      // Track
                      c.saveContext();
                      c.setFillColor(_kDivider);
                      c.drawRect(0, 0, size.x, size.y);
                      c.fillPath();
                      c.restoreContext();
                      // Target band
                      if (targetMin != null && targetMax != null) {
                        final range = zoneMax - zoneMin;
                        final tMinX = ((targetMin - zoneMin) / range)
                            .clamp(0.0, 1.0) * size.x;
                        final tMaxX = ((targetMax - zoneMin) / range)
                            .clamp(0.0, 1.0) * size.x;
                        c.saveContext();
                        c.setFillColor(_kSuccess.shade(0.25));
                        c.drawRect(tMinX, 0, tMaxX - tMinX, size.y);
                        c.fillPath();
                        c.restoreContext();
                      }
                      // Current value marker
                      final range = zoneMax - zoneMin;
                      final cx = ((currentVal - zoneMin) / range)
                          .clamp(0.0, 1.0) * size.x;
                      c.saveContext();
                      c.setFillColor(statusColor);
                      c.drawEllipse(cx, size.y / 2, 3.5, 3.5);
                      c.fillPath();
                      c.restoreContext();
                    }),
                  ),
                if (currentVal != null) pw.SizedBox(height: 3),
                pw.Text(target,
                    style: pw.TextStyle(font: font, fontSize: 7,
                        color: _kTextDisabled)),
              ],
            ),
          ),
        ),
      ]),
        ),
    );
  }

// ── Headline metric grid (2 cols × 3 rows = 6 tiles) ───────────────────────

  static pw.Widget _buildMetricGrid(
      pw.Font bold, pw.Font medium, pw.Font font,
      SessionDetail s, double depthMin, double depthMax) {

    final n = s.compressionCount.toDouble();

    // ── Track widget ────────────────────────────────────────────────────────────
    // rangeMin/rangeMax = full axis extents
    // targetMin/targetMax = green zone
    // value = where the dot sits
    // color = dot + value color
    pw.Widget track({
      required double rangeMin,
      required double rangeMax,
      required double targetMin,
      required double targetMax,
      required double value,
      required PdfColor color,
      String? labelMin,
      String? labelMax,
    }) {
      if (value.isNaN || value.isInfinite) return pw.SizedBox();
      if (rangeMax <= rangeMin) return pw.SizedBox();

      final span   = rangeMax - rangeMin;
      final tStart = ((targetMin - rangeMin) / span).clamp(0.0, 1.0);
      final tEnd   = ((targetMax - rangeMin) / span).clamp(0.0, 1.0);
      final dot    = ((value    - rangeMin) / span).clamp(0.0, 1.0);

      const trackH = 5.0;
      const dotD   = 9.0;
      const totalH = dotD;

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (labelMin != null || labelMax != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(labelMin ?? '',
                      style: pw.TextStyle(font: font,
                          fontSize: 8, color: _kTextDisabled)),
                  pw.Text(labelMax ?? '',
                      style: pw.TextStyle(font: font,
                          fontSize: 8, color: _kTextDisabled)),
                ],
              ),
            ),
          pw.SizedBox(
            height: totalH,
            width: double.infinity,
            child: pw.CustomPaint(
              painter: (canvas, size) {
                final w   = size.x;
                final cy  = size.y / 2;

                // Base track
                canvas.saveContext();
                canvas.setFillColor(_kDivider);
                canvas.drawRRect(0, cy - trackH / 2, w, trackH,
                    trackH / 2, trackH / 2);
                canvas.fillPath();
                canvas.restoreContext();

                // Green target zone
                final zx = tStart * w;
                final zw = (tEnd - tStart) * w;
                if (zw > 0) {
                  canvas.saveContext();
                  canvas.setFillColor(_kSuccess.shade(0.25));
                  canvas.drawRRect(zx, cy - trackH / 2, zw, trackH,
                      trackH / 2, trackH / 2);
                  canvas.fillPath();
                  canvas.restoreContext();
                }

                // Dot
                final dx = dot * w;
                canvas.saveContext();
                // white border ring
                canvas.setFillColor(_kBgGrey);
                canvas.drawEllipse(dx, cy, dotD / 2, dotD / 2);
                canvas.fillPath();
                // colored fill
                canvas.setFillColor(color);
                canvas.drawEllipse(dx, cy, (dotD / 2) - 1.5, (dotD / 2) - 1.5);
                canvas.fillPath();
                canvas.restoreContext();
              },
            ),
          ),
        ],
      );
    }

    // ── Tile builder ────────────────────────────────────────────────────────────
    pw.Widget tile({
      required String label,
      required String value,
      required PdfColor valueColor,
      required String target,
      pw.Widget? trackWidget,
    }) =>
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: pw.BoxDecoration(
            color: _kWhite,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: _kDivider, width: 0.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(font: medium, fontSize: 8,
                      color: _kTextDisabled, letterSpacing: 0.4)),
              pw.SizedBox(height: 5),
              pw.Text(value,
                  style: pw.TextStyle(font: bold, fontSize: 20,
                      color: valueColor)),
              pw.SizedBox(height: 2),
              pw.Text(target,
                  style: pw.TextStyle(font: font, fontSize: 8,
                      color: _kTextDisabled)),
              if (trackWidget != null) ...[
                pw.SizedBox(height: 8),
                trackWidget,
              ],
            ],
          ),
        );

    // ── Colors ──────────────────────────────────────────────────────────────────
    // Avg depth
    final depthOk    = s.averageDepth >= depthMin && s.averageDepth <= depthMax;
    final depthHigh  = s.averageDepth > depthMax;
    final depthColor = s.averageDepth == 0 ? _kTextDisabled
        : depthOk   ? _kSuccess
        : depthHigh ? _kError
        : _kWarning;

    // Avg rate
    final rateOk    = s.averageFrequency >= 100 && s.averageFrequency <= 120;
    final rateWarn  = s.averageFrequency > 0 &&
        s.averageFrequency >= 85 && s.averageFrequency <= 135;
    final rateColor = s.averageFrequency == 0 ? _kTextDisabled
        : rateOk   ? _kSuccess
        : rateWarn ? _kWarning
        : _kError;

    // Avg recoil
    final recoilPct   = n > 0 ? (s.correctRecoil / n * 100) : 0.0;
    final recoilColor = _pctColor(recoilPct / 100);

    // Time to first
    final ttf      = s.timeToFirstCompression;
    final ttfColor = ttf <= 0 ? _kTextDisabled
        : ttf <= 10 ? _kSuccess
        : ttf <= 20 ? _kWarning
        : _kError;

    // Unplanned pauses
    final pauseTime  = s.unplannedPauseTime;
    final pauseLimit = AppConstants.maxAcceptablePauseSec;
    final pauseColor = pauseTime <= pauseLimit ? _kSuccess : _kWarning;

    // ── Row helper ───────────────────────────────────────────────────────────────
    pw.Widget row(pw.Widget a, pw.Widget b) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: a),
        pw.SizedBox(width: 10),
        pw.Expanded(child: b),
      ],
    );

    pw.Widget row3(pw.Widget a, pw.Widget b, pw.Widget c) => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: a),
        pw.SizedBox(width: 10),
        pw.Expanded(child: b),
        pw.SizedBox(width: 10),
        pw.Expanded(child: c),
      ],
    );

    // ── Compose ──────────────────────────────────────────────────────────────────
    return pw.Column(children: [
      // Row 1 — duration, compressions, time to first
      row3(
        tile(
          label: 'Duration',
          value: s.durationFormatted,
          valueColor: _kTextPrimary,
          target: 'min : sec',
        ),
        tile(
          label: 'Compressions',
          value: s.compressionCount.toString(),
          valueColor: _kTextPrimary,
          target: 'total',
        ),
        tile(
          label: 'Time to first',
          value: ttf > 0 ? '${ttf.toStringAsFixed(1)}s' : '—',
          valueColor: ttfColor,
          target: 'target < 10s',
          trackWidget: ttf > 0 ? track(
            rangeMin: 0, rangeMax: 30,
            targetMin: 0, targetMax: 10,
            value: ttf.clamp(0.0, 30.0),
            color: ttfColor,
            labelMin: '0s', labelMax: '30s',
          ) : null,
        ),
      ),
      pw.SizedBox(height: 10),

      // Row 2 — avg depth, avg rate, avg recoil
      row3(
        tile(
          label: 'Avg depth',
          value: s.averageDepth > 0
              ? '${s.averageDepth.toStringAsFixed(1)} cm' : '—',
          valueColor: depthColor,
          target: 'target ${depthMin.toStringAsFixed(0)}–${depthMax.toStringAsFixed(0)} cm',
          trackWidget: s.averageDepth > 0 ? track(
            rangeMin: 0, rangeMax: 9,
            targetMin: depthMin, targetMax: depthMax,
            value: s.averageDepth.clamp(0.0, 9.0),
            color: depthColor,
            labelMin: '0', labelMax: '9 cm',
          ) : null,
        ),
        tile(
          label: 'Avg rate',
          value: s.averageFrequency > 0
              ? '${s.averageFrequency.round()} BPM' : '—',
          valueColor: rateColor,
          target: 'target 100–120 BPM',
          trackWidget: s.averageFrequency > 0 ? track(
            rangeMin: 60, rangeMax: 160,
            targetMin: 100, targetMax: 120,
            value: s.averageFrequency.clamp(60.0, 160.0),
            color: rateColor,
            labelMin: '60', labelMax: '160',
          ) : null,
        ),
        tile(
          label: 'Avg recoil',
          value: n > 0 ? '${recoilPct.toStringAsFixed(0)}%' : '—',
          valueColor: recoilColor,
          target: 'target ≥ 80%',
          trackWidget: n > 0 ? track(
            rangeMin: 0, rangeMax: 100,
            targetMin: 80, targetMax: 100,
            value: recoilPct.clamp(0.0, 100.0),
            color: recoilColor,
            labelMin: '0%', labelMax: '100%',
          ) : null,
        ),
      ),
      pw.SizedBox(height: 10),

      // Full-width — unplanned pauses
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: pw.BoxDecoration(
          color: _kWhite,
          borderRadius: pw.BorderRadius.circular(10),
          border: pw.Border.all(color: _kDivider, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('UNPLANNED PAUSES',
                style: pw.TextStyle(font: medium, fontSize: 8,
                    color: _kTextDisabled, letterSpacing: 0.4)),
            pw.SizedBox(height: 5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                    pauseTime > 0 ? '${pauseTime.toStringAsFixed(1)}s' : '0s',
                    style: pw.TextStyle(font: bold, fontSize: 20,
                        color: pauseColor)),
                pw.SizedBox(width: 8),
                pw.Text(
                    'total · ${s.unplannedPauseCount}× · target < ${pauseLimit.toStringAsFixed(0)}s',
                    style: pw.TextStyle(font: font, fontSize: 8,
                        color: _kTextDisabled)),
              ],
            ),
            pw.SizedBox(height: 8),
            track(
              rangeMin: 0, rangeMax: 15,
              targetMin: 0, targetMax: pauseLimit,
              value: pauseTime.clamp(0.0, 15.0),
              color: pauseColor,
              labelMin: '0s', labelMax: '15s',
            ),
          ],
        ),
      ),
    ]);
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
              font: medium, fontSize: 7, color: _kBrandBlue,
              letterSpacing: 0.6)),
        ),
        pw.Table(
          border: pw.TableBorder(
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
                      style: pw.TextStyle(font: medium, fontSize: 8,
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
      border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5)),
      columnWidths: {
        0: const pw.FixedColumnWidth(28),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FixedColumnWidth(60),  // was index 3 — Duration
        3: const pw.FixedColumnWidth(52),  // was index 4 — Compliant
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _kBrandDark),
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
                    child: pw.Text(v.compliant ? '✓' : 'x',
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
    final classColors = [_kError, _kWarning, _kSuccess];
    final classBgs    = [_kErrorLight, _kWarningLight, _kSuccessLight];

    return pw.Column(children: [
      pw.Table(
        border: pw.TableBorder(
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
            decoration: pw.BoxDecoration(color: _kBrandDark),
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
          '${s.patientTemperature!.toStringAsFixed(1)} °C', _kTextPrimary));
    if (patSpO2 != null)
      patientItems.add(_Metric('Patient SpO₂ (best)',
          '${patSpO2.toStringAsFixed(0)}%', _kTextPrimary));
    if (s.rescuerWristTempStart != null)
      rescuerItems.add(_Metric('Wrist Temp (start)',
          '${s.rescuerWristTempStart!.toStringAsFixed(1)} °C', _kTextSecond));
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
                color: _kBgGrey,
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
            pw.Spacer(),
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

// ── Trend banner card (dark gradient, matches app _TrendBanner) ────────────

  static pw.Widget _buildTrendBannerCard(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions, double trendDelta,
      double avgGrade, double bestGrade, double worstGrade) {

    if (sessions.length < 2) {
      return pw.Container(
        height: 80,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
            color: _kBgGrey, borderRadius: pw.BorderRadius.circular(10)),
        child: pw.Center(child: pw.Text('Not enough sessions for trend',
            style: pw.TextStyle(font: font, fontSize: 10, color: _kTextDisabled))),
      );
    }

    final improved  = trendDelta > 2;
    final declined  = trendDelta < -2;
    final grades    = sessions.map((s) => s.totalGrade).toList();
    final first     = grades.first;
    final last      = grades.last;
    final spread    = grades.reduce((a, b) => a > b ? a : b) -
        grades.reduce((a, b) => a < b ? a : b);

    final lineColor = improved ? _kSuccess : declined ? _kError : _kWarning;
    final stateLabel = improved ? 'IMPROVING'
        : declined ? 'NEEDS WORK'
        : spread < 5 ? 'STABLE' : 'FLUCTUATING';
    final deltaStr  = trendDelta >= 0
        ? '+${trendDelta.toStringAsFixed(0)} pts'
        : '${trendDelta.toStringAsFixed(0)} pts';

    pw.Widget statRow(String icon, String label, String value) =>
        pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Text(icon, style: pw.TextStyle(font: bold, fontSize: 8,
              color: _kWhite.shade(0.5))),
          pw.SizedBox(width: 3),
          pw.Text('$label ', style: pw.TextStyle(font: font, fontSize: 8,
              color: _kWhite.shade(0.45))),
          pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 9,
              color: _kWhite)),
        ]);

    return pw.Container(
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
            colors: [_kBrandBlue, _kBrandDark],
            begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        // ── Header row ─────────────────────────────────────────────────────
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Left: delta + range
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('GRADE TREND',
                        style: pw.TextStyle(font: bold, fontSize: 7,
                            color: _kWhite.shade(0.5))),
                    pw.SizedBox(height: 3),
                    pw.Text(deltaStr,
                        style: pw.TextStyle(font: bold, fontSize: 22,
                            color: _kWhite)),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '${first.toStringAsFixed(0)}% → ${last.toStringAsFixed(0)}%',
                      style: pw.TextStyle(font: font, fontSize: 9,
                          color: _kWhite.shade(0.55)),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Avg ${avgGrade.toStringAsFixed(1)}%  ·  '
                          '${sessions.length} sessions',
                      style: pw.TextStyle(font: medium, fontSize: 8,
                          color: _kWhite.shade(0.5)),
                    ),
                  ],
                ),
              ),
              // Right: state pill + best/worst
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color:        lineColor.shade(0.25),
                      borderRadius: pw.BorderRadius.circular(999),
                      border: pw.Border.all(color: lineColor, width: 0.8),
                    ),
                    child: pw.Text(stateLabel,
                        style: pw.TextStyle(font: bold, fontSize: 8,
                            color: lineColor)),
                  ),
                  pw.SizedBox(height: 10),
                  statRow('★', 'Best',  '${bestGrade.toStringAsFixed(0)}%'),
                  pw.SizedBox(height: 3),
                  statRow('↓', 'Worst', '${worstGrade.toStringAsFixed(0)}%'),
                ],
              ),
            ],
          ),
        ),
        // ── Sparkline chart ─────────────────────────────────────────────────
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(8, 0, 8, 14),
          child: pw.SizedBox(
            height: 80,
            child: pw.CustomPaint(
              painter: (canvas, size) =>
                  _paintGradeSparkline(canvas, size, grades),
            ),
          ),
        ),
        // ── Date range footer ───────────────────────────────────────────────
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(sessions.first.dateFormatted,
                  style: pw.TextStyle(font: font, fontSize: 7,
                      color: _kWhite.shade(0.45))),
              pw.Text(sessions.last.dateFormatted,
                  style: pw.TextStyle(font: font, fontSize: 7,
                      color: _kWhite.shade(0.45))),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Shared colour helper ───────────────────────────────────────────────────

  static PdfColor _pctColor(double fraction) {
    if (fraction >= 0.80) return _kSuccess;
    if (fraction >= 0.60) return _kWarning;
    return _kError;
  }

  // ── Radar bar table — one row per axis, one bar per session ───────────────

  static pw.Widget _buildRadarBarTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions, List<PdfColor> slotColors) {

    final axes = <(String, double Function(SessionSummary))>[
      ('Depth',   (s) => s.compressionCount > 0
          ? s.correctDepth / s.compressionCount * 100 : 0),
      ('Rate',    (s) => s.compressionCount > 0
          ? s.correctFrequency / s.compressionCount * 100 : 0),
      ('Recoil',  (s) => s.compressionCount > 0
          ? s.correctRecoil / s.compressionCount * 100 : 0),
      ('Hands-on',(s) => s.handsOnRatio * 100),
      ('Posture', (s) => s.compressionCount > 0
          ? s.correctPosture / s.compressionCount * 100 : 0),
    ];
    // Comparison mode: show ALL selected sessions.
// Capped at 4 because the chart isn't readable beyond that.
    final show = sessions.take(4).toList();

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kWhite,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(children: [
        pw.SizedBox(
          height: 200,
          child: pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.CustomPaint(
                  painter: (canvas, size) => _paintRadar(
                      canvas, size, show, axes, slotColors),
                ),
              ),
              // 5 axis labels positioned around the pentagon.
              // Pentagon centre ≈ (centre, 100); r ≈ 76 (100-24).
              for (int i = 0; i < axes.length; i++)
                _radarLabel(font, axes[i].$1, i, axes.length, 200),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 14, runSpacing: 4,
          children: [
            for (int i = 0; i < show.length; i++)
              pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                pw.Container(width: 8, height: 8,
                    decoration: pw.BoxDecoration(
                        color: slotColors[i % slotColors.length],
                        shape: pw.BoxShape.circle)),
                pw.SizedBox(width: 4),
                pw.Text('S${show[i].sessionNumber ?? i + 1}',
                    style: pw.TextStyle(
                        font: medium, fontSize: 8, color: _kTextSecond)),
              ]),
          ],
        ),
      ]),
    );
  }

  static pw.Widget _radarLabel(
      pw.Font font, String text, int i, int n, double box) {
    const pi = 3.141592653589793;
    final ang = (pi / 2) - (2 * pi * i / n);
    final cx  = box / 2;
    final cy  = box / 2;
    final r   = (box / 2) - 14;          // just outside the outer ring
    final lx  = cx + r * math.cos(ang);
    final ly  = cy - r * math.sin(ang);
    return pw.Positioned(
      left: lx - 26, top: ly - 5,
      child: pw.SizedBox(
        width: 52,
        child: pw.Text(text, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: font, fontSize: 7,
                color: _kTextSecond)),
      ),
    );
  }

  /// Overlaid radar pentagon — one polygon per session. Mirrors the
  /// in-app _RadarCard (Depth/Rate/Recoil/Hands-on/Posture, 0–100).
  static void _paintRadar(
      PdfGraphics canvas, PdfPoint size,
      List<SessionSummary> sessions,
      List<(String, double Function(SessionSummary))> axes,
      List<PdfColor> slotColors) {
    final n  = axes.length;
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r  = (size.y / 2) - 24; // leave room for axis labels

    // angle for axis i (start at top, clockwise)
    double ang(int i) => (3.141592653589793 / 2) - (2 * 3.141592653589793 * i / n);
    double px(int i, double frac) => cx + r * frac * _cos(ang(i));
    double py(int i, double frac) => cy - r * frac * _sin(ang(i));

    // Grid rings at 25/50/75/100%
    for (final ringFrac in [0.25, 0.5, 0.75, 1.0]) {
      canvas.saveContext();
      canvas.setStrokeColor(_kDivider);
      canvas.setLineWidth(0.5);
      for (int i = 0; i < n; i++) {
        final a = px(i, ringFrac), b = py(i, ringFrac);
        final a2 = px((i + 1) % n, ringFrac), b2 = py((i + 1) % n, ringFrac);
        if (i == 0) canvas.moveTo(a, b);
        canvas.lineTo(a2, b2);
      }
      canvas.strokePath();
      canvas.restoreContext();
    }

    // Spokes
    for (int i = 0; i < n; i++) {
      canvas.saveContext();
      canvas.setStrokeColor(_kDivider);
      canvas.moveTo(cx, cy);
      canvas.lineTo(px(i, 1.0), py(i, 1.0));
      canvas.strokePath();
      canvas.restoreContext();
    }

    // Session polygons
    for (int s = 0; s < sessions.length; s++) {
      final col = slotColors[s % slotColors.length];
      final fracs = [
        for (final ax in axes)
          (ax.$2(sessions[s]).clamp(0.0, 100.0)) / 100.0,
      ];
      // fill
      if (sessions.length <= 2) {
        canvas.saveContext();
        canvas.setFillColor(col.shade(0.10));
        for (int i = 0; i < n; i++) {
          final x = px(i, fracs[i]),
              y = py(i, fracs[i]);
          if (i == 0)
            canvas.moveTo(x, y);
          else
            canvas.lineTo(x, y);
        }
        canvas.closePath();
        canvas.fillPath();
        canvas.restoreContext();
      }

      // outline
      canvas.saveContext();
      canvas.setStrokeColor(col);
      canvas.setLineWidth(1.4);
      for (int i = 0; i < n; i++) {
        final x = px(i, fracs[i]), y = py(i, fracs[i]);
        if (i == 0) canvas.moveTo(x, y);
        else canvas.lineTo(x, y);
      }
      canvas.lineTo(px(0, fracs[0]), py(0, fracs[0]));
      canvas.strokePath();
      canvas.restoreContext();
    }
  }

  static double _cos(double x) {
    // Use dart:math via the file's existing import if present;
    // otherwise this references math.cos — see EX-A note.
    return math.cos(x);
  }
  static double _sin(double x) => math.sin(x);

  // ── Phase depth card (single session) ─────────────────────────────────────

  static pw.Widget _buildPhaseDepthCard(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<CompressionEvent> compressions,
      double depthMin, double depthMax) {

    final third = (compressions.length / 3).ceil();
    final early = compressions.take(third).toList();
    final mid   = compressions.skip(third).take(third).toList();
    final late  = compressions.skip(third * 2).toList();

    double avg(List<CompressionEvent> sl) => sl.isEmpty
        ? 0
        : sl.map((c) => c.depth).reduce((a, b) => a + b) / sl.length;

    double avgRate(List<CompressionEvent> sl) => sl.isEmpty
        ? 0
        : sl.map((c) => c.instantaneousRate > 0
        ? c.instantaneousRate : c.frequency)
        .reduce((a, b) => a + b) / sl.length;

    final phases = [
      ('Early', avg(early), avgRate(early), _kBrandBlue),
      ('Mid',   avg(mid),   avgRate(mid),   _kBrandMid),
      ('Late',  avg(late),  avgRate(late),  _kWarning),
    ];

    pw.Widget phaseBar(String label, double depth, double rate, PdfColor color) {
      final depthColor  = depth >= depthMin && depth <= depthMax ? _kSuccess
          : depth >= depthMin - 0.5 && depth <= depthMax + 0.5 ? _kWarning
          : _kError;
      final rateColor   = rate >= 100 && rate <= 120 ? _kSuccess
          : rate >= 90 && rate <= 130 ? _kWarning : _kError;
      final barFraction = (depth / 9.0).clamp(0.0, 1.0);
      final fillFlex    = (barFraction * 100).round().clamp(1, 99);
      final emptyFlex   = (100 - fillFlex).clamp(1, 99);

      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 4),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _kBgGrey,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: color.shade(0.4), width: 1),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(children: [
                pw.Container(width: 8, height: 8,
                    decoration: pw.BoxDecoration(
                        color: color, shape: pw.BoxShape.circle)),
                pw.SizedBox(width: 4),
                pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 9,
                    color: _kTextPrimary)),
              ]),
              pw.SizedBox(height: 8),
              // Depth bar
              pw.Text('Depth', style: pw.TextStyle(font: font, fontSize: 7,
                  color: _kTextDisabled)),
              pw.SizedBox(height: 2),
              pw.Stack(children: [
                pw.Container(height: 7, decoration: pw.BoxDecoration(
                    color: _kDivider, borderRadius: pw.BorderRadius.circular(3))),
                pw.Row(children: [
                  pw.Expanded(flex: fillFlex, child: pw.Container(
                      height: 7,
                      decoration: pw.BoxDecoration(color: depthColor,
                          borderRadius: pw.BorderRadius.circular(3)))),
                  pw.Expanded(flex: emptyFlex, child: pw.SizedBox(height: 7)),
                ]),
              ]),
              pw.SizedBox(height: 2),
              pw.Text('${depth.toStringAsFixed(1)} cm',
                  style: pw.TextStyle(font: bold, fontSize: 10,
                      color: depthColor)),
              pw.SizedBox(height: 8),
              // Rate
              pw.Text('Rate', style: pw.TextStyle(font: font, fontSize: 7,
                  color: _kTextDisabled)),
              pw.SizedBox(height: 1),
              pw.Text('${rate.toStringAsFixed(0)} BPM',
                  style: pw.TextStyle(font: bold, fontSize: 10,
                      color: rateColor)),
            ],
          ),
        ),
      );
    }

    return pw.Column(children: [
      pw.Row(
        children: phases
            .map((p) => phaseBar(p.$1, p.$2, p.$3, p.$4))
            .toList(),
      ),
      pw.SizedBox(height: 6),
      // Target reminder
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: pw.BoxDecoration(
          color: _kSuccessLight,
          borderRadius: pw.BorderRadius.circular(5),
        ),
        child: pw.Text(
          'Target: ${depthMin.toStringAsFixed(1)}–${depthMax.toStringAsFixed(1)} cm  ·  100–120 BPM  ·  '
              'Consistent across all phases indicates good stamina',
          style: pw.TextStyle(font: font, fontSize: 7, color: _kSuccess),
        ),
      ),
    ]);
  }



  // ─────────────────────────────────────────────────────────────────────────────
// SESSION TIMELINE (single-session event timeline)
//
// Mirrors the in-app _SessionTimelineSection. One row per event:
//   [ mm:ss ] [ dot ] [ title / subtitle / tip ]
// A vertical connector line links all dots. Last event ("Session ended")
// has a square cap to indicate the end.
// ─────────────────────────────────────────────────────────────────────────────

  static String _mmssFromSec(double secs) {
    final m = (secs ~/ 60).toString();
    final s = (secs % 60).toInt().toString().padLeft(2, '0');
    return '$m:$s';
  }

  static List<_TLEventPdf> _buildTimelineEvents(SessionDetail d) {
    final events = <_TLEventPdf>[];

    // ── Session start ──────────────────────────────────────────────────────
    events.add(_TLEventPdf(
      sortKey:   -1,
      time:      '0:00',
      title:     'Session started',
      subtitle:  d.timeToFirstCompression > 0
          ? 'First compression at ${d.timeToFirstCompression.toStringAsFixed(1)} s'
          : 'Compressions begun immediately',
      dotColor:  _kBrandMid,
      isBookend: true,
      tip:       d.timeToFirstCompression > 10
          ? 'Slow start — target under 10 s'
          : null,
    ));

    // ── Fatigue onset ──────────────────────────────────────────────────────
    if (d.fatigueOnsetIndex > 0 &&
        d.compressions.length >= d.fatigueOnsetIndex) {
      final t = d.compressions[d.fatigueOnsetIndex - 1].timestampSec;
      events.add(_TLEventPdf(
        sortKey:  t,
        time:     _mmssFromSec(t),
        title:    'Fatigue onset',
        subtitle: 'Detected at compression #${d.fatigueOnsetIndex}',
        dotColor: _kWarning,
      ));
    }

    // ── Unplanned pauses (scan gaps just like the app) ────────────────────
    void scan(double gapStart, double gapEnd) {
      final gap = gapEnd - gapStart;
      if (gap <= 2.0) return;
      const tol = AppConstants.plannedWindowAssocToleranceSec;
      final isPlanned = d.ventilations.any((v) =>
      v.timestampSec >= gapStart - tol && v.timestampSec <= gapEnd) ||
          d.pulseChecks.any((p) =>
          p.timestampSec >= gapStart - tol && p.timestampSec <= gapEnd);
      if (!isPlanned) {
        events.add(_TLEventPdf(
          sortKey:  gapStart,
          time:     _mmssFromSec(gapStart),
          title:    'Unplanned pause',
          subtitle: '${gap.toStringAsFixed(1)} s with no compressions',
          dotColor: _kError,
          tip:      'Keep pauses under '
              '${AppConstants.maxAcceptablePauseSec.toStringAsFixed(0)} s',
        ));
      } else if (gap > AppConstants.maxAcceptablePauseSec) {
        final excess = gap - AppConstants.maxAcceptablePauseSec;
        events.add(_TLEventPdf(
          sortKey:  gapEnd - 0.001,
          time:     _mmssFromSec(gapStart + AppConstants.maxAcceptablePauseSec),
          title:    'Unplanned pause',
          subtitle: '${excess.toStringAsFixed(1)} s over the '
              '${AppConstants.maxAcceptablePauseSec.toStringAsFixed(0)} s allowance',
          dotColor: _kError,
        ));
      }
    }
    if (d.compressions.isNotEmpty) {
      scan(0.0, d.compressions.first.timestampSec);
      for (int i = 1; i < d.compressions.length; i++) {
        scan(d.compressions[i - 1].timestampSec,
            d.compressions[i].timestampSec);
      }
      scan(d.compressions.last.timestampSec, d.sessionDuration.toDouble());
    }

    // ── Ventilations ───────────────────────────────────────────────────────
    for (final v in d.ventilations) {
      events.add(_TLEventPdf(
        sortKey:  v.timestampSec,
        time:     _mmssFromSec(v.timestampSec),
        title:    'Ventilation · cycle ${v.cycleNumber}',
        subtitle: v.compliant
            ? '${v.durationSec.toStringAsFixed(1)} s pause'
            : 'Prompt ignored · CPR continued',
        dotColor:  v.compliant ? _kBrandMid : _kTextDisabled,
        isIgnored: !v.compliant,
      ));
    }

    // ── Pulse checks (emergency mode usually) ─────────────────────────────
    for (final p in d.pulseChecks) {
      final detected = p.detected && p.detectedBpm > 0;
      events.add(_TLEventPdf(
        sortKey:   p.timestampSec,
        time:      _mmssFromSec(p.timestampSec),
        title:     'Pulse check #${p.intervalNumber}',
        subtitle:  !p.compliant
            ? 'Prompt ignored · CPR continued'
            : detected
            ? '${p.detectedBpm.round()} bpm · ${p.confidence}% confidence'
            : 'No pulse found',
        dotColor:  !p.compliant   ? _kTextDisabled
            : detected      ? _kSuccess
            : _kError,
        isIgnored: !p.compliant,
      ));
    }

    // ── Rescuer swaps ──────────────────────────────────────────────────────
    for (int i = 0; i < d.rescuerSwapCount; i++) {
      final t = (i + 1) * 120.0;
      events.add(_TLEventPdf(
        sortKey:  t,
        time:     _mmssFromSec(t),
        title:    'Rescuer swap · alert ${i + 1}',
        subtitle: '2-minute interval prompt',
        dotColor: _kWarning,
      ));
    }

    events.sort((a, b) => a.sortKey.compareTo(b.sortKey));

    // ── Session end ────────────────────────────────────────────────────────
    events.add(_TLEventPdf(
      sortKey:   d.sessionDuration.toDouble() + 1,
      time:      d.durationFormatted,
      title:     'Session ended',
      subtitle:  () {
        final parts = ['${d.compressionCount} compressions'];
        if (d.unplannedPauseCount > 0) {
          parts.add('${d.unplannedPauseCount} unplanned '
              'pause${d.unplannedPauseCount == 1 ? '' : 's'}');
        }
        return parts.join(' · ');
      }(),
      dotColor:  _kBrandMid,
      isBookend: true,
    ));

    return events;
  }

// ── Build the timeline widget ────────────────────────────────────────────────

  static pw.Widget _buildSessionTimeline(
      pw.Font bold, pw.Font medium, pw.Font font,
      SessionDetail d) {

    final events = _buildTimelineEvents(d);
    if (events.length <= 2) {
      // Just start + end → not worth rendering.
      return pw.SizedBox.shrink();
    }

    // Row layout (PDF can't do IntrinsicHeight cleanly, so each row has
    // fixed-height connector segments stitched together):
    //
    // [ 0:42  ]   ●          Unplanned pause
    //              │          3.4 s with no compressions
    //              │          [ tip pill ]
    // [ 0:55  ]   ●          Ventilation · cycle 3
    //              │          1.4 s pause
    //              │
    //
    // Connector line is drawn by a small CustomPaint behind each row's dot.

    pw.Widget row(_TLEventPdf e, bool isFirst, bool isLast) {
      final dotSize     = e.isBookend ? 18.0 : 12.0;
      final dotColumnW  = 22.0;

      // Build the optional tip pill
      pw.Widget? tip;
      if (e.tip != null) {
        tip = pw.Container(
          margin:  const pw.EdgeInsets.only(top: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: pw.BoxDecoration(
            color: _kWarningLight,
            borderRadius: pw.BorderRadius.circular(99),
          ),
          child: pw.Text(e.tip!,
              style: pw.TextStyle(font: medium, fontSize: 7,
                  color: _kWarning)),
        );
      }

      return pw.Container(
        // No fixed height — let content drive it.
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Time column
            pw.SizedBox(
              width: 32,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(e.time,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(font: medium, fontSize: 7,
                        color: _kTextDisabled)),
              ),
            ),
            pw.SizedBox(width: 6),
            // Dot + connector column
            pw.SizedBox(
              width: dotColumnW,
              child: pw.Stack(
                alignment: pw.Alignment.topCenter,
                children: [
                  // Connector segments — drawn behind the dot.
                  // Top half (above the dot) — skip on first row.
                  if (!isFirst)
                    pw.Positioned(
                      top: 0,
                      child: pw.Container(
                          width: 1.5, height: 8, color: _kDivider),
                    ),
                  // Bottom half (below the dot) — skip on last row.
                  // Fixed height instead of bottom:0 so the Stack has a
                  // resolvable size — otherwise MultiPage can't lay out.
                  if (!isLast)
                    pw.Positioned(
                      top: 8 + dotSize - 1,
                      child: pw.Container(
                          width: 1.5, height: 40, color: _kDivider),
                    ),
                  // The dot itself
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 6),
                    child: e.isIgnored
                        ? pw.Container(
                      width: dotSize, height: dotSize,
                      decoration: pw.BoxDecoration(
                        color: _kBgGrey,
                        shape: pw.BoxShape.circle,
                        border: pw.Border.all(
                            color: _kTextDisabled, width: 0.8),
                      ),
                    )
                        : pw.Container(
                      width: dotSize, height: dotSize,
                      decoration: pw.BoxDecoration(
                        color: e.dotColor,
                        shape: pw.BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            // Content
            pw.Expanded(
              child: pw.Padding(
                padding: pw.EdgeInsets.only(
                    top: 3,
                    bottom: isLast ? 0 : 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(e.title,
                        style: pw.TextStyle(
                            font: e.isBookend ? bold : medium,
                            fontSize: 9,
                            color: e.isIgnored
                                ? _kTextDisabled : _kTextPrimary)),
                    pw.SizedBox(height: 1),
                    pw.Text(e.subtitle,
                        style: pw.TextStyle(font: font, fontSize: 7,
                            color: e.isIgnored
                                ? _kTextDisabled
                                : _kTextSecond)),
                    if (tip != null) tip,
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── Stat strip below the timeline (like _TimelineStatGrid) ──────────────
    final activeCprTime = (d.sessionDuration - d.noFlowTime).clamp(0.0, double.infinity);
    final compliantVent = d.ventilations.where((v) => v.compliant).length;
    final pauseColor    = d.unplannedPauseTime > AppConstants.maxAcceptablePauseSec
        ? _kWarning : _kSuccess;

    final chips = <(String, String, PdfColor)>[
      ('Total time',   d.durationFormatted, _kTextSecond),
      if (d.unplannedPauseCount > 0)
        ('Active CPR',  _mmssFromSec(activeCprTime.toDouble()), _kBrandBlue),
      ('Compressions', '${d.compressionCount}', _kTextPrimary),
      if (d.unplannedPauseCount > 0)
        ('Unplanned pauses',
        '${d.unplannedPauseTime.toStringAsFixed(1)}s '
            '(${d.unplannedPauseCount}×)', pauseColor),
      if (d.ventilations.isNotEmpty)
        ('Ventilations',
        '$compliantVent/${d.ventilations.length} compliant',
        compliantVent == d.ventilations.length ? _kBrandBlue : _kWarning),
      if (d.pulseChecks.isNotEmpty)
        ('Pulse checks',
        '${d.pulseChecks.where((p) => p.compliant).length}/${d.pulseChecks.length} completed',
        d.pulseDetectedFinal ? _kSuccess : _kTextSecond),
    ];

    // Render chips as 2-column grid
    pw.Widget chipWidget((String, String, PdfColor) c) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(c.$1,
              style: pw.TextStyle(font: font, fontSize: 7,
                  color: _kTextSecond)),
          pw.SizedBox(height: 1),
          pw.Text(c.$2,
              style: pw.TextStyle(font: bold, fontSize: 9, color: c.$3)),
        ],
      ),
    );

    final chipRows = <pw.Widget>[];
    for (int i = 0; i < chips.length; i += 2) {
      chipRows.add(pw.Row(children: [
        pw.Expanded(child: chipWidget(chips[i])),
        if (i + 1 < chips.length) ...[
          pw.Container(width: 0.5, height: 28, color: _kDivider),
          pw.Expanded(child: chipWidget(chips[i + 1])),
        ] else
          pw.Expanded(child: pw.SizedBox()),
      ]));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Timeline card — wrapping ONLY the rows in a card so MultiPage
        // can split between events if the session has many of them.
        // Using a transparent background per-row keeps it visually grouped.
        for (int i = 0; i < events.length; i++)
          pw.Container(
            width: double.infinity,
            color: _kWhite,
            padding: pw.EdgeInsets.only(
              left: 12, right: 12,
              top:    i == 0 ? 12 : 0,
              bottom: i == events.length - 1 ? 10 : 0,
            ),
            child: row(events[i], i == 0, i == events.length - 1),
          ),

        // Divider before stats (still inside the white card)
        pw.Container(
          width: double.infinity,
          color: _kWhite,
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: pw.Container(height: 0.5, color: _kDivider),
        ),

        // Stats grid card — its own atomic block; small enough to fit
        pw.Container(
          width: double.infinity,
          decoration: pw.BoxDecoration(
            color: _kBrandLight.shade(0.4),
            borderRadius: const pw.BorderRadius.only(
              bottomLeft:  pw.Radius.circular(10),
              bottomRight: pw.Radius.circular(10),
            ),
          ),
          padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: pw.Column(children: chipRows),
        ),
      ],
    );
  }


  // ── Multi-session phase comparison table ───────────────────────────────────

  static pw.Widget _buildMultiPhaseTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions,
      List<SessionDetail?> details,
      List<PdfColor> slotColors) {

    List<double> phases(SessionDetail d) {
      final c     = d.compressions;
      if (c.isEmpty) return [0, 0, 0, 0, 0, 0];
      final third = (c.length / 3).ceil();
      final early = c.take(third).toList();
      final mid   = c.skip(third).take(third).toList();
      final late  = c.skip(third * 2).toList();
      double ad(List<CompressionEvent> sl) => sl.isEmpty ? 0
          : sl.map((e) => e.depth).reduce((a, b) => a + b) / sl.length;
      double ar(List<CompressionEvent> sl) => sl.isEmpty ? 0
          : sl.map((e) => e.instantaneousRate > 0
          ? e.instantaneousRate : e.frequency)
          .reduce((a, b) => a + b) / sl.length;
      return [ad(early), ad(mid), ad(late), ar(early), ar(mid), ar(late)];
    }

    final withDetail = [
      for (int i = 0; i < sessions.length && i < details.length; i++)
        if (details[i] != null && details[i]!.compressions.length >= 9)
          (i, sessions[i], details[i]!),
    ];

    if (withDetail.isEmpty) return pw.SizedBox.shrink();

    pw.Widget cell(String text, {pw.TextAlign align = pw.TextAlign.center,
      PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(text, textAlign: align,
              style: pw.TextStyle(font: medium, fontSize: 8,
                  color: color ?? _kTextSecond)),
        );

    return pw.Table(
      border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5)),
      columnWidths: {
        0: const pw.FixedColumnWidth(20),
        1: const pw.FlexColumnWidth(1.6),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(1),
        6: const pw.FlexColumnWidth(1),
        7: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _kBrandDark),
          children: [
            _tableCell(bold, '#',       isHeader: true, isDark: true),
            _tableCell(bold, 'Session', isHeader: true, isDark: true),
            _tableCell(bold, 'D-Early', isHeader: true, isDark: true,
                align: pw.TextAlign.center),
            _tableCell(bold, 'D-Mid',   isHeader: true, isDark: true,
                align: pw.TextAlign.center),
            _tableCell(bold, 'D-Late',  isHeader: true, isDark: true,
                align: pw.TextAlign.center),
            _tableCell(bold, 'R-Early', isHeader: true, isDark: true,
                align: pw.TextAlign.center),
            _tableCell(bold, 'R-Mid',   isHeader: true, isDark: true,
                align: pw.TextAlign.center),
            _tableCell(bold, 'R-Late',  isHeader: true, isDark: true,
                align: pw.TextAlign.center),
          ],
        ),
        for (final (idx, s, d) in withDetail) ...[
              () {
            final p     = phases(d);
            final isPed = s.scenario == 'pediatric';
            final dMin  = isPed ? CprTargets.depthMinPediatric : CprTargets.depthMin;
            final dMax  = isPed ? CprTargets.depthMaxPediatric : CprTargets.depthMax;
            PdfColor dc(double v) => v >= dMin && v <= dMax ? _kSuccess
                : v >= dMin - 0.5 && v <= dMax + 0.5 ? _kWarning : _kError;
            PdfColor rc(double v) => v >= 100 && v <= 120 ? _kSuccess
                : v >= 90 && v <= 130 ? _kWarning : _kError;
            return pw.TableRow(
              decoration: pw.BoxDecoration(
                  color: idx.isOdd ? _kBgGrey : _kWhite),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6, vertical: 6),
                  child: pw.Container(
                    width: 10, height: 10,
                    decoration: pw.BoxDecoration(
                        color: slotColors[idx % slotColors.length],
                        shape: pw.BoxShape.circle),
                  ),
                ),
                _tableCell(font, s.dateFormatted),
                cell('${p[0].toStringAsFixed(1)}', color: dc(p[0])),
                cell('${p[1].toStringAsFixed(1)}', color: dc(p[1])),
                cell('${p[2].toStringAsFixed(1)}', color: dc(p[2])),
                cell('${p[3].toStringAsFixed(0)}', color: rc(p[3])),
                cell('${p[4].toStringAsFixed(0)}', color: rc(p[4])),
                cell('${p[5].toStringAsFixed(0)}', color: rc(p[5])),
              ],
            );
          }(),
        ],
      ],
    );
  }

  // ── Enhanced all-sessions table with slot colour dots ─────────────────────

  static pw.Widget _buildAllSessionsTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions,
      List<PdfColor> slotColors) {

    return pw.Table(
      border: pw.TableBorder(
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
          decoration: pw.BoxDecoration(color: _kBrandDark),
          children: [
            _tableCell(bold, '#',        isHeader: true, isDark: true),
            _tableCell(bold, 'Date',     isHeader: true, isDark: true),
            _tableCell(bold, 'Mode',     isHeader: true, isDark: true),
            _tableCell(bold, 'Scenario', isHeader: true, isDark: true),
            _tableCell(bold, 'Duration', isHeader: true, isDark: true,
                align: pw.TextAlign.right),
            _tableCell(bold, 'Compr.',   isHeader: true, isDark: true,
                align: pw.TextAlign.right),
            _tableCell(bold, 'Depth',    isHeader: true, isDark: true,
                align: pw.TextAlign.right),
            _tableCell(bold, 'CCF',      isHeader: true, isDark: true,
                align: pw.TextAlign.right),
            _tableCell(bold, 'Grade',    isHeader: true, isDark: true,
                align: pw.TextAlign.right),
          ],
        ),
        ...sessions.asMap().entries.map((e) {
          final i          = e.key;
          final s          = e.value;
          final isAlt      = i.isOdd;
          final gradeColor = s.isEmergency ? _kTextDisabled : _gradeColor(s.totalGrade);
          final slotColor  = slotColors[i % slotColors.length];

          return pw.TableRow(
            decoration: pw.BoxDecoration(
                color: isAlt ? _kBgGrey : _kWhite),
            children: [
              // Slot colour dot
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6, vertical: 7),
                child: pw.Container(
                  width: 8, height: 8,
                  decoration: pw.BoxDecoration(
                      color: slotColor, shape: pw.BoxShape.circle),
                ),
              ),
              _tableCell(font, s.dateFormatted),
              _tableModeCell(bold, s),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 5, vertical: 5),
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: pw.BoxDecoration(
                      color: s.scenario == 'pediatric'
                          ? _kPediatricBg : _kBrandLight,
                      borderRadius: pw.BorderRadius.circular(3)),
                  child: pw.Text(
                      s.scenario == 'pediatric' ? 'Ped.' : 'Adult',
                      style: pw.TextStyle(font: bold, fontSize: 7,
                          color: s.scenario == 'pediatric'
                              ? _kPediatric : _kBrandBlue)),
                ),
              ),
              _tableCell(font, s.durationFormatted,
                  align: pw.TextAlign.right),
              _tableCell(font, '${s.compressionCount}',
                  align: pw.TextAlign.right),
              _tableCell(font,
                  s.averageDepth > 0
                      ? '${s.averageDepth.toStringAsFixed(1)} cm' : '—',
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


  // ─────────────────────────────────────────────────────────────────────────────
// COMPARISON METRICS TABLE
//
// One row per metric, one column per slot. The "best" value per row is
// highlighted in bold + colored.
// ─────────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildComparisonMetricsTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions,
      List<SessionDetail?>? details,
      List<PdfColor> slotColors) {

    final n = sessions.length;
    double? safeAvg(List<double> v) => v.isEmpty
        ? null : v.reduce((a, b) => a + b) / v.length;

    SessionDetail? detailFor(int i) {
      if (details == null) return null;
      if (i >= details.length) return null;
      return details[i];
    }

    // ── Define rows ────────────────────────────────────────────────────────
    final rows = <_CompareRow>[
      // ── Session Info group ──
      _CompareRow(
        label: 'Duration',
        group: 'Session',
        values: [for (final s in sessions) s.sessionDuration.toDouble()],
        format: (v) => v == null ? '—' : Duration(seconds: v.toInt()).mmss,
        noWinner: true,
      ),
      _CompareRow(
        label: 'Compressions',
        group: 'Session',
        values: [for (final s in sessions) s.compressionCount.toDouble()],
        format: (v) => v == null ? '—' : v.toInt().toString(),
        noWinner: true,
      ),
      _CompareRow(
        label: 'Grade',
        hint:  'higher is better',
        group: 'Session',
        values: [for (final s in sessions)
          s.isEmergency ? null : s.totalGrade],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(0)}%',
        higherIsBetter: true,
      ),

      // ── Depth group ──
      _CompareRow(
        label: 'Avg Depth',
        hint:  '5–6 cm target',
        group: 'Depth',
        values: [for (final s in sessions) s.averageDepth > 0
            ? s.averageDepth : null],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(1)} cm',
        // "Best" means closest to 5.5 (or 4.5 pediatric)
        higherIsBetter: false,    // handled with distance — see below
      ),
      _CompareRow(
        label: 'Peak Depth',
        group: 'Depth',
        values: [for (final s in sessions) s.peakDepth > 0
            ? s.peakDepth : null],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(1)} cm',
        noWinner: true,
      ),
      _CompareRow(
        label: 'Depth in Target',
        hint:  'higher is better',
        group: 'Depth',
        values: [for (final s in sessions) s.compressionCount > 0
            ? s.correctDepth / s.compressionCount * 100 : null],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(0)}%',
        higherIsBetter: true,
      ),

      // ── Rate group ──
      _CompareRow(
        label: 'Avg Rate',
        hint:  '100–120 BPM',
        group: 'Rate',
        values: [for (final s in sessions) s.averageFrequency > 0
            ? s.averageFrequency : null],
        format: (v) => v == null ? '—' : '${v.round()} BPM',
        higherIsBetter: false,    // distance from 110 — see logic below
      ),
      _CompareRow(
        label: 'Rate in Target',
        hint:  'higher is better',
        group: 'Rate',
        values: [for (final s in sessions) s.compressionCount > 0
            ? s.correctFrequency / s.compressionCount * 100 : null],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(0)}%',
        higherIsBetter: true,
      ),

      // ── Quality group ──
      _CompareRow(
        label: 'Recoil',
        hint:  'higher is better',
        group: 'Quality',
        values: [for (final s in sessions) s.compressionCount > 0
            ? s.correctRecoil / s.compressionCount * 100 : null],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(0)}%',
        higherIsBetter: true,
      ),
      _CompareRow(
        label: 'CCF (Hands-On)',
        hint:  'target ≥ 80%',
        group: 'Quality',
        values: [for (final s in sessions) s.handsOnRatio * 100],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(0)}%',
        higherIsBetter: true,
      ),
      _CompareRow(
        label: 'Posture',
        hint:  'higher is better',
        group: 'Quality',
        values: [for (final s in sessions) s.compressionCount > 0
            ? s.correctPosture / s.compressionCount * 100 : null],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(0)}%',
        higherIsBetter: true,
      ),

      // ── Timing group ──
      _CompareRow(
        label: 'Time to 1st',
        hint:  '< 10 s',
        group: 'Timing',
        values: [for (int i = 0; i < n; i++) detailFor(i)?.timeToFirstCompression],
        format: (v) => v == null || v <= 0 ? '—' : '${v.toStringAsFixed(1)} s',
        higherIsBetter: false,
      ),
      _CompareRow(
        label: 'Unplanned Pauses',
        hint:  'fewer is better',
        group: 'Timing',
        values: [for (int i = 0; i < n; i++)
          detailFor(i)?.unplannedPauseTime],
        format: (v) => v == null ? '—' : '${v.toStringAsFixed(1)} s',
        higherIsBetter: false,
      ),
    ];

    // ── Determine winner per row ───────────────────────────────────────────
    int? winnerIdx(_CompareRow r) {
      if (r.noWinner) return null;
      final entries = <(int, double)>[];
      for (int i = 0; i < r.values.length; i++) {
        final v = r.values[i];
        if (v != null) entries.add((i, v));
      }
      if (entries.length < 2) return null;
      // Depth: closest to 5.5; Rate: closest to 110. Detect by label.
      if (r.label == 'Avg Depth') {
        final target = sessions.first.scenario == 'pediatric' ? 4.5 : 5.5;
        entries.sort((a, b) =>
            (a.$2 - target).abs().compareTo((b.$2 - target).abs()));
        return entries.first.$1;
      }
      if (r.label == 'Avg Rate') {
        entries.sort((a, b) =>
            (a.$2 - 110).abs().compareTo((b.$2 - 110).abs()));
        return entries.first.$1;
      }
      entries.sort((a, b) => r.higherIsBetter
          ? b.$2.compareTo(a.$2) : a.$2.compareTo(b.$2));
      return entries.first.$1;
    }

    // ── Render ─────────────────────────────────────────────────────────────
    // Group by `group` field, render section header then rows.
    final groupOrder = <String>[];
    final byGroup = <String, List<_CompareRow>>{};
    for (final r in rows) {
      if (!groupOrder.contains(r.group)) groupOrder.add(r.group);
      byGroup.putIfAbsent(r.group, () => []).add(r);
    }

    final children = <pw.Widget>[];
    for (final g in groupOrder) {
      // Group header
      children.add(pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: pw.BoxDecoration(
          color: _kBrandLight,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(g.toUpperCase(),
            style: pw.TextStyle(font: bold, fontSize: 8,
                color: _kBrandBlue, letterSpacing: 0.6)),
      ));
      children.add(pw.SizedBox(height: 4));
      // Group rows
      for (final r in byGroup[g]!) {
        final winner = winnerIdx(r);
        children.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Label column
              pw.SizedBox(
                width: 110,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(r.label,
                        style: pw.TextStyle(font: medium, fontSize: 9,
                            color: _kTextPrimary)),
                    if (r.hint.isNotEmpty)
                      pw.Text(r.hint,
                          style: pw.TextStyle(font: font, fontSize: 7,
                              color: _kTextDisabled)),
                  ],
                ),
              ),
              // Value columns
              for (int i = 0; i < r.values.length; i++)
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4, vertical: 5),
                    decoration: pw.BoxDecoration(
                      color: winner == i
                          ? slotColors[i].shade(0.85)
                          : null,
                      borderRadius: pw.BorderRadius.circular(4),
                      border: winner == i
                          ? pw.Border.all(color: slotColors[i], width: 0.5)
                          : null,
                    ),
                    child: pw.Text(r.format(r.values[i]),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                            font: winner == i ? bold : medium,
                            fontSize: 9,
                            color: winner == i
                                ? slotColors[i]
                                : (r.values[i] == null
                                ? _kTextDisabled
                                : _kTextPrimary))),
                  ),
                ),
            ],
          ),
        ));
      }
      children.add(pw.SizedBox(height: 8));
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _kWhite,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────────
// MULTI-SESSION TIMELINE
//
// One row per session in chronological order. Shows:
//   [ date ] [ dot — grade color ] [ mode/scenario · grade · key stat ]
// A vertical connector links all sessions visually as a "training journey".
// ─────────────────────────────────────────────────────────────────────────────

  static pw.Widget _buildMultiSessionTimeline(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions) {

    if (sessions.isEmpty) return pw.SizedBox.shrink();

    // Sort oldest first — timeline reads top → bottom = past → present.
    final sorted = [...sessions]
      ..sort((a, b) =>
          (a.sessionStart ?? DateTime(2000))
              .compareTo(b.sessionStart ?? DateTime(2000)));

    // Compute best/worst for highlighting
    final trainingGrades = sorted
        .where((s) => s.isTraining && s.totalGrade > 0)
        .map((s) => s.totalGrade)
        .toList();
    final maxG = trainingGrades.isEmpty
        ? 0.0 : trainingGrades.reduce((a, b) => a > b ? a : b);
    final minG = trainingGrades.isEmpty
        ? 0.0 : trainingGrades.reduce((a, b) => a < b ? a : b);

    pw.Widget sessionRow(SessionSummary s, int idx, bool isFirst, bool isLast,
        double? prevGrade) {

      final isEmg     = s.isEmergency;
      final dotColor  = isEmg ? _kEmgGreen : _gradeColor(s.totalGrade);
      final isBest    = !isEmg && trainingGrades.length > 1 && s.totalGrade == maxG;
      final isWorst   = !isEmg && trainingGrades.length > 1 && s.totalGrade == minG;

      // Delta from previous training session
      String? deltaStr;
      PdfColor? deltaColor;
      if (!isEmg && prevGrade != null && prevGrade > 0) {
        final d = s.totalGrade - prevGrade;
        if (d.abs() >= 1) {
          deltaStr   = d > 0 ? '+${d.toStringAsFixed(0)} pts'
              : '${d.toStringAsFixed(0)} pts';
          deltaColor = d > 0 ? _kSuccess : _kError;
        }
      }

      // Badge
      String? badge;
      PdfColor? badgeColor, badgeBg;
      if (isBest) {
        badge = 'BEST';   badgeColor = _kSuccess;  badgeBg = _kSuccessLight;
      } else if (isWorst) {
        badge = 'WEAKEST'; badgeColor = _kWarning; badgeBg = _kWarningLight;
      }

      // Subtitle: scenario · stats
      final scenario = s.scenario == 'pediatric' ? 'Pediatric' : 'Adult';
      final modeStr  = isEmg ? 'Emergency' : 'Training';
      final keyStat  = isEmg
          ? '${s.compressionCount} compressions · '
          '${s.durationFormatted}'
          : 'Grade ${s.totalGrade.toStringAsFixed(0)}% · '
          'CCF ${(s.handsOnRatio * 100).round()}%';

      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Date column
          pw.SizedBox(
            width: 56,
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(s.dateFormatted,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: medium, fontSize: 8,
                          color: _kTextPrimary)),
                  pw.Text(
                      s.sessionStart != null
                          ? '${s.sessionStart!.hour.toString().padLeft(2, '0')}:'
                          '${s.sessionStart!.minute.toString().padLeft(2, '0')}'
                          : '',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(font: font, fontSize: 7, color: _kTextDisabled)),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          // Dot + connector
          pw.SizedBox(
            width: 22,
            child: pw.Stack(
              alignment: pw.Alignment.topCenter,
              children: [
                if (!isFirst)
                  pw.Positioned(top: 0,
                      child: pw.Container(width: 1.5, height: 10,
                          color: _kDivider)),
                if (!isLast)
                  pw.Positioned(top: 24,
                      child: pw.Container(width: 1.5, height: 50, color: _kDivider)),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 8),
                  child: pw.Container(
                    width: 14, height: 14,
                    decoration: pw.BoxDecoration(
                      color: dotColor,
                      shape: pw.BoxShape.circle,
                      border: pw.Border.all(color: _kWhite, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          // Content
          pw.Expanded(
            child: pw.Container(
              margin: pw.EdgeInsets.only(top: 4, bottom: isLast ? 0 : 12),
              padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: pw.BoxDecoration(
                color: _kWhite,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _kDivider, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        // Mode pill
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: pw.BoxDecoration(
                            color: isEmg ? _kEmgGreenBg : _kBrandLight,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(modeStr,
                              style: pw.TextStyle(font: bold, fontSize: 7,
                                  color: isEmg ? _kEmgGreen : _kBrandBlue)),
                        ),
                        pw.SizedBox(width: 4),
                        // Scenario pill
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: pw.BoxDecoration(
                            color: s.scenario == 'pediatric'
                                ? _kPediatricBg : _kBgGrey,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                          child: pw.Text(scenario,
                              style: pw.TextStyle(font: medium, fontSize: 7,
                                  color: s.scenario == 'pediatric'
                                      ? _kPediatric : _kTextSecond)),
                        ),
                        if (badge != null) ...[
                          pw.SizedBox(width: 4),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: pw.BoxDecoration(
                              color: badgeBg,
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                            child: pw.Text(badge!,
                                style: pw.TextStyle(font: bold, fontSize: 7,
                                    color: badgeColor)),
                          ),
                        ],
                        pw.Spacer(),
                        if (deltaStr != null)
                          pw.Text(deltaStr,
                              style: pw.TextStyle(font: bold, fontSize: 8,
                                  color: deltaColor)),
                      ]),
                  pw.SizedBox(height: 4),
                  pw.Text(keyStat,
                      style: pw.TextStyle(font: medium, fontSize: 9,
                          color: _kTextPrimary)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '${s.compressionCount} compressions · '
                        '${s.averageDepth > 0
                        ? '${s.averageDepth.toStringAsFixed(1)} cm depth · ' : ''}'
                        '${s.averageFrequency > 0
                        ? '${s.averageFrequency.round()} BPM' : '—'}',
                    style: pw.TextStyle(font: font, fontSize: 7,
                        color: _kTextSecond),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Walk sessions, track previous TRAINING grade for delta calculation.
    final widgets = <pw.Widget>[];
    double? prevTrainingGrade;
    for (int i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      widgets.add(sessionRow(s, i, i == 0, i == sorted.length - 1,
          prevTrainingGrade));
      if (s.isTraining && s.totalGrade > 0) {
        prevTrainingGrade = s.totalGrade;
      }
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: widgets);
  }

  // ── All-sessions table ────────────────────────────────────────────────────

  static pw.Widget _sessionTable(
      pw.Font bold, pw.Font medium, pw.Font font,
      List<SessionSummary> sessions) {
    return pw.Table(
      border: pw.TableBorder(
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
          decoration: pw.BoxDecoration(color: _kBrandDark),
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

  // ── Section title ──────────────────────────────────────────────────────────

  static pw.Widget _sectionTitle(pw.Font bold, String title) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(width: 3, height: 14,
            decoration: pw.BoxDecoration(
                color: _kBrandBlue,
                borderRadius: pw.BorderRadius.circular(1.5))),
        pw.SizedBox(width: 7),
        pw.Text(title,
            style: pw.TextStyle(
                font: bold, fontSize: 11, color: _kTextPrimary,
                letterSpacing: 0.3)),
      ],
    );
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

// ═══════════════════════════════════════════════════════════════════════════
  // CONSOLIDATED TIME-SERIES CHART
  // One builder replaces _chartCard + all 7 hand-rolled painters.
  // Axis LABELS are real pw.Text (canvas drawString is unusable here);
  // the CustomPaint draws only the plot: gridlines, band, lines, dots.
  // X axis = time (m:ss) from timestampSec — matches the in-app charts.
  // ═══════════════════════════════════════════════════════════════════════════

  /// One data line in a chart.
  /// `points` are (timeSec, value) pairs already filtered/clamped by the caller.
  static List<List<double>> _series<T>(
      Iterable<T> items,
      double Function(T) t,
      double Function(T) v, {
        bool Function(T)? where,
      }) {
    final out = <List<double>>[];
    for (final it in items) {
      if (where != null && !where(it)) continue;
      out.add([t(it), v(it)]);
    }
    return out;
  }

  static pw.Widget _buildOverlaidComparisonChart({
    required pw.Font font,
    required pw.Font fontBold,
    required String title,
    required String? subtitle,
    required String? caption,
    required List<SessionSummary> sessions,
    required List<SessionDetail?>? details,
    required List<PdfColor> slotColors,
    required double Function(CompressionEvent) yExtractor,
    required double minY,
    required double maxY,
    double? yTickInterval,
    required String Function(double) yLabel,
    _ChartBand? band,
    List<_ChartGuide> guides = const [],
  }) {
    if (details == null) return pw.SizedBox.shrink();

    final lines = <_ChartLine>[];
    final legend = <_LegendItem>[];
    for (int i = 0; i < sessions.length; i++) {
      final d = i < details.length ? details[i] : null;
      if (d == null || d.compressions.isEmpty) continue;
      lines.add(_ChartLine(
          _series(d.compressions, (c) => c.timestampSec, yExtractor),
          slotColors[i],
          fill: false));   // never fill on overlay — that's the difference
      legend.add(_LegendItem('Slot ${i + 1}', slotColors[i]));
    }
    if (band != null) {
      legend.add(_LegendItem('Target band', _kSuccess));
    }
    if (lines.isEmpty) return pw.SizedBox.shrink();

    return _buildTimeChart(
      font: font, fontBold: fontBold,
      title: title,
      subtitle: subtitle,
      caption: caption,
      lines: lines,
      minY: minY, maxY: maxY, yTickInterval: yTickInterval, yLabel: yLabel,
      band: band, guides: guides, legend: legend,
      plotHeight: 110,
      dotColor: null,   // no dots on overlaid charts — too noisy
    );
  }

  /// Builds a complete chart card: left value-axis labels + plot + bottom
  /// time-axis labels + legend. This is the ONLY chart entry point.
  static pw.Widget _buildTimeChart({
    required pw.Font font,
    required pw.Font fontBold,
    required String  title,
    String?         subtitle,            // optional one-liner under the title
    String?         caption,             // optional explanation under the legend
    required List<_ChartLine> lines,
    required double minY,
    required double maxY,
    required String Function(double) yLabel,
    double? yTickInterval,
    _ChartBand? band,
    List<_ChartGuide> guides = const [],
    required List<_LegendItem> legend,
    double plotHeight = 100,
    PdfColor? Function(int, double)? dotColor,
  }) {
    const double kLeftGutter   = 26;
    const double kBottomGutter = 14;

    // Overall session span for the x axis (max t across all lines).
    double tMax = 0;
    for (final l in lines) {
      for (final p in l.points) { if (p[0] > tMax) tMax = p[0]; }
    }
    if (tMax <= 0) tMax = 1;

    final ticks = yTickInterval != null
        ? <double>[
      for (double y = minY; y <= maxY + 0.001; y += yTickInterval) y
    ]
        : <double>[
      minY,
      minY + (maxY - minY) * 0.33,
      minY + (maxY - minY) * 0.66,
      maxY,
    ];

    // X tick times (5 evenly spaced m:ss labels).
    final xTicks = <double>[
      for (int i = 0; i <= 4; i++) tMax * i / 4,
    ];

    return pw.Container(
      width:   double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: pw.BoxDecoration(
        color:        _kBgGrey,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  font: fontBold, fontSize: 10, color: _kTextPrimary,
                  letterSpacing: 0.2)),
          if (subtitle != null) ...[
            pw.SizedBox(height: 1),
            pw.Text(subtitle,
                style: pw.TextStyle(font: font, fontSize: 7,
                    color: _kTextDisabled)),
          ],
          pw.SizedBox(height: 6),

          // Plot row: [ y labels ] [ plot ]
          pw.SizedBox(
            height: plotHeight,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Left value axis
                pw.SizedBox(
                  width: kLeftGutter,
                  child: pw.Stack(
                    children: [
                      for (final ty in ticks)
                        pw.Positioned(
                          right: 3,
                          top: (1 - (ty - minY) / (maxY - minY)) *
                              plotHeight - 4,
                          child: pw.Text(yLabel(ty),
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 6.5,
                                  color: _kTextDisabled)),
                        ),
                    ],
                  ),
                ),
                // Plot
                pw.Expanded(
                  child: pw.CustomPaint(
                    painter: (canvas, size) => _paintPlot(
                      canvas, size,
                      lines: lines,
                      minY: minY, maxY: maxY, tMax: tMax,
                      ticks: ticks,
                      band: band, guides: guides,
                      dotColor: dotColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom time axis (aligned under the plot, offset by gutter)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: kLeftGutter, top: 2),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                for (final tx in xTicks)
                  pw.Text(_mmss(tx.round()),
                      style: pw.TextStyle(
                          font: font,
                          fontSize: 6.5,
                          color: _kTextDisabled)),
              ],
            ),
          ),

          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 14, runSpacing: 3,
            children: legend.map((item) => pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Container(width: 10, height: 3,
                    decoration: pw.BoxDecoration(
                        color: item.color,
                        borderRadius:
                        pw.BorderRadius.circular(2))),
                pw.SizedBox(width: 4),
                pw.Text(item.label,
                    style: pw.TextStyle(
                        font: font, fontSize: 8, color: _kTextSecond)),
              ],
            )).toList(),
          ),
          if (caption != null) ...[
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: pw.BoxDecoration(
                color: _kBrandLight.shade(0.3),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(caption,
                  style: pw.TextStyle(font: font, fontSize: 7,
                      color: _kTextSecond, lineSpacing: 1.5)),
            ),
          ],
        ],
      ),
    );
  }

  /// The single plot painter — gridlines, band, guides, every line, dots.
  /// Replaces _paintDepthChart/_paintRateChart/_paintForceChart/
  /// _paintPostureChart/_paintVitalsChart/_paintGradeSparkline/
  /// _paintGenericSparkline.
  static void _paintPlot(
      PdfGraphics canvas, PdfPoint size, {
        required List<_ChartLine> lines,
        required double minY,
        required double maxY,
        required double tMax,
        required List<double> ticks,
        _ChartBand? band,
        List<_ChartGuide> guides = const [],
        PdfColor? Function(int, double)? dotColor,
      }) {
    double xOf(double tSec) => (tSec / tMax).clamp(0.0, 1.0) * size.x;
    double yOf(double v) =>
        size.y - ((v - minY) / (maxY - minY)).clamp(0.0, 1.0) * size.y;

    // Horizontal gridlines at each y tick (very light).
    canvas.saveContext();
    canvas.setStrokeColor(_kDivider);
    canvas.setLineWidth(0.4);
    for (final ty in ticks) {
      final y = yOf(ty);
      canvas.moveTo(0, y);
      canvas.lineTo(size.x, y);
      canvas.strokePath();
    }
    canvas.restoreContext();

    // Target band.
    if (band != null) {
      final top = yOf(band.max);
      final h   = yOf(band.min) - top;
      if (h > 0) {
        // Filled rect
        canvas.saveContext();
        canvas.setFillColor(band.fill);
        canvas.drawRect(0, top, size.x, h);
        canvas.fillPath();
        canvas.restoreContext();
        // Top edge
        canvas.saveContext();
        canvas.setStrokeColor(band.edge);
        canvas.setLineWidth(0.5);
        canvas.moveTo(0, top);
        canvas.lineTo(size.x, top);
        canvas.strokePath();
        canvas.restoreContext();
        // Bottom edge
        canvas.saveContext();
        canvas.setStrokeColor(band.edge);
        canvas.setLineWidth(0.5);
        canvas.moveTo(0, top + h);
        canvas.lineTo(size.x, top + h);
        canvas.strokePath();
        canvas.restoreContext();
      }
    }

    // Dashed guide lines.
    for (final g in guides) {
      final gy = yOf(g.y);
      var dx = 0.0;
      while (dx < size.x) {
        canvas.saveContext();
        canvas.setStrokeColor(g.color);
        canvas.setLineWidth(0.6);
        canvas.moveTo(dx, gy);
        canvas.lineTo((dx + 4.0) < size.x ? dx + 4.0 : size.x, gy);
        canvas.strokePath();
        canvas.restoreContext();
        dx += 7.0;
      }
    }

    // Lines (+ optional area fill on the first line only).
    for (int li = 0; li < lines.length; li++) {
      final l = lines[li];
      if (l.points.length < 2) continue;

      if (l.fill) {
        canvas.saveContext();
        canvas.setFillColor(l.color.shade(0.08));
        canvas.moveTo(xOf(l.points[0][0]), yOf(l.points[0][1]));
        for (final p in l.points) canvas.lineTo(xOf(p[0]), yOf(p[1]));
        canvas.lineTo(xOf(l.points.last[0]), 0);
        canvas.lineTo(xOf(l.points.first[0]), 0);
        canvas.closePath();
        canvas.fillPath();
        canvas.restoreContext();
      }

      canvas.saveContext();
      canvas.setStrokeColor(l.color);
      canvas.setLineWidth(l.width);
      canvas.moveTo(xOf(l.points[0][0]), yOf(l.points[0][1]));
      for (final p in l.points) canvas.lineTo(xOf(p[0]), yOf(p[1]));
      canvas.strokePath();
      canvas.restoreContext();

      if (dotColor != null) {
        // Decimate dots if the series is dense — keeps the chart readable.
        final n        = l.points.length;
        final stride   = n > 300 ? (n / 200).ceil()
            : n > 100 ? (n / 100).ceil()
            : 1;
        for (int idx = 0; idx < n; idx += stride) {
          final p = l.points[idx];
          final c = dotColor(li, p[1]);
          if (c == null) continue;
          canvas.saveContext();
          canvas.setFillColor(c);
          canvas.drawEllipse(xOf(p[0]), yOf(p[1]), 2.0, 2.0);
          canvas.fillPath();
          canvas.restoreContext();
        }
        // Always draw the last dot so the line ends with one.
        if (n > 1 && (n - 1) % stride != 0) {
          final p = l.points.last;
          final c = dotColor(li, p[1]);
          if (c != null) {
            canvas.saveContext();
            canvas.setFillColor(c);
            canvas.drawEllipse(xOf(p[0]), yOf(p[1]), 2.0, 2.0);
            canvas.fillPath();
            canvas.restoreContext();
          }
        }
      }
    }
  }

  /// Grade sparkline with colored grade-band background zones.
  static void _paintGradeSparkline(
      PdfGraphics canvas, PdfPoint size, List<double> grades) {
    if (grades.length < 2) return;

    final n = grades.length;

    double xOf(int i) => i / (n - 1) * size.x;
    double yOf(double g) => size.y - (g / 100).clamp(0.0, 1.0) * size.y;

    // Grade band backgrounds (bottom to top: <55 red, 55-75 orange, 75-90 blue, ≥90 green)
    void band(double lo, double hi, PdfColor color) {
      canvas.saveContext();
      canvas.setFillColor(color.shade(0.08));
      canvas.drawRect(0, yOf(hi), size.x, yOf(lo) - yOf(hi));
      canvas.fillPath();
      canvas.restoreContext();
    }
    band(0,   55,  _kError);
    band(55,  75,  _kWarning);
    band(75,  90,  _kBrandBlue);
    band(90,  100, _kSuccess);

    // Fill under line
    canvas.saveContext();
    canvas.setFillColor(_kBrandBlue.shade(0.12));
    canvas.moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(grades[i]));
    canvas.lineTo(xOf(n - 1), 0);
    canvas.lineTo(0, 0);
    canvas.closePath();
    canvas.fillPath();
    canvas.restoreContext();

    // Line
    canvas.saveContext();
    canvas.setStrokeColor(_kBrandBlue);
    canvas.setLineWidth(1.5);
    canvas.moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(grades[i]));
    canvas.strokePath();
    canvas.restoreContext();

    // Dots — colored by grade band
    for (int i = 0; i < n; i++) {
      final g     = grades[i];
      final color = g >= 90 ? _kSuccess : g >= 75 ? _kBrandBlue : g >= 55 ? _kWarning : _kError;
      canvas.saveContext();
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(g), 3.0, 3.0);
      canvas.fillPath();
      canvas.restoreContext();
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
    final bandTop    = yOf(targetMax);
    final bandHeight = yOf(targetMin) - bandTop;
    if (bandHeight > 0) {
      canvas.saveContext();
      canvas.setFillColor(_kSuccess.shade(0.12));
      canvas.drawRect(0, bandTop, size.x, bandHeight);
      canvas.fillPath();
      canvas.restoreContext();

      canvas.saveContext();
      canvas.setStrokeColor(_kSuccess.shade(0.4));
      canvas.setLineWidth(0.5);
      canvas.moveTo(0, bandTop);
      canvas.lineTo(size.x, bandTop);
      canvas.strokePath();
      canvas.restoreContext();

      canvas.saveContext();
      canvas.setStrokeColor(_kSuccess.shade(0.4));
      canvas.setLineWidth(0.5);
      canvas.moveTo(0, bandTop + bandHeight);
      canvas.lineTo(size.x, bandTop + bandHeight);
      canvas.strokePath();
      canvas.restoreContext();
    }

    // Fill
    canvas.saveContext();
    canvas.moveTo(xOf(0), yOf(values[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(values[i]));
    canvas.lineTo(xOf(n - 1), 0);
    canvas.lineTo(0, 0);
    canvas.closePath();
    canvas.setFillColor(lineColor.shade(0.1));
    canvas.fillPath();
    canvas.restoreContext();

    // Line
    canvas.saveContext();
    canvas.setStrokeColor(lineColor);
    canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOf(values[0]));
    for (int i = 1; i < n; i++) canvas.lineTo(xOf(i), yOf(values[i]));
    canvas.strokePath();
    canvas.restoreContext();

    // Dots — colored by in/out target
    for (int i = 0; i < n; i++) {
      final v     = values[i];
      final color = (v >= targetMin && v <= targetMax) ? _kSuccess : _kWarning;
      canvas.saveContext();
      canvas.setFillColor(color);
      canvas.drawEllipse(xOf(i), yOf(v), 2.5, 2.5);
      canvas.fillPath();
      canvas.restoreContext();
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
    if (grade >= 75) return _kBrandMid;
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

class _ChartLine {
  final List<List<double>> points; // each [tSec, value]
  final PdfColor color;
  final double   width;
  final bool     fill;
  const _ChartLine(this.points, this.color,
      {this.width = 1.2, this.fill = false});
}

class _ChartBand {
  final double   min, max;
  final PdfColor fill, edge;
  const _ChartBand(this.min, this.max, this.fill, this.edge);
}

class _ChartGuide {
  final double   y;
  final PdfColor color;
  const _ChartGuide(this.y, this.color);
}

class _TLEventPdf {
  final double    sortKey;
  final String    time;
  final String    title;
  final String    subtitle;
  final PdfColor  dotColor;
  final String?   tip;
  final bool      isBookend;
  final bool      isIgnored;
  const _TLEventPdf({
    required this.sortKey,
    required this.time,
    required this.title,
    required this.subtitle,
    required this.dotColor,
    this.tip,
    this.isBookend = false,
    this.isIgnored = false,
  });
}


class _CompareRow {
  final String  label;
  final String  hint;          // e.g. "5–6 cm target"
  final String  group;         // section grouping
  final List<double?> values;  // raw numeric per slot — null if not applicable
  final String Function(double?) format;
  final bool higherIsBetter;
  final bool noWinner;         // for descriptive rows (no highlighting)
  const _CompareRow({
    required this.label,
    this.hint = '',
    required this.group,
    required this.values,
    required this.format,
    this.higherIsBetter = true,
    this.noWinner = false,
  });
}

class _HeaderPillSpec {
  final String   label;
  final PdfColor color;
  final PdfColor bg;
  const _HeaderPillSpec(this.label, this.color, this.bg);
}
