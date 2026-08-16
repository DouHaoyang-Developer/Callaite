import { WorkspaceService } from './WorkspaceService';

/**
 * JournalService — 日志页服务。
 *
 * 负责日志页的自动创建、日期格式化。
 * 对应 Logseq handler/journal.cljs。
 */
export class JournalService {

  /**
   * 获取今天的日期字符串 yyyy-MM-dd。
   */
  static getTodayDateString(): string {
    const now = new Date();
    const year = now.getFullYear().toString();
    const month = (now.getMonth() + 1).toString().padStart(2, '0');
    const day = now.getDate().toString().padStart(2, '0');
    return year + '-' + month + '-' + day;
  }

  /**
   * 确保指定日期的日志页存在，如果不存在则自动创建。
   * 日志流 feed 渲染每一天前调用，保证空日期页也可编辑。
   */
  static ensureJournal(dateStr: string): string {
    const ws = WorkspaceService.getInstance();
    let page = ws.getPageByName(dateStr);
    if (!page) {
      page = ws.createJournalPage(dateStr);
    }
    return dateStr;
  }

  /**
   * 确保今天的日志页存在，如果不存在则自动创建。
   */
  static ensureTodayJournal(): string {
    const today = JournalService.getTodayDateString();
    JournalService.ensureJournal(today);
    return today;
  }

  /**
   * 获取昨天的日期字符串。
   */
  static getYesterdayDateString(): string {
    const now = new Date();
    now.setDate(now.getDate() - 1);
    const year = now.getFullYear().toString();
    const month = (now.getMonth() + 1).toString().padStart(2, '0');
    const day = now.getDate().toString().padStart(2, '0');
    return year + '-' + month + '-' + day;
  }

  /**
   * 获取 N 天后的日期字符串。
   */
  static getDateAfter(days: number): string {
    const now = new Date();
    now.setDate(now.getDate() + days);
    const year = now.getFullYear().toString();
    const month = (now.getMonth() + 1).toString().padStart(2, '0');
    const day = now.getDate().toString().padStart(2, '0');
    return year + '-' + month + '-' + day;
  }

  /**
   * 获取明天的日期字符串。
   */
  static getTomorrowDateString(): string {
    const now = new Date();
    now.setDate(now.getDate() + 1);
    const year = now.getFullYear().toString();
    const month = (now.getMonth() + 1).toString().padStart(2, '0');
    const day = now.getDate().toString().padStart(2, '0');
    return year + '-' + month + '-' + day;
  }
}
