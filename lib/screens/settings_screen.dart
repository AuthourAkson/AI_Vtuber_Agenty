import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _serverCtrl;

  @override
  void initState() {
    super.initState();
    _serverCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, ChatProvider>(
      builder: (context, sp, chat, _) {
        if (_serverCtrl.text.isEmpty) {
          _serverCtrl.text = sp.settings.backendUrl;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // Server Connection
              _sectionHeader('Server Connection'),
              const SizedBox(height: 8),
              TextField(
                controller: _serverCtrl,
                decoration: const InputDecoration(
                  labelText: 'Backend URL',
                  hintText: 'http://localhost:8000',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFF1E1E1E),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => sp.updateBackendUrl(v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: chat.connected
                      ? chat.disconnect
                      : () => chat.connectToBackend(),
                  icon: Icon(chat.connected ? Icons.link_off : Icons.link, size: 18),
                  label: Text(chat.connected ? 'Disconnect' : 'Connect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: chat.connected ? const Color(0xFFCF6679) : const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              if (chat.connected)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                      const SizedBox(width: 6),
                      Text('Connected to ${sp.settings.backendUrl}',
                          style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 13)),
                    ],
                  ),
                ),

              const SizedBox(height: 24),
              _sectionHeader('About'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI VTuber Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Text('v1.0.0 — Flutter Desktop App',
                        style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                    SizedBox(height: 12),
                    Text('Features:',
                        style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 14)),
                    SizedBox(height: 4),
                    Text('• Streaming LLM chat with character system prompt'),
                    Text('• TTS voice synthesis via GPT-SoVITS'),
                    Text('• Live2D / VRM character display (WIP)'),
                    Text('• Screenshot vision + OCR'),
                    Text('• Vector memory with Qdrant'),
                    Text('• Session history management'),
                    Text('• YouTube live chat integration'),
                    SizedBox(height: 12),
                    Text('Backend: LocalAIVtuber2 (Python FastAPI)',
                        style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                    Text('UI Framework: Flutter 3.x + Provider',
                        style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _sectionHeader('Data & Storage'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCF6679)),
                label: const Text('Clear Local Cache', style: TextStyle(color: Color(0xFFCF6679))),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF4CAF50),
    ));
  }
}
