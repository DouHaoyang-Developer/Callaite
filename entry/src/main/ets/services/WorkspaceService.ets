import { SaveQueue } from './SaveQueue';
import { DataStore } from '../core/db/DataStore';
import { OutlinerEngine } from '../core/engine/OutlinerEngine';
import { PageData } from '../core/models/Page';
import { BlockData } from '../core/models/Block';
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
      // O1：向保存队列注入落盘回调（静默 1.2s 自动 saveAll，原子写逐页落盘）
      const created = WorkspaceService.instance;
      SaveQueue.getInstance().init((): void => {
        created!.saveAll();
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

  getBlock(uuid: string): BlockData | undefined {
    return this.dataStore.getBlock(uuid);
  }

  executeOp(op: OutlinerOp): OpResult {
    const result = this.outlinerEngine.execute(op);
    // O1：变更成功即标记脏（静默 1.2s 落盘，强杀丢失窗口 ≤1.2s）
    if (result.success) {
      SaveQueue.getInstance().markDirty();
    }
    return result;
  }

  undo(): OpResult {
    const result = this.outlinerEngine.undo();
    if (result.success) {
      SaveQueue.getInstance().markDirty();
    }
    return result;
  }

  redo(): OpResult {
    const result = this.outlinerEngine.redo();
    if (result.success) {
      SaveQueue.getInstance().markDirty();
    }
    return result;
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

  savePage(pageId: string): void {
    this.dataStore.savePage(pageId);
  }

  getPageUuidForBlock(blockUuid: string): string | undefined {
    return this.dataStore.getPageUuidForBlock(blockUuid);
  }

  saveAll(): void {
    this.dataStore.saveAll();
  }

  /**
   * O4：整页编辑器保存 —— 用 Markdown 重建页面块（保留页面身份）。
   */
  replacePageBlocks(pageId: string, markdown: string): boolean {
    return this.dataStore.replacePageBlocks(pageId, markdown);
  }
}
