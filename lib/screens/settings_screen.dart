     1|     1|import 'package:flutter/material.dart';
     2|     2|import 'package:provider/provider.dart';
     3|     3|import '../app.dart';
     4|     4|import '../providers/settings_provider.dart';
     5|     5|import '../providers/chat_provider.dart';
     6|     6|import '../providers/multi_agent_provider.dart';
     7|     7|
     8|     8|class SettingsScreen extends StatefulWidget {
     9|     9|  const SettingsScreen({super.key});
    10|    10|
    11|    11|  @override
    12|    12|  State<SettingsScreen> createState() => _SettingsScreenState();
    13|    13|}
    14|    14|
    15|    15|class _SettingsScreenState extends State<SettingsScreen> {
    16|    16|  late TextEditingController _serverCtrl;
    17|    17|  late TextEditingController _waHostCtrl;
    18|    18|  late TextEditingController _waDeviceNameCtrl;
    19|    19|  late TextEditingController _waTopicCtrl;
    20|    20|  bool _waEnabled = false;
    21|    21|  int _waPort = 9090;
    22|    22|  int _lanTab = 0; // 0=Join, 1=Create
    23|    23|
    24|    24|  @override
    25|    25|  void initState() {
    26|    26|    super.initState();
    27|    27|    _serverCtrl = TextEditingController();
    28|    28|    _waHostCtrl = TextEditingController(text: '127.0.0.1');
    29|    29|    _waDeviceNameCtrl = TextEditingController(text: 'AI VTuber');
    30|    30|    _waTopicCtrl = TextEditingController();
    31|    31|  }
    32|    32|
    33|    33|  @override
    34|    34|  void dispose() {
    35|    35|    _serverCtrl.dispose();
    36|    36|    _waHostCtrl.dispose();
    37|    37|    _waDeviceNameCtrl.dispose();
    38|    38|    _waTopicCtrl.dispose();
    39|    39|    super.dispose();
    40|    40|  }
    41|    41|
    42|    42|  @override
    43|    43|  Widget build(BuildContext context) {
    44|    44|    return Consumer3<SettingsProvider, ChatProvider, AgentManager>(
    45|    45|      builder: (context, sp, chat, wa, _) {
    46|    46|        // Sync text controllers with settings on first load
    47|    47|        if (_serverCtrl.text.isEmpty) {
    48|    48|          _serverCtrl.text = sp.settings.backendUrl;
    49|    49|        }
    50|    50|
    51|    51|        return SingleChildScrollView(
    52|    52|          padding: const EdgeInsets.all(24),
    53|    53|          child: Column(
    54|    54|            crossAxisAlignment: CrossAxisAlignment.start,
    55|    55|            children: [
    56|    56|              const Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
    57|    57|              const SizedBox(height: 24),
    58|    58|
    59|    59|              // ─── WenzAgent Multi-Agent LAN ──────────────────
    60|    60|              _sectionHeader('WenzAgent Multi-Agent Network'),
    61|    61|              const SizedBox(height: 8),
    62|    62|              _buildLanConfig(sp, wa),
    63|    63|
    64|    64|              const SizedBox(height: 24),
    65|    65|
    66|    66|              // ─── Server Connection ────────────────────────
    67|    67|              _sectionHeader('Server Connection'),
    68|    68|              const SizedBox(height: 8),
    69|    69|              TextField(
    70|    70|                controller: _serverCtrl,
    71|    71|                decoration: const InputDecoration(
    72|    72|                  labelText: 'Backend URL',
    73|    73|                  hintText: 'D:\\AiVtuber_Agent_profile',
    74|    74|                  border: OutlineInputBorder(),
    75|    75|                  filled: true,
    76|    76|                  fillColor: ShadTheme.of(context).secondary,
    77|    77|                ),
    78|    78|                style: const TextStyle(fontSize: 13),
    79|    79|                onChanged: (v) => sp.updateBackendUrl(v),
    80|    80|              ),
    81|    81|              const SizedBox(height: 12),
    82|    82|              const Row(
    83|    83|                children: [
    84|    84|                  Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
    85|    85|                  SizedBox(width: 6),
    86|    86|                  Text('Self-contained — no external backend needed',
    87|    87|                      style: TextStyle(color: Color(0xFF4CAF50), fontSize: 13)),
    88|    88|                ],
    89|    89|              ),
    90|    90|              const SizedBox(height: 24),
    91|    91|
    92|    92|              // ─── About ────────────────────────────────────
    93|    93|              _sectionHeader('About'),
    94|    94|              const SizedBox(height: 8),
    95|    95|              Container(
    96|    96|                padding: const EdgeInsets.all(16),
    97|    97|                decoration: BoxDecoration(
    98|    98|                  color: ShadTheme.of(context).card,
    99|    99|                  borderRadius: BorderRadius.circular(10),
   100|   100|                  border: Border.all(color: ShadTheme.of(context).border),
   101|   101|                ),
   102|   102|                child: const Column(
   103|   103|                  crossAxisAlignment: CrossAxisAlignment.start,
   104|   104|                  children: [
   105|   105|                    Text('AI VTuber Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
   106|   106|                    SizedBox(height: 4),
   107|   107|                    Text('v1.0.0 — Flutter Desktop App',
   108|   108|                        style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
   109|   109|                    SizedBox(height: 12),
   110|   110|                    Text('Features:',
   111|   111|                        style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 14)),
   112|   112|                    SizedBox(height: 4),
   113|   113|                    Text('• Streaming LLM chat with character system prompt'),
   114|   114|                    Text('• TTS voice synthesis via edge-tts'),
   115|   115|                    Text('• Live2D / VRM character display (WIP)'),
   116|   116|                    Text('• Screenshot vision + OCR'),
   117|   117|                    Text('• Local keyword-based memory'),
   118|   118|                    Text('• Session history management'),
   119|   119|                    Text('• WenzAgent multi-agent LAN networking'),
   120|   120|                    SizedBox(height: 12),
   121|   121|                    Text('Backend: Self-contained Dart services',
   122|   122|                        style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
   123|   123|                    Text('UI Framework: Flutter 3.x + Provider',
   124|   124|                        style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
   125|   125|                  ],
   126|   126|                ),
   127|   127|              ),
   128|   128|
   129|   129|              const SizedBox(height: 24),
   130|   130|              _sectionHeader('Data & Storage'),
   131|   131|              const SizedBox(height: 8),
   132|   132|              OutlinedButton.icon(
   133|   133|                onPressed: () {},
   134|   134|                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFCF6679)),
   135|   135|                label: const Text('Clear Local Cache', style: TextStyle(color: Color(0xFFCF6679))),
   136|   136|              ),
   137|   137|            ],
   138|   138|          ),
   139|   139|        );
   140|   140|      },
   141|   141|    );
   142|   142|  }
   143|   143|
   144|   144|  Widget _sectionHeader(String title) {
   145|   145|    return Text(title, style: const TextStyle(
   146|   146|      fontSize: 14,
   147|   147|      fontWeight: FontWeight.w600,
   148|   148|      color: Color(0xFF4CAF50),
   149|   149|    ));
   150|   150|  }
   151|   151|
   152|   152|  Widget _miniButton(String label, VoidCallback onTap) {
   153|   153|    return GestureDetector(
   154|   154|      onTap: onTap,
   155|   155|      child: Container(
   156|   156|        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
   157|   157|        decoration: BoxDecoration(
   158|   158|          color: ShadTheme.of(context).secondary,
   159|   159|          borderRadius: BorderRadius.circular(4),
   160|   160|          border: Border.all(color: ShadTheme.of(context).border),
   161|   161|        ),
   162|   162|        child: Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground)),
   163|   163|      ),
   164|   164|    );
   165|   165|  }
   166|   166|
   167|   167|  // ─── LAN Config Card ──────────────────────────────────────
   168|   168|
   169|   169|  Widget _buildLanConfig(SettingsProvider sp, AgentManager wa) {
   170|   170|    return Container(
   171|   171|      padding: const EdgeInsets.all(16),
   172|   172|      decoration: BoxDecoration(
   173|   173|        color: ShadTheme.of(context).card,
   174|   174|        borderRadius: BorderRadius.circular(10),
   175|   175|        border: Border.all(color: ShadTheme.of(context).border),
   176|   176|      ),
   177|   177|      child: Column(
   178|   178|        crossAxisAlignment: CrossAxisAlignment.start,
   179|   179|        children: [
   180|   180|          // Enable toggle
   181|   181|          SwitchListTile(
   182|   182|            contentPadding: EdgeInsets.zero,
   183|   183|            title: const Text('Enable multi-agent LAN', style: TextStyle(fontSize: 14)),
   184|   184|            subtitle: const Text(
   185|   185|              'Connect to a WenzAgent LAN server for multi-device AI collaboration',
   186|   186|              style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground),
   187|   187|            ),
   188|   188|            value: sp.settings.wenzagentEnabled,
   189|   189|            onChanged: (v) {
   190|   190|              sp.settings.wenzagentEnabled = v;
   191|   191|              sp.saveSettings(sp.settings);
   192|   192|              setState(() {});
   193|   193|            },
   194|   194|          ),
   195|   195|          if (sp.settings.wenzagentEnabled) ...[
   196|   196|            const SizedBox(height: 12),
   197|   197|            // Join / Create tabs
   198|   198|            Row(
   199|   199|              children: [
   200|   200|                _lanTabButton('Join LAN', 0),
   201|   201|                const SizedBox(width: 8),
   202|   202|                _lanTabButton('Create LAN', 1),
   203|   203|              ],
   204|   204|            ),
   205|   205|            const SizedBox(height: 12),
   206|   206|            // Host IP
   207|   207|            TextField(
   208|   208|              controller: _waHostCtrl,
   209|   209|              decoration: InputDecoration(
   210|   210|                labelText: _lanTab == 0 ? 'Server IP Address' : 'Bind Address',
   211|   211|                hintText: _lanTab == 0 ? '192.168.1.100' : '0.0.0.0',
   212|   212|                border: const OutlineInputBorder(),
   213|   213|                filled: true,
   214|   214|                fillColor: ShadTheme.of(context).secondary,
   215|   215|              ),
   216|   216|              style: const TextStyle(fontSize: 13),
   217|   217|              onChanged: (v) {
   218|   218|                sp.settings.wenzagentHost = v;
   219|   219|                sp.saveSettings(sp.settings);
   220|   220|              },
   221|   221|            ),
   222|   222|            const SizedBox(height: 8),
   223|   223|            // Port
   224|   224|            TextField(
   225|   225|              controller: TextEditingController(text: '${sp.settings.wenzagentPort}'),
   226|   226|              decoration: const InputDecoration(
   227|   227|                labelText: 'Port',
   228|   228|                hintText: '9090',
   229|   229|                border: OutlineInputBorder(),
   230|   230|                filled: true,
   231|   231|                fillColor: ShadTheme.of(context).secondary,
   232|   232|                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
   233|   233|              ),
   234|   234|              keyboardType: TextInputType.number,
   235|   235|              style: const TextStyle(fontSize: 13),
   236|   236|              onChanged: (v) {
   237|   237|                sp.settings.wenzagentPort = int.tryParse(v) ?? 9090;
   238|   238|                sp.saveSettings(sp.settings);
   239|   239|              },
   240|   240|            ),
   241|   241|            const SizedBox(height: 8),
   242|   242|            // Device Name
   243|   243|            TextField(
   244|   244|              controller: _waDeviceNameCtrl,
   245|   245|              decoration: const InputDecoration(
   246|   246|                labelText: 'Device Name',
   247|   247|                hintText: 'AI VTuber',
   248|   248|                border: OutlineInputBorder(),
   249|   249|                filled: true,
   250|   250|                fillColor: ShadTheme.of(context).secondary,
   251|   251|              ),
   252|   252|              style: const TextStyle(fontSize: 13),
   253|   253|              onChanged: (v) {
   254|   254|                sp.settings.wenzagentDeviceName = v;
   255|   255|                sp.saveSettings(sp.settings);
   256|   256|              },
   257|   257|            ),
   258|   258|            const SizedBox(height: 8),
   259|   259|            // Topic
   260|   260|            TextField(
   261|   261|              controller: _waTopicCtrl,
   262|   262|              decoration: const InputDecoration(
   263|   263|                labelText: 'Topic (optional)',
   264|   264|                hintText: 'Group identifier',
   265|   265|                border: OutlineInputBorder(),
   266|   266|                filled: true,
   267|   267|                fillColor: ShadTheme.of(context).secondary,
   268|   268|              ),
   269|   269|              style: const TextStyle(fontSize: 13),
   270|   270|              onChanged: (v) {
   271|   271|                sp.settings.wenzagentTopic = v;
   272|   272|                sp.saveSettings(sp.settings);
   273|   273|              },
   274|   274|            ),
   275|   275|            const SizedBox(height: 14),
   276|   276|            // Connection status + button
   277|   277|            Row(
   278|   278|              children: [
   279|   279|                Icon(
   280|   280|                  wa.connected ? Icons.check_circle : Icons.cancel,
   281|   281|                  size: 16,
   282|   282|                  color: wa.connected ? const Color(0xFF4CAF50) : const Color(0xFFCF6679),
   283|   283|                ),
   284|   284|                const SizedBox(width: 6),
   285|   285|                Expanded(
   286|   286|                  child: Text(
   287|   287|                    wa.connected ? 'Connected to LAN' : wa.statusMessage,
   288|   288|                    style: TextStyle(
   289|   289|                      color: wa.connected ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground,
   290|   290|                      fontSize: 13,
   291|   291|                    ),
   292|   292|                  ),
   293|   293|                ),
   294|   294|                if (wa.connected)
   295|   295|                  _miniButton('Disconnect', () => wa.disconnect())
   296|   296|                else
   297|   297|                  _miniButton(_lanTab == 0 ? 'Join' : 'Start', () {
   298|   298|                    if (_lanTab == 0) {
   299|   299|                      wa.joinLAN(host: sp.settings.wenzagentHost, port: sp.settings.wenzagentPort);
   300|   300|                    } else {
   301|   301|                      wa.createLAN(host: sp.settings.wenzagentHost, port: sp.settings.wenzagentPort);
   302|   302|                    }
   303|   303|                  }),
   304|   304|              ],
   305|   305|            ),
   306|   306|          ],
   307|   307|        ],
   308|   308|      ),
   309|   309|    );
   310|   310|  }
   311|   311|
   312|   312|  Widget _lanTabButton(String label, int index) {
   313|   313|    final active = _lanTab == index;
   314|   314|    return GestureDetector(
   315|   315|      onTap: () => setState(() => _lanTab = index),
   316|   316|      child: Container(
   317|   317|        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
   318|   318|        decoration: BoxDecoration(
   319|   319|          color: active ? ShadTheme.of(context).sidebarPrimary : ShadTheme.of(context).secondary,
   320|   320|          borderRadius: BorderRadius.circular(6),
   321|   321|        ),
   322|   322|        child: Text(
   323|   323|          label,
   324|   324|          style: TextStyle(
   325|   325|            fontSize: 12,
   326|   326|            fontWeight: FontWeight.w500,
   327|   327|            color: active ? Colors.white : ShadTheme.of(context).mutedForeground,
   328|   328|          ),
   329|   329|        ),
   330|   330|      ),
   331|   331|    );
   332|   332|  }
   333|   333|}
   334|   334|