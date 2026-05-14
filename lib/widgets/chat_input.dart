import 'package:flutter/material.dart';
import '../app.dart';

/// Chat input bar matching LocalAIVtuber2's chatbox input area:
/// `bg-secondary rounded-lg px-4 py-6` with Input + Send/Square button.
class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final bool isStreaming;

  const ChatInput({
    super.key,
    required this.onSend,
    required this.isStreaming,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: ShadColors.border)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: ShadColors.secondary,
          borderRadius: BorderRadius.circular(8), // rounded-lg
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: 4,
                minLines: 1,
                enabled: !widget.isStreaming,
                style: const TextStyle(
                  fontSize: 14,
                  color: ShadColors.foreground,
                ),
                decoration: const InputDecoration(
                  hintText: 'Type your message here.',
                  hintStyle: TextStyle(color: ShadColors.mutedForeground),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => widget.isStreaming ? null : _send(),
              ),
            ),
            const SizedBox(width: 10),
            // Send / Stop button
            GestureDetector(
              onTap: widget.isStreaming ? null : _send,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.isStreaming
                      ? ShadColors.accent
                      : ShadColors.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  widget.isStreaming ? Icons.stop : Icons.send,
                  size: 16,
                  color: widget.isStreaming
                      ? ShadColors.mutedForeground
                      : ShadColors.primaryForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
