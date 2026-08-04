import { AppState } from '../state/AppState';

export interface ContentSegment {
  text: string;
  type: SegmentType;
}

export enum SegmentType {
  TEXT = 0,
  PAGE_REF = 1,
  BLOCK_REF = 2,
  TAG_REF = 3,
  BOLD = 4,
  ITALIC = 5,
  CODE = 6,
  HIGHLIGHT = 7,
  STRIKETHROUGH = 8,
  PAGE_EMBED = 9,
  BLOCK_EMBED = 10,
  IMAGE = 11,
  BLOCKQUOTE = 12,
  TABLE_CELL = 13,
  MATH_INLINE = 14,
  MATH_BLOCK = 15,
  MERMAID = 16
}

interface MatchResult {
  segment: ContentSegment;
  consumed: number;
}

export class ContentRenderer {

  static parse(text: string): ContentSegment[] {
    if (!text || text.length === 0) {
      return [];
    }

    // 代码块 ```...``` 整体渲染
    if (text.startsWith('```') && text.endsWith('```') && text.length > 6) {
      let inner = text.substring(3, text.length - 3);
      const nlIdx = inner.indexOf('\n');
      if (nlIdx > 0) {
        const lang = inner.substring(0, nlIdx).trim();
        if (lang === 'mermaid') {
          const seg: ContentSegment = { text: inner.substring(nlIdx + 1), type: SegmentType.MERMAID };
          const result: ContentSegment[] = [];
          result.push(seg);
          return result;
        }
        inner = inner.substring(nlIdx + 1);
      }
      const seg: ContentSegment = { text: inner, type: SegmentType.CODE };
      const result: ContentSegment[] = [];
      result.push(seg);
      return result;
    }

    const segments: ContentSegment[] = [];
    let pos = 0;

    while (pos < text.length) {
      // 查找当前位置开始的匹配
      const match = ContentRenderer.tryMatchAt(text, pos);
      if (match) {
        segments.push(match.segment);
        pos = pos + match.consumed;
      } else {
        // 累积纯文本直到下一个匹配开始
        let nextMatch = text.length;
        const candidates = ContentRenderer.findPatternStarts(text, pos);
        if (candidates.length > 0) {
          nextMatch = candidates[0];
        }
        if (nextMatch > pos) {
          segments.push({ text: text.substring(pos, nextMatch), type: SegmentType.TEXT });
        }
        pos = nextMatch;
      }
    }

    return segments;
  }

  private static tryMatchAt(text: string, pos: number): MatchResult | undefined {
    if (pos >= text.length) return undefined;

    const ch = text.charAt(pos);

    // [[page]] or ![[page]]
    if (pos + 1 < text.length && text.charAt(pos) === '[' && text.charAt(pos + 1) === '[') {
      const end = text.indexOf(']]', pos + 2);
      if (end > pos + 2) {
        const isEmbed = pos > 0 && text.charAt(pos - 1) === '!';
        const inner = text.substring(pos + 2, end);
        const segType = isEmbed ? SegmentType.PAGE_EMBED : SegmentType.PAGE_REF;
        const consumed = end + 2 - pos;
        const seg: ContentSegment = { text: inner, type: segType };
        const result: MatchResult = { segment: seg, consumed: consumed };
        return result;
      }
    }

    // ((uuid)) or !((uuid))
    if (pos + 1 < text.length && text.charAt(pos) === '(' && text.charAt(pos + 1) === '(') {
      const end = text.indexOf('))', pos + 2);
      if (end > pos + 2) {
        const isEmbed = pos > 0 && text.charAt(pos - 1) === '!';
        const inner = text.substring(pos + 2, end);
        const segType = isEmbed ? SegmentType.BLOCK_EMBED : SegmentType.BLOCK_REF;
        const consumed = end + 2 - pos;
        const seg: ContentSegment = { text: inner, type: segType };
        const result: MatchResult = { segment: seg, consumed: consumed };
        return result;
      }
    }

    // **bold**
    if (ch === '*' && pos + 2 < text.length && text.charAt(pos + 1) === '*') {
      const end = text.indexOf('**', pos + 2);
      if (end > pos + 2) {
        const inner = text.substring(pos + 2, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.BOLD };
        const result: MatchResult = { segment: seg, consumed: end + 2 - pos };
        return result;
      }
    }

    // *italic*
    if (ch === '*' && (pos === 0 || text.charAt(pos - 1) !== '*') &&
        (pos + 1 >= text.length || text.charAt(pos + 1) !== '*')) {
      const end = text.indexOf('*', pos + 1);
      if (end > pos + 1) {
        const inner = text.substring(pos + 1, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.ITALIC };
        const result: MatchResult = { segment: seg, consumed: end + 1 - pos };
        return result;
      }
    }

    // ==highlight==
    if (ch === '=' && pos + 1 < text.length && text.charAt(pos + 1) === '=') {
      const end = text.indexOf('==', pos + 2);
      if (end > pos + 2) {
        const inner = text.substring(pos + 2, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.HIGHLIGHT };
        const result: MatchResult = { segment: seg, consumed: end + 2 - pos };
        return result;
      }
    }

    // ~~strikethrough~~
    if (ch === '~' && pos + 1 < text.length && text.charAt(pos + 1) === '~') {
      const end = text.indexOf('~~', pos + 2);
      if (end > pos + 2) {
        const inner = text.substring(pos + 2, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.STRIKETHROUGH };
        const result: MatchResult = { segment: seg, consumed: end + 2 - pos };
        return result;
      }
    }

    // `code`
    if (ch === '`') {
      const end = text.indexOf('`', pos + 1);
      if (end > pos + 1) {
        const inner = text.substring(pos + 1, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.CODE };
        const result: MatchResult = { segment: seg, consumed: end + 1 - pos };
        return result;
      }
    }

    // #tag
    if (ch === '#' && (pos === 0 || text.charAt(pos - 1) === ' ')) {
      if (pos + 1 < text.length && ContentRenderer.isTagChar(text.charAt(pos + 1))) {
        let end = pos + 1;
        while (end < text.length && ContentRenderer.isTagChar(text.charAt(end))) {
          end++;
        }
        const inner = text.substring(pos + 1, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.TAG_REF };
        const result: MatchResult = { segment: seg, consumed: end - pos };
        return result;
      }
    }

    // ![](url) 图片
    if (ch === '!' && pos + 1 < text.length && text.charAt(pos + 1) === '[') {
      const altEnd = text.indexOf('](', pos + 2);
      if (altEnd > pos + 2) {
        const urlEnd = text.indexOf(')', altEnd + 2);
        if (urlEnd > altEnd + 2) {
          const url = text.substring(altEnd + 2, urlEnd);
          const seg: ContentSegment = { text: url, type: SegmentType.IMAGE };
          const result: MatchResult = { segment: seg, consumed: urlEnd + 1 - pos };
          return result;
        }
      }
    }

    // > 引用块
    if (ch === '>' && (pos === 0 || text.charAt(pos - 1) === '\n')) {
      const seg: ContentSegment = { text: '▎', type: SegmentType.BLOCKQUOTE };
      const result: MatchResult = { segment: seg, consumed: 1 };
      return result;
    }

    // $$ 块级数学公式
    if (ch === '$' && pos + 1 < text.length && text.charAt(pos + 1) === '$') {
      const end = text.indexOf('$$', pos + 2);
      if (end > pos + 2) {
        const inner = text.substring(pos + 2, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.MATH_BLOCK };
        const result: MatchResult = { segment: seg, consumed: end + 2 - pos };
        return result;
      }
    }

    // $ 行内数学公式
    if (ch === '$' && (pos + 1 >= text.length || text.charAt(pos + 1) !== '$')) {
      const end = text.indexOf('$', pos + 1);
      if (end > pos + 1) {
        const inner = text.substring(pos + 1, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.MATH_INLINE };
        const result: MatchResult = { segment: seg, consumed: end + 1 - pos };
        return result;
      }
    }

    return undefined;
  }

  private static findPatternStarts(text: string, fromPos: number): number[] {
    const result: number[] = [];
    for (let i = fromPos; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === '[' || ch === '(' || ch === '*' || ch === '=' ||
          ch === '~' || ch === '`' || ch === '#') {
        result.push(i);
      }
    }
    return result;
  }

  private static isTagChar(ch: string): boolean {
    const code = ch.charCodeAt(0);
    return (code >= 48 && code <= 57) ||
           (code >= 65 && code <= 90) ||
           (code >= 97 && code <= 122) ||
           code === 45 || code === 95 ||
           code >= 0x4e00;
  }

  static getSegmentColor(type: SegmentType): ResourceColor {
    if (type === SegmentType.PAGE_REF || type === SegmentType.PAGE_EMBED) return $r('app.color.link');
    if (type === SegmentType.BLOCK_REF || type === SegmentType.BLOCK_EMBED) return $r('app.color.primary');
    if (type === SegmentType.TAG_REF) return $r('app.color.success');
    if (type === SegmentType.CODE) return '#EF4444';
    if (type === SegmentType.HIGHLIGHT) return '#B8860B';
    if (type === SegmentType.IMAGE) return $r('app.color.link');
    if (type === SegmentType.BLOCKQUOTE) return $r('app.color.muted_text');
    if (type === SegmentType.MATH_INLINE || type === SegmentType.MATH_BLOCK) return '#8B5CF6';
    if (type === SegmentType.MERMAID) return '#06B6D4';
    return $r('app.color.text');
  }

  static isClickable(type: SegmentType): boolean {
    return type === SegmentType.PAGE_REF || type === SegmentType.BLOCK_REF ||
           type === SegmentType.TAG_REF || type === SegmentType.PAGE_EMBED ||
           type === SegmentType.BLOCK_EMBED || type === SegmentType.IMAGE;
  }

  static handleClick(type: SegmentType, value: string): void {
    if (type === SegmentType.PAGE_REF || type === SegmentType.PAGE_EMBED) {
      AppState.setCurrentPage(value);
    }
    if (type === SegmentType.BLOCK_REF || type === SegmentType.BLOCK_EMBED) {
      AppState.setCurrentPage(value);
    }
    if (type === SegmentType.TAG_REF) {
      AppState.setCurrentPage(value);
    }
  }
}
