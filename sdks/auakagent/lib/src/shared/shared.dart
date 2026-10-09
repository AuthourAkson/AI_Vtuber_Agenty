/// 共享层 —— 统一消息模型 + 映射器
///
/// 所有模块通过此入口使用 ChatMessage 及其相关类型，
/// 不再直接引用 agent/entity 或 persistence/entities 中的旧模型。
library;

export 'chat_message.dart';
export 'message_record.dart';
export 'llm_message_mapper.dart';
export 'message_sequence_report.dart';
