import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/skill_manager.dart';

int _testCounter = 0;

void main() {
  late String testDbPath;
  late String deviceId;
  late SkillManager manager;

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_skill_manager_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);
    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';
    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: testDbPath,
    );
    manager = SkillManager.getInstance(deviceId);
  });

  tearDown(() async {
    (manager as SkillManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceId).close();
    DatabaseManager.removeInstance(deviceId);
    SkillManager.removeInstance(deviceId);
    try {
      await Directory(testDbPath).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  AiEmployeeSkillEntity createSkillEntity({
    String? uuid,
    String? employeeId,
    String? name,
    String? description,
    String skillType = 'mcp',
    String? config,
    int enabled = 1,
    int sortOrder = 0,
  }) {
    return AiEmployeeSkillEntity(
      uuid: uuid ?? const Uuid().v4(),
      employeeId: employeeId ?? 'emp-${const Uuid().v4().substring(0, 8)}',
      name: name ?? 'Test Skill',
      description: description,
      skillType: skillType,
      config: config,
      enabled: enabled,
      sortOrder: sortOrder,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════
  // 1. createSkill
  // ═══════════════════════════════════════════════════

  group('createSkill', () {
    test('sets createTime/updateTime and fires created event with skill data',
        () async {
      final entity = createSkillEntity(name: 'My Skill');
      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      final created = await manager.createSkill(entity);

      // createTime/updateTime should be set by manager (overriding input)
      expect(created.createTime, isNotNull);
      expect(created.updateTime, isNotNull);
      expect(created.name, 'My Skill');
      expect(created.uuid, entity.uuid);

      // Allow stream to deliver
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events[0].type, SkillChangeType.created);
      expect(events[0].skillUuid, entity.uuid);
      expect(events[0].skill, isNotNull);
      expect(events[0].skill!.name, 'My Skill');
    });

    test('saves with deviceId from manager', () async {
      final entity = createSkillEntity();
      await manager.createSkill(entity);

      // Retrieve directly and verify deviceId matches
      final fetched = await manager.getSkill(entity.uuid);
      expect(fetched, isNotNull);
      expect(fetched!.deviceId, deviceId);
    });
  });

  // ═══════════════════════════════════════════════════
  // 2. updateSkill
  // ═══════════════════════════════════════════════════

  group('updateSkill', () {
    test('sets updateTime and fires updated event', () async {
      final entity = createSkillEntity(name: 'Original');
      await manager.createSkill(entity);

      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      // Wait a bit so updateTime differs
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final updated = entity.copyWith(name: 'Updated');
      await manager.updateSkill(updated);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events[0].type, SkillChangeType.updated);
      expect(events[0].skillUuid, entity.uuid);
      expect(events[0].skill!.name, 'Updated');

      // Verify the persisted data
      final fetched = await manager.getSkill(entity.uuid);
      expect(fetched!.name, 'Updated');
    });
  });

  // ═══════════════════════════════════════════════════
  // 3. deleteSkill
  // ═══════════════════════════════════════════════════

  group('deleteSkill', () {
    test('soft-deletes and fires deleted event with skill data', () async {
      final entity = createSkillEntity(name: 'To Delete');
      await manager.createSkill(entity);

      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      await manager.deleteSkill(entity.uuid);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events[0].type, SkillChangeType.deleted);
      expect(events[0].skillUuid, entity.uuid);
      expect(events[0].skill, isNotNull);
      expect(events[0].skill!.name, 'To Delete');

      // Soft delete means getSkill returns null (deleted = 0 filter)
      final fetched = await manager.getSkill(entity.uuid);
      expect(fetched, isNull);
    });

    test('on non-existent skill does not fire event', () async {
      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      await manager.deleteSkill('non-existent-uuid');

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════
  // 4. setSkillEnabled
  // ═══════════════════════════════════════════════════

  group('setSkillEnabled', () {
    test('toggles enabled to 0 (disabled)', () async {
      final entity = createSkillEntity(enabled: 1);
      await manager.createSkill(entity);

      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      await manager.setSkillEnabled(entity.uuid, false);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events[0].type, SkillChangeType.updated);
      expect(events[0].skill!.enabled, 0);

      final fetched = await manager.getSkill(entity.uuid);
      expect(fetched!.enabled, 0);
    });

    test('toggles enabled to 1 (enabled)', () async {
      final entity = createSkillEntity(enabled: 0);
      await manager.createSkill(entity);

      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      await manager.setSkillEnabled(entity.uuid, true);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events[0].type, SkillChangeType.updated);
      expect(events[0].skill!.enabled, 1);

      final fetched = await manager.getSkill(entity.uuid);
      expect(fetched!.enabled, 1);
    });

    test('on non-existent skill does nothing', () async {
      final events = <SkillChangeEvent>[];
      manager.onSkillChanged.listen(events.add);

      await manager.setSkillEnabled('non-existent-uuid', true);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════
  // 5. getSkills
  // ═══════════════════════════════════════════════════

  group('getSkills', () {
    test('returns only skills for the employee', () async {
      const emp1 = 'emp-001';
      const emp2 = 'emp-002';

      await manager.createSkill(
          createSkillEntity(employeeId: emp1, name: 'Skill A'));
      await manager.createSkill(
          createSkillEntity(employeeId: emp1, name: 'Skill B'));
      await manager.createSkill(
          createSkillEntity(employeeId: emp2, name: 'Skill C'));

      final emp1Skills = await manager.getSkills(emp1);
      expect(emp1Skills, hasLength(2));
      expect(emp1Skills.every((s) => s.employeeId == emp1), isTrue);

      final emp2Skills = await manager.getSkills(emp2);
      expect(emp2Skills, hasLength(1));
      expect(emp2Skills.first.name, 'Skill C');
    });

    test('returns empty list for unknown employee', () async {
      final skills = await manager.getSkills('unknown-emp');
      expect(skills, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════
  // 6. getSkill
  // ═══════════════════════════════════════════════════

  group('getSkill', () {
    test('returns null for non-existent uuid', () async {
      final skill = await manager.getSkill('does-not-exist');
      expect(skill, isNull);
    });

    test('returns created skill by uuid', () async {
      final entity = createSkillEntity(name: 'Fetch Me');
      await manager.createSkill(entity);

      final fetched = await manager.getSkill(entity.uuid);
      expect(fetched, isNotNull);
      expect(fetched!.uuid, entity.uuid);
      expect(fetched.name, 'Fetch Me');
    });
  });

  // ═══════════════════════════════════════════════════
  // 7. Device isolation
  // ═══════════════════════════════════════════════════

  test('Skills are isolated by deviceId', () async {
    const empId = 'emp-shared';

    // Create skill with first device
    final entity = createSkillEntity(employeeId: empId, name: 'Device1 Skill');
    await manager.createSkill(entity);

    // Verify it shows up for device1
    final skills1 = await manager.getSkills(empId);
    expect(skills1, hasLength(1));

    // Create a second device manager
    final device2Id = 'dev-${const Uuid().v4().substring(0, 8)}';
    final testDbPath2 =
        '${Directory.systemTemp.path}/wenzagent_skill_manager_test_${_testCounter}_dev2';
    await Directory(testDbPath2).create(recursive: true);
    await DatabaseManager.getInstance(device2Id).initialize(
      storagePath: testDbPath2,
    );
    final manager2 = SkillManager.getInstance(device2Id);

    try {
      // Device2 should see no skills for the same employee
      final skills2 = await manager2.getSkills(empId);
      expect(skills2, isEmpty);

      // Device2 can create its own skill for the same employee
      await manager2.createSkill(
          createSkillEntity(employeeId: empId, name: 'Device2 Skill'));
      final skills2After = await manager2.getSkills(empId);
      expect(skills2After, hasLength(1));
      expect(skills2After.first.name, 'Device2 Skill');

      // Device1 still sees only its own skill
      final skills1After = await manager.getSkills(empId);
      expect(skills1After, hasLength(1));
      expect(skills1After.first.name, 'Device1 Skill');
    } finally {
      (manager2 as SkillManagerImpl).dispose();
      await DatabaseManager.getInstance(device2Id).close();
      DatabaseManager.removeInstance(device2Id);
      SkillManager.removeInstance(device2Id);
      try {
        await Directory(testDbPath2).delete(recursive: true);
      } catch (_) {}
    }
  });

  // ═══════════════════════════════════════════════════
  // 8. Event stream sequence
  // ═══════════════════════════════════════════════════

  test('Event stream receives correct sequence of events', () async {
    final events = <SkillChangeEvent>[];
    manager.onSkillChanged.listen(events.add);

    const empId = 'emp-events';

    // Create
    final entity1 =
        createSkillEntity(employeeId: empId, name: 'Skill 1');
    await manager.createSkill(entity1);

    // Update
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await manager.updateSkill(entity1.copyWith(name: 'Skill 1 Updated'));

    // Disable
    await manager.setSkillEnabled(entity1.uuid, false);

    // Enable
    await manager.setSkillEnabled(entity1.uuid, true);

    // Create second
    final entity2 =
        createSkillEntity(employeeId: empId, name: 'Skill 2');
    await manager.createSkill(entity2);

    // Delete first
    await manager.deleteSkill(entity1.uuid);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(events, hasLength(6));
    expect(events[0].type, SkillChangeType.created);
    expect(events[0].skillUuid, entity1.uuid);
    expect(events[0].skill!.name, 'Skill 1');

    expect(events[1].type, SkillChangeType.updated);
    expect(events[1].skill!.name, 'Skill 1 Updated');

    expect(events[2].type, SkillChangeType.updated);
    expect(events[2].skill!.enabled, 0);

    expect(events[3].type, SkillChangeType.updated);
    expect(events[3].skill!.enabled, 1);

    expect(events[4].type, SkillChangeType.created);
    expect(events[4].skillUuid, entity2.uuid);
    expect(events[4].skill!.name, 'Skill 2');

    expect(events[5].type, SkillChangeType.deleted);
    expect(events[5].skillUuid, entity1.uuid);
    expect(events[5].skill!.name, 'Skill 1 Updated');
  });

  // ═══════════════════════════════════════════════════
  // 9. createSkillEntity helper
  // ═══════════════════════════════════════════════════

  test('createSkillEntity helper creates entity with UUID and timestamps', () {
    final impl = manager as SkillManagerImpl;

    const empId = 'emp-helper';
    const skillName = 'Helper Skill';
    const description = 'A test skill';
    const config = '{"server": "localhost"}';

    final entity = impl.createSkillEntity(
      employeeId: empId,
      name: skillName,
      description: description,
      skillType: 'mcp',
      config: config,
    );

    expect(entity.uuid, isNotEmpty);
    expect(entity.employeeId, empId);
    expect(entity.name, skillName);
    expect(entity.description, description);
    expect(entity.skillType, 'mcp');
    expect(entity.config, config);
    expect(entity.enabled, 1);
    expect(entity.sortOrder, 0);
    expect(entity.createTime, isNotNull);
    expect(entity.updateTime, isNotNull);

    // UUID should be a valid v4 format
    expect(entity.uuid, hasLength(36));
    expect(entity.uuid.contains('-'), isTrue);
  });

  // ═══════════════════════════════════════════════════
  // 10. Singleton behavior
  // ═══════════════════════════════════════════════════

  test('getInstance returns same singleton for same deviceId', () {
    final instance1 = SkillManager.getInstance(deviceId);
    final instance2 = SkillManager.getInstance(deviceId);
    expect(identical(instance1, instance2), isTrue);
  });

  test('removeInstance removes the singleton', () {
    final instance1 = SkillManager.getInstance(deviceId);
    SkillManager.removeInstance(deviceId);
    final instance2 = SkillManager.getInstance(deviceId);
    expect(identical(instance1, instance2), isFalse);
    // Clean up the new instance
    (instance2 as SkillManagerImpl).dispose();
  });
}
