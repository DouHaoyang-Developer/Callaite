import { TablerIcon } from '../common/Icons';
import { WorkspaceService } from '../../services/WorkspaceService';
import { BlockData } from '../../core/models/Block';
import { AppState } from '../../state/AppState';

/**
 * QueryView — 查询结果视图组件。
 *
 * 支持三种展示模式：列表 / 卡片 / 表格。
 *
 * 查询语法（简单查询，支持空格分隔多条件 AND 组合）：
 *  - "TODO" / "DOING" / "DONE" / "LATER" / "NOW" / "CANCELLED" — 按 marker 筛选
 *  - "tag:xxx" — 按 Block tags 包含 xxx 筛选
 *  - "property:key:value" — 按属性 key 的值等于 value 筛选
 *  - "property:key" — 按属性 key 存在性筛选
 *  - "all" 或空字符串 — 返回全部 Block
 *
 * 数据来源：WorkspaceService.getAllPages() 遍历所有页面的顶层 Block。
 */

// 查询条件类型
interface QueryCondition {
  kind: string; // 'marker' | 'tag' | 'property-eq' | 'property-has'
  value: string; // 主值
  extra: string; // 辅助值（property-eq 时为属性值）
}

// 视图模式选项
interface ViewModeOption {
  key: string;
  label: string;
  icon: string;
}

const VIEW_MODES: ViewModeOption[] = [
  { key: 'list', label: '列表', icon: 'list' },
  { key: 'card', label: '卡片', icon: 'layout-grid' },
  { key: 'table', label: '表格', icon: 'table' }
];

@Component
export struct QueryView {
  @Prop @Watch('onQueryChange') query: string;
  @State viewMode: string = 'list';
  @State results: BlockData[] = [];
  @State columns: string[] = [];

  aboutToAppear(): void {
    this.executeQuery();
  }

  /**
   * query 属性变化时重新执行查询。
   */
  onQueryChange(): void {
    this.executeQuery();
  }

  /**
   * 执行查询：解析查询语句，遍历所有页面 Block，筛选匹配项。
   */
  private executeQuery(): void {
    const conditions = this.parseQuery(this.query);
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    const matched: BlockData[] = [];

    for (let i = 0; i < pages.length; i++) {
      const blocks = ws.getPageBlocks(pages[i].uuid);
      for (let j = 0; j < blocks.length; j++) {
        if (this.matchBlock(blocks[j], conditions)) {
          matched.push(blocks[j]);
        }
      }
    }

    this.results = matched;
    this.columns = this.collectColumns(matched);
  }

  /**
   * 解析查询字符串为条件列表。按空格分隔多个条件（AND 逻辑）。
   */
  private parseQuery(raw: string): QueryCondition[] {
    const result: QueryCondition[] = [];
    if (!raw) {
      return result;
    }
    const parts = raw.split(' ');
    for (let i = 0; i < parts.length; i++) {
      const token = parts[i].trim();
      if (token.length === 0) {
        continue;
      }
      const cond = this.parseToken(token);
      if (cond) {
        result.push(cond);
      }
    }
    return result;
  }

  /**
   * 解析单个查询 token 为条件。
   */
  private parseToken(token: string): QueryCondition | undefined {
    // property:key:value 或 property:key
    if (token.startsWith('property:')) {
      const rest = token.substring('property:'.length);
      const colonIdx = rest.indexOf(':');
      if (colonIdx > 0 && colonIdx < rest.length - 1) {
        const key = rest.substring(0, colonIdx).trim();
        const value = rest.substring(colonIdx + 1).trim();
        const cond: QueryCondition = { kind: 'property-eq', value: key, extra: value };
        return cond;
      }
      if (rest.length > 0) {
        const cond: QueryCondition = { kind: 'property-has', value: rest.trim(), extra: '' };
        return cond;
      }
      return undefined;
    }

    // tag:xxx
    if (token.startsWith('tag:')) {
      const tag = token.substring('tag:'.length).trim();
      if (tag.length > 0) {
        const cond: QueryCondition = { kind: 'tag', value: tag, extra: '' };
        return cond;
      }
      return undefined;
    }

    // all
    if (token === 'all') {
      const cond: QueryCondition = { kind: 'all', value: '', extra: '' };
      return cond;
    }

    // 纯 marker（TODO/DOING/DONE/LATER/NOW/CANCELLED，大小写不敏感）
    const upper = token.toUpperCase();
    if (upper === 'TODO' || upper === 'DOING' || upper === 'DONE' ||
      upper === 'LATER' || upper === 'NOW' || upper === 'CANCELLED') {
      const cond: QueryCondition = { kind: 'marker', value: upper, extra: '' };
      return cond;
    }

    return undefined;
  }

  /**
   * 判断 Block 是否匹配所有条件（AND 逻辑）。
   */
  private matchBlock(block: BlockData, conditions: QueryCondition[]): boolean {
    // 无条件 = 不匹配（避免全量返回过载）
    if (conditions.length === 0) {
      return false;
    }
    for (let i = 0; i < conditions.length; i++) {
      const cond = conditions[i];
      if (cond.kind === 'all') {
        continue;
      }
      if (cond.kind === 'marker') {
        if (block.marker !== cond.value) {
          return false;
        }
        continue;
      }
      if (cond.kind === 'tag') {
        if (!this.hasTag(block, cond.value)) {
          return false;
        }
        continue;
      }
      if (cond.kind === 'property-eq') {
        if (!block.properties.has(cond.value)) {
          return false;
        }
        if (block.properties.get(cond.value) !== cond.extra) {
          return false;
        }
        continue;
      }
      if (cond.kind === 'property-has') {
        if (!block.properties.has(cond.value)) {
          return false;
        }
        continue;
      }
    }
    return true;
  }

  /**
   * 判断 Block 是否包含指定 tag。
   */
  private hasTag(block: BlockData, tag: string): boolean {
    for (let i = 0; i < block.tags.length; i++) {
      if (block.tags[i] === tag) {
        return true;
      }
    }
    return false;
  }

  /**
   * 收集所有结果 Block 的属性键并集（用于表格视图列）。
   */
  private collectColumns(blocks: BlockData[]): string[] {
    const set = new Map<string, boolean>();
    for (let i = 0; i < blocks.length; i++) {
      const keys = blocks[i].properties.keys();
      for (let j = 0; j < keys.length; j++) {
        set.set(keys[j], true);
      }
    }
    const cols: string[] = [];
    set.forEach((_v: boolean, k: string) => {
      cols.push(k);
    });
    return cols;
  }

  /**
   * 通过 pageId 查找页面名（找不到时回退为 pageId）。
   */
  private findPageName(pageId: string): string {
    const pages = WorkspaceService.getInstance().getAllPages();
    for (let i = 0; i < pages.length; i++) {
      if (pages[i].uuid === pageId) {
        return pages[i].originalName;
      }
    }
    return pageId;
  }

  /**
   * 获取 Block 摘要（截断过长内容）。
   */
  private summary(content: string, max: number): string {
    if (content.length <= max) {
      return content;
    }
    return content.substring(0, max) + '…';
  }

  /**
   * 获取 Block 的 marker 颜色。
   */
  private markerColor(marker: string): ResourceColor {
    if (marker === 'DONE') {
      return $r('app.color.success');
    }
    if (marker === 'TODO' || marker === 'DOING' || marker === 'NOW') {
      return $r('app.color.primary');
    }
    if (marker === 'CANCELLED') {
      return $r('app.color.muted_text');
    }
    return $r('app.color.warning');
  }

  /**
   * 点击结果跳转到对应页面。
   */
  private navigateToBlock(block: BlockData): void {
    const pageName = this.findPageName(block.pageId);
    AppState.setCurrentPage(pageName);
  }

  build() {
    Column({ space: 12 }) {
      // 视图切换按钮组
      Row({ space: 4 }) {
        ForEach(VIEW_MODES, (mode: ViewModeOption) => {
          Row({ space: 4 }) {
            TablerIcon(mode.icon, 14, this.viewMode === mode.key
              ? $r('app.color.primary') : $r('app.color.muted_text'))
            Text(mode.label)
              .fontSize(12)
              .fontColor(this.viewMode === mode.key
                ? $r('app.color.primary') : $r('app.color.muted_text'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.viewMode === mode.key
            ? $r('app.color.surface2') : Color.Transparent)
          .onClick(() => {
            this.viewMode = mode.key;
          })
        }, (mode: ViewModeOption) => mode.key)
      }
      .width('100%')

      // 结果计数
      Row({ space: 6 }) {
        TablerIcon('search', 14, $r('app.color.muted_text'))
        Text('查询: ' + this.query + ' · 共 ' + this.results.length + ' 条结果')
          .fontSize(12)
          .fontColor($r('app.color.muted_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      // 结果区域
      if (this.results.length === 0) {
        this.EmptyState()
      } else {
        if (this.viewMode === 'list') {
          this.ListView()
        } else if (this.viewMode === 'card') {
          this.CardView()
        } else {
          this.TableView()
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  EmptyState() {
    Column({ space: 8 }) {
      TablerIcon('mood-empty', 32, $r('app.color.muted_text'))
      Text('无匹配结果')
        .fontSize(13)
        .fontColor($r('app.color.muted_text'))
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ListView() {
    Scroll() {
      Column({ space: 6 }) {
        ForEach(this.results, (block: BlockData) => {
          Row({ space: 8 }) {
            if (block.marker.length > 0) {
              Text(block.marker)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.markerColor(block.marker))
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(3)
                .backgroundColor($r('app.color.surface2'))
            }
            Column({ space: 2 }) {
              Text(this.summary(block.content, 60))
                .fontSize(13)
                .fontColor($r('app.color.text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.findPageName(block.pageId))
                .fontSize(11)
                .fontColor($r('app.color.muted_text'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            TablerIcon('chevron-right', 14, $r('app.color.muted_text'))
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor($r('app.color.surface1'))
          .onClick(() => {
            this.navigateToBlock(block);
          })
        }, (block: BlockData) => block.uuid)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  CardView() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.results, (block: BlockData) => {
          Column({ space: 6 }) {
            Row({ space: 4 }) {
              if (block.marker.length > 0) {
                Text(block.marker)
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.markerColor(block.marker))
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .borderRadius(3)
                  .backgroundColor($r('app.color.surface2'))
              }
              Blank()
            }
            .width('100%')

            Text(this.summary(block.content, 80))
              .fontSize(13)
              .fontColor($r('app.color.text'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            // 标签行
            if (block.tags.length > 0) {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(block.tags, (tag: string) => {
                  Text('#' + tag)
                    .fontSize(10)
                    .fontColor($r('app.color.link'))
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    .margin({ right: 4, bottom: 4 })
                    .borderRadius(3)
                    .backgroundColor($r('app.color.surface2'))
                }, (tag: string) => tag)
              }
              .width('100%')
            }

            Text(this.findPageName(block.pageId))
              .fontSize(10)
              .fontColor($r('app.color.muted_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .width('46%')
          .padding(10)
          .margin({ right: 8, bottom: 8 })
          .borderRadius(8)
          .backgroundColor($r('app.color.surface1'))
          .onClick(() => {
            this.navigateToBlock(block);
          })
        }, (block: BlockData) => block.uuid)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  TableView() {
    Scroll() {
      Column({ space: 0 }) {
        // 表头
        Row() {
          Text('内容')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.muted_text'))
            .width('40%')
            .padding({ left: 8, right: 4, top: 6, bottom: 6 })
          ForEach(this.columns, (col: string) => {
            Text(col)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted_text'))
              .layoutWeight(1)
              .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          }, (col: string) => col)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface2'))
        .borderRadius({ topLeft: 6, topRight: 6 })

        // 表行
        ForEach(this.results, (block: BlockData) => {
          Row() {
            Text(this.summary(block.content, 40))
              .fontSize(11)
              .fontColor($r('app.color.text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('40%')
              .padding({ left: 8, right: 4, top: 6, bottom: 6 })
            ForEach(this.columns, (col: string) => {
              Text(block.properties.has(col) ? block.properties.get(col) : '-')
                .fontSize(11)
                .fontColor($r('app.color.text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
                .padding({ left: 4, right: 4, top: 6, bottom: 6 })
            }, (col: string) => col + '-' + block.uuid)
          }
          .width('100%')
          .border({ width: { bottom: 0.5 }, color: $r('app.color.border') })
          .onClick(() => {
            this.navigateToBlock(block);
          })
        }, (block: BlockData) => block.uuid)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
  }
}
