import { TablerIcon } from '../common/Icons';
import { PageTree } from './PageTree';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { SubscriptionService } from '../../services/SubscriptionService';
import { Breakpoints } from '../../state/Breakpoints';

interface NavItem {
  key: string;          // 唯一标识，对应 AppState.currentPage 值
  label: string;        // i18n 标题
  iconName: string;     // Tabler 图标名
}

/**
 * LeftSidebar — Obsidian 文件树侧栏 + Logseq 分组基因融合。
 *
 * 结构（自上而下，对齐 Obsidian 桌面左栏）：
 *   ┌──────────────────────┐
 *   │ Vault 行 (bolt+名称)  │  ← Obsidian 仓库标题
 *   ├──────────────────────┤
 *   │ 视图切换图标行         │  ← files/search/star（Obsidian 左栏顶部图标）
 *   ├──────────────────────┤
 *   │ 导航（可折叠分组）     │  ← Logseq 基因：Journal/AllPages/Graph/...
 *   │ 收藏夹（可折叠分组）   │
 *   │ 最近（可折叠分组）     │
 *   │ 所有页面（命名空间树） │
 *   ├──────────────────────┤
 *   │ 底部 Vault 行（设置） │  ← Obsidian 左下角仓库切换位
 *   └──────────────────────┘
 */
@Component
export struct LeftSidebar {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_favorites') @Watch('onFavoritesChanged') favoritesRaw: string = '[]';
  @StorageLink('callaite_recentPages') @Watch('onRecentChanged') recentRaw: string = '[]';
  @State allPages: PageData[] = [];
  @State favorites: string[] = [];
  @State recent: string[] = [];
  @State renamingPage: string = '';
  @State renameText: string = '';
  @State hoveredPage: string = '';
  @State hoveredNavKey: string = '';
  @State hoveredViewIcon: string = '';
  @State hoveredStrip: string = '';
  @State hoveredTool: string = '';
  /** 方案三（W1）：侧栏视图 —— 'files' | 'search' | 'bookmarks' | 'tags' */
  @State sidebarView: string = 'files';
  /** 标签视图数据源（切入标签视图时刷新） */
  @State allTags: string[] = [];
  /** 文件树排序方向：false=名称升序，true=名称降序（对齐 Obsidian 左栏排序按钮） */
  @StorageLink('callaite_sidebarSortDesc') sortDesc: boolean = false;
  // 分组折叠态（持久化，Logseq sidebar-content-group）
  @StorageLink('callaite_collapsed_favorites') collapsedFavorites: boolean = false;
  @StorageLink('callaite_collapsed_recent') collapsedRecent: boolean = false;
  @StorageLink('callaite_collapsed_allpages') collapsedAllPages: boolean = false;

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    this.allPages = ws.getAllPages();
    this.refreshSidebarData();
  }

  onFavoritesChanged(): void {
    this.refreshFavorites();
  }

  onRecentChanged(): void {
    this.refreshRecent();
  }

  refreshFavorites(): void {
    if (this.favoritesRaw) {
      try { this.favorites = JSON.parse(this.favoritesRaw) as string[] ?? []; } catch (e) { this.favorites = []; }
    } else {
      this.favorites = [];
    }
  }

  refreshRecent(): void {
    if (this.recentRaw) {
      try {
        const parsed = JSON.parse(this.recentRaw) as string[] ?? [];
        this.recent = parsed.filter((name: string) => !AppState.isInternalRoute(name));
      } catch (e) { this.recent = []; }
    } else {
      this.recent = [];
    }
  }

  refreshSidebarData(): void {
    this.refreshFavorites();
    this.refreshRecent();
  }

  getNavItems(): NavItem[] {
    const items: NavItem[] = [];
    items[0] = { key: 'Journal', label: t('nav_journals'), iconName: 'calendar' };
    items[1] = { key: 'AllPages', label: t('nav_all_pages'), iconName: 'files' };
    items[2] = { key: 'Graph', label: t('nav_graph_view'), iconName: 'hierarchy' };
    items[3] = { key: 'Flashcards', label: t('nav_flashcards'), iconName: 'stack-2' };
    items[4] = { key: 'Whiteboards', label: t('whiteboards'), iconName: 'layout-grid' };
    items[5] = { key: 'Pdf', label: 'PDF', iconName: 'file' };
    return items;
  }

  isCompact(): boolean {
    return Breakpoints.isCompact();
  }

  toggleSection(key: string): void {
    if (key === 'favorites') {
      this.collapsedFavorites = !this.collapsedFavorites;
    } else if (key === 'recent') {
      this.collapsedRecent = !this.collapsedRecent;
    } else if (key === 'allpages') {
      this.collapsedAllPages = !this.collapsedAllPages;
    }
  }

  build() {
    Row({ space: 0 }) {
      // ─── 方案三（W1）：44vp 活动栏图标列已下线，面板独占侧栏宽度 ───
      //   原图标列入口去向：新建 → 顶部操作行；仓库 → 顶部操作行；
      //   收藏折叠 → 区段标题自带折叠；设置 → Ribbon 底部；
      //   Journal/AllPages/Pdf/图谱/白板/闪卡 → Ribbon（见 Ribbon.ets）。
      //   侧栏总宽仍为 SIDEBAR_DEFAULT(260vp)，去掉图标列后面板 216vp → 260vp
      //   （计划 §2.2 目标 240–260vp，落在区间上沿）。
      Column({ space: 0 }) {
        this.ViewSwitcher()

        if (this.sidebarView !== 'tags') {
        Row({ space: 8 }) {
          TablerIcon('search', 14, $r('app.color.muted_text'))
          Text('搜索或开始搜索...')
            .fontSize(12.5)
            .fontColor($r('app.color.muted_text'))
            .layoutWeight(1)
            .maxLines(1)
        }
        .width('100%')
        .height(30)
        .padding({ left: 10, right: 10 })
        .margin({ left: 8, right: 8, top: 8 })
        .borderRadius(6)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          AppState.setSearchPanelOpen(true);
        })
        }

        if (this.sidebarView === 'files' || this.sidebarView === 'bookmarks') {
          this.SectionHeader(t('favorites'), 'favorites', this.collapsedFavorites)
          if (!this.collapsedFavorites) {
            ForEach(this.favorites, (name: string) => { this.PageLink(name); }, (name: string) => name)
            if (this.favorites.length === 0) this.EmptyHint(t('empty_favorites_hint'))
          }
          this.SectionSpacer()
        }

        if (this.sidebarView === 'files') {
          this.SectionHeader(t('recent'), 'recent', this.collapsedRecent)
          if (!this.collapsedRecent) {
            ForEach(this.recent.slice(0, 8), (name: string) => { this.PageLink(name); }, (name: string) => name)
            if (this.recent.length === 0) this.EmptyHint(t('empty_recent_hint'))
          }
          this.SectionSpacer()

          PageTree()
            .layoutWeight(1)
        }

        if (this.sidebarView === 'tags') {
          this.TagListView()
        }

        if (this.sidebarView === 'search') {
          this.EmptyHint('在上方搜索框中检索页面与内容')
          Blank()
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 侧栏视图切换器（方案三 · W1）—— Obsidian 式：侧栏顶部一行视图标签，
   * 取代原先占据 44vp 的第二条图标列。
   */
  @Builder
  ViewSwitcher() {
    Row({ space: 2 }) {
      this.ViewChip('files', 'file-text', '文件')
      this.ViewChip('search', 'search', '搜索')
      this.ViewChip('star', 'bookmark', '书签')
      this.ViewChip('tag', 'tags', '标签')
      Blank()
      this.IconAction('file-plus', (): void => {
        AppStorage.setOrCreate('callaite_newFileDialogOpen', true);
      })
      this.IconAction('database', (): void => {
        AppStorage.setOrCreate('callaite_vaultSwitcherOpen', true);
      })
    }
    .width('100%')
    .height(36)
    .padding({ left: 6, right: 6 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  ViewChip(icon: string, key: string, label: string) {
    Row({ space: 3 }) {
      TablerIcon(icon, 12, this.sidebarView === key ? $r('app.color.primary') : $r('app.color.muted_text'))
      Text(label)
        .fontSize(11.5)
        .fontColor(this.sidebarView === key ? $r('app.color.primary') : $r('app.color.muted_text'))
        .maxLines(1)
    }
    .height(26)
    // 内边距 6→4：4 chip + 2 操作图标在 260vp 面板内原本越界 14vp（实测右缘 639px vs 面板 612px）
    .padding({ left: 4, right: 4 })
    .borderRadius(6)
    // ⚠️ 选中态配色：surface2（#F4F5F7 级近白灰）与面板底色几乎无差，实测 20×20 区域众数色
    //    为 #FEFFFF/#F4F5F7/#F6F7F9 —— 用户在文件视图看不出当前视图。改用与 Ribbon 选中底
    //    一致的紫色低透明（#14705DCF = 主色 8%），保证选中可辨且不喧宾夺主。
    .backgroundColor(this.sidebarView === key ? '#14705DCF' : Color.Transparent)
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onClick(() => {
      this.sidebarView = key;
      if (key === 'tags') {
        this.allTags = WorkspaceService.getInstance().getAllTags();
      }
    })
  }

  @Builder
  IconAction(icon: string, onTap: () => void) {
    Row() {
      TablerIcon(icon, 15, $r('app.color.icon_color'))
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .onClick(() => {
      onTap();
    })
  }

  /** 标签视图：列出全库标签（点击进入搜索面板） */
  @Builder
  TagListView() {
    Column({ space: 0 }) {
      Row() {
        Text('标签')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      if (this.allTags.length === 0) {
        this.EmptyHint('本库暂无标签（在块中输入 #标签 即可创建）')
      } else {
        ForEach(this.allTags, (tag: string) => {
          Row({ space: 6 }) {
            TablerIcon('tag', 13, $r('app.color.muted_text'))
            Text('#' + tag)
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .maxLines(1)
              .layoutWeight(1)
          }
          .width('100%')
          .height(30)
          .padding({ left: 12, right: 10 })
          .onClick(() => {
            AppState.setSearchPanelOpen(true);
          })
        }, (tag: string) => tag)
      }
      Blank()
    }
    .layoutWeight(1)
    .width('100%')
  }
  /**
   * 活动栏图标按钮（40vp 热区 + 选中高亮 + 悬停/按压三态）。
   */
  @Builder
  StripIcon(icon: string, key: string, active: boolean, onTap: () => void) {
    Row() {
      TablerIcon(icon, 18, active ? $r('app.color.primary') : $r('app.color.icon_color'))
    }
    .width(36)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .margin({ left: 4, right: 4 })
    .backgroundColor(active || this.hoveredStrip === key ? $r('app.color.surface2') : Color.Transparent)
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredStrip = isHover ? key : '';
    })
    .onClick(() => {
      onTap();
    })
  }

  @Builder
  ViewSwitchIcon(icon: string, active: boolean, onTap: () => void) {
    Row() {
      TablerIcon(icon, 16, active ? $r('app.color.text') : $r('app.color.icon_color'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width(40)
    .height(40)
    .borderRadius(6)
    .stateStyles({
      normal: {
        .backgroundColor(active
          ? $r('app.color.surface2')
          : (this.hoveredViewIcon === icon ? $r('app.color.surface1') : Color.Transparent))
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredViewIcon = isHover ? icon : '';
    })
    .onClick(() => {
      onTap();
    })
  }

  /**
   * 文件树工具行按钮（Obsidian 左栏第二行）。
   * 三态齐全：正常 / 悬停 / 按下；每个按钮均绑定**真实动作**，不做空壳按钮。
   */
  @Builder
  TreeToolIcon(icon: string, key: string, onTap: () => void) {
    Row() {
      TablerIcon(icon, 16, $r('app.color.icon_color'))
    }
    .width(40)
    .height(40)
    .borderRadius(6)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredTool === key ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredTool = isHover ? key : '';
    })
    .onClick(() => {
      onTap();
    })
  }

  /** 生成不重名的页面名（基准名 + 递增序号） */
  private uniquePageName(base: string): string {
    const ws = WorkspaceService.getInstance();
    if (ws.getPageByName(base) === undefined) {
      return base;
    }
    let i = 2;
    while (ws.getPageByName(base + ' ' + i.toString()) !== undefined) {
      i++;
    }
    return base + ' ' + i.toString();
  }

  /**
   * 新建笔记：创建后立即进入内联重命名，省去二次点击。
   */
  private createNewNote(): void {
    const ws = WorkspaceService.getInstance();
    const name = this.uniquePageName('未命名');
    ws.createPage(name);
    this.allPages = ws.getAllPages();
    this.startRename(name);
    AppState.setCurrentPage(name);
  }

  /**
   * 新建命名空间页面。
   * 本项目以「页面名含 `/`」表达层级（PageData.namespace 由此派生），
   * 因此新建 `命名空间/未命名` 即会在文件树中生成一个可折叠的分组节点。
   */
  private createNewNamespace(): void {
    const ws = WorkspaceService.getInstance();
    let ns = '新文件夹';
    let i = 2;
    while (this.namespaceExists(ns)) {
      ns = '新文件夹 ' + i.toString();
      i++;
    }
    const full = ns + '/未命名';
    ws.createPage(full);
    this.allPages = ws.getAllPages();
    this.startRename(full);
    AppState.setCurrentPage(full);
  }

  private namespaceExists(ns: string): boolean {
    for (let i = 0; i < this.allPages.length; i++) {
      if (this.allPages[i].namespace === ns) {
        return true;
      }
    }
    return false;
  }

  /** 全部折叠 / 全部展开（三组状态一致时切换方向） */
  private toggleCollapseAll(): void {
    const allCollapsed = this.collapsedFavorites && this.collapsedRecent && this.collapsedAllPages;
    const target = !allCollapsed;
    this.collapsedFavorites = target;
    this.collapsedRecent = target;
    this.collapsedAllPages = target;
  }

  /**
   * section header — Logseq 可折叠分组（保留基因，弱化为 Obsidian 树风格）。
   */
  @Builder
  SectionHeader(title: string, sectionKey: string, collapsed: boolean) {
    Row({ space: 2 }) {
      TablerIcon(collapsed ? 'chevron-right' : 'chevron-down', 12, $r('app.color.muted_text'))
      Text(title)
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.6)
    }
    .width('100%')
    .constraintSize({ minHeight: 40 })
    // 与导航行同一左基准 16vp（原先 12vp，导致分组标题比导航行左移 4vp）
    .padding({ left: 16, right: 16, top: 12, bottom: 4 })
    .borderRadius(4)
    .onClick(() => {
      this.toggleSection(sectionKey);
    })
  }

  @Builder
  SectionSpacer() {
    Column().width('100%').height(8)
  }

  @Builder
  EmptyHint(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.muted_text'))
      // 必须显式占满宽度并左对齐：Column 默认 alignItems 为 Center，否则空态文案会被居中，与列表左对齐不一致
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ left: 22, right: 16, top: 4, bottom: 4 })
      .opacity(0.7)
  }

  /**
   * 导航行背景：激活 > 悬停 > 透明（悬停态仅在鼠标设备生效）。
   */
  private navRowBackground(item: NavItem): ResourceColor {
    if (this.currentPage === item.key) {
      return $r('app.color.accent_soft');
    }
    if (this.hoveredNavKey === item.key) {
      return $r('app.color.surface2');
    }
    return Color.Transparent;
  }

  /**
   * 导航项 row — Obsidian 树行风格（当前项 accent 软背景）。
   */
  @Builder
  NavRow(item: NavItem) {
    Row({ space: 8 }) {
      TablerIcon(item.iconName, 16,
        this.currentPage === item.key
          ? $r('app.color.primary')
          : $r('app.color.icon_color'))
      Text(item.label)
        .fontSize(13.5)
        .fontColor($r('app.color.text'))
        .fontWeight(this.currentPage === item.key ? FontWeight.Medium : FontWeight.Normal)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(40)
    // 4(margin) + 12 = 16vp 左基准，与分组标题/Vault 行对齐
    .padding({ left: 12, right: 10 })
    .margin({ left: 4, right: 4 })
    .borderRadius(6)
    .stateStyles({
      normal: { .backgroundColor(this.navRowBackground(item)) },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredNavKey = isHover ? item.key : '';
    })
    .onClick(() => {
      // 仅窄屏抽屉模式导航后收起侧栏，宽屏保持常开
      if (this.isCompact()) {
        AppState.setLeftSidebarOpen(false);
      }
      if ((item.key === 'Flashcards' && !SubscriptionService.canUseFeature('flashcard')) ||
        (item.key === 'Pdf' && !SubscriptionService.canUseFeature('pdf'))) {
        AppState.setCurrentPage('ProUpgrade');
      } else {
        AppState.setCurrentPage(item.key);
      }
    })
  }

  /**
   * 页面项 row — Obsidian 文件树行风格（hover 显示操作按钮）。
   */
  @Builder
  PageLink(name: string) {
    Row({ space: 8 }) {
      if (this.renamingPage === name) {
        TextInput({ text: this.renameText })
          .fontSize(13)
          .layoutWeight(1)
          .height(26)
          .onChange((value: string) => { this.renameText = value; })
          .onSubmit(() => { this.commitRename(); })
      } else {
        TablerIcon('file', 14, $r('app.color.muted_text'))
        Text(name)
          .fontSize(13.5)
          .fontColor($r('app.color.text'))
          .fontWeight(this.currentPage === name ? FontWeight.Medium : FontWeight.Normal)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.hoveredPage === name) {
        Row() { TablerIcon('edit', 14, $r('app.color.icon_color')) }
          .width(24)
          .height(24)
          .borderRadius(4)
          .opacity(0.7)
          .onClick(() => { this.startRename(name); })
        Row() { TablerIcon('trash', 14, $r('app.color.danger')) }
          .width(24)
          .height(24)
          .borderRadius(4)
          .opacity(0.7)
          .onClick(() => { this.deletePage(name); })
      }
    }
    .width('100%')
    .height(40)
    // 子级缩进一级：4(margin) + 18 = 22vp
    .padding({ left: 18, right: 10 })
    .margin({ left: 4, right: 4 })
    .borderRadius(6)
    .stateStyles({
      normal: {
        .backgroundColor(this.currentPage === name
          ? $r('app.color.accent_soft')
          : (this.hoveredPage === name ? $r('app.color.surface1') : Color.Transparent))
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredPage = isHover ? name : '';
    })
    // 整行命中：原先 onClick 仅挂在 Text 上，行内空白区域点击无效
    .onClick(() => {
      AppState.setCurrentPage(name);
    })
  }

  startRename(oldName: string): void {
    this.renamingPage = oldName;
    this.renameText = oldName;
  }

  commitRename(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.renamingPage);
    if (page && this.renameText !== '' && this.renameText !== this.renamingPage) {
      ws.getDataStore().renamePage(page.uuid, this.renameText);
    }
    this.renamingPage = '';
    this.renameText = '';
    this.allPages = WorkspaceService.getInstance().getAllPages();
  }

  deletePage(pageName: string): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (page) {
      ws.getDataStore().deletePage(page.uuid);
      this.allPages = ws.getAllPages();
    }
  }

  getNamespaceGroups(): string[] {
    const ns: string[] = [''];
    for (let i = 0; i < this.allPages.length; i++) {
      const n = this.allPages[i].namespace;
      if (n && ns.indexOf(n) === -1) {
        ns.push(n);
      }
    }
    // 分组名排序（'' 永远置首，代表无命名空间的顶层页面）
    const head = ns[0];
    const rest = ns.slice(1).sort();
    if (this.sortDesc) {
      rest.reverse();
    }
    const out: string[] = [head];
    for (let i = 0; i < rest.length; i++) {
      out.push(rest[i]);
    }
    return out;
  }

  getPagesByNamespace(ns: string): PageData[] {
    const r: PageData[] = [];
    for (let i = 0; i < this.allPages.length; i++) {
      if (this.allPages[i].namespace === ns) {
        r.push(this.allPages[i]);
      }
    }
    // 按显示名排序，方向由工具行排序按钮控制
    r.sort((a: PageData, b: PageData) => {
      const x = a.originalName;
      const y = b.originalName;
      return x < y ? -1 : (x > y ? 1 : 0);
    });
    if (this.sortDesc) {
      r.reverse();
    }
    return r;
  }
}
