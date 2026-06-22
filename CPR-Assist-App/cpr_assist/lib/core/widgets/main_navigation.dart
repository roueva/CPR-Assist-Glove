import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

import 'package:cpr_assist/core/core.dart';

import '../../features/account/screens/account_menu.dart';
import '../../features/aed_map/screens/aed_map_screen.dart';
import '../../features/guide/screens/guide_screen.dart';
import '../../features/live_cpr/screens/live_cpr_screen.dart';
import '../../main.dart';
import '../../providers/app_providers.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState
    extends ConsumerState<MainNavigationScreen> {
  late PageController _pageController;
  StreamSubscription<Map<String, dynamic>>? _sessionStartSub;
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
      GuideScreen(onTabTapped: _onTabTapped),
    ];
    nfcTabNotifier.addListener(_onNfcTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionStartSub = ref.read(bleConnectionProvider).dataStream.listen((data) {
        if (!mounted) return;
        if (data['isStartPing'] == true) {
          final autoSwitch = ref.read(settingsProvider).autoSwitchToCPR;
          if (autoSwitch) {
            // A session can start while the user is on a pushed route
            // (Session History, results, settings...). Pop back to the
            // navigation shell first, then switch to the Live CPR tab.
            final nav = Navigator.of(context);
            while (nav.canPop()) {
              nav.pop();
            }
            if (_currentIndex != 1) _onTabTapped(1);
          }
        }
      });
    });
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
    if (index == 1) {
      liveCprTabActivationNotifier.value++;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _panelController.dispose();
    nfcTabNotifier.removeListener(_onNfcTab);
    _sessionStartSub?.cancel();
    super.dispose();
  }

  void _onNfcTab() {
    final tab = nfcTabNotifier.value;
    if (tab >= 0 && tab < _screens.length) {
      _onTabTapped(tab);
      nfcTabNotifier.value = -1; // reset so it doesn't retrigger
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: UniversalHeader.forMainScreens(
        onAccountTap: _panelController.toggle,
        isLiveCprTab: _currentIndex == 1,
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

class _BottomNav extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final isSessionActive = ref.watch(cprSessionActiveProvider);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
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
                      _PulsingNavIcon(
                        assetPath: item.icon,
                        selected: selected,
                        pulse: i == 1 && isSessionActive && !selected,
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

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing nav icon — breathes between textDisabled and feedbackBad
// when a live session is active and this tab is not selected.
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingNavIcon extends StatefulWidget {
  final String assetPath;
  final bool selected;
  final bool pulse;

  const _PulsingNavIcon({
    required this.assetPath,
    required this.selected,
    required this.pulse,
  });

  @override
  State<_PulsingNavIcon> createState() => _PulsingNavIconState();
}

class _PulsingNavIconState extends State<_PulsingNavIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingNavIcon old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staticColor = widget.selected
        ? AppColors.primary
        : AppColors.textDisabled;

    if (!widget.pulse) {
      return SvgPicture.asset(
        widget.assetPath,
        width: AppSpacing.iconMd - AppSpacing.xxs,
        height: AppSpacing.iconMd - AppSpacing.xxs,
        colorFilter: ColorFilter.mode(staticColor, BlendMode.srcIn),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final color = Color.lerp(
          AppColors.textDisabled,
          AppColors.feedbackBad,
          Curves.easeInOut.transform(_controller.value),
        )!;
        return SvgPicture.asset(
          widget.assetPath,
          width: AppSpacing.iconMd - AppSpacing.xxs,
          height: AppSpacing.iconMd - AppSpacing.xxs,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        );
      },
    );
  }
}