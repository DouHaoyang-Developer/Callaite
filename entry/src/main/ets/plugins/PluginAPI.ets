import { WorkspaceService } from '../services/WorkspaceService';
import { AppState } from '../state/AppState';
import { TemplateService, TemplateInfo } from '../services/TemplateService';
import { promptAction } from '@kit.ArkUI';

export interface PluginStats {
  pages: number;
  blocks: number;
}

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

  /** 获取所有页面名 */
  static listAllPages(): string[] {
    const pages = WorkspaceService.getInstance().getAllPages();
    const names: string[] = [];
    for (let i = 0; i < pages.length; i++) {
      names.push(pages[i].originalName);
    }
    return names;
  }

  /** 获取页面 Block 内容摘要 */
  static getPageBlocks(pageName: string): string[] {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) {
      return [];
    }
    const blocks = ws.getPageBlocks(page.uuid);
    const result: string[] = [];
    for (let i = 0; i < blocks.length; i++) {
      result.push(blocks[i].content.substring(0, 80));
    }
    return result;
  }

  /** 统计页面与 Block 数量 */
  static getPageStats(): PluginStats {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    let blocks = 0;
    for (let i = 0; i < pages.length; i++) {
      blocks = blocks + ws.getPageBlocks(pages[i].uuid).length;
    }
    const stats: PluginStats = { pages: pages.length, blocks: blocks };
    return stats;
  }

  /** 获取内置模板名列表 */
  static getTemplateNames(): string[] {
    const templates = TemplateService.getBuiltinTemplates();
    const names: string[] = [];
    for (let i = 0; i < templates.length; i++) {
      names.push(templates[i].name);
    }
    return names;
  }

  /** 按名称插入模板到今日日志 */
  static insertTemplateByName(name: string): boolean {
    const templates = TemplateService.getBuiltinTemplates();
    for (let i = 0; i < templates.length; i++) {
      if (templates[i].name === name) {
        const expanded = TemplateService.expand(templates[i].content, PluginAPI.getCurrentPage());
        PluginAPI.insertTodayBlock(expanded, '');
        return true;
      }
    }
    return false;
  }

  /** 弹出通知 toast */
  static notify(message: string): void {
    promptAction.openToast({ message: message }).catch(() => {});
  }
}
