import { AppState } from '../state/AppState';
import { WorkspaceService } from '../services/WorkspaceService';
import { FileService } from '../services/FileService';
import { common } from '@kit.AbilityKit';

export interface ContentSegment {
  text: string;
  type: SegmentType;
  extra?: string;
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
  MERMAID = 16,
  LINK = 17
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
      let lang = '';
      if (nlIdx > 0) {
        lang = inner.substring(0, nlIdx).trim();
        if (lang === 'mermaid') {
          const seg: ContentSegment = { text: inner.substring(nlIdx + 1), type: SegmentType.MERMAID };
          const result: ContentSegment[] = [];
          result.push(seg);
          return result;
        }
        inner = inner.substring(nlIdx + 1);
      } else if (nlIdx === 0) {
        // 无语言围栏（``` 后直接换行）：去掉紧跟围栏的换行，避免高亮渲染出空首行
        inner = inner.substring(1);
      }
      // U3.5：围栏语言**必须随段携带**，否则 CodeBlock 无法做语法高亮。
      // 之前 lang 被直接丢弃（只用于判定 mermaid）。extra 原仅 LINK 段使用，此处复用无冲突。
      // 约定：extra !== undefined ⇔ 本段是**整块围栏代码块**；
      //       行内 `code`（tryMatchAt 的 ` 分支）不带 extra，两者据此区分。
      const seg: ContentSegment = { text: inner, type: SegmentType.CODE, extra: lang };
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
          pos = nextMatch;
        } else {
          // ────────── P0 死循环兜底（既有缺陷，非本次引入）──────────
          // 归因：git blame → e5fc508「基础功能实现及应用框架构建」(2026-08-03) 首次引入，
          //       之后 3 次改版（3a03508 / 84aeb67）均未触碰这 4 行，故与 U3.5 无关。
          //
          // 触发条件（精确表述）：
          //   块内容中出现「模式起始字符」(` [ ( * = ~ # ! > $) 之一，且该字符处
          //   tryMatchAt 因**闭合定界符缺失**而无法成段（如孤立的 `!` `=` `*` `(` `~` `$` `[`），
          //   同时 findPatternStarts 把 pos 自身报为候选 → nextMatch === pos → pos 不前进。
          //   等价说法：**任何含未配对定界符字符的块**都会让 parse() 同步死循环、挂死 UI 线程。
          //   （实测：`![[嵌入页]]` 使 com.example.callaite 单核 123% CPU、首帧永不渲染）
          //
          // 兜底语义：把该字符当普通文本消费掉，逐字前进。
          // 零回归论证：能进入本分支 ⇔ 原实现 pos 不前进 ⇒ 原实现**永不返回**。
          //   因此对任何「原本能返回」的输入，执行路径与输出**逐字节不变**。
          segments.push({ text: text.substring(pos, pos + 1), type: SegmentType.TEXT });
          pos = pos + 1;
        }
      }
    }

    return segments;
  }

  private static tryMatchAt(text: string, pos: number): MatchResult | undefined {
    if (pos >= text.length) return undefined;

    const ch = text.charAt(pos);

    // [[page]]（PAGE_REF）
    if (pos + 1 < text.length && text.charAt(pos) === '[' && text.charAt(pos + 1) === '[') {
      const end = text.indexOf(']]', pos + 2);
      if (end > pos + 2) {
        // ⚠️ P0 兜底修复的**配套保险**：`![[页]]` 的 PAGE_EMBED 分支原本因死循环而不可达，
        //    修好死循环后它会**第一次变成可达代码**（`!` 被兜底消费后，pos 落在 `[[` 且前一字符是 `!`）。
        //    嵌入渲染链（BlockView.hasEmbedSegments/EmbedBlocks）从未被任何输入执行过、未经真机验证，
        //    按「不放出未验证渲染路径」处置：此处**显式拦截**，一律降级为已验证的 PAGE_REF。
        //    视觉结果：`![[页]]` 原样显示为 `!` + `[[页]]`（可点击跳转），不崩、不白屏。
        //    如需启用嵌入，请单独开任务验证 EmbedBlocks 后再改回 isEmbed 判定。
        const inner = text.substring(pos + 2, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.PAGE_REF };
        const result: MatchResult = { segment: seg, consumed: end + 2 - pos };
        return result;
      }
    }

    // [text](url) markdown 链接
    if (ch === '[' && (pos + 1 >= text.length || text.charAt(pos + 1) !== '[')) {
      const closeBracket = text.indexOf('](', pos + 1);
      if (closeBracket > pos + 1) {
        const urlEnd = text.indexOf(')', closeBracket + 2);
        if (urlEnd > closeBracket + 2) {
          const label = text.substring(pos + 1, closeBracket);
          const url = text.substring(closeBracket + 2, urlEnd);
          const seg: ContentSegment = { text: url, type: SegmentType.LINK, extra: label };
          const result: MatchResult = { segment: seg, consumed: urlEnd + 1 - pos };
          return result;
        }
      }
    }

    // ((uuid))（BLOCK_REF）
    if (pos + 1 < text.length && text.charAt(pos) === '(' && text.charAt(pos + 1) === '(') {
      const end = text.indexOf('))', pos + 2);
      if (end > pos + 2) {
        // ⚠️ 同上：`!((uuid))` 的 BLOCK_EMBED 分支同样保持不可达，显式降级为已验证的 BLOCK_REF。
        const inner = text.substring(pos + 2, end);
        const seg: ContentSegment = { text: inner, type: SegmentType.BLOCK_REF };
        const result: MatchResult = { segment: seg, consumed: end + 2 - pos };
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
          ch === '~' || ch === '`' || ch === '#' || ch === '!' ||
          ch === '>' || ch === '$') {
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
    if (type === SegmentType.CODE) return $r('app.color.inline_code');
    if (type === SegmentType.HIGHLIGHT) return $r('app.color.text');
    if (type === SegmentType.IMAGE) return $r('app.color.link');
    if (type === SegmentType.BLOCKQUOTE) return $r('app.color.muted_text');
    if (type === SegmentType.MATH_INLINE || type === SegmentType.MATH_BLOCK) return $r('app.color.math');
    if (type === SegmentType.MERMAID) return $r('app.color.mermaid');
    if (type === SegmentType.LINK) return $r('app.color.link');
    return $r('app.color.text');
  }

  static isClickable(type: SegmentType): boolean {
    return type === SegmentType.PAGE_REF || type === SegmentType.BLOCK_REF ||
           type === SegmentType.TAG_REF || type === SegmentType.PAGE_EMBED ||
           type === SegmentType.BLOCK_EMBED || type === SegmentType.IMAGE ||
           type === SegmentType.LINK;
  }

  static handleClick(type: SegmentType, value: string): void {
    if (type === SegmentType.PAGE_REF || type === SegmentType.PAGE_EMBED) {
      AppState.setCurrentPage(value);
    }
    if (type === SegmentType.BLOCK_REF || type === SegmentType.BLOCK_EMBED) {
      // Block 引用点击应跳转到 Block 所属页面，而不是把 UUID 当作页面名。
      const pageId = WorkspaceService.getInstance().getPageUuidForBlock(value);
      const page = pageId ? WorkspaceService.getInstance().getDataStore().getPage(pageId) : undefined;
      if (page) {
        AppState.setCurrentPage(page.originalName);
      }
    }
    if (type === SegmentType.TAG_REF) {
      // 标签不是页面，点击标签应打开搜索面板并按标签过滤。
      AppState.setSearchPanelOpen(true);
      AppStorage.setOrCreate('callaite_tagFilter', value);
    }
    if (type === SegmentType.LINK) {
      try {
        const ctx = FileService.getContext() as common.UIAbilityContext;
        if (ctx) {
          ctx.openLink(value).catch(() => {});
        }
      } catch (_e) {
        // 打开链接失败时忽略
      }
    }
  }
}
