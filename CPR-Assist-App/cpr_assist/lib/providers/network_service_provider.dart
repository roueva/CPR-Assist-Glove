import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cpr_assist/services/network_service.dart';
import 'shared_preferences_provider.dart';

final networkServiceProvider = Provider<NetworkService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return NetworkService(prefs);
});