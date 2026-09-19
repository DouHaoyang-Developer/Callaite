import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { TabState } from '../../state/TabState';
import { GlassSurface } from '../common/GlassSurface';
import { GlassMode } from '../common/GlassSurface';
import { MaterialRole } from '../../theme/MaterialTokens';

/**
 * MobileBottomBar — Obsidian iOS 底部悬浮玻璃胶囊栏（Obsidian_iphone 1/6/7 截图）：
 * [← 后退] [→ 前进] | [🔍 快速切换] [＋ 新标签] [[N] 标签总览] [☰ 菜单]
 *
 * 玻璃光感悬浮于内容之上，距底部 34vp 避开手势条。
 * 宽度自适应：占视口 92%，上限 336vp —— 避免在 ≤360vp 窄屏（如折叠屏外屏）溢出。
 */
@Component
export struct MobileBottomBar {
  @StorageLink('callaite_tabsVersion') tabsVersion: number = 0;
  @StorageLink('callaite_historyBack') historyBackTrigger: number = 0;
  @StorageLink('callaite_historyForward') historyForwardTrigger: number = 0;
  @State hoveredKey: string = '';

  private tabCount(): number {
    const n = TabState.getTabs().length;
    return n > 99 ? 99 : n;
  }

  /**
   * 点击单元 —— 统一承载悬停/按压/禁用反馈。
   */
  @Builder
  PillIcon(itemKey: string, icon: string, enabled: boolean, onTap: () => void) {
    Row() {
      TablerIcon(icon, 22, enabled ? $r('app.color.text') : $r('app.color.muted_text'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width(44)
    .height(44)
    .borderRadius(14)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredKey === itemKey && enabled ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .opacity(enabled ? 1 : 0.35)
    .onHover((isHover: boolean) => {
      this.hoveredKey = isHover ? itemKey : '';
    })
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  @Builder
  TabCountBadge() {
    Row() {
      Text('[' + this.tabCount().toString() + ']')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text'))
    }
    .width(44)
    .height(44)
    .borderRadius(14)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: {
        .backgroundColor(this.hoveredKey === 'tabcount' ? $r('app.color.surface2') : Color.Transparent)
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredKey = isHover ? 'tabcount' : '';
    })
    .onClick(() => {
      AppStorage.setOrCreate('callaite_tabOverviewOpen', true);
    })
  }

  build() {
    Row() {
      GlassSurface({
        radius: 28,
        fill: $r('app.color.glass_fill'),
        mode: GlassMode.EFFECT,
        // 官方规范：底部悬浮组件推荐 THIN 档 + 渐变颜色蒙层
        materialRole: MaterialRole.BOTTOM_FLOATING
      }) {
        Row() {
          this.PillIcon('back', 'chevron-left', AppState.canGoBack(), () => {
            AppState.goBack();
          })
          this.PillIcon('forward', 'chevron-right', AppState.canGoForward(), () => {
            AppState.goForward();
          })
          this.PillIcon('search', 'search', true, () => {
            AppState.setSearchPanelOpen(true);
          })
          this.PillIcon('newtab', 'plus', true, () => {
            TabState.newTab('Journal');
          })
          this.TabCountBadge()
          this.PillIcon('menu', 'menu-2', true, () => {
            AppStorage.setOrCreate('callaite_mobileMenuOpen', true);
          })
        }
        .width('100%')
        .height(56)
        .padding({ left: 10, right: 10 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('80%')
    .constraintSize({ maxWidth: 336 })
    .height(56)
  }
}
