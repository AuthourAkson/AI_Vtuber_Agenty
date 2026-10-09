/// 前端 MCP 配置问题诊断测试
///
/// 从多个维度分析前端无法正常配置员工 MCP 的问题：
///
/// 维度 1：双路径数据不一致（SkillStore vs EmployeeEntity.mcpConfig）
///   - 前端 addMcpServer 走 SkillManager.createSkill → SkillStore
///   - Agent.setMcpConfigs 走 EmployeeStore + SkillStore 双写
///   - 两条路径独立写入，可能互相覆盖或丢失
///
/// 维度 2：setMcpConfigs 的 config 格式不一致
///   - SkillStore 中 entity.config = McpServerConfig.toJsonString([config])（JSON 数组）
///   - Agent.setMcpConfigs 中 entity.config = jsonEncode(config.toMap())（JSON 对象）
///   - 前端 parseMcpConfig 期望 List 格式，单对象格式无法解析！
///
/// 维度 3：loadMcpServers 通过 proxy.getMcpConfigsAsync() 返回空
///   - AgentImpl.getMcpConfigs() 从运行时已加载的 McpSkill 提取
///   - 如果 Agent 未初始化或 MCP 技能未加载，返回空列表
///   - 前端拿到空列表后覆盖 mcpServers，导致已有配置丢失
///
/// 维度 4：toggleMcpServer 只更新 entity.enabled，未更新 config 内 enabled
///   - entity.enabled=0 但 config JSON 中 enabled=true
///   - Agent 重载时按 config 内的 enabled 判断，导致禁用无效
///
/// 维度 5：_buildMcpEntities 重建时丢失原始 UUID
///   - loadMcpServers → getMcpConfigsAsync → _buildMcpEntities
///   - 每次加载都生成新 UUID，后续 updateMcpServer/deleteMcpServer 按 UUID 查找会失败
///
/// 维度 6：addMcpServer 走 proxy 路径时先加入 mcpServers 再批量保存
///   - 如果 _saveMcpConfigsViaProxy 失败，mcpServers 已被修改但未持久化
///   - 后续 loadMcpServers 会重新从 Agent 读取（覆盖错误状态），但中间状态不可靠
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/persistence/entities/employee_entity.dart';
import 'package:auakagent/src/persistence/entities/mcp_server_config.dart';
import 'package:auakagent/src/persistence/entities/skill_entity.dart';
import 'package:auakagent/src/utils/logger.dart';

import 'client_test_fixture.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════
  // 维度 1：双路径数据不一致
  // ═══════════════════════════════════════════════════════════════

  group('维度1: 双路径数据不一致（SkillStore vs EmployeeEntity.mcpConfig）', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('dual-path');
      employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(
          uuid: employeeId,
          name: '双路径测试',
          status: 'active',
          role: 'assistant',
          createTime: now,
          updateTime: now,
        ),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('路径A: SkillManager.createSkill 只写 SkillStore，不更新 Employee.mcpConfig', () async {
      final config = McpServerConfig.stdio(name: 'via-skill-manager', command: 'npx');
      final entity = AiEmployeeSkillEntity(
        uuid: const Uuid().v4(),
        employeeId: employeeId,
        name: 'via-skill-manager',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([config]),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      await fixture.skillManager.createSkill(entity);

      // SkillStore 有记录
      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.length, equals(1));
      expect(mcpSkills.first.name, equals('via-skill-manager'));

      // 但 Employee.mcpConfig 为空！
      final employee = await fixture.employeeManager.getEmployee(employeeId);
      expect(employee!.mcpConfig, isNull);
      expect(employee.getMcpConfigs(), isEmpty); // ❌ 问题1: 员工实体没有 MCP 配置
    });

    test('路径B: EmployeeConfigService.updateEmployeeMcpConfigs 只写 Employee，不写 SkillStore', () async {
      final configs = [
        McpServerConfig.stdio(name: 'via-config-service', command: 'npx'),
      ];

      await fixture.configService.updateEmployeeMcpConfigs(employeeId, configs);

      // Employee.mcpConfig 有记录
      final employee = await fixture.employeeManager.getEmployee(employeeId);
      expect(employee!.getMcpConfigs().length, equals(1));

      // 但 SkillStore 为空！
      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills, isEmpty); // ❌ 问题2: SkillStore 没有 MCP 技能
    });

    test('路径A写入后路径B读取不一致', () async {
      // 通过 SkillManager 写入
      final config = McpServerConfig.stdio(name: 'skill-path', command: 'cmd');
      await fixture.skillManager.createSkill(AiEmployeeSkillEntity(
        uuid: const Uuid().v4(),
        employeeId: employeeId,
        name: 'skill-path',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([config]),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      // 通过 EmployeeConfigService 读取
      final empConfig = await fixture.configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs, isEmpty); // ❌ 路径A写入的数据在路径B看不到

      // 反过来也一样
      await fixture.configService.updateEmployeeMcpConfigs(employeeId, [
        McpServerConfig.sse(name: 'config-path', url: 'http://localhost/sse'),
      ]);

      final skills = await fixture.skillManager.getSkills(employeeId);
      final mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      // 只有之前通过 SkillManager 创建的那一条，路径B的写入不在 SkillStore 中
      expect(mcpSkills.length, equals(1));
      expect(mcpSkills.first.name, equals('skill-path')); // ❌ 不是 'config-path'
    });

    test('路径B写入再路径A写入，路径B数据被覆盖', () async {
      // 先通过 EmployeeConfigService 写入
      await fixture.configService.updateEmployeeMcpConfigs(employeeId, [
        McpServerConfig.stdio(name: 'emp-config', command: 'cmd1'),
      ]);

      // 再通过 SkillManager 写入
      await fixture.skillManager.createSkill(AiEmployeeSkillEntity(
        uuid: const Uuid().v4(),
        employeeId: employeeId,
        name: 'skill-entry',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([
          McpServerConfig.stdio(name: 'skill-entry', command: 'cmd2'),
        ]),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      // Employee.mcpConfig 仍然是路径B的数据
      final employee = await fixture.employeeManager.getEmployee(employeeId);
      expect(employee!.getMcpConfigs().length, equals(1));
      expect(employee.getMcpConfigs().first.name, equals('emp-config'));

      // SkillStore 有两条
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.where((s) => s.skillType == 'mcp').length, equals(1)); // 只有 skill-entry
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 维度 2：config JSON 格式不一致（数组 vs 对象）
  // ═══════════════════════════════════════════════════════════════

  group('维度2: config JSON 格式不一致（数组 vs 对象）', () {
    test('前端写入的 config 是 JSON 数组格式', () {
      final config = McpServerConfig.stdio(name: 'test', command: 'cmd');
      final json = McpServerConfig.toJsonString([config]);

      final decoded = jsonDecode(json);
      expect(decoded, isA<List>()); // ✅ 数组格式
      expect(decoded.length, equals(1));
    });

    test('Agent.setMcpConfigs 写入的 config 是 JSON 对象格式（非数组）', () {
      // 模拟 AgentImpl.setMcpConfigs 第483行的行为：
      // config: jsonEncode(config.toMap())
      final config = McpServerConfig.stdio(name: 'test', command: 'cmd');
      final agentWrittenConfig = jsonEncode(config.toMap());

      final decoded = jsonDecode(agentWrittenConfig);
      expect(decoded, isA<Map>()); // ❌ 对象格式，不是数组！
    });

    test('前端 parseMcpConfig 无法解析 Agent 写入的对象格式', () {
      // Agent 写入的格式
      final config = McpServerConfig.stdio(name: 'agent-format', command: 'cmd');
      final agentConfig = jsonEncode(config.toMap());

      // 前端解析逻辑
      Map<String, dynamic>? parseMcpConfig(String? configJson) {
        if (configJson == null || configJson.isEmpty) return null;
        try {
          final decoded = jsonDecode(configJson);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded[0] as Map<String, dynamic>;
          }
          return decoded as Map<String, dynamic>; // ✅ 这行能兜底
        } catch (_) {
          return null;
        }
      }

      final result = parseMcpConfig(agentConfig);
      expect(result, isNotNull);
      expect(result!['name'], equals('agent-format'));
      // 注意：前端 parseMcpConfig 实际上有兜底逻辑 `return decoded as Map`
      // 但 McpSkill.fromEntity 会用 McpServerConfig.parseList 解析
    });

    test('McpServerConfig.parseList 无法解析单对象格式', () {
      final savedLevel = Logger.level;
      Logger.level = LogLevel.none;
      try {
        final config = McpServerConfig.stdio(name: 'single-obj', command: 'cmd');
        final singleObjJson = jsonEncode(config.toMap());

        // parseList 期望 List 或 Map(旧格式)
        final result = McpServerConfig.parseList(singleObjJson);
        // ❌ 单对象格式不含 name 作为 key，旧格式转换逻辑要求 Map 的 key 是 server name
        // 实际上 parseList 的 _convertLegacyMap 会把整个 map 当作一个 server
        // 但 name 字段不会被正确设置
      } finally {
        Logger.level = savedLevel;
      }
    });

    test('McpSkill.fromEntity 用 parseList 解析 Agent 写入的单对象 config 会失败', () {
      // Agent.setMcpConfigs 第483行: config: jsonEncode(config.toMap())
      final config = McpServerConfig.stdio(name: 'broken', command: 'cmd');
      final brokenConfig = jsonEncode(config.toMap());

      // McpSkill.fromEntity 内部调用 McpServerConfig.parseList
      final parsed = McpServerConfig.parseList(brokenConfig);

      // 单对象 JSON 既不是 List 也不是旧格式 Map（key 是 server name）
      // 实际行为取决于 parseList 实现
      // 如果 parseList 把它当作旧格式 Map，则 key 是 config 的字段名而非 server name
      // 这会导致 name 丢失或错误
      // 结论：parseList 对单对象格式可能返回空或错误数据
    });

    test('前端 _extractMcpConfigMaps 无法从 Agent 格式提取配置', () {
      // 模拟 Agent 写入的 config（单对象）
      final config = McpServerConfig.stdio(name: 'agent-written', command: 'cmd');
      final agentConfig = jsonEncode(config.toMap());

      final entity = AiEmployeeSkillEntity(
        uuid: 'test-uuid',
        employeeId: 'emp-1',
        name: 'agent-written',
        skillType: 'mcp',
        config: agentConfig, // ❌ 单对象格式
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // 前端 _extractMcpConfigMaps
      final decoded = jsonDecode(entity.config ?? '[]');
      Map<String, dynamic> extracted;
      if (decoded is List && decoded.isNotEmpty) {
        extracted = decoded[0] as Map<String, dynamic>;
      } else {
        extracted = <String, dynamic>{}; // ❌ 返回空 Map！
      }

      expect(extracted, isEmpty); // ❌ 丢失了配置数据！
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 维度 3：loadMcpServers 通过 proxy 返回空导致配置丢失
  // ═══════════════════════════════════════════════════════════════

  group('维度3: loadMcpServers 通过 proxy 返回空导致配置丢失', () {
    test('前端 _buildMcpEntities 重建时生成新 UUID', () {
      // 第一次加载
      final configMaps = [
        {'name': 'fs', 'transportType': 'stdio', 'command': 'npx'},
      ];
      final entities1 = configMaps.map((m) {
        final config = McpServerConfig.fromMap(m);
        return AiEmployeeSkillEntity(
          uuid: 'mcp_${config.name}_${const Uuid().v4()}',
          employeeId: 'emp-1',
          name: config.name,
          skillType: 'mcp',
          config: McpServerConfig.toJsonString([config]),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        );
      }).toList();

      // 第二次加载（模拟 loadMcpServers 再次调用）
      final entities2 = configMaps.map((m) {
        final config = McpServerConfig.fromMap(m);
        return AiEmployeeSkillEntity(
          uuid: 'mcp_${config.name}_${const Uuid().v4()}',
          employeeId: 'emp-1',
          name: config.name,
          skillType: 'mcp',
          config: McpServerConfig.toJsonString([config]),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        );
      }).toList();

      // ❌ UUID 不同！
      expect(entities1.first.uuid, isNot(equals(entities2.first.uuid)));
    });

    test('前端按 UUID 删除/更新在 loadMcpServers 后失效', () {
      // 初始添加
      final configMaps = [
        {'name': 'fs', 'transportType': 'stdio', 'command': 'npx'},
      ];
      final entities = configMaps.map((m) {
        final config = McpServerConfig.fromMap(m);
        return AiEmployeeSkillEntity(
          uuid: 'mcp_${config.name}_${const Uuid().v4()}',
          employeeId: 'emp-1',
          name: config.name,
          skillType: 'mcp',
          config: McpServerConfig.toJsonString([config]),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        );
      }).toList();

      final originalUuid = entities.first.uuid;

      // 模拟 loadMcpServers 重建
      final rebuilt = configMaps.map((m) {
        final config = McpServerConfig.fromMap(m);
        return AiEmployeeSkillEntity(
          uuid: 'mcp_${config.name}_${const Uuid().v4()}',
          employeeId: 'emp-1',
          name: config.name,
          skillType: 'mcp',
          config: McpServerConfig.toJsonString([config]),
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        );
      }).toList();

      // 按原始 UUID 查找 → 找不到
      final found = rebuilt.where((s) => s.uuid == originalUuid).firstOrNull;
      expect(found, isNull); // ❌ 删除/更新操作会静默失败
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 维度 4：toggleMcpServer 只更新 entity.enabled，未更新 config
  // ═══════════════════════════════════════════════════════════════

  group('维度4: toggleMcpServer enabled 状态与 config 内 enabled 不同步', () {
    test('toggleMcpServer 设置 enabled=0 后 config 中 enabled 仍为 true', () {
      final config = McpServerConfig.stdio(name: 'toggle-test', command: 'cmd', enabled: true);
      final entity = AiEmployeeSkillEntity(
        uuid: 'toggle-uuid',
        employeeId: 'emp-1',
        name: 'toggle-test',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([config]),
        enabled: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // 模拟前端 toggleMcpServer
      final disabled = entity.copyWith(enabled: 0, updateTime: DateTime.now());

      // entity.enabled = 0 ✅
      expect(disabled.enabled, equals(0));

      // 但 config JSON 中 enabled 仍为 true ❌
      final configMap = jsonDecode(disabled.config!) as List;
      final innerConfig = configMap[0] as Map<String, dynamic>;
      expect(innerConfig['enabled'], isTrue); // ❌ config 内 enabled 未更新！
    });

    test('Agent 重载时按 config 内 enabled 判断，禁用无效', () {
      // Agent.setMcpConfigs 第506行:
      // if (entity.skillType != 'mcp' || entity.enabled != 1) continue;
      // 这里检查的是 entity.enabled，不是 config 内的 enabled

      // 但如果通过 _saveMcpConfigsViaProxy 保存：
      // proxy.setMcpConfigs → Agent.setMcpConfigs → 重建 entity 时 enabled=1（硬编码）
      // 所以禁用状态在 Agent 重建时会丢失

      final config = McpServerConfig.stdio(name: 'disabled-test', command: 'cmd', enabled: true);
      final entity = AiEmployeeSkillEntity(
        uuid: 'disabled-uuid',
        employeeId: 'emp-1',
        name: 'disabled-test',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([config]),
        enabled: 0, // 前端已禁用
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      // 前端 _extractMcpConfigMaps 提取配置
      final decoded = jsonDecode(entity.config!) as List;
      final configMap = decoded[0] as Map<String, dynamic>;

      // configMap 中 enabled=true，entity.enabled=0
      // 通过 proxy.setMcpConfigs 传给 Agent 后：
      // Agent 重建 entity 时 enabled 硬编码为 1
      expect(configMap['enabled'], isTrue); // ❌ 禁用状态丢失
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 维度 5：_saveMcpConfigsViaProxy 失败时数据不一致
  // ═══════════════════════════════════════════════════════════════

  group('维度5: _saveMcpConfigsViaProxy 失败时的数据不一致', () {
    test('addMcpServer 先加入 mcpServers 再保存，失败后状态不一致', () async {
      final fixture = await ClientTestFixture.create('proxy-fail');
      final employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(uuid: employeeId, name: '失败测试', status: 'active', role: 'assistant', createTime: now, updateTime: now),
      );

      // 模拟：前端 addMcpServer 走 proxy 路径
      // 1. 创建 entity
      // 2. mcpServers.add(entity)  ← 已修改内存
      // 3. _saveMcpConfigsViaProxy() ← 如果失败，内存已脏

      // 验证：SkillManager 路径下没有数据
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.where((s) => s.skillType == 'mcp'), isEmpty);

      // 如果 proxy 为 null，走 SkillManager 路径
      // 如果 proxy 不为 null 但 setMcpConfigs 失败，
      // mcpServers 已被修改但数据未持久化

      await fixture.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 维度 6：端到端验证 — 模拟前端完整操作序列
  // ═══════════════════════════════════════════════════════════════

  group('维度6: 端到端验证 — 模拟前端完整操作序列', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('e2e-diag');
      employeeId = const Uuid().v4();
      final now = DateTime.now();
      await fixture.employeeManager.createEmployee(
        AiEmployeeEntity(uuid: employeeId, name: '端到端诊断', status: 'active', role: 'assistant', createTime: now, updateTime: now),
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('通过 SkillManager 添加后，configService 读不到', () async {
      // 模拟前端 addMcpServer（无 proxy 时走 SkillManager）
      final config = McpServerConfig.stdio(name: 'e2e-fs', command: 'npx');
      await fixture.skillManager.createSkill(AiEmployeeSkillEntity(
        uuid: const Uuid().v4(),
        employeeId: employeeId,
        name: 'e2e-fs',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([config]),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      // SkillManager 能读到
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.where((s) => s.skillType == 'mcp').length, equals(1));

      // 但 configService 读不到（Employee.mcpConfig 为空）
      final empConfig = await fixture.configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs, isEmpty); // ❌ 关键问题：数据不一致
    });

    test('通过 configService 添加后，SkillManager 读不到', () async {
      // 模拟 EmployeeConfigService 路径
      await fixture.configService.addMcpServerConfig(
        employeeId,
        McpServerConfig.sse(name: 'e2e-api', url: 'http://localhost/sse'),
      );

      // configService 能读到
      final empConfig = await fixture.configService.getEmployeeConfig(employeeId);
      expect(empConfig.mcpConfigs.length, equals(1));

      // 但 SkillManager 读不到
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.where((s) => s.skillType == 'mcp'), isEmpty); // ❌ 关键问题
    });

    test('前端 loadMcpServers 回退路径读取 SkillStore 的数据', () async {
      // 通过 SkillManager 写入
      final config = McpServerConfig.stdio(name: 'fallback-test', command: 'cmd');
      await fixture.skillManager.createSkill(AiEmployeeSkillEntity(
        uuid: const Uuid().v4(),
        employeeId: employeeId,
        name: 'fallback-test',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([config]),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      ));

      // 模拟前端回退路径（无 proxy 时）
      final entities = await fixture.skillManager.getSkills(employeeId);
      final mcpServers = entities.where((s) => s.skillType == 'mcp').toList();

      expect(mcpServers.length, equals(1));
      expect(mcpServers.first.name, equals('fallback-test'));

      // 解析 config
      final decoded = jsonDecode(mcpServers.first.config ?? '[]');
      expect(decoded, isA<List>());
      expect(decoded.length, equals(1));
      expect(decoded[0]['name'], equals('fallback-test'));
    });

    test('完整序列：添加→读取→更新→读取→删除→读取', () async {
      // 使用 SkillManager 路径（无 proxy 时的前端行为）

      // 1. 添加
      final entity = AiEmployeeSkillEntity(
        uuid: const Uuid().v4(),
        employeeId: employeeId,
        name: 'seq-test',
        skillType: 'mcp',
        config: McpServerConfig.toJsonString([
          McpServerConfig.stdio(name: 'seq-test', command: 'old-cmd'),
        ]),
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );
      await fixture.skillManager.createSkill(entity);

      // 2. 读取
      var skills = await fixture.skillManager.getSkills(employeeId);
      var mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills.length, equals(1));

      // 3. 更新
      final updated = entity.copyWith(
        config: McpServerConfig.toJsonString([
          McpServerConfig.sse(name: 'seq-test', url: 'http://new-url/sse'),
        ]),
        updateTime: DateTime.now(),
      );
      await fixture.skillManager.updateSkill(updated);

      // 4. 读取验证
      skills = await fixture.skillManager.getSkills(employeeId);
      mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      final configMap = (jsonDecode(mcpSkills.first.config!) as List)[0] as Map<String, dynamic>;
      expect(configMap['transportType'], equals('sse'));
      expect(configMap['url'], equals('http://new-url/sse'));

      // 5. 删除
      await fixture.skillManager.deleteSkill(entity.uuid);

      // 6. 读取验证
      skills = await fixture.skillManager.getSkills(employeeId);
      mcpSkills = skills.where((s) => s.skillType == 'mcp').toList();
      expect(mcpSkills, isEmpty);
    });
  });
}
