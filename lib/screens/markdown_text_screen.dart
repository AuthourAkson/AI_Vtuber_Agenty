import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/multi_agent_provider.dart';
import '../services/project_summary_service.dart';

/// Three-column Markdown documentation editor screen.
///
/// Left: file tree (project-summary/ structure)
/// Center: markdown editor + preview tabs
/// Right: requirements panel + employee selector + status
///
/// Supports any project folder — select via the header button.
/// On send, injects project-summary convention so MultiAgent employees
/// automatically create and maintain project documentation.
class MarkdownTextScreen extends StatefulWidget {
  const MarkdownTextScreen({super.key});

  @override
  State<MarkdownTextScreen> createState() => _MarkdownTextScreenState();
}

class _MarkdownTextScreenState extends State<MarkdownTextScreen> {
  final ProjectSummaryService _svc = ProjectSummaryService();
  final TextEditingController _editorCtrl = TextEditingController();
  final TextEditingController _reqCtrl = TextEditingController();
  final ScrollController _editorScrollCtrl = ScrollController();

  String? _projectRoot;
  bool _projectLoading = true;

  List<SummaryNode> _tree = [];
  bool _treeLoading = true;

  SummaryNode? _selectedNode;
  String? _selectedPath;
  String _originalContent = '';
  bool _isDirty = false;
  bool _editMode = true; // true = edit, false = preview

  String? _selectedEmployeeId;
  bool _sending = false;
  String? _sendStatus; // null | 'sent' | 'failed'

  @override
  void initState() {
    super.initState();
    _loadProjectRoot();
    _editorCtrl.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _editorCtrl.removeListener(_onEditorChanged);
    _editorCtrl.dispose();
    _reqCtrl.dispose();
    _editorScrollCtrl.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    final dirty = _editorCtrl.text != _originalContent;
    if (dirty != _isDirty) {
      setState(() => _isDirty = dirty);
    }
  }

  // ─── Project Root ──────────────────────────────────────

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

  Future<void> _pickProjectFolder() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: AppLocalizations.of(context).mdSelectProject,
    );
    if (result == null || result.isEmpty) return;

    // Clear current selection
    setState(() {
      _projectRoot = result;
      _selectedNode = null;
      _selectedPath = null;
      _editorCtrl.text = '';
      _isDirty = false;
    });

    _svc.setProjectRoot(result);

    // Persist
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('markdown_project_root', result);

    await _loadTree();
  }

  // ─── Tree ──────────────────────────────────────────────

  Future<void> _loadTree() async {
    if (_projectRoot == null) return;
    setState(() => _treeLoading = true);
    try {
      final tree = await _svc.buildTree();
      if (mounted) setState(() { _tree = tree; _treeLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _treeLoading = false);
    }
  }

  Future<void> _selectNode(SummaryNode node) async {
    // Save current changes first if dirty
    if (_isDirty && _selectedPath != null) {
      await _svc.writeFile(_selectedPath!, _editorCtrl.text);
    }

    if (node.isDirectory) return; // directories just toggle

    setState(() {
      _selectedNode = node;
      _selectedPath = node.relativePath;
      _isDirty = false;
      _editMode = true;
    });

    try {
      final content = await _svc.readFile(node.relativePath);
      _originalContent = content;
      _editorCtrl.text = content;
    } catch (e) {
      _originalContent = '';
      _editorCtrl.text = '';
    }
  }

  Future<void> _saveFile() async {
    if (_selectedPath == null) return;
    try {
      await _svc.writeFile(_selectedPath!, _editorCtrl.text);
      _originalContent = _editorCtrl.text;
      if (mounted) {
        setState(() => _isDirty = false);
        _showSnackBar(AppLocalizations.of(context).mdSaved);
      }
    } catch (e) {
      _showSnackBar('Save failed: $e');
    }
  }

  Future<void> _createFile(String dirRelPath) async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mdNewFile),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.mdFileNameHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await _svc.createFile(dirRelPath, result);
      await _loadTree();
    } catch (e) {
      _showSnackBar('$e');
    }
  }

  Future<void> _createFolder(String parentRelPath) async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mdNewFolder),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.mdFolderNameHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await _svc.createDirectory(parentRelPath, result);
      await _loadTree();
    } catch (e) {
      _showSnackBar('$e');
    }
  }

  Future<void> _deleteNode(SummaryNode node) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mdDelete),
        content: Text(l10n.mdDeleteConfirm.replaceAll(r'${name}', node.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.mdDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _svc.delete(node.relativePath);
      if (_selectedPath == node.relativePath) {
        setState(() {
          _selectedNode = null;
          _selectedPath = null;
          _editorCtrl.text = '';
          _isDirty = false;
        });
      }
      await _loadTree();
    } catch (e) {
      _showSnackBar('Delete failed: $e');
    }
  }

  // ─── Send Requirements (with deep project context) ─────

  /// Convention instruction injected when sending to MultiAgent employees.
  /// Tells the agent to maintain project-summary/ documentation for any project it works on.
  static const _projectSummaryConvention = '''
# Project Documentation Convention (project-summary/)

Every project you work on MUST maintain a structured documentation directory at:
  <project-root>/project-summary/

Directory structure:
  project-summary/
  ├── README.md           # Project overview with quick links
  ├── architecture/       # Architecture decisions, data flow, tech stack
  │   ├── overview.md
  │   └── data-flow.md
  ├── screens/            # One doc per UI screen
  ├── services/           # One doc per backend service
  ├── widgets/            # Reusable components
  ├── models/             # Data model docs
  └── providers/          # State management docs

Rules:
- Each .md file describes ONE component (screen/service/widget/model)
- Include: file path, overview, key components, related files
- Use markdown headings, code blocks, and tables
- When creating a new project, scaffold this structure automatically
- When modifying code, update the corresponding .md file
- Keep README.md up to date as the navigation hub
''';

  Future<void> _sendRequirements() async {
    final text = _reqCtrl.text.trim();
    if (text.isEmpty || _selectedEmployeeId == null || _projectRoot == null) return;

    // Build a contextual prompt that includes the current file + project convention
    final buffer = StringBuffer();
    buffer.writeln('[MarkdownText Request]');
    buffer.writeln('Project: $_projectRoot');
    buffer.writeln();
    buffer.writeln(_projectSummaryConvention);
    buffer.writeln();

    if (_selectedPath != null) {
      buffer.writeln('Current file: project-summary/$_selectedPath');
      buffer.writeln();
      buffer.writeln('```markdown');
      buffer.writeln(_editorCtrl.text);
      buffer.writeln('```');
      buffer.writeln();
    } else {
      buffer.writeln('(No file currently open — the user is browsing the project docs.)');
      buffer.writeln();
    }

    buffer.writeln('User request:');
    buffer.writeln(text);

    final mgr = context.read<AgentManager>();
    final employees = mgr.employees;
    if (employees.isEmpty) return;

    final employee = employees.firstWhere(
      (e) => e.uuid == _selectedEmployeeId,
      orElse: () => employees.first,
    );

    setState(() {
      _sending = true;
      _sendStatus = null;
    });

    try {
      // Open agent session and send the message
      await mgr.openAgent(employee.uuid, employee.name);
      await mgr.sendMessage(buffer.toString());
      if (mounted) {
        setState(() {
          _sending = false;
          _sendStatus = 'sent';
          _reqCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendStatus = 'failed';
        });
        _showSnackBar('${AppLocalizations.of(context).mdSendFailed} $e');
      }
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ─── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = ShadTheme.of(context);

    if (_projectLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_projectRoot == null) {
      return _buildNoProject(l10n, theme);
    }

    return Column(
      children: [
        // Header bar with project selector
        _buildHeader(l10n, theme),
        const Divider(height: 1),
        // Three-column body
        Expanded(
          child: Row(
            children: [
              // ── Left: File Tree ──
              SizedBox(width: 250, child: _buildTreePanel(l10n, theme)),
              VerticalDivider(width: 1, color: theme.border),
              // ── Center: Editor / Preview ──
              Expanded(child: _buildEditorPanel(l10n, theme)),
              VerticalDivider(width: 1, color: theme.border),
              // ── Right: Requirements + Employee Status ──
              SizedBox(width: 300, child: _buildRightPanel(l10n, theme)),
            ],
          ),
        ),
      ],
    );
  }

  // ─── No Project Placeholder ────────────────────────────

  Widget _buildNoProject(AppLocalizations l10n, ShadTheme theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 64, color: theme.mutedForeground.withAlpha(80)),
          const SizedBox(height: 16),
          Text(
            l10n.mdNoProject,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.mutedForeground, fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _pickProjectFolder,
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(l10n.mdOpenProject),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              foregroundColor: theme.accentForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, ShadTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.card,
      child: Row(
        children: [
          Icon(Icons.article_outlined, size: 20, color: theme.mutedForeground),
          const SizedBox(width: 8),
          Text(l10n.mdTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          // Project folder selector
          GestureDetector(
            onTap: _pickProjectFolder,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: theme.border),
                color: theme.muted.withAlpha(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder, size: 14, color: theme.mutedForeground),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      _projectRoot ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: theme.mutedForeground),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.unfold_more, size: 12, color: theme.mutedForeground),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (_selectedPath != null) ...[
            if (_isDirty)
              Text(l10n.mdUnsaved,
                style: TextStyle(fontSize: 11, color: Colors.orange.shade300)),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _isDirty ? _saveFile : null,
              icon: const Icon(Icons.save, size: 16),
              label: Text(l10n.mdSave),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Left Panel: File Tree ──

  Widget _buildTreePanel(AppLocalizations l10n, ShadTheme theme) {
    return Column(
      children: [
        // Tree header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.muted.withAlpha(40),
          child: Row(
            children: [
              Text(l10n.mdTreeTitle,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.mutedForeground)),
              const Spacer(),
              // Refresh button
              GestureDetector(
                onTap: _loadTree,
                child: Icon(Icons.refresh, size: 16, color: theme.mutedForeground),
              ),
              const SizedBox(width: 4),
              // Add file
              GestureDetector(
                onTap: () => _createFile(''),
                child: Icon(Icons.note_add, size: 16, color: theme.mutedForeground),
              ),
              const SizedBox(width: 4),
              // Add folder
              GestureDetector(
                onTap: () => _createFolder(''),
                child: Icon(Icons.create_new_folder, size: 16, color: theme.mutedForeground),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Tree content
        Expanded(
          child: _treeLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _tree.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No documentation yet.\nCreate a file to get started.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.mutedForeground, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: _buildTreeNodes(_tree, 0, theme, l10n),
                    ),
        ),
      ],
    );
  }

  List<Widget> _buildTreeNodes(List<SummaryNode> nodes, int depth, ShadTheme theme, AppLocalizations l10n) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final isSelected = _selectedPath == node.relativePath;
      widgets.add(
        _TreeTile(
          node: node,
          depth: depth,
          isSelected: isSelected,
          theme: theme,
          l10n: l10n,
          onTap: () => _selectNode(node),
          onAddFile: () => _createFile(node.isDirectory ? node.relativePath : ''),
          onAddFolder: () => _createFolder(node.isDirectory ? node.relativePath : ''),
          onDelete: () => _deleteNode(node),
        ),
      );
    }
    return widgets;
  }

  // ── Center Panel: Editor / Preview ──

  Widget _buildEditorPanel(AppLocalizations l10n, ShadTheme theme) {
    if (_selectedNode == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48, color: theme.mutedForeground.withAlpha(80)),
            const SizedBox(height: 12),
            Text(l10n.mdNoFileSelected,
              style: TextStyle(color: theme.mutedForeground, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Tab bar: Edit | Preview
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: theme.muted.withAlpha(30),
          child: Row(
            children: [
              _EditorTab(
                label: l10n.mdEdit,
                icon: Icons.edit,
                isActive: _editMode,
                onTap: () => setState(() => _editMode = true),
              ),
              const SizedBox(width: 4),
              _EditorTab(
                label: l10n.mdPreview,
                icon: Icons.visibility,
                isActive: !_editMode,
                onTap: () => setState(() => _editMode = false),
              ),
              const Spacer(),
              // File path breadcrumb
              Text(
                _selectedPath ?? '',
                style: TextStyle(fontSize: 11, color: theme.mutedForeground),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Editor or Preview
        Expanded(
          child: _editMode ? _buildEditor(theme) : _buildPreview(theme),
        ),
      ],
    );
  }

  Widget _buildEditor(ShadTheme theme) {
    return Container(
      color: theme.card,
      child: TextField(
        controller: _editorCtrl,
        scrollController: _editorScrollCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.foreground,
          height: 1.5,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          hintText: 'Write markdown here...',
          hintStyle: TextStyle(color: theme.mutedForeground.withAlpha(120)),
        ),
      ),
    );
  }

  Widget _buildPreview(ShadTheme theme) {
    return Container(
      color: theme.card,
      padding: const EdgeInsets.all(16),
      child: Markdown(
        data: _editorCtrl.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(color: theme.foreground, fontSize: 14, height: 1.6),
          h1: TextStyle(color: theme.foreground, fontSize: 22, fontWeight: FontWeight.bold),
          h2: TextStyle(color: theme.foreground, fontSize: 18, fontWeight: FontWeight.bold),
          h3: TextStyle(color: theme.foreground, fontSize: 16, fontWeight: FontWeight.w600),
          code: TextStyle(
            color: theme.accentForeground,
            backgroundColor: theme.muted.withAlpha(60),
            fontSize: 13,
          ),
          codeblockDecoration: BoxDecoration(
            color: theme.muted.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
          ),
          blockquoteDecoration: BoxDecoration(
            border: Border(left: BorderSide(color: theme.accent, width: 3)),
          ),
        ),
      ),
    );
  }

  // ── Right Panel: Requirements + Employee Status ──

  Widget _buildRightPanel(AppLocalizations l10n, ShadTheme theme) {
    return Column(
      children: [
        // Requirements section
        _buildRequirementsSection(l10n, theme),
        const Divider(height: 1),
        // Employee status section
        Expanded(child: _buildEmployeeStatusSection(l10n, theme)),
      ],
    );
  }

  Widget _buildRequirementsSection(AppLocalizations l10n, ShadTheme theme) {
    return SizedBox(
      height: 280,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.muted.withAlpha(40),
            child: Text(l10n.mdRequirements,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.mutedForeground)),
          ),
          // Text area
          Expanded(
            child: TextField(
              controller: _reqCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(fontSize: 13, color: theme.foreground, height: 1.4),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(10),
                hintText: l10n.mdRequirementsHint,
                hintStyle: TextStyle(color: theme.mutedForeground.withAlpha(100), fontSize: 12),
              ),
            ),
          ),
          // Employee selector + Send
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: theme.border)),
            ),
            child: Column(
              children: [
                // Employee dropdown
                _buildEmployeeDropdown(l10n, theme),
                const SizedBox(height: 6),
                // Send button
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: (_selectedEmployeeId != null && _reqCtrl.text.trim().isNotEmpty && !_sending)
                        ? _sendRequirements
                        : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(
                            _sendStatus == 'sent' ? Icons.check : Icons.send,
                            size: 16,
                          ),
                    label: Text(_sending
                        ? l10n.mdSending
                        : _sendStatus == 'sent'
                            ? l10n.mdSent
                            : l10n.mdSendToEmployee),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: theme.accentForeground,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeDropdown(AppLocalizations l10n, ShadTheme theme) {
    return Consumer<AgentManager>(
      builder: (context, mgr, _) {
        final employees = mgr.employees;
        if (employees.isEmpty) {
          return Text(l10n.mdNoEmployee,
            style: TextStyle(fontSize: 11, color: theme.mutedForeground));
        }

        // Compute a valid employee ID without mutating state during build
        final validId = _validEmployeeId(employees);

        return SizedBox(
          height: 30,
          child: DropdownButtonFormField<String>(
            initialValue: validId,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
              isDense: true,
            ),
            style: TextStyle(fontSize: 12, color: theme.foreground),
            items: employees.map((e) {
              final icon = e.status == 'online' ? Icons.circle : Icons.circle_outlined;
              final color = e.status == 'online' ? Colors.green : theme.mutedForeground;
              return DropdownMenuItem<String>(
                value: e.uuid,
                child: Row(
                  children: [
                    Icon(icon, size: 8, color: color),
                    const SizedBox(width: 6),
                    Flexible(child: Text(e.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) => setState(() => _selectedEmployeeId = v),
          ),
        );
      },
    );
  }

  /// Returns a valid employee ID without side effects.
  String? _validEmployeeId(List<AgentModel> employees) {
    if (employees.isEmpty) return null;
    if (_selectedEmployeeId != null &&
        employees.any((e) => e.uuid == _selectedEmployeeId)) {
      return _selectedEmployeeId;
    }
    // Don't mutate _selectedEmployeeId here — caller does it if needed
    return employees.first.uuid;
  }

  // ── Employee Status ──

  Widget _buildEmployeeStatusSection(AppLocalizations l10n, ShadTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: theme.muted.withAlpha(40),
          child: Text(l10n.mdEmployeeStatus,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: theme.mutedForeground)),
        ),
        const Divider(height: 1),
        // Employee list
        Expanded(
          child: Consumer<AgentManager>(
            builder: (context, mgr, _) {
              final employees = mgr.employees;
              if (employees.isEmpty) {
                return Center(
                  child: Text(l10n.mdNoEmployee,
                    style: TextStyle(fontSize: 12, color: theme.mutedForeground)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: employees.length,
                itemBuilder: (context, index) {
                  final emp = employees[index];
                  return _EmployeeStatusTile(employee: emp, theme: theme, l10n: l10n);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Tree Tile Widget ────────────────────────────────────

class _TreeTile extends StatefulWidget {
  final SummaryNode node;
  final int depth;
  final bool isSelected;
  final ShadTheme theme;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onAddFile;
  final VoidCallback onAddFolder;
  final VoidCallback onDelete;

  const _TreeTile({
    required this.node,
    required this.depth,
    required this.isSelected,
    required this.theme,
    required this.l10n,
    required this.onTap,
    required this.onAddFile,
    required this.onAddFolder,
    required this.onDelete,
  });

  @override
  State<_TreeTile> createState() => _TreeTileState();
}

class _TreeTileState extends State<_TreeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final theme = widget.theme;
    final indent = 8.0 + widget.depth * 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: widget.isSelected ? theme.accent.withAlpha(30) : Colors.transparent,
          child: InkWell(
            onTap: node.isDirectory
                ? () => setState(() => _expanded = !_expanded)
                : widget.onTap,
            child: Container(
              height: 32,
              padding: EdgeInsets.only(left: indent, right: 4),
              child: Row(
                children: [
                  // Expand/collapse arrow for directories
                  if (node.isDirectory) ...[
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: theme.mutedForeground,
                    ),
                  ] else
                    const SizedBox(width: 16),
                  const SizedBox(width: 4),
                  // Icon
                  Icon(
                    node.isDirectory
                        ? (_expanded ? Icons.folder_open : Icons.folder)
                        : Icons.description_outlined,
                    size: 16,
                    color: node.isDirectory
                        ? Colors.amber.shade300
                        : widget.isSelected
                            ? theme.accent
                            : theme.mutedForeground,
                  ),
                  const SizedBox(width: 6),
                  // Name
                  Flexible(
                    child: Text(
                      node.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: widget.isSelected ? theme.accent : theme.foreground,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Context menu for directories
                  if (node.isDirectory)
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      icon: Icon(Icons.more_horiz, size: 14, color: theme.mutedForeground),
                      onSelected: (action) {
                        switch (action) {
                          case 'addFile': widget.onAddFile();
                          case 'addFolder': widget.onAddFolder();
                          case 'delete': widget.onDelete();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'addFile', child: Text(widget.l10n.mdNewFile, style: TextStyle(fontSize: 12))),
                        PopupMenuItem(value: 'addFolder', child: Text(widget.l10n.mdNewFolder, style: TextStyle(fontSize: 12))),
                        PopupMenuItem(value: 'delete', child: Text(widget.l10n.mdDelete, style: TextStyle(fontSize: 12, color: Colors.red))),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        // Children
        if (node.isDirectory && _expanded)
          ...widget.node.children.map((child) => _TreeTile(
            node: child,
            depth: widget.depth + 1,
            isSelected: false, // handled by parent
            theme: theme,
            l10n: widget.l10n,
            onTap: () {
              // Bubble up: the parent screen handles selection
              final screen = context.findAncestorStateOfType<_MarkdownTextScreenState>();
              screen?._selectNode(child);
            },
            onAddFile: widget.onAddFile,
            onAddFolder: widget.onAddFolder,
            onDelete: widget.onDelete,
          )),
      ],
    );
  }
}

// ─── Employee Status Tile ─────────────────────────────────

class _EmployeeStatusTile extends StatelessWidget {
  final AgentModel employee;
  final ShadTheme theme;
  final AppLocalizations l10n;

  const _EmployeeStatusTile({
    required this.employee,
    required this.theme,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = employee.status == 'online';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.green : theme.mutedForeground.withAlpha(100),
            ),
          ),
          const SizedBox(width: 8),
          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  employee.name,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.foreground),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isOnline ? l10n.mdIdle : employee.status,
                  style: TextStyle(
                    fontSize: 10,
                    color: isOnline ? Colors.green.shade300 : theme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Editor Tab Widget ────────────────────────────────────

class _EditorTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _EditorTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? theme.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isActive ? theme.accent : theme.mutedForeground),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? theme.accent : theme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
