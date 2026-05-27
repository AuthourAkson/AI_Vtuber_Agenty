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
import '../l10n/app_localizations.dart';

/// Character screen — matches LocalAIVtuber2's characterPage.tsx / character-render.tsx layout.
/// Full-screen character preview with a sliding right-side settings panel.
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
  bool _panelOpen = true;
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
          SnackBar(content: Text(AppLocalizations.of(context).charModelImported),
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
        title: Text(AppLocalizations.of(context).charDelete),
        content: Text(AppLocalizations.of(context).charDeleteConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context).cancel)),
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

  // ════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(builder: (context, sp, _) {
      final s = sp.settings;
      final modelJsonPath = s.selectedLive2DModel;
      final shad = ShadTheme.of(context);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          // ── Page background (theme-aware, the real background layer) ──
          Positioned.fill(child: Container(color: shad.background)),

          // ── Full-screen character preview ──
          Positioned.fill(child: _buildPreview(s, modelJsonPath, shad)),

          // ── Settings panel + toggle button (slide via visual transform — no layout churn) ──
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              offset: _panelOpen ? Offset.zero : const Offset(400 / 422, 0.0),
              child: SizedBox(
                width: 422, // 400 panel + 22 toggle
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Toggle button — always at the left edge of this container
                    Positioned(
                      left: 0,
                      top: 20,
                      child: GestureDetector(
                        onTap: () => setState(() => _panelOpen = !_panelOpen),
                        child: Container(
                          width: 22,
                          height: 40,
                          decoration: BoxDecoration(
                            color: shad.background,
                            border: Border.all(color: shad.input),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              bottomLeft: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              _panelOpen ? Icons.chevron_right : Icons.chevron_left,
                              size: 14,
                              color: shad.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Panel content — right-aligned within this container
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 400,
                        color: shad.sidebar,
                        child: _buildPanelContent(sp, s, modelJsonPath),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Full-screen preview — character fills the entire area (LAV2: character-render.tsx lines 212-239)
  Widget _buildPreview(AppSettings s, String? modelJsonPath, ShadTheme shad) {
    final l10n = AppLocalizations.of(context);

    // Render turned off
    if (!s.renderModel) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.visibility_off, size: 64, color: shad.mutedForeground),
          const SizedBox(height: 16),
          Text('Render Model turned off',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: shad.mutedForeground)),
          const SizedBox(height: 8),
          Text(l10n.charShowCharacterDesc,
            style: TextStyle(fontSize: 14, color: shad.mutedForeground)),
        ]),
      );
    }

    // VRM mode (3D)
    if (s.use3D) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.view_in_ar, size: 80, color: shad.mutedForeground),
          const SizedBox(height: 16),
          Text('VRM 3D Preview', style: TextStyle(fontSize: 20, color: shad.mutedForeground)),
          const SizedBox(height: 8),
          Text('Coming soon', style: TextStyle(fontSize: 14, color: shad.mutedForeground)),
        ]),
      );
    }

    // Live2D mode — render full-screen, transparent overlay lets page bg through
    if (modelJsonPath != null) {
      return Container(
        color: Colors.transparent,
        child: Live2DView(
        modelPath: modelJsonPath,
        positionX: s.live2DXPosition,
        positionY: s.live2DYPosition,
        scale: s.live2DScale,
        interactive: false,
        onEvent: (event) { if (event.type == 'modelError') debugPrint('Live2D error: ${event.data}'); },
      ));
    }

    // No model selected
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.person, size: 80, color: shad.mutedForeground),
        const SizedBox(height: 16),
        Text('No model selected', style: TextStyle(fontSize: 20, color: shad.mutedForeground)),
        const SizedBox(height: 8),
        Text(l10n.charUploadHint, style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
      ]),
    );
  }

  /// Right side panel content — all character controls (LAV2: character-render.tsx lines 88-208)
  Widget _buildPanelContent(SettingsProvider sp, AppSettings s, String? modelJsonPath) {
    final l10n = AppLocalizations.of(context);
    final shad = ShadTheme.of(context);
    final isLive2D = !s.use3D;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Section: Display ──
        _panelSectionLabel(context, l10n.charDisplaySection, Icons.tv),
        const SizedBox(height: 12),
        _switchTile(context, l10n.charShowCharacter, l10n.charShowCharacterDesc,
          s.renderModel, (v) => _update(sp, s, renderModel: v)),
        const SizedBox(height: 8),
        _modeSelector(context, s, sp),
        const SizedBox(height: 24),

        // ── Section: Model Configuration ──
        _panelSectionLabel(context, l10n.charModelSection, Icons.person),
        const SizedBox(height: 12),

        if (isLive2D) ...[
          // Live2D model dropdown
          if (_models.isNotEmpty) ...[
            _modelDropdown(context, modelJsonPath, sp, s),
            const SizedBox(height: 16),
            _sliderControl(context, l10n.charXPosition, s.live2DXPosition, -100, 200, 1,
              (v) => _update(sp, s, live2DXPosition: v)),
            _sliderControl(context, l10n.charYPosition, s.live2DYPosition, -100, 200, 1,
              (v) => _update(sp, s, live2DYPosition: v)),
            _sliderControl(context, l10n.charScale, s.live2DScale, 0.01, 0.5, 0.01,
              (v) => _update(sp, s, live2DScale: v)),
          ],
          if (_models.isEmpty)
            _emptyHint(context, l10n.charNoModels),
        ] else ...[
          // VRM model section
          _emptyHint(context, l10n.charVRMComingToast),
        ],
        const SizedBox(height: 24),

        // ── Section: Model Management ──
        _panelSectionLabel(context, l10n.charManageSection, Icons.folder_open),
        const SizedBox(height: 12),
        // Upload buttons
        _uploadButton(context, l10n.charUploadLive2D, Icons.upload_file,
          _importingModel != null ? null : _uploadLive2DModel, _importingModel != null),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(l10n.charVRMComingToast), backgroundColor: shad.mutedForeground));
          },
          icon: const Icon(Icons.upload_file, size: 18),
          label: Text(l10n.charUploadVRM),
          style: OutlinedButton.styleFrom(
            foregroundColor: shad.mutedForeground,
            side: BorderSide(color: shad.border),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          ),
        ),
        const SizedBox(height: 4),
        Text(l10n.charUploadGuide, style: TextStyle(fontSize: 11, color: shad.mutedForeground)),
        const SizedBox(height: 12),

        // Installed models list
        if (_models.isNotEmpty) ...[
          Text(l10n.charInstalledModels, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: shad.foreground)),
          const SizedBox(height: 8),
          ..._models.map((m) => _modelTile(context, m, modelJsonPath, sp, s)),
        ],

        const SizedBox(height: 24),

        // ── Section: Desktop Pet ──
        _panelSectionLabel(context, l10n.charPetSection, Icons.pets),
        const SizedBox(height: 12),
        Text('Open a separate transparent always-on-top window with your Live2D character.',
          style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: modelJsonPath != null && !Live2DServer.petRunning
              ? () => _openPet(modelJsonPath, s) : null,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(Live2DServer.petRunning ? l10n.charPetActive : l10n.charOpenPet),
            style: OutlinedButton.styleFrom(
              foregroundColor: shad.primary,
              side: BorderSide(color: shad.primary),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            ),
          ),
          if (Live2DServer.petRunning) ...[
            OutlinedButton.icon(
              onPressed: _closePet,
              icon: const Icon(Icons.close, size: 18),
              label: Text(l10n.charClose),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _togglePetClickThrough,
              icon: Icon(_clickThrough ? Icons.touch_app : Icons.touch_app_outlined, size: 18),
              label: Text(_clickThrough ? l10n.charClickThroughOn : l10n.charInteractive),
              style: OutlinedButton.styleFrom(
                foregroundColor: _clickThrough ? shad.primary : shad.mutedForeground,
                side: BorderSide(color: _clickThrough ? shad.primary : shad.border),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _reloadPetModel,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.charReloadModel),
              style: OutlinedButton.styleFrom(
                foregroundColor: shad.mutedForeground, side: BorderSide(color: shad.input),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              ),
            ),
          ],
        ]),

        const SizedBox(height: 24),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  // Panel sub-widgets
  // ════════════════════════════════════════════════════════════

  Widget _panelSectionLabel(BuildContext context, String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: ShadTheme.of(context).mutedForeground),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
        color: ShadTheme.of(context).mutedForeground, letterSpacing: 0.5)),
    ]);
  }

  Widget _switchTile(BuildContext context, String label, String desc, bool value, ValueChanged<bool> onChanged) {
    final shad = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: shad.secondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: shad.foreground)),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 11, color: shad.mutedForeground)),
          ],
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: shad.primary),
      ]),
    );
  }

  Widget _modeSelector(BuildContext context, AppSettings s, SettingsProvider sp) {
    final shad = ShadTheme.of(context);
    return Row(children: [
      Expanded(child: _modeCard(context, 'Live2D (2D)', Icons.person_outline, !s.use3D,
        () => _update(sp, s, use3D: false))),
      const SizedBox(width: 10),
      Expanded(child: _modeCard(context, 'VRM (3D)', Icons.view_in_ar, s.use3D,
        () => _update(sp, s, use3D: true))),
    ]);
  }

  Widget _modeCard(BuildContext context, String title, IconData icon, bool selected, VoidCallback onTap) {
    final shad = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? shad.muted : shad.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? shad.primary : shad.border),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? shad.primary : shad.mutedForeground, size: 22),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
            color: selected ? shad.primary : shad.mutedForeground)),
        ]),
      ),
    );
  }

  Widget _modelDropdown(BuildContext context, String? modelJsonPath, SettingsProvider sp, AppSettings s) {
    final shad = ShadTheme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.charSelectModel, style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: shad.secondary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: shad.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: modelJsonPath != null && _models.any((m) => m['path'] == modelJsonPath)
              ? modelJsonPath : null,
            hint: Text(l10n.charSelectModelHint, style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
            isExpanded: true,
            dropdownColor: shad.card,
            style: TextStyle(fontSize: 13, color: shad.foreground),
            items: _models.map((m) => DropdownMenuItem<String>(
              value: m['path'],
              child: Text(m['name']!, style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (path) {
              if (path != null) _update(sp, s, selectedLive2DModel: path);
            },
          ),
        ),
      ),
    ]);
  }

  Widget _sliderControl(BuildContext context, String label, double value, double min, double max, double step, ValueChanged<double> onChanged) {
    final shad = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: shad.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(value.toStringAsFixed(step >= 1 ? 0 : 2),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: shad.primary)),
          ),
        ]),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: shad.primary,
            inactiveTrackColor: shad.secondary,
            thumbColor: shad.primary,
            overlayColor: shad.primary.withAlpha(40),
            trackHeight: 3,
          ),
          child: Slider(value: value, min: min, max: max,
            divisions: ((max - min) / step).round(),
            onChanged: onChanged),
        ),
      ]),
    );
  }

  Widget _emptyHint(BuildContext context, String text) {
    final shad = ShadTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: shad.secondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 16, color: shad.mutedForeground),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: shad.mutedForeground))),
      ]),
    );
  }

  Widget _uploadButton(BuildContext context, String label, IconData icon, VoidCallback? onPressed, bool loading) {
    final shad = ShadTheme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: loading
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: shad.primary))
          : Icon(icon, size: 18),
        label: Text(loading ? 'Importing...' : label),
        style: OutlinedButton.styleFrom(
          foregroundColor: shad.primary,
          side: BorderSide(color: shad.border),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
      ),
    );
  }

  Widget _modelTile(BuildContext context, Map<String, String> m, String? modelJsonPath,
      SettingsProvider sp, AppSettings s) {
    final shad = ShadTheme.of(context);
    final isSelected = modelJsonPath != null && modelJsonPath.contains(m['name']!);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? shad.muted : shad.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isSelected ? shad.primary : shad.border),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.person, color: shad.primary, size: 18),
        title: Text(m['name']!, style: const TextStyle(fontSize: 13)),
        selected: isSelected,
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: shad.mutedForeground, size: 16),
          onPressed: () => _deleteModel(m['name']!),
        ),
        onTap: () => _update(sp, s, selectedLive2DModel: m['path']),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════
  // Python Pet (asset-bundled)
  // ════════════════════════════════════════════════════════════

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).charPetFailed), backgroundColor: Colors.red));
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
          content: Text(AppLocalizations.of(context).charPetOpened), backgroundColor: ShadTheme.of(context).primary,
          duration: const Duration(seconds: 2)));
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
}
