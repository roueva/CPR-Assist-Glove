import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/network_service_provider.dart';
import '../services/decrypted_data.dart';
import 'login_screen.dart';

class PastSessionsScreen extends ConsumerStatefulWidget {
  final Stream<Map<String, dynamic>> dataStream;
  final DecryptedData decryptedDataHandler;

  const PastSessionsScreen({
    super.key,
    required this.dataStream,
    required this.decryptedDataHandler,
  });

  @override
  _PastSessionsScreenState createState() => _PastSessionsScreenState();
}

class _PastSessionsScreenState extends ConsumerState<PastSessionsScreen> {
  List<dynamic> sessionSummaries = [];
  bool isLoading = true;
  String? errorMessage;
  String selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    fetchSessionSummaries();
  }

  Future<void> fetchSessionSummaries() async {
    try {
      debugPrint('Fetching session summaries...');
      final networkService = ref.read(networkServiceProvider);
      final response = await networkService.get('/sessions/summaries', requiresAuth: true);

      if (response['success'] == true && response['data'] is List) {
        setState(() {
          sessionSummaries = response['data'];
          isLoading = false;
        });
      } else {
        throw Exception('Unexpected response format');
      }
    } catch (e) {
      debugPrint('Error fetching session summaries: $e');
      if (e.toString().contains('401')) {
        final networkService = ref.read(networkServiceProvider);
        await networkService.removeToken();
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => LoginScreen(
              dataStream: widget.dataStream,
              decryptedDataHandler: widget.decryptedDataHandler,
            ),
          ),
              (route) => false,
        );
      } else {
        setState(() {
          errorMessage = 'Failed to fetch session summaries: $e';
          isLoading = false;
        });
      }
    }
  }

  List<dynamic> get filteredSessions {
    if (selectedFilter == 'All') return sessionSummaries;

    switch (selectedFilter) {
      case 'Excellent':
        return sessionSummaries.where((s) => (s['total_grade'] ?? 0) >= 90).toList();
      case 'Good':
        return sessionSummaries.where((s) => (s['total_grade'] ?? 0) >= 70 && (s['total_grade'] ?? 0) < 90).toList();
      case 'Recent':
        return sessionSummaries.take(10).toList();
      default:
        return sessionSummaries;
    }
  }

  double _calculateGrade(Map<String, dynamic> session) {
    final compressions = session['compression_count'] ?? 0;
    if (compressions == 0) return 0.0;

    final correctDepth = session['correct_depth'] ?? 0;
    final correctFreq = session['correct_frequency'] ?? 0;
    final correctRecoil = session['correct_recoil'] ?? 0;

    // Simple grade calculation - you can adjust this formula
    final score = (correctDepth + correctFreq + correctRecoil) / (3 * compressions) * 100;
    return score.clamp(0, 100);
  }

  Color _getGradeColor(double grade) {
    if (grade >= 90) return const Color(0xFF4CAF50); // Green
    if (grade >= 70) return const Color(0xFF2196F3); // Blue
    if (grade >= 50) return const Color(0xFFF57C00); // Orange
    return const Color(0xFFF44336); // Red
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return "$minutes:$remainingSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF4F9), // Same as your other screens
      appBar: AppBar(
        backgroundColor: const Color(0xFFEDF4F9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF194E9D)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Training History',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Color(0xFF194E9D),
          ),
        ),
      ),
      body: isLoading
          ? const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF194E9D)),
        ),
      )
          : errorMessage != null
          ? _buildErrorState()
          : sessionSummaries.isEmpty
          ? _buildEmptyState()
          : _buildSessionsList(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                isLoading = true;
                errorMessage = null;
              });
              fetchSessionSummaries();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF194E9D),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Training Sessions Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Complete your first training session\nto see your progress here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsList() {
    return Column(
      children: [
        // Statistics Header
        _buildStatsHeader(),

        // Filter Tabs
        _buildFilterTabs(),

        // Sessions List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: filteredSessions.length,
            itemBuilder: (context, index) {
              final session = filteredSessions[index];
              return _buildSessionCard(session, filteredSessions.length - index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatsHeader() {
    final totalSessions = sessionSummaries.length;
    final avgGrade = sessionSummaries.isEmpty
        ? 0.0
        : sessionSummaries.map((s) => _calculateGrade(s)).reduce((a, b) => a + b) / totalSessions;
    final totalCompressions = sessionSummaries.fold<int>(0, (sum, s) => sum + (s['compression_count'] as int? ?? 0));
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF335484), // Same blue as your CprMetricsCard
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
          Expanded(
            child: _buildStatItem('Total Sessions', totalSessions.toString()),
          ),
          Expanded(
            child: _buildStatItem('Average Grade', '${avgGrade.toStringAsFixed(0)}%'),
          ),
          Expanded(
            child: _buildStatItem('Total Compressions', totalCompressions.toString()),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    final filters = ['All', 'Recent', 'Excellent', 'Good'];

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  selectedFilter = filter;
                });
              },
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF194E9D),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF194E9D),
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, int sessionNumber) {
    final formattedDate = DateFormat('MMM dd, yyyy • HH:mm')
        .format(DateTime.parse(session['session_start']));
    final grade = _calculateGrade(session);
    final duration = _formatDuration(session['session_duration'] ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showSessionDetails(session, sessionNumber),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Session $sessionNumber',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF194E9D),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getGradeColor(grade),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${grade.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Date and Duration
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Color(0xFF727272),
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Stats Row
                Row(
                  children: [
                    _buildQuickStat(Icons.compress, 'Compressions', '${session['compression_count'] ?? 0}'),
                    const SizedBox(width: 16),
                    _buildQuickStat(Icons.timer, 'Duration', duration),
                    const SizedBox(width: 16),
                    _buildQuickStat(Icons.speed, 'Correct Depth', '${session['correct_depth'] ?? 0}'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStat(IconData icon, String label, String value) {
    return Expanded(
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: const Color(0xFF727272),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF4D4A4A),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: Color(0xFF727272),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSessionDetails(Map<String, dynamic> session, int sessionNumber) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SessionDetailsModal(
        session: session,
        sessionNumber: sessionNumber,
        calculateGrade: _calculateGrade,
        formatDuration: _formatDuration,
      ),
    );
  }
}

class SessionDetailsModal extends StatelessWidget {
  final Map<String, dynamic> session;
  final int sessionNumber;
  final double Function(Map<String, dynamic>) calculateGrade;
  final String Function(int) formatDuration;

  const SessionDetailsModal({
    super.key,
    required this.session,
    required this.sessionNumber,
    required this.calculateGrade,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    final grade = calculateGrade(session);
    final formattedDate = DateFormat('MMMM dd, yyyy • HH:mm')
        .format(DateTime.parse(session['session_start']));

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Color(0xFFEDF4F9),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  'Session $sessionNumber Details',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Color(0xFF194E9D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: Color(0xFF727272),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Grade Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF335484),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${grade.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.bold,
                            fontSize: 32,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'OVERALL GRADE',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Performance Details
                  _buildDetailCard('Performance Metrics', [
                    _buildDetailRow('Total Compressions', '${session['compression_count'] ?? 0}'),
                    _buildDetailRow('Correct Depth', '${session['correct_depth'] ?? 0}'),
                    _buildDetailRow('Correct Frequency', '${session['correct_frequency'] ?? 0}'),
                    _buildDetailRow('Correct Recoil', '${session['correct_recoil'] ?? 0}'),
                    _buildDetailRow('Session Duration', formatDuration(session['session_duration'] ?? 0)),
                  ]),
                  const SizedBox(height: 16),

                  // Vitals if available
                  if (session['patient_heart_rate'] != null || session['user_heart_rate'] != null)
                    _buildDetailCard('Vital Signs', [
                      if (session['patient_heart_rate'] != null)
                        _buildDetailRow('Patient Heart Rate', '${session['patient_heart_rate']} bpm'),
                      if (session['patient_temperature'] != null)
                        _buildDetailRow('Patient Temperature', '${session['patient_temperature']}°C'),
                      if (session['user_heart_rate'] != null)
                        _buildDetailRow('Your Heart Rate', '${session['user_heart_rate']} bpm'),
                      if (session['user_temperature_rate'] != null)
                        _buildDetailRow('Your Temperature', '${session['user_temperature_rate']}°C'),
                    ]),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF194E9D),
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              color: Color(0xFF727272),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF4D4A4A),
            ),
          ),
        ],
      ),
    );
  }
}