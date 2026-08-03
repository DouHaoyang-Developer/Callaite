import { BlockList } from '../outliner/BlockList';
import { JournalService } from '../../services/JournalService';
import { SettingsPage } from '../settings/SettingsPage';
import { QueryBuilder } from '../query/QueryBuilder';
import { TaskDashboard } from '../search/TaskDashboard';

@Component
export struct PageView {
  @StorageLink('callaite_currentPage') currentPage: string = 'Journal';
  @State displayName: string = '';
  @State showProperties: boolean = false;

  aboutToAppear(): void {
    if (this.currentPage === 'Journal') {
      JournalService.ensureTodayJournal();
      this.displayName = JournalService.getTodayDateString();
    } else {
      this.displayName = this.currentPage;
    }
  }

  build() {
    if (this.currentPage === 'Settings') {
      SettingsPage()
    } else if (this.currentPage === 'Graph') {
      this.QueryView()
    } else {
      Column({ space: 0 }) {
        // 页面标题（Logseq 风格: 大号粗体, 可点击编辑）
        Text(this.displayName)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text'))
          .width('100%')
          .padding({ top: 32, bottom: 4, left: 4, right: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 属性区（可折叠）
        Row({ space: 8 }) {
          Row({ space: 4 }) {
            Text('页面属性')
              .fontSize(13)
              .fontColor($r('app.color.muted_text'))
            Text(this.showProperties ? '▼' : '▶')
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
          }
          .onClick(() => { this.showProperties = !this.showProperties; })
        }
        .width('100%')
        .padding({ top: 8, bottom: 8, left: 4, right: 4 })

        if (this.showProperties) {
          Row()
            .width('100%')
            .padding(10)
            .backgroundColor($r('app.color.surface1'))
            .borderRadius(4)
        }

        // 任务面板（仅日志页）
        if (this.currentPage === 'Journal') {
          TaskDashboard({ pageName: this.displayName })
        }

        // Block 列表
        Scroll() {
          BlockList({ pageName: this.displayName })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

        Blank()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 48, right: 48 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  QueryView() {
    Column({ space: 16 }) {
      Text('图谱 / 查询').fontSize(32).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
        .width('100%').padding({ top: 24, bottom: 8 })
      Scroll() { QueryBuilder() }.width('100%').layoutWeight(1)
      Blank()
    }
    .width('100%').height('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
  }
}
