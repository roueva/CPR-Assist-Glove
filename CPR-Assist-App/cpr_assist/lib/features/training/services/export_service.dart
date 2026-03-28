import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:cpr_assist/features/training/services/session_detail.dart';

import 'certificate_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExportService
//
// Two export formats:
//   PDF — pretty, branded, two layouts:
//     • Single session  → analytical (full detail, metrics, grade breakdown)
//     • Multi-session   → summary report (table + grade trend sparkline + stats)
//   CSV — flat tabular export, compatible with Excel / SPSS / R
//
// Entry points:
//   ExportService.exportSingleSessionPdf(detail)
//   ExportService.exportSingleSessionCsv(summary)
//   ExportService.exportMultiSessionPdf(summaries)
//   ExportService.exportSessionsAsCsv(summaries)
//
// All methods share the file via the OS native share sheet (share_plus).
// ─────────────────────────────────────────────────────────────────────────────

// ── Brand colours (PDF-safe PdfColor equivalents of AppColors) ────────────────

const _kBrandBlue    = PdfColor.fromInt(0xFF194E9D);
const _kBrandDark    = PdfColor.fromInt(0xFF335484);
const _kBrandLight   = PdfColor.fromInt(0xFFEDF4F9);
const _kSuccess      = PdfColor.fromInt(0xFF2E7D32);
const _kWarning      = PdfColor.fromInt(0xFFF57C00);
const _kError        = PdfColor.fromInt(0xFFD32F2F);
const _kTextPrimary  = PdfColor.fromInt(0xFF111827);
const _kTextSecond   = PdfColor.fromInt(0xFF4B5563);
const _kTextDisabled = PdfColor.fromInt(0xFF9CA3AF);
const _kDivider      = PdfColor.fromInt(0xFFEEF2F7);
const _kWhite        = PdfColors.white;
const _kBgGrey       = PdfColor.fromInt(0xFFF4F7FB);

// ── CustomPainter is a typedef in the pdf package: ────────────────────────────
// typedef CustomPainter = Function(PdfGraphics canvas, PdfPoint size)
// Do NOT extend it — pass a plain function directly to pw.CustomPaint(painter:)

class ExportService {
  ExportService._();

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /// Single-session analytical PDF — full detail breakdown.
  static Future<bool> exportSingleSessionPdf(
      SessionDetail detail, {
        String? username,
      }) async {
    try {
      final pdf  = await _buildSingleSessionPdf(detail, username: username);
      final date = _dateStamp();
      final name = 'cpr_session_${detail.sessionStart.millisecondsSinceEpoch}_$date.pdf';
      return _sharePdf(pdf, name, 'CPR Assist — Session Report');
    } catch (e) {
      debugPrint('ExportService: PDF single-session failed — $e');
      return false;
    }
  }

  /// Single-session CSV.
  static Future<bool> exportSingleSessionCsv(SessionSummary session) =>
      exportSessionsAsCsv(
        [session],
        filename: 'cpr_session_${session.sessionStart?.millisecondsSinceEpoch ?? 0}',
      );

  /// Multi-session summary PDF — table + trend chart + aggregate stats.
  static Future<bool> exportMultiSessionPdf(
      List<SessionSummary> sessions, {
        String? username,
      }) async {
    if (sessions.isEmpty) return false;
    try {
      final pdf  = await _buildMultiSessionPdf(sessions, username: username);
      final date = _dateStamp();
      final name = 'cpr_sessions_${sessions.length}_$date.pdf';
      return _sharePdf(pdf, name, 'CPR Assist — Session History Report');
    } catch (e) {
      debugPrint('ExportService: PDF multi-session failed — $e');
      return false;
    }
  }

  /// Certificate PDF for a specific milestone.
  static Future<bool> exportCertificate({
    required String              username,
    required CertificateMilestone milestone,
  }) async {
    try {
      final pdf  = await _buildCertificatePdf(
          username: username, milestone: milestone);
      final name = 'cpr_cert_${milestone.id}_${_dateStamp()}.pdf';
      return _sharePdf(pdf, name, 'CPR Assist — ${milestone.title} Certificate');
    } catch (e) {
      debugPrint('ExportService: certificate failed — $e');
      return false;
    }
  }

  /// CSV export — one row per session.
  static Future<bool> exportSessionsAsCsv(
      List<SessionSummary> sessions, {
        String filename = 'cpr_assist_sessions',
      }) async {
    if (sessions.isEmpty) return false;
    try {
      final csv  = _buildCsv(sessions);
      final date = _dateStamp();
      final name = '${filename}_$date.csv';
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: name)],
        subject: 'CPR Assist — Session Data Export',
      );
      return true;
    } catch (e) {
      debugPrint('ExportService: CSV export failed — $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — SINGLE SESSION (analytical)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildSingleSessionPdf(
      SessionDetail s, {
        String? username,
      }) async {
    final doc          = pw.Document();
    final roboto       = await PdfGoogleFonts.robotoRegular();
    final robotoBold   = await PdfGoogleFonts.robotoBold();
    final robotoMedium = await PdfGoogleFonts.robotoMedium();
    final theme        = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    final isTraining  = s.isTraining;
    final isPediatric = s.scenario == 'pediatric';
    final depthMin    = isPediatric ? 4.0 : 5.0;
    final depthMax    = isPediatric ? 5.0 : 6.0;

    doc.addPage(
      pw.MultiPage(
        theme:      theme,
        pageFormat: PdfPageFormat.a4,
        margin:     const pw.EdgeInsets.all(32),
        header: (ctx) => _pageHeader(
          robotoBold, robotoMedium,
          title:     isTraining ? 'Training Session Report' : 'Emergency Session Record',
          subtitle:  s.dateTimeFormatted,
          username:  username,
          mode:      isTraining ? 'TRAINING' : 'EMERGENCY',
          modeColor: isTraining ? _kWarning : _kError,
        ),
        footer: (ctx) => _pageFooter(roboto, ctx),
        build: (ctx) => [

          if (isTraining) ...[
            _gradeHero(robotoBold, robotoMedium, s.totalGrade, s.scenario),
            pw.SizedBox(height: 16),
          ],

          _summaryStrip(robotoBold, robotoMedium, [
            _Cell('Duration',     s.durationFormatted),
            _Cell('Compressions', '${s.compressionCount}'),
            _Cell('Avg Rate',     s.averageFrequency > 0 ? '${s.averageFrequency.round()} BPM' : '—'),
            _Cell('Avg Depth',    s.averageDepth > 0 ? '${s.averageDepth.toStringAsFixed(1)} cm' : '—'),
          ]),
          pw.SizedBox(height: 20),

          if (isTraining) ...[
            _sectionTitle(robotoBold, 'Quality Breakdown'),
            pw.SizedBox(height: 8),
            _metricsGrid(robotoMedium, roboto, [
              _Metric('Depth Consistency',
                  s.compressionCount > 0 ? '${(s.correctDepth / s.compressionCount * 100).round()}%' : '—',
                  _gradeColorForPct(s.compressionCount > 0 ? s.correctDepth / s.compressionCount : 0)),
              _Metric('Rate Consistency',
                  s.compressionCount > 0 ? '${(s.correctFrequency / s.compressionCount * 100).round()}%' : '—',
                  _gradeColorForPct(s.compressionCount > 0 ? s.correctFrequency / s.compressionCount : 0)),
              _Metric('Full Recoil',
                  s.compressionCount > 0 ? '${(s.correctRecoil / s.compressionCount * 100).round()}%' : '—',
                  _gradeColorForPct(s.compressionCount > 0 ? s.correctRecoil / s.compressionCount : 0)),
              _Metric('Depth + Rate Combo',
                  s.compressionCount > 0 ? '${(s.depthRateCombo / s.compressionCount * 100).round()}%' : '—',
                  _gradeColorForPct(s.compressionCount > 0 ? s.depthRateCombo / s.compressionCount : 0)),
              _Metric('Correct Posture',
                  s.compressionCount > 0 ? '${(s.correctPosture / s.compressionCount * 100).round()}%' : '—',
                  _gradeColorForPct(s.compressionCount > 0 ? s.correctPosture / s.compressionCount : 0)),
              _Metric('Ventilation Compliance',
                  s.ventilationCount > 0 ? '${s.ventilationCompliance.round()}%' : 'No ventilations',
                  s.ventilationCount > 0 ? _gradeColorForPct(s.ventilationCompliance / 100) : _kTextDisabled),
            ]),
            pw.SizedBox(height: 20),
          ],

          // Depth chart — pw.CustomPaint takes a typedef function directly
          if (s.compressions.isNotEmpty) ...[
            _sectionTitle(robotoBold, 'Compression Depth Over Time'),
            pw.SizedBox(height: 8),
            pw.SizedBox(
              height: 80,
              child: pw.CustomPaint(
                painter: (canvas, size) =>
                    _paintDepthChart(canvas, size, s.compressions, depthMin, depthMax),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _legendDot(roboto, _kBrandBlue, 'Depth (cm)'),
                _legendDot(roboto, _kSuccess,
                    'Target ${depthMin.toStringAsFixed(0)}–${depthMax.toStringAsFixed(0)} cm'),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          _sectionTitle(robotoBold, 'Session Metrics'),
          pw.SizedBox(height: 8),
          _detailTable(robotoMedium, roboto, [
            if (s.averageDepth > 0)
              _Row('Average Depth', '${s.averageDepth.toStringAsFixed(1)} cm',
                  note: 'Target: ${depthMin.toStringAsFixed(0)}–${depthMax.toStringAsFixed(0)} cm'),
            if (s.averageEffectiveDepth > 0)
              _Row('Effective Depth (angle-corrected)', '${s.averageEffectiveDepth.toStringAsFixed(1)} cm'),
            if (s.peakDepth > 0)
              _Row('Peak Depth', '${s.peakDepth.toStringAsFixed(1)} cm'),
            if (s.depthSD > 0)
              _Row('Depth Variability (SD)', '${s.depthSD.toStringAsFixed(2)} cm',
                  note: 'Lower = more consistent'),
            _Row('Average Rate',
                s.averageFrequency > 0 ? '${s.averageFrequency.round()} BPM' : '—',
                note: 'Target: 100–120 BPM'),
            if (s.handsOnRatio > 0)
              _Row('Hands-On Time (CCF)', '${(s.handsOnRatio * 100).round()}%',
                  note: 'Target ≥ 80%'),
            if (s.noFlowTime > 0)
              _Row('No-Flow Time', '${s.noFlowTime.toStringAsFixed(1)} s',
                  note: '${s.noFlowIntervals} unplanned pause(s)'),
            if (s.timeToFirstCompression > 0)
              _Row('Time to First Compression',
                  '${s.timeToFirstCompression.toStringAsFixed(1)} s'),
            if (s.consecutiveGoodPeak > 0)
              _Row('Best Compression Streak', '${s.consecutiveGoodPeak} compressions'),
            if (s.leaningCount > 0)
              _Row('Leaning Detected', '${s.leaningCount}×', isAlert: true),
            if (s.overForceCount > 0)
              _Row('Over-Force Events', '${s.overForceCount}×', isAlert: true),
            if (s.fatigueOnsetIndex > 0)
              _Row('Fatigue Onset', 'Compression #${s.fatigueOnsetIndex}', isAlert: true),
            if (s.ventilationCount > 0) ...[
              _Row('Ventilation Cycles', '${s.ventilationCount}'),
              _Row('Ventilation Compliance', '${s.ventilationCompliance.round()}%'),
            ],
          ]),
          pw.SizedBox(height: 20),

          if (s.rescuerHRLastPause != null ||
              s.rescuerSpO2LastPause != null ||
              s.patientTemperature != null) ...[
            _sectionTitle(robotoBold, 'Biometrics'),
            pw.SizedBox(height: 8),
            _detailTable(robotoMedium, roboto, [
              if (s.rescuerHRLastPause != null)
                _Row('Rescuer Heart Rate (last pause)',
                    '${s.rescuerHRLastPause!.toStringAsFixed(0)} BPM'),
              if (s.rescuerSpO2LastPause != null)
                _Row('Rescuer SpO2 (last pause)',
                    '${s.rescuerSpO2LastPause!.toStringAsFixed(0)}%'),
              if (s.patientTemperature != null)
                _Row('Patient Skin Temperature',
                    '${s.patientTemperature!.toStringAsFixed(1)} C',
                    note: 'Measured via fingertip sensor'),
              if (s.ambientTempStart != null)
                _Row('Room Temperature (start)',
                    '${s.ambientTempStart!.toStringAsFixed(1)} C',
                    note: 'Ambient — not patient or rescuer'),
            ]),
            pw.SizedBox(height: 20),
          ],

          if (s.note != null && s.note!.isNotEmpty) ...[
            _sectionTitle(robotoBold, 'Note'),
            pw.SizedBox(height: 8),
            pw.Container(
              width:   double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color:        _kBgGrey,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Text(s.note!,
                  style: pw.TextStyle(font: roboto, fontSize: 11, color: _kTextPrimary)),
            ),
          ],
        ],
      ),
    );

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF — MULTI SESSION (summary report)
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildMultiSessionPdf(
      List<SessionSummary> sessions, {
        String? username,
      }) async {
    final doc          = pw.Document();
    final roboto       = await PdfGoogleFonts.robotoRegular();
    final robotoBold   = await PdfGoogleFonts.robotoBold();
    final robotoMedium = await PdfGoogleFonts.robotoMedium();
    final theme        = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    final trainingSessions  = sessions.where((s) => s.isTraining && s.totalGrade > 0).toList();
    final emergencySessions = sessions.where((s) => s.isEmergency).toList();
    final avgGrade = trainingSessions.isEmpty
        ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a + b) /
        trainingSessions.length;
    final bestGrade = trainingSessions.isEmpty
        ? 0.0
        : trainingSessions.map((s) => s.totalGrade).reduce((a, b) => a > b ? a : b);
    final totalCompressions =
    sessions.fold<int>(0, (sum, s) => sum + s.compressionCount);

    doc.addPage(
      pw.MultiPage(
        theme:      theme,
        pageFormat: PdfPageFormat.a4,
        margin:     const pw.EdgeInsets.all(32),
        header: (ctx) => _pageHeader(
          robotoBold, robotoMedium,
          title:    'CPR Training History Report',
          subtitle: '${sessions.length} sessions · Generated ${_dateStampFull()}',
          username: username,
        ),
        footer: (ctx) => _pageFooter(roboto, ctx),
        build: (ctx) => [

          _summaryStrip(robotoBold, robotoMedium, [
            _Cell('Total Sessions', '${sessions.length}'),
            _Cell('Training',       '${trainingSessions.length}'),
            _Cell('Emergency',      '${emergencySessions.length}'),
            _Cell('Compressions',   totalCompressions > 999
                ? '${(totalCompressions / 1000).toStringAsFixed(1)}k'
                : '$totalCompressions'),
          ]),
          pw.SizedBox(height: 20),

          if (trainingSessions.isNotEmpty) ...[
            _sectionTitle(robotoBold, 'Training Performance'),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 1,
                  child: _statPanel(robotoBold, robotoMedium, [
                    _Cell('Average Grade', '${avgGrade.toStringAsFixed(1)}%'),
                    _Cell('Best Grade',    '${bestGrade.toStringAsFixed(1)}%'),
                    _Cell('Sessions Graded', '${trainingSessions.length}'),
                  ]),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  flex: 2,
                  child: _gradeSparklinePanel(
                    roboto, robotoMedium, robotoBold,
                    trainingSessions.reversed.toList(),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          _sectionTitle(robotoBold, 'All Sessions'),
          pw.SizedBox(height: 8),
          _sessionTable(robotoBold, robotoMedium, roboto, sessions),
        ],
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> _buildCertificatePdf({
    required String               username,
    required CertificateMilestone milestone,
  }) async {
    final doc        = pw.Document();
    final roboto     = await PdfGoogleFonts.robotoRegular();
    final robotoBold = await PdfGoogleFonts.robotoBold();
    final robotoMedium = await PdfGoogleFonts.robotoMedium();
    final theme      = pw.ThemeData.withFont(base: roboto, bold: robotoBold);

    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December',
    ];
    final dateStr = milestone.earnedDate != null
        ? '${milestone.earnedDate!.day} ${months[milestone.earnedDate!.month - 1]} ${milestone.earnedDate!.year}'
        : _dateStampFull();

    doc.addPage(
      pw.Page(
        theme:      theme,
        pageFormat: PdfPageFormat.a4.landscape,
        margin:     const pw.EdgeInsets.all(40),
        build: (ctx) => pw.Stack(
          children: [
            // ── Outer border ──────────────────────────────────────────────────
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _kBrandBlue, width: 3),
                borderRadius: pw.BorderRadius.circular(8),
              ),
            ),
            // ── Inner border ──────────────────────────────────────────────────
            pw.Positioned(
              left: 8, right: 8, top: 8, bottom: 8,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color: _kBrandBlue.shade(0.35), width: 1),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
              ),
            ),
            // ── Content ───────────────────────────────────────────────────────
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 48, vertical: 36),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  // Header row: logo text + AUTH tag
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('CPR Assist',
                          style: pw.TextStyle(
                              font: robotoBold, fontSize: 13,
                              color: _kBrandBlue)),
                      pw.Text(
                        'AUTH Biomedical Engineering · Prof. P. Bamidis',
                        style: pw.TextStyle(
                            font: roboto, fontSize: 9,
                            color: _kTextDisabled),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 16),

                  // Divider
                  pw.Container(height: 1, color: _kBrandBlue.shade(0.3)),
                  pw.SizedBox(height: 24),

                  // "Certificate of Achievement"
                  pw.Text(
                    'Certificate of Achievement',
                    style: pw.TextStyle(
                        font: roboto, fontSize: 13,
                        color: _kTextSecond,
                        letterSpacing: 3),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 8),

                  // Certificate title
                  pw.Text(
                    milestone.title,
                    style: pw.TextStyle(
                        font: robotoBold, fontSize: 32,
                        color: _kBrandBlue),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 24),

                  // "This certifies that"
                  pw.Text(
                    'This certifies that',
                    style: pw.TextStyle(
                        font: roboto, fontSize: 12,
                        color: _kTextSecond),
                  ),
                  pw.SizedBox(height: 8),

                  // Username
                  pw.Text(
                    username,
                    style: pw.TextStyle(
                        font: robotoBold, fontSize: 22,
                        color: _kTextPrimary),
                  ),
                  pw.SizedBox(height: 8),

                  // Description
                  pw.Text(
                    'has successfully completed the requirement:',
                    style: pw.TextStyle(
                        font: roboto, fontSize: 11,
                        color: _kTextSecond),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    milestone.subtitle,
                    style: pw.TextStyle(
                        font: robotoMedium, fontSize: 13,
                        color: _kTextPrimary),
                    textAlign: pw.TextAlign.center,
                  ),

                  pw.SizedBox(height: 24),
                  pw.Container(height: 1, color: _kDivider),
                  pw.SizedBox(height: 16),

                  // Date + issued by row
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('Date',
                              style: pw.TextStyle(
                                  font: roboto, fontSize: 9,
                                  color: _kTextDisabled)),
                          pw.SizedBox(height: 2),
                          pw.Text(dateStr,
                              style: pw.TextStyle(
                                  font: robotoBold, fontSize: 11,
                                  color: _kTextPrimary)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text('CPR Assist Training System',
                              style: pw.TextStyle(
                                  font: robotoBold, fontSize: 10,
                                  color: _kBrandBlue)),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Aristotle University of Thessaloniki',
                            style: pw.TextStyle(
                                font: roboto, fontSize: 9,
                                color: _kTextDisabled),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Research Ethics Approval',
                              style: pw.TextStyle(
                                  font: roboto, fontSize: 9,
                                  color: _kTextDisabled)),
                          pw.SizedBox(height: 2),
                          pw.Text('ΕΗΔΕ — AUTH',
                              style: pw.TextStyle(
                                  font: robotoBold, fontSize: 11,
                                  color: _kTextPrimary)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CSV
  // ═══════════════════════════════════════════════════════════════════════════

  static const _csvHeaders = [
    'session_number', 'date', 'mode', 'scenario',
    'duration_sec', 'total_grade',
    'compression_count', 'correct_depth', 'correct_frequency',
    'correct_recoil', 'depth_rate_combo', 'correct_posture',
    'leaning_count', 'over_force_count', 'no_flow_intervals',
    'rescuer_swap_count', 'fatigue_onset_index',
    'average_depth_cm', 'average_frequency_bpm',
    'average_effective_depth_cm', 'peak_depth_cm', 'depth_sd',
    'depth_consistency_pct', 'freq_consistency_pct',
    'ventilation_count', 'ventilation_compliance_pct',
    'pulse_checks_prompted', 'pulse_checks_complied', 'pulse_detected_final',
    'patient_temperature_c', 'rescuer_hr_last_pause_bpm', 'rescuer_spo2_last_pause_pct',
  ];

  static String _buildCsv(List<SessionSummary> sessions) {
    final sb = StringBuffer();
    sb.writeln(_csvHeaders.join(','));
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      sb.writeln([
        i + 1,
        _csvEscape(s.sessionStart?.toIso8601String() ?? ''),
        _csvEscape(s.mode),
        _csvEscape(s.scenario),
        s.sessionDuration,
        s.totalGrade.toStringAsFixed(2),
        s.compressionCount,
        s.correctDepth,
        s.correctFrequency,
        s.correctRecoil,
        s.depthRateCombo,
        s.correctPosture,
        s.leaningCount,
        s.overForceCount,
        s.noFlowIntervals,
        s.rescuerSwapCount,
        s.fatigueOnsetIndex,
        s.averageDepth.toStringAsFixed(2),
        s.averageFrequency.toStringAsFixed(2),
        s.averageEffectiveDepth.toStringAsFixed(2),
        s.peakDepth.toStringAsFixed(2),
        s.depthSD.toStringAsFixed(2),
        s.depthConsistency.toStringAsFixed(1),
        s.frequencyConsistency.toStringAsFixed(1),
        s.ventilationCount,
        s.ventilationCompliance.toStringAsFixed(1),
        s.pulseChecksPrompted,
        s.pulseChecksComplied,
        s.pulseDetectedFinal ? 1 : 0,
        s.patientTemperature?.toStringAsFixed(1) ?? '',
        s.rescuerHRLastPause?.toStringAsFixed(1) ?? '',
        s.rescuerSpO2LastPause?.toStringAsFixed(1) ?? '',
      ].join(','));
    }
    return sb.toString();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PDF BUILDING BLOCKS
  // ═══════════════════════════════════════════════════════════════════════════

  static pw.Widget _pageHeader(
      pw.Font bold,
      pw.Font medium, {
        required String title,
        required String subtitle,
        String?   username,
        String?   mode,
        PdfColor? modeColor,
      }) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _kDivider, width: 1)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 12),
      margin:  const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 6, height: 22,
                      decoration: pw.BoxDecoration(
                        color:        _kBrandBlue,
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(title,
                        style: pw.TextStyle(font: bold, fontSize: 16, color: _kTextPrimary)),
                    if (mode != null) ...[
                      pw.SizedBox(width: 10),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color:        (modeColor ?? _kBrandBlue).shade(0.1),
                          borderRadius: pw.BorderRadius.circular(999),
                          border:       pw.Border.all(color: modeColor ?? _kBrandBlue, width: 0.8),
                        ),
                        child: pw.Text(mode,
                            style: pw.TextStyle(font: bold, fontSize: 8,
                                color: modeColor ?? _kBrandBlue)),
                      ),
                    ],
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(subtitle,
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(), fontSize: 10, color: _kTextSecond)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('CPR Assist',
                  style: pw.TextStyle(font: bold, fontSize: 11, color: _kBrandBlue)),
              if (username != null)
                pw.Text(username,
                    style: pw.TextStyle(
                        font: pw.Font.helvetica(), fontSize: 9, color: _kTextDisabled)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter(pw.Font font, pw.Context ctx) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _kDivider, width: 1)),
      ),
      padding: const pw.EdgeInsets.only(top: 8),
      margin:  const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Generated by CPR Assist  ·  AUTH BME Thesis',
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
        ],
      ),
    );
  }

  static pw.Widget _gradeHero(
      pw.Font bold, pw.Font medium, double grade, String scenario) {
    final color = _gradeColor(grade);
    final label = grade >= 90 ? 'Excellent!'
        : grade >= 75 ? 'Good job!'
        : grade >= 55 ? 'Keep it up!'
        : 'Keep practicing!';
    final scenarioLabel = scenario == 'pediatric' ? 'PEDIATRIC'
        : scenario == 'timed_endurance' ? 'ENDURANCE'
        : 'STANDARD ADULT';

    // Grade bar fill: use a Stack with two Containers instead of FractionallySizedBox
    // (FractionallySizedBox is a Flutter widget — it doesn't exist in the pdf package)
    final pct = (grade / 100).clamp(0.0, 1.0);

    return pw.Container(
      width:   double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
          colors: [_kBrandBlue, _kBrandDark],
          begin:  pw.Alignment.topLeft,
          end:    pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Row(
        children: [
          // Grade circle
          pw.Container(
            width:  90, height: 90,
            decoration: pw.BoxDecoration(
              shape:  pw.BoxShape.circle,
              border: pw.Border.all(color: _kWhite.shade(0.4), width: 2),
              color:  _kWhite.shade(0.12),
            ),
            child: pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('${grade.toStringAsFixed(0)}%',
                      style: pw.TextStyle(font: bold, fontSize: 24, color: _kWhite)),
                  pw.Text(label,
                      style: pw.TextStyle(
                          font: medium, fontSize: 8, color: _kWhite.shade(0.8))),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 20),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color:        _kWhite.shade(0.15),
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                  child: pw.Text(scenarioLabel,
                      style: pw.TextStyle(font: bold, fontSize: 9, color: _kWhite)),
                ),
                pw.SizedBox(height: 10),
                // Grade bar label row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Grade',
                        style: pw.TextStyle(
                            font: bold, fontSize: 9, color: _kWhite.shade(0.7))),
                    pw.Text('${grade.toStringAsFixed(1)}%',
                        style: pw.TextStyle(font: bold, fontSize: 9, color: _kWhite)),
                  ],
                ),
                pw.SizedBox(height: 4),
                // Grade bar: track + filled portion using Stack
                pw.Stack(
                  children: [
                    // Track
                    pw.Container(
                      height: 6,
                      decoration: pw.BoxDecoration(
                        color:        _kWhite.shade(0.2),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                    ),
                    // Fill — use pw.LayoutBuilder alternative: wrap in pw.Row
                    pw.Row(
                      children: [
                        pw.Expanded(
                          flex: (pct * 100).round(),
                          child: pw.Container(
                            height: 6,
                            decoration: pw.BoxDecoration(
                              color:        color,
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        if ((100 - (pct * 100).round()) > 0)
                          pw.Expanded(
                            flex: 100 - (pct * 100).round(),
                            child: pw.SizedBox(height: 6),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryStrip(
      pw.Font bold,
      pw.Font medium,
      List<_Cell> cells,
      ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color:        _kBrandDark,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Row(
        children: cells.map((c) {
          final isLast = cells.last == c;
          return pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: pw.BoxDecoration(
                border: isLast
                    ? null
                    : const pw.Border(
                    right: pw.BorderSide(color: _kWhite, width: 0.15)),
              ),
              child: pw.Column(
                children: [
                  pw.Text(c.value,
                      style: pw.TextStyle(font: bold, fontSize: 18, color: _kWhite),
                      textAlign: pw.TextAlign.center),
                  pw.SizedBox(height: 3),
                  pw.Text(c.label,
                      style: pw.TextStyle(
                          font: medium, fontSize: 8, color: _kWhite.shade(0.6)),
                      textAlign: pw.TextAlign.center),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _statPanel(pw.Font bold, pw.Font medium, List<_Cell> cells) {
    return pw.Container(
      padding:    const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color:        _kBrandLight,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: cells.map((c) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(c.label,
                  style: pw.TextStyle(font: medium, fontSize: 9, color: _kTextSecond)),
              pw.SizedBox(height: 2),
              pw.Text(c.value,
                  style: pw.TextStyle(font: bold, fontSize: 16, color: _kBrandBlue)),
            ],
          ),
        )).toList(),
      ),
    );
  }

  static pw.Widget _gradeSparklinePanel(
      pw.Font font,
      pw.Font medium,
      pw.Font bold,
      List<SessionSummary> sessions,
      ) {
    if (sessions.length < 2) {
      return pw.Container(
        height:  100,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color:        _kBgGrey,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Center(
          child: pw.Text('Not enough sessions for trend',
              style: pw.TextStyle(font: font, fontSize: 10, color: _kTextDisabled)),
        ),
      );
    }

    final grades = sessions.map((s) => s.totalGrade).toList();

    return pw.Container(
      padding:    const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color:        _kBgGrey,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Grade Trend  (Training sessions)',
              style: pw.TextStyle(font: bold, fontSize: 10, color: _kTextPrimary)),
          pw.SizedBox(height: 8),
          // CustomPainter in pdf package is a typedef: Function(PdfGraphics, PdfPoint)
          // Pass the function directly — do NOT create a class
          pw.SizedBox(
            height: 70,
            child: pw.CustomPaint(
              painter: (canvas, size) => _paintSparkline(canvas, size, grades),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(sessions.first.dateFormatted,
                  style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
              pw.Text(sessions.last.dateFormatted,
                  style: pw.TextStyle(font: font, fontSize: 8, color: _kTextDisabled)),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _metricsGrid(
      pw.Font medium, pw.Font font, List<_Metric> metrics) {
    const cols = 3;
    final rows = <pw.Widget>[];
    for (var i = 0; i < metrics.length; i += cols) {
      final rowItems = metrics.skip(i).take(cols).toList();
      rows.add(pw.Row(
        children: rowItems.map((m) => pw.Expanded(
          child: pw.Container(
            margin:  const pw.EdgeInsets.only(right: 6, bottom: 6),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color:        _kBgGrey,
              borderRadius: pw.BorderRadius.circular(8),
              border:       pw.Border.all(color: _kDivider, width: 0.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(m.value,
                    style: pw.TextStyle(font: medium, fontSize: 16, color: m.color)),
                pw.SizedBox(height: 2),
                pw.Text(m.label,
                    style: pw.TextStyle(font: font, fontSize: 8, color: _kTextSecond)),
              ],
            ),
          ),
        )).toList(),
      ));
    }
    return pw.Column(children: rows);
  }

  static pw.Widget _detailTable(
      pw.Font medium, pw.Font font, List<_Row> rows) {
    if (rows.isEmpty) return pw.SizedBox.shrink();
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kBrandLight),
          children: [
            _tableCell(medium, 'Metric', isHeader: true),
            _tableCell(medium, 'Value',  isHeader: true, align: pw.TextAlign.right),
          ],
        ),
        ...rows.map((r) => pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(r.label,
                      style: pw.TextStyle(
                          font: medium, fontSize: 9,
                          color: r.isAlert ? _kError : _kTextPrimary)),
                  if (r.note != null)
                    pw.Text(r.note!,
                        style: pw.TextStyle(
                            font: pw.Font.helvetica(),
                            fontSize: 8,
                            color: _kTextDisabled)),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: pw.Text(r.value,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                      font:     medium,
                      fontSize: 10,
                      color:    r.isAlert ? _kError : _kTextPrimary)),
            ),
          ],
        )),
      ],
    );
  }

  static pw.Widget _sessionTable(
      pw.Font bold,
      pw.Font medium,
      pw.Font font,
      List<SessionSummary> sessions,
      ) {
    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _kDivider, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FixedColumnWidth(60),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.4),
        5: const pw.FlexColumnWidth(1.2),
        6: const pw.FlexColumnWidth(1.2),
        7: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _kBrandDark),
          children: [
            _tableCell(bold, '#',            isHeader: true, isDark: true),
            _tableCell(bold, 'Date',         isHeader: true, isDark: true),
            _tableCell(bold, 'Mode',         isHeader: true, isDark: true),
            _tableCell(bold, 'Duration',     isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Compressions', isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Avg Depth',    isHeader: true, isDark: true, align: pw.TextAlign.right),
            _tableCell(bold, 'Avg Rate',     isHeader: true, isDark: true, align: pw.TextAlign.right),
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
              _tableCell(font, s.durationFormatted, align: pw.TextAlign.right),
              _tableCell(font, '${s.compressionCount}', align: pw.TextAlign.right),
              _tableCell(font,
                  s.averageDepth > 0
                      ? '${s.averageDepth.toStringAsFixed(1)} cm'
                      : '—',
                  align: pw.TextAlign.right),
              _tableCell(font,
                  s.averageFrequency > 0
                      ? '${s.averageFrequency.round()} BPM'
                      : '—',
                  align: pw.TextAlign.right),
              _tableCell(bold,
                  s.isEmergency ? '—' : '${s.totalGrade.toStringAsFixed(1)}%',
                  align: pw.TextAlign.right, color: gradeColor),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _tableCell(
      pw.Font font,
      String text, {
        bool      isHeader = false,
        bool      isDark   = false,
        pw.TextAlign align = pw.TextAlign.left,
        PdfColor? color,
      }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font:     font,
          fontSize: isHeader ? 8 : 9,
          color:    color ??
              (isDark ? _kWhite : (isHeader ? _kTextPrimary : _kTextSecond)),
        ),
      ),
    );
  }

  static pw.Widget _tableModeCell(pw.Font bold, SessionSummary s) {
    final label = s.isEmergency ? 'Emergency'
        : s.isNoFeedback ? 'No-Feedback'
        : 'Training';
    final color = s.isEmergency ? _kError : _kWarning;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: pw.BoxDecoration(
          color:        color.shade(0.1),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Text(label,
            style: pw.TextStyle(font: bold, fontSize: 8, color: color)),
      ),
    );
  }

  static pw.Widget _sectionTitle(pw.Font bold, String title) {
    return pw.Row(
      children: [
        pw.Container(
          width: 3, height: 14,
          decoration: pw.BoxDecoration(
            color:        _kBrandBlue,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 6),
        pw.Text(title,
            style: pw.TextStyle(font: bold, fontSize: 11, color: _kTextPrimary)),
      ],
    );
  }

  static pw.Widget _legendDot(pw.Font font, PdfColor color, String label) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8, height: 8,
          decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: color),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label,
            style: pw.TextStyle(font: font, fontSize: 8, color: _kTextSecond)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CANVAS PAINTERS
  //
  // CustomPainter in the pdf package is a typedef:
  //   typedef CustomPainter = Function(PdfGraphics canvas, PdfPoint size)
  //
  // Pass these as plain functions — do NOT create classes extending CustomPainter.
  // ═══════════════════════════════════════════════════════════════════════════

  static void _paintSparkline(
      PdfGraphics canvas, PdfPoint size, List<double> grades) {
    if (grades.length < 2) return;

    final n    = grades.length;
    final minG = grades.reduce((a, b) => a < b ? a : b).clamp(0.0, 100.0);
    final maxG = grades.reduce((a, b) => a > b ? a : b).clamp(0.0, 100.0);
    final range = (maxG - minG) < 10 ? 20.0 : (maxG - minG) * 1.2;
    final mid   = (minG + maxG) / 2;
    final lo    = (mid - range / 2).clamp(0.0, 100.0);
    final hi    = lo + range;

    double xOf(int i) => i / (n - 1) * size.x;
    double yOf(double g) =>
        size.y - ((g - lo) / (hi - lo)).clamp(0.0, 1.0) * size.y;

    // Fill area
    canvas.setFillColor(_kBrandBlue.shade(0.1));
    canvas.moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < n; i++) {
      canvas.lineTo(xOf(i), yOf(grades[i]));
    }
    canvas.lineTo(xOf(n - 1), size.y);
    canvas.lineTo(0, size.y);
    canvas.closePath();
    canvas.fillPath();

    // Line
    canvas.setStrokeColor(_kBrandBlue);
    canvas.setLineWidth(1.5);
    canvas.moveTo(xOf(0), yOf(grades[0]));
    for (int i = 1; i < n; i++) {
      canvas.lineTo(xOf(i), yOf(grades[i]));
    }
    canvas.strokePath();

    // Dots
    for (int i = 0; i < n; i++) {
      canvas.setFillColor(_kBrandBlue);
      canvas.drawEllipse(xOf(i), yOf(grades[i]), 2.5, 2.5);
      canvas.fillPath();
    }
  }

  static void _paintDepthChart(
      PdfGraphics canvas,
      PdfPoint    size,
      List<dynamic> compressions,
      double targetMin,
      double targetMax,
      ) {
    if (compressions.isEmpty) return;

    const maxDepth = 9.0;
    final n = compressions.length;

    double xOf(int i) => i / (n == 1 ? 1 : n - 1) * size.x;
    double yOf(double d) =>
        size.y - (d / maxDepth).clamp(0.0, 1.0) * size.y;

    // Target band
    canvas.setFillColor(_kSuccess.shade(0.12));
    final bandTop    = yOf(targetMax);
    final bandHeight = yOf(targetMin) - bandTop;
    canvas.drawRect(0, bandTop, size.x, bandHeight);
    canvas.fillPath();

    // Depth line fill
    final depths = compressions
        .map<double>((c) => (c.depth as num).toDouble())
        .toList();

    canvas.setFillColor(_kBrandBlue.shade(0.08));
    canvas.moveTo(xOf(0), yOf(depths[0]));
    for (int i = 1; i < n; i++) {
      canvas.lineTo(xOf(i), yOf(depths[i]));
    }
    canvas.lineTo(xOf(n - 1), size.y);
    canvas.lineTo(0, size.y);
    canvas.closePath();
    canvas.fillPath();

    // Depth line stroke
    canvas.setStrokeColor(_kBrandBlue);
    canvas.setLineWidth(1.2);
    canvas.moveTo(xOf(0), yOf(depths[0]));
    for (int i = 1; i < n; i++) {
      canvas.lineTo(xOf(i), yOf(depths[i]));
    }
    canvas.strokePath();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<bool> _sharePdf(
      Uint8List bytes, String name, String subject) async {
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: name)],
      subject: subject,
    );
    return true;
  }

  static String _dateStamp() {
    final d = DateTime.now();
    return '${d.year}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
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

  static String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small data models for PDF builders
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