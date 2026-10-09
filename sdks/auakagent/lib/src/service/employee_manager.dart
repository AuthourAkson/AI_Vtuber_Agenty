import 'dart:async';

import '../persistence/persistence.dart';
import '../utils/logger.dart';

/// 员工变更类型
enum EmployeeChangeType { created, updated, deleted }

/// 员工变更事件
class EmployeeChangeEvent {
  final EmployeeChangeType type;
  final String employeeId;
  final AiEmployeeEntity? employee;

  EmployeeChangeEvent({
    required this.type,
    required this.employeeId,
    this.employee,
  });
}

/// 员工统计信息
class EmployeeStats {
  final int totalCount;
  final int activeCount;
  final int pinnedCount;

  EmployeeStats({
    required this.totalCount,
    required this.activeCount,
    required this.pinnedCount,
  });
}

/// 员工管理器接口
abstract class EmployeeManager {
  static final Map<String, EmployeeManager> _instances = {};

  /// 按 deviceId 获取单例，不存在则自动创建
  static EmployeeManager getInstance(String deviceId) {
    return _instances.putIfAbsent(
      deviceId,
      () => EmployeeManagerImpl(deviceId: deviceId),
    );
  }

  /// 移除指定 deviceId 的实例
  static void removeInstance(String deviceId) => _instances.remove(deviceId);

  /// 获取员工列表
  /// [allDevices] 为 true 时返回所有设备的员工（跨设备同步场景），
  /// 为 false 时仅返回本设备的员工（默认行为）
  /// [includeDeleted] 为 true 时包含已删除的员工（用于跨设备同步场景）
  Future<List<AiEmployeeEntity>> getEmployees({
    String? keyword,
    String? status,
    bool allDevices = false,
    bool includeDeleted = false,
  });

  /// 获取单个员工
  Future<AiEmployeeEntity?> getEmployee(String uuid);

  /// 获取单个员工（包含已删除的，用于同步合并场景）
  Future<AiEmployeeEntity?> getEmployeeIncludingDeleted(String uuid);

  /// 创建员工
  Future<AiEmployeeEntity> createEmployee(AiEmployeeEntity employee);

  /// 保存员工（同步场景使用，不修改 deviceId 和时间戳）
  Future<void> saveEmployee(AiEmployeeEntity employee);

  /// 更新员工
  Future<void> updateEmployee(AiEmployeeEntity employee);

  /// 更新员工当前设备ID（会话漫游）
  Future<void> updateCurrentDeviceId(String uuid, String deviceId);

  /// 删除员工（软删除）
  Future<void> deleteEmployee(String uuid);

  /// 获取员工统计信息
  Future<EmployeeStats> getEmployeeStats();

  /// 员工变更通知流
  Stream<EmployeeChangeEvent> get onEmployeeEvent;
}

/// 员工管理器实现
class EmployeeManagerImpl implements EmployeeManager {
  final EmployeeStore _store;
  final String _deviceId;
  final _changeController = StreamController<EmployeeChangeEvent>.broadcast();
  static final _log = Logger('EmployeeManager');

  EmployeeManagerImpl({
    EmployeeStore? store,
    String deviceId = 'default',
  })  : _store = store ?? EmployeeStore(deviceId: deviceId),
        _deviceId = deviceId;

  @override
  Future<List<AiEmployeeEntity>> getEmployees({
    String? keyword,
    String? status,
    bool allDevices = false,
    bool includeDeleted = false,
  }) async {
    return _store.findAll(
      allDevices ? null : _deviceId,
      keyword: keyword,
      status: status,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<AiEmployeeEntity?> getEmployee(String uuid) async {
    return _store.find(null, uuid);
  }

  @override
  Future<AiEmployeeEntity?> getEmployeeIncludingDeleted(String uuid) async {
    return _store.findIncludingDeleted(uuid);
  }

  @override
  Future<AiEmployeeEntity> createEmployee(AiEmployeeEntity employee) async {
    final now = DateTime.now();
    _log.info('[createEmployee] 入参: name=${employee.name}, '
        'currentDeviceId=${employee.currentDeviceId}, '
        'deviceId=${employee.deviceId}, '
        '_deviceId(本设备)=$_deviceId');
    final newEmployee = employee.copyWith(
      deviceId: employee.deviceId ?? _deviceId,
      currentDeviceId: employee.currentDeviceId ?? employee.deviceId ?? _deviceId,
      createTime: now,
      updateTime: now,
    );
    _log.info('[createEmployee] 处理后: name=${newEmployee.name}, '
        'currentDeviceId=${newEmployee.currentDeviceId}, '
        'deviceId=${newEmployee.deviceId}');
    await _store.save(newEmployee);
    _notifyChange(EmployeeChangeType.created, newEmployee);
    return newEmployee;
  }

  @override
  Future<void> saveEmployee(AiEmployeeEntity employee) async {
    final existing = await _store.find(null, employee.uuid);
    await _store.save(employee);
    if (existing != null) {
      _notifyChange(EmployeeChangeType.updated, employee);
    } else {
      _notifyChange(EmployeeChangeType.created, employee);
    }
  }

  @override
  Future<void> updateEmployee(AiEmployeeEntity employee) async {
    final updated = employee.copyWith(updateTime: DateTime.now());
    await _store.save(updated);
    _notifyChange(EmployeeChangeType.updated, updated);
  }

  @override
  Future<void> updateCurrentDeviceId(String uuid, String deviceId) async {
    final employee = await getEmployee(uuid);
    if (employee == null) return;

    final updated = employee.copyWith(
      currentDeviceId: deviceId,
      updateTime: DateTime.now(),
    );
    await _store.save(updated);
    _notifyChange(EmployeeChangeType.updated, updated);
  }

  @override
  Future<void> deleteEmployee(String uuid) async {
    await _store.delete(_deviceId, uuid);
    _notifyChange(EmployeeChangeType.deleted, uuid);
  }

  @override
  Future<EmployeeStats> getEmployeeStats() async {
    final all = await _store.findAll(_deviceId);
    final active = all.where((e) => e.status == 'active').toList();
    final pinned = all.where((e) => e.isPinned == 1).toList();
    return EmployeeStats(
      totalCount: all.length,
      activeCount: active.length,
      pinnedCount: pinned.length,
    );
  }

  @override
  Stream<EmployeeChangeEvent> get onEmployeeEvent => _changeController.stream;

  void _notifyChange(EmployeeChangeType type, dynamic employeeOrUuid) {
    if (employeeOrUuid is AiEmployeeEntity) {
      _changeController.add(
        EmployeeChangeEvent(
          type: type,
          employeeId: employeeOrUuid.uuid,
          employee: employeeOrUuid,
        ),
      );
    } else if (employeeOrUuid is String) {
      _changeController.add(
        EmployeeChangeEvent(type: type, employeeId: employeeOrUuid),
      );
    }
  }

  /// 释放资源
  void dispose() {
    _changeController.close();
  }
}
