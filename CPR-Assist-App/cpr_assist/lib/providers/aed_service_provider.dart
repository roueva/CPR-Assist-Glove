import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cpr_assist/services/aed_map/aed_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/aed_models.dart';
import 'network_service_provider.dart';

final aedServiceProvider = Provider<AEDService>((ref) {
  final networkService = ref.watch(networkServiceProvider);
  return AEDService(networkService);
});

// === MAP STATE PROVIDER ===
final mapStateProvider = StateNotifierProvider<MapStateNotifier, AEDMapState>((ref) {
  return MapStateNotifier(ref);
});

class MapStateNotifier extends StateNotifier<AEDMapState> {
  final Ref ref;

  MapStateNotifier(this.ref) : super(const AEDMapState(isLoading: true));

  bool get isInNavigationMode => state.navigation.hasStarted;
  bool get isInPreviewMode => state.navigation.isActive && !state.navigation.hasStarted;

  void updateUserLocation(LatLng location) {
    state = state.copyWith(userLocation: location);
  }

  void setAEDs(List<AED> aeds) {
    state = state.copyWith(
      aedList: aeds,
      isLoading: false,
      isRefreshing: false,
    );
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setRefreshing(bool refreshing) {
    state = state.copyWith(isRefreshing: refreshing);
  }

  void setOffline(bool offline) {
    state = state.copyWith(isOffline: offline);
  }

  void showNavigationPreview(LatLng destination) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        isActive: true,
        destination: destination,
        hasStarted: false,
      ),
    );
  }

  void startNavigation(LatLng destination) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        isActive: true,
        destination: destination,
        hasStarted: true,
      ),
    );
  }

  void updateRoute(Polyline? route, String time, double? distance) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(
        route: route,
        estimatedTime: time,
        distance: distance,
      ),
    );
  }

  void updateTransportMode(String mode) {
    state = state.copyWith(
      navigation: state.navigation.copyWith(transportMode: mode),
    );
  }

  void cancelNavigation() {
    state = state.copyWith(navigation: const NavigationState());
  }

  void updateAEDsAndMarkers(List<AED> aeds) {
    state = state.copyWith(
        aedList: aeds
    );
  }
}