     1|import 'package:flutter/material.dart';
     2|import '../app.dart';
     3|import '../models/message.dart';
     4|import 'rich_content_bubble.dart';
     5|
     6|/// Chat message bubble.
     7|/// Wrapped in SelectionArea for native text selection + right-click copy on desktop.
     8|class ChatBubble extends StatelessWidget {
     9|  final HistoryItem item;
    10|
    11|  const ChatBubble({super.key, required this.item});
    12|
    13|  @override
    14|  Widget build(BuildContext context) {
    15|    final isUser = item.role == 'user';
    16|
    17|    return Align(
    18|      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    19|      child: Container(
    20|        constraints: const BoxConstraints(maxWidth: 560),
    21|        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    22|        decoration: BoxDecoration(
    23|          color: ShadTheme.of(context).secondary,
    24|          borderRadius: BorderRadius.circular(6),
    25|          boxShadow: const [
    26|            BoxShadow(color: Color(0x08000000), blurRadius: 1, offset: Offset(0, 0.5)),
    27|          ],
    28|        ),
    29|        child: SelectionArea(
    30|          child: RichContentBubble(content: item.content, isUser: isUser),
    31|        ),
    32|      ),
    33|    );
    34|  }
    35|}
    36|