import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/chat_provider.dart';

class VisionScreen extends StatefulWidget {
  const VisionScreen({super.key});

  @override
  State<VisionScreen> createState() => _VisionScreenState();
}

class _VisionScreenState extends State<VisionScreen> {
  String _screenshotResult = '';
  bool _capturing = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chat, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vision / Screenshot', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),

              // Vision prompt
              Text('Vision Prompt', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).visionPromptHint,
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: ShadTheme.of(context).secondary,
                ),
                onChanged: (v) => chat.visionPrompt = v,
              ),

              const SizedBox(height: 16),
              Text('OCR Prompt', style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).visionOcrHint,
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: ShadTheme.of(context).secondary,
                ),
                onChanged: (v) => chat.ocrPrompt = v,
              ),

              const SizedBox(height: 24),

              // Capture button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _capturing ? null : () async {
                    setState(() => _capturing = true);
                    try {
                      final result = await chat.backend.captureScreenshot();
                      setState(() {
                        _screenshotResult = 'OCR: ${result['extracted_text'] ?? 'N/A'}\n\n'
                            'Caption: ${result['caption'] ?? 'N/A'}';
                      });
                      chat.visionPrompt = result['caption'] as String? ?? '';
                      chat.ocrPrompt = result['extracted_text'] as String? ?? '';
                    } catch (e) {
                      setState(() => _screenshotResult = 'Error: $e');
                    }
                    setState(() => _capturing = false);
                  },
                  icon: Icon(_capturing ? Icons.hourglass_top : Icons.screenshot_monitor, size: 18),
                  label: Text(_capturing ? 'Capturing...' : 'Capture Screenshot'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ),

              if (_screenshotResult.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ShadTheme.of(context).secondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ShadTheme.of(context).border),
                  ),
                  child: Text(_screenshotResult,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                ),
              ],

              const SizedBox(height: 16),
              Text('Current Vision Context',
                  style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 14)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ShadTheme.of(context).secondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ShadTheme.of(context).border),
                ),
                child: Text(
                  chat.visionPrompt.isEmpty ? 'No vision context' : chat.visionPrompt,
                  style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
