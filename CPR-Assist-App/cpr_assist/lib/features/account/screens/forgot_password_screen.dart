import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ForgotPasswordScreen
// User enters their email → backend sends a password reset link OR their
// username, depending on which button they tap.
// ─────────────────────────────────────────────────────────────────────────────

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey         = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _emailFocus      = FocusNode();

  bool    _isLoading      = false;
  bool    _submitted      = false;   // true after a successful send
  bool    _emailTouched   = false;
  bool    _submitAttempted = false;
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

    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus && _emailController.text.isNotEmpty) {
        setState(() => _emailTouched = true);
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit(String endpoint) async {
    UIHelper.unfocus(context);
    setState(() {
      _submitAttempted = true;
      _emailTouched    = true;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    try {
      final network = ref.read(networkServiceProvider);
      await network.post(endpoint, {
        'email': _emailController.text.trim(),
      });
      if (mounted) setState(() => _submitted = true);
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
              // ── Logo block ─────────────
              SliverToBoxAdapter(
                child:
                    Padding(
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
                                'Account Recovery',
                                style: AppTypography.heading(
                                    size: 24, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ],
                      ),
                ),
              ),

              // ── Form card or Confirmation ──────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md,
                    AppSpacing.md, AppSpacing.md,
                  ),
                  child: _submitted ? _buildConfirmation() : _buildForm(),
                ),
              ),

              // ── "Back to Login" text link ──────────────────────────────────
              if (!_submitted)
                SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(
                          bottom: AppSpacing.xl + context.safeBottom),
                      child: TextButton(
                        onPressed: () => context.pop(),
                        child: RichText(
                          text: TextSpan(
                            style: AppTypography.body(
                                color: AppColors.textSecondary),
                            children: [
                              const TextSpan(
                                  text: 'Remembered it? '),
                              TextSpan(
                                text: 'Back to Login',
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

              if (_submitted)
                SliverToBoxAdapter(
                  child: SizedBox(
                      height: AppSpacing.xl + context.safeBottom),
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

  // ── Form ───────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recover your account',
                style: AppTypography.heading(size: 22)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enter the email address linked to your account.',
              style: AppTypography.body(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Email ────────────────────────────────────────────────────────
            const _FieldLabel('Email'),
            const SizedBox(height: AppSpacing.xs),
            TextFormField(
              controller:      _emailController,
              focusNode:       _emailFocus,
              keyboardType:    TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) =>
                  _submit('/auth/password-reset-request'),
              autovalidateMode: (_emailTouched || _submitAttempted)
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!v.trim().isValidEmail) {
                  return 'Enter a valid email address';
                }
                return null;
              },
              style:      AppTypography.bodyMedium(),
              decoration: _inputDecoration(
                hint: 'name@example.com',
                icon: Icons.mail_outline_rounded,
              ),
            ),

            // ── Error banner ─────────────────────────────────────────────────
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              _ErrorBanner(message: _errorMessage!),
            ],

            const SizedBox(height: AppSpacing.lg),

            // ── Send Reset Link button ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: _isLoading
                  ? const Center(
                child: SizedBox(
                  width:  AppSpacing.iconLg,
                  height: AppSpacing.iconLg,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary),
                  ),
                ),
              )
                  : ElevatedButton(
                onPressed: () =>
                    _submit('/auth/password-reset-request'),
                style: ElevatedButton.styleFrom(
                  elevation:   4,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                ),
                child: const Text('Send Reset Link'),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── "or" divider ─────────────────────────────────────────────────
            Row(children: [
              const Expanded(
                  child: Divider(
                      thickness: 0.5, color: AppColors.textDisabled)),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm),
                child: Text('or',
                    style: AppTypography.body(
                        size: 13, color: AppColors.textDisabled)),
              ),
              const Expanded(
                  child: Divider(
                      thickness: 0.5, color: AppColors.textDisabled)),
            ]),

            const SizedBox(height: AppSpacing.md),

            // ── Email my Username button ──────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () => _submit('/auth/forgot-username'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'Email me my Username',
                  style: AppTypography.buttonSecondary(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirmation state ─────────────────────────────────────────────────────

  Widget _buildConfirmation() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          Container(
            width:  AppSpacing.iconXl + AppSpacing.lg,
            height: AppSpacing.iconXl + AppSpacing.lg,
            decoration: AppDecorations.iconCircle(bg: AppColors.successBg),
            child: const Icon(
              Icons.mark_email_read_outlined,
              color: AppColors.success,
              size:  AppSpacing.iconLg,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Check your email',
              style: AppTypography.heading(size: 20)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'If an account exists for ${_emailController.text.trim()}, '
                'we\'ve sent you an email. '
                'Check your inbox and follow the instructions.',
            textAlign: TextAlign.center,
            style: AppTypography.body(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                elevation:   4,
                shadowColor: AppColors.primary.withValues(alpha: 0.4),
              ),
              child: const Text('Back to Login'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers (duplicated locally — same as registration_screen.dart)
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