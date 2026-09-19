import { display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { LeftSidebar } from '../sidebar/LeftSidebar';
import { RightSidebar } from '../sidebar/RightSidebar';
import { ContentArea } from '../page/ContentArea';
import { Ribbon } from './Ribbon';
import { TabBar } from './TabBar';
import { StatusBar } from './StatusBar';
import { MobileHeader } from './MobileHeader';
import { MobileBottomBar } from './MobileBottomBar';
import { TabOverviewSheet } from './TabOverviewSheet';
import { MobileMenuSheet } from './MobileMenuSheet';
import { FloatingPanel } from '../common/FloatingPanel';
import { AppState } from '../../state/AppState';
import { TabState } from '../../state/TabState';
import { Breakpoints } from '../../state/Breakpoints';

const SIDEBAR_DEFAULT = 260;
const RIGHT_SIDEBAR_DEFAULT = 280;
const SIDEBAR_MIN = 180;
const SIDEBAR_MAX = 480;
const RESIZER_WIDTH = 4;

/**
 * MainContainer — Obsidian 桌面布局 + Obsidian iOS 移动布局（同一代码多设备自适应）。
 *
 * 桌面（≥600vp）— 复刻 Obsidian_Laptop.png：
 *   ┌──────┬───────────┬──────────────────────────┬───────────┐
 *   │      │ View      │ TabBar（标签页栏）        │ Right     │
 *   │Ribbon│ Switch +  ├──────────────────────────┤ Sidebar   │
 *   │      │ File Tree │        ContentArea       │ (Logseq   │
 *   │      │ (Left)    │                          │  堆叠块)  │
 *   ├──────┴───────────┴──────────────────────────┴───────────┤
 *   │                    StatusBar（统计/状态）                 │
 *   └─────────────────────────────────────────────────────────┘
 *
 * 手机（<600vp）— 复刻 Obsidian_iphone 截图：
 *   悬浮玻璃顶栏（侧栏开关/标题/更多）+ 悬浮玻璃底部胶囊栏 + 抽屉侧栏
 *   + 标签总览卡片面板 + 更多菜单面板。
 *
 * 氛围渐变底层为玻璃光感材质提供透光背景。
 */
@Component
export struct MainContainer {
  @StorageLink('callaite_leftSidebarOpen') leftSidebarOpen: boolean = true;
  @StorageLink('callaite_rightSidebarOpen') rightSidebarOpen: boolean = false;
  @StorageLink('callaite_tabOverviewOpen') tabOverviewOpen: boolean = false;
  @StorageLink('callaite_mobileMenuOpen') mobileMenuOpen: boolean = false;
  // currentPage 变化 → 同步标签页（幂等）
  @StorageLink('callaite_currentPage') @Watch('onCurrentPageChanged') currentPage: string = 'Journal';
  @State windowWidth: number = 800;
  // 系统栏安全区（由 EntryAbility 在启用沉浸式后写入，单位 vp）
  @StorageLink('callaite_safeTop') safeTop: number = 0;
  @StorageLink('callaite_safeBottom') safeBottom: number = 0;
  @State leftWidth: number = SIDEBAR_DEFAULT;
  @State rightWidth: number = RIGHT_SIDEBAR_DEFAULT;
  @State draggingLeft: boolean = false;
  @State draggingRight: boolean = false;
  private dragStartLeftWidth: number = SIDEBAR_DEFAULT;
  private dragStartRightWidth: number = RIGHT_SIDEBAR_DEFAULT;
  private displayCallback: ((displayId: number) => void) | undefined;

  private syncViewportWidth(): void {
    try {
      const displayInstance = display.getDefaultDisplaySync();
      if (displayInstance.densityPixels > 0) {
        this.windowWidth = displayInstance.width / displayInstance.densityPixels;
      }
    } catch (e) {
      console.warn('[MainContainer] Failed to get display info');
    }
  }

  /**
   * 以**组件实际宽度**作为断点依据。
   *
   * 为什么不能只用 display 宽度：2in1 / PC 上应用运行在可缩放窗口中，display 宽度
   * 是整块屏幕的宽度且不随窗口缩放变化，会导致窗口拉窄后仍停留在桌面形态
   * （断点失效）。onAreaChange 上报的是本组件占用的真实 vp 尺寸，窗口缩放、
   * 分屏、折叠屏展开、旋转都会触发，是唯一可靠的断点来源。
   */
  private applyViewportWidth(width: number): void {
    if (width > 0 && !Number.isNaN(width)) {
      const wasCompact: boolean = this.windowWidth < Breakpoints.SM_MAX;
      const nowCompact: boolean = width < Breakpoints.SM_MAX;
      this.windowWidth = width;
      // 桌面 → 紧凑：左栏语义由「常驻侧栏」变为「抽屉」。同一个状态位若不复位，
      // 窗口被拉窄时抽屉会无缘无故自动弹出（实测 2in1 收窄即出现）。
      if (!wasCompact && nowCompact) {
        AppState.setLeftSidebarOpen(false);
        AppState.setRightSidebarOpen(false);
      }
    }
  }

  /**
   * 以**实际窗口宽度**初始化断点。
   *
   * 为什么需要：onAreaChange 只在尺寸「变化」时回调，不保证在首帧布局后上报一次。
   * 冷启动时若窗口已被用户拖窄（如 2in1 上 304vp 的窄窗），仅靠 onAreaChange 会
   * 停留在 display 宽度推导出的桌面形态，导致 Ribbon + 侧栏挤爆窄窗。
   * 因此启动时主动查询一次窗口矩形。
   */
  private initViewportFromWindow(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        const rect: window.Rect = win.getWindowProperties().windowRect;
        const density: number = display.getDefaultDisplaySync().densityPixels;
        if (rect.width > 0 && density > 0) {
          this.applyViewportWidth(rect.width / density);
        }
      }).catch(() => {
        // 查询失败时保留 display 推导值
      });
    } catch (e) {
      console.warn('[MainContainer] Failed to init viewport from window');
    }
  }

  aboutToAppear(): void {
    this.syncViewportWidth();
    this.initViewportFromWindow();
    try {
      // 折叠屏展开 / 旋转 / 分辨率变化时响应式刷新布局（回调参数为 displayId）
      this.displayCallback = (displayId: number) => {
        this.syncViewportWidth();
      };
      display.on('change', this.displayCallback);
    } catch (e) {
      console.warn('[MainContainer] Failed to register display listener');
    }
    const savedLeft = AppStorage.get<number>('callaite_leftSidebarWidth');
    if (savedLeft && savedLeft >= SIDEBAR_MIN && savedLeft <= SIDEBAR_MAX) {
      this.leftWidth = savedLeft;
    }
    const savedRight = AppStorage.get<number>('callaite_rightSidebarWidth');
    if (savedRight && savedRight >= SIDEBAR_MIN && savedRight <= SIDEBAR_MAX) {
      this.rightWidth = savedRight;
    }
    // 启动时同步一次标签页（与 currentPage 对齐）
    TabState.syncToCurrentPage(AppState.getCurrentPage());
  }

  aboutToDisappear(): void {
    if (this.displayCallback !== undefined) {
      try {
        display.off('change', this.displayCallback);
      } catch (_e) {
        // 忽略注销失败
      }
    }
  }

  onCurrentPageChanged(): void {
    TabState.syncToCurrentPage(this.currentPage);
  }

  // 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
  getIsCompact(): boolean {
    return this.windowWidth < Breakpoints.SM_MAX;
  }

  build() {
    Stack() {
      // ─── 氛围渐变底层（玻璃材质的透光背景）───
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: [
            [$r('app.color.ambient_a'), 0.0],
            [$r('app.color.ambient_b'), 0.55],
            [$r('app.color.ambient_a'), 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      // ─── 主体布局 ───
      Row() {
        // ─── Ribbon（最左侧图标栏，仅桌面）───
        if (!this.getIsCompact()) {
          Ribbon()
        }

        // ─── 左侧栏（桌面内嵌 / 手机抽屉）───
        if (!this.getIsCompact() && this.leftSidebarOpen) {
          LeftSidebar()
            .width(this.leftWidth)
            .height('100%')

          this.Resizer(true)
        }

        // ─── 中列：TabBar + 内容 + StatusBar ───
        Column() {
          if (!this.getIsCompact()) {
            TabBar()
          }

          ContentArea()
            .layoutWeight(1)

          if (!this.getIsCompact()) {
            StatusBar()
          }
        }
        .layoutWeight(1)
        .height('100%')

        // ─── 右侧栏（Logseq 堆叠块，桌面内嵌）───
        if (!this.getIsCompact() && this.rightSidebarOpen) {
          this.Resizer(false)

          RightSidebar()
            .width(this.rightWidth)
            .height('100%')
        }
      }
      .width('100%')
      .height('100%')
      // 桌面壳：整体避让系统栏（沉浸式后系统栏悬浮于内容之上）。
      // 紧凑壳不在此处避让 —— 顶栏/底栏/内容区各自按安全区避让，避免重复内缩。
      .padding({
        top: this.getIsCompact() ? 0 : this.safeTop,
        bottom: this.getIsCompact() ? 0 : this.safeBottom
      })

      // ─── 移动端浮层：顶栏 + 底部胶囊栏 ───
      if (this.getIsCompact()) {
        Column() {
          MobileHeader()
          Blank()
          Row() {
            MobileBottomBar()
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: this.safeBottom + 12 })
          // 全宽容器透明命中：空白区域放行触摸，仅胶囊本体可点
          .hitTestBehavior(HitTestMode.Transparent)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ─── 移动端浮层：左右侧边悬浮面板（HarmonyOS 悬浮弹窗规范）───
      // 取代 bindSheet：bindSheet 是铺满整屏、贴底的抽屉语义，与"悬浮弹窗"不符
      if (this.getIsCompact() && this.leftSidebarOpen) {
        FloatingPanel({
          side: 'left',
          maxPanelWidth: 320,
          onClose: () => {
            AppState.setLeftSidebarOpen(false);
          }
        }) {
          LeftSidebar()
        }
      }

      if (this.getIsCompact() && this.rightSidebarOpen) {
        FloatingPanel({
          side: 'right',
          maxPanelWidth: 340,
          onClose: () => {
            AppState.setRightSidebarOpen(false);
          }
        }) {
          RightSidebar()
        }
      }

      // ─── 移动端浮层：标签页总览（Obsidian iOS 卡片式）───
      if (this.getIsCompact() && this.tabOverviewOpen) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.35)')
            .onClick(() => {
              AppStorage.setOrCreate('callaite_tabOverviewOpen', false);
            })
          TabOverviewSheet()
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction })
                .combine(TransitionEffect.translate({ y: 320 })),
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction })
                .combine(TransitionEffect.translate({ y: 320 }))
            ))
        }
        .width('100%')
        .height('100%')
      }

      // ─── 移动端浮层：更多菜单 ───
      if (this.getIsCompact() && this.mobileMenuOpen) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.35)')
            .onClick(() => {
              AppStorage.setOrCreate('callaite_mobileMenuOpen', false);
            })
          MobileMenuSheet()
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction })
                .combine(TransitionEffect.translate({ y: 360 })),
              TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction })
                .combine(TransitionEffect.translate({ y: 360 }))
            ))
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    // 断点唯一可靠来源：窗口/组件真实宽度（响应窗口缩放、分屏、折叠、旋转）
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.applyViewportWidth(newArea.width as number);
    })
  }

  /**
   * 可拖拽分隔条（桌面侧栏调宽，拖拽结束持久化）。
   */
  @Builder
  Resizer(isLeft: boolean) {
    Row() {
      Column()
        .width(2)
        .height(40)
        .borderRadius(1)
        .backgroundColor(isLeft
          ? (this.draggingLeft ? $r('app.color.primary') : $r('app.color.border'))
          : (this.draggingRight ? $r('app.color.primary') : $r('app.color.border')))
    }
    .width(RESIZER_WIDTH)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .gesture(
      PanGesture()
        .onActionStart(() => {
          if (isLeft) {
            this.draggingLeft = true;
            this.dragStartLeftWidth = this.leftWidth;
          } else {
            this.draggingRight = true;
            this.dragStartRightWidth = this.rightWidth;
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          if (isLeft) {
            const newWidth = this.dragStartLeftWidth + event.offsetX;
            if (newWidth >= SIDEBAR_MIN && newWidth <= SIDEBAR_MAX) {
              this.leftWidth = newWidth;
            }
          } else {
            const newWidth = this.dragStartRightWidth - event.offsetX;
            if (newWidth >= SIDEBAR_MIN && newWidth <= SIDEBAR_MAX) {
              this.rightWidth = newWidth;
            }
          }
        })
        .onActionEnd(() => {
          if (isLeft) {
            this.draggingLeft = false;
            AppStorage.setOrCreate('callaite_leftSidebarWidth', this.leftWidth);
          } else {
            this.draggingRight = false;
            AppStorage.setOrCreate('callaite_rightSidebarWidth', this.rightWidth);
          }
        })
    )
  }
}
