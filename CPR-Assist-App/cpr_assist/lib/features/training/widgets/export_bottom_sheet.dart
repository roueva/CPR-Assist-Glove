import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import '../screens/session_service.dart';
import '../services/export_service.dart';
import '../services/session_detail.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExportBottomSheet
//
// Shows a styled bottom sheet letting the user choose:
//   • Format  — PDF (pretty, analytical) or CSV (flat, data-ready)
//   • Scope   — this session only / all sessions / selected sessions
//             (scope options shown depend on where it's called from)
//
// Two static entry points:
//
//   ExportBottomSheet.showForSingleSession(context, detail: d, summary: s)
//     → called from SessionResultsScreen app bar action
//     → always exports the one session; choice is only format
//
//   ExportBottomSheet.showForMultipleSessions(context, sessions: list)
//     → called from SessionHistoryScreen selection mode or bulk action
//     → choice is format; scope is the provided list
// ─────────────────────────────────────────────────────────────────────────────

class ExportBottomSheet extends ConsumerStatefulWidget {
  final SessionDetail?       detail;    // non-null → single session PDF is available
  final SessionSummary?      summary;   // always non-null for single-session entry
  final List<SessionSummary> sessions;  // for multi-session entry

  const ExportBottomSheet._({
    this.detail,
    this.summary,
    this.sessions = const [],
  });

  // ── Entry points ───────────────────────────────────────────────────────────

  static Future<void> showForSingleSession(
      BuildContext context, {
        required SessionSummary summary,
        SessionDetail?          detail,
      }) {
    return showModalBottomSheet<void>(
      context:         context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportBottomSheet._(
        detail:  detail,
        summary: summary,
      ),
    );
  }

  static Future<void> showForMultipleSessions(
      BuildContext context, {
        required List<SessionSummary> sessions,
      }) {
    return showModalBottomSheet<void>(
      context:         context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExportBottomSheet._(sessions: sessions),
    );
  }

  @override
  ConsumerState<ExportBottomSheet> createState() => _ExportBottomSheetState();
}

class _ExportBottomSheetState extends ConsumerState<ExportBottomSheet> {
  _ExportFormat _format = _ExportFormat.pdf;
  _ExportAction _action = _ExportAction.download;
  bool          _isExporting = false;

  bool get _isSingleSession => widget.summary != null;

  String get _sessionCountLabel {
    if (_isSingleSession) return '1 session';
    final n = widget.sessions.length;
    return '$n session${n == 1 ? '' : 's'}';
  }

  Future<void> _doExport() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    final auth = ref.read(authStateProvider);

    try {
      bool ok;
      final download = _action == _ExportAction.download;

      switch (_format) {
        case _ExportFormat.pdf:
          if (_isSingleSession && widget.detail != null) {
            ok = download
                ? await ExportService.downloadSingleSessionPdf(
                widget.detail!, username: auth.username)
                : await ExportService.exportSingleSessionPdf(
                widget.detail!, username: auth.username);
          } else if (_isSingleSession) {
            ok = download
                ? await ExportService.downloadSingleSessionCsv(widget.summary!)
                : await ExportService.exportSingleSessionCsv(widget.summary!);
            if (mounted) UIHelper.showSnackbar(context,
                message: 'Full detail not available — exported as CSV',
                icon: Icons.info_outline_rounded);
          } else {
            ok = download
                ? await ExportService.downloadMultiSessionPdf(
                widget.sessions, username: auth.username)
                : await ExportService.exportMultiSessionPdf(
                widget.sessions, username: auth.username);
          }

        case _ExportFormat.csv:
          if (_isSingleSession) {
            ok = download
                ? await ExportService.downloadSingleSessionCsv(widget.summary!)
                : await ExportService.exportSingleSessionCsv(widget.summary!);
          } else {
            ok = download
                ? await ExportService.downloadSessionsAsCsv(widget.sessions)
                : await ExportService.exportSessionsAsCsv(widget.sessions);
          }

        case _ExportFormat.rawCsv:
        // rawCsv sub-format is handled via the raw data buttons directly
          ok = false;
      }

      if (mounted) {
        context.pop();
        if (ok) {
          UIHelper.showSnackbar(
            context,
            message: Platform.isAndroid
                ? 'Saved to Downloads'
                : 'Choose Save to Files in the share sheet',
            icon: Icons.check_circle_rounded,
          );
        } else {
          UIHelper.showError(context, 'Export failed. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        context.pop();
        UIHelper.showError(context, 'Export failed. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.bottomSheet(),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle — always visible, outside scroll ─────────────────
          const _DragHandle(),
          const SizedBox(height: AppSpacing.md),

          // ── Scrollable content ───────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // ── Title ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Row(
                      children: [
                        Container(
                          width:  AppSpacing.iconXl,
                          height: AppSpacing.iconXl,
                          decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
                          child: const Icon(
                            Icons.download_rounded,
                            color: AppColors.primary,
                            size:  AppSpacing.iconMd,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Export Sessions',
                                  style: AppTypography.heading(size: 17)),
                              Text(
                                _sessionCountLabel,
                                style: AppTypography.caption(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: AppSpacing.lg),

                  // ── Format picker ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FORMAT',
                          style: AppTypography.badge(size: 10, color: AppColors.textDisabled),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _FormatTile(
                                icon:        Icons.picture_as_pdf_rounded,
                                label:       'PDF Report',
                                description: _isSingleSession
                                    ? 'Analytical report\nwith metrics & charts'
                                    : 'Summary report\nwith table & grade trend',
                                selected:    _format == _ExportFormat.pdf,
                                accent:      AppColors.emergency,
                                accentBg:    AppColors.errorBg,
                                onTap:       () => setState(() => _format = _ExportFormat.pdf),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _FormatTile(
                                icon:        Icons.table_chart_outlined,
                                label:       'CSV Summary',
                                description: 'Session metrics\nfor Excel / SPSS / R',
                                selected:    _format == _ExportFormat.csv,
                                accent:      AppColors.success,
                                accentBg:    AppColors.successBg,
                                onTap:       () => setState(() => _format = _ExportFormat.csv),
                              ),
                            ),
                          ],
                        ),
                        if (_isSingleSession && widget.detail != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _FormatTile(
                            icon:        Icons.data_object_rounded,
                            label:       'Raw Data (CSV)',
                            description: 'Per-event data streams — compressions, vitals, ventilations, pulse checks',
                            selected:    _format == _ExportFormat.rawCsv,
                            accent:      AppColors.pediatric,
                            accentBg:    AppColors.pediatricLight,
                            onTap:       () => setState(() => _format = _ExportFormat.rawCsv),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: AppSpacing.lg),

                  // ── Format description ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: _FormatDescription(
                      format:          _format,
                      isSingleSession: _isSingleSession,
                      hasDetail:       widget.detail != null,
                    ),
                  ),

                  // ── Raw data stream buttons ────────────────────────────
                  if (_format == _ExportFormat.rawCsv && widget.detail != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: _RawDataButtons(
                        detail:      widget.detail!,
                        isExporting: _isExporting,
                        onStart:     () => setState(() => _isExporting = true),
                        onDone: (ok) {
                          if (mounted) {
                            setState(() => _isExporting = false);
                            context.pop();
                            if (ok) {
                              UIHelper.showSnackbar(
                                context,
                                message: Platform.isAndroid
                                    ? 'Saved to Downloads'
                                    : 'Choose Save to Files in the share sheet',
                                icon: Icons.check_circle_rounded,
                              );
                            } else {
                              UIHelper.showError(context, 'Export failed. Please try again.');
                            }
                          }
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.lg),

                  // ── Action buttons — hidden when rawCsv selected ───────
                  if (_format != _ExportFormat.rawCsv)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Column(
                        children: [
                          // Primary — Download
                          SizedBox(
                            width:  double.infinity,
                            height: AppSpacing.touchTargetLarge,
                            child: ElevatedButton.icon(
                              onPressed: _isExporting
                                  ? null
                                  : () {
                                setState(() => _action = _ExportAction.download);
                                _doExport();
                              },
                              icon: _isExporting && _action == _ExportAction.download
                                  ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.textOnDark),
                                  ))
                                  : const Icon(Icons.download_rounded),
                              label: Text(
                                _isExporting && _action == _ExportAction.download
                                    ? 'Saving…'
                                    : 'Download ${_format == _ExportFormat.pdf ? 'PDF' : 'CSV'}',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textOnDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(AppSpacing.buttonRadius),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // Secondary — Share
                          SizedBox(
                            width:  double.infinity,
                            height: AppSpacing.touchTargetLarge,
                            child: OutlinedButton.icon(
                              onPressed: _isExporting
                                  ? null
                                  : () {
                                setState(() => _action = _ExportAction.share);
                                _doExport();
                              },
                              icon: _isExporting && _action == _ExportAction.share
                                  ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primary),
                                  ))
                                  : const Icon(Icons.share_rounded),
                              label: Text(
                                _isExporting && _action == _ExportAction.share
                                    ? 'Sharing…'
                                    : 'Share ${_format == _ExportFormat.pdf ? 'PDF' : 'CSV'}',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                  BorderRadius.circular(AppSpacing.buttonRadius),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppSpacing.sm),

                  // ── Cancel ─────────────────────────────────────────────
                  TextButton(
                    onPressed: () => context.pop(),
                    style: TextButton.styleFrom(
                      minimumSize:
                      const Size(double.infinity, AppSpacing.touchTargetMin),
                    ),
                    child: Text('Cancel',
                        style: AppTypography.body(color: AppColors.textSecondary)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Format option tile
// ─────────────────────────────────────────────────────────────────────────────

class _FormatTile extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       description;
  final bool         selected;
  final Color        accent;
  final Color        accentBg;
  final VoidCallback onTap;

  const _FormatTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.accent,
    required this.accentBg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:  const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color:        selected ? accentBg : AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(
            color: selected ? accent : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
            BoxShadow(
              color:      accent.withValues(alpha: 0.12),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ]
              : const [
            BoxShadow(
              color:      AppColors.shadowDefault,
              blurRadius: 6,
              offset:     Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: selected ? accent : AppColors.textSecondary,
                  size:  AppSpacing.iconMd,
                ),
                const Spacer(),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: accent,
                    size:  AppSpacing.iconSm,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: AppTypography.subheading(
                color: selected ? accent : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: AppTypography.caption(
                color: selected ? accent.withValues(alpha: 0.75) : AppColors.textDisabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RawDataButtons extends ConsumerStatefulWidget {
  final SessionDetail detail;
  final bool          isExporting;
  final VoidCallback  onStart;
  final void Function(bool) onDone;

  const _RawDataButtons({
    required this.detail,
    required this.isExporting,
    required this.onStart,
    required this.onDone,
  });

  @override
  ConsumerState<_RawDataButtons> createState() => _RawDataButtonsState();
}

class _RawDataButtonsState extends ConsumerState<_RawDataButtons> {
  String? _active; // key of the stream currently saving/sharing

  Future<void> _run(String key, Future<bool> Function() fn) async {
    if (_active != null) return;
    setState(() => _active = key);
    widget.onStart();
    final ok = await fn();
    if (mounted) setState(() => _active = null);
    widget.onDone(ok);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;

    final streams = [
      if (d.compressions.isNotEmpty)
        _RawStream(
          key:   'compressions',
          label: 'Compressions',
          count: '${d.compressions.length} rows · 25 columns',
          icon:  Icons.compress_rounded,
          color: AppColors.primary,
          downloadFn: () => ExportService.downloadRawCompressionsCsv(d),
          shareFn:    () => ExportService.exportRawCompressionsCsv(d),
        ),
      if (d.rescuerVitals.isNotEmpty)
        _RawStream(
          key:   'vitals',
          label: 'Rescuer Vitals',
          count: '${d.rescuerVitals.length} rows · 13 columns',
          icon:  Icons.monitor_heart_rounded,
          color: AppColors.success,
          downloadFn: () => ExportService.downloadRawRescuerVitalsCsv(d),
          shareFn:    () => ExportService.exportRawRescuerVitalsCsv(d),
        ),
      if (d.ventilations.isNotEmpty)
        _RawStream(
          key:   'ventilations',
          label: 'Ventilations',
          count: '${d.ventilations.length} rows · 9 columns',
          icon:  Icons.air_rounded,
          color: AppColors.warning,
          downloadFn: () => ExportService.downloadRawVentilationsCsv(d),
          shareFn:    () => ExportService.exportRawVentilationsCsv(d),
        ),
      if (d.pulseChecks.isNotEmpty)
        _RawStream(
          key:   'pulse',
          label: 'Pulse Checks',
          count: '${d.pulseChecks.length} rows · 17 columns · PPG waveform',
          icon:  Icons.favorite_rounded,
          color: AppColors.emergency,
          downloadFn: () => ExportService.downloadRawPulseChecksCsv(d),
          shareFn:    () => ExportService.exportRawPulseChecksCsv(d),
        ),
    ];

    if (streams.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text('No raw data available for this session.',
            style: AppTypography.caption(color: AppColors.textDisabled)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── ZIP — all streams in one file ──────────────────────────────────
        _ZipExportTile(
          detail:     d,
          isDisabled: _active != null,
          onDownload: () => _run('zip_dl', () => ExportService.downloadRawDataZip(d)),
          onShare:    () => _run('zip_sh', () => ExportService.exportRawDataZip(d)),
          isDownloading: _active == 'zip_dl',
          isSharing:     _active == 'zip_sh',
        ),
        const SizedBox(height: AppSpacing.md),
        Text('OR DOWNLOAD INDIVIDUALLY',
            style: AppTypography.badge(size: 10, color: AppColors.textDisabled)),
        const SizedBox(height: AppSpacing.sm),
        ...streams.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: _RawStreamTile(
            stream:        s,
            isDownloading: _active == '${s.key}_dl',
            isSharing:     _active == '${s.key}_sh',
            isDisabled:    _active != null,
            onDownload:    () => _run('${s.key}_dl', s.downloadFn),
            onShare:       () => _run('${s.key}_sh', s.shareFn),
          ),
        )),
      ],
    );
  }
}

class _RawStream {
  final String key;
  final String label;
  final String count;
  final IconData icon;
  final Color  color;
  final Future<bool> Function() downloadFn;
  final Future<bool> Function() shareFn;
  const _RawStream({
    required this.key, required this.label, required this.count,
    required this.icon, required this.color,
    required this.downloadFn, required this.shareFn,
  });
}

class _RawStreamTile extends StatelessWidget {
  final _RawStream   stream;
  final bool         isDownloading;
  final bool         isSharing;
  final bool         isDisabled;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _RawStreamTile({
    required this.stream,
    required this.isDownloading,
    required this.isSharing,
    required this.isDisabled,
    required this.onDownload,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      child: ListTile(
        dense: true,
        leading: Container(
          width:  AppSpacing.iconBoxSize,
          height: AppSpacing.iconBoxSize,
          decoration: AppDecorations.iconRounded(
            bg:     stream.color.withValues(alpha: 0.1),
            radius: AppSpacing.cardRadiusSm,
          ),
          child: Icon(stream.icon, color: stream.color, size: AppSpacing.iconSm),
        ),
        title: Text(stream.label,
            style: AppTypography.label(color: AppColors.textPrimary)),
        subtitle: Text(stream.count,
            style: AppTypography.caption(color: AppColors.textDisabled)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Share
            _iconBtn(
              icon: Icons.share_rounded,
              color: stream.color,
              loading: isSharing,
              disabled: isDisabled,
              onTap: onShare,
            ),
            const SizedBox(width: AppSpacing.xs),
            // Download
            _iconBtn(
              icon: Icons.download_rounded,
              color: stream.color,
              loading: isDownloading,
              disabled: isDisabled,
              onTap: onDownload,
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required bool loading,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    if (loading) {
      return SizedBox(
        width: 20, height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    return IconButton(
      icon: Icon(icon,
          color: disabled ? AppColors.textDisabled : color,
          size: AppSpacing.iconMd),
      onPressed: disabled ? null : onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Format description — what's included
// ─────────────────────────────────────────────────────────────────────────────

class _FormatDescription extends StatelessWidget {
  final _ExportFormat format;
  final bool          isSingleSession;
  final bool          hasDetail;

  const _FormatDescription({
    required this.format,
    required this.isSingleSession,
    required this.hasDetail,
  });

  @override
  Widget build(BuildContext context) {
    final items = _getItems();
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      width:   double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.tintedCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INCLUDES',
            style: AppTypography.badge(size: 9, color: AppColors.textDisabled),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.check_rounded,
                  color: AppColors.success,
                  size:  AppSpacing.iconSm,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    item,
                    style: AppTypography.body(size: 12),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  List<String> _getItems() {
    switch (format) {
      case _ExportFormat.pdf:
        if (isSingleSession) {
          return [
            if (hasDetail) 'Charts: depth, rate, force, posture, rescuer vitals over time',
            'Grade hero with progress bar (training) or ROSC outcome (emergency)',
            'Two-column metrics: depth/force group + rate/timing group',
            'Ventilation cycle table with compliance per cycle',
            if (hasDetail) 'Pulse check table with ABSENT/UNCERTAIN/PRESENT classification',
            if (hasDetail) 'Biometrics: rescuer HR, SpO₂, RMSSD, fatigue — patient temp, SpO₂, ambient temp',
            'Session note (if any) · Session ID for traceability',
          ];
        } else {
          return [
            'Grade trend sparkline with colored band zones and trend delta',
            '2×2 metric trend charts: depth, rate, CCF, recoil across sessions',
            'Average metrics grid: depth, rate, consistency, CCF, recoil',
            'Emergency session summary: ROSC rate and total compressions',
            'Full session table with scenario, CCF column, mode badges',
          ];
        }
      case _ExportFormat.csv:
        return [
          '${isSingleSession ? '1 row' : 'All session rows'} · 44 columns',
          'Identity: session ID, date/time UTC, mode, scenario, depth targets',
          'Compression quality: counts + computed percentages for depth, rate, recoil, posture',
          'Metrics: avg depth, effective depth, peak depth, SD, CCF, no-flow time',
          'Ventilation + pulse check results, biometrics, ambient temperature',
          'UTF-8 encoded · compatible with Excel, SPSS, R, Python pandas',
        ];
      case _ExportFormat.rawCsv:
        return [
          'ZIP containing all raw data streams for this session',
          'compressions.csv — 1 row per compression · 25 columns',
          'rescuer_vitals.csv — HR, SpO₂, RMSSD, fatigue over time',
          'ventilations.csv — one row per 30:2 cycle',
          'pulse_checks.csv — classification, PPG waveform data',
          'Includes session_id + elapsed_sec in every file for easy merging',
          'Ideal for signal processing, SPSS, and research analysis',
        ];
    }
  }
}

class _ZipExportTile extends StatelessWidget {
  final SessionDetail detail;
  final bool         isDisabled;
  final bool         isDownloading;
  final bool         isSharing;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _ZipExportTile({
    required this.detail,
    required this.isDisabled,
    required this.isDownloading,
    required this.isSharing,
    required this.onDownload,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final d           = detail;
    final streamCount = (d.compressions.isNotEmpty ? 1 : 0) +
        (d.rescuerVitals.isNotEmpty ? 1 : 0) +
        (d.ventilations.isNotEmpty ? 1 : 0) +
        (d.pulseChecks.isNotEmpty  ? 1 : 0);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryAlt],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            width:  AppSpacing.iconBoxSize,
            height: AppSpacing.iconBoxSize,
            decoration: BoxDecoration(
              color:        AppColors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
            ),
            child: const Icon(Icons.folder_zip_rounded,
                color: AppColors.textOnDark, size: AppSpacing.iconMd),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All Raw Data (ZIP)',
                    style: AppTypography.subheading(color: AppColors.textOnDark)),
                Text('$streamCount data streams · compressions, vitals, ventilations, pulse checks',
                    style: AppTypography.caption(
                        color: AppColors.textOnDark.withValues(alpha: 0.75))),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Share
          _zipBtn(
            icon: Icons.share_rounded,
            loading: isSharing,
            disabled: isDisabled,
            onTap: onShare,
          ),
          const SizedBox(width: AppSpacing.xs),
          // Download
          _zipBtn(
            icon: Icons.download_rounded,
            loading: isDownloading,
            disabled: isDisabled,
            onTap: onDownload,
          ),
        ],
      ),
    );
  }

  Widget _zipBtn({
    required IconData      icon,
    required bool          loading,
    required bool          disabled,
    required VoidCallback  onTap,
  }) {
    if (loading) {
      return const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnDark)));
    }
    return IconButton(
      icon: Icon(icon,
          color: disabled ? AppColors.textOnDark.withValues(alpha: 0.4) : AppColors.textOnDark,
          size: AppSpacing.iconMd),
      onPressed: disabled ? null : onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drag handle
// ─────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: Container(
          width:  AppSpacing.dragHandleWidth,
          height: AppSpacing.dragHandleHeight,
          decoration: BoxDecoration(
            color:        AppColors.divider,
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadiusLg),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Format enum
// ─────────────────────────────────────────────────────────────────────────────

enum _ExportFormat { pdf, csv, rawCsv }
enum _ExportAction { download, share }