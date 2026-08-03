import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';
import '../providers/multi_agent_provider.dart';
import '../services/project_summary_service.dart';
import '../widgets/md_title_bar.dart';
import '../widgets/md_file_sidebar.dart';
import '../widgets/md_markdown_editor.dart';
import '../widgets/md_ai_task_panel.dart';
import '../widgets/md_bottom_status_bar.dart';

/// wenzmark 风格 MarkdownText IDE（AppShell）。
///
/// 五段式布局：
/// ┌─────────────────────────────────────────────┐
/// │              顶部菜单栏 (35px)               │
/// ├──────────┬──────────────────┬───────────────┤
/// │ 文件树    │   Markdown 编辑区  │  AI 任务中心   │
/// │ ~22%     │      ~40%         │   ~38%       │
/// ├──────────┴──────────────────┴───────────────┤
/// │              底部状态栏 (24px)               │
/// └─────────────────────────────────────────────┘
class MarkdownTextScreen extends StatefulWidget {
  const MarkdownTextScreen({super.key});

  @override
  State<MarkdownTextScreen> createState() => _MarkdownTextScreenState();
}

class _MarkdownTextScreenState extends State<MarkdownTextScreen> {
  final ProjectSummaryService _svc = ProjectSummaryService();
  final TextEditingController _editorCtrl = TextEditingController();

  // ── 项目状态 ──
  String? _projectRoot;
  bool _projectLoading = true;

  // ── 文件树状态 ──
  List<SummaryNode> _tree = [];
  bool _treeLoading = true;
  String _fileSearch = '';

  // ── 编辑器状态 ──
  final List<MdOpenTab> _tabs = [];
  String? _activeTabPath;
  bool _previewMode = false;
  int _tabIndex = 0; // 返回/前进导航

  // ── AI 任务状态 ──
  final List<MdTask> _tasks = [];
  String? _selectedEmployeeId;
  MdTaskExecutor _executor = MdTaskExecutor.employee;
  String? _selectedProviderName;

  // CLI 任务日志 setState 节流（text_delta 每秒可达几十次）
  DateTime? _lastCliLogFlush;

  // ── 面板宽度（可拖拽，持久化）──
  static const _leftMin = 220.0, _leftMax = 560.0;
  static const _rightMin = 300.0, _rightMax = 720.0;
  static const _middleMin = 360.0;
  double _leftWidth = 350;
  double _rightWidth = 440;

  // AI 右侧面板显隐（标题栏 AI 按钮切换）
  bool _showAiPanel = true;
  // HTML 预览刷新信号（保存成功后 +1，触发 WebView 重载）
  int _htmlReloadTick = 0;

  @override
  void initState() {
    super.initState();
    _loadProjectRoot();
    _loadPanelWidths();
    _loadPersistedUiState();
    _editorCtrl.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _editorCtrl.removeListener(_onEditorChanged);
    _editorCtrl.dispose();
    super.dispose();
  }

  // ─── 状态持久化（切页后 State 销毁重建，靠 SharedPreferences 恢复）───
  //
  // 根因：home_screen._buildPage 每次切页都 new MarkdownTextScreen()，
  // 离开页面时 State 销毁，_showAiPanel/_tabs/_previewMode 全部重置。
  // 这里把 UI 开关与打开的 Tab 列表持久化，重新进入自动恢复。

  /// 恢复与项目根无关的 UI 开关（AI 面板、预览模式、执行器、服务商）。
  Future<void> _loadPersistedUiState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _showAiPanel = prefs.getBool('md_ai_panel_visible') ?? true;
      _previewMode = prefs.getBool('md_preview_mode') ?? false;
      _executor = MdTaskExecutor.fromKey(prefs.getString('md_executor') ?? '');
      _selectedProviderName = prefs.getString('md_provider_name');
    });
  }

  /// 项目根就绪后恢复上次打开的 Tab 列表与激活 Tab。
  Future<void> _restoreTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTabs = prefs.getStringList('md_open_tabs') ?? const [];
    if (savedTabs.isEmpty || !mounted) return;

    // 并行读文件内容；失败（文件已被删）的跳过
    final results = await Future.wait<({String path, String? content})>(
      savedTabs.map((p) async {
        try {
          return (path: p, content: await _svc.readFile(p));
        } catch (_) {
          return (path: p, content: null as String?);
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      for (final r in results) {
        if (r.content == null) continue;
        _tabs.add(MdOpenTab(
          path: r.path,
          title: r.path.split('/').last,
          content: r.content!,
          original: r.content!,
          fileUri: _svc.absoluteFileUri(r.path),
        ));
      }
    });

    // 恢复激活 Tab
    final active = prefs.getString('md_active_tab') ?? '';
    if (mounted && active.isNotEmpty) {
      final idx = _tabs.indexWhere((t) => t.path == active);
      if (idx >= 0) {
        setState(() {
          _activeTabPath = active;
          _tabIndex = idx;
        });
        _editorCtrl.text = _tabs[idx].content;
      }
    }
  }

  /// 持久化当前 UI 状态（AI 面板开关/预览模式/打开的 Tab/激活 Tab/执行器/服务商）。
  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('md_ai_panel_visible', _showAiPanel);
    await prefs.setBool('md_preview_mode', _previewMode);
    await prefs.setStringList('md_open_tabs', [for (final t in _tabs) t.path]);
    await prefs.setString('md_active_tab', _activeTabPath ?? '');
    await prefs.setString('md_executor', _executor.key);
    await prefs.setString('md_provider_name', _selectedProviderName ?? '');
  }

  void _onEditorChanged() {
    final tab = _activeTab;
    if (tab == null) return;
    final text = _editorCtrl.text;
    if (text != tab.content) {
      tab.content = text;
      if (mounted) setState(() {});
    }
  }

  // ─── 项目 ─────────────────────────────────────────

  Future<void> _loadProjectRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('markdown_project_root');
    if (saved != null && saved.isNotEmpty) {
      _svc.setProjectRoot(saved);
      if (mounted) {
        setState(() {
          _projectRoot = saved;
          _projectLoading = false;
        });
        await _loadTree();
        await _restoreTabs(); // 项目根就绪后恢复上次打开的 Tab
      }
    } else {
      if (mounted) setState(() => _projectLoading = false);
    }
  }

  // ── 面板宽度持久化 ──

  Future<void> _loadPanelWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble('md_left_width');
    final right = prefs.getDouble('md_right_width');
    if (mounted) {
      setState(() {
        if (left != null && left >= _leftMin && left <= _leftMax) {
          _leftWidth = left;
        }
        if (right != null && right >= _rightMin && right <= _rightMax) {
          _rightWidth = right;
        }
      });
    }
  }

  Future<void> _savePanelWidths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('md_left_width', _leftWidth);
    await prefs.setDouble('md_right_width', _rightWidth);
  }

  Future<void> _pickProjectFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: AppLocalizations.of(context).mdSelectProject,
    );
    if (result == null || result.isEmpty) return;

    setState(() {
      _projectRoot = result;
      _tabs.clear();
      _activeTabPath = null;
      _editorCtrl.clear();
    });

    _svc.setProjectRoot(result);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('markdown_project_root', result);
    await _loadTree();
    await _persistState(); // 切换项目后清空旧 Tab 持久化
  }

  // ─── 文件树 ───────────────────────────────────────

  Future<void> _loadTree() async {
    if (_projectRoot == null) return;
    setState(() => _treeLoading = true);
    try {
      final tree = await _svc.buildTree();
      if (mounted) {
        setState(() {
          _tree = _filterTree(tree, _fileSearch);
          _treeLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _treeLoading = false);
      }
    }
  }

  List<SummaryNode> _filterTree(List<SummaryNode> nodes, String query) {
    if (query.isEmpty) return nodes;
    final q = query.toLowerCase();
    final result = <SummaryNode>[];
    for (final node in nodes) {
      if (node.isDirectory) {
        final children = _filterTree(node.children, query);
        if (children.isNotEmpty || node.name.toLowerCase().contains(q)) {
          result.add(SummaryNode(
            name: node.name,
            relativePath: node.relativePath,
            isDirectory: true,
            children: children,
          ));
        }
      } else {
        if (node.name.toLowerCase().contains(q)) result.add(node);
      }
    }
    return result;
  }

  void _onFileSearch(String query) {
    _fileSearch = query;
    setState(() => _tree = _filterTree(_tree, query));
  }

  // ─── Tab / 编辑器 ─────────────────────────────────

  MdOpenTab? get _activeTab {
    if (_activeTabPath == null) return null;
    for (final t in _tabs) {
      if (t.path == _activeTabPath) return t;
    }
    return null;
  }

  Future<void> _openFile(String relativePath) async {
    // 已打开则直接切换
    for (final t in _tabs) {
      if (t.path == relativePath) {
        setState(() => _activeTabPath = relativePath);
        _editorCtrl.text = t.content;
        _editorCtrl.selection = TextSelection.collapsed(offset: 0);
        _persistState(); // 激活 Tab 变化
        return;
      }
    }

    final content = await _svc.readFile(relativePath);
    final tab = MdOpenTab(
      path: relativePath,
      title: relativePath.split('/').last,
      content: content,
      original: content,
      fileUri: _svc.absoluteFileUri(relativePath),
    );
    if (mounted) {
      setState(() {
        _tabs.add(tab);
        _activeTabPath = relativePath;
        _tabIndex = _tabs.length - 1;
      });
      _editorCtrl.text = content;
    }
    _persistState(); // Tab 列表变化
  }

  void _closeTab(String path) async {
    final idx = _tabs.indexWhere((t) => t.path == path);
    if (idx < 0) return;
    final closing = _tabs[idx];
    // 自动保存未保存的修改（wenzmark 风格：状态栏提示未保存，关闭即保存）
    if (closing.isDirty) {
      try {
        await _svc.writeFile(closing.path, closing.content);
      } catch (_) {}
    }
    final wasActive = _activeTabPath == path;

    setState(() {
      _tabs.removeAt(idx);
      if (wasActive) {
        _activeTabPath = _tabs.isEmpty ? null : _tabs[idx < _tabs.length ? idx : idx - 1].path;
        _tabIndex = _tabs.isEmpty ? 0 : (idx < _tabs.length ? idx : _tabs.length - 1);
      }
    });
    if (wasActive) {
      final tab = _activeTab;
      _editorCtrl.text = tab?.content ?? '';
    }
    _persistState(); // Tab 列表变化
  }

  Future<void> _saveActiveTab() async {
    final tab = _activeTab;
    if (tab == null || !tab.isDirty) return;
    try {
      await _svc.writeFile(tab.path, tab.content);
      tab.original = tab.content;
      if (mounted) {
        setState(() {
          _htmlReloadTick++; // HTML 预览模式下保存后自动刷新
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mdSaved), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context).mdSaveFailed}: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _goTab(int delta) {
    if (_tabs.isEmpty) return;
    final target = (_tabIndex + delta).clamp(0, _tabs.length - 1);
    if (target == _tabIndex) return;
    setState(() {
      _tabIndex = target;
      _activeTabPath = _tabs[target].path;
    });
    _editorCtrl.text = _tabs[target].content;
  }

  Future<void> _createFile() async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final theme = MdIdeTheme.of(ctx);
        return AlertDialog(
          backgroundColor: theme.card,
          title: Text(l10n.mdNewFile, style: TextStyle(color: theme.foreground)),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TextStyle(color: theme.foreground),
            decoration: InputDecoration(
              hintText: l10n.mdFileNameHint,
              hintStyle: TextStyle(color: theme.faint),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: Text(l10n.create),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await _svc.createFile('', result);
      await _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _createFolder() async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final theme = MdIdeTheme.of(ctx);
        return AlertDialog(
          backgroundColor: theme.card,
          title: Text(l10n.mdNewFolder, style: TextStyle(color: theme.foreground)),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TextStyle(color: theme.foreground),
            decoration: InputDecoration(
              hintText: l10n.mdFolderNameHint,
              hintStyle: TextStyle(color: theme.faint),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: Text(l10n.create),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty) return;
    try {
      await _svc.createDirectory('', result);
      await _loadTree();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  // ─── AI 任务 ──────────────────────────────────────

  /// 标题栏"文档"按钮：打开项目 README.md（存在时）。
  Future<void> _openReadme() async {
    if (_projectRoot == null) {
      // 还没选项目：提示并直接拉起项目选择器
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).mdNoProjectToast),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _pickProjectFolder();
      return;
    }
    try {
      if (await _svc.exists('README.md')) {
        await _openFile('README.md');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mdNoReadme), duration: const Duration(seconds: 2)),
        );
      }
    } catch (_) {}
  }

  static const _projectSummaryConvention = '''
# Project Documentation Convention (project-summary/)

Every project you work on MUST maintain a structured documentation directory at:
  <project-root>/project-summary/

Directory structure:
  project-summary/
  ├── README.md           # Project overview with quick links
  ├── architecture/       # Architecture decisions, data flow, tech stack
  ├── screens/            # One doc per UI screen
  ├── services/           # One doc per backend service
  ├── widgets/            # Reusable components
  ├── models/             # Data model docs
  └── providers/          # State management docs

Rules:
- Each .md file describes ONE component (screen/service/widget/model)
- Include: file path, overview, key components, related files
- When creating a new project, scaffold this structure automatically
- When modifying code, update the corresponding .md file
- Keep README.md up to date as the navigation hub
''';

  Future<void> _submitTask(String prompt) async {
    if (_projectRoot == null) return;

    // ── CLI 执行器（Claude Code / Codex）：外接独立 CLI 运行 ──
    if (_executor != MdTaskExecutor.employee) {
      final mgr = context.read<AgentManager>();
      final profile = _resolveProvider(mgr);
      if (profile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).mdNoProviderToast)),
          );
        }
        return;
      }
      final task = MdTask(
        id: 'task-${DateTime.now().millisecondsSinceEpoch}',
        title: prompt.length > 40 ? '${prompt.substring(0, 40)}...' : prompt,
        status: MdTaskStatus.waiting,
        projectPath: _projectRoot!,
        executor: _executor,
        providerName: profile.name,
        model: _executor == MdTaskExecutor.claudeCli ? 'Claude Code CLI' : 'Codex CLI',
        prompt: prompt,
      );
      setState(() => _tasks.insert(0, task));
      _runCliTask(task, prompt, profile);
      return;
    }

    // ── 员工执行器：发送给 MultiAgent 员工 ──
    final mgr = context.read<AgentManager>();
    if (mgr.employees.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mdNoEmployeeToast)),
        );
      }
      return;
    }

    // 确定目标员工
    final employee = _selectedEmployeeId != null
        ? mgr.employees.firstWhere(
            (e) => e.uuid == _selectedEmployeeId,
            orElse: () => mgr.employees.first,
          )
        : mgr.employees.first;
    _selectedEmployeeId ??= employee.uuid;

    // 创建任务卡片（waiting）
    final task = MdTask(
      id: 'task-${DateTime.now().millisecondsSinceEpoch}',
      title: prompt.length > 40 ? '${prompt.substring(0, 40)}...' : prompt,
      status: MdTaskStatus.waiting,
      projectPath: _projectRoot!,
      employeeId: employee.uuid,
      prompt: prompt,
    );
    setState(() => _tasks.insert(0, task));

    // 执行任务
    _runTask(task, prompt, employee);
  }

  /// 按名称解析当前选中的 AI 服务商（MultiAgent Settings 配置）。
  ProviderProfile? _resolveProvider(AgentManager mgr) {
    if (mgr.providerProfiles.isEmpty) return null;
    if (_selectedProviderName != null) {
      for (final p in mgr.providerProfiles) {
        if (p.name == _selectedProviderName) return p;
      }
    }
    return mgr.providerProfiles.first;
  }

  void _onExecutorChanged(MdTaskExecutor executor) {
    setState(() => _executor = executor);
    _persistState();
  }

  void _onProviderChanged(String name) {
    setState(() => _selectedProviderName = name);
    _persistState();
  }

  Future<void> _runTask(MdTask task, String prompt, AgentModel employee) async {
    setState(() => task.status = MdTaskStatus.running);

    // 构造上下文 prompt
    final buffer = StringBuffer();
    buffer.writeln('[MarkdownText Task]');
    buffer.writeln('Project: ${task.projectPath}');
    buffer.writeln();
    buffer.writeln(_projectSummaryConvention);
    buffer.writeln();

    final tab = _activeTab;
    if (tab != null) {
      buffer.writeln('Current file: ${tab.path}');
      buffer.writeln();
      buffer.writeln('```markdown');
      buffer.writeln(tab.content);
      buffer.writeln('```');
      buffer.writeln();
    } else {
      buffer.writeln('(No file currently open — the user is browsing the project docs.)');
      buffer.writeln();
    }

    buffer.writeln('User request:');
    buffer.writeln(prompt);

    try {
      final mgr = context.read<AgentManager>();
      await mgr.openAgent(employee.uuid, employee.name);
      await mgr.sendMessage(buffer.toString());
      if (mounted) {
        setState(() {
          task.status = MdTaskStatus.completed;
          task.error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          task.status = MdTaskStatus.failed;
          task.error = '$e';
        });
      }
    }
  }

  // ─── CLI 执行器（Claude Code CLI）──────────────────────

  /// 构造任务上下文 prompt（与员工路径一致的 convention + 当前文件）。
  String _buildTaskPrompt(MdTask task, String prompt) {
    final buffer = StringBuffer();
    buffer.writeln('[MarkdownText Task]');
    buffer.writeln('Project: ${task.projectPath}');
    buffer.writeln();
    buffer.writeln(_projectSummaryConvention);
    buffer.writeln();

    final tab = _activeTab;
    if (tab != null) {
      buffer.writeln('Current file: ${tab.path}');
      buffer.writeln();
      buffer.writeln('```markdown');
      buffer.writeln(tab.content);
      buffer.writeln('```');
      buffer.writeln();
    } else {
      buffer.writeln('(No file currently open — the user is browsing the project docs.)');
      buffer.writeln();
    }

    buffer.writeln('User request:');
    buffer.writeln(prompt);
    return buffer.toString();
  }

  /// 启动外部 CLI（claude -p）运行任务，stream-json 输出实时写进任务卡片。
  ///
  /// prompt 经 stdin 管道传入（Windows cmd 命令行有 8KB 长度限制）；
  /// 环境变量把所选 AI 服务商注入 claude（ANTHROPIC_BASE_URL/AUTH_TOKEN）。
  Future<void> _runCliTask(MdTask task, String prompt, ProviderProfile profile) async {
    setState(() {
      task.status = MdTaskStatus.running;
      task.transcript = '▶ ${task.model} · ${profile.name}\n';
    });

    final contextPrompt = _buildTaskPrompt(task, prompt);
    final tmpFile = File('${Directory.systemTemp.path}/md_cli_prompt_${task.id}.txt');
    try {
      await tmpFile.writeAsString(contextPrompt, flush: true);
    } catch (_) {}

    // 环境：注入所选 AI 服务商 → claude 走网关而非 OAuth 登录
    final env = Map<String, String>.from(Platform.environment);
    if (profile.baseUrl.isNotEmpty && !profile.baseUrl.contains('api.anthropic.com')) {
      env['ANTHROPIC_BASE_URL'] = profile.baseUrl;
    }
    if (profile.apiKey.isNotEmpty) {
      env['ANTHROPIC_AUTH_TOKEN'] = profile.apiKey;
    }
    if (profile.model.isNotEmpty) {
      env['ANTHROPIC_SMALL_FAST_MODEL'] = profile.model;
    }
    env['DISABLE_TELEMETRY'] = '1';
    env['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1';

    final args = <String>[
      '-p',
      '--verbose',
      '--include-partial-messages',
      '--output-format', 'stream-json',
      '--max-turns', '30',
      '--permission-mode', 'bypassPermissions',
      if (profile.model.isNotEmpty) '--model', profile.model,
    ];

    Process process;
    try {
      process = await Process.start(
        'claude',
        args,
        workingDirectory: task.projectPath,
        environment: env,
        runInShell: Platform.isWindows,
      );
    } catch (e) {
      final label =
          mounted ? AppLocalizations.of(context).mdCliStartFailed : 'CLI start failed';
      _appendTaskLog(task, '\n❌ $label: $e');
      _finishCliTask(task, exitCode: -1);
      return;
    }

    // 经 stdin 传入 prompt（避免命令行长度限制）
    try {
      process.stdin.write(contextPrompt);
      await process.stdin.close();
    } catch (_) {}

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleCliLine(task, line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final t = line.trim();
      if (t.isNotEmpty) _appendTaskLog(task, '\n[stderr] $t');
    });

    final code = await process.exitCode;
    if (mounted) _finishCliTask(task, exitCode: code);

    // 清理临时 prompt 文件
    try {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
    } catch (_) {}
  }

  void _finishCliTask(MdTask task, {required int exitCode}) {
    if (task.status != MdTaskStatus.running) return;
    final ok = exitCode == 0;
    if (!mounted) {
      // State 已销毁：只落状态字段，不再 setState（避免 deactivated 崩溃）
      task.status = ok ? MdTaskStatus.completed : MdTaskStatus.failed;
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      if (ok) {
        task.status = MdTaskStatus.completed;
      } else {
        task.status = MdTaskStatus.failed;
        task.error = exitCode == -1
            ? l10n.mdCliStartFailed
            : '${l10n.mdCliExited} $exitCode';
      }
    });
  }

  /// 解析 claude stream-json 单行事件，追加到任务 transcript。
  void _handleCliLine(MdTask task, String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    Object? obj;
    try {
      obj = jsonDecode(trimmed);
    } catch (_) {
      return; // 非 JSON 行（警告等）忽略
    }
    if (obj is! Map<String, dynamic>) return;

    switch (obj['type'] as String?) {
      case 'system':
        return; // init/status 噪音
      case 'stream_event':
        final event = obj['event'] as Map<String, dynamic>?;
        if (event?['type'] == 'text_delta') {
          final delta = event?['delta'] as Map<String, dynamic>?;
          final text = delta?['text'] as String?;
          if (text != null && text.isNotEmpty) _appendTaskLog(task, text);
        }
      case 'assistant':
      case 'assistant_message':
        // 只提取工具调用块（文本已由 text_delta 实时流式追加，避免重复）
        final message = obj['message'] as Map<String, dynamic>?;
        final content = message?['content'];
        if (content is List) {
          for (final block in content) {
            if (block is Map<String, dynamic> && block['type'] == 'tool_use') {
              final name = block['name'] as String? ?? 'tool';
              final input = block['input'];
              final inputStr = input == null ? '' : jsonEncode(input);
              final shown = inputStr.length > 160
                  ? '${inputStr.substring(0, 160)}…'
                  : inputStr;
              _appendTaskLog(task, '\n⚙ $name $shown');
            }
          }
        }
      case 'result':
        final isError = obj['is_error'] == true;
        final result = obj['result'];
        if (result is String && result.isNotEmpty) {
          _appendTaskLog(task, '\n${isError ? '❌' : '✅'} $result');
        }
    }
  }

  /// 追加一行 CLI 输出到任务卡片；setState 节流到 ~80ms 一次。
  void _appendTaskLog(MdTask task, String chunk) {
    task.transcript += chunk;
    if (task.transcript.length > 40000) {
      task.transcript = task.transcript.substring(task.transcript.length - 40000);
    }
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastCliLogFlush != null &&
        now.difference(_lastCliLogFlush!) < const Duration(milliseconds: 80)) {
      return;
    }
    _lastCliLogFlush = now;
    setState(() {});
  }

  void _deleteTask(MdTask task) {
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
  }

  void _retryTask(MdTask task) {
    // CLI 任务：按原执行器 + 服务商重跑
    if (task.executor != MdTaskExecutor.employee) {
      final mgr = context.read<AgentManager>();
      ProviderProfile? profile;
      if (task.providerName != null) {
        for (final p in mgr.providerProfiles) {
          if (p.name == task.providerName) {
            profile = p;
            break;
          }
        }
      }
      profile ??= mgr.providerProfiles.isNotEmpty ? mgr.providerProfiles.first : null;
      if (profile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).mdNoProviderToast)),
          );
        }
        return;
      }
      task.transcript = '';
      task.error = null;
      _runCliTask(task, task.prompt ?? task.title, profile);
      return;
    }

    final mgr = context.read<AgentManager>();
    final employee = mgr.employees.firstWhere(
      (e) => e.uuid == task.employeeId,
      orElse: () => mgr.employees.first,
    );
    _runTask(task, task.prompt ?? task.title, employee);
  }

  /// 笔杆图标：编辑原始 prompt → 保存后按原执行器重新执行。
  Future<void> _editTask(MdTask task) async {
    if (task.status == MdTaskStatus.running) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).mdEditWhileRunning)),
        );
      }
      return;
    }
    final l10n = AppLocalizations.of(context);
    final promptCtrl = TextEditingController(text: task.prompt ?? task.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final theme = MdIdeTheme.of(ctx);
        return AlertDialog(
          backgroundColor: theme.card,
          title: Text(l10n.mdEditTask, style: TextStyle(color: theme.foreground)),
          content: SizedBox(
            width: 420,
            height: 180,
            child: TextField(
              controller: promptCtrl,
              autofocus: true,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(fontSize: 13, color: theme.foreground, height: 1.4),
              decoration: InputDecoration(
                filled: false, // 规避全局 InputDecorationTheme filled:true 污染
                hintText: l10n.mdPromptHint,
                hintStyle: TextStyle(fontSize: 12, color: theme.faint),
                border: OutlineInputBorder(borderSide: BorderSide(color: theme.borderSubtle)),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            TextButton(
              onPressed: () => Navigator.pop(ctx, promptCtrl.text.trim()),
              child: Text(l10n.mdSaveAndRerun),
            ),
          ],
        );
      },
    );
    if (result == null || result.isEmpty || result == task.prompt) return;

    // 更新任务内容
    task.prompt = result;
    task.title = result.length > 40 ? '${result.substring(0, 40)}...' : result;
    task.error = null;
    task.transcript = '';

    // 按原执行器重新执行
    if (task.executor != MdTaskExecutor.employee) {
      final mgr = context.read<AgentManager>();
      ProviderProfile? profile;
      if (task.providerName != null) {
        for (final p in mgr.providerProfiles) {
          if (p.name == task.providerName) {
            profile = p;
            break;
          }
        }
      }
      profile ??= mgr.providerProfiles.isNotEmpty ? mgr.providerProfiles.first : null;
      if (profile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.mdNoProviderToast)),
          );
        }
        return;
      }
      _runCliTask(task, result, profile);
    } else {
      final mgr = context.read<AgentManager>();
      final employee = mgr.employees.firstWhere(
        (e) => e.uuid == task.employeeId,
        orElse: () => mgr.employees.first,
      );
      _runTask(task, result, employee);
    }
  }

  /// 眼睛图标：弹窗查看任务完整会话（CLI 输出全文，可复制）。
  Future<void> _viewTask(MdTask task) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = MdIdeTheme.of(ctx);
        // ⚠️ 状态色必须在 builder（build 阶段）里算——MdIdeTheme.of 内部是
        // context.watch，事件处理器里调用 watch 有风险
        final (statusLabel, statusColor) = switch (task.status) {
          MdTaskStatus.running => (l10n.mdStatusRunning, theme.info),
          MdTaskStatus.failed => (l10n.mdStatusFailed, theme.error),
          MdTaskStatus.completed => (l10n.mdStatusCompleted, theme.success),
          MdTaskStatus.waiting => (l10n.mdStatusWaiting, theme.muted),
        };
        final content = task.transcript.isEmpty
            ? l10n.mdNoOutput
            : task.transcript;
        return AlertDialog(
          backgroundColor: theme.card,
          title: Row(
            children: [
              Icon(Icons.terminal, size: 16, color: theme.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: theme.foreground),
                ),
              ),
              // 状态徽章（内联实现，_StatusBadge 是 panel 文件私有类不可跨文件用）
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withAlpha(80)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(fontSize: 10, color: statusColor),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 760,
            height: 460,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 元信息行：执行器 · 服务商 · 项目路径
                Text(
                  '${task.model}'
                  '${task.providerName != null ? ' · ${task.providerName}' : ''}'
                  ' · ${task.projectPath}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: theme.muted),
                ),
                const SizedBox(height: 8),
                // 完整会话输出（等宽字体 + 可选中复制）
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.sidebar,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.borderSubtle),
                    ),
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: theme.foreground,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: task.transcript));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(l10n.mdCopied), duration: const Duration(seconds: 1)),
                  );
                }
              },
              child: Text(l10n.mdCopy),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.close)),
          ],
        );
      },
    );
  }

  Future<void> _pickEmployee() async {
    final mgr = context.read<AgentManager>();
    if (mgr.employees.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final theme = MdIdeTheme.of(ctx);
        return SimpleDialog(
          backgroundColor: theme.card,
          title: Text(l10n.mdSelectEmployee, style: TextStyle(fontSize: 14, color: theme.foreground)),
          children: mgr.employees.map((e) {
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.uuid),
              child: Row(
                children: [
                  Icon(
                    e.status == 'online' ? Icons.circle : Icons.circle_outlined,
                    size: 8,
                    color: e.status == 'online' ? theme.success : theme.faint,
                  ),
                  const SizedBox(width: 8),
                  Text(e.name, style: TextStyle(fontSize: 13, color: theme.foreground)),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
    if (selected != null) setState(() => _selectedEmployeeId = selected);
  }

  // ─── Build ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final mgr = context.watch<AgentManager>();
    String? employeeName;
    if (_selectedEmployeeId != null) {
      for (final e in mgr.employees) {
        if (e.uuid == _selectedEmployeeId) {
          employeeName = e.name;
          break;
        }
      }
    } else if (mgr.employees.isNotEmpty) {
      employeeName = mgr.employees.first.name;
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Ctrl+S 保存当前文件
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.keyS &&
            HardwareKeyboard.instance.isControlPressed) {
          _saveActiveTab();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: theme.background,
        child: Column(
        children: [
          // 顶部菜单栏
          MdTitleBar(
            canBack: _tabIndex > 0,
            canForward: _tabIndex < _tabs.length - 1,
            onBack: () => _goTab(-1),
            onForward: () => _goTab(1),
            onOpenAi: () {
              setState(() => _showAiPanel = !_showAiPanel);
              _persistState(); // AI 面板开关持久化
            },
            onOpenDocs: _openReadme,
            onToggleTheme: () {},
            aiActive: _showAiPanel,
          ),
          // 主体三栏（左右面板可拖拽调宽）
          Expanded(
            child: _projectLoading
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final total = constraints.maxWidth;
                      // 中间区域至少保留 _middleMin；按剩余空间约束左右面板上限
                      // （AI 面板隐藏时，右面板宽度视为 0，中间区域可占满）
                      final leftMaxEff = _showAiPanel
                          ? (total - _rightWidth - _middleMin).clamp(_leftMin, _leftMax)
                          : (total - _middleMin).clamp(_leftMin, _leftMax);
                      final rightMaxEff =
                          (total - _leftWidth - _middleMin).clamp(_rightMin, _rightMax);
                      final leftW = _leftWidth.clamp(_leftMin, leftMaxEff);
                      final rightW =
                          _showAiPanel ? _rightWidth.clamp(_rightMin, rightMaxEff) : 0.0;

                      return Row(
                        children: [
                          // 左侧：文件管理器
                          SizedBox(
                            width: leftW,
                            child: MdFileSidebar(
                              projectRoot: _projectRoot,
                              tree: _tree,
                              loading: _treeLoading,
                              selectedPath: _activeTabPath ?? '',
                              onPickProject: _pickProjectFolder,
                              onSelectPath: _openFile,
                              onSearchChanged: _onFileSearch,
                              onAddFile: _createFile,
                              onAddFolder: _createFolder,
                              onRefresh: _loadTree,
                            ),
                          ),
                          _DragHandle(
                            onDrag: (dx) {
                              setState(() => _leftWidth = (leftW + dx).clamp(_leftMin, leftMaxEff));
                            },
                            onDragEnd: _savePanelWidths,
                          ),
                          // 中间：编辑器（占满剩余）
                          Expanded(
                            child: MdMarkdownEditor(
                              tabs: _tabs,
                              activeTabPath: _activeTabPath,
                              previewMode: _previewMode,
                              controller: _editorCtrl,
                              onSelectTab: (path) => _openFile(path),
                              onCloseTab: _closeTab,
                              onTogglePreview: () {
                                setState(() => _previewMode = !_previewMode);
                                _persistState(); // 预览模式持久化
                              },
                              onSave: _saveActiveTab,
                              htmlReloadTick: _htmlReloadTick,
                            ),
                          ),
                          // 右侧：AI 任务中心（可被标题栏 AI 按钮隐藏）
                          if (_showAiPanel) ...[
                            _DragHandle(
                              onDrag: (dx) {
                                setState(() => _rightWidth = (rightW - dx).clamp(_rightMin, rightMaxEff));
                              },
                              onDragEnd: _savePanelWidths,
                            ),
                            SizedBox(
                              width: rightW,
                              child: MdAiTaskPanel(
                                tasks: _tasks,
                                selectedEmployeeName: employeeName,
                                executor: _executor,
                                providerName: _selectedProviderName,
                                providerNames: [for (final p in mgr.providerProfiles) p.name],
                                onPromptSubmitted: _submitTask,
                                onExecutorChanged: _onExecutorChanged,
                                onProviderChanged: _onProviderChanged,
                                onSearchChanged: (_) {},
                                onFilterChanged: (_) {},
                                onDeleteTask: _deleteTask,
                                onRetryTask: _retryTask,
                                onEditTask: _editTask,
                                onViewTask: _viewTask,
                                onPickEmployee: _pickEmployee,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
          ),
          // 底部状态栏
          MdBottomStatusBar(
            projectRoot: _projectRoot ?? '',
            currentPath: _activeTabPath ?? '',
            dirty: _activeTab?.isDirty ?? false,
            content: _activeTab?.content ?? '',
            taskCount: _tasks.length,
          ),
        ],
        ),
      ),
    );
  }
}

/// 面板间拖拽分割条。
/// hover 时高亮 + resize 光标，拖动实时回调 dx，松手回调 onDragEnd（持久化）。
class _DragHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  const _DragHandle({required this.onDrag, this.onDragEnd});

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => widget.onDragEnd?.call(),
        child: Container(
          width: 5,
          height: double.infinity,
          color: _hovered ? theme.accent.withAlpha(80) : theme.borderSubtle,
        ),
      ),
    );
  }
}
