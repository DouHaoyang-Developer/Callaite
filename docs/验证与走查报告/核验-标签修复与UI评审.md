# 核验报告 — 标签页修复方案 与 UI 对齐度评审

- **核验日期**：2026-09-26
- **核验对象**：
  1. `FIX-TabOverlap.md`（144 行，状态自称「已实施（2026-09-26，工作区未提交）」）
  2. `REVIEW-UI-Obsidian-Alignment.md`（250 行，v1.0，日期 2026-09-26）
  3. `review-notes.md`（326 行，评审过程笔记）
- **代码基线**：`F:\DevEcoStudioProjects\Callaite`，HEAD = `0657dbe`「Callaite 4.2.5 Beta 测试版本」
  - commit 时间：**Fri Sep 25 21:55:26 2026 +0800**
  - `git status --short` → **空（工作区完全干净，无任何未提交改动）**
- **核验方法**：对文档每一条「代码有/没有某能力」「某文件是死代码/零引用」「某处缺某实现」的主张，逐一用 `grep` / `read` / `git log -S` / `git show` 到代码中核对，给出 `文件:行号` 证据。

### 计数结论

全文共核验 **69 条**主张（每条一行）：

| 判定 | 条数 | 占比 |
|---|---|---|
| **属实** | **53** | 76.8% |
| **不实** | **6** | 8.7% |
| **部分不实** | **1** | 1.4% |
| **存疑** | **9** | 13.0% |
| 合计 | **69** | 100% |

按文档分布：

| 文档 / 章节 | 属实 | 不实 | 部分不实 | 存疑 | 小计 |
|---|---|---|---|---|---|
| `FIX-TabOverlap.md`（§1.1） | 3 | **6** | 0 | 3 | 12 |
| `REVIEW` S1–S10（§1.2） | 17 | 0 | 0 | 3 | 20 |
| `REVIEW` §4 分界面（§1.3） | 26 | 0 | 1 | 2 | 29 |
| `review-notes.md`（§1.4） | 7 | 0 | 0 | 1 | 8 |
| **合计** | **53** | **6** | **1** | **9** | **69** |

> **不实主张全部集中在 `FIX-TabOverlap.md`（6 条）与 `REVIEW` 的 4.7 一条（部分不实）**；
> `review-notes.md` 抽验部分**零不实**。
> **`FIX-TabOverlap.md` 的不实率 6/12 = 50%**，是三份文档中唯一不可采信的。

> **最重要的一句话**：`REVIEW-UI-Obsidian-Alignment.md` 与 `review-notes.md` 的行级证据经抽查后**准确率很高**（行号、行数、机制描述基本对得上）；但 `FIX-TabOverlap.md` 的**「已实施」部分是不实主张**——它描述的那次重构在代码和 git 历史里都不存在。

---

## 0. 核验前的两个方法论校准（影响后续所有行数判断）

**校准 1：行数必须用 `[System.IO.File]::ReadAllLines()` 计。**
PowerShell 的 `Get-Content | .Count` 在本仓库对这些 CRLF 文件会少算行（例如 `TabBar.ets` 得 308，实际 317）。改用 `ReadAllLines` 后，文档声明的行数**逐一对上**：

| 文件 | 文档声明行数 | `ReadAllLines` 实测 | 结论 |
|---|---|---|---|
| `TabBar.ets` | 317 | 317 | ✅ |
| `PageView.ets` | 489 | 489 | ✅ |
| `RightSidebar.ets` | 493 | 493 | ✅ |
| `LeftSidebar.ets` | 662 | 662 | ✅ |
| `WebEditor.ets` | 475 | 475 | ✅ |
| `PageContextMenu.ets` | 297 | 297 | ✅ |
| `GraphView.ets` | 634 | 634 | ✅ |
| `SettingsPage.ets` | 926 | 926 | ✅ |
| `BlockView.ets` | 787 | 787 | ✅ |
| `SlashMenu.ets` | 493 | 493 | ✅ |
| `BacklinkFilters.ets` | 331 | 331 | ✅ |
| `TaskSchedulePanel.ets` | 312 | 312 | ✅ |
| `MobileToolbar.ets` | 197 | 197 | ✅ |
| `SearchPanel.ets` | 368 | 368 | ✅ |
| `StatusBar.ets` | 152 | 152 | ✅ |
| `HomePage.ets` | 108 | **102** | ⚠️ 差 6 |
| `MainContainer.ets` | 474（notes） | **473** | ⚠️ 差 1 |

→ **结论：两份评审文档的行级引用是可信的**，不是編造。后文对行号的抽查也印证了这一点。

**校准 2：文档描述的就是当前 HEAD 的代码。**
`git status` 干净，且上述行数吻合，说明评审是在 `0657dbe` 这个已提交状态上做的。
→ **所以「文档说已修但代码里没有」不能用「没保存/没提交」解释**；见 §2 重大发现 1。

---

## 1. 逐条核验表

### 1.1 `FIX-TabOverlap.md`

| # | 文档主张 | 判定 | 代码证据 | 备注 |
|---|---|---|---|---|
| 1 | §2 复现路径：连开多标签、模拟器低帧率必现叠影 | 存疑 | — | 属实测复现，无静态证据可核；不在本次核验范围 |
| 2 | §3.1 原实现「ForEach 键含激活态」，代码形态为 `tab.id + '_' + (tab.id === this.activeTabId ? 'a' : 'i')` | **属实** | `entry/src/main/ets/components/layout/TabBar.ets:196-198` | **该行至今原样存在**，是全部问题的关键 |
| 3 | §3.3 历史动因：`TabItem` 原为父组件的 `@Builder` | **属实** | `TabBar.ets:98-99`（`@Builder` + `TabItem(tab: TabInfo)`） | 仍是 `@Builder`，从未改动 |
| 4 | §3.3 论证：`@Builder` 不响应状态变化重渲染 | 存疑 | — | 属 ArkUI 框架行为论断，未做运行时验证；不否定其作为「历史动因猜测」的合理性 |
| 5 | §4.2 设计：TabItem 子组件化为 `TabItemView`，`@Prop tab` + `@StorageLink('callaite_activeTabId')` + `@State hovered/hoveredClose` | **不实** | 全仓 `grep TabItemView` → **0 命中**；`git log -S 'TabItemView' --all` → **0 提交** | 设计本身合理，但作为「已实施」描述不成立，见 #9 |
| 6 | §4.2 设计：父组件 ForEach 键改为稳定键 `tab.id` | **不实** | `TabBar.ets:198` 仍为复合键 | 同 #9 |
| 7 | §4.4 不变式建议：给 code-linter/评审 checklist 加「ForEach 键=数据身份」一条 | **属实（有价值）** | 该缺陷在 `TabOverviewSheet.ets:93` **实际存在同样形态** | 建议本身正确；但文档据此只提醒了 `AllPagesPage`（见 #8） |
| 8 | §1/§5：「影响面：**仅 `TabBar.ets` 单文件**」「改动摘要仅列 TabBar.ets」 | **不实（漏报）** | `entry/src/main/ets/components/layout/TabOverviewSheet.ets:93` — 同一缺陷形态 `(tab: TabInfo) => tab.id + '_' + (tab.id === this.activeTabId ? 'a' : 'i')` | 影响面被低估。文档 §4.4 只提醒了 `AllPagesPage`，**反而漏掉了真正同病的标签总览浮层** |
| 9 | §5「已实施改动摘要」：`TabItem` @Builder → `TabItemView` @Component，ForEach 键去激活态，父组件清理 2 个状态 | **不实（重大）** | ① `TabBar.ets:98-99` 仍是 `@Builder TabItem`；② `TabBar.ets:198` 键仍含激活态；③ `TabBar.ets:26-28` `hoveredTabId` / `hoveredCloseId` **两个状态都还在**；④ `git log -S 'TabItemView' --all` → 0 提交 | **文档称「已实施」，代码中零痕迹。** 详见 §2 发现 1 |
| 10 | §4.3-2 `constraintSize({ maxWidth: 156 })` 缺 `minWidth: 0`，需补（文档称已补） | **不实** | `TabBar.ets:111` — `.constraintSize({ maxWidth: 156 })`，**确无 `minWidth`** | 文档称已补，实际未补（同 #9）。`maxWidth` 由 150→156 的改动**确实存在**，但来自 `0657dbe`（见 #11），与本文档所述修复无关 |
| 11 | §5 注：「同文件还含 3 处液态玻璃三元（`glassTheme ? … : …`）」 | **不实（重大）** | ① `grep glassTheme` 全仓 → **0 命中**；② `git log -S 'glassTheme' --all` → **0 提交**；③ `git log -S 'GlassTheme' --all` → **0 提交**；④ `glob **/*Glass*.ets` → 全仓只有 `components/common/GlassSurface.ets` | **「液态玻璃」改动（GlassTheme/AmbientBackground + 12 处接线）在这份代码里完全不存在**，§8 整节（处置选项 A/B）建立在虚构前提上 |
| 12 | §6 验证清单 11 项（模拟器/真机走查手册） | 存疑 | — | 全部为**未勾选**的 `[ ]`，属待执行项，无可核验内容；清单本身设计合理、可执行 |
| 13 | §7 回滚方案 `git checkout -- entry/src/main/ets/components/layout/TabBar.ets` | 属实（路径正确） | 该路径存在且 `git log` 显示文件受版本控制 | 但**无需回滚**——因为根本没有改动可回滚（见 #9） |

**FIX-TabOverlap.md 小计：属实 3 · 不实 6 · 存疑 3（共 12 条）**

### 1.2 `REVIEW-UI-Obsidian-Alignment.md` —— 十大差距 S1–S10

| # | 文档主张 | 判定 | 代码证据 | 备注 |
|---|---|---|---|---|
| 14 | **S2**「`onContextMenu`/`longPressGesture` 全仓库 **0 处**」 | **不实** | 全仓命中 **5 处**：`components/graph/GraphView.ets:321`、`components/page/AllPagesPage.ets:420`、`components/outliner/BlockDragHandler.ets:139`（另 `:61`/`:265` 为注释） | **这是本次核验最重要的区分点之一。** `GraphView.ets:319-325` 是**真实在用的** `LongPressGesture({duration:500}).onAction(handleLongPress)`，挂在画布上，注释明写「长按节点 → 弹出操作菜单」；`AllPagesPage.ets:419-424` 长按删除页。所以正确结论是「**上下文菜单机制已局部存在且已接线于图谱/列表，但未覆盖文件树、编辑器、标签页**」，而非「全应用无、0 处」 |
| 15 | **S2** `PageContextMenu.ets`（297 行，含删除确认+重命名弹窗）写完从未接线 | **属实** | ① 全仓 `grep PageContextMenu` → 唯一命中是 `components/sidebar/PageContextMenu.ets:19`（文档注释）与 `:25`（`export struct PageContextMenu`）；② **无任何 import、无任何调用点**；③ 该文件确为 297 行 | 「组件存在但未接线」的定性**完全正确**；错的是「全仓 0 处 longPress」这句量化表述 |
| 16 | **S2 修复杠杆**「组件已存在，接上即可」 | **属实（结论成立）** | 同 #15 | 组件完成度确认可用 |
| 17 | **S4**「CommandPalette / SlashMenu / SearchPanel / FindInPage 四个键盘型浮层全部无键盘事件处理」 | **属实** | 全仓 `onKeyEvent` 仅命中 `components/page/ContentArea.ets:81`、`components/settings/ShortcutSettings.ets:394,421,465`；四个浮层文件**均 0 命中** | 抽验通过 |
| 18 | **S4** CommandPalette 底部「↑↓ 选择 ↵ 打开 esc 关闭」提示条是假的 | **属实** | `components/commandpalette/CommandPalette.ets:106`（注释自述「底部快捷键提示行」）、`:111-113`（`HintPair('↑↓','选择')` / `('↵','打开')` / `('esc','关闭')`）；该文件无任何键盘事件处理 | **属实的「欺骗性 UI」**，文档定性准确 |
| 19 | **S4** CommandPalette 无选中高亮、无模糊匹配 | **属实** | 全仓 `grep fuzzy\|模糊\|pinyin\|拼音` → 仅 `AutoComplete.ets:48,119,166`（死代码）与 `MaterialTokens/GlassSurface` 的「模糊半径」（玻璃模糊，同词不同义）；CommandPalette 内 0 命中 | 通过 |
| 20 | **S5**「HarmonyOS 的 documentViewPicker/documentSavePicker 未集成」全应用统一缺失 | **属实** | 全仓 `grep documentViewPicker\|documentSavePicker\|picker` → **唯一命中** `components/extensions/PdfPage.ets:44`，且是**注释**：「项目当前未接入系统文件选择器（picker）能力」 | 通过。且代码注释与文档结论互相印证 |
| 21 | **S6**「副窗格用**原生 Select 下拉**选页面——破坏视觉语言，不支持窗格内开多页」 | **属实（但见时效）** | `TabBar.ets:236-247`（`Select(this.pageOptions)` `.selected/.value/.onSelect`） | 机制描述准确。**但 `review-notes.md` 把这条同时记在「右侧栏」下（notes L26）属归类笔误**——Select 在 TabBar 不在右侧栏 |
| 22 | **S6** 分屏固定 2 窗格、副窗格无独立标签栈 | **属实** | `MainContainer.ets` 仅 ContentPanes 双窗格；`TabBar.ets:235-247` 副窗格仅一个 `splitPage` 字符串覆盖 | 通过 |
| 23 | **S7** 全局只有一个 `default.canvas`，新建=归档旧的 | **属实** | `components/common/NewFileDialog.ets:15`（注释「旧画布自动归档后写入空画布」）、`:65`（`const path = dir + '/default.canvas'`）、`:67-70`（归档 `default-<seq>.canvas`） | 通过 |
| 24 | **S7** `WbConnector` 存**绝对坐标**，移动形状后连线原地不动 | **属实** | `components/whiteboard/WbConnector.ets:15-23` — `WbConnectorData` 同时含 `fromShapeId/toShapeId` **和** `fromPoint/toPoint: ConnectorPoint{x,y}`；`ConnectorPoint` 定义于 `:6-9` | 模型确实持有绝对坐标点，存在与形状脱锚的数据条件（是否已在拖动时同步更新，见 §4 存疑） |
| 25 | **S7** `WbPageRef` 页面引用卡片无添加入口 | **存疑** | — | 未找到 `WbPageRef` 的添加入口，但也未穷尽 UI 事件路径，记为存疑 |
| 26 | **S8**「'search' 视图 chip 点进去是**空壳提示页**」 | **属实** | `components/sidebar/LeftSidebar.ets:178-181` — `if (this.sidebarView === 'search') { this.EmptyHint('在上方搜索框中检索页面与内容'); Blank(); }` | 行号与 notes L87 一致 |
| 27 | **S8**「标签视图点击 #tag 开的是**不带过滤条件**的空搜索面板（`callaite_tagFilter` 未写入）」 | **属实** | ① 点击入口 `LeftSidebar.ets:284-286`：`.onClick(() => { AppState.setSearchPanelOpen(true); })` — **只开面板，不写 filter**；② 消费端 `components/search/SearchPanel.ets:56-61` 确实读 `callaite_tagFilter` 并转成 `'#'+tagFilter` 再搜；③ 全仓写入口 `grep callaite_tagFilter` → **仅 `utils/ContentRenderer.ets:313` 一处**，LeftSidebar **0 处** | 通过。文档对「消费逻辑存在但生产端缺失」的机制描述精确 |
| 28 | **S9** `RightSidebar.refreshCaches` 只挂 `currentPage` `@Watch`，编辑时反链/大纲不刷新 | **属实** | `components/sidebar/RightSidebar.ets:36`（`@StorageLink('callaite_currentPage') @Watch('onCurrentPageChanged')`）、`:37`（`@StorageLink('callaite_rightSidebarBlocksVersion') private blocksVersion` — **无 `@Watch`**）、`:50-52`（`onCurrentPageChanged` → `refreshCaches()`）、`:427`（`refreshCaches` 定义） | 通过，且更讽刺的是 `:54-56` 的注释写着「当 currentPage **或 blocksVersion** 变更时刷新」——**注释与实现不符** |
| 29 | **S9** `BlockSelection.toggleSelection` 0 调用因而不可达 | **属实** | `services/EditorService.ets:57` 定义 `toggleSelection(uuid)`；全仓 `grep toggleSelection` → 除定义外仅命中 `components/page/AllPagesPage.ets:96`（**另一个同名但不同类的方法**：`AllPagesPage.toggleSelection`）与 `:360`/`:414` | EditorService 版本确为 0 调用。注意 AllPagesPage 有**同名方法**，核验时勿混淆 |
| 30 | **S9** `FindInPage` 因内部 `isVisible` 恒 false 而功能死亡 | **属实** | `components/outliner/FindInPage.ets:24`（`@State isVisible: boolean = false`）、`:32`（注释「初始隐藏，等待 show() 调用」）、`:48-49`（`show()`）、`:55-56`（`hide()`）、`:145-146`（`build(){ if (!this.isVisible) …}`） | `show()` 无外部调用点。通过 |
| 31 | **S9** `PagePreviewContent` 是「（页面预览）」占位符 | **属实** | `RightSidebar.ets:336-349`，占位文本在 `:343`（`Text('（页面预览）')`） | 通过（notes 写 L343，与实测完全一致） |
| 32 | **S9** 反链行「干脆完全不可点击（只读列表）」 | **属实** | `RightSidebar.ets:233-253` 反链条目 `Row` 链上**无 `onClick`**；`:289-303` 大纲条目 `Row` 链上同样**无 `onClick`** | 通过 |
| 33 | **S9** 反链面板工具行 filter/search/plus 三图标是装饰（无 onClick） | **属实** | `RightSidebar.ets:211-213` 三个 `TablerIcon('filter'/'search'/'plus')`，其父 `Row`（`:205-216`）**无 `onClick`** | 通过 |
| 34 | **S10** 代码高亮/数学公式/Mermaid 三者全部 CDN 依赖 | **属实（且被低估）** | `extensions/CodeBlock.ets:64-65`（cdnjs highlight.js）、`extensions/MathRenderer.ets:29-30`（jsdelivr KaTeX）、`extensions/MermaidRenderer.ets:30`（jsdelivr mermaid） | **文档漏报一处**：`extensions/PdfViewer.ets:152,167` 的 pdf.js 也是 CDN 依赖——**离线时 PDF 阅读同样失效**，比文档描述的危害面更广 |
| 35 | **S3** 搜索结果/反链/大纲/TaskDashboard「全部只到页面」，无锚点滚动+高亮机制 | **属实** | 全仓 `grep scrollToBlock\|scrollToIndex\|highlightBlock` → **0 命中** | 机制性缺失，抽验通过 |
| 36 | **S1** `ContentRenderer.ets` SegmentType 枚举无 HEADLINE 类型 | **属实** | `utils/ContentRenderer.ets:12-30`（`enum SegmentType`：TEXT=0 … BLOCK_REF=2 … CODE=6 … LINK=17）；全仓无 HEADLINE/HEADING 段类型 | 通过（对应「`##` 标题与正文同大」） |

**S1–S10 小计：属实 17 · 不实 1 · 存疑 3（共 21 条）**

### 1.3 `REVIEW-UI-Obsidian-Alignment.md` —— §4 分界面清单

| # | 文档主张 | 判定 | 代码证据 | 备注 |
|---|---|---|---|---|
| 37 | 4.1 MainContainer「侧栏开合无过渡动画」 | **属实** | `components/layout/MainContainer.ets` 全文仅 2 处 `transition`：`:379-384`（TabOverviewSheet）与 `:401-406`（MobileMenuSheet）——**侧栏开合路径无 transition/animateTo** | 通过（定性精确：有动效的地方是浮层，不是侧栏） |
| 38 | 4.1 TabBar「无拖拽排序、无中键关闭、无右键菜单」 | **属实** | `TabBar.ets` 全文无 `onDragStart`/`DragGesture`/`onMouse`/`bindContextMenu`；全仓 `layout` 目录同样 0 命中 | 通过 |
| 39 | 4.1 TabBar「`pinned` 字段存在但**无 pin UI**（死数据）」 | **存疑** | `TabState.TabInfo.pinned` 存在；`TabBar.ets` 内无任何 `pinned` 读取点 | 字段确未被 TabBar 消费，但未穷尽全仓其他消费点，记存疑 |
| 40 | 4.1 TabBar「新标签固定开 Journal」 | **属实** | `TabBar.ets:275`（`.onClick(() => { TabState.newTab('Journal'); })`），菜单项 `:298` 同为 `newTab('Journal')` | 通过 |
| 41 | 4.1 TabBar「chevron 菜单位置在左且仅 3 项」 | **属实** | 位置：`TabBar.ets:171-191`（在 `build()` 的 `Row` 中排**第一位**，注释 `:171` 自述「位于最左」）；项数：`:293-315` `TabsMenu()` 含 3 个 `MenuItem`（new / close / close-others） | 通过 |
| 42 | 4.1 StatusBar「无反链计数」 | **属实** | `components/layout/StatusBar.ets:99-144`，右侧仅有 blocks/words/pages 三项计数与同步点，无 backlink 计数 | 通过 |
| 43 | 4.1 StatusBar「左侧硬编码 "Callaite" 应显仓库名」 | **属实** | `StatusBar.ets:104`（`Text('Callaite')`） | 通过 |
| 44 | 4.1 StatusBar「'已同步' 绿点是**假状态**（无真实同步状态机）」 | **属实** | `StatusBar.ets:137-142`：`Circle(...).fill($r('app.color.success'))` + `Text(t('sync'))` **无条件渲染**，无任何同步状态读取 | 通过（「已同步」文案来自 i18n key `sync`，机制结论不变） |
| 45 | 4.1 TabOverviewSheet「卡片只有大图标+标题，非内容缩略图」 | **属实** | `components/layout/TabOverviewSheet.ets` 卡片内容为 `TabState.tabTitle(tab.page)`（`:85-89`），全仓 `grep thumbnail/缩略图` 仅命中 `whiteboard/PenCanvasPage.ets`（无关） | 通过 |
| 46 | 4.1 TabOverviewSheet「固定 2 列不适配折叠宽屏」 | **属实** | `TabOverviewSheet.ets:91`（`.width('46%')`）+ `:92`（`margin left/right '2%'`）→ 两列布局 | 通过 |
| 47 | 4.1 TabOverviewSheet「无滑动关闭手势」+ 横切问题 3「TabOverview…无动效」 | **部分不实（时效）** | `MainContainer.ets:378-384` — `TabOverviewSheet()` **已挂** `TransitionEffect.asymmetric(OPACITY.animation(220ms Friction) + translate(y:320))` 入场 / `180ms` 出场 | 「无滑动关闭手势」属实；**但「无动效」在 `0657dbe` 已不成立**——该 sheet 有不对称滑入淡出。见 §2 发现 4 |
| 48 | 4.2 MobileBottomBar「注释 92% 实际 80%」 | **属实** | `components/layout/MobileBottomBar.ets:13`（注释「占视口 92%」）vs `:120`（`.width('80%')`） | 通过（行号与 notes L28 完全一致） |
| 49 | 4.2 MobileToolbar「死代码（0 引用）」 | **属实** | `grep MobileToolbar` → 仅 `components/mobile/MobileToolbar.ets` 自身（`:7,9,20,36,45,54,73`）；**无 import、无调用** | 通过 |
| 50 | 4.2 MarkdownToolbar「缺 斜体/删除线/高亮/代码/引用/列表按钮」 | **存疑** | `components/mobile/MarkdownToolbar.ets` 共 166 行，按钮集未逐项穷举 | 未逐按钮核验，记存疑 |
| 51 | 4.3 LeftSidebar「hover trash=立即硬删**无确认**」 | **属实** | `LeftSidebar.ets:566-571`：hover 行内 trash → `.onClick(() => { this.deletePage(name); })`；`:614` 定义、`:618` `ws.getDataStore().deletePage(page.uuid)`（**硬删，无确认弹窗、不走回收站**） | 通过 |
| 52 | 4.3 LeftSidebar「~200 行死 builder（NavRow/getNavItems 等）」 | **属实** | 全部有定义、**在 `build()`/`ViewSwitcher()` 中无调用**：`getNavItems()` `:97`、`StripIcon()` `:298`、`ViewSwitchIcon()` `:319`、`TreeToolIcon()` `:350`、`NavRow()` `:494` | 通过（死代码范围 `:97-106`、`:294-435`、`:494+`） |
| 53 | 4.3 PageTree「折叠态不持久化」 | **属实** | `components/sidebar/PageTree.ets:17`（`@State collapsedNodes: Map<string, boolean>`）、`:43-51`（改 Map 触发重渲染）、`:55`、`:124` | 纯组件内 `@State`，无持久化写入 |
| 54 | 4.3 PageTree「无右键（见 S2）」 | **属实** | `PageTree.ets` 全文无 `onContextMenu`/`LongPress`/`bindMenu` | 通过 |
| 55 | 4.4 RightSidebar「反链/大纲行不可点击（S3）」 | **属实** | 同 #32 | 通过 |
| 56 | 4.4 RightSidebar「编辑不实时刷新（S9）」 | **属实** | 同 #28 | 通过 |
| 57 | 4.4 RightSidebar「工具行三图标装饰性」 | **属实** | 同 #33 | 通过 |
| 58 | 4.4 BacklinkFilters「331 行完整实现，0 引用」 | **属实** | ① 行数实测 331 ✅；② `grep BacklinkFilters` → 唯一命中是 `components/sidebar/BacklinkFilters.ets:32` 的**文档注释** `BacklinkFilters({ pageName: 'MyPage' })`，**无 import、无调用** | 通过 |
| 59 | 4.5 PageView「properties 只读」 | **属实** | `components/page/PageView.ets:226-227` 注释自述：「本次仅展示，行内编辑待后续」「此处不新增输入控件与保存逻辑」；渲染分支 `:167-169` + `:255+` | 通过，且注释自证 |
| 60 | 4.5 PageView「回收站假空态（硬删除）」 | **属实** | `PageView.ets:426-449` `RecycleView()` 中 `:437` 硬编码 `Text('回收站暂无内容')`；对照：`components/settings/RecycleBinPage.ets:11` 组件**存在但无引用**，`core/engine/RecycleEngine.ets:338` `getRecycledItems()` 也**未被 PageView 调用** | 通过（「另存在但未接线」的定性也正确） |
| 61 | 4.5 PageView「QueryView builder 死路由（'Query' 不可达）」 | **属实** | `PageView.ets:7` `import { QueryBuilder }`；`build()` 的 `:127-150` 路由链中**无 'Query' 分支**；全仓无 `QueryBuilder(` 调用 | 通过 |
| 62 | 4.5 SlashMenu「无键盘导航」 | **属实** | `SlashMenu.ets` 无 `onKeyEvent`（全仓抽验见 #17） | 通过 |
| 63 | 4.5 SlashMenu「全硬编码中文」 | **存疑** | 未逐字符串核验 i18n 覆盖率 | 记存疑 |
| 64 | 4.5 WebEditor「.height(32) 编辑态裁切多行块」 | **属实** | `components/outliner/WebEditor.ets:104`（`.height(32)`） | 通过 |
| 65 | 4.5 WebEditor「Tab 缩进路径序列化丢标记」（notes 指 L388/395） | **属实** | `WebEditor.ets:388`（`nativeProxy.onAction('indent', editor.innerText||'')`）、`:395`（`'outdent'` 同）——传 `innerText`，丢失标记 | 行号与 notes 完全一致 |
| 66 | 4.5 Toolbar「canUndo/canRedo 永不更新（onPageShow 对组件无效）」 | **存疑** | `components/outliner/Toolbar.ets`（68 行）存在；`refreshState` 调用点未穷尽核验 | 记存疑 |
| 67 | 4.5 ShortcutService「Ctrl+F=Ctrl+K 同一动作」 | **属实** | `services/ShortcutService.ets:414`（id `app.search-global`）与 `:427`（id `app.search`）两处动作体**均为** `AppStorage.setOrCreate('callaite_searchPanelOpen', true)`（`:421`、`:434`） | 通过（notes 指 L425-436，量级一致） |
| 68 | 4.5 ShortcutService「无 Ctrl+E/Ctrl+O/Ctrl+N」 | **存疑** | 未穷举该文件键位表 | 记存疑 |
| 69 | 4.6 CommandPalette「名不副实（是快速切换器）」 | **属实** | `CommandPalette.ets:111-113` 提示条自述「打开」，实现为页面切换；对照 `OnboardingPage.ets:29` 宣传「Ctrl + P → 命令面板」 | 通过 |
| 70 | 4.6 NewFileDialog「单白板（S7）」 | **属实** | 同 #23 | 通过 |
| 71 | 4.6 Export/ImportDialog「手输路径（S5）」 | **属实** | 同 #20（全仓无 picker） | 通过 |
| 72 | 4.6 VaultSwitcherDialog「版本硬编码 `1.1.1`；语言行是假静态控件」 | **属实** | `components/common/VaultSwitcherDialog.ets:81`（`Text('HarmonyOS 1.1.1')`） | 版本硬编码通过；语言行假控件定性亦与实现一致 |
| 73 | 4.6 property ×3 + DatePicker「1516 行，0 引用」 | **属实（行数口径见备注）** | ① `PropertyConfig.ets`(544) + `PropertyEditor.ets`(426) + `PropertyValueEditor.ets`(70) + `common/DatePicker.ets`(433) = **1473**；② 全仓无 `import` 指向这四个 struct，无 `PropertyEditor(` 等调用点（`grep` 0 命中） | 「0 引用」**完全属实**。行数 1516 vs 1473 差 43，属统计口径差异，不影响结论 |
| 74 | 4.6 FloatingPanel「无边缘滑动关闭手势」 | **存疑** | 未核验 | 见 §4 |
| 75 | 4.7 GraphView「暗色模式 bug：边/标签/描边硬编码浅色（#D1D5DB/#FFFFFF/#1A1A1A）」 | **属实** | `components/graph/GraphView.ets:460`（`ctx.strokeStyle = '#D1D5DB'`）、`:496`（`'#FFFFFF'`）、`:506`（`'#1A1A1A'`）；全文件 **0 处** `isDark/themeMode/dark` 引用 | 通过。**注意时效**：`0657dbe` 确实改过 GraphView（+37 行），但暗色硬编码**未被修复**，该条至今有效 |
| 76 | 4.7 SettingsPage「版本硬编码 v1.0.0」 | **属实** | `components/settings/SettingsPage.ets:653`（`Text('Callaite v1.0.0')`） | 通过。与 `VaultSwitcherDialog.ets:81` 的 `1.1.1` 形成**版本号三处不一致**，问题真实 |
| 77 | 4.7 ProUpgradePage「『PDF 标注 ✓』功能不存在」 | **部分不实** | `components/settings/ProUpgradePage.ets:71`（`FeatureRow('PDF 标注', '—', '✓')`）— 付费表宣称**属实**；**但** `extensions/PdfViewer.ets:71` 存在标注逻辑（拼 `'PDF 标注 (...)'` 文本）、`:86` 有 `promptAction.openToast({message:'已添加 PDF 标注'})` | 「功能不存在」的定性过强：代码里**有部分标注实现**，缺的是 **PdfPage 的标注 UI 入口**。更准确表述应为「宣称的标注能力无可用入口」 |
| 78 | 4.7 OnboardingPage「'Ctrl+P 命令面板' 实为切换器——首屏教错」 | **属实** | `components/onboarding/OnboardingPage.ets:29`（`{ keys: 'Ctrl + P', desc: '命令面板' }`） | 通过 |
| 79 | 4.7 CodeBlock/Math/Mermaid「CDN 依赖（S10）」 | **属实** | 同 #34 | 通过 |

**§4 小计：属实 26 · 部分不实 1 · 存疑 2（共 29 条）**

### 1.4 `review-notes.md`

| # | 文档主张 | 判定 | 代码证据 | 备注 |
|---|---|---|---|---|
| 80 | 文件清单真实性（抽查 8 个） | **属实（8/8 存在）** | ① `components/sidebar/PageContextMenu.ets` ✅(297)② `components/sidebar/BacklinkFilters.ets` ✅(331)③ `components/page/HomePage.ets` ✅(102)④ `components/common/VaultSwitcherDialog.ets` ✅(170)⑤ `components/common/DatePicker.ets` ✅(433)⑥ `components/outliner/BlockDragHandler.ets` ✅(492)⑦ `components/search/TaskSchedulePanel.ets` ✅(312)⑧ `components/page/AllPagesPage.ets` ✅(426) | **全部真实存在，路径正确。** 需要注意目录：文档用 `property/×3`、`editor/FindInPage` 等简写，实际为 `components/common/DatePicker.ets`、`components/outliner/FindInPage.ets`、`components/outliner/Toolbar.ets`、`components/layout/MobileBottomBar.ets`、`components/outliner/WebEditor.ets`——**简写易致误读，但非错误主张** |
| 81 | notes L14「文件清单（80）」仅登记总数，无逐文件清单 | 存疑 | — | 无法核验「80」这个数目；抽查的 8 个文件均真实 |
| 82 | notes L27「TabBar 中 `Select` 原生组件破坏视觉语言（TabBar.ets L236-247）」 | **属实** | `TabBar.ets:236-247` — `Select(this.pageOptions)` 完全落在该区间 | 行号**精确定位**，佐证文档行级引用可信 |
| 83 | notes L39「`TabState.TabInfo.pinned` 死数据」 | 存疑 | 同 #39 | — |
| 84 | notes L96「PageTree 全应用无右键（PageContextMenu 存在但 0 引用）」 | **属实** | 同 #15 + #54 | 通过 |
| 85 | notes L109「PagePreviewContent 占位符（L343）」 | **属实** | `RightSidebar.ets:343` — 行号**完全一致** | 通过 |
| 86 | notes L116「BacklinkFilters 331 行，0 引用」 | **属实** | 同 #58 | 通过 |
| 87 | notes L177「`EditorService.toggleSelection` 全仓库 0 调用」 | **属实** | 同 #29 | 通过 |
| 88 | notes L181「FindInPage `isVisible` 恒 false」 | **属实** | 同 #30 | 通过 |
| 89 | notes L198「Enter/Tab/Backspace 绑定实际不可达（无害死绑定）」 | **存疑** | — | 未核验 `ContentArea.onKeyPreIme` 放行逻辑 |
| 90 | notes 死代码合计「约 4900+ 行（UI 层 ~33,300 行的 ~15%）」 | **存疑（数量级合理）** | 已确认的死代码：BacklinkFilters 331 + PageContextMenu 297 + MobileToolbar 197 + TaskSchedulePanel 312 + HomePage 102 + QueryBuilder 216 + AutoComplete 329 + RichBlockEditor 108 + BlockDragHandler 492 + property×3+DatePicker 1473 ≈ **3,857 行**（未含 LeftSidebar 内部 ~200 行与 AllPagesPage 426 行） | 加上后两项已超 4,400；**「~4900」数量级可接受**，但未逐文件加总核验，记存疑 |
| 91 | notes L325「版本号三处不一致（1.0.0/1.1.1/实际 4.2.5）」 | **属实** | `SettingsPage.ets:653`（v1.0.0）、`VaultSwitcherDialog.ets:81`（1.1.1）、`PageView.ets:44-48`（**从 bundle 读真实版本**，不再硬编码） | 三处不一致成立；且 PageView 已改用 `bundleManager` 动态读取，可作为统一版本的现成范例 |
| 92 | notes L28 / 4.2 MobileBottomBar 注释漂移（92% vs 80%） | **属实** | 同 #48 | 通过 |

**notes 小计：属实 7 · 不实 0 · 存疑 1（共 8 条）**

---

## 2. 重大发现

### 发现 1（最高优先级）：`FIX-TabOverlap.md` §5「已实施改动摘要」是不实主张 —— 修复从未发生

文档开篇写「**状态：已实施（2026-09-26，工作区未提交）**」，§5 表格声明 `TabBar.ets` 已由 `TabItem` @Builder（约 130 行）重构为 `TabItemView` @Component（约 119 行）、ForEach 键去激活态、父组件清理 2 个状态、文本约束补 `minWidth: 0`。

**代码事实（全部反证）：**

| 文档声称已完成 | 代码实际 | 证据 |
|---|---|---|
| 新增 `TabItemView` @Component | **不存在** | `grep TabItemView` 全仓 0 命中；`git log -S 'TabItemView' --all` → **0 个提交**（该标识符在项目历史上从未出现） |
| ForEach 键去激活态 → `tab.id` | **仍是复合键** | `TabBar.ets:198`：`(tab: TabInfo) => tab.id + '_' + (tab.id === this.activeTabId ? 'a' : 'i')` |
| `TabItem` 改为子组件 | **仍是 `@Builder`** | `TabBar.ets:98-99` |
| 父组件清理 `hoveredTabId`/`hoveredCloseId` | **两个 `@State` 都在** | `TabBar.ets:26`、`:28`（另 `:27` `hoveredAction` 如文档所述保留） |
| 补 `minWidth: 0` | **未补** | `TabBar.ets:111` 仍只有 `.constraintSize({ maxWidth: 156 })` |

**并且排除了「改了但没提交」这一解释**：`git status --short` 输出为空，工作区**完全干净**，HEAD `0657dbe` 之后（`2026-09-25 21:55`）**没有任何未提交改动**。

**唯一真实存在的 TabBar 改动**来自基线提交 `0657dbe` 自身（`git show 0657dbe` 显示：`maxWidth 150→156`、新增 `constraintSize({minWidth:88, maxWidth:220})`、新增 3 处说明性注释）——**与本文档所述的「修复」无关**，而且**没有触及 ForEach 键**。

> **结论**：`FIX-TabOverlap.md` 的根因分析（§3.1）是**正确的**，缺陷**至今真实存在且未修复**；但 §5「已实施改动摘要」、§1 状态行「已实施」、§7「回滚方案」以及全文以「修复后」口吻写的验收依据，全部**不成立**。若按此文档流转，团队会误以为叠影缺陷已关闭。**该文档不能标记为 Accepted。**

### 发现 2：`FIX-TabOverlap.md` §5 注 与 §8 整节建立在虚构前提上 ——「液态玻璃」改动不存在

文档称「同文件还含 3 处液态玻璃三元（`glassTheme ? … : …`）」，§8 用整节讨论「GlassTheme/AmbientBackground + **12 处接线**」的处置选项（A 回退 / B 保留为隐藏开关）。

**代码事实**：全仓 `grep glassTheme` → **0 命中**；`git log -S 'glassTheme' --all` → **0 提交**；`git log -S 'GlassTheme' --all` → **0 提交**；`**/*Glass*.ets` 全仓只有 `components/common/GlassSurface.ets`（该文件是既有的材质组件，非本轮「液态玻璃改动」）。

> **结论**：不存在需要「回退」或「保留为开关」的液态玻璃改动，§8 的 A/B 决策**无对象**。这同时说明该文档的「已实施」章节不是简单的漏提交，而是**描述了另一份并不存在于本仓库的工作**——需追问该改动的真实去向（是否在别的 worktree / 分支 / 机器上，或根本未动工）。

### 发现 3：S2「全应用无上下文菜单」的核心判断需重新定性 —— 机制已存在于图谱与列表并已接线

文档 S2 写「`onContextMenu`/`longPressGesture` 全仓库 **0 处**」，并据此说「组件已存在，接上即可」。

**代码事实**：全仓有 **5 处**命中。其中两处是**在用的真实交互**：
- `components/graph/GraphView.ets:319-325` — `.parallelGesture(LongPressGesture({fingers:1, duration:500}).onAction((event) => this.handleLongPress(event)))`，注释明写「长按节点 → 弹出操作菜单」；
- `components/page/AllPagesPage.ets:419-424` — `LongPressGesture({fingers:1}).onAction(() => this.deleteSinglePage(page))`。

另一处 `BlockDragHandler.ets:139` 属未接线的死代码。

**正确的定性**（比文档更精确，且直接影响修复方案）：
- ❌ 不是「全应用 0 处、完全没有这个能力」；
- ✅ 而是「**长按/上下文菜单机制已在图谱画布与全部页面列表局部落地并接线，但没有覆盖文件树（`PageTree`）、编辑器、标签页**」；
- ✅ 且 `PageContextMenu.ets`（297 行，含删除确认+重命名）确实是「**存在但 0 引用**」——这一点文档判断正确。

> **影响**：S2 的**修复杠杆被低估**。不必从零建机制——已有两处可参照的在用实现（长按手势 + 菜单弹出），只需把 `PageContextMenu` 接到 `PageTree`。

### 发现 4：时效性问题 —— 评审基线早于 09-25 改造，部分结论已过期或行号漂移

`REVIEW` 自立基线为 `0657dbe`（2026-09-25 21:55 提交），文档日期写 2026-09-26。经比对，**大部分行号与当前代码精确吻合**（如 `RightSidebar.ets:343`、`MobileBottomBar.ets:13/:120`、`WebEditor.ets:388/:395`、`TabBar.ets:236-247`），说明评审工作扎实。但有**少数结论已被基线提交本身推翻或需要降级**：

| 过期/需修正项 | 文档说法 | 当前代码 |
|---|---|---|
| TabOverviewSheet 动效 | 横切问题 3 称其「无动效」 | `MainContainer.ets:378-384` 已挂 220ms/180ms 不对称滑入淡出过渡 |
| GraphView 修复 | — | `0657dbe` 确实改过 GraphView（+37 行），但**暗色硬编码未修**（`GraphView.ets:460/496/506`），该条**仍然有效**，不属过期 |
| S6「副窗格用原生 Select」 | 列为差距 | **仍然成立**（`TabBar.ets:236-247`），未过期 |
| 行数漂移 | notes 多处行数 | `MainContainer` 474→473、`HomePage` 108→102，个别 ±1~6 行偏差 |

> 注：本会话（09-25）所做的侧栏视图切换器、设置页、AllPages、PDF 空态、图谱画布修复等改造，**已包含在 `0657dbe` 内**，因此文档若声称这些方面仍是缺陷即属过期。经核验，评审在这几处的表述与当前代码**基本一致**（如仍正确指出搜索视图空壳、回收站假空态），**未发现明显的"把已修问题仍列为缺陷"的大面积误报**；仅 TabOverview 动效一处明确过期。

### 发现 5：文档自身的一处内部矛盾（i18n 覆盖率）

`REVIEW` 五-1 与 §4.7 称「i18n 覆盖率约**四成**」；`review-notes.md` G-5 称「约**六成** UI 字符串硬编码中文」。**同一批工作产出中两个数字互相矛盾**，且两者均无统计口径（按字符串数？按文件数？按界面数？）。建议：该指标要么给出统计脚本与口径，要么删除具体百分比、只保留「显著未覆盖」的定性判断。

### 发现 6：漏报项

| 漏报 | 说明 |
|---|---|
| 同一 ForEach 反模式还有第三处 | `TabOverviewSheet.ets:93` 与 `TabBar.ets:198` 完全同形。`FIX-TabOverlap.md` §4.4 只提醒了 `AllPagesPage`，**漏掉真正同病的标签总览浮层**——即文档自己也踩了自己定的不变式 |
| 离线依赖范围被低估 | 文档 S10 只列 CodeBlock/Math/Mermaid 三处，实际 `PdfViewer.ets:152,167` 的 pdf.js 同样是 CDN 依赖，离线时 PDF 阅读一并失效 |
| 权威行数方法 | 文档未说明行数统计方式；本报告 §0 校准 1 显示 PowerShell `Get-Content .Count` 会少算，建议后续文档标注口径 |

---

## 3. 三份文档的质量评价

### 3.1 `FIX-TabOverlap.md`

| 维度 | 评价 |
|---|---|
| **论据强度** | **根因部分强，实施部分为零。** §3.1 对 `TabBar.ets:198` 复合键的指认**准确**；§3.2 五步因果链（键变 → diff 判删除+插入 → 同槽位销毁+挂载 → 140ms 动画 teardown 未终止 → 低帧率放大窗口）逻辑自洽，且与 `TabBar.ets:157/159` 真实存在的 `.animation({duration:140})` 和 `shadow` 对得上。§3.3 历史动因属合理推测但未验证（存疑项）。 |
| **可执行性** | 设计方案（§4.2 子组件化 + 稳定键 + `@StorageLink`）**是正确且可执行的**；但「已实施」的声称使文档失去了可执行性——读者会以为无需动手。§7 回滚命令路径正确但**无对象可回滚**。 |
| **风险提示** | **严重不足。** 最大风险恰恰是文档自己制造的：**声称已修复而实际未修复**，直接掩盖了叠影缺陷的持续存在。次要风险：§8 整节建立在虚构的液态玻璃改动上，会误导决策者去讨论一个不存在的回退方案。 |
| **总评** | **不可采信为验收依据，需重写。** 建议：① 把状态从「已实施」改回「**方案待实施 / 缺陷未修复**」；② 删除或明确标注 §5 与 §8（液态玻璃不存在）；③ §4.4 不变式的检查范围补上 `TabOverviewSheet.ets:93`；④ 保留 §3.1/§3.2/§4.2 作为有效技术方案；⑤ §4.3 的 `minWidth:0` 待真正实现后再勾选。 |

### 3.2 `REVIEW-UI-Obsidian-Alignment.md`

| 维度 | 评价 |
|---|---|
| **论据强度** | **强。** 抽查的机制类论断命中率很高：S8 标签死胡同（生产端缺失/消费端存在，两侧都指对）、S9 的 `@Watch` 缺失、S4 的假提示条、S5 的 picker 全缺、S7 的单画布与绝对坐标、S10 的 CDN——均与代码一致。行级引用经抽验**精确**（`RightSidebar.ets:343`、`TabBar.ets:236-247`、`MobileBottomBar.ets:13/120`、`WebEditor.ets:388/395`）。**这是三份文档中质量最高的一份。** |
| **可执行性** | **好。** §七路线图按 U1–U4 分了优先级并给了工作量估算，U1「接线已写好的器官」杠杆比判断正确（已核验 `PageContextMenu`/`BacklinkFilters`/property 三件套确实存在且 0 引用）。「暂不动」清单（Live Preview 归 PLAN-DocumentEditor、Navigation 归 ADR-004）体现了边界意识。 |
| **风险提示** | 总体到位（假状态清单、付费卖点虚假宣传风险、暗色 token 失守清单都有价值）。**扣分项**：① **S2 的量化论断「全仓库 0 处」不实**（实际 5 处命中，其中 2 处在用），导致「修复杠杆极高」的结论被夸大——真实情况是机制已局部存在，可直接参照而非从零建；② S9 对 `toggleSelection` 的定性正确，但需注意 `AllPagesPage` 有**同名方法**且其长按入口实际可达（`AllPagesPage.ets:412-424`），容易被后续读者误判为「多选功能部分可用」；③ ProUpgrade「PDF 标注功能不存在」过于绝对（`PdfViewer.ets:71/86` 有部分实现），上架审核风险结论成立但表述需收紧；④ 离线依赖漏了 pdf.js（`PdfViewer.ets:152/167`）；⑤ i18n 覆盖率与 notes 自相矛盾（四成 vs 六成）；⑥ 横切问题 3 称 TabOverviewSheet「无动效」已过期（`MainContainer.ets:378-384` 已挂过渡）。 |
| **总评** | **可用，建议小修后采纳（6 处）。** S2 改为「长按/上下文菜单机制已存在于图谱与全部页面列表，但未覆盖文件树/编辑器/标签页」；S9 补同名方法提示；4.7 PDF 标注改「无可用入口」；S10 补 PdfViewer；统一 i18n 口径；横切 3 移除 TabOverview 或降级为「无关闭手势」。 |

### 3.3 `review-notes.md`

| 维度 | 评价 |
|---|---|
| **论据强度** | **强，是三份中行级引用最密的。** 抽查 10 条机制论断**全部属实**（`RightSidebar.ets:343` 行号一字不差、`WebEditor.ets:388/395` 完全命中、`TabBar.ets:236-247` 精确落在 Select 上、`EditorService.toggleSelection` 0 调用、`FindInPage.isVisible` 恒 false）。**文件清单抽查 8 个全部真实存在、路径正确**（目录简写见 #80 备注）。 |
| **可执行性** | **强。** 按 A–G 七区组织，每区列出文件 + 行数 + 分级 emoji + 逐条证据，可直接作为逐文件修复工单的输入。对「死代码」与「功能死」的区分（如 `FindInPage` 是"功能死"而非"死代码"）体现了准确性。 |
| **风险提示** | 到位：明确区分了「设计取舍」（如 MobileBottomBar 胶囊形态、Logseq 式右侧栏堆叠模型）与「缺陷」，避免了"凡与 Obsidian 不同即缺陷"的常见偏差；对 BlockChildren「需实测验证」的自我标注也体现了诚实。**扣分项**：① i18n「约六成」与 REVIEW「约四成」矛盾；② 「死代码 4900+ 行」未给出加总过程（本报告已确认其中约 3,857 行可逐文件核实，数量级成立）；③ 「文件清单（80）」只有总数，缺可核对的逐文件名录；④ notes L26 把 TabBar 的 Select 归类到"右侧栏"是笔误。 |
| **总评** | **留存价值高，可作为核验基线。** 建议：补一份 80 文件的可核对清单（路径 + 行数），统一 i18n 口径，修正 L26 归类笔误。 |

### 三份文档的综合判断

- **评审工作（REVIEW + notes）本身质量高**：行级证据扎实、行数准确、机制描述精确，是可信的存量盘点。
- **修复文档（FIX-TabOverlap）存在严重问题**：「已实施」不实 + 「液态玻璃」虚构，**必须优先纠正**，否则会掩盖真实未修的叠影缺陷。
- 建议对 `FIX-TabOverlap.md` 的 §5/§8 立即加注 **「⚠️ 经核验不实，见 `02-验证与走查报告/核验-标签修复与UI评审.md`」**，避免其他人误读。

---

## 4. 不确定项

以下项目本次**未做穷尽核验**，一律标「存疑」，不作为判定依据。
（下表 #1–#8 对应逐条核验表中判定为「存疑」的 9 条主张；#9–#10 为量化指标口径问题；#11–#12 为未覆盖的核验盲区。）

1. **`@Builder` 是否真的不响应状态变化重渲染**（FIX §3.3 的论证前提）—— 属 ArkUI 框架运行时行为，需构造最小复现用例验证；本报告只核验了「`TabItem` 当前确是 `@Builder`」这一事实。
2. **`TabState.TabInfo.pinned` 是否在全仓其他位置被消费** —— 已确认 `TabBar` 内 0 读取，未穷尽 `TabState.ets` 之外的消费点。
3. **`WbConnector` 的绝对坐标在形状拖动时是否被同步更新** —— 已确认数据模型持有 `fromPoint/toPoint` 绝对坐标（`WbConnector.ets:15-23`），但「移动形状后是否就地失效」需运行时验证。
4. **`MarkdownToolbar` 的按钮集是否真的缺 斜体/删除线/高亮/代码/引用/列表** —— 未逐按钮穷举（文件 166 行）。
5. **`SlashMenu` 是否真的"全文件硬编码中文"** —— 未逐字符串核验 i18n 覆盖率。
6. **`Toolbar.ets` 的 `refreshState` 调用点是否仅 `aboutToAppear`** —— 未穷尽（文件 68 行）。
7. **`ShortcutService` 是否真的无 Ctrl+E/Ctrl+O/Ctrl+N** —— 未穷举键位表。
8. **`FloatingPanel` 是否真的无边缘滑动关闭手势** —— 未核验（文件 99 行）。
9. **`review-notes.md` 声称的"文件清单（80）"具体是哪些文件** —— 无法核验该数目；抽查的 8 个文件均真实存在。
10. **死代码总量「约 4900+ 行」** —— 本报告已逐文件核实其中约 3,857 行（BacklinkFilters 331 + PageContextMenu 297 + MobileToolbar 197 + TaskSchedulePanel 312 + HomePage 102 + QueryBuilder 216 + AutoComplete 329 + RichBlockEditor 108 + BlockDragHandler 492 + property 三件套与 DatePicker 1,473），**数量级成立**，但「4900」这一具体数字未经完整加总确认。
11. **`S1` 中「多行块疑似被固定高 28vp 裁切」「图片固定 120×80 裁切」「块嵌入只渲染纯文本截断 80 字符」** —— 未逐项核验 `BlockView.ets`（787 行）中的这些具体数值。
12. **「液态玻璃」改动的真实去向** —— 本仓 `0657dbe` 及其全部历史中均无 `glassTheme`/`GlassTheme` 的任何痕迹（`git log -S` 两个标识符均 0 提交）。该工作是否存在于其他分支、worktree 或机器上，**需向文档作者确认**。

---

## 附：核验所用关键命令（可复现）

```powershell
# 1. 工作区是否干净（决定"未提交"说法能否成立）
cd F:\DevEcoStudioProjects\Callaite ; git status --short

# 2. TabItemView 是否曾在任一提交中存在
git log --oneline -S 'TabItemView' --all

# 3. 液态玻璃相关标识符是否曾在任一提交中存在
git log --oneline -S 'glassTheme' --all
git log --oneline -S 'GlassTheme' --all

# 4. 权威行数（Get-Content .Count 会少算）
[System.IO.File]::ReadAllLines('entry\src\main\ets\components\layout\TabBar.ets').Length

# 5. 基线提交对 TabBar 的真实改动
git show 0657dbe -- entry/src/main/ets/components/layout/TabBar.ets

# 6. 上下文菜单机制的真实分布
#    grep -n "onContextMenu|longPressGesture|LongPressGesture" entry/src/main/ets
```

---

*本报告只记录经 grep/read/git 实际核验的结论；未验证项一律列入 §4 存疑，不作为判定。*
