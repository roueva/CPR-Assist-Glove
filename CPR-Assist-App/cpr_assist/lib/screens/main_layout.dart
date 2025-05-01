  import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
  import 'package:shared_preferences/shared_preferences.dart';
  import '../main.dart';
  import '../widgets/account_menu.dart';
  import '../widgets/battery_widget.dart';
  import '../widgets/ble_status_indicator.dart';
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
    int get gloveBatteryPercentage => 96; // replace later
    bool get isGloveCharging => false; // replace later


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
          appBar: AppBar(
            toolbarHeight: 45,
              title: Row(
                children: [
                  SvgPicture.asset(
                    "assets/icons/logo.svg",
                    width: 28.6,
                    height: 28,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      "CPR Assist",
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        letterSpacing: 0.0,
                        color: const Color(0xFF194E9D),
                      ),
                    ),
                  ),
                ],
              ),
            centerTitle: true,
            backgroundColor: _currentIndex == 1 ? const Color(0xFFEDF4F9) : Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
              actions: [
                // Bluetooth + Battery Combined Container
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                      color: _currentIndex == 1 ? Colors.white : const Color(0xFFE3EFF8),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BLEStatusIndicator(
                          bleConnection: globalBLEConnection,
                          connectionStatusNotifier: globalBLEConnection.connectionStatusNotifier,
                        ),
                        const SizedBox(width: 4),
                        Tooltip(
                          message: isGloveCharging
                              ? 'Charging: $gloveBatteryPercentage%'
                              : 'Battery: $gloveBatteryPercentage%',
                          triggerMode: TooltipTriggerMode.tap,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          textStyle: const TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          showDuration: const Duration(seconds: 2),
                          child: GloveBatteryIndicator(
                            batteryPercentage: gloveBatteryPercentage,
                            isCharging: isGloveCharging,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Account Icon
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _currentIndex == 1 ? Colors.white : const Color(0xFFE3EFF8),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AccountMenu(
                        decryptedDataHandler: widget.decryptedDataHandler,
                      ),
                    ),
                  ),
                ),
              ],
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
            selectedLabelStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            unselectedLabelStyle: GoogleFonts.poppins(
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
