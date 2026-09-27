import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { TabState, TabInfo } from '../../state/TabState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { pageTitle } from '../../utils/PageTitle';
import { PageData } from '../../core/models/Page';

/**
 * TabBar — Obsidian 桌面端编辑器标签页栏（复刻 Obsidian_Laptop.png 顶部标签组）。
 *
 * 结构：[ 标签1 | 标签2 | ... ]    [＋ 新建] [⌄ 列表菜单]
 *  - 激活标签 = 编辑器底色（surface0），未激活 = 侧栏底色，1px 分隔
 *  - hover 显示关闭按钮；右侧菜单提供 关闭/关闭其他/新建
 *  - 数据源 TabState（AppStorage 持久化 + 版本号触发刷新）
 */
@Component
export struct TabBar {
  /** 副窗格可选的内置路由（与 pageTitle 的映射保持一致） */
  private static readonly BUILTIN_ROUTES: string[] =
    ['Journal', 'AllPages', 'Graph', 'Whiteboards', 'Flashcards', 'Pdf'];

  @StorageLink('callaite_tabsVersion') @Watch('onTabsChanged') tabsVersion: number = 0;
  @StorageLink('callaite_activeTabId') activeTabId: string = '';
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @State tabsList: TabInfo[] = [];
  @State hoveredAction: string = '';
  // ─── 分屏（对齐 Obsidian 桌面 split）───
  @StorageLink('callaite_splitEnabled') splitEnabled: boolean = false;
  @StorageLink('callaite_splitPage') splitPage: string = 'Journal';
  /** 副窗格可选页面（缓存，避免 build 期间访问服务） */
  @State pageOptions: SelectOption[] = [];
  /** 与 pageOptions 一一对应的内部路由（SelectOption.value 为 ResourceStr，单独存字符串便于比较） */
  @State pageRoutes: string[] = [];

  aboutToAppear(): void {
    this.refreshPageOptions();
    this.tabsList = TabState.getTabs();
  }

  /** 收集副窗格可选页面（内置入口 + 全部页面）；在生命周期内调用，避免 build 期间访问服务 */
  private refreshPageOptions(): void {
    const opts: SelectOption[] = [];
    const routes: string[] = [];
    for (let i = 0; i < TabBar.BUILTIN_ROUTES.length; i++) {
      const r: string = TabBar.BUILTIN_ROUTES[i];
      opts.push({ value: pageTitle(r) });
      routes.push(r);
    }
    const pages: PageData[] = WorkspaceService.getInstance().getAllPages();
    for (let i = 0; i < pages.length && i < 40; i++) {
      opts.push({ value: pages[i].originalName });
      routes.push(pages[i].originalName);
    }
    this.pageOptions = opts;
    this.pageRoutes = routes;
  }

  /** 选项下标 → 内部路由 */
  private routeOfOption(index: number): string {
    return this.pageRoutes[index] !== undefined ? this.pageRoutes[index] : 'Journal';
  }

  /** 当前副窗格路由对应的选项下标 */
  private currentSplitIndex(): number {
    for (let i = 0; i < this.pageRoutes.length; i++) {
      if (this.pageRoutes[i] === this.splitPage) {
        return i;
      }
    }
    return 0;
  }

  onTabsChanged(): void {
    this.tabsList = TabState.getTabs();
  }

  private iconFor(tab: TabInfo): string {
    if (tab.page === 'Journal' || /^\d{4}-\d{2}-\d{2}$/.test(tab.page)) {
      return 'calendar';
    }
    if (tab.page === 'Graph') {
      return 'hierarchy';
    }
    if (tab.page === 'Whiteboards') {
      return 'layout-grid';
    }
    if (tab.page === 'Flashcards') {
      return 'stack-2';
    }
    if (tab.page === 'Settings') {
      return 'settings';
    }
    return 'file';
  }

  // TabItem @Builder 已迁移为文件末尾的 TabItemView @Component（见该组件注释说明原因）


  build() {
    Row({ space: 2 }) {
      // ─── 标签列表下拉（Obsidian 桌面：位于最左）───
      Row() {
        TablerIcon('chevron-down', 18, $r('app.color.icon_color'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(40)
      .height(40)
      .borderRadius(6)
      .margin({ left: 2 })
      .stateStyles({
        normal: {
          .backgroundColor(this.hoveredAction === 'menu' ? $r('app.color.surface2') : Color.Transparent)
        },
        pressed: { .backgroundColor($r('app.color.surface3')) }
      })
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onHover((isHover: boolean) => {
        this.hoveredAction = isHover ? 'menu' : '';
      })
      .bindMenu(this.TabsMenu())

      // ─── 标签滚动区 ───
      Scroll() {
        Row({ space: 0 }) {
          // ⚠️ 不变式：ForEach 键 = 数据身份（tab.id），**不携带任何 UI 态**。
          //    原键含激活态（…_a / …_i）：每次切换标签时恰好两个条目的键同时变化，
          //    ArkUI 按「删除 + 插入」处理 → 新旧页签在同一渲染槽位短暂共存且位置重叠；
          //    低帧率（模拟器 ~20-30fps）下 140ms 过渡横跨 3-5 帧，叠影肉眼可见。
          //    样式刷新改由 TabItemView 的 @StorageLink('callaite_activeTabId') 承担。
          ForEach(this.tabsList, (tab: TabInfo) => {
            TabItemView({ tab: tab, icon: this.iconFor(tab) })
          }, (tab: TabInfo) => tab.id)
        }
      }
      .layoutWeight(1)
      .height('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)

      // ─── 右侧操作区 ───
      // 分屏（Obsidian 桌面 split）：开关 + 副窗格页面选择
      Row() {
        TablerIcon('square-toggle-horizontal', 16, this.splitEnabled
          ? $r('app.color.primary')
          : $r('app.color.icon_color'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(40)
      .height(40)
      .borderRadius(6)
      .stateStyles({
        normal: {
          .backgroundColor(this.splitEnabled
            ? $r('app.color.accent_soft')
            : (this.hoveredAction === 'split' ? $r('app.color.surface2') : Color.Transparent))
        },
        pressed: { .backgroundColor($r('app.color.surface3')) }
      })
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onHover((isHover: boolean) => {
        this.hoveredAction = isHover ? 'split' : '';
      })
      .onClick(() => {
        this.splitEnabled = !this.splitEnabled;
      })

      if (this.splitEnabled) {
        Select(this.pageOptions)
          .selected(this.currentSplitIndex())
          .value(this.currentSplitIndex() < this.pageOptions.length
            ? this.pageOptions[this.currentSplitIndex()].value
            : '')
          .font({ size: 12 })
          .height(30)
          .constraintSize({ maxWidth: 150 })
          .onSelect((index: number) => {
            this.splitPage = this.routeOfOption(index);
          })
      }

      Divider()
        .vertical(true)
        .height(16)
        .color($r('app.color.border'))

      Row() {
        TablerIcon('plus', 18, $r('app.color.icon_color'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      // 热区 40vp：满足官方 7.1.1.3.3（原 30vp 不达标）
      .width(40)
      .height(40)
      .borderRadius(6)
      .margin({ left: 4 })
      .stateStyles({
        normal: {
          .backgroundColor(this.hoveredAction === 'new' ? $r('app.color.surface2') : Color.Transparent)
        },
        pressed: { .backgroundColor($r('app.color.surface3')) }
      })
      .animation({ duration: 140, curve: Curve.EaseOut })
      .onHover((isHover: boolean) => {
        this.hoveredAction = isHover ? 'new' : '';
      })
      .onClick(() => {
        TabState.newTab('Journal');
      })

    }
    .width('100%')
    // 标签栏容器高度 40vp：与页签 40vp 等高（页签才完整贴合栏底、不溢出栏外），
    // 同时满足官方 40vp 点击热区下限。
    // 这里是该高度的唯一定义处 —— MainContainer 的 TabBar() 调用点（约 L275）未加任何尺寸修饰符。
    .height(40)
    .padding({ left: 4, right: 0 })
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })
  }

  /**
   * 标签列表菜单（静态 Builder，避免参数化 CustomBuilder 兼容性问题）。
   */
  @Builder
  TabsMenu() {
    Menu() {
      MenuItemGroup() {
        MenuItem({ content: t('tab_new') })
          .onClick(() => {
            TabState.newTab('Journal');
          })
      }
      MenuItemGroup() {
        MenuItem({ content: t('tab_close') })
          .onClick(() => {
            if (this.activeTabId !== '') {
              TabState.closeTab(this.activeTabId);
            }
          })
        MenuItem({ content: t('tab_close_others') })
          .onClick(() => {
            if (this.activeTabId !== '') {
              TabState.closeOthers(this.activeTabId);
            }
          })
      }
    }
  }
}

/**
 * TabItemView — 单个标签页（子组件化，2026-09-26 修复标签页重叠）
 *
 * **为什么必须是 @Component，而不是父组件的 @Builder**：
 *   ArkUI 的 @Builder **不响应状态变化重渲染** —— `activeTabId` 改变后 Builder 内的样式三元
 *   不会刷新。历史实现因此把激活态编进 ForEach 键（`tab.id + '_' + (active?'a':'i')`）来
 *   「借用键变化强制重建」强刷样式。副作用：每次切换标签恰好两个条目的键同时变化 →
 *   ArkUI 按「删除 + 插入」处理 → 旧组件进入销毁周期、新组件同帧挂载，两者在同一渲染槽位
 *   短暂共存；旧组件上 140ms 的 stateStyles/animation 在拆除窗口内继续出帧，低帧率设备
 *   （模拟器 ~20-30fps，过渡横跨 3-5 帧）表现为肉眼可见的**标签页叠影**。
 *
 * **本组件的解法**：激活态用 `@StorageLink('callaite_activeTabId')` 自刷新、hover 态用
 *   `@State` 自持，父组件 ForEach 键回归稳定身份 `tab.id`，组件树只做「复用 + 更新」。
 *
 * **不变式（防回归）**：ForEach 键 = 数据身份，**不携带任何 UI 态**。
 *   任何「想让 ForEach 条目刷新样式」的需求，一律用子组件 + @StorageLink/@Prop/@Watch 实现。
 */
@Component
struct TabItemView {
  /** 标签数据（身份：id）。icon 由父组件按 page 推导后传入，避免重复实现图标映射 */
  @Prop tab: TabInfo = { id: '', page: '', pinned: false };
  @Prop icon: string = 'file';
  /** 激活态：组件自持并随 AppStorage 刷新，父组件无需参与 */
  @StorageLink('callaite_activeTabId') activeTabId: string = '';
  /** hover 态组件内自持：组件复用后 hover 不丢失、切换标签后不残留 */
  @State hovered: boolean = false;
  @State hoveredClose: boolean = false;

  private isActive(): boolean {
    return this.tab.id === this.activeTabId;
  }

  build() {
    Row({ space: 6 }) {
      TablerIcon(this.icon, 14,
        this.isActive() ? $r('app.color.primary') : $r('app.color.muted_text'))

      Text(TabState.tabTitle(this.tab.page))
        .fontSize(13)
        .fontColor(this.isActive() ? $r('app.color.text') : $r('app.color.muted_text'))
        .fontWeight(this.isActive() ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 文本上限 156vp = 页签上限 220 − 固定开销 64（内边距 16 + 图标 14 + 间距 6+6 + 关闭按钮 22）
        // minWidth: 0 必填 —— 否则 Row 收缩时文本节点宽度协商不收敛，长标题偶发不出现省略号
        .constraintSize({ maxWidth: 156, minWidth: 0 })

      // 关闭按钮：激活或 hover 时显示（视觉 22vp，命中区经 responseRegion 扩到 40vp）
      if (this.isActive() || this.hovered) {
        Row() {
          TablerIcon('x', 12, this.hoveredClose
            ? $r('app.color.danger')
            : $r('app.color.muted_text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(22)
        .height(22)
        .responseRegion({ x: -9, y: -9, width: 40, height: 40 })
        .borderRadius(4)
        .backgroundColor(this.hoveredClose ? $r('app.color.surface2') : Color.Transparent)
        .animation({ duration: 120, curve: Curve.EaseOut })
        .onHover((isHover: boolean) => {
          this.hoveredClose = isHover;
        })
        .onClick(() => {
          TabState.closeTab(this.tab.id);
        })
      } else {
        Row().width(22).height(22)
      }
    }
    // 页签整体高度 40vp：满足官方点击热区下限（原 30vp 不达标）
    .height(40)
    // 宽度随标题自适应：minWidth 88vp（固定开销 64 + 24vp 文本）、maxWidth 220vp（超出交给省略号）
    .constraintSize({ minWidth: 88, maxWidth: 220 })
    .padding({ left: 12, right: 4 })
    .borderRadius(6)
    .margin({ left: 2, right: 2 })
    .stateStyles({
      normal: {
        .backgroundColor(this.isActive()
          ? $r('app.color.surface0')
          : (this.hovered ? $r('app.color.surface2') : Color.Transparent))
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .border({ width: 0.5, color: this.isActive() ? $r('app.color.border') : Color.Transparent })
    .shadow(this.isActive() ? { radius: 4, color: 'rgba(0,0,0,0.06)', offsetY: 1 } :
      { radius: 0, color: Color.Transparent })
    .onClick(() => {
      TabState.activateTab(this.tab.id);
    })
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
  }
}