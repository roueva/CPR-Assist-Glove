import 'compression_event.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionDetail
//
// The full training session record: extends SessionSummary's data with the
// per-compression stream and richer derived metrics.
//
// Flow:
//   BLE start-ping  → BLE service starts accumulating CompressionEvents
//   BLE compression → CompressionEvent added to _events list in real-time
//   BLE end-ping    → SessionDetail.fromBleSession() assembles everything
//   Grade screen    → receives SessionDetail, renders GradeCard
//   Backend         → SessionDetail.toJson() posted to /sessions/detail
//   History screen  → SessionDetail.fromJson() hydrated from backend
//
// File location: features/training/models/session_detail.dart
// ─────────────────────────────────────────────────────────────────────────────

class SessionDetail {
  // ── Identity ────────────────────────────────────────────────────────────────
  final int? id;
  final DateTime sessionStart;
  final DateTime? sessionEnd;

  // ── Core totals (match SessionSummary for backend compatibility) ────────────
  final int    compressionCount;
  final int    correctDepth;
  final int    correctFrequency;
  final int    correctRecoil;
  final int    depthRateCombo;
  final double averageDepth;      // cm
  final double averageFrequency;  // BPM
  final int    sessionDuration;   // seconds
  final double totalGrade;        // 0–100

  // ── New enriched metrics ────────────────────────────────────────────────────

  /// Seconds of session time with no active compressions.
  final double noFlowTime;

  /// Fraction of session time with active compressions (0.0–1.0).
  /// e.g. 0.85 = hands on chest 85% of the time.
  final double handsOnRatio;

  /// Seconds from session start to the first compression.
  final double timeToFirstCompression;

  /// Fraction of compressions within the 5–6 cm depth target (0–100).
  final double depthConsistency;

  /// Fraction of compressions within the 100–120 BPM rate target (0–100).
  final double frequencyConsistency;

  // ── Rescuer biometrics ──────────────────────────────────────────────────────
  final int?    userHeartRate;
  final double? userTemperature;

  // ── Per-compression stream ──────────────────────────────────────────────────
  /// Full ordered list of compression events captured during the session.
  /// May be empty if the BLE service did not stream per-compression data.
  final List<CompressionEvent> compressions;

  const SessionDetail({
    this.id,
    required this.sessionStart,
    this.sessionEnd,
    required this.compressionCount,
    required this.correctDepth,
    required this.correctFrequency,
    required this.correctRecoil,
    required this.depthRateCombo,
    required this.averageDepth,
    required this.averageFrequency,
    required this.sessionDuration,
    required this.totalGrade,
    this.noFlowTime               = 0.0,
    this.handsOnRatio             = 1.0,
    this.timeToFirstCompression   = 0.0,
    this.depthConsistency         = 0.0,
    this.frequencyConsistency     = 0.0,
    this.userHeartRate,
    this.userTemperature,
    this.compressions             = const [],
  });

  // ── Derived helpers (shared with SessionSummary) ────────────────────────────

  /// "3:42"
  String get durationFormatted {
    final m = sessionDuration ~/ 60;
    final s = sessionDuration % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// "8 Mar 2026 • 14:35"
  String get dateTimeFormatted {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = sessionStart.hour.toString().padLeft(2, '0');
    final m = sessionStart.minute.toString().padLeft(2, '0');
    return '${sessionStart.day} ${months[sessionStart.month - 1]} ${sessionStart.year} • $h:$m';
  }

  /// Hands-off ratio as a readable percentage string e.g. "15%"
  String get noFlowPct =>
      '${((1.0 - handsOnRatio) * 100).round()}%';

  /// Hands-on ratio as a readable percentage string e.g. "85%"
  String get handsOnPct => '${(handsOnRatio * 100).round()}%';

  // ── Factory: assemble from BLE session data ─────────────────────────────────

  /// Called when the BLE end-ping arrives.
  /// [summaryPacket] — the end-ping data map from the glove.
  /// [events]        — the list of CompressionEvents accumulated during session.
  /// [sessionStart]  — when the session began (recorded at start-ping).
  /// [sessionDurationSecs] — total seconds (from CPRSessionManager).
  /// [totalGrade]    — pre-calculated by SessionService.calculateGrade().
  factory SessionDetail.fromBleSession({
    required Map<String, dynamic> summaryPacket,
    required List<CompressionEvent> events,
    required DateTime sessionStart,
    required int sessionDurationSecs,
    required double totalGrade,
  }) {
    // ── Compute enriched metrics from the compression stream ─────────────────

    double depthConsistency     = 0.0;
    double frequencyConsistency = 0.0;
    double timeToFirst          = 0.0;
    double noFlowTime           = 0.0;
    double handsOnRatio         = 1.0;

    if (events.isNotEmpty) {
      final inDepth = events.where((e) => e.isDepthInTarget).length;
      final inFreq  = events.where((e) => e.isFrequencyInTarget).length;

      depthConsistency     = inDepth / events.length * 100;
      frequencyConsistency = inFreq  / events.length * 100;
      timeToFirst          = events.first.timestampSec;

      // No-flow time: gaps > 2s between consecutive compressions
      const noFlowThresholdSec = 2.0;
      for (int i = 1; i < events.length; i++) {
        final gapSec = (events[i].timestampMs - events[i - 1].timestampMs) / 1000.0;
        if (gapSec > noFlowThresholdSec) {
          noFlowTime += gapSec;
        }
      }

      // Also count time before first compression and after last compression
      final lastEventSec = events.last.timestampSec;
      final afterLastSec = sessionDurationSecs - lastEventSec;
      if (afterLastSec > noFlowThresholdSec) noFlowTime += afterLastSec;
      if (timeToFirst > noFlowThresholdSec)  noFlowTime += timeToFirst;

      handsOnRatio = sessionDurationSecs > 0
          ? (1.0 - noFlowTime / sessionDurationSecs).clamp(0.0, 1.0)
          : 1.0;
    }

    return SessionDetail(
      sessionStart:            sessionStart,
      compressionCount:        summaryPacket['totalCompressions'] as int?    ?? 0,
      correctDepth:            summaryPacket['correctDepth']      as int?    ?? 0,
      correctFrequency:        summaryPacket['correctFrequency']  as int?    ?? 0,
      correctRecoil:           summaryPacket['correctRecoil']     as int?    ?? 0,
      depthRateCombo:          summaryPacket['depthRateCombo']    as int?    ?? 0,
      averageDepth:            (summaryPacket['depth']            as num?)?.toDouble() ?? 0.0,
      averageFrequency:        (summaryPacket['frequency']        as num?)?.toDouble() ?? 0.0,
      userHeartRate:           summaryPacket['userHeartRate']     as int?,
      userTemperature:         (summaryPacket['userTemperature']  as num?)?.toDouble(),
      sessionDuration:         sessionDurationSecs,
      totalGrade:              totalGrade,
      noFlowTime:              noFlowTime,
      handsOnRatio:            handsOnRatio,
      timeToFirstCompression:  timeToFirst,
      depthConsistency:        depthConsistency,
      frequencyConsistency:    frequencyConsistency,
      compressions:            events,
    );
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    final rawEvents = json['compressions'] as List<dynamic>? ?? [];
    return SessionDetail(
      id:                      json['id']                    as int?,
      compressionCount:        (json['compression_count']   as num).toInt(),
      correctDepth:            (json['correct_depth']        as num).toInt(),
      correctFrequency:        (json['correct_frequency']    as num).toInt(),
      correctRecoil:           (json['correct_recoil']       as num?)?.toInt()    ?? 0,
      depthRateCombo:          (json['depth_rate_combo']     as num?)?.toInt()    ?? 0,
      averageDepth:            (json['average_depth']        as num?)?.toDouble() ?? 0.0,
      averageFrequency:        (json['average_frequency']    as num?)?.toDouble() ?? 0.0,
      sessionDuration:         (json['session_duration']     as num).toInt(),
      totalGrade:              (json['total_grade']          as num?)?.toDouble() ?? 0.0,
      noFlowTime:              (json['no_flow_time']         as num?)?.toDouble() ?? 0.0,
      handsOnRatio:            (json['hands_on_ratio']       as num?)?.toDouble() ?? 1.0,
      timeToFirstCompression:  (json['time_to_first']        as num?)?.toDouble() ?? 0.0,
      depthConsistency:        (json['depth_consistency']    as num?)?.toDouble() ?? 0.0,
      frequencyConsistency:    (json['freq_consistency']     as num?)?.toDouble() ?? 0.0,
      userHeartRate:           (json['user_heart_rate']      as num?)?.toInt(),
      userTemperature:         (json['user_temperature']     as num?)?.toDouble(),
      sessionStart:  DateTime.parse(json['session_start'] as String),
      sessionEnd:    json['session_end'] != null
          ? DateTime.tryParse(json['session_end'] as String)
          : null,
      compressions:  rawEvents
          .map((e) => CompressionEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'compression_count':  compressionCount,
    'correct_depth':      correctDepth,
    'correct_frequency':  correctFrequency,
    'correct_recoil':     correctRecoil,
    'depth_rate_combo':   depthRateCombo,
    'average_depth':      averageDepth,
    'average_frequency':  averageFrequency,
    'session_duration':   sessionDuration,
    'total_grade':        totalGrade,
    'no_flow_time':       noFlowTime,
    'hands_on_ratio':     handsOnRatio,
    'time_to_first':      timeToFirstCompression,
    'depth_consistency':  depthConsistency,
    'freq_consistency':   frequencyConsistency,
    if (userHeartRate    != null) 'user_heart_rate':    userHeartRate,
    if (userTemperature  != null) 'user_temperature':   userTemperature,
    'session_start':      sessionStart.toIso8601String(),
    if (sessionEnd != null) 'session_end': sessionEnd!.toIso8601String(),
    'compressions':       compressions.map((e) => e.toJson()).toList(),
  };
}