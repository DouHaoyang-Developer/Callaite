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
    // ★ A-2 修复①b：**连续普通文本只切一次**。
    //   原实现在两条分支里各推一个 `text.substring(...)` 段；兜底分支更是**每字符一次**
    //   `substring(pos, pos+1)`。当整段都是「无法成段的模式字符」（`!`×20000）时，
    //   那就是 20000 次子串切分 —— 若运行时的 `substring` 是整串拷贝而非引用切片，
    //   这本身就是 Θ(n²)（与 `StringCharAtStwCopy` 的「逐字符 + 拷贝」语义吻合）。
    //   实测（本窗口交付构建，20000 字 `!` 单块）：仅做修复①②③时系统仍报
    //   `THREAD_BLOCK_3S`；补上本条后同一输入不再触发（见 docs/S3-W3-A2停顿记录.md）。
    //   语义等价：产出段的**文本内容、类型、顺序**均不变，只是把相邻 TEXT 提前合并，
    //   与 `coalescePlainText` 的结果一致。
    let plainStart = -1;

    while (pos < text.length) {
      // 查找当前位置开始的匹配
      const match = ContentRenderer.tryMatchAt(text, pos);
      if (match) {
        if (plainStart >= 0) {
          segments.push({ text: text.substring(plainStart, pos), type: SegmentType.TEXT });
          plainStart = -1;
        }
        segments.push(match.segment);
        pos = pos + match.consumed;
      } else {
        // 累积纯文本直到下一个匹配开始
        let nextMatch = text.length;
        // ★ A-2 修复①：只取**第一个**候补下标，不再把全后缀的候补收集成数组。
        //   原实现（`findPatternStarts`）扫到文末并把每个候补下标压进数组，而调用点
        //   只读 `[0]` ⇒ 当文本里连续出现「无法成段的模式字符」时（`!!!!` / `****` /
        //   `[[[[` …），`tryMatchAt` 每次失败、`pos` 每次只前进 1，这次「扫到文末」
        //   被重复执行 ⇒ **Θ(n²) 时间 + Θ(n²) 分配**。
        //   实测（MatePad Pro 13 / debug）：4 KB ⇒ 单次 912 ms；8 KB ⇒ 3265 ms
        //   （翻倍 ×3.58 ≈ 4 ⇒ 二次方）。
        //   改成「只找第一个」后为 Θ(n)，**输出逐字节不变**（旧代码也只读 `[0]`）。
        const firstStart = ContentRenderer.findFirstPatternStart(text, pos);
        if (firstStart >= 0) {
          nextMatch = firstStart;
        }
        if (nextMatch > pos) {
          if (plainStart < 0) {
            plainStart = pos;
          }
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
          if (plainStart < 0) {
            plainStart = pos;
          }
          pos = pos + 1;
        }
      }
    }

    if (plainStart >= 0) {
      segments.push({ text: text.substring(plainStart, pos), type: SegmentType.TEXT });
    }

    return ContentRenderer.coalescePlainText(segments);
  }

  /**
   * 把**相邻的纯文本（TEXT）段**合并为一段。★ A-2 修复②：段数上界。
   *
   * 为什么必须做（实测）：`parse` 的兜底分支在「模式起始字符但无法成段」时**逐字符**
   * 前进，并**每字符各推一个 TEXT 段**。于是
   *   ① 段数与字符数同阶（4000 字 ⇒ 4000 段）；
   *   ② 下游 `BlockView.ContentSegments()` 是 `ForEach` 逐段建组件，
   *      实测 **≈0.54 ms/段**（8000 段 ⇒ 单次停顿里多出 ≈4.3 s）。
   * 合并后同一输入只剩 **1 段** ⇒ 下游成本与「行数」同阶，而不是与「字符数」同阶。
   *
   * **为什么是纯优化（零行为变更）**：
   *   - 只合并 `type === SegmentType.TEXT` 的相邻段；`RenderSegment` 对 TEXT 段
   *     走同一个 `Text(seg.text)` 分支，且 `isClickable(TEXT) === false`
   *     ⇒ 拆成 N 段与并成 1 段**渲染结果相同**（同一 Text 内相邻字符无额外间距）。
   *   - 非 TEXT 段一律原样保留、顺序不变 ⇒ 语法/链接/公式/表格等类型判定不受影响。
   *   - 合并后各段文本的**拼接逐字符等于原文本**（不引入、不丢失字符）。
   *   - 用 `join('')` 而不是逐次 `prev + seg.text`：后者本身就是 Θ(n²) 字符串拼接
   *     （本窗口已实测 `chunk += charAt(i)` 那条路的代价，故不再复制该形状）。
   */
  private static coalescePlainText(segments: ContentSegment[]): ContentSegment[] {
    if (segments.length < 2) {
      return segments;
    }
    const out: ContentSegment[] = [];
    let buf: string[] = [];
    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];
      if (seg.type === SegmentType.TEXT) {
        buf.push(seg.text);
      } else {
        if (buf.length > 0) {
          out.push({ text: buf.join(''), type: SegmentType.TEXT });
          buf = [];
        }
        out.push(seg);
      }
    }
    if (buf.length > 0) {
      out.push({ text: buf.join(''), type: SegmentType.TEXT });
    }
    return out;
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

  /**
   * 返回 `fromPos` 起**第一个**「模式起始字符」的下标；找不到返回 -1。
   *
   * ★ A-2 修复①：替换掉原先的 `findPatternStarts`（返回**全部**候补下标的数组）。
   *   唯一调用点只需要 `[0]`，数组其余部分是纯浪费；而当候补字符连续且都无法成段时，
   *   那个「扫到文末」会被每个字符重复一次 ⇒ Θ(n²)。改为提前返回 ⇒ Θ(n)。
   *   判据等价：`findPatternStarts(...).length > 0` ⇔ `findFirstPatternStart(...) >= 0`，
   *   且 `candidates[0] === findFirstPatternStart(...)` ⇒ **输出逐字节不变**。
   */
  private static findFirstPatternStart(text: string, fromPos: number): number {
    for (let i = fromPos; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === '[' || ch === '(' || ch === '*' || ch === '=' ||
          ch === '~' || ch === '`' || ch === '#' || ch === '!' ||
          ch === '>' || ch === '$') {
        return i;
      }
    }
    return -1;
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
