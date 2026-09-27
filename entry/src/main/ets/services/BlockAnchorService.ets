import { BlockData } from '../core/models/Block';
import { PageData } from '../core/models/Page';
import { WorkspaceService } from './WorkspaceService';
import { AppState } from '../state/AppState';
import { JournalService } from './JournalService';
import { promptAction } from '@kit.ArkUI';
import { t } from '../utils/i18n';

/**
 * BlockAnchorService — U2.1a 块定位跳转（渲染层可寻址化）。
 *
 * ─── 渲染序列的真实构成（读代码核验，非假设）───
 * 整页大纲分支：`BlockList.ets:190-222`
 *   List({ space: 0, scroller })            ← 唯一的滚动容器，Scroller 由 ContentArea 注入
 *     └ LazyForEach(this.dataSource, ...)   ← BlockList.ets:200
 *         └ ListItem()                      ← BlockList.ets:201
 *             └ Column { BlockView; if (!collapsed) BlockChildren }  ← BlockList.ets:202-210
 * 数据源：`BlockList.ets:16-51` BlockDataSource，内容由 `refreshBlocks()`（BlockList.ets:128-137）
 *   写入 `WorkspaceService.getPageBlocks(page.uuid)` = `DataStore.getTopLevelBlocks`
 *   = `BlockTree.getChildren(pageId)` —— **只有顶层块（parentId === pageId）**。
 *
 * 关键结论（U2.1a 下标正确性的依据）：
 *   1. 子块**不是** List 的行。`BlockChildren`（BlockChildren.ets:54-69）在同一个 ListItem 的
 *      Column 内部用 `ForEach` 递归渲染，属于该行的**行内内容**，不占用 List 下标。
 *   2. 因此 List 下标空间 = [0, N-1] 对应 dataSource 的 N 个顶层块，
 *      下标 N 是尾部 `AddBlockButton` 的 ListItem（BlockList.ets:217-221）。
 *      （blocks 为空时 [0] 是空态 ListItem，与定位无关。）
 *   3. 折叠态**不会**让顶层块下标漂移：`if (!block.collapsed)`（BlockList.ets:206）只决定该行
 *      内部是否渲染 BlockChildren，行本身永远存在。折叠只让**祖先折叠的块完全不被渲染**。
 *   4. 所以「uuid → 下标」的规则是：沿 parentId 上溯到根块，取根块在
 *      `getPageBlocks(pageId)` 返回数组中的位置。
 *
 * 本服务不做任何渲染，只做下标计算 + 调用 Scroller.scrollToIndex + 触发高亮 + 失败降级提示。
 * 折叠展开通过既有 `collapse` op（OutlinerEngine.ets:136 → BlockTree.setCollapsed）复用现有写通路。
 */

/** 定位结果状态（tagged union，替代 ArkTS 不支持的字符串联合 + 便于调用方分派） */
export enum BlockRevealStatus {
  /** 已滚动到目标行并触发高亮 */
  SCROLLED = 'scrolled',
  /** 目标块不在当前页（未加载/已删除/属于别的页面）—— 需要调用方先切页 */
  DIFFERENT_PAGE = 'different-page',
  /** 目标块查不到（已删除或 uuid 错误） */
  BLOCK_NOT_FOUND = 'block-not-found',
  /** 页面不展开（页不存在或为空页，没有任何行可定位） */
  EMPTY_PAGE = 'empty-page',
  /** 当前窗格没有可用的滚动容器（非整页大纲视图，如日志流/整页编辑器/图谱）*/
  NO_SCROLLER = 'no-scroller',
  /** 下标越界（索引与数据源不一致时的兜底，不静默失败）*/
  INDEX_OUT_OF_RANGE = 'index-out-of-range',
  /**
   * 已排入下一帧执行（本次调用未滚动）。
   * 出现在「展开折叠祖先」之后：展开会触发 callaite_blocksVersion → BlockList/BlockChildren
   * 重建，而 SDK 要求 scrollToIndex 必须在数据刷新完成后调用（scroll.d.ts:489-490），
   * 故必须让出这一帧。这是预期路径，**不是失败**，调用方不应据此弹提示。
   */
  DEFERRED = 'deferred-until-next-frame'
}

/** 定位结果 */
export interface BlockRevealResult {
  status: BlockRevealStatus;
  /** 命中的 List 下标；未命中为 -1 */
  index: number;
  /** 可直接展示给用户的说明（已本地化）*/
  message: string;
  /** 是否真正执行了滚动 */
  scrolled: boolean;
}

/** ContentArea 发布 Scroller 的键前缀（ContentArea.ets:70-72）*/
const SCROLLER_KEY_PREFIX = 'callaite_blockScroller_';

/** 折叠展开 + 数据源刷新后，等一帧再滚动（避免在 LazyForEach 重建中途发起定位）*/
const SCROLL_DEFER_MS = 80;

/**
 * 单个块的可定位信息（下标计算结果）。
 */
export interface BlockAnchorInfo {
  /** 目标块本身 */
  blockUuid: string;
  /** 目标块的顶层祖先（= 承载它的那个 ListItem 对应的块）*/
  rootUuid: string;
  /** 顶层祖先在 List 下标空间中的位置；未知为 -1 */
  index: number;
  /** 根块 → 目标块 的祖先链（含根与目标自身），用于折叠展开 */
  chain: string[];
}

export class BlockAnchorService {
  private static instance: BlockAnchorService | undefined;

  static getInstance(): BlockAnchorService {
    if (!BlockAnchorService.instance) {
      BlockAnchorService.instance = new BlockAnchorService();
    }
    return BlockAnchorService.instance;
  }

  // ─── Scroller 取用 ───

  /** 取某一窗格的 Block 列表滚动控制器（由 ContentArea 发布）。 */
  getScroller(paneId: string): Scroller | undefined {
    return AppStorage.get<Scroller>(SCROLLER_KEY_PREFIX + paneId);
  }

  /** 主窗格（paneId='primary'）的滚动控制器。 */
  getPrimaryScroller(): Scroller | undefined {
    return this.getScroller('primary');
  }

  /**
   * 注册/覆盖某窗格的 Scroller。
   * 正常链路由 ContentArea.publishScroller 完成；此处仅作兜底与可测性入口。
   */
  registerScroller(paneId: string, scroller: Scroller): void {
    AppStorage.setOrCreate(SCROLLER_KEY_PREFIX + paneId, scroller);
  }

  // ─── 当前显示页判定 ───

  /**
   * 主窗格当前实际渲染的页面名。
   * 与 `PageView.resolvePage()`（PageView.ets:107-119）保持同一规则：
   * 'Journal' 路由的实际页名是当天日期串。
   */
  getActivePageName(): string {
    const route = AppState.getCurrentPage();
    if (route === 'Journal') {
      return JournalService.getTodayDateString();
    }
    return route;
  }

  /** 主窗格是否有承载整页大纲的滚动容器（没有则说明当前路由不渲染 BlockList 的 List）。 */
  hasActiveScroller(): boolean {
    return this.getPrimaryScroller() !== undefined;
  }

  // ─── 下标计算 ───

  /**
   * 计算某块在「当前渲染序列」中的下标。
   *
   * 规则（依据见文件头注释）：
   *   1. 沿 parentId 上溯到 parentId === pageId 的根块；
   *   2. 该根块在 `getPageBlocks(pageId)`（顶层块数组）中的位置即 List 下标；
   *   3. 目标块自身是子块时，下标等于其根块的下标（子块与根块同处一个 ListItem，
   *      scrollToIndex 会把整行滚到视口顶部，目标子块随行可见）。
   *
   * @returns 下标信息；块不存在返回 undefined
   */
  indexOf(pageId: string, blockUuid: string): number {
    if (blockUuid === '') {
      return -1;
    }
    const ws = WorkspaceService.getInstance();
    const top: BlockData[] = ws.getPageBlocks(pageId);
    for (let i = 0; i < top.length; i++) {
      if (top[i].uuid === blockUuid) {
        return i;
      }
    }
    // 不是顶层块：上溯到根块再取下标
    const info = this.resolveAnchor(pageId, blockUuid);
    return info ? info.index : -1;
  }

  /**
   * 解析目标块的可定位信息（根块 + 下标 + 祖先链）。
   * 关键：下标**只**由根块决定；祖先链用于跳转前展开折叠的祖先。
   */
  resolveAnchor(pageId: string, blockUuid: string): BlockAnchorInfo | undefined {
    const ws = WorkspaceService.getInstance();
    const target = ws.getBlock(blockUuid);
    if (!target || target.pageId !== pageId) {
      return undefined;
    }

    // 沿 parentId 上溯，构造 根→目标 的链
    const reversed: string[] = [];
    let cursor: BlockData | undefined = target;
    let guard = 0;
    while (cursor && guard < 512) {
      reversed.push(cursor.uuid);
      if (cursor.parentId === pageId || cursor.parentId === '') {
        break;
      }
      cursor = ws.getBlock(cursor.parentId);
      guard = guard + 1;
    }
    if (guard >= 512) {
      // 数据异常（父链成环）—— 不静默吞掉，交给上层走降级提示
      return undefined;
    }

    const chain: string[] = [];
    for (let i = reversed.length - 1; i >= 0; i--) {
      chain.push(reversed[i]);
    }
    const rootUuid = chain[0];

    const top: BlockData[] = ws.getPageBlocks(pageId);
    let index = -1;
    for (let i = 0; i < top.length; i++) {
      if (top[i].uuid === rootUuid) {
        index = i;
        break;
      }
    }

    const info: BlockAnchorInfo = {
      blockUuid: blockUuid,
      rootUuid: rootUuid,
      index: index,
      chain: chain
    };
    return info;
  }

  /**
   * 展开目标块的折叠祖先（不含目标自身 —— 目标是叶子时没有可展开的东西）。
   * 复用既有 `collapse` op 写通路（OutlinerEngine.ets:136），不新造数据操作。
   *
   * @returns 实际被展开的块数
   */
  expandAncestors(chain: string[]): number {
    const ws = WorkspaceService.getInstance();
    let expanded = 0;
    // chain 是 根→目标，但目标是自身不展开，故遍历到 length-1
    for (let i = 0; i < chain.length - 1; i++) {
      const ancestor = ws.getBlock(chain[i]);
      if (ancestor && ancestor.collapsed) {
        ws.executeOp({ type: 'collapse', uuid: chain[i], collapsed: false });
        expanded = expanded + 1;
      }
    }
    if (expanded > 0) {
      // 通知 BlockList / BlockChildren 重算（它们监听 callaite_blocksVersion）
      AppState.bumpBlocksVersion();
    }
    return expanded;
  }

  // ─── 跳转 ───

  /**
   * 把目标块滚动到视口顶部并触发高亮。
   *
   * @param pageId   目标块所属页面 uuid
   * @param pageName 目标块所属页面名（用于「不在当前页」判定与提示文案）
   * @param blockUuid 目标块 uuid
   */
  revealBlock(pageId: string, pageName: string, blockUuid: string): BlockRevealResult {
    const ws = WorkspaceService.getInstance();

    // 1. 目标块是否存在
    const target = ws.getBlock(blockUuid);
    if (!target) {
      return this.failure(BlockRevealStatus.BLOCK_NOT_FOUND,
        this.msg('anchor_block_missing', '目标块已不存在（可能已被删除）'));
    }

    // 2. 是否当前显示页 —— 不在就交给调用方先切页（不静默失败）
    const activePage = this.getActivePageName();
    if (activePage !== pageName) {
      return this.failure(BlockRevealStatus.DIFFERENT_PAGE,
        this.msg('anchor_other_page', '目标块在页面「{page}」，请先打开该页面').replace('{page}', pageName));
    }

    // 3. 滚动容器
    const scroller = this.getPrimaryScroller();
    if (scroller === undefined) {
      return this.failure(BlockRevealStatus.NO_SCROLLER,
        this.msg('anchor_no_scroller', '当前视图不支持块定位（请切回大纲视图）'));
    }

    // 4. 解析下标（子块归到其根块那一行）
    const info = this.resolveAnchor(pageId, blockUuid);
    if (info === undefined) {
      return this.failure(BlockRevealStatus.BLOCK_NOT_FOUND,
        this.msg('anchor_block_missing', '目标块已不存在（可能已被删除）'));
    }

    // 5. 折叠的祖先先展开（否则目标块在界面上根本不存在，滚到根块也看不到它）
    const expanded = this.expandAncestors(info.chain);

    if (info.index < 0) {
      return this.failure(BlockRevealStatus.EMPTY_PAGE,
        this.msg('anchor_empty_page', '目标块当前不在大纲中（页面可能为空）'));
    }

    // 下标边界：List 下标空间是 [0, top.length-1]（下标 top.length 是尾部 AddBlockButton）。
    // SDK scroll.d.ts:509-510 对越界值的处理是「不做任何滚动」——静默失败，
    // 所以这里必须自己拦住并给出可读提示。
    const count = ws.getPageBlocks(pageId).length;
    if (info.index >= count) {
      return this.failure(BlockRevealStatus.INDEX_OUT_OF_RANGE,
        this.msg('anchor_out_of_range', '列表尚未就绪，无法定位'));
    }

    // 6. 滚动 + 高亮
    const runScroll = (): void => {
      // SDK scroll.d.ts:533；NOTE 明确 scrollToIndex 仅对 ArcList/Grid/List/WaterFlow 生效
      scroller.scrollToIndex(info.index, false, ScrollAlign.START);
      this.flash(blockUuid);
    };

    if (expanded > 0) {
      // 刚触发过一次数据刷新（bumpBlocksVersion）：让出一帧再滚，避免在重建中途定位
      setTimeout(() => {
        runScroll();
      }, SCROLL_DEFER_MS);
      const pending: BlockRevealResult = {
        status: BlockRevealStatus.DEFERRED,
        index: info.index,
        message: '',
        scrolled: false
      };
      return pending;
    }

    runScroll();
    const ok: BlockRevealResult = {
      status: BlockRevealStatus.SCROLLED,
      index: info.index,
      message: '',
      scrolled: true
    };
    return ok;
  }

  /**
   * 延迟一帧再定位。
   * 用途：调用方刚切换页面（或是搜索面板关闭引起重排）时，BlockList 的 List 与
   * LazyForEach 数据源尚未重建完成 —— SDK scroll.d.ts:489-490 明确要求
   * 「数据刷新完成后」再调用 scrollToIndex。此处用 setTimeout 等一帧。
   */
  revealBlockDeferred(pageId: string, pageName: string, blockUuid: string): void {
    setTimeout(() => {
      const result = this.revealBlock(pageId, pageName, blockUuid);
      this.notifyIfFailed(result);
    }, SCROLL_DEFER_MS);
  }

  /**
   * `revealBlockByUuid` 的延迟版本（页面刚切换时用）。
   * 失败会自行 toast，调用方无需再处理。
   */
  revealBlockDeferredByUuid(blockUuid: string): void {
    setTimeout(() => {
      const result = this.revealBlockByUuid(blockUuid);
      this.notifyIfFailed(result);
    }, SCROLL_DEFER_MS);
  }

  /**
   * 统一失败提示入口。
   * DEFERRED 是「已排入下一帧」的正常中间态（见 BlockRevealStatus.DEFERRED），不算失败，
   * 若把它当失败会在展开折叠祖先时误弹「无法定位」。
   */
  notifyIfFailed(result: BlockRevealResult): void {
    if (result.scrolled) {
      return;
    }
    if (result.status === BlockRevealStatus.DEFERRED) {
      return;
    }
    this.notify(result);
  }

  /**
   * 目标块已知 uuid、但页面 uuid/页名未知时的便捷入口（自行解析）。
   */
  revealBlockByUuid(blockUuid: string): BlockRevealResult {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(blockUuid);
    if (!block) {
      return this.failure(BlockRevealStatus.BLOCK_NOT_FOUND,
        this.msg('anchor_block_missing', '目标块已不存在（可能已被删除）'));
    }
    const page: PageData | undefined = ws.getDataStore().getIndexStore().getPage(block.pageId);
    const pageName = page ? page.originalName : '';
    return this.revealBlock(block.pageId, pageName, blockUuid);
  }

  // ─── 高亮反馈 ───

  /**
   * 触发目标块闪烁高亮：写 AppStorage 两个键（经 AppState.triggerHighlight 单一写入口），
   * BlockView 通过 @StorageLink + @Watch 接收。序号单调递增保证「连续点同一块」每次都有反馈。
   */
  flash(blockUuid: string): void {
    AppState.triggerHighlight(blockUuid);
  }

  // ─── 内部 ───

  private failure(status: BlockRevealStatus, message: string): BlockRevealResult {
    const result: BlockRevealResult = {
      status: status,
      index: -1,
      message: message,
      scrolled: false
    };
    return result;
  }

  /**
   * 用户可见提示。
   * 优先走项目既有 i18n 机制（utils/i18n.ets 的 t()）；键缺失时 t() 会原样返回键名，
   * 故用 fallback 兜底为可读中文（本任务不允许改 i18n.ets，新增键留待后续统一补录）。
   */
  private msg(key: string, fallback: string): string {
    const translated = t(key);
    if (translated === key || translated === '') {
      return fallback;
    }
    return translated;
  }

  /** 把失败结果以 toast 呈现（降级路径绝不静默）。 */
  notify(result: BlockRevealResult): void {
    if (result.message === '') {
      return;
    }
    promptAction.openToast({ message: result.message }).catch(() => {});
  }
}
