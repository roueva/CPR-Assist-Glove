import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cpr_assist/core/core.dart';

import '../../../providers/app_providers.dart';
import '../services/aed_map_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AEDScreen
//
// Emergency mode:  banner calls 112 directly.
// Training mode:   banner opens the Simulation 112 dialog.
//
// No login gate — both modes are accessible without an account.
// ─────────────────────────────────────────────────────────────────────────────

class AedMapScreen extends ConsumerStatefulWidget {
  final Function(int) onTabTapped;

  const AedMapScreen({
    super.key,
    required this.onTabTapped,
  });

  @override
  ConsumerState<AedMapScreen> createState() => _AedMapScreenState();
}

class _AedMapScreenState extends ConsumerState<AedMapScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Actions ───────────────────────────────────────────────────────────────

  void _makeEmergencyCall() {
    HapticFeedback.heavyImpact();
    launchUrl(Uri.parse('tel:112'));
  }

  void _showSimulation112Dialog() {
    AppDialogs.showSimulation112(context);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  // REMOVE _buildLandscapeLayout entirely and simplify build:
  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.watch(bleConnectionProvider);
    final isLandscape = context.isLandscape; // uses your extension

    return Column(
      children: [
        _buildEmergencyBanner(isLandscape: isLandscape),
        const Expanded(child: AEDMapWidget()),
      ],
    );
  }


  Widget _buildEmergencyBanner({required bool isLandscape}) {
    final isTraining = ref.watch(appModeProvider) == AppMode.training;

    return SizedBox(
      height: isLandscape
          ? AppSpacing.emergencyBannerH - AppSpacing.cardSpacing  // 50
          : AppSpacing.emergencyBannerH,                          // 56
      child: Material(
        color: AppColors.emergencyRed,
        child: InkWell(
          onTap: isTraining ? _showSimulation112Dialog : _makeEmergencyCall,
          child: SizedBox.expand(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/icons/phone_call.svg',
                  height: AppSpacing.lg,
                  width:  AppSpacing.lg,
                  colorFilter: const ColorFilter.mode(
                    AppColors.textOnDark,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isTraining ? 'Simulation 112 Call' : 'Call 112',
                  style: AppTypography.heading(
                    size:  22,
                    color: AppColors.textOnDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}