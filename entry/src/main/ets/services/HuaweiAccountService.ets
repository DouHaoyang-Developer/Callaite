import { distributedAccount } from '@kit.BasicServicesKit';

/**
 * 华为账号（分布式账号）信息。
 */
export interface HuaweiAccountInfo {
  id: string;
  name: string;
  nickname: string;
  avatar: string;
  isLoggedIn: boolean;
}

/**
 * HuaweiAccountService — 华为账号服务。
 *
 * 通过 distributedAccount 查询当前系统的华为账号（分布式账号）状态，
 * 用于：
 *  - 设置页展示账号信息
 *  - 云同步（端云协同）前置校验：未登录时禁止同步
 *  - IAP 订阅状态绑定：账号变化/未登录时刷新 Pro 状态
 *
 * 依赖权限：ohos.permission.DISTRIBUTED_DATASYNC（module.json5 已声明）。
 */
export class HuaweiAccountService {
  private static cache: HuaweiAccountInfo | undefined;

  /**
   * 刷新并返回当前华为账号信息；失败/未登录返回 isLoggedIn=false 的占位对象。
   */
  static async refresh(): Promise<HuaweiAccountInfo> {
    try {
      const ability = distributedAccount.getDistributedAccountAbility();
      const info = await ability.getOsAccountDistributedInfo();
      const account: HuaweiAccountInfo = {
        id: info.id ?? '',
        name: info.name ?? '',
        nickname: info.nickname ?? '',
        avatar: info.avatar ?? '',
        isLoggedIn: HuaweiAccountService.detectLoggedIn(info)
      };
      HuaweiAccountService.cache = account;
      return account;
    } catch (_e) {
      const fallback: HuaweiAccountInfo = {
        id: '',
        name: '',
        nickname: '',
        avatar: '',
        isLoggedIn: false
      };
      HuaweiAccountService.cache = fallback;
      return fallback;
    }
  }

  /**
   * 获取缓存的账号信息（未刷新过则返回未登录占位）。
   */
  static getCached(): HuaweiAccountInfo {
    if (HuaweiAccountService.cache) {
      return HuaweiAccountService.cache;
    }
    return {
      id: '',
      name: '',
      nickname: '',
      avatar: '',
      isLoggedIn: false
    };
  }

  /**
   * 判断当前是否已登录华为账号。
   */
  static async isLoggedIn(): Promise<boolean> {
    const info = await HuaweiAccountService.refresh();
    return info.isLoggedIn;
  }

  /**
   * 获取展示名称（昵称优先，其次账号名）。
   */
  static displayName(): string {
    const info = HuaweiAccountService.getCached();
    if (info.nickname !== '') {
      return info.nickname;
    }
    if (info.name !== '') {
      return info.name;
    }
    return '';
  }

  private static detectLoggedIn(info: distributedAccount.DistributedInfo): boolean {
    if (info.status === distributedAccount.DistributedAccountStatus.LOGGED_IN) {
      return true;
    }
    if (info.status === distributedAccount.DistributedAccountStatus.NOT_LOGGED_IN) {
      return false;
    }
    // 旧版本可能不返回 status，按 id 是否为空兜底判断
    return info.id !== undefined && info.id !== '';
  }
}
