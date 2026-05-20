import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../providers/settings_provider.dart';

/// TTS Settings page — matches LocalAIVtuber2's TTSPage style.
class TTSScreen extends StatefulWidget {
TTSScreen({super.key});

@override
State<TTSScreen> createState() => _TTSScreenState();
}

class _TTSScreenState extends State<TTSScreen> {
void _update(SettingsProvider sp, AppSettings s, {
String? ttsProvider,
bool? useRvc,
int? rvcF0UpKey,
}) {
sp.saveSettings(s.copyWith(
ttsProvider: ttsProvider,
useRvc: useRvc,
rvcF0UpKey: rvcF0UpKey,
));
}

@override
Widget build(BuildContext context) {
return Consumer<SettingsProvider>(
builder: (context, sp, _) {
final s = sp.settings;

return SingleChildScrollView(
padding: EdgeInsets.only(top: 40, left: 48, right: 48, bottom: 40),
child: ConstrainedBox(
constraints: BoxConstraints(maxWidth: 640),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'TTS Settings',
style: TextStyle(
fontSize: 28,
fontWeight: FontWeight.bold,
color: ShadTheme.of(context).foreground,
),
),
SizedBox(height: 6),
Text(
AppLocalizations.of(context).ttsSubtitle,
style: TextStyle(
fontSize: 14,
color: ShadTheme.of(context).mutedForeground,
),
),
SizedBox(height: 28),

// Provider selection card
_shadCard(
title: 'TTS Provider Selection',
icon: Icons.settings,
child: Column(
children: [
Row(
children: [
_providerChip(
'GPT-SoVITS',
s.ttsProvider == 'gpt-sovits',
() => _update(sp, s, ttsProvider: 'gpt-sovits'),
),
SizedBox(width: 8),
_providerChip(
'RVC',
s.ttsProvider == 'rvc',
() => _update(sp, s, ttsProvider: 'rvc'),
),
],
),
],
),
),
SizedBox(height: 16),

// Voice selection card
_shadCard(
title: 'Active Voice',
icon: Icons.record_voice_over,
child: Container(
width: double.infinity,
padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
decoration: BoxDecoration(
color: ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(6),
border: Border.all(color: ShadTheme.of(context).input),
),
child: Text(
s.ttsVoice.isEmpty ? 'No voice selected' : s.ttsVoice,
style: TextStyle(
fontSize: 14,
color: ShadTheme.of(context).foreground,
),
),
),
),
SizedBox(height: 16),

// RVC settings
if (s.ttsProvider == 'rvc') ...[
_shadCard(
title: 'RVC Settings',
icon: Icons.tune,
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Enable RVC switch
Row(
children: [
SizedBox(
height: 24,
child: Switch(
value: s.useRvc,
onChanged: (v) => _update(sp, s, useRvc: v),
activeColor: ShadTheme.of(context).primary,
),
),
SizedBox(width: 10),
Text(
'Enable RVC',
style: TextStyle(
fontSize: 14,
color: ShadTheme.of(context).foreground,
),
),
],
),
SizedBox(height: 16),

// Pitch shift slider
Row(
children: [
Text(
'Pitch Shift (semitones): ',
style: TextStyle(
fontSize: 13,
color: ShadTheme.of(context).mutedForeground,
),
),
Text(
'${s.rvcF0UpKey}',
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.w600,
color: ShadTheme.of(context).foreground,
),
),
],
),
Slider(
value: s.rvcF0UpKey.toDouble(),
min: -12,
max: 12,
divisions: 24,
activeColor: ShadTheme.of(context).primary,
inactiveColor: ShadTheme.of(context).secondary,
onChanged: (v) =>
_update(sp, s, rvcF0UpKey: v.round()),
),
],
),
),
],

// Upload voice
SizedBox(height: 12),
SizedBox(
width: double.infinity,
child: OutlinedButton.icon(
onPressed: () {},
icon: Icon(Icons.upload_file, size: 16),
label: Text('Upload Voice Model'),
),
),
],
),
),
);
},
);
}

Widget _providerChip(String name, bool selected, VoidCallback onTap) {
return Expanded(
child: GestureDetector(
onTap: onTap,
child: Container(
padding: EdgeInsets.symmetric(vertical: 14),
decoration: BoxDecoration(
color: selected ? ShadTheme.of(context).primary.withAlpha(25) : ShadTheme.of(context).secondary,
borderRadius: BorderRadius.circular(8),
border: Border.all(
color: selected ? ShadTheme.of(context).primary : ShadTheme.of(context).input,
width: selected ? 1.5 : 1,
),
),
child: Center(
child: Text(
name,
style: TextStyle(
fontSize: 14,
color: selected ? ShadTheme.of(context).foreground : ShadTheme.of(context).mutedForeground,
fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
),
),
),
),
),
);
}

Widget _shadCard({
required String title,
required IconData icon,
required Widget child,
}) {
return Container(
width: double.infinity,
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
Row(
children: [
Icon(icon, size: 16, color: ShadTheme.of(context).foreground),
SizedBox(width: 8),
Text(
title,
style: TextStyle(
fontSize: 15,
fontWeight: FontWeight.w600,
color: ShadTheme.of(context).foreground,
),
),
],
),
SizedBox(height: 14),
child,
],
),
);
}
}
