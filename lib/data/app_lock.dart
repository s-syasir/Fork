import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lockEnabledKey = 'fork_lock_enabled';

/// Whether opening the app (cold start or resume from background)
/// requires a biometric/PIN check first. Off by default - opt-in, same as
/// every other setting in this app family.
class AppLockNotifier extends StateNotifier<bool> {
  AppLockNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_lockEnabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockEnabledKey, enabled);
    state = enabled;
  }
}

final appLockEnabledProvider = StateNotifierProvider<AppLockNotifier, bool>((ref) => AppLockNotifier());
