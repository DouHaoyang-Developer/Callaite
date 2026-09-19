import { AppState } from './AppState';
import { pageTitle } from '../utils/PageTitle';

/**
 * TabInfo — 单个标签页（对齐 Obsidian 编辑器标签组）。
 */
export interface TabInfo {
  id: string;
  page: string;   // AppState.currentPage 路由键（'Journal' / 页面名 / 'Graph' 等内部路由）
  pinned: boolean;
}

const TABS_KEY = 'callaite_tabs';
const ACTIVE_KEY = 'callaite_activeTabId';
const VERSION_KEY = 'callaite_tabsVersion';

/**
 * TabState — Obsidian 式标签页管理。
 *
 * 设计要点（与 AppState.currentPage 单向数据流，避免循环）：
 *   - AppState.setCurrentPage() 是唯一"打开页面"入口（含历史/最近记录）。
 *   - MainContainer @Watch(currentPage) → syncToCurrentPage()：保证存在对应标签并置为激活，
 *     不回写 currentPage（无递归）。
 *   - TabBar 点击 → activateTab()：写 activeTabId + 调 AppState.setCurrentPage()
 *     （历史/最近照常记录，sync 幂等无副作用）。
 *
 * 状态持久化到 AppStorage（JSON 字面量键序列化，混淆安全）。
 */
export class TabState {
  /**
   * 初始化（EntryAbility 首次启动时调用）：至少一个 Journal 标签。
   */
  static initialize(): void {
    const existing = TabState.getTabs();
    if (existing.length === 0) {
      const home: TabInfo = { id: TabState.genId(), page: 'Journal', pinned: false };
      TabState.persist([home], home.id);
    } else {
      const active = AppStorage.get<string>(ACTIVE_KEY);
      if (active === undefined || !TabState.findById(existing, active)) {
        TabState.persist(existing, existing[0].id);
      }
    }
  }

  // ─── 读取 ───

  static getTabs(): TabInfo[] {
    const raw = AppStorage.get<string>(TABS_KEY);
    if (!raw) {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as TabInfo[];
      if (!parsed || parsed.length === 0) {
        return [];
      }
      const out: TabInfo[] = [];
      for (let i = 0; i < parsed.length; i++) {
        const t = parsed[i];
        if (typeof t.id === 'string' && typeof t.page === 'string') {
          const pinned = t.pinned === true;
          out.push({ id: t.id, page: t.page, pinned: pinned });
        }
      }
      return out;
    } catch (_e) {
      return [];
    }
  }

  static getActiveTabId(): string {
    return AppStorage.get<string>(ACTIVE_KEY) ?? '';
  }

  static getActiveTab(): TabInfo | undefined {
    return TabState.findById(TabState.getTabs(), TabState.getActiveTabId());
  }

  static findByPage(tabs: TabInfo[], page: string): TabInfo | undefined {
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].page === page) {
        return tabs[i];
      }
    }
    return undefined;
  }

  private static findById(tabs: TabInfo[], id: string): TabInfo | undefined {
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].id === id) {
        return tabs[i];
      }
    }
    return undefined;
  }

  /**
   * 标签标题：Journal → 今日日期；日志日期页 → 本地化日期；其余 → 页面名。
   */
  /**
   * 标签显示标题 —— 统一走 pageTitle()，内部路由不再以英文标识暴露。
   */
  static tabTitle(page: string): string {
    return pageTitle(page);
  }

  // ─── 操作 ───

  /**
   * currentPage 变化时同步标签（幂等，不回写 currentPage）。
   */
  static syncToCurrentPage(page: string): void {
    const tabs = TabState.getTabs();
    const activeId = TabState.getActiveTabId();
    const activeTab = TabState.findById(tabs, activeId);
    if (activeTab !== undefined && activeTab.page === page) {
      return;
    }
    const existing = TabState.findByPage(tabs, page);
    if (existing !== undefined) {
      TabState.persist(tabs, existing.id);
      return;
    }
    const created: TabInfo = { id: TabState.genId(), page: page, pinned: false };
    tabs.push(created);
    TabState.persist(tabs, created.id);
  }

  /**
   * 点击标签：激活并路由到对应页面。
   */
  static activateTab(id: string): void {
    const tab = TabState.findById(TabState.getTabs(), id);
    if (tab === undefined) {
      return;
    }
    TabState.persist(TabState.getTabs(), id);
    if (AppState.getCurrentPage() !== tab.page) {
      AppState.setCurrentPage(tab.page);
    }
  }

  /**
   * 关闭标签；若关闭的是激活标签则激活相邻标签。
   */
  static closeTab(id: string): void {
    const tabs = TabState.getTabs();
    const target = TabState.findById(tabs, id);
    if (target === undefined) {
      return;
    }
    const idx = tabs.indexOf(target);
    const remaining: TabInfo[] = [];
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].id !== id) {
        remaining.push(tabs[i]);
      }
    }
    if (remaining.length === 0) {
      // 最后一个标签：重置为 Journal，不允许空标签组
      const home: TabInfo = { id: TabState.genId(), page: 'Journal', pinned: false };
      TabState.persist([home], home.id);
      AppState.setCurrentPage('Journal');
      return;
    }
    if (id === TabState.getActiveTabId()) {
      const nextIdx = idx >= remaining.length ? remaining.length - 1 : idx;
      const next = remaining[nextIdx];
      TabState.persist(remaining, next.id);
      AppState.setCurrentPage(next.page);
    } else {
      TabState.persist(remaining, TabState.getActiveTabId());
    }
  }

  /**
   * 新建标签页：Obsidian 默认打开欢迎/空页，这里打开 Journal（今日日志）。
   */
  static newTab(page: string): void {
    const tabs = TabState.getTabs();
    const existing = TabState.findByPage(tabs, page);
    if (existing !== undefined) {
      TabState.activateTab(existing.id);
      return;
    }
    const created: TabInfo = { id: TabState.genId(), page: page, pinned: false };
    tabs.push(created);
    TabState.persist(tabs, created.id);
    AppState.setCurrentPage(page);
  }

  /**
   * 关闭除指定标签外的全部标签。
   */
  static closeOthers(id: string): void {
    const target = TabState.findById(TabState.getTabs(), id);
    if (target === undefined) {
      return;
    }
    TabState.persist([target], id);
    AppState.setCurrentPage(target.page);
  }

  // ─── 持久化 ───

  private static persist(tabs: TabInfo[], activeId: string): void {
    let s = '[';
    for (let i = 0; i < tabs.length; i++) {
      if (i > 0) {
        s += ',';
      }
      s += '{"id":"' + tabs[i].id + '","page":"' + TabState.escape(tabs[i].page) +
        '","pinned":' + (tabs[i].pinned ? 'true' : 'false') + '}';
    }
    s += ']';
    AppStorage.setOrCreate(TABS_KEY, s);
    AppStorage.setOrCreate(ACTIVE_KEY, activeId);
    // 版本触发器：驱动 TabBar / MobileBottomBar 刷新
    const v = AppStorage.get<number>(VERSION_KEY) ?? 0;
    AppStorage.setOrCreate(VERSION_KEY, v + 1);
  }

  private static escape(raw: string): string {
    return raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  private static genId(): string {
    return 'tab_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 100000).toString(36);
  }
}
