import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../services/live2d_model_service.dart';
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

  @override
  void initState() {
    super.initState();
    _refreshModels();
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

              // ─── Desktop Pet Overlay ───
              const Text('Desktop Pet Overlay',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Opens a transparent always-on-top window with your Live2D character on the desktop. '
                'Right-click the character to open a chat dialog.',
                style: TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _openOverlayWindow(modelJsonPath),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Launch Desktop Pet'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4CAF50),
                  side: const BorderSide(color: Color(0xFF4CAF50)),
                ),
              ),
              const SizedBox(height: 16),

              // ─── Mouth / Expression Test ───
              const Text('Test Controls',
                style: TextStyle(color: Color(0xFF888888), fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _sendToOverlay('setExpression', {'expression': '咧嘴笑'}),
                    child: const Text('Smile', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF888888),
                      side: const BorderSide(color: Color(0xFF2C2C2C)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _sendToOverlay('setExpression', {'expression': '星星眼'}),
                    child: const Text('Star Eyes', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF888888),
                      side: const BorderSide(color: Color(0xFF2C2C2C)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _testMouthOpen(),
                      child: const Text('Test Mouth Open', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4CAF50),
                        side: const BorderSide(color: Color(0xFF2C2C2C)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  WindowController? _overlayController;

  Future<void> _openOverlayWindow(String? modelPath) async {
    try {
      final config = jsonEncode({
        'modelPath': modelPath,
      });
      final controller = await WindowController.create(
        WindowConfiguration(arguments: config, hiddenAtLaunch: true),
      );
      _overlayController = controller;

      await controller.show();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desktop pet launched!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to launch: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendToOverlay(String method, Map<String, dynamic> args) async {
    if (_overlayController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open desktop pet first!'), backgroundColor: Color(0xFF888888)),
      );
      return;
    }
    try {
      await _overlayController!.invokeMethod(method, args);
    } catch (e) {
      debugPrint('Overlay IPC error: $e');
    }
  }

  Future<void> _testMouthOpen() async {
    if (_overlayController == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open desktop pet first!'), backgroundColor: Color(0xFF888888)),
      );
      return;
    }
    for (var i = 0; i < 3; i++) {
      await _overlayController!.invokeMethod('setMouthOpen', {'value': 0.8});
      await Future.delayed(const Duration(milliseconds: 200));
      await _overlayController!.invokeMethod('setMouthOpen', {'value': 0.0});
      await Future.delayed(const Duration(milliseconds: 300));
    }
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
