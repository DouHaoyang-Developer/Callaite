import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * SaveQueue —— 脏页保存队列（优化方案 v2.0 · O1：即时持久化）。
 *
 * 设计（对应缺陷 D1 强杀丢数据 / D3 保存竞态）：
 *   · 任何变更路径调用 markDirty() 后，静默 1.2s 自动执行一次全量落盘
 *     （saveAll 内部逐页原子写：临时文件 + fsync + rename）
 *   · 强杀场景：丢失窗口从"会话级"（依赖 onBackground）收敛为 ≤1.2s
 *   · 解耦：SaveQueue 不反向 import 业务服务，落盘动作经 init() 注入回调
 *     （避免 SaveQueue → WorkspaceService 循环引用）
 *   · onBackground 的 saveAll 兜底保留不变（双保险）
 */
export class SaveQueue {
  private static instance: SaveQueue | undefined;
  private dirty: boolean = false;
  private timerId: number = -1;
  private flushCallback: (() => void) | undefined = undefined;
  private static readonly TAG = 'SaveQueue';
  private static readonly DOMAIN = 0x0002;
  /** 静默窗口：最后一次变更后 1.2s 落盘 */
  private static readonly QUIET_MS = 1200;

  static getInstance(): SaveQueue {
    if (!SaveQueue.instance) {
      SaveQueue.instance = new SaveQueue();
    }
    return SaveQueue.instance;
  }

  /**
   * 由持有落盘能力的服务（WorkspaceService）在初始化时注入落盘回调。
   * 必须在首次 markDirty 之前调用。
   */
  init(flushCallback: () => void): void {
    this.flushCallback = flushCallback;
  }

  /**
   * 任意变更路径调用：标记脏并排程静默落盘。
   * 已有排程时直接返回（合并窗口内的多次变更只落盘一次）。
   */
  markDirty(): void {
    this.dirty = true;
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      this.flush();
    }, SaveQueue.QUIET_MS);
  }

  /**
   * 立即落盘（onBackground / onSaveState 等兜底时机也可调用）。
   */
  flush(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    if (!this.dirty) {
      return;
    }
    this.dirty = false;
    if (this.flushCallback) {
      this.flushCallback();
      hilog.info(SaveQueue.DOMAIN, SaveQueue.TAG, 'dirty pages flushed');
    }
  }
}
