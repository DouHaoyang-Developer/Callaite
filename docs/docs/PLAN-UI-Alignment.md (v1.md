# Callaite UI 对齐修复执行方案（PLAN-UI-Alignment）

- **状态**：草案 v1.1（待评审）
- **日期**：2026-09-26（v1.1 同日修订）
- **输入**：`REVIEW-UI-Obsidian-Alignment.md`（v1.0 评审报告，S1–S10 十大结构性差距 + 六域明细）
- **姊妹文档**：`PLAN-DocumentEditor.md`（编辑器主轴，4.3–4.5）
- **范围**：评审报告中 **S1 之外** 的全部差距项——即交互通路、死代码接线、系统适配、桌面细节、白板核心缺陷
- **明确不做**（有归属）：阅读态渲染/Live Preview（→ DocumentEditor 主轴）；Navigation 全壳迁移（→ ADR-004 搁置）；i18n 全量覆盖（→ 独立项，本文仅给方法，见 §7.1）

### v1.1 变更记录（外部评审采纳 + 决策落地）

| # | 修订 | 来源 |
|---|---|---|
| 1 | U1.5 清扫表修正：HomePage 移出（转生为新标签页，用户决策）；Toolbar 补挂载点；补 QueryView.ets(508L) 遗漏；清扫口径改为「未引用面 5,638 行」 | DeepSeek 核验二 P0-1/P2-5 |
| 2 | 新增 U1.6：SearchPanel 启用为全局搜索面板（用户决策 1） | 决策 1 |
| 3 | 新增 U1.7：HomePage 转生「新标签页」+ 启动页改恢复会话（用户决策 2） | 决策 2 |
| 4 | U2.1 拆分为 U2.1a（渲染层可寻址化 spike）+ U2.1b（AnchorRegistry）——BlockList 实为 Scroll 容器非 List，原方案前提不成立 | DeepSeek 核验二 P1-1 |
| 5 | U2.3 键位表重写（现动作列三处错误修正）+ cyclePriority 移入 SlashMenu（决策 3：块级操作归块上下文，Ctrl+Shift+P 留给未来真命令面板） | DeepSeek P1-5 + 决策 3 |
| 6 | U2.4 FindInPage 延后至编辑器 Phase 3 之后（避免与 overlay 改造双重做）；Ctrl+E 延后至 Phase 4（视图模式归编辑器） | DeepSeek 排程修正 |
| 7 | U3.4 接 RecycleEngine.ets（430L 完整软删除实现，原方案漏检）；删除语义统一：页面/块删除=进回收站无确认 | DeepSeek P0-3 |
| 8 | U3.5 CDN 清单补 PdfViewer（pdf.js 第四处）+ worker rawfile 化 spike；U5.2 补空画布初始化（删除演示数据注入） | DeepSeek P2-4/P2-7 |
| 9 | U4.2 新标签行为改为「打开新标签页（HomePage 转生）」，替换原 QuickSwitcher 方案 | 决策 2 |
| 10 | §7.2 排程重构：ShortcutService 独占窗口 + i18n 独立阶段（不穿插，防 diff 污染） | DeepSeek 排程修正 |
| 11 | tagFilter 事实修正：写入方为 ContentRenderer.ets:312-313（原「LeftSidebar 未写」结论不成立，死胡同成因另查） | DeepSeek P2-6 |
| 12 | 工时修正：U4 实为 9.5 天（原子项算术错误）；总量 26–33 → **31–36 天** | DeepSeek P2-8 |

---

## 0. 总则

### 0.1 修复原则（排序依据）

1. **先接线后新建**：未引用面 5,638 行（占 UI 层 ~17%）是现成器官，接上 1 天 ≈ 新写 5 天
2. **先通路后皮**：右键/键盘/锚点/Picker 四条通路决定「像不像桌面工具」，先于一切视觉打磨
3. **先撒谎后缺失**：6 处假状态每一处都在消耗用户信任，且其中 2 处有上架/法务风险，优先级内嵌于各包
4. **不与主轴抢时间**：本文档全部工作包均可在 DocumentEditor 各 Phase 之间插入执行，无相互依赖（唯二接口见 §7.3）

### 0.2 工作量总表

| 工作包 | 名称 | 子项 | 工时（净） |
|---|---|---|---|
| WP-U1 | 器官移植（未引用代码接线） | 7 | 6–8 天 |
| WP-U2 | 神经接通（锚点+键盘+快捷键） | 5 | 5–6 天 |
| WP-U3 | 诚信与适配（Picker+假状态+暗色+软删除+离线） | 5 | 7–9 天 |
| WP-U4 | 桌面细节（tooltip/标签/分屏/动效） | 6 | 9.5–10 天 |
| WP-U5 | 白板核心缺陷（连线锚定+多画布） | 2 | 4–5 天 |
| **合计** | | **25** | **31–36 天** |

单列：i18n 批量覆盖 5–8 天（**独立阶段执行，不穿插**——穿插会污染各工作包的 diff 归因）。

---

## 1. WBS 总览与依赖图

```
WP-U1.1 PageContextMenu 接线 ──┐
WP-U1.2 property 接线          ├─→ 无相互依赖，可任意顺序
WP-U1.3 BacklinkFilters 接线  │
WP-U1.4 块多选接通             │
WP-U1.5 死代码清扫             ┘

WP-U2.1 锚点服务 ←── WP-U2.5 反链/大纲/搜索接锚点
WP-U2.2 键盘导航件 ←─ WP-U2.4 FindInPage 重做（依赖 KeyNav）
WP-U2.3 快捷键重排（独立）

WP-U3.* 全部独立
WP-U4.5 分屏标签栈（独立）；U4.2 标签增强（独立）
WP-U5.1 连线锚定 → WP-U5.2 多画布（顺序无硬依赖，建议先 U5.2 后 U5.1）
```

**推荐执行序**：U1 → U2 →（编辑器 Phase 1–2）→ U3 → U4 → U5（穿插）。U1+U2 完成后应用即具备 Obsidian 的全部交互通路，体感跃迁最大。

---

## 2. WP-U1 器官移植（死代码接线，5–6 天）

### U1.1 PageContextMenu 接入 PageTree（解决 S2 主干）

**现状**：`PageContextMenu.ets`（297L）完整实现（重命名弹窗+删除确认+收藏+复制路径），0 引用；PageTree 无任何右键/长按。

**技术方案**：

ArkUI 标准 API 是 `bindContextMenu(builder, responseType)`。responseType 二选一（`RightClick`/`LongPress`），按形态绑定：

```typescript
// PageTree.ets RenderNode 内，Row 节点容器上：
.bindContextMenu(this.PageMenu(node.fullName), 
  Breakpoints.isDesktop() ? ResponseType.RightClick : ResponseType.LongPress)
```

- 桌面（medium/expanded）绑 `RightClick`，compact 绑 `LongPress`（触屏长按）
- **Phase 0 spike**：验证同节点能否链式双绑（RightClick + LongPress 同时生效）。若能，2in1 触屏双支持；不能则维持形态二选一（可接受）
- PageContextMenu 现有的自绘定位逻辑（positionX/positionY/isVisible）**整体删除**，bindContextMenu 自带定位与遮罩；保留其 MenuRow 列表、重命名弹窗、删除确认
- 菜单项按 Obsidian 文件树对齐补齐：打开 / 在新标签打开 / 重命名（F2）/ 收藏（toggle，修复「只加不减」）/ 复制完整路径 / **移入回收站**（复用 U3.4 软删除）/ 删除（红字，走确认）

**接线点**：PageTree RenderNode（页面行）+ LeftSidebar 收藏/最近行 + AllPages 列表（如保留该入口）。移动端 MobileMenuSheet 无需右键。

**验收**：
- [ ] 桌面右键页面 → 菜单出现在光标处，点外部关闭
- [ ] 手机长按页面 → 同一菜单
- [ ] 删除走确认对话框（替换现状 hover trash 直删）
- [ ] 收藏项可 toggle（已收藏时显示移除收藏）
- [ ] Esc/点遮罩关闭

**工时**：1 天（含 spike）｜**风险**：双绑不支持 → 降级方案已备

### U1.2 property 三件套接线（1,516 行复活）

**现状**：PropertyEditor/PropertyConfig/PropertyValueEditor（1083L）+ DatePicker（433L）0 引用；块属性（SCHEDULED/DEADLINE/tags/type::）当前只能靠手敲文本。

**方案**：接入点选 **BlockView ActionsBar**，而非右栏（Obsidian 的属性编辑入口就在块上）：

1. `BlockView.ets` ActionsBar 增加第四个图标 `list-details`（属性）→ 半模态 `bindSheet` 展示 `PropertyEditor({ blockUuid })`
2. `PropertyEditor` 已有 `@Prop @Watch blockUuid`，直接可用；其内部 `openDatePicker()` → DatePicker 的调用链原样激活
3. 属性写入后 `bumpBlocksVersion()` 已有链路会刷新 PageView 头部只读属性区（PageView 展示页面属性、PropertyEditor 展示块属性，互不冲突）
4. **SlashMenu 联动**（顺手项）：SlashMenu 的 SCHEDULED/DEADLINE 命令当前写死今天，改为拉起 DatePicker（同一组件）

**验收**：
- [ ] 块 hover → 属性按钮 → sheet 弹出，显示该块全部属性
- [ ] 添加 SCHEDULED(date) 类型属性 → 点值弹日期选择器 → 写入后 PageView 头部出现
- [ ] 手机同路径可用

**工时**：1–1.5 天｜**风险**：PropertyEditor 若与当前 BlockData 模型有字段漂移（4.1.x 编写），补齐映射即可

### U1.3 BacklinkFilters 接线 + 右侧栏三装饰图标激活

**现状**：RightSidebar 反链工具行 filter/search/plus 三个图标无 onClick；BacklinkFilters（331L）完整筛选/排序 0 引用。

**方案**：
- filter 图标 → 切换 BacklinkFilters 面板显隐（插入在反链标题之下，展开态默认收起）
- search 图标 → 打开全局 SearchPanel 并预填当前页面名（`callaite_searchPreload` 新键）
- plus 图标 → 在当前页**新建块并反链本页**（`[[当前页]] ` 前缀插入）——Obsidian 无此交互，取自 Logseq「在反链面板快速添加引用」，实用且成本 1 小时

**验收**：三个图标全部可点且有真实结果；筛选「按标签」下拉列出真实标签。

**工时**：0.5–1 天

### U1.4 块多选接通（BlockSelection 复活）

**现状**：`EditorService.toggleSelection` 0 调用；BlockSelection 浮条（272L）实现完整但永不出现。

**方案**：
1. `BlockView` bullet 区加手势：桌面 `Ctrl + onClick`、手机长按块 → `EditorService.toggleSelection(uuid)`（注意与 U1.1 的 bindContextMenu 长按冲突：块级长按=选中，树级长按=菜单，不冲突；同一节点内长按优先级用 gesture 组的 priority 控制）
2. 选中态视觉：块根容器背景 `accent_soft`（见 U4.6 选中态统一）
3. `BlockSelection` 浮条当前挂在 BlockList 尾部 → 移到 MainContainer 顶部 Stack 层（与 FindInPage 同层），避免跟随滚动
4. ShortcutService 增 `Ctrl+A` → `selectAll(currentPageId)`，**守卫**：`EditorService.getFocusedBlockUuid() === ''` 才触发（焦点在编辑器时归文本全选，见 U2.3 冲突表）

**验收**：Ctrl+点选三个块 → 底部浮条出现「3 个块」→ 批量缩进/删除/复制 markdown 全链路可用；手机长按同效。

**工时**：1 天

### U1.5 未引用代码清扫（执行评审第六节决策矩阵）

**清扫口径（v1.1 修正）**：三态分类——**接线**（有完整价值，别的子项做）、**删除**（负资产）、**冻结**（未来有主但当前无消费方）。总未引用面 **5,638 行**（含 services 层 RecycleEngine/部分 Query 系），本表为组件层。

| 文件 | 处置 | 理由 |
|---|---|---|
| MobileToolbar.ets (197L) | **删** | 与 MarkdownToolbar 双实现冲突且绕过编辑器通道 |
| RichBlockEditor.ets (114L) | **删** | 被 IntegralEditor 取代 |
| TaskSchedulePanel.ets (312L) | **删** | TaskDashboard 已覆盖同场景 |
| QueryBuilder.ets (216L) + **QueryView.ets (508L，v1.0 遗漏)** + PageView 内 Query 路由 builder | **删**（QueryEngine 保留） | 路由不可达；查询能力经 InlineQueryBlock 仍可达 |
| AllPagesPage.ets (426L) | **删**（PageView 内建 builder 为准） | 二选一，保留体积小的 |
| Toolbar.ets (68L) | **删**（含挂载点） | **活代码修正**：ContentArea:69 无条件挂载（非零引用）；但功能与 MarkdownToolbar（移动）+ Ctrl+Z/Y（桌面）完全重复，且 refreshState 仅 aboutToAppear 调用（onPageShow 对 @Component 无效）导致状态恒陈旧——删组件 + 删 ContentArea 挂载行 |
| HomePage.ets (108L) | **改造保留**（见 U1.7） | 活代码（AppState:189 启动固定 'Home'），v1.0 误判为不可达 |
| LeftSidebar 内部 ~200L（NavRow/getNavItems/StripIcon/ViewSwitchIcon/TreeToolIcon/toggleCollapseAll/createNewNote/createNewNamespace） | **删** | build 已不引用 |
| AutoComplete.ets (329L) | **冻结不删** | 标注 `@deprecated 待 DocumentEditor 重做`，知识在 |
| BlockDragHandler.ets (538L) | **冻结不删** | 同上，块拖拽在 DocumentEditor Phase 3 复用 |

**执行规程（v1.1 强化）**：删除 = 删文件 **+ 删全部 import 引用点**（v1.0 只写了删文件，编译器兜底不够——引用点残留会误导后续评审，正是本次外部核验抓到误判的成因之一）。单独 commit（`移除未接线的历史组件`），一个一个删并编译验证。

**工时**：0.5 天（含全量编译回归）｜**风险**：误删仍被 import 的符号 → 编译器兜底

### U1.6 SearchPanel 启用为全局搜索面板（用户决策 1）

**现状（v1.0 误判修正）**：SearchPanel.ets（368L）**从未挂载**——`callaite_searchPanelOpen` 键驱动的渲染位在 ContentArea:98 挂的是 CommandPalette（页面切换器）。SearchPanel 的完整实现（页面名+块内容搜索/匹配高亮/tagFilter 消费/空查询显示最近）从未可达。`AppState.setSearchPanelOpen()` 的多个调用点（MobileBottomBar 搜索钮、右栏 search 图标占位）实际打开的都是 CommandPalette。

**方案**：
1. ContentArea 浮层渲染分支拆分：`searchPanelOpen` → 渲染 **SearchPanel**（真搜索）；CommandPalette 由独立键 `callaite_paletteOpen` 驱动（现 `Ctrl+K`/`Ctrl+P` 改写此键）
2. 两个面板共处 MainContainer 顶部 Stack 层，互斥打开（开一关另）
3. SearchPanel 接 U2.2 键盘导航（↑↓/Enter/Esc）与 U2.5 锚点跳转（结果行 pendingAnchor）
4. `onChange` 加 200ms 防抖（现每击键全库遍历）

**验收**：Ctrl+F → 输入关键词 → ↑↓ 选择 → Enter → 跳到结果块并高亮；#标签入口（tagFilter）真实过滤。

**工时**：1 天（挂载拆分 0.5 + 防抖/键盘/锚点接线 0.5）

### U1.7 HomePage 转生「新标签页」+ 启动会话恢复（用户决策 2）

**现状**：HomePage 是启动落地页（AppState:189 固定 'Home'，展示版本号/快捷键/onboarding 文案）；Obsidian 语义的「新标签页」缺失（新标签固定开 Journal）。

**方案**：
1. **HomePage 改造为「新标签页」内容**：删 onboarding 文案（引导语义移除，那是 OnboardingPage 的职责）；改为「快速开始」面板——新建 Markdown 笔记/新建白板/新建大纲笔记三入口（复用 NewFileDialog 动作）+ 最近页面 5 行列表（`callaite_recentPages`）+ 回今日 Journal 按钮
2. **TabState.newTab() 默认 page = 'Home'**：TabBar/TabBar 菜单/MobileBottomBar/CommandPalette 兜底行全部改（现传 'Journal'）——新标签 = 空白起点 + 快速开始，选定目标后该标签变身（TabState.updateTab 已有激活语义，补 `setTabPage(id, page)` 一个 API）
3. **启动页逻辑改会话恢复**：AppState.initialize 不再固定 'Home'——改读 TabState 持久化的激活标签页（`TabState.getTabs()` + activeTabId → currentPage）；无标签/首装 → 'Journal'（OnboardingPage 完成后的落点不变）
4. StatePersistence 恢复时序确认：TabState 键在 STATE_KEYS 之外（自带 JSON 持久化），EntryAbility 恢复顺序需 TabState 先于 AppState.initialize（现有顺序已是，仅需验证）

**验收**：启动恢复上次会话的页面与标签列表；Ctrl+T/＋ → 新标签页显示快速开始；从快速开始打开笔记后标签标题随内容变化；重启后新标签页若未使用则不再恢复（空 Home 标签视为临时态，持久化时过滤——`persist` 前置过滤 `page !== 'Home' || pinned`）。

**工时**：1 天

---

## 3. WP-U2 神经接通（5–6 天）

### U2.1 块锚点服务（核心基建，解决 S3）——v1.1 拆分为 spike + 实现

**现状（v1.0 前提错误修正）**：BlockList 容器是 `Scroll`（LazyForEach 挂在 Scroll 内），**不是 List**——`scrollToIndex` 无处可调；滚动宿主是 ContentArea 的 `Scroll`（`scrollId()`）。原方案「List.scrollToIndex 两阶段定位」前提不成立。

#### U2.1a 渲染层可寻址化 spike（半天，先行判据）

两个候选路线，spike 后择一：

| 路线 | 改造 | 优势 | 风险 |
|---|---|---|---|
| **A：Scroll → List** | BlockList 顶层 LazyForEach 从 Scroll 迁到 List（List 天然支持 LazyForEach），保留 `scroller` 引用 → `scrollToIndex(index, smooth)` | 官方虚拟化容器，锚定一步到位 | List 与现有布局/padding/嵌套子树递归的兼容回归；embedded 模式（JournalFeed 内嵌）需保持 Scroll |
| **B：全局 offset 注册表** | 维持 Scroll；AnchorRegistry 记录「顶层项全局 y」（LazyForEach 项 onAreaChange 上报），滚动 = `scroller.scrollTo({yOffset: topY - 120})` | 零容器迁移，回归面小 | 视口外 LazyForEach 未物化的项**没有 y**——需先 `ScrollEdge` 粗滚（或估算 index × 平均行高）触发物化，再精调；两阶段时延不如路线 A 稳定 |

**判据**：路线 A 迁移后 300 块页滚动帧率不降、embedded 模式不破 → 选 A；否则 B（B 的粗滚-精调两跳时延需 ≤ 500ms 达标）。

#### U2.1b AnchorRegistry（无论 A/B 都需要）

```typescript
export class AnchorRegistry {
  /** 块 uuid → 视口全局 y（onAreaChange 上报，≥2vp 变化才写） */
  private static tops: Map<string, number> = new Map();
  static report(uuid: string, globalY: number): void { ... }
  static lookup(uuid: string): number { ... }

  /** 定位：路线A=scrollToIndex+精调；路线B=粗滚物化+精调 */
  static locate(targetUuid: string, ...): void { ... }
  // 高亮协议不变：callaite_highlightUuid，200ms 淡入 / 2s 淡出
}
```

**接线**（不变）：BlockView onAreaChange 上报；跨页 `callaite_pendingAnchor`；折叠目标 → 定位顶层祖先。**风险 R7 同前**。

**工时**：spike 0.5 + 实现 1.5 = **2 天**（与 v1.0 持平，spike 占原预算）

### U2.2 键盘导航通用件 OverlayKeyRouter（解决 S4）

**现状**：四个键盘型浮层无键盘事件；CommandPalette 渲染假提示条。

**设计**（复用仓库已验证的两条模式：`onKeyPreIme` 拦截 + AppStorage 版本号触发）：

```typescript
// utils/OverlayKeyRouter.ets
export class OverlayKeyRouter {
  static handle(event: KeyEvent): boolean {
    // 依次检查各浮层是否打开（AppStorage 布尔）：
    // paletteOpen → searchPanelOpen → slashMenuOpen → findInPageOpen → mobileMenuOpen
    const key = event.key;   // 'ArrowUp' | 'ArrowDown' | 'Enter' | 'Escape'
    if (!isOverlayOpen() || !isNavKey(key)) { return false; }
    const ch = AppStorage.get<number>('callaite_overlayKeySeq') ?? 0;
    AppStorage.setOrCreate('callaite_overlayKey', key);
    AppStorage.setOrCreate('callaite_overlayKeySeq', ch + 1); // 版本号驱动 @Watch
    return true; // 消费掉，不再下沉
  }
}

// ContentArea.onKeyPreIme 首行插入：
if (OverlayKeyRouter.handle(event)) { return true; }
```

各浮层接入（以 CommandPalette 为例）：

```typescript
@StorageLink('callaite_overlayKeySeq') @Watch('onOverlayKey') keySeq: number = 0;
@State selectedIdx: number = 0;

onOverlayKey(): void {
  const key = AppStorage.get<string>('callaite_overlayKey') ?? '';
  if (key === 'ArrowDown') { this.selectedIdx = min(this.selectedIdx + 1, n - 1); }
  if (key === 'ArrowUp')   { this.selectedIdx = max(this.selectedIdx - 1, 0); }
  if (key === 'Enter')     { this.open(this.results[this.selectedIdx]); }
  if (key === 'Escape')    { this.close(); }
  // 滚动跟随：scroller.scrollToIndex(selectedIdx)
}
```

选中行视觉：`surface2` 背景 + 左侧 2vp `primary` 竖条（Obsidian 同款）。

**接入清单**：CommandPalette、SearchPanel、SlashMenu、FindInPage、MobileMenuSheet（跳过）→ 共 4 个。SlashMenu 额外收益：filter 输入与选择共存（AppStorage 通道与 TextInput 焦点无耦合，天然不抢焦点）。

**验收**：
- [ ] Ctrl+K → 输入 → ↑↓ 移动选中 → Enter 打开 → 全程手不离开键盘
- [ ] Esc 在任何浮层打开时关闭该浮层
- [ ] CommandPalette 底部键位提示条从「假」变「真」
- [ ] SlashMenu 同上（含分类间跳转）

**工时**：1.5 天（Router 0.5 + 四浮层接入 1）｜**风险**：onKeyPreIme 对 Enter 的拦截发生在 IME 之前，需确认中文输入法组词回车上屏不受影响——**守卫**：仅 `overlayOpen` 状态路由，输入框失焦态无影响；Phase 0 加拼音组词回车用例

### U2.3 快捷键重排（v1.1 键位表重写——现动作列经外部核验修正）

**现状（实测）**：Ctrl+K 与 Ctrl+F 同开 CommandPalette（页面切换器）；Ctrl+P = cyclePriority（切换优先级）；Ctrl+O/E 无绑定。

**目标键位表**：

| 键 | 现动作（核验修正） | 新动作 | 备注 |
|---|---|---|---|
| Ctrl+K | 打开 CommandPalette | **QuickSwitcher**（CommandPalette 更名，行为不变） | 现状保持，仅正名 |
| Ctrl+P | cyclePriority | **同 Ctrl+K**（QuickSwitcher 等价键，VS Code 惯例） | cyclePriority 让位（见下） |
| Ctrl+O | 无 | 同 Ctrl+K（Obsidian 惯例位，三键等价） | |
| Ctrl+F | 打开 CommandPalette | **SearchPanel（全局搜索）** | 用户决策 1；U1.6 挂载 |
| Ctrl+Shift+F | 无 | **FindInPage（页内搜索）** | U2.4 重做后归位；Obsidian 语义里 Ctrl+F 是页内——若后续要严格对齐，与 Ctrl+Shift+F 对调成本为零（注册表一行） |
| Ctrl+A | 无（透传文本全选） | 块全选（守卫：无块焦点时，见 U1.4） | |
| Ctrl+E | 无 | ~~视图模式循环~~ **延后至 DocumentEditor Phase 4**（视图模式归编辑器管，避免键位在编辑器重铸前后两次改语义） | 排程修正 |
| ~~Ctrl+P（原）~~ cyclePriority | — | **移入 SlashMenu 命令「切换优先级 A/B/C」** | 用户决策 3 裁决：块级操作归块上下文；Ctrl+Shift+P 留给未来真命令面板 |

配套：OnboardingPage 快捷键页文案改为「Ctrl+K/P/O 快速切换 · Ctrl+F 全局搜索 · Ctrl+Shift+F 页内搜索」；ShortcutSettings 读注册表自动跟随。

**工时**：0.5 天（含 Onboarding 文案与 CommandPalette 更名的引用清理；SlashMenu 加命令 0.2 天含在 U1.2 联动内）

### U2.4 FindInPage 重做（**v1.1 排程修正：延后至编辑器 Phase 3 之后**）

> 延后理由：DocumentEditor Phase 3 将重做全部 overlay 挂载层（SlashMenu/AC/FindInPage 移入编辑器协议）——现在重做 FindInPage 会在 Phase 3 被二次改造，同一模块两轮 churn。键位 Ctrl+Shift+F 先注册（打开即占位提示「编辑器重铸后可用」），组件本体随编辑器节奏走。

**现状**：内部 isVisible 恒 false，功能死亡；navigate 只改计数。

**方案**（复用 U2.1/U2.2 两基建，收益最大的一项）：
1. 显隐控制反转：删除内部 isVisible，`@StorageLink('callaite_findInPageOpen')` 由 ShortcutService（Ctrl+F）与 BlockList 工具行控制
2. 渲染位置：从 BlockList 内联移到 MainContainer 顶部 Stack（ContentArea 之上，右上角浮动小卡，Obsidian 布局位）
3. navigatePrev/Next：matchedUuids[current] → `AnchorRegistry.locate()` + 高亮（复用 U2.1）；匹配块内的**文本级高亮**沿用 SearchPanel 的 splitHighlight 段渲染（把匹配块临时切到高亮样式）
4. Enter=下一个 / Shift+Enter=上一个 / Esc=关闭（走 U2.2 通道）
5. 计数「N/M」保持；空结果显示「无匹配」

**验收**：Ctrl+F → 输入 → Enter 循环跳转，每次跳转滚动+块高亮+块内文本高亮；Esc 关闭。

**工时**：1 天

### U2.5 反链/大纲/搜索结果接锚点（收割 U2.1）

一行级改造 ×4 处：
- RightSidebar 反链行 onClick → `setCurrentPage(page) + pendingAnchor=blockUuid`
- RightSidebar 大纲行 onClick → 同上（同页时只滚不切）
- SearchPanel 结果行 onClick → 补 `pendingAnchor=blockUuid`
- TaskDashboard 任务行 onClick → 补 `pendingAnchor`

**验收**：四处点击全部落到具体块并高亮——「到页不到块」从应用中消失。

**工时**：0.5 天

---

## 4. WP-U3 诚信与适配（6–8 天）

### U3.1 系统文件 Picker 四处接入（解决 S5）

统一走 `@kit.CoreFileKit` 的 `picker.DocumentViewPicker`：

| 场景 | API | 后续动作 |
|---|---|---|
| ImportDialog 导入 .md | `documentSelect({ fileSuffixFilters: ['md','markdown'], maxSelectNumber: 1 })` | 读 URI → 复制入 graph → ImportService 现有链路（**删除手输路径 TextInput**） |
| ExportDialog 导出 | `documentSave({ defaultFileName: '<页面名>.md', fileSuffixFilters: [...] })` | 写 URI（ExportService 改为接受可写 fd/uri） |
| PdfPage 打开 PDF | `documentSelect({ fileSuffixFilters: ['pdf'] })` | 复制到 graph 根 → PdfViewer 现有链路（**删除「请放入目录」提示**） |
| MarkdownToolbar 插入文件/附件（桌面/移动通用） | `documentSelect({ fileSuffixFilters: ['png','jpg','jpeg','webp','pdf','md'] })` | 图片复制到 `graph/attachments/` → 插入 `![[attachments/xxx.png]]`；md 插入 `[[页面名]]`；pdf 插入 `![[xxx.pdf]]` |

交互形态：对话框内按钮「选择文件…」替代 TextInput；选中后显示文件名 chip（可清除重选）。

**注意**：picker 返回 URI 的临时读权限只在本次会话有效，导入必须在选择后立即完成复制——正好符合流程。

**验收**：手机上不接电脑完成 导入一个 .md / 导出一个 .md / 打开一个 PDF / 插入一张图 四个任务。

**工时**：2 天｜**风险**：低（API 成熟）；documentSave 在部分模拟器行为异常 → 真机验证

### U3.2 六处假状态清除（信任级）

| # | 位置 | 方案 | 备注 |
|---|---|---|---|
| 1 | CommandPalette 假键位提示条 | U2.2 落地后自然成真 | 已覆盖 |
| 2 | StatusBar 假「已同步」绿点 | 接真状态：`CloudSyncService.getFileSyncState() + getLastSyncTime()` → 三态渲染：同步中（转圈图标）/ 已同步 + 相对时间（「3 分钟前」）/ 未启用（灰色 cloud-off，点击跳设置） | 状态刷新：blocksVersion bump 时触发 |
| 3 | VaultSwitcher 假语言行 | 接真：行 → 点击展开语言二选一（简中/English），调 `I18n.setLanguage()` + 重启提示（或即时生效，取决于 i18n 实现） | 若即时生效成本高，v1 先删除该行 |
| 4 | ProUpgradePage「PDF 标注 ✓」 | **删除该行**（功能不存在，且属付费宣称——法务风险） | 等 PDF 标注真做出来再加回 |
| 5 | 版本号三处不一致（1.0.0 / 1.1.1 / 实际 4.2.5） | `bundleManager.getBundleInfoForSelf()` → versionName → AppStorage `callaite_appVersion`，SettingsPage/VaultSwitcher/About 全部改读此键 | **依赖**：app.json5 的 versionName 要先改成真实版本（本就是发布阻断项之一，顺手一起） |
| 6 | RightSidebar 三装饰图标 | U1.3 已覆盖 | 已覆盖 |
| 7 | PageView 假回收站空态 | U3.4 软删除后自然成真 | 已覆盖 |

**工时**：1.5 天（#2 占 1 天：真同步状态机）

### U3.3 暗色模式 token 化（硬编码色清扫）

**新增 Token**（`base/element/color.json` + `dark/element/color.json` 双份，见附录 C 全表）：

| Token | 用途 | 现硬编码值 |
|---|---|---|
| `graph_edge` | 图谱边 | #D1D5DB |
| `graph_label` | 图谱标签 | #1A1A1A（暗色下不可见的元凶） |
| `graph_label_stroke` | 标签描边 | #FFFFFF |
| `wb_grid` | 白板网格线 | 固定浅灰 |
| `wb_shape_fill` / `wb_shape_stroke` | 白板形状默认双色 | 固定蓝/青 |
| `flash_progress` / `flash_grade_*` | 闪卡进度条与四档评分色 | 固定绿/四色 |
| `task_marker_bg` 系列 | TaskDashboard 标记底 | 已有部分 token，补齐缺口 |

**规则**：本次起 code review 检查项——`rg "#[0-9A-Fa-f]{6}" components/` 新增彩色硬编码一律打回（黑白透明 rgba 例外）。

**验收**：暗色模式下图谱标签清晰可读；白板/闪卡/任务面板在明暗两模式下全部走主题。

**工时**：1 天（含两套 json 与所有替换点）

### U3.4 回收站软删除（假空态 → 真功能）——v1.1：先审 RecycleEngine

**现状（v1.0 漏检修正）**：`services/RecycleEngine.ets`（430L）**已存在完整软删除实现**（含 restoreBlock / 恢复路径），0 引用——又一个没插电的器官。本子项第一步是**审计它与 U3.4 设计的差距**，接线为主、补缺为辅：

1. 审计 RecycleEngine：删除路径（页面+块）、.trash 目录约定（或其自有方案）、恢复事务、索引联动——与下方设计比对，冲突处**以现实现为准调整方案**（现实现已经过编译期检验）
2. `DataStore.deletePage` / 块删除改走 RecycleEngine（若其接口齐备则纯接线）
3. 缺什么补什么：`.trash/` 加入全库扫描排除清单（WorkspaceService 索建、PdfPage listFileSync、白板扫描）；RecycleBinPage 读回收站列表（名称/时间/大小）→ 恢复 / 彻底删除（确认+unlink）/ 清空
4. **删除语义统一（v1.1 裁定）**：页面删除、块删除、画布删除 = **一律进回收站，无确认弹窗**（可恢复即安全）；「彻底删除」仅存在于回收站内（需确认）。原 U1.1 菜单里「删除（红字，走确认）」随之改为「移入回收站」
5. PageView 的 Recycle 路由接真 RecycleBinPage（假空态代码删除）

**验收**：删除页面/块/画布 → 回收站可见 → 恢复后内容完好；重启后回收站仍在；全应用无「不可恢复的直接删除」入口（文件树 hover trash 直删同步改造）。

**工时**：1–1.5 天（审计 0.5 + 接线补缺 0.5–1）｜**风险**：RecycleEngine 与当前 DataStore API 有 4.1.x 漂移 → 补适配层

### U3.5 CDN 离线化（解决 S10）——v1.1 补第四处

**现状**：**四处** CDN 依赖——CodeBlock(highlight.js)/MathRenderer(KaTeX)/MermaidRenderer(Mermaid)（jsdelivr/cdnjs）+ **PdfViewer(pdf.js)（v1.0 遗漏）**。

**方案**：
1. 库打包进 `resources/rawfile/vendor/`：highlight、katex（+fonts/）、mermaid、**pdf.js（pdfjs-dist 的 pdf.min.js + pdf.worker.min.js）**
2. 四个组件从「拼 HTML 字符串」改为「rawfile 模板 + 注入」：
   - 模板 `rawfile/templates/*.html`，内相对引用（ArkWeb $rawfile 相对路径解析——**Phase 0 spike 验证**，失败则 `onInterceptRequest` 自建协议路由）
   - **pdf.js worker 是难点**：worker 脚本加载策略（`workerSrc` 指向 rawfile 内路径是否被 ArkWeb 接受）单独 spike；fallback = `GlobalWorkerOptions.workerPort` 用主线程模式（性能降级可接受，PDF 渲染非热路径）
   - `runJavaScript(JSON.stringify(...))` 参数化注入（注入安全闭环）
3. KaTeX 字体子目录随 rawfile 保留相对结构
4. 顺手项：CodeBlock/MathRenderer 纯文本回退态直接 Text 渲染省实例

**验收**：**飞行模式（断网）下**：代码块高亮、数学公式、Mermaid 图全部正常渲染；**打开一个本地 PDF 正常翻页**（v1.0 验收缺口补上）。

**工时**：2.5 天（含两个 spike 与四组件改造，pdf.js worker 占 0.5）｜**风险**：rawfile 相对路径 + worker 加载双 spike 先行；fallback（onInterceptRequest / 主线程 worker）均有把握

---

## 5. WP-U4 桌面细节（6–8 天）

### U4.1 Tooltip 全局层

**设计**：单例浮层（不做每按钮 bindPopup ×N）：

```typescript
// components/common/TooltipLayer.ets（挂 MainContainer 顶部 Stack）
// API：TooltipLayer.show(text, globalX, globalY) / hide()
// 宿主接入（一行）：
.onHover((h: boolean) => h ? TooltipLayer.show('快速切换  Ctrl+P', ev.globalX, ev.globalY) : TooltipLayer.hide())
```

- 400ms 延迟出现、即时消失；GlassSurface THIN 材质小卡（radius 8, fontSize 12）
- **接入清单**：Ribbon 全部 10 图标（含快捷键文本）、TabBar 关闭/新建/菜单、StatusBar 同步态、SplitDivider（「拖拽调整 · 双击复位」）、块 ActionsBar 三图标、白板工具栏
- 移动端自动不触发（onHover 不发生）——零成本平台隔离

**工时**：1.5 天（层 0.5 + 接入 1）｜**验收**：桌面悬停 Ribbon 任意图标 400ms 出现玻璃提示卡含名称+快捷键。

### U4.2 标签页增强（右键/拖拽/中键/pin）

1. **右键菜单**（bindContextMenu，复用 U1.1 模式）：固定标签/取消固定、关闭、关闭其他、关闭右侧全部、复制文件路径
2. **pin UI**：TabInfo.pinned 已有死数据 → 右键 toggle；pinned 标签渲染：宽度收缩至 48vp、无关闭按钮、左侧 pin 小图标；排序时 pinned 恒前置
3. **中键关闭**：`.onMouseEvent` button === Middle → closeTab
4. **拖拽排序**：TabBar 的 Row+ForEach 改 `List(horizontal) + ListItem.draggable(true)`，onDragStart 携带 tabId，目标项 onDrop → `TabState.moveTab(from, to)`
   - **Phase 0 spike**：水平 List 拖拽排序在当前 SDK 的成熟度；不行则 fallback：长按进入排序模式 + ←→ 箭头移动（体验降级但可用）
5. chevron 菜单移到右侧（新建按钮之左），菜单项从 3 → 6（同右键）
6. **新标签行为**（v1.1 依用户决策 2 改）：打开 **HomePage 转生的「新标签页」**（见 U1.7）——`newTab()` 默认 page='Home'，快速开始面板选定目标后 `setTabPage` 填充。原「开 QuickSwitcher」方案废弃（新标签页内含最近列表，比切换器更符合「先展示再选择」的移动/桌面统一语义）

**工时**：2–2.5 天｜**验收**：右键/pin/中键/拖拽全通；pinned 标签不受「关闭其他」影响。

### U4.3 TabOverview 内容缩略图（🔴 项）

v1 轻量方案（不做真截图，成本差 10 倍）：
- 卡片结构改为：标题行（图标+页名）+ **内容预览区**（取该页前 3 个块的纯文本，fontSize 10，muted 色，行距紧缩）+ 底部页脚（块数）
- 数据：`WorkspaceService.getPageBlocks(page).slice(0, 3)` 在 aboutToAppear 一次性取
- 列数自适应：compact 2 列、medium 3 列、expanded 4 列（Grid colsCallback）
- 卡片下滑手势关闭（ListItem swipe，可选）
- 空页面显示居中「空白」水印字

真截图（PixelMap 捕获渲染树）列为 v2 backlog。

**验收**：打开总览，扫一眼即可凭内容（而非仅标题）区分标签。

**工时**：1 天

### U4.4 侧栏开合动画 + resizer hover 线

- 侧栏容器加 `transition(translate x ±40 + opacity)`（FloatingPanel 已有同款参数可直接抄，asymmetric 220/160ms Friction）
- resizer：onHover → 竖线变 `primary` 色并加宽到 2vp（SplitDivider 同款已在，侧栏 resizer 补齐）
- 移动端 FloatingPanel 抽屉加**边缘右滑打开**手势：MainContainer 根 `.gesture(PanGesture` 从左缘 24vp 内起手 → 逐步拖出侧栏（进度跟随，松手判定 >50% 展开或回弹）——解决评审 4.2 MobileHeader 无边缘手势项

**工时**：1.5 天（边缘手势占 1 天，可用性要实测调参）

### U4.5 分屏副窗格自绘标签栈（去 Select）

**方案**：
1. 新 `state/PaneState.ets`（仿 TabState 模式）：`paneRight: { tabs: TabInfo[], activeTabId }`，AppStorage JSON 持久化 + 版本号触发
2. MainContainer 副窗格：原生 Select 删除 → 渲染迷你 TabBar（复用 TabBar 的标签卡片 builder，高度 32 缩水版）+ 内容区渲染 `paneRight.activeTab.page`
3. 副窗格内容点击链接 → 在**副窗格自己的栈**里开新标签（Obsidian 语义），主窗格不动
4. 「拖标签到副窗格」跨窗格拖拽 = v2（依赖 ArkUI 跨 List 拖拽成熟度，先不做）
5. split down（上下分屏）= v2 backlog

**验收**：副窗格可开多个标签独立切换，重启后保持；视觉与主 TabBar 一致。

**工时**：2 天

### U4.6 选中态统一 + 块 hover 行为

1. **视觉语言裁定**（写进 ThemeManager 头注释）：`surface2` = hover/按压（瞬时态）；`accent_soft` + `primary` 左竖条 = 选中/激活（持久态）。全应用清扫：LeftSidebar 收藏/最近行（当前 accent_soft ✓ 保持）、PageTree 当前页（surface2 → accent_soft）、SlashMenu 选中行（U2.2 新增即按此）
2. **块 ActionsBar hover 显隐**：桌面默认 `opacity(0)`，块根 onHover → 1（150ms 过渡）；compact 恒显（触屏无 hover）
3. **块删除确认**：ActionsBar 删除 → 长按删除进回收站（U3.4 软删除统一语义，不再需要确认弹窗——回收站可恢复）
4. MarkdownToolbar 长按循环变体：长按 H 循环 H1→H6、长按 B 循环 bold/italic/highlight/strike（LongPressGesture 1.2s + UI 提示当前档位小浮签）

**工时**：1 天

---

## 6. WP-U5 白板核心缺陷（4–5 天）

### U5.1 连线锚定（🔴 核心交互缺陷）——v1.1 修正数据模型事实

**现状（核验修正）**：`WbConnectorData` 的 `fromShapeId / toShapeId` **已存在**（WbConnector.ets:15-23）——不是「纯绝对坐标」；旧版字段为 `fromPoint: {x, y}` / `toPoint: {x, y}`（单点非对角点对）。缺陷本质：字段在但**渲染读的是绝对坐标路径**（WbConnector.ets:61-205 读取处），移动形状时无跟随逻辑。

**数据模型（增量，v1.1 改为保守迁移）**：

```typescript
interface WbConnectorData {
  id: string;
  type: string;            // 保留现字段名（含 'line' 等枚举），不重命名
  fromShapeId: string;     // 已有：真形状引用（空/旧数据 = 裸连线模式）
  toShapeId: string;
  fromPoint?: { x: number; y: number };   // 旧字段保留：裸连线坐标 / 未吸附兜底
  toPoint?: { x: number; y: number };
  style: string; color: string; arrowStart: boolean; arrowEnd: boolean;
}
```

- **渲染派生**：`fromShapeId` 非空 → 端点 = `edgeIntersection(shapeRect(fromShapeId), dir(两形状中心连线))`（CanvasMath 新增工具函数）；为空 → 回退 `fromPoint` 绝对坐标（现行为，零回归）
- 形状移动/缩放 → 重绘自动跟随；**不新增 version 字段、不改字段名**——判定线：`fromShapeId` 非空即锚定态
- **旧数据迁移**：加载时 `fromShapeId` 为空但画布内存在距 `fromPoint` < 200vp 的形状 → 自动吸附（写回 fromShapeId）；无命中保持裸连线（用户画在空白处的自由线段，语义合法）
- 锚点八方向手动微调 = v2；v1 自动选向已覆盖 95% 场景

**验收**：画两个形状连线 → 拖动任一形状 → 连线始终粘附边缘且方向正确；旧画布（fromPoint 时代）打开后：形状附近的线自动吸附、自由线段原样保留。

**工时**：**3–4 天**（v1.0 低估：忽略 WbConnector 渲染层 61-205 的重写量与旧格式双读）

### U5.2 多画布——v1.1 补空画布初始化

**现状**：全局单 default.canvas，新建=归档旧的（S7）+ **新画布创建时注入演示数据**（NewFileDialog:65-67 触发的路径含 shapes/connectors 示例，v1.0 遗漏）；WhiteboardFileService 本身已是按 filePath 的 load/save——**地基是好的，只是 UI 层锁死了**。

**方案**：
1. `WhiteboardFileService.listCanvases()`：扫 graph 根 `*.canvas`
2. **空画布工厂**：`createEmptyCanvas(name)` —— shapes/connectors/strokes/pageRefs 全空数组 + 初始 viewport（替代演示数据注入；demo 数据仅保留在 Onboarding 首次演示场景或彻底删除）
3. Ribbon 'Whiteboards' 路由 → 打开「最近画布」（AppStorage `callaite_lastCanvas`），无则 default
4. NewFileDialog「新建白板」→ 弹命名输入（复用重命名弹窗 builder）→ `canvas-<N>.canvas`，**删除归档逻辑**
5. WhiteboardStatusBar 加画布切换器：当前名 + chevron → Menu 列出全部画布（选中切换 + 长按/右键重命名、移入回收站）
6. 删除画布 → U3.4 软删除路径
7. WbPageRef 添加入口：工具栏「页面引用」工具 → 拉起 QuickSwitcher 选页 → 在画布点击处放置 WbPageRef 卡片

**验收**：创建 3 个画布，互不覆盖，**全部为空白画布**，重启记住最近的；画布内可放置页面引用卡。

**工时**：2–3 天

---

## 7. 横切项

### 7.1 i18n 批量覆盖（独立立项，方法学）

- **范围统计先行**：`rg -n "[\u4e00-\u9fa5]" components/ --type-add 'arkts:*.ets' -tarkts | grep -v '^\s*//'`（排除纯注释）建立基线清单，目标：UI 字符串硬编码清零
- **方法**：i18n key 命名 `域.组件.语义`（如 `slash.category.basic`）；批量迁移按组件提 PR，每组件一个 commit；新增 key 双语齐写
- **验收**：切 English 后 Onboarding/SlashMenu/Settings/白板/图谱无中文残留（`rg` 基线复查为零）
- **工时**：5–8 天（**独立阶段集中执行**——v1.0 说「可穿插」自相矛盾：穿插会污染各工作包 diff 的归因，评审无法区分「功能变更」与「文案迁移」；排在 Sprint C 之后、与编辑器观察期并行最安全）

### 7.2 与 PLAN-DocumentEditor 的排程咬合（v1.1 重构——真并行关键路径）

```
Sprint A（纯 UI，1.5 周）
  U1 全部 + U2.2 + U2.3
  ⚠ ShortcutService 键位重排独占此窗口（不与编辑器键位调试同期——
    两处 ShortcutService/JS 键盘层同时动会互相污染回归归因）
  [编辑器 Phase 0–2（3 周）]
Sprint B（1.5 周）
  U2.1a spike → U2.1b + U2.5 + U3 全部
  （U2.4 FindInPage 不做——见其 v1.1 延后标注）
  [编辑器 Phase 3–4（2 周）]（Ctrl+E 随 Phase 4 落）
Sprint C（1.5 周）
  U4 + U5（U4.2 依赖的 U1.7 已在 Sprint A 就绪）
  [编辑器 Phase 5–6 + 观察期]
i18n 独立阶段（1 周，与编辑器观察期并行）
```

变更理由（v1.0 排程三处错误修正）：① 原「i18n 穿插全程」自相矛盾（见 7.1）；② U2.4 原排在 U2 内部但依赖编辑器 overlay 形态，两轮 churn；③ Ctrl+E 原无依赖标注但语义上属于编辑器视图模式，键位先落会在编辑器重铸后二次变更。U1/U2 先行的总理由不变：锚点/键盘/右键是后续一切体验评审的地基。

### 7.3 与编辑器方案的唯二接口

1. **AnchorRegistry**：DocumentEditor 的 `scrollHint`/`focusHint` 消息（PLAN §3.3）落地后，锚点服务增加 `mode: 'native' | 'web'` 分发——native 模式用本方案的 onAreaChange 注册表，web 模式走 `doc.scrollTo` 命令。两方案不冲突，先后兼容
2. **OverlayKeyRouter**：DocumentEditor 的 JS 侧 slash/autocomplete 弹层未来同样接入该路由（新增 overlayOpen 键即可）

---

## 8. 里程碑与验收

| 里程碑 | 内容 | 出口判据（demo 脚本） |
|---|---|---|
| M1（U1 完） | 器官全部复活 | 右键/长按菜单、块属性编辑、反链筛选、块多选、5 个文件删除且编译通过 |
| M2（U2 完） | 通路全部接通 | 「搜索→键盘选择→Enter→滚动定位到块→高亮」全程不碰鼠标；Ctrl+F/E/O 各归其位 |
| M3（U3 完） | 诚信与适配 | 断网三渲染正常；手机完成导入导出；暗色无失守色；回收站真功能 |
| M4（U4 完） | 桌面细节 | tooltip/标签四件套/分屏标签栈/选中态统一 全部可演示 |
| M5（U5 完） | 白板达标 | 连线粘附 + 三画布并存 |

**全局回归矩阵**（每个里程碑跑一遍）：3 形态（手机/折叠半开/桌面）× 2 主题（明/暗）× 4 核心流（编辑/搜索/白板/图谱）= 24 用例，`docs/regression-checklist.md` 建档。

---

## 9. 风险登记册

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | bindContextMenu 不支持右键+长按同节点双绑 | 2in1 触屏只支持其一 | 形态二选一（已设计）；Phase 0 spike 验证 |
| R2 | onKeyPreIme 拦截 Enter 影响中文输入法上屏 | 输入体验回退 | 仅 overlayOpen 态路由；拼音组词回车用例进 Phase 0 |
| R3 | rawfile 内相对路径引用不被 ArkWeb 解析 | 离线化方案返工 | Phase 0 spike；fallback：onInterceptRequest 自建 resource 协议路由 |
| R4 | 水平 List 拖拽排序在 API 26 不成熟 | 标签拖拽降级 | fallback：长按+箭头排序已备 |
| R5 | 软删除 .trash 目录被端云同步带上去 | 对端出现 .trash（无害但脏） | 可接受（Obsidian 同行为）；后续可加同步排除（若 Cloud Kit 支持 exclude） |
| R6 | 连线迁移吸附算法对旧画布误判 | 旧画布连线错位 | 迁移只做「最近形状」吸附，距离上限 200vp，超出保持原坐标并 console.warn |
| R7 | onAreaChange 高频上报性能 | 大页面滚动掉帧 | ≥2vp 变化短路 + Map 覆盖写（无 GC 压力）；300 块页面 profile 验证 |
| R8 | TabState/PaneState 双状态机互相覆盖 | 标签状态错乱 | PaneState 独立键空间 + 版本号，禁止交叉写；TabState 单向数据流注释已有先例 |

---

## 附录 A：文件 × 工作包矩阵（改动热点）

| 文件 | U1 | U2 | U3 | U4 | U5 |
|---|---|---|---|---|---|
| BlockView.ets | ●(多选/属性入口) | ●(锚点上报/高亮) | | ●(hover 显隐) | |
| BlockList.ets | | ●(locateBlock/FindInPage 挂载点迁移) | | | |
| PageTree.ets | ●(bindContextMenu) | | | | |
| LeftSidebar.ets | ●(tagFilter 修复/重命名 Esc/删死 builder) | | | ●(选中态) | |
| RightSidebar.ets | ●(三图标激活) | ●(行点击接锚点) | | | |
| SearchPanel.ets | | ●(键盘+锚点) | | | |
| CommandPalette.ets | | ●(键盘+更名 QuickSwitcher) | | | |
| SlashMenu.ets | ●(DatePicker 接线) | ●(键盘) | | | |
| FindInPage.ets | | ●(重做) | | | |
| ShortcutService.ets | ●(Ctrl+A) | ●(键位表) | | | |
| ContentArea.ets | | ●(OverlayKeyRouter 挂点) | | | |
| MainContainer.ets | | ●(浮层上移) | | ●(分屏栈/Tooltip 层/边缘手势) | |
| TabBar.ets | | | | ●(四件套) | |
| TabOverviewSheet.ets | | | | ●(缩略图) | |
| state/（新增 PaneState） | | | | ● | |
| GraphView.ets | | | ●(token 化) | | |
| Whiteboard.ets | | | ●(token) | | ●(锚定/画布切换) |
| WbConnector.ets | | | | | ●(模型迁移) |
| WhiteboardFileService.ets | | | | | ●(listCanvases) |
| CodeBlock/Math/Mermaid | | | ●(离线化) | | |
| Import/ExportDialog | | | ●(Picker) | | |
| PdfPage.ets | | | ●(Picker) | | |
| RecycleBinPage.ets | | | ●(真功能) | | |
| DataStore.ets | | | ●(软删除) | | |
| SettingsPage/VaultSwitcher/ProUpgrade/Onboarding | | | ●(版本/语言/删标注/文案) | | |
| 删除：MobileToolbar/RichBlockEditor/HomePage/TaskSchedulePanel/AllPagesPage/QueryBuilder/Toolbar | ● | | | | |
| 新增：AnchorRegistry/OverlayKeyRouter/TooltipLayer/PaneState | | ● | | ● | |

## 附录 B：新增 AppStorage 键一览

| 键 | 类型 | 写入方 | 消费方 | 持久化 |
|---|---|---|---|---|
| `callaite_pendingAnchor` | string(uuid) | 搜索/反链/大纲/TaskDashboard | BlockList | 否（消费即清） |
| `callaite_highlightUuid` | string | AnchorRegistry | BlockView | 否 |
| `callaite_overlayKey` + `callaite_overlayKeySeq` | string + number | OverlayKeyRouter | 四浮层 | 否 |
| `callaite_findInPageOpen` | boolean | Ctrl+F/BlockList | FindInPage | 否 |
| `callaite_searchPreload` | string | 右栏 search 图标 | SearchPanel | 否 |
| `callaite_paneRight` | string(JSON) | PaneState | MainContainer | 是 |
| `callaite_lastCanvas` | string | Whiteboard | Ribbon 路由 | 是 |
| `callaite_appVersion` | string | EntryAbility(bundleManager) | Settings/VaultSwitcher/About | 否（启动重取） |
| `callaite_syncState` | string | CloudSyncService 钩子 | StatusBar | 否 |
| `callaite_tagFilter` | string | **ContentRenderer.ets:312-313**（核验修正：写入方已存在，v1.0「LeftSidebar 未写」结论不成立——标签点击死胡同的真实成因需在 Sprint A 复查：链路上某环未消费或未写） | SearchPanel | 否 |

## 附录 C：新增颜色 Token 清单（base + dark 双份）

```
graph_edge / graph_label / graph_label_stroke
wb_grid / wb_shape_fill / wb_shape_stroke / wb_shape_text
flash_progress / flash_grade_again / flash_grade_hard / flash_grade_good / flash_grade_easy
task_todo_bg / task_doing_bg / task_done_bg（补齐缺口，与 marker_*_bg 对齐）
glass_tooltip_fill（TooltipLayer 专用半透明）
```

## 附录 D：Phase 0 Spike 清单（各 WP 开工前半天集中验证）

1. bindContextMenu 双绑（R1）
2. onKeyPreIme × IME 组词回车（R2）
3. rawfile 相对路径解析（R3）
4. 水平 List 拖拽（R4）
5. scrollToIndex 后子树物化时延实测（80ms 假设校准）
6. documentSave 真机行为

---

*本方案与 `PLAN-DocumentEditor.md`（编辑器主轴）、`REVIEW-UI-Obsidian-Alignment.md`（评审输入）构成三件套。评审通过后将本文档状态改为 Accepted，按 §7.2 排程执行。*
