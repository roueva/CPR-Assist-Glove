import 'package:flutter/material.dart';
import '../utils/safe_fonts.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDF4F9),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('CPR Quick Steps'),
            const SizedBox(height: 12),
            _buildStepCard(
              step: 1,
              title: 'Check Scene Safety',
              description: 'Ensure the area is safe for you and the victim before approaching.',
              icon: Icons.security,
              color: Colors.blue,
            ),
            _buildStepCard(
              step: 2,
              title: 'Check Responsiveness',
              description: 'Tap the person\'s shoulder and shout "Are you okay?"',
              icon: Icons.touch_app,
              color: Colors.orange,
            ),
            _buildStepCard(
              step: 3,
              title: 'Call 112 (Emergency Only)',
              description: 'Call emergency services immediately. In training mode, use the simulation.',
              icon: Icons.phone,
              color: Colors.red,
            ),
            _buildStepCard(
              step: 4,
              title: 'Find Nearest AED',
              description: 'Use the AED Map tab to locate the closest defibrillator.',
              icon: Icons.location_on,
              color: Colors.green,
            ),
            _buildStepCard(
              step: 5,
              title: 'Start CPR',
              description: 'Begin chest compressions immediately. Use Live CPR tab for real-time guidance.',
              icon: Icons.favorite,
              color: Colors.pink,
            ),

            const SizedBox(height: 24),
            _buildSectionTitle('Chest Compressions'),
            const SizedBox(height: 12),

            _buildInfoCard(
              icon: Icons.speed,
              title: 'Compression Rate',
              content: '100-120 compressions per minute\n(almost 2 per second)',
              color: Colors.blue,
            ),
            _buildInfoCard(
              icon: Icons.straighten,
              title: 'Compression Depth',
              content: '5-6 cm (2-2.4 inches)\nPush hard and fast',
              color: Colors.orange,
            ),
            _buildInfoCard(
              icon: Icons.pan_tool,
              title: 'Hand Position',
              content: 'Center of chest, between nipples\nHeel of one hand, other hand on top\nFingers interlaced',
              color: Colors.purple,
            ),
            _buildInfoCard(
              icon: Icons.expand,
              title: 'Full Recoil',
              content: 'Allow chest to return to normal position\nDon\'t lean on chest between compressions',
              color: Colors.teal,
            ),

            const SizedBox(height: 24),
            _buildSectionTitle('Rescue Breaths (if trained)'),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '30:2 Ratio',
                    style: SafeFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF194E9D),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• 30 chest compressions\n'
                        '• Then 2 rescue breaths\n'
                        '• Tilt head back, lift chin\n'
                        '• Pinch nose, seal mouth\n'
                        '• Give 1 breath over 1 second\n'
                        '• Watch for chest rise',
                    style: SafeFonts.inter(
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _buildSectionTitle('Using an AED'),
            const SizedBox(height: 12),

            _buildAEDStep(1, 'Turn on the AED', 'Open the case and press the power button'),
            _buildAEDStep(2, 'Expose the chest', 'Remove clothing and dry the chest if wet'),
            _buildAEDStep(3, 'Attach pads', 'Place pads exactly as shown in the pictures'),
            _buildAEDStep(4, 'Stand clear', 'Don\'t touch the person during analysis'),
            _buildAEDStep(5, 'Deliver shock if advised', 'Press the shock button when prompted'),
            _buildAEDStep(6, 'Resume CPR', 'Continue compressions immediately after shock'),

            const SizedBox(height: 24),
            _buildSectionTitle('Important Notes'),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Critical Reminders',
                        style: SafeFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Continue CPR until:\n'
                        '  - Help arrives\n'
                        '  - Person starts breathing\n'
                        '  - AED is ready to analyze\n'
                        '  - You are too exhausted\n\n'
                        '• Minimize interruptions\n'
                        '• Switch rescuers every 2 minutes if possible\n'
                        '• Don\'t give up - CPR saves lives!',
                    style: SafeFonts.inter(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.red.shade900,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: SafeFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF194E9D),
      ),
    );
  }

  Widget _buildStepCard({
    required int step,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step $step: $title',
                  style: SafeFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF194E9D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: SafeFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SafeFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF194E9D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: SafeFonts.inter(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAEDStep(int step, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF194E9D),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: SafeFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SafeFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  description,
                  style: SafeFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}