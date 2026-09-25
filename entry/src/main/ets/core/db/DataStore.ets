import { BlockData } from '../models/Block';
import { PageData, createPageData, pageNameToFileName } from '../models/Page';
import { BlockTree } from '../engine/BlockTree';
import { IndexStore } from './IndexStore';
import { MarkdownParser, ParseResult } from '../parser/MarkdownParser';
import { MarkdownExporter } from '../parser/MarkdownExporter';
import { FileRepository } from '../persistence/FileRepository';
import { UUID } from '../../utils/UUID';
import { FileFormat } from '../models/Constants';

/**
 * DataStore — 中央数据存储协调器。
 *
 * 职责：
 *  - 管理 FileRepository ↔ BlockTree ↔ IndexStore 之间的数据流
 *  - 提供页面和 Block 的 CRUD 接口
 *  - 协调文件加载和保存
 *
 * 对应 Logseq db/model.cljs (DataScript 接口层) + frontend/fs.cljs。
 */
export class DataStore {
  private blockTree: BlockTree = new BlockTree();
  private indexStore: IndexStore = new IndexStore();
  private fileRepo: FileRepository = new FileRepository();
  private initialized: boolean = false;

  // ─── 初始化 ───

  getFileRepo(): FileRepository {
    return this.fileRepo;
  }

  getBlockTree(): BlockTree {
    return this.blockTree;
  }

  getIndexStore(): IndexStore {
    return this.indexStore;
  }

  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * 加载整个 Graph，解析所有 .md 文件到内存。
   *
   * @param graphRoot Graph 根目录路径
   */
  loadGraph(graphRoot: string): void {
    this.fileRepo.setGraphRoot(graphRoot);
    this.indexStore.clear();

    const mdFiles = this.fileRepo.listMdFiles(graphRoot);
    console.info('[DataStore] Loading ' + mdFiles.length + ' .md files from ' + graphRoot);

    for (let i = 0; i < mdFiles.length; i++) {
      this.loadPageFromFile(mdFiles[i]);
    }

    this.initialized = true;
    console.info('[DataStore] Graph loaded. Pages: ' + this.indexStore.getAllPages().length);
  }

  /**
   * 从单个 .md 文件加载页面。
   */
  private loadPageFromFile(fileName: string): void {
    const fullPath = this.fileRepo.joinPath(this.fileRepo.getGraphRoot(), fileName);
    const rawText = this.fileRepo.readTextSync(fullPath);
    if (!rawText) {
      console.warn('[DataStore] Empty or unreadable file: ' + fileName);
      return;
    }

    const pageName = this.fileRepo.fileNameWithoutExt(fileName);
    const result = MarkdownParser.parse(rawText, pageName, fileName);

    // 存储 Page
    this.indexStore.addPage(result.page);

    // 存储 Blocks
    this.blockTree.loadPageBlocks(result.page.uuid, result.blocks);
    this.indexStore.indexBlocks(result.blocks);

    // 构建引用索引
    this.indexStore.rebuildReferences(result.blocks);
  }

  // ─── 页面 CRUD ───

  getPage(uuid: string): PageData | undefined {
    return this.indexStore.getPage(uuid);
  }

  getPageByName(name: string): PageData | undefined {
    return this.indexStore.getPageByName(name);
  }

  getAllPages(): PageData[] {
    return this.indexStore.getAllPages();
  }

  searchPages(query: string): PageData[] {
    return this.indexStore.searchPages(query);
  }

  /**
   * 创建新页面。
   */
  createPage(name: string, originalName: string): PageData {
    const uuid = UUID.generate();
    const page = createPageData(uuid, name, originalName);
    // 使用安全文件名转换，防止页面名包含 / .. 等造成路径穿越
    page.filePath = pageNameToFileName(name);
    this.indexStore.addPage(page);
    this.savePage(uuid);
    return page;
  }

  /**
   * O4：整页编辑器 —— 用新 Markdown 重建页面块（保留页面身份：uuid/元数据不变）。
   * 块间引用自洽（parse 新 uuid）；跨页 ((块uuid)) 引用会因重建失效（v1 已知限制）。
   */
  replacePageBlocks(pageUuid: string, markdown: string): boolean {
    const oldPage = this.indexStore.getPage(pageUuid);
    if (!oldPage) {
      return false;
    }
    const result = MarkdownParser.parse(markdown, oldPage.originalName, oldPage.filePath);
    // ⚠️ 防误删硬闸（实测缺陷）：整页编辑器切换模式会重建 RichEditor，曾导致
    // markdown 退化为空/不可解析文本，此处照常重建 → 整页块被清空并落盘（页面变
    // 0 字节）。数据层必须自保：解析结果为空而页面原本有块时，拒绝重建。
    const oldCount = this.blockTree.getPageBlocks(pageUuid).length;
    if (result.blocks.length === 0 && oldCount > 0) {
      console.error('[DataStore] replacePageBlocks refused: parsed 0 blocks, page had '
        + oldCount.toString() + ', mdLen=' + markdown.length.toString()
        + ', md=' + markdown.substring(0, 120));
      return false;
    }
    // ⚠️ 先记下解析时生成的页面 uuid，再覆盖为既有页面 uuid。
    // 必须同时改写顶层块的 parentId：MarkdownParser 用**解析时新生成的页面 uuid**
    // 作为顶层块的 parentId，而 MarkdownExporter.filterTopLevel 以
    // `parentId === page.uuid` 挑选顶层块。若只改 pageId 不改 parentId，导出时一个
    // 顶层块都选不中 → 写出 0 字节文件（实测「应用并重建」后块行数 1 → 0、页面被清空）。
    const parsedPageUuid = result.page.uuid;
    result.page.uuid = pageUuid;
    result.page.createdAt = oldPage.createdAt;
    result.page.journalDay = oldPage.journalDay;
    result.page.namespace = oldPage.namespace;
    result.page.filePath = oldPage.filePath;
    for (let i = 0; i < result.blocks.length; i++) {
      const blk = result.blocks[i];
      blk.pageId = pageUuid;
      if (blk.parentId === parsedPageUuid) {
        blk.parentId = pageUuid;
      }
    }
    this.blockTree.loadPageBlocks(pageUuid, result.blocks);
    this.indexStore.addPage(result.page);
    this.indexStore.indexBlocks(result.blocks);
    this.indexStore.rebuildReferences(result.blocks);
    this.savePage(pageUuid);
    return true;
  }

  /**
   * 删除页面（从索引和文件系统）。
   */
  deletePage(pageUuid: string): void {
    const page = this.indexStore.getPage(pageUuid);
    if (page) {
      const fullPath = this.fileRepo.joinPath(this.fileRepo.getGraphRoot(), page.filePath);
      this.fileRepo.deleteFile(fullPath);
    }
    this.blockTree.removePageBlocks(pageUuid);
    this.indexStore.removePage(pageUuid);
  }

  /**
   * 重命名页面。
   */
  renamePage(pageUuid: string, newName: string): void {
    const page = this.indexStore.getPage(pageUuid);
    if (!page) {
      return;
    }

    // 删除旧文件
    const oldPath = this.fileRepo.joinPath(this.fileRepo.getGraphRoot(), page.filePath);
    this.fileRepo.deleteFile(oldPath);

    // 更新数据
    const oldName = page.name;
    page.name = newName;
    page.originalName = newName;
    page.filePath = pageNameToFileName(newName);
    page.updatedAt = Date.now();

    // 重新索引
    this.indexStore.removePage(pageUuid);
    this.indexStore.addPage(page);

    // 引用传导更新：将所有页面的 [[oldName]] 更新为 [[newName]]
    this.propagateReferenceRename(oldName, newName);

    // 写新文件
    this.savePage(pageUuid);
  }

  /**
   * 引用传导：页面重命名时，更新所有 Block 中的 [[oldName]] 引用。
   * 对应 Logseq db/common/reference.cljs (312行)。
   */
  private propagateReferenceRename(oldName: string, newName: string): void {
    const allPages = this.indexStore.getAllPages();
    for (let pi = 0; pi < allPages.length; pi++) {
      const blocks = this.blockTree.getPageBlocks(allPages[pi].uuid);
      let pageModified = false;
      for (let bi = 0; bi < blocks.length; bi++) {
        const block = blocks[bi];
        // 检查内容中是否包含 [[oldName]]
        if (block.content.indexOf('[[' + oldName + ']]') >= 0) {
          block.content = block.content.replace(
            new RegExp('\\[\\[' + this.escapeRegexStr(oldName) + '\\]\\]', 'g'),
            '[[' + newName + ']]'
          );
          pageModified = true;
        }
      }
      if (pageModified) {
        this.savePage(allPages[pi].uuid);
      }
    }
  }

  private escapeRegexStr(str: string): string {
    let result = '';
    for (let i = 0; i < str.length; i++) {
      const ch = str.charAt(i);
      if (ch === '(' || ch === ')' || ch === '[' || ch === ']' ||
          ch === '{' || ch === '}' || ch === '.' || ch === '*' ||
          ch === '+' || ch === '?' || ch === '|' || ch === '^' ||
          ch === '$' || ch === '\\') {
        result = result + '\\' + ch;
      } else {
        result = result + ch;
      }
    }
    return result;
  }

    // ─── Block 查询 ───

  getBlock(uuid: string): BlockData | undefined {
    return this.blockTree.getBlock(uuid);
  }

  getPageBlocks(pageId: string): BlockData[] {
    return this.blockTree.getPageBlocks(pageId);
  }

  getTopLevelBlocks(pageId: string): BlockData[] {
    return this.blockTree.getTopLevelBlocks(pageId);
  }

  getChildrenOfBlock(uuid: string): BlockData[] {
    return this.blockTree.getChildren(uuid);
  }

  getPageUuidForBlock(blockUuid: string): string | undefined {
    return this.indexStore.getPageUuidForBlock(blockUuid);
  }

  // ─── 反向链接 ───

  getBacklinks(targetName: string): BacklinkInfo[] {
    const entries = this.indexStore.getBacklinks(targetName);
    const result: BacklinkInfo[] = [];
    for (let i = 0; i < entries.length; i++) {
      const block = this.blockTree.getBlock(entries[i].sourceBlockId);
      const pageUuid = this.indexStore.getPageUuidForBlock(entries[i].sourceBlockId);
      const page = pageUuid ? this.indexStore.getPage(pageUuid) : undefined;
      if (block && page) {
        const info: BacklinkInfo = {
          sourceBlockId: block.uuid,
          sourceContent: block.content.substring(0, 120),
          sourcePageName: page.originalName,
          isBlockRef: entries[i].isBlockRef
        };
        result.push(info);
      }
    }
    return result;
  }

  // ─── 标签 ───

  getPagesByTag(tag: string): PageData[] {
    return this.indexStore.getPagesByTag(tag);
  }

  getAllTags(): string[] {
    return this.indexStore.getAllTags();
  }

  // ─── 持久化 ───

  /**
   * 保存单个页面到 .md 文件。
   */
  savePage(pageUuid: string): void {
    const page = this.indexStore.getPage(pageUuid);
    if (!page) {
      return;
    }
    const blocks = this.blockTree.getPageBlocks(pageUuid);
    const markdown = MarkdownExporter.export(page, blocks);
    const fullPath = this.fileRepo.joinPath(this.fileRepo.getGraphRoot(), page.filePath);
    this.fileRepo.writeTextSync(fullPath, markdown);
    page.updatedAt = Date.now();
  }

  /**
   * 保存所有页面。
   */
  saveAll(): void {
    const pages = this.indexStore.getAllPages();
    for (let i = 0; i < pages.length; i++) {
      this.savePage(pages[i].uuid);
    }
  }
}

export interface BacklinkInfo {
  sourceBlockId: string;
  sourceContent: string;
  sourcePageName: string;
  isBlockRef: boolean;
}
