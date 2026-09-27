import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'PreferencesStore';

/**
 * PreferencesStore —— 系统用户首选项（`@kit.ArkData` / `@ohos.data.preferences`）取实例的薄封装。
 *
 * 为什么需要这一层：
 *   1. 项目有 4 条互相独立的持久化线，每条线一个 **独立的 preferences 实例**（见下方命名表），
 *      避免键冲突与并发写相互覆盖；实例创建 + 失败日志只需在这里写一次。
 *   2. 本层**只做「取实例」和「记日志」**，不替调用方决定失败后返回什么默认值，
 *      避免把「读写失败」伪装成「读到默认值」这种静默失败。
 *
 * 实例命名（含模块名，稳定不变；改名字等于丢数据，不要改）：
 *   callaite_app_state      AppStorage 跨进程状态      （state/StatePersistence）
 *   callaite_plugin_state   插件启用/禁用状态          （plugins/PluginManager）
 *   callaite_pro_state      Pro 订阅缓存               （services/SubscriptionService）
 *   callaite_pdf_highlights PDF 页内高亮               （components/extensions/PdfViewer）
 *
 * API 选型（均已在本机 SDK 的 @ohos.data.preferences.d.ts 中核对）：
 *   - getPreferencesSync(context, options): Preferences   // since 10
 *   - getSync / putSync / hasSync / deleteSync            // since 10
 *   - flushSync(): void                                   // since 14
 *   本模块 compatibleSdkVersion = 26.0.0，以上同步接口均可用；
 *   异步 get/put/flush 需要 Promise 链，而现有 4 处调用点全是同步方法（如 onCreate /
 *   aboutToAppear / enable），改异步会波及调用方签名，故统一使用同步接口。
 *
 * 注意：getSync(key, defValue) 在「存储值类型与 defValue 类型不一致」时返回 defValue，
 * 所以**同一个 key 必须始终写入同一种类型**（见各调用点的注释）。
 */
export class PreferencesStore {
  /** storeName → 实例。同一实例名重复 getPreferencesSync 由系统返回同一实例，这里再做一层缓存避免重复查找。 */
  private static instances: Map<string, preferences.Preferences> = new Map<string, preferences.Preferences>();

  /**
   * 获取指定用途的 Preferences 实例。
   *
   * @param context 应用 Context（本项目统一由 FileService.getContext() 提供）。
   * @param storeName 实例名，对应一个独立的持久化文件；长度 ≤255 字节且不能含斜杠。
   * @throws BusinessError 实例创建失败（磁盘不可用 / name 非法等）时**抛出**，由调用方决定如何降级。
   */
  static open(context: Context, storeName: string): preferences.Preferences {
    const cached: preferences.Preferences | undefined = PreferencesStore.instances.get(storeName);
    if (cached !== undefined) {
      return cached;
    }
    const options: preferences.Options = { name: storeName };
    const store: preferences.Preferences = preferences.getPreferencesSync(context, options);
    PreferencesStore.instances.set(storeName, store);
    return store;
  }

  /** 统一错误日志：读写失败必须留下 hilog.error 痕迹，不能只 catch 掉。 */
  static logError(storeName: string, operation: string, error: Object): void {
    hilog.error(DOMAIN, TAG, 'store=%{public}s op=%{public}s failed: %{public}s',
      storeName, operation, JSON.stringify(error));
  }

  /** 统一警告日志：用于「可继续但需要注意」的情况（如 context 未就绪、旧值类型不符）。 */
  static logWarn(storeName: string, message: string): void {
    hilog.warn(DOMAIN, TAG, 'store=%{public}s %{public}s', storeName, message);
  }

  /** 统一信息日志：用于一次性数据迁移这类需要留痕的动作。 */
  static logInfo(storeName: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'store=%{public}s %{public}s', storeName, message);
  }
}
