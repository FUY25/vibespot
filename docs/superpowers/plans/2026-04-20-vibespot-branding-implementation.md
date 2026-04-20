# VibeSpot Branding Implementation Plan

日期：2026-04-20

## Goal

把当前产品从 `Flare` 统一重命名为 `VibeSpot`，并按已批准的 branding spec 替换主图标与菜单栏图标，同时避免破坏现有用户的本地设置、索引数据和运行时兼容性。

对应设计定稿：

- [2026-04-20-vibespot-branding-design.md](/Users/fuyuming/Desktop/project/vibelight/docs/superpowers/specs/2026-04-20-vibespot-branding-design.md)

---

## Scope

本计划覆盖：

1. 产品可见名称从 `Flare` 改为 `VibeSpot`
2. app icon 与 menu bar logo 替换为新的品牌资产
3. onboarding / preferences / about / diagnostics / release docs 品牌统一
4. 运行时与持久化兼容策略，避免已有用户“因为改名丢设置”
5. QA 与回归验证

本计划暂不覆盖：

1. 签名、notarization、正式 release 打包
2. marketing site 或官网视觉系统
3. 自动更新器
4. 大规模 bundle identifier 迁移发布策略落地

---

## Architecture Summary

这次品牌替换不是单纯搜字串。

当前工程里，`Flare` 同时存在于 4 个层级：

1. `用户可见品牌层`
   - 窗口标题
   - 菜单项
   - onboarding / preferences / docs 文案

2. `构建与模块层`
   - Swift package product / target 名
   - `@testable import Flare`
   - 运行命令 `swift run Flare`

3. `持久化与本地兼容层`
   - `UserDefaults` key 前缀 `flare.*`
   - diagnostics 导出目录 `flare-diagnostics-*`
   - Application Support 子目录 `Flare`

4. `资产层`
   - app icon
   - menu bar symbol
   - 相关截图与文档素材

实现时必须把这 4 层拆开处理：

- 用户可见品牌需要尽快全部切到 `VibeSpot`
- 但持久化 key 和本地目录不能直接粗暴重命名，否则会让旧用户像“第一次安装”
- 构建层是否同步改 target/product，要作为单独步骤执行，避免一次 diff 过大

---

## Key Decision

### Rename Strategy

采用“两层改名”：

1. **先改品牌与资产**
   - 所有用户可见名称改成 `VibeSpot`
   - 图标、菜单栏、窗口标题、文档统一

2. **持久化兼容先保守**
   - 继续兼容现有 `flare.*` settings keys
   - 继续兼容现有 `Flare` Application Support 路径
   - 新代码可以开始支持 `VibeSpot` 命名，但必须保留读取旧值能力

理由：

- production 前优先保证用户升级不丢设置
- 视觉和文案统一不需要强依赖底层数据迁移
- 真正的数据迁移可以在后续 release pipeline 阶段再做

### Menu Bar Mark Strategy

按 branding spec 执行：

- 基于用户提供 SVG 的同一母版派生
- 默认保留右侧 dot
- 只有在真机 16px-18px 可读性失败时，才降级去掉 dot

---

## Workstreams

### Workstream 1: Brand Inventory And Asset Preparation

目标：先把所有品牌触点列清楚，并准备正式可落地的图形资产。

涉及文件：

- `Sources/VibeLight/UI/MenuBarLogo.swift`
- `Sources/VibeLight/Resources/Assets.xcassets/`
- `docs/vibespot-brand-exploration.html`
- `README.md`
- `docs/BETA-INVITE-INSTALL.md`
- `docs/BETA-RELEASE-CHECKLIST.md`

任务：

1. 生成正式品牌资产清单：
   - app icon master
   - menu bar symbol
   - 如需多尺寸导出，列出 16 / 18 / 24 / 32 / 128 / 256 / 512
2. 明确 app icon 采用 `A2` 比例承载
3. 确认菜单栏 mark 的小尺寸渲染策略
4. 把探索页保留为参考，不作为生产资源入口

完成标准：

- 有单一正式来源可供 AppKit 和资产目录消费
- 资产命名不再混用试验版方案

---

### Workstream 2: User-Facing Product Rename

目标：用户在应用内看到的名字全部统一为 `VibeSpot`。

重点文件：

- `Sources/VibeLight/App/AppDelegate.swift`
- `Sources/VibeLight/Onboarding/OnboardingWindowController.swift`
- `Sources/VibeLight/UI/PreferencesWindowController.swift`
- `Sources/VibeLight/Resources/Web/onboarding.html`
- `Sources/VibeLight/Resources/Web/onboarding.js`
- 其他包含 `Flare` 的 UI / doc strings

任务：

1. 替换 app 内品牌文案：
   - `Welcome to Flare`
   - `Quit Flare`
   - tooltip / subtitle / helper copy
2. 替换 onboarding 网页资源中的品牌名
3. 替换 Preferences 说明文案中的品牌名
4. 替换 README 与安装文档中的产品名、应用包名示例

完成标准：

- 用户可见界面不再混用 `Flare` 与 `VibeSpot`
- 文档安装说明与应用实际品牌一致

风险：

- 文档、说明文案较多，容易漏改
- 需要单独跑一次全文品牌扫描

---

### Workstream 3: Runtime Compatibility Layer

目标：保证旧用户升级后不会因为改名失去已有状态。

重点文件：

- `Sources/VibeLight/Settings/SettingsStore.swift`
- `Sources/VibeLight/App/AppDelegate.swift`
- `Sources/VibeLight/Support/DiagnosticsExporter.swift`
- `scripts/dev-run.sh`

任务：

1. `SettingsStore` 明确采用“新旧 key 双读”策略：
   - 新 key 可以逐步引入 `vibespot.*`
   - 旧 key `flare.*` 必须继续读
2. onboarding completion、hotkey、theme、history mode 等历史 key 不得失效
3. diagnostics 导出目录名改成品牌一致的 `vibespot-*`，但不影响旧导出读取逻辑
4. Application Support 路径策略需要显式决定：
   - 首版 rename 先继续用旧目录，确保平滑升级
   - 或者做惰性迁移，但必须带 fallback
5. `scripts/dev-run.sh` 的 defaults 清理逻辑同步更新，同时保留旧域兼容

完成标准：

- 已有用户升级后仍能读到旧设置
- 改名不会把 onboarding / preferences / hotkey 重置掉

风险：

- 如果直接改 defaults domain 或 support path，最容易造成“像重装了一次”

---

### Workstream 4: Build And Module Naming

目标：决定是否同步把工程内部 target/product 名称从 `Flare` 切换到 `VibeSpot`。

重点文件：

- `Package.swift`
- `Tests/VibeLightTests/*.swift`
- `scripts/dev-run.sh`

建议：

这一项分两步：

1. **本轮可以做**
   - 可执行产物名、对外运行说明、文档里的 app 名称改成 `VibeSpot`

2. **本轮谨慎处理**
   - Swift package product / target 名是否从 `Flare` 改成 `VibeSpot`
   - `@testable import Flare` 是否整体迁移

原因：

- 这是高扰动改动，触及所有测试与运行入口
- 如果和品牌替换同一提交一起做，排错成本太高

默认建议：

- **先把用户可见层与产物层改成 `VibeSpot`**
- **模块名 `Flare` 暂时保留一版**
- 等 branding 稳定后，再单独做模块级 rename

完成标准：

- 对用户和发布物而言已经是 `VibeSpot`
- 内部模块名是否继续沿用 `Flare` 成为一个明确的后续任务，而不是模糊状态

---

### Workstream 5: Icon And Menu Bar Integration

目标：把新品牌图形真正接到应用运行态。

重点文件：

- `Sources/VibeLight/UI/MenuBarLogo.swift`
- `Sources/VibeLight/App/AppDelegate.swift`
- `Sources/VibeLight/Resources/Assets.xcassets/`

任务：

1. 用正式品牌几何重做菜单栏 symbol 生成逻辑或替换为资产驱动逻辑
2. 接入 app icon 资产，确保 Finder / Dock / packaged build 能显示新图标
3. 验证暗色系统菜单栏中的小尺寸清晰度
4. 如小圆点在 16-18px 真机下失败，再按 spec 允许的降级策略简化

完成标准：

- 菜单栏图标与 app icon 属于同一品牌体系
- 暗色菜单栏、浅色背景、截图里都能成立

---

### Workstream 6: Diagnostics, About, And Support Surface

目标：把支持面和导出产物也统一到新品牌。

重点文件：

- `Sources/VibeLight/Support/DiagnosticsExporter.swift`
- `Sources/VibeLight/UI/PreferencesWindowController.swift`
- 如存在 About / version surface 的其他文件

任务：

1. diagnostics 导出文件夹改成 `vibespot-*`
2. diagnostics manifest 中 application name 改为 `VibeSpot`
3. About / version / build 信息保持品牌一致
4. 如有“Open Flare automatically”这类支持文案，同步改名

完成标准：

- 用户导出的支持包、About 信息、设置文案全都使用统一品牌

---

### Workstream 7: Docs And Production Checklist Sync

目标：把 repo 中面向外部的主要文档同步到新品牌。

重点文件：

- `README.md`
- `docs/BETA-INVITE-INSTALL.md`
- `docs/BETA-RELEASE-CHECKLIST.md`
- `docs/2026-04-19-production-readiness-checklist.md`

任务：

1. 把外部安装和发布文案中的 `Flare.app` 改成 `VibeSpot.app`
2. 把产品描述统一成 `VibeSpot`
3. production readiness checklist 里加入“正式命名与图标替换已完成”的已执行项
4. 如需保留历史名称，明确只在迁移说明里出现一次

完成标准：

- 外部阅读者不会再误以为产品名是 `Flare`

---

## Suggested Execution Order

1. 准备正式品牌资产和菜单栏渲染路径
2. 先改所有用户可见品牌文案
3. 再接 diagnostics / support / docs
4. 最后决定是否在同一轮处理 build product rename
5. 完成后做一次运行态 QA 和全文扫描

原因：

- 先完成用户可见层，可以最快收敛品牌一致性
- 把高风险的模块 rename 放后面，可以降低一次性改动面

---

## Verification Plan

### Automated

1. 全文扫描不得残留用户可见 `Flare` 文案
2. `swift test` 全量通过
3. 针对 `SettingsStore` 增加兼容测试：
   - 旧 `flare.*` key 仍然可读
   - 如引入新 key，双读逻辑正确
4. 针对 diagnostics 增加导出命名测试

### Runtime QA

1. 启动应用后确认菜单栏显示为新图标
2. 打开 onboarding，确认标题和说明文案已改成 `VibeSpot`
3. 打开 Preferences，确认所有品牌文案一致
4. 导出 diagnostics，确认目录和 manifest 品牌名正确
5. 真实小尺寸检查菜单栏图标在暗色 macOS 菜单栏中的读数

---

## Risks And Mitigations

### Risk 1: Rename breaks existing settings

缓解：

- 先保留旧 `flare.*` 持久化 key 读取
- 必要时新旧 key 双写或懒迁移

### Risk 2: Menu bar icon looks good in mock but fails at 16px

缓解：

- 必须做真机菜单栏验证
- 若 dot 失真，再按 spec 降级

### Risk 3: Large mechanical rename creates noisy diff

缓解：

- 把“品牌文案替换”和“模块/target rename”分开
- 先完成低风险用户可见层

### Risk 4: Docs and code drift

缓解：

- 最后跑一次全文品牌扫描
- 把文档同步纳入同一轮交付，不留到后面

---

## Definition Of Done

当以下条件同时满足时，这一轮 branding implementation 算完成：

1. 用户可见产品名已经统一为 `VibeSpot`
2. app icon 与菜单栏图标已经切到新品牌方向
3. diagnostics / onboarding / preferences / docs 全部品牌一致
4. 旧用户升级后不会因为改名丢设置或重走 onboarding
5. 真机菜单栏和窗口级 QA 通过
6. `swift test` 通过

---

## Recommended Execution Mode

推荐使用 **Subagent-Driven**。

原因：

- 这轮工作天然可以拆成几个独立面：
  - 品牌字符串与 docs
  - 图标与菜单栏
  - 持久化兼容与 diagnostics
- 平行推进可以缩短总时长
- 最终再由主线程统一收口 QA

