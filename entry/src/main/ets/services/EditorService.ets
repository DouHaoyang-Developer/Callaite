import { WorkspaceService } from './WorkspaceService';
import { BlockData } from '../core/models/Block';
import { UUID } from '../utils/UUID';

/**
 * EditorService — 编辑器服务。
 *
 * 负责将键盘事件 / 手势事件转换为 OutlinerOp，并通过 OutlinerEngine 执行。
 * 管理编辑器焦点状态、当前选中的 Block。
 *
 * 对应 Logseq handler/editor.cljs (4096行) 的核心逻辑。
 */
export class EditorService {
  private static instance: EditorService | undefined;

  /** 当前获得焦点的 block UUID（空字符串 = 无焦点） */
  private focusedBlockUuid: string = '';

  /** 多选 block UUID 列表 */
  private selectedUuids: string[] = [];

  /** Slash 命令菜单是否打开 */
  private slashMenuOpen: boolean = false;

  /** 当前页码 */
  private currentPageName: string = '';

  private constructor() {}

  static getInstance(): EditorService {
    if (!EditorService.instance) {
      EditorService.instance = new EditorService();
    }
    return EditorService.instance;
  }

  // ─── 焦点管理 ───

  setFocusedBlock(uuid: string): void {
    this.focusedBlockUuid = uuid;
  }

  getFocusedBlockUuid(): string {
    return this.focusedBlockUuid;
  }

  clearFocus(): void {
    this.focusedBlockUuid = '';
    this.selectedUuids = [];
  }

  // ─── 多选管理 ───

  toggleSelection(uuid: string): void {
    let idx = -1;
    for (let i = 0; i < this.selectedUuids.length; i++) {
      if (this.selectedUuids[i] === uuid) {
        idx = i;
        break;
      }
    }
    if (idx >= 0) {
      const newSelection: string[] = [];
      for (let i = 0; i < this.selectedUuids.length; i++) {
        if (i !== idx) newSelection.push(this.selectedUuids[i]);
      }
      this.selectedUuids = newSelection;
    } else {
      this.selectedUuids.push(uuid);
    }
  }

  isSelected(uuid: string): boolean {
    for (let i = 0; i < this.selectedUuids.length; i++) {
      if (this.selectedUuids[i] === uuid) return true;
    }
    return false;
  }

  getSelectedCount(): number {
    return this.selectedUuids.length;
  }

  deleteSelected(): void {
    const ws = WorkspaceService.getInstance();
    for (let i = 0; i < this.selectedUuids.length; i++) {
      ws.executeOp({ type: 'delete-block', uuid: this.selectedUuids[i] });
    }
    this.selectedUuids = [];
  }

  // ─── 拖拽重排 ───

  moveBlockToTarget(draggedUuid: string, targetUuid: string, position: string): void {
    const ws = WorkspaceService.getInstance();
    const dragged = ws.getBlock(draggedUuid);
    const target = ws.getBlock(targetUuid);
    if (!dragged || !target) return;

    if (position === 'above') {
      const leftSibling = ws.getDataStore().getBlockTree().getLeftSibling(targetUuid);
      ws.executeOp({
        type: 'move-block', uuid: draggedUuid,
        newParentId: target.parentId,
        newLeftId: leftSibling ? leftSibling.uuid : '',
        newLevel: target.level
      });
    } else if (position === 'below') {
      ws.executeOp({
        type: 'move-block', uuid: draggedUuid,
        newParentId: target.parentId,
        newLeftId: targetUuid,
        newLevel: target.level
      });
    } else if (position === 'child') {
      const children = ws.getChildrenOfBlock(targetUuid);
      const lastChildId = children.length > 0 ? children[children.length - 1].uuid : '';
      ws.executeOp({
        type: 'move-block', uuid: draggedUuid,
        newParentId: targetUuid,
        newLeftId: lastChildId,
        newLevel: target.level + 1
      });
    }
  }

  canUndo(): boolean {
    const ws = WorkspaceService.getInstance();
    return ws.getOutlinerEngine().canUndo();
  }

  canRedo(): boolean {
    const ws = WorkspaceService.getInstance();
    return ws.getOutlinerEngine().canRedo();
  }

  undo(): void {
    const ws = WorkspaceService.getInstance();
    ws.getOutlinerEngine().undo();
  }

  redo(): void {
    const ws = WorkspaceService.getInstance();
    ws.getOutlinerEngine().redo();
  }

  // ─── 粘贴处理 ───

  pasteMarkdownAsBlocks(markdown: string, pageId: string): void {
    if (!markdown) return;
    const lines = markdown.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim();
      if (trimmed === '') continue;
      // 移除 Markdown 前缀，检测缩进
      let level = 0;
      let content = trimmed;
      if (trimmed.startsWith('- ')) {
        content = trimmed.substring(2);
      } else if (trimmed.startsWith('* ')) {
        content = trimmed.substring(2);
      }
      const ws = WorkspaceService.getInstance();
      ws.executeOp({
        type: 'insert-block', content: content,
        pageId: pageId, parentId: pageId,
        leftId: '', level: level
      });
    }
  }

  // ─── Block 内容更新 ───

  /**
   * 更新 block 内容并自动保存。
   */
  updateBlockContent(uuid: string, content: string): void {
    const ws = WorkspaceService.getInstance();
    const result = ws.executeOp({
      type: 'update-block',
      uuid: uuid,
      content: content
    });
    if (result.success) {
      // 操作成功后 Engine 内部已触发持久化
    }
  }

  // ─── Enter 键处理：创建兄弟 Block ───

  /**
   * 在当前焦点 block 下方创建新 block，并将焦点移到新 block。
   * @returns 新 block 的 UUID
   */
  createBlockBelow(pageId: string): string {
    const ws = WorkspaceService.getInstance();
    const focusedBlock = ws.getBlock(this.focusedBlockUuid);

    if (!focusedBlock) {
      // 在页面末尾创建新 block
      const result = ws.executeOp({
        type: 'insert-block',
        content: '',
        pageId: pageId,
        parentId: pageId,
        leftId: '',
        level: 0
      });
      if (result.success && result.affectedUuids.length > 0) {
        this.focusedBlockUuid = result.affectedUuids[0];
        return this.focusedBlockUuid;
      }
      return '';
    }

    // 在 focusedBlock 同级的右侧创建
    const result = ws.executeOp({
      type: 'insert-block',
      content: '',
      pageId: focusedBlock.pageId,
      parentId: focusedBlock.parentId,
      leftId: focusedBlock.uuid,
      level: focusedBlock.level
    });

    if (result.success && result.affectedUuids.length > 0) {
      this.focusedBlockUuid = result.affectedUuids[0];
      return this.focusedBlockUuid;
    }
    return '';
  }

  /**
   * 在指定 block 下方创建子 block（Tab 缩进语义）。
   */
  createChildBlock(parentUuid: string, pageId: string): string {
    const ws = WorkspaceService.getInstance();
    const parent = ws.getBlock(parentUuid);
    if (!parent) {
      return '';
    }

    const children = ws.getChildrenOfBlock(parentUuid);
    const lastChildId = children.length > 0 ? children[children.length - 1].uuid : '';

    const result = ws.executeOp({
      type: 'insert-block',
      content: '',
      pageId: pageId,
      parentId: parentUuid,
      leftId: lastChildId,
      level: parent.level + 1
    });

    if (result.success && result.affectedUuids.length > 0) {
      this.focusedBlockUuid = result.affectedUuids[0];
      return this.focusedBlockUuid;
    }
    return '';
  }

  // ─── Tab / Shift+Tab：缩进/反缩进 ───

  indentBlock(): void {
    if (!this.focusedBlockUuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    ws.executeOp({ type: 'indent', uuid: this.focusedBlockUuid });
  }

  outdentBlock(): void {
    if (!this.focusedBlockUuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    ws.executeOp({ type: 'outdent', uuid: this.focusedBlockUuid });
  }

  // ─── Backspace on empty：删除并合并 ───

  /**
   * 如果当前 block 内容为空，删除该 block，焦点上移到前一个兄弟或父 block。
   */
  deleteEmptyBlock(): boolean {
    if (!this.focusedBlockUuid) {
      return false;
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(this.focusedBlockUuid);
    if (!block || block.content !== '') {
      return false;
    }

    // 找到前一个兄弟（或父 block）
    const parent = ws.getBlock(block.parentId);
    const leftSibling = ws.getDataStore().getBlockTree().getLeftSibling(block.uuid);
    const prevId = leftSibling ? leftSibling.uuid : (parent ? parent.uuid : '');

    // 删除空 block
    ws.executeOp({ type: 'delete-block', uuid: block.uuid });

    // 焦点移到前一个
    if (prevId) {
      this.focusedBlockUuid = prevId;
    }
    return true;
  }

  // ─── 移动 Block ───

  moveBlockUp(): void {
    if (!this.focusedBlockUuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(this.focusedBlockUuid);
    if (!block) {
      return;
    }

    const leftSibling = ws.getDataStore().getBlockTree().getLeftSibling(block.uuid);
    if (!leftSibling) {
      return; // 已经是最顶部
    }

    // 找到 leftSibling 的 leftSibling
    const grandLeft = ws.getDataStore().getBlockTree().getLeftSibling(leftSibling.uuid);
    const newLeftId = grandLeft ? grandLeft.uuid : '';

    const result = ws.executeOp({
      type: 'move-block',
      uuid: block.uuid,
      newParentId: block.parentId,
      newLeftId: newLeftId,
      newLevel: block.level
    });
  }

  moveBlockDown(): void {
    if (!this.focusedBlockUuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(this.focusedBlockUuid);
    if (!block) {
      return;
    }

    const rightSibling = ws.getDataStore().getBlockTree().getRightSibling(block.uuid);
    if (!rightSibling) {
      return; // 已经是最底部
    }

    const result = ws.executeOp({
      type: 'move-block',
      uuid: block.uuid,
      newParentId: block.parentId,
      newLeftId: rightSibling.uuid,
      newLevel: block.level
    });
  }

  // ─── 标记循环 ───

  cycleMarker(): void {
    if (!this.focusedBlockUuid) {
      return;
    }
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(this.focusedBlockUuid);
    if (!block) {
      return;
    }

    let nextMarker = '';
    if (block.marker === '') {
      nextMarker = 'TODO';
    } else if (block.marker === 'TODO') {
      nextMarker = 'DOING';
    } else if (block.marker === 'DOING') {
      nextMarker = 'DONE';
    } else if (block.marker === 'DONE') {
      nextMarker = '';
    } else {
      nextMarker = 'TODO';
    }

    ws.executeOp({ type: 'set-marker', uuid: block.uuid, marker: nextMarker });
  }

  // ─── Slash 菜单 ───

  isSlashMenuOpen(): boolean {
    return this.slashMenuOpen;
  }

  openSlashMenu(): void {
    this.slashMenuOpen = true;
  }

  closeSlashMenu(): void {
    this.slashMenuOpen = false;
  }
}
