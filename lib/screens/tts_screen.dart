import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';
import '../services/tts_service.dart';

/// TTS Settings page — horizontal provider carousel + per-provider config panel.
class TTSScreen extends StatefulWidget {
  TTSScreen({super.key});

  @override
  State<TTSScreen> createState() => _TTSScreenState();
}

class _TTSScreenState extends State<TTSScreen> {
  final _testTextController = TextEditingController(text: '你好，欢迎来到直播间！');
  final _carouselController = ScrollController();
  late TTSService _tts;

  // EdgeTTS voice list
  List<Map<String, String>> _voices = [];
  bool _loadingVoices = false;
  bool _isPlaying = false;
  StreamSubscription? _playerSub;

  // GPT-SoVITS state
  List<Map<String, String>> _gptRefAudios = [];
  List<Map<String, String>> _gptWeights = [];
  bool _gptServerRunning = false;
  bool _gptServerLoading = false;
  String? _gptError;
  String? _uploadWavPath;
  final _uploadVoiceNameCtrl = TextEditingController();
  final _uploadPromptTextCtrl = TextEditingController();
  final _pythonPathCtrl = TextEditingController(text: 'python');
  String _uploadPromptLang = 'zh';

  // Provider definitions for the carousel
  static const _providers = [
    _ProviderDef('edge-tts', Icons.record_voice_over, 'ttsProviderEdgeTts'),
    _ProviderDef('gpt-sovits', Icons.smart_toy, 'ttsProviderGptSovits'),
    _ProviderDef('rvc', Icons.graphic_eq, 'ttsProviderRvc'),
    _ProviderDef('azure', Icons.cloud, 'ttsProviderAzure'),
  ];

  @override
  void initState() {
    super.initState();
    _tts = context.read<ChatProvider>().backend.tts;
    _loadVoices();
    _playerSub = _tts.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
  }

  @override
  void dispose() {
    _carouselController.dispose();
    _testTextController.dispose();
    _uploadVoiceNameCtrl.dispose();
    _uploadPromptTextCtrl.dispose();
    _pythonPathCtrl.dispose();
    _playerSub?.cancel();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    setState(() => _loadingVoices = true);
    final voices = await _tts.listVoices();
    if (mounted) {
      setState(() {
        _voices = voices;
        _loadingVoices = false;
      });
    }
  }

  void _update(SettingsProvider sp, AppSettings s, {
    String? ttsProvider,
    bool? useRvc,
    int? rvcF0UpKey,
    String? edgeTtsVoice,
    String? edgeTtsPitch,
    String? edgeTtsRate,
    String? edgeTtsVolume,
    String? gptSovitsPath,
    String? gptSovitsGptWeights,
    String? gptSovitsSovitsWeights,
    String? gptSovitsRefAudio,
    String? gptSovitsPromptText,
    String? gptSovitsPromptLang,
    int? gptSovitsPort,
    String? gptSovitsDevice,
    String? gptSovitsPythonPath,
  }) {
    final updated = s.copyWith(
      ttsProvider: ttsProvider,
      useRvc: useRvc,
      rvcF0UpKey: rvcF0UpKey,
      edgeTtsVoice: edgeTtsVoice,
      edgeTtsPitch: edgeTtsPitch,
      edgeTtsRate: edgeTtsRate,
      edgeTtsVolume: edgeTtsVolume,
      gptSovitsPath: gptSovitsPath,
      gptSovitsGptWeights: gptSovitsGptWeights,
      gptSovitsSovitsWeights: gptSovitsSovitsWeights,
      gptSovitsRefAudio: gptSovitsRefAudio,
      gptSovitsPromptText: gptSovitsPromptText,
      gptSovitsPromptLang: gptSovitsPromptLang,
      gptSovitsPort: gptSovitsPort,
      gptSovitsDevice: gptSovitsDevice,
      gptSovitsPythonPath: gptSovitsPythonPath,
    );
    sp.saveSettings(updated);

    // Sync to TTSService instance
    if (edgeTtsVoice != null || edgeTtsPitch != null ||
        edgeTtsRate != null || edgeTtsVolume != null) {
      _tts.setParams(
        voice: edgeTtsVoice,
        pitch: edgeTtsPitch,
        rate: edgeTtsRate,
        volume: edgeTtsVolume,
      );
    }
  }

  Future<void> _testPlay() async {
    final text = _testTextController.text.trim();
    if (text.isEmpty) return;
    await _tts.synthesizeAndPlay(text);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, sp, _) {
        final s = sp.settings;
        final shad = ShadTheme.of(context);
        final l10n = AppLocalizations.of(context)!;

        // Build provider name map
        final providerNames = <String, String>{
          'edge-tts': l10n.ttsProviderEdgeTts,
          'gpt-sovits': l10n.ttsProviderGptSovits,
          'rvc': l10n.ttsProviderRvc,
          'azure': l10n.ttsProviderAzure,
        };

        return SingleChildScrollView(
          padding: EdgeInsets.only(top: 40, left: 48, right: 48, bottom: 40),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Text(
                  l10n.ttsTitle,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: shad.foreground,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  l10n.ttsSubtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: shad.mutedForeground,
                  ),
                ),
                SizedBox(height: 28),

                // ── Provider carousel ──
                _buildProviderCarousel(s.ttsProvider, providerNames, shad, (provider) {
                  _update(sp, s, ttsProvider: provider);
                }),
                SizedBox(height: 20),

                // ── Provider-specific settings ──
                if (s.ttsProvider == 'edge-tts')
                  _buildEdgeTtsPanel(s, shad, l10n, sp),
                if (s.ttsProvider == 'rvc')
                  _buildRvcPanel(s, shad, l10n, sp),
                if (s.ttsProvider == 'gpt-sovits')
                  _buildGptSovitsPanel(s, shad, l10n, sp),
                if (s.ttsProvider == 'azure')
                  _buildPlaceholderPanel('Azure TTS', l10n.ttsProviderAzure, shad),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Provider Carousel
  // ═══════════════════════════════════════════════════════════════

  Widget _buildProviderCarousel(
    String current,
    Map<String, String> names,
    ShadTheme shad,
    ValueChanged<String> onSelect,
  ) {
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          // Left scroll arrow
          _carouselArrow(Icons.chevron_left, () {
            _carouselController.animateTo(
              (_carouselController.offset - 120).clamp(0.0, _carouselController.position.maxScrollExtent),
              duration: Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }),
          // Scrollable cards
          Expanded(
            child: ListView.builder(
              controller: _carouselController,
              scrollDirection: Axis.horizontal,
              itemCount: _providers.length,
              itemBuilder: (context, index) {
                final def = _providers[index];
                final selected = current == def.id;
                return Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: _buildProviderCard(
                    def, names[def.id] ?? def.id, selected, shad,
                    () => onSelect(def.id),
                  ),
                );
              },
            ),
          ),
          // Right scroll arrow
          _carouselArrow(Icons.chevron_right, () {
            _carouselController.animateTo(
              (_carouselController.offset + 120).clamp(0.0, _carouselController.position.maxScrollExtent),
              duration: Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }),
        ],
      ),
    );
  }

  Widget _carouselArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 72,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: ShadTheme.of(context).mutedForeground),
      ),
    );
  }

  Widget _buildProviderCard(
    _ProviderDef def,
    String name,
    bool selected,
    ShadTheme shad,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        width: 120,
        decoration: BoxDecoration(
          color: selected ? shad.primary.withAlpha(18) : shad.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? shad.primary : shad.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              def.icon,
              size: 24,
              color: selected ? shad.primary : shad.mutedForeground,
            ),
            SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? shad.primary : shad.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // EdgeTTS Panel
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEdgeTtsPanel(AppSettings s, ShadTheme shad, AppLocalizations l10n, SettingsProvider sp) {
    return _shadCard(
      title: l10n.ttsEdgeTtsSettings,
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Voice selector ──
          Text(l10n.ttsEdgeTtsVoice, style: _labelStyle(shad)),
          SizedBox(height: 6),
          _loadingVoices
              ? Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: shad.secondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: shad.input),
                  ),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text(l10n.ttsLoadingVoices, style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
                  ]),
                )
              : _buildVoiceAutocomplete(s, shad, l10n, sp),
          SizedBox(height: 16),

          // ── Pitch slider ──
          _buildEdgeTtsSlider(
            shad: shad,
            label: l10n.ttsEdgeTtsPitch,
            value: _parsePitch(s.edgeTtsPitch),
            min: -20,
            max: 20,
            divisions: 40,
            suffix: 'Hz',
            displayValue: s.edgeTtsPitch,
            onChanged: (v) {
              final hz = v.round();
              final sign = hz >= 0 ? '+' : '';
              _update(sp, s, edgeTtsPitch: '$sign${hz}Hz');
            },
          ),
          SizedBox(height: 12),

          // ── Rate slider ──
          _buildEdgeTtsSlider(
            shad: shad,
            label: l10n.ttsEdgeTtsRate,
            value: _parsePercent(s.edgeTtsRate),
            min: -50,
            max: 50,
            divisions: 20,
            suffix: '%',
            displayValue: s.edgeTtsRate,
            onChanged: (v) {
              final pct = v.round();
              final sign = pct >= 0 ? '+' : '';
              _update(sp, s, edgeTtsRate: '$sign${pct}%');
            },
          ),
          SizedBox(height: 12),

          // ── Volume slider ──
          _buildEdgeTtsSlider(
            shad: shad,
            label: l10n.ttsEdgeTtsVolume,
            value: _parsePercent(s.edgeTtsVolume),
            min: -50,
            max: 50,
            divisions: 20,
            suffix: '%',
            displayValue: s.edgeTtsVolume,
            onChanged: (v) {
              final pct = v.round();
              final sign = pct >= 0 ? '+' : '';
              _update(sp, s, edgeTtsVolume: '$sign${pct}%');
            },
          ),
          SizedBox(height: 18),

          // ── Test play ──
          Text(l10n.ttsTestPlay, style: _labelStyle(shad)),
          SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _testTextController,
                  style: TextStyle(fontSize: 13, color: shad.foreground),
                  decoration: InputDecoration(
                    hintText: l10n.ttsTestPlayHint,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: shad.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: shad.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: shad.primary),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isPlaying ? null : _testPlay,
                icon: Icon(
                  _isPlaying ? Icons.volume_up : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(_isPlaying ? l10n.ttsPlaying : l10n.ttsTestPlay,
                    style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: shad.primary,
                  foregroundColor: shad.primaryForeground,
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Voice autocomplete: type to search or enter custom voice ──
  Widget _buildVoiceAutocomplete(AppSettings s, ShadTheme shad, AppLocalizations l10n, SettingsProvider sp) {
    // Build display labels for sorting/filtering
    final voiceLabels = <String, String>{};
    final voiceSearchTexts = <String, String>{};
    for (final v in _voices) {
      final sn = v['shortName'] ?? '';
      final locale = v['locale'] ?? '';
      final display = v['displayName'] ?? sn;
      voiceLabels[sn] = locale.isNotEmpty ? '$display ($locale)' : display;
      voiceSearchTexts[sn] = '$sn $display $locale'.toLowerCase();
    }

    String _voiceToLabel(String sn) => voiceLabels[sn] ?? sn;

    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _voiceToLabel(s.edgeTtsVoice)),
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return _voices.map((v) => v['shortName'] ?? '');
        }
        final query = textEditingValue.text.toLowerCase();
        return _voices
            .where((v) {
              final sn = v['shortName'] ?? '';
              final searchText = voiceSearchTexts[sn] ?? sn.toLowerCase();
              return searchText.contains(query);
            })
            .map((v) => v['shortName'] ?? '');
      },
      displayStringForOption: _voiceToLabel,
      onSelected: (shortName) {
        _update(sp, s, edgeTtsVoice: shortName);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onSubmitted) {
        // Keep controller in sync with settings
        if (textEditingController.text != _voiceToLabel(s.edgeTtsVoice) && !focusNode.hasFocus) {
          textEditingController.text = _voiceToLabel(s.edgeTtsVoice);
        }
        return Container(
          decoration: BoxDecoration(
            color: shad.secondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: focusNode.hasFocus ? shad.primary : shad.input,
            ),
          ),
          child: TextField(
            controller: textEditingController,
            focusNode: focusNode,
            onSubmitted: (text) {
              // On submit, try to match a voice; if no match, use raw text
              final match = _voices.firstWhere(
                (v) => _voiceToLabel(v['shortName'] ?? '') == text || v['shortName'] == text,
                orElse: () => {'shortName': text},
              );
              _update(sp, s, edgeTtsVoice: match['shortName'] ?? text);
            },
            style: TextStyle(fontSize: 13, color: shad.foreground),
            decoration: InputDecoration(
              hintText: l10n.ttsEdgeTtsVoiceHint,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: InputBorder.none,
              suffixIcon: Icon(Icons.arrow_drop_down, size: 20, color: shad.mutedForeground),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEdgeTtsSlider({
    required ShadTheme shad,
    required String label,
    required double value,
    required int min,
    required int max,
    required int divisions,
    required String suffix,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: _labelStyle(shad)),
            Text(displayValue,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: shad.foreground,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          activeColor: shad.primary,
          inactiveColor: shad.secondary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // RVC Panel
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRvcPanel(AppSettings s, ShadTheme shad, AppLocalizations l10n, SettingsProvider sp) {
    return _shadCard(
      title: l10n.ttsRvcSettings,
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Enable RVC switch
          Row(
            children: [
              SizedBox(
                height: 24,
                child: Switch(
                  value: s.useRvc,
                  onChanged: (v) => _update(sp, s, useRvc: v),
                  activeColor: shad.primary,
                ),
              ),
              SizedBox(width: 10),
              Text(l10n.ttsEnableRVC,
                style: TextStyle(fontSize: 14, color: shad.foreground),
              ),
            ],
          ),
          SizedBox(height: 16),

          // Pitch shift slider
          Row(
            children: [
              Text(l10n.ttsPitchShift,
                style: TextStyle(fontSize: 13, color: shad.mutedForeground),
              ),
              Text('${s.rvcF0UpKey}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: shad.foreground,
                ),
              ),
            ],
          ),
          Slider(
            value: s.rvcF0UpKey.toDouble(),
            min: -12,
            max: 12,
            divisions: 24,
            activeColor: shad.primary,
            inactiveColor: shad.secondary,
            onChanged: (v) => _update(sp, s, rvcF0UpKey: v.round()),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // GPT-SoVITS Panel
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGptSovitsPanel(AppSettings s, ShadTheme shad, AppLocalizations l10n, SettingsProvider sp) {
    // Refresh ref audios & weights when path changes (deferred to post-frame)
    if (s.gptSovitsPath.isNotEmpty && _gptRefAudios.isEmpty && _gptWeights.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshGptData(s));
    }
    // Sync Python path from settings to controller (avoids reset on tab switch)
    if (_pythonPathCtrl.text != s.gptSovitsPythonPath) {
      _pythonPathCtrl.text = s.gptSovitsPythonPath;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Path & Server card ──
        _shadCard(title: l10n.ttsGptSovitsSettings, icon: Icons.dns, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project Path
            Text(l10n.ttsGptSovitsPath, style: _labelStyle(shad)),
            SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: s.gptSovitsPath),
                  style: TextStyle(fontSize: 12, color: shad.foreground),
                  decoration: InputDecoration(
                    hintText: l10n.ttsGptSovitsPathHint,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: shad.border)),
                  ),
                  onSubmitted: (v) => _update(sp, s, gptSovitsPath: v),
                  onChanged: (v) {},
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await FilePicker.getDirectoryPath(dialogTitle: l10n.ttsGptSovitsPath);
                    if (result != null) {
                      _update(sp, s, gptSovitsPath: result);
                      _refreshGptData(sp.settings);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: shad.secondary, foregroundColor: shad.foreground, padding: EdgeInsets.symmetric(horizontal: 12)),
                  child: Text(l10n.ttsGptSovitsBrowse, style: TextStyle(fontSize: 12)),
                ),
              ),
            ]),
            SizedBox(height: 12),

            // Python Path
            Text(l10n.ttsGptSovitsPythonPath, style: _labelStyle(shad)),
            SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _pythonPathCtrl,
                  style: TextStyle(fontSize: 12, color: shad.foreground),
                  decoration: InputDecoration(
                    hintText: l10n.ttsGptSovitsPythonPathHint,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: shad.border)),
                  ),
                  onSubmitted: (v) => _update(sp, s, gptSovitsPythonPath: v),
                ),
              ),
            ]),
            SizedBox(height: 14),

            // Server control + status
            Row(children: [
              if (_gptServerRunning)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.withAlpha(25), borderRadius: BorderRadius.circular(4)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, size: 8, color: Colors.green),
                    SizedBox(width: 4),
                    Text(l10n.ttsGptSovitsServerRunning.replaceAll(r'$port', '${s.gptSovitsPort}'),
                        style: TextStyle(fontSize: 12, color: Colors.green)),
                  ]),
                )
              else
                Text(l10n.ttsGptSovitsServerStopped, style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
              Spacer(),
              if (_gptServerLoading)
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                ElevatedButton.icon(
                  onPressed: () => _toggleGptServer(sp, s),
                  icon: Icon(_gptServerRunning ? Icons.stop : Icons.play_arrow, size: 14),
                  label: Text(_gptServerRunning ? l10n.ttsGptSovitsStopServer : l10n.ttsGptSovitsStartServer, style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gptServerRunning ? Colors.red.withAlpha(30) : shad.primary,
                    foregroundColor: _gptServerRunning ? Colors.red : shad.primaryForeground,
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
            ]),
            if (_gptError != null) ...[
              SizedBox(height: 8),
              Text(_gptError!, style: TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ],
        )),
        SizedBox(height: 16),

        // ── Weights card ──
        if (s.gptSovitsPath.isNotEmpty) ...[
          _shadCard(title: 'Model Weights', icon: Icons.model_training, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // GPT weights dropdown
              Text(l10n.ttsGptSovitsGptWeights, style: _labelStyle(shad)),
              SizedBox(height: 6),
              _buildWeightsDropdown(
                shad: shad,
                value: s.gptSovitsGptWeights,
                hint: l10n.ttsGptSovitsSelectWeights,
                filterType: 'gpt',
                onChanged: (v) {
                  _update(sp, s, gptSovitsGptWeights: v);
                  if (_gptServerRunning) _tts.setGptWeights(v);
                },
              ),
              SizedBox(height: 12),

              // SoVITS weights dropdown
              Text(l10n.ttsGptSovitsSovitsWeights, style: _labelStyle(shad)),
              SizedBox(height: 6),
              _buildWeightsDropdown(
                shad: shad,
                value: s.gptSovitsSovitsWeights,
                hint: l10n.ttsGptSovitsSelectWeights,
                filterType: 'sovits',
                onChanged: (v) {
                  _update(sp, s, gptSovitsSovitsWeights: v);
                  if (_gptServerRunning) _tts.setSovitsWeights(v);
                },
              ),
            ],
          )),
          SizedBox(height: 16),

          // ── Reference Voice list ──
          _shadCard(title: l10n.ttsGptSovitsRefAudio, icon: Icons.record_voice_over, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_gptRefAudios.isEmpty)
                _gptEmptyState(l10n.ttsGptSovitsNoRefAudios, shad)
              else
                ..._gptRefAudios.map((r) => _buildRefAudioTile(r, s, shad, l10n, sp)),
            ],
          )),
          SizedBox(height: 16),

          // ── Upload Voice card ──
          _shadCard(title: l10n.ttsGptSovitsUploadVoice, icon: Icons.upload_file, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Voice name
              Text(l10n.ttsGptSovitsVoiceName, style: _labelStyle(shad)),
              SizedBox(height: 4),
              TextField(
                controller: _uploadVoiceNameCtrl,
                style: TextStyle(fontSize: 12, color: shad.foreground),
                decoration: InputDecoration(
                  hintText: l10n.ttsGptSovitsVoiceNameHint,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: shad.border)),
                ),
              ),
              SizedBox(height: 10),

              // Prompt text
              Text(l10n.ttsGptSovitsPromptText, style: _labelStyle(shad)),
              SizedBox(height: 4),
              TextField(
                controller: _uploadPromptTextCtrl,
                style: TextStyle(fontSize: 12, color: shad.foreground),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: '说话内容...',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: shad.border)),
                ),
              ),
              SizedBox(height: 10),

              // Language + WAV picker
              Row(children: [
                // Language dropdown
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l10n.ttsGptSovitsPromptLang, style: _labelStyle(shad)),
                    SizedBox(height: 4),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: shad.secondary,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: shad.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _uploadPromptLang,
                          isExpanded: true,
                          style: TextStyle(fontSize: 12, color: shad.foreground),
                          items: ['zh', 'en', 'ja', 'ko', 'yue'].map((l) =>
                            DropdownMenuItem(value: l, child: Text(_langLabel(l), style: TextStyle(fontSize: 12))),
                          ).toList(),
                          onChanged: (v) => setState(() => _uploadPromptLang = v ?? 'zh'),
                        ),
                      ),
                    ),
                  ]),
                ),
                SizedBox(width: 12),
                // WAV file picker
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WAV', style: _labelStyle(shad)),
                    SizedBox(height: 4),
                    SizedBox(
                      height: 38,
                      child: OutlinedButton(
                        onPressed: () async {
                          final result = await FilePicker.pickFiles(
                            type: FileType.custom, allowedExtensions: ['wav'],
                          );
                          if (result != null) {
                            setState(() => _uploadWavPath = result.files.single.path);
                          }
                        },
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 10)),
                        child: Text(
                          _uploadWavPath != null ? p.basename(_uploadWavPath!) : 'Select .wav',
                          style: TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
              SizedBox(height: 12),

              // Upload button
              SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () => _doUploadVoice(s, l10n, sp),
                  icon: Icon(Icons.cloud_upload, size: 14),
                  label: Text(l10n.ttsGptSovitsUploadVoice, style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: shad.primary, foregroundColor: shad.primaryForeground),
                ),
              ),
            ],
          )),
          SizedBox(height: 16),
        ],

        // ── Test Play card ──
        Text(l10n.ttsTestPlay, style: _labelStyle(shad)),
        SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _testTextController,
              style: TextStyle(fontSize: 13, color: shad.foreground),
              decoration: InputDecoration(
                hintText: l10n.ttsTestPlayHint,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: shad.border)),
              ),
            ),
          ),
          SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isPlaying ? null : () => _testPlayGptSovits(s),
            icon: Icon(_isPlaying ? Icons.volume_up : Icons.play_arrow, size: 16),
            label: Text(_isPlaying ? l10n.ttsPlaying : l10n.ttsTestPlay, style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: shad.primary, foregroundColor: shad.primaryForeground,
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ]),
        SizedBox(height: 16),
      ],
    );
  }

  // ── GPT-SoVITS helpers ──

  void _refreshGptData(AppSettings s) {
    if (s.gptSovitsPath.isEmpty) return;
    setState(() {
      _gptRefAudios = TTSService.scanRefAudios(s.gptSovitsPath);
      _gptWeights = TTSService.scanWeights(s.gptSovitsPath);
    });
    _gptServerRunning = _tts.isGptSovitsRunning;
  }

  Future<void> _toggleGptServer(SettingsProvider sp, AppSettings s) async {
    setState(() { _gptServerLoading = true; _gptError = null; });

    if (_gptServerRunning) {
      _tts.stopGptSovitsServer();
      setState(() { _gptServerRunning = false; _gptServerLoading = false; });
      return;
    }

    final err = await _tts.startGptSovitsServer(
      pythonPath: s.gptSovitsPythonPath.isEmpty ? 'python' : s.gptSovitsPythonPath,
      projectPath: s.gptSovitsPath,
      port: s.gptSovitsPort,
      device: s.gptSovitsDevice,
    );

    setState(() {
      _gptServerLoading = false;
      if (err != null) {
        _gptError = err;
        _gptServerRunning = false;
      } else {
        _gptServerRunning = true;
        _gptError = null;
        // Apply current weights to server
        if (s.gptSovitsGptWeights.isNotEmpty) _tts.setGptWeights(s.gptSovitsGptWeights);
        if (s.gptSovitsSovitsWeights.isNotEmpty) _tts.setSovitsWeights(s.gptSovitsSovitsWeights);
      }
    });
  }

  Future<void> _testPlayGptSovits(AppSettings s) async {
    final text = _testTextController.text.trim();
    if (text.isEmpty) return;
    if (!_gptServerRunning) {
      setState(() => _gptError = 'Please start the GPT-SoVITS server first.');
      return;
    }
    if (s.gptSovitsRefAudio.isEmpty) {
      setState(() => _gptError = 'Please select a reference voice.');
      return;
    }
    await _tts.synthesizeGptSovitsAndPlay(
      text: text,
      refAudioPath: s.gptSovitsRefAudio,
      promptText: s.gptSovitsPromptText,
      promptLang: s.gptSovitsPromptLang,
    );
  }

  Future<void> _doUploadVoice(AppSettings s, AppLocalizations l10n, SettingsProvider sp) async {
    final name = _uploadVoiceNameCtrl.text.trim();
    final promptText = _uploadPromptTextCtrl.text.trim();
    if (name.isEmpty || promptText.isEmpty || _uploadWavPath == null) {
      final msg = 'Please fill all fields';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }

    final err = await TTSService.uploadRefAudio(
      projectPath: s.gptSovitsPath,
      voiceName: name,
      sourceWavPath: _uploadWavPath!,
      promptText: promptText,
      promptLang: _uploadPromptLang,
    );

    if (mounted) {
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.ttsGptSovitsUploadFailed}: $err'), backgroundColor: Colors.red),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.ttsGptSovitsUploadSuccess), backgroundColor: Colors.green),
        );
        _uploadVoiceNameCtrl.clear();
        _uploadPromptTextCtrl.clear();
        setState(() => _uploadWavPath = null);
        _refreshGptData(sp.settings);
      }
    }
  }

  Widget _buildWeightsDropdown({
    required ShadTheme shad,
    required String value,
    required String hint,
    required String filterType,
    required ValueChanged<String> onChanged,
  }) {
    final items = _gptWeights.where((w) => w['type'] == filterType).toList();
    final displayValue = value.isNotEmpty ? p.basename(value) : null;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: shad.secondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: shad.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.any((w) => w['path'] == value) ? value : null,
          hint: Text(displayValue ?? hint, style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
          isExpanded: true,
          style: TextStyle(fontSize: 12, color: shad.foreground),
          items: items.map((w) => DropdownMenuItem(
            value: w['path'],
            child: Text(w['name']!, style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  Widget _buildRefAudioTile(Map<String, String> ref, AppSettings s, ShadTheme shad, AppLocalizations l10n, SettingsProvider sp) {
    final selected = s.gptSovitsRefAudio == ref['audioPath'];
    return Container(
      margin: EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected ? shad.primary.withAlpha(18) : shad.secondary.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? shad.primary : shad.border.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          _update(sp, s,
            gptSovitsRefAudio: ref['audioPath']!,
            gptSovitsPromptText: ref['promptText']!,
            gptSovitsPromptLang: ref['promptLang']!,
          );
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 16, color: selected ? shad.primary : shad.mutedForeground),
            SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ref['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: shad.foreground)),
                if (ref['promptText']?.isNotEmpty == true)
                  Text(ref['promptText']!, style: TextStyle(fontSize: 11, color: shad.mutedForeground), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            SizedBox(
              height: 28,
              child: IconButton(
                icon: Icon(Icons.delete_outline, size: 14, color: shad.mutedForeground),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _confirmDeleteVoice(ref['name']!, s, l10n, sp),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _confirmDeleteVoice(String name, AppSettings s, AppLocalizations l10n, SettingsProvider sp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.ttsGptSovitsDelete),
        content: Text(l10n.ttsGptSovitsDeleteConfirm.replaceAll(r'$name', name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              TTSService.deleteRefAudio(s.gptSovitsPath, name);
              // Clear selection if current voice was deleted
              if (s.gptSovitsRefAudio.contains('/$name/')) {
                _update(sp, s, gptSovitsRefAudio: '', gptSovitsPromptText: '', gptSovitsPromptLang: 'zh');
              }
              _refreshGptData(sp.settings);
            },
            child: Text(l10n.ttsGptSovitsDelete, style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _gptEmptyState(String msg, ShadTheme shad) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Column(children: [
        Icon(Icons.mic_none, size: 32, color: shad.mutedForeground.withAlpha(60)),
        SizedBox(height: 8),
        Text(msg, style: TextStyle(fontSize: 12, color: shad.mutedForeground), textAlign: TextAlign.center),
      ]),
    );
  }

  String _langLabel(String code) {
    switch (code) {
      case 'zh': return '中文';
      case 'en': return 'English';
      case 'ja': return '日本語';
      case 'ko': return '한국어';
      case 'yue': return '粵語';
      default: return code;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Placeholder Panel (for unimplemented providers)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPlaceholderPanel(String providerKey, String name, ShadTheme shad) {
    return _shadCard(
      title: name,
      icon: Icons.construction,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.inventory_2, size: 40, color: shad.mutedForeground.withAlpha(80)),
            SizedBox(height: 12),
            Text('$name — Coming soon',
              style: TextStyle(fontSize: 14, color: shad.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Shared widgets
  // ═══════════════════════════════════════════════════════════════

  TextStyle _labelStyle(ShadTheme shad) {
    return TextStyle(fontSize: 13, color: shad.mutedForeground, fontWeight: FontWeight.w500);
  }

  Widget _shadCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final shad = ShadTheme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: shad.border),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: shad.foreground),
              SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: shad.foreground,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // ── Parsing helpers ──
  static double _parsePitch(String s) {
    final match = RegExp(r'([+-]?\d+)').firstMatch(s);
    if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    return 0;
  }

  static double _parsePercent(String s) {
    final match = RegExp(r'([+-]?\d+)').firstMatch(s);
    if (match != null) return double.tryParse(match.group(1)!) ?? 0;
    return 0;
  }
}

/// Definition for a TTS provider in the carousel.
class _ProviderDef {
  final String id;
  final IconData icon;
  final String i18nKey;
  const _ProviderDef(this.id, this.icon, this.i18nKey);
}
