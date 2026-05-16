import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../models/task.dart';
import '../providers/chat_provider.dart';

/// Real-time pipeline task monitor — shows LLM → TTS → Audio pipeline
class PipelineMonitorScreen extends StatefulWidget {
const PipelineMonitorScreen({super.key});

@override
State<PipelineMonitorScreen> createState() => _PipelineMonitorScreenState();
}

class _PipelineMonitorScreenState extends State<PipelineMonitorScreen> {
@override
Widget build(BuildContext context) {
return Consumer<ChatProvider>(
builder: (context, chat, _) {
final tasks = chat.pipeline.tasks;

return Column(
children: [
// Header
Container(
padding: const EdgeInsets.all(16),
decoration: const BoxDecoration(
border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
),
child: Row(
children: [
const Icon(Icons.square_foot, color: Color(0xFF4CAF50)),
const SizedBox(width: 8),
const Text('Pipeline Monitor',
style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
const Spacer(),
Text('${tasks.length} tasks',
style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
const SizedBox(width: 12),
IconButton(
icon: const Icon(Icons.delete_outline, size: 18),
tooltip: 'Clear finished',
onPressed: () => chat.pipeline.removeFinishedTasks(maxCount: 5),
),
],
),
),
// Task list
Expanded(
child: tasks.isEmpty
? const Center(
child: Text('No pipeline tasks',
style: TextStyle(color: Color(0xFF888888))))
: ListView.builder(
padding: const EdgeInsets.all(16),
itemCount: tasks.length,
itemBuilder: (_, index) {
final task = tasks[index];
return _TaskCard(task: task);
},
),
),
],
);
},
);
}
}

class _TaskCard extends StatelessWidget {
final Task task;

const _TaskCard({required this.task});

@override
Widget build(BuildContext context) {
return Card(
color: ShadTheme.of(context).card,
margin: const EdgeInsets.only(bottom: 8),
child: Padding(
padding: const EdgeInsets.all(12),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// Header: status + task ID
Row(
children: [
_statusChip(task.status),
const SizedBox(width: 8),
Expanded(
child: Text(
task.id.length > 12 ? '${task.id.substring(0, 12)}...' : task.id,
style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground, fontFamily: 'monospace'),
),
),
if (task.status == TaskStatus.pendingInterruption)
const Icon(Icons.warning_amber, color: Color(0xFFFFA726), size: 16),
],
),
const SizedBox(height: 8),
// Input preview
if (task.input != null)
Container(
padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
color: const Color(0xFF252525),
borderRadius: BorderRadius.circular(6),
),
child: Text(
'Input: ${task.input!.length > 80 ? '${task.input!.substring(0, 80)}...' : task.input}',
style: const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
),
),
// Response segments
if (task.response.isNotEmpty) ...[
const SizedBox(height: 8),
...task.response.asMap().entries.map((entry) {
final idx = entry.key;
final resp = entry.value;
return _ResponseSegment(index: idx, response: resp);
}),
],
// Interruption state
if (task.status == TaskStatus.pendingInterruption && task.interruptionState != null)
Padding(
padding: const EdgeInsets.only(top: 8),
child: Row(
children: [
_interruptDot('LLM', task.interruptionState!.llm),
const SizedBox(width: 8),
_interruptDot('TTS', task.interruptionState!.tts),
const SizedBox(width: 8),
_interruptDot('Audio', task.interruptionState!.audio),
],
),
),
],
),
),
);
}

Widget _statusChip(TaskStatus status) {
final (color, label) = switch (status) {
TaskStatus.created => (const Color(0xFF888888), 'Created'),
TaskStatus.llmStarted => (const Color(0xFF2196F3), 'LLM...'),
TaskStatus.llmFinished => (const Color(0xFF4CAF50), 'LLM Done'),
TaskStatus.ttsFinished => (const Color(0xFF9C27B0), 'TTS Done'),
TaskStatus.taskFinished => (const Color(0xFF4CAF50), 'Finished'),
TaskStatus.pendingInterruption => (const Color(0xFFFFA726), 'Interrupting'),
TaskStatus.cancelled => (const Color(0xFFCF6679), 'Cancelled'),
};
return Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
decoration: BoxDecoration(
color: color.withOpacity(0.15),
borderRadius: BorderRadius.circular(4),
border: Border.all(color: color.withOpacity(0.4)),
),
child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
);
}

Widget _interruptDot(String label, bool done) {
return Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(
done ? Icons.check_circle : Icons.radio_button_unchecked,
size: 12,
color: done ? const Color(0xFF4CAF50) : const Color(0xFF888888),
),
const SizedBox(width: 4),
Text(label, style: TextStyle(fontSize: 10, color: done ? const Color(0xFF4CAF50) : const Color(0xFF888888))),
],
);
}
}

class _ResponseSegment extends StatelessWidget {
final int index;
final TaskResponse response;

const _ResponseSegment({required this.index, required this.response});

@override
Widget build(BuildContext context) {
return Padding(
padding: const EdgeInsets.only(bottom: 4),
child: Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Container(
width: 24,
height: 24,
alignment: Alignment.center,
decoration: BoxDecoration(
color: const Color(0xFF333333),
borderRadius: BorderRadius.circular(4),
),
child: Text('$index', style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
),
const SizedBox(width: 8),
Expanded(
child: Text(
response.text.length > 60 ? '${response.text.substring(0, 60)}...' : response.text,
style: const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
),
),
if (response.audioUrl != null)
const Icon(Icons.volume_up, size: 14, color: Color(0xFF4CAF50)),
if (response.playbackFinished)
const Padding(
padding: EdgeInsets.only(left: 4),
child: Icon(Icons.check, size: 14, color: Color(0xFF4CAF50)),
),
],
),
);
}
}
