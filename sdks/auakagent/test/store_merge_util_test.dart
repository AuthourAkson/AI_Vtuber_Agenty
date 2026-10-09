import 'package:test/test.dart';
import 'package:auakagent/src/persistence/store_merge_util.dart';
import 'package:auakagent/src/persistence/entities/session_entity.dart';
import 'package:auakagent/src/persistence/entities/employee_entity.dart';

void main() {
  group('StoreMergeUtil.mergeDeleteState', () {
    test('both null deleteTime returns not deleted', () {
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: null,
        localDeleted: 0,
        remoteDeleteTime: null,
        remoteDeleted: 0,
      );
      expect(result.mergedDeleted, 0);
      expect(result.mergedDeleteTime, isNull);
    });

    test('local null, remote has deleteTime adopts remote', () {
      final dt = DateTime(2024, 1, 1);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: null,
        localDeleted: 0,
        remoteDeleteTime: dt,
        remoteDeleted: 1,
      );
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, dt);
    });

    test('remote null, local has deleteTime adopts local', () {
      final dt = DateTime(2024, 1, 1);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: dt,
        localDeleted: 1,
        remoteDeleteTime: null,
        remoteDeleted: 0,
      );
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, dt);
    });

    test('both have deleteTime, local is newer', () {
      final localDt = DateTime(2024, 1, 2);
      final remoteDt = DateTime(2024, 1, 1);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: localDt,
        localDeleted: 1,
        remoteDeleteTime: remoteDt,
        remoteDeleted: 1,
      );
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, localDt);
    });

    test('both have deleteTime, remote is newer', () {
      final localDt = DateTime(2024, 1, 1);
      final remoteDt = DateTime(2024, 1, 2);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: localDt,
        localDeleted: 1,
        remoteDeleteTime: remoteDt,
        remoteDeleted: 1,
      );
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, remoteDt);
    });

    test('remote resurrection when updateTime is newer', () {
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: DateTime(2024, 1, 1),
        localDeleted: 1,
        remoteDeleteTime: null,
        remoteDeleted: 0,
        localUpdateTime: DateTime(2024, 1, 1),
        remoteUpdateTime: DateTime(2024, 1, 2), // 远程更新
      );
      expect(result.mergedDeleted, 0);
      expect(result.mergedDeleteTime, isNull);
    });

    test('keeps local delete when remote updateTime is older', () {
      final localDt = DateTime(2024, 1, 2);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: localDt,
        localDeleted: 1,
        remoteDeleteTime: null,
        remoteDeleted: 0,
        localUpdateTime: DateTime(2024, 1, 2),
        remoteUpdateTime: DateTime(2024, 1, 1), // 远程更旧
      );
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, localDt);
    });

    test('backward compatible without updateTime', () {
      // 不传 updateTime 时走原有逻辑：单侧有 deleteTime → 采用有 deleteTime 的一方
      final localDt = DateTime(2024, 1, 1);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: localDt,
        localDeleted: 1,
        remoteDeleteTime: null,
        remoteDeleted: 0,
      );
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, localDt);
    });

    test('local resurrection when localUpdateTime is newer', () {
      final remoteDt = DateTime(2024, 1, 1);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: null,
        localDeleted: 0,
        remoteDeleteTime: remoteDt,
        remoteDeleted: 1,
        localUpdateTime: DateTime(2024, 1, 2),
        remoteUpdateTime: DateTime(2024, 1, 1),
      );
      expect(result.mergedDeleted, 0);
      expect(result.mergedDeleteTime, isNull);
    });

    test('remote resurrection ignored when updateTimes are equal', () {
      final localDt = DateTime(2024, 1, 1);
      final ts = DateTime(2024, 1, 2);
      final result = StoreMergeUtil.mergeDeleteState(
        localDeleteTime: localDt,
        localDeleted: 1,
        remoteDeleteTime: null,
        remoteDeleted: 0,
        localUpdateTime: ts,
        remoteUpdateTime: ts, // 相同时间不满足 isAfter
      );
      // 不满足复活条件，走原有逻辑：单侧有 deleteTime → 采用有 deleteTime 的一方
      expect(result.mergedDeleted, 1);
      expect(result.mergedDeleteTime, localDt);
    });
  });

  group('AiEmployeeSessionEntity.copyWith sentinel', () {
    test('not passing deleteTime keeps original value', () {
      final dt = DateTime(2024, 1, 1);
      final session = AiEmployeeSessionEntity(
        employeeId: 'test',
        deleted: 1,
        deleteTime: dt,
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      // 不传 deleteTime → 保留原值
      final kept = session.copyWith(deleted: 0);
      expect(kept.deleteTime, isNotNull);
      expect(kept.deleteTime, dt);
      expect(kept.deleted, 0);
    });

    test('explicitly passing null clears deleteTime', () {
      final session = AiEmployeeSessionEntity(
        employeeId: 'test',
        deleted: 1,
        deleteTime: DateTime(2024, 1, 1),
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      // 显式传 null → 清除 deleteTime
      final cleared = session.copyWith(deleted: 0, deleteTime: null);
      expect(cleared.deleteTime, isNull);
      expect(cleared.deleted, 0);
    });

    test('passing new deleteTime updates value', () {
      final oldDt = DateTime(2024, 1, 1);
      final newDt = DateTime(2024, 1, 2);
      final session = AiEmployeeSessionEntity(
        employeeId: 'test',
        deleted: 0,
        deleteTime: oldDt,
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      final updated = session.copyWith(deleteTime: newDt);
      expect(updated.deleteTime, newDt);
    });
  });

  group('AiEmployeeEntity.copyWith sentinel', () {
    test('not passing deletedTime keeps original value', () {
      final dt = DateTime(2024, 1, 1);
      final employee = AiEmployeeEntity(
        uuid: 'test-uuid',
        name: 'Test',
        deleted: 1,
        deletedTime: dt,
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      // 不传 deletedTime → 保留原值
      final kept = employee.copyWith(deleted: 0);
      expect(kept.deletedTime, isNotNull);
      expect(kept.deletedTime, dt);
      expect(kept.deleted, 0);
    });

    test('explicitly passing null clears deletedTime', () {
      final employee = AiEmployeeEntity(
        uuid: 'test-uuid',
        name: 'Test',
        deleted: 1,
        deletedTime: DateTime(2024, 1, 1),
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      // 显式传 null → 清除 deletedTime
      final cleared = employee.copyWith(deleted: 0, deletedTime: null);
      expect(cleared.deletedTime, isNull);
      expect(cleared.deleted, 0);
    });

    test('passing new deletedTime updates value', () {
      final oldDt = DateTime(2024, 1, 1);
      final newDt = DateTime(2024, 1, 2);
      final employee = AiEmployeeEntity(
        uuid: 'test-uuid',
        name: 'Test',
        deleted: 0,
        deletedTime: oldDt,
        createTime: DateTime(2024, 1, 1),
        updateTime: DateTime(2024, 1, 1),
      );

      final updated = employee.copyWith(deletedTime: newDt);
      expect(updated.deletedTime, newDt);
    });
  });
}
