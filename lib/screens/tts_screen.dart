import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';

class TTSScreen extends StatefulWidget {
  const TTSScreen({super.key});

  @override
  State<TTSScreen> createState() => _TTSScreenState();
}

class _TTSScreenState extends State<TTSScreen> {
  void _update(SettingsProvider sp, AppSettings s, {
    String? ttsProvider,
    bool? useRvc,
    int? rvcF0UpKey,
  }) {
    sp.saveSettings(AppSettings(
      ttsProvider: ttsProvider ?? s.ttsProvider,
      useRvc: useRvc ?? s.useRvc,
      rvcF0UpKey: rvcF0UpKey ?? s.rvcF0UpKey,
      ttsVoice: s.ttsVoice,
      systemPrompt: s.systemPrompt,
      enableMemoryRetrieval: s.enableMemoryRetrieval,
      keepModelLoaded: s.keepModelLoaded,
      apiRelayEnabled: s.apiRelayEnabled,
      apiRelayBaseUrl: s.apiRelayBaseUrl,
      apiRelayApiKey: s.apiRelayApiKey,
      apiRelayModel: s.apiRelayModel,
      llmModelFilename: s.llmModelFilename,
      showMonitor: s.showMonitor,
      selectedLive2DModel: s.selectedLive2DModel,
      selectedVRMModel: s.selectedVRMModel,
      renderModel: s.renderModel,
      live2DXPosition: s.live2DXPosition,
      live2DYPosition: s.live2DYPosition,
      live2DScale: s.live2DScale,
      use3D: s.use3D,
      backendUrl: s.backendUrl,
    ));
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        final s = sp.settings;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TTS Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // Provider selection
              const Text('TTS Engine', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _providerCard('GPT-SoVITS', s.ttsProvider == 'gpt-sovits', () {
                    _update(sp, s, ttsProvider: 'gpt-sovits');
                  }),
                  const SizedBox(width: 12),
                  _providerCard('RVC', s.ttsProvider == 'rvc', () {
                    _update(sp, s, ttsProvider: 'rvc');
                  }),
                ],
              ),

              const SizedBox(height: 24),
              const Text('Voice', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 12),
                    Text(s.ttsVoice.isEmpty ? 'No voice selected' : s.ttsVoice,
                        style: const TextStyle(fontSize: 14)),
                    const Spacer(),
                    const Icon(Icons.chevron_right, color: Color(0xFF888888)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // RVC Settings
              if (s.ttsProvider == 'rvc') ...[
                const Text('RVC Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Enable RVC'),
                  value: s.useRvc,
                    onChanged: (v) => _update(sp, s, useRvc: v),
                  activeColor: const Color(0xFF4CAF50),
                ),
                Row(
                  children: [
                    const Text('Pitch Shift (semitones): '),
                    Text('${s.rvcF0UpKey}', style: const TextStyle(color: Color(0xFF4CAF50))),
                  ],
                ),
                Slider(
                  value: s.rvcF0UpKey.toDouble(),
                  min: -12,
                  max: 12,
                  divisions: 24,
                  activeColor: const Color(0xFF4CAF50),
                  onChanged: (v) => _update(sp, s, rvcF0UpKey: v.round()),
                ),
              ],

              const SizedBox(height: 16),
              const Text('Upload Voice Model',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {}, // TODO: upload voice
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload Voice Model'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _providerCard(String name, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1E3A1E) : const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF4CAF50) : const Color(0xFF2C2C2C),
            ),
          ),
          child: Center(child: Text(name, style: TextStyle(
            color: selected ? const Color(0xFF4CAF50) : const Color(0xFF888888),
            fontWeight: FontWeight.w600,
          ))),
        ),
      ),
    );
  }
}
