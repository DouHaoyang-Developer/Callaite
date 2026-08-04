import { LuniusPlugin } from './LuniusPlugin';
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
  private plugins: Map<string, LuniusPlugin> = new Map<string, LuniusPlugin>();
  private enabledPlugins: Set<string> = new Set<string>();
  private registry: LuniusPlugin[] = [];

  private readonly CONFIG_PATH = '/data/storage/el2/base/files/plugin_state.json';

  static getInstance(): PluginManager {
    if (!PluginManager.instance) {
      PluginManager.instance = new PluginManager();
    }
    return PluginManager.instance;
  }

  register(plugin: LuniusPlugin): PluginManager {
    this.registry.push(plugin);
    return this;
  }

  initAllPlugins(): void {
    this.loadState();
    for (let i = 0; i < this.registry.length; i++) {
      const plugin = this.registry[i];
      this.plugins.set(plugin.id, plugin);
      if (this.enabledPlugins.has(plugin.id) || (plugin.enabledByDefault && !PluginManager.hasExplicit(this, plugin.id))) {
        this.enable(plugin.id);
      }
    }
    console.info('[PluginManager] Initialized ' + this.plugins.size + ' plugins');
  }

  private static hasExplicit(mgr: PluginManager, id: string): boolean {
    try {
      if (fs.accessSync(mgr.CONFIG_PATH)) {
        const raw = fs.readTextSync(mgr.CONFIG_PATH);
        const state: PluginState = JSON.parse(raw) as PluginState;
        if (state.enabled) {
          for (let i = 0; i < state.enabled.length; i++) {
            if (state.enabled[i] === id) return false;
          }
          return true;
        }
      }
    } catch (_e) {}
    return false;
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
      this.saveState();
    } catch (e) {
      console.error('[PluginManager] Failed to disable: ' + pluginId, e);
    }
  }

  /**
   * 获取所有已注册插件。
   */
  getAll(): LuniusPlugin[] {
    const result: LuniusPlugin[] = [];
    this.plugins.forEach((p: LuniusPlugin) => { result.push(p); });
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
      }
    } catch (_e) { /* 首次启动 */ }
  }

  private saveState(): void {
    try {
      const enabled: string[] = [];
      this.enabledPlugins.forEach((id: string) => { enabled.push(id); });
      const state: PluginState = { enabled: enabled };
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
}
