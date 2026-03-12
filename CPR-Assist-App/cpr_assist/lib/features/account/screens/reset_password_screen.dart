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

  bool    _isLoading              = false;
  bool    _passwordVisible        = false;
  bool    _confirmPasswordVisible = false;
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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    UIHelper.unfocus(context);
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
            // Pop back to login — pop twice if reset was pushed on top of forgot screen
            context.pop();
            context.pop();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().contains('SocketException') ||
              e.toString().contains('timed out')
              ? 'Network error. Please check your connection.'
              : e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => UIHelper.unfocus(context),
      child: Scaffold(
        backgroundColor: AppColors.screenBgGrey,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Container(
                    decoration: AppDecorations.card(),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Set a new password',
                              style: AppTypography.heading(size: 22)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Choose a strong password for your account.',
                            style: AppTypography.body(
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // New password
                          Text('New Password',
                              style: AppTypography.label(
                                  size: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: AppSpacing.xs),
                          TextFormField(
                            controller:      _passwordController,
                            obscureText:     !_passwordVisible,
                            textInputAction: TextInputAction.next,
                            style:           AppTypography.bodyMedium(),
                            decoration: InputDecoration(
                              hintText:   'Enter new password',
                              hintStyle:  AppTypography.body(color: AppColors.textHint),
                              prefixIcon: const Icon(Icons.lock_outline_rounded,
                                  size: AppSpacing.iconSm,
                                  color: AppColors.textDisabled),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _passwordVisible
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size:  AppSpacing.iconSm,
                                  color: AppColors.textDisabled,
                                ),
                                onPressed: () => setState(
                                        () => _passwordVisible = !_passwordVisible),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please enter a password';
                              if (v.length < 6) return 'At least 6 characters';
                              if (!v.contains(RegExp(r'[0-9]'))) {
                                return 'Must contain at least one number';
                              }
                              if (!v.contains(RegExp(r'[A-Z]'))) {
                                return 'Must contain at least one uppercase letter';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // Confirm password
                          Text('Confirm Password',
                              style: AppTypography.label(
                                  size: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: AppSpacing.xs),
                          TextFormField(
                            controller:      _confirmPasswordController,
                            obscureText:     !_confirmPasswordVisible,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            style:           AppTypography.bodyMedium(),
                            decoration: InputDecoration(
                              hintText:   'Re-enter new password',
                              hintStyle:  AppTypography.body(color: AppColors.textHint),
                              prefixIcon: const Icon(Icons.lock_outline_rounded,
                                  size: AppSpacing.iconSm,
                                  color: AppColors.textDisabled),
                              suffixIcon: IconButton(
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
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (v != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),

                          if (_errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: AppDecorations.errorCard(),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded,
                                      size:  AppSpacing.iconSm,
                                      color: AppColors.error),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(_errorMessage!,
                                        style: AppTypography.body(
                                            size: 13, color: AppColors.error)),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.lg),

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
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        context.padding.top + AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      decoration: AppDecorations.primaryGradientCard(radius: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width:  AppSpacing.touchTargetMin,
              height: AppSpacing.touchTargetMin,
              decoration: AppDecorations.iconCircle(
                bg: AppColors.textOnDark.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textOnDark, size: AppSpacing.iconMd),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width:  AppSpacing.iconXl + AppSpacing.lg,
            height: AppSpacing.iconXl + AppSpacing.lg,
            decoration: AppDecorations.iconCircle(
              bg: AppColors.textOnDark.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.lock_reset_rounded,
                color: AppColors.textOnDark,
                size:  AppSpacing.iconLg + AppSpacing.sm),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Reset Password',
              style: AppTypography.displayLg(color: AppColors.textOnDark)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Choose a new password for your account.',
            style: AppTypography.body(
                color: AppColors.textOnDark.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}