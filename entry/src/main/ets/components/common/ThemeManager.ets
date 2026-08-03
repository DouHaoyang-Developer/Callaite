import { ConfigurationConstant } from '@kit.AbilityKit';

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

  static setThemeMode(mode: ThemeMode): void {
    AppStorage.setOrCreate(THEME_MODE_KEY, mode);
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
