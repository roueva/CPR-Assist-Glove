import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RegistrationScreen
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

  // Per-field dirty tracking — error shown only after field loses focus once
  bool _usernameTouched = false;
  bool _emailTouched    = false;
  bool _confirmTouched  = false;
  bool _passwordTouched = false;

  // Whether the submit button was pressed at least once
  bool _submitAttempted = false;

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

    // Mark fields as touched when they lose focus
    _usernameFocus.addListener(() {
      if (!_usernameFocus.hasFocus && _usernameController.text.isNotEmpty) {
        setState(() => _usernameTouched = true);
      }
    });
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus && _emailController.text.isNotEmpty) {
        setState(() => _emailTouched = true);
      }
    });
    _confirmFocus.addListener(() {
      if (!_confirmFocus.hasFocus &&
          _confirmPasswordController.text.isNotEmpty) {
        setState(() => _confirmTouched = true);
      }
    });

    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus && _passwordController.text.isNotEmpty) {
        setState(() => _passwordTouched = true);
      }
    });

    // Live-update password checklist
    _passwordController.addListener(() => setState(() {}));
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

  // ── Password rule helpers ──────────────────────────────────────────────────

  bool get _pwMinLength  => _passwordController.text.length >= 6;
  bool get _pwHasNumber  => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _pwHasUpper   => _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool get _pwAllPassing => _pwMinLength && _pwHasNumber && _pwHasUpper;

  // ── Validators ─────────────────────────────────────────────────────────────

  String? _validateUsername(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter a username';
    if (v.trim().length < 3) return 'At least 3 characters';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter your email';
    if (!v.trim().isValidEmail) return 'Enter a valid email address';
    return null;
  }

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

  // ── Error mapping ──────────────────────────────────────────────────────────

  String _friendlyError(dynamic e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('no internet connection') ||
        raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection refused')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('timed out') || raw.contains('request timed out')) {
      return 'Request timed out. Please check your connection and try again.';
    }
    if (raw.contains('409') ||
        raw.contains('already exists') ||
        raw.contains('already taken') ||
        raw.contains('duplicate')) {
      return 'That username or email is already registered. Please try a different one.';
    }
    if (raw.contains('400') || raw.contains('validation failed')) {
      return 'Please check your input and try again.';
    }
    if (raw.contains('429')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (raw.contains('500') || raw.contains('503') || raw.contains('502')) {
      return 'Server error. Please try again later.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  // ── Registration logic ─────────────────────────────────────────────────────

  Future<void> _register() async {
    UIHelper.unfocus(context);
    setState(() {
      _submitAttempted = true;
      _usernameTouched = true;
      _emailTouched    = true;
      _confirmTouched  = true;
    });

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
        final serverMsg = response['message'] as String? ??
            response['error']   as String? ?? '';
        setState(() {
          _errorMessage = _friendlyError(
              serverMsg.isEmpty
                  ? 'Registration failed. Please try again.'
                  : serverMsg);
        });
      }
    } catch (e) {
      setState(() => _errorMessage = _friendlyError(e));
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
              // ── Logo block ────────────────────────────────────
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
                      Icons.show_chart_rounded,
                      color: AppColors.primary,
                      size:  AppSpacing.iconLg + AppSpacing.sm,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'CPR Assist',
                    style: AppTypography.heading(
                        size: 24, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
          ),
              // ── Form card ─────────────────────────────────────────────────
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
                          Text('Create Account',
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
                          TextFormField(
                            controller:      _usernameController,
                            focusNode:       _usernameFocus,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _emailFocus.requestFocus(),
                            autovalidateMode: (_usernameTouched || _submitAttempted)
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            validator:  _validateUsername,
                            style:      AppTypography.bodyMedium(),
                            decoration: _inputDecoration(
                              hint: 'e.g. john_doe or johndoe',
                              icon: Icons.person_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Email ──────────────────────────────────────────
                          const _FieldLabel('Email'),
                          const SizedBox(height: AppSpacing.xs),
                          TextFormField(
                            controller:      _emailController,
                            focusNode:       _emailFocus,
                            textInputAction: TextInputAction.next,
                            keyboardType:    TextInputType.emailAddress,
                            onFieldSubmitted: (_) =>
                                _passwordFocus.requestFocus(),
                            autovalidateMode: (_emailTouched || _submitAttempted)
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            validator:  _validateEmail,
                            style:      AppTypography.bodyMedium(),
                            decoration: _inputDecoration(
                              hint: 'name@example.com',
                              icon: Icons.mail_outline_rounded,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // ── Password ───────────────────────────────────────
                          const _FieldLabel('Password'),
                          const SizedBox(height: AppSpacing.xs),
                          TextFormField(
                            controller:      _passwordController,
                            focusNode:       _passwordFocus,
                            obscureText:     !_passwordVisible,
                            textInputAction: TextInputAction.next,
                            onFieldSubmitted: (_) =>
                                _confirmFocus.requestFocus(),
                            // password errors only shown on submit
                            autovalidateMode: _submitAttempted
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            validator:  _validatePassword,
                            style:      AppTypography.bodyMedium(),
                            decoration: _inputDecoration(
                              hint:   'Enter a strong password',
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
                                        () => _passwordVisible = !_passwordVisible),
                              ),
                            ),
                          ),

                          // ── Password checklist ─────────────────────────────
                          if (showPasswordChecklist) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _PasswordChecklist(
                              minLength: _pwMinLength,
                              hasNumber: _pwHasNumber,
                              hasUpper:  _pwHasUpper,
                              showErrors: _passwordTouched || _submitAttempted,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),

                          // ── Confirm password ───────────────────────────────
                          const _FieldLabel('Confirm Password'),
                          const SizedBox(height: AppSpacing.xs),
                          TextFormField(
                            controller:      _confirmPasswordController,
                            focusNode:       _confirmFocus,
                            obscureText:     !_confirmPasswordVisible,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _register(),
                            autovalidateMode: (_confirmTouched || _submitAttempted)
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            validator:  _validateConfirm,
                            style:      AppTypography.bodyMedium(),
                            decoration: _inputDecoration(
                              hint:   'Re-enter your password',
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

                          // ── Server error banner ────────────────────────────
                          if (_errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _ErrorBanner(message: _errorMessage!),
                          ],

                          const SizedBox(height: AppSpacing.lg),

                          // ── Create Account button ──────────────────────────
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
                              style: ElevatedButton.styleFrom(
                                elevation: 4,
                                shadowColor: AppColors.primary
                                    .withValues(alpha: 0.4),
                              ),
                              child: const Text('Create Account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Already have an account ────────────────────────────────────
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: AppSpacing.xxl + context.safeBottom),
                    child: TextButton(
                      onPressed: () => context.pop(),
                      child: RichText(
                        text: TextSpan(
                          style: AppTypography.body(
                              color: AppColors.textSecondary),
                          children: [
                            const TextSpan(text: 'Already have an account? '),
                            TextSpan(
                              text: 'Log in',
                              style: AppTypography.bodyBold(
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
            // ── Fixed back arrow ───────────────────────────────────────────
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
// Input decoration helper (keeps TextFormField declarations concise)
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

// ─────────────────────────────────────────────────────────────────────────────
// Password checklist
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
        color: AppColors.screenBgGrey,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CheckRow('At least 6 characters',      minLength, showErrors),
          const SizedBox(height: AppSpacing.xxs),
          _CheckRow('At least one number',         hasNumber, showErrors),
          const SizedBox(height: AppSpacing.xxs),
          _CheckRow('At least one uppercase letter', hasUpper, showErrors),
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
        : (showError
        ? Icons.cancel_rounded
        : Icons.circle_outlined);

    return Row(
      children: [
        Icon(icon, size: AppSpacing.iconSm, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.body(size: 12, color: color),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

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