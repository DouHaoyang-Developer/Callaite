import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { pageTitle } from '../../utils/PageTitle';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { JournalService } from '../../services/JournalService';
import { BlockData } from '../../core/models/Block';

/**
 * StatusBar — Obsidian 桌面端底部状态栏。
 *
 * 结构：[仓库 / 页面面包屑]                    [N 块 · M 字 · K 页面] [主题]
 *  - 统计随 currentPage 与 blocksVersion 变化自动刷新
 *  - 仅桌面形态显示（手机端由 MobileBottomBar 承担导航）
 */
@Component
export struct StatusBar {
  @StorageLink('callaite_currentPage') @Watch('onPageChanged') currentPage: string = 'Journal';
  @StorageLink('callaite_blocksVersion') @Watch('onStatsDirty') blocksVersion: number = 0;
  @State blockCount: number = 0;
  @State wordCount: number = 0;
  @State pageCount: number = 0;

  aboutToAppear(): void {
    this.refreshStats();
  }

  onPageChanged(): void {
    this.refreshStats();
  }

  onStatsDirty(): void {
    this.refreshStats();
  }

  /**
   * 页面数据查询键 —— 必须是数据层真实页面名（Journal → 今日日期）。
   * 注意：不能与显示标题混用，否则内部路由页会查不到数据。
   */
  private resolvePageKey(): string {
    if (this.currentPage === 'Journal') {
      return JournalService.getTodayDateString();
    }
    return this.currentPage;
  }

  /**
   * 页面显示名 —— 走统一路由→标题映射，避免暴露 Settings/AllPages 等内部标识。
   */
  private resolveDisplayName(): string {
    return pageTitle(this.currentPage);
  }

  private refreshStats(): void {
    const ws = WorkspaceService.getInstance();
    this.pageCount = ws.getAllPages().length;
    const page = ws.getPageByName(this.resolvePageKey());
    this.blockCount = 0;
    this.wordCount = 0;
    if (page !== undefined) {
      const blocks: BlockData[] = ws.getDataStore().getPageBlocks(page.uuid);
      this.blockCount = blocks.length;
      let words = 0;
      for (let i = 0; i < blocks.length; i++) {
        words += StatusBar.countWords(blocks[i].content);
      }
      this.wordCount = words;
    }
  }

  /**
   * 字数统计：CJK 字符按字计，拉丁字母/数字按词计。
   */
  private static countWords(content: string): number {
    let cjk = 0;
    let words = 0;
    let inWord = false;
    for (let i = 0; i < content.length; i++) {
      const code = content.charCodeAt(i);
      if (code >= 0x4E00 && code <= 0x9FFF) {
        cjk++;
        inWord = false;
      } else if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
        if (!inWord) {
          words++;
          inWord = true;
        }
      } else {
        inWord = false;
      }
    }
    return cjk + words;
  }

  private isInternalRoute(): boolean {
    return AppState.isInternalRoute(this.currentPage);
  }

  build() {
    Row({ space: 12 }) {
      // ─── 左：仓库 / 面包屑 ───
      Row({ space: 5 }) {
        TablerIcon('bolt', 12, $r('app.color.primary'))
        Text('Callaite')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        if (!this.isInternalRoute()) {
          TablerIcon('chevron-right', 10, $r('app.color.muted_text'))
          Text(this.resolveDisplayName())
            .fontSize(11)
            .fontColor($r('app.color.muted_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 280 })
        }
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      // ─── 右：统计 + 状态 ───
      Text(this.blockCount.toString() + ' ' + t('status_blocks'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text('·')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text(this.wordCount.toString() + ' ' + t('status_words'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text('·')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text(this.pageCount.toString() + ' ' + t('status_pages'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))

      Row({ space: 4 }) {
        Circle({ width: 6, height: 6 }).fill($r('app.color.success'))
        Text(t('sync'))
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
      }
      .margin({ left: 8 })
    }
    .width('100%')
    .height(26)
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { top: 0.5 }, color: $r('app.color.border') })
    .alignItems(VerticalAlign.Center)
  }
}
