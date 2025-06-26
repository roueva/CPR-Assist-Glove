import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/ble_connection.dart';
import '../widgets/depth_bar.dart';
import '../widgets/rotating_arrow.dart';

class LiveCPRScreen extends StatefulWidget {
  final Function(int) onTabTapped;
  const LiveCPRScreen({super.key, required this.onTabTapped});

  @override
  State<LiveCPRScreen> createState() => _LiveCPRScreenState();
}

class _LiveCPRScreenState extends State<LiveCPRScreen> with AutomaticKeepAliveClientMixin {
  double lastDepth = 0.0;
  double lastFrequency = 0.0;
  Timer? _resetTimer;
  int _displayCompressionCount = 0;
  Duration _displaySessionDuration = Duration.zero;
  bool _isSessionActive = false;
  double _displayDepth = 0.0;
  double _displayFrequency = 0.0;
  bool _hasHandledEndPing = false;
  double? _heartRatePatient;
  double? _temperaturePatient;
  double? _heartRateUser;
  double? _temperatureUser;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: const Color(0xFFEDF4F9),
      child:
      StreamBuilder<Map<String, dynamic>>(
        stream: BLEConnection.instance.dataStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _updateDisplayValues(snapshot.data!);
              }
            });
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                PatientVitalsCard(
              heartRate: _heartRatePatient,
              temperature: _temperaturePatient,
            ),
                const SizedBox(height: 16),
                CprMetricsCard(
                  depth: _displayDepth,
                  frequency: _displayFrequency,
                  cprTime: _displaySessionDuration,
                  compressionCount: _displayCompressionCount,
                  isSessionActive: _isSessionActive,
                ),
                const SizedBox(height: 16),
                 UserVitalsCard(
                  heartRate: _heartRateUser,
                  temperature: _temperatureUser,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _updateDisplayValues(Map<String, dynamic> data) {
    final sessionActive = data['isSessionActive'] == true;
    final isStartPing = data['startPing'] == true;
    final isEndPing = data['endPing'] == true;

    if (data.containsKey('heartRatePatient')) {
      final hr = (data['heartRatePatient'] as num).toDouble();
      if (hr > 0) _heartRatePatient = hr;
    }

    if (data.containsKey('temperaturePatient')) {
      final temp = (data['temperaturePatient'] as num).toDouble();
      if (temp > 0) _temperaturePatient = temp;
    }

    if (data.containsKey('heartRateUser')) {
      final hr = (data['heartRateUser'] as num).toDouble();
      if (hr > 0) _heartRateUser = hr;
    }

    if (data.containsKey('temperatureUser')) {
      final temp = (data['temperatureUser'] as num).toDouble();
      if (temp > 0) _temperatureUser = temp;
    }

    // Handle session state changes
    if (isStartPing) {
      setState(() {
        _isSessionActive = true;
        _displayDepth = 0.0;
        _displayFrequency = 0.0;
        _displayCompressionCount = 0;
        _displaySessionDuration = Duration.zero;
      });
      _hasHandledEndPing = false; // Reset here
      print('🟢 UI: Session started - all displays reset');
      return;
    }

    if (isEndPing && !_hasHandledEndPing) {
      setState(() {
        _isSessionActive = false;
        _displayDepth = 0.0;
        _displayFrequency = 0.0;
      });
      print('🔴 UI: Session ended - depth/frequency reset, count/time preserved');
      _hasHandledEndPing = true;
      return;
    }

    // Update values during active session or for final display
    if (mounted) {
      setState(() {
        _isSessionActive = sessionActive;

        // Always update compression count and session duration
        if (data.containsKey('compressionCount')) {
          _displayCompressionCount = data['compressionCount'] as int;
        }

        if (data.containsKey('sessionDuration')) {
          _displaySessionDuration = data['sessionDuration'] as Duration;
        }

        // Only update depth and frequency during active session
        if (_isSessionActive) {
          if (data.containsKey('depth')) {
            _displayDepth = (data['depth'] as num).toDouble();
          }

          if (data.containsKey('frequency')) {
            _displayFrequency = (data['frequency'] as num).toDouble();
          }
        }
      });
    }
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return "$minutes:$seconds";
}


class PatientVitalsCard extends StatelessWidget {
  final double? heartRate;
  final double? temperature;
  const PatientVitalsCard({
    super.key,
    this.heartRate,
    this.temperature,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                      heartRate != null ? "${heartRate!.toStringAsFixed(0)} bpm" : "--",
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
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
                      temperature != null ? "${temperature!.toStringAsFixed(1)}°C" : "--",
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
  final Duration cprTime;
  final int compressionCount;
  final bool isSessionActive;

  const CprMetricsCard({
    super.key,
    required this.frequency,
    required this.depth,
    required this.cprTime,
    required this.compressionCount,
    required this.isSessionActive,
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
              Expanded(child: _SmallInfoCard(value: compressionCount.toString(), label: "COMPRESSIONS")),
              const SizedBox(width: 12),
              Expanded(
                child: _SmallInfoCard(
                  value: _formatDuration(cprTime),
                  label: "CPR TIME",
                ),
              ),
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
  final double? heartRate;
  final double? temperature;

  const UserVitalsCard({
    super.key,
    required this.heartRate,
    required this.temperature,
  });

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
                      heartRate != null ? "${heartRate!.toStringAsFixed(0)} bpm" : "--",
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
                      temperature != null ? "${temperature!.toStringAsFixed(1)}°C" : "--",
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
      ],
    );
  }
}