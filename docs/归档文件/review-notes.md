# UI 评审工作笔记（评审过程文件，最终交付为 REVIEW-UI-Obsidian-Alignment.md）

## 评审框架
对照物：Obsidian 1.x（Desktop + Mobile）分层 UI 模型：
- 壳层：Ribbon / 左右侧栏 / TabBar / 状态栏 / 移动端顶栏+底部工具条
- 编辑区：view header / inline title / breadcrumbs / 编辑器 / 嵌入反链
- 浮层：Command Palette / Quick Switcher / 各种 Dialog / hover preview
- 材质：CSS 变量主题系统 / dark-light / 强调色
- 交互维度：布局结构 L / 视觉 V / 交互 I / 动效 M / 平台适配 P / 无障碍 A

差距评级：🔴 结构性缺失 | 🟠 有但明显差距 | 🟡 细节差距 | 🟢 已对齐或超出

## 文件清单（80）
[已入册：components 全部 71 + state 4 + theme 1 + GlassSurface 在 common]

## 区域笔记
（逐区域追加）

---

### A. 壳层（MainContainer/Ribbon/TabBar/StatusBar/MobileHeader/MobileBottomBar/MobileMenuSheet/TabOverviewSheet/SplitDivider/MarkdownToolbar/MobileToolbar）

**MainContainer.ets (474L)**
- 结构：Ribbon+双侧栏+TabBar+ContentPanes(split 2窗格,ratio 0.2-0.8)+StatusBar，compact 形态 FloatingPanel 浮层侧栏+氛围渐变底。与 Obsidian 桌面骨架一致 ✓
- 🔴 分屏只有固定 2 窗格：副窗格无独立标签栈（仅 pageOverride+原生 Select 选页），Obsidian 为每窗格独立 tab 栈+可拖拽标签跨窗格+split right/down 多窗格
- 🟠 侧栏开合无过渡动画（Obsidian 有平滑 slide）；resizer 拖拽时无实时反馈预览（有，左宽实时变）→ 侧栏 resizer 无 hover 高亮提示线
- 🟡 TabBar 中 `Select` 原生组件破坏视觉语言（TabBar.ets L236-247）
- 🟡 MobileBottomBar 注释说 92% 宽，代码 80%（L13 vs L120 文档漂移）

**Ribbon.ets (182L)**
- 结构对齐 Obsidian（上层功能+底部系统）✓ 46vp 宽 vs Obsidian ~44px ✓
- 🟠 无 tooltip 系统：hover 只有背景变化，无 label 浮层（Obsidian ribbon hover 显示名称+快捷键）。TabBar/侧栏同样缺
- 🟡 Ribbon 含路由项（Journal/AllPages/Pdf）——Obsidian 无此形态（属设计取舍，但 10 个图标偏多，Obsidian 默认 7-8 个）
- 🟢 激活态 accent_soft 底+primary 图标，hover/pressed 三态齐全，140ms 动画

**TabBar.ets (317L)**
- 标签卡片：88-220vp 自适应宽、40vp 高、hover 显关闭、responseRegion 40vp 热区 ✓ 细节到位
- 🟠 无标签拖拽排序；无中键关闭；无右键上下文菜单（pin/复制路径等）——chevron 菜单仅 3 项
- 🟠 pinned 字段存在但无 UI 入口（TabState.TabInfo.pinned 死数据）
- 🟡 chevron 列表菜单位于最左（Obsidian 在右侧 + 旁边）；新标签固定开 Journal（Obsidian 开空标签+选择器）
- 🟢 关闭按钮 hover 变 danger 色；激活标签有 shadow+border 区分

**StatusBar.ets (152L)**
- 🟠 无反链计数（Obsidian 状态栏 signature 项）
- 🟠 sync 绿点+"已同步"是装饰性假状态（无真实同步状态机）
- 🟡 左侧硬编码 "Callaite" 品牌，应显示当前仓库名（Vault 体系已有）
- 🟢 CJK 字数统计逻辑正确

**MobileHeader.ets (98L)**
- 结构对齐 Obsidian iOS：圆形玻璃左/右按钮+居中标题 ✓ 沉浸避让 safeTop ✓ hitTest Transparent 内容可从按钮下滚过 ✓
- 🟠 无边缘右滑返回手势（Obsidian iOS 支持侧滑打开抽屉）
- 🟢 ULTRA_THIN 材质档位正确

**MobileBottomBar.ets (124L)**
- 形态为 Logseq/Safari 式悬浮胶囊（Obsidian iOS 实际无持久底栏，编辑时才有键盘工具行）——设计取舍，但注释声称"Obsidian iOS 复刻"不准确
- 🟢 back/forward 禁用态处理正确；[N] 徽标开总览
- 🟡 与 MobileMenuSheet 的 menu 按钮功能重复（顶栏"更多"与底栏 menu 均开同一浮层）

**MobileMenuSheet.ets (151L)**
- 🟠 无下滑手势关闭（拖动指示条是装饰）；Obsidian 为 iOS 下拉菜单形态，此为 bottom sheet（取舍）
- 🟡 无导出入口（有 import 无 export）；无主题切换（桌面 Ribbon 有，移动端丢失）
- 🟢 分组化菜单（内容/视图/系统）信息架构优于平铺

**TabOverviewSheet.ets (152L)**
- 🔴 卡片只有大图标+标题：Obsidian 标签总览卡片是**页面内容缩略图**（截图式预览），失去"视觉扫读"核心价值
- 🟠 卡片无滑动关闭手势；固定 2 列（46%）不适配折叠屏宽屏（应 3-4 列）
- 🟢 底部 [＋/N个标签/完成] 与参考图一致

**SplitDivider.ets (83L)**
- 🟢 拖拽交互正确（起始快照防二次累加已注释）；hover/拖拽态双反馈；双击复位 50%——超过 Obsidian 体验

**MarkdownToolbar.ets (176L)**
- 🟢 9 按钮与参考图 1:1；H/B 字母字形还原原设计；命令通道 cmd|seq 设计合理
- 🟠 无长按循环变体（Obsidian signature：长按 H 循环标题级别、长按 B 循环 bold/italic/highlight/strike）
- 🟠 按钮集偏少：缺 斜体/删除线/高亮/代码/引用/列表/复选框（Obsidian 工具行可横滚+更多）
- 🟡 'file' 按钮插入 `[](/.md)` 语义不明

**MobileToolbar.ets (197L)**
- 🔴 死代码：0 引用（仅自身定义）。且 wrapSelection 直接写 store 绕过 WebEditor 活跃编辑态——与 MarkdownToolbar 的 cmd 通道互相矛盾的双实现，应删除

---

### B. 侧栏区（LeftSidebar/PageTree/PageContextMenu/RightSidebar/BacklinkFilters/SearchPanel）

**LeftSidebar.ets (662L)**
- 结构：ViewSwitcher chips（文件/搜索/书签/标签）+搜索框+收藏/最近分组+PageTree。Obsidian 为图标 tab 切换（无文字），此处为图标+文字 chips——偏 Logseq 风
- 🔴 'search' 视图是空壳：点"搜索"chip 只显示"在上方搜索框中检索"空提示（L178-181），真搜索在浮层 SearchPanel——功能孤岛
- 🔴 标签视图点击 #tag 仅开搜索面板但不带过滤（TagListView onClick → setSearchPanelOpen(true)，而 SearchPanel 的 tagFilter 消费逻辑要求先写 callaite_tagFilter——LeftSidebar 没写！对比：其它入口有写。实测点击标签=空面板）——交互死胡同
- 🟠 hover 行内 trash 图标=立即硬删除，无确认（PageContextMenu 有确认但从未被调用，见下）——破坏性操作裸奔
- 🟠 内联重命名只支持 Enter 提交，无 Esc 取消、无失焦提交/取消——重命名卡死态
- 🟠 死代码约 200 行：NavRow/getNavItems/StripIcon/ViewSwitchIcon/TreeToolIcon/toggleCollapseAll/createNewNote/createNewNamespace（L97-106,294-435）均未在 build 引用（导航已迁 Ribbon、新建已迁 NewFileDialog）
- 🟡 书签视图=扁平收藏列表（Obsidian 书签支持文件夹分组/嵌入搜索/图谱）
- 🟡 选中态 accent_soft（收藏/最近行）vs PageTree 的 surface2——同屏两种"当前项"视觉语言

**PageTree.ets (202L)**
- 🟠 全应用无右键/长按上下文菜单（PageContextMenu 存在但 0 引用）——Obsidian 文件树核心交互（重命名/删除/移动到文件夹/新建子页）全部缺失入口
- 🟠 折叠态不持久化（@State Map，重启即失）——Obsidian 持久化
- 🟠 无拖拽：不能拖页面进文件夹（Obsidian 基础操作）
- 🟡 28vp 行高紧凑 ✓；统计行对齐移动端 ✓；空态 ✓

**PageContextMenu.ets (297L)**
- 🔴 死代码：`PageContextMenu(`/`onContextMenu`/`longPressGesture` 全仓库 0 匹配。组件本身完成度尚可（含删除确认+重命名弹窗），但从未接线
- 🟡 favorite 只加不减（无 toggle）；菜单无进出场动画；无键盘导航；位置无防溢出钳制

**RightSidebar.ets (493L)**
- 模型为 Logseq 堆叠块（非 Obsidian tab 面板）——设计取舍，但面板内容差距大：
- 🔴 反链行不可点击（Obsidian 反链点击跳转来源并高亮）——只读列表
- 🔴 大纲行不可点击（Obsidian 大纲点击滚动定位）
- 🔴 PagePreviewContent 是占位符："（页面预览）"（L343）
- 🟠 反链工具行的 filter/search/plus 三个图标是装饰（无 onClick）
- 🟠 数据陈旧 bug：refreshCaches 仅挂 currentPage @Watch；blocksVersion 已 @StorageLink 但无 @Watch——编辑页面时反链/大纲不实时刷新（切页才刷）
- 🟠 无 unlinked mentions（Obsidian 反链面板 signature 功能）
- 🟡 无块拖拽排序；closeAll 连带关整个侧栏（Logseq 行为，OK）

**BacklinkFilters.ets (331L)**
- 🔴 死代码：0 引用（RightSidebar 用自己的内联反链渲染）。331 行筛选/排序/标签下拉完整实现——从未接线
- 🟡 BacklinkItem 同样不可点击导航

**SearchPanel.ets (368L)**
- 🔴 形态：居中浮层模态（80% 宽）——Obsidian 搜索是左侧栏内嵌持久面板（含历史/筛选/操作符/逐页分组计数）。当前为 Logseq Cmd+K 基因
- 🔴 block 结果点击只 setCurrentPage，不定位到块（无锚点滚动/高亮）
- 🟠 无键盘导航（↑↓选择+Enter）；无搜索操作符（tag:/path:/task:...仅支持 # 前缀）；无按页分组折叠
- 🟠 onChange 每击键全库遍历（allPages×blocks 同步扫），无防抖——大库性能风险
- 🟢 匹配高亮 splitHighlight 实现正确；空查询显示最近页面 ✓；tagFilter 消费逻辑（但见 LeftSidebar 死胡同）

---

### C. 编辑区（PageView/BlockList/BlockView/BlockChildren/WebEditor/IntegralEditor/SlashMenu/BlockSelection/FindInPage/Toolbar/JournalFeed/ShortcutService）

**PageView.ets (489L)**
- 🔴 标题不可点击编辑（Obsidian inline title=文件名，点击即改）；properties 只读（Obsidian 可编辑值+Add property UI）
- 🔴 无 view header/面包屑（Obsidian 编辑窗格顶部：路径面包屑可点+more-options 按钮）
- 🟠 "整页编辑"chip 在内容流内（Obsidian 在窗格头部/移动端底栏）；properties 折叠用 '+/−' 文字而非 chevron 图标
- 🔴 Recycle 路由渲染硬编码"回收站暂无内容"假空态（不读真实回收站数据，RecycleBinPage 另存在但未接线）
- 🟡 QueryView builder + QueryBuilder import 疑似死代码（'Query' 路由不可达）
- 🟡 maxWidth 960（Obsidian 默认可读行宽 ~40em≈700px）
- 🟢 Journal/Graph/Whiteboards/Flashcards/Pdf/Settings/Pro 路由分发清晰

**BlockList.ets (230L)**
- LazyForEach 仅顶层+children 递归：结构合理；onDataReloaded 全量重载
- 🟠 每次 blocksVersion bump 全树刷新（无脏路径局部更新）——大页性能风险
- 🟢 空态 ghost 行+Enter 懒创建页面 ✓（Logseq 行为）

**BlockView.ets (787L)——差距最大**
- 🔴 阅读态显示原始标记：[[页面]] 带双方括号原样显示、((uuid)) 直接把内部 UUID 暴露给用户、`![[嵌入]]` 双显示（行内 [[链接]] + 下方嵌入框同时出现）——Obsidian/Logseq 阅读态均隐藏语法
- 🔴 无 Live Preview 任何形态：无"光标行源码/其余渲染"翻转（块级 WebEditor 结构性限制，已在 PLAN-DocumentEditor 论证）
- 🟠 标题无字号/字重层级（## 与正文同大，仅颜色区分）；列表（有序/无序）无列表样式
- 🟠 多行长块疑似被 .height(28) 固定高裁切（Text segment 显式高度）
- 🟠 图片固定 120×80 Cover 裁切、无点击放大 lightbox（Obsidian 点击全屏预览）
- 🟠 ActionsBar 删除无确认；无 copy block ref/open in sidebar
- 🟠 块嵌入只渲染纯文本截断 80 字符（应渲染转写内容）；页面嵌入取前 5 行原文
- 🟡 TAG_REF 点击 → setCurrentPage(tag名)（把标签当页面打开），Obsidian 语义=搜索该标签
- 🟡 块级 hover 操作三按钮（折叠/引用/删除）始终同行显示（Obsidian hover 才浮现）

**BlockChildren.ets (71L)**
- 🟠 BlockView 不监听 blocksVersion：undo/redo 或外部 op 改子块内容时，嵌套块显示可能滞留旧内容（ForEach key 相同组件保留，refreshBlock 不触发）——需实测验证

**WebEditor.ets (475L)（已在编辑器方案中深度分析，此处 UI 视角补充）**
- 🔴 .height(32) 固定高：多行块在编辑态被裁切（比阅读态 28 更严重）
- 🟠 获焦块无 border/focus ring（仅背景色区分）
- 🟡 键盘契约完整（Enter/Tab/Backspace/箭头）✓ 但 Tab 缩进路径序列化丢标记（L388/395 传 innerText）

**IntegralEditor.ets (367L)**
- 四模式 live/source/preview/split 齐 ✓ split 分屏对照是 Obsidian 没有的加分项
- 🟠 live 模式的"光标感知语法隐藏"仅整行/整块粒度翻转，非逐行翻转——与 Obsidian Live Preview 体验差距大（根因同块级作用域）
- 🟠 PreviewLine 手写 span 渲染子集（粗体/代码/链接/标题），与 ContentRenderer 两套并行——渲染一致性靠人肉
- 🟡 整页 RichEditor 重建为空的补丁注释多处（防误删防御代码）

**SlashMenu.ets (493L)**
- 🔴 位置：渲染在列表尾部内联（推挤内容），非光标处浮动浮层（Logseq/Obsidian slash=光标锚定浮层）
- 🔴 无键盘导航（↑↓+Enter）——slash 菜单的核心操作方式缺失；filter TextInput 抢焦点风险
- 🔴 insertText 追加到块末尾而非光标位置
- 🟠 SCHEDULED/DEADLINE 直接设为今天，无日期选择器（DatePicker 组件已存在未接）
- 🟡 全文件硬编码中文（'搜索命令...'/'无匹配命令'/分类标签），未走 t() i18n

**BlockSelection.ets (272L)**
- 🔴 不可达：EditorService.toggleSelection 全仓库 0 调用；BlockView 无长按/Ctrl+点击选中手势；无 Ctrl+A 快捷键——多选工具栏永远不出现
- 🟢 批量缩进/删除/复制(markdown+tab 缩进)/全选/清除 实现完整

**FindInPage.ets (215L)**
- 🔴 功能死：内部 isVisible 恒 false（show()/hide() 无外部调用通道，BlockList 的 findInPageVisible 控制渲染但组件自身 build 又判 isVisible）——Ctrl+F 实际打开的是全局 SearchPanel（ShortcutService L425-436 两个快捷键同一个 action）
- 🔴 navigatePrev/Next 只改计数不滚动不高亮；无 Enter/Shift+Enter/Esc 键位
- 🟡 placeholder 硬编码中文未 i18n

**Toolbar.ets (68L)**
- 🟠 refreshState 仅 aboutToAppear 调用（onPageShow 对 @Component 无效）——canUndo/canRedo 永远停留初始值，撤销工具栏状态陈旧（隐藏后不再出现/出现后不消失）
- 🟡 与 MarkdownToolbar 的 undo/redo 重复

**JournalFeed.ets (96L)**
- 🟢 无限回溯时间流+今天 TaskDashboard ✓ 独创且合理
- 🟠 天数无限累计无窗口化（每 day 一个完整 BlockList 组件树，长滚内存增长）
- 🟡 日期标题点击跳单日页 ✓ 但无"回到今天"锚点按钮

**ShortcutService.ets (591L)**
- 🔴 Ctrl+F 与 Ctrl+K 同一动作（都开全局搜索）——页内搜索快捷键缺失（Obsidian Ctrl+F=in-page）
- 🟠 无 Ctrl+E（编辑/预览切换，Obsidian 核心）、无 Ctrl+O（快速切换器——Callaite 无此功能本体）、无 Ctrl+N
- 🟠 Ctrl+B/I 包裹整块内容而非选区（代码注释自认局限）
- 🟡 Enter/Tab/Backspace 在此注册但 ContentArea.onKeyPreIme 只放行无修饰键给编辑器——这三条绑定实际不可达（无害死绑定）

**死代码汇总（编辑区）**：HomePage.ets(108L, 路由不可达)、AllPagesPage.ets(426L, PageView 用内建 builder)、RichBlockEditor.ets(114L)、AutoComplete.ets(329L)、BlockDragHandler.ets(538L)、FindInPage(功能死)、BlockSelection(不可达)、Toolbar(状态死)——合计约 1900+ 行

---

### D. 浮层区（CommandPalette/NewFileDialog/ExportDialog/ImportDialog/VaultSwitcherDialog/FloatingPanel/property 三件套）

**CommandPalette.ets (145L)**
- 🔴 名不副实：实为**页面快速切换器**（搜页面+跳转），无任何"命令"——Obsidian Ctrl+P=命令面板（命令列表），Ctrl+O=快速切换器。Ribbon"命令面板"按钮打开的是切换器
- 🔴 底部键位提示是假的：渲染"↑↓ 选择 ↵ 打开 esc 关闭"但**无任何键盘事件处理**——提示条装饰性撒谎
- 🟠 无选中高亮/无模糊匹配/无拼音首字母；Enter/Esc 无响应
- 🟢 新建页面兜底行 ✓

**NewFileDialog.ets (197L)**
- 🔴 白板永远覆写 default.canvas（旧画布归档）——**全应用只支持一个白板**（Obsidian 无限 .canvas）。Ribbon 'Whiteboards' 路由也只加载 default.canvas
- 🟡 三选项设计（Markdown/白板/大纲）合理但类型选择不可逆；'未命名笔记' 未 i18n
- 🟢 GlassSurface MODAL 材质+三态按钮 ✓

**ExportDialog.ets (238L) / ImportDialog.ets (180L)**
- 🔴 手输文件系统路径（placeholder '/data/notes/example.md'）——无 documentViewPicker/documentSavePicker 系统选择器；手机上不可用。PDF 页同样（提示"放入目录后刷新"）。**全应用统一缺失系统 Picker 集成**
- 🟡 视觉与玻璃对话框体系脱节（原生 Button 胶囊+白字硬编码+✕ 文字字符）；全部硬编码中文；导出无 PDF 选项（Obsidian 有 Export to PDF）
- 🟢 导入双模式（当前页/新页面）+块计数反馈 ✓

**VaultSwitcherDialog.ets (175L)**
- 🟠 版本号硬编码 'HarmonyOS 1.1.1'（实际 4.2.5）；"语言"行是静态展示不可点击（假控件）；注释宣称"重新加载索引"未实现
- 🟡 深色固定配色符合 Obsidian 参考 ✓ 但全部硬编码中文
- 结构对齐 Obsidian 仓库切换大模态 ✓（单库架构下的合理简化）

**FloatingPanel.ets (99L)**
- 🟢 工程质量最高的浮层：PopupSizeChecker 合规、不对称过渡动画(220/160ms Friction)、safe area 避让、hitTest 透明
- 🟡 无边缘滑动关闭手势

**property/ 三件套 (1083L) + DatePicker (433L)**
- 🔴 全部死代码：PropertyEditor/PropertyConfig/PropertyValueEditor 0 外部引用；DatePicker 唯一调用方是死代码 PropertyEditor——1516 行完整的块属性编辑系统（6 类型+日期选择+类型配置）从未接线

---

### E. 主题材质区（ThemeManager/GlassSurface/MaterialTokens/SystemBarHelper/Icons/Breakpoints）

**GlassSurface.ets (182L)** 🟢
- 双模式材质（COMPONENT/自定义 backgroundEffect）+sheen 高光层+token 化参数+按压弹性——超过 Obsidian 的平面 CSS 体系，是差异化资产
- systemMaterial 关闭原因有文档（THREAD_BLOCK_6S），与 ADR-004 一致

**MaterialTokens.ets (221L)** 🟢
- 五档语义 Token（TOP_FLOATING/BOTTOM_FLOATING/TRANSIENT/MODAL/CONTENT）对齐官方沉浸光感规范；能力探测+缓存
- 🟡 MaterialSpec.fillAlpha 定义但 GlassSurface 未消费（fill 走颜色资源）——token 部分失配

**ThemeManager.ets (131L)**
- 🟠 无强调色自定义（Obsidian accent color 是主题系统核心）；无字体选择
- 🟡 SYSTEM 模式下 toggle 到 DARK：系统暗色用户首次点切换无视觉变化（暗→暗）
- 🟢 限符资源切换时机正确（AppStorage 后、loadContent 前）

**SystemBarHelper.ets (59L)** 🟢 全透明+主题内容色，正确

**Icons.ets (146L)** 🟢
- 弧参数感知的 SVG 缩放（a/A flag 不缩放）+密度换算+占位兜底——工程质量高
- Tabler 图标系=Logseq 同款，与 Obsidian 的 Lucide 同美学 ✓

**Breakpoints.ets (56L)**
- 🟡 viewportWidth 读的是**屏幕宽**而非窗口宽——但 MainContainer 已用 onAreaChange 真实尺寸修正形态（L94 有注释），Breakpoints 仅用于 padding 级决策——影响有限
- 🟢 三形态（compact/medium/expanded）模型比 Obsidian 的双形态（desktop/mobile）更细

---

### F. 其他界面（Graph/Whiteboard/Settings/扩展/Flashcard/Onboarding/Query/TaskDashboard）

**GraphView.ets (634L)+GraphLayout(340)+GraphActions(252)**
- 🟢 力导向+捏合缩放+节点拖拽+局部图谱+标签过滤+NaN 防护——基础扎实
- 🔴 暗色模式 bug：边/描边/标签硬编码（#D1D5DB/#FFFFFF/#1A1A1A）——暗色主题下标签近乎不可见
- 🟠 无图谱设置面板（Obsidian：力参数滑条/节点大小/箭头/文字显隐阈值/动画开关全套）
- 🟠 捏合缩放不锚定手势中心（缩放围绕原点+固定 offset，手指间内容漂移）
- 🟠 无 hover 邻居高亮、无节点 hover 预览；布局无动画（静态 settle）；同步 100 迭代在 UI 线程
- 🟡 标签截断 12 字符硬编码；'图谱关系' 等硬编码中文；返回键固定回 Journal 丢导航栈

**Whiteboard.ets (1157L)+6 子组件**
- 🟢 无限画布+6 工具+压感笔迹+50 级撤销+viewport 持久化+NaN 防护+组件化重构完成
- 🔴 连线不锚定形状：WbConnector 存绝对坐标，移动形状后连线原地不动——Obsidian Canvas 边是粘附节点的，这是核心交互缺陷
- 🔴 单白板限制（见 NewFileDialog）+ WbPageRef 无添加入口（页面引用卡片只能靠 demo 数据出现）
- 🟠 无形状 resize 手柄/无旋转 UI（rotation 字段存在）/无多选/无复制粘贴/无颜色选择（形状固定两色，不随主题）
- 🟠 文字仅纯文本单行 TextInput（Obsidian Canvas 节点=完整 Markdown 卡片）
- 🟡 咖捏合缩放同 GraphView 不锚定中心；网格色不随主题

**SettingsPage.ets (926L)+ShortcutSettings(485L)**
- 🟢 双栏+搜索+分组+插件三段行——结构对齐 Obsidian 设置模态 ✓；快捷键重绑 UI 存在
- 🟠 版本硬编码 'v1.0.0'（陈旧）；反馈按钮是死胡同（弹窗告知去 GitHub，无链接）
- 🟠 编辑器组设置仅 3 项（Obsidian 编辑器组 15+ 项：行宽/默认视图/严格换行/拼写检查...）；无附件默认路径/链接格式设置
- 🟠 i18n 覆盖率约四成——设置页大量硬编码中文，语言切换后仍是中文
- 🟡 '清除缓存' 实际只清最近页面，标签误导

**CodeBlock(187)/MathRenderer(44)/MermaidRenderer(84)**
- 🟠 三者全部 CDN 依赖（cdnjs/jsdelivr）——**离线场景代码高亮/公式/图表全部失效**；Obsidian 全离线
- 🟠 每个代码块/公式一个 WebView 实例——同屏多块时内存/渲染成本高（块级 WebView 同病）
- 🟢 JSON 转义+语言白名单的注入防护 ✓；KaTeX 主题跟随 ✓

**FlashcardPage.ets (293L)**
- 🟢 FSRS 流程完整+空态+统计卡（等宽列修复注释详实）——Obsidian 默认无此功能，是超出项
- 🟡 卡片内容纯 Text 直出（含 markdown 的卡片显示原始标记）；进度条/评分按钮硬编码色；全硬编码中文

**PdfPage(171)+PdfViewer(296)**
- 🔴 导入=提示语（"请放入目录"），无系统 Picker——与 ImportDialog 同病
- 🟠 无标注（Pro 表宣称 "PDF 标注 ✓" 但功能不存在——付费卖点虚假宣传风险）
- 🟢 空态有刷新按钮（注释记录了死胡同修复过程）

**TaskDashboard.ets (149L)**
- 🟢 今日计划/截止双列表+QueryEngine 驱动 ✓；🟡 点击只到页面不到块；标记底色硬编码

**OnboardingPage.ets (285L)**
- 🟢 四步引导+过渡动画+宽屏限宽 ✓
- 🟠 快捷键宣传与实际不符：'Ctrl+P 命令面板'（实为页面切换器）——首屏就教错
- 🟡 全硬编码中文（英文用户的首次体验是中文）

**死代码补充（F 区）**：TaskSchedulePanel(312L)、QueryBuilder(216L)+QueryView builder、'About' 路由疑似不可达
**全部死代码合计约 4900+ 行（UI 层 ~33,300 行的 ~15%）**

---

### G. 全局横切问题（跨界面）

1. 🔴 **无右键/长按上下文菜单**：全应用 0 处 onContextMenu/longPress——Obsidian 桌面交互的一半（文件树/编辑器/标签页/图谱节点右键）不存在，PageContextMenu 写好了没接
2. 🔴 **无系统 Picker**：导入/导出/PDF 全部手输路径
3. 🔴 **块定位缺失**：搜索结果/TaskDashboard/反链/大纲全部"到页不到块"——无锚点滚动+高亮机制（Obsidian 每个 jump 都定位）
4. 🔴 **键盘导航系统性缺失**：CommandPalette/SlashMenu/SearchPanel/FindInPage 四个"本该键盘驱动"的浮层全部无 ↑↓/Enter/Esc——而且 CommandPalette 还渲染了假的键位提示条
5. 🟠 **i18n 覆盖率低**：i18n 框架存在（t()）但约六成 UI 字符串硬编码中文——Onboarding/SlashMenu/Settings/白板/图谱几乎全量硬编码
6. 🟠 **动效体系不均**：FloatingPanel/GlassSurface/Onboarding 有精致过渡，但侧栏开合/TabOverview/菜单/SlashMenu 无动效或无入场动画
7. 🟠 **暗色模式硬编码色**：GraphView 边/标签、Whiteboard 形状/网格、TaskDashboard 标记底、Flashcard 进度条/评分色——主题 token 体系没覆盖到的角落
8. 🟠 **hover 体系缺失**：无 tooltip（Ribbon/TabBar/工具栏按钮无悬停说明）；桌面端 hover 反馈零散
9. 🟠 **假状态/假控件清单**：StatusBar 假同步绿点、VaultSwitcher 假语言行、ProUpgrade 假"PDF 标注"、版本号三处不一致（1.0.0/1.1.1/实际 4.2.5）
10. 🟡 **"当前项"视觉语言不统一**：accent_soft vs surface2 两套选中态混用
