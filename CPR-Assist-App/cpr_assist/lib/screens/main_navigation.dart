import 'package:cpr_assist/widgets/universal_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import '../providers/app_providers.dart';
import '../utils/safe_fonts.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'live_cpr_screen.dart';
import 'login_screen.dart';
import '../services/decrypted_data.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

  // Screens (lazy init for Training)
  late final HomeScreen _homeScreen;
  late final LiveCPRScreen _liveScreen;
  late final DecryptedData _decryptedDataHandler;


  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _decryptedDataHandler = ref.read(decryptedDataProvider);

    _homeScreen = HomeScreen(
      decryptedDataHandler: _decryptedDataHandler,
      onTabTapped: _onTabTapped,
    );

    _liveScreen = LiveCPRScreen(onTabTapped: _onTabTapped);
  }

  void _onTabTapped(int index) async {
    if (index == 2) {
      // ✅ Read current auth state from provider
      final isLoggedIn = ref.read(authStateProvider).isLoggedIn;

      if (!isLoggedIn) {
        final loggedIn = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(
              dataStream: _decryptedDataHandler.dataStream,
              decryptedDataHandler: _decryptedDataHandler,
              onLoginSuccess: () {
                _onTabTapped(2); // 👈 Automatically switch to Guide after login
              },
            ),
          ),
        );

        if (loggedIn != true) return; // ⛔️ Stop here if user canceled login
      }
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
      appBar: UniversalHeader.forMainScreens(
        decryptedDataHandler: _decryptedDataHandler,
        currentIndex: _currentIndex,
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
// AFTER line 75 (in the PageView children), REPLACE with:

          children: [
            _homeScreen,
            _liveScreen,
            const GuideScreen(),
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
          fontWeight: FontWeight.w500,
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
            label: 'AED Map', // ✅ Changed to match thesis
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
            label: 'Live CPR', // ✅ Changed to match thesis
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
            label: 'Guide', // ✅ Changed to match thesis
          ),
        ],
      ),
    );
  }
}