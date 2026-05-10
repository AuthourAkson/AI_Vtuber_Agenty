import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';

class ChatScreen extends StatelessWidget {
  final VoidCallback? onToggleApi;

  const ChatScreen({super.key, this.onToggleApi});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        return Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0x20FFFFFF))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.chat, size: 18, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 8),
                  const Text(
                    'Chat',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (chat.isStreaming)
                    TextButton.icon(
                      onPressed: chat.interrupt,
                      icon: const Icon(Icons.stop, size: 16, color: Color(0xFFCF6679)),
                      label: const Text('Stop', style: TextStyle(color: Color(0xFFCF6679))),
                    ),
                  if (onToggleApi != null) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'API Settings',
                      child: IconButton(
                        onPressed: onToggleApi,
                        icon: const Icon(Icons.api, size: 18),
                        color: const Color(0xFF888888),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Messages
            Expanded(
              child: chat.messages.isEmpty
                  ? const Center(
                      child: Text(
                        'Start a conversation',
                        style: TextStyle(color: Color(0xFF888888)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: chat.messages.length,
                      itemBuilder: (_, index) =>
                          ChatBubble(item: chat.messages[index]),
                    ),
            ),
            // Input
            ChatInput(
              onSend: (text) => chat.sendMessage(text),
              isStreaming: chat.isStreaming,
            ),
          ],
        );
      },
    );
  }
}
