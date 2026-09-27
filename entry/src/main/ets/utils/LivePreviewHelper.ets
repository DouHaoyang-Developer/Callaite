// utils/LivePreviewHelper.ets
// Lunius 风格实时阅览引擎 —— 基于 RichEditor Spans 的光标感知语法隐藏

import { parseMarkdownSegments, MarkdownSegment } from './MarkdownSegmenter';

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
  return {
    fontColor: Color.Transparent,
    fontSize: 1
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

export interface RichEditorTextStyle {
  fontColor?: ResourceColor;
  fontSize?: number;
  fontWeight?: FontWeight;
  fontFamily?: string;
  fontStyle?: FontStyle;
  decoration?: DecorationStyle;
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
    try {
      controller.deleteSpans();
      this.buildSpansInternal(controller, text, caretOffset);
    } catch (e) {
      console.error('LivePreviewHelper buildSpans error: ' + JSON.stringify(e));
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

    for (let i = 0; i < segments.length; i++) {
      const seg: MarkdownSegment = segments[i];
      if (!seg.text) continue;

      const segStart: number = offset;
      const segEnd: number = offset + seg.text.length;
      offset = segEnd;

      // 判断光标是否在语法段内
      const cursorInside: boolean = caretOffset >= 0 &&
        caretOffset >= segStart && caretOffset < segEnd;

      // 换行符重置行上下文
      if (seg.text === '\n') {
        currentLineContext = LineContext.NORMAL;
        headingLevel = 0;
        continue;
      }

      // 根据段类型和行上下文选择样式
      const style = this.chooseStyle(seg, cursorInside, currentLineContext, headingLevel);

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
    lineCtx: LineContext, headingLvl: number): RichEditorTextStyle | null {

    const isSyntax: boolean = seg.type === 'syntax';

    // ─── 内容段：始终显示 ───────────────────────
    if (!isSyntax) {
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
