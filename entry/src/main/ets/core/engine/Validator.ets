import { OutlinerOp } from './OutlinerOps';
import { BlockTree } from './BlockTree';
import { BlockData } from '../models/Block';

/**
 * Validator — 操作验证器。
 *
 * 在执行 OutlinerOp 之前验证操作合法性。
 * 对应 Logseq outliner/validate.cljs (378行)。
 */
export class Validator {

  /**
   * 验证插入操作。
   */
  static validateInsert(
    blockTree: BlockTree,
    pageId: string,
    parentId: string,
    _leftId: string,
    _level: number
  ): string | undefined {
    // 顶层块的 parentId 即所属页面（见 Block.parentId 语义）；页面不是 Block，
    // 不在 BlockTree 中，必须直接放行。
    // ⚠️ 早期实现用「父 ID 长度 < 36」识别页面 UUID，但 UUID.generate() 产生的
    // 页面 UUID 同样是 36 位，该短路分支永不命中 → **顶层块插入永远被判
    // Parent block not found**。此前 OutlinerEngine.execute 未接 Validator，
    // 缺陷一直潜伏；M0 单测将其暴露。
    if (parentId === pageId || parentId === '') {
      return undefined;
    }
    const parent = blockTree.getBlock(parentId);
    if (!parent) {
      return 'Parent block not found';
    }
    return undefined;
  }

  /**
   * 验证删除操作。
   */
  static validateDelete(blockTree: BlockTree, uuid: string): string | undefined {
    const block = blockTree.getBlock(uuid);
    if (!block) {
      return 'Block not found';
    }
    return undefined;
  }

  /**
   * 验证移动操作。
   */
  static validateMove(
    blockTree: BlockTree,
    uuid: string,
    newParentId: string,
    newLevel: number
  ): string | undefined {
    const block = blockTree.getBlock(uuid);
    if (!block) {
      return 'Block not found';
    }
    // 不能移动到自己的子节点下
    if (newParentId === uuid) {
      return 'Cannot move a block into itself';
    }
    // 检查循环引用：newParent 不能是 uuid 的后代
    if (newParentId.length === 36) {
      const descendants = blockTree.getDescendants(uuid);
      for (let i = 0; i < descendants.length; i++) {
        if (descendants[i].uuid === newParentId) {
          return 'Cannot move a block into its own descendant';
        }
      }
    }
    // level 必须 >= 0
    if (newLevel < 0) {
      return 'Level cannot be negative';
    }
    return undefined;
  }

  /**
   * 验证缩进操作。
   */
  static validateIndent(blockTree: BlockTree, uuid: string): string | undefined {
    const block = blockTree.getBlock(uuid);
    if (!block) {
      return 'Block not found';
    }
    const leftSibling = blockTree.getLeftSibling(uuid);
    if (!leftSibling) {
      return 'Cannot indent: block is the first child';
    }
    return undefined;
  }

  /**
   * 验证反缩进操作。
   */
  static validateOutdent(blockTree: BlockTree, uuid: string): string | undefined {
    const block = blockTree.getBlock(uuid);
    if (!block) {
      return 'Block not found';
    }
    if (block.level <= 0) {
      return 'Cannot outdent: already at top level';
    }
    return undefined;
  }

  /**
   * 验证任意操作。
   */
  static validate(blockTree: BlockTree, op: OutlinerOp): string | undefined {
    if (op.type === 'insert-block') {
      return Validator.validateInsert(blockTree, op.pageId, op.parentId, op.leftId, op.level);
    }
    if (op.type === 'delete-block') {
      return Validator.validateDelete(blockTree, op.uuid);
    }
    if (op.type === 'move-block') {
      return Validator.validateMove(blockTree, op.uuid, op.newParentId, op.newLevel);
    }
    if (op.type === 'indent') {
      return Validator.validateIndent(blockTree, op.uuid);
    }
    if (op.type === 'outdent') {
      return Validator.validateOutdent(blockTree, op.uuid);
    }
    return undefined;
  }
}
