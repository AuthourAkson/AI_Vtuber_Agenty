import '../models/message.dart';
import '../models/settings.dart';
import 'storage_service.dart';
import 'llm_service.dart';
import 'tts_service.dart';
import 'memory_service.dart';
import 'vision_service.dart';
import 'live2d_model_service.dart';

/// Central backend service — replaces ApiClient with local Dart implementation.
/// All data stored at D:\AiVtuber_Agent_profile\ (like Steam game saves).
class BackendService {
  final StorageService storage = StorageService();
  late final LLMService llm = LLMService();
  late final TTSService tts = TTSService(storage);
  late final MemoryService memory = MemoryService(storage);
  late final VisionService vision = VisionService(storage);
  late final Live2DModelService live2dModels = Live2DModelService();

  /// Whether the backend is "connected" (always true — local).
  bool get connected => true;

  // ─── Settings ───

  Future<AppSettings> getSettings() async {
    final raw = storage.loadSettings();
    // Merge with defaults
    final settings = AppSettings.fromJson(raw);
    llm.updateFromSettings(settings);
    return settings;
  }

  Future<void> updateSettings(AppSettings settings) async {
    storage.saveSettings(settings.toJson());
    llm.updateFromSettings(settings);
  }

  // ─── Chat Completion (streaming) ───

  Stream<String> completionStream({
    required String text,
    required List<HistoryItem> history,
    required String systemPrompt,
  }) {
    return llm.completionStream(
      text: text,
      history: history,
      systemPrompt: systemPrompt,
    );
  }

  // ─── Chat Sessions ───

  Future<String> createSession() async {
    return storage.createSession('Chat Session');
  }

  Future<void> updateSession(String id, List<HistoryItem> history) async {
    final existing = storage.getSession(id);
    if (existing != null) {
      existing['history'] = history.map((h) => h.toJson()).toList();
      existing['updated_at'] = DateTime.now().toIso8601String();
      storage.updateSession(id, existing);
    }
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    return storage.listSessions();
  }

  Future<Map<String, dynamic>?> getSession(String id) async {
    return storage.getSessionFull(id);
  }

  Future<void> deleteSession(String id) async {
    storage.deleteSession(id);
  }

  // ─── TTS ───

  Future<List<int>> ttsSynthesize(String text) => tts.synthesize(text);

  Future<List<Map<String, dynamic>>> listTTSVoices() => tts.listVoices();

  // ─── LLM Models ───

  Future<List<Map<String, dynamic>>> listLLMModels() => llm.listModels();

  // ─── Character Models ───

  Future<List<Map<String, String>>> listLive2DModels() async {
    return live2dModels.listModels();
  }

  Future<String?> importLive2DModel(String sourceDir) async {
    return live2dModels.importModel(sourceDir);
  }

  Future<bool> deleteLive2DModel(String modelName) async {
    return live2dModels.deleteModel(modelName);
  }

  // ─── Memory ───

  Future<List<String>> queryMemory(String text, {int limit = 3}) {
    return memory.query(text, limit: limit);
  }

  // ─── Vision ───

  Future<Map<String, dynamic>> captureScreenshot() {
    return vision.captureScreenshot();
  }

  Future<List<Map<String, dynamic>>> getMonitors() {
    return vision.getMonitors();
  }
}
