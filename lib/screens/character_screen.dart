import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../services/live2d_model_service.dart';
import '../services/live2d_server.dart';
import '../widgets/live2d_view.dart';

class CharacterScreen extends StatefulWidget {
  const CharacterScreen({super.key});

  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  final Live2DModelService _modelService = Live2DModelService();
  List<Map<String, String>> _models = [];
  String? _importingModel; // model being imported
  int _petPort = 48889; // HTTP port for pet control
  bool _clickThrough = true; // Default: click-through for streaming
  final HttpClient _httpClient = HttpClient();

  @override
  void initState() {
    super.initState();
    _refreshModels();
  }

  @override
  void dispose() {
    _closePet(); // Clean up Python pet process if running
    _httpClient.close();
    super.dispose();
  }

  void _refreshModels() {
    setState(() {
      _models = _modelService.listModels();
    });
  }

  void _update(SettingsProvider sp, AppSettings s, {
    bool? renderModel,
    bool? use3D,
    double? live2DXPosition,
    double? live2DYPosition,
    double? live2DScale,
    String? selectedLive2DModel,
  }) {
    sp.saveSettings(AppSettings(
      renderModel: renderModel ?? s.renderModel,
      use3D: use3D ?? s.use3D,
      live2DXPosition: live2DXPosition ?? s.live2DXPosition,
      live2DYPosition: live2DYPosition ?? s.live2DYPosition,
      live2DScale: live2DScale ?? s.live2DScale,
      selectedLive2DModel: selectedLive2DModel ?? s.selectedLive2DModel,
      selectedVRMModel: s.selectedVRMModel,
      systemPrompt: s.systemPrompt,
      enableMemoryRetrieval: s.enableMemoryRetrieval,
      keepModelLoaded: s.keepModelLoaded,
      apiRelayEnabled: s.apiRelayEnabled,
      apiRelayBaseUrl: s.apiRelayBaseUrl,
      apiRelayApiKey: s.apiRelayApiKey,
      apiRelayModel: s.apiRelayModel,
      llmModelFilename: s.llmModelFilename,
      showMonitor: s.showMonitor,
      ttsProvider: s.ttsProvider,
      ttsVoice: s.ttsVoice,
      useRvc: s.useRvc,
      rvcF0UpKey: s.rvcF0UpKey,
      backendUrl: s.backendUrl,
    ));
  }

  Future<void> _uploadLive2DModel() async {
    // Pick a Live2D model folder
    // User selects the .model3.json file — we import the parent folder
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Live2D model file (.model3.json or .model.json)',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    // The parent directory is the model folder
    final dir = Directory(filePath).parent;

    setState(() => _importingModel = dir.path);

    try {
      final modelName = dir.path.split(Platform.pathSeparator).last;
      final destPath = await _modelService.importModel(dir.path);

      if (destPath != null && mounted) {
        _refreshModels();
        // Auto-select the newly imported model
        final sp = context.read<SettingsProvider>();
        final modelJson = _modelService.getModelJsonPath(modelName);
        _update(sp, sp.settings, selectedLive2DModel: modelJson);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Model "$modelName" imported'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No valid Live2D model found in selected folder'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importingModel = null);
    }
  }

  Future<void> _deleteModel(String modelName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Model?'),
        content: Text('Delete "$modelName"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _modelService.deleteModel(modelName);
      _refreshModels();
      // If the deleted model was selected, clear selection
      final sp = context.read<SettingsProvider>();
      final currentPath = sp.settings.selectedLive2DModel;
      if (currentPath != null && currentPath.contains(modelName)) {
        _update(sp, sp.settings, selectedLive2DModel: null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        final s = sp.settings;
        // Resolve model JSON path from the stored model path
        final modelJsonPath = s.selectedLive2DModel;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Character Settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // ─── Render toggle ───
              SwitchListTile(
                title: const Text('Show Character'),
                subtitle: const Text('Display Live2D/VRM character on screen'),
                value: s.renderModel,
                onChanged: (v) => _update(sp, s, renderModel: v),
                activeColor: const Color(0xFF4CAF50),
              ),
              const SizedBox(height: 16),

              // ─── 2D/3D switch ───
              Row(
                children: [
                  Expanded(
                    child: _modeCard(
                      'Live2D (2D)',
                      Icons.person_outline,
                      !s.use3D,
                      () => _update(sp, s, use3D: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _modeCard(
                      'VRM (3D)',
                      Icons.view_in_ar,
                      s.use3D,
                      () => _update(sp, s, use3D: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ─── Live2D Character Preview ───
              if (!s.use3D) ...[
                const Text('Live2D Preview',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  height: 350,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2C2C2C)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: modelJsonPath != null
                        ? Live2DView(
                            modelPath: modelJsonPath,
                            positionX: s.live2DXPosition,
                            positionY: s.live2DYPosition,
                            scale: s.live2DScale,
                            interactive: false,
                            onEvent: (event) {
                              if (event.type == 'modelError') {
                                debugPrint('Live2D error: ${event.data}');
                              }
                            },
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person, size: 64,
                                  color: Color(0xFF666666)),
                                SizedBox(height: 12),
                                Text('No model selected',
                                  style: TextStyle(color: Color(0xFF666666))),
                                Text('Upload a Live2D model to preview',
                                  style: TextStyle(color: Color(0xFF555555),
                                    fontSize: 12)),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),

                // Position sliders
                const Text('Live2D Position',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _sliderSetting('X', s.live2DXPosition, 0, 100,
                      (v) => _update(sp, s, live2DXPosition: v))),
                    Expanded(child: _sliderSetting('Y', s.live2DYPosition, 0, 100,
                      (v) => _update(sp, s, live2DYPosition: v))),
                    Expanded(child: _sliderSetting('Scale', s.live2DScale, 0.05, 0.5,
                      (v) => _update(sp, s, live2DScale: v))),
                  ],
                ),
                const SizedBox(height: 24),
              ],

              // ─── VRM preview placeholder ───
              if (s.use3D) ...[
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
                        Icon(Icons.view_in_ar, size: 64,
                          color: Color(0xFF666666)),
                        SizedBox(height: 12),
                        Text('VRM 3D Preview',
                          style: TextStyle(color: Color(0xFF666666))),
                        Text('Coming soon — will use Three.js via WebView',
                          style: TextStyle(color: Color(0xFF555555),
                            fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // ─── Model Selection ───
              const Text('Installed Models',
                style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              if (_models.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF2C2C2C)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF888888), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('No models installed. Upload a Live2D model folder.',
                          style: TextStyle(color: Color(0xFF888888))),
                      ),
                    ],
                  ),
                )
              else
                ...(_models.map((m) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: modelJsonPath != null &&
                           modelJsonPath.contains(m['name']!)
                        ? const Color(0xFF1E3A1E)
                        : const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: modelJsonPath != null &&
                             modelJsonPath.contains(m['name']!)
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF2C2C2C),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.person,
                      color: Color(0xFF4CAF50), size: 20),
                    title: Text(m['name']!,
                      style: const TextStyle(fontSize: 13)),
                    selected: modelJsonPath != null &&
                              modelJsonPath.contains(m['name']!),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                        color: Color(0xFF888888), size: 18),
                      onPressed: () => _deleteModel(m['name']!),
                    ),
                    onTap: () {
                      _update(sp, s, selectedLive2DModel: m['path']);
                    },
                  ),
                ))),
              const SizedBox(height: 20),

              // ─── Upload buttons ───
              const Text('Upload Model',
                style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _importingModel != null ? null : _uploadLive2DModel,
                    icon: _importingModel != null
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF4CAF50)))
                        : const Icon(Icons.upload_file, size: 18),
                    label: Text(_importingModel != null
                        ? 'Importing...' : 'Upload Live2D'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('VRM upload coming in next update'),
                          backgroundColor: Color(0xFF888888),
                        ),
                      );
                    },
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload VRM'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Select the .model3.json or .model.json file inside your Live2D model folder.',
                style: TextStyle(color: const Color(0xFF555555), fontSize: 11),
              ),

              const SizedBox(height: 32),
              const Divider(color: Color(0xFF2C2C2C)),
              const SizedBox(height: 16),

              // ─── Transparent Overlay (VTube Studio Style) ───
              const Text('Transparent Overlay',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Open a separate transparent, always-on-top window with your Live2D character. '
                'Default: click-through (mouse passes through). '
                'F2 or Ctrl+Shift+F2 to toggle Interactive mode for dragging. '
                'ESC or Ctrl+Shift+Q to close the overlay.',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: modelJsonPath != null && !Live2DServer.petRunning
                        ? () => _openPet(modelJsonPath!, s)
                        : null,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(Live2DServer.petRunning ? 'Pet Active' : 'Open Pet'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4CAF50),
                      side: BorderSide(
                        color: Live2DServer.petRunning
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                  if (Live2DServer.petRunning) ...[
                    OutlinedButton.icon(
                      onPressed: _closePet,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Close'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _togglePetClickThrough,
                      icon: Icon(_clickThrough ? Icons.touch_app : Icons.touch_app_outlined, size: 18),
                      label: Text(_clickThrough ? 'Click-through ON' : 'Interactive'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _clickThrough ? const Color(0xFF4CAF50) : const Color(0xFF888888),
                        side: BorderSide(color: _clickThrough ? const Color(0xFF4CAF50) : const Color(0xFF444444)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _reloadPetModel,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reload Model'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF888888),
                        side: const BorderSide(color: Color(0xFF444444)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Python Pet Subprocess Management ───

  /// Send an HTTP request to the Python pet control server.
  Future<Map<String, dynamic>?> _petRequest(String path, {Map<String, dynamic>? body}) async {
    if (!Live2DServer.petRunning) return null;
    try {
      final request = await _httpClient.postUrl(
        Uri.parse('http://127.0.0.1:$_petPort$path'),
      );
      if (body != null) {
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = await response.transform(utf8.decoder).join();
        return jsonDecode(data) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Pet HTTP error ($path): $e');
    }
    return null;
  }

  Future<void> _openPet(String modelPath, AppSettings s) async {
    if (Live2DServer.petRunning) return;

    // Build model URL
    final modelUrl = Live2DServer.toModelUrl(modelPath);

    // Resolve python executable — try python3 first, then python
    String pythonExe = 'python3';
    try {
      final result = await Process.run(pythonExe, ['--version']);
      if (result.exitCode != 0) pythonExe = 'python';
    } catch (_) {
      pythonExe = 'python';
    }

    // Find the pet script path relative to the project
    final scriptPath = 'lib/services/live2d_pet.py';

    try {
      final process = await Process.start(pythonExe, [
        scriptPath,
        '--port', _petPort.toString(),
        '--model-url', modelUrl,
        '--scale', s.live2DScale.toString(),
        '--x', s.live2DXPosition.toString(),
        '--y', s.live2DYPosition.toString(),
      ]);

      Live2DServer.setPetProcess(process);

      // Listen to stdout/stderr
      process.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[Pet stdout] $data');
      });
      process.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[Pet stderr] $data');
      });

      // Handle process exit
      process.exitCode.then((code) {
        debugPrint('[Pet] Process exited with code $code');
        Live2DServer.setPetProcess(null);
        if (mounted) setState(() {});
      });

      // Wait a moment for the server to start, then confirm health
      await Future.delayed(const Duration(seconds: 2));
      final healthOk = await _checkPetHealth();
      if (healthOk && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desktop pet opened. Hover top-left corner to drag.'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Live2DServer.setPetProcess(null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start desktop pet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _checkPetHealth() async {
    try {
      final request = await _httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$_petPort/health'),
      );
      final response = await request.close().timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _closePet() {
    if (Live2DServer.petRunning) {
      // Try graceful shutdown via HTTP
      _petRequest('/close');
      // Force kill after a short delay as safety net
      Future.delayed(const Duration(milliseconds: 500), () {
        Live2DServer.killPet();
      });
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Desktop pet closed.'),
          backgroundColor: Color(0xFF888888),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _togglePetClickThrough() {
    if (!Live2DServer.petRunning) return;
    final newState = !_clickThrough;
    _petRequest('/click_through', body: {'enable': newState});
    setState(() => _clickThrough = newState);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newState
            ? 'Click-through ON — mouse passes through'
            : 'Interactive mode — drag handle visible to move window'),
        backgroundColor: newState ? const Color(0xFF4CAF50) : const Color(0xFF888888),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _reloadPetModel() {
    if (!Live2DServer.petRunning) return;
    final sp = context.read<SettingsProvider>();
    final s = sp.settings;
    final modelPath = s.selectedLive2DModel;
    if (modelPath == null) return;
    final modelUrl = Live2DServer.toModelUrl(modelPath);
    _petRequest('/reload_model', body: {
      'model_url': modelUrl,
      'scale': s.live2DScale,
      'x': s.live2DXPosition,
      'y': s.live2DYPosition,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reloading pet model...'),
        backgroundColor: Color(0xFF888888),
        duration: Duration(seconds: 1),
      ),
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
            Icon(icon, color: selected
                ? const Color(0xFF4CAF50) : const Color(0xFF888888)),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(color: selected
                ? const Color(0xFF4CAF50) : const Color(0xFF888888))),
          ],
        ),
      ),
    );
  }

  Widget _sliderSetting(String label, double value, double min, double max,
      Function(double) onChanged) {
    return Column(
      children: [
        Text('$label: ${value.toStringAsFixed(2)}',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
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
