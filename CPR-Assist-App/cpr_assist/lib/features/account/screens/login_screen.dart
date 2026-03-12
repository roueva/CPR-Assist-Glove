import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';
import 'forgot_password_screen.dart';
import 'registration_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
//
// Login is NEVER required to use the app.
// This screen is only reached from:
//   1. AccountPanel → "Log In" item (unauthenticated state)
//   2. Post-session prompt after an Emergency session
//   3. Training mode gate when not logged in
//
// On success: pops with true so the caller can react.
// On dismiss:  pops with false — caller stays in current state.
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey            = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

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
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Login logic ────────────────────────────────────────────────────────────

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
        'username': _usernameController.text.trim(),
        'password': _passwordController.text.trim(),
      });

      if (response['token'] != null && response['user_id'] != null) {
        await ref.read(authStateProvider.notifier).login(
          response['token'],
          response['user_id'],
          _usernameController.text.trim(),
        );
        if (mounted) context.pop(true);
      } else {
        setState(() {
          _errorMessage =
              response['message'] ?? 'Login failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().contains('SocketException') || e.toString().contains('timed out')
            ? 'Network error. Please check your connection and try again.'
            : e.toString().replaceFirst('Exception: ', '');
      });
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
        body: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            slivers: [
              // ── Hero header ────────────────────────────────────────────────
              SliverToBoxAdapter(child: _HeroHeader()),

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
                          Text('Welcome back',
                              style: AppTypography.heading(size: 22)),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Log in to track your sessions and progress.',
                            style: AppTypography.body(
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          // Username
                          const _FieldLabel('Username'),
                          const SizedBox(height: AppSpacing.xs),
                          _AppTextField(
                            controller: _usernameController,
                            hint:       'Enter your username',
                            icon:       Icons.person_outline_rounded,
                            action:     TextInputAction.next,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter your username';
                              }
                              if (v.trim().length < 3) {
                                return 'At least 3 characters';
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
                              if (v.length < 6) return 'At least 6 characters';
                              return null;
                            },
                          ),

                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => context.push(const ForgotPasswordScreen()),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical:   AppSpacing.xxs,
                                ),
                              ),
                              child: Text(
                                'Forgot password?',
                                style: AppTypography.body(
                                  size:  13,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),

                          // Error message
                          if (_errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _ErrorBanner(message: _errorMessage!),
                          ],

                          const SizedBox(height: AppSpacing.lg),

                          // Login button
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
                              child: const Text('Log In'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Register link ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md),
                  child: _RegisterPrompt(),
                ),
              ),

              // ── Skip link ──────────────────────────────────────────────────
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
                child: SizedBox(height: AppSpacing.xl + MediaQuery.paddingOf(context).bottom),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Register prompt card
// ─────────────────────────────────────────────────────────────────────────────

class _RegisterPrompt extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.primaryCard(),
      child: Row(
        children: [
          Container(
            width:  AppSpacing.iconXl,
            height: AppSpacing.iconXl,
            decoration: AppDecorations.iconCircle(bg: AppColors.primaryLight),
            child: const Icon(Icons.person_add_outlined,
                color: AppColors.primary, size: AppSpacing.iconMd),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Don't have an account?",
                    style: AppTypography.bodyMedium(size: 14)),
                Text('Create one — it only takes a minute.',
                    style: AppTypography.caption()),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push(const RegistrationScreen()),
            child: Text('Register',
                style: AppTypography.buttonSecondary()),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero header
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
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
            onTap: () => context.pop(false),
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
              Icons.monitor_heart_outlined,
              color: AppColors.textOnDark,
              size:  AppSpacing.iconLg + AppSpacing.sm,  // 40
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text(
            'CPR Assist',
            style: AppTypography.displayLg(color: AppColors.textOnDark),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your sessions, progress, and rankings\nare just one login away.',
            style: AppTypography.body(
                color: AppColors.textOnDark.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared field label
// ─────────────────────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: AppTypography.label(
            size: 13, color: AppColors.textSecondary));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared text field
// ─────────────────────────────────────────────────────────────────────────────

class _AppTextField extends StatelessWidget {
  final TextEditingController      controller;
  final String                     hint;
  final IconData                   icon;
  final TextInputAction            action;
  final bool                       obscure;
  final Widget?                    suffix;
  final String? Function(String?)? validator;
  final void Function(String)?     onSubmitted;

  const _AppTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.action,
    this.obscure      = false,
    this.suffix,
    this.validator,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:       controller,
      obscureText:      obscure,
      textInputAction:  action,
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

// ─────────────────────────────────────────────────────────────────────────────
// Error banner
// ─────────────────────────────────────────────────────────────────────────────

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