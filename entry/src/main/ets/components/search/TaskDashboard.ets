import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { JournalService } from '../../services/JournalService';
import { BlockData } from '../../core/models/Block';
import { AppState } from '../../state/AppState';
import { QueryEngine, QueryOptions } from '../../core/db/QueryEngine';

/**
 * TaskDashboard — 任务管理面板。
 * 使用 QueryEngine 查询计划/截止任务。
 */
@Component
export struct TaskDashboard {
  @Prop pageName: string = '';
  @State scheduledTasks: BlockData[] = [];
  @State deadlineTasks: BlockData[] = [];

  aboutToAppear(): void {
    this.refreshTasks();
  }

  refreshTasks(): void {
    const ws = WorkspaceService.getInstance();
    const store = ws.getDataStore();
    const today = JournalService.getTodayDateString();
    const nextWeek = JournalService.getDateAfter(7);

    // 使用 QueryEngine 查询计划任务
    const schedOpts: QueryOptions = {
      markers: ['TODO', 'DOING', 'LATER', 'NOW'],
      scheduledAfter: today,
      scheduledBefore: nextWeek,
      limit: 10
    };
    this.scheduledTasks = QueryEngine.query(store, schedOpts);

    // 查询截止任务
    const deadOpts: QueryOptions = {
      deadlineAfter: today,
      deadlineBefore: nextWeek,
      limit: 10
    };
    this.deadlineTasks = QueryEngine.query(store, deadOpts);
  }

  build() {
    if (this.scheduledTasks.length === 0 && this.deadlineTasks.length === 0) {
      Column().width(0).height(0)
    } else {
      Column({ space: 12 }) {
        if (this.scheduledTasks.length > 0) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              TablerIcon('calendar', 14, $r('app.color.primary'))
              Text('计划任务 (' + this.scheduledTasks.length + ')')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')

            ForEach(this.scheduledTasks.slice(0, 5), (block: BlockData) => {
              Row({ space: 6 }) {
                Text(block.scheduled)
                  .fontSize(11)
                  .fontColor($r('app.color.muted_text'))
                if (block.marker !== '') {
                  Text(block.marker)
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(block.marker === 'DONE' ? $r('app.color.success') : $r('app.color.primary'))
                    .padding({ left: 2, right: 2, top: 0, bottom: 0 })
                    .borderRadius(2)
                    .backgroundColor(block.marker === 'DONE' ? '#10B98120' : '#0078D420')
                }
                Text(block.content)
                  .fontSize(13)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .height(28)
              .padding({ left: 6, right: 6 })
              .borderRadius(4)
              .onClick(() => {
                AppState.setCurrentPage(this.findPageName(block));
              })
            }, (block: BlockData) => block.uuid)
          }
          .width('100%')
        }

        if (this.deadlineTasks.length > 0) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              TablerIcon('alert-triangle', 14, $r('app.color.danger'))
              Text('截止提醒 (' + this.deadlineTasks.length + ')')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')

            ForEach(this.deadlineTasks.slice(0, 5), (block: BlockData) => {
              Row({ space: 6 }) {
                Text(block.deadline)
                  .fontSize(11)
                  .fontColor($r('app.color.danger'))
                Text(block.content)
                  .fontSize(13)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .height(28)
              .padding({ left: 6, right: 6 })
              .borderRadius(4)
              .onClick(() => {
                AppState.setCurrentPage(this.findPageName(block));
              })
            }, (block: BlockData) => block.uuid)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(10)
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(8)
    }
  }

  findPageName(block: BlockData): string {
    const ws = WorkspaceService.getInstance();
    const pageId = ws.getPageUuidForBlock(block.uuid);
    if (pageId) {
      const page = ws.getDataStore().getIndexStore().getPage(pageId);
      if (page) {
        return page.originalName;
      }
    }
    return 'Journal';
  }
}
