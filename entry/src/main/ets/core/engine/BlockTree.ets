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

  /**
   * uuid → 删除时的**全局序号**（单调递增，跨删除操作连续）。
   *
   * 为什么必须有它，而不能靠下标/leftId 推（W10 四次实测的结论）：
   *   撤销的正确顺序是「删除顺序的**严格逆序**」：
   *     一次 delete-block 删的是「块 + 整棵子树」，删除时是父→子，
   *     恢复必须子→父之外还要**后删的先回**，否则先回来的块找不到左邻居锚点
   *     （`addToChildrenList` 会把找不到锚点的块追加到末尾 / 或全部落到最前）。
   *   实测反例：删 2、3 后按下标排序恢复（两块下标都退化成 0）会得到
   *     [3, 2, 4, 5, …]，导出首行成了「测试块 3」；按删除序号的逆序恢复才得到
   *     [2, 3, 4, 5, …]。
   *   下标做不到这一点：删除会把右侧元素左移，后删的块下标与前一个**重叠**，
   *   信息已被破坏；序号是删除那一刻唯一没有歧义的顺序证据。
   */
  private deleteSeq: Map<string, number> = new Map<string, number>();
  /** deleteSeq 的发号器 */
  private deleteSeqCounter: number = 0;

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
   * 获取页面的**可见行序列**（顶层块 + 所有已展开子块，屏幕从上到下的顺序）。
   *
   * 为什么需要它（S1-B 之后的渲染契约）：
   *   整页大纲的宿主是 `List`，而 `ListItem` 的高度必须由内容确定。此前把「父行 + 整棵子块树」
   *   放进**同一个** ListItem（子块由 BlockChildren 行内递归渲染），List 测量该 item 时拿不到
   *   确定的内容高度，会把**整个视口高度**分给这个 item；该高度再沿 Column 链传到每个子行，
   *   子行被拉伸到数百 vp、文字被推到各自容器底部 —— 表现为「子块不渲染」。
   *   实测最小复现：两行页面 `- 父块` / `  - 子块`（子行容器 703vp、子块文字落到 y≈664）；
   *   把子行换成纯 `Text` 即恢复正常 ⇒ 拉伸由自定义组件链的高度契约触发，属结构性问题。
   *   修法：展平后每个可见行各占一个 ListItem、只含一个 BlockView ⇒ item 高度恒定。
   *
   * 折叠语义：`collapsed === true` 的块其**整棵子树**都不出现（与 BlockChildren 的
   *   `if (!child.collapsed)` 一致；折叠只影响下钻，不影响该块自身作为一行出现）。
   *   折叠态只在内存中（磁盘 .md 无该字段），故本方法**每次从当前 BlockTree 现算**，
   *   不做任何缓存 —— 缓存会让折叠/展开的结果过期。
   *
   * 顺序：先父后子、同层按 leftId 链排序（即屏幕上从上到下），
   *   因此返回值的下标可直接用作 `Scroller.scrollToIndex` 的下标（见 BlockAnchorService）。
   */
  getVisibleBlocks(pageId: string): BlockData[] {
    const result: BlockData[] = [];
    this.collectVisible(pageId, result);
    return result;
  }

  /** getVisibleBlocks 的递归体：前序 DFS，只在未折叠时下钻。 */
  private collectVisible(parentUuid: string, out: BlockData[]): void {
    const children = this.getChildren(parentUuid);
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      out.push(child);
      if (!child.collapsed) {
        this.collectVisible(child.uuid, out);
      }
    }
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
    // 修复右侧兄弟的 leftId 链：原来 leftId 指向被删块，现在指向被删块的左侧兄弟
    this.fixLeftIdOnRemoval(block.parentId, uuid, block.leftId);

    // 从 blockMap 中移除并存入 recycleBin
    for (let i = 0; i < toDelete.length; i++) {
      const b = toDelete[i];
      // 记下全局删除序号 —— 撤销时按它的**逆序**恢复即可整段无损还原
      this.deleteSeqCounter = this.deleteSeqCounter + 1;
      this.deleteSeq.set(b.uuid, this.deleteSeqCounter);
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

    // 记录旧层级，用于后续统一更新子孙层级
    const oldLevel = block.level;

    // 从旧位置移除
    this.removeFromChildrenList(block.parentId, uuid);
    // 修复旧父节点下的兄弟 leftId 链
    this.fixLeftIdOnRemoval(block.parentId, uuid, block.leftId);

    // 更新位置信息
    block.parentId = newParentId;
    block.leftId = newLeftId;
    block.level = newLevel;

    // 递归更新子 Block 的 level
    const descendants = this.getDescendants(uuid);
    const levelDelta = newLevel - oldLevel;
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
   * 按 leftId 链对单个 children 列表排序（**保证不丢节点**）。
   *
   * 早期实现以 `Map<leftId, uuid>` 为桶：同层多个节点 leftId 相同时（典型是
   * leftId 未被赋值，全为 ''）后写入覆盖先写入，链走完后剩余项已不在 Map 中，
   * 结果 childrenMap 里**只剩最后一个兄弟**，其余在树中不可达。现改为在候选池上
   * 按 uuid 标记消费，未能入链的一律按原顺序追加。
   */
  private sortChildrenList(parentId: string): void {
    const uuids = this.childrenMap.get(parentId);
    if (!uuids || uuids.length <= 1) {
      return;
    }

    const sorted: string[] = [];
    const consumed = new Set<string>();
    let leftId = '';
    let progressed = true;
    while (progressed) {
      progressed = false;
      for (let i = 0; i < uuids.length; i++) {
        const uuid = uuids[i];
        if (consumed.has(uuid)) {
          continue;
        }
        const block = this.blockMap.get(uuid);
        if (block && block.leftId === leftId) {
          sorted.push(uuid);
          consumed.add(uuid);
          leftId = uuid;
          progressed = true;
          break;
        }
      }
    }

    // 兜底：leftId 链破损的节点按原顺序补齐（绝不丢弃）
    for (let i = 0; i < uuids.length; i++) {
      if (!consumed.has(uuids[i])) {
        sorted.push(uuids[i]);
      }
    }

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
   * 删除/移走 Block 后，将其右侧兄弟的 leftId 指回被移除块的左侧兄弟。
   * 保证 leftId 链表不因删除而断裂。
   */
  private fixLeftIdOnRemoval(parentId: string, removedUuid: string, removedLeftId: string): void {
    const siblings = this.childrenMap.get(parentId);
    if (!siblings) {
      return;
    }
    for (let i = 0; i < siblings.length; i++) {
      const block = this.blockMap.get(siblings[i]);
      if (block && block.leftId === removedUuid) {
        block.leftId = removedLeftId;
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
      this.addToChildrenList(block.parentId, uuid, this.restoreAnchor(block));
      // 恢复整棵子树（删除时子孙也进入了 recycleBin）
      this.restoreDescendantsFromRecycleBin(uuid);
      // 全部插回之后再修 leftId 链（顺序见 relinkLeftIds 注释）
      this.relinkLeftIds(block.parentId);
    }
    return block;
  }

  /**
   * 计算「块回到 children 列表时应插在谁后面」—— 恢复路径的插入锚点。
   *
   * 为什么不能用 `block.leftId` 直接当锚点（W10 实测）：
   *   `addToChildrenList` 找不到锚点时**退化为追加到末尾**。撤销「删除 2 与 3」时
   *   块 2 的 leftId 指向 `__S1_long` 里根本不存在的块 1（解析阶段首个块 leftId=''）
   *   ⇒ 块 2 被追加到末尾，children 变成 [3, 4, …, 2]，导出首行成了「测试块 3」。
   *
   * 算法：沿 leftId 链**向左回溯**，取第一个「当前在树上」或「已被本次撤销恢复」的块
   *   （两者都已在 blockMap 中，故判据统一为 blockMap.has）。
   *   · 左侧邻居没被删过 ⇒ 直接命中（最常见情形）。
   *   · 左侧邻居属于同一批被删区间但**已先被恢复** ⇒ 命中它（这正是顺序要求，
   *     见 `collectRestoreRoots`：按删除序号**逆序**恢复，故左邻居总是先回来）。
   *   · 一路回溯到链头都没有 ⇒ 返回 ''，即插到列表最前（删的是整页前若干个块）。
   */
  private restoreAnchor(block: BlockData): string {
    let cursor = block.leftId;
    while (cursor !== '') {
      if (this.blockMap.has(cursor)) {
        return cursor;
      }
      const vanished = this.recycleBin.get(cursor);
      if (!vanished) {
        // 链上出现既不在树、也不在回收站的 uuid（悬空）——停止回溯，退回最前
        break;
      }
      cursor = vanished.leftId;
    }
    return '';
  }

  /**
   * 从回收站里挑出「本次撤销应当直接恢复的根块」，并给出**正确的恢复顺序**。
   *
   * 顺序 = 删除序号的**严格逆序**（后删的先回），理由（W10 多次实测的结论）：
   *   `restoreFromRecycleBin` 把块插回它左侧邻居之后（锚点见 `restoreAnchor`），
   *   而**左邻居必须先回到树上**才能当锚点。删除是从左往右做的，故逆序恢复
   *   （右 → 左）时每个块的左邻居要么从未被删、要么已经回来 —— 顺序因此自洽。
   *   实测反例：删 2、3 后若按别的顺序恢复，会得到 [3, 2, 4, 5, …] 或
   *   [4, …, 2, 3]（导出首行变成「测试块 3」）。
   *
   * 只返回根块：子孙由 `restoreFromRecycleBin` → `restoreDescendantsFromRecycleBin` 递归带回。
   * 判据用「父块是否也在这批待恢复里」——一次删除会把整棵子树一起放进回收站，
   *   故父块不在待恢复集合 ⇒ 本块是该被删单元的根。
   */
  collectRestoreRoots(uuids: string[]): string[] {
    const want = new Set<string>();
    for (let i = 0; i < uuids.length; i++) {
      if (this.recycleBin.has(uuids[i])) {
        want.add(uuids[i]);
      }
    }
    const ordered: string[] = [];
    want.forEach((uuid: string) => {
      ordered.push(uuid);
    });
    // 删除序号降序 = 后删的先恢复
    ordered.sort((a: string, b: string) => {
      return this.restoreSeqOf(b) - this.restoreSeqOf(a);
    });
    const roots: string[] = [];
    for (let i = 0; i < ordered.length; i++) {
      const block = this.recycleBin.get(ordered[i]);
      if (!block) {
        continue;
      }
      if (!want.has(block.parentId)) {
        roots.push(ordered[i]);
      }
    }
    return roots;
  }

  /**
   * 递归恢复回收站中某个 Block 的后代。
   * 修复 undo 删除时仅恢复父块、丢失子块的问题。
   */
  private restoreDescendantsFromRecycleBin(parentUuid: string): void {
    const descendants: BlockData[] = [];
    this.recycleBin.forEach((candidate: BlockData) => {
      if (candidate.parentId === parentUuid) {
        descendants.push(candidate);
      }
    });
    // 与 collectRestoreRoots 同一理由：删除序号**降序**（后删的先回），左邻居才能当锚点
    descendants.sort((a: BlockData, b: BlockData) => {
      return this.restoreSeqOf(b.uuid) - this.restoreSeqOf(a.uuid);
    });
    for (let i = 0; i < descendants.length; i++) {
      const child = descendants[i];
      this.recycleBin.delete(child.uuid);
      this.blockMap.set(child.uuid, child);
      this.addToChildrenList(parentUuid, child.uuid, this.restoreAnchor(child));
      this.restoreDescendantsFromRecycleBin(child.uuid);
    }
    // 本层全部插回之后再修链
    if (descendants.length > 0) {
      this.relinkLeftIds(parentUuid);
    }
  }

  /** 读删除序号，缺省时用 0（排序比较器用）。 */
  private restoreSeqOf(uuid: string): number {
    const seq = this.deleteSeq.get(uuid);
    return seq === undefined ? 0 : seq;
  }

  /**
   * 按 children 列表顺序把同层兄弟的 leftId 链整体重接为 `前一个兄弟`。
   *
   * 为什么需要「整体重接」而不是只接被恢复的那一块（W10 实测的两次失败教训）：
   *   删除时 `deleteBlock` 会 `fixLeftIdOnRemoval()` 把右侧兄弟的 leftId 改写为
   *   「被删块的左侧兄弟」，而恢复侧此前没有任何对应处理 ⇒ 链上跨过了被恢复的块
   *   ⇒ `sortByLeftChain`（MarkdownExporter.ets:123，getChildren 同源）走链时跳不到它，
   *   被落进「链破损兜底」分支**追加到文件末尾**。
   *   只补「右侧兄弟指回自己」也不够：`addToChildrenList` 是按**块自己那份陈旧的
   *   leftId** 找插入位的，当左侧兄弟不在列表里时就退化成「追加到末尾」——
   *   实测「撤销两次删除」后 children 列表变成 [3, (余下全部), 2]，
   *   于是导出顺序正确反而成了巧合级的结果（实测首行变成 测试块 3）。
   *
   * 事实标准（本仓既有实现给出的）：`BlockTree.sortChildrenList` 与
   *   `MarkdownExporter.sortByLeftChain` 都假设 **children 列表顺序 ≡ leftId 链顺序**
   *   （前者专门靠 leftId 链给 children 排序、后者靠链导出文件）。
   *   因此这里以**列表顺序为准**重接 leftId：`children[i].leftId = children[i-1].uuid`
   *   （首个为 ''）。这是幂等的，且只在恢复路径上调用。
   *
   * 不变量：一次删除会把「被删块及其子孙」整段从列表移除，恢复时整段插回，
   *   故列表本身仍是删除前的相对顺序 —— 重接 leftId 后链与列表一致，撤销即为无损还原。
   */
  private relinkLeftIds(parentId: string): void {
    const siblings = this.childrenMap.get(parentId);
    if (!siblings) {
      return;
    }
    for (let i = 0; i < siblings.length; i++) {
      const block = this.blockMap.get(siblings[i]);
      if (block) {
        block.leftId = i === 0 ? '' : siblings[i - 1];
      }
    }
  }
}
