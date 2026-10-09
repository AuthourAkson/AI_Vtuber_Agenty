import '../agent/agent_state.dart';
import '../agent/tool/permission_manager.dart';
import '../agent/tool/permission_rule.dart';

/// 权限转发器
///
/// 将 sub-agent 的工具权限请求转发到主 agent 的 PermissionManager 处理。
/// 用于定时任务执行场景：sub-agent 需要执行工具时，权限请求通过主 agent
/// 通知用户，用户批准/拒绝后结果回传给 sub-agent。
///
/// 继承 [ToolPermissionManager] 的规则引擎逻辑，仅替换用户确认回调为转发回调。
/// 当提供 [parentConfig] 时，继承的 checkPermission() 会先在本地评估规则，
/// 仅在本地规则未匹配时才通过 onPermissionRequest 转发到父级。
class PermissionForwarder extends ToolPermissionManager {
  /// 权限请求转发回调
  ///
  /// 由 ScheduledTaskManager 注入，将请求通过主 agent 发送给用户。
  Future<PermissionDecision> Function(AgentPermissionRequest request)?
      onForwardPermissionRequest;

  PermissionForwarder({PermissionConfig? parentConfig}) {
    // 如果提供了父级配置，先配置规则引擎使本地规则生效
    if (parentConfig != null) {
      configure(parentConfig);
    }
    // 将权限请求转发到主 agent，而非直接回调用户
    onPermissionRequest = (request) async {
      if (onForwardPermissionRequest == null) {
        return PermissionDecision.deny;
      }
      return onForwardPermissionRequest!(request);
    };
  }
}
