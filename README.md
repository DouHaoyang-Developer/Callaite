# Callaite

**Logseq 风格的鸿蒙知识管理应用** — 基于 HarmonyOS ArkTS 构建，完整复刻 Logseq 的大纲编辑、双向链接、知识图谱等核心体验。

> **SDK**: 6.1.1(24) / API 12 · **语言**: ArkTS · **模型**: Stage Model  
> **规模**: 72 源文件 · ~10,200 行代码 · 0 第三方运行时依赖  
> **架构**: MVVM + Service + Plugin + Query 四层架构

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
# 3. 首次启动自动播种 5 个测试页面
```

启动后点击左侧栏「日志」进入今天的日志页，点击 Block 开始编辑。

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
- **自动保存**：编辑器失焦时自动保存到 DataStore 并持久化到 .md 文件

**Block 操作**
- 圆点（●）点击：展开操作工具栏
- 任务标记（TODO/DOING/DONE）：点击循环切换，彩色标签
- 缩进/反缩进：Tab / Shift+Tab 或操作按钮
- 上移/下移：Alt+↑↓ 或操作按钮
- 删除：操作栏 × 按钮
- 折叠/展开：点击 chevron 图标隐藏/显示子 Block
- 拖拽排序：拖拽手柄 + EditorService.moveBlockToTarget

**行内格式渲染**

| 语法 | 效果 |
|------|------|
| `**粗体**` | **粗体** |
| `*斜体*` | *斜体* |
| `~~删除线~~` | ~~删除线~~ |
| `==高亮==` | 黄色背景高亮 |
| `` `代码` `` | 等宽字体代码 |
| `[[页面名]]` | 蓝色可点击页面链接 |
| `((uuid))` | 蓝色可点击 Block 引用 |
| `#标签` | 绿色可点击标签 |
| `![[页面]]` | 页面嵌入 |
| `!((uuid))` | Block 嵌入（内联预览） |
| `$E=mc^2$` | 行内 KaTeX 公式 |
| `$$\sum x$$` | 块级 KaTeX 公式 |

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

**反向链接面板（右侧栏）**
- 实时显示哪些页面引用了当前页面
- 显示引用 Block 的上下文内容
- 筛选：全部 / 页面引用 / Block 引用

### 3. 页面系统

**日志页**
- 每日自动创建（格式 yyyy-MM-dd）
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

**间隔重复评分**：

| 评分 | 间隔系数 | 说明 |
|------|---------|------|
| 忘记 (0) | 重置为 1 | 完全遗忘 |
| 困难 (1) | ×0.8 | 勉强回忆 |
| 良好 (2) | ×1.5 | 正常回忆 |
| 简单 (3) | ×2.5 | 轻松回忆 |

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
│ Plugins（LuniusPlugin + PluginAPI）     │  ← 扩展层
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
class MyPlugin extends LuniusPlugin {
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

---

## 鸿蒙特性

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

### IAP Kit 订阅

| 方法 | API |
|------|-----|
| 查询状态 | `iap.queryPurchases(ctx, { productType: AUTORENEWABLE, queryType: CURRENT_ENTITLEMENT })` |
| 发起购买 | `iap.createPurchase(ctx, { productType: AUTORENEWABLE, productId: 'callaite_pro_monthly' })` |
| 确认发货 | `iap.finishPurchase(ctx, { purchaseToken, productType, purchaseOrderId })` |

### Cloud Kit 云同步

```
.md 文件 → /data/storage/el2/cloud/files/ → 系统自动上行同步
                                        → 其他设备自动下行同步
```

### 服务卡片

- 类型：FormExtensionAbility（2×2 ArkTS 卡片）
- 内容：显示最新 3 个 Block 预览
- 刷新：每 2 小时定时更新

### 安全

- **应用沙箱**：HarmonyOS 应用沙箱隔离
- **AES-256-CBC 加密**：cryptoFramework + 随机 IV
- **权限**：DISTRIBUTED_DATASYNC（分布式数据同步）

---

## UI 设计规范

### 配色方案

| Token | 浅色 | 暗色 | 用途 |
|-------|------|------|------|
| primary | `#0458A6` | `#5B9BD5` | 主色调（链接、选中态） |
| text | `#1A1A1A` | `#E0E0E0` | 正文 |
| surface0 | `#FCFCFC` | `#1C1C1D` | 主背景 |
| surface1 | `#F3F3F4` | `#242425` | 侧栏背景 |
| border | `#E8E9EA` | `#38383A` | 分割线 |
| bullet | `#A0A3A8` | `#6B6F74` | Block 圆点 |
| muted | `#787B80` | `#8B8F94` | 辅助文字 |
| success | `#059669` | `#34D399` | DONE / 成功 |
| danger | `#DC2626` | `#F87171` | TODO / 危险 |

### 图标系统

使用 Tabler Icons v2.47（MIT 协议），97 个图标以 SVG Path 数据存储 → ArkTS `Shape` + `Path` 组件原生绘制（零字体加载）。

| 分类 | 数量 | 代表图标 |
|------|------|---------|
| 导航 | 10 | arrow-left/right/up/down, chevron-* |
| 操作 | 12 | plus, check, x, trash, edit, copy, refresh |
| 文件 | 7 | file, file-code, folder, file-upload |
| 视图 | 12 | search, settings, layout-*, menu-2, dots |
| 内容 | 21 | hash, home, bolt, bulb, calendar, lock, pin |
| 状态 | 5 | check, circle-minus, alert-triangle |
| 用户 | 7 | user, world, logout, message-* |
| 系统 | 8 | server-cog, database-export, source-code |

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
| Header 高度 | 44px |
| 侧栏宽度 | 260px / 280px |
| 页面左右内边距 | 48px |

---

## 启动链

```
EntryAbility.onCreate
  └── FileService.setContext(this.context)

EntryAbility.onWindowStageCreate
  ├── FileService.initGraph()             // 加载 .md 文件到内存
  ├── TestDataService.seedIfEmpty()       // 空 Graph → 播种 5 个测试页面
  ├── CollaborationService.init(ctx)      // 初始化分布式 KVStore
  ├── SubscriptionService.refreshPro()    // 异步 IAP 订阅状态刷新
  ├── EncryptionService.init()            // AES-256 密钥初始化
  ├── CloudSyncService.initCloudDir()     // 端云协同目录创建
  ├── registerBuiltinPlugins()            // 插件系统初始化
  ├── AppState.initialize()              // 主题 → i18n → AppStorage → 侧栏状态
  └── loadContent('pages/Index')         // 渲染主界面
```

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
| 订阅 | IAP Kit | 华为应用市场 |
| 云同步 | Core File Kit 端云协同 | 零服务器 |
| 加密 | cryptoFramework AES-256-CBC | 随机 IV |
| 图标 | 97 个 Tabler SVG → ArkTS Shape | MIT 协议 |
| 插件 | 预编译 + 静态注册表 | ArkTS 安全兼容 |
| i18n | 自定义 I18nDict class | 中/英双语 |

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

---

## 项目目录

```
Callaite/entry/src/main/ets/
├── components/              34 文件 (UI 层)
│   ├── outliner/             6  (BlockView / BlockList / WebEditor / SlashMenu / AutoComplete / Toolbar)
│   ├── sidebar/              2  (LeftSidebar / RightSidebar)
│   ├── page/                 2  (PageView / ContentArea)
│   ├── layout/               2  (Header / MainContainer)
│   ├── graph/                2  (GraphView / GraphLayout)
│   ├── whiteboard/           1  (Whiteboard)
│   ├── search/               1  (TaskDashboard)
│   ├── settings/             3  (SettingsPage / ProUpgradePage / RecycleBinPage)
│   ├── commandpalette/       1  (CommandPalette)
│   ├── flashcard/            1  (FlashcardPage)
│   ├── onboarding/           1  (OnboardingPage)
│   ├── common/               3  (Icons / TablerIconPaths / ThemeManager)
│   ├── extensions/           2  (MathRenderer / MermaidRenderer)
│   ├── property/             1  (PropertyValueEditor)
│   └── query/                1  (QueryBuilder)
├── core/                    12 文件 (引擎层)
│   ├── models/               4  (Block / Page / Property / Constants)
│   ├── engine/               4  (BlockTree / OutlinerOps / OutlinerEngine / Validator)
│   ├── parser/               2  (MarkdownParser / MarkdownExporter)
│   ├── db/                   5  (DataStore / IndexStore / QueryEngine / DatalogEngine / LogicEngine)
│   └── persistence/          1  (FileRepository)
├── services/                15 文件 (服务层)
│   Workspace / File / Editor / Journal / Template /
│   Subscription / Collaboration / Encryption / CloudSync /
│   Export / Flashcard / TestData
├── plugins/                  4 文件 (插件框架)
│   LuniusPlugin / PluginAPI / PluginManager / BuiltinPlugins
├── state/                    1  (AppState)
├── utils/                    3  (i18n / UUID / ContentRenderer)
├── pages/                    1  (Index)
├── entryability/             1  (EntryAbility)
├── entryformability/         1  (EntryFormAbility)
├── entrybackupability/       1  (EntryBackupAbility)
├── shareability/             1  (ShareReceiveAbility)
└── widget/pages/             1  (WidgetCard)
```

---

## 构建说明

```bash
# 构建模式在 build-profile.json5 中配置
# 编译日志输出到工作区根目录的 errorlog.txt
# 构建产物: entry/build/default/outputs/default/entry-default-signed.hap
```

**系统要求**: HarmonyOS SDK 6.1.1(24) / DevEco Studio 5.0+ / API 12 模拟器或真机

**权限声明** (`module.json5`):
- `ohos.permission.DISTRIBUTED_DATASYNC` — 分布式协同编辑

**测试数据**: 首次启动自动创建 5 个页面（今日日志 / 项目文档 / dev/鸿蒙开发笔记 / HarmonyOS开发指南），含 TODO 标记、引用、嵌套 Block、KaTeX 公式、Mermaid 图表。

---

## 许可

MIT License
