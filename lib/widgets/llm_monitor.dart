import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/chat_provider.dart';

/// LLM Monitor panel — matches LocalAIVtuber2's llm-monitor.tsx.
/// Shows system prompt, vision context, OCR, memory, and full assembled prompt.
class LLMMonitor extends StatelessWidget {
  const LLMMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mic / Vision toggle buttons (stubs — LAV2 uses GlobalStateManager)
              Row(
                children: [
                  _toggleButton(
                    icon: Icons.mic,
                    label: 'Start Mic',
                    active: false,
                    onTap: () {},
                  ),
                  const SizedBox(width: 8),
                  _toggleButton(
                    icon: Icons.camera_alt,
                    label: 'Start Vision',
                    active: false,
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // System context
              _sectionLabel('System Context'),
              const SizedBox(height: 4),
              _readOnlyTextArea(
                chat.systemPrompt.isNotEmpty
                    ? chat.systemPrompt
                    : 'No system prompt set',
              ),
              const SizedBox(height: 12),

              // Vision context
              _sectionLabel('Vision Context'),
              const SizedBox(height: 4),
              _readOnlyTextArea(
                chat.currentCaption.isNotEmpty
                    ? chat.currentCaption
                    : 'No vision context',
              ),
              const SizedBox(height: 12),

              // OCR context
              _sectionLabel('OCR Context'),
              const SizedBox(height: 4),
              _readOnlyTextArea(
                chat.currentOcrText.isNotEmpty
                    ? chat.currentOcrText
                    : 'No OCR context',
              ),
              const SizedBox(height: 12),

              // Divider
              Container(height: 1, color: ShadColors.border),
              const SizedBox(height: 12),

              // Retrieved memory context
              _sectionLabel('Retrieved Memory Context'),
              const SizedBox(height: 4),
              _readOnlyTextArea(
                chat.currentMemoryContext.isNotEmpty
                    ? chat.currentMemoryContext
                    : 'No context retrieved from memory',
              ),
              const SizedBox(height: 12),

              // Full system prompt
              _sectionLabel('Full System Prompt'),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ShadColors.muted,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: ShadColors.input),
                ),
                child: Text(
                  chat.fullSystemPrompt.isNotEmpty
                      ? chat.fullSystemPrompt
                      : 'No system prompt composed yet',
                  style: const TextStyle(
                    fontSize: 12,
                    color: ShadColors.foreground,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ShadColors.foreground,
        ),
      ),
    );
  }

  Widget _readOnlyTextArea(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ShadColors.input),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: ShadColors.mutedForeground,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _toggleButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: BoxDecoration(
          color: active ? ShadColors.primary : ShadColors.secondary,
          borderRadius: BorderRadius.circular(6),
          border: active ? null : Border.all(color: ShadColors.input),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: ShadColors.foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: ShadColors.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
