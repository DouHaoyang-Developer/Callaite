import { BlockData } from '../../core/models/Block';
import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { ContentRenderer, ContentSegment, SegmentType } from '../../utils/ContentRenderer';

/**
 * BlockView — Logseq 风格 Block 行。
 *
 * 视觉对齐 Logseq 原版:
 *  - 圆点: 6px filled circle, 灰色 #9CA3AF
 *  - 缩进: 24px/级, 无显式引导线(Logseq 用空白缩进)
 *  - 字体: 15px
 *  - 行高: 紧凑 28px
 *  - marker: 彩色圆角标签
 */
@Component
export struct BlockView {
  @Prop blockUuid: string = '';
  @Prop depth: number = 0;
  @State isEditing: boolean = false;
  @State editContent: string = '';
  @State showActions: boolean = false;
  @State displaySegments: ContentSegment[] = [];
  private blockData: BlockData | undefined;

  aboutToAppear(): void {
    this.refreshBlock();
  }

  refreshBlock(): void {
    const ws = WorkspaceService.getInstance();
    this.blockData = ws.getBlock(this.blockUuid);
    if (this.blockData) {
      this.displaySegments = ContentRenderer.parse(this.blockData.content);
    }
  }

  build() {
    if (!this.blockData) {
      Row().width('100%').height(0)
    } else {
      Column() {
        Row() {
          // 缩进空白（Logseq: 每级 24px）
          if (this.depth > 0) {
            Blank().width(this.depth * 24)
          }

          // 圆点 + 内容行
          Row({ space: 8 }) {
            // Logseq 风格圆点: 6px filled circle, 灰色
            Circle({ width: 6, height: 6 })
              .fill($r('app.color.bullet'))
              .margin({ top: 6 })

            Row({ space: 4 }) {
              // 任务标记（彩色标签）
              if (this.blockData.marker !== '') {
                Text(this.blockData.marker)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.getMarkerColor(this.blockData.marker))
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .borderRadius(3)
                  .backgroundColor(this.getMarkerBg(this.blockData.marker))
                  .onClick(() => {
                    const editor = EditorService.getInstance();
                    editor.setFocusedBlock(this.blockUuid);
                    editor.cycleMarker();
                    this.refreshBlock();
                  })
              }

              // 内容区
              if (this.isEditing) {
                TextArea({ text: this.editContent, placeholder: '输入内容...' })
                  .fontSize(15)
                  .fontColor($r('app.color.text'))
                  .backgroundColor($r('app.color.surface0'))
                  .layoutWeight(1)
                  .height(28)
                  .maxLength(5000)
                  .padding(0)
                  .onChange((value: string) => { this.editContent = value; })
                  .onBlur(() => {
                    EditorService.getInstance().updateBlockContent(this.blockUuid, this.editContent);
                    this.isEditing = false;
                    this.refreshBlock();
                  })
              } else {
                Row({ space: 0 }) {
                  if (this.displaySegments.length === 0) {
                    Text(' ')
                      .fontSize(15)
                      .fontColor($r('app.color.muted_text'))
                      .height(28)
                      .onClick(() => {
                        EditorService.getInstance().setFocusedBlock(this.blockUuid);
                        this.isEditing = true;
                        this.editContent = this.blockData ? this.blockData.content : '';
                      })
                  } else {
                    ForEach(this.displaySegments, (seg: ContentSegment, idx: number) => {
                      Text(seg.text)
                        .fontSize(15)
                        .fontColor(ContentRenderer.getSegmentColor(seg.type))
                        .fontWeight(seg.type === SegmentType.BOLD ? FontWeight.Bold : FontWeight.Normal)
                        .fontStyle(seg.type === SegmentType.ITALIC ? FontStyle.Italic : FontStyle.Normal)
                        .decoration({
                          type: seg.type === SegmentType.STRIKETHROUGH ? TextDecorationType.LineThrough : TextDecorationType.None,
                          color: $r('app.color.muted_text')
                        })
                        .backgroundColor(seg.type === SegmentType.HIGHLIGHT ? '#FFF3CD' : Color.Transparent)
                        .fontFamily(seg.type === SegmentType.CODE ? 'monospace' : '')
                        .height(28)
                        .onClick(() => {
                          if (ContentRenderer.isClickable(seg.type)) {
                            ContentRenderer.handleClick(seg.type, seg.text);
                          } else {
                            EditorService.getInstance().setFocusedBlock(this.blockUuid);
                            this.isEditing = true;
                            this.editContent = this.blockData ? this.blockData.content : '';
                          }
                        })
                    }, (seg: ContentSegment, idx: number) => idx.toString())
                  }
                }
                .layoutWeight(1)
              }
            }
            .layoutWeight(1)

            // 操作菜单（hover 时显示）
            if (this.showActions) {
              Row({ space: 2 }) {
                // Indent
                Row() {
                  Text('→').fontSize(12).fontColor($r('app.color.muted_text'))
                }
                .width(22).height(22)
                .onClick(() => { EditorService.getInstance().indentBlock(); this.refreshBlock(); this.showActions = false; })

                // Outdent
                Row() {
                  Text('←').fontSize(12).fontColor($r('app.color.muted_text'))
                }
                .width(22).height(22)
                .onClick(() => { EditorService.getInstance().outdentBlock(); this.refreshBlock(); this.showActions = false; })

                // Delete
                Row() {
                  Text('×').fontSize(14).fontColor($r('app.color.danger'))
                }
                .width(22).height(22)
                .onClick(() => {
                  WorkspaceService.getInstance().executeOp({ type: 'delete-block', uuid: this.blockUuid });
                  this.refreshBlock(); this.showActions = false;
                })
              }
            }
          }
          .width('100%')
          .constraintSize({ minHeight: 28 })
          .padding({ top: 2, bottom: 2 })
          .onClick(() => {
            if (!this.isEditing) {
              EditorService.getInstance().setFocusedBlock(this.blockUuid);
              this.showActions = !this.showActions;
            }
          })
        }
        .width('100%')

        // Block 嵌入预览
        if (this.hasEmbedSegments()) {
          this.EmbedBlocks()
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
  }

  hasEmbedSegments(): boolean {
    for (let i = 0; i < this.displaySegments.length; i++) {
      if (this.displaySegments[i].type === SegmentType.BLOCK_EMBED ||
          this.displaySegments[i].type === SegmentType.PAGE_EMBED) {
        return true;
      }
    }
    return false;
  }

  getEmbedUuids(): string[] {
    const uuids: string[] = [];
    for (let i = 0; i < this.displaySegments.length; i++) {
      if (this.displaySegments[i].type === SegmentType.BLOCK_EMBED) {
        uuids.push(this.displaySegments[i].text);
      }
    }
    return uuids;
  }

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
        .backgroundColor($r('app.color.surface1'))
        .borderRadius(4)
        .border({ width: { left: 2 }, color: $r('app.color.primary') })
        .padding({ left: 24 })
      }, (uuid: string) => uuid)
    }
    .width('100%')
  }

  getBlockContent(uuid: string): string {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(uuid);
    if (block) return block.content.substring(0, 120);
    return uuid.substring(0, 8) + '...';
  }

  getMarkerColor(marker: string): ResourceColor {
    if (marker === 'DONE') return '#10B981';
    if (marker === 'DOING') return '#0078D4';
    if (marker === 'TODO') return '#EF4444';
    if (marker === 'CANCELLED') return '#9CA3AF';
    return '#9CA3AF';
  }

  getMarkerBg(marker: string): ResourceColor {
    if (marker === 'DONE') return '#10B98118';
    if (marker === 'DOING') return '#0078D418';
    if (marker === 'TODO') return '#EF444418';
    if (marker === 'CANCELLED') return '#6B728018';
    return Color.Transparent;
  }
}
