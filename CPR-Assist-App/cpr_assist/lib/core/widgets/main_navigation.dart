import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

import 'package:cpr_assist/core/core.dart';

import '../../features/account/screens/account_menu.dart';
import '../../features/aed_map/screens/aed_map_screen.dart';
import '../../features/guide/screens/guide_screen.dart';
import '../../features/live_cpr/screens/live_cpr_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState
    extends ConsumerState<MainNavigationScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _panelController = AccountPanelController();

  // Screens are kept alive across tab switches
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _screens = [
      AedMapScreen(onTabTapped: _onTabTapped),
      LiveCPRScreen(onTabTapped: _onTabTapped),
      const GuideScreen(),
    ];
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _panelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: UniversalHeader.forMainScreens(
        onAccountTap: _panelController.open,  // ← was openEndDrawer
      ),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _screens,
          ),
          AccountPanel(controller: _panelController),  // ← was endDrawer
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem(icon: 'assets/icons/locations.svg', label: 'AED Map'),
    _NavItem(icon: 'assets/icons/live.svg',      label: 'Live CPR'),
    _NavItem(icon: 'assets/icons/training.svg',  label: 'Guide'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceWhite,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: AppSpacing.dividerThickness),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSpacing.bottomNavHeight,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadiusSm),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        item.icon,
                        width: AppSpacing.iconMd - AppSpacing.xxs, // 22
                        height: AppSpacing.iconMd - AppSpacing.xxs,
                        colorFilter: ColorFilter.mode(
                          selected
                              ? AppColors.primary
                              : AppColors.textDisabled,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        item.label,
                        style: selected
                            ? AppTypography.navSelected()
                            : AppTypography.navUnselected(),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}