import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { WorkspaceService } from '../services/WorkspaceService';
import { JournalService } from '../services/JournalService';

/**
 * ShareReceiveAbility — 分享接收 Ability。
 *
 * 接收其他应用分享的文本内容，自动创建 Block 到今天的日志页。
 * 对应 Lunius shareability/ShareReceiveAbility.ets。
 */
export default class ShareReceiveAbility extends UIAbility {
  private readonly DOMAIN = 0x0002;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(this.DOMAIN, 'ShareReceive', 'Ability onCreate');
    this.handleShareContent(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(this.DOMAIN, 'ShareReceive', 'Failed to load content');
      }
    });
  }

  /**
   * 处理分享内容。
   */
  private handleShareContent(want: Want): void {
    try {
      // 从 Want 中提取分享的文本
      const sharedText = this.extractSharedText(want);
      if (!sharedText) return;

      // 创建 Block 到今天的日志页
      const ws = WorkspaceService.getInstance();
      const today = JournalService.ensureTodayJournal();
      const page = ws.getPageByName(today);
      if (page) {
        ws.executeOp({
          type: 'insert-block',
          content: '📥 分享: ' + sharedText,
          pageId: page.uuid,
          parentId: page.uuid,
          leftId: '',
          level: 0
        });
        ws.savePage(page.uuid);
      }
    } catch (e) {
      hilog.error(this.DOMAIN, 'ShareReceive', 'Failed to handle share: ' + JSON.stringify(e));
    }
  }

  private extractSharedText(want: Want): string | undefined {
    // 从 Want.parameters 中提取文本
    const params = want.parameters as Record<string, Object>;
    if (!params) return undefined;

    const textValue = params['ohos.extra.param.key.content'] as string;
    if (textValue) return textValue;

    const shareText = params['shareText'] as string;
    if (shareText) return shareText;

    return undefined;
  }

  onDestroy(): void {
    hilog.info(this.DOMAIN, 'ShareReceive', 'Ability onDestroy');
  }
}
