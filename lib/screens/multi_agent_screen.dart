import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:wenzagent/wenzagent.dart';
import '../app.dart';
import '../providers/multi_agent_provider.dart';
import '../providers/appearance_provider.dart';
import 'package:flutter/services.dart';
import '../services/wenzagent_service.dart';
import '../services/log_service.dart';
import '../l10n/app_localizations.dart';
import 'multi_agent_appearance.dart';

/// Multi-agent network page — matches prompt.md spec:
/// Secondary sidebar (Chat/Contacts), device list, agent chat, employee creation.
class MultiAgentScreen extends StatefulWidget {
MultiAgentScreen({super.key});

@override
State<MultiAgentScreen> createState() => _MultiAgentScreenState();
}

class _MultiAgentScreenState extends State<MultiAgentScreen> {
final _msgCtrl = TextEditingController();
final _scrollCtrl = ScrollController();
final _searchCtrl = TextEditingController();

bool _initialized = false;
bool _contactsMode = false;
bool _skillsMode = false;
bool _showSettings = false;
String _searchQuery = '';
String? _selectedSkillId; // Track selected skill for detail view
int _lastMsgCount = 0; // Track to auto-scroll only on new messages

@override
void initState() {
super.initState();
_searchCtrl.addListener(() => setState(() => _searchQuery = _searchCtrl.text.toLowerCase()));
WidgetsBinding.instance.addPostFrameCallback((_) => _init());
}

@override
void dispose() {
_msgCtrl.dispose();
_scrollCtrl.dispose();
_searchCtrl.dispose();
_waHostCtrl.dispose();
_waPortCtrl.dispose();
_waTopicCtrl.dispose();
_deviceNameCtrl.dispose();
super.dispose();
}

void _init() {
if (_initialized) return;
_initialized = true;
final mgr = context.read<AgentManager>();
if (!mgr.initialized) {
mgr.initIfEnabled(
storagePath: r'D:\AiVtuber_Agent_profile\wenzagent',
host: '127.0.0.1',
port: 9090,
deviceName: 'AI VTuber',
);
}
}

// ─── Build ──────────────────────────────────────────────

@override
Widget build(BuildContext context) {
return Consumer<AgentManager>(
builder: (context, mgr, _) {
return Row(
children: [
// ── Secondary Sidebar ──
SizedBox(
width: 260,
child: _buildSecondarySidebar(mgr),
),
VerticalDivider(width: 1, color: ShadTheme.of(context).border),
// ── Content Area ──
Expanded(child: _buildContentArea(mgr)),
],
);
},
);
}

// ══════════════════════════════════════════════════════════
// Secondary Sidebar
// ══════════════════════════════════════════════════════════

Widget _buildSecondarySidebar(AgentManager mgr) {
return Column(
children: [
// ── Top bar: status + mode switch ──
_buildSidebarHeader(mgr),
Divider(height: 1, color: ShadTheme.of(context).border),
    // ── Search (Chat mode + Skills mode) ──
    if (!_contactsMode)
      Padding(
padding: EdgeInsets.all(10),
child: TextField(
controller: _searchCtrl,
decoration: InputDecoration(
hintText: 'Search agents...',
prefixIcon: Icon(Icons.search, size: 18, color: ShadTheme.of(context).mutedForeground),
filled: true,
fillColor: ShadTheme.of(context).secondary,
contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
border: OutlineInputBorder(
borderRadius: BorderRadius.circular(8),
borderSide: BorderSide.none,
),
isDense: true,
),
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
),
),
Divider(height: 1, color: ShadTheme.of(context).border),
// ── Content (Chat list / Skills list / Contacts list) ──
Expanded(
child: _skillsMode
    ? _buildSkillsList(mgr)
    : _contactsMode ? _buildContactsList(mgr) : _buildChatList(mgr),
),
// ── "+ Create" button (Contacts mode or Skills mode) ──
if (_contactsMode || _skillsMode) _buildCreateButton(),
],
);
}

Widget _buildSidebarHeader(AgentManager mgr) {
return Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
color: ShadTheme.of(context).sidebar,
child: Row(
children: [
// Connection dot
Container(
width: 8, height: 8,
decoration: BoxDecoration(
color: mgr.connected ? Color(0xFF4CAF50) : Color(0xFFCF6679),
shape: BoxShape.circle,
),
),
SizedBox(width: 6),
Text(
mgr.connected ? 'LAN Online' : 'Offline',
style: TextStyle(
fontSize: 11,
color: mgr.connected ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground,
),
),
Spacer(),
// Settings gear
GestureDetector(
onTap: () => setState(() => _showSettings = !_showSettings),
child: Container(
padding: EdgeInsets.all(6),
decoration: BoxDecoration(
color: _showSettings ? ShadTheme.of(context).sidebarAccent : Colors.transparent,
borderRadius: BorderRadius.circular(6),
),
child: Icon(Icons.settings, size: 18,
            color: _showSettings ? Theme.of(context).colorScheme.onPrimary : ShadTheme.of(context).mutedForeground),
),
),
SizedBox(width: 4),
// Mode toggle buttons
_modeButton(Icons.chat_bubble_outline, 'Chat', !_contactsMode && !_skillsMode, () => setState(() { _contactsMode = false; _skillsMode = false; })),
SizedBox(width: 4),
_modeButton(Icons.contacts_outlined, 'Contacts', _contactsMode, () => setState(() { _contactsMode = true; _skillsMode = false; })),
SizedBox(width: 4),
_modeButton(Icons.extension_outlined, 'Skills', _skillsMode, () => setState(() { _contactsMode = false; _skillsMode = true; })),
],
),
);
}

Widget _modeButton(IconData icon, String tooltip, bool active, VoidCallback onTap) {
return GestureDetector(
onTap: onTap,
child: Tooltip(
message: tooltip,
child: Container(
padding: EdgeInsets.all(6),
decoration: BoxDecoration(
color: active ? ShadTheme.of(context).sidebarAccent : Colors.transparent,
borderRadius: BorderRadius.circular(6),
),
child: Icon(icon, size: 18,
        color: active ? Theme.of(context).colorScheme.onPrimary : ShadTheme.of(context).mutedForeground),
),
),
);
}

// ══════════════════════════════════════════════════════════
// Chat List (Chat mode)
// ══════════════════════════════════════════════════════════

Widget _buildChatList(AgentManager mgr) {
// Show device list first, then filtered agent list
final filtered = _searchQuery.isEmpty
? mgr.agentSummaries
: mgr.agentSummaries.where((a) =>
a.name.toLowerCase().contains(_searchQuery) ||
a.uuid.toLowerCase().contains(_searchQuery)).toList();

if (mgr.onlineDevices.isEmpty && mgr.agentSummaries.isEmpty) {
return Center(
child: Padding(
padding: EdgeInsets.all(24),
child: Text(
AppLocalizations.of(context).waNoAgents,
textAlign: TextAlign.center,
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground),
),
),
);
}

  return ListView(
children: [
// ── Devices section ──
if (mgr.onlineDevices.isNotEmpty) ...[
Padding(
padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
child: Text('DEVICES',
style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
),
...mgr.onlineDevices.map((d) => _deviceTile(d)),
Divider(height: 1, color: ShadTheme.of(context).border),
],
// ── Agents section header with "New Conversation" button ──
Padding(
padding: EdgeInsets.fromLTRB(12, 8, 8, 4),
child: Row(
children: [
Text('AGENTS (${filtered.length})',
style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
Spacer(),
GestureDetector(
onTap: () => _showNewConversationDialog(mgr),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
decoration: BoxDecoration(
color: Theme.of(context).colorScheme.primary.withAlpha(25),
borderRadius: BorderRadius.circular(4),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.add, size: 14, color: Theme.of(context).colorScheme.primary),
SizedBox(width: 2),
Text('New', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
],
),
),
),
],
),
),
if (filtered.isEmpty)
Padding(
padding: EdgeInsets.all(12),
child: Text(AppLocalizations.of(context).waNoMatching,
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
)
else
...filtered.map((a) => _agentTile(a, mgr)),
],
);
}

Widget _deviceTile(LanDeviceInfo device) {
return Padding(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
decoration: BoxDecoration(
color: ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
),
child: Row(
children: [
Icon(Icons.computer, size: 16, color: Color(0xFF4CAF50)),
SizedBox(width: 8),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(device.name ?? device.id, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
if (device.ip != null)
Text(device.ip!, style: TextStyle(fontSize: 10, color: ShadTheme.of(context).mutedForeground)),
],
),
),
if (device.isHost)
Container(
padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(3)),
child: Text('HOST', style: TextStyle(fontSize: 8, color: Theme.of(context).colorScheme.primary)),
),
],
),
),
);
}

Widget _agentTile(AgentModel agent, AgentManager mgr) {
final isActive = mgr.activeEmployeeId == agent.uuid;
final lastMsg = agent.description ?? '';
final timeStr = ''; // Could show last reply time if available

return Padding(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
child: GestureDetector(
onTap: () => _selectAgent(agent, mgr),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
decoration: BoxDecoration(
color: isActive ? ShadTheme.of(context).sidebarAccent : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
border: isActive ? Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(80)) : null,
),
child: Row(
children: [
Icon(Icons.smart_toy, size: 20,
    color: isActive ? ShadTheme.of(context).sidebarAccentForeground : ShadTheme.of(context).foreground),
SizedBox(width: 8),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(agent.name, style: TextStyle(fontSize: 13,
fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
color: isActive ? ShadTheme.of(context).sidebarAccentForeground : ShadTheme.of(context).foreground)),
if (lastMsg.isNotEmpty)
Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
style: TextStyle(fontSize: 11,
    color: isActive
        ? ShadTheme.of(context).sidebarAccentForeground.withAlpha(180)
        : ShadTheme.of(context).mutedForeground)),
],
),
),
if (agent.status == 'unread')
Container(
padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
decoration: BoxDecoration(color: ShadTheme.of(context).destructive, borderRadius: BorderRadius.circular(8)),
child: Text('NEW', style: TextStyle(fontSize: 9, color: Colors.white)),
),
SizedBox(width: 2),
// Delete session button — larger tap area to avoid gesture conflict with outer tile
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () => _confirmDeleteSession(agent, mgr),
child: Container(
padding: EdgeInsets.all(6),
child: Icon(Icons.close, size: 16,
    color: isActive ? ShadTheme.of(context).sidebarAccentForeground.withAlpha(150) : ShadTheme.of(context).mutedForeground),
),
),
],
),
),
),
);
}

Widget _unreadBadge(int count) {
return Container(
padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
decoration: BoxDecoration(color: ShadTheme.of(context).destructive, borderRadius: BorderRadius.circular(8)),
child: Text(count > 99 ? '99+' : '$count',
style: TextStyle(fontSize: 10, color: Colors.white)),
);
}

// ══════════════════════════════════════════════════════════
// Contacts List (Contacts mode)
// ══════════════════════════════════════════════════════════

Widget _buildContactsList(AgentManager mgr) {
final filtered = _searchQuery.isEmpty
? mgr.employees
: mgr.employees.where((e) =>
e.name.toLowerCase().contains(_searchQuery) ||
(e.description ?? '').toLowerCase().contains(_searchQuery)).toList();

if (mgr.employees.isEmpty) {
return Center(
child: Padding(
padding: EdgeInsets.all(24),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.group_add_outlined, size: 40, color: ShadTheme.of(context).mutedForeground),
SizedBox(height: 12),
Text(AppLocalizations.of(context).waNoEmployees,
style: TextStyle(fontSize: 14, color: ShadTheme.of(context).mutedForeground)),
SizedBox(height: 4),
Text(AppLocalizations.of(context).waEmptyHint,
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
],
),
),
);
}

return ListView.builder(
itemCount: filtered.length,
itemBuilder: (_, i) => _employeeTile(filtered[i], mgr),
);
}

Widget _employeeTile(AgentModel emp, AgentManager mgr) {
return Padding(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
child: GestureDetector(
onTap: () {
setState(() => _contactsMode = false);
_selectAgent(emp, mgr);
},
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
decoration: BoxDecoration(
color: ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
),
child: Row(
children: [
// Avatar placeholder
Container(
width: 32, height: 32,
decoration: BoxDecoration(
color: Theme.of(context).colorScheme.primary.withAlpha(40),
borderRadius: BorderRadius.circular(8),
),
child: Icon(Icons.person, size: 18, color: Theme.of(context).colorScheme.primary),
),
SizedBox(width: 10),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(emp.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
color: ShadTheme.of(context).foreground)),
if (emp.description != null && emp.description!.isNotEmpty)
Text(emp.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
SizedBox(height: 2),
Wrap(
spacing: 4,
runSpacing: 2,
children: [
_chip(emp.provider ?? 'unknown'),
_chip(emp.model ?? 'default'),
_chip(emp.deviceId != null ? 'bound' : 'unbound'),
],
),
],
),
),
// Delete button
GestureDetector(
onTap: () => _confirmDelete(emp, mgr),
child: Icon(Icons.delete_outline, size: 16, color: ShadTheme.of(context).mutedForeground),
),
],
),
),
),
);
}

Widget _chip(String label) {
return Container(
padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
decoration: BoxDecoration(
color: ShadTheme.of(context).mutedForeground.withAlpha(25),
borderRadius: BorderRadius.circular(3),
),
child: Text(label, style: TextStyle(fontSize: 9, color: ShadTheme.of(context).mutedForeground)),
);
}

void _confirmDelete(AgentModel emp, AgentManager mgr) {
showDialog(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: ShadTheme.of(context).card,
title: Text(AppLocalizations.of(context).waDeleteEmployee, style: TextStyle(color: ShadTheme.of(context).foreground)),
content: Text(AppLocalizations.of(context).waDeleteConfirm,
style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
actions: [
TextButton(
onPressed: () => Navigator.pop(ctx),
child: Text(AppLocalizations.of(context).cancel, style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
),
TextButton(
onPressed: () {
mgr.deleteEmployee(emp.uuid);
Navigator.pop(ctx);
},
child: Text(AppLocalizations.of(context).delete, style: TextStyle(color: ShadTheme.of(context).destructive)),
),
],
),
);
}

void _confirmDeleteSession(AgentModel agent, AgentManager mgr) {
showDialog(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: ShadTheme.of(context).card,
title: Text(AppLocalizations.of(context).waDeleteSession, style: TextStyle(color: ShadTheme.of(context).foreground)),
content: Text(AppLocalizations.of(context).waDeleteSessionConfirm,
style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
actions: [
TextButton(
onPressed: () => Navigator.pop(ctx),
child: Text(AppLocalizations.of(context).cancel, style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
),
TextButton(
onPressed: () {
mgr.deleteAgentSession(agent.uuid);
Navigator.pop(ctx);
},
child: Text(AppLocalizations.of(context).delete, style: TextStyle(color: ShadTheme.of(context).destructive)),
),
],
),
);
}

Widget _buildCreateButton() {
final isSkills = _skillsMode;
return Container(
padding: EdgeInsets.all(10),
decoration: BoxDecoration(
border: Border(top: BorderSide(color: ShadTheme.of(context).border)),
),
child: SizedBox(
width: double.infinity,
child: OutlinedButton.icon(
onPressed: () => isSkills ? _showAddSkillDialog() : _showCreateEmployeeDialog(),
icon: Icon(Icons.add, size: 18),
label: Text(isSkills ? AppLocalizations.of(context).skillAdd : AppLocalizations.of(context).waCreateEmployee),
style: OutlinedButton.styleFrom(
foregroundColor: Theme.of(context).colorScheme.primary,
side: BorderSide(color: Theme.of(context).colorScheme.primary),
padding: EdgeInsets.symmetric(vertical: 10),
),
),
),
);
}

// ══════════════════════════════════════════════════════════
// Create Employee Dialog
// ══════════════════════════════════════════════════════════

void _showCreateEmployeeDialog() {
final nameCtrl = TextEditingController();
final descCtrl = TextEditingController();

showDialog(
context: context,
builder: (ctx) {
return AlertDialog(
backgroundColor: ShadTheme.of(context).card,
title: Text(AppLocalizations.of(context).waCreateEmployee, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 16)),
content: SizedBox(
width: 400,
child: SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Name
SizedBox(
width: 360,
child: TextField(
controller: nameCtrl,
decoration: InputDecoration(
labelText: 'Name',
hintText: 'e.g. Code Reviewer',
filled: true, fillColor: ShadTheme.of(context).secondary,
border: OutlineInputBorder(),
),
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
),
),
SizedBox(height: 12),
// Description
SizedBox(
width: 360,
child: TextField(
controller: descCtrl,
maxLines: 3,
decoration: InputDecoration(
labelText: 'Description',
hintText: AppLocalizations.of(context).waDescHint,
filled: true, fillColor: ShadTheme.of(context).secondary,
border: OutlineInputBorder(),
),
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
),
),
SizedBox(height: 12),
// Device assignment
],
),
),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(ctx),
child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
),
ElevatedButton(
onPressed: () async {
final name = nameCtrl.text.trim();
if (name.isEmpty) return;
Navigator.pop(ctx);
final mgr = context.read<AgentManager>();
await mgr.createEmployee(
name: name,
description: descCtrl.text.trim(),
);
},
style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
    child: Text(AppLocalizations.of(context).create, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
),
],
);
},
);
}

// ══════════════════════════════════════════════════════════
// Multi-Agent Settings Page
// ══════════════════════════════════════════════════════════

String _activeSettingSection = 'ai_config';

// ── Logs panel state ──
String _logSearch = '';
final Set<LogLevel> _logLevels = LogLevel.values.toSet();
int? _expandedLogId;

// ── MCP Config state ──
bool _mcpRunning = false;
String _mcpHost = 'localhost';
int _mcpPort = 9898;
String _mcpConfigJson = '{\n  "mcpServers": {\n    "filesystem": {\n      "command": "npx",\n      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]\n    }\n  }\n}';
final List<Map<String, String>> _mcpServers = [
  {'name': 'filesystem', 'url': 'http://localhost:9898', 'status': 'stopped'},
];

// ── Permissions state ──
// (permission toggles are now stored in AgentManager for persistence)

int _lanTab = 0;
final _waHostCtrl = TextEditingController(text: '127.0.0.1');
final _waPortCtrl = TextEditingController(text: '9090');
final _waTopicCtrl = TextEditingController();

// ── Devices panel state ──
final Set<String> _expandedDevices = {};
String? _editingNameFor;
final _deviceNameCtrl = TextEditingController();

Widget _buildSettingsPage(AgentManager mgr) {
return Row(
children: [
// Settings sidebar
SizedBox(
width: 200,
child: Container(
color: ShadTheme.of(context).sidebar,
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Padding(
padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
child: Row(
children: [
Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
Spacer(),
GestureDetector(
onTap: () => setState(() => _showSettings = false),
child: Icon(Icons.close, size: 18, color: ShadTheme.of(context).mutedForeground),
),
],
),
),
Divider(color: ShadTheme.of(context).border),
_settingsGroup(AppLocalizations.of(context).preferences, [
_settingsItem(AppLocalizations.of(context).appearance, 'pref_appearance', Icons.palette_outlined),
_settingsItem(AppLocalizations.of(context).general, 'pref_general', Icons.tune),
]),
_settingsGroup(AppLocalizations.of(context).aiSection, [
_settingsItem(AppLocalizations.of(context).aiConfig, 'ai_config', Icons.api),
_settingsItem(AppLocalizations.of(context).mcpConfig, 'ai_mcp', Icons.extension),
_settingsItem(AppLocalizations.of(context).permissions, 'ai_permissions', Icons.security),
]),
_settingsGroup(AppLocalizations.of(context).dataSection, [
_settingsItem(AppLocalizations.of(context).sync, 'data_sync', Icons.sync),
_settingsItem(AppLocalizations.of(context).storage, 'data_storage', Icons.storage),
_settingsItem(AppLocalizations.of(context).files, 'data_files', Icons.folder),
]),
_settingsGroup(AppLocalizations.of(context).networkSection, [
_settingsItem(AppLocalizations.of(context).lan, 'net_lan', Icons.lan),
_settingsItem(AppLocalizations.of(context).devices, 'net_devices', Icons.devices),
]),
_settingsGroup(AppLocalizations.of(context).systemSection, [
_settingsItem(AppLocalizations.of(context).privacy, 'sys_privacy', Icons.privacy_tip_outlined),
_settingsItem(AppLocalizations.of(context).logs, 'sys_logs', Icons.article_outlined),
_settingsItem(AppLocalizations.of(context).about, 'sys_about', Icons.info_outline),
]),
],
),
),
),
VerticalDivider(width: 1, color: ShadTheme.of(context).border),
// Settings content
Expanded(child: _buildSettingsContent(mgr)),
],
);
}

Widget _settingsGroup(String title, List<Widget> items) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Padding(
padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
),
...items,
],
);
}

Widget _settingsItem(String title, String key, IconData icon) {
final active = _activeSettingSection == key;
return GestureDetector(
onTap: () => setState(() => _activeSettingSection = key),
child: Container(
margin: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
decoration: BoxDecoration(
color: active ? ShadTheme.of(context).sidebarAccent : Colors.transparent,
borderRadius: BorderRadius.circular(6),
),
child: Row(
children: [
          Icon(icon, size: 16, color: active ? Theme.of(context).colorScheme.onPrimary : ShadTheme.of(context).mutedForeground),
          SizedBox(width: 8),
          Text(title, style: TextStyle(fontSize: 13,
              color: active ? Theme.of(context).colorScheme.onPrimary : ShadTheme.of(context).foreground)),
],
),
),
);
}

Widget _buildSettingsContent(AgentManager mgr) {
switch (_activeSettingSection) {
case 'pref_appearance':
return MultiAgentAppearancePage();
case 'pref_general':
return _buildGeneralPanel();
      case 'ai_config':
        return _buildAiConfigPanel(mgr);
      case 'ai_mcp':
        return _buildMcpConfigPanel(mgr);
      case 'ai_permissions':
        return _buildPermissionsPanel(mgr);
      case 'data_files':
        return _buildDataFilesPanel(mgr);
      case 'data_storage':
        return _buildDataStoragePanel(mgr);
      case 'net_lan':
        return _buildLanSettingsPanel(mgr);
      case 'net_devices':
        return _buildDevicesPanel(mgr);
      case 'sys_logs':
        return _buildLogsPanel(mgr);
      case 'sys_privacy':
        return _buildPrivacyPanel(mgr);
default:
return Center(
child: Text('$_activeSettingSection — coming soon',
style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
);
}
}

// ─── AI Config Panel ─────────────────────────────────────

Widget _buildAiConfigPanel(AgentManager mgr) {
return Column(
children: [
// Header
Container(
padding: EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(AppLocalizations.of(context).aiTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
SizedBox(height: 4),
Text(AppLocalizations.of(context).aiSubtitle,
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
],
),
),
Divider(height: 1, color: ShadTheme.of(context).border),
// Profile list
Expanded(
child: ListView.builder(
padding: EdgeInsets.all(16),
itemCount: mgr.providerProfiles.length,
itemBuilder: (_, i) => _profileCard(mgr.providerProfiles[i], i, mgr),
),
),
// Add profile button
Container(
padding: EdgeInsets.all(16),
decoration: BoxDecoration(
border: Border(top: BorderSide(color: ShadTheme.of(context).border)),
),
child: SizedBox(
width: double.infinity,
child: OutlinedButton.icon(
onPressed: () => _showProfileDialog(mgr),
icon: Icon(Icons.add, size: 18),
label: Text(AppLocalizations.of(context).aiAddProfile),
style: OutlinedButton.styleFrom(
foregroundColor: Theme.of(context).colorScheme.primary,
side: BorderSide(color: Theme.of(context).colorScheme.primary),
padding: EdgeInsets.symmetric(vertical: 12),
),
),
),
),
],
);
}

Widget _profileCard(ProviderProfile profile, int index, AgentManager mgr) {
return Container(
margin: EdgeInsets.only(bottom: 8),
padding: EdgeInsets.all(14),
decoration: BoxDecoration(
color: ShadTheme.of(context).card,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: ShadTheme.of(context).border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(Icons.api, size: 18, color: Theme.of(context).colorScheme.primary),
SizedBox(width: 8),
Expanded(
child: Text(profile.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
),
GestureDetector(
onTap: () => _showProfileDialog(mgr, index: index, existing: profile),
child: Icon(Icons.edit, size: 16, color: ShadTheme.of(context).mutedForeground),
),
SizedBox(width: 12),
GestureDetector(
onTap: () => mgr.removeProfile(index),
child: Icon(Icons.delete_outline, size: 16, color: ShadTheme.of(context).destructive),
),
],
),
SizedBox(height: 8),
_profileRow('URL', profile.baseUrl),
_profileRow('Model', profile.model),
_profileRow('Key', profile.apiKey.isNotEmpty ? '${profile.apiKey.substring(0, profile.apiKey.length > 12 ? 12 : profile.apiKey.length)}...' : '(not set)'),
],
),
);
}

Widget _profileRow(String label, String value) {
return Padding(
padding: EdgeInsets.only(top: 2),
child: Row(
children: [
SizedBox(
width: 40,
child: Text(label, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
),
Expanded(
child: Text(value, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground),
overflow: TextOverflow.ellipsis),
),
],
),
);
}

void _showProfileDialog(AgentManager mgr, {int? index, ProviderProfile? existing}) {
final nameCtrl = TextEditingController(text: existing?.name ?? '');
final urlCtrl = TextEditingController(text: existing?.baseUrl ?? 'https://api.openai.com/v1');
final keyCtrl = TextEditingController(text: existing?.apiKey ?? '');
final modelCtrl = TextEditingController(text: existing?.model ?? 'gpt-4o');

showDialog(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: ShadTheme.of(context).card,
title: Text(existing != null ? 'Edit Profile' : 'New Profile', style: TextStyle(color: ShadTheme.of(context).foreground)),
content: SizedBox(
width: 400,
child: SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
_dialogField('Profile Name', 'e.g. My OpenAI', nameCtrl),
SizedBox(height: 10),
_dialogField('Base URL', 'https://api.openai.com/v1', urlCtrl),
SizedBox(height: 10),
_dialogField('API Key', 'sk-...', keyCtrl, obscure: true),
SizedBox(height: 10),
_dialogField('Model', 'gpt-4o', modelCtrl),
],
),
),
),
actions: [
TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground))),
ElevatedButton(
onPressed: () {
final name = nameCtrl.text.trim();
if (name.isEmpty) return;
final profile = ProviderProfile(
name: name,
baseUrl: urlCtrl.text.trim(),
apiKey: keyCtrl.text.trim(),
model: modelCtrl.text.trim(),
);
if (existing != null && index != null) {
mgr.updateProfile(index, profile);
} else {
mgr.addProfile(profile);
}
Navigator.pop(ctx);
},
style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
    child: Text(AppLocalizations.of(context).save, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
),
],
),
);
}

Widget _dialogField(String label, String hint, TextEditingController ctrl, {bool obscure = false}) {
return TextField(
controller: ctrl,
obscureText: obscure,
decoration: InputDecoration(
labelText: label,
hintText: hint,
filled: true, fillColor: ShadTheme.of(context).secondary,
border: OutlineInputBorder(),
),
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
);
}

// ─── MCP Config Panel ────────────────────────────────────

Widget _buildMcpConfigPanel(AgentManager mgr) {
  final l10n = AppLocalizations.of(context);
  return SingleChildScrollView(
    padding: EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.mcpTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
        SizedBox(height: 4),
        Text(l10n.mcpSubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
        SizedBox(height: 24),

        // ── Servers list ──
        if (_mcpServers.isEmpty)
          _emptyCard(l10n.mcpNoServers)
        else
          ..._mcpServers.map((srv) => _mcpServerCard(srv, l10n)),
        SizedBox(height: 16),

        // ── Add Server button ──
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showMcpAddDialog(l10n),
            icon: Icon(Icons.add, size: 18),
            label: Text(l10n.mcpAddServer),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _mcpServerCard(Map<String, String> srv, AppLocalizations l10n) {
  final running = srv['status'] == 'running';
  final color = running ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground;
  return Container(
    margin: EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ShadTheme.of(context).card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ShadTheme.of(context).border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(srv['name'] ?? 'MCP Server',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withAlpha(80)),
              ),
              child: Text(running ? l10n.mcpRunning : l10n.mcpStopped,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text(srv['url'] ?? '', style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: ShadTheme.of(context).mutedForeground)),
        SizedBox(height: 12),
        Row(
          children: [
            _mcpActionBtn(
              running ? Icons.stop : Icons.play_arrow,
              running ? l10n.mcpStop : l10n.mcpStart,
              running ? ShadTheme.of(context).destructive : Color(0xFF4CAF50),
              () => setState(() {
                srv['status'] = running ? 'stopped' : 'running';
                _mcpRunning = srv['status'] == 'running';
              }),
            ),
            SizedBox(width: 8),
            _mcpActionBtn(Icons.edit, l10n.mcpEditConfig, Theme.of(context).colorScheme.primary,
              () => _showMcpEditDialog(srv, l10n)),
          ],
        ),
      ],
    ),
  );
}

Widget _mcpActionBtn(IconData icon, String label, Color c, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: c),
          SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    ),
  );
}

void _showMcpEditDialog(Map<String, String> srv, AppLocalizations l10n) {
  final hostCtrl = TextEditingController(text: _mcpHost);
  final portCtrl = TextEditingController(text: '$_mcpPort');
  final configCtrl = TextEditingController(text: _mcpConfigJson);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ShadTheme.of(context).card,
      title: Text('${l10n.mcpEditConfig} — ${srv['name']}', style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 15)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hostCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.mcpHost, filled: true,
                        fillColor: ShadTheme.of(context).secondary, border: OutlineInputBorder(),
                      ),
                      style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
                    ),
                  ),
                  SizedBox(width: 10),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: l10n.mcpPort, filled: true,
                        fillColor: ShadTheme.of(context).secondary, border: OutlineInputBorder(),
                      ),
                      style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              TextField(
                controller: configCtrl,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: l10n.mcpConfigJson,
                  hintText: l10n.mcpConfigHint,
                  filled: true, fillColor: ShadTheme.of(context).secondary,
                  border: OutlineInputBorder(),
                ),
                style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: ShadTheme.of(context).foreground),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel, style: TextStyle(color: ShadTheme.of(context).mutedForeground))),
        ElevatedButton(
          onPressed: () {
            setState(() {
              _mcpHost = hostCtrl.text;
              _mcpPort = int.tryParse(portCtrl.text) ?? 9898;
              _mcpConfigJson = configCtrl.text;
              srv['url'] = 'http://$_mcpHost:$_mcpPort';
            });
            Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: Text(l10n.mcpSaveConfig, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
        ),
      ],
    ),
  );
}

void _showMcpAddDialog(AppLocalizations l10n) {
  final nameCtrl = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ShadTheme.of(context).card,
      title: Text(l10n.mcpAddServer, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 15)),
      content: SizedBox(
        width: 350,
        child: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: 'Name', filled: true,
            fillColor: ShadTheme.of(context).secondary, border: OutlineInputBorder(),
          ),
          style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel, style: TextStyle(color: ShadTheme.of(context).mutedForeground))),
        ElevatedButton(
          onPressed: () {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            setState(() => _mcpServers.add({
              'name': name,
              'url': 'http://$_mcpHost:$_mcpPort',
              'status': 'stopped',
            }));
            Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          child: Text(l10n.create, style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
        ),
      ],
    ),
  );
}

// ─── Permissions Panel ───────────────────────────────────

Widget _buildPermissionsPanel(AgentManager mgr) {
  final l10n = AppLocalizations.of(context);
  return SingleChildScrollView(
    padding: EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.permTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
        SizedBox(height: 4),
        Text(l10n.permSubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
        SizedBox(height: 24),
        ...AgentManager.builtinPermDefs.map((def) => _permToggleCard(mgr, def, l10n)),
      ],
    ),
  );
}

Widget _permToggleCard(AgentManager mgr, Map<String, String> def, AppLocalizations l10n) {
  final toolId = def['id']!;
  final label = _permItemLabelByKey(def['label']!, l10n);
  final desc = _permItemDescByKey(def['desc']!, l10n);
  final enabled = mgr.isPermEnabled(toolId);
  return Container(
    margin: EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: ShadTheme.of(context).card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ShadTheme.of(context).border),
    ),
    child: SwitchListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      title: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ShadTheme.of(context).foreground)),
      subtitle: Text(desc, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
      value: enabled,
      onChanged: (_) => mgr.togglePerm(toolId),
      activeColor: ShadTheme.of(context).primary,
    ),
  );
}

String _permItemLabelByKey(String key, AppLocalizations l10n) {
  switch (key) {
    case 'permFileRead': return l10n.permFileRead;
    case 'permFileWrite': return l10n.permFileWrite;
    case 'permFileDelete': return l10n.permFileDelete;
    case 'permFilePatch': return l10n.permFilePatch;
    case 'permDirCreate': return l10n.permDirCreate;
    case 'permCmdExec': return l10n.permCmdExec;
    case 'permBgCmd': return l10n.permBgCmd;
    case 'permGitOps': return l10n.permGitOps;
    case 'permDocRead': return l10n.permDocRead;
    case 'permDocWrite': return l10n.permDocWrite;
    case 'permTaskRead': return l10n.permTaskRead;
    case 'permTaskWrite': return l10n.permTaskWrite;
    default: return key;
  }
}

String _permItemDescByKey(String key, AppLocalizations l10n) {
  switch (key) {
    case 'permFileReadDesc': return l10n.permFileReadDesc;
    case 'permFileWriteDesc': return l10n.permFileWriteDesc;
    case 'permFileDeleteDesc': return l10n.permFileDeleteDesc;
    case 'permFilePatchDesc': return l10n.permFilePatchDesc;
    case 'permDirCreateDesc': return l10n.permDirCreateDesc;
    case 'permCmdExecDesc': return l10n.permCmdExecDesc;
    case 'permBgCmdDesc': return l10n.permBgCmdDesc;
    case 'permGitOpsDesc': return l10n.permGitOpsDesc;
    case 'permDocReadDesc': return l10n.permDocReadDesc;
    case 'permDocWriteDesc': return l10n.permDocWriteDesc;
    case 'permTaskReadDesc': return l10n.permTaskReadDesc;
    case 'permTaskWriteDesc': return l10n.permTaskWriteDesc;
    default: return key;
  }
}

// ─── Data Files Panel ────────────────────────────────────

Widget _buildDataFilesPanel(AgentManager mgr) {
  final l10n = AppLocalizations.of(context);
  final storagePath = r'D:\AiVtuber_Agent_profile\wenzagent';
  final dir = Directory(storagePath);
  List<FileSystemEntity> entries = [];
  if (dir.existsSync()) {
    entries = dir.listSync().toList();
  }
  return Column(
    children: [
      Container(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.dataFilesTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
            SizedBox(height: 4),
            Text(l10n.dataFilesSubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
            SizedBox(height: 16),
            // Accessible folders
            _folderCard(storagePath, 'WenzAgent Data', l10n),
            _folderCard(r'D:\AiVtuber_Agent_profile', 'Agent Profile', l10n),
          ],
        ),
      ),
    ],
  );
}

Widget _folderCard(String path, String name, AppLocalizations l10n) {
  final dir = Directory(path);
  final exists = dir.existsSync();
  int fileCount = 0;
  if (exists) {
    try {
      fileCount = dir.listSync(recursive: true).where((e) => e is File).length;
    } catch (_) {}
  }
  return Container(
    margin: EdgeInsets.only(bottom: 8),
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ShadTheme.of(context).card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ShadTheme.of(context).border),
    ),
    child: Row(
      children: [
        Icon(Icons.folder, size: 24, color: Theme.of(context).colorScheme.primary),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ShadTheme.of(context).foreground)),
              SizedBox(height: 2),
              Text(exists ? path : '$path (not found)',
                style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
            ],
          ),
        ),
        SizedBox(width: 8),
        Text('$fileCount files', style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
        SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            if (exists) {
              Process.run('explorer', [path]);
            }
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ShadTheme.of(context).secondary,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ShadTheme.of(context).border),
            ),
            child: Text(l10n.dataFilesOpenDir, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).foreground)),
          ),
        ),
      ],
    ),
  );
}

// ─── Data Storage Panel ──────────────────────────────────

Widget _buildDataStoragePanel(AgentManager mgr) {
  final l10n = AppLocalizations.of(context);
  final storagePath = r'D:\AiVtuber_Agent_profile';
  final dir = Directory(storagePath);
  int totalFiles = 0;
  int totalSize = 0;
  if (dir.existsSync()) {
    try {
      final all = dir.listSync(recursive: true);
      totalFiles = all.where((e) => e is File).length;
      for (final f in all) {
        if (f is File) {
          try { totalSize += f.lengthSync(); } catch (_) {}
        }
      }
    } catch (_) {}
  }
  final sizeStr = totalSize > 1024 * 1024
    ? '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(totalSize / 1024).toStringAsFixed(1)} KB';

  return SingleChildScrollView(
    padding: EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dataStorageTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
        SizedBox(height: 4),
        Text(l10n.dataStorageSubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
        SizedBox(height: 24),

        // ── Space usage card ──
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ShadTheme.of(context).card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ShadTheme.of(context).border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.donut_large, size: 22, color: Theme.of(context).colorScheme.primary),
                  SizedBox(width: 10),
                  Text(l10n.dataStorageSpace, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  _storageStat(l10n.dataStorageSpace, sizeStr, Icons.disc_full, Theme.of(context).colorScheme.primary),
                  SizedBox(width: 24),
                  _storageStat(l10n.dataStorageFiles, '$totalFiles', Icons.insert_drive_file, ShadTheme.of(context).mutedForeground),
                ],
              ),
              SizedBox(height: 6),
              // Simple progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalSize > 0 ? (totalSize / (500 * 1024 * 1024)).clamp(0.0, 1.0) : 0.05,
                  backgroundColor: ShadTheme.of(context).secondary,
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),

        // ── Manage button ──
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              if (dir.existsSync()) {
                Process.run('explorer', [storagePath]);
              }
            },
            icon: Icon(Icons.folder_open, size: 18),
            label: Text(l10n.dataStorageOpen),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _storageStat(String label, String value, IconData icon, Color c) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: c),
      SizedBox(width: 6),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ShadTheme.of(context).foreground)),
          Text(label, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
        ],
      ),
    ],
  );
}

Widget _emptyCard(String message) {
  return Container(
    padding: EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: ShadTheme.of(context).card,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: ShadTheme.of(context).border),
    ),
    child: Center(
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: ShadTheme.of(context).mutedForeground.withAlpha(80)),
          SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
        ],
      ),
    ),
  );
}

// ─── General Preferences Panel ────────────────────────────

Widget _buildGeneralPanel() {
return Consumer<AppearanceProvider>(
builder: (context, ap, _) {
final l10n = AppLocalizations.of(context);
return SingleChildScrollView(
padding: EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(l10n.generalTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
SizedBox(height: 4),
Text(l10n.generalSubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
SizedBox(height: 24),

// ── Auto-open last page ──
Container(
padding: EdgeInsets.all(16),
decoration: BoxDecoration(
color: ShadTheme.of(context).card,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: ShadTheme.of(context).border),
),
child: SwitchListTile(
contentPadding: EdgeInsets.zero,
title: Text(l10n.generalAutoOpen, style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground)),
subtitle: Text(l10n.generalAutoOpenDesc, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
value: ap.autoOpenLastPage,
onChanged: (v) => ap.update(ap.prefs.copyWith(autoOpenLastPage: v)),
activeColor: ShadTheme.of(context).primary,
),
),
SizedBox(height: 16),

// ── Language ──
Container(
padding: EdgeInsets.all(16),
decoration: BoxDecoration(
color: ShadTheme.of(context).card,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: ShadTheme.of(context).border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(Icons.translate, size: 20, color: ShadTheme.of(context).primary),
SizedBox(width: 10),
Text(l10n.generalLanguage, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
],
),
SizedBox(height: 4),
Text(l10n.generalLanguageDesc, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
SizedBox(height: 12),
DropdownButtonFormField<String>(
value: ap.language,
decoration: InputDecoration(
filled: true,
fillColor: ShadTheme.of(context).secondary,
border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: ShadTheme.of(context).input)),
contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
),
dropdownColor: ShadTheme.of(context).card,
style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground),
items: const [
DropdownMenuItem(value: 'en', child: Text('English')),
DropdownMenuItem(value: 'zh-CN', child: Text('简体中文')),
DropdownMenuItem(value: 'zh-TW', child: Text('繁體中文')),
],
onChanged: (v) {
if (v != null) ap.update(ap.prefs.copyWith(language: v));
},
),
],
),
),
],
),
);
},
);
}

// ─── LAN Settings Panel ──────────────────────────────────

Widget _buildLanSettingsPanel(AgentManager mgr) {
return SingleChildScrollView(
padding: EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(AppLocalizations.of(context).lan, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
SizedBox(height: 4),
Text(mgr.connected ? 'Connected to ${mgr.host}:${mgr.port}' : 'Not connected',
style: TextStyle(fontSize: 13, color: mgr.connected ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground)),
SizedBox(height: 20),

// Join / Create tabs
Row(
children: [
_lanTabBtn('Join LAN', 0),
SizedBox(width: 8),
_lanTabBtn('Create LAN', 1),
],
),
SizedBox(height: 20),

if (_lanTab == 0) ...[
// ── Join LAN ──
_cardHeader('Join Existing Network', Icons.wifi),
SizedBox(height: 12),
_labeledField('Host IP', '192.168.1.100', _waHostCtrl),
SizedBox(height: 8),
_labeledField('Port', '9090', _waPortCtrl),
SizedBox(height: 8),
_labeledField('Topic (optional)', 'Group identifier', _waTopicCtrl),
SizedBox(height: 16),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
onPressed: () => mgr.joinLAN(host: _waHostCtrl.text, port: int.tryParse(_waPortCtrl.text) ?? 9090),
icon: Icon(Icons.wifi, size: 16),
label: Text(AppLocalizations.of(context).waJoinNetwork),
style: ElevatedButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Theme.of(context).colorScheme.onPrimary,
padding: EdgeInsets.symmetric(vertical: 12),
),
),
),
] else ...[
// ── Create LAN ──
_cardHeader('Host Network', Icons.router),
SizedBox(height: 12),
_labeledField('Bind Address', '0.0.0.0', _waHostCtrl),
SizedBox(height: 8),
_labeledField('Port', '9090', _waPortCtrl),
SizedBox(height: 8),
_labeledField('Topic (optional)', 'Group identifier', _waTopicCtrl),
SizedBox(height: 16),
Row(
children: [
Icon(Icons.info_outline, size: 14, color: ShadTheme.of(context).mutedForeground),
SizedBox(width: 6),
Expanded(
child: Text(
AppLocalizations.of(context).waServerHint,
style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground),
),
),
],
),
SizedBox(height: 12),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
onPressed: () => mgr.createLAN(host: '127.0.0.1', port: int.tryParse(_waPortCtrl.text) ?? 9090),
icon: Icon(Icons.play_arrow, size: 16),
label: Text(AppLocalizations.of(context).waStart),
style: ElevatedButton.styleFrom(
backgroundColor: Theme.of(context).colorScheme.primary,
foregroundColor: Theme.of(context).colorScheme.onPrimary,
padding: EdgeInsets.symmetric(vertical: 12),
),
),
),
],
  ],
  ),
  );
}

// ─── Devices Panel ─────────────────────────────────────

Widget _buildDevicesPanel(AgentManager mgr) {
  final devices = mgr.onlineDevices;
  return Column(
    children: [
      // Header
      Container(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context).devices, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
            SizedBox(height: 4),
            Text('${devices.length} ${AppLocalizations.of(context).devicesOnline}',
              style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
          ],
        ),
      ),
      Divider(height: 1, color: ShadTheme.of(context).border),
      // Device list
      Expanded(
        child: devices.isEmpty
            ? Center(
                child: Text(AppLocalizations.of(context).noDevicesOnline,
                  style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
              )
            : ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: devices.length,
                itemBuilder: (_, i) => _deviceDetailCard(devices[i], mgr),
              ),
      ),
    ],
  );
}

Widget _deviceDetailCard(LanDeviceInfo device, AgentManager mgr) {
  final isExpanded = _expandedDevices.contains(device.id);
  final isEditing = _editingNameFor == device.id;
  final typeLabel = (device.type == 'mobile') ? AppLocalizations.of(context).deviceTypeMobile : AppLocalizations.of(context).deviceTypeDesktop;
  final osLabel = device.os ?? AppLocalizations.of(context).notSet;
  final ipLabel = device.ip ?? AppLocalizations.of(context).notSet;
  final deviceIdLabel = device.deviceId ?? AppLocalizations.of(context).notSet;
  final connectedTime = device.connectedAt != null
      ? '${device.connectedAt!.year}-${_pad(device.connectedAt!.month)}-${_pad(device.connectedAt!.day)} ${_pad(device.connectedAt!.hour)}:${_pad(device.connectedAt!.minute)}'
      : AppLocalizations.of(context).notSet;

  return Card(
    color: ShadTheme.of(context).secondary,
    margin: EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        if (isExpanded) {
          _expandedDevices.remove(device.id);
        } else {
          _expandedDevices.add(device.id);
        }
      }),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ═══ Header row (always visible) ═══
            Row(
              children: [
                Icon(device.type == 'mobile' ? Icons.phone_android : Icons.computer, size: 20, color: Color(0xFF4CAF50)),
                SizedBox(width: 10),
                Expanded(
                  child: isEditing
                      ? TextField(
                          controller: _deviceNameCtrl,
                          autofocus: true,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onSubmitted: (_) => _saveDeviceName(),
                        )
                      : Text(device.name ?? device.id, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
                ),
                Container(width: 8, height: 8, decoration: BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle)),
                if (device.isHost) ...[
                  SizedBox(width: 8),
                  Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withAlpha(30), borderRadius: BorderRadius.circular(3)),
                    child: Text('HOST', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.primary))),
                ],
                SizedBox(width: 4),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0.0,
                  duration: Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, size: 20, color: ShadTheme.of(context).mutedForeground),
                ),
              ],
            ),
            // ═══ Subtitle (always visible, shows type / OS / IP) ═══
            Padding(
              padding: EdgeInsets.only(left: 30, top: 4),
              child: Text('$typeLabel · $osLabel · $ipLabel',
                style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
            ),
            // ═══ Expanded details ═══
            if (isExpanded) ...[
              SizedBox(height: 12),
              Divider(height: 1, color: ShadTheme.of(context).border),
              SizedBox(height: 10),
              // Device config header
              Row(
                children: [
                  Icon(Icons.settings, size: 14, color: ShadTheme.of(context).mutedForeground),
                  SizedBox(width: 6),
                  Text(AppLocalizations.of(context).deviceConfig, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ShadTheme.of(context).mutedForeground)),
                ],
              ),
              SizedBox(height: 8),
              // Editable name
              _editableRow(
                AppLocalizations.of(context).deviceNameLabel,
                device.name ?? device.id,
                () {
                  _deviceNameCtrl.text = device.name ?? '';
                  setState(() => _editingNameFor = device.id);
                },
                isEditing: isEditing,
              ),
              SizedBox(height: 8),
              // Detail rows
              _detailRow(AppLocalizations.of(context).deviceTypeLabel, typeLabel),
              _detailRow(AppLocalizations.of(context).devicePlatform, device.platform ?? AppLocalizations.of(context).notSet),
              _detailRow(AppLocalizations.of(context).deviceOs, osLabel),
              _detailRow(AppLocalizations.of(context).deviceIp, ipLabel),
              _detailRow(AppLocalizations.of(context).deviceConnectedAt, connectedTime),
              _detailRow(AppLocalizations.of(context).deviceIdLabel, deviceIdLabel),
            ],
          ],
        ),
      ),
    ),
  );
}

void _saveDeviceName() {
  _editingNameFor = null;
  _deviceNameCtrl.clear();
  setState(() {});
}

Widget _editableRow(String label, String value, VoidCallback onEdit, {bool isEditing = false}) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground))),
        Expanded(
          child: isEditing
              ? SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _deviceNameCtrl,
                    autofocus: true,
                    style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                    onSubmitted: (_) => _saveDeviceName(),
                  ),
                )
              : Row(
                  children: [
                    Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground))),
                    GestureDetector(
                      onTap: onEdit,
                      child: Icon(Icons.edit, size: 14, color: ShadTheme.of(context).mutedForeground),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground))),
      ],
    ),
  );
}

String _pad(int n) => n.toString().padLeft(2, '0');

Widget _lanTabBtn(String label, int index) {
final active = _lanTab == index;
return GestureDetector(
onTap: () => setState(() => _lanTab = index),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
decoration: BoxDecoration(
color: active ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(8),
),
child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
            color: active ? Theme.of(context).colorScheme.onPrimary : ShadTheme.of(context).mutedForeground)),
),
);
}

Widget _cardHeader(String title, IconData icon) {
return Row(
children: [
Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
SizedBox(width: 8),
Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
],
);
}

Widget _labeledField(String label, String hint, TextEditingController ctrl, {bool obscure = false}) {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
SizedBox(height: 4),
TextField(
controller: ctrl,
obscureText: obscure,
decoration: InputDecoration(
hintText: hint,
filled: true, fillColor: ShadTheme.of(context).secondary,
border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
    ),
    style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
    ),
    ],
    );
    }

    // ─── Logs Panel ──────────────────────────────────────────

    Widget _buildLogsPanel(AgentManager mgr) {
    final logService = LogService();
    final l10n = AppLocalizations.of(context);

    // Seed demo data on first open so the UI isn't empty.
    logService.seedDemoData();

    // Listen to log changes so the UI auto-refreshes.
    // NOTE: this builds a listener every build — for production,
    // register in initState / dispose. Fine for prototype.
    final filtered = logService.filtered(query: _logSearch, levels: _logLevels);

    return Column(
    children: [
    // ── Header ──
    Container(
    padding: EdgeInsets.all(24),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Row(
    children: [
    Icon(Icons.article_outlined, size: 22, color: ShadTheme.of(context).primary),
    SizedBox(width: 10),
    Text(l10n.logTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
    ],
    ),
    SizedBox(height: 4),
    Text(l10n.logSubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
    SizedBox(height: 16),
    // ── Search bar + actions row ──
    Row(
    children: [
    Expanded(
    flex: 2,
    child: TextField(
    onChanged: (v) => setState(() => _logSearch = v),
    decoration: InputDecoration(
    hintText: l10n.logSearch,
    prefixIcon: Icon(Icons.search, size: 18, color: ShadTheme.of(context).mutedForeground),
    filled: true,
    fillColor: ShadTheme.of(context).secondary,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide.none,
    ),
    isDense: true,
    ),
    style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
    ),
    ),
    SizedBox(width: 10),
    _logActionBtn(l10n.logExport, Icons.download, () => _exportLogs(l10n, logService)),
    SizedBox(width: 6),
    _logActionBtn(l10n.logClear, Icons.delete_outline, () => _confirmClearLogs(l10n, logService)),
    ],
    ),
    // ── Filter chips ──
    SizedBox(height: 12),
    SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
    children: [
    _logFilterChip(l10n.logAll, null),
    ...LogLevel.values.map((lvl) => _logFilterChip(lvl.label, lvl)),
    ],
    ),
    ),
    ],
    ),
    ),
    Divider(height: 1, color: ShadTheme.of(context).border),

    // ── Count ──
    Padding(
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    child: Row(
    children: [
    Text(
    l10n.logCount.replaceAll('\$count', '${filtered.length}'),
    style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground),
    ),
    Spacer(),
    Text(
    '${_logLevels.length == LogLevel.values.length ? l10n.logAll : _logLevels.map((l) => l.label).join(', ')}',
    style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground),
    ),
    ],
    ),
    ),
    Divider(height: 1, color: ShadTheme.of(context).border),

    // ── Log list ──
    Expanded(
    child: filtered.isEmpty
    ? Center(
    child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
    Icon(Icons.inbox_outlined, size: 48, color: ShadTheme.of(context).mutedForeground.withAlpha(80)),
    SizedBox(height: 12),
    Text(l10n.logEmpty, style: TextStyle(fontSize: 15, color: ShadTheme.of(context).mutedForeground)),
    SizedBox(height: 4),
    Text(l10n.logEmptyHint, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
    ],
    ),
    )
    : ListView.builder(
    padding: EdgeInsets.symmetric(vertical: 4),
    itemCount: filtered.length,
    itemBuilder: (_, i) => _logEntryTile(filtered[i], l10n),
    ),
    ),
    ],
    );
    }

    Widget _buildPrivacyPanel(AgentManager mgr) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
    padding: EdgeInsets.all(24),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // ── Header ──
    Row(
    children: [
    Icon(Icons.privacy_tip_outlined, size: 22, color: ShadTheme.of(context).primary),
    SizedBox(width: 10),
    Text(l10n.privacyTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
    ],
    ),
    SizedBox(height: 4),
    Text(l10n.privacySubtitle, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
    SizedBox(height: 24),
    // ── Clear Cache Card ──
    Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
    color: ShadTheme.of(context).card,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: ShadTheme.of(context).border),
    ),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    Row(
    children: [
    Icon(Icons.cleaning_services_outlined, size: 20, color: ShadTheme.of(context).destructive),
    SizedBox(width: 8),
    Expanded(
    child: Text(l10n.privacyClearCache, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
    ),
    ],
    ),
    SizedBox(height: 6),
    Text(l10n.privacyClearCacheDesc, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
    SizedBox(height: 12),
    OutlinedButton.icon(
    onPressed: () => _confirmClearCache(mgr),
    icon: Icon(Icons.delete_outline, size: 16),
    label: Text(l10n.privacyClearCacheButton),
    style: OutlinedButton.styleFrom(
    foregroundColor: ShadTheme.of(context).destructive,
    side: BorderSide(color: ShadTheme.of(context).destructive),
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    ),
    ],
    ),
    ),
    ],
    ),
    );
    }

    void _confirmClearCache(AgentManager mgr) {
    final l10n = AppLocalizations.of(context);
    showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
    backgroundColor: ShadTheme.of(context).card,
    title: Text(l10n.privacyClearCache, style: TextStyle(color: ShadTheme.of(context).foreground)),
    content: Text(l10n.privacyClearCacheConfirm, style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
    actions: [
    TextButton(
    onPressed: () => Navigator.pop(ctx),
    child: Text(l10n.cancel, style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
    ),
    ElevatedButton(
    onPressed: () async {
    await mgr.clearAllCache();
    Navigator.pop(ctx);
    if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
    content: Text(l10n.privacyCacheCleared),
    backgroundColor: ShadTheme.of(context).card,
    ),
    );
    }
    },
    style: ElevatedButton.styleFrom(
    backgroundColor: ShadTheme.of(context).destructive,
    ),
    child: Text(l10n.privacyClearCacheButton, style: TextStyle(color: Colors.white)),
    ),
    ],
    ),
    );
    }

    Widget _logFilterChip(String label, LogLevel? level) {
    final active = level == null
    ? _logLevels.length == LogLevel.values.length
    : _logLevels.contains(level);
    return GestureDetector(
    onTap: () {
    setState(() {
    if (level == null) {
    // "All" — toggle all on/off
    if (_logLevels.length == LogLevel.values.length) {
    _logLevels.clear();
    } else {
    _logLevels.addAll(LogLevel.values);
    }
    } else {
    if (_logLevels.contains(level)) {
    _logLevels.remove(level);
    } else {
    _logLevels.add(level);
    }
    }
    });
    },
    child: Container(
    margin: EdgeInsets.only(right: 6),
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
    color: active ? _logLevelColor(level).withAlpha(30) : ShadTheme.of(context).secondary,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
    color: active ? _logLevelColor(level) : ShadTheme.of(context).border,
    ),
    ),
    child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
    if (level != null) ...[
    Container(
    width: 8, height: 8,
    margin: EdgeInsets.only(right: 5),
    decoration: BoxDecoration(color: _logLevelColor(level), shape: BoxShape.circle),
    ),
    ],
    Text(label, style: TextStyle(
    fontSize: 12, fontWeight: FontWeight.w500,
    color: active ? _logLevelColor(level) : ShadTheme.of(context).mutedForeground,
    )),
    ],
    ),
    ),
    );
    }

    Widget _logEntryTile(LogEntry entry, AppLocalizations l10n) {
    final isExpanded = _expandedLogId == entry.id;
    final color = _logLevelColor(entry.level);
    final timeStr = _formatTime(entry.timestamp);

    return Column(
    children: [
    GestureDetector(
    onTap: () => setState(() => _expandedLogId = isExpanded ? null : entry.id),
    child: Container(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: isExpanded ? ShadTheme.of(context).secondary.withAlpha(80) : null,
    child: Row(
    children: [
    // Level dot
    Container(
    width: 8, height: 8,
    margin: EdgeInsets.only(right: 10),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
    // Badge
    Container(
    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    margin: EdgeInsets.only(right: 8),
    decoration: BoxDecoration(
    color: color.withAlpha(25),
    borderRadius: BorderRadius.circular(3),
    border: Border.all(color: color.withAlpha(60)),
    ),
    child: Text(entry.level.label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    ),
    // Brief message
    Expanded(
    child: Text(
    entry.message,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground),
    ),
    ),
    SizedBox(width: 8),
    // Time
    Text(timeStr, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
    SizedBox(width: 4),
    // Expand chevron
    Icon(
    isExpanded ? Icons.expand_less : Icons.expand_more,
    size: 16,
    color: ShadTheme.of(context).mutedForeground,
    ),
    ],
    ),
    ),
    ),
    // ── Expanded detail ──
    if (isExpanded)
    Container(
    padding: EdgeInsets.fromLTRB(24, 8, 24, 14),
    color: ShadTheme.of(context).secondary.withAlpha(60),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    _logDetailRow(l10n.logLevel,
    Row(children: [
    Container(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
    color: color.withAlpha(25),
    borderRadius: BorderRadius.circular(4),
    border: Border.all(color: color.withAlpha(60)),
    ),
    child: Text(entry.level.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    ),
    ]),
    ),
    _logDetailRow(
    l10n.logTime,
    Text(timeStr, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground)),
    ),
    _logDetailRow(l10n.logModule, Text(entry.module, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground))),
    _logDetailRow(l10n.logMessage, Text(entry.message, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground))),
    if (entry.stackTrace != null && entry.stackTrace!.isNotEmpty) ...[
    SizedBox(height: 8),
    Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    SizedBox(
    width: 70,
    child: Text(l10n.logStackTrace, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ShadTheme.of(context).mutedForeground)),
    ),
    Expanded(
    child: Container(
    padding: EdgeInsets.all(10),
    decoration: BoxDecoration(
    color: Colors.black.withAlpha(60),
    borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
    entry.stackTrace!,
    style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: ShadTheme.of(context).foreground.withAlpha(200), height: 1.5),
    ),
    ),
    ),
    ],
    ),
    ],
    ],
    ),
    ),
    Divider(height: 1, color: ShadTheme.of(context).border.withAlpha(60)),
    ],
    );
    }

    Widget _logDetailRow(String label, Widget value) {
    return Padding(
    padding: EdgeInsets.symmetric(vertical: 3),
    child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    SizedBox(
    width: 70,
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: ShadTheme.of(context).mutedForeground)),
    ),
    Expanded(child: value),
    ],
    ),
    );
    }

    Widget _logActionBtn(String tooltip, IconData icon, VoidCallback onTap) {
    return GestureDetector(
    onTap: onTap,
    child: Container(
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
    color: ShadTheme.of(context).secondary,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: ShadTheme.of(context).border),
    ),
    child: Icon(icon, size: 18, color: ShadTheme.of(context).mutedForeground),
    ),
    );
    }

    Color _logLevelColor(LogLevel? level) {
    switch (level) {
    case LogLevel.debug: return const Color(0xFF90A4AE);
    case LogLevel.info:  return const Color(0xFF42A5F5);
    case LogLevel.warn:  return const Color(0xFFFFA726);
    case LogLevel.error: return const Color(0xFFEF5350);
    default:             return const Color(0xFF90A4AE);
    }
    }

    String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    if (d == today) return time;
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
    return '${dt.month}/${dt.day} $time';
    }

    void _exportLogs(AppLocalizations l10n, LogService logService) {
    // For now, just notify — file save dialog would require file_picker package.
    // Output is available via LogService.exportJson().
    final json = logService.exportJson();
    debugPrint('=== LOG EXPORT ===\n$json');
    ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
    content: Text(l10n.logExported),
    backgroundColor: ShadTheme.of(context).card,
    duration: const Duration(seconds: 2),
    ),
    );
    }

    void _confirmClearLogs(AppLocalizations l10n, LogService logService) {
    showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
    backgroundColor: ShadTheme.of(context).card,
    title: Text(l10n.logClear, style: TextStyle(color: ShadTheme.of(context).foreground)),
    content: Text(l10n.logClearConfirm, style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
    actions: [
    TextButton(
    onPressed: () => Navigator.pop(ctx),
    child: Text(l10n.cancel, style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
    ),
    TextButton(
    onPressed: () {
    logService.clear();
    setState(() {});
    Navigator.pop(ctx);
    },
    child: Text(l10n.logClear, style: TextStyle(color: ShadTheme.of(context).destructive)),
    ),
    ],
    ),
    );
    }

    // ══════════════════════════════════════════════════════════
    // Content Area (Empty State or Chat)
// ══════════════════════════════════════════════════════════

Widget _buildContentArea(AgentManager mgr) {
if (_showSettings) {
return _buildSettingsPage(mgr);
}
if (_selectedSkillId != null && _skillsMode) {
return _buildSkillDetailView(mgr);
}
if (_showEmployeeDetail && mgr.activeEmployeeId != null) {
return _buildEmployeeDetailView(mgr);
}
if (mgr.activeEmployeeId == null) {
return _buildEmptyState();
}
return _buildChatPanel(mgr);
}

Widget _buildEmptyState() {
return Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.chat_bubble_outline, size: 56, color: ShadTheme.of(context).mutedForeground.withAlpha(100)),
SizedBox(height: 16),
Text(AppLocalizations.of(context).waEmptyHint,
style: TextStyle(fontSize: 15, color: ShadTheme.of(context).mutedForeground)),
SizedBox(height: 6),
Text(AppLocalizations.of(context).waEmptySub,
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
],
),
);
}

// ══════════════════════════════════════════════════════════
// Chat Panel
// ══════════════════════════════════════════════════════════

Widget _buildThinkingIndicator() {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(ShadTheme.of(context).mutedForeground),
          ),
        ),
        SizedBox(width: 8),
        Text('Thinking...', style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
      ],
    ),
  );
}

void _showNewConversationDialog(AgentManager mgr) {
  final employees = mgr.employees;
  if (employees.isEmpty) {
    // No employees yet — prompt to create one
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ShadTheme.of(context).card,
        title: Text('No Employees', style: TextStyle(color: ShadTheme.of(context).foreground)),
        content: Text('Create an AI employee first in the Contacts tab.',
          style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: ShadTheme.of(context).mutedForeground))),
        ],
      ),
    );
    return;
  }
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ShadTheme.of(context).card,
      title: Text('New Conversation', style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 15)),
      content: SizedBox(
        width: 350,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: employees.length,
          itemBuilder: (_, i) {
            final emp = employees[i];
            return ListTile(
              leading: Icon(Icons.smart_toy, color: Theme.of(context).colorScheme.primary),
              title: Text(emp.name, style: TextStyle(color: ShadTheme.of(context).foreground)),
              subtitle: emp.description != null && emp.description!.isNotEmpty
                  ? Text(emp.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground))
                  : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              tileColor: ShadTheme.of(context).secondary,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              onTap: () {
                Navigator.pop(ctx);
                _selectAgent(emp, mgr);
              },
            );
          },
        ),
      ),
    ),
  );
}

Widget _buildChatPanel(AgentManager mgr) {
final statusColor = mgr.activeAgentStatus == 'streaming'
? Color(0xFF4CAF50)
: mgr.activeAgentStatus == 'processing'
? Color(0xFFFFC107)
: Color(0xFF888888);

return Column(
children: [
// Agent header
Container(
padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
color: ShadTheme.of(context).card,
child: Row(
children: [
GestureDetector(
onTap: () {
  _lastMsgCount = 0;
  mgr.closeAgent();
},
child: Icon(Icons.arrow_back, size: 20, color: ShadTheme.of(context).mutedForeground),
),
SizedBox(width: 10),
Icon(Icons.smart_toy, size: 20, color: ShadTheme.of(context).foreground),
SizedBox(width: 8),
Expanded(
child: Text(
mgr.activeEmployeeName ?? 'Agent',
style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: ShadTheme.of(context).foreground),
),
),
Container(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
decoration: BoxDecoration(
color: statusColor.withAlpha(30),
borderRadius: BorderRadius.circular(4),
border: Border.all(color: statusColor.withAlpha(80)),
),
child: Text(mgr.activeAgentStatus.toUpperCase(),
style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
),
SizedBox(width: 4),
GestureDetector(
onTap: () {
  mgr.refreshEmployeeSkills();
  setState(() => _showEmployeeDetail = true);
},
child: Icon(Icons.more_vert, size: 20, color: ShadTheme.of(context).mutedForeground),
),
SizedBox(width: 4),
GestureDetector(
onTap: mgr.interruptAgent,
child: Icon(Icons.stop, size: 18, color: ShadTheme.of(context).mutedForeground),
),
],
),
),
      Divider(height: 1, color: ShadTheme.of(context).border),
      // Messages
      Expanded(
        child: mgr.activeMessages.isEmpty
            ? Center(
                child: Text('Start a conversation', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
              )
            : Builder(builder: (context) {
                final totalItems = mgr.activeMessages.length + (mgr.activeAgentStatus == 'processing' || mgr.activeAgentStatus == 'streaming' ? 1 : 0);
                // Auto-scroll only when new messages arrive (not on every rebuild)
                if (mgr.activeMessages.length > _lastMsgCount) {
                  _lastMsgCount = mgr.activeMessages.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollCtrl.hasClients) {
                      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
                        duration: Duration(milliseconds: 150), curve: Curves.easeOut);
                    }
                  });
                }
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.all(16),
                  itemCount: totalItems,
                  itemBuilder: (_, i) {
                    if (i < mgr.activeMessages.length) {
                      return _msgBubble(mgr.activeMessages[i]);
                    }
                    return _buildThinkingIndicator();
                  },
                );
              }),
      ),
Divider(height: 1, color: ShadTheme.of(context).border),
// Profile switcher
if (mgr.activeProfile != null)
Padding(
padding: EdgeInsets.fromLTRB(16, 6, 16, 2),
child: Align(
alignment: Alignment.centerLeft,
child: GestureDetector(
onTap: () {
final dummy = _DummyAgent(mgr.activeEmployeeId ?? '', mgr.activeEmployeeName ?? '');
_showProfilePicker(dummy, mgr);
},
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(
color: Theme.of(context).colorScheme.primary.withAlpha(20),
borderRadius: BorderRadius.circular(12),
border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(50)),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.api, size: 13, color: Theme.of(context).colorScheme.primary),
SizedBox(width: 5),
Text(mgr.activeProfile!.name,
style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
SizedBox(width: 6),
Icon(Icons.swap_horiz, size: 12, color: ShadTheme.of(context).mutedForeground),
SizedBox(width: 4),
Text(mgr.activeProfile!.model,
style: TextStyle(fontSize: 10, color: ShadTheme.of(context).mutedForeground)),
],
),
),
),
),
),
// Input
_buildChatInput(mgr),
],
);
}

Widget _msgBubble(Map<String, dynamic> msg) {
final isUser = (msg['role'] ?? 'user') == 'user';
final content = msg['content']?.toString() ?? '';
final type = msg['type']?.toString() ?? 'text';
final toolName = msg['toolName']?.toString();
final toolResult = msg['toolResult']?.toString();
final toolCalls = msg['toolCalls'] as List?;

// Determine if this message has tool-related data
final hasToolCalls = toolCalls != null && toolCalls.isNotEmpty;
final hasToolName = toolName != null && toolName.isNotEmpty;
final hasToolResult = toolResult != null && toolResult.isNotEmpty;
final isToolMessage = type == 'functionCall' || type == 'functionResult';

  return Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primary.withAlpha(25)
                : isToolMessage
                    ? Theme.of(context).colorScheme.primary.withAlpha(8)
                    : ShadTheme.of(context).secondary,
            borderRadius: BorderRadius.circular(12),
            border: isToolMessage
                ? Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(40))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Tool call header ──
              if (isToolMessage && hasToolName)
                _buildToolCallHeader(toolName!, hasToolResult),
              // ── Tool calls list ──
              if (hasToolCalls)
                ...toolCalls!.map((tc) => _buildToolCallItem(tc as Map<String, dynamic>)),
              // ── Content (markdown if assistant, plain text if user) ──
              if (content.isNotEmpty)
                isUser
                    ? Text(content, style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground, height: 1.5))
                    : _buildAssistantContent(content),
              // ── Tool result (collapsible) ──
              if (hasToolResult)
                _buildToolResultSection(toolResult!),
            ],
          ),
        ),
        _CopyButton(content: content),
      ],
    ),
  );
}

/// Collapsible tool result section.
Widget _buildToolResultSection(String result) {
  return _CollapsibleSection(
    title: '执行结果',
    icon: Icons.check_circle_outline,
    color: Color(0xFF4CAF50),
    initiallyExpanded: true,
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(result,
        style: TextStyle(fontSize: 12, fontFamily: 'monospace',
          color: ShadTheme.of(context).foreground.withAlpha(200), height: 1.5)),
    ),
  );
}

/// Individual tool call item with arguments.
Widget _buildToolCallItem(Map<String, dynamic> tc) {
  final tcName = tc['name']?.toString() ?? '';
  final tcArgs = tc['arguments'];
  return _CollapsibleSection(
    title: '函数: $tcName',
    icon: Icons.code,
    color: Theme.of(context).colorScheme.primary,
    initiallyExpanded: false,
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('调用参数',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: ShadTheme.of(context).mutedForeground)),
          SizedBox(height: 4),
          Text(
            tcArgs != null
              ? (tcArgs is String ? tcArgs : _prettyJson(tcArgs))
              : '(无参数)',
            style: TextStyle(fontSize: 11, fontFamily: 'monospace',
              color: ShadTheme.of(context).foreground.withAlpha(200), height: 1.5)),
        ],
      ),
    ),
  );
}

/// Assistant content with markdown rendering.
Widget _buildAssistantContent(String content) {
  return MarkdownBody(
    data: content,
    selectable: true,
    styleSheet: MarkdownStyleSheet(
      p: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground, height: 1.5),
      code: TextStyle(fontSize: 13, fontFamily: 'monospace',
        color: ShadTheme.of(context).foreground,
        backgroundColor: ShadTheme.of(context).secondary),
      codeblockDecoration: BoxDecoration(
        color: Colors.black.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquoteDecoration: BoxDecoration(
        color: ShadTheme.of(context).secondary,
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)),
      ),
    ),
  );
}

String _prettyJson(dynamic obj) {
  try {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(obj);
  } catch (_) {
    return obj.toString();
  }
}

/// Tool call header badge.
Widget _buildToolCallHeader(String name, bool hasResult) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(60)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.build, size: 13, color: Theme.of(context).colorScheme.primary),
              SizedBox(width: 4),
              Text(hasResult ? 'TOOL RESULT: $name' : 'TOOL CALL: $name',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildChatInput(AgentManager mgr) {
  final l10n = AppLocalizations.of(context);
  final theme = ShadTheme.of(context);
  final primary = Theme.of(context).colorScheme.primary;

  // Count enabled skills attached to active agent
  final enabledSkills = mgr.skills.where((s) => s.enabled == 1).length;

  return Container(
    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
    color: theme.card,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900),
        child: AnimatedBuilder(
          animation: _msgCtrl,
          builder: (context, _) {
            final hasText = _msgCtrl.text.trim().isNotEmpty;
            return Container(
              decoration: BoxDecoration(
                color: theme.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.border?.withAlpha(80) ?? Color(0xFFECECEC)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Row 1: Context Pills ──
                  if (enabledSkills > 0 || mgr.activeProfile != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Skills pill
                          if (enabledSkills > 0)
                            _contextPill(
                              icon: Icons.extension_outlined,
                              label: l10n.skills,
                              count: enabledSkills,
                              onTap: () => setState(() {
                                _skillsMode = true;
                                _contactsMode = false;
                              }),
                              theme: theme,
                            ),
                          // Active model pill
                          if (mgr.activeProfile != null)
                            _contextPill(
                              icon: Icons.auto_awesome,
                              label: mgr.activeProfile!.model,
                              count: null,
                              onTap: () {
                                final dummy = _DummyAgent(
                                  mgr.activeEmployeeId ?? '',
                                  mgr.activeEmployeeName ?? '',
                                );
                                _showProfilePicker(dummy, mgr);
                              },
                              theme: theme,
                            ),
                          // Add context button
                          _addContextPill(theme),
                        ],
                      ),
                    ),
                  // ── Row 2: Input area ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: _SmoothCursorField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.waSendMessage,
                        hintStyle: TextStyle(
                          color: theme.mutedForeground,
                          fontSize: 15,
                        ),
                        filled: true,
                        fillColor: theme.card,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        isDense: true,
                      ),
                      style: TextStyle(fontSize: 15, height: 24 / 15, color: theme.foreground),
                      maxLines: 5,
                      minLines: 1,
                      onSubmitted: (t) => _send(t, mgr),
                    ),
                  ),
                  // ── Row 3: Bottom toolbar ──
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(
                      children: [
                        // Left: Employee/Workspace selector
                        if (mgr.activeEmployeeName != null)
                          _bottomSelector(
                            icon: Icons.folder_outlined,
                            label: mgr.activeEmployeeName!,
                            onTap: () => setState(() {
                              _contactsMode = true;
                              _skillsMode = false;
                            }),
                            theme: theme,
                          ),
                        SizedBox(width: 6),
                        // Model selector
                        if (mgr.activeProfile != null)
                          _bottomSelector(
                            icon: Icons.auto_awesome,
                            label: mgr.activeProfile!.name,
                            onTap: () {
                              final dummy = _DummyAgent(
                                mgr.activeEmployeeId ?? '',
                                mgr.activeEmployeeName ?? '',
                              );
                              _showProfilePicker(dummy, mgr);
                            },
                            theme: theme,
                          ),
                        Spacer(),
                        // Right: Send button
                        _sendButton(hasText, primary, theme, mgr),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Context pill (capsule tag with icon + label + optional count badge).
Widget _contextPill({
  required IconData icon,
  required String label,
  int? count,
  required VoidCallback onTap,
  required dynamic theme,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 30,
      padding: EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.border?.withAlpha(80) ?? Color(0xFFE0E0E0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: ShadTheme.of(context).mutedForeground),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ShadTheme.of(context).foreground,
            ),
          ),
          if (count != null) ...[
            SizedBox(width: 5),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ShadTheme.of(context).mutedForeground.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: ShadTheme.of(context).mutedForeground,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// "+" add context pill.
Widget _addContextPill(dynamic theme) {
  return GestureDetector(
    onTap: () => setState(() {
      _skillsMode = true;
      _contactsMode = false;
    }),
    child: Container(
      height: 30,
      width: 30,
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.border?.withAlpha(60) ?? Color(0xFFE0E0E0),
        ),
      ),
      child: Icon(
        Icons.add,
        size: 15,
        color: ShadTheme.of(context).mutedForeground,
      ),
    ),
  );
}

/// Bottom toolbar selector button (workspace / model).
Widget _bottomSelector({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  required dynamic theme,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: ShadTheme.of(context).secondary.withAlpha(100),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ShadTheme.of(context).mutedForeground),
          SizedBox(width: 5),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: ShadTheme.of(context).foreground,
              ),
            ),
          ),
          SizedBox(width: 3),
          Icon(Icons.keyboard_arrow_down, size: 14, color: ShadTheme.of(context).mutedForeground),
        ],
      ),
    ),
  );
}

/// Send button — disabled (gray) when empty, primary color when has text.
Widget _sendButton(bool hasText, Color primary, dynamic theme, AgentManager mgr) {
  return GestureDetector(
    onTap: hasText ? () => _send(_msgCtrl.text, mgr) : null,
    child: AnimatedContainer(
      duration: Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 34,
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: hasText ? primary : (theme.mutedForeground?.withAlpha(40) ?? Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context).waSend,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: hasText ? Colors.white : (theme.mutedForeground ?? Color(0xFF999999)),
            ),
          ),
          SizedBox(width: 5),
          Icon(Icons.arrow_upward, size: 15,
            color: hasText ? Colors.white : (theme.mutedForeground ?? Color(0xFF999999))),
        ],
      ),
    ),
  );
}

void _send(String text, AgentManager mgr) {
final t = text.trim();
if (t.isEmpty) return;
_msgCtrl.clear();
mgr.sendMessage(t);
WidgetsBinding.instance.addPostFrameCallback((_) {
if (_scrollCtrl.hasClients) {
_scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
duration: Duration(milliseconds: 200), curve: Curves.easeOut);
}
});
}

  void _selectAgent(dynamic agent, AgentManager mgr) {
  _lastMsgCount = 0; // Reset for new conversation
  final profiles = mgr.providerProfiles;
if (profiles.isEmpty) return;

// Check if this employee has a last-used profile
final lastIdx = mgr.getLastProfileIndex(agent.uuid as String);
if (lastIdx != null && lastIdx < profiles.length) {
// Auto-use the last profile
mgr.openAgentWithProfile(agent.uuid, agent.name, lastIdx);
return;
}

// Single profile: auto-select
if (profiles.length == 1) {
mgr.openAgentWithProfile(agent.uuid, agent.name, 0);
return;
}

// Multiple profiles, no last-used: show picker
_showProfilePicker(agent, mgr);
}

void _showProfilePicker(dynamic agent, AgentManager mgr) {
final profiles = mgr.providerProfiles;
showDialog(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: ShadTheme.of(context).card,
title: Text(AppLocalizations.of(context).waSelectProfile, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 15)),
content: SizedBox(
width: 350,
child: ListView.builder(
shrinkWrap: true,
itemCount: profiles.length,
itemBuilder: (_, i) {
final p = profiles[i];
return ListTile(
leading: Icon(Icons.api, color: Theme.of(context).colorScheme.primary),
title: Text(p.name, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 14)),
subtitle: Text('${p.model}  •  ${p.baseUrl}',
style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
tileColor: ShadTheme.of(context).secondary,
contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
onTap: () {
Navigator.pop(ctx);
mgr.openAgentWithProfile(agent.uuid, agent.name, i);
},
);
},
),
),
),
);
}

  // ══════════════════════════════════════════════════════════
  // Skills List
  // ══════════════════════════════════════════════════════════

  Widget _buildSkillsList(AgentManager mgr) {
    final l10n = AppLocalizations.of(context);
    final skills = mgr.skills;
    if (skills.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(l10n.skillNoSkills,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
        ),
      );
    }
    final filtered = _searchQuery.isEmpty
        ? skills
        : skills.where((s) =>
            s.name.toLowerCase().contains(_searchQuery) ||
            (s.description ?? '').toLowerCase().contains(_searchQuery)).toList();
    return ListView(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Text('SKILLS (${filtered.length})',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
              color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
        ),
        if (filtered.isEmpty)
          Padding(
            padding: EdgeInsets.all(12),
            child: Text(l10n.waNoMatching,
              style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
          )
        else
          ...filtered.map((s) => _skillTile(s, mgr)),
      ],
    );
  }

  Widget _skillTile(GlobalSkillEntity skill, AgentManager mgr) {
    final isSelected = _selectedSkillId == skill.uuid;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() => _selectedSkillId = skill.uuid),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? ShadTheme.of(context).sidebarAccent : ShadTheme.of(context).secondary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                skill.skillType == 'folder' ? Icons.folder_outlined : Icons.settings,
                size: 16,
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimary
                    : (skill.enabled == 1 ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(skill.name,
                      style: TextStyle(fontSize: 13,
                        color: isSelected ? Theme.of(context).colorScheme.onPrimary : ShadTheme.of(context).foreground),
                      overflow: TextOverflow.ellipsis),
                    if (skill.description != null && skill.description!.isNotEmpty)
                      Text(skill.description!,
                        style: TextStyle(fontSize: 10,
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary.withAlpha(180)
                                : ShadTheme.of(context).mutedForeground),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (skill.enabled == 1)
                Container(
                  width: 6, height: 6,
                  margin: EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // Add Skill Dialog
  // ══════════════════════════════════════════════════════════

  void _showAddSkillDialog() {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String folderPath = '';

    bool isMcp = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ShadTheme.of(context).card,
          title: Text(l10n.skillAddTitle, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 16)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type selector
                  Row(children: [
                    _typeChip('Folder', Icons.folder_outlined, !isMcp,
                      () => setDialogState(() => isMcp = false)),
                    SizedBox(width: 8),
                    _typeChip('MCP', Icons.settings_ethernet, isMcp,
                      () => setDialogState(() => isMcp = true)),
                  ]),
                  SizedBox(height: 12),
                  SizedBox(width: 460,
                    child: TextField(controller: nameCtrl,
                      decoration: InputDecoration(labelText: l10n.skillName, hintText: l10n.skillNameHint,
                        filled: true, fillColor: ShadTheme.of(context).secondary,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true))),
                  SizedBox(height: 12),
                  SizedBox(width: 460,
                    child: TextField(controller: descCtrl, maxLines: 2,
                      decoration: InputDecoration(labelText: l10n.skillDesc, hintText: l10n.skillDescHint,
                        filled: true, fillColor: ShadTheme.of(context).secondary,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true))),
                  SizedBox(height: 16),
                  if (!isMcp) ...[
                    Text(l10n.skillFolderPath, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
                    SizedBox(height: 4),
                    Text(l10n.skillFolderHint, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
                    SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(color: ShadTheme.of(context).secondary, borderRadius: BorderRadius.circular(8)),
                        child: Text(folderPath.isEmpty ? l10n.skillFolderHint : folderPath,
                          style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground),
                          maxLines: 1, overflow: TextOverflow.ellipsis))),
                      SizedBox(width: 8),
                      OutlinedButton(onPressed: () async {
                        final picked = await _showFolderBrowserDialog();
                        if (picked != null) setDialogState(() => folderPath = picked);
                      }, child: Text(l10n.skillBrowse)),
                    ]),
                  ] else ...[
                    Text('Uses MCP servers configured in Settings → MCP Config',
                      style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final mgr = context.read<AgentManager>();
                if (isMcp) {
                  await mgr.createMcpSkill(name: name,
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    serverConfig: McpServerConfig(name: name, transportType: 'http', url: ''));
                } else {
                  if (folderPath.isEmpty) return;
                  await mgr.createSkill(name: name,
                    description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(), folderPath: folderPath);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
              child: Text(l10n.create),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String label, IconData? icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary.withAlpha(25) : ShadTheme.of(context).secondary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: selected ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).mutedForeground), SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Theme.of(context).colorScheme.primary : ShadTheme.of(context).mutedForeground)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // Folder Browser Dialog
  // ══════════════════════════════════════════════════════════

  Future<String?> _showFolderBrowserDialog() async {
    final l10n = AppLocalizations.of(context);
    String currentPath = '';
    List<String> drives = [];
    try {
      if (Platform.isWindows) {
        for (var letter in ['C', 'D', 'E', 'F', 'G']) {
          final drive = '$letter:\\';
          if (await Directory(drive).exists()) drives.add(drive);
        }
      }
    } catch (_) {
      drives = ['C:\\', 'D:\\'];
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String folderSearchFilter = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: ShadTheme.of(context).card,
            title: Text(l10n.skillSelectFolder, style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 16)),
            content: SizedBox(
              width: 550, height: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    _browseModeButton(l10n.skillSelectFolder, true),
                    SizedBox(width: 8),
                    _browseModeButton(l10n.skillSelectZip, false, compact: true, onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.comingSoon), duration: Duration(seconds: 2)));
                    }),
                  ]),
                  SizedBox(height: 8),
                  Divider(color: ShadTheme.of(context).border),
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.skillSearchFolder,
                      prefixIcon: Icon(Icons.search, size: 18, color: ShadTheme.of(context).mutedForeground),
                      filled: true, fillColor: ShadTheme.of(context).secondary,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    style: TextStyle(fontSize: 13),
                    onChanged: (v) => setDialogState(() => folderSearchFilter = v),
                  ),
                  SizedBox(height: 8),
                  if (currentPath.isEmpty)                     // <-- fixed: empty = show drives
                    Expanded(
                      child: ListView(
                        children: drives.map((d) => ListTile(
                          dense: true,
                          leading: Icon(Icons.storage, size: 18, color: ShadTheme.of(context).mutedForeground),
                          title: Text(d, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
                          trailing: Icon(Icons.chevron_right, size: 16),
                          onTap: () => setDialogState(() => currentPath = d),
                        )).toList(),
                      ),
                    )
                  else                                        // <-- fixed: non-empty = browse folders
                    Expanded(
                      child: _buildFolderContents(currentPath, (String newPath) {
                        if (newPath == '..') {
                          final parent = Directory(currentPath).parent.path;
                          // If parent is same as current (drive root), go back to drive selection
                          if (parent == currentPath || parent.length <= 3) {
                            setDialogState(() { currentPath = ''; folderSearchFilter = ''; });
                          } else {
                            setDialogState(() { currentPath = parent; folderSearchFilter = ''; });
                          }
                        } else {
                          setDialogState(() { currentPath = newPath; folderSearchFilter = ''; });
                        }
                      }, filter: folderSearchFilter),
                    ),
                  SizedBox(height: 8),
                  if (currentPath.isNotEmpty)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ShadTheme.of(context).secondary, borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        Expanded(child: Text(currentPath,
                          style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
              if (currentPath.isNotEmpty)
                TextButton(onPressed: () => Navigator.pop(ctx, currentPath), child: Text(l10n.skillConfirm)),
            ],
          ),
        );
      },
    );
    return result;
  }

  Widget _browseModeButton(String label, bool isFolder, {bool compact = false, VoidCallback? onPressed}) {
    return OutlinedButton(
      onPressed: onPressed ?? () {},
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 6),
        minimumSize: Size(0, 32),
      ),
      child: Text(label, style: TextStyle(fontSize: compact ? 11 : 12)),
    );
  }

  Widget _buildFolderContents(String path, Function(String) onNavigate, {String filter = ''}) {
    final dir = Directory(path);
    List<FileSystemEntity> allEntries = [];
    try {
      allEntries = dir.listSync().toList();
      allEntries.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.compareTo(b.path);
      });
    } catch (_) {}

    final filtered = filter.isEmpty ? allEntries : allEntries.where((e) {
      final name = e.path.split(Platform.pathSeparator).last.toLowerCase();
      return name.contains(filter.toLowerCase());
    }).toList();

    final dirs = filtered.whereType<Directory>().toList();
    final files = filtered.whereType<File>().toList();

    return Column(children: [
      ListTile(
        dense: true,
        leading: Icon(Icons.arrow_upward, size: 18, color: ShadTheme.of(context).mutedForeground),
        title: Text('..', style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
        onTap: () => onNavigate('..'),
      ),
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text('No matching items',
                style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)))
            : ListView(
                children: [
                  ...dirs.map((e) {
                    final name = e.path.split(Platform.pathSeparator).last;
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.folder, size: 18, color: Color(0xFFF4B400)),
                      title: Text(name, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
                      trailing: Icon(Icons.chevron_right, size: 16),
                      onTap: () => onNavigate(e.path),
                    );
                  }),
                  ...files.map((f) {
                    final name = f.path.split(Platform.pathSeparator).last;
                    final ext = name.split('.').last.toLowerCase();
                    final icon = _fileIcon(ext);
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, size: 16, color: ShadTheme.of(context).mutedForeground),
                      title: Text(name, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
                    );
                  }),
                ],
              ),
      ),
    ]);
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'md': return Icons.description_outlined;
      case 'yaml':
      case 'yml': return Icons.settings_outlined;
      case 'dart': return Icons.code;
      case 'py': return Icons.code;
      case 'json': return Icons.data_object;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp': return Icons.image_outlined;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z': return Icons.folder_zip_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  // ══════════════════════════════════════════════════════════
  // Skill Detail View (Right Panel) — Global Skill
  // ══════════════════════════════════════════════════════════

  Widget _buildSkillDetailView(AgentManager mgr) {
    final l10n = AppLocalizations.of(context);
    final skill = mgr.skills.firstWhere(
      (s) => s.uuid == _selectedSkillId,
      orElse: () => throw Exception('Skill not found'),
    );
    final enabled = skill.enabled == 1;
    final typeLabel = skill.skillType == 'folder' ? 'Folder' : (skill.skillType == 'mcp' ? 'MCP' : 'Config');

    return Column(children: [
      Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: ShadTheme.of(context).card,
          border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _selectedSkillId = null),
            child: Icon(Icons.arrow_back, size: 20, color: ShadTheme.of(context).mutedForeground),
          ),
          SizedBox(width: 12),
          Icon(Icons.extension, size: 22, color: enabled ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground),
          SizedBox(width: 10),
          Expanded(child: Text(skill.name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground))),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(enabled ? 'Global' : 'Local',
              style: TextStyle(fontSize: 11, color: enabled ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground)),
            SizedBox(width: 6),
            Switch(value: enabled, onChanged: (_) async {
              await mgr.toggleSkillEnabled(skill.uuid);
              setState(() {});
            }, activeColor: Color(0xFF4CAF50)),
          ]),
          SizedBox(width: 8),
          IconButton(icon: Icon(Icons.delete_outline, size: 20, color: ShadTheme.of(context).mutedForeground),
            onPressed: () => _confirmDeleteSkill(mgr, skill), tooltip: l10n.skillDelete),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildDetailSection(l10n.skillConfig, [
              _buildDetailRow(l10n.skillFolderPath, skill.config ?? '-'),
            ]),
            SizedBox(height: 16),
            _buildDetailSection(l10n.skillInfo, [
              _buildDetailRow(l10n.skillId, skill.uuid),
              _buildDetailRow(l10n.skillType, typeLabel),
              _buildDetailRow(l10n.skillCreatedAt, _formatDateTime(skill.createTime)),
              _buildDetailRow(l10n.skillUpdatedAt, _formatDateTime(skill.updateTime)),
            ]),
            if (skill.description != null && skill.description!.isNotEmpty) ...[
              SizedBox(height: 16),
              _buildDetailSection(l10n.skillDesc, [
                Padding(padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(skill.description!, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground))),
              ]),
            ],
          ]),
        ),
      ),
    ]);
  }

  void _confirmDeleteSkill(AgentManager mgr, GlobalSkillEntity skill) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ShadTheme.of(context).card,
        title: Text(l10n.skillDelete, style: TextStyle(color: ShadTheme.of(context).foreground)),
        content: Text(l10n.skillDeleteConfirm.replaceAll(r'${name}', skill.name),
          style: TextStyle(color: ShadTheme.of(context).foreground)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(onPressed: () async {
            await mgr.deleteSkill(skill.uuid);
            setState(() => _selectedSkillId = null);
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: Text(l10n.delete, style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // Employee Detail Page (from ⋮ in chat header)
  // ══════════════════════════════════════════════════════════

  bool _showEmployeeDetail = false;

  Widget _buildEmployeeDetailView(AgentManager mgr) {
    final l10n = AppLocalizations.of(context);
    final emp = mgr.employees.firstWhere(
      (e) => e.uuid == mgr.activeEmployeeId,
      orElse: () => throw Exception('Employee not found'));
    final empSkills = mgr.employeeSkills;
    final globalSkills = mgr.skills;
    // Which global skills are already added to this employee
    final addedIds = empSkills.map((s) => s.globalSkillId).whereType<String>().toSet();

    return Column(children: [
      // Header
      Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: ShadTheme.of(context).card,
          border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() => _showEmployeeDetail = false),
            child: Icon(Icons.arrow_back, size: 20, color: ShadTheme.of(context).mutedForeground),
          ),
          SizedBox(width: 12),
          Icon(Icons.person_outline, size: 22, color: ShadTheme.of(context).mutedForeground),
          SizedBox(width: 10),
          Expanded(child: Text(emp.name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground))),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(padding: EdgeInsets.all(24), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Basic Info
          _buildDetailSection('Basic Info', [
            _buildDetailRow(l10n.skillName, emp.name),
            if (emp.description != null && emp.description!.isNotEmpty)
              _buildDetailRow(l10n.skillDesc, emp.description!),
          ]),
          SizedBox(height: 16),
          // Model Config
          _buildDetailSection('Model Config', [
            _buildDetailRow('Provider', emp.provider ?? '-'),
            _buildDetailRow('Model', emp.model ?? '-'),
          ]),
          SizedBox(height: 16),
          // Skills
          _buildDetailSection('Skills (${empSkills.length})', [
            if (empSkills.isEmpty)
              Padding(padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('No skills assigned', style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)))
            else
              ...empSkills.map((es) => Container(
                margin: EdgeInsets.only(bottom: 6),
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: ShadTheme.of(context).secondary,
                  borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(Icons.extension, size: 14, color: Color(0xFF4CAF50)),
                  SizedBox(width: 8),
                  Expanded(child: Text(es.name, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground))),
                  GestureDetector(
                    onTap: () => mgr.removeSkillFromEmployee(es.globalSkillId ?? es.uuid),
                    child: Icon(Icons.close, size: 16, color: ShadTheme.of(context).mutedForeground)),
                ]))),
            SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _showGlobalSkillPicker(mgr, addedIds),
              icon: Icon(Icons.add, size: 16),
              label: Text('Add from Global Library'),
              style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
            ),
          ]),
        ])),
      ),
    ]);
  }

  void _showGlobalSkillPicker(AgentManager mgr, Set<String> addedIds) {
    final l10n = AppLocalizations.of(context);
    final available = mgr.skills.where((s) => !addedIds.contains(s.uuid) && s.enabled == 1).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ShadTheme.of(context).card,
        title: Text('Global Skill Library', style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 16)),
        content: SizedBox(
          width: 400, height: 350,
          child: available.isEmpty
              ? Center(child: Text('No available skills',
                  style: TextStyle(color: ShadTheme.of(context).mutedForeground)))
              : ListView(
                  children: available.map((s) => ListTile(
                    leading: Icon(Icons.extension, size: 18, color: Color(0xFF4CAF50)),
                    title: Text(s.name, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
                    subtitle: s.description != null && s.description!.isNotEmpty
                        ? Text(s.description!, style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground))
                        : null,
                    onTap: () async {
                      await mgr.addSkillToEmployee(s.uuid);
                      if (ctx.mounted) Navigator.pop(ctx);
                      setState(() {});
                    },
                  )).toList(),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.close)),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // Chat Header ⋮ button
  // ══════════════════════════════════════════════════════════

  // The ⋮ button is rendered in _buildChatPanel which doesn't exist here yet.
  // We handle this via the _showEmployeeDetail flag in _buildContentArea.

  Widget _buildDetailSection(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
        color: ShadTheme.of(context).mutedForeground, letterSpacing: 0.8)),
      SizedBox(height: 8),
      Container(
        width: double.infinity, padding: EdgeInsets.all(16),
        decoration: BoxDecoration(color: ShadTheme.of(context).secondary, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    ]);
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground))),
      ],
    ));
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// TextField with smooth cursor animation using AnimatedPositioned.
class _SmoothCursorField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle style;
  final int maxLines;
  final int minLines;
  final void Function(String)? onSubmitted;
  const _SmoothCursorField({
    required this.controller, required this.decoration,
    required this.style, this.maxLines = 1, this.minLines = 1,
    this.onSubmitted,
  });
  @override
  State<_SmoothCursorField> createState() => _SmoothCursorFieldState();
}

class _SmoothCursorFieldState extends State<_SmoothCursorField> {
  final GlobalKey _textKey = GlobalKey();
  double _cursorX = 0;
  double _cursorY = 0;
  double _cursorH = 18;
  int _lastOffset = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final offset = sel.baseOffset;
    if (offset == _lastOffset) return;
    _lastOffset = offset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updatePos(offset);
    });
  }

  void _updatePos(int offset) {
    try {
      final renderObj = _textKey.currentContext?.findRenderObject();
      if (renderObj is RenderBox) {
        final editable = _findEditable(renderObj);
        if (editable != null) {
          final caretRect = editable.getLocalRectForCaret(
            TextPosition(offset: offset),
          );
          setState(() {
            _cursorX = caretRect.right + 5;
            _cursorY = caretRect.top;
            _cursorH = caretRect.height;
          });
          return;
        }
      }
    } catch (_) {}
    // Fallback: TextPainter (single-line only)
    final text = widget.controller.text;
    final o = offset.clamp(0, text.length);
    final tp = TextPainter(
      text: TextSpan(text: text.substring(0, o), style: widget.style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    setState(() => _cursorX = tp.width + 1.5);
  }

  RenderEditable? _findEditable(RenderObject obj) {
    if (obj is RenderEditable) return obj;
    if (obj is RenderBox) {
      for (final child in _childrenOf(obj)) {
        final found = _findEditable(child);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<RenderObject> _childrenOf(RenderBox box) {
    final result = <RenderObject>[];
    box.visitChildren((child) => result.add(child));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TextField(
          key: _textKey,
          controller: widget.controller,
          decoration: widget.decoration,
          style: widget.style,
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          onSubmitted: widget.onSubmitted,
          cursorColor: Colors.transparent,
          cursorWidth: 0,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: widget.decoration.contentPadding ?? EdgeInsets.zero,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    left: _cursorX,
                    top: _cursorY,
                    width: 2,
                    height: _cursorH,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One-click copy button below each message bubble.
/// Shows hover highlight and brief "已复制" checkmark feedback on tap.
class _CopyButton extends StatefulWidget {
  final String content;
  const _CopyButton({required this.content});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  bool _hovering = false;

  void _onTap() {
    Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fg = ShadTheme.of(context).mutedForeground;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: _onTap,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _copied
                ? Row(
                    key: const ValueKey('copied'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check, size: 16, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 4),
                      Text('已复制', style: TextStyle(fontSize: 11, color: const Color(0xFF4CAF50))),
                    ],
                  )
                : Row(
                    key: const ValueKey('copy'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 16, color: _hovering ? fg : fg.withAlpha(80)),
                      const SizedBox(width: 4),
                      Text('复制', style: TextStyle(fontSize: 11, color: _hovering ? fg : fg.withAlpha(80))),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Stateful widget for collapsible sections.
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final bool initiallyExpanded;

  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 14, color: widget.color),
                SizedBox(width: 4),
                Text(widget.title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: widget.color)),
                SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14, color: widget.color.withAlpha(150)),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: widget.child,
          ),
      ],
    );
  }
}

class _DummyAgent {
  final String uuid;
  final String name;
  _DummyAgent(this.uuid, this.name);
}
