import { CallaitePlugin } from './CallaitePlugin';
import { PluginManager } from './PluginManager';
import { PluginAPI } from './PluginAPI';

/**
 * BookmarkPlugin — 每日速记插件。
 */
export class BookmarkPlugin extends CallaitePlugin {
  get id(): string { return 'callaite-bookmark'; }
  get name(): string { return '每日速记'; }
  get version(): string { return '1.0.0'; }
  get description(): string { return '每天自动在日志页插入快速记录模板'; }
  get enabledByDefault(): boolean { return true; }

  onEnable(): void {
    PluginAPI.insertTodayBlock('📌 今日要点: ', 'TODO');
  }
}

/**
 * TodoExportPlugin — 待办统计插件。
 */
export class TodoExportPlugin extends CallaitePlugin {
  get id(): string { return 'callaite-todo-export'; }
  get name(): string { return '待办统计'; }
  get version(): string { return '1.0.0'; }
  get description(): string { return '统计并导出待办事项'; }
  get enabledByDefault(): boolean { return false; }

  onEnable(): void {
    const tags = PluginAPI.getAllTags();
    console.info('[TodoExportPlugin] Tags: ' + tags.length);
  }
}

/**
 * PageStatsPlugin — 页面统计插件。
 */
export class PageStatsPlugin extends CallaitePlugin {
  get id(): string { return 'callaite-page-stats'; }
  get name(): string { return '页面统计'; }
  get version(): string { return '1.0.0'; }
  get description(): string { return '统计知识库中的页面与 Block 数量'; }
  get enabledByDefault(): boolean { return false; }

  onEnable(): void {
    const stats = PluginAPI.getPageStats();
    console.info('[PageStatsPlugin] pages=' + stats.pages + ' blocks=' + stats.blocks);
  }
}

/**
 * TemplateInsertPlugin — 模板插入插件。
 */
export class TemplateInsertPlugin extends CallaitePlugin {
  get id(): string { return 'callaite-template-insert'; }
  get name(): string { return '模板插入'; }
  get version(): string { return '1.0.0'; }
  get description(): string { return '提供日记、会议、项目、周回顾等内置模板'; }
  get enabledByDefault(): boolean { return false; }

  onEnable(): void {
    const names = PluginAPI.getTemplateNames();
    console.info('[TemplateInsertPlugin] templates=' + names.length);
  }
}

/**
 * 注册所有内置插件。
 */
export function registerBuiltinPlugins(): void {
  PluginManager.getInstance()
    .register(new BookmarkPlugin())
    .register(new TodoExportPlugin())
    .register(new PageStatsPlugin())
    .register(new TemplateInsertPlugin())
    .initAllPlugins();
}
