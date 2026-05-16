     1|import 'package:flutter/material.dart';
     2|import 'package:provider/provider.dart';
     3|import '../app.dart';
     4|import '../models/settings.dart';
     5|import '../providers/settings_provider.dart';
     6|
     7|/// TTS Settings page — matches LocalAIVtuber2's TTSPage style.
     8|class TTSScreen extends StatefulWidget {
     9|  const TTSScreen({super.key});
    10|
    11|  @override
    12|  State<TTSScreen> createState() => _TTSScreenState();
    13|}
    14|
    15|class _TTSScreenState extends State<TTSScreen> {
    16|  void _update(SettingsProvider sp, AppSettings s, {
    17|    String? ttsProvider,
    18|    bool? useRvc,
    19|    int? rvcF0UpKey,
    20|  }) {
    21|    sp.saveSettings(s.copyWith(
    22|      ttsProvider: ttsProvider,
    23|      useRvc: useRvc,
    24|      rvcF0UpKey: rvcF0UpKey,
    25|    ));
    26|  }
    27|
    28|  @override
    29|  Widget build(BuildContext context) {
    30|    return Consumer<SettingsProvider>(
    31|      builder: (context, sp, _) {
    32|        final s = sp.settings;
    33|
    34|        return SingleChildScrollView(
    35|          padding: const EdgeInsets.only(top: 40, left: 48, right: 48, bottom: 40),
    36|          child: ConstrainedBox(
    37|            constraints: const BoxConstraints(maxWidth: 640),
    38|            child: Column(
    39|              crossAxisAlignment: CrossAxisAlignment.start,
    40|              children: [
    41|                const Text(
    42|                  'TTS Settings',
    43|                  style: TextStyle(
    44|                    fontSize: 28,
    45|                    fontWeight: FontWeight.bold,
    46|                    color: ShadTheme.of(context).foreground,
    47|                  ),
    48|                ),
    49|                const SizedBox(height: 6),
    50|                const Text(
    51|                  'Configure text-to-speech engine and voice settings',
    52|                  style: TextStyle(
    53|                    fontSize: 14,
    54|                    color: ShadTheme.of(context).mutedForeground,
    55|                  ),
    56|                ),
    57|                const SizedBox(height: 28),
    58|
    59|                // Provider selection card
    60|                _shadCard(
    61|                  title: 'TTS Provider Selection',
    62|                  icon: Icons.settings,
    63|                  child: Column(
    64|                    children: [
    65|                      Row(
    66|                        children: [
    67|                          _providerChip(
    68|                            'GPT-SoVITS',
    69|                            s.ttsProvider == 'gpt-sovits',
    70|                            () => _update(sp, s, ttsProvider: 'gpt-sovits'),
    71|                          ),
    72|                          const SizedBox(width: 8),
    73|                          _providerChip(
    74|                            'RVC',
    75|                            s.ttsProvider == 'rvc',
    76|                            () => _update(sp, s, ttsProvider: 'rvc'),
    77|                          ),
    78|                        ],
    79|                      ),
    80|                    ],
    81|                  ),
    82|                ),
    83|                const SizedBox(height: 16),
    84|
    85|                // Voice selection card
    86|                _shadCard(
    87|                  title: 'Active Voice',
    88|                  icon: Icons.record_voice_over,
    89|                  child: Container(
    90|                    width: double.infinity,
    91|                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    92|                    decoration: BoxDecoration(
    93|                      color: ShadTheme.of(context).secondary,
    94|                      borderRadius: BorderRadius.circular(6),
    95|                      border: Border.all(color: ShadTheme.of(context).input),
    96|                    ),
    97|                    child: Text(
    98|                      s.ttsVoice.isEmpty ? 'No voice selected' : s.ttsVoice,
    99|                      style: const TextStyle(
   100|                        fontSize: 14,
   101|                        color: ShadTheme.of(context).foreground,
   102|                      ),
   103|                    ),
   104|                  ),
   105|                ),
   106|                const SizedBox(height: 16),
   107|
   108|                // RVC settings
   109|                if (s.ttsProvider == 'rvc') ...[
   110|                  _shadCard(
   111|                    title: 'RVC Settings',
   112|                    icon: Icons.tune,
   113|                    child: Column(
   114|                      crossAxisAlignment: CrossAxisAlignment.start,
   115|                      children: [
   116|                        // Enable RVC switch
   117|                        Row(
   118|                          children: [
   119|                            SizedBox(
   120|                              height: 24,
   121|                              child: Switch(
   122|                                value: s.useRvc,
   123|                                onChanged: (v) => _update(sp, s, useRvc: v),
   124|                                activeColor: ShadTheme.of(context).primary,
   125|                              ),
   126|                            ),
   127|                            const SizedBox(width: 10),
   128|                            const Text(
   129|                              'Enable RVC',
   130|                              style: TextStyle(
   131|                                fontSize: 14,
   132|                                color: ShadTheme.of(context).foreground,
   133|                              ),
   134|                            ),
   135|                          ],
   136|                        ),
   137|                        const SizedBox(height: 16),
   138|
   139|                        // Pitch shift slider
   140|                        Row(
   141|                          children: [
   142|                            const Text(
   143|                              'Pitch Shift (semitones): ',
   144|                              style: TextStyle(
   145|                                fontSize: 13,
   146|                                color: ShadTheme.of(context).mutedForeground,
   147|                              ),
   148|                            ),
   149|                            Text(
   150|                              '${s.rvcF0UpKey}',
   151|                              style: const TextStyle(
   152|                                fontSize: 14,
   153|                                fontWeight: FontWeight.w600,
   154|                                color: ShadTheme.of(context).foreground,
   155|                              ),
   156|                            ),
   157|                          ],
   158|                        ),
   159|                        Slider(
   160|                          value: s.rvcF0UpKey.toDouble(),
   161|                          min: -12,
   162|                          max: 12,
   163|                          divisions: 24,
   164|                          activeColor: ShadTheme.of(context).primary,
   165|                          inactiveColor: ShadTheme.of(context).secondary,
   166|                          onChanged: (v) =>
   167|                              _update(sp, s, rvcF0UpKey: v.round()),
   168|                        ),
   169|                      ],
   170|                    ),
   171|                  ),
   172|                ],
   173|
   174|                // Upload voice
   175|                const SizedBox(height: 12),
   176|                SizedBox(
   177|                  width: double.infinity,
   178|                  child: OutlinedButton.icon(
   179|                    onPressed: () {},
   180|                    icon: const Icon(Icons.upload_file, size: 16),
   181|                    label: const Text('Upload Voice Model'),
   182|                  ),
   183|                ),
   184|              ],
   185|            ),
   186|          ),
   187|        );
   188|      },
   189|    );
   190|  }
   191|
   192|  Widget _providerChip(String name, bool selected, VoidCallback onTap) {
   193|    return Expanded(
   194|      child: GestureDetector(
   195|        onTap: onTap,
   196|        child: Container(
   197|          padding: const EdgeInsets.symmetric(vertical: 14),
   198|          decoration: BoxDecoration(
   199|            color: selected ? ShadTheme.of(context).primary.withAlpha(25) : ShadTheme.of(context).secondary,
   200|            borderRadius: BorderRadius.circular(8),
   201|            border: Border.all(
   202|              color: selected ? ShadTheme.of(context).primary : ShadTheme.of(context).input,
   203|              width: selected ? 1.5 : 1,
   204|            ),
   205|          ),
   206|          child: Center(
   207|            child: Text(
   208|              name,
   209|              style: TextStyle(
   210|                fontSize: 14,
   211|                color: selected ? ShadTheme.of(context).foreground : ShadTheme.of(context).mutedForeground,
   212|                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
   213|              ),
   214|            ),
   215|          ),
   216|        ),
   217|      ),
   218|    );
   219|  }
   220|
   221|  Widget _shadCard({
   222|    required String title,
   223|    required IconData icon,
   224|    required Widget child,
   225|  }) {
   226|    return Container(
   227|      width: double.infinity,
   228|      padding: const EdgeInsets.all(16),
   229|      decoration: BoxDecoration(
   230|        color: ShadTheme.of(context).card,
   231|        borderRadius: BorderRadius.circular(8),
   232|        border: Border.all(color: ShadTheme.of(context).border),
   233|        boxShadow: const [
   234|          BoxShadow(
   235|            color: Color(0x08000000),
   236|            blurRadius: 2,
   237|            offset: Offset(0, 1),
   238|          ),
   239|        ],
   240|      ),
   241|      child: Column(
   242|        crossAxisAlignment: CrossAxisAlignment.start,
   243|        children: [
   244|          Row(
   245|            children: [
   246|              Icon(icon, size: 16, color: ShadTheme.of(context).foreground),
   247|              const SizedBox(width: 8),
   248|              Text(
   249|                title,
   250|                style: const TextStyle(
   251|                  fontSize: 15,
   252|                  fontWeight: FontWeight.w600,
   253|                  color: ShadTheme.of(context).foreground,
   254|                ),
   255|              ),
   256|            ],
   257|          ),
   258|          const SizedBox(height: 14),
   259|          child,
   260|        ],
   261|      ),
   262|    );
   263|  }
   264|}
   265|