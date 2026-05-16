     1|     1|import 'package:flutter/material.dart';
     2|     2|import 'package:provider/provider.dart';
     3|     3|import '../app.dart';
     4|     4|import '../providers/multi_agent_provider.dart';
     5|     5|import '../providers/appearance_provider.dart';
     6|     6|import '../services/wenzagent_service.dart';
     7|     7|import 'multi_agent_appearance.dart';
     8|     8|
     9|     9|/// Multi-agent network page — matches prompt.md spec:
    10|    10|/// Secondary sidebar (Chat/Contacts), device list, agent chat, employee creation.
    11|    11|class MultiAgentScreen extends StatefulWidget {
    12|    12|  const MultiAgentScreen({super.key});
    13|    13|
    14|    14|  @override
    15|    15|  State<MultiAgentScreen> createState() => _MultiAgentScreenState();
    16|    16|}
    17|    17|
    18|    18|class _MultiAgentScreenState extends State<MultiAgentScreen> {
    19|    19|  final _msgCtrl = TextEditingController();
    20|    20|  final _scrollCtrl = ScrollController();
    21|    21|  final _searchCtrl = TextEditingController();
    22|    22|
    23|    23|  bool _initialized = false;
    24|    24|  bool _contactsMode = false;
    25|    25|  bool _showSettings = false;
    26|    26|  String _searchQuery = '';
    27|    27|
    28|    28|  @override
    29|    29|  void initState() {
    30|    30|    super.initState();
    31|    31|    _searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
    32|    32|    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
    33|    33|  }
    34|    34|
    35|    35|  @override
    36|    36|  void dispose() {
    37|    37|    _msgCtrl.dispose();
    38|    38|    _scrollCtrl.dispose();
    39|    39|    _searchCtrl.dispose();
    40|    40|    _waHostCtrl.dispose();
    41|    41|    _waPortCtrl.dispose();
    42|    42|    _waTopicCtrl.dispose();
    43|    43|    super.dispose();
    44|    44|  }
    45|    45|
    46|    46|  void _init() {
    47|    47|    if (_initialized) return;
    48|    48|    _initialized = true;
    49|    49|    final mgr = context.read<AgentManager>();
    50|    50|    if (!mgr.initialized) {
    51|    51|      mgr.initIfEnabled(
    52|    52|        storagePath: r'D:\AiVtuber_Agent_profile\wenzagent',
    53|    53|        host: '127.0.0.1',
    54|    54|        port: 9090,
    55|    55|        deviceName: 'AI VTuber',
    56|    56|      );
    57|    57|    }
    58|    58|  }
    59|    59|
    60|    60|  // ─── Build ──────────────────────────────────────────────
    61|    61|
    62|    62|  @override
    63|    63|  Widget build(BuildContext context) {
    64|    64|    return Consumer<AgentManager>(
    65|    65|      builder: (context, mgr, _) {
    66|    66|        return Row(
    67|    67|          children: [
    68|    68|            // ── Secondary Sidebar ──
    69|    69|            SizedBox(
    70|    70|              width: 260,
    71|    71|              child: _buildSecondarySidebar(mgr),
    72|    72|            ),
    73|    73|            VerticalDivider(width: 1, color: ShadTheme.of(context).border),
    74|    74|            // ── Content Area ──
    75|    75|            Expanded(child: _buildContentArea(mgr)),
    76|    76|          ],
    77|    77|        );
    78|    78|      },
    79|    79|    );
    80|    80|  }
    81|    81|
    82|    82|  // ══════════════════════════════════════════════════════════
    83|    83|  // Secondary Sidebar
    84|    84|  // ══════════════════════════════════════════════════════════
    85|    85|
    86|    86|  Widget _buildSecondarySidebar(AgentManager mgr) {
    87|    87|    return Column(
    88|    88|      children: [
    89|    89|        // ── Top bar: status + mode switch ──
    90|    90|        _buildSidebarHeader(mgr),
    91|    91|        Divider(height: 1, color: ShadTheme.of(context).border),
    92|    92|        // ── Search (Chat mode only) ──
    93|    93|        if (!_contactsMode)
    94|    94|          Padding(
    95|    95|            padding: const EdgeInsets.all(10),
    96|    96|            child: TextField(
    97|    97|              controller: _searchCtrl,
    98|    98|              decoration: InputDecoration(
    99|    99|                hintText: 'Search agents...',
   100|   100|                prefixIcon: Icon(Icons.search, size: 18, color: ShadTheme.of(context).mutedForeground),
   101|   101|                filled: true,
   102|   102|                fillColor: ShadTheme.of(context).secondary,
   103|   103|                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
   104|   104|                border: OutlineInputBorder(
   105|   105|                  borderRadius: BorderRadius.circular(8),
   106|   106|                  borderSide: BorderSide.none,
   107|   107|                ),
   108|   108|                isDense: true,
   109|   109|              ),
   110|   110|              style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
   111|   111|            ),
   112|   112|          ),
   113|   113|        Divider(height: 1, color: ShadTheme.of(context).border),
   114|   114|        // ── Content (Chat list or Contacts list) ──
   115|   115|        Expanded(
   116|   116|          child: _contactsMode ? _buildContactsList(mgr) : _buildChatList(mgr),
   117|   117|        ),
   118|   118|        // ── "+ Create Employee" button (Contacts mode only) ──
   119|   119|        if (_contactsMode) _buildCreateButton(),
   120|   120|      ],
   121|   121|    );
   122|   122|  }
   123|   123|
   124|   124|  Widget _buildSidebarHeader(AgentManager mgr) {
   125|   125|    return Container(
   126|   126|      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
   127|   127|      color: ShadTheme.of(context).sidebar,
   128|   128|      child: Row(
   129|   129|        children: [
   130|   130|          // Connection dot
   131|   131|          Container(
   132|   132|            width: 8, height: 8,
   133|   133|            decoration: BoxDecoration(
   134|   134|              color: mgr.connected ? const Color(0xFF4CAF50) : const Color(0xFFCF6679),
   135|   135|              shape: BoxShape.circle,
   136|   136|            ),
   137|   137|          ),
   138|   138|          const SizedBox(width: 6),
   139|   139|          Text(
   140|   140|            mgr.connected ? 'LAN Online' : 'Offline',
   141|   141|            style: TextStyle(
   142|   142|              fontSize: 11,
   143|   143|              color: mgr.connected ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground,
   144|   144|            ),
   145|   145|          ),
   146|   146|          const Spacer(),
   147|   147|          // Settings gear
   148|   148|          GestureDetector(
   149|   149|            onTap: () => setState(() => _showSettings = !_showSettings),
   150|   150|            child: Container(
   151|   151|              padding: const EdgeInsets.all(6),
   152|   152|              decoration: BoxDecoration(
   153|   153|                color: _showSettings ? ShadTheme.of(context).sidebarAccent : Colors.transparent,
   154|   154|                borderRadius: BorderRadius.circular(6),
   155|   155|              ),
   156|   156|              child: Icon(Icons.settings, size: 18,
   157|   157|                  color: _showSettings ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).mutedForeground),
   158|   158|            ),
   159|   159|          ),
   160|   160|          const SizedBox(width: 4),
   161|   161|          // Mode toggle buttons
   162|   162|          _modeButton(Icons.chat_bubble_outline, 'Chat', !_contactsMode, () => setState(() => _contactsMode = false)),
   163|   163|          const SizedBox(width: 4),
   164|   164|          _modeButton(Icons.contacts_outlined, 'Contacts', _contactsMode, () => setState(() => _contactsMode = true)),
   165|   165|        ],
   166|   166|      ),
   167|   167|    );
   168|   168|  }
   169|   169|
   170|   170|  Widget _modeButton(IconData icon, String tooltip, bool active, VoidCallback onTap) {
   171|   171|    return GestureDetector(
   172|   172|      onTap: onTap,
   173|   173|      child: Tooltip(
   174|   174|        message: tooltip,
   175|   175|        child: Container(
   176|   176|          padding: const EdgeInsets.all(6),
   177|   177|          decoration: BoxDecoration(
   178|   178|            color: active ? ShadTheme.of(context).sidebarAccent : Colors.transparent,
   179|   179|            borderRadius: BorderRadius.circular(6),
   180|   180|          ),
   181|   181|          child: Icon(icon, size: 18,
   182|   182|              color: active ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).mutedForeground),
   183|   183|        ),
   184|   184|      ),
   185|   185|    );
   186|   186|  }
   187|   187|
   188|   188|  // ══════════════════════════════════════════════════════════
   189|   189|  // Chat List (Chat mode)
   190|   190|  // ══════════════════════════════════════════════════════════
   191|   191|
   192|   192|  Widget _buildChatList(AgentManager mgr) {
   193|   193|    // Show device list first, then filtered agent list
   194|   194|    final filtered = _searchQuery.isEmpty
   195|   195|        ? mgr.agentSummaries
   196|   196|        : mgr.agentSummaries.where((a) =>
   197|   197|            a.name.toLowerCase().contains(_searchQuery) ||
   198|   198|            a.uuid.toLowerCase().contains(_searchQuery)).toList();
   199|   199|
   200|   200|    if (mgr.onlineDevices.isEmpty && mgr.agentSummaries.isEmpty) {
   201|   201|      return const Center(
   202|   202|        child: Padding(
   203|   203|          padding: EdgeInsets.all(24),
   204|   204|          child: Text(
   205|   205|            'No agents found.\nStart a wenzagent server to see agents here.',
   206|   206|            textAlign: TextAlign.center,
   207|   207|            style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground),
   208|   208|          ),
   209|   209|        ),
   210|   210|      );
   211|   211|    }
   212|   212|
   213|   213|    return ListView(
   214|   214|      children: [
   215|   215|        // ── Devices section ──
   216|   216|        if (mgr.onlineDevices.isNotEmpty) ...[
   217|   217|          const Padding(
   218|   218|            padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
   219|   219|            child: Text('DEVICES',
   220|   220|                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
   221|   221|                    color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
   222|   222|          ),
   223|   223|          ...mgr.onlineDevices.map((d) => _deviceTile(d)),
   224|   224|          Divider(height: 1, color: ShadTheme.of(context).border),
   225|   225|        ],
   226|   226|        // ── Agents section ──
   227|   227|        Padding(
   228|   228|          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
   229|   229|          child: Text('AGENTS (${filtered.length})',
   230|   230|              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
   231|   231|                  color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
   232|   232|        ),
   233|   233|        if (filtered.isEmpty)
   234|   234|          const Padding(
   235|   235|            padding: EdgeInsets.all(12),
   236|   236|            child: Text('No matching agents',
   237|   237|                style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
   238|   238|          )
   239|   239|        else
   240|   240|          ...filtered.map((a) => _agentTile(a, mgr)),
   241|   241|      ],
   242|   242|    );
   243|   243|  }
   244|   244|
   245|   245|  Widget _deviceTile(DeviceInfo device) {
   246|   246|    return Padding(
   247|   247|      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
   248|   248|      child: Container(
   249|   249|        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
   250|   250|        decoration: BoxDecoration(
   251|   251|          color: ShadTheme.of(context).secondary,
   252|   252|          borderRadius: BorderRadius.circular(6),
   253|   253|        ),
   254|   254|        child: Row(
   255|   255|          children: [
   256|   256|            const Icon(Icons.computer, size: 16, color: Color(0xFF4CAF50)),
   257|   257|            const SizedBox(width: 8),
   258|   258|            Expanded(
   259|   259|              child: Text(device.deviceName, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
   260|   260|            ),
   261|   261|            Container(width: 8, height: 8, decoration: const BoxDecoration(
   262|   262|                color: Color(0xFF4CAF50), shape: BoxShape.circle)),
   263|   263|          ],
   264|   264|        ),
   265|   265|      ),
   266|   266|    );
   267|   267|  }
   268|   268|
   269|   269|  Widget _agentTile(AgentModel agent, AgentManager mgr) {
   270|   270|    final isActive = mgr.activeEmployeeId == agent.uuid;
   271|   271|
   272|   272|    return Padding(
   273|   273|      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
   274|   274|      child: GestureDetector(
   275|   275|        onTap: () => _selectAgent(agent, mgr),
   276|   276|        child: Container(
   277|   277|          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
   278|   278|          decoration: BoxDecoration(
   279|   279|            color: isActive ? ShadTheme.of(context).sidebarAccent : ShadTheme.of(context).secondary,
   280|   280|            borderRadius: BorderRadius.circular(6),
   281|   281|            border: isActive ? Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(80)) : null,
   282|   282|          ),
   283|   283|          child: Row(
   284|   284|            children: [
   285|   285|              Icon(Icons.smart_toy, size: 20, color: ShadTheme.of(context).foreground),
   286|   286|              const SizedBox(width: 8),
   287|   287|              Expanded(
   288|   288|                child: Column(
   289|   289|                  crossAxisAlignment: CrossAxisAlignment.start,
   290|   290|                  children: [
   291|   291|                    Text(agent.name, style: TextStyle(fontSize: 13,
   292|   292|                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
   293|   293|                        color: ShadTheme.of(context).foreground)),
   294|   294|                    if (agent.description != null && agent.description!.isNotEmpty)
   295|   295|                      Text(agent.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
   296|   296|                          style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
   297|   297|                  ],
   298|   298|                ),
   299|   299|              ),
   300|   300|              if (agent.status == 'unread')
   301|   301|                Container(
   302|   302|                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
   303|   303|                  decoration: BoxDecoration(color: ShadTheme.of(context).destructive, borderRadius: BorderRadius.circular(8)),
   304|   304|                  child: const Text('NEW', style: TextStyle(fontSize: 9, color: Colors.white)),
   305|   305|                ),
   306|   306|              const SizedBox(width: 4),
   307|   307|              Icon(Icons.chevron_right, size: 16, color: ShadTheme.of(context).mutedForeground),
   308|   308|            ],
   309|   309|          ),
   310|   310|        ),
   311|   311|      ),
   312|   312|    );
   313|   313|  }
   314|   314|
   315|   315|  Widget _unreadBadge(int count) {
   316|   316|    return Container(
   317|   317|      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
   318|   318|      decoration: BoxDecoration(color: ShadTheme.of(context).destructive, borderRadius: BorderRadius.circular(8)),
   319|   319|      child: Text(count > 99 ? '99+' : '$count',
   320|   320|          style: const TextStyle(fontSize: 10, color: Colors.white)),
   321|   321|    );
   322|   322|  }
   323|   323|
   324|   324|  // ══════════════════════════════════════════════════════════
   325|   325|  // Contacts List (Contacts mode)
   326|   326|  // ══════════════════════════════════════════════════════════
   327|   327|
   328|   328|  Widget _buildContactsList(AgentManager mgr) {
   329|   329|    final filtered = _searchQuery.isEmpty
   330|   330|        ? mgr.employees
   331|   331|        : mgr.employees.where((e) =>
   332|   332|            e.name.toLowerCase().contains(_searchQuery) ||
   333|   333|            (e.description ?? '').toLowerCase().contains(_searchQuery)).toList();
   334|   334|
   335|   335|    if (mgr.employees.isEmpty) {
   336|   336|      return Center(
   337|   337|        child: Padding(
   338|   338|          padding: const EdgeInsets.all(24),
   339|   339|          child: Column(
   340|   340|            mainAxisSize: MainAxisSize.min,
   341|   341|            children: [
   342|   342|              Icon(Icons.group_add_outlined, size: 40, color: ShadTheme.of(context).mutedForeground),
   343|   343|              const SizedBox(height: 12),
   344|   344|              const Text('No employees yet',
   345|   345|                  style: TextStyle(fontSize: 14, color: ShadTheme.of(context).mutedForeground)),
   346|   346|              const SizedBox(height: 4),
   347|   347|              const Text('Create an AI employee to get started',
   348|   348|                  style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
   349|   349|            ],
   350|   350|          ),
   351|   351|        ),
   352|   352|      );
   353|   353|    }
   354|   354|
   355|   355|    return ListView.builder(
   356|   356|      itemCount: filtered.length,
   357|   357|      itemBuilder: (_, i) => _employeeTile(filtered[i], mgr),
   358|   358|    );
   359|   359|  }
   360|   360|
   361|   361|  Widget _employeeTile(AgentModel emp, AgentManager mgr) {
   362|   362|    return Padding(
   363|   363|      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
   364|   364|      child: GestureDetector(
   365|   365|        onTap: () {
   366|   366|          setState(() => _contactsMode = false);
   367|   367|          _selectAgent(emp, mgr);
   368|   368|        },
   369|   369|        child: Container(
   370|   370|          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
   371|   371|          decoration: BoxDecoration(
   372|   372|            color: ShadTheme.of(context).secondary,
   373|   373|            borderRadius: BorderRadius.circular(6),
   374|   374|          ),
   375|   375|          child: Row(
   376|   376|            children: [
   377|   377|              // Avatar placeholder
   378|   378|              Container(
   379|   379|                width: 32, height: 32,
   380|   380|                decoration: BoxDecoration(
   381|   381|                  color: Theme.of(context).colorScheme.primary.withAlpha(40),
   382|   382|                  borderRadius: BorderRadius.circular(8),
   383|   383|                ),
   384|   384|                child: Icon(Icons.person, size: 18, color: Theme.of(context).colorScheme.primary),
   385|   385|              ),
   386|   386|              const SizedBox(width: 10),
   387|   387|              Expanded(
   388|   388|                child: Column(
   389|   389|                  crossAxisAlignment: CrossAxisAlignment.start,
   390|   390|                  children: [
   391|   391|                    Text(emp.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
   392|   392|                        color: ShadTheme.of(context).foreground)),
   393|   393|                    if (emp.description != null && emp.description!.isNotEmpty)
   394|   394|                      Text(emp.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
   395|   395|                          style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
   396|   396|                    const SizedBox(height: 2),
   397|   397|                    Wrap(
   398|   398|                      spacing: 4,
   399|   399|                      runSpacing: 2,
   400|   400|                      children: [
   401|   401|                        _chip(emp.provider ?? 'unknown'),
   402|   402|                        _chip(emp.model ?? 'default'),
   403|   403|                        _chip(emp.deviceId != null ? 'bound' : 'unbound'),
   404|   404|                      ],
   405|   405|                    ),
   406|   406|                  ],
   407|   407|                ),
   408|   408|              ),
   409|   409|              // Delete button
   410|   410|              GestureDetector(
   411|   411|                onTap: () => _confirmDelete(emp, mgr),
   412|   412|                child: Icon(Icons.delete_outline, size: 16, color: ShadTheme.of(context).mutedForeground),
   413|   413|              ),
   414|   414|            ],
   415|   415|          ),
   416|   416|        ),
   417|   417|      ),
   418|   418|    );
   419|   419|  }
   420|   420|
   421|   421|  Widget _chip(String label) {
   422|   422|    return Container(
   423|   423|      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
   424|   424|      decoration: BoxDecoration(
   425|   425|        color: ShadTheme.of(context).mutedForeground.withAlpha(25),
   426|   426|        borderRadius: BorderRadius.circular(3),
   427|   427|      ),
   428|   428|      child: Text(label, style: TextStyle(fontSize: 9, color: ShadTheme.of(context).mutedForeground)),
   429|   429|    );
   430|   430|  }
   431|   431|
   432|   432|  void _confirmDelete(AgentModel emp, AgentManager mgr) {
   433|   433|    showDialog(
   434|   434|      context: context,
   435|   435|      builder: (ctx) => AlertDialog(
   436|   436|        backgroundColor: ShadTheme.of(context).card,
   437|   437|        title: Text('Delete Employee', style: TextStyle(color: ShadTheme.of(context).foreground)),
   438|   438|        content: Text('Delete "${emp.name}"? This cannot be undone.',
   439|   439|            style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
   440|   440|        actions: [
   441|   441|          TextButton(
   442|   442|            onPressed: () => Navigator.pop(ctx),
   443|   443|            child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
   444|   444|          ),
   445|   445|          TextButton(
   446|   446|            onPressed: () {
   447|   447|              mgr.deleteEmployee(emp.uuid);
   448|   448|              Navigator.pop(ctx);
   449|   449|            },
   450|   450|            child: Text('Delete', style: TextStyle(color: ShadTheme.of(context).destructive)),
   451|   451|          ),
   452|   452|        ],
   453|   453|      ),
   454|   454|    );
   455|   455|  }
   456|   456|
   457|   457|  Widget _buildCreateButton() {
   458|   458|    return Container(
   459|   459|      padding: const EdgeInsets.all(10),
   460|   460|      decoration: const BoxDecoration(
   461|   461|        border: Border(top: BorderSide(color: ShadTheme.of(context).border)),
   462|   462|      ),
   463|   463|      child: SizedBox(
   464|   464|        width: double.infinity,
   465|   465|        child: OutlinedButton.icon(
   466|   466|          onPressed: () => _showCreateEmployeeDialog(),
   467|   467|          icon: const Icon(Icons.add, size: 18),
   468|   468|          label: const Text('Create Employee'),
   469|   469|          style: OutlinedButton.styleFrom(
   470|   470|            foregroundColor: Theme.of(context).colorScheme.primary,
   471|   471|            side: BorderSide(color: Theme.of(context).colorScheme.primary),
   472|   472|            padding: const EdgeInsets.symmetric(vertical: 10),
   473|   473|          ),
   474|   474|        ),
   475|   475|      ),
   476|   476|    );
   477|   477|  }
   478|   478|
   479|   479|  // ══════════════════════════════════════════════════════════
   480|   480|  // Create Employee Dialog
   481|   481|  // ══════════════════════════════════════════════════════════
   482|   482|
   483|   483|  void _showCreateEmployeeDialog() {
   484|   484|    final nameCtrl = TextEditingController();
   485|   485|    final descCtrl = TextEditingController();
   486|   486|
   487|   487|    showDialog(
   488|   488|      context: context,
   489|   489|      builder: (ctx) {
   490|   490|        return AlertDialog(
   491|   491|            backgroundColor: ShadTheme.of(context).card,
   492|   492|            title: Text('Create AI Employee', style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 16)),
   493|   493|            content: SizedBox(
   494|   494|              width: 400,
   495|   495|              child: SingleChildScrollView(
   496|   496|                child: Column(
   497|   497|                  mainAxisSize: MainAxisSize.min,
   498|   498|                  crossAxisAlignment: CrossAxisAlignment.start,
   499|   499|                  children: [
   500|   500|                    // Name
   501|   501|                    SizedBox(
   502|   502|                      width: 360,
   503|   503|                      child: TextField(
   504|   504|                        controller: nameCtrl,
   505|   505|                        decoration: const InputDecoration(
   506|   506|                          labelText: 'Name',
   507|   507|                          hintText: 'e.g. Code Reviewer',
   508|   508|                          filled: true, fillColor: ShadTheme.of(context).secondary,
   509|   509|                          border: OutlineInputBorder(),
   510|   510|                        ),
   511|   511|                        style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
   512|   512|                      ),
   513|   513|                    ),
   514|   514|                    const SizedBox(height: 12),
   515|   515|                    // Description
   516|   516|                    SizedBox(
   517|   517|                      width: 360,
   518|   518|                      child: TextField(
   519|   519|                        controller: descCtrl,
   520|   520|                        maxLines: 3,
   521|   521|                        decoration: const InputDecoration(
   522|   522|                          labelText: 'Description',
   523|   523|                          hintText: 'Describe what this agent does...',
   524|   524|                          filled: true, fillColor: ShadTheme.of(context).secondary,
   525|   525|                          border: OutlineInputBorder(),
   526|   526|                        ),
   527|   527|                        style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
   528|   528|                      ),
   529|   529|                    ),
   530|   530|                    const SizedBox(height: 12),
   531|   531|                    // Device assignment
   532|   532|                  ],
   533|   533|                ),
   534|   534|              ),
   535|   535|            ),
   536|   536|            actions: [
   537|   537|              TextButton(
   538|   538|                onPressed: () => Navigator.pop(ctx),
   539|   539|                child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
   540|   540|              ),
   541|   541|              ElevatedButton(
   542|   542|                onPressed: () async {
   543|   543|                  final name = nameCtrl.text.trim();
   544|   544|                  if (name.isEmpty) return;
   545|   545|                  Navigator.pop(ctx);
   546|   546|                  final mgr = context.read<AgentManager>();
   547|   547|                  await mgr.createEmployee(
   548|   548|                    name: name,
   549|   549|                    description: descCtrl.text.trim(),
   550|   550|                  );
   551|   551|                },
   552|   552|                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
   553|   553|                child: const Text('Create', style: TextStyle(color: Colors.white)),
   554|   554|              ),
   555|   555|            ],
   556|   556|          );
   557|   557|        },
   558|   558|    );
   559|   559|  }
   560|   560|
   561|   561|  // ══════════════════════════════════════════════════════════
   562|   562|  // Multi-Agent Settings Page
   563|   563|  // ══════════════════════════════════════════════════════════
   564|   564|
   565|   565|  String _activeSettingSection = 'ai_config';
   566|   566|
   567|   567|  int _lanTab = 0;
   568|   568|  final _waHostCtrl = TextEditingController(text: '127.0.0.1');
   569|   569|  final _waPortCtrl = TextEditingController(text: '9090');
   570|   570|  final _waTopicCtrl = TextEditingController();
   571|   571|
   572|   572|  Widget _buildSettingsPage(AgentManager mgr) {
   573|   573|    return Row(
   574|   574|      children: [
   575|   575|        // Settings sidebar
   576|   576|        SizedBox(
   577|   577|          width: 200,
   578|   578|          child: Container(
   579|   579|            color: ShadTheme.of(context).sidebar,
   580|   580|            child: Column(
   581|   581|              crossAxisAlignment: CrossAxisAlignment.start,
   582|   582|              children: [
   583|   583|                Padding(
   584|   584|                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
   585|   585|                  child: Row(
   586|   586|                    children: [
   587|   587|                      Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
   588|   588|                      const Spacer(),
   589|   589|                      GestureDetector(
   590|   590|                        onTap: () => setState(() => _showSettings = false),
   591|   591|                        child: Icon(Icons.close, size: 18, color: ShadTheme.of(context).mutedForeground),
   592|   592|                      ),
   593|   593|                    ],
   594|   594|                  ),
   595|   595|                ),
   596|   596|                Divider(color: ShadTheme.of(context).border),
   597|   597|                _settingsGroup('Preferences', [
   598|   598|                  _settingsItem('Appearance', 'pref_appearance', Icons.palette_outlined),
   599|   599|                  _settingsItem('General', 'pref_general', Icons.tune),
   600|   600|                ]),
   601|   601|                _settingsGroup('AI', [
   602|   602|                  _settingsItem('AI Config', 'ai_config', Icons.api),
   603|   603|                  _settingsItem('MCP Config', 'ai_mcp', Icons.extension),
   604|   604|                  _settingsItem('Permissions', 'ai_permissions', Icons.security),
   605|   605|                ]),
   606|   606|                _settingsGroup('Data', [
   607|   607|                  _settingsItem('Sync', 'data_sync', Icons.sync),
   608|   608|                  _settingsItem('Storage', 'data_storage', Icons.storage),
   609|   609|                  _settingsItem('Files', 'data_files', Icons.folder),
   610|   610|                ]),
   611|   611|                _settingsGroup('Network', [
   612|   612|                  _settingsItem('LAN', 'net_lan', Icons.lan),
   613|   613|                  _settingsItem('Devices', 'net_devices', Icons.devices),
   614|   614|                ]),
   615|   615|                _settingsGroup('System', [
   616|   616|                  _settingsItem('Privacy', 'sys_privacy', Icons.privacy_tip_outlined),
   617|   617|                  _settingsItem('Logs', 'sys_logs', Icons.article_outlined),
   618|   618|                  _settingsItem('About', 'sys_about', Icons.info_outline),
   619|   619|                ]),
   620|   620|              ],
   621|   621|            ),
   622|   622|          ),
   623|   623|        ),
   624|   624|        VerticalDivider(width: 1, color: ShadTheme.of(context).border),
   625|   625|        // Settings content
   626|   626|        Expanded(child: _buildSettingsContent(mgr)),
   627|   627|      ],
   628|   628|    );
   629|   629|  }
   630|   630|
   631|   631|  Widget _settingsGroup(String title, List<Widget> items) {
   632|   632|    return Column(
   633|   633|      crossAxisAlignment: CrossAxisAlignment.start,
   634|   634|      children: [
   635|   635|        Padding(
   636|   636|          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
   637|   637|          child: Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
   638|   638|              color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
   639|   639|        ),
   640|   640|        ...items,
   641|   641|      ],
   642|   642|    );
   643|   643|  }
   644|   644|
   645|   645|  Widget _settingsItem(String title, String key, IconData icon) {
   646|   646|    final active = _activeSettingSection == key;
   647|   647|    return GestureDetector(
   648|   648|      onTap: () => setState(() => _activeSettingSection = key),
   649|   649|      child: Container(
   650|   650|        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
   651|   651|        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
   652|   652|        decoration: BoxDecoration(
   653|   653|          color: active ? ShadTheme.of(context).sidebarAccent : Colors.transparent,
   654|   654|          borderRadius: BorderRadius.circular(6),
   655|   655|        ),
   656|   656|        child: Row(
   657|   657|          children: [
   658|   658|            Icon(icon, size: 16, color: active ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).mutedForeground),
   659|   659|            const SizedBox(width: 8),
   660|   660|            Text(title, style: TextStyle(fontSize: 13,
   661|   661|                color: active ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).foreground)),
   662|   662|          ],
   663|   663|        ),
   664|   664|      ),
   665|   665|    );
   666|   666|  }
   667|   667|
   668|   668|  Widget _buildSettingsContent(AgentManager mgr) {
   669|   669|    switch (_activeSettingSection) {
   670|   670|      case 'pref_appearance':
   671|   671|        return const MultiAgentAppearancePage();
   672|   672|      case 'ai_config':
   673|   673|        return _buildAiConfigPanel(mgr);
   674|   674|      case 'ai_mcp':
   675|   675|        return _buildMcpConfigPanel(mgr);
   676|   676|      case 'ai_permissions':
   677|   677|        return _buildPermissionsPanel(mgr);
   678|   678|      case 'net_lan':
   679|   679|        return _buildLanSettingsPanel(mgr);
   680|   680|      default:
   681|   681|        return Center(
   682|   682|          child: Text('$_activeSettingSection — coming soon',
   683|   683|              style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
   684|   684|        );
   685|   685|    }
   686|   686|  }
   687|   687|
   688|   688|  // ─── AI Config Panel ─────────────────────────────────────
   689|   689|
   690|   690|  Widget _buildAiConfigPanel(AgentManager mgr) {
   691|   691|    return Column(
   692|   692|      children: [
   693|   693|        // Header
   694|   694|        Container(
   695|   695|          padding: const EdgeInsets.all(24),
   696|   696|          child: Column(
   697|   697|            crossAxisAlignment: CrossAxisAlignment.start,
   698|   698|            children: [
   699|   699|              Text('AI Provider Profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
   700|   700|              const SizedBox(height: 4),
   701|   701|   701|   701|              const Text('Create named profiles with base URL, API key, and model. Select a profile when starting an agent chat.',
   702|   702|                  style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
   703|   703|            ],
   704|   704|          ),
   705|   705|        ),
   706|   706|        Divider(height: 1, color: ShadTheme.of(context).border),
   707|   707|        // Profile list
   708|   708|        Expanded(
   709|   709|          child: ListView.builder(
   710|   710|            padding: const EdgeInsets.all(16),
   711|   711|            itemCount: mgr.providerProfiles.length,
   712|   712|            itemBuilder: (_, i) => _profileCard(mgr.providerProfiles[i], i, mgr),
   713|   713|          ),
   714|   714|        ),
   715|   715|        // Add profile button
   716|   716|        Container(
   717|   717|          padding: const EdgeInsets.all(16),
   718|   718|          decoration: const BoxDecoration(
   719|   719|            border: Border(top: BorderSide(color: ShadTheme.of(context).border)),
   720|   720|          ),
   721|   721|          child: SizedBox(
   722|   722|            width: double.infinity,
   723|   723|            child: OutlinedButton.icon(
   724|   724|              onPressed: () => _showProfileDialog(mgr),
   725|   725|              icon: const Icon(Icons.add, size: 18),
   726|   726|              label: const Text('Add Profile'),
   727|   727|              style: OutlinedButton.styleFrom(
   728|   728|                foregroundColor: Theme.of(context).colorScheme.primary,
   729|   729|                side: BorderSide(color: Theme.of(context).colorScheme.primary),
   730|   730|                padding: const EdgeInsets.symmetric(vertical: 12),
   731|   731|              ),
   732|   732|            ),
   733|   733|          ),
   734|   734|        ),
   735|   735|      ],
   736|   736|    );
   737|   737|  }
   738|   738|
   739|   739|  Widget _profileCard(ProviderProfile profile, int index, AgentManager mgr) {
   740|   740|    return Container(
   741|   741|      margin: const EdgeInsets.only(bottom: 8),
   742|   742|      padding: const EdgeInsets.all(14),
   743|   743|      decoration: BoxDecoration(
   744|   744|        color: ShadTheme.of(context).card,
   745|   745|        borderRadius: BorderRadius.circular(10),
   746|   746|        border: Border.all(color: ShadTheme.of(context).border),
   747|   747|      ),
   748|   748|      child: Column(
   749|   749|        crossAxisAlignment: CrossAxisAlignment.start,
   750|   750|        children: [
   751|   751|          Row(
   752|   752|            children: [
   753|   753|              Icon(Icons.api, size: 18, color: Theme.of(context).colorScheme.primary),
   754|   754|              const SizedBox(width: 8),
   755|   755|              Expanded(
   756|   756|                child: Text(profile.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
   757|   757|              ),
   758|   758|              GestureDetector(
   759|   759|                onTap: () => _showProfileDialog(mgr, index: index, existing: profile),
   760|   760|                child: Icon(Icons.edit, size: 16, color: ShadTheme.of(context).mutedForeground),
   761|   761|              ),
   762|   762|              const SizedBox(width: 12),
   763|   763|              GestureDetector(
   764|   764|                onTap: () => mgr.removeProfile(index),
   765|   765|                child: Icon(Icons.delete_outline, size: 16, color: ShadTheme.of(context).destructive),
   766|   766|              ),
   767|   767|            ],
   768|   768|          ),
   769|   769|          const SizedBox(height: 8),
   770|   770|          _profileRow('URL', profile.baseUrl),
   771|   771|          _profileRow('Model', profile.model),
   772|   772|          _profileRow('Key', profile.apiKey.isNotEmpty ? '${profile.apiKey.substring(0, profile.apiKey.length > 12 ? 12 : profile.apiKey.length)}...' : '(not set)'),
   773|   773|        ],
   774|   774|      ),
   775|   775|    );
   776|   776|  }
   777|   777|
   778|   778|  Widget _profileRow(String label, String value) {
   779|   779|    return Padding(
   780|   780|      padding: const EdgeInsets.only(top: 2),
   781|   781|      child: Row(
   782|   782|        children: [
   783|   783|          SizedBox(
   784|   784|            width: 40,
   785|   785|            child: Text(label, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
   786|   786|          ),
   787|   787|          Expanded(
   788|   788|            child: Text(value, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground),
   789|   789|                overflow: TextOverflow.ellipsis),
   790|   790|          ),
   791|   791|        ],
   792|   792|      ),
   793|   793|    );
   794|   794|  }
   795|   795|
   796|   796|  void _showProfileDialog(AgentManager mgr, {int? index, ProviderProfile? existing}) {
   797|   797|    final nameCtrl = TextEditingController(text: existing?.name ?? '');
   798|   798|    final urlCtrl = TextEditingController(text: existing?.baseUrl ?? 'https://api.openai.com/v1');
   799|   799|    final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
   800|   800|    final modelCtrl = TextEditingController(text: existing?.model ?? 'gpt-4o');
   801|   801|
   802|   802|    showDialog(
   803|   803|      context: context,
   804|   804|      builder: (ctx) => AlertDialog(
   805|   805|        backgroundColor: ShadTheme.of(context).card,
   806|   806|        title: Text(existing != null ? 'Edit Profile' : 'New Profile', style: TextStyle(color: ShadTheme.of(context).foreground)),
   807|   807|        content: SizedBox(
   808|   808|          width: 400,
   809|   809|          child: SingleChildScrollView(
   810|   810|            child: Column(
   811|   811|              mainAxisSize: MainAxisSize.min,
   812|   812|              children: [
   813|   813|                _dialogField('Profile Name', 'e.g. My OpenAI', nameCtrl),
   814|   814|                const SizedBox(height: 10),
   815|   815|                _dialogField('Base URL', 'https://api.openai.com/v1', urlCtrl),
   816|   816|                const SizedBox(height: 10),
   817|   817|                _dialogField('API Key', 'sk-...', keyCtrl, obscure: true),
   818|   818|                const SizedBox(height: 10),
   819|   819|                _dialogField('Model', 'gpt-4o', modelCtrl),
   820|   820|              ],
   821|   821|            ),
   822|   822|          ),
   823|   823|        ),
   824|   824|        actions: [
   825|   825|          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground))),
   826|   826|          ElevatedButton(
   827|   827|            onPressed: () {
   828|   828|              final name = nameCtrl.text.trim();
   829|   829|              if (name.isEmpty) return;
   830|   830|              final profile = ProviderProfile(
   831|   831|                name: name,
   832|   832|                baseUrl: urlCtrl.text.trim(),
   833|   833|                apiKey: keyCtrl.text.trim(),
   834|   834|                model: modelCtrl.text.trim(),
   835|   835|              );
   836|   836|              if (existing != null && index != null) {
   837|   837|                mgr.updateProfile(index, profile);
   838|   838|              } else {
   839|   839|                mgr.addProfile(profile);
   840|   840|              }
   841|   841|              Navigator.pop(ctx);
   842|   842|            },
   843|   843|            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
   844|   844|            child: const Text('Save', style: TextStyle(color: Colors.white)),
   845|   845|          ),
   846|   846|        ],
   847|   847|      ),
   848|   848|    );
   849|   849|  }
   850|   850|
   851|   851|  Widget _dialogField(String label, String hint, TextEditingController ctrl, {bool obscure = false}) {
   852|   852|    return TextField(
   853|   853|      controller: ctrl,
   854|   854|      obscureText: obscure,
   855|   855|      decoration: InputDecoration(
   856|   856|        labelText: label,
   857|   857|        hintText: hint,
   858|   858|        filled: true, fillColor: ShadTheme.of(context).secondary,
   859|   859|        border: const OutlineInputBorder(),
   860|   860|      ),
   861|   861|      style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
   862|   862|    );
   863|   863|  }
   864|   864|
   865|   865|  // ─── MCP Config Panel ────────────────────────────────────
   866|   866|
   867|   867|  Widget _buildMcpConfigPanel(AgentManager mgr) {
   868|   868|    return const Center(
   869|   869|      child: Column(
   870|   870|        mainAxisSize: MainAxisSize.min,
   871|   871|        children: [
   872|   872|          Icon(Icons.extension, size: 48, color: ShadTheme.of(context).mutedForeground),
   873|   873|          SizedBox(height: 16),
   874|   874|          Text('MCP Configuration', style: TextStyle(fontSize: 16, color: ShadTheme.of(context).foreground)),
   875|   875|          SizedBox(height: 8),
   876|   876|          Text('MCP (Model Context Protocol) server management\nwill be available soon.',
   877|   877|              textAlign: TextAlign.center,
   878|   878|              style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
   879|   879|        ],
   880|   880|      ),
   881|   881|    );
   882|   882|  }
   883|   883|
   884|   884|  // ─── Permissions Panel ───────────────────────────────────
   885|   885|
   886|   886|  Widget _buildPermissionsPanel(AgentManager mgr) {
   887|   887|    return const Center(
   888|   888|      child: Column(
   889|   889|        mainAxisSize: MainAxisSize.min,
   890|   890|        children: [
   891|   891|          Icon(Icons.security, size: 48, color: ShadTheme.of(context).mutedForeground),
   892|   892|          SizedBox(height: 16),
   893|   893|          Text('Global Permissions', style: TextStyle(fontSize: 16, color: ShadTheme.of(context).foreground)),
   894|   894|          SizedBox(height: 8),
   895|   895|          Text('Configure agent permissions globally.\nFile access, command whitelist, and tool authorization.',
   896|   896|              textAlign: TextAlign.center,
   897|   897|              style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
   898|   898|        ],
   899|   899|      ),
   900|   900|    );
   901|   901|  }
   902|   902|
   903|   903|  // ─── LAN Settings Panel ──────────────────────────────────
   904|   904|
   905|   905|  Widget _buildLanSettingsPanel(AgentManager mgr) {
   906|   906|    return SingleChildScrollView(
   907|   907|      padding: const EdgeInsets.all(24),
   908|   908|      child: Column(
   909|   909|        crossAxisAlignment: CrossAxisAlignment.start,
   910|   910|        children: [
   911|   911|          Text('LAN Network', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
   912|   912|          const SizedBox(height: 4),
   913|   913|          Text(mgr.connected ? 'Connected to ${mgr.host}:${mgr.port}' : 'Not connected',
   914|   914|              style: TextStyle(fontSize: 13, color: mgr.connected ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground)),
   915|   915|          const SizedBox(height: 20),
   916|   916|
   917|   917|          // Join / Create tabs
   918|   918|          Row(
   919|   919|            children: [
   920|   920|              _lanTabBtn('Join LAN', 0),
   921|   921|              const SizedBox(width: 8),
   922|   922|              _lanTabBtn('Create LAN', 1),
   923|   923|            ],
   924|   924|          ),
   925|   925|          const SizedBox(height: 20),
   926|   926|
   927|   927|          if (_lanTab == 0) ...[
   928|   928|            // ── Join LAN ──
   929|   929|            _cardHeader('Join Existing Network', Icons.wifi),
   930|   930|            const SizedBox(height: 12),
   931|   931|            _labeledField('Host IP', '192.168.1.100', _waHostCtrl),
   932|   932|            const SizedBox(height: 8),
   933|   933|            _labeledField('Port', '9090', _waPortCtrl),
   934|   934|            const SizedBox(height: 8),
   935|   935|            _labeledField('Topic (optional)', 'Group identifier', _waTopicCtrl),
   936|   936|            const SizedBox(height: 16),
   937|   937|            SizedBox(
   938|   938|              width: double.infinity,
   939|   939|              child: ElevatedButton.icon(
   940|   940|                onPressed: () => mgr.joinLAN(host: _waHostCtrl.text, port: int.tryParse(_waPortCtrl.text) ?? 9090),
   941|   941|                icon: const Icon(Icons.wifi, size: 16),
   942|   942|                label: const Text('Join Network'),
   943|   943|                style: ElevatedButton.styleFrom(
   944|   944|                  backgroundColor: Theme.of(context).colorScheme.primary,
   945|   945|                  foregroundColor: Colors.white,
   946|   946|                  padding: const EdgeInsets.symmetric(vertical: 12),
   947|   947|                ),
   948|   948|              ),
   949|   949|            ),
   950|   950|          ] else ...[
   951|   951|            // ── Create LAN ──
   952|   952|            _cardHeader('Host Network', Icons.router),
   953|   953|            const SizedBox(height: 12),
   954|   954|            _labeledField('Bind Address', '0.0.0.0', _waHostCtrl),
   955|   955|            const SizedBox(height: 8),
   956|   956|            _labeledField('Port', '9090', _waPortCtrl),
   957|   957|            const SizedBox(height: 8),
   958|   958|            _labeledField('Topic (optional)', 'Group identifier', _waTopicCtrl),
   959|   959|            const SizedBox(height: 16),
   960|   960|            Row(
   961|   961|              children: [
   962|   962|                Icon(Icons.info_outline, size: 14, color: ShadTheme.of(context).mutedForeground),
   963|   963|                const SizedBox(width: 6),
   964|   964|                const Expanded(
   965|   965|                  child: Text(
   966|   966|                    'Run wenzagent_server.exe on this machine first,\nthen click Start to connect.',
   967|   967|                    style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground),
   968|   968|                  ),
   969|   969|                ),
   970|   970|              ],
   971|   971|            ),
   972|   972|            const SizedBox(height: 12),
   973|   973|            SizedBox(
   974|   974|              width: double.infinity,
   975|   975|              child: ElevatedButton.icon(
   976|   976|                onPressed: () => mgr.createLAN(host: '127.0.0.1', port: int.tryParse(_waPortCtrl.text) ?? 9090),
   977|   977|                icon: const Icon(Icons.play_arrow, size: 16),
   978|   978|                label: const Text('Start & Connect'),
   979|   979|                style: ElevatedButton.styleFrom(
   980|   980|                  backgroundColor: const Color(0xFF4CAF50),
   981|   981|                  foregroundColor: Colors.white,
   982|   982|                  padding: const EdgeInsets.symmetric(vertical: 12),
   983|   983|                ),
   984|   984|              ),
   985|   985|            ),
   986|   986|          ],
   987|   987|        ],
   988|   988|      ),
   989|   989|    );
   990|   990|  }
   991|   991|
   992|   992|  Widget _lanTabBtn(String label, int index) {
   993|   993|    final active = _lanTab == index;
   994|   994|    return GestureDetector(
   995|   995|      onTap: () => setState(() => _lanTab = index),
   996|   996|      child: Container(
   997|   997|        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
   998|   998|        decoration: BoxDecoration(
   999|   999|          color: active ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).secondary,
  1000|  1000|          borderRadius: BorderRadius.circular(8),
  1001|  1001|        ),
  1002|  1002|        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
  1003|  1003|            color: active ? Colors.white : ShadTheme.of(context).mutedForeground)),
  1004|  1004|      ),
  1005|  1005|    );
  1006|  1006|  }
  1007|  1007|
  1008|  1008|  Widget _cardHeader(String title, IconData icon) {
  1009|  1009|    return Row(
  1010|  1010|      children: [
  1011|  1011|        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
  1012|  1012|        const SizedBox(width: 8),
  1013|  1013|        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
  1014|  1014|      ],
  1015|  1015|    );
  1016|  1016|  }
  1017|  1017|
  1018|  1018|  Widget _labeledField(String label, String hint, TextEditingController ctrl, {bool obscure = false}) {
  1019|  1019|    return Column(
  1020|  1020|      crossAxisAlignment: CrossAxisAlignment.start,
  1021|  1021|      children: [
  1022|  1022|        Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
  1023|  1023|        const SizedBox(height: 4),
  1024|  1024|        TextField(
  1025|  1025|          controller: ctrl,
  1026|  1026|          obscureText: obscure,
  1027|  1027|          decoration: InputDecoration(
  1028|  1028|            hintText: hint,
  1029|  1029|            filled: true, fillColor: ShadTheme.of(context).secondary,
  1030|  1030|            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
  1031|  1031|            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  1032|  1032|            isDense: true,
  1033|  1033|          ),
  1034|  1034|          style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
  1035|  1035|        ),
  1036|  1036|      ],
  1037|  1037|    );
  1038|  1038|  }
  1039|  1039|
  1040|  1040|  // ══════════════════════════════════════════════════════════
  1041|  1041|  // Content Area (Empty State or Chat)
  1042|  1042|  // ══════════════════════════════════════════════════════════
  1043|  1043|
  1044|  1044|  Widget _buildContentArea(AgentManager mgr) {
  1045|  1045|    if (_showSettings) {
  1046|  1046|      return _buildSettingsPage(mgr);
  1047|  1047|    }
  1048|  1048|    if (mgr.activeEmployeeId == null) {
  1049|  1049|      return _buildEmptyState();
  1050|  1050|    }
  1051|  1051|    return _buildChatPanel(mgr);
  1052|  1052|  }
  1053|  1053|
  1054|  1054|  Widget _buildEmptyState() {
  1055|  1055|    return Center(
  1056|  1056|      child: Column(
  1057|  1057|        mainAxisSize: MainAxisSize.min,
  1058|  1058|        children: [
  1059|  1059|          Icon(Icons.chat_bubble_outline, size: 56, color: ShadTheme.of(context).mutedForeground.withAlpha(100)),
  1060|  1060|          const SizedBox(height: 16),
  1061|  1061|          const Text('Select a conversation to start chatting',
  1062|  1062|              style: TextStyle(fontSize: 15, color: ShadTheme.of(context).mutedForeground)),
  1063|  1063|          const SizedBox(height: 6),
  1064|  1064|          const Text('Messages are routed through the WenzAgent LAN network',
  1065|  1065|              style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
  1066|  1066|        ],
  1067|  1067|      ),
  1068|  1068|    );
  1069|  1069|  }
  1070|  1070|
  1071|  1071|  // ══════════════════════════════════════════════════════════
  1072|  1072|  // Chat Panel
  1073|  1073|  // ══════════════════════════════════════════════════════════
  1074|  1074|
  1075|  1075|  Widget _buildChatPanel(AgentManager mgr) {
  1076|  1076|    final statusColor = mgr.activeAgentStatus == 'streaming'
  1077|  1077|        ? const Color(0xFF4CAF50)
  1078|  1078|        : mgr.activeAgentStatus == 'processing'
  1079|  1079|            ? const Color(0xFFFFC107)
  1080|  1080|            : const Color(0xFF888888);
  1081|  1081|
  1082|  1082|    return Column(
  1083|  1083|      children: [
  1084|  1084|        // Agent header
  1085|  1085|        Container(
  1086|  1086|          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  1087|  1087|          color: ShadTheme.of(context).card,
  1088|  1088|          child: Row(
  1089|  1089|            children: [
  1090|  1090|              GestureDetector(
  1091|  1091|                onTap: () => mgr.closeAgent(),
  1092|  1092|                child: Icon(Icons.arrow_back, size: 20, color: ShadTheme.of(context).mutedForeground),
  1093|  1093|              ),
  1094|  1094|              const SizedBox(width: 10),
  1095|  1095|              Icon(Icons.smart_toy, size: 20, color: ShadTheme.of(context).foreground),
  1096|  1096|              const SizedBox(width: 8),
  1097|  1097|              Expanded(
  1098|  1098|                child: Text(
  1099|  1099|                  mgr.activeEmployeeName ?? 'Agent',
  1100|  1100|                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ShadTheme.of(context).foreground),
  1101|  1101|                ),
  1102|  1102|              ),
  1103|  1103|              Container(
  1104|  1104|                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  1105|  1105|                decoration: BoxDecoration(
  1106|  1106|                  color: statusColor.withAlpha(30),
  1107|  1107|                  borderRadius: BorderRadius.circular(4),
  1108|  1108|                  border: Border.all(color: statusColor.withAlpha(80)),
  1109|  1109|                ),
  1110|  1110|                child: Text(mgr.activeAgentStatus.toUpperCase(),
  1111|  1111|                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
  1112|  1112|              ),
  1113|  1113|              const SizedBox(width: 8),
  1114|  1114|              GestureDetector(
  1115|  1115|                onTap: mgr.interruptAgent,
  1116|  1116|                child: Icon(Icons.stop, size: 18, color: ShadTheme.of(context).mutedForeground),
  1117|  1117|              ),
  1118|  1118|            ],
  1119|  1119|          ),
  1120|  1120|        ),
  1121|  1121|        Divider(height: 1, color: ShadTheme.of(context).border),
  1122|  1122|        // Messages
  1123|  1123|        Expanded(
  1124|  1124|          child: ListView.builder(
  1125|  1125|            controller: _scrollCtrl,
  1126|  1126|            padding: const EdgeInsets.all(16),
  1127|  1127|            itemCount: mgr.activeMessages.length,
  1128|  1128|            itemBuilder: (_, i) => _msgBubble(mgr.activeMessages[i]),
  1129|  1129|          ),
  1130|  1130|        ),
  1131|  1131|        Divider(height: 1, color: ShadTheme.of(context).border),
  1132|  1132|        // Profile switcher
  1133|  1133|        if (mgr.activeProfile != null)
  1134|  1134|          Padding(
  1135|  1135|            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
  1136|  1136|            child: Align(
  1137|  1137|              alignment: Alignment.centerLeft,
  1138|  1138|              child: GestureDetector(
  1139|  1139|                onTap: () {
  1140|  1140|                  final dummy = _DummyAgent(mgr.activeEmployeeId ?? '', mgr.activeEmployeeName ?? '');
  1141|  1141|                  _showProfilePicker(dummy, mgr);
  1142|  1142|                },
  1143|  1143|                child: Container(
  1144|  1144|                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  1145|  1145|                  decoration: BoxDecoration(
  1146|  1146|                    color: Theme.of(context).colorScheme.primary.withAlpha(20),
  1147|  1147|                    borderRadius: BorderRadius.circular(12),
  1148|  1148|                    border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(50)),
  1149|  1149|                  ),
  1150|  1150|                  child: Row(
  1151|  1151|                    mainAxisSize: MainAxisSize.min,
  1152|  1152|                    children: [
  1153|  1153|                      Icon(Icons.api, size: 13, color: Theme.of(context).colorScheme.primary),
  1154|  1154|                      const SizedBox(width: 5),
  1155|  1155|                      Text(mgr.activeProfile!.name,
  1156|  1156|                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
  1157|  1157|                      const SizedBox(width: 6),
  1158|  1158|                      Icon(Icons.swap_horiz, size: 12, color: ShadTheme.of(context).mutedForeground),
  1159|  1159|                      const SizedBox(width: 4),
  1160|  1160|                      Text(mgr.activeProfile!.model,
  1161|  1161|                          style: TextStyle(fontSize: 10, color: ShadTheme.of(context).mutedForeground)),
  1162|  1162|                    ],
  1163|  1163|                  ),
  1164|  1164|                ),
  1165|  1165|              ),
  1166|  1166|            ),
  1167|  1167|          ),
  1168|  1168|        // Input
  1169|  1169|        _buildChatInput(mgr),
  1170|  1170|      ],
  1171|  1171|    );
  1172|  1172|  }
  1173|  1173|
  1174|  1174|  Widget _msgBubble(Map<String, dynamic> msg) {
  1175|  1175|    final isUser = (msg['role'] ?? 'user') == 'user';
  1176|  1176|    final content = msg['content']?.toString() ?? '';
  1177|  1177|    final type = msg['type']?.toString() ?? 'text';
  1178|  1178|
  1179|  1179|    return Align(
  1180|  1180|      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
  1181|  1181|      child: Container(
  1182|  1182|        margin: const EdgeInsets.only(bottom: 8),
  1183|  1183|        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  1184|  1184|        constraints: const BoxConstraints(maxWidth: 520),
  1185|  1185|        decoration: BoxDecoration(
  1186|  1186|          color: isUser ? Theme.of(context).colorScheme.primary.withAlpha(25) : ShadTheme.of(context).secondary,
  1187|  1187|          borderRadius: BorderRadius.circular(12),
  1188|  1188|        ),
  1189|  1189|        child: Column(
  1190|  1190|          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
  1191|  1191|          children: [
  1192|  1192|            if (type == 'functionCall')
  1193|  1193|              _toolLabel('TOOL CALL'),
  1194|  1194|            if (type == 'functionResult')
  1195|  1195|              _toolLabel('TOOL RESULT'),
  1196|  1196|            Text(content, style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground, height: 1.5)),
  1197|  1197|            if (msg['toolResult'] != null && msg['toolResult'].toString().isNotEmpty)
  1198|  1198|              Container(
  1199|  1199|                margin: const EdgeInsets.only(top: 6),
  1200|  1200|                padding: const EdgeInsets.all(8),
  1201|  1201|                decoration: BoxDecoration(color: Colors.black.withAlpha(50), borderRadius: BorderRadius.circular(6)),
  1202|  1202|                child: Text(msg['toolResult'].toString(), maxLines: 5, overflow: TextOverflow.ellipsis,
  1203|  1203|                    style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
  1204|  1204|              ),
  1205|  1205|          ],
  1206|  1206|        ),
  1207|  1207|      ),
  1208|  1208|    );
  1209|  1209|  }
  1210|  1210|
  1211|  1211|  Widget _toolLabel(String text) {
  1212|  1212|    return Container(
  1213|  1213|      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  1214|  1214|      margin: const EdgeInsets.only(bottom: 4),
  1215|  1215|      decoration: BoxDecoration(
  1216|  1216|        color: ShadTheme.of(context).mutedForeground.withAlpha(25),
  1217|  1217|        borderRadius: BorderRadius.circular(4),
  1218|  1218|      ),
  1219|  1219|      child: Text(text, style: TextStyle(fontSize: 9, color: ShadTheme.of(context).mutedForeground)),
  1220|  1220|    );
  1221|  1221|  }
  1222|  1222|
  1223|  1223|  Widget _buildChatInput(AgentManager mgr) {
  1224|  1224|    return Container(
  1225|  1225|      padding: const EdgeInsets.all(12),
  1226|  1226|      color: ShadTheme.of(context).card,
  1227|  1227|      child: Row(
  1228|  1228|        children: [
  1229|  1229|          Expanded(
  1230|  1230|            child: TextField(
  1231|  1231|              controller: _msgCtrl,
  1232|  1232|              decoration: const InputDecoration(
  1233|  1233|                hintText: 'Send message to agent...',
  1234|  1234|                filled: true, fillColor: ShadTheme.of(context).secondary,
  1235|  1235|                border: OutlineInputBorder(),
  1236|  1236|                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  1237|  1237|                isDense: true,
  1238|  1238|              ),
  1239|  1239|              style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground),
  1240|  1240|              maxLines: 3, minLines: 1,
  1241|  1241|              onSubmitted: (t) => _send(t, mgr),
  1242|  1242|            ),
  1243|  1243|          ),
  1244|  1244|          const SizedBox(width: 8),
  1245|  1245|          GestureDetector(
  1246|  1246|            onTap: () => _send(_msgCtrl.text, mgr),
  1247|  1247|            child: Container(
  1248|  1248|              width: 40, height: 40,
  1249|  1249|              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
  1250|  1250|              child: const Icon(Icons.send, size: 18, color: Colors.white),
  1251|  1251|            ),
  1252|  1252|          ),
  1253|  1253|        ],
  1254|  1254|      ),
  1255|  1255|    );
  1256|  1256|  }
  1257|  1257|
  1258|  1258|  void _send(String text, AgentManager mgr) {
  1259|  1259|    final t = text.trim();
  1260|  1260|    if (t.isEmpty) return;
  1261|  1261|    _msgCtrl.clear();
  1262|  1262|    mgr.sendMessage(t);
  1263|  1263|    WidgetsBinding.instance.addPostFrameCallback((_) {
  1264|  1264|      if (_scrollCtrl.hasClients) {
  1265|  1265|        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
  1266|  1266|            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  1267|  1267|      }
  1268|  1268|    });
  1269|  1269|  }
  1270|  1270|
  1271|  1271|  void _selectAgent(dynamic agent, AgentManager mgr) {
  1272|  1272|    final profiles = mgr.providerProfiles;
  1273|  1273|    if (profiles.isEmpty) return;
  1274|  1274|
  1275|  1275|    // Check if this employee has a last-used profile
  1276|  1276|    final lastIdx = mgr.getLastProfileIndex(agent.uuid as String);
  1277|  1277|    if (lastIdx != null && lastIdx < profiles.length) {
  1278|  1278|      // Auto-use the last profile
  1279|  1279|      mgr.openAgentWithProfile(agent.uuid, agent.name, lastIdx);
  1280|  1280|      return;
  1281|  1281|    }
  1282|  1282|
  1283|  1283|    // Single profile: auto-select
  1284|  1284|    if (profiles.length == 1) {
  1285|  1285|      mgr.openAgentWithProfile(agent.uuid, agent.name, 0);
  1286|  1286|      return;
  1287|  1287|    }
  1288|  1288|
  1289|  1289|    // Multiple profiles, no last-used: show picker
  1290|  1290|    _showProfilePicker(agent, mgr);
  1291|  1291|  }
  1292|  1292|
  1293|  1293|  void _showProfilePicker(dynamic agent, AgentManager mgr) {
  1294|  1294|    final profiles = mgr.providerProfiles;
  1295|  1295|    showDialog(
  1296|  1296|      context: context,
  1297|  1297|      builder: (ctx) => AlertDialog(
  1298|  1298|        backgroundColor: ShadTheme.of(context).card,
  1299|  1299|        title: Text('Select Profile for "${agent.name}"', style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 15)),
  1300|  1300|        content: SizedBox(
  1301|  1301|          width: 350,
  1302|  1302|          child: ListView.builder(
  1303|  1303|            shrinkWrap: true,
  1304|  1304|            itemCount: profiles.length,
  1305|  1305|            itemBuilder: (_, i) {
  1306|  1306|              final p = profiles[i];
  1307|  1307|              return ListTile(
  1308|  1308|                leading: Icon(Icons.api, color: Theme.of(context).colorScheme.primary),
  1309|  1309|                title: Text(p.name, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 14)),
  1310|  1310|                subtitle: Text('${p.model}  •  ${p.baseUrl}',
  1311|  1311|                    style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
  1312|  1312|                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  1313|  1313|                tileColor: ShadTheme.of(context).secondary,
  1314|  1314|                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  1315|  1315|                onTap: () {
  1316|  1316|                  Navigator.pop(ctx);
  1317|  1317|                  mgr.openAgentWithProfile(agent.uuid, agent.name, i);
  1318|  1318|                },
  1319|  1319|              );
  1320|  1320|            },
  1321|  1321|          ),
  1322|  1322|        ),
  1323|  1323|      ),
  1324|  1324|    );
  1325|  1325|  }
  1326|  1326|}
  1327|  1327|
  1328|  1328|class _DummyAgent {
  1329|  1329|  final String uuid;
  1330|  1330|  final String name;
  1331|  1331|  _DummyAgent(this.uuid, this.name);
  1332|  1332|}
  1333|  1333|