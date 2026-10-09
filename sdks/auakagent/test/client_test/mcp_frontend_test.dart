/// 前端 MCP 配置管理功能测试
///
/// 模拟 wenzflow_flutter 前端管理员工 MCP 配置的完整流程，
/// 验证前端操作（增删改查 + 启用/禁用）在后端能正确执行。
///
/// 参考：
/// - wenzflow_flutter/lib/view/desktop/ai/employee/employee_tab/info/mcp/controller.dart
/// - wenzflow_flutter/lib/service/ai/mcp/test/employee_test_helper.dart
///
/// 前端 MCP 管理流程：
/// 1. loadMcpServers: 加载员工 MCP 技能列表（skillType='mcp'）
/// 2. addMcpServer: 创建 AiEmployeeSkillEntity（skillType='mcp'）→ skillManager.createSkill
/// 3. updateMcpServer: 更新 entity.config → skillManager.updateSkill
/// 4. deleteMcpServer: 删除 → skillManager.deleteSkill
/// 5. toggleMcpServer: 启用/禁用 → skillManager.setSkillEnabled
/// 6. parseMcpConfig: 解析 config JSON → McpServerConfig
///
/// 另一条路径（通过 Agent Proxy）：
/// - setMcpConfigs: 批量保存 MCP 配置到员工实体 + SkillStore
/// - getMcpConfigsAsync: 从 Agent 运行时获取 MCP 配置
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/entities/employee_entity.dart';
import 'package:auakagent/src/persistence/entities/mcp_server_config.dart';
import 'package:auakagent/src/persistence/entities/skill_entity.dart';

import 'client_test_fixture.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法：模拟前端 EmployeeMcpController 的核心逻辑
// ═══════════════════════════════════════════════════════════════

/// 模拟前端 _buildMcpEntities：从 McpServerConfig Map 列表构建 AiEmployeeSkillEntity
List<AiEmployeeSkillEntity> buildMcpEntities(
  String employeeId,
  List<Map<String, dynamic>> configMaps,
) {
  return configMaps.map((m) {
    final config = McpServerConfig.fromMap(m);
    return AiEmployeeSkillEntity(
      uuid: 'mcp_${config.name}_${const Uuid().v4()}',
      employeeId: employeeId,
      name: config.name,
      description: config.description,
      skillType: 'mcp',
      config: McpServerConfig.toJsonString([config]),
      enabled: config.enabled ? 1 : 0,
      createTime: DateTime.now(),
      updateTime: DateTime.now(),
    );
  }).toList();
}

/// 模拟前端 _extractMcpConfigMaps：从 AiEmployeeSkillEntity 列表提取配置 Map
List<Map<String, dynamic>> extractMcpConfigMaps(
  List<AiEmployeeSkillEntity> mcpServers,
) {
  return mcpServers.map((entity) {
    try {
      final decoded = jsonDecode(entity.config ?? '[]');
      if (decoded is List && decoded.isNotEmpty) {
        return decoded[0] as Map<String, dynamic>;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }).toList();
}

/// 模拟前端 parseMcpConfig：解析单个 MCP 配置
Map<String, dynamic>? parseMcpConfig(String? configJson) {
  if (configJson == null || configJson.isEmpty) return null;
  try {
    final decoded = jsonDecode(configJson);
    if (decoded is List && decoded.isNotEmpty) {
      return decoded[0] as Map<String, dynamic>;
    }
    return decoded as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// 模拟前端 addMcpServer：创建 MCP 技能实体
AiEmployeeSkillEntity createMcpSkillEntity({
  required String employeeId,
  required String name,
  String? description,
  required String transportType,
  String? command,
  List<String>? args,
  Map<String, String>? env,
  String? url,
  Map<String, String>? headers,
}) {
  final McpServerConfig serverConfig;
  switch (transportType) {
    case 'stdio':
      serverConfig = McpServerConfig.stdio(
        name: name,
        command: command ?? '',
        args: args,
        env: env,
      );
    case 'sse':
      serverConfig = McpServerConfig.sse(
        name: name,
        url: url ?? '',
        headers: headers,
      );
    case 'http':
      serverConfig = McpServerConfig.http(
        name: name,
        url: url ?? '',
        headers: headers,
      );
    default:
      serverConfig = McpServerConfig.stdio(
        name: name,
        command: command ?? '',
      );
  }

  return AiEmployeeSkillEntity(
    uuid: const Uuid().v4(),
    employeeId: employeeId,
    name: name,
    description: description,
    skillType: 'mcp',
    config: McpServerConfig.toJsonString([serverConfig]),
    createTime: DateTime.now(),
    updateTime: DateTime.now(),
  );
}

// ═══════════════════════════════════════════════════════════════
// 测试主体
// ═══════════════════════════════════════════════════════════════

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: 前端 MCP 实体构建与解析（纯数据层，无需 Fixture）
  // ═══════════════════════════════════════════════════════════════

  group('前端 MCP 实体构建与解析', () {
    test('buildMcpEntities 从配置 Map 构建技能实体', () {
      final entities = buildMcpEntities('emp-1', [
        {
          'name': 'filesystem',
          'transportType': 'stdio',
          'command': 'npx',
          'args': ['-y', 'fs-server'],
        },
        {
          'name': 'remote-api',
          'transportType': 'sse',
          'url': 'http://localhost:3001/sse',
        },
      ]);

      expect(entities.length, equals(2));
      expect(entities[0].skillType, equals('mcp'));
      expect(entities[0].name, equals('filesystem'));
      expect(entities[0].uuid, startsWith('mcp_filesystem_'));
      expect(entities[1].name, equals('remote-api'));
    });

    test('extractMcpConfigMaps 从技能实体提取配置', () {
      final entities = buildMcpEntities('emp-1', [
        {
          'name': 'git',
          'transportType': 'stdio',
          'command': 'npx',
          'args': ['-y', 'git-server'],
          'env': {'DEBUG': 'true'},
        },
      ]);

      final configs = extractMcpConfigMaps(entities);

      expect(configs.length, equals(1));
      expect(configs[0]['name'], equals('git'));
      expect(configs[0]['transportType'], equals('stdio'));
      expect(configs[0]['command'], equals('npx'));
    });

    test('parseMcpConfig 解析单个配置', () {
      final config = McpServerConfig.stdio(
        name: 'test',
        command: 'cmd',
        args: ['arg1'],
      );
      final json = McpServerConfig.toJsonString([config]);

      final parsed = parseMcpConfig(json);

      expect(parsed, isNotNull);
      expect(parsed!['name'], equals('test'));
      expect(parsed['command'], equals('cmd'));
    });

    test('parseMcpConfig 空/null 输入返回 null', () {
      expect(parseMcpConfig(null), isNull);
      expect(parseMcpConfig(''), isNull);
      expect(parseMcpConfig('invalid'), isNull);
    });

    test('buildMcpEntities → extractMcpConfigMaps 往返一致', () {
      final originalConfigs = [
        {
          'name': 'fs',
          'transportType': 'stdio',
          'command': 'npx',
          'args': ['-y', 'fs-server'],
          'env': {'KEY': 'VALUE'},
        },
        {
          'name': 'api',
          'transportType': 'http',
          'url': 'http://api.example.com/mcp',
          'headers': {'Authorization': 'Bearer token'},
        },
      ];

      final entities = buildMcpEntities('emp-1', originalConfigs);
      final extracted = extractMcpConfigMaps(entities);

      expect(extracted.length, equals(2));
      expect(extracted[0]['name'], equals('fs'));
      expect(extracted[0]['env'], equals({'KEY': 'VALUE'}));
      expect(extracted[1]['name'], equals('api'));
      expect(extracted[1]['headers'], equals({'Authorization': 'Bearer token'}));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: 前端 SkillManager 路径 — MCP 增删改查
  // ═══════════════════════════════════════════════════════════════

  group('前端 SkillManager 路径 — MCP 增删改查', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('mcp-frontend');

      // 创建测试员工
      employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(
          uuid: employeeId,
          name: '前端MCP测试员工',
          status: 'active',
          role: 'assistant',
          model: 'gpt-4o-mini',
          createTime: now,
          updateTime: now,
        ),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    // ── 添加 MCP 配置 ──

    test('addMcpServer: 添加 stdio 类型 MCP 配置', () async {
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'filesystem',
        description: '文件系统 MCP',
        transportType: 'stdio',
        command: 'npx',
        args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
        env: {'NODE_ENV': 'production'},
      );

      await fixture.skillManager.createSkill(entity);

      // 验证持久化
      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();

      expect(mcpSkills.length, equals(1));
      expect(mcpSkills.first.name, equals('filesystem'));
      expect(mcpSkills.first.skillType, equals('mcp'));

      // 解析 config
      final config = parseMcpConfig(mcpSkills.first.config);
      expect(config, isNotNull);
      expect(config!['transportType'], equals('stdio'));
      expect(config['command'], equals('npx'));
      expect(config['args'], equals(['-y', '@modelcontextprotocol/server-filesystem', '/tmp']));
      expect(config['env'], equals({'NODE_ENV': 'production'}));
    });

    test('addMcpServer: 添加 sse 类型 MCP 配置', () async {
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'remote-sse',
        transportType: 'sse',
        url: 'http://localhost:3001/sse',
        headers: {'Authorization': 'Bearer test-token'},
      );

      await fixture.skillManager.createSkill(entity);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();

      expect(mcpSkills.length, equals(1));
      final config = parseMcpConfig(mcpSkills.first.config);
      expect(config!['transportType'], equals('sse'));
      expect(config['url'], equals('http://localhost:3001/sse'));
      expect(config['headers'], equals({'Authorization': 'Bearer test-token'}));
    });

    test('addMcpServer: 添加 http 类型 MCP 配置', () async {
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'remote-http',
        transportType: 'http',
        url: 'http://localhost:3002/mcp',
      );

      await fixture.skillManager.createSkill(entity);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final config = parseMcpConfig(
        skills.where((s) => s.skillType == 'mcp').first.config,
      );
      expect(config!['transportType'], equals('http'));
      expect(config['url'], equals('http://localhost:3002/mcp'));
    });

    test('addMcpServer: 添加多个 MCP 配置', () async {
      for (final type in ['stdio', 'sse', 'http']) {
        final entity = createMcpSkillEntity(
          employeeId: employeeId,
          name: 'mcp-$type',
          transportType: type,
          command: type == 'stdio' ? 'cmd' : null,
          url: type != 'stdio' ? 'http://localhost/$type' : null,
        );
        await fixture.skillManager.createSkill(entity);
      }

      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();

      expect(mcpSkills.length, equals(3));
      final names = mcpSkills.map((s) => s.name).toSet();
      expect(names, containsAll(['mcp-stdio', 'mcp-sse', 'mcp-http']));
    });

    // ── 查询 MCP 配置 ──

    test('loadMcpServers: 查询员工 MCP 配置列表', () async {
      // 先添加 2 个
      await fixture.skillManager.createSkill(
        createMcpSkillEntity(employeeId: employeeId, name: 'fs', transportType: 'stdio', command: 'npx'),
      );
      await fixture.skillManager.createSkill(
        createMcpSkillEntity(employeeId: employeeId, name: 'api', transportType: 'sse', url: 'http://localhost/sse'),
      );

      // 模拟前端 loadMcpServers
      final allSkills = await fixture.skillManager.getSkills(employeeId);
      final mcpServers = allSkills.where((s) => s.skillType == 'mcp').toList();

      expect(mcpServers.length, equals(2));

      // 解析每个配置
      final configs = extractMcpConfigMaps(mcpServers);
      expect(configs.length, equals(2));
      expect(configs.any((c) => c['name'] == 'fs'), isTrue);
      expect(configs.any((c) => c['name'] == 'api'), isTrue);
    });

    test('loadMcpServers: 无 MCP 配置时返回空列表', () async {
      final allSkills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = allSkills.where((s) => s.skillType == 'mcp').toList();

      expect(mcpSkills, isEmpty);
    });

    // ── 更新 MCP 配置 ──

    test('updateMcpServer: 更新 MCP 配置', () async {
      // 先添加
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'updateable',
        description: '原始描述',
        transportType: 'stdio',
        command: 'old-cmd',
      );
      await fixture.skillManager.createSkill(entity);
      final uuid = entity.uuid;

      // 模拟前端 updateMcpServer
      final newConfig = McpServerConfig.stdio(
        name: 'updateable',
        command: 'new-cmd',
        args: ['--verbose'],
        env: {'DEBUG': 'true'},
      );
      final updated = entity.copyWith(
        name: 'updateable',
        description: '更新后的描述',
        config: McpServerConfig.toJsonString([newConfig]),
        updateTime: DateTime.now(),
      );
      await fixture.skillManager.updateSkill(updated);

      // 验证
      final skills = await fixture.skillManager.getSkills(employeeId);
      final found = skills.where((s) => s.uuid == uuid).first;
      expect(found.name, equals('updateable'));
      expect(found.description, equals('更新后的描述'));

      final config = parseMcpConfig(found.config);
      expect(config!['command'], equals('new-cmd'));
      expect(config['args'], equals(['--verbose']));
      expect(config['env'], equals({'DEBUG': 'true'}));
    });

    test('updateMcpServer: 切换传输类型（stdio → sse）', () async {
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'switchable',
        transportType: 'stdio',
        command: 'old-cmd',
      );
      await fixture.skillManager.createSkill(entity);

      // 切换为 sse
      final newConfig = McpServerConfig.sse(
        name: 'switchable',
        url: 'http://new-url/sse',
      );
      await fixture.skillManager.updateSkill(
        entity.copyWith(
          config: McpServerConfig.toJsonString([newConfig]),
          updateTime: DateTime.now(),
        ),
      );

      final skills = await fixture.skillManager.getSkills(employeeId);
      final config = parseMcpConfig(
        skills.where((s) => s.skillType == 'mcp').first.config,
      );
      expect(config!['transportType'], equals('sse'));
      expect(config['url'], equals('http://new-url/sse'));
      expect(config.containsKey('command'), isFalse);
    });

    // ── 删除 MCP 配置 ──

    test('deleteMcpServer: 删除指定 MCP 配置', () async {
      final e1 = createMcpSkillEntity(employeeId: employeeId, name: 'keep', transportType: 'stdio', command: 'cmd1');
      final e2 = createMcpSkillEntity(employeeId: employeeId, name: 'delete', transportType: 'sse', url: 'http://localhost/sse');
      await fixture.skillManager.createSkill(e1);
      await fixture.skillManager.createSkill(e2);

      // 模拟前端 deleteMcpServer
      await fixture.skillManager.deleteSkill(e2.uuid);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.length, equals(1));
      expect(mcpSkills.first.name, equals('keep'));
    });

    test('deleteMcpServer: 删除所有 MCP 配置', () async {
      final e1 = createMcpSkillEntity(employeeId: employeeId, name: 'a', transportType: 'stdio', command: 'cmd');
      final e2 = createMcpSkillEntity(employeeId: employeeId, name: 'b', transportType: 'sse', url: 'http://localhost');
      await fixture.skillManager.createSkill(e1);
      await fixture.skillManager.createSkill(e2);

      await fixture.skillManager.deleteSkill(e1.uuid);
      await fixture.skillManager.deleteSkill(e2.uuid);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills, isEmpty);
    });

    // ── 启用/禁用 MCP 配置 ──

    test('toggleMcpServer: 启用 MCP 配置', () async {
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'toggle',
        transportType: 'stdio',
        command: 'cmd',
      );
      await fixture.skillManager.createSkill(entity);

      // 禁用
      await fixture.skillManager.setSkillEnabled(entity.uuid, false);
      var skills = await fixture.skillManager.getSkills(employeeId);
      var found = skills.where((s) => s.uuid == entity.uuid).first;
      expect(found.enabled, equals(0));

      // 启用
      await fixture.skillManager.setSkillEnabled(entity.uuid, true);
      skills = await fixture.skillManager.getSkills(employeeId);
      found = skills.where((s) => s.uuid == entity.uuid).first;
      expect(found.enabled, equals(1));
    });

    test('toggleMcpServer: 通过 copyWith 更新 enabled 状态', () async {
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'toggle2',
        transportType: 'stdio',
        command: 'cmd',
      );
      await fixture.skillManager.createSkill(entity);

      // 模拟前端通过 copyWith 更新 enabled
      final disabled = entity.copyWith(enabled: 0, updateTime: DateTime.now());
      await fixture.skillManager.updateSkill(disabled);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final found = skills.where((s) => s.uuid == entity.uuid).first;
      expect(found.enabled, equals(0));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 前端完整操作流程模拟
  // ═══════════════════════════════════════════════════════════════

  group('前端完整操作流程模拟', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('mcp-flow');
      employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(
          uuid: employeeId,
          name: '流程测试员工',
          status: 'active',
          role: 'assistant',
          model: 'gpt-4o-mini',
          createTime: now,
          updateTime: now,
        ),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('完整 CRUD 流程：添加→查询→更新→删除', () async {
      // 1. 添加
      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'crud-test',
        description: 'CRUD测试',
        transportType: 'stdio',
        command: 'npx',
        args: ['-y', 'server'],
      );
      await fixture.skillManager.createSkill(entity);

      // 2. 查询
      var skills = await fixture.skillManager.getSkills(employeeId);
      var mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.length, equals(1));
      expect(mcpSkills.first.name, equals('crud-test'));

      // 3. 更新
      final newConfig = McpServerConfig.sse(
        name: 'crud-test',
        url: 'http://updated-url/sse',
        headers: {'X-Custom': 'value'},
      );
      await fixture.skillManager.updateSkill(
        entity.copyWith(
          description: '已更新',
          config: McpServerConfig.toJsonString([newConfig]),
          updateTime: DateTime.now(),
        ),
      );

      skills = await fixture.skillManager.getSkills(employeeId);
      mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.first.description, equals('已更新'));
      final config = parseMcpConfig(mcpSkills.first.config);
      expect(config!['transportType'], equals('sse'));
      expect(config['url'], equals('http://updated-url/sse'));

      // 4. 删除
      await fixture.skillManager.deleteSkill(entity.uuid);
      skills = await fixture.skillManager.getSkills(employeeId);
      mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills, isEmpty);
    });

    test('多 MCP 配置管理：添加多个→禁用部分→删除一个→验证剩余', () async {
      // 添加 3 个
      final e1 = createMcpSkillEntity(employeeId: employeeId, name: 'fs', transportType: 'stdio', command: 'npx');
      final e2 = createMcpSkillEntity(employeeId: employeeId, name: 'api', transportType: 'sse', url: 'http://api/sse');
      final e3 = createMcpSkillEntity(employeeId: employeeId, name: 'db', transportType: 'http', url: 'http://db/mcp');
      await fixture.skillManager.createSkill(e1);
      await fixture.skillManager.createSkill(e2);
      await fixture.skillManager.createSkill(e3);

      // 禁用 api
      await fixture.skillManager.setSkillEnabled(e2.uuid, false);

      // 删除 fs
      await fixture.skillManager.deleteSkill(e1.uuid);

      // 验证剩余
      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.length, equals(2));

      final apiSkill = mcpSkills.where((s) => s.uuid == e2.uuid).first;
      expect(apiSkill.enabled, equals(0));

      final dbSkill = mcpSkills.where((s) => s.uuid == e3.uuid).first;
      expect(dbSkill.enabled, equals(1));
      final dbConfig = parseMcpConfig(dbSkill.config);
      expect(dbConfig!['transportType'], equals('http'));
    });

    test('前端 loadMcpServers 完整模拟', () async {
      // 模拟前端 loadMcpServers 的完整流程
      // 1. 先添加一些 MCP 配置
      await fixture.skillManager.createSkill(
        createMcpSkillEntity(employeeId: employeeId, name: 'server1', transportType: 'stdio', command: 'cmd1'),
      );
      await fixture.skillManager.createSkill(
        createMcpSkillEntity(employeeId: employeeId, name: 'server2', transportType: 'sse', url: 'http://localhost/sse'),
      );

      // 2. 模拟 loadMcpServers
      final allSkills = await fixture.skillManager.getSkills(employeeId);
      final mcpServers = allSkills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpServers.length, equals(2));

      // 3. 解析每个配置（模拟前端渲染）
      for (final server in mcpServers) {
        final configMap = parseMcpConfig(server.config);
        expect(configMap, isNotNull);
        expect(configMap!['name'], isNotNull);
        expect(configMap['transportType'], isNotNull);

        if (configMap['transportType'] == 'stdio') {
          expect(configMap['command'], isNotNull);
        } else {
          expect(configMap['url'], isNotNull);
        }
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 前端 MCP 配置数据格式验证
  // ═══════════════════════════════════════════════════════════════

  group('前端 MCP 配置数据格式验证', () {
    test('MCP 技能实体的 config 字段是有效的 JSON 数组', () async {
      final fixture = await ClientTestFixture.create('mcp-format');
      final employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(uuid: employeeId, name: '格式测试', status: 'active', role: 'assistant', createTime: now, updateTime: now),
      );

      final entity = createMcpSkillEntity(
        employeeId: employeeId,
        name: 'format-test',
        transportType: 'stdio',
        command: 'npx',
        args: ['-y', 'server'],
        env: {'KEY': 'VALUE'},
      );
      await fixture.skillManager.createSkill(entity);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkill = skills.firstWhere((s) => s.skillType == 'mcp');

      // 验证 config 是有效 JSON
      expect(mcpSkill.config, isNotNull);
      final decoded = jsonDecode(mcpSkill.config!);
      expect(decoded, isA<List>());
      expect(decoded.length, equals(1));

      final configMap = decoded[0] as Map<String, dynamic>;
      expect(configMap['name'], equals('format-test'));
      expect(configMap['transportType'], equals('stdio'));
      expect(configMap['command'], equals('npx'));

      await fixture.dispose();
    });

    test('前端 buildMcpEntities 生成的 UUID 以 mcp_ 开头', () {
      final entities = buildMcpEntities('emp-1', [
        {'name': 'test', 'transportType': 'stdio', 'command': 'cmd'},
      ]);

      expect(entities.first.uuid, startsWith('mcp_test_'));
    });

    test('前端 extractMcpConfigMaps 处理异常 config', () {
      final brokenEntities = [
        AiEmployeeSkillEntity(
          uuid: 'broken-1',
          employeeId: 'emp-1',
          name: 'broken',
          skillType: 'mcp',
          config: 'not-json',
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        AiEmployeeSkillEntity(
          uuid: 'empty-1',
          employeeId: 'emp-1',
          name: 'empty',
          skillType: 'mcp',
          config: null,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
        AiEmployeeSkillEntity(
          uuid: 'valid-1',
          employeeId: 'emp-1',
          name: 'valid',
          skillType: 'mcp',
          config: jsonEncode([{'name': 'ok', 'transportType': 'stdio', 'command': 'cmd'}]),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        ),
      ];

      final configs = extractMcpConfigMaps(brokenEntities);

      expect(configs.length, equals(3));
      expect(configs[0], isEmpty); // broken JSON → empty map
      expect(configs[1], isEmpty); // null config → empty map
      expect(configs[2]['name'], equals('ok')); // valid config
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: 前端 EmployeeConfigService 路径 — setMcpConfigs
  // ═══════════════════════════════════════════════════════════════

  group('前端 EmployeeConfigService 路径 — setMcpConfigs', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('mcp-config-svc');
      employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(uuid: employeeId, name: '配置服务测试', status: 'active', role: 'assistant', createTime: now, updateTime: now),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('EmployeeConfigService.updateEmployeeMcpConfigs 批量保存', () async {
      final configs = [
        McpServerConfig.stdio(name: 'fs', command: 'npx', args: ['-y', 'fs']),
        McpServerConfig.sse(name: 'api', url: 'http://localhost/sse'),
      ];

      await fixture.configService.updateEmployeeMcpConfigs(employeeId, configs);

      // 通过 EmployeeConfig 验证
      final empConfig = await fixture.configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs.length, equals(2));
      expect(empConfig.mcpConfigs[0].name, equals('fs'));
      expect(empConfig.mcpConfigs[1].name, equals('api'));
    });

    test('EmployeeConfigService.addMcpServerConfig 添加单个', () async {
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'added', command: 'cmd'),
      );

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('added'));
    });

    test('EmployeeConfigService.removeMcpServerConfig 删除', () async {
      await fixture.configService.updateEmployeeMcpConfigs(employeeId, [
        McpServerConfig.stdio(name: 'keep', command: 'keep'),
        McpServerConfig.stdio(name: 'remove', command: 'remove'),
      ]);

      await fixture.configService.removeMcpServerConfig(employeeId, 'remove');

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.name, equals('keep'));
    });

    test('EmployeeConfigService.updateMcpServerConfig 更新', () async {
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.stdio(name: 'update', command: 'old'),
      );

      await fixture.configService.updateMcpServerConfig(
        employeeId,
        McpServerConfig.sse(name: 'update', url: 'http://new-url'),
      );

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.mcpConfigs.length, equals(1));
      expect(config.mcpConfigs.first.transportType, equals('sse'));
      expect(config.mcpConfigs.first.url, equals('http://new-url'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 6: 跨设备 MCP 配置同步
  // ═══════════════════════════════════════════════════════════════

  group('跨设备 MCP 配置同步', () {
    late ServerTestFixture serverA;
    late ServerTestFixture serverB;
    late String employeeId;

    setUp(() async {
      serverA = await ServerTestFixture.create('sync-a');
      serverB = await ServerTestFixture.create('sync-b');

      // 在 ServerA 创建员工并配置 MCP
      employeeId = const Uuid().v4();
      final now = DateTime.now();
      final configs = [
        McpServerConfig.stdio(name: 'sync-fs', command: 'npx', args: ['-y', 'fs-server']),
        McpServerConfig.sse(name: 'sync-api', url: 'http://api.example.com/sse'),
      ];
      await serverA.employeeManager.createEmployee(
        AiEmployeeEntity(
          uuid: employeeId,
          name: '同步测试员工',
          status: 'active',
          role: 'assistant',
          deviceId: serverA.deviceId,
          enableMcp: 1,
          mcpConfig: McpServerConfig.toJsonString(configs),
          createTime: now,
          updateTime: now,
        ),
      );

      // 同时在 ServerA 创建对应的 MCP 技能实体
      for (final config in configs) {
        await serverA.skillManager.createSkill(AiEmployeeSkillEntity(
          uuid: 'mcp_${config.name}_${const Uuid().v4()}',
          employeeId: employeeId,
          name: config.name,
          description: config.description,
          skillType: 'mcp',
          config: McpServerConfig.toJsonString([config]),
          createTime: now,
          updateTime: now,
        ));
      }
    });

    tearDown(() async {
      await serverA.dispose();
      await serverB.dispose();
    });

    test('员工同步 RPC 保留 MCP 配置和技能', () async {
      // 通过 RPC 同步员工数据
      final employee = await serverA.employeeManager.getEmployee(employeeId);
      expect(employee, isNotNull);
      expect(employee!.enableMcp, equals(1));

      // 同步员工
      await serverB.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee.toMap()]},
      );

      // 验证 ServerB 的员工 MCP 配置
      final empOnB = await serverB.employeeManager.getEmployee(employeeId);
      expect(empOnB, isNotNull);
      expect(empOnB!.enableMcp, equals(1));
      final configs = empOnB.getMcpConfigs();
      expect(configs.length, equals(2));
      expect(configs[0].name, equals('sync-fs'));
      expect(configs[1].name, equals('sync-api'));
    });

    test('技能同步 RPC 保留 MCP 技能实体', () async {
      // 获取 ServerA 的 MCP 技能
      final skills = await serverA.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.length, equals(2));

      // 先同步员工（外键依赖）
      final employee = await serverA.employeeManager.getEmployee(employeeId);
      await serverB.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee!.toMap()]},
      );

      // 同步技能
      await serverB.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': mcpSkills.map((s) => s.toMap()).toList()},
      );

      // 验证 ServerB 的技能
      final skillsOnB = await serverB.skillManager.getSkills(employeeId);
      final mcpSkillsOnB = skillsOnB.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkillsOnB.length, equals(2));

      // 验证配置内容
      final configMaps = extractMcpConfigMaps(mcpSkillsOnB);
      expect(configMaps.length, equals(2));
      expect(configMaps.any((c) => c['name'] == 'sync-fs'), isTrue);
      expect(configMaps.any((c) => c['name'] == 'sync-api'), isTrue);
    });
  });
}
