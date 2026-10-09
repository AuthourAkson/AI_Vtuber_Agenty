import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/employee_manager.dart';

int _testCounter = 0;

/// EmployeeManager CRUD + Event 全方位测试
///
/// 验证：
/// 1. createEmployee — 自动设置时间戳、deviceId 回退、触发 created 事件
/// 2. updateEmployee — 自动刷新 updateTime、触发 updated 事件
/// 3. deleteEmployee — 软删除、触发 deleted 事件（event.employee == null）
/// 4. saveEmployee — 新员工触发 created、已有员工触发 updated
/// 5. getEmployees — deviceId 过滤、allDevices、includeDeleted
/// 6. getEmployee / getEmployeeIncludingDeleted — 删除态过滤
/// 7. updateCurrentDeviceId — 会话漫游字段更新
/// 8. getEmployeeStats — totalCount / activeCount / pinnedCount
/// 9. onEmployeeEvent — 事件序列与载荷验证
/// 10. 多步操作序列 — create → update → delete 全链路事件追踪
void main() {
  late String testDbPath;
  late String deviceId;
  late EmployeeManager manager;

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_employee_manager_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);

    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';

    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: testDbPath,
    );

    manager = EmployeeManager.getInstance(deviceId);
  });

  tearDown(() async {
    (manager as EmployeeManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceId).close();
    DatabaseManager.removeInstance(deviceId);
    EmployeeManager.removeInstance(deviceId);
    try {
      await Directory(testDbPath).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  AiEmployeeEntity buildEmployee({
    String? uuid,
    String? name,
    String? deviceId,
    String? description,
    String? systemPrompt,
    String? provider,
    String? model,
    String? apiKey,
    String? apiBaseUrl,
    String status = 'active',
    int deleted = 0,
    DateTime? deletedTime,
    int isPinned = 0,
    int sortOrder = 0,
    int autoApprove = 0,
    int enableTools = 1,
    int enableMcp = 0,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    final now = DateTime.now();
    return AiEmployeeEntity(
      uuid: uuid ?? const Uuid().v4(),
      name: name ?? '测试员工',
      deviceId: deviceId,
      description: description,
      systemPrompt: systemPrompt,
      provider: provider,
      model: model,
      apiKey: apiKey,
      apiBaseUrl: apiBaseUrl,
      status: status,
      deleted: deleted,
      deletedTime: deletedTime,
      isPinned: isPinned,
      sortOrder: sortOrder,
      autoApprove: autoApprove,
      enableTools: enableTools,
      enableMcp: enableMcp,
      createTime: createTime ?? now,
      updateTime: updateTime ?? now,
    );
  }

  /// 收集事件的辅助方法：监听 [duration] 毫秒内的事件并返回
  Future<List<EmployeeChangeEvent>> collectEvents(
    EmployeeManager mgr,
    Future<void> Function() action, {
    int duration = 100,
  }) async {
    final events = <EmployeeChangeEvent>[];
    final sub = mgr.onEmployeeEvent.listen(events.add);
    await action();
    await Future<void>.delayed(Duration(milliseconds: duration));
    await sub.cancel();
    return events;
  }

  // ═══════════════════════════════════════════════════
  // 1. createEmployee
  // ═══════════════════════════════════════════════════

  group('createEmployee', () {
    test('自动设置 createTime 和 updateTime', () async {
      final before = DateTime.now();
      final emp = buildEmployee(name: '时间戳测试');
      final created = await manager.createEmployee(emp);

      expect(
        created.createTime.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
      expect(
        created.updateTime.millisecondsSinceEpoch,
        greaterThanOrEqualTo(before.millisecondsSinceEpoch),
      );
    });

    test('deviceId 为 null 时回退到 manager 的 deviceId', () async {
      final emp = buildEmployee(name: '无设备ID', deviceId: null);
      final created = await manager.createEmployee(emp);

      expect(created.deviceId, equals(deviceId));
    });

    test('deviceId 已指定时不被覆盖', () async {
      final emp = buildEmployee(name: '指定设备', deviceId: 'dev-custom');
      final created = await manager.createEmployee(emp);

      expect(created.deviceId, equals('dev-custom'));
    });

    test('触发 created 事件，包含完整 employee', () async {
      final emp = buildEmployee(name: '事件验证');
      final events = await collectEvents(manager, () => manager.createEmployee(emp));

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.created));
      expect(events.first.employeeId, equals(emp.uuid));
      expect(events.first.employee, isNotNull);
      expect(events.first.employee!.name, equals('事件验证'));
      expect(events.first.employee!.uuid, equals(emp.uuid));
    });

    test('创建后可通过 getEmployee 查询到', () async {
      final emp = buildEmployee(name: '可查询');
      await manager.createEmployee(emp);

      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('可查询'));
    });

    test('创建后出现在 getEmployees 列表中', () async {
      await manager.createEmployee(buildEmployee(name: '列表员工'));

      final list = await manager.getEmployees();
      expect(list.length, equals(1));
      expect(list.first.name, equals('列表员工'));
    });

    test('连续创建多个员工均触发独立事件', () async {
      final events = <EmployeeChangeEvent>[];
      final sub = manager.onEmployeeEvent.listen(events.add);

      await manager.createEmployee(buildEmployee(name: '员工A'));
      await manager.createEmployee(buildEmployee(name: '员工B'));
      await manager.createEmployee(buildEmployee(name: '员工C'));

      await Future<void>.delayed(Duration(milliseconds: 100));
      await sub.cancel();

      expect(events.length, equals(3));
      expect(events.every((e) => e.type == EmployeeChangeType.created), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════
  // 2. updateEmployee
  // ═══════════════════════════════════════════════════

  group('updateEmployee', () {
    test('自动刷新 updateTime', () async {
      final emp = buildEmployee(
        name: '更新前',
        updateTime: DateTime(2024, 1, 1),
      );
      await manager.createEmployee(emp);

      final beforeUpdate = DateTime.now();
      await manager.updateEmployee(emp.copyWith(name: '更新后'));

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.name, equals('更新后'));
      expect(
        found.updateTime.millisecondsSinceEpoch,
        greaterThanOrEqualTo(beforeUpdate.millisecondsSinceEpoch),
      );
    });

    test('createTime 不被修改', () async {
      final emp = buildEmployee(
        name: '原始',
        createTime: DateTime(2024, 6, 1),
      );
      final created = await manager.createEmployee(emp);

      await manager.updateEmployee(created.copyWith(name: '改名'));

      final found = await manager.getEmployee(emp.uuid);
      expect(
        found!.createTime.millisecondsSinceEpoch,
        equals(created.createTime.millisecondsSinceEpoch),
      );
    });

    test('触发 updated 事件', () async {
      final emp = buildEmployee(name: '待更新');
      await manager.createEmployee(emp);

      final events = await collectEvents(
        manager,
        () => manager.updateEmployee(emp.copyWith(name: '已更新')),
      );

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.updated));
      expect(events.first.employeeId, equals(emp.uuid));
      expect(events.first.employee, isNotNull);
      expect(events.first.employee!.name, equals('已更新'));
    });

    test('更新多个字段全部生效', () async {
      final emp = buildEmployee(
        name: '原始',
        description: '原始描述',
        provider: 'openai',
        model: 'gpt-3.5',
      );
      await manager.createEmployee(emp);

      await manager.updateEmployee(emp.copyWith(
        name: '新名',
        description: '新描述',
        provider: 'claude',
        model: 'claude-3',
      ));

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.name, equals('新名'));
      expect(found.description, equals('新描述'));
      expect(found.provider, equals('claude'));
      expect(found.model, equals('claude-3'));
    });
  });

  // ═══════════════════════════════════════════════════
  // 3. deleteEmployee
  // ═══════════════════════════════════════════════════

  group('deleteEmployee', () {
    test('软删除后 getEmployee 返回 null', () async {
      final emp = buildEmployee(name: '待删除');
      await manager.createEmployee(emp);

      await manager.deleteEmployee(emp.uuid);

      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNull);
    });

    test('软删除后 getEmployeeIncludingDeleted 仍可查到', () async {
      final emp = buildEmployee(name: '待删除');
      await manager.createEmployee(emp);

      await manager.deleteEmployee(emp.uuid);

      final deleted = await manager.getEmployeeIncludingDeleted(emp.uuid);
      expect(deleted, isNotNull);
      expect(deleted!.deleted, equals(1));
      expect(deleted.deletedTime, isNotNull);
    });

    test('触发 deleted 事件，employee 为 null', () async {
      final emp = buildEmployee(name: '删除事件');
      await manager.createEmployee(emp);

      final events = await collectEvents(
        manager,
        () => manager.deleteEmployee(emp.uuid),
      );

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.deleted));
      expect(events.first.employeeId, equals(emp.uuid));
      // deleted 事件不携带 employee 对象
      expect(events.first.employee, isNull);
    });

    test('删除后不出现在 getEmployees 列表中', () async {
      await manager.createEmployee(buildEmployee(name: '保留'));
      final toDelete = buildEmployee(name: '删除');
      await manager.createEmployee(toDelete);

      await manager.deleteEmployee(toDelete.uuid);

      final list = await manager.getEmployees();
      expect(list.length, equals(1));
      expect(list.first.name, equals('保留'));
    });

    test('删除不存在的 uuid 不抛异常', () async {
      // 应静默成功
      await manager.deleteEmployee('non-existent-uuid-12345');
    });
  });

  // ═══════════════════════════════════════════════════
  // 4. saveEmployee（同步场景）
  // ═══════════════════════════════════════════════════

  group('saveEmployee', () {
    test('新员工触发 created 事件', () async {
      final emp = buildEmployee(name: '同步新员工');
      final events = await collectEvents(
        manager,
        () => manager.saveEmployee(emp),
      );

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.created));
      expect(events.first.employeeId, equals(emp.uuid));
    });

    test('已有员工触发 updated 事件', () async {
      final emp = buildEmployee(name: '原员工');
      await manager.saveEmployee(emp);

      final events = await collectEvents(
        manager,
        () => manager.saveEmployee(emp.copyWith(name: '更新员工')),
      );

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.updated));
    });

    test('不修改 createTime 和 updateTime（同步场景保留原始时间戳）', () async {
      final ct = DateTime(2024, 3, 15, 10, 0, 0);
      final ut = DateTime(2024, 3, 16, 14, 30, 0);
      final emp = buildEmployee(name: '时间保留', createTime: ct, updateTime: ut);

      await manager.saveEmployee(emp);

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.createTime.millisecondsSinceEpoch, equals(ct.millisecondsSinceEpoch));
      expect(found.updateTime.millisecondsSinceEpoch, equals(ut.millisecondsSinceEpoch));
    });

    test('不修改 deviceId（同步场景保留远程 deviceId）', () async {
      final emp = buildEmployee(name: '远程设备', deviceId: 'dev-remote');
      await manager.saveEmployee(emp);

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.deviceId, equals('dev-remote'));
    });

    test('连续 saveEmployee 同一 uuid → 第一次 created，后续 updated', () async {
      final emp = buildEmployee(name: 'V1');

      final events1 = await collectEvents(
        manager,
        () => manager.saveEmployee(emp),
      );
      expect(events1.first.type, equals(EmployeeChangeType.created));

      final events2 = await collectEvents(
        manager,
        () => manager.saveEmployee(emp.copyWith(name: 'V2')),
      );
      expect(events2.first.type, equals(EmployeeChangeType.updated));

      final events3 = await collectEvents(
        manager,
        () => manager.saveEmployee(emp.copyWith(name: 'V3')),
      );
      expect(events3.first.type, equals(EmployeeChangeType.updated));
    });
  });

  // ═══════════════════════════════════════════════════
  // 5. getEmployees 过滤
  // ═══════════════════════════════════════════════════

  group('getEmployees', () {
    test('默认仅返回本设备员工', () async {
      await manager.createEmployee(buildEmployee(name: '本机员工'));
      // 通过 store 直接插入其他设备的员工
      final store = EmployeeStore(deviceId: deviceId);
      await store.save(buildEmployee(name: '远程员工', deviceId: 'dev-other'));

      final result = await manager.getEmployees();
      expect(result.length, equals(1));
      expect(result.first.name, equals('本机员工'));
    });

    test('allDevices: true 返回所有设备员工', () async {
      await manager.createEmployee(buildEmployee(name: '本机员工'));
      final store = EmployeeStore(deviceId: deviceId);
      await store.save(buildEmployee(name: '远程员工', deviceId: 'dev-other'));

      final result = await manager.getEmployees(allDevices: true);
      expect(result.length, equals(2));
    });

    test('includeDeleted: false 不返回已删除员工', () async {
      final emp = buildEmployee(name: '待删除');
      await manager.createEmployee(emp);
      await manager.deleteEmployee(emp.uuid);

      final result = await manager.getEmployees(includeDeleted: false);
      expect(result.isEmpty, isTrue);
    });

    test('includeDeleted: true 包含已删除员工', () async {
      await manager.createEmployee(buildEmployee(name: '正常'));
      final toDelete = buildEmployee(name: '待删除');
      await manager.createEmployee(toDelete);
      await manager.deleteEmployee(toDelete.uuid);

      final result = await manager.getEmployees(includeDeleted: true);
      expect(result.length, equals(2));
    });

    test('allDevices + includeDeleted 组合', () async {
      await manager.createEmployee(buildEmployee(name: '本机正常'));
      final toDelete = buildEmployee(name: '本机删除');
      await manager.createEmployee(toDelete);
      await manager.deleteEmployee(toDelete.uuid);

      final store = EmployeeStore(deviceId: deviceId);
      await store.save(buildEmployee(
        name: '远程已删除',
        deviceId: 'dev-other',
        deleted: 1,
        deletedTime: DateTime(2024, 1, 5),
      ));

      final result = await manager.getEmployees(
        allDevices: true,
        includeDeleted: true,
      );
      expect(result.length, equals(3));
    });

    test('keyword 过滤', () async {
      await manager.createEmployee(buildEmployee(name: '张三'));
      await manager.createEmployee(buildEmployee(name: '李四'));
      await manager.createEmployee(buildEmployee(name: '张三丰'));

      final result = await manager.getEmployees(keyword: '张');
      expect(result.length, equals(2));
    });

    test('status 过滤', () async {
      await manager.createEmployee(buildEmployee(status: 'active'));
      await manager.createEmployee(buildEmployee(status: 'inactive'));
      await manager.createEmployee(buildEmployee(status: 'active'));

      final active = await manager.getEmployees(status: 'active');
      expect(active.length, equals(2));

      final inactive = await manager.getEmployees(status: 'inactive');
      expect(inactive.length, equals(1));
    });
  });

  // ═══════════════════════════════════════════════════
  // 6. getEmployee / getEmployeeIncludingDeleted
  // ═══════════════════════════════════════════════════

  group('getEmployee & getEmployeeIncludingDeleted', () {
    test('getEmployee 返回正常员工', () async {
      final emp = buildEmployee(name: '正常');
      await manager.createEmployee(emp);

      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('正常'));
    });

    test('getEmployee 不返回已删除员工', () async {
      final emp = buildEmployee(name: '已删除');
      await manager.createEmployee(emp);
      await manager.deleteEmployee(emp.uuid);

      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNull);
    });

    test('getEmployee 不存在的 uuid 返回 null', () async {
      final found = await manager.getEmployee('non-existent-uuid');
      expect(found, isNull);
    });

    test('getEmployeeIncludingDeleted 返回已删除员工', () async {
      final emp = buildEmployee(name: '已删除');
      await manager.createEmployee(emp);
      await manager.deleteEmployee(emp.uuid);

      final found = await manager.getEmployeeIncludingDeleted(emp.uuid);
      expect(found, isNotNull);
      expect(found!.deleted, equals(1));
      expect(found.deletedTime, isNotNull);
    });

    test('getEmployeeIncludingDeleted 不存在的 uuid 返回 null', () async {
      final found = await manager.getEmployeeIncludingDeleted('non-existent');
      expect(found, isNull);
    });

    test('getEmployeeIncludingDeleted 也返回未删除员工', () async {
      final emp = buildEmployee(name: '正常');
      await manager.createEmployee(emp);

      final found = await manager.getEmployeeIncludingDeleted(emp.uuid);
      expect(found, isNotNull);
      expect(found!.deleted, equals(0));
    });
  });

  // ═══════════════════════════════════════════════════
  // 7. updateCurrentDeviceId
  // ═══════════════════════════════════════════════════

  group('updateCurrentDeviceId', () {
    test('更新 currentDeviceId 字段', () async {
      final emp = buildEmployee(name: '漫游测试');
      await manager.createEmployee(emp);

      await manager.updateCurrentDeviceId(emp.uuid, 'dev-roaming-target');

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.currentDeviceId, equals('dev-roaming-target'));
    });

    test('多次更新 currentDeviceId 保留最后一次', () async {
      final emp = buildEmployee(name: '多次漫游');
      await manager.createEmployee(emp);

      await manager.updateCurrentDeviceId(emp.uuid, 'dev-A');
      await manager.updateCurrentDeviceId(emp.uuid, 'dev-B');
      await manager.updateCurrentDeviceId(emp.uuid, 'dev-C');

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.currentDeviceId, equals('dev-C'));
    });

    test('更新 currentDeviceId 触发 updated 事件', () async {
      final emp = buildEmployee(name: '事件漫游');
      await manager.createEmployee(emp);

      final events = await collectEvents(
        manager,
        () => manager.updateCurrentDeviceId(emp.uuid, 'dev-new'),
      );

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.updated));
      expect(events.first.employee!.currentDeviceId, equals('dev-new'));
    });

    test('员工不存在时不报错', () async {
      // 不应抛出异常
      await manager.updateCurrentDeviceId('non-existent-uuid', 'dev-X');
    });

    test('员工不存在时不触发事件', () async {
      final events = await collectEvents(
        manager,
        () => manager.updateCurrentDeviceId('non-existent-uuid', 'dev-X'),
      );

      expect(events.isEmpty, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════
  // 8. getEmployeeStats
  // ═══════════════════════════════════════════════════

  group('getEmployeeStats', () {
    test('空数据库返回全零', () async {
      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(0));
      expect(stats.activeCount, equals(0));
      expect(stats.pinnedCount, equals(0));
    });

    test('正确统计 totalCount', () async {
      await manager.createEmployee(buildEmployee(name: 'A'));
      await manager.createEmployee(buildEmployee(name: 'B'));
      await manager.createEmployee(buildEmployee(name: 'C'));

      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(3));
    });

    test('正确统计 activeCount（仅 status=active）', () async {
      await manager.createEmployee(buildEmployee(name: 'A', status: 'active'));
      await manager.createEmployee(buildEmployee(name: 'B', status: 'active'));
      await manager.createEmployee(buildEmployee(name: 'C', status: 'inactive'));

      final stats = await manager.getEmployeeStats();
      expect(stats.activeCount, equals(2));
    });

    test('正确统计 pinnedCount（仅 isPinned=1）', () async {
      await manager.createEmployee(buildEmployee(name: 'A', isPinned: 1));
      await manager.createEmployee(buildEmployee(name: 'B', isPinned: 0));
      await manager.createEmployee(buildEmployee(name: 'C', isPinned: 1));

      final stats = await manager.getEmployeeStats();
      expect(stats.pinnedCount, equals(2));
    });

    test('不统计其他设备的员工', () async {
      await manager.createEmployee(buildEmployee(name: '本机'));
      final store = EmployeeStore(deviceId: deviceId);
      await store.save(buildEmployee(name: '远程', deviceId: 'dev-other'));

      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(1));
    });

    test('不统计已删除员工', () async {
      await manager.createEmployee(buildEmployee(name: '保留'));
      final toDelete = buildEmployee(name: '删除');
      await manager.createEmployee(toDelete);
      await manager.deleteEmployee(toDelete.uuid);

      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(1));
      expect(stats.activeCount, equals(1));
    });

    test('综合统计', () async {
      await manager.createEmployee(
        buildEmployee(name: 'A', status: 'active', isPinned: 1),
      );
      await manager.createEmployee(
        buildEmployee(name: 'B', status: 'active', isPinned: 0),
      );
      await manager.createEmployee(
        buildEmployee(name: 'C', status: 'inactive', isPinned: 1),
      );
      await manager.createEmployee(
        buildEmployee(name: 'D', status: 'active', isPinned: 0),
      );

      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(4));
      expect(stats.activeCount, equals(3)); // A, B, D
      expect(stats.pinnedCount, equals(2)); // A, C
    });
  });

  // ═══════════════════════════════════════════════════
  // 9. onEmployeeEvent 事件序列
  // ═══════════════════════════════════════════════════

  group('onEmployeeEvent', () {
    test('created 事件包含完整 employee 载荷', () async {
      final emp = buildEmployee(
        name: '载荷测试',
        provider: 'openai',
        model: 'gpt-4',
      );
      final events = await collectEvents(
        manager,
        () => manager.createEmployee(emp),
      );

      final event = events.single;
      expect(event.type, equals(EmployeeChangeType.created));
      expect(event.employeeId, equals(emp.uuid));
      expect(event.employee, isNotNull);
      expect(event.employee!.name, equals('载荷测试'));
      expect(event.employee!.provider, equals('openai'));
      expect(event.employee!.model, equals('gpt-4'));
    });

    test('updated 事件包含更新后的 employee 载荷', () async {
      final emp = buildEmployee(name: '原始');
      await manager.createEmployee(emp);

      final events = await collectEvents(
        manager,
        () => manager.updateEmployee(emp.copyWith(name: '更新后')),
      );

      final event = events.single;
      expect(event.type, equals(EmployeeChangeType.updated));
      expect(event.employee!.name, equals('更新后'));
    });

    test('deleted 事件不包含 employee', () async {
      final emp = buildEmployee(name: '待删');
      await manager.createEmployee(emp);

      final events = await collectEvents(
        manager,
        () => manager.deleteEmployee(emp.uuid),
      );

      final event = events.single;
      expect(event.type, equals(EmployeeChangeType.deleted));
      expect(event.employeeId, equals(emp.uuid));
      expect(event.employee, isNull);
    });

    test('多个监听者均收到事件', () async {
      final events1 = <EmployeeChangeEvent>[];
      final events2 = <EmployeeChangeEvent>[];
      final sub1 = manager.onEmployeeEvent.listen(events1.add);
      final sub2 = manager.onEmployeeEvent.listen(events2.add);

      await manager.createEmployee(buildEmployee(name: '广播'));

      await Future<void>.delayed(Duration(milliseconds: 100));
      await sub1.cancel();
      await sub2.cancel();

      expect(events1.length, equals(1));
      expect(events2.length, equals(1));
      expect(events1.first.employeeId, equals(events2.first.employeeId));
    });
  });

  // ═══════════════════════════════════════════════════
  // 10. 多步操作序列（create → update → delete）
  // ═══════════════════════════════════════════════════

  group('多步操作序列', () {
    test('create → update → delete 全链路事件追踪', () async {
      final events = <EmployeeChangeEvent>[];
      final sub = manager.onEmployeeEvent.listen(events.add);

      final emp = buildEmployee(name: '链路测试');
      final created = await manager.createEmployee(emp);

      await manager.updateEmployee(created.copyWith(name: '链路更新'));

      await manager.deleteEmployee(emp.uuid);

      await Future<void>.delayed(Duration(milliseconds: 100));
      await sub.cancel();

      expect(events.length, equals(3));
      expect(events[0].type, equals(EmployeeChangeType.created));
      expect(events[0].employee!.name, equals('链路测试'));
      expect(events[1].type, equals(EmployeeChangeType.updated));
      expect(events[1].employee!.name, equals('链路更新'));
      expect(events[2].type, equals(EmployeeChangeType.deleted));
      expect(events[2].employee, isNull);
      expect(events[2].employeeId, equals(emp.uuid));
    });

    test('create → delete → 重新 saveEmployee（模拟同步恢复）', () async {
      final emp = buildEmployee(name: '恢复测试');
      await manager.createEmployee(emp);

      // 删除
      await manager.deleteEmployee(emp.uuid);
      expect(await manager.getEmployee(emp.uuid), isNull);

      // 通过 saveEmployee 恢复（同步场景中远程未删除的数据覆盖本地）
      final restored = emp.copyWith(
        deleted: 0,
        deletedTime: null,
        name: '恢复后',
        updateTime: DateTime.now(),
      );
      await manager.saveEmployee(restored);

      // 注意：由于 copyWith 无法清除 deletedTime，实际 saveEmployee
      // 保存的实体 deletedTime 仍不为 null，但 deleted=0。
      // 在真实同步中，fromMap 构造的实体会正确设置 deletedTime=null。
      // 此处验证 saveEmployee 的基本行为：upsert 后数据可查。
      final found = await manager.getEmployeeIncludingDeleted(emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('恢复后'));
    });

    test('多次 update 后 delete，中间状态均通过事件通知', () async {
      final events = <EmployeeChangeEvent>[];
      final sub = manager.onEmployeeEvent.listen(events.add);

      final emp = buildEmployee(name: 'V0');
      final created = await manager.createEmployee(emp);

      await manager.updateEmployee(created.copyWith(name: 'V1'));
      await manager.updateEmployee(created.copyWith(name: 'V2'));
      await manager.updateEmployee(created.copyWith(name: 'V3'));
      await manager.deleteEmployee(emp.uuid);

      await Future<void>.delayed(Duration(milliseconds: 100));
      await sub.cancel();

      // 1 created + 3 updated + 1 deleted = 5
      expect(events.length, equals(5));
      expect(events[0].type, equals(EmployeeChangeType.created));
      expect(events[1].type, equals(EmployeeChangeType.updated));
      expect(events[2].type, equals(EmployeeChangeType.updated));
      expect(events[3].type, equals(EmployeeChangeType.updated));
      expect(events[4].type, equals(EmployeeChangeType.deleted));
    });

    test('create 多个员工后 getEmployees 返回全部', () async {
      final names = ['员工A', '员工B', '员工C', '员工D'];
      for (final name in names) {
        await manager.createEmployee(buildEmployee(name: name));
      }

      final list = await manager.getEmployees();
      expect(list.length, equals(4));

      final listNames = list.map((e) => e.name).toSet();
      for (final name in names) {
        expect(listNames.contains(name), isTrue);
      }
    });

    test('create → update → 验证最终状态一致性', () async {
      final emp = buildEmployee(
        name: '初始',
        description: '初始描述',
        systemPrompt: '初始提示词',
        provider: 'openai',
        model: 'gpt-3.5',
        apiKey: 'sk-old',
        apiBaseUrl: 'https://old.api.com',
        enableTools: 1,
        enableMcp: 0,
        autoApprove: 0,
        sortOrder: 0,
        isPinned: 0,
      );
      final created = await manager.createEmployee(emp);

      await manager.updateEmployee(created.copyWith(
        name: '最终',
        description: '最终描述',
        systemPrompt: '最终提示词',
        provider: 'claude',
        model: 'claude-3',
        apiKey: 'sk-new',
        apiBaseUrl: 'https://new.api.com',
        enableTools: 0,
        enableMcp: 1,
        autoApprove: 1,
        sortOrder: 10,
        isPinned: 1,
      ));

      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('最终'));
      expect(found.description, equals('最终描述'));
      expect(found.systemPrompt, equals('最终提示词'));
      expect(found.provider, equals('claude'));
      expect(found.model, equals('claude-3'));
      expect(found.apiKey, equals('sk-new'));
      expect(found.apiBaseUrl, equals('https://new.api.com'));
      expect(found.enableTools, equals(0));
      expect(found.enableMcp, equals(1));
      expect(found.autoApprove, equals(1));
      expect(found.sortOrder, equals(10));
      expect(found.isPinned, equals(1));
      // uuid 和 deviceId 不变
      expect(found.uuid, equals(emp.uuid));
      expect(found.deviceId, equals(deviceId));
    });
  });

  // ═══════════════════════════════════════════════════
  // 额外：getInstance 单例行为
  // ═══════════════════════════════════════════════════

  group('getInstance', () {
    test('相同 deviceId 返回同一实例', () {
      final a = EmployeeManager.getInstance(deviceId);
      final b = EmployeeManager.getInstance(deviceId);
      expect(identical(a, b), isTrue);
    });

    test('不同 deviceId 返回不同实例', () {
      final a = EmployeeManager.getInstance('dev-X');
      final b = EmployeeManager.getInstance('dev-Y');
      expect(identical(a, b), isFalse);
    });

    test('removeInstance 后重新获取为新实例', () {
      final original = EmployeeManager.getInstance('dev-remove-test');
      EmployeeManager.removeInstance('dev-remove-test');
      final recreated = EmployeeManager.getInstance('dev-remove-test');
      expect(identical(original, recreated), isFalse);
    });
  });
}
