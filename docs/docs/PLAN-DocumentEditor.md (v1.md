# Callaite 4.3 编辑器重铸执行方案（DocumentEditor + TabState v2）

- **状态**：草案 v1.3（**含勘误横幅**；**设计正文仍为 v1.2 原样，零改动**）

> ## ⚠️ 勘误（v1.2 → v1.3，2026-09-30）
>
> **本横幅只做勘误，不改正文一行。** 下列两条**根因判断已被实测推翻** ✗，**不得再被引用为事实**；正文其余部分**保持可执行** —— **回切触发器命中时，本计划立即升为执行版**，其设计内容即为执行依据。
>
> ### ① 被推翻的两条根因（**引用原文**）
>
> | # | 本计划 v1.2 的原判断（原文） | 位置 |
> |---|---|---|
> | 1 | 「`BlockView.ets` L124：块获焦 → 创建独立 Web 实例 → …」，`WebEditor.ets` 「`.height(32)` 固定高度，长块换行内容直接裁切」 | §1.1 |
> | 2 | 「Obsidian Live Preview 的本质是**逐行动态翻转**：… 块级作用域里永远只有一个「活」块，前提不成立。**这是模型问题，不是调参问题。**」 | §1.2 |
>
> 被推翻后的**实测根因**（W1）：
> - **①** 「整页清空 = 模式切换重建编辑器、控制器内容为空 ⇒ 用 markdown 回填」的归因**不成立**（回填早已在 `rebuildSpans()` 里），真根因是 `LivePreviewHelper.buildSpansInternal()` **吞掉 `'\n'` 段**；
> - **②** 「live preview 的加粗/行内代码/高亮缺口 = 原生能力不足」**不成立**，真根因是 `MarkdownSegmenter` 的 `specials` 表缺 `=`、行内代码被整段标为 `syntax`，以及 `LivePreviewHelper` 缺行内上下文。
> ⇒ **支撑「必须 WebView 化」的两条论据不成立** ⇒ **本计划不能再被当作「原生做不到」的证据**（以上表述逐字取自 `EXEC-PLAN.md` §15.4 与 `D-GATE-1-判定表.md`「5. 对 `PLAN-DocumentEditor v1.2` 的处置建议」第 1 条，非概括）。
>
> ### ② 推翻它的是什么证据
>
> | 窗口 | 判据 | 结论 | 证据等级 |
> |---|---|---|---|
> | **W1** | D-Gate 1 **判据①** 整页清空可修 | ✅ 可修（修复前 100% 复现整页块被清空并落盘） | **Ⓐ 真实设备操作 + 磁盘 md5 逐字节比对** |
> | **W1** | D-Gate 1 **判据③** 三类 span 编辑态↔渲染态动态翻转 | ✅ 可实现（高亮已用 `RichEditorTextStyle.textBackgroundStyle`（@since 18）做出**真底色**） | **Ⓐ 真实设备操作 + 截图目视** |
> | W2 | 判据④⑤ + **路线定案** | 原生优先 —— **无一项判负、④ 未终验** ⇒ **不触发**「任一失败 → 维持 WebView」 | ④ 初判 Ⓐ（软键盘逐键 + 候选条/编辑器截图）· ⑤ 原生 Ⓐ（像素级光标测量）· ⑤ 块级 Ⓑ（源码死分支） |
> | W8 / W9 | 判据④（B 形态、2in1：组词中硬件回车） | W8 **判负** ✗（W5 的 Enter 接管破坏「IME 优先」）→ W9 **修复并 A/B 转正** ✓ | Ⓐ（A/B 对照 + 磁盘字节） |
> ⇒ **超过「两条」的判定均来自上表** —— 勘误对象是**根因论据**，**不是**判据④ 那条过程（W8 判负 → W9 修复）。
>
> ### ③ 本计划现在的定位
>
> **降级为渐进备选，不要重写**（`EXEC-PLAN.md` §15.4 标题原文）。
> **原生路线已定案** ✓ —— `EXEC-PLAN.md` §15 标题原文「**D-Gate 1 定案：原生优先**」；其后进入 **B 形态（块级按需实例化）** 落地：`BlockEditor.ets`（原生 `RichEditor`）接入 `BlockView`，`WebEditor` 保留为**一行回退开关**（`EDITOR_IMPL`）（`EXEC-PLAN.md` §19.1）。
> **三条回切触发器** ✓（`EXEC-PLAN.md` §15.4 原文，**非重拟**）：
> 1. ④ **终验判负**；
> 2. **增量 span 整改后仍复现 ANR 或触碰预算红线**；
> 3. **真机 IME 组词丢字**。
> ⇒ 该处置**逐条承接** `D-GATE-1-判定表.md`「路线定案 §5」：**状态 = 渐进备选（保持可执行）** ✓ · **不回切、不归档** ✓ · **不重写**（重写成本约等于 WebView 路线本身）✗。
>
> ### ④ 它依然有效、不可删除的原因
>
> - **回切触发器命中时要用它** ✗ —— 故必须**保持可执行** ✓；
> - 其**设计内容仍有价值** ✓（MessagePort 通道 · overlay · IME 防护 · goalColumn 算法 · 渐进 Phase 1–3 拆分）—— 只是**不能再当「原生做不到」的证据**（`EXEC-PLAN.md` §15.4 原文）；
> - **当前三条触发器均未触发** ✓（`EXEC-PLAN.md` §19.4：① **初验已转正** ✓（W9）⇒ 真机终验留 R0 ✓ **未触发**；② **A-2 已消除一整类无界停顿** ✓、预算红线 ①✓②✓ **③未测** ✗ ⇒ 需复核 ✓ **未触发**；③ 待 R0 真机验 ✓ **未触发**）⇒ **原生路线继续** ✓。
> - ⚠️ 但 ④ 的**真机终验仍在 R0**（`docs/待验收清单.md` **S3-1**）⇒ **一旦终验判负，本横幅即刻失效、本计划升为执行版** ✗。

> **勘误署名**：EXEC-SPRINT-02 / W10（纯文档窗口）· 依据 `EXEC-PLAN.md` §15.4 / §19.4 / §19.5 与 `D-GATE-1-判定表.md` 路线定案 §5 · **本窗口对仓库业务代码零改动** ✓

- **日期**：2026-09-26（v1.1 / v1.2 同日修订）· **2026-09-30（v1.3：仅加勘误横幅）**
- **范围**：4.3.0 → 4.5.0 主轴
- **作者**：Callaite Agent × 窦浩扬
- **关系**：接替 README 中「4.x 主轴为 WebEditor 编辑器 + 白板」的编辑器部分——主轴从**块级 WebEditor** 升级为**文档级 DocumentEditor**
- **实证基础**：Obsidian Desktop 1.10.6 反混淆逆向报告（`docs/reverse/` 两份，下称 R1 解析器拆解 / R2 架构分析）——核心架构选型已对照实证结论校验，差异点见 §0.1
- **外部核验**：v1.2 采纳 DeepSeek 三份核验报告的事实修正（保存链真实模型 / TabState 持久化安全 / undo 静默失败），见各节「v1.2」标注

### v1.1 变更记录（基于逆向报告的修订）

| # | 修订 | 来源 |
|---|---|---|
| 1 | ~~保存链补「焦点绑定 flush」：blur/切页/隐藏立即落盘~~（被 v1.2 #10 取代——保存链模型当时有误，flush 语义保留但载体改为卸载序确认） | R1 §3.3 |
| 2 | 键盘契约补代码块/表格的编辑态定义（整块 source，v1 不做 Widget） | R1 §3.2-2 |
| 3 | focusRelative 光标算法升格为 goalColumn 精确算法 | R1 §3.2-3 |
| 4 | IME 防护补 overlay Enter 的 isComposing 检查 | R1 §3.4 |
| 5 | 新增附录 C：Obsidian 语法对齐测试矩阵（20 例） | R1 §1.2/1.3 |
| 6 | TabState v2 schema 对齐 workspace.json 布局树 | R2 §5 |
| 7 | 桥协议预留「编辑器上下文注入」位（未来插件生态） | R2 §6 / R1 Facet 接入面 |
| 8 | 安全节补 nodeIntegration 反面论据 | R2 |
| 9 | 变更通知细化方向：changed/finished 双事件模式（列后续项） | R1 §4.1 |

### v1.2 变更记录（基于外部核验的修正）

| # | 修订 | 来源 |
|---|---|---|
| 10 | **I3 保存链按真实代码重写**：update-block 走 persistForOp 主线程同步整页落盘（fsync），SaveQueue 不在此路径——v1.1 的「SaveQueue 400ms 防抖」模型双向错误；新增连续输入性能预算与 Phase 2 spike | DeepSeek 核验三 P1-2 |
| 11 | **§6.3 TabState 持久化重写**：schema 版本移独立键（顶层 v:2 会致旧版解析重置用户标签——P0 数据安全）；escape() 边界注记；四重建落点清单 | DeepSeek 核验三 P0-4 |
| 12 | **§4.10 撤销重写**：update-block 不入 OutlinerEngine undo 栈（:329）→「打字→切块→Ctrl+Z」静默失败为 known bug，本方案以跨块文本栈修复 | DeepSeek 核验二 存疑#8 |
| 13 | 附录 C 加块模型方言总则（Obsidian 行为为兼容参考，非判定标准） | DeepSeek 核验一 N8 |

### v1.3 变更记录（**仅勘误，正文零改动**）

| # | 修订 | 来源 |
|---|---|---|
| 14 | **文件头新增勘误横幅**：逐条列出被推翻的两条根因（§1.1 / §1.2）、推翻证据与证据等级、现定位（降级为渐进备选 / 不重写 / 三条回切触发器）、以及不可删除的理由 | `EXEC-PLAN.md` §15.4 / §19.4 / §19.5 · `D-GATE-1-判定表.md` 路线定案 §5 · W1/W2/W8/W9 窗口记录 |

---

## 0. 决策记录（ADR）

| 编号 | 决策 | 理由摘要 |
|---|---|---|
| ADR-001 | **采纳**：文档级 WebView 编辑器（DocumentEditor），每窗格一个 ArkWeb 实例 | Live Preview 的「光标行显源码、其余行渲染」是文档级行为模型；块级作用域内该前提不成立。**R1 §3.2 实证**：Obsidian Live Preview = CM6 装饰翻转（replace 装饰隐藏标记 + 光标行恢复），单一文档状态、无双渲染器同步——与本方案「块级 source/render 翻转」同构，核心风险实证排除 |
| ADR-002 | **否决**：自研鸿蒙版 Electron 框架 | 解析器属数据层，WebView 化无增益且拖累原生消费方；标签页是壳层问题，与 Web 运行时无关；沉浸光感依赖 ArkUI 原生材质（GlassSurface/SystemBarHelper/MaterialTokens），Electron 化即全部作废 |
| ADR-003 | **否决**：保留块级 WebEditor 继续修补 | 焦点迁移 = WebView 销毁→写文件→loadUrl→onPageEnd→focus 的生命周期 churn，迟滞无法调优；每块 `.height(32)` 裁切长块是结构性缺陷 |
| ADR-004 | **搁置**：Navigation/Titlebar 全壳迁移 | 投入产出为负：拆掉 4.2.x 刚稳定的三形态壳（87 文件）换取 ~10% 材质提升。**重启判据**（满足其一，且仅在分支上做 spike）：① GlassSurface 调参后侧对侧对比仍有肉眼可见差距；② 系统放开 systemMaterial 容器约束 |
| ADR-005 | **预留**：桥协议消息带「编辑器上下文」扩展位（对应 Obsidian Facet 接入面） | R2 实证 Obsidian 插件生态契约 = 217 个 API 导出面 + `editorEditorField`/`editorLivePreviewField` Facet。Callaite 已有 PluginManager 骨架；协议预留一个可选 `ctx` 字段的成本 ≈ 0，避免未来插件系统立项时协议 breaking change。**本 ADR 只预留字段，不做插件功能** |

### 0.1 逆向实证对照摘要（详细论证见各节「R1/R2 引用」标注）

| 方案核心选型 | Obsidian 实证 | 结论 |
|---|---|---|
| 装饰翻转（非双渲染器） | CM6 装饰插件套件，单一文档状态 | ✅ 同构（粒度差异：行级 vs 块级，后者符合大纲模型） |
| 编辑器输入路径零解析 | 键入 → 事务 → 保存 → 异步 Worker 解析 → 事件流 | ✅ 同构（edit.block + SaveQueue + 原生消费） |
| 单实例多模式 | Compartment 热重配置共用 CM6 实例 | ✅ 对应 mode.set 显示开关 |
| IME 组合期冻结 | 建议 Enter 检查 isComposing | ✅ 已补 4.6（Phase 2 机制 / Phase 3 overlay 应用） |
| 输入路径安全 | R2：nodeIntegration 无沙箱（反面教材） | ✅ 反向印证桥最小面设计（4.9） |

---

## 1. 现状诊断（为什么重铸）

### 1.1 块级 WebView 的结构性死锁

- `BlockView.ets` L124：块获焦 → 创建独立 Web 实例 → 加载 cacheDir 里的 per-block HTML → 失焦销毁。焦点链 = 销毁 → 写文件 → loadUrl → onPageEnd → focus，光标跳跃迟滞感即来源于此
- `WebEditor.ets`：`.height(32)` 固定高度，长块换行内容直接裁切；Tab 缩进路径传 `editor.innerText`（已格式化的 `<strong>**bold**</strong>`），序列化时标记丢失，靠 blur 时 `editorToMarkdown` 兜底但存在竞态；XSS 转义靠字符串拼接
- 每块一个 WebView 实例 = 焦点路径上的内存与启动税

### 1.2 Live Preview 无法成立的根因

Obsidian Live Preview 的本质是**逐行动态翻转**：光标所在块显示源码，其余块实时渲染。这要求「其余块」在同一个文档视图中持续存在。块级作用域里永远只有一个「活」块，前提不成立。这是模型问题，不是调参问题。

### 1.3 标签页缺状态快照

`TabState.ets`（231 行）的路由与持久化设计是对的，但 `TabInfo = {id, page, pinned}`——切换标签 = `ContentArea` 整体重建，滚动位置、焦点块、光标、显示模式全部丢失。标签是路由不是视图，这是「不成熟」的病根。

### 1.4 三套编辑器栈并存

- `WebEditor.ets`（块级 Web，主路径）
- `IntegralEditor.ets`（RichEditor 整页，四模式）
- `RichBlockEditor.ets`（待审计，疑似遗留）
- 配套 `LivePreviewHelper.ets` / `MarkdownSegmenter.ets` 服务于 IntegralEditor 路线

隐性维护税：两套键盘语义、两套序列化兜底逻辑、两套「重建为空」补丁。

### 1.5 重大利好：EditorService 已经是正确的形状

`EditorService.ets`（558 行）已提供完整 outliner 操作层：`createBlockBelow` / `createChildBlock` / `indentBlock` / `outdentBlock` / `deleteEmptyBlock` / `moveBlockUp/Down` / `cycleMarker` / `cyclePriority` / `setScheduled/setDeadline` / `toggleCollapse` / `collapseAll/expandAll` / 多选批量操作 / `undo/redo`（走 OutlinerEngine 事务）。

**结论：JS 侧保持薄壳，一切结构操作沿用原生 op 层。重铸的是「视图作用域」，不是「操作层」。**

---

## 2. 目标架构

### 2.1 组件拓扑

```
MainContainer（壳，零改动）
├── Ribbon / LeftSidebar / RightSidebar / TabBar / StatusBar / Mobile*
└── ContentArea（改动：仅 onKeyPreIme 保留，PageView 分支）
    └── PageView（改动：特性开关分支）
        ├── flag = 'legacy'   → BlockList → BlockView ×N → WebEditor（现状，回滚路径）
        └── flag = 'document' → DocumentEditor（新）
            └── Web (src = $rawfile('editor/editor.html'))   ← 每窗格 1 实例，分屏共 2
                └── EditorHost（服务，持 WebviewController + 协议）
                    ↕  EditorProtocol（JSON 消息，双通道）
                    └── editor.js：DOM 大纲 + Live Preview 翻转 + 键盘契约

EditorService / OutlinerEngine / WorkspaceService / SaveQueue / MarkdownParser  ← 全部不动
```

### 2.2 数据流与单一真相（不变式）

| # | 不变式 |
|---|---|
| I1 | Markdown 语法树唯一真相在 ArkTS（DataStore + MarkdownParser）。JS 是投影与编辑面板，不持有真相 |
| I2 | 一切结构操作走 OutlinerEngine 事务（经 EditorService）。JS 不私自改树，只发 `op.request` |
| I3 | 保存链唯一（v1.2 依真实代码修正）：`edit.block` → `EditorService.updateBlockContent` → `executeOp('update-block')` → **`persistForOp` 主线程同步整页落盘（含 fsync）**——SaveQueue（1.2s 节流）服务 autosave 场景，**不在 edit.block 路径上**。焦点绑定 flush（R1 §3.3）：WebView blur / 标签切换 / onBackground 时立即确认该页落盘完成 |
| I4 | 壳层零改动：Ribbon / 双侧栏 / TabBar / MaterialTokens / GlassSurface 不因本方案变更。沉浸光感独立演进 |
| I5 | 特性开关可回滚：`AppStorage['callaite_editorEngine'] = 'legacy' | 'document'`，运行期读取，默认 legacy 直到 4.4.0 翻转 |

### 2.3 与 Electron 决策的关系

本方案**不是** Electron 的变体。UI 壳、侧栏、标签页、材质全部保持 ArkUI 原生；Web 只出现在「页面内容区」这一个矩形里，且从「一块一个」收敛为「一页一个」。这是把 WebEditor 的既有投入（键盘契约、IME 验证、contenteditable 模型）按正确粒度重铸。

---

## 3. 桥协议 v1（EditorProtocol）

### 3.1 通道选型（Phase 1 首个 spike）

| 方案 | 优点 | 风险 |
|---|---|---|
| **首选**：ArkWeb MessagePort（`createWebMessagePort` 系） | 全双工、结构化消息、无需字符串拼接 | API 形态需 spike 验证（半天） |
| **回退**：`javaScriptProxy`（JS→ArkTS）+ `runJavaScript`（ArkTS→JS） | 当前 WebEditor 已验证可用，零风险 | 异步回调式，代码略丑 |

**决策规则**：spike 当天若 MessagePort 双向往返延迟 < 5ms 且 JSON 无损坏 → 采用；否则回退。协议层与通道解耦（EditorProtocol 消息结构对两种通道透明），通道选型不影响本节其余内容。

### 3.2 N→E 消息表（ArkTS → JS）

| 消息 | payload | 语义 |
|---|---|---|
| `hello` | `{proto, theme, fontFamily}` | 握手应答，携带初始主题令牌 |
| `doc.load` | `{pageId, pageTitle, blocks: BlockDTO[], viewMode, scrollHint, focusHint}` | 全量加载（页面切换、标签激活） |
| `doc.patch` | `{ops: PatchOp[], rev}` | 树变更增量（OutlinerEngine 事务结果投影） |
| `doc.unload` | `{}` | 清空（页面切换前） |
| `mode.set` | `{mode: 'live'\|'source'\|'preview'\|'split'}` | 显示模式（收编 IntegralEditor） |
| `cmd.format` | `{kind: 'bold'\|'italic'\|'code'\|'highlight'\|'strike'\|'link'\|'wikilink', value?}` | 工具条/快捷键格式化 |
| `cmd.insertText` | `{text}` | 斜杠菜单模板/日期等插入 |
| `cmd.caret` | `{uuid, offset \| 'start' \| 'end'}` | 焦点路由（命令面板跳块、搜索定位） |
| `cmd.scroll` | `{offset}` | 快照恢复滚动 |
| `search.exec` | `{query, caseSensitive}` | 执行页内搜索 |
| `search.nav` | `{dir: 'next'\|'prev'}` | 下/上一个匹配 |
| `search.clear` | `{}` | 清除高亮 |
| `theme.set` | `{tokens}` | 主题切换（MaterialTokens 摘要） |

**BlockDTO**：`{uuid, content, level, marker, collapsed, scheduled, deadline, priority}`——扁平可见序 + level，树重组留给原生。

**PatchOp**：`{type: 'insert'\|'delete'\|'move'\|'update'\|'marker'\|'collapse'\|'props', ...}`，由 EditorHost 从 `executeOp` 返回的 `affectedUuids` 与 op 参数生成，JS 按 uuid 定位做局部 DOM 重建（不整页重载）。

### 3.3 E→N 消息表（JS → ArkTS）

| 消息 | payload | 语义 |
|---|---|---|
| `ready` | `{}` | Web 侧初始化完成（触发 hello） |
| `loaded` | `{rev}` | 文档装载完成回执 |
| `edit.block` | `{uuid, content, rev}` | 块文本变更（JS 侧 150ms 合并，原生 SaveQueue 400ms 兜底） |
| `op.request` | `{op, uuid, arg?}` | 键盘/手势结构操作（见 4.4 映射表） |
| `caret.change` | `{uuid, offset, rect: {x, y, w, h}}` | 光标变化（CSS px，原生换算 vp），驱动 overlay 锚定与 EditorService.setFocusedBlock |
| `blur.change` | `{uuid \| null}` | 文档主焦点变化 |
| `slash.trigger` | `{uuid, query}` | 斜杠菜单触发 |
| `ac.trigger` | `{kind: 'page'\|'tag', query, rect}` | `[[` / `#` 自动补全触发 |
| `link.open` | `{kind: 'wiki'\|'url'\|'tag', target}` | 链接点击（wiki 走页面路由，url 走系统浏览器） |
| `search.state` | `{matchIndex, matchCount, query}` | 搜索状态回报 |
| `scroll.change` | `{offset}` | 滚动位置（TabState 快照数据源） |
| `drag.block` | `{uuid, over, position: 'above'\|'below'\|'child'}` | 拖拽提交（映射 EditorService.moveBlockToTarget） |
| `error.report` | `{code, message}` | JS 异常上报（hilog） |

**扩展位（ADR-005）**：N→E 全部消息携带可选 `ctx?: Record` 字段，v1 恒为空。设计意图：对应 Obsidian Facet 接入面（`editorEditorField` / `editorLivePreviewField`）——未来插件系统立项时，插件对编辑器的增强（自定义块渲染、快捷键拦截、状态栏注入）经此字段下发，协议无需 breaking change。v1 仅保证：编解码器对该字段「存在即透传、缺失即忽略」。

### 3.4 关键时序

```
启动：  EntryAbility.onWindowStageCreate
          └─ webview.WebviewController.initializeWebEngine()   ← 渲染进程预热（冷启动预算的关键）
        DocumentEditor aboutToAppear
          └─ EditorHost.attach(controller, paneId)
              ├─ Web 加载 $rawfile('editor/editor.html')
              ├─ JS 侧 ready → EditorHost 发 hello
              └─ hello 后立即 doc.load（当前页面块树）

编辑：  JS keydown/input
          ├─ 文本 → 150ms 合并 → edit.block → updateBlockContent → executeOp('update-block')
          │                                            └─ persistForOp：主线程同步整页落盘（fsync）
          │                                               ⚠ v1.2 风险点：500 块页 × 连续输入 = 每次合并触发全页写
          │                                               Phase 2 spike：实测卡顿 >100ms → 改「update-block 增量
          │                                               写」走 SaveQueue 聚合（动 OutlinerOps 持久化钩子，~1 天）
          └─ 结构 → op.request → EditorService.* → executeOp 事务
                       └─ affectedUuids → doc.patch → JS 局部重建 → cmd.caret 归位

落盘：  blur / 切标签 / onBackground
          └─ 确认 persistForOp 完成（JS 收到 ack.doc.saved 才允许 doc.unload）
             （R1 §3.3 精神：保存绑焦点不绑定时器——原生侧本已同步落盘，补的是**卸载序**保证）

换页：  AppState.setCurrentPage('X')
          └─ MainContainer @Watch(currentPage) → TabState 先快照旧 tab（scroll.change 缓存 + focus）
              → EditorHost.loadDocument('X') → doc.unload + doc.load → 恢复新 tab 快照
```

### 3.5 rev 与冲突规则

- 每条 `doc.patch` 递增 `rev`；`edit.block` 携带基于的 rev
- v1 **单写者假设**（本机单窗格编辑为绝对主流）；检测到 stale（编辑期间树被外部改动，如多选操作、粘贴、同步）→ 以原生为准，EditorHost 对该块下发 `doc.patch` 强制重投影
- 冲突兜底是块级 reload，不做 merge。文档化此限制，若未来出现双写场景（协同）再升级

### 3.6 看门狗

`doc.load` 发出后 3s 未收到 `loaded` → hilog 上报 + 该窗格降级 legacy 渲染 + 设置页提示。**Web 侧任何 error.report 都不静默**，全量进 hilog。

---

## 4. JS 端设计（rawfile，零构建）

### 4.1 文件与约束

```
entry/src/main/resources/rawfile/editor/
├── editor.html    ← 骨架 + meta viewport
├── editor.css     ← 全部样式（CSS variables 接主题）
└── editor.js     ← 单文件，IIFE 模块模式，JSDoc 标类型
```

- **零 npm、零打包器**，延续项目「0 第三方运行时依赖」原则
- ES2020 直写（ArkWeb Chromium 支持）
- 禁止 `innerHTML` 接触用户内容（见 4.9），DOM 构造一律 `createElement` + `textContent`

### 4.2 DOM 结构

```html
<div class="doc" data-page="...">
  <div class="blk" data-uuid="..." data-level="0" data-mode="render">
    <div class="bullet" data-collapsed="false"></div>   ← 折叠圆点，点击 toggleCollapse
    <div class="marker">TODO</div>                       ← 有 marker 时
    <div class="ct" contenteditable="true">...</div>    ← 唯一可编辑区
  </div>
  ...
</div>
```

- 缩进：`margin-left = level * 24px`（CSS variables，随断点调整）
- 折叠：`doc.load` 全量下发含 collapsed；JS 渲染时折叠块的后代（连续 `level > 祖先` 段）`display: none`；`patch[collapse]` 时重算该段
- 块选择模式（对齐 Logseq）：点击 bullet 进入选择态，`.blk[data-selected]` 高亮，批量命令经 `op.request` 转发

### 4.3 Live Preview 翻转算法（核心）

```js
onSelectionChange():
  active = caret 所在 .blk
  if (active === lastActive) return                    // 无翻转，零开销
  if (composing) return                                // IME 组合期冻结（见 4.6）
  if (lastActive) renderBlock(lastActive)              // render：源码 → 渲染态 DOM
  if (active) sourceBlock(active)                      // source：渲染态 → 源码文本
  lastActive = active

renderBlock(blk):   // 剥 contenteditable、按源码重建渲染 DOM（textContent 读入 → renderer 输出）
sourceBlock(blk):   // 恢复源码文本、开 contenteditable、caret 按缓存 offset 归位
```

细则：
- **每次翻转只碰 2 个块**，其余块的 render 态由 `content-visibility` 惰性维护——这是性能成立的根基
- 源码态保留 caret 位置：`sourceBlock` 前记录全局字符 offset，恢复后重设
- `mode.source` = 全部块锁 source + 行内弱高亮；`mode.preview` = 全部 render + 关闭所有 contenteditable；`mode.split` = DOM 两列（左源码右渲染，共享滚动）——比再开一个 ArkWeb 实例便宜一个数量级

### 4.4 键盘契约 → EditorService 映射表

JS 只做**检测与路由**，语义全部落在原生（现有 API 直接映射）：

| 按键 | JS 检测条件 | `op.request` | EditorService 落点 | 状态 |
|---|---|---|---|---|
| Enter | 无修饰 | `split {uuid, head, tail}` | **新增 `splitBlock`**（事务：update 原块 + insert 尾块） | 需补 |
| Shift+Enter | — | 本地插入 `\n` | （edit.block 上报） | 现成 |
| Tab | — | `indent {uuid}` | `indentBlock()` | 现成 |
| Shift+Tab | — | `outdent {uuid}` | `outdentBlock()` | 现成 |
| Backspace | 块空 | `deleteEmpty {uuid}` | `deleteEmptyBlock()` | 现成 |
| Backspace | offset=0 且有前块 | `mergeIntoPrev {uuid}` | **新增 `mergeBlockIntoPrev`**（事务：update 前块 + delete 本块） | 需补 |
| ArrowUp | 视觉首行 | `focusPrev {uuid}` | 新增 `focusRelative(uuid, -1)` | 需补 |
| ArrowDown | 视觉末行 | `focusNext {uuid}` | `focusRelative(uuid, +1)` | 需补 |
| Alt+↑ / Alt+↓ | — | `moveUp/moveDown` | `moveBlockUp/Down()` | 现成 |
| Ctrl+Z / Ctrl+Y | — | 撤销路由（见 4.10） | `undo()/redo()` | 现成 |
| Ctrl+B / I / E / H | — | 本地 `cmd.format` | （不落原生） | 现成 |
| Ctrl+K | — | 转发原生 | ShortcutService（ContentArea `onKeyPreIme` 已拦截，**零改动**） | 现成 |

> 新增的 4 个 API（split / merge / focusRelative ×2）都是 EditorService 层的小函数 + OutlinerOps 组合事务，Validator 校验走现成管线。这是本方案原生侧的全部新增逻辑量。

#### 4.4.1 跨块光标：goalColumn 算法（R1 §3.2-3 升格）

ArrowUp/Down 离开当前块进入相邻块时的落点，采用 Obsidian Widget 跨块算法的等价实现：

```
记录：每次水平移动/点击时更新 goalColumn（目标列的 x 坐标）
离开块 A 进入块 B：
  candidate1 = B 中 x 最接近 goalColumn 的字符 offset（二分/CaretPositionFromPoint）
  candidate2 = min(B 首行宽, goalColumn)  ← B 行宽不足时的截断落点
  取 |实际列x − goalColumn| 更小者；行宽不足时 goalColumn 保留（下一次垂直移动仍可用）
```

- `focusRelative` 的 JS 端在发 `op.request` 前用此算法计算目标 offset，随消息携带 `{uuid, offset}`，原生只路由焦点不猜位置
- 这消除了「跨块导航光标总跳到块首/块尾」的廉价感——是 Obsidian 键盘手感的核心细节

#### 4.4.2 代码块 / 表格的编辑态（R1 §3.2-2，v1 简化）

Obsidian 对代码块/表格用 CM6 Widget + StateField（光标进入整块切换为源码编辑视图）。Callaite v1 采用其**呈现语义**、不采用其 Widget 机制：

| 状态 | 呈现 | 编辑 |
|---|---|---|
| 光标不在块内 | ``` 围栏内容整块 `<pre>` 渲染（等宽字体 + codeBg） | 不可编辑 |
| 光标进入（点击/键盘到达） | **整块翻转为 source 态**（含围栏标记 ``` 的原始文本），等宽字体 | contenteditable，所见即源码 |
| 光标离开 | 恢复 `<pre>` 渲染 | — |

- 即代码块/表格在 Live Preview 中作为**原子块**参与翻转——与普通块的「块内翻转」不同，粒度升到整块
- 表格 v1 不做列感知编辑（Markdown 源码态直接编辑管道符文本）；结构化表格编辑列 v2
- Widget 化（悬浮编辑窗、语法高亮输入区）列 v2 观察

### 4.5 块内渲染器 token 集

与现 `ContentRenderer.ets` / WebEditor 词法对齐（不新造语法）：

`**bold**` · `*em*` / `_em_` · `` `code` `` · `==highlight==` · `~~strike~~` · `[[wikilink]]` · `[[alias|wikilink]]` · `#tag` · `[text](url)` · `<2026-09-26>`（scheduled/deadline 徽标）· marker 胶囊（TODO/DOING/DONE/LATER/NOW）· 代码块（``` 围栏，整块 `<pre>` 渲染，render 态不可编辑、source 态可编辑）

渲染器输出 `DocumentFragment`，节点值全部走 `textContent`。wikilink/tag 带 `data-target`，点击 → `link.open`。

### 4.6 IME 防护（组合输入硬关卡）

- `compositionstart` → `composing = true`：**冻结该块一切重渲染、翻转、patch 应用**（受影响 patch 排队）
- `compositionend` → `composing = false` → 排队 patch 应用 + 正常翻转
- **overlay Enter 防误触**（R1 §3.4，Obsidian 建议面板同款判定）：斜杠菜单/自动补全的 Enter 确认处理器必须检查 `event.isComposing`（或等价的 composing 标志）——组合态的 Enter 是「上屏候选词」，绝不能当作菜单确认
- 验收以拼音「你好世界」逐字确认 + 播号器（连续 20 字）无闪断、无重复、无丢失
- 物理/软键盘均测；这是 Phase 2 出口条件，不是可选项

### 4.7 性能设计

| 手段 | 说明 |
|---|---|
| `content-visibility: auto` + `contain-intrinsic-size` | 视口外块跳过布局绘制，500+ 块文档滚动预算的根基 |
| 翻转只碰 2 块 | selectionchange 处理 O(1)（含 lastActive 短路） |
| patch 局部重建 | 按 `affectedUuids` 定位，`replaceChildren` 局部段，不整页重载 |
| 编辑节流 | input → 150ms 合并上报；渲染态块永不因输入重排 |
| 预热 | EntryAbility 调 `webview.WebviewController.initializeWebEngine()`，冷启动预算从 ~600ms 压到 <300ms |

### 4.8 主题注入

`theme.set` 携带 MaterialTokens 摘要：`surface0/1、textPrimary/Secondary、accent、codeBg、border、selectionColor` 等，JS 写入 CSS variables。ThemeManager 切换 → EditorHost 广播两窗格。暗色模式为同一套变量换值，无闪烁。

### 4.9 安全

- **DOM 构造只用 `createElement` + `textContent`**，用户内容永不进 `innerHTML` —— `<script>` `<img onerror>` 等全部按字面渲染。消灭现 WebEditor 的转义拼接类问题
- Web 组件配置：`fileAccess(false)`、`onLineIntercept` 只放行 http/https、无 systemPath
- 壳与数据经 `$rawfile` 加载，不落 cacheDir —— 消灭 per-block HTML 文件写入与读放大
- 链接点击统一 `link.open` 出口，wiki 走页面路由、url 走系统浏览器，白名单协议拦截其余
- **反面论据（R2 实证）**：Obsidian 渲染进程 `nodeIntegration: true` 且无沙箱——插件即进程权限，是其整个生态攻击面的根源。Callaite 的桥最小面（双通道 + 参数化注入 + 无 Node 能力）是刻意的架构对立面；评审任何「给 JS 侧加能力」的提案时，先过这条对照

### 4.10 撤销设计（v1.2 依外部核验修正）

**已知缺陷（升级为 known bug）**：`OutlinerEngine:329` 的 undo 明确**不支持 update-block**——现网路径「块内打字（update-block）→ Enter 切块（split）→ Ctrl+Z」时，结构栈顶是 split 但它依赖的文本变更不在任何栈上，撤销**静默失败**（无效果也无提示）。这比 v1.0 假设的「两栈不互通」更糟，本方案必须修：

- **文本栈（JS 侧）扩为跨块页内历史**：`{seq, uuid, old, new}` 环形队列（上限 100 条，`seq` 为页内单调序号）。split/merge 的 `op.request` 在原生执行前，JS 先把「前块的文本变更」压栈（split: `{old: full, new: head}`；merge 反之）——保证结构操作所依赖的文本前态可回退
- **结构栈**：OutlinerEngine 事务 undo（现成，split/merge/move/delete 均支持）
- **路由规则**：Ctrl+Z 时 JS 栈顶 `seq` ≥ 页内最后结构操作 seq → 本地应用文本回退；否则发 `op.request: undo`；结构与文本交错时按 seq 交错回退（近似全局历史，v1 不做操作合并）
- 残余 gap：跨页撤销不可达（栈随 doc.unload 清空）——v1 接受并文档化

**验收（Phase 2 新增）**：块内改字 → Enter 切块 → Ctrl+Z → 回到改字前（一步文本回退）→ 再 Ctrl+Z → 回到切块前（两块合一）。

---

## 5. ArkTS 端设计

### 5.1 文件清单

**新增：**

| 文件 | 职责 |
|---|---|
| `rawfile/editor/editor.html / .css / .js` | Web 侧全部（见 §4） |
| `services/editor/EditorProtocol.ets` | 消息类型定义 + JSON 编解码 + rev 记账（纯逻辑，可单测） |
| `services/editor/EditorHost.ets` | 每窗格一个：持 WebviewController、协议收发、doc.load/patch 投影、看门狗、主题广播 |
| `components/outliner/DocumentEditor.ets` | UI 组件：挂 Web、loading 态、接收 `pageOverride/paneId`、对接 PageView 生命周期 |
| `test/EditorProtocol.test.ets` | 编解码 + BlockDTO/patch 序列化 round-trip 单测 |

**修改：**

| 文件 | 改动 |
|---|---|
| `components/page/PageView.ets` | 特性开关分支：`'document'` → DocumentEditor；`'legacy'` → BlockList（现状） |
| `services/EditorService.ets` | 新增 `splitBlock` / `mergeBlockIntoPrev` / `focusRelative`（见 4.4 表）+ `setFocusedBlock` 由 `caret.change` 驱动 |
| `core/engine/OutlinerOps.ets` | split / merge 组合事务（经现有 Validator 管线） |
| `components/outliner/SlashMenu.ets` | 触发源从 BlockView 调用改为 `slash.trigger` 事件 + `caret.rect` 锚定 |
| `components/outliner/FindInPage.ets` | 逻辑下放 JS（`search.*` 协议），组件保留输入框与状态条 UI |
| `components/mobile/MarkdownToolbar.ets` | `cmd|seq` 通道退役 → `cmd.format` / `cmd.insertText` 协议 |
| `components/outliner/BlockDragHandler.ets` | 供 BlockList 路径继续使用；document 路径由 JS pointer 事件 + `drag.block` 承接 |
| `entryability/EntryAbility.ets` | `initializeWebEngine()` 预热 |
| `state/TabState.ets` | v2 快照（见 §6） |
| `components/settings/SettingsPage.ets` | 开发者选项：编辑器引擎切换 |

**Phase 6 删除：** `WebEditor.ets`、`IntegralEditor.ets`、`LivePreviewHelper.ets`、`MarkdownSegmenter.ets`（删除前 grep 确认无残留引用）、`RichBlockEditor.ets`（Phase 0 审计后定）、cacheDir per-block HTML 写入逻辑。

### 5.2 EditorHost（核心服务）

```ts
class EditorHost {
  attach(controller: WebviewController, paneId: string): void
  loadDocument(pageName: string): void          // 块树全量 → BlockDTO[] → doc.load
  applyPatch(op: OutlinerOpResult): void         // affectedUuids → PatchOp[] → doc.patch
  sendCommand(cmd: EditorCommand): void          // cmd.* / search.* / mode.set / theme.set
  captureSnapshot(): TabSnapshot                 // 缓存的 scroll + 当前 focus
  restoreSnapshot(s: TabSnapshot): void          // cmd.scroll + cmd.caret
  onMessage(msg: EditorToNativeMsg): void        // 路由到 EditorService / AppState / overlay 事件总线
}
```

- 实例表按 paneId 管理（`primary` / `secondary`），消息天然隔离
- `applyPatch` 挂接点：OutlinerEngine 事务回调（与 SaveQueue 同源），保证结构变更后 JS 与持久化同序
- overlay 事件（`slash.trigger` / `ac.trigger` / `caret.change`）经回调注入 PageView 层，锚定用 `caret.rect`（CSS px → vp 换算）

### 5.3 DocumentEditor 组件

- `@Prop pageOverride / paneId`，与 ContentArea 分屏约定对齐
- 挂 `Web({ src: $rawfile('editor/editor.html'), controller })`，`javaScriptProxy` 注入（或 MessagePort，见 3.1）
- 首帧 loading 态（页面骨架 + spinner），`loaded` 回执后淡入

### 5.4 特性开关

- `AppStorage['callaite_editorEngine']`，默认 `'legacy'`
- CommandPalette 加隐藏命令「切换编辑器引擎」（开发期用），4.4.0 起默认翻转 `'document'`，4.5.0 删除 legacy 路径
- **回滚成本 = 切一个字符串**

---

## 6. TabState v2（标签页状态快照）

### 6.1 Schema

```ts
interface TabSnapshot {
  scroll: number;        // px，来自 scroll.change 缓存
  focusedBlock: string;  // uuid，'' = 无焦点
  caret: number;         // 块内 offset
  viewMode: string;      // 'live' | 'source' | 'preview' | 'split'
  splitPage?: string;    // 副窗格路由（有分屏时）
  splitRatio?: number;   // 分屏比例
}

interface TabInfo {
  id: string;
  page: string;
  pinned: boolean;
  snapshot: TabSnapshot;   // 新增
}
```

### 6.2 时机与路径

- **快照**：`MainContainer @Watch(currentPage)` 在切换前调 `TabState.deactivate(oldTabId)` → `EditorHost.captureSnapshot()` 写入
- **恢复**：`activate(newTabId)` → 若页面已装载（同页复用）直接 `restoreSnapshot`；否则 `doc.load` 携带 `scrollHint / focusHint`
- 打开新标签、关闭标签的路径不变（TabState 现有逻辑）

### 6.3 兼容（v1.2 依外部核验重写——P0 级数据安全）

- **版本标记不得放进 tabs JSON 顶层**：v1.1 方案「持久化 JSON 增加 `v: 2` 字段」有致命缺陷——`getTabs()` 里 `parsed.length` 对含 `v` 键的对象数组仍成立，但 `initialize()` 判空路径与 `parsed as TabInfo[]` 的逐字段读取在含额外顶层键时会与 `escape()` 手写序列化互相破坏；更糟的是旧版读新版文件时任何解析异常都走 `catch → return []` → **initialize 重置为单 Journal 标签，用户全部标签静默丢失**。修正：
  - schema 版本放**独立 AppStorage 键**（`callaite_tabsSchema: 1 | 2`），tabs JSON 本体只含数组——旧版读新数组天然向前兼容（多出的 `snapshot` 字段被逐字段构造器丢弃）
  - `escape()` 边界注记：转义仅覆盖 `\` 与 `"`；page 名经文件名校验不含控制字符（PageTree 建页路径约束），**此为不变式前提**——若未来放开页面名的字符域，`escape()` 必须同步扩展（列入代码注释与本文档）
  - **四个重建落点清单**（任何改 TabState 持久化的 PR 必须逐点核对）：① `getTabs()` 解析 ② `initialize()` 首启判空 ③ `StatePersistence.load()` 恢复后（EntryAbility 时序）④ `closeTab/closeOthers` 的数组收缩
- 新增字段全部为标量（`scroll: 0`、`viewMode: 'live'`、`focus: ''`），手写序列化沿用现有 `escape()`，混淆安全不变
- **schema 对齐说明（R2 §5）**：Obsidian 的 `workspace.json` 布局树为 split/tabs/leaf 三型节点，leaf 持 `state`（视图类型 + 每视图独立状态）。`TabInfo.snapshot` 即 leaf.state 的扁平对应——若 4.5+ 做多窗格/多 leaf，将 snapshot 收进 per-leaf state 节点即可，无需迁移格式（现在按此边界设计，避免二次迁移）

### 6.4 同期补齐的标签页交互皮（Obsidian 对齐）

中键关闭、`TabOverviewSheet` 长按预览信息补全、未 pin 标签超宽渐隐 + 横滑。**不做**拖拽排序（ArkUI Tabs 拖拽手势成本高，列入 v2 观察）。

---

## 7. IntegralEditor 收编

| IntegralEditor 模式 | DocumentEditor 承接 |
|---|---|
| live（实时阅览） | 默认模式（本方案本体） |
| source（源码） | `mode.set: 'source'` |
| preview（阅读） | `mode.set: 'preview'` |
| split（分屏） | `mode.set: 'split'`（JS 内两列，见 4.3） |

- PageView 顶部模式切换器保留，切换器语义不变
- 「应用并重建大纲」按钮退役：live 模式下块树与显示实时同步，不存在「先改源码再应用」的心智模型
- 收编完成后删除 IntegralEditor + LivePreviewHelper + MarkdownSegmenter（MarkdownRoundTrip 测试保留，成为原生解析器与 JS 渲染器的共同契约）

---

## 8. 阶段执行计划

> 每阶段独立提交、独立可回滚。预估按「单人 + 每天有效 4h」计。

### Phase 0：冻结与开分支（0.5 天）

**目标**：协议冻结，文档评审通过，分支就位。

- [ ] 本文档评审（批注 → 修订 → 状态改 Accepted）
- [ ] `git checkout -b feature/document-editor`
- [ ] 审计 `RichBlockEditor.ets` 引用情况，确定保留/删除
- [ ] 审计 `AutoComplete.ets` 挂载点（grep 未见 `AutoComplete({` 调用，疑似死组件，确认后处置）
- [ ] `webview.WebviewController.initializeWebEngine()` 预热接入 EntryAbility（独立小 commit，legacy 路径立刻受益）

### Phase 1：协议 + 通道 + 静态骨架（3–4 天）

**目标**：flag 下挂出一个能静态渲染块树、可点击翻转 source/render 的 Web 文档，无编辑语义。

- [ ] **Spike（D1 上午）**：MessagePort 双向往返 demo，按 3.1 决策规则定通道
- [ ] `EditorProtocol.ets`：类型 + 编解码 + rev 记账
- [ ] `EditorProtocol.test.ets`：round-trip 单测（LocalUnitTest）
- [ ] `EditorHost.ets`：attach / loadDocument / 看门狗
- [ ] rawfile 三件套骨架：DOM 结构（4.2）+ 静态渲染器（4.5）+ 翻转算法（4.3，不含 IME 细节）
- [ ] `DocumentEditor.ets` 组件 + PageView 开关分支
- [ ] 主题注入（4.8）首版

**验收**：开发者开关切到 document，Journal 页在 Web 内静态渲染 500 块测试文档，点击块 A → A 变源码、原块恢复渲染；DevEco Profiler 滚动不掉帧。
**回滚**：开关切回 legacy。

### Phase 2：键盘契约 + 保存链 + IME（4–5 天）

**目标**：document 路径达到 WebEditor 全部键盘语义，可日常自用。

- [ ] `OutlinerOps` 补 split / merge 组合事务（Validator 管线）
- [ ] **持久化路径 spike**（I3 v1.2）：500 块页连续输入实测 persistForOp 卡顿——超预算则 update-block 增量写走 SaveQueue 聚合（~1 天）
- [ ] `EditorService` 新增 `splitBlock / mergeBlockIntoPrev / focusRelative`（含 4.4.1 goalColumn 算法的 JS 端）
- [ ] JS 键盘层：4.4 映射表逐条实现
- [ ] `edit.block` → 150ms 合并 → updateBlockContent → executeOp('update-block') 链路（I3 真实路径）
- [ ] **卸载序保证**：blur / 标签切换 / onBackground → `ack.doc.saved` 确认后才 `doc.unload`（I3 v1.2）
- [ ] 撤销路由（4.10 v1.2：跨块文本栈 + seq 交错回退 + 静默失败回归用例）
- [ ] `caret.change` → `EditorService.setFocusedBlock`（`callaite_focusedBlock` 键不变，外围依赖不破坏）
- [ ] `doc.patch` 投影：insert/delete/move/update/marker/collapse 六类
- [ ] **IME 硬化**（4.6，含 overlay Enter 的 isComposing 检查）+ 拼音逐字验收清单

**验收**：① 4.4 表逐键手测通过（含块中间 Enter 分裂、块首 Backspace 合并）；② 「你好世界」+ 连续 20 字播号无闪断；③ kill 进程重启，内容丢失 ≤ 150ms 合并窗口（同步落盘链路下应趋近 0）；④ 自用 Journal 写一天，无「切回 legacy 才能干活」的时刻；⑤ 4.10 双段撤销（打字→切块→两次 Ctrl+Z）通过。
**回滚**：开关切回 legacy。

### Phase 3：overlay 改接 + 移动端（4–5 天）

**目标**：SlashMenu / 自动补全 / FindInPage / MarkdownToolbar / 拖拽在 document 路径全量可用。

- [ ] SlashMenu：`slash.trigger` + `caret.rect` 锚定 + `cmd.insertText` 回填
- [ ] 自动补全（`[[` 页面 / `#` 标签）：`ac.trigger` + overlay 复用现有组件
- [ ] FindInPage：JS 侧搜索 + 高亮 + `search.state` 回报
- [ ] MarkdownToolbar（移动端工具行）：`cmd.format` 全 kind + 键盘避让
- [ ] 块拖拽：JS pointer 事件 + drop 指示线 + `drag.block` → `moveBlockToTarget`
- [ ] 块选择模式：bullet 点选 + 批量 op 转发（对应 EditorService 多选 API）
- [ ] 移动端专项：safe-area 透传（ContentArea `mobileTopInset/BottomInset` 已有值）、触摸滚动 vs 长按选区手势消歧（`touch-action` + 长按 350ms 阈值）
- [ ] `link.open` 出口 + 白名单

**验收**：手机真机（非模拟器）全流程：斜杠建 TODO、`[[` 补全跳页、工具行加粗、拖拽重排、页内搜索。任一失败不出阶段。
**回滚**：开关切回 legacy。

### Phase 4：显示模式收编（2–3 天）

**目标**：IntegralEditor 四模式在 document 路径成立，legacy 编辑栈退出主路径。

- [ ] `mode.set` 四模式 JS 实现（split = DOM 两列共享滚动）
- [ ] PageView 模式切换器对接（语义不变）
- [ ] MarkdownRoundTrip 扩展：golden corpus（≥30 用例覆盖 4.5 token 全集），作为 JS 渲染器与 MarkdownParser 的契约
- [ ] 删除 IntegralEditor / LivePreviewHelper / MarkdownSegmenter

**验收**：四模式切换 <100ms；golden corpus 全绿；「应用并重建大纲」交互无残留。
**回滚**：整个 Phase 是独立 commit，revert 即回。

### Phase 5：TabState v2（2–3 天）

**目标**：标签 = 带视图状态的标签。

- [ ] `TabInfo.snapshot` + 持久化 v2 兼容（6.3）
- [ ] `deactivate/activate` 快照链（6.2）
- [ ] `doc.load` 携带 `scrollHint/focusHint` 恢复
- [ ] 中键关闭、标签溢出横滑等交互皮（6.4）

**验收**：A 标签滚到中部 + 光标在第 8 块 → 切 B → 回 A：滚动位置、焦点块、光标 offset、显示模式全部复原；冷启动恢复同样成立（杀进程重启）。
**回滚**：snapshot 字段读写包 try-catch，异常回零值。

### Phase 6：teardown 与默认翻转（1 天 + 观察 1–2 周）

**目标**：legacy 路径退役。

- [ ] 自用 document 路径 **≥10 天无「必须回 legacy」的缺陷**后，默认翻转 `callaite_editorEngine = 'document'`（版本号 4.4.0）
- [ ] 观察期结束（再 2 周）→ 删除 WebEditor.ets + cacheDir HTML 写入逻辑 + 开关本身（4.5.0）
- [ ] README 主轴章节更新：「4.x 主轴为 DocumentEditor 编辑器 + 白板」

**验收**：grep 全仓无 WebEditor / IntegralEditor / per-block HTML 残留引用；安装包体积对比记录进 README。

---

## 9. 测试与性能预算

### 9.1 测试矩阵

| 层 | 内容 | 载体 |
|---|---|---|
| 单测 | EditorProtocol 编解码 round-trip、rev 记账 | `EditorProtocol.test.ets`（LocalUnitTest） |
| 契约 | golden corpus：MarkdownParser ↔ JS 渲染器 token 全集（≥30 例） | `MarkdownRoundTrip.test.ets` 扩展 |
| 契约 | **附录 C：Obsidian 语法对齐矩阵（20 例，边界行为断言）** | 同上，独立 describe 块 |
| 单测 | split/merge 事务：OutlinerCore（含 undo 恢复） | `OutlinerCore.test.ets` 扩展 |
| 手测 | 4.4 键盘映射表逐条 + IME 清单 | 文档化 checklist（手机 + 2in1 各一轮） |
| 渗透 | `<script>` / `<img onerror>` / `[[a\|b\|c]]` / 超长行 / 全角符号 | 内容按字面渲染断言 |

### 9.2 性能预算（超出即停下优化，不带病推进）

| 指标 | 预算 | 测量方式 |
|---|---|---|
| 首次 doc.load → loaded（500 块） | < 400ms（预热后 < 300ms） | JS performance.now 上报 |
| 键盘敲击 → 屏显 | < 30ms | 手感 + Profiler |
| 翻转（render↔source） | < 16ms（单帧内） | performance.now 包裹 |
| 滚动（1000 块） | 无掉帧（>55fps） | DevEco Profiler |
| **连续输入（500 块页 × 10s）** | **无 >100ms 主线程卡顿**（persistForOp fsync 路径，v1.2 新增） | Profiler 主线程 trace |
| 单 Web 实例常驻内存 | < 150MB | hidumper |
| 20 标签切换内存增长 | ≈ 0（数据换内容，实例不增） | hidumper 连续采样 |

---

## 10. 风险登记册

| # | 风险 | 概率 | 影响 | 缓解 | 回滚触发 |
|---|---|---|---|---|---|
| R1 | MessagePort API 形态不符预期 | 中 | 低 | 3.1 决策规则当天回退 runJavaScript 通道，协议层无感 | — |
| R2 | IME 组合态竞态（翻转/patch 插入组合文本） | 中 | **高** | 4.6 冻结协议；Phase 2 出口条件；真机三输入法验收 | 拼音验收不过不出 Phase 2 |
| R3 | Web 常驻内存超预算 | 低 | 中 | 预热 + 单实例模型本身低成本；9.2 监控 | 超预算 2 周无解 → 评审会（仍可保留 legacy） |
| R4 | 触摸滚动 vs contenteditable 手势冲突 | 中 | 中 | `touch-action` 消歧 + 长按阈值；Phase 3 真机专项 | 真机不可用 → 该手势走原生层代理 |
| R5 | split/merge 事务与现有 Validator 冲突 | 低 | 中 | 走现有事务管线 + OutlinerCore 单测先行 | 单测红 → 修事务不动 JS |
| R6 | patch 投影丢帧（结构高频操作卡顿） | 低 | 中 | 局部重建 + 全量 reload 兜底开关 | — |
| R7 | 双窗格消息串线 | 低 | 高 | EditorHost 按 paneId 实例隔离，通道对象级绑定 | 任何串线 bug → 暂禁 document×分屏 组合 |
| R8 | 撤销两栈割裂体验 | 确定 | 低 | 4.10 路由规则缓解；known gap 文档化；v2 统一 | — |
| R9 | 兼容性：API 26 行为差异再现 | 低 | 中 | editor.js 保守用 ES2020 核心；beta 渠道灰度 | — |

---

## 11. 里程碑与版本对齐

| 版本 | 内容 | 退出条件 |
|---|---|---|
| 4.3.0 | Phase 0–2（flag 默认 legacy，document 可自用） | IME + 键盘契约验收 |
| 4.3.x | Phase 3–4 补丁流 | overlay 全量 + 四模式 |
| 4.4.0 | Phase 5 完成后默认翻转 document | 快照验收 + 10 天自用无回退 |
| 4.5.0 | Phase 6 teardown | legacy 路径删除 |

**总量预估**：17–21 个工作日（不含观察期）。发布阻断项（bundleName / 签名 / 隐私政策等 5 项）**不混入本主轴**，另行处理。

---

## 12. Non-goals（明确不做）

- Electron / 自研 Web 框架（ADR-002）
- Navigation 全壳迁移（ADR-004 搁置判据）
- 协同编辑 / CRDT（rev 冲突兜底即可）
- 统一撤销栈（v2）
- wikilink 悬浮预览、嵌入块实时渲染增强（编辑器稳定后的下一批；实现参照 R1 §5 分节渲染 parseSections——按需渲染单顶层块而非整页，移动端 hover 场景的成本护城河）
- 标签页拖拽排序（v2 观察）
- 插件编辑器 API（ADR-005 仅预留 `ctx` 字段，功能另立项）
- 变更通知细化（changed/finished 双事件模式，R1 §4.1：逐文件 changed + 队列空 10ms 防抖 finished——用于替代粗粒度 blocksVersion bump，联动 UI 方案的全树刷新问题；编辑器主轴稳定后做，避免两条轴线同时动 IndexStore）

---

## 附录 A：消息 JSON 样例

```json
// doc.load（N→E）
{"t":"doc.load","pageId":"2026-09-26","viewMode":"live",
 "blocks":[{"uuid":"a1","content":"TODO 完成 **编辑器** 方案","level":0,
            "marker":"TODO","collapsed":false,"scheduled":"","deadline":"","priority":""}],
 "scrollHint":812,"focusHint":{"uuid":"a1","offset":5}}

// edit.block（E→N）
{"t":"edit.block","uuid":"a1","content":"TODO 完成 **编辑器** 方案 v1.1","rev":42}

// op.request（E→N）
{"t":"op.request","op":"split","uuid":"a1","head":"TODO 完成","tail":"方案 v1.1"}

// doc.patch（N→E）
{"t":"doc.patch","rev":43,
 "ops":[{"type":"update","uuid":"a1","content":"TODO 完成"},
        {"type":"insert","uuid":"a2","after":"a1","level":0,"content":"方案 v1.1"}]}

// caret.change（E→N，rect 为 CSS px）
{"t":"caret.change","uuid":"a1","offset":5,"rect":{"x":64,"y":318,"w":2,"h":22}}
```

## 附录 B：Obsidian Live Preview 对齐清单（验收口径）

| # | 行为 | 对齐目标 |
|---|---|---|
| B1 | 光标所在块显示源码标记，其余块实时渲染 | 逐块翻转，无整页闪烁 |
| B2 | 点击渲染块 → 该块转源码并落光标（点击处附近） | caret offset 按 x 坐标就近归位 |
| B3 | 移出后块恢复渲染，且不改变内容 | 渲染态与源码 round-trip 恒等（golden corpus 保证） |
| B4 | 行内代码 / wikilink / tag 在源码态保留颜色弱提示 | Obsidian 同款「淡标记」样式 |
| B5 | 选区跨块时的视觉连续性 | v1 单块选区；跨块选择走块选择模式（4.2） |
| B6 | preview 模式点击 wikilink 可跳转 | `link.open` 出口 |
| B7 | 折叠动画 | v1 无动画（直接显隐），动画列 v2 |
| B8 | 代码块/表格为原子块（光标进入整块转源码） | 4.4.2 |
| B9 | 跨块垂直移动光标列对齐（goalColumn） | 4.4.1 |

## 附录 C：Obsidian 语法对齐测试矩阵（v1.1 新增）

**总则（v1.2 依外部核验补）**：Callaite 是块模型大纲方言，Obsidian 是连续文本——同形输入在语义边界上允许有 deliberate divergence。本矩阵的角色是**兼容参考**（Import/Obsidian 用户迁移时行为不令人惊讶），**不是判定标准**；每例「Callaite 断言」即方言定义本身。标注 ⚠️ 的条目需先核实现解析器行为再定案。

**来源**：R1 §1.2/1.3 从 worker.js 反混淆实现中提取的实证规则（非规范推断）。**用途**：`MarkdownRoundTrip` golden corpus 的边界用例——每例断言 MarkdownParser 与断言列**一致**；不一致者按「Callaite 有意偏离」标注并给理由，禁止静默偏离。

| # | 输入 | Obsidian 实测行为 | Callaite 断言 |
|---|---|---|---|
| C1 | `- [ ] 任务` / `- [x] 已完成` / `- [X] 大写` | 任务项标记，大小写均可 | TODO/DONE marker |
| C2 | `- [任意字符] 文本`（如 `- [!] 重要`、`- [?]`） | **仍判任务项**（`[.+?]+\s`，非白名单字符集） | ⚠️ 现解析器若只认 `x /空格`，扩为「任务项任意内容 + 状态白名单驱动样式」；非白名单内容无状态胶囊 |
| C3 | `- [ ]无空格` | **不判任务项**（标记后必须空白） | 同款：marker 与文本间需空白 |
| C4 | `#标签` / `#嵌套/子标签` | 嵌套 tag，按 `/` 建层级 | 同款（图谱/筛选按层级聚合） |
| C5 | `#123` | **纯数字拒绝**（避千年虫式解析） | 同款 |
| C6 | `#标签#` | **不识别**（tag 正则含 `[[` 拒绝） | 同款 |
| C7 | `[[页面]]` | wikilink | 同款 |
| C8 | `[[页面\|别名]]` / `[[页面|别名]]`（半角管道） | 别名（`d+` 不含 `\|`，见 worker L11466） | alias 渲染 |
| C9 | `[[页面#标题]]` | 页内 heading 跳转 | v1 存链接语义；**跳转到 heading 列 BlockAnchor 后续项**（依赖 UI 方案 U2.1） |
| C10 | `[[页面#^blockid]]` | 块引用跳转 | 同 C9 依赖 |
| C11 | `^abc123`（块尾） | 块 id，**小写字母数字**，索引到 MetadataCache | v1 解析入库；引用跳转同 C9 |
| C12 | `![[嵌入页]]` / `![[图片.png]]` | 页/媒体嵌入 | 同款（现 BlockView 双显示缺陷一并修） |
| C13 | `==高亮==` | 高亮 | 同款 |
| C14 | `---`（三横线）文档头部 | Frontmatter 解析（YAML） | properties 现有；**位置语义对齐：仅在文档头识别** |
| C15 | 标题 `#`–`######` | heading，**0-based 位置索引**（R1：links/tags/headings 位置全部 0-based） | ⚠️ 审计现 IndexStore 位置语义统一 0-based；不一致即修（影响块锚点精度） |
| C16 | `<dl>`（ISO 日期） | 日历弹窗交互徽标 | 现有 `<2026-09-26>`；对齐无 `@` 前缀变体行为 |
| C17 | wikilink 指向不存在页面 | 仍入 links 索引（创建入口） | 同款（BacklinkFilters 的 unlinked 区分依赖） |
| C18 | tag 后接 CJK 无空格（`#中文标签内容`） | tag 词尾按空白/标点截断 | ⚠️ 实测确认 CJK 截断规则（报告未覆盖，真机验证补录） |
| C19 | 嵌套 wikilink 内含 tag（`[[#嵌套]]`） | 标题引用形态 | 归 C9 家族 |
| C20 | `%%注释%%` | 注释语法 | v1 **有意偏离**：不实现（现生态无消费方）；记录在案防静默蔓延 |

**维护规则**：任何 Callaite 解析器行为变更触及上表语义 → 先改矩阵、跑全绿、再合码。R1 报告原文位于 `docs/reverse/Obsidian-Parser-Editor-Deep-Dive.md` §1.2/1.3，正则原文可对照。
