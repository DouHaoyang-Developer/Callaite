# S3 · W12 反链刷新与 FindInPage 可达性（EXEC-SPRINT-02 / W12）

> **窗口**：EXEC-SPRINT-02 / W12 —— `EXEC-PLAN.md` §19.5 M3 缺口 **#4（遗留 1：右侧栏反链列表切页刷新）** + **#3 的前两件（U2.4 FindInPage：显隐统一 + 挂载层/触发源）**
> **代码基线**：`fdc5947`（S3-W9 交付）→ 本窗口交付后 **未提交**（见 §7 交付状态）
> **设备**：模拟器 **`MateBook Pro`（2in1）**，`hdc` 目标 `127.0.0.1:5555`，窗口 1216×811 vp（截图 3120×2080）。**一台设备一个任务，本窗口独占** ✓（交还时仍在运行，见 §8）
> **夹具**：`2026-09-25.md` = **67 B**（9 块）·`2026-09-30.md` = **3538 B**（1023 块）⇒ 两者反链数 **0 / 1**，**天然满足「切到一个反链不同的页」** ✓
> **交付改动**：**5 个文件**，+237 / −66

---

## 0. 结论速览

| # | 结论 | 证据等级 |
|---|---|---|
| **T1-1** | **根因不是「版本号没传下去」，而是「参数化 `@Builder` 里的 `ForEach` 不随参数变化重跑」** —— 计数行（直接读 `@State`）**切页后正确更新**，而列表（`@Builder BacklinkList(filtered)` 内的 `ForEach`）**不更新** ⇒ 形成「计数 1 / 列表空」或「计数 0 / 列表 1」的自相矛盾画面 | Ⓐ 设备实测（截图 + `dumpLayout` 双证）✓ |
| **T1-2** | **W8 的 `@Prop @Watch dataVersion` 机制本身是好的** —— 插桩实测切页后它**确实跑到了**、`@State backlinks` **确实刷新了**（`BF.watch page=2026-09-25 raw=0`）⇒ 缺口**只在渲染层那一个 `@Builder`** | Ⓐ 设备实测（hilog 插桩）✓ |
| **T1-3** | 修法 = **把列表内联进 `build()`**，让 `ForEach` 直接依赖 `@State`（数据源与计数行同源）。**不新造版本号、不改 `keyGenerator`** | Ⓐ 设备实测（阳性 4 轮 + 阴性对照）✓ |
| **T2-1** | **计划原文核实**：`Ctrl+Shift+F` 那句**不在 `EXEC-PLAN.md`**，而在 **`docs/PLAN-UI-Alignment.md (v1.md` §U2.4 延后理由**（原文见 §4）。用户的转述**基本准确**，但**出处需要更正** | Ⓑ 文档原文逐字引用 ✓ |
| **T2-2** | **显隐统一完成**：删掉 `FindInPage` 自己的 `@State isVisible`，与宿主 `BlockList` **共用** `AppStorage['callaite_findInPageOpen']`（唯一写入口 `AppState.open/closeFindInPage`）——与 Sprint-01 W12 的 SlashMenu 同一约定 | Ⓐ 设备实测 + Ⓑ 源码 ✓ |
| **T2-3** | **可达性完成**：`Ctrl+Shift+F` 已注册并**设备实测可打开**（占位条显示「页内搜索：编辑器重铸后可用」+「Esc 关闭」），**Esc 可关**（4/4） | Ⓐ 设备实测（含阴性对照）✓ |
| **T2-4** | **第 3 件（跳块走 `AnchorRegistry` + 文本级高亮）明确未做** ⇒ 以 `FIND_IN_PAGE_BODY_READY = false` 常量**显式封存**，占位形态交付（见 §5.3） | Ⓑ 源码（刻意留空）✓ |

---

## 1. 任务 1 · 复现（**先复现，再改码**）

### 1.1 夹具构造（`vault` 不可 shell 写 ⇒ 走应用内构造，AGENTS §7c）

**写入阳性对照**（必做，§7c 要求）：

```
$ hdc shell "ls -ld <vault>/graph"
drwxrwxrwx 2 20020050 20020050 4096 ... graph        ← 权限位看似可写
$ hdc shell "touch <vault>/graph/__w12_probe.md"
touch: '.../__w12_probe.md': Permission denied        ← 实测被拒 ✗（SELinux）
```

⇒ **§7c 的「不可 shell 写」前提在本机仍成立** ✓（与 W6/W7 一致）。

**改用应用内构造**（`-click <widgetId>` 通道 + `-fill`）：

| 步 | 动作 | 结果 |
|---|---|---|
| 1 | `emulator -instance 'MateBook Pro' -click 445`（底部「添加」行） | 磁盘 **50 → 53 B**（`\n- ` ✓ +3 B/块） |
| 2 | 点新块进编辑态（`RichEditor [id:464]`） | — |
| 3 | `-fill "464 [[2026-09-30]]"` | UI 出现 `RichEditor [[2026-09-30]]`；磁盘 **53 → 67 B** |

⇒ 夹具达成：**`2026-09-25` 引用 `2026-09-30`** ⇒ `2026-09-30` 的反链数 = **1**，`2026-09-25` = **0**。

> ⚠️ **一条本窗口学到的工具事实**（值得写进 AGENTS）：**`uitest uiInput click` 的原始坐标在本机 2in1 窗口上不可靠**（实测把「添加」行点成无反应，连试 2 个坐标 ✗），而 **`emulator.exe -instance <名> -click <widgetId>` 一次成功** ✓。
> 根因：`-uiLayout` **给出的坐标是绝对屏幕坐标**，且**窗口位置会变**（本窗口观测到同一 dump 的坐标相对窗口内容偏移 (75,10) vp 的两个版本）⇒ **永远按 widgetId 点，不要自己算坐标**。

### 1.2 复现现场（截图 + `dumpLayout` 双证）

**基线（`2026-09-30`，反链应为 1）**：`反向链接 · 1 个结果` / `共 1 条反链` / 列表**有** `2026-09-25` + `[[2026-09-30]]` 卡片。

**缺陷现场（切到 `2026-09-25`，反链应为 0）**：

| 判据 | 实测 |
|---|---|
| 页头计数 | `Text 反向链接 · 0 个结果 [id:542]` ✓ **已更新** |
| 计数行 | `Text 共 0 条反链 [id:561]` ✓ **已更新** |
| **列表卡片** | **`2026-09-25` + `[[2026-09-30]]` 卡片仍在** ✗（`dumpLayout` 节点仍在原坐标） |
| 截图 | 计数行写「共 0 条反链」，**下面却挂着一张反链卡片** ✗ |

⇒ **同一屏内自相矛盾**（计数 0 / 列表 1）——这正是 Sprint-01 登记的「切页后不刷新」现象，**且比原描述更精确：不是全不刷新，而是只有列表不刷新**。

> 修复前另有一版更极端的现场（旧包）：`反向链接 · 1 个结果` + `共 1 条反链`，**列表区却是「暂无反链」空态**（列表区 297 px 高、里面只有空态图标与文字）⇒ 同一份 `getFilteredBacklinks()` 在两个渲染位置给出相反结果。

### 1.3 定位（**文件:行号**）

| 层 | 位置 | 状态 |
|---|---|---|
| 宿主版本号 | `components/sidebar/RightSidebar.ets:63`（`backlinkDataVersion`）· `:78-80`（`onCurrentPageChanged`→`refreshCaches`）· `:656-663`（`refreshCaches` 自增版本号） | **正常** ✓ |
| 传参 | `RightSidebar.ets:320-326`（列表那份 `BacklinkFilters({… dataVersion: this.backlinkDataVersion …})`） | **正常** ✓ |
| 收值 | `BacklinkFilters.ets:53`（`@Prop @Watch('onDataVersionChanged') dataVersion`）· `:113-115`（watch→`reloadFromSource`）· `:134-137`（`loadBacklinks`） | **正常** ✓（插桩实证：`BF.watch page=2026-09-25 raw=0`） |
| **渲染（真根因）** | **`BacklinkFilters.ets:406-428` 的 `@Builder BacklinkList(filtered: BacklinkDisplay[])`** —— `build()` 在 `:356` 以 `this.BacklinkList(this.getFilteredBacklinks())` 调用它 | ✗ **参数变化不触发 `ForEach` 重跑** |
| 计数行（对照） | `BacklinkFilters.ets:367-376` `CountRow()` —— **无参** `@Builder`，内部直接读 `this.getFilteredBacklinks()` | **正常** ✓ |

**机制**：`ForEach` 的数据源来自**带参 `@Builder` 的形参**。切页后组件重建、`@State backlinks` 变新，但 `ForEach` **不因「实参变了」重跑** ⇒ 仍渲染旧序列。
与 **AGENTS 陷阱 15 同族**（「键未变 ⇒ `LazyForEach` 不重跑 `itemGenerator`」），但**触发条件不同**：本例**不是键的问题**（1 条 → 0 条，键已消失，项仍留着），而是**数据源经形参传递后失去响应性**。

> 这也解释了为什么 W8 的 `@Prop @Watch dataVersion` 修法**看起来有效却没修好**：它把**数据**修对了（计数行立刻正确），只把**列表**留在了旧渲染上 —— 一个「一半修好」的假象。

---

## 2. 任务 1 · 修法（**为何复用既有版本号机制**）

```diff
         // ─── 反链列表 ───
         if (this.showList) {
-          this.BacklinkList(this.getFilteredBacklinks())
+          if (this.getFilteredBacklinks().length === 0) {
+            … 空态（含 hasActiveFilter 的两分文案）…
+          } else {
+            Column({ space: 0 }) {
+              ForEach(this.getFilteredBacklinks(), (item: BacklinkDisplay) => {
+                this.BacklinkItem(item)
+              }, (item: BacklinkDisplay) => item.sourceBlockId)
+            }
+            .width('100%')
+          }
         }
```

并**删除** `@Builder BacklinkList(filtered)`（其内容已内联）。

**为什么是「复用既有机制」而不是新造一套** ✗：

1. **版本号链路一个字没动** ✓ —— `RightSidebar.backlinkDataVersion`（`:63/78-80/656-663`）→ `@Prop @Watch dataVersion`（`BacklinkFilters.ets:53/113-115`）→ `@State backlinks` 全部原样保留。插桩已证明这条链**本来就是通的**，缺的只是最后一跳。
2. **不新增任何 AppStorage 键 / 版本号 / 事件总线** ✓ —— 修法只是把「数据源」从**形参**换成**直接读 `@State`**，让 `ForEach` 恢复响应性。改动面 = 1 个 `@Builder` 的 21 行。
3. **不改 `keyGenerator`** ✓ —— 与 W10 修陷阱 15 时的取舍一致：行的身份（`sourceBlockId`）不变，避免无谓重建。本例键本来就正确，改了反而掩盖真因。
4. **数据源与计数行同源** ✓ —— 两处都调 `this.getFilteredBacklinks()`，**结构上不可能再出现「计数 1 / 列表空」的口径打架**（这正是本缺陷最刺眼的表征）。

**未做的顺手加固**（刻意，见 §6）：没有把 `getFilteredBacklinks()` 的结果缓存到 `@State`（那会引入「筛选词变了但缓存没变」的新一类陈旧风险），也没有给 `ForEach` 的键加页面名前缀（无必要）。

---

## 3. 任务 1 · 验收（**阳性 / 阴性对照**）

### 3.1 阳性对照：切页 ⇒ 反链列表随之变化（4 轮，末版构建）

| # | 页面 | 页头 | 计数行 | 列表 | 判定 |
|---|---|---|---|---|---|
| 1 | 冷启动 → `2026-09-30` | `1 个结果` | `共 1 条反链` | **ITEM**（`2026-09-25` / `[[2026-09-30]]`） | ✓ |
| 2 | 切 → `2026-09-25` | `0 个结果` | `共 0 条反链` | **none** + 空态 | ✓ |
| 3 | 切 → `2026-09-25`（重复） | `0 个结果` | `共 0 条反链` | **none** + 空态 | ✓ |
| 4 | 切 → `2026-09-30` | `1 个结果` | `共 1 条反链` | **ITEM** | ✓ |
| 5 | 切 → `2026-09-30`（重复） | `1 个结果` | `共 1 条反链` | **ITEM** | ✓ |

⇒ **`列表` 与 `计数行` 每一轮都一致**，且**随页面在「1 条 ITEM」与「0 条空态」之间稳定往返** ✓。
（更早一版修复构建上另跑过完整 4 轮 V0→V3，同样全绿。）

**截图证据**（同一台设备、同一夹具）：

- 修复前：`2026-09-25` 页「**共 0 条反链**」下方**仍挂着**反链卡片 ✗
- 修复后：`2026-09-25` 页 = 计数 0 + **空态**（`link-off` 图标 + 「暂无反链」）✓
- 修复后：`2026-09-30` 页 = 计数 1 + **卡片**（`2026-09-25` / `[[2026-09-30]]`）✓

### 3.2 阴性对照：**不切页时列表不变** ✓

做法：停在 `2026-09-30`（列表 1 条），**不切页**，只点反链面板头部的 `filter` 图标（会触发 `filterPanelMode` 变化 ⇒ 组件重建），再取两次截图。

| 判据 | 实测 |
|---|---|
| 列表区（屏幕 `(2074,620)-(2605,880)`）像素差分 bbox | **`None`**（逐像素相同） |
| 该区域 MD5（前 / 后） | `7ece7b8ee8033ec93e7da4351eb1f5ac` / **同值** ✓ |

⇒ **列表不会「自己乱动」**（排除「其实是每帧都在重算、只是恰好对上了」这一解释）✓。

### 3.3 判据量说明（AGENTS 验证纪律 2：尺度必须匹配）

本项的判据量是 **`dumpLayout` 里反链列表项的 `text`/`bounds` 节点是否存在**（`Text 2026-09-25` / `Text [[2026-09-30]]`），辅以**页头与计数行的 `text`**（中文全角数字直接可比）与**截图逐像素差分**。**不用「节点总数」**——它会随无关面板开合抖动。

---

## 4. 任务 2 · 计划原文核实（**用户要求：不要凭转述**）

**核实方法**：对 `Callaite-工作文档/` 全目录（21 个 `.md` + 子目录）逐文件按字节读，检索 `Ctrl+Shift+F` / `Ctrl+Shift` / `Shift+F` / `KEYCODE_F` / `FindInPage`。

### 4.1 结论：**「Ctrl+Shift+F」在 `EXEC-PLAN.md` 里 0 命中** ✗

`EXEC-PLAN.md`（1023 行）提到 FindInPage **14 次**，但**没有任何一处出现 `Ctrl+Shift+F`**（其 §19.5 缺口 #3 只写「U2.4 FindInPage 三件套」；§17.6-2 只写「触发源 0 调用」）。

**那句话的真实出处 = `docs/PLAN-UI-Alignment.md (v1.md` §U2.4**（第 313–315 行）。**原文逐字**：

> ### U2.4 FindInPage 重做（**v1.1 排程修正：延后至编辑器 Phase 3 之后**）
>
> > 延后理由：DocumentEditor Phase 3 将重做全部 overlay 挂载层（SlashMenu/AC/FindInPage 移入编辑器协议）——现在重做 FindInPage 会在 Phase 3 被二次改造，同一模块两轮 churn。键位 Ctrl+Shift+F 先注册（打开即占位提示「编辑器重铸后可用」），组件本体随编辑器节奏走。

**配套的两处原文**（同文件）：

- §U2.3 目标键位表（第 304 行）：
  > `| Ctrl+Shift+F | 无 | **FindInPage（页内搜索）** | U2.4 重做后归位；Obsidian 语义里 Ctrl+F 是页内——若后续要严格对齐，与 Ctrl+Shift+F 对调成本为零（注册表一行） |`
- 第 309 行（配套文案）：
  > `配套：OnboardingPage 快捷键页文案改为「Ctrl+K/P/O 快速切换 · Ctrl+F 全局搜索 · Ctrl+Shift+F 页内搜索」；ShortcutSettings 读注册表自动跟随。`

### 4.2 逐条裁定用户转述

| 转述 | 裁定 |
|---|---|
| 「Sprint-02 原计划 W12 明确写过 Ctrl+Shift+F 打开后显示『编辑器重铸后可用』占位」 | **内容属实** ✓（「先注册」+「打开即占位提示『编辑器重铸后可用』」逐字在案） |
| 出处是 **Sprint-02 / W12** | **不准** ✗ —— 出处是 **`PLAN-UI-Alignment.md` v1.1 的 U2.4 排程修正**；`EXEC-PLAN.md` 里没有这句话。W12 只是 `EXEC-PLAN` 的窗口编号 ✓ |
| 「**若计划要求占位 ⇒ 就做占位**」 | **计划确实要求占位** ✓ ⇒ **本窗口按占位交付** ✓ |

⇒ 故本窗口**只做占位，不做搜索本体**，与计划一致 ✓。

---

## 5. 任务 2 · 实现

### 5.1 显隐统一（**收敛成单一开合态**）

**迁移前**（= 计划 §U2.4 诊断的「两个互不相通的显隐标志」）：

```
BlockList.ets:123   @State findInPageVisible = false          ← 宿主：决定是否构造组件（全仓 0 调用写它 ✗）
FindInPage.ets:26   @State isVisible = false                  ← 组件：初始 false，只有 show() 能置 true（show() 全仓 0 调用 ✗）
```

**迁移后**（与 Sprint-01 W12 的 SlashMenu 同一约定 —— **开合态收敛到 `AppState`**）：

| 文件 | 改动 |
|---|---|
| `state/AppState.ets` | `StorageKeys.findInPageOpen = 'callaite_findInPageOpen'`（:35/:51）· `AppState.init()` 初值 `false`（:234）· 新增 `isFindInPageOpen()` / `openFindInPage()` / `closeFindInPage()`（:647-682），**并与快速切换 / 全局搜索 / Slash 菜单互斥** |
| `components/outliner/BlockList.ets` | `@State findInPageVisible` → **`@StorageLink('callaite_findInPageOpen')`**（:123-132）；`toggleFindInPage`/`showFindInPage`/`hideFindInPage` 三个方法**改为写 `AppState`**（不再写本地状态） |
| `components/outliner/FindInPage.ets` | 删 `@State isVisible`，改 **`@StorageLink('callaite_findInPageOpen') @Watch('onVisibilityChanged')`**（:52-59）；`show()`/`hide()` 改为 `AppState.openFindInPage()`/`closeFindInPage()`；新增 `onVisibilityChanged()` **同步 `OverlayKeyRouter` 的开合态**并在关闭时清搜索态（原来是 `hide()` 里手写同步，现在由「状态变化」这一个入口保证，**不会再漏**） |

**闭环性**：**唯一写入口 = `AppState.open/closeFindInPage`**；宿主与组件读**同一个键** ⇒ 结构上不可能再分叉 ✓。

### 5.2 挂载层 / 触发源

- **触发源**：`services/ShortcutService.ets` 注册 **`app.find-in-page`（Ctrl+Shift+F）**，action = `AppState.openFindInPage()`（插在 `app.search` 之后，含计划原文引用）。
- **挂载层**：**仍由 `BlockList` 在既有两处按 `findInPageVisible` 构造**（`BlockList.ets:298-300` 内嵌模式 / `:341-343` 整页模式）—— **不做计划 §U2.4 第 2 件的「迁到 MainContainer 顶部 Stack」** ✗，理由见 §5.3。
- **键位隔离**：`Ctrl+F`（`app.search`，全局搜索）**未动**；两者靠 `matchShortcut` 的 `getModifierKeyState(['shift'])` 区分（`ShortcutService.ets:643-651`）✓。

### 5.3 第 3 件（跳块）**本窗口不做** ⇒ 显式封存

新增常量：

```ts
const FIND_IN_PAGE_BODY_READY: boolean = false;
```

`build()` 三分支：**关**（0 高）· **占位**（`false` 时）· **本体**（`true` 时，即原有搜索实现，**原样保留未删**）。

**为什么用常量而不是删代码**：
1. 计划 §U2.4 第 3 件（**跳块走 `AnchorRegistry` + 文本级高亮**）未做 ⇒ 现在打开本体 = 交付「能搜到计数、但既不滚动也不高亮」的半成品，用户点「下一个」**画面不动**，比占位更糟 ✗；
2. 保留实现 + 一个常量 ⇒ 第 3 件做完时**改一行**即可，避免「现在删、下轮重写」的两轮 churn（这正是计划延后它的原始理由）✓。

**占位条内容**（照计划原文用词）：`页内搜索：编辑器重铸后可用` + `Esc 关闭` + `✕` 按钮。
**id 约定**（供后续 `dumpLayout` 定位，AGENTS 陷阱 18 同款）：`callaite_findInPagePlaceholder`（文本）· `callaite_findInPageClose`（关闭按钮）。

### 5.4 任务 2 · 可达性验收

| 步 | 注入 | 观测（`-uiLayout`） | 判定 |
|---|---|---|---|
| 0 | — | 无任何 FindInPage 节点 | 基线 ✓ |
| 1 | `uitest uiInput keyEvent 2072 2047 2022`（Ctrl+Shift+F） | `Text 页内搜索：编辑器重铸后可用 [id:270]` · `Text Esc 关闭 [id:271]` | **能打开** ✓ |
| 2 | `keyEvent 2070`（Esc） | FindInPage 节点消失 | **能关闭** ✓ |
| 3 | 重复 (1)(2) ×2 | 开 → 关 → 开 → 关 全对 | 可重复 ✓ |
| 4 | `keyEvent 2072 2022`（**仅 Ctrl+F**） | FindInPage **仍关**（打开的是全局搜索 SearchPanel） | **键位隔离** ✓ 阴性对照 |

**截图证据**：占位条位于内容区顶部（`2026-09-25` 页标题下方），左起放大镜图标 + 文案 + 「Esc 关闭」+ `✕`；同屏右侧栏显示 `反向链接 · 1 个结果` 与反链卡片（**两项交付物同框**）✓。

> 注：注入的**是**`Ctrl+Shift+F` 三键序列（`2072`=Ctrl、`2047`=Shift、`2022`=F）。按陷阱 21，2in1 上注入键**过 IME**；本项命中 `ContentArea.onKeyPreIme`（`ContentArea.ets:250-260`，**修饰键在 IME 前拦截**）⇒ 与 IME 无争用 ✓。

---

## 5.5 回归面复核（**W12 改动触及的共享设施：`ShortcutService` / `AppState` / `BlockList`**）

改动落在**全局快捷键表**与**全局开合态**上 ⇒ 必须复核 Sprint-01 的既有浮层未被挤掉。
判据 = **整屏截图逐像素差分**（陷阱 12：浮层在独立子窗口，`dumpLayout` 读不全 ⇒ **文本检索会假阴性** ✗，本窗口实测正是如此）。

| 注入 | 与基线的整屏差分 | 判定 |
|---|---|---|
| **`Ctrl+K`**（快速切换/命令面板） | `bbox=(1104,424,3114,1969)` · **385 908 px 变化** | **仍能打开** ✓（未回归） |
| `Esc` 之后 | **`bbox=None` · 0 px** | 逐像素回基线 ✓ |
| **`Ctrl+F`**（全局搜索） | `bbox=(1104,424,3114,1969)` · **1 190 001 px 变化** | **仍能打开** ✓（未回归；且与 Ctrl+Shift+F **不串**） |
| **`Ctrl+Shift+F`**（本窗口新增：页内搜索） | `bbox=(1192,671,3008,2016)` · **217 841 px 变化** | 打开占位条 ✓ |
| 再 `Esc` | `bbox=(2976,1992,3008,2016)` · **657 px**（**仅状态栏时钟区**） | 回到基线 ✓ |

> ⚠️ **方法论收获**（建议并入 AGENTS）：**「浮层是否打开」不能用 `dumpLayout` 的文本检索判分** ✗ —— 本窗口按文本比对 `Ctrl+K`/`Ctrl+F` 双双读出「无新增文本」（假阴性 ✗），而整屏像素差分显示两者**各变化数十万像素**（真打开 ✓）。
> ⇒ 与陷阱 12/3 同族：**读不到不等于不存在**；浮层类判据请用**像素差分**或浮层自身的 `id` 节点。

**W11 的红线未受影响**（源码级核对，未复跑）：本窗口**未改** `OutlinerEngine` / `BlockEditor` / `BlockTree` / `MarkdownExporter` / `IndexStore` / `DataStore` 任何一个字节 ⇒ E13（撤销/重做落盘）与 E14（行刷新）的代码路径与本窗口零交集 ✓。
**未复跑**的项如实列出：E1–E20 中除本窗口直接触及的浮层/面板外**均未复跑** ✗（本窗口定位是「两条遗留项」，不是全量回归窗口）。

---

## 6. 对症修复 vs 顺手加固（**分开说明**）

| 类别 | 内容 | 说明 |
|---|---|---|
| **对症（本窗口的任务）** | ① `BacklinkFilters` 列表内联（§2）② FindInPage 显隐统一 + Ctrl+Shift+F 注册 + 占位（§5） | 两者的判据都在 §3 / §5.4，均有设备证据 ✓ |
| **刻意不做**（并说明理由） | ③ **不修**「编辑正文产生的反链在**不切页**时也要刷新」✗ —— 现状是 `@Watch('callaite_focusedBlock')` 覆盖（`RightSidebar.ets:68/83-87`），但 `IndexStore.rebuildReferences` **只在 `DataStore.loadPage` 时调用**（全仓仅 `DataStore.ets:96/171` 两处）⇒ **块内新增 `[[引用]]` 不会进反链索引**，属于**索引层**的另一个缺陷，与本窗口的渲染层缺陷**不同源**；擅自改会把「刷新」与「索引重建」两件事混在一起 | 已登记为遗留项（§9） |
| **刻意不做** | ④ 不迁 FindInPage 到 MainContainer 顶部 Stack ✗ —— 属计划 §U2.4 第 2 件的后半，与第 3 件同一批（Phase 3 overlay 协议重做） | 见 §5.3 |
| **顺手加固（低风险、与任务同源）** | ⑤ `FindInPage.onVisibilityChanged` 让「关闭时清态 + 同步按键路由器」变成**由状态变化驱动**（原来是 `hide()` 内手写，任何别的关闭路径都会漏同步） | 属同一缺陷族（「两份状态手工同步必然漏一处」），改动 8 行 ✓ |
| **顺手加固** | ⑥ `AppState.openFindInPage()` 补**浮层互斥**（关掉快速切换 / 全局搜索 / Slash 菜单），与 `openSlashMenu` 同一判据 | 防「多块浮层同开争键盘焦点」，3 行 ✓ |
| **未做** | ⑦ 没给反链列表加 `.id()`（本窗口用 `text` + `bounds` 已够判分；加 id 属纯工具性，等真有自动化回归再加） | — |

---

## 7. 编译与交付状态

| 项 | 结果 |
|---|---|
| **清洁构建**（先删 `entry\build` + `.hvigor\cache`） | **`BUILD SUCCESSFUL in 13 s 123 ms`** ✓ · 产物 **8 965 745 B** · MD5 **`194A7DE71A4D81E445DD214544D1538D`** |
| 末次增量构建 | `BUILD SUCCESSFUL in 6 s 873 ms` · MD5 **`71ED9F72B9A899B723C975FF3EF43420`** |
| **§7b 对抗性检查**（证明 5 个文件**真的在编译图里**） | 向 5 个文件各注入一处 `const __W12_TYPE_CHECK: number = 'deliberate-string';` ⇒ **构建失败**，且 **5 个文件全部各自报出** `Type 'string' is not assignable to type 'number'` ✓（撤销后复绿 ✓） |
| 安装 | `hdc install -r`（**未用 `uninstall`** ✓）· `updateTime` **前进** ✓：`1790762494376` → `1790764529155` → `1790764686220` → `1790764924115` → **`1790765158634`** |
| 行尾 | 5 个改动文件 **CRLF=0 / LF 归一** ✓（陷阱 10） |
| 探针残留 | 全仓 grep `W12PROBE` = **0 命中** ✓（插桩已全部还原，未触碰 `main_pages.json` / `SpikeHarness.ets` / `rawfile/spike/*` / `rawfile/libs/**`） |
| `git status --short` **前**（开工时） | **空**（= `fdc5947` 干净树）✓ |
| `git status --short` **后** | 恰好 **5 个 ` M`**：`AppState.ets` · `BlockList.ets` · `FindInPage.ets` · `BacklinkFilters.ets` · `ShortcutService.ets` —— **无未跟踪产物、无探针** ✓ |
| 提交 | **未提交**（本窗口只交付到工作区 + 本报告；按纪律逐个列文件提交，**禁用 `git add -A/-u`**） |

---

## 8. 交还时的实例与 vault 状态

| 项 | 状态 |
|---|---|
| **实例** | **`MateBook Pro`（2in1）运行中** ✓ —— 本窗口**未换实例、未重启设备**（未触发陷阱 26 的场景）· **一次只跑一个实例** ✓ |
| **已装包** | 本窗口末版（HAP MD5 `71ED9F72B9A899B723C975FF3EF43420`）· `updateTime=1790765158634` ✓ |
| **vault** | `2026-09-25.md` = **67 B / 9 块 / MD5 `972a9698d60e65e172de5fbfd6f95209`**（⚠️ **含本窗口新加的夹具行 `- [[2026-09-30]]`**，不再是 W11 交还时的 50 B / 8 块 ✗；本窗口结束前**复读两次一致** ✓ 陷阱 24）· `2026-09-30.md` = **3772 B / 1023 块 / MD5 `804b1e6cfc2e84df6317e7b32346d475`**（W11 交还 3434 B ⇒ **期间自增，本窗口未主动编辑该页** ✗，与 W11 记录的「`2026-09-30.md` 自己变大」同型，**未归因** ✓） |
| **vault 可写性** | **仍不可 shell 写** ✓（本窗口 `touch` 阳性对照 `Permission denied`，§1.1）⇒ §7c 的应用内构造路线仍是唯一路线 ✓ |
| **屏幕** | 应用停在前台（`2026-09-30` 页；FindInPage **已关闭**、右侧栏反链面板开着）✓ · 设备曾处**锁屏**，已用 `power-shell wakeup` + `setmode 602` 唤醒并保持常亮 ✓ |

---

## 9. 本窗口未闭合项（**登记，不写成通过**）

| # | 项 | 阻塞/理由 | 级别 |
|---|---|---|---|
| **W12-1** | **FindInPage 第 3 件：跳块走 `AnchorRegistry` + 文本级高亮** | 计划 §U2.4 第 3 件；与 Phase 3 overlay 协议重做同批 ⇒ 本窗口**明确不做** ✓ | Ⓑ 代码就绪（由 `FIND_IN_PAGE_BODY_READY` 封存） |
| **W12-2** | **FindInPage 第 2 件后半：迁到 MainContainer 顶部 Stack** | 同上（挂载层重做）；当前仍内联在 `BlockList` 内容顶部 | Ⓑ 待 Phase 3 |
| **W12-3** | **反链索引的时效性**：块内新增 `[[引用]]` 后**不切页**看不到新反链 | `IndexStore.rebuildReferences` 只在 `DataStore.loadPage` 调用（全仓 2 处）⇒ 属**索引层**缺陷，与本窗口的渲染层缺陷不同源 ✗ **未修** | Ⓑ 待定位 |
| **W12-4** | FindInPage 占位条的**触屏可达性**（无物理键盘时的入口） | 本窗口只按要求做 `Ctrl+Shift+F`（计划原文就只要键位）；平板/触屏无该键 ⇒ 仍不可达 ✗ | Ⓐ 待产品定 |
| **W12-5** | `Ctrl+Shift+F` 在**平板**上不可验 | 平板注入键不过 IME（陷阱 21）；且 `ContentArea.onKeyPreIme` 只在持焦时拦截 ⇒ 需真机 + 物理键盘终验（并入 S3-1） | Ⓐ 待 R0 |

---

## 10. 不可自证项（**如实列出**）

1. **`uitest uiInput click` 在本机 2in1 上为何不可靠**：本窗口实测「底部添加行」用两个不同坐标点都无反应，而 `-instance -click <widgetId>` 一次成功 ⇒ **无法区分**「坐标算错了」与「坐标点击本身不进该窗口」。已改用 widgetId 通道，但**根因未归因** ✗。
2. **`-uiLayout` 的坐标系**：同一会话内观测到**两套**（相对窗口内容 vs 绝对屏幕），差异来自**窗口位置变化**（(75,10) vp）。**未能证明**它到底以何为基准 ✗ ⇒ 本窗口一律**只信 widgetId**，`text`/`bounds` 仅作展示与判据量。
3. **反链夹具的「应用内构造」只能造出 `[[页面名]]` 这一种引用**：块引用 `((uuid))` 形态（`isBlockRef=true`）**本窗口未构造、未验** ✗ ⇒ 反链卡片的 `hash`/`file` 两种图标只验到 `file` 一种。
4. **修复前的旧包现场只取到两次观测**（一次「计数 1 / 列表空态」、一次「计数 0 / 列表 1」），**未做多轮重复以排除偶发** ✗；修复后跑了 4+5 轮全绿。
5. **`ForEach` 在带参 `@Builder` 内不随参数重跑的机制解释是推断**：本窗口的**观测**（计数行更新 / 列表不更新，插桩证明 `@State` 已刷新）是硬证据 ✓，但「ArkUI 具体在哪一层跳过了重建」**未从 SDK 源码证实** ✗。
6. **`Ctrl+Shift+F` 的键码路径未在平板复跑**（见 W12-5）⇒ 「注入键在 2in1 过 IME」这一前提沿用了陷阱 21 的既有结论，**本窗口未重跑 IME 阳性对照** ✗。
7. 本报告所有设备结论**只在 `MateBook Pro`（2in1 模拟器）成立** ✗；真机未验（= S3-5 口径）。

---

## 11. 对 AGENTS.md 的建议增补（供后续窗口决定）

1. **新增陷阱（渲染层）**：**参数化 `@Builder` 内的 `ForEach` 不随「实参变化」重跑** —— 与陷阱 15 同族但触发条件不同；判据 = **同一份数据在两个渲染位置给出相反结果**（本例「计数 0 / 列表 1」）。修法 = 让 `ForEach` 直接依赖 `@State`（内联进 `build()`），**不要**为了复用抽成带参 `@Builder`。
2. **§3 设备工作流增补**：**点应用内控件一律用 `emulator.exe -instance <名> -click <widgetId>`** ✓；`-uiLayout` 的 `text`/`bounds` **只作展示**，**不要自己把 bounds 换算成点击坐标**（本窗口在 2in1 窗口上踩到，是陷阱 25 的加强版）。
3. **§7c 补充**：本机 `files/graph` 权限位 `drwxrwxrwx` 但 `touch` 仍 `Permission denied` ✓ —— **W7 的结论在本窗口复现**，§7c 的「应用内构造」是唯一路线。

---

**维护规则**：本窗口的两项交付已按 §3 / §5.4 的设备判据闭合；**§9 的五项不得写成已通过** ✗，须随 `docs/待验收清单.md` 与 `docs/S3-回归矩阵-编辑器行.md` 一起清账。
