import { SupportedLanguage, I18n } from '../utils/i18n';
import { ThemeManager, ThemeMode } from '../components/common/ThemeManager';

export interface AppConfig {
  preferredLanguage: SupportedLanguage;
  themeMode: ThemeMode;
  leftSidebarOpen: boolean;
  rightSidebarOpen: boolean;
  showBullets: boolean;
  enableShortcuts: boolean;
}

export const DEFAULT_CONFIG: AppConfig = {
  preferredLanguage: 'zh-CN',
  themeMode: ThemeMode.SYSTEM,
  leftSidebarOpen: true,
  rightSidebarOpen: false,
  showBullets: true,
  enableShortcuts: true
};

interface StorageKeys {
  config: string;
  currentPage: string;
  leftSidebarOpen: string;
  rightSidebarOpen: string;
  favorites: string;
  recentPages: string;
  commandPaletteOpen: string;
  searchPanelOpen: string;
}

const STORAGE_KEYS: StorageKeys = {
  config: 'callaite_config',
  currentPage: 'callaite_currentPage',
  leftSidebarOpen: 'callaite_leftSidebarOpen',
  rightSidebarOpen: 'callaite_rightSidebarOpen',
  favorites: 'callaite_favorites',
  recentPages: 'callaite_recentPages',
  commandPaletteOpen: 'callaite_commandPaletteOpen',
  searchPanelOpen: 'callaite_searchPanelOpen'
};

/**
 * 可选的 AppConfig 字段 — 替代 Partial<AppConfig>。
 */
export interface AppConfigPartial {
  preferredLanguage?: SupportedLanguage;
  themeMode?: ThemeMode;
  leftSidebarOpen?: boolean;
  rightSidebarOpen?: boolean;
  showBullets?: boolean;
  enableShortcuts?: boolean;
}

/**
 * 手动合并：override 中的非 undefined 值覆盖 base 对应字段。
 */
function mergeConfig(base: AppConfig, override: AppConfigPartial): AppConfig {
  const result: AppConfig = {
    preferredLanguage: base.preferredLanguage,
    themeMode: base.themeMode,
    leftSidebarOpen: base.leftSidebarOpen,
    rightSidebarOpen: base.rightSidebarOpen,
    showBullets: base.showBullets,
    enableShortcuts: base.enableShortcuts
  };
  if (override.preferredLanguage !== undefined) {
    result.preferredLanguage = override.preferredLanguage;
  }
  if (override.themeMode !== undefined) {
    result.themeMode = override.themeMode;
  }
  if (override.leftSidebarOpen !== undefined) {
    result.leftSidebarOpen = override.leftSidebarOpen;
  }
  if (override.rightSidebarOpen !== undefined) {
    result.rightSidebarOpen = override.rightSidebarOpen;
  }
  if (override.showBullets !== undefined) {
    result.showBullets = override.showBullets;
  }
  if (override.enableShortcuts !== undefined) {
    result.enableShortcuts = override.enableShortcuts;
  }
  return result;
}

export class AppState {
  static initialize(): void {
    ThemeManager.initDefault();
    I18n.initDefault();

    if (!AppStorage.has(STORAGE_KEYS.config)) {
      AppStorage.setOrCreate(STORAGE_KEYS.config, JSON.stringify(DEFAULT_CONFIG));
    }

    const storedConfig = AppStorage.get<string>(STORAGE_KEYS.config);
    let config = DEFAULT_CONFIG;
    if (storedConfig) {
      try {
        const parsed: AppConfigPartial = JSON.parse(storedConfig) as AppConfigPartial;
        config = mergeConfig(DEFAULT_CONFIG, parsed);
      } catch (e) {
        console.error('[AppState] Failed to parse config', e);
      }
    }

    AppStorage.setOrCreate(STORAGE_KEYS.config, JSON.stringify(config));
    AppStorage.setOrCreate('language', config.preferredLanguage);
    AppStorage.setOrCreate('themeMode', config.themeMode);

    const storedPage = AppStorage.get<string>(STORAGE_KEYS.currentPage);
    AppStorage.setOrCreate(STORAGE_KEYS.currentPage, storedPage ?? 'Journal');

    const storedLeft = AppStorage.get<boolean>(STORAGE_KEYS.leftSidebarOpen);
    AppStorage.setOrCreate(STORAGE_KEYS.leftSidebarOpen, storedLeft ?? config.leftSidebarOpen);

    const storedRight = AppStorage.get<boolean>(STORAGE_KEYS.rightSidebarOpen);
    AppStorage.setOrCreate(STORAGE_KEYS.rightSidebarOpen, storedRight ?? config.rightSidebarOpen);

    const storedFav = AppStorage.get<string>(STORAGE_KEYS.favorites);
    AppStorage.setOrCreate(STORAGE_KEYS.favorites, storedFav ?? JSON.stringify([]));

    const storedRecent = AppStorage.get<string>(STORAGE_KEYS.recentPages);
    AppStorage.setOrCreate(STORAGE_KEYS.recentPages, storedRecent ?? JSON.stringify([]));

    AppStorage.setOrCreate(STORAGE_KEYS.commandPaletteOpen, false);
    AppStorage.setOrCreate(STORAGE_KEYS.searchPanelOpen, false);
  }

  // ─── Config ───
  static getConfig(): AppConfig {
    const raw = AppStorage.get<string>(STORAGE_KEYS.config);
    if (!raw) {
      return DEFAULT_CONFIG;
    }
    try {
      const parsed: AppConfigPartial = JSON.parse(raw) as AppConfigPartial;
      return mergeConfig(DEFAULT_CONFIG, parsed);
    } catch (e) {
      return DEFAULT_CONFIG;
    }
  }

  static setConfig(config: AppConfigPartial): void {
    const current = AppState.getConfig();
    const merged = mergeConfig(current, config);
    AppStorage.setOrCreate(STORAGE_KEYS.config, JSON.stringify(merged));
    if (config.preferredLanguage !== undefined) {
      AppStorage.setOrCreate('language', config.preferredLanguage);
      I18n.setLanguage(config.preferredLanguage);
    }
    if (config.themeMode !== undefined) {
      AppStorage.setOrCreate('themeMode', config.themeMode);
      ThemeManager.setThemeMode(config.themeMode);
    }
  }

  // ─── Current Page ───
  static getCurrentPage(): string {
    return AppStorage.get<string>(STORAGE_KEYS.currentPage) ?? 'Journal';
  }

  static setCurrentPage(pageName: string): void {
    AppStorage.setOrCreate(STORAGE_KEYS.currentPage, pageName);
    AppState.addRecentPage(pageName);
  }

  // ─── Sidebars ───
  static isLeftSidebarOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.leftSidebarOpen) ?? true;
  }

  static setLeftSidebarOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.leftSidebarOpen, open);
  }

  static toggleLeftSidebar(): void {
    AppState.setLeftSidebarOpen(!AppState.isLeftSidebarOpen());
  }

  static isRightSidebarOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.rightSidebarOpen) ?? false;
  }

  static setRightSidebarOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.rightSidebarOpen, open);
  }

  static toggleRightSidebar(): void {
    AppState.setRightSidebarOpen(!AppState.isRightSidebarOpen());
  }

  // ─── Favorites & Recent ───
  static getFavorites(): string[] {
    const raw = AppStorage.get<string>(STORAGE_KEYS.favorites);
    if (!raw) {
      return [];
    }
    try {
      return JSON.parse(raw) as string[];
    } catch (e) {
      return [];
    }
  }

  static setFavorites(pages: string[]): void {
    AppStorage.setOrCreate(STORAGE_KEYS.favorites, JSON.stringify(pages));
  }

  static addFavorite(pageName: string): void {
    const list = AppState.getFavorites();
    const alreadyExists = list.length > 0 && list[0] === pageName;
    if (alreadyExists) {
      return;
    }
    let found = false;
    for (let i = 0; i < list.length; i++) {
      if (list[i] === pageName) {
        found = true;
        break;
      }
    }
    if (!found) {
      const newList: string[] = [];
      newList[0] = pageName;
      for (let i = 0; i < list.length; i++) {
        newList[i + 1] = list[i];
      }
      AppState.setFavorites(newList);
    }
  }

  static removeFavorite(pageName: string): void {
    const list = AppState.getFavorites();
    const filtered: string[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i] !== pageName) {
        filtered[filtered.length] = list[i];
      }
    }
    AppState.setFavorites(filtered);
  }

  static getRecentPages(): string[] {
    const raw = AppStorage.get<string>(STORAGE_KEYS.recentPages);
    if (!raw) {
      return [];
    }
    try {
      return JSON.parse(raw) as string[];
    } catch (e) {
      return [];
    }
  }

  static setRecentPages(pages: string[]): void {
    const capped: string[] = [];
    const limit = pages.length < 20 ? pages.length : 20;
    for (let i = 0; i < limit; i++) {
      capped[i] = pages[i];
    }
    AppStorage.setOrCreate(STORAGE_KEYS.recentPages, JSON.stringify(capped));
  }

  static addRecentPage(pageName: string): void {
    if (pageName === 'Journal') {
      return;
    }
    const list = AppState.getRecentPages();
    const deduped: string[] = [];
    deduped[0] = pageName;
    for (let i = 0; i < list.length; i++) {
      if (list[i] !== pageName) {
        deduped[deduped.length] = list[i];
      }
    }
    AppState.setRecentPages(deduped);
  }

  // ─── Overlays ───
  static isCommandPaletteOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.commandPaletteOpen) ?? false;
  }

  static setCommandPaletteOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.commandPaletteOpen, open);
  }

  static isSearchPanelOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.searchPanelOpen) ?? false;
  }

  static setSearchPanelOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.searchPanelOpen, open);
  }
}
