# WenzAgent 使用说明

WenzAgent 是一个纯 Dart 实现的 AI Agent 管理框架，提供局域网通信、RPC 和技能系统。

## 快速开始

### 1. 准备配置文件

将 `config/` 目录下的示例配置复制为实际配置：

**服务端：**
```bash
cp config/auak_server.yaml.example auak_server.yaml
```

**客户端：**
```bash
cp config/auak_client.yaml.example auak_client.yaml
```

### 2. 修改配置

编辑 `auak_server.yaml`：
```yaml
port: 9090                    # 服务端口
deviceId: ""                  # 设备ID（留空自动生成UUID）
hostName: "WenzAgent Server"  # 设备显示名称
storagePath: "./data"         # 数据存储目录
logLevel: "info"              # 日志级别: debug|info|warn|error|none
```

编辑 `auak_client.yaml`：
```yaml
host: "192.168.1.100"         # 服务器IP地址（必填）
port: 9090                    # 服务器端口
deviceId: ""                  # 设备ID（留空自动生成UUID）
deviceName: "My Laptop"       # 设备显示名称
storagePath: "./data"         # 数据存储目录
logLevel: "info"              # 日志级别: debug|info|warn|error|none
topic: ""                     # 分组主题（可选，留空不分组）
```

### 3. 启动服务

**启动服务端：**
```bash
./auak_server
```

**启动客户端：**
```bash
./auak_client --host <服务器IP>
```

启动成功后，客户端会自动连接到服务端，完成设备注册和发现。

---

## 命令行参数

### auak_server

```
Usage: auak_server [options]

Options:
  --config <path>       YAML 配置文件路径 (默认: auak_server.yaml)
  --port <int>          服务端口 (默认: 9090)
  --device-id <id>      设备ID (默认: 自动生成UUID)
  --host-name <name>    设备显示名称 (默认: "WenzAgent Server")
  --storage-path <path> 数据存储目录 (默认: ./data)
  --log-level <level>   日志级别: debug|info|warn|error|none (默认: info)
  --version             显示版本号
  --help, -h            显示帮助信息
```

**示例：**
```bash
# 使用默认配置启动
./auak_server

# 指定端口和日志级别
./auak_server --port 8080 --log-level debug

# 使用自定义配置文件
./auak_server --config /path/to/my_config.yaml
```

### auak_client

```
Usage: auak_client --host <ip> [options]

Options:
  --config <path>       YAML 配置文件路径 (默认: auak_client.yaml)
  --host <ip>           服务器IP地址（必填，或在配置文件中设置）
  --port <int>          服务器端口 (默认: 9090)
  --device-id <id>      设备ID (默认: 自动生成UUID)
  --device-name <name>  设备显示名称 (默认: "WenzAgent Client")
  --storage-path <path> 本地存储目录 (默认: ./data)
  --log-level <level>   日志级别: debug|info|warn|error|none (默认: info)
  --topic <topic>       分组主题（可选）
  --version             显示版本号
  --help, -h            显示帮助信息
```

**示例：**
```bash
# 连接到服务器
./auak_client --host 192.168.1.100

# 指定端口和设备名称
./auak_client --host 192.168.1.100 --port 8080 --device-name "My PC"

# 使用配置文件
./auak_client --config /path/to/my_client.yaml

# 加入指定分组
./auak_client --host 192.168.1.100 --topic "project-alpha"
```

---

## 配置优先级

命令行参数 > YAML 配置文件 > 默认值

即：命令行参数会覆盖配置文件中的对应项，配置文件会覆盖默认值。

---

## 更多文档

- 项目主页：https://github.com/lyming99/wenzagent
- 问题反馈：https://github.com/lyming99/wenzagent/issues
