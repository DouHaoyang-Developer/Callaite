import { BlockData } from '../models/Block';
import { PageData } from '../models/Page';
import { BlockMarker, BlockPriority, BLOCK_PREFIX, INDENT_PREFIX } from '../models/Constants';

/**
 * MarkdownExporter — Block 树 → Logseq .md 文件导出器。
 *
 * 对应 Logseq deps/graph-parser/exporter.cljs (3134行)。
 * 将内存中的 Page + Block 树序列化为 Logseq 兼容的 Markdown 文件格式。
 */
export class MarkdownExporter {

  /**
   * 将 Page 和 Blocks 导出为完整的 .md 文件内容。
   *
   * @param page 页面数据
   * @param blocks 页面所有 Block（由调用方保证已经按遍历顺序排列）
   * @returns 完整的 .md 文件字符串
   */
  static export(page: PageData, blocks: BlockData[]): string {
    const lines: string[] = [];

    // ─── 第一步：输出页面属性（frontmatter 格式） ───
    const hasProperties = page.properties.size() > 0 || page.aliases.length > 0;
    if (hasProperties) {
      lines.push('---');
      page.properties.forEach((key: string, value: string) => {
        // alias/aliases 统一从 page.aliases 输出，避免重复写入
        if (key !== 'alias' && key !== 'aliases') {
          lines.push(key + ':: ' + value);
        }
      });
      if (page.aliases.length > 0) {
        lines.push('alias:: ' + page.aliases.join(', '));
      }
      lines.push('---');
      lines.push('');
    }

    // ─── 第二步：按层级输出 Block ───
    // blocks 已经按 leftId 链排序，每个 block 知道自己的 level
    const topLevelBlocks = MarkdownExporter.filterTopLevel(blocks, page.uuid);
    for (let i = 0; i < topLevelBlocks.length; i++) {
      MarkdownExporter.exportBlock(blocks, topLevelBlocks[i], lines);
    }

    return lines.join('\n');
  }

  /**
   * 递归输出单个 Block（含属性行和子 Block）。
   */
  private static exportBlock(allBlocks: BlockData[], block: BlockData, lines: string[]): void {
    // 计算缩进前缀
    const indent = MarkdownExporter.buildIndent(block.level);
    const prefix = indent + BLOCK_PREFIX;

    // 组装 Block 头部
    let header = '';
    if (block.marker !== BlockMarker.NONE) {
      header = header + block.marker + ' ';
    }
    if (block.priority !== BlockPriority.NONE) {
      header = header + '[#' + block.priority + '] ';
    }

    // 输出第一行：前缀 + marker + priority + content（取第一行）
    const contentLines = block.content.split('\n');
    const firstLine = contentLines[0];
    lines.push(prefix + header + firstLine);

    // 输出续行（多行内容）
    const continuationIndent = indent + INDENT_PREFIX;
    for (let i = 1; i < contentLines.length; i++) {
      if (contentLines[i].trim() !== '') {
        lines.push(continuationIndent + contentLines[i]);
      }
    }

    // 输出 Block 属性
    block.properties.forEach((key: string, value: string) => {
      lines.push(continuationIndent + key + ':: ' + value);
    });

    // 输出 scheduled
    if (block.scheduled !== '') {
      lines.push(continuationIndent + 'SCHEDULED: <' + block.scheduled + '>');
    }

    // 输出 deadline
    if (block.deadline !== '') {
      lines.push(continuationIndent + 'DEADLINE: <' + block.deadline + '>');
    }

    // 递归输出子 Block
    const children = MarkdownExporter.getChildrenInOrder(allBlocks, block.uuid);
    for (let i = 0; i < children.length; i++) {
      MarkdownExporter.exportBlock(allBlocks, children[i], lines);
    }
  }

  /**
   * 获取所有顶层 Block（parentId = pageId），按 leftId 链排序。
   */
  private static filterTopLevel(blocks: BlockData[], pageId: string): BlockData[] {
    const topLevel: BlockData[] = [];
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].parentId === pageId) {
        topLevel.push(blocks[i]);
      }
    }
    return MarkdownExporter.sortByLeftChain(topLevel);
  }

  /**
   * 按 leftId 链排序，**保证不丢块**。
   *
   * 早期实现用 `Map<leftId, block>` 做桶：当多个兄弟的 leftId 相同（典型场景是
   * leftId 未被赋值，全为 ''）时，后写入者会覆盖先写入者，链走完后剩余项已不在
   * Map 中，导致**同层只导出最后一个块**——静默数据丢失。现改为在候选池上按
   * uuid 标记消费：链能走多远走多远，未能入链的一律按原顺序追加，绝不丢弃。
   */
  private static sortByLeftChain(items: BlockData[]): BlockData[] {
    const sorted: BlockData[] = [];
    const consumed = new Set<string>();
    let cursor = '';
    let progressed = true;
    while (progressed) {
      progressed = false;
      for (let i = 0; i < items.length; i++) {
        const b = items[i];
        if (!consumed.has(b.uuid) && b.leftId === cursor) {
          sorted.push(b);
          consumed.add(b.uuid);
          cursor = b.uuid;
          progressed = true;
          break;
        }
      }
    }
    // 兜底：leftId 链破损（空值/重复/悬空）的块按原顺序补齐
    for (let i = 0; i < items.length; i++) {
      if (!consumed.has(items[i].uuid)) {
        sorted.push(items[i]);
      }
    }
    return sorted;
  }

  /**
   * 获取某个 Block 的子 Block（已排序）。
   */
  private static getChildrenInOrder(blocks: BlockData[], parentUuid: string): BlockData[] {
    const children: BlockData[] = [];
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].parentId === parentUuid) {
        children.push(blocks[i]);
      }
    }
    return MarkdownExporter.sortByLeftChain(children);
  }

  /**
   * 构建缩进字符串。
   */
  private static buildIndent(level: number): string {
    let result = '';
    for (let i = 0; i < level; i++) {
      result = result + INDENT_PREFIX;
    }
    return result;
  }
}
