import { TablerIcon } from '../common/Icons';
import { AppState, RightSidebarBlock } from '../../state/AppState';
import { t } from '../../utils/i18n';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { BacklinkInfo } from '../../core/db/DataStore';
import { JournalService } from '../../services/JournalService';

/**
 * RightSidebar — 按 logseq right_sidebar.cljs 多块堆叠结构复刻
 *
 * 结构：
 *   ┌──────────────────────────────────────┐
 *   │ [⇲ collapse all] [⇱ expand] [✕ close all] │  ← 顶部工具栏
 *   ├──────────────────────────────────────┤
 *   │ ▼ Block Title                  [✕]   │  ← 块头部（可折叠）
 *   │   block content                      │
 *   ├──────────────────────────────────────┤
 *   │ ▶ Block Title (collapsed)      [✕]   │
 *   ├──────────────────────────────────────┤
 *   │ ▼ ...                                │
 *   └──────────────────────────────────────┘
 *
 * 块类型（type）：
 *   - 'backlinks'  : 反向链接列表
 *   - 'outline'    : 页面大纲
 *   - 'properties' : 页面属性
 *   - 'page'       : 页面预览
 *   - 'help'       : 帮助信息
 *
 * 数据源：AppState.getRightSidebarBlocks() 持久化在 AppStorage。
 * 自动初始化：首次打开且 blocks 为空时，添加 backlinks/outline/properties 三个默认块。
 */
@Component
export struct RightSidebar {
  @StorageLink('callaite_currentPage') @Watch('onCurrentPageChanged') currentPage: string = 'Journal';
  @StorageLink('callaite_rightSidebarBlocksVersion') private blocksVersion: number = 0;
  @State backlinksCache: BacklinkInfo[] = [];
  @State headingsCache: BlockData[] = [];
  @State propsCache: string[][] = [];

  aboutToAppear(): void {
    this.ensureDefaultBlocks();
    this.refreshCaches();
  }

  /**
   * currentPage 变更时刷新缓存数据（反链/大纲/属性）。
   */
  onCurrentPageChanged(): void {
    this.refreshCaches();
  }

  /**
   * 当 currentPage 或 blocksVersion 变更时刷新缓存与块内容。
   */
  build() {
    Column({ space: 0 }) {
      this.Toolbar()
      Divider().color($r('app.color.border')).width('100%')

      Scroll() {
        Column({ space: 0 }) {
          if (this.getBlocks().length === 0) {
            this.EmptyState()
          } else {
            ForEach(this.getBlocks(), (block: RightSidebarBlock) => {
              this.SidebarBlock(block)
            }, (block: RightSidebarBlock) => block.id)
          }
        }
        .width('100%')
        .padding({ bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface1'))
    .border({ width: { left: 1 }, color: $r('app.color.border') })
  }

  /**
   * 顶部工具栏 — 全部折叠 / 全部展开 / 全部关闭。
   */
  @Builder
  Toolbar() {
    Row({ space: 8 }) {
      Text(t('sidebar_right_title'))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.muted_text'))
        .layoutWeight(1)

      // collapse all
      Row() {
        TablerIcon('chevron-up', 16, $r('app.color.muted_text'))
      }
      .width(28)
      .height(28)
      .borderRadius(4)
      .onClick(() => { this.collapseAll(); })

      // expand all
      Row() {
        TablerIcon('chevron-down', 16, $r('app.color.muted_text'))
      }
      .width(28)
      .height(28)
      .borderRadius(4)
      .onClick(() => { this.expandAll(); })

      // close all
      Row() {
        TablerIcon('x', 16, $r('app.color.muted_text'))
      }
      .width(28)
      .height(28)
      .borderRadius(4)
      .onClick(() => { this.closeAll(); })
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
  }

  /**
   * 单个堆叠块 — 头部 + 可折叠内容。
   */
  @Builder
  SidebarBlock(block: RightSidebarBlock) {
    Column({ space: 0 }) {
      // 块头部：chevron + 标题 + 关闭按钮
      Row({ space: 8 }) {
        TablerIcon(block.collapsed ? 'chevron-right' : 'chevron-down',
          14, $r('app.color.muted_text'))
        Text(block.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          TablerIcon('x', 16, $r('app.color.muted_text'))
        }
        .width(20)
        .height(20)
        .onClick(() => { AppState.removeRightSidebarBlock(block.id); })
      }
      .width('100%')
      .height(34)
      .padding({ left: 16, right: 12 })
      .onClick(() => { AppState.toggleRightSidebarBlockCollapsed(block.id); })

      // 块内容（折叠时隐藏）
      if (!block.collapsed) {
        Column({ space: 4 }) {
          this.BlockContent(block)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 12 })
      }

      Divider().color($r('app.color.border')).width('100%')
    }
    .width('100%')
  }

  /**
   * 根据 block.type 渲染对应内容。
   */
  @Builder
  BlockContent(block: RightSidebarBlock) {
    if (block.type === 'backlinks') {
      this.BacklinksContent(block)
    } else if (block.type === 'outline') {
      this.OutlineContent(block)
    } else if (block.type === 'properties') {
      this.PropertiesContent(block)
    } else if (block.type === 'page') {
      this.PagePreviewContent(block)
    } else if (block.type === 'help') {
      this.HelpContent(block)
    }
  }

  @Builder
  BacklinksContent(block: RightSidebarBlock) {
    if (this.backlinksCache.length === 0) {
      Text(t('no_backlinks'))
        .fontSize(12)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
    } else {
      ForEach(this.backlinksCache, (info: BacklinkInfo) => {
        Row({ space: 8 }) {
          TablerIcon('arrow-right', 12, $r('app.color.muted_text'))
          Column({ space: 2 }) {
            Text(info.sourceContent)
              .fontSize(12)
              .fontColor($r('app.color.text'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(t('from_page') + ': ' + info.sourcePageName)
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ top: 4, bottom: 4 })
      }, (info: BacklinkInfo) => info.sourceBlockId)
    }
  }

  @Builder
  OutlineContent(block: RightSidebarBlock) {
    if (this.headingsCache.length === 0) {
      Text(t('no_outline'))
        .fontSize(12)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
    } else {
      ForEach(this.headingsCache, (b: BlockData) => {
        Row({ space: 8 }) {
          if (b.level > 0) {
            Blank().width(b.level * 12)
          }
          Circle({ width: 4, height: 4 })
            .fill($r('app.color.bullet'))
          Text(b.content)
            .fontSize(12)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
      }, (b: BlockData) => b.uuid)
    }
  }

  @Builder
  PropertiesContent(block: RightSidebarBlock) {
    if (this.propsCache.length === 0) {
      Text(t('no_properties'))
        .fontSize(12)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
    } else {
      ForEach(this.propsCache, (pair: string[]) => {
        Row({ space: 4 }) {
          Text(pair[0] + '::')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.muted_text'))
          Text(pair[1])
            .fontSize(12)
            .fontColor($r('app.color.text'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ top: 2, bottom: 2 })
      }, (pair: string[]) => pair[0])
    }
  }

  @Builder
  PagePreviewContent(block: RightSidebarBlock) {
    Column({ space: 4 }) {
      Text(block.pageName)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
      Text('（页面预览）')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  HelpContent(block: RightSidebarBlock) {
    Column({ space: 4 }) {
      Text(t('sidebar_help'))
        .fontSize(12)
        .fontColor($r('app.color.text'))
      Text('— ' + t('app_name'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    Column({ space: 6 }) {
      Text(t('empty_sidebar'))
        .fontSize(13)
        .fontColor($r('app.color.muted_text'))
      Text(t('empty_sidebar_hint'))
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
        .opacity(0.7)
    }
    .width('100%')
    .padding({ top: 40, left: 24, right: 24 })
    .alignItems(HorizontalAlign.Center)
  }

  // ─── 工具方法 ───

  // 注意：必须是普通方法 —— struct 上的 getter 会被 ArkTS 编译器静默丢弃。
  getCurrentDisplayPage(): string {
    if (this.currentPage === 'Journal') {
      return JournalService.getTodayDateString();
    }
    return this.currentPage;
  }

  getBlocks(): RightSidebarBlock[] {
    return AppState.getRightSidebarBlocks();
  }

  /**
   * 首次打开自动添加默认块（backlinks / outline / properties）。
   */
  ensureDefaultBlocks(): void {
    const existing = AppState.getRightSidebarBlocks();
    if (existing.length > 0) return;
    const pageName = this.getCurrentDisplayPage();
    const blocks: RightSidebarBlock[] = [];
    blocks[0] = {
      id: 'backlinks-' + pageName,
      type: 'backlinks',
      title: t('backlinks'),
      pageName: pageName,
      collapsed: false
    };
    blocks[1] = {
      id: 'outline-' + pageName,
      type: 'outline',
      title: t('outline'),
      pageName: pageName,
      collapsed: false
    };
    blocks[2] = {
      id: 'properties-' + pageName,
      type: 'properties',
      title: t('properties'),
      pageName: pageName,
      collapsed: false
    };
    AppState.setRightSidebarBlocks(blocks);
  }

  refreshCaches(): void {
    const ws = WorkspaceService.getInstance();
    this.backlinksCache = ws.getDataStore().getBacklinks(this.getCurrentDisplayPage());
    this.headingsCache = this.collectHeadings(ws);
    this.propsCache = this.collectProps(ws);
  }

  collectHeadings(ws: WorkspaceService): BlockData[] {
    const page = ws.getPageByName(this.getCurrentDisplayPage());
    if (!page) return [];
    const allBlocks = ws.getPageBlocks(page.uuid);
    const result: BlockData[] = [];
    for (let i = 0; i < allBlocks.length; i++) {
      const b = allBlocks[i];
      if (b.content.startsWith('## ') || b.content.startsWith('# ') ||
          b.content.startsWith('### ')) {
        result.push(b);
      }
    }
    return result;
  }

  collectProps(ws: WorkspaceService): string[][] {
    const page = ws.getPageByName(this.getCurrentDisplayPage());
    if (!page) return [];
    const entries: string[][] = [];
    page.properties.forEach((propKey: string, propValue: string) => {
      const pair: string[] = [];
      pair[0] = propKey;
      pair[1] = propValue;
      entries.push(pair);
    });
    return entries;
  }

  // ─── 工具栏动作 ───

  collapseAll(): void {
    const list = AppState.getRightSidebarBlocks();
    const newList: RightSidebarBlock[] = [];
    for (let i = 0; i < list.length; i++) {
      newList.push({
        id: list[i].id, type: list[i].type, title: list[i].title,
        pageName: list[i].pageName, collapsed: true
      });
    }
    AppState.setRightSidebarBlocks(newList);
  }

  expandAll(): void {
    const list = AppState.getRightSidebarBlocks();
    const newList: RightSidebarBlock[] = [];
    for (let i = 0; i < list.length; i++) {
      newList.push({
        id: list[i].id, type: list[i].type, title: list[i].title,
        pageName: list[i].pageName, collapsed: false
      });
    }
    AppState.setRightSidebarBlocks(newList);
  }

  closeAll(): void {
    AppState.clearRightSidebarBlocks();
    // ✕ 同时关闭整个右侧栏（Logseq 右侧栏 close 行为）
    AppState.setRightSidebarOpen(false);
  }
}
