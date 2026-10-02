import { WorkspaceService } from '../services/WorkspaceService';
import { AppState } from '../state/AppState';
import { TemplateService, TemplateInfo } from '../services/TemplateService';
import { promptAction } from '@kit.ArkUI';

export interface PluginStats {
  pages: number;
  blocks: number;
}

/**
 * PluginAPI — 插件能力代理。
 *
 * 提供给插件的 API 接口集合，插件通过此类访问应用核心功能。
 * 新能力通过 PluginManager.registerAPI() 动态注册。
 */
export class PluginAPI {
  private static apis: Map<string, Object> = new Map<string, Object>();

  /**
   * 注册一个 API 能力。
   */
  static register(name: string, api: Object): void {
    PluginAPI.apis.set(name, api);
  }

  /**
   * 获取已注册的 API 能力。
   */
  static get<T>(name: string): T | undefined {
    return PluginAPI.apis.get(name) as T;
  }

  // ─── 内置 API ───

  /** 获取当前页面名 */
  static getCurrentPage(): string {
    return AppState.getCurrentPage();
  }

  /** 切换页面 */
  static navigateTo(page: string): void {
    AppState.setCurrentPage(page);
  }

  /**
   * 在今日日志插入 Block（**按天幂等**：今日页已有同款块时不再插入）。
   *
   * S3-W10 修 `W9-1`。为什么必须有守卫：`BookmarkPlugin.enabledByDefault = true`
   * ⇒ 每次冷启动 `initAllPlugins()` 都会走 `enable()` → `onEnable()` → 本方法
   * （`BuiltinPlugins.ets:15-17`）⇒ 修复前**每次启动都在用户的日记里追加一行**
   * （W9 实测：1 次冷启动 = 今日页 +26 B = 恰好 1 块；`2026-09-30.md` 里留下 29 个）。
   * 而插件自述的语义是「**每天**自动在日志页插入快速记录模板」（`BuiltinPlugins.ets:12`）
   * ⇒ 本方法按「每天一次」而非「每次启动一次」实现 —— 让代码符合它自己的注释。
   *
   * ─── 判据（本窗口唯一的设计决策）───
   * **「以模板文本开头」的顶层块即算「今天已经插过」**（不是「逐字节相等」）：
   *   ① 用户当天把 `📌 今日要点: ` 改写成 `📌 今日要点: 写完 W10` ⇒ **仍算已插**
   *      —— 否则同一天会再插一次，那正是本缺陷的用户可见形态 ✗；
   *   ② 次日是**新页**（`getPageByName(新日期)`）⇒ 自然再插一次 ✓ ——「每天一次」的语义保住 ✓。
   *   ⇒ 判据刻意偏保守：用户手打一行同模板开头的块，也会让当天不再插 ✓（这是想要的）。
   *
   * ⚠️ **为什么必须做「尾随空白归一」**（本窗口实测踩到的坑，务必保留本注释）：
   *   模板文本**带尾随空格**（`'📌 今日要点: '`），而模型的 `content` 是**不带**的
   *   —— `MarkdownParser` 在 `:170` 用 `afterPriority.trim()` 剥掉尾部空白。
   *   实测反证（设备 `hilog` 探针，MateBook Pro / 2026-10-02）：
   *     `content` 码点 = `d83d.dccc.20.4eca.65e5.8981.70b9.3a.20.`（**9** 个码元，含 `20.`）
   *     而模型里同类块的 `content` = `d83d.dccc.20.4eca.65e5.8981.70b9.3a.`（**8** 个码元）
   *   ⇒ 用未归一的入参做判据时 **命中 = 0** ⇒ 守卫**一次都不生效**、每次启动照样 +26 B ✗
   *     （实测：该版本下 2026-10-02.md `572 → 598 → 624 → 650 → 676 → 702 → 728`，每次都 +26 ✗）。
   *   ⇒ 归一后同一现场 **命中 = 28/28** ✓、文件停在 728 B **不再增长** ✓。
   *   归一**只作用于尾部空白**（`trimEnd()`）：两**侧**都归一 ⇒ 「文件里带尾随空格」与
   *   「模型里已剥掉」两种形态都能命中，也不会因空白差异把同一模板判成两个 ✓。
   *
   * ⚠️ **多行模板必须用「续行形态」匹配**（本窗口受控差分查出的第 3 个契约细节）：
   *   模板若含 `\n`（如 `TemplateService` 的会议/项目模板），落盘后被导出成**续行**形式
   *   `MarkdownExporter` 对第 2 行起写的是 `indent + INDENT_PREFIX + 行`
   *   （`MarkdownExporter.ets:73-77`，`INDENT_PREFIX = '  '` 见 `Constants.ets:83`
   *   ⇒ 顶层块恒为 `'  - 行'`），再解析时又按 `'{缩进}- {行}'` 拼回 `content`
   *   （`MarkdownParser.ets:150` 剥前缀 + `:197` 用 `\n` 拼回）
   *   ⇒ 模型里的多行 `content` **不是原串**，而是 `首行 + '\n  - ' + 第2行 + '\n  - ' + …`。
   *   实测（`w10/diff_driver.js` 夹具 J）：只匹配首行形态时，多行模板在**当天第二轮**判为「没有」
   *   ⇒ 仍会重复插入 ✗（本缺陷的同族缺口）⇒ 故 `parsedText` 用 `'\n  - '` 替换换行 ✓
   *   （**只用 2 空格**：本方法固定插在 `level: 0`，见下方 `executeOp` ⇒ 缩进恒为 `'  '` ✓）。
   *
   * 放在这一层（最靠近「插入」）⇒ 覆盖**所有**调用方：`BookmarkPlugin` 的每次启动 ✓、
   * `SettingsPage` 里把插件开关**重新打开**（`SettingsPage.ets:845-847` → `enable()`）✓、
   * `insertTemplateByName` 的模板展开 ✓ —— 且**不改插件的语义**（每天仍插一次 ✓）。
   * 作用域只限**顶层块**（`getPageBlocks` = `getTopLevelBlocks`）：本方法自己也只插顶层块
   * （`parentId: page.uuid`）⇒ 与插入位置同域 ✓；子块里的同款文本不参与判据（不会误拦）。
   * ⚠️ **判据基于内存模型**（`getPageBlocks`）：与 `PluginAPI.getPageBlocks()` 同一数据源
   * ⇒ 本页若尚有「已改但未 flush」的文本，判据看到的是内存值（本仓一致口径 ✓）。
   */
  static insertTodayBlock(content: string, marker: string = ''): void {
    const ws = WorkspaceService.getInstance();
    const now = new Date();
    const today = now.getFullYear() + '-' +
      (now.getMonth() + 1).toString().padStart(2, '0') + '-' +
      now.getDate().toString().padStart(2, '0');
    const page = ws.getPageByName(today);
    if (!page) return;
    const matchText = content.trimEnd();
    // 续行形态：**所有**换行都要换（用 split/join 而非 replace —— 后者只替换第一处，实测会在
    // 夹具 J 上失手：3 行模板的第 3 行没被转换 ⇒ 判为「没有」⇒ 当天仍重复插入 ✗）
    const parsedText = matchText.split('\n').join('\n  - ');
    const existingBlocks = ws.getPageBlocks(page.uuid);
    for (let i = 0; i < existingBlocks.length; i++) {
      const existing = existingBlocks[i].content;
      if (existing.startsWith(matchText) || existing.startsWith(parsedText)) {
        return; // 今日页已有该模板块 ⇒ 按天幂等，不再插
      }
    }
    const r = ws.executeOp({
      type: 'insert-block', content: marker ? marker + ' ' + content : content,
      pageId: page.uuid, parentId: page.uuid, leftId: '', level: 0
    });
    // ★ W11（修 `W8-A`）：真插入才 bump —— 守卫命中时上面已 `return`，语义不变 ✓。
    //   为什么补在**服务内**（而不是调用方）：本方法的调用方是**插件**
    //   （`BuiltinPlugins.ets:16` 的 `onEnable`）与 `insertTemplateByName`（零外部调用方），
    //   而插件是纯逻辑类、拿不到视图层语义 ⇒ 「补在调用方」这一层不存在。
    //   且**有可达的运行时调用方**：设置页插件开关 → `PluginManager.enable()` → `onEnable()`
    //   （`SettingsPage.ets:845-847`）⇒ 插入可能发生在 UI 存活期间，目标页（今日日志）
    //   可能正被 `JournalFeed` 内嵌 `BlockList` 或**副窗格**（`callaite_splitPage`）显示
    //   ⇒ 没有 bump 就是「数据与磁盘都对、界面毫无反应」（陷阱 22 / 15）。
    //   W10 的注释已把「放在这一层（最靠近插入）⇒ 覆盖所有调用方」定为既定决策，本行沿用它 ✓。
    if (r.success) {
      AppState.bumpBlocksVersion();
    }
  }

  /** 搜索页面 */
  static searchPages(query: string): string[] {
    const ws = WorkspaceService.getInstance();
    const pages = ws.searchPages(query);
    const names: string[] = [];
    for (let i = 0; i < pages.length; i++) names.push(pages[i].originalName);
    return names;
  }

  /** 获取所有标签 */
  static getAllTags(): string[] {
    return WorkspaceService.getInstance().getAllTags();
  }

  /** 获取所有页面名 */
  static listAllPages(): string[] {
    const pages = WorkspaceService.getInstance().getAllPages();
    const names: string[] = [];
    for (let i = 0; i < pages.length; i++) {
      names.push(pages[i].originalName);
    }
    return names;
  }

  /** 获取页面 Block 内容摘要 */
  static getPageBlocks(pageName: string): string[] {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) {
      return [];
    }
    const blocks = ws.getPageBlocks(page.uuid);
    const result: string[] = [];
    for (let i = 0; i < blocks.length; i++) {
      result.push(blocks[i].content.substring(0, 80));
    }
    return result;
  }

  /** 统计页面与 Block 数量 */
  static getPageStats(): PluginStats {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    let blocks = 0;
    for (let i = 0; i < pages.length; i++) {
      blocks = blocks + ws.getPageBlocks(pages[i].uuid).length;
    }
    const stats: PluginStats = { pages: pages.length, blocks: blocks };
    return stats;
  }

  /** 获取内置模板名列表 */
  static getTemplateNames(): string[] {
    const templates = TemplateService.getBuiltinTemplates();
    const names: string[] = [];
    for (let i = 0; i < templates.length; i++) {
      names.push(templates[i].name);
    }
    return names;
  }

  /** 按名称插入模板到今日日志 */
  static insertTemplateByName(name: string): boolean {
    const templates = TemplateService.getBuiltinTemplates();
    for (let i = 0; i < templates.length; i++) {
      if (templates[i].name === name) {
        const expanded = TemplateService.expand(templates[i].content, PluginAPI.getCurrentPage());
        PluginAPI.insertTodayBlock(expanded, '');
        return true;
      }
    }
    return false;
  }

  /** 弹出通知 toast */
  static notify(message: string): void {
    promptAction.openToast({ message: message }).catch(() => {});
  }
}
