import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';

class LLMScreen extends StatefulWidget {
  const LLMScreen({super.key});

  @override
  State<LLMScreen> createState() => _LLMScreenState();
}

class _LLMScreenState extends State<LLMScreen> {
  final _promptCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _promptCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _initFromSettings(AppSettings s) {
    if (_initialized) return;
    _initialized = true;

    if (_promptCtrl.text.isEmpty && s.systemPrompt.isNotEmpty) {
      _promptCtrl.text = s.systemPrompt;
    }
    _baseUrlCtrl.text = s.apiRelayBaseUrl;
    _apiKeyCtrl.text = s.apiRelayApiKey;
    _modelCtrl.text = s.apiRelayModel;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        final s = sp.settings;
        _initFromSettings(s);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LLM Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // System Prompt
              Text('System Prompt', style: TextStyle(fontSize: 14, color: ShadTheme.of(context).mutedForeground)),
              const SizedBox(height: 8),
              TextField(
                controller: _promptCtrl,
                maxLines: 10,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter the character system prompt...',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: ShadTheme.of(context).secondary,
                ),
              ),
              const SizedBox(height: 16),

              // Switches
              SwitchListTile(
                title: const Text('Enable Memory Retrieval'),
                subtitle: const Text('Use vector memory for context'),
                value: s.enableMemoryRetrieval,
                onChanged: (v) => _saveSwitch(sp, s, memoryRetrieval: v),
              ),
              SwitchListTile(
                title: const Text('Keep Model Loaded'),
                subtitle: const Text('Keep LLM in VRAM for faster responses'),
                value: s.keepModelLoaded,
                onChanged: (v) => _saveSwitch(sp, s, keepLoaded: v),
              ),
              SwitchListTile(
                title: const Text('API Relay Mode'),
                subtitle: const Text('Use remote API instead of local LLM'),
                value: s.apiRelayEnabled,
                onChanged: (v) => _saveSwitch(sp, s, relayEnabled: v),
              ),

              if (s.apiRelayEnabled) ...[
                const SizedBox(height: 16),
                Text('API Relay Config', style: TextStyle(fontSize: 14, color: ShadTheme.of(context).mutedForeground)),
                const SizedBox(height: 8),
                _settingField('Base URL', _baseUrlCtrl, false),
                _settingField('API Key', _apiKeyCtrl, true),
                _settingField('Model', _modelCtrl, false),
              ],

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final updated = _buildUpdatedSettings(s);
                  sp.saveSettings(updated);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Settings saved'),
                      backgroundColor: ShadTheme.of(context).primary,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ShadTheme.of(context).primary,
                  foregroundColor: ShadTheme.of(context).primaryForeground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build a full AppSettings from current form state + existing settings,
  /// so no fields are lost on save.
  AppSettings _buildUpdatedSettings(AppSettings s) {
    return AppSettings(
      systemPrompt: _promptCtrl.text,
      enableMemoryRetrieval: s.enableMemoryRetrieval,
      keepModelLoaded: s.keepModelLoaded,
      apiRelayEnabled: s.apiRelayEnabled,
      apiRelayBaseUrl: _baseUrlCtrl.text,
      apiRelayApiKey: _apiKeyCtrl.text,
      apiRelayModel: _modelCtrl.text,
      // Preserve other settings
      llmModelFilename: s.llmModelFilename,
      showMonitor: s.showMonitor,
      ttsProvider: s.ttsProvider,
      ttsVoice: s.ttsVoice,
      useRvc: s.useRvc,
      rvcF0UpKey: s.rvcF0UpKey,
      selectedLive2DModel: s.selectedLive2DModel,
      selectedVRMModel: s.selectedVRMModel,
      renderModel: s.renderModel,
      live2DXPosition: s.live2DXPosition,
      live2DYPosition: s.live2DYPosition,
      live2DScale: s.live2DScale,
      use3D: s.use3D,
      backendUrl: s.backendUrl,
    );
  }

  void _saveSwitch(SettingsProvider sp, AppSettings s, {
    bool? memoryRetrieval,
    bool? keepLoaded,
    bool? relayEnabled,
  }) {
    final updated = AppSettings(
      systemPrompt: _promptCtrl.text,
      enableMemoryRetrieval: memoryRetrieval ?? s.enableMemoryRetrieval,
      keepModelLoaded: keepLoaded ?? s.keepModelLoaded,
      apiRelayEnabled: relayEnabled ?? s.apiRelayEnabled,
      apiRelayBaseUrl: _baseUrlCtrl.text,
      apiRelayApiKey: _apiKeyCtrl.text,
      apiRelayModel: _modelCtrl.text,
      llmModelFilename: s.llmModelFilename,
      showMonitor: s.showMonitor,
      ttsProvider: s.ttsProvider,
      ttsVoice: s.ttsVoice,
      useRvc: s.useRvc,
      rvcF0UpKey: s.rvcF0UpKey,
      selectedLive2DModel: s.selectedLive2DModel,
      selectedVRMModel: s.selectedVRMModel,
      renderModel: s.renderModel,
      live2DXPosition: s.live2DXPosition,
      live2DYPosition: s.live2DYPosition,
      live2DScale: s.live2DScale,
      use3D: s.use3D,
      backendUrl: s.backendUrl,
    );
    sp.saveSettings(updated);
  }

  Widget _settingField(String label, TextEditingController ctrl, bool obscure) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: ShadTheme.of(context).secondary,
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
