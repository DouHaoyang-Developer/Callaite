import { TablerIcon } from '../common/Icons';
import { PageTree } from './PageTree';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { SubscriptionService } from '../../services/SubscriptionService';
import { Breakpoints } from '../../state/Breakpoints';
import { countBacklinks } from '../../utils/BacklinkWarning';
import { promptAction } from '@kit.ArkUI';
import { Font, Motion, Radius, Size, Space } from '../../utils/DesignTokens';

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
    Row({ space: Space.NONE }) {
      // ─── 方案三（W1）：44vp 活动栏图标列已下线，面板独占侧栏宽度 ───
      //   原图标列入口去向：新建 → 顶部操作行；仓库 → 顶部操作行；
      //   收藏折叠 → 区段标题自带折叠；设置 → Ribbon 底部；
      //   Journal/AllPages/Pdf/图谱/白板/闪卡 → Ribbon（见 Ribbon.ets）。
      //   侧栏总宽仍为 SIDEBAR_DEFAULT(260vp)，去掉图标列后面板 216vp → 260vp
      //   （计划 §2.2 目标 240–260vp，落在区间上沿）。
      Column({ space: Space.NONE }) {
        this.ViewSwitcher()

        if (this.sidebarView !== 'tags') {
        Row({ space: Space.SM }) {
          TablerIcon('search', 14, $r('app.color.muted_text'))
          Text('搜索或开始搜索...')
            .fontSize(Font.LABEL)
            .fontColor($r('app.color.muted_text'))
            .layoutWeight(1)
            .maxLines(1)
        }
        .width('100%')
        .height(Size.ROW_SM)
        .padding({ left: Space.MD, right: Space.MD })
        .margin({ left: Space.SM, right: Space.SM, top: Space.SM })
        .borderRadius(Radius.MD)
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
    Row({ space: Space.HAIR }) {
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
    // S4-W1 热区规范：本行是**交互行**，行高取交互元素最小值 40vp
    // （原 36vp；chip 视觉随之从 26vp 变为 40vp —— 这是本窗口的试点改动）。
    .height(Size.TOUCH_MIN)
    .padding({ left: Space.SM, right: Space.SM })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  ViewChip(icon: string, key: string, label: string) {
    Row({ space: Space.XS }) {
      TablerIcon(icon, 12, this.sidebarView === key ? $r('app.color.primary') : $r('app.color.muted_text'))
      Text(label)
        .fontSize(Font.CAPTION)
        .fontColor(this.sidebarView === key ? $r('app.color.primary') : $r('app.color.muted_text'))
        .maxLines(1)
    }
    // S4-W1 热区规范：视图 chip 的命中短边从 24vp 提到交互元素最小值 40vp。
    // ⚠️ 只改**高度**、不动宽度 —— 本行是 260vp 侧栏里的 4 chip + 2 图标，
    //    横向本来就没有余量（L228 注释：曾越界 14vp）⇒ 加宽会直接复现溢出。
    .height(Size.TOUCH_MIN)
    // 内边距 6→4：4 chip + 2 操作图标在 260vp 面板内原本越界 14vp（实测右缘 639px vs 面板 612px）
    .padding({ left: Space.XS, right: Space.XS })
    .borderRadius(Radius.MD)
    // ⚠️ 选中态配色：surface2（#F4F5F7 级近白灰）与面板底色几乎无差，实测 20×20 区域众数色
    //    为 #FEFFFF/#F4F5F7/#F6F7F9 —— 用户在文件视图看不出当前视图。改用与 Ribbon 选中底
    //    一致的紫色低透明（主色 8%），保证选中可辨且不喧宾夺主。
    //    ⚠️ 这里原来内联了浅色值 '#14705DCF'，暗色下主色是 #A88BFA、该值几乎不可见
    //    （选中态在暗色下等于没有）。改用 Ribbon.ets:38 / TabBar.ets:157 同一 token。
    .backgroundColor(this.sidebarView === key ? $r('app.color.accent_soft') : Color.Transparent)
    .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
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
    .width(Size.ROW_SM)
    .height(Size.ROW_SM)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(Radius.MD)
    .onClick(() => {
      onTap();
    })
  }

  /** 标签视图：列出全库标签（点击进入搜索面板） */
  @Builder
  TagListView() {
    Column({ space: Space.NONE }) {
      Row() {
        Text('标签')
          .fontSize(Font.LABEL)
          .fontColor($r('app.color.muted_text'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: Space.MD, right: Space.MD, top: Space.SM, bottom: Space.XS })

      if (this.allTags.length === 0) {
        this.EmptyHint('本库暂无标签（在块中输入 #标签 即可创建）')
      } else {
        ForEach(this.allTags, (tag: string) => {
          Row({ space: Space.SM }) {
            // S3-W20 修：此处原为 'tag'（单数），而 TablerIconPaths 注册表（149 项）里只有 'tags'
            // ⇒ findIconPath() 返回 undefined ⇒ 该图标**静默不渲染**（全仓 123 处静态图标名中唯一一处未注册）。
            TablerIcon('tags', 13, $r('app.color.muted_text'))
            Text('#' + tag)
              .fontSize(Font.BODY_SM)
              .fontColor($r('app.color.text'))
              .maxLines(1)
              .layoutWeight(1)
          }
          .width('100%')
          .height(Size.ROW_SM)
          .padding({ left: Space.MD, right: Space.MD })
          .onClick(() => {
            // U1.6：标签行此前只「打开面板」而不注入过滤词 —— SearchPanel 挂载后，
            // 面板打开就是一张空的最近访问列表（看起来像坏了）。
            // 编辑器内点标签走的是同一意图（ContentRenderer：先写 callaite_tagFilter 再开面板），
            // 这里补齐这一步，让 SearchPanel 既有的 '#tag' 检索路径可被点击触达。
            AppStorage.setOrCreate('callaite_tagFilter', tag);
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
    .width(Size.ROW_LG)
    .height(Size.ROW_LG)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(Radius.MD)
    .margin({ left: Space.XS, right: Space.XS })
    // S4-W1 · U4.6 选中态统一：本条原用 surface2（近白灰），与面板底色几乎无差 ——
    // 与 ViewChip(L231-236) 的诊断逐字同源。全仓选中态收敛到 accent_soft 一套。
    .backgroundColor(active || this.hoveredStrip === key ? $r('app.color.accent_soft') : Color.Transparent)
    .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
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
    .width(Size.TOUCH_MIN)
    .height(Size.TOUCH_MIN)
    .borderRadius(Radius.MD)
    .stateStyles({
      normal: {
        .backgroundColor(active
          ? $r('app.color.accent_soft')
          : (this.hoveredViewIcon === icon ? $r('app.color.surface1') : Color.Transparent))
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
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
    .width(Size.TOUCH_MIN)
    .height(Size.TOUCH_MIN)
    .borderRadius(Radius.MD)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredTool === key ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
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
    // S4-W27（H2）：名字碰撞被拒时页面并不存在 —— 必须就此收手，
    // 否则会进入一个不存在的页面的重命名态并把当前页切过去。
    if (!ws.createPage(name)) {
      this.notifyNameCollision('未创建', name);
      return;
    }
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
    // S4-W27（H2）：同 createNewNote —— 被拒则不进重命名态、不切页。
    if (!ws.createPage(full)) {
      this.notifyNameCollision('未创建', full);
      return;
    }
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
    Row({ space: Space.HAIR }) {
      TablerIcon(collapsed ? 'chevron-right' : 'chevron-down', 12, $r('app.color.muted_text'))
      Text(title)
        .fontSize(Font.CAPTION)
        .fontColor($r('app.color.muted_text'))
        .textCase(TextCase.UpperCase)
        .letterSpacing(0.6)
    }
    .width('100%')
    .constraintSize({ minHeight: 40 })
    // 与导航行同一左基准 16vp（原先 12vp，导致分组标题比导航行左移 4vp）
    .padding({ left: Space.LG, right: Space.LG, top: Space.MD, bottom: Space.XS })
    .borderRadius(Radius.SM)
    .onClick(() => {
      this.toggleSection(sectionKey);
    })
  }

  @Builder
  SectionSpacer() {
    Column().width('100%').height(Size.XS)
  }

  @Builder
  EmptyHint(text: string) {
    Text(text)
      .fontSize(Font.LABEL)
      .fontColor($r('app.color.muted_text'))
      // 必须显式占满宽度并左对齐：Column 默认 alignItems 为 Center，否则空态文案会被居中，与列表左对齐不一致
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ left: 22, right: Space.LG, top: Space.XS, bottom: Space.XS })
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
    Row({ space: Space.SM }) {
      TablerIcon(item.iconName, 16,
        this.currentPage === item.key
          ? $r('app.color.primary')
          : $r('app.color.icon_color'))
      Text(item.label)
        .fontSize(Font.BODY_SM)
        .fontColor($r('app.color.text'))
        .fontWeight(this.currentPage === item.key ? FontWeight.Medium : FontWeight.Normal)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(Size.TOUCH_MIN)
    // 4(margin) + 12 = 16vp 左基准，与分组标题/Vault 行对齐
    .padding({ left: Space.MD, right: Space.MD })
    .margin({ left: Space.XS, right: Space.XS })
    .borderRadius(Radius.MD)
    .stateStyles({
      normal: { .backgroundColor(this.navRowBackground(item)) },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
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
    Row({ space: Space.SM }) {
      if (this.renamingPage === name) {
        TextInput({ text: this.renameText })
          .fontSize(Font.BODY_SM)
          .layoutWeight(1)
          .height(Size.MD)
          .onChange((value: string) => { this.renameText = value; })
          .onSubmit(() => { this.commitRename(); })
      } else {
        TablerIcon('file', 14, $r('app.color.muted_text'))
        Text(name)
          .fontSize(Font.BODY_SM)
          .fontColor($r('app.color.text'))
          .fontWeight(this.currentPage === name ? FontWeight.Medium : FontWeight.Normal)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.hoveredPage === name) {
        Row() { TablerIcon('edit', 14, $r('app.color.icon_color')) }
          .width(Size.MD)
          .height(Size.MD)
          .borderRadius(Radius.SM)
          .opacity(0.7)
          .onClick(() => { this.startRename(name); })
        Row() { TablerIcon('trash', 14, $r('app.color.danger')) }
          .width(Size.MD)
          .height(Size.MD)
          .borderRadius(Radius.SM)
          .opacity(0.7)
          .onClick(() => { this.deletePage(name); })
      }
    }
    .width('100%')
    .height(Size.TOUCH_MIN)
    // 子级缩进一级：4(margin) + 18 = 22vp
    .padding({ left: 18, right: Space.MD })
    .margin({ left: Space.XS, right: Space.XS })
    .borderRadius(Radius.MD)
    .stateStyles({
      normal: {
        .backgroundColor(this.currentPage === name
          ? $r('app.color.accent_soft')
          : (this.hoveredPage === name ? $r('app.color.surface1') : Color.Transparent))
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
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

  /**
   * S4-W27（H2 命名碰撞）：把「被拒绝」变成用户可见的反馈。
   *
   * 用本仓既有的提示机制 `promptAction.openToast`（全仓 30 处在用，
   * 如 IntegralEditor / PdfViewer / PluginAPI），不新造提示条。
   * 文案必须说清**为什么**失败 —— 名字本身看起来完全合法，
   * 只说「失败」会让用户以为应用坏了。
   */
  private notifyNameCollision(action: string, name: string): void {
    promptAction.openToast({
      message: '已存在同名文件，' + action +'：「' + name + '」'
    }).catch(() => {});
  }

  commitRename(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.renamingPage);
    if (page && this.renameText !== '' && this.renameText !== this.renamingPage) {
      // S4-W27（H2）：改名可能被拒（新名与**别的页**映射到同一个文件）。
      // 修复前这里无从知道成败，失败会静默 —— 现在上抛并给出可见反馈。
      if (!ws.getDataStore().renamePage(page.uuid, this.renameText)) {
        this.notifyNameCollision('未重命名', this.renameText);
      }
    }
    this.renamingPage = '';
    this.renameText = '';
    this.allPages = WorkspaceService.getInstance().getAllPages();
  }

  /**
   * 侧栏页面行的删除入口（原为「无确认、直接删」）。
   *
   * 改造原则 —— 平衡「删除=进回收站、无确认」的既定裁定与本项的反链预警诉求：
   *   本案的确认**只作为反链预警的载体**，不是阻断式二次确认，故按反链数分流：
   *     · N = 0（绝大多数页面）：与改造前**逐字节等价** —— 不弹任何框，一次点击直接删。
   *       既定裁定在常规路径上被完整保留。
   *     · N > 0：才弹一次知情提示。按钮文案用「取消 / 仍要删除」而非
   *       「取消 / 删除」，语义是「告知风险后放行」，落点仍在「删」上；
   *       且不置 memorized，用户可以一路确认下去，永不被永久拦截。
   *   即：确认的门槛由「是否有牵连」决定，而不是由「是否是删除」决定 —— 反链预警
   *   把破坏性操作的风险面显性化，代价只落在真正会牵连别处的少数页面上。
   *
   * 反链只在用户点击这一刻算一次（见 countBacklinks 的惰性约束），
   * 不会进入 hover / 列表渲染路径。
   */
  deletePage(pageName: string): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) {
      return;
    }
    const n: number = countBacklinks(ws.getDataStore(), pageName);
    if (n <= 0) {
      // 无被引用：保持既定「无确认」体验
      this.performDeletePage(page.uuid);
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '删除页面',
      message: '「' + pageName + '」被 ' + n.toString() + ' 处引用，删除后这些链接将失效。\n\n'
        + '此操作不可撤销，确定继续吗？',
      primaryButton: {
        value: t('cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: '仍要删除',
        fontColor: $r('app.color.danger'),
        action: (): void => {
          this.performDeletePage(page.uuid);
        }
      }
    });
  }

  /** 真正执行删除并刷新侧栏页面列表。 */
  private performDeletePage(pageUuid: string): void {
    const ws = WorkspaceService.getInstance();
    ws.getDataStore().deletePage(pageUuid);
    this.allPages = ws.getAllPages();
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
