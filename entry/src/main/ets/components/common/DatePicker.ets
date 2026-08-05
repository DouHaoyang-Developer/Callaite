import { TablerIcon } from '../common/Icons';
import { JournalService } from '../../services/JournalService';

/**
 * DatePicker — 日历日期选择器组件。
 *
 * 职责：
 *  - 月份导航（左右箭头切换月份）
 *  - 星期标题行：日 一 二 三 四 五 六
 *  - 6 行 × 7 列日期网格
 *  - 选中日期高亮、今日日期标记
 *  - 快捷选择：今天 / 明天 / 下周 / 下月
 *  - 选中后通过 onSelect 回调返回 yyyy-MM-dd 格式日期
 *
 * 注意：
 *  - @Prop selectedDate 受控的当前选中日期
 *  - @State isVisible 控制日历面板展开/折叠
 *  - 折叠时仅显示选中日期触发器，展开后显示完整日历
 */

// 星期标题
const WEEK_HEADERS: string[] = ['日', '一', '二', '三', '四', '五', '六'];

// 月份显示名
const MONTH_NAMES: string[] = [
  '1月', '2月', '3月', '4月', '5月', '6月',
  '7月', '8月', '9月', '10月', '11月', '12月'
];

// 快捷选项
interface QuickOption {
  label: string;
  icon: string;
}

const QUICK_OPTIONS: QuickOption[] = [
  { label: '今天', icon: 'calendar' },
  { label: '明天', icon: 'calendar-plus' },
  { label: '下周', icon: 'calendar-week' },
  { label: '下月', icon: 'calendar-month' }
];

// 日期网格单元
interface GridCell {
  day: number;
  isCurrentMonth: boolean;
  dateStr: string;
}

@Component
export struct DatePicker {
  @Prop selectedDate: string = '';
  @State currentMonth: number = 0;
  @State currentYear: number = 0;
  @State isVisible: boolean = false;
  @State gridCells: GridCell[] = [];

  // 选中回调
  onSelect: (date: string) => void = (date: string) => {};

  aboutToAppear(): void {
    // 初始化日历视图到 selectedDate 对应的月份，或今天
    const today = new Date();
    if (this.selectedDate.length > 0) {
      const parsed = this.parseDate(this.selectedDate);
      if (parsed) {
        this.currentYear = parsed.year;
        this.currentMonth = parsed.month;
      } else {
        this.currentYear = today.getFullYear();
        this.currentMonth = today.getMonth();
      }
    } else {
      this.currentYear = today.getFullYear();
      this.currentMonth = today.getMonth();
    }
    this.buildGrid();
  }

  // ─── 日期计算私有方法 ───

  /**
   * 获取指定年份月份的天数。
   */
  private getDaysInMonth(year: number, month: number): number {
    // month 为 0-11，利用下个月第 0 天返回当月最后一天
    return new Date(year, month + 1, 0).getDate();
  }

  /**
   * 获取指定年份月份第一天是星期几（0=周日, 1=周一, ..., 6=周六）。
   */
  private getFirstDayOfWeek(year: number, month: number): number {
    return new Date(year, month, 1).getDay();
  }

  /**
   * 格式化日期字符串为 yyyy-MM-dd。
   * month 为 0-11，day 为 1-31。
   */
  private formatDateString(year: number, month: number, day: number): string {
    const y = year.toString();
    const m = (month + 1).toString().padStart(2, '0');
    const d = day.toString().padStart(2, '0');
    return y + '-' + m + '-' + d;
  }

  /**
   * 判断指定日期是否为今天。
   */
  private isToday(year: number, month: number, day: number): boolean {
    const todayStr = JournalService.getTodayDateString();
    const target = this.formatDateString(year, month, day);
    return todayStr === target;
  }

  /**
   * 解析 yyyy-MM-dd 字符串为 { year, month, day }。失败返回 undefined。
   */
  private parseDate(dateStr: string): { year: number; month: number; day: number } | undefined {
    if (dateStr.length < 10) {
      return undefined;
    }
    const parts = dateStr.split('-');
    if (parts.length !== 3) {
      return undefined;
    }
    const y = parseInt(parts[0], 10);
    const m = parseInt(parts[1], 10) - 1;
    const d = parseInt(parts[2], 10);
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
      return undefined;
    }
    return { year: y, month: m, day: d };
  }

  /**
   * 构建 6×7 日期网格（42 个单元）。
   * 包含上月末尾几天、当月全部、下月开头几天。
   */
  private buildGrid(): void {
    const cells: GridCell[] = [];
    const firstDay = this.getFirstDayOfWeek(this.currentYear, this.currentMonth);
    const daysInCurrent = this.getDaysInMonth(this.currentYear, this.currentMonth);
    const daysInPrev = this.getDaysInMonth(this.currentYear, this.currentMonth - 1);

    // 上月填充
    for (let i = firstDay - 1; i >= 0; i--) {
      const day = daysInPrev - i;
      let year = this.currentYear;
      let month = this.currentMonth - 1;
      if (month < 0) {
        month = 11;
        year = year - 1;
      }
      const cell: GridCell = {
        day: day,
        isCurrentMonth: false,
        dateStr: this.formatDateString(year, month, day)
      };
      cells.push(cell);
    }

    // 当月
    for (let d = 1; d <= daysInCurrent; d++) {
      const cell: GridCell = {
        day: d,
        isCurrentMonth: true,
        dateStr: this.formatDateString(this.currentYear, this.currentMonth, d)
      };
      cells.push(cell);
    }

    // 下月填充至 42 格
    const remaining = 42 - cells.length;
    for (let d = 1; d <= remaining; d++) {
      let year = this.currentYear;
      let month = this.currentMonth + 1;
      if (month > 11) {
        month = 0;
        year = year + 1;
      }
      const cell: GridCell = {
        day: d,
        isCurrentMonth: false,
        dateStr: this.formatDateString(year, month, d)
      };
      cells.push(cell);
    }

    this.gridCells = cells;
  }

  /**
   * 切换到上一个月。
   */
  private prevMonth(): void {
    let m = this.currentMonth - 1;
    let y = this.currentYear;
    if (m < 0) {
      m = 11;
      y = y - 1;
    }
    this.currentMonth = m;
    this.currentYear = y;
    this.buildGrid();
  }

  /**
   * 切换到下一个月。
   */
  private nextMonth(): void {
    let m = this.currentMonth + 1;
    let y = this.currentYear;
    if (m > 11) {
      m = 0;
      y = y + 1;
    }
    this.currentMonth = m;
    this.currentYear = y;
    this.buildGrid();
  }

  /**
   * 选中某个日期。
   */
  private selectDate(dateStr: string): void {
    this.onSelect(dateStr);
    this.isVisible = false;
  }

  /**
   * 快捷选择。
   */
  private quickSelect(label: string): void {
    let dateStr = '';
    if (label === '今天') {
      dateStr = JournalService.getTodayDateString();
    } else if (label === '明天') {
      dateStr = JournalService.getTomorrowDateString();
    } else if (label === '下周') {
      dateStr = JournalService.getDateAfter(7);
    } else if (label === '下月') {
      dateStr = JournalService.getDateAfter(30);
    }
    if (dateStr.length > 0) {
      const parsed = this.parseDate(dateStr);
      if (parsed) {
        this.currentYear = parsed.year;
        this.currentMonth = parsed.month;
        this.buildGrid();
      }
      this.selectDate(dateStr);
    }
  }

  /**
   * 获取月份标题文本。
   */
  private monthTitle(): string {
    return this.currentYear + '年 ' + MONTH_NAMES[this.currentMonth];
  }

  build() {
    Column({ space: 8 }) {
      // 触发器：显示当前选中日期
      Row({ space: 6 }) {
        TablerIcon('calendar', 16, $r('app.color.muted_text'))
        Text(this.selectedDate.length > 0 ? this.selectedDate : '选择日期')
          .fontSize(13)
          .fontColor(this.selectedDate.length > 0
            ? $r('app.color.text') : $r('app.color.muted_text'))
          .layoutWeight(1)
        TablerIcon(this.isVisible ? 'chevron-up' : 'chevron-down', 14, $r('app.color.muted_text'))
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .borderRadius(8)
      .backgroundColor($r('app.color.surface1'))
      .onClick(() => {
        this.isVisible = !this.isVisible;
      })

      // 日历面板
      if (this.isVisible) {
        Column({ space: 8 }) {
          // 月份导航
          Row() {
            Row() {
              TablerIcon('chevron-left', 18, $r('app.color.muted_text'))
            }
            .width(32).height(32)
            .onClick(() => {
              this.prevMonth();
            })

            Text(this.monthTitle())
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            Row() {
              TablerIcon('chevron-right', 18, $r('app.color.muted_text'))
            }
            .width(32).height(32)
            .onClick(() => {
              this.nextMonth();
            })
          }
          .width('100%')

          // 星期标题
          Row() {
            ForEach(WEEK_HEADERS, (h: string) => {
              Text(h)
                .fontSize(11)
                .fontColor($r('app.color.muted_text'))
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
            }, (h: string) => h)
          }
          .width('100%')

          // 日期网格（6 行 × 7 列）
          Grid() {
            ForEach(this.gridCells, (cell: GridCell, index: number) => {
              GridItem() {
                this.DateCell(cell)
              }
            }, (cell: GridCell, index: number) => cell.dateStr + '-' + index.toString())
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
          .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
          .width('100%')
          .height(240)

          // 快捷选择
          Row() {
            ForEach(QUICK_OPTIONS, (opt: QuickOption) => {
              Row({ space: 3 }) {
                TablerIcon(opt.icon, 12, $r('app.color.muted_text'))
                Text(opt.label)
                  .fontSize(11)
                  .fontColor($r('app.color.text'))
              }
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor($r('app.color.surface1'))
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.quickSelect(opt.label);
              })
            }, (opt: QuickOption) => opt.label)
          }
          .width('100%')
        }
        .width('100%')
        .padding(10)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface2'))
      }
    }
    .width('100%')
  }

  @Builder
  DateCell(cell: GridCell) {
    Column() {
      Text(cell.day.toString())
        .fontSize(12)
        .fontColor(this.cellTextColor(cell))
        .fontWeight(cell.dateStr === this.selectedDate ? FontWeight.Bold : FontWeight.Normal)
      // 今日圆点标记
      if (this.isTodayFromStr(cell.dateStr)) {
        Circle({ width: 3, height: 3 })
          .fill($r('app.color.primary'))
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .borderRadius(6)
    .backgroundColor(this.cellBgColor(cell))
    .onClick(() => {
      this.selectDate(cell.dateStr);
    })
  }

  /**
   * 从日期字符串判断是否为今天（适配 isToday 私有方法的对外封装）。
   */
  private isTodayFromStr(dateStr: string): boolean {
    const parsed = this.parseDate(dateStr);
    if (parsed) {
      return this.isToday(parsed.year, parsed.month, parsed.day);
    }
    return false;
  }

  /**
   * 单元格文本颜色。
   */
  private cellTextColor(cell: GridCell): ResourceColor {
    if (cell.dateStr === this.selectedDate) {
      return Color.White;
    }
    if (!cell.isCurrentMonth) {
      return $r('app.color.muted_text');
    }
    return $r('app.color.text');
  }

  /**
   * 单元格背景色：选中 primary，今日 surface2，其他透明。
   */
  private cellBgColor(cell: GridCell): ResourceColor {
    if (cell.dateStr === this.selectedDate) {
      return $r('app.color.primary');
    }
    if (this.isTodayFromStr(cell.dateStr)) {
      return $r('app.color.surface2');
    }
    return Color.Transparent;
  }
}
