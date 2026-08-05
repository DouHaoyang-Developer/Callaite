import { OutlinerOp, OpResult } from './OutlinerOps';
import { WorkspaceService } from '../../services/WorkspaceService';

/**
 * TransactionPipeline — 事务管道。
 *
 * 对应 Logseq db/transact.cljs 中的批量事务支持。
 *
 * 职责：
 *  - 将多个 OutlinerOp 组合为原子事务
 *  - 全部成功则提交，任一失败则回滚已执行的操作
 *  - 支持事务后手动 rollback（撤销整个已提交事务）
 *
 * 使用方式：
 *   const pipeline = TransactionPipeline.getInstance();
 *   pipeline.begin();
 *   pipeline.add(op1);
 *   pipeline.add(op2);
 *   const results = pipeline.commit();
 *   if (results.length === 0) {
 *     // 事务失败，已自动回滚
 *   }
 */
export class TransactionPipeline {
  private static instance: TransactionPipeline | undefined;

  // 待执行的操作队列
  private ops: OutlinerOp[] = [];
  // 是否处于事务中
  private inTransaction: boolean = false;
  // 已成功执行的操作结果（用于回滚）
  private savedResults: OpResult[] = [];

  static getInstance(): TransactionPipeline {
    if (!TransactionPipeline.instance) {
      TransactionPipeline.instance = new TransactionPipeline();
    }
    return TransactionPipeline.instance;
  }

  // ─── 事务控制 ───

  /**
   * 开始一个新事务。
   * 清空待执行队列和已保存结果，标记事务开始。
   */
  begin(): void {
    this.ops = [];
    this.savedResults = [];
    this.inTransaction = true;
  }

  /**
   * 添加操作到事务队列。
   * 仅在事务进行中有效。
   */
  add(op: OutlinerOp): void {
    if (!this.inTransaction) {
      return;
    }
    this.ops.push(op);
  }

  /**
   * 提交事务：逐个执行队列中的操作。
   *
   * - 全部成功：返回结果数组，savedResults 保留以供后续 rollback
   * - 任一失败：自动回滚已执行的操作，返回空数组
   *
   * @returns 成功时返回所有操作的结果；失败时返回空数组
   */
  commit(): OpResult[] {
    if (!this.inTransaction) {
      return [];
    }

    const results: OpResult[] = [];

    for (let i = 0; i < this.ops.length; i++) {
      const result = WorkspaceService.getInstance().executeOp(this.ops[i]);

      if (result.success) {
        results.push(result);
        this.savedResults.push(result);
      } else {
        // 失败：先撤销失败的 op（从 undo 栈中移除），再回滚所有已成功的 op
        WorkspaceService.getInstance().getOutlinerEngine().undo();
        this.rollback();
        return [];
      }
    }

    // 全部成功：清理事务状态，但保留 savedResults 以支持后续 rollback
    this.ops = [];
    this.inTransaction = false;
    return results;
  }

  /**
   * 回滚事务：撤销所有已执行的操作。
   *
   * 可在以下场景调用：
   *  - commit 失败后（内部自动调用）
   *  - commit 成功后手动调用（撤销整个已提交事务）
   *  - begin 之后、commit 之前（取消事务）
   */
  rollback(): void {
    const engine = WorkspaceService.getInstance().getOutlinerEngine();
    for (let i = 0; i < this.savedResults.length; i++) {
      engine.undo();
    }
    this.savedResults = [];
    this.ops = [];
    this.inTransaction = false;
  }

  // ─── 状态查询 ───

  /**
   * 是否处于事务中。
   */
  isInTransaction(): boolean {
    return this.inTransaction;
  }

  /**
   * 获取待执行的操作数量。
   */
  getPendingCount(): number {
    return this.ops.length;
  }

  /**
   * 获取已执行成功的操作数量（事务提交后可用）。
   */
  getCommittedCount(): number {
    return this.savedResults.length;
  }
}
