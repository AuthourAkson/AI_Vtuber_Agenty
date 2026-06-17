import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../services/live2d_model_service.dart';
import '../services/live2d_server.dart';
import '../services/vrm_model_service.dart';
import '../services/overlay_service.dart';
import '../services/vrm_pet_bridge.dart';
import '../widgets/live2d_view.dart';
import '../widgets/vrm_view.dart';
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
  final VrmModelService _vrmModelService = VrmModelService();
  List<Map<String, String>> _models = [];
  List<Map<String, String>> _vrmModels = [];
  String? _importingModel;
  int _petPort = 48889;
  bool _clickThrough = true;
  bool _mouseTracking = true;
  Color? _chromaKeyColor; // null = off; non-null = on with this color
  double _mouthScaleMin = 0.0;
  double _mouthScaleMax = 3.0;
  static const List<_ChromaKeyPreset> _chromaPresets = [
    _ChromaKeyPreset('Magenta', Color(0xFFFF00FF)),
    _ChromaKeyPreset('Blue', Color(0xFF0000FF)),
    _ChromaKeyPreset('Green', Color(0xFF00FF00)),
    _ChromaKeyPreset('Cyan', Color(0xFF00FFFF)),
    _ChromaKeyPreset('Red', Color(0xFFFF0000)),
    _ChromaKeyPreset('Yellow', Color(0xFFFFFF00)),
  ];
  bool _panelOpen = true;

  final HttpClient _httpClient = HttpClient();

  @override
  void initState() {
    super.initState();
    _refreshModels();
    _ensureDefaults();
    _loadChromaColor();
    _syncMouthScaleFromSettings();
    VrmPetBridge.loadPath();
    VrmPetBridge.runningNotifier.addListener(_onVrmPetStateChanged);
  }

  void _onVrmPetStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _closePet();
    VrmPetBridge.runningNotifier.removeListener(_onVrmPetStateChanged);
    // NOTE: Do NOT close VRM pet here — the process survives page navigation.
    _httpClient.close();
    super.dispose();
  }

  void _refreshModels() {
    setState(() {
      _models = _modelService.listModels();
      _vrmModels = _vrmModelService.listModels();
    });
  }

  /// Copy default VRM models from LAV2 on first run.
  Future<void> _ensureDefaults() async {
    if (_vrmModels.isEmpty) {
      try {
        await _vrmModelService.copyDefaultModels();
        await _vrmModelService.copyAnimations();
        _refreshModels();
      } catch (_) {
        // LAV2 models directory may not exist, that's fine
      }
    }
  }

  void _update(SettingsProvider sp, AppSettings s, {
    bool? renderModel, bool? use3D,
    double? live2DXPosition, double? live2DYPosition, double? live2DScale,
    String? selectedLive2DModel,
    String? selectedVRMModel,
    double? mouthScale,
  }) {
    sp.saveSettings(AppSettings(
      renderModel: renderModel ?? s.renderModel,
      use3D: use3D ?? s.use3D,
      live2DXPosition: live2DXPosition ?? s.live2DXPosition,
      live2DYPosition: live2DYPosition ?? s.live2DYPosition,
      live2DScale: live2DScale ?? s.live2DScale,
      selectedLive2DModel: selectedLive2DModel ?? s.selectedLive2DModel,
      selectedVRMModel: selectedVRMModel ?? s.selectedVRMModel,
      mouthScale: mouthScale ?? s.mouthScale,
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
      edgeTtsVoice: s.edgeTtsVoice,
      edgeTtsPitch: s.edgeTtsPitch,
      edgeTtsRate: s.edgeTtsRate,
      edgeTtsVolume: s.edgeTtsVolume,
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

  Future<void> _uploadVRMModel() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select VRM model file (.vrm)',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['vrm'],
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    setState(() => _importingModel = filePath);
    try {
      final destPath = await _vrmModelService.importModel(filePath);
      if (destPath != null && mounted) {
        _refreshModels();
        final sp = context.read<SettingsProvider>();
        _update(sp, sp.settings, selectedVRMModel: destPath);
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

  Future<void> _deleteVRMModel(String modelPath) async {
    final name = modelPath.split(Platform.pathSeparator).last.replaceAll('.vrm', '');
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
      _vrmModelService.deleteModel(name);
      _refreshModels();
      final sp = context.read<SettingsProvider>();
      if (sp.settings.selectedVRMModel == modelPath) {
        _update(sp, sp.settings, selectedVRMModel: null);
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
      final vrmPath = s.selectedVRMModel;
      final vrmBgColor = _chromaKeyColor ?? shad.background;
      if (vrmPath != null && vrmPath.isNotEmpty) {
        return Container(
          color: vrmBgColor,
          child: VrmView(
            modelPath: vrmPath,
            backgroundColor: vrmBgColor,
            onEvent: (event) {
              if (event.type == 'modelError') {
                debugPrint('[CharacterScreen] VRM error: ${event.data['error']}');
              }
            },
          ),
        );
      }
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.view_in_ar, size: 80, color: shad.mutedForeground),
          const SizedBox(height: 16),
          Text(l10n.charNoVRMModel, style: TextStyle(fontSize: 20, color: shad.mutedForeground)),
          const SizedBox(height: 8),
          Text(l10n.charUploadHint, style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
        ]),
      );
    }

    // Live2D mode — render full-screen, transparent overlay lets page bg through
    if (modelJsonPath != null) {
      final l2dBgColor = _chromaKeyColor ?? shad.background;
      return Container(
        color: l2dBgColor,
        child: Live2DView(
        modelPath: modelJsonPath,
        backgroundColor: l2dBgColor,
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
              (v) { _update(sp, s, live2DXPosition: v); _syncToPopout({'x': v}); }),
            _sliderControl(context, l10n.charYPosition, s.live2DYPosition, -100, 200, 1,
              (v) { _update(sp, s, live2DYPosition: v); _syncToPopout({'y': v}); }),
            _sliderControl(context, l10n.charScale, s.live2DScale, 0.01, 0.5, 0.01,
              (v) { _update(sp, s, live2DScale: v); _syncToPopout({'scale': v}); }),
          ],
          if (_models.isEmpty)
            _emptyHint(context, l10n.charNoModels),
        ] else ...[
          // VRM model section
          if (_vrmModels.isNotEmpty) ...[
            _vrmModelDropdown(context, s.selectedVRMModel, sp, s),
          ],
          if (_vrmModels.isEmpty)
            _emptyHint(context, l10n.charNoModels),
        ],
        const SizedBox(height: 24),

        // ── Section: Model Management ──
        _panelSectionLabel(context, l10n.charManageSection, Icons.folder_open),
        const SizedBox(height: 12),
        // Upload buttons — Live2D left, VRM right (always same order)
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _importingModel != null ? null : _uploadLive2DModel,
              icon: const Icon(Icons.person_outline, size: 16),
              label: Text(l10n.charUploadLive2D, style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: shad.primary,
                side: BorderSide(color: shad.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _importingModel != null ? null : _uploadVRMModel,
              icon: const Icon(Icons.view_in_ar, size: 16),
              label: Text(l10n.charUploadVRM, style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: shad.mutedForeground,
                side: BorderSide(color: shad.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Text(l10n.charUploadGuide, style: TextStyle(fontSize: 11, color: shad.mutedForeground)),
        const SizedBox(height: 12),

        // Installed models list
        if (isLive2D && _models.isNotEmpty) ...[
          Text(l10n.charInstalledModels, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: shad.foreground)),
          const SizedBox(height: 8),
          ..._models.map((m) => _modelTile(context, m, modelJsonPath, sp, s)),
        ],
        if (!isLive2D && _vrmModels.isNotEmpty) ...[
          Text(l10n.charInstalledModels, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: shad.foreground)),
          const SizedBox(height: 8),
          ..._vrmModels.map((m) => _vrmModelTile(context, m, s.selectedVRMModel, sp, s)),
        ],

        const SizedBox(height: 24),

        // ── Section: Desktop Pet ──
        _panelSectionLabel(context, l10n.charPetSection, Icons.pets),
        const SizedBox(height: 12),
        if (isLive2D) ...[
          Text('Open a separate transparent always-on-top window with your Live2D character.',
            style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
          const SizedBox(height: 8),
        ] else ...[
          // VRM Desktop Pet description
          Text(l10n.charVrmPetDesc,
            style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(l10n.charVrmPetPath(VrmPetBridge.exePath),
                style: TextStyle(fontSize: 11, color: shad.mutedForeground)),
            ),
          ]),
          const SizedBox(height: 8),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          // Character Pop Out (for OBS capture)
          OutlinedButton.icon(
            onPressed: OverlayService.instance.isPopoutRunning
                ? _closePopout
                : () => _openPopout(sp, s),
            icon: Icon(OverlayService.instance.isPopoutRunning ? Icons.close_fullscreen : Icons.open_in_full, size: 18),
            label: Text(OverlayService.instance.isPopoutRunning ? l10n.charPopoutClose : l10n.charPopoutOpen),
            style: OutlinedButton.styleFrom(
              foregroundColor: OverlayService.instance.isPopoutRunning ? const Color(0xFFEF4444) : shad.primary,
              side: BorderSide(color: OverlayService.instance.isPopoutRunning ? const Color(0xFFEF4444) : shad.primary),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            ),
          ),
          // ── Mouth Scale slider (only when pop-out is running) ──
          if (OverlayService.instance.isPopoutRunning)
            _mouthScaleControl(context, sp, s),
          // ── Live2D Pet: Open Pet button ──
          if (isLive2D)
            OutlinedButton.icon(
              onPressed: modelJsonPath != null && !Live2DServer.petRunning && !OverlayService.instance.isRunning
                ? () => _openPet(modelJsonPath, s) : null,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text((Live2DServer.petRunning || OverlayService.instance.isRunning) ? l10n.charPetActive : l10n.charOpenPet),
              style: OutlinedButton.styleFrom(
                foregroundColor: shad.primary,
                side: BorderSide(color: shad.primary),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              ),
            ),
          // ── VRM Pet: Launch + Settings ──
          if (!isLive2D)
            Row(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                onPressed: VrmPetBridge.isRunning ? null : _launchVRMPet,
                icon: Icon(VrmPetBridge.isRunning ? Icons.check_circle : Icons.play_arrow, size: 18),
                label: Text(VrmPetBridge.isRunning ? l10n.charVrmPetActive : l10n.charOpenVrmPet),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VrmPetBridge.isRunning ? const Color(0xFF4CAF50) : shad.primary,
                  side: BorderSide(color: VrmPetBridge.isRunning ? const Color(0xFF4CAF50) : shad.primary),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                ),
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: _showVrmPetSettings,
                style: OutlinedButton.styleFrom(
                  foregroundColor: shad.mutedForeground,
                  side: BorderSide(color: shad.border),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  minimumSize: Size.zero,
                ),
                child: const Icon(Icons.settings, size: 18),
              ),
            ]),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _chromaKeyColor = _chromaKeyColor != null ? null : const Color(0xFFFF00FF);
              });
              _saveChromaColor();
              final hex = _chromaKeyColor != null
                  ? (_chromaKeyColor!.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()
                  : 'transparent';
              _syncToPopout({'bgColor': hex});
            },
            icon: Icon(_chromaKeyColor != null ? Icons.colorize : Icons.colorize_outlined, size: 18),
            label: Text(_chromaKeyColor != null 
                ? l10n.charChromaKeyOn.replaceAll('\$colorName', _getColorName(_chromaKeyColor!))
                : l10n.charChromaKey),
            style: OutlinedButton.styleFrom(
              foregroundColor: _chromaKeyColor ?? shad.mutedForeground,
              side: BorderSide(color: _chromaKeyColor ?? shad.border),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            ),
          ),
          if (_chromaKeyColor != null)
            _buildChromaColorPicker(shad),
          if (Live2DServer.petRunning || OverlayService.instance.isRunning || VrmPetBridge.isRunning) ...[
            OutlinedButton.icon(
              onPressed: () { if (VrmPetBridge.isRunning) VrmPetBridge.close(); else _closePet(); },
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
            OutlinedButton.icon(
              onPressed: OverlayService.instance.isRunning ? _toggleMouseTracking : null,
              icon: Icon(_mouseTracking ? Icons.remove_red_eye : Icons.remove_red_eye_outlined, size: 18),
              label: Text(_mouseTracking ? '眼部追踪: 开' : '眼部追踪: 关'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _mouseTracking ? shad.primary : shad.mutedForeground,
                side: BorderSide(color: _mouseTracking ? shad.primary : shad.border),
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
        () {
          _update(sp, s, use3D: false);
          if (s.selectedLive2DModel != null) {
            _syncToPopout({'modelPath': s.selectedLive2DModel, 'use3D': false, 'scale': s.live2DScale});
          }
        })),
      const SizedBox(width: 10),
      Expanded(child: _modeCard(context, 'VRM (3D)', Icons.view_in_ar, s.use3D,
        () {
          _update(sp, s, use3D: true);
          if (s.selectedVRMModel != null) {
            _syncToPopout({'modelPath': s.selectedVRMModel, 'use3D': true, 'scale': 0.8});
          }
        })),
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
              if (path != null) {
                _update(sp, s, selectedLive2DModel: path);
                _syncToPopout({'modelPath': path, 'use3D': false, 'scale': s.live2DScale});
              }
            },
          ),
        ),
      ),
    ]);
  }

  Widget _vrmModelDropdown(BuildContext context, String? modelPath, SettingsProvider sp, AppSettings s) {
    final shad = ShadTheme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.charSelectVRMModel, style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
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
            value: modelPath != null && _vrmModels.any((m) => m['path'] == modelPath)
              ? modelPath : null,
            hint: Text(l10n.charSelectModelHint, style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
            isExpanded: true,
            dropdownColor: shad.card,
            style: TextStyle(fontSize: 13, color: shad.foreground),
            items: _vrmModels.map((m) => DropdownMenuItem<String>(
              value: m['path'],
              child: Text(m['name']!, style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (path) {
              if (path != null) {
                _update(sp, s, selectedVRMModel: path);
                _syncToPopout({'modelPath': path, 'use3D': true, 'scale': 0.8});
              }
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

  /// Mouth scale control: editable min/max text fields + slider.
  /// Only shown when pop-out is running. Value persisted to settings.
  Widget _mouthScaleControl(BuildContext context, SettingsProvider sp, AppSettings s) {
    final shad = ShadTheme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final overlay = OverlayService.instance;
    final currentScale = overlay.mouthScale;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.charMouthScale, style: TextStyle(fontSize: 11, color: shad.mutedForeground)),
        const SizedBox(height: 4),
        Row(children: [
          // Min input
          SizedBox(
            width: 52,
            child: TextField(
              controller: TextEditingController(text: _mouthScaleMin.toStringAsFixed(1)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 11, color: shad.foreground),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                labelText: l10n.charMouthScaleMin,
                labelStyle: TextStyle(fontSize: 9, color: shad.mutedForeground),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: shad.border)),
              ),
              onSubmitted: (v) {
                final val = double.tryParse(v);
                if (val != null && val < _mouthScaleMax) {
                  setState(() => _mouthScaleMin = val);
                }
              },
            ),
          ),
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: shad.primary,
                inactiveTrackColor: shad.secondary,
                thumbColor: shad.primary,
                overlayColor: shad.primary.withAlpha(40),
                trackHeight: 4,
              ),
              child: Slider(
                value: currentScale.clamp(_mouthScaleMin, _mouthScaleMax),
                min: _mouthScaleMin,
                max: _mouthScaleMax,
                onChanged: (v) {
                  overlay.mouthScale = v;
                  _update(sp, s, mouthScale: v);
                },
              ),
            ),
          ),
          // Max input
          SizedBox(
            width: 52,
            child: TextField(
              controller: TextEditingController(text: _mouthScaleMax.toStringAsFixed(1)),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 11, color: shad.foreground),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                labelText: l10n.charMouthScaleMax,
                labelStyle: TextStyle(fontSize: 9, color: shad.mutedForeground),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: shad.border)),
              ),
              onSubmitted: (v) {
                final val = double.tryParse(v);
                if (val != null && val > _mouthScaleMin) {
                  setState(() => _mouthScaleMax = val);
                }
              },
            ),
          ),
        ]),
        // Current value display
        Align(
          alignment: Alignment.centerRight,
          child: Text('${currentScale.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: shad.primary)),
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
        onTap: () {
          _update(sp, s, selectedLive2DModel: m['path']);
          _syncToPopout({'modelPath': m['path'], 'use3D': false, 'scale': s.live2DScale});
        },
      ),
    );
  }

  Widget _vrmModelTile(BuildContext context, Map<String, String> m, String? selectedPath,
      SettingsProvider sp, AppSettings s) {
    final shad = ShadTheme.of(context);
    final isSelected = selectedPath != null && selectedPath == m['path'];
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? shad.muted : shad.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isSelected ? shad.primary : shad.border),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.view_in_ar, color: shad.primary, size: 18),
        title: Text(m['name']!, style: const TextStyle(fontSize: 13)),
        selected: isSelected,
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: shad.mutedForeground, size: 16),
          onPressed: () => _deleteVRMModel(m['path']!),
        ),
        onTap: () {
          _update(sp, s, selectedVRMModel: m['path']);
          _syncToPopout({'modelPath': m['path'], 'use3D': true, 'scale': 0.8});
        },
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
    if (Live2DServer.petRunning || OverlayService.instance.isRunning) return;

    // 优先使用原生C++透明overlay (WS_EX_NOREDIRECTIONBITMAP, 真透明)
    final overlay = OverlayService.instance;
    final ok = await overlay.startLive2D(
      modelPath: modelPath,
      scale: s.live2DScale,
      x: (s.live2DXPosition * 10).toInt(),
      y: (s.live2DYPosition * 10).toInt(),
      width: 500,
      height: 600,
    );
    if (ok) {
      if (mounted) setState(() {});
      return;
    }

    // 回退：Python pet (旧方案)
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
    if (OverlayService.instance.isRunning) {
      OverlayService.instance.stop();
      if (mounted) setState(() {});
      return;
    }
    if (!Live2DServer.petRunning) return;
    Live2DServer.killPet();
    setState(() {});
  }

  // ════════════════════════════════════════════════════════════
  // VRM Desktop Pet — launches AI-Pet-Engine (Unity)
  // ════════════════════════════════════════════════════════════

  Future<void> _launchVRMPet() async {
    if (VrmPetBridge.isRunning) return;
    final l10n = AppLocalizations.of(context);

    final error = await VrmPetBridge.launch();
    if (!mounted) return;

    if (error == 'timeout') {
      // Launched but bridge not ready yet
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.charVrmPetLaunched),
            backgroundColor: ShadTheme.of(context).primary,
            duration: const Duration(seconds: 2)));
      return;
    }

    if (error != null) {
      if (error.startsWith('Not found:')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.charVrmPetNotFoundPath(VrmPetBridge.exePath)),
              backgroundColor: Colors.red));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.charVrmPetFailed(error)),
              backgroundColor: Colors.red));
      }
      return;
    }

    // Bridge alive — push system prompt
    try {
      final sp = context.read<SettingsProvider>();
      final prompt = sp.settings.systemPrompt;
      if (prompt.isNotEmpty) {
        await VrmPetBridge.pushSystemPrompt(prompt);
        debugPrint('[VRM Pet] System prompt pushed (len=${prompt.length})');
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.charVrmPetLaunchedConnected),
            backgroundColor: ShadTheme.of(context).primary,
            duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _showVrmPetSettings() async {
    final l10n = AppLocalizations.of(context);
    final shad = ShadTheme.of(context);
    final controller = TextEditingController(text: VrmPetBridge.exePath);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: shad.card,
        title: Text(l10n.charVrmPetSettings),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.charVrmPetSettingsDesc,
              style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: shad.secondary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: shad.border),
              ),
              child: TextField(
                controller: controller,
                style: TextStyle(fontSize: 13, color: shad.foreground),
                decoration: InputDecoration(
                  hintText: VrmPetBridge.defaultPath,
                  hintStyle: TextStyle(fontSize: 12, color: shad.mutedForeground),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel, style: TextStyle(color: shad.mutedForeground))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.save, style: TextStyle(color: shad.primary))),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await VrmPetBridge.savePath(result);
      if (mounted) setState(() {});
    }
    controller.dispose();
  }

  void _togglePetClickThrough() {
    if (OverlayService.instance.isRunning) {
      setState(() => _clickThrough = !_clickThrough);
      OverlayService.instance.setClickThrough(_clickThrough);
      return;
    }
    if (!Live2DServer.petRunning) return;
    setState(() => _clickThrough = !_clickThrough);
  }

  void _toggleMouseTracking() {
    if (OverlayService.instance.isRunning) {
      setState(() => _mouseTracking = !_mouseTracking);
      OverlayService.instance.setMouseTracking(_mouseTracking);
    }
  }

  // ═══ Character Pop Out window (for OBS capture) ═══

  Future<void> _openPopout(SettingsProvider sp, AppSettings s) async {
    if (OverlayService.instance.isPopoutRunning) return;

    final is3D = s.use3D;
    final modelPath = is3D ? s.selectedVRMModel : s.selectedLive2DModel;
    if (modelPath == null || modelPath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.charNoModels),
              backgroundColor: Colors.red));
      }
      return;
    }

    final overlay = OverlayService.instance;
    final ok = await overlay.startCharacterPopout(
      use3D: is3D,
      modelPath: modelPath,
      backgroundColor: _chromaKeyColor,
      scale: is3D ? 0.8 : s.live2DScale,
      width: 600,
      height: 700,
    );

    if (ok && mounted) {
      setState(() {});
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Pop Out'), backgroundColor: Colors.red));
    }
  }

  void _closePopout() {
    OverlayService.instance.stopPopout();
    if (mounted) setState(() {});
  }

  void _syncToPopout(Map<String, dynamic> data) {
    final overlay = OverlayService.instance;
    if (!overlay.isPopoutRunning) return;

    // Position sync (Live2D)
    if (data.containsKey('x') || data.containsKey('y')) {
      final x = (data['x'] as num?)?.toInt() ?? 50;
      final y = (data['y'] as num?)?.toInt() ?? 50;
      overlay.executePopoutScript('setModelPosition($x, $y);');
    }
    // Scale sync
    if (data.containsKey('scale')) {
      final s = data['scale'];
      overlay.executePopoutScript('setModelScale($s);');
      overlay.executePopoutScript('window.setVRMScale && window.setVRMScale($s);');
    }
    // Background color sync
    if (data.containsKey('bgColor')) {
      final hex = data['bgColor'] as String;
      if (hex == 'transparent') {
        overlay.executePopoutScript("setBackground('transparent');");
        overlay.executePopoutScript("vrmSetBackground('transparent');");
      } else {
        overlay.executePopoutScript("setBackground('#$hex');");
        overlay.executePopoutScript("vrmSetBackground('#$hex');");
      }
    }
  }

  String _getColorName(Color c) {
    final v = c.value & 0xFFFFFF;
    for (final p in _chromaPresets) {
      if ((p.color.value & 0xFFFFFF) == v) return p.name;
    }
    return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Widget _buildChromaColorPicker(ShadTheme shad) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(AppLocalizations.of(context)!.charChromaKeyColor, style: TextStyle(fontSize: 11, color: shad.mutedForeground)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final preset in _chromaPresets)
            GestureDetector(
              onTap: () {
                setState(() => _chromaKeyColor = preset.color);
                _saveChromaColor();
                _syncToPopout({'bgColor': (preset.color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()});
              },
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: preset.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _chromaKeyColor != null && (_chromaKeyColor!.value & 0xFFFFFF) == (preset.color.value & 0xFFFFFF)
                        ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: [BoxShadow(color: preset.color.withAlpha(60), blurRadius: 4)],
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        // Inline HSV picker
        _HsvColorPicker(
          initialColor: _chromaKeyColor ?? const Color(0xFFFF00FF),
          onChanged: (c) {
            setState(() => _chromaKeyColor = c);
            _saveChromaColor();
            _syncToPopout({'bgColor': (c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()});
          },
        ),
      ],
    );
  }

  Future<void> _loadChromaColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hex = prefs.getString('chroma_key_color');
      if (hex != null) {
        final parsed = int.tryParse(hex, radix: 16);
        if (parsed != null && mounted) {
          setState(() => _chromaKeyColor = Color(0xFF000000 | parsed));
        }
      }
    } catch (_) {}
  }

  /// Sync mouthScale from persisted settings into OverlayService.
  void _syncMouthScaleFromSettings() {
    try {
      final sp = context.read<SettingsProvider>();
      OverlayService.instance.mouthScale = sp.settings.mouthScale;
    } catch (_) {}
  }

  Future<void> _saveChromaColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_chromaKeyColor == null) {
        await prefs.remove('chroma_key_color');
      } else {
        final hex = (_chromaKeyColor!.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
        await prefs.setString('chroma_key_color', hex);
      }
    } catch (_) {}
  }

  void _reloadPetModel() {
    if (!Live2DServer.petRunning) return;
    _closePet();
    final sp = context.read<SettingsProvider>();
    final path = sp.settings.selectedLive2DModel;
    if (path != null) _openPet(path, sp.settings);
  }
}

class _ChromaKeyPreset {
  final String name;
  final Color color;
  const _ChromaKeyPreset(this.name, this.color);
}

// ════════════════════════════════════════════════════════════
// HSV Color Picker widget (zero external deps)
// ════════════════════════════════════════════════════════════
class _HsvColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onChanged;

  const _HsvColorPicker({required this.initialColor, required this.onChanged});

  @override
  State<_HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends State<_HsvColorPicker> {
  late double _hue;       // 0-360
  late double _sat;       // 0-1
  late double _val;       // 0-1
  late double _alpha;     // stored from initial

  static const double _svSize = 160.0;
  static const double _hueBarHeight = 16.0;
  static const double _thumbRadius = 5.0;

  @override
  void initState() {
    super.initState();
    final hsv = _colorToHsv(widget.initialColor);
    _hue = hsv[0];
    _sat = hsv[1];
    _val = hsv[2];
    _alpha = widget.initialColor.alpha / 255.0;
  }

  Color get _currentColor => _hsvToColor(_hue, _sat, _val, _alpha);

  void _onSvChange(Offset local, Size size) {
    setState(() {
      _sat = (local.dx / size.width).clamp(0.0, 1.0);
      _val = 1.0 - (local.dy / size.height).clamp(0.0, 1.0);
    });
    widget.onChanged(_currentColor);
  }

  void _onHueChange(double localX, double width) {
    setState(() {
      _hue = 360.0 * (localX / width).clamp(0.0, 1.0);
    });
    widget.onChanged(_currentColor);
  }

  static Color _hsvToColor(double h, double s, double v, double a) {
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;
    double r, g, b;
    if (h < 60)       { r = c; g = x; b = 0; }
    else if (h < 120) { r = x; g = c; b = 0; }
    else if (h < 180) { r = 0; g = c; b = x; }
    else if (h < 240) { r = 0; g = x; b = c; }
    else if (h < 300) { r = x; g = 0; b = c; }
    else              { r = c; g = 0; b = x; }
    return Color.fromRGBO(
      ((r + m) * 255).round().clamp(0, 255),
      ((g + m) * 255).round().clamp(0, 255),
      ((b + m) * 255).round().clamp(0, 255),
      a,
    );
  }

  static List<double> _colorToHsv(Color c) {
    final r = c.red / 255.0, g = c.green / 255.0, b = c.blue / 255.0;
    final mx = [r, g, b].reduce((a, b) => a > b ? a : b);
    final mn = [r, g, b].reduce((a, b) => a < b ? a : b);
    final d = mx - mn;
    double h = 0;
    if (d != 0) {
      if (mx == r) h = 60 * (((g - b) / d) % 6);
      else if (mx == g) h = 60 * (((b - r) / d) + 2);
      else h = 60 * (((r - g) / d) + 4);
    }
    if (h < 0) h += 360;
    final s = mx == 0 ? 0.0 : d / mx;
    final v = mx;
    return [h, s, v];
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = _hsvToColor(_hue, 1.0, 1.0, 1.0);
    final svThumbX = _sat * _svSize;
    final svThumbY = (1.0 - _val) * _svSize;
    final hueThumbX = (_hue / 360.0) * _svSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── SV square ──
        GestureDetector(
          onTapDown: (d) => _onSvChange(d.localPosition, const Size(_svSize, _svSize)),
          onPanUpdate: (d) => _onSvChange(d.localPosition, const Size(_svSize, _svSize)),
          child: Container(
            width: _svSize, height: _svSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x33FFFFFF)),
              color: hueColor,
            ),
            child: Stack(
              children: [
                // White → transparent (left to right = Saturation 0→1)
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(5)),
                      gradient: LinearGradient(
                        colors: [Colors.white, Color(0x00FFFFFF)],
                        stops: [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                // Transparent → black (top to bottom = Value 1→0)
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.all(Radius.circular(5)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Colors.black],
                        stops: [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                // Thumb
                Positioned(
                  left: svThumbX - _thumbRadius,
                  top: svThumbY - _thumbRadius,
                  child: Container(
                    width: _thumbRadius * 2, height: _thumbRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentColor,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ── Hue bar ──
        GestureDetector(
          onTapDown: (d) => _onHueChange(d.localPosition.dx, _svSize),
          onPanUpdate: (d) => _onHueChange(d.localPosition.dx, _svSize),
          child: Container(
            width: _svSize, height: _hueBarHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                  Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: hueThumbX - _thumbRadius,
                  top: 0, bottom: 0,
                  child: Container(
                    width: _thumbRadius * 2,
                    decoration: BoxDecoration(
                      color: hueColor,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
