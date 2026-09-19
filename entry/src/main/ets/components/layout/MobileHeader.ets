import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { pageTitle } from '../../utils/PageTitle';
import { GlassSurface } from '../common/GlassSurface';
import { GlassMode } from '../common/GlassSurface';
import { MaterialRole } from '../../theme/MaterialTokens';

/**
 * MobileHeader — Obsidian iOS 顶栏复刻（Obsidian_iphone 1/3/6/7 截图）：
 * 左上角圆形玻璃"侧栏"按钮 + 居中标题 + 右上角圆形玻璃"更多"按钮。
 * 内容在按钮下滚动，按钮为悬浮玻璃光感材质。
 *
 * 标题统一走 pageTitle()，避免把 Settings/AllPages 等内部路由名直接显示给用户。
 */
@Component
export struct MobileHeader {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  /** 状态栏安全区（沉浸式下内容延伸到状态栏之下，需自行避让） */
  @StorageLink('callaite_safeTop') safeTop: number = 0;
  @State hoverLeft: boolean = false;
  @State hoverRight: boolean = false;

  /**
   * 圆形玻璃按钮 —— 悬停/按压反馈（2in1 与折叠屏展开态可用鼠标）。
   */
  @Builder
  CircleButton(icon: string, hovered: boolean, onTap: () => void, onHoverChange: (h: boolean) => void) {
    Row() {
      GlassSurface({
        radius: 22,
        fill: $r('app.color.glass_fill'),
        mode: GlassMode.EFFECT,
        // 官方规范：顶部悬浮组件推荐 ULTRA_THIN 档（最通透、高光最明显）
        materialRole: MaterialRole.TOP_FLOATING
      }) {
        Row() {
          TablerIcon(icon, 20, $r('app.color.text'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .width(44)
    .height(44)
    .stateStyles({
      normal: { .opacity(1) },
      pressed: { .opacity(0.6) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .scale({ x: hovered ? 1.04 : 1, y: hovered ? 1.04 : 1 })
    .onHover((isHover: boolean) => {
      onHoverChange(isHover);
    })
    .onClick(() => {
      onTap();
    })
  }

  build() {
    Row({ space: 0 }) {
      // ─── 左：侧栏开关（圆形玻璃） ───
      this.CircleButton('layout-sidebar', this.hoverLeft, () => {
        AppState.toggleLeftSidebar();
      }, (h: boolean) => {
        this.hoverLeft = h;
      })

      // ─── 中：页面标题（占用剩余宽度并居中，避免固定 200vp 在宽/窄屏失衡）───
      Text(pageTitle(this.currentPage))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ left: 10, right: 10 })

      // ─── 右：更多菜单（圆形玻璃） ───
      this.CircleButton('dots', this.hoverRight, () => {
        AppStorage.setOrCreate('callaite_mobileMenuOpen', true);
      }, (h: boolean) => {
        this.hoverRight = h;
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 14, right: 14 })
    // 避让状态栏：沉浸式下状态栏悬浮于内容之上，标题需下移安全区高度
    .margin({ top: this.safeTop })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
