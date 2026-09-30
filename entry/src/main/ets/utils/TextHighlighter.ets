/**
 * TextHighlighter — 「把一段文本按查询词切成匹配/非匹配段」的**单一实现**（U2.4 第 3 件 / W13）。
 *
 * ─── 为什么抽成独立文件，而不是各自复制一份 ───
 * 计划 §U2.4 第 3 件的原文是：
 *   「匹配块内的**文本级高亮**沿用 SearchPanel 的 splitHighlight 段渲染
 *     （把匹配块临时切到高亮样式）」
 * 即：FindInPage 的块内高亮与 `SearchPanel` 的结果行高亮**必须是同一套切分语义**，
 * 否则同一个查询词在两个地方会切出不同的段（大小写、重叠、边界）。故把算法上移到这里，
 * `SearchPanel.splitHighlight` 改为**委托本函数**（行为逐字不变），
 * `BlockView` 的命中块渲染直接调用本函数。
 *
 * ─── 边界语义（与迁移前 `SearchPanel.splitHighlight` 逐字一致，刻意不改）───
 *   · 空查询 / 空文本 ⇒ 单个 `isMatch=false` 段（原样返回，不抛错）；
 *   · 大小写不敏感（两侧都 `toLowerCase` 后 `indexOf`）；
 *   · **不重叠**扫描：命中后游标跳到命中串之后（"aa" 在 "aaa" 上只命中第 1 段）；
 *   · 长度按 `query.length` 截取（`toLowerCase` 不改变 BMP 字符长度）。
 */

/** 一段文本及其是否为命中片段。 */
export interface HighlightSegment {
  text: string;
  isMatch: boolean;
}

/**
 * 将文本按搜索词拆分为分段（匹配段 isMatch=true）。
 *
 * 迁移说明：本函数体原样来自 `SearchPanel.splitHighlight`（该方法现委托到此处），
 * 未做任何行为调整 —— W12 已设备验收的 Ctrl+F 结果行高亮语义因此保持逐字不变。
 */
export function splitHighlight(text: string, query: string): HighlightSegment[] {
  if (query === '' || text === '') {
    const whole: HighlightSegment = { text: text, isMatch: false };
    return [whole];
  }

  const lowerText = text.toLowerCase();
  const lowerQuery = query.toLowerCase();
  const segments: HighlightSegment[] = [];
  let idx = 0;

  while (idx < text.length) {
    const found = lowerText.indexOf(lowerQuery, idx);
    if (found === -1) {
      const tail: HighlightSegment = { text: text.substring(idx), isMatch: false };
      segments.push(tail);
      break;
    }
    if (found > idx) {
      const head: HighlightSegment = { text: text.substring(idx, found), isMatch: false };
      segments.push(head);
    }
    const hit: HighlightSegment = {
      text: text.substring(found, found + query.length),
      isMatch: true
    };
    segments.push(hit);
    idx = found + query.length;
  }

  return segments;
}

/**
 * 文本是否命中查询词（大小写不敏感）。
 * 空查询 / 空文本恒为 false —— 调用方据此决定「要不要走高亮渲染分支」，
 * 避免为一次空查询把每一行都切一遍段。
 */
export function containsQuery(text: string, query: string): boolean {
  if (query === '' || text === '') {
    return false;
  }
  return text.toLowerCase().indexOf(query.toLowerCase()) >= 0;
}
