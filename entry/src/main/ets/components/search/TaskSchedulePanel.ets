import { TablerIcon } from '../common/Icons';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { JournalService } from '../../services/JournalService';
import { AppState } from '../../state/AppState';

/**
 * TaskSchedulePanel — 日志页顶部 SCHEDULED/DEADLINE 任务聚合面板。
 *
 * 对应 Logseq journal 日志页顶部的计划/截止任务摘要。
 *
 * 职责：
 *  - 遍历当前页所有 Block（含子 Block），收集有 scheduled/deadline 日期的任务
 *  - 按日期升序排序展示
 *  - 过期任务用 danger 色标记，今日任务用 warning 色标记
 *  - 可折叠面板（默认展开）
 *  - 点击任务跳转到对应页面
 */

// 任务条目数据结构
interface TaskItem {
  blockUuid: string;
  content: string;
  marker: string;
  scheduled: string;
  deadline: string;
  pageName: string;
}

@Component
export struct TaskSchedulePanel {
  @Prop @Watch('onPageIdChange') pageId: string;
  @State scheduledTasks: TaskItem[] = [];
  @State deadlineTasks: TaskItem[] = [];
  @State isExpanded: boolean = true;
  private today: string = '';

  aboutToAppear(): void {
    this.today = JournalService.getTodayDateString();
    this.loadTasks();
  }

  /**
   * pageId 变化时重新加载任务。
   */
  onPageIdChange(): void {
    this.today = JournalService.getTodayDateString();
    this.loadTasks();
  }

  /**
   * 加载当前页所有带 scheduled/deadline 的任务 Block。
   * 递归遍历子 Block 以收集所有层级的任务。
   */
  private loadTasks(): void {
    const ws = WorkspaceService.getInstance();
    const blocks = ws.getPageBlocks(this.pageId);

    const schedList: TaskItem[] = [];
    const deadList: TaskItem[] = [];

    // 收集顶层 + 子层级 Block
    const allBlocks: BlockData[] = [];
    this.collectAllBlocks(blocks, allBlocks);

    for (let i = 0; i < allBlocks.length; i++) {
      const block = allBlocks[i];
      const isTask = block.marker.length > 0;
      if (!isTask) {
        continue;
      }
      const pageName = this.findPageName(block.pageId);

      if (block.scheduled.length > 0) {
        const item: TaskItem = {
          blockUuid: block.uuid,
          content: block.content,
          marker: block.marker,
          scheduled: block.scheduled,
          deadline: '',
          pageName: pageName
        };
        schedList.push(item);
      }

      if (block.deadline.length > 0) {
        const item: TaskItem = {
          blockUuid: block.uuid,
          content: block.content,
          marker: block.marker,
          scheduled: '',
          deadline: block.deadline,
          pageName: pageName
        };
        deadList.push(item);
      }
    }

    // 按日期升序排序
    schedList.sort((a: TaskItem, b: TaskItem) => {
      return a.scheduled.localeCompare(b.scheduled);
    });
    deadList.sort((a: TaskItem, b: TaskItem) => {
      return a.deadline.localeCompare(b.deadline);
    });

    this.scheduledTasks = schedList;
    this.deadlineTasks = deadList;
  }

  /**
   * 递归收集所有层级的 Block（含子 Block）。
   */
  private collectAllBlocks(blocks: BlockData[], accumulator: BlockData[]): void {
    const ws = WorkspaceService.getInstance();
    for (let i = 0; i < blocks.length; i++) {
      accumulator.push(blocks[i]);
      const children = ws.getChildrenOfBlock(blocks[i].uuid);
      if (children.length > 0) {
        this.collectAllBlocks(children, accumulator);
      }
    }
  }

  /**
   * 通过 pageId 查找页面名。
   */
  private findPageName(pageId: string): string {
    const pages = WorkspaceService.getInstance().getAllPages();
    for (let i = 0; i < pages.length; i++) {
      if (pages[i].uuid === pageId) {
        return pages[i].originalName;
      }
    }
    return pageId;
  }

  /**
   * 判断日期是否过期（早于今天）。
   */
  private isOverdue(dateStr: string): boolean {
    return dateStr.length > 0 && dateStr < this.today;
  }

  /**
   * 判断日期是否为今天。
   */
  private isToday(dateStr: string): boolean {
    return dateStr === this.today;
  }

  /**
   * 获取内容摘要。
   */
  private summary(content: string, max: number): string {
    if (content.length <= max) {
      return content;
    }
    return content.substring(0, max) + '…';
  }

  /**
   * 获取 marker 的颜色。
   */
  private markerColor(marker: string): ResourceColor {
    if (marker === 'DONE') {
      return $r('app.color.success');
    }
    if (marker === 'CANCELLED') {
      return $r('app.color.muted_text');
    }
    return $r('app.color.primary');
  }

  build() {
    if (this.scheduledTasks.length === 0 && this.deadlineTasks.length === 0) {
      // 无任务时不渲染
      Column().width(0).height(0)
    } else {
      Column({ space: 8 }) {
        // 面板标题栏（可折叠）
        Row({ space: 8 }) {
          TablerIcon('calendar-event', 16, $r('app.color.primary'))
          Text('任务计划')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
          Row() {
            TablerIcon(this.isExpanded ? 'chevron-up' : 'chevron-down', 16, $r('app.color.muted_text'))
          }
          .width(28).height(28)
          .onClick(() => {
            this.isExpanded = !this.isExpanded;
          })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(8)
        .backgroundColor($r('app.color.surface1'))

        if (this.isExpanded) {
          // SCHEDULED 区块
          if (this.scheduledTasks.length > 0) {
            this.TaskSection('计划任务', this.scheduledTasks, 'scheduled')
          }

          // DEADLINE 区块
          if (this.deadlineTasks.length > 0) {
            this.TaskSection('截止任务', this.deadlineTasks, 'deadline')
          }
        }
      }
      .width('100%')
    }
  }

  @Builder
  TaskSection(title: string, tasks: TaskItem[], dateField: string) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        TablerIcon(dateField === 'deadline' ? 'alert-triangle' : 'calendar', 13,
          dateField === 'deadline' ? $r('app.color.danger') : $r('app.color.muted_text'))
        Text(title + ' (' + tasks.length + ')')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .padding({ left: 12, top: 2, bottom: 2 })

      ForEach(tasks, (task: TaskItem) => {
        this.TaskRow(task, dateField)
      }, (task: TaskItem) => task.blockUuid + '-' + dateField)
    }
    .width('100%')
  }

  @Builder
  TaskRow(task: TaskItem, dateField: string) {
    Row({ space: 6 }) {
      // Marker 标签
      Text(task.marker)
        .fontSize(9)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.markerColor(task.marker))
        .padding({ left: 3, right: 3, top: 1, bottom: 1 })
        .borderRadius(2)
        .backgroundColor($r('app.color.surface2'))

      // 内容摘要
      Text(this.summary(task.content, 36))
        .fontSize(12)
        .fontColor($r('app.color.text'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      // 日期
      Text(dateField === 'deadline' ? task.deadline : task.scheduled)
        .fontSize(10)
        .fontColor(this.dateColor(task, dateField))
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .borderRadius(2)
        .backgroundColor(this.dateBgColor(task, dateField))

      // 所属页面
      Text(task.pageName)
        .fontSize(9)
        .fontColor($r('app.color.link'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 60 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
    .borderRadius(6)
    .onClick(() => {
      AppState.setCurrentPage(task.pageName);
    })
  }

  /**
   * 获取日期文本颜色：过期 danger，今日 warning，其他 muted。
   */
  private dateColor(task: TaskItem, dateField: string): ResourceColor {
    const dateStr = dateField === 'deadline' ? task.deadline : task.scheduled;
    if (this.isOverdue(dateStr)) {
      return $r('app.color.danger');
    }
    if (this.isToday(dateStr)) {
      return $r('app.color.warning');
    }
    return $r('app.color.muted_text');
  }

  /**
   * 获取日期背景色：过期淡红，今日淡黄，其他透明。
   */
  private dateBgColor(task: TaskItem, dateField: string): ResourceColor {
    const dateStr = dateField === 'deadline' ? task.deadline : task.scheduled;
    if (this.isOverdue(dateStr)) {
      return $r('app.color.surface2');
    }
    if (this.isToday(dateStr)) {
      return $r('app.color.surface2');
    }
    return Color.Transparent;
  }
}
