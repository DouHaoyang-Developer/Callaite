import { BlockData, createBlockData } from '../models/Block';
import { PageData } from '../models/Page';
import { UUID } from '../../utils/UUID';

/**
 * BlockTree — 内存中的 Block 树数据结构。
 *
 * 对应 Logseq outliner/tree.cljs (INode 协议) + outliner/core.cljs。
 * 维护页面内所有 Block 的关系索引（父子、兄弟排序、UUID 查找）。
 *
 * 设计要点：
 *  - 每个 Page 的 Block 以 parentId → children 的形式索引，children 按 leftId 链表排序
 *  - 所有 Block 同时存入 uuid → BlockData 的 flat map 中用于 O(1) 查找
 *  - 不存储跨页面关系（跨页面引用由 IndexStore 的引用索引处理）
 */
export class BlockTree {
  /** uuid → BlockData 平铺索引 */
  private blockMap: Map<string, BlockData> = new Map<string, BlockData>();

  /** parentId → 子 Block UUID 列表（按 leftId 链排序的数组） */
  private childrenMap: Map<string, string[]> = new Map<string, string[]>();

  /** 临时存储已从 tree 中移除但会在短时间内引用的 blocks（用于 undo） */
  private recycleBin: Map<string, BlockData> = new Map<string, BlockData>();

  // ─── 初始化 ───

  /**
   * 将一个页面的所有 Block 加载到树中。
   * 调用时机：MarkdownParser 解析完一个页面后。
   */
  loadPageBlocks(pageId: string, blocks: BlockData[]): void {
    // 清除该页面的旧数据
    this.removePageBlocks(pageId);

    // 建立 UUID 索引
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      this.blockMap.set(block.uuid, block);
    }

    // 建立父子关系索引
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      const parentId = block.parentId;
      if (!this.childrenMap.has(parentId)) {
        this.childrenMap.set(parentId, []);
      }
      const siblings = this.childrenMap.get(parentId);
      if (siblings) {
        siblings.push(block.uuid);
      }
    }

    // 按 leftId 链表排序所有 children 数组
    this.sortAllChildren();
  }

  /**
   * 清除一个页面在树中的所有数据。
   */
  removePageBlocks(pageId: string): void {
    const toRemove: string[] = [];
    this.blockMap.forEach((block: BlockData) => {
      if (block.pageId === pageId) {
        toRemove.push(block.uuid);
      }
    });
    for (let i = 0; i < toRemove.length; i++) {
      this.blockMap.delete(toRemove[i]);
    }

    // 清除 childrenMap 中以 pageId 为 parent 的条目
    this.childrenMap.delete(pageId);

    // 清除以被删 blocks 为 parent 的条目
    for (let i = 0; i < toRemove.length; i++) {
      this.childrenMap.delete(toRemove[i]);
    }
  }

  // ─── 查询 ───

  /**
   * 按 UUID 获取 Block，O(1)。
   */
  getBlock(uuid: string): BlockData | undefined {
    return this.blockMap.get(uuid);
  }

  /**
   * 获取页面的所有 Block（无序，从 flat map 中过滤）。
   */
  getPageBlocks(pageId: string): BlockData[] {
    const result: BlockData[] = [];
    this.blockMap.forEach((block: BlockData) => {
      if (block.pageId === pageId) {
        result.push(block);
      }
    });
    return result;
  }

  /**
   * 获取页面的顶层 Block（parentId = pageId）。
   */
  getTopLevelBlocks(pageId: string): BlockData[] {
    return this.getChildren(pageId);
  }

  /**
   * 获取某个 Block/Parent 的直接子节点列表（已排序）。
   */
  getChildren(parentUuid: string): BlockData[] {
    const childUuids = this.childrenMap.get(parentUuid);
    if (!childUuids) {
      return [];
    }
    const result: BlockData[] = [];
    for (let i = 0; i < childUuids.length; i++) {
      const block = this.blockMap.get(childUuids[i]);
      if (block) {
        result.push(block);
      }
    }
    return result;
  }

  /**
   * 获取 Block 在兄弟中的位置索引。
   */
  getSiblingIndex(uuid: string): number {
    const block = this.blockMap.get(uuid);
    if (!block) {
      return 0;
    }
    const siblings = this.childrenMap.get(block.parentId);
    if (!siblings) {
      return 0;
    }
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i] === uuid) {
        return i;
      }
    }
    return 0;
  }

  /**
   * 获取左侧兄弟。
   */
  getLeftSibling(uuid: string): BlockData | undefined {
    const block = this.blockMap.get(uuid);
    if (!block || block.leftId === '') {
      return undefined;
    }
    return this.blockMap.get(block.leftId);
  }

  /**
   * 获取右侧兄弟。
   */
  getRightSibling(uuid: string): BlockData | undefined {
    const block = this.blockMap.get(uuid);
    if (!block) {
      return undefined;
    }
    const siblings = this.childrenMap.get(block.parentId);
    if (!siblings) {
      return undefined;
    }
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i] === uuid && i + 1 < siblings.length) {
        return this.blockMap.get(siblings[i + 1]);
      }
    }
    return undefined;
  }

  /**
   * 判断 Block 是否有子节点。
   */
  hasChildren(uuid: string): boolean {
    const children = this.childrenMap.get(uuid);
    return children !== undefined && children.length > 0;
  }

  /**
   * 获取某个 Block 及其所有后代（DFS 遍历）。
   */
  getDescendants(uuid: string): BlockData[] {
    const result: BlockData[] = [];
    this.collectDescendants(uuid, result);
    return result;
  }

  private collectDescendants(uuid: string, result: BlockData[]): void {
    const children = this.getChildren(uuid);
    for (let i = 0; i < children.length; i++) {
      result.push(children[i]);
      this.collectDescendants(children[i].uuid, result);
    }
  }

  // ─── 写操作 ───

  /**
   * 在指定位置插入单个 Block。
   * @returns 插入的 BlockData
   */
  insertBlock(
    content: string,
    pageId: string,
    parentId: string,
    leftId: string,
    level: number
  ): BlockData {
    const uuid = UUID.generate();
    const block = createBlockData(uuid, pageId, parentId, level);
    block.content = content;
    block.leftId = leftId;

    this.blockMap.set(uuid, block);

    // 更新 children 列表
    this.addToChildrenList(parentId, uuid, leftId);

    // 如果 leftId 指向的 block 的右侧兄弟，需要更新该兄弟的 leftId
    this.updateNeighborLeftId(parentId, uuid, leftId);

    return block;
  }

  /**
   * 删除单个 Block 及其所有子 Block。
   * 被删除的 blocks 会暂存到 recycleBin 中（供 undo 使用）。
   */
  deleteBlock(uuid: string): BlockData[] {
    const block = this.blockMap.get(uuid);
    if (!block) {
      return [];
    }

    // 收集要删除的所有 blocks（自身 + 子树）
    const toDelete = this.getDescendants(uuid);
    toDelete.push(block);

    // 从父节点的 children 列表中移除
    this.removeFromChildrenList(block.parentId, uuid);

    // 从 blockMap 中移除并存入 recycleBin
    for (let i = 0; i < toDelete.length; i++) {
      const b = toDelete[i];
      this.blockMap.delete(b.uuid);
      this.childrenMap.delete(b.uuid);
      this.recycleBin.set(b.uuid, b);
    }

    return toDelete;
  }

  /**
   * 移动 Block 到新位置。
   */
  moveBlock(uuid: string, newParentId: string, newLeftId: string, newLevel: number): void {
    const block = this.blockMap.get(uuid);
    if (!block) {
      return;
    }

    // 从旧位置移除
    this.removeFromChildrenList(block.parentId, uuid);
    this.updateNeighborLeftId(block.parentId, '', uuid);

    // 更新位置信息
    const oldParentId = block.parentId;
    block.parentId = newParentId;
    block.leftId = newLeftId;
    block.level = newLevel;

    // 递归更新子 Block 的 level
    const descendants = this.getDescendants(uuid);
    const levelDelta = newLevel - block.level;
    for (let i = 0; i < descendants.length; i++) {
      descendants[i].level = descendants[i].level + levelDelta;
    }

    // 添加到新位置
    this.addToChildrenList(newParentId, uuid, newLeftId);
    this.updateNeighborLeftId(newParentId, uuid, newLeftId);
  }

  /**
   * 更新 Block 内容。
   */
  updateBlock(uuid: string, content: string): void {
    const block = this.blockMap.get(uuid);
    if (block) {
      block.content = content;
      block.updatedAt = Date.now();
    }
  }

  /**
   * 设置 Block 折叠状态。
   */
  setCollapsed(uuid: string, collapsed: boolean): void {
    const block = this.blockMap.get(uuid);
    if (block) {
      block.collapsed = collapsed;
    }
  }

  // ─── 辅助 ───

  /**
   * 将所有 children 列表按 leftId 链表排序。
   */
  private sortAllChildren(): void {
    this.childrenMap.forEach((_uuids: string[], parentId: string) => {
      this.sortChildrenList(parentId);
    });
  }

  /**
   * 按 leftId 链对单个 children 列表排序。
   */
  private sortChildrenList(parentId: string): void {
    const uuids = this.childrenMap.get(parentId);
    if (!uuids || uuids.length <= 1) {
      return;
    }

    // 找到第一个 block (leftId = '')
    const sorted: string[] = [];
    const remaining = new Map<string, string>();
    for (let i = 0; i < uuids.length; i++) {
      const block = this.blockMap.get(uuids[i]);
      if (block) {
        remaining.set(block.leftId, uuids[i]);
      }
    }

    let leftId = '';
    while (remaining.has(leftId)) {
      const uuid = remaining.get(leftId);
      if (uuid) {
        sorted.push(uuid);
        remaining.delete(leftId);
        leftId = uuid;
      } else {
        break;
      }
    }

    // 追加剩余（以防 leftId 链破损）
    remaining.forEach((uuid: string) => {
      sorted.push(uuid);
    });

    this.childrenMap.set(parentId, sorted);
  }

  /**
   * 将 uuid 添加到 parentId 的 children 列表中指定位置。
   */
  private addToChildrenList(parentId: string, uuid: string, leftId: string): void {
    if (!this.childrenMap.has(parentId)) {
      this.childrenMap.set(parentId, []);
    }
    const siblings = this.childrenMap.get(parentId);
    if (!siblings) {
      return;
    }

    // 找到 leftId 在列表中的位置，插入其后
    if (leftId === '') {
      siblings.unshift(uuid);
    } else {
      let inserted = false;
      for (let i = 0; i < siblings.length; i++) {
        if (siblings[i] === leftId) {
          siblings.splice(i + 1, 0, uuid);
          inserted = true;
          break;
        }
      }
      if (!inserted) {
        siblings.push(uuid);
      }
    }
  }

  /**
   * 从 parentId 的 children 列表中移除 uuid。
   */
  private removeFromChildrenList(parentId: string, uuid: string): void {
    const siblings = this.childrenMap.get(parentId);
    if (!siblings) {
      return;
    }
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i] === uuid) {
        siblings.splice(i, 1);
        break;
      }
    }
  }

  /**
   * 更新被插入 block 右侧兄弟的 leftId。
   * 原来 leftId = leftId 的兄弟现在应该 leftId = uuid。
   */
  private updateNeighborLeftId(parentId: string, newUuid: string, leftId: string): void {
    if (newUuid === '') {
      return;
    }
    const siblings = this.childrenMap.get(parentId);
    if (!siblings) {
      return;
    }
    for (let i = 0; i < siblings.length; i++) {
      if (siblings[i] === newUuid) {
        continue;
      }
      const block = this.blockMap.get(siblings[i]);
      if (block && block.leftId === leftId && block.uuid !== newUuid) {
        block.leftId = newUuid;
        break;
      }
    }
  }

  /**
   * 清空回收站（undo 栈满时调用）。
   */
  clearRecycleBin(): void {
    this.recycleBin.clear();
  }

  /**
   * 从回收站恢复 Block（undo 操作）。
   */
  restoreFromRecycleBin(uuid: string): BlockData | undefined {
    const block = this.recycleBin.get(uuid);
    if (block) {
      this.recycleBin.delete(uuid);
      this.blockMap.set(uuid, block);
      this.addToChildrenList(block.parentId, uuid, block.leftId);
    }
    return block;
  }
}
