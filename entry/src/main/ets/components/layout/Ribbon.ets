import { ConfigurationConstant } from '@kit.AbilityKit';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { ThemeManager } from '../common/ThemeManager';
import { SubscriptionService } from '../../services/SubscriptionService';

interface RibbonItem {
  key: string;       // 激活态判定（对应 AppState.currentPage 或动作 key）
  icon: string;      // Tabler 图标名
  label: string;     // 无障碍描述
  action: string;    // 'route' | 'palette' | 'theme' | 'toggleLeft'
  route?: string;    // action=route 时的目标页
}

/**
 * Ribbon — Obsidian 桌面端最左侧竖排图标栏（复刻自 Obsidian_Laptop.png 左缘）。
 *
 * 布局：上层功能图标（侧栏开关/快速切换/图谱/白板/闪卡/命令面板），
 *       底部系统图标（主题切换/设置）。
 * 材质：玻璃光感半透明填充，与氛围渐变背景叠加产生通透感。
 */
@Component
export struct Ribbon {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('themeMode') themeMode: string = 'system';
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
    items[1] = { key: 'switcher', icon: 'search', label: t('ribbon_quick_switcher'), action: 'palette' };
    items[2] = { key: 'Graph', icon: 'hierarchy', label: t('ribbon_graph'), action: 'route', route: 'Graph' };
    items[3] = { key: 'Whiteboards', icon: 'layout-grid', label: t('ribbon_whiteboard'), action: 'route', route: 'Whiteboards' };
    items[4] = { key: 'Flashcards', icon: 'stack-2', label: t('ribbon_flashcards'), action: 'route', route: 'Flashcards' };
    items[5] = { key: 'palette', icon: 'terminal-2', label: t('ribbon_command'), action: 'palette' };
    return items;
  }

  private handle(item: RibbonItem): void {
    if (item.action === 'toggleLeft') {
      AppState.toggleLeftSidebar();
    } else if (item.action === 'palette') {
      AppState.setSearchPanelOpen(true);
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
      Column({ space: 4 }) {
        ForEach(this.topItems(), (item: RibbonItem) => {
          Row() {
            TablerIcon(item.icon, 20,
              this.isItemActive(item) ? $r('app.color.primary') :
                (item.key === 'sidebar' && this.leftSidebarOpen ? $r('app.color.primary') : $r('app.color.icon_color')))
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .width(40)
          .height(40)
          .borderRadius(8)
          .stateStyles({
            normal: {
              .backgroundColor(this.itemBackground(item.key,
                this.isItemActive(item) || (item.key === 'sidebar' && this.leftSidebarOpen)))
            },
            pressed: { .backgroundColor($r('app.color.surface3')) }
          })
          .animation({ duration: 140, curve: Curve.EaseOut })
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
      Column({ space: 4 }) {
        Row() {
          TablerIcon(this.isDark() ? 'sun' : 'moon', 20, $r('app.color.icon_color'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(40)
        .height(40)
        .borderRadius(8)
        .stateStyles({
          normal: { .backgroundColor(this.itemBackground('theme', false)) },
          pressed: { .backgroundColor($r('app.color.surface3')) }
        })
        .animation({ duration: 140, curve: Curve.EaseOut })
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
        .width(40)
        .height(40)
        .borderRadius(8)
        .stateStyles({
          normal: { .backgroundColor(this.itemBackground('settings', this.currentPage === 'Settings')) },
          pressed: { .backgroundColor($r('app.color.surface3')) }
        })
        .animation({ duration: 140, curve: Curve.EaseOut })
        .onHover((isHover: boolean) => {
          this.hoveredKey = isHover ? 'settings' : '';
        })
        .onClick(() => {
          AppState.setCurrentPage('Settings');
        })
      }
      .width('100%')
    }
    .width(46)
    .height('100%')
    .padding({ top: 6, bottom: 6 })
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { right: 0.5 }, color: $r('app.color.border') })
  }
}
