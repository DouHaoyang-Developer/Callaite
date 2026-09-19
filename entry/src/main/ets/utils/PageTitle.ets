import { t } from './i18n';
import { JournalService } from '../services/JournalService';

const DATE_ONLY: RegExp = /^\d{4}-\d{2}-\d{2}$/;

/**
 * 页面显示标题解析 —— 把内部路由标识映射为本地化标题。
 *
 * 背景：AppState.currentPage 保存的是**内部路由名**（Journal / AllPages / Graph /
 * Whiteboards / Flashcards / Pdf / Settings / ProUpgrade）。此前标题栏、标签页、
 * 状态栏直接渲染该原始值，导致中文界面里混入 "Settings"、"AllPages"、"Pdf"
 * 这类内部英文标识，且与页面正文标题（「设置」）自相矛盾。
 *
 * 统一入口：所有需要展示页面名的地方都应调用 pageTitle()，不要再直接用 currentPage。
 */
export function pageTitle(page: string): string {
  if (page === 'Journal') {
    return JournalService.formatJournalTitle(JournalService.getTodayDateString());
  }
  if (DATE_ONLY.test(page)) {
    return JournalService.formatJournalTitle(page);
  }
  if (page === 'AllPages') {
    return t('nav_all_pages');
  }
  if (page === 'Graph') {
    return t('nav_graph_view');
  }
  if (page === 'Whiteboards') {
    return t('title_whiteboards');
  }
  if (page === 'Flashcards') {
    return t('nav_flashcards');
  }
  if (page === 'Pdf') {
    return t('title_pdf');
  }
  if (page === 'Settings') {
    return t('title_settings');
  }
  if (page === 'ProUpgrade') {
    return t('title_pro_upgrade');
  }
  // 普通笔记页 —— 页面名本身即可读
  return page;
}
