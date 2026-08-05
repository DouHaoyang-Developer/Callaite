import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, promptAction } from '@kit.ArkUI';
import { WorkspaceService } from '../services/WorkspaceService';
import { JournalService } from '../services/JournalService';
import { AppState } from '../state/AppState';
import { FileService } from '../services/FileService';

const DOMAIN = 0x0002;
const LOG_TAG = 'ShareReceive';

/**
 * ShareReceiveAbility — 分享接收 Ability。
 *
 * 接收其他应用分享的文本/URL，自动创建 Block 到今天的日志页。
 * - 普通文本：直接作为 Block content
 * - URL（http/https）：自动转为 [url] 格式作为 Block content
 *
 * 对应 Callaite shareability/ShareReceiveAbility.ets。
 */
export default class ShareReceiveAbility extends UIAbility {
  private pendingSharedText: string = '';

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, LOG_TAG, 'Ability onCreate');

    // 初始化文件服务上下文与 Graph（冷启动时确保 WorkspaceService 可用）
    FileService.setContext(this.context);
    FileService.initGraph();

    // 提取分享内容并暂存（在窗口创建后处理以支持 toast 提示）
    this.pendingSharedText = this.extractSharedText(want);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 初始化全局状态（确保 AppStorage 键存在，与 EntryAbility 一致）
    AppState.initialize();

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, LOG_TAG, 'Failed to load content: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, LOG_TAG, 'Content loaded');
      this.processPendingShare();
    });
  }

  /**
   * 处理暂存的分享内容：根据类型调用对应处理器并显示 toast。
   */
  private processPendingShare(): void {
    if (this.pendingSharedText.length === 0) {
      return;
    }
    const text = this.pendingSharedText;
    this.pendingSharedText = '';

    let success = false;
    try {
      if (this.isUrl(text)) {
        this.handleSharedUrl(text);
      } else {
        this.handleSharedText(text);
      }
      success = true;
    } catch (e) {
      hilog.error(DOMAIN, LOG_TAG, 'Failed to handle share: %{public}s', JSON.stringify(e));
    }

    // 显示 toast 提示（成功/失败）
    const message = success ? '已添加到今日日志' : '分享接收失败';
    this.showToast(message);
  }

  /**
   * 处理分享的文本内容：在今日日志页创建 Block。
   * @param text 分享的文本
   */
  private handleSharedText(text: string): void {
    const ws = WorkspaceService.getInstance();
    const today = JournalService.ensureTodayJournal();
    const page = ws.getPageByName(today);
    if (!page) {
      hilog.warn(DOMAIN, LOG_TAG, 'Today journal page not found: %{public}s', today);
      return;
    }
    ws.executeOp({
      type: 'insert-block',
      content: text,
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: '',
      level: 0
    });
    ws.savePage(page.uuid);
    // 跳转到今日日志页
    AppState.setCurrentPage(today);
    hilog.info(DOMAIN, LOG_TAG, 'Shared text added to journal');
  }

  /**
   * 处理分享的 URL：转为 [url] 格式在今日日志页创建 Block。
   * @param url 分享的 URL
   */
  private handleSharedUrl(url: string): void {
    const ws = WorkspaceService.getInstance();
    const today = JournalService.ensureTodayJournal();
    const page = ws.getPageByName(today);
    if (!page) {
      hilog.warn(DOMAIN, LOG_TAG, 'Today journal page not found: %{public}s', today);
      return;
    }
    ws.executeOp({
      type: 'insert-block',
      content: '[' + url + ']',
      pageId: page.uuid,
      parentId: page.uuid,
      leftId: '',
      level: 0
    });
    ws.savePage(page.uuid);
    AppState.setCurrentPage(today);
    hilog.info(DOMAIN, LOG_TAG, 'Shared URL added to journal');
  }

  /**
   * 从 Want 中提取分享的文本内容。
   * 兼容多种分享键名（系统标准键 + 通用键）。
   */
  private extractSharedText(want: Want): string {
    if (want.parameters === undefined || want.parameters === null) {
      return '';
    }

    // 尝试 ohos.extra.param.key.content（HarmonyOS 系统分享标准键名）
    const content = want.parameters['ohos.extra.param.key.content'];
    if (content !== undefined && content !== null && typeof content === 'string' && content.length > 0) {
      return content;
    }

    // 尝试 shareText
    const shareText = want.parameters['shareText'];
    if (shareText !== undefined && shareText !== null && typeof shareText === 'string' && shareText.length > 0) {
      return shareText;
    }

    // 尝试 sharedText
    const sharedText = want.parameters['sharedText'];
    if (sharedText !== undefined && sharedText !== null && typeof sharedText === 'string' && sharedText.length > 0) {
      return sharedText;
    }

    // 尝试 content（通用键名）
    const plainText = want.parameters['content'];
    if (plainText !== undefined && plainText !== null && typeof plainText === 'string' && plainText.length > 0) {
      return plainText;
    }

    return '';
  }

  /**
   * 判断字符串是否为 URL（http/https 协议）。
   */
  private isUrl(text: string): boolean {
    if (text.length < 8) {
      return false;
    }
    const lower = text.toLowerCase();
    if (lower.startsWith('https://')) {
      return true;
    }
    if (lower.startsWith('http://')) {
      return true;
    }
    return false;
  }

  /**
   * 显示 toast 提示（showToast 已弃用，改用 openToast）。
   */
  private showToast(message: string): void {
    promptAction.openToast({
      message: message
    }).catch(() => {
      hilog.warn(DOMAIN, LOG_TAG, 'showToast failed');
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, LOG_TAG, 'Ability onDestroy');
  }
}
