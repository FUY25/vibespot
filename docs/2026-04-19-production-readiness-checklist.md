# VibeSpot Production Readiness Checklist

更新时间：2026-04-20

这份清单的目标不是“还能继续优化什么”，而是回答一个更严格的问题：

**VibeSpot 什么时候才算可以作为 production-level 的 macOS 应用正式对外发布。**

当前判断：

- 搜索、索引、Preferences、source staging、基础 QA 和测试体系已经进入可控状态。
- `VibeSpot` 命名、菜单栏图形和应用内大部分可见品牌替换已经落地。
- onboarding 已从旧的 2-step flow 重构为 8 张顺序卡结构，并会跟随系统语言切换中英文。
- 现在最大的缺口不再是单点 UI，而是：
  - 首次成功体验
  - 正式发布链路
  - 出错后的恢复与支持能力
  - 对外品牌资产统一

---

## Release Bar

只有当下面这些条件同时满足，才建议把 VibeSpot 视为 production-ready：

- P0 全部完成
- P1 中所有“发布前必须项”完成
- clean-machine 安装和首次使用流程通过
- 正式 release build 已签名并 notarize
- 文档、应用内文案、图标、安装物料全部使用最终品牌

---

## P0

这些是正式发布前必须完成的项目。

### 1. 最终产品命名定稿

- [x] 最终产品名确定，不再使用临时命名
- [x] 应用内所有可见名称统一替换
  - 菜单栏
  - 搜索面板
  - Preferences
  - Onboarding
  - About
  - diagnostics 导出命名
  - README / 安装文档 / release 文案
- [ ] 发布产物命名统一
  - `App` 名称
  - 压缩包或 DMG 名称
  - 截图标题与说明
- [ ] 若需要修改 bundle display name / bundle identifier，明确迁移策略

**验收标准**
- 用户在任何一个入口都看不到旧名字或混用名字
- release 物料、应用内文案、导出文件名完全一致

### 2. 最终 logo / app icon 定稿

- [ ] 1024x1024 正式 app icon 定稿
- [x] 菜单栏图形定稿
- [ ] 文档与安装页用图统一
- [ ] 截图、beta 邀请、release note 里的视觉资产统一
- [ ] 深色 / 浅色环境下视觉识别做过最小验证

**验收标准**
- Finder、Dock、菜单栏、About、文档里都使用同一套最终视觉资产
- 不存在占位 icon、旧 logo、风格不一致的情况

### 3. Onboarding 改成 first-success 体验

目标不是“让用户完成 onboarding”，而是“让用户第一次就成功”。

- [x] onboarding 明确区分以下用户状态
  - 没装 Claude / Codex
  - 装了 binary 但没有 session 数据
  - session source 不可读或路径失效
  - 只有 Claude 或只有 Codex
- [ ] onboarding 的环境检查提升为“可成功使用”的检查
  - binary 是否存在
  - session 路径是否存在
  - session 路径是否可读
  - source override 是否有效
- [ ] onboarding 结束前至少引导用户完成一个真实动作
  - 能打开搜索
  - 能看到结果或明确知道为什么没有结果
  - 能成功触发一次 `new codex` / `new claude`
- [ ] 空状态解释要清楚，不让用户误以为 app 坏了
- [ ] 失败状态要可操作，不只是提示 warning

当前进度补充：

- [x] onboarding 结构已经重构为 8 张顺序卡
- [x] onboarding 会根据系统语言自动切中文 / 英文
- [ ] 右侧真实 GIF / 录屏仍待替换
- [ ] onboarding 最终视觉 polish 仍待完成

**验收标准**
- 新用户第一次启动后，能明确知道“下一步该干嘛”
- 用户无法成功使用时，界面会明确指出卡在哪里，而不是静默失败

### 4. 正式 release pipeline

- [ ] 明确 production build 流程
- [ ] 生成正式 `VibeSpot.app`
- [ ] code signing 完成
- [ ] notarization 完成
- [ ] 最终安装分发形式确定
  - `VibeSpot.app`
  - `.zip`
  - `.dmg`
  - 或其他明确方案
- [ ] 在干净机器上验证安装链路
  - 下载
  - 拖进 `/Applications`
  - 首次打开
  - 信任提示
  - 正常运行
- [ ] launch-at-login 在 packaged build 下真实验证

**验收标准**
- 非开发者用户无需源码环境即可安装使用
- 安装流程没有“只适用于本机开发环境”的步骤

### 5. Supportability 与恢复能力

- [ ] 关键失败路径不再只靠 `print(...)`
- [ ] 用户可见的错误提示补齐
  - source 切换失败
  - launch action 失败
  - diagnostics 导出失败
  - 索引不可用或索引损坏
  - session source 无效
- [ ] diagnostics 导出增强
  - 当前 settings
  - 当前 source resolution
  - index workspace 信息
  - active/staging DB 信息
  - 最近错误摘要
  - 环境检查结果
- [ ] reindex / source switch / invalid source 的恢复路径清晰
- [ ] 至少保留一个面向用户的反馈入口
  - GitHub issue
  - 邮件
  - 诊断包说明

**验收标准**
- 用户出错时至少能看到“发生了什么、怎么办、如何反馈”
- 团队拿到 diagnostics 后能更快定位问题，而不是只能复现猜测

### 6. Clean-machine QA

- [ ] 全新 profile 首装验证
- [ ] 无 session 数据场景验证
- [ ] 仅 Claude 场景验证
- [ ] 仅 Codex 场景验证
- [ ] Claude + Codex 都存在场景验证
- [ ] custom source 场景验证
- [ ] source 失效场景验证
- [ ] launch-at-login packaged build 验证
- [ ] diagnostics 导出验证
- [ ] Preferences 关键路径验证
- [ ] onboarding 到 first action 全链路验证

**验收标准**
- 不依赖开发者对本机环境的熟悉程度
- 不依赖已有索引、已有权限、已有 session 作为前提

---

## P1

这些很重要，但不一定要全部卡住第一版 production 发布。

### 1. 升级与迁移路径

- [ ] 旧配置迁移验证
- [ ] 旧 source 配置迁移验证
- [ ] 改名后的迁移策略明确
- [ ] 未来 bundle display name / bundle id 变化的兼容策略明确

### 2. 自动更新机制

- [ ] 确定是否引入 updater
- [ ] 如果引入，确定 channel 策略
  - stable
  - beta
  - internal
- [ ] 更新失败的回退策略明确

### 3. 文档对外化

- [ ] README 改成用户视角，而不再以源码运行作为主路径
- [ ] 安装文档按正式 release 更新
- [ ] known limitations 明确
- [ ] privacy / local-only 行为说明明确
- [ ] troubleshooting 文档补齐

### 4. Accessibility

- [ ] 关键控件可被 VoiceOver 识别
- [ ] 键盘导航语义完整
- [ ] 重要状态变化可被感知
- [ ] 非鼠标用户能完成核心流程

### 5. Production 监控与支持入口

- [ ] 统一 issue 模板
- [ ] diagnostics 使用说明
- [ ] version/build 可复制
- [ ] release note 模板

---

## P2

这些属于正式发布后继续打磨也可以接受的项。

### 1. 本地化

- [ ] 文案集中管理
- [ ] 为未来多语言做好结构准备

### 2. 更完整的运行态遥测与性能采样

- [ ] release build 下的 first-open latency 采样
- [ ] first-keystroke latency 采样
- [ ] 大索引压力测试
- [ ] source switch 性能采样

### 3. 更完整的 About / Support 面板

- [ ] build / version / channel 展示更完整
- [ ] diagnostics 快捷入口
- [ ] release source / support link 明确

---

## Current Recommendation

如果目标是“真正对外发 production”而不是继续 beta，我建议执行顺序如下：

1. 先定最终名字和 logo
2. 同时把 onboarding 改成 first-success
3. 立刻补正式 release pipeline
4. 再补 supportability 与 diagnostics
5. 最后用 clean-machine QA 做 production gate

---

## Ship Decision

### 可以发 public beta，但不建议叫 production 的状态

- 测试全绿
- UI 和核心交互稳定
- 偶发问题有 workaround
- 安装仍然偏手工
- 支持与恢复能力还不够

### 可以叫 production 的状态

- P0 全部完成
- 用户首次使用不需要开发者解释
- 正式安装链路完成
- 出问题时用户知道如何恢复或反馈
- 品牌、文档、安装、应用内命名完全统一
