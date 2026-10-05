import { TablerIcon } from '../common/Icons';
import { AppState, RightSidebarBlock } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { BacklinkInfo } from '../../core/db/DataStore';
import { JournalService } from '../../services/JournalService';
import { AnchorRegistry, AnchorSource } from '../../services/AnchorRegistry';
import { BacklinkFilters } from './BacklinkFilters';

/**
 * RightSidebar — 按 logseq right_sidebar.cljs 多块堆叠结构复刻
 *
 * 结构：
 *   ┌──────────────────────────────────────┐
 *   │ [⇲ collapse all] [⇱ expand] [✕ close all] │  ← 顶部工具栏
 *   ├──────────────────────────────────────┤
 *   │ ▼ Block Title                  [✕]   │  ← 块头部（可折叠）
 *   │   block content                      │
 *   ├──────────────────────────────────────┤
 *   │ ▶ Block Title (collapsed)      [✕]   │
 *   ├──────────────────────────────────────┤
 *   │ ▼ ...                                │
 *   └──────────────────────────────────────┘
 *
 * 块类型（type）：
 *   - 'backlinks'  : 反向链接列表
 *   - 'outline'    : 页面大纲
 *   - 'properties' : 页面属性
 *   - 'page'       : 页面预览
 *   - 'help'       : 帮助信息
 *
 * 数据源：AppState.getRightSidebarBlocks() 持久化在 AppStorage。
 * 自动初始化：首次打开且 blocks 为空时，添加 backlinks/outline/properties 三个默认块。
 */
@Component
export struct RightSidebar {
  @StorageLink('callaite_currentPage') @Watch('onCurrentPageChanged') currentPage: string = 'Journal';
  @StorageLink('callaite_rightSidebarBlocksVersion') private blocksVersion: number = 0;
  @State backlinksCache: BacklinkInfo[] = [];
  @State headingsCache: BlockData[] = [];
  @State propsCache: string[][] = [];
  /**
   * W8-U1.3：反链筛选面板模式。
   *
   *  · ''       —— 关闭
   *  · 'tag'    —— filter 图标：按标签收窄（只渲染标签下拉）
   *  · 'query'  —— search 图标：按关键词收窄（只渲染文本输入）
   *
   * 为什么两个图标不共用一个开关：右侧栏内容区只有 ~248vp，把
   * 「文本输入 + 标签下拉 + 排序」三件套平铺会把输入框压到 8px 宽（实测），
   * 且两个图标做同一件事等于只激活了一个（另一个仍是装饰）。
   */
  @State filterPanelMode: string = '';
  /**
   * W8-U1.3：+ 图标的页面选择列表开关 —— 用于把**别的页面**的反链块加进右侧栏。
   */
  @State addPanelOpen: boolean = false;
  /**
   * W8-U1.3：反链数据版本号，自增即让挂载中的 BacklinkFilters 重新拉取。
   * 触发点：切页（onCurrentPageChanged）、聚焦块变化、增删反链块。
   */
  @State backlinkDataVersion: number = 0;
  /**
   * W8-U1.3：聚焦块。挂它只为**驱动反链刷新** —— 编辑正文会产生新的 [[引用]]，
   * 反链面板必须跟着变，否则用户看到的是「改完了但反链没加」的假象。
   */
  @StorageLink('callaite_focusedBlock') @Watch('onFocusedBlockChanged') focusedBlock: string = '';

  aboutToAppear(): void {
    this.ensureDefaultBlocks();
    this.refreshCaches();
  }

  /**
   * currentPage 变更时刷新缓存数据（反链/大纲/属性）。
   */
  onCurrentPageChanged(): void {
    this.refreshCaches();
  }

  /** 聚焦块变化 ⇒ 只刷新反链（大纲/属性与聚焦块无关，不做无谓重算） */
  onFocusedBlockChanged(): void {
    // S3-W1：走 `getBacklinksFresh()`（读前先 flush 脏页）。
    // 本回调的**存在理由**就是「编辑正文会产生新的 [[引用]]，反链面板必须跟着变」
    // （见本组件 focusedBlock 声明处的注释）；而文本输入是惰性落盘、索引对账挂在落盘链路上
    // ⇒ 不先 flush 就会在这个回调里读到「还没对账」的旧索引，恰好复现 W12-3 的假象。
    this.backlinksCache = WorkspaceService.getInstance()
      .getBacklinksFresh(this.getCurrentDisplayPage());
    this.backlinkDataVersion = this.backlinkDataVersion + 1;
  }

  /**
   * 当 currentPage 或 blocksVersion 变更时刷新缓存与块内容。
   */
  build() {
    Column({ space: 0 }) {
      this.Toolbar()
      Divider().color($r('app.color.border')).width('100%')

      Scroll() {
        Column({ space: 0 }) {
          if (this.getBlocks().length === 0) {
            this.EmptyState()
          } else {
            ForEach(this.getBlocks(), (block: RightSidebarBlock) => {
              this.SidebarBlock(block)
            }, (block: RightSidebarBlock) => block.id)
          }
        }
        .width('100%')
        .padding({ bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { left: 0.5 }, color: $r('app.color.border') })
  }

  /**
   * 顶部工具栏 — 全部折叠 / 全部展开 / 全部关闭。
   *
   * 注：这三个图标**原本就是可点且有实义**的（各自 onClick 分别调 collapseAll /
   * expandAll / closeAll）。本仓的「三装饰图标」指的是**反链面板头部**那三个
   * （filter / search / plus），它们在 U1.3 之前没有任何 onClick，见 BacklinksHeader。
   */
  @Builder
  Toolbar() {
    Row({ space: 8 }) {
      TablerIcon('link', 14, $r('app.color.icon_color'))
      Text(t('sidebar_right_title'))
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted_text'))
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.6)
        .layoutWeight(1)

      // collapse all
      Row() {
        TablerIcon('chevron-up', 16, $r('app.color.muted_text'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(28)
      .height(28)
      .borderRadius(4)
      .onClick(() => { this.collapseAll(); })

      // expand all
      Row() {
        TablerIcon('chevron-down', 16, $r('app.color.muted_text'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(28)
      .height(28)
      .borderRadius(4)
      .onClick(() => { this.expandAll(); })

      // close all
      Row() {
        TablerIcon('x', 16, $r('app.color.muted_text'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(28)
      .height(28)
      .borderRadius(4)
      .onClick(() => { this.closeAll(); })
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
  }

  /**
   * 单个堆叠块 — 头部 + 可折叠内容。
   */
  @Builder
  SidebarBlock(block: RightSidebarBlock) {
    Column({ space: 0 }) {
      // 块头部：chevron + 标题 + 关闭按钮
      Row({ space: 8 }) {
        TablerIcon(block.collapsed ? 'chevron-right' : 'chevron-down',
          14, $r('app.color.muted_text'))
        Text(block.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        // W8-U1.3：反链块显示它**实际取数**的页面名。
        // 图谱菜单塞进来的反链块 pageName 与 currentPage 不同，不标出来会让人
        // 误以为面板显示的是当前页的反链（观感与数据对不上的静默误导）。
        if (this.isForeignBacklinkBlock(block)) {
          Text(this.blockPageName(block))
            .fontSize(10)
            .fontColor($r('app.color.muted_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 90 })
        }
        Row() {
          TablerIcon('x', 16, $r('app.color.muted_text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(20)
        .height(20)
        .onClick(() => { AppState.removeRightSidebarBlock(block.id); })
      }
      .width('100%')
      .height(34)
      .padding({ left: 16, right: 12 })
      .onClick(() => { AppState.toggleRightSidebarBlockCollapsed(block.id); })

      // 块内容（折叠时隐藏）
      if (!block.collapsed) {
        Column({ space: 4 }) {
          this.BlockContent(block)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }

      Divider().color($r('app.color.border')).width('100%')
    }
    .width('100%')
  }

  /**
   * 根据 block.type 渲染对应内容。
   */
  @Builder
  BlockContent(block: RightSidebarBlock) {
    if (block.type === 'backlinks') {
      this.BacklinksContent(block)
    } else if (block.type === 'outline') {
      this.OutlineContent(block)
    } else if (block.type === 'properties') {
      this.PropertiesContent(block)
    } else if (block.type === 'page') {
      this.PagePreviewContent(block)
    } else if (block.type === 'help') {
      this.HelpContent(block)
    }
  }

  /**
   * W8-U1.3：反链块 —— 头部（标题 + 三个可点图标）+ 筛选工具行 + 反链列表。
   *
   * 与 `GraphActions.openBacklinksView()` 的关系（先弄清再接线，勿凭印象）：
   *  · `GraphActions`（图谱节点长按菜单 →「查看反链」）**不自己渲染反链面板**，
   *    它只是 `AppState.addRightSidebarBlock({type:'backlinks', pageName: 图谱节点名})`
   *    然后把右侧栏打开 ⇒ 反链面板的**唯一渲染点就是本文件**。
   *  · 所以「把 BacklinkFilters 挂到 `openBacklinksView` 里」在结构上不成立：
   *    那里没有可挂的 UI。真正的挂载点只能是这里 —— 挂进来之后，
   *    图谱菜单那条路径**自动**也享受到了筛选能力（同一份渲染代码）。
   *  · 这也解释了为什么本组件必须按 `block.pageName` 取数：图谱路径塞进来的块，
   *    其 `pageName` 是**图谱节点页**而非当前页，只认 currentPage 会让那条路径拿错数据。
   */
  @Builder
  BacklinksContent(block: RightSidebarBlock) {
    // ─── 头部：标题 + 反链数 + 三个图标（filter / search / plus）───
    Row({ space: 4 }) {
      Text('反向链接 · ' + this.backlinksCache.length.toString() + ' 个结果')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // ① filter：按**标签**收窄反链（常显热区，不挂 onHover —— 触屏无 hover，陷阱 11）
      this.HeaderIcon('filter', this.filterPanelMode === 'tag', (): void => {
        this.toggleFilterPanel('tag');
      })
      // ② search：按**关键词**收窄反链
      this.HeaderIcon('search', this.filterPanelMode === 'query', (): void => {
        this.toggleFilterPanel('query');
      })
      // ③ plus：把**另一个页面**的反链视图加进右侧栏（对齐 Obsidian「在右侧栏打开反链」）
      this.HeaderIcon('plus', this.addPanelOpen, (): void => {
        this.addPanelOpen = !this.addPanelOpen;
        this.filterPanelMode = '';
      })
    }
    .width('100%')
    .padding({ top: 2, bottom: 2 })

    // ─── 筛选/搜索面板（由 ① ② 两个图标驱动；实现由挂载的 BacklinkFilters 提供）───
    // 这一份**只取工具栏**（showList/showCount = false）：计数行由下方列表那份提供，
    // 两份都画计数会出现两行一模一样的「共 N 条反链」。
    if (this.filterPanelMode !== '') {
      Column() {
        BacklinkFilters({
          pageName: this.blockPageName(block),
          dataVersion: this.backlinkDataVersion,
          showToolbar: true,
          showCount: false,
          showList: false,
          showTagOnly: this.filterPanelMode === 'tag',
          showQueryOnly: this.filterPanelMode === 'query'
        })
      }
      .width('100%')
      .padding({ top: 4, bottom: 2 })
    }

    // ─── + 图标的页面选择（把别的页面的反链加进来）───
    if (this.addPanelOpen) {
      this.AddBacklinksPicker()
    }

    // ─── 反链列表（计数行 + 列表；与上面那份共用同一份 BacklinkFilters 实现）───
    Column() {
      BacklinkFilters({
        pageName: this.blockPageName(block),
        dataVersion: this.backlinkDataVersion,
        showToolbar: false,
        showCount: true,
        showList: true
      })
    }
    .width('100%')
  }

  /**
   * W8-U1.3：反链块头部的图标热区（28×28，常显可点）。
   *
   * 不挂 `onHover`：触屏不产生 hover（AGENTS §7 陷阱 11），只挂 hover 的入口
   * 在平板上等于不存在。激活态用 primary 色 + 淡底表示，保证「点了有没有反应」可见。
   */
  @Builder
  HeaderIcon(name: string, active: boolean, onTap: () => void) {
    Row() {
      TablerIcon(name, 13, active ? $r('app.color.primary') : $r('app.color.muted_text'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width(28)
    .height(24)
    .borderRadius(4)
    // S4-W1 · U4.6 选中态统一：与 LeftSidebar.ViewChip / Ribbon / TabBar 同用 accent_soft
    .backgroundColor(active ? $r('app.color.accent_soft') : Color.Transparent)
    .onClick(() => {
      onTap();
    })
  }

  /**
   * 切换筛选/搜索面板（再点同一个图标即关闭）。
   *
   * 关掉 + 页面选择面板，避免「筛选关着但 + 的列表还挂着」的错位观感。
   */
  private toggleFilterPanel(mode: string): void {
    if (this.filterPanelMode === mode) {
      this.filterPanelMode = '';
    } else {
      this.filterPanelMode = mode;
    }
    this.addPanelOpen = false;
  }

  /**
   * W8-U1.3：+ 图标的页面选择列表。
   *
   * 为什么做成**内联列表**而不是 bindMenu / bindSheet：
   *  · bindMenu / bindContextMenu 弹在**独立子窗口**，`uitest` 注入到不了（陷阱 12）
   *    ⇒ 做出来就是「无法验收」的交互；
   *  · 内联列表长在侧栏里，可被 dumpLayout 看见、可被 uiInput 点到 ⇒ 可验收。
   *
   * 列表内容 = 自身 + 工作区里已有页面名的前 8 个（去重、去空）。
   * 点一项即 `AppState.addRightSidebarBlock`，选中项会置顶展开（AppState 去重逻辑）。
   */
  @Builder
  AddBacklinksPicker() {
    Column({ space: 2 }) {
      Text('在右侧栏打开哪个页面的反链？')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
        .padding({ bottom: 2 })

      ForEach(this.addBacklinkCandidates(), (name: string) => {
        Row({ space: 6 }) {
          TablerIcon('link', 12, $r('app.color.muted_text'))
          Text(name)
            .fontSize(12)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(28)
        .padding({ left: 6, right: 6 })
        .borderRadius(4)
        .backgroundColor($r('app.color.surface1'))
        .onClick(() => {
          this.openBacklinksForPage(name);
        })
      }, (name: string) => name)
    }
    .width('100%')
    .padding({ top: 4, bottom: 6 })
  }

  /**
   * + 面板的候选页面：当前页 + 工作区已有页面（去重、去空、上限 8 条）。
   *
   * 上限是刻意的：这是侧栏里的一块内联列表，不是页面选择器对话框；
   * 无限长会把反链列表整体挤出视口。
   */
  private addBacklinkCandidates(): string[] {
    const result: string[] = [];
    const self = this.getCurrentDisplayPage();
    result.push(self);
    const pages = WorkspaceService.getInstance().getAllPages();
    for (let i = 0; i < pages.length && result.length < 8; i++) {
      const name = pages[i].originalName;
      if (name !== '' && result.indexOf(name) < 0) {
        result.push(name);
      }
    }
    return result;
  }

  /**
   * 把指定页面的反链块加进右侧栏（+ 图标选项的落点）。
   */
  private openBacklinksForPage(name: string): void {
    const block: RightSidebarBlock = {
      id: 'sidebar-backlinks-' + name + '-' + Date.now(),
      type: 'backlinks',
      title: '反链: ' + name,
      pageName: name,
      collapsed: false
    };
    AppState.addRightSidebarBlock(block);
    this.addPanelOpen = false;
    this.backlinksCache = WorkspaceService.getInstance()
      .getBacklinksFresh(this.getCurrentDisplayPage());
    this.backlinkDataVersion = this.backlinkDataVersion + 1;
  }

  /**
   * 反链块的目标页面名（U1.3 实测修正，勿回退）。
   *
   * ⚠️ 这里踩过一次真坑：最初写成「无条件用 `block.pageName`」，结果右侧栏反链恒为 0。
   * 原因是 `ensureDefaultBlocks()` 只在**首次**初始化时建块，把当时的 currentPage
   * 永久写进了 `block.pageName`，而 `refreshCaches()` 是跟随 currentPage 的 ——
   * 于是「自动块」的数据源被冻在了启动那一页（实测：块里写着 `Home`，
   * 当前页却是 `__BKL_target` ⇒ 面板显示 `共 0 条反链`，而同一屏头部
   * 「反向链接 · 2 个结果」用的是 currentPage ⇒ 两处口径打架）。
   *
   * 判据用块 id 前缀而不是「pageName 是否为空」：
   *  · `backlinks-*`（AppState 自动块）：id 由 `'backlinks-' + pageName` 生成，
   *    页面变了它也不会变，所以**必须**跟随 currentPage；
   *  · 其余（`graph-backlinks-*` / `sidebar-backlinks-*`，由图谱菜单或 + 图标创建）：
   *    `pageName` 是**用户显式指定**的「要看哪一页的反链」，必须尊重它。
   */
  blockPageName(block: RightSidebarBlock): string {
    if (block.id.startsWith('backlinks-')) {
      return this.getCurrentDisplayPage();
    }
    if (block.pageName !== undefined && block.pageName !== '') {
      return block.pageName;
    }
    return this.getCurrentDisplayPage();
  }

  /**
   * 该反链块是否显式指向「非当前页」的页面。
   *
   * 只有这种块才需要在块头部标出页面名 —— 否则用户会以为面板显示的是当前页的反链。
   */
  private isForeignBacklinkBlock(block: RightSidebarBlock): boolean {
    return block.type === 'backlinks'
      && !block.id.startsWith('backlinks-')
      && this.blockPageName(block) !== this.getCurrentDisplayPage();
  }

  @Builder
  OutlineContent(block: RightSidebarBlock) {
    if (this.headingsCache.length === 0) {
      Text(t('no_outline'))
        .fontSize(12)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
    } else {
      ForEach(this.headingsCache, (b: BlockData) => {
        Row({ space: 8 }) {
          if (b.level > 0) {
            Blank().width(b.level * 12)
          }
          Circle({ width: 4, height: 4 })
            .fill($r('app.color.bullet'))
          Text(b.content)
            .fontSize(12)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
        // U2.1a：点击大纲条目 → 滚到该块并高亮（此前该行为纯展示，点了没反应）
        .onClick(() => {
          this.jumpToBlock(b);
        })
      }, (b: BlockData) => b.uuid)
    }
  }

  /**
   * U2.1a：大纲条目跳转。
   *
   * `headingsCache` 来自 `collectHeadings()`，而后者用 `ws.getPageBlocks(page.uuid)`
   * ——注意该方法名其实返回的是 DataStore 的**顶层块**（WorkspaceService.ets:88-90
   * → getTopLevelBlocks），所以标题若在子块上，它本来就不会出现在大纲里。
   *
   * U2.1b：本方法不再自己判状态、自己切页、自己弹提示 —— 一律交给 `AnchorRegistry`
   * （与搜索面板、反链面板同一个入口）。迁移前这里有一段「DIFFERENT_PAGE ⇒ 只切页、
   * 不定位」的兜底（大纲缓存可能停留在上一页）：现在 Registry 会**先**把目标块解析成
   * 它真正所属的页面并切过去，再等一帧定位 ⇒ 那个「切了页却没跳到那一行」的中间态
   * 不再出现，跨页大纲点击也能真正落到标题行。
   */
  private jumpToBlock(b: BlockData): void {
    AnchorRegistry.getInstance().jump({
      blockUuid: b.uuid,
      source: AnchorSource.OUTLINE
    });
  }

  @Builder
  PropertiesContent(block: RightSidebarBlock) {
    if (this.propsCache.length === 0) {
      Text(t('no_properties'))
        .fontSize(12)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
    } else {
      ForEach(this.propsCache, (pair: string[]) => {
        Row({ space: 4 }) {
          Text(pair[0] + '::')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.muted_text'))
          Text(pair[1])
            .fontSize(12)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
      }, (pair: string[]) => pair[0])
    }
  }

  @Builder
  PagePreviewContent(block: RightSidebarBlock) {
    Column({ space: 4 }) {
      Text(block.pageName)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
      Text('（页面预览）')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HelpContent(block: RightSidebarBlock) {
    Column({ space: 4 }) {
      Text(t('sidebar_help'))
        .fontSize(12)
        .fontColor($r('app.color.text'))
      Text('— ' + t('app_name'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    Column({ space: 6 }) {
      Text(t('empty_sidebar'))
        .fontSize(13)
        .fontColor($r('app.color.muted_text'))
      Text(t('empty_sidebar_hint'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
        .opacity(0.7)
    }
    .width('100%')
    .padding({ top: 40, left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
  }

  // ─── 工具方法 ───

  // 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
  getCurrentDisplayPage(): string {
    if (this.currentPage === 'Journal') {
      return JournalService.getTodayDateString();
    }
    return this.currentPage;
  }

  getBlocks(): RightSidebarBlock[] {
    return AppState.getRightSidebarBlocks();
  }

  /**
   * 首次打开自动添加默认块（backlinks / outline / properties）。
   */
  ensureDefaultBlocks(): void {
    const existing = AppState.getRightSidebarBlocks();
    if (existing.length > 0) return;
    const pageName = this.getCurrentDisplayPage();
    const blocks: RightSidebarBlock[] = [];
    blocks[0] = {
      id: 'backlinks-' + pageName,
      type: 'backlinks',
      title: t('backlinks'),
      pageName: pageName,
      collapsed: false
    };
    blocks[1] = {
      id: 'outline-' + pageName,
      type: 'outline',
      title: t('outline'),
      pageName: pageName,
      collapsed: false
    };
    blocks[2] = {
      id: 'properties-' + pageName,
      type: 'properties',
      title: t('properties'),
      pageName: pageName,
      collapsed: false
    };
    AppState.setRightSidebarBlocks(blocks);
  }

  refreshCaches(): void {
    const ws = WorkspaceService.getInstance();
    // S3-W1：`getBacklinksFresh()` = 先 flush 脏页再读反链（读前置 flush 的单一入口）。
    // 切页/切标签时 `flushNow` 本来就被 `AppState`/`TabState` 调用过，此处是**幂等**的
    // （无脏页时 O(1) 返回）；保留它是为了不依赖「调用方一定先 flush 过」这一假设。
    this.backlinksCache = ws.getBacklinksFresh(this.getCurrentDisplayPage());
    this.headingsCache = this.collectHeadings(ws);
    this.propsCache = this.collectProps(ws);
    // W8-U1.3：通知挂载中的 BacklinkFilters 重新拉取（切页后它必须换数据）
    this.backlinkDataVersion = this.backlinkDataVersion + 1;
  }

  collectHeadings(ws: WorkspaceService): BlockData[] {
    const page = ws.getPageByName(this.getCurrentDisplayPage());
    if (!page) return [];
    const allBlocks = ws.getPageBlocks(page.uuid);
    const result: BlockData[] = [];
    for (let i = 0; i < allBlocks.length; i++) {
      const b = allBlocks[i];
      if (b.content.startsWith('## ') || b.content.startsWith('# ') ||
          b.content.startsWith('### ')) {
        result.push(b);
      }
    }
    return result;
  }

  collectProps(ws: WorkspaceService): string[][] {
    const page = ws.getPageByName(this.getCurrentDisplayPage());
    if (!page) return [];
    const entries: string[][] = [];
    page.properties.forEach((propKey: string, propValue: string) => {
      const pair: string[] = [];
      pair[0] = propKey;
      pair[1] = propValue;
      entries.push(pair);
    });
    return entries;
  }

  // ─── 工具栏动作 ───

  collapseAll(): void {
    const list = AppState.getRightSidebarBlocks();
    const newList: RightSidebarBlock[] = [];
    for (let i = 0; i < list.length; i++) {
      newList.push({
        id: list[i].id, type: list[i].type, title: list[i].title,
        pageName: list[i].pageName, collapsed: true
      });
    }
    AppState.setRightSidebarBlocks(newList);
  }

  expandAll(): void {
    const list = AppState.getRightSidebarBlocks();
    const newList: RightSidebarBlock[] = [];
    for (let i = 0; i < list.length; i++) {
      newList.push({
        id: list[i].id, type: list[i].type, title: list[i].title,
        pageName: list[i].pageName, collapsed: false
      });
    }
    AppState.setRightSidebarBlocks(newList);
  }

  closeAll(): void {
    AppState.clearRightSidebarBlocks();
    // ✕ 同时关闭整个右侧栏（Logseq 右侧栏 close 行为）
    AppState.setRightSidebarOpen(false);
  }
}
