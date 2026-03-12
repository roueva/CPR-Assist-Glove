  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import 'package:cpr_assist/core/core.dart';

  import '../../../providers/app_providers.dart';

  // ─────────────────────────────────────────────────────────────────────────────
  // ProfileEditorScreen
  // ─────────────────────────────────────────────────────────────────────────────

  class ProfileEditorScreen extends ConsumerStatefulWidget {
    const ProfileEditorScreen({super.key});

    @override
    ConsumerState<ProfileEditorScreen> createState() =>
        _ProfileEditorScreenState();
  }

  class _ProfileEditorScreenState extends ConsumerState<ProfileEditorScreen> {
    late TextEditingController _nameController;
    bool    _isSaving    = false;
    bool    _hasChanges  = false;
    String? _errorMessage;

    @override
    void initState() {
      super.initState();
      final username = ref.read(authStateProvider).username ?? '';
      _nameController = TextEditingController(text: username)
        ..addListener(_onChanged);
    }

    void _onChanged() {
      final original = ref.read(authStateProvider).username ?? '';
      setState(() {
        _hasChanges   = _nameController.text.trim() != original;
        _errorMessage = null;
      });
    }

    @override
    void dispose() {
      _nameController
        ..removeListener(_onChanged)
        ..dispose();
      super.dispose();
    }

    // ── Save ───────────────────────────────────────────────────────────────────

    Future<void> _save() async {
      final newName = _nameController.text.trim();
      if (newName.length < 3) {
        setState(() => _errorMessage = 'Name must be at least 3 characters.');
        return;
      }

      setState(() { _isSaving = true; _errorMessage = null; });

      try {
        final networkService = ref.read(networkServiceProvider);
        await networkService.put(
          '/auth/profile',
          {'username': newName},
          requiresAuth: true,
        );

        await ref.read(authStateProvider.notifier).updateUsername(newName);

        if (mounted) {
          HapticFeedback.lightImpact();
          context.pop();
          UIHelper.showSuccess(context, 'Profile updated');
        }
      } on Exception catch (e) {
        setState(() {
          _isSaving     = false;
          final msg     = e.toString().replaceFirst('Exception: ', '');
          _errorMessage = msg.contains('409')
              ? 'That username is already taken.'
              : 'Could not save. Check your connection.';
        });
      }
    }

    // ── Back-press guard ───────────────────────────────────────────────────────

    Future<bool> _confirmDiscard() async {
      if (!_hasChanges) return true;

      final discard = await AppDialogs.confirmDiscard(context);
      return discard == true;
    }

    // ── Build ──────────────────────────────────────────────────────────────────

    @override
    Widget build(BuildContext context) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmDiscard() && mounted) context.pop();
        },
        child: Scaffold(
          backgroundColor: AppColors.screenBgGrey,
          appBar: _buildAppBar(context),
          body: GestureDetector(
            onTap: () => UIHelper.unfocus(context),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                // ── Avatar preview ─────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width:  AppSpacing.avatarLg + AppSpacing.lg, // 90
                            height: AppSpacing.avatarLg + AppSpacing.lg,
                            decoration: BoxDecoration(
                              shape:  BoxShape.circle,
                              color:  AppColors.primaryLight,
                              border: Border.all(
                                color: AppColors.primaryMid,
                                width: AppSpacing.xxs + AppSpacing.xxs,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _nameController.text.trim().initials,
                                style: AppTypography.heading(
                                  size:  28,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: AppSpacing.xxs,
                            right:  AppSpacing.xxs,
                            child: GestureDetector(
                              onTap: () => UIHelper.showSnackbar(
                                context,
                                message: 'Photo upload coming soon',
                                icon:    Icons.camera_alt_outlined,
                              ),
                              child: Container(
                                width:  AppSpacing.lg + AppSpacing.xs, // 28
                                height: AppSpacing.lg + AppSpacing.xs,
                                decoration: BoxDecoration(
                                  color:  AppColors.primary,
                                  shape:  BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.surfaceWhite,
                                    width: AppSpacing.xxs,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_outlined,
                                  color: AppColors.textOnDark,
                                  size:  AppSpacing.iconXs,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Tap camera to change photo',
                        style: AppTypography.caption(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Name field ─────────────────────────────────────────────
                Text(
                  'DISPLAY NAME',
                  style: AppTypography.badge(color: AppColors.textDisabled),
                ),
                const SizedBox(height: AppSpacing.cardSpacing),
                TextField(
                  controller:      _nameController,
                  textInputAction: TextInputAction.done,
                  onSubmitted:     (_) { if (_hasChanges) _save(); },
                  decoration: InputDecoration(
                    hintText:  'Your name',
                    errorText: _errorMessage,
                  ),
                ),
                const SizedBox(height: AppSpacing.cardSpacing),
                Text(
                  'This name appears on the leaderboard and in session reports.',
                  style: AppTypography.caption(),
                ),

                const SizedBox(height: AppSpacing.xl),

                // ── Save button ────────────────────────────────────────────
                AnimatedOpacity(
                  opacity:  _hasChanges ? 1.0 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_hasChanges && !_isSaving) ? _save : null,
                      child: _isSaving
                          ? const SizedBox(
                        width:  AppSpacing.iconSm,
                        height: AppSpacing.iconSm,
                        child: CircularProgressIndicator(
                          strokeWidth: AppSpacing.xxs,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.textOnDark,
                          ),
                        ),
                      )
                          : const Text('Save Changes'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    PreferredSizeWidget _buildAppBar(BuildContext context) {
      return AppBar(
        backgroundColor:        AppColors.headerBg,
        foregroundColor:        AppColors.textPrimary,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary),
          onPressed: () async {
            if (await _confirmDiscard() && mounted) context.pop();
          },
        ),
        title: Text('Edit Profile', style: AppTypography.heading(size: 18)),
        actions: [
          if (_hasChanges)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TextButton(
                onPressed: _isSaving ? null : _save,
                child: Text(
                  'Save',
                  style: AppTypography.buttonSecondary(
                    color: _isSaving ? AppColors.textDisabled : AppColors.primary,
                  ),
                ),
              ),
            ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(
            height: AppSpacing.dividerThickness,
            color:  AppColors.divider,
          ),
        ),
      );
    }
  }