# S3 · 前置 A 与接入形态设计（EXEC-SPRINT-02 / W1）

> **文档性质**：**设计文档**（设计优先，不含实现）。W1 窗口交付物。
> **已定案的上级决策（直接采纳，不再论证）**：
> 1. **接入形态 = B（块级按需实例化）** ✓ —— 把 `BlockView.ets:304-318` 的 `WebEditor` 槽位换成**原生 `RichEditor`**；同一时刻每窗格至多 1 个实例（焦点行才有实例）；**A（整页单缓冲区）保留为显式可选模式**（= 今天的 `PageView.integralMode` ✓）；**明确不做 B1（每行常驻实例）** ✗
> 2. **前置 A 走「设计优先」** ✓ —— 先出设计，不先写 spike 代码 ✓
>
> **本窗口实测环境**：模拟器 `MatePad Pro 13`（HarmonyOS / API 26 / 2880×1920 横屏 / density 2.0）；`hdc` 目标 `127.0.0.1:5555`。
> **代码基线**：`ec432fb`（W12-U2.3）。**本窗口结束时工作区对该基线零改动**（`git status --short` 为空 ✓）。

---

## 0. 结论速览（TL;DR）

| # | 结论 | 证据强度 |
|---|---|---|
| **C1** | `focusControl.requestFocus(id)` **能命中原生 `RichEditor`** —— B 形态的最大技术假设**成立** ✓ | 阳性 + 阴性对照实测 ✓ |
| **C2** | 两实例间迁移焦点：**文本无损 · IME 不闪 · 不重建** ✓ | 双实例指纹前后一致 ✓ |
| **C3** | 但 `onDidChange` **在开发者在 `onReady` 里 `addTextSpan` 回填时也会触发**（`before=[0,0) after=[0,len)`）⇒ B 形态**首个实例必须自带回填闸**，否则「回填 → onDidChange → 再回填」自激 ✗ | 首次实测发现，非理论 ✓ |
| **C4** | **前置 A 的范围可以大幅收窄**：选 B 后「整页增量 span 更新」整套机器可以砍掉 ✗，剩余范围 = **单块内脏段增量**（甚至可选）✓ | 设计推演 + A/B 研究结论复核 ✓ |
| **C5** | **ANR 在本形态下不复现**（298 行夹具 × 连打 70 键：70/70 成功、单键中位 222.8ms、无 >500ms、无新 appfreeze）✓ | 实测 + 系统日志反证 ✓ |
| **C6** | ⚠️ **但 B 形态不是 ANR 的解药**：历史 ANR（`appfreeze-…20260929`）发生在 **1 个块 / 66 字节**的页面上 ✗ ⇒ 「按块缩小重建范围」**在原理上不可能**修掉它 | 历史 fault 报告硬证据 ✓ |
| **C7** | 🔴 **新发现（独立缺陷，与 ANR 无关）**：`IntegralEditor` 的 live 编辑**根本不落盘** —— 连打 70 键改了 UI 与内存，`__S1_long.md` **逐字节不变**（4661 B / MD5 `501bf94f…`），重启后内容回滚 ✗ | 磁盘字节 + 冷启动双重证据 ✓ |
| **C8** | 「行级上下文」的**唯一跨块传播项是 fenced code 的 `inCodeBlock`**（以及 `inBold/inInlineCode/inHighlight` 的跨块溢出）；标题/引用/列表/HR 都是**行内局部**，可在单块内重算 ✓ | 源码逐行核实 ✓ |

---

## 1. 前置 A 的范围重划

### 1.1 原问题（重述，已复核）

`IntegralEditor.rebuildSpans()`（`IntegralEditor.ets:223-258`）在每次 `onDidChange` 时：

```
LivePreviewHelper.extractText(controller)      // getSpans() 求和 → 全页字符串
  → livePreview.buildSpans(controller, text, caret)
       → controller.deleteSpans()              // 全清
       → buildSpansInternal: parseMarkdownSegments(全页) → 逐段 addTextSpan   // 全量重建
```

即**单键成本 = O(全页段数)**，且**全程同步占主线程、不 yield**。

### 1.2 「选 B 之后 ⇒ 前置 A 几乎自动成立」—— **复核结果：方向成立，但表述必须收紧** ⚠️

**成立的部分** ✓：B 形态下每个实例只承载**一个块**的文本 ⇒ 单键成本从 `O(全页段数)` 降到
`O(该块段数)`。对典型笔记（每块几十字符、1–6 个段），这是 **2–3 个数量级**的下降。

**必须收紧的部分** ✗：
1. 「几乎自动成立」**只在 O(n) 这一维上成立**。见 **C6**：历史 ANR 发生在 **1 块 / 66 字节**的页面上
   ⇒ 那次挂起的成因**不是扫描成本**。
2. ⇒ **不能把「选 B」当成「前置 A 的验收通过」**。B 降低**平均**单键成本；它不消除**单次调用的无界停顿**。
   二者是**两个独立的失效模式**，必须分开记账（见 §1.5）。

### 1.3 选 B 之后**可以砍掉**的（相对「整页增量 span 更新」方案）

| 原「前置 A」若按整页做所需的东西 | 选 B 后 | 理由 |
|---|---|---|
| 全页旧/新文本 diff（求脏区间） | ✗ **砍掉** | 实例只持有自己那一块的文本；脏区间由 `onDidChange` 的 `rangeBefore/rangeAfter` 直接给出，无需 diff ✓ |
| 全页「段数组 ↔ 字符 offset」映射表 + 增量维护 | ✗ **砍掉** | 缩到单块后该表只有个位数条目；且可整块重算 |
| 全页 `deleteSpans(range)` 的区间运算与边界钳制 | ✗ **砍掉** | 单块内区间天然落在 `[0, len)`，越界风险归零 |
| 跨段/跨行的样式上下文重算（局部依赖追踪） | ✗ **砍掉** | 单块内整块重算即可（见 §1.4 的取舍） |
| 光标/选区在重建后的位置恢复（按全页绝对 offset） | ✗ **砍掉** | 块级编辑器的 caret 天然是**块内相对 offset**，不会因邻块变化而漂移 ✓ |
| 整页重建期间的输入排队 / 合并 | ✗ **砍掉** | 单块重建的同步时间远低于一帧，无需排队 |
| 一次性数据迁移（把已有整页 markdown 切成块） | ✗ **砍掉** | 块数据本来就在 `BlockTree` 里；A 模式保留即可覆盖整页场景 |

### 1.4 剩余范围（**唯一还需做的**）

> **前置 A（重划后）= 单块内的 span 局部更新** —— 且它**是否值得做**取决于实测。

分层设计，**按序推进，前一层不够再上下一次层**：

- **A-0（默认落点，强烈建议先只做这一层）**：块内**整块重建**。
  `deleteSpans()`（无参，只作用于本实例）+ 对**本块** `parseMarkdownSegments` + 逐段 `addTextSpan`。
  - 复杂度：`O(该块段数)`，典型 1–6 段 ⇒ 单键亚毫秒级。
  - **零增量机器**、零 offset 维护、零边界条件 ⇒ 与今天 `LivePreviewHelper` 的代码形状几乎一致，
    只是 `text` 从「全页」换成「本块」。
  - **判据**：A-0 落地后，若单键 `rebuildSpans` 的 P99 仍 > 8ms（一帧的一半），再考虑 A-1。

- **A-1（可选优化）**：块内**脏段增量**。
  - 用 `onDidChange(rangeBefore, rangeAfter)`（`text_common.d.ts:466`：
    `OnDidChangeCallback = (rangeBefore: TextRange, rangeAfter: TextRange) => void`）
    定位受影响的段区间 → 只对这段调 `deleteSpans(range)`（`rich_editor.d.ts:2552`）+ `addTextSpan(content, {offset})`（:2390）。
  - **必须付的代价（这是 A-1 独有的、A-0 没有的）**：块内「段数组 ↔ 字符 offset」映射的增量维护。
    `rangeBefore/rangeAfter` 给的是**字符区间**，而 `deleteSpans`/`addTextSpan` 也吃字符区间 ⇒
    只要**每段起止 offset** 这张小表在每次编辑后同步平移即可，**不需要**按 `getSpans()` 逐项比对。
  - 提前排除的伪方案 ✗：`updateSpanStyle`（:2529）**不能**用来做增量 —— 文本变了以后 span 边界随之改变，
    单靠改样式无法表达「插入/删除」。它只能用在「文本不变、仅样式随光标翻转」的场景
    （即今天的 syntax 显隐 ✓，那部分**保留**）。

- **A-2（正交，不属前置 A 但必须登记）**：**消除无界单次停顿**。
  见 §1.5。`rebuildSpans` 内部目前是「一条同步长任务」；无论扫描范围多小，
  只要出现病态输入就可能长时间不返回。**A-0/A-1 都不修这个** ✗。

### 1.5 为什么不能把「选 B」当作 ANR 的验收通过（**本节是本次设计最重要的修正**）

历史 fault 报告（`/data/log/faultlog/faultlogger/appfreeze-com.example.callaite-20020059-20260929211345808.log`）实测：

| 项 | 值 |
|---|---|
| `Reason` | `THREAD_BLOCK_6S` |
| `Current Running` 起始 | `2026-09-29 21:13:37.802` |
| 抓栈时刻 | `2026-09-29 21:13:42.357` ⇒ **主线程已阻塞 ≈4555 ms** |
| 阻塞中的 task | `ArkUIAceContainerNonPointerEvent`（RichEditor 事件路径） |
| 主线程栈顶 | `BuiltinStub_StringCharAtStwCopy`（逐字符读取） |
| **当时页面规模** | `[IntegralEditor] loaded page=未命名 6 blocks=1 mdLen=66` ⇒ **1 个块 / 66 字节** ✗ |

**这张表推翻了「ANR 是全文扫描成本」的解释**：66 字节的页面上不可能有「扫全文慢」这回事。

旁证（另外 3 份历史 fault 报告，`2026-09-27` 三连）：
`Reason` 同为 `THREAD_BLOCK_6S`，但**栈顶各不相同**（`BCStub_HandleTonumericImm8StwCopy` /
`BCStub_HandleReturnStwCopy` / `BCStub_HandleCallthis2withnameImm8Id16V8V8V8StwCopy`），
主线程阻塞时长分别 ≈12.4s / 12.3s / 12.5s，且当时 `Current Running` 是 `ArkUIRunPageUrl`。
⇒ **同一现象、不同栈顶** ⇒ 症状是「主线程被一次超长同步调用占住」，而不是某条固定慢路径。

**因此**：
- **前置 A 的验收判据不能是「选 B 了」**，必须是**对抗性压力测试**：
  在块级实例上构造病态输入（长单段、未闭合围栏、大量成对/未成对 `**`/`` ` ``/`==`、超长单行无换行、
  深缩进续行等），断言单次 `rebuildSpans` 有**上界**。
- 若压力测试仍能触发长停顿 ⇒ **需要的是 A-2**（给解析/重建加**上界与让出**：
  段数/字符数上限熔断、超限退化为纯文本 span、必要时分包到多个 task），而**不是**继续缩小扫描范围。
- ⇒ **对 EXEC-SPRINT-02 的排期建议**：前置 A 的「整页增量」部分可以**整段删除**（省下的是原本最大的一块），
  省下的预算**转投 A-2 的压力测试**。这一条请上级裁决。

---

## 2. B 形态（块级原生编辑器）落地设计

### 2.1 组件位置与命名

| 项 | 建议 |
|---|---|
| 新组件 | `entry/src/main/ets/components/outliner/BlockEditor.ets` |
| 命名理由 | 与 `WebEditor.ets` **同级同构**（都是「块内容编辑器」），文件名直述职责；不用 `NativeEditor`（「原生」是手段不是职责），也不用 `BlockRichEditor`（把 SDK 类型写进名字，将来换实现即失义） |
| 替换点 | `BlockView.ets:304-318` 的 `if (this.isEditing) { WebEditor({...}) }` 分支 → `if (this.isEditing) { BlockEditor({...}) }` |
| 参数面 | **刻意与 `WebEditor` 对齐**：`blockUuid` · `initialContent` · `pageName` · `fontSize` · `onSave` · `onAction` ⇒ `BlockView` 侧只改**类名**，参数与回调逐字不变（改动面最小化 ✓） |
| 职责边界 | **只做「显示 + 编辑 + span」**；一切数据/结构操作（新块、缩进、删除、落盘）**照旧走 `EditorService` / `WorkspaceService`**，与 `WebEditor.NativeBridge` 同构 ⇒ `undo/redo` 落盘与行刷新链路**零改动** ✓ |
| 与 `WebEditor` 的关系 | **两个并存**（`WebEditor` 保留），由 `BlockView` 按一个模式常量二选一。**不合并成一个组件的 `mode` 分支** ✗ —— 二者内部（WebView 桥 + HTML vs 原生 span）几乎没有共享代码，合并只会得到一堆 `if` |

### 2.2 实例生命周期

**创建**：`BlockView.isEditing` 由 `false → true` 时创建（`if (this.isEditing)` 分支）。
**销毁**：满足任一即销毁 ——
1. `isEditing` 由 `true → false`（`onSave` 回调 / Esc / 焦点迁移）；
2. `BlockView.aboutToDisappear()`（`LazyForEach` 回收该行 / 切页 / 折叠把该行移出可见集）。

**销毁前必须做的事（顺序固定，不可交换）**：
```
① 从 RichEditor 读回文本（getSpans 求和）
② 与 BlockData.content 比对；不同才 EditorService.updateBlockContent(uuid, text)
③ DirtyPageTracker.flushNow()
④ 释放 controller / 清 span 重建计时器 / 反注册
```
> ⚠️ **②的「不同才写」是硬要求**：`onDidChange` 会在**回填时也触发**（见 **C3**），
> 若无脑回写，`onReady → addTextSpan(初始内容) → onDidChange → 回写` 会凭空制造一次「内容变更」，
> 且会把首次回填的**空提取**风险重新引入（这正是 `IntegralEditor.handleEditorChange` 今天要防的事）。

**与 `LazyForEach` 回收的对齐（关键）**：
- 行的键是 `row.uuid` 且**刻意不改**（AGENTS §7 陷阱 15 / W10 修法）⇒ 实例复用发生在**行级**，
  而块编辑器实例是**行内 `if` 分支** ⇒ 行被复用时该分支会被重新求值，
  旧实例走 `aboutToDisappear`（必须落盘 ✓），新实例走 `aboutToAppear`。
- ⇒ **「行不被重建」这一 W10 成果被完整保留** ✓：`BlockDragLayer` 的命中表仍按 `BlockView` 实例注册，
  不会因为块编辑器实例的生死而被成批清空 ✓。

### 2.3 焦点模型

**权威只有一个：`EditorService.focusedBlockUuid`** ✓（`:17-18` / `setFocusedBlock :48-53` / `getFocusedBlockUuid :55-57`，
并镜像到 `AppStorage['callaite_focusedBlock']`）。

数据流：

```
用户点击某行
  → BlockView.onClick → EditorService.setFocusedBlock(uuid)     // 权威写入（同时 flush 上一块的脏页 ✓）
      → AppStorage 'callaite_focusedBlock' 变化
          → 目标行 BlockView.focusedBlockUuid @Watch → isEditing = true → 创建 BlockEditor
          → 其他行 同 @Watch → isEditing = false → 销毁自己的 BlockEditor（先落盘 ✓）
BlockEditor.aboutToAppear（或 onReady 后一帧）
  → focusControl.requestFocus('block_editor_' + uuid)            // 只是「把系统焦点交给它的手段」
BlockEditor.onFocus / onBlur
  → 只上报（用于行内视觉态），**不改** focusedBlockUuid ✗       // 防止「焦点回调 → setFocusedBlock → 焦点回调」回环
```

**`focusControl.requestFocus(id)` 与 `focusedBlockUuid` 的关系**（明确写清）：
- `focusedBlockUuid` = **语义权威**（谁"在被编辑"），也是 `undo/redo`、`Tab` 缩进、光标上下移动等
  `EditorService` 操作的**唯一依据**（既有代码全部读它 ✓）。
- `requestFocus(id)` = **实现手段**（把 OS/IME 的输入焦点交给那个原生控件），**不是权威、不参与判定**。
- 二者关系是**单向派生**：`focusedBlockUuid` 变 ⇒ 才去 `requestFocus`；反向不成立 ✗。
- **必须用 `.id()` 而不是 `defaultFocus`**：`defaultFocus` 只在**构建期**生效，而块编辑器的创建时刻由焦点迁移决定 ⇒
  用 `defaultFocus` 会在「先构建、后求焦」的时序下失效。仓库同手法见 `ContentArea.ets:97` + `:136` ✓，
  以及 `CommandPalette.ets:402` / `SearchPanel.ets:139` 的**下一帧请求**约定 ✓。

**实测得到的时序约束（必须写进实现）** ✗：
> `requestFocus` 要在**组件完成布局之后**才有意义。本仓既有注释（`CommandPalette.ets:402`）已写明
> 「`aboutToAppear` 阶段组件尚未完成布局，立即 requestFocus 可能落空」。
> 本次探针实测：从 `requestFocus(probe_ed_a)` 到 `onFocus` 回调之间 **≈620 ms**
> （`14:01:16.385 → 14:01:17.005`）。
> ⇒ 实现应在 **`onReady` 回调之后的下一帧**（`setTimeout(…, 0)` 或 `getUIContext().runScopedTask`）请求，
> 并**接受它是异步的**：不要在请求后同步断言「已获焦」✗（AGENTS §7 陷阱 19 判据①）。

### 2.4 与既有装置的关系（逐条零破坏承诺）

| 既有装置 | 依赖的机制（现状） | B 形态下的影响 | 结论 |
|---|---|---|---|
| **`BlockDragLayer` 命中表** | 按 **`BlockView` 实例**在 `aboutToAppear` 注册 / `aboutToDisappear` 反注册 / `onAreaChange` 回填矩形（`registerBlockRow` / `invalidateBlockRow` / `unregisterBlockRow`，`BlockDragLayer.ets:143/172/935`） | 块编辑器是**行内 `if` 分支**，**不改变 `BlockView` 实例的身份与生命周期** ⇒ 注册/反注册/回填时机**逐字节不变** ✓ | ✓ **零影响** |
| | 但：编辑器实例出现/消失会改变**行高** | `onAreaChange` 本来就会因行高变化重新触发 ⇒ 命中表自动跟上 ✓ **不需要新代码** | ✓ |
| **W10 修法**（`BlockView.depth` 由 `@Prop` → `@State` + `blocksVersion @Watch`） | 行**自读**自己的块数据，不靠父组件传参 | 与编辑器无关；块编辑器同样应遵守「行自读」原则：**`initialContent` 只用于首次回填**，后续以块数据为准（`refreshBlock()` 时若不在编辑态则重取） | ✓ **零影响** |
| **多选**（`BlockSelection` / `EditorService.selectedUuids` / `selectionVersion`） | 多选模式下点击行**不再改焦点**（`BlockView.onClick` 里 `if (this.selectionMode) return;`） | 该守卫在**进入编辑器之前**生效 ⇒ 多选模式下根本不会创建块编辑器 ⇒ `WebEditor` / 快捷键 / 编辑器语义**不与多选互相干扰**这一既有结论**继续成立** ✓ | ✓ **零影响** |
| **折叠**（`BlockTree.getVisibleBlocks` / `collapsed`） | 折叠把子孙移出可见集 ⇒ `LazyForEach` 销毁那些行 | 被销毁的行若不是编辑态，则**没有块编辑器实例**；若是编辑态 ⇒ 走 §2.2 的销毁序列（先落盘再销毁）✓ | ✓ 需实现销毁序列 |
| **`undo/redo` 落盘 + 行刷新** | 走 `OutlinerEngine` + `bumpBlocksVersion` | 块编辑器**不参与**结构操作；文本编辑仍走 `update-block`（**不** bump 版本 ✓）⇒ 不存在「每次按键重算可见行」 | ✓ **零影响** |
| **`AnchorRegistry` + 跳块 / `OverlayKeyRouter` + 组词守卫** | 与块内容编辑无关 | 唯一新增风险：块编辑器**新增了一个 IME 输入目标** ⇒ 组词守卫的判定对象从「WebView 内的 contenteditable」变成「原生 `RichEditor`」。**必须复核 `OverlayKeyRouter` 的组词态判据对原生 RichEditor 是否同样成立** ⚠️（见 §5 未决项 U3） | ⚠️ **需复核** |
| **快捷键重排（W12-U2.3）** | `ContentArea.onKeyEvent` → `ShortcutService.handleKeyEvent` | 原生 `RichEditor` 会**消费**一部分按键（Tab/Enter/方向键）。今天 `WebEditor` 是**自持按键**（HTML 内 `keydown` 拦截后经桥回传）⇒ 换成 `RichEditor` 后，**哪些键在应用侧、哪些键在编辑器内，需要重新确认** ⚠️（见 §5 未决项 U2） | ⚠️ **需复核** |

### 2.5 单块内的脏段增量（A-1 详设，**可选层**）

```
onDidChange(rangeBefore, rangeAfter)
  ① 新文本 = getSpans() 求和（或维护镜像字符串，避免每次 getSpans ✗）
  ② 若 rangeBefore 与 rangeAfter 等长且内容相同 ⇒ 直接 return（幂等短路）
  ③ 段重算：只用 (新文本, caretOffset) 重算**受影响的段区间**
     - A-0 落点：整块重算（不依赖 ①②③ 的精确性）
     - A-1 落点：按 range 求「脏段区间 [segI, segJ)」
  ④ controller.deleteSpans({ start: segStart(segI), end: segStart(segJ) })
  ⑤ for k in [segI, segJ): controller.addTextSpan(seg[k].text, { offset: segStart(k), style: … })
  ⑥ 平移 offset 表：把 segJ 及其右侧各段的 start 加上 (lenAfter - lenBefore)
```

**为什么 A-0 是推荐落点**：块内段数是个位数 ⇒ ③④⑤ 的整块版本与增量版本的**实际收益差在微秒–亚毫秒级**，
而 A-1 引入了 offset 表这一**新的可错状态**。先做 A-0、用实测 P99 决定是否需要 A-1 ✓。

### 2.6 行级上下文：块级化之后的边界怎么定（**设计要点**）

现状（`LivePreviewHelper.buildSpansInternal:263-371`）是**文档级顺序扫描**：`offset` 从 0 单调递增扫完整个 serde 段数组，
并在此过程中维护一组**跨行存活**的状态：

| 状态 | 声明 | 换行 (`'\n'`) 时是否复位 | **是否跨块传播** |
|---|---|---|---|
| `currentLineContext` | `:268` | ✓ 复位为 `NORMAL`（`:298`） | ✗ 不传播 |
| `headingLevel` | `:269` | ✓ 复位为 0（`:299`） | ✗ 不传播 |
| `inCodeBlock` | `:270` | **✗ 不复位** | ✅ **跨块传播** |
| `inBold` | `:274` | ✓ 复位（`:300`） | ✗ |
| `inInlineCode` | `:275` | ✓ 复位（`:301`） | ✗ |
| `inHighlight` | `:276` | ✓ 复位（`:302`） | ✗ |
| `offset` | `:265` | — | ✅（但块级化后改为**块内相对 offset**） |

⇒ **块级化后必须处理的只有一类**：`inCodeBlock`。

**方案（建议）**：

1. **围栏状态由「块的派生属性」承载，而不是靠扫前文得到。**
   新增 `BlockEditor.fenceOpenAt(uuid): boolean` —— 返回值语义是「**本块内容的第一行是否处在未闭合围栏内**」。
   - 实现：在**页面级**缓存一份 `blockUuid → fenceOpen`（由 `BlockTree.getVisibleBlocks()` 顺序一次算完，
     遇到 ` ``` ` 行翻转），缓存键挂 `callaite_blocksVersion`（结构性变更才失效 ✓，
     文本输入不 bump ⇒ 不产生每次按键的重算 ✓ —— 与 W10 的性能前提完全一致）。
   - **不做**「每次进块向前扫所有前序块」✗：那是 O(块数)，且与 §1.5 的「避免长同步任务」原则相悖。

2. **块边界即为「软重置点」，但要显式记账。**
   - `currentLineContext` / `headingLevel` 在块内**从 `NORMAL` / 0 起步** ✓（与现状等价，因为换行本来就复位）。
   - `inBold` / `inInlineCode` / `inHighlight` 在块内**从 `false` 起步** ✓。
     - 与现状的差异：现状里一个**未闭合**的 `**` 会把粗体**溢出到后续块**（因为只有换行不复位它们——
       而 `**` 标记本身跨行不闭合时 `inBold` 会一直是 `true`）。块级化后该溢出消失。
     - **这是行为变更，需要显式确认**（见 §5 未决项 U1）。倾向：**接受**（未闭合标记的跨块溢出是**bug 级**行为，
       不是特性）。
   - `inCodeBlock` 由 (1) 的 `fenceOpenAt` **播种** ⇒ 行为与现状**逐字节一致** ✓（除上述未闭合标记的差异）。

3. **`caretOffset` 的坐标系统一。** 现状是**全页绝对 offset**（`:287-288` 的 `cursorInside` 判定依赖它）。
   块级化后 `caretOffset` 必须是**块内相对 offset**；若沿用绝对 offset，光标在第一个块之后的任何位置都会
   判成「不在任何段内」⇒ **语法标记永不显示**（用户看不到自己正在编辑的 `**`）。
   ⇒ 这是块级化**最容易踩且最难自测**的一处 ✗，实现时必须写进注释。

---

## 3. 关键探针：`focusControl` × 原生 `RichEditor`（W1 核心）

### 3.1 探针设计（极简、用完即删）

- **组件**：临时 `components/outliner/ProbeFocus.ets` —— 同一 `Column` 内放**两个**原生 `RichEditor`，
  分别 `.id('probe_ed_a')` / `.id('probe_ed_b')`，各自带 `onFocus` / `onBlur` / `onDidChange`（打印 range）/ `onReady`。
- **入口**：临时 `pages/ProbeFocusPage.ets` + `EntryAbility` 的一个 `PROBE_FOCUS` 常量分支。
  > 之所以要一个**新**入口页：`windowStage.loadContent` 的目标必须在 `main_pages.json` 注册。
  > **临时**在 `main_pages.json` 加了一行 `pages/ProbeFocusPage`；**验证完成后已整体还原到 HEAD** ✓
  > （见 §6 收尾核对）。**没有**触碰 `SpikeHarness.ets` / `rawfile/spike/*` / `rawfile/libs/**` ✓
- **为什么用「自驱动序列」而不是点按钮** ✗：本探针页上的 `uitest uiInput click` **实测不达**
  （3 次点击全部无任何回调，而同一时刻注入按键可达 ⇒ 不是通道问题，是坐标/窗口问题）。
  ⇒ 改为把时序写进组件（`setTimeout` 阶梯），外部只负责在**已知时间窗**内注入按键与截图。
  **这一步很关键**：否则「点击没生效」会被误读成「`requestFocus` 没生效」✗（AGENTS §3 验证纪律 4）。

### 3.2 时序与判据（实测）

| 时刻 | 事件 | 观测 |
|---|---|---|
| `14:01:13.855` | 探针页挂载 | 两个编辑器均 **未**获焦 |
| `14:01:13.880/881` | A / B `onReady` 回填 | `A onDidChange before=[0,0) after=[0,47)` · `B … [0,38)` ⇒ **C3：回填也触发 onDidChange** ✗ |
| `14:01:14.4` | **阴性对照**：注入 `KEYCODE_A=2017` | **两个编辑器的内容都没变** ✓（编辑器 A 保持 47，B 保持 38；`didA=0 didB=0`） |
| `14:01:16.385` | `focusControl.requestFocus('probe_ed_a')` | 未抛错（`err=[]`） |
| `14:01:17.005` | **`A onFocus`** | ✅ **命中！** 请求→回调 **≈620 ms** |
| `14:01:19.253` | 注入 `KEYCODE_A` | `A onDidChange before=[47,47) after=[47,48)` ⇒ **真获焦，真能打字** ✓ |
| `14:01:25.384` | `focusControl.requestFocus('probe_ed_b')` | A→B 迁移 |
| `14:01:25.407` | **`A onBlur` → `B onFocus`（同一毫秒组）** | ✅ **迁移干净**（blur 与 focus 相隔 0–23 ms） |
| `14:01:27.733` | 注入 `KEYCODE_Z=2042` | `B onDidChange before=[38,38) after=[38,39)` ⇒ B 真的接手了输入 ✓ |
| `14:01:27.884` | 迁移后读回 | `A=48:97545848` · `B=39:480176182` |
| `14:01:30.384` | `focusControl.requestFocus('probe_ed_a')`（**迁回**） | `B onBlur` → `A onFocus`（相隔 31 ms） |
| `14:01:32.725` | 注入 `KEYCODE_A` | `A onDidChange before=[48,48) after=[48,49)` |
| `14:01:32.884` | 最终读回 | `A=49:23921364`（长度 48→49 ✓）· **`B=39:480176182` 与迁出前逐位相同** ✓ |

### 3.3 三条判据的结论

**① `focusControl.requestFocus(id)` 能否命中原生 `RichEditor`？** ⇒ ✅ **能**。
- **阳性**：请求后 `onFocus` 真的回调（`A onFocus` @ `14:01:17.005`、`B onFocus` @ `14:01:25.407`、迁回后 `A onFocus` @ `14:01:30.415`）。
- **可观测的结果（不止"没抛错"）**：光标可见（截图 `q_t1_focusA.jpeg` 中 `…789a|` 的插入符）+
  注入的键真的进了编辑器（47→48→49）+ **软键盘自动升起**。
- **阴性对照**：`14:01:14.4` 在**没有任何 `requestFocus`** 时注入同一键位
  ⇒ `didA=0 didB=0`、两个编辑器文本均**未变**、无软键盘
  （截图 `q_t0_negctrl.jpeg` vs `q_t1_focusA.jpeg`）。
  ⇒ **「能打字」这一现象确实由 `requestFocus` 引起**，不是「点进去本来就有焦点」✓。
- **ID 生效的直接证据**：请求后**只有** A 获焦（B 仍 `false`）⇒ 不存在「id 没生效、碰巧焦点落在某个默认元素」的替代解释 ✓。
- 对照仓内既有手法：`ContentArea.ets:97`（`focusControl.requestFocus(this.scrollId())`）命中的是**普通 `Column`**；
  **本次证实同一手法对 `RichEditor` 同样成立** ✓ —— 这是 B 形态此前唯一未实测的假设。

**② 两实例间迁移后文本是否完好？** ⇒ ✅ **完好，不丢字**。
- A：`47 → 48`（注入 `a`）→ 迁出 → 迁回 → `48 → 49`（再注入 `a`），长度与指纹**单调且自洽**。
- B：`38 → 39`（注入 `z`）；**迁回 A 之后再读，仍是 `39:480176182`，与迁出瞬间逐位相同**。
- 迁移期间**没有任何一次 `onDidChange` 携带「长度缩短」的 range**（全部是 `[n,n)→[n,n+1)` 的单字符插入）
  ⇒ 没有发生「重建 → 内容被清空 → 回填」这类丢字路径 ✓。

**③ 是否出现 IME 异常？** ⇒ ✅ **未观察到异常**。
- IME 在 A 获焦时升起，**跨实例迁移全程保持**（截图 `q_t3_focusB.jpeg` 中键盘仍在，且弹出候选条
  `TEXT / TEXTS / TEXTING`，即联想生效）。
- `blur`→`focus` 相隔 0–31 ms ⇒ 没有出现「先收键盘再弹」的可视闪烁窗口。
- **但**：本次只在**平板 + 英文字母注入**下验证，且候选条是**英文联想**而非中文组词
  ⇒ **不能外推**到「中文组词态下的跨实例迁移」（见 §5 未决项 U3）✗。

### 3.4 证据文件（`%TEMP%\callaite_probe\`，临时目录，不入仓库 ✓）

| 文件 | 内容 |
|---|---|
| `probe_hilog.txt` | 探针完整 hilog（`A00002/ProbeFocus`，含 T0–T6 全部时刻与 range） |
| `q_t0_negctrl.jpeg` | **阴性对照**截图：注入前/无 requestFocus，两编辑器文本未变、无软键盘 |
| `q_t1_focusA.jpeg` | **阳性**截图：`A onFocus` 后注入 `a` ⇒ A 内容 `…789a` + 可见光标 + 软键盘升起 |
| `q_t3_focusB.jpeg` | **迁移**截图：焦点已到 B，B 内容 `…TEXTz`，A 内容保持含 `a`，键盘未落、候选条正常 |
| `q_t5_focusA2.jpeg` | 迁回 A 后截图 |
| `callaite_appfreeze_0929.log` | 历史 ANR 报告（复制件，用于 §1.5 的规模反驳） |
| `make_fixture.py` | `__S1_long.md` 夹具重建脚本（**MD5 已核对** ✓） |

> 探针源码（`ProbeFocus.ets` / `ProbeFocusPage.ets`）**已删除**，`main_pages.json` / `EntryAbility.ets` /
> `IntegralEditor.ets` **已还原到 HEAD** ✓

---

## 4. ANR 基线量化

### 4.1 夹具与前置（按 AGENTS §7c「夹具复位法」）

| 项 | 值 |
|---|---|
| 夹具 | `__S1_long.md` = `- 测试块 2` … `- 测试块 299`，298 行，**无结尾换行** |
| 本地重建 + 核对 | `4661` 字节 / MD5 **`501bf94f19171bd19844d1724f2ecaa2`** ✓（与规定基线**逐字节相同**） |
| 推进方式 | `hdc file send` → `/data/local/tmp/` → `hdc shell "cp … <vault>/__S1_long.md"` |
| 设备侧断言 | `md5sum` = `501bf94f19171bd19844d1724f2ecaa2`，`wc -c` = `4661` ✓（**实验前已断言复位**） |
| 环境 | `MatePad Pro 13`，冷启动（`aa force-stop` + `aa start`），`integralMode = live`（实时模式） |
| 注入 | `uitest uiInput keyEvent 2017`（`KEYCODE_A`）逐次注入，每次记录 hdc round-trip 耗时 |
| 内容规模 | 298 块 / 1192 字（状态栏实测；`IntegralEditor` 侧 `mdLen` 未单独打印） |

### 4.2 结果

| 条件 | 注入次数 | 成功 | 总墙钟 | 单键 min | **单键中位** | 单键 P90 | 单键 max | >500ms | >1000ms |
|---|---|---|---|---|---|---|---|---|---|
| **`integralMode` live（`RichEditor` 在场）** | 70 | **70/70** | **15.8 s** | 206.2 ms | **222.8 ms** | 237.8 ms | 243.2 ms | **0** | **0** |
| 大纲视图（无 `RichEditor`）**对照** | 70 | 70/70 | 16.2 s | 213.9 ms | 232.8 ms | 240.4 ms | 300.3 ms | 0 | 0 |

**⇒ 未复现 ANR** ✗（无 >500 ms 的单次注入，无卡死，无进程重启）。

**系统侧反证** ✓：
- `/data/log/faultlog/faultlogger/` 中**没有** `2026-09-30` 的 `appfreeze-com.example.callaite-*` 记录
  （该目录里 Callaite 的 appfreeze 报告全部是 `2026-09-27` 与 `2026-09-29` 的历史件）；
- 70 键期间 `hilog` 中**无** `com.example.callaite` 的 `THREAD_BLOCK_3S/6S`。

**两个条件差值的解读（重要，不要过度解读）** ⚠️：
「整页重建在场」比「不在场」的**中位单键耗时低 10 ms**（222.8 vs 232.8）。
但**单键注入的 hdc round-trip 本身就 ≈200 ms 量级**，是该测量的**主导项**；
10 ms 的差落在噪声内 ⇒ 本次测量**只能证明「整页重建没有把单键成本推到 ANR 量级」**，
**不能**用来反推 span 重建的绝对耗时（这是本测量的**灵敏度上限**，见 §5 未决项 U4）。

**旁证：整页重建确实在跑** ✓ —— 70 键之后截图里，每行的 `- ` 前缀**都被隐藏**了
（`q` 显示为 `测试块 2`…而非 `- 测试块 2`）。`- ` 的隐藏只可能由 `buildSpans` 写入透明色 span 产生
⇒ **这 70 次按键确实各触发了一次全页 span 重建**，且没有造成 ANR ✓。

### 4.3 顺带发现：一个独立的（更严重的）真缺陷 🔴

同一实验里，70 键把编辑器内容改成 `测试块 7aaaaaaaa…`（**UI 与内存都变了**），
而设备磁盘上：

```
md5sum  /data/app/el2/100/base/com.example.callaite/haps/entry/files/graph/__S1_long.md
        501bf94f19171bd19844d1724f2ecaa2        ← 与实验前逐字节相同
wc -c   4661                                     ← 未变
```

再 `aa force-stop` + 冷启动 ⇒ **内容回滚**为原始 298 行 `- 测试块 N` ✗。

**根因（读源码确认）**：`IntegralEditor` 唯一写盘路径是 `applyAndRebuild()`
（`IntegralEditor.ets:189-221` 里的 `ws.replacePageBlocks(...)` + `SaveQueue.markDirty()`），
而它**只由顶部那个 ✓ 按钮调用**（`:381-383`）。`handleEditorChange()`（:260-289）**只更新 `this.markdown` 内存副本**。
⇒ 在整页编辑器里打的字，**只要不点 ✓ 就永远不会落盘**；而切模式 / 切页 / `LazyForEach` 回收都会**销毁 `RichEditor`**
⇒ 未点 ✓ 的输入**不可恢复地丢失** ✗。

> **这条与前置 A 是两件独立的事**，但**优先级更高**（数据丢失 > 性能）。
> 建议**单独立项**，不要塞进前置 A 的范围里。登记在此以免丢失。

---

## 5. 风险与未决项

| # | 项 | 性质 | 影响 | 建议处置 |
|---|---|---|---|---|
| **U1** | 块边界是否清零 `inBold` / `inInlineCode` / `inHighlight` | **行为变更**（未闭合标记不再跨块溢出） | 视觉；无数据风险 | 倾向**接受**（现行为是 bug 级）；请上级确认 |
| **U2** | `RichEditor` 对按键的消费面 vs `ShortcutService` | **回归风险**（W12-U2.3 成果） | 可能使部分快捷键失效或多触发 | 接线前先做「按键归属表」实测：对 `Tab` / `Shift+Tab` / `Enter` / `↑↓` / `Ctrl+Z` 逐个断言是应用侧还是编辑器侧收到的 |
| **U3** | `OverlayKeyRouter` 的**组词守卫**判据对原生 `RichEditor` 是否成立 | **回归风险**（W11-U2.2 成果） | 中文组词时回车可能被浮层抢走 | 必须在**中文组词态**下复跑 W11 的 A/B（AGENTS 陷阱 21：先断言候选条存在 ✓）。本次探针只验了**英文联想**，**不足以覆盖** ✗ |
| **U4** | 单键 `rebuildSpans` 的**绝对**耗时未取到 | **测量灵敏度**限制 | §4.2 只能给出「没有 ANR 量级」，给不出「重建花了 N ms」 | 若排期需要该数字：在 `rebuildSpans` 内加一对 `hilog` 时间戳插桩（本次已写过插桩，但因误把按键打进浏览器窗口而作废 ✗，非方法问题）。**注意**：插桩本身要 `git checkout` 还原 ✓ |
| **U5** | 桌面/2in1 与本次（平板）的一致性 | **设备差异** | 陷阱 21 已记录「两台机器结论不一致时先查 IME 授权状态」 | 本次结论**只在平板**成立；2in1 未复跑 ⚠️ |
| **U6** | `IntegralEditor` 不落盘（§4.3） | 🔴 **数据丢失** | 未点 ✓ 的编辑全部丢失 | **单独立项**，优先于前置 A |
| **U7** | 块级实例的**创建开销**（每行首次进入编辑都要建一个 `RichEditor`） | 性能 | 快速上下移动焦点时可能抖动 | 实现后压测「连续 ↓ 穿过 50 行」；必要时保留 1 个「热实例」池（但**注意**这不能退化成 B1 ✗） |
| **U8** | 历史 ANR 的**触发条件未知** | 未知 | 无法断言「已修」 | 见 §1.5：先补**病态输入压力测试**，再谈修复 |

---

## 6. 本窗口收尾核对（交付条件 ✓）

| 检查 | 结果 |
|---|---|
| 探针源码 `components/outliner/ProbeFocus.ets` | **已删除** ✓ |
| 探针入口 `pages/ProbeFocusPage.ets` | **已删除** ✓ |
| `resources/base/profile/main_pages.json` | **已还原到 HEAD**（仅 `pages/Index`）✓ |
| `entryability/EntryAbility.ets` | **已还原到 HEAD** ✓ |
| `components/outliner/IntegralEditor.ets`（临时插桩） | **已还原到 HEAD** ✓ |
| 禁止触碰项核对 | `main_pages.json` / `SpikeHarness.ets` / `rawfile/spike/*` / `rawfile/libs/**` ⇒ **最终均未改动** ✓；`SpikeHarness.ets` 与 `rawfile/spike/` 在本工作区**本就不存在**（已 grep 确认），未创建 ✓ |
| 临时产物 | 全部在 `%TEMP%\callaite_probe\`，**仓库内零临时文件** ✓ |
| `git status --short` | **空输出** ✓ |
| 构建 | `BUILD SUCCESSFUL` ✓（见答复） |

> 唯一的仓库外产物是本文件 `docs/S3-前置A与接入形态设计.md` ✓
> （`Callaite-工作文档/` 在仓库之外，天然不入 git ✓ 见 AGENTS §0）
