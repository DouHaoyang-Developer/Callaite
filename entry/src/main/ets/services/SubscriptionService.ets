import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from './FileService';
import { util } from '@kit.ArkTS';
import { HuaweiAccountService } from './HuaweiAccountService';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PreferencesStore } from '../utils/PreferencesStore';

const DOMAIN = 0x0001;
const TAG = 'SubscriptionService';

interface ProStateCache {
  isPro: boolean;
  expiresTime: number;
}

export class SubscriptionService {
  static readonly FREE_GRAPH_LIMIT = 1;
  static readonly PRO_GRAPH_LIMIT = 10;
  static readonly PRO_PRODUCT_ID = 'callaite_pro_monthly';
  /** 旧版自研 JSON 持久化文件（仅用于一次性迁移，迁移后删除） */
  private static readonly PRO_STATE_FILE = 'callaite_pro_state.json';
  /** 本持久化线专用的 preferences 实例名（稳定性要求：改名即丢数据） */
  private static readonly PRO_STORE_NAME = 'callaite_pro_state';
  /** preferences 键：两者必须始终是同一类型（boolean / number），否则 getSync 会回落到 defValue */
  private static readonly KEY_IS_PRO = 'isPro';
  private static readonly KEY_EXPIRES_TIME = 'expiresTime';
  private static readonly REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000;

  private static isPro: boolean = false;
  private static proExpiry: number = 0;
  private static refreshTimerId: number = -1;

  /**
   * 从 preferences 恢复缓存的 Pro 状态（离线启动时仍可识别未过期的订阅）。
   *
   * 首次运行（preferences 中尚无本线任一键）且旧的 callaite_pro_state.json 仍存在时，
   * 一次性把旧文件内容迁入 preferences 并删除旧文件。
   *
   * @returns true 表示读取流程正常结束（含「无缓存」这一正常情况）；false 表示 context 缺失或读写失败（已 hilog.error）。
   */
  static initCachedProState(): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'context 未就绪，跳过 Pro 缓存恢复');
      return false;
    }
    let store: preferences.Preferences;
    try {
      store = PreferencesStore.open(ctx, SubscriptionService.PRO_STORE_NAME);
    } catch (e) {
      PreferencesStore.logError(SubscriptionService.PRO_STORE_NAME, 'getPreferencesSync', e as Object);
      return false;
    }
    try {
      // ─── 一次性迁移 ───
      // 触发条件：preferences 中两个键都不存在（= 从未用 preferences 写过本线数据），且旧 JSON 文件存在。
      // 只要 preferences 已有任一键，就认为已完成迁移，旧文件即使残留也不再读取。
      if (!store.hasSync(SubscriptionService.KEY_IS_PRO)
        && !store.hasSync(SubscriptionService.KEY_EXPIRES_TIME)) {
        SubscriptionService.migrateLegacyProState(store, ctx);
      }
      if (!store.hasSync(SubscriptionService.KEY_IS_PRO)) {
        // 全新安装：无任何缓存，保持内存默认值（isPro=false / proExpiry=0）
        return true;
      }
      // 与旧实现同一套有效性判定：必须 isPro === true 且未过期才认
      const cachedPro: boolean = store.getSync(SubscriptionService.KEY_IS_PRO, false) as boolean;
      const expiry: number = store.getSync(SubscriptionService.KEY_EXPIRES_TIME, 0) as number;
      if (cachedPro === true && expiry > Date.now()) {
        SubscriptionService.isPro = true;
        SubscriptionService.proExpiry = expiry;
      }
      return true;
    } catch (e) {
      PreferencesStore.logError(SubscriptionService.PRO_STORE_NAME, 'read cached pro state', e as Object);
      return false;
    }
  }

  /**
   * 把旧 JSON 文件（filesDir/callaite_pro_state.json）的内容迁入 preferences，随后删除旧文件。
   *
   * 旧文件结构：{"isPro": boolean, "expiresTime": number}（见 ProStateCache）。
   * 迁移写入的键类型与正常写入路径保持一致，避免 getSync 因类型不匹配回落到 defValue。
   */
  private static migrateLegacyProState(store: preferences.Preferences, ctx: Context): void {
    const path = ctx.filesDir + '/' + SubscriptionService.PRO_STATE_FILE;
    let exists = false;
    try {
      exists = fs.accessSync(path);
    } catch (e) {
      PreferencesStore.logError(SubscriptionService.PRO_STORE_NAME, 'accessSync(legacy)', e as Object);
      return;
    }
    if (!exists) {
      return;
    }
    try {
      const raw = fs.readTextSync(path).trim();
      if (raw !== '') {
        const parsed = JSON.parse(raw) as ProStateCache;
        let expiry: number = Number(parsed.expiresTime);
        if (!(expiry > 0)) {
          // NaN / 负数 / 0 一律归一为 0，避免把非法数值写进 preferences
          expiry = 0;
        }
        store.putSync(SubscriptionService.KEY_IS_PRO, parsed.isPro === true);
        store.putSync(SubscriptionService.KEY_EXPIRES_TIME, expiry);
        store.flushSync();
      }
      // 迁移完成：旧文件不再是真相来源，删除它（失败仅记录，不影响内存状态）
      fs.unlinkSync(path);
      PreferencesStore.logInfo(SubscriptionService.PRO_STORE_NAME,
        'migrated legacy file, removed ' + path);
    } catch (e) {
      PreferencesStore.logError(SubscriptionService.PRO_STORE_NAME, 'migrate legacy file', e as Object);
    }
  }

  /**
   * 启动 24 小时定时刷新订阅状态。
   */
  static startPeriodicRefresh(): void {
    SubscriptionService.stopPeriodicRefresh();
    SubscriptionService.scheduleRefresh();
  }

  static stopPeriodicRefresh(): void {
    if (SubscriptionService.refreshTimerId !== -1) {
      clearTimeout(SubscriptionService.refreshTimerId);
      SubscriptionService.refreshTimerId = -1;
    }
  }

  private static scheduleRefresh(): void {
    SubscriptionService.refreshTimerId = setTimeout(() => {
      SubscriptionService.refreshProStatus().then(() => {
        SubscriptionService.scheduleRefresh();
      }).catch(() => {
        SubscriptionService.scheduleRefresh();
      });
    }, SubscriptionService.REFRESH_INTERVAL_MS);
  }

  /**
   * 更新内存中的 Pro 状态并持久化。
   * @returns true 表示已成功写入 preferences；false 表示持久化失败（已 hilog.error，内存状态仍然生效）。
   */
  private static setPro(pro: boolean, expiry: number): boolean {
    SubscriptionService.isPro = pro;
    SubscriptionService.proExpiry = expiry;
    return SubscriptionService.saveProState();
  }

  /**
   * 把 Pro 状态写入 preferences（实例名 callaite_pro_state，键 isPro / expiresTime）。
   *
   * 与旧实现一致：每次状态变化都落盘（含 isPro=false 的负结果），这样离线启动能识别
   * 「上次网络刷新判定为非 Pro」，也把迁移标记为已完成。
   * 失败不再静默：hilog.error 记录并返回 false。
   */
  private static saveProState(): boolean {
    const ctx = FileService.getContext();
    if (!ctx) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'saveProState: context 未就绪，Pro 状态未持久化');
      return false;
    }
    try {
      const store: preferences.Preferences = PreferencesStore.open(ctx, SubscriptionService.PRO_STORE_NAME);
      store.putSync(SubscriptionService.KEY_IS_PRO, SubscriptionService.isPro);
      store.putSync(SubscriptionService.KEY_EXPIRES_TIME, SubscriptionService.proExpiry);
      // XML 存储（默认）必须 flush 才真正落盘
      store.flushSync();
      return true;
    } catch (e) {
      PreferencesStore.logError(SubscriptionService.PRO_STORE_NAME, 'saveProState', e as Object);
      return false;
    }
  }

  static async refreshProStatus(): Promise<boolean> {
    try {
      // 绑定华为账号：未登录时直接返回非 Pro，避免使用缓存或旧账号的订阅状态
      const accountOk = await HuaweiAccountService.isLoggedIn();
      if (!accountOk) {
        SubscriptionService.setPro(false, 0);
        return false;
      }
      const ctx = FileService.getContext() as common.UIAbilityContext;
      if (!ctx) {
        SubscriptionService.setPro(false, 0);
        return false;
      }

      const param: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.AUTORENEWABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      };

      const result: iap.QueryPurchaseResult = await iap.queryPurchases(ctx, param);
      const dataList: string[] = result.purchaseDataList;
      if (!dataList || dataList.length === 0) {
        SubscriptionService.setPro(false, 0);
        return false;
      }

      for (let i = 0; i < dataList.length; i++) {
        const purchase = JSON.parse(dataList[i]) as Record<string, Object>;
        const statusJws: string = purchase['jwsSubscriptionStatus'] as string;
        if (statusJws) {
          const payloadStr = SubscriptionService.decodeJwsPayload(statusJws);
          const statusObj = JSON.parse(payloadStr) as Record<string, Object>;
          const lastStatus = statusObj['lastSubscriptionStatus'] as Record<string, Object>;
          if (lastStatus) {
            const statusCode = Number(lastStatus['status']);
            if (statusCode === 1) {
              if (!SubscriptionService.setPro(true, Number(lastStatus['expiresTime']))) {
                // 网络已确认 Pro，但缓存写入失败：本次会话生效，下次启动会重新走网络刷新
                hilog.error(DOMAIN, TAG, '%{public}s',
                  'Pro 订阅已确认但持久化失败，重启后需依赖网络刷新');
              }
              return true;
            }
          }
        }
      }
      SubscriptionService.setPro(false, 0);
      return false;
    } catch (e) {
      return SubscriptionService.isPro;
    }
  }

  static async purchasePro(): Promise<boolean> {
    try {
      const ctx = FileService.getContext() as common.UIAbilityContext;
      if (!ctx) return false;

      const result: iap.CreatePurchaseResult = await iap.createPurchase(ctx, {
        productType: iap.ProductType.AUTORENEWABLE,
        productId: SubscriptionService.PRO_PRODUCT_ID
      });

      if (result.purchaseData) {
        await SubscriptionService.finishAndRefresh(result.purchaseData);
        return SubscriptionService.isPro;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  private static async finishAndRefresh(purchaseData: string): Promise<void> {
    try {
      const parsed = JSON.parse(purchaseData) as Record<string, Object>;
      const token: string = parsed['purchaseToken'] as string;
      if (token) {
        const ctx2 = FileService.getContext() as common.UIAbilityContext;
        if (ctx2) {
          const orderId: string = parsed['purchaseOrderId'] as string;
          const prodType: number = Number(parsed['productType']);
          await iap.finishPurchase(ctx2, {
            purchaseToken: token,
            productType: prodType,
            purchaseOrderId: orderId
          });
        }
      }
    } catch (_e) {
      // ignore
    }
    await SubscriptionService.refreshProStatus();
  }

  static canSyncGraph(syncedCount: number): boolean {
    const limit = SubscriptionService.isPro ? SubscriptionService.PRO_GRAPH_LIMIT : SubscriptionService.FREE_GRAPH_LIMIT;
    return syncedCount < limit;
  }

  static canSync(): boolean {
    return true;
  }

  static checkPro(): boolean {
    return SubscriptionService.isPro;
  }

  static getGraphLimit(): number {
    return SubscriptionService.isPro ? SubscriptionService.PRO_GRAPH_LIMIT : SubscriptionService.FREE_GRAPH_LIMIT;
  }

  static canUseFeature(feature: string): boolean {
    if (SubscriptionService.isPro) return true;
    if (feature === 'sync' || feature === 'flow') return true;
    return false;
  }

  private static decodeJwsPayload(jws: string): string {
    const parts = jws.split('.');
    if (parts.length < 2) return '{}';
    // JWS payload 使用 base64url（无填充，-/_ 替代 +//），需先转回标准 base64
    let b64 = parts[1].replace(new RegExp('-', 'g'), '+').replace(new RegExp('_', 'g'), '/');
    const pad = b64.length % 4;
    if (pad === 2) {
      b64 = b64 + '==';
    } else if (pad === 3) {
      b64 = b64 + '=';
    }
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const bytes: number[] = [];
    let i = 0;
    while (i < b64.length) {
      const c1 = chars.indexOf(b64.charAt(i));
      const c2 = chars.indexOf(b64.charAt(i + 1));
      const c3 = b64.charAt(i + 2) === '=' ? 0 : chars.indexOf(b64.charAt(i + 2));
      const c4 = b64.charAt(i + 3) === '=' ? 0 : chars.indexOf(b64.charAt(i + 3));
      bytes.push((c1 << 2) | (c2 >> 4));
      if (b64.charAt(i + 2) !== '=') {
        bytes.push(((c2 & 15) << 4) | (c3 >> 2));
      }
      if (b64.charAt(i + 3) !== '=') {
        bytes.push(((c3 & 3) << 6) | c4);
      }
      i += 4;
    }
    const arr = new Uint8Array(bytes.length);
    for (let j = 0; j < bytes.length; j++) {
      arr[j] = bytes[j];
    }
    const decoder = new util.TextDecoder();
    return decoder.decodeToString(arr);
  }
}
