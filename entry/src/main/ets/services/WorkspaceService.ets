import { SaveQueue } from './SaveQueue';
import { DirtyPageTracker } from './DirtyPageTracker';
import { DataStore } from '../core/db/DataStore';
import { OutlinerEngine } from '../core/engine/OutlinerEngine';
import { PageData } from '../core/models/Page';
import { BlockData } from '../core/models/Block';
import { BacklinkInfo } from '../core/db/DataStore';
import { OutlinerOp, OpResult } from '../core/engine/OutlinerOps';

/**
 * WorkspaceService — 工作区服务单例。
 *
 * 职责：
 *  - 持有 DataStore 和 OutlinerEngine 实例
 *  - 提供 UI 层可调用的高层 API
 *  - 协调页面切换、Block 操作、搜索等
 *
 * 对应 Logseq 中 state.cljs (全局 Atom) + handler/ 各模块的组合。
 */
export class WorkspaceService {
  private static instance: WorkspaceService | undefined;

  private dataStore: DataStore = new DataStore();
  private outlinerEngine: OutlinerEngine;

  private constructor() {
    this.outlinerEngine = new OutlinerEngine(this.dataStore);
  }

  static getInstance(): WorkspaceService {
    if (!WorkspaceService.instance) {
      WorkspaceService.instance = new WorkspaceService();
      const created = WorkspaceService.instance;
      // 历史兼容：SaveQueue 只保留「全库落盘」回调入口，不再自行定时调用
      SaveQueue.getInstance().init((): void => {
        created!.saveAll();
      });
      // 惰性落盘：把「写单页」能力注入脏页协调器（由它在事件/兜底时机调用）
      DirtyPageTracker.getInstance().setPageSaver((pageId: string): boolean => {
        return created!.getOutlinerEngine().persistNow(pageId);
      });
    }
    return WorkspaceService.instance;
  }

  // ─── 初始化 ───

  getDataStore(): DataStore {
    return this.dataStore;
  }

  getOutlinerEngine(): OutlinerEngine {
    return this.outlinerEngine;
  }

  /**
   * 加载知识库。
   */
  loadGraph(graphRoot: string): void {
    this.dataStore.loadGraph(graphRoot);
  }

  isInitialized(): boolean {
    return this.dataStore.isInitialized();
  }

  // ─── 页面操作 ───

  getAllPages(): PageData[] {
    return this.dataStore.getAllPages();
  }

  getPageByName(name: string): PageData | undefined {
    return this.dataStore.getPageByName(name);
  }

  getJournalPage(dateStr: string): PageData | undefined {
    return this.dataStore.getPageByName(dateStr);
  }

  createPage(name: string): PageData {
    return this.dataStore.createPage(name, name);
  }

  createJournalPage(dateStr: string): PageData {
    const page = this.dataStore.createPage(dateStr, dateStr);
    page.journalDay = dateStr;
    this.dataStore.savePage(page.uuid);
    return page;
  }

  // ─── Block 操作 ───

  getPageBlocks(pageId: string): BlockData[] {
    return this.dataStore.getTopLevelBlocks(pageId);
  }

  /**
   * 取页面**全部** Block（含子块）。
   *
   * 与 getPageBlocks（仅顶层，走 childrenMap 查表）不同，此方法遍历 blockMap 按
   * pageId 过滤，不依赖父子索引是否健全 —— 整页编辑器导出 markdown 时应用它。
   * 背景：O4 整页编辑器曾因块列表为空导致 markdown 为空（诊断 toast 实测
   * `md=0 uuid=OK`），「应用并重建」因此被空内容闸门拦下。
   */
  getAllPageBlocks(pageId: string): BlockData[] {
    return this.dataStore.getPageBlocks(pageId);
  }

  getChildrenOfBlock(blockUuid: string): BlockData[] {
    return this.dataStore.getChildrenOfBlock(blockUuid);
  }

  /**
   * 页面的**可见行序列**（顶层块 + 已展开子块，屏幕从上到下的顺序）。
   *
   * 整页大纲的 List 数据源与 U2.1a 的 `scrollToIndex` 下标空间**必须同源**，
   * 否则下标会指向另一行；故两侧统一走这里（单一实现，不会漂移）。
   */
  getVisibleBlocks(pageId: string): BlockData[] {
    return this.dataStore.getVisibleBlocks(pageId);
  }

  getBlock(uuid: string): BlockData | undefined {
    return this.dataStore.getBlock(uuid);
  }

  executeOp(op: OutlinerOp): OpResult {
    // 落盘时机完全由 OutlinerEngine.persistForOp 分流：
    //   文本类（update-block）→ 标脏等 flush；结构性 → 先 flush 再即时写。
    // 故此处不再调用 SaveQueue.markDirty()（原先它会导致「结构性操作已落盘，
    // 却又留下一个脏标记 → 下次 flush 再写一遍」的冗余写）。
    return this.outlinerEngine.execute(op);
  }

  undo(): OpResult {
    return this.outlinerEngine.undo();
  }

  redo(): OpResult {
    return this.outlinerEngine.redo();
  }

  // ─── 搜索 ───

  searchPages(query: string): PageData[] {
    return this.dataStore.searchPages(query);
  }

  getAllTags(): string[] {
    return this.dataStore.getAllTags();
  }

  getPagesByTag(tag: string): PageData[] {
    return this.dataStore.getPagesByTag(tag);
  }

  // ─── 保存 ───

  /**
   * 立即落盘「已标脏但未 flush」的页面。
   *
   * 事件驱动 flush 的统一入口：块/编辑器失焦、切换页面/标签、应用进入后台、
   * 应用销毁前都必须先调它（结构性操作前由 OutlinerEngine.persistForOp 自行调用）。
   */
  flushDirtyPages(): void {
    DirtyPageTracker.getInstance().flushNow();
  }

  /** 是否存在「已标脏但未落盘」的页面（供 UI/诊断使用） */
  hasUnflushedPages(): boolean {
    return DirtyPageTracker.getInstance().hasPending();
  }

  savePage(pageId: string): void {
    // 先把待写的文本内容写下去，再写目标页（两者都走同一批 .md 文件）
    DirtyPageTracker.getInstance().flushNow();
    this.dataStore.savePage(pageId);
  }

  getPageUuidForBlock(blockUuid: string): string | undefined {
    return this.dataStore.getPageUuidForBlock(blockUuid);
  }

  /**
   * 读取反链 —— **先 flush 脏页，再读索引**。
   *
   * 为什么读一次反链也要 flush（S3-W1 的「双向验收①：保存后不切页就能看到新反链」）：
   *   文本输入走惰性落盘 ⇒ `update-block` 只 `markDirty`，索引对账挂在落盘链路上。
   *   若读方不先 flush，就会出现**纯粹由读取时机造成的假阴性**：
   *   用户刚打完 `[[x]]`，反链面板因为「聚焦块变化」刷新（`RightSidebar` 的
   *   `@Watch('callaite_focusedBlock')`，见其注释「挂它只为驱动反链刷新」），
   *   而此刻页面还没到 5s 兜底、也还没失焦 ⇒ 索引里当然还没有这条反链
   *   ⇒ 面板显示「改完了但反链没加」，与 W12-3 的现象**逐字相同**，
   *   但根因完全不同（一个是索引从不更新，一个是读得太早）。
   *
   * 成本：`flushNow()` 在无脏页时是 O(1) 直接返回（见 `DirtyPageTracker.flushNow`），
   *   正常使用下脏页数 ≤1，所以「多一次 flush」在绝大多数调用里是零开销。
   *
   * ⚠️ 本方法**不改变索引口径**，只是把「读前置 flush」这件事收敛成一个入口 ——
   *   与 `SaveQueue` / `DirtyPageTracker` 同样的「单一写入口」约定。
   */
  getBacklinksFresh(pageName: string): BacklinkInfo[] {
    this.flushDirtyPages();
    return this.dataStore.getBacklinks(pageName);
  }

  saveAll(): void {
    // 兜底路径（onBackground / onSaveState / 未捕获异常）同样先 flush 脏页；
    // 注意 saveAll 依旧逐页全量写，不走 DirtyPageTracker —— 它是最后一道防线。
    DirtyPageTracker.getInstance().flushNow();
    this.dataStore.saveAll();
  }

  /**
   * O4：整页编辑器保存 —— 用 Markdown 重建页面块（保留页面身份）。
   */
  replacePageBlocks(pageId: string, markdown: string): boolean {
    return this.dataStore.replacePageBlocks(pageId, markdown);
  }
}
