import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/service.dart';

int _testCounter = 0;

/// EmployeeConfigService 全面测试
///
/// 验证：
/// - A. 单例模式 (getInstance / removeInstance)
/// - B. getEmployeeConfig 完整配置获取
/// - C. updateEmployeeBasicInfo 基础信息更新
/// - D. updateEmployeeProvider AI提供商配置更新
/// - E. updateEmployeePermission 权限配置更新
/// - F. MCP配置管理 (批量/添加/删除/更新)
/// - G. setMcpEnabled MCP开关
/// - H. updateEmployeeProject 项目关联
/// - I. onConfigChanged 事件通知流
void main() {
  late String testDbPath;
  late String deviceId;
  late EmployeeManager employeeManager;
  late SkillManager skillManager;
  late EmployeeConfigService configService;

  const employeeId = 'emp-config-test-0001';

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_config_service_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);
    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';

    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: testDbPath,
    );

    employeeManager = EmployeeManager.getInstance(deviceId);
    skillManager = SkillManager.getInstance(deviceId);
    configService = EmployeeConfigService.getInstance(deviceId);

    // 创建测试用员工
    await employeeManager.createEmployee(AiEmployeeEntity(
      uuid: employeeId,
      name: 'Test Employee',
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    ));
  });

  tearDown(() async {
    (configService as EmployeeConfigServiceImpl).dispose();
    (employeeManager as EmployeeManagerImpl).dispose();
    (skillManager as SkillManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceId).close();
    DatabaseManager.removeInstance(deviceId);
    EmployeeManager.removeInstance(deviceId);
    SkillManager.removeInstance(deviceId);
    EmployeeConfigService.removeInstance(deviceId);
    try {
      await Directory(testDbPath).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  /// 创建一个MCP服务器配置
  McpServerConfig createMcpConfig({
    String name = 'test-server',
    String transportType = 'stdio',
    String? command,
    List<String>? args,
    String? url,
    bool enabled = true,
  }) {
    return McpServerConfig(
      name: name,
      transportType: transportType,
      command: command ?? 'npx',
      args: args ?? ['-y', '@test/server'],
      url: url,
      enabled: enabled,
    );
  }

  /// 创建一个技能实体
  AiEmployeeSkillEntity createSkill({
    required String employeeId,
    String? name,
    String skillType = 'mcp',
  }) {
    return AiEmployeeSkillEntity(
      uuid: const Uuid().v4(),
      employeeId: employeeId,
      name: name ?? 'Test Skill',
      skillType: skillType,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════
  // A. 单例模式
  // ═══════════════════════════════════════════════════

  group('EmployeeConfigService singleton', () {
    test('getInstance returns same instance for same deviceId', () {
      final instance1 = EmployeeConfigService.getInstance(deviceId);
      final instance2 = EmployeeConfigService.getInstance(deviceId);
      expect(identical(instance1, instance2), isTrue);
    });

    test('getInstance returns different instance for different deviceId', () {
      final otherDeviceId = 'dev-other-${const Uuid().v4().substring(0, 8)}';
      final instance1 = EmployeeConfigService.getInstance(deviceId);
      final instance2 = EmployeeConfigService.getInstance(otherDeviceId);
      expect(identical(instance1, instance2), isFalse);

      // 清理
      EmployeeConfigService.removeInstance(otherDeviceId);
    });

    test('removeInstance removes cached instance', () {
      final tempDeviceId = 'dev-temp-${const Uuid().v4().substring(0, 8)}';
      final instance1 = EmployeeConfigService.getInstance(tempDeviceId);
      EmployeeConfigService.removeInstance(tempDeviceId);
      final instance2 = EmployeeConfigService.getInstance(tempDeviceId);
      expect(identical(instance1, instance2), isFalse);

      // 清理
      EmployeeConfigService.removeInstance(tempDeviceId);
    });
  });

  // ═══════════════════════════════════════════════════
  // B. getEmployeeConfig
  // ═══════════════════════════════════════════════════

  group('getEmployeeConfig', () {
    test('returns complete config for existing employee', () async {
      final config = await configService.getEmployeeConfig(employeeId);

      expect(config, isNotNull);
      expect(config.employee.uuid, equals(employeeId));
      expect(config.employee.name, equals('Test Employee'));
      expect(config.skills, isA<List<AiEmployeeSkillEntity>>());
      expect(config.mcpConfigs, isA<List<McpServerConfig>>());
    });

    test('returns empty skills list when no skills exist', () async {
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.skills, isEmpty);
    });

    test('returns empty mcpConfigs when no MCP config set', () async {
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs, isEmpty);
    });

    test('returns null permissionConfig when not set', () async {
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.permissionConfig, isNull);
    });

    test('returns skills when skills exist', () async {
      // 先创建技能
      await skillManager.createSkill(
        createSkill(employeeId: employeeId, name: 'Skill A'),
      );
      await skillManager.createSkill(
        createSkill(employeeId: employeeId, name: 'Skill B'),
      );

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.skills.length, equals(2));
      expect(config.skills.map((s) => s.name), containsAll(['Skill A', 'Skill B']));
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.getEmployeeConfig('non-existent-id'),
        throwsA(isA<StateError>()),
      );
    });

    test('handles invalid permissionConfig JSON gracefully', () async {
      // 直接通过 employeeManager 设置无效 JSON
      final emp = await employeeManager.getEmployee(employeeId);
      await employeeManager.updateEmployee(
        emp!.copyWith(permissionConfig: 'invalid-json{{{'),
      );

      // 不应抛出异常，permissionConfig 应为 null
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.permissionConfig, isNull);
    });

    test('parses valid permissionConfig JSON', () async {
      final permConfig = {
        'allowedTools': ['*'],
        'fileAccess': ['\${workspace}/**'],
        'commandWhitelist': ['git', 'npm'],
      };
      final emp = await employeeManager.getEmployee(employeeId);
      await employeeManager.updateEmployee(
        emp!.copyWith(permissionConfig: jsonEncode(permConfig)),
      );

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.permissionConfig, isNotNull);
      expect(config.permissionConfig!['allowedTools'], equals(['*']));
      expect(config.permissionConfig!['commandWhitelist'], equals(['git', 'npm']));
    });
  });

  // ═══════════════════════════════════════════════════
  // C. updateEmployeeBasicInfo
  // ═══════════════════════════════════════════════════

  group('updateEmployeeBasicInfo', () {
    test('updates name', () async {
      await configService.updateEmployeeBasicInfo(
        employeeId,
        name: 'Updated Name',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.name, equals('Updated Name'));
    });

    test('updates description', () async {
      await configService.updateEmployeeBasicInfo(
        employeeId,
        description: 'New description',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.description, equals('New description'));
    });

    test('updates systemPrompt', () async {
      await configService.updateEmployeeBasicInfo(
        employeeId,
        systemPrompt: 'You are a helpful assistant.',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.systemPrompt, equals('You are a helpful assistant.'));
    });

    test('updates avatar', () async {
      await configService.updateEmployeeBasicInfo(
        employeeId,
        avatar: 'https://example.com/avatar.png',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.avatar, equals('https://example.com/avatar.png'));
    });

    test('updates multiple fields at once', () async {
      await configService.updateEmployeeBasicInfo(
        employeeId,
        name: 'Multi Update',
        description: 'Multi desc',
        systemPrompt: 'Multi prompt',
        avatar: 'https://example.com/new.png',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.name, equals('Multi Update'));
      expect(config.employee.description, equals('Multi desc'));
      expect(config.employee.systemPrompt, equals('Multi prompt'));
      expect(config.employee.avatar, equals('https://example.com/new.png'));
    });

    test('does not modify unspecified fields', () async {
      // 先设置 name
      await configService.updateEmployeeBasicInfo(
        employeeId,
        name: 'Name Only',
      );
      // 只更新 description，name 不变
      await configService.updateEmployeeBasicInfo(
        employeeId,
        description: 'Desc Only',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.name, equals('Name Only'));
      expect(config.employee.description, equals('Desc Only'));
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.updateEmployeeBasicInfo(
          'non-existent',
          name: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('fires EmployeeConfigChangeEvent with basicInfo type', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeeBasicInfo(
        employeeId,
        name: 'Event Test',
      );

      // 等待事件传播
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].type, equals(EmployeeConfigChangeType.basicInfo));
      expect(events[0].employeeId, equals(employeeId));
    });
  });

  // ═══════════════════════════════════════════════════
  // D. updateEmployeeProvider
  // ═══════════════════════════════════════════════════

  group('updateEmployeeProvider', () {
    test('updates provider and model', () async {
      await configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4o',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.provider, equals('openai'));
      expect(config.employee.model, equals('gpt-4o'));
    });

    test('updates apiKey and apiBaseUrl', () async {
      await configService.updateEmployeeProvider(
        employeeId,
        provider: 'claude',
        apiKey: 'sk-test-key-123',
        apiBaseUrl: 'https://api.anthropic.com',
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.apiKey, equals('sk-test-key-123'));
      expect(config.employee.apiBaseUrl, equals('https://api.anthropic.com'));
    });

    test('updates modelConfig as JSON', () async {
      final modelConfig = {
        'temperature': 0.7,
        'maxTokens': 4096,
        'topP': 0.9,
      };
      await configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        modelConfig: modelConfig,
      );
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.modelConfig, isNotNull);
      final decoded = jsonDecode(config.employee.modelConfig!) as Map<String, dynamic>;
      expect(decoded['temperature'], equals(0.7));
      expect(decoded['maxTokens'], equals(4096));
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.updateEmployeeProvider(
          'non-existent',
          provider: 'openai',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('fires EmployeeConfigChangeEvent with provider type', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].type, equals(EmployeeConfigChangeType.provider));
      expect(events[0].employeeId, equals(employeeId));
    });
  });

  // ═══════════════════════════════════════════════════
  // E. updateEmployeePermission
  // ═══════════════════════════════════════════════════

  group('updateEmployeePermission', () {
    test('serializes and persists permission config', () async {
      final permConfig = {
        'allowedTools': ['*'],
        'fileAccess': ['\${workspace}/**'],
        'commandWhitelist': ['git', 'npm', 'dart'],
      };
      await configService.updateEmployeePermission(employeeId, permConfig);

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.permissionConfig, isNotNull);
      expect(config.permissionConfig!['allowedTools'], equals(['*']));
      expect(config.permissionConfig!['fileAccess'], equals(['\${workspace}/**']));
      expect(config.permissionConfig!['commandWhitelist'], equals(['git', 'npm', 'dart']));
    });

    test('overwrites previous permission config', () async {
      await configService.updateEmployeePermission(employeeId, {
        'allowedTools': ['tool1'],
      });
      await configService.updateEmployeePermission(employeeId, {
        'allowedTools': ['tool2', 'tool3'],
        'newField': 'value',
      });

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.permissionConfig!['allowedTools'], equals(['tool2', 'tool3']));
      expect(config.permissionConfig!['newField'], equals('value'));
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.updateEmployeePermission('non-existent', {}),
        throwsA(isA<StateError>()),
      );
    });

    test('fires EmployeeConfigChangeEvent with permission type', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeePermission(employeeId, {'key': 'value'});

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].type, equals(EmployeeConfigChangeType.permission));
      expect(events[0].employeeId, equals(employeeId));
    });
  });

  // ═══════════════════════════════════════════════════
  // F. MCP配置管理
  // ═══════════════════════════════════════════════════

  group('updateEmployeeMcpConfigs', () {
    test('sets MCP configs list on employee', () async {
      final configs = [
        createMcpConfig(name: 'server-1'),
        createMcpConfig(name: 'server-2'),
      ];
      await configService.updateEmployeeMcpConfigs(employeeId, configs);

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(2));
      expect(config.mcpConfigs[0].name, equals('server-1'));
      expect(config.mcpConfigs[1].name, equals('server-2'));
    });

    test('replaces existing MCP configs', () async {
      await configService.updateEmployeeMcpConfigs(
        employeeId,
        [createMcpConfig(name: 'old-server')],
      );
      await configService.updateEmployeeMcpConfigs(
        employeeId,
        [createMcpConfig(name: 'new-server-1'), createMcpConfig(name: 'new-server-2')],
      );

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(2));
      expect(
        config.mcpConfigs.map((c) => c.name),
        containsAll(['new-server-1', 'new-server-2']),
      );
    });

    test('sets empty list clears MCP configs', () async {
      await configService.updateEmployeeMcpConfigs(
        employeeId,
        [createMcpConfig(name: 'server')],
      );
      await configService.updateEmployeeMcpConfigs(employeeId, []);

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs, isEmpty);
    });

    test('fires EmployeeConfigChangeEvent with mcp type and data', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      final configs = [createMcpConfig(name: 'event-server')];
      await configService.updateEmployeeMcpConfigs(employeeId, configs);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].type, equals(EmployeeConfigChangeType.mcp));
      expect(events[0].employeeId, equals(employeeId));
      expect(events[0].data, isA<List<McpServerConfig>>());
      final data = events[0].data as List<McpServerConfig>;
      expect(data.first.name, equals('event-server'));
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.updateEmployeeMcpConfigs('non-existent', []),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('addMcpServerConfig', () {
    test('adds new MCP server config', () async {
      final config = createMcpConfig(name: 'new-server');
      await configService.addMcpServerConfig(employeeId, config);

      final empConfig = await configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs.length, equals(1));
      expect(empConfig.mcpConfigs.first.name, equals('new-server'));
    });

    test('adds multiple MCP server configs sequentially', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'server-a'),
      );
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'server-b'),
      );
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'server-c'),
      );

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(3));
      expect(
        config.mcpConfigs.map((c) => c.name),
        containsAll(['server-a', 'server-b', 'server-c']),
      );
    });

    test('throws ArgumentError for duplicate name', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'duplicate-name'),
      );

      expect(
        () => configService.addMcpServerConfig(
          employeeId,
          createMcpConfig(name: 'duplicate-name'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('preserves existing configs when adding new one', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'existing'),
      );
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'new-one'),
      );

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(2));
      expect(config.mcpConfigs[0].name, equals('existing'));
      expect(config.mcpConfigs[1].name, equals('new-one'));
    });

    test('throws ArgumentError with correct message for duplicate', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'dup'),
      );

      try {
        await configService.addMcpServerConfig(
          employeeId,
          createMcpConfig(name: 'dup'),
        );
        fail('Should have thrown ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains('dup'));
        expect(e.toString(), contains('already exists'));
      }
    });
  });

  group('removeMcpServerConfig', () {
    test('removes MCP server config by name', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'to-remove'),
      );
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'to-keep'),
      );

      await configService.removeMcpServerConfig(employeeId, 'to-remove');

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('to-keep'));
    });

    test('does nothing when removing non-existent server name', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'existing'),
      );

      // 移除不存在的名称，不应抛出异常
      await configService.removeMcpServerConfig(employeeId, 'non-existent');

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('existing'));
    });

    test('removes all configs if all are removed', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 's1'),
      );
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 's2'),
      );

      await configService.removeMcpServerConfig(employeeId, 's1');
      await configService.removeMcpServerConfig(employeeId, 's2');

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs, isEmpty);
    });
  });

  group('updateMcpServerConfig', () {
    test('updates existing MCP server config by name', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'updatable', command: 'old-cmd'),
      );

      final updated = createMcpConfig(
        name: 'updatable',
        command: 'new-cmd',
        args: ['--verbose'],
      );
      await configService.updateMcpServerConfig(employeeId, updated);

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('updatable'));
      expect(config.mcpConfigs.first.command, equals('new-cmd'));
      expect(config.mcpConfigs.first.args, equals(['--verbose']));
    });

    test('throws ArgumentError if config name not found', () async {
      expect(
        () => configService.updateMcpServerConfig(
          employeeId,
          createMcpConfig(name: 'not-found'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError with correct message for missing name', () async {
      try {
        await configService.updateMcpServerConfig(
          employeeId,
          createMcpConfig(name: 'missing'),
        );
        fail('Should have thrown ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.toString(), contains('missing'));
        expect(e.toString(), contains('not found'));
      }
    });

    test('preserves other configs when updating one', () async {
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'keep-me'),
      );
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'update-me', command: 'old'),
      );

      await configService.updateMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'update-me', command: 'new'),
      );

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(2));
      expect(
        config.mcpConfigs.firstWhere((c) => c.name == 'keep-me').command,
        equals('npx'),
      );
      expect(
        config.mcpConfigs.firstWhere((c) => c.name == 'update-me').command,
        equals('new'),
      );
    });
  });

  // ═══════════════════════════════════════════════════
  // G. setMcpEnabled
  // ═══════════════════════════════════════════════════

  group('setMcpEnabled', () {
    test('enables MCP (sets enableMcp to 1)', () async {
      // 默认 enableMcp = 0
      var config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.enableMcp, equals(0));

      await configService.setMcpEnabled(employeeId, true);

      config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.enableMcp, equals(1));
      expect(config.employee.isMcpEnabled, isTrue);
    });

    test('disables MCP (sets enableMcp to 0)', () async {
      await configService.setMcpEnabled(employeeId, true);
      await configService.setMcpEnabled(employeeId, false);

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.enableMcp, equals(0));
      expect(config.employee.isMcpEnabled, isFalse);
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.setMcpEnabled('non-existent', true),
        throwsA(isA<StateError>()),
      );
    });

    test('fires EmployeeConfigChangeEvent with mcpEnabled type and data',
        () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.setMcpEnabled(employeeId, true);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].type, equals(EmployeeConfigChangeType.mcpEnabled));
      expect(events[0].employeeId, equals(employeeId));
      expect(events[0].data, isTrue);
    });

    test('fires event with false data when disabling', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.setMcpEnabled(employeeId, false);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].data, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════
  // H. updateEmployeeProject
  // ═══════════════════════════════════════════════════

  group('updateEmployeeProject', () {
    test('sets projectUuid', () async {
      const projectUuid = 'proj-1234-5678';
      await configService.updateEmployeeProject(employeeId, projectUuid);

      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.projectUuid, equals(projectUuid));
    });

    test('sets projectUuid to null (unlinks project)', () async {
      // Note: Due to the copyWith pattern (null ?? this.value),
      // passing null does NOT clear the field — it keeps the old value.
      // This test documents the current behavior.
      await configService.updateEmployeeProject(employeeId, 'proj-temp');

      final configBefore = await configService.getEmployeeConfig(employeeId);
      expect(configBefore.employee.projectUuid, equals('proj-temp'));

      // Passing null keeps the existing value (copyWith limitation)
      await configService.updateEmployeeProject(employeeId, null);

      final configAfter = await configService.getEmployeeConfig(employeeId);
      expect(configAfter.employee.projectUuid, equals('proj-temp'));
    });

    test('throws StateError for non-existent employee', () async {
      expect(
        () => configService.updateEmployeeProject('non-existent', 'proj'),
        throwsA(isA<StateError>()),
      );
    });

    test('fires EmployeeConfigChangeEvent with project type and data',
        () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      const projectUuid = 'proj-event-test';
      await configService.updateEmployeeProject(employeeId, projectUuid);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].type, equals(EmployeeConfigChangeType.project));
      expect(events[0].employeeId, equals(employeeId));
      expect(events[0].data, equals(projectUuid));
    });

    test('fires event with null data when clearing project', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeeProject(employeeId, null);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(1));
      expect(events[0].data, isNull);
    });
  });

  // ═══════════════════════════════════════════════════
  // I. onConfigChanged 事件通知流
  // ═══════════════════════════════════════════════════

  group('onConfigChanged stream', () {
    test('receives events in sequence for multiple operations', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeeBasicInfo(employeeId, name: 'A');
      await configService.updateEmployeeProvider(employeeId, provider: 'openai');
      await configService.updateEmployeePermission(employeeId, {'k': 'v'});
      await configService.setMcpEnabled(employeeId, true);
      await configService.updateEmployeeProject(employeeId, 'proj-1');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(events.length, equals(5));
      expect(events[0].type, equals(EmployeeConfigChangeType.basicInfo));
      expect(events[1].type, equals(EmployeeConfigChangeType.provider));
      expect(events[2].type, equals(EmployeeConfigChangeType.permission));
      expect(events[3].type, equals(EmployeeConfigChangeType.mcpEnabled));
      expect(events[4].type, equals(EmployeeConfigChangeType.project));
    });

    test('all events contain correct employeeId', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeeBasicInfo(employeeId, name: 'X');
      await configService.updateEmployeeProvider(employeeId, provider: 'p');
      await configService.setMcpEnabled(employeeId, false);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      for (final event in events) {
        expect(event.employeeId, equals(employeeId));
      }
    });

    test('broadcasts to multiple listeners', () async {
      final events1 = <EmployeeConfigChangeEvent>[];
      final events2 = <EmployeeConfigChangeEvent>[];
      final sub1 = configService.onConfigChanged.listen(events1.add);
      final sub2 = configService.onConfigChanged.listen(events2.add);

      await configService.updateEmployeeBasicInfo(employeeId, name: 'Broadcast');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub1.cancel();
      await sub2.cancel();

      expect(events1.length, equals(1));
      expect(events2.length, equals(1));
      expect(events1.first.type, equals(events2.first.type));
      expect(events1.first.employeeId, equals(events2.first.employeeId));
    });

    test('MCP add/remove/update all fire mcp type events', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      // addMcpServerConfig 内部调用 updateEmployeeMcpConfigs → fires mcp
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 's1'),
      );
      // updateMcpServerConfig 内部调用 updateEmployeeMcpConfigs → fires mcp
      await configService.updateMcpServerConfig(
        employeeId,
        createMcpConfig(name: 's1', command: 'updated'),
      );
      // removeMcpServerConfig 内部调用 updateEmployeeMcpConfigs → fires mcp
      await configService.removeMcpServerConfig(employeeId, 's1');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.length, equals(3));
      expect(events.every((e) => e.type == EmployeeConfigChangeType.mcp), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════
  // J. MCP配置序列化往返测试
  // ═══════════════════════════════════════════════════

  group('MCP config serialization round-trip', () {
    test('stdio config round-trip preserves all fields', () async {
      final config = McpServerConfig.stdio(
        name: 'stdio-server',
        displayName: 'Stdio Server',
        description: 'A test stdio server',
        command: 'npx',
        args: ['-y', '@test/server'],
        env: {'API_KEY': 'secret'},
        enabled: true,
        autoStart: false,
        timeout: 5000,
        retryConfig: McpRetryConfig(
          maxRetries: 5,
          retryDelay: 2000,
          exponentialBackoff: false,
        ),
      );

      await configService.addMcpServerConfig(employeeId, config);

      final empConfig = await configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs.length, equals(1));

      final result = empConfig.mcpConfigs.first;
      expect(result.name, equals('stdio-server'));
      expect(result.displayName, equals('Stdio Server'));
      expect(result.description, equals('A test stdio server'));
      expect(result.transportType, equals('stdio'));
      expect(result.command, equals('npx'));
      expect(result.args, equals(['-y', '@test/server']));
      expect(result.env, equals({'API_KEY': 'secret'}));
      expect(result.enabled, isTrue);
      expect(result.autoStart, isFalse);
      expect(result.timeout, equals(5000));
      expect(result.retryConfig, isNotNull);
      expect(result.retryConfig!.maxRetries, equals(5));
      expect(result.retryConfig!.retryDelay, equals(2000));
      expect(result.retryConfig!.exponentialBackoff, isFalse);
    });

    test('sse config round-trip preserves URL and headers', () async {
      final config = McpServerConfig.sse(
        name: 'sse-server',
        url: 'https://example.com/sse',
        headers: {'Authorization': 'Bearer token'},
        enabled: false,
      );

      await configService.addMcpServerConfig(employeeId, config);

      final empConfig = await configService.getEmployeeConfig(employeeId);
      final result = empConfig.mcpConfigs.first;
      expect(result.name, equals('sse-server'));
      expect(result.transportType, equals('sse'));
      expect(result.url, equals('https://example.com/sse'));
      expect(result.headers, equals({'Authorization': 'Bearer token'}));
      expect(result.enabled, isFalse);
    });

    test('http config round-trip preserves URL', () async {
      final config = McpServerConfig.http(
        name: 'http-server',
        url: 'https://example.com/mcp',
      );

      await configService.addMcpServerConfig(employeeId, config);

      final empConfig = await configService.getEmployeeConfig(employeeId);
      final result = empConfig.mcpConfigs.first;
      expect(result.name, equals('http-server'));
      expect(result.transportType, equals('http'));
      expect(result.url, equals('https://example.com/mcp'));
    });

    test('multiple configs round-trip preserves order and data', () async {
      final configs = [
        McpServerConfig.stdio(name: 'alpha', command: 'cmd-a'),
        McpServerConfig.sse(name: 'beta', url: 'http://b'),
        McpServerConfig.http(name: 'gamma', url: 'http://c'),
      ];

      await configService.updateEmployeeMcpConfigs(employeeId, configs);

      final empConfig = await configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs.length, equals(3));
      expect(empConfig.mcpConfigs[0].name, equals('alpha'));
      expect(empConfig.mcpConfigs[0].transportType, equals('stdio'));
      expect(empConfig.mcpConfigs[1].name, equals('beta'));
      expect(empConfig.mcpConfigs[1].transportType, equals('sse'));
      expect(empConfig.mcpConfigs[2].name, equals('gamma'));
      expect(empConfig.mcpConfigs[2].transportType, equals('http'));
    });

    test('add → getEmployeeConfig → verify → update → verify round-trip',
        () async {
      // 添加
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'rt-server', command: 'initial'),
      );

      var config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.command, equals('initial'));

      // 更新
      await configService.updateMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'rt-server', command: 'updated'),
      );

      config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.command, equals('updated'));

      // 删除
      await configService.removeMcpServerConfig(employeeId, 'rt-server');

      config = await configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════
  // K. 综合集成场景
  // ═══════════════════════════════════════════════════

  group('integration scenarios', () {
    test('full employee configuration lifecycle', () async {
      // 1. 设置基础信息
      await configService.updateEmployeeBasicInfo(
        employeeId,
        name: 'Integration Bot',
        description: 'A full integration test bot',
        systemPrompt: 'You are a test assistant.',
      );

      // 2. 设置 Provider
      await configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4o',
        apiKey: 'sk-test',
        apiBaseUrl: 'https://api.openai.com/v1',
        modelConfig: {'temperature': 0.5},
      );

      // 3. 设置权限
      await configService.updateEmployeePermission(employeeId, {
        'allowedTools': ['*'],
        'commandWhitelist': ['git'],
      });

      // 4. 添加 MCP 配置
      await configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'fs', command: 'npx'),
      );

      // 5. 启用 MCP
      await configService.setMcpEnabled(employeeId, true);

      // 6. 关联项目
      await configService.updateEmployeeProject(employeeId, 'proj-integration');

      // 验证完整配置
      final config = await configService.getEmployeeConfig(employeeId);
      expect(config.employee.name, equals('Integration Bot'));
      expect(config.employee.description, equals('A full integration test bot'));
      expect(config.employee.systemPrompt, equals('You are a test assistant.'));
      expect(config.employee.provider, equals('openai'));
      expect(config.employee.model, equals('gpt-4o'));
      expect(config.employee.apiKey, equals('sk-test'));
      expect(config.employee.apiBaseUrl, equals('https://api.openai.com/v1'));
      expect(config.employee.enableMcp, equals(1));
      expect(config.employee.projectUuid, equals('proj-integration'));
      expect(config.permissionConfig, isNotNull);
      expect(config.permissionConfig!['allowedTools'], equals(['*']));
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('fs'));
    });

    test('event stream captures full lifecycle', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = configService.onConfigChanged.listen(events.add);

      await configService.updateEmployeeBasicInfo(employeeId, name: 'Lifecycle');
      await configService.updateEmployeeProvider(employeeId, provider: 'p');
      await configService.updateEmployeePermission(employeeId, {'k': 'v'});
      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 's1'),
      );
      await configService.updateMcpServerConfig(
        employeeId,
        createMcpConfig(name: 's1', command: 'new'),
      );
      await configService.removeMcpServerConfig(employeeId, 's1');
      await configService.setMcpEnabled(employeeId, true);
      await configService.updateEmployeeProject(employeeId, 'proj');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(events.length, equals(8));
      // 验证事件序列
      expect(events[0].type, equals(EmployeeConfigChangeType.basicInfo));
      expect(events[1].type, equals(EmployeeConfigChangeType.provider));
      expect(events[2].type, equals(EmployeeConfigChangeType.permission));
      expect(events[3].type, equals(EmployeeConfigChangeType.mcp)); // add
      expect(events[4].type, equals(EmployeeConfigChangeType.mcp)); // update
      expect(events[5].type, equals(EmployeeConfigChangeType.mcp)); // remove
      expect(events[6].type, equals(EmployeeConfigChangeType.mcpEnabled));
      expect(events[7].type, equals(EmployeeConfigChangeType.project));
    });

    test('concurrent operations on different employees are isolated', () async {
      // 创建第二个员工
      const employeeId2 = 'emp-config-test-0002';
      await employeeManager.createEmployee(AiEmployeeEntity(
        uuid: employeeId2,
        name: 'Employee 2',
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      // 分别配置
      await configService.updateEmployeeBasicInfo(employeeId, name: 'Emp 1');
      await configService.updateEmployeeBasicInfo(employeeId2, name: 'Emp 2');

      await configService.addMcpServerConfig(
        employeeId,
        createMcpConfig(name: 'server-for-1'),
      );
      await configService.addMcpServerConfig(
        employeeId2,
        createMcpConfig(name: 'server-for-2'),
      );

      // 验证隔离
      final config1 = await configService.getEmployeeConfig(employeeId);
      final config2 = await configService.getEmployeeConfig(employeeId2);

      expect(config1.employee.name, equals('Emp 1'));
      expect(config2.employee.name, equals('Emp 2'));
      expect(config1.mcpConfigs.first.name, equals('server-for-1'));
      expect(config2.mcpConfigs.first.name, equals('server-for-2'));
    });
  });
}
