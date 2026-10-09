import 'skill.dart';

/// 技能工厂接口
///
/// SDK 用户可实现此接口，注册自定义的 Skill 类型。
/// 当 [SkillLifecycleManager] 遇到未知的 Skill 类型标识时，
/// 会查找匹配的 [SkillFactory] 来创建 Skill 实例。
///
/// 使用示例：
/// ```dart
/// class HttpApiSkillFactory implements SkillFactory {
///   @override
///   String get typeKey => 'http_api';
///
///   @override
///   Skill create(Map<String, dynamic> config) {
///     return HttpApiSkill(
///       id: config['id'] as String,
///       name: config['name'] as String,
///       baseUrl: config['baseUrl'] as String,
///     );
///   }
/// }
///
/// // 注册到 SDK
/// sdk.registerSkillFactory(HttpApiSkillFactory());
/// ```
abstract class SkillFactory {
  /// 该工厂能处理的 Skill 类型标识
  ///
  /// 用于匹配配置中的 `type` 字段，如 'http_api', 'graphql', 'websocket' 等。
  /// 必须全局唯一，重复注册会覆盖之前的工厂。
  String get typeKey;

  /// 从配置 Map 创建 Skill 实例
  ///
  /// [config] 包含 Skill 所需的全部配置信息，通常来自持久化存储或 SDK 用户传入。
  /// 工厂负责解析配置并返回正确初始化的 Skill 实例。
  Skill create(Map<String, dynamic> config);
}
