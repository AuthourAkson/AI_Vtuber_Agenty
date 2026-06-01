import 'package:flutter/material.dart';

/// Lightweight localization for AI VTuber Agent.
/// Supports en, zh-CN, zh-TW.
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
  ];

  String get appTitle => _t('appTitle');
  String get appSubtitle => _t('appSubtitle');
  String get appBackend => _t('appBackend');
  String get appFramework => _t('appFramework');
  String get appVersion => _t('appVersion');
  String get appFeatures => _t('appFeatures');
  String get sidebarHome => _t('sidebarHome');
  String get sidebarInput => _t('sidebarInput');
  String get sidebarCharacter => _t('sidebarCharacter');
  String get sidebarVision => _t('sidebarVision');
  String get sidebarTTS => _t('sidebarTTS');
  String get sidebarMemory => _t('sidebarMemory');
  String get sidebarStream => _t('sidebarStream');
  String get sidebarPipeline => _t('sidebarPipeline');
  String get sidebarSettings => _t('sidebarSettings');
  String get sidebarAgents => _t('sidebarAgents');
  String get testPipeline => _t('testPipeline');
  String get chatNewSession => _t('chatNewSession');
  String get chatSessions => _t('chatSessions');
  String get chatStartConversation => _t('chatStartConversation');
  String get chatSettings => _t('chatSettings');
  String get chatNameHint => _t('chatNameHint');
  String get chatYou => _t('chatYou');
  String get chatAI => _t('chatAI');
  String get chatTypeMessage => _t('chatTypeMessage');
  String get chatSend => _t('chatSend');
  String get chatSaveSettings => _t('chatSaveSettings');
  String get memoryTitle => _t('memoryTitle');
  String get memorySubtitle => _t('memorySubtitle');
  String get memorySearch => _t('memorySearch');
  String get memoryEmpty => _t('memoryEmpty');
  String get memoryNoResults => _t('memoryNoResults');
  String get memoryNoResultsHint => _t('memoryNoResultsHint');
  String get memoryLoad => _t('memoryLoad');
  String get memoryCreated => _t('memoryCreated');
  String get generalTitle => _t('generalTitle');
  String get generalSubtitle => _t('generalSubtitle');
  String get generalAutoOpen => _t('generalAutoOpen');
  String get generalAutoOpenDesc => _t('generalAutoOpenDesc');
  String get generalLanguage => _t('generalLanguage');
  String get generalLanguageDesc => _t('generalLanguageDesc');
  String get appearanceTitle => _t('appearanceTitle');
  String get appearanceSubtitle => _t('appearanceSubtitle');
  String get appearanceDarkMode => _t('appearanceDarkMode');
  String get appearanceDarkModeDesc => _t('appearanceDarkModeDesc');
  String get appearanceFontSize => _t('appearanceFontSize');
  String get appearanceFontSizeDesc => _t('appearanceFontSizeDesc');
  String get appearanceThemeColor => _t('appearanceThemeColor');
  String get appearanceThemeColorDesc => _t('appearanceThemeColorDesc');
  String get appearanceThemeDisabled => _t('appearanceThemeDisabled');
  String get appearanceBgPattern => _t('appearanceBgPattern');
  String get appearanceBgPatternDesc => _t('appearanceBgPatternDesc');
  String get appearanceBgImage => _t('appearanceBgImage');
  String get appearanceBgImageDesc => _t('appearanceBgImageDesc');
  String get appearanceStartupAnim => _t('appearanceStartupAnim');
  String get appearanceStartupAnimDesc => _t('appearanceStartupAnimDesc');
  String get appearanceReset => _t('appearanceReset');
  String get appearanceResetDesc => _t('appearanceResetDesc');
  String get appearanceResetConfirm => _t('appearanceResetConfirm');
  String get appearanceUploadImage => _t('appearanceUploadImage');
  String get appearanceClearImage => _t('appearanceClearImage');
  String get appearancePreview => _t('appearancePreview');
  String get appearanceNoPattern => _t('appearanceNoPattern');
  String get appearanceChangeImage => _t('appearanceChangeImage');
  String get appearanceChooseImage => _t('appearanceChooseImage');
  String get appearanceStartupInfo => _t('appearanceStartupInfo');
  String get appearanceStartupComing => _t('appearanceStartupComing');
  String get appearanceDefault => _t('appearanceDefault');
  String get patternNone => _t('patternNone');
  String get patternDots => _t('patternDots');
  String get patternGrid => _t('patternGrid');
  String get patternDiagonal => _t('patternDiagonal');
  String get patternLines => _t('patternLines');
  String get patternCross => _t('patternCross');
  String get patternZigzag => _t('patternZigzag');
  String get patternWaves => _t('patternWaves');
  String get patternHexagon => _t('patternHexagon');
  String get patternCircles => _t('patternCircles');
  String get patternTriangles => _t('patternTriangles');
  String get patternDiamonds => _t('patternDiamonds');
  String get patternChess => _t('patternChess');
  String get llmTitle => _t('llmTitle');
  String get llmSystemPrompt => _t('llmSystemPrompt');
  String get llmPromptHint => _t('llmPromptHint');
  String get llmEnableMemory => _t('llmEnableMemory');
  String get llmEnableMemoryDesc => _t('llmEnableMemoryDesc');
  String get llmKeepLoaded => _t('llmKeepLoaded');
  String get llmKeepLoadedDesc => _t('llmKeepLoadedDesc');
  String get llmApiRelay => _t('llmApiRelay');
  String get llmApiRelayDesc => _t('llmApiRelayDesc');
  String get llmApiConfig => _t('llmApiConfig');
  String get llmBaseUrl => _t('llmBaseUrl');
  String get llmApiKey => _t('llmApiKey');
  String get llmModel => _t('llmModel');
  String get llmSave => _t('llmSave');
  String get llmSaved => _t('llmSaved');
  String get apiTitle => _t('apiTitle');
  String get apiPresets => _t('apiPresets');
  String get apiTest => _t('apiTest');
  String get apiTesting => _t('apiTesting');
  String get apiTestOK => _t('apiTestOK');
  String get apiSaved => _t('apiSaved');
  String get aiTitle => _t('aiTitle');
  String get aiSubtitle => _t('aiSubtitle');
  String get aiAddProfile => _t('aiAddProfile');
  String get aiEditProfile => _t('aiEditProfile');
  String get aiNewProfile => _t('aiNewProfile');
  String get aiProfileName => _t('aiProfileName');
  String get aiProfileNameHint => _t('aiProfileNameHint');
  String get charTitle => _t('charTitle');
  String get charShowCharacter => _t('charShowCharacter');
  String get charShowCharacterDesc => _t('charShowCharacterDesc');
  String get charLive2D => _t('charLive2D');
  String get charVRM => _t('charVRM');
  String get charLive2DPreview => _t('charLive2DPreview');
  String get charLive2DPosition => _t('charLive2DPosition');
  String get charScale => _t('charScale');
  String get charNoModel => _t('charNoModel');
  String get charUploadHint => _t('charUploadHint');
  String get charVRMPreview => _t('charVRMPreview');
  String get charVRMComing => _t('charVRMComing');
  String get charInstalledModels => _t('charInstalledModels');
  String get charNoModels => _t('charNoModels');
  String get charUploadModel => _t('charUploadModel');
  String get charUploadLive2D => _t('charUploadLive2D');
  String get charUploadVRM => _t('charUploadVRM');
  String get charVRMComingToast => _t('charVRMComingToast');
  String get charUploadGuide => _t('charUploadGuide');
  String get charOverlay => _t('charOverlay');
  String get charOverlayDesc => _t('charOverlayDesc');
  String get charOpenPet => _t('charOpenPet');
  String get charPetActive => _t('charPetActive');
  String get charClose => _t('charClose');
  String get charClickThrough => _t('charClickThrough');
  String get charInteractive => _t('charInteractive');
  String get charReloadModel => _t('charReloadModel');
  String get charDelete => _t('charDelete');
  String get charDeleteConfirm => _t('charDeleteConfirm');
  String get charModelImported => _t('charModelImported');
  String get charImportFailed => _t('charImportFailed');
  String get charPetOpened => _t('charPetOpened');
  String get charPetFailed => _t('charPetFailed');
  String get charImporting => _t('charImporting');
  String get charDisplaySection => _t('charDisplaySection');
  String get charModelSection => _t('charModelSection');
  String get charManageSection => _t('charManageSection');
  String get charPetSection => _t('charPetSection');
  String get charSelectModel => _t('charSelectModel');
  String get charSelectModelHint => _t('charSelectModelHint');
  String get charNoVRMModel => _t('charNoVRMModel');
  String get charSelectVRMModel => _t('charSelectVRMModel');
  String get charXPosition => _t('charXPosition');
  String get charYPosition => _t('charYPosition');
  String get charClickThroughOn => _t('charClickThroughOn');
  String get charChromaKey => _t('charChromaKey');
  String get charChromaKeyOn => _t('charChromaKeyOn');
  String get charChromaKeyColor => _t('charChromaKeyColor');
  String get charPopoutOpen => _t('charPopoutOpen');
  String get charPopoutClose => _t('charPopoutClose');
  String get ttsTitle => _t('ttsTitle');
  String get ttsSubtitle => _t('ttsSubtitle');
  String get ttsProvider => _t('ttsProvider');
  String get ttsActiveVoice => _t('ttsActiveVoice');
  String get ttsEnableRVC => _t('ttsEnableRVC');
  String get ttsRvcSettings => _t('ttsRvcSettings');
  String get ttsPitchShift => _t('ttsPitchShift');
  String get ttsUploadVoice => _t('ttsUploadVoice');
  String get visionTitle => _t('visionTitle');
  String get visionPrompt => _t('visionPrompt');
  String get visionPromptHint => _t('visionPromptHint');
  String get visionOcrPrompt => _t('visionOcrPrompt');
  String get visionOcrHint => _t('visionOcrHint');
  String get visionCapture => _t('visionCapture');
  String get visionCapturing => _t('visionCapturing');
  String get visionContext => _t('visionContext');
  String get visionNoContext => _t('visionNoContext');
  String get streamTitle => _t('streamTitle');
  String get streamId => _t('streamId');
  String get streamIdHint => _t('streamIdHint');
  String get streamConnect => _t('streamConnect');
  String get streamDisconnect => _t('streamDisconnect');
  String get streamConnected => _t('streamConnected');
  String get streamControls => _t('streamControls');
  String get streamManualReply => _t('streamManualReply');
  String get streamOBSTip => _t('streamOBSTip');
  String get streamWaiting => _t('streamWaiting');
  String get streamConnectForDanmaku => _t('streamConnectForDanmaku');
  String get streamMessages => _t('streamMessages');
  String get streamNotConnected => _t('streamNotConnected');
  String get streamSetlist => _t('streamSetlist');
  String get streamNoItems => _t('streamNoItems');
  String get streamStatusLive => _t('streamStatusLive');
  String get streamStatusOff => _t('streamStatusOff');
  String get streamAutoReply => _t('streamAutoReply');
  String get streamConnection => _t('streamConnection');
  String get streamAddNodeHint => _t('streamAddNodeHint');
  String get streamStopFlow => _t('streamStopFlow');
  String get streamStartFlow => _t('streamStartFlow');
  String get streamInProgress => _t('streamInProgress');
  String get streamNodeSettings => _t('streamNodeSettings');
  String get streamPreset => _t('streamPreset');
  String get streamPresetHint => _t('streamPresetHint');
  String get confirm => _t('confirm');
  String get pipelineTitle => _t('pipelineTitle');
  String get pipelineTasks => _t('pipelineTasks');
  String get pipelineNoTasks => _t('pipelineNoTasks');
  String get settingsTitle => _t('settingsTitle');
  String get settingsServer => _t('settingsServer');
  String get settingsBackendHint => _t('settingsBackendHint');
  String get settingsSelfContained => _t('settingsSelfContained');
  String get settingsAbout => _t('settingsAbout');
  String get settingsClearCache => _t('settingsClearCache');
  String get settingsDataStorage => _t('settingsDataStorage');
  String get waTitle => _t('waTitle');
  String get waEnable => _t('waEnable');
  String get waEnableDesc => _t('waEnableDesc');
  String get waJoin => _t('waJoin');
  String get waCreate => _t('waCreate');
  String get waHost => _t('waHost');
  String get waPort => _t('waPort');
  String get waDeviceName => _t('waDeviceName');
  String get waTopic => _t('waTopic');
  String get waTopicHint => _t('waTopicHint');
  String get waDisconnect => _t('waDisconnect');
  String get waConnected => _t('waConnected');
  String get waStart => _t('waStart');
  String get waJoinNetwork => _t('waJoinNetwork');
  String get waHostNetwork => _t('waHostNetwork');
  String get waServerHint => _t('waServerHint');
  String get waEmployees => _t('waEmployees');
  String get waNoEmployees => _t('waNoEmployees');
  String get waCreateEmployee => _t('waCreateEmployee');
  String get waSearchAgents => _t('waSearchAgents');
  String get waNoAgents => _t('waNoAgents');
  String get waNoMatching => _t('waNoMatching');
  String get waName => _t('waName');
  String get waDescription => _t('waDescription');
  String get waDescHint => _t('waDescHint');
  String get waSelectProfile => _t('waSelectProfile');
  String get waDeleteEmployee => _t('waDeleteEmployee');
  String get waDeleteConfirm => _t('waDeleteConfirm');
  String get waDeleteSession => _t('waDeleteSession');
  String get waDeleteSessionConfirm => _t('waDeleteSessionConfirm');
  String get waEmptyHint => _t('waEmptyHint');
  String get waEmptySub => _t('waEmptySub');
  String get waSendMessage => _t('waSendMessage');
  String get cancel => _t('cancel');
  String get save => _t('save');
  String get create => _t('create');
  String get delete => _t('delete');
  String get reset => _t('reset');
  String get resetAll => _t('resetAll');
  String get close => _t('close');
  String get load => _t('load');
  String get preferences => _t('preferences');
  String get aiSection => _t('aiSection');
  String get dataSection => _t('dataSection');
  String get networkSection => _t('networkSection');
  String get systemSection => _t('systemSection');
  String get appearance => _t('appearance');
  String get general => _t('general');
  String get aiConfig => _t('aiConfig');
  String get mcpConfig => _t('mcpConfig');
  String get permissions => _t('permissions');
  String get lan => _t('lan');
  String get devices => _t('devices');
  String get devicesOnline => _t('devicesOnline');
  String get noDevicesOnline => _t('noDevicesOnline');
  String get notSet => _t('notSet');
  String get deviceTypeLabel => _t('deviceTypeLabel');
  String get deviceTypeDesktop => _t('deviceTypeDesktop');
  String get deviceTypeMobile => _t('deviceTypeMobile');
  String get devicePlatform => _t('devicePlatform');
  String get deviceOs => _t('deviceOs');
  String get deviceIp => _t('deviceIp');
  String get deviceConnectedAt => _t('deviceConnectedAt');
  String get deviceIdLabel => _t('deviceIdLabel');
  String get deviceConfig => _t('deviceConfig');
  String get deviceNameLabel => _t('deviceNameLabel');
  String get privacy => _t('privacy');
  String get privacyTitle => _t('privacyTitle');
  String get privacySubtitle => _t('privacySubtitle');
  String get skills => _t('skills');
  String get skillAdd => _t('skillAdd');
  String get skillAddTitle => _t('skillAddTitle');
  String get skillName => _t('skillName');
  String get skillNameHint => _t('skillNameHint');
  String get skillDesc => _t('skillDesc');
  String get skillDescHint => _t('skillDescHint');
  String get skillFolderPath => _t('skillFolderPath');
  String get skillFolderHint => _t('skillFolderHint');
  String get skillBrowse => _t('skillBrowse');
  String get skillSelectFolder => _t('skillSelectFolder');
  String get skillSelectZip => _t('skillSelectZip');
  String get skillSearchFolder => _t('skillSearchFolder');
  String get skillEnabled => _t('skillEnabled');
  String get skillDisabled => _t('skillDisabled');
  String get skillDelete => _t('skillDelete');
  String get skillDeleteConfirm => _t('skillDeleteConfirm');
  String get skillModify => _t('skillModify');
  String get skillConfig => _t('skillConfig');
  String get skillInfo => _t('skillInfo');
  String get skillId => _t('skillId');
  String get skillType => _t('skillType');
  String get skillCreatedAt => _t('skillCreatedAt');
  String get skillUpdatedAt => _t('skillUpdatedAt');
  String get skillNoSkills => _t('skillNoSkills');
  String get skillConfirm => _t('skillConfirm');
  String get privacyClearCache => _t('privacyClearCache');
  String get privacyClearCacheDesc => _t('privacyClearCacheDesc');
  String get privacyClearCacheConfirm => _t('privacyClearCacheConfirm');
  String get privacyCacheCleared => _t('privacyCacheCleared');
  String get privacyClearCacheButton => _t('privacyClearCacheButton');
  String get logs => _t('logs');
  String get about => _t('about');
  String get logTitle => _t('logTitle');
  String get logSubtitle => _t('logSubtitle');
  String get logSearch => _t('logSearch');
  String get logAll => _t('logAll');
  String get logExport => _t('logExport');
  String get logClear => _t('logClear');
  String get logClearConfirm => _t('logClearConfirm');
  String get logCount => _t('logCount');
  String get logEmpty => _t('logEmpty');
  String get logEmptyHint => _t('logEmptyHint');
  String get logLevel => _t('logLevel');
  String get logModule => _t('logModule');
  String get logMessage => _t('logMessage');
  String get logStackTrace => _t('logStackTrace');
  String get logExported => _t('logExported');
  String get logExportFailed => _t('logExportFailed');
  String get logTime => _t('logTime');
  String get mcpTitle => _t('mcpTitle');
  String get mcpSubtitle => _t('mcpSubtitle');
  String get mcpRunning => _t('mcpRunning');
  String get mcpStopped => _t('mcpStopped');
  String get mcpStart => _t('mcpStart');
  String get mcpStop => _t('mcpStop');
  String get mcpEditConfig => _t('mcpEditConfig');
  String get mcpHost => _t('mcpHost');
  String get mcpPort => _t('mcpPort');
  String get mcpConfigJson => _t('mcpConfigJson');
  String get mcpConfigHint => _t('mcpConfigHint');
  String get mcpSaveConfig => _t('mcpSaveConfig');
  String get mcpNoServers => _t('mcpNoServers');
  String get mcpAddServer => _t('mcpAddServer');
  String get permTitle => _t('permTitle');
  String get permSubtitle => _t('permSubtitle');
  String get permEnabled => _t('permEnabled');
  String get permDisabled => _t('permDisabled');
  String get permAddRule => _t('permAddRule');
  String get permDeleteRule => _t('permDeleteRule');
  String get permRulePattern => _t('permRulePattern');
  String get permRuleDesc => _t('permRuleDesc');
  String get permRuleType => _t('permRuleType');
  String get permRuleAllow => _t('permRuleAllow');
  String get permRuleDeny => _t('permRuleDeny');
  String get permPatternHint => _t('permPatternHint');
  String get permDescHint => _t('permDescHint');
  String get permFileRead => _t('permFileRead');
  String get permFileReadDesc => _t('permFileReadDesc');
  String get permFileWrite => _t('permFileWrite');
  String get permFileWriteDesc => _t('permFileWriteDesc');
  String get permFileDelete => _t('permFileDelete');
  String get permFileDeleteDesc => _t('permFileDeleteDesc');
  String get permFilePatch => _t('permFilePatch');
  String get permFilePatchDesc => _t('permFilePatchDesc');
  String get permDirCreate => _t('permDirCreate');
  String get permDirCreateDesc => _t('permDirCreateDesc');
  String get permCmdExec => _t('permCmdExec');
  String get permCmdExecDesc => _t('permCmdExecDesc');
  String get permBgCmd => _t('permBgCmd');
  String get permBgCmdDesc => _t('permBgCmdDesc');
  String get permGitOps => _t('permGitOps');
  String get permGitOpsDesc => _t('permGitOpsDesc');
  String get permDocRead => _t('permDocRead');
  String get permDocReadDesc => _t('permDocReadDesc');
  String get permDocWrite => _t('permDocWrite');
  String get permDocWriteDesc => _t('permDocWriteDesc');
  String get permTaskRead => _t('permTaskRead');
  String get permTaskReadDesc => _t('permTaskReadDesc');
  String get permTaskWrite => _t('permTaskWrite');
  String get permTaskWriteDesc => _t('permTaskWriteDesc');
  String get dataFilesTitle => _t('dataFilesTitle');
  String get dataFilesSubtitle => _t('dataFilesSubtitle');
  String get dataFilesOpenDir => _t('dataFilesOpenDir');
  String get dataFilesEmpty => _t('dataFilesEmpty');
  String get dataStorageTitle => _t('dataStorageTitle');
  String get dataStorageSubtitle => _t('dataStorageSubtitle');
  String get dataStorageSpace => _t('dataStorageSpace');
  String get dataStorageFiles => _t('dataStorageFiles');
  String get dataStorageManage => _t('dataStorageManage');
  String get dataStorageOpen => _t('dataStorageOpen');
  String get sync => _t('sync');
  String get storage => _t('storage');
  String get files => _t('files');
  String get comingSoon => _t('comingSoon');

  String _t(String key) {
    final entry = _strings[key];
    if (entry == null) return key;
    return entry[locale.languageCode] ?? entry['en'] ?? key;
  }

  static const _strings = <String, Map<String, String>>{
    'appTitle':       {'en': 'AI VTuber Agent',    'zh': 'AI 虚拟主播代理'},
    'appSubtitle':    {'en': 'v1.0.0 — Flutter Desktop App', 'zh': 'v1.0.0 — Flutter 桌面应用'},
    'appBackend':     {'en': 'Backend: Self-contained Dart services', 'zh': '后端：自包含 Dart 服务'},
    'appFramework':   {'en': 'UI Framework: Flutter 3.x + Provider', 'zh': 'UI 框架：Flutter 3.x + Provider'},
    'appVersion':     {'en': 'Features:',           'zh': '功能特性：'},
    'appFeatures':    {'en': 'AI VTuber Agent',     'zh': 'AI 虚拟主播代理'},
    'sidebarHome':      {'en': 'Home',       'zh': '首页'},
    'sidebarInput':     {'en': 'Input',      'zh': '输入'},
    'sidebarCharacter': {'en': 'Character',  'zh': '角色'},
    'sidebarVision':    {'en': 'Vision',     'zh': '视觉'},
    'sidebarTTS':       {'en': 'TTS',        'zh': '语音'},
    'sidebarMemory':    {'en': 'Memory',     'zh': '记忆'},
    'sidebarStream':    {'en': 'Stream',     'zh': '直播'},
    'sidebarPipeline':  {'en': 'Pipeline',   'zh': '流水线'},
    'sidebarSettings':  {'en': 'Settings',   'zh': '设置'},
    'sidebarAgents':    {'en': 'Multi-Agent', 'zh': '多代理'},
    'testPipeline':     {'en': 'Test pipeline', 'zh': '测试流水线'},
    'chatNewSession':       {'en': 'New Session',          'zh': '新建会话'},
    'chatSessions':         {'en': 'Sessions',             'zh': '会话列表'},
    'chatStartConversation':{'en': 'Start a conversation', 'zh': '开始对话'},
    'chatSettings':         {'en': 'Settings',             'zh': '设置'},
    'chatNameHint':         {'en': 'Session name',         'zh': '会话名称'},
    'chatYou':              {'en': 'You',                  'zh': '你'},
    'chatAI':               {'en': 'AI',                   'zh': 'AI'},
    'chatTypeMessage':      {'en': 'Type your message here.', 'zh': '在此输入消息...'},
    'chatSend':             {'en': 'Send',                 'zh': '发送'},
    'chatSaveSettings':     {'en': 'Save Settings',        'zh': '保存设置'},
    'memoryTitle':        {'en': 'Chat Sessions',    'zh': '聊天会话'},
    'memorySubtitle':     {'en': 'Manage and review your conversation sessions', 'zh': '管理和查看您的对话会话'},
    'memorySearch':       {'en': 'Search sessions...', 'zh': '搜索会话...'},
    'memoryEmpty':        {'en': 'Memory Empty',      'zh': '记忆为空'},
    'memoryNoResults':    {'en': 'No sessions found', 'zh': '未找到会话'},
    'memoryNoResultsHint':{'en': 'Try adjusting your search criteria', 'zh': '请尝试调整搜索条件'},
    'memoryLoad':         {'en': 'Load',              'zh': '加载'},
    'memoryCreated':      {'en': 'Created:',          'zh': '创建于：'},
    'generalTitle':         {'en': 'General Preferences',         'zh': '通用设置'},
    'generalSubtitle':      {'en': 'Behaviour and language settings.', 'zh': '行为和语言设置。'},
    'generalAutoOpen':      {'en': 'Auto-open last page on startup', 'zh': '启动时自动打开上次的页面'},
    'generalAutoOpenDesc':  {'en': 'Restore the last active page when the app starts', 'zh': '应用启动时恢复上次打开的页面'},
    'generalLanguage':      {'en': 'Language',                    'zh': '语言'},
    'generalLanguageDesc':  {'en': 'Select the UI display language', 'zh': '选择界面显示语言'},
    'appearanceTitle':          {'en': 'Appearance',               'zh': '外观设置'},
    'appearanceSubtitle':       {'en': 'Customise the look and feel of the application', 'zh': '自定义应用的外观和风格'},
    'appearanceDarkMode':       {'en': 'Dark Mode',                'zh': '深色模式'},
    'appearanceDarkModeDesc':   {'en': 'Switch between dark and light theme', 'zh': '在深色和浅色主题之间切换'},
    'appearanceFontSize':       {'en': 'Font Size',                'zh': '字体大小'},
    'appearanceFontSizeDesc':   {'en': 'Adjust the application font size', 'zh': '调整应用的字体大小'},
    'appearanceThemeColor':     {'en': 'Theme Color',              'zh': '主题颜色'},
    'appearanceThemeColorDesc': {'en': 'Choose a colour accent for the UI', 'zh': '选择界面的强调色'},
    'appearanceThemeDisabled':  {'en': 'Theme color disabled — using default Blue', 'zh': '主题颜色已关闭 — 使用默认蓝色'},
    'appearanceBgPattern':      {'en': 'Background Pattern',       'zh': '背景图案'},
    'appearanceBgPatternDesc':  {'en': 'Select a background pattern', 'zh': '选择背景图案'},
    'appearanceBgImage':        {'en': 'Background Image',         'zh': '背景图片'},
    'appearanceBgImageDesc':    {'en': 'Set a custom background image', 'zh': '设置自定义背景图片'},
    'appearanceStartupAnim':    {'en': 'Startup Animation',        'zh': '启动动画'},
    'appearanceStartupAnimDesc':{'en': 'Show transition animation on startup', 'zh': '启动时显示过渡动画'},
    'appearanceReset':          {'en': 'Reset to Default',         'zh': '恢复默认'},
    'appearanceResetDesc':      {'en': 'Restore all appearance settings to factory defaults', 'zh': '将所有外观设置恢复为出厂默认值'},
    'appearanceResetConfirm':   {'en': 'This will restore all appearance settings to their factory defaults.', 'zh': '这将把所有外观设置恢复为出厂默认值。'},
    'appearanceUploadImage':    {'en': 'Upload Image',             'zh': '上传图片'},
    'appearanceClearImage':     {'en': 'Clear Image',              'zh': '清除图片'},
    'appearancePreview':        {'en': 'The quick brown fox jumps over the lazy dog.', 'zh': '敏捷的棕色狐狸跳过了懒狗。'},
        'patternNone':      {'en': 'None',      'zh': '无'},
    'patternDots':      {'en': 'Dots',      'zh': '圆点'},
    'patternGrid':      {'en': 'Grid',      'zh': '网格'},
    'patternDiagonal':  {'en': 'Diagonal',  'zh': '斜线'},
    'patternLines':     {'en': 'Lines',     'zh': '横线'},
    'patternCross':     {'en': 'Cross',     'zh': '交叉'},
    'patternZigzag':    {'en': 'Zigzag',    'zh': '锯齿'},
    'patternWaves':     {'en': 'Waves',     'zh': '波浪'},
    'patternHexagon':   {'en': 'Hexagon',   'zh': '六边形'},
    'patternCircles':   {'en': 'Circles',   'zh': '圆形'},
    'patternTriangles': {'en': 'Triangles', 'zh': '三角'},
    'patternDiamonds':  {'en': 'Diamonds',  'zh': '菱形'},
    'patternChess':     {'en': 'Chess',     'zh': '棋盘'},
    'appearanceNoPattern':      {'en': 'No pattern',               'zh': '无图案'},
    'appearanceChangeImage':    {'en': 'Change Image',             'zh': '更换图片'},
    'appearanceChooseImage':    {'en': 'Choose Image',             'zh': '选择图片'},
    'appearanceStartupInfo':    {'en': 'Startup animation will play when launching the app.', 'zh': '启动应用时将播放过渡动画。'},
    'appearanceStartupComing':  {'en': 'This feature is not yet implemented. Enable it now to auto-activate when available.', 'zh': '此功能尚未实现。现在启用以在可用时自动激活。'},
    'appearanceDefault':        {'en': 'Default',                  'zh': '默认'},
    'llmTitle':           {'en': 'LLM Settings',                 'zh': 'LLM 设置'},
    'llmSystemPrompt':    {'en': 'System Prompt',                'zh': '系统提示词'},
    'llmPromptHint':      {'en': 'Enter the character system prompt...', 'zh': '输入角色系统提示词...'},
    'llmEnableMemory':    {'en': 'Enable Memory Retrieval',      'zh': '启用记忆检索'},
    'llmEnableMemoryDesc':{'en': 'Use vector memory for context','zh': '使用向量记忆获取上下文'},
    'llmKeepLoaded':      {'en': 'Keep Model Loaded',            'zh': '保持模型加载'},
    'llmKeepLoadedDesc':  {'en': 'Keep LLM in VRAM for faster responses', 'zh': '将 LLM 保持在显存中以加快响应'},
    'llmApiRelay':        {'en': 'API Relay Mode',               'zh': 'API 中继模式'},
    'llmApiRelayDesc':    {'en': 'Use remote API instead of local LLM', 'zh': '使用远程 API 代替本地 LLM'},
    'llmApiConfig':       {'en': 'API Relay Config',             'zh': 'API 中继配置'},
    'llmBaseUrl':         {'en': 'Base URL',                     'zh': '基础 URL'},
    'llmApiKey':          {'en': 'API Key',                      'zh': 'API 密钥'},
    'llmModel':           {'en': 'Model',                        'zh': '模型'},
    'llmSave':            {'en': 'Save Settings',                'zh': '保存设置'},
    'llmSaved':           {'en': 'Settings saved',               'zh': '设置已保存'},
    'apiTitle':     {'en': 'API Config',             'zh': 'API 配置'},
    'apiPresets':   {'en': 'Quick Presets',          'zh': '快速预设'},
    'apiTest':      {'en': 'Test',                   'zh': '测试'},
    'apiTesting':   {'en': 'Testing...',             'zh': '测试中...'},
    'apiTestOK':    {'en': 'Connection successful',   'zh': '连接成功'},
    'apiSaved':     {'en': 'API settings saved',     'zh': 'API 设置已保存'},
    'aiTitle':            {'en': 'AI Provider Profiles',   'zh': 'AI 提供商配置'},
    'aiSubtitle':         {'en': 'Create named profiles with base URL, API key, and model. Select a profile when starting an agent chat.', 'zh': '创建包含基础 URL、API 密钥和模型的命名配置文件。'},
    'aiAddProfile':       {'en': 'Add Profile',           'zh': '添加配置'},
    'aiEditProfile':      {'en': 'Edit Profile',          'zh': '编辑配置'},
    'aiNewProfile':       {'en': 'New Profile',           'zh': '新建配置'},
    'aiProfileName':      {'en': 'Profile Name',          'zh': '配置名称'},
    'aiProfileNameHint':  {'en': 'e.g. My OpenAI',        'zh': '例如：我的 OpenAI'},
    'charTitle':            {'en': 'Character Settings',      'zh': '角色设置'},
    'charShowCharacter':    {'en': 'Show Character',          'zh': '显示角色'},
    'charShowCharacterDesc':{'en': 'Display Live2D/VRM character on screen', 'zh': '在屏幕上显示 Live2D/VRM 角色'},
    'charLive2D':           {'en': 'Live2D (2D)',             'zh': 'Live2D (2D)'},
    'charVRM':              {'en': 'VRM (3D)',                'zh': 'VRM (3D)'},
    'charLive2DPreview':    {'en': 'Live2D Preview',          'zh': 'Live2D 预览'},
    'charLive2DPosition':   {'en': 'Live2D Position',         'zh': 'Live2D 位置'},
    'charScale':            {'en': 'Scale',                   'zh': '缩放'},
    'charNoModel':          {'en': 'No model selected',       'zh': '未选择模型'},
    'charUploadHint':       {'en': 'Upload a Live2D model to preview', 'zh': '上传 Live2D 模型以预览'},
    'charVRMPreview':       {'en': 'VRM 3D Preview',          'zh': 'VRM 3D 预览'},
    'charVRMComing':        {'en': 'Coming soon',             'zh': '即将推出'},
    'charInstalledModels':  {'en': 'Installed Models',        'zh': '已安装模型'},
    'charNoModels':         {'en': 'No models installed. Upload a Live2D model folder.', 'zh': '未安装模型。请上传 Live2D 模型文件夹。'},
    'charUploadModel':      {'en': 'Upload Model',            'zh': '上传模型'},
    'charUploadLive2D':     {'en': 'Upload Live2D',           'zh': '上传 Live2D'},
    'charUploadVRM':        {'en': 'Upload VRM',              'zh': '上传 VRM'},
    'charVRMComingToast':   {'en': 'VRM upload coming in next update', 'zh': 'VRM 上传将在下一版本推出'},
    'charUploadGuide':      {'en': 'Select the .model3.json or .model.json file inside your Live2D model folder.', 'zh': '选择 Live2D 模型文件夹中的 .model3.json 或 .model.json 文件。'},
    'charOverlay':          {'en': 'Transparent Overlay',     'zh': '透明浮窗'},
    'charOverlayDesc':      {'en': 'Open a separate transparent, always-on-top window with your Live2D character. Default: click-through. F2 to toggle Interactive mode. ESC to close.', 'zh': '打开独立的透明置顶窗口显示 Live2D 角色。F2 切换交互模式。ESC 关闭。'},
    'charOpenPet':          {'en': 'Open Pet',                'zh': '打开桌宠'},
    'charPetActive':        {'en': 'Pet Active',              'zh': '桌宠已激活'},
    'charClose':            {'en': 'Close',                   'zh': '关闭'},
    'charClickThrough':     {'en': 'Click-through ON',        'zh': '鼠标穿透：开'},
    'charInteractive':      {'en': 'Interactive',             'zh': '可交互'},
    'charReloadModel':      {'en': 'Reload Model',            'zh': '重新加载模型'},
    'charDelete':           {'en': 'Delete',                  'zh': '删除'},
    'charDeleteConfirm':    {'en': r'Delete "$modelName"? This cannot be undone.', 'zh': r'删除"$modelName"？此操作不可撤销。'},
    'charModelImported':    {'en': r'Model "$modelName" imported', 'zh': r'模型"$modelName"已导入'},
    'charImportFailed':     {'en': r'Import failed: $e',       'zh': r'导入失败：$e'},
    'charPetOpened':        {'en': 'Desktop pet opened.',     'zh': '桌宠已打开。'},
    'charPetFailed':        {'en': 'Failed to extract pet script.', 'zh': '提取桌宠脚本失败。'},
    'charImporting':        {'en': 'Importing...',            'zh': '导入中...'},
    'charDisplaySection':   {'en': 'Display',                 'zh': '显示'},
    'charModelSection':     {'en': 'Model Configuration',     'zh': '模型配置'},
    'charManageSection':    {'en': 'Model Management',        'zh': '模型管理'},
    'charPetSection':       {'en': 'Desktop Pet',             'zh': '桌面宠物'},
    'charSelectModel':      {'en': 'Select Model',            'zh': '选择模型'},
    'charSelectModelHint':  {'en': 'Choose a model...',       'zh': '选择模型...'},
    'charNoVRMModel':       {'en': 'No VRM Model Selected',   'zh': '未选择 VRM 模型'},
    'charSelectVRMModel':   {'en': 'Select VRM Model',        'zh': '选择 VRM 模型'},
    'charXPosition':        {'en': 'X Position',              'zh': '水平位置'},
    'charYPosition':        {'en': 'Y Position',              'zh': '垂直位置'},
    'charClickThroughOn':   {'en': 'Click-through ON',        'zh': '鼠标穿透：开'},
    'charChromaKey':        {'en': 'Chroma Key',              'zh': '色度键'},
    'charChromaKeyOn':      {'en': r'Chroma Key: $colorName',  'zh': r'色度键：$colorName'},
    'charChromaKeyColor':   {'en': 'Color',                   'zh': '颜色'},
    'charPopoutOpen':       {'en': 'Pop Out (OBS)',           'zh': '弹出窗口(OBS采集)'},
    'charPopoutClose':      {'en': 'Close Pop Out',           'zh': '关闭弹出窗口'},
    'ttsTitle':       {'en': 'TTS Settings',                      'zh': 'TTS 设置'},
    'ttsSubtitle':    {'en': 'Configure text-to-speech engine and voice settings', 'zh': '配置文字转语音引擎和语音设置'},
    'ttsProvider':    {'en': 'TTS Provider Selection',            'zh': 'TTS 提供商选择'},
    'ttsActiveVoice': {'en': 'Active Voice',                      'zh': '当前语音'},
    'ttsEnableRVC':   {'en': 'Enable RVC',                        'zh': '启用 RVC'},
    'ttsRvcSettings': {'en': 'RVC Settings',                      'zh': 'RVC 设置'},
    'ttsPitchShift':  {'en': 'Pitch Shift (semitones):',          'zh': '音高偏移（半音）：'},
    'ttsUploadVoice': {'en': 'Upload Voice Model',                'zh': '上传语音模型'},
    'visionTitle':        {'en': 'Vision / Screenshot',           'zh': '视觉 / 截图'},
    'visionPrompt':       {'en': 'Vision Prompt',                 'zh': '视觉提示词'},
    'visionPromptHint':   {'en': 'Describe the screen for the AI...', 'zh': '为 AI 描述屏幕内容...'},
    'visionOcrPrompt':    {'en': 'OCR Prompt',                    'zh': 'OCR 提示词'},
    'visionOcrHint':      {'en': 'OCR text context for the AI...','zh': '为 AI 提供 OCR 文字上下文...'},
    'visionCapture':      {'en': 'Capture Screenshot',            'zh': '截取屏幕'},
    'visionCapturing':    {'en': 'Capturing...',                  'zh': '截图中...'},
    'visionContext':      {'en': 'Current Vision Context',        'zh': '当前视觉上下文'},
    'visionNoContext':    {'en': 'No vision context',             'zh': '无视觉上下文'},
    'streamTitle':          {'en': 'Bilibili Live Stream',    'zh': 'Bilibili 直播'},
    'streamId':             {'en': 'Room ID',                 'zh': '直播间号'},
    'streamIdHint':         {'en': 'Enter Bilibili room ID',  'zh': '输入 Bilibili 直播间号'},
    'streamConnect':        {'en': 'Connect to Live Chat',    'zh': '连接直播间'},
    'streamDisconnect':     {'en': 'Disconnect',              'zh': '断开连接'},
    'streamConnected':      {'en': 'Connected',               'zh': '已连接'},
    'streamControls':       {'en': 'Stream Controls',         'zh': '直播控制'},
    'streamManualReply':    {'en': 'Manual AI Reply',         'zh': '手动触发AI回复'},
    'streamOBSTip':         {'en': 'Use OBS/Bilibili Studio window capture to overlay character onto stream', 'zh': 'OBS/Bilibili直播姬 窗口捕获即可将角色画面推流到直播间'},
    'streamWaiting':        {'en': 'Waiting for danmaku...',  'zh': '等待弹幕中...'},
    'streamConnectForDanmaku': {'en': 'Connect to see danmaku', 'zh': '连接直播间后显示弹幕'},
    'streamMessages':       {'en': 'Live Danmaku',            'zh': '直播弹幕'},
    'streamNotConnected':   {'en': 'Not connected to stream', 'zh': '未连接到直播'},
    'streamSetlist':        {'en': 'Stream Setlist',          'zh': '直播流程 Setlist'},
    'streamNoItems':        {'en': 'No nodes in setlist',     'zh': '流程中无节点'},
    'streamStatusLive':     {'en': r'Live · $pop viewers',    'zh': r'直播中 · $pop人气'},
    'streamStatusOff':      {'en': 'Disconnected',            'zh': '未连接'},
    'streamAutoReply':      {'en': 'Auto Reply',              'zh': '自动回复'},
    'streamConnection':     {'en': 'Connection',              'zh': '直播间连接'},
    'streamAddNodeHint':    {'en': 'Click + to add a node',   'zh': '点击 + 添加直播节点'},
    'streamStopFlow':       {'en': 'Stop Flow',               'zh': '停止流程'},
    'streamStartFlow':      {'en': 'Start Flow',              'zh': '开始流程'},
    'streamInProgress':     {'en': '\u25c0 Active',           'zh': '\u25c0 进行中'},
    'streamNodeSettings':   {'en': r'$name Settings',          'zh': r'$name 设置'},
    'streamPreset':         {'en': 'Preset',                  'zh': '预设'},
    'streamPresetHint':     {'en': 'Choose preset...',        'zh': '选择预设...'},
    'confirm':              {'en': 'Confirm',                 'zh': '确定'},
    'pipelineTitle':    {'en': 'Pipeline Monitor',   'zh': '流水线监控'},
    'pipelineTasks':    {'en': 'tasks',              'zh': '个任务'},
    'pipelineNoTasks':  {'en': 'No pipeline tasks',  'zh': '无流水线任务'},
    'settingsTitle':        {'en': 'Settings',                          'zh': '设置'},
    'settingsServer':       {'en': 'Server Connection',                 'zh': '服务器连接'},
    'settingsBackendHint':  {'en': 'AiVtuber_Agent_profile',            'zh': 'AiVtuber_Agent_profile'},
    'settingsSelfContained':{'en': 'Self-contained — no external backend needed', 'zh': '自包含 — 无需外部后端'},
    'settingsAbout':        {'en': 'About',                             'zh': '关于'},
    'settingsClearCache':   {'en': 'Clear Local Cache',                 'zh': '清除本地缓存'},
    'settingsDataStorage':  {'en': 'Data & Storage',                    'zh': '数据与存储'},
    'waTitle':            {'en': 'WenzAgent Multi-Agent Network', 'zh': 'WenzAgent 多代理网络'},
    'waEnable':           {'en': 'Enable multi-agent LAN',       'zh': '启用多代理局域网'},
    'waEnableDesc':       {'en': 'Connect to a WenzAgent LAN server for multi-device AI collaboration', 'zh': '连接到 WenzAgent LAN 服务器进行多设备 AI 协作'},
    'waJoin':             {'en': 'Join LAN',                     'zh': '加入局域网'},
    'waCreate':           {'en': 'Create LAN',                   'zh': '创建局域网'},
    'waHost':             {'en': 'Server IP Address',            'zh': '服务器 IP 地址'},
    'waPort':             {'en': 'Port',                         'zh': '端口'},
    'waDeviceName':       {'en': 'Device Name',                  'zh': '设备名称'},
    'waTopic':            {'en': 'Topic (optional)',             'zh': '主题（可选）'},
    'waTopicHint':        {'en': 'Group identifier',             'zh': '群组标识符'},
    'waDisconnect':       {'en': 'Disconnect',                   'zh': '断开连接'},
    'waConnected':        {'en': 'Connected to LAN',             'zh': '已连接到局域网'},
    'waStart':            {'en': 'Start',                        'zh': '开始'},
    'waJoinNetwork':      {'en': 'Join Network',                 'zh': '加入网络'},
    'waHostNetwork':      {'en': 'Host Network',                 'zh': '托管网络'},
    'waServerHint':       {'en': 'Run wenzagent_server.exe on this machine first,\nthen click Start to connect.', 'zh': '请先在此机器上运行 wenzagent_server.exe，\n然后点击开始连接。'},
    'waEmployees':        {'en': 'AGENTS',                       'zh': '代理'},
    'waNoEmployees':      {'en': 'No employees yet',             'zh': '暂无员工'},
    'waCreateEmployee':   {'en': 'Create Employee',              'zh': '创建员工'},
    'waSearchAgents':     {'en': 'Search agents...',             'zh': '搜索代理...'},
    'waNoAgents':         {'en': 'No agents found.\nStart a wenzagent server to see agents here.', 'zh': '未找到代理。\n启动 wenzagent 服务器以在此查看代理。'},
    'waNoMatching':       {'en': 'No matching agents',           'zh': '无匹配的代理'},
    'waName':             {'en': 'Name',                         'zh': '名称'},
    'waDescription':      {'en': 'Description',                  'zh': '描述'},
    'waDescHint':         {'en': 'Describe what this agent does...', 'zh': '描述此代理的功能...'},
    'waSelectProfile':    {'en': r'Select Profile for "${agent.name}"', 'zh': r'为"${agent.name}"选择配置'},
    'waDeleteEmployee':   {'en': 'Delete Employee',              'zh': '删除员工'},
    'waDeleteConfirm':    {'en': r'Delete "${emp.name}"? This cannot be undone.', 'zh': r'删除"${emp.name}"？此操作不可撤销。'},
    'waDeleteSession':    {'en': 'Delete Chat Session',          'zh': '删除会话'},
    'waDeleteSessionConfirm': {'en': 'Delete this chat session? The employee will not be deleted.', 'zh': '删除此聊天会话？员工不会被删除。'},
    'waEmptyHint':        {'en': 'Create an AI employee to get started', 'zh': '创建 AI 员工以开始使用'},
    'waEmptySub':         {'en': 'Messages are routed through the WenzAgent LAN network', 'zh': '消息通过 WenzAgent LAN 网络路由'},
    'waSendMessage':      {'en': 'Send message to agent...',     'zh': '发送消息给代理...'},
    'cancel':       {'en': 'Cancel',       'zh': '取消'},
    'save':         {'en': 'Save',         'zh': '保存'},
    'create':       {'en': 'Create',       'zh': '创建'},
    'delete':       {'en': 'Delete',       'zh': '删除'},
    'reset':        {'en': 'Reset',        'zh': '重置'},
    'resetAll':     {'en': 'Reset All',    'zh': '全部重置'},
    'close':        {'en': 'Close',        'zh': '关闭'},
    'load':         {'en': 'Load',         'zh': '加载'},
    'preferences':  {'en': 'Preferences',  'zh': '偏好设置'},
    'aiSection':    {'en': 'AI',           'zh': 'AI'},
    'dataSection':  {'en': 'Data',         'zh': '数据'},
    'networkSection':{'en': 'Network',     'zh': '网络'},
    'systemSection':{'en': 'System',       'zh': '系统'},
    'appearance':   {'en': 'Appearance',   'zh': '外观'},
    'general':      {'en': 'General',      'zh': '通用'},
    'aiConfig':     {'en': 'AI Config',    'zh': 'AI 配置'},
    'mcpConfig':    {'en': 'MCP Config',   'zh': 'MCP 配置'},
    'permissions':  {'en': 'Permissions',  'zh': '权限'},
    'lan':          {'en': 'LAN',          'zh': '局域网'},
    'devices':      {'en': 'Devices',      'zh': '设备'},
    'devicesOnline': {'en': 'online',       'zh': '在线'},
    'noDevicesOnline': {'en': 'No devices online', 'zh': '暂无在线设备'},
    'notSet':       {'en': 'Not set',      'zh': '未设定'},
    'deviceTypeLabel': {'en': 'Device Type', 'zh': '设备类型'},
    'deviceTypeDesktop': {'en': 'Desktop',  'zh': '桌面端'},
    'deviceTypeMobile': {'en': 'Mobile',    'zh': '移动端'},
    'devicePlatform': {'en': 'Platform',    'zh': '平台'},
    'deviceOs':     {'en': 'OS',           'zh': '操作系统'},
    'deviceIp':     {'en': 'IP Address',   'zh': 'IP 地址'},
    'deviceConnectedAt': {'en': 'Connected At', 'zh': '连接时间'},
    'deviceIdLabel': {'en': 'Device ID',    'zh': '设备 ID'},
    'deviceConfig': {'en': 'Device Config', 'zh': '设备配置'},
    'deviceNameLabel': {'en': 'Device Name', 'zh': '设备名称'},
    'privacy':      {'en': 'Privacy',      'zh': '隐私'},
    'privacyTitle': {'en': 'Privacy',      'zh': '隐私'},
    'privacySubtitle': {'en': 'Manage cache and data privacy settings.', 'zh': '管理缓存和数据隐私设置。'},
    'privacyClearCache': {'en': 'Clear MultiAgent Cache', 'zh': '清除MultiAgent缓存'},
    'privacyClearCacheDesc': {'en': 'Clear all employee and session cache data.', 'zh': '清除员工及会话缓存数据。'},
    'privacyClearCacheConfirm': {'en': 'This will clear all employee and session cache data. This cannot be undone.', 'zh': '将清除所有员工及会话缓存数据，此操作不可撤销。'},
    'privacyCacheCleared': {'en': 'MultiAgent cache cleared.', 'zh': 'MultiAgent缓存已清除。'},
    'privacyClearCacheButton': {'en': 'Clear Cache', 'zh': '清除缓存'},
    'logs':         {'en': 'Logs',         'zh': '日志'},
    'about':        {'en': 'About',        'zh': '关于'},
    'sync':         {'en': 'Sync',         'zh': '同步'},
    'storage':      {'en': 'Storage',      'zh': '存储'},
    'files':        {'en': 'Files',        'zh': '文件'},
    'comingSoon':   {'en': 'coming soon',  'zh': '即将推出'},
    'logTitle':         {'en': 'System Logs',                        'zh': '系统日志'},
    'logSubtitle':      {'en': 'View, search, export and clear diagnostic logs.', 'zh': '查看、搜索、导出和清除诊断日志。'},
    'logSearch':        {'en': 'Search logs...',                     'zh': '搜索日志...'},
    'logAll':           {'en': 'All',                                'zh': '全部'},
    'logExport':        {'en': 'Export',                             'zh': '导出日志'},
    'logClear':         {'en': 'Clear',                              'zh': '清空日志'},
    'logClearConfirm':  {'en': 'Clear all logs? This cannot be undone.', 'zh': '清空所有日志？此操作不可撤销。'},
    'logCount':         {'en': r'Total: $count logs',                'zh': r'共 $count 条日志'},
    'logEmpty':         {'en': 'No Logs',                            'zh': '暂无日志'},
    'logEmptyHint':     {'en': 'When the system runs, diagnostic entries will appear here.', 'zh': '系统运行后，诊断条目将出现在此处。'},
    'logLevel':         {'en': 'Level',                              'zh': '级别'},
    'logModule':        {'en': 'Module',                             'zh': '模块'},
    'logMessage':       {'en': 'Message',                            'zh': '消息'},
    'logStackTrace':    {'en': 'Stack Trace',                        'zh': '堆栈跟踪'},
    'logExported':      {'en': 'Logs exported.',                     'zh': '日志已导出。'},
    'logExportFailed':  {'en': 'Export failed.',                     'zh': '导出失败。'},
    'logTime':          {'en': 'Time',                               'zh': '时间'},
    'mcpTitle':         {'en': 'MCP Server Config',                  'zh': 'MCP 服务器配置'},
    'mcpSubtitle':      {'en': 'Manage MCP (Model Context Protocol) server connections and tools.', 'zh': '管理 MCP（模型上下文协议）服务器连接和工具。'},
    'mcpRunning':       {'en': 'Running',                            'zh': '运行中'},
    'mcpStopped':       {'en': 'Stopped',                            'zh': '已停止'},
    'mcpStart':         {'en': 'Start Service',                      'zh': '启动服务'},
    'mcpStop':          {'en': 'Stop Service',                       'zh': '停止服务'},
    'mcpEditConfig':    {'en': 'Edit Config',                        'zh': '编辑配置'},
    'mcpHost':          {'en': 'Host',                               'zh': '主机'},
    'mcpPort':          {'en': 'Port',                               'zh': '端口'},
    'mcpConfigJson':    {'en': 'Configuration',                      'zh': '配置'},
    'mcpConfigHint':    {'en': 'Paste MCP server config JSON here',  'zh': '在此粘贴 MCP 服务器配置 JSON'},
    'mcpSaveConfig':    {'en': 'Save Config',                        'zh': '保存配置'},
    'mcpNoServers':     {'en': 'No MCP servers configured yet.',     'zh': '尚未配置 MCP 服务器。'},
    'mcpAddServer':     {'en': 'Add MCP Server',                     'zh': '添加 MCP 服务器'},
    'permTitle':        {'en': 'Global Permissions',                 'zh': '全局权限'},
    'permSubtitle':     {'en': 'Control which tools agents are allowed to use and set validation rules.', 'zh': '控制代理可使用的工具并设置校验规则。'},
    'permEnabled':      {'en': 'Enabled',                            'zh': '已启用'},
    'permDisabled':     {'en': 'Disabled',                           'zh': '已禁用'},
    'permAddRule':      {'en': 'Add Rule',                           'zh': '添加规则'},
    'permDeleteRule':   {'en': 'Delete Rule',                        'zh': '删除规则'},
    'permRulePattern':  {'en': 'Match Pattern (RegExp)',             'zh': '匹配模式（正则表达式）'},
    'permRuleDesc':     {'en': 'Rule Description',                   'zh': '规则描述'},
    'permRuleType':     {'en': 'Rule Type',                          'zh': '规则类型'},
    'permRuleAllow':    {'en': 'Allow',                              'zh': '允许'},
    'permRuleDeny':     {'en': 'Deny',                               'zh': '禁止'},
    'permPatternHint':  {'en': 'e.g. *.dart, /workspace/.*',         'zh': '例如 *.dart, /workspace/.*'},
    'permDescHint':     {'en': 'Describe what this rule matches',    'zh': '描述此规则的匹配条件'},
    'permFileRead':     {'en': 'File Read',                          'zh': '文件读取'},
    'permFileReadDesc': {'en': 'Allow reading any file',             'zh': '允许读取任何文件'},
    'permFileWrite':    {'en': 'File Write',                         'zh': '文件写入'},
    'permFileWriteDesc':{'en': 'Allow modifying any file',           'zh': '允许修改任何文件'},
    'permFileDelete':   {'en': 'File Delete',                        'zh': '文件删除'},
    'permFileDeleteDesc':{'en': 'Allow deleting any file',           'zh': '允许删除任何文件'},
    'permFilePatch':    {'en': 'File Patch',                         'zh': '文件补丁'},
    'permFilePatchDesc':{'en': 'Allow patching files',               'zh': '允许对文件进行补丁修改'},
    'permDirCreate':    {'en': 'Directory Create',                   'zh': '目录创建'},
    'permDirCreateDesc':{'en': 'Allow creating any directory',       'zh': '允许创建任何目录'},
    'permCmdExec':      {'en': 'Command Execute',                    'zh': '命令执行'},
    'permCmdExecDesc':  {'en': 'Allow executing any command',        'zh': '允许执行任何命令'},
    'permBgCmd':        {'en': 'Background Command',                 'zh': '后台命令'},
    'permBgCmdDesc':    {'en': 'Allow executing background commands','zh': '允许执行后台命令'},
    'permGitOps':       {'en': 'Git Operations',                     'zh': 'Git 操作'},
    'permGitOpsDesc':   {'en': 'Allow Git related operations',       'zh': '允许执行 Git 相关操作'},
    'permDocRead':      {'en': 'Document Read',                      'zh': '文档读取'},
    'permDocReadDesc':  {'en': 'Allow reading any document',         'zh': '允许读取任何文档'},
    'permDocWrite':     {'en': 'Document Write',                     'zh': '文档写入'},
    'permDocWriteDesc': {'en': 'Allow modifying any document',       'zh': '允许修改任何文档'},
    'permTaskRead':     {'en': 'Task Read',                          'zh': '任务读取'},
    'permTaskReadDesc': {'en': 'Allow reading any task',             'zh': '允许读取任何任务'},
    'permTaskWrite':    {'en': 'Task Write',                         'zh': '任务写入'},
    'permTaskWriteDesc':{'en': 'Allow modifying any task',           'zh': '允许修改任何任务'},
    'dataFilesTitle':   {'en': 'File Access',                        'zh': '文件访问'},
    'dataFilesSubtitle':{'en': 'Manage folders accessible to agents.', 'zh': '管理代理可访问的文件夹。'},
    'dataFilesOpenDir': {'en': 'Open Folder',                        'zh': '打开文件夹'},
    'dataFilesEmpty':   {'en': 'No accessible folders configured.',  'zh': '未配置可访问的文件夹。'},
    'dataStorageTitle': {'en': 'Storage',                            'zh': '存储空间'},
    'dataStorageSubtitle':{'en': 'View storage usage and manage files.', 'zh': '查看存储占用并管理文件。'},
    'dataStorageSpace': {'en': 'Disk Usage',                         'zh': '空间占用'},
    'dataStorageFiles': {'en': 'Associated Files',                   'zh': '关联文件数'},
    'dataStorageManage':{'en': 'Manage Files',                       'zh': '管理文件'},
    'dataStorageOpen':  {'en': 'Open Storage Folder',                'zh': '打开存储目录'},
    'skills':           {'en': 'Skills',                             'zh': '技能'},
    'skillAdd':         {'en': 'Add Skill',                          'zh': '添加技能'},
    'skillAddTitle':    {'en': 'Add Skill',                          'zh': '添加技能'},
    'skillName':        {'en': 'Skill Name',                         'zh': '技能名称'},
    'skillNameHint':    {'en': 'Enter skill name',                   'zh': '输入技能名称'},
    'skillDesc':        {'en': 'Description',                        'zh': '描述'},
    'skillDescHint':    {'en': 'Brief description of the skill',     'zh': '技能的简要描述'},
    'skillFolderPath':  {'en': 'Skill Folder Path',                 'zh': '技能文件夹路径'},
    'skillFolderHint':  {'en': 'Folder must contain SKILL.md',      'zh': '文件夹中需包含 SKILL.md'},
    'skillBrowse':      {'en': 'Browse',                             'zh': '浏览'},
    'skillSelectFolder':{'en': 'Select Folder',                      'zh': '选择文件夹'},
    'skillSelectZip':   {'en': 'From ZIP Archive',                   'zh': '从压缩包导入'},
    'skillSearchFolder':{'en': 'Search folders...',                  'zh': '搜索文件夹...'},
    'skillEnabled':     {'en': 'Enabled',                            'zh': '已启用'},
    'skillDisabled':    {'en': 'Disabled',                           'zh': '已禁用'},
    'skillDelete':      {'en': 'Delete Skill',                       'zh': '删除技能'},
    'skillDeleteConfirm':{'en': r'Delete skill "${name}"? This cannot be undone.', 'zh': r'删除技能"${name}"？此操作不可撤销。'},
    'skillModify':      {'en': 'Modify',                             'zh': '修改'},
    'skillConfig':      {'en': 'Configuration',                      'zh': '配置'},
    'skillInfo':        {'en': 'Information',                        'zh': '信息'},
    'skillId':          {'en': 'Skill ID',                           'zh': '技能 ID'},
    'skillType':        {'en': 'Type',                               'zh': '类型'},
    'skillCreatedAt':   {'en': 'Created',                            'zh': '创建时间'},
    'skillUpdatedAt':   {'en': 'Updated',                            'zh': '更新时间'},
    'skillNoSkills':    {'en': 'No skills yet.\\nClick + to add a skill.', 'zh': '暂无技能。\\n点击 + 添加技能。'},
    'skillConfirm':     {'en': 'Confirm',                            'zh': '确认'},
  };
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'zh'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(covariant _AppLocalizationsDelegate old) => false;
}
