import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { FileService } from './FileService';
import { util } from '@kit.ArkTS';
import { HuaweiAccountService } from './HuaweiAccountService';
import { fileIo as fs } from '@kit.CoreFileKit';

interface ProStateCache {
  isPro: boolean;
  expiresTime: number;
}

export class SubscriptionService {
  static readonly FREE_GRAPH_LIMIT = 1;
  static readonly PRO_GRAPH_LIMIT = 10;
  static readonly PRO_PRODUCT_ID = 'callaite_pro_monthly';
  private static readonly PRO_STATE_FILE = 'callaite_pro_state.json';
  private static readonly REFRESH_INTERVAL_MS = 24 * 60 * 60 * 1000;

  private static isPro: boolean = false;
  private static proExpiry: number = 0;
  private static refreshTimerId: number = -1;

  /**
   * 从沙箱文件恢复缓存的 Pro 状态（离线启动时仍可识别未过期的订阅）。
   */
  static initCachedProState(): void {
    try {
      const ctx = FileService.getContext();
      if (!ctx) {
        return;
      }
      const path = ctx.filesDir + '/' + SubscriptionService.PRO_STATE_FILE;
      if (!fs.accessSync(path)) {
        return;
      }
      const raw = fs.readTextSync(path).trim();
      if (raw === '') {
        return;
      }
      const parsed = JSON.parse(raw) as ProStateCache;
      const expiry = Number(parsed.expiresTime);
      if (parsed.isPro === true && expiry > Date.now()) {
        SubscriptionService.isPro = true;
        SubscriptionService.proExpiry = expiry;
      }
    } catch (_e) {
      // 缓存损坏时忽略，走网络刷新
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

  private static setPro(pro: boolean, expiry: number): void {
    SubscriptionService.isPro = pro;
    SubscriptionService.proExpiry = expiry;
    SubscriptionService.saveProState();
  }

  private static saveProState(): void {
    try {
      const ctx = FileService.getContext();
      if (!ctx) {
        return;
      }
      const path = ctx.filesDir + '/' + SubscriptionService.PRO_STATE_FILE;
      const cache: ProStateCache = {
        isPro: SubscriptionService.isPro,
        expiresTime: SubscriptionService.proExpiry
      };
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(cache));
      fs.closeSync(file);
    } catch (_e) {
      // 持久化失败不影响内存状态
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
              SubscriptionService.setPro(true, Number(lastStatus['expiresTime']));
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
