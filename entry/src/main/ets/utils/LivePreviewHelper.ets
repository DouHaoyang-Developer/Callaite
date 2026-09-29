// utils/LivePreviewHelper.ets
// Lunius 风格实时阅览引擎 —— 基于 RichEditor Spans 的光标感知语法隐藏

import { parseMarkdownSegments, MarkdownSegment } from './MarkdownSegmenter';
import { BusinessError } from '@kit.BasicServicesKit';

// ─── 样式工厂 ─────────────────────────────────
//
// ⚠️ 这里全部由「模块级字面量常量」改为「按主题 token 取色的函数」，原因：
//   原实现把正文写死 `#1A1A1A`、Callout 写死 `#333333`、代码块写死 `#6A5ACD`，
//   而 IntegralEditor 的编辑区底色是 `$r('app.color.surface0')`
//   （浅色 #FFFFFF / 暗色 #202020）→ 暗色下 `#1A1A1A` on `#202020` ≈ **1.06:1**，
//   整页正文完全不可见；`#333333` ≈ 1.29:1，同样不可读。
//
// 改用 `$r('app.color.*')` 后由资源限定符自动切换明暗两套值，
// 无需 import ThemeManager 判断主题（与 ContentRenderer.ets:281 的既有做法一致）。

function syntaxHiddenStyle(): RichEditorTextStyle {
  // ⚠️ 「隐藏态」必须与 syntaxVisibleStyle() **字号/字体完全一致**，只把颜色设为透明。
  //    原实现用 `fontSize: 1` 隐藏标记：光标移进标记时字号 1→14 会改变文本度量 →
  //    触发原生重排 → 选区/caret 变化 → 再次触发重排的同步反馈，实测在
  //    `**bold**` 标记内点击会把 JS 调用栈打爆（`Stack overflow!` @buildSpansInternal）
  //    且编辑器被清成空白。改为「同度量、仅换色」后翻转不再引发重排。
  return {
    fontColor: Color.Transparent,
    fontSize: 14,
    fontFamily: 'monospace'
  };
}

function syntaxVisibleStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.muted_text'),
    fontSize: 14,
    fontFamily: 'monospace'
  };
}

function contentStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.text'),
    fontSize: 16,
    fontFamily: 'monospace'
  };
}

/**
 * 标题样式：层级靠字号/字重区分，颜色走主题。
 * H1/H3 → 主色；H2 → lp_h2（保留原来「二级标题偏品红」的辨识度）。
 */
function headingStyle(level: number): RichEditorTextStyle {
  if (level === 1) {
    return {
      fontColor: $r('app.color.primary'),
      fontSize: 28, fontWeight: FontWeight.Bold, fontFamily: 'monospace'
    };
  }
  if (level === 2) {
    return {
      fontColor: $r('app.color.lp_h2'),
      fontSize: 24, fontWeight: FontWeight.Bold, fontFamily: 'monospace'
    };
  }
  return {
    fontColor: $r('app.color.primary'),
    fontSize: 20, fontWeight: FontWeight.Bold, fontFamily: 'monospace'
  };
}

function quoteStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.primary'), fontSize: 16,
    fontStyle: FontStyle.Italic, fontFamily: 'monospace'
  };
}

function codeLineStyle(): RichEditorTextStyle {
  return { fontColor: $r('app.color.lp_code'), fontSize: 15, fontFamily: 'monospace' };
}

/**
 * 分隔线（`---` 渲染成的文本）：走 muted 灰。
 * 明暗两套底色上都可辨（暗色 #202020 上 ≈3.5:1），且比原来的 #C7C7CC 在浅色下更清楚。
 */
function hrStyle(): RichEditorTextStyle {
  return { fontColor: $r('app.color.bullet'), fontSize: 14, fontFamily: 'monospace' };
}

function embedSyntaxStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.link'), fontSize: 16, fontFamily: 'monospace',
    fontWeight: FontWeight.Medium
  };
}

// ─── 行内格式的「渲染态」样式（D-Gate 1 判据③：加粗 / 行内代码 / 高亮）───
//
// 光标不在标记内时使用这三套样式，标记本身按 syntaxHiddenStyle() 隐藏。
// 三者必须**视觉上互相可区分**，否则「渲染态」退化成普通正文，等于没渲染。

/** 加粗渲染态：粗体正文色 */
function inlineBoldStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.text'), fontSize: 16,
    fontWeight: FontWeight.Bold, fontFamily: 'monospace'
  };
}

/** 行内代码渲染态：代码色 + 等宽 + 弱底色块 */
function inlineCodeStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.inline_code'), fontSize: 15, fontFamily: 'monospace',
    textBackgroundStyle: { color: $r('app.color.surface2'), radius: 2 }
  };
}

/**
 * 高亮渲染态：真·底色填充。
 * `RichEditorTextStyle.textBackgroundStyle`（@since 18，本项目 compatibleSdkVersion 26）——
 * 这是「原生 span 做不出底色」这一旧假设的反例；无需 RichEditorStyledStringController。
 * 色值走 `app.color.search_highlight`，明暗两套资源自动切换。
 */
function highlightStyle(): RichEditorTextStyle {
  return {
    fontColor: $r('app.color.text'), fontSize: 16, fontFamily: 'monospace',
    textBackgroundStyle: { color: $r('app.color.search_highlight'), radius: 2 }
  };
}

export interface RichEditorTextStyle {
  fontColor?: ResourceColor;
  fontSize?: number;
  fontWeight?: FontWeight;
  fontFamily?: string;
  fontStyle?: FontStyle;
  decoration?: DecorationStyle;
  /** 文字底色（@since 18）——高亮渲染态用它做真·底色填充 */
  textBackgroundStyle?: TextBackgroundStyle;
}

// ─── 行级上下文类型 ───────────────────────────

enum LineContext {
  NORMAL = 'normal',
  HEADING = 'heading',
  QUOTE = 'quote',
  CALLOUT = 'callout',
  CODE = 'code',
  HR = 'hr',
  LIST = 'list'
}

export class LivePreviewHelper {
  private isRebuilding: boolean = false;

  getIsRebuilding(): boolean {
    return this.isRebuilding;
  }

  // ─── 主体方法：将 Markdown 文本渲染为 RichEditor Spans ────

  buildSpans(controller: RichEditorController, text: string, caretOffset: number): void {
    if (this.isRebuilding) return;
    this.isRebuilding = true;
    // 出错时区分「哪一步抛的」：deleteSpans 抛 → 编辑器已被清空且未回填（表现为整页空白）；
    // addTextSpan 抛 → 只丢失样式。`JSON.stringify(Error)` 恒为 {}，必须打 code/message。
    let stage = 'start';
    try {
      stage = 'deleteSpans';
      controller.deleteSpans();
      stage = 'buildSpansInternal';
      this.buildSpansInternal(controller, text, caretOffset);
    } catch (e) {
      const err = e as BusinessError;
      console.error('LivePreviewHelper buildSpans error at ' + stage
        + ' code=' + err.code + ' msg=' + err.message
        + ' textLen=' + text.length.toString()
        + ' caret=' + caretOffset.toString());
    } finally {
      this.isRebuilding = false;
    }
  }

  // ─── 源码模式：Markdown 段级语法着色 ─────────────

  buildSourceSpans(controller: RichEditorController, text: string): void {
    if (this.isRebuilding) return;
    this.isRebuilding = true;
    try {
      controller.deleteSpans();
      if (text.length === 0) return;

      const segments = parseMarkdownSegments(text);
      let currentLineContext: LineContext = LineContext.NORMAL;
      let headingLevel = 0;

      for (let i = 0; i < segments.length; i++) {
        const seg = segments[i];
        if (!seg.text) continue;

        // 换行后重置
        if (seg.text === '\n') {
          currentLineContext = LineContext.NORMAL;
          headingLevel = 0;
          controller.addTextSpan('\n');
          continue;
        }

        // 语法段：检测行上下文
        if (seg.type === 'syntax') {
          const hMatch = seg.text.match(/^(#{1,6})\s/);
          if (hMatch) { currentLineContext = LineContext.HEADING; headingLevel = hMatch[1].length; }
          if (seg.text.match(/^>\s?/)) { currentLineContext = LineContext.QUOTE; }
          if (seg.text.match(/^[\-\*\+]\s/) || seg.text.match(/^\d+\.\s/)) { currentLineContext = LineContext.LIST; }
          if (/^(---|\*\*\*|___)\s*$/.test(seg.text.trim())) { currentLineContext = LineContext.HR; }
        }

        // 选择样式：语法段用灰/隐藏，内容段用行级着色
        if (seg.type === 'syntax') {
          controller.addTextSpan(seg.text, { style: syntaxVisibleStyle() });
        } else {
          let style: RichEditorTextStyle = contentStyle();
          if (currentLineContext === LineContext.HEADING && headingLevel > 0 && headingLevel <= 3) {
            style = headingStyle(headingLevel);
          } else if (currentLineContext === LineContext.QUOTE) {
            style = quoteStyle();
          } else if (currentLineContext === LineContext.HR) {
            style = hrStyle();
          }
          controller.addTextSpan(seg.text, { style: style });
        }
      }
    } catch (e) {
      console.error('LivePreviewHelper buildSourceSpans error');
    } finally {
      this.isRebuilding = false;
    }
  }

  // ─── 从 spans 重建纯文本 ──────────────────────

  static extractText(controller: RichEditorController): string {
    try {
      const spans = controller.getSpans();
      let text = '';
      for (let i = 0; i < spans.length; i++) {
        const item = spans[i];
        if (item !== null && item !== undefined) {
          const spanObj = item as RichEditorTextSpanResult;
          const value: string = spanObj.value;
          text = text + value;
        }
      }
      return text;
    } catch (e) {
      console.error('LivePreviewHelper extractText error');
      return '';
    }
  }

  // ─── 内部实现：逐行解析 + 光标感知 ─────────────

  private buildSpansInternal(controller: RichEditorController, text: string, caretOffset: number): void {
    const segments = parseMarkdownSegments(text);
    let offset: number = 0;

    // 当前行的上下文（追踪是否在标题行、引用行、列表行等）
    let currentLineContext: LineContext = LineContext.NORMAL;
    let headingLevel: number = 0;
    let inCodeBlock: boolean = false;

    // 行内上下文（判据③）：粗体 / 行内代码 / 高亮 三类「编辑态↔渲染态」翻转。
    // 标记段成对出现，进入时置位、离开时复位；内容段据此选渲染态样式。
    let inBold: boolean = false;
    let inInlineCode: boolean = false;
    let inHighlight: boolean = false;

    for (let i = 0; i < segments.length; i++) {
      const seg: MarkdownSegment = segments[i];
      if (!seg.text) continue;

      const segStart: number = offset;
      const segEnd: number = offset + seg.text.length;
      offset = segEnd;

      // 判断光标是否在语法段内
      const cursorInside: boolean = caretOffset >= 0 &&
        caretOffset >= segStart && caretOffset < segEnd;

      // ★ 换行符必须写回编辑器。
      //   原实现在此 `continue` 而不 addTextSpan('\n')：每次 onDidChange 触发
      //   buildSpans 都会把编辑器内的**所有换行抹掉**，整页塌成一行；随后
      //   handleEditorChange 把塌缩结果回写 this.markdown，点「应用并重建」
      //   即以 1 个块覆盖整页并落盘（实测 6 块 → 1 块，文件 71B → 66B）。
      //   这就是「模式切换/重建后整页块被清空并落盘」的根因，而不是缺 markdown 回填。
      //   保留换行后，getSpans() 读回的就是含 `  ` 缩进与 `- ` 前缀的原文。
      if (seg.text === '\n') {
        currentLineContext = LineContext.NORMAL;
        headingLevel = 0;
        inBold = false;
        inInlineCode = false;
        inHighlight = false;
        controller.addTextSpan('\n');
        continue;
      }

      // ─── 行内格式标记段：翻转上下文 + 按光标位置决定显示/隐藏标记 ───
      if (seg.type === 'syntax' &&
          (seg.text === '**' || seg.text === '`' || seg.text === '==')) {
        controller.addTextSpan(seg.text, {
          style: cursorInside ? syntaxVisibleStyle() : syntaxHiddenStyle()
        });
        if (seg.text === '**') {
          inBold = !inBold;
        } else if (seg.text === '`') {
          inInlineCode = !inInlineCode;
        } else {
          inHighlight = !inHighlight;
        }
        continue;
      }

      // 根据段类型和行上下文选择样式
      const style = this.chooseStyle(seg, cursorInside, currentLineContext, headingLevel,
        inBold, inInlineCode, inHighlight);

      // 更新行上下文
      if (seg.type === 'syntax') {
        // 检测标题
        const hMatch = seg.text.match(/^(#{1,6})\s$/);
        if (hMatch) {
          currentLineContext = LineContext.HEADING;
          headingLevel = hMatch[1].length;
        }
        // 检测引用 / Callout
        if (seg.text.match(/^>\s*\[!/)) {
          currentLineContext = LineContext.CALLOUT;
        } else if (seg.text.match(/^>\s?/)) {
          currentLineContext = LineContext.QUOTE;
        }
        // 检测列表标记
        if (seg.text.match(/^[\-\*\+]\s$/) || seg.text.match(/^\d+\.\s$/)) {
          currentLineContext = LineContext.LIST;
        }
        // 检测 Wiki 嵌入 ![[
        if (seg.text.startsWith('![[')) {
          currentLineContext = LineContext.NORMAL;
        }
        // 检测分割线
        if (seg.text.match(/^(---|\*\*\*|___)\s*$/)) {
          currentLineContext = LineContext.HR;
        }
        // 检测 Fenced 代码块开始 ```lang / 结束 ```
        if (seg.text.match(/^```/) && !seg.text.match(/^```.*```$/)) {
          inCodeBlock = !inCodeBlock;
          if (inCodeBlock) {
            currentLineContext = LineContext.CODE;
          } else {
            currentLineContext = LineContext.NORMAL;
          }
          continue;
        }
      }

      if (style) {
        controller.addTextSpan(seg.text, { style: style });
      } else {
        controller.addTextSpan(seg.text, {});
      }
    }
  }

  private chooseStyle(seg: MarkdownSegment, cursorInside: boolean,
    lineCtx: LineContext, headingLvl: number,
    inBold: boolean = false, inInlineCode: boolean = false,
    inHighlight: boolean = false): RichEditorTextStyle | null {

    const isSyntax: boolean = seg.type === 'syntax';

    // ─── 内容段：始终显示 ───────────────────────
    if (!isSyntax) {
      // 行内格式优先于行级样式：内容处在 `**` / `` ` `` / `==` 之间时走渲染态
      if (inInlineCode) {
        return inlineCodeStyle();
      }
      if (inHighlight) {
        return highlightStyle();
      }
      if (inBold) {
        return inlineBoldStyle();
      }
      if (lineCtx === LineContext.CALLOUT) {
        return contentStyle();
      }
      if (lineCtx === LineContext.QUOTE) {
        return quoteStyle();
      }
      if (lineCtx === LineContext.CODE) {
        return codeLineStyle();
      }
      if (lineCtx === LineContext.HR) {
        return hrStyle();
      }
      if (lineCtx === LineContext.HEADING && headingLvl > 0 && headingLvl <= 3) {
        // 标题内容用对应样式
        return headingStyle(headingLvl);
      }
      return contentStyle();
    }

    // ─── 语法段 ─────────────────────────────────
    // Wiki 链接语法 [[ ]] 用主题链接色标识
    if (seg.text === '[[' || seg.text === ']]' ||
        seg.text.startsWith('![[') || seg.text.startsWith('[[')) {
      const embedStyle: RichEditorTextStyle = embedSyntaxStyle();
      if (cursorInside) return embedStyle;
      return syntaxHiddenStyle();
    }
    // 核心逻辑：光标不在语法段内 → 隐藏；光标在语法段内 → 显示为灰色
    if (cursorInside) {
      return syntaxVisibleStyle();
    }
    return syntaxHiddenStyle();
  }
}
