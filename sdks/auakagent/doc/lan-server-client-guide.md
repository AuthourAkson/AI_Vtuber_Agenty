# LAN Server & Client 使用指南

WenzAgent 提供 Server 和 Client 两个独立 CLI 工具，用于在局域网内搭建多设备通信环境。Server 端负责监听连接和管理 RPC 请求，Client 端通过 WebSocket 连接到 Server 并进行数据交互。

---

## 目录

- [快速开始](#快速开始)
- [启动 Server](#启动-server)
  - [命令行参数](#server-命令行参数)
  - [YAML 配置文件](#server-yaml-配置文件)
- [启动 Client](#启动-client)
  - [命令行参数](#client-命令行参数)
  - [YAML 配置文件](#client-yaml-配置文件)
- [配置优先级](#配置优先级)
- [日志级别](#日志级别)
- [典型场景](#典型场景)
  - [单 Server 多 Client](#单-server-多-client)
  - [多分组隔离](#多分组隔离)
  - [开发调试](#开发调试)
- [优雅关闭](#优雅关闭)
- [存储目录结构](#存储目录结构)
- [常见问题](#常见问题)

---

## 快速开始

### 1. 启动 Server（机器 A）

```bash
dart run bin/auak_server.dart
```

Server 启动后会输出监听的 IP 和端口：

```
[INF][WenzAgentServer] WenzAgent LAN Server started
[INF][WenzAgentServer]   Device ID : 7108ff89-876d-4f6e-a8cc-1c4c7e5979d2
[INF][WenzAgentServer]   IP        : 192.168.1.7
[INF][WenzAgentServer]   Port      : 9090
[INF][WenzAgentServer] Press Ctrl+C to stop.
```

### 2. 启动 Client（机器 B）

```bash
dart run bin/auak_client.dart --host 192.168.1.7
```

Client 连接成功后会输出：

```
[INF][WenzAgentClient] WenzAgent LAN Client started
[INF][WenzAgentClient]   Server      : 192.168.1.7:9090
[INF][WenzAgentClient] Press Ctrl+C to stop.
```

---

## 启动 Server

### Server 命令行参数

```bash
dart run bin/auak_server.dart [options]
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--config` | String | `wenzagent.yaml` | YAML 配置文件路径 |
| `--port` | int | `9090` | 服务监听端口（1-65535） |
| `--device-id` | String | 自动生成 UUID | 服务端设备 ID，用于 RPC 路由标识 |
| `--host-name` | String | `WenzAgent Server` | 设备显示名称 |
| `--storage-path` | String | `./data` | 数据库和文件缓存目录 |
| `--log-level` | String | `info` | 日志级别 |
| `--version` | - | - | 打印版本号 |
| `--help`, `-h` | - | - | 打印帮助信息 |

### Server YAML 配置文件

默认读取当前目录下的 `wenzagent.yaml`，可通过 `--config` 指定其他路径。配置文件不存在时使用默认值，服务仍可正常启动。

```yaml
# wenzagent.yaml
port: 9090                    # 服务端口
deviceId: "host-server-001"   # 设备 ID（留空则自动生成 UUID）
hostName: "WenzAgent Server"  # 设备显示名称
storagePath: "./data"         # 数据库和文件缓存目录
logLevel: "info"              # 日志级别: debug | info | warn | error | none
```

示例配置文件位于 `config/auak_server.yaml.example`，可复制使用：

```bash
cp config/auak_server.yaml.example wenzagent.yaml
```

---

## 启动 Client

### Client 命令行参数

```bash
dart run bin/auak_client.dart --host <ip> [options]
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `--host` | String | (必填) | Server 的 IP 地址 |
| `--port` | int | `9090` | Server 的端口 |
| `--device-id` | String | 自动生成 UUID | 本设备 ID，用于跨设备数据同步标识 |
| `--device-name` | String | `WenzAgent Client` | 设备显示名称 |
| `--storage-path` | String | `./data` | 本地数据库存储目录 |
| `--log-level` | String | `info` | 日志级别 |
| `--topic` | String? | null | 分组主题，同 Topic 的设备可以互相通信 |
| `--config` | String | `auak_client.yaml` | YAML 配置文件路径 |
| `--version` | - | - | 打印版本号 |
| `--help`, `-h` | - | - | 打印帮助信息 |

`--host` 为必填参数。如果未通过命令行传入，必须通过 YAML 配置文件提供，否则 Client 会报错退出。

### Client YAML 配置文件

默认读取当前目录下的 `auak_client.yaml`，可通过 `--config` 指定其他路径。

```yaml
# auak_client.yaml
host: "192.168.1.100"         # 服务器 IP 地址（必填）
port: 9090                    # 服务器端口
deviceId: "my-laptop"         # 设备 ID（留空自动生成 UUID）
deviceName: "My Laptop"       # 设备显示名称
storagePath: "./data"         # 本地数据存储目录
logLevel: "info"              # 日志级别: debug | info | warn | error | none
topic: ""                     # 分组主题（可选，留空或删除此行表示不分组）
```

示例配置文件位于 `config/auak_client.yaml.example`：

```bash
cp config/auak_client.yaml.example auak_client.yaml
```

---

## 配置优先级

所有配置项遵循以下优先级：

```
命令行参数 > YAML 配置文件 > 内置默认值
```

示例：YAML 中设置 `port: 8080`，命令行传入 `--port 3000`，最终使用 `3000`。

对于 `--device-id`，如果命令行和 YAML 都未指定，则自动生成一个 UUID。每次启动生成的 UUID 不同，如果需要固定设备 ID（用于数据持久化），建议通过配置文件指定。

---

## 日志级别

通过 `--log-level` 设置，支持以下级别：

| 级别 | 说明 |
|------|------|
| `debug` | 输出所有日志，包括详细调试信息 |
| `info` | 输出常规运行信息（默认） |
| `warn` | 仅输出警告和错误 |
| `error` | 仅输出错误 |
| `none` | 关闭所有日志输出 |

日志格式：

```
[HH:mm:ss.mmm][级别][标签] 消息内容
```

示例：

```
[14:30:01.234][INF][WenzAgentServer] WenzAgent LAN Server started
[14:30:05.678][WRN][WenzAgentClient] Connection lost, reconnecting...
[14:30:10.123][ERR][DatabaseManager] Migration to version 5 failed: ...
```

---

## 典型场景

### 单 Server 多 Client

最常用的部署方式：一台机器运行 Server，多台机器运行 Client。

```bash
# Server 端（机器 A，IP: 192.168.1.100）
dart run bin/auak_server.dart --port 9090 --host-name "Main Server"

# Client 端（机器 B）
dart run bin/auak_client.dart --host 192.168.1.100 --device-name "Dev Laptop"

# Client 端（机器 C）
dart run bin/auak_client.dart --host 192.168.1.100 --device-name "Test Tablet"
```

### 多分组隔离

使用 `--topic` 参数将设备分组，不同 Topic 的 Client 之间消息隔离。

```bash
# Server（所有 Topic 共用一个 Server）
dart run bin/auak_server.dart

# Team A 的 Client
dart run bin/auak_client.dart --host 192.168.1.100 --topic team-a

# Team B 的 Client
dart run bin/auak_client.dart --host 192.168.1.100 --topic team-b
```

### 开发调试

使用 `--log-level debug` 和 `--device-id` 固定设备 ID，方便调试和复现。

```bash
# Server（调试模式）
dart run bin/auak_server.dart --port 9090 --device-id "dev-server" --log-level debug --storage-path ./dev_data

# Client（调试模式）
dart run bin/auak_client.dart --host 127.0.0.1 --device-id "dev-client" --log-level debug --storage-path ./dev_data
```

本地回环测试时 Server 和 Client 可以在同一台机器上运行（Server 用 `0.0.0.0`，Client 连接 `127.0.0.1`）。

---

## 优雅关闭

Server 和 Client 均支持通过 `Ctrl+C`（SIGINT 信号）优雅关闭。

**Server 关闭顺序**：
1. 取消消息订阅
2. 停止 Host 服务（关闭所有客户端 WebSocket 连接）
3. 释放 RPC Server 资源
4. 关闭数据库

**Client 关闭顺序**：
1. 断开与服务器的连接
2. 释放 DeviceClient 实例（关闭数据库等）

关闭过程中会输出日志：

```
[INF][WenzAgentServer] Shutting down...
[INF][WenzAgentServer] Server stopped.
```

---

## 存储目录结构

Server 和 Client 默认使用 `./data` 作为存储目录（可通过 `--storage-path` 修改）。目录会在首次启动时自动创建。

```
data/
├── wenzagent.db          # SQLite 数据库（员工、会话、消息等）
├── wenzagent.db-wal      # WAL 日志文件
├── wenzagent.db-shm      # 共享内存文件
└── cache/                # 文件缓存（上传/下载的文件）
```

同一台机器上 Server 和 Client 应使用不同的 `--storage-path`，避免数据库冲突。

---

## 常见问题

### 启动报 "port must be between 1 and 65535"

端口参数超出有效范围。检查命令行 `--port` 或 YAML 中 `port` 的值是否为 1-65535 的整数。

### Client 启动报 "--host is required"

未指定 Server 地址。通过 `--host <ip>` 参数或 YAML 配置文件中的 `host` 字段提供。

### Client 无法连接 Server

1. 确认 Server 已启动并查看其输出的 IP 地址
2. 确认两台机器在同一局域网内
3. 确认防火墙未阻止端口（默认 9090）
4. 确认 `--port` 参数与 Server 端一致

### 重复启动后数据丢失

默认 `--device-id` 为自动生成的 UUID，每次启动不同。建议通过配置文件固定 `deviceId`。

### Server 和 Client 在同一台机器

可以正常运行，但必须使用不同的 `--storage-path`：

```bash
# 终端 1 — Server
dart run bin/auak_server.dart --storage-path ./server_data

# 终端 2 — Client（连接本地回环地址）
dart run bin/auak_client.dart --host 127.0.0.1 --storage-path ./client_data
```
