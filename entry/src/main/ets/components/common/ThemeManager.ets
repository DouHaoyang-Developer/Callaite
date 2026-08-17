import { ConfigurationConstant } from '@kit.AbilityKit';
import { FileService } from '../../services/FileService';
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
