# Callaite 项目交接文档

> 交接日期：2026-09-25 · 编写：AI 开发助手（基于 09-19 → 09-25 全程开发会话）
> 接手前必读三份文件：`Callaite-工作文档/README.md`（文档索引）、`Callaite_优化与升级方案_v2.md`（执行计划）、本文件
> 项目仓库：github.com/DouHaoyang-Developer/Callaite.git

---

## 一、项目概况

| 项 | 内容 |
|---|---|
| 定位 | Obsidian 风格的鸿蒙知识管理应用（Logseq 大纲 + Obsidian 桌面/移动体验） |
| 技术栈 | ArkTS / ArkUI · Stage 模型 · **targetSdkVersion 26.0.0（HarmonyOS 7）· compatibleSdkVersion 26.0.0** |
| 规模 | **144 个 .ets 源文件 / 30,449 行**（2026-09-25 复核；文档原记 140/34,195 已过时）· 0 第三方运行时依赖 |
| 架构 | MVVM + Service（15 单例）+ Plugin + Query 三层查询引擎（多条件/Datalog/递归规则） |
| 主题 | 明暗双套 token（对齐 Obsidian 官方默认主题变量，浅色像素级实测一致） |
| 仓库 | `F://DevEcoStudioProjects//Callaite//`（**不要打开工作区根目录**） |

**构建**：`bash "F:/DevEcoStudioProjects/Callaite-工作文档/03-构建与设备脚本/build_callaite.sh" debug`（产物 `entry/build/default/outputs/default/entry-default-unsigned.hap`）
> ⚠️ 脚本已于 2026-09-25 从根目录移入 `Callaite-工作文档/03-构建与设备脚本/`（根目录整理），旧路径 `F://DevEcoStudioProjects//build_callaite.sh` 已失效。

## 二、当前状态总览（接手第一件事：核对本节）

### 2.0 本轮新增发现（2026-09-25，AI 续作会话）

1. **模拟器第二个系统级缺陷：`foundation` 进程崩溃**
   - 现象：模拟器窗口**不再响应任何输入**（点击/文本注入全失效），界面停在最后一帧 —— 与用户报告的「整个模拟器窗口消失或卡死无响应」一致。
   - 证据：`/data/log/faultlog/faultlogger/cppcrash-foundation-5523-20260925113321169.log`
     `Reason: Signal:SIGILL(ILL_ILLOPN)` + `LastFatalMessage: ubsan: sub-overflow`，
     栈顶为 `OHOS::IPCProcessSkeleton::UnlockForNumExecuting()`（IPC 执行计数**下溢**，UBSan 触发即 abort）。
   - 归档与完整分析：`华为缺陷上报_附件/05_平板实测证据/证据7`、`证据8`。
   - **处置经验（重要）**：崩溃后模拟器若**热启动**会把崩溃态一起恢复（重启也没用）→ 必须
     **删除实例目录下 `ram.img`/`ram.bin` 强制冷启动**才能恢复（用户数据在 `userdata.img.qcow2`，不受影响）。
2. **`verify_o1_wal.sh` 已重写为 v2**（原 v1 无法使用，四处缺陷均已修复）：
   - v1 坐标 `(22,105)/(1500,800)` 是 O5 双栏改造**前**的布局，点不中 → 改为 `find_node.py` 从 dumpLayout 按文本动态解析坐标；
   - Git Bash 会把 `/data/local/tmp/...` 当本地路径改写 → 加 `MSYS2_ARG_CONV_EXCL='*'`（否则 dump/recv 静默失败）；
   - Python 输出 `✅/❌` 在 GBK 控制台抛 `UnicodeEncodeError` → 加 `PYTHONIOENCODING=utf-8`；
   - 固定测试文本会被上一轮遗留页面「满足」造成**假通过** → 改每轮唯一 marker + **磁盘级断言**（`grep` 落盘文件）。
   - 另需注意：`uitest uiInput text` 注入**中文无效**（实测），脚本一律用 ASCII。
3. **O5 双栏结构在 API 26 上渲染正常**（原「空白」报告为 API 24 时期现象），但发现 **Ribbon 与活动栏功能重复**（详见 2.2 表格）。
4. **O4 设备验证已执行，发现 P0 内容丢失缺陷（未闭环）**：
   - 验证结论（`verify_o4_editor_modes.sh`）：整页编辑入口 ✔、四模式按钮齐全 ✔、实时/源码/阅读/分屏 四模式切换渲染 ✔、应用按钮触达 ✔。
   - **但「应用并重建大纲」会把页面内容清空**：实测 `未命名 4.md` 块行数 **1 → 0**（另一页 `未命名 5.md` 直接变 0 字节）。
   - 已定位的机制：切换模式会**重建 RichEditor**（新控制器为空）→ `onReady → rebuildSpans()` 从空控制器提取 `''` 写回 → `onDidChange` 把 `this.markdown` 清空 → 应用时以空/退化文本重建整页。分屏模式原先还漏了回填（左栏空白）。
   - 已做的修复（防御性，已验证生效）：① `applyAndRebuild` 增加**空内容硬闸**（实测空页时正确弹出「内容为空，已取消重建」）；② `handleEditorChange` 不再用空提取覆盖非空 markdown；③ `rebuildSpans` 在编辑器为空时用 `this.markdown` 回填，并把分屏模式纳入回填分支。
   - **仍未闭环**：对有内容的页面执行「切换四模式 → 应用」后块行数仍 1 → 0，说明**送入 `replacePageBlocks` 的文本本身**与解析器期望不符（高度怀疑 `LivePreviewHelper.extractText()` 返回的是**去掉 `- ` 前缀的纯文本**，而 `MarkdownParser` 期望块前缀）。下一步：对比两者输出并让重建链路补回块前缀（或改用带前缀的源码文本作为唯一真源），并补一条「纯文本 → 重建 → 块数」单测。
   - 结论：**O4 不可发布**，直到该缺陷修复并跑通 `verify_o4_editor_modes.sh`（脚本已就位，含内容保全断言）。

### 2.0.1 O4 缺陷处置进展（2026-09-25 第二轮，AI 续作）

- **数据丢失已彻底阻断（设备实测）**：在 `DataStore.replacePageBlocks` 加了**数据层硬闸**——解析结果为空而页面原本有块时直接拒绝重建并 `console.error`。实测：`apply` 前后磁盘块行数 **1 → 1**，`verify_o4_editor_modes.sh` 的「apply 当场未丢内容」「页面内容未丢」两条断言均 ✔。
  - 另有两道 UI 层防御：`applyAndRebuild` 空内容硬闸（实测空页时正确提示「内容为空，已取消重建」）、`handleEditorChange` 不再用空提取覆盖非空 markdown、`rebuildSpans` 在编辑器重建时用 `this.markdown` 回填（并把分屏模式纳入回填）。
  - 调用方新增 `toMarkdown()`：正文若无块前缀则按行补 `- ` 后再重建。
- **功能仍未修复**：加了 `toMarkdown` 后，应用仍被硬闸拒绝（说明解析结果依旧为 0 块），即**上游文本的真实形态尚未确认**。已埋诊断日志：`[DataStore] replacePageBlocks refused: parsed 0 blocks, page had N, mdLen=…, md=…`
  - **下一步（半小时内可完成）**：启动应用 → 复现一次「整页编辑 → 应用」→ 立即 `hdc shell "hilog -x -n 500 -P $(hdc shell pidof com.example.callaite)" | grep replacePageBlocks` 读取 `md=` 片段与 `mdLen`，即可确定文本形态；随后在 `toMarkdown` 或 `IntegralEditor` 的文本来源处修掉，并跑 `verify_o4_editor_modes.sh` 复验（当前 9 通过 / 1 失败，唯一失败项为「应用并重建成功」）。

### 2.0.2 O4 根因定位（2026-09-25 第三轮）—— 缺陷在**上游索引**，不在编辑器

用「诊断 toast + hilog」两路取证，拿到了决定性证据：

```
# 诊断 toast（点击应用后）
空内容取消 | name=未命名 4  uuid=OK  md=0  txt=0  mode=live
# 新增日志（进入整页编辑时）
[IntegralEditor] loaded page=未命名 4 blocks=0 mdLen=0
# 同期磁盘
未命名 4.md 块行数 = 1        ← 文件里有内容
```

**结论：整页编辑器从内存里取到的是 0 个块**（page 名与 uuid 都解析成功），因此 markdown 为空 → 「应用并重建」被空内容闸门正确拦下（数据安全 ✓）。也就是说：

- 整页编辑器**不是**缺陷源头，它只是第一个暴露者；
- 真正的缺陷是 **页面块未进入内存索引**（磁盘有内容、内存为空），这会同时影响大纲视图、查询、反链等所有消费者；
- 已实现的 `getAllPageBlocks`（遍历 blockMap 而非 childrenMap）**同样返回 0**，说明不是父子索引的问题，而是块压根没被加载/归属到该页面。

**下一步（定位口很窄）**：
1. 设备上打开 `未命名 4` 的**大纲视图**并 dump —— 若大纲也是空的，确认「页面块未加载」是全局问题（而非整页编辑器专有）；若大纲有块，则问题在 `getPageByName` 返回的 page 对象与块的 pageId 不一致。
2. 查 `DataStore.loadGraph`：日志显示 `Loading 7 .md files` → `Graph loaded. Pages: 4`，需确认每个页面解析出的 blocks 是否真的 `addPage`/`loadPageBlocks` 到位（重点看 `未命名 4` 这类**文件名含空格**的页面：`pageNameToFileName` 往返是否一致、`getPageByName('未命名 4')` 命中的 uuid 是否与加载时用的 uuid 相同）。
3. 修好后跑 `verify_o4_editor_modes.sh`（应 10/10）与 `verify_o1_wal.sh` 复验。

> 提示：文件名含空格是一个**高风险嫌疑点**（本会话已因空格文件名踩过远端 grep 的坑）：`未命名 4.md` ← `pageNameToFileName('未命名 4')` 是否也是 `未命名 4.md`？若加载侧与索引侧的命名/清洗规则不一致，就会出现「文件在、页面在、块不在」的错配。

### 2.0.10 W2/W3/W4 批次结果与方法学教训 —— 2026-09-25（第 13–24 轮）

**已设备验收**：① 页签宽度自适应（实测 397/265/202/183px 互不相同；容器源码本就是 40vp）；③ AllPages 行高 32vp + 顶部工具栏（「名称 ↑」点击可翻转文案）；④ 设置搜索框 + 分组标题 + 插件三段式；⑥ PDF 空态两个按钮（旧 #F2F3F5 灰底按钮全应用消失）。
**代码完成、未验收**：② 单日页 Properties 区（需带属性的页面）；⑤ 闪卡主 CTA（需 Pro 态，非 Pro 会被重定向到升级页）。
**缺陷撤回**：E 组报告的「侧栏视图切换器选中态丢失」经目视确认**不成立**（文件 chip 有淡紫选中底），其样本疑取自旧包。
**已交付**：⑦ `06-UI截图与改造计划/04-沉浸光感GL3预研.md`（三条实测硬约束 + 三条候选路径 + Settings 试点方案与回归清单）。

**五条方法学教训**（详见计划 §3.16，血泪换来的）：① 测量前先 `read_image` 目视确认目标；② dump 不含 fontSize/fontColor、backgroundColor 部分节点不可靠 → 走像素实测；③ 文本节点边界 ≠ 容器边界；④ PowerShell here-string 是 CRLF，与文件行尾不一致会导致替换静默落空；⑤ 几何测量用 `find_node.py --list`，别用正则硬解 dump JSON。

**工具沉淀**：`uiwalk/tablet/find_node.py` 已支持 `--bounds` / `--list`（几何列行 + 自动算行距）/ `--props`（取 backgroundColor 等属性）/ `--buttons`（注意：dump 的 clickable 字段普遍为空，此法不可靠）；另有 E 组留下的 5 个像素探针脚本（`probe.py` / `profilerows.py` / `darkpx.py` / `edges.py` / `scanrows.py`）。
### 2.0.9 W2：AllPages 行高整改 + dump 几何测量工具 —— 2026-09-25

- **改动**：`PageView.ets` 的 AllPagesView 列表行 `.height(48)` → `.height(32)`；标题留白 `top 24/bottom 16` → `20/12`。
- **实测验收**：行高 **64px = 32.0vp**、相邻行 **gap = 64px = 32vp**（改造前 48vp，计划目标 28–32vp）✓
- **工具产出**：`uiwalk/tablet/find_node.py` 新增 **`--list` 模式**（按几何条件列节点 + 自动算相邻行距）：
  `python find_node.py <dump.json> --list [--min-x N --max-x N --min-w N --min-h N --max-h N]`
  - **教训**：此前三轮我用 PowerShell 正则硬解 dump JSON 测行距，遇嵌套 `attributes` 整段失配、结果恒为 0；改用 `json.load` 递归遍历后一次成功。**测几何一律用 `--list`，不要写正则。**
### 2.0.8 设备自动化锚点表（Ribbon 图标，2026-09-25 实测）

Ribbon 图标为**纯图标**（dump 中无 text、无 accessibility 标签），自动化点击必须用**设备像素坐标**（1vp=2px；截图预览坐标需按 ×1.837 换算，勿直接使用）。实测锚点（Ribbon 列 x ≈ **46**，间距 88px = 44vp）：

| 序号 | y (px) | 入口 |
|---|---|---|
| 0 | 130 | 侧栏开关 |
| 1 | 218 | 快速切换（搜索面板） |
| 2 | 306 | 图谱 |
| 3 | 394 | 白板 |
| 4 | 482 | 闪卡 |
| 5 | 570 | 命令面板 |
| 6 | 658 | 新建（W1 由活动栏迁入） |
| 7 | 746 | Journal（同上） |
| 8 | 834 | **所有页面**（同上） |
| 9 | 922 | PDF（同上） |
| — | 1729 | 主题（浅/深） |
| — | 1817 | **设置** |

**采集方法**（可靠，勿再用推算）：dump 后枚举**所有 x1<100 的节点**并按 y 排序，取 cx≈46 且间距 88px 的那一列即为 Ribbon；**不要加 `clickable:true` 过滤**（该列 clickable 字段为空，加了会得到 0 结果——本会话因此连续两轮点空）。更彻底的方案是给 Ribbon 图标补 `accessibilityText`（兼顾无障碍与可测性）。
### 2.0.7 W2 首项：设置页内容顶对齐 —— 2026-09-25

- **现象**：设置页内容整体垂直居中（D 组像素实测：块中心 = 内容区中心，页头下空 173vp）。
- **根因（两层）**：① 旧修复把 `.align(Alignment.TopStart)` 加在 `Scroll` 上，而 `.align()` 是 **Stack 的属性**，对 Scroll 无效；② 真正的决定因素是**父 Row 的默认 `alignItems = VerticalAlign.Center`**，Scroll 的 `layoutWeight(1)` 只管主轴宽度，交叉轴高度不足即被居中。
- **修复**：`SettingsPage.ets` 父 Row 增加 `.alignItems(VerticalAlign.Top)`（附注释说明旧写法为何无效）。
- **证据**：设备实测内容区最上方元素 **y=909px → y=382px**；`06-UI截图与改造计划/01-应用截图/W2-01-settings-topalign.jpeg`。
- **自动化提示**：Ribbon 图标为纯图标（dump 中无 text / 无 accessibility 标签），自动化点击需按**设备像素坐标**（1vp=2px；截图预览坐标不可直接用）。建议给 Ribbon 图标补 `accessibilityText`，兼顾无障碍与可测性。
### 2.0.6 W1 侧栏改造（方案三）落地 —— 2026-09-25

- **决策**：活动栏（O5 产物，44vp 图标列）不再作为第二条图标列，改造为 Obsidian 式「侧栏视图切换器」，置于面板顶部。
- **改动**：`LeftSidebar.ets` 移除 44vp `Column`；新增 `ViewSwitcher / ViewChip / IconAction / TagListView` 与 `@State sidebarView`（files|search|bookmarks|tags）；`Ribbon.ets` 新增 `items[6..9]`（新建 newFile / Journal / AllPages / Pdf）+ `handle()` 的 `newFile` 分支。
- **效果（设备实测）**：左侧只剩一条图标列；面板 216vp → **约 266vp**；顶部四 chip 齐全；「8 个文件 · 8 页面」与磁盘一致。
- **证据**：`06-UI截图与改造计划/01-应用截图/W1-01-sidebar-files.jpeg`、`W1-02-sidebar-tags.jpeg`。
- **W1 回归（两条链路均通过）**：`verify_o4_editor_modes.sh` 10/10（退出码 0）；`verify_o1_wal.sh` 重跑退出码 0（marker 落盘并强杀生存）。首轮 O1 的退出码 1 经判定为 `uitest uiInput text` 注入抖动（全盘 grep 不到 marker ⇒ 文本未进入页面），**非回归**；脚本已加「注入未上屏即作废（退出码 2）」闸门以防假失败。- **踩坑**：① 首版用 i18n 长标签导致四个 chip 占满面板、挤掉右侧操作图标 → 改两字标签；② 本仓库 ArkTS 文件**行尾不统一**（`Ribbon.ets` 为 CRLF、`LeftSidebar.ets` 为 LF），用脚本做批量替换时必须先归一化行尾，否则替换静默落空（本轮因此漏掉一次 Ribbon 条目插入，已修）。
### 2.0.5 空文件页面静默消失（P1）修复 —— 2026-09-25

- **现象**：内容为空（0 字节或仅 `- ` 空块）的 .md 对应页面**不出现在侧栏文件树**，日志仅 `Empty or unreadable file`。实测受影响：`未命名 4.md`、`未命名 5.md`、当天的 `2026-09-25.md`。
- **风险**：与 O4「整页被清空」缺陷叠加时，一次意外清空 = 页面永久从应用中消失（文件在磁盘但树里没有）。
- **根因**：`DataStore.loadPageFromFile` 对空串一律跳过，而 `FileRepository.readTextSync` 把读取异常也吞成空串 → 无法区分「空文件」与「读失败」。
- **修复**：新增 `FileRepository.hasContent()`（`statSync().size > 0`）；仅确属空文件时按空页面加载，读失败仍跳过。
- **验收**：`Graph loaded. Pages: 8`（修复前 3）；侧栏「8 个文件」与磁盘一致。
- **附带纠正**：此前记录的「侧栏同名页面重复 / 计数不符」经对账为**误判**（最近列表 + 文件树是设计如此，计数亦正确），已在 UI 改造计划 §3.7 撤回。
### 2.0.4 图谱画布空白（P0）修复 —— 2026-09-25 第四轮后

- **现象**：图谱页头部显示「N 节点 · 0 连线」，但画布 2260×1358px 内零图元（`06-UI截图与改造计划/01-应用截图/30-Graph.jpeg`）。
- **根因**：`components/graph/GraphView.ets` 的 `ctx: CanvasRenderingContext2D | undefined` **声明后从未实例化** → `Canvas(this.ctx)` 不渲染 + `drawGraph()` 的 `if (!this.ctx) return;` 恒提前返回；叠加 `canvasWidth/Height` 从未更新（恒 800×600）。
- **修复**：实例化 ctx + Canvas 增加 `onAreaChange` 同步实测尺寸并重建布局。
- **验收**：`30b-Graph-FIXED.jpeg` 正确绘制 3 节点与标签。
- **同类风险提示**：本项目中 Canvas 组件仅图谱与白板两处，**白板渲染正常**（有笔迹与网格），故该缺陷为图谱单点问题，非通用 Canvas 用法问题。
### 2.0.3 O4 缺陷闭环（2026-09-25 第四轮）—— 真正的根因与修复

**根因（一行字段改写缺失）**：`DataStore.replacePageBlocks` 只把解析结果的块 `pageId` 改写为目标页 uuid，**未改写顶层块的 `parentId`**；而 `MarkdownParser` 把顶层块的 `parentId` 设为**解析时新生成的页面 uuid**。`MarkdownExporter.filterTopLevel(blocks, page.uuid)` 以 `parentId === page.uuid` 挑选顶层块 —— 于是**一个顶层块都选不中**，导出结果为空 → 写出 0 字节文件 → 页面被清空（实测块行数 1 → 0）。

**修复**：先保存解析时的 page uuid，再覆盖为目标 uuid，并在循环中同步改写顶层块的 `parentId`（仅当 `parentId === parsedPageUuid`，子块不受影响）。

```ts
const parsedPageUuid = result.page.uuid;   // ← 必须在覆盖之前取
result.page.uuid = pageUuid;
for (...) { blk.pageId = pageUuid; if (blk.parentId === parsedPageUuid) blk.parentId = pageUuid; }
```

**配套加固（均已保留，非临时插桩）**：
- `DataStore.replacePageBlocks` **数据层防误删硬闸**：解析结果为空而页面原本有块 → 拒绝重建（实测空页时页面未被清空）。
- `IntegralEditor`：`toMarkdown()` 补块前缀、空内容闸门、空提取不覆盖非空 markdown、分屏模式回填、`getAllPageBlocks` 兜底。
- 单测新增契约用例：**无 `- ` 前缀 → 解析出 0 块**（这是内容丢失的间接成因，已固化防回归）。

**验收证据**：`verify_o4_editor_modes.sh` **10 通过 / 0 失败，退出码 0**（含「apply 当场未丢内容」与「重启后内容未丢 1 → 1」两条硬断言）；`build_callaite.sh debug` 构建 + 单测门禁退出码 0；全库复查无临时插桩残留。

**过程中的两次误判（记录以免重蹈）**：
1. 曾把缺陷归因于「切换模式重建 RichEditor 导致 markdown 被清空」——方向部分正确（确实会清空编辑器文本），但**不是**写文件的根因。
2. 曾据 `blocks=0` 判定「页面块未进入内存索引（上游缺陷）」——实为**测试选中的页面本身已被前一轮缺陷清空**（文件内容只有 `- ` 空块）。教训：页面级断言前先确认**该页确有非空内容**（脚本已改为用 `grep -c -- '- .'` 排除空块）。

### 2.1 Git 状态（4.2.0 之后有 8 个未提交文件 = O1/O4/O5 的全部产出）

```
?? services/SaveQueue.ets              ← O1 保存队列（新）
?? utils/LivePreviewHelper.ets         ← O4 移植自 Lunius（328 行）
?? utils/MarkdownSegmenter.ets         ← O4 移植（260 行，零依赖）
?? components/outliner/IntegralEditor.ets  ← O4 四模式整页编辑器（新）
 M core/db/DataStore.ets               ← O4 replacePageBlocks（身份保持重建）
 M services/WorkspaceService.ets       ← O1 挂钩 + O4 委托
 M components/page/PageView.ets        ← O4 接线（integralMode 切换）
 M components/sidebar/LeftSidebar.ets  ← O5 调试版（含三色调试边框，勿直接提交）
```
> **✔ 已完成（2026-09-25）**：LeftSidebar 调试插桩已全部移除——1 处 `[O5 调试]` 标记（aboutToAppear 强制展开 + hilog 打点）与 **3 处颜色边框**（`#FF00FF` 活动栏 / `#0000FF` 搜索框 / `#FF0000` 面板）均已清理，全库复查无残留，重建 BUILD SUCCESSFUL 并安装实测双栏正常。
> 另：搜索框原先**没有 onClick（死按钮）**，已按方案文件补上 `AppState.setSearchPanelOpen(true)`（如需回退，删该 3 行即可）。
> ⚠️ 历史教训：只搜 `[O5 调试]` 会漏掉那 3 个彩色边框（它们不含该标记），发布版会带着品红/蓝/红边框出去。

### 2.2 优化任务状态（O1–O9，方案见 `Callaite_优化与升级方案_v2.md`）

| 任务 | 状态 | 说明 |
|---|---|---|
| O1 即时持久化 | **✔ 代码完成** | SaveQueue（markDirty → 静默 1.2s → saveAll 原子落盘）；executeOp/undo/redo 全挂接；PropertyEngine 旁路已有即时落盘（无需挂钩） |
| O1 验收 | **✔ 已通过（2026-09-25 脚本化）** | `verify_o1_wal.sh` v2 一键跑通退出码 0：唯一 marker 落盘至 `未命名 4.md`（磁盘断言）+ 重启后页面内可见（界面断言）。**无 onBackground 落盘 → force-stop → 重启数据完好**，O1 闭环 |
| O2 THREAD_BLOCK | **✔ 已闭环** | **根因 = 模拟器缺陷**（express GPU 通路 + VSync 时间戳溢出 2³²ms），非应用代码；平板 13 轮压测未复现；已向华为提单（见 `华为缺陷上报_附件/`）。**新增第二缺陷**：平板实例 `foundation` 系统进程 SIGILL 崩溃（UBSan sub-overflow），见下方「本轮新增发现」 |
| O4 编辑器四模式 | **✔ 已完成并设备验收（2026-09-25）** | 整页 RichEditor + Live/Source/Preview/Split + 身份保持重建（replacePageBlocks）。`verify_o4_editor_modes.sh` **10 通过 / 0 失败，退出码 0**：入口 ✔ 四模式按钮齐全 ✔ 四模式切换渲染 ✔ 应用并重建 ✔ 强杀重启后内容保全（块行数 1 → 1）✔。修复的 P0 根因见 2.0.3 |
| O5 活动栏双栏 | **✔ 已完成（2026-09-25）** | 三色调试插桩已全部移除（含 3 处颜色边框，非仅 `[O5 调试]` 标记）；重建安装实测双栏结构渲染正常。**排查结论：原报告「资源管理器面板渲染空白」系 API 24 模拟器时期现象，在 API 26 平板上未复现**（搜索框/收藏夹/最近/PageTree 全部正常渲染，有数据后树正常显示页面）。**遗留设计问题：Ribbon 与活动栏功能重复**（图谱/白板/闪卡/设置两条栏都有，白占 36vp），待决策合并方案 |
| O6 沉浸光感 | ✘ 未启动 | GL-2 主壳 Navigation 迁移是前置（注意：上轮实机曾布局回归，须按页分步） |
| O3/O7–O9 | 未启动 | 按方案 v2.0 优先级矩阵排期 |

### 2.3 实测通过的项
- 全量构建 ✔（debug 全量 ~10s）· 沉浸式布局/系统栏/深浅色主题（平板实机 ✔）· 新标签页/文件树/仓库切换器 UI（截图 ✔）· 浅色主题像素级对齐 Obsidian ✔

## 三、功能完成度与 Obsidian 对标（摘要）

综合完成度 **≈78%**，UI 还原度 **≈82%**（结构层 90% / 细节层 75%）。完整对照表见 `Callaite_八问深度解析报告.md`。要点：
- ✔ 已达 85–90%：大纲/双链/文件树/标签页/图谱/查询（超 Obsidian）/任务/闪卡 FSRS/插件/模板/主题
- ◐ 60–80%：编辑器 Live Preview（v1 打字期格式化；**Lunius 已验证四模式可行并已移植**）/ 白板（核心 ✔，形态未对齐 Obsidian——用户已排除该项复刻）/ PDF / 同步
- ✘ 未实现：碰一碰互传（全库无 NFC/ShareKit 代码）；独立设置窗口；多仓库管理

## 四、进行中/待办工作（按优先级）

### P0（发布阻断）
1. ~~**O1 验收执行**~~ **✔ 已完成 2026-09-25**：`verify_o1_wal.sh` v2 一键跑通，退出码 0（磁盘断言 + 界面断言双通过）
2. ~~**O5 调试截图 + 修复 + 移除插桩**~~ **✔ 已完成 2026-09-25**：双栏渲染正常（原空白为 API24 时期现象），插桩已清除；**遗留设计决策**：Ribbon 与活动栏功能重复，需定合并方案（见 2.2）
3. **O4 设备验证**：「所有页面 → 页面 → 整页编辑」验证四模式 + 「应用并重建大纲」+ 强杀后数据完好
4. **签名 + bundleName**（release 无证书、包名占位）

### P1
5. O4 编辑器完善：暗色主题适配（LivePreviewHelper 硬编码浅色）、日志页接入整页编辑、跨页块引用失效方案
6. 沉浸光感 GL-2~GL-5（主壳 Navigation 迁移，**每页分步实机回归**——上轮曾布局回归）
7. 传输四件套真机验证（需 AGC + 华为账号 + 双设备）
8. O8 碰一碰互传立项（NFC TagSession / Share Kit）

### P2
9. O10 长列表 LazyForEach 试点（搜索面板先行）→ 推广文件树/日志流
10. O12 大文件拆分（Whiteboard 1157 行手势/绘制续拆）+ 36 处 TODO 清零
11. O14 同步冲突副本 + NativeBridge 命令白名单

## 五、关键技术决策与陷阱记录（高价值，务必阅读）

1. **模拟器 THREAD_BLOCK_6S = 模拟器缺陷，非应用问题**：express GPU ioctl 失败 → VSync 时间戳溢出 2³²ms → 主线程永久阻塞。手机实例（Pura 90 Pro Max）复现 10 次；平板实例 13 轮压测 0 复现。已提单华为。**不要为此改应用代码**。
2. **force-stop 跳过生命周期丢数据**：项目曾有"未保存日志页丢失"实证——O1 已修复（强杀丢失窗口 ≤1.2s），验收前勿再归因于应用。
3. **沙箱快照回滚**：本会话 AI 执行环境中，对会话内新建目录（如 `.git/refs/remotes/`）的写入会被沙箱回滚（fetch/update-ref 报成功但不落盘）。git 元数据操作须脱离沙箱执行，并用**跨命令探针**验证。
4. **模板字符串反斜杠陷阱**：WebEditorHTML 是 ArkTS 模板字面量——注入 JS 中的 `\*`/`\n` 会被模板转义吃掉（`/**` 甚至变成块注释）。**模板区内反斜杠必须全部翻倍**。
5. **ArkTS 高频约束**：@Builder 内禁局部变量声明（用私有方法替代）；自定义组件不可链式 `.width()`；struct build 单根节点；MaterialRole 枚举值是 MODAL/TRANSIENT 等（无 DIALOG）；`Color.Magenta` 不存在（用十六进制）。
6. **编译器与 IDE 检查容错度不同**：hvigor 曾容忍 @Builder 签名后的非法链式（IDE 报 80 错）。"构建通过"不能证明"IDE 无错"，反之 IDE 报错需先找单点损坏+级联放大。
7. **大块 UI 替换必须核对旧块功能元素清单**：曾因此误删导航区（已修复）。
8. **批量改代码用词边界匹配**：`Button(` 会误命中 `TypeButton(`（曾造成 @Builder 签名损坏）。
9. **Pen Kit 是 HSP 硬依赖**：无 HMS 设备上静态 import 即 SIGABRT——已隔离在启动路径外（PenCanvasPage），接入需 product flavor/HSP 模块。
10. **SDK 26 兼容性**：compatibleSdkVersion 当前 26.0.0（仅 API 26+ 设备可装）；覆盖 API 24 需改 `"6.1.1(24)"`（格式规则见 README 头部）。setWindowLayoutFullScreen 在 PC/2in1 禁用（已分支处理）。

## 六、工具链与脚本索引

| 工具 | 位置 | 用途 |
|---|---|---|
| 构建脚本 | `Callaite-工作文档/03-构建与设备脚本/build_callaite.sh` | `bash build_callaite.sh debug`；日志入 `uiwalk/build_*.log`（**已从根目录移入，旧根路径失效**） |
| O1 验收 | `Callaite-工作文档/03-构建与设备脚本/verify_o1_wal.sh` | 强杀生存测试（一键） |
| UI 走查 | `uiwalk/walk.sh` + `official_ux_audit.py` + `verify/` | 截图/布局 dump/官方阈值审计 |
| 部署 | `hdc -t 127.0.0.1:5555 install <hap>` + `aa start -a EntryAbility -b com.example.callaite` | 平板实例 MatePad Pro 13 |
| 静态检查 | `code-linter.json5` 已配置 | 目标 0 error（尚未接入构建门禁） |

**模拟器说明**：手机实例（Pura 90 Pro Max，API 26）存在 GPU 缺陷已提单——**验证工作请优先使用平板实例（MatePad Pro 13，API 26 / HarmonyOS 7.0.0(26.0.0)，tablet_x86 镜像）**；启动后约 60–90s 稳定窗口，截图/dump 动作要快。
> ⚠️ **两项更正**（2026-09-25 复核）：
> 1. 平板实例**不是 API 24，而是 API 26**——依据 `emulator -list -details` 的 `os.osVersion = HarmonyOS 7.0.0(26.0.0)`；且应用 `compatibleSdkVersion = 26.0.0`，若平板真是 API 24 则根本无法安装。
> 2. 平板实例**无手机那种冻结缺陷**：13 轮前台切换压测（宿主空闲内存最低压到 288 MB，比手机崩溃时的 135–600 MB 更严苛）应用零崩溃、faultlog 为空。但它另有独立故障：2026-09-24 23:54–09-25 00:33 会话出现 **861 次 `QProcess: CreateFile failed`（Windows 命名管道耗尽）**，会话无法正常退出、快照被判失效删除，下次冷启动——详见 `华为缺陷上报_附件/05_平板实测证据/`。

## 七、文档与证据索引（09-25 已整理）

```
F://DevEcoStudioProjects//
├── 华为缺陷上报_附件\          THREAD_BLOCK 提单全套（正文/冻结日志/复现证据/诊断报告/平板压测）
│   ├── 华为缺陷上报_正文.md      可直接复制到工单系统
│   ├── 04_诊断报告\API26模拟器闪退诊断报告.md   根因分析（GPU 通路 + VSync 溢出）
│   └── 05_平板实测证据\         13 轮压测未复现 + 命名管道耗尽 + GPU 报错对比
├── Callaite-工作文档\          全部历史文档（README.md 为索引）
│   ├── 01-需求与方案\          深度研究/H7升级评估/优化方案 v1+v2/八问报告
│   │   └── Callaite_LeftSidebar活动栏方案.ets.txt   ← O5 双栏完整代码（含调试指引，已从根目录移入）
│   ├── 02-验证与走查报告\      验证/UI 走查/仓库恢复
│   ├── 03-构建与设备脚本\      build_callaite.sh / verify_o1_wal.sh / verify_device.sh
│   ├── 04-模拟器闪退诊断\      freeze logs + 环境快照
│   └── 05-测试截图\
└── Callaite\                    项目本体
```

## 八、交接后优先级行动清单

```
第 1 步  模拟器恢复后：bash verify_o1_wal.sh          → O1 验收闭环（10 分钟）
第 2 步  启动截图（三色边框）→ O5 诊断 → 修复 → 移除调试插桩 → 提交 8 个未提交文件
第 3 步  O4 设备验证（四模式 + 重建链路 + 强杀）
第 4 步  签名 + AGC 配置（用户操作）→ 传输四件套真机验证
第 5 步  沉浸光感 GL-2 主壳迁移（每页分步回归）
第 6 步  发布物料 + 提审
```

## 九、风险与限制声明

- O4 整页编辑器：跨页 `((块uuid))` 引用因重建失效（已知限制）；LivePreviewHelper 硬编码浅色（暗色待适配）；日志页未接入
- 传输类功能（流转/协同/云同步/IAP）均为代码完成、系统级未验证（依赖外部条件）
- 本文档未覆盖 Obsidian 全部长尾功能（白动化任务/图谱过滤等以 README 为准）
- 模拟器 GPU 缺陷已提单华为，等待官方修复期间以平板实例为验证主力

---
*交接人：AI 开发助手 · 数据截止 2026-09-25 11:08 · 全部结论可溯源至 `Callaite-工作文档/` 与 `.workbuddy/memory/`（09-19/09-24/09-25 三日日志）*
