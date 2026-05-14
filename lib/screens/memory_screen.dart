import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/chat_provider.dart';

/// Memory page — matches LocalAIVtuber2's SessionList / MemoryPage.
/// Memory page — matches LocalAIVtuber2's SessionList / MemoryPage.
class MemoryScreen extends StatefulWidget {
  final VoidCallback? onNavigateHome;
  const MemoryScreen({super.key, this.onNavigateHome});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _searchCtrl = TextEditingController();
  String _searchTerm = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // Load sessions into cache on first open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chat = context.read<ChatProvider>();
      chat.sessionManager.loadSessions().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        final sessions = chat.sessions;

        // Filter by search term
        final filtered = sessions.where((s) {
          final title = (s['title'] as String?) ?? '';
          return title.toLowerCase().contains(_searchTerm.toLowerCase());
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.only(top: 40, left: 48, right: 48, bottom: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page header — matches LAV2 style
                const Text(
                  'Chat Sessions',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: ShadColors.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manage and review your conversation sessions',
                  style: TextStyle(
                    fontSize: 14,
                    color: ShadColors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 24),

                // Search & filter bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ShadColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ShadColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x08000000),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Search field
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(
                              fontSize: 13,
                              color: ShadColors.foreground,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search sessions...',
                              hintStyle: const TextStyle(
                                color: ShadColors.mutedForeground,
                                fontSize: 13,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 16,
                                color: ShadColors.mutedForeground,
                              ),
                              filled: true,
                              fillColor: ShadColors.secondary,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: ShadColors.input),
                              ),
                            ),
                            onChanged: (v) => setState(() => _searchTerm = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Refresh button
                      GestureDetector(
                        onTap: _loading
                            ? null
                            : () async {
                                setState(() => _loading = true);
                                await chat.sessionManager.loadSessions();
                                if (mounted) setState(() => _loading = false);
                              },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ShadColors.input),
                          ),
                          child: _loading
                              ? const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: ShadColors.mutedForeground,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh,
                                  size: 16,
                                  color: ShadColors.mutedForeground,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Session cards
                if (filtered.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.storage_rounded,
                            size: 48,
                            color: ShadColors.mutedForeground,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No sessions found',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: ShadColors.foreground,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Try adjusting your search criteria',
                            style: TextStyle(
                              fontSize: 13,
                              color: ShadColors.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...filtered.map((session) {
                    final id = session['id'] as String? ?? '';
                    final title = (session['title'] as String?) ?? 'Untitled';
                    final createdAt =
                        (session['created_at'] as String?) ?? '';
                    return _sessionCard(
                      id: id,
                      title: title,
                      createdAt: createdAt,
                      chat: chat,
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sessionCard({
    required String id,
    required String title,
    required String createdAt,
    required ChatProvider chat,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShadColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ShadColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Session info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ShadColors.foreground,
                  ),
                ),
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Created: $createdAt',
                    style: const TextStyle(
                      fontSize: 12,
                      color: ShadColors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Load button
              GestureDetector(
                onTap: () async {
                  await chat.loadSession(id);
                  widget.onNavigateHome?.call();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: ShadColors.input),
                  ),
                  child: const Text(
                    'Load',
                    style: TextStyle(
                      fontSize: 12,
                      color: ShadColors.foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Delete button
              GestureDetector(
                onTap: () async {
                  await chat.sessionManager.deleteSession(id);
                  setState(() {});
                },
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: ShadColors.mutedForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
