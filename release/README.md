# Release assets — AI VTuber Agent v1.0.0

本目录存放待发布的构建产物（`*.zip` 与 `_build/` 不入库，仅作为 GitHub Release 附件上传）。

| 资产 | 大小 | 说明 |
|------|------|------|
| `AiVtuber-Agent-v1.0.0-win-x64.zip` | ~26 MB | **主程序便携包**：解压后双击 `ai_vtuber_agent.exe`。内含 `agent-server/`（AUAKAgent LAN 服务端/客户端），全部引用为相对路径，可解压到任意目录。 |
| `auakagent-windows-x64.zip` | ~8 MB | **单独的多代理 LAN 组件**：`auak_server.exe` / `auak_client.exe` + 配置 + `lib/sqlite3_connection_pool.dll`。供只需要局域网 Agent 服务的用户，或与主程序分机部署。 |

## 运行要求

- Windows 10 / 11 x64，建议安装 WebView2 Runtime（Win11 及新版 Win10 已预装）
- 可选外部组件（不随包分发，缺失时自动降级）：`edge-tts`、`ffmpeg`、`easyocr`+`mss`、
  PyQt6（Live2D 桌宠）、GPT-SoVITS-v2pro、AI-Pet-Engine、Claude Code CLI
- 用户数据固定写入 `D:\AiVtuber_Agent_profile\`（Steam 风格存档，运行机需有可写 D 盘）

## 多代理 LAN 快速上手

```bat
cd agent-server\bin
auak_server.exe            :: 默认 0.0.0.0:9090，数据写入 .\data
```

App 内：**MultiAgent → Settings → LAN** → `127.0.0.1` / `9090` → **Start**。

## 本次发布的构建与验证

| 项目 | 结果 |
|------|------|
| 主程序 | `flutter build windows`（Release，Dart AOT）— 构建成功 |
| LAN 组件 | `dart build cli -t bin/auak_server.dart` / `bin/auak_client.dart`（Dart 3.11.5 AOT + 原生资产） |
| 二进制品牌 | `--version` → `auakagent v1.0.0`；`--help` → `AUAKAgent LAN Server/Client`，无 `wenzagent` 字样 |
| 服务端实测 | 启动成功、监听端口、SQLite 迁移 v0→v22 全通过 |
| LAN 端到端实测 | 从 zip 解压后：`auak_client.exe --host 127.0.0.1` → `Connection state: connected`，并向服务端完成一次员工查询 RPC |
| 配置实测 | 4 份 YAML（`auak_*.yaml` 与 `config/*.example`）均实测被正确解析：自动生成 UUID 设备 ID、设备名/端口/主题按配置生效 |
| 便携包实测 | 从 zip 解压到 `%TEMP%` 后：主程序启动正常（窗口 + 127.0.0.1:48888），`agent-server` 相对 DLL 加载正常 |

## 已知事项

1. **设备 ID 请勿写成空串**：`deviceId: ""` 会得到「空设备 ID」而不是自动 UUID（配置里的空串优先于
   程序内自动生成），多设备/多实例场景下设备将无法区分。随包 YAML 已默认注释掉该行并在注释中说明；
   需要固定身份时请填唯一值（如 `deviceId: "auak-server-01"`）。主程序本身不受影响 —— 它在
   SharedPreferences 里生成并持久化 `ai-vtuber-<时间戳>`。
2. **`data\db\wenzagent.db`**：局域网组件的数据库文件名沿用上游命名，保持数据/工具链兼容
   （首次运行自动创建）。SDK 内部另有 MCP 身份标识与 `web_fetch` 的 User-Agent 仍为
   `WenzAgent`，属上游运行时标识，未改动（改动会影响既有数据与外部服务端兼容）。
3. **外部工具默认路径**仍为绝对路径（`D:\GPT-SoVITS-v2pro-20250604`、
   `D:\AI-Pet-Engine\Build\MateEngineX.exe`），这是刻意保留的「开箱默认值」，均可在设置界面修改。
4. `data\app.so`、插件 DLL 内含构建机的源文件路径字符串，仅用于崩溃堆栈，运行时无影响。

## 校验

```powershell
Get-FileHash .\AiVtuber-Agent-v1.0.0-win-x64.zip -Algorithm SHA256
Get-FileHash .\auakagent-windows-x64.zip -Algorithm SHA256
```

见 `SHA256SUMS.txt`。
