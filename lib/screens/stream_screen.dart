import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/stream_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../services/bilibili_chat_service.dart';
import '../widgets/vrm_view.dart';
import '../widgets/live2d_view.dart';

/// Bilibili直播Stream页面
/// 三列布局: 连接面板+角色预览 / 弹幕实时列表 / Setlist编辑器
class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  final _roomIdController = TextEditingController();
  final _scrollController = ScrollController();
  late LiveStreamProvider _streamProvider;

  @override
  void initState() {
    super.initState();
    _streamProvider = context.read<LiveStreamProvider>();

    // 注入AI回复回调
    _streamProvider.onAIResponse = _handleAIResponse;

    // 恢复上次的房间号
    _streamProvider.loadSavedRoomId().then((id) {
      if (id.isNotEmpty && mounted) {
        _roomIdController.text = id;
      }
    });
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleAIResponse(String prompt) {
    if (!mounted) return;
    final chatProvider = context.read<ChatProvider>();

    if (prompt.startsWith('__SYSTEM_PROMPT__:')) {
      final newPrompt = prompt.substring('__SYSTEM_PROMPT__:'.length);
      chatProvider.systemPrompt = newPrompt;
      return;
    }

    chatProvider.sendMessage(prompt);
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
    final shad = ShadTheme.of(context);

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
                'Bilibili 直播',
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
                      _buildCharacterPreview(shad),
                      const SizedBox(height: 12),
                      _buildControls(shad),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 中列
                Expanded(child: _buildChatList(shad)),
                const SizedBox(width: 12),
                // 右列
                SizedBox(
                  width: 300,
                  child: _buildSetlistPanel(shad),
                ),
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
                ? '直播中  ${_streamProvider.popularity}人气'
                : '未连接',
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('自动回复',
            style: TextStyle(fontSize: 12, color: shad.mutedForeground)),
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
              alignment:
                  enabled ? Alignment.centerRight : Alignment.centerLeft,
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
          Text('直播间连接',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: shad.foreground)),
          const SizedBox(height: 8),
          TextField(
            controller: _roomIdController,
            enabled: !connected,
            decoration: InputDecoration(
              hintText: '输入Bilibili直播间号',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              prefixIcon:
                  Icon(Icons.room, size: 16, color: shad.mutedForeground),
              suffixText: connected ? '已连接' : null,
              suffixStyle:
                  TextStyle(color: const Color(0xFF22C55E), fontSize: 12),
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
              label: Text(connected ? '断开连接' : '连接直播间'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    connected ? const Color(0xFFEF4444) : shad.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_streamProvider.statusMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              _streamProvider.statusMessage,
              style:
                  TextStyle(fontSize: 11, color: const Color(0xFFEF4444)),
            ),
          ],
        ],
      ),
    );
  }

  // ── 角色预览 ──
  Widget _buildCharacterPreview(ShadTheme shad) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: shad.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: shad.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '角色预览',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: shad.mutedForeground),
              ),
            ),
            Expanded(
              child: Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  final use3D = settings.settings.use3D;
                  if (use3D) {
                    final vrmModel = settings.settings.selectedVRMModel;
                    if (vrmModel != null && vrmModel.isNotEmpty) {
                      return VrmView(
                        modelPath: vrmModel,
                        positionX: 50,
                        positionY: 50,
                        scale: 0.8,
                      );
                    }
                  } else {
                    final live2dModel =
                        settings.settings.selectedLive2DModel;
                    if (live2dModel != null && live2dModel.isNotEmpty) {
                      return Live2DView(
                        modelPath: live2dModel,
                        positionX: 50,
                        positionY: 45,
                        scale: 0.12,
                        interactive: false,
                      );
                    }
                  }
                  return Center(
                    child: Text(
                      use3D ? '未选择VRM模型' : '未选择Live2D模型',
                      style: TextStyle(
                          fontSize: 12, color: shad.mutedForeground),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 控制面板 ──
  Widget _buildControls(ShadTheme shad) {
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
          Text('直播控制',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: shad.foreground)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _streamProvider.isConnected
                  ? () => _streamProvider
                      .triggerReply('请对观众们说点什么吧~')
                  : null,
              icon: const Icon(Icons.chat, size: 16),
              label: const Text('手动触发AI回复'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'OBS/Bilibili直播姬 窗口捕获即可将角色画面推流到直播间',
            style: TextStyle(
                fontSize: 10, color: shad.mutedForeground, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── 弹幕消息列表 ──
  Widget _buildChatList(ShadTheme shad) {
    final messages = _streamProvider.messages;
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
                  '直播弹幕',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: shad.foreground),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: shad.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${messages.length}',
                    style: TextStyle(fontSize: 11, color: shad.primary),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: shad.border),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      _streamProvider.isConnected
                          ? '等待弹幕中...'
                          : '连接直播间后显示弹幕',
                      style: TextStyle(
                          fontSize: 13, color: shad.mutedForeground),
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
                      style: TextStyle(color: shad.mutedForeground)),
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
                  '直播流程 Setlist',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: shad.foreground),
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
                        Icon(Icons.queue_music,
                            size: 36,
                            color: shad.mutedForeground.withAlpha(100)),
                        const SizedBox(height: 8),
                        Text('点击 + 添加直播节点',
                            style: TextStyle(
                                fontSize: 12,
                                color: shad.mutedForeground)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: setlist.length,
                    itemBuilder: (context, index) {
                      final item = setlist[index];
                      final isCurrent = isRunning &&
                          _streamProvider.currentNodeIndex == index;
                      return _buildSetlistItem(
                          item, index, isCurrent, shad);
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
                      size: 18),
                  label: Text(isRunning ? '停止流程' : '开始流程'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRunning
                        ? const Color(0xFFEF4444)
                        : shad.primary,
                    foregroundColor: Colors.white,
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
      itemBuilder: (context) =>
          StreamNodeDefinition.registry.entries.map((e) {
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

  Widget _buildSetlistItem(StreamSetlistItem item, int index,
      bool isCurrent, ShadTheme shad) {
    final def = item.nodeDef;
    final name = def?.name ?? item.nodeType.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isCurrent ? shad.primary.withAlpha(20) : null,
        borderRadius: BorderRadius.circular(6),
        border:
            isCurrent ? Border.all(color: shad.primary, width: 1.5) : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showNodeSettingsDialog(item, index, shad),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(_getNodeIcon(item.nodeType),
                  size: 16, color: shad.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$name ${isCurrent ? "◀ 进行中" : ""}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent ? shad.primary : shad.foreground,
                  ),
                ),
              ),
              if (!_streamProvider.isSetlistRunning)
                GestureDetector(
                  onTap: () =>
                      _streamProvider.moveSetlistNode(index, -1),
                  child: Icon(Icons.arrow_upward,
                      size: 14,
                      color: index == 0
                          ? shad.mutedForeground.withAlpha(60)
                          : shad.mutedForeground),
                ),
              if (!_streamProvider.isSetlistRunning)
                GestureDetector(
                  onTap: () =>
                      _streamProvider.moveSetlistNode(index, 1),
                  child: Icon(Icons.arrow_downward,
                      size: 14,
                      color: index ==
                              _streamProvider.setlist.length - 1
                          ? shad.mutedForeground.withAlpha(60)
                          : shad.mutedForeground),
                ),
              if (!_streamProvider.isSetlistRunning)
                GestureDetector(
                  onTap: () =>
                      _streamProvider.removeSetlistNode(index),
                  child: Icon(Icons.close,
                      size: 14, color: shad.mutedForeground),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodeSettingsDialog(
      StreamSetlistItem item, int index, ShadTheme shad) {
    final def = item.nodeDef;
    if (def == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        final settings = Map<String, dynamic>.from(item.settings);
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text('${def.name} 设置',
                  style: TextStyle(color: shad.foreground)),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (def.presets.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: '预设',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        value: null,
                        hint: const Text('选择预设...',
                            style: TextStyle(fontSize: 13)),
                        items: def.presets.keys.map((key) {
                          return DropdownMenuItem(
                              value: key, child: Text(key));
                        }).toList(),
                        onChanged: (presetKey) {
                          if (presetKey != null &&
                              def.presets.containsKey(presetKey)) {
                            settings
                                .addAll(def.presets[presetKey]!);
                            setDialogState(() {});
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...def.defaultSettings.keys.map((key) {
                      final value =
                          settings[key] ?? def.defaultSettings[key];
                      if (value is String) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: TextEditingController(
                                text: value),
                            decoration: InputDecoration(
                              labelText: key,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
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
                                text: value.toString()),
                            decoration: InputDecoration(
                              labelText: key,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 13),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final num = int.tryParse(v) ??
                                  double.tryParse(v);
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
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    _streamProvider.updateNodeSettings(
                      index,
                      StreamSetlistItem(
                          nodeType: item.nodeType,
                          settings: settings),
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('确定'),
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
