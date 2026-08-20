import { WorkspaceService } from './WorkspaceService';
import { I18n } from '../utils/i18n';

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
   * 将 yyyy-MM-dd 格式的日志页名格式化为 Logseq 风格的本地化标题：
   * 中文：2026年8月20日 星期四；英文：Aug 20th, 2026。
   * 页面存储名保持 yyyy-MM-dd 不变，仅用于显示。
   */
  static formatJournalTitle(dateStr: string): string {
    const parts = dateStr.split('-');
    if (parts.length !== 3) {
      return dateStr;
    }
    const year = parseInt(parts[0]);
    const month = parseInt(parts[1]);
    const day = parseInt(parts[2]);
    const date = new Date(year, month - 1, day);
    if (I18n.getLanguage() === 'zh-CN') {
      const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
      return year + '年' + month + '月' + day + '日 星期' + weekdays[date.getDay()];
    }
    const months: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    let suffix = 'th';
    if (day % 10 === 1 && day !== 11) {
      suffix = 'st';
    } else if (day % 10 === 2 && day !== 12) {
      suffix = 'nd';
    } else if (day % 10 === 3 && day !== 13) {
      suffix = 'rd';
    }
    return months[month - 1] + ' ' + day + suffix + ', ' + year;
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
