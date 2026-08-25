import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/stream_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/multi_agent_provider.dart';
import '../services/bilibili_chat_service.dart';
import '../services/tts_service.dart';
import '../services/overlay_service.dart';
import '../services/live2d_server.dart';

/// Bilibili直播Stream页面
/// 三列布局: 连接面板+直播控制 / 弹幕实时列表 / Setlist编辑器
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  final _roomIdController = TextEditingController();
  final _scrollController = ScrollController();
  final _editDanmakuController = TextEditingController();
  late LiveStreamProvider _streamProvider;
  AgentManager? _agentManager;
  StreamSubscription<void>? _ttsCompleteSub;

  @override
  void initState() {
    super.initState();
    _streamProvider = context.read<LiveStreamProvider>();
    _agentManager = context.read<AgentManager>();
    _agentManager!.addListener(_syncAgentEmployeeNames);
    _syncAgentEmployeeNames();
    // 提前初始化 WenzAgent 并刷新员工列表，确保第一波弹幕 @员工 就能被识别。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _agentManager!.ensureReady().then((_) => _syncAgentEmployeeNames());
    });

    // 用闭包捕获 ChatProvider 和 SettingsProvider，不依赖 mounted 状态
    // 即使 StreamScreen 被切到后台，AI 回复回调仍能正常工作
    final chatProvider = context.read<ChatProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    final tts = chatProvider.backend.tts;

    _streamProvider.onAIResponse = (String prompt) async {
      if (prompt.startsWith('__SYSTEM_PROMPT__:')) {
        chatProvider.systemPrompt = prompt.substring(
          '__SYSTEM_PROMPT__:'.length,
        );
        return;
      }

      // Count messages before to find the AI response after
      final msgCountBefore = chatProvider.messages.length;
      await chatProvider.sendMessage(prompt);

      // Extract AI response and TTS it
      final messages = chatProvider.messages;
      if (messages.length > msgCountBefore) {
        // Find the last assistant message added
        String? aiText;
        for (int i = messages.length - 1; i >= 0; i--) {
          if (messages[i].role == 'assistant') {
            aiText = messages[i].content;
            break;
          }
        }

        if (aiText != null && aiText.isNotEmpty) {
          final s = settingsProvider.settings;

          if (s.ttsProvider == 'gpt-sovits' &&
              tts.isGptSovitsRunning &&
              s.gptSovitsRefAudio.isNotEmpty) {
            // Use GPT-SoVITS for TTS with mouth sync (Live2D + VRM)
            final overlay = OverlayService.instance;
            final (audioPath, volumes) = await tts
                .synthesizeGptSovitsWithVolumes(
                  aiText,
                  refAudioPath: s.gptSovitsRefAudio,
                  promptText: s.gptSovitsPromptText,
                  promptLang: s.gptSovitsPromptLang,
                );

            // Push audio URL to VRM pop-out (Web Audio API analysis)
            if (audioPath != null && overlay.isPopoutRunning) {
              final audioUrl = Live2DServer.toModelUrl(audioPath);
              overlay.pushAudioToPopout(audioUrl);
            }

            // Start mouth animation for Live2D (volume-based)
            if (overlay.isPopoutRunning) {
              overlay.startMouthAnimation(volumes);
            }

            if (volumes.isNotEmpty && overlay.isPopoutRunning) {
              _ttsCompleteSub?.cancel();
              _ttsCompleteSub = tts.onPlayerComplete.listen((_) {
                overlay.stopMouthAnimation();
                _ttsCompleteSub?.cancel();
                _ttsCompleteSub = null;
              });
            }
          } else {
            // Default: EdgeTTS with mouth sync
            tts.setParams(
              voice: s.edgeTtsVoice,
              pitch: s.edgeTtsPitch,
              rate: s.edgeTtsRate,
              volume: s.edgeTtsVolume,
            );

            final overlay = OverlayService.instance;
            final (audioPath, volumes) = await tts.synthesizeWithVolumes(
              aiText,
              onBeforePlay: (path) {
                if (overlay.isPopoutRunning) {
                  final audioUrl = Live2DServer.toModelUrl(path);
                  overlay.pushAudioToPopout(audioUrl);
                }
              },
            );

            if (overlay.isPopoutRunning) {
              overlay.startMouthAnimation(volumes);
            }

            if (volumes.isNotEmpty && overlay.isPopoutRunning) {
              _ttsCompleteSub?.cancel();
              _ttsCompleteSub = tts.onPlayerComplete.listen((_) {
                overlay.stopMouthAnimation();
                _ttsCompleteSub?.cancel();
                _ttsCompleteSub = null;
              });
            }
          }
        }
      }
    };

    // Direction 2: danmaku audience dispatches tasks to WenzAgent employees.
    // 使用闭包捕获 AgentManager；即使切到其它页面，回调仍可驱动 Agent 干活。
    final agentManager = _agentManager!;
    _streamProvider.onAgentTask = (String? targetName, String taskText) async {
      await agentManager.ensureReady();
      final employees = await agentManager.refreshEmployeesIfNeeded();
      if (employees.isEmpty) return;

      // Prefer explicit @name, then the default employee chosen in the panel.
      AgentModel? target;
      if (targetName != null && targetName.trim().isNotEmpty) {
        for (final e in employees) {
          if (e.name.trim() == targetName.trim() ||
              e.name.toLowerCase().contains(targetName.trim().toLowerCase())) {
            target = e;
            break;
          }
        }
      }
      if (target == null) {
        final defaultId = _streamProvider.agentTaskDefaultEmployeeId;
        if (defaultId != null) {
          for (final e in employees) {
            if (e.uuid == defaultId) {
              target = e;
              break;
            }
          }
        }
      }
      target ??= employees.first;

      await agentManager.runStreamAgentTask(target.uuid, taskText);
    };

    // 恢复上次的房间号
    _streamProvider.loadSavedRoomId().then((id) {
      if (id.isNotEmpty && mounted) {
        _roomIdController.text = id;
      }
    });

    // 恢复回复模式
    _streamProvider.loadReplyMode();
  }

  @override
  void dispose() {
    _agentManager?.removeListener(_syncAgentEmployeeNames);
    _ttsCompleteSub?.cancel();
    _roomIdController.dispose();
    _scrollController.dispose();
    _editDanmakuController.dispose();
    super.dispose();
  }

  void _syncAgentEmployeeNames() {
    final mgr = _agentManager;
    if (mgr == null) return;
    _streamProvider.agentTaskEmployeeNames = mgr.employees
        .map((e) => e.name)
        .toList();
  }

  Future<void> _toggleConnection() async {
    if (_streamProvider.isConnected) {
      await _streamProvider.disconnect();
    } else {
      await _streamProvider.connect(_roomIdController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 用 context.watch 才能响应 Provider 状态变化
    _streamProvider = context.watch<LiveStreamProvider>();
    final agentManager = context.watch<AgentManager>();
    final shad = ShadTheme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            children: [
              Icon(Icons.live_tv, size: 22, color: shad.primary),
              const SizedBox(width: 8),
              Text(
                l10n.streamTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: shad.foreground,
                ),
              ),
              if (_streamProvider.isConnected) ...[
                const SizedBox(width: 12),
                _buildStatusBadge(shad),
              ],
              const Spacer(),
              _buildAutoReplyToggle(shad),
            ],
          ),
          const SizedBox(height: 12),

          // 三列主内容
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左列
                SizedBox(
                  width: 280,
                  child: Column(
                    children: [
                      _buildConnectionPanel(shad),
                      const SizedBox(height: 12),
                      _buildAgentTaskPanel(shad, agentManager),
                      const SizedBox(height: 12),
                      _buildControls(shad),
                      const SizedBox(height: 12),
                      _buildReplyModePanel(shad),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 中列
                Expanded(child: _buildChatList(shad)),
                const SizedBox(width: 12),
                // 右列
                SizedBox(width: 300, child: _buildSetlistPanel(shad)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 状态标签 ──
  Widget _buildStatusBadge(ShadTheme shad) {
    final connected = _streamProvider.isConnected;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF22C55E).withAlpha(30)
            : const Color(0xFFEF4444).withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: connected
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected
                ? l10n.streamStatusLive.replaceAll(
                    '\$pop',
                    _streamProvider.popularity.toString(),
                  )
                : l10n.streamStatusOff,
            style: TextStyle(
              fontSize: 11,
              color: connected
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFEF4444),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── 自动回复开关 ──
  Widget _buildAutoReplyToggle(ShadTheme shad) {
    final enabled = _streamProvider.autoReply;
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.streamAutoReply,
          style: TextStyle(fontSize: 12, color: shad.mutedForeground),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _streamProvider.autoReply = !enabled,
          child: Container(
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: enabled ? shad.primary : shad.secondary,
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        if (enabled) ...[
          const SizedBox(width: 8),
          _buildIntervalDropdown(shad),
        ],
      ],
    );
  }

  Widget _buildIntervalDropdown(ShadTheme shad) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: shad.secondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _streamProvider.replyInterval,
          isDense: true,
          style: TextStyle(fontSize: 11, color: shad.foreground),
          items: const [
            DropdownMenuItem(value: 10, child: Text('10s')),
            DropdownMenuItem(value: 20, child: Text('20s')),
            DropdownMenuItem(value: 30, child: Text('30s')),
            DropdownMenuItem(value: 60, child: Text('60s')),
          ],
          onChanged: (v) {
            if (v != null) _streamProvider.replyInterval = v;
          },
        ),
      ),
    );
  }

  // ── 连接面板 ──
  Widget _buildConnectionPanel(ShadTheme shad) {
    final connected = _streamProvider.isConnected;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.streamConnection,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: shad.foreground,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _roomIdController,
            enabled: !connected,
            decoration: InputDecoration(
              hintText: l10n.streamIdHint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              prefixIcon: Icon(
                Icons.room,
                size: 16,
                color: shad.mutedForeground,
              ),
              suffixText: connected ? l10n.streamConnected : null,
              suffixStyle: TextStyle(
                color: const Color(0xFF22C55E),
                fontSize: 12,
              ),
            ),
            style: TextStyle(fontSize: 13, color: shad.foreground),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _toggleConnection,
              icon: Icon(
                connected ? Icons.stop_circle : Icons.play_circle,
                size: 18,
              ),
              label: Text(
                connected ? l10n.streamDisconnect : l10n.streamConnect,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: connected
                    ? const Color(0xFFEF4444)
                    : shad.primary,
                foregroundColor: connected
                    ? Colors.white
                    : shad.primaryForeground,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_streamProvider.statusMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _streamProvider.statusMessage,
              style: TextStyle(fontSize: 11, color: const Color(0xFFEF4444)),
            ),
          ],
        ],
      ),
    );
  }

  // ── 控制面板 ──
  Widget _buildAgentTaskPanel(ShadTheme shad, AgentManager mgr) {
    final enabled = _streamProvider.agentTaskEnabled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled ? shad.primary.withAlpha(80) : shad.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.assignment_ind,
                size: 16,
                color: enabled ? shad.primary : shad.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                'Agent 弹幕派活',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: shad.foreground,
                ),
              ),
              const Spacer(),
              Switch(
                value: enabled,
                onChanged: (v) => _streamProvider.agentTaskEnabled = v,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '观众发送 @agent 内容 / @员工名 任务 即可派活给员工',
            style: TextStyle(
              fontSize: 10,
              color: shad.mutedForeground,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          if (mgr.employees.isEmpty)
            Text(
              '暂无 WenzAgent 员工，请先在 Multi-Agent 页创建',
              style: TextStyle(fontSize: 10, color: shad.destructive),
            )
          else
            DropdownButtonFormField<String?>(
              key: ValueKey(
                'agent-default-${mgr.employees.map((e) => e.uuid).join(',')}',
              ),
              initialValue:
                  _streamProvider.agentTaskDefaultEmployeeId ??
                  (mgr.employees.isNotEmpty ? mgr.employees.first.uuid : null),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: shad.secondary,
                border: OutlineInputBorder(),
                labelText: '默认接活员工',
                labelStyle: TextStyle(
                  fontSize: 11,
                  color: shad.mutedForeground,
                ),
              ),
              items: mgr.employees
                  .map(
                    (e) => DropdownMenuItem<String?>(
                      value: e.uuid,
                      child: Text(
                        e.name,
                        style: TextStyle(fontSize: 12, color: shad.foreground),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => _streamProvider.agentTaskDefaultEmployeeId = v,
            ),
        ],
      ),
    );
  }

  // ── 控制面板 ──
  Widget _buildControls(ShadTheme shad) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.streamControls,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: shad.foreground,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _streamProvider.isConnected
                  ? () => _streamProvider.triggerReply('请对观众们说点什么吧~')
                  : null,
              icon: const Icon(Icons.chat, size: 16),
              label: Text(l10n.streamManualReply),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.streamOBSTip,
            style: TextStyle(
              fontSize: 10,
              color: shad.mutedForeground,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ── 回复模式切换面板 ──
  Widget _buildReplyModePanel(ShadTheme shad) {
    final isSliding =
        _streamProvider.replyMode == StreamReplyMode.slidingWindow;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.streamReplyMode,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: shad.foreground,
            ),
          ),
          const SizedBox(height: 8),
          // 模式切换按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                _streamProvider.replyMode = isSliding
                    ? StreamReplyMode.sequential
                    : StreamReplyMode.slidingWindow;
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                side: BorderSide(
                  color: isSliding
                      ? const Color(0xFF8B5CF6)
                      : const Color(0xFF22C55E),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isSliding ? Icons.window : Icons.format_list_numbered,
                    size: 16,
                    color: isSliding
                        ? const Color(0xFF8B5CF6)
                        : const Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isSliding
                        ? l10n.streamReplyModeSliding
                        : l10n.streamReplyModeSequential,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSliding
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFF22C55E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.streamReplyModeSwitch.replaceAll(
                      r'$mode',
                      isSliding
                          ? l10n.streamReplyModeSequential
                          : l10n.streamReplyModeSliding,
                    ),
                    style: TextStyle(fontSize: 9, color: shad.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 测试弹幕按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _sendTestDanmaku,
              icon: const Icon(Icons.science, size: 16),
              label: Text(
                l10n.streamTestDanmaku,
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                side: BorderSide(color: shad.border),
                foregroundColor: shad.mutedForeground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendTestDanmaku() {
    _streamProvider.sendTestDanmaku();
  }

  // ── 弹幕消息列表 ──
  Widget _buildChatList(ShadTheme shad) {
    final messages = _streamProvider.messages;
    final isEdit = _streamProvider.isEditMode;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行 + Live/Edit 切换
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  l10n.streamMessages,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: shad.foreground,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: shad.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${messages.length}',
                    style: TextStyle(fontSize: 11, color: shad.primary),
                  ),
                ),
                const Spacer(),
                // Live / Edit 切换
                _buildModeToggle(shad),
              ],
            ),
          ),
          // 编辑模式输入框
          if (isEdit) _buildEditInput(shad),
          Divider(height: 1, color: shad.border),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      isEdit
                          ? l10n.streamEditDanmakuHint
                          : _streamProvider.isConnected
                          ? l10n.streamWaiting
                          : l10n.streamConnectForDanmaku,
                      style: TextStyle(
                        fontSize: 13,
                        color: shad.mutedForeground,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildChatBubble(msg, shad);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(ShadTheme shad) {
    final isEdit = _streamProvider.isEditMode;
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () => _streamProvider.isEditMode = !isEdit,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isEdit
              ? const Color(0xFFF59E0B).withAlpha(25)
              : const Color(0xFF22C55E).withAlpha(25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isEdit ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEdit ? Icons.edit : Icons.circle,
              size: 10,
              color: isEdit ? const Color(0xFFF59E0B) : const Color(0xFF22C55E),
            ),
            const SizedBox(width: 5),
            Text(
              isEdit ? l10n.streamEditMode : l10n.streamLiveMode,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isEdit
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF22C55E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditInput(ShadTheme shad) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _editDanmakuController,
              onSubmitted: (_) => _sendManualDanmaku(),
              style: TextStyle(fontSize: 13, color: shad.foreground),
              decoration: InputDecoration(
                hintText: l10n.streamEditDanmakuHint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: shad.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: shad.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: shad.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 35,
            child: ElevatedButton(
              onPressed: _sendManualDanmaku,
              style: ElevatedButton.styleFrom(
                backgroundColor: shad.primary,
                foregroundColor: shad.primaryForeground,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                l10n.streamSendDanmaku,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendManualDanmaku() {
    final text = _editDanmakuController.text;
    if (text.trim().isEmpty) return;
    _streamProvider.addManualDanmaku(text);
    _editDanmakuController.clear();
  }

  Widget _buildChatBubble(BilibiliDanmaku msg, ShadTheme shad) {
    Color? bubbleColor;
    IconData? icon;
    switch (msg.type) {
      case BilibiliDanmakuType.gift:
        bubbleColor = const Color(0xFFF59E0B).withAlpha(20);
        icon = Icons.card_giftcard;
      case BilibiliDanmakuType.superChat:
        bubbleColor = const Color(0xFFEF4444).withAlpha(20);
        icon = Icons.star;
      case BilibiliDanmakuType.guard:
        bubbleColor = const Color(0xFF8B5CF6).withAlpha(20);
        icon = Icons.shield;
      default:
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bubbleColor ?? shad.secondary.withAlpha(60),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: shad.mutedForeground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: shad.foreground),
                children: [
                  TextSpan(
                    text: msg.uname,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: msg.type == BilibiliDanmakuType.superChat
                          ? const Color(0xFFEF4444)
                          : shad.primary,
                    ),
                  ),
                  TextSpan(
                    text: ': ',
                    style: TextStyle(color: shad.mutedForeground),
                  ),
                  TextSpan(text: msg.content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Setlist编辑面板 ──
  Widget _buildSetlistPanel(ShadTheme shad) {
    final setlist = _streamProvider.setlist;
    final isRunning = _streamProvider.isSetlistRunning;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: shad.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: shad.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Text(
                  l10n.streamSetlist,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: shad.foreground,
                  ),
                ),
                const Spacer(),
                _buildAddNodeButton(shad),
              ],
            ),
          ),
          Divider(height: 1, color: shad.border),
          Expanded(
            child: setlist.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.queue_music,
                          size: 36,
                          color: shad.mutedForeground.withAlpha(100),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.streamAddNodeHint,
                          style: TextStyle(
                            fontSize: 12,
                            color: shad.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: setlist.length,
                    itemBuilder: (context, index) {
                      final item = setlist[index];
                      final isCurrent =
                          isRunning &&
                          _streamProvider.currentNodeIndex == index;
                      return _buildSetlistItem(item, index, isCurrent, shad);
                    },
                  ),
          ),
          if (setlist.isNotEmpty) ...[
            Divider(height: 1, color: shad.border),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: isRunning
                      ? () => _streamProvider.stopSetlist()
                      : () => _streamProvider.startSetlist(),
                  icon: Icon(
                    isRunning ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(
                    isRunning ? l10n.streamStopFlow : l10n.streamStartFlow,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRunning
                        ? const Color(0xFFEF4444)
                        : shad.primary,
                    foregroundColor: isRunning
                        ? Colors.white
                        : shad.primaryForeground,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddNodeButton(ShadTheme shad) {
    return PopupMenuButton<StreamNodeType>(
      icon: Icon(Icons.add, size: 18, color: shad.primary),
      onSelected: (type) => _streamProvider.addSetlistNode(type),
      itemBuilder: (context) => StreamNodeDefinition.registry.entries.map((e) {
        return PopupMenuItem(
          value: e.key,
          child: Row(
            children: [
              Icon(_getNodeIcon(e.key), size: 16),
              const SizedBox(width: 8),
              Text(e.value.name, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSetlistItem(
    StreamSetlistItem item,
    int index,
    bool isCurrent,
    ShadTheme shad,
  ) {
    final def = item.nodeDef;
    final name = def?.name ?? item.nodeType.name;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isCurrent ? shad.primary.withAlpha(20) : null,
        borderRadius: BorderRadius.circular(6),
        border: isCurrent ? Border.all(color: shad.primary, width: 1.5) : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showNodeSettingsDialog(item, index, shad),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(_getNodeIcon(item.nodeType), size: 16, color: shad.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$name ${isCurrent ? l10n.streamInProgress : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent ? shad.primary : shad.foreground,
                  ),
                ),
              ),
              if (!_streamProvider.isSetlistRunning)
                GestureDetector(
                  onTap: () => _streamProvider.moveSetlistNode(index, -1),
                  child: Icon(
                    Icons.arrow_upward,
                    size: 14,
                    color: index == 0
                        ? shad.mutedForeground.withAlpha(60)
                        : shad.mutedForeground,
                  ),
                ),
              if (!_streamProvider.isSetlistRunning)
                GestureDetector(
                  onTap: () => _streamProvider.moveSetlistNode(index, 1),
                  child: Icon(
                    Icons.arrow_downward,
                    size: 14,
                    color: index == _streamProvider.setlist.length - 1
                        ? shad.mutedForeground.withAlpha(60)
                        : shad.mutedForeground,
                  ),
                ),
              if (!_streamProvider.isSetlistRunning)
                GestureDetector(
                  onTap: () => _streamProvider.removeSetlistNode(index),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: shad.mutedForeground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodeSettingsDialog(
    StreamSetlistItem item,
    int index,
    ShadTheme shad,
  ) {
    final def = item.nodeDef;
    if (def == null) return;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) {
        final settings = Map<String, dynamic>.from(item.settings);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                l10n.streamNodeSettings.replaceAll('\$name', def.name),
                style: TextStyle(color: shad.foreground),
              ),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (def.presets.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: l10n.streamPreset,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        value: null,
                        hint: Text(
                          l10n.streamPresetHint,
                          style: const TextStyle(fontSize: 13),
                        ),
                        items: def.presets.keys.map((key) {
                          return DropdownMenuItem(value: key, child: Text(key));
                        }).toList(),
                        onChanged: (presetKey) {
                          if (presetKey != null &&
                              def.presets.containsKey(presetKey)) {
                            settings.addAll(def.presets[presetKey]!);
                            setDialogState(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...def.defaultSettings.keys.map((key) {
                      final value = settings[key] ?? def.defaultSettings[key];
                      if (value is String) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: TextEditingController(text: value),
                            decoration: InputDecoration(
                              labelText: key,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (v) {
                              settings[key] = v;
                              setDialogState(() {});
                            },
                          ),
                        );
                      } else if (value is num) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: TextEditingController(
                              text: value.toString(),
                            ),
                            decoration: InputDecoration(
                              labelText: key,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final num = int.tryParse(v) ?? double.tryParse(v);
                              if (num != null) settings[key] = num;
                              setDialogState(() {});
                            },
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    _streamProvider.updateNodeSettings(
                      index,
                      StreamSetlistItem(
                        nodeType: item.nodeType,
                        settings: settings,
                      ),
                    );
                    Navigator.pop(ctx);
                  },
                  child: Text(l10n.confirm),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getNodeIcon(StreamNodeType type) {
    switch (type) {
      case StreamNodeType.systemPrompt:
        return Icons.tune;
      case StreamNodeType.promptedResponse:
        return Icons.psychology;
      case StreamNodeType.chat:
        return Icons.chat_bubble;
      case StreamNodeType.sing:
        return Icons.music_note;
    }
  }
}
