import { display } from '@kit.ArkUI';

/**
 * 断点系统 — 遵循 HarmonyOS 一多开发规范（sm < 600vp ≤ md < 840vp ≤ lg）。
 *
 * 同一份代码在三类设备上呈现不同形态：
 *   - compact（手机，<600vp）：Obsidian iOS 式悬浮玻璃按钮 + 抽屉侧栏 + 底部胶囊栏
 *   - medium（折叠屏展开/小平板，600–840）：桌面布局，侧栏默认收起
 *   - expanded（平板/2in1/PC，>840）：完整 Obsidian 桌面布局（Ribbon + 侧栏 + 标签页 + 状态栏）
 */
export class Breakpoints {
  static readonly SM_MAX = 600;
  static readonly MD_MAX = 840;

  /**
   * 当前视口宽度（vp）。
   */
  static viewportWidth(): number {
    try {
      const d = display.getDefaultDisplaySync();
      return d.width / d.densityPixels;
    } catch (_e) {
      return 800;
    }
  }

  /**
   * 手机形态（compact）— 使用移动端悬浮 UI。
   */
  static isCompact(): boolean {
    return Breakpoints.viewportWidth() < Breakpoints.SM_MAX;
  }

  /**
   * 中等形态 — 桌面布局但侧栏默认收起。
   */
  static isMedium(): boolean {
    const w = Breakpoints.viewportWidth();
    return w >= Breakpoints.SM_MAX && w < Breakpoints.MD_MAX;
  }

  /**
   * 完整桌面形态。
   */
  static isExpanded(): boolean {
    return Breakpoints.viewportWidth() >= Breakpoints.MD_MAX;
  }

  /**
   * 是否显示桌面布局（medium + expanded）。
   */
  static isDesktop(): boolean {
    return !Breakpoints.isCompact();
  }
}
