import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RegistrationScreen
//
// Reached from LoginScreen only.
// On success: shows confirmation then pops back to LoginScreen.
// No login gate — registration itself is always accessible.
// ─────────────────────────────────────────────────────────────────────────────

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() =>
      _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final _formKey                   = GlobalKey<FormState>();
  final _usernameController        = TextEditingController();
  final _emailController           = TextEditingController();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool    _isLoading              = false;
  bool    _passwordVisible        = false;
  bool    _confirmPasswordVisible = false;
  String? _errorMessage;

  final _usernameFocus = FocusNode();
  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus  = FocusNode();

  late final AnimationController _fadeController;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(
        parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ── Registration logic ─────────────────────────────────────────────────────

  Future<void> _register() async {
    UIHelper.unfocus(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    try {
      final network  = ref.read(networkServiceProvider);
      final response = await network.post('/auth/register', {
        'username': _usernameController.text.trim(),
        'email':    _emailController.text.trim(),
        'password': _passwordController.text.trim(),
      });

      if (response['success'] == true) {
        if (mounted) _showSuccessDialog();
      } else {
        setState(() {
          _errorMessage =
              response['message'] ?? 'Registration failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    AppDialogs.showAlert(
      context,
      icon:         Icons.check_circle_outline_rounded,
      iconColor:    AppColors.success,
      iconBg:       AppColors.successBg,
      title:        'Account Created!',
      message:
      'Your account is ready. Log in with your new credentials to start tracking your sessions.',
      dismissLabel: 'Go to Login',
    ).then((_) {
      if (mounted) context.pop();
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
              // ── Hero header ────────────────────────────────────────────────
              SliverToBoxAdapter(child: _RegHeroHeader()),

              // ── Form card ─────────────────────────────────────────────────
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
                          Text('Create your account',
                              style: AppTypography.heading(size: 22)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Fill in the details below to get started.',
                            style: AppTypography.body(
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // ── Username ───────────────────────────────────────
                          const _FieldLabel('Username'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller:  _usernameController,
                            focusNode:   _usernameFocus,
                            hint:        'Choose a username',
                            icon:        Icons.person_outline_rounded,
                            action:      TextInputAction.next,
                            onSubmitted: (_) => _emailFocus.requestFocus(),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter a username';
                              }
                              if (v.trim().length < 3) {
                                return 'At least 3 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Email ──────────────────────────────────────────
                          const _FieldLabel('Email'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller:   _emailController,
                            focusNode:    _emailFocus,
                            hint:         'Enter your email address',
                            icon:         Icons.mail_outline_rounded,
                            action:       TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            onSubmitted:  (_) => _passwordFocus.requestFocus(),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!v.trim().isValidEmail) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Password ───────────────────────────────────────
                          const _FieldLabel('Password'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller:  _passwordController,
                            focusNode:   _passwordFocus,
                            hint:        'Choose a password',
                            icon:        Icons.lock_outline_rounded,
                            action:      TextInputAction.next,
                            obscure:     !_passwordVisible,
                            onSubmitted: (_) => _confirmFocus.requestFocus(),
                            suffix: IconButton(
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
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please enter a password';
                              if (v.length < 6) return 'At least 6 characters';
                              if (!v.contains(RegExp(r'[0-9]'))) return 'Must contain at least one number';
                              if (!v.contains(RegExp(r'[A-Z]'))) return 'Must contain at least one uppercase letter';
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Confirm password ───────────────────────────────
                          const _FieldLabel('Confirm Password'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller:  _confirmPasswordController,
                            focusNode:   _confirmFocus,
                            hint:        'Re-enter your password',
                            icon:        Icons.lock_outline_rounded,
                            action:      TextInputAction.done,
                            obscure:     !_confirmPasswordVisible,
                            onSubmitted: (_) => _register(),
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

                          // Error
                          if (_errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _ErrorBanner(message: _errorMessage!),
                          ],

                          const SizedBox(height: AppSpacing.lg),

                          // Register button
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
                              onPressed: _register,
                              child: const Text('Create Account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Already have account ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.xl + context.safeBottom),
                    child: TextButton(
                      onPressed: () => context.pop(),
                      child: Text(
                        'Already have an account? Log in',
                        style: AppTypography.body(
                            color: AppColors.textDisabled),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registration hero header
// ─────────────────────────────────────────────────────────────────────────────

class _RegHeroHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
          // Back button
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width:  AppSpacing.touchTargetMin,
              height: AppSpacing.touchTargetMin,
              decoration: AppDecorations.iconCircle(
                bg: AppColors.textOnDark.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textOnDark,
                size:  AppSpacing.iconMd,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Icon
          Container(
            width:  AppSpacing.iconXl + AppSpacing.lg,  // 72
            height: AppSpacing.iconXl + AppSpacing.lg,
            decoration: AppDecorations.iconCircle(
              bg: AppColors.textOnDark.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.person_add_outlined,
              color: AppColors.textOnDark,
              size:  AppSpacing.iconLg + AppSpacing.sm,  // 40
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text(
            'Join CPR Assist',
            style: AppTypography.displayLg(color: AppColors.textOnDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Track every session, see your progress,\nand compete on the leaderboard.',
            style: AppTypography.body(
                color: AppColors.textOnDark.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers (private to this file)
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.label(
        size: 13, color: AppColors.textSecondary),
  );
}

class _AppTextField extends StatelessWidget {
  final TextEditingController      controller;
  final FocusNode?                 focusNode;
  final String                     hint;
  final IconData                   icon;
  final TextInputAction            action;
  final bool                       obscure;
  final Widget?                    suffix;
  final String? Function(String?)? validator;
  final void Function(String)?     onSubmitted;
  final TextInputType?             keyboardType;

  const _AppTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.action,
    this.focusNode,
    this.obscure      = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:       controller,
      focusNode:        focusNode,
      obscureText:      obscure,
      textInputAction:  action,
      keyboardType:     keyboardType,
      onFieldSubmitted: onSubmitted,
      validator:        validator,
      style:            AppTypography.bodyMedium(),
      decoration: InputDecoration(
        hintText:   hint,
        hintStyle:  AppTypography.body(color: AppColors.textHint),
        prefixIcon: Icon(icon,
            size: AppSpacing.iconSm, color: AppColors.textDisabled),
        suffixIcon: suffix,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.errorCard(),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: AppSpacing.iconSm, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message,
                style: AppTypography.body(
                    size: 13, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}