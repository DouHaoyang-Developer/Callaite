import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { TabState, TabInfo } from '../../state/TabState';

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
  @StorageLink('callaite_tabsVersion') @Watch('onTabsChanged') tabsVersion: number = 0;
  @StorageLink('callaite_activeTabId') activeTabId: string = '';
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @State tabsList: TabInfo[] = [];
  @State hoveredTabId: string = '';
  @State hoveredAction: string = '';
  @State hoveredCloseId: string = '';

  aboutToAppear(): void {
    this.tabsList = TabState.getTabs();
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
        .constraintSize({ maxWidth: 150 })

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

      Row() {
        TablerIcon('chevron-down', 18, $r('app.color.icon_color'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .width(40)
      .height(40)
      .borderRadius(6)
      .margin({ right: 6 })
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
    }
    .width('100%')
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
