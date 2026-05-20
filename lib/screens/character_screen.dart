import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../services/live2d_model_service.dart';
import '../services/live2d_server.dart';
import '../widgets/live2d_view.dart';
import '../app.dart';

class CharacterScreen extends StatefulWidget {
  const CharacterScreen({super.key});
  @override
  State<CharacterScreen> createState() => _CharacterScreenState();
}

class _CharacterScreenState extends State<CharacterScreen> {
  final Live2DModelService _modelService = Live2DModelService();
  List<Map<String, String>> _models = [];
  String? _importingModel;
  int _petPort = 48889;
  bool _clickThrough = true;
  final HttpClient _httpClient = HttpClient();

  @override
  void initState() {
    super.initState();
    _refreshModels();
  }

  @override
  void dispose() {
    _closePet();
    _httpClient.close();
    super.dispose();
  }

  void _refreshModels() {
    setState(() => _models = _modelService.listModels());
  }

  void _update(SettingsProvider sp, AppSettings s, {
    bool? renderModel, bool? use3D,
    double? live2DXPosition, double? live2DYPosition, double? live2DScale,
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
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select Live2D model file (.model3.json or .model.json)',
      allowMultiple: false, type: FileType.custom, allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;
    final dir = Directory(filePath).parent;
    setState(() => _importingModel = dir.path);
    try {
      final modelName = dir.path.split(Platform.pathSeparator).last;
      final destPath = await _modelService.importModel(dir.path);
      if (destPath != null && mounted) {
        _refreshModels();
        final sp = context.read<SettingsProvider>();
        final modelJson = _modelService.getModelJsonPath(modelName);
        _update(sp, sp.settings, selectedLive2DModel: modelJson);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Model "$modelName" imported'),
            backgroundColor: const Color(0xFF4CAF50)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _importingModel = null);
    }
  }

  Future<void> _deleteModel(String modelName) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) =>
      AlertDialog(backgroundColor: ShadTheme.of(context).card,
        title: const Text('Delete Model?'),
        content: Text('Delete "$modelName"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ]));
    if (confirm == true) {
      _modelService.deleteModel(modelName);
      _refreshModels();
      final sp = context.read<SettingsProvider>();
      if ((sp.settings.selectedLive2DModel ?? '').contains(modelName)) {
        _update(sp, sp.settings, selectedLive2DModel: null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(builder: (context, sp, _) {
      final s = sp.settings;
      final modelJsonPath = s.selectedLive2DModel;
      return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Character Settings',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        SwitchListTile(title: const Text('Show Character'),
          subtitle: const Text('Display Live2D/VRM character on screen'),
          value: s.renderModel, onChanged: (v) => _update(sp, s, renderModel: v)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _modeCard('Live2D (2D)', Icons.person_outline,
            !s.use3D, () => _update(sp, s, use3D: false))),
          const SizedBox(width: 12),
          Expanded(child: _modeCard('VRM (3D)', Icons.view_in_ar,
            s.use3D, () => _update(sp, s, use3D: true))),
        ]),
        const SizedBox(height: 24),
        if (!s.use3D) ...[
          Text('Live2D Preview',
            style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
          const SizedBox(height: 8),
          Container(height: 350, decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ShadTheme.of(context).border)),
            child: ClipRRect(borderRadius: BorderRadius.circular(12),
              child: modelJsonPath != null
                ? Live2DView(modelPath: modelJsonPath,
                    positionX: s.live2DXPosition, positionY: s.live2DYPosition,
                    scale: s.live2DScale, interactive: false,
                    onEvent: (event) { if (event.type == 'modelError') debugPrint('Live2D error: ${event.data}'); })
                : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person, size: 64, color: ShadTheme.of(context).mutedForeground),
                    SizedBox(height: 12), Text('No model selected', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
                    Text('Upload a Live2D model to preview', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 12))])))),
          const SizedBox(height: 16),
          Text('Live2D Position', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _sliderSetting('X', s.live2DXPosition, 0, 100, (v) => _update(sp, s, live2DXPosition: v))),
            Expanded(child: _sliderSetting('Y', s.live2DYPosition, 0, 100, (v) => _update(sp, s, live2DYPosition: v))),
            Expanded(child: _sliderSetting('Scale', s.live2DScale, 0.05, 0.5, (v) => _update(sp, s, live2DScale: v))),
          ]),
          const SizedBox(height: 24),
        ],
        if (s.use3D) ...[
          Container(height: 300, decoration: BoxDecoration(
            color: ShadTheme.of(context).secondary, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ShadTheme.of(context).border)),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.view_in_ar, size: 64, color: ShadTheme.of(context).mutedForeground),
              SizedBox(height: 12), Text('VRM 3D Preview', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
              Text('Coming soon', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 12))]))),
          const SizedBox(height: 24),
        ],
        Text('Installed Models', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
        const SizedBox(height: 8),
        if (_models.isEmpty)
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(
            color: ShadTheme.of(context).secondary, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: ShadTheme.of(context).border)),
            child: Row(children: [
              Icon(Icons.info_outline, color: ShadTheme.of(context).mutedForeground, size: 18), SizedBox(width: 8),
              Expanded(child: Text('No models installed. Upload a Live2D model folder.',
                style: TextStyle(color: ShadTheme.of(context).mutedForeground)))]))
        else ...(_models.map((m) {
          final isSelected = modelJsonPath != null && modelJsonPath.contains(m['name']!);
          final shad = ShadTheme.of(context);
          return Container(margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(
            color: isSelected ? shad.muted : shad.card, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? shad.primary : shad.border)),
            child: ListTile(dense: true,
              leading: Icon(Icons.person, color: shad.primary, size: 20),
              title: Text(m['name']!, style: const TextStyle(fontSize: 13)),
              selected: isSelected,
              trailing: IconButton(icon: Icon(Icons.delete_outline, color: shad.mutedForeground, size: 18),
                onPressed: () => _deleteModel(m['name']!)),
              onTap: () => _update(sp, s, selectedLive2DModel: m['path'])));})),
        const SizedBox(height: 20),
        Text('Upload Model', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _importingModel != null ? null : _uploadLive2DModel,
            icon: _importingModel != null
              ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(
                  strokeWidth: 2, color: Theme.of(context).colorScheme.primary))
              : const Icon(Icons.upload_file, size: 18),
            label: Text(_importingModel != null ? 'Importing...' : 'Upload Live2D')),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('VRM upload coming in next update'), backgroundColor: ShadTheme.of(context).mutedForeground));
          }, icon: const Icon(Icons.upload_file, size: 18), label: const Text('Upload VRM')),
        ]),
        const SizedBox(height: 8),
        Text('Select the .model3.json or .model.json file inside your Live2D model folder.',
          style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 11)),
        SizedBox(height: 32), Divider(color: ShadTheme.of(context).border), const SizedBox(height: 16),
        const Text('Transparent Overlay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Open a separate transparent, always-on-top window with your Live2D character. '
          'Default: click-through. F2 to toggle Interactive mode. ESC to close.',
          style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: modelJsonPath != null && !Live2DServer.petRunning
              ? () => _openPet(modelJsonPath!, s) : null,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(Live2DServer.petRunning ? 'Pet Active' : 'Open Pet'),
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary))),
          if (Live2DServer.petRunning) ...[
            OutlinedButton.icon(onPressed: _closePet, icon: const Icon(Icons.close, size: 18),
              label: const Text('Close'), style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent))),
            OutlinedButton.icon(onPressed: _togglePetClickThrough,
              icon: Icon(_clickThrough ? Icons.touch_app : Icons.touch_app_outlined, size: 18),
              label: Text(_clickThrough ? 'Click-through ON' : 'Interactive'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _clickThrough ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).mutedForeground,
                side: BorderSide(color: _clickThrough ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).border))),
            OutlinedButton.icon(onPressed: _reloadPetModel, icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reload Model'), style: OutlinedButton.styleFrom(
                foregroundColor: ShadTheme.of(context).mutedForeground, side: BorderSide(color: ShadTheme.of(context).input))),
          ],
        ]),
      ]));
    });
  }

  // ─── Python Pet (asset-bundled) ───

  static const _scriptDir = r'D:\AiVtuber_Agent_profile\python_scripts';

  static Future<String?> _ensureScript() async {
    final dir = Directory(_scriptDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final destFile = File('$_scriptDir\\live2d_pet.py');
    try {
      final data = await rootBundle.load('assets/python/live2d_pet.py');
      await destFile.writeAsBytes(data.buffer.asUint8List());
      return destFile.path;
    } catch (e) { return null; }
  }

  Future<void> _openPet(String modelPath, AppSettings s) async {
    if (Live2DServer.petRunning) return;
    final scriptPath = await _ensureScript();
    if (scriptPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to extract pet script.'), backgroundColor: Colors.red));
      return;
    }
    final modelUrl = Live2DServer.toModelUrl(modelPath);
    String py = 'python3';
    try { if ((await Process.run(py, ['--version'])).exitCode != 0) py = 'python'; } catch (_) { py = 'python'; }
    try {
      final process = await Process.start(py, [scriptPath, '--port', _petPort.toString(),
        '--model-url', modelUrl, '--scale', s.live2DScale.toString(),
        '--x', s.live2DXPosition.toString(), '--y', s.live2DYPosition.toString()]);
      Live2DServer.setPetProcess(process);
      process.stdout.transform(utf8.decoder).listen((d) => debugPrint('[Pet] $d'));
      process.stderr.transform(utf8.decoder).listen((d) => debugPrint('[Pet ERR] $d'));
      process.exitCode.then((code) {
        Live2DServer.setPetProcess(null);
        if (mounted) setState(() {});
      });
      await Future.delayed(const Duration(seconds: 2));
      if (Live2DServer.petRunning && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Desktop pet opened.'), backgroundColor: ShadTheme.of(context).primary,
          duration: Duration(seconds: 2)));
      }
    } catch (e) {
      Live2DServer.setPetProcess(null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed: $e'), backgroundColor: Colors.red));
    }
  }

  void _closePet() {
    if (!Live2DServer.petRunning) return;
    Live2DServer.killPet();
    setState(() {});
  }

  void _togglePetClickThrough() {
    if (!Live2DServer.petRunning) return;
    setState(() => _clickThrough = !_clickThrough);
  }

  void _reloadPetModel() {
    if (!Live2DServer.petRunning) return;
    _closePet();
    final sp = context.read<SettingsProvider>();
    final path = sp.settings.selectedLive2DModel;
    if (path != null) _openPet(path, sp.settings);
  }

  Widget _modeCard(String title, IconData icon, bool selected, VoidCallback onTap) {
    final shad = ShadTheme.of(context);
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: selected ? shad.muted : shad.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? shad.primary : shad.border)),
      child: Column(children: [
        Icon(icon, color: selected ? shad.primary : shad.mutedForeground),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: selected ? shad.primary : shad.mutedForeground))])));
  }

  Widget _sliderSetting(String label, double value, double min, double max, Function(double) onChanged) {
    return Column(children: [
      Text('$label: ${value.toStringAsFixed(2)}', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 12)),
      Slider(value: value, min: min, max: max, onChanged: onChanged)]);
  }
}
