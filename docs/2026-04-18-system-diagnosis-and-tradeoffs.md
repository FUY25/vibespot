# 2026-04-18 当前代码库诊断与待决取舍

## 范围

这份文档汇总了两轮分析结果，覆盖：

- 当前 `master` 相对 `origin/master` 的已提交改动。
- 当前工作区里与 `Preferences`、`session source`、`search panel`、`indexer` 相关的未提交改动。
- 之前已经确认的系统级性能问题，以及这轮是否被修复。
- 用户报告的 `Preferences 点不开` 症状。

这不是 refinement plan。
这份文档的目标是先把问题和取舍写清楚，再决定后续怎么做。

## 当前仓库状态

- 分支状态：`master...origin/master [ahead 3]`
- 已提交差异统计：`8 files changed, 509 insertions(+), 56 deletions(-)`
- 未提交差异统计：`12 files changed, 1076 insertions(+), 268 deletions(-)`
- 未提交改动里，最大单文件是 `Sources/VibeLight/UI/PreferencesWindowController.swift`，当前 diff 规模约 `+935` 行。

这说明最近两类变化同时存在：

1. 已提交的 3 个 commit，主要是搜索面板 UI 稳定性和视觉对齐。
2. 未提交改动，主要是 preferences/source fallback 架构扩展。

## 证据来源

- 代码路径审查：`AppDelegate`、`PreferencesWindowController`、`SearchPanelController`、`Indexer`、`SessionIndex`、`SessionSourceConfiguration`、`LiveSessionRegistry`、`WebBridge`
- 当前分支与工作区 diff 审查
- 定向测试：
  - `swift test --filter PreferencesWindowControllerTests`
  - `swift test --filter SearchPanelControllerPreviewTests`

这两个测试目前都通过。
这意味着：

- 至少在测试环境中，preferences controller 可以创建出来，about tab 和 shortcut sheet 也能工作。
- 但这还不能证明真实运行态里 `Preferences 点不开` 这个症状不存在。

## 性能量级背景

以下是此前本地数据规模和查询量级测量结果，用来判断哪些问题是真正的 blocker：

- `~/.codex/sessions`：约 `964` 个 JSONL 文件，总体积约 `855.7 MB`
- 当前 Flare 索引：约 `530 MB`
- 当前索引数据量：约 `623` 个 sessions，`92,084` 条 transcript rows
- 空查询 live list 路径：平均约 `0.04ms`
- metadata-only 搜索路径：平均约 `0.26ms`
- transcript FTS 搜索：平均约 `37.3ms`，峰值约 `90.8ms`

结论不是 SQLite 本身慢，而是应用在高频、非增量、主线程路径上做了太多工作。

## A. 已确认的新问题或放大的问题

### 1. `[P1]` 切换 session source mode 会触发破坏性全量重建，即使“实际使用路径”没变

相关代码：

- `Sources/VibeLight/UI/PreferencesWindowController.swift:919`
- `Sources/VibeLight/App/AppDelegate.swift:237`
- `Sources/VibeLight/App/AppDelegate.swift:252`
- `Sources/VibeLight/Settings/SessionSourceConfiguration.swift:25`

问题链路：

1. `sourceModeChanged()` 一触发就立刻保存设置。
2. `AppDelegate.applySettings()` 比较 `newSourceResolution != sessionSourceResolution`。
3. `SessionSourceResolution` 的相等性不是只比较有效路径，还包含：
   - `requestedMode`
   - `customRequestedButUnavailable`
   - `autoFallbackForClaude`
   - `autoFallbackForCodex`
   - `usingCustomClaude`
   - `usingCustomCodex`
4. 一旦不相等，就调用 `reconfigureIndexerForSessionSourceChange()`。
5. 这条路径里会直接 `clearAllIndexedSessions()` 并重建 indexer。

结果：

- 用户只是把 `Automatic` 切到 `Custom`，即使当前仍 fallback 到完全相同的 auto 路径，也可能触发一次整库清空和全量重建。
- 对当前索引规模，这不是“有点浪费”，而是很重的系统级抖动。

### 2. `[P1]` source 切换时先清库再停旧 indexer，存在 stale data 回灌竞态

相关代码：

- `Sources/VibeLight/App/AppDelegate.swift:252`
- `Sources/VibeLight/Watchers/Indexer.swift:71`
- `Sources/VibeLight/Watchers/Indexer.swift:115`

问题点：

- `reconfigureIndexerForSessionSourceChange()` 先执行 `sessionIndex.clearAllIndexedSessions()`
- 然后才执行 `indexer?.stop()`
- 而旧 indexer 的 startup scan 是 `Task.detached(priority: .utility)` 跑起来的

这意味着：

- 在旧 indexer 真正停掉之前，它仍有机会把旧 source 的数据重新写回索引。
- 这会带来“刚清空又被旧扫描回填”的竞态风险。

### 3. `[P2]` 搜索面板里按 `Tab` 切 history mode，会持久化设置并重建 hotkey manager

相关代码：

- `Sources/VibeLight/UI/SearchPanelController.swift:207`
- `Sources/VibeLight/App/AppDelegate.swift:249`
- `Sources/VibeLight/App/AppDelegate.swift:263`
- `Sources/VibeLight/App/AppDelegate.swift:350`

问题点：

- `Tab` 本来是一个高频、轻量的 panel 内交互。
- 现在它会：
  - 改全局设置
  - `settingsStore.save(...)`
  - 重新走 `applySettings(...)`
  - 每次都 `rebuildHotkeyManagerIfNeeded()`

结果：

- 一个 Spotlight 风格的轻交互，被接到了整套全局 settings apply 路径上。
- 这不一定造成致命性能问题，但明显增加了不必要工作和耦合。

### 4. `[P2]` 自定义 source 路径无效时，resolver 的最终状态表达不够清楚

相关代码：

- `Sources/VibeLight/Settings/SessionSourceConfiguration.swift:86`
- `Sources/VibeLight/Settings/SessionSourceConfiguration.swift:121`
- `Sources/VibeLight/Settings/SessionSourceConfiguration.swift:133`

问题点：

- 当 `requestedMode == .custom`
- 且 `customPath` 无效
- 且 auto root 也不可用

当前逻辑会返回：

- `path = normalizedCustom ?? autoPath`
- `usingCustom = false`
- `fallbackToAuto = false`

这会导致：

- UI 层很难准确表达“当前 custom 配置无效，且并没有真正 fallback 成功”。
- 系统可能静默指向一个无效目录，而不是明确进入错误态。

### 5. `[P2]` Preferences 控制器体积和职责已经明显失衡

相关代码：

- `Sources/VibeLight/UI/PreferencesWindowController.swift:115`
- `Sources/VibeLight/UI/PreferencesWindowController.swift:272`
- `Sources/VibeLight/UI/PreferencesWindowController.swift:312`
- `Sources/VibeLight/UI/PreferencesWindowController.swift:896`

现状：

- 这个 controller 现在同时承担：
  - window 构建
  - sidebar/tab 切换
  - settings pane 构建
  - about pane 构建
  - source picker
  - settings 保存
  - shortcut sheet 协调
  - reindex / diagnostics action

问题不是“文件长一点”本身，而是：

- UI 组装、状态管理、持久化、副作用触发都混在一起。
- 后续如果继续修 preference，复杂度会上升得很快。
- 用户已经报告 `Preferences` 打不开，这会进一步放大对这个模块的风险判断。

### 6. `[P3]` 新增 preferences/source 流程测试覆盖仍然偏薄

相关代码：

- `Tests/VibeLightTests/PreferencesWindowControllerTests.swift:7`

当前已有测试只覆盖：

- shortcut sheet 可取消
- about tab 可点击

缺失的关键覆盖包括：

- source mode 切换是否应触发 reindex
- custom/automatic/fallback 组合状态
- invalid custom path 的 UI 和运行时行为
- `Tab` 切 history mode 的持久化副作用
- source 切换时是否会触发竞态

### 6.1 `[P2]` 选择单个 custom root 时也会立刻进入 custom mode，并可能触发过早重建

相关代码：

- `Sources/VibeLight/UI/PreferencesWindowController.swift:932`
- `Sources/VibeLight/UI/PreferencesWindowController.swift:954`

问题点：

- 现在只要用户在 picker 里选了 `Claude` 或 `Codex` 其中一个 root
- 代码就会立刻把 `settings.sessionSourceConfiguration.mode = .custom`
- 然后马上保存并触发全局 apply

这意味着：

- 用户还没把两个 root 都配完，系统就可能先做一次 source 切换和重建。
- 对一个全局 source 配置来说，这会制造多次过早副作用。

## B. 用户报告但尚未被测试复现的问题

### 7. `[待复现]` Preferences 当前“点不开”

用户反馈：

- 目前 preference 点不开，怀疑是窗口太大。

当前从代码看，不支持“纯粹因为太大所以打不开”这个判断：

- `AppDelegate.openPreferences()` 很直接，只是惰性创建 controller 然后 `showPreferences()`：
  - `Sources/VibeLight/App/AppDelegate.swift:118`
  - `Sources/VibeLight/App/AppDelegate.swift:135`
- `PreferencesWindowController.showPreferences()` 也只是：
  - `center`
  - `showWindow`
  - `makeKeyAndOrderFront`
  - `NSApp.activate(...)`
- 主内容区是 `NSScrollView`
  - `Sources/VibeLight/UI/PreferencesWindowController.swift:272`
- 内容栈被约束到 scroll view 宽度，不是靠无限增高硬顶窗口：
  - `Sources/VibeLight/UI/PreferencesWindowController.swift:294`
- 当前窗口尺寸是 `780 x 540`

所以目前更准确的结论是：

- 这个“点不开”症状是真实用户报告。
- 但它还没有被测试复现。
- 从现有代码看，也不明显是“窗口太大”这个单一原因导致。

更可能的解释方向：

- runtime 环境里的窗口管理/菜单路由问题
- 某个真实 UI 交互路径上的状态问题
- preferences 模块复杂度过高，导致更难定位交互态 bug

当前不能把“太大”当成已经确认的 root cause。

## C. 上一轮已确认、目前仍未解决的系统级性能问题

### 8. `[P1]` 面板可见时每 500ms 强制重新搜索

相关代码：

- `Sources/VibeLight/UI/SearchPanelController.swift:856`
- `Sources/VibeLight/UI/SearchPanelController.swift:865`

问题点：

- 面板可见时，定时器每 `0.5s` 触发一次
- 再从 `WKWebView` 读一遍输入框值
- 然后重新执行 `refreshResults(query:)`

这意味着：

- 即使用户没有输入、索引没有变化，也会重复做 search 和结果推送。

### 9. `[P1]` 搜索和结果序列化仍然跑在主 actor 路径上

相关代码：

- `Sources/VibeLight/UI/SearchPanelController.swift:264`
- `Sources/VibeLight/UI/SearchPanelController.swift:289`
- `Sources/VibeLight/UI/WebBridge.swift:91`
- `Sources/VibeLight/UI/WebBridge.swift:140`

问题点：

- `refreshResults(query:)` 直接调用 `sessionIndex.search(...)`
- `pushResults(...)` 先做整份 `results -> JSON`
- `WebBridge.resultToJSON(...)` 每次都会重新算 `relativeTime`

并且当前顺序是：

1. 先 JSON 序列化整份结果
2. 再生成 signature
3. 最后才判断是否真的要推给 web view

也就是说，即使结果没变，序列化成本也已经付出了。

### 10. `[P1]` Codex 状态文件变化仍然触发整棵 sessions 全量重建

相关代码：

- `Sources/VibeLight/Watchers/Indexer.swift:567`
- `Sources/VibeLight/Watchers/Indexer.swift:592`
- `Sources/VibeLight/Watchers/Indexer.swift:677`

问题点：

- `~/.codex/session_index.jsonl` 或 `~/.codex/state_5.sqlite` 有变化时
- `Indexer` 会把它当成全量重建信号
- 然后枚举 `codexSessionsPath` 下所有 `.jsonl`

对当前数据规模，这个代价非常高。

### 11. `[P1]` transcript 仍然是全文件解析 + 全量重写

相关代码：

- `Sources/VibeLight/Parsers/ClaudeParser.swift:10`
- `Sources/VibeLight/Parsers/CodexParser.swift:38`
- `Sources/VibeLight/Data/SessionIndex.swift:369`
- `Sources/VibeLight/Data/SessionIndex.swift:374`

问题点：

- JSONL 文件仍然通过 `String(contentsOf:)` 整份读入
- transcript 更新仍然是：
  - `DELETE FROM transcripts WHERE session_id = ?`
  - 再完整 `INSERT` 全部 transcript

对于 append-only 日志，这是结构性低效，不是简单调 SQL 参数能解决的问题。

### 12. `[P1]` 文件监听和索引变更处理仍然压在主队列 / 主 actor 上

相关代码：

- `Sources/VibeLight/Watchers/FileWatcher.swift:63`
- `Sources/VibeLight/Watchers/Indexer.swift:3`
- `Sources/VibeLight/Watchers/Indexer.swift:93`

问题点：

- FSEvents 仍然 schedule 在 `.main`
- `Indexer` 仍然是 `@MainActor`
- watcher 回调一进来就把 `handleChanges(...)` 拉回主 actor

结果：

- 文件解析
- 数据库写入
- live refresh
- UI 交互

这些路径会在同一条关键线程上竞争。

### 13. `[P1]` live session 刷新仍然每 3 秒做一轮系统级探测

相关代码：

- `Sources/VibeLight/Watchers/Indexer.swift:101`
- `Sources/VibeLight/Watchers/Indexer.swift:425`
- `Sources/VibeLight/Data/LiveSessionRegistry.swift:53`
- `Sources/VibeLight/Data/LiveSessionRegistry.swift:68`
- `Sources/VibeLight/Data/LiveSessionRegistry.swift:84`
- `Sources/VibeLight/Data/CodexStateDB.swift:199`
- `Sources/VibeLight/Parsers/TranscriptTailReader.swift:147`

这一轮刷新里仍然会混合：

- `ps` / `lsof` / 父进程遍历
- 读取 Codex sqlite
- tail 读 transcript
- 标题/状态推断

而这一切仍然是定时发生的，不是纯事件驱动。

### 14. `[P2]` 预览文件查找仍然走文件系统扫描路径，没有统一缓存服务

相关代码：

- `Sources/VibeLight/UI/SearchPanelController.swift:180`
- `Sources/VibeLight/UI/SearchPanelController.swift:230`
- `Sources/VibeLight/UI/SearchPanelController.swift:247`

问题点：

- Claude 预览会遍历 projects 目录找 `sessionId.jsonl`
- Codex 预览在精确路径失败后，会枚举 sessions 树并匹配文件名

这类扫描在 hover / selection 交互上尤其容易制造“滑动一下就迟钝”的体感。

### 15. `[P2]` preview 请求是 uncancelled detached task，selection 快速变化时可能堆积无效工作

相关代码：

- `Sources/VibeLight/UI/SearchPanelController.swift:180`
- `Sources/VibeLight/UI/SearchPanelController.swift:183`
- `Sources/VibeLight/Resources/Web/panel.js:123`
- `Sources/VibeLight/Resources/Web/panel.js:425`

问题点：

- 每次 preview 请求都会直接起一个 `Task.detached`
- controller 没有保存 task handle，也没有取消旧 preview task
- JS 侧除了 dwell 触发外，在预览中的 session `lastActivityAt` 变化时还会再次请求 preview

这意味着：

- 用户快速切 selection，或者 live session 活动频繁变化时，系统可能做出一串最终会被丢弃的 tail read / JSON 构建 / JS 更新准备工作。
- 结果可能不会显示错，但成本已经付出。

### 16. `[P2]` 每 60 秒的 title sweep 仍然会做全局 metadata 扫描，而且入口在主 actor 定时器上

相关代码：

- `Sources/VibeLight/Watchers/Indexer.swift:107`
- `Sources/VibeLight/Watchers/Indexer.swift:730`
- `Sources/VibeLight/Watchers/Indexer.swift:781`
- `Sources/VibeLight/Watchers/IndexingHelpers.swift:377`
- `Sources/VibeLight/Parsers/CodexParser.swift:4`

问题点：

- `titleSweepTimer` 每 `60s` 触发一次
- `runTitleSweep()` 会重新加载：
  - Codex `session_index.jsonl`
  - Claude 各项目的 `sessions-index.json`
- 这一步在进入 detached task 前就已经做了同步扫描

这不是当前最大的 blocker，但它说明系统里还存在另一类“定时全局扫一遍”的设计。

### 17. `[P3]` 状态栏 tooltip 仍然每 3 秒轮询 live session count

相关代码：

- `Sources/VibeLight/App/AppDelegate.swift:384`

问题点：

- `sessionCountTimer` 每 `3s` 查一次 `liveSessionCount()`
- 只为了刷新状态栏 tooltip

这不是主要性能瓶颈，因为查询很便宜。
但它仍然属于“系统在持续做并不急迫的轮询工作”。

## D. 不是主 blocker，但值得记账的问题

### 18. `[P3]` metadata 搜索路径仍然是全表扫描思路

此前测量显示：

- metadata-only 搜索当前依然够快
- 但 query plan 仍然偏向全表扫描并借助临时排序

这不是现在最该先打的问题。
但如果后续索引继续长大，它会从“没感觉”变成“开始有感觉”。

### 19. `[P3]` 破坏性 clear-all reindex 还会带来 SQLite 空间回收问题

相关代码：

- `Sources/VibeLight/Data/SessionIndex.swift:389`

这是一个推断，不是这轮实测过的主结论：

- `clearAllIndexedSessions()` 现在只是 `DELETE FROM transcripts` 和 `DELETE FROM sessions`
- 没有伴随 `VACUUM`

因此如果系统因为 source 切换反复做 clear-all + rebuild，数据库文件尺寸和碎片情况未必会跟着回落。
这不是当前最优先问题，但会放大“误触全量重建”的副作用。

## E. 近期已改善或已解决的问题

### 20. 搜索面板 resize 抖动和裁切问题有实质改善

相关代码：

- `Sources/VibeLight/UI/SearchPanelController.swift:171`
- `Sources/VibeLight/UI/SearchPanelController.swift:311`
- `Sources/VibeLight/Resources/Web/panel.js`

当前改进方向是正确的：

- resize 计划里加入了更稳定的 frame 计算
- 减少了不必要动画
- JS 侧也做了 resize 去重

### 21. 键盘上下选择的滚动稳定性改善了

相关代码：

- `Sources/VibeLight/Resources/Web/panel.js`

之前容易出现的滚动跳动，现在已经明显往正确方向修了。

### 22. path highlight 渲染修好了

相关代码：

- `Sources/VibeLight/Resources/Web/panel.js`
- `Sources/VibeLight/Resources/Web/panel.css`

这部分属于已修正的 UI 正确性问题。

### 23. 搜索面板 chrome 更接近 `DESIGN.md`

相关代码：

- `Sources/VibeLight/Resources/Web/panel.css`
- `DESIGN.md`

这轮已提交 commit 在 panel radius、spacing、icon radius、padding 等方面，确实是在往 design system 对齐。

### 24. 路径不再完全硬编码在 `~/.claude` / `~/.codex`

相关代码：

- `Sources/VibeLight/Settings/SessionSourceConfiguration.swift`
- `Sources/VibeLight/UI/SearchPanelController.swift`
- `Sources/VibeLight/Watchers/Indexer.swift`
- `Sources/VibeLight/Data/LiveSessionRegistry.swift`

这是方向正确的结构修复。
但它目前把“source resolution 的灵活性”接到了“过重的重建路径”上，所以收益被新的副作用抵消了一部分。

### 25. live-session 路径上已经有“部分降噪”，但还没有彻底解决

相关代码：

- `Sources/VibeLight/Watchers/Indexer.swift:470`
- `Sources/VibeLight/Watchers/Indexer.swift:509`
- `Sources/VibeLight/Watchers/Indexer.swift:880`
- `Sources/VibeLight/Watchers/Indexer.swift:943`

这轮代码里，至少有两点是正向变化：

- live-session 文件路径现在有一套 `sessionFileURLCache`
- health tail read 已经按文件 `mtime` 做了门控，不再无条件每 3 秒都读

但这还不是完整解法，因为：

- `updateLiveSessionTitle()` 里仍会持续抽取 `lastUserPrompt`
- `SearchPanelController` 仍有自己独立的无缓存扫描逻辑
- `findSessionFileStatic()` 仍为 title sweep 维持着第三套扫描实现

更准确的说法是：文件查找和 tail 读取已经开始局部优化，但系统级统一方案还没有完成。

## F. 进入 refinement plan 前，必须先拍板的 tradeoff

下面这些问题不先定，后面的 refinement plan 很容易写歪。

### 1. session source 切换是“即时生效”还是“草稿态 + Apply”？

当前问题：

- 只要切 mode，就可能立刻引发全局副作用。

需要决定：

- 方案 A：继续即时生效，但要极限收窄副作用，只在“有效路径真的变化”时才重建。
- 方案 B：改成草稿态编辑，只有点击 `Apply` 才真正切 source 和触发重建。

这个选择会直接影响：

- preferences 交互心智模型
- reindex 触发频率
- 实现复杂度

### 2. source 变化时，要不要先销毁旧索引？

当前问题：

- 现在是先清空再重建，风险最大。

需要决定：

- 方案 A：保持“立即清空旧索引”，实现简单，但用户会看到空窗期，且竞态风险更大。
- 方案 B：保留旧索引，等新 source 扫描完成后再原子切换，复杂一些，但体验和安全性更好。

### 3. 搜索面板里的 `Tab` 模式切换，是临时交互还是全局偏好？

当前问题：

- 现在 quick toggle 直接改全局设置，代价太大。

需要决定：

- 方案 A：`Tab` 只影响当前 panel / 当前会话，不持久化。
- 方案 B：`Tab` 继续持久化为全局偏好。
- 方案 C：Preferences 里的 toggle 是“默认值”，面板内 `Tab` 只是临时覆盖。

### 4. Preferences 要不要继续保留当前双栏大窗体设计？

当前问题：

- 现在的两栏设计方向不一定错，但 controller 已经明显变重。

需要决定：

- 方案 A：保留双栏 `Settings / About` 架构，但把 controller 拆小、把副作用收口。
- 方案 B：先回退到更小、更稳定的单页 preferences，优先把可用性救回来，再做视觉/结构升级。

### 5. custom root 无效时，系统应该“自动兜底”还是“显式报错并阻止应用”？

当前问题：

- 现在 invalid custom path 的状态表达不够明确，容易静默失败。

需要决定：

- 方案 A：无效路径时阻止 Apply，并给出明确错误状态。
- 方案 B：继续允许保存，但明确显示当前没有生效。
- 方案 C：自动 fallback 到 auto root，但必须显式告诉用户已经 fallback。

## 当前建议的阅读顺序

如果要快速定方向，建议先看这 5 件事：

1. `source mode 切换触发全量重建`
2. `先清库再停旧 indexer`
3. `500ms 定时搜索刷新`
4. `Codex 状态文件变化触发全量 reindex`
5. `Preferences 点不开但尚未复现`

这 5 个点决定了后面是先做“性能止血”，还是先做“preferences 可用性修复”，还是两者一起做。

## G. 当前已决定的方向

以下是当前已经拍板的 tradeoff，后续 implementation plan 会以这些为前提：

### 1. Session source 生效时机：`B`

- 结论：source 改动先进入草稿态，只有点 `Apply` 才真正切换并触发副作用。
- 含义：不能再出现“刚切 mode 就触发清库/重建”。

### 2. Claude / Codex source 配置模型：`B`

- 结论：Claude 和 Codex 各自独立选择 `automatic` / `custom`。
- 含义：不能再用一个全局 mode 同时绑住两个工具。

### 3. Source 切换时索引切换方式：`B`

- 结论：保留旧索引，后台建立新 source 的索引，完成后再原子切换。
- 含义：不接受“先清空旧索引，再重建”的空窗方案。

### 4. Custom path 无效时的处理：`C`

- 结论：如果 auto path 可用，就自动 fallback 到 auto path，并且必须明确提示用户已经 fallback。
- 含义：不允许静默失败。

### 5. 搜索面板里 `Tab` 切 history mode 的语义：`A`

- 结论：`Tab` 直接切换全局 mode，并保持到用户下一次再次按 `Tab` 为止。
- 补充约束：虽然是全局偏好，但实现上不能继续把这件事接到“整套 settings apply + hotkey 重建”上。

### 8. Weak title 更新策略：`B`

- 结论：只在索引变更、live 变更、或弱标题 session 命中时做增量更新，不保留每分钟全局扫一遍的老思路。

### 9. Preferences 修复路线：`B`

- 结论：先回到更小、更稳、更容易打开的单页 preferences。
- 含义：先救可用性，不先坚持当前双栏大窗体。

### 10. Preview 交互策略：`A`

- 结论：保留 dwell preview，不砍功能。
- 含义：主要修缓存、取消、扫描路径和无效工作堆积。

### 7. Live session / animation 刷新模型：`7B-1`

- 结论：绝大多数昂贵工作改成事件驱动，但当面板可见且存在 live session 时，保留一个 `0.5-1s` 的轻量快路径 tick。
- 约束：这个快路径只允许做轻量状态刷新，不允许做全量 reindex、整棵文件扫描、整棵 codex 枚举、全量重搜。
- 含义：保住 live 动画和状态新鲜度，但不能再用“高频做重活”的办法实现。

### 11. Preferences 保存模型：`11A`

- 结论：只有 source 相关设置走草稿 + `Apply`，其他轻量设置继续即时保存。
- 含义：单页 preferences 保持轻量，不把 theme / hotkey / history mode 也强行塞进 staged form。

### 12. 当 custom 无效且 auto 也不可用时的表现：`12B`

- 结论：保留旧索引和旧结果，同时显示 source 失效警告，直到用户修正。
- 含义：坏配置不会立刻把用户现有结果清空。

### 6. 搜索刷新模型：`live 轻量刷新 / history 不自动重搜`

- 结论：`history` 结果不因为时间流逝而自动重新搜索；`live` 结果允许在面板可见时走轻量刷新。
- 约束：这个轻量刷新只服务于 live session 的状态新鲜度，不允许退化成对 history / transcript FTS 的定时重搜。
- 含义：搜索系统按数据类型分层处理。
  - history：纯事件驱动
  - live：事件驱动为主，面板可见时允许轻量 tick

## H. 还没真正定下来的点

## I. 额外还值得现在就拍板的 tradeoff

当前没有新增必须先拍板的架构级 tradeoff。
进入 implementation plan 的前置决策已经齐了。

## J. QA Follow-up Resolution (2026-04-18 Night)

这一轮基于真实运行态 QA，又确认并修复了 3 个具体问题：

### 1. Preferences 顶部布局挤进 titlebar：已修复

- 现象：`Preferences` 首屏内容和窗口标题区、traffic lights 区域发生重叠。
- 根因：窗口使用了 `fullSizeContentView`，而内部 `scrollView` 又直接贴到了 `contentView.topAnchor`，导致内容实际进入 titlebar 区。
- 修复：改回标准 titled window，不再让 preferences 内容占满 titlebar。
- 验证：
  - 新增测试 `preferences content respects titlebar safe area`
  - 运行态截图确认顶部内容不再与 titlebar 重叠

### 2. Preferences reopen 后残留旧状态文案：已修复

- 现象：重新打开窗口时，底部还会保留诸如 `Diagnostics exported` 之类的旧状态。
- 根因：`showPreferences()` 没有清理 transient status。
- 修复：每次重新展示 preferences 时先清空 `statusMessage`，再刷新控件。
- 验证：
  - 新增测试 `reopening preferences clears transient status messages`
  - 运行态关闭再重开后，底部恢复默认说明文案

### 3. 从搜索面板按 `Cmd-,` 打开 Preferences 不可靠：已修复

- 现象：真实运行态下，打开搜索面板后按 `Cmd-,`，不会稳定弹出 `Preferences`。
- 根因：搜索面板自己的原生 key handling 只拦截了方向键 / `Esc` / `Enter` / `Tab`，没有显式处理 `Cmd-,`；而 menu bar app 又不能可靠依赖标准主菜单快捷键链路。
- 修复：在 `SearchPanelController` 的 panel-level key handler 里显式处理 `Cmd-,`，先关闭搜索面板，再直接调用 `openPreferences()`。
- 验证：
  - 新增测试 `command comma opens preferences from the search panel`
  - 真实运行态通过 menu bar 打开搜索面板后，`Cmd-,` 可直接拉起 `Preferences`
