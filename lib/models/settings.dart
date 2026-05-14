/// Application settings (backed by SharedPreferences + backend settings.json)
class AppSettings {
  // LLM
  String llmModelFilename;
  bool keepModelLoaded;
  bool enableMemoryRetrieval;
  String systemPrompt;
  bool showMonitor;

  // TTS
  String ttsProvider;
  String ttsVoice;

  // RVC
  bool useRvc;
  int rvcF0UpKey;

  // Character
  String? selectedLive2DModel;
  String? selectedVRMModel;
  bool renderModel;
  double live2DXPosition;
  double live2DYPosition;
  double live2DScale;
  bool use3D; // true = VRM 3D, false = Live2D 2D

  // API Relay
  String apiRelayBaseUrl;
  String apiRelayApiKey;
  String apiRelayModel;
  bool apiRelayEnabled;

  // Server
  String backendUrl;

  AppSettings({
    this.llmModelFilename = '',
    this.keepModelLoaded = true,
    this.enableMemoryRetrieval = true,
    this.systemPrompt = '',
    this.showMonitor = false,
    this.ttsProvider = 'gpt-sovits',
    this.ttsVoice = '',
    this.useRvc = false,
    this.rvcF0UpKey = 0,
    this.selectedLive2DModel,
    this.selectedVRMModel,
    this.renderModel = true,
    this.live2DXPosition = 46,
    this.live2DYPosition = 51,
    this.live2DScale = 0.16,
    this.use3D = false,
    this.apiRelayBaseUrl = '',
    this.apiRelayApiKey = '',
    this.apiRelayModel = '',
    this.apiRelayEnabled = true,
    this.backendUrl = '', // No external backend — self-contained
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      llmModelFilename: json['llm.model_filename'] as String? ?? '',
      keepModelLoaded: json['llm.keep_model_loaded'] as bool? ?? true,
      enableMemoryRetrieval: json['llm.enableMemoryRetrieval'] as bool? ?? true,
      systemPrompt: json['llm.system_prompt'] as String? ?? '',
      showMonitor: json['llm.showMonitor'] as bool? ?? false,
      ttsProvider: json['tts.provider'] as String? ?? 'gpt-sovits',
      ttsVoice: json['tts.voice'] as String? ?? '',
      useRvc: json['rvc.use-rvc'] as bool? ?? false,
      rvcF0UpKey: json['rvc.f0-up-key'] as int? ?? 0,
      selectedLive2DModel: json['frontend.character.selectedLive2DModel'] as String?,
      selectedVRMModel: json['frontend.character.selectedVRMModel'] as String?,
      renderModel: json['frontend.character.renderModel'] as bool? ?? true,
      live2DXPosition: (json['frontend.character.live2D.xPosition'] as num?)?.toDouble() ?? 46,
      live2DYPosition: (json['frontend.character.live2D.yPosition'] as num?)?.toDouble() ?? 51,
      live2DScale: (json['frontend.character.live2D.scale'] as num?)?.toDouble() ?? 0.16,
      use3D: json['frontend.character.3d2dSwitch'] as bool? ?? false,
      apiRelayBaseUrl: json['api_relay']?['base_url'] as String? ?? '',
      apiRelayApiKey: json['api_relay']?['api_key'] as String? ?? '',
      apiRelayModel: json['api_relay']?['model'] as String? ?? '',
      apiRelayEnabled: json['api_relay']?['enabled'] as bool? ?? true,
    );
  }

  /// Create a copy with overridden fields — Dart equivalent of spread operator.
  AppSettings copyWith({
    String? llmModelFilename,
    bool? keepModelLoaded,
    bool? enableMemoryRetrieval,
    String? systemPrompt,
    bool? showMonitor,
    String? ttsProvider,
    String? ttsVoice,
    bool? useRvc,
    int? rvcF0UpKey,
    String? selectedLive2DModel,
    String? selectedVRMModel,
    bool? renderModel,
    double? live2DXPosition,
    double? live2DYPosition,
    double? live2DScale,
    bool? use3D,
    String? apiRelayBaseUrl,
    String? apiRelayApiKey,
    String? apiRelayModel,
    bool? apiRelayEnabled,
    String? backendUrl,
  }) {
    return AppSettings(
      llmModelFilename: llmModelFilename ?? this.llmModelFilename,
      keepModelLoaded: keepModelLoaded ?? this.keepModelLoaded,
      enableMemoryRetrieval: enableMemoryRetrieval ?? this.enableMemoryRetrieval,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      showMonitor: showMonitor ?? this.showMonitor,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      useRvc: useRvc ?? this.useRvc,
      rvcF0UpKey: rvcF0UpKey ?? this.rvcF0UpKey,
      selectedLive2DModel: selectedLive2DModel ?? this.selectedLive2DModel,
      selectedVRMModel: selectedVRMModel ?? this.selectedVRMModel,
      renderModel: renderModel ?? this.renderModel,
      live2DXPosition: live2DXPosition ?? this.live2DXPosition,
      live2DYPosition: live2DYPosition ?? this.live2DYPosition,
      live2DScale: live2DScale ?? this.live2DScale,
      use3D: use3D ?? this.use3D,
      apiRelayBaseUrl: apiRelayBaseUrl ?? this.apiRelayBaseUrl,
      apiRelayApiKey: apiRelayApiKey ?? this.apiRelayApiKey,
      apiRelayModel: apiRelayModel ?? this.apiRelayModel,
      apiRelayEnabled: apiRelayEnabled ?? this.apiRelayEnabled,
      backendUrl: backendUrl ?? this.backendUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'llm.model_filename': llmModelFilename,
    'llm.keep_model_loaded': keepModelLoaded,
    'llm.enableMemoryRetrieval': enableMemoryRetrieval,
    'llm.system_prompt': systemPrompt,
    'llm.showMonitor': showMonitor,
    'tts.provider': ttsProvider,
    'tts.voice': ttsVoice,
    'rvc.use-rvc': useRvc,
    'rvc.f0-up-key': rvcF0UpKey,
    'frontend.character.selectedLive2DModel': selectedLive2DModel,
    'frontend.character.selectedVRMModel': selectedVRMModel,
    'frontend.character.renderModel': renderModel,
    'frontend.character.live2D.xPosition': live2DXPosition,
    'frontend.character.live2D.yPosition': live2DYPosition,
    'frontend.character.live2D.scale': live2DScale,
    'frontend.character.3d2dSwitch': use3D,
    'api_relay': {
      'base_url': apiRelayBaseUrl,
      'api_key': apiRelayApiKey,
      'model': apiRelayModel,
      'enabled': apiRelayEnabled,
    },
  };
}
