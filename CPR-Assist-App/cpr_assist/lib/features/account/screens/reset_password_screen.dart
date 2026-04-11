import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ResetPasswordScreen
// Reached via deep link: cpr-assist://reset-password?token=xxx
// Takes the token from the URL, lets user set a new password.
// ─────────────────────────────────────────────────────────────────────────────

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String token;
  const ResetPasswordScreen({super.key, required this.token});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey                   = GlobalKey<FormState>();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFocus             = FocusNode();
  final _confirmFocus              = FocusNode();

  bool    _isLoading              = false;
  bool    _passwordVisible        = false;
  bool    _confirmPasswordVisible = false;
  bool    _passwordTouched        = false;
  bool    _confirmTouched         = false;
  bool    _submitAttempted        = false;
  String? _errorMessage;

  late final AnimationController _fadeController;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus && _passwordController.text.isNotEmpty) {
        setState(() => _passwordTouched = true);
      }
    });
    _confirmFocus.addListener(() {
      if (!_confirmFocus.hasFocus &&
          _confirmPasswordController.text.isNotEmpty) {
        setState(() => _confirmTouched = true);
      }
    });

    // Live-update password checklist
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ── Password rule helpers ──────────────────────────────────────────────────

  bool get _pwMinLength  => _passwordController.text.length >= 6;
  bool get _pwHasNumber  => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _pwHasUpper   => _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _pwAllPassing => _pwMinLength && _pwHasNumber && _pwHasUpper;

  // ── Validators ─────────────────────────────────────────────────────────────

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Please enter a password';
    if (!_pwAllPassing) return 'Password does not meet requirements';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your password';
    if (v != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    UIHelper.unfocus(context);
    setState(() {
      _submitAttempted = true;
      _passwordTouched = true;
      _confirmTouched  = true;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    try {
      final network = ref.read(networkServiceProvider);
      await network.post(
        '/auth/password-reset/${widget.token}',
        {'newPassword': _passwordController.text.trim()},
      );

      if (mounted) {
        AppDialogs.showAlert(
          context,
          icon:         Icons.check_circle_outline_rounded,
          iconColor:    AppColors.success,
          iconBg:       AppColors.successBg,
          title:        'Password Reset!',
          message:      'Your password has been updated. You can now log in.',
          dismissLabel: 'Go to Login',
        ).then((_) {
          if (mounted) {
            context.pop();
            context.pop();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          final raw = e.toString().toLowerCase();
          if (raw.contains('socketexception') ||
              raw.contains('failed host lookup') ||
              raw.contains('connection refused')) {
            _errorMessage =
            'No internet connection. Please check your network and try again.';
          } else if (raw.contains('timed out')) {
            _errorMessage =
            'Request timed out. Please check your connection and try again.';
          } else if (raw.contains('400') ||
              raw.contains('invalid') ||
              raw.contains('expired')) {
            _errorMessage =
            'This reset link is invalid or has expired. Please request a new one.';
          } else if (raw.contains('429')) {
            _errorMessage =
            'Too many attempts. Please wait a moment and try again.';
          } else if (raw.contains('500') ||
              raw.contains('502') ||
              raw.contains('503')) {
            _errorMessage = 'Server error. Please try again later.';
          } else {
            _errorMessage = e.toString().replaceFirst('Exception: ', '');
          }
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showPasswordChecklist = _passwordFocus.hasFocus ||
        _passwordController.text.isNotEmpty;

    return GestureDetector(
      onTap: () => UIHelper.unfocus(context),
      child: Scaffold(
        backgroundColor: AppColors.screenBgGrey,
        body: Stack(
          children: [
            FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(
                slivers: [
                  // ── Logo block ──────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        context.padding.top + AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width:  72,
                                height: 72,
                                decoration: AppDecorations.card(
                                    radius: AppSpacing.cardRadiusLg),
                                child: const Icon(
                                  Icons.lock_reset_rounded,
                                  color: AppColors.primary,
                                  size:  AppSpacing.iconLg + AppSpacing.sm,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Reset Password',
                                style: AppTypography.heading(
                                    size: 24, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Form card ───────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, AppSpacing.md,
                        AppSpacing.md, AppSpacing.md,
                      ),
                      child: Container(
                        decoration: AppDecorations.card(),
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.disabled,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Choose a new password for your account.',
                                style: AppTypography.body(
                                    color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: AppSpacing.lg),

                              // ── New password ─────────────────────────────
                              const _FieldLabel('New Password'),
                              const SizedBox(height: AppSpacing.xs),
                              TextFormField(
                                controller:      _passwordController,
                                focusNode:       _passwordFocus,
                                obscureText:     !_passwordVisible,
                                textInputAction: TextInputAction.next,
                                onFieldSubmitted: (_) =>
                                    _confirmFocus.requestFocus(),
                                autovalidateMode: _submitAttempted
                                    ? AutovalidateMode.onUserInteraction
                                    : AutovalidateMode.disabled,
                                validator:  _validatePassword,
                                style:      AppTypography.bodyMedium(),
                                decoration: _inputDecoration(
                                  hint:   'Enter new password',
                                  icon:   Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _passwordVisible
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      size:  AppSpacing.iconSm,
                                      color: AppColors.textDisabled,
                                    ),
                                    onPressed: () => setState(
                                            () => _passwordVisible =
                                        !_passwordVisible),
                                  ),
                                ),
                              ),

                              // ── Password checklist ───────────────────────
                              if (showPasswordChecklist) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _PasswordChecklist(
                                  minLength:  _pwMinLength,
                                  hasNumber:  _pwHasNumber,
                                  hasUpper:   _pwHasUpper,
                                  showErrors: _passwordTouched || _submitAttempted,
                                ),
                              ],
                              const SizedBox(height: AppSpacing.md),

                              // ── Confirm password ─────────────────────────
                              const _FieldLabel('Confirm Password'),
                              const SizedBox(height: AppSpacing.xs),
                              TextFormField(
                                controller:      _confirmPasswordController,
                                focusNode:       _confirmFocus,
                                obscureText:     !_confirmPasswordVisible,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                autovalidateMode: (_confirmTouched || _submitAttempted)
                                    ? AutovalidateMode.onUserInteraction
                                    : AutovalidateMode.disabled,
                                validator:  _validateConfirm,
                                style:      AppTypography.bodyMedium(),
                                decoration: _inputDecoration(
                                  hint:   'Re-enter new password',
                                  icon:   Icons.lock_outline_rounded,
                                  suffix: IconButton(
                                    icon: Icon(
                                      _confirmPasswordVisible
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      size:  AppSpacing.iconSm,
                                      color: AppColors.textDisabled,
                                    ),
                                    onPressed: () => setState(() =>
                                    _confirmPasswordVisible =
                                    !_confirmPasswordVisible),
                                  ),
                                ),
                              ),

                              // ── Error banner ─────────────────────────────
                              if (_errorMessage != null) ...[
                                const SizedBox(height: AppSpacing.md),
                                _ErrorBanner(message: _errorMessage!),
                              ],

                              const SizedBox(height: AppSpacing.lg),

                              // ── Reset Password button ────────────────────
                              SizedBox(
                                width: double.infinity,
                                child: _isLoading
                                    ? const Center(
                                  child: SizedBox(
                                    width:  AppSpacing.iconLg,
                                    height: AppSpacing.iconLg,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                          AppColors.primary),
                                    ),
                                  ),
                                )
                                    : ElevatedButton(
                                  onPressed: _submit,
                                  style: ElevatedButton.styleFrom(
                                    elevation:   4,
                                    shadowColor: AppColors.primary
                                        .withValues(alpha: 0.4),
                                  ),
                                  child: const Text('Reset Password'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: SizedBox(
                        height: AppSpacing.xl + context.safeBottom),
                  ),
                ],
              ),
            ),

            // ── Fixed back arrow ────────────────────────────────────────────
            Positioned(
              top:  context.padding.top + AppSpacing.xs,
              left: AppSpacing.xs,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.textSecondary,
                  size:  AppSpacing.iconMd,
                ),
                onPressed: () => context.pop(),
                tooltip: 'Back',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (same pattern as registration_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

InputDecoration _inputDecoration({
  required String   hint,
  required IconData icon,
  Widget?           suffix,
}) =>
    InputDecoration(
      hintText:   hint,
      hintStyle:  AppTypography.body(color: AppColors.textHint),
      prefixIcon: Icon(icon,
          size: AppSpacing.iconSm, color: AppColors.textDisabled),
      suffixIcon: suffix,
    );

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.label(size: 13, color: AppColors.textPrimary),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      decoration: AppDecorations.errorCard(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline_rounded,
                size: AppSpacing.iconSm, color: AppColors.error),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: AppTypography.body(size: 13, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Password checklist (copied from registration_screen.dart)
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordChecklist extends StatelessWidget {
  final bool minLength;
  final bool hasNumber;
  final bool hasUpper;
  final bool showErrors;

  const _PasswordChecklist({
    required this.minLength,
    required this.hasNumber,
    required this.hasUpper,
    required this.showErrors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color:        AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        border:       Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CheckRow('At least 6 characters',       minLength, showErrors),
          const SizedBox(height: AppSpacing.xxs),
          _CheckRow('At least one number',          hasNumber, showErrors),
          const SizedBox(height: AppSpacing.xxs),
          _CheckRow('At least one uppercase letter', hasUpper,  showErrors),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool   done;
  final bool   showError;
  const _CheckRow(this.label, this.done, this.showError);

  @override
  Widget build(BuildContext context) {
    final Color color = done
        ? AppColors.success
        : (showError ? AppColors.error : AppColors.textDisabled);
    final IconData icon = done
        ? Icons.check_circle_rounded
        : (showError ? Icons.cancel_rounded : Icons.circle_outlined);

    return Row(
      children: [
        Icon(icon, size: AppSpacing.iconSm, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.body(size: 12, color: color)),
      ],
    );
  }
}