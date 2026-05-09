import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.memory, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 8),
                  const Text('Memory & Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  // Memory retrieval toggle
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Memory:', style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                      Switch(
                        value: chat.enableMemoryRetrieval,
                        onChanged: (v) => chat.enableMemoryRetrieval = v,
                        activeColor: const Color(0xFF4CAF50),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadSessions,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
            // Memory context display
            if (chat.retrievedContext.isNotEmpty)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2A1E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2C4A2C)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Retrieved Context', style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(chat.retrievedContext, style: const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB))),
                  ],
                ),
              ),
            // Session list
            Expanded(
              child: _sessions.isEmpty
                  ? const Center(child: Text('No sessions yet', style: TextStyle(color: Color(0xFF888888))))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      itemBuilder: (_, index) {
                        final s = _sessions[index];
                        final id = s['id'] as String;
                        final title = s['title'] as String? ?? 'Untitled';
                        final isActive = chat.sessionId == id;
                        return Card(
                          color: isActive ? const Color(0xFF1E3A1E) : const Color(0xFF1E1E1E),
                          child: ListTile(
                            leading: const Icon(Icons.chat_bubble_outline, color: Color(0xFF888888)),
                            title: Text(title),
                            subtitle: Text(id, style: const TextStyle(fontSize: 11, color: Color(0xFF666666))),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 18),
                                  onPressed: () async {
                                    await chat.api.deleteSession(id);
                                    _loadSessions();
                                  },
                                ),
                              ],
                            ),
                            onTap: () => chat.setSessionId(id),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final chat = context.read<ChatProvider>();
      _sessions = await chat.api.listSessions();
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSessions());
  }
}
