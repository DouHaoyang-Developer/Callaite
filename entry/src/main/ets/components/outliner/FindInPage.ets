import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { TablerIcon } from '../common/Icons';

/**
 * FindInPage — 页内搜索浮动组件。
 *
 * 在当前页面所有 Block 中搜索文本，提供上/下导航。
 * 对应 Logseq 的 find-in-page 功能。
 *
 * 用法：
 *   FindInPage({ pageId: 'xxx' })
 *   通过组件引用调用 show() / hide() 控制显隐。
 *
 * 搜索逻辑：
 *   1. 递归遍历当前页所有 Block（getPageBlocks + getChildrenOfBlock）
 *   2. 匹配 content 包含 searchQuery（不区分大小写）
 *   3. 显示 "N/M" 匹配计数
 *   4. 上/下按钮循环导航匹配项
 */
@Component
export struct FindInPage {
  @Prop pageId: string = '';
  @State isVisible: boolean = false;
  @State searchQuery: string = '';
  @State matchCount: number = 0;
  @State currentMatch: number = 0;
  @State matchedUuids: string[] = [];
  @StorageLink('callaite_blocksVersion') @Watch('onRefresh') private blocksVersion: number = 0;

  aboutToAppear(): void {
    // 初始隐藏，等待 show() 调用
  }

  /**
   * blocksVersion 变化时重新执行搜索（如果可见且查询非空）。
   * 由 Block 编辑/移动/删除等操作触发，保持搜索结果新鲜。
   */
  onRefresh(): void {
    if (this.isVisible && this.searchQuery.length > 0) {
      this.performSearch();
    }
  }

  /**
   * 显示搜索框。
   */
  show(): void {
    this.isVisible = true;
  }

  /**
   * 隐藏并清空搜索状态。
   */
  hide(): void {
    this.isVisible = false;
    this.searchQuery = '';
    this.matchCount = 0;
    this.currentMatch = 0;
    this.matchedUuids = [];
  }

  /**
   * 递归收集页面所有 Block UUID（深度优先，保持文档顺序）。
   * isPage 为 true 时 nodeId 是 pageId，否则是 block uuid。
   */
  collectAllBlocks(nodeId: string, isPage: boolean, out: string[]): void {
    const ws = WorkspaceService.getInstance();
    let blocks: BlockData[] = [];
    if (isPage) {
      blocks = ws.getPageBlocks(nodeId);
    } else {
      blocks = ws.getChildrenOfBlock(nodeId);
    }
    for (let i = 0; i < blocks.length; i++) {
      const b: BlockData = blocks[i];
      out.push(b.uuid);
      this.collectAllBlocks(b.uuid, false, out);
    }
  }

  /**
   * 执行搜索，刷新匹配列表。
   * 不区分大小写，匹配 content 包含 searchQuery 的 Block。
   */
  performSearch(): void {
    const query: string = this.searchQuery;
    if (query.length === 0) {
      this.matchCount = 0;
      this.currentMatch = 0;
      this.matchedUuids = [];
      return;
    }

    const allUuids: string[] = [];
    this.collectAllBlocks(this.pageId, true, allUuids);

    const ws = WorkspaceService.getInstance();
    const matched: string[] = [];
    const lowerQuery: string = query.toLowerCase();
    for (let i = 0; i < allUuids.length; i++) {
      const block: BlockData | undefined = ws.getBlock(allUuids[i]);
      if (block && block.content.toLowerCase().indexOf(lowerQuery) >= 0) {
        matched.push(block.uuid);
      }
    }

    this.matchedUuids = matched;
    this.matchCount = matched.length;
    if (matched.length > 0) {
      this.currentMatch = 1;
    } else {
      this.currentMatch = 0;
    }
  }

  /**
   * 跳转到上一个匹配项（循环导航）。
   */
  navigatePrev(): void {
    if (this.matchedUuids.length === 0) {
      return;
    }
    if (this.currentMatch <= 1) {
      this.currentMatch = this.matchedUuids.length;
    } else {
      this.currentMatch = this.currentMatch - 1;
    }
  }

  /**
   * 跳转到下一个匹配项（循环导航）。
   */
  navigateNext(): void {
    if (this.matchedUuids.length === 0) {
      return;
    }
    if (this.currentMatch >= this.matchedUuids.length) {
      this.currentMatch = 1;
    } else {
      this.currentMatch = this.currentMatch + 1;
    }
  }

  build() {
    if (!this.isVisible) {
      Row().width('100%').height(0)
    } else {
      Row({ space: 8 }) {
        TablerIcon('search', 16, $r('app.color.muted_text'))

        TextInput({ placeholder: '页内搜索...', text: this.searchQuery })
          .fontSize(14)
          .layoutWeight(1)
          .height(32)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .onChange((value: string) => {
            this.searchQuery = value;
            this.performSearch();
          })

        // 匹配计数 — 有匹配时使用 search_highlight 高亮色
        Text(this.currentMatch.toString() + '/' + this.matchCount.toString())
          .fontSize(12)
          .fontColor(this.matchCount > 0 ? $r('app.color.search_highlight') : $r('app.color.muted_text'))
          .margin({ left: 4, right: 4 })

        // 上一个匹配
        Row() {
          TablerIcon('chevron-up', 16, $r('app.color.text'))
        }
        .width(28)
        .height(28)
        .borderRadius(4)
        .onClick(() => {
          this.navigatePrev();
        })

        // 下一个匹配
        Row() {
          TablerIcon('chevron-down', 16, $r('app.color.text'))
        }
        .width(28)
        .height(28)
        .borderRadius(4)
        .onClick(() => {
          this.navigateNext();
        })

        // 关闭按钮
        Row() {
          TablerIcon('x', 16, $r('app.color.muted_text'))
        }
        .width(28)
        .height(28)
        .borderRadius(4)
        .onClick(() => {
          this.hide();
        })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12, right: 8 })
      .backgroundColor($r('app.color.surface1'))
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    }
  }
}
