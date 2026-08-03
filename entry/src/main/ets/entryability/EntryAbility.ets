import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppState } from '../state/AppState';
import { ThemeManager } from '../components/common/ThemeManager';
import { FileService } from '../services/FileService';
import { WorkspaceService } from '../services/WorkspaceService';

const DOMAIN = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onCreate');

    // 设置应用上下文（FileService 需要 context 获取沙箱路径）
    FileService.setContext(this.context);

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'EntryAbility', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'EntryAbility', '%{public}s', 'Ability onWindowStageCreate');

    // ─── 启动链（对应迁移计划 §启动链） ───
    // 1. 初始化文件服务并加载 Graph
    FileService.initGraph();

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
  }
}
