import 'package:flutter/material.dart';
import '../app.dart';
import '../models/message.dart';

/// Chat message bubble matching LocalAIVtuber2's editable-chat-history.tsx style.
/// - User messages: right-aligned, bg-secondary, opacity 0.8
/// - AI messages: left-aligned, bg-secondary, full opacity
/// - Minimal padding, rounded-md corners, text-sm font
class ChatBubble extends StatelessWidget {
  final HistoryItem item;

  const ChatBubble({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final isUser = item.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: ShadColors.secondary,
          borderRadius: BorderRadius.circular(6), // rounded-md = 6px
          // box-shadow-xs equivalent — subtle shadow
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 1,
              offset: Offset(0, 0.5),
            ),
          ],
        ),
        child: Text(
          item.content,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isUser
                ? ShadColors.secondaryForeground.withAlpha(204) // opacity-80
                : ShadColors.secondaryForeground,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
