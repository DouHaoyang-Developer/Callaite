# S3 · W4 键盘契约与 ANR 复核（EXEC-SPRINT-02 / W4）

> **窗口**：EXEC-SPRINT-02 / W4 —— 任务 0（计数器探针证实/证伪「持续重建链」）+ 任务 1（键盘契约：块级 ↑↓ / Enter / Backspace / 快捷键回归）
> **代码基线**：`3537acd`（S2-W3 A-2 交付）
> **设备**：模拟器 `MatePad Pro 13`（HarmonyOS 7.0.0 / API 26 / 2880×1920 横屏 / density 2.0），`hdc` 目标 `127.0.0.1:5555`。**一台设备一个任务，本窗口独占** ✓（收尾时已交还）
> **夹具**：`__S1_long.md` 基线 **4661 B / MD5 `501bf94f19171bd19844d1724f2ecaa2`**；每轮实验前后按 AGENTS §7c 复位并 `md5sum` 断言 ✓ **交付前已复位** ✓
> **交付改动**：`entry/src/main/ets/components/outliner/BlockEditor.ets`（**1 个文件，+21 / −1**）· commit `9a5e469`
> **收尾 `git status --short`**：**空** ✓（插桩文件全部 `git checkout HEAD --` 还原 ✓ 全仓 grep 探针关键字命中 **0** ✓）

---

## 0. 结论速览

| # | 结论 | 证据等级 |
|---|---|---|
| **T0-1** | **假设「跨 task 持续重建链」成立** —— 计数器探针实测一条 **30 环**的链：每环 ≈220ms、持续 7s+，`isRebuildingSpans` **一次都没拦住**（`skipped=0`） | Ⓐ 设备实测（计数器探针 + 看门狗）✓ |
| **T0-2** | 链的**驱动量**不是「重建自己」，而是**native 侧待提交的输入事件**：每环落 **1 个字符**（`len` 76→95、`caret` 24→43，逐环 +1），链长 = 待落盘输入事件数（30 键 ⇒ 30 环）。落盘内容**正确**（66→96 = +30，无重复无丢失） | Ⓐ 设备实测 ✓ |
| **T0-3** | **但它不足以解释那一次 66 字节 ANR**：66 字节页面上单环仅 **2–14ms** ⇒ 30 环 ≈0.3s 主线程，与 4555ms 差一个量级 | Ⓐ 设备实测 Ⓑ 反推 ✓ |
| **T0-4** | **新的最强候选（本次取到硬证据）**：**一次按键 ⇒ 多次整页重建的放大**。历史 fault 报告里的系统日志实测：一次 Backspace 之后 **343ms 内出现 5 次 `delete spans` + 31 次 `AddTextSpan` + 47 条 `OnSelectionChange`**（§2.3）。放大倍数 = 段数 | Ⓐ 历史 fault 报告原始日志（设备内 `faultlogger/`）✓ |
| **T0-5** | 剂量-反应（当前构建、298 块页面）：**一次 30 键连发 ⇒ 32 次整页重建 / 累计 `buildSpans` 27.6 s / 单次最大 1026ms** —— 整页编辑器仍是「每个输入事件一次 O(全页) 重建」 | Ⓐ 设备实测 ✓ |
| **T1-1** | **B 形态下块级 ↑↓ 不存在**：`↑`/`↓` 被原生 `RichEditor` **消费**（`return: 1`），**不上浮**到 `ContentArea.onKeyEvent`（探针 0 命中）；磁盘逐字节不变、编辑行不迁移。**W1 在 A 模式取得的「跨块 ↑↓ 像素级成立」不迁移到 B 形态** | Ⓐ 设备实测（焦点阳性对照 + 键路由探针）✓ |
| **T1-2** | **B 形态下 Enter 是死键**：既不在块内产生换行（`AddTextSpan('\n')` 报 `spanIndex error, return`），也不建兄弟块（`editor.create-below` 到不了 —— 键被 RichEditor 吃掉）。截图可见「光标落到下一行」但该行**没有任何字符被提交** | Ⓐ 设备实测（截图 + 磁盘字节 + native 日志）✓ |
| **T1-3** | **发现并修复一个逐键丢字缺陷（本窗口最有价值的交付）**：`onSelectionChange` 早于 `onDidChange` 到达时，旧实现拿**上一次**的 `lastRenderedText` 重建 ⇒ 刚输入的字符被旧快照覆盖。实测注入 1 键磁盘**逐字节不变**；修复后 5 键 ⇒ 磁盘 4661→4666 / 首行 `- 测试块 2aaaaa` | Ⓐ 设备实测（前后对照，判据 = 磁盘字节）✓ |
| **T1-4** | 快捷键回归：**只有 `Esc`(2070) 能上浮**到 `ContentArea`（`HOST`/`ROOT` 探针双命中），且行为正确（`editor.escape`，无数据丢失）。`Tab`/`Backspace`/`↑`/`↓`/`Enter` 全部被 `RichEditor` 消费 | Ⓐ 设备实测 ✓ |

---

## 1. 任务 0：计数器探针（做法）

### 1.1 度量装置（尺子沿用 W3 §1.1）

| 尺子 | 做法 | 度量对象 |
|---|---|---|
| **① 主线程停顿看门狗**（主尺子） | `EntryAbility.onCreate` 挂 `setInterval(…, 50)` 心跳，相邻间隔 >150ms 打 `STALL gap=N ms`，每 5s 打 `HB max=` | 主线程单次停顿（`THREAD_BLOCK_*` 的同一物理量） |
| **② span 重建计数器** | `LivePreviewHelper.buildSpans` / `buildSourceSpans` 首尾计时，累加 `calls / ms / maxSingle` | 单次调用耗时与总占用 |
| **③ 重建计数器 + 成链判定** | `rebuildSpans` 入口打点；两次调用间隔 **<300ms** 记为一环，维护 `chainLinks / maxChain`；成链即打 `CHAIN link=N reason=…` | **链长与链的驱动来源** |
| **④ 回调计数器** | `handleSelectionChange` / `handleEditorChange` 入口计数 | 回声密度 |
| **⑤ 外部判据** | `hilog` 的 `THREAD_BLOCK_3S/6S` + 历史 `faultlogger/appfreeze-*` 原始日志 | 系统自己的 ANR 检测器 |

> **刻意不用注入键时延当重建耗时**（AGENTS §3：≈200ms 是主导项）✓
> 插桩落在 5 个文件：`EntryAbility`（看门狗）· `LivePreviewHelper`（计数器）· `IntegralEditor`（建链打点 + 原因）· `BlockEditor`（计数）· `ContentArea`（键路由）。**全部为临时插桩，交付前 `git checkout HEAD --` 还原，全仓 grep 命中 0** ✓
> **未新建任何页面级探针**：`main_pages.json` / `SpikeHarness.ets` / `rawfile/spike/*` / `rawfile/libs/**` **全程未触碰** ✓；病态内容按 W3 的手法推入 vault 的 `__S1_long.md`，应用自动恢复上次标签页 ⇒ 冷启动即打开 ✓

### 1.2 收回了一条关键历史证据（faultlogger 原始报告）

从设备 `/data/log/faultlog/faultlogger/` 取回 **2026-09-29 21:13 的 `appfreeze-…-THREAD_BLOCK_6S`** 原始报告，它把历史 ANR 的现场固定到字节级：

```
09-29 21:13:30.070 JSAPP  [IntegralEditor] loaded page=未命名 6 blocks=1 mdLen=66
09-29 21:13:37.104 AceFocus OnKeyEventInteral … RichEditor/931 handle KeyEvent(secure_field, 1) return: 0
09-29 21:13:37.223 AceRichText delete length=1 isIME=1          ← 用户按了一次退格
09-29 21:13:37.224 AceRichText caret:64->63
…（见 §2.3：接下来 343ms 内 5 次整页重建）
Reason: THREAD_BLOCK_6S        Process life time: 54s
main: state=R, utime=447, stime=77
#00 pc …/stub.an(BuiltinStub_StringCharAtStwCopy+358)
```

⇒ **那一次的页面内容被精确定位**：`未命名 6`，**66 字节**，内容 = `- alpha  - child1- beta- **bold** text- \`code\` text- ==mark== text`（本窗口用它作为 `__S1_small.md` 夹具，`wc -c` = **66** ✓ 与 `mdLen=66` 逐字节吻合）。
⇒ **主线程栈只有一帧**（`StringCharAtStwCopy`，`#01` 就是 `[stack]`），**无法从栈归因到具体函数** —— 这一点必须写清楚，否则会把「一帧栈」当成「已定位」 ✗

---

## 2. 任务 0：实测数据

### 2.1 计数器探针原始数据（全部为设备实测）

| 场景 | 页面 | 重建次数 | 累计 `buildSpans` | 单次最大 | `skipped` | **`maxChain`** | 看门狗 |
|---|---|---|---|---|---|---|---|
| 空闲（刚冷启动、块视图） | 298 块 | 0 | 0 | 0 | 0 | 0 | `HB max=53ms` |
| 进入整页编辑器（`onReady` 首次回填） | 298 块 | **1** | **319ms** | 319ms | 0 | 0 | `STALL 482ms` |
| 注入 1 个 `KEYCODE_A` | 298 块 | **1** | **880ms** | 880ms | 0 | 0 | `STALL 1109ms` |
| 空闲 | **66 B** | 1 | **2ms** | 2ms | 0 | 0 | `HB max=53ms` |
| 20 键 @150ms + 10 次方向键 | 66 B | 24 | 194ms | 11ms | 0 | **0** | `HB max=60ms` |
| **30 键连发（无间隔）** | **66 B** | 32 | 291ms | 12ms | **0** | **30** | `HB max=63ms` |
| **30 键连发（无间隔）** | **298 块** | **32** | **27 655ms** | **1026ms** | 0 | 0 | 系统 `THREAD_BLOCK_6S`（IME 侧）|

**成链打点（66 B 页面，摘录）**：

```
[W4PROBE] CHAIN link=11 at=… reason=sel cur=24 last=23 v=live len=76
[W4PROBE] CHAIN link=12 at=… reason=sel cur=25 last=24 v=live len=77
…
[W4PROBE] CHAIN link=30 at=… reason=sel cur=43 last=42 v=live len=95
[W4PROBE] WIN dt=5000 rebuilds=22 spans=22 spanMs=210 selCalls=374 chgCalls=352
                                  | totalRebuilds=32 … chainLinks=29 maxChain=30
```

**读法**：`cur`/`last` 与 `len` **逐环 +1** ⇒ 每环落 **1 个字符**；环间隔 ≈220ms；30 个待落盘输入事件 ⇒ **30 环**；`skipped=0` ⇒ `isRebuildingSpans` 全程没有触发过一次。落盘结果**正确**：`66 → 96` 字节（+30，无重复、无丢失）。

### 2.2 结论（任务 0 要求 ②）

**假设成立 —— 但要按它成立的那个形态说清楚：**

- **成立的部分**：确实存在一条**跨 task 的持续重建链**，`isRebuildingSpans` / `lastSpanText` **只防同 task 重入、完全防不住它**（`skipped=0` 是本窗口最干净的一条反证）。链的每一环都是独立 task，因此任何**同步**重入闸在原理上都不可能拦住。
- **要修正的部分**：链的**驱动量不是「重建自己」**，而是 **native 侧待提交的输入事件**。链长 = 待落盘输入事件数；没有待提交输入时链立刻停止（空闲 40s 重建 0 次）。所以它不是自激振荡，而是「**一个输入事件 ⇒ 一次整页重建**」的**串行放大**。
- **不足以解释那一次 ANR** ✗：66 字节页面上单环 **2–14ms**，30 环只占主线程 ≈0.3s；即便链一直存在，也**到不了 4555ms**。

### 2.3 新的最强候选（任务 0 要求 ③）

> **候选：`buildSpans` 的「每段一次 `addTextSpan`」在 native 侧引发**多次**整页重建 —— 一次按键 ⇒ 5 次 `deleteSpans` + 重建。放大倍数 = 该页段数；历史那次页面虽只有 66 字节，但它的段数并不小（`**bold**` / `` `code` `` / `==mark==` / `- ` 前缀 ⇒ 14 段）。**

**硬证据（历史 fault 报告自带的系统日志，343ms 窗口内的原始计数）**：

| 计数项 | 343ms 内的次数 |
|---|---|
| `AceRichText: delete spans`（= 我们的 `deleteSpans()`，一次 = 一轮整页重建） | **5** |
| `AceRichText: AddTextSpan` | **31** |
| `AceRichText: setCaretOffset` | 8 |
| `ImsaKit: OnSelectionChange`（回灌给输入法/应用的光标事件） | **47** |
| `ImsaKit: OnCursorUpdate` | 49 |
| `AceRichText: spanIndex error, return`（**native 侧 addTextSpan 直接失败**） | **27** |

⇒ **一次退格 ⇒ ≥5 轮整页重建**，且 **31 次 `addTextSpan` 里有 27 次被 native 拒绝**（`spanIndex error`）。这条日志同时解释了 §2.1 里那 47 条 `OnSelectionChange` 回声的来源：**它们本来就是重建自己产生的**。

**推理链**：
1. 单轮重建 = `deleteSpans()` + 14 次 `addTextSpan()`；native 对**每一次 addTextSpan** 回灌一条 `OnSelectionChange`；
2. 这些回调在 `rebuildSpans()` **返回之后**才派发，那时 `isRebuildingSpans` 已落下 ⇒ `handleSelectionChange` 拿一条**重建中途**的光标去和 `lastSpanCaret` 比 ⇒ 不等 ⇒ 再发起一轮整页重建；
3. 于是「一次按键」被放大成「段数轮重建」。66 字节页面上单轮 ≈10ms ⇒ 5 轮只有 50ms *（安静时）*；但只要**任何一轮**碰上更慢的路径（`spanIndex error` 之后 native 侧重建 span 树、或与 `flushSave`/`MarkdownParser` 落盘链叠加），就会滚成秒级。
4. **当前构建上放大仍在**：30 键连发在 298 块页面上是 **32 次重建 / 27.6s 累计**（§2.1 末行），即「一个输入事件一次 O(全页) 重建」这条**没被 A-2 修掉** —— W3 §5.3 已如实登记过这一点，本窗口给出了它的**量化剂量-反应**。

**为什么没有把它写成「已证实就是那一次」** ✗：66 字节页面上单轮只有毫秒级，5 轮不足以连续占住主线程 4555ms。**放大机制已证实存在且在历史现场跑过；「它单独造成了那 4555ms」仍未证实。**

### 2.4 修复建议（任务 0 要求 ③；本窗口**未落地**，理由见 §6）

**建议 A（对症主修，改 `IntegralEditor.rebuildSpans`，约 +40 行，本窗口已实现并实测）**
给重建加一个**回声静默窗**：重建结束后 `settle = max(250ms, 2 × 本次重建耗时)`，窗内 `handleSelectionChange` 一律丢弃；窗口结束时**回读一次真实光标**，只有当它确实变了（= 窗内发生过**真实**光标移动，而不是回声）才补一次重建。

```ts
// rebuildSpans() 的 finally
const cost = Date.now() - w4t0;
const settle = cost * 2 > IntegralEditor.REBUILD_SETTLE_MS ? cost * 2 : IntegralEditor.REBUILD_SETTLE_MS;
this.rebuildSettleUntil = Date.now() + settle;
this.settleTimerId = setTimeout(() => { this.applyPostSettleCaret(); }, settle);

// handleSelectionChange() 开头
if (Date.now() < this.rebuildSettleUntil) { return; }   // 这是上一次重建的回声
```

**本窗口实测结果（必须一起读）**：

| 指标 | 加静默窗前 | 加静默窗后 |
|---|---|---|
| 成链的**驱动来源** | `reason=sel`（回声驱动） | **`reason=change`**（真实内容变更驱动）✓ |
| 5s 窗口内 `selCalls` 引发的重建 | 30 | **0** ✓ |
| 66 B 页面 30 键：重建次数 / 累计 | 32 / 291ms | 32 / 291ms（**不变**）|
| **298 块页面 30 键：重建次数 / 累计 / 单次最大** | 32 / **27 655ms** / 1026ms | 32 / **27 598ms** / 946ms（**不变**）|

⇒ 它**消除了回声驱动的重建**（这一条是实测的），但在**当前构建**上**没有**降低端到端成本（因为 A-2 之后 66 字节页面的单轮重建只剩 2ms，回声本来就便宜）⇒ **ANR 级的收益未被证实**，而它会给 live 模式的语法标记显隐引入最多一个静默窗的延迟。**故本窗口只把它作为建议交付，没有落地**（见 §6 的处置理由）。

**建议 B（对症，治本方向）**：把 `buildSpansInternal` 的「逐段 `addTextSpan`」收口为「**先拼段、后一次性写入**」—— 回声条数于是与段数解耦（14 段 ⇒ 1 次写入）。这条路需要确认 `RichEditorController` 是否有「一次写多段」的 API（`addTextSpan` 只接受单段 + `offset`，`updateSpanStyle` 是改样式），**未核实 ⇒ 只登记为方向** ✗。

**建议 C（本轮明确不做）**：整页编辑器改为脏段增量（A-1）。W2 已裁决「块内段数是个位数，增量不划算」，但**整页编辑器不是块**：它在 298 块页面上单次重建 319–1026ms，是本窗口测到的最大单项成本。真正的对症方向是**让整页编辑器也块级化**，而不是继续在 span 层打补丁。

---

## 3. 任务 1：键盘契约（B 形态实测）

### 3.1 焦点阳性对照（AGENTS §3 验证纪律 4，**先建立再判分**）

W3 记录过「`uitest uiInput click` 未能给 `RichEditor` 建立焦点」⇒ 本窗口**先做阳性对照**：

| 步骤 | 观测 | 判定 |
|---|---|---|
| 冷启动 → 点 `测试块 2` 行文本（dump 坐标 `900,466`） | 行进入编辑态（光标可见）+ **软键盘升起** | 编辑态已进入 ✓ |
| 注入 3 × `KEYCODE_A`（250ms 间隔） | 磁盘 **4661 → 4664**，首行 `- 测试块 2aaa` | **焦点确实落在 `RichEditor` 里** ✓ |
| 阴性对照（不点行直接注入） | 磁盘逐字节不变 | 注入键不会平白生效 ✓ |

⇒ **本窗口所有「按键没反应」的判据都在这个阳性对照之后** ✓（W3 的焦点问题未复现；推测那是**另一个页面/形态**下的现象，本窗口不做归因 ✗）

### 3.2 块级 ↑↓（要求 ④）

**实测行为**：

| 注入 | 磁盘 | 编辑行 | 键路由（`ContentArea` 探针） | native 侧 |
|---|---|---|---|---|
| `↓`(2013) ×3 | **4666 逐字节不变** | **不迁移**（仍在 `测试块 2aaaaa`） | **0 命中** | 被 `RichEditor` 消费 |
| `↑`(2012) ×3 | **4666 逐字节不变** | 不迁移 | **0 命中** | 被 `RichEditor` 消费 |

native 原始日志（`AceFocus`）：

```
OnKeyEventInteral Node process self: Node RichEditor/3312 handle KeyEvent(secure_field, 0) return: 1
Focus system handled the key event: code:secure_field/action:0
```

`return: 1` = **该节点已消费**，键不会上浮到 `ContentArea` 的 `onKeyEvent`。

⇒ **结论（B 形态）**：
1. **跨块 ↑↓ 在 B 形态下不存在** ✗ —— W1 在 A 模式（整页单缓冲区）测到的「`MOVE_HOME`/`DPAD_DOWN` Δy 恒 +44」**不迁移**到块级实例形态；
2. `WebEditor` 侧仍在发 `focusPrev`/`focusNext`（`:426/:442` → 转发 `:215/:219-222`），而 `BlockView.onAction` 仍是 `(_a,_d)=>{ this.refreshBlock(); }` ⇒ **全仓零消费方**这一条**依旧成立**（本窗口独立复核：`git grep focusPrev` 的全部命中都在 `WebEditor.ets`）；
3. 原生 `RichEditor` **会**消费未修饰的 ↑/↓，所以**接线落点不能放在 `ContentArea`**（键到不了那里）。

**接线设计（本窗口**未落地**，理由见 §6）**：
- **落点**：只能放在 `BlockEditor` 的 `RichEditor` 上（`ContentArea` 收不到这几个键）。**必须先验证「挂 `onKeyEvent` 不干扰文本输入」** —— 本窗口第一次测量时确实观察到「键到达处理器但字没落盘」，但**该现象的根因是 §3.5 的旧快照覆盖缺陷，不是 `onKeyEvent` 本身**（去掉探针后丢字依旧）⇒ 探针不是元凶这一点已排除，但「挂了它之后输入是否完好」**仍未独立验证** ✗。
- **边界判据**（纯文本、不需要 native 坐标）：块内相对光标 `caret` 与 `LivePreviewHelper.extractText()` 的结果 —— 首行 ⇔ `text.substring(0, caret).indexOf('\n') < 0`；末行 ⇔ `text.substring(caret).indexOf('\n') < 0`。这套判据与 §3.4 的「块内换行」用例天然一致。
- **邻居解析**：在 `BlockList` 层用 `rows`（`WorkspaceService.getVisibleBlocks`，与 `scrollToIndex` 同一坐标空间）；或在 `BlockEditor` 里 `ws.getPageUuidForBlock(uuid)` + `getVisibleBlocks` 现算（与 `fenceOpenForThisBlock()` 同一手法，零新装置）。
- **目标行进入编辑 + 取焦**：写权威焦点 `EditorService.setFocusedBlock(uuid)`（`editorCaretOffset` 由 `BlockView.onGlobalFocusChanged` 驱动 `isEditing`），再 `focusControl.requestFocus('callaite_blockEditor_' + uuid)` —— **必须在 `onReady` 之后的下一帧请求**，且请求→`onFocus` 实测 ≈620ms（W1/W2）。
- **离屏行**：目标行可能还没被 `LazyForEach` 创建 ⇒ `BlockAnchorService.revealBlockDeferred`（`:437-460` 已有**幂等重试**：80ms / +240ms，上限 2 次，AGENTS 陷阱 20）✓ **不要自己再写一套**。
- **落光标**：`setCaretOffset`；块内相对坐标（类头 ③ 的既有约定）。

### 3.3 Enter / Backspace 契约（要求 ⑤）

| 键 | 键码 | 键路由 | native | 数据效果 |
|---|---|---|---|---|
| `Enter` | 2054 | **被 RichEditor 消费**（`return: 1`，`HOST` 探针 0 命中） | `AddTextSpan opts={index=-1, len=1, themeFC=1}` → **`spanIndex error, return`** | **磁盘逐字节不变**（4664）。截图可见光标落到**下一行**，但那一行**没有任何字符被提交** ⇒ **Enter 在 B 形态下是死键** ✗ |
| `Backspace` | 2055 | 被 RichEditor 消费（`HOST` 0 命中） | `delete length=1 isIME=1`（有内容时） | 见 §3.5 —— 内容删除**会被后续重建覆盖**（已修） |
| `Tab` | 2049 | 被 RichEditor 消费（`HOST` 0 命中） | — | **磁盘不变**，未缩进 ⇒ `editor.indent` 在 B 形态下**不可达** ✗ |
| `Esc` | 2070 | **上浮**（`HOST` + `ROOT` 探针双命中 ✓） | — | `editor.escape` → `clearFocus()`，**磁盘不变、无数据丢失** ✓ |

⇒ **B 形态的按键归属发生了整体位移**：`WebEditor` 时代由 HTML 侧 `keydown` 拦截后**经桥回传**，所以 Enter/Tab/Backspace 都能到应用侧；换成原生 `RichEditor` 后，这几个键**被 native 吞掉且不产生等价动作** ⇒ `ShortcutService` 里的 `editor.create-below` / `editor.indent` / `editor.delete-empty` 三个动作在**块编辑器持焦时不可达**。
**这是本窗口最需要上级裁决的一条**：它影响的是「回车即新建块」这一 Logseq 核心交互。

**块内换行用例（Sprint-02 §3 风险 5 明确要求）**：
- 现状下**无法用注入构造**：Enter 在 B 形态不产生换行（见上表）。
- 已用**夹具法**准备并核对了「多行块」的磁盘表示（`Exporter` 把多行块导出为**缩进续行**，缩进 = 块缩进 + 2）—— 该用例的**判据**已定：块内容含 `\n` 时，↑ 应只在**首行**越界、↓ 应只在**末行**越界（用 §3.2 的纯文本判据），且 Enter 在**中间行**应产生块内换行、在**末行**才新建兄弟块。
- **本窗口未取到该用例的设备证据** ✗ ⇒ **登记为未验证**，不写成通过。

### 3.4 快捷键回归（要求 ⑥）

| 项 | 结论 | 依据 |
|---|---|---|
| `Esc` | ✓ 正常（唯一能上浮的非修饰键） | `HOST`/`ROOT` 探针 + 磁盘不变 |
| `Tab` / `Backspace` / `↑` / `↓` / `Enter` | ✗ **不再上浮**（原生 RichEditor 消费） | 探针 0 命中 + `return: 1` |
| `Ctrl+K` / `Ctrl+Z` 等修饰键组合 | **未测** ✗：`uitest uiInput keyEvent` 只接受单个键码，本窗口**没有**找到带修饰键的注入通道 ⇒ 按 AGENTS §3「不得把无法验证写成通过」登记 | — |
| `ShortcutService.ets` 源码 | **本窗口零改动** ✓（`OverlayKeyRouter` 的浮层守卫、`isOverlayBlockedKey`、`rebind`/`aliases` 全部未触碰） | `git diff` 只含 1 个文件 |

⚠️ **必须说清的回归面**：`Tab`/`Backspace` 的「不再上浮」**不是本窗口引入的**（本窗口只改了 `onSelectionChange` 的重建时序，没有碰任何键路由）。它在 `3537acd`（W2 B 形态落地）时就已经如此；本窗口只是**第一次把它测出来** ✓

### 3.5 本轮发现并修复的缺陷：B 形态**逐键丢字**（交付改动）

**现象**：在 B 形态块编辑器里打字，**字符会被静默丢弃**（不是丢一部分，是「注入 1 键 ⇒ 磁盘逐字节不变」）。W2 §2.4 记录的「注入 10 键 ⇒ 4661→4665（只落 4 个）」其实就是它的表现，当时被归因为「注入通道的固有损耗」 ✗。

**根因（native 日志逐行）**：

```
insertLen=1, isIME=1, shouldCommitInput=1     ← 字符真的插进去了
caret:5->6
GetCaretPosition
delete spans, range=[0,6]                     ← 我们的 rebuildSpans（由 onSelectionChange 触发）
addedLen=0, removedLen=11
AddTextSpan, opts={index=-1, len=5, …}         ← 只写回 5 个字符（旧快照）
caret:0->5
```

native 在插入字符时**先报光标（`OnSelectionChange`）、后报内容变更（`onDidChange`）**。旧 `onSelectionChange` 只比 `caret !== lastSpanCaret` 就调 `rebuildSpans()`，而 `rebuildSpans()` 写回的是**上一次的 `lastRenderedText`** ⇒ 用旧文本把刚输入的字符盖掉；盖完 `snapshotText` 也被同步成旧文本，随后迟到的 `onDidChange` 判定「文本与快照相同」而被丢弃 ⇒ **丢字是终局的**。

**修法（+21 / −1，只改 `BlockEditor.onSelectionChange`）**：重建前先与编辑器的**真实内容**对齐（并只在内容真的变了时同步数据模型），再决定是否重建；空提取沿用既有闸门（`live !== ''`）丢弃。

**验收（判据 = 磁盘字节，前后对照）**：

| | 注入 | 磁盘 | 首行 |
|---|---|---|---|
| 修复前 | 1 × `KEYCODE_A` | **4661（逐字节不变）** | `- 测试块 2` |
| 修复后 | 5 × `KEYCODE_A` | **4661 → 4666** | **`- 测试块 2aaaaa`** |
| 修复后（回归） | 3 × `KEYCODE_A` + `Esc` | 4664 → 4664（Esc 不写坏数据） | `- 测试块 2aaa` |

---

## 4. 编译与工作区核对

| 检查 | 结果 |
|---|---|
| 交付构建 | **`BUILD SUCCESSFUL`** ✓（`exit code 1` 为 sign WARN 假报，AGENTS §2） |
| 改动文件 | **仅 `BlockEditor.ets`（+21 / −1）**，**无行尾噪声**（`CRLF=0` 已断言）✓ |
| 插桩还原 | `IntegralEditor` / `LivePreviewHelper` / `EntryAbility` / `ContentArea` **已 `git checkout HEAD --`** ✓ |
| 全仓探针残留 | `git grep "W4PROBE\|probeMarkRebuild\|W4KEY\|probeSelCalls\|probeReport"` ⇒ **0 命中** ✓ |
| `main_pages.json` / `SpikeHarness.ets` / `rawfile/spike/*` / `rawfile/libs/**` | **全程未触碰** ✓（未新建任何页面级探针） |
| 夹具 `__S1_long.md` | **已复位**：4661 B / MD5 `501bf94f19171bd19844d1724f2ecaa2` ✓ |
| 临时产物 | 全部在 `%TEMP%\callaite_w4\`，**仓库内零临时文件** ✓ |
| `git status --short`（提交前） | ` M entry/src/main/ets/components/outliner/BlockEditor.ets` |
| `git status --short`（提交后） | **空** ✓ |
| 提交 | `9a5e469`（**逐个列出文件**，未用 `git add -A/-u`）✓ |

---

## 5. 对症 vs 顺手加固（分开说明）

| 类别 | 项 | 说明 |
|---|---|---|
| **对症（已落地）** | `BlockEditor.onSelectionChange` 重建前对齐真实内容 | 直接对应 §3.5 的实测缺陷；判据 = 磁盘字节；**只改这一处** |
| **对症（未落地，仅建议）** | `IntegralEditor` 重建回声静默窗（§2.4 建议 A） | 实测能消除回声驱动的重建，但在当前构建上**端到端成本不变**（66 B 单轮只剩 2ms）⇒ 收益未证实，改为建议 |
| **未做（顺手加固的红线）** | ① 没有给 `RichEditor` 挂任何 `onKeyEvent`；② 没有改 `ShortcutService` / `OverlayKeyRouter` / `WebEditor`；③ 没有动 `FenceOpenCache` / 拖拽命中表 / 多选 / 折叠；④ 没有碰落盘链路 | W2 的四条「零破坏」复核前提全部保持原样 ✓ |

---

## 6. 为什么 ↑↓ / Enter 的接线**没有**在本窗口落地（处置理由）

1. **落点被 native 收走**：`ContentArea` 收不到这几个键（§3.2/§3.3 实测），只能挂到 `RichEditor` 上；而「挂 `onKeyEvent` 之后文本输入是否完好」这一条**本窗口没有独立验证**（第一次测量时出现的丢字已被证明是 §3.5 的旧缺陷、与探针无关，但**不能反过来推论「挂了它就没问题」** ✗）。
2. **`BlockEditor` 是本仓最敏感的部位之一**：`isRebuildingSpans` / `programmaticDepth` / `snapshotText` / `lastSpanText` 四道闸互相咬合，任何新增的键回调都可能改变「谁先看到 `onDidChange`」的时序 —— 本窗口刚在那里修掉一个**静默丢字**缺陷，不适合在同一窗口再叠一层未验证的时序改动。
3. **硬约束优先**：AGENTS §7 陷阱 7「接线必须先验证」+ 本窗口约束 9「不要破坏已验收能力」⇒ 宁可交付**已验证的修复 + 已验证的契约测量 + 可执行的接线设计**，也不交付一个没量过的新键处理路径。

---

## 7. 不可自证项（如实登记，全部**不写成通过**）✗

1. **`ContentArea.onKeyEvent` 对 ↑/↓/Enter 的「不命中」是探针结论**。探针是 `hilog` 一行日志，不改变键流；但「探针自身是否影响键流」**未做独立对照** ✗。
2. **`Ctrl+K` / `Ctrl+Z` / `Alt+↑↓` 的回归未测** ✗ —— 没有找到带修饰键的注入通道（`uitest uiInput keyEvent` 只收单个键码）。
3. **「块内换行」用例未取到设备证据** ✗（Enter 在 B 形态不产生换行，无法用注入构造；见 §3.3）。
4. **物理键盘 vs 注入键的差异无法排除** ✗：平板无宿主物理键盘（AGENTS 陷阱 21）。「Enter 是死键」是在**注入通道**下测到的；真实软键盘按「换行」键是否同样无效 —— **未验证**。
5. **B 形态下 ↑↓ 的真实观感**：本窗口只观测了「磁盘不变 + 编辑行不迁移 + 键不上浮」。**光标在块内是否移动、移动了几行**没有量（`dumpLayout` 不输出 `RichEditor` 内部状态）✗。
6. **那一次 4555ms 的成因仍未证实** ✗（§2.3）。本窗口把候选从「持续重建链」换成了「**一次按键 ⇒ 段数轮整页重建的放大**」，并给出了它在历史现场跑过的硬证据，但**没有**在设备上复现出一次 4555ms 的连续阻塞。
7. **`spanIndex error, return` 的成因未归因** ✗：native 侧 `addTextSpan` 在 31 次里失败 27 次。**不排除**是「`deleteSpans()` + 逐段 `addTextSpan` 与 native span 树的既有竞态」，但**未从源码/文档侧证实**。
8. **`RichEditor` 是否在 `onKeyEvent` 之外还有别的键通道（`onKeyPreIme` / `onKeyEventDispatch`）未探** ✗。

---

## 8. 对上级的提示

- **本窗口只交付 1 个文件**（`BlockEditor.ets`，commit `9a5e469`）。夹具/插桩/临时产物全部复位或清理，`git status --short` **为空** ✓
- **设备已交还**：应用 `force-stop`，停在基线 `__S1_long` 页面（4661 B / `501bf94f…`），无残留实验状态 ✓
- **建议下一窗口的第一优先级**：**「B 形态按键归属表」**（Enter / Tab / Backspace / ↑↓ 各自由谁消费、可否在 `RichEditor` 上安全接管）。它决定的是「回车新建块」这条核心交互，比 ↑↓ 跨块更紧急。
- **可直接复用的装置**：① 本文件的计数器探针设计（§1.1 表，四把尺子）；② 66 字节历史页夹具（内容见 §1.2，`wc -c` = 66）；③ `faultlogger` 原始报告的取用方法（`hdc file recv /data/log/faultlog/faultlogger/appfreeze-*`）—— 它比 `hilog` 事后检索**信息量大得多**（带 `utime/stime`、main handler dump、native 侧 `AceRichText` 逐行）。
