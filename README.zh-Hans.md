# VibeSpot

VibeSpot 是为 Claude Code 和 Codex 做的 macOS Spotlight。它把搜索旧会话、切回正在进行中的会话、预览最近上下文、启动新会话，全部收进一个原生命令面板里。

[English](README.md) · [下载最新 Release](https://github.com/FUY25/vibespot/releases) · [发布说明](docs/RELEASING.md)

## 演示

### 一键唤起

![Quick activation demo](docs/readme-media/quick-activation.gif)

### 快速切回 live session

![Fast switch demo](docs/readme-media/fast-switch.gif)

### 模糊搜索历史会话

![Search sessions demo](docs/readme-media/search-sessions.gif)

### 直接开始新会话

![Start new session demo](docs/readme-media/start-new-session.gif)

## 为什么做它

Claude Code 和 Codex 都会在本地留下很有价值的 session 数据，但回到正确的上下文仍然太慢。VibeSpot 把这些本地历史变成一个原生、快速的切换器，用来找 live run、旧上下文、未完成工作，以及直接开始新的会话。

## 功能

- 用 Spotlight 风格面板搜索 Claude 和 Codex 的 live / 历史 session
- 按 `Enter` 直接切回 live session
- 在恢复前预览最近消息和改动文件
- 用关键词模糊搜索旧线程
- 在同一个入口里输入 `new claude` 或 `new codex`
- 默认只读本地 session 文件，不依赖云端同步

## 安装

### 方式一：下载 Release

1. 打开 [最新 Release](https://github.com/FUY25/vibespot/releases)
2. 下载 `VibeSpot.dmg`
3. 把 `VibeSpot.app` 拖到 `/Applications`
4. 首次启动时按 macOS 提示完成信任确认
5. 完成 onboarding

注意：当前打包版还没有接官方 Apple 签名和 notarization，所以 macOS 可能会要求你额外确认是否打开。

### 方式二：从源码运行

```bash
git clone https://github.com/FUY25/vibespot.git vibespot
cd vibespot
./scripts/dev-run.sh
```

## 运行要求

- macOS 14+
- 本地已经用过 Claude Code 和/或 Codex
- `~/.claude` 和/或 `~/.codex` 下已经有 session 文件

## 它不是什么

- 不是云端同步产品
- 不是托管搜索服务
- 不是 Claude Code 或 Codex 的替代品
- 目前不是跨平台产品

## 开发

常用本地命令：

```bash
./scripts/dev-run.sh
./scripts/dev-run.sh --clean
./scripts/dev-run.sh --reset-onboarding
swift test
./scripts/package-app.sh
./scripts/create-dmg.sh
```

## 开源状态

VibeSpot 已经开源，也已经可用，但仍然偏早期。核心能力已经在，剩下主要是体验打磨、打包发布、release 流程，以及公开文档整理。

## License

[MIT](LICENSE)
