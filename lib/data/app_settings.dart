import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();
const _backendUrlKey = 'fork_backend_url';
const _tokenKey = 'fork_backend_token';

class ForkSettings {
  final String? backendUrl;
  final String? token;

  const ForkSettings({this.backendUrl, this.token});

  bool get isConfigured => backendUrl != null && backendUrl!.isNotEmpty && token != null && token!.isNotEmpty;
}

class SettingsNotifier extends StateNotifier<ForkSettings> {
  SettingsNotifier() : super(const ForkSettings()) {
    _load();
  }

  Future<void> _load() async {
    final url = await _storage.read(key: _backendUrlKey);
    final token = await _storage.read(key: _tokenKey);
    state = ForkSettings(backendUrl: url, token: token);
  }

  Future<void> save({required String backendUrl, required String token}) async {
    await _storage.write(key: _backendUrlKey, value: backendUrl);
    await _storage.write(key: _tokenKey, value: token);
    state = ForkSettings(backendUrl: backendUrl, token: token);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, ForkSettings>(
  (ref) => SettingsNotifier(),
);
