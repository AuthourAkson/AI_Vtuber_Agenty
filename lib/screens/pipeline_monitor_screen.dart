     1|     1|import 'package:flutter/material.dart';
     2|     2|import 'package:provider/provider.dart';
     3|     3|import '../app.dart';
     4|     4|import '../models/task.dart';
     5|     5|import '../providers/chat_provider.dart';
     6|     6|
     7|     7|/// Real-time pipeline task monitor — shows LLM → TTS → Audio pipeline
     8|     8|class PipelineMonitorScreen extends StatefulWidget {
     9|     9|  const PipelineMonitorScreen({super.key});
    10|    10|
    11|    11|  @override
    12|    12|  State<PipelineMonitorScreen> createState() => _PipelineMonitorScreenState();
    13|    13|}
    14|    14|
    15|    15|class _PipelineMonitorScreenState extends State<PipelineMonitorScreen> {
    16|    16|  @override
    17|    17|  Widget build(BuildContext context) {
    18|    18|    return Consumer<ChatProvider>(
    19|    19|      builder: (context, chat, _) {
    20|    20|        final tasks = chat.pipeline.tasks;
    21|    21|
    22|    22|        return Column(
    23|    23|          children: [
    24|    24|            // Header
    25|    25|            Container(
    26|    26|              padding: const EdgeInsets.all(16),
    27|    27|              decoration: const BoxDecoration(
    28|    28|                border: Border(bottom: BorderSide(color: ShadTheme.of(context).border)),
    29|    29|              ),
    30|    30|              child: Row(
    31|    31|                children: [
    32|    32|                  const Icon(Icons.square_foot, color: Color(0xFF4CAF50)),
    33|    33|                  const SizedBox(width: 8),
    34|    34|                  const Text('Pipeline Monitor',
    35|    35|                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
    36|    36|                  const Spacer(),
    37|    37|                  Text('${tasks.length} tasks',
    38|    38|                      style: const TextStyle(color: Color(0xFF888888), fontSize: 13)),
    39|    39|                  const SizedBox(width: 12),
    40|    40|                  IconButton(
    41|    41|                    icon: const Icon(Icons.delete_outline, size: 18),
    42|    42|                    tooltip: 'Clear finished',
    43|    43|                    onPressed: () => chat.pipeline.removeFinishedTasks(maxCount: 5),
    44|    44|                  ),
    45|    45|                ],
    46|    46|              ),
    47|    47|            ),
    48|    48|            // Task list
    49|    49|            Expanded(
    50|    50|              child: tasks.isEmpty
    51|    51|                  ? const Center(
    52|    52|                      child: Text('No pipeline tasks',
    53|    53|                          style: TextStyle(color: Color(0xFF888888))))
    54|    54|                  : ListView.builder(
    55|    55|                      padding: const EdgeInsets.all(16),
    56|    56|                      itemCount: tasks.length,
    57|    57|                      itemBuilder: (_, index) {
    58|    58|                        final task = tasks[index];
    59|    59|                        return _TaskCard(task: task);
    60|    60|                      },
    61|    61|                    ),
    62|    62|            ),
    63|    63|          ],
    64|    64|        );
    65|    65|      },
    66|    66|    );
    67|    67|  }
    68|    68|}
    69|    69|
    70|    70|class _TaskCard extends StatelessWidget {
    71|    71|  final Task task;
    72|    72|
    73|    73|  const _TaskCard({required this.task});
    74|    74|
    75|    75|  @override
    76|    76|  Widget build(BuildContext context) {
    77|    77|    return Card(
    78|    78|      color: ShadTheme.of(context).card,
    79|    79|      margin: const EdgeInsets.only(bottom: 8),
    80|    80|      child: Padding(
    81|    81|        padding: const EdgeInsets.all(12),
    82|    82|        child: Column(
    83|    83|          crossAxisAlignment: CrossAxisAlignment.start,
    84|    84|          children: [
    85|    85|            // Header: status + task ID
    86|    86|            Row(
    87|    87|              children: [
    88|    88|                _statusChip(task.status),
    89|    89|                const SizedBox(width: 8),
    90|    90|                Expanded(
    91|    91|                  child: Text(
    92|    92|                    task.id.length > 12 ? '${task.id.substring(0, 12)}...' : task.id,
    93|    93|                    style: TextStyle(fontSize: 11, color: ShadTheme.of(context).mutedForeground, fontFamily: 'monospace'),
    94|    94|                  ),
    95|    95|                ),
    96|    96|                if (task.status == TaskStatus.pendingInterruption)
    97|    97|                  const Icon(Icons.warning_amber, color: Color(0xFFFFA726), size: 16),
    98|    98|              ],
    99|    99|            ),
   100|   100|            const SizedBox(height: 8),
   101|   101|            // Input preview
   102|   102|            if (task.input != null)
   103|   103|              Container(
   104|   104|                padding: const EdgeInsets.all(8),
   105|   105|                decoration: BoxDecoration(
   106|   106|                  color: const Color(0xFF252525),
   107|   107|                  borderRadius: BorderRadius.circular(6),
   108|   108|                ),
   109|   109|                child: Text(
   110|   110|                  'Input: ${task.input!.length > 80 ? '${task.input!.substring(0, 80)}...' : task.input}',
   111|   111|                  style: const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
   112|   112|                ),
   113|   113|              ),
   114|   114|            // Response segments
   115|   115|            if (task.response.isNotEmpty) ...[
   116|   116|              const SizedBox(height: 8),
   117|   117|              ...task.response.asMap().entries.map((entry) {
   118|   118|                final idx = entry.key;
   119|   119|                final resp = entry.value;
   120|   120|                return _ResponseSegment(index: idx, response: resp);
   121|   121|              }),
   122|   122|            ],
   123|   123|            // Interruption state
   124|   124|            if (task.status == TaskStatus.pendingInterruption && task.interruptionState != null)
   125|   125|              Padding(
   126|   126|                padding: const EdgeInsets.only(top: 8),
   127|   127|                child: Row(
   128|   128|                  children: [
   129|   129|                    _interruptDot('LLM', task.interruptionState!.llm),
   130|   130|                    const SizedBox(width: 8),
   131|   131|                    _interruptDot('TTS', task.interruptionState!.tts),
   132|   132|                    const SizedBox(width: 8),
   133|   133|                    _interruptDot('Audio', task.interruptionState!.audio),
   134|   134|                  ],
   135|   135|                ),
   136|   136|              ),
   137|   137|          ],
   138|   138|        ),
   139|   139|      ),
   140|   140|    );
   141|   141|  }
   142|   142|
   143|   143|  Widget _statusChip(TaskStatus status) {
   144|   144|    final (color, label) = switch (status) {
   145|   145|      TaskStatus.created => (const Color(0xFF888888), 'Created'),
   146|   146|      TaskStatus.llmStarted => (const Color(0xFF2196F3), 'LLM...'),
   147|   147|      TaskStatus.llmFinished => (const Color(0xFF4CAF50), 'LLM Done'),
   148|   148|      TaskStatus.ttsFinished => (const Color(0xFF9C27B0), 'TTS Done'),
   149|   149|      TaskStatus.taskFinished => (const Color(0xFF4CAF50), 'Finished'),
   150|   150|      TaskStatus.pendingInterruption => (const Color(0xFFFFA726), 'Interrupting'),
   151|   151|      TaskStatus.cancelled => (const Color(0xFFCF6679), 'Cancelled'),
   152|   152|    };
   153|   153|    return Container(
   154|   154|      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
   155|   155|      decoration: BoxDecoration(
   156|   156|        color: color.withOpacity(0.15),
   157|   157|        borderRadius: BorderRadius.circular(4),
   158|   158|        border: Border.all(color: color.withOpacity(0.4)),
   159|   159|      ),
   160|   160|      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
   161|   161|    );
   162|   162|  }
   163|   163|
   164|   164|  Widget _interruptDot(String label, bool done) {
   165|   165|    return Row(
   166|   166|      mainAxisSize: MainAxisSize.min,
   167|   167|      children: [
   168|   168|        Icon(
   169|   169|          done ? Icons.check_circle : Icons.radio_button_unchecked,
   170|   170|          size: 12,
   171|   171|          color: done ? const Color(0xFF4CAF50) : const Color(0xFF888888),
   172|   172|        ),
   173|   173|        const SizedBox(width: 4),
   174|   174|        Text(label, style: TextStyle(fontSize: 10, color: done ? const Color(0xFF4CAF50) : const Color(0xFF888888))),
   175|   175|      ],
   176|   176|    );
   177|   177|  }
   178|   178|}
   179|   179|
   180|   180|class _ResponseSegment extends StatelessWidget {
   181|   181|  final int index;
   182|   182|  final TaskResponse response;
   183|   183|
   184|   184|  const _ResponseSegment({required this.index, required this.response});
   185|   185|
   186|   186|  @override
   187|   187|  Widget build(BuildContext context) {
   188|   188|    return Padding(
   189|   189|      padding: const EdgeInsets.only(bottom: 4),
   190|   190|      child: Row(
   191|   191|        crossAxisAlignment: CrossAxisAlignment.start,
   192|   192|        children: [
   193|   193|          Container(
   194|   194|            width: 24,
   195|   195|            height: 24,
   196|   196|            alignment: Alignment.center,
   197|   197|            decoration: BoxDecoration(
   198|   198|              color: const Color(0xFF333333),
   199|   199|              borderRadius: BorderRadius.circular(4),
   200|   200|            ),
   201|   201|            child: Text('$index', style: const TextStyle(fontSize: 10, color: Color(0xFF888888))),
   202|   202|          ),
   203|   203|          const SizedBox(width: 8),
   204|   204|          Expanded(
   205|   205|            child: Text(
   206|   206|              response.text.length > 60 ? '${response.text.substring(0, 60)}...' : response.text,
   207|   207|              style: const TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
   208|   208|            ),
   209|   209|          ),
   210|   210|          if (response.audioUrl != null)
   211|   211|            const Icon(Icons.volume_up, size: 14, color: Color(0xFF4CAF50)),
   212|   212|          if (response.playbackFinished)
   213|   213|            const Padding(
   214|   214|              padding: EdgeInsets.only(left: 4),
   215|   215|              child: Icon(Icons.check, size: 14, color: Color(0xFF4CAF50)),
   216|   216|            ),
   217|   217|        ],
   218|   218|      ),
   219|   219|    );
   220|   220|  }
   221|   221|}
   222|   222|