import { AppState } from '../state/AppState';
import { PageData } from '../core/models/Page';
import { WorkspaceService } from './WorkspaceService';
import { BlockAnchorService, BlockRevealResult, BlockRevealStatus } from './BlockAnchorService';

/**
 * AnchorRegistry — U2.1b 锚点跳转的**单一入口**（入口层）。
 *
 * ─── 为什么要单开一层，而不是塞进 BlockAnchorService ───
 * `BlockAnchorService`（c7fbff7 落地）的契约是「不做任何渲染，只做下标计算 +
 * scrollToIndex + 触发高亮 + 降级提示」，那是**算法层**。而三处来源真正重复的是
 * **入口策略**：
 *   ① 关不关来源面板（搜索面板是带遮罩的模态，必须关；右侧栏不是模态，不能关）；
 *   ② 同页 → 立即定位 / 跨页 → 等一帧（`scroll.d.ts:489-490` 要求数据刷新完成后
 *      才能 scrollToIndex，跨页时 List 与 LazyForEach 数据源下一帧才重建完成）；
 *   ③ 路由要不要跟着走（主窗格要，分屏副窗格不能改全局路由）；
 *   ④ 6 种降级状态怎么分派（谁 toast、谁静默、谁由调用方兜底）。
 * 把这四件事写进算法层，会让算法层反向依赖路由/面板策略，且 c7fbff7 已验收的
 * 定位路径要多担一份回归风险。故：**算法层原样保留，只把 「用哪个窗格的 Scroller /
 * 拿哪个窗格的当前页做同页判定」参数化（revealBlock 新增可选 paneId）**，策略收敛到本类。
 *
 * ─── 三处来源（迁移后都只调本类）───
 *   · 搜索面板  `SearchPanel.navigateToResult`（SearchPanel.ets:409）
 *   · 右侧栏大纲 `RightSidebar.OutlineContent` → `jumpToBlock`（RightSidebar.ets:511/526）
 *   · 右侧栏反链 `BacklinkFilters.BacklinkItem`（BacklinkFilters.ets:407；W10/U2.1b 新接线）
 *
 * ─── `BlockRevealStatus` 的 6 种降级如何透传（一个都不丢）───
 *   状态                含义                        本类的处理
 *   ─────────────────  ──────────────────────────  ──────────────────────────────────────
 *   SCROLLED           已滚动+已高亮                 直接返回，不提示
 *   DEFERRED           已排入下一帧（展开折叠祖先 / 跨页重建）  直接返回，**不提示**（正常
 *                      中间态；当失败弹提示会在展开祖先时误报「无法定位」）
 *   DIFFERENT_PAGE     目标页不是该窗格当前页        同页判定已由本类前置（跨页先切页/先选窗格），
 *                      走到这里说明索引与渲染不一致 ⇒ 经 `notifyIfFailed` 给出可读提示
 *   BLOCK_NOT_FOUND    块不存在（已删除/uuid 错）   经 `notifyIfFailed` 提示
 *   EMPTY_PAGE         展开祖先后方序列仍无此行      经 `notifyIfFailed` 提示
 *   NO_SCROLLER        该窗格没有 BlockList 滚动容器 经 `notifyIfFailed` 提示
 *   INDEX_OUT_OF_RANGE 下标越界（兜底）             经 `notifyIfFailed` 提示
 *   即：**分派规则完全复用服务自己的 `notifyIfFailed`（scrolled / DEFERRED 不提示，
 *   其余一律提示）**，本类不另写一套文案与判定，避免两处口径漂移。
 *
 * 本类只做「取块 → 定页 → 定窗格 → 对齐路由 → 分派同步/延迟定位 → 统一降级」，
 * 不做下标计算、不碰 Scroller、不写数据。
 */

/** 锚点来源（谁发起的跳转）。仅用于诊断与来源面板关闭策略，不改变定位算法。 */
export enum AnchorSource {
  SEARCH = 'search',
  OUTLINE = 'outline',
  BACKLINK = 'backlink',
  /** 页内搜索条（FindInPage，U2.4 第 3 件 / W13 接线）。
   *  与 SEARCH（全局搜索面板，带遮罩的模态）区分开：本来源**不传 onDismiss**
   *  —— 搜索条不是模态，跳转后保持打开才能连按 ↵ 逐个走。 */
  FIND_IN_PAGE = 'find-in-page',
  DIRECT = 'direct'
}

/** 一次锚点跳转请求。 */
export interface AnchorRequest {
  /** 目标块 uuid（唯一必填项）*/
  blockUuid: string;
  /** 来源（搜索/大纲/反链/直接调用）*/
  source: AnchorSource;
  /**
   * 关闭来源面板的动作。
   * 搜索面板是**带遮罩的模态**，不关就看不见刚跳到的位置 ⇒ 必须传；
   * 右侧栏（大纲/反链）不是模态，跳转后保持打开才符合预期 ⇒ 不传。
   */
  onDismiss?: () => void;
  /** 调用方已知的目标页名。仅在索引里查不到该块所属页面时作兜底，正常情况下不使用。 */
  pageNameHint?: string;
  /** 指定窗格（可选）。不传则按「主窗格优先、其次已显示该页的分屏副窗格」自动判定。 */
  paneId?: string;
}

/** 锚点跳转结果。调用方无需解析 toast 即可知道发生了什么。 */
export interface AnchorOutcome {
  /** 定位状态（跨页/延迟时为 DEFERRED）*/
  status: BlockRevealStatus;
  /** 实际使用的窗格 */
  paneId: string;
  /** 是否改变了该窗格**渲染的页面**（跨页跳转为 true）*/
  switchedPage: boolean;
  /** 是否调用了来源面板的关闭动作 */
  dismissedSource: boolean;
  /** 是否已发出定位（同步已滚 or 已排入下一帧）*/
  dispatched: boolean;
  /** 可直接展示的说明（空串 = 无需提示）*/
  message: string;
}

export class AnchorRegistry {
  private static instance: AnchorRegistry | undefined;

  static getInstance(): AnchorRegistry {
    if (!AnchorRegistry.instance) {
      AnchorRegistry.instance = new AnchorRegistry();
    }
    return AnchorRegistry.instance;
  }

  /**
   * 锚点跳转**唯一入口**：三处来源全部经此进入。
   *
   * 时序（固定，不随来源变化）：
   *   ① 关来源面板（若调用方给了 onDismiss）
   *   ② 解析目标块（不存在 ⇒ BLOCK_NOT_FOUND，可读提示，绝不静默）
   *   ③ 解析目标页名（块 → 页 → 页名；索引缺失时用 pageNameHint 兜底）
   *   ④ 选定窗格（分屏语义）
   *   ⑤ 需要时对齐路由（仅主窗格；副窗格改全局路由等于劫持主窗格）
   *   ⑥ 跨页 ⇒ 等一帧；同页 ⇒ 立即定位；两者都走服务的统一降级分派
   */
  jump(req: AnchorRequest): AnchorOutcome {
    const anchor = BlockAnchorService.getInstance();

    // ① 关来源面板：必须先于定位 —— 搜索面板带遮罩，关晚了会把「跳到哪了」盖住
    //    （SearchPanel 原有注释记录的同一结论，此处收敛为固定时序）。
    let dismissed = false;
    const dismiss = req.onDismiss;
    if (dismiss !== undefined) {
      dismiss();
      dismissed = true;
    }

    // ② 目标块必须存在
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(req.blockUuid);
    if (!block) {
      const missing: BlockRevealResult = anchor.revealBlockByUuid(req.blockUuid);
      anchor.notifyIfFailed(missing);
      return this.outcome(missing.status, BlockAnchorService.PRIMARY_PANE, false, dismissed, false, missing.message);
    }

    // ③ 目标页名。口径与 `revealBlockByUuid` 完全一致（IndexStore.getPage(block.pageId)），
    //    保证「本类判定的页」与「服务定位的页」是同一个字符串。
    const page: PageData | undefined = ws.getDataStore().getIndexStore().getPage(block.pageId);
    let pageName = page ? page.originalName : '';
    if (pageName === '' && req.pageNameHint !== undefined) {
      pageName = req.pageNameHint;
    }
    if (pageName === '') {
      // 索引里查不到该块所属页面：交给服务给出**同一条**降级结论与文案，本类不自造。
      const unresolved: BlockRevealResult = anchor.revealBlockByUuid(req.blockUuid);
      anchor.notifyIfFailed(unresolved);
      return this.outcome(unresolved.status, BlockAnchorService.PRIMARY_PANE, false, dismissed, false, unresolved.message);
    }

    // ④ 选定窗格
    const paneId = req.paneId !== undefined ? req.paneId : this.resolvePane(pageName);

    // ⑤ 路由对齐 + 同页/跨页判定。
    //    判据是「该窗格**渲染的页**是否已是目标页」（getPanePageName 会把
    //    'Journal' 映射成当天日期串），不是「路由键字符串是否相等」——
    //    否则在日志路由上会误判为跨页，平白多等一帧。
    const samePage = anchor.getPanePageName(paneId) === pageName;
    let switched = false;
    if (!samePage && paneId === BlockAnchorService.PRIMARY_PANE) {
      // 只在这一页确实要换掉时才写路由：同页时 setCurrentPage 会顺带 flushNow +
      // addRecentPage（AppState.ets:274-288），既非「切换页面」的本意，也会把
      // 日志路由 'Journal' 无谓地改写成日期串。
      AppState.setCurrentPage(pageName);
      switched = true;
    }

    // ⑥ 跨页等一帧 / 同页立即定位
    if (switched) {
      // 跨页：PageView/BlockList 的 List 与 LazyForEach 数据源下一帧才重建完成，
      // 而 SDK 要求 scrollToIndex 必须在数据刷新完成后调用（scroll.d.ts:489-490）。
      anchor.revealBlockDeferred(block.pageId, pageName, req.blockUuid, paneId);
      return this.outcome(BlockRevealStatus.DEFERRED, paneId, true, dismissed, true, '');
    }

    const result: BlockRevealResult = anchor.revealBlock(block.pageId, pageName, req.blockUuid, paneId);
    anchor.notifyIfFailed(result);
    return this.outcome(result.status, paneId, false, dismissed, result.scrolled, result.message);
  }

  /**
   * 选定窗格（分屏语义）。
   *
   * 规则（顺序即优先级）：
   *   ① 目标页已在主窗格渲染 ⇒ 主窗格；
   *   ② 分屏未开 / 副窗格未真的挂载（关掉分屏后旧 Scroller 仍留在 AppStorage）⇒ 主窗格；
   *   ③ 目标页已在副窗格渲染 ⇒ 副窗格 —— **不改全局路由**：
   *      跳「主窗格正显示别页、副窗格正显示目标页」时若去改路由，等于把主窗格劫持走，
   *      用户眼前的两个窗格会同时跳页；
   *   ④ 其余 ⇒ 主窗格（由调用方决定要不要切页）。
   */
  resolvePane(pageName: string): string {
    const anchor = BlockAnchorService.getInstance();
    const primary = BlockAnchorService.PRIMARY_PANE;
    const secondary = BlockAnchorService.SECONDARY_PANE;

    if (anchor.getPanePageName(primary) === pageName) {
      return primary;
    }
    if (!anchor.isPaneMounted(secondary)) {
      return primary;
    }
    if (anchor.getPanePageName(secondary) === pageName) {
      return secondary;
    }
    return primary;
  }

  private outcome(status: BlockRevealStatus, paneId: string, switchedPage: boolean,
    dismissedSource: boolean, dispatched: boolean, message: string): AnchorOutcome {
    const result: AnchorOutcome = {
      status: status,
      paneId: paneId,
      switchedPage: switchedPage,
      dismissedSource: dismissedSource,
      dispatched: dispatched,
      message: message
    };
    return result;
  }
}
