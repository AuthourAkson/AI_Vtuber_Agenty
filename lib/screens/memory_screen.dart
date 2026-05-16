     1|     1|import 'package:flutter/material.dart';
     2|     2|import 'package:provider/provider.dart';
     3|     3|import '../app.dart';
     4|     4|import '../providers/chat_provider.dart';
     5|     5|
     6|     6|/// Memory page — matches LocalAIVtuber2's SessionList / MemoryPage.
     7|     7|/// Memory page — matches LocalAIVtuber2's SessionList / MemoryPage.
     8|     8|class MemoryScreen extends StatefulWidget {
     9|     9|  final VoidCallback? onNavigateHome;
    10|    10|  const MemoryScreen({super.key, this.onNavigateHome});
    11|    11|
    12|    12|  @override
    13|    13|  State<MemoryScreen> createState() => _MemoryScreenState();
    14|    14|}
    15|    15|
    16|    16|class _MemoryScreenState extends State<MemoryScreen> {
    17|    17|  final _searchCtrl = TextEditingController();
    18|    18|  String _searchTerm = '';
    19|    19|  bool _loading = false;
    20|    20|
    21|    21|  @override
    22|    22|  void initState() {
    23|    23|    super.initState();
    24|    24|    // Load sessions into cache on first open
    25|    25|    WidgetsBinding.instance.addPostFrameCallback((_) {
    26|    26|      final chat = context.read<ChatProvider>();
    27|    27|      chat.sessionManager.loadSessions().then((_) {
    28|    28|        if (mounted) setState(() {});
    29|    29|      });
    30|    30|    });
    31|    31|  }
    32|    32|
    33|    33|  @override
    34|    34|  void dispose() {
    35|    35|    _searchCtrl.dispose();
    36|    36|    super.dispose();
    37|    37|  }
    38|    38|
    39|    39|  @override
    40|    40|  Widget build(BuildContext context) {
    41|    41|    return Consumer<ChatProvider>(
    42|    42|      builder: (context, chat, _) {
    43|    43|        final sessions = chat.sessions;
    44|    44|
    45|    45|        // Filter by search term
    46|    46|        final filtered = sessions.where((s) {
    47|    47|          final title = (s['title'] as String?) ?? '';
    48|    48|          return title.toLowerCase().contains(_searchTerm.toLowerCase());
    49|    49|        }).toList();
    50|    50|
    51|    51|        return SingleChildScrollView(
    52|    52|          padding: const EdgeInsets.only(top: 40, left: 48, right: 48, bottom: 40),
    53|    53|          child: ConstrainedBox(
    54|    54|            constraints: const BoxConstraints(maxWidth: 960),
    55|    55|            child: Column(
    56|    56|              crossAxisAlignment: CrossAxisAlignment.start,
    57|    57|              children: [
    58|    58|                // Page header — matches LAV2 style
    59|    59|                const Text(
    60|    60|                  'Chat Sessions',
    61|    61|                  style: TextStyle(
    62|    62|                    fontSize: 28,
    63|    63|                    fontWeight: FontWeight.bold,
    64|    64|                    color: ShadTheme.of(context).foreground,
    65|    65|                  ),
    66|    66|                ),
    67|    67|                const SizedBox(height: 4),
    68|    68|                const Text(
    69|    69|                  'Manage and review your conversation sessions',
    70|    70|                  style: TextStyle(
    71|    71|                    fontSize: 14,
    72|    72|                    color: ShadTheme.of(context).mutedForeground,
    73|    73|                  ),
    74|    74|                ),
    75|    75|                const SizedBox(height: 24),
    76|    76|
    77|    77|                // Search & filter bar
    78|    78|                Container(
    79|    79|                  padding: const EdgeInsets.all(16),
    80|    80|                  decoration: BoxDecoration(
    81|    81|                    color: ShadTheme.of(context).card,
    82|    82|                    borderRadius: BorderRadius.circular(8),
    83|    83|                    border: Border.all(color: ShadTheme.of(context).border),
    84|    84|                    boxShadow: const [
    85|    85|                      BoxShadow(
    86|    86|                        color: Color(0x08000000),
    87|    87|                        blurRadius: 2,
    88|    88|                        offset: Offset(0, 1),
    89|    89|                      ),
    90|    90|                    ],
    91|    91|                  ),
    92|    92|                  child: Row(
    93|    93|                    children: [
    94|    94|                      // Search field
    95|    95|                      Expanded(
    96|    96|                        child: SizedBox(
    97|    97|                          height: 36,
    98|    98|                          child: TextField(
    99|    99|                            controller: _searchCtrl,
   100|   100|                            style: const TextStyle(
   101|   101|                              fontSize: 13,
   102|   102|                              color: ShadTheme.of(context).foreground,
   103|   103|                            ),
   104|   104|                            decoration: InputDecoration(
   105|   105|                              hintText: 'Search sessions...',
   106|   106|                              hintStyle: const TextStyle(
   107|   107|                                color: ShadTheme.of(context).mutedForeground,
   108|   108|                                fontSize: 13,
   109|   109|                              ),
   110|   110|                              prefixIcon: const Icon(
   111|   111|                                Icons.search,
   112|   112|                                size: 16,
   113|   113|                                color: ShadTheme.of(context).mutedForeground,
   114|   114|                              ),
   115|   115|                              filled: true,
   116|   116|                              fillColor: ShadTheme.of(context).secondary,
   117|   117|                              contentPadding: const EdgeInsets.symmetric(
   118|   118|                                horizontal: 12,
   119|   119|                                vertical: 8,
   120|   120|                              ),
   121|   121|                              border: OutlineInputBorder(
   122|   122|                                borderRadius: BorderRadius.circular(6),
   123|   123|                                borderSide: BorderSide.none,
   124|   124|                              ),
   125|   125|                              enabledBorder: OutlineInputBorder(
   126|   126|                                borderRadius: BorderRadius.circular(6),
   127|   127|                                borderSide: BorderSide(color: ShadTheme.of(context).input),
   128|   128|                              ),
   129|   129|                            ),
   130|   130|                            onChanged: (v) => setState(() => _searchTerm = v),
   131|   131|                          ),
   132|   132|                        ),
   133|   133|                      ),
   134|   134|                      const SizedBox(width: 8),
   135|   135|                      // Refresh button
   136|   136|                      GestureDetector(
   137|   137|                        onTap: _loading
   138|   138|                            ? null
   139|   139|                            : () async {
   140|   140|                                setState(() => _loading = true);
   141|   141|                                await chat.sessionManager.loadSessions();
   142|   142|                                if (mounted) setState(() => _loading = false);
   143|   143|                              },
   144|   144|                        child: Container(
   145|   145|                          width: 36,
   146|   146|                          height: 36,
   147|   147|                          decoration: BoxDecoration(
   148|   148|                            borderRadius: BorderRadius.circular(6),
   149|   149|                            border: Border.all(color: ShadTheme.of(context).input),
   150|   150|                          ),
   151|   151|                          child: _loading
   152|   152|                              ? const Center(
   153|   153|                                  child: SizedBox(
   154|   154|                                    width: 14,
   155|   155|                                    height: 14,
   156|   156|                                    child: CircularProgressIndicator(
   157|   157|                                      strokeWidth: 2,
   158|   158|                                      color: ShadTheme.of(context).mutedForeground,
   159|   159|                                    ),
   160|   160|                                  ),
   161|   161|                                )
   162|   162|                              : const Icon(
   163|   163|                                  Icons.refresh,
   164|   164|                                  size: 16,
   165|   165|                                  color: ShadTheme.of(context).mutedForeground,
   166|   166|                                ),
   167|   167|                        ),
   168|   168|                      ),
   169|   169|                    ],
   170|   170|                  ),
   171|   171|                ),
   172|   172|                const SizedBox(height: 20),
   173|   173|
   174|   174|                // Session cards
   175|   175|                if (filtered.isEmpty)
   176|   176|                  Center(
   177|   177|                    child: Padding(
   178|   178|                      padding: const EdgeInsets.symmetric(vertical: 48),
   179|   179|                      child: Column(
   180|   180|                        children: [
   181|   181|                          const Icon(
   182|   182|                            Icons.storage_rounded,
   183|   183|                            size: 48,
   184|   184|                            color: ShadTheme.of(context).mutedForeground,
   185|   185|                          ),
   186|   186|                          const SizedBox(height: 12),
   187|   187|                          const Text(
   188|   188|                            'No sessions found',
   189|   189|                            style: TextStyle(
   190|   190|                              fontSize: 16,
   191|   191|                              fontWeight: FontWeight.w500,
   192|   192|                              color: ShadTheme.of(context).foreground,
   193|   193|                            ),
   194|   194|                          ),
   195|   195|                          const SizedBox(height: 4),
   196|   196|                          const Text(
   197|   197|                            'Try adjusting your search criteria',
   198|   198|                            style: TextStyle(
   199|   199|                              fontSize: 13,
   200|   200|                              color: ShadTheme.of(context).mutedForeground,
   201|   201|                            ),
   202|   202|                          ),
   203|   203|                        ],
   204|   204|                      ),
   205|   205|                    ),
   206|   206|                  )
   207|   207|                else
   208|   208|                  ...filtered.map((session) {
   209|   209|                    final id = session['id'] as String? ?? '';
   210|   210|                    final title = (session['title'] as String?) ?? 'Untitled';
   211|   211|                    final createdAt =
   212|   212|                        (session['created_at'] as String?) ?? '';
   213|   213|                    return _sessionCard(
   214|   214|                      id: id,
   215|   215|                      title: title,
   216|   216|                      createdAt: createdAt,
   217|   217|                      chat: chat,
   218|   218|                    );
   219|   219|                  }),
   220|   220|              ],
   221|   221|            ),
   222|   222|          ),
   223|   223|        );
   224|   224|      },
   225|   225|    );
   226|   226|  }
   227|   227|
   228|   228|  Widget _sessionCard({
   229|   229|    required String id,
   230|   230|    required String title,
   231|   231|    required String createdAt,
   232|   232|    required ChatProvider chat,
   233|   233|  }) {
   234|   234|    return Container(
   235|   235|      margin: const EdgeInsets.only(bottom: 12),
   236|   236|      padding: const EdgeInsets.all(16),
   237|   237|      decoration: BoxDecoration(
   238|   238|        color: ShadTheme.of(context).card,
   239|   239|        borderRadius: BorderRadius.circular(8),
   240|   240|        border: Border.all(color: ShadTheme.of(context).border),
   241|   241|        boxShadow: const [
   242|   242|          BoxShadow(
   243|   243|            color: Color(0x08000000),
   244|   244|            blurRadius: 2,
   245|   245|            offset: Offset(0, 1),
   246|   246|          ),
   247|   247|        ],
   248|   248|      ),
   249|   249|      child: Row(
   250|   250|        children: [
   251|   251|          // Session info
   252|   252|          Expanded(
   253|   253|            child: Column(
   254|   254|              crossAxisAlignment: CrossAxisAlignment.start,
   255|   255|              children: [
   256|   256|                Text(
   257|   257|                  title,
   258|   258|                  style: const TextStyle(
   259|   259|                    fontSize: 16,
   260|   260|                    fontWeight: FontWeight.w600,
   261|   261|                    color: ShadTheme.of(context).foreground,
   262|   262|                  ),
   263|   263|                ),
   264|   264|                if (createdAt.isNotEmpty) ...[
   265|   265|                  const SizedBox(height: 4),
   266|   266|                  Text(
   267|   267|                    'Created: $createdAt',
   268|   268|                    style: const TextStyle(
   269|   269|                      fontSize: 12,
   270|   270|                      color: ShadTheme.of(context).mutedForeground,
   271|   271|                    ),
   272|   272|                  ),
   273|   273|                ],
   274|   274|              ],
   275|   275|            ),
   276|   276|          ),
   277|   277|          // Actions
   278|   278|          Row(
   279|   279|            mainAxisSize: MainAxisSize.min,
   280|   280|            children: [
   281|   281|              // Load button
   282|   282|              GestureDetector(
   283|   283|                onTap: () async {
   284|   284|                  await chat.loadSession(id);
   285|   285|                  widget.onNavigateHome?.call();
   286|   286|                },
   287|   287|                child: Container(
   288|   288|                  padding: const EdgeInsets.symmetric(
   289|   289|                    horizontal: 10,
   290|   290|                    vertical: 4,
   291|   291|                  ),
   292|   292|                  decoration: BoxDecoration(
   293|   293|                    borderRadius: BorderRadius.circular(4),
   294|   294|                    border: Border.all(color: ShadTheme.of(context).input),
   295|   295|                  ),
   296|   296|                  child: const Text(
   297|   297|                    'Load',
   298|   298|                    style: TextStyle(
   299|   299|                      fontSize: 12,
   300|   300|                      color: ShadTheme.of(context).foreground,
   301|   301|                    ),
   302|   302|                  ),
   303|   303|                ),
   304|   304|              ),
   305|   305|              const SizedBox(width: 6),
   306|   306|              // Delete button
   307|   307|              GestureDetector(
   308|   308|                onTap: () async {
   309|   309|                  await chat.sessionManager.deleteSession(id);
   310|   310|                  setState(() {});
   311|   311|                },
   312|   312|                child: const Icon(
   313|   313|                  Icons.close,
   314|   314|                  size: 16,
   315|   315|                  color: ShadTheme.of(context).mutedForeground,
   316|   316|                ),
   317|   317|              ),
   318|   318|            ],
   319|   319|          ),
   320|   320|        ],
   321|   321|      ),
   322|   322|    );
   323|   323|  }
   324|   324|}
   325|   325|