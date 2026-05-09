import 'package:uuid/uuid.dart';
import '../models/task.dart';

typedef PipelineListener = void Function(List<Task> tasks);

/// Mirrors the LAV2 PipelineManager: orchestrates LLM -> TTS -> Audio flow.
/// Subscribes to pipeline events and dispatches to listeners.
class PipelineManager {
  final _tasks = <Task>[];
  final _listeners = <PipelineListener>{};
  final _uuid = const Uuid();

  void subscribe(PipelineListener listener) {
    _listeners.add(listener);
    listener(List.unmodifiable(_tasks));
  }

  void unsubscribe(PipelineListener listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    for (final listener in _listeners.toList()) {
      listener(List.unmodifiable(_tasks));
    }
  }

  List<Task> get tasks => List.unmodifiable(_tasks);
  Task? getTaskById(String id) => _tasks.cast<Task?>().firstWhere(
    (t) => t?.id == id,
    orElse: () => null,
  );

  String addInputTask(String input) {
    final id = _uuid.v4();
    _tasks.add(Task(id: id, input: input, status: TaskStatus.created));
    _notify();
    return id;
  }

  String createTaskFromLLM(String input, String initialResponse) {
    final id = _uuid.v4();
    _tasks.add(Task(
      id: id,
      input: input,
      response: [TaskResponse(text: initialResponse)],
      status: TaskStatus.llmStarted,
    ));
    _notify();
    return id;
  }

  void addLLMResponse(String taskId, String text) {
    final task = getTaskById(taskId);
    if (task == null || task.status == TaskStatus.cancelled) return;
    task.response.add(TaskResponse(text: text));
    _notify();
  }

  void markLLMStarted(String taskId) {
    final task = getTaskById(taskId);
    if (task != null) {
      task.status = TaskStatus.llmStarted;
      _updateTaskStatus(task);
      _notify();
    }
  }

  void markLLMFinished(String taskId) {
    final task = getTaskById(taskId);
    if (task != null) {
      task.status = TaskStatus.llmFinished;
      _updateTaskStatus(task);
      _notify();
    }
  }

  void addTTSAudio(String taskId, int responseIndex, String audioUrl) {
    final task = getTaskById(taskId);
    if (task == null || task.status == TaskStatus.cancelled) return;
    if (responseIndex < task.response.length) {
      task.response[responseIndex].audioUrl = audioUrl;
      _updateTaskStatus(task);
      _notify();
    }
  }

  void markPlaybackFinished(String taskId, int responseIndex) {
    final task = getTaskById(taskId);
    if (task == null) return;
    if (responseIndex < task.response.length) {
      task.response[responseIndex].playbackFinished = true;
      _updateTaskStatus(task);
      _notify();
    }
  }

  Task? getNextTaskForLLM() {
    final task = getCurrentTask();
    if (task != null &&
        task.status != TaskStatus.pendingInterruption &&
        task.input != null &&
        task.status == TaskStatus.created) {
      return task;
    }
    return null;
  }

  Task? getCurrentTask() {
    return _tasks.cast<Task?>().firstWhere(
      (t) => t?.status != TaskStatus.taskFinished && t?.status != TaskStatus.cancelled,
      orElse: () => null,
    );
  }

  void interruptCurrentTask() {
    final task = getCurrentTask();
    if (task != null) {
      task.status = TaskStatus.pendingInterruption;
      task.interruptionState = InterruptionState();
      _notify();
    }
  }

  void _updateTaskStatus(Task task) {
    if (task.status == TaskStatus.cancelled) return;
    if (task.status == TaskStatus.pendingInterruption) {
      final state = task.interruptionState;
      if (state != null && state.tts && state.llm && state.audio) {
        task.status = TaskStatus.cancelled;
      }
      return;
    }
    final llmFinish = task.status == TaskStatus.llmFinished;
    final allAudio = task.response.every((r) => r.audioUrl != null);
    final allPlayback = task.response.every((r) => r.playbackFinished);

    if (llmFinish && allAudio) task.status = TaskStatus.ttsFinished;
    if (task.status == TaskStatus.ttsFinished && allPlayback) {
      task.status = TaskStatus.taskFinished;
    }
  }

  void removeFinishedTasks({int maxCount = 20}) {
    final active = _tasks.where((t) => t.status != TaskStatus.taskFinished).toList();
    final recentFinished = _tasks
        .where((t) => t.status == TaskStatus.taskFinished)
        .toList()
        .reversed
        .take(maxCount)
        .toList();
    _tasks
      ..clear()
      ..addAll(recentFinished.reversed)
      ..addAll(active);
    _notify();
  }

  void reset() {
    _tasks.clear();
    _notify();
  }
}
