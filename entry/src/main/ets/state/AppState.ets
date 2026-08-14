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
  exportDialogOpen: string;
  importDialogOpen: string;
  rightSidebarBlocks: string;
}

const STORAGE_KEYS: StorageKeys = {
  config: 'callaite_config',
  currentPage: 'callaite_currentPage',
  leftSidebarOpen: 'callaite_leftSidebarOpen',
  rightSidebarOpen: 'callaite_rightSidebarOpen',
  favorites: 'callaite_favorites',
  recentPages: 'callaite_recentPages',
  commandPaletteOpen: 'callaite_commandPaletteOpen',
  searchPanelOpen: 'callaite_searchPanelOpen',
  exportDialogOpen: 'callaite_exportDialogOpen',
  importDialogOpen: 'callaite_importDialogOpen',
  rightSidebarBlocks: 'callaite_rightSidebarBlocks'
};

/**
 * 右侧栏块条目类型 — 对应 logseq 的 sidebar item。
 */
export interface RightSidebarBlock {
  id: string;          // 唯一 id
  type: 'page' | 'backlinks' | 'outline' | 'properties' | 'help';
  title: string;       // 显示标题
  pageName: string;    // 关联页面名（用于刷新内容）
  collapsed: boolean;  // 是否折叠
}

/**
 * 历史栈结构 — 用于 Header 前进/后退。
 */
interface HistoryStack {
  pages: string[];
  current: number;     // 当前位置索引
}

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
    AppStorage.setOrCreate(STORAGE_KEYS.exportDialogOpen, false);
    AppStorage.setOrCreate(STORAGE_KEYS.importDialogOpen, false);
    AppStorage.setOrCreate(STORAGE_KEYS.rightSidebarBlocks, JSON.stringify([]));

    // 历史栈初始化
    const initHistory: HistoryStack = { pages: [AppStorage.get<string>(STORAGE_KEYS.currentPage) ?? 'Journal'], current: 0 };
    AppStorage.setOrCreate('callaite_historyStack', JSON.stringify(initHistory));
    // 历史栈触发器初始化（驱动 Header 前进/后退按钮状态）
    AppStorage.setOrCreate('callaite_historyBack', 0);
    AppStorage.setOrCreate('callaite_historyForward', 0);
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
    const prev = AppStorage.get<string>(STORAGE_KEYS.currentPage);
    AppStorage.setOrCreate(STORAGE_KEYS.currentPage, pageName);
    AppState.addRecentPage(pageName);
    // 记录历史（仅当与上一次不同时）
    if (prev !== pageName) {
      AppState.pushHistory(pageName);
    }
  }

  // ─── History Navigation ───
  private static pushHistory(pageName: string): void {
    const raw = AppStorage.get<string>('callaite_historyStack');
    let stack: HistoryStack = { pages: [pageName], current: 0 };
    if (raw) {
      try {
        const parsed = JSON.parse(raw) as HistoryStack;
        if (parsed && parsed.pages && typeof parsed.current === 'number') {
          stack = parsed;
        }
      } catch (e) {
        // 使用默认 stack
      }
    }
    // 截断当前位置之后的历史
    const newPages: string[] = [];
    for (let i = 0; i <= stack.current && i < stack.pages.length; i++) {
      newPages.push(stack.pages[i]);
    }
    // 避免连续重复
    if (newPages.length === 0 || newPages[newPages.length - 1] !== pageName) {
      newPages.push(pageName);
    }
    const newStack: HistoryStack = { pages: newPages, current: newPages.length - 1 };
    AppStorage.setOrCreate('callaite_historyStack', JSON.stringify(newStack));
    // 修复：通知 Header 刷新前进/后退按钮启用状态
    AppStorage.setOrCreate('callaite_historyBack', Date.now());
    AppStorage.setOrCreate('callaite_historyForward', Date.now());
  }

  static canGoBack(): boolean {
    const raw = AppStorage.get<string>('callaite_historyStack');
    if (!raw) return false;
    try {
      const stack = JSON.parse(raw) as HistoryStack;
      return stack && stack.current > 0;
    } catch (e) {
      return false;
    }
  }

  static canGoForward(): boolean {
    const raw = AppStorage.get<string>('callaite_historyStack');
    if (!raw) return false;
    try {
      const stack = JSON.parse(raw) as HistoryStack;
      return stack && stack.current < stack.pages.length - 1;
    } catch (e) {
      return false;
    }
  }

  static goBack(): void {
    if (!AppState.canGoBack()) return;
    const raw = AppStorage.get<string>('callaite_historyStack');
    if (!raw) return;
    try {
      const stack = JSON.parse(raw) as HistoryStack;
      const newCurrent = stack.current - 1;
      const newStack: HistoryStack = { pages: stack.pages, current: newCurrent };
      AppStorage.setOrCreate('callaite_historyStack', JSON.stringify(newStack));
      // 直接设置 currentPage，不触发 pushHistory
      AppStorage.setOrCreate(STORAGE_KEYS.currentPage, stack.pages[newCurrent]);
      AppStorage.setOrCreate('callaite_historyBack', Date.now());
    } catch (e) {
      // 忽略
    }
  }

  static goForward(): void {
    if (!AppState.canGoForward()) return;
    const raw = AppStorage.get<string>('callaite_historyStack');
    if (!raw) return;
    try {
      const stack = JSON.parse(raw) as HistoryStack;
      const newCurrent = stack.current + 1;
      const newStack: HistoryStack = { pages: stack.pages, current: newCurrent };
      AppStorage.setOrCreate('callaite_historyStack', JSON.stringify(newStack));
      AppStorage.setOrCreate(STORAGE_KEYS.currentPage, stack.pages[newCurrent]);
      AppStorage.setOrCreate('callaite_historyForward', Date.now());
    } catch (e) {
      // 忽略
    }
  }

  // ─── Right Sidebar Blocks (logseq-style 多块堆叠) ───
  static getRightSidebarBlocks(): RightSidebarBlock[] {
    const raw = AppStorage.get<string>(STORAGE_KEYS.rightSidebarBlocks);
    if (!raw) return [];
    try {
      return JSON.parse(raw) as RightSidebarBlock[];
    } catch (e) {
      return [];
    }
  }

  static setRightSidebarBlocks(blocks: RightSidebarBlock[]): void {
    AppStorage.setOrCreate(STORAGE_KEYS.rightSidebarBlocks, JSON.stringify(blocks));
    AppStorage.setOrCreate('callaite_rightSidebarBlocksVersion', Date.now());
  }

  static addRightSidebarBlock(block: RightSidebarBlock): void {
    const list = AppState.getRightSidebarBlocks();
    // 去重（同 type + 同 pageName 不重复添加）
    for (let i = 0; i < list.length; i++) {
      if (list[i].type === block.type && list[i].pageName === block.pageName) {
        // 已存在，置顶并展开
        const newList: RightSidebarBlock[] = [];
        newList[0] = { id: list[i].id, type: list[i].type, title: list[i].title, pageName: list[i].pageName, collapsed: false };
        for (let j = 0; j < list.length; j++) {
          if (j !== i) newList.push(list[j]);
        }
        AppState.setRightSidebarBlocks(newList);
        return;
      }
    }
    const newList: RightSidebarBlock[] = [];
    newList[0] = block;
    for (let i = 0; i < list.length; i++) newList.push(list[i]);
    AppState.setRightSidebarBlocks(newList);
  }

  static removeRightSidebarBlock(id: string): void {
    const list = AppState.getRightSidebarBlocks();
    const newList: RightSidebarBlock[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id !== id) newList.push(list[i]);
    }
    AppState.setRightSidebarBlocks(newList);
  }

  static toggleRightSidebarBlockCollapsed(id: string): void {
    const list = AppState.getRightSidebarBlocks();
    const newList: RightSidebarBlock[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        newList.push({
          id: list[i].id, type: list[i].type, title: list[i].title,
          pageName: list[i].pageName, collapsed: !list[i].collapsed
        });
      } else {
        newList.push(list[i]);
      }
    }
    AppState.setRightSidebarBlocks(newList);
  }

  static clearRightSidebarBlocks(): void {
    AppState.setRightSidebarBlocks([]);
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

  static isExportDialogOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.exportDialogOpen) ?? false;
  }

  static setExportDialogOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.exportDialogOpen, open);
  }

  static isImportDialogOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.importDialogOpen) ?? false;
  }

  static setImportDialogOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.importDialogOpen, open);
  }

  // ─── Blocks Version（用于触发 BlockList 刷新） ───

  /**
   * 递增 blocksVersion，触发所有监听该值的组件（如 BlockList）刷新。
   * 用于 Block 折叠/缩进/移动/删除等操作后通知 UI 更新。
   */
  static bumpBlocksVersion(): void {
    const current = AppStorage.get<number>('callaite_blocksVersion') ?? 0;
    AppStorage.setOrCreate('callaite_blocksVersion', current + 1);
  }

  static getBlocksVersion(): number {
    return AppStorage.get<number>('callaite_blocksVersion') ?? 0;
  }
}
