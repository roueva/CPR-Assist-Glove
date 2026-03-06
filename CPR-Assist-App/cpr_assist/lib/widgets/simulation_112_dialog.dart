import 'package:flutter/material.dart';
import '../utils/safe_fonts.dart';

class Simulation112Dialog extends StatefulWidget {
  const Simulation112Dialog({super.key});

  @override
  State<Simulation112Dialog> createState() => _Simulation112DialogState();
}

class _Simulation112DialogState extends State<Simulation112Dialog> {
  int _currentStep = 0;

  final List<Map<String, String>> _dispatcherQuestions = [
    {
      'question': 'Dispatcher: "112, what is your emergency?"',
      'answer': 'You: "I need an ambulance. Someone is unconscious and not breathing."',
    },
    {
      'question': 'Dispatcher: "What is your exact location?"',
      'answer': 'You: "[State your address or describe landmarks]\nExample: 123 Main Street, Athens, near the central park"',
    },
    {
      'question': 'Dispatcher: "Is the person breathing?"',
      'answer': 'You: "No, they are not breathing."',
    },
    {
      'question': 'Dispatcher: "Are you trained in CPR?"',
      'answer': 'You: "Yes" or "No, but I can follow instructions."',
    },
    {
      'question': 'Dispatcher: "Start chest compressions. Push hard and fast in the center of the chest."',
      'answer': 'You: "Okay, I am starting compressions now."\n[Begin CPR: 100-120 compressions per minute]',
    },
    {
      'question': 'Dispatcher: "Is there an AED nearby?"',
      'answer': 'You: "Let me check..." [Use AED Map to locate]\n"Yes, there is one at [location]" or "No"',
    },
    {
      'question': 'Dispatcher: "Continue CPR until help arrives. Do not stop."',
      'answer': 'You: "Understood. I will continue."\n[Keep performing CPR until ambulance arrives]',
    },
  ];

  void _nextStep() {
    if (_currentStep < _dispatcherQuestions.length - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentQ = _dispatcherQuestions[_currentStep];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB53B3B).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.phone,
                    color: Color(0xFFB53B3B),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '112 Emergency Call',
                        style: SafeFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Training Simulation',
                        style: SafeFonts.inter(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Progress indicator
            Row(
              children: List.generate(
                _dispatcherQuestions.length,
                    (index) => Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: index <= _currentStep
                          ? const Color(0xFFB53B3B)
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Question
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.headset_mic, color: Color(0xFFB53B3B), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      currentQ['question']!,
                      style: SafeFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFB53B3B),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Answer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.person, color: Color(0xFF194E9D), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      currentQ['answer']!,
                      style: SafeFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF194E9D),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Navigation buttons
            Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousStep,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Previous',
                        style: SafeFonts.inter(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFB53B3B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      _currentStep == _dispatcherQuestions.length - 1
                          ? 'Finish'
                          : 'Next',
                      style: SafeFonts.inter(fontWeight: FontWeight.w600),
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