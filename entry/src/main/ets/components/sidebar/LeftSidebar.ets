import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { SubscriptionService } from '../../services/SubscriptionService';

interface NavItem {
  key: string;          // 唯一标识，对应 AppState.currentPage 值
  label: string;        // i18n 标题
  iconName: string;     // Tabler 图标名
}

/**
 * LeftSidebar — 按 logseq left_sidebar.cljs 布局复刻
 *
 * 结构（自上而下）：
 *   ┌──────────────────────┐
 *   │ App Name Header      │
 *   ├──────────────────────┤
 *   │ NAVIGATION（导航区）  │  ← 新增：Journal / AllPages / Graph / Flashcards
 *   ├──────────────────────┤
 *   │ FAVORITES（收藏夹）   │
 *   ├──────────────────────┤
 *   │ RECENT（最近访问）    │
 *   ├──────────────────────┤
 *   │ ALL PAGES（页面树）   │  按命名空间分组
 *   ├──────────────────────┤
 *   │ Settings Footer      │
 *   └──────────────────────┘
 *
 * 视觉规则：
 *  - 当前页 highlight 用 primary 色文字 + 浅色背景
 *  - section header 全大写、11px、muted_text、左侧带小图标
 *  - 页面项左缩进 20px，hover/current 高亮
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
  // 分组折叠态（持久化，Logseq sidebar-content-group）
  @StorageLink('callaite_collapsed_favorites') collapsedFavorites: boolean = false;
  @StorageLink('callaite_collapsed_recent') collapsedRecent: boolean = false;
  @StorageLink('callaite_collapsed_allpages') collapsedAllPages: boolean = false;

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    this.allPages = ws.getAllPages();
    this.refreshSidebarData();
  }

  /**
   * 修复：favoritesRaw 变化时重新解析收藏列表。
   * 此前仅在 aboutToAppear 调用 refreshSidebarData，外部添加/删除收藏后左侧栏不刷新。
   */
  onFavoritesChanged(): void {
    this.refreshFavorites();
  }

  /**
   * 修复：recentRaw 变化时重新解析最近访问列表。
   */
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
      try { this.recent = JSON.parse(this.recentRaw) as string[] ?? []; } catch (e) { this.recent = []; }
    } else {
      this.recent = [];
    }
  }

  refreshSidebarData(): void {
    this.refreshFavorites();
    this.refreshRecent();
  }

  /**
   * 导航项列表 — 对应 logseq sidebar 顶部 nav 区。
   * 注意：必须是普通方法 —— ArkTS 编译器会静默丢弃 @Component struct 上的
   * getter（导致 navItems 为 undefined，导航区整体不渲染）。
   */
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

  /**
   * 切换分组折叠态（Logseq sidebar-content-group 可折叠交互）。
   */
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
    Column({ space: 0 }) {
      // ─── App Name Header ───
      Row({ space: 10 }) {
        TablerIcon('bolt', 20, $r('app.color.primary'))
        Text(t('app_name'))
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(48)
      .padding({ left: 18, right: 16 })

      Divider().color($r('app.color.border')).width('100%')

      // ─── 可滚动主体 ───
      Scroll() {
        Column({ space: 0 }) {
          // 导航区（logseq sidebar 顶部）
          this.SectionHeader(t('sidebar_navigations'), 'menu-2')
          ForEach(this.getNavItems(), (item: NavItem) => {
            this.NavRow(item)
          }, (item: NavItem) => item.key)
          this.SectionSpacer()

          // 收藏夹（可折叠分组）
          this.SectionHeader(t('favorites'), 'pin', 'favorites', this.collapsedFavorites)
          if (!this.collapsedFavorites) {
            ForEach(this.favorites, (name: string) => { this.PageLink(name); }, (name: string) => name)
            if (this.favorites.length === 0) this.EmptyHint(t('empty_sidebar_hint'))
          }
          this.SectionSpacer()

          // 最近页面（可折叠分组）
          this.SectionHeader(t('recent'), 'refresh', 'recent', this.collapsedRecent)
          if (!this.collapsedRecent) {
            ForEach(this.recent.slice(0, 8), (name: string) => { this.PageLink(name); }, (name: string) => name)
            if (this.recent.length === 0) this.EmptyHint(t('empty_sidebar_hint'))
          }
          this.SectionSpacer()

          // 所有页面（按命名空间分组，可折叠）
          this.SectionHeader(t('all_pages'), 'file', 'allpages', this.collapsedAllPages)
          if (!this.collapsedAllPages) {
            ForEach(this.getNamespaceGroups(), (ns: string) => {
              if (ns !== '') {
                Row({ space: 6 }) {
                  TablerIcon('folder', 16, $r('app.color.icon_color'))
                  Text(ns)
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.muted_text'))
                }
                .width('100%')
                .padding({ left: 20, top: 10, bottom: 4 })
              }
              ForEach(this.getPagesByNamespace(ns), (page: PageData) => {
                this.PageLink(page.originalName);
              }, (page: PageData) => page.uuid)
            }, (ns: string) => ns)
            if (this.allPages.length === 0) this.EmptyHint(t('empty_page'))
          }
        }.width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // ─── Footer：设置 ───
      Divider().color($r('app.color.border')).width('100%')
      Row({ space: 8 }) {
        TablerIcon('settings', 18, $r('app.color.icon_color'))
        Text(t('settings')).fontSize(14).fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .height(40)
      .padding({ left: 18, right: 16 })
      .onClick(() => {
        AppState.setLeftSidebarOpen(false);
        AppState.setCurrentPage('Settings');
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4, bottom: 4 })
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { right: 1 }, color: $r('app.color.border') })
  }

  /**
   * section header — 大写 + 11px + muted_text + 小图标。
   * sectionKey 非空时渲染为可折叠分组（Logseq sidebar-content-group）：
   * 左侧 chevron 指示折叠态，点击整行切换。
   */
  @Builder
  SectionHeader(title: string, iconName: string, sectionKey: string = '', collapsed: boolean = false) {
    Row({ space: 6 }) {
      if (sectionKey !== '') {
        TablerIcon(collapsed ? 'chevron-right' : 'chevron-down', 12, $r('app.color.icon_color'))
      }
      TablerIcon(iconName, 14, $r('app.color.icon_color'))
      Text(title.toUpperCase())
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.muted_text'))
        .letterSpacing(0.6)
    }
    .width('100%')
    .padding({ left: sectionKey !== '' ? 12 : 20, right: 16, top: 14, bottom: 6 })
    .borderRadius(4)
    .onClick(() => {
      if (sectionKey !== '') {
        this.toggleSection(sectionKey);
      }
    })
  }

  @Builder
  SectionSpacer() {
    Divider()
      .color($r('app.color.border'))
      .width('100%')
      .margin({ left: 16, right: 16, top: 2, bottom: 2 })
  }

  @Builder
  EmptyHint(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.muted_text'))
      .padding({ left: 20, right: 16, top: 4, bottom: 4 })
      .opacity(0.7)
  }

  /**
   * 导航项 row — logseq sidebar nav 风格。
   * 选中时 primary 色文字 + 浅色背景。
   */
  @Builder
  NavRow(item: NavItem) {
    Row({ space: 10 }) {
      TablerIcon(item.iconName, 20,
        this.currentPage === item.key
          ? $r('app.color.primary')
          : $r('app.color.icon_color'))
      Text(item.label)
        .fontSize(14)
        .fontColor(this.currentPage === item.key
          ? $r('app.color.primary')
          : $r('app.color.text'))
        .fontWeight(this.currentPage === item.key ? FontWeight.Medium : FontWeight.Normal)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(40)
    .padding({ left: 20, right: 14 })
    .borderRadius(4)
    .backgroundColor(this.currentPage === item.key
      ? $r('app.color.surface2')
      : Color.Transparent)
    .onClick(() => {
      // 导航后关闭抽屉（窄屏模式），避免遮挡目标页面
      AppState.setLeftSidebarOpen(false);
      if ((item.key === 'Flashcards' && !SubscriptionService.canUseFeature('flashcard')) ||
        (item.key === 'Pdf' && !SubscriptionService.canUseFeature('pdf'))) {
        AppState.setCurrentPage('ProUpgrade');
      } else {
        AppState.setCurrentPage(item.key);
      }
    })
  }

  /**
   * 页面项 row — logseq sidebar page 风格。
   * 含 rename/delete 操作按钮（hover 时显示）。
   */
  @Builder
  PageLink(name: string) {
    Row({ space: 10 }) {
      if (this.renamingPage === name) {
        TextInput({ text: this.renameText })
          .fontSize(13)
          .layoutWeight(1)
          .height(26)
          .onChange((value: string) => { this.renameText = value; })
          .onSubmit(() => { this.commitRename(); })
      } else {
        Text(name)
          .fontSize(14)
          .fontColor(this.currentPage === name
            ? $r('app.color.primary')
            : $r('app.color.text'))
          .fontWeight(this.currentPage === name ? FontWeight.Medium : FontWeight.Normal)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .onClick(() => { AppState.setCurrentPage(name); })
      }
      Row() { TablerIcon('edit', 16, $r('app.color.icon_color')) }
        .width(28)
        .height(28)
        .opacity(0.4)
        .onClick(() => { this.startRename(name); })
      Row() { TablerIcon('trash', 16, $r('app.color.danger')) }
        .width(28)
        .height(28)
        .opacity(0.4)
        .onClick(() => { this.deletePage(name); })
    }
    .width('100%')
    .height(40)
    .padding({ left: 20, right: 14 })
    .borderRadius(4)
    .backgroundColor(this.currentPage === name
      ? $r('app.color.surface2')
      : Color.Transparent)
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
    return ns;
  }

  getPagesByNamespace(ns: string): PageData[] {
    const r: PageData[] = [];
    for (let i = 0; i < this.allPages.length; i++) {
      if (this.allPages[i].namespace === ns) {
        r.push(this.allPages[i]);
      }
    }
    return r;
  }
}
