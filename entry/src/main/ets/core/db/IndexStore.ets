import { PageData } from '../models/Page';
import { BlockData } from '../models/Block';
import { MarkdownParser } from '../parser/MarkdownParser';

/**
 * IndexStore — 倒排索引系统。
 *
 * 维护三种索引以支持高效的页面查找和引用解析：
 *  1. 页面名索引：lowercase name → page UUID
 *  2. 标签索引：tag → page UUID 列表
 *  3. 引用索引：被引用的页面名 → 引用它的 Block 信息列表（反向链接）
 *
 * 对应 Logseq db/model.cljs (DataScript 查询层) + worker/search.cljs。
 */
export class IndexStore {
  // name → pageUuid（一个 name 可能对应多个 page，取最新）
  private pageNameIndex: Map<string, string> = new Map<string, string>();

  // tag → pageUuid[] （倒排）
  private tagIndex: Map<string, string[]> = new Map<string, string[]>();

  // 反向链接索引：被引用页面名 → BacklinkEntry[]
  private backlinkIndex: Map<string, BacklinkEntry[]> = new Map<string, BacklinkEntry[]>();

  // pageUuid → PageData（快速查找）
  private pageMap: Map<string, PageData> = new Map<string, PageData>();

  // blockUuid → BlockData + 所属 pageUuid
  private blockPageIndex: Map<string, string> = new Map<string, string>();

  // ─── 页面索引 ───

  clear(): void {
    this.pageNameIndex.clear();
    this.tagIndex.clear();
    this.backlinkIndex.clear();
    this.pageMap.clear();
    this.blockPageIndex.clear();
  }

  addPage(page: PageData): void {
    this.pageMap.set(page.uuid, page);
    this.pageNameIndex.set(page.name.toLowerCase(), page.uuid);

    // 别名也加入名称索引
    for (let i = 0; i < page.aliases.length; i++) {
      this.pageNameIndex.set(page.aliases[i].toLowerCase(), page.uuid);
    }

    // 标签索引
    this.updateTagIndex(page);
  }

  removePage(pageUuid: string): void {
    const page = this.pageMap.get(pageUuid);
    if (page) {
      this.pageNameIndex.delete(page.name.toLowerCase());
      for (let i = 0; i < page.aliases.length; i++) {
        this.pageNameIndex.delete(page.aliases[i].toLowerCase());
      }
    }
    this.pageMap.delete(pageUuid);

    // 清理标签索引中的该页面
    this.tagIndex.forEach((uuids: string[], tag: string) => {
      const filtered: string[] = [];
      for (let i = 0; i < uuids.length; i++) {
        if (uuids[i] !== pageUuid) {
          filtered.push(uuids[i]);
        }
      }
      this.tagIndex.set(tag, filtered);
    });
  }

  private updateTagIndex(page: PageData): void {
    for (let i = 0; i < page.tags.length; i++) {
      const tag = page.tags[i];
      if (!this.tagIndex.has(tag)) {
        this.tagIndex.set(tag, []);
      }
      const uuids = this.tagIndex.get(tag);
      if (uuids) {
        const found = uuids.findIndex((u) => u === page.uuid);
        if (found === -1) {
          uuids.push(page.uuid);
        }
      }
    }
  }

  getPage(uuid: string): PageData | undefined {
    return this.pageMap.get(uuid);
  }

  getPageByName(name: string): PageData | undefined {
    const uuid = this.pageNameIndex.get(name.toLowerCase());
    if (!uuid) {
      return undefined;
    }
    return this.pageMap.get(uuid);
  }

  getAllPages(): PageData[] {
    const result: PageData[] = [];
    this.pageMap.forEach((page: PageData) => {
      result.push(page);
    });
    return result;
  }

  getPagesByTag(tag: string): PageData[] {
    const uuids = this.tagIndex.get(tag);
    if (!uuids) {
      return [];
    }
    const result: PageData[] = [];
    for (let i = 0; i < uuids.length; i++) {
      const page = this.pageMap.get(uuids[i]);
      if (page) {
        result.push(page);
      }
    }
    return result;
  }

  getAllTags(): string[] {
    const result: string[] = [];
    this.tagIndex.forEach((_uuids: string[], tag: string) => {
      result.push(tag);
    });
    return result;
  }

  /**
   * 搜索页面（按名称前缀匹配）。
   */
  searchPages(query: string): PageData[] {
    const lower = query.toLowerCase();
    const result: PageData[] = [];
    this.pageNameIndex.forEach((uuid: string, name: string) => {
      if (name.startsWith(lower) || name.indexOf(lower) !== -1) {
        const page = this.pageMap.get(uuid);
        if (page) {
          const found = result.findIndex((p) => p.uuid === page.uuid);
          if (found === -1) {
            result.push(page);
          }
        }
      }
    });
    return result;
  }

  // ─── Block→Page 索引 ───

  indexBlock(blockUuid: string, pageUuid: string): void {
    this.blockPageIndex.set(blockUuid, pageUuid);
  }

  indexBlocks(blocks: BlockData[]): void {
    for (let i = 0; i < blocks.length; i++) {
      this.blockPageIndex.set(blocks[i].uuid, blocks[i].pageId);
    }
  }

  removeBlock(blockUuid: string): void {
    this.blockPageIndex.delete(blockUuid);
  }

  getPageUuidForBlock(blockUuid: string): string | undefined {
    return this.blockPageIndex.get(blockUuid);
  }

  // ─── 引用索引（反向链接） ───

  /**
   * 注册一个引用关系：sourceBlockId 引用了 targetName（页面或 Block）。
   */
  addReference(sourceBlockId: string, targetName: string, isBlockRef: boolean): void {
    if (!this.backlinkIndex.has(targetName)) {
      this.backlinkIndex.set(targetName, []);
    }
    const entries = this.backlinkIndex.get(targetName);
    if (entries) {
      const found = entries.findIndex(
        (e) => e.sourceBlockId === sourceBlockId && e.isBlockRef === isBlockRef
      );
      if (found === -1) {
        const entry: BacklinkEntry = {
          sourceBlockId: sourceBlockId,
          targetName: targetName,
          isBlockRef: isBlockRef
        };
        entries.push(entry);
      }
    }
  }

  /**
   * 获取某个页面/Block 的反向链接列表。
   */
  getBacklinks(targetName: string): BacklinkEntry[] {
    const entries = this.backlinkIndex.get(targetName);
    if (!entries) {
      return [];
    }
    return entries;
  }

  /**
   * S3-W1：把**单个块**的引用条目折进索引 —— 编辑路径上的增量更新点。
   *
   * 与 `reindexPageReferences` 的分工：
   *   · 本方法 = 「**只有一个块**的内容变了」时的最小更新（块级入口）；
   *   · `reindexPageReferences` = 整页对账（落盘链路挂点），内部逐块委托给本方法
   *     ⇒ 内容没变的块被快照短路，不会做正则扫描。
   *
   * 为什么必须「先清后加」：`backlinkIndex` 是按目标名聚合的 **Map**，
   * `addReference` 只做去重追加、**没有任何删除语义**。内容里删掉 `[[x]]` 后若只重加，
   * 旧条目会永远留在索引里 ⇒ 反链只增不减（正是本窗口要修的 W12-3 另一半）。
   *
   * 数据来源改为**从 `content` 现算**，不再读 `block.refs` / `block.blockRefs`：
   * 那两个数组由 `MarkdownParser.parse` 在落盘→重新载入时才刷新，编辑期间是陈旧快照
   * （见 `BlockData.contentIndexed` 的注释）。现算是为了让「索引所见」= 「正文实际内容」。
   *
   * 复杂度：O(该块 content 长度 + 该块新引用数 × 同目标条目数)，外加
   * `removeBlockReferences` 的「无条目即早退」（见其注释）。
   * **与该页/全库的块数无关** —— 打字路径上每次落盘只对「内容真的变了」的块收费。
   *
   * ⚠️ 快照短路的**含义**必须记牢：`contentIndexed === content` 断言的是
   *   「这个 content 的条目**此刻确实在索引里**」。
   *   ⇒ 因此**任何摘除条目的地方都必须同时把快照打回空串**
   *     （`reindexPageReferences` 第 ④ 步、`OutlinerEngine.invalidateDeletedRefs`），
   *     否则「条目被摘了、重建又被跳过」⇒ 反链静默消失（离线探针实测踩到过 ✗）。
   */
  reindexBlockReferences(block: BlockData): void {
    if (block.contentIndexed === block.content) {
      return; // 该内容已经折进索引过：零扫描、零变更
    }
    // 旧条目按「本块曾登记过的目标名」定点摘除（按 sourceBlockId 扫该目标名下的数组）
    this.removeBlockReferences(block.uuid);
    const refs = MarkdownParser.extractPageRefs(block.content);
    const blockRefs = MarkdownParser.extractBlockRefs(block.content);
    for (let i = 0; i < refs.length; i++) {
      this.addReference(block.uuid, refs[i], false);
    }
    for (let j = 0; j < blockRefs.length; j++) {
      this.addReference(block.uuid, blockRefs[j], true);
    }
    // 回写块自身的派生字段，使 GraphView / GraphLayout 等处读到的 refs 与正文一致
    block.refs = refs;
    block.blockRefs = blockRefs;
    block.contentIndexed = block.content;
  }

  /**
   * S3-W1：整页引用索引对账 —— 落盘链路上的挂点。
   *
   * 五步（顺序不可交换）：
   *  ① **定「本页相关」范围**：当前块 ∪ `blockPageIndex` 里仍归属本页的块。
   *     并集不可省 —— 整页换代（`replacePageBlocks`）后块 uuid 全换新，
   *     旧块只能从 `blockPageIndex` 里认出来（详见方法内注释）。
   *  ② **定「本页当前」范围**：只用 `blocks`。
   *  ③ **清场**：摘两类失效条目 ——
   *     ㈠ 悬空（源块已不在树里）；㈡ 本页相关但**已不在当前 `blocks`**（被删/被换代）。
   *     **活着的块条目一律保留** ⇒ 这是「增量」的来源：不会每次落盘都重建整页。
   *  ④ **作废被摘除条目对应块的快照**（不变量：条目没了 ⇒ 「已索引」必须失效）。
   *  ⑤ **刷新本页活块**：`reindexBlockReferences` 只对 `contentIndexed !== content`
   *     的块动手 ⇒ 内容没变的块**正则扫描次数为 0**。
   *
   * 复杂度：O(全局反链条目总数) —— 这是清场那一遍的固有成本，与库规模成正比、
   *   与页面大小无关；**正则只与「本次真正改动过的块数」成正比**。
   *   对照旧实现（逐块 `addReference` 且无内容短路）在「N 块引同一目标」下会退化
   *   成 Σᵢ i = O(N²)（每加一条都要 `findIndex` 扫已累积的同目标数组）。
   * 实测（受控离线探针 Ⓒ：`w1_cost_probe3.js`，1000 块页，宿主 Node，**非设备数据** ✗）：
   *   | 输入 | 引用密集页（每 10 块 1 条引用） | 全纯文本页 |
   *   |---|---|---|
   *   | 首次对账（全部未索引） | 1.85 ms / 扫 1000 块 | 0.32 ms / 扫 1000 块 |
   *   | 无改动再次落盘 | 0.15 ms / 扫 **0** 块 | 0.10 ms / 扫 **0** 块 |
   *   | 改 1 块正文 | 0.19 ms / 扫 **1** 块 | 0.09 ms / 扫 **1** 块 |
   *   | 改 334 块正文 | 0.57 ms / 扫 334 块 | 0.12 ms / 扫 334 块 |
   *   | 删 100 块后落盘 | 0.12 ms / 扫 0 块 | 0.06 ms / 扫 0 块 |
   *   ⇒ 最坏一档（首次对账）1.85 ms，占 A-2 后实测上界（576 ms）的 **0.32%**；
   *     稳态每轮落盘 0.06–0.19 ms。**无二次项、无随页面规模放大的项**。
   *   真机复测口径（含量法陷阱）见 `docs/S3-W1-反链索引层时效性.md` §3。
   *
   * @param pageUuid 本次落盘的页面
   * @param blocks   该页当前的全部块（`blockTree.getPageBlocks` 的结果）
   */
  reindexPageReferences(pageUuid: string, blocks: BlockData[]): void {
    if (blocks.length === 0) {
      // 页面无块（空页/新建页）：没有可重建的条目，且**不能**顺手清场 ——
      // 清场判据依赖 `blockPageIndex`，而空页的旧块可能仍留在里面（尚无落盘点触发移除）。
      return;
    }
    // ① 本页「当前 + 历史」的块 uuid 集合
    //
    // ⚠️ 为什么必须把**历史块**也收进来（只收 `blocks` 会漏掉一整类陈旧）：
    //   `DataStore.replacePageBlocks`（整页编辑器「应用并重建」/ 切 live 模式）
    //   走的是 `blockTree.loadPageBlocks` ⇒ **整页块 uuid 全部换新**，而
    //   `IndexStore.blockPageIndex` 里旧块的映射**不会**被清掉。此时若清场只认
    //   「新块集合」，旧块（已不在树里、但 blockPageIndex 仍说它属于本页）的条目
    //   会原样留下 ⇒ 反链出现**幽灵行**（页面换代后旧引用仍在）。
    //   故判据取并集：新块 ∪ `blockPageIndex` 里仍归属本页的块。
    const pageBlockUuids: Set<string> = new Set<string>();
    for (let i = 0; i < blocks.length; i++) {
      pageBlockUuids.add(blocks[i].uuid);
    }
    this.blockPageIndex.forEach((ownerPageUuid: string, blockUuid: string) => {
      if (ownerPageUuid === pageUuid) {
        pageBlockUuids.add(blockUuid);
      }
    });
    // ② 本页**当前**块集合（与 ① 的并集区别：这里只收 `blocks` 里的块）
    const livePageUuids: Set<string> = new Set<string>();
    for (let i = 0; i < blocks.length; i++) {
      livePageUuids.add(blocks[i].uuid);
    }
    // ③ 全局条目清场 + 本页**失效**条目摘除（一次遍历同时做两件事）
    //
    // 「失效」只两种，**不含「本页仍然活着的块」**：
    //   ㈠ 源块已不在树里（悬空）；
    //   ㈡ 源块仍挂在 `blockPageIndex` 的本页名下，但**已不在当前 `blocks` 里**
    //      —— 即被删除、或被整页换代换掉的那些块。
    // 活着的块条目一律**保留**（这是「增量」的关键：这一步不再无条件清空本页，
    // 否则每次落盘都要把本页引用全部重建一遍，与「防抖重建」的初衷相反）。
    // 本页活块的条目刷新由 ④ 的 `reindexBlockReferences` 负责 —— 它只在
    // `contentIndexed !== content` 时动手，内容没变的块零动作。
    const cleaned: Map<string, BacklinkEntry[]> = new Map<string, BacklinkEntry[]>();
    const invalidated: Set<string> = new Set<string>();
    this.backlinkIndex.forEach((entries: BacklinkEntry[], targetName: string) => {
      const kept: BacklinkEntry[] = [];
      for (let i = 0; i < entries.length; i++) {
        const e = entries[i];
        // ㈠ 悬空：`removeBlock` 已把它从 blockPageIndex 摘掉 ⇒ 树里没有这个块
        if (this.blockPageIndex.get(e.sourceBlockId) === undefined) {
          invalidated.add(e.sourceBlockId);
          continue;
        }
        // ㈡ 本页已失效的块（被删除 / 被换代）⇒ 摘掉，稍后不会重建
        if (pageBlockUuids.has(e.sourceBlockId) && !livePageUuids.has(e.sourceBlockId)) {
          invalidated.add(e.sourceBlockId);
          continue;
        }
        kept.push(e);
      }
      if (kept.length > 0) {
        cleaned.set(targetName, kept);
      }
    });
    this.backlinkIndex = cleaned;

    // ④ **作废被摘除条目对应块的快照** —— 不变量：条目没了 ⇒ 「已索引」必须失效
    //
    // ⚠️ 这一步不是防御性代码，而是不变量的一半（离线探针实测踩到过 ✗）：
    //   `reindexBlockReferences` 用 `contentIndexed === content` 短路，含义是
    //   「这个 content 的条目**已经在索引里**」。所以**任何摘除条目的地方，
    //   都必须同时把快照打回空串**；否则「条目被摘了、重建又被跳过」
    //   ⇒ 反链会静默消失。
    //   实测现场（探针 E，未加这一步的第一版实现）：1000 块页里第 501 块写着 `[[x]]`，
    //   第一次落盘后索引正确（1 条），**第二次落盘后条目归零** ✗。
    for (let j = 0; j < blocks.length; j++) {
      if (invalidated.has(blocks[j].uuid)) {
        blocks[j].contentIndexed = '';
      }
    }
    // 说明：`invalidated` 里的 uuid 多数**不在** `blocks` 里（已删除/已换代），
    //   它们的 `BlockData` 此刻只可能在 `recycleBin`（撤销用）——
    //   那条路径由 `OutlinerEngine.invalidateDeletedRefs` 在删除当刻作废，覆盖更全。

    // ⑤ 刷新本页活块的条目（内容没变的块在 ④ 里没被作废 ⇒ 这里零动作）
    for (let k = 0; k < blocks.length; k++) {
      this.reindexBlockReferences(blocks[k]);
    }
  }

  /**
   * 移除某个 Block 的所有引用。
   *
   * S3-W1 调整（**为什么必须改**）：原实现无论是否有条目被摘掉，都会**无条件**
   * 用一份全新 Map 覆盖 `backlinkIndex`；而它现在位于编辑/落盘的热路径上
   * （每个内容有变的块都会调一次）⇒ 「一块从没写过引用」也要付一次
   * `O(全局条目数)` 的重建。改为先计数、真的摘掉了才重建。
   *
   * 同时删掉了原先那个**纯空转**的首轮 `forEach`（它只往一个局部数组里 push，
   * 注释也自认「这里需要绕一下」，结果一个元素都没用上，纯属白扫一遍）。
   */
  removeBlockReferences(blockUuid: string): void {
    let removed = 0;
    this.backlinkIndex.forEach((entries: BacklinkEntry[], _targetName: string) => {
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].sourceBlockId === blockUuid) {
          removed++;
          return; // 该目标名下只要有一条就够，计数在下面的重建里精确处理
        }
      }
    });
    if (removed === 0) {
      return; // 本块从未登记过引用：零变更、零重建
    }
    const newBacklinks: Map<string, BacklinkEntry[]> = new Map<string, BacklinkEntry[]>();
    this.backlinkIndex.forEach((entries: BacklinkEntry[], targetName: string) => {
      const filtered: BacklinkEntry[] = [];
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].sourceBlockId !== blockUuid) {
          filtered.push(entries[i]);
        }
      }
      if (filtered.length > 0) {
        newBacklinks.set(targetName, filtered);
      }
    });
    this.backlinkIndex = newBacklinks;
  }
}

// ─── 类型 ───

export interface BacklinkEntry {
  sourceBlockId: string;
  targetName: string;
  isBlockRef: boolean; // true = block reference, false = page reference
}
