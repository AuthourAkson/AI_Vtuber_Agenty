import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/multi_agent_provider.dart';
import '../providers/appearance_provider.dart';
import '../services/wenzagent_service.dart';
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
bool _showSettings = false;
String _searchQuery = '';

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
// ── Search (Chat mode only) ──
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
// ── Content (Chat list or Contacts list) ──
Expanded(
child: _contactsMode ? _buildContactsList(mgr) : _buildChatList(mgr),
),
// ── "+ Create Employee" button (Contacts mode only) ──
if (_contactsMode) _buildCreateButton(),
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
_modeButton(Icons.chat_bubble_outline, 'Chat', !_contactsMode, () => setState(() => _contactsMode = false)),
SizedBox(width: 4),
_modeButton(Icons.contacts_outlined, 'Contacts', _contactsMode, () => setState(() => _contactsMode = true)),
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
// ── Agents section ──
Padding(
padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
child: Text('AGENTS (${filtered.length})',
style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
color: ShadTheme.of(context).mutedForeground, letterSpacing: 1.2)),
),
if (filtered.isEmpty)
Padding(
padding: EdgeInsets.all(12),
child: Text('No matching agents',
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
)
else
...filtered.map((a) => _agentTile(a, mgr)),
],
);
}

Widget _deviceTile(DeviceInfo device) {
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
child: Text(device.deviceName, style: TextStyle(fontSize: 13, color: ShadTheme.of(context).foreground)),
),
Container(width: 8, height: 8, decoration: BoxDecoration(
color: Color(0xFF4CAF50), shape: BoxShape.circle)),
],
),
),
);
}

Widget _agentTile(AgentModel agent, AgentManager mgr) {
final isActive = mgr.activeEmployeeId == agent.uuid;

return Padding(
padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
child: GestureDetector(
onTap: () => _selectAgent(agent, mgr),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
decoration: BoxDecoration(
color: isActive ? ShadTheme.of(context).sidebarAccent : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
border: isActive ? Border.all(color: Theme.of(context).colorScheme.primary.withAlpha(80)) : null,
),
child: Row(
children: [
Icon(Icons.smart_toy, size: 20, color: ShadTheme.of(context).foreground),
SizedBox(width: 8),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(agent.name, style: TextStyle(fontSize: 13,
fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
color: ShadTheme.of(context).foreground)),
if (agent.description != null && agent.description!.isNotEmpty)
Text(agent.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground)),
],
),
),
if (agent.status == 'unread')
Container(
padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
decoration: BoxDecoration(color: ShadTheme.of(context).destructive, borderRadius: BorderRadius.circular(8)),
child: Text('NEW', style: TextStyle(fontSize: 9, color: Colors.white)),
),
SizedBox(width: 4),
Icon(Icons.chevron_right, size: 16, color: ShadTheme.of(context).mutedForeground),
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
Text('No employees yet',
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
title: Text('Delete Employee', style: TextStyle(color: ShadTheme.of(context).foreground)),
content: Text(AppLocalizations.of(context).waDeleteConfirm,
style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
actions: [
TextButton(
onPressed: () => Navigator.pop(ctx),
child: Text('Cancel', style: TextStyle(color: ShadTheme.of(context).mutedForeground)),
),
TextButton(
onPressed: () {
mgr.deleteEmployee(emp.uuid);
Navigator.pop(ctx);
},
child: Text('Delete', style: TextStyle(color: ShadTheme.of(context).destructive)),
),
],
),
);
}

Widget _buildCreateButton() {
return Container(
padding: EdgeInsets.all(10),
decoration: BoxDecoration(
border: Border(top: BorderSide(color: ShadTheme.of(context).border)),
),
child: SizedBox(
width: double.infinity,
child: OutlinedButton.icon(
onPressed: () => _showCreateEmployeeDialog(),
icon: Icon(Icons.add, size: 18),
label: Text('Create Employee'),
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
title: Text('Create AI Employee', style: TextStyle(color: ShadTheme.of(context).foreground, fontSize: 16)),
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
    child: Text('Create', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
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

int _lanTab = 0;
final _waHostCtrl = TextEditingController(text: '127.0.0.1');
final _waPortCtrl = TextEditingController(text: '9090');
final _waTopicCtrl = TextEditingController();

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
_settingsGroup('Preferences', [
_settingsItem('Appearance', 'pref_appearance', Icons.palette_outlined),
_settingsItem('General', 'pref_general', Icons.tune),
]),
_settingsGroup('AI', [
_settingsItem('AI Config', 'ai_config', Icons.api),
_settingsItem('MCP Config', 'ai_mcp', Icons.extension),
_settingsItem('Permissions', 'ai_permissions', Icons.security),
]),
_settingsGroup('Data', [
_settingsItem('Sync', 'data_sync', Icons.sync),
_settingsItem('Storage', 'data_storage', Icons.storage),
_settingsItem('Files', 'data_files', Icons.folder),
]),
_settingsGroup('Network', [
_settingsItem('LAN', 'net_lan', Icons.lan),
_settingsItem('Devices', 'net_devices', Icons.devices),
]),
_settingsGroup('System', [
_settingsItem('Privacy', 'sys_privacy', Icons.privacy_tip_outlined),
_settingsItem('Logs', 'sys_logs', Icons.article_outlined),
_settingsItem('About', 'sys_about', Icons.info_outline),
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
case 'net_lan':
return _buildLanSettingsPanel(mgr);
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
Text('AI Provider Profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
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
label: Text('Add Profile'),
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
    child: Text('Save', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
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
return Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.extension, size: 48, color: ShadTheme.of(context).mutedForeground),
SizedBox(height: 16),
Text('MCP Configuration', style: TextStyle(fontSize: 16, color: ShadTheme.of(context).foreground)),
SizedBox(height: 8),
Text('MCP (Model Context Protocol) server management\nwill be available soon.',
textAlign: TextAlign.center,
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
],
),
);
}

// ─── Permissions Panel ───────────────────────────────────

Widget _buildPermissionsPanel(AgentManager mgr) {
return Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.security, size: 48, color: ShadTheme.of(context).mutedForeground),
SizedBox(height: 16),
Text('Global Permissions', style: TextStyle(fontSize: 16, color: ShadTheme.of(context).foreground)),
SizedBox(height: 8),
Text('Configure agent permissions globally.\nFile access, command whitelist, and tool authorization.',
textAlign: TextAlign.center,
style: TextStyle(fontSize: 13, color: ShadTheme.of(context).mutedForeground)),
],
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
Text('LAN Network', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadTheme.of(context).foreground)),
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
label: Text('Join Network'),
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
label: Text('Start & Connect'),
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

// ══════════════════════════════════════════════════════════
// Content Area (Empty State or Chat)
// ══════════════════════════════════════════════════════════

Widget _buildContentArea(AgentManager mgr) {
if (_showSettings) {
return _buildSettingsPage(mgr);
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
Text('Select a conversation to start chatting',
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
onTap: () => mgr.closeAgent(),
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
SizedBox(width: 8),
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
child: ListView.builder(
controller: _scrollCtrl,
padding: EdgeInsets.all(16),
itemCount: mgr.activeMessages.length,
itemBuilder: (_, i) => _msgBubble(mgr.activeMessages[i]),
),
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

return Align(
alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
child: Container(
margin: EdgeInsets.only(bottom: 8),
padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
constraints: BoxConstraints(maxWidth: 520),
decoration: BoxDecoration(
color: isUser ? Theme.of(context).colorScheme.primary.withAlpha(25) : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(12),
),
child: Column(
crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
children: [
if (type == 'functionCall')
_toolLabel('TOOL CALL'),
if (type == 'functionResult')
_toolLabel('TOOL RESULT'),
Text(content, style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground, height: 1.5)),
if (msg['toolResult'] != null && msg['toolResult'].toString().isNotEmpty)
Container(
margin: EdgeInsets.only(top: 6),
padding: EdgeInsets.all(8),
decoration: BoxDecoration(color: Colors.black.withAlpha(50), borderRadius: BorderRadius.circular(6)),
child: Text(msg['toolResult'].toString(), maxLines: 5, overflow: TextOverflow.ellipsis,
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground)),
),
],
),
),
);
}

Widget _toolLabel(String text) {
return Container(
padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
margin: EdgeInsets.only(bottom: 4),
decoration: BoxDecoration(
color: ShadTheme.of(context).mutedForeground.withAlpha(25),
borderRadius: BorderRadius.circular(4),
),
child: Text(text, style: TextStyle(fontSize: 9, color: ShadTheme.of(context).mutedForeground)),
);
}

Widget _buildChatInput(AgentManager mgr) {
return Container(
padding: EdgeInsets.all(12),
color: ShadTheme.of(context).card,
child: Row(
children: [
Expanded(
child: TextField(
controller: _msgCtrl,
decoration: InputDecoration(
hintText: 'Send message to agent...',
filled: true, fillColor: ShadTheme.of(context).secondary,
border: OutlineInputBorder(),
contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
isDense: true,
),
style: TextStyle(fontSize: 14, color: ShadTheme.of(context).foreground),
maxLines: 3, minLines: 1,
onSubmitted: (t) => _send(t, mgr),
),
),
SizedBox(width: 8),
GestureDetector(
onTap: () => _send(_msgCtrl.text, mgr),
child: Container(
width: 40, height: 40,
decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
            child: Icon(Icons.send, size: 18, color: Theme.of(context).colorScheme.onPrimary),
),
),
],
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
}

class _DummyAgent {
final String uuid;
final String name;
_DummyAgent(this.uuid, this.name);
}
