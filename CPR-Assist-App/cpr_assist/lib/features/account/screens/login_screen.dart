import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import 'forgot_password_screen.dart';
import 'registration_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey              = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController   = TextEditingController();

  bool    _isLoading       = false;
  bool    _passwordVisible = false;
  String? _errorMessage;

  late final AnimationController _fadeController;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
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
    if (raw.contains('401') ||
        raw.contains('invalid credentials') ||
        raw.contains('unauthorized')) {
      return 'Incorrect username/email or password. Please try again.';
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

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<void> _login() async {
    UIHelper.unfocus(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    try {
      final network  = ref.read(networkServiceProvider);
      final response = await network.post('/auth/login', {
        'username': _identifierController.text.trim(),
        'password': _passwordController.text.trim(),
      });

      if (response['token'] != null && response['user_id'] != null) {
        await ref.read(authStateProvider.notifier).login(
          response['token'],
          response['user_id'],
          _identifierController.text.trim(),
        );
        if (mounted) context.pop(true);
      } else {
        final serverMsg = response['message'] as String? ??
            response['error']   as String? ?? '';
        setState(() {
          _errorMessage = _friendlyError(serverMsg.isEmpty ? '401' : serverMsg);
        });
      }
    } catch (e) {
      setState(() => _errorMessage = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                    AppSpacing.md, AppSpacing.sm,
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
                          Text('Log In',
                              style: AppTypography.heading(size: 22)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Welcome back. Enter your credentials to continue.',
                            style: AppTypography.body(
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // Username / Email
                          const _FieldLabel('Username or Email'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller:   _identifierController,
                            hint:         'name@example.com or username',
                            icon:         Icons.person_outline_rounded,
                            action:       TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter your username or email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),

                          // Password
                          const _FieldLabel('Password'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller:  _passwordController,
                            hint:        'Enter your password',
                            icon:        Icons.lock_outline_rounded,
                            action:      TextInputAction.done,
                            obscure:     !_passwordVisible,
                            onSubmitted: (_) => _login(),
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
                              if (v == null || v.isEmpty) {
                                return 'Please enter your password';
                              }
                              return null;
                            },
                          ),

                          // Forgot password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  context.push(const ForgotPasswordScreen()),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.only(
                                  left:   AppSpacing.xs,
                                  right:  AppSpacing.xs,
                                  top:    AppSpacing.xxs,
                                  bottom: AppSpacing.xxs,
                                ),
                                tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot password?',
                                style: AppTypography.body(
                                    size: 13, color: AppColors.primary),
                              ),
                            ),
                          ),

                          // Error banner
                          if (_errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _ErrorBanner(message: _errorMessage!),
                          ],
                          const SizedBox(height: AppSpacing.md),

                          // Log In button
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
                              onPressed: _login,
                              style: ElevatedButton.styleFrom(
                                elevation: 4,
                                shadowColor: AppColors.primary
                                    .withValues(alpha: 0.4),
                              ),
                              child: const Text('Log In'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── "or" divider ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical:   AppSpacing.sm,
                  ),
                  child: Row(children: [
                    const Expanded(
                        child: Divider(
                            thickness: 0.5,
                            color: AppColors.textDisabled)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm),
                      child: Text('or',
                          style: AppTypography.body(
                              size: 13,
                              color: AppColors.textDisabled)),
                    ),
                    const Expanded(
                        child: Divider(
                            thickness: 0.5,
                            color: AppColors.textDisabled)),
                  ]),
                ),
              ),

              // ── Create account ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, 0, AppSpacing.md, 0),
                  child: OutlinedButton(
                    onPressed: () =>
                        context.push(const RegistrationScreen()),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      'Create Account',
                      style: AppTypography.buttonSecondary(),
                    ),
                  ),
                ),
              ),

              // ── Skip ───────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: () => context.pop(false),
                    child: Text(
                      'Continue without an account',
                      style: AppTypography.body(
                          color: AppColors.textDisabled),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: SizedBox(
                    height: AppSpacing.md + context.padding.bottom),
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
                onPressed: () => context.pop(false),
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
    this.obscure      = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
    this.keyboardType,
    this.focusNode,
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