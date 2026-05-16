     1|     1|import 'dart:io';
     2|     2|import 'dart:math' as math;
     3|     3|import 'package:flutter/material.dart';
     4|     4|import 'package:provider/provider.dart';
     5|     5|import 'package:file_picker/file_picker.dart';
     6|     6|import '../app.dart';
     7|     7|import '../models/appearance_prefs.dart';
     8|     8|import '../providers/appearance_provider.dart';
     9|     9|
    10|    10|/// MultiAgent Settings → Preferences → Appearance
    11|    11|///
    12|    12|/// All changes apply globally through AppearanceProvider.
    13|    13|/// Sections:
    14|    14|///   1. Dark Mode
    15|    15|///   2. Font Size
    16|    16|///   3. Theme Color (16 presets)
    17|    17|///   4. Background Pattern (13 previews)
    18|    18|///   5. Background Image
    19|    19|///   6. Startup Animation
    20|    20|///   7. Reset to Default
    21|    21|class MultiAgentAppearancePage extends StatelessWidget {
    22|    22|  const MultiAgentAppearancePage({super.key});
    23|    23|
    24|    24|  @override
    25|    25|  Widget build(BuildContext context) {
    26|    26|    final ap = context.watch<AppearanceProvider>();
    27|    27|    final accent = Color(ap.accentColorValue);
    28|    28|
    29|    29|    return SingleChildScrollView(
    30|    30|      padding: const EdgeInsets.all(24),
    31|    31|      child: Column(
    32|    32|        crossAxisAlignment: CrossAxisAlignment.start,
    33|    33|        children: [
    34|    34|          _sectionHeader('Appearance', Icons.palette_outlined, accent),
    35|    35|          const SizedBox(height: 24),
    36|    36|
    37|    37|          // 1. Dark Mode
    38|    38|          _buildDarkMode(ap, accent),
    39|    39|          const SizedBox(height: 24),
    40|    40|
    41|    41|          // 2. Font Size
    42|    42|          _buildFontSize(ap, accent),
    43|    43|          const SizedBox(height: 24),
    44|    44|
    45|    45|          // 3. Theme Color
    46|    46|          _buildThemeColor(ap, accent),
    47|    47|          const SizedBox(height: 24),
    48|    48|
    49|    49|          // 4. Background Pattern
    50|    50|          _buildBgPattern(ap, accent),
    51|    51|          const SizedBox(height: 24),
    52|    52|
    53|    53|          // 5. Background Image
    54|    54|          _buildBgImage(ap, accent, context),
    55|    55|          const SizedBox(height: 24),
    56|    56|
    57|    57|          // 6. Startup Animation
    58|    58|          _buildStartupAnim(ap, accent),
    59|    59|          const SizedBox(height: 24),
    60|    60|
    61|    61|          // 7. Reset to Default
    62|    62|          _buildResetSection(ap, accent, context),
    63|    63|          const SizedBox(height: 32),
    64|    64|        ],
    65|    65|      ),
    66|    66|    );
    67|    67|  }
    68|    68|
    69|    69|  // ═══════════════════════════════════════════════════════
    70|    70|  // Helpers
    71|    71|  // ═══════════════════════════════════════════════════════
    72|    72|
    73|    73|  Widget _sectionHeader(String title, IconData icon, Color accent) {
    74|    74|    return Row(
    75|    75|      children: [
    76|    76|        Icon(icon, size: 20, color: accent),
    77|    77|        const SizedBox(width: 8),
    78|    78|        Text(title,
    79|    79|            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
    80|    80|      ],
    81|    81|    );
    82|    82|  }
    83|    83|
    84|    84|  Widget _sectionLabel(String title, String? subtitle) {
    85|    85|    return Padding(
    86|    86|      padding: const EdgeInsets.only(bottom: 12),
    87|    87|      child: Column(
    88|    88|        crossAxisAlignment: CrossAxisAlignment.start,
    89|    89|        children: [
    90|    90|          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
    91|    91|          if (subtitle != null) ...[
    92|    92|            const SizedBox(height: 2),
    93|    93|            Text(subtitle, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
    94|    94|          ],
    95|    95|        ],
    96|    96|      ),
    97|    97|    );
    98|    98|  }
    99|    99|
   100|   100|  Widget _settingCard({required Widget child}) {
   101|   101|    return Container(
   102|   102|      padding: const EdgeInsets.all(16),
   103|   103|      decoration: BoxDecoration(
   104|   104|        color: ShadTheme.of(context).card,
   105|   105|        borderRadius: BorderRadius.circular(10),
   106|   106|        border: Border.all(color: ShadTheme.of(context).border),
   107|   107|      ),
   108|   108|      child: child,
   109|   109|    );
   110|   110|  }
   111|   111|
   112|   112|  // ═══════════════════════════════════════════════════════
   113|   113|  // 1. Dark Mode
   114|   114|  // ═══════════════════════════════════════════════════════
   115|   115|
   116|   116|  Widget _buildDarkMode(AppearanceProvider ap, Color accent) {
   117|   117|    return _settingCard(
   118|   118|      child: Row(
   119|   119|        children: [
   120|   120|          Icon(Icons.dark_mode, size: 22, color: ShadTheme.of(context).foreground),
   121|   121|          const SizedBox(width: 12),
   122|   122|          Expanded(
   123|   123|            child: _sectionLabel('Dark Mode', 'Switch between dark and light theme'),
   124|   124|          ),
   125|   125|          Switch(
   126|   126|            value: ap.isDark,
   127|   127|            onChanged: (v) => ap.update(ap.prefs.copyWith(darkMode: v)),
   128|   128|            activeColor: accent,
   129|   129|          ),
   130|   130|        ],
   131|   131|      ),
   132|   132|    );
   133|   133|  }
   134|   134|
   135|   135|  // ═══════════════════════════════════════════════════════
   136|   136|  // 2. Font Size
   137|   137|  // ═══════════════════════════════════════════════════════
   138|   138|
   139|   139|  Widget _buildFontSize(AppearanceProvider ap, Color accent) {
   140|   140|    return _settingCard(
   141|   141|      child: Column(
   142|   142|        crossAxisAlignment: CrossAxisAlignment.start,
   143|   143|        children: [
   144|   144|          Row(
   145|   145|            children: [
   146|   146|              Icon(Icons.format_size, size: 22, color: ShadTheme.of(context).foreground),
   147|   147|              const SizedBox(width: 12),
   148|   148|              Expanded(
   149|   149|                child: _sectionLabel('Font Size', 'Adjust text size across the app'),
   150|   150|              ),
   151|   151|              Container(
   152|   152|                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
   153|   153|                decoration: BoxDecoration(
   154|   154|                  color: accent.withAlpha(25),
   155|   155|                  borderRadius: BorderRadius.circular(6),
   156|   156|                ),
   157|   157|                child: Text('${ap.fontSize.toInt()} px',
   158|   158|                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
   159|   159|              ),
   160|   160|            ],
   161|   161|          ),
   162|   162|          const SizedBox(height: 12),
   163|   163|          SliderTheme(
   164|   164|            data: SliderThemeData(
   165|   165|              activeTrackColor: accent,
   166|   166|              inactiveTrackColor: ShadTheme.of(context).secondary,
   167|   167|              thumbColor: accent,
   168|   168|              overlayColor: accent.withAlpha(40),
   169|   169|            ),
   170|   170|            child: Slider(
   171|   171|              value: ap.fontSize,
   172|   172|              min: 12,
   173|   173|              max: 20,
   174|   174|              divisions: 8,
   175|   175|              onChanged: (v) => ap.update(ap.prefs.copyWith(fontSize: v)),
   176|   176|            ),
   177|   177|          ),
   178|   178|          Center(
   179|   179|            child: Padding(
   180|   180|              padding: const EdgeInsets.only(top: 8),
   181|   181|              child: Text(
   182|   182|                'The quick brown fox jumps over the lazy dog.',
   183|   183|                style: TextStyle(fontSize: ap.fontSize, color: ShadTheme.of(context).foreground),
   184|   184|              ),
   185|   185|            ),
   186|   186|          ),
   187|   187|        ],
   188|   188|      ),
   189|   189|    );
   190|   190|  }
   191|   191|
   192|   192|  // ═══════════════════════════════════════════════════════
   193|   193|  // 3. Theme Color (16 presets)
   194|   194|  // ═══════════════════════════════════════════════════════
   195|   195|
   196|   196|  Widget _buildThemeColor(AppearanceProvider ap, Color accent) {
   197|   197|    final colors = AppearancePrefs.themeColors;
   198|   198|    return _settingCard(
   199|   199|      child: Column(
   200|   200|        crossAxisAlignment: CrossAxisAlignment.start,
   201|   201|        children: [
   202|   202|          Row(
   203|   203|            children: [
   204|   204|              Icon(Icons.color_lens, size: 22, color: ShadTheme.of(context).foreground),
   205|   205|              const SizedBox(width: 12),
   206|   206|              Expanded(
   207|   207|                child: _sectionLabel('Theme Color', 'Choose your accent color'),
   208|   208|              ),
   209|   209|              Container(
   210|   210|                width: 28, height: 28,
   211|   211|                decoration: BoxDecoration(
   212|   212|                  color: accent,
   213|   213|                  borderRadius: BorderRadius.circular(8),
   214|   214|                  boxShadow: [BoxShadow(color: accent.withAlpha(80), blurRadius: 8)],
   215|   215|                ),
   216|   216|              ),
   217|   217|            ],
   218|   218|          ),
   219|   219|          const SizedBox(height: 16),
   220|   220|          Wrap(
   221|   221|            spacing: 10,
   222|   222|            runSpacing: 10,
   223|   223|            children: List.generate(colors.length, (i) {
   224|   224|              final c = colors[i];
   225|   225|              final selected = ap.themeColorIndex == i;
   226|   226|              return GestureDetector(
   227|   227|                onTap: () => ap.update(ap.prefs.copyWith(themeColorIndex: i)),
   228|   228|                child: Tooltip(
   229|   229|                  message: c.label,
   230|   230|                  child: AnimatedContainer(
   231|   231|                    duration: const Duration(milliseconds: 200),
   232|   232|                    width: 40, height: 40,
   233|   233|                    decoration: BoxDecoration(
   234|   234|                      color: Color(c.color),
   235|   235|                      borderRadius: BorderRadius.circular(10),
   236|   236|                      border: Border.all(
   237|   237|                        color: selected ? ShadTheme.of(context).foreground : Colors.transparent,
   238|   238|                        width: selected ? 2.5 : 0,
   239|   239|                      ),
   240|   240|                      boxShadow: selected
   241|   241|                          ? [BoxShadow(color: Color(c.color).withAlpha(100), blurRadius: 8, spreadRadius: 1)]
   242|   242|                          : [],
   243|   243|                    ),
   244|   244|                    child: selected
   245|   245|                        ? const Icon(Icons.check, size: 18, color: Colors.white)
   246|   246|                        : null,
   247|   247|                  ),
   248|   248|                ),
   249|   249|              );
   250|   250|            }),
   251|   251|          ),
   252|   252|        ],
   253|   253|      ),
   254|   254|    );
   255|   255|  }
   256|   256|
   257|   257|  // ═══════════════════════════════════════════════════════
   258|   258|  // 4. Background Pattern
   259|   259|  // ═══════════════════════════════════════════════════════
   260|   260|
   261|   261|  Widget _buildBgPattern(AppearanceProvider ap, Color accent) {
   262|   262|    final patterns = AppearancePrefs.bgPatterns;
   263|   263|    return _settingCard(
   264|   264|      child: Column(
   265|   265|        crossAxisAlignment: CrossAxisAlignment.start,
   266|   266|        children: [
   267|   267|          Row(
   268|   268|            children: [
   269|   269|              Icon(Icons.texture, size: 22, color: ShadTheme.of(context).foreground),
   270|   270|              const SizedBox(width: 12),
   271|   271|              Expanded(
   272|   272|                child: _sectionLabel('Background Pattern',
   273|   273|                    ap.bgPatternIndex == 0 ? 'No pattern' : patterns[ap.bgPatternIndex].label),
   274|   274|              ),
   275|   275|            ],
   276|   276|          ),
   277|   277|          const SizedBox(height: 16),
   278|   278|          Wrap(
   279|   279|            spacing: 8,
   280|   280|            runSpacing: 8,
   281|   281|            children: List.generate(patterns.length, (i) {
   282|   282|              final selected = ap.bgPatternIndex == i;
   283|   283|              return GestureDetector(
   284|   284|                onTap: () => ap.update(ap.prefs.copyWith(bgPatternIndex: i)),
   285|   285|                child: Tooltip(
   286|   286|                  message: patterns[i].label,
   287|   287|                  child: AnimatedContainer(
   288|   288|                    duration: const Duration(milliseconds: 200),
   289|   289|                    width: 64, height: 56,
   290|   290|                    decoration: BoxDecoration(
   291|   291|                      color: ShadTheme.of(context).secondary,
   292|   292|                      borderRadius: BorderRadius.circular(8),
   293|   293|                      border: Border.all(
   294|   294|                        color: selected ? accent : ShadTheme.of(context).border,
   295|   295|                        width: selected ? 2 : 1,
   296|   296|                      ),
   297|   297|                    ),
   298|   298|                    child: _PatternPreview(
   299|   299|                      pattern: i,
   300|   300|                      color: selected ? accent : ShadTheme.of(context).mutedForeground,
   301|   301|                    ),
   302|   302|                  ),
   303|   303|                ),
   304|   304|              );
   305|   305|            }),
   306|   306|          ),
   307|   307|        ],
   308|   308|      ),
   309|   309|    );
   310|   310|  }
   311|   311|
   312|   312|  // ═══════════════════════════════════════════════════════
   313|   313|  // 5. Background Image
   314|   314|  // ═══════════════════════════════════════════════════════
   315|   315|
   316|   316|  Widget _buildBgImage(AppearanceProvider ap, Color accent, BuildContext context) {
   317|   317|    final hasImage = ap.bgImagePath != null;
   318|   318|    return _settingCard(
   319|   319|      child: Column(
   320|   320|        crossAxisAlignment: CrossAxisAlignment.start,
   321|   321|        children: [
   322|   322|          Row(
   323|   323|            children: [
   324|   324|              Icon(Icons.image, size: 22, color: ShadTheme.of(context).foreground),
   325|   325|              const SizedBox(width: 12),
   326|   326|              Expanded(
   327|   327|                child: _sectionLabel('Background Image', 'Set a custom background image'),
   328|   328|              ),
   329|   329|            ],
   330|   330|          ),
   331|   331|          const SizedBox(height: 12),
   332|   332|          if (hasImage) ...[
   333|   333|            ClipRRect(
   334|   334|              borderRadius: BorderRadius.circular(8),
   335|   335|              child: Stack(
   336|   336|                children: [
   337|   337|                  Image.file(
   338|   338|                    File(ap.bgImagePath!),
   339|   339|                    height: 140,
   340|   340|                    width: double.infinity,
   341|   341|                    fit: BoxFit.cover,
   342|   342|                    errorBuilder: (_, __, ___) => Container(
   343|   343|                      height: 140,
   344|   344|                      color: ShadTheme.of(context).secondary,
   345|   345|                      child: const Center(
   346|   346|                        child: Icon(Icons.broken_image, size: 32, color: ShadTheme.of(context).mutedForeground),
   347|   347|                      ),
   348|   348|                    ),
   349|   349|                  ),
   350|   350|                  Positioned(
   351|   351|                    right: 4, top: 4,
   352|   352|                    child: GestureDetector(
   353|   353|                      onTap: () => ap.update(ap.prefs.copyWith(clearBgImage: true)),
   354|   354|                      child: Container(
   355|   355|                        padding: const EdgeInsets.all(4),
   356|   356|                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
   357|   357|                        child: const Icon(Icons.close, size: 16, color: Colors.white),
   358|   358|                      ),
   359|   359|                    ),
   360|   360|                  ),
   361|   361|                ],
   362|   362|              ),
   363|   363|            ),
   364|   364|            const SizedBox(height: 8),
   365|   365|            Text(ap.bgImagePath!, maxLines: 1, overflow: TextOverflow.ellipsis,
   366|   366|                style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
   367|   367|            const SizedBox(height: 8),
   368|   368|          ],
   369|   369|          SizedBox(
   370|   370|            width: double.infinity,
   371|   371|            child: OutlinedButton.icon(
   372|   372|              onPressed: () => _pickBgImage(ap),
   373|   373|              icon: const Icon(Icons.folder_open, size: 18),
   374|   374|              label: Text(hasImage ? 'Change Image' : 'Choose Image'),
   375|   375|              style: OutlinedButton.styleFrom(
   376|   376|                foregroundColor: ShadTheme.of(context).foreground,
   377|   377|                side: BorderSide(color: ShadTheme.of(context).border),
   378|   378|                padding: const EdgeInsets.symmetric(vertical: 12),
   379|   379|              ),
   380|   380|            ),
   381|   381|          ),
   382|   382|        ],
   383|   383|      ),
   384|   384|    );
   385|   385|  }
   386|   386|
   387|   387|  Future<void> _pickBgImage(AppearanceProvider ap) async {
   388|   388|    try {
   389|   389|      final result = await FilePicker.pickFiles(
   390|   390|        type: FileType.image,
   391|   391|        allowMultiple: false,
   392|   392|      );
   393|   393|      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
   394|   394|        ap.update(ap.prefs.copyWith(bgImagePath: result.files.single.path));
   395|   395|      }
   396|   396|    } catch (_) {}
   397|   397|  }
   398|   398|
   399|   399|  // ═══════════════════════════════════════════════════════
   400|   400|  // 6. Startup Animation
   401|   401|  // ═══════════════════════════════════════════════════════
   402|   402|
   403|   403|  Widget _buildStartupAnim(AppearanceProvider ap, Color accent) {
   404|   404|    return _settingCard(
   405|   405|      child: Column(
   406|   406|        crossAxisAlignment: CrossAxisAlignment.start,
   407|   407|        children: [
   408|   408|          Row(
   409|   409|            children: [
   410|   410|              Icon(Icons.animation, size: 22, color: ShadTheme.of(context).foreground),
   411|   411|              const SizedBox(width: 12),
   412|   412|              Expanded(
   413|   413|                child: _sectionLabel('Startup Animation',
   414|   414|                    'Smooth transition when launching the app'),
   415|   415|              ),
   416|   416|              Switch(
   417|   417|                value: ap.startupAnimEnabled,
   418|   418|                onChanged: (v) => ap.update(ap.prefs.copyWith(startupAnimEnabled: v)),
   419|   419|                activeColor: accent,
   420|   420|              ),
   421|   421|            ],
   422|   422|          ),
   423|   423|          const SizedBox(height: 8),
   424|   424|          Container(
   425|   425|            padding: const EdgeInsets.all(12),
   426|   426|            decoration: BoxDecoration(
   427|   427|              color: ShadTheme.of(context).background,
   428|   428|              borderRadius: BorderRadius.circular(8),
   429|   429|              border: Border.all(color: ShadTheme.of(context).border),
   430|   430|            ),
   431|   431|            child: Row(
   432|   432|              children: [
   433|   433|                Icon(Icons.info_outline, size: 14,
   434|   434|                    color: ap.startupAnimEnabled ? ShadTheme.of(context).mutedForeground : Color(0xFFF59E0B)),
   435|   435|                const SizedBox(width: 8),
   436|   436|                Expanded(
   437|   437|                  child: Text(
   438|   438|                    ap.startupAnimEnabled
   439|   439|                        ? 'Startup animation will play when launching the app.'
   440|   440|                        : 'This feature is not yet implemented. Enable it now to auto-activate when available.',
   441|   441|                    style: TextStyle(fontSize: 12,
   442|   442|                        color: ap.startupAnimEnabled ? ShadTheme.of(context).mutedForeground : Color(0xFFF59E0B)),
   443|   443|                  ),
   444|   444|                ),
   445|   445|              ],
   446|   446|            ),
   447|   447|          ),
   448|   448|        ],
   449|   449|      ),
   450|   450|    );
   451|   451|  }
   452|   452|
   453|   453|  // ═══════════════════════════════════════════════════════
   454|   454|  // 7. Reset to Default
   455|   455|  // ═══════════════════════════════════════════════════════
   456|   456|
   457|   457|  Widget _buildResetSection(AppearanceProvider ap, Color accent, BuildContext ctx) {
   458|   458|    return _settingCard(
   459|   459|      child: Row(
   460|   460|        children: [
   461|   461|          Icon(Icons.restore, size: 22, color: ShadTheme.of(context).foreground),
   462|   462|          const SizedBox(width: 12),
   463|   463|          Expanded(
   464|   464|            child: _sectionLabel('Default', 'Restore all appearance settings to factory defaults'),
   465|   465|          ),
   466|   466|          OutlinedButton.icon(
   467|   467|            onPressed: () => _confirmReset(ap, ctx),
   468|   468|            icon: const Icon(Icons.refresh, size: 16),
   469|   469|            label: const Text('Reset'),
   470|   470|            style: OutlinedButton.styleFrom(
   471|   471|              foregroundColor: ShadTheme.of(context).destructive,
   472|   472|              side: BorderSide(color: ShadTheme.of(context).destructive),
   473|   473|              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
   474|   474|            ),
   475|   475|          ),
   476|   476|        ],
   477|   477|      ),
   478|   478|    );
   479|   479|  }
   480|   480|
   481|   481|  void _confirmReset(AppearanceProvider ap, BuildContext ctx) {
   482|   482|    showDialog(
   483|   483|      context: ctx,
   484|   484|      builder: (dCtx) => AlertDialog(
   485|   485|        backgroundColor: ShadTheme.of(context).card,
   486|   486|        title: Text('Reset to Default', style: TextStyle(color: ShadTheme.of(context).foreground)),
   487|   487|        content: const Text(
   488|   488|          'This will restore all appearance settings to their factory defaults.',
   489|   489|          style: TextStyle(color: ShadTheme.of(context).mutedForeground),
   490|   490|        ),
   491|   491|        actions: [
   492|   492|          TextButton(
   493|   493|            onPressed: () => Navigator.pop(dCtx),
   494|   494|            child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
   495|   495|          ),
   496|   496|          TextButton(
   497|   497|            onPressed: () {
   498|   498|              ap.resetToDefaults();
   499|   499|              Navigator.pop(dCtx);
   500|   500|            },
   501|   501|            child: Text('Reset All', style: TextStyle(color: ShadTheme.of(context).destructive)),
   502|   502|          ),
   503|   503|        ],
   504|   504|      ),
   505|   505|    );
   506|   506|  }
   507|   507|}
   508|   508|
   509|   509|// ══════════════════════════════════════════════════════════
   510|   510|// Pattern Preview painter
   511|   511|// ══════════════════════════════════════════════════════════
   512|   512|
   513|   513|class _PatternPreview extends StatelessWidget {
   514|   514|  final int pattern;
   515|   515|  final Color color;
   516|   516|
   517|   517|  const _PatternPreview({required this.pattern, required this.color});
   518|   518|
   519|   519|  @override
   520|   520|  Widget build(BuildContext context) {
   521|   521|    if (pattern == 0) return const SizedBox.shrink();
   522|   522|    return ClipRRect(
   523|   523|      borderRadius: BorderRadius.circular(6),
   524|   524|      child: CustomPaint(
   525|   525|        painter: _PreviewPainter(pattern: pattern, color: color),
   526|   526|        size: const Size(64, 56),
   527|   527|      ),
   528|   528|    );
   529|   529|  }
   530|   530|}
   531|   531|
   532|   532|class _PreviewPainter extends CustomPainter {
   533|   533|  final int pattern;
   534|   534|  final Color color;
   535|   535|
   536|   536|  _PreviewPainter({required this.pattern, required this.color});
   537|   537|
   538|   538|  @override
   539|   539|  void paint(Canvas canvas, Size size) {
   540|   540|    final paint = Paint()
   541|   541|      ..color = color
   542|   542|      ..style = PaintingStyle.stroke
   543|   543|      ..strokeWidth = 1.2;
   544|   544|    final step = 8.0;
   545|   545|    final w = size.width;
   546|   546|    final h = size.height;
   547|   547|
   548|   548|    switch (pattern) {
   549|   549|      case 1: // Dots
   550|   550|        final fill = Paint()..color = color.withAlpha(30);
   551|   551|        for (double x = step; x < w; x += step * 2) {
   552|   552|          for (double y = step; y < h; y += step * 2) {
   553|   553|            canvas.drawCircle(Offset(x, y), 1.5, fill);
   554|   554|            canvas.drawCircle(Offset(x, y), 1.5, paint);
   555|   555|          }
   556|   556|        }
   557|   557|        break;
   558|   558|      case 2: // Grid
   559|   559|        for (double x = 0; x <= w; x += step) canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
   560|   560|        for (double y = 0; y <= h; y += step) canvas.drawLine(Offset(0, y), Offset(w, y), paint);
   561|   561|        break;
   562|   562|      case 3: // Diagonal
   563|   563|        final d = step * 1.5;
   564|   564|        for (double x = -h; x < w + h; x += d) canvas.drawLine(Offset(x, 0), Offset(x + h, h), paint);
   565|   565|        break;
   566|   566|      case 4: // Lines
   567|   567|        for (double y = step; y < h; y += step * 1.5) canvas.drawLine(Offset(0, y), Offset(w, y), paint);
   568|   568|        break;
   569|   569|      case 5: // Crosshatch
   570|   570|        final d2 = step * 1.5;
   571|   571|        final p2 = Paint()..color = color.withAlpha(80)..style = PaintingStyle.stroke..strokeWidth = 1.2;
   572|   572|        for (double x = -h; x < w + h; x += d2) canvas.drawLine(Offset(x, 0), Offset(x + h, h), paint);
   573|   573|        for (double x = 0; x < w + h * 2; x += d2) canvas.drawLine(Offset(x, 0), Offset(x - h, h), p2);
   574|   574|        break;
   575|   575|      case 6: // Zigzag
   576|   576|        final d3 = step * 1.5;
   577|   577|        for (double y = -d3; y < h + d3 * 3; y += d3 * 3) {
   578|   578|          final path = Path();
   579|   579|          var up = true;
   580|   580|          for (double x = 0; x <= w; x += d3 * 1.5) {
   581|   581|            if (x == 0) { path.moveTo(x, up ? y : y + d3); }
   582|   582|            else { path.lineTo(x, up ? y : y + d3); }
   583|   583|            up = !up;
   584|   584|          }
   585|   585|          canvas.drawPath(path, paint);
   586|   586|        }
   587|   587|        break;
   588|   588|      case 7: // Waves
   589|   589|        final d4 = step * 2;
   590|   590|        for (double y = d4 / 2; y < h + d4; y += d4) {
   591|   591|          final path = Path();
   592|   592|          path.moveTo(0, y);
   593|   593|          for (double x = 0; x <= w; x += 4) path.lineTo(x, y + math.sin(x / 8) * d4 / 3);
   594|   594|          canvas.drawPath(path, paint);
   595|   595|        }
   596|   596|        break;
   597|   597|      case 8: // Hexagon
   598|   598|        _drawHex(canvas, w, h, step, paint);
   599|   599|        break;
   600|   600|      case 9: // Circles
   601|   601|        final r = step * 0.6;
   602|   602|        final cf = Paint()..color = color.withAlpha(25)..style = PaintingStyle.fill;
   603|   603|        for (double x = step; x < w + step; x += step * 2.5) {
   604|   604|          for (double y = step; y < h + step; y += step * 2.5) {
   605|   605|            canvas.drawCircle(Offset(x, y), r, cf);
   606|   606|            canvas.drawCircle(Offset(x, y), r, paint);
   607|   607|          }
   608|   608|        }
   609|   609|        break;
   610|   610|      case 10: // Triangles
   611|   611|        _drawTri(canvas, w, h, step, paint);
   612|   612|        break;
   613|   613|      case 11: // Diamonds
   614|   614|        _drawDia(canvas, w, h, step, paint);
   615|   615|        break;
   616|   616|      case 12: // Chess
   617|   617|        final d5 = step * 2;
   618|   618|        final cf2 = Paint()..style = PaintingStyle.fill;
   619|   619|        for (double x = 0; x < w; x += d5) {
   620|   620|          for (double y = 0; y < h; y += d5) {
   621|   621|            if (((x / d5).round() + (y / d5).round()).isEven) {
   622|   622|              cf2.color = color.withAlpha(30);
   623|   623|              canvas.drawRect(Rect.fromLTWH(x, y, d5, d5), cf2);
   624|   624|            }
   625|   625|          }
   626|   626|        }
   627|   627|        break;
   628|   628|    }
   629|   629|  }
   630|   630|
   631|   631|  void _drawHex(Canvas c, double w, double h, double step, Paint p) {
   632|   632|    final r = step * 0.6;
   633|   633|    final rows = (h / r / 1.5).ceil() + 2;
   634|   634|    final cols = (w / r / math.sqrt(3)).ceil() + 2;
   635|   635|    final fill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
   636|   636|    for (int row = 0; row < rows; row++) {
   637|   637|      for (int col = 0; col < cols; col++) {
   638|   638|        final cx = col * r * math.sqrt(3) + (row.isOdd ? r * math.sqrt(3) / 2 : 0);
   639|   639|        final cy = row * r * 1.5;
   640|   640|        final path = Path();
   641|   641|        for (int i = 0; i < 6; i++) {
   642|   642|          final angle = i * math.pi / 3 - math.pi / 6;
   643|   643|          final pt = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
   644|   644|          if (i == 0) { path.moveTo(pt.dx, pt.dy); }
   645|   645|          else { path.lineTo(pt.dx, pt.dy); }
   646|   646|        }
   647|   647|        path.close();
   648|   648|        c.drawPath(path, fill);
   649|   649|        c.drawPath(path, p);
   650|   650|      }
   651|   651|    }
   652|   652|  }
   653|   653|
   654|   654|  void _drawTri(Canvas c, double w, double h, double step, Paint p) {
   655|   655|    final d = step * 2;
   656|   656|    final fill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
   657|   657|    for (double x = 0; x < w + d; x += d) {
   658|   658|      for (double y = 0; y < h + d; y += d) {
   659|   659|        final even = ((x / d).round() + (y / d).round()).isEven;
   660|   660|        final path = Path();
   661|   661|        if (even) {
   662|   662|          path.moveTo(x, y + d); path.lineTo(x + d / 2, y); path.lineTo(x + d, y + d);
   663|   663|        } else {
   664|   664|          path.moveTo(x, y); path.lineTo(x + d / 2, y + d); path.lineTo(x + d, y);
   665|   665|        }
   666|   666|        path.close();
   667|   667|        c.drawPath(path, fill);
   668|   668|        c.drawPath(path, p);
   669|   669|      }
   670|   670|    }
   671|   671|  }
   672|   672|
   673|   673|  void _drawDia(Canvas c, double w, double h, double step, Paint p) {
   674|   674|    final d = step * 2;
   675|   675|    final fill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
   676|   676|    for (double x = -d / 2; x < w + d; x += d) {
   677|   677|      for (double y = -d / 2; y < h + d; y += d) {
   678|   678|        final path = Path();
   679|   679|        path.moveTo(x + d / 2, y); path.lineTo(x + d, y + d / 2);
   680|   680|        path.lineTo(x + d / 2, y + d); path.lineTo(x, y + d / 2);
   681|   681|        path.close();
   682|   682|        c.drawPath(path, fill);
   683|   683|        c.drawPath(path, p);
   684|   684|      }
   685|   685|    }
   686|   686|  }
   687|   687|
   688|   688|  @override
   689|   689|  bool shouldRepaint(covariant _PreviewPainter old) =>
   690|   690|      old.pattern != pattern || old.color != color;
   691|   691|}
   692|   692|