import 'dart:async';

import '../../service/service.dart';
import '../../persistence/persistence.dart';
import '../../utils/logger.dart';
import '../app_context.dart';
import '../device_client.dart';
import 'device_agent_manager.dart';
import 'device_registry.dart';
import 'device_state_holder.dart';

/// 员工在线状态追踪器
///
/// 负责维护员工在线状态缓存并发布变化事件。
class EmployeeOnlineTracker {
  static final _log = Logger('EmployeeOnlineTracker');

  final String _deviceId;
  late final EmployeeManager _employeeManager = EmployeeManager.getInstance(_deviceId);
  late final DeviceAgentManager _agentManager = DeviceAgentManager.getInstance(_deviceId);
  late final DeviceRegistry _deviceRegistry = DeviceRegistry.getInstance(_deviceId);
  late final DeviceStateHolder _stateHolder = DeviceStateHolder.getInstance(_deviceId);

  final Map<String, bool> _employeeOnlineState = {};
  final Map<String, String> _employeeDeviceMap = {};

  StreamSubscription<EmployeeChangeEvent>? _employeeEventSub;
  bool _started = false;

  EmployeeOnlineTracker._({required String deviceId}) : _deviceId = deviceId;

  // ===== 单例管理 =====

  static final Map<String, EmployeeOnlineTracker> _instances = {};

  /// 从 [AppContext] 获取实例，不存在则回退到独立创建
  static EmployeeOnlineTracker getInstance(String deviceId) {
    final ctx = AppContext.get(deviceId);
    if (ctx != null) {
      _log.info('[getInstance] 从 AppContext 获取, deviceId=$deviceId');
      return ctx.onlineTracker;
    }
    return _instances.putIfAbsent(
      deviceId,
      () {
        _log.info('[getInstance] 新建实例, deviceId=$deviceId (无 AppContext)');
        return EmployeeOnlineTracker._(deviceId: deviceId);
      },
    );
  }

  static void removeInstance(String deviceId) {
    _log.info('[removeInstance] deviceId=$deviceId');
    final tracker = _instances.remove(deviceId);
    tracker?._dispose();
  }

  void _dispose() {
    _employeeEventSub?.cancel();
    _employeeEventSub = null;
    _started = false;
    _employeeOnlineState.clear();
    _employeeDeviceMap.clear();
  }

  // ===== 公开访问 =====

  bool? isEmployeeOnline(String employeeId) {
    final result = _employeeOnlineState[employeeId];
    _log.info('[isEmployeeOnline] empId=${employeeId.substring(0,8)}... '
        'result=$result, mapSize=${_employeeOnlineState.length}, '
        'keys=${_employeeOnlineState.keys.map((k) => k.substring(0,8)).toList()}');
    return result;
  }

  /// 启动员工事件监听（在 DeviceClient 初始化完成后调用）
  ///
  /// 监听 [EmployeeManager.onEmployeeEvent]，在员工创建/更新后自动刷新在线状态，
  /// 解决新建员工或切换设备后在线状态不更新的问题。
  void startListening() {
    if (_started) {
      _log.info('[startListening] 已启动，跳过, deviceId=$_deviceId');
      return;
    }
    _started = true;
    _log.info('[startListening] 启动事件监听, deviceId=$_deviceId');
    _employeeEventSub = _employeeManager.onEmployeeEvent.listen(_onEmployeeChanged);
  }

  /// 处理员工变更事件：先同步设置单个员工状态，再后台全量刷新兜底
  ///
  /// 关键优化：创建/更新员工时立即（同步）判定该员工的在线状态，
  /// 不等异步全量刷新完成。消除 UI 首帧显示离线的闪烁问题。
  void _onEmployeeChanged(EmployeeChangeEvent event) {
    _log.info('[onEmployeeChanged] type=${event.type.name}, '
        'empId=${event.employeeId.substring(0,8)}..., '
        'hasEmployee=${event.employee != null}');
    if (event.employee != null) {
      _log.info('[onEmployeeChanged] employee fields: '
          'currentDeviceId=${event.employee!.currentDeviceId}, '
          'deviceId=${event.employee!.deviceId}');
      // 立即同步设置该员工的在线状态（创建/更新都生效）
      _setSingleEmployeeOnlineState(event.employee!);
    } else {
      _log.info('[onEmployeeChanged] employee=null, 跳过单员工设置');
    }
    // 后台全量刷新作为兜底（处理批量同步等场景）
    refreshEmployeeOnlineStates();
  }

  /// 立即设置单个员工的在线状态（同步，无 await）
  void _setSingleEmployeeOnlineState(AiEmployeeEntity employee) {
    // currentDeviceId 优先，为空时回退到 deviceId
    final devId = employee.currentDeviceId ?? employee.deviceId;
    _log.info('[setSingleOnline] empId=${employee.uuid.substring(0,8)}..., '
        'currentDeviceId=${employee.currentDeviceId}, '
        'deviceId=${employee.deviceId}, '
        'devId(实际使用)=$devId, '
        '_deviceId(本设备)=$_deviceId, '
        'isLocal=${devId == _deviceId}');
    if (devId != null && devId.isNotEmpty) {
      _employeeDeviceMap[employee.uuid] = devId;
      final online = devId == _deviceId
          ? true
          : _deviceRegistry.containsDevice(devId);
      _log.info('[setSingleOnline] 设置结果: online=$online, devId=$devId');
      _updateEmployeeOnlineState(employee.uuid, online, devId);
    } else {
      _log.info('[setSingleOnline] devId 为空，跳过设置！(currentDeviceId 和 deviceId 都为 null)');
    }
  }

  /// 刷新所有员工的在线状态（含远程设备上的员工）
  ///
  /// 返回 Future 以便调用方可以 await 完成后再依赖状态结果。
  Future<void> refreshEmployeeOnlineStates() async {
    try {
      final employees = await _employeeManager.getEmployees(allDevices: true);
      _log.info('[refreshAll] 查询到 ${employees.length} 个员工 (allDevices=true)');
      for (final employee in employees) {
        // currentDeviceId 优先，为空时回退到 deviceId
        final devId = employee.currentDeviceId ?? employee.deviceId;
        if (devId != null && devId.isNotEmpty) {
          _employeeDeviceMap[employee.uuid] = devId;
        }
        bool online = false;
        if (devId != null && devId.isNotEmpty) {
          // 本地设备：当前设备在线则员工在线（Agent 是否存活是运行时细节，非在线判断依据）
          // 远程设备：设备在缓存中（已上线）则为在线
          online = devId == _deviceId
              ? true
              : _deviceRegistry.containsDevice(devId);
        }
        _log.info('[refreshAll] empId=${employee.uuid.substring(0,8)}..., '
            'name=${employee.name}, '
            'devId=$devId, online=$online');
        _updateEmployeeOnlineState(employee.uuid, online, devId);
      }
      _log.info('[refreshAll] 完成, onlineMapSize=${_employeeOnlineState.length}');
    } catch (e) {
      _log.debug('refreshEmployeeOnlineStates failed: $e');
    }
  }

  /// 将指定设备的所有员工标记为离线
  void markDeviceEmployeesOffline(String offlineDeviceId) {
    if (offlineDeviceId == _deviceId) return;
    for (final e in Map<String, bool>.from(_employeeOnlineState).entries) {
      if (e.value && _employeeDeviceMap[e.key] == offlineDeviceId) {
        _employeeOnlineState[e.key] = false;
        _stateHolder.employeeOnlineController.add(EmployeeOnlineEvent(
          employeeId: e.key,
          isOnline: false,
          deviceId: offlineDeviceId,
        ));
      }
    }
  }

  /// 将所有远程员工标记为离线（基于完整员工列表，确保远程员工也被覆盖）
  Future<void> markAllRemoteEmployeesOffline() async {
    try {
      final employees = await _employeeManager.getEmployees(allDevices: true);
      for (final employee in employees) {
        final devId = employee.currentDeviceId;
        // 跳过本设备的员工
        if (devId == _deviceId) continue;
        final online = _employeeOnlineState[employee.uuid] ?? false;
        if (online) {
          _employeeOnlineState[employee.uuid] = false;
          _stateHolder.employeeOnlineController.add(
            EmployeeOnlineEvent(employeeId: employee.uuid, isOnline: false),
          );
        }
      }
    } catch (e) {
      _log.debug('markAllRemoteEmployeesOffline failed: $e');
    }
  }

  void _updateEmployeeOnlineState(String empId, bool isOnline, String? devId) {
    final prev = _employeeOnlineState[empId];
    if (prev != isOnline) {
      _log.info('[updateState] empId=${empId.substring(0,8)}..., '
          'prev=$prev → new=$isOnline, devId=$devId');
      _employeeOnlineState[empId] = isOnline;
      _stateHolder.employeeOnlineController.add(EmployeeOnlineEvent(
        employeeId: empId,
        isOnline: isOnline,
        deviceId: devId,
      ));
    } else {
      _log.info('[updateState] empId=${empId.substring(0,8)}..., '
          '状态未变: $isOnline, devId=$devId');
    }
  }
}
