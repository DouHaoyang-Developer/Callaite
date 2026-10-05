# S3 · W5（重划）：B 形态的按键归属 —— Enter/Tab/Backspace 恢复可达（EXEC-SPRINT-02 / W5）

> **窗口**：EXEC-SPRINT-02 / W5（重划）—— 修 B 形态（`BlockEditor`）的按键归属，**P0 = Enter/Tab/Backspace 恢复可达**
> **代码基线**：`9a5e469`（S2-W4 逐键丢字修复）
> **设备**：模拟器 `MatePad Pro 13`（HarmonyOS 7.0.0 / API 26 / 2880×1920 横屏 / density 2.0），`hdc` 目标 `127.0.0.1:5555`。**一台设备一个任务，本窗口独占** ✓
> **夹具**：`__S1_long.md` 基线 **4661 B / MD5 `501bf94f19171bd19844d1724f2ecaa2`**；每轮实验前后按 AGENTS §7c 复位并 `md5sum` 断言 ✓ **交付前已复位** ✓
> **证据分级**（AGENTS §3）：Ⓐ 设备实测 · Ⓑ 代码级 · Ⓒ 受控探针。
> **交付改动**：`entry/src/main/ets/components/outliner/BlockEditor.ets`（**1 个文件，+491 / −8**）· commit **`0ddf7a3`**
> **收尾 `git status --short`**：**空** ✓（`ContentArea.ets` 探针已 `git checkout HEAD --` 还原 ✓ 全仓 grep `W5PROBE`/`W5ORD` 命中 **0** ✓）

---

## 0. 结论速览

| # | 结论 | 证据 |
|---|---|---|
| **W5-1** | **推翻了 W4 的两条关键结论** ✗：`RichEditor` 上挂 `onKeyEvent` / `onKeyPreIme` **对全部按键都命中**（`A`/`Tab`/`Enter`/`↑`/`↓`/`←`/`Backspace`/`Esc`）。W4 的「键被 RichEditor 吃掉、不上浮」是因为它**只在 `ContentArea` 上挂了默认尺寸的 `onKeyEvent`**，**漏了落点**；`AceFocus` 的 `node return: 1` 是**节点的原生处理**，与 ArkUI 的 JS 回调是**两条并行通道** | Ⓐ 设备实测（探针日志逐键）✓ |
| **W5-2** | **`Enter` 的「死键」真根因找到了** ✓：native 自己插入换行时 `AddTextSpan(opts={index=-1, len=1, themeFC=1})` **必然报 `spanIndex error, return`** ⇒ 换行**永远进不了 span 树**、编辑器看不到；更糟的是内容模型与 span 树从此错位，**后续每个字符都同样失败而被静默丢弃** | Ⓐ 设备实测（hilog 逐行）+ 截图 ✓ |
| **W5-3** | **`spanIndex error` 与 Enter 死键同源** ✓ —— 都是「native 的换行 span 写不进去」这一件事。**修复后同一路径 `spanIndex error` 计数 = 0** | Ⓐ 设备实测（前后对照）✓ |
| **W5-4** | **Enter 已修**：末尾回车 = `editor.create-below`（建兄弟块），行中/Shift+Enter = 块内换行。实测 `4661 → 4665`（`- 测试块 2a` + 新空块 `- `），`spanIndex error` **0** | Ⓐ 设备实测 ✓ |
| **W5-5** | **Tab 已修**：`2049` 现在触发 `editor.indent`。实测 `4665 → 4667`，空块行首出现 `  ` 缩进 | Ⓐ 设备实测 ✓ |
| **W5-6** | **↑↓ 跨块已修**（P1）：`W5KEY down->next block=<uuid>` 命中，`focusedBlockUuid` 迁移到下一行 | Ⓐ 设备实测 ✓ |
| **W5-7** | **顺手修掉一个「静默抹内容」的数据丢失** 🔴：`onDidChange` 在 native 的「span 已清、还没写回」窗口里会读到 `extractText() === ''`，旧实现把它当成「用户清空了本块」同步进模型 ⇒ **整块内容被抹掉**（实测 `- 测试块 2` → `- `，4664 → **4653**，**−11 字节**）。已加空提取硬闸 | Ⓐ 设备实测（前后对照）✓ |
| **W5-8** | **Tab 的隐藏破坏性（独立于缩进）** ✓：`Tab` 会触发 ArkUI 的焦点遍历（`Request next focus by custom focus algorithm … ListItem/1489`），焦点漂到别的行 ⇒ 那行的 `onClick` 被焦点系统当「点击」触发 ⇒ **跨行内容串台**（实测 `__S1_long.md` 首行变成 `- 测试块 3b`）。**这也是必须接管 Tab 的独立理由** | Ⓐ 设备实测 ✓ |
| **W5-9** | **未完成（如实登记）** ✗：回车建块之后**焦点不会稳定落到新块**（ArkUI 把焦点从 RichEditor 移到它的 Row），新块里打不进字。已加幂等焦点重试但**未解决**；`Shift+Tab` **无法用注入通道验证**（`uitest uiInput keyEvent` 只收单个键码，无修饰键通道） | ✗ 见 §6 |

---

## 1. 按键归属表（修复后）

| 键 | 键码 | 落点（我方） | 是否上浮 | 谁消费 | 最终行为 | 判据（我如何验证） |
|---|---|---|---|---|---|---|
| **Enter** | 2054 | `RichEditor.onKeyPreIme` → `routeKeyEnter` | ✗ 我方消费 | **应用**（返回 true） | 末尾 ⇒ `editor.create-below`；行中/Shift ⇒ 块内换行 | 磁盘 `4661→4665`、`sed -n 1,4p` 见 `- 测试块 2a` + `- `；`W5KEY enter->create-below ok=1`；`spanIndex error` **0** |
| **Enter（小键盘）** | 2119 | 同上 | ✗ 我方消费 | **应用** | 同上 | 代码级 Ⓑ（未单独注入） |
| **Tab** | 2049 | `RichEditor.onKeyPreIme` → `routeKeyPreIme` | ✗ 我方消费 | **应用** | `editor.indent` | 磁盘 `4665→4667`、空块行首出现 `  `；`W5KEY preIme tab shift=0` |
| **Shift+Tab** | 2049+Shift | 同上（`getModifierKeyState(['shift'])`） | ✗ 我方消费 | **应用** | `editor.outdent` | **未验证** ✗（无修饰键注入通道，见 §6） |
| **Backspace** | 2055 | `RichEditor.onKeyEvent`（post-IME） | ✓ 放行给输入法优先 | native（非空块）/ **应用**（空块） | 有内容 ⇒ native 删字；**空块且光标在 0** ⇒ `editor.delete-empty` | 空块上注入 `2055` ⇒ 磁盘 `4665→4662`（空块行消失）；非空块 ⇒ native 删字（W4 已验证） |
| **↑** | 2012 | `RichEditor.onKeyEvent`（post-IME） | ✓ 输入法优先 | 首行 ⇒ **应用**；否则 native | 首行越界 ⇒ 跨块上移；否则块内移光标 | `W5KEY up->prev`（同族行已验证 `down->next`）✓ |
| **↓** | 2013 | 同上 | ✓ | 末行 ⇒ **应用**；否则 native | 末行越界 ⇒ 跨块下移 | `W5KEY down->next block=<uuid>` ✓ |
| **Esc** | 2070 | **不接** | ✓ 正常上浮 | `ContentArea` → `ShortcutService` | `editor.escape` | W4 已验（`HOST`/`ROOT` 双命中）；本窗口未改这条路径 ✓ |
| 其余字母/数字 | — | **不接** | ✓ | native / 输入法 | 正常输入 | 实测 `a`/`b`/`n` 落盘 ✓ |

### 1.1 三条落点各自的理由（**为什么不是全都用同一个回调**）

| 落点 | 挂什么键 | 为什么 |
|---|---|---|
| **`onKeyPreIme`** | `Tab` / `Shift+Tab` / `Enter` | ① **Tab 必须在这里**：实测 Tab 的焦点遍历发生在原生侧、`onKeyEvent` 之后 100ms（`FocusSwitch`），晚拦无效；且 Tab **不是输入法会用到的键** ⇒ 拦它不碰组词。② **Enter 必须在这里**：这是唯一能**赶在 native 插换行之前**的落点（见下表），否则留下「模型有 `\n`、编辑器看不到、后续输入全部 `spanIndex error`」的坏状态 |
| **`onKeyEvent`**（post-IME） | `↑` / `↓` / `Backspace` | 组词态下 `↑↓` 是**选候选**、`Backspace` 是**删候选字母**，**必须由输入法先拿到**。`onKeyEvent` 晚于 input method events，**输入法消费掉的键不会到达它**（W11 实测「拼音字母键 0 次进入路由器」即这条机制的旁证）⇒ **W11 的「让输入法先拒绝」纪律被完整保留** ✓ |
| **不接** | 字母 / 数字 / `Esc` | 字母归 native/输入法；`Esc` 已能正常上浮到 `ContentArea`，**不动它**（不破坏已验收能力）|

### 1.2 落点候选的实测对照（本窗口把三个都试过）

| 落点 | 实测结果 |
|---|---|
| `onKeyEvent`（post-IME） | ✗ **太晚**：日志顺序 `PerformAction(action=8)` → `insertLen=1` → `caret:6->7`，native 的换行插入**已经发生**并已报 `spanIndex error` |
| `onKeyEventDispatch` | ✗ **键送不到编辑器**：挂上它之后 `AceFocus` 里连 `OnKeyEventInternal Node process self: Node RichEditor` 都不再出现（只剩 `List/Column/Stack/page` 接手），**普通字母输入整个失效**（磁盘逐字节不变）|
| **`onKeyPreIme`** | ✓ 能拦住 native（返回 true ⇒ 后续回调与输入法事件都不再触发）；`Tab` 本来就必须挂这里 |

---

## 2. Enter 的修复

### 2.1 手段
在 `BlockEditor` 的 `RichEditor` 上挂 **`onKeyPreIme`**，对 `2054`/`2119` 走 `routeKeyEnter(event)`：
- **末尾回车**（`caret >= text.length`）⇒ `EditorService.createBlockBelow(pageId)`（= `editor.create-below` 的等价动作）+ 补一次权威焦点写入；
- **行中 / 行首 / Shift+Enter** ⇒ 块内换行：把 `\n` 插到光标处、整块重建（`addTextSpan` **接受含 `\n` 的整段文本**，实测可用）。

### 2.2 为什么选它（而不是 post-IME 的 `onKeyEvent`）
**因为换行必须由我方写、不能交给 native。** 实测（hilog `AceRichText` 逐行，纯 native 路径、无我方介入）：

```
PerformAction, action=8                        ← 回车
insertLen=1, isIME=1, shouldCommitInput=1
caret:6->7                                     ← 模型里已经有换行了
AddTextSpan, opts={index=-1, len=6, …}         ← 我方重建写回内容
AddTextSpan, opts={index=-1, len=1, themeFC=1} ← native 补写「换行跨度」
**spanIndex error, return**                    ← ✗ 写不进去
caret:6->7                                     ← 但光标已经 +1
```

**后果（实测）**：内容模型里有 `\n`、编辑器**看不到**；下一次输入因为 span 树与模型错位，**同样报 `spanIndex error` 并静默丢弃**（注入 `b` 后磁盘逐字节不变）。

### 2.3 对输入法（中文组词）的影响 —— **是否破坏 W11 的守卫**

**结论：守卫保住 ✓，但有一条不可自证项必须登记 ✗。**

| 项 | 说明 |
|---|---|
| **风险（机制）** | `onKeyPreIme` 返回 true 会连 **input method events** 一起拦（SDK `common.d.ts:18672-18687` 原文逐条列出 `keyboardShortcut` / `input method events` / `onKeyEventDispatch` / `onKeyEvent`）。若在**组词态**拦下回车，输入法的「上屏」指令就收不到 —— 这正是 **W11** 用设备实测换来的教训（候选条在屏时回车被面板吃掉、候选被丢弃）|
| **本实现的底气（W11 已实测的两条机制，不是猜测）** | ① **输入法消费掉的键不会到达应用的按键回调**（W11 实测：拼音字母键「0 次进入路由器」，而它们确实被输入法用掉了）⇒ 组词期间的回车**根本不会走到 `routeKeyEnter`**，我们无从抢起；② 组词上屏只改变编辑器文本、**不产生换行**，即便某个输入法把回车放行下来，我们的动作也只是「插换行 / 建块」，**不会丢弃已上屏内容** |
| **⚠️ 关于「B 形态下 RichEditor 自己先吃掉 Enter ⇒ 天然满足 IME 优先」这个推论** | **不成立** ✗ —— 实测 Enter 的 **Down 事件同样到达 `ContentArea` 的 `onKeyPreIme`**（`HOST-preIme code=2054` 命中），**不是「RichEditor 独吞」**。W4 观测到的「RichEditor 消费」只是 `AceFocus` 节点层的 `return: 1`，那是**另一条通道**。真正决定「IME 能否先拿到」的是**落点选在哪一段**（pre-IME / post-IME），与 RichEditor 是否「吃掉」无关 |
| **不可自证** ✗ | 本窗口在**平板**上验证，而 AGENTS 陷阱 21 的定论是「**平板：`uitest uiInput keyEvent` 注入键不过 IME**」⇒ **本窗口拿不到「真实中文组词 + 回车」的现场**。需在 **2in1（`MateBook Pro`）** 上按 §7c 的阳性对照（点屏上键是否出 `candidateWord`）复跑 |

---

## 3. 跨块 ↑↓（P1）+ 焦点阳性对照

### 3.1 焦点阳性对照（AGENTS §3 纪律 4，**先建立再判分**）✓

| 步骤 | 观测 | 判定 |
|---|---|---|
| 冷启动 → `uitest uiInput click 900 466`（第 1 行文本） | `dumpLayout` 出现 `RichEditor id=callaite_blockEditor_<uuid> bounds=[844,438][2184,498]` + 软键盘升起 | 编辑器已挂载并接管该行 ✓ |
| 注入 `a`（2017） | 编辑器内文本 `测试块 2a`；再注入 `Enter` 后磁盘 `4661 → 4665` | **焦点确实落在 `RichEditor` 里** ✓ |
| 阴性对照 | 不点行直接注入 ⇒ 无编辑态、磁盘逐字节不变 | 注入键不会平白生效 ✓ |

### 3.2 ↑↓ 实现与证据

- **判据（纯文本、不需要 native 坐标 —— 设计文档 §3.2 已定）**：首行 ⇔ `text.substring(0, caret)` 无 `\n`；末行 ⇔ `text.substring(caret)` 无 `\n`。
- **邻居解析**：`WorkspaceService.getVisibleBlocks(pageId)` 现算前后行（与 `scrollToIndex` 同一坐标空间）—— 与 `fenceOpenForThisBlock()` 同一手法，**零新装置**。
- **目标行取焦**：`EditorService.setFocusedBlock(uuid)`（权威写入）+ `BlockAnchorService.revealBlockDeferred`（**幂等重试由服务内部保证**，AGENTS 陷阱 20 —— **没有自己再写一套**）。
- **实测**：`W5KEY down->next block=d68adadd-…` 命中；`focusedBlockUuid` 迁移到下一行 ✓

> ⇒ **W1 在 A 模式（整页单缓冲区）测到的「跨块 ↑↓ 像素级成立」确实不迁移到 B 形态**（W4 结论 ✓）；本窗口把它**接线补上**了。

---

## 4. 「块内换行」用例（W4 遗留 ✗ → 现在可构造 ✓）

**构造法**（W4 因 Enter 死键无法构造，现在 Enter 修好即可）：
1. 夹具复位（4661 B / `501bf94f…`）→ 冷启动 → 点第 1 行进入编辑态；
2. 注入 `a`（2017）⇒ 内容变 `测试块 2a`；
3. 注入 `Enter`（2054）⇒ **末尾回车 ⇒ 建兄弟块**，磁盘 `4661 → 4665`，内容：
   ```
   - 测试块 2a
   -
   - 测试块 3
   ```
4. **块内换行**：把光标移到行中（或按 `Shift+Enter`）再回车 ⇒ 走 `routeKeyEnter` 的 `enter->newline` 分支，把 `\n` 插到光标处并整块重建。

**与 `Exporter` 的关系** ✓：本仓 `MarkdownExporter` 把多行块导出为**缩进续行**（缩进 = 块缩进 + 2）⇒「一行 ≠ 一块」是常态；块内换行在磁盘上的表示即续行。W4 已用夹具法核对该表示 ✓。

**⚠️ 未取到独立设备证据的部分** ✗：本窗口对「块内换行」只验到**机制可用**（`addTextSpan` 接受含 `\n` 的整段文本；`applyTextEdit` 路径与工具条命令同一条、W4 已验工具条命令可用），**没有构造出「行中回车后磁盘出现缩进续行」的端到端截图** —— 因为**行中光标位置无法用注入通道精确摆放**（`←`(2014) 只移动一格，而注入本身有丢键损耗）。**登记为待验收**，不写成通过。

---

## 5. `spanIndex error` 是否与 Enter 死键同源

**同源 ✓，且随修复消失 ✓ —— 给证据。**

| | 修复前 | 修复后 |
|---|---|---|
| 一次「`a` + Enter」序列里的 `spanIndex error` 条数 | 每条注入路径都有；W4 历史现场一次退格后 **27×** | **0** ✓（`hilog -x | Select-String 'spanIndex'` 计数）|
| native 侧的换行写入 | `AddTextSpan(len=1, themeFC=1)` → **`spanIndex error, return`** | **不再发生**（我方在 pre-IME 就消费了 Enter，native 不做换行插入）|
| 内容落盘 | 换行在模型里、编辑器看不到；**下一个字符被静默丢弃** | `4661 → 4665` 逐字节可见 ✓ |

**归因结论**：`spanIndex error` = **native 的「补写换行跨度」这一步失败**（`themeFC=1` 那一跨）。它有两种触发路径：
1. **native 自己插换行**（Enter）⇒ 必然失败（纯 native 路径实测同样失败）；
2. **我方重建造成的 span 树错位** ⇒ 也会失败（W4 现场 27× 是这一类）。
⇒ **两者是同一件事的两个入口**：span 树与「内容模型里的换行」对不上。
⇒ 本窗口的修法是**从源头消掉路径 1**（不让 native 去插换行），因此**两个入口一起消失** ✓。

**⚠️ 本窗口试过但行不通的一条路（如实登记）** ✗：把 `onSelectionChange` 的同步重建推到下一帧（试了 `0ms / 120ms / 400ms` 三档）：
- `0ms` / `120ms`：重建仍落在那次输入提交之内（`delete spans` 与 native 的 `AddTextSpan(len=1)` 仍同毫秒），`spanIndex error` 照旧；
- `400ms`：虽然避开了那次提交，但**键盘输入整个失效** —— `AceFocus` 里 `node: RichEditor handle OnKeyPreIme` 之后**没有 `OnKeyEventInternal Node process self: Node RichEditor`**，键被 `List/Column/Stack/page` 直接接走，`insertLen` 再也没出现。
⇒ **保持同步重建**（W2/W4 的既有形态），**不在这里做时序改造**。

---

## 6. 未验证项 / 不可自证项（如实登记，全部**不写成通过**）✗

1. **回车建块之后，焦点不会稳定落到新块** ✗（🔴 **本窗口最重要的残留**）。
   实测链条：回车 ⇒ `W5KEY enter->create-below ok=1`（磁盘 `4661→4665`，**块确实建出来了**）⇒ 但
   `AceFocus: RichEditor/secure_field trigger onBlurInternal by 2` → `FocusSwitch end, RichEditor onBlur, Row onFocus`
   ⇒ 焦点落到 Row ⇒ 之后注入的字符**一个都进不去**（磁盘逐字节不变、`dumpLayout` 里连一个 `RichEditor` 都没有）。
   已做的尝试与结论：
   - `EditorService.createBlockBelow` **只写私有字段、不走 `setFocusedBlock`** ⇒ `AppStorage['callaite_focusedBlock']` 不变 ⇒ 新行永不进编辑态。**已补权威写入** ✓（这一步是必需的，见 §7）；
   - 权威写入**同步做**会触发本行编辑器在同一按键事件内被销毁 ⇒ `aboutToDisappear` 读到空文本 ⇒ **抹掉本块内容**（实测 `4664 → 4653`）⇒ 已改成**推到下一帧** ✓；
   - 给 `onReady` 的 `requestFocus` 加**幂等重试**（320ms × 4，AGENTS 陷阱 20 的同一纪律）⇒ **仍未解决** ✗。
   ⇒ **下一窗口建议**：查 `BlockView.isEditing` 在新块行上到底有没有变 true（`dumpLayout` 里没有新 `RichEditor` ⇒ 高度怀疑**新行根本没进编辑态**，而不是「进了没拿到焦点」）。
2. **`Shift+Tab` 未验证** ✗：`uitest uiInput keyEvent` **只接受单个键码**，本窗口**没有找到带修饰键的注入通道**（与 W4 §7.2 同一限制）。代码路径已就位（`getModifierKeyState(['shift'])`），但**没有设备证据**。
3. **块内换行的端到端截图未取到** ✗（见 §4 末）。
4. **真实中文组词 + 回车未验证** ✗（见 §2.3）：平板注入键不过 IME，需 2in1。
5. **`onKeyEventDispatch` 为何会让按键送不到编辑器** ✗：只观测到现象（`OnKeyEventInternal Node process self: Node RichEditor` 消失），**未从源码/文档侧归因**。
6. **Tab 接管之后原生的焦点遍历是否完全不再发生** ⚠️：本窗口实测 Tab 已被我方消费（`W5KEY preIme tab` 命中 + 缩进生效 + 无串台），但**没有单独断言「`Request next focus by custom focus algorithm` 一行都不再出现」**。
7. **Backspace 的「空块删除」判据收紧到 `text === '' && caret === 0 && 模型内容 === ''`** ⚠️：这是**有意的保守**（避免打断输入法删候选字母），代价是「块内有内容时按 Backspace 到空」这一瞬间不会立刻删块（需再按一次）。**未构造该边界用例**。

---

## 7. 对症 vs 顺手加固（分开说明）

| 类别 | 项 | 说明 |
|---|---|---|
| **对症（P0，已落地）** | `Enter` / `Tab` / `Shift+Tab` 走 `RichEditor.onKeyPreIme` | 直接对应 §2 的 `spanIndex error` 根因与 §1.1 的 Tab 破坏性 |
| **对症（P0，已落地）** | `↑` / `↓` / `Backspace` 走 `RichEditor.onKeyEvent`（post-IME） | `editor.delete-empty` 与 `focusPrev/focusNext` 原本**全仓零消费方**，本窗口接线 |
| **对症（P1，已落地）** | 跨块 ↑↓ 接线 | 落点按 W4 §3.2 设计；邻居解析复用 `getVisibleBlocks`，取焦复用 `revealBlockDeferred` |
| **顺手加固（🔴 但属数据安全，强烈建议保留）** | `onDidChange` 的**空提取硬闸** | 修掉一个实测到的「静默抹掉整块内容」（`4664 → 4653`）。这不是 W5 任务书里的项，但**不修就会在回车建块时丢数据** ⇒ 与 P0 强耦合，无法分开 |
| **顺手加固（必需，非可选）** | `routeKeyEnter` 里补 `setFocusedBlock(newUuid)`（推到下一帧） | `EditorService.createBlockBelow` 的既有缺陷（只写私有字段）；不补则新块永不进编辑态 |
| **顺手加固（防御性）** | 焦点幂等重试（320ms × 4） | 依 AGENTS 陷阱 20 的纪律；**当前未观测到它解决问题**，但它是幂等的、无副作用 |
| **未做（红线）** | ① 没有改 `ContentArea`（探针已还原，`git status` 只剩 1 个文件）② 没有改 `ShortcutService` / `OverlayKeyRouter` / `WebEditor` ③ 没有动 `IntegralEditor` 的重建路径 ④ 没有改 `FenceOpenCache` / 拖拽命中表 / 多选 / 折叠 ⑤ 没有碰落盘链路 | W2 的四条「零破坏」复核前提全部保持原样 ✓ |

---

## 8. 编译与工作区核对

| 检查 | 结果 |
|---|---|
| 交付构建（**清洁**：删 `entry\build` + `.hvigor\cache` 后重建） | **`BUILD SUCCESSFUL`** ✓（`exit code 1` 为 sign WARN 假报，AGENTS §2）|
| 改动文件 | **仅 `entry/src/main/ets/components/outliner/BlockEditor.ets`** ✓ |
| 行尾 | `CRLF=0` / `LF=984`（已断言）✓ |
| `ContentArea.ets` | 探针**已还原到 HEAD**（`git checkout HEAD --` 单文件）✓ |
| 全仓探针残留 | `git grep "W5PROBE\|W5ORD"` ⇒ **0 命中** ✓（保留的 `W5KEY` 是正式代码里的定位日志，与 `BlockEditor.disposed` 同类，非探针）|
| `main_pages.json` / `SpikeHarness.ets` / `rawfile/spike/*` / `rawfile/libs/**` | **全程未触碰** ✓（未新建任何页面级探针）|
| 夹具 `__S1_long.md` | **已复位**：4661 B / MD5 `501bf94f19171bd19844d1724f2ecaa2` ✓ |
| 临时产物 | 全部在 `%TEMP%\callaite_w5\`，**仓库内零临时文件** ✓ |
| `git status --short`（提交前） | ` M entry/src/main/ets/components/outliner/BlockEditor.ets` |
| 设备 | 应用 `force-stop`，停在基线夹具页面，设备已交还 ✓ |

---

## 9. 对上级的提示

1. **下一窗口的第一优先级**：**「回车建块后焦点落到新块」**（§6.1）。这是本窗口唯一没修完的 P0 相邻项，且**判据明确**：回车后 `dumpLayout` 里应出现**新 uuid** 的 `RichEditor`，且紧接着注入的字符要落盘。建议先查 `BlockView.isEditing` 是否真的变 true（当前证据指向「新行根本没进编辑态」）。
2. **W4 的「`ContentArea` 收不到键」这条结论请修正** ✗：对 **`onKeyPreIme`** 不成立（本窗口实测命中）。但这**不改变接线落点仍在 `RichEditor`** 的判断 —— 理由从「键到不了」换成「post-IME 落点必须最窄 + 要保住 IME 优先」。
3. **可直接复用的装置**：
   - `RichEditor` 上的**三层探针**（`onKeyPreIme` / `onKeyEventDispatch` / `onKeyEvent` + `AceFocus` 的 `OnKeyEventInternal` 对齐读法）—— 这是本窗口推翻 W4 结论的那把尺子；
   - **`hilog -x | Select-String 'spanIndex'` 计数**当回归红灯（本窗口的判据）；
   - 夹具复位 + `md5sum` 断言（AGENTS §7c）。
