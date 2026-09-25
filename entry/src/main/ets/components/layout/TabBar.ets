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
  @State hoveredTabId: string = '';
  @State hoveredAction: string = '';
  @State hoveredCloseId: string = '';
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

  @Builder
  TabItem(tab: TabInfo) {
    Row({ space: 6 }) {
      TablerIcon(this.iconFor(tab), 14,
        tab.id === this.activeTabId ? $r('app.color.primary') : $r('app.color.muted_text'))

      Text(TabState.tabTitle(tab.page))
        .fontSize(13)
        .fontColor(tab.id === this.activeTabId ? $r('app.color.text') : $r('app.color.muted_text'))
        .fontWeight(tab.id === this.activeTabId ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 文本上限 156vp = 页签上限 220 − 固定开销 64（内边距 16 + 图标 14 + 间距 6+6 + 关闭按钮 22）
        .constraintSize({ maxWidth: 156 })

      // 关闭按钮：激活或 hover 时显示（命中区 22vp，避免 18vp 过小难点）
      if (tab.id === this.activeTabId || this.hoveredTabId === tab.id) {
        Row() {
          TablerIcon('x', 12, this.hoveredCloseId === tab.id
            ? $r('app.color.danger')
            : $r('app.color.muted_text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(22)
        .height(22)
        // 视觉保持 22vp 以免撑开页签，命中区用 responseRegion 扩展到 40vp
        .responseRegion({ x: -9, y: -9, width: 40, height: 40 })
        .borderRadius(4)
        .backgroundColor(this.hoveredCloseId === tab.id ? $r('app.color.surface2') : Color.Transparent)
        .animation({ duration: 120, curve: Curve.EaseOut })
        .onHover((isHover: boolean) => {
          this.hoveredCloseId = isHover ? tab.id : '';
        })
        .onClick(() => {
          TabState.closeTab(tab.id);
        })
      } else {
        Row().width(22).height(22)
      }
    }
    // 页签整体高度 40vp：满足官方点击热区下限（原 30vp 不达标），
    // 页签填满标签栏高度也是编辑器标签栏的常规形态
    .height(40)
    // 宽度随标题自适应（Obsidian 形态）：不使用固定等宽，仅设上下限
    //   minWidth 88vp = 固定开销 64vp（内边距 16 + 图标 14 + 间距 6+6 + 关闭按钮 22）+ 24vp 文本
    //   maxWidth 220vp：长标题不挤占整条标签栏，超出交给 Text 省略号截断
    .constraintSize({ minWidth: 88, maxWidth: 220 })
    .padding({ left: 12, right: 4 })
    .borderRadius(6)
    .margin({ left: 2, right: 2 })
    .stateStyles({
      normal: {
        .backgroundColor(tab.id === this.activeTabId
          ? $r('app.color.surface0')
          : (this.hoveredTabId === tab.id ? $r('app.color.surface2') : Color.Transparent))
      },
      pressed: { .backgroundColor($r('app.color.surface3')) }
    })
    .animation({ duration: 140, curve: Curve.EaseOut })
    .border({ width: 0.5, color: tab.id === this.activeTabId ? $r('app.color.border') : Color.Transparent })
    .shadow(tab.id === this.activeTabId ? { radius: 4, color: 'rgba(0,0,0,0.06)', offsetY: 1 } :
      { radius: 0, color: Color.Transparent })
    .onClick(() => {
      TabState.activateTab(tab.id);
    })
    .onHover((isHover: boolean) => {
      this.hoveredTabId = isHover ? tab.id : '';
    })
  }

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
          ForEach(this.tabsList, (tab: TabInfo) => {
            this.TabItem(tab)
          }, (tab: TabInfo) => tab.id + '_' + (tab.id === this.activeTabId ? 'a' : 'i'))
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
