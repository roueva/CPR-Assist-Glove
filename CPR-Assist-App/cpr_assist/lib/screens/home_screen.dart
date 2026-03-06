import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_providers.dart';
import '../services/decrypted_data.dart';
import '../services/aed_map/aed_map.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/safe_fonts.dart';
import '../widgets/simulation_112_dialog.dart';


class HomeScreen extends ConsumerStatefulWidget {
  final DecryptedData decryptedDataHandler;
  final Function(int) onTabTapped;

  const HomeScreen({
    super.key,
    required this.decryptedDataHandler,
    required this.onTabTapped,
  });

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  String connectionStatus = "Disconnected";


  /// **📞 Make Emergency Call**
  void _makeEmergencyCall() {
    launchUrl(Uri.parse('tel:112'));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.watch(bleConnectionProvider);

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        return isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout();
      },
    );
  }

  Widget _buildPortraitLayout() {
    return Column(
      children: [
        _buildEmergencyHeader(),     // 🔴 Call 112 on top
        const Expanded(child: AEDMapWidget()), // 🗺 Map fills remaining space
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    return Column(
      children: [
        _buildEmergencyHeader(isLandscape: true),
        const Expanded(child: AEDMapWidget()),  // 🗺 Fill remaining space
      ],
    );
  }

  Widget _buildEmergencyHeader({bool isLandscape = false}) {
    final currentMode = ref.watch(appModeProvider);  // ✅ ADD
    final isTrainingMode = currentMode == AppMode.training;

    return Container(
      height: isLandscape ? 50 : 60,
      color: const Color(0xFFB53B3B),
      child: InkWell(
        onTap: isTrainingMode ? _showSimulation112Dialog : _makeEmergencyCall,  // ✅ CHANGED
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/phone_call.svg',
              height: 26,
              width: 26,
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Text(
              isTrainingMode ? "Simulation 112 Call" : "Call 112",  // ✅ CHANGED
              style: SafeFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

// ✅ ADD NEW METHOD
  void _showSimulation112Dialog() {
    showDialog(
      context: context,
      builder: (context) => const Simulation112Dialog(),
    );
  }
}
