import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/llm_monitor.dart';

/// Chat page — matches LocalAIVtuber2's llmPage.tsx + chatbox.tsx layout.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _sessionPanelOpen = false;
  bool _settingsPanelOpen = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChatProvider, SettingsProvider>(
      builder: (context, chat, sp, _) {
        _scrollToBottom();
        final showMonitor = sp.settings.showMonitor;

        return ClipRect(
          child: Stack(
            children: [
              // ── Main content ──
              Column(
                children: [
                  _buildHeader(chat),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: _buildChatMessages(chat)),
                        if (showMonitor)
                          Container(
                            width: 380,
                            decoration: const BoxDecoration(
                              border: Border(left: BorderSide(color: ShadColors.border)),
                            ),
                            child: const LLMMonitor(),
                          ),
                      ],
                    ),
                  ),
                  ChatInput(
                    onSend: (text) => chat.sendMessage(text),
                    isStreaming: chat.isStreaming,
                  ),
                ],
              ),

              // ── Left: Session panel (slides in) ──
              if (_sessionPanelOpen)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _SessionPanel(chat: chat, onClose: () => setState(() => _sessionPanelOpen = false)),
                ),

              // ── Right: Settings panel (slides in) ──
              if (_settingsPanelOpen)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _SettingsPanel(
                    sp: sp,
                    chat: chat,
                    onClose: () => setState(() => _settingsPanelOpen = false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Header ──

  Widget _buildHeader(ChatProvider chat) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ShadColors.border)),
      ),
      child: Row(
        children: [
          // Session toggle
          GestureDetector(
            onTap: () => setState(() => _sessionPanelOpen = !_sessionPanelOpen),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _sessionPanelOpen ? ShadColors.primary.withAlpha(25) : ShadColors.secondary,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.menu, size: 14, color: ShadColors.mutedForeground),
                  const SizedBox(width: 4),
                  Text(
                    chat.activeSessionTitle.isNotEmpty ? chat.activeSessionTitle : 'Chat',
                    style: const TextStyle(fontSize: 13, color: ShadColors.foreground),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // New session
          GestureDetector(
            onTap: chat.isStreaming ? null : () => chat.createNewSession(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ShadColors.input),
              ),
              child: const Icon(Icons.add, size: 14, color: ShadColors.mutedForeground),
            ),
          ),
          const SizedBox(width: 6),
          // Settings toggle
          GestureDetector(
            onTap: () => setState(() => _settingsPanelOpen = !_settingsPanelOpen),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _settingsPanelOpen ? ShadColors.primary.withAlpha(25) : null,
                border: _settingsPanelOpen ? null : Border.all(color: ShadColors.input),
              ),
              child: const Icon(Icons.settings, size: 14, color: ShadColors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }

  // ── Messages ──

  Widget _buildChatMessages(ChatProvider chat) {
    return chat.messages.isEmpty
        ? Center(
            child: Text('Start a conversation',
                style: TextStyle(color: ShadColors.mutedForeground.withAlpha(120), fontSize: 14)))
        : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            itemCount: chat.messages.length,
            itemBuilder: (_, i) {
              final item = chat.messages[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: item.role == 'user' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(item.role == 'user' ? 'You' : 'AI',
                          style: const TextStyle(fontSize: 11, color: ShadColors.mutedForeground)),
                    ),
                    ChatBubble(item: item),
                  ],
                ),
              );
            },
          );
  }
}

// ═══════════════════════════════════════════════════════════════
// Session Panel (left)
// ═══════════════════════════════════════════════════════════════

class _SessionPanel extends StatelessWidget {
  final ChatProvider chat;
  final VoidCallback onClose;

  const _SessionPanel({required this.chat, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: 260,
      color: const Color(0xFF151515),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with close button
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ShadColors.border)),
            ),
            child: Row(
              children: [
                const Text('Sessions',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadColors.foreground)),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 16, color: ShadColors.mutedForeground),
                ),
              ],
            ),
          ),
          // New Session button
          Padding(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: chat.isStreaming ? null : () => chat.createNewSession(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: ShadColors.input),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 14, color: ShadColors.foreground),
                    SizedBox(width: 6),
                    Text('New Session', style: TextStyle(fontSize: 13, color: ShadColors.foreground)),
                  ],
                ),
              ),
            ),
          ),
          // Session list
          Expanded(
            child: chat.sessions.isEmpty
                ? Center(
                    child: Text('Memory Empty',
                        style: TextStyle(fontSize: 12, color: ShadColors.mutedForeground.withAlpha(120))))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: chat.sessions.length,
                    itemBuilder: (_, i) {
                      final s = chat.sessions[i];
                      final id = s['id'] as String? ?? '';
                      final title = (s['title'] as String?) ?? 'Untitled';
                      final active = id == chat.activeSessionId;
                      return GestureDetector(
                        onTap: () => chat.loadSession(id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: active ? ShadColors.secondary : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(title,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: active ? ShadColors.foreground : ShadColors.mutedForeground),
                              overflow: TextOverflow.ellipsis),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Settings Panel (right)
// ═══════════════════════════════════════════════════════════════

class _SettingsPanel extends StatelessWidget {
  final SettingsProvider sp;
  final ChatProvider chat;
  final VoidCallback onClose;

  const _SettingsPanel({required this.sp, required this.chat, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final s = sp.settings;
    final baseUrlCtrl = TextEditingController(text: s.apiRelayBaseUrl);
    final apiKeyCtrl = TextEditingController(text: s.apiRelayApiKey);
    final modelCtrl = TextEditingController(text: s.apiRelayModel);
    final promptCtrl = TextEditingController(text: s.systemPrompt);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: 420,
      color: const Color(0xFF151515),
      child: Column(
        children: [
          // Header
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: ShadColors.border)),
            ),
            child: Row(
              children: [
                const Text('Settings',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadColors.foreground)),
                const Spacer(),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(Icons.close, size: 16, color: ShadColors.mutedForeground),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('AI Model Selector'),
                  const SizedBox(height: 6),
                  _field(modelCtrl, 'Model name'),
                  const SizedBox(height: 16),
                  _label('System Prompt'),
                  const SizedBox(height: 6),
                  _field(promptCtrl, 'You are an uncensored AI model.', maxLines: 5),
                  const SizedBox(height: 16),
                  _switchRow(
                    label: 'Show Monitor',
                    desc: 'Show the LLM monitor on the right side.',
                    value: s.showMonitor,
                    onChanged: (v) => sp.saveSettings(s.copyWith(showMonitor: v)),
                  ),
                  const SizedBox(height: 12),
                  _switchRow(
                    label: 'Enable Memory Retrieval',
                    desc: 'Retrieve relevant context from memory.',
                    value: s.enableMemoryRetrieval,
                    onChanged: (v) => sp.saveSettings(s.copyWith(enableMemoryRetrieval: v)),
                  ),
                  const SizedBox(height: 20),
                  Container(height: 1, color: ShadColors.border),
                  const SizedBox(height: 16),
                  _label('API Relay Config'),
                  const SizedBox(height: 8),
                  _label('Base URL'),
                  const SizedBox(height: 4),
                  _field(baseUrlCtrl, 'https://api.siliconflow.cn/v1'),
                  const SizedBox(height: 10),
                  _label('API Key'),
                  const SizedBox(height: 4),
                  _field(apiKeyCtrl, 'sk-...', obscure: true),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        sp.saveSettings(s.copyWith(
                          apiRelayBaseUrl: baseUrlCtrl.text.trim(),
                          apiRelayApiKey: apiKeyCtrl.text.trim(),
                          apiRelayModel: modelCtrl.text.trim(),
                          systemPrompt: promptCtrl.text,
                        ));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Settings saved'),
                            backgroundColor: ShadColors.primary,
                            duration: Duration(seconds: 2)));
                      },
                      child: const Text('Save Settings', style: TextStyle(color: ShadColors.primaryForeground)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ShadColors.foreground));

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1, bool obscure = false}) {
    return TextField(
      controller: ctrl, maxLines: maxLines, obscureText: obscure,
      style: const TextStyle(fontSize: 13, color: ShadColors.foreground),
      decoration: InputDecoration(
        hintText: hint, filled: true, fillColor: ShadColors.secondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: ShadColors.input)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: ShadColors.ring, width: 1)),
      ),
    );
  }

  Widget _switchRow({required String label, required String desc, required bool value, required ValueChanged<bool> onChanged}) {
    return Row(children: [
      SizedBox(height: 24, child: Switch(value: value, onChanged: onChanged, activeColor: ShadColors.primary)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: ShadColors.foreground)),
        Text(desc, style: const TextStyle(fontSize: 11, color: ShadColors.mutedForeground)),
      ])),
    ]);
  }
}
