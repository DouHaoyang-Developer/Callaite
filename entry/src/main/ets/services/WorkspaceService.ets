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

  getChildrenOfBlock(blockUuid: string): BlockData[] {
    return this.dataStore.getChildrenOfBlock(blockUuid);
  }

  getBlock(uuid: string): BlockData | undefined {
    return this.dataStore.getBlock(uuid);
  }

  executeOp(op: OutlinerOp): OpResult {
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

  savePage(pageId: string): void {
    this.dataStore.savePage(pageId);
  }

  getPageUuidForBlock(blockUuid: string): string | undefined {
    return this.dataStore.getPageUuidForBlock(blockUuid);
  }

  saveAll(): void {
    this.dataStore.saveAll();
  }
}
