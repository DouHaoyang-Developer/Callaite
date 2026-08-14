import { appRecovery, errorManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WorkspaceService } from './WorkspaceService';

const DOMAIN = 0x0001;
const TAG = 'ErrorRecovery';

/**
 * 全局未捕获异常观察者。
 * 捕获 JS 运行时未处理异常，记录日志并尽力保存未落盘数据。
 */
class GlobalErrorObserver {
  onUnhandledException(errMsg: string): void {
    hilog.error(DOMAIN, TAG, 'Uncaught exception: %{public}s', errMsg);
    try {
      WorkspaceService.getInstance().saveAll();
    } catch (_e) {
      // 保存失败不阻塞异常处理
    }
  }
}

/**
 * ErrorRecoveryService — 崩溃恢复与全局异常捕获。
 *
 *  - appRecovery.enableAppRecovery：JS 崩溃 / 主线程卡死 / Native 崩溃后自动重启并恢复状态
 *  - errorManager.on('error')：全局捕获未处理异常并落日志、保存数据
 */
export class ErrorRecoveryService {
  private static observerId: number = -1;

  static init(): void {
    try {
      appRecovery.enableAppRecovery(
        appRecovery.RestartFlag.RESTART_WHEN_JS_CRASH |
          appRecovery.RestartFlag.RESTART_WHEN_APP_FREEZE |
          appRecovery.RestartFlag.RESTART_WHEN_CPP_CRASH,
        appRecovery.SaveOccasionFlag.SAVE_WHEN_ERROR,
        appRecovery.SaveModeFlag.SAVE_WITH_FILE
      );
      ErrorRecoveryService.observerId = errorManager.on('error', new GlobalErrorObserver());
      hilog.info(DOMAIN, TAG, 'App recovery enabled');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to enable app recovery: %{public}s', JSON.stringify(e));
    }
  }
}
