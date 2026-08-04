/**
 * LuniusPlugin — 插件抽象基类。
 *
 * 所有插件必须继承此类并实现 getManifest()。
 * 插件通过 PluginManager 注册，在应用启动时自动发现。
 *
 * ArkTS 兼容方案: 插件代码预编译为 ArkTS 模块，
 * PluginManager 通过静态注册表发现，无需动态加载。
 */
export abstract class LuniusPlugin {
  /** 插件唯一 ID（kebab-case） */
  abstract get id(): string;

  /** 显示名称 */
  abstract get name(): string;

  /** 版本号 */
  abstract get version(): string;

  /** 描述 */
  abstract get description(): string;

  /** 是否默认启用 */
  get enabledByDefault(): boolean {
    return true;
  }

  /**
   * 插件加载时调用（注册后首次启用）。
   * 可用于初始化资源、注册快捷键等。
   */
  onLoad(): void {
    // 子类可重写
  }

  /**
   * 插件卸载时调用。
   * 可用于清理资源。
   */
  onUnload(): void {
    // 子类可重写
  }

  /**
   * 插件启用时调用。
   * 与 onLoad 的区别：每次从禁用→启用切换时都会调用。
   */
  onEnable(): void {
    // 子类可重写
  }

  /**
   * 插件禁用时调用。
   */
  onDisable(): void {
    // 子类可重写
  }
}
