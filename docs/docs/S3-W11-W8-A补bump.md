# S3-W11 · 修 `W8-A`（6 条「非 UI 发起的结构变更」路径补 `bumpBlocksVersion`）

> **窗口**：EXEC-SPRINT-03 / **W11** —— 用户裁定：把 `W8-A` 从「**S4 开工时一并做**」（`S3-W9-收束与M3重判.md` §5 遗留清单口径）**提前到本窗口**。
> **性质**：**修缺陷窗口 ⇒ 仓库有改动** ✓（**6 文件 / +84 −6**，HEAD 仍 `94cea91`，**本窗口未提交**）。
> ⚠️ **编号去重提示** ✗：本工作区**已有一份 `docs/S3-W11-G1G2回归复跑.md`**（G1/G2 回归复跑窗口）。
> 本文件是**第二个 W11 窗口**（与 W8 的「两个冲刺同号窗口」同族 ✓）—— 本文一律自称 **「W11（W8-A 窗口）」** ✓。
> **设备**：`MateBook Pro`（**2in1**，`127.0.0.1:5555`）**唯一在跑** ✓；**未启平板** ✓（一次只跑一个实例）。
> **已装包（交还时）**：`updateTime = 1790942226336`（≈ 2026-10-02 **19:57** CST，本窗口的**清洁构建**）✓
> —— **包身份按 `updateTime` + HAP mtime 判定，未用 HAP MD5**（陷阱 27 ✓）。
> **证据分级**：Ⓐ 设备实测（本轮）· Ⓑ 代码级论证 · Ⓒ 受控探针/离线。
> **口径**：**不得把「无法验证」写成「通过」** ✗（验证纪律 5）—— 每条 ✅ 都带等级，**未验的一律写 ❌/⚠️ + 原因** ✓。

---

## 0. 本窗口的硬边界（先读）

| 边界 | 本轮执行情况 |
|---|---|
| 改源码用 `edit`/`write` 或 Python 字节级 | ✅ 6 文件用 `edit`；§7b 注入/回退用 **Python 字节级**（`%TEMP%` 下脚本，仓库外 ✓）；**6 文件 `CRLF=0 / loneCR=0`** ✓（陷阱 10 ✓）|
| 禁止触碰 `main_pages.json` / `rawfile/spike/*` / `rawfile/libs/**` | ✅ **未触碰**（`git status --short` 只列 6 个 `.ets` ✓）|
| 页面级探针须先问 | ✅ **未新建任何探针页** |
| 启动链插桩 | ✅ **未做**（无插桩 ⇒ 无还原项）✓ |
| **探针串残留 = 0** | ✅ **0** ✓（§7b 的 `w11s7b` 注入物已字节级删除；`git grep -i w11s7b` **零命中** ✓）|
| 提交逐个列文件 | ✅ **未提交**（工作区 6 个 M，**0 个未跟踪** ✓）|
| `uninstall` / `git stash` / `git checkout -- <目录>` / `git reset --hard` / `git add -A`/`-u` | ✅ **全部未使用** |
| 设备 | ✅ 每步先断言 `hdc list targets`；**未用** `-bootMode coldboot`（快速启动正常 ✓）|
| 临时产物 | 全部在**仓库外** `F:\DevEcoStudioProjects\.dsh_tmp\w11\`（截图 / `uiLayout` 副本 ✓）；仓库内**零**残留 ✓ |

---

## 1. 开工基线（**臂 A 不需要另建** ✓✓ —— 这是本窗口 A/B 的关键前提）

| 项 | 值 |
|---|---|
| `git status --short`（开工） | **空** ✓ |
| HEAD | `94cea91`（W10 提交）✓ |
| **已装包（开工）** | `updateTime = 1790941190853` ≈ **19:39** CST（**W11-G1G2 窗口的构建**，源码 = HEAD，**不含 W8-A 修复**）✓ |
| ⇒ **臂 A（未修）** | **= 开工时设备上那个包** ⇒ **无需为 A/B 另做一次「回退构建」** ✓（**单变量**：同一台设备、同一 vault、同一注入配方，唯一变量 = 是否含本窗口的 6 处 bump ✓）|
| vault（开工，4 个 `.md`） | `2026-09-25.md` **109 B** `5f46fc46…`（= W8 交还值 ✓）· `2026-09-30.md` **3953 B** `7d6192c1…` · `2026-10-02.md` **26 B** `2f6c6187…`（**= W10 的稳态：1 个占位块** ✓）· `未命名.md` **102 B** `7e7c1931…` |
| 起始落点 | 活动标签 = `Journal`（`callaite_app_state` 的 `callaite_activeTabId` = `tab_muqscwuj_2r7` ✓）⇒ 冷启动落在**日志流页** ✓ |

> ⚠️ 与 W8 交还值的差异（**如实登记** ✗）：W8 交还时 `2026-10-02.md` = **546 B / 20 行**，本窗口开工时是 **26 B / 1 行**
> ⇒ 中间的 **W11-G1G2 窗口**已把该页清回 W10 稳态 ✓（本窗口**未**再清理过它；本窗口开工时 `git status` 为空 ✓）。

---

## 2. 任务 ①：**逐条核实**（先核实再改 ✓）

### 2.1 汇总表（6 条 × 4 问）

| # | 路径（文件:方法） | ① 真的会**结构变更**？ | ② 有 **UI 调用方**？ | ③ 当前**已有 bump**？ | ④ 用户可达入口 | 判定 |
|---|---|---|---|---|---|---|
| 1 | `EditorService.pasteMarkdownAsBlocks`（`:178`） | ✅ `insert-block` ×N | ✗ **零调用方**（全仓 `git grep pasteMarkdownAsBlocks` **仅定义处 1 命中**）| ✗ | ⚠️ **无**（**未接线**）| **补在服务内** ✓ |
| 2 | `ImportService.importToPage` / `importAsNewPage`（`:82` / `:102`） | ✅ `insert-block` ×N（新页面分支另含 `new-page`）| ✅ **`ImportDialog.doImport`**（`:79`/`:90`，**唯一调用方**）⇒ 渲染点 `ContentArea.ets:217-229` | ✗ | ✅ **设置 → 数据 → 导入数据**（`SettingsPage.ets:662`）· 紧凑形态走 `MobileMenuSheet.ets:129` | **补在调用方** ✓ |
| 3 | `PluginAPI.insertTodayBlock`（`:94`） | ✅ `insert-block` | ✗（调用方是**插件**：`BuiltinPlugins.ets:16`、`insertTemplateByName:186`）| ✗ | ✅ **启动链**（`EntryAbility.ets:105` → `registerBuiltinPlugins` → `initAllPlugins` → `enable` → `onEnable`）· ✅ **运行时**：设置 → 插件开关（`SettingsPage.ets:845-847` → `pm.enable()`）| **补在服务内** ✓ |
| 4 | `PdfViewer.createAnnotation`（`:65`） | ✅ `insert-block` + 显式 `ws.savePage` | ✅ **它自己就是 UI 组件**（`@Component struct`；唯一构造点 `PdfPage.ets:170`）| ✗ | ✅ Ribbon **`Pdf`** → 选 `.pdf` → 在 PDF 文本层**选中文字**（WebView 内 `mouseup` → `callaitePdf.annotate` ✓）| **补在组件内** ✓ |
| 5 | `ShareReceiveAbility.handleSharedText` / `handleSharedUrl`（`:80` / `:106`） | ✅ `insert-block` ×2 | ✗（触发者是**系统分享框架**，`skills = ohos.want.action.sendData` ✓）| ✗ | ✅ **系统分享到 Callaite**（本窗口实测：`aa start -a ShareReceiveAbility … --ps …` **可直达** ✓）| **补在 Ability 内** ✓ |
| 6 | `EntryFormAbility.handleQuickNote`（`:209`） | ✅ `insert-block` | ✗（触发者是**桌面服务卡片**：`onFormEvent` → `handleQuickNoteFromMessage`）| ✗ | ✅ 桌面**速记卡片**提交（`type: form` 扩展 ✓）| **补在扩展内** ✓ |

**⇒ 结论（① 的答案）**：
- **6/6 都是真·结构变更** ✓ —— 判据不是「行号存在」，而是**逐条读它们发出的 `OutlinerOp` 类型**：全部是 `insert-block`（#2 还含 `new-page`）✓；
- **6/6 当前都没有 bump** ✓（本窗口**独立复核**，不是引用 W8 —— `git grep bumpBlocksVersion` 在这 6 个文件里命中 **0** ✓，验证纪律 9 ✓）；
- **「只改文本的路径」= 0 条** ⇒ **没有一条属于「不需要 bump」** ✗✓（见 §3 的两条边界登记）。

### 2.2 逐条补充（决定**层次**的那些事实）

1. **`pasteMarkdownAsBlocks` 零调用方** ✓：`git grep -n pasteMarkdownAsBlocks` 全仓仅 `EditorService.ets:178` 一处（**定义处本身**）。
   ⇒ 「补在调用方」这一层**不存在**；而同文件 `createBlockBelow`（W6，`:241` 原行号）与 `createChildBlock` 已有**服务内 bump** 先例 ✓
   ⇒ 补在服务内是与**本文件**既定分工一致的选择。⚠️ **不删**（陷阱 2：零引用 ≠ 死代码，取决于路线图 ✓）。
2. **`ImportService` 的唯一调用方是 `ImportDialog`** ✓：`git grep ImportService.` 命中 `ImportDialog.ets` 4 处（`:79`/`:83`/`:90`/`:93`，其中两条是**同一流程内的重复解析**，只为显示块数）；`ImportDialog` 的唯一渲染点 = `ContentArea.ets:217-229` ✓。
   ⇒ 补在**调用方**（W8 的既定分工：结构类操作补在调用方，服务不碰视图 ✓）。
3. **`PluginAPI` 的调用方是插件、不是 UI** ✓：`PluginManager.enable()` 的**运行时**入口在 `SettingsPage.ets:842-852` 的 Toggle（`onChange → pm.enable/disable`）✓
   ⇒ 插入**可能发生在 UI 存活期间**，而**目标页（今日日志）可能正被显示**：`JournalFeed.ets:147` 的**内嵌 `BlockList({pageName: day, embedded: true})`**（今天 = `index 0` ✓），或**副窗格**（`MainContainer.ets:252` 的 `ContentArea({ pageOverride: this.splitPage })`，`callaite_splitPage` **默认 `'Journal'`** ✓）。
   ⇒ 插件层无处可补（插件是纯逻辑类）⇒ 补在最靠近插入的服务层（**沿用 W10 在该方法上已确立的层次决策** ✓）。
4. **`PdfViewer` 是 UI 组件** ✓（`components/extensions/PdfViewer.ets:46` = `@Component export struct`）
   ⇒ 它**就是** `WorkspaceService.executeOp` 的调用方 ⇒ 与 W8 把 bump 补在 `BlockView`/`Toolbar` **同一层次** ✓。
   目标页 = `AppState.getCurrentPage()`（真页时即当前显示页）；**取不到时回退今日日志页**（`:76-79`）⇒ 上面的「内嵌 feed / 副窗格」陈旧面同样适用 ✓。
5. **`ShareReceiveAbility` 没有 UI 调用方** ✓ —— 它是 `UIAbility`，自己 `loadContent('pages/Index')` 后调 `processPendingShare()`；本窗口用 `aa start --ps` **实测该入口可达** ✓（§5.2）。
6. **`EntryFormAbility` 没有 UI 调用方** ✓ —— `FormExtensionAbility`（`type: form`），入口是卡片事件 `onFormEvent` ✓。

---

## 3. 任务 ②：**判定「不需要 bump」的项 + 理由**

**核实后：6 条全部需要 bump，判为「不需要」的 = 0 条** ✗✓（理由见 §2.1 的 op 类型逐条核对）。
但核实过程查出**两条边界**，**一并登记**（这是本窗口除修复外的附加产出 ✓）：

| 编号 | 登记内容 | 证据 | 处置 |
|---|---|---|---|
| **`W11-A`**（**新查出的独立缺陷**，**非 bump 类**）| **`ShareReceiveAbility` 没有 `onNewWant`，`launchType` 又是默认 `singleton`** ⇒ **第二次分享的内容被静默丢弃** ✗ | Ⓐ：`aa start -a ShareReceiveAbility -b com.example.callaite --ps ohos.extra.param.key.content W11SHARE` **第一次** ⇒ 磁盘 `245 → 256 B`（+11 = `\n- W11SHARE` ✓）；**第二次同命令** ⇒ **`256 → 256 B`（+0）** ✗（`W11SHARE` 计数仍 = 1 ✓）| **只登记，不修** —— 超出本窗口裁定范围（本窗口只修 bump）；它**不是**「结构变更没刷新」，而是**结构变更根本没发生** ✓ |
| **`W11-B`**（口径登记）| `EditorService.pasteMarkdownAsBlocks` **当前零调用方** ⇒ **当前没有任何用户可达入口 ⇒ 当前无缺陷面** ✗✓ | Ⓑ：`git grep` 全仓 1 命中（定义处）| **仍补 bump** ✓（未接线资产，一旦接线即缺陷；陷阱 2：不删 ✓）—— 但**不得**把它写成「已修用户可见缺陷」✗ |

> ⚠️ **同时核过、明确「不补」的地方**（避免乱补 ✗）：
> - `EditorService` 的其余结构类方法（`indentBlock`/`outdentBlock`/`deleteEmptyBlock`/`moveBlockToTarget`/`undo`/`redo`/`deleteSelected`/`indentSelected`…）
>   **调用方已 bump**（W8 的 11 入口 + `BlockDragLayer`/`BlockSelection` ✓）⇒ **不重复补** ✓；
> - `EditorService.updateBlockContent` / `setMarker` / `setPriority` / `setScheduled` / `setDeadline` / `addProperty`：**非结构变更**（不改行序列）⇒ 不需要 ✓；
> - `EditorService.collapseAll` / `expandAll` / `toggleCollapse`：**零调用方**（W8-B）⇒ 不动 ✓；
> - **W10 的按天幂等守卫**：一字未动 ✓（§6.2 回归通过 ✓）。

---

## 4. 修复清单（**文件:行 + bump 补在哪一层 + 为何**）

| # | 文件 | 行（改后） | 层次 | 为什么是这一层 |
|---|---|---|---|---|
| 1 | `entry/src/main/ets/services/EditorService.ets` | **:215**（`pasteMarkdownAsBlocks` 末尾）| **服务内** | **零调用方** ⇒ 「调用方」层不存在；同文件 W6 已有服务内先例 ✓。**刻意只在循环后 bump 一次**（循环内 bump 会在长文档粘贴时触发 N 次全表重建 ✗）|
| 2 | `entry/src/main/ets/components/common/ImportDialog.ets` | **:93**（`mode='current'` 成功分支）· **:106**（`mode='new'` 成功分支）· `:3` 新增 `AppState` import | **调用方** | `ImportDialog` 是全仓**唯一**的 `ImportService` 调用方 ✓ ⇒ 沿用 W8 分工「结构类补在调用方、服务不碰视图」✓。**只在成功分支补**（失败路径不 bump ✓）|
| 3 | `entry/src/main/ets/plugins/PluginAPI.ets` | **:127**（守卫之后、`executeOp` 的成功分支内）| **服务内** | 调用方是**插件**（纯逻辑类，拿不到视图语义）⇒ 无处可补；W10 已把本方法定为「最靠近插入、覆盖所有调用方」的那一层 ✓。**守卫命中时已 `return`** ⇒ 按天幂等语义**零变化** ✓ |
| 4 | `entry/src/main/ets/components/extensions/PdfViewer.ets` | **:101**（`savePage` 之后）| **组件内（= 调用方）** | 它自己就是 UI 组件、就是 `executeOp` 的调用方 ⇒ 与 W8 的 `BlockView`/`Toolbar` 同层 ✓ |
| 5 | `entry/src/main/ets/shareability/ShareReceiveAbility.ets` | **:105**（文本分支）· **:135**（URL 分支）| **Ability 内** | **无 UI 调用方**（触发者是系统框架），本 Ability 即调用链顶 ⇒ 按陷阱 22 的判据（「这条路径上究竟有没有一个地方 bump」）只能在此补 ✓ |
| 6 | `entry/src/main/ets/entryformability/EntryFormAbility.ets` | **:240**（`savePage` 之后）· `:5` 新增 `AppState` import | **扩展内** | **无 UI 调用方**（触发者是桌面卡片）⇒ 同上 ✓ |

**改动规模**：`6 files changed, 84 insertions(+), 6 deletions(-)` ✓ —— 其中**实质代码 = 7 行**（6 处 `if (r.success) { AppState.bumpBlocksVersion(); }` + 2 行 import + 1 行 `let inserted = 0` / `inserted += 1`），**其余是注释**（写清层次理由与不可自证边界 ✓）。
**零业务逻辑改动** ✓：每处都是「捕获既有 `executeOp` 的返回值 + 成功后通知视图」，**不改任何 op 的语义、不改守卫、不改落盘** ✓。

> ⚠️ **冲突自查（用户特别提示的 `insertTodayBlock`）** ✓：W10 的按天幂等守卫（`:102-112`）**一字未动**；
> 新增行**在其之后**的 `executeOp` 成功分支里 ⇒ **守卫命中 ⇒ 提前 return ⇒ 不会 bump** ✓（回归见 §6.2）✓。

---

## 5. 任务 ③：**验收**（分级 Ⓐ/Ⓑ；每条给判据）

### 5.1 Ⓐ **臂 A / 臂 B 单变量对照** —— 走 **`ImportService`**（`W8-A` 的第 2 条，也是**唯一一条注入通道完全可达**的）

**为什么选它**：导入对话框的入口 = **设置 → 数据 → 导入数据**（Ribbon 齿轮 → 数据 → 导入数据，全部可用 `-uiLayout -i` 的**当轮 widgetId** 点到 ✓）；
目标页取 `ContentArea.resolvePageName(currentPage)`（`ContentArea.ets:263-272`：`'Journal'` → **今日日期** ✓）⇒ 在 Journal 标签下点导入 = **往「正在显示的今日节」里插块** ⇒ **陈旧面与 E14 逐字相同** ✓。

**配方（两次完全相同的注入序列）**：冷启动 → Ribbon 齿轮 → `数据` → `导入数据` → `当前页` → `-fill` 源文件路径 → 切到 **Journal 标签** → `导入`。
**源文件** = **vault 自己的** `2026-09-25.md`（109 B / 14 行，ASCII 文件名 ✓ —— `-fill` 只能送 ASCII ✗）。
⚠️ **路径必须用应用视角**：`/data/storage/el2/base/haps/entry/files/graph/2026-09-25.md` ✓
（**踩过一次** ✗：先用 shell 视角的 `/data/app/el2/100/base/…` ⇒ 应用 `readTextSync` 失败 ⇒ 对话框报 **`导入失败`** ✓ —— 这是一条**新发现的通道纪律**，见 §9-6）。

| 判据 | **臂 A（未修，`updateTime` ≈19:39）** | **臂 B（已修，`updateTime` ≈19:57）** | 结论 |
|---|---|---|---|
| **① 磁盘字节**（硬证据）| `2026-10-02.md` **26 → 135 B**（+109 = 源文件等长 ✓）· md5 `2f6c6187…` → `50aa1786…` ✓ | **135 → 245 B**（+110 ✓）· md5 `50aa1786…` → `04380c75…` ✓ | **两次都真落盘** ✓（结构变更确实发生）|
| **② 对话框自述** | `导入成功：14 个 Block` ✓ | `导入成功：14 个 Block` ✓ | 补丁**没有改变导入行为** ✓ |
| **③ 状态栏块数**（`StatusBar.ets:19` 的 `@Watch('onStatsDirty')` ✓）| **1 块 → 1 块** ✗（**不刷新**）| **15 块 → 29 块** ✓✓ | **bump 生效** ✓ |
| **④ 界面行**（Journal 今日节的行数）| **1 行 → 1 行** ✗（**不刷新**）| **15 行 → 29 行** ✓✓ | **行就地刷新** ✓（含**内嵌 `BlockList`** ✓）|
| **⑤ 下一节标题 y**（`2026年10月1日 星期四` 的 `top`）| **600 → 600** ✗（**不动**）| **1541 → 2556** ✓（≈ +15 行）| 同一结论的**独立一条** ✓ |
| 截图 | `w11_04_armA.jpeg`（对话框「导入成功」+ 今日节**仍只 1 行** ✓ 目视可证）| `w11_05_armB.jpeg`（今日节已列出 `啊啊啊不来开n` / `w4smoke` / `[` / `TODO [[residual]` ✓ · 状态栏 **29 块** ✓）| 验证纪律 1「先看图」✓ |

**⇒ 这是本窗口最硬的一条** ✓✓：**同一台设备、同一 vault、同一注入序列**，唯一变量 = 那 6 处 bump
⇒ **「数据与磁盘都对、界面毫无反应」被设备级复现（臂 A）并在同一判据上被修掉（臂 B）** ✓✓。
> ✅ **它同时补上了 W9 的一个空洞** ✗✓：`S3-W9-收束与M3重判.md` §11 第 7 条自述
> 「**`W8-A` 的 6 条路径是否真的会表现为「行不刷新」没有实测** —— 我是按陷阱 22 的机制类推」⇒ **现已对该条做过设备级实测** ✓。

### 5.2 Ⓐ **`ShareReceiveAbility` 的入口可达性 + 落盘**（第 5 条）

| 步骤 | 判据 | 结果 |
|---|---|---|
| `aa start -a ShareReceiveAbility -b com.example.callaite --ps ohos.extra.param.key.content W11SHARE` | 磁盘字节 | `2026-10-02.md` **245 → 256 B**（+11 = `\n- W11SHARE` ✓）· **插在页首**（`head -3` 实测 `- W11SHARE` 是第 1 行 ✓ —— 该方法 `leftId: ''` ✓）|
| 同上 | 界面 | 枚举到 `Text W11SHARE [id:340] [top: 751, left: 1379]` ✓（`setCurrentPage(today)` 后停在今日页 ✓）|
| **同一命令再跑一次** | 磁盘 | **+0** ✗ ⇒ 登记 **`W11-A`**（无 `onNewWant`，§3）|

> ⚠️ **诚实边界** ✗：**这一条不构成「bump 生效」的证据** —— 该 Ability 自己 `loadContent` 后才插入，
> 且插入后立即 `setCurrentPage(today)`（会**新建** `BlockList` 实例 ⇒ `aboutToAppear` 本来就会读到新行 ✓）。
> ⇒ 它的等级是「**入口可达 + 结构变更落盘**」Ⓐ ✓，**bump 本身的贡献仍是 Ⓑ** ✗。

### 5.3 Ⓑ **代码级论证**（**未设备验**，逐条如实标注 ✗）

| # | 路径 | 判据（调用链 + bump 位置） | 等级 | 为什么没设备验 |
|---|---|---|---|---|
| 1 | `EditorService.pasteMarkdownAsBlocks` | `调用方 = 无` ⇒ `EditorService.pasteMarkdownAsBlocks:215` 循环末尾 bump（`inserted > 0` 才 bump）| **Ⓑ** | **零调用方 ⇒ 无入口** ✗（`W11-B`）|
| 2 | `ImportService`（**新页面分支**）| `ImportDialog.ets:106` ⇐ `importAsNewPage`（`insert-block` ×N + `new-page`）| **Ⓑ**（同分支的 `mode='current'` 已 Ⓐ ✓）| 新页面分支需要**换一个源文件名**才能验；本窗口只跑了 `mode='current'`（**同层对照**：两条分支的成败判据同源 ✓）|
| 3 | `PluginAPI.insertTodayBlock` | `BuiltinPlugins.ets:16` / `:186` ⇐ `PluginAPI.ets:127`（服务内）| **Ⓑ** | **无法在设备上隔离观测** ✗：要「今日页正被显示」∧「守卫放行」同时成立；守卫要求今日页**没有**该模板块 ⇒ 得先删占位块（**删除通道不稳** ✗），且显示面还得是 Journal（Settings 页无 `BlockList`）——**除非开副窗格**（`callaite_splitPage` ✓ 可达但本窗口预算未投）|
| 4 | `PdfViewer.createAnnotation` | `PdfPage.ets:170` ⇐ `PdfViewer.ets:101`（组件内）| **Ⓑ** | **vault 里没有 `.pdf`** ✗（`ls` 只有 4 个 `.md`），且选中文字靠 **WebView 内 `mouseup`** ⇒ 注入不可达 |
| 5 | `ShareReceiveAbility`（两个分支）| `:105` / `:135`（Ability 内）| **Ⓑ**（入口与落盘是 Ⓐ ✓）| 见 §5.2 的边界说明 |
| 6 | `EntryFormAbility.handleQuickNote` | `:240`（扩展内）| **Ⓑ** | 桌面卡片需**手工添加**到桌面 + 提交事件 ⇒ 注入不可达；且**卡片扩展是否与主 UI 同进程无法从外部证明** ✗（§9-3）|

**一条「同层对照」旁证** ✓（用户建议的替代判据）：`ImportService` 的 Ⓐ 证明的是 **`callaite_blocksVersion` → `BlockList` 的 `@Watch` 通道**（**含 `embedded: true` 的日志流内嵌实例** ✓）在设备上真实有效
⇒ 另外 5 条只要**补在同一通道的写入口**（`AppState.bumpBlocksVersion()`）就**走的是同一条已被实测的路径** ✓
⚠️ **但这是旁证、不是证明** ✗：它不检验那 5 条的**层次判断**（例如「插件层确实无处可补」），那部分仍是 Ⓑ ✓。

### 5.4 本窗口**没有**做到的（如实 ✗）

1. **没有**对 `PdfViewer` / `PluginAPI` / `EntryFormAbility` / `pasteMarkdownAsBlocks` / `ImportService`（新页面分支）做设备级验收 ✗（原因见上表）。
2. **没有**为「未修 vs 已修」之外再做一次**第三方注入通道**的交叉验证（例如用 `-fill` 之外的方式构造导入）✗ —— 但 §5.1 的 A/B 已是**同配方单变量** ✓。
3. **没有**测量本次修复的**性能代价** ✗：`bumpBlocksVersion` 会让**所有可见行**重算（W8 §6.2 已注明这是刻意的取舍：只在结构性操作上 bump、文本输入不 bump ✓）；导入/分享都是**一次 bump**（`pasteMarkdownAsBlocks` 刻意循环后合并为 1 次 ✓）。

---

## 6. 任务 ⑤：**回归**（E14 两条入口 + W10 按天幂等）

### 6.1 E14 两条已修入口**不得回退** ✓✓ —— **两条都复跑通过**

**配方**（沿用 W8 §7.1；夹具 = `2026-09-25` 页的 `w4smoke` 行，该页 **109 B** 未变 ✓）：
侧栏点开 `2026-09-25` → 点 `w4smoke` 行 ⇒ **进编辑态**（阳性对照：`-uiLayout -i` 出现 `RichEditor w4smoke` ✓，满足 AGENTS §21-④「先证明焦点在编辑器里」✓）→ 注入 `Tab(2049)`。

| 步骤 | 磁盘 | 行几何（`-uiLayout -i`，单位 px）| **就地**刷新？ |
|---|---|---|---|
| 基线 | **109 B** `5f46fc46…` | `RichEditor w4smoke [top: 1427, **left: 1316**]` | — |
| `uitest uiInput keyEvent 2049`（Tab）| **111 B**（+2 ✓ 尾行实测 `- w4smoke` → `  - w4smoke` ✓）| **left: 1362（+46）** ✓✓ | ✅ **是**（**未离开页面**）|
| `uitest uiInput click 1547 464`（= `callaite_undoBtn`）| **109 B**（−2 ✓ 逐字节回基线 ✓）| **left: 1316（−46）** ✓✓ | ✅ **是**（同上）|

- `callaite_undoBtn` 的定位方式：`hdc shell uitest dumpLayout -p …` ⇒ 节点 `"id":"callaite_undoBtn"`、`bounds/origBounds = [1513,430][1581,498]` ⇒ 取中心 **(1547, 464)** 用 `uitest uiInput click` ✓（**勾选**：`enabled: true` / `clickable: true` ✓）。
- ⇒ **E14 的两条入口（编辑器内 Tab / 工具栏 undo）在本窗口构建上仍是「就地刷新」** ✓✓（与 W8 §7.1 同判据：`±46 px` + 磁盘 `±2 B` ✓）。

### 6.2 W10 的**按天幂等**不得回退 ✓✓

| 快照 | `2026-10-02.md` | `今日要点` 计数 | 其余三页 md5 |
|---|---|---|---|
| T0（冷启动前，含本窗口实验产物）| **245 B** / `04380c75…` | **1** ✓ | 全部一致 ✓ |
| T1（`aa force-stop` + `aa start` 之后）| **245 B** / `04380c75…` | **1** ✓ | 全部一致 ✓ |
| T2（**第二次冷启动**之后）| **245 B** / `04380c75…` | **1** ✓ | 全部一致 ✓ |

⇒ **两次冷启动 `+26 B` 后 `+0` 的 W10 判据仍然成立** ✓✓（且 **`今日要点` 恒为 1 个** ✓ —— 也顺带证明本窗口**没有**给 `insertTodayBlock` 引入任何额外副作用 ✓）。
（读法：`grep -c ''` 计数、`md5sum` 判字节；每次读取都「读到稳定」—— 陷阱 24 ✓。）

---

## 7. 任务 ⑥：**编译 + §7b**

| 项 | 结果 |
|---|---|
| **构建判据** | **`BUILD SUCCESSFUL`** ✓ —— ⚠️ pwsh 报 `exit code: 1` 是**签名 WARN 走 stderr**的固有假象 ✓（AGENTS §2）|
| 构建 #1（含修复，增量）| `BUILD SUCCESSFUL in 8 s 399 ms` ✓（`default@CompileArkTS` 缓存与 `modules.abc` 的 mtime 均已刷新 ✓）|
| **构建 #2（§7b 对抗性验证）** | **注入 6 处故意的类型错误**（Python 字节级，追加 `const __W11S7B_probe: number = 'w11s7b';` 到每个文件末尾）⇒ **`BUILD FAILED`** ✓ 且**报错恰好落在 6 个文件各自身上** ✓✓：`PluginAPI.ets:211:7` · `ShareReceiveAbility.ets:210:7` · `EntryFormAbility.ets:246:7` · `EditorService.ets:615:7` · `PdfViewer.ets:387:7` · `ImportDialog.ets:247:7` ⇒ **6 个改动文件全部在编译图里** ✓（一条构建覆盖全部 6 个 ✓）|
| 探针回退 | 字节级**精确删除**（`assert b.endswith(marker)` ✓）⇒ 6 文件 `CRLF=0 / loneCR=0` ✓、`git grep -i w11s7b` **0 命中** ✓ |
| 构建 #3（**清洁**：删 `entry\build` + `.hvigor\cache`）| **`BUILD SUCCESSFUL in 15 s 37 ms`** ✓ ⇒ **交还的包 = 清洁构建产物** ✓ |
| 产物 / 包身份 | `entry-default-unsigned.hap` **9,000,496 B @ 2026-10-02 19:57:03** ✓ · 装机 `updateTime = 1790942226336`（≈ **19:57**）✓ ⇒ **HAP mtime 早于 `updateTime`** ✓（陷阱 27 的口径 ✓，**未用 HAP MD5** ✗）|
| 行为级「设备跑的是这份源码」的**更强证据** | **臂 B 的 3 条判据全部翻正**（§5.1）⇒ 设备上跑的**确实**是含 6 处 bump 的构建 ✓✓（比任何静态标识都硬 ✓）|
| 行尾（陷阱 10）| 6 个改动文件 **`CRLF=0 / loneCR=0`** ✓（Python 字节级核验 ✓；git 仍打印 `LF will be replaced by CRLF`，是 `core.autocrlf=true` 的固有行为 ✓）|

---

## 8. 任务 ⑦：**对症 vs 顺手加固**（分开说明 ✓）

| 类别 | 内容 |
|---|---|
| **对症（= 本窗口裁定范围）** | **6 条路径 7 处 bump** ✓：`EditorService:215` · `ImportDialog:93`/`:106` · `PluginAPI:127` · `PdfViewer:101` · `ShareReceiveAbility:105`/`:135` · `EntryFormAbility:240`（+ 2 处 import）—— **每条路径恰好一处** ✓ |
| **顺手加固** | **无** ✗ —— 本窗口**刻意不加**任何「保险起见也补一个」的重复 bump ✓（`EditorService` 其余方法、`ImportService` 内部、`WorkspaceService`/`OutlinerEngine` 全部**未动** ✓，保持陷阱 22 的分工 ✓）|
| **刻意不做** ✗ | · 不删 `pasteMarkdownAsBlocks`（陷阱 2 ✓）· 不动 `collapseAll`/`expandAll`/`toggleCollapse`（W8-B 零调用方 ✓）· 不动 W10 的按天幂等守卫 ✓ · **不修 `W11-A`（`onNewWant` 缺失）**——属另一类缺陷，只登记 ✓ · 不给 `StatusBar`/`BlockList` 加新的刷新通道 ✓ |
| **本窗口发现但未修（登记）** ✗ | ① **`W11-A`**：`ShareReceiveAbility` 第二次分享静默丢弃（无 `onNewWant`）Ⓐ ✓ · ② **`W11-B`**：`pasteMarkdownAsBlocks` 零调用方（口径登记）Ⓑ ✓ · ③ **新通道纪律**：导入的源文件路径**必须用应用视角** `/data/storage/el2/...`（shell 视角 `/data/app/el2/100/base/...` 会让应用 `readTextSync` 失败 ✗）✓ —— 建议补进 AGENTS §3 ✓ |

---

## 9. 任务 ⑧：**我无法自证的项**（✗ 逐条）

1. **`PdfViewer` / `PluginAPI` / `EntryFormAbility` / `pasteMarkdownAsBlocks` / `ImportService`（新页面分支）5 处 bump 没有设备级证据** ✗ —— 全部只有 Ⓑ（调用链 + bump 位置），原因逐条见 §5.3。
2. **`PluginAPI` 的 bump 在设备上不可隔离观测** ✗ —— 要「今日页正被显示」∧「守卫放行」同时成立；本窗口未投预算开副窗格（`callaite_splitPage` 通道**未实测** ✗）。
3. **`EntryFormAbility`（卡片扩展）与主 UI 是否同进程，无法从外部证明** ✗ —— 若被系统放进**独立进程**，那一行只在该进程的 `AppStorage` 里建键（**无害但无效** ✓）；无卡片实例 ⇒ `ps` 也看不到 ✗。**该层判断因此带一个未闭合的前提** ✗。
4. **`ShareReceiveAbility` 的 bump 是否真的刷新了主窗口，未验** ✗（§5.2 边界；该 Ability 走的是「新建 `BlockList`」路径，本身就会读新数据）。
5. **`W11-A` 的归因只到「与 `onNewWant` 未实现一致」** ✗ —— **没有**做 `hilog` 级取证（没打 `onNewWant` 探针）；「第二次 `aa start` 是走 `onNewWant` 还是被系统合并/拒绝」**无法从外部区分** ✗。
6. **「应用视角路径」这条纪律只有 1 个反例 + 1 个正例** ✗（`/data/app/el2/…` ⇒ `导入失败`；`/data/storage/el2/…` ⇒ `导入成功：14 个 Block`）⇒ 机制（SELinux/沙箱路径解析）**未归因**，只是**行为级**结论 ✓。
7. **「零调用方」是 `grep` 级判定** ✗ —— 不排除动态/字符串形式的调用点（本仓无 `eval`/动态 `require` ⇒ 风险低，但未穷举 ✓）；`ImportService` 的「唯一调用方」同理 ✓。
8. **模拟器 ≠ 真机** ✗：本窗口全部 Ⓐ 只在 `MateBook Pro`（2in1 / API 26）上成立 ✓。
9. **本窗口未测性能** ✗：没有测「一次导入后全表重建」的耗时/内存（本仓 W5-W9 的性能红线读数不在本窗口口径内 ✓）；也未在**大页面**（如 1037 块的 `2026-09-30`）上试导入（刻意避开 ✗ —— 那会把 1037 块灌进今日页 ✓）。
10. **A/B 的「唯一变量」有一处不纯净** ✗：臂 A 与臂 B 的**起始 vault 不同**（臂 A 起点 26 B，臂 B 起点 135 B）。
    但我把**同一条判据的两次读数**都取了（磁盘增量 ≈ +109/+110 B ✓、状态栏与行数**在各自臂内前后对比** ✓）⇒ **不影响结论方向** ✓，**如实登记** ✗。

---

## 10. 任务 ⑨⑩：**`git status` 前后对照 + 交还时状态**

### 10.1 仓库

| 项 | 状态 |
|---|---|
| HEAD | **`94cea91`**（**本窗口未提交** ✓）|
| `git status --short`（开工）| **空** ✓ |
| `git status --short`（收工）| **6 个修改，0 个未跟踪** ✓：`entry/src/main/ets/services/EditorService.ets` · `entry/src/main/ets/components/common/ImportDialog.ets` · `entry/src/main/ets/plugins/PluginAPI.ets` · `entry/src/main/ets/components/extensions/PdfViewer.ets` · `entry/src/main/ets/shareability/ShareReceiveAbility.ets` · `entry/src/main/ets/entryformability/EntryFormAbility.ets` |
| `git diff --stat` | `6 files changed, 84 insertions(+), 6 deletions(-)` ✓ |
| 红线文件 | **未触碰** ✓（`main_pages.json` / `rawfile/spike/*` / `rawfile/libs/**`）|
| 探针残留 | **0** ✓（`w11s7b` 零命中 ✓）|
| 临时产物 | 全部在仓库外 `F:\DevEcoStudioProjects\.dsh_tmp\w11\` ✓（截图 3 张 + `uiLayout` 快照 2 份 + dumpLayout 2 份）|

### 10.2 设备（交还时）

| 项 | 状态 |
|---|---|
| 实例 | **`MateBook Pro`（2in1）运行中** ✓；`hdc list targets` = **`127.0.0.1:5555`** ✓；**唯一在跑** ✓；**未启平板** ✓ |
| 已装包 | **本窗口的清洁构建**：`updateTime = 1790942226336`（≈19:57）✓ |
| 应用 | 前台停在**今日日志页**（`ShareReceiveAbility` 的 `setCurrentPage(today)` 之后 ✓）；进程存活 ✓ |
| 新增崩溃 | **未做** `/data/log/faultlog/faultlogger/` 清点 ✗（本窗口未做崩溃类判据，故未取样 —— **如实登记** ✗）|

### 10.3 vault（**逐文件字节 + MD5**，交还与开工对照）

| 文件 | 开工 | 交还 | 变化说明 |
|---|---|---|---|
| `2026-09-25.md` | 109 B / `5f46fc46…` | **109 B / `5f46fc46…`** | ✅ **逐字节不变** ✓（E14 回归的 `Tab` 与 `undo` **精确互逆** ✓）|
| `2026-09-30.md` | 3953 B / `7d6192c1…` | **3953 B / `7d6192c1…`** | ✅ **全程未变** ✓ |
| `未命名.md` | 102 B / `7e7c1931…` | **102 B / `7e7c1931…`** | ✅ **全程未变** ✓ |
| `2026-10-02.md`（今日页）| 26 B / `2f6c6187…` | **256 B / `2bdd6d77…`（30 行）** | ⚠️ **本窗口的实验产物**：臂 A 导入 +14 块（→135 B）· 臂 B 导入 +14 块（→245 B）· `ShareReceive` 分享 +1 块（→256 B）⇒ **共 +29 块** ✗（**全部是「导入/分享」这两条被测路径自己的产物** ✓）；**W10 占位块恒为 1 个** ✓ |
| 自建页面 | — | **0** ✓（未新建任何页面；`ls` 仍是 4 个 `.md` ✓）|

> ⚠️ **交还时的 vault 说明** ✗：今日页不再是 W10 的 26 B 稳态（**+29 块**）。
> 这是**不可避免**的：`W8-A` 的第 2/5 条路径的**唯一可注入通道**就是「真导入一次 / 真分享一次」（`-fill` 不能替换内容 ✗、`graph/` 对 shell 只读 ✗ ⇒ 无法从外部复位）。
> **清场手段**：应用内 `⋯ → 删除`（W10 用过 ✓）或选中块删除；**本窗口未清**（删除通道本轮未验活 ⇒ 不冒险 ✗）。
> ✅ **可安全点开**：新增块内容全部来自 `2026-09-25.md`（**不含**「以 `[[` 开头且 `]]` 之后还有字符」的串 ✓ —— 陷阱 37 的崩溃形态不成立 ✓）。

---

## 11. 文档侧交付（回填）

| 文件 | 动作 |
|---|---|
| `docs/S3-W11-W8-A补bump.md` | **新建**（本文件）✓ |
| `docs/待验收清单.md` | 新增 **§10「W11 处置」**：`W8-A` 由「**已修 + 已设备验收（1/6 路径 Ⓐ，5/6 路径 Ⓑ）**」取代原「登记未修」；并登记新查出的 `W11-A`（`onNewWant`）✓ |
| `EXEC-PLAN.md` | 新增 **§22.10「W11 = `W8-A` 补 bump 窗口」** ✓ |
