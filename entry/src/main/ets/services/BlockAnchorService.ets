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
 * 整页大纲分支：`BlockList.ets` 的 List 分支
 *   List({ space: 0, scroller })            ← 唯一的滚动容器，Scroller 由 ContentArea 注入
 *     └ LazyForEach(this.dataSource, ...)
 *         └ ListItem() { BlockView }        ← **每个可见行一个 item，item 内只有 1 个 BlockView**
 * 数据源：`WorkspaceService.getVisibleBlocks(page.uuid)` = `DataStore.getVisibleBlocks`
 *   = `BlockTree.getVisibleBlocks` —— **可见行序列**：顶层块 + 所有已展开（collapsed===false）
 *   子块，按屏幕从上到下的顺序。
 *
 * 关键结论（U2.1a 下标正确性的依据）：
 *   1. List 下标空间 = [0, R-1]，R = 可见行数；下标 R 是尾部 `AddBlockButton` 的 ListItem。
 *      （页面为空时 [0] 是空态 ListItem，与定位无关。）
 *   2. 每一行的 uuid **就是**该行所渲染块的 uuid —— 不再存在「子块与根块共用一个 item」。
 *      因此「uuid → 下标」= 该块在 `getVisibleBlocks(pageId)` 中的位置；子块不再归到根块行。
 *   3. 折叠会让**整棵子树**从可见行序列中消失（`getVisibleBlocks` 只在未折叠时下钻），
 *      所以被折叠祖先藏住的块下标为 -1。**必须先展开祖先、再算下标** —— 这正是
 *      `revealBlock` 把 `expandAncestors` 放在 `indexOf` 之前的原因（顺序反了会误报"不在大纲中"）。
 *   4. 折叠态只在内存（磁盘 .md 无 collapsed 字段），故下标每次从 BlockTree 现算；
 *      本服务与 BlockList 走**同一个** getVisibleBlocks —— 单一实现，下标空间不会漂移。
 *
 * 本服务不做任何渲染，只做下标计算 + 调用 Scroller.scrollToIndex + 触发高亮 + 失败降级提示。
 * 折叠展开通过既有 `collapse` op（OutlinerEngine.ets:136 → BlockTree.setCollapsed）复用现有写通路。
 *
 * ─── U2.1b 分层：本类是**算法层**，`AnchorRegistry` 是**入口层** ───
 * 「同页/跨页判定、跨页等一帧、关闭来源面板、选哪个窗格、6 种降级怎么分派」属入口策略，
 * 一律放在 `services/AnchorRegistry.ets`；组件（搜索面板/右侧栏大纲/反链）只调 Registry，
 * 不再各自直调本类。本类保持「无 UI 副作用」的契约，便于单独调用与验证。
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

/** 主窗格 paneId（ContentArea 默认值，见 ContentArea.ets:48）*/
const PANE_PRIMARY = 'primary';
/** 副窗格 paneId（MainContainer 分屏时注入，见 MainContainer.ets:223）*/
const PANE_SECONDARY = 'secondary';

/** 折叠展开 + 数据源刷新后，等一帧再滚动（避免在 LazyForEach 重建中途发起定位）*/
const SCROLL_DEFER_MS = 80;

/**
 * 跨页定位的**第二次**尝试延迟。
 *
 * 为什么要重试（U2.1b 设备实测）：切页后 `BlockList` 要重算可见行序列、替换 LazyForEach
 * 数据源并重新布局，而 SDK 明确要求 `scrollToIndex` 必须在**数据刷新完成后**调用
 * （scroll.d.ts:489-490）；在那之前调用会被**静默忽略**（不抛错、不滚动）。
 * 实测：只等 80ms（≈2 帧，模拟器 ~20-30fps）时，`__BKL_source` → `2026-09-27` 的跨页
 * 大纲/搜索跳转**没有滚动**（列表停在顶部）；同一目标在页面已就绪后再点（同页路径）则正常滚动。
 * ⇒ 首帧之后再补一次（幂等：index 已重算，重复调用只会滚到同一位置）。
 */
const SCROLL_RETRY_MS = 240;

/** 跨页定位的最大尝试次数（首帧 + 1 次重试；不做无限重试，失败仍走统一降级提示）*/
const SCROLL_MAX_ATTEMPTS = 2;

/**
 * 单个块的可定位信息（下标计算结果）。
 */
export interface BlockAnchorInfo {
  /** 目标块本身 */
  blockUuid: string;
  /** 目标块的顶层祖先（仅作 chain 的起点；展平后每行即块自身，不再靠它定位）*/
  rootUuid: string;
  /** 目标块**自身**在可见行序列中的下标；被折叠祖先藏住时为 -1 */
  index: number;
  /** 根块 → 目标块 的祖先链（含根与目标自身），用于折叠展开 */
  chain: string[];
}

export class BlockAnchorService {
  private static instance: BlockAnchorService | undefined;

  /**
   * 窗格 → Scroller 的**直接引用**登记表。
   * 不走 AppStorage 中转（AppStorage 里的那个副本与 List 的绑定不是同一个对象，
   * 见 getScroller 的实测注释）。由 BlockList 在 aboutToAppear 自报。
   */
  private paneScrollers: Map<string, Scroller> = new Map<string, Scroller>();

  /** 主窗格 paneId（对外常量，避免各处硬编码字符串）*/
  static readonly PRIMARY_PANE: string = PANE_PRIMARY;
  /** 分屏副窗格 paneId */
  static readonly SECONDARY_PANE: string = PANE_SECONDARY;

  static getInstance(): BlockAnchorService {
    if (!BlockAnchorService.instance) {
      BlockAnchorService.instance = new BlockAnchorService();
    }
    return BlockAnchorService.instance;
  }

  // ─── Scroller 取用 ───

  /** 取某一窗格的 Block 列表滚动控制器。 */
  getScroller(paneId: string): Scroller | undefined {
    // ⚠️ U2.1b 实测（设备硬证据）：**不能只信 AppStorage**。
    // `ContentArea.publishScroller()` 把 Scroller 写进 AppStorage，但读回来的那个对象
    // **与 List 实际绑定的是两个东西** —— 对它调用 `currentOffset()` 直接抛异常
    // （探针：`PROBE idx=1 pre=THROW post=THROW`，hilog A02110/U21B），
    // 于是 `scrollToIndex()` 静默无效（不抛错、不滚动）⇒「点搜索结果/大纲条目不跳块」。
    // 修法：以**组件自报的直接引用**为准（BlockList 在 aboutToAppear 里 registerScroller），
    // AppStorage 只留作兜底与外部可测性入口。
    const direct = this.paneScrollers.get(paneId);
    if (direct !== undefined) {
      return direct;
    }
    return AppStorage.get<Scroller>(SCROLLER_KEY_PREFIX + paneId);
  }

  /** 主窗格（paneId='primary'）的滚动控制器。 */
  getPrimaryScroller(): Scroller | undefined {
    return this.getScroller(PANE_PRIMARY);
  }

  /**
   * 注册/覆盖某窗格的 Scroller。
   * 正常链路由 BlockList 在构造期自报（它才是真正把它交给 `List` 的那一方）；
   * 外部也可调用，但**外部注册的实例未必与 List 绑定的是同一个** —— 优先信组件自报。
   */
  registerScroller(paneId: string, scroller: Scroller): void {
    this.paneScrollers.set(paneId, scroller);
    AppStorage.setOrCreate(SCROLLER_KEY_PREFIX + paneId, scroller);
  }

  /**
   * 某窗格此刻是否真的挂载着。
   *
   * ⚠️ 不能只看 `getScroller(paneId) !== undefined`：ContentArea 的 `publishScroller()`
   * 只在 `aboutToAppear` 写一次，**关闭分屏时不会撤销**该键 ⇒ 关掉分屏后副窗格的
   * Scroller 仍留在 AppStorage 里（一个已经不在渲染树上的死 Scroller）。
   * 因此副窗格必须叠加「分屏开关当前为 true」这一个条件。
   */
  isPaneMounted(paneId: string): boolean {
    if (this.getScroller(paneId) === undefined) {
      return false;
    }
    if (paneId === PANE_PRIMARY) {
      return true;
    }
    return AppStorage.get<boolean>('callaite_splitEnabled') === true;
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

  /**
   * 指定窗格当前实际渲染的页面名（分屏语义）。
   *
   * · 主窗格：跟随全局路由（`getActivePageName`）。
   * · 副窗格：跟随 `callaite_splitPage`（MainContainer.ets:223 把它作为 pageOverride 注入），
   *   其 'Journal' → 当天日期串的映射与 `PageView.resolvePage()`（PageView.ets:131-136）一致。
   * · 窗格未挂载（分屏关着）⇒ 返回空串，调用方据此判定「这一页不在该窗格」。
   */
  getPanePageName(paneId: string): string {
    if (paneId === PANE_PRIMARY) {
      return this.getActivePageName();
    }
    if (!this.isPaneMounted(paneId)) {
      return '';
    }
    const splitPage = AppStorage.get<string>('callaite_splitPage') ?? '';
    if (splitPage === 'Journal') {
      return JournalService.getTodayDateString();
    }
    return splitPage;
  }

  /** 主窗格是否有承载整页大纲的滚动容器（没有则说明当前路由不渲染 BlockList 的 List）。 */
  hasActiveScroller(): boolean {
    return this.getPrimaryScroller() !== undefined;
  }

  // ─── 下标计算 ───

  /**
   * 计算某块在「当前渲染序列」（可见行序列）中的下标。
   *
   * 规则：直接取该块在 `getVisibleBlocks(pageId)` 中的位置 —— 展平后每一行就是该块自身，
   * 不再需要（也不允许）上溯到根块取下标。
   *
   * 返回 -1 有两种含义，调用方需区别对待：
   *   · 块不存在 → 报 BLOCK_NOT_FOUND；
   *   · 块存在但被某个**折叠祖先**藏住 → 先 `expandAncestors` 再重新调用本方法。
   *
   * @returns 可见行下标；不存在或当前不可见返回 -1
   */
  indexOf(pageId: string, blockUuid: string): number {
    if (blockUuid === '') {
      return -1;
    }
    const rows: BlockData[] = WorkspaceService.getInstance().getVisibleBlocks(pageId);
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].uuid === blockUuid) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 解析目标块的可定位信息（可见行下标 + 祖先链）。
   *
   * `index` 是**调用时刻**的可见行下标：若目标被折叠祖先藏住则为 -1
   * （调用方必须先 `expandAncestors` 再重新 `indexOf`，见 revealBlock）。
   * `chain`（根→目标，含两端）用于展开折叠祖先；展开只遍历到 length-1（目标自身不展开）。
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

    // 下标 = 目标块自身在可见行序列中的位置（可能为 -1：被折叠祖先藏住）
    const index = this.indexOf(pageId, blockUuid);

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
      // 通知 BlockList 重算可见行序列（它监听 callaite_blocksVersion）
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
   * @param paneId   目标窗格（分屏语义；缺省 = 主窗格）。窗格只影响
   *                 「用哪个 Scroller」与「拿哪个窗格的当前页做同页判定」，
   *                 下标算法与可见行序列是窗格无关的（`getVisibleBlocks(pageId)` 按页取）。
   */
  revealBlock(pageId: string, pageName: string, blockUuid: string,
    paneId: string = PANE_PRIMARY): BlockRevealResult {
    const ws = WorkspaceService.getInstance();

    // 1. 目标块是否存在
    const target = ws.getBlock(blockUuid);
    if (!target) {
      return this.failure(BlockRevealStatus.BLOCK_NOT_FOUND,
        this.msg('anchor_block_missing', '目标块已不存在（可能已被删除）'));
    }

    // 2. 是否当前显示页 —— 不在就交给调用方先切页（不静默失败）
    //    判定口径按窗格取：主窗格 = 全局路由；副窗格 = 分屏页（见 getPanePageName）。
    const activePage = this.getPanePageName(paneId);
    if (activePage !== pageName) {
      return this.failure(BlockRevealStatus.DIFFERENT_PAGE,
        this.msg('anchor_other_page', '目标块在页面「{page}」，请先打开该页面').replace('{page}', pageName));
    }

    // 3. 滚动容器
    const scroller = this.getScroller(paneId);
    if (scroller === undefined) {
      return this.failure(BlockRevealStatus.NO_SCROLLER,
        this.msg('anchor_no_scroller', '当前视图不支持块定位（请切回大纲视图）'));
    }

    // 4. 解析祖先链（此刻下标可能为 -1：目标被折叠祖先藏住时不在可见行序列里）
    const info = this.resolveAnchor(pageId, blockUuid);
    if (info === undefined) {
      return this.failure(BlockRevealStatus.BLOCK_NOT_FOUND,
        this.msg('anchor_block_missing', '目标块已不存在（可能已被删除）'));
    }

    // 5. 折叠的祖先先展开 —— **必须早于下标计算**：
    //    展开会把目标块放回可见行序列，其下标在展开前后不同（顺序反了会误报「不在大纲中」）。
    const expanded = this.expandAncestors(info.chain);

    // 6. 展开后重算下标（此刻才是「屏幕上真实的第几行」）
    const index = this.indexOf(pageId, blockUuid);
    if (index < 0) {
      return this.failure(BlockRevealStatus.EMPTY_PAGE,
        this.msg('anchor_empty_page', '目标块当前不在大纲中（页面可能为空）'));
    }

    // 下标边界：List 下标空间是 [0, 可见行数-1]（下标 = 可见行数是尾部 AddBlockButton）。
    // SDK scroll.d.ts:509-510 对越界值的处理是「不做任何滚动」——静默失败，
    // 所以这里必须自己拦住并给出可读提示。
    const count = ws.getVisibleBlocks(pageId).length;
    if (index >= count) {
      return this.failure(BlockRevealStatus.INDEX_OUT_OF_RANGE,
        this.msg('anchor_out_of_range', '列表尚未就绪，无法定位'));
    }

    // 7. 滚动 + 高亮
    const runScroll = (): void => {
      // SDK scroll.d.ts:533；NOTE 明确 scrollToIndex 仅对 ArcList/Grid/List/WaterFlow 生效
      // 注意：该调用是**异步**生效的（实测 currentOffset 在调用返回时仍为旧值，
      // 下一轮布局后才变）—— 因此不要用「调用后立刻读 offset」来判断是否跳成功。
      scroller.scrollToIndex(index, false, ScrollAlign.START);
      this.flash(blockUuid);
    };

    if (expanded > 0) {
      // 刚触发过一次数据刷新（bumpBlocksVersion）：让出一帧再滚，避免在重建中途定位
      setTimeout(() => {
        runScroll();
      }, SCROLL_DEFER_MS);
      const pending: BlockRevealResult = {
        status: BlockRevealStatus.DEFERRED,
        index: index,
        message: '',
        scrolled: false
      };
      return pending;
    }

    runScroll();
    const ok: BlockRevealResult = {
      status: BlockRevealStatus.SCROLLED,
      index: index,
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
   *
   * U2.1b：切页后的重建要**若干帧**（不止一帧），首帧调用可能被 SDK 静默忽略，
   * 故在 SCROLL_RETRY_MS 后再幂等补一次（见 SCROLL_RETRY_MS 注释里的实测）。
   *
   * @param paneId 目标窗格（分屏语义；缺省 = 主窗格）
   */
  revealBlockDeferred(pageId: string, pageName: string, blockUuid: string,
    paneId: string = PANE_PRIMARY): void {
    this.revealDeferredAttempt(pageId, pageName, blockUuid, paneId, 1);
  }

  /** `revealBlockDeferred` 的分步实现（attempt 从 1 开始）*/
  private revealDeferredAttempt(pageId: string, pageName: string, blockUuid: string,
    paneId: string, attempt: number): void {
    const delay = attempt <= 1 ? SCROLL_DEFER_MS : SCROLL_RETRY_MS;
    setTimeout(() => {
      const result = this.revealBlock(pageId, pageName, blockUuid, paneId);
      if (!result.scrolled) {
        // 真正的失败、或 DEFERRED（展开折叠祖先后的正常中间态，内部已自行排帧）：
        // 都不再重试，交给统一降级分派（DEFERRED 不会被弹提示）。
        this.notifyIfFailed(result);
        return;
      }
      if (attempt < SCROLL_MAX_ATTEMPTS) {
        // 列表可能还没就绪（跨页）：幂等地再试一次；同页场景第二次只是滚到同一位置。
        this.revealDeferredAttempt(pageId, pageName, blockUuid, paneId, attempt + 1);
      }
    }, delay);
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
