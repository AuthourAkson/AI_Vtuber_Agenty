# Client Test - 功能测试基础框架

本目录包含 wenzagent 的功能测试基础类，用于模拟 Client ↔ Server 的各种通信场景。

## 文件结构

```
test/client_test/
├── fake_lan_client_service.dart   # FakeLanClientService - 可控的 LAN 客户端假实现
├── fake_lan_host_service.dart     # FakeLanHostService - 可控的 LAN 服务端假实现
├── client_test_fixture.dart       # ClientTestFixture - 客户端完整生命周期模拟
├── server_test_fixture.dart       # ServerTestFixture - 服务端完整生命周期模拟
├── lan_test_harness.dart          # LanTestHarness - 端到端通信模拟
├── client_scenario_test.dart      # 示例测试（27 个测试用例）
└── README.md                      # 本文件
```

## 核心组件

### 1. FakeLanClientService

模拟 `LanClientService` 接口，替代真实 WebSocket 连接。

```dart
final fake = FakeLanClientService(deviceId: 'test-device');

// 控制连接状态
fake.simulateConnected();
fake.simulateDisconnected();

// 注入接收消息
fake.injectMessage(LanMessage(type: LanMessageType.pong, fromId: 'host'));

// 记录发送的消息
await fake.sendLanMessage(LanMessage(type: LanMessageType.text, content: 'hello'));
expect(fake.sentMessages.length, 1);

// 消息拦截器
fake.sendInterceptor = (msg) => msg.type != LanMessageType.ping;
```

### 2. FakeLanHostService

模拟 `LanHostService` 接口，替代真实 WebSocket Server。

```dart
final fakeHost = FakeLanHostService();
await fakeHost.start(port: 9090);

// 注册虚拟客户端
fakeHost.registerClient(clientId: 'c1', deviceId: 'device-1');

// 模拟客户端发送消息
fakeHost.simulateClientMessage(clientId: 'c1', message: LanMessage(...));

// 广播 / 定向发送
fakeHost.broadcast(LanMessage.system('broadcast'));
fakeHost.sendToClient('c1', LanMessage.system('directed'));
```

### 3. ClientTestFixture

模拟 `bin/auak_client.dart` 的完整生命周期。自动创建临时数据库、初始化 DeviceClient、模拟连接。

```dart
setUp(() async {
  fixture = await ClientTestFixture.create('my-test');
});

tearDown(() async {
  await fixture.dispose(); // 自动清理临时文件
});

// 业务操作
await fixture.employeeManager.createEmployee(employee);
final emp = await fixture.employeeManager.getEmployee(empId);

// 便捷访问
fixture.employeeManager;  // EmployeeManager
fixture.sessionManager;   // SessionManager
fixture.messageStore;     // MessageStoreService
fixture.fakeLanClient;    // FakeLanClientService
```

### 4. ServerTestFixture

模拟 `bin/auak_server.dart` 的完整生命周期。包含 Host RPC 方法注册、客户端会话管理。

```dart
setUp(() async {
  fixture = await ServerTestFixture.create('server-test');
});

// 直接调用 RPC 方法
final result = await fixture.callRpc(
  HostRpcConfig.methodSyncEmployees,
  {'employees': [employee.toMap()]},
);

// 获取 handler 引用
final handler = fixture.getHandler(HostRpcConfig.methodGetEmployees);

// 模拟客户端连接
fixture.simulateClientConnect(clientId: 'c1', clientDeviceId: 'd1');
fixture.simulateClientDisconnect('c1');
```

### 5. LanTestHarness

组合 Client + Server，提供端到端通信模拟。内置消息桥接机制。

```dart
setUp(() async {
  harness = await LanTestHarness.create('e2e-test');
});

// 消息自动桥接：Client ↔ Server
// Client 发送 → Host 接收
// Host 广播 → Client 接收

// 网络模拟
harness.simulateNetworkDisconnect();
harness.simulateNetworkRecover();

// 便捷访问
harness.server;   // ServerTestFixture
harness.client;   // ClientTestFixture
```

## 编写新测试

参考 `client_scenario_test.dart` 的模式：

```dart
import 'package:test/test.dart';
import 'client_test_fixture.dart';

void main() {
  group('我的功能测试', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('my-feature');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('测试某个功能', () async {
      // 使用 fixture 的业务服务
      // ...
    });
  });
}
```

## 设计原则

1. **不依赖真实网络**：所有 LAN 通信通过 Fake 实现模拟
2. **真实数据库**：使用 SQLite 内存/临时数据库，验证真实持久化逻辑
3. **自动清理**：每个 Fixture 在 dispose() 时自动删除临时文件
4. **参考 bin 代码**：初始化流程与 bin/server、bin/client 保持一致
5. **可组合**：ClientTestFixture 和 ServerTestFixture 可独立使用，也可通过 LanTestHarness 组合
