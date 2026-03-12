import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Simulation112Dialog
//
// Step-through simulation of a 112 emergency call.
// Used inside the Guide screen — no login required.
// ─────────────────────────────────────────────────────────────────────────────

class Simulation112Dialog extends StatefulWidget {
  const Simulation112Dialog({super.key});

  @override
  State<Simulation112Dialog> createState() => _Simulation112DialogState();
}

class _Simulation112DialogState extends State<Simulation112Dialog> {
  int _step = 0;

  static const _steps = [
    _Step(
      question: 'Dispatcher: "112, what is your emergency?"',
      answer: 'You: "I need an ambulance. Someone is unconscious and not breathing."',
    ),
    _Step(
      question: 'Dispatcher: "What is your exact location?"',
      answer: 'You: "[State your address or describe landmarks]\nExample: 123 Main Street, Athens, near the central park"',
    ),
    _Step(
      question: 'Dispatcher: "Is the person breathing?"',
      answer: 'You: "No, they are not breathing."',
    ),
    _Step(
      question: 'Dispatcher: "Are you trained in CPR?"',
      answer: 'You: "Yes" or "No, but I can follow instructions."',
    ),
    _Step(
      question: 'Dispatcher: "Start chest compressions. Push hard and fast in the center of the chest."',
      answer: 'You: "Okay, I am starting compressions now."\n[Begin CPR: 100–120 compressions per minute]',
    ),
    _Step(
      question: 'Dispatcher: "Is there an AED nearby?"',
      answer: 'You: "Let me check…" [Use AED Map to locate]\n"Yes, there is one at [location]" or "No"',
    ),
    _Step(
      question: 'Dispatcher: "Continue CPR until help arrives. Do not stop."',
      answer: 'You: "Understood. I will continue."\n[Keep performing CPR until the ambulance arrives]',
    ),
  ];

  void _next() {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      context.pop();
    }
  }

  void _prev() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final current  = _steps[_step];
    final isLast   = _step == _steps.length - 1;
    final isFirst  = _step == 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dialogInsetH,
        vertical:   AppSpacing.dialogInsetV,
      ),
      child: Container(
        decoration: AppDecorations.dialog(),
        padding: const EdgeInsets.all(AppSpacing.dialogPaddingH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: AppDecorations.iconCircle(bg: AppColors.emergencyBg),
                  child: const Icon(
                    Icons.phone_rounded,
                    color: AppColors.emergencyRed,
                    size: AppSpacing.iconMd,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs), // 12
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('112 Emergency Call',
                          style: AppTypography.heading(size: 17)),
                      Text('Training Simulation',
                          style: AppTypography.caption(
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  onPressed: context.pop,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Step progress bar ────────────────────────────────────────────
            Row(
              children: List.generate(_steps.length, (i) {
                return Expanded(
                  child: Container(
                    height: AppSpacing.xxs + AppSpacing.xxs, // 4
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? AppColors.emergencyRed
                          : AppColors.divider,
                      borderRadius: BorderRadius.circular(AppSpacing.xxs),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Dispatcher question ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.emergencyCard(
                radius: AppSpacing.cardRadiusSm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.headset_mic_rounded,
                      color: AppColors.emergencyRed,
                      size: AppSpacing.iconSm + AppSpacing.xxs), // 20
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                  Expanded(
                    child: Text(
                      current.question,
                      style: AppTypography.bodyMedium(
                        size: 13,
                        color: AppColors.emergencyRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // ── Your response ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.primaryCard(
                radius: AppSpacing.cardRadiusSm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.person_rounded,
                      color: AppColors.primary,
                      size: AppSpacing.iconSm + AppSpacing.xxs),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                  Expanded(
                    child: Text(
                      current.answer,
                      style: AppTypography.body(
                        size: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Navigation buttons ───────────────────────────────────────────
            Row(
              children: [
                if (!isFirst) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _prev,
                      child: Text('Previous',
                          style: AppTypography.buttonSecondary()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emergencyRed,
                      foregroundColor: AppColors.textOnDark,
                    ),
                    child: Text(
                      isLast ? 'Finish' : 'Next',
                      style: AppTypography.buttonPrimary(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for each step
// ─────────────────────────────────────────────────────────────────────────────

class _Step {
  final String question;
  final String answer;
  const _Step({required this.question, required this.answer});
}