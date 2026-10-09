# 数据同步功能开发计划

> 基于项目代码分析，梳理各同步功能的完成状态、缺失环节和分阶段开发方案。

## 项目架构概述

```
同步数据流：
  AgentImpl → AgentEvent → DeviceAgentManager → LAN广播 → DeviceMessageHandler → CachedAgentProxy → Store/Cache
                                ↓ RPC                                       ↓
                          HostRpcMethods                              DataSyncManager
```

### 关键文件索引

| 层级 | 文件 | 职责 |
|------|------|------|
| Agent事件 | `agent/entity/agent_event.dart` | 事件类型定义 |
| Agent状态 | `agent/agent_state.dart` | 状态快照、权限/确认请求 |
| Agent代理 | `agent/client/agent_proxy.dart` | 本地/远程统一代理 |
| Agent远程操作 | `agent/client/agent_proxy_remote_ops.dart` | RPC远程操作封装 |
| 缓存代理 | `agent/client/cached_agent_proxy.dart` | 缓存层（主文件） |
| 缓存事件处理 | `agent/client/cached_proxy_event_handler.dart` | 事件处理mixin |
| 缓存消息同步 | `agent/client/cached_proxy_message_sync.dart` | 消息同步mixin |
| 设备Agent管理 | `device/impl/device_agent_manager.dart` | Agent生命周期+事件广播 |
| 设备Agent事件 | `device/impl/device_agent_manager_events.dart` | 事件广播/处理扩展 |
| 设备消息处理 | `device/impl/device_message_handler.dart` | LAN消息分发 |
| 数据同步管理 | `device/impl/data_sync_manager.dart` | 跨设备数据同步 |
| 通知管理 | `device/impl/device_notification_manager.dart` | 未读/已读/pending管理 |
| Host RPC | `host/host_rpc_methods.dart` | 服务端RPC方法 |
| LAN消息 | `entity/lan_message.dart` | LAN消息类型定义 |
| 设备状态 | `device/impl/device_state_holder.dart` | 设备级共享状态 |
| 设备客户端 | `device/device_client.dart` | 设备级统一入口 |

---

## 功能状态总览

| # | 功能 | 路径1 (event>store) | 路径2 (query>store) | 存储位置 | 优先级 |
|---|------|:---:|:---:|------|:---:|
| 1 | 会话列表同步(session) | ✅ 已完成 | ✅ 已完成 | SQLite | P0 |
| 2 | 会话列表状态同步(summary) | ✅ 已完成 | ✅ 已完成 | SQLite | P0 |
| 3 | 员工信息同步 | ✅ 已完成 | ✅ 已完成 | SQLite | P0 |
| 4 | 会话窗口消息同步 | ✅ 已完成 | ✅ 已完成 | SQLite | P0 |
| 5 | 会话窗口配置同步 | ❌ 未完成 | ❌ 未完成 | SQLite | P1 |
| 6 | 会话窗口状态同步 | ⚠️ 部分完成 | ⚠️ 部分完成 | 内存 | P1 |
| 7 | 会话窗口spec数据同步 | ❌ 未完成 | ❌ 未完成 | SQLite | P2 |
| 8 | 会话窗口todo数据同步 | ❌ 未完成 | ❌ 未完成 | SQLite | P2 |

---

## 阶段一：会话窗口配置同步（P1）

### 1.1 功能分析

**目标**：project配置（项目id、工作路径、项目名称）和model配置（AI的api参数）在多设备间同步。

**当前状态**：
- `AgentEventType.configChanged` 事件已定义，LAN广播通道已建立（`LanMessageType.agentConfigChanged`）
- `DeviceMessageHandler._handleAgentEvent()` 已处理 `configChanged` 事件，但**仅透传给UI**，未写入本地store
- `CachedAgentProxy._handleAgentEvent()` 对 `configChanged` 仅注释 `// 数据变更事件：透传给上层`
- 无RPC方法支持配置的跨设备查询同步
- 无本地持久化存储用于远程设备的配置数据

**关键问题**：
- 配置数据存储在 `AiEmployeeSessionEntity.config[deviceId]`（Map结构，key=deviceId）
- 本地设备的配置通过 `setProvider()`/`setProject()` 写入 Agent 内存
- 远程设备的配置变更无法持久化到本地 DB

### 1.2 实现方案

#### 1.2.1 路径1：event(lan广播+event) > update store

**实现步骤**：

1. **扩展 `AgentEvent.data` 的配置变更数据**
   - 文件：`agent/impl/agent_impl.dart`（或 `agent/impl/agent_impl_messaging.dart`）
   - 在 `setProvider()`/`setProject()`/`setSkills()`/`setMcpConfigs()` 时触发 `configChanged` 事件
   - 事件 data 携带完整配置数据：`{providerConfig, projectData, skills, mcpConfigs}`
   - **当前状态**：需检查 AgentImpl 是否已触发此事件

2. **CachedAgentProxy 处理 configChanged 事件**
   - 文件：`agent/client/cached_proxy_event_handler.dart`
   - 在 `_handleAgentEvent` 的 `configChanged` case 中：
     - 解析事件 data 中的 providerConfig/projectData
     - 更新 `_proxy` 的 `_remoteCache`
     - 通知 UI 刷新

3. **DeviceMessageHandler 处理 LAN 广播的 configChanged**
   - 文件：`device/impl/device_message_handler.dart`
   - 在 `_handleAgentEvent()` 中对 `configChanged` 事件：
     - 解析 providerConfig/projectData
     - 更新 `SessionManager` 中对应 employeeId 的设备配置
     - 更新 `SessionSummaryStore` 中的相关缓存

#### 1.2.2 路径2：query > update store

**实现步骤**：

1. **CachedAgentProxy 初始化时同步配置**
   - 文件：`agent/client/cached_proxy_message_sync.dart`
   - 在 `_syncRemoteStateAndPermission()` 中已有部分实现：
     - ✅ 已同步 `providerConfig`
     - ✅ 已同步 `projectUuid`
     - ✅ 已同步 `skillsConfig`
     - ✅ 已同步 `mcpConfigs`
   - **需要增加**：将同步到的配置写入本地 SessionStore

2. **Host RPC 增加配置查询方法**
   - 文件：`host/host_rpc_methods.dart`
   - 已有 `methodUpdateDeviceConfig`，但缺少按 deviceId 查询配置的方法
   - 新增 `hostGetDeviceConfig` 方法

### 1.3 涉及文件清单

| 文件 | 修改内容 |
|------|----------|
| `agent/client/cached_proxy_event_handler.dart` | configChanged 事件处理：更新本地配置缓存 |
| `agent/client/cached_proxy_message_sync.dart` | 同步配置后写入 SessionStore |
| `device/impl/device_message_handler.dart` | LAN configChanged 事件：更新 Session 配置 |
| `host/host_rpc_methods.dart` | 新增 hostGetDeviceConfig RPC 方法 |
| `agent/impl/agent_impl.dart` | 确认 configChanged 事件触发及数据完整性 |

---

## 阶段二：会话窗口状态同步（P1）

### 2.1 功能分析

**目标**：以下状态在多设备间实时同步（仅存内存，不持久化）：
- 聊天状态：思考中、回复中、空闲
- 设备状态：在线、离线
- 权限申请
- confirm请求
- 处理中消息id
- 处理中functionCallId
- 队列中消息id

**当前状态**：
- ✅ 聊天状态（agentStatusChanged）：LAN广播已实现，`_handleAgentEvent` 中已处理
- ✅ 设备状态（在线/离线）：通过 `DeviceRegistry` + `EmployeeOnlineTracker` 已实现
- ✅ 权限申请/confirm请求：通过 `SessionSummaryEntity.pendingPermission/pendingConfirm` 已实现持久化+同步
- ⚠️ 处理中消息id/队列中消息id：`AgentStateSnapshot` 中有字段但未在 LAN 广播中完整同步
- ❌ 处理中functionCallId：未同步
- ⚠️ CachedAgentProxy 的内存缓存不完整：仅缓存 `_pendingPermissionRequests` 和 `_pendingConfirmRequests`

### 2.2 实现方案

#### 2.2.1 路径1：event(lan广播+event) > update cache(proxy 内存)

**实现步骤**：

1. **扩展 CachedAgentProxy 状态缓存**
   - 文件：`agent/client/cached_agent_proxy.dart`
   - 新增内存缓存字段：
     ```dart
     String? _currentProcessingMessageId;  // 处理中消息id
     List<String> _queuedMessageIds = [];   // 队列中消息id
     List<String> _callingToolIds = [];     // 处理中functionCallId
     String? _thinkingContent;              // 思考内容
     ```
   - 暴露只读 getter 供 UI 读取

2. **处理 agentStatusChanged 事件更新缓存**
   - 文件：`agent/client/cached_proxy_event_handler.dart`
   - 在 `_handleAgentStatusChanged` 中：
     - 解析 `currentProcessingMessageId`、`queuedMessageIds`
     - 更新 CachedAgentProxy 的内存缓存
     - 通知 UI 刷新

3. **处理 toolCallStart/toolCallResult 事件更新缓存**
   - 文件：`agent/client/cached_proxy_event_handler.dart`
   - 在 `_handleToolEvent` 中：
     - 维护 `_callingToolIds` 列表（start时添加，result时移除）

4. **LAN 广播状态快照增强**
   - 文件：`device/impl/device_agent_manager_events.dart`
   - 在 `broadcastAgentEvent` 中对 `agentStatusChanged` 事件：
     - 确保完整 `AgentStateSnapshot` 数据被广播（含 currentProcessingMessageId、queuedMessageIds）

5. **DeviceMessageHandler 处理远程状态**
   - 文件：`device/impl/device_message_handler.dart`
   - 在 `_handleAgentEvent()` 的 `agentStatusChanged` case 中：
     - 更新本地 `CachedAgentProxy` 的内存缓存

#### 2.2.2 路径2：query > update cache(proxy 内存)

**实现步骤**：

1. **CachedAgentProxy 初始化时查询状态**
   - 文件：`agent/client/cached_proxy_message_sync.dart`
   - 在 `_syncRemoteStateAndPermission()` 中：
     - ✅ 已查询 `getStateSnapshotAsync()`
     - **需要增加**：将 snapshot 中的字段写入内存缓存
     - **需要增加**：查询 `getCallingToolIdsAsync()` 并缓存

### 2.3 涉及文件清单

| 文件 | 修改内容 |
|------|----------|
| `agent/client/cached_agent_proxy.dart` | 新增状态缓存字段和 getter |
| `agent/client/cached_proxy_event_handler.dart` | agentStatusChanged/toolCall 事件更新内存缓存 |
| `agent/client/cached_proxy_message_sync.dart` | 初始化同步时写入内存缓存 |
| `device/impl/device_agent_manager_events.dart` | 确保广播完整状态快照 |
| `device/impl/device_message_handler.dart` | 远程状态事件更新 CachedAgentProxy 缓存 |

---

## 阶段三：会话窗口 Spec 数据同步（P2）

### 3.1 功能分析

**目标**：spec 数据（`SpecItemEntity`）在多设备间同步，支持增删改操作。

**当前状态**：
- ✅ `AgentEventType.specChanged` 事件已定义
- ✅ `LanMessageType.agentSpecChanged` LAN消息类型已定义
- ✅ `DeviceMessageHandler._handleAgentEvent()` 已路由 `specChanged` 事件
- ✅ `CachedAgentProxy` 有完整的 spec RPC 方法（getActiveSpecs, updateSpecStatus 等）
- ❌ LAN 广播 `specChanged` 时**不携带完整 spec 数据**，仅透传事件
- ❌ `DeviceMessageHandler` 收到远程 `specChanged` 后**未写入本地 SpecStore**
- ❌ 无 RPC 方法支持 spec 数据的跨设备查询同步
- ❌ `SpecStore` 无 `upsertFromRemote` 方法（需要基于 updateTime 的 merge）

### 3.2 实现方案

#### 3.2.1 路径1：event(lan广播+event) > update store

**实现步骤**：

1. **AgentImpl 触发 specChanged 事件时携带完整数据**
   - 文件：`agent/impl/agent_impl.dart`（或 spec 相关操作的位置）
   - 确保 spec 变更事件 data 中包含完整的 `SpecItemEntity.toMap()` 数据
   - 包含 `specId`、`action`（created/updated/deleted）、完整 spec 数据

2. **DeviceAgentManager 广播 specChanged 时附加完整数据**
   - 文件：`device/impl/device_agent_manager_events.dart`
   - 在 `broadcastAgentEvent` 中对 `specChanged` 事件：
     - 从 `SpecStore` 查询完整 spec 数据并附加到广播 data 中

3. **DeviceMessageHandler 处理远程 specChanged**
   - 文件：`device/impl/device_message_handler.dart`
   - 在 `_handleAgentEvent()` 中新增 `specChanged` 处理：
     - 解析 spec 数据
     - 调用 `SpecStore.upsertFromRemote()` 写入本地 DB
     - 通知 UI 刷新

4. **SpecStore 新增 upsertFromRemote 方法**
   - 文件：`persistence/stores/spec_store.dart`
   - 实现基于 `updateTime` 的 merge 逻辑：
     - 本地不存在 → INSERT
     - 远程 updateTime > 本地 updateTime → UPDATE
     - 软删除合并：`deleted = deleteTime1 > deleteTime2 ? deleted1 : deleted2`

5. **CachedAgentProxy 处理 specChanged 事件**
   - 文件：`agent/client/cached_proxy_event_handler.dart`
   - 在 `configChanged` 同级处理 `specChanged`：
     - 通知 UI 刷新 spec 列表

#### 3.2.2 路径2：query > update store

**实现步骤**：

1. **Host RPC 新增 spec 同步方法**
   - 文件：`host/host_rpc_methods.dart`
   - 新增 `hostGetSpecs` 方法：查询指定 employeeId 的所有 spec 项
   - 新增 `hostSyncSpecs` 方法：接收远程 spec 列表并 merge 写入

2. **DataSyncManager 新增 spec 同步方法**
   - 文件：`device/impl/data_sync_manager.dart`
   - 新增 `syncSpecsFromDevices()` 方法
   - 新增 `broadcastSpecToAllDevices()` 方法

3. **CachedAgentProxy 初始化时同步 spec**
   - 文件：`agent/client/cached_proxy_message_sync.dart`
   - 在 `syncFromRemote()` 中增加 spec 数据同步步骤

### 3.3 涉及文件清单

| 文件 | 修改内容 |
|------|----------|
| `agent/impl/agent_impl.dart` | 确保 specChanged 事件携带完整数据 |
| `agent/client/cached_proxy_event_handler.dart` | specChanged 事件处理 |
| `device/impl/device_agent_manager_events.dart` | 广播 specChanged 附加完整数据 |
| `device/impl/device_message_handler.dart` | 远程 specChanged 写入 SpecStore |
| `device/impl/data_sync_manager.dart` | 新增 spec 同步方法 |
| `persistence/stores/spec_store.dart` | 新增 upsertFromRemote/merge 方法 |
| `host/host_rpc_methods.dart` | 新增 hostGetSpecs/hostSyncSpecs RPC 方法 |
| `agent/client/cached_proxy_message_sync.dart` | 初始化时同步 spec |
| `entity/lan_message.dart` | 无需修改（已有 agentSpecChanged） |

---

## 阶段四：会话窗口 Todo 数据同步（P2）

### 4.1 功能分析

**目标**：todo 数据（`TodoTopicEntity` + `TodoTaskItemEntity`）在多设备间同步。

**当前状态**：
- ✅ `AgentEventType.todoTopicChanged` / `AgentEventType.todoTaskItemChanged` 已定义
- ✅ `LanMessageType.agentTodoChanged` LAN消息类型已定义
- ✅ `DeviceMessageHandler._handleAgentEvent()` 已路由 todo 事件
- ✅ `CachedAgentProxy` 有完整的 todo RPC 方法
- ❌ LAN 广播 todo 事件时**不携带完整数据**
- ❌ `DeviceMessageHandler` 收到远程 todo 事件后**未写入本地 TodoStore**
- ❌ 无 RPC 方法支持 todo 数据的跨设备查询同步
- ❌ `TodoStore` 无 `upsertFromRemote` 方法

### 4.2 实现方案

#### 4.2.1 路径1：event(lan广播+event) > update store

**实现步骤**：

1. **AgentImpl 触发 todo 事件时携带完整数据**
   - 文件：`agent/impl/agent_impl.dart`（或 todo 相关操作的位置）
   - 确保 todoTopicChanged 事件包含完整 `TodoTopicEntity.toMap()` 数据
   - 确保 todoTaskItemChanged 事件包含完整 `TodoTaskItemEntity.toMap()` 数据

2. **DeviceAgentManager 广播 todo 事件时附加完整数据**
   - 文件：`device/impl/device_agent_manager_events.dart`
   - 在 `broadcastAgentEvent` 中对 `todoTopicChanged`/`todoTaskItemChanged` 事件：
     - 从 `TodoStore` 查询完整数据并附加到广播 data 中

3. **DeviceMessageHandler 处理远程 todo 事件**
   - 文件：`device/impl/device_message_handler.dart`
   - 在 `_handleAgentEvent()` 中新增 `todoTopicChanged`/`todoTaskItemChanged` 处理：
     - 解析 todo 数据
     - 调用 `TodoStore.upsertTopicFromRemote()` / `TodoStore.upsertTaskItemFromRemote()` 写入本地 DB
     - 通知 UI 刷新

4. **TodoStore 新增 upsertFromRemote 方法**
   - 文件：`persistence/stores/todo_store.dart`
   - 实现 `upsertTopicFromRemote(TodoTopicEntity)` 方法
   - 实现 `upsertTaskItemFromRemote(TodoTaskItemEntity)` 方法
   - 基于 `updateTime` 的 merge 逻辑

5. **CachedAgentProxy 处理 todo 事件**
   - 文件：`agent/client/cached_proxy_event_handler.dart`
   - 处理 `todoTopicChanged`/`todoTaskItemChanged`：
     - 通知 UI 刷新 todo 列表

#### 4.2.2 路径2：query > update store

**实现步骤**：

1. **Host RPC 新增 todo 同步方法**
   - 文件：`host/host_rpc_methods.dart`
   - 新增 `hostGetTodos` 方法：查询指定 employeeId 的所有 todo 数据
   - 新增 `hostSyncTodos` 方法：接收远程 todo 列表并 merge 写入

2. **DataSyncManager 新增 todo 同步方法**
   - 文件：`device/impl/data_sync_manager.dart`
   - 新增 `syncTodosFromDevices()` 方法
   - 新增 `broadcastTodoToAllDevices()` 方法

3. **CachedAgentProxy 初始化时同步 todo**
   - 文件：`agent/client/cached_proxy_message_sync.dart`
   - 在 `syncFromRemote()` 中增加 todo 数据同步步骤

### 4.3 涉及文件清单

| 文件 | 修改内容 |
|------|----------|
| `agent/impl/agent_impl.dart` | 确保 todo 事件携带完整数据 |
| `agent/client/cached_proxy_event_handler.dart` | todo 事件处理 |
| `device/impl/device_agent_manager_events.dart` | 广播 todo 附加完整数据 |
| `device/impl/device_message_handler.dart` | 远程 todo 写入 TodoStore |
| `device/impl/data_sync_manager.dart` | 新增 todo 同步方法 |
| `persistence/stores/todo_store.dart` | 新增 upsertFromRemote/merge 方法 |
| `host/host_rpc_methods.dart` | 新增 hostGetTodos/hostSyncTodos RPC 方法 |
| `agent/client/cached_proxy_message_sync.dart` | 初始化时同步 todo |
| `persistence/entities/todo_task_item_entity.dart` | 无需修改（已有完整 toMap/fromMap） |

---

## 通用基础设施（跨阶段复用）

### A. 通用 merge 工具方法

以下 merge 逻辑在多个 Store 中重复使用，建议抽取为通用工具：

- 文件：新建 `persistence/store_merge_util.dart`（或放在 `persistence/utils/` 下）

```dart
/// 通用 merge 逻辑
/// 返回 (shouldUpdate, mergedDeleted, mergedDeleteTime)
(bool, int, DateTime?) mergeDeleteState({
  required DateTime? localDeleteTime,
  required int localDeleted,
  required DateTime? remoteDeleteTime,
  required int remoteDeleted,
}) {
  // 软删除合并：deleteTime 取较新值决定 deleted
  if (localDeleteTime == null && remoteDeleteTime == null) {
    return (false, 0, null);
  }
  if (localDeleteTime == null) return (true, remoteDeleted, remoteDeleteTime);
  if (remoteDeleteTime == null) return (false, localDeleted, localDeleteTime);
  if (remoteDeleteTime.isAfter(localDeleteTime)) {
    return (true, remoteDeleted, remoteDeleteTime);
  }
  return (false, localDeleted, localDeleteTime);
}
```

**涉及文件**：
- `persistence/stores/spec_store.dart` — 使用 merge 工具
- `persistence/stores/todo_store.dart` — 使用 merge 工具
- `device/impl/data_sync_manager.dart` — 已有类似逻辑，可重构复用
- `host/host_rpc_methods.dart` — 已有类似逻辑，可重构复用

### B. fromDeviceId 过滤机制

**注意事项**中提到：event 有 2 条路线收到，需要根据 fromDeviceId 判断是否需要同步。

**当前实现**：
- `DeviceMessageHandler._handleSessionSummaryChanged()` 中已有 `if (fromDeviceId == _deviceId) return;` 过滤
- `DeviceMessageHandler._handleAgentEvent()` 中对部分事件已有 `isLocal` 判断
- `CachedAgentProxy._handleAgentEvent()` 中 `employeeId != null && employeeId != _employeeId` 过滤

**需要统一**：
- 所有 LAN 广播事件处理都应检查 `fromDeviceId != _deviceId`（跳过自己发出的广播）
- 本地 event（从 AgentImpl 直接发出）不需要过滤，因为是本设备的操作

---

## 开发优先级建议

```
阶段一（配置同步）→ 阶段二（状态同步）→ 通用基础设施重构 → 阶段三（Spec同步）→ 阶段四（Todo同步）
```

**理由**：
1. 阶段一和二影响核心用户体验（配置不同步导致功能异常，状态不同步导致UI错乱）
2. 通用基础设施重构为阶段三、四提供可复用的 merge 工具
3. 阶段三和四结构相似，可并行开发，且优先级较低

---

## 验收标准

### 通用验收标准
- [ ] update store 对本地数据进行 merge（基于 updateTime 取较新值）
- [ ] 软删除合并：`deleted = deleteTime1 > deleteTime2 ? deleted1 : deleted2`
- [ ] event 根据 fromDeviceId 判断是否需要同步（跳过自己发出的广播）
- [ ] LAN 广播携带完整数据（不仅仅是事件通知）
- [ ] 断线重连后 query 路径能补齐缺失数据

### 各功能验收标准
- [ ] 配置同步：A设备修改 provider/project 后，B设备实时更新
- [ ] 状态同步：A设备 Agent 处理中，B设备能看到处理中状态和消息id
- [ ] Spec同步：A设备创建/修改 spec，B设备能看到变更
- [ ] Todo同步：A设备创建/修改 todo，B设备能看到变更
