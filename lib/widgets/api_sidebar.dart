import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../app.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';

/// Right-side API configuration panel for the chat screen.
class ApiSidebar extends StatefulWidget {
  final bool visible;
  final VoidCallback? onClose;

  const ApiSidebar({
    super.key,
    required this.visible,
    this.onClose,
  });

  @override
  State<ApiSidebar> createState() => _ApiSidebarState();
}

class _ApiSidebarState extends State<ApiSidebar> {
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _obscureKey = true;
  bool _initialized = false;
  bool _testing = false;

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _initFromSettings(AppSettings s) {
    if (_initialized) return;
    _initialized = true;
    _baseUrlCtrl.text = s.apiRelayBaseUrl;
    _apiKeyCtrl.text = s.apiRelayApiKey;
    _modelCtrl.text = s.apiRelayModel;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        final s = sp.settings;
        _initFromSettings(s);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 280,
          decoration: BoxDecoration(
            color: ShadTheme.of(context).sidebar,
            border: Border(left: BorderSide(color: ShadTheme.of(context).border)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.api, size: 16, color: ShadTheme.of(context).primary),
                    const SizedBox(width: 8),
                    const Text(
                      'API Config',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => widget.onClose?.call(),
                      child: Icon(Icons.close, size: 16, color: ShadTheme.of(context).mutedForeground),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _sectionLabel('Base URL'),
                const SizedBox(height: 6),
                _buildTextField(controller: _baseUrlCtrl, hint: 'https://api.siliconflow.cn/v1', icon: Icons.link),
                const SizedBox(height: 14),
                _sectionLabel('API Key'),
                const SizedBox(height: 6),
                _buildTextField(
                  controller: _apiKeyCtrl,
                  hint: 'sk-...',
                  icon: Icons.key,
                  obscure: _obscureKey,
                  suffix: GestureDetector(
                    onTap: () => setState(() => _obscureKey = !_obscureKey),
                    child: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility, size: 16, color: ShadTheme.of(context).mutedForeground),
                  ),
                ),
                const SizedBox(height: 14),
                _sectionLabel('Model'),
                const SizedBox(height: 6),
                _buildTextField(controller: _modelCtrl, hint: 'deepseek-ai/DeepSeek-V3.2', icon: Icons.smart_toy),
                const SizedBox(height: 20),
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : () => _testConnection(context),
                        icon: _testing
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi, size: 14),
                        label: Text(_testing ? 'Testing...' : 'Test'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: ShadTheme.of(context).mutedForeground,
                          side: BorderSide(color: ShadTheme.of(context).input),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveSettings(context, sp, s),
                        icon: const Icon(Icons.save, size: 14),
                        label: Text(AppLocalizations.of(context).save),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ShadTheme.of(context).primary,
                          foregroundColor: ShadTheme.of(context).primaryForeground,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('Quick Presets', style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _presetChip('SiliconFlow', 'https://api.siliconflow.cn/v1', 'deepseek-ai/DeepSeek-V3.2'),
                    _presetChip('OpenRouter', 'https://openrouter.ai/api/v1', 'openai/gpt-4o'),
                    _presetChip('OpenAI', 'https://api.openai.com/v1', 'gpt-4o'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground, fontWeight: FontWeight.w500));
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 12),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 14, color: ShadTheme.of(context).mutedForeground),
        ),
        suffixIcon: suffix != null
            ? Padding(padding: const EdgeInsets.all(10), child: suffix)
            : null,
        filled: true,
        fillColor: ShadTheme.of(context).secondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: ShadTheme.of(context).input)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: ShadTheme.of(context).primary)),
      ),
    );
  }

  Widget _presetChip(String label, String url, String model) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _baseUrlCtrl.text = url;
          _modelCtrl.text = model;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: ShadTheme.of(context).secondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ShadTheme.of(context).input),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
      ),
    );
  }

  void _saveSettings(BuildContext context, SettingsProvider sp, AppSettings s) {
    final updated = AppSettings(
      apiRelayBaseUrl: _baseUrlCtrl.text.trim(),
      apiRelayApiKey: _apiKeyCtrl.text.trim(),
      apiRelayModel: _modelCtrl.text.trim(),
      apiRelayEnabled: true,
      systemPrompt: s.systemPrompt,
      enableMemoryRetrieval: s.enableMemoryRetrieval,
      keepModelLoaded: s.keepModelLoaded,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).apiSaved),
        backgroundColor: ShadTheme.of(context).primary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testConnection(BuildContext context) async {
    setState(() => _testing = true);
    try {
      final url = _baseUrlCtrl.text.trim();
      final key = _apiKeyCtrl.text.trim();
      if (url.isEmpty || key.isEmpty) {
        _showSnack(context, 'Base URL and API Key required', false);
        return;
      }
      final result = await _doTestRequest(url, key);
      if (!mounted) return;
      _showSnack(context, result == 'ok' ? 'Connection successful' : result, result == 'ok');
    } catch (e) {
      if (mounted) _showSnack(context, 'Connection failed: $e', false);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<String> _doTestRequest(String baseUrl, String apiKey) async {
    try {
      var url = baseUrl.replaceAll(RegExp(r'/+$'), '');
      if (!url.endsWith('/v1')) url = '$url/v1';
      url = '$url/models';
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $apiKey'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return 'ok';
      return 'HTTP ${response.statusCode}';
    } catch (e) {
      return e.toString();
    }
  }

  void _showSnack(BuildContext context, String message, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? ShadTheme.of(context).primary : const Color(ThemePreset.destructive),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
