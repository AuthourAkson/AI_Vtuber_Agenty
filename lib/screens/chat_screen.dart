import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

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
                  const Icon(Icons.chat, color: Color(0xFF4CAF50), size: 20),
                  const SizedBox(width: 8),
                  const Text('Chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (chat.isStreaming)
                    TextButton.icon(
                      onPressed: chat.interrupt,
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('Stop'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFCF6679)),
                    ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: chat.messages.isEmpty
                  ? const Center(child: Text('Start a conversation', style: TextStyle(color: Color(0xFF888888))))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: chat.messages.length,
                      itemBuilder: (_, index) => ChatBubble(item: chat.messages[index]),
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
