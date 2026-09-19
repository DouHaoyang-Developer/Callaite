# Callaite

**Logseq 风格的鸿蒙知识管理应用** — 基于 HarmonyOS ArkTS 构建，完整复刻 Logseq 的大纲编辑、双向链接、知识图谱等核心体验，并对齐 Obsidian 的桌面多窗格与移动端编辑工具条交互。

> **SDK**: targetSdkVersion 26.0.0（HarmonyOS 7）· **语言**: ArkTS · **模型**: Stage Model  
> **规模**: 134 源文件 · ~33,300 行代码 · 0 第三方运行时依赖 · 当前版本 4.1.5 Beta  
> **架构**: MVVM + Service + Plugin + Query 四层架构

> ⚠️ **兼容性说明**：`compatibleSdkVersion` 当前为 `26.0.0`，仅 API 26+ 设备可安装（实测 API 24 模拟器安装报 `9568297`）。若需覆盖 API 24 设备，将 `compatibleSdkVersion` 改为 `"6.1.1(24)"`——注意 SDK 格式规则：API 10–25 必须写 `"X.Y.Z(NN)"`，API 26+ 必须写 `"26.0.0"`，混用会报 `00306042 Specification Limit Violation`。

---

## 目录

- [快速开始](#快速开始)
- [功能特性](#功能特性)
- [架构设计](#架构设计)
- [数据模型](#数据模型)
- [Markdown 文件格式](#markdown-文件格式)
- [核心引擎](#核心引擎)
- [编辑器与键盘交互](#编辑器与键盘交互)
- [查询系统](#查询系统)
- [插件框架](#插件框架)
- [鸿蒙特性](#鸿蒙特性)
- [扩展功能](#扩展功能)
- [UI 设计规范](#ui-设计规范)
- [启动链](#启动链)
- [技术选型](#技术选型)
- [ArkTS 编译约束](#arkts-编译约束)
- [项目目录](#项目目录)
- [构建说明](#构建说明)

---

## 快速开始

```bash
# 1. 用 DevEco Studio 打开 Callaite/ 目录
# 2. Sync Project → Build → Run
# 3. 首次启动进入 4 步引导（欢迎 → 创建 Graph → 快捷键 → 开始使用）
```

启动后进入日志流首页（最近 7 天按日期倒序，滚动到底自动追加），点击日期标题进入单日日志页，点击 Block 开始编辑。

| 快捷键 | 功能 |
|--------|------|
| `Enter` | 创建新 Block |
| `Shift+Enter` | 块内换行 |
| `Tab` | 缩进 |
| `Shift+Tab` | 反缩进 |
| `Backspace`（空行） | 删除并合并 |
| `Alt+↑` / `Alt+↓` | 上下移动 Block |
| `Ctrl+K` | 全局搜索 |

---

## 功能特性

### 1. 大纲编辑器

Callaite 的核心是 Logseq 风格的大纲树编辑器。每个 Block 是一个树节点，缩进表示父子层级。

**编辑模式**
- **阅读模式**：Block 内容以格式化文本显示，`[[引用]]` 显示为蓝色链接
- **编辑模式**：点击 Block 进入 WebView contenteditable 编辑器，支持全键盘操作
- **自动保存**：输入防抖 400ms 自动落库（只保存、不退出编辑态、不触发 UI 刷新），失焦时保存并持久化到 .md 文件

**Block 操作**
- 圆点（●）点击：展开操作工具栏 / 折叠子 Block
- 任务标记（TODO/DOING/DONE）：点击循环切换，彩色标签
- 缩进/反缩进：Tab / Shift+Tab 或操作按钮
- 上移/下移：Alt+↑↓ 或操作按钮
- 删除：操作栏 × 按钮
- 折叠/展开：点击 chevron 图标或圆点隐藏/显示子 Block
- 拖拽排序：长按 500ms 激活拖拽 + 振动反馈 + PanGesture 排序
- 多选批量：Shift+点击 进入多选 + 批量缩进/删除/移动
- 页内搜索：Ctrl+F 触发 FindInPage + 高亮匹配 + 上/下导航
- 智能粘贴：粘贴 Markdown 自动按 `- ` 前缀拆分为多个 Block，保留缩进层级

**行内格式渲染**

| 语法 | 效果 |
|------|------|
| `**粗体**` | **粗体** |
| `*斜体*` | *斜体* |
| `~~删除线~~` | ~~删除线~~ |
| `==高亮==` | 黄色背景高亮 |
| `` `代码` `` | 等宽字体代码 |
| `[文本](url)` | 可点击链接（系统浏览器打开） |
| `[[页面名]]` | 蓝色可点击页面链接 |
| `((uuid))` | 蓝色可点击 Block 引用 |
| `#标签` | 绿色可点击标签（点击打开搜索面板并按标签过滤） |
| `![[页面]]` | 页面嵌入 |
| `!((uuid))` | Block 嵌入（内联预览） |
| `$E=mc^2$` | 行内 KaTeX 公式 |
| `$$\sum x$$` | 块级 KaTeX 公式 |
| `\| a \| b \|`（多行） | 可编辑 Markdown 表格（点击单元格编辑） |

**Slash 命令面板**

输入 `/` 触发，支持 10 种命令：

| 命令 | 效果 |
|------|------|
| `/TODO` | 标记为待办 |
| `/DOING` | 标记为进行中 |
| `/DONE` | 标记为已完成 |
| `/LATER` | 标记为稍后 |
| `/NOW` | 标记为现在 |
| `/Template` | 插入模板 |
| `/Link` | 插入 `[[]]` |
| `/Embed` | 插入 `!(())` |
| `/Date Picker` | 插入今天日期 |
| `/Query` | 插入查询块 |

**自动补全**

- `[[` → 弹出页面搜索列表，选择后插入 `[[页面名]]`
- `((` → 弹出 Block UUID 列表，选择后插入 `((uuid))`
- `#` → 弹出标签列表，选择后插入 `#标签`

### 2. 双向链接

**页面引用 `[[page]]`**
- 创建指向目标页面的引用链接
- 目标页面自动显示在反向链接面板中
- 引用传导更新：页面重命名时自动更新所有 `[[旧名]]` → `[[新名]]`

**Block 引用 `((uuid))`**
- 创建指向特定 Block 的引用链接
- 嵌入 Block 显示内联预览卡片

**页面嵌入 `![[page]]`**
- 显示目标页面顶层 Block 的预览列表，可点击标题跳转

**反向链接面板（右侧栏）**
- 实时显示哪些页面引用了当前页面
- 显示引用 Block 的上下文内容
- 筛选：全部 / 页面引用 / Block 引用

### 3. 页面系统

**日志页**
- 每日自动创建（存储名 yyyy-MM-dd，参与文件系统与查询）
- 显示标题本地化（`JournalService.formatJournalTitle`）：中文「2026年8月20日 星期四」/ 英文「Aug 20th, 2026」，仅显示用，存储名不变
- Header 导航箭头支持前一天/后一天快速跳转
- 日志页顶部显示计划/截止任务面板

**页面属性**
- 页面级 key:: value 属性（tags / alias / created-at / updated-at）
- 右侧栏内联编辑器：输入 `key:: value` 自动添加
- 属性删除：点击 × 按钮
- PageView 可折叠属性展示区

**命名空间**
- 支持 `project/sub-page` 格式
- 左侧栏按命名空间分组显示（文件夹图标 + 命名空间标题）

**收藏夹 & 最近页面**
- 左侧栏 Pin 图标区 / Refresh 图标区
- 自动记录最近访问页面（最多 20 个）

### 4. 知识图谱

**力导向布局**
- 斥力系数 5000 / 引力系数 0.005 / 阻尼 0.85 / 向心力 → 中心
- 100 次迭代收敛
- 节点：页面（蓝色） / 日志页（绿色）
- 连线：`[[引用]]` 关系

**交互**
- 拖拽平移
- 点击节点跳转到对应页面

### 5. 查询系统

**三层查询架构**

| 层级 | 文件 | 能力 |
|------|------|------|
| QueryEngine | `core/db/QueryEngine.ets` | 多条件筛选（marker/priority/date/tag/page/hasProperty/contentContains/notMarker/notTags） |
| DatalogEngine | `core/db/DatalogEngine.ets` | S-表达式解析 + 逻辑运算（and/or/not/between/task/priority/tag） |
| LogicEngine | `core/db/LogicEngine.ets` | 递归规则引擎（半朴素评估算法） |

**内联查询**：Block 内容中的 `#+BEGIN_QUERY ... #+END_QUERY`（Datalog 表达式）与 `{{query ...}}`（简单标记/tag/property）会就地渲染结果列表，点击结果项跳转到对应页面。

**LogicEngine 支持的递归规则**

```
事实: (parent BlockA BlockB), (parent BlockB BlockC)
规则: (ancestor ?x ?y) :- (parent ?x ?y)
      (ancestor ?x ?y) :- (parent ?x ?z), (ancestor ?z ?y)
查询: (ancestor BlockA ?y) → [{?y: BlockB}, {?y: BlockC}]
```

- `ancestor` — Block 层级祖先（传递闭包）
- `descendant` — Block 后代
- `connected` — 同标签 Block 关联

**查询构建器 UI**
- 状态筛选（TODO/DOING/DONE）
- 优先级筛选（A/B/C）
- 日期范围筛选
- 标签筛选
- 结果列表可点击导航到对应页面

### 6. 任务管理

**任务标记循环**：点击 marker 标签 → TODO → DOING → DONE → 清除 → ...

**计划/截止面板**
- 日志页顶部自动显示
- 使用 QueryEngine 跨页面扫描
- 计划任务：SCHEDULED 日期在范围内的 TODO/DOING Block
- 截止任务：DEADLINE 日期在范围内的 Block

### 7. 闪卡系统

**创建闪卡**：在 Block 内容中包含 `#card` 标签或 block.tags 包含 'card'

**Cloze 填空**：`{{cloze 隐藏答案}}` 格式，复习时点击翻转显示

**FSRS-4.5 算法**（Free Spaced Repetition Scheduler）：

基于稳定性（Stability）/ 难度（Difficulty）/ 可提取性（Retrievability）三大核心变量的现代间隔重复算法，取代传统 SM-2。

| 评分 | 含义 | 调度逻辑 |
|------|------|---------|
| Again (1) | 完全遗忘 | 稳定性重置， lapse+1，进入重新学习 |
| Hard (2) | 勉强回忆 | 稳定性增长 ×(1 + W[8]×难度惩罚) |
| Good (3) | 正常回忆 | 稳定性增长 ×(1 + W[9]×可提取性) |
| Easy (4) | 轻松回忆 | 稳定性增长 ×(1 + W[10]×易度奖励) |

- 19 个参数权重 `W[0..18]`，默认值适配通用场景
- 难度向 5.0 回归（meanReversion），避免极端值
- 可提取性 R = exp(-elapsedDays/stability)
- 调度数据持久化到 Block 属性 `fsrs_*`

**复习界面**：顶部进度条 + 翻卡 + 4 按钮评分 + 完成后统计摘要（已复习/平均难度/下次到期）

### 8. 模板系统

| 变量 | 展开 |
|------|------|
| `{{date}}` | 今天日期 yyyy-MM-dd |
| `{{time}}` | 当前时间 HH:mm |
| `{{title}}` | 当前页面标题 |
| `{{date:+Nd}}` | N 天后 |
| `{{date:-Nd}}` | N 天前 |

**内置模板**
- 日记：今日计划 + 回顾段落
- 会议记录：参会人 + 议题 + 结论 + 待办
- 项目页面：tags::project + status::active
- 周回顾：{{date:-7d}} ~ {{date}}

### 9. 白板（Whiteboard）

Logseq Whiteboards 风格的无限画布白板，支持形状/连线/手写笔/页面引用。
入口：左侧栏导航「白板」。

**画布与手势**
- 无限平移（PanGesture）+ 缩放（PinchGesture）
- 6 种工具：选择 / 矩形 / 椭圆 / 菱形 / 文本 / 连线 / 手写笔
- 撤销/重做栈（50 层，含 shapes / connectors / strokes 快照）
- `.canvas` JSON 文件持久化（JSON Canvas 1.0 规范）

### 10. PDF 阅读与标注（P2）

入口：左侧栏导航「PDF」，列出知识库目录下的 `.pdf` 文件。
- WebView + pdf.js 渲染，支持上一页/下一页
- 文本层选中文字后自动在当前页追加 `PDF 标注 (文件名:页号)` Block
- 选中文本即时高亮，并持久化到 `<pdf>.highlights.json`，重新打开后按页恢复高亮

**形状与连线**
- WbShape：矩形/椭圆/菱形/文本 + 命中测试 + 拖动/缩放
- WbConnector：贝塞尔曲线连线 + 箭头 + 自动跟随端点
- WbPageRef：拖入 Logseq 页面 + 双击跳转

**PenKit 手写笔**（详见 [鸿蒙特性](#鸿蒙特性)）
- 4 种笔刷：钢笔 / 铅笔 / 马克笔 / 橡皮擦
- 压感映射 + 手掌误触过滤 + 笔触平滑

### 11. 桌面分屏（内容区左右双窗格）

平板 / 2in1 桌面形态下，内容区可开启左右分屏（对齐 Obsidian 桌面 split）：

- **入口**：标签栏右侧分屏开关（激活态高亮），开启后标签栏同步出现副窗格页面选择器（内置路由 + 全部页面，`Select` 下拉）
- **双窗格**：主窗格跟随全局 `currentPage`，副窗格经 `PageView.pageOverride` 独立渲染，复用同一套渲染与数据逻辑
- **可拖拽分隔条**（`SplitDivider`）：PanGesture 调整左窗格占比（0.2–0.8 钳制）、单击复位 50%、拖拽态主题色高亮；比例经 `splitAreaWidth()` 把像素位移换算为权重
- **独立焦点域**：两窗格 Scroll 的 `id` 按窗格区分，仅主窗格抢焦点，快捷键路由不串扰
- 紧凑形态（手机）自动关闭分屏，TabBar 不渲染

### 12. 文件树工具行（左侧栏）

对齐 Obsidian 左栏第二行工具条，4 个按钮均绑定真实动作（无空壳按钮）：

| 图标 | 功能 | 行为 |
|------|------|------|
| `file-plus` | 新建笔记 | `WorkspaceService.createPage()` + 自动进入内联重命名 |
| `folder` | 新建命名空间页面 | 创建 `新文件夹/未命名`（页面名含 `/` 即构成层级），文件树生成可折叠分组 |
| `arrows-up-down` | 排序切换 | 名称升/降序（`@StorageLink` 持久），同时作用于命名空间分组与页面列表 |
| `arrows-minimize` | 全部折叠/展开 | 收藏夹 / 最近 / 所有页面三组折叠状态一键切换 |

### 13. 键盘上方 Markdown 工具行（移动端）

手机编辑态（存在获焦 Block）时，底部胶囊栏上方浮出玻璃工具条，复刻 Obsidian iOS 编辑器工具行：

- **9 个按钮**：撤销 / 重做 / 页面双链 `[[]]` / 插入文件 / `#` 标签 / 链接 / `H` 标题（循环 h1→h2→h3→正文）/ `B` 加粗 / 收起键盘
- 「H」「B」按参考设计使用**字母字形**（`Text`）而非近义图标
- **命令通道**：按钮写入 AppStorage（`callaite_editorCommand`，格式 `cmd|seq`，序号保证连点同一按钮也能触发），仅**当前获焦块**的 WebEditor 响应，经 `runJavaScript` 在编辑器内部以 `document.execCommand` 执行（contenteditable 原生复用选区），执行后派发 `input` 事件复用 400ms 防抖持久化链路
- 为什么不直接改 store：块编辑态由 WebEditor（contenteditable WebView）承载，仅创建时读取 `initialContent`，直接写库不会反映到正在编辑的编辑器

---

## 架构设计

### 分层架构

```
┌─────────────────────────────────────────┐
│ Components（ArkUI @Component struct）   │  ← UI 层
│   BlockView / PageView / Sidebar / ...  │
├─────────────────────────────────────────┤
│ Services（单例 static class）           │  ← 业务逻辑层
│   Workspace / Editor / File / ...       │
├─────────────────────────────────────────┤
│ Plugins（CallaitePlugin + PluginAPI）     │  ← 扩展层
│   BookmarkPlugin / TodoExportPlugin     │
├─────────────────────────────────────────┤
│ Core Engine                             │  ← 引擎层
│   BlockTree / Outliner / Parser / DB    │
├─────────────────────────────────────────┤
│ Query Layer                             │  ← 查询层
│   QueryEngine / DatalogEngine / Logic   │
└─────────────────────────────────────────┘
```

### 数据流

```
用户输入 → WebEditor (WebView contenteditable)
  → NativeBridge.onAction('save', content)
    → EditorService.updateBlockContent(uuid, content)
      → WorkspaceService.executeOp({ type: 'update-block', ... })
        → OutlinerEngine.dispatch(op)
          → BlockTree.updateBlock(uuid, content)
          → DataStore.savePage(pageId)
            → MarkdownExporter.export(page, blocks)
              → FileRepository.writeTextSync(path, markdown)
```

### 状态管理

| 机制 | 用途 |
|------|------|
| `@StorageLink` | 跨组件共享状态（当前页面、侧栏开关、收藏夹、主题） |
| `@State` | 组件内局部状态（编辑模式、焦点、数据列表） |
| `@Prop` | 父→子单向数据流（blockUuid、depth） |
| `AppStorage` | 全局持久化键值（config、语言、主题模式） |

---

## 数据模型

### Block

```typescript
interface BlockData {
  uuid: string;              // UUID v4
  content: string;           // Block 文本（不含 marker/priority 前缀）
  format: FileFormat;        // 'markdown' | 'org'
  pageId: string;            // 所属页面 UUID
  parentId: string;          // 父 Block UUID（顶层 = pageId）
  leftId: string;            // 左侧兄弟 UUID（链表排序）
  level: number;             // 缩进层级（0 = 顶层）
  marker: string;            // '' | TODO | DOING | DONE | LATER | NOW | CANCELLED
  priority: string;          // '' | A | B | C
  scheduled: string;         // yyyy-MM-dd
  deadline: string;          // yyyy-MM-dd
  properties: PropertyBag;   // 自定义属性 key:: value
  refs: string[];            // [[页面引用]] 列表
  blockRefs: string[];       // ((Block引用)) 列表
  tags: string[];            // #标签 列表
  collapsed: boolean;        // 是否折叠
  createdAt: number;         // 创建时间戳
  updatedAt: number;         // 更新时间戳
}
```

### Page

```typescript
interface PageData {
  uuid: string;
  name: string;              // 规范化名称（小写，URL 安全）
  originalName: string;      // 原始显示名称
  namespace: string;         // project/sub → namespace = "project"
  properties: PropertyBag;   // 页面属性
  journalDay: string;        // yyyy-MM-dd（日志页）/ 空（普通页）
  format: FileFormat;
  filePath: string;          // 相对路径，如 "My Page.md"
  aliases: string[];         // 别名列表
  tags: string[];            // 聚合标签
  createdAt: number;
  updatedAt: number;
}
```

### PropertyBag

由于 ArkTS 禁止 `Record<string, string>` 和 `[key: string]` 索引签名，属性使用专用包装类：

```typescript
class PropertyBag {
  set(key: string, value: string): void;
  get(key: string): string;
  has(key: string): boolean;
  remove(key: string): void;
  keys(): string[];
  forEach(callback: (key: string, value: string) => void): void;
  toJSON(): string;          // 序列化
  static fromJSON(json: string): PropertyBag;  // 反序列化
}
```

---

## Markdown 文件格式

Callaite 严格兼容 Logseq 的 .md 文件格式：

```markdown
---
title:: My Page
tags:: project, important
---
- TODO [#A] 完成需求分析 [[项目文档]]
  SCHEDULED: <2026-08-03>
  - 子任务拆解
    - 前端接口对接
- DOING 编写技术方案
  DEADLINE: <2026-08-10>
```

**解析规则**：
- 前端元数据（`---` 包裹或首行 `key:: value`）→ 页面属性
- `- ` 前缀 → Block 分隔符
- 每 2 空格 = 1 级缩进
- `TODO/DOING/DONE/LATER/NOW` → 任务标记
- `[#A]/[#B]/[#C]` → 优先级
- `SCHEDULED: <yyyy-MM-dd>` / `DEADLINE: <yyyy-MM-dd>` → 日期属性
- `[[page]]` / `((uuid))` / `#tag` → 引用和标签

---

## 核心引擎

### BlockTree（453 行）

内存 Block 树数据结构：

- `blockMap: Map<uuid, BlockData>` — O(1) UUID 查找
- `childrenMap: Map<parentId, uuid[]>` — 父子关系索引
- `recycleBin: Map<uuid, BlockData>` — 撤销恢复暂存
- leftId 链表排序 — 维护兄弟 Block 顺序
- `sortAllChildren()` — 按 leftId 链自动排序
- 循环引用检测 — 移动前验证目标不是自身后代

### OutlinerEngine（359 行）

操作引擎，支持 17 种操作类型：

- Block 操作：insert-block / delete-block / delete-blocks / move-block / move-blocks / update-block
- 结构操作：indent / outdent
- 任务操作：set-marker / set-priority / set-scheduled / set-deadline
- 属性操作：add-property / remove-property
- UI 操作：collapse
- 页面操作：new-page / rename-page / delete-page
- 撤销/重做：50 层操作栈

### MarkdownParser（420 行）

Logseq .md → Block 树解析器：

1. 按行分割文本
2. 分离页面元数据（frontmatter 或首行属性）
3. 逐行解析 Block：计算缩进层级 → 提取 marker/priority → 提取内容
4. 处理多行 Block 内容
5. 提取内联引用（`[[page]]`、`((uuid))`、`#tag`）
6. 维护 parentId/leftId 关系链

### DataStore（~290 行）

中央协调器：

- 持有 BlockTree + IndexStore + FileRepository
- `loadGraph(root)` — 加载所有 .md 文件到内存
- `createPage(name)` — 创建新页面
- `deletePage(uuid)` — 删除页面（含文件）
- `renamePage(uuid, newName)` — 重命名 + 引用传导更新
- `savePage(uuid)` — MarkdownExporter 导出 → 文件写入

### IndexStore（263 行）

三种倒排索引：

| 索引 | 结构 | 用途 |
|------|------|------|
| 页面名索引 | `Map<lowerName, pageUuid>` | 页面快速查找 |
| 标签索引 | `Map<tag, pageUuid[]>` | 按标签筛选页面 |
| 反向链接索引 | `Map<targetName, BacklinkEntry[]>` | 反向链接面板 |

---

## 编辑器与键盘交互

Callaite 采用 **WebView contenteditable** 方案实现完整键盘支持。每个 Block 编辑时实例化一个微型 WebView 编辑器。

**加载方式（4.1.1）**：编辑器 HTML 写入应用沙箱缓存目录后以 `file://` URL 加载。Web 组件的 `src` 只接受 URL / `$rawfile`，HTML 源码串直接传 `src` 或 `loadData` 均实测渲染空白，沙箱文件是唯一可靠方案。

### JS ↔ ArkTS 通信

```
ArkTS WebEditor 组件
  └── WebView（contenteditable div）
        ├── keydown handler → Enter/Tab/Backspace/Arrow
        ├── blur handler → 自动保存
        └── NativeBridge 回调
              ├── onAction('newBlock', content)  → EditorService
              ├── onAction('indent', content)     → EditorService
              ├── onAction('save', content)       → EditorService + 持久化
              └── onAction('focusPrev/Next')      → 父组件焦点切换
```

### 键盘操作映射

| 按键 | JS 处理 | ArkTS 响应 |
|------|---------|-----------|
| Enter | `e.preventDefault()` + 分割光标前后内容 | `nativeProxy.onAction('newBlock', after)` → `EditorService.createBlockBelow()` |
| Shift+Enter | 默认行为（插入 \n） | — |
| Tab | `e.preventDefault()` | `nativeProxy.onAction('indent', content)` → `EditorService.indentBlock()` |
| Backspace（空行） | `nativeProxy.onAction('delete')` | `EditorService.deleteEmptyBlock()` |
| ArrowUp（首行） | `nativeProxy.onAction('focusPrev')` | 父组件激活上一个 Block |
| ArrowDown（末行） | `nativeProxy.onAction('focusNext')` | 父组件激活下一个 Block |

---

## 查询系统

### QueryEngine

```typescript
const opts: QueryOptions = {
  markers: ['TODO', 'DOING'],
  priority: 'A',
  scheduledAfter: '2026-08-01',
  tags: ['project'],
  limit: 20
};
const results = QueryEngine.query(store, opts);
```

### DatalogEngine

```typescript
// S-表达式查询
const results = DatalogEngine.execute(
  '(and (task TODO DOING) (property tags "project") (between scheduled -7d +7d))',
  store
);
```

### LogicEngine（递归规则）

```typescript
const engine = new LogicEngine();
engine.addFact('parent', 'blockA', 'blockB');
engine.addFact('parent', 'blockB', 'blockC');
engine.addRule(['ancestor', '?x', '?y'], [['parent', '?x', '?y']]);
engine.addRule(['ancestor', '?x', '?y'], [['parent', '?x', '?z'], ['ancestor', '?z', '?y']]);

const results = engine.query(['ancestor', 'blockA', '?y']);
// → [{?y: 'blockB'}, {?y: 'blockC'}]
```

---

## 插件框架

### 架构

```
PluginManager（单例）
  ├── register(plugin)        // 注册插件实例
  ├── initAllPlugins()        // 发现所有注册插件并实例化
  ├── enable(id) / disable(id)
  ├── isEnabled(id)
  └── plugin_state.json       // 启停状态持久化
```

### 开发插件

```typescript
class MyPlugin extends CallaitePlugin {
  get id(): string { return 'my-plugin'; }
  get name(): string { return 'My Plugin'; }
  get version(): string { return '1.0.0'; }
  get description(): string { return 'This is my plugin'; }

  onEnable(): void {
    PluginAPI.insertTodayBlock('📌 Hello from plugin!', 'TODO');
  }
}

// 注册
PluginManager.getInstance().register(new MyPlugin());
```

### PluginAPI 能力

| API | 功能 |
|-----|------|
| `getCurrentPage()` | 获取当前页面名 |
| `navigateTo(page)` | 跳转到指定页面 |
| `insertTodayBlock(content, marker)` | 在今日日志插入 Block |
| `searchPages(query)` | 搜索页面 |
| `getAllTags()` | 获取所有标签 |
| `listAllPages()` | 获取所有页面名 |
| `getPageBlocks(pageName)` | 获取页面 Block 内容摘要 |
| `getPageStats()` | 统计页面与 Block 数量 |
| `getTemplateNames()` | 获取内置模板名列表 |
| `insertTemplateByName(name)` | 按名称插入模板 |
| `notify(message)` | 弹出通知 toast |

**内置插件**：每日速记、待办统计、页面统计、模板插入共 4 个；设置页「插件」分区可查看 manifest 并启用/禁用，状态持久化到 `plugin_state.json`。

---

## 鸿蒙特性

### 华为账号（Account）

通过 `@kit.BasicServicesKit` 的 `distributedAccount` 查询当前系统华为账号（分布式账号）状态，并作为云同步与订阅的前置条件：

- `HuaweiAccountService.refresh()` 获取账号 ID / 昵称 / 头像 / 登录状态
- `CloudSyncService.syncAll()` 在未登录华为账号时直接跳过（端云协同依赖系统账号）
- `SubscriptionService.refreshProStatus()` 在未登录时强制返回非 Pro，避免旧账号订阅状态串用
- 设置页「账户」分区展示华为账号、云同步绑定状态，并提供「刷新账号状态」

依赖权限：`ohos.permission.DISTRIBUTED_DATASYNC`（已在 `module.json5` 声明）。

### 分布式协同编辑

```typescript
// DistributedKVStore + autoSync
const kvStore = await kvManager.getKVStore('callaite_collab_store', {
  createIfMissing: true,
  autoSync: true,
  kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
  securityLevel: distributedKVStore.SecurityLevel.S2
});

// 监听跨设备变更
kvStore.on('dataChange', SubscribeType.SUBSCRIBE_TYPE_ALL, (data) => { ... });
```

### 多端流转（Continuation）

跨设备无缝迁移编辑状态，基于 `continuable` Ability + `onContinue` / `onRestoreData` 回调。

```typescript
// EntryAbility.onContinue — 源端序列化
onContinue(wantParam: Record<string, Object>): void {
  const want: Want = { parameters: wantParam };
  ContinuationManager.saveToContinue(want);
}

// EntryAbility.onRestoreData — 目标端恢复
onRestoreData(want: Want): void {
  ContinuationManager.restoreFromContinue(want);
}
```

**迁移状态字段**：currentPage / editingBlockUuid / scrollOffset / leftSidebarOpen / rightSidebarOpen

`module.json5` 已配置 `"continuable": true`。

### PenKit 手写笔集成

白板支持手写笔压感输入，4 种笔刷各有独特映射：

| 笔刷 | 线宽公式 | 透明度 |
|------|---------|--------|
| 钢笔（PEN） | `base × (0.3 + 0.7×pressure)` | 1.0 |
| 铅笔（PENCIL） | `base × (0.5 + 0.5×pressure)` | 随压感变化 |
| 马克笔（MARKER） | `base × (0.8 + 0.2×pressure)` | 0.6 |
| 橡皮擦（ERASER） | `base × 1.5` | 1.0 |

- 手掌误触过滤：压感 < 0.1 且非手写笔来源判定为手掌
- 笔触平滑：3 点移动平均
- 模拟器降级：检测不到手写笔时 pressure 固定 1.0，通过 `TouchEvent.force` 运行时检测

> **按需启用说明（4.1.5）**：Pen Kit 以 HSP 形式提供（HMS 能力），OpenHarmony 模拟器不含该 HSP；ArkTS 不支持动态 import，静态引用即构成硬依赖（实测在无该 HSP 的设备上启动即 `SIGABRT`，崩溃点 `LoadJSPandaFile: com.huawei.hmos.hwstylusfeature/Penkit`）。因此 Pen Kit 渲染页独立于启动路径（`components/whiteboard/PenCanvasPage.ets`），仅在具备手写笔能力的真机构建中接入（需 product flavor 或独立 HSP 模块）。`PenKitService` 的笔刷/压感映射与白板 Canvas 渲染逻辑可独立工作，不受影响。

### IAP Kit 订阅

| 方法 | API |
|------|-----|
| 查询状态 | `iap.queryPurchases(ctx, { productType: AUTORENEWABLE, queryType: CURRENT_ENTITLEMENT })` |
| 发起购买 | `iap.createPurchase(ctx, { productType: AUTORENEWABLE, productId: 'callaite_pro_monthly' })` |
| 确认发货 | `iap.finishPurchase(ctx, { purchaseToken, productType, purchaseOrderId })` |

Pro 状态缓存到沙箱文件，启动时先恢复未过期缓存，随后网络刷新；每 24 小时定时刷新一次。
闪卡与 PDF 为 Pro 功能，Free 用户点击入口会跳转「Callaite Pro」升级页。

### Cloud Kit 云同步

使用 Core File Kit `cloudSync` 能力：

```
本地 .md → AES-256-CBC 加密 → context.cloudFileDir → FileSync.start() → 系统上云
                                                                       → 其他设备自动下行
```

- 云端文件使用 `EncryptionService` AES-256-CBC 加密后写入（IV + 密文 base64）
- 文件名做路径穿越校验（拒绝 `/`、`\`、`..` 与非 `.md`）
- 同步受 Free/Pro 配额门控：Free 最多 1 个文件、Pro 最多 10 个文件，仅阻止新增、放行已同步文件更新
- 冲突解决：last-write-wins（按 mtime 比较，较旧一侧跳过）
- Block 元数据索引经 `BlockMetadataSyncService` 序列化并加密同步到云目录（跨设备快速检索）
- 入口：设置页「立即同步」、应用退后台自动触发 `syncAll()`

### 服务卡片（FormExtensionAbility）

两种卡片类型，30 分钟定时刷新：

| 卡片类型 | 功能 |
|---------|------|
| 概览卡片（2×2） | 显示页面数 + 最新 3 条 Block 预览 |
| 速记卡片 | 说明文本 + 打开应用按钮，点击跳转主应用 |

卡片不支持 TextInput（SDK 限制），速记输入在主应用内完成：

```
点击按钮 → postCardAction router → EntryAbility
```

> 兼容说明：EntryFormAbility 仍保留 `onFormEvent` message 通道
> （`handleQuickNoteFromMessage`），旧版卡片发送的
> `{ "text": "..." }` message 依旧会创建 Block 到今日日志页。

### 分享接收（ShareReceiveAbility）

接收系统分享文本/URL，自动创建 Block 到今日日志页：

- 文本分享 → Block content
- URL 分享 → 转为 `[url]` 格式 Block
- 处理后显示 toast 提示并跳转日志页

### 状态持久化（StatePersistence）

`PersistentStorage` 在 SDK 冷启动时恢复不可靠，Callaite 自管 JSON 文件持久化关键状态：

- `onCreate` 同步恢复 10 个 AppStorage 键（引导标志 / 主题模式 / 语言 / 用户配置 / 收藏夹 / 侧栏折叠状态等），必须在任何 UI 加载前执行
- `onBackground` 与 `onSaveState` 时写入，避免进程被杀后状态丢失
- 主题恢复分两步：启动初期 `setColorMode(NOT_SET)` 跟随系统 → `AppState.initialize()` 后 `ThemeManager.applyPersistedTheme()` 应用持久化主题（顺序错误会导致 dark/light 资源限定符不切换）

### 崩溃恢复（ErrorRecoveryService）

- `appRecovery.enableAppRecovery` — JS 崩溃 / 主线程卡死 / Native 崩溃自动重启
- `errorManager.on('error')` — 全局捕获未处理异常，落日志并保存数据
- `onSaveState` 回调 — 框架触发时执行 `WorkspaceService.saveAll()`

### 沉浸光感与系统栏（API 26）

**材质 Token 体系**（`theme/MaterialTokens.ets` + `components/common/GlassSurface.ets`）

- 5 档语义角色 `MaterialRole`：TOP_FLOATING（顶栏）/ BOTTOM_FLOATING（底栏）/ OVERLAY（浮层）/ DIALOG（弹窗）/ DRAWER（抽屉），映射官方沉浸光感 ULTRA_THIN → ULTRA_THICK 五档
- 每档定义模糊半径 / 填充色 / 高光不透明度 / 阴影半径与透明度，由 `ImmersiveMaterialResolver` 统一解析；顶栏 56vp 玻璃面同步支持按压弹性反馈（官方六特性之一）
- 运行时能力探测：`isImmersiveMaterialSupported()` 为 false 时自动走 Token 降级参数，低算力设备按 `getGlobalMaterialLevel()` 细化
- **系统材质（`systemMaterial`）当前未启用**：官方约束其仅在 `Navigation`/`NavDestination` 标题栏或横向 Tabs 底部 TabBar 生效；实测在自研容器外壳上调用会触发 `THREAD_BLOCK_6S` 冻结（且 Navigation 简单包裹会导致桌面壳布局回归）。外壳按 Navigation 布局模型重设计后，经预留入口 `ImmersiveMaterialResolver.buildSystemMaterial()` 启用

**系统栏颜色统一**（`utils/SystemBarHelper.ets`）

- `statusBarColor` / `navigationBarColor` 显式置 `#00000000` —— SDK 默认值为 `#66000000`（40% 黑色半透明），沉浸式布局下会让应用背景透出灰色条，与顶栏/底栏颜色不一致
- 内容色随主题：浅色 `#1F2328` / 深色 `#FFFFFF`；`ThemeManager.setThemeMode` 切换主题时实时刷新
- 沉浸式避让区由 `EntryAbility.publishAvoidArea()` 写入 AppStorage（`safeTop`/`safeBottom`），Header、底栏胶囊、内容区内边距统一消费，并监听 `avoidAreaChange` 动态更新（折叠/旋转/分屏）

### API 26 行为变更适配

针对 API 26 SDK 升级扫描出的行为变更（P0 级）逐项适配：

| 变更 | 适配方式 |
|------|---------|
| `setWindowLayoutFullScreen` / `setImmersiveModeEnabledState` 在 PC/2in1 自由多窗禁用 | 按 `deviceInfo.deviceType` 分支：PC/2in1 跳过全屏切换，仅采集避让区 + 系统栏样式 |
| Canvas 方法传 NaN/Infinity 后污染整幅画面（其它绘制由不绘制变更为正常绘制） | `utils/CanvasMath.ets` 有限性防护接入 Whiteboard（网格/笔触）与 GraphView（连线/节点/文本）；**绘制热路径使用定参比较（`notFinite2/3/4`），禁止数组字面量**——每帧每段分配临时数组会引发 GC 风暴（实测主线程冻结，`BCStub_*` 桩 CPU 忙等） |
| ArkUI 双指长按行为变更 | 三处 `LongPressGesture` 显式 `fingers: 1` |
| `Button` 默认 type 变更为新增圆角矩形 | 全项目 Button 显式 `.type(ButtonType.Capsule/Circle)`，保持 API 26 前外观 |
| `getOsAccountDistributedInfo` 返回值生成规则变更 | 登录判定以 `status` 枚举为主，`id` 仅作空值兜底，不比较具体值 |
| 属性动画 `onFinish` 退后台提前触发 | 项目未使用 `onFinish` 回调，无需适配 |

### 安全

- **应用沙箱**：HarmonyOS 应用沙箱隔离
- **AES-256-CBC 加密**：cryptoFramework + 密码学安全随机 IV（16 字节）
- **密钥持久化**：随机生成的 256 位密钥持久化到应用沙箱文件，跨启动复用，不使用硬编码种子
- **UTF-8 安全**：加解密使用 UTF-8 编码，正确支持中文等多字节内容
- **端云同步加密**：云端 `.md` 以 AES-256-CBC 加密后写入，避免云端明文泄露
- **云同步路径校验**：拒绝文件名中的路径穿越片段（`/`、`\`、`..`）
- **IAP JWS 解析**：订阅状态 JWS 使用 base64url 解码，状态码兼容数字/字符串
- **WebView 防注入**：Block 内容进入编辑器前做 HTML 实体转义，阻断脚本注入
- **路径穿越防护**：页面名转换为文件名时清洗 `/ \ ..` 等危险片段
- **权限**：DISTRIBUTED_DATASYNC（分布式数据同步）

---

## 扩展功能

### 导入导出

**导出**（ExportService + ExportDialog）
入口：Header 菜单「导出图谱」、设置页「数据 → 导出数据」。

| 范围 | 格式 | 说明 |
|------|------|------|
| 当前页 | Markdown | 复制原 .md 文件到目标目录 |
| 全部页 | Markdown | 批量复制所有 .md |
| 当前页 | HTML | Block → `<ul><li>` 嵌套 + TODO/引用/代码/引用块 + 完整 HTML 文档 |
| 全部页 | HTML | 批量导出 HTML |
| 当前页/全部页 | OPML | 页面树导出为 `callaite.opml` |

**导入**（ImportService + ImportDialog）
入口：Header 菜单「导入」、设置页「数据 → 导入数据」。

外部 .md 文件导入，自动解析为 Block 树：

- `- ` / `* ` 前缀识别 Block
- 2 空格 / Tab 缩进识别层级
- `# ` 标题作为顶层 Block
- `- [ ]` / `- [x]` 作为 TODO Block
- ``` 代码块合并为单个 Block
- `---` 分隔符识别

导入模式：导入到当前页 / 作为新页面（文件名作为页面名）。

### 快捷键自定义（ShortcutSettings）

设置页内提供快捷键自定义入口，支持：

- 按分类分组的快捷键列表（编辑 / 导航 / 视图 / 其他）
- 搜索过滤
- 点击"修改"进入按键监听模式
- 冲突检测（重复绑定显示红色警告）
- 恢复默认
- 持久化到 AppStorage，加载时合并默认值与用户覆盖

### 多步引导（Onboarding）

首次启动 4 步引导流程：

1. **欢迎**：功能介绍（日志 / 大纲 / 双向链接 / 搜索）
2. **创建 Graph**：说明本地 Markdown 存储
3. **快捷键**：6 个核心快捷键展示
4. **示例页面**：点击"开始使用"完成引导

顶部 4 圆点进度指示器，完成后写入 `AppStorage('callaite_onboarded', true)`。

### 代码高亮（CodeBlock）

WebView + highlight.js CDN 实现代码语法高亮，支持常见语言。

### 数学公式（MathRenderer）

WebView + KaTeX 0.16.9 CDN，支持行内 `$...$` 和块级 `$$...$$`。

### 图表（MermaidRenderer）

WebView + mermaid.js 10 CDN，支持流程图/时序图/类图等，主题自动适配深浅色。

---

## UI 设计规范

### 配色方案

浅色对齐 Logseq light，暗色为 Logseq Solarized 深色（`vars-classic.css` `[data-theme=dark]`）。

| Token | 浅色 | 暗色（Solarized） | 用途 |
|-------|------|------|------|
| primary | `#106BA3` | `#268BD2` | 主色调（链接、选中态、交互强调） |
| text | `#433F38` | `#A4B5B6` | 正文 |
| surface0 | `#FFFFFF` | `#002B36` | 主背景 |
| surface1 | `#F7F7F5` | `#023643` | 侧栏背景 |
| surface2 | `#F0F1F2` | `#08404F` | 选中态/hover 背景 |
| border | `#E8E9EA` | `#0E5263` | 分割线 |
| bullet | `#B9BEC7` | `#608E91` | Block 圆点 |
| muted_text | `#8A94A6` | `#5E7A7E` | 辅助文字 |
| icon_color | `#646464` | `#5E7A7E` | 工具图标（--ls-icon-color） |
| link | `#106BA3` | `#8ABBBB` | 链接文字 |
| success | `#059669` | `#34D399` | DONE / 成功 |
| danger | `#DC2626` | `#F87171` | TODO / 危险 |

### 布局规范

- **响应式三形态外壳**（`state/Breakpoints.ets`，遵循 HarmonyOS 一多断点：sm < 600vp ≤ md < 840vp ≤ lg）：
  - **compact**（手机，<600vp）：Obsidian iOS 式沉浸玻璃 —— 悬浮玻璃顶栏 + 底部 6 单元胶囊栏（宽度 80%、上限 336vp）+ 抽屉侧栏 + 编辑态键盘上方 Markdown 工具行
  - **medium**（600–840vp，折叠屏展开/小平板）：桌面布局，侧栏默认收起
  - **expanded**（>840vp，平板/2in1/PC）：完整 Obsidian 桌面 —— Ribbon + 双侧栏 + 标签栏（`⌄` 标签列表在最左 / 分屏开关 / 新建）+ StatusBar，内容区支持左右分屏
- 主内容区限宽 960vp 并水平居中（`--ls-main-content-max-width`），宽屏两侧留白；窄屏（<768vp）左右内边距 20vp，宽屏 48vp。
- Journal 首页为日志流 feed：最近日期在上，初始 7 天，滚动到底追加 7 天；点击日期标题进入单日页。
- 左侧栏 FAVORITES / RECENT / ALL PAGES 为可折叠分组（chevron 切换，折叠态持久化到 `callaite_collapsed_*`），顶部含文件树工具行（见功能特性 12）。
- 左右双侧栏与分屏比例支持拖拽调整并持久化。

### 图标系统

使用 Tabler Icons v2.47（MIT 协议），以 SVG Path 数据内联存储，经 ArkTS `Shape` + `Path` 组件原生绘制（零字体加载、无第三方依赖）。

**渲染规范**：`IconRenderer` 通过 `viewPort({ x:0, y:0, width:24, height:24 })` 将 Tabler 的 24×24 设计坐标系映射到目标尺寸，并按 `strokeWidth = iconSize / 12` 等比缩放线宽，确保任意尺寸下图标不错位、不模糊、不产生过粗线条。

**尺寸与用色分级**：Header 工具图标 20vp（48vp 触控容器）、左侧栏导航 20vp、分段标题 14vp、行内操作 16vp；工具图标统一使用 `icon_color`，激活态用 `primary`，禁用态用 `muted_text`。

| 分类 | 代表图标 |
|------|---------|
| 导航 | arrow-*, chevron-*, caret-*, menu-2 |
| 操作 | plus, check, x, trash, edit, copy, refresh, download, upload |
| 文件 | file, files, file-code, file-off, folder, folder-off, file-upload |
| 视图 | search, settings, layout-*, layout-grid, table, list, filter |
| 内容/标记 | hash, home, bolt, bulb, calendar-*, alarm, lock, pin, link, stack-2 |
| 状态 | check, checkbox, circle-minus, alert-triangle, mood-empty |
| 图谱/画布 | focus, focus-2, circle-dot, world, hierarchy, user |
| 系统 | database, server-cog, source-code, keyboard, command, crown |

### 字体层级

| 用途 | 大小 | 字重 |
|------|------|------|
| 页面标题 | 36px | Bold |
| 导航标题 | 24px | Bold |
| App 名称 | 17px | Bold |
| Block 正文 | 15px | Normal |
| 侧栏链接 | 13px | Normal/Medium |
| 分段标题 | 11px | Bold |
| 辅助文字 | 11-12px | Normal |

### 间距

| 元素 | 尺寸 |
|------|------|
| Block 缩进/级 | 24px |
| Block 行高 | 28px |
| 圆点直径 | 6px |
| Header 高度 | 48px |
| 侧栏宽度 | 260px / 280px |
| 页面左右内边距 | 48px |

---

## 启动链

```
EntryAbility.onCreate
  ├── FileService.setContext(this.context)   // 沙箱路径上下文
  ├── StatePersistence.load()                // 冷启动恢复 10 个 AppStorage 键（引导标志/主题/语言/配置等）
  ├── ErrorRecoveryService.init()            // appRecovery + errorManager 全局异常捕获
  └── setColorMode(NOT_SET)                  // 启动初期跟随系统，持久化主题延后应用

EntryAbility.onRestoreData（仅多端流转目标端）
  └── ContinuationManager.restoreFromContinue(want)   // 恢复迁移状态

EntryAbility.onWindowStageCreate
  ├── GlobalContext.setContext(this.context) // 全局上下文（Pen Kit 等按需模块消费）
  ├── FileService.initGraph()                // 加载 .md 文件到内存
  ├── CollaborationService.getInstance().init(ctx)      // 初始化分布式 KVStore
  ├── SubscriptionService.initCachedProState()          // 恢复缓存的 Pro 状态（先展示，不等网络）
  ├── SubscriptionService.startPeriodicRefresh()        // 24h 定时刷新
  ├── SubscriptionService.refreshProStatus()            // 网络刷新 IAP 订阅状态
  ├── HuaweiAccountService.refresh()         // 华为账号状态（云同步与 IAP 前置）
  ├── EncryptionService.init()               // AES-256 密钥初始化
  ├── CloudSyncService.initCloudDir()        // 端云协同目录创建
  ├── registerBuiltinPlugins()               // 插件系统初始化
  ├── AppState.initialize()                  // 主题 → i18n → AppStorage → 侧栏状态
  ├── TabState.initialize()                  // 标签页状态初始化
  ├── ThemeManager.applyPersistedTheme()     // 必须在 AppStorage 初始化后、loadContent 前，
  │                                          // 否则 dark/light 资源限定符不切换
  └── loadContent('pages/Index')             // 渲染主界面
        └── 回调内 setupImmersiveLayout(windowStage)   // 沉浸式布局（API 26 适配）
              ├── PC/2in1 → 跳过 setWindowLayoutFullScreen（自由多窗禁用），仅采集避让区
              ├── 其它设备 → setWindowLayoutFullScreen(true)
              ├── SystemBarHelper.apply(isDark)          // 系统栏背景全透明 + 主题内容色
              ├── publishAvoidArea()                     // safeTop/safeBottom → AppStorage
              └── on('avoidAreaChange')                  // 折叠/旋转/分屏动态更新

EntryAbility.onBackground
  ├── WorkspaceService.saveAll()             // 保存所有页面
  ├── StatePersistence.save()                // 持久化跨进程状态
  └── CloudSyncService.syncAll()             // 端云协同同步（完成后同步 Block 元数据索引）

EntryAbility.onSaveState（崩溃恢复）
  └── WorkspaceService.saveAll()             // 框架触发时保存数据
```

> 测试数据播种 `TestDataService.seedIfEmpty()` 已于 3.1.2 从启动链移除，生产构建不会创建示例页面。

---

## 技术选型

| 领域 | 方案 | 说明 |
|------|------|------|
| UI 框架 | ArkUI 声明式 | HarmonyOS 原生 |
| 状态管理 | AppStorage + @StorageLink | MVVM 响应式 |
| 编辑器 | WebView contenteditable | 98% Logseq 键盘兼容 |
| Markdown 解析 | 自研缩进感知解析器 | Logseq .md 格式兼容 |
| 文件 I/O | CoreFileKit fd-based | `fs.openSync/writeSync/closeSync` |
| 内存索引 | BlockTree + IndexStore | UUID O(1) + 三种倒排 |
| 查询 | QueryEngine / DatalogEngine / LogicEngine | 多条件 + S-表达式 + 递归规则 |
| 图谱 | Canvas 2D + 力导向布局 | 斥力 5000 / 引力 0.005 / 阻尼 0.85 |
| 公式 | WebView + KaTeX 0.16.9 CDN | 行内 + 块级 |
| 图表 | WebView + Mermaid 10.9.0 CDN | 流程图/时序图 |
| 分布式 | DistributedKVStore + autoSync | P2P 实时协同 |
| 多端流转 | continuable Ability + onContinue/onRestoreData | 跨设备状态迁移 |
| 目标 SDK | API 26.0.0（HarmonyOS 7） | API 26 行为变更已逐项适配（见鸿蒙特性） |
| 沉浸光感 | MaterialTokens 五档语义 Token + GlassSurface | 能力探测自动降级；系统材质待外壳迁移 Navigation 后启用 |
| 桌面分屏 | layoutWeight 权重 + PanGesture 分隔条 | 0.2–0.8 钳制、双窗格独立焦点域 |
| 系统栏 | SystemBarHelper | 背景全透明 + 内容色随主题实时刷新 |
| 手写笔 | PenKit（HSP 按需启用模块） | 压感映射；无 HSP 设备走 Canvas 降级，详见鸿蒙特性 |
| 订阅 | IAP Kit | 华为应用市场 |
| 云同步 | Core File Kit 端云协同 | 零服务器 |
| 加密 | cryptoFramework AES-256-CBC | 随机 IV |
| 闪卡 | FSRS-4.5 算法 | 稳定性/难度/可提取性 |
| 图标 | 149 个 Tabler SVG → ArkTS Shape | MIT 协议 |
| 插件 | 预编译 + 静态注册表 | ArkTS 安全兼容 |
| i18n | 自定义 I18nDict class | 中/英双语 |
| 状态持久化 | StatePersistence 自管 JSON | 替代 PersistentStorage（冷启动恢复不可靠） |
| 崩溃恢复 | appRecovery + errorManager | 自动重启 + 全局异常捕获 |

---

## ArkTS 编译约束

开发中严格遵守以下 ArkTS 限制：

| 禁止 | 替代方案 |
|------|---------|
| `any` / `unknown` | 显式类型注解 |
| `Record<K,V>` | 自定义 class（PropertyBag / I18nDict / IconEntry[]） |
| `[key: string]` 索引签名 | class + get/set/forEach 方法 |
| `...spread` 展开运算符 | 逐字段手动赋值（mergeConfig / manual copy） |
| 独立函数中 `this` | 类名静态引用（`ClassName.method()`） |
| `Partial<T>` | 显式 `AppConfigPartial` interface |
| @Builder 中变量声明 | @State + aboutToAppear 预加载 |
| 对象字面量作类型声明 | interface 独立定义 |
| `switch` 语句 | if/else 链 |
| `in` 操作符 | tagged union 字段检测 |
| `for...of` | 传统 for 循环 + Map.forEach |
| 绘制热路径数组字面量 | `CanvasMath.notFinite2/3/4` 定参比较（每帧分配临时数组会引发 GC 风暴，实测主线程冻结） |

---

## 项目目录

```
Callaite/entry/src/main/ets/
├── components/              68 文件 (UI 层)
│   ├── outliner/            11  (BlockView / BlockList / BlockChildren / BlockDragHandler / BlockSelection /
│   │                            WebEditor / RichBlockEditor / SlashMenu / AutoComplete / Toolbar / FindInPage)
│   ├── sidebar/              5  (LeftSidebar / RightSidebar / PageTree / PageContextMenu / BacklinkFilters)
│   ├── page/                 4  (PageView / ContentArea / JournalFeed / AllPagesPage)
│   ├── layout/               9  (MainContainer / Ribbon / TabBar / StatusBar / MobileHeader /
│   │                            MobileBottomBar / TabOverviewSheet / MobileMenuSheet / SplitDivider)
│   ├── graph/                3  (GraphView / GraphLayout / GraphActions)
│   ├── whiteboard/           5  (Whiteboard / WbShape / WbConnector / WbPageRef / PenCanvasPage*)
│   ├── search/               3  (SearchPanel / TaskDashboard / TaskSchedulePanel)
│   ├── settings/             4  (SettingsPage / ProUpgradePage / RecycleBinPage / ShortcutSettings)
│   ├── property/             3  (PropertyEditor / PropertyConfig / PropertyValueEditor)
│   ├── query/                3  (QueryBuilder / QueryView / InlineQueryBlock)
│   ├── commandpalette/       1  (CommandPalette)
│   ├── flashcard/            1  (FlashcardPage)
│   ├── onboarding/           1  (OnboardingPage)
│   ├── mobile/               2  (MobileToolbar / MarkdownToolbar — 键盘上方 Markdown 工具行)
│   ├── common/               8  (Icons / TablerIconPaths / ThemeManager / DatePicker / ExportDialog /
│   │                            ImportDialog / FloatingPanel / GlassSurface)
│   └── extensions/           5  (MathRenderer / MermaidRenderer / CodeBlock / PdfViewer / PdfPage)
├── theme/                    1  (MaterialTokens — 沉浸光感五档语义 Token)
├── core/                    22 文件 (引擎层)
│   ├── models/               4  (Block / Page / Property / Constants)
│   ├── engine/               9  (BlockTree / OutlinerOps / OutlinerEngine / Validator /
│   │                            TransactionPipeline / ReferenceResolver / PropertyEngine /
│   │                            TemplateEngine / RecycleEngine)
│   ├── parser/               2  (MarkdownParser / MarkdownExporter)
│   ├── db/                   6  (DataStore / IndexStore / QueryEngine / DatalogEngine / LogicEngine / ReactiveQuery)
│   └── persistence/          1  (FileRepository)
├── services/                21 文件 (服务层)
│   Workspace / File / Editor / Journal / Template / ShortcutService / PasteService /
│   Subscription / Collaboration / Encryption / CloudSync / ContinuationManager /
│   PenKitService / Export / Import / Flashcard / WhiteboardFileService / TestData /
│   HuaweiAccount / BlockMetadataSync / ErrorRecovery
├── plugins/                  4 文件 (插件框架)
│   CallaitePlugin / PluginAPI / PluginManager / BuiltinPlugins
├── state/                    4  (AppState / StatePersistence / TabState / Breakpoints)
├── utils/                    8  (i18n / UUID / ContentRenderer / NamespaceUtils / PageTitle /
│                                CanvasMath / SystemBarHelper / GlobalContext)
├── pages/                    1  (Index)
├── entryability/             1  (EntryAbility — onContinue/onRestoreData + PC/2in1 沉浸式分支)
├── entryformability/         1  (EntryFormAbility — 速记卡片 + 30 分钟刷新)
├── entrybackupability/       1  (EntryBackupAbility)
├── shareability/             1  (ShareReceiveAbility — 接收分享创建 Block)
└── widget/pages/             1  (WidgetCard — 概览/速记双卡片)
```

\* `PenCanvasPage` 为 Pen Kit 按需启用模块，不在应用启动路径（原因与启用方式见[鸿蒙特性](#鸿蒙特性)）。

---

## 构建说明

```bash
# 快捷方式（工作区根目录）：bash build_callaite.sh debug
# 构建模式在 build-profile.json5 中配置
# 编译日志输出到工作区根目录的 errorlog.txt
# 构建产物: entry/build/default/outputs/default/entry-default-unsigned.hap
```

**系统要求**: HarmonyOS SDK（targetSdkVersion 26.0.0）/ DevEco Studio 6.x+ / API 26 模拟器或真机

> **SDK 兼容性实测**：`compatibleSdkVersion: "26.0.0"` 仅允许 API 26+ 设备安装（API 24 模拟器安装报 `9568297 older sdk version`）。已验证的模拟器：MatePad Pro 13（API 24）与 Pura 90 Pro Max（API 26 / OpenHarmony 7.0.0.105）。若需覆盖 API 24 设备，将 `compatibleSdkVersion` 改为 `"6.1.1(24)"`（格式规则见文档开头）；`target 26.0.0 + compatible 6.1.1(24)` 组合已实测可行，API 26 设备不受影响。

**权限声明** (`module.json5`):
- `ohos.permission.DISTRIBUTED_DATASYNC` — 分布式协同编辑

**测试数据**: `TestDataService` 保留在代码库中供开发调试，但自 3.1.2 起已从启动链移除，生产构建首次启动为空白 Graph + 4 步引导。

---

## 发布前检查清单

> 以下清单覆盖「可发布」所需的全部前置条件、质量门禁、真机回归与上架产物，按顺序执行即可。

### 0. 必须手动完成（签名/包名/云端配置，代码无法代填）

- [ ] 将 `AppScope/app.json5` 中的占位 `bundleName: "com.example.callaite"` 替换为正式包名，并同步修改 `services/CollaborationService.ets` 中硬编码的 `bundleName`
- [ ] 在 `build-profile.json5` 的 `signingConfigs` 中配置发布证书（目前为空，release HAP 不会签名）
- [ ] 在 AppGallery Connect 创建项目并绑定应用，完成云端配置：IAP 商品、云同步/云数据库能力
- [ ] 在 AGC「商品管理」中创建自动续期订阅商品 `callaite_pro_monthly`（月订阅，UI 标价 ¥12/月）
- [ ] 确认发布设备的「系统设置 → 华为账号」已登录（云同步与 IAP 均依赖系统华为账号）

### 1. 版本与元信息

- [ ] 更新 `AppScope/app.json5` 的 `versionCode` / `versionName`（当前 `1000000` / `1.0.0`）
- [ ] 检查 `oh-package.json5` 的 `description` 与应用说明一致
- [ ] 检查 `AppScope/resources/base/element/string.json` 的 `app_name`（当前 `Callaite`）
- [ ] 检查应用图标与启动图（`AppScope/resources/base/media/`）已替换为正式资源

### 2. 权限与隐私

当前仅声明一个普通权限：

| 权限 | 用途 | 类型 |
|------|------|------|
| `ohos.permission.DISTRIBUTED_DATASYNC` | 分布式协同编辑 + 华为账号查询 | normal，无需动态申请 |

- [ ] 确认隐私政策已说明：笔记经 AES-256-CBC 加密后写入华为云空间进行端云同步
- [ ] 若后续引入位置/相册/文件等敏感权限，需在 `module.json5` 补充 `reason` 并做动态申请与合规声明

### 3. 测试数据清理 ✅ 已完成

- [x] `TestDataService.seedIfEmpty()` 已于 3.1.2 从 [EntryAbility.ets](entry/src/main/ets/entryability/EntryAbility.ets) 启动链移除，生产构建首次启动为空白 Graph + 4 步引导

### 4. 构建与质量门禁

```bash
# 全量 clean 编译（目标 BUILD SUCCESSFUL，仅允许出现签名/弃用 WARN）
node "D:\program files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" --mode module -p product=default clean assembleHap --analyze=normal

# 静态检查（CodeLinter）
node "D:\program files\Huawei\DevEco Studio\plugins\codelinter\run\index.js" -c code-linter.json5 -f json -o lint-result.json .
```

- [ ] CodeLinter 结果：0 error、0 security；当前存在 12 条 performance `warn`（非阻断，可后续清理）
- [ ] 确认无 `any`/`unknown`/`Record`/索引签名等 ArkTS 违例（仅 `onContinue` 签名与 JSON 解析处保留 SDK 要求的 `Record`）

### 5. 安全自查要点

- WebView 内容渲染已做 HTML 转义/JSON 安全嵌入，阻断 `<script>` 注入
- 文件名与云同步已做路径穿越校验（`/`、`\`、`..`）
- 端云同步文件以 AES-256-CBC 加密写入
- 依赖无第三方运行时库；仅使用 HarmonyOS 官方 Kit

### 可靠性与发布优化（已就绪）

- 崩溃恢复与全局异常捕获：`appRecovery` 启用 JS 崩溃/主线程卡死/Native 崩溃自动重启，`errorManager.on('error')` 全局捕获未处理异常并落日志、保存数据
- 文件原子写入：`FileRepository.writeTextSync` 先写临时文件并 `fsync`，再 `rename` 原子替换，异常退出不破坏原文件
- 单元测试已补齐：本地纯逻辑测试（路径穿越/UUID）与设备端测试（Markdown 链接/模板展开）
- release 混淆已启用：`entry/build-profile.json5` 的 release `buildOptionSet` 中 `obfuscation.ruleOptions.enable = true`
- 包元信息：`entry/oh-package.json5` 已设置 `license: "MIT"` 与描述

### 6. 功能回归清单（真机）

**编辑器**
- [ ] Block 树/缩进/上下移/折叠/拖拽/多选
- [ ] Slash 命令、`[[`/`((`/`#` 补全
- [ ] 行内格式、代码块、引用块、Markdown 表格单元格编辑、`[文本](url)` 链接
- [ ] 中文 IME 输入、粘贴 Markdown 拆分

**引用/查询/任务**
- [ ] 页面/块引用、页面/块嵌入、反链与筛选
- [ ] `{{query}}` 与 `#+BEGIN_QUERY` 内联查询、查询构建器三视图
- [ ] TODO/DOING/DONE、优先级、SCHEDULED/DEADLINE、日志页任务面板

**其他**
- [ ] 全局搜索、命令面板、图谱、白板（含手写笔）、模板、导入/导出（MD/HTML/OPML）、回收站、主题、多语言、快捷键

**鸿蒙特性**
- [ ] 华为账号展示与刷新
- [ ] 云同步（加密、配额 Free 1/Pro 10、冲突 last-write-wins、退后台自动同步）
- [ ] 分布式协同编辑（多设备）
- [ ] 多端流转、分享接收、备份恢复、服务卡片
- [ ] PenKit 压感手写（真机）

**Pro 订阅**
- [ ] 沙箱购买/恢复购买、Pro 状态持久化与 24h 刷新
- [ ] Free 用户访问闪卡/PDF 跳转升级页、云同步配额拦截
- [ ] PDF 选中文字 → 页内高亮持久化 → 生成标注 Block

### 7. 上架产物

- [ ] 配置签名后重新构建，确认产物为 `entry/build/default/outputs/default/entry-default-signed.hap`（当前为 `entry-default-unsigned.hap`）
- [ ] 在 AppGallery Connect 上传签名 HAP，填写审核材料（应用描述、截图、隐私政策 URL、订阅定价与说明）
- [ ] 提交审核前复核包名、版本号与签名证书与上架信息一致

---

## 许可

MIT License
