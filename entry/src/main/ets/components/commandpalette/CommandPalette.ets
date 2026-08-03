import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { AppState } from '../../state/AppState';

@Component
export struct CommandPalette {
  @State queryText: string = '';
  @State results: PageData[] = [];

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    this.results = ws.getAllPages();
  }

  build() {
    Column() {
      // 搜索输入框
      Row({ space: 8 }) {
        TablerIcon('search', 18, $r('app.color.muted_text'))
        TextInput({ placeholder: t('placeholder_search'), text: this.queryText })
          .fontSize(16)
          .layoutWeight(1)
          .height(48)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .onChange((value: string) => {
            this.queryText = value;
            this.doSearch(value);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      // 搜索结果
      Scroll() {
        Column({ space: 2 }) {
          if (this.results.length === 0) {
            Row({ space: 8 }) {
              Text('创建页面: ' + this.queryText)
                .fontSize(15)
                .fontColor($r('app.color.primary'))
            }
            .width('100%')
            .height(44)
            .padding({ left: 16, right: 16 })
            .borderRadius(6)
            .onClick(() => {
              AppState.setCurrentPage(this.queryText);
              AppState.setSearchPanelOpen(false);
            })
          } else {
            ForEach(this.results.slice(0, 15), (page: PageData) => {
              Row({ space: 12 }) {
                if (page.journalDay !== '') {
                  TablerIcon('calendar', 18, $r('app.color.muted_text'))
                } else {
                  TablerIcon('file', 18, $r('app.color.muted_text'))
                }

                Column({ space: 2 }) {
                  Text(page.originalName)
                    .fontSize(15)
                    .fontColor($r('app.color.text'))
                  if (page.tags.length > 0) {
                    Text(page.tags.join(', '))
                      .fontSize(12)
                      .fontColor($r('app.color.muted_text'))
                      .maxLines(1)
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .height(48)
              .padding({ left: 16, right: 16 })
              .borderRadius(6)
              .onClick(() => {
                AppState.setCurrentPage(page.originalName);
                AppState.setSearchPanelOpen(false);
              })
            }, (page: PageData) => page.uuid)
          }
        }
        .width('100%')
        .padding({ top: 8, left: 8, right: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }

  doSearch(query: string): void {
    const ws = WorkspaceService.getInstance();
    if (query === '') {
      this.results = ws.getAllPages();
    } else {
      this.results = ws.searchPages(query);
    }
  }
}
