import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';
import '../services/api_client.dart';

/// Manages app settings: loads from backend & persists locally.
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  bool _loaded = false;
  bool _connecting = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;
  bool get connecting => _connecting;

  final ApiClient _api = ApiClient();

  Future<void> loadSettings() async {
    _connecting = true;
    notifyListeners();

    // Try backend first
    try {
      _settings = await _api.getSettings();
    } catch (_) {
      // Fallback to local preferences
      final prefs = await SharedPreferences.getInstance();
      _settings = AppSettings(
        backendUrl: prefs.getString('backend_url') ?? 'http://localhost:8000',
        systemPrompt: prefs.getString('system_prompt') ?? '',
        enableMemoryRetrieval: prefs.getBool('enable_memory') ?? true,
        apiRelayEnabled: prefs.getBool('api_relay') ?? true,
      );
    }

    _loaded = true;
    _connecting = false;
    notifyListeners();
  }

  Future<void> saveSettings(AppSettings newSettings) async {
    // Save locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backend_url', newSettings.backendUrl);
    await prefs.setString('system_prompt', newSettings.systemPrompt);
    await prefs.setBool('enable_memory', newSettings.enableMemoryRetrieval);
    await prefs.setBool('api_relay', newSettings.apiRelayEnabled);

    // Push to backend
    try {
      await _api.updateSettings(newSettings);
    } catch (_) {}

    _settings = newSettings;
    notifyListeners();
  }

  void updateBackendUrl(String url) {
    _settings.backendUrl = url;
    notifyListeners();
  }
}
