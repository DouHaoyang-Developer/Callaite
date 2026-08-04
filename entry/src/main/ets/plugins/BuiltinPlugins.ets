import { LuniusPlugin } from './LuniusPlugin';
import { PluginManager } from './PluginManager';
import { PluginAPI } from './PluginAPI';

/**
 * BookmarkPlugin — 每日速记插件。
 */
export class BookmarkPlugin extends LuniusPlugin {
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
export class TodoExportPlugin extends LuniusPlugin {
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
 * 注册所有内置插件。
 */
export function registerBuiltinPlugins(): void {
  PluginManager.getInstance()
    .register(new BookmarkPlugin())
    .register(new TodoExportPlugin())
    .initAllPlugins();
}
