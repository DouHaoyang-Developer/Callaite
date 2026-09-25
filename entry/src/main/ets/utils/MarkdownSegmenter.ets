/**
 * Markdown 语法分段器
 * 将 Markdown 文本解析为 {text, type} 段落，区分「语法符号」与「内容文字」
 * 用于实时阅览模式下的 RichEditor span 样式渲染
 */

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

    // 行内代码 `text`
    if (text.charAt(i) === '`') {
      const end = text.indexOf('`', i + 1);
      if (end > i) {
        result.push({ text: text.slice(i, end + 1), type: 'syntax' });
        i = end + 1;
        continue;
      }
      result.push({ text: '`', type: 'syntax' });
      i += 1;
      continue;
    }

    // Wiki 链接 [[target]] 或 [[target|display]]
    if (text.startsWith('[[')) {
      const closeIdx = text.indexOf(']]', 2);
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
    let chunk = '';
    const specials = '*`[!';
    while (i < text.length && !specials.includes(text.charAt(i))) {
      chunk += text.charAt(i);
      i++;
    }
    if (chunk) {
      result.push({ text: chunk, type: 'content' });
    }
  }

  return result;
}
