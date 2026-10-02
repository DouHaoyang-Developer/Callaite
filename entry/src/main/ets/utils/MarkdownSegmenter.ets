/**
 * Markdown 语法分段器
 * 将 Markdown 文本解析为 {text, type} 段落，区分「语法符号」与「内容文字」
 * 用于实时阅览模式下的 RichEditor span 样式渲染
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

/** 无条件前进兜底的日志域/标签（仅观测用，不参与任何判定逻辑） */
const MARKDOWN_SEGMENTER_DOMAIN = 0x0002;
const MARKDOWN_SEGMENTER_TAG = 'MarkdownSegmenter';

export interface MarkdownSegment {
  text: string;
  type: 'syntax' | 'content';
}

/**
 * 将 Markdown 文本解析为段落数组
 * 语法符号标记为 'syntax'，内容文字标记为 'content'
 */
export function parseMarkdownSegments(text: string): MarkdownSegment[] {
  if (!text) {
    return [{ text: '', type: 'content' }];
  }

  const segments: MarkdownSegment[] = [];
  const lines = text.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (i > 0) {
      segments.push({ text: '\n', type: 'syntax' });
    }

    // 空行
    if (line.trim() === '') {
      segments.push({ text: line, type: 'content' });
      continue;
    }

    // 标题: # ~ ######
    const headingMatch = line.match(/^(#{1,6})\s/);
    if (headingMatch) {
      segments.push({ text: headingMatch[0], type: 'syntax' });
      const content = line.slice(headingMatch[0].length);
      if (content) {
        segments.push(...parseInlineMarkdown(content));
      }
      continue;
    }

    // Callout 块: > [!note] / > [!warning] 等
    const calloutMatch = line.match(/^>\s*\[!(\w+)\]\s?(.*)/);
    if (calloutMatch) {
      const prefix = calloutMatch[0].substring(0, calloutMatch[0].length - (calloutMatch[2]?.length || 0));
      segments.push({ text: prefix, type: 'syntax' });
      if (calloutMatch[2]) {
        segments.push(...parseInlineMarkdown(calloutMatch[2]));
      }
      continue;
    }

    // 引用块: >
    const quoteMatch = line.match(/^>\s?/);
    if (quoteMatch) {
      segments.push({ text: quoteMatch[0], type: 'syntax' });
      const content = line.slice(quoteMatch[0].length);
      if (content) {
        segments.push(...parseInlineMarkdown(content));
      }
      continue;
    }

    // 无序列表: - or * or +
    const ulMatch = line.match(/^[\-\*\+]\s/);
    if (ulMatch) {
      segments.push({ text: ulMatch[0], type: 'syntax' });
      const content = line.slice(ulMatch[0].length);
      if (content) {
        segments.push(...parseInlineMarkdown(content));
      }
      continue;
    }

    // 有序列表: 1.
    const olMatch = line.match(/^\d+\.\s/);
    if (olMatch) {
      segments.push({ text: olMatch[0], type: 'syntax' });
      const content = line.slice(olMatch[0].length);
      if (content) {
        segments.push(...parseInlineMarkdown(content));
      }
      continue;
    }

    // LaTeX 块级公式 $$ ... $$
    if (line.trim().startsWith('$$') && line.trim().endsWith('$$') && line.trim().length > 4) {
      segments.push({ text: '$$', type: 'syntax' });
      const inner = line.trim().slice(2, -2);
      if (inner) {
        segments.push({ text: inner, type: 'syntax' });
      }
      segments.push({ text: '$$', type: 'syntax' });
      continue;
    }

    // 分割线: --- *** ___
    if (/^(---|\*\*\*|___)\s*$/.test(line.trim())) {
      segments.push({ text: line, type: 'syntax' });
      continue;
    }

    // 默认：行内解析
    segments.push(...parseInlineMarkdown(line));
  }

  return segments;
}

/**
 * 解析行内 Markdown 语法
 */
function parseInlineMarkdown(text: string): MarkdownSegment[] {
  if (!text) {
    return [];
  }

  const result: MarkdownSegment[] = [];
  let i = 0;
  // 无条件前进兜底的水位线：见循环末尾的守卫
  let guardMark = -1;
  let guardFires = 0;

  while (i < text.length) {
    // 行内 LaTeX $...$（单 $ 符）
    if (text.charAt(i) === '$' && !text.startsWith('$$', i)) {
      const end = text.indexOf('$', i + 1);
      if (end > i + 1) {
        result.push({ text: text.slice(i, end + 1), type: 'syntax' });
        i = end + 1;
        continue;
      }
      result.push({ text: '$', type: 'syntax' });
      i += 1;
      continue;
    }

    // 粗斜体 ***text***
    if (text.startsWith('***', i)) {
      result.push({ text: '***', type: 'syntax' });
      const end = text.indexOf('***', i + 3);
      if (end > i + 3) {
        result.push(...parseInlineMarkdown(text.slice(i + 3, end)));
        result.push({ text: '***', type: 'syntax' });
        i = end + 3;
      } else {
        i += 3;
      }
      continue;
    }

    // 粗体 **text**
    if (text.startsWith('**', i)) {
      result.push({ text: '**', type: 'syntax' });
      const end = text.indexOf('**', i + 2);
      if (end > i + 2) {
        result.push(...parseInlineMarkdown(text.slice(i + 2, end)));
        result.push({ text: '**', type: 'syntax' });
        i = end + 2;
      } else {
        i += 2;
      }
      continue;
    }

    // 斜体 *text*（不是 **）
    if (text.charAt(i) === '*' && !text.startsWith('**', i)) {
      result.push({ text: '*', type: 'syntax' });
      const end = text.indexOf('*', i + 1);
      if (end > i + 1) {
        result.push(...parseInlineMarkdown(text.slice(i + 1, end)));
        result.push({ text: '*', type: 'syntax' });
        i = end + 1;
      } else {
        i += 1;
      }
      continue;
    }

    // 高亮 ==text==
    // 与粗体同构：标记段 syntax、内容段 content —— 编辑态显示 `==`、渲染态给内容加底色。
    if (text.startsWith('==', i)) {
      result.push({ text: '==', type: 'syntax' });
      const end = text.indexOf('==', i + 2);
      if (end > i + 2) {
        result.push(...parseInlineMarkdown(text.slice(i + 2, end)));
        result.push({ text: '==', type: 'syntax' });
        i = end + 2;
      } else {
        // 未闭合：`==` 退回普通内容，避免「打了一半的高亮标记被当作语法隐藏」
        result.push({ text: '=', type: 'content' });
        i += 1;
      }
      continue;
    }

    // 行内代码 `text`
    // ⚠️ 必须拆成「反引号 / 内容 / 反引号」三段。原实现把**整段（含内容）**标为
    //    syntax，而 LivePreview 对语法段的规则是「光标不在其中则隐藏」——于是
    //    `code` 连内容一起变成不可见（实测：live 模式下单词 code 从页面上消失）。
    //    内容段必须是 content，才能在没有光标时以「代码样式」渲染。
    if (text.charAt(i) === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i) {
        result.push({ text: '`', type: 'syntax' });
        const inner = text.slice(i + 1, end);
        if (inner) {
          result.push(...parseInlineMarkdown(inner));
        }
        result.push({ text: '`', type: 'syntax' });
        i = end + 1;
        continue;
      }
      result.push({ text: '`', type: 'syntax' });
      i += 1;
      continue;
    }

    // Wiki 链接 [[target]] 或 [[target|display]]
    // ⚠️⚠️ W8 修复（P0 `W7-1`）：**判定必须与游标对齐**，否则死循环 ⇒ OOM 崩应用 ✗✗
    //
    // 原实现是 `startsWith('[[')`（**没有 position 实参 = 只看串首**）+
    // `indexOf(']]', 2)` + `slice(2, closeIdx)` —— **三个实参全部写死成「串首」**，
    // 而 `i` 是游标 ✗。于是「文本以 `[[` 开头、且首个 `]]` 之后还有字符」
    // （`[[W]]Y]]Z` · `[[链接]] ` —— **尾随一个空格也算**）会走到
    // `i = closeIdx + 2` —— 一个**已经走过**的位置 ⇒ 下一轮该分支**仍成立**
    // ⇒ `i` 永不前进、每轮 push 3 段 ⇒ `result` 无界增长 ⇒
    // `Heap::AllocateHugeObject` 79 MB 失败 ⇒ `OutOfMemoryError`、进程被杀
    // （设备实测 **14 s 确定性复现**；崩溃栈 `parseInlineMarkdown` ← `parseMarkdownSegments:110`
    //  ← `LivePreviewHelper.buildSpansInternal:278` ← `BlockEditor.rebuildSpans:221`）。
    // 这是本函数**同族第 2 例**：第 1 例是「孤立 `!` 死循环」（见本函数末尾的兜底注释，
    // 由 `d4d1b5f` 修掉）。
    //
    // ── 修法：只增加一条「不许把游标写回去」的守卫（零漂移）──
    // `startsWith`（无实参）是**全局属性**、与游标无关 ⇒ 它恒等价于
    // `i === 0 && startsWith('[[')`。所以本分支**只可能在 i 落后于首个 `]]` 时**发生
    // 「写回过去」，判据就是 `closeIdx + 2 <= i`。
    //
    // ⚠️ **刻意不把判定整体改成 `startsWith('[[', i)` + `indexOf(']]', i + 2)`** ✗ ——
    // 那会把**串中间的 wikilink 也纳入语法识别**，是**语义扩展**而不是修 bug：
    // 受控差分实测（`%TEMP%\w8\diff_test.js`，4112 条语料）它让 **64 条**原本正常终止的
    // 输入**分段结果改变**（`未命名页的 [[2026-09-25]] 引用` 由「1 段 content」变成「5 段」，
    // `b[[a]]` / `![[a]]` 同理）⇒ 既有语义被一并改掉 ✗（本窗口的硬要求是**零漂移**）。
    // 本守卫对**所有修复前能正常终止的输入**是**恒假**的 ⇒ 分段结果**逐字节不变** ✓
    // （60112 条语料差分：drift = 0）。
    // > 串中间 wikilink 在编辑态不被识别为语法，**是既有行为，本次刻意不动** ✗；
    // > 若要改，属**产品/语义决策**（需与 `ContentRenderer` 对齐 + 独立验收），另开窗口 ✓。
    //
    // ⚠️ 与「未闭合」不是一回事：未闭合时 `closeIdx === -1`，**没有**越界风险，
    // 那时仍必须走本分支的「未闭合 ⇒ 逐字符当内容」通道（改了就是漂移 ✗）。
    const wikiClose: number = text.startsWith('[[') ? text.indexOf(']]', 2) : -1;
    const isWikiTail: boolean = wikiClose !== -1 && wikiClose + 2 <= i;
    if (!isWikiTail && text.startsWith('[[')) {
      const closeIdx = wikiClose;
      if (closeIdx !== -1) {
        result.push({ text: '[[', type: 'syntax' });
        const inner = text.slice(2, closeIdx);
        if (inner) {
          result.push(...parseInlineMarkdown(inner));
        }
        result.push({ text: ']]', type: 'syntax' });
        i = closeIdx + 2;
        continue;
      }
      // 未闭合的 [[ 视为内容
      result.push({ text: text.charAt(i), type: 'content' });
      i += 1;
      continue;
    }

    // 链接 [text](url)
    if (text.charAt(i) === '[') {
      const closeBracket = text.indexOf('](', i);
      const closeParen = closeBracket > i ? text.indexOf(')', closeBracket + 2) : -1;
      if (closeParen > closeBracket) {
        result.push({ text: '[', type: 'syntax' });
        result.push(...parseInlineMarkdown(text.slice(i + 1, closeBracket)));
        result.push({ text: text.slice(closeBracket, closeParen + 1), type: 'syntax' });
        i = closeParen + 1;
        continue;
      }
      result.push({ text: text.charAt(i), type: 'content' });
      i += 1;
      continue;
    }

    // 图片 ![text](url)
    if (text.charAt(i) === '!' && i + 1 < text.length && text.charAt(i + 1) === '[') {
      const closeBracket = text.indexOf('](', i + 1);
      const closeParen = closeBracket > i ? text.indexOf(')', closeBracket + 2) : -1;
      if (closeParen > closeBracket) {
        result.push({ text: '![', type: 'syntax' });
        result.push(...parseInlineMarkdown(text.slice(i + 2, closeBracket)));
        result.push({ text: text.slice(closeBracket, closeParen + 1), type: 'syntax' });
        i = closeParen + 1;
        continue;
      }
      result.push({ text: text.charAt(i), type: 'content' });
      i += 1;
      continue;
    }

    // 普通字符
    // specials 必须包含 '='（高亮标记起始符），否则 `==x==` 会被整体当作普通文本吞掉。
    let chunk = '';
    const specials = '*`[!=';
    while (i < text.length && !specials.includes(text.charAt(i))) {
      chunk += text.charAt(i);
      i++;
    }
    if (chunk) {
      result.push({ text: chunk, type: 'content' });
      continue;
    }
    // ⚠️ 兜底推进：能走到这里说明 charAt(i) 是 specials 之一，但上面没有任何分支接手
    //    （典型：孤立的 `!`（后面不接 `[`，例如正文写 "Hello!"）、未成对的单个 `=`）。
    //    此时 chunk 为空且 i 不前进 → 外层 while 永远不退出 → **整段解析死循环**
    //    （LivePreviewHelper.buildSpans 会挂死主线程）。必须显式消费一个字符。
    if (i < text.length) {
      result.push({ text: text.charAt(i), type: 'content' });
      i += 1;
    }

    // ═══ 无条件前进兜底（W8 新增；改的是「类」，不只是上面那一个 bug）═══
    // 本函数是**游标式 while**：终止性完全依赖「每次迭代 `i` 严格增长」这条不变量 ✗。
    // 而仓里已经出现过**两次**它被打破（`d4d1b5f` 的孤立 `!`、W8 的串首 `[[`），
    // 两次都表现为「主线程挂死 / OOM」这种**在设备上极难定位**的形态。
    // 逐个分支去证明「它一定前进」在当下成立，但挡不住**下一次**加分支的人 ✗。
    // ⇒ 这里把它降级成一个**运行时不变量**：迭代末比较水位，没前进就强制 +1
    //    并打一条 WARN（可 grep，兼作「还有没有第三个不推进的分支」的活体探针）✓。
    // 只有 `continue` 的分支会跳过这一句 —— 而它们的 `continue` 之前都写了 `i =`/`i +=` ✓。
    if (i <= guardMark) {
      guardFires += 1;
      hilog.warn(MARKDOWN_SEGMENTER_DOMAIN, MARKDOWN_SEGMENTER_TAG,
        'parseInlineMarkdown cursor stalled: forced advance i=%{public}d len=%{public}d fires=%{public}d',
        i, text.length, guardFires);
      i = guardMark + 1;
    }
    guardMark = i;
  }

  return coalesceContentSegments(result);
}

/**
 * 把**相邻的 content 段**合并为一段。★ A-2 修复③：段数上界（RichEditor/span 侧）。
 *
 * 背景（实测）：`LivePreviewHelper.buildSpansInternal` 对**每个段**各调一次
 * `controller.addTextSpan()`，而 `parseInlineMarkdown` 在遇到「无法成段的模式字符」时
 * **逐字符**推 content 段（`!` `=` `[` … 的兜底分支）⇒ 段数与字符数同阶。
 * 实测（MatePad Pro 13 / debug，整页编辑器 live 模式）：4000 个 `!` ⇒ 4000 段
 * ⇒ **单次 `buildSpans` 5130 ms**（≈1.28 ms/次 addTextSpan），主线程单次停顿 5595 ms。
 * 合并后同一输入只剩 1 段。
 *
 * **为什么是纯优化（零行为变更）**：
 *   - 只合并 `type === 'content'` 的相邻段。`buildSpansInternal` / `buildSourceSpans`
 *     的状态机只由 **syntax 段的确切文本**（`'**'` / `` '`' `` / `'=='` / `'\n'` /
 *     行首正则）驱动；content 段**不参与任何状态迁移**，只被原样 `addTextSpan`。
 *     因此两段相邻 content 之间**不存在状态差**（样式由 inBold/inInlineCode/
 *     inHighlight/行上下文决定，这三者只被 syntax 段与换行翻转）⇒ 并成一段后
 *     样式与文本**逐字符一致**。
 *   - syntax 段一律**不动**：`'**'` 与 `'***'` 合并会破坏 `seg.text === '**'` 的
 *     翻转判据，故**不合并 syntax**（这是本函数只处理 content 的原因）。
 *   - 用 `join('')` 而非逐次 `+=`：避免复制 Θ(n²) 拼接形状。
 */
function coalesceContentSegments(segments: MarkdownSegment[]): MarkdownSegment[] {
  if (segments.length < 2) {
    return segments;
  }
  const out: MarkdownSegment[] = [];
  let buf: string[] = [];
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    if (seg.type === 'content') {
      buf.push(seg.text);
    } else {
      if (buf.length > 0) {
        out.push({ text: buf.join(''), type: 'content' });
        buf = [];
      }
      out.push(seg);
    }
  }
  if (buf.length > 0) {
    out.push({ text: buf.join(''), type: 'content' });
  }
  return out;
}
