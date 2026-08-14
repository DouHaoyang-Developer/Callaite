import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppState } from '../state/AppState';
import { ThemeManager } from '../components/common/ThemeManager';
import { FileService } from '../services/FileService';
import { WorkspaceService } from '../services/WorkspaceService';
import { TestDataService } from '../services/TestDataService';
import { CollaborationService } from '../services/CollaborationService';
import { SubscriptionService } from '../services/SubscriptionService';
import { EncryptionService } from '../services/EncryptionService';
import { CloudSyncService } from '../services/CloudSyncService';
import { registerBuiltinPlugins } from '../plugins/BuiltinPlugins';
import { ContinuationManager } from '../services/ContinuationManager';
import { HuaweiAccountService } from '../services/HuaweiAccountService';
import { BlockMetadataSyncService } from '../services/BlockMetadataSyncService';
import { ErrorRecoveryService } from '../services/ErrorRecoveryService';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onCreate');

    // 设置应用上下文（FileService 需要 context 获取沙箱路径）
    FileService.setContext(this.context);

    // 启用崩溃恢复与全局异常捕获
    ErrorRecoveryService.init();

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onDestroy');
  }

  /**
   * 应用异常/后台时由框架调用，保存应用数据以便崩溃恢复后继续使用。
   */
  onSaveState(reason: AbilityConstant.StateType, wantParam: Record<string, Object>): AbilityConstant.OnSaveResult {
    hilog.info(DOMAIN, 'EntryAbility', 'onSaveState reason=%{public}d', reason);
    try {
      WorkspaceService.getInstance().saveAll();
    } catch (_e) {
      // 保存失败不阻塞
    }
    return AbilityConstant.OnSaveResult.ALL_AGREE;
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onWindowStageCreate');

    // ─── 启动链（对应迁移计划 §启动链） ───
    // 1. 初始化文件服务并加载 Graph
    FileService.initGraph();

    // 1.5 播种测试数据
    TestDataService.seedIfEmpty();

    // 1.6 初始化分布式协同
    CollaborationService.getInstance().init(this.context);

    // 1.7 恢复缓存 + 启动 24h 定时刷新 + 网络刷新 Pro 订阅状态
    SubscriptionService.initCachedProState();
    SubscriptionService.startPeriodicRefresh();
    SubscriptionService.refreshProStatus();

    // 1.75 刷新华为账号状态（云同步与 IAP 依赖）
    HuaweiAccountService.refresh().then(() => {
      hilog.info(DOMAIN, 'EntryAbility', 'Huawei account refreshed: %{public}s',
        HuaweiAccountService.displayName());
    }).catch(() => {});

    // 1.8 初始化加密服务
    EncryptionService.init();

    // 1.9 初始化端云协同目录
    CloudSyncService.initCloudDir();

    // 1.10 初始化插件系统
    registerBuiltinPlugins();

    // 2. 初始化全局状态（主题、i18n、AppStorage 默认值）
    AppState.initialize();

    // 3. 加载主页面
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'EntryAbility', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onBackground');

    // 后台时保存所有页面
    try {
      WorkspaceService.getInstance().saveAll();
    } catch (_e) {
      // 保存失败不阻塞
    }

    // 保存后触发端云协同同步
    try {
      CloudSyncService.syncAll().then((count: number) => {
        hilog.info(DOMAIN, 'EntryAbility', 'Cloud sync done: %{public}d files', count);
        // 文件同步完成后同步 Block 元数据索引
        BlockMetadataSyncService.syncToCloud().catch(() => {});
      }).catch(() => {});
    } catch (_e) {
      // 云同步失败不阻塞
    }
  }

  // ─── 多端流转（Continuation） ───

  /**
   * 源端流转回调：在设备迁移前将应用状态写入 wantParam。
   * SDK 签名要求返回 AbilityConstant.OnContinueResult，表示是否同意流转。
   */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onContinue — preparing migration');
    const want: Want = {
      parameters: wantParam
    };
    ContinuationManager.saveToContinue(want);
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /**
   * 目标端流转回调：从 want 恢复应用状态。
   * 在 onCreate 之后、onWindowStageCreate 之前调用。
   */
  onRestoreData(want: Want): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onRestoreData — restoring state');
    ContinuationManager.restoreFromContinue(want);
  }
}
