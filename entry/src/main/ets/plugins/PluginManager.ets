import { CallaitePlugin } from './CallaitePlugin';
import { PluginAPI } from './PluginAPI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../services/FileService';
import { PreferencesStore } from '../utils/PreferencesStore';

const DOMAIN = 0x0001;
const TAG = 'PluginManager';

/** 本持久化线专用的 preferences 实例名（含模块名，稳定性要求：改名即丢数据） */
const PLUGIN_STORE_NAME = 'callaite_plugin_state';
/** preferences 键：两个键的值必须**始终**是 string[]（getSync 在类型不匹配时会回落到 defValue） */
const KEY_ENABLED = 'enabled';
const KEY_DISABLED = 'disabled';
/**
 * 旧版自研持久化文件（仅用于一次性迁移，迁移后删除）。
 *
 * 原实现把路径**硬编码**为 '/data/storage/el2/base/files/plugin_state.json'，
 * 绕过了 context.filesDir：沙箱路径或用户空间（el1/el2）变化时会写错位置甚至写入失败。
 * 迁移时两个候选路径都尝试：优先 filesDir 推导值（即硬编码路径在正常设备上的实际位置），
 * 再兜底原来的硬编码值，保证旧数据一定被读到。
 */
const LEGACY_CONFIG_FILE = 'plugin_state.json';
const LEGACY_ABS_CONFIG_PATH = '/data/storage/el2/base/files/plugin_state.json';

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
    if (!this.loadState()) {
      // 读取失败不中断启动：退回「按插件默认值启用」策略，但必须留下错误痕迹
      hilog.error(DOMAIN, TAG, '%{public}s',
        'loadState 失败，本次启动按插件默认启用策略（enabledByDefault）继续');
    }
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
      if (!this.saveState()) {
        hilog.error(DOMAIN, TAG, '%{public}s',
          'enable(' + pluginId + ') 已生效但状态未持久化，重启后不会保持');
      }
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
      if (!this.saveState()) {
        hilog.error(DOMAIN, TAG, '%{public}s',
          'disable(' + pluginId + ') 已生效但状态未持久化，重启后不会保持');
      }
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

  // ─── 持久化（系统 preferences，实例名 callaite_plugin_state） ───

  /**
   * 恢复插件启用/禁用状态。
   *
   * 首次运行（preferences 中两个键都不存在）且旧的 plugin_state.json 仍存在时，
   * 一次性把旧文件内容迁入 preferences 并删除旧文件。
   *
   * @returns true 表示读取流程正常结束；false 表示 context 缺失或读写失败（已 hilog.error）。
   */
  private loadState(): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'loadState: context 未就绪，插件状态无法恢复');
      return false;
    }
    let store: preferences.Preferences;
    try {
      store = PreferencesStore.open(ctx, PLUGIN_STORE_NAME);
    } catch (e) {
      PreferencesStore.logError(PLUGIN_STORE_NAME, 'getPreferencesSync', e as Object);
      return false;
    }
    try {
      // ─── 一次性迁移 ───
      // 触发条件：两个键都不存在（= 从未用 preferences 写过本线数据）且旧 JSON 文件存在。
      if (!store.hasSync(KEY_ENABLED) && !store.hasSync(KEY_DISABLED)) {
        PluginManager.migrateLegacyState(store, ctx);
      }
      const emptyList: string[] = [];
      const enabled: string[] = store.getSync(KEY_ENABLED, emptyList) as string[];
      const disabled: string[] = store.getSync(KEY_DISABLED, emptyList) as string[];
      for (let i = 0; i < enabled.length; i++) {
        this.enabledPlugins.add(enabled[i]);
      }
      for (let i = 0; i < disabled.length; i++) {
        this.disabledPlugins.add(disabled[i]);
      }
      return true;
    } catch (e) {
      PreferencesStore.logError(PLUGIN_STORE_NAME, 'loadState', e as Object);
      return false;
    }
  }

  /**
   * 一次性迁移：读旧的 plugin_state.json 写入 preferences，随后删除旧文件。
   *
   * 两个候选路径都尝试（filesDir 推导值优先，其次原硬编码绝对路径）；
   * 只要是存在的旧文件，无论有没有被当作迁移源，迁移结束后都会被清理。
   */
  private static migrateLegacyState(store: preferences.Preferences, ctx: Context): void {
    const candidates: string[] = [];
    candidates.push(ctx.filesDir + '/' + LEGACY_CONFIG_FILE);
    candidates.push(LEGACY_ABS_CONFIG_PATH);
    let migrated = false;
    for (let i = 0; i < candidates.length; i++) {
      const path = candidates[i];
      let exists = false;
      try {
        exists = fs.accessSync(path);
      } catch (e) {
        PreferencesStore.logError(PLUGIN_STORE_NAME, 'accessSync(legacy) ' + path, e as Object);
        continue;
      }
      if (!exists) {
        continue;
      }
      if (!migrated) {
        try {
          const raw = fs.readTextSync(path).trim();
          if (raw !== '') {
            const state = JSON.parse(raw) as PluginState;
            const enabled: string[] = state.enabled !== undefined ? state.enabled : [];
            const disabled: string[] = state.disabled !== undefined ? state.disabled : [];
            store.putSync(KEY_ENABLED, enabled);
            store.putSync(KEY_DISABLED, disabled);
            store.flushSync();
          }
          migrated = true;
          PreferencesStore.logInfo(PLUGIN_STORE_NAME, 'migrated legacy state from ' + path);
        } catch (e) {
          PreferencesStore.logError(PLUGIN_STORE_NAME, 'migrate legacy state ' + path, e as Object);
        }
      }
      // 旧文件不再是真相来源：清理掉（失败仅记录）
      try {
        fs.unlinkSync(path);
        PreferencesStore.logInfo(PLUGIN_STORE_NAME, 'removed legacy file ' + path);
      } catch (e) {
        PreferencesStore.logError(PLUGIN_STORE_NAME, 'unlink(legacy) ' + path, e as Object);
      }
    }
  }

  /**
   * 写入插件启用/禁用状态。
   * @returns true 表示已 flush 落盘；false 表示失败（已 hilog.error）。
   */
  private saveState(): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'saveState: context 未就绪，插件状态未持久化');
      return false;
    }
    try {
      const store: preferences.Preferences = PreferencesStore.open(ctx, PLUGIN_STORE_NAME);
      const enabled: string[] = [];
      this.enabledPlugins.forEach((id: string) => { enabled.push(id); });
      const disabled: string[] = [];
      this.disabledPlugins.forEach((id: string) => { disabled.push(id); });
      store.putSync(KEY_ENABLED, enabled);
      store.putSync(KEY_DISABLED, disabled);
      // XML 存储（默认）必须 flush 才真正落盘
      store.flushSync();
      return true;
    } catch (e) {
      PreferencesStore.logError(PLUGIN_STORE_NAME, 'saveState', e as Object);
      return false;
    }
  }

}

interface PluginState {
  enabled?: string[];
  disabled?: string[];
}
