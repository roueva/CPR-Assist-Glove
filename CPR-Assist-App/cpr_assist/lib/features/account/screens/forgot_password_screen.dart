import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cpr_assist/core/core.dart';
import '../../../providers/app_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ForgotPasswordScreen
// User enters their email → backend sends a reset link.
// Also has "Forgot username?" option.
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

  bool    _isLoading    = false;
  bool    _submitted    = false; // true after successful send — shows confirmation
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
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit(String endpoint) async {
    UIHelper.unfocus(context);
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
              // ── Hero header ──────────────────────────────────────────────
              SliverToBoxAdapter(child: _buildHeader()),

              // ── Body ─────────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: _submitted ? _buildConfirmation() : _buildForm(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero header ────────────────────────────────────────────────────────────

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
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textOnDark,
                size:  AppSpacing.iconMd,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            width:  AppSpacing.iconXl + AppSpacing.lg,
            height: AppSpacing.iconXl + AppSpacing.lg,
            decoration: AppDecorations.iconCircle(
              bg: AppColors.textOnDark.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              color: AppColors.textOnDark,
              size:  AppSpacing.iconLg + AppSpacing.sm,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Account Recovery',
              style: AppTypography.displayLg(color: AppColors.textOnDark)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter your email to recover your\npassword or username.',
            style: AppTypography.body(
                color: AppColors.textOnDark.withValues(alpha: 0.75)),
          ),
        ],
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
        autovalidateMode: AutovalidateMode.onUserInteraction,
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

            // Email field
            Text('Email',
                style: AppTypography.label(
                    size: 13, color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.xs),
            TextFormField(
              controller:      _emailController,
              keyboardType:    TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              style:           AppTypography.bodyMedium(),
              decoration: InputDecoration(
                hintText:   'Enter your email address',
                hintStyle:  AppTypography.body(color: AppColors.textHint),
                prefixIcon: const Icon(Icons.mail_outline_rounded,
                    size: AppSpacing.iconSm, color: AppColors.textDisabled),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please enter your email';
                if (!v.trim().isValidEmail) return 'Enter a valid email address';
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
                        size: AppSpacing.iconSm, color: AppColors.error),
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

            // Reset password button
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
                onPressed: () => _submit('/auth/password-reset-request'),
                child: const Text('Send Reset Link'),
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Divider
            Row(children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text('or',
                    style: AppTypography.caption()),
              ),
              const Expanded(child: Divider()),
            ]),

            const SizedBox(height: AppSpacing.md),

            // Forgot username button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoading
                    ? null
                    : () => _submit('/auth/forgot-username'),
                child: const Text('Email me my Username'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirmation state (after submit) ─────────────────────────────────────

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
              child: const Text('Back to Login'),
            ),
          ),
        ],
      ),
    );
  }
}