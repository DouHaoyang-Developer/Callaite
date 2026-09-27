import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * DirtyPageTracker —— 惰性落盘协调器（过渡方案：事件驱动 flush + 放宽定时兜底）。
 *
 * 背景（实测缺陷链）：
 *   `EditorService.updateBlockContent` → `OutlinerEngine.execute` → `persistForOp` 每次
 *   文本变更都同步走 `DataStore.savePage`（整页 markdown 导出 + tmp 写入 + fsyncSync +
 *   rename）。打字时约 150ms 级触发一次主线程整页落盘 + fsync —— 这是 THREAD_BLOCK /
 *   appfreeze 类问题的可疑成因。
 *
 * 本类只做「什么时候写」，不碰「怎么写」：
 *   · 文本类变更（`update-block`）只登记 pageId 到脏页集合，不落盘；
 *   · 显式 flush（失焦 / 切页 / 切标签 / 进后台 / 销毁前 / 结构性操作前）立即写脏页；
 *   · 兜底定时器在「首次标脏」时武装，到期写脏页并清空集合。
 *
 * ⚠️ 定时器是**截止期限**而非静默窗口：标脏只在「当前没有排程」时武装一次，
 *    期间继续打字**不会**顺延。因此「持续打字从不失焦」时最多 5s 必有一次落盘，
 *    强杀丢失窗口有硬上限（旧 SaveQueue 的 1.2s 静默窗口会被连续输入无限顺延）。
 *
 * ⚠️ 本类刻意不 import 任何业务模块（落盘能力经 setPageSaver 注入），
 *    以便 state/ 与 components/ 都能安全地反向调用而不引入循环依赖。
 */
export class DirtyPageTracker {
  private static instance: DirtyPageTracker | undefined;

  /** 待落盘页面：key = pageUuid */
  private dirtyPages: Map<string, boolean> = new Map();
  private timerId: number = -1;
  private pageSaver: ((pageId: string) => boolean) | undefined = undefined;

  private static readonly TAG = 'DirtyPageTracker';
  private static readonly DOMAIN = 0x0002;

  /** 定时兜底间隔（ms）：只兜「持续打字从不失焦」，不是主路径 */
  private static readonly BACKSTOP_MS: number = 5000;

  static getInstance(): DirtyPageTracker {
    if (!DirtyPageTracker.instance) {
      DirtyPageTracker.instance = new DirtyPageTracker();
    }
    return DirtyPageTracker.instance;
  }

  /**
   * 由 WorkspaceService 注入「写单页并返回是否成功」的回调
   * （`OutlinerEngine.persistNow`）。必须在下一次 flush 之前调用。
   */
  setPageSaver(saver: (pageId: string) => boolean): void {
    this.pageSaver = saver;
  }

  /** 兜底间隔（ms），供 UI/日志展示与「强杀窗口」说明引用 */
  static backstopMs(): number {
    return DirtyPageTracker.BACKSTOP_MS;
  }

  /**
   * 标脏一个页面；首次标脏时武装兜底定时器（不做顺延）。
   */
  markDirty(pageId: string): void {
    if (!pageId || pageId === '') {
      return;
    }
    this.dirtyPages.set(pageId, true);
    this.armTimer();
  }

  /** 当前是否有「已标脏但未落盘」的页面 */
  hasPending(): boolean {
    return this.dirtyPages.size > 0;
  }

  /** 待落盘页面数 */
  pendingCount(): number {
    return this.dirtyPages.size;
  }

  /**
   * 取消排程的兜底定时器（不落盘）。仅供测试/诊断使用。
   */
  cancel(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  /**
   * 立即把脏页落盘并清空集合（幂等；无脏页时零开销）。
   *
   * 由下列时机调用：块/编辑器失焦、切换页面/标签、应用进入后台、应用销毁前、
   * 任何结构性操作之前、兜底定时器到期。
   */
  flushNow(): void {
    if (this.dirtyPages.size === 0) {
      return;
    }
    this.flushPages();
  }

  /**
   * 只落盘指定页面（定点 flush 用；保留给「需要单独写某一页」的未来调用点，
   * 当前结构性操作前走的是 flushNow() —— 保守取「把全部脏页写下去」）。
   */
  flushPage(pageId: string): void {
    if (!this.dirtyPages.has(pageId)) {
      return;
    }
    this.flushPages(pageId);
  }

  // ─── 内部实现 ───

  private armTimer(): void {
    if (this.timerId >= 0) {
      return; // 已有排程：不顺延，保证 5s 硬上限
    }
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      this.flushPages();
    }, DirtyPageTracker.BACKSTOP_MS);
  }

  /**
   * @param onlyPageId 只落该页；undefined = 全部脏页
   *
   * 集合在写盘**之前**清空（快照式）：写盘回调不会重入本方法，
   * 且写失败时由 `persistNow` 把页面重新标脏，交给下一次兜底重试。
   */
  private flushPages(onlyPageId?: string): void {
    if (this.dirtyPages.size === 0) {
      return;
    }
    const pages: string[] = [];
    if (onlyPageId !== undefined) {
      pages.push(onlyPageId);
      this.dirtyPages.delete(onlyPageId);
    } else {
      this.dirtyPages.forEach((_v: boolean, k: string) => {
        pages.push(k);
      });
      this.dirtyPages.clear();
    }

    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }

    const saver = this.pageSaver;
    let okCount = 0;
    for (let i = 0; i < pages.length; i++) {
      if (saver === undefined) {
        // 未注入落盘回调：保留脏标记，避免静默丢数据
        this.dirtyPages.set(pages[i], true);
        continue;
      }
      // 回调返回 false 有两种含义（实现层无法区分，见 OutlinerEngine.persistNow）：
      // 页面不存在（无内容可写，无需重试）或写盘失败（需要重试）。
      // 一律重新标脏，代价是「页面被删除」时会多一次空转 —— 由 5s 兜底收敛，
      // 换取的是「写失败绝不静默丢弃」。
      if (saver(pages[i])) {
        okCount++;
      } else {
        this.dirtyPages.set(pages[i], true);
      }
    }
    if (pages.length > 0) {
      hilog.info(DirtyPageTracker.DOMAIN, DirtyPageTracker.TAG,
        'flushed %{public}d/%{public}d dirty pages', okCount, pages.length);
    }
    if (this.dirtyPages.size > 0) {
      // 尚有未落盘页面（写失败或未注入回调）→ 重新武装兜底
      this.armTimer();
    }
  }
}
