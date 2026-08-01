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
    _editorCtrl.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _editorCtrl.removeListener(_onEditorChanged);
    _editorCtrl.dispose();
    super.dispose();
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
    );
    setState(() => _tasks.insert(0, task));

    // 执行任务
    _runTask(task, prompt, employee);
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

  void _deleteTask(MdTask task) {
    setState(() => _tasks.removeWhere((t) => t.id == task.id));
  }

  void _retryTask(MdTask task) {
    final mgr = context.read<AgentManager>();
    final employee = mgr.employees.firstWhere(
      (e) => e.uuid == task.employeeId,
      orElse: () => mgr.employees.first,
    );
    _runTask(task, task.title, employee);
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
            onOpenAi: () => setState(() => _showAiPanel = !_showAiPanel),
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
                              onTogglePreview: () => setState(() => _previewMode = !_previewMode),
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
                                onPromptSubmitted: _submitTask,
                                onSearchChanged: (_) {},
                                onFilterChanged: (_) {},
                                onDeleteTask: _deleteTask,
                                onRetryTask: _retryTask,
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
