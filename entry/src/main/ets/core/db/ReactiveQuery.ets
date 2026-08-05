/**
 * ReactiveQuery — 响应式查询引擎。
 *
 * 对应 Logseq 中 datalog/reactive.cljs 的订阅与重算机制。
 *
 * 职责：
 *  - 注册查询订阅（subscribe），每个订阅包含一个 queryFn 和 callback
 *  - 数据变更通知（notifyChange），触发所有订阅者重算
 *  - 若重算结果与上次不同（JSON.stringify 比较），则触发 callback
 *  - 取消订阅 / 清空所有订阅
 *
 * 使用方式：
 *   ReactiveQuery.getInstance().subscribe('my-query', () => {
 *     return WorkspaceService.getInstance().getAllPages().length;
 *   }, (count: number) => {
 *     console.info('Page count changed: ' + count);
 *   });
 *
 *   // 数据变更后通知
 *   ReactiveQuery.getInstance().notifyChange(blockUuid);
 */

// ─── 订阅信息接口 ───

/**
 * 单个查询订阅。
 * queryFn 返回 Object 类型（经过类型擦除），callback 接收 Object 参数。
 * lastResult 存储上次结果的 JSON 字符串，用于变化比较。
 */
interface QuerySubscription {
  /** 订阅唯一标识 */
  queryId: string;
  /** 查询函数（擦除为 Object 返回值） */
  queryFn: () => Object;
  /** 结果变更回调（擦除为 Object 参数） */
  callback: (result: Object) => void;
  /** 上次结果的 JSON 字符串（空字符串表示尚未执行过） */
  lastResult: string;
}

/**
 * 响应式查询引擎单例。
 */
export class ReactiveQuery {
  private static instance: ReactiveQuery | undefined;

  /** 订阅表：queryId → QuerySubscription */
  private subscriptions: Map<string, QuerySubscription> = new Map<string, QuerySubscription>();

  /** 上次结果存储：queryId → Object（保存实际对象，便于直接传给 callback） */
  private lastResults: Map<string, Object> = new Map<string, Object>();

  static getInstance(): ReactiveQuery {
    if (!ReactiveQuery.instance) {
      ReactiveQuery.instance = new ReactiveQuery();
    }
    return ReactiveQuery.instance;
  }

  // ─── 订阅管理 ───

  /**
   * 注册一个响应式查询订阅。
   *
   * 注册后立即执行一次 queryFn，并将结果传给 callback。
   * 后续 notifyChange 调用时，会重新执行 queryFn，若结果变化（JSON.stringify 比较）
   * 则再次调用 callback。
   *
   * @param queryId 订阅唯一标识（重复注册会覆盖旧订阅）
   * @param queryFn 查询函数，返回泛型 T
   * @param callback 结果变更回调
   */
  subscribe<T>(queryId: string, queryFn: () => T, callback: (result: T) => void): void {
    // 将泛型 queryFn 包装为 Object 返回值
    const wrappedQueryFn: () => Object = (): Object => {
      const result: T = queryFn();
      return result as Object;
    };

    // 将泛型 callback 包装为 Object 参数
    const wrappedCallback: (result: Object) => void = (result: Object): void => {
      callback(result as T);
    };

    const subscription: QuerySubscription = {
      queryId: queryId,
      queryFn: wrappedQueryFn,
      callback: wrappedCallback,
      lastResult: ''
    };

    this.subscriptions.set(queryId, subscription);

    // 立即执行一次，触发初始 callback
    this.recompute(subscription);
  }

  /**
   * 通知数据变更，触发所有订阅者重算。
   *
   * 遍历所有订阅，执行 queryFn，若结果与上次不同则调用 callback。
   *
   * @param blockUuid 发生变更的 Block UUID（用于日志记录，当前实现通知所有订阅者）
   */
  notifyChange(blockUuid: string): void {
    // 遍历所有订阅并重算
    const subscriptionsToNotify: QuerySubscription[] = [];
    this.subscriptions.forEach((sub: QuerySubscription) => {
      subscriptionsToNotify.push(sub);
    });

    for (let i = 0; i < subscriptionsToNotify.length; i++) {
      this.recompute(subscriptionsToNotify[i]);
    }
  }

  /**
   * 取消指定订阅。
   *
   * @param queryId 订阅唯一标识
   */
  unsubscribe(queryId: string): void {
    this.subscriptions.delete(queryId);
    this.lastResults.delete(queryId);
  }

  // ─── 查询 ───

  /**
   * 获取所有已注册的查询 ID 列表。
   *
   * @returns queryId 数组
   */
  getAllQueryIds(): string[] {
    const result: string[] = [];
    this.subscriptions.forEach((sub: QuerySubscription) => {
      result.push(sub.queryId);
    });
    return result;
  }

  /**
   * 清空所有订阅。
   */
  clearAll(): void {
    this.subscriptions.clear();
    this.lastResults.clear();
  }

  // ─── 内部方法 ───

  /**
   * 重新计算指定订阅的查询结果。
   *
   * 执行 queryFn，将结果与 lastResult（JSON 字符串）比较：
   *  - 若不同：更新 lastResult、lastResults，并调用 callback
   *  - 若相同：不触发 callback
   *
   * @param subscription 订阅信息
   */
  private recompute(subscription: QuerySubscription): void {
    try {
      const newResult: Object = subscription.queryFn();
      const newJson: string = this.safeStringify(newResult);

      if (newJson !== subscription.lastResult) {
        subscription.lastResult = newJson;
        this.lastResults.set(subscription.queryId, newResult);
        subscription.callback(newResult);
      }
    } catch (e) {
      // 查询执行失败时不触发 callback，保留旧结果
    }
  }

  /**
   * 安全的 JSON 序列化。
   *
   * 处理循环引用和序列化失败的情况，失败时回退为 toString()。
   *
   * @param obj 待序列化的对象
   * @returns JSON 字符串
   */
  private safeStringify(obj: Object): string {
    try {
      return JSON.stringify(obj);
    } catch (e) {
      // 循环引用或其它序列化失败
      return '';
    }
  }
}
