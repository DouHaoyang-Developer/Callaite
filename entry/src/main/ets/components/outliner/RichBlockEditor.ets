import { WorkspaceService } from '../../services/WorkspaceService';
import { EditorService } from '../../services/EditorService';
import { ContentRenderer, ContentSegment, SegmentType } from '../../utils/ContentRenderer';

/**
 * RichBlockEditor — 使用 RichEditor 实现接近 Logseq contenteditable 的自由格式编辑。
 *
 * 相比 TextArea 的优势：
 *  - 行内格式渲染（粗体/斜体/代码/链接着色）
 *  - [[page]] / ((uuid)) / #tag 在编辑态即可见样式
 *  - 更好的光标控制
 *  - IME 安全的编辑流程
 */
@Component
export struct RichBlockEditor {
  @Prop blockUuid: string = '';
  @Prop initialContent: string = '';
  onSave: () => void = () => {};
  @State currentContent: string = '';

  private controller: RichEditorController = new RichEditorController();

  aboutToAppear(): void {
    this.currentContent = this.initialContent;
  }

  build() {
    Column() {
      RichEditor({ controller: this.controller })
        .onReady(() => {
          // 加载初始内容到 RichEditor
          this.loadContent(this.initialContent);
        })
        .onDidChange((_rangeBefore: TextRange, _rangeAfter: TextRange) => {
          // 获取当前全部文本内容
          this.controller.getSpans().then((spans: RichEditorImageSpanResult[]) => {
            // 从 spans 重建纯文本
            let text = '';
            for (let i = 0; i < spans.length; i++) {
              const span = spans[i] as RichEditorTextSpanResult;
              if (span.value !== undefined) {
                text = text + span.value;
              }
            }
            this.currentContent = text;
          });
        })
        .onBlur(() => {
          // 失焦时保存
          EditorService.getInstance().updateBlockContent(this.blockUuid, this.currentContent);
          this.onSave();
        })
        .width('100%')
        .constraintSize({ minHeight: 36 })
        .backgroundColor($r('app.color.surface0'))
    }
    .width('100%')
  }

  /**
   * 将 Logseq 格式文本加载到 RichEditor，并应用样式。
   */
  private loadContent(text: string): void {
    const segments = ContentRenderer.parse(text);

    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];
      const style: RichEditorTextStyle = this.buildStyle(seg.type);

      // 页面引用添加特殊前后缀显示
      if (seg.type === SegmentType.PAGE_REF || seg.type === SegmentType.PAGE_EMBED) {
        const prefix = seg.type === SegmentType.PAGE_EMBED ? '![[' : '[[';
        this.controller.addTextSpan(prefix, { fontColor: $r('app.color.muted_text'), fontSize: 15 });
        this.controller.addTextSpan(seg.text, style);
        this.controller.addTextSpan(']]', { fontColor: $r('app.color.muted_text'), fontSize: 15 });
      } else if (seg.type === SegmentType.BLOCK_REF || seg.type === SegmentType.BLOCK_EMBED) {
        const prefix = seg.type === SegmentType.BLOCK_EMBED ? '!>((' : '((';
        this.controller.addTextSpan(prefix, { fontColor: $r('app.color.muted_text'), fontSize: 15 });
        this.controller.addTextSpan(seg.text, style);
        this.controller.addTextSpan('))', { fontColor: $r('app.color.muted_text'), fontSize: 15 });
      } else {
        this.controller.addTextSpan(seg.text, style);
      }
    }
  }

  private buildStyle(type: SegmentType): RichEditorTextStyle {
    const base: RichEditorTextStyle = { fontSize: 15 };

    if (type === SegmentType.PAGE_REF || type === SegmentType.PAGE_EMBED) {
      base.fontColor = $r('app.color.link');
      base.fontWeight = FontWeight.Medium;
    } else if (type === SegmentType.BLOCK_REF || type === SegmentType.BLOCK_EMBED) {
      base.fontColor = $r('app.color.primary');
      base.fontWeight = FontWeight.Medium;
    } else if (type === SegmentType.TAG_REF) {
      base.fontColor = $r('app.color.success');
      base.fontWeight = FontWeight.Medium;
    } else if (type === SegmentType.BOLD) {
      base.fontWeight = FontWeight.Bold;
    } else if (type === SegmentType.ITALIC) {
      base.fontStyle = FontStyle.Italic;
    } else if (type === SegmentType.CODE) {
      base.fontColor = '#EF4444';
      base.fontFamily = 'monospace';
    } else if (type === SegmentType.HIGHLIGHT) {
      base.decoration = { type: TextDecorationType.Underline, color: '#B8860B' };
    } else if (type === SegmentType.STRIKETHROUGH) {
      base.decoration = { type: TextDecorationType.LineThrough, color: $r('app.color.muted_text') };
    }

    return base;
  }
}
