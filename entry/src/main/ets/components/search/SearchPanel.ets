import { TablerIcon } from '../common/Icons';
import { t } from '../../utils/i18n';
import { AppState } from '../../state/AppState';
import { WorkspaceService } from '../../services/WorkspaceService';
import { PageData } from '../../core/models/Page';
import { BlockData } from '../../core/models/Block';

/**
 * 搜索结果项。
 */
interface SearchResultItem {
  type: string;
  pageName: string;
  blockUuid: string;
  content: string;
  matchedText: string;
}

/**
 * 文本分段（用于搜索高亮）。
 */
interface TextSegment {
  text: string;
  isMatch: boolean;
}

/**
 * SearchPanel — 全局搜索面板。
 *
 * 对应 Logseq 的全局搜索（Cmd+K / Ctrl+K）。
 * 搜索范围：页面名 + Block 内容。结果上限 50 条。
 * 空搜索词时显示最近访问的页面。
 */
@Component
export struct SearchPanel {
  @StorageLink('callaite_searchPanelOpen') @Watch('onPanelVisibilityChanged') isOpen: boolean = false;

  @State searchQuery: string = '';
  @State results: SearchResultItem[] = [];
  @State isSearching: boolean = false;
  @State recentPages: string[] = [];

  private inputController: TextInputController = new TextInputController();

  aboutToAppear(): void {
    this.recentPages = AppState.getRecentPages();
  }

  /**
   * 面板显隐变化时的处理。
   */
  onPanelVisibilityChanged(): void {
    if (this.isOpen) {
      this.recentPages = AppState.getRecentPages();
      // 消费标签点击产生的过滤请求
      const tagFilter = AppStorage.get<string>('callaite_tagFilter');
      if (tagFilter && tagFilter !== '') {
        AppStorage.setOrCreate('callaite_tagFilter', '');
        this.searchQuery = '#' + tagFilter;
        this.executeSearch(this.searchQuery);
      }
      setTimeout(() => {
        if (this.isOpen) {
          this.inputController.requestFocus();
        }
      }, 100);
    } else {
      this.searchQuery = '';
      this.results = [];
    }
  }

  /**
   * 执行搜索：页面名 + Block 内容。
   */
  executeSearch(query: string): void {
    if (query === '') {
      this.results = [];
      return;
    }

    this.isSearching = true;
    const ws = WorkspaceService.getInstance();
    const items: SearchResultItem[] = [];
    const lowerQuery = query.toLowerCase();

    // 标签搜索：`#tag` 前缀时按标签索引查找页面
    if (query.startsWith('#') && query.length > 1) {
      const tag = query.substring(1);
      const pagesByTag = ws.getPagesByTag(tag);
      for (let i = 0; i < pagesByTag.length && items.length < 50; i++) {
        const item: SearchResultItem = {
          type: 'page',
          pageName: pagesByTag[i].originalName,
          blockUuid: '',
          content: pagesByTag[i].originalName,
          matchedText: query
        };
        items.push(item);
      }
      this.results = items;
      this.isSearching = false;
      return;
    }

    // 1. 搜索页面名
    const pages = ws.searchPages(query);
    for (let i = 0; i < pages.length && items.length < 50; i++) {
      const item: SearchResultItem = {
        type: 'page',
        pageName: pages[i].originalName,
        blockUuid: '',
        content: pages[i].originalName,
        matchedText: query
      };
      items.push(item);
    }

    // 2. 搜索 Block 内容
    if (items.length < 50) {
      const allPages = ws.getAllPages();
      for (let pi = 0; pi < allPages.length && items.length < 50; pi++) {
        const page = allPages[pi];
        const blocks = ws.getDataStore().getPageBlocks(page.uuid);
        for (let bi = 0; bi < blocks.length && items.length < 50; bi++) {
          const block = blocks[bi];
          if (block.content.toLowerCase().indexOf(lowerQuery) !== -1) {
            const item: SearchResultItem = {
              type: 'block',
              pageName: page.originalName,
              blockUuid: block.uuid,
              content: block.content,
              matchedText: query
            };
            items.push(item);
          }
        }
      }
    }

    this.results = items;
    this.isSearching = false;
  }

  /**
   * 获取显示结果：空搜索词时返回最近页面。
   */
  getDisplayResults(): SearchResultItem[] {
    if (this.searchQuery !== '') {
      return this.results;
    }

    const items: SearchResultItem[] = [];
    for (let i = 0; i < this.recentPages.length; i++) {
      const item: SearchResultItem = {
        type: 'page',
        pageName: this.recentPages[i],
        blockUuid: '',
        content: this.recentPages[i],
        matchedText: ''
      };
      items.push(item);
    }
    return items;
  }

  /**
   * 点击搜索结果跳转。
   */
  navigateToResult(result: SearchResultItem): void {
    AppState.setCurrentPage(result.pageName);
    this.isOpen = false;
  }

  closePanel(): void {
    this.isOpen = false;
  }

  /**
   * 将文本按搜索词拆分为分段（匹配段标记 isMatch=true）。
   */
  splitHighlight(text: string, query: string): TextSegment[] {
    if (query === '' || text === '') {
      const seg: TextSegment = { text: text, isMatch: false };
      return [seg];
    }

    const lowerText = text.toLowerCase();
    const lowerQuery = query.toLowerCase();
    const segments: TextSegment[] = [];
    let idx = 0;

    while (idx < text.length) {
      const found = lowerText.indexOf(lowerQuery, idx);
      if (found === -1) {
        const seg: TextSegment = { text: text.substring(idx), isMatch: false };
        segments.push(seg);
        break;
      }
      if (found > idx) {
        const seg: TextSegment = { text: text.substring(idx, found), isMatch: false };
        segments.push(seg);
      }
      const matchSeg: TextSegment = {
        text: text.substring(found, found + query.length),
        isMatch: true
      };
      segments.push(matchSeg);
      idx = found + query.length;
    }

    return segments;
  }

  build() {
    if (this.isOpen) {
      Stack() {
        // ─── 半透明遮罩 ───
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.closePanel(); })

        // ─── 搜索面板 ───
        Column({ space: 0 }) {
          // 搜索框
          Row({ space: 10 }) {
            TablerIcon('search', 20, $r('app.color.muted_text'))

            TextInput({ text: this.searchQuery, controller: this.inputController, placeholder: '搜索页面或内容...' })
              .fontSize(14)
              .layoutWeight(1)
              .height(40)
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => {
                this.searchQuery = value;
                this.executeSearch(value);
              })
              .onSubmit(() => {
                const r = this.getDisplayResults();
                if (r.length > 0) {
                  this.navigateToResult(r[0]);
                }
              })

            Row() {
              TablerIcon('x', 16, $r('app.color.muted_text'))
            }
            .width(28)
            .height(28)
            .justifyContent(FlexAlign.Center)
            .borderRadius(4)
            .onClick(() => { this.closePanel(); })
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 8, bottom: 8 })
          .border({ width: { bottom: 1 }, color: $r('app.color.border') })

          // 结果区域
          if (this.getDisplayResults().length === 0) {
            Column({ space: 8 }) {
              TablerIcon('search', 32, $r('app.color.muted_text'))
              Text(this.searchQuery === '' ? '开始搜索' : '未找到结果')
                .fontSize(14)
                .fontColor($r('app.color.muted_text'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column({ space: 0 }) {
                // 空搜索词时显示"最近访问"标题
                if (this.searchQuery === '') {
                  Row({ space: 6 }) {
                    TablerIcon('refresh', 14, $r('app.color.muted_text'))
                    Text(t('recent').toUpperCase())
                      .fontSize(11)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.muted_text'))
                  }
                  .width('100%')
                  .padding({ left: 16, top: 10, bottom: 6 })
                }

                ForEach(this.getDisplayResults(), (result: SearchResultItem, index: number) => {
                  this.ResultItem(result)
                }, (result: SearchResultItem, index: number) => index.toString())
              }
              .width('100%')
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        }
        .width('80%')
        .maxHeight('70%')
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(10)
        .border({ width: 1, color: $r('app.color.border') })
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)', offsetX: 0, offsetY: 8 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Column().width(0).height(0)
    }
  }

  @Builder
  ResultItem(result: SearchResultItem) {
    Row({ space: 10 }) {
      // 图标
      if (result.type === 'page') {
        TablerIcon('file', 16, $r('app.color.primary'))
      } else {
        TablerIcon('indent-increase', 16, $r('app.color.muted_text'))
      }

      // 内容
      Column({ space: 3 }) {
        if (result.type === 'page') {
          // 页面结果：高亮页面名
          Text() {
            ForEach(this.splitHighlight(result.content, this.searchQuery), (seg: TextSegment, idx: number) => {
              Span(seg.text)
                .fontSize(14)
                .fontColor(seg.isMatch ? $r('app.color.primary') : $r('app.color.text'))
                .backgroundColor(seg.isMatch ? $r('app.color.search_highlight') : 'rgba(0,0,0,0)')
            }, (seg: TextSegment, idx: number) => idx.toString())
          }
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          // Block 结果：内容预览 + 所属页面
          Text() {
            ForEach(this.splitHighlight(result.content, this.searchQuery), (seg: TextSegment, idx: number) => {
              Span(seg.text)
                .fontSize(13)
                .fontColor(seg.isMatch ? $r('app.color.primary') : $r('app.color.text'))
                .backgroundColor(seg.isMatch ? $r('app.color.search_highlight') : 'rgba(0,0,0,0)')
            }, (seg: TextSegment, idx: number) => idx.toString())
          }
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 4 }) {
            TablerIcon('file', 14, $r('app.color.muted_text'))
            Text(result.pageName)
              .fontSize(11)
              .fontColor($r('app.color.muted_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .onClick(() => { this.navigateToResult(result); })
  }
}
