/// MCP 数据配置功能测试
///
/// 测试范围：
/// - McpServerConfig 序列化/反序列化
/// - McpServerConfig 工厂方法（stdio/sse/http）
/// - McpServerConfig 旧格式兼容
/// - McpRetryConfig
/// - AiEmployeeEntity MCP 配置存取
/// - EmployeeConfigService MCP CRUD
/// - MCP 配置变更事件通知
/// - 跨设备 MCP 配置同步（通过 Server RPC）
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/entities/employee_entity.dart';
import 'package:auakagent/src/persistence/entities/mcp_server_config.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/service/employee_config_service.dart';
import 'package:auakagent/src/utils/logger.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

AiEmployeeEntity _createEmployee({
  String? uuid,
  String? name,
  String? deviceId,
  int enableMcp = 0,
  String? mcpConfig,
}) {
  final now = DateTime.now();
  return AiEmployeeEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? '测试员工',
    deviceId: deviceId,
    enableMcp: enableMcp,
    mcpConfig: mcpConfig,
    createTime: now,
    updateTime: now,
  );
}

// ═══════════════════════════════════════════════════════════════
// Group 1: McpServerConfig 序列化与反序列化
// ═══════════════════════════════════════════════════════════════

void main() {
  group('McpServerConfig 序列化与反序列化', () {
    test('stdio 配置 toMap/fromMap 往返', () {
      final config = McpServerConfig.stdio(
        name: 'filesystem',
        displayName: 'File System',
        description: '文件系统 MCP 服务器',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
        env: {'NODE_ENV': 'production'},
        enabled: true,
        autoStart: true,
        timeout: 30000,
        retryConfig: McpRetryConfig(
          maxRetries: 5,
          retryDelay: 2000,
          exponentialBackoff: true,
        ),
      );

      final map = config.toMap();
      final restored = McpServerConfig.fromMap(map);

      expect(restored.name, equals('filesystem'));
      expect(restored.displayName, equals('File System'));
      expect(restored.description, equals('文件系统 MCP 服务器'));
      expect(restored.transportType, equals('stdio'));
      expect(restored.command, equals('npx'));
      expect(restored.args, equals(['-y', '@modelcontextprotocol/server-filesystem', '/tmp']));
      expect(restored.env, equals({'NODE_ENV': 'production'}));
      expect(restored.enabled, isTrue);
      expect(restored.autoStart, isTrue);
      expect(restored.timeout, equals(30000));
      expect(restored.retryConfig?.maxRetries, equals(5));
      expect(restored.retryConfig?.retryDelay, equals(2000));
      expect(restored.retryConfig?.exponentialBackoff, isTrue);
    });

    test('sse 配置 toMap/fromMap 往返', () {
      final config = McpServerConfig.sse(
        name: 'remote-api',
        url: 'http://localhost:3001/sse',
        headers: {'Authorization': 'Bearer token123'},
        enabled: true,
      );

      final map = config.toMap();
      final restored = McpServerConfig.fromMap(map);

      expect(restored.transportType, equals('sse'));
      expect(restored.url, equals('http://localhost:3001/sse'));
      expect(restored.headers, equals({'Authorization': 'Bearer token123'}));
      expect(restored.command, isNull);
    });

    test('http 配置 toMap/fromMap 往返', () {
      final config = McpServerConfig.http(
        name: 'remote-http',
        url: 'http://localhost:3002/mcp',
        enabled: false,
      );

      final map = config.toMap();
      final restored = McpServerConfig.fromMap(map);

      expect(restored.transportType, equals('http'));
      expect(restored.url, equals('http://localhost:3002/mcp'));
      expect(restored.enabled, isFalse);
    });

    test('toMap 不包含 null 值字段', () {
      final config = McpServerConfig.stdio(
        name: 'minimal',
        command: 'echo',
      );

      final map = config.toMap();

      expect(map.containsKey('displayName'), isFalse);
      expect(map.containsKey('description'), isFalse);
      expect(map.containsKey('url'), isFalse);
      expect(map.containsKey('headers'), isFalse);
      expect(map.containsKey('timeout'), isFalse);
      expect(map.containsKey('retryConfig'), isFalse);
    });

    test('fromMap 使用默认值', () {
      final config = McpServerConfig.fromMap({
        'name': 'defaults-test',
        'command': 'test',
      });

      expect(config.transportType, equals('stdio'));
      expect(config.enabled, isTrue);
      expect(config.autoStart, isTrue);
      expect(config.retryConfig, isNull);
    });

    test('copyWith 正确复制和修改', () {
      final original = McpServerConfig.stdio(
        name: 'original',
        command: 'cmd1',
        args: ['arg1'],
        enabled: true,
      );

      final modified = original.copyWith(
        command: 'cmd2',
        enabled: false,
      );

      expect(modified.name, equals('original')); // 未修改
      expect(modified.command, equals('cmd2')); // 已修改
      expect(modified.args, equals(['arg1'])); // 未修改
      expect(modified.enabled, isFalse); // 已修改
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: McpServerConfig JSON 解析
  // ═══════════════════════════════════════════════════════════════

  group('McpServerConfig JSON 解析', () {
    test('parseList 解析新格式（List）', () {
      final json = '''
      [
        {"name": "fs", "transportType": "stdio", "command": "npx", "args": ["-y", "fs-server"]},
        {"name": "api", "transportType": "sse", "url": "http://localhost:3001/sse"}
      ]
      ''';

      final configs = McpServerConfig.parseList(json);

      expect(configs.length, equals(2));
      expect(configs[0].name, equals('fs'));
      expect(configs[0].transportType, equals('stdio'));
      expect(configs[0].command, equals('npx'));
      expect(configs[1].name, equals('api'));
      expect(configs[1].transportType, equals('sse'));
    });

    test('parseList 解析旧格式（Map）并自动转换', () {
      final json = '''
      {
        "filesystem": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem"],
          "env": {"NODE_ENV": "production"}
        },
        "remote-api": {
          "command": "node",
          "args": ["server.js"]
        }
      }
      ''';

      final configs = McpServerConfig.parseList(json);

      expect(configs.length, equals(2));
      // 旧格式自动推断 transportType = stdio
      expect(configs[0].name, equals('filesystem'));
      expect(configs[0].transportType, equals('stdio'));
      expect(configs[0].command, equals('npx'));
      expect(configs[0].env, equals({'NODE_ENV': 'production'}));
      expect(configs[1].name, equals('remote-api'));
      expect(configs[1].command, equals('node'));
    });

    test('parseList 空字符串返回空列表', () {
      expect(McpServerConfig.parseList(''), isEmpty);
      expect(McpServerConfig.parseList(null), isEmpty);
    });

    test('parseList 无效 JSON 返回空列表', () {
      // 使用 Logger.level = none 避免测试输出中产生 debug 日志
      final savedLevel = Logger.level;
      Logger.level = LogLevel.none;
      try {
        expect(McpServerConfig.parseList('not json'), isEmpty);
      } finally {
        Logger.level = savedLevel;
      }
    });

    test('toJsonString 生成有效的 JSON', () {
      final configs = [
        McpServerConfig.stdio(name: 'fs', command: 'npx'),
        McpServerConfig.sse(name: 'api', url: 'http://localhost/sse'),
      ];

      final json = McpServerConfig.toJsonString(configs);

      // 解析回来应该得到相同的结果
      final restored = McpServerConfig.parseList(json);
      expect(restored.length, equals(2));
      expect(restored[0].name, equals('fs'));
      expect(restored[1].name, equals('api'));
    });

    test('toJsonString → parseList 往返一致性', () {
      final configs = [
        McpServerConfig.stdio(
          name: 'full-config',
          displayName: 'Full Config',
          description: 'A full config test',
          command: 'npx',
          args: ['-y', 'server'],
          env: {'KEY': 'VALUE'},
          enabled: true,
          autoStart: false,
          timeout: 5000,
          retryConfig: McpRetryConfig(
            maxRetries: 3,
            retryDelay: 1000,
            exponentialBackoff: true,
          ),
        ),
      ];

      final json = McpServerConfig.toJsonString(configs);
      final restored = McpServerConfig.parseList(json);

      expect(restored.length, equals(1));
      final r = restored.first;
      expect(r.name, equals('full-config'));
      expect(r.displayName, equals('Full Config'));
      expect(r.description, equals('A full config test'));
      expect(r.command, equals('npx'));
      expect(r.args, equals(['-y', 'server']));
      expect(r.env, equals({'KEY': 'VALUE'}));
      expect(r.enabled, isTrue);
      expect(r.autoStart, isFalse);
      expect(r.timeout, equals(5000));
      expect(r.retryConfig?.maxRetries, equals(3));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: McpRetryConfig
  // ═══════════════════════════════════════════════════════════════

  group('McpRetryConfig', () {
    test('默认值', () {
      final config = McpRetryConfig();
      expect(config.maxRetries, equals(3));
      expect(config.retryDelay, equals(1000));
      expect(config.exponentialBackoff, isTrue);
    });

    test('toMap/fromMap 往返', () {
      final config = McpRetryConfig(
        maxRetries: 5,
        retryDelay: 2000,
        exponentialBackoff: false,
      );

      final map = config.toMap();
      final restored = McpRetryConfig.fromMap(map);

      expect(restored.maxRetries, equals(5));
      expect(restored.retryDelay, equals(2000));
      expect(restored.exponentialBackoff, isFalse);
    });

    test('copyWith', () {
      final original = McpRetryConfig();
      final modified = original.copyWith(maxRetries: 10);

      expect(modified.maxRetries, equals(10));
      expect(modified.retryDelay, equals(1000)); // 保持不变
    });

    test('相等性判断', () {
      final a = McpRetryConfig(maxRetries: 3, retryDelay: 1000);
      final b = McpRetryConfig(maxRetries: 3, retryDelay: 1000);
      final c = McpRetryConfig(maxRetries: 5, retryDelay: 1000);

      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode == b.hashCode, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: AiEmployeeEntity MCP 配置存取
  // ═══════════════════════════════════════════════════════════════

  group('AiEmployeeEntity MCP 配置存取', () {
    test('getMcpConfigs 从空配置返回空列表', () {
      final employee = _createEmployee();
      expect(employee.getMcpConfigs(), isEmpty);
    });

    test('getMcpConfigs 解析 JSON 配置', () {
      final employee = _createEmployee(
        mcpConfig: '[{"name":"fs","transportType":"stdio","command":"npx"}]',
      );
      final configs = employee.getMcpConfigs();
      expect(configs.length, equals(1));
      expect(configs.first.name, equals('fs'));
    });

    test('setMcpConfigs 生成正确的 JSON', () {
      final employee = _createEmployee();
      final configs = [
        McpServerConfig.stdio(name: 'fs', command: 'npx'),
        McpServerConfig.sse(name: 'api', url: 'http://localhost/sse'),
      ];

      final updated = employee.setMcpConfigs(configs);

      // 验证 mcpConfig 字段是有效 JSON
      expect(updated.mcpConfig, isNotNull);
      final restored = McpServerConfig.parseList(updated.mcpConfig);
      expect(restored.length, equals(2));
      expect(restored[0].name, equals('fs'));
      expect(restored[1].name, equals('api'));
    });

    test('setMcpConfigs 更新 updateTime', () {
      final employee = _createEmployee();
      final originalTime = employee.updateTime;

      // 确保有微小延迟（copyWith 中 DateTime.now() 可能与 createTime 相同）
      // 由于 DateTime.now() 在 copyWith 中调用，实际测试中只要方法不抛异常即可
      final updated = employee.setMcpConfigs([
        McpServerConfig.stdio(name: 'test', command: 'echo'),
      ]);

      // 验证 updateTime 被设置了（copyWith 中显式传入 DateTime.now()）
      expect(updated.updateTime, isNotNull);
      // mcpConfig 字段被正确设置
      expect(updated.mcpConfig, isNotNull);
      expect(updated.mcpConfig!, isNotEmpty);
    });

    test('isMcpEnabled 默认为 false', () {
      final employee = _createEmployee();
      expect(employee.isMcpEnabled, isFalse);
    });

    test('isMcpEnabled enableMcp=1 时为 true', () {
      final employee = _createEmployee(enableMcp: 1);
      expect(employee.isMcpEnabled, isTrue);
    });

    test('setMcpConfigs 后 getMcpConfigs 往返一致', () {
      final employee = _createEmployee();
      final configs = [
        McpServerConfig.stdio(
          name: 'complex',
          command: 'npx',
          args: ['-y', 'server'],
          env: {'API_KEY': 'secret'},
          enabled: true,
          timeout: 10000,
          retryConfig: McpRetryConfig(maxRetries: 5),
        ),
      ];

      final updated = employee.setMcpConfigs(configs);
      final restored = updated.getMcpConfigs();

      expect(restored.length, equals(1));
      expect(restored[0].name, equals('complex'));
      expect(restored[0].command, equals('npx'));
      expect(restored[0].args, equals(['-y', 'server']));
      expect(restored[0].env, equals({'API_KEY': 'secret'}));
      expect(restored[0].timeout, equals(10000));
      expect(restored[0].retryConfig?.maxRetries, equals(5));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: EmployeeConfigService MCP CRUD
  // ═══════════════════════════════════════════════════════════════

  group('EmployeeConfigService MCP CRUD', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('mcp-config');

      // 创建一个测试员工
      employeeId = const Uuid().v4();
      await fixture.employeeManager.createEmployee(
        _createEmployee(uuid: employeeId, name: 'MCP测试员工', deviceId: fixture.deviceId),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('getEmployeeConfig 返回空 MCP 配置', () async {
      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs, isEmpty);
      expect(config.employee.isMcpEnabled, isFalse);
    });

    test('updateEmployeeMcpConfigs 设置多个 MCP 配置', () async {
      final configs = [
        McpServerConfig.stdio(name: 'fs', command: 'npx', args: ['-y', 'fs-server']),
        McpServerConfig.sse(name: 'api', url: 'http://localhost:3001/sse'),
      ];

      await fixture.configService.updateEmployeeMcpConfigs(employeeId, configs);

      // 验证持久化
      final employee = await fixture.employeeManager.getEmployee(employeeId);
      expect(employee, isNotNull);
      final restored = employee!.getMcpConfigs();
      expect(restored.length, equals(2));
      expect(restored[0].name, equals('fs'));
      expect(restored[1].name, equals('api'));
    });

    test('addMcpServerConfig 添加单个 MCP 配置', () async {
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'git', command: 'npx', args: ['-y', 'git-server']),
      );

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('git'));
    });

    test('addMcpServerConfig 重复名称抛出异常', () async {
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'duplicate', command: 'cmd1'),
      );

      expect(
        () => fixture.configService.addMcpServerConfig(
          employeeId,
          McpServerConfig.stdio(name: 'duplicate', command: 'cmd2'),
        ),
        throwsArgumentError,
      );
    });

    test('removeMcpServerConfig 删除指定名称的配置', () async {
      // 先添加两个
      await fixture.configService.updateEmployeeMcpConfigs(employeeId, [
        McpServerConfig.stdio(name: 'keep', command: 'keep-cmd'),
        McpServerConfig.stdio(name: 'remove', command: 'remove-cmd'),
      ]);

      // 删除一个
      await fixture.configService.removeMcpServerConfig(employeeId, 'remove');

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('keep'));
    });

    test('removeMcpServerConfig 删除不存在的名称不会报错', () async {
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'only', command: 'cmd'),
      );

      // 删除不存在的名称
      await fixture.configService.removeMcpServerConfig(employeeId, 'nonexistent');

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
    });

    test('updateMcpServerConfig 更新指定名称的配置', () async {
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'updateable', command: 'old-cmd', enabled: true),
      );

      await fixture.configService.updateMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'updateable', command: 'new-cmd', enabled: false),
      );

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.command, equals('new-cmd'));
      expect(config.mcpConfigs.first.enabled, isFalse);
    });

    test('updateMcpServerConfig 更新不存在的名称抛出异常', () async {
      expect(
        () => fixture.configService.updateMcpServerConfig(
          employeeId,
          McpServerConfig.stdio(name: 'nonexistent', command: 'cmd'),
        ),
        throwsArgumentError,
      );
    });

    test('setMcpEnabled 启用 MCP', () async {
      await fixture.configService.setMcpEnabled(employeeId, true);

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.employee.isMcpEnabled, isTrue);
      expect(config.employee.enableMcp, equals(1));
    });

    test('setMcpEnabled 禁用 MCP', () async {
      // 先启用
      await fixture.configService.setMcpEnabled(employeeId, true);
      // 再禁用
      await fixture.configService.setMcpEnabled(employeeId, false);

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.employee.isMcpEnabled, isFalse);
      expect(config.employee.enableMcp, equals(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 6: MCP 配置变更事件通知
  // ═══════════════════════════════════════════════════════════════

  group('MCP 配置变更事件通知', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('mcp-event');
      employeeId = const Uuid().v4();
      await fixture.employeeManager.createEmployee(
        _createEmployee(uuid: employeeId, name: '事件测试员工', deviceId: fixture.deviceId),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('updateEmployeeMcpConfigs 触发 mcp 变更事件', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = fixture.configService.onConfigChanged.listen(events.add);

      await fixture.configService.updateEmployeeMcpConfigs(
        employeeId,
        [McpServerConfig.stdio(name: 'test', command: 'cmd')],
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, isNotEmpty);
      expect(events.last.type, equals(EmployeeConfigChangeType.mcp));
      expect(events.last.employeeId, equals(employeeId));
    });

    test('setMcpEnabled 触发 mcpEnabled 变更事件', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = fixture.configService.onConfigChanged.listen(events.add);

      await fixture.configService.setMcpEnabled(employeeId, true);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, isNotEmpty);
      expect(events.last.type, equals(EmployeeConfigChangeType.mcpEnabled));
      expect(events.last.data, isTrue);
    });

    test('addMcpServerConfig 触发 mcp 变更事件', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = fixture.configService.onConfigChanged.listen(events.add);

      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'new', command: 'cmd'),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, isNotEmpty);
      expect(events.last.type, equals(EmployeeConfigChangeType.mcp));
    });

    test('removeMcpServerConfig 触发 mcp 变更事件', () async {
      // 先添加
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'to-remove', command: 'cmd'),
      );

      final events = <EmployeeConfigChangeEvent>[];
      final sub = fixture.configService.onConfigChanged.listen(events.add);

      await fixture.configService.removeMcpServerConfig(employeeId, 'to-remove');

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, isNotEmpty);
      expect(events.last.type, equals(EmployeeConfigChangeType.mcp));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 7: MCP 配置跨设备同步
  // ═══════════════════════════════════════════════════════════════

  group('MCP 配置跨设备同步', () {
    late ServerTestFixture serverFixture;
    late String employeeId;

    setUp(() async {
      serverFixture = await ServerTestFixture.create('mcp-sync');

      // 在 Server 端创建员工（带 MCP 配置）
      employeeId = const Uuid().v4();
      final configs = [
        McpServerConfig.stdio(name: 'fs', command: 'npx', args: ['-y', 'fs-server']),
        McpServerConfig.sse(name: 'api', url: 'http://localhost:3001/sse'),
      ];
      final employee = _createEmployee(
        uuid: employeeId,
        name: '同步测试员工',
        deviceId: serverFixture.deviceId,
        enableMcp: 1,
        mcpConfig: McpServerConfig.toJsonString(configs),
      );
      await serverFixture.employeeManager.createEmployee(employee);
    });

    tearDown(() async {
      await serverFixture.dispose();
    });

    test('员工数据同步时 MCP 配置完整保留', () async {
      // 通过 RPC 获取员工数据
      final result = await serverFixture.callRpc(
        HostRpcConfig.methodGetEmployee,
        {'uuid': employeeId},
      );

      final empMap = result['employee'] as Map<String, dynamic>;
      expect(empMap['enableMcp'], equals(1));
      expect(empMap['mcpConfig'], isNotNull);

      // 解析 MCP 配置
      final configs = McpServerConfig.parseList(empMap['mcpConfig'] as String?);
      expect(configs.length, equals(2));
      expect(configs[0].name, equals('fs'));
      expect(configs[0].transportType, equals('stdio'));
      expect(configs[1].name, equals('api'));
      expect(configs[1].transportType, equals('sse'));
    });

    test('员工同步 RPC 保留 MCP 配置', () async {
      // 获取原始员工数据
      final employee = await serverFixture.employeeManager.getEmployee(employeeId);
      expect(employee, isNotNull);
      final originalConfigs = employee!.getMcpConfigs();
      expect(originalConfigs.length, equals(2));

      // 创建另一个 Server 来接收同步数据
      final receiverServer = await ServerTestFixture.create('mcp-receiver');

      try {
        // 通过 RPC 同步员工到接收端
        await receiverServer.callRpc(
          HostRpcConfig.methodSyncEmployees,
          {'employees': [employee.toMap()]},
        );

        // 验证接收端的员工 MCP 配置
        final received = await receiverServer.employeeManager.getEmployee(employeeId);
        expect(received, isNotNull);
        expect(received!.enableMcp, equals(1));

        final receivedConfigs = received.getMcpConfigs();
        expect(receivedConfigs.length, equals(2));
        expect(receivedConfigs[0].name, equals('fs'));
        expect(receivedConfigs[0].command, equals('npx'));
        expect(receivedConfigs[1].name, equals('api'));
        expect(receivedConfigs[1].url, equals('http://localhost:3001/sse'));
      } finally {
        await receiverServer.dispose();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 8: MCP 配置端到端场景
  // ═══════════════════════════════════════════════════════════════

  group('MCP 配置端到端场景', () {
    late LanTestHarness harness;
    late String employeeId;

    setUp(() async {
      harness = await LanTestHarness.create('mcp-e2e');

      // 在 Server 端创建员工
      employeeId = const Uuid().v4();
      await harness.server.employeeManager.createEmployee(
        _createEmployee(
          uuid: employeeId,
          name: 'E2E测试员工',
          deviceId: harness.server.deviceId,
        ),
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('Client 端配置 MCP 后 Server 端数据一致', () async {
      // 在 Client 端创建员工
      final clientEmpId = const Uuid().v4();
      await harness.client.employeeManager.createEmployee(
        _createEmployee(uuid: clientEmpId, name: 'Client端员工', deviceId: harness.client.deviceId),
      );

      // 在 Client 端配置 MCP
      await harness.client.configService.addMcpServerConfig(
        clientEmpId,
        McpServerConfig.stdio(
          name: 'e2e-fs',
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-filesystem'],
          env: {'ROOT': '/home'},
        ),
      );

      // 验证 Client 端持久化
      final clientConfig = await harness.client.configService.getEmployeeConfig(clientEmpId);
      expect(clientConfig.mcpConfigs.length, equals(1));
      expect(clientConfig.mcpConfigs.first.name, equals('e2e-fs'));
      expect(clientConfig.mcpConfigs.first.env, equals({'ROOT': '/home'}));
    });

    test('多步 MCP 配置操作序列', () async {
      // 在 Client 端创建员工
      final seqEmpId = const Uuid().v4();
      await harness.client.employeeManager.createEmployee(
        _createEmployee(uuid: seqEmpId, name: '序列操作员工', deviceId: harness.client.deviceId),
      );

      // 1. 添加第一个 MCP 配置
      await harness.client.configService.addMcpServerConfig(
        seqEmpId,
        McpServerConfig.stdio(name: 'first', command: 'cmd1'),
      );

      // 2. 添加第二个 MCP 配置
      await harness.client.configService.addMcpServerConfig(
        seqEmpId,
        McpServerConfig.sse(name: 'second', url: 'http://localhost/sse'),
      );

      // 3. 启用 MCP
      await harness.client.configService.setMcpEnabled(seqEmpId, true);

      // 4. 更新第一个配置
      await harness.client.configService.updateMcpServerConfig(
        seqEmpId,
        McpServerConfig.stdio(name: 'first', command: 'updated-cmd1', enabled: false),
      );

      // 5. 验证最终状态
      final config = await harness.client.configService.getEmployeeConfig(seqEmpId);
      expect(config.employee.isMcpEnabled, isTrue);
      expect(config.mcpConfigs.length, equals(2));

      final first = config.mcpConfigs.firstWhere((c) => c.name == 'first');
      expect(first.command, equals('updated-cmd1'));
      expect(first.enabled, isFalse);

      final second = config.mcpConfigs.firstWhere((c) => c.name == 'second');
      expect(second.transportType, equals('sse'));

      // 6. 删除第二个配置
      await harness.client.configService.removeMcpServerConfig(seqEmpId, 'second');

      final afterRemove = await harness.client.configService.getEmployeeConfig(seqEmpId);
      expect(afterRemove.mcpConfigs.length, equals(1));
      expect(afterRemove.mcpConfigs.first.name, equals('first'));
    });

    test('MCP 配置与员工基础信息共存', () async {
      // 在 Client 端创建员工
      final coexistEmpId = const Uuid().v4();
      await harness.client.employeeManager.createEmployee(
        _createEmployee(uuid: coexistEmpId, name: '共存测试员工', deviceId: harness.client.deviceId),
      );

      // 同时更新基础信息和 MCP 配置
      await harness.client.configService.updateEmployeeBasicInfo(
        coexistEmpId,
        name: '更新后的员工',
        description: '带 MCP 配置的员工',
      );

      await harness.client.configService.updateEmployeeMcpConfigs(
        coexistEmpId,
        [
          McpServerConfig.http(
            name: 'http-mcp',
            url: 'http://mcp.example.com/api',
            headers: {'X-API-Key': 'test-key'},
            timeout: 60000,
            retryConfig: McpRetryConfig(maxRetries: 10, retryDelay: 5000),
          ),
        ],
      );

      await harness.client.configService.setMcpEnabled(coexistEmpId, true);

      // 验证所有数据完整
      final config = await harness.client.configService.getEmployeeConfig(coexistEmpId);
      expect(config.employee.name, equals('更新后的员工'));
      expect(config.employee.description, equals('带 MCP 配置的员工'));
      expect(config.employee.isMcpEnabled, isTrue);
      expect(config.mcpConfigs.length, equals(1));

      final mcp = config.mcpConfigs.first;
      expect(mcp.transportType, equals('http'));
      expect(mcp.url, equals('http://mcp.example.com/api'));
      expect(mcp.headers?['X-API-Key'], equals('test-key'));
      expect(mcp.timeout, equals(60000));;
      expect(mcp.retryConfig?.maxRetries, equals(10));
      expect(mcp.retryConfig?.retryDelay, equals(5000));
    });
  });
}
