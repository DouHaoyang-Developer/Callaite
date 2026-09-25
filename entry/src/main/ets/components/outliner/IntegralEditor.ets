import { hilog } from '@kit.PerformanceAnalysisKit';
import { TablerIcon } from '../common/Icons';
import { LivePreviewHelper } from '../../utils/LivePreviewHelper';
import { MarkdownExporter } from '../../core/parser/MarkdownExporter';
import { WorkspaceService } from '../../services/WorkspaceService';
import { SaveQueue } from '../../services/SaveQueue';
import { AppState } from '../../state/AppState';
import { promptAction } from '@kit.ArkUI';

/**
 * IntegralEditor —— 整页四模式编辑器（O4，参照 Lunius MarkdownEditor）。
 *
 * 模式：live（实时阅览，光标感知语法隐藏）/ source（源码着色）/ preview（阅读）/ split（分屏）。
 * 架构：原生 RichEditor 整页承载页面 Markdown；「应用并重建大纲」将 Markdown
 * 经 MarkdownParser 重建页面块（页面身份保持），随后回到块级视图。
 * 保存链：变更 → replacePageBlocks → SaveQueue.markDirty（即时持久化）。
 */
interface PreviewLine {
  text: string;
  size: number;
  weight: FontWeight;
  color: ResourceColor;
  indent: number;
  bullet: boolean;
}

@Component
export struct IntegralEditor {
  @Prop pageName: string = '';
  onClose: () => void = () => {};
  @State viewMode: string = 'live';
  @State markdown: string = '';
  @State previewLines: PreviewLine[] = [];
  private richController: RichEditorController = new RichEditorController();
  private livePreview: LivePreviewHelper = new LivePreviewHelper();
  private editorCaretOffset: number = -1;
  private pageUuid: string = '';
  private static readonly TAG = 'IntegralEditor';
  private static readonly DOMAIN = 0x0002;

  aboutToAppear(): void {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(this.pageName);
    if (page) {
      this.pageUuid = page.uuid;
      // 用「全页块」导出 markdown：getPageBlocks 仅顶层且走 childrenMap 查表，
      // 实测在该路径下取到空列表 → markdown 为空 → 编辑器空白、应用被拒。
      let blocks = ws.getAllPageBlocks(page.uuid);
      if (blocks.length === 0) {
        blocks = ws.getPageBlocks(page.uuid);
      }
      this.markdown = MarkdownExporter.export(page, blocks);
      console.info('[IntegralEditor] loaded page=' + page.name
        + ' blocks=' + blocks.length.toString()
        + ' mdLen=' + this.markdown.length.toString());
    } else {
      console.error('[IntegralEditor] page not found: ' + this.pageName);
    }
    this.rebuildPreview();
  }

  private rebuildPreview(): void {
    const lines = this.markdown.split('\n');
    const out: PreviewLine[] = [];
    let inCode = false;
    for (let i = 0; i < lines.length; i++) {
      const raw = lines[i];
      if (raw.startsWith('```')) {
        inCode = !inCode;
        out.push({ text: inCode ? '┌ 代码块' : '└', size: 11, weight: FontWeight.Normal,
          color: $r('app.color.muted_text'), indent: 0, bullet: false });
        continue;
      }
      if (inCode) {
        out.push({ text: raw, size: 13, weight: FontWeight.Normal,
          color: '#6A5ACD', indent: 12, bullet: false });
        continue;
      }
      if (raw.startsWith('### ')) {
        out.push({ text: raw.substring(4), size: 19, weight: FontWeight.Bold,
          color: $r('app.color.text'), indent: 0, bullet: false });
      } else if (raw.startsWith('## ')) {
        out.push({ text: raw.substring(3), size: 22, weight: FontWeight.Bold,
          color: $r('app.color.text'), indent: 0, bullet: false });
      } else if (raw.startsWith('# ')) {
        out.push({ text: raw.substring(2), size: 26, weight: FontWeight.Bold,
          color: $r('app.color.text'), indent: 0, bullet: false });
      } else if (raw.startsWith('- ') || raw.startsWith('* ')) {
        out.push({ text: raw.substring(2), size: 15, weight: FontWeight.Normal,
          color: $r('app.color.text'), indent: 16, bullet: true });
      } else if (raw.startsWith('> ')) {
        out.push({ text: raw.substring(2), size: 14, weight: FontWeight.Normal,
          color: $r('app.color.primary'), indent: 16, bullet: false });
      } else if (raw.trim() !== '') {
        out.push({ text: raw, size: 15, weight: FontWeight.Normal,
          color: $r('app.color.text'), indent: 0, bullet: false });
      }
    }
    this.previewLines = out;
  }

  /**
   * 编辑器当前文本；编辑器未挂载（阅读模式）或刚重建为空时，以 this.markdown 为准。
   * ⚠️ 不能直接用 extractText：切换模式会重建 RichEditor，新控制器内容为空。
   */
  private currentText(): string {
    if (this.viewMode === 'preview') {
      return this.markdown;
    }
    const t = LivePreviewHelper.extractText(this.richController);
    return t !== '' ? t : this.markdown;
  }

  /**
   * 把编辑器纯文本转换为 MarkdownParser 能识别的 markdown。
   *
   * ⚠️ 关键约定：RichEditor 里存的是**纯文本**（`- ` 块前缀只在渲染层作为装饰，
   * extractText 取不到），而 MarkdownParser 把「非 `- ` 开头」的行当作上一块的
   * **续行**处理 —— 于是纯文本文档解析出 **0 个块**，「应用并重建」会把整页清空
   * （实测：块行数 1 → 0，文件变 0 字节）。因此重建前必须补回块前缀。
   *
   * 已含块前缀则原样返回；否则按行补 `- `（每行一个顶层块，保留行序）。
   * 已知限制：v1 只保内容不保缩进层级（缩进信息在 span 中，后续可从 spans 还原）。
   */
  private toMarkdown(text: string): string {
    if (text.trim() === '') {
      return '';
    }
    const lines: string[] = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      if (l.startsWith('- ') || l.startsWith('* ')) {
        return text;
      }
    }
    const out: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const l = lines[i];
      if (l.trim() === '') {
        continue;
      }
      out.push('- ' + l.trim());
    }
    return out.join('\n');
  }

  /** 应用 Markdown → 重建页面块（身份保持）→ 即时持久化 */
  private applyAndRebuild(): void {
    const text = this.toMarkdown(this.currentText());
    // 防误删硬闸：空内容不得覆盖已有块。
    // 实测缺陷：切换模式（分屏/阅读）会使 RichEditor 重建为空 → markdown 被清空
    // → 此处以空文本重建，整页块被清空并落盘（页面变 0 字节）。
    if (text.trim() === '') {
      promptAction.openToast({ message: '内容为空，已取消重建' });
      return;
    }
    const ok = WorkspaceService.getInstance().replacePageBlocks(this.pageUuid, text);
    if (ok) {
      SaveQueue.getInstance().markDirty();
      promptAction.openToast({ message: '大纲已重建' });
      this.onClose();
    } else {
      // 数据层防误删闸门拒绝（解析结果为空而原页面有块）时走这里
      promptAction.openToast({ message: '重建被拒绝：内容解析为空，已保护原页面' });
    }
  }

  private rebuildSpans(): void {
    if (this.livePreview.getIsRebuilding()) {
      return;
    }
    const caret = this.editorCaretOffset;
    // 关键：onReady 时编辑器是新创建的空实例，extractText 返回 ''。
    // 此时必须用 this.markdown 回填，否则会把空内容写回编辑器 → onDidChange
    // → markdown 被清空 → 整页内容丢失。分屏模式同样需要回填（原先漏了，
    // 导致分屏左栏空白）。
    const extracted = LivePreviewHelper.extractText(this.richController);
    const text = extracted !== '' ? extracted : this.markdown;
    if (this.viewMode === 'live' || this.viewMode === 'split') {
      this.livePreview.buildSpans(this.richController, text, caret);
    } else if (this.viewMode === 'source') {
      this.livePreview.buildSourceSpans(this.richController, text);
    }
    if (caret >= 0 && caret <= text.length) {
      this.richController.setCaretOffset(caret);
    }
  }

  private handleEditorChange(): void {
    if (this.livePreview.getIsRebuilding()) {
      return;
    }
    const t = LivePreviewHelper.extractText(this.richController);
    // 防误删：编辑器重建期间的「空提取」不得覆盖非空 markdown。
    // （用户真正清空全文的场景极少，且删除到只剩空行时 extractText 通常仍含换行；
    //   以「宁可保留旧内容」为代价换取绝不会静默清空整页。）
    if (t !== '' || this.markdown === '') {
      this.markdown = t;
    }
    if (this.viewMode === 'live' || this.viewMode === 'source') {
      this.rebuildSpans();
    }
    if (this.viewMode === 'split') {
      this.rebuildPreview();
    }
  }

  private handleSelectionChange(): void {
    if (this.livePreview.getIsRebuilding()) {
      return;
    }
    try {
      this.editorCaretOffset = this.richController.getCaretOffset();
    } catch (e) {
      this.editorCaretOffset = -1;
    }
    if (this.viewMode === 'live') {
      this.rebuildSpans();
    }
  }

  @Builder
  ModeButton(mode: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.viewMode === mode ? $r('app.color.primary') : $r('app.color.muted_text'))
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(6)
      .backgroundColor(this.viewMode === mode ? $r('app.color.surface2') : Color.Transparent)
      .onClick(() => {
        const prev = this.viewMode;
        this.viewMode = mode;
        if (prev !== mode) {
          if (mode === 'live' || mode === 'source') {
            this.rebuildSpans();
          } else {
            this.rebuildPreview();
          }
        }
      })
  }

  @Builder
  PreviewPane() {
    Scroll() {
      Column({ space: 6 }) {
        ForEach(this.previewLines, (line: PreviewLine) => {
          Row({ space: 6 }) {
            if (line.bullet) {
              Circle({ width: 5, height: 5 }).fill($r('app.color.bullet')).margin({ top: 8 })
            }
            Text(line.text)
              .fontSize(line.size)
              .fontWeight(line.weight)
              .fontColor(line.color)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: line.indent })
        }, (line: PreviewLine) => line.text + line.size.toString())
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .align(Alignment.TopStart)
  }

  build() {
    Column({ space: 0 }) {
      // ─── 顶部：页名 + 模式切换 + 应用 ───
      Row({ space: 8 }) {
        Text(this.pageName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text'))
          .layoutWeight(1)
          .maxLines(1)
        this.ModeButton('live', '实时')
        this.ModeButton('source', '源码')
        this.ModeButton('preview', '阅读')
        this.ModeButton('split', '分屏')
        Row() {
          TablerIcon('check', 14, $r('app.color.on_primary'))
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(6)
        .backgroundColor($r('app.color.primary'))
        .onClick(() => {
          this.applyAndRebuild();
        })
        Row() {
          TablerIcon('x', 14, $r('app.color.muted_text'))
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .borderRadius(6)
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 12, top: 8, bottom: 8 })
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      // ─── 内容区（按模式）───
      if (this.viewMode === 'split') {
        Row({ space: 0 }) {
          Column({ space: 0 }) {
            RichEditor({ controller: this.richController })
              .onReady(() => {
                this.rebuildSpans();
              })
              .onDidChange(() => {
                this.handleEditorChange();
              })
              .onSelectionChange(() => {
                this.handleSelectionChange();
              })
              .width('100%')
              .height('100%')
              .padding({ left: 12, right: 8 })
          }
          .layoutWeight(1)
          .height('100%')
          .border({ width: { right: 1 }, color: $r('app.color.border') })

          Column({ space: 0 }) {
            this.PreviewPane()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.viewMode === 'preview') {
        this.PreviewPane()
      } else {
        // live / source：整页 RichEditor
        RichEditor({ controller: this.richController })
          .onReady(() => {
            this.rebuildSpans();
          })
          .onDidChange(() => {
            this.handleEditorChange();
          })
          .onSelectionChange(() => {
            this.handleSelectionChange();
          })
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }
}
