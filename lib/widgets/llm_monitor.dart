     1|import 'package:flutter/material.dart';
     2|import 'package:provider/provider.dart';
     3|import '../app.dart';
     4|import '../providers/chat_provider.dart';
     5|
     6|/// LLM Monitor panel — matches LocalAIVtuber2's llm-monitor.tsx.
     7|/// Shows system prompt, vision context, OCR, memory, and full assembled prompt.
     8|class LLMMonitor extends StatelessWidget {
     9|  const LLMMonitor({super.key});
    10|
    11|  @override
    12|  Widget build(BuildContext context) {
    13|    return Consumer<ChatProvider>(
    14|      builder: (context, chat, _) {
    15|        return SingleChildScrollView(
    16|          padding: const EdgeInsets.all(16),
    17|          child: Column(
    18|            crossAxisAlignment: CrossAxisAlignment.start,
    19|            children: [
    20|              // Mic / Vision toggle buttons (stubs — LAV2 uses GlobalStateManager)
    21|              Row(
    22|                children: [
    23|                  _toggleButton(
    24|                    icon: Icons.mic,
    25|                    label: 'Start Mic',
    26|                    active: false,
    27|                    onTap: () {},
    28|                  ),
    29|                  const SizedBox(width: 8),
    30|                  _toggleButton(
    31|                    icon: Icons.camera_alt,
    32|                    label: 'Start Vision',
    33|                    active: false,
    34|                    onTap: () {},
    35|                  ),
    36|                ],
    37|              ),
    38|              const SizedBox(height: 16),
    39|
    40|              // System context
    41|              _sectionLabel('System Context'),
    42|              const SizedBox(height: 4),
    43|              _readOnlyTextArea(
    44|                chat.systemPrompt.isNotEmpty
    45|                    ? chat.systemPrompt
    46|                    : 'No system prompt set',
    47|              ),
    48|              const SizedBox(height: 12),
    49|
    50|              // Vision context
    51|              _sectionLabel('Vision Context'),
    52|              const SizedBox(height: 4),
    53|              _readOnlyTextArea(
    54|                chat.currentCaption.isNotEmpty
    55|                    ? chat.currentCaption
    56|                    : 'No vision context',
    57|              ),
    58|              const SizedBox(height: 12),
    59|
    60|              // OCR context
    61|              _sectionLabel('OCR Context'),
    62|              const SizedBox(height: 4),
    63|              _readOnlyTextArea(
    64|                chat.currentOcrText.isNotEmpty
    65|                    ? chat.currentOcrText
    66|                    : 'No OCR context',
    67|              ),
    68|              const SizedBox(height: 12),
    69|
    70|              // Divider
    71|              Container(height: 1, color: ShadTheme.of(context).border),
    72|              const SizedBox(height: 12),
    73|
    74|              // Retrieved memory context
    75|              _sectionLabel('Retrieved Memory Context'),
    76|              const SizedBox(height: 4),
    77|              _readOnlyTextArea(
    78|                chat.currentMemoryContext.isNotEmpty
    79|                    ? chat.currentMemoryContext
    80|                    : 'No context retrieved from memory',
    81|              ),
    82|              const SizedBox(height: 12),
    83|
    84|              // Full system prompt
    85|              _sectionLabel('Full System Prompt'),
    86|              const SizedBox(height: 4),
    87|              Container(
    88|                width: double.infinity,
    89|                padding: const EdgeInsets.all(10),
    90|                decoration: BoxDecoration(
    91|                  color: ShadTheme.of(context).muted,
    92|                  borderRadius: BorderRadius.circular(6),
    93|                  border: Border.all(color: ShadTheme.of(context).input),
    94|                ),
    95|                child: Text(
    96|                  chat.fullSystemPrompt.isNotEmpty
    97|                      ? chat.fullSystemPrompt
    98|                      : 'No system prompt composed yet',
    99|                  style: const TextStyle(
   100|                    fontSize: 12,
   101|                    color: ShadTheme.of(context).foreground,
   102|                    height: 1.4,
   103|                  ),
   104|                ),
   105|              ),
   106|            ],
   107|          ),
   108|        );
   109|      },
   110|    );
   111|  }
   112|
   113|  Widget _sectionLabel(String text) {
   114|    return Padding(
   115|      padding: const EdgeInsets.only(bottom: 4),
   116|      child: Text(
   117|        text,
   118|        style: const TextStyle(
   119|          fontSize: 13,
   120|          fontWeight: FontWeight.w600,
   121|          color: ShadTheme.of(context).foreground,
   122|        ),
   123|      ),
   124|    );
   125|  }
   126|
   127|  Widget _readOnlyTextArea(String text) {
   128|    return Container(
   129|      width: double.infinity,
   130|      padding: const EdgeInsets.all(10),
   131|      decoration: BoxDecoration(
   132|        borderRadius: BorderRadius.circular(6),
   133|        border: Border.all(color: ShadTheme.of(context).input),
   134|      ),
   135|      child: Text(
   136|        text,
   137|        style: const TextStyle(
   138|          fontSize: 12,
   139|          color: ShadTheme.of(context).mutedForeground,
   140|          height: 1.4,
   141|        ),
   142|      ),
   143|    );
   144|  }
   145|
   146|  Widget _toggleButton({
   147|    required IconData icon,
   148|    required String label,
   149|    required bool active,
   150|    required VoidCallback onTap,
   151|  }) {
   152|    return GestureDetector(
   153|      onTap: onTap,
   154|      child: Container(
   155|        width: 140,
   156|        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
   157|        decoration: BoxDecoration(
   158|          color: active ? ShadTheme.of(context).primary : ShadTheme.of(context).secondary,
   159|          borderRadius: BorderRadius.circular(6),
   160|          border: active ? null : Border.all(color: ShadTheme.of(context).input),
   161|        ),
   162|        child: Row(
   163|          mainAxisSize: MainAxisSize.min,
   164|          children: [
   165|            Icon(icon, size: 14, color: ShadTheme.of(context).foreground),
   166|            const SizedBox(width: 6),
   167|            Text(
   168|              label,
   169|              style: const TextStyle(
   170|                fontSize: 12,
   171|                color: ShadTheme.of(context).foreground,
   172|              ),
   173|            ),
   174|          ],
   175|        ),
   176|      ),
   177|    );
   178|  }
   179|}
   180|