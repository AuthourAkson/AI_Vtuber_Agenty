import 'package:flutter/material.dart';

/// Lightweight localization for AI VTuber Agent.
/// Supports en, zh-CN, zh-TW. Add new strings here as needed.
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

  // ─── String keys ────────────────────────────────────────

  String get appTitle => _t('appTitle');
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
  String get chatNewSession => _t('chatNewSession');
  String get chatSessions => _t('chatSessions');
  String get chatStartConversation => _t('chatStartConversation');
  String get chatSettings => _t('chatSettings');
  String get memoryTitle => _t('memoryTitle');
  String get memorySubtitle => _t('memorySubtitle');
  String get memorySearch => _t('memorySearch');
  String get memoryEmpty => _t('memoryEmpty');
  String get memoryNoResults => _t('memoryNoResults');
  String get generalTitle => _t('generalTitle');
  String get generalSubtitle => _t('generalSubtitle');
  String get generalAutoOpen => _t('generalAutoOpen');
  String get generalAutoOpenDesc => _t('generalAutoOpenDesc');
  String get generalLanguage => _t('generalLanguage');
  String get generalLanguageDesc => _t('generalLanguageDesc');

  // ─── Lookup ─────────────────────────────────────────────

  String _t(String key) => _strings[key]?[locale.languageCode] ??
      _strings[key]?['en'] ?? key;

  static const _strings = <String, Map<String, String>>{
    'appTitle': {'en': 'AI VTuber Agent', 'zh': 'AI 虚拟主播代理'},
    'sidebarHome': {'en': 'Home', 'zh': '首页'},
    'sidebarInput': {'en': 'Input', 'zh': '输入'},
    'sidebarCharacter': {'en': 'Character', 'zh': '角色'},
    'sidebarVision': {'en': 'Vision', 'zh': '视觉'},
    'sidebarTTS': {'en': 'TTS', 'zh': '语音'},
    'sidebarMemory': {'en': 'Memory', 'zh': '记忆'},
    'sidebarStream': {'en': 'Stream', 'zh': '直播'},
    'sidebarPipeline': {'en': 'Pipeline', 'zh': '流水线'},
    'sidebarSettings': {'en': 'Settings', 'zh': '设置'},
    'sidebarAgents': {'en': 'Agents', 'zh': '代理'},
    'chatNewSession': {'en': 'New Session', 'zh': '新建会话'},
    'chatSessions': {'en': 'Sessions', 'zh': '会话列表'},
    'chatStartConversation': {'en': 'Start a conversation', 'zh': '开始对话'},
    'chatSettings': {'en': 'Settings', 'zh': '设置'},
    'memoryTitle': {'en': 'Chat Sessions', 'zh': '聊天会话'},
    'memorySubtitle': {'en': 'Manage and review your conversation sessions', 'zh': '管理和查看您的对话会话'},
    'memorySearch': {'en': 'Search sessions...', 'zh': '搜索会话...'},
    'memoryEmpty': {'en': 'Memory Empty', 'zh': '记忆为空'},
    'memoryNoResults': {'en': 'No sessions found', 'zh': '未找到会话'},
    'generalTitle': {'en': 'General Preferences', 'zh': '通用设置'},
    'generalSubtitle': {'en': 'Behaviour and language settings.', 'zh': '行为和语言设置。'},
    'generalAutoOpen': {'en': 'Auto-open last page on startup', 'zh': '启动时自动打开上次的页面'},
    'generalAutoOpenDesc': {'en': 'Restore the last active page when the app starts', 'zh': '应用启动时恢复上次打开的页面'},
    'generalLanguage': {'en': 'Language', 'zh': '语言'},
    'generalLanguageDesc': {'en': 'Select the UI display language', 'zh': '选择界面显示语言'},
  };
}

// ════════════════════════════════════════════════════════════

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
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
