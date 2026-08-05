import { CallaitePlugin } from './CallaitePlugin';
import { PluginAPI } from './PluginAPI';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * PluginManager — 插件管理器（单例）。
 *
 * 负责插件注册、发现、启用/禁用、状态持久化。
 *
 * 架构: 插件预编译为 ArkTS 模块 → PluginManager 通过静态注册表发现 → 按用户配置启用/禁用。
 * 无需动态 require/eval，完全兼容 ArkTS 安全模型。
 */
export class PluginManager {
  private static instance: PluginManager | undefined;
  private plugins: Map<string, CallaitePlugin> = new Map<string, CallaitePlugin>();
  private enabledPlugins: Set<string> = new Set<string>();
  // 修复：添加 disabledPlugins 集合，区分"显式禁用"和"未配置"
  private disabledPlugins: Set<string> = new Set<string>();
  private registry: CallaitePlugin[] = [];

  private readonly CONFIG_PATH = '/data/storage/el2/base/files/plugin_state.json';

  static getInstance(): PluginManager {
    if (!PluginManager.instance) {
      PluginManager.instance = new PluginManager();
    }
    return PluginManager.instance;
  }

  register(plugin: CallaitePlugin): PluginManager {
    this.registry.push(plugin);
    return this;
  }

  initAllPlugins(): void {
    this.loadState();
    for (let i = 0; i < this.registry.length; i++) {
      const plugin = this.registry[i];
      this.plugins.set(plugin.id, plugin);
      // 修复：正确区分"显式启用"、"显式禁用"、"未配置（按默认）"三种状态
      if (this.enabledPlugins.has(plugin.id)) {
        // 显式启用
        this.enable(plugin.id);
      } else if (this.disabledPlugins.has(plugin.id)) {
        // 显式禁用 — 不启用
      } else if (plugin.enabledByDefault) {
        // 未配置但默认启用
        this.enable(plugin.id);
      }
    }
    console.info('[PluginManager] Initialized ' + this.plugins.size + ' plugins');
  }

  /**
   * 启用插件。
   */
  enable(pluginId: string): void {
    const plugin = this.plugins.get(pluginId);
    if (!plugin) return;
    try {
      plugin.onEnable();
      this.enabledPlugins.add(pluginId);
      // 修复：启用时从显式禁用集合中移除
      this.disabledPlugins.delete(pluginId);
      this.saveState();
    } catch (e) {
      console.error('[PluginManager] Failed to enable: ' + pluginId, e);
    }
  }

  /**
   * 禁用插件。
   */
  disable(pluginId: string): void {
    const plugin = this.plugins.get(pluginId);
    if (!plugin) return;
    try {
      plugin.onDisable();
      this.enabledPlugins.delete(pluginId);
      // 修复：记录显式禁用状态，防止重启后默认启用的插件被重新启用
      this.disabledPlugins.add(pluginId);
      this.saveState();
    } catch (e) {
      console.error('[PluginManager] Failed to disable: ' + pluginId, e);
    }
  }

  /**
   * 获取所有已注册插件。
   */
  getAll(): CallaitePlugin[] {
    const result: CallaitePlugin[] = [];
    this.plugins.forEach((p: CallaitePlugin) => { result.push(p); });
    return result;
  }

  /**
   * 检查插件是否启用。
   */
  isEnabled(pluginId: string): boolean {
    return this.enabledPlugins.has(pluginId);
  }

  // ─── 持久化 ───

  private loadState(): void {
    try {
      if (fs.accessSync(this.CONFIG_PATH)) {
        const raw = fs.readTextSync(this.CONFIG_PATH);
        const state: PluginState = JSON.parse(raw) as PluginState;
        if (state.enabled) {
          for (let i = 0; i < state.enabled.length; i++) {
            this.enabledPlugins.add(state.enabled[i]);
          }
        }
        // 修复：加载显式禁用列表
        if (state.disabled) {
          for (let i = 0; i < state.disabled.length; i++) {
            this.disabledPlugins.add(state.disabled[i]);
          }
        }
      }
    } catch (_e) { /* 首次启动 */ }
  }

  private saveState(): void {
    try {
      const enabled: string[] = [];
      this.enabledPlugins.forEach((id: string) => { enabled.push(id); });
      const disabled: string[] = [];
      this.disabledPlugins.forEach((id: string) => { disabled.push(id); });
      const state: PluginState = { enabled: enabled, disabled: disabled };
      const json = JSON.stringify(state);
      const file = fs.openSync(this.CONFIG_PATH, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, json);
      fs.closeSync(file);
    } catch (e) {
      console.error('[PluginManager] Failed to save state', e);
    }
  }

}

interface PluginState {
  enabled: string[];
  disabled?: string[];
}
