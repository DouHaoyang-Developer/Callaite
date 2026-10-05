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
      // ⚠️ 原实现对所有空串直接 `return` 跳过 → **空文件对应的页面会从文件树中静默消失**
      //    （实测：未命名 4.md 内容仅 `- ` 空块、未命名 5.md 与当天的 2026-09-25.md 为
      //     0 字节，三者均未出现在侧栏文件树，用户无从察觉与恢复）。
      //    但 readTextSync 把「读取失败」也吞成空串，若无差别地建空页面，
      //    一旦随后保存就会把该文件写成 0 字节 —— 那才是真正的数据丢失。
      //    故仅当「文件确实存在且大小为 0」时才作为空页面加载。
      if (this.fileRepo.hasContent(fullPath)) {
        console.warn('[DataStore] Read failed on non-empty file, skipped: ' + fileName);
        return;
      }
      console.warn('[DataStore] Empty file, loaded as empty page: ' + fileName);
    }

    const pageName = this.fileRepo.fileNameWithoutExt(fileName);
    const result = MarkdownParser.parse(rawText, pageName, fileName);

    // 存储 Page
    this.indexStore.addPage(result.page);

    // 存储 Blocks
    this.blockTree.loadPageBlocks(result.page.uuid, result.blocks);
    this.indexStore.indexBlocks(result.blocks);

    // 构建引用索引。
    // S3-W1：改用 `reindexPageReferences`（先摘本页旧条目/悬空条目，再按当前内容重建），
    // 不再用只加不减的 `rebuildReferences`。
    // 为什么载入路径也需要「先清」：同一个页面被重新载入时（`loadGraph` 全量重载 /
    // 整页编辑器整页换代），页面的 uuid 可能被复用而**块 uuid 全部换新** ⇒
    // 旧条目会以「源块已不在索引里」的悬空形态永久留在 backlinkIndex 中（显示层靠
    // `getBacklinks` 的 `if (block && page)` 兜住，但索引自身会持续膨胀）。
    // 载入期索引为空或该页条目待重建，故两种实现结果一致，但对账版本**不会留悬空**；
    // 代价是首次载入时块的内容快照未播种 ⇒ 会做一次全页正则（仅此一次）。
    this.indexStore.reindexPageReferences(result.page.uuid, result.blocks);
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
   * S4-W27（H2 命名碰撞）：「拒绝」判据的**唯一实现**。
   *
   * 判据：`pageNameToFileName(newName)` 的结果，是否已被**除目标页自身之外**的
   * 任一已有页占用 ⇒ 是则拒绝，且**不得产生任何副作用**。
   *
   * 为什么占用集合取 `p.filePath`（而不是 `pageNameToFileName(p.name)`）：
   *   写盘那一步是 `joinPath(graphRoot, page.filePath)`（见 `savePage`）—— 也就是
   *   **会被写坏的路径就是 `filePath` 本身**，于是「判据」与「伤害」定义在同一个项上。
   *   而 `filePath ≡ pageNameToFileName(name)` 由构造保证：全仓 `filePath` 只有四个写点，
   *   逐个核对均取自同一个 `pageNameToFileName`：
   *     · `createPage`（本文件）→ `pageNameToFileName(name)`
   *     · `renamePage`（本文件）→ `pageNameToFileName(newName)`
   *     · `Page.ets` 的 `createPageData` → `pageNameToFileName(name)`
   *     · `replacePageBlocks` → 原样保留旧 `filePath`（页面名未变）
   *   ⇒ **不存在第二套 sanitize 映射**（避免「一个概念两套判据迟早分叉」）。
   *
   * ⚠️ 比较是**逐字节、大小写敏感**的全等 —— 不得 `toLowerCase()`：
   *   设备实测 `/data` 是 `ext4`（大小写敏感），`ZzCase.md` 与 `zzcase.md` 在
   *   同一目录并存且内容各异 ⇒ `A_B.md` 与 `a_b.md` 是**两个文件、不构成碰撞**。
   *   注意 `IndexStore.getPageByName` 走 `name.toLowerCase()`（页索引不敏感），
   *   那是**索引层**的同一性，与**文件层**的占用不是一回事，不可复用。
   *
   * ⚠️ Unicode 不做 NFC/NFD 归一化（`pageNameToFileName` 只特判 9 个非法 ASCII 与
   *   控制字符，其余码元原样透传）⇒ 视觉同形的 NFC/NFD 两名各占一个文件、不碰撞；
   *   而 `中文/页` 与 `中文:页` 都映射到 `中文_页.md` ⇒ 碰撞。
   *
   * @param fileName 候选文件名（必须是 pageNameToFileName 的输出）
   * @param excludeUuid 需要自我排除的页面 uuid；`createPage` 传空串（无目标页），
   *   `renamePage` 传目标页 uuid（改回自己当前的名字/文件不得被判碰撞）。
   * @returns 占用了该文件名的**其他**页面；无则 undefined。
   */
  private findFileNameOwner(fileName: string, excludeUuid: string): PageData | undefined {
    const pages = this.indexStore.getAllPages();
    for (let i = 0; i < pages.length; i++) {
      const candidate = pages[i];
      if (candidate.uuid === excludeUuid) {
        continue;
      }
      if (candidate.filePath === fileName) {
        return candidate;
      }
    }
    return undefined;
  }

  /**
   * 创建新页面。
   *
   * @returns 新建的页面；**名字碰撞被拒时返回 `undefined`**（S4-W27/H2）。
   *   调用方必须判空 —— 拒绝后页面不存在，继续取 `page.uuid` 会拿到 undefined。
   */
  createPage(name: string, originalName: string): PageData | undefined {
    // 使用安全文件名转换，防止页面名包含 / .. 等造成路径穿越
    const fileName = pageNameToFileName(name);

    // S4-W27（H2）：碰撞即拒绝，且在任何副作用之前 —— 拒绝后不留任何痕迹。
    // 新建路径没有「目标页」，故排除集为空（不存在「与自己碰撞」）。
    const owner = this.findFileNameOwner(fileName, '');
    if (owner) {
      console.error('[DataStore] createPage refused: name "' + name + '" maps to "'
        + fileName + '", already occupied by page "' + owner.originalName
        + '" (' + owner.uuid + ')');
      return undefined;
    }

    const uuid = UUID.generate();
    const page = createPageData(uuid, name, originalName);
    // 复用上面算出的结果：同一个 pageNameToFileName，只调用一次 ⇒ 两处不可能分叉。
    page.filePath = fileName;
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
    // S3-W1：原先此处单独调 `rebuildReferences(result.blocks)`（只加不减的播种路径）。
    // 整页重建会换掉全部块 uuid ⇒ 旧块在索引里的条目此时已成悬空条目，
    // 「只加不减」清不掉它们 ⇒ 反链会留下幽灵行。改由 `savePage` 内部的
    // `reindexPageReferences` 统一对账：它先摘悬空/换代的条目，再按新内容重建。
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
   *
   * @returns 是否确实改名成功。**S4-W27/H2**：原先返回 `void`，
   *   名字碰撞被拒时调用方无从得知 ⇒ 改为 `boolean`，沿用 W0 给 `savePage`
   *   建立的 `void → boolean` 上报模式（不重抛：本仓的失败通道是返回值）。
   */
  renamePage(pageUuid: string, newName: string): boolean {
    const page = this.indexStore.getPage(pageUuid);
    if (!page) {
      return false;
    }

    // ⚠️ S4-W27（H2）：碰撞判定必须**先于任何副作用**。
    //   本方法原实现是「先 deleteFile(oldPath)（见下），再算新路径」—— 若把守卫
    //   放在删除之后，一次拒绝会把该页变成**盘上无文件**，比碰撞本身更糟。
    //
    //   自我排除按 **uuid**（不是按名字）：把 `A_B` 改名为 `A:B` 时新旧文件名相同，
    //   但只要没有**别的页**占着它，就没有任何数据受损 ⇒ 放行。
    const newFilePath = pageNameToFileName(newName);
    const owner = this.findFileNameOwner(newFilePath, pageUuid);
    if (owner) {
      console.error('[DataStore] renamePage refused: "' + page.name + '" -> "' + newName
        + '" maps to "' + newFilePath + '", already occupied by page "'
        + owner.originalName + '" (' + owner.uuid + ')');
      return false;
    }

    // 删除旧文件
    const oldPath = this.fileRepo.joinPath(this.fileRepo.getGraphRoot(), page.filePath);
    this.fileRepo.deleteFile(oldPath);

    // 更新数据
    const oldName = page.name;
    page.name = newName;
    page.originalName = newName;
    page.filePath = newFilePath;
    page.updatedAt = Date.now();

    // 重新索引
    this.indexStore.removePage(pageUuid);
    this.indexStore.addPage(page);

    // 引用传导更新：将所有页面的 [[oldName]] 更新为 [[newName]]
    this.propagateReferenceRename(oldName, newName);

    // 写新文件 —— 把写盘结果一并上抛（W27：改名「有没有成」必须可观测）
    return this.savePage(pageUuid);
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

  /** 页面的可见行序列（顶层块 + 已展开子块，屏幕顺序）；见 BlockTree.getVisibleBlocks。 */
  getVisibleBlocks(pageId: string): BlockData[] {
    return this.blockTree.getVisibleBlocks(pageId);
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
   *
   * ⚠️ **S3-W1：本方法是「引用索引对账」的唯一挂点**，挂在写盘**之后**（见下）。
   *
   * @returns 是否确实写盘成功。**S4-W0/N1-a 新增**：此前返回 `void`，导致
   *   写盘失败无法上抛给 `OutlinerEngine.persistNow`（其契约本就是 boolean）。
   */
  savePage(pageUuid: string): boolean {
    const page = this.indexStore.getPage(pageUuid);
    if (!page) {
      return false;
    }
    const blocks = this.blockTree.getPageBlocks(pageUuid);
    const markdown = MarkdownExporter.export(page, blocks);
    const fullPath = this.fileRepo.joinPath(this.fileRepo.getGraphRoot(), page.filePath);
    // ⚠️ S4-W0/N1-a：这里必须拿到**真实的**写盘结果。
    //   修复前 `writeTextSync` 返回 void 且吞异常 ⇒ 本方法无条件改 updatedAt 并重索引，
    //   而下方 :361-363 的注释却断言「写失败 ⇒ 抛异常 ⇒ 对账不执行」——该前提不成立。
    //   现在：写盘未成功 ⇒ 不声称成功、不让索引先于磁盘说谎。
    const wrote: boolean = this.fileRepo.writeTextSync(fullPath, markdown);
    if (!wrote) {
      // 不更新 updatedAt、不重索引：内存与索引都保持「上一次磁盘真实值」。
      // 失败信号由 savePage 的返回值继续上抛给 OutlinerEngine.persistNow。
      return false;
    }
    page.updatedAt = Date.now();

    // ─── S3-W1：反链索引层的时效性（W12-3）───
    //
    // 为什么挂在这里：
    //  ① **覆盖完整**：`writeTextSync` 全仓只此一处调用（`FileRepository.ets:129` 是定义），
    //     而 `savePage` 又被两条落盘链共用 ——
    //       · 惰性链：`EditorService.updateBlockContent` → `OutlinerEngine.execute`
    //         → `persistForOp`（文本类只 `markDirty`，5s 兜底/失焦/切页时 flush）
    //         → `DirtyPageTracker.flushPages` → 注入回调 `OutlinerEngine.persistNow`
    //         → 本方法；
    //       · 即时链：结构性操作 `persistForOp` → `persistNow` → 本方法。
    //     所以「正文变了」与「索引对账」在**同一次落盘事务**里完成，不存在只写盘不对账的缺口。
    //  ② **时序正确**：必须在写盘**成功**之后。
    //     ⚠️ S4-W0/N1-a 更正：本段注释原先断言「写失败 ⇒ 抛异常 ⇒ 对账不执行」，
    //     而 `writeTextSync` 当时**从不抛异常**（catch 只打日志）⇒ 该安全性论证整段失效，
    //     实际发生的正是它宣称要避免的「**索引先于磁盘说谎**」。
    //     现在该不变量由 `:352-356` 的 `if (!wrote) return false;` **真正兑现**。
    //  ③ **不额外引入计时器**：`flushNow` 本身就是事件驱动 + 5s 硬截止的防抖器
    //     （`DirtyPageTracker.armTimer` 刻意**不顺延**，见其注释）。在它内部再套一层
    //     setTimeout 只会把索引的陈旧窗口从「写盘时刻」推迟到「写盘后 N ms」，
    //     代价是新增一个需要与脏页集合/生命周期对齐的状态 —— 收益为零。
    //     **本挂点拿到的防抖间隔 = 既有 5000ms 硬截止**（真机需实测该间隔下的成本，
    //     量法与判据见 `docs/S3-W1-反链索引层时效性.md` §3）。
    //
    // 为什么是「对账」而不是再调一次 `rebuildReferences`：
    //   `rebuildReferences` 是**只加不减**的（`addReference` 无删除语义）⇒ 直接复用会让
    //   反链只增不减（W12-3 的另一半：删掉 `[[x]]` 后反链不消失）。
    //   详见 `IndexStore.reindexPageReferences` 的复杂度与清场规则。
    //
    // 容错：索引对账失败绝不能连累「内容已经写进磁盘」这个事实 —— 写盘成功即算成功，
    //   索引是**派生数据**，下一次落盘会重新对账（内容快照不匹配 ⇒ 自动重算）。
    try {
      this.indexStore.reindexPageReferences(pageUuid, blocks);
    } catch (e) {
      console.error('[DataStore] reindexPageReferences failed for page ' + pageUuid
        + ': ' + JSON.stringify(e));
    }
    return true;
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
