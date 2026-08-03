import { PageData } from '../models/Page';
import { BlockData } from '../models/Block';

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
   * 重建引用索引（页面加载时调用，扫描所有 blocks）。
   */
  rebuildReferences(blocks: BlockData[]): void {
    for (let i = 0; i < blocks.length; i++) {
      const block = blocks[i];
      // 页面引用
      for (let j = 0; j < block.refs.length; j++) {
        this.addReference(block.uuid, block.refs[j], false);
      }
      // Block 引用
      for (let k = 0; k < block.blockRefs.length; k++) {
        this.addReference(block.uuid, block.blockRefs[k], true);
      }
    }
  }

  /**
   * 移除某个 Block 的所有引用。
   */
  removeBlockReferences(blockUuid: string): void {
    this.backlinkIndex.forEach((entries: BacklinkEntry[], _targetName: string) => {
      const filtered: BacklinkEntry[] = [];
      for (let i = 0; i < entries.length; i++) {
        if (entries[i].sourceBlockId !== blockUuid) {
          filtered.push(entries[i]);
        }
      }
      // 注意：forEach 中不能直接修改 map，这里需要绕一下
    });
    // 简化：遍历并重建
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
