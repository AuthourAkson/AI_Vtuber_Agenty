import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
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
  }) {
    final updated = s.copyWith(
      ttsProvider: ttsProvider,
      useRvc: useRvc,
      rvcF0UpKey: rvcF0UpKey,
      edgeTtsVoice: edgeTtsVoice,
      edgeTtsPitch: edgeTtsPitch,
      edgeTtsRate: edgeTtsRate,
      edgeTtsVolume: edgeTtsVolume,
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
                  _buildPlaceholderPanel('GPT-SoVITS', l10n.ttsProviderGptSovits, shad),
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
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: shad.secondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: shad.input),
            ),
            child: _loadingVoices
                ? Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Row(children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text(l10n.ttsLoadingVoices, style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
                    ]),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _voices.any((v) => v['shortName'] == s.edgeTtsVoice)
                          ? s.edgeTtsVoice
                          : null,
                      isExpanded: true,
                      hint: Text(l10n.ttsEdgeTtsVoiceHint,
                          style: TextStyle(fontSize: 13, color: shad.mutedForeground)),
                      style: TextStyle(fontSize: 13, color: shad.foreground),
                      items: _voices.map((v) {
                        final locale = v['locale'] ?? '';
                        final display = v['displayName'] ?? v['shortName'] ?? '';
                        final label = locale.isNotEmpty
                            ? '$display ($locale)'
                            : display;
                        return DropdownMenuItem(
                          value: v['shortName'],
                          child: Text(label, style: TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (voice) {
                        if (voice != null) {
                          _update(sp, s, edgeTtsVoice: voice);
                        }
                      },
                    ),
                  ),
          ),
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
