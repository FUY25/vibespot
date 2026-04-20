# VibeSpot Branding Design

日期：2026-04-20

## Goal

把当前产品的正式品牌方向锁定下来，为后续 production-ready 重命名与图标替换提供单一真相来源。

这份设计只回答品牌定稿问题，不直接修改应用资源或文案实现。

---

## Approved Decisions

### 1. Product Name

- 正式产品名定为 `VibeSpot`

### 2. Master Symbol

- 主图形直接使用用户提供的 SVG 作为母版
- 后续不再重排内部 element
- 后续不再擅自修改 chevron、圆环、小圆点之间的相对位置
- 允许做的调整只限于：
  - 整体缩放
  - 承载底板
  - 导出适配
  - 小尺寸裁切策略

### 3. App Icon Direction

- app icon 采用深色底
- 品牌探索中选用 `A2` 作为正式 app icon 比例方向
- `A2` 的含义不是换图形，而是：
  - 使用相同母版 SVG
  - 选用更平衡的整体承载比例
  - 让图形与底板留白关系更适合作为正式 macOS app icon

### 4. Menu Bar Mark

- menu bar 版本从同一母版派生
- 当前决策：先保留最右侧小圆点
- 如果后续真机 16px-18px 验证显示该点影响可读性，再单独删掉
- 也就是说：
  - 当前默认方案是“保留 dot”
  - 只有在小尺寸真实显示失败时，才降级为去掉 dot 的 companion mark

---

## Design Principle

这次 branding 的核心原则是：

**不要再重新设计主图形，只做比例和承载决策。**

原因：

- 用户已经提供了接近定稿的主品牌图形
- production 阶段更需要的是品牌一致性，而不是持续探索新符号
- 如果主图形本身继续变动，会连带影响：
  - app icon
  - menu bar 图标
  - onboarding
  - preferences / about
  - diagnostics 命名
  - 文档和发布物料

因此这轮将主图形视为固定资产，后续工作只围绕“如何在不同载体中稳定呈现”。

---

## Chosen Direction

### App Icon

正式方向采用：

- 深色底板
- 用户提供 SVG 原样作为主符号
- `A2` 的整体缩放比例

这意味着：

- 不走最满的 `A1`
- 也不走最克制的 `A3`
- 选择中间值，优先保证：
  - Finder / Dock 中的识别度
  - 不显得过挤
  - 不显得过空
  - 更像正式可发布的 app icon

### Menu Bar

menu bar 继续遵循：

- 先最大程度忠于母版
- 保留右侧 dot
- 只有在实际 16px-18px 验证失败时，才做单独简化

这保证了品牌在正式发布前不会过早出现“主 logo 一套、menu bar 一套”的分裂。

---

## Visual Assets Scope

后续实现时，`VibeSpot` branding 替换应覆盖这些范围：

### In-App

- App title / window title
- Onboarding 中的产品名
- Preferences 中的产品名
- Menu bar status item branding
- About / diagnostics 名称

### Release Assets

- App icon
- Menu bar symbol
- 安装页与文档截图
- release 文案中的产品名
- diagnostics 导出命名

### Documentation

- `README.md`
- 安装文档
- production readiness / release checklist 中的产品名

---

## Reference Artifact

本次探索页保留在：

- [docs/vibespot-brand-exploration.html](/Users/fuyuming/Desktop/project/vibelight/docs/vibespot-brand-exploration.html)

该页面的作用是：

- 记录品牌探索过程
- 保留 `A1 / A2 / A3` 比例对比
- 作为为什么最终选择 `A2` 的参考

它不是最终的生产资源来源。生产资源来源应回到母版 SVG 和后续正式导出资产。

---

## What This Unlocks

锁定这份 branding design 后，后续可以进入实现阶段的工作包括：

1. 批量把 `Flare` 重命名为 `VibeSpot`
2. 替换 app icon 与 menu bar 图标
3. 更新 onboarding / preferences / docs / diagnostics 命名
4. 把品牌替换纳入 production P0 checklist

---

## Non-Goals

这份设计不包含：

- 新 logo 再创作
- 新几何语言探索
- marketing site 视觉系统
- 自动更新、打包、签名等发布链路实现

这些属于后续 implementation plan 和 production readiness 范围。

---

## Final Decision Summary

- 产品名：`VibeSpot`
- 主图形：使用用户提供 SVG 作为固定母版
- app icon：深色底，采用 `A2` 比例
- menu bar：先保留右侧小圆点，只有真机小尺寸失败时才简化
- 后续实现重点：统一替换，而不是继续设计主符号
