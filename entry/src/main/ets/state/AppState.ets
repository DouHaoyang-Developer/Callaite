import { SupportedLanguage, I18n } from '../utils/i18n';
import { ThemeManager, ThemeMode } from '../components/common/ThemeManager';
import { DirtyPageTracker } from '../services/DirtyPageTracker';
import { display } from '@kit.ArkUI';

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

/**
 * 用字面量键序列化配置。
 * 注意：不能用 JSON.stringify(config) —— release 属性混淆会把字段名重命名，
 * 导致持久化的配置在跨版本/跨启动时无法解析。字面量键不受混淆影响。
 */
function serializeConfig(c: AppConfig): string {
  let s = '{"preferredLanguage":"' + c.preferredLanguage + '"';
  s += ',"themeMode":"' + c.themeMode + '"';
  s += ',"leftSidebarOpen":' + (c.leftSidebarOpen ? 'true' : 'false');
  s += ',"rightSidebarOpen":' + (c.rightSidebarOpen ? 'true' : 'false');
  s += ',"showBullets":' + (c.showBullets ? 'true' : 'false');
  s += ',"enableShortcuts":' + (c.enableShortcuts ? 'true' : 'false') + '}';
  return s;
}

/**
 * 用字面量键解析配置（与 serializeConfig 对应，混淆安全）。
 */
function parseConfig(raw: string): AppConfigPartial {
  const part: AppConfigPartial = {};
  try {
    const o = JSON.parse(raw) as Record<string, Object>;
    const pl = o['preferredLanguage'];
    if (typeof pl === 'string' && (pl === 'zh-CN' || pl === 'en-US')) {
      part.preferredLanguage = pl as SupportedLanguage;
    }
    const tm = o['themeMode'];
    if (typeof tm === 'string' && (tm === 'light' || tm === 'dark' || tm === 'system')) {
      part.themeMode = tm as ThemeMode;
    }
    const lo = o['leftSidebarOpen'];
    if (typeof lo === 'boolean') {
      part.leftSidebarOpen = lo;
    }
    const ro = o['rightSidebarOpen'];
    if (typeof ro === 'boolean') {
      part.rightSidebarOpen = ro;
    }
    const sb = o['showBullets'];
    if (typeof sb === 'boolean') {
      part.showBullets = sb;
    }
    const es = o['enableShortcuts'];
    if (typeof es === 'boolean') {
      part.enableShortcuts = es;
    }
  } catch (_e) {
    // 解析失败返回空 partial（全默认）
  }
  return part;
}

export class AppState {
  static initialize(): void {
    ThemeManager.initDefault();
    I18n.initDefault();

    if (!AppStorage.has(STORAGE_KEYS.config)) {
      AppStorage.setOrCreate(STORAGE_KEYS.config, serializeConfig(DEFAULT_CONFIG));
    }

    const storedConfig = AppStorage.get<string>(STORAGE_KEYS.config);
    let config = DEFAULT_CONFIG;
    if (storedConfig) {
      const parsed: AppConfigPartial = parseConfig(storedConfig);
      config = mergeConfig(DEFAULT_CONFIG, parsed);
    }

    AppStorage.setOrCreate(STORAGE_KEYS.config, serializeConfig(config));
    AppStorage.setOrCreate('language', config.preferredLanguage);
    AppStorage.setOrCreate('themeMode', config.themeMode);

    // 启动行为调整：不再恢复上次页面/直接加载大纲，统一进入首页（Obsidian 新标签页式）。
    // 上次页面键仍持久化（供历史栈等使用），但启动初始页固定为 Home。
    AppStorage.setOrCreate(STORAGE_KEYS.currentPage, 'Home');

    const storedLeft = AppStorage.get<boolean>(STORAGE_KEYS.leftSidebarOpen);
    let leftDefault = storedLeft ?? config.leftSidebarOpen;
    // 窄屏（手机）首次进入不自动弹出抽屉，避免遮挡主内容；用户可点菜单按钮打开。
    // 必须在页面挂载前设置（EntryAbility 在 loadContent 前调用 initialize），
    // 否则与 bindSheet 初始绑定产生框架竞态导致抽屉打开后立即关闭。
    try {
      const disp = display.getDefaultDisplaySync();
      // 手机与折叠屏/小平板（<840vp）首次进入不自动展开侧栏，
      // 为内容区留出足够宽度（对齐 Obsidian 窄窗口行为）；宽屏默认展开。
      if (disp.width / disp.densityPixels < 840) {
        leftDefault = false;
      }
    } catch (_e) {
      // 取不到显示信息时保持默认值
    }
    AppStorage.setOrCreate(STORAGE_KEYS.leftSidebarOpen, leftDefault);

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
    // 移动端浮层（Obsidian iOS：标签总览 / 更多菜单）
    AppStorage.setOrCreate('callaite_tabOverviewOpen', false);
    AppStorage.setOrCreate('callaite_mobileMenuOpen', false);

    // 历史栈初始化
    const initHistory: HistoryStack = { pages: [AppStorage.get<string>(STORAGE_KEYS.currentPage) ?? 'Home'], current: 0 };
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
    const parsed: AppConfigPartial = parseConfig(raw);
    return mergeConfig(DEFAULT_CONFIG, parsed);
  }

  static setConfig(config: AppConfigPartial): void {
    const current = AppState.getConfig();
    const merged = mergeConfig(current, config);
    AppStorage.setOrCreate(STORAGE_KEYS.config, serializeConfig(merged));
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
    return AppStorage.get<string>(STORAGE_KEYS.currentPage) ?? 'Home';
  }

  static setCurrentPage(pageName: string): void {
    // 事件驱动 flush 点 ②-a：切换页面。
    // 必须在改写路由键**之前**把「已标脏未落盘」的页面写下去 —— 页面切换会重建
    // 编辑器（旧编辑器的 DOM 随之销毁，其 blur 不保证还会触发一次），
    // 也意味着用户已经离开这一页，延迟落盘再无收益。
    // 无脏页时 flushNow() 是零开销的空操作，不会被启动期的重复调用放大。
    DirtyPageTracker.getInstance().flushNow();
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
      // 事件驱动 flush 点 ②-a（同 setCurrentPage）：后退也是切换页面，
      // 且这里**绕过** setCurrentPage 直接写路由键，故必须单独挂一次。
      DirtyPageTracker.getInstance().flushNow();
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
      // 事件驱动 flush 点 ②-a（同 setCurrentPage）：前进同样绕过 setCurrentPage。
      DirtyPageTracker.getInstance().flushNow();
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
    // 内部路由页（设置/图谱等伪页面）不记入最近列表
    if (AppState.isInternalRoute(pageName)) {
      return;
    }
    const list = AppState.getRecentPages();
    const deduped: string[] = [];
    deduped[0] = pageName;
    for (let i = 0; i < list.length; i++) {
      if (list[i] !== pageName && !AppState.isInternalRoute(list[i])) {
        deduped[deduped.length] = list[i];
      }
    }
    AppState.setRecentPages(deduped);
  }

  /**
   * 判断是否为内部路由键（非真实笔记页面）。
   */
  static isInternalRoute(pageName: string): boolean {
    return pageName === 'Journal' || pageName === 'Settings' || pageName === 'Graph' ||
      pageName === 'Whiteboards' || pageName === 'Flashcards' || pageName === 'Pdf' ||
      pageName === 'ProUpgrade' || pageName === 'AllPages' || pageName === 'Recycle' ||
      pageName === 'About';
  }

  // ─── Overlays ───
  static isCommandPaletteOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.commandPaletteOpen) ?? false;
  }

  /**
   * 命令面板 / 快速切换（CommandPalette，Ctrl+K）。
   * U1.6：与全局搜索面板**互斥** —— 两块浮层同时打开会叠成两层模态并争抢键盘焦点。
   */
  static setCommandPaletteOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.commandPaletteOpen, open);
    if (open) {
      AppStorage.setOrCreate(STORAGE_KEYS.searchPanelOpen, false);
    }
  }

  static isSearchPanelOpen(): boolean {
    return AppStorage.get<boolean>(STORAGE_KEYS.searchPanelOpen) ?? false;
  }

  /**
   * 全局搜索面板（SearchPanel，Ctrl+F）。
   * U1.6：开面板时顺手关掉命令面板（互斥理由同上）。
   */
  static setSearchPanelOpen(open: boolean): void {
    AppStorage.setOrCreate(STORAGE_KEYS.searchPanelOpen, open);
    if (open) {
      AppStorage.setOrCreate(STORAGE_KEYS.commandPaletteOpen, false);
    }
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

  // ─── Block 定位高亮（U2.1a） ───

  /**
   * 当前被「定位跳转」高亮的块 uuid（空串表示无）。
   * 由 BlockAnchorService.flash() 写入，BlockView 通过 @StorageLink 接收后闪烁高亮。
   */
  static getHighlightedBlock(): string {
    return AppStorage.get<string>('callaite_highlightedBlock') ?? '';
  }

  /**
   * 高亮触发序号。
   * 仅靠 uuid 无法让「连续点同一个块」再次闪烁（值未变 → @Watch 不触发），
   * 故 BlockView 以本序号为 watch 源。
   */
  static getHighlightSeq(): number {
    return AppStorage.get<number>('callaite_highlightSeq') ?? 0;
  }

  /** 设置/清除高亮块（清除时传空串；清除不递增序号，避免误触发闪烁）。 */
  static setHighlightedBlock(blockUuid: string): void {
    AppStorage.setOrCreate('callaite_highlightedBlock', blockUuid);
  }

  /**
   * 触发一次高亮闪烁：设置目标块并递增序号。
   * BlockAnchorService.flash() 内部即调用本方法（保持单一写入口）。
   */
  static triggerHighlight(blockUuid: string): void {
    const seq = AppStorage.get<number>('callaite_highlightSeq') ?? 0;
    AppStorage.setOrCreate('callaite_highlightedBlock', blockUuid);
    AppStorage.setOrCreate('callaite_highlightSeq', seq + 1);
  }
}
