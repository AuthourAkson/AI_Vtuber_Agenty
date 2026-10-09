# 系统提示词指南 (System Prompt Guide)

## 概述

系统提示词由固定前缀 + 用户自定义内容 + 项目信息自动组装而成。

**涉及文件：**
- `lib/src/agent/adapter/llm_chat_adapter.dart` — 主 Agent 的系统提示词组装（含固定前缀）
- `lib/src/agent/adapter/sub_agent_llm_chat_adapter.dart` — 子 Agent 的系统提示词组装
- `lib/src/persistence/entities/employee_entity.dart` — systemPrompt 字段定义

## 系统提示词组装流程

```
最终系统提示词 = [固定前缀：任务分级执行流程] + [用户自定义 systemPrompt] + [项目信息（自动注入）] + [补充信息（自动注入）]
```

1. **固定前缀**：`_fixedSystemPromptPrefix` 常量，定义了任务分级执行流程（代码内置，不可配置）
2. **用户自定义 systemPrompt**：来自 `AiEmployeeEntity.systemPrompt`，通过数据库持久化
3. **项目信息**：当绑定项目时自动注入（项目名、项目ID、工作路径）
4. **补充信息**：通过 `_context['additionalInfo']` 传入

## 固定前缀：任务分级执行流程

在 `llm_chat_adapter.dart` 中通过 `_fixedSystemPromptPrefix` 常量定义，所有主 Agent 都会自动携带此前缀：

### 1. 小型任务 → 直接执行
- **特征**：单文件修改、简单查询、格式转换等可在 1-3 轮工具调用内完成
- **做法**：主 Agent 直接使用工具完成，无需创建待办或规格文档

### 2. 中型任务 → 待办驱动 + 子 Agent 执行
- **特征**：涉及多文件修改、需要多步骤完成、有明确预期
- **做法**：
  1. 使用 `todo_manage` 创建待办列表，将任务拆分为可独立执行的子项
  2. 对每个待办项，使用 `spawn_sub_agent` 创建子 Agent 执行
  3. 子 Agent 返回结果后，主 Agent 验收代码质量和需求满足度
  4. 验收通过则标记待办为 completed，不通过则修正后重新执行
  5. 所有待办完成后向用户汇报整体结果

### 3. 复杂任务 → Spec 驱动 + 分阶段执行
- **特征**：需求不够明确、涉及架构调整、需要多个中型任务协作
- **做法**：
  1. 提示用户创建 Spec，使用 `spec_manage` 记录需求规格
  2. 与用户反复讨论、修正 Spec，直到需求完全对齐
  3. 根据最终 Spec 拆分为多个中型任务，使用 `todo_manage` 创建待办列表
  4. 按照中型任务的流程逐个执行
  5. 所有待办完成后对照 Spec 做最终检查

## 注意事项

1. **子 Agent 无法递归**：子 Agent 不能再创建子 Agent（`spawn_sub_agent` 对子 Agent 不可用），中型任务的拆分粒度应确保每个子项可由子 Agent 独立完成。

2. **待办和 Spec 持久化**：`todo_manage` 和 `spec_manage` 的数据持久化到 SQLite，跨轮次可用。

3. **子 Agent 默认工具集**：子 Agent 默认可用的工具为只读工具（file_read, file_list, file_search, content_search, file_info, command_execute, bg_command, code_symbols），如需写操作需在 spawn_sub_agent 时指定。

4. **固定前缀不可配置**：任务分级流程前缀是代码内置的，所有 Agent 实例都会自动携带。用户自定义的 systemPrompt 会追加在固定前缀之后。
