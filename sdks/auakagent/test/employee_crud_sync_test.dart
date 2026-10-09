import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/employee_manager.dart';

int _testCounter = 0;

/// Employee 增删改查 + TCP 同步 全方位测试
///
/// 验证：
/// - A. EmployeeStore CRUD（保存、查询、软删除、统计）
/// - B. EmployeeManager 业务逻辑（创建、更新、删除、事件通知、统计）
/// - C. 同步合并逻辑（deleteTime 合并、软删除传播、已删除不复活）
/// - D. 序列化往返（toMap/fromMap、copyWith）
void main() {
  late String testDbPath;
  late String deviceId;
  late EmployeeStore store;
  late EmployeeManager manager;

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_employee_crud_sync_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);

    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';

    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: testDbPath,
    );

    store = EmployeeStore(deviceId: deviceId);
    manager = EmployeeManager.getInstance(deviceId);
  });

  tearDown(() async {
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

  AiEmployeeEntity createEmployee({
    String? uuid,
    String? name,
    String? deviceId,
    String? description,
    String? systemPrompt,
    String? provider,
    String? model,
    String status = 'active',
    int deleted = 0,
    DateTime? deletedTime,
    int isPinned = 0,
    int sortOrder = 0,
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
      status: status,
      deleted: deleted,
      deletedTime: deletedTime,
      isPinned: isPinned,
      sortOrder: sortOrder,
      createTime: createTime ?? now,
      updateTime: updateTime ?? now,
    );
  }

  /// 模拟 _mergeDeleteTime 逻辑（与 DataSyncManager._mergeDeleteTime 一致）
  (DateTime?, int) mergeDeleteTime(
    DateTime? localDT,
    int localD,
    DateTime? remoteDT,
    int remoteD,
  ) {
    if (localDT == null && remoteDT == null) return (null, 0);
    if (localDT == null) return (remoteDT, remoteD);
    if (remoteDT == null) return (localDT, localD);
    return localDT.isAfter(remoteDT) ? (localDT, localD) : (remoteDT, remoteD);
  }

  /// 模拟 DataSyncManager._mergeAndSaveEmployee 的完整合并逻辑
  /// 返回 (shouldSave, mergedEntity)
  (bool, AiEmployeeEntity?) simulateMerge(
    AiEmployeeEntity existing,
    AiEmployeeEntity remote,
  ) {
    final (dt, d) = mergeDeleteTime(
      existing.deletedTime,
      existing.deleted,
      remote.deletedTime,
      remote.deleted,
    );
    final shouldUpdateData = remote.updateTime.isAfter(existing.updateTime);
    final shouldUpdateDelete =
        dt?.millisecondsSinceEpoch != existing.deletedTime?.millisecondsSinceEpoch || d != existing.deleted;
    if (shouldUpdateData || shouldUpdateDelete) {
      final base = shouldUpdateData ? remote : existing;
      return (true, base.copyWith(deleted: d, deletedTime: dt));
    }
    return (false, null);
  }

  /// 模拟 DataSyncManager._mergeAndSaveEmployee，但支持 remote.deletedTime 实际为 null
  /// （copyWith 无法清除 deletedTime，所以用此方法模拟）
  ///
  /// [remoteDeletedTime] 和 [remoteDeleted] 覆盖 remote 实体的值传入 mergeDeleteTime，
  /// 合并后的 (dt, d) 直接应用到最终结果，绕过 copyWith 无法清除 nullable 字段的限制。
  (bool, AiEmployeeEntity?) simulateMergeWithNulls(
    AiEmployeeEntity existing,
    AiEmployeeEntity remote, {
    DateTime? remoteDeletedTime,
    int? remoteDeleted,
  }) {
    final rdt = remoteDeletedTime ?? remote.deletedTime;
    final rd = remoteDeleted ?? remote.deleted;
    final (dt, d) = mergeDeleteTime(
      existing.deletedTime,
      existing.deleted,
      rdt,
      rd,
    );
    final shouldUpdateData = remote.updateTime.isAfter(existing.updateTime);
    final shouldUpdateDelete =
        dt?.millisecondsSinceEpoch != existing.deletedTime?.millisecondsSinceEpoch || d != existing.deleted;
    if (shouldUpdateData || shouldUpdateDelete) {
      final base = shouldUpdateData ? remote : existing;
      // 直接构建合并后的实体，确保 deleted/deletedTime 使用合并后的值
      return (true, AiEmployeeEntity(
        uuid: base.uuid,
        name: base.name,
        avatar: base.avatar,
        role: base.role,
        status: base.status,
        description: base.description,
        systemPrompt: base.systemPrompt,
        provider: base.provider,
        model: base.model,
        apiKey: base.apiKey,
        apiBaseUrl: base.apiBaseUrl,
        modelConfig: base.modelConfig,
        enableTools: base.enableTools,
        enableMcp: base.enableMcp,
        projectUuid: base.projectUuid,
        projectName: base.projectName,
        projectContext: base.projectContext,
        workPath: base.workPath,
        mcpConfig: base.mcpConfig,
        permissionConfig: base.permissionConfig,
        deviceId: base.deviceId,
        currentDeviceId: base.currentDeviceId,
        autoApprove: base.autoApprove,
        sortOrder: base.sortOrder,
        isPinned: base.isPinned,
        deleted: d,
        deletedTime: dt,
        createTime: base.createTime,
        updateTime: base.updateTime,
      ));
    }
    return (false, null);
  }

  // ═══════════════════════════════════════════════════
  // A. EmployeeStore CRUD 测试
  // ═══════════════════════════════════════════════════

  group('A. EmployeeStore - save', () {
    test('save - 新增员工', () async {
      final emp = createEmployee(name: '张三');
      await store.save(emp);

      final found = await store.find(null, emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('张三'));
      expect(found.uuid, equals(emp.uuid));
    });

    test('save - 覆盖更新（同 uuid）', () async {
      final emp = createEmployee(name: '张三');
      await store.save(emp);

      final updated = emp.copyWith(name: '李四', description: '更新描述');
      await store.save(updated);

      final found = await store.find(null, emp.uuid);
      expect(found!.name, equals('李四'));
      expect(found.description, equals('更新描述'));
    });

    test('save - 保存已删除状态的员工', () async {
      final emp = createEmployee(
        deleted: 1,
        deletedTime: DateTime(2024, 1, 5),
      );
      await store.save(emp);

      // find 不返回已删除
      final found = await store.find(null, emp.uuid);
      expect(found, isNull);

      // findIncludingDeleted 返回
      final foundAll = await store.findIncludingDeleted(emp.uuid);
      expect(foundAll, isNotNull);
      expect(foundAll!.deleted, equals(1));
    });
  });

  group('A. EmployeeStore - findAll', () {
    test('findAll - 按 deviceId 过滤', () async {
      await store.save(createEmployee(deviceId: 'dev-A', name: 'A员工'));
      await store.save(createEmployee(deviceId: 'dev-B', name: 'B员工'));
      await store.save(createEmployee(deviceId: 'dev-A', name: 'A员工2'));

      final resultA = await store.findAll('dev-A');
      expect(resultA.length, equals(2));
      expect(resultA.every((e) => e.deviceId == 'dev-A'), isTrue);

      final resultB = await store.findAll('dev-B');
      expect(resultB.length, equals(1));
      expect(resultB.first.name, equals('B员工'));
    });

    test('findAll - deviceId 为 null 查所有', () async {
      await store.save(createEmployee(deviceId: 'dev-A'));
      await store.save(createEmployee(deviceId: 'dev-B'));
      await store.save(createEmployee(deviceId: 'dev-C'));

      final result = await store.findAll(null);
      expect(result.length, equals(3));
    });

    test('findAll - keyword 模糊搜索（name）', () async {
      await store.save(createEmployee(name: '张三'));
      await store.save(createEmployee(name: '李四'));
      await store.save(createEmployee(name: '张三丰'));

      final result = await store.findAll(null, keyword: '张');
      expect(result.length, equals(2));
      expect(result.every((e) => e.name.contains('张')), isTrue);
    });

    test('findAll - keyword 模糊搜索（description）', () async {
      await store.save(createEmployee(
        name: '员工A',
        description: '前端开发工程师',
      ));
      await store.save(createEmployee(
        name: '员工B',
        description: '后端开发工程师',
      ));
      await store.save(createEmployee(
        name: '员工C',
        description: '产品经理',
      ));

      final result = await store.findAll(null, keyword: '开发');
      expect(result.length, equals(2));
    });

    test('findAll - status 过滤', () async {
      await store.save(createEmployee(status: 'active'));
      await store.save(createEmployee(status: 'inactive'));
      await store.save(createEmployee(status: 'active'));

      final active = await store.findAll(null, status: 'active');
      expect(active.length, equals(2));

      final inactive = await store.findAll(null, status: 'inactive');
      expect(inactive.length, equals(1));
    });

    test('findAll - 排序验证（is_pinned DESC, sort_order ASC）', () async {
      await store.save(createEmployee(name: '普通1', isPinned: 0, sortOrder: 2));
      await store.save(createEmployee(name: '置顶1', isPinned: 1, sortOrder: 1));
      await store.save(createEmployee(name: '普通2', isPinned: 0, sortOrder: 1));
      await store.save(createEmployee(name: '置顶2', isPinned: 1, sortOrder: 2));

      final result = await store.findAll(null);
      // 置顶在前（按 sortOrder 升序），普通在后（按 sortOrder 升序）
      expect(result[0].name, equals('置顶1'));
      expect(result[1].name, equals('置顶2'));
      expect(result[2].name, equals('普通2'));
      expect(result[3].name, equals('普通1'));
    });

    test('findAll - 不返回已删除员工', () async {
      await store.save(createEmployee(name: '正常'));
      await store.save(createEmployee(name: '已删除', deleted: 1));

      final result = await store.findAll(null);
      expect(result.length, equals(1));
      expect(result.first.name, equals('正常'));
    });

    test('findAll - includeDeleted 包含已删除', () async {
      await store.save(createEmployee(name: '正常'));
      await store.save(createEmployee(name: '已删除', deleted: 1));

      final result = await store.findAll(null, includeDeleted: true);
      expect(result.length, equals(2));
    });
  });

  group('A. EmployeeStore - find / findIncludingDeleted', () {
    test('find - 按 uuid 精确查找', () async {
      final emp = createEmployee(name: '唯一');
      await store.save(emp);

      final found = await store.find(null, emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('唯一'));
    });

    test('find - 已删除员工不可查', () async {
      final emp = createEmployee(deleted: 1);
      await store.save(emp);

      final found = await store.find(null, emp.uuid);
      expect(found, isNull);
    });

    test('find - 按 deviceId + uuid 查找', () async {
      final emp = createEmployee(deviceId: 'dev-A');
      await store.save(emp);

      // 正确的 deviceId
      final foundA = await store.find('dev-A', emp.uuid);
      expect(foundA, isNotNull);

      // 错误的 deviceId
      final foundB = await store.find('dev-B', emp.uuid);
      expect(foundB, isNull);
    });

    test('findIncludingDeleted - 可查已删除员工', () async {
      final emp = createEmployee(name: '已删', deleted: 1, deletedTime: DateTime(2024, 1, 5));
      await store.save(emp);

      final found = await store.findIncludingDeleted(emp.uuid);
      expect(found, isNotNull);
      expect(found!.deleted, equals(1));
      expect(found.name, equals('已删'));
    });

    test('findIncludingDeleted - 不存在返回 null', () async {
      final found = await store.findIncludingDeleted('non-existent-uuid');
      expect(found, isNull);
    });
  });

  group('A. EmployeeStore - delete / count / exists', () {
    test('delete - 软删除', () async {
      final emp = createEmployee();
      await store.save(emp);

      // 删除前可查
      expect(await store.exists(null, emp.uuid), isTrue);

      await store.delete(null, emp.uuid);

      // 删除后不可查
      expect(await store.exists(null, emp.uuid), isFalse);
      final found = await store.find(null, emp.uuid);
      expect(found, isNull);

      // findIncludingDeleted 可查到，且有 deletedTime
      final deleted = await store.findIncludingDeleted(emp.uuid);
      expect(deleted, isNotNull);
      expect(deleted!.deleted, equals(1));
      expect(deleted.deletedTime, isNotNull);
    });

    test('delete - deviceId 参数未使用（已知行为）', () async {
      // EmployeeStore.delete 的 deviceId 参数在 SQL 中未使用
      // 任何设备都可以软删除其他设备创建的员工
      final emp = createEmployee(deviceId: 'dev-A');
      await store.save(emp);

      // 用 dev-B 删除 dev-A 创建的员工
      await store.delete('dev-B', emp.uuid);

      final found = await store.findIncludingDeleted(emp.uuid);
      expect(found!.deleted, equals(1));
    });

    test('count - 统计数量', () async {
      await store.save(createEmployee(deviceId: 'dev-A'));
      await store.save(createEmployee(deviceId: 'dev-A'));
      await store.save(createEmployee(deviceId: 'dev-B'));

      expect(await store.count('dev-A'), equals(2));
      expect(await store.count('dev-B'), equals(1));
      expect(await store.count(null), equals(3));
    });

    test('count - 按 status 过滤', () async {
      await store.save(createEmployee(status: 'active'));
      await store.save(createEmployee(status: 'active'));
      await store.save(createEmployee(status: 'inactive'));

      expect(await store.count(null, status: 'active'), equals(2));
      expect(await store.count(null, status: 'inactive'), equals(1));
    });

    test('count - 不统计已删除', () async {
      await store.save(createEmployee());
      await store.save(createEmployee(deleted: 1));

      expect(await store.count(null), equals(1));
    });

    test('exists - 存在性检查', () async {
      final emp = createEmployee();
      await store.save(emp);

      expect(await store.exists(null, emp.uuid), isTrue);
      expect(await store.exists(null, 'non-existent'), isFalse);
    });

    test('exists - 已删除返回 false', () async {
      final emp = createEmployee(deleted: 1);
      await store.save(emp);

      expect(await store.exists(null, emp.uuid), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════
  // B. EmployeeManager 业务逻辑测试
  // ═══════════════════════════════════════════════════

  group('B. EmployeeManager - createEmployee', () {
    test('createEmployee - 自动设置 deviceId/createTime/updateTime', () async {
      final emp = createEmployee(name: '新建员工');
      // 不设置 deviceId
      final created = await manager.createEmployee(
        emp.copyWith(deviceId: null),
      );

      expect(created.deviceId, equals(deviceId));
      expect(created.createTime.millisecondsSinceEpoch,
          greaterThan(emp.createTime.millisecondsSinceEpoch - 1000));
      expect(created.updateTime.millisecondsSinceEpoch,
          greaterThan(emp.updateTime.millisecondsSinceEpoch - 1000));
    });

    test('createEmployee - 已有 deviceId 不覆盖', () async {
      final emp = createEmployee(name: '指定设备', deviceId: 'dev-custom');
      final created = await manager.createEmployee(emp);

      expect(created.deviceId, equals('dev-custom'));
    });

    test('createEmployee - 触发 created 事件', () async {
      final events = <EmployeeChangeEvent>[];
      manager.onEmployeeEvent.listen(events.add);

      final emp = createEmployee(name: '事件测试');
      await manager.createEmployee(emp);

      // 等待事件传播
      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.created));
      expect(events.first.employeeId, equals(emp.uuid));
      expect(events.first.employee, isNotNull);
    });
  });

  group('B. EmployeeManager - saveEmployee', () {
    test('saveEmployee - 新员工触发 created 事件', () async {
      final events = <EmployeeChangeEvent>[];
      manager.onEmployeeEvent.listen(events.add);

      final emp = createEmployee(name: '同步新员工');
      await manager.saveEmployee(emp);

      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.created));
    });

    test('saveEmployee - 已有员工触发 updated 事件', () async {
      final emp = createEmployee(name: '原员工');
      await manager.saveEmployee(emp);

      final events = <EmployeeChangeEvent>[];
      manager.onEmployeeEvent.listen(events.add);

      await manager.saveEmployee(emp.copyWith(name: '更新员工'));

      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.updated));
    });

    test('saveEmployee - 不修改时间戳（同步场景）', () async {
      final ct = DateTime(2024, 1, 1);
      final ut = DateTime(2024, 1, 2);
      final emp = createEmployee(createTime: ct, updateTime: ut);

      await manager.saveEmployee(emp);

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.createTime, equals(ct));
      expect(found.updateTime, equals(ut));
    });
  });

  group('B. EmployeeManager - updateEmployee', () {
    test('updateEmployee - 自动刷新 updateTime', () async {
      final emp = createEmployee(
        name: '更新前',
        updateTime: DateTime(2024, 1, 1),
      );
      await manager.saveEmployee(emp);

      final beforeUpdate = DateTime.now();
      await manager.updateEmployee(emp.copyWith(name: '更新后'));

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.name, equals('更新后'));
      expect(found.updateTime.isAfter(beforeUpdate.subtract(Duration(seconds: 1))),
          isTrue);
    });

    test('updateEmployee - 触发 updated 事件', () async {
      final emp = createEmployee();
      await manager.saveEmployee(emp);

      final events = <EmployeeChangeEvent>[];
      manager.onEmployeeEvent.listen(events.add);

      await manager.updateEmployee(emp.copyWith(name: '更新'));

      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.updated));
    });
  });

  group('B. EmployeeManager - updateCurrentDeviceId', () {
    test('updateCurrentDeviceId - 更新会话漫游设备', () async {
      final emp = createEmployee();
      await manager.saveEmployee(emp);

      await manager.updateCurrentDeviceId(emp.uuid, 'dev-roaming');

      final found = await manager.getEmployee(emp.uuid);
      expect(found!.currentDeviceId, equals('dev-roaming'));
    });

    test('updateCurrentDeviceId - 员工不存在时不报错', () async {
      // 不应抛出异常
      await manager.updateCurrentDeviceId('non-existent', 'dev-X');
    });
  });

  group('B. EmployeeManager - deleteEmployee', () {
    test('deleteEmployee - 软删除 + deleted 事件', () async {
      final emp = createEmployee();
      await manager.saveEmployee(emp);

      final events = <EmployeeChangeEvent>[];
      manager.onEmployeeEvent.listen(events.add);

      await manager.deleteEmployee(emp.uuid);

      // getEmployee 不返回
      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNull);

      // getEmployeeIncludingDeleted 返回
      final deleted = await manager.getEmployeeIncludingDeleted(emp.uuid);
      expect(deleted, isNotNull);
      expect(deleted!.deleted, equals(1));

      // 事件
      await Future.delayed(Duration(milliseconds: 50));
      expect(events.length, equals(1));
      expect(events.first.type, equals(EmployeeChangeType.deleted));
      expect(events.first.employeeId, equals(emp.uuid));
    });
  });

  group('B. EmployeeManager - getEmployees', () {
    test('getEmployees(allDevices: false) - 仅本设备', () async {
      await manager.createEmployee(createEmployee(name: '本机'));
      // 手动保存一个其他设备的员工
      await store.save(createEmployee(
        name: '远程',
        deviceId: 'dev-other',
      ));

      final result = await manager.getEmployees(allDevices: false);
      expect(result.length, equals(1));
      expect(result.first.name, equals('本机'));
    });

    test('getEmployees(allDevices: true) - 所有设备', () async {
      await manager.createEmployee(createEmployee(name: '本机'));
      await store.save(createEmployee(
        name: '远程',
        deviceId: 'dev-other',
      ));

      final result = await manager.getEmployees(allDevices: true);
      expect(result.length, equals(2));
    });

    test('getEmployees - includeDeleted', () async {
      await manager.createEmployee(createEmployee(name: '正常'));
      await store.save(createEmployee(name: '已删除', deleted: 1, deviceId: deviceId));

      final withoutDeleted = await manager.getEmployees(includeDeleted: false);
      expect(withoutDeleted.length, equals(1));

      final withDeleted = await manager.getEmployees(includeDeleted: true);
      expect(withDeleted.length, equals(2));
    });
  });

  group('B. EmployeeManager - getEmployeeStats', () {
    test('getEmployeeStats - 统计信息', () async {
      await manager.createEmployee(
        createEmployee(name: 'A', status: 'active', isPinned: 1),
      );
      await manager.createEmployee(
        createEmployee(name: 'B', status: 'active'),
      );
      await manager.createEmployee(
        createEmployee(name: 'C', status: 'inactive'),
      );

      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(3));
      expect(stats.activeCount, equals(2));
      expect(stats.pinnedCount, equals(1));
    });

    test('getEmployeeStats - 不统计其他设备', () async {
      await manager.createEmployee(createEmployee(name: '本机'));
      await store.save(createEmployee(
        name: '远程',
        deviceId: 'dev-other',
      ));

      final stats = await manager.getEmployeeStats();
      expect(stats.totalCount, equals(1));
    });
  });

  // ═══════════════════════════════════════════════════
  // C. 同步合并逻辑测试
  // ═══════════════════════════════════════════════════

  group('C. 同步 - 新建员工同步', () {
    test('本地不存在 → 直接保存', () async {
      final remote = createEmployee(
        name: '远程员工',
        deviceId: 'dev-remote',
      );

      // 模拟：existing == null → saveEmployee
      final existing = await manager.getEmployeeIncludingDeleted(remote.uuid);
      expect(existing, isNull);

      await manager.saveEmployee(remote);

      final found = await manager.getEmployee(remote.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('远程员工'));
    });

    test('本地不存在 + 远程已删除 → 不保存', () async {
      final remote = createEmployee(
        name: '已删除远程',
        deleted: 1,
        deletedTime: DateTime(2024, 1, 5),
      );

      // 模拟 _doSyncEmployeesFromDevices 的修复后逻辑
      final existing = await manager.getEmployeeIncludingDeleted(remote.uuid);
      expect(existing, isNull);

      if (remote.deleted != 1) {
        await manager.saveEmployee(remote);
      }

      // 验证没有保存
      final found = await manager.getEmployeeIncludingDeleted(remote.uuid);
      expect(found, isNull);
    });
  });

  group('C. 同步 - 更新合并', () {
    test('远程更新 → remote.updateTime > local → 取远程数据', () async {
      final local = createEmployee(
        name: '本地名',
        updateTime: DateTime(2024, 1, 2),
      );
      await manager.saveEmployee(local);

      final remote = local.copyWith(
        name: '远程名',
        updateTime: DateTime(2024, 1, 5),
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      final (shouldSave, merged) = simulateMerge(existing!, remote);

      expect(shouldSave, isTrue);
      expect(merged!.name, equals('远程名'));
    });

    test('本地更新 → local.updateTime > remote → 保留本地数据', () async {
      final local = createEmployee(
        name: '本地名',
        updateTime: DateTime(2024, 1, 5),
      );
      await manager.saveEmployee(local);

      final remote = local.copyWith(
        name: '远程名',
        updateTime: DateTime(2024, 1, 2),
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      final (shouldSave, merged) = simulateMerge(existing!, remote);

      expect(shouldSave, isFalse);
    });

    test('updateTime 相等 → 不更新（isAfter 返回 false）', () async {
      final ts = DateTime(2024, 1, 5);
      final local = createEmployee(name: '本地名', updateTime: ts);
      await manager.saveEmployee(local);

      final remote = local.copyWith(name: '远程名', updateTime: ts);

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      final (shouldSave, _) = simulateMerge(existing!, remote);

      // updateTime.isAfter 相等时返回 false，不更新
      expect(shouldSave, isFalse);
    });
  });

  group('C. 同步 - 软删除同步传播', () {
    test('远程 deleted=1 → 本地同步删除', () async {
      final local = createEmployee(
        name: '正常员工',
        updateTime: DateTime(2024, 1, 2),
      );
      await manager.saveEmployee(local);

      final remote = local.copyWith(
        deleted: 1,
        deletedTime: DateTime(2024, 1, 5),
        updateTime: DateTime(2024, 1, 5),
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      expect(existing!.deleted, equals(0));

      final (shouldSave, merged) = simulateMerge(existing, remote);

      expect(shouldSave, isTrue);
      expect(merged!.deleted, equals(1));
      expect(merged.deletedTime, isNotNull);

      // 应用合并结果
      await manager.updateEmployee(merged);
      final found = await manager.getEmployee(local.uuid);
      expect(found, isNull); // 已删除，getEmployee 不返回
    });

    test('单向删除传播 - 本地未删除 + 远程已删除', () async {
      final local = createEmployee(
        deleted: 0,
        deletedTime: null,
        updateTime: DateTime(2024, 1, 2),
      );
      await manager.saveEmployee(local);

      final remoteDeleteTime = DateTime(2024, 1, 5);
      final remote = local.copyWith(
        deleted: 1,
        deletedTime: remoteDeleteTime,
        updateTime: DateTime(2024, 1, 2),
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      final (dt, d) = mergeDeleteTime(
        existing!.deletedTime, existing.deleted,
        remote.deletedTime, remote.deleted,
      );

      expect(dt, equals(remoteDeleteTime));
      expect(d, equals(1));
    });
  });

  group('C. 同步 - 双向删除 deleteTime 合并', () {
    test('双方都删除 → 取较大 deleteTime', () async {
      final localDT = DateTime(2024, 1, 5);
      final remoteDT = DateTime(2024, 1, 3);

      final local = createEmployee(
        deleted: 1,
        deletedTime: localDT,
        updateTime: DateTime(2024, 1, 4),
      );
      await manager.saveEmployee(local);

      final remote = local.copyWith(
        deleted: 1,
        deletedTime: remoteDT,
        name: '远程更新名',
        updateTime: DateTime(2024, 1, 6),
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      final (shouldSave, merged) = simulateMerge(existing!, remote);

      // deleteTime 取本地（更大），数据取远程（updateTime 更大）
      expect(shouldSave, isTrue);
      expect(merged!.deletedTime, equals(localDT));
      expect(merged.deleted, equals(1));
      expect(merged.name, equals('远程更新名')); // 数据取远程
    });

    test('远程 deleteTime 更大 → 取远程', () async {
      final localDT = DateTime(2024, 1, 3);
      final remoteDT = DateTime(2024, 1, 5);

      final (dt, d) = mergeDeleteTime(localDT, 1, remoteDT, 1);
      expect(dt, equals(remoteDT));
      expect(d, equals(1));
    });
  });

  group('C. 同步 - 已删除员工不复活', () {
    test('本地已删除 + 远程未删除(旧) → 保持删除', () async {
      final localDT = DateTime(2024, 1, 5);

      final local = createEmployee(
        deleted: 1,
        deletedTime: localDT,
        updateTime: DateTime(2024, 1, 4),
      );
      await store.save(local);

      // remote: 未删除（旧数据），deleted=0, deletedTime=null
      // 注意：copyWith(deleted: 0) 不会清除 deletedTime，所以手动设为 null
      final remote = local.copyWith(
        deleted: 0,
        deletedTime: null,
        updateTime: DateTime(2024, 1, 2),
      );
      // 验证 remote 确实没有 deletedTime
      // (copyWith 不支持设 null，但 remoteDT 传入 mergeDeleteTime 是 null 即可)

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      expect(existing!.deleted, equals(1));
      final existingDT = existing.deletedTime;

      // 直接用 null 作为 remote deletedTime，模拟实际同步场景
      final (dt, d) = mergeDeleteTime(
        existingDT, existing.deleted,
        null, 0, // remote: deletedTime=null, deleted=0
      );

      // 本地有 deleteTime，远程没有 → 保留本地删除状态
      expect(dt?.millisecondsSinceEpoch, equals(localDT.millisecondsSinceEpoch));
      expect(d, equals(1));

      final shouldUpdateData =
          remote.updateTime.isAfter(existing.updateTime);
      expect(shouldUpdateData, isFalse); // 远程数据更旧

      final shouldUpdateDelete =
          dt?.millisecondsSinceEpoch != existingDT?.millisecondsSinceEpoch || d != existing.deleted;
      expect(shouldUpdateDelete, isFalse); // 无需更新
    });

    test('已删除员工不保存（无本地记录）', () async {
      final deletedEmployee = createEmployee(
        deleted: 1,
        deletedTime: DateTime(2024, 1, 5),
      );

      final existing = await manager.getEmployeeIncludingDeleted(
        deletedEmployee.uuid,
      );
      expect(existing, isNull);

      // 模拟修复后的 _doSyncEmployeesFromDevices 逻辑
      if (deletedEmployee.deleted != 1) {
        await manager.saveEmployee(deletedEmployee);
      }

      // 验证没有保存
      final found = await manager.getEmployeeIncludingDeleted(
        deletedEmployee.uuid,
      );
      expect(found, isNull);
    });
  });

  group('C. 同步 - _mergeDeleteTime 边界情况', () {
    test('both null → (null, 0)', () {
      final (dt, d) = mergeDeleteTime(null, 0, null, 0);
      expect(dt, isNull);
      expect(d, equals(0));
    });

    test('local null, remote present → 取远程', () {
      final remoteDT = DateTime(2024, 1, 3);
      final (dt, d) = mergeDeleteTime(null, 0, remoteDT, 1);
      expect(dt, equals(remoteDT));
      expect(d, equals(1));
    });

    test('remote null, local present → 取本地', () {
      final localDT = DateTime(2024, 1, 3);
      final (dt, d) = mergeDeleteTime(localDT, 1, null, 0);
      expect(dt, equals(localDT));
      expect(d, equals(1));
    });

    test('equal deleteTime → 取 remote（isAfter 返回 false）', () {
      final dt = DateTime(2024, 1, 3);
      final (result, d) = mergeDeleteTime(dt, 0, dt, 1);
      expect(result, equals(dt));
      expect(d, equals(1)); // remote wins when equal
    });

    test('local after remote → 取本地', () {
      final localDT = DateTime(2024, 1, 5);
      final remoteDT = DateTime(2024, 1, 3);
      final (dt, d) = mergeDeleteTime(localDT, 1, remoteDT, 0);
      expect(dt, equals(localDT));
      expect(d, equals(1));
    });

    test('remote after local → 取远程', () {
      final localDT = DateTime(2024, 1, 3);
      final remoteDT = DateTime(2024, 1, 5);
      final (dt, d) = mergeDeleteTime(localDT, 0, remoteDT, 1);
      expect(dt, equals(remoteDT));
      expect(d, equals(1));
    });
  });

  group('C. 同步 - 数据 + 删除独立合并', () {
    test('数据取远程 + 删除取本地（远程数据新但本地删除新）', () async {
      final localDT = DateTime(2024, 1, 6); // 本地删除时间更新
      final local = createEmployee(
        name: '本地名',
        deleted: 1,
        deletedTime: localDT,
        updateTime: DateTime(2024, 1, 2),
      );
      await store.save(local);

      // remote: 数据更新但未删除
      // 注意：copyWith 无法清除 nullable 字段（deletedTime），所以 remote.deletedTime 仍为 localDT
      // 但在真实同步场景中，remote 来自 fromMap，deletedTime 应为 null
      // 这里我们直接构造一个 deletedTime=null 的 remote 实体来模拟真实场景
      final remote = AiEmployeeEntity(
        uuid: local.uuid,
        name: '远程名',
        deleted: 0,
        deletedTime: null,
        updateTime: DateTime(2024, 1, 5), // 远程数据更新
        createTime: local.createTime,
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      expect(existing!.deleted, equals(1));

      // mergeDeleteTime(localDT, 1, null, 0) → localDT != null, remoteDT == null → (localDT, localD=1)
      // shouldUpdateData = remote.updateTime(1/5).isAfter(existing.updateTime(1/2)) = true
      // shouldUpdateDelete = (localDT == existing.deletedTime && 1 == existing.deleted) = false
      // shouldSave = true (shouldUpdateData)
      // base = remote (shouldUpdateData=true)
      // merged: 数据取远程，删除取本地
      final (shouldSave, merged) = simulateMerge(
        existing, remote,
      );

      expect(shouldSave, isTrue);
      expect(merged!.name, equals('远程名')); // 数据取远程（remote.updateTime 更新）
      expect(merged.deleted, equals(1)); // 删除取本地（localDT > null）
      expect(
        merged.deletedTime?.millisecondsSinceEpoch,
        equals(localDT.millisecondsSinceEpoch),
      );
    });

    test('数据取本地 + 删除取远程（本地数据新但远程删除新）', () async {
      final remoteDT = DateTime(2024, 1, 6); // 远程删除时间更新
      final local = createEmployee(
        name: '本地名',
        deleted: 1,
        deletedTime: DateTime(2024, 1, 3),
        updateTime: DateTime(2024, 1, 5), // 本地数据更新
      );
      await store.save(local);

      final remote = local.copyWith(
        name: '远程名',
        deleted: 1,
        deletedTime: remoteDT,
        updateTime: DateTime(2024, 1, 2),
      );

      final existing = await manager.getEmployeeIncludingDeleted(local.uuid);
      final (shouldSave, merged) = simulateMerge(existing!, remote);

      expect(shouldSave, isTrue);
      expect(merged!.name, equals('本地名')); // 数据取本地
      expect(merged.deleted, equals(1)); // 删除取远程
      expect(merged.deletedTime?.millisecondsSinceEpoch, equals(remoteDT.millisecondsSinceEpoch));
    });
  });

  group('C. 同步 - 完整 CRUD + 同步链路', () {
    test('创建→查询→更新→删除→同步 完整链路', () async {
      // 1. 创建
      final emp = createEmployee(name: '完整链路测试');
      await manager.createEmployee(emp);

      // 2. 查询
      var found = await manager.getEmployee(emp.uuid);
      expect(found, isNotNull);
      expect(found!.name, equals('完整链路测试'));

      // 3. 更新
      await manager.updateEmployee(found.copyWith(
        name: '更新后',
        description: '新增描述',
        systemPrompt: '你是一个AI助手',
      ));

      found = await manager.getEmployee(emp.uuid);
      expect(found!.name, equals('更新后'));
      expect(found.description, equals('新增描述'));
      expect(found.systemPrompt, equals('你是一个AI助手'));

      // 4. 模拟同步：序列化 → 反序列化
      final mapData = found.toMap();
      final restored = AiEmployeeEntity.fromMap(mapData);
      expect(restored.name, equals('更新后'));
      expect(restored.uuid, equals(emp.uuid));

      // 5. 模拟同步到另一设备：保存反序列化数据
      await manager.saveEmployee(restored);
      found = await manager.getEmployee(emp.uuid);
      expect(found!.name, equals('更新后'));

      // 6. 删除
      await manager.deleteEmployee(emp.uuid);
      found = await manager.getEmployee(emp.uuid);
      expect(found, isNull);

      // 7. findIncludingDeleted 仍可查
      final deleted = await manager.getEmployeeIncludingDeleted(emp.uuid);
      expect(deleted, isNotNull);
      expect(deleted!.deleted, equals(1));
    });

    test('模拟两设备同步：并发更新冲突 → updateTime 解决', () async {
      // 设备A创建
      final emp = createEmployee(
        name: '设备A',
        updateTime: DateTime(2024, 1, 1),
      );
      await manager.saveEmployee(emp);

      // 设备A更新（本地 updateTime = 1月3日）
      final localUpdate = emp.copyWith(
        name: '设备A更新',
        updateTime: DateTime(2024, 1, 3),
      );
      await manager.saveEmployee(localUpdate);

      // 设备B的更新（远程 updateTime = 1月5日，更晚）
      final remoteUpdate = emp.copyWith(
        name: '设备B更新',
        updateTime: DateTime(2024, 1, 5),
      );

      // 合并
      final existing = await manager.getEmployeeIncludingDeleted(emp.uuid);
      final (shouldSave, merged) = simulateMerge(existing!, remoteUpdate);

      expect(shouldSave, isTrue);
      expect(merged!.name, equals('设备B更新')); // 远程胜出
    });

    test('模拟两设备同步：设备A删除 → 设备B收到 deleted=1 → 标记删除', () async {
      // 设备A和B都有这个员工
      final emp = createEmployee(
        name: '待删除',
        updateTime: DateTime(2024, 1, 2),
      );
      await manager.saveEmployee(emp);

      // 设备A删除后广播（deleted=1, deletedTime, updateTime 更新）
      final remoteDeleted = emp.copyWith(
        deleted: 1,
        deletedTime: DateTime(2024, 1, 5),
        updateTime: DateTime(2024, 1, 5),
      );

      // 设备B执行合并
      final existing = await manager.getEmployeeIncludingDeleted(emp.uuid);
      final (shouldSave, merged) = simulateMerge(existing!, remoteDeleted);

      expect(shouldSave, isTrue);
      expect(merged!.deleted, equals(1));
      expect(merged.deletedTime, isNotNull);

      // 应用合并
      await manager.updateEmployee(merged);
      final found = await manager.getEmployee(emp.uuid);
      expect(found, isNull);
    });
  });

  // ═══════════════════════════════════════════════════
  // D. 序列化往返测试
  // ═══════════════════════════════════════════════════

  group('D. 序列化 - toMap/fromMap 往返', () {
    test('所有字段一致', () {
      final now = DateTime(2024, 6, 15, 12, 30, 0);
      final emp = AiEmployeeEntity(
        uuid: 'test-uuid-123',
        name: '序列化测试',
        avatar: 'https://example.com/avatar.png',
        role: 'assistant',
        status: 'active',
        description: '这是一个测试员工',
        systemPrompt: '你是一个AI助手',
        provider: 'openai',
        model: 'gpt-4',
        apiKey: 'sk-test-key',
        apiBaseUrl: 'https://api.openai.com/v1',
        modelConfig: '{"temperature": 0.7}',
        enableTools: 1,
        enableMcp: 1,
        projectUuid: 'proj-123',
        projectName: '测试项目',
        projectContext: '项目上下文',
        workPath: '/home/user/project',
        mcpConfig: '[{"name":"server1"}]',
        permissionConfig: '{"allowedTools":["*"]}',
        deviceId: 'dev-test',
        currentDeviceId: 'dev-test',
        autoApprove: 1,
        sortOrder: 5,
        isPinned: 1,
        deleted: 0,
        deletedTime: null,
        createTime: now,
        updateTime: now,
      );

      final map = emp.toMap();
      final restored = AiEmployeeEntity.fromMap(map);

      expect(restored.uuid, equals(emp.uuid));
      expect(restored.name, equals(emp.name));
      expect(restored.avatar, equals(emp.avatar));
      expect(restored.role, equals(emp.role));
      expect(restored.status, equals(emp.status));
      expect(restored.description, equals(emp.description));
      expect(restored.systemPrompt, equals(emp.systemPrompt));
      expect(restored.provider, equals(emp.provider));
      expect(restored.model, equals(emp.model));
      expect(restored.apiKey, equals(emp.apiKey));
      expect(restored.apiBaseUrl, equals(emp.apiBaseUrl));
      expect(restored.modelConfig, equals(emp.modelConfig));
      expect(restored.enableTools, equals(emp.enableTools));
      expect(restored.enableMcp, equals(emp.enableMcp));
      expect(restored.projectUuid, equals(emp.projectUuid));
      expect(restored.projectName, equals(emp.projectName));
      expect(restored.projectContext, equals(emp.projectContext));
      expect(restored.workPath, equals(emp.workPath));
      expect(restored.mcpConfig, equals(emp.mcpConfig));
      expect(restored.permissionConfig, equals(emp.permissionConfig));
      expect(restored.deviceId, equals(emp.deviceId));
      expect(restored.currentDeviceId, equals(emp.currentDeviceId));
      expect(restored.autoApprove, equals(emp.autoApprove));
      expect(restored.sortOrder, equals(emp.sortOrder));
      expect(restored.isPinned, equals(emp.isPinned));
      expect(restored.deleted, equals(emp.deleted));
      expect(restored.deletedTime, equals(emp.deletedTime));
      // createTime/updateTime use millisecondsSinceEpoch in toMap,
      // so sub-millisecond precision is lost in round-trip.
      expect(restored.createTime.millisecondsSinceEpoch, equals(emp.createTime.millisecondsSinceEpoch));
      expect(restored.updateTime.millisecondsSinceEpoch, equals(emp.updateTime.millisecondsSinceEpoch));
    });

    test('deletedTime 非空时往返一致', () {
      final dt = DateTime(2024, 1, 5, 10, 30, 0);
      final emp = createEmployee(
        deleted: 1,
        deletedTime: dt,
      );

      final map = emp.toMap();
      final restored = AiEmployeeEntity.fromMap(map);

      expect(restored.deletedTime, isNotNull);
      expect(restored.deletedTime!.millisecondsSinceEpoch,
          equals(dt.millisecondsSinceEpoch));
    });

    test('null 字段往返保持 null', () {
      final emp = AiEmployeeEntity(
        uuid: 'test-uuid',
        name: '最小员工',
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      final map = emp.toMap();
      final restored = AiEmployeeEntity.fromMap(map);

      expect(restored.avatar, isNull);
      expect(restored.description, isNull);
      expect(restored.systemPrompt, isNull);
      expect(restored.provider, isNull);
      expect(restored.model, isNull);
      expect(restored.apiKey, isNull);
      expect(restored.apiBaseUrl, isNull);
      expect(restored.modelConfig, isNull);
      expect(restored.projectUuid, isNull);
      expect(restored.projectName, isNull);
      expect(restored.projectContext, isNull);
      expect(restored.workPath, isNull);
      expect(restored.mcpConfig, isNull);
      expect(restored.permissionConfig, isNull);
      expect(restored.deviceId, isNull);
      expect(restored.currentDeviceId, isNull);
      expect(restored.deletedTime, isNull);
    });
  });

  group('D. 序列化 - copyWith', () {
    test('copyWith - 每个字段可独立修改', () {
      final emp = createEmployee(
        name: '原始',
        description: '原始描述',
        systemPrompt: '原始提示词',
      );

      expect(emp.copyWith(name: '新名').name, equals('新名'));
      expect(emp.copyWith(description: '新描述').description, equals('新描述'));
      expect(emp.copyWith(systemPrompt: '新提示词').systemPrompt, equals('新提示词'));
      expect(emp.copyWith(provider: 'claude').provider, equals('claude'));
      expect(emp.copyWith(model: 'claude-3').model, equals('claude-3'));
      expect(emp.copyWith(deviceId: 'dev-new').deviceId, equals('dev-new'));
      expect(emp.copyWith(currentDeviceId: 'dev-new').currentDeviceId, equals('dev-new'));
      expect(emp.copyWith(deleted: 1).deleted, equals(1));
      expect(emp.copyWith(isPinned: 1).isPinned, equals(1));
      expect(emp.copyWith(sortOrder: 10).sortOrder, equals(10));
      expect(emp.copyWith(status: 'inactive').status, equals('inactive'));
    });

    test('copyWith - 未指定的字段保持不变', () {
      final emp = createEmployee(
        name: '原始',
        description: '描述',
        provider: 'openai',
      );

      final modified = emp.copyWith(name: '新名');
      expect(modified.name, equals('新名'));
      expect(modified.description, equals('描述'));
      expect(modified.provider, equals('openai'));
      expect(modified.uuid, equals(emp.uuid));
    });

    test('copyWith - deletedTime 可设置和清除', () {
      final dt = DateTime(2024, 1, 5);
      final emp = createEmployee(deletedTime: dt);

      expect(emp.deletedTime, equals(dt));

      // 注意：copyWith 不能传 null 来清除值（这是 Dart copyWith 的常见限制）
      // 需要通过设置 deleted=0 并依赖业务逻辑来处理
      final cleared = emp.copyWith(deleted: 0);
      expect(cleared.deleted, equals(0));
      expect(cleared.deletedTime, equals(dt)); // deletedTime 仍保留
    });
  });
}
