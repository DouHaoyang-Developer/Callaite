import { BlockList } from '../outliner/BlockList';
import { TaskDashboard } from '../search/TaskDashboard';
import { JournalService } from '../../services/JournalService';
import { AppState } from '../../state/AppState';
import { display } from '@kit.ArkUI';

/**
 * JournalFeed — 日志流首页，对应 Logseq journal.cljs 的 all-journals。
 *
 * 首页不再只显示今天，而是「最近日期在上」的无限滚动时间流：
 * 初始加载最近 7 天，滚动到底部（onReachEnd）时每次向前追加 7 天。
 * 每一天一节：日期标题（点击进入单日页）+ 该日的 BlockList（embedded 模式）。
 * 日期标题格式与单日页一致（yyyy-MM-dd）。
 */
@Component
export struct JournalFeed {
  @State days: string[] = [];

  aboutToAppear(): void {
    JournalService.ensureTodayJournal();
    this.appendDays(7);
  }

  /**
   * 向前追加 N 天的日期（从当前最后一天的下一天开始）。
   * 不预创建页面（保持全部页面列表干净），空日期在编辑时由 BlockList 懒创建。
   */
  appendDays(count: number): void {
    const base: number = this.days.length;
    for (let i = 0; i < count; i++) {
      this.days.push(JournalService.getDateAfter(-(base + i)));
    }
  }

  /**
   * 响应式内容留白：与 PageView.getContentPadding 保持一致。
   */
  getContentPadding(): number {
    try {
      const d = display.getDefaultDisplaySync();
      if (d.width / d.densityPixels < 768) {
        return 20;
      }
    } catch (_e) {
      // 取不到显示信息时用窄屏值
    }
    return 48;
  }

  build() {
    Scroll() {
      Column({ space: 0 }) {
        Column({ space: 0 }) {
          ForEach(this.days, (day: string, index: number) => {
            Column({ space: 0 }) {
              // 日期标题（Logseq 本地化格式）— 点击进入该日单日页
              Text(JournalService.formatJournalTitle(day))
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text'))
                .opacity(index === 0 ? 1 : 0.85)
                .width('100%')
                .padding({ top: index === 0 ? 20 : 32, bottom: 8 })
                .onClick(() => {
                  AppState.setCurrentPage(day);
                })

              // 任务面板（仅今天）
              if (index === 0) {
                TaskDashboard({ pageName: day })
              }

              // 该日 Block 列表（内嵌模式：高度自适应、无多选浮动栏）
              BlockList({ pageName: day, embedded: true })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (day: string) => day)
        }
        .width('100%')
        .constraintSize({ maxWidth: 960 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: this.getContentPadding(), right: this.getContentPadding() })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.Top)
    .onReachEnd(() => {
      this.appendDays(7);
    })
  }
}
