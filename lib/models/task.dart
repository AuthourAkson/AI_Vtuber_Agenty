/// Response segment within a pipeline task
class TaskResponse {
  final String text;
  String? audioUrl;
  bool playbackFinished;

  TaskResponse({
    required this.text,
    this.audioUrl,
    this.playbackFinished = false,
  });
}

/// Pipeline task status (mirrors backend TaskStatus)
enum TaskStatus {
  created,
  llmStarted,
  llmFinished,
  ttsFinished,
  taskFinished,
  pendingInterruption,
  cancelled,
}

/// Interruption state tracking per pipeline stage
class InterruptionState {
  bool tts = false;
  bool llm = false;
  bool audio = false;
}

/// A pipeline task: input -> LLM -> TTS -> Audio
class Task {
  final String id;
  final String? input;
  final List<TaskResponse> response;
  TaskStatus status;
  InterruptionState? interruptionState;

  Task({
    required this.id,
    this.input,
    List<TaskResponse>? response,
    this.status = TaskStatus.created,
    this.interruptionState,
  }) : response = response ?? [];
}
