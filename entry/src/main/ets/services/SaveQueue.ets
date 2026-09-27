import { hilog } from '@kit.PerformanceAnalysisKit';
import { DirtyPageTracker } from './DirtyPageTracker';

/**
 * SaveQueue —— 变更登记入口（历史遗留 API；落盘时机已交由 DirtyPageTracker 统一调度）。
 *
 * 演进（优化方案 v2.0 · O1 → 「事件驱动 flush + 放宽定时兜底」过渡方案）：
 *   · 原实现：任何变更 → 静默 1.2s → `saveAll()`（**全库逐页原子写**）。两点问题：
 *     ① 「静默窗口」会被连续输入无限顺延，强杀丢失窗口没有硬上限；
 *     ② 打字期间每 1.2s 触发一次**全 vault** 落盘，I/O 量比原先「每次变更只写当前页」
 *        更大，与 O1 想缓解的 THREAD_BLOCK 相悖。
 *   · 现实现：`markDirty(pageId)` 转发给 DirtyPageTracker —— 由后者登记脏页，并在
 *     「首次标脏 + 5s」的**硬截止期限**落盘；四个事件驱动 flush 点
 *     （失焦 / 切页切标签 / 进后台 / 销毁前）与「结构性操作前」也由后者统一持有，
 *     避免两套定时器各写一遍、也避免两处 flush 时机漂移。
 *
 * 保留本类是为了不改动既有调用点（WorkspaceService / IntegralEditor），
 * 同时避免 SaveQueue → WorkspaceService 的循环引用（本类只依赖叶子模块）。
 */
export class SaveQueue {
  private static instance: SaveQueue | undefined;
  /** 历史遗留标志位：flush() 的幂等门；真正的脏页集合在 DirtyPageTracker 内 */
  private dirty: boolean = false;
  private flushCallback: (() => void) | undefined = undefined;
  private static readonly TAG = 'SaveQueue';
  private static readonly DOMAIN = 0x0002;

  static getInstance(): SaveQueue {
    if (!SaveQueue.instance) {
      SaveQueue.instance = new SaveQueue();
    }
    return SaveQueue.instance;
  }

  /**
   * 由持有落盘能力的服务（WorkspaceService）在初始化时注入落盘回调。
   *
   * ⚠️ 该回调现已不参与脏页写入 —— 写入统一走 DirtyPageTracker 注入的**单页**回调
   *    （`OutlinerEngine.persistNow`）。保留它只为兼容既有初始化调用点与人工兜底。
   */
  init(flushCallback: () => void): void {
    this.flushCallback = flushCallback;
  }

  /**
   * 任意变更路径调用。pageId 为可选的定点信息：
   *   · 传入 pageId → 该页标脏（正常路径由 OutlinerEngine.persistForOp 已经标过，
   *     这里重复标脏是幂等的）；
   *   · 不传 → 仅置历史标志位，不做任何落盘安排（此时页面级标脏已由
   *     `OutlinerEngine.persistForOp` 完成，不可能出现「无页面可写却有脏数据」）。
   */
  markDirty(pageId?: string): void {
    this.dirty = true;
    if (pageId !== undefined && pageId !== '') {
      DirtyPageTracker.getInstance().markDirty(pageId);
    }
  }

  /**
   * 立即落盘（onBackground / onSaveState 等兜底时机也可调用）。
   */
  flush(): void {
    if (!this.dirty) {
      return;
    }
    this.dirty = false;
    DirtyPageTracker.getInstance().flushNow();
    hilog.info(SaveQueue.DOMAIN, SaveQueue.TAG, 'dirty pages flushed');
  }

  /** 注入的全库落盘回调（不再由本类定时调用，仅保留读取入口） */
  getFlushCallback(): (() => void) | undefined {
    return this.flushCallback;
  }
}
