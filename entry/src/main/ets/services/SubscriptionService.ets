import { iap } from '@kit.IAPKit';
import { common } from '@kit.AbilityKit';
import { FileService } from './FileService';

export class SubscriptionService {
  static readonly FREE_GRAPH_LIMIT = 1;
  static readonly PRO_GRAPH_LIMIT = 10;
  static readonly PRO_PRODUCT_ID = 'callaite_pro_monthly';

  private static isPro: boolean = false;
  private static proExpiry: number = 0;

  static async refreshProStatus(): Promise<boolean> {
    try {
      const ctx = FileService.getContext() as common.UIAbilityContext;
      if (!ctx) return false;

      const param: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.AUTORENEWABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      };

      const result: iap.QueryPurchaseResult = await iap.queryPurchases(ctx, param);
      const dataList: string[] = result.purchaseDataList;
      if (!dataList || dataList.length === 0) {
        SubscriptionService.isPro = false;
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
            const statusCode: string = lastStatus['status'] as string;
            if (statusCode === '1') {
              SubscriptionService.isPro = true;
              SubscriptionService.proExpiry = lastStatus['expiresTime'] as number;
              return true;
            }
          }
        }
      }
      SubscriptionService.isPro = false;
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
          const prodType: number = parsed['productType'] as number;
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
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let result = '';
    const str = parts[1];
    let i = 0;
    while (i < str.length) {
      const i1 = chars.indexOf(str.charAt(i)); const i2 = chars.indexOf(str.charAt(i + 1));
      const i3 = chars.indexOf(str.charAt(i + 2)); const i4 = chars.indexOf(str.charAt(i + 3));
      result += String.fromCharCode((i1 << 2) | (i2 >> 4));
      if (i3 !== 64) result += String.fromCharCode(((i2 & 15) << 4) | (i3 >> 2));
      if (i4 !== 64) result += String.fromCharCode(((i3 & 3) << 6) | i4);
      i += 4;
    }
    return result;
  }
}
