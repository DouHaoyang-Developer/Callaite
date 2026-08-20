import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { ContentRenderer, ContentSegment, SegmentType } from '../../utils/ContentRenderer';
import { MathRenderer } from '../extensions/MathRenderer';
import { MermaidRenderer } from '../extensions/MermaidRenderer';
import { WebEditor } from './WebEditor';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { InlineQueryBlock } from '../query/InlineQueryBlock';

interface EmbedItem {
  kind: string;   // 'block' | 'page'
  value: string;
}

/**
 * BlockView — 单个 Block 的渲染组件。
 *
 * 对应 Logseq components/block.cljs (block 视图层)。
 *
 * 职责：
 *  - 渲染 Block 内容（支持 16 种 segment 类型）
 *  - 处理折叠/展开（点击 bullet 或 chevron）
 *  - 处理点击进入编辑、引用跳转
 *  - 渲染 SCHEDULED/DEADLINE 日期标签
 *  - 渲染 Block 引用嵌入（((uuid))）
 *  - 悬停时显示操作按钮
 */
@Component
export struct BlockView {
  @Prop blockUuid: string = '';
  @Prop depth: number = 0;
  @State isEditing: boolean = false;
  @State showActions: boolean = false;
  @State displaySegments: ContentSegment[] = [];
  @State isHovered: boolean = false;
  @State isCollapsed: boolean = false;
  @State hasChildrenFlag: boolean = false;
  // 修复：bulletColor 声明为 @State，使用主题资源
  @State bulletColor: ResourceColor = $r('app.color.muted_text');
  // 选中状态（多选支持）
  @State isSelected: boolean = false;
  // 内联查询文本（{{query ...}} 或 #+BEGIN_QUERY）
  @State inlineQuery: string = '';
  // Markdown 表格原始行（按行保留，支持单元格编辑）
  @State tableLines: string[] = [];
  @State isTable: boolean = false;
  @State editingCellLine: number = -1;
  @State editingCellCol: number = -1;
  @State editingCellText: string = '';
  // 正文字号（设置页可切换 12-16pt，默认 15）
  @StorageLink('callaite_fontSize') contentFontSize: number = 15;
  private blockData: BlockData | undefined;

  aboutToAppear(): void {
    this.refreshBlock();
  }

  refreshBlock(): void {
    const ws = WorkspaceService.getInstance();
    this.blockData = ws.getBlock(this.blockUuid);
    if (this.blockData) {
      this.displaySegments = ContentRenderer.parse(this.blockData.content);
      this.isCollapsed = this.blockData.collapsed;
      this.hasChildrenFlag = ws.getChildrenOfBlock(this.blockUuid).length > 0;
      this.inlineQuery = BlockView.extractQuery(this.blockData.content);
      this.tableLines = BlockView.extractTableLines(this.blockData.content);
      this.isTable = this.tableLines.length >= 2;
    }
  }

  build() {
    if (!this.blockData) {
      Row().width('100%').height(0)
    } else {
      Column() {
        // 选中态边框包裹
        Column() {
          Row() {
            // 缩进引导线
            if (this.depth > 0) {
              ForEach(this.buildGuideArray(), (idx: number) => {
                Row() {
                  Column().width(1).height('100%').backgroundColor($r('app.color.border')).margin({ left: 8 })
                  Blank().width(15)
                }.width(24).height('100%')
              }, (idx: number) => idx.toString())
            }

            Row({ space: 8 }) {
              // Bullet + 折叠箭头
              this.BulletControl()

              // Marker（TODO/DOING/DONE）
              if (this.blockData.marker !== '') {
                Text(this.blockData.marker)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getMarkerColor(this.blockData.marker))
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(3)
                  .backgroundColor(this.getMarkerBg(this.blockData.marker))
                  .onClick(() => {
                    EditorService.getInstance().setFocusedBlock(this.blockUuid);
                    EditorService.getInstance().cycleMarker();
                    this.refreshBlock();
                  })
              }

              // 优先级标记
              if (this.blockData.priority !== '') {
                Text('[#' + this.blockData.priority + ']')
                  .fontSize(11)
                  .fontColor($r('app.color.warning'))
                  .fontWeight(FontWeight.Bold)
                  .margin({ right: 2 })
              }

              // 内容区域
              if (this.isEditing) {
                WebEditor({
                  blockUuid: this.blockUuid,
                  initialContent: this.blockData.content,
                  pageName: this.resolvePageName(),
                  onSave: () => {
                    this.isEditing = false;
                    this.refreshBlock();
                  },
                  onAction: (_a: string, _d: string) => {
                    this.refreshBlock();
                  }
                }).layoutWeight(1)
              } else {
                Column() {
                  if (this.isTable) {
                    this.TableView()
                  } else if (BlockView.isPureQueryBlock(this.blockData.content)) {
                    InlineQueryBlock({ queryText: this.inlineQuery })
                  } else {
                    // 内容 segments
                    this.ContentSegments()
                    if (this.inlineQuery !== '') {
                      InlineQueryBlock({ queryText: this.inlineQuery })
                    }
                  }

                  // SCHEDULED / DEADLINE 日期标签
                  if (this.blockData !== undefined &&
                      (this.blockData.scheduled !== '' || this.blockData.deadline !== '')) {
                    this.DateLabels(this.blockData)
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }
            }.layoutWeight(1)

            // 悬停操作按钮
            if (this.isHovered || this.showActions) {
              Row() {
                TablerIcon('dots', 16, $r('app.color.muted_text'))
              }
              .width(20).height(20)
              .onClick(() => {
                this.showActions = !this.showActions;
              })
            }
          }.width('100%').padding({ top: 4, bottom: 4 })
          .onHover((isHover: boolean) => {
            this.isHovered = isHover;
            this.bulletColor = isHover ? $r('app.color.primary') : $r('app.color.muted_text');
          })
          .onClick(() => {
            if (!this.isEditing) {
              EditorService.getInstance().setFocusedBlock(this.blockUuid);
            }
          })
          .backgroundColor(this.isHovered ? $r('app.color.surface2') : Color.Transparent)
          .borderRadius(4)

          // 展开的操作栏
          if (this.showActions) {
            this.ActionsBar()
          }

          // Block 引用嵌入渲染
          if (this.hasEmbedSegments()) {
            this.EmbedBlocks()
          }
        }
        .width('100%')
        .border(this.isSelected ? { width: 2, color: $r('app.color.primary') } : { width: 0, color: Color.Transparent })
        .borderRadius(4)
      }.width('100%').padding({ left: 16, right: 16 })
    }
  }

  // ─── Bullet + 折叠控制 ───

  @Builder
  BulletControl() {
    Row({ space: 2 }) {
      // 折叠箭头（有子 Block 时显示，Logseq block-control：半透明 + 展开时旋转 90°）
      if (this.hasChildrenFlag) {
        Row() {
          TablerIcon('chevron-right', 10, $r('app.color.muted_text'))
        }
        .width(14).height(14)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .opacity(0.4)
        .rotate({ angle: this.isCollapsed ? 0 : 90 })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          this.toggleCollapse();
        })
      }

      // Bullet 圆点（Logseq bullet-container：hover 显示圆环 + 圆点放大）
      Row() {
        Circle({ width: this.isHovered ? 7 : 6, height: this.isHovered ? 7 : 6 })
          .fill(this.bulletColor)
      }
      .width(16).height(16)
      .justifyContent(FlexAlign.Center)
      .borderRadius(8)
      .border({ width: 1, color: this.isHovered ? this.bulletColor : Color.Transparent })
      .margin({ top: 3 })
      .animation({ duration: 150, curve: Curve.EaseOut })
      .onClick(() => {
        // 有子 Block 时点击 bullet 切换折叠
        if (this.hasChildrenFlag) {
          this.toggleCollapse();
        } else {
          this.enterEdit();
        }
      })
    }
  }

  toggleCollapse(): void {
    const ws = WorkspaceService.getInstance();
    ws.executeOp({
      type: 'collapse',
      uuid: this.blockUuid,
      collapsed: !this.isCollapsed
    });
    this.refreshBlock();
    // 触发父组件刷新（通过 AppState 全局版本号）
    AppState.bumpBlocksVersion();
  }

  // ─── 内容 Segments 渲染 ───

  @Builder
  ContentSegments() {
    Row({ space: 0 }) {
      if (this.displaySegments.length === 0) {
        Text(' ')
          .fontSize(this.contentFontSize)
          .fontColor($r('app.color.muted_text'))
          .height(28)
          .onClick(() => {
            this.enterEdit();
          })
      } else {
        ForEach(this.displaySegments, (seg: ContentSegment, idx: number) => {
          this.RenderSegment(seg, idx)
        }, (seg: ContentSegment, idx: number) => idx.toString())
      }
    }.width('100%')
  }

  @Builder
  RenderSegment(seg: ContentSegment, idx: number) {
    if (seg.type === SegmentType.IMAGE) {
      Image(seg.text)
        .width(120).height(80)
        .objectFit(ImageFit.Cover)
        .borderRadius(4)
    } else if (seg.type === SegmentType.MATH_BLOCK) {
      MathRenderer({ formula: seg.text, displayMode: true })
    } else if (seg.type === SegmentType.MATH_INLINE) {
      MathRenderer({ formula: seg.text, displayMode: false })
    } else if (seg.type === SegmentType.MERMAID) {
      MermaidRenderer({ diagram: seg.text })
    } else if (seg.type === SegmentType.BLOCKQUOTE) {
      Row() {
        Column().width(3).height('100%').backgroundColor($r('app.color.border')).margin({ right: 8 })
        Text(seg.text).fontSize(14).fontColor($r('app.color.muted_text')).fontStyle(FontStyle.Italic).layoutWeight(1)
      }.width('100%').padding({ left: 4, top: 2, bottom: 2 })
    } else if (seg.type === SegmentType.PAGE_REF || seg.type === SegmentType.PAGE_EMBED) {
      Text('[[' + seg.text + ']]')
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.link'))
        .height(28)
        .onClick(() => {
          AppState.setCurrentPage(seg.text);
        })
    } else if (seg.type === SegmentType.BLOCK_REF) {
      Text('((' + seg.text.substring(0, 8) + '))')
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.primary'))
        .height(28)
        .onClick(() => {
          // 跳转到 Block 所在页面
          const ws = WorkspaceService.getInstance();
          const block = ws.getBlock(seg.text);
          if (block) {
            const pageUuid = ws.getPageUuidForBlock(seg.text);
            if (pageUuid) {
              const page = ws.getDataStore().getPage(pageUuid);
              if (page) {
                AppState.setCurrentPage(page.originalName);
              }
            }
          }
        })
    } else if (seg.type === SegmentType.TAG_REF) {
      Text('#' + seg.text)
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.success'))
        .height(28)
        .onClick(() => {
          AppState.setCurrentPage(seg.text);
        })
    } else if (seg.type === SegmentType.LINK) {
      Text(seg.extra !== undefined && seg.extra !== '' ? seg.extra : seg.text)
        .fontSize(this.contentFontSize)
        .fontColor($r('app.color.link'))
        .decoration({ type: TextDecorationType.Underline, color: $r('app.color.link') })
        .height(28)
        .onClick(() => {
          ContentRenderer.handleClick(SegmentType.LINK, seg.text);
        })
    } else {
      Text(seg.text)
        .fontSize(this.contentFontSize)
        .fontColor(ContentRenderer.getSegmentColor(seg.type))
        .fontWeight(seg.type === SegmentType.BOLD ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(seg.type === SegmentType.ITALIC ? FontStyle.Italic : FontStyle.Normal)
        .decoration({
          type: seg.type === SegmentType.STRIKETHROUGH ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: $r('app.color.muted_text')
        })
        .backgroundColor(seg.type === SegmentType.HIGHLIGHT ? $r('app.color.highlight') : Color.Transparent)
        .fontFamily(seg.type === SegmentType.CODE ? 'monospace' : '')
        .height(28)
        .onClick(() => {
          if (ContentRenderer.isClickable(seg.type)) {
            ContentRenderer.handleClick(seg.type, seg.text);
          } else {
            this.enterEdit();
          }
        })
    }
  }

  // ─── SCHEDULED / DEADLINE 日期标签 ───

  @Builder
  DateLabels(data: BlockData) {
    Row({ space: 8 }) {
      if (data.scheduled !== '') {
        Row({ space: 4 }) {
          TablerIcon('calendar-event', 16, $r('app.color.primary'))
          Text('SCHEDULED: ' + data.scheduled)
            .fontSize(11)
            .fontColor($r('app.color.primary'))
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(3)
        .backgroundColor($r('app.color.surface2'))
      }
      if (data.deadline !== '') {
        Row({ space: 4 }) {
          TablerIcon('alarm', 16, $r('app.color.error'))
          Text('DEADLINE: ' + data.deadline)
            .fontSize(11)
            .fontColor($r('app.color.error'))
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(3)
        .backgroundColor($r('app.color.surface2'))
      }
    }
    .width('100%')
    .padding({ top: 2, left: 2 })
  }

  // ─── 操作栏 ───

  @Builder
  ActionsBar() {
    Row({ space: 4 }) {
      // 缩进
      Button() { TablerIcon('indent-increase', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().indentBlock();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 反缩进
      Button() { TablerIcon('indent-decrease', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().outdentBlock();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 上移
      Button() { TablerIcon('arrow-up', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().moveBlockUp();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 下移
      Button() { TablerIcon('arrow-down', 18, $r('app.color.text')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().moveBlockDown();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 折叠/展开
      if (this.hasChildrenFlag) {
        Button() {
          TablerIcon(this.isCollapsed ? 'chevron-down' : 'chevron-up', 18, $r('app.color.text'))
        }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          this.toggleCollapse();
          this.showActions = false;
        })
      }
      // 删除
      Button() { TablerIcon('trash', 18, $r('app.color.error')) }
        .width(36).height(36).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          WorkspaceService.getInstance().executeOp({ type: 'delete-block', uuid: this.blockUuid });
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
    }.width('100%').padding({ left: 24, right: 8, bottom: 4 })
  }

  // ─── 引用 / 嵌入渲染 ───

  @Builder
  EmbedBlocks() {
    Column({ space: 4 }) {
      ForEach(this.getEmbedItems(), (item: EmbedItem) => {
        this.EmbedItemView(item)
      }, (item: EmbedItem) => item.kind + ':' + item.value)
    }.width('100%')
  }

  @Builder
  EmbedItemView(item: EmbedItem) {
    Column({ space: 2 }) {
      if (item.kind === 'page') {
        Text('![[' + item.value + ']]')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.link'))
          .width('100%')
        ForEach(this.getPageEmbedLines(item.value), (line: string, idx: number) => {
          Text(line)
            .fontSize(12)
            .fontColor($r('app.color.muted_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }, (line: string, idx: number) => idx.toString())
      } else {
        Text(this.getBlockContent(item.value))
          .fontSize(13)
          .fontColor($r('app.color.muted_text'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.surface2'))
    .borderRadius(4)
    .border({ width: { left: 2 }, color: $r('app.color.primary') })
    .padding({ left: 12, right: 8, top: 6, bottom: 6 })
  }

  @Builder
  TableView() {
    Column() {
      ForEach(this.tableLines, (line: string, li: number) => {
        if (!BlockView.isSeparatorRow(BlockView.splitTableRow(line))) {
          Row() {
            ForEach(BlockView.splitTableRow(line), (cell: string, ci: number) => {
              if (this.editingCellLine === li && this.editingCellCol === ci) {
                TextInput({ text: this.editingCellText })
                  .fontSize(12)
                  .fontColor($r('app.color.text'))
                  .layoutWeight(1)
                  .height(32)
                  .padding({ left: 4, right: 4 })
                  .backgroundColor($r('app.color.surface0'))
                  .onChange((v: string) => { this.editingCellText = v; })
                  .onSubmit(() => { this.commitCellEdit(); })
              } else {
                Text(cell)
                  .fontSize(12)
                  .fontColor($r('app.color.text'))
                  .fontWeight(li === 0 ? FontWeight.Medium : FontWeight.Normal)
                  .layoutWeight(1)
                  .padding({ left: 6, right: 6, top: 5, bottom: 5 })
                  .backgroundColor(li === 0 ? $r('app.color.surface2') : Color.Transparent)
                  .border({ width: { right: 1, bottom: 1 }, color: $r('app.color.border') })
                  .onClick(() => { this.startCellEdit(li, ci, cell); })
              }
            }, (cell: string, ci: number) => li.toString() + '-' + ci.toString())
          }
          .width('100%')
        }
      }, (line: string, li: number) => li.toString())
    }
    .width('100%')
    .border({ width: 1, color: $r('app.color.border') })
    .borderRadius(4)
    .padding({ top: 4, bottom: 4 })
  }

  // ─── 辅助方法 ───

  enterEdit(): void {
    EditorService.getInstance().setFocusedBlock(this.blockUuid);
    this.isEditing = true;
  }

  private startCellEdit(line: number, col: number, text: string): void {
    this.editingCellLine = line;
    this.editingCellCol = col;
    this.editingCellText = text;
  }

  private clearCellEdit(): void {
    this.editingCellLine = -1;
    this.editingCellCol = -1;
    this.editingCellText = '';
  }

  private commitCellEdit(): void {
    if (this.editingCellLine < 0 || this.editingCellCol < 0) {
      return;
    }
    const line = this.tableLines[this.editingCellLine];
    const cells = BlockView.splitTableRow(line);
    if (this.editingCellCol < cells.length) {
      cells[this.editingCellCol] = this.editingCellText.trim();
      this.tableLines[this.editingCellLine] = '| ' + cells.join(' | ') + ' |';
      const newContent = this.tableLines.join('\n');
      EditorService.getInstance().updateBlockContent(this.blockUuid, newContent);
    }
    this.clearCellEdit();
    this.refreshBlock();
  }

  resolvePageName(): string {
    const ws = WorkspaceService.getInstance();
    const pid = ws.getPageUuidForBlock(this.blockUuid);
    if (pid) {
      const p = ws.getDataStore().getIndexStore().getPage(pid);
      if (p) return p.originalName;
    }
    return '';
  }

  buildGuideArray(): number[] {
    const a: number[] = [];
    for (let i = 0; i < this.depth; i++) {
      a.push(i);
    }
    return a;
  }

  hasEmbedSegments(): boolean {
    for (let i = 0; i < this.displaySegments.length; i++) {
      const t = this.displaySegments[i].type;
      if (t === SegmentType.BLOCK_EMBED || t === SegmentType.PAGE_EMBED) return true;
    }
    return false;
  }

  getEmbedItems(): EmbedItem[] {
    const items: EmbedItem[] = [];
    for (let i = 0; i < this.displaySegments.length; i++) {
      const seg = this.displaySegments[i];
      if (seg.type === SegmentType.BLOCK_EMBED) {
        items.push({ kind: 'block', value: seg.text });
      } else if (seg.type === SegmentType.PAGE_EMBED) {
        items.push({ kind: 'page', value: seg.text });
      }
    }
    return items;
  }

  getPageEmbedLines(pageName: string): string[] {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) {
      return [];
    }
    const blocks = ws.getPageBlocks(page.uuid);
    const lines: string[] = [];
    for (let i = 0; i < blocks.length && i < 5; i++) {
      lines.push(blocks[i].content.substring(0, 80));
    }
    return lines;
  }

  getBlockContent(uuid: string): string {
    const ws = WorkspaceService.getInstance();
    const b = ws.getBlock(uuid);
    if (b) return b.content.substring(0, 120);
    return uuid.substring(0, 8) + '...';
  }

  static extractQuery(content: string): string {
    const beginIdx = content.indexOf('#+BEGIN_QUERY');
    const endIdx = content.indexOf('#+END_QUERY');
    if (beginIdx >= 0 && endIdx > beginIdx) {
      const inner = content.substring(beginIdx + '#+BEGIN_QUERY'.length, endIdx);
      const open = inner.indexOf('(');
      const close = inner.lastIndexOf(')');
      if (open >= 0 && close > open) {
        return inner.substring(open, close + 1).trim();
      }
      return inner.trim();
    }
    const qIdx = content.indexOf('{{query');
    if (qIdx >= 0) {
      let start = qIdx + '{{query'.length;
      if (start < content.length && content.charAt(start) === ':') {
        start = start + 1;
      }
      let end = content.indexOf('}}', start);
      if (end < 0) {
        end = content.length;
      }
      return content.substring(start, end).trim();
    }
    return '';
  }

  static isPureQueryBlock(content: string): boolean {
    const trimmed = content.trim();
    return trimmed.startsWith('#+BEGIN_QUERY') || trimmed.startsWith('{{query');
  }

  static extractTableLines(content: string): string[] {
    const lines = content.split('\n');
    const result: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t === '') {
        continue;
      }
      if (!t.startsWith('|')) {
        return [];
      }
      result.push(t);
    }
    return result.length >= 2 ? result : [];
  }

  static parseTable(content: string): string[][] {
    const lines = content.split('\n');
    const tableLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i].trim();
      if (t === '') {
        continue;
      }
      if (!t.startsWith('|')) {
        return [];
      }
      tableLines.push(t);
    }
    if (tableLines.length < 2) {
      return [];
    }
    const rows: string[][] = [];
    for (let i = 0; i < tableLines.length; i++) {
      const cells = BlockView.splitTableRow(tableLines[i]);
      if (BlockView.isSeparatorRow(cells)) {
        continue;
      }
      rows.push(cells);
    }
    return rows;
  }

  static splitTableRow(line: string): string[] {
    let inner = line;
    if (inner.startsWith('|')) {
      inner = inner.substring(1);
    }
    if (inner.endsWith('|')) {
      inner = inner.substring(0, inner.length - 1);
    }
    const parts = inner.split('|');
    const cells: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      cells.push(parts[i].trim());
    }
    return cells;
  }

  static isSeparatorRow(cells: string[]): boolean {
    for (let i = 0; i < cells.length; i++) {
      const c = cells[i];
      let ok = true;
      for (let j = 0; j < c.length; j++) {
        const ch = c.charAt(j);
        if (ch !== '-' && ch !== ':' && ch !== ' ') {
          ok = false;
          break;
        }
      }
      if (!ok) {
        return false;
      }
    }
    return cells.length > 0;
  }

  getMarkerColor(m: string): ResourceColor {
    if (m === 'DONE') return $r('app.color.marker_done');
    if (m === 'DOING') return $r('app.color.marker_doing');
    if (m === 'TODO') return $r('app.color.marker_todo');
    if (m === 'LATER') return $r('app.color.marker_later');
    if (m === 'NOW') return $r('app.color.marker_doing');
    if (m === 'CANCELLED') return $r('app.color.marker_cancelled');
    return $r('app.color.muted_text');
  }

  getMarkerBg(m: string): ResourceColor {
    if (m === 'DONE') return $r('app.color.marker_done_bg');
    if (m === 'DOING') return $r('app.color.marker_doing_bg');
    if (m === 'TODO') return $r('app.color.marker_todo_bg');
    if (m === 'LATER') return $r('app.color.marker_later_bg');
    if (m === 'NOW') return $r('app.color.marker_doing_bg');
    if (m === 'CANCELLED') return $r('app.color.marker_cancelled_bg');
    return Color.Transparent;
  }
}
