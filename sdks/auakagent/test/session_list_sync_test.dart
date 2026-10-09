import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/persistence/store_merge_util.dart';
import 'package:auakagent/src/service/session_manager.dart';

int _testCounter = 0;

/// 会话列表同步(session)测试
///
/// Primary Key: employeeId（一个员工只有一个会话）
///
/// 同步路径1：event(lan广播+event) > update store
///   - Device A 本地变更 → 序列化 → LAN广播/事件推送 → Device B 收到 → 合并写入 store
///
/// 同步路径2：query > update store
///   - Device B 主动查询 Device A 的全部会话 → 逐条合并写入 store
///
/// 验证：
/// - 路径1：单条事件广播同步（create/update/delete/复活）
/// - 路径2：全量查询同步（批量拉取 + 合并）
/// - 两条路径的合并逻辑一致（StoreMergeUtil.mergeDeleteState）
/// - 端到端场景：离线→上线、并发冲突、多轮同步稳定性
void main() {
  late String testDbPathA;
  late String testDbPathB;
  late String deviceA;
  late String deviceB;
  late SessionManager managerA;
  late SessionManager managerB;

  setUp(() async {
    _testCounter++;
    final base =
        '${Directory.systemTemp.path}/wenzagent_session_list_sync_test_$_testCounter';

    testDbPathA = '$base/device_a';
    testDbPathB = '$base/device_b';
    await Directory(testDbPathA).create(recursive: true);
    await Directory(testDbPathB).create(recursive: true);

    deviceA = 'dev-a-${const Uuid().v4().substring(0, 8)}';
    deviceB = 'dev-b-${const Uuid().v4().substring(0, 8)}';

    await DatabaseManager.getInstance(deviceA).initialize(
      storagePath: testDbPathA,
    );
    await DatabaseManager.getInstance(deviceB).initialize(
      storagePath: testDbPathB,
    );

    managerA = SessionManager.getInstance(deviceA);
    managerB = SessionManager.getInstance(deviceB);
  });

  tearDown(() async {
    (managerA as SessionManagerImpl).dispose();
    (managerB as SessionManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceA).close();
    await DatabaseManager.getInstance(deviceB).close();
    DatabaseManager.removeInstance(deviceA);
    DatabaseManager.removeInstance(deviceB);
    SessionManager.removeInstance(deviceA);
    SessionManager.removeInstance(deviceB);
    try {
      await Directory(testDbPathA).delete(recursive: true);
      await Directory(testDbPathB).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  String randomEmpId() => 'emp-${const Uuid().v4().substring(0, 8)}';

  /// 创建会话实体
  AiEmployeeSessionEntity createSession({
    required String employeeId,
    String title = '新对话',
    Map<String, DeviceSessionConfig>? config,
    int isArchived = 0,
    int isPinned = 0,
    int deleted = 0,
    DateTime? deleteTime,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    final now = DateTime.now();
    return AiEmployeeSessionEntity(
      employeeId: employeeId,
      title: title,
      config: config,
      isArchived: isArchived,
      isPinned: isPinned,
      deleted: deleted,
      deleteTime: deleteTime,
      createTime: createTime ?? now,
      updateTime: updateTime ?? now,
    );
  }

  // ─── 同步路径1 模拟：event(lan广播+event) → update store ───

  /// 模拟 LAN 广播同步路径：Device A 将单条会话序列化后推送到 Device B
  ///
  /// 对应 DataSyncManager.broadcastSessionToAllDevices：
  ///   A → invokeRemote(B, methodSyncSessions, {sessions: [session.toMap()]})
  ///
  /// 对应 HostRpcMethods.methodSyncSessions 接收端：
  ///   B 收到后执行 StoreMergeUtil.mergeDeleteState 合并写入
  Future<void> syncViaEvent(
    SessionManager fromManager,
    SessionManager toManager,
    String employeeId,
  ) async {
    final session = await fromManager.getSession(employeeId);
    if (session == null) return;

    // 序列化 → 反序列化（模拟网络传输）
    final map = session.toMap();
    final received = AiEmployeeSessionEntity.fromMap(map);

    // 接收端执行合并逻辑（与 HostRpcMethods.methodSyncSessions 一致）
    final existing = await toManager.getSession(received.employeeId);
    if (existing == null) {
      if (received.deleted != 1) {
        await toManager.save(received);
      }
    } else {
      final mergeResult = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: existing.deleteTime,
        localDeleted: existing.deleted,
        remoteDeleteTime: received.deleteTime,
        remoteDeleted: received.deleted,
        localUpdateTime: existing.updateTime,
        remoteUpdateTime: received.updateTime,
      );
      final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
        existing.updateTime,
        received.updateTime,
      );
      final shouldUpdateDelete =
          mergeResult.mergedDeleteTime != existing.deleteTime ||
              mergeResult.mergedDeleted != existing.deleted;

      if (shouldUpdateData || shouldUpdateDelete) {
        final base = shouldUpdateData ? received : existing;
        await toManager.save(base.copyWith(
          deleted: mergeResult.mergedDeleted,
          deleteTime: mergeResult.mergedDeleteTime,
        ));
      }
    }
  }

  // ─── 同步路径2 模拟：query → update store ───

  /// 模拟主动查询同步路径：Device B 查询 Device A 的全部会话列表后合并写入
  ///
  /// 对应 DataSyncManager._doSyncSessionsFromDevices：
  ///   B → invokeRemote(A, methodGetSessions, {includeDeleted: true})
  ///   B 收到后逐条执行 StoreMergeUtil.mergeDeleteState 合并
  Future<void> syncViaQuery(
    SessionManager fromManager,
    SessionManager toManager,
  ) async {
    // 查询远端全部会话（包含已删除）
    final remoteSessions =
        await fromManager.getAllSessions(includeDeleted: true);

    for (final remote in remoteSessions) {
      // 序列化 → 反序列化（模拟网络传输）
      final map = remote.toMap();
      final received = AiEmployeeSessionEntity.fromMap(map);

      final existing = await toManager.getSession(received.employeeId);
      if (existing == null) {
        if (received.deleted != 1) {
          await toManager.save(received);
        }
      } else {
        final mergeResult = StoreMergeUtil.mergeDeleteState(
          localDeleteTime: existing.deleteTime,
          localDeleted: existing.deleted,
          remoteDeleteTime: received.deleteTime,
          remoteDeleted: received.deleted,
          localUpdateTime: existing.updateTime,
          remoteUpdateTime: received.updateTime,
        );
        final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
          existing.updateTime,
          received.updateTime,
        );
        final shouldUpdateDelete =
            mergeResult.mergedDeleteTime != existing.deleteTime ||
                mergeResult.mergedDeleted != existing.deleted;

        if (shouldUpdateData || shouldUpdateDelete) {
          final base = shouldUpdateData ? received : existing;
          await toManager.save(base.copyWith(
            deleted: mergeResult.mergedDeleted,
            deleteTime: mergeResult.mergedDeleteTime,
          ));
        }
      }
    }
  }

  // ═══════════════════════════════════════════════════
  // 同步路径1：event(lan广播+event) > update store
  // ═══════════════════════════════════════════════════

  group('同步路径1: event广播同步', () {
    // ---- 1.1 创建同步 ----

    group('1.1 创建同步', () {
      test('Device A 新建会话 → 广播到 Device B → B 可查到', () async {
        final empId = randomEmpId();

        // Device A 创建会话
        await managerA.save(createSession(
          employeeId: empId,
          title: '项目讨论',
        ));

        // Device B 初始无此会话
        expect(await managerB.getSession(empId), isNull);

        // 广播同步
        await syncViaEvent(managerA, managerB, empId);

        // Device B 可查到
        final synced = await managerB.getSession(empId);
        expect(synced, isNotNull);
        expect(synced!.title, equals('项目讨论'));
        expect(synced.deleted, equals(0));
        expect(synced.employeeId, equals(empId));
      });

      test('广播已删除的会话 → 接收端不保存', () async {
        final empId = randomEmpId();

        // Device A 创建后删除
        await managerA.save(createSession(
          employeeId: empId,
          title: '待删除',
          deleted: 1,
          deleteTime: DateTime(2024, 6, 1),
          updateTime: DateTime(2024, 6, 1),
        ));

        // 广播（已删除）
        await syncViaEvent(managerA, managerB, empId);

        // Device B 不应保存
        expect(await managerB.getSession(empId), isNull);
      });

      test('多次广播同一会话 → 幂等', () async {
        final empId = randomEmpId();

        await managerA.save(createSession(
          employeeId: empId,
          title: '幂等测试',
          updateTime: DateTime(2024, 6, 1),
        ));

        // 广播 3 次
        for (var i = 0; i < 3; i++) {
          await syncViaEvent(managerA, managerB, empId);
        }

        final synced = await managerB.getSession(empId);
        expect(synced, isNotNull);
        expect(synced!.title, equals('幂等测试'));
      });
    });

    // ---- 1.2 更新同步 ----

    group('1.2 更新同步', () {
      test('Device A 更新标题 → 广播 → Device B 标题更新', () async {
        final empId = randomEmpId();

        // 初始同步
        await managerA.save(createSession(
          employeeId: empId,
          title: '旧标题',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 更新标题
        await managerA.save(createSession(
          employeeId: empId,
          title: '新标题',
          updateTime: DateTime(2024, 6, 2),
        ));
        await syncViaEvent(managerA, managerB, empId);

        final synced = await managerB.getSession(empId);
        expect(synced!.title, equals('新标题'));
      });

      test('Device A 更新 config → 广播 → Device B config 同步', () async {
        final empId = randomEmpId();

        // 初始同步
        await managerA.save(createSession(
          employeeId: empId,
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 更新设备配置
        final configMap = <String, DeviceSessionConfig>{
          deviceA: DeviceSessionConfig(
            providerConfig: '{"provider":"openai","model":"gpt-4"}',
            systemPromptOverride: '你是AI助手',
            totalInputTokens: 100,
            totalOutputTokens: 50,
            totalMessageCount: 5,
            updateTime: DateTime(2024, 6, 2),
          ),
        };
        await managerA.save(createSession(
          employeeId: empId,
          config: configMap,
          updateTime: DateTime(2024, 6, 2),
        ));
        await syncViaEvent(managerA, managerB, empId);

        final synced = await managerB.getSession(empId);
        expect(synced!.config[deviceA], isNotNull);
        expect(synced.config[deviceA]!.providerConfig,
            equals('{"provider":"openai","model":"gpt-4"}'));
        expect(synced.config[deviceA]!.systemPromptOverride, equals('你是AI助手'));
        expect(synced.config[deviceA]!.totalInputTokens, equals(100));
      });

      test('Device B 有更新数据 → 收到旧广播不覆盖', () async {
        final empId = randomEmpId();

        // Device A 创建
        await managerA.save(createSession(
          employeeId: empId,
          title: '初始',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device B 本地更新（时间更新）
        await managerB.save(createSession(
          employeeId: empId,
          title: 'B的更新',
          updateTime: DateTime(2024, 6, 5),
        ));

        // Device A 发出旧广播（时间更旧）
        await managerA.save(createSession(
          employeeId: empId,
          title: 'A的旧更新',
          updateTime: DateTime(2024, 6, 2),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device B 保留自己的更新
        final synced = await managerB.getSession(empId);
        expect(synced!.title, equals('B的更新'));
      });

      test('归档状态同步', () async {
        final empId = randomEmpId();

        await managerA.save(createSession(
          employeeId: empId,
          isArchived: 0,
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 归档
        await managerA.save(createSession(
          employeeId: empId,
          isArchived: 1,
          updateTime: DateTime(2024, 6, 2),
        ));
        await syncViaEvent(managerA, managerB, empId);

        final synced = await managerB.getSession(empId);
        expect(synced!.isArchived, equals(1));
      });

      test('置顶状态同步', () async {
        final empId = randomEmpId();

        await managerA.save(createSession(
          employeeId: empId,
          isPinned: 0,
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 置顶
        await managerA.save(createSession(
          employeeId: empId,
          isPinned: 1,
          updateTime: DateTime(2024, 6, 2),
        ));
        await syncViaEvent(managerA, managerB, empId);

        final synced = await managerB.getSession(empId);
        expect(synced!.isPinned, equals(1));
      });
    });

    // ---- 1.3 删除同步 ----

    group('1.3 删除同步', () {
      test('Device A 软删除 → 广播 → Device B 同步删除', () async {
        final empId = randomEmpId();

        // 初始同步
        await managerA.save(createSession(
          employeeId: empId,
          title: '待删除会话',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 软删除
        await managerA.save(createSession(
          employeeId: empId,
          title: '待删除会话',
          deleted: 1,
          deleteTime: DateTime(2024, 6, 5),
          updateTime: DateTime(2024, 6, 5),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device B 也标记为删除
        final synced = await managerB.getSession(empId);
        expect(synced, isNotNull);
        expect(synced!.deleted, equals(1));
        expect(synced.deleteTime, isNotNull);
      });

      test('Device B 已删除 → 收到旧数据不复活', () async {
        final empId = randomEmpId();

        // 两端都有会话
        await managerA.save(createSession(
          employeeId: empId,
          title: '测试',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device B 先删除
        await managerB.save(createSession(
          employeeId: empId,
          title: '测试',
          deleted: 1,
          deleteTime: DateTime(2024, 6, 5),
          updateTime: DateTime(2024, 6, 5),
        ));

        // Device A 发出旧的更新广播（deleteTime=null）
        await managerA.save(createSession(
          employeeId: empId,
          title: 'A的更新',
          updateTime: DateTime(2024, 6, 2),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device B 仍然保持删除状态
        final synced = await managerB.getSession(empId);
        expect(synced!.deleted, equals(1));
      });

      test('双向删除 → deleteTime 合并取较大值', () async {
        final empId = randomEmpId();

        // 两端都有会话
        await managerA.save(createSession(
          employeeId: empId,
          title: '测试',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 删除（较早）
        final deleteTimeA = DateTime(2024, 6, 3);
        await managerA.save(createSession(
          employeeId: empId,
          deleted: 1,
          deleteTime: deleteTimeA,
          updateTime: DateTime(2024, 6, 3),
        ));

        // Device B 也删除（较晚）
        final deleteTimeB = DateTime(2024, 6, 5);
        await managerB.save(createSession(
          employeeId: empId,
          deleted: 1,
          deleteTime: deleteTimeB,
          updateTime: DateTime(2024, 6, 5),
        ));

        // A 广播到 B → B 的 deleteTime 更大，保留 B 的
        await syncViaEvent(managerA, managerB, empId);

        var syncedB = await managerB.getSession(empId);
        expect(syncedB!.deleted, equals(1));
        expect(syncedB.deleteTime!.millisecondsSinceEpoch,
            equals(deleteTimeB.millisecondsSinceEpoch));

        // B 广播到 A → A 的 deleteTime 更小，更新为 B 的
        await syncViaEvent(managerB, managerA, empId);

        var syncedA = await managerA.getSession(empId);
        expect(syncedA!.deleted, equals(1));
        expect(syncedA.deleteTime!.millisecondsSinceEpoch,
            equals(deleteTimeB.millisecondsSinceEpoch));
      });
    });

    // ---- 1.4 复活同步 ----

    group('1.4 复活同步', () {
      test('远程明确复活(updateTime更新) → 本地跟随复活', () async {
        final empId = randomEmpId();

        // 两端都有已删除的会话
        await managerA.save(createSession(
          employeeId: empId,
          title: '已删除',
          deleted: 1,
          deleteTime: DateTime(2024, 6, 3),
          updateTime: DateTime(2024, 6, 3),
        ));
        await syncViaEvent(managerA, managerB, empId);

        // Device A 复活（getOrCreateSession 会自动复活 deleted=1 的会话）
        await managerA.save(createSession(
          employeeId: empId,
          title: '已复活',
          deleted: 0,
          deleteTime: null,
          updateTime: DateTime(2024, 6, 10), // updateTime 更新
        ));

        // 广播到 B
        await syncViaEvent(managerA, managerB, empId);

        // Device B 也复活
        final synced = await managerB.getSession(empId);
        expect(synced, isNotNull);
        expect(synced!.deleted, equals(0));
        expect(synced.title, equals('已复活'));
      });
    });
  });

  // ═══════════════════════════════════════════════════
  // 同步路径2：query > update store
  // ═══════════════════════════════════════════════════

  group('同步路径2: query全量同步', () {
    // ---- 2.1 全量拉取 ----

    group('2.1 全量拉取', () {
      test('Device A 有 3 个会话 → Device B 全量查询后同步 3 个', () async {
        final emp1 = randomEmpId();
        final emp2 = randomEmpId();
        final emp3 = randomEmpId();

        await managerA.save(createSession(employeeId: emp1, title: '项目A'));
        await managerA.save(createSession(employeeId: emp2, title: '项目B'));
        await managerA.save(createSession(employeeId: emp3, title: '项目C'));

        // Device B 初始为空
        expect(await managerB.getAllSessions(), isEmpty);

        // 全量查询同步
        await syncViaQuery(managerA, managerB);

        final sessionsB = await managerB.getAllSessions();
        expect(sessionsB.length, equals(3));

        final titles = sessionsB.map((s) => s.title).toSet();
        expect(titles, containsAll(['项目A', '项目B', '项目C']));
      });

      test('全量同步跳过已删除的会话（本地不存在时）', () async {
        final emp1 = randomEmpId();
        final emp2 = randomEmpId();

        // Device A 有一个正常会话和一个已删除会话
        await managerA.save(createSession(employeeId: emp1, title: '正常'));
        await managerA.save(createSession(
          employeeId: emp2,
          title: '已删除',
          deleted: 1,
          deleteTime: DateTime(2024, 6, 1),
          updateTime: DateTime(2024, 6, 1),
        ));

        await syncViaQuery(managerA, managerB);

        final sessionsB = await managerB.getAllSessions();
        expect(sessionsB.length, equals(1));
        expect(sessionsB.first.title, equals('正常'));
      });

      test('全量同步包含已删除会话的合并（本地已有记录）', () async {
        final empId = randomEmpId();

        // 两端都有此会话
        await managerA.save(createSession(
          employeeId: empId,
          title: '共享会话',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaQuery(managerA, managerB);

        // Device A 删除
        await managerA.save(createSession(
          employeeId: empId,
          title: '共享会话',
          deleted: 1,
          deleteTime: DateTime(2024, 6, 5),
          updateTime: DateTime(2024, 6, 5),
        ));

        // Device B 全量查询同步
        await syncViaQuery(managerA, managerB);

        final synced = await managerB.getSession(empId);
        expect(synced!.deleted, equals(1));
      });

      test('空数据库全量同步无副作用', () async {
        await syncViaQuery(managerA, managerB);

        expect(await managerB.getAllSessions(), isEmpty);
      });
    });

    // ---- 2.2 增量同步 ----

    group('2.2 增量同步', () {
      test('Device A 新增会话后，Device B 增量查询只拉到新增的', () async {
        final emp1 = randomEmpId();
        final emp2 = randomEmpId();

        // 初始同步
        await managerA.save(createSession(employeeId: emp1, title: '初始'));
        await syncViaQuery(managerA, managerB);
        expect((await managerB.getAllSessions()).length, equals(1));

        // Device A 新增
        await managerA.save(createSession(employeeId: emp2, title: '新增'));
        await syncViaQuery(managerA, managerB);

        final sessionsB = await managerB.getAllSessions();
        expect(sessionsB.length, equals(2));
      });

      test('Device A 更新会话后，Device B 增量查询更新', () async {
        final empId = randomEmpId();

        // 初始同步
        await managerA.save(createSession(
          employeeId: empId,
          title: '旧标题',
          updateTime: DateTime(2024, 6, 1),
        ));
        await syncViaQuery(managerA, managerB);

        // Device A 更新
        await managerA.save(createSession(
          employeeId: empId,
          title: '新标题',
          isPinned: 1,
          updateTime: DateTime(2024, 6, 5),
        ));
        await syncViaQuery(managerA, managerB);

        final synced = await managerB.getSession(empId);
        expect(synced!.title, equals('新标题'));
        expect(synced.isPinned, equals(1));
      });
    });

    // ---- 2.3 双向查询同步 ----

    group('2.3 双向查询同步', () {
      test('A→B 然后 B→A 双向同步后数据一致', () async {
        final emp1 = randomEmpId();
        final emp2 = randomEmpId();

        // Device A 有 emp1
        await managerA.save(createSession(employeeId: emp1, title: 'A创建'));
        // Device B 有 emp2
        await managerB.save(createSession(employeeId: emp2, title: 'B创建'));

        // 双向同步
        await syncViaQuery(managerA, managerB);
        await syncViaQuery(managerB, managerA);

        // 两端都有 2 个会话
        final sessionsA = await managerA.getAllSessions();
        final sessionsB = await managerB.getAllSessions();
        expect(sessionsA.length, equals(2));
        expect(sessionsB.length, equals(2));

        final titlesA = sessionsA.map((s) => s.title).toSet();
        final titlesB = sessionsB.map((s) => s.title).toSet();
        expect(titlesA, equals(titlesB));
        expect(titlesA, containsAll(['A创建', 'B创建']));
      });

      test('双向同步解决更新冲突（取 updateTime 更大的）', () async {
        final empId = randomEmpId();

        // 两端都有此会话
        await managerA.save(createSession(
          employeeId: empId,
          title: 'A版本',
          updateTime: DateTime(2024, 6, 3),
        ));
        await managerB.save(createSession(
          employeeId: empId,
          title: 'B版本',
          updateTime: DateTime(2024, 6, 5), // B 更新
        ));

        // 双向同步
        await syncViaQuery(managerA, managerB); // A→B: B更新，不覆盖
        await syncViaQuery(managerB, managerA); // B→A: A更新为B版本

        final syncedA = await managerA.getSession(empId);
        expect(syncedA!.title, equals('B版本'));

        final syncedB = await managerB.getSession(empId);
        expect(syncedB!.title, equals('B版本'));
      });
    });
  });

  // ═══════════════════════════════════════════════════
  // 两条路径一致性验证
  // ═══════════════════════════════════════════════════

  group('路径一致性: event 与 query 结果相同', () {
    test('同一变更通过 event 和 query 同步到新设备，结果一致', () async {
      final empId = randomEmpId();

      // 准备第三个设备用于对比
      final testDbPathC =
          '${Directory.systemTemp.path}/wenzagent_session_list_sync_test_${_testCounter}_c';
      await Directory(testDbPathC).create(recursive: true);
      final deviceC = 'dev-c-${const Uuid().v4().substring(0, 8)}';
      await DatabaseManager.getInstance(deviceC).initialize(
        storagePath: testDbPathC,
      );
      final managerC = SessionManager.getInstance(deviceC);

      // Device A 创建会话
      await managerA.save(createSession(
        employeeId: empId,
        title: '一致性测试',
        isPinned: 1,
        isArchived: 0,
        config: {
          deviceA: DeviceSessionConfig(
            providerConfig: '{"provider":"openai"}',
            totalInputTokens: 42,
            updateTime: DateTime(2024, 6, 5),
          ),
        },
        updateTime: DateTime(2024, 6, 5),
      ));

      // 路径1: event 同步到 B
      await syncViaEvent(managerA, managerB, empId);

      // 路径2: query 同步到 C
      await syncViaQuery(managerA, managerC);

      // 验证 B 和 C 结果一致
      final syncedB = await managerB.getSession(empId);
      final syncedC = await managerC.getSession(empId);

      expect(syncedB, isNotNull);
      expect(syncedC, isNotNull);
      expect(syncedB!.title, equals(syncedC!.title));
      expect(syncedB.isPinned, equals(syncedC.isPinned));
      expect(syncedB.isArchived, equals(syncedC.isArchived));
      expect(syncedB.deleted, equals(syncedC.deleted));
      expect(syncedB.updateTime.millisecondsSinceEpoch,
          equals(syncedC.updateTime.millisecondsSinceEpoch));
      expect(syncedB.config[deviceA]!.providerConfig,
          equals(syncedC.config[deviceA]!.providerConfig));
      expect(syncedB.config[deviceA]!.totalInputTokens,
          equals(syncedC.config[deviceA]!.totalInputTokens));

      // 清理
      (managerC as SessionManagerImpl).dispose();
      await DatabaseManager.getInstance(deviceC).close();
      DatabaseManager.removeInstance(deviceC);
      SessionManager.removeInstance(deviceC);
      try {
        await Directory(testDbPathC).delete(recursive: true);
      } catch (_) {}
    });
  });

  // ═══════════════════════════════════════════════════
  // 端到端场景
  // ═══════════════════════════════════════════════════

  group('端到端场景', () {
    test('完整生命周期: 创建→同步→更新→同步→删除→同步→复活→同步', () async {
      final empId = randomEmpId();

      // 1. Device A 创建
      await managerA.save(createSession(
        employeeId: empId,
        title: '生命周期测试',
        updateTime: DateTime(2024, 6, 1),
      ));
      await syncViaEvent(managerA, managerB, empId);

      var syncedB = await managerB.getSession(empId);
      expect(syncedB, isNotNull);
      expect(syncedB!.title, equals('生命周期测试'));

      // 2. Device A 更新标题和配置
      await managerA.save(createSession(
        employeeId: empId,
        title: '更新后标题',
        config: {
          deviceA: DeviceSessionConfig(
            providerConfig: '{"provider":"openai","model":"gpt-4o"}',
            updateTime: DateTime(2024, 6, 3),
          ),
        },
        updateTime: DateTime(2024, 6, 3),
      ));
      await syncViaEvent(managerA, managerB, empId);

      syncedB = await managerB.getSession(empId);
      expect(syncedB!.title, equals('更新后标题'));
      expect(syncedB.config[deviceA]!.providerConfig,
          equals('{"provider":"openai","model":"gpt-4o"}'));

      // 3. Device A 软删除
      await managerA.save(createSession(
        employeeId: empId,
        title: '更新后标题',
        deleted: 1,
        deleteTime: DateTime(2024, 6, 5),
        updateTime: DateTime(2024, 6, 5),
      ));
      await syncViaEvent(managerA, managerB, empId);

      syncedB = await managerB.getSession(empId);
      expect(syncedB!.deleted, equals(1));

      // 4. Device A 复活（getOrCreateSession 场景）
      await managerA.save(createSession(
        employeeId: empId,
        title: '复活了',
        deleted: 0,
        deleteTime: null,
        updateTime: DateTime(2024, 6, 10),
      ));
      await syncViaEvent(managerA, managerB, empId);

      syncedB = await managerB.getSession(empId);
      expect(syncedB!.deleted, equals(0));
      expect(syncedB.title, equals('复活了'));
    });

    test('离线场景: Device B 离线期间 A 有多次变更 → 上线后全量同步', () async {
      final emp1 = randomEmpId();
      final emp2 = randomEmpId();
      final emp3 = randomEmpId();

      // Device B 离线前同步一次
      await managerA.save(createSession(
        employeeId: emp1,
        title: '已有会话',
        updateTime: DateTime(2024, 6, 1),
      ));
      await syncViaQuery(managerA, managerB);

      // Device B 离线期间，Device A 有多次变更
      // - emp1 更新
      await managerA.save(createSession(
        employeeId: emp1,
        title: '更新后的会话',
        isPinned: 1,
        updateTime: DateTime(2024, 6, 5),
      ));
      // - emp2 新建
      await managerA.save(createSession(
        employeeId: emp2,
        title: '新建会话',
        updateTime: DateTime(2024, 6, 3),
      ));
      // - emp3 新建后删除
      await managerA.save(createSession(
        employeeId: emp3,
        title: '临时会话',
        deleted: 1,
        deleteTime: DateTime(2024, 6, 4),
        updateTime: DateTime(2024, 6, 4),
      ));

      // Device B 上线，全量同步
      await syncViaQuery(managerA, managerB);

      // 验证
      final sessionsB = await managerB.getAllSessions();
      expect(sessionsB.length, equals(2)); // emp1 + emp2（emp3 已删除不保存）

      final emp1B = await managerB.getSession(emp1);
      expect(emp1B!.title, equals('更新后的会话'));
      expect(emp1B.isPinned, equals(1));

      final emp2B = await managerB.getSession(emp2);
      expect(emp2B!.title, equals('新建会话'));

      final emp3B = await managerB.getSession(emp3);
      expect(emp3B, isNull); // 已删除不保存
    });

    test('并发冲突: 两端同时更新同一会话 → 最终一致', () async {
      final empId = randomEmpId();

      // 初始同步
      await managerA.save(createSession(
        employeeId: empId,
        title: '初始',
        updateTime: DateTime(2024, 6, 1),
      ));
      await syncViaQuery(managerA, managerB);

      // 两端同时更新
      await managerA.save(createSession(
        employeeId: empId,
        title: 'A的更新',
        isPinned: 1,
        updateTime: DateTime(2024, 6, 5),
      ));
      await managerB.save(createSession(
        employeeId: empId,
        title: 'B的更新',
        isArchived: 1,
        updateTime: DateTime(2024, 6, 3),
      ));

      // 双向同步
      await syncViaQuery(managerA, managerB);
      await syncViaQuery(managerB, managerA);

      // A 的 updateTime 更大，最终一致取 A
      final syncedA = await managerA.getSession(empId);
      final syncedB = await managerB.getSession(empId);

      expect(syncedA!.title, equals('A的更新'));
      expect(syncedB!.title, equals('A的更新'));
      expect(syncedA.isPinned, equals(1));
      expect(syncedB.isPinned, equals(1));
    });

    test('多轮同步后数据稳定不漂移', () async {
      final empId = randomEmpId();

      await managerA.save(createSession(
        employeeId: empId,
        title: '稳定测试',
        isPinned: 1,
        updateTime: DateTime(2024, 6, 1),
      ));
      await syncViaQuery(managerA, managerB);

      // 执行 10 轮双向同步
      for (var i = 0; i < 10; i++) {
        await syncViaQuery(managerA, managerB);
        await syncViaQuery(managerB, managerA);
      }

      // 数据不变
      final syncedA = await managerA.getSession(empId);
      final syncedB = await managerB.getSession(empId);

      expect(syncedA!.title, equals('稳定测试'));
      expect(syncedB!.title, equals('稳定测试'));
      expect(syncedA.isPinned, equals(1));
      expect(syncedB.isPinned, equals(1));
    });

    test('序列化往返一致性（模拟网络传输）', () async {
      final empId = randomEmpId();
      final now = DateTime(2024, 6, 15, 10, 30, 0);

      final session = AiEmployeeSessionEntity(
        employeeId: empId,
        title: '序列化测试',
        config: {
          'dev-A': DeviceSessionConfig(
            providerConfig: '{"provider":"openai","model":"gpt-4"}',
            systemPromptOverride: '系统提示词',
            contextData: '{"project":"test"}',
            totalInputTokens: 1000,
            totalOutputTokens: 500,
            totalMessageCount: 42,
            updateTime: now,
          ),
          'dev-B': DeviceSessionConfig(
            providerConfig: '{"provider":"claude"}',
            totalInputTokens: 200,
            updateTime: now,
          ),
        },
        isArchived: 1,
        isPinned: 1,
        deleted: 0,
        createTime: now,
        updateTime: now,
      );

      // 模拟 toMap → 网络传输 → fromMap
      final map = session.toMap();
      final restored = AiEmployeeSessionEntity.fromMap(map);

      // 写入 Device B
      await managerB.save(restored);

      final synced = await managerB.getSession(empId);
      expect(synced, isNotNull);
      expect(synced!.employeeId, equals(empId));
      expect(synced.title, equals('序列化测试'));
      expect(synced.isArchived, equals(1));
      expect(synced.isPinned, equals(1));
      expect(synced.config.length, equals(2));
      expect(synced.config['dev-A']!.providerConfig,
          equals('{"provider":"openai","model":"gpt-4"}'));
      expect(synced.config['dev-A']!.totalInputTokens, equals(1000));
      expect(synced.config['dev-B']!.providerConfig,
          equals('{"provider":"claude"}'));
    });

    test('多会话同步后列表排序一致', () async {
      // Device A 创建多个会话，不同 pin 状态和时间
      await managerA.save(createSession(
        employeeId: randomEmpId(),
        title: '普通1',
        isPinned: 0,
        updateTime: DateTime(2024, 6, 3),
      ));
      await managerA.save(createSession(
        employeeId: randomEmpId(),
        title: '置顶1',
        isPinned: 1,
        updateTime: DateTime(2024, 6, 1),
      ));
      await managerA.save(createSession(
        employeeId: randomEmpId(),
        title: '普通2',
        isPinned: 0,
        updateTime: DateTime(2024, 6, 5),
      ));
      await managerA.save(createSession(
        employeeId: randomEmpId(),
        title: '置顶2',
        isPinned: 1,
        updateTime: DateTime(2024, 6, 2),
      ));

      await syncViaQuery(managerA, managerB);

      final listA = await managerA.getAllSessions();
      final listB = await managerB.getAllSessions();

      expect(listA.length, equals(listB.length));

      // 验证排序一致：is_pinned DESC, update_time DESC
      for (var i = 0; i < listA.length; i++) {
        expect(listA[i].employeeId, equals(listB[i].employeeId));
        expect(listA[i].title, equals(listB[i].title));
      }

      // 置顶在前
      expect(listB[0].isPinned, equals(1));
      expect(listB[1].isPinned, equals(1));
      expect(listB[2].isPinned, equals(0));
      expect(listB[3].isPinned, equals(0));
    });
  });
}
