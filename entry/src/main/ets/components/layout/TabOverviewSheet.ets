import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { TabState, TabInfo } from '../../state/TabState';

/**
 * TabOverviewSheet — Obsidian iOS 标签页总览（Obsidian_iphone (4).jpg 复刻）：
 * 卡片式标签预览网格 + 底部操作条 [＋] [N 个标签页] [完成]。
 * 由 MainContainer 以全屏浮层方式呈现（半透明遮罩 + 底部滑入面板）。
 */
@Component
export struct TabOverviewSheet {
  @StorageLink('callaite_tabsVersion') @Watch('onTabsChanged') tabsVersion: number = 0;
  @StorageLink('callaite_activeTabId') activeTabId: string = '';
  @State tabsList: TabInfo[] = [];

  aboutToAppear(): void {
    this.tabsList = TabState.getTabs();
  }

  onTabsChanged(): void {
    this.tabsList = TabState.getTabs();
  }

  private close(): void {
    AppStorage.setOrCreate('callaite_tabOverviewOpen', false);
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
    return 'file';
  }

  build() {
    Column() {
      // ─── 标签卡片网格 ───
      Scroll() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.tabsList, (tab: TabInfo) => {
            Column({ space: 6 }) {
              Stack({ alignContent: Alignment.TopEnd }) {
                Column() {
                  TablerIcon(this.iconFor(tab), 40,
                    tab.id === this.activeTabId ? $r('app.color.primary') : $r('app.color.muted_text'))
                }
                .alignItems(HorizontalAlign.Center)
                .width('100%')
                .height(160)
                .justifyContent(FlexAlign.Center)
                .backgroundColor($r('app.color.surface0'))
                .borderRadius(16)
                .border({ width: tab.id === this.activeTabId ? 2 : 0.5,
                  color: tab.id === this.activeTabId ? $r('app.color.primary') : $r('app.color.border') })
                .shadow({ radius: 10, color: 'rgba(0,0,0,0.08)', offsetY: 3 })
                .onClick(() => {
                  TabState.activateTab(tab.id);
                  this.close();
                })

                Row() {
                  TablerIcon('x', 16, $r('app.color.text'))
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .width(28)
                .height(28)
                .borderRadius(8)
                .margin(8)
                .onClick(() => {
                  TabState.closeTab(tab.id);
                })
              }
              .width('100%')

              Text(TabState.tabTitle(tab.page))
                .fontSize(13)
                .fontColor($r('app.color.text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('46%')
            .margin({ left: '2%', right: '2%', bottom: 12 })
          }, (tab: TabInfo) => tab.id + '_' + (tab.id === this.activeTabId ? 'a' : 'i'))
        }
        .width('100%')
        .padding({ top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)

      // ─── 底部操作条 ───
      Row() {
        Row() {
          TablerIcon('plus', 24, $r('app.color.text'))
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .width(48)
        .height(44)
        .onClick(() => {
          TabState.newTab('Journal');
        })

        Blank()

        Row({ space: 4 }) {
          Text(this.tabsList.length.toString() + ' ' + t('tabs_count'))
            .fontSize(16)
            .fontColor($r('app.color.text'))
          TablerIcon('chevron-down', 14, $r('app.color.muted_text'))
        }

        Blank()

        Row() {
          Text(t('done'))
            .fontSize(16)
            .fontColor($r('app.color.text'))
        }
        .width(48)
        .height(44)
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.End)
        .onClick(() => {
          this.close();
        })
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('72%')
    .padding({ left: 8, right: 8, top: 12, bottom: 20 })
    .backgroundColor($r('app.color.surface1'))
    .borderRadius({ topLeft: 24, topRight: 24 })
    .border({ width: { top: 0.5 }, color: $r('app.color.glass_border') })
  }
}
