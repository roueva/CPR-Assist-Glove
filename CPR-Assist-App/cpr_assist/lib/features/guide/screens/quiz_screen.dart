import 'package:flutter/material.dart';

import 'package:cpr_assist/core/core.dart';

// ─────────────────────────────────────────────────────────────────────────────
// QuizScreen — CPR Knowledge Quiz
//
// 10 multiple-choice questions covering AHA/ERC 2020 guidelines.
// No login required. No backend. Self-contained.
// Entry point: Guide screen hero "Test your knowledge" button.
// ─────────────────────────────────────────────────────────────────────────────

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int  _current  = 0;
  int  _score    = 0;
  int? _selected; // index of tapped answer, null = not yet answered
  bool _finished = false;

  static const _questions = [
    _Question(
      question: 'What is the correct compression depth for adult CPR?',
      options:  ['2–3 cm', '3–4 cm', '5–6 cm', '7–8 cm'],
      correct:  2,
      explanation: 'AHA/ERC 2020: compress at least 5 cm (2 inches) but no more than 6 cm (2.4 inches) in adults.',
    ),
    _Question(
      question: 'What is the target compression rate for adult CPR?',
      options:  ['60–80 per minute', '80–100 per minute', '100–120 per minute', '120–140 per minute'],
      correct:  2,
      explanation: 'AHA/ERC 2020: 100–120 compressions per minute is the recommended rate.',
    ),
    _Question(
      question: 'What does full chest recoil mean?',
      options:  [
        'Pressing hard enough to feel the sternum move',
        'Allowing the chest to fully rise between compressions',
        'Keeping hands on the chest at all times',
        'Compressing at a steady, slow pace',
      ],
      correct:  1,
      explanation: 'Full recoil allows the heart to refill with blood between compressions. Leaning on the chest reduces cardiac output.',
    ),
    _Question(
      question: 'What is the standard compression-to-ventilation ratio for a single adult rescuer?',
      options:  ['15:1', '15:2', '30:1', '30:2'],
      correct:  3,
      explanation: 'AHA/ERC 2020: 30 compressions followed by 2 rescue breaths for a single adult rescuer.',
    ),
    _Question(
      question: 'Where should you place your hands for adult chest compressions?',
      options:  [
        'Upper half of the sternum',
        'Lower half of the sternum, centre of the chest',
        'Directly over the heart, left side of chest',
        'Just below the collarbone',
      ],
      correct:  1,
      explanation: 'Place the heel of one hand on the lower half of the sternum (breastbone), in the centre of the chest.',
    ),
    _Question(
      question: 'What is the correct compression depth for infant CPR?',
      options:  ['1–2 cm', '2–3 cm', '4–5 cm', '5–6 cm'],
      correct:  2,
      explanation: 'AHA/ERC 2020: For infants, compress approximately 4 cm (1.5 inches) — about one-third of the chest depth.',
    ),
    _Question(
      question: 'What is Hands-On Time (Chest Compression Fraction)?',
      options:  [
        'The percentage of time compressions are performed during CPR',
        'How hard you press during each compression',
        'The rate of compressions per minute',
        'Time from collapse to first defibrillation',
      ],
      correct:  0,
      explanation: 'CCF is the proportion of resuscitation time spent doing compressions. Target is ≥ 60%, ideally ≥ 80%.',
    ),
    _Question(
      question: 'When should an AED be used?',
      options:  [
        'Only after 10 minutes of CPR',
        'As soon as it is available — use it immediately',
        'Only if the patient is unconscious and breathing',
        'Only by trained medical professionals',
      ],
      correct:  1,
      explanation: 'Every minute without defibrillation reduces survival by ~10%. Use the AED as soon as it is available.',
    ),
    _Question(
      question: 'How long should each rescue breath take?',
      options:  ['Less than 0.5 seconds', '1 second (until visible chest rise)', '3–4 seconds', '5 seconds'],
      correct:  1,
      explanation: 'Give each breath over about 1 second, just enough to see the chest rise. Over-ventilation reduces cardiac output.',
    ),
    _Question(
      question: 'What is the first step when you find an unresponsive person?',
      options:  [
        'Begin chest compressions immediately',
        'Open the airway and check for breathing',
        'Check scene safety, then check for responsiveness',
        'Call 112 before approaching',
      ],
      correct:  2,
      explanation: 'Always ensure scene safety first. Then check responsiveness (tap and shout). Only then call for help and begin CPR.',
    ),
  ];

  void _selectAnswer(int index) {
    if (_selected != null) return; // already answered
    final correct = _questions[_current].correct == index;
    setState(() {
      _selected = index;
      if (correct) _score++;
    });
  }

  void _next() {
    if (_current < _questions.length - 1) {
      setState(() {
        _current++;
        _selected = null;
      });
    } else {
      setState(() => _finished = true);
    }
  }

  void _restart() {
    setState(() {
      _current  = 0;
      _score    = 0;
      _selected = null;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.screenBgGrey,
      appBar: AppBar(
        backgroundColor:        AppColors.headerBg,
        elevation:              0,
        scrolledUnderElevation: 0,
        toolbarHeight:          AppSpacing.headerHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary),
          onPressed: context.pop,
        ),
        title: Text('CPR Knowledge Quiz',
            style: AppTypography.heading(size: 18)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(AppSpacing.dividerThickness),
          child: Divider(
              height: AppSpacing.dividerThickness, color: AppColors.divider),
        ),
      ),
      body: _finished ? _buildResults() : _buildQuestion(),
    );
  }

  // ── Question view ──────────────────────────────────────────────────────────

  Widget _buildQuestion() {
    final q           = _questions[_current];
    final answered    = _selected != null;
    final progress    = (_current + 1) / _questions.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Progress bar + counter
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                  BorderRadius.circular(AppSpacing.buttonRadiusLg),
                  child: LinearProgressIndicator(
                    value:           progress,
                    minHeight:       6,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${_current + 1} / ${_questions.length}',
                style: AppTypography.caption(color: AppColors.textSecondary),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // Score running total
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: AppDecorations.chip(
              color: AppColors.success,
              bg:    AppColors.successBg,
            ),
            child: Text('Score: $_score / ${_current + (answered ? 1 : 0)}',
                style: AppTypography.badge(
                    size: 11, color: AppColors.success)),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Question card
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: AppDecorations.primaryDarkCard(),
            child: Text(
              q.question,
              style: AppTypography.subheading(
                  size: 15, color: AppColors.textOnDark),
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Answer options
          ...List.generate(q.options.length, (i) {
            final isSelected = _selected == i;
            final isCorrect  = q.correct == i;
            final showResult = answered;

            Color bgColor     = AppColors.surfaceWhite;
            Color borderColor = AppColors.divider;
            Color textColor   = AppColors.textPrimary;
            IconData? icon;

            if (showResult) {
              if (isCorrect) {
                bgColor     = AppColors.successBg;
                borderColor = AppColors.success;
                textColor   = AppColors.success;
                icon        = Icons.check_circle_rounded;
              } else if (isSelected) {
                bgColor     = AppColors.errorBg;
                borderColor = AppColors.error;
                textColor   = AppColors.error;
                icon        = Icons.cancel_rounded;
              }
            } else if (isSelected) {
              bgColor     = AppColors.primaryLight;
              borderColor = AppColors.primary;
              textColor   = AppColors.primary;
            }

            return GestureDetector(
              onTap: () => _selectAnswer(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.cardPadding),
                decoration: BoxDecoration(
                  color:        bgColor,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: borderColor, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color:      AppColors.shadowDefault,
                      blurRadius: 6,
                      offset:     Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Option letter badge
                    Container(
                      width:  AppSpacing.lg,
                      height: AppSpacing.lg,
                      decoration: BoxDecoration(
                        color:  showResult && isCorrect
                            ? AppColors.success
                            : showResult && isSelected
                            ? AppColors.error
                            : AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          String.fromCharCode(65 + i), // A B C D
                          style: AppTypography.label(
                            size:  12,
                            color: (showResult && (isCorrect || isSelected))
                                ? AppColors.textOnDark
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        q.options[i],
                        style: AppTypography.body(
                            size: 14, color: textColor),
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Icon(icon, size: AppSpacing.iconSm, color: textColor),
                    ],
                  ],
                ),
              ),
            );
          }),

          // Explanation (shown after answer)
          if (answered) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.tintedCard(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: AppSpacing.iconSm, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      q.explanation,
                      style: AppTypography.body(
                          size: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: AppSpacing.touchTargetLarge,
              child: ElevatedButton(
                onPressed: _next,
                child: Text(
                  _current < _questions.length - 1
                      ? 'Next Question'
                      : 'See Results',
                  style: AppTypography.buttonPrimary(),
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  // ── Results view ───────────────────────────────────────────────────────────

  Widget _buildResults() {
    final pct     = _score / _questions.length;
    final isPass  = pct >= 0.7;
    final color   = pct >= 0.9
        ? AppColors.success
        : pct >= 0.7
        ? AppColors.info
        : pct >= 0.5
        ? AppColors.warning
        : AppColors.error;

    final label   = pct >= 0.9
        ? 'Excellent!'
        : pct >= 0.7
        ? 'Good job!'
        : pct >= 0.5
        ? 'Keep studying!'
        : 'Keep practicing!';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [

          const SizedBox(height: AppSpacing.lg),

          // Score circle
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            decoration: AppDecorations.primaryDarkCard(),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width:  140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value:           pct,
                        strokeWidth:     10,
                        strokeCap:       StrokeCap.round,
                        backgroundColor:
                        AppColors.textOnDark.withValues(alpha: 0.15),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_score/${_questions.length}',
                          style: AppTypography.numericDisplay(
                              size: 36, color: AppColors.textOnDark),
                        ),
                        Text(
                          label,
                          style: AppTypography.label(
                              size:  12,
                              color: AppColors.textOnDark
                                  .withValues(alpha: 0.8)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${(pct * 100).round()}% correct',
                  style: AppTypography.body(
                      color: AppColors.textOnDark.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Pass / fail message
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: isPass
                ? AppDecorations.successCard()
                : AppDecorations.warningCard(),
            child: Row(
              children: [
                Icon(
                  isPass
                      ? Icons.check_circle_outline_rounded
                      : Icons.menu_book_rounded,
                  color: isPass ? AppColors.success : AppColors.warning,
                  size:  AppSpacing.iconMd,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    isPass
                        ? 'You have a solid understanding of CPR guidelines. '
                        'Review the Guide to reinforce your knowledge.'
                        : 'Review the CPR Guide to strengthen your knowledge '
                        'before your next session.',
                    style: AppTypography.body(
                      size:  13,
                      color: isPass
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // Retry button
          SizedBox(
            width: double.infinity,
            height: AppSpacing.touchTargetLarge,
            child: ElevatedButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Try Again', style: AppTypography.buttonPrimary()),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),

          // Back to guide
          SizedBox(
            width: double.infinity,
            height: AppSpacing.touchTargetLarge,
            child: OutlinedButton(
              onPressed: context.pop,
              child: Text('Back to Guide',
                  style: AppTypography.buttonSecondary()),
            ),
          ),

          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────────────────────

class _Question {
  final String       question;
  final List<String> options;
  final int          correct;
  final String       explanation;

  const _Question({
    required this.question,
    required this.options,
    required this.correct,
    required this.explanation,
  });
}