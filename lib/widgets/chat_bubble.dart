import 'package:flutter/material.dart';
import '../app.dart';
import '../models/message.dart';
import 'rich_content_bubble.dart';

/// Chat message bubble.
/// Wrapped in SelectionArea for native text selection + right-click copy on desktop.
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
color: ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
boxShadow: const [
BoxShadow(color: Color(0x08000000), blurRadius: 1, offset: Offset(0, 0.5)),
],
),
child: SelectionArea(
child: RichContentBubble(content: item.content, isUser: isUser),
),
),
);
}
}
