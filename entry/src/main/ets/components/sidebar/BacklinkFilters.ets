import { TablerIcon } from '../common/Icons';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BacklinkInfo } from '../../core/db/DataStore';

/**
 * BacklinkDisplay — 反链展示信息（含从 Block 中提取的 tags 和时间戳）。
 *
 * BacklinkInfo 仅包含 sourceBlockId/sourceContent/sourcePageName/isBlockRef，
 * 筛选和排序所需的 tags/createdAt/updatedAt 通过 sourceBlockId 查询 Block 获取。
 */
interface BacklinkDisplay {
  sourceBlockId: string;
  sourceContent: string;
  sourcePageName: string;
  isBlockRef: boolean;
  tags: string[];
  createdAt: number;
  updatedAt: number;
}

/**
 * BacklinkFilters — 反链筛选 UI 组件。
 *
 * 对应 Logseq sidebar/backlinks.cljs 中的筛选与排序面板。
 *
 * 功能：
 *  - 文本筛选（按 content 包含）
 *  - 标签筛选（下拉选择标签）
 *  - 排序（更新时间 / 创建时间 / 内容字母序）
 *
 * 用法：
 *   BacklinkFilters({ pageName: 'MyPage' })
 */
@Component
export struct BacklinkFilters {
  /** 目标页面名（反链指向的页面） */
  @Prop pageName: string;
  /** 文本筛选词 */
  @State filterText: string = '';
  /** 标签筛选（空字符串表示不筛选） */
  @State filterTag: string = '';
  /** 排序方式：'updated' / 'created' / 'content' */
  @State sortBy: string = 'updated';
  /** 原始反链列表 */
  @State backlinks: BacklinkInfo[] = [];
  /** 所有可用标签（用于下拉） */
  @State allTags: string[] = [];

  aboutToAppear(): void {
    this.loadBacklinks();
    this.allTags = WorkspaceService.getInstance().getAllTags();
  }

  /**
   * 加载反链数据。
   */
  loadBacklinks(): void {
    const ws = WorkspaceService.getInstance();
    this.backlinks = ws.getDataStore().getBacklinks(this.pageName);
  }

  /**
   * 构建标签下拉选项（含"全部标签"选项）。
   */
  getTagOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    const allOption: SelectOption = { value: '全部标签' };
    options.push(allOption);
    for (let i = 0; i < this.allTags.length; i++) {
      const option: SelectOption = { value: this.allTags[i] };
      options.push(option);
    }
    return options;
  }

  /**
   * 获取排序按钮显示文本。
   */
  getSortLabel(): string {
    if (this.sortBy === 'updated') {
      return '按更新时间';
    }
    if (this.sortBy === 'created') {
      return '按创建时间';
    }
    return '按内容排序';
  }

  /**
   * 循环切换排序方式：updated → created → content → updated
   */
  cycleSort(): void {
    if (this.sortBy === 'updated') {
      this.sortBy = 'created';
    } else if (this.sortBy === 'created') {
      this.sortBy = 'content';
    } else {
      this.sortBy = 'updated';
    }
  }

  /**
   * 将 BacklinkInfo 转换为 BacklinkDisplay（补充 tags 和时间戳）。
   */
  private enrichBacklink(info: BacklinkInfo): BacklinkDisplay {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(info.sourceBlockId);
    const tags: string[] = [];
    let createdAt: number = 0;
    let updatedAt: number = 0;
    if (block) {
      for (let i = 0; i < block.tags.length; i++) {
        tags.push(block.tags[i]);
      }
      createdAt = block.createdAt;
      updatedAt = block.updatedAt;
    }
    const display: BacklinkDisplay = {
      sourceBlockId: info.sourceBlockId,
      sourceContent: info.sourceContent,
      sourcePageName: info.sourcePageName,
      isBlockRef: info.isBlockRef,
      tags: tags,
      createdAt: createdAt,
      updatedAt: updatedAt
    };
    return display;
  }

  /**
   * 获取筛选 + 排序后的反链列表。
   */
  getFilteredBacklinks(): BacklinkDisplay[] {
    // 1. 转换为 BacklinkDisplay
    const enriched: BacklinkDisplay[] = [];
    for (let i = 0; i < this.backlinks.length; i++) {
      enriched.push(this.enrichBacklink(this.backlinks[i]));
    }

    // 2. 筛选
    const filtered: BacklinkDisplay[] = [];
    const lowerFilter = this.filterText.toLowerCase();
    for (let i = 0; i < enriched.length; i++) {
      const item = enriched[i];
      // 文本筛选：content 包含筛选词
      if (lowerFilter !== '') {
        if (item.sourceContent.toLowerCase().indexOf(lowerFilter) < 0) {
          continue;
        }
      }
      // 标签筛选：tags 包含选中标签
      if (this.filterTag !== '') {
        let tagFound = false;
        for (let j = 0; j < item.tags.length; j++) {
          if (item.tags[j] === this.filterTag) {
            tagFound = true;
            break;
          }
        }
        if (!tagFound) {
          continue;
        }
      }
      filtered.push(item);
    }

    // 3. 排序
    if (this.sortBy === 'updated') {
      filtered.sort((a: BacklinkDisplay, b: BacklinkDisplay): number => {
        return b.updatedAt - a.updatedAt;
      });
    } else if (this.sortBy === 'created') {
      filtered.sort((a: BacklinkDisplay, b: BacklinkDisplay): number => {
        return b.createdAt - a.createdAt;
      });
    } else {
      // content：按内容字母序
      filtered.sort((a: BacklinkDisplay, b: BacklinkDisplay): number => {
        if (a.sourceContent < b.sourceContent) {
          return -1;
        }
        if (a.sourceContent > b.sourceContent) {
          return 1;
        }
        return 0;
      });
    }

    return filtered;
  }

  build() {
    Column({ space: 12 }) {
      // ─── 筛选工具栏 ───
      Row({ space: 8 }) {
        // 文本筛选输入框
        TextInput({ text: this.filterText, placeholder: '筛选反链...' })
          .fontSize(13)
          .layoutWeight(1)
          .height(32)
          .backgroundColor($r('app.color.surface2'))
          .borderRadius(6)
          .onChange((value: string) => {
            this.filterText = value;
          })

        // 标签下拉
        Select(this.getTagOptions())
          .selected(0)
          .value(this.filterTag === '' ? '全部标签' : this.filterTag)
          .fontSize(13)
          .height(32)
          .width(120)
          .backgroundColor($r('app.color.surface2'))
          .borderRadius(6)
          .onSelect((index: number, text: string) => {
            if (text === '全部标签') {
              this.filterTag = '';
            } else {
              this.filterTag = text;
            }
          })

        // 排序按钮
        Row({ space: 4 }) {
          TablerIcon('arrows-sort', 14, $r('app.color.muted_text'))
          Text(this.getSortLabel())
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
        }
        .height(32)
        .padding({ left: 10, right: 10 })
        .backgroundColor($r('app.color.surface2'))
        .borderRadius(6)
        .onClick(() => {
          this.cycleSort();
        })
      }
      .width('100%')

      // ─── 反链计数 ───
      Row({ space: 6 }) {
        TablerIcon('link', 12, $r('app.color.muted_text'))
        Text('共 ' + this.getFilteredBacklinks().length.toString() + ' 条反链')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
      }
      .width('100%')

      // ─── 反链列表 ───
      this.BacklinkList(this.getFilteredBacklinks())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }

  /**
   * 反链列表渲染。
   */
  @Builder
  BacklinkList(filtered: BacklinkDisplay[]) {
    if (filtered.length === 0) {
      Column({ space: 8 }) {
        TablerIcon('link-off', 28, $r('app.color.muted_text'))
        Text('暂无反链')
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
      }
      .width('100%')
      .padding({ top: 32, bottom: 32 })
      .alignItems(HorizontalAlign.Center)
    } else {
      Column({ space: 0 }) {
        ForEach(filtered, (item: BacklinkDisplay) => {
          this.BacklinkItem(item)
        }, (item: BacklinkDisplay) => item.sourceBlockId)
      }
      .width('100%')
    }
  }

  /**
   * 单条反链渲染。
   */
  @Builder
  BacklinkItem(item: BacklinkDisplay) {
    Column({ space: 4 }) {
      // 来源页面名 + 引用类型
      Row({ space: 6 }) {
        TablerIcon(item.isBlockRef ? 'hash' : 'file', 12, $r('app.color.primary'))
        Text(item.sourcePageName)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')

      // 内容预览
      Text(item.sourceContent)
        .fontSize(12)
        .fontColor($r('app.color.text'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      // 标签
      if (item.tags.length > 0) {
        Row({ space: 4 }) {
          ForEach(item.tags, (tag: string) => {
            Text('#' + tag)
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .padding({ left: 4, right: 4, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.surface2'))
              .borderRadius(3)
          }, (tag: string) => tag)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .margin({ top: 4, bottom: 4 })
    .borderRadius(6)
    .backgroundColor($r('app.color.surface1'))
    .border({ width: 1, color: $r('app.color.border') })
  }
}
