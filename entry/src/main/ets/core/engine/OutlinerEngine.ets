import { BlockTree } from './BlockTree';
import { DataStore } from '../db/DataStore';
import { BlockData } from '../models/Block';
import { DirtyPageTracker } from '../../services/DirtyPageTracker';
import {
  OutlinerOp,
  InsertBlockOp,
  DeleteBlockOp,
  DeleteBlocksOp,
  MoveBlockOp,
  MoveBlocksOp,
  UpdateBlockOp,
  IndentOp,
  OutdentOp,
  SetMarkerOp,
  SetPriorityOp,
  SetScheduledOp,
  SetDeadlineOp,
  AddPropertyOp,
  RemovePropertyOp,
  CollapseOp,
  NewPageOp,
  RenamePageOp,
  DeletePageOp,
  OpResult
} from './OutlinerOps';

/**
 * OutlinerEngine — 大纲操作引擎。
 *
 * 对应 Logseq outliner/core.cljs (1241行) + outliner/op.cljs (438行)。
 *
 * 职责：
 *  - 接收 OutlinerOp 并执行对应的树操作
 *  - 维护 undo/redo 栈（50 层）
 *  - 触发数据持久化
 */
export class OutlinerEngine {
  private blockTree: BlockTree;
  private dataStore: DataStore;
  private undoStack: OutlinerOp[] = [];
  private redoStack: OutlinerOp[] = [];
  private maxUndoDepth: number = 50;
  // 修复：记录每次操作的结果，用于 undo 时获取受影响的 UUID
  private lastOpResults: Map<OutlinerOp, string[]> = new Map();

  constructor(dataStore: DataStore) {
    this.dataStore = dataStore;
    this.blockTree = dataStore.getBlockTree();
  }

  // ─── 主入口 ───

  /**
   * 执行一个操作。
   */
  execute(op: OutlinerOp): OpResult {
    this.undoStack.push(op);
    this.redoStack = [];

    if (this.undoStack.length > this.maxUndoDepth) {
      const removed = this.undoStack.splice(0, 1);
      // 清理对应的 result 缓存
      this.lastOpResults.delete(removed[0]);
      this.blockTree.clearRecycleBin();
    }

    const result = this.dispatch(op);

    if (result.success) {
      // 修复：记录操作结果，供 undo 使用
      this.lastOpResults.set(op, result.affectedUuids);
      this.persistForOp(op);
    }

    return result;
  }

  /**
   * 撤销最近一个操作。
   */
  canUndo(): boolean { return this.undoStack.length > 0; }
  canRedo(): boolean { return this.redoStack.length > 0; }

  undo(): OpResult {
    if (this.undoStack.length === 0) {
      return { success: false, message: 'Nothing to undo', affectedUuids: [] };
    }
    const op = this.undoStack.pop();
    if (!op) {
      return { success: false, message: 'Nothing to undo', affectedUuids: [] };
    }
    this.redoStack.push(op);
    const result = this.undoOp(op);
    this.persistForOp(op);
    return result;
  }

  /**
   * 重做最近撤销的操作。
   */
  redo(): OpResult {
    if (this.redoStack.length === 0) {
      return { success: false, message: 'Nothing to redo', affectedUuids: [] };
    }
    const op = this.redoStack.pop();
    if (!op) {
      return { success: false, message: 'Nothing to redo', affectedUuids: [] };
    }
    this.undoStack.push(op);
    const result = this.dispatch(op);
    // 修复：redo 后记录结果，保证再次 undo 能正确还原
    if (result.success) {
      this.lastOpResults.set(op, result.affectedUuids);
    }
    this.persistForOp(op);
    return result;
  }

  // ─── 操作分发 ───

  private dispatch(op: OutlinerOp): OpResult {
    if (op.type === 'insert-block') return this.doInsertBlock(op);
    if (op.type === 'delete-block') return this.doDeleteBlock(op);
    if (op.type === 'delete-blocks') return this.doDeleteBlocks(op);
    if (op.type === 'move-block') return this.doMoveBlock(op);
    if (op.type === 'move-blocks') return this.doMoveBlocks(op);
    if (op.type === 'update-block') return this.doUpdateBlock(op);
    if (op.type === 'indent') return this.doIndent(op);
    if (op.type === 'outdent') return this.doOutdent(op);
    if (op.type === 'set-marker') return this.doSetMarker(op);
    if (op.type === 'set-priority') return this.doSetPriority(op);
    if (op.type === 'set-scheduled') return this.doSetScheduled(op);
    if (op.type === 'set-deadline') return this.doSetDeadline(op);
    if (op.type === 'add-property') return this.doAddProperty(op);
    if (op.type === 'remove-property') return this.doRemoveProperty(op);
    if (op.type === 'collapse') return this.doCollapse(op);
    if (op.type === 'new-page') return this.doNewPage(op);
    if (op.type === 'rename-page') return this.doRenamePage(op);
    if (op.type === 'delete-page') return this.doDeletePage(op);

    return { success: false, message: 'Unknown operation type', affectedUuids: [] };
  }

  // ─── Block 操作实现 ───

  private doInsertBlock(op: InsertBlockOp): OpResult {
    const block = this.blockTree.insertBlock(
      op.content, op.pageId, op.parentId, op.leftId, op.level
    );
    this.dataStore.getIndexStore().indexBlock(block.uuid, op.pageId);
    return { success: true, message: 'Block inserted', affectedUuids: [block.uuid] };
  }

  private doDeleteBlock(op: DeleteBlockOp): OpResult {
    const deleted = this.blockTree.deleteBlock(op.uuid);
    for (let i = 0; i < deleted.length; i++) {
      this.dataStore.getIndexStore().removeBlock(deleted[i].uuid);
    }
    const ids = this.extractUuids(deleted);
    return { success: true, message: 'Block deleted', affectedUuids: ids };
  }

  private doDeleteBlocks(op: DeleteBlocksOp): OpResult {
    const allDeleted: string[] = [];
    for (let i = 0; i < op.uuids.length; i++) {
      const deleted = this.blockTree.deleteBlock(op.uuids[i]);
      for (let j = 0; j < deleted.length; j++) {
        this.dataStore.getIndexStore().removeBlock(deleted[j].uuid);
        allDeleted.push(deleted[j].uuid);
      }
    }
    return { success: true, message: 'Blocks deleted', affectedUuids: allDeleted };
  }

  private doMoveBlock(op: MoveBlockOp): OpResult {
    this.blockTree.moveBlock(op.uuid, op.newParentId, op.newLeftId, op.newLevel);
    return { success: true, message: 'Block moved', affectedUuids: [op.uuid] };
  }

  private doMoveBlocks(op: MoveBlocksOp): OpResult {
    for (let i = 0; i < op.uuids.length; i++) {
      this.blockTree.moveBlock(op.uuids[i], op.newParentId, op.newLeftId, op.newLevel);
    }
    return { success: true, message: 'Blocks moved', affectedUuids: op.uuids };
  }

  private doUpdateBlock(op: UpdateBlockOp): OpResult {
    this.blockTree.updateBlock(op.uuid, op.content);
    return { success: true, message: 'Block updated', affectedUuids: [op.uuid] };
  }

  private doIndent(op: IndentOp): OpResult {
    const block = this.blockTree.getBlock(op.uuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    const leftSibling = this.blockTree.getLeftSibling(op.uuid);
    if (!leftSibling) {
      return { success: false, message: 'Cannot indent: no left sibling', affectedUuids: [] };
    }

    // 将 block 移动为 leftSibling 的最后一个子节点
    const leftChildren = this.blockTree.getChildren(leftSibling.uuid);
    const newLeftId = leftChildren.length > 0 ? leftChildren[leftChildren.length - 1].uuid : '';
    this.blockTree.moveBlock(op.uuid, leftSibling.uuid, newLeftId, block.level + 1);
    return { success: true, message: 'Block indented', affectedUuids: [op.uuid] };
  }

  private doOutdent(op: OutdentOp): OpResult {
    const block = this.blockTree.getBlock(op.uuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    if (block.level <= 0) {
      return { success: false, message: 'Cannot outdent: already at top level', affectedUuids: [] };
    }

    const parent = this.blockTree.getBlock(block.parentId);
    if (!parent) {
      return { success: false, message: 'Cannot outdent: no parent', affectedUuids: [] };
    }

    // 将 block 移动到 parent 之后
    const grandParentId = parent.parentId;
    const newLeftId = parent.uuid;
    this.blockTree.moveBlock(op.uuid, grandParentId, newLeftId, block.level - 1);
    return { success: true, message: 'Block outdented', affectedUuids: [op.uuid] };
  }

  private doSetMarker(op: SetMarkerOp): OpResult {
    const block = this.blockTree.getBlock(op.uuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    block.marker = op.marker;
    return { success: true, message: 'Marker set', affectedUuids: [op.uuid] };
  }

  private doSetPriority(op: SetPriorityOp): OpResult {
    const block = this.blockTree.getBlock(op.uuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    block.priority = op.priority;
    return { success: true, message: 'Priority set', affectedUuids: [op.uuid] };
  }

  private doSetScheduled(op: SetScheduledOp): OpResult {
    const block = this.blockTree.getBlock(op.uuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    block.scheduled = op.date;
    return { success: true, message: 'Scheduled date set', affectedUuids: [op.uuid] };
  }

  private doSetDeadline(op: SetDeadlineOp): OpResult {
    const block = this.blockTree.getBlock(op.uuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    block.deadline = op.date;
    return { success: true, message: 'Deadline set', affectedUuids: [op.uuid] };
  }

  private doAddProperty(op: AddPropertyOp): OpResult {
    const block = this.blockTree.getBlock(op.blockUuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    block.properties.set(op.name, op.value);
    return { success: true, message: 'Property added', affectedUuids: [op.blockUuid] };
  }

  private doRemoveProperty(op: RemovePropertyOp): OpResult {
    const block = this.blockTree.getBlock(op.blockUuid);
    if (!block) {
      return { success: false, message: 'Block not found', affectedUuids: [] };
    }
    block.properties.remove(op.name);
    return { success: true, message: 'Property removed', affectedUuids: [op.blockUuid] };
  }

  private doCollapse(op: CollapseOp): OpResult {
    this.blockTree.setCollapsed(op.uuid, op.collapsed);
    return { success: true, message: 'Collapse toggled', affectedUuids: [op.uuid] };
  }

  private doNewPage(op: NewPageOp): OpResult {
    const page = this.dataStore.createPage(op.name, op.originalName);
    return { success: true, message: 'Page created', affectedUuids: [page.uuid] };
  }

  private doRenamePage(op: RenamePageOp): OpResult {
    this.dataStore.renamePage(op.pageId, op.newName);
    return { success: true, message: 'Page renamed', affectedUuids: [op.pageId] };
  }

  private doDeletePage(op: DeletePageOp): OpResult {
    this.dataStore.deletePage(op.pageId);
    return { success: true, message: 'Page deleted', affectedUuids: [op.pageId] };
  }

  // ─── Undo ───

  private undoOp(op: OutlinerOp): OpResult {
    // 修复：使用 lastOpResults 获取操作影响的具体 UUID
    const affectedUuids = this.lastOpResults.get(op);

    if (op.type === 'insert-block') {
      // undo insert = delete 插入的 block
      if (affectedUuids && affectedUuids.length > 0) {
        const insertedUuid = affectedUuids[0];
        this.lastOpResults.delete(op);
        return this.doDeleteBlock({ type: 'delete-block', uuid: insertedUuid });
      }
      return { success: false, message: 'Cannot undo insert: no UUID recorded', affectedUuids: [] };
    }
    if (op.type === 'delete-block') {
      // undo delete = restore from recycle bin
      this.blockTree.restoreFromRecycleBin(op.uuid);
      this.lastOpResults.delete(op);
      return { success: true, message: 'Block restored', affectedUuids: [op.uuid] };
    }
    if (op.type === 'update-block') {
      // undo update: 需要旧内容 — 此前未保存，标记不支持
      // 完整实现需要在 execute 前保存 block 旧内容
      this.lastOpResults.delete(op);
      return { success: false, message: 'Undo content update not supported', affectedUuids: [] };
    }
    if (op.type === 'indent') {
      // undo indent = outdent
      this.lastOpResults.delete(op);
      return this.doOutdent({ type: 'outdent', uuid: op.uuid });
    }
    if (op.type === 'outdent') {
      // undo outdent = indent
      this.lastOpResults.delete(op);
      return this.doIndent({ type: 'indent', uuid: op.uuid });
    }
    if (op.type === 'set-marker') {
      // undo set-marker: 需要旧 marker — 简化不支持
      this.lastOpResults.delete(op);
      return { success: false, message: 'Undo marker change not supported', affectedUuids: [] };
    }
    // 其他操作的 undo 暂简化为不支持
    this.lastOpResults.delete(op);
    return { success: false, message: 'Undo not yet supported for this operation', affectedUuids: [] };
  }

  // ─── 辅助 ───

  private extractUuids(blocks: BlockData[]): string[] {
    const result: string[] = [];
    for (let i = 0; i < blocks.length; i++) {
      result.push(blocks[i].uuid);
    }
    return result;
  }

  // ─── 持久化 ───

  /**
   * 纯文本内容变更的操作类型 —— 只有这些走「标脏 + 延迟 flush」。
   *
   * 判定标准：只改 `block.content`，不动块的存在性与层级（父子/左右兄弟关系），
   * 因此中间态即便丢失也不会造成结构损坏，且高频（每次按键，实测 150ms 级）。
   * 与之相对，`set-marker` / `add-property` 等虽然也低频，但保守起见仍即时落盘。
   *
   * ⚠️ 只放 `update-block` 一项。`rename-page` 虽然也改文件，但其落盘发生在
   *    `DataStore.renamePage`（:217）内部，本就不经过这里；若将来把它移出来，
   *    应走结构性分支（先 flush 再写），而不是被延迟。
   */
  private static readonly TEXT_ONLY_OPS: string[] = [
    'update-block'
  ];

  /**
   * 结构性操作后是否要把所有脏页先写下去。
   *
   * 结构性操作会立即读写同一批 .md 文件；若此时还有「已标脏未落盘」的文本内容，
   * 必须先 flush，否则内存内容与文件内容不一致的窗口会被拉长。
   * 实现上保守取「flush 全部脏页」—— 脏页数在正常使用下为 1。
   */
  private static readonly STRUCTURAL_OPS: string[] = [
    'insert-block', 'delete-block',
    'delete-blocks', 'update-block',
    'move-block', 'move-blocks',
    'indent', 'outdent',
    'set-marker', 'set-priority',
    'set-scheduled', 'set-deadline',
    'add-property', 'remove-property'
  ];

  private isTextOnlyOp(op: OutlinerOp): boolean {
    for (let i = 0; i < OutlinerEngine.TEXT_ONLY_OPS.length; i++) {
      if (OutlinerEngine.TEXT_ONLY_OPS[i] === op.type) {
        return true;
      }
    }
    return false;
  }

  private isStructuralOp(op: OutlinerOp): boolean {
    for (let i = 0; i < OutlinerEngine.STRUCTURAL_OPS.length; i++) {
      if (OutlinerEngine.STRUCTURAL_OPS[i] === op.type) {
        return true;
      }
    }
    return false;
  }

  /**
   * 操作后的持久化分流（本方法取代原先「一律同步 savePage」的 persistForOp）。
   *
   *   · 文本类变更（update-block）→ **只标脏**，不落盘。
   *     落盘由 DirtyPageTracker 的 flush 时机决定（失焦 / 切页 / 进后台 / 销毁前 /
   *     5s 兜底定时器）。
   *   · 结构性变更 → **先 flush 全部脏页**（把待写的文本内容写下去），
   *     再同步 savePage 本次受影响的页面。保留原有的即时落盘语义。
   *   · 其余操作（collapse 等）→ 不动文件，与原实现一致
   *     （`collapse` 从未在 persistForOp 的落盘清单里）。
   */
  private persistForOp(op: OutlinerOp): void {
    if (this.isTextOnlyOp(op)) {
      const pageId = this.findPageForOp(op);
      if (pageId) {
        DirtyPageTracker.getInstance().markDirty(pageId);
      }
      return;
    }

    if (!this.isStructuralOp(op)) {
      return;
    }

    // 结构性操作之前：必须先把「已标脏未落盘」的内容写下去
    DirtyPageTracker.getInstance().flushNow();

    const pageId = this.findPageForOp(op);
    if (pageId) {
      this.persistNow(pageId);
    }
  }

  /**
   * 立即把单个页面写盘。
   *
   * 唯一的落盘出口（除 DataStore 自身的 CRUD 内部调用外），供
   * DirtyPageTracker 的注入回调与 persistForOp 共用。
   *
   * ⚠️ 刻意不改 `DataStore.savePage` / `FileRepository.writeTextSync` 的内部实现
   *    （临时文件 + fsync + rename 是最后一道防线），只决定调用时机。
   *
   * @returns 是否确实写盘成功。失败时由调用方（DirtyPageTracker）重新标脏，
   *          交给下一次兜底重试，避免「写失败即静默丢弃」。
   */
  persistNow(pageId: string): boolean {
    if (!this.dataStore.getPage(pageId)) {
      return false;
    }
    try {
      this.dataStore.savePage(pageId);
      return true;
    } catch (e) {
      console.error('[OutlinerEngine] persistNow failed for page ' + pageId + ': ' + JSON.stringify(e));
      return false;
    }
  }

  private findPageForOp(op: OutlinerOp): string | undefined {
    if (op.type === 'insert-block') {
      return op.pageId;
    }
    if (op.type === 'delete-block') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'update-block') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'move-block') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'move-blocks') {
      if (op.uuids.length > 0) {
        return this.dataStore.getPageUuidForBlock(op.uuids[0]);
      }
      return undefined;
    }
    if (op.type === 'delete-blocks') {
      if (op.uuids.length > 0) {
        return this.dataStore.getPageUuidForBlock(op.uuids[0]);
      }
      return undefined;
    }
    if (op.type === 'indent') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'outdent') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'set-marker') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'set-priority') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'set-scheduled') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'set-deadline') return this.dataStore.getPageUuidForBlock(op.uuid);
    if (op.type === 'add-property') return this.dataStore.getPageUuidForBlock(op.blockUuid);
    if (op.type === 'remove-property') return this.dataStore.getPageUuidForBlock(op.blockUuid);
    if (op.type === 'collapse') return this.dataStore.getPageUuidForBlock(op.uuid);
    return undefined;
  }
}
