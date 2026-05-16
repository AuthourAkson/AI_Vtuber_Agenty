import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/chat_provider.dart';

/// LLM Monitor panel — matches LocalAIVtuber2's llm-monitor.tsx.
/// Shows system prompt, vision context, OCR, memory, and full assembled prompt.
class LLMMonitor extends StatelessWidget {
LLMMonitor({super.key});

@override
Widget build(BuildContext context) {
return Consumer<ChatProvider>(
builder: (context, chat, _) {
return SingleChildScrollView(
padding: EdgeInsets.all(16),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Mic / Vision toggle buttons (stubs — LAV2 uses GlobalStateManager)
Row(
children: [
_toggleButton(context, 
icon: Icons.mic,
label: 'Start Mic',
active: false,
onTap: () {},
),
SizedBox(width: 8),
_toggleButton(context, 
icon: Icons.camera_alt,
label: 'Start Vision',
active: false,
onTap: () {},
),
],
),
SizedBox(height: 16),

// System context
_sectionLabel(context, 'System Context'),
SizedBox(height: 4),
_readOnlyTextArea(context, 
chat.systemPrompt.isNotEmpty
? chat.systemPrompt
: 'No system prompt set',
),
SizedBox(height: 12),

// Vision context
_sectionLabel(context, 'Vision Context'),
SizedBox(height: 4),
_readOnlyTextArea(context, 
chat.currentCaption.isNotEmpty
? chat.currentCaption
: 'No vision context',
),
SizedBox(height: 12),

// OCR context
_sectionLabel(context, 'OCR Context'),
SizedBox(height: 4),
_readOnlyTextArea(context, 
chat.currentOcrText.isNotEmpty
? chat.currentOcrText
: 'No OCR context',
),
SizedBox(height: 12),

// Divider
Container(height: 1, color: ShadTheme.of(context).border),
SizedBox(height: 12),

// Retrieved memory context
_sectionLabel(context, 'Retrieved Memory Context'),
SizedBox(height: 4),
_readOnlyTextArea(context, 
chat.currentMemoryContext.isNotEmpty
? chat.currentMemoryContext
: 'No context retrieved from memory',
),
SizedBox(height: 12),

// Full system prompt
_sectionLabel(context, 'Full System Prompt'),
SizedBox(height: 4),
Container(
width: double.infinity,
padding: EdgeInsets.all(10),
decoration: BoxDecoration(
color: ShadTheme.of(context).muted,
borderRadius: BorderRadius.circular(6),
border: Border.all(color: ShadTheme.of(context).input),
),
child: Text(
chat.fullSystemPrompt.isNotEmpty
? chat.fullSystemPrompt
: 'No system prompt composed yet',
style: TextStyle(
fontSize: 12,
color: ShadTheme.of(context).foreground,
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

Widget _sectionLabel(BuildContext context, String text) {
return Padding(
padding: EdgeInsets.only(bottom: 4),
child: Text(
text,
style: TextStyle(
fontSize: 13,
fontWeight: FontWeight.w600,
color: ShadTheme.of(context).foreground,
),
),
);
}

Widget _readOnlyTextArea(BuildContext context, String text) {
return Container(
width: double.infinity,
padding: EdgeInsets.all(10),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(6),
border: Border.all(color: ShadTheme.of(context).input),
),
child: Text(
text,
style: TextStyle(
fontSize: 12,
color: ShadTheme.of(context).mutedForeground,
height: 1.4,
),
),
);
}

Widget _toggleButton(BuildContext context, {
required IconData icon,
required String label,
required bool active,
required VoidCallback onTap,
}) {
return GestureDetector(
onTap: onTap,
child: Container(
width: 140,
padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
decoration: BoxDecoration(
color: active ? ShadTheme.of(context).primary : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
border: active ? null : Border.all(color: ShadTheme.of(context).input),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(icon, size: 14, color: ShadTheme.of(context).foreground),
SizedBox(width: 6),
Text(
label,
style: TextStyle(
fontSize: 12,
color: ShadTheme.of(context).foreground,
),
),
],
),
),
);
}
}
