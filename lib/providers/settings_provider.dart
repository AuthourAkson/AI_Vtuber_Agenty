import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';
import '../services/backend_service.dart';

/// Manages app settings: loads/saves locally via BackendService.
/// Data stored at D:\AiVtuber_Agent_profile\settings.json
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  bool _loaded = false;

  AppSettings get settings => _settings;
  bool get loaded => _loaded;

  final BackendService _backend = BackendService();

  Future<void> loadSettings() async {
    // Load from local storage (D:\AiVtuber_Agent_profile\settings.json)
    try {
      _settings = await _backend.getSettings();
    } catch (_) {
      // Fallback to SharedPreferences legacy values
      final prefs = await SharedPreferences.getInstance();
      _settings = AppSettings(
        apiRelayBaseUrl: prefs.getString('api_relay_url') ?? 'https://api.siliconflow.cn/v1',
        apiRelayApiKey: prefs.getString('api_relay_key') ?? '',
        apiRelayModel: prefs.getString('api_relay_model') ?? 'deepseek-ai/DeepSeek-V3.2',
        systemPrompt: prefs.getString('system_prompt') ?? '',
        enableMemoryRetrieval: prefs.getBool('enable_memory') ?? true,
        apiRelayEnabled: prefs.getBool('api_relay') ?? true,
      );
    }

    _loaded = true;
    notifyListeners();
  }

  void updateBackendUrl(String url) {
    _settings.backendUrl = url;
    saveSettings(_settings);
  }

  Future<void> saveSettings(AppSettings newSettings) async {
    // Save to local profile (D:\AiVtuber_Agent_profile\settings.json)
    try {
      await _backend.updateSettings(newSettings);
    } catch (_) {}

    // Also save to SharedPreferences as fallback
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_relay_url', newSettings.apiRelayBaseUrl);
    await prefs.setString('api_relay_key', newSettings.apiRelayApiKey);
    await prefs.setString('api_relay_model', newSettings.apiRelayModel);
    await prefs.setString('system_prompt', newSettings.systemPrompt);
    await prefs.setBool('enable_memory', newSettings.enableMemoryRetrieval);
    await prefs.setBool('api_relay', newSettings.apiRelayEnabled);

    _settings = newSettings;
    notifyListeners();
  }
}
