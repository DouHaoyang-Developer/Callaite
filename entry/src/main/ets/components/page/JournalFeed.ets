import { BlockList } from '../outliner/BlockList';
import { TaskDashboard } from '../search/TaskDashboard';
import { JournalService } from '../../services/JournalService';
import { AppState } from '../../state/AppState';
import { display } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * JournalFeed — 日志流首页，对应 Logseq journal.cljs 的 all-journals。
 *
 * 首页不再只显示今天，而是「最近日期在上」的无限滚动时间流：
 * 初始加载最近 7 天，滚动到底部（onReachEnd）时每次向前追加 7 天。
 * 每一天一节：日期标题（点击进入单日页）+ 该日的 BlockList（embedded 模式）。
 * 日期标题格式与单日页一致（yyyy-MM-dd）。
 *
 * 追加受两道约束（见 appendDays）：
 *  1) 节流时间窗 APPEND_COOLDOWN_MS：一次滚动会话内的连续触底只追加一次；
 *  2) 可回溯天数上限 MAX_JOURNAL_DAYS：触达后不再追加，且只在首次触达时打一条 NO_MORE。
 */

/**
 * 追加节流时间窗（毫秒）。取值依据见 appendDays 注释：
 * 需大于「一次惯性滑动 + 7 天新节布局提交」的窗口（实测同一会话约 3 次触底，间隔数百毫秒），
 * 又要小于用户感知「卡住」的 1s 量级，500ms 取在两者之间。
 */
const APPEND_COOLDOWN_MS: number = 500;

/**
 * 可回溯天数上限。180 天 ≈ 半年：
 * 日志流定位是「最近的日志上下文」，半年之外靠日期跳转而非无限下拉；
 * 每天一节且每节一个 BlockList，180 节已接近纯 ForEach 渲染的舒适上限，
 * 再多只增加布局与磁盘读取成本、不增加可用性。
 */
const MAX_JOURNAL_DAYS: number = 180;

@Component
export struct JournalFeed {
  @State days: string[] = [];

  /** 上次成功追加的时间戳（ms）；0 表示尚未追加过，保证初始加载不被节流。 */
  private lastAppendMs: number = 0;

  /** 上限日志只打一次的标记，避免每次触底刷屏。 */
  private limitReachedLogged: boolean = false;

  aboutToAppear(): void {
    JournalService.ensureTodayJournal();
    this.appendDays(7);
  }

  /**
   * 向前追加 N 天的日期（从当前最后一天的下一天开始）。
   * 不预创建页面（保持全部页面列表干净），空日期在编辑时由 BlockList 懒创建。
   *
   * 入口处两道闸：
   *  - 上限闸在前：已达 MAX_JOURNAL_DAYS 就直接返回（首次触达打一条 NO_MORE，之后静默），
   *    这样触底噪声不会再叠出一串 SKIP；
   *  - 节流闸在后：用时间窗而非「追加中」布尔标记。
   *    原因：本函数是纯同步的（只有 for 循环 + push，无 await），
   *    布尔标记在 return 之前就已复位，下一次 onReachEnd 回调进来时它永远是 false，
   *    抑制不住任何东西；时间戳记录的是「上一次真的追加了」，
   *    与回调何时再次触发无关，才真正能覆盖一次滚动会话。
   */
  appendDays(count: number): void {
    const base: number = this.days.length;

    // ① 上限：达到可回溯天数上限后不再追加；只在首次触达时打一条日志
    if (base >= MAX_JOURNAL_DAYS) {
      if (!this.limitReachedLogged) {
        this.limitReachedLogged = true;
        hilog.info(0x0000, 'JOURNALFEED',
          'NO_MORE total=' + base + ' limit=' + MAX_JOURNAL_DAYS + ' first=1');
      }
      return;
    }

    // ② 节流：同一次滚动会话内被抑制的追加会打 SKIP，便于从日志确认节流生效
    const nowMs: number = Date.now();
    const delta: number = nowMs - this.lastAppendMs;
    if (this.lastAppendMs > 0 && delta < APPEND_COOLDOWN_MS) {
      hilog.info(0x0000, 'JOURNALFEED',
        'SKIP reason=cooldown delta=' + delta + ' threshold=' + APPEND_COOLDOWN_MS + ' total=' + base);
      return;
    }
    this.lastAppendMs = nowMs;

    // ③ 末尾夹取：距上限不足 count 天时只补到上限，保证 days.length 恒 <= MAX_JOURNAL_DAYS
    //    （正常区间 actual 恒等于 count，追加天数与既有行为一致）
    let actual: number = count;
    const remaining: number = MAX_JOURNAL_DAYS - base;
    if (actual > remaining) {
      actual = remaining;
    }

    const now: Date = new Date();
    hilog.info(0x0000, 'JOURNALFEED',
      'APPEND days=' + actual + ' from=' + JournalService.getDateAfter(-base)
        + ' total=' + base + ' today=' + now.getFullYear() + '-' + (now.getMonth() + 1) + '-' + now.getDate());
    for (let i = 0; i < actual; i++) {
      this.days.push(JournalService.getDateAfter(-(base + i)));
    }
    hilog.info(0x0000, 'JOURNALFEED',
      'APPEND_DONE added=' + actual + ' total=' + this.days.length + ' newest=' + this.days[0]
        + ' oldest=' + this.days[this.days.length - 1]);
  }

  /**
   * 响应式内容留白：与 PageView.getContentPadding 保持一致。
   */
  getContentPadding(): number {
    try {
      const d = display.getDefaultDisplaySync();
      if (d.width / d.densityPixels < 600) {
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

              // 任务面板（仅今天）。S3-W4：原先这里传的 `pageName: day` 已被删除 ——
              // 该组件从不读它，且它自己的日期窗口就是 `getTodayDateString()`。
              if (index === 0) {
                TaskDashboard()
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
