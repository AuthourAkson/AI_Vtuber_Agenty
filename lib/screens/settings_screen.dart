import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/settings_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/multi_agent_provider.dart';

class SettingsScreen extends StatefulWidget {
SettingsScreen({super.key});

@override
State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
late TextEditingController _serverCtrl;
late TextEditingController _waHostCtrl;
late TextEditingController _waDeviceNameCtrl;
late TextEditingController _waTopicCtrl;
bool _waEnabled = false;
int _waPort = 9090;
int _lanTab = 0; // 0=Join, 1=Create

@override
void initState() {
super.initState();
_serverCtrl = TextEditingController();
_waHostCtrl = TextEditingController(text: '127.0.0.1');
_waDeviceNameCtrl = TextEditingController(text: 'AI VTuber');
_waTopicCtrl = TextEditingController();
}

@override
void dispose() {
_serverCtrl.dispose();
_waHostCtrl.dispose();
_waDeviceNameCtrl.dispose();
_waTopicCtrl.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return Consumer3<SettingsProvider, ChatProvider, AgentManager>(
builder: (context, sp, chat, wa, _) {
// Sync text controllers with settings on first load
if (_serverCtrl.text.isEmpty) {
_serverCtrl.text = sp.settings.backendUrl;
}

return SingleChildScrollView(
padding: EdgeInsets.all(24),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text('Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
SizedBox(height: 24),

// ─── WenzAgent Multi-Agent LAN ──────────────────
_sectionHeader('WenzAgent Multi-Agent Network'),
SizedBox(height: 8),
_buildLanConfig(sp, wa),

SizedBox(height: 24),

// ─── Server Connection ────────────────────────
_sectionHeader('Server Connection'),
SizedBox(height: 8),
TextField(
controller: _serverCtrl,
decoration: InputDecoration(
labelText: 'Backend URL',
hintText: 'D:\\AiVtuber_Agent_profile',
border: OutlineInputBorder(),
filled: true,
fillColor: ShadTheme.of(context).secondary,
),
style: TextStyle(fontSize: 13),
onChanged: (v) => sp.updateBackendUrl(v),
),
SizedBox(height: 12),
Row(
children: [
Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
SizedBox(width: 6),
Text('Self-contained — no external backend needed',
style: TextStyle(color: Color(0xFF4CAF50), fontSize: 13)),
],
),
SizedBox(height: 24),

// ─── About ────────────────────────────────────
_sectionHeader('About'),
SizedBox(height: 8),
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
Text('AI VTuber Agent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
SizedBox(height: 4),
Text('v1.0.0 — Flutter Desktop App',
style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
SizedBox(height: 12),
Text('Features:',
style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 14)),
SizedBox(height: 4),
Text('• Streaming LLM chat with character system prompt'),
Text('• TTS voice synthesis via edge-tts'),
Text('• Live2D / VRM character display (WIP)'),
Text('• Screenshot vision + OCR'),
Text('• Local keyword-based memory'),
Text('• Session history management'),
Text('• WenzAgent multi-agent LAN networking'),
SizedBox(height: 12),
Text('Backend: Self-contained Dart services',
style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
Text('UI Framework: Flutter 3.x + Provider',
style: TextStyle(color: Color(0xFF666666), fontSize: 12)),
],
),
),

SizedBox(height: 24),
_sectionHeader('Data & Storage'),
SizedBox(height: 8),
OutlinedButton.icon(
onPressed: () {},
icon: Icon(Icons.delete_outline, size: 18, color: Color(0xFFCF6679)),
label: Text('Clear Local Cache', style: TextStyle(color: Color(0xFFCF6679))),
),
],
),
);
},
);
}

Widget _sectionHeader(String title) {
return Text(title, style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.w600,
color: Color(0xFF4CAF50),
));
}

Widget _miniButton(String label, VoidCallback onTap) {
return GestureDetector(
onTap: onTap,
child: Container(
padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
decoration: BoxDecoration(
color: ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(4),
border: Border.all(color: ShadTheme.of(context).border),
),
child: Text(label, style: TextStyle(fontSize: 12, color: ShadTheme.of(context).foreground)),
),
);
}

// ─── LAN Config Card ──────────────────────────────────────

Widget _buildLanConfig(SettingsProvider sp, AgentManager wa) {
return Container(
padding: EdgeInsets.all(16),
decoration: BoxDecoration(
color: ShadTheme.of(context).card,
borderRadius: BorderRadius.circular(10),
border: Border.all(color: ShadTheme.of(context).border),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Enable toggle
SwitchListTile(
contentPadding: EdgeInsets.zero,
title: Text('Enable multi-agent LAN', style: TextStyle(fontSize: 14)),
subtitle: Text(
'Connect to a WenzAgent LAN server for multi-device AI collaboration',
style: TextStyle(fontSize: 12, color: ShadTheme.of(context).mutedForeground),
),
value: sp.settings.wenzagentEnabled,
onChanged: (v) {
sp.settings.wenzagentEnabled = v;
sp.saveSettings(sp.settings);
setState(() {});
},
),
if (sp.settings.wenzagentEnabled) ...[
SizedBox(height: 12),
// Join / Create tabs
Row(
children: [
_lanTabButton('Join LAN', 0),
SizedBox(width: 8),
_lanTabButton('Create LAN', 1),
],
),
SizedBox(height: 12),
// Host IP
TextField(
controller: _waHostCtrl,
decoration: InputDecoration(
labelText: _lanTab == 0 ? 'Server IP Address' : 'Bind Address',
hintText: _lanTab == 0 ? '192.168.1.100' : '0.0.0.0',
border: OutlineInputBorder(),
filled: true,
fillColor: ShadTheme.of(context).secondary,
),
style: TextStyle(fontSize: 13),
onChanged: (v) {
sp.settings.wenzagentHost = v;
sp.saveSettings(sp.settings);
},
),
SizedBox(height: 8),
// Port
TextField(
controller: TextEditingController(text: '${sp.settings.wenzagentPort}'),
decoration: InputDecoration(
labelText: 'Port',
hintText: '9090',
border: OutlineInputBorder(),
filled: true,
fillColor: ShadTheme.of(context).secondary,
contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
),
keyboardType: TextInputType.number,
style: TextStyle(fontSize: 13),
onChanged: (v) {
sp.settings.wenzagentPort = int.tryParse(v) ?? 9090;
sp.saveSettings(sp.settings);
},
),
SizedBox(height: 8),
// Device Name
TextField(
controller: _waDeviceNameCtrl,
decoration: InputDecoration(
labelText: 'Device Name',
hintText: 'AI VTuber',
border: OutlineInputBorder(),
filled: true,
fillColor: ShadTheme.of(context).secondary,
),
style: TextStyle(fontSize: 13),
onChanged: (v) {
sp.settings.wenzagentDeviceName = v;
sp.saveSettings(sp.settings);
},
),
SizedBox(height: 8),
// Topic
TextField(
controller: _waTopicCtrl,
decoration: InputDecoration(
labelText: 'Topic (optional)',
hintText: 'Group identifier',
border: OutlineInputBorder(),
filled: true,
fillColor: ShadTheme.of(context).secondary,
),
style: TextStyle(fontSize: 13),
onChanged: (v) {
sp.settings.wenzagentTopic = v;
sp.saveSettings(sp.settings);
},
),
SizedBox(height: 14),
// Connection status + button
Row(
children: [
Icon(
wa.connected ? Icons.check_circle : Icons.cancel,
size: 16,
color: wa.connected ? Color(0xFF4CAF50) : Color(0xFFCF6679),
),
SizedBox(width: 6),
Expanded(
child: Text(
wa.connected ? 'Connected to LAN' : wa.statusMessage,
style: TextStyle(
color: wa.connected ? Color(0xFF4CAF50) : ShadTheme.of(context).mutedForeground,
fontSize: 13,
),
),
),
if (wa.connected)
_miniButton('Disconnect', () => wa.disconnect())
else
_miniButton(_lanTab == 0 ? 'Join' : 'Start', () {
if (_lanTab == 0) {
wa.joinLAN(host: sp.settings.wenzagentHost, port: sp.settings.wenzagentPort);
} else {
wa.createLAN(host: sp.settings.wenzagentHost, port: sp.settings.wenzagentPort);
}
}),
],
),
],
],
),
);
}

Widget _lanTabButton(String label, int index) {
final active = _lanTab == index;
return GestureDetector(
onTap: () => setState(() => _lanTab = index),
child: Container(
padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
decoration: BoxDecoration(
color: active ? ShadTheme.of(context).sidebarPrimary : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
),
child: Text(
label,
style: TextStyle(
fontSize: 12,
fontWeight: FontWeight.w500,
color: active ? Colors.white : ShadTheme.of(context).mutedForeground,
),
),
),
);
}
}
