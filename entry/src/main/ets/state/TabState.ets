import { AppState } from './AppState';
import { StatePersistence } from './StatePersistence';
import { DirtyPageTracker } from '../services/DirtyPageTracker';
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
 * 标签持久化落盘延迟（ms）。
 *
 * 标签切换/新建/关闭是用户节奏的操作，但要经 preferences.putSync + flushSync
 * 真正落盘，不能每次点击都同步写一次 XML；400ms 足以把「连点几个标签」合并成一次写，
 * 又短于用户「切完标签立刻上滑杀掉应用」的反应时间。
 * 真正的兜底仍是 EntryAbility.onBackground 的 StatePersistence.save()。
 */
const PERSIST_DEBOUNCE_MS = 400;

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
 * 状态持久化：AppStorage（JSON 字面量键序列化，混淆安全）+ 落盘。
 * U1.7 起 `callaite_tabs` / `callaite_activeTabId` 登记进 StatePersistence.STATE_KEYS —
 * AppStorage 本身是纯内存的，不落盘就谈不上「启动恢复上次会话」。
 */
export class TabState {
  /**
   * 「新标签页」路由 —— 新建标签时打开的起始页（components/page/HomePage.ets）。
   *
   * 对齐 Obsidian：Ctrl/Cmd+T 打开的是一张空白起始页（创建新文件 / 打开文件 / 关闭当前页），
   * 而不是直接切到今日日志。日志/图谱/白板等是**具体内容**，由各自入口显式打开。
   */
  static readonly NEW_TAB_PAGE: string = 'Home';

  /**
   * 初始化（EntryAbility 启动链调用，必须在 AppState.initialize() 之后）。
   *
   * 两种情形：
   *   · **上次会话已恢复**：StatePersistence 在 onCreate 阶段把 `callaite_tabs` /
   *     `callaite_activeTabId` 写回了 AppStorage（两键已登记进 StatePersistence.STATE_KEYS），
   *     这里校验激活标签仍然存在，并把 currentPage 对齐到该标签的页面。
   *   · **没有会话**（首次启动，或上次异常退出且未及落盘）：建一个「新标签页」。
   *
   * ⚠️ 为什么必须在这里对齐 currentPage：MainContainer.aboutToAppear（MainContainer.ets:157）
   *    调 syncToCurrentPage(AppState.getCurrentPage()) —— 该方法是**以 currentPage 为准**
   *    反向补标签。若不同步，恢复出来的标签组会被再补一个 currentPage（默认 Home）对应的标签。
   */
  static initialize(): void {
    const existing = TabState.getTabs();
    if (existing.length === 0) {
      const home: TabInfo = { id: TabState.genId(), page: TabState.NEW_TAB_PAGE, pinned: false };
      TabState.persist([home], home.id);
      return;
    }
    // 会话恢复：activeTabId 可能指向一个已被关闭的标签（用户上次操作与落盘之间的窗口），
    // 此时回落到第一个标签 —— 不允许留下「有标签但没有激活标签」的不一致状态
    // （TabBar 的 activeTabId 找不到匹配项会让所有页签都渲染成未激活态）。
    const active = AppStorage.get<string>(ACTIVE_KEY);
    const activeTab = active === undefined ? undefined : TabState.findById(existing, active);
    if (activeTab === undefined) {
      TabState.persist(existing, existing[0].id);
    }
    const restored = TabState.getActiveTab();
    if (restored !== undefined && AppState.getCurrentPage() !== restored.page) {
      AppState.setCurrentPage(restored.page);
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
    // 事件驱动 flush 点 ②-b：切换标签。
    // 注意这条路径**可能不经过** AppState.setCurrentPage（当 tab.page 恰好等于
    // 当前路由时，下面的 if 不成立），因此必须在 TabState 侧单独挂一次，
    // 否则「切到同路由的另一个标签」会绕过所有 flush 时机，只剩 5s 兜底。
    DirtyPageTracker.getInstance().flushNow();
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
    // 事件驱动 flush 点 ②-b（同 activateTab）：关闭标签会销毁对应页面视图，
    // 分支里还可能绕过 setCurrentPage（非激活标签分支），故统一在此挂一次。
    DirtyPageTracker.getInstance().flushNow();
    const idx = tabs.indexOf(target);
    const remaining: TabInfo[] = [];
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].id !== id) {
        remaining.push(tabs[i]);
      }
    }
    if (remaining.length === 0) {
      // 最后一个标签：重置为「新标签页」，不允许空标签组
      const home: TabInfo = { id: TabState.genId(), page: TabState.NEW_TAB_PAGE, pinned: false };
      TabState.persist([home], home.id);
      AppState.setCurrentPage(TabState.NEW_TAB_PAGE);
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
   * 新建标签页：打开「新标签页」起始页（HTML 路由 'Home' → components/page/HomePage.ets）。
   *
   * 传具体路由（'Graph' / 'Whiteboards' / 'AllPages' …）时行为不变：打开该路由的标签，
   * 已存在同路由标签则直接激活（沿用原有去重语义）。
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
    // 事件驱动 flush 点 ②-b（同 activateTab）：批量关闭会销毁多个页面视图。
    DirtyPageTracker.getInstance().flushNow();
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
    // 「启动恢复上次会话」的落盘时机：标签组每次变化都排一次去抖落盘。
    // 持久化介质与其余跨进程状态同源（StatePersistence → preferences `callaite_app_state`），
    // 两个键已登记进 StatePersistence.STATE_KEYS，否则 AppStorage 是纯内存的、重启即丢。
    StatePersistence.scheduleSave(PERSIST_DEBOUNCE_MS);
  }

  private static escape(raw: string): string {
    return raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }

  private static genId(): string {
    return 'tab_' + Date.now().toString(36) + '_' + Math.floor(Math.random() * 100000).toString(36);
  }
}
