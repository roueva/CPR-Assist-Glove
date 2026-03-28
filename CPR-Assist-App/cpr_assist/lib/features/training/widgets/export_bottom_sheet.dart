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
      switch (_format) {
        case _ExportFormat.pdf:
          if (_isSingleSession && widget.detail != null) {
            ok = await ExportService.exportSingleSessionPdf(
              widget.detail!,
              username: auth.username,
            );
          } else if (_isSingleSession) {
            // No detail — fall back to single-row CSV
            ok = await ExportService.exportSingleSessionCsv(widget.summary!);
            if (mounted) {
              UIHelper.showSnackbar(
                context,
                message: 'Full detail not available — exported as CSV',
                icon:    Icons.info_outline_rounded,
              );
            }
          } else {
            ok = await ExportService.exportMultiSessionPdf(
              widget.sessions,
              username: auth.username,
            );
          }

        case _ExportFormat.csv:
          if (_isSingleSession) {
            ok = await ExportService.exportSingleSessionCsv(widget.summary!);
          } else {
            ok = await ExportService.exportSessionsAsCsv(widget.sessions);
          }
      }

      if (mounted) {
        context.pop();
        if (!ok) {
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
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ─────────────────────────────────────────────────────
          const _DragHandle(),
          const SizedBox(height: AppSpacing.md),

          // ── Title ───────────────────────────────────────────────────────────
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

          // ── Format picker ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FORMAT',
                  style: AppTypography.badge(
                    size:  10,
                    color: AppColors.textDisabled,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _FormatTile(
                        icon:        Icons.picture_as_pdf_rounded,
                        label:       'PDF',
                        description: _isSingleSession
                            ? 'Analytical report\nwith metrics & charts'
                            : 'Summary report\nwith table & grade trend',
                        selected:    _format == _ExportFormat.pdf,
                        accent:      AppColors.emergencyRed,
                        accentBg:    AppColors.emergencyBg,
                        onTap:       () => setState(() => _format = _ExportFormat.pdf),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _FormatTile(
                        icon:        Icons.table_chart_outlined,
                        label:       'CSV',
                        description: 'Flat data table\nfor Excel / SPSS / R',
                        selected:    _format == _ExportFormat.csv,
                        accent:      AppColors.success,
                        accentBg:    AppColors.successBg,
                        onTap:       () => setState(() => _format = _ExportFormat.csv),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Format description ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _FormatDescription(
              format:          _format,
              isSingleSession: _isSingleSession,
              hasDetail:       widget.detail != null,
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Action button ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SizedBox(
              width: double.infinity,
              height: AppSpacing.touchTargetLarge,
              child: ElevatedButton.icon(
                onPressed: _isExporting ? null : _doExport,
                icon: _isExporting
                    ? const SizedBox(
                  width:  18,
                  height: 18,
                  child:  CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnDark),
                  ),
                )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  _isExporting
                      ? 'Preparing…'
                      : 'Export as ${_format == _ExportFormat.pdf ? 'PDF' : 'CSV'}',
                ),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Cancel ───────────────────────────────────────────────────────────
          TextButton(
            onPressed: () => context.pop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, AppSpacing.touchTargetMin),
            ),
            child: Text('Cancel',
                style: AppTypography.body(color: AppColors.textSecondary)
                    .copyWith(fontWeight: FontWeight.w600)),
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
          color:        selected ? accentBg : AppColors.surfaceWhite,
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
    if (format == _ExportFormat.pdf) {
      if (isSingleSession) {
        return [
          if (hasDetail) 'Compression depth chart over time',
          'Grade circle with motivational label (training)',
          'Quality breakdown: depth, rate, recoil, posture, ventilation',
          'Detailed metrics table with all sub-scores',
          if (hasDetail) 'Biometrics: rescuer HR, SpO₂, patient temperature',
          'Session note (if any)',
          'Branded header with session date and mode badge',
        ];
      } else {
        return [
          'Aggregate stats: total sessions, compressions, avg & best grade',
          'Grade trend sparkline across all training sessions',
          'Full session table: date, mode, duration, depth, rate, grade',
          'Branded header with your username',
        ];
      }
    } else {
      return [
        '${isSingleSession ? '1 row' : 'All session rows'} with 32 columns',
        'Session number, date, mode, scenario, duration',
        'All compression quality counts and percentages',
        'Average depth, frequency, effective depth, peak depth, SD',
        'Ventilation count and compliance, pulse check results',
        'Rescuer and patient biometrics',
        'Compatible with Excel, SPSS, R, Python pandas',
      ];
    }
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

enum _ExportFormat { pdf, csv }