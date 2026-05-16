     1|import 'package:flutter/material.dart';
     2|import '../app.dart';
     3|
     4|/// Chat input bar matching LocalAIVtuber2's chatbox input area:
     5|/// `bg-secondary rounded-lg px-4 py-6` with Input + Send/Square button.
     6|class ChatInput extends StatefulWidget {
     7|  final Function(String) onSend;
     8|  final bool isStreaming;
     9|
    10|  const ChatInput({
    11|    super.key,
    12|    required this.onSend,
    13|    required this.isStreaming,
    14|  });
    15|
    16|  @override
    17|  State<ChatInput> createState() => _ChatInputState();
    18|}
    19|
    20|class _ChatInputState extends State<ChatInput> {
    21|  final _controller = TextEditingController();
    22|  final _focusNode = FocusNode();
    23|
    24|  void _send() {
    25|    final text = _controller.text.trim();
    26|    if (text.isEmpty) return;
    27|    widget.onSend(text);
    28|    _controller.clear();
    29|    _focusNode.requestFocus();
    30|  }
    31|
    32|  @override
    33|  void dispose() {
    34|    _controller.dispose();
    35|    _focusNode.dispose();
    36|    super.dispose();
    37|  }
    38|
    39|  @override
    40|  Widget build(BuildContext context) {
    41|    return Container(
    42|      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
    43|      decoration: const BoxDecoration(
    44|        border: Border(top: BorderSide(color: ShadTheme.of(context).border)),
    45|      ),
    46|      child: Container(
    47|        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    48|        decoration: BoxDecoration(
    49|          color: ShadTheme.of(context).secondary,
    50|          borderRadius: BorderRadius.circular(8), // rounded-lg
    51|        ),
    52|        child: Row(
    53|          children: [
    54|            Expanded(
    55|              child: TextField(
    56|                controller: _controller,
    57|                focusNode: _focusNode,
    58|                maxLines: 4,
    59|                minLines: 1,
    60|                enabled: !widget.isStreaming,
    61|                style: const TextStyle(
    62|                  fontSize: 14,
    63|                  color: ShadTheme.of(context).foreground,
    64|                ),
    65|                decoration: const InputDecoration(
    66|                  hintText: 'Type your message here.',
    67|                  hintStyle: TextStyle(color: ShadTheme.of(context).mutedForeground),
    68|                  border: InputBorder.none,
    69|                  isDense: true,
    70|                  contentPadding: EdgeInsets.zero,
    71|                ),
    72|                onSubmitted: (_) => widget.isStreaming ? null : _send(),
    73|              ),
    74|            ),
    75|            const SizedBox(width: 10),
    76|            // Send / Stop button
    77|            GestureDetector(
    78|              onTap: widget.isStreaming ? null : _send,
    79|              child: Container(
    80|                width: 36,
    81|                height: 36,
    82|                decoration: BoxDecoration(
    83|                  color: widget.isStreaming
    84|                      ? ShadTheme.of(context).accent
    85|                      : ShadTheme.of(context).primary,
    86|                  borderRadius: BorderRadius.circular(6),
    87|                ),
    88|                child: Icon(
    89|                  widget.isStreaming ? Icons.stop : Icons.send,
    90|                  size: 16,
    91|                  color: widget.isStreaming
    92|                      ? ShadTheme.of(context).mutedForeground
    93|                      : ShadTheme.of(context).primaryForeground,
    94|                ),
    95|              ),
    96|            ),
    97|          ],
    98|        ),
    99|      ),
   100|    );
   101|  }
   102|}
   103|