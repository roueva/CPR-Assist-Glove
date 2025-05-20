import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/ble_connection.dart';
import '../services/fake_ble_data.dart';
import '../widgets/depth_bar.dart';
import '../widgets/rotating_arrow.dart';


class LiveCPRScreen extends StatefulWidget {
  final Function(int) onTabTapped;
  const LiveCPRScreen({super.key, required this.onTabTapped});

  @override
  State<LiveCPRScreen> createState() => _LiveCPRScreenState();
}

class _LiveCPRScreenState extends State<LiveCPRScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  //fake ble data start

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: const Color(0xFFEDF4F9), // Light blue background
      child: StreamBuilder<Map<String, dynamic>>(
        // stream: FakeBleStreamService.stream,
        stream: BLEConnection.instance.dataStream,
        builder: (context, snapshot) {
          final data = snapshot.data ?? {};

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                PatientVitalsCard(),
                const SizedBox(height: 16),
                CprMetricsCard(
                 // frequency: (data['frequency'] as num?)?.toDouble() ?? 90, // simulation
                  frequency: (data['frequency'] as num?)?.toDouble() ?? 0,
                  // depth: (data['depth'] as num?)?.toDouble() ?? 0,  // simulation
                  depth: (data['weight'] as num?)?.toDouble() ?? 0, // depth comes from FSR (weight)
                ),
                const SizedBox(height: 16),
                UserVitalsCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class PatientVitalsCard extends StatelessWidget {
  const PatientVitalsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title outside the card
        Text(
          "Patient Vitals",
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Color(0xFF194E9D),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Heart Rate (Left side)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "110 bpm", // Placeholder value
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, // SemiBold
                        fontSize: 20,
                        color: Color(0xFF4D4A4A),
                      ),
                    ),
                    Text(
                      "HEART RATE",
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, // SemiBold
                        fontSize: 12,
                        color: Color(0xFF727272),
                      ),
                    ),
                  ],
                ),
              ),
              // Temperature (Right side)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "36.4°C", // Placeholder value
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, // SemiBold
                        fontSize: 20,
                        color: Color(0xFF4D4A4A),
                      ),
                    ),
                    Text(
                      "TEMPERATURE",
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, // SemiBold
                        fontSize: 12,
                        color: Color(0xFF727272),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CprMetricsCard extends StatelessWidget {
  final double frequency;
  final double depth;

  const CprMetricsCard({
    super.key,
    required this.frequency,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF335484), // Big dark blue card
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Two small stat cards: Compressions and CPR Time
          Row(
            children: [
              Expanded(child: _SmallInfoCard(value: "12", label: "COMPRESSIONS")),
              const SizedBox(width: 12),
              Expanded(child: _SmallInfoCard(value: "04:25", label: "CPR TIME")),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: 3,
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "FREQUENCY",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: [
                            Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/frequency_arc.svg',
                                  width: 200,
                                  height: 110,
                                ),
                                RotatingArrow(frequency: frequency),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              frequency.toStringAsFixed(0), // show as whole number
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 110, // match the icon's width
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          "DEPTH",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 116,
                          height: 140,
                          child: AnimatedDepthBar(
                            depth: depth,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// 🔥 Small info card widget
class _SmallInfoCard extends StatelessWidget {
  final String value;
  final String label;
  const _SmallInfoCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF315FA3), // Small card blue
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 24,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}


class UserVitalsCard extends StatelessWidget {
  const UserVitalsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title outside the card
        Text(
          "Your Vitals",
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Color(0xFF194E9D),
          ),
        ),
        const SizedBox(height: 2),
        // Card
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Heart Rate (Left side)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "98 bpm", // Placeholder for user heart rate
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, // SemiBold
                        fontSize: 20,
                        color: Color(0xFF4D4A4A),
                      ),
                    ),
                    Text(
                      "HEART RATE",
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Color(0xFF727272),
                      ),
                    ),
                  ],
                ),
              ),
              // Temperature (Right side)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "36.7°C", // Placeholder for user temperature
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, // SemiBold
                        fontSize: 20,
                        color: Color(0xFF4D4A4A),
                      ),
                    ),
                    Text(
                      "TEMPERATURE",
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: Color(0xFF727272),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // TEMPORARY MANUAL SIMULATION BUTTON
        GestureDetector(
          onLongPressStart: (_) {
            // Simulate compression
            FakeBleStreamService.simulatePress();
          },
          onLongPressEnd: (_) {
            // Simulate release
            FakeBleStreamService.simulateRelease();
          },
          child: Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF319E77),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              "Hold to Simulate Compression",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        )
      ],
    );
  }
}
