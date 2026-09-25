import { describe, it, expect } from '@ohos/hypium';
import { BlockTree } from '../main/ets/core/engine/BlockTree';
import { Validator } from '../main/ets/core/engine/Validator';
import { createBlockData, BlockData } from '../main/ets/core/models/Block';
import { UUID } from '../main/ets/utils/UUID';

/**
 * T2（优化方案 v2 §七 任务卡）：大纲引擎 BlockTree + Validator 操作安全网。
 *
 * 覆盖：树的载入与层级查询、插入/更新/折叠、删除子树与回收站、
 *       移动、以及 Validator 的**循环引用负例**（移动父节点到自己的后代下必须被拒绝）。
 * 覆盖范围对应 v2 中「OutlinerEngine 17 种操作各 1 正例 + 循环引用负例」中
 * 可在纯逻辑层验证的部分（OutlinerEngine 本身依赖 DataStore，需设备侧测试）。
 */

interface TreeFixture {
  tree: BlockTree;
  pageId: string;
  aId: string;    // 顶层 A
  a1Id: string;   // A 的子节点 A1
  bId: string;    // 顶层 B
}

/**
 * 构造夹具：pageId ├─ A ─ A1
 *                     └─ B
 * A1 的 leftId 显式指向 A（getLeftSibling 依赖 leftId 字段）。
 */
function makeFixture(): TreeFixture {
  const tree: BlockTree = new BlockTree();
  const pageId: string = UUID.generate();

  const a: BlockData = createBlockData(UUID.generate(), pageId, pageId, 0);
  a.content = 'A';

  const a1: BlockData = createBlockData(UUID.generate(), pageId, a.uuid, 1);
  a1.content = 'A1';
  a1.leftId = a.uuid;

  const b: BlockData = createBlockData(UUID.generate(), pageId, pageId, 0);
  b.content = 'B';
  b.leftId = a.uuid;

  tree.loadPageBlocks(pageId, [a, a1, b]);

  const fx: TreeFixture = { tree: tree, pageId: pageId, aId: a.uuid, a1Id: a1.uuid, bId: b.uuid };
  return fx;
}

export default function outlinerCoreTest() {
  describe('大纲引擎 BlockTree / Validator 操作', () => {

    it('载入：顶层块与子节点层级正确', 0, () => {
      const fx = makeFixture();
      expect(fx.tree.getTopLevelBlocks(fx.pageId).length).assertEqual(2);
      expect(fx.tree.getChildren(fx.aId).length).assertEqual(1);
      expect(fx.tree.getChildren(fx.aId)[0].uuid).assertEqual(fx.a1Id);
      expect(fx.tree.getChildren(fx.a1Id).length).assertEqual(0);
      expect(fx.tree.getPageBlocks(fx.pageId).length).assertEqual(3);
    });

    it('查询：hasChildren / getDescendants / getSiblingIndex', 0, () => {
      const fx = makeFixture();
      expect(fx.tree.hasChildren(fx.aId)).assertTrue();
      expect(fx.tree.hasChildren(fx.a1Id)).assertFalse();
      expect(fx.tree.getDescendants(fx.aId).length).assertEqual(1);
      expect(fx.tree.getDescendants(fx.a1Id).length).assertEqual(0);
      expect(fx.tree.getBlock(fx.bId)!.content).assertEqual('B');
      expect(fx.tree.getBlock('not-exist-uuid') === undefined).assertTrue();
    });

    it('插入：新块追加到指定位置并成为右侧兄弟', 0, () => {
      const fx = makeFixture();
      const c: BlockData = fx.tree.insertBlock('C', fx.pageId, fx.pageId, fx.bId, 0);
      expect(c.content).assertEqual('C');
      expect(c.pageId).assertEqual(fx.pageId);
      expect(c.parentId).assertEqual(fx.pageId);
      expect(fx.tree.getTopLevelBlocks(fx.pageId).length).assertEqual(3);
      // B 的右侧兄弟应变为 C
      const right = fx.tree.getRightSibling(fx.bId);
      expect(right !== undefined).assertTrue();
      expect(right!.uuid).assertEqual(c.uuid);
    });

    it('更新：updateBlock 改写内容并刷新 updatedAt', 0, () => {
      const fx = makeFixture();
      const before: number = fx.tree.getBlock(fx.aId)!.updatedAt;
      fx.tree.updateBlock(fx.aId, 'A-改');
      const after: BlockData = fx.tree.getBlock(fx.aId)!;
      expect(after.content).assertEqual('A-改');
      expect(after.updatedAt >= before).assertTrue();
    });

    it('折叠：setCollapsed 仅影响目标块', 0, () => {
      const fx = makeFixture();
      fx.tree.setCollapsed(fx.aId, true);
      expect(fx.tree.getBlock(fx.aId)!.collapsed).assertTrue();
      expect(fx.tree.getBlock(fx.bId)!.collapsed).assertFalse();
      // 折叠不改变树结构
      expect(fx.tree.getChildren(fx.aId).length).assertEqual(1);
    });

    it('删除：删除父块连带整棵子树，且块从索引消失', 0, () => {
      const fx = makeFixture();
      const removed: BlockData[] = fx.tree.deleteBlock(fx.aId);
      expect(removed.length).assertEqual(2);          // A + A1
      expect(fx.tree.getBlock(fx.aId) === undefined).assertTrue();
      expect(fx.tree.getBlock(fx.a1Id) === undefined).assertTrue();
      expect(fx.tree.getTopLevelBlocks(fx.pageId).length).assertEqual(1);
      expect(fx.tree.getBlock(fx.bId) !== undefined).assertTrue();
    });

    it('移动：moveBlock 改写父节点与层级', 0, () => {
      const fx = makeFixture();
      // 把顶层 B 移到 A 之下
      fx.tree.moveBlock(fx.bId, fx.aId, fx.a1Id, 1);
      const moved: BlockData = fx.tree.getBlock(fx.bId)!;
      expect(moved.parentId).assertEqual(fx.aId);
      expect(moved.level).assertEqual(1);
      expect(fx.tree.getChildren(fx.aId).length).assertEqual(2);
      expect(fx.tree.getTopLevelBlocks(fx.pageId).length).assertEqual(1);
    });

    it('校验负例：未知块被拒绝', 0, () => {
      const fx = makeFixture();
      expect(Validator.validateDelete(fx.tree, 'ghost-uuid')).assertEqual('Block not found');
      expect(Validator.validateOutdent(fx.tree, 'ghost-uuid')).assertEqual('Block not found');
    });

    it('校验负例：移动到自身被拒绝', 0, () => {
      const fx = makeFixture();
      expect(Validator.validateMove(fx.tree, fx.aId, fx.aId, 1))
        .assertEqual('Cannot move a block into itself');
    });

    it('校验负例【核心】：循环引用 —— 父节点不得移入自己的后代', 0, () => {
      const fx = makeFixture();
      // A1 是 A 的后代，把 A 移到 A1 之下必须被拒绝（否则树将成环）
      expect(Validator.validateMove(fx.tree, fx.aId, fx.a1Id, 2))
        .assertEqual('Cannot move a block into its own descendant');
    });

    it('校验负例：非法层级与未知父节点被拒绝', 0, () => {
      const fx = makeFixture();
      expect(Validator.validateMove(fx.tree, fx.aId, fx.pageId, -1))
        .assertEqual('Level cannot be negative');
      // 36 位但树中不存在的父节点
      expect(Validator.validateInsert(fx.tree, fx.pageId, UUID.generate(), '', 0))
        .assertEqual('Parent block not found');
      // 短 ID 视为 page UUID，跳过父检查
      expect(Validator.validateInsert(fx.tree, fx.pageId, fx.pageId, '', 0) === undefined).assertTrue();
    });

    it('校验正负例：缩进与反缩进', 0, () => {
      const fx = makeFixture();
      // A1 的 leftId 指向 A → 允许缩进
      expect(Validator.validateIndent(fx.tree, fx.a1Id) === undefined).assertTrue();
      // B 的 leftId 也指向 A → 允许缩进
      expect(Validator.validateIndent(fx.tree, fx.bId) === undefined).assertTrue();
      // 反缩进：A1（level 1）允许，A（level 0）拒绝
      expect(Validator.validateOutdent(fx.tree, fx.a1Id) === undefined).assertTrue();
      expect(Validator.validateOutdent(fx.tree, fx.aId))
        .assertEqual('Cannot outdent: already at top level');
    });
  });
}
