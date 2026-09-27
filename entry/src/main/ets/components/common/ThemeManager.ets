import { ConfigurationConstant } from '@kit.AbilityKit';
import { FileService } from '../../services/FileService';
import { SystemBarHelper } from '../../utils/SystemBarHelper';
import { StatePersistence } from '../../state/StatePersistence';

export enum ThemeMode {
  LIGHT = 'light',
  DARK = 'dark',
  SYSTEM = 'system'
}

const THEME_MODE_KEY = 'callaite_themeMode';
const SYSTEM_COLOR_MODE_KEY = 'callaite_systemColorMode';

export class ThemeManager {
  static initDefault(): void {
    if (!AppStorage.has(THEME_MODE_KEY)) {
      AppStorage.setOrCreate(THEME_MODE_KEY, ThemeMode.SYSTEM);
    }
    if (!AppStorage.has(SYSTEM_COLOR_MODE_KEY)) {
      AppStorage.setOrCreate(SYSTEM_COLOR_MODE_KEY, ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    }
  }

  static getThemeMode(): ThemeMode {
    const mode = AppStorage.get<string>(THEME_MODE_KEY);
    if (mode !== undefined) {
      if (mode === 'light' || mode === 'dark' || mode === 'system') {
        return mode as ThemeMode;
      }
    }
    return ThemeMode.SYSTEM;
  }

  /**
   * 将当前持久化的主题应用到系统资源限定符。
   * 必须在 EntryAbility.onCreate（页面加载前）调用，且 setThemeMode 时同步调用，
   * 否则 resources/dark/ 目录永远不会生效（切换主题无任何视觉变化）。
   */
  static applyPersistedTheme(): void {
    ThemeManager.applyColorMode(ThemeManager.getThemeMode());
  }

  private static applyColorMode(mode: ThemeMode): void {
    const ctx = FileService.getContext();
    if (!ctx) {
      return;
    }
    const appCtx = ctx.getApplicationContext();
    let target = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === ThemeMode.DARK) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    } else if (mode === ThemeMode.LIGHT) {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    try {
      appCtx.setColorMode(target);
    } catch (e) {
      console.warn('[ThemeManager] Failed to set color mode', e);
    }
  }

  static setThemeMode(mode: ThemeMode): void {
    AppStorage.setOrCreate(THEME_MODE_KEY, mode);
    ThemeManager.applyColorMode(mode);
    StatePersistence.save();
    // 主题切换后实时刷新系统栏内容色（浅色页深字 / 深色页浅字）
    SystemBarHelper.apply(ThemeManager.isDarkMode());
  }

  static toggleTheme(): void {
    const current = ThemeManager.getThemeMode();
    if (current === ThemeMode.DARK) {
      ThemeManager.setThemeMode(ThemeMode.LIGHT);
    } else {
      ThemeManager.setThemeMode(ThemeMode.DARK);
    }
  }

  static isDarkMode(): boolean {
    const mode = ThemeManager.getThemeMode();
    if (mode === ThemeMode.SYSTEM) {
      const systemColorMode = AppStorage.get<number>(SYSTEM_COLOR_MODE_KEY);
      return systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    return mode === ThemeMode.DARK;
  }

  static onSystemColorModeChanged(colorMode: ConfigurationConstant.ColorMode): void {
    AppStorage.setOrCreate(SYSTEM_COLOR_MODE_KEY, colorMode);
  }
}

export interface ThemeColors {
  primary: ResourceColor;
  bg: ResourceColor;
  text: ResourceColor;
  surface0: ResourceColor;
  surface1: ResourceColor;
  surface2: ResourceColor;
  bullet: ResourceColor;
  link: ResourceColor;
  highlight: ResourceColor;
  searchHighlight: ResourceColor;
  border: ResourceColor;
  toolbar: ResourceColor;
  mutedText: ResourceColor;
  danger: ResourceColor;
  success: ResourceColor;
}

/**
 * CanvasColors —— 供 CanvasRenderingContext2D 使用的**原始色值**调色板。
 *
 * 为什么必须单独存在：
 *   `ctx.fillStyle` / `ctx.strokeStyle` 的类型是
 *   `string | number | CanvasGradient | CanvasPattern`，**不接受 Resource**。
 *   因此 Canvas 绘制代码无法直接写 `$r('app.color.graph_edge')`。
 *
 * 取值依据（沿用项目既有模式，非自创）：
 *   项目内三处「需要按主题选色、但拿不到 Resource」的代码都采用
 *   「ThemeManager.isDarkMode() 判主题 + 明暗两个字面量」：
 *     · components/extensions/CodeBlock.ets:54-57
 *     · components/extensions/MermaidRenderer.ets:23-26
 *     · utils/SystemBarHelper.ets:34
 *   这里沿用同一模式，只是把字面量**集中到一处**，避免散落在各 Canvas 文件里。
 *
 * ⚠️ 已知维护风险（见 U3.3 交付说明⑥）：
 *   下列 hex 与 `resources/base/element/color.json` + `resources/dark/element/color.json`
 *   中的同名 token 是**镜像关系**，必须同步修改。每个字段的注释标出了对应 token 名。
 */
export interface CanvasColors {
  /** app.color.graph_edge —— 图谱连线 */
  graphEdge: string;
  /** app.color.graph_node —— 图谱普通节点填充 */
  graphNode: string;
  /** app.color.primary —— 图谱当前页节点填充（与主色保持一致） */
  graphNodeCurrent: string;
  /** app.color.graph_node_ring —— 图谱节点描边环（暗色取画布底色，形成"间隙"效果） */
  graphNodeRing: string;
  /** app.color.graph_label —— 图谱节点标签文字 */
  graphLabel: string;
  /** app.color.canvas_grid —— Canvas 画布网格线（白板 / 手绘） */
  canvasGrid: string;
}

/**
 * 取当前主题下 Canvas 可用的原始色值。
 * 每次绘制时调用即可拿到最新值（isDarkMode 读 AppStorage，切换主题后即变）。
 */
export function getCanvasColors(): CanvasColors {
  const dark: boolean = ThemeManager.isDarkMode();
  const colors: CanvasColors = {
    graphEdge: dark ? '#333333' : '#D1D5DB',
    graphNode: dark ? '#8B949E' : '#4B5563',
    graphNodeCurrent: dark ? '#A88BFA' : '#705DCF',
    graphNodeRing: dark ? '#161616' : '#FFFFFF',
    graphLabel: dark ? '#DADADA' : '#1A1A1A',
    canvasGrid: dark ? '#2E2E2E' : '#E8E9EA'
  };
  return colors;
}

export function getThemeColors(): ThemeColors {
  const colors: ThemeColors = {
    primary: $r('app.color.primary'),
    bg: $r('app.color.bg'),
    text: $r('app.color.text'),
    surface0: $r('app.color.surface0'),
    surface1: $r('app.color.surface1'),
    surface2: $r('app.color.surface2'),
    bullet: $r('app.color.bullet'),
    link: $r('app.color.link'),
    highlight: $r('app.color.highlight'),
    searchHighlight: $r('app.color.search_highlight'),
    border: $r('app.color.border'),
    toolbar: $r('app.color.toolbar'),
    mutedText: $r('app.color.muted_text'),
    danger: $r('app.color.danger'),
    success: $r('app.color.success')
  };
  return colors;
}
