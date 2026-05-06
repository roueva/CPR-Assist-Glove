part of 'session_results.dart';

// Shared section label — accent bar + title, used in all detail dialogs
Widget _sectionLabel(String text, Color accentColor) {
  return Row(
    children: [
      Container(
        width: 3,
        height: 12,
        margin: const EdgeInsets.only(right: AppSpacing.xs),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
        ),
      ),
      Text(text, style: AppTypography.subheading(size: 12)),
    ],
  );
}


class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: AppTypography.numericDisplay(
                    size: 18, color: AppColors.textOnDark)),
            const SizedBox(height: AppSpacing.xxs),
            Text(label,
                style: AppTypography.badge(
                    size: 8,
                    color: AppColors.textOnDark.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.dividerThickness,
      color: AppColors.textOnDark.withValues(alpha: 0.2),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final String?  note;
  final Color    iconColor;
  final Color?   valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.iconColor  = AppColors.primary,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width:  AppSpacing.iconLg,
            height: AppSpacing.iconLg,
            decoration: AppDecorations.iconRounded(
              bg:     iconColor.withValues(alpha: 0.10),
              radius: AppSpacing.cardRadiusSm,
            ),
            child: Icon(icon, color: iconColor, size: AppSpacing.iconSm),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyMedium(size: 13)),
                if (note != null)
                  Text(note!,
                      style: AppTypography.caption(
                          color: AppColors.textDisabled)),
              ],
            ),
          ),
          Text(value,
              style: AppTypography.bodyBold(
                  size: 14,
                  color: valueColor ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final String?      note;
  final bool         canEdit;
  final VoidCallback onTap;

  const _NoteCard({
    required this.note,
    required this.canEdit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canEdit ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: AppDecorations.tintedCard(),
        child: Row(
          children: [
            Icon(
              note != null ? Icons.sticky_note_2_outlined : Icons.add_comment_outlined,
              color: AppColors.primary,
              size:  AppSpacing.iconSm,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                note ?? 'Add a session note…',
                style: note != null
                    ? AppTypography.body(size: 13, color: AppColors.textPrimary)
                    : AppTypography.body(size: 13, color: AppColors.textDisabled),
              ),
            ),
            if (canEdit)
              const Icon(Icons.edit_outlined,
                  color: AppColors.textDisabled, size: AppSpacing.iconSm),
          ],
        ),
      ),
    );
  }
}

class _UnsyncedBanner extends StatelessWidget {
  final bool isLoggedIn;
  const _UnsyncedBanner({required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: AppDecorations.tintedCard(radius: AppSpacing.cardRadius),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: AppSpacing.iconSm, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isLoggedIn
                  ? 'Saved locally. Will sync when back online.'
                  : 'Saved locally. Log in to sync this session.',
              style: AppTypography.caption(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveSessionBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.primaryCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Save this session',
              style: AppTypography.subheading(size: 13)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This session was conducted without an account. Sign in to save it permanently.',
            style: AppTypography.caption(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnDark,
                shape: RoundedRectangleBorder(
                    borderRadius:
                    BorderRadius.circular(AppSpacing.buttonRadius)),
              ),
              onPressed: () => context.push(const LoginScreen()),
              child: Text('Log In / Sign Up',
                  style: AppTypography.buttonPrimary()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final VoidCallback onTap;
  final String       label;
  const _ExportButton({required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon:  const Icon(Icons.upload_file_outlined,
            size: AppSpacing.iconSm, color: AppColors.primary),
        label: Text(label, style: AppTypography.buttonSecondary()),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _PastSessionsButton extends StatelessWidget {
  const _PastSessionsButton();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.push(const SessionHistoryScreen()),
      child: Text('View All Sessions →',
          style: AppTypography.buttonSecondary()),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState — centred empty/unavailable placeholder used across all tabs
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   body;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppSpacing.iconXl, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                style: AppTypography.subheading(
                    color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
            Text(body,
                textAlign: TextAlign.center,
                style: AppTypography.caption(color: AppColors.textDisabled)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ExpandableSectionCard — collapsible card used in both Emergency and Training
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableSectionCard extends StatefulWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       title;
  final String?      subtitle;
  final Widget       child;
  final bool         startOpen;
  final VoidCallback? onInfo;

  const _ExpandableSectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.subtitle,
    this.startOpen = false,
    this.onInfo,
  });

  @override
  State<_ExpandableSectionCard> createState() => _ExpandableSectionCardState();
}

class _ExpandableSectionCardState extends State<_ExpandableSectionCard> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.startOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: expand/collapse + optional info icon ──────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The InkWell covers title + chevron only
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
                    child: Row(
                      children: [
                        Container(
                          width:  AppSpacing.iconLg,
                          height: AppSpacing.iconLg,
                          decoration: AppDecorations.iconRounded(
                            bg:     widget.iconColor.withValues(alpha: 0.10),
                            radius: AppSpacing.cardRadiusSm,
                          ),
                          child: Icon(widget.icon,
                              color: widget.iconColor,
                              size:  AppSpacing.iconSm),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.title,
                                  style: AppTypography.subheading(size: 14)),
                              if (widget.subtitle != null &&
                                  widget.subtitle!.isNotEmpty)
                                Text(widget.subtitle!,
                                    style: AppTypography.caption()),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns:    _open ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textSecondary,
                              size:  AppSpacing.iconSm),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Info icon — outside InkWell so it doesn't collapse the card
              if (widget.onInfo != null)
                GestureDetector(
                  onTap: widget.onInfo,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xs, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size:  AppSpacing.iconSm - 2,
                      color: AppColors.primary.withValues(alpha: 0.40),
                    ),
                  ),
                ),
            ],
          ),
          AnimatedCrossFade(
            firstChild:  const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              children: [
                const Divider(height: 1, thickness: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: widget.child,
                ),
              ],
            ),
            crossFadeState:
            _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}