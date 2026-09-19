import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';
import { AppState } from '../state/AppState';
import { TabState } from '../state/TabState';
import { ThemeManager } from '../components/common/ThemeManager';
import { FileService } from '../services/FileService';
import { WorkspaceService } from '../services/WorkspaceService';
import { CollaborationService } from '../services/CollaborationService';
import { SubscriptionService } from '../services/SubscriptionService';
import { EncryptionService } from '../services/EncryptionService';
import { CloudSyncService } from '../services/CloudSyncService';
import { registerBuiltinPlugins } from '../plugins/BuiltinPlugins';
import { ContinuationManager } from '../services/ContinuationManager';
import { HuaweiAccountService } from '../services/HuaweiAccountService';
import { BlockMetadataSyncService } from '../services/BlockMetadataSyncService';
import { ErrorRecoveryService } from '../services/ErrorRecoveryService';
import { StatePersistence } from '../state/StatePersistence';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onCreate');

    // 设置应用上下文（FileService 需要 context 获取沙箱路径）
    FileService.setContext(this.context);

    // 恢复跨进程状态（引导标志/主题/语言/配置等），必须在任何 UI 加载前执行
    StatePersistence.load();

    // 启用崩溃恢复与全局异常捕获
    ErrorRecoveryService.init();

    try {
      // 启动初期先跟随系统，持久化主题在 AppState.initialize 之后由 applyPersistedTheme 应用
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

    // 2.2 初始化 Obsidian 式标签页状态（至少一个 Journal 标签）
    TabState.initialize();

    // 2.5 应用持久化主题（必须在 AppStorage 初始化后、loadContent 前执行，
    //     否则 dark/light 资源限定符不会切换，主题设置形同虚设）
    ThemeManager.applyPersistedTheme();

    // 3. 加载主页面
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EntryAbility', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'EntryAbility', 'Succeeded in loading the content.');
      // 4. 延后到首帧渲染完成再切换沉浸式。
      //    不能在 loadContent 回调里同步切换：此时窗口场景尚未完全就绪，
      //    切换会与 onForeground 的场景创建竞争（实测触发
      //    DoOnForegroundForSceneIsNull → WindowSession 创建 → 阻塞在渲染服务 IPC，
      //    最终 LIFECYCLE_TIMEOUT 并连带渲染服务冻结）。
      setTimeout(() => {
        this.setupImmersiveLayout(windowStage);
      }, 350);
    });
  }

  /**
   * 沉浸式布局 —— 让应用内容延伸到状态栏/导航条之下，使悬浮玻璃栏与内容真正融合。
   *
   * 不做这件事时，系统会把状态栏与导航条区域留成独立色块，应用背景无法延伸到
   * 该区域，导致顶部/底部出现一条与页面割裂的横带（官方 7.1.2.6.1 状态栏
   * 背景色与页面背景色一致性、7.1.2.7.8 标题栏沉浸均不达标）。
   *
   * 同时发布安全区尺寸：启用沉浸式后系统栏会覆盖在内容之上，UI 必须自行避让，
   * 否则标题会被状态栏遮挡、底部操作栏会与导航条重叠。
   */
  private setupImmersiveLayout(windowStage: window.WindowStage): void {
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true).then(() => {
        this.publishAvoidArea(win);
        this.applySystemBarStyle(win);
      }).catch((err: Object) => {
        hilog.warn(DOMAIN, 'EntryAbility', 'setWindowLayoutFullScreen failed: %{public}s', JSON.stringify(err));
        this.publishAvoidArea(win);
      });
      // 折叠/旋转/分屏会改变避让区，需重新发布
      win.on('avoidAreaChange', () => {
        this.publishAvoidArea(win);
      });
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to setup immersive layout. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 把系统栏避让区换算为 vp 写入 AppStorage，供 UI 层避让。
   */
  private publishAvoidArea(win: window.Window): void {
    try {
      let density = 3.5;
      try {
        const d = display.getDefaultDisplaySync();
        if (d.densityPixels > 0) {
          density = d.densityPixels;
        }
      } catch (e) {
        // 取不到密度时沿用默认值
      }
      const statusArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const topVp: number = statusArea.topRect.height / density;
      const bottomVp: number = navArea.bottomRect.height / density;
      // 仅在数值真正变化时写入：避免 avoidAreaChange → AppStorage → 重排版
      // → 再次 avoidAreaChange 的自激循环（会把渲染服务打满）。
      const prevTop: number | undefined = AppStorage.get<number>('callaite_safeTop');
      const prevBottom: number | undefined = AppStorage.get<number>('callaite_safeBottom');
      if (prevTop === undefined || Math.abs(prevTop - topVp) > 0.5) {
        AppStorage.setOrCreate('callaite_safeTop', topVp);
      }
      if (prevBottom === undefined || Math.abs(prevBottom - bottomVp) > 0.5) {
        AppStorage.setOrCreate('callaite_safeBottom', bottomVp);
      }
      hilog.info(DOMAIN, 'EntryAbility', 'AvoidArea: safeTop=%{public}s vp, safeBottom=%{public}s vp',
        topVp.toFixed(1), bottomVp.toFixed(1));
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to publish avoid area. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 系统栏文字/图标颜色随主题切换，保证在浅色/深色页面背景上均清晰可辨。
   */
  private applySystemBarStyle(win: window.Window): void {
    try {
      const isDark: boolean = ThemeManager.isDarkMode();
      // 深色页面 → 系统栏内容用浅色；浅色页面 → 用深色
      const contentColor: string = isDark ? '#FFFFFF' : '#1F2328';
      win.setWindowSystemBarProperties({
        statusBarContentColor: contentColor,
        navigationBarContentColor: contentColor
      }).catch(() => {
        // 个别设备不支持时忽略
      });
    } catch (e) {
      // 忽略：不影响主流程
    }
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

    // 保存跨进程状态（引导标志/主题/语言/配置/收藏等）
    StatePersistence.save();

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
