import 'dart:io';

import 'package:cpr_assist/features/training/screens/session_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExportService
//
// Generates a CSV of all SessionSummary records and shares it via share_plus.
// Uses path_provider to write a temporary file, then shares it as an XFile
// so the OS presents the native share sheet (save to Files, email, etc.).
//
// Only fields present on SessionSummary are exported. Fields that only exist
// on SessionDetail (handsOnRatio, noFlowTime, rateVariability,
// timeToFirstCompression, consecutiveGoodPeak) are not available here —
// SessionSummary is the lightweight projection returned by /sessions/summaries.
//
// Requires: path_provider: ^2.1.2 in pubspec.yaml
//
// Usage:
//   await ExportService.exportSessionsAsCsv(sessions);
// ─────────────────────────────────────────────────────────────────────────────

class ExportService {
  ExportService._();

  // ── CSV column headers ────────────────────────────────────────────────────
  static const _headers = [
    'session_number',
    'date',
    'mode',
    'scenario',
    'duration_sec',
    'total_grade',
    'compression_count',
    'correct_depth',
    'correct_frequency',
    'correct_recoil',
    'depth_rate_combo',
    'correct_posture',
    'leaning_count',
    'over_force_count',
    'no_flow_intervals',
    'rescuer_swap_count',
    'fatigue_onset_index',
    'average_depth_cm',
    'average_frequency_bpm',
    'average_effective_depth_cm',
    'peak_depth_cm',
    'depth_sd',
    'ventilation_count',
    'ventilation_compliance_pct',
    'pulse_checks_prompted',
    'pulse_checks_complied',
    'pulse_detected_final',
    'patient_temperature_c',
    'rescuer_hr_last_pause_bpm',
    'rescuer_spo2_last_pause_pct',
  ];

  /// Generate CSV string from a list of [SessionSummary].
  static String buildCsv(List<SessionSummary> sessions) {
    final sb = StringBuffer();
    sb.writeln(_headers.join(','));

    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      sb.writeln([
        i + 1,
        _escape(s.sessionStart?.toIso8601String() ?? ''),
        _escape(s.mode),
        _escape(s.scenario),
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

  /// Build CSV and share it as a .csv file via the system share sheet.
  /// Returns true if the share sheet was shown, false on error.
  static Future<bool> exportSessionsAsCsv(
      List<SessionSummary> sessions, {
        String filename = 'cpr_assist_sessions',
      }) async {
    if (sessions.isEmpty) return false;

    try {
      final csv  = buildCsv(sessions);
      final date = DateTime.now();
      final name = '${filename}_${date.year}'
          '${date.month.toString().padLeft(2, '0')}'
          '${date.day.toString().padLeft(2, '0')}.csv';

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/$name');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: name)],
        subject: 'CPR Assist — Session Export',
      );

      return true;
    } catch (e) {
      debugPrint('ExportService: export failed — $e');
      return false;
    }
  }

  /// Wrap a value in quotes if it contains a comma, quote, or newline.
  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}