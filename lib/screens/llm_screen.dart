import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class LLMScreen extends StatefulWidget {
  const LLMScreen({super.key});

  @override
  State<LLMScreen> createState() => _LLMScreenState();
}

class _LLMScreenState extends State<LLMScreen> {
  late TextEditingController _promptCtrl;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        final s = sp.settings;
        if (_promptCtrl.text.isEmpty && s.systemPrompt.isNotEmpty) {
          _promptCtrl.text = s.systemPrompt;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('LLM Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // System Prompt
              const Text('System Prompt', style: TextStyle(fontSize: 14, color: Color(0xFF888888))),
              const SizedBox(height: 8),
              TextField(
                controller: _promptCtrl,
                maxLines: 10,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Enter the character system prompt...',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 16),

              // Switches
              SwitchListTile(
                title: const Text('Enable Memory Retrieval'),
                subtitle: const Text('Use vector memory for context'),
                value: s.enableMemoryRetrieval,
                onChanged: (v) {
                  sp.saveSettings(AppSettings()..enableMemoryRetrieval = v);
                },
                activeColor: const Color(0xFF4CAF50),
              ),
              SwitchListTile(
                title: const Text('Keep Model Loaded'),
                subtitle: const Text('Keep LLM in VRAM for faster responses'),
                value: s.keepModelLoaded,
                onChanged: (v) {
                  sp.saveSettings(s..keepModelLoaded = v);
                },
                activeColor: const Color(0xFF4CAF50),
              ),
              SwitchListTile(
                title: const Text('API Relay Mode'),
                subtitle: const Text('Use remote API instead of local LLM'),
                value: s.apiRelayEnabled,
                onChanged: (v) {
                  sp.saveSettings(s..apiRelayEnabled = v);
                },
                activeColor: const Color(0xFF4CAF50),
              ),

              if (s.apiRelayEnabled) ...[
                const SizedBox(height: 16),
                const Text('API Relay Config', style: TextStyle(fontSize: 14, color: Color(0xFF888888))),
                const SizedBox(height: 8),
                _settingField('Base URL', s.apiRelayBaseUrl, (v) {
                  sp.saveSettings(s..apiRelayBaseUrl = v);
                }),
                _settingField('API Key', s.apiRelayApiKey, (v) {
                  sp.saveSettings(s..apiRelayApiKey = v);
                }, obscure: true),
                _settingField('Model', s.apiRelayModel, (v) {
                  sp.saveSettings(s..apiRelayModel = v);
                }),
              ],

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final newSettings = AppSettings()
                    ..systemPrompt = _promptCtrl.text
                    ..enableMemoryRetrieval = s.enableMemoryRetrieval
                    ..keepModelLoaded = s.keepModelLoaded
                    ..apiRelayEnabled = s.apiRelayEnabled
                    ..apiRelayBaseUrl = s.apiRelayBaseUrl
                    ..apiRelayApiKey = s.apiRelayApiKey
                    ..apiRelayModel = s.apiRelayModel;
                  sp.saveSettings(newSettings);
                },
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _settingField(String label, String value, Function(String) onChanged, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: onChanged,
        controller: TextEditingController(text: value),
      ),
    );
  }
}
