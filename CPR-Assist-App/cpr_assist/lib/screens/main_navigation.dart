import 'package:cpr_assist/screens/universal_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/safe_fonts.dart';
import 'home_screen.dart';
import 'live_cpr_screen.dart';
import 'login_screen.dart';
import 'training_screen.dart';
import '../services/decrypted_data.dart';

class MainNavigationScreen extends StatefulWidget {
  final DecryptedData decryptedDataHandler;
  final bool isLoggedIn;

  const MainNavigationScreen({
    super.key,
    required this.decryptedDataHandler,
    required this.isLoggedIn,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

  // Screens (lazy init for Training)
  late final HomeScreen _homeScreen;
  late final LiveCPRScreen _liveScreen;
  TrainingScreen? _trainingScreen;

  //Battery status
  int get gloveBatteryPercentage => widget.decryptedDataHandler.batteryPercentageNotifier.value;
  bool get isGloveCharging => widget.decryptedDataHandler.isChargingNotifier.value;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);

    _homeScreen = HomeScreen(
      decryptedDataHandler: widget.decryptedDataHandler,
      isLoggedIn: widget.isLoggedIn,
      onTabTapped: _onTabTapped,
    );

    _liveScreen = LiveCPRScreen(onTabTapped: _onTabTapped);
  }

  void _onTabTapped(int index) async {
    if (index == 2) {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (!isLoggedIn) {
        final loggedIn = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(
              dataStream: widget.decryptedDataHandler.dataStream,
              decryptedDataHandler: widget.decryptedDataHandler,
              onLoginSuccess: () {
                _onTabTapped(2); // 👈 Automatically switch to Training after login
              },
            ),
          ),
        );

        if (loggedIn != true) return; // ⛔️ Stop here if user canceled login
      }
      // Lazy load TrainingScreen
      _trainingScreen ??= TrainingScreen(
        dataStream: widget.decryptedDataHandler.dataStream,
        decryptedDataHandler: widget.decryptedDataHandler,
        onTabTapped: _onTabTapped,
      );
    }
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ Replace the entire AppBar with the new UniversalHeader
      appBar: UniversalHeader.forMainScreens(
        decryptedDataHandler: widget.decryptedDataHandler,
        currentIndex: _currentIndex,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _homeScreen,
          _liveScreen,
          _trainingScreen ?? const SizedBox(), // Lazy-loaded, safe fallback
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF194E9D),
        unselectedItemColor: const Color(0xFF797979),
        selectedLabelStyle: SafeFonts.poppins(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelStyle: SafeFonts.poppins(
          fontWeight: FontWeight.w500, // Medium weight
          fontSize: 14,
        ),
        items: [
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              'assets/icons/locations.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                _currentIndex == 0 ? const Color(0xFF194E9D) : const Color(0xFF797979),
                BlendMode.srcIn,
              ),
            ),
            label: 'Locations',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              'assets/icons/live.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                _currentIndex == 1 ? const Color(0xFF194E9D) : const Color(0xFF797979),
                BlendMode.srcIn,
              ),
            ),
            label: 'Live',
          ),
          BottomNavigationBarItem(
            icon: SvgPicture.asset(
              'assets/icons/training.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                _currentIndex == 2 ? const Color(0xFF194E9D) : const Color(0xFF797979),
                BlendMode.srcIn,
              ),
            ),
            label: 'Training',
          ),
        ],
      ),
    );
  }
}