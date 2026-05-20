import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input.dart';
import '../widgets/llm_monitor.dart';
import '../l10n/app_localizations.dart';

/// Chat page — matches LocalAIVtuber2's llmPage.tsx + chatbox.tsx layout.
class ChatScreen extends StatefulWidget {
ChatScreen({super.key});

@override
State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
final _scrollController = ScrollController();
bool _autoScroll = true;
bool _sessionPanelOpen = false;
bool _settingsPanelOpen = false;

@override
void dispose() {
_scrollController.dispose();
super.dispose();
}

void _scrollToBottom() {
if (_autoScroll && _scrollController.hasClients) {
WidgetsBinding.instance.addPostFrameCallback((_) {
if (_scrollController.hasClients) {
_scrollController.animateTo(
_scrollController.position.maxScrollExtent,
duration: Duration(milliseconds: 200),
curve: Curves.easeOut,
);
}
});
}
}

@override
Widget build(BuildContext context) {
return Consumer2<ChatProvider, SettingsProvider>(
builder: (context, chat, sp, _) {
_scrollToBottom();
final showMonitor = sp.settings.showMonitor;

return ClipRect(
child: Stack(
children: [
// ── Main content ──
Column(
children: [
_buildHeader(chat),
Expanded(
child: Row(
children: [
Expanded(child: _buildChatMessages(chat)),
if (showMonitor)
Container(
width: 380,
decoration: BoxDecoration(
border: Border(left: BorderSide(color: ShadTheme.of(context).border)),
),
child: LLMMonitor(),
),
],
),
),
ChatInput(
onSend: (text) => chat.sendMessage(text),
isStreaming: chat.isStreaming,
),
],
),

// ── Left: Session panel (slides in) ──
if (_sessionPanelOpen)
Positioned(
left: 0,
top: 0,
bottom: 0,
child: _SessionPanel(chat: chat, onClose: () => setState(() => _sessionPanelOpen = false)),
),

// ── Right: Settings panel (slides in) ──
if (_settingsPanelOpen)
Positioned(
right: 0,
top: 0,
bottom: 0,
child: _SettingsPanel(
sp: sp,
chat: chat,
onClose: () => setState(() => _settingsPanelOpen = false),
),
),
],
),
);
},
);
}

// ── Header ──

Widget _buildHeader(ChatProvider chat) {
return Container(
height: 42,
padding: EdgeInsets.symmetric(horizontal: 16),
decoration: BoxDecoration(
border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
),
child: Row(
children: [
// Session toggle
GestureDetector(
onTap: () => setState(() => _sessionPanelOpen = !_sessionPanelOpen),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(4),
color: _sessionPanelOpen ? ShadTheme.of(context).primary.withAlpha(25) : ShadTheme.of(context).secondary,
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.menu, size: 14, color: ShadTheme.of(context).mutedForeground),
SizedBox(width: 4),
Text(
chat.activeSessionTitle.isNotEmpty ? chat.activeSessionTitle : 'Chat',
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
),
],
),
),
),
Spacer(),
// New session
GestureDetector(
onTap: chat.isStreaming ? null : () => chat.createNewSession(),
child: Container(
padding: EdgeInsets.all(6),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(4),
border: Border.all(color: ShadTheme.of(context).input),
),
child: Icon(Icons.add, size: 14, color: ShadTheme.of(context).mutedForeground),
),
),
SizedBox(width: 6),
// Settings toggle
GestureDetector(
onTap: () => setState(() => _settingsPanelOpen = !_settingsPanelOpen),
child: Container(
padding: EdgeInsets.all(6),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(4),
color: _settingsPanelOpen ? ShadTheme.of(context).primary.withAlpha(25) : null,
border: _settingsPanelOpen ? null : Border.all(color: ShadTheme.of(context).input),
),
child: Icon(Icons.settings, size: 14, color: ShadTheme.of(context).mutedForeground),
),
),
],
),
);
}

// ── Messages ──

Widget _buildChatMessages(ChatProvider chat) {
return chat.messages.isEmpty
? Center(
child: Text(AppLocalizations.of(context).chatStartConversation,
style: TextStyle(color: ShadTheme.of(context).mutedForeground.withAlpha(120), fontSize: 14)))
: ListView.builder(
controller: _scrollController,
padding: EdgeInsets.symmetric(horizontal: 48, vertical: 16),
itemCount: chat.messages.length,
itemBuilder: (_, i) {
final item = chat.messages[i];
return Padding(
padding: EdgeInsets.only(bottom: 12),
child: Column(
crossAxisAlignment: item.role == 'user' ? CrossAxisAlignment.end : CrossAxisAlignment.start,
children: [
Padding(
padding: EdgeInsets.only(bottom: 4),
child: Text(item.role == 'user' ? 'You' : 'AI',
style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
),
ChatBubble(item: item),
],
),
);
},
);
}
}

// ═══════════════════════════════════════════════════════════════
// Session Panel (left)
// ═══════════════════════════════════════════════════════════════

class _SessionPanel extends StatefulWidget {
final ChatProvider chat;
final VoidCallback onClose;

_SessionPanel({required this.chat, required this.onClose});

@override
State<_SessionPanel> createState() => _SessionPanelState();
}

class _SessionPanelState extends State<_SessionPanel> {
String? _renamingId;
final _renameCtrl = TextEditingController();

@override
void dispose() {
_renameCtrl.dispose();
super.dispose();
}

void _startRename(String id, String currentTitle) {
setState(() {
_renamingId = id;
_renameCtrl.text = currentTitle;
});
}

void _commitRename(String id) async {
final newTitle = _renameCtrl.text.trim();
setState(() => _renamingId = null);
if (newTitle.isNotEmpty && newTitle != 'Chat Session') {
await widget.chat.renameSession(id, newTitle);
}
}

void _cancelRename() {
setState(() => _renamingId = null);
}

Future<void> _newSessionWithTitle() async {
final ctrl = TextEditingController(text: '');
final title = await showDialog<String>(
context: context,
builder: (ctx) => AlertDialog(
title: Text(AppLocalizations.of(context).chatNewSession),
content: TextField(
controller: ctrl,
autofocus: true,
decoration: InputDecoration(
hintText: 'Session name',
filled: true,
fillColor: ShadTheme.of(ctx).secondary,
border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
),
onSubmitted: (v) => Navigator.pop(ctx, v.trim().isNotEmpty ? v.trim() : 'Chat Session'),
),
actions: [
TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context).cancel)),
TextButton(
onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty ? ctrl.text.trim() : 'Chat Session'),
child: Text(AppLocalizations.of(context).create)),
],
),
);
ctrl.dispose();
if (title != null) {
await widget.chat.createNewSession(title: title);
}
}

@override
Widget build(BuildContext context) {
final chat = widget.chat;

return AnimatedContainer(
duration: Duration(milliseconds: 250),
curve: Curves.easeInOut,
width: 260,
color: ShadTheme.of(context).sidebar,
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
// Header with close button
Container(
height: 42,
padding: EdgeInsets.symmetric(horizontal: 12),
decoration: BoxDecoration(
border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
),
child: Row(
children: [
Text(AppLocalizations.of(context).chatSessions,
style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
Spacer(),
GestureDetector(
onTap: widget.onClose,
child: Icon(Icons.close, size: 16, color: ShadTheme.of(context).mutedForeground),
),
],
),
),
// New Session button — shows rename dialog
Padding(
padding: EdgeInsets.all(12),
child: GestureDetector(
onTap: chat.isStreaming ? null : _newSessionWithTitle,
child: Container(
width: double.infinity,
padding: EdgeInsets.symmetric(vertical: 8),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(6),
border: Border.all(color: ShadTheme.of(context).input),
),
child: Row(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(Icons.add, size: 14, color: ShadTheme.of(context).foreground),
SizedBox(width: 6),
Text(AppLocalizations.of(context).chatNewSession, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
],
),
),
),
),
// Session list
Expanded(
child: chat.sessions.isEmpty
? Center(
child: Text(AppLocalizations.of(context).memoryEmpty,
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground.withAlpha(120))))
: ListView.builder(
padding: EdgeInsets.symmetric(horizontal: 8),
itemCount: chat.sessions.length,
itemBuilder: (_, i) {
final s = chat.sessions[i];
final id = s['id'] as String? ?? '';
final title = (s['title'] as String?) ?? 'Untitled';
final active = id == chat.activeSessionId;
final isRenaming = _renamingId == id;

if (isRenaming) {
return Container(
padding: EdgeInsets.symmetric(horizontal: 4),
margin: EdgeInsets.only(bottom: 2),
child: TextField(
controller: _renameCtrl,
autofocus: true,
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
decoration: InputDecoration(
border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
isDense: true,
filled: true,
fillColor: ShadTheme.of(context).secondary,
),
onSubmitted: (_) => _commitRename(id),
onEditingComplete: () => _commitRename(id),
),
);
}

return GestureDetector(
onTap: () => chat.loadSession(id),
onLongPress: () => _startRename(id, title),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
margin: EdgeInsets.only(bottom: 2),
decoration: BoxDecoration(
color: active ? ShadTheme.of(context).secondary : null,
borderRadius: BorderRadius.circular(4),
),
child: Row(
children: [
Expanded(
child: Text(title,
style: TextStyle(
fontSize: 13,
color: active ? ShadTheme.of(context).foreground : ShadTheme.of(context).mutedForeground),
overflow: TextOverflow.ellipsis),
),
GestureDetector(
onTap: () => _startRename(id, title),
child: Icon(Icons.edit, size: 12, color: ShadTheme.of(context).mutedForeground.withAlpha(120)),
),
],
),
),
);
},
),
),
SizedBox(height: 8),
],
),
);
}
}

// ═══════════════════════════════════════════════════════════════
// Settings Panel (right)
// ═══════════════════════════════════════════════════════════════

class _SettingsPanel extends StatelessWidget {
final SettingsProvider sp;
final ChatProvider chat;
final VoidCallback onClose;

_SettingsPanel({required this.sp, required this.chat, required this.onClose});

@override
Widget build(BuildContext context) {
final s = sp.settings;
final baseUrlCtrl = TextEditingController(text: s.apiRelayBaseUrl);
final apiKeyCtrl = TextEditingController(text: s.apiRelayApiKey);
final modelCtrl = TextEditingController(text: s.apiRelayModel);
final promptCtrl = TextEditingController(text: s.systemPrompt);

return AnimatedContainer(
duration: Duration(milliseconds: 250),
curve: Curves.easeInOut,
width: 420,
color: ShadTheme.of(context).sidebar,
child: Column(
children: [
// Header
Container(
height: 42,
padding: EdgeInsets.symmetric(horizontal: 12),
decoration: BoxDecoration(
border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
),
child: Row(
children: [
Text(AppLocalizations.of(context).chatSettings,
style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
Spacer(),
GestureDetector(
onTap: onClose,
child: Icon(Icons.close, size: 16, color: ShadTheme.of(context).mutedForeground),
),
],
),
),
// Content
Expanded(
child: SingleChildScrollView(
padding: EdgeInsets.all(16),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
_label(context, 'AI Model Selector'),
SizedBox(height: 6),
_field(context, modelCtrl, 'Model name'),
SizedBox(height: 16),
_label(context, 'System Prompt'),
SizedBox(height: 6),
_field(context, promptCtrl, 'You are an uncensored AI model.', maxLines: 5),
SizedBox(height: 16),
_switchRow(context,
label: 'Show Monitor',
desc: 'Show the LLM monitor on the right side.',
value: s.showMonitor,
onChanged: (v) => sp.saveSettings(s.copyWith(showMonitor: v)),
),
SizedBox(height: 12),
_switchRow(context,
label: 'Enable Memory Retrieval',
desc: 'Retrieve relevant context from memory.',
value: s.enableMemoryRetrieval,
onChanged: (v) => sp.saveSettings(s.copyWith(enableMemoryRetrieval: v)),
),
SizedBox(height: 20),
Container(height: 1, color: ShadTheme.of(context).border),
SizedBox(height: 16),
_label(context, 'API Relay Config'),
SizedBox(height: 8),
_label(context, 'Base URL'),
SizedBox(height: 4),
_field(context, baseUrlCtrl, 'https://api.siliconflow.cn/v1'),
SizedBox(height: 10),
_label(context, 'API Key'),
SizedBox(height: 4),
_field(context, apiKeyCtrl, 'sk-...', obscure: true),
SizedBox(height: 20),
SizedBox(
width: double.infinity,
child: ElevatedButton(
onPressed: () {
sp.saveSettings(s.copyWith(
apiRelayBaseUrl: baseUrlCtrl.text.trim(),
apiRelayApiKey: apiKeyCtrl.text.trim(),
apiRelayModel: modelCtrl.text.trim(),
systemPrompt: promptCtrl.text,
));
ScaffoldMessenger.of(context).showSnackBar(SnackBar(
content: Text(AppLocalizations.of(context).chatSaveSettings),
backgroundColor: ShadTheme.of(context).primary,
duration: Duration(seconds: 2)));
},
child: Text('Save Settings', style: TextStyle(color: ShadTheme.of(context).primaryForeground)),
),
),
],
),
),
),
],
),
);
}

Widget _label(BuildContext context, String t) => Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground));

Widget _field(BuildContext context, TextEditingController ctrl, String hint, {int maxLines = 1, bool obscure = false}) {
return TextField(
controller: ctrl, maxLines: maxLines, obscureText: obscure,
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
decoration: InputDecoration(
hintText: hint, filled: true, fillColor: ShadTheme.of(context).secondary,
contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
borderSide: BorderSide(color: ShadTheme.of(context).input)),
focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
borderSide: BorderSide(color: ShadTheme.of(context).ring, width: 1)),
),
);
}

Widget _switchRow(BuildContext context, {required String label, required String desc, required bool value, required ValueChanged<bool> onChanged}) {
return Row(children: [
SizedBox(height: 24, child: Switch(value: value, onChanged: onChanged, activeColor: ShadTheme.of(context).primary)),
SizedBox(width: 10),
Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(label, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
Text(desc, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
])),
]);
}
}
