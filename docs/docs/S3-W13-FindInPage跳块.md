# S3 · W13 FindInPage 第三件（跳块走 `AnchorRegistry` + 文本级高亮）（EXEC-SPRINT-02 / W13）

> **窗口**：EXEC-SPRINT-02 / W13 —— `EXEC-PLAN.md` §19.5 缺口 **#3 的第三件**（U2.4 FindInPage：跳块 + 文本级高亮）+ 解除 `FIND_IN_PAGE_BODY_READY` 占位封存
> **代码基线**：`5775f6a`（S3-W12 交付，已提交）→ 本窗口交付后**未提交**（见 §7）
> **设备**：模拟器 **`MateBook Pro`（2in1）**，`hdc` 目标 `127.0.0.1:5555`，窗口 1216×811 vp（截图 3120×2080）。**一台设备一个任务，本窗口独占** ✓（交还时仍在运行，见 §8）
> **夹具**：**自建新页 `未命名`**（32 块，其中两块含 ASCII 命中词 `w13needle` / `w13needleB`）—— 按 AGENTS §7c「vault 不可 shell 写 ⇒ 应用内构造」+ 用户约束「前窗口页面都已是夹具 ⇒ 自建新页」✓
> **交付改动**：**7 个文件**（1 新增 + 6 修改）

---

## 0. 结论速览

| # | 结论 | 证据等级 |
|---|---|---|
| **T1-1** | **计划原文核实**：文本级高亮**是计划明确要求**，原文在 **`PLAN-UI-Alignment.md (v1.md` §U2.4 第 3 条**：「匹配块内的**文本级高亮**沿用 SearchPanel 的 splitHighlight 段渲染（把匹配块临时切到高亮样式）」；验收在 §U2.4 末：「每次跳转**滚动+块高亮+块内文本高亮**；Esc 关闭」 | Ⓑ 文档原文逐字引用 ✓ |
| **T1-2** | ⚠️ **转述更正**：计划原文写的是 `AnchorRegistry.locate()`，而**本仓实现叫 `jump()`**（`AnchorRegistry.ets:109`）—— 全仓**没有** `locate()`。按语义对应到既有的 `jump()` ✓ | Ⓑ 源码 ✓ |
| **T1-3** | **跳块 + 块内文本高亮 + 块高亮三件全部落地并设备验收** ✓ —— 一帧截图同时呈现三者（§3.3） | Ⓐ 设备实测 ✓ |
| **T2-1** | **发现并修复一个使第三件「结构上不可能生效」的真缺陷** ✗→✓：`PageView.ets:254` **从未给 `BlockList` 传 `pageId`** ⇒ `@Prop pageId` 恒为 `''` ⇒ `FindInPage` 去 `getPageBlocks('')` 里搜 ⇒ **恒 0 匹配**（实测计数停在 `0/0`）。改为传 `this.pageUuidForDrag`（与 `BlockList.ets:452` 给 `BlockSelection` 修的是同一个坑） | Ⓐ 设备实测（修前 0/2、修后 1/2）✓ |
| **T2-2** | **发现 `Span.backgroundColor` 是静默无效 API** ✗：`SpanAttribute`（SDK `component/span.d.ts`）**没有** `backgroundColor`，只从 `CommonMethod` 继承同名方法 ⇒ **能编译、渲染层直接忽略**。改用 `textBackgroundStyle` 后底色才真的画出来（`#FEF08A` 命中像素 0 → 266）| Ⓐ 设备实测（像素扫描）✓ |
| **T2-3** | ⇒ 该缺陷**同时存在于 `SearchPanel` 的结果行高亮**（W2/U2.1b 起就一直是「只变字色、无底色」）⇒ 本窗口**一并修**（顺手加固，见 §5.2 / §9） | Ⓐ 设备实测（0 → 342 像素）✓ |
| **T3-1** | **占位封存已解除** ✓：`FIND_IN_PAGE_BODY_READY` 常量与占位分支**整体删除**（不是改成 `true` 留死分支）；实测 `callaite_findInPagePlaceholder` 节点 = **0** | Ⓐ 设备实测 ✓ |
| **T3-2** | **回归全绿**：`Ctrl+K` 385 190 px · `Ctrl+F` 1 188 841 px · `Ctrl+Shift+F` 88 609 px · **每一次 Esc 后与基线逐像素相同（0 px）**；键位隔离按 `id` 判定（Ctrl+F 不开页内搜索、Ctrl+Shift+F 不开全局搜索） | Ⓐ 设备实测（整屏像素差分）✓ |
| **T3-3** | **未做**：第 2 件后半「迁到 MainContainer 顶部 Stack」—— 本窗口**明确登记不做**（见 §9 W13-2） | Ⓑ 登记 ✓ |

---

## 1. 任务 1 · 计划原文核实（**用户要求：自己读，不要凭转述**）

**核实方法**：对 `Callaite-工作文档/` 全目录按字节读，检索 `U2.4` / `FindInPage` / `splitHighlight` / `高亮` / `MainContainer`。

### 1.1 文本级高亮：**计划明确要求** ✓（原文逐字）

`docs/PLAN-UI-Alignment.md (v1.md` 第 **322** 行（§U2.4「方案」第 3 条）：

> 3. navigatePrev/Next：matchedUuids[current] → `AnchorRegistry.locate()` + 高亮（复用 U2.1）；匹配块内的**文本级高亮**沿用 SearchPanel 的 splitHighlight 段渲染（把匹配块临时切到高亮样式）

同文件第 **326** 行（§U2.4「验收」）：

> **验收**：Ctrl+F → 输入 → Enter 循环跳转，每次跳转滚动+块高亮+块内文本高亮；Esc 关闭。

⇒ **三样判据是计划自己列的**：① 滚动（跳块）② 块高亮 ③ **块内文本高亮**。本窗口三者都验了（§3.3）。

### 1.2 迁 Stack：**计划要求，但属第 2 件** —— 本窗口不做

同文件第 **321** 行（§U2.4「方案」第 2 条）：

> 2. 渲染位置：从 BlockList 内联移到 MainContainer 顶部 Stack（ContentArea 之上，右上角浮动小卡，Obsidian 布局位）

另见第 **145** 行（U1.x 的同一诉求）：

> 3. `BlockSelection` 浮条当前挂在 BlockList 尾部 → 移到 MainContainer 顶部 Stack 层（与 FindInPage 同层），避免跟随滚动

⇒ 该项是 W12 §5.3 已登记的「第 2 件后半」，与本窗口的第 3 件**不同批**；本窗口按用户口径「可选，否则明确登记」处理 ⇒ **登记不做**（§9 W13-2）。

### 1.3 逐条裁定用户转述

| 转述 | 裁定 |
|---|---|
| 「跳块必须复用 Sprint-01 的 `AnchorRegistry` 单一入口，不要自己写滚动/定位」 | **与计划一致** ✓（原文 `AnchorRegistry.locate()`；本仓实现名为 `jump()`） |
| 「文本级高亮沿用 SearchPanel 的 splitHighlight」 | **逐字属实** ✓（§1.1） |
| 「迁 Stack 是可选」 | **计划里它是第 2 件（要求项）**，但 W12 已明确把它归入 Phase 3 overlay 重做批次；本窗口按「可选」处理并登记 ✓ |

---

## 2. 任务 2 · 实现（文件:行号）

| 文件 | 改动 | 关键行号 |
|---|---|---|
| **`utils/TextHighlighter.ets`**（**新增**） | 把 `SearchPanel.splitHighlight` 的算法**上移为单一实现** + 新增 `containsQuery` 谓词 | `:32` `splitHighlight` · `:70` `containsQuery` |
| `components\search\SearchPanel.ets` | `splitHighlight` 改为**委托**新 util（删本地 `TextSegment`，改用 `HighlightSegment`）⇒ 全仓**一套切分语义** | `:436` `return splitHighlight(text, query)` |
| `state\AppState.ets` | 新增两个 AppStorage 键 `callaite_findInPageMatchUuid` / `callaite_findInPageQuery`（`StorageKeys` + `STORAGE_KEYS` + `init()` 初值）；新增**唯一写入口** `setFindInPageHighlight` / `clearFindInPageHighlight`；`closeFindInPage` **顺带清高亮**（防「关不掉的底色」） | `:697` `closeFindInPage` · `:725` `setFindInPageHighlight` · `:731` `clearFindInPageHighlight` |
| `components\outliner\FindInPage.ets` | **删** `FIND_IN_PAGE_BODY_READY` 常量 + 占位分支；`performSearch` 发布高亮；新增 `currentMatchUuid` / `resolvePageName` / **`revealCurrentMatch`**（高亮 + `AnchorRegistry.jump`）；`navigateNext/Prev` 末尾调用它；`clearSearchState` 清高亮；给 `TextInput`/上/下/关四个控件补**稳定 id**（供 widgetId 通道验收） | `:221`/`:252`/`:273` 发布点 · `:227` `currentMatchUuid` · `:242` `resolvePageName` · `:267` `revealCurrentMatch` · `:275` `jump` · `:320` 占位分支已删 |
| `components\outliner\BlockView.ets` | 新增两个**只读响应式** `@StorageLink`（命中块 / 命中词，**刻意不挂 @Watch**，理由见下）；新增 `isFindHitSegment` 谓词 + `RenderSegment` 的**命中分支**（`Text(){ForEach(Span)}`，`textBackgroundStyle` 铺底色） | `:623` 字段 · `:733` `isFindHitSegment` · `:755` 命中分支（`textBackgroundStyle`） |
| `components\outliner\BlockList.ets` | **两处挂载点**把 `FindInPage({ pageId: this.pageId })` 改为 **`this.pageUuidForDrag`**（对症修复，见 §2.2） | `:313`（内嵌） · `:357`（整页） |
| `services\AnchorRegistry.ets` | `AnchorSource` 新增 `FIND_IN_PAGE = 'find-in-page'`（与全局搜索的模态语义区分；**不改定位算法**） | `:54` |

### 2.1 为何**复用** `AnchorRegistry` 而不是自己写滚动/定位（用户硬约束）

本仓 Sprint-01 已把「锚点跳转」分成**入口层 / 算法层**两层，里面沉淀了三个**只有踩过才知道**的坑；自写一套必然重踩：

| 坑 | 内容 | 自写会怎么错 |
|---|---|---|
| **陷阱 19** | `AppStorage` 里那个 `Scroller` **不是 `List` 绑定的那一个**：对它 `scrollToIndex` **不抛错也不滚动**。必须用 `BlockList` 在 `aboutToAppear` 自报的**直接引用** | 自写若从 AppStorage 取 Scroller ⇒ **静默不跳**，且「没抛错」会让人以为成功 ✗ |
| **陷阱 20** | `scrollToIndex` **异步生效**，且**切页后首帧会被静默忽略**（SDK `scroll.d.ts:489-490`：必须等数据刷新完成）⇒ `revealBlockDeferred` 的**幂等重试**（80ms/+240ms）就是为此而建 | 自写若「调用后立刻判成败」⇒ 误判失败；或只等一帧 ⇒ 跨页不跳 ✗ |
| **折叠祖先** | 目标块可能被折叠祖先藏住（下标 -1）⇒ 必须**先 `expandAncestors` 再算下标**（顺序反了会误报「不在大纲中」） | 自写几乎必错顺序 ✗ |

另有三条**契约性**理由：

1. **单一入口**：跳转的五件事（关不关来源面板 / 同页 vs 跨页 / 路由要不要跟着走 / 选哪个窗格 / 6 种降级怎么分派）全部收敛在 `AnchorRegistry.jump()`；本组件只提供 `blockUuid` + `source`，**不碰 Scroller、不写路由、不算下标** ✓
2. **降级不静默**：`jump()` 内部走服务自己的 `notifyIfFailed`（`scrolled`/`DEFERRED` 不提示，其余一律 toast）⇒ 本组件**不需要另写一套文案与判定**，避免两处口径漂移 ✓
3. **不传 `onDismiss`** 是**刻意的**：全局搜索面板（`AnchorSource.SEARCH`）带遮罩，跳转前必须关；而页内搜索条**不是模态**（内联在内容区顶部）⇒ 跳转后保持打开，用户才能连按 ↵ 逐个走（与右侧栏大纲/反链同一取舍）✓ 新增 `AnchorSource.FIND_IN_PAGE` 就是为了把这条语义差异显式记下来。

### 2.2 对症修复：`pageId` 恒为 `''`（**不修则第三件不可能生效**）

`PageView.ets:254` 构造 `BlockList` 时**只传了** `pageName` / `scroller` / `paneId`，**没传 `pageId`**：

```ts
BlockList({ pageName: this.displayName, scroller: this.blockScroller, paneId: this.paneId })
```

⇒ `BlockList.pageId`（`@Prop pageId: string = ''`）**恒为空串** ⇒ `FindInPage({ pageId: this.pageId })` ⇒ `collectAllBlocks('', true, …)` ⇒ `ws.getPageBlocks('')` ⇒ **0 个块** ⇒ **不论搜什么都 0 匹配**。

**这不是新坑**：`BlockList.ets:440-446` 已经为 `BlockSelection` 记录过**同一个坑**（并改用 `pageUuidForDrag`），只是 `FindInPage` 的两处挂载点没跟着改 —— 因为在 W13 之前**本组件从未可达**（W12 才接通入口，且当时交付的是占位形态），这条路径**从未被执行过**（陷阱 1 的「零引用/零执行代码藏着缺陷」同型）。

**修法**（最小面）：两处 `FindInPage({…})` 改传 `this.pageUuidForDrag`（`refreshBlocks()` 每次刷新都会同步它，`BlockList.ets:289`）。
**实测**：修前注入查询 ⇒ 计数恒 `0/0` ✗；修后 ⇒ `1/2` ✓（§3.1）。

> **未做的顺手清理** ✗：`BlockList.pageId` 这个 `@Prop` 现已无调用方读取（成为死字段）。**刻意不删** —— 删 `@Prop` 属组件对外契约变更，且 `PageView` 将来可能真的开始传它；本窗口只标注、不动（见 §9 W13-4）。

### 2.3 文本级高亮的落点（**唯一写入口 + 只读响应式**）

```
FindInPage.performSearch / revealCurrentMatch
      └─ AppState.setFindInPageHighlight(uuid, query)      ← 唯一写入口（写 2 个 AppStorage 键）
             └─ BlockView @StorageLink('callaite_findInPageMatchUuid' / 'callaite_findInPageQuery')
                    └─ isFindHitSegment(seg) ? Text(){ ForEach(splitHighlight(seg.text, query)) { Span(…).textBackgroundStyle(search_highlight) } }
                                         : Text(seg.text)  ← 原有路径逐字节未变
```

三条设计取舍：

1. **为什么走 AppStorage 而不是给 `BlockView` 加 `@Prop`** ✗：`BlockView` 由 `LazyForEach` 创建、键是 `row.uuid`，**结构性变更不重跑 `itemGenerator`** ⇒ 传参型 `@Prop` 会停在旧值上（AGENTS 陷阱 15，W10 已为此把 `depth` 从 `@Prop` 改成自读）。更关键的是：**命中块可能此刻根本不存在**（在视口外、被 `LazyForEach` 回收），它是**滚到那一行时才被创建**的 ⇒ 只有「全局可读的键」能覆盖这种实例（与既有 `callaite_highlightedBlock` 同一做法）✓
2. **为什么这两个 `@StorageLink` 刻意不挂 `@Watch`** ✗：本组件**每行一份**；若挂 `@Watch` 并在回调里 `refreshBlock()`，则**每次按键**都会让所有可见行重跑 `ContentRenderer.parse`（1000 块页面上是 O(可见行) 次 markdown 解析/键）⇒ 与 W8/W11 的性能红线（ANR）正面冲突。这里只把它们当**只读的响应式依赖**用在渲染分支上 ✓
3. **为什么 `RenderSegment` 里内联 `ForEach` 而不另抽带参 `@Builder`** ✗：W12 §11.1 的教训正是「**参数化 `@Builder` 内的 `ForEach` 不随实参变化重跑**」。这里让 `ForEach` 的数据源**直接读 `this.findQuery`**（响应式），并把分支判据也放在同一处，避免二次踩坑 ✓

**命中分支的样式逐项照抄下方 `else`**（fontSize / fontColor / fontWeight / fontStyle / decoration / fontFamily）⇒ 加高亮前后**字重字形完全一致**，差异只有命中词的底色 ⇒ 判据可**归因到高亮本身** ✓

---

## 3. 任务 2 · 跳块验收（**可观测判据 + 阴性对照**）

### 3.1 夹具（应用内构造，§7c）

| 步 | 动作 | 结果 |
|---|---|---|
| 1 | 侧栏 `file-plus`（widgetId `102`）⇒ `NewFileDialog` | 三选项对话框出现 ✓ |
| 2 | 点「新建大纲笔记」（widgetId `626`） | 新页 `未命名` 创建并打开（侧栏 3 个文件）✓ |
| 3 | 底部「添加」行 + 注入 `Enter(2054)` × 26 | **32 块**落盘 ✓（`grep -c '^- '` = 32）|
| 4 | 点第 13 行 ⇒ 编辑态 ⇒ `-fill "<RichEditor id> w13needleB"` | 磁盘出现 `- w13needleB`（第 13 行）✓ |
| 5 | （误注入）`uitest uiInput inputText` 落到第 1 行 | 该块变成 `w13needle` ⇒ **共 2 个命中**，正好用来验 `N/M` 与循环 ✓ |

> 夹具页 `未命名.md` = **114 B / 32 行**，MD5 `917a7ac74854a324b2b4c7a517ab6ff6`。

### 3.2 跳块前置态（**目标块确实在视口外**）

把 List 甩到底部后取 `-uiLayout`：

| 判据 | 实测 |
|---|---|
| `Text w13needle*` 节点 | **0 个** ⇒ 两个命中块**都在视口外** ✓ |
| 底部标记 `Text 添加` | 在 `top:1579` ⇒ List 已到底 ✓ |

### 3.3 阳性对照：点「下一个」⇒ **目标块真的进入视口** ✓

| 步 | 动作 | 观测 | 判定 |
|---|---|---|---|
| 0 | `Ctrl+Shift+F` ⇒ 点输入框 ⇒ 注入 9 个字母键 | `Text 1/2 [id:294]` | 2 个命中，当前第 1 个 ✓ |
| 1 | 点「下一个」（widgetId `298`） | 计数 **`1/2` → `2/2`** ✓ · **`Text w13needle` 出现在 `top:772`（= List 顶部）** ✓ · 底部 `Text 添加` **消失**（已滚出视口）✓ | **跳块成功** ✓ |
| 2 | 同一次跳转的整屏像素差分 | `bbox=(1200,703,1729,1624)` · **21 475 px** | 画面确实变了 ✓ |

**一帧截图同时给出计划要求的三样判据**（`crop 1195,760 → 2010,980`）：

| 计划验收项 | 图面证据 |
|---|---|
| **滚动（跳块）** | 命中行位于 **List 视口顶部**（跳前它在视口外、List 在底部） |
| **块高亮** | 整行铺 `#E3E5E8`（`surface2`）+ 左侧紫色色条 —— 像素扫描该区域 **12 986 px** ✓（`BlockAnchorService.flash()` 生效的直接证据）|
| **块内文本高亮** | 命中词 `w13needleB` 铺 `#FEF08A`（`search_highlight`）✓ |

> 像素判据量说明（验证纪律 2）：**不用「节点总数」**；用 ①`-uiLayout` 里命中块 `Text` 的 **`top` 坐标**（772 = 视口顶部，跳前不存在）②`添加` 行是否可见 ③整屏像素差分 ④按 `id` 查 `callaite_findHit_*` 是否存在。

### 3.4 阴性对照：点**非结果处**不动 ✓

| 动作 | 整屏像素差分 | 判定 |
|---|---|---|
| 点计数文本 `2/2`（`Text id:294`，**无 `onClick`**） | **`bbox=None` · 0 px** | **画面逐像素不动** ✓ |
| 同时核对 UI 状态 | 计数仍 `2/2`、命中块仍在 `top:772` | 无副作用 ✓ |

⇒ 「跳块是**点到结果**才发生的」这一因果被阴性对照钉住 ✓（对照 W12 的教训：只验阳性会把「本来就在视口里」误判成跳块成功 ✗ —— 本窗口**先**把 List 甩到底部再验，正是为了排除这一点）。

---

## 4. 任务 2 · 文本级高亮验收

### 4.1 FindInPage 的块内高亮 ✓

| 判据 | 修 `Span.backgroundColor` 之前 | 改用 `textBackgroundStyle` 之后 |
|---|---|---|
| 渲染树 `callaite_findHit_<uuid>` 节点 | 存在（分支确实走了）✓ | 存在 ✓ |
| 整屏扫描 `#FEF08A`（`search_highlight`） | **0 像素** ✗ | **266 像素** ✓（bbox 覆盖命中词区域）|
| 目视 | 命中词**无底色** ✗ | 命中词**黄色底色** ✓（见 §3.3 截图）|

### 4.2 根因（**一条可推广的 SDK 事实**）✗→✓

`component/span.d.ts` 的 `SpanAttribute` **没有** `backgroundColor`；它只从 `CommonMethod` 继承了一个**同名方法** ⇒ 写 `.backgroundColor(...)` **能通过编译**，但**渲染层直接忽略**（Span 不是独立渲染节点）。

* 正确 API：`Span.textBackgroundStyle({ color, radius })`（`span.d.ts` 内 `textBackgroundStyle(style: TextBackgroundStyle): T`，@since 11；本仓 `compatibleSdkVersion` 26）✓
* **对照实验**（决定性）：同一台设备上先用 SearchPanel（Ctrl+F）验 —— 它的 `Span` 也用 `backgroundColor`，实测命中词**只有字色变紫、没有底色**（`#FEF08A` = 0 像素）⇒ 证明这是 **API 静默无效**，而不是我新写的分支有问题 ✓

### 4.3 顺手加固：SearchPanel 的同族缺陷一并修 ✓

同一处缺陷自 W2/U2.1b 起就存在于 `SearchPanel.ResultItem` 的两个结果行（页面结果 + 块结果）。本窗口把两处也改为 `textBackgroundStyle`：

| 判据 | 修前 | 修后 |
|---|---|---|
| Ctrl+F 结果行 `#FEF08A` 像素 | **0** ✗ | **342** ✓ |
| 目视 | 命中词仅字色变紫 | 命中词**黄色底色 + 紫色字** ✓ |

> 这同时让计划 §U2.4 的「沿用 SearchPanel 的 splitHighlight **段渲染**（把匹配块临时切到高亮样式）」在**两处都不再是空话** ✓。

---

## 5. 占位封存解除

| 项 | 处置 |
|---|---|
| `const FIND_IN_PAGE_BODY_READY: boolean = false;` | **整段删除**（含其说明注释）✗→✓ |
| `build()` 的**占位分支**（`页内搜索：编辑器重铸后可用` + `Esc 关闭` + `callaite_findInPagePlaceholder`） | **整段删除** |
| `build()` 结构 | 由三分支（关 / 占位 / 本体）收敛为**两分支**（关 / 本体） |
| **实测** | `callaite_findInPagePlaceholder` 节点 **= 0**；`callaite_findInPageInput` / `Next` / `Prev` **= 2**（各出现 2 次：命中文本 + key 字段）✓ |

**为什么是「删」而不是「翻成 `true`」**：把常量改成 `true` 会让占位分支变成**编译期可证明的死代码**（`else if (!true)`），既留着无用分支、又给下一位读者留下「还有一个开关」的错觉。第三件既已完成，占位就应当**从代码里消失**，而不是被一个常量永久遮蔽 ✓（与 W12「保留实现、用常量封存」的**临时**决定配套：那个决定的原文就是「第 3 件做完时改一行」—— 现在做完了，且做得比「改一行」更彻底）。

---

## 6. 回归面（**整屏像素差分**，验证纪律 8）

判据 = 与**冷启动基线截图**逐像素差分（陷阱 12：浮层在独立子窗口，`dumpLayout` 文本检索**会假阴性** ✗ ⇒ 一律用像素差分 + 按 `id` 查节点）。

| 注入 | 与基线差分 | 按 `id` 查节点 | 判定 |
|---|---|---|---|
| **`Ctrl+K`**（快速切换） | `bbox=(1104,424,3114,1969)` · **385 190 px** | `commandPaletteInput`=2 · 其余 0 | **仍能打开** ✓（W12 同项 385 908 ⇒ 同一量级，未回归）|
| `Esc` | **`bbox=None` · 0 px** | — | 逐像素回基线 ✓ |
| **`Ctrl+F`**（全局搜索） | `bbox=(1104,424,3114,1969)` · **1 188 841 px** | `searchPanelInput`=2 · **`callaite_findInPage*`=0** | **仍能打开** ✓（W12 同项 1 190 001）· **且不属于页内搜索** ✓ |
| `Esc` | **`bbox=None` · 0 px** | — | 回基线 ✓ |
| **`Ctrl+Shift+F`**（页内搜索，**本窗口交付的本体**） | `bbox=(1192,671,1976,1624)` · **88 609 px** | `callaite_findInPageInput/Next/Prev`=2 · **`searchPanelInput`=0** · **`Placeholder`=0** | 打开**本体**（非占位）✓ · **未串到全局搜索** ✓ |
| `Esc` | **`bbox=None` · 0 px** | — | 回基线 ✓ |

**键位隔离**（用户要求「`Ctrl+F` 不属于它」）：由「按 id 查节点」双向钉住 ✓ —— `Ctrl+F` 时页内搜索节点为 0；`Ctrl+Shift+F` 时全局搜索节点为 0。

> ⚠️ **上表 `Esc` 行的前提**：三次 Esc 都是在「刚打开、焦点在搜索输入框」的状态下注入的 ✓。
> **边界**（本窗口新发现，见 §9 W13-5）：**先点过「上一个/下一个」按钮之后，Esc 不再关闭** ✗（实测输入框节点仍 = 1）；**点回输入框再 Esc 即关** ✓（2/2）。该边界**不是 W13 引入**（W12 只验过前一种情形），但由本窗口新增的按钮**暴露**出来 ⇒ 已登记。

**W2–W12 红线未受影响**（源码级核对，未复跑）：本窗口**未改** `OutlinerEngine` / `BlockTree` / `MarkdownExporter` / `IndexStore` / `DataStore` / `BlockEditor` / `WebEditor` 任何一个字节 ⇒ E13（撤销/重做落盘）与 E14（行刷新）代码路径与本窗口**零交集** ✓。
**未复跑**的项如实列出 ✗：E1–E20 中除上表四个浮层/面板与页内搜索自身外**均未复跑**（本窗口定位是「U2.4 第三件」，不是全量回归窗口）。

---

## 7. 编译与交付状态

| 项 | 结果 |
|---|---|
| 首次构建（改动后） | **`BUILD SUCCESSFUL in 11 s 89 ms`** ✓ |
| 末次构建（还原 §7b 注入后） | **`BUILD SUCCESSFUL in 6 s 904 ms`** ✓ |
| **§7b 对抗性检查**（证明**新增文件真的在编译图里**） | 向 `TextHighlighter.ets` 注入 `const __W13_TYPE_CHECK: number = 'deliberate-string';` ⇒ **构建失败**，报 `Type 'string' is not assignable to type 'number'. At File: …/utils/TextHighlighter.ets:20:7` ✓（撤销后复绿 ✓）<br>其余 6 个文件**不需要**该检查：它们的行为在设备上**直接变了**（计数 `0/0`→`1/2`、占位节点消失、底色出现）⇒ 「被编译并在运行」由**运行时行为**直接证明，强度高于注入法 ✓ |
| 安装 | `hdc install -r`（**未用 `uninstall`** ✓）· `updateTime` **前进** ✓：`1790765158634`（W12 交还）→ `1790766159849` → `1790766763904` → **`1790766914145`** |
| 行尾 | 7 个改动文件 **CRLF=0 / LF 归一** ✓（陷阱 10；本次 `edit`/`write` 未引入 CRLF，已逐文件字节级核对）|
| 探针残留 | 全仓 grep `W13PROBE` / `__W13_TYPE_CHECK` / `W12PROBE` = **0 命中** ✓ |
| 禁区 | **未触碰** `main_pages.json` · `rawfile/spike/*` · `rawfile/libs/**` ✓ · **未加任何页面级探针** ✓ · 启动链未插桩 ✓ |
| `git status --short` **前**（开工时） | **空**（= `5775f6a` 干净树）✓ |
| `git status --short` **后** | 恰好 **6 个 ` M` + 1 个 `??`**：`BlockList.ets` · `BlockView.ets` · `FindInPage.ets` · `SearchPanel.ets` · `AnchorRegistry.ets` · `AppState.ets` + **新增** `utils/TextHighlighter.ets` —— **无未跟踪产物、无探针** ✓ |
| 提交 | **未提交**（本窗口只交付到工作区 + 本报告；按纪律逐个列文件提交，**禁用 `git add -A/-u`**）|

---

## 8. 交还时的实例与 vault 状态

| 项 | 状态 |
|---|---|
| **实例** | **`MateBook Pro`（2in1）运行中** ✓ —— 本窗口**未换实例、未重启设备**（未触发陷阱 26 的场景）· **一次只跑一个实例** ✓ |
| **已装包** | 本窗口末版 · `updateTime=1790766914145` ✓ |
| **屏幕** | 应用停在前台（页 `未命名`；FindInPage **已关闭**、右侧栏反链面板开着）✓ · 设备曾处锁屏，已用 `power-shell wakeup` 唤醒 ✓ |
| **vault** | `2026-09-25.md` = **67 B / 9 块 / MD5 `972a9698d60e65e172de5fbfd6f95209`**（**与 W12 交还时逐字节相同** ✓）· `2026-09-30.md` = **3928 B / 1037 行 / MD5 `c6afe1bf6a3026b5c8563eaf58e15de1`**（W12 交还 3772 B ⇒ **期间又自增 156 B，本窗口未主动编辑该页** ✗，与 W11/W12 记录的「该页自己变大」同型，**未归因**）· **`未命名.md` = 114 B / 32 行 / MD5 `917a7ac74854a324b2b4c7a517ab6ff6`（本窗口新建的夹具页，未删除）** —— 三者**各复读两次一致** ✓（陷阱 24）|
| **vault 可写性** | 本窗口**未重跑** shell 写入阳性对照 ✗（沿用 W12：`touch` ⇒ `Permission denied`）；夹具全程走**应用内构造** ✓ |

---

## 9. 本窗口未闭合项（**登记，不写成通过**）

| # | 项 | 阻塞/理由 | 级别 |
|---|---|---|---|
| **W13-1** | **两侧文本级高亮只验到「查询词 = 单个 ASCII 字符 `w`」** ✗ | 注入通道的现实限制：`-fill` / `uitest uiInput text` **只写入 TextInput 的原生缓冲、不触发 `onChange`**（计数恒 `0/0`）；改用 `keyEvent` 逐键注入后 `onChange` 才触发，但**只有第 1 个字符进了 `this.searchQuery`**（后续字符留在原生缓冲里）⇒ 实测高亮的是 `w` 而非整串 `w13needle`。**产品逻辑本身对多字符串无特殊分支**（`splitHighlight` 是纯函数、已由 SearchPanel 的多字符路径间接覆盖），但**「多字符命中词的块内高亮」未取到设备证据** ✗ | Ⓐ 待真机 + 物理键盘终验 |
| **W13-2** | **FindInPage 第 2 件后半：迁到 `MainContainer` 顶部 Stack** | 计划 §U2.4 第 2 条要求；W12 已归入 Phase 3 overlay 协议重做批次，与本窗口第 3 件不同批 ⇒ **本窗口不做**（用户口径：可选，否则明确登记）| Ⓑ 待 Phase 3 |
| **W13-3** | **状态栏块数与磁盘行数不一致**：夹具页 `未命名` 磁盘 **32 行**（`grep -c '^- '`）/ 应用内状态栏 **20 块**（冷启动后与切页往返后**都是 20**，非瞬时陈旧）✗ | **未归因**：W13 未触碰解析 / 落盘 / 计数任一代码路径（`StatusBar.refreshStats` 读 `DataStore.getPageBlocks`）；**同机 `2026-09-25` 页计数 9/9 正确** ✓ ⇒ 疑与**连续空 `- ` 行**（本夹具全部由 `Enter` 注入、几乎全空）的装载/索引有关，也可能与 `2026-09-30.md` 的「自己变大」同源。**需要下一窗口单独定位**（判据：造一个每块都有内容的同规模页对照）| Ⓑ 待定位 |
| **W13-4** | `BlockList.pageId`（`@Prop`）在改为传 `pageUuidForDrag` 后**已无读取方**（死字段）| 刻意不删（删 `@Prop` 属对外契约变更；`PageView` 将来可能真的开始传它）| Ⓑ 待清 |
| **W13-5** | **`Esc` 关闭页内搜索条有焦点前提** ✗：**点过「上一个/下一个」按钮之后，Esc 不再关闭**（实测 TextInput 节点仍 = 1）；**先点回输入框再 Esc 才关** ✓ | 计划 §U2.4 验收写的是「Esc 关闭」（无前提）。**不是 W13 引入**：W12 的 Esc 证据同样是「刚打开、焦点在输入框」这一种情形（当时占位条无可聚焦子控件，等价于本窗口的 ②）。本窗口新增的上/下按钮引入了「焦点落在按钮上」这一新状态 ⇒ **暴露**了既有边界。根因（未深挖）：按钮点击后焦点不留在 FindInPage 的 `Row` 子树内，行级 `.onKeyEvent` 兜底落点因此收不到键 | Ⓐ 待修（可考虑给按钮 `.focusable(false)` 或把 Esc 兜底上移到宿主）|

---

## 10. 不可自证项（**如实列出**）

1. **`reject` / `scrollToIndex` 的实际下标的数值**：本窗口**没有**读 `currentOffset()`（无插桩，且用户禁止页面级探针）⇒ 「跳块」的判据是**目标块进入视口**（`top:772`）与**底部标记滚出**，**不是** offset 的数值 ✓。`scrollToIndex` 的**异步性**（陷阱 20）在本窗口表现为「点击后需等 2–3 s 再取图」，**未测最小生效帧数** ✗。
2. **注入键为何只有首字符进 `onChange`** ✗：现象已复现（`TextInput` 显示全串、`searchQuery` 只有 `w`），但**未归因**（2in1 的 IME 会「迟提交」—— 陷阱 21 ⑥；本窗口未跑 IME 阳性对照）。
3. **产品在真实键盘输入多字符查询时是否正常**：**未验** ✗ —— 只能由代码路径推断（`onChange` 是 ArkUI 标准通道，`SearchPanel` 的多字符结果行高亮在真实输入下历史可用）。**归入 W13-1**。
4. **`Span.backgroundColor` 在其它 SDK/设备上是否同样静默无效**：本窗口只在**本机 2in1 + API 26** 上证实 ✗；`span.d.ts` 的 API 面（无 `backgroundColor`）是**源码级**证据 ✓。
5. **状态栏 20 vs 磁盘 32 的根因** ✗：见 W13-3，未归因。
6. 本报告所有设备结论**只在 `MateBook Pro`（2in1 模拟器）成立** ✗；真机未验（= S3-5 口径）。

---

## 11. 对 AGENTS.md 的建议增补（供后续窗口决定）

1. **新增陷阱（SDK 静默无效）**：**`Span` 没有 `backgroundColor`** —— `SpanAttribute` 从 `CommonMethod` 继承了同名方法 ⇒ **能编译、渲染层忽略**。判据 = **像素扫描目标色**（`#FEF08A` 命中数 0 vs 266）；正确写法 `Span.textBackgroundStyle({color, radius})`。**同类可疑方法**（在 Span 上无渲染意义的 `CommonMethod`）建议一并排查。
2. **补强陷阱 1**：**「零执行的既有代码」同型于「零引用文件」** —— `FindInPage` 的两处挂载点从 W12 起就传着恒为 `''` 的 `pageId`，只因为该组件此前**从未可达**（占位封存）而从未暴露；**接线任何此前不可达的组件时，要把它传给它的每一个参数都对着上游核一遍**（本例 `PageView.ets:254` 没传 `pageId`，而 `BlockList.ets:440` 早已为同类问题留过注释）。
3. **§3 设备工作流增补**：`uitest uiInput text` / `emulator -fill` **只写 TextInput 的原生文本缓冲、不触发 ArkUI `onChange`** ✗ ⇒ 凡「输入框驱动搜索/过滤」的验收，**必须用 `uitest uiInput keyEvent <字母码>` 逐键注入**（`KEYCODE_A=2017`，字母 `= 2017 + (c - 'a')`，数字 `= 2000 + d`），并配「计数/结果节点是否变化」的阳性判据 ✓。
4. **§7c 补充**：本窗口**新建页面**的可行路线（无需 vault 写权限）：侧栏 `file-plus`（widgetId）⇒「新建大纲笔记」⇒ 底部「添加」行 + `Enter` 注入批量造块 ✓。

---

**维护规则**：本窗口的两项交付已按 §3 / §4 / §6 的设备判据闭合；**§9 的四项不得写成已通过** ✗，须随 `docs/待验收清单.md` 与 `docs/S3-回归矩阵-编辑器行.md` 一起清账。
