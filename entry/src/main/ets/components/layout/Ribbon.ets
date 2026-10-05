import { ConfigurationConstant } from '@kit.AbilityKit';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { ThemeManager } from '../common/ThemeManager';
import { SubscriptionService } from '../../services/SubscriptionService';
import { Motion, Radius, Size, Space } from '../../utils/DesignTokens';

interface RibbonItem {
  key: string;       // 激活态判定（对应 AppState.currentPage 或动作 key）
  icon: string;      // Tabler 图标名
  label: string;     // 无障碍描述
  action: string;    // 'route' | 'search' | 'palette' | 'newFile' | 'toggleLeft'
  route?: string;    // action=route 时的目标页
}

/**
 * Ribbon — Obsidian 桌面端最左侧竖排图标栏（复刻自 Obsidian_Laptop.png 左缘）。
 *
 * 布局：上层功能图标（侧栏开关/全局搜索/图谱/白板/闪卡/命令面板），
 *       底部系统图标（主题切换/设置）。
 * 材质：玻璃光感半透明填充，与氛围渐变背景叠加产生通透感。
 */
@Component
export struct Ribbon {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  // 键名必须是 ThemeManager 的规范键（callaite_themeMode）。
  // 历史上这里写的是无前缀 'themeMode'：该键只有 AppState 在启动/设置时写过，
  // ThemeManager.setThemeMode / toggleTheme 从不写它，导致主题切换后本组件收不到通知。
  @StorageLink('callaite_themeMode') themeMode: string = 'system';
  @StorageLink('callaite_systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  @State hoveredKey: string = '';

  /**
   * Ribbon 图标按钮背景：激活 > 悬停 > 透明。
   * 抽成方法以便 stateStyles.normal 复用（保证状态切换动画连续）。
   */
  private itemBackground(key: string, active: boolean): ResourceColor {
    if (active) {
      return $r('app.color.accent_soft');
    }
    if (this.hoveredKey === key) {
      return $r('app.color.surface2');
    }
    return Color.Transparent;
  }

  private isDark(): boolean {
    if (this.themeMode === 'dark') {
      return true;
    }
    if (this.themeMode === 'light') {
      return false;
    }
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private topItems(): RibbonItem[] {
    const items: RibbonItem[] = [];
    items[0] = { key: 'sidebar', icon: 'layout-sidebar', label: t('ribbon_toggle_sidebar'), action: 'toggleLeft' };
    // U1.6：放大镜图标 = 全局搜索面板（SearchPanel，搜页面名 + 块内容）。
    // 原先它指向命令面板，与 terminal-2 图标重复；拆分后两者语义不再重叠。
    items[1] = { key: 'search', icon: 'search', label: t('search'), action: 'search' };
    items[2] = { key: 'Graph', icon: 'hierarchy', label: t('ribbon_graph'), action: 'route', route: 'Graph' };
    items[3] = { key: 'Whiteboards', icon: 'layout-grid', label: t('ribbon_whiteboard'), action: 'route', route: 'Whiteboards' };
    items[4] = { key: 'Flashcards', icon: 'stack-2', label: t('ribbon_flashcards'), action: 'route', route: 'Flashcards' };
    items[5] = { key: 'palette', icon: 'terminal-2', label: t('ribbon_command'), action: 'palette' };
    // ─── W1（方案三）：活动栏图标列下线后迁入的入口 ───
    //   原活动栏 44vp 图标列的独有入口统一收敛到 Ribbon 这一条图标条上，
    //   与 Obsidian「只有一条 Ribbon」的形态一致（见 UI 改造计划 §2.2）。
    items[6] = { key: 'new', icon: 'file-plus', label: t('new_page'), action: 'newFile' };
    items[7] = { key: 'Journal', icon: 'calendar', label: t('nav_journals'), action: 'route', route: 'Journal' };
    items[8] = { key: 'AllPages', icon: 'files', label: t('nav_all_pages'), action: 'route', route: 'AllPages' };
    items[9] = { key: 'Pdf', icon: 'file', label: 'PDF', action: 'route', route: 'Pdf' };
    return items;
  }

  private handle(item: RibbonItem): void {
    if (item.action === 'toggleLeft') {
      AppState.toggleLeftSidebar();
    } else if (item.action === 'search') {
      // U1.6：全局搜索面板（SearchPanel）—— 与命令面板是两件事、两把键
      AppState.setSearchPanelOpen(true);
    } else if (item.action === 'palette') {
      // U1.6：命令面板 / 快速切换（CommandPalette）
      AppState.setCommandPaletteOpen(true);
    } else if (item.action === 'newFile') {
      // 原活动栏「新建」入口（打开新建文件对话框）
      AppStorage.setOrCreate('callaite_newFileDialogOpen', true);
    } else if (item.action === 'route' && item.route !== undefined) {
      // 订阅限制沿用原导航逻辑（闪卡受限 → 引导升级页）
      if (item.route === 'Flashcards' && !SubscriptionService.canUseFeature('flashcard')) {
        AppState.setCurrentPage('ProUpgrade');
      } else {
        AppState.setCurrentPage(item.route);
      }
    }
  }

  private isItemActive(item: RibbonItem): boolean {
    return item.action === 'route' && this.currentPage === item.key;
  }

  build() {
    Column() {
      // ─── 上层功能图标 ───
      Column({ space: Space.XS }) {
        ForEach(this.topItems(), (item: RibbonItem) => {
          Row() {
            TablerIcon(item.icon, 20,
              this.isItemActive(item) ? $r('app.color.primary') :
                (item.key === 'sidebar' && this.leftSidebarOpen ? $r('app.color.primary') : $r('app.color.icon_color')))
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .width(Size.TOUCH_MIN)
          .height(Size.TOUCH_MIN)
          .borderRadius(Radius.MD)
          .stateStyles({
            normal: {
              .backgroundColor(this.itemBackground(item.key,
                this.isItemActive(item) || (item.key === 'sidebar' && this.leftSidebarOpen)))
            },
            pressed: { .backgroundColor($r('app.color.surface3')) }
          })
          .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
          .onHover((isHover: boolean) => {
            this.hoveredKey = isHover ? item.key : '';
          })
          .onClick(() => {
            this.handle(item);
          })
        }, (item: RibbonItem) => item.key)
      }
      .width('100%')

      Blank()

      // ─── 底部系统图标 ───
      Column({ space: Space.XS }) {
        Row() {
          TablerIcon(this.isDark() ? 'sun' : 'moon', 20, $r('app.color.icon_color'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(Size.TOUCH_MIN)
        .height(Size.TOUCH_MIN)
        .borderRadius(Radius.MD)
        .stateStyles({
          normal: { .backgroundColor(this.itemBackground('theme', false)) },
          pressed: { .backgroundColor($r('app.color.surface3')) }
        })
        .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
        .onHover((isHover: boolean) => {
          this.hoveredKey = isHover ? 'theme' : '';
        })
        .onClick(() => {
          ThemeManager.toggleTheme();
        })

        Row() {
          TablerIcon('settings', 20, $r('app.color.icon_color'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(Size.TOUCH_MIN)
        .height(Size.TOUCH_MIN)
        .borderRadius(Radius.MD)
        .stateStyles({
          normal: { .backgroundColor(this.itemBackground('settings', this.currentPage === 'Settings')) },
          pressed: { .backgroundColor($r('app.color.surface3')) }
        })
        .animation({ duration: Motion.BASE, curve: Curve.EaseOut })
        .onHover((isHover: boolean) => {
          this.hoveredKey = isHover ? 'settings' : '';
        })
        .onClick(() => {
          AppState.setCurrentPage('Settings');
        })
      }
      .width('100%')
    }
    .width(Size.BAR)
    .height('100%')
    .padding({ top: Space.SM, bottom: Space.SM })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { right: 0.5 }, color: $r('app.color.border') })
  }
}
