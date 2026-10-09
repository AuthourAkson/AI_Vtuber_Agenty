# Employee Session Summary 系统完善与测试规划

## 1. 系统概述

Session Summary 是员工会话窗口数据的摘要缓存层，以 `employeeId + deviceId` 为联合主键，
提供 O(1) 的未读计数和最新消息查询能力。通过 LAN RPC 实现跨设备同步。

### 1.1 核心设计

```
┌─────────────────────────────────────────────────────────────────┐
│                        DeviceClient                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │ DeviceNotification│  │ DeviceAgent      │  │ DataSync      │  │
│  │ Manager          │  │ Manager (Events) │  │ Manager       │  │
│  │ - 会话打开状态    │  │ - Agent事件监听   │  │ - RPC同步     │  │
│  │ - 最新消息缓存    │  │ - 摘要广播       │  │ - 防抖合并    │  │
│  │ - 已读管理       │  │                  │  │               │  │
│  └────────┬─────────┘  └────────┬─────────┘  └───────┬───────┘  │
│           │                     │                     │          │
│  ┌────────▼─────────────────────▼─────────────────────▼───────┐  │
│  │              AgentNotificationHub (内存层)                   │  │
│  │  - 未读消息索引: employeeId -> { msgId -> event }           │  │
│  │  - 未读计数: employeeId -> count (总 + 按设备)              │  │
│  │  - 事件广播: Stream<AgentNotificationEvent>                 │  │
│  └─────────────────────────┬───────────────────────────────────┘  │
│                            │                                      │
│  ┌─────────────────────────▼───────────────────────────────────┐  │
│  │            SessionSummaryStore (持久层)                      │  │
│  │  - SQLite session_summary 表                                │  │
│  │  - UPSERT 原子操作, O(1) 读写                               │  │
│  │  - PK: (employee_id, device_id)                             │  │
│  └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
         │ LAN Broadcast (agentSessionSummaryChanged)    │ RPC
         │                                                │
┌────────▼────────────────────────────────────────────────────────┐
│                      Remote Device                               │
│  DeviceMessageHandler._handleSessionSummaryChanged()            │
│  → upsertFromRemote() → adjustUnreadCountFromDb()              │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 数据模型

**session_summary 表** (PK: employee_id + device_id)

| 字段 | 类型 | 说明 | 状态 |
|------|------|------|------|
| employee_id | TEXT PK | 员工ID | ✅ 已有 |
| device_id | TEXT PK | 设备ID（数据来源设备） | ✅ 已有 |
| unread_count | INTEGER | 未读消息数 | ✅ 已有 |
| last_msg_id | TEXT | 最新消息ID | ✅ 已有 |
| last_msg_role | TEXT | 最新消息角色 | ✅ 已有 |
| last_msg_content | TEXT | 最新消息内容（截断200字） | ✅ 已有 |
| last_msg_time | INTEGER | 最新消息时间戳 | ✅ 已有 |
| last_msg_seq | INTEGER | 最新消息序号 | ✅ 已有 |
| update_time | INTEGER | 更新时间 | ✅ 已有 |
| pending_permission | TEXT | 待处理权限请求(JSON) | 🆕 待扩展 |
| pending_confirm | TEXT | 待处理确认请求(JSON) | 🆕 待扩展 |
| pending_permission_time | INTEGER | 权限请求时间 | 🆕 待扩展 |
| pending_confirm_time | INTEGER | 确认请求时间 | 🆕 待扩展 |

### 1.3 关键代码文件

| 文件 | 职责 | 行数 |
|------|------|------|
| `session_summary_entity.dart` | 摘要实体定义 | ~70 |
| `session_summary_schema.dart` | DB Schema | ~35 |
| `session_summary_store.dart` | 持久层 CRUD | ~310 |
| `device_notification_manager.dart` | 通知与已读管理 | ~340 |
| `agent_notification_hub.dart` | 内存层事件广播 | ~400 |
| `device_agent_manager_events.dart` | Agent事件→摘要广播 | ~300 |
| `device_message_handler.dart` | LAN消息→摘要处理 | ~580 |
| `data_sync_manager.dart` | 跨设备RPC同步 | ~350 |
| `device_client.dart` | 统一入口 | ~680 |

---

## 2. 现有测试覆盖分析

### 2.1 已覆盖（session_summary_store_test.dart）

| 测试组 | 测试数 | 覆盖方法 |
|--------|--------|----------|
| upsertFromRemote 合并策略 | 5 | upsertFromRemote |
| onMessageAdded | 4 | onMessageAdded |
| getAllSummaries 过滤 | 2 | getAllSummaries |
| markAsRead | 1 | markAsRead |
| 综合同步合并 | 2 | upsertFromRemote + onMessageAdded |

### 2.2 未覆盖方法

| 方法 | 说明 | 优先级 |
|------|------|--------|
| `markAsReadBySeq` | 基于 seq 批量标记已读 | P0 |
| `onMessageSoftDeleted` | 软删除后摘要回退 | P0 |
| `rebuildSummary` / `rebuildAllSummaries` | 从 messages 表重建 | P1 |
| `onMessagesAdded` | 批量写入事务一致性 | P1 |
| `deleteSummary` | 删除摘要 | P1 |
| `getUnreadEmployeeIds` | 未读员工列表 | P2 |
| `markAllAsRead` | 全局标记已读 | P2 |

### 2.3 未覆盖功能模块

| 模块 | 说明 | 优先级 |
|------|------|--------|
| DeviceNotificationManager | 会话打开/已读/缓存管理 | P0 |
| AgentNotificationHub | 未读追踪/事件广播 | P0 |
| DataSyncManager 摘要同步 | _doSyncSessionSummariesFromDevices | P1 |
| DeviceMessageHandler 摘要处理 | _handleSessionSummaryChanged | P1 |
| DeviceAgentManagerEvents 摘要广播 | _broadcastSessionSummary | P1 |
| DeviceClient 摘要 API | getUnreadCount/restoreUnreadStatus | P2 |

---

## 3. 阶段性任务规划

### Phase 1: SessionSummaryStore 单元测试补全 [P0]

**目标**: 补全底层 SQL 操作的测试覆盖

**测试用例清单**:

```
group('markAsReadBySeq') {
  test('按 seq 阈值标记已读，减少 unread_count')
  test('seq 阈值外的不受影响')
  test('无符合条件的消息时不操作')
}

group('onMessageSoftDeleted') {
  test('删除未读消息 → unread_count - 1')
  test('删除已读消息 → unread_count 不变')
  test('删除最新消息 → 回退到前一条消息')
  test('删除非最新消息 → latest 不变')
  test('并发保护：last_msg_id 匹配才回退')
}

group('rebuildSummary') {
  test('从 messages 表重建单个摘要')
  test('无消息时不创建摘要')
  test('重建覆盖现有错误数据')
}

group('rebuildAllSummaries') {
  test('批量重建所有摘要')
  test('按 deviceId 过滤重建')
}

group('onMessagesAdded') {
  test('批量写入事务一致性（全部成功或全部回滚）')
  test('空列表不操作')
}

group('deleteSummary') {
  test('删除指定摘要')
  test('删除不存在的摘要无副作用')
}

group('getUnreadEmployeeIds') {
  test('返回有未读的员工ID列表')
  test('按 deviceId 过滤')
}

group('边界条件') {
  test('空 DB 查询返回空/0')
  test('重复 upsert 幂等')
  test('content 超过 200 字截断')
  test('lastMsgTime 为 null 时的合并')
}
```

---

### Phase 2: Entity 扩展 - pending 字段 [P0]

**目标**: 将权限请求和确认请求持久化到 session_summary 表

**Schema 变更** (v14_migration.dart):
```sql
ALTER TABLE session_summary ADD COLUMN pending_permission TEXT;
ALTER TABLE session_summary ADD COLUMN pending_confirm TEXT;
ALTER TABLE session_summary ADD COLUMN pending_permission_time INTEGER;
ALTER TABLE session_summary ADD COLUMN pending_confirm_time INTEGER;

-- 查询有 pending 请求的摘要
CREATE INDEX IF NOT EXISTS idx_summary_pending_permission
  ON session_summary(pending_permission) WHERE pending_permission IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_summary_pending_confirm
  ON session_summary(pending_confirm) WHERE pending_confirm IS NOT NULL;
```

**Store 新增方法**:
```dart
void setPendingPermission(String employeeId, String deviceId, Map<String, dynamic> request)
void clearPendingPermission(String employeeId, String deviceId)
void setPendingConfirm(String employeeId, String deviceId, Map<String, dynamic> request)
void clearPendingConfirm(String employeeId, String deviceId)
List<SessionSummaryEntity> getPendingSummaries({String? deviceId})
```

**同步策略扩展**:
- `upsertFromRemote` 合并 pending 字段
  - pending: 远程有 + 本地无 → 覆盖
  - pending: 远程无 + 本地有 → 保留
  - pending: 都有 → 取时间较新的

---

### Phase 3: NotificationManager 集成 [P1]

**目标**: pending 请求的自动持久化与恢复

**DeviceNotificationManager 扩展**:
```dart
// 启动恢复
Future<void> restorePendingRequests()

// 权限请求生命周期
void onPermissionRequested(String employeeId, AgentPermissionRequest request)
void onPermissionResponded(String employeeId, String requestId)

// 确认请求生命周期
void onConfirmRequested(String employeeId, AgentConfirmRequest request)
void onConfirmResponded(String employeeId, String requestId)
```

**AgentNotificationHub 事件扩展**:
```dart
class AgentPermissionPendingEvent extends AgentNotificationEvent { ... }
class AgentConfirmPendingEvent extends AgentNotificationEvent { ... }
```

**事件处理链路**:
```
AgentImpl._pendingPermissionRequests → onEvent(toolPermissionRequest)
  → DeviceAgentManagerEvents._subscribeAgentEvents
    → DeviceNotificationManager.onPermissionRequested
      → SessionSummaryStore.setPendingPermission
      → LAN broadcast (agentSessionSummaryChanged)

响应:
  CachedAgentProxy.respondPermission
    → DeviceNotificationManager.onPermissionResponded
      → SessionSummaryStore.clearPendingPermission
      → LAN broadcast (agentSessionSummaryChanged)
```

---

### Phase 4: DataSyncManager 同步完善 [P1]

**目标**: 确保 pending 字段的跨设备一致性

**同步时序**:
```
设备A (Agent 运行)                     设备B (监控端)
    │                                      │
    ├─ 产生权限请求                         │
    ├─ 写入 session_summary.pending        │
    ├─ LAN broadcast ──────────────────────→│
    │                                      ├─ upsertFromRemote (含 pending)
    │                                      ├─ adjustUnreadCountFromDb
    │                                      ├─ onLatestMessageUpdated
    │                                      └─ UI 显示 pending
    │                                      │
    │←──────────── LAN broadcast (响应) ────┤
    ├─ clearPendingPermission              │
    └─ 更新 UI                             └─ 更新 UI
```

**离线重连同步**:
```
设备B 上线 → syncSessionSummariesFromDevices()
  → RPC methodGetSessionSummaries → 获取设备A的所有摘要（含 pending）
  → upsertFromRemote → 合并到本地
  → 恢复 pending 状态
```

---

### Phase 5: 集成测试 [P1]

**测试基础设施**:
- 双 DeviceClient 实例 + 内存 SQLite
- Mock LAN 连接（直接方法调用替代 TCP）
- Mock RPC（直接调用 HostRpcMethods）

**7 大测试场景**:

| # | 场景 | 关键验证点 |
|---|------|-----------|
| 1 | 基础同步流程 | 摘要创建、RPC 拉取、广播更新 |
| 2 | 未读计数同步 | 未读传递、已读广播、MAX 合并 |
| 3 | 最新消息同步 | 消息预览更新、旧广播不覆盖 |
| 4 | 权限请求同步 | pending 持久化、响应清除、离线恢复 |
| 5 | 确认请求同步 | confirm 端到端一致性 |
| 6 | 并发与冲突 | 同时已读、同时新消息、同步中到达 |
| 7 | 会话删除同步 | 删除传播、重建恢复 |

---

### Phase 6: DeviceClient API 完善 [P2]

**新增公开 API**:

```dart
// 摘要查询
List<SessionSummaryEntity> getSessionSummaries({String? deviceId});
SessionSummaryEntity? getSessionSummary({required String employeeId, String? deviceId});

// Pending 查询
List<SessionSummaryEntity> getPendingPermissionSessions();
List<SessionSummaryEntity> getPendingConfirmSessions();
List<SessionSummaryEntity> getPendingSessions();

// Pending 响应
Future<void> respondPermission({
  required String employeeId,
  required String requestId,
  required PermissionDecision decision,
  required PermissionApprovalScope scope,
});
Future<void> respondConfirm({
  required String employeeId,
  required String requestId,
  required String selectedOption,
});

// 批量操作
List<SessionSummaryEntity> getUnreadSessions({String? deviceId});
```

---

## 4. 执行优先级与依赖关系

```
Phase 1 (Store 测试补全)
    │
    ▼
Phase 2 (Entity 扩展 + Schema 迁移)
    │
    ▼
Phase 3 (NotificationManager 集成) ←── 依赖 Phase 2 的 pending 字段
    │
    ▼
Phase 4 (DataSyncManager 同步完善) ←── 依赖 Phase 3 的事件链路
    │
    ├──→ Phase 5 (集成测试) ←── 依赖 Phase 1-4 的完整实现
    │
    └──→ Phase 6 (DeviceClient API) ←── 依赖 Phase 2-4 的底层能力
```

**建议执行顺序**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → (Phase 5 + Phase 6 并行)

---

## 5. 风险与注意事项

1. **Schema 迁移兼容性**: v14_migration 需确保 ALTER TABLE 在所有目标 SQLite 版本上可用
2. **pending 字段大小**: AgentPermissionRequest JSON 可能较大，需评估是否需要截断
3. **广播频率**: permission/confirm 事件与 summary 变更合并广播，避免消息洪泛
4. **内存-DB 一致性**: AgentNotificationHub 内存计数与 session_summary DB 计数需保持同步
5. **测试隔离**: 集成测试需确保双 DeviceClient 实例的 DB 完全隔离
