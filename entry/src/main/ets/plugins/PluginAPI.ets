import { WorkspaceService } from '../services/WorkspaceService';
import { AppState } from '../state/AppState';

/**
 * PluginAPI — 插件能力代理。
 *
 * 提供给插件的 API 接口集合，插件通过此类访问应用核心功能。
 * 新能力通过 PluginManager.registerAPI() 动态注册。
 */
export class PluginAPI {
  private static apis: Map<string, Object> = new Map<string, Object>();

  /**
   * 注册一个 API 能力。
   */
  static register(name: string, api: Object): void {
    PluginAPI.apis.set(name, api);
  }

  /**
   * 获取已注册的 API 能力。
   */
  static get<T>(name: string): T | undefined {
    return PluginAPI.apis.get(name) as T;
  }

  // ─── 内置 API ───

  /** 获取当前页面名 */
  static getCurrentPage(): string {
    return AppState.getCurrentPage();
  }

  /** 切换页面 */
  static navigateTo(page: string): void {
    AppState.setCurrentPage(page);
  }

  /** 在今日日志插入 Block */
  static insertTodayBlock(content: string, marker: string = ''): void {
    const ws = WorkspaceService.getInstance();
    const now = new Date();
    const today = now.getFullYear() + '-' +
      (now.getMonth() + 1).toString().padStart(2, '0') + '-' +
      now.getDate().toString().padStart(2, '0');
    const page = ws.getPageByName(today);
    if (!page) return;
    const contentWithMarker = marker ? marker + ' ' + content : content;
    ws.executeOp({
      type: 'insert-block', content: contentWithMarker,
      pageId: page.uuid, parentId: page.uuid, leftId: '', level: 0
    });
  }

  /** 搜索页面 */
  static searchPages(query: string): string[] {
    const ws = WorkspaceService.getInstance();
    const pages = ws.searchPages(query);
    const names: string[] = [];
    for (let i = 0; i < pages.length; i++) names.push(pages[i].originalName);
    return names;
  }

  /** 获取所有标签 */
  static getAllTags(): string[] {
    return WorkspaceService.getInstance().getAllTags();
  }
}
