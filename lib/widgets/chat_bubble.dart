import 'package:flutter/material.dart';
import '../models/message.dart';

/// Renders a single chat message bubble
class ChatBubble extends StatelessWidget {
  final HistoryItem item;

  const ChatBubble({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final isUser = item.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF4CAF50),
              child: Icon(Icons.smart_toy, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF2C3A2C) : const Color(0xFF252525),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUser ? 'You' : 'AI',
                    style: TextStyle(
                      fontSize: 11,
                      color: isUser ? const Color(0xFF4CAF50) : const Color(0xFF888888),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.content,
                    style: const TextStyle(fontSize: 14, color: Color(0xFFDDDDDD)),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF3A3A3A),
              child: Icon(Icons.person, size: 16, color: Color(0xFF888888)),
            ),
          ],
        ],
      ),
    );
  }
}
