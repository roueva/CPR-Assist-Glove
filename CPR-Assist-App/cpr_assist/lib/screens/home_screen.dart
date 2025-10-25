import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/decrypted_data.dart';
import '../services/aed_map/aed_map.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/safe_fonts.dart';


class HomeScreen extends ConsumerStatefulWidget {
  final DecryptedData decryptedDataHandler;
  final bool isLoggedIn;
  final Function(int) onTabTapped;

  const HomeScreen({
    super.key,
    required this.decryptedDataHandler,
    required this.isLoggedIn,
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
        Expanded(child: AEDMapWidget()), // 🗺 Map fills remaining space
      ],
    );
  }

  Widget _buildLandscapeLayout() {
    return Column(
      children: [
        _buildEmergencyHeader(isLandscape: true),
        Expanded(child: AEDMapWidget()),  // 🗺 Fill remaining space
      ],
    );
  }

  Widget _buildEmergencyHeader({bool isVertical = false, bool isLandscape = false}) {
    return Container(
      padding: isVertical
          ? const EdgeInsets.symmetric(horizontal: 10)
          : isLandscape
          ? const EdgeInsets.symmetric(vertical: 10)
          : const EdgeInsets.symmetric(vertical: 22),
      color: const Color(0xFFB53B3B),
      child: GestureDetector(
        onTap: _makeEmergencyCall,
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
              "Call 112",
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
}
