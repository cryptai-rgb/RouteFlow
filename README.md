# RouteFlow

> 掌控你的多网卡流量，让路由规则随心而动。  
> Take control of traffic across multiple network interfaces, and make routing rules move the way you want.

[中文](#中文说明) | [English](#english)

## 中文说明

### 简介

RouteFlow 是一个面向 macOS 的菜单栏应用，用来管理多网卡并存场景下的静态路由规则。

一个很典型的场景是：

- 公司内网通过有线网卡接入
- 互联网通过 Wi-Fi 接入
- 某些内网网段必须走内网出口
- 其他流量仍希望走默认外网

这类环境里，系统默认路由和网卡优先级常常会互相影响，导致访问冲突、切换不稳定，或者每次重连后都要手动补路由。RouteFlow 的目标就是把这件事变成“保存规则、自动恢复、随时开关”。

### 当前项目状态

| 平台 | 状态 | 说明 |
| --- | --- | --- |
| macOS 13+ | 已支持 | 当前代码库为 SwiftUI 菜单栏应用 |
| Windows | 暂未支持 | README 中仅保留未来支持方向 |
| Linux | 暂未支持 | README 中仅保留未来支持方向 |

### 核心能力

- 自动检测网络接口、网关、IPv4 地址和系统服务顺序
- 将规则持久化到 `~/Library/Application Support/RouteFlow/config.json`
- 通过一次管理员授权批量执行路由新增/删除
- 监听网络状态变化，在接口断开/恢复时同步规则状态
- 支持启动时自动应用规则、退出时清理规则、登录时启动
- 支持导入/导出 JSON 配置
- 支持从当前系统路由表中识别可管理路由
- 内置中英文界面文案

### 界面预览

主界面：网络接口、系统路由和导出能力

![RouteFlow main interface](<screenshot/企业微信截图_876a869e-fdc6-41cb-8f6c-d32689fe5225.png>)

规则列表：已保存规则与启动恢复开关

![RouteFlow saved rules](<screenshot/企业微信截图_944b24d7-aa62-4c77-ac96-65ee1e658ddc.png>)

### 工作原理

RouteFlow 当前的实现方式和代码保持一致，核心流程如下：

1. 使用 `networksetup`、`ifconfig` 和 `SystemConfiguration` 读取硬件端口、设备名、网关、IPv4 和服务顺序。
2. 使用 `SCDynamicStore` 监听网络状态变化，在接口上下线时刷新状态。
3. 将保存的规则写入本地 JSON 配置文件。
4. 通过 `osascript` 触发 macOS 管理员授权，再调用 `/sbin/route` 动态修改系统路由表。
5. 使用 `netstat -nr -f inet` 校验当前系统路由，并与已保存规则做同步。

当前每条规则都与具体接口绑定，并使用 `-ifscope` 控制作用网卡，适合“内网走 A，外网走 B”这类多出口场景。

### 安装

#### macOS

前置要求：

- macOS 13 或更高版本
- Xcode 15 或更高版本
- 允许输入管理员密码以更新系统路由表

从源码运行：

```bash
git clone https://github.com/<your-org>/RouteFlow.git
cd RouteFlow
xcodebuild -project RouteFlow.xcodeproj -scheme RouteFlow -destination 'platform=macOS' build
```

如果你希望根据 `project.yml` 重新生成工程，也可以：

```bash
brew install xcodegen
xcodegen generate
```

然后直接打开 `RouteFlow.xcodeproj` 进行编译和运行。

#### Windows

当前仓库没有 Windows 实现，也没有安装包。

#### Linux

当前仓库没有 Linux 实现，也没有安装包。

### 使用说明

1. 启动 RouteFlow，它会以菜单栏应用形式运行。
2. 在左侧选择一个可用网络接口。
3. 为该接口添加目标地址，可以是单个 IP，也可以是 CIDR 网段。
4. 根据需要开启“启动时自动应用规则”或“退出时清理路由”。
5. 当网络接口状态变化时，RouteFlow 会刷新并尝试恢复相关规则状态。

当前版本是 GUI 优先，配置文件实际格式为 JSON，而不是 YAML。下面的 YAML 示例更适合表达“路由意图”。

#### Usage Example (Conceptual YAML)

```yaml
# 示例规则：公司内网网段走指定网卡，其余流量继续使用系统默认路由
rules:
  - destination: 10.0.0.0/8
    interface: eth0
  - destination: 172.16.0.0/12
    interface: en0
```

#### 当前实际配置示例（JSON）

```json
{
  "version": 1,
  "isActive": true,
  "autoApplyOnLaunch": true,
  "rules": [
    {
      "id": "11111111-2222-3333-4444-555555555555",
      "destination": "10.0.0.0/8",
      "interfaceName": "en0",
      "gateway": "10.0.0.1",
      "hardwarePort": "Ethernet",
      "isActive": true,
      "createdAt": "2026-04-21T12:00:00Z"
    }
  ],
  "cleanRoutesOnExit": false
}
```

### 风险声明

RouteFlow 会直接修改 macOS 系统路由表。请在了解自己网络环境的前提下使用，尤其要注意以下风险：

- 可能短暂影响当前连接中的内网、外网、VPN 或代理流量
- 错误的目标网段、网关或接口选择，可能导致网络不可达
- 某些企业安全软件、VPN 客户端或系统策略，可能会覆盖或阻止手动路由

在生产网络、远程办公或重要会议环境中，请先小范围验证，再正式启用。

### License

本项目使用 MIT License。

---

## English

### Introduction

RouteFlow is a macOS menu bar app for managing static routes in multi-interface network environments.

A common setup looks like this:

- Corporate intranet over wired Ethernet
- Internet access over Wi-Fi
- Internal subnets must go through the intranet interface
- Everything else should keep using the default external route

In that kind of setup, default routes and interface priorities often conflict with each other. RouteFlow turns that into a simpler workflow: save rules once, restore them automatically, and toggle them when needed.

### Current Status

| Platform | Status | Notes |
| --- | --- | --- |
| macOS 13+ | Supported | SwiftUI menu bar app in this repository |
| Windows | Not supported yet | Mentioned only as a future direction |
| Linux | Not supported yet | Mentioned only as a future direction |

### Core Features

- Detects network interfaces, gateways, IPv4 addresses, and service order
- Persists rules in `~/Library/Application Support/RouteFlow/config.json`
- Applies or removes routes in batches with a single admin prompt
- Watches interface changes and updates rule state when links go down or come back
- Supports auto-apply on launch, clean on exit, and launch at login
- Imports and exports JSON configuration
- Reads existing system routes and syncs managed state
- Includes Chinese and English UI copy

### Screenshots

Main interface: network interfaces, live routes, and route export

![RouteFlow main interface](<screenshot/企业微信截图_876a869e-fdc6-41cb-8f6c-d32689fe5225.png>)

Saved rules view: persisted rules and restore-on-launch toggles

![RouteFlow saved rules](<screenshot/企业微信截图_944b24d7-aa62-4c77-ac96-65ee1e658ddc.png>)

### How It Works

The current implementation works like this:

1. It uses `networksetup`, `ifconfig`, and `SystemConfiguration` to detect hardware ports, device names, gateways, IPv4 addresses, and service order.
2. It listens for network changes through `SCDynamicStore`.
3. It stores saved rules in a local JSON config file.
4. It asks for administrator privileges through `osascript`, then updates the macOS routing table with `/sbin/route`.
5. It reads `netstat -nr -f inet` to reconcile saved rules with the live system route table.

Each rule is bound to a specific interface and applied with `-ifscope`, which makes it useful for "intranet through interface A, internet through interface B" workflows.

### Installation

#### macOS

Requirements:

- macOS 13 or later
- Xcode 15 or later
- Administrator approval for route table changes

Build from source:

```bash
git clone https://github.com/<your-org>/RouteFlow.git
cd RouteFlow
xcodebuild -project RouteFlow.xcodeproj -scheme RouteFlow -destination 'platform=macOS' build
```

If you want to regenerate the Xcode project from `project.yml`, you can also run:

```bash
brew install xcodegen
xcodegen generate
```

Then open `RouteFlow.xcodeproj` and run the app from Xcode.

#### Windows

There is no Windows implementation or package in the current repository.

#### Linux

There is no Linux implementation or package in the current repository.

### Usage

1. Launch RouteFlow. It runs as a menu bar app.
2. Select an available network interface.
3. Add destinations as single IPs or CIDR ranges.
4. Enable auto-apply on launch or clean on exit if needed.
5. RouteFlow refreshes rule state when interface connectivity changes.

The current release is GUI-first. The real on-disk format is JSON, not YAML. The YAML below is best read as a conceptual rule example.

#### Usage Example (Conceptual YAML)

```yaml
rules:
  - destination: 10.0.0.0/8
    interface: eth0
  - destination: 172.16.0.0/12
    interface: en0
```

#### Actual Config Example (JSON)

```json
{
  "version": 1,
  "isActive": true,
  "autoApplyOnLaunch": true,
  "rules": [
    {
      "id": "11111111-2222-3333-4444-555555555555",
      "destination": "10.0.0.0/8",
      "interfaceName": "en0",
      "gateway": "10.0.0.1",
      "hardwarePort": "Ethernet",
      "isActive": true,
      "createdAt": "2026-04-21T12:00:00Z"
    }
  ],
  "cleanRoutesOnExit": false
}
```

### Disclaimer

RouteFlow directly modifies the macOS routing table. Please use it carefully and only when you understand your network environment.

Potential risks include:

- Temporary interruption of intranet, internet, VPN, or proxy traffic
- Incorrect destinations, gateways, or interfaces causing connectivity loss
- Corporate security tools, VPN clients, or system policies overriding manual routes

Test carefully before using it in a production or mission-critical network environment.

### License

This project is licensed under the MIT License.
