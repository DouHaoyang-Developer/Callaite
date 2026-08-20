import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { JournalService } from '../../services/JournalService';
import { t } from '../../utils/i18n';
import { ThemeManager } from '../common/ThemeManager';

/**
 * Header — 按 logseq header.cljs 布局复刻
 *
 * 结构（左→右）：
 *   [☰ 菜单] [← 后退] [→ 前进] [🔍 搜索]    [页面标题/面包屑]    [🏠 主页] [··· 更多] [UILayout 右侧栏]
 *
 * 历史栈变更通过 @StorageLink 监听 callaite_historyBack / callaite_historyForward 触发重渲染。
 */
@Component
export struct Header {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('callaite_rightSidebarOpen') rightSidebarOpen: boolean = false;
  // 历史栈触发器 — 用于驱动 build 重新计算 canBack/canForward
  @StorageLink('callaite_historyBack') private historyBackTrigger: number = 0;
  @StorageLink('callaite_historyForward') private historyForwardTrigger: number = 0;

  /**
   * 显示标题：Journal → 今日日期；其他 → 页面名。
   * 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
   */
  getDisplayTitle(): string {
    if (this.currentPage === 'Journal') {
      return JournalService.formatJournalTitle(JournalService.getTodayDateString());
    }
    // 日志日期页（yyyy-MM-dd）显示本地化日期
    if (/^\d{4}-\d{2}-\d{2}$/.test(this.currentPage)) {
      return JournalService.formatJournalTitle(this.currentPage);
    }
    return this.currentPage;
  }

  build() {
    Row({ space: 0 }) {
      // ─── 左侧：菜单 + 后退 + 前进 + 搜索（logseq header.cljs 左侧功能组）───
      // 菜单按钮必须始终可点击（enabled=true），否则抽屉关闭后无法再打开；
      // 打开状态通过 active 参数高亮表达。
      this.IconButton('menu-2', true,
        () => { AppState.toggleLeftSidebar(); }, this.leftSidebarOpen)

      this.IconButton('arrow-left', AppState.canGoBack(),
        () => { AppState.goBack(); })

      this.IconButton('arrow-right', AppState.canGoForward(),
        () => { AppState.goForward(); })

      this.IconButton('search', true,
        () => { AppState.setSearchPanelOpen(true); })

      Blank()

      // ─── 中间：页面标题居中（logseq header breadcrumb 位）───
      // 日志页的前后日期箭头紧贴标题两侧（logseq journal 标题箭头风格）
      Row({ space: 4 }) {
        if (this.currentPage === 'Journal') {
          Row() {
            TablerIcon('chevron-left', 16, $r('app.color.icon_color'))
          }
          .width(28).height(28).borderRadius(4)
          .onClick(() => {
            AppState.setCurrentPage(JournalService.getYesterdayDateString());
          })
        }

        Text(this.getDisplayTitle())
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.currentPage === 'Journal') {
          Row() {
            TablerIcon('chevron-right', 16, $r('app.color.icon_color'))
          }
          .width(28).height(28).borderRadius(4)
          .onClick(() => {
            AppState.setCurrentPage(JournalService.getTomorrowDateString());
          })
        }
      }
      .alignItems(VerticalAlign.Center)

      Blank()

      // ─── 右侧：主页 + 更多 + 右侧栏（logseq header 右侧开关组）───
      this.IconButton('home', this.currentPage !== 'Journal',
        () => { AppState.setCurrentPage('Journal'); })

      // 三点菜单（logseq toolbar-dots-menu）
      Row() {
        TablerIcon('dots-vertical', 20, $r('app.color.icon_color'))
      }
      .width(48).height(48).borderRadius(4)
      .bindMenu(this.DotsMenu)

      this.IconButton('layout-sidebar-right', true,
        () => { AppState.toggleRightSidebar(); }, this.rightSidebarOpen)
    }
    .width('100%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.surface0'))
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  /**
   * 通用图标按钮 Builder。
   * 华为规范：触控目标 ≥ 44vp；Logseq headbar 图标约 20vp。
   * active 参数用于在按钮处于激活态时使用主色高亮（如右侧栏已打开）。
   */
  @Builder
  IconButton(name: string, enabled: boolean, onClick: () => void, active: boolean = false) {
    Row() {
      TablerIcon(name, 20,
        enabled
          ? (active ? $r('app.color.primary') : $r('app.color.icon_color'))
          : $r('app.color.muted_text'))
    }
    .width(48).height(48).borderRadius(4)
    .opacity(enabled ? 1 : 0.4)
    .onClick(() => {
      if (enabled) {
        onClick();
      }
    })
  }

  /**
   * 三点菜单（logseq 的 toolbar-dots-menu）— 使用 Menu + MenuItemGroup 分组。
   * Menu 仅允许 Option/MenuItem/MenuItemGroup 子组件，组间自带分隔效果。
   */
  @Builder
  DotsMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: t('settings') })
          .onClick(() => { AppState.setCurrentPage('Settings'); })

        MenuItem({ content: t('nav_appearance') })
          .onClick(() => { ThemeManager.toggleTheme(); })

        MenuItem({ content: t('nav_recycle') })
          .onClick(() => { AppState.setCurrentPage('Recycle'); })

        MenuItem({ content: t('nav_graph_view') })
          .onClick(() => { AppState.setCurrentPage('Graph'); })

        MenuItem({ content: t('nav_flashcards') })
          .onClick(() => { AppState.setCurrentPage('Flashcards'); })
      }

      MenuItemGroup() {
        MenuItem({ content: t('nav_all_pages') })
          .onClick(() => { AppState.setCurrentPage('AllPages'); })

        MenuItem({ content: t('nav_export') })
          .onClick(() => { AppState.setExportDialogOpen(true); })

        MenuItem({ content: t('nav_import') })
          .onClick(() => { AppState.setImportDialogOpen(true); })
      }

      MenuItemGroup() {
        MenuItem({ content: t('nav_about') })
          .onClick(() => { AppState.setCurrentPage('About'); })
      }
    }
  }
}
