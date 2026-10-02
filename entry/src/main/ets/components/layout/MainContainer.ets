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
import { MarkdownToolbar } from '../mobile/MarkdownToolbar';
import { NewFileDialog } from '../common/NewFileDialog';
import { VaultSwitcherDialog } from '../common/VaultSwitcherDialog';
import { TabOverviewSheet } from './TabOverviewSheet';
import { MobileMenuSheet } from './MobileMenuSheet';
import { FloatingPanel } from '../common/FloatingPanel';
import { SplitDivider } from './SplitDivider';
import { FindInPage } from '../outliner/FindInPage';
import { MaterialRole } from '../../theme/MaterialTokens';
import { AppState } from '../../state/AppState';
import { TabState } from '../../state/TabState';
import { Breakpoints } from '../../state/Breakpoints';
import { WorkspaceService } from '../../services/WorkspaceService';
import { OverlayKeyRouter } from '../../utils/OverlayKeyRouter';

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
  // ─── 内容区左右分屏（对齐 Obsidian 桌面分屏）───
  @StorageLink('callaite_splitEnabled') splitEnabled: boolean = false;
  @StorageLink('callaite_splitRatio') splitRatio: number = 0.5;
  @StorageLink('callaite_splitPage') splitPage: string = 'Journal';
  /**
   * 当前获焦 block（由 EditorService 写入）。
   * 非空时说明正在编辑，此时在底部栏之上显示 Markdown 工具行
   * （对齐 Obsidian iOS 键盘上方工具行）。
   */
  @StorageLink('callaite_focusedBlock') focusedBlock: string = '';
  /**
   * S3-W3（U2.4 第 2 件后半）：页内搜索条开合态。
   *
   * 键仍是 `callaite_findInPageOpen`（W12 的「显隐统一」契约**未变**：唯一写入口是
   * `AppState.open/closeFindInPage`）。变的只是**谁读它来决定挂载** ——
   * W12/W13 是 `BlockList`（内联在列表上方），S3-W3 起是本组件（顶层 Stack 右上角浮动小卡，
   * 计划 `PLAN-UI-Alignment.md (v1.md:321`）。
   */
  @StorageLink('callaite_findInPageOpen') findInPageOpen: boolean = false;
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

  /**
   * 页内搜索条的搜索目标页 uuid（S3-W3）。
   *
   * 为什么必须有这个方法：`FindInPage` 靠 `pageId` 递归取块（`ws.getPageBlocks(pageId)`），
   * 传空串 ⇒ **恒 0 匹配**（W13 踩过：当时传的是 `BlockList.pageId`，而 `PageView.ets:254`
   * 从没传过它 ⇒ `@Prop` 恒为 `''`）。迁到本组件后，本组件手里只有**页名**
   * （`callaite_currentPage`），所以要按页名反查 uuid。
   *
   * 页名口径与 `ContentArea.resolvePageName` **同源**：`Journal` 是「今天」的别名，
   * 不是真实页名 —— 不换算就会在日记页上搜不到任何东西。
   * 查不到页（如首页/空仓库）时返回空串，`FindInPage` 的表现是「0/0」，不是崩溃。
   */
  private findInPagePageId(): string {
    const page = WorkspaceService.getInstance().getPageByName(ContentArea.resolvePageName(this.currentPage));
    return page ? page.uuid : '';
  }

  // 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
  getIsCompact(): boolean {
    return this.windowWidth < Breakpoints.SM_MAX;
  }

  /**
   * 内容区分屏区域可用宽度（vp）—— 用于把分隔条拖拽的像素位移换算为比例。
   * 扣除 Ribbon、左右侧栏后为真实可分配宽度。
   */
  private splitAreaWidth(): number {
    let w = this.windowWidth;
    if (!this.getIsCompact()) {
      w -= 46;                                                  // Ribbon
      if (this.leftSidebarOpen) {
        w -= this.leftWidth;
      }
      if (this.rightSidebarOpen) {
        w -= this.rightWidth;
      }
    }
    return w > 100 ? w : 100;
  }

  /** 左窗格权重（layoutWeight 需为数值，放大 1000 倍保留精度） */
  private splitLeftWeight(): number {
    return Math.round(this.splitRatio * 1000);
  }

  /** 右窗格权重 */
  private splitRightWeight(): number {
    return Math.round((1 - this.splitRatio) * 1000);
  }

  /**
   * 内容区分屏容器 —— 单窗格 / 双窗格（主 + 副 + 可拖拽分隔条）。
   */
  @Builder
  ContentPanes() {
    if (!this.getIsCompact() && this.splitEnabled) {
      Row() {
        ContentArea()
          .layoutWeight(this.splitLeftWeight())
        SplitDivider({
          ratio: this.splitRatio,
          totalWidth: this.splitAreaWidth(),
          onRatioChange: (r: number) => {
            this.splitRatio = r;
          }
        })
        ContentArea({ pageOverride: this.splitPage, paneId: 'secondary' })
          .layoutWeight(this.splitRightWeight())
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Top)
    } else {
      ContentArea()
        .layoutWeight(1)
    }
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
        // ⚠️ 沉浸光感阶段二说明：曾尝试用 Navigation 包裹此列、把 TabBar 挂到
        // .title() 标题栏以启用 systemMaterial，实测 Navigation 会按自己的
        // 布局模型重排子节点（标题栏与内容区并排），导致桌面壳布局回归。
        // 该迁移需要按 Navigation 的布局模型重新设计（titleBar 高度/模式/分屏
        // 兼容），本阶段保持原有自研外壳 + Token 化玻璃方案。
        Column() {
          if (!this.getIsCompact()) {
            TabBar()
          }

          this.ContentPanes()

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

      // ─── U2.4 第 2 件后半（S3-W3）：页内搜索条 = ContentArea 之上的右上角浮动小卡 ───
      // 计划 §U2.4 第 2 条原文：「渲染位置：从 BlockList 内联移到 MainContainer 顶部 Stack
      // （ContentArea 之上，右上角浮动小卡，Obsidian 布局位）」。
      //
      // 为什么放在这一层（Stack 的**绘制顺序即层级**，这里插在主体布局之后、各模态浮层之前）：
      //   · 在主体 `Row()` 之后 ⇒ 画在内容之上（迁移前它挤在 `BlockList` 的 Column 里，
      //     占纵向空间 ⇒ 打开即把整条 List 往下推，那正是迁移前 `Ctrl+Shift+F`
      //     像素差分覆盖整条内容列的原因）；
      //   · 在 `NewFileDialog`/`VaultSwitcherDialog` 等**模态**之前 ⇒ 模态打开时盖住它
      //     （与 `OverlayKeyRouter` 的优先级表一致：findInPage=100，是最底层浮层）；
      //   · **唯一挂载点**：`BlockList` 的两处内联挂载已删除 ⇒ 不可能出现两个实例
      //     各自注册按键路由器（那会让「一次按压走两步」）。
      //
      // `pageId` 必须由本组件解析成**真实页 uuid**（见 findInPagePageId），
      // 理由与 W13 修的 `pageId` 恒为 `''` 是同一个坑。
      if (this.findInPageOpen) {
        // ─── 定位方式：**用嵌套 Stack 的 `alignContent`**，不要用子节点的 `.align()` ✗ ───
        // 实测（本窗口，2026-10-02，两次构建两次装机）：在**本根 Stack**（没有显式
        // `alignContent`，默认 `Alignment.Center`）下，
        //   · 套一层 `Column` 再 `.align(Alignment.TopEnd)` ⇒ 卡片落在**正中** ✗；
        //   · 直接挂在 `FindInPage(...)` 上 `.align(Alignment.TopEnd)` ⇒ **仍然在正中** ✗。
        // 两次的像素证据同一：卡片中心 ≈ 窗口 `[515,281,2090,1394]` 的中心 `(1560,978)`。
        // ⇒ 在本根 Stack 上，子节点的 `.align()` 没有改变落点（`SlashMenu` 那条同型写法
        //   之所以生效，是因为它的宿主 `BlockList` 是 `Stack({ alignContent: Alignment.Bottom })`
        //   —— 即**真正起作用的是宿主 Stack 的 `alignContent`**）。
        // 因此这里显式给一个只服务定位的嵌套 `Stack({ alignContent: Alignment.TopEnd })`：
        //   · `HitTestMode.None` = 该层**自身不参与触摸测试**（子节点与兄弟节点照常参与）
        //     ⇒ 卡片可点、卡片以外的区域仍然点到下面的正文，不多一个"挡板"；
        //   · 与文件顶部氛围渐变层用的是同一个模式（`HitTestMode.None`）。
        Stack({ alignContent: Alignment.TopEnd }) {
          FindInPage({ pageId: this.findInPagePageId() })
            .margin({
              top: this.getIsCompact() ? this.safeTop + 64 : 12,
              right: this.getIsCompact() ? 12 : 16
            })
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }

      // ─── 移动端浮层：顶栏 + 底部胶囊栏 ───
      if (this.getIsCompact()) {
        Column() {
          MobileHeader()
          Blank()

          // ─── 键盘上方 Markdown 工具行（仅编辑态出现）───
          if (this.focusedBlock !== '') {
            Row() {
              MarkdownToolbar()
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 8 })
            .hitTestBehavior(HitTestMode.Transparent)
          }

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
      // ─── 全局浮层：新建文件三选项对话框 ───
      NewFileDialog()

      // ─── 全局浮层：仓库切换器（深色模态）───
      VaultSwitcherDialog()

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
    // ─── S3-W3：浮层按键的**最外层宿主兜底**（W13-5 的根因修复面）───
    // W13 登记：「点过上/下按钮后 Esc 不关页内搜索条」✗。根因不是路由器（ESC 在 `isNavKey` 里），
    // 而是**焦点离开了 FindInPage 子树**（按钮点完后焦点不再落在搜索输入框上）⇒
    // 键根本没经过 FindInPage 根 Row 那个兜底落点。
    //
    // 为什么兜底必须放在**这一层**：本 Stack 是整页的根容器。
    // 「焦点不在任何叶子节点上」时，ArkUI 把按键投给根容器 —— 只有挂在根上的处理器能收到。
    // `ContentArea` 的那一份（`ContentArea.ets:243`）覆盖不到这种态：FindInPage 迁到本层后
    // **已不是 ContentArea 的后代**，焦点漂到根上时事件不会经过 ContentArea。
    //
    // 零副作用的两条保证（逐条与既有实现对齐）：
    //   · `handleFromHost()` 在**没有任何浮层打开**时恒返回 false（`topOverlayId() === ''`）
    //     ⇒ 不 `stopPropagation`、不吞任何键，与接线前逐字节相同；
    //   · 与 `ContentArea`/浮层自身的落点共用 `OverlayKeyRouter` 那一份去重标记
    //     ⇒ 一次按压只走一步，不会双触发。
    // ⚠️ 刻意**不**在此处转投 `ShortcutService`：`ContentArea.onKeyEvent` 已经无条件转过一次
    //    且不 `stopPropagation`，这里再转一次会让 Ctrl+Z／Ctrl+K 这类动作**执行两次**。
    .onKeyEvent((event: KeyEvent) => {
      if (OverlayKeyRouter.getInstance().handleFromHost(event)) {
        event.stopPropagation();
      }
    })
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
