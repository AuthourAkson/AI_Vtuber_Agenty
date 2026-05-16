     1|     1|import 'package:flutter/material.dart';
     2|     2|import 'package:provider/provider.dart';
     3|     3|import '../app.dart';
     4|     4|import '../providers/chat_provider.dart';
     5|     5|import '../providers/settings_provider.dart';
     6|     6|import '../widgets/chat_bubble.dart';
     7|     7|import '../widgets/chat_input.dart';
     8|     8|import '../widgets/llm_monitor.dart';
     9|     9|
    10|    10|/// Chat page — matches LocalAIVtuber2's llmPage.tsx + chatbox.tsx layout.
    11|    11|class ChatScreen extends StatefulWidget {
    12|    12|  const ChatScreen({super.key});
    13|    13|
    14|    14|  @override
    15|    15|  State<ChatScreen> createState() => _ChatScreenState();
    16|    16|}
    17|    17|
    18|    18|class _ChatScreenState extends State<ChatScreen> {
    19|    19|  final _scrollController = ScrollController();
    20|    20|  bool _autoScroll = true;
    21|    21|  bool _sessionPanelOpen = false;
    22|    22|  bool _settingsPanelOpen = false;
    23|    23|
    24|    24|  @override
    25|    25|  void dispose() {
    26|    26|    _scrollController.dispose();
    27|    27|    super.dispose();
    28|    28|  }
    29|    29|
    30|    30|  void _scrollToBottom() {
    31|    31|    if (_autoScroll && _scrollController.hasClients) {
    32|    32|      WidgetsBinding.instance.addPostFrameCallback((_) {
    33|    33|        if (_scrollController.hasClients) {
    34|    34|          _scrollController.animateTo(
    35|    35|            _scrollController.position.maxScrollExtent,
    36|    36|            duration: const Duration(milliseconds: 200),
    37|    37|            curve: Curves.easeOut,
    38|    38|          );
    39|    39|        }
    40|    40|      });
    41|    41|    }
    42|    42|  }
    43|    43|
    44|    44|  @override
    45|    45|  Widget build(BuildContext context) {
    46|    46|    return Consumer2<ChatProvider, SettingsProvider>(
    47|    47|      builder: (context, chat, sp, _) {
    48|    48|        _scrollToBottom();
    49|    49|        final showMonitor = sp.settings.showMonitor;
    50|    50|
    51|    51|        return ClipRect(
    52|    52|          child: Stack(
    53|    53|            children: [
    54|    54|              // ── Main content ──
    55|    55|              Column(
    56|    56|                children: [
    57|    57|                  _buildHeader(chat),
    58|    58|                  Expanded(
    59|    59|                    child: Row(
    60|    60|                      children: [
    61|    61|                        Expanded(child: _buildChatMessages(chat)),
    62|    62|                        if (showMonitor)
    63|    63|                          Container(
    64|    64|                            width: 380,
    65|    65|                            decoration: const BoxDecoration(
    66|    66|                              border: Border(left: BorderSide(color: ShadTheme.of(context).border)),
    67|    67|                            ),
    68|    68|                            child: const LLMMonitor(),
    69|    69|                          ),
    70|    70|                      ],
    71|    71|                    ),
    72|    72|                  ),
    73|    73|                  ChatInput(
    74|    74|                    onSend: (text) => chat.sendMessage(text),
    75|    75|                    isStreaming: chat.isStreaming,
    76|    76|                  ),
    77|    77|                ],
    78|    78|              ),
    79|    79|
    80|    80|              // ── Left: Session panel (slides in) ──
    81|    81|              if (_sessionPanelOpen)
    82|    82|                Positioned(
    83|    83|                  left: 0,
    84|    84|                  top: 0,
    85|    85|                  bottom: 0,
    86|    86|                  child: _SessionPanel(chat: chat, onClose: () => setState(() => _sessionPanelOpen = false)),
    87|    87|                ),
    88|    88|
    89|    89|              // ── Right: Settings panel (slides in) ──
    90|    90|              if (_settingsPanelOpen)
    91|    91|                Positioned(
    92|    92|                  right: 0,
    93|    93|                  top: 0,
    94|    94|                  bottom: 0,
    95|    95|                  child: _SettingsPanel(
    96|    96|                    sp: sp,
    97|    97|                    chat: chat,
    98|    98|                    onClose: () => setState(() => _settingsPanelOpen = false),
    99|    99|                  ),
   100|   100|                ),
   101|   101|            ],
   102|   102|          ),
   103|   103|        );
   104|   104|      },
   105|   105|    );
   106|   106|  }
   107|   107|
   108|   108|  // ── Header ──
   109|   109|
   110|   110|  Widget _buildHeader(ChatProvider chat) {
   111|   111|    return Container(
   112|   112|      height: 42,
   113|   113|      padding: const EdgeInsets.symmetric(horizontal: 16),
   114|   114|      decoration: const BoxDecoration(
   115|   115|        border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
   116|   116|      ),
   117|   117|      child: Row(
   118|   118|        children: [
   119|   119|          // Session toggle
   120|   120|          GestureDetector(
   121|   121|            onTap: () => setState(() => _sessionPanelOpen = !_sessionPanelOpen),
   122|   122|            child: Container(
   123|   123|              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
   124|   124|              decoration: BoxDecoration(
   125|   125|                borderRadius: BorderRadius.circular(4),
   126|   126|                color: _sessionPanelOpen ? ShadTheme.of(context).primary.withAlpha(25) : ShadTheme.of(context).secondary,
   127|   127|              ),
   128|   128|              child: Row(
   129|   129|                mainAxisSize: MainAxisSize.min,
   130|   130|                children: [
   131|   131|                  Icon(Icons.menu, size: 14, color: ShadTheme.of(context).mutedForeground),
   132|   132|                  const SizedBox(width: 4),
   133|   133|                  Text(
   134|   134|                    chat.activeSessionTitle.isNotEmpty ? chat.activeSessionTitle : 'Chat',
   135|   135|                    style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
   136|   136|                  ),
   137|   137|                ],
   138|   138|              ),
   139|   139|            ),
   140|   140|          ),
   141|   141|          const Spacer(),
   142|   142|          // New session
   143|   143|          GestureDetector(
   144|   144|            onTap: chat.isStreaming ? null : () => chat.createNewSession(),
   145|   145|            child: Container(
   146|   146|              padding: const EdgeInsets.all(6),
   147|   147|              decoration: BoxDecoration(
   148|   148|                borderRadius: BorderRadius.circular(4),
   149|   149|                border: Border.all(color: ShadTheme.of(context).input),
   150|   150|              ),
   151|   151|              child: Icon(Icons.add, size: 14, color: ShadTheme.of(context).mutedForeground),
   152|   152|            ),
   153|   153|          ),
   154|   154|          const SizedBox(width: 6),
   155|   155|          // Settings toggle
   156|   156|          GestureDetector(
   157|   157|            onTap: () => setState(() => _settingsPanelOpen = !_settingsPanelOpen),
   158|   158|            child: Container(
   159|   159|              padding: const EdgeInsets.all(6),
   160|   160|              decoration: BoxDecoration(
   161|   161|                borderRadius: BorderRadius.circular(4),
   162|   162|                color: _settingsPanelOpen ? ShadTheme.of(context).primary.withAlpha(25) : null,
   163|   163|                border: _settingsPanelOpen ? null : Border.all(color: ShadTheme.of(context).input),
   164|   164|              ),
   165|   165|              child: Icon(Icons.settings, size: 14, color: ShadTheme.of(context).mutedForeground),
   166|   166|            ),
   167|   167|          ),
   168|   168|        ],
   169|   169|      ),
   170|   170|    );
   171|   171|  }
   172|   172|
   173|   173|  // ── Messages ──
   174|   174|
   175|   175|  Widget _buildChatMessages(ChatProvider chat) {
   176|   176|    return chat.messages.isEmpty
   177|   177|        ? Center(
   178|   178|            child: Text('Start a conversation',
   179|   179|                style: TextStyle(color: ShadTheme.of(context).mutedForeground.withAlpha(120), fontSize: 14)))
   180|   180|        : ListView.builder(
   181|   181|            controller: _scrollController,
   182|   182|            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
   183|   183|            itemCount: chat.messages.length,
   184|   184|            itemBuilder: (_, i) {
   185|   185|              final item = chat.messages[i];
   186|   186|              return Padding(
   187|   187|                padding: const EdgeInsets.only(bottom: 12),
   188|   188|                child: Column(
   189|   189|                  crossAxisAlignment: item.role == 'user' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
   190|   190|                  children: [
   191|   191|                    Padding(
   192|   192|                      padding: const EdgeInsets.only(bottom: 4),
   193|   193|                      child: Text(item.role == 'user' ? 'You' : 'AI',
   194|   194|                          style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
   195|   195|                    ),
   196|   196|                    ChatBubble(item: item),
   197|   197|                  ],
   198|   198|                ),
   199|   199|              );
   200|   200|            },
   201|   201|          );
   202|   202|  }
   203|   203|}
   204|   204|
   205|   205|// ═══════════════════════════════════════════════════════════════
   206|   206|// Session Panel (left)
   207|   207|// ═══════════════════════════════════════════════════════════════
   208|   208|
   209|   209|class _SessionPanel extends StatelessWidget {
   210|   210|  final ChatProvider chat;
   211|   211|  final VoidCallback onClose;
   212|   212|
   213|   213|  const _SessionPanel({required this.chat, required this.onClose});
   214|   214|
   215|   215|  @override
   216|   216|  Widget build(BuildContext context) {
   217|   217|    return AnimatedContainer(
   218|   218|      duration: const Duration(milliseconds: 250),
   219|   219|      curve: Curves.easeInOut,
   220|   220|      width: 260,
   221|   221|      color: const Color(0xFF151515),
   222|   222|      child: Column(
   223|   223|        crossAxisAlignment: CrossAxisAlignment.stretch,
   224|   224|        children: [
   225|   225|          // Header with close button
   226|   226|          Container(
   227|   227|            height: 42,
   228|   228|            padding: const EdgeInsets.symmetric(horizontal: 12),
   229|   229|            decoration: const BoxDecoration(
   230|   230|              border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
   231|   231|            ),
   232|   232|            child: Row(
   233|   233|              children: [
   234|   234|                const Text('Sessions',
   235|   235|                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
   236|   236|                const Spacer(),
   237|   237|                GestureDetector(
   238|   238|                  onTap: onClose,
   239|   239|                  child: Icon(Icons.close, size: 16, color: ShadTheme.of(context).mutedForeground),
   240|   240|                ),
   241|   241|              ],
   242|   242|            ),
   243|   243|          ),
   244|   244|          // New Session button
   245|   245|          Padding(
   246|   246|            padding: const EdgeInsets.all(12),
   247|   247|            child: GestureDetector(
   248|   248|              onTap: chat.isStreaming ? null : () => chat.createNewSession(),
   249|   249|              child: Container(
   250|   250|                width: double.infinity,
   251|   251|                padding: const EdgeInsets.symmetric(vertical: 8),
   252|   252|                decoration: BoxDecoration(
   253|   253|                  borderRadius: BorderRadius.circular(6),
   254|   254|                  border: Border.all(color: ShadTheme.of(context).input),
   255|   255|                ),
   256|   256|                child: const Row(
   257|   257|                  mainAxisAlignment: MainAxisAlignment.center,
   258|   258|                  children: [
   259|   259|                    Icon(Icons.add, size: 14, color: ShadTheme.of(context).foreground),
   260|   260|                    SizedBox(width: 6),
   261|   261|                    Text('New Session', style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
   262|   262|                  ],
   263|   263|                ),
   264|   264|              ),
   265|   265|            ),
   266|   266|          ),
   267|   267|          // Session list
   268|   268|          Expanded(
   269|   269|            child: chat.sessions.isEmpty
   270|   270|                ? Center(
   271|   271|                    child: Text('Memory Empty',
   272|   272|                        style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground.withAlpha(120))))
   273|   273|                : ListView.builder(
   274|   274|                    padding: const EdgeInsets.symmetric(horizontal: 8),
   275|   275|                    itemCount: chat.sessions.length,
   276|   276|                    itemBuilder: (_, i) {
   277|   277|                      final s = chat.sessions[i];
   278|   278|                      final id = s['id'] as String? ?? '';
   279|   279|                      final title = (s['title'] as String?) ?? 'Untitled';
   280|   280|                      final active = id == chat.activeSessionId;
   281|   281|                      return GestureDetector(
   282|   282|                        onTap: () => chat.loadSession(id),
   283|   283|                        child: Container(
   284|   284|                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
   285|   285|                          margin: const EdgeInsets.only(bottom: 2),
   286|   286|                          decoration: BoxDecoration(
   287|   287|                            color: active ? ShadTheme.of(context).secondary : null,
   288|   288|                            borderRadius: BorderRadius.circular(4),
   289|   289|                          ),
   290|   290|                          child: Text(title,
   291|   291|                              style: TextStyle(
   292|   292|                                  fontSize: 13,
   293|   293|                                  color: active ? ShadTheme.of(context).foreground : ShadTheme.of(context).mutedForeground),
   294|   294|                              overflow: TextOverflow.ellipsis),
   295|   295|                        ),
   296|   296|                      );
   297|   297|                    },
   298|   298|                  ),
   299|   299|          ),
   300|   300|          const SizedBox(height: 8),
   301|   301|        ],
   302|   302|      ),
   303|   303|    );
   304|   304|  }
   305|   305|}
   306|   306|
   307|   307|// ═══════════════════════════════════════════════════════════════
   308|   308|// Settings Panel (right)
   309|   309|// ═══════════════════════════════════════════════════════════════
   310|   310|
   311|   311|class _SettingsPanel extends StatelessWidget {
   312|   312|  final SettingsProvider sp;
   313|   313|  final ChatProvider chat;
   314|   314|  final VoidCallback onClose;
   315|   315|
   316|   316|  const _SettingsPanel({required this.sp, required this.chat, required this.onClose});
   317|   317|
   318|   318|  @override
   319|   319|  Widget build(BuildContext context) {
   320|   320|    final s = sp.settings;
   321|   321|    final baseUrlCtrl = TextEditingController(text: s.apiRelayBaseUrl);
   322|   322|    final apiKeyCtrl = TextEditingController(text: s.apiRelayApiKey);
   323|   323|    final modelCtrl = TextEditingController(text: s.apiRelayModel);
   324|   324|    final promptCtrl = TextEditingController(text: s.systemPrompt);
   325|   325|
   326|   326|    return AnimatedContainer(
   327|   327|      duration: const Duration(milliseconds: 250),
   328|   328|      curve: Curves.easeInOut,
   329|   329|      width: 420,
   330|   330|      color: const Color(0xFF151515),
   331|   331|      child: Column(
   332|   332|        children: [
   333|   333|          // Header
   334|   334|          Container(
   335|   335|            height: 42,
   336|   336|            padding: const EdgeInsets.symmetric(horizontal: 12),
   337|   337|            decoration: const BoxDecoration(
   338|   338|              border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
   339|   339|            ),
   340|   340|            child: Row(
   341|   341|              children: [
   342|   342|                const Text('Settings',
   343|   343|                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
   344|   344|                const Spacer(),
   345|   345|                GestureDetector(
   346|   346|                  onTap: onClose,
   347|   347|                  child: Icon(Icons.close, size: 16, color: ShadTheme.of(context).mutedForeground),
   348|   348|                ),
   349|   349|              ],
   350|   350|            ),
   351|   351|          ),
   352|   352|          // Content
   353|   353|          Expanded(
   354|   354|            child: SingleChildScrollView(
   355|   355|              padding: const EdgeInsets.all(16),
   356|   356|              child: Column(
   357|   357|                crossAxisAlignment: CrossAxisAlignment.start,
   358|   358|                children: [
   359|   359|                  _label('AI Model Selector'),
   360|   360|                  const SizedBox(height: 6),
   361|   361|                  _field(modelCtrl, 'Model name'),
   362|   362|                  const SizedBox(height: 16),
   363|   363|                  _label('System Prompt'),
   364|   364|                  const SizedBox(height: 6),
   365|   365|                  _field(promptCtrl, 'You are an uncensored AI model.', maxLines: 5),
   366|   366|                  const SizedBox(height: 16),
   367|   367|                  _switchRow(
   368|   368|                    label: 'Show Monitor',
   369|   369|                    desc: 'Show the LLM monitor on the right side.',
   370|   370|                    value: s.showMonitor,
   371|   371|                    onChanged: (v) => sp.saveSettings(s.copyWith(showMonitor: v)),
   372|   372|                  ),
   373|   373|                  const SizedBox(height: 12),
   374|   374|                  _switchRow(
   375|   375|                    label: 'Enable Memory Retrieval',
   376|   376|                    desc: 'Retrieve relevant context from memory.',
   377|   377|                    value: s.enableMemoryRetrieval,
   378|   378|                    onChanged: (v) => sp.saveSettings(s.copyWith(enableMemoryRetrieval: v)),
   379|   379|                  ),
   380|   380|                  const SizedBox(height: 20),
   381|   381|                  Container(height: 1, color: ShadTheme.of(context).border),
   382|   382|                  const SizedBox(height: 16),
   383|   383|                  _label('API Relay Config'),
   384|   384|                  const SizedBox(height: 8),
   385|   385|                  _label('Base URL'),
   386|   386|                  const SizedBox(height: 4),
   387|   387|                  _field(baseUrlCtrl, 'https://api.siliconflow.cn/v1'),
   388|   388|                  const SizedBox(height: 10),
   389|   389|                  _label('API Key'),
   390|   390|                  const SizedBox(height: 4),
   391|   391|                  _field(apiKeyCtrl, 'sk-...', obscure: true),
   392|   392|                  const SizedBox(height: 20),
   393|   393|                  SizedBox(
   394|   394|                    width: double.infinity,
   395|   395|                    child: ElevatedButton(
   396|   396|                      onPressed: () {
   397|   397|                        sp.saveSettings(s.copyWith(
   398|   398|                          apiRelayBaseUrl: baseUrlCtrl.text.trim(),
   399|   399|                          apiRelayApiKey: apiKeyCtrl.text.trim(),
   400|   400|                          apiRelayModel: modelCtrl.text.trim(),
   401|   401|                          systemPrompt: promptCtrl.text,
   402|   402|                        ));
   403|   403|                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
   404|   404|                            content: Text('Settings saved'),
   405|   405|                            backgroundColor: ShadTheme.of(context).primary,
   406|   406|                            duration: Duration(seconds: 2)));
   407|   407|                      },
   408|   408|                      child: Text('Save Settings', style: TextStyle(color: ShadTheme.of(context).primaryForeground)),
   409|   409|                    ),
   410|   410|                  ),
   411|   411|                ],
   412|   412|              ),
   413|   413|            ),
   414|   414|          ),
   415|   415|        ],
   416|   416|      ),
   417|   417|    );
   418|   418|  }
   419|   419|
   420|   420|  Widget _label(String t) => Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground));
   421|   421|
   422|   422|  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1, bool obscure = false}) {
   423|   423|    return TextField(
   424|   424|      controller: ctrl, maxLines: maxLines, obscureText: obscure,
   425|   425|      style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
   426|   426|      decoration: InputDecoration(
   427|   427|        hintText: hint, filled: true, fillColor: ShadTheme.of(context).secondary,
   428|   428|        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
   429|   429|        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
   430|   430|        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
   431|   431|            borderSide: BorderSide(color: ShadTheme.of(context).input)),
   432|   432|        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
   433|   433|            borderSide: BorderSide(color: ShadTheme.of(context).ring, width: 1)),
   434|   434|      ),
   435|   435|    );
   436|   436|  }
   437|   437|
   438|   438|  Widget _switchRow({required String label, required String desc, required bool value, required ValueChanged<bool> onChanged}) {
   439|   439|    return Row(children: [
   440|   440|      SizedBox(height: 24, child: Switch(value: value, onChanged: onChanged, activeColor: ShadTheme.of(context).primary)),
   441|   441|      const SizedBox(width: 10),
   442|   442|      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
   443|   443|        Text(label, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
   444|   444|        Text(desc, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
   445|   445|      ])),
   446|   446|    ]);
   447|   447|  }
   448|   448|}
   449|   449|