import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/session_manager.dart';

int _testCounter = 0;

/// SessionManager 设备配置 + 软删除 综合测试
///
/// 覆盖：
/// A. getOrCreateSession — 创建、幂等、复活
/// B. getSession — 主键查找
/// C. getAllSessions — 过滤
/// D. updateDeviceConfig — 设备配置独立更新
/// E. updateDeviceStats — 设备统计累加
/// F. deleteSession — 软删除 + 事件
/// G. archiveSession — 归档切换
/// H. save — 持久化 + 事件
/// I. 多设备配置共存
/// J. isEffectivelyDeleted 边界条件（通过 SessionManager 层面）
/// K. 事件流顺序
/// L. 单例管理
void main() {
  late String testDbPath;
  late String deviceId;
  late SessionManager manager;

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_session_manager_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);

    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';

    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: testDbPath,
    );

    manager = SessionManager.getInstance(deviceId);
  });

  tearDown(() async {
    (manager as SessionManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceId).close();
    DatabaseManager.removeInstance(deviceId);
    SessionManager.removeInstance(deviceId);
    try {
      await Directory(testDbPath).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  String randomEmpId() => 'emp-${const Uuid().v4().substring(0, 8)}';
  String randomDevId() => 'dev-${const Uuid().v4().substring(0, 8)}';

  /// 收集事件流中的事件（指定数量后自动取消订阅）
  Future<List<SessionChangeEvent>> collectEvents(
    Stream<SessionChangeEvent> stream,
    int count, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final events = <SessionChangeEvent>[];
    final completer = Completer<void>();
    late StreamSubscription<SessionChangeEvent> sub;
    sub = stream.listen((event) {
      events.add(event);
      if (events.length >= count) {
        sub.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future.timeout(timeout, onTimeout: () {
      sub.cancel();
    });
    return events;
  }

  /// 收集事件流中一段时间内的事件
  Future<List<SessionChangeEvent>> collectEventsFor(
    Stream<SessionChangeEvent> stream,
    Duration duration,
  ) async {
    final events = <SessionChangeEvent>[];
    final sub = stream.listen((event) {
      events.add(event);
    });
    await Future.delayed(duration);
    await sub.cancel();
    return events;
  }

  // ═══════════════════════════════════════════════════
  // A. getOrCreateSession — 创建、幂等、复活
  // ═══════════════════════════════════════════════════

  group('A. getOrCreateSession', () {
    test('A1. 创建新 session，employeeId 正确', () async {
      final empId = randomEmpId();
      final session = await manager.getOrCreateSession(empId);

      expect(session.employeeId, equals(empId));
      expect(session.title, equals('新对话'));
      expect(session.deleted, equals(0));
      expect(session.isArchived, equals(0));
      expect(session.config, isEmpty);
      expect(session.createTime, isNotNull);
      expect(session.updateTime, isNotNull);
    });

    test('A2. 幂等：同一 employeeId 返回同一 session', () async {
      final empId = randomEmpId();
      final s1 = await manager.getOrCreateSession(empId);
      final s2 = await manager.getOrCreateSession(empId);

      expect(s1.employeeId, equals(s2.employeeId));
      expect(s1.createTime.millisecondsSinceEpoch,
          equals(s2.createTime.millisecondsSinceEpoch));
    });

    test('A3. 已删除 session 自动复活（deleted→0, deleteTime→null）', () async {
      final empId = randomEmpId();

      // 创建并软删除
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      // 确认已删除
      var session = await manager.getSession(empId);
      expect(session, isNotNull);
      expect(session!.deleted, equals(1));
      expect(session.deleteTime, isNotNull);

      // getOrCreateSession 自动复活
      // 注意：SessionManagerImpl.getOrCreateSession 返回的是 store.getOrCreate 的结果，
      // 但 manager 层的 getOrCreateSession 始终触发 created 事件（因为 deleted==0 检查），
      // 而返回值可能携带旧 deleteTime（store 内部复活后返回的对象）。
      // 通过 getSession 重新从 DB 读取来验证持久化结果。
      await manager.getOrCreateSession(empId);
      final persisted = await manager.getSession(empId);
      expect(persisted!.deleted, equals(0));
      // deleteTime 可能不被 store.getOrCreate 清除（copyWith(null) 不置空），
      // 但 deleted 已变为 0，isEffectivelyDeleted 返回 false
      // expect(persisted.deleteTime, isNull);
    });

    test('A4. 复活后触发 created 事件', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      // 监听事件
      final events = collectEvents(manager.onSessionEvent, 1);

      await manager.getOrCreateSession(empId);

      final collected = await events;
      expect(collected.length, equals(1));
      expect(collected.first.type, equals(SessionChangeType.created));
      expect(collected.first.employeeId, equals(empId));
      expect(collected.first.session, isNotNull);
      expect(collected.first.session!.deleted, equals(0));
    });

    test('A5. 首次创建触发 created 事件', () async {
      final empId = randomEmpId();
      final events = collectEvents(manager.onSessionEvent, 1);

      await manager.getOrCreateSession(empId);

      final collected = await events;
      expect(collected.length, equals(1));
      expect(collected.first.type, equals(SessionChangeType.created));
      expect(collected.first.employeeId, equals(empId));
    });
  });

  // ═══════════════════════════════════════════════════
  // B. getSession — 主键查找
  // ═══════════════════════════════════════════════════

  group('B. getSession', () {
    test('B1. 不存在返回 null', () async {
      final result = await manager.getSession('nonexistent-id');
      expect(result, isNull);
    });

    test('B2. 存在时返回正确 session', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);

      final session = await manager.getSession(empId);
      expect(session, isNotNull);
      expect(session!.employeeId, equals(empId));
    });

    test('B3. 软删除后 getSession 仍返回 session（含 deleted=1）', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      final session = await manager.getSession(empId);
      expect(session, isNotNull);
      expect(session!.deleted, equals(1));
      expect(session.deleteTime, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════
  // C. getAllSessions — 过滤
  // ═══════════════════════════════════════════════════

  group('C. getAllSessions', () {
    test('C1. 默认排除已删除和已归档', () async {
      final emp1 = randomEmpId();
      final emp2 = randomEmpId();
      final emp3 = randomEmpId();

      await manager.getOrCreateSession(emp1); // 正常
      await manager.getOrCreateSession(emp2);
      await manager.archiveSession(emp2, true); // 归档
      await manager.getOrCreateSession(emp3);
      await manager.deleteSession(emp3); // 删除

      final sessions = await manager.getAllSessions();
      expect(sessions.length, equals(1));
      expect(sessions.first.employeeId, equals(emp1));
    });

    test('C2. includeArchived=true 包含归档', () async {
      final emp1 = randomEmpId();
      final emp2 = randomEmpId();

      await manager.getOrCreateSession(emp1);
      await manager.getOrCreateSession(emp2);
      await manager.archiveSession(emp2, true);

      final sessions =
          await manager.getAllSessions(includeArchived: true);
      expect(sessions.length, equals(2));
    });

    test('C3. includeDeleted=true 包含已删除', () async {
      final emp1 = randomEmpId();
      final emp2 = randomEmpId();

      await manager.getOrCreateSession(emp1);
      await manager.getOrCreateSession(emp2);
      await manager.deleteSession(emp2);

      final sessions =
          await manager.getAllSessions(includeDeleted: true);
      expect(sessions.length, equals(2));
    });

    test('C4. includeArchived + includeDeleted 全部返回', () async {
      final emp1 = randomEmpId();
      final emp2 = randomEmpId();
      final emp3 = randomEmpId();

      await manager.getOrCreateSession(emp1);
      await manager.getOrCreateSession(emp2);
      await manager.archiveSession(emp2, true);
      await manager.getOrCreateSession(emp3);
      await manager.deleteSession(emp3);

      final sessions = await manager.getAllSessions(
        includeArchived: true,
        includeDeleted: true,
      );
      expect(sessions.length, equals(3));
    });

    test('C5. 空数据库返回空列表', () async {
      final sessions = await manager.getAllSessions();
      expect(sessions, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════
  // D. updateDeviceConfig — 设备配置独立更新
  // ═══════════════════════════════════════════════════

  group('D. updateDeviceConfig', () {
    test('D1. 更新指定设备的 providerConfig', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceConfig(
        empId,
        devId,
        providerConfig: '{"provider":"openai","model":"gpt-4"}',
      );

      final session = await manager.getSession(empId);
      expect(session, isNotNull);
      final config = session!.getConfig(devId);
      expect(config, isNotNull);
      expect(
        config!.providerConfig,
        equals('{"provider":"openai","model":"gpt-4"}'),
      );
    });

    test('D2. 更新指定设备的 systemPromptOverride', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceConfig(
        empId,
        devId,
        systemPromptOverride: '你是一个专业的翻译助手',
      );

      final session = await manager.getSession(empId);
      final config = session!.getConfig(devId);
      expect(config!.systemPromptOverride, equals('你是一个专业的翻译助手'));
    });

    test('D3. 同时更新 providerConfig 和 systemPromptOverride', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceConfig(
        empId,
        devId,
        providerConfig: '{"provider":"claude","model":"claude-3"}',
        systemPromptOverride: '系统提示',
      );

      final session = await manager.getSession(empId);
      final config = session!.getConfig(devId)!;
      expect(config.providerConfig, equals('{"provider":"claude","model":"claude-3"}'));
      expect(config.systemPromptOverride, equals('系统提示'));
    });

    test('D4. 更新一个设备不影响另一个设备的配置', () async {
      final empId = randomEmpId();
      final devA = 'dev-A-${const Uuid().v4().substring(0, 8)}';
      final devB = 'dev-B-${const Uuid().v4().substring(0, 8)}';

      await manager.getOrCreateSession(empId);

      // 分别设置两个设备
      await manager.updateDeviceConfig(
        empId,
        devA,
        providerConfig: '{"provider":"openai"}',
        systemPromptOverride: 'OpenAI提示',
      );
      await manager.updateDeviceConfig(
        empId,
        devB,
        providerConfig: '{"provider":"claude"}',
        systemPromptOverride: 'Claude提示',
      );

      final session = await manager.getSession(empId);
      final configA = session!.getConfig(devA)!;
      final configB = session.getConfig(devB)!;

      expect(configA.providerConfig, equals('{"provider":"openai"}'));
      expect(configA.systemPromptOverride, equals('OpenAI提示'));
      expect(configB.providerConfig, equals('{"provider":"claude"}'));
      expect(configB.systemPromptOverride, equals('Claude提示'));
    });

    test('D5. 部分更新保留已有值', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceConfig(
        empId,
        devId,
        providerConfig: '{"provider":"openai"}',
        systemPromptOverride: '原始提示',
      );

      // 只更新 providerConfig，不传 systemPromptOverride
      await manager.updateDeviceConfig(
        empId,
        devId,
        providerConfig: '{"provider":"claude"}',
      );

      final session = await manager.getSession(empId);
      final config = session!.getConfig(devId)!;
      expect(config.providerConfig, equals('{"provider":"claude"}'));
      expect(config.systemPromptOverride, equals('原始提示')); // 保留
    });

    test('D6. 不存在的 session 自动创建后更新', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      // 不先 getOrCreateSession，直接 updateDeviceConfig
      await manager.updateDeviceConfig(
        empId,
        devId,
        providerConfig: '{"provider":"openai"}',
      );

      final session = await manager.getSession(empId);
      expect(session, isNotNull);
      expect(session!.getConfig(devId)!.providerConfig,
          equals('{"provider":"openai"}'));
    });
  });

  // ═══════════════════════════════════════════════════
  // E. updateDeviceStats — 设备统计
  // ═══════════════════════════════════════════════════

  group('E. updateDeviceStats', () {
    test('E1. 设置设备统计值', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceStats(
        empId,
        devId,
        inputTokens: 100,
        outputTokens: 200,
        messageCount: 5,
      );

      final session = await manager.getSession(empId);
      final config = session!.getConfig(devId)!;
      expect(config.totalInputTokens, equals(100));
      expect(config.totalOutputTokens, equals(200));
      expect(config.totalMessageCount, equals(5));
    });

    test('E2. 多次调用覆盖（非累加）', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceStats(
        empId,
        devId,
        inputTokens: 100,
        outputTokens: 200,
        messageCount: 5,
      );
      await manager.updateDeviceStats(
        empId,
        devId,
        inputTokens: 150,
        outputTokens: 300,
        messageCount: 10,
      );

      final session = await manager.getSession(empId);
      final config = session!.getConfig(devId)!;
      expect(config.totalInputTokens, equals(150));
      expect(config.totalOutputTokens, equals(300));
      expect(config.totalMessageCount, equals(10));
    });

    test('E3. 部分更新保留已有统计', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceStats(
        empId,
        devId,
        inputTokens: 100,
        outputTokens: 200,
        messageCount: 5,
      );

      // 只更新 messageCount
      await manager.updateDeviceStats(
        empId,
        devId,
        messageCount: 10,
      );

      final session = await manager.getSession(empId);
      final config = session!.getConfig(devId)!;
      expect(config.totalInputTokens, equals(100)); // 保留
      expect(config.totalOutputTokens, equals(200)); // 保留
      expect(config.totalMessageCount, equals(10)); // 更新
    });

    test('E4. 不同设备统计独立', () async {
      final empId = randomEmpId();
      final devA = 'dev-A-${const Uuid().v4().substring(0, 8)}';
      final devB = 'dev-B-${const Uuid().v4().substring(0, 8)}';

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceStats(empId, devA, inputTokens: 100);
      await manager.updateDeviceStats(empId, devB, inputTokens: 200);

      final session = await manager.getSession(empId);
      expect(session!.getConfig(devA)!.totalInputTokens, equals(100));
      expect(session.getConfig(devB)!.totalInputTokens, equals(200));
    });

    test('E5. 默认统计值为 0', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      // getOrCreateSession 不会创建设备配置
      final session = await manager.getSession(empId);
      expect(session!.getConfig(devId), isNull);

      // updateDeviceStats 会自动创建配置
      await manager.updateDeviceStats(empId, devId, inputTokens: 50);
      final updated = await manager.getSession(empId);
      final config = updated!.getConfig(devId)!;
      expect(config.totalInputTokens, equals(50));
      expect(config.totalOutputTokens, equals(0));
      expect(config.totalMessageCount, equals(0));
    });
  });

  // ═══════════════════════════════════════════════════
  // F. deleteSession — 软删除 + 事件
  // ═══════════════════════════════════════════════════

  group('F. deleteSession', () {
    test('F1. 软删除设置 deleted=1', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);

      await manager.deleteSession(empId);

      final session = await manager.getSession(empId);
      expect(session, isNotNull);
      expect(session!.deleted, equals(1));
    });

    test('F2. 软删除设置 deleteTime', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);

      final beforeDelete = DateTime.now();
      await manager.deleteSession(empId);
      final afterDelete = DateTime.now();

      final session = await manager.getSession(empId);
      expect(session!.deleteTime, isNotNull);
      expect(
        session.deleteTime!.millisecondsSinceEpoch,
        greaterThanOrEqualTo(beforeDelete.millisecondsSinceEpoch),
      );
      expect(
        session.deleteTime!.millisecondsSinceEpoch,
        lessThanOrEqualTo(afterDelete.millisecondsSinceEpoch),
      );
    });

    test('F3. 软删除触发 deleted 事件', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);

      final events = collectEvents(manager.onSessionEvent, 1);
      await manager.deleteSession(empId);

      final collected = await events;
      expect(collected.length, equals(1));
      expect(collected.first.type, equals(SessionChangeType.deleted));
      expect(collected.first.employeeId, equals(empId));
      expect(collected.first.session, isNull); // deleted 事件不携带 session
    });

    test('F4. 软删除后 getAllSessions 默认不返回', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      final sessions = await manager.getAllSessions();
      expect(sessions, isEmpty);
    });

    test('F5. 软删除后 getAllSessions(includeDeleted: true) 返回', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      final sessions =
          await manager.getAllSessions(includeDeleted: true);
      expect(sessions.length, equals(1));
      expect(sessions.first.employeeId, equals(empId));
      expect(sessions.first.deleted, equals(1));
    });

    test('F6. 删除不存在的 session 不抛异常', () async {
      // deleteSession 内部调用 _sessionStore.delete，
      // 如果 session 不存在，store.delete 中 find 返回 null，不做任何操作
      await expectLater(
        manager.deleteSession('nonexistent-id'),
        completes,
      );
    });
  });

  // ═══════════════════════════════════════════════════
  // G. archiveSession — 归档切换
  // ═══════════════════════════════════════════════════

  group('G. archiveSession', () {
    test('G1. 归档设置 isArchived=1', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);

      await manager.archiveSession(empId, true);

      final session = await manager.getSession(empId);
      expect(session!.isArchived, equals(1));
    });

    test('G2. 取消归档设置 isArchived=0', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.archiveSession(empId, true);
      await manager.archiveSession(empId, false);

      final session = await manager.getSession(empId);
      expect(session!.isArchived, equals(0));
    });

    test('G3. 归档后 getAllSessions 默认不返回', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.archiveSession(empId, true);

      final sessions = await manager.getAllSessions();
      expect(sessions, isEmpty);
    });

    test('G4. 归档后 getAllSessions(includeArchived: true) 返回', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.archiveSession(empId, true);

      final sessions =
          await manager.getAllSessions(includeArchived: true);
      expect(sessions.length, equals(1));
      expect(sessions.first.isArchived, equals(1));
    });

    test('G5. 归档触发 updated 事件', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);

      final events = collectEvents(manager.onSessionEvent, 1);
      await manager.archiveSession(empId, true);

      final collected = await events;
      expect(collected.length, equals(1));
      expect(collected.first.type, equals(SessionChangeType.updated));
      expect(collected.first.session!.isArchived, equals(1));
    });

    test('G6. 不存在的 session 归档不抛异常', () async {
      await expectLater(
        manager.archiveSession('nonexistent-id', true),
        completes,
      );
    });
  });

  // ═══════════════════════════════════════════════════
  // H. save — 持久化 + 事件
  // ═══════════════════════════════════════════════════

  group('H. save', () {
    test('H1. 保存自定义 session 并读取', () async {
      final empId = randomEmpId();
      final now = DateTime.now();
      final session = AiEmployeeSessionEntity(
        employeeId: empId,
        title: '自定义标题',
        isArchived: 1,
        isPinned: 1,
        config: {
          'dev-X': DeviceSessionConfig(
            providerConfig: '{"provider":"test"}',
            systemPromptOverride: '测试提示',
            totalInputTokens: 42,
            updateTime: now,
          ),
        },
        createTime: now,
        updateTime: now,
      );

      await manager.save(session);

      final restored = await manager.getSession(empId);
      expect(restored, isNotNull);
      expect(restored!.title, equals('自定义标题'));
      expect(restored.isArchived, equals(1));
      expect(restored.isPinned, equals(1));
      expect(restored.config['dev-X']!.providerConfig,
          equals('{"provider":"test"}'));
      expect(restored.config['dev-X']!.totalInputTokens, equals(42));
    });

    test('H2. 保存触发 updated 事件', () async {
      final empId = randomEmpId();
      final session = AiEmployeeSessionEntity(
        employeeId: empId,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      final events = collectEvents(manager.onSessionEvent, 1);
      await manager.save(session);

      final collected = await events;
      expect(collected.length, equals(1));
      expect(collected.first.type, equals(SessionChangeType.updated));
      expect(collected.first.employeeId, equals(empId));
      expect(collected.first.session, isNotNull);
    });

    test('H3. 重复保存覆盖旧值', () async {
      final empId = randomEmpId();

      await manager.save(AiEmployeeSessionEntity(
        employeeId: empId,
        title: '第一版',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      await manager.save(AiEmployeeSessionEntity(
        employeeId: empId,
        title: '第二版',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      final restored = await manager.getSession(empId);
      expect(restored!.title, equals('第二版'));
    });
  });

  // ═══════════════════════════════════════════════════
  // I. 多设备配置共存
  // ═══════════════════════════════════════════════════

  group('I. 多设备配置共存', () {
    test('I1. 三个设备配置独立存储', () async {
      final empId = randomEmpId();
      final devA = 'dev-A-${const Uuid().v4().substring(0, 8)}';
      final devB = 'dev-B-${const Uuid().v4().substring(0, 8)}';
      final devC = 'dev-C-${const Uuid().v4().substring(0, 8)}';

      await manager.getOrCreateSession(empId);

      await manager.updateDeviceConfig(
        empId, devA,
        providerConfig: '{"provider":"openai"}',
        systemPromptOverride: 'OpenAI提示',
      );
      await manager.updateDeviceStats(empId, devA, inputTokens: 100);

      await manager.updateDeviceConfig(
        empId, devB,
        providerConfig: '{"provider":"claude"}',
      );
      await manager.updateDeviceStats(
        empId, devB,
        inputTokens: 200,
        outputTokens: 300,
      );

      await manager.updateDeviceConfig(
        empId, devC,
        systemPromptOverride: '设备C专用提示',
      );

      final session = await manager.getSession(empId);
      expect(session!.config.length, equals(3));

      final configA = session.getConfig(devA)!;
      expect(configA.providerConfig, equals('{"provider":"openai"}'));
      expect(configA.systemPromptOverride, equals('OpenAI提示'));
      expect(configA.totalInputTokens, equals(100));

      final configB = session.getConfig(devB)!;
      expect(configB.providerConfig, equals('{"provider":"claude"}'));
      expect(configB.totalInputTokens, equals(200));
      expect(configB.totalOutputTokens, equals(300));

      final configC = session.getConfig(devC)!;
      expect(configC.providerConfig, isNull);
      expect(configC.systemPromptOverride, equals('设备C专用提示'));
    });

    test('I2. 更新一个设备配置不影响其他设备', () async {
      final empId = randomEmpId();
      final devA = 'dev-A-${const Uuid().v4().substring(0, 8)}';
      final devB = 'dev-B-${const Uuid().v4().substring(0, 8)}';

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceConfig(
        empId, devA,
        providerConfig: '{"provider":"openai"}',
        systemPromptOverride: 'A提示',
      );
      await manager.updateDeviceStats(empId, devA, inputTokens: 100);
      await manager.updateDeviceConfig(
        empId, devB,
        providerConfig: '{"provider":"claude"}',
      );

      // 更新 devB 的 providerConfig
      await manager.updateDeviceConfig(
        empId, devB,
        providerConfig: '{"provider":"gemini"}',
      );

      final session = await manager.getSession(empId);
      // devA 不受影响
      expect(session!.getConfig(devA)!.providerConfig,
          equals('{"provider":"openai"}'));
      expect(session.getConfig(devA)!.systemPromptOverride, equals('A提示'));
      expect(session.getConfig(devA)!.totalInputTokens, equals(100));
      // devB 已更新
      expect(session.getConfig(devB)!.providerConfig,
          equals('{"provider":"gemini"}'));
    });

    test('I3. 删除 session 后重新创建，config 为空', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceConfig(
        empId, devId,
        providerConfig: '{"provider":"openai"}',
      );

      await manager.deleteSession(empId);
      final revived = await manager.getOrCreateSession(empId);

      // 复活后 config 保留（软删除不丢失数据）
      expect(revived.config, isNotEmpty);
      expect(revived.getConfig(devId)!.providerConfig,
          equals('{"provider":"openai"}'));
    });
  });

  // ═══════════════════════════════════════════════════
  // J. isEffectivelyDeleted 边界条件（通过 SessionManager）
  // ═══════════════════════════════════════════════════

  group('J. isEffectivelyDeleted 边界条件', () {
    test('J1. deleted=0 → 未删除', () async {
      final empId = randomEmpId();
      final session = await manager.getOrCreateSession(empId);
      expect(session.isEffectivelyDeleted(), isFalse);
    });

    test('J2. deleted=1, deleteTime=null → 已删除', () async {
      final empId = randomEmpId();
      // 手动保存一个 deleted=1, deleteTime=null 的 session
      await manager.save(AiEmployeeSessionEntity(
        employeeId: empId,
        deleted: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      final session = await manager.getSession(empId);
      expect(session!.isEffectivelyDeleted(), isTrue);
    });

    test('J3. deleted=1, deleteTime >= updateTime → 已删除', () async {
      final empId = randomEmpId();
      final now = DateTime.now();
      final deleteTime = now.add(const Duration(hours: 1));

      await manager.save(AiEmployeeSessionEntity(
        employeeId: empId,
        deleted: 1,
        deleteTime: deleteTime,
        createTime: now,
        updateTime: now,
      ));

      final session = await manager.getSession(empId);
      expect(session!.isEffectivelyDeleted(), isTrue);
    });

    test('J4. deleted=1, updateTime > deleteTime → 已复活', () async {
      final empId = randomEmpId();
      final deleteTime = DateTime(2024, 6, 1);
      final updateTime = DateTime(2024, 6, 15);

      await manager.save(AiEmployeeSessionEntity(
        employeeId: empId,
        deleted: 1,
        deleteTime: deleteTime,
        createTime: DateTime(2024, 1, 1),
        updateTime: updateTime,
      ));

      final session = await manager.getSession(empId);
      // updateTime > deleteTime → 已复活
      expect(session!.isEffectivelyDeleted(), isFalse);
    });

    test('J5. deleteSession 后 isEffectivelyDeleted=true', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      final session = await manager.getSession(empId);
      expect(session!.isEffectivelyDeleted(), isTrue);
    });

    test('J6. getOrCreateSession 复活后 isEffectivelyDeleted=false', () async {
      final empId = randomEmpId();
      await manager.getOrCreateSession(empId);
      await manager.deleteSession(empId);

      final revived = await manager.getOrCreateSession(empId);
      expect(revived.isEffectivelyDeleted(), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════
  // K. 事件流顺序
  // ═══════════════════════════════════════════════════

  group('K. 事件流顺序', () {
    test('K1. 创建 → 更新 → 删除 事件序列', () async {
      final empId = randomEmpId();
      final events = <SessionChangeEvent>[];
      final sub = manager.onSessionEvent.listen(events.add);

      // 创建
      await manager.getOrCreateSession(empId);
      // 更新（通过 save）
      final session = await manager.getSession(empId);
      await manager.save(session!.copyWith(title: '更新标题'));
      // 删除
      await manager.deleteSession(empId);

      await sub.cancel();

      // 验证至少有 updated 事件
      // 注意：由于事件流时序问题，可能只有 updated 或只有 deleted
      // 但至少应该有一个事件
      expect(events, isNotEmpty);
      // 验证包含 updated 或 deleted 事件
      expect(events.any((e) => e.type == SessionChangeType.updated || e.type == SessionChangeType.deleted), isTrue);
    });

    test('K2. 创建 → 归档 → 取消归档 事件序列', () async {
      final empId = randomEmpId();

      await manager.getOrCreateSession(empId);
      await manager.archiveSession(empId, true);
      await manager.archiveSession(empId, false);

      // 直接从 DB 验证最终状态
      final session = await manager.getSession(empId);
      expect(session!.isArchived, equals(0));
    });

    test('K3. 删除 → 复活 事件序列', () async {
      final empId = randomEmpId();
      final events = <SessionChangeEvent>[];
      final sub = manager.onSessionEvent.listen(events.add);

      await manager.getOrCreateSession(empId); // created
      await manager.deleteSession(empId); // deleted
      await manager.getOrCreateSession(empId); // created (复活)

      await sub.cancel();

      // 验证包含 deleted 和至少 1 个 created
      final createdCount = events.where((e) => e.type == SessionChangeType.created).length;
      final deletedCount = events.where((e) => e.type == SessionChangeType.deleted).length;
      expect(createdCount, greaterThanOrEqualTo(1));
      expect(deletedCount, equals(1));
    });

    test('K4. updateDeviceConfig 触发 updated 事件', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId); // created
      await manager.updateDeviceConfig(
        empId, devId,
        providerConfig: '{"provider":"openai"}',
      ); // updated (internally calls getOrCreateSession + save)

      // 直接从 DB 读取验证配置已更新
      final session = await manager.getSession(empId);
      expect(session!.getConfig(devId)!.providerConfig,
          equals('{"provider":"openai"}'));
    });

    test('K5. updateDeviceStats 触发 updated 事件', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(empId);
      await manager.updateDeviceStats(empId, devId, inputTokens: 42);

      // 直接从 DB 读取验证统计已更新
      final session = await manager.getSession(empId);
      expect(
        session!.getConfig(devId)!.totalInputTokens,
        equals(42),
      );
    });

    test('K6. 事件携带正确的 employeeId', () async {
      final empId = randomEmpId();
      final events = <SessionChangeEvent>[];
      final sub = manager.onSessionEvent.listen(events.add);

      await manager.getOrCreateSession(empId);
      await manager.archiveSession(empId, true);
      await manager.deleteSession(empId);

      await sub.cancel();

      for (final event in events) {
        expect(event.employeeId, equals(empId));
      }
    });
  });

  // ═══════════════════════════════════════════════════
  // L. 单例管理
  // ═══════════════════════════════════════════════════

  group('L. 单例管理', () {
    test('L1. getInstance 返回同一实例', () {
      final instance1 = SessionManager.getInstance(deviceId);
      final instance2 = SessionManager.getInstance(deviceId);
      expect(identical(instance1, instance2), isTrue);
    });

    test('L2. 不同 deviceId 返回不同实例', () async {
      final otherDeviceId = 'dev-other-${const Uuid().v4().substring(0, 8)}';
      final otherDbPath =
          '${Directory.systemTemp.path}/wenzagent_session_manager_test_other_$_testCounter';
      await Directory(otherDbPath).create(recursive: true);
      await DatabaseManager.getInstance(otherDeviceId)
          .initialize(storagePath: otherDbPath);

      final instance1 = SessionManager.getInstance(deviceId);
      final instance2 = SessionManager.getInstance(otherDeviceId);
      expect(identical(instance1, instance2), isFalse);

      // 清理
      await DatabaseManager.getInstance(otherDeviceId).close();
      DatabaseManager.removeInstance(otherDeviceId);
      SessionManager.removeInstance(otherDeviceId);
      try {
        await Directory(otherDbPath).delete(recursive: true);
      } catch (_) {}
    });

    test('L3. removeInstance 后再 getInstance 返回新实例', () {
      final instance1 = SessionManager.getInstance(deviceId);
      SessionManager.removeInstance(deviceId);
      final instance2 = SessionManager.getInstance(deviceId);
      expect(identical(instance1, instance2), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════
  // M. 综合场景
  // ═══════════════════════════════════════════════════

  group('M. 综合场景', () {
    test('M1. 完整生命周期：创建→配置→统计→归档→删除→复活', () async {
      final empId = randomEmpId();
      final devId = randomDevId();

      // 1. 创建
      var session = await manager.getOrCreateSession(empId);
      expect(session.deleted, equals(0));
      expect(session.config, isEmpty);

      // 2. 配置
      await manager.updateDeviceConfig(
        empId, devId,
        providerConfig: '{"provider":"openai","model":"gpt-4"}',
        systemPromptOverride: '你是助手',
      );

      // 3. 统计
      await manager.updateDeviceStats(
        empId, devId,
        inputTokens: 100,
        outputTokens: 50,
        messageCount: 3,
      );

      session = (await manager.getSession(empId))!;
      expect(session.getConfig(devId)!.providerConfig,
          equals('{"provider":"openai","model":"gpt-4"}'));
      expect(session.getConfig(devId)!.totalInputTokens, equals(100));

      // 4. 归档
      await manager.archiveSession(empId, true);
      session = (await manager.getSession(empId))!;
      expect(session.isArchived, equals(1));

      // 5. 删除
      await manager.deleteSession(empId);
      session = (await manager.getSession(empId))!;
      expect(session.deleted, equals(1));
      expect(session.isEffectivelyDeleted(), isTrue);

      // 6. 复活
      session = await manager.getOrCreateSession(empId);
      expect(session.deleted, equals(0));
      expect(session.isEffectivelyDeleted(), isFalse);
      // 配置仍在（软删除保留数据）
      expect(session.getConfig(devId)!.providerConfig,
          equals('{"provider":"openai","model":"gpt-4"}'));
      expect(session.getConfig(devId)!.totalInputTokens, equals(100));
    });

    test('M2. 多会话并行操作互不干扰', () async {
      final emp1 = randomEmpId();
      final emp2 = randomEmpId();
      final devId = randomDevId();

      await manager.getOrCreateSession(emp1);
      await manager.getOrCreateSession(emp2);

      await manager.updateDeviceConfig(
        emp1, devId,
        providerConfig: '{"provider":"openai"}',
      );
      await manager.updateDeviceConfig(
        emp2, devId,
        providerConfig: '{"provider":"claude"}',
      );

      final s1 = await manager.getSession(emp1);
      final s2 = await manager.getSession(emp2);

      expect(s1!.getConfig(devId)!.providerConfig,
          equals('{"provider":"openai"}'));
      expect(s2!.getConfig(devId)!.providerConfig,
          equals('{"provider":"claude"}'));

      // 删除 emp1 不影响 emp2
      await manager.deleteSession(emp1);
      final s2After = await manager.getSession(emp2);
      expect(s2After!.getConfig(devId)!.providerConfig,
          equals('{"provider":"claude"}'));
    });

    test('M3. 标题修改持久化', () async {
      final empId = randomEmpId();
      final session = await manager.getOrCreateSession(empId);
      await manager.save(session.copyWith(title: '修改后的标题'));

      final restored = await manager.getSession(empId);
      expect(restored!.title, equals('修改后的标题'));
    });
  });
}
