import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { ContentRenderer, ContentSegment, SegmentType } from '../../utils/ContentRenderer';
import { MathRenderer } from '../extensions/MathRenderer';
import { MermaidRenderer } from '../extensions/MermaidRenderer';
import { WebEditor } from './WebEditor';
import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';

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
                  // 内容 segments
                  this.ContentSegments()

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
                Text('···').fontSize(12).fontColor($r('app.color.muted_text'))
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
      // 折叠箭头（有子 Block 时显示）
      if (this.hasChildrenFlag) {
        Row() {
          TablerIcon(
            this.isCollapsed ? 'chevron-right' : 'chevron-down',
            10,
            $r('app.color.muted_text')
          )
        }
        .width(14).height(14)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.toggleCollapse();
        })
      }

      // Bullet 圆点
      Circle({ width: 6, height: 6 })
        .fill(this.bulletColor)
        .margin({ top: 5 })
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
          .fontSize(15)
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
        .fontSize(15)
        .fontColor($r('app.color.link'))
        .height(28)
        .onClick(() => {
          AppState.setCurrentPage(seg.text);
        })
    } else if (seg.type === SegmentType.BLOCK_REF) {
      Text('((' + seg.text.substring(0, 8) + '))')
        .fontSize(15)
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
        .fontSize(15)
        .fontColor($r('app.color.success'))
        .height(28)
        .onClick(() => {
          AppState.setCurrentPage(seg.text);
        })
    } else {
      Text(seg.text)
        .fontSize(15)
        .fontColor(ContentRenderer.getSegmentColor(seg.type))
        .fontWeight(seg.type === SegmentType.BOLD ? FontWeight.Bold : FontWeight.Normal)
        .fontStyle(seg.type === SegmentType.ITALIC ? FontStyle.Italic : FontStyle.Normal)
        .decoration({
          type: seg.type === SegmentType.STRIKETHROUGH ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: $r('app.color.muted_text')
        })
        .backgroundColor(seg.type === SegmentType.HIGHLIGHT ? '#FFF9E6' : Color.Transparent)
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
          TablerIcon('calendar-event', 12, $r('app.color.primary'))
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
          TablerIcon('alarm', 12, $r('app.color.error'))
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
      Button() { Text('→').fontSize(13).fontColor($r('app.color.text')) }
        .width(26).height(26).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().indentBlock();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 反缩进
      Button() { Text('←').fontSize(13).fontColor($r('app.color.text')) }
        .width(26).height(26).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().outdentBlock();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 上移
      Button() { Text('↑').fontSize(13).fontColor($r('app.color.text')) }
        .width(26).height(26).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          EditorService.getInstance().moveBlockUp();
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
      // 下移
      Button() { Text('↓').fontSize(13).fontColor($r('app.color.text')) }
        .width(26).height(26).type(ButtonType.Circle)
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
          Text(this.isCollapsed ? '展开' : '折叠').fontSize(11).fontColor($r('app.color.text'))
        }
        .height(26).type(ButtonType.Capsule)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          this.toggleCollapse();
          this.showActions = false;
        })
      }
      // 删除
      Button() { Text('×').fontSize(15).fontColor($r('app.color.error')) }
        .width(26).height(26).type(ButtonType.Circle)
        .backgroundColor($r('app.color.surface2'))
        .onClick(() => {
          WorkspaceService.getInstance().executeOp({ type: 'delete-block', uuid: this.blockUuid });
          this.refreshBlock();
          this.showActions = false;
          AppState.bumpBlocksVersion();
        })
    }.width('100%').padding({ left: 24, right: 8, bottom: 4 })
  }

  // ─── Block 引用嵌入 ───

  @Builder
  EmbedBlocks() {
    Column({ space: 4 }) {
      ForEach(this.getEmbedUuids(), (uuid: string) => {
        Column() {
          Text(this.getBlockContent(uuid))
            .fontSize(13)
            .fontColor($r('app.color.muted_text'))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({ top: 4, bottom: 4, left: 12, right: 8 })
        }
        .width('100%')
        .backgroundColor($r('app.color.surface2'))
        .borderRadius(4)
        .border({ width: { left: 2 }, color: $r('app.color.primary') })
        .padding({ left: 24 })
      }, (uuid: string) => uuid)
    }.width('100%')
  }

  // ─── 辅助方法 ───

  enterEdit(): void {
    EditorService.getInstance().setFocusedBlock(this.blockUuid);
    this.isEditing = true;
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

  getEmbedUuids(): string[] {
    const u: string[] = [];
    for (let i = 0; i < this.displaySegments.length; i++) {
      if (this.displaySegments[i].type === SegmentType.BLOCK_EMBED) {
        u.push(this.displaySegments[i].text);
      }
    }
    return u;
  }

  getBlockContent(uuid: string): string {
    const ws = WorkspaceService.getInstance();
    const b = ws.getBlock(uuid);
    if (b) return b.content.substring(0, 120);
    return uuid.substring(0, 8) + '...';
  }

  getMarkerColor(m: string): ResourceColor {
    if (m === 'DONE') return '#059669';
    if (m === 'DOING') return $r('app.color.primary');
    if (m === 'TODO') return $r('app.color.error');
    if (m === 'CANCELLED') return $r('app.color.muted_text');
    return $r('app.color.muted_text');
  }

  getMarkerBg(m: string): ResourceColor {
    if (m === 'DONE') return '#05966918';
    if (m === 'DOING') return '#0458A618';
    if (m === 'TODO') return '#DC262618';
    if (m === 'CANCELLED') return '#787B8018';
    return Color.Transparent;
  }
}
