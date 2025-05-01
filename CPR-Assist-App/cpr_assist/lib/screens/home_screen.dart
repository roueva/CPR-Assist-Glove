import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../services/decrypted_data.dart';
import '../services/ble_connection.dart';
import '../services/aed_map/aed_map.dart';
import 'package:flutter_svg/flutter_svg.dart';


class HomeScreen extends StatefulWidget {
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

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  BLEConnection bleConnection = globalBLEConnection; // ✅ Use global instance
  String connectionStatus = "Disconnected";


  /// **📞 Make Emergency Call**
  void _makeEmergencyCall() {
    launchUrl(Uri.parse('tel:112'));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.only(top: 22, bottom: 22),
                decoration: const BoxDecoration(
                  color: Color(0xFFB53B3B), // your custom red
                ),
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
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        /// Map below
        Expanded(
          child: AEDMapWidget(),
        ),
      ],
    );
  }
}
