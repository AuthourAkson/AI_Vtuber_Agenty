import 'dart:async';

import '../utils/logger.dart';
import 'skill.dart';
import 'skill_context.dart';
import 'skill_factory.dart';

/// 技能变更事件
class SkillEvent {
  /// 技能ID
  final String skillId;

  /// 事件类型：added | removed | reloaded | error
  final String type;

  /// 附加数据
  final dynamic data;

  SkillEvent({required this.skillId, required this.type, this.data});
}

/// 技能生命周期管理器（运行时）
///
/// 统一管理三种 Skill 的加载、激活、卸载。
/// 核心职责：将 Skill 产出的 AgentTool 注册/注销到 ToolRegistry。
///
/// 与 service/skill_manager.dart 中的 SkillManager（持久化 CRUD）职责分离：
/// - SkillManager / SkillManagerImpl：数据库 CRUD、持久化
/// - SkillLifecycleManager（此类）：运行时生命周期管理、工具注册/注销
class SkillLifecycleManager {
  static final _log = Logger('SkillLifecycle');

  final SkillContext _context;
  final Map<String, Skill> _skills = {};
  final Map<String, SkillFactory> _skillFactories = {};
  final _eventController = StreamController<SkillEvent>.broadcast(sync: true);

  SkillLifecycleManager(this._context);

  /// 加载并激活技能
  Future<void> loadSkill(Skill skill) async {
    try {
      _log.debug('开始加载技能: id=${skill.id}, name=${skill.name}, type=${skill.runtimeType}');

      await skill.initialize();
      _log.debug('技能初始化完成: ${skill.name}, tools=[${skill.tools.map((t) => t.name).join(', ')}]');

      await skill.activate();
      _log.debug('技能激活完成: ${skill.name}');

      for (final tool in skill.tools) {
        final existed = _context.toolRegistry.contains(tool.name);
        if (existed) {
          _context.toolRegistry.registerOrReplaceTool(tool);
          _log.debug('工具已替换: ${tool.name}');
        } else {
          _context.toolRegistry.registerTool(tool);
          _log.debug('工具已注册: ${tool.name}');
        }
      }

      _skills[skill.id] = skill;
      _eventController.add(SkillEvent(
        skillId: skill.id,
        type: 'added',
        data: {'name': skill.name, 'toolCount': skill.tools.length},
      ));
      _log.debug('技能加载成功: ${skill.name}, 共注册 ${skill.tools.length} 个工具');
    } catch (e, st) {
      _context.logger('error', '技能加载失败: ${skill.name}, $e\n$st');
      _eventController.add(SkillEvent(
        skillId: skill.id, type: 'error', data: {'error': e.toString()},
      ));
      rethrow;
    }
  }

  /// 卸载技能
  Future<void> unloadSkill(String skillId) async {
    final skill = _skills.remove(skillId);
    if (skill == null) return;

    for (final tool in skill.tools) {
      _context.toolRegistry.unregisterTool(tool.name);
    }
    await skill.deactivate();
    await skill.dispose();

    _eventController.add(SkillEvent(
      skillId: skillId, type: 'removed',
    ));
  }

  /// 重新加载技能
  Future<void> reloadSkill(String skillId) async {
    final skill = _skills[skillId];
    if (skill == null) return;

    // 注销旧工具
    for (final tool in skill.tools) {
      _context.toolRegistry.unregisterTool(tool.name);
    }
    await skill.deactivate();
    await skill.dispose();

    // 重新初始化
    await skill.initialize();
    await skill.activate();

    for (final tool in skill.tools) {
      _context.toolRegistry.registerOrReplaceTool(tool);
    }

    _eventController.add(SkillEvent(skillId: skillId, type: 'reloaded'));
  }

  /// 获取所有已加载技能
  List<Skill> get skills => _skills.values.toList();

  /// 根据ID获取技能
  Skill? getSkill(String id) => _skills[id];

  /// 技能变更事件流
  Stream<SkillEvent> get onEvent => _eventController.stream;

  /// 释放所有技能资源
  Future<void> dispose() async {
    for (final skill in _skills.values) {
      try {
        await skill.dispose();
      } catch (e) {
        _log.warn('释放技能资源失败: ${skill.id}, $e');
      }
    }
    _skills.clear();
    _skillFactories.clear();
    await _eventController.close();
  }

  // ===== SkillFactory 支持 =====

  /// 注册自定义 Skill 工厂
  ///
  /// 允许 SDK 用户注册自定义类型的 Skill 创建器。
  /// 当遇到 [typeKey] 对应的 Skill 配置时，会使用此工厂创建实例。
  void registerSkillFactory(SkillFactory factory) {
    _skillFactories[factory.typeKey] = factory;
    _log.debug('注册 SkillFactory: typeKey=${factory.typeKey}');
  }

  /// 注销自定义 Skill 工厂
  void unregisterSkillFactory(String typeKey) {
    _skillFactories.remove(typeKey);
  }

  /// 根据类型标识查找已注册的 SkillFactory
  SkillFactory? getSkillFactory(String typeKey) => _skillFactories[typeKey];

  /// 获取所有已注册的 SkillFactory
  List<SkillFactory> get skillFactories => _skillFactories.values.toList();

  /// 通过工厂创建并加载自定义 Skill
  ///
  /// [typeKey] 工厂类型标识，必须在 [registerSkillFactory] 中已注册。
  /// [config] 传递给工厂 [SkillFactory.create] 方法的配置数据。
  Future<void> loadSkillFromFactory(String typeKey, Map<String, dynamic> config) async {
    final factory = _skillFactories[typeKey];
    if (factory == null) {
      throw ArgumentError('未找到 typeKey="$typeKey" 对应的 SkillFactory，'
          '请先通过 registerSkillFactory() 注册');
    }
    final skill = factory.create(config);
    await loadSkill(skill);
  }
}
