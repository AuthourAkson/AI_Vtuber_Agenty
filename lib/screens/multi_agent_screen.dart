import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/multi_agent_provider.dart';
import '../services/wenzagent_service.dart';

/// Multi-agent network screen — browse LAN devices & agents, chat with remote agents.
class MultiAgentScreen extends StatefulWidget {
  const MultiAgentScreen({super.key});

  @override
  State<MultiAgentScreen> createState() => _MultiAgentScreenState();
}

class _MultiAgentScreenState extends State<MultiAgentScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;
    final provider = context.read<MultiAgentProvider>();
    if (!provider.enabled) {
      provider.initIfEnabled(
        storagePath: r'D:\AiVtuber_Agent_profile\wenzagent',
        host: '127.0.0.1',
        port: 9090,
        deviceName: 'AI VTuber',
      );
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MultiAgentProvider>(
      builder: (context, provider, _) {
        return Column(
          children: [
            _buildStatusBar(provider),
            const Divider(height: 1, color: ShadColors.border),
            Expanded(
              child: Row(
                children: [
                  // Left panel: devices + agent list
                  SizedBox(
                    width: 260,
                    child: _buildAgentList(provider),
                  ),
                  const VerticalDivider(width: 1, color: ShadColors.border),
                  // Right panel: chat
                  Expanded(child: _buildChatPanel(provider)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Status Bar ───────────────────────────────────────────

  Widget _buildStatusBar(MultiAgentProvider p) {
    final statusColor = p.connected
        ? const Color(0xFF4CAF50)
        : p.connecting
            ? const Color(0xFFFFC107)
            : const Color(0xFFCF6679);
    final statusIcon = p.connected
        ? Icons.cloud_done
        : p.connecting
            ? Icons.sync
            : Icons.cloud_off;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: ShadColors.card,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Icon(statusIcon, size: 18, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              p.statusMessage,
              style: const TextStyle(fontSize: 13, color: ShadColors.foreground),
            ),
          ),
          if (!p.connected && !p.connecting)
            _miniButton('Connect', Icons.wifi, () => p.connect()),
          if (p.connected)
            _miniButton('Disconnect', Icons.wifi_off, () => p.disconnect()),
          const SizedBox(width: 8),
          _miniButton('Refresh', Icons.refresh, () async {
            await p.refreshDevices();
            await p.refreshSummaries();
          }),
        ],
      ),
    );
  }

  // ─── Agent List (Left Panel) ──────────────────────────────

  String? _selectedDeviceId; // track which device is selected

  Widget _buildAgentList(MultiAgentProvider p) {
    // Filter agents by selected device
    final filteredAgents = _selectedDeviceId == null
        ? p.agentSummaries
        : p.agentSummaries
              .where((a) => a.deviceId == _selectedDeviceId)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Devices header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Text(
                'DEVICES (${p.onlineDevices.length})',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ShadColors.mutedForeground,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (_selectedDeviceId != null)
                GestureDetector(
                  onTap: () => setState(() => _selectedDeviceId = null),
                  child: const Text('Show all',
                      style: TextStyle(fontSize: 10, color: ShadColors.sidebarPrimary)),
                ),
            ],
          ),
        ),
        // Device list
        if (p.onlineDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              'No devices online',
              style: TextStyle(fontSize: 12, color: ShadColors.mutedForeground),
            ),
          )
        else
          ...p.onlineDevices.map((d) => _deviceItem(d, p)),

        const Divider(height: 1, color: ShadColors.border),

        // Agents header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            'AGENTS (${p.agentSummaries.length})',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: ShadColors.mutedForeground,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Agent list
        Expanded(
          child: filteredAgents.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    _selectedDeviceId != null
                        ? 'No agents on this device'
                        : 'No agents available.\nStart a wenzagent server + client on another machine.',
                    style: const TextStyle(fontSize: 12, color: ShadColors.mutedForeground),
                  ),
                )
              : ListView.builder(
                  itemCount: filteredAgents.length,
                  itemBuilder: (_, i) => _agentItem(filteredAgents[i], p),
                ),
        ),
      ],
    );
  }

  Widget _deviceItem(DeviceInfo device, MultiAgentProvider p) {
    final isSelected = _selectedDeviceId == device.deviceId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedDeviceId = isSelected ? null : device.deviceId;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? ShadColors.sidebarAccent : ShadColors.secondary,
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: ShadColors.sidebarPrimary.withAlpha(80))
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.computer, size: 16,
                  color: isSelected ? ShadColors.sidebarPrimary : const Color(0xFF4CAF50)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceName,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? ShadColors.sidebarPrimary : ShadColors.foreground,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      device.deviceId.length > 16
                          ? '${device.deviceId.substring(0, 16)}...'
                          : device.deviceId,
                      style: const TextStyle(fontSize: 11, color: ShadColors.mutedForeground),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentItem(MultiAgentInfo agent, MultiAgentProvider p) {
    final isActive = p.activeEmployeeId == agent.employeeId;
    final statusColor = _agentStatusColor(agent.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: GestureDetector(
        onTap: () => p.openAgent(agent.employeeId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? ShadColors.sidebarAccent : ShadColors.secondary,
            borderRadius: BorderRadius.circular(6),
            border: isActive
                ? Border.all(color: ShadColors.sidebarPrimary.withAlpha(80))
                : null,
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  const Icon(Icons.smart_toy, size: 20, color: ShadColors.foreground),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: ShadColors.secondary, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        color: ShadColors.foreground,
                      ),
                    ),
                    if (agent.latestMessage != null && agent.latestMessage!.isNotEmpty)
                      Text(
                        agent.latestMessage!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: ShadColors.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              if (agent.unreadCount > 0)
                _unreadBadge(agent.unreadCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _unreadBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ShadColors.destructive,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }

  // ─── Chat Panel (Right) ──────────────────────────────────

  Widget _buildChatPanel(MultiAgentProvider p) {
    if (p.activeEmployeeId == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: ShadColors.mutedForeground),
            SizedBox(height: 12),
            Text(
              'Select an agent to start chatting',
              style: TextStyle(fontSize: 14, color: ShadColors.mutedForeground),
            ),
            SizedBox(height: 4),
            Text(
              'Messages are routed through the WenzAgent LAN network',
              style: TextStyle(fontSize: 12, color: ShadColors.mutedForeground),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Agent header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: ShadColors.card,
          child: Row(
            children: [
              const Icon(Icons.smart_toy, size: 18, color: ShadColors.foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.activeEmployeeId!.length >= 12
                      ? 'Agent ${p.activeEmployeeId!.substring(0, 12)}...'
                      : 'Agent ${p.activeEmployeeId}',
                  style: const TextStyle(fontSize: 14, color: ShadColors.foreground),
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _agentStatusColor(p.activeAgentStatus).withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _agentStatusColor(p.activeAgentStatus).withAlpha(80),
                  ),
                ),
                child: Text(
                  p.activeAgentStatus.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _agentStatusColor(p.activeAgentStatus),
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: p.interruptAgent,
                child: const Icon(Icons.stop, size: 18, color: ShadColors.mutedForeground),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: ShadColors.border),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: p.activeMessages.length,
            itemBuilder: (_, i) => _messageBubble(p.activeMessages[i]),
          ),
        ),
        const Divider(height: 1, color: ShadColors.border),
        // Input
        _buildChatInput(p),
      ],
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final role = msg['role'] as String? ?? 'user';
    final content = msg['content'] as String? ?? '';
    final isUser = role == 'user';
    final type = msg['type'] as String? ?? 'text';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: isUser ? ShadColors.sidebarPrimary.withAlpha(30) : ShadColors.secondary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (type == 'functionCall' || type == 'functionResult')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: ShadColors.mutedForeground.withAlpha(30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  type == 'functionCall' ? 'TOOL CALL' : 'TOOL RESULT',
                  style: const TextStyle(fontSize: 9, color: ShadColors.mutedForeground),
                ),
              ),
            Text(
              content,
              style: const TextStyle(fontSize: 14, color: ShadColors.foreground, height: 1.5),
            ),
            // Tool info
            if (msg['toolName'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tool: ${msg['toolName']}',
                  style: const TextStyle(fontSize: 11, color: ShadColors.mutedForeground),
                ),
              ),
            if (msg['toolResult'] != null && msg['toolResult'].toString().isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(60),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  msg['toolResult'].toString(),
                  style: const TextStyle(fontSize: 12, color: ShadColors.mutedForeground),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInput(MultiAgentProvider p) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: ShadColors.card,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageCtrl,
              decoration: const InputDecoration(
                hintText: 'Send message to agent...',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: ShadColors.secondary,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14, color: ShadColors.foreground),
              maxLines: 3,
              minLines: 1,
              onSubmitted: (text) => _send(text, p),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _send(_messageCtrl.text, p),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: ShadColors.sidebarPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _send(String text, MultiAgentProvider p) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _messageCtrl.clear();
    p.sendMessage(trimmed);
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Helpers ──────────────────────────────────────────────

  Widget _miniButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ShadColors.secondary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: ShadColors.mutedForeground),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: ShadColors.mutedForeground)),
          ],
        ),
      ),
    );
  }

  Color _agentStatusColor(String status) {
    switch (status) {
      case 'idle':
        return const Color(0xFF888888);
      case 'processing':
        return const Color(0xFFFFC107);
      case 'streaming':
        return const Color(0xFF4CAF50);
      case 'waitingPermission':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF888888);
    }
  }
}
