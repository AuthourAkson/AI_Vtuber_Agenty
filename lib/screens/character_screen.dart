import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class CharacterScreen extends StatefulWidget {
  const CharacterScreen({super.key});

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
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
              const Text('Character Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // Render toggle
              SwitchListTile(
                title: const Text('Show Character'),
                subtitle: const Text('Display Live2D/VRM character on screen'),
                value: s.renderModel,
                onChanged: (v) => sp.saveSettings(AppSettings()..renderModel = v),
                activeColor: const Color(0xFF4CAF50),
              ),

              const SizedBox(height: 16),

              // 2D/3D switch
              Row(
                children: [
                  Expanded(
                    child: _modeCard(
                      'Live2D (2D)',
                      Icons.person_outline,
                      !s.use3D,
                      () => sp.saveSettings(AppSettings()..use3D = false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _modeCard(
                      'VRM (3D)',
                      Icons.view_in_ar,
                      s.use3D,
                      () => sp.saveSettings(AppSettings()..use3D = true),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Character display placeholder
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, size: 64, color: Color(0xFF666666)),
                      SizedBox(height: 12),
                      Text('Character preview',
                          style: TextStyle(color: Color(0xFF666666))),
                      Text('Live2D / VRM rendering WIP',
                          style: TextStyle(color: Color(0xFF555555), fontSize: 12)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Text('Live2D Position', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _sliderSetting('X', s.live2DXPosition, 0, 100, (v) {
                    sp.saveSettings(AppSettings()..live2DXPosition = v);
                  })),
                  Expanded(child: _sliderSetting('Y', s.live2DYPosition, 0, 100, (v) {
                    sp.saveSettings(AppSettings()..live2DYPosition = v);
                  })),
                  Expanded(child: _sliderSetting('Scale', s.live2DScale, 0.05, 0.5, (v) {
                    sp.saveSettings(AppSettings()..live2DScale = v);
                  })),
                ],
              ),

              const SizedBox(height: 24),
              const Text('Upload Model', style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {}, // TODO: file picker for Live2D
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload Live2D'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {}, // TODO: file picker for VRM
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload VRM'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _modeCard(String title, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
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
        child: Column(
          children: [
            Icon(icon, color: selected ? const Color(0xFF4CAF50) : const Color(0xFF888888)),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: selected ? const Color(0xFF4CAF50) : const Color(0xFF888888))),
          ],
        ),
      ),
    );
  }

  Widget _sliderSetting(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(
      children: [
        Text('$label: ${value.toStringAsFixed(2)}', style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
        Slider(
          value: value,
          min: min,
          max: max,
          activeColor: const Color(0xFF4CAF50),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
