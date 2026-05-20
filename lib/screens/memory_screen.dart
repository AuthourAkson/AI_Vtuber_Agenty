import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/chat_provider.dart';

/// Memory page — matches LocalAIVtuber2's SessionList / MemoryPage.
/// Memory page — matches LocalAIVtuber2's SessionList / MemoryPage.
class MemoryScreen extends StatefulWidget {
final VoidCallback? onNavigateHome;
MemoryScreen({super.key, this.onNavigateHome});

@override
State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
final _searchCtrl = TextEditingController();
String _searchTerm = '';
bool _loading = false;
String? _renamingId;
final _renameCtrl = TextEditingController();

@override
void initState() {
super.initState();
// Load sessions into cache on first open
WidgetsBinding.instance.addPostFrameCallback((_) {
final chat = context.read<ChatProvider>();
chat.sessionManager.loadSessions().then((_) {
if (mounted) setState(() {});
});
});
}

@override
void dispose() {
_searchCtrl.dispose();
_renameCtrl.dispose();
super.dispose();
}

void _startRename(String id, String currentTitle) {
setState(() {
_renamingId = id;
_renameCtrl.text = currentTitle;
});
}

void _commitRename(ChatProvider chat, String id) async {
final newTitle = _renameCtrl.text.trim();
setState(() => _renamingId = null);
if (newTitle.isNotEmpty) {
await chat.renameSession(id, newTitle);
}
}

@override
Widget build(BuildContext context) {
return Consumer<ChatProvider>(
builder: (context, chat, _) {
final sessions = chat.sessions;
final l10n = AppLocalizations.of(context);

// Filter by search term
final filtered = sessions.where((s) {
final title = (s['title'] as String?) ?? '';
return title.toLowerCase().contains(_searchTerm.toLowerCase());
}).toList();

return SingleChildScrollView(
padding: EdgeInsets.only(top: 40, left: 48, right: 48, bottom: 40),
child: ConstrainedBox(
constraints: BoxConstraints(maxWidth: 960),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Page header — matches LAV2 style
Text(
l10n.memoryTitle,
style: TextStyle(
fontSize: 28,
fontWeight: FontWeight.bold,
color: ShadTheme.of(context).foreground,
),
),
SizedBox(height: 4),
Text(
l10n.memorySubtitle,
style: TextStyle(
fontSize: 14,
color: ShadTheme.of(context).mutedForeground,
),
),
SizedBox(height: 24),

// Search & filter bar
Container(
padding: EdgeInsets.all(16),
decoration: BoxDecoration(
color: ShadTheme.of(context).card,
borderRadius: BorderRadius.circular(8),
border: Border.all(color: ShadTheme.of(context).border),
boxShadow: [
BoxShadow(
color: Color(0x08000000),
blurRadius: 2,
offset: Offset(0, 1),
),
],
),
child: Row(
children: [
// Search field
Expanded(
child: SizedBox(
height: 36,
child: TextField(
controller: _searchCtrl,
style: TextStyle(
fontSize: 13,
color: ShadTheme.of(context).foreground,
),
decoration: InputDecoration(
hintText: l10n.memorySearch,
hintStyle: TextStyle(
color: ShadTheme.of(context).mutedForeground,
fontSize: 13,
),
prefixIcon: Icon(
Icons.search,
size: 16,
color: ShadTheme.of(context).mutedForeground,
),
filled: true,
fillColor: ShadTheme.of(context).secondary,
contentPadding: EdgeInsets.symmetric(
horizontal: 12,
vertical: 8,
),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(6),
borderSide: BorderSide.none,
),
enabledBorder: OutlineInputBorder(
borderRadius: BorderRadius.circular(6),
borderSide: BorderSide(color: ShadTheme.of(context).input),
),
),
onChanged: (v) => setState(() => _searchTerm = v),
),
),
),
SizedBox(width: 8),
// Refresh button
GestureDetector(
onTap: _loading
? null
: () async {
setState(() => _loading = true);
await chat.sessionManager.loadSessions();
if (mounted) setState(() => _loading = false);
},
child: Container(
width: 36,
height: 36,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(6),
border: Border.all(color: ShadTheme.of(context).input),
),
child: _loading
? Center(
child: SizedBox(
width: 14,
height: 14,
child: CircularProgressIndicator(
strokeWidth: 2,
color: ShadTheme.of(context).mutedForeground,
),
),
)
: Icon(
Icons.refresh,
size: 16,
color: ShadTheme.of(context).mutedForeground,
),
),
),
],
),
),
SizedBox(height: 20),

// Session cards
if (filtered.isEmpty)
Center(
child: Padding(
padding: EdgeInsets.symmetric(vertical: 48),
child: Column(
children: [
Icon(
Icons.storage_rounded,
size: 48,
color: ShadTheme.of(context).mutedForeground,
),
SizedBox(height: 12),
Text(
l10n.memoryNoResults,
style: TextStyle(
fontSize: 16,
fontWeight: FontWeight.w500,
color: ShadTheme.of(context).foreground,
),
),
SizedBox(height: 4),
Text(
AppLocalizations.of(context).memoryNoResultsHint,
style: TextStyle(
fontSize: 13,
color: ShadTheme.of(context).mutedForeground,
),
),
],
),
),
)
else
...filtered.map((session) {
final id = session['id'] as String? ?? '';
final title = (session['title'] as String?) ?? 'Untitled';
final createdAt =
(session['created_at'] as String?) ?? '';
return _sessionCard(
id: id,
title: title,
createdAt: createdAt,
chat: chat,
isRenaming: _renamingId == id,
renameCtrl: _renamingId == id ? _renameCtrl : null,
onStartRename: () => _startRename(id, title),
onCommitRename: () => _commitRename(chat, id),
);
}),
],
),
),
);
},
);
}

Widget _sessionCard({
required String id,
required String title,
required String createdAt,
required ChatProvider chat,
required bool isRenaming,
TextEditingController? renameCtrl,
required VoidCallback onStartRename,
required VoidCallback onCommitRename,
}) {
return Container(
margin: EdgeInsets.only(bottom: 12),
padding: EdgeInsets.all(16),
decoration: BoxDecoration(
color: ShadTheme.of(context).card,
borderRadius: BorderRadius.circular(8),
border: Border.all(color: ShadTheme.of(context).border),
boxShadow: [
BoxShadow(
color: Color(0x08000000),
blurRadius: 2,
offset: Offset(0, 1),
),
],
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
if (isRenaming)
Padding(
padding: EdgeInsets.only(bottom: 8),
child: TextField(
controller: renameCtrl,
autofocus: true,
style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground),
decoration: InputDecoration(
border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
isDense: true,
filled: true,
fillColor: ShadTheme.of(context).secondary,
),
onSubmitted: (_) => onCommitRename(),
onEditingComplete: () => onCommitRename(),
),
)
else
Row(
children: [
Expanded(
child: GestureDetector(
onLongPress: onStartRename,
child: Text(
title,
style: TextStyle(
fontSize: 16,
fontWeight: FontWeight.w600,
color: ShadTheme.of(context).foreground,
),
),
),
),
GestureDetector(
onTap: onStartRename,
child: Icon(Icons.edit, size: 14, color: ShadTheme.of(context).mutedForeground.withAlpha(100)),
),
],
),
if (createdAt.isNotEmpty && !isRenaming) ...[
SizedBox(height: 4),
Text(
'Created: $createdAt',
style: TextStyle(
fontSize: 12,
color: ShadTheme.of(context).mutedForeground,
),
),
],
SizedBox(height: isRenaming ? 4 : 8),
// Actions
Row(
mainAxisSize: MainAxisSize.min,
children: [
// Load button
GestureDetector(
onTap: () async {
await chat.loadSession(id);
widget.onNavigateHome?.call();
},
child: Container(
padding: EdgeInsets.symmetric(
horizontal: 10,
vertical: 4,
),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(4),
border: Border.all(color: ShadTheme.of(context).input),
),
child: Text(
'Load',
style: TextStyle(
fontSize: 12,
color: ShadTheme.of(context).foreground,
),
),
),
),
SizedBox(width: 6),
// Delete button
GestureDetector(
onTap: () async {
await chat.sessionManager.deleteSession(id);
setState(() {});
},
child: Icon(
Icons.close,
size: 16,
color: ShadTheme.of(context).mutedForeground,
),
),
],
),
],
),
);
}
}
