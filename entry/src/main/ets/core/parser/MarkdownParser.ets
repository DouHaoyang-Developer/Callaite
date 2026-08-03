import { BlockData, createBlockData } from '../models/Block';
import { PageData, createPageData } from '../models/Page';
import { PropertyBag } from '../models/Property';
import { UUID } from '../../utils/UUID';
import {
  BlockMarker,
  BlockPriority,
  PROPERTY_REGEX,
  MARKER_REGEX,
  PRIORITY_REGEX,
  SCHEDULED_REGEX,
  DEADLINE_REGEX,
  BLOCK_PREFIX
} from '../models/Constants';

/**
 * MarkdownParser — Logseq .md 文件 → Block 树的解析器。
 *
 * 对应 Logseq deps/graph-parser/block.cljs (897行)。
 *
 * 解析流程：
 *  1. 按行分割文本
 *  2. 提取页面级元数据（文件头部的 key:: value 或 frontmatter）
 *  3. 逐行解析 Block（识别缩进层级、任务标记、优先级、行内属性）
 *  4. 处理多行 Block 内容（续行）
 *  5. 提取内联引用（[[page]], ((uuid)), #tag）
 */
export class MarkdownParser {

  /**
   * 解析整个 .md 文件内容，返回 PageData + BlockData 数组。
   *
   * @param rawText 文件的原始文本内容
   * @param fileName .md 文件名（不含路径和扩展名），作为页面名
   * @param filePath .md 文件的完整相对路径
   * @returns { page: PageData, blocks: BlockData[] }
   */
  static parse(rawText: string, fileName: string, filePath: string): ParseResult {
    const pageUuid = UUID.generate();
    const lines = rawText.split('\n');

    // ─── 第一步：分离页面元数据行与 Block 行 ───
    let metadataEndIndex = 0;
    let hasFrontmatter = false;

    if (lines.length > 0 && lines[0].trim() === '---') {
      // YAML frontmatter 格式
      hasFrontmatter = true;
      for (let i = 1; i < lines.length; i++) {
        if (lines[i].trim() === '---') {
          metadataEndIndex = i + 1;
          break;
        }
      }
    } else {
      // 无 frontmatter：行首第一个 -  之前的内容都是页面元数据
      for (let i = 0; i < lines.length; i++) {
        const trimmed = lines[i].trim();
        if (trimmed.startsWith(BLOCK_PREFIX)) {
          metadataEndIndex = i;
          break;
        }
        metadataEndIndex = i + 1; // 全部读完也没有 Block 的情况
      }
    }

    // ─── 第二步：解析页面属性 ───
    const pageProperties = new PropertyBag();
    const pageName = fileName;
    let pageTitle = fileName;
    const aliases: string[] = [];

    for (let i = hasFrontmatter ? 1 : 0; i < metadataEndIndex; i++) {
      const line = lines[i];
      if (line === undefined) {
        continue;
      }
      const trimmed = line.trim();
      if (trimmed === '' || trimmed === '---') {
        continue;
      }

      const propMatch = PROPERTY_REGEX.exec(trimmed);
      if (propMatch) {
        const key = propMatch[1];
        const value = propMatch[2];
        pageProperties.set(key, value);

        if (key === 'title') {
          pageTitle = value;
        }
        if (key === 'alias' || key === 'aliases') {
          const parts = MarkdownParser.splitCommaSeparated(value);
          for (let j = 0; j < parts.length; j++) {
            aliases.push(parts[j]);
          }
        }
      }
    }

    // ─── 第三步：创建 Page ───
    const page = createPageData(pageUuid, pageName, pageTitle);
    page.filePath = filePath;
    page.properties = pageProperties;
    page.aliases = aliases;

    // 从 fileName 推断 journalDay
    if (MarkdownParser.isJournalFileName(fileName)) {
      page.journalDay = fileName; // yyyy-MM-dd
    }

    // 标签聚合（后面填充）

    // ─── 第四步：逐行解析 Block ───
    const blocks: BlockData[] = [];
    const blockStack: BlockData[] = []; // 用于追踪父 Block 的栈
    let i = metadataEndIndex;

    while (i < lines.length) {
      const line = lines[i];
      if (line === undefined || line.trim() === '') {
        i++;
        continue;
      }

      // 计算缩进层级
      const indentResult = MarkdownParser.countIndent(line);
      if (!indentResult.isBlock) {
        i++;
        continue;
      }

      const level = indentResult.level;
      const stripped = line.substring(indentResult.contentStart);

      // 提取 marker
      let marker: string = BlockMarker.NONE;
      let afterMarker = stripped;
      const markerMatch = MARKER_REGEX.exec(stripped);
      if (markerMatch) {
        marker = markerMatch[1];
        afterMarker = stripped.substring(markerMatch[0].length);
      }

      // 提取 priority
      let priority: string = BlockPriority.NONE;
      let afterPriority = afterMarker;
      const priorityMatch = PRIORITY_REGEX.exec(afterMarker);
      if (priorityMatch) {
        priority = priorityMatch[1];
        afterPriority = afterMarker.substring(priorityMatch[0].length);
      }

      let content = afterPriority.trim();

      // 收集多行内容
      const subLines: string[] = [];
      i++;
      while (i < lines.length) {
        const nextLine = lines[i];
        if (nextLine === undefined) {
          break;
        }
        const nextIndent = MarkdownParser.countIndent(nextLine);
        if (nextIndent.isBlock && nextIndent.level <= level) {
          // 新的同级或上级 Block，停止收集
          break;
        }
        if (nextIndent.isBlock) {
          // 更深层的 Block，停止收集（它将成为子 Block）
          break;
        }
        if (nextLine.trim() !== '') {
          subLines.push(nextLine.trim());
        }
        i++;
      }

      // 合并子行内容
      if (subLines.length > 0) {
        content = content + '\n' + subLines.join('\n');
      }

      // ─── 第五步：处理行内属性与引用 ───
      // 解析子行中的属性
      const blockProperties = new PropertyBag();
      let scheduled = '';
      let deadline = '';

      const contentLines = content.split('\n');
      const cleanContentLines: string[] = [];

      for (let li = 0; li < contentLines.length; li++) {
        const cl = contentLines[li];
        const propMatch = PROPERTY_REGEX.exec(cl);
        if (propMatch && li > 0) {
          // 非首行的 key:: value 是 Block 属性
          blockProperties.set(propMatch[1], propMatch[2]);
        } else {
          // 检查 scheduled/deadline
          const schedMatch = SCHEDULED_REGEX.exec(cl);
          if (schedMatch) {
            scheduled = schedMatch[1];
          } else {
            const deadMatch = DEADLINE_REGEX.exec(cl);
            if (deadMatch) {
              deadline = deadMatch[1];
            } else {
              cleanContentLines.push(cl);
            }
          }
        }
      }

      const finalContent = cleanContentLines.join('\n');

      // 提取引用和标签
      const refs = MarkdownParser.extractPageRefs(finalContent);
      const blockRefs = MarkdownParser.extractBlockRefs(finalContent);
      const tags = MarkdownParser.extractTags(finalContent);

      // ─── 第六步：构建 Block 并维护父子关系 ───
      // 确定 parentId
      let parentId = pageUuid;
      if (level > 0 && blockStack.length >= level) {
        // 向上找 level-1 的 block 作为 parent
        const parentBlock = blockStack[level - 1];
        if (parentBlock) {
          parentId = parentBlock.uuid;
        }
      }

      // 确定 leftId（同级的最后一个 Block）
      let leftId = '';
      for (let bi = blocks.length - 1; bi >= 0; bi--) {
        if (blocks[bi].parentId === parentId && blocks[bi].level === level) {
          leftId = blocks[bi].uuid;
          break;
        }
      }

      const uuid = UUID.generate();
      const block = createBlockData(uuid, pageUuid, parentId, level);
      block.content = finalContent;
      block.marker = marker;
      block.priority = priority;
      block.scheduled = scheduled;
      block.deadline = deadline;
      block.properties = blockProperties;
      block.refs = refs;
      block.blockRefs = blockRefs;
      block.tags = tags;

      blocks.push(block);

      // 维护栈
      blockStack[level] = block;
      // 截断更深层的栈（因为新 block 变浅了）
      blockStack.length = level + 1;

      // 聚合标签到页面
      for (let ti = 0; ti < tags.length; ti++) {
        const alreadyHas = page.tags.findIndex((t) => t === tags[ti]) !== -1;
        if (!alreadyHas) {
          page.tags.push(tags[ti]);
        }
      }
    }

    // 从页面元数据标签聚合
    const pageTagsRaw = pageProperties.get('tags');
    if (pageTagsRaw !== '') {
      const parts = MarkdownParser.splitCommaSeparated(pageTagsRaw);
      for (let pi = 0; pi < parts.length; pi++) {
        const alreadyHas = page.tags.findIndex((t) => t === parts[pi]) !== -1;
        if (!alreadyHas) {
          page.tags.push(parts[pi]);
        }
      }
    }

    return { page: page, blocks: blocks };
  }

  // ─── 辅助方法 ───

  /**
   * 计算一行的缩进层级。
   * @returns { level, isBlock, contentStart }
   */
  static countIndent(line: string): IndentResult {
    let spaces = 0;
    for (let i = 0; i < line.length; i++) {
      if (line.charAt(i) === ' ') {
        spaces++;
      } else {
        break;
      }
    }

    const level = Math.floor(spaces / 2);
    const afterIndent = line.substring(spaces);

    if (afterIndent.startsWith(BLOCK_PREFIX)) {
      return {
        level: level,
        isBlock: true,
        contentStart: spaces + 2 // skip "- "
      };
    }

    return {
      level: level,
      isBlock: false,
      contentStart: spaces
    };
  }

  /**
   * 判断文件名是否为日志页格式（yyyy-MM-dd）。
   */
  static isJournalFileName(name: string): boolean {
    if (name.length !== 10) {
      return false;
    }
    if (name.charAt(4) !== '-' || name.charAt(7) !== '-') {
      return false;
    }
    for (let i = 0; i < 10; i++) {
      if (i === 4 || i === 7) {
        continue;
      }
      const c = name.charAt(i);
      if (c < '0' || c > '9') {
        return false;
      }
    }
    return true;
  }

  /**
   * 提取 [[page]] 页面引用。
   */
  static extractPageRefs(text: string): string[] {
    const refs: string[] = [];
    const regex = /\[\[([^\]]+)\]\]/g;
    let match = regex.exec(text);
    while (match) {
      const ref = match[1];
      // 排除 ![[embed]] 嵌入
      if (!ref.startsWith('!') && refs.findIndex((r) => r === ref) === -1) {
        refs.push(ref);
      }
      match = regex.exec(text);
    }
    return refs;
  }

  /**
   * 提取 ((uuid)) Block 引用。
   */
  static extractBlockRefs(text: string): string[] {
    const refs: string[] = [];
    const regex = /\(\(([a-f0-9\-]{36})\)\)/g;
    let match = regex.exec(text);
    while (match) {
      const ref = match[1];
      if (refs.findIndex((r) => r === ref) === -1) {
        refs.push(ref);
      }
      match = regex.exec(text);
    }
    return refs;
  }

  /**
   * 提取 #tag 标签。
   */
  static extractTags(text: string): string[] {
    const tags: string[] = [];
    const regex = /#([\w一-鿿\-]+)/g;
    let match = regex.exec(text);
    while (match) {
      const tag = match[1];
      if (tags.findIndex((t) => t === tag) === -1) {
        tags.push(tag);
      }
      match = regex.exec(text);
    }
    return tags;
  }

  /**
   * 分割逗号分隔的字符串，用于 tags/aliases 等属性。
   */
  static splitCommaSeparated(raw: string): string[] {
    const parts = raw.split(',');
    const result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const trimmed = parts[i].trim();
      if (trimmed !== '') {
        result.push(trimmed);
      }
    }
    return result;
  }
}

// ─── 类型 ───

export interface IndentResult {
  level: number;
  isBlock: boolean;
  contentStart: number;
}

export interface ParseResult {
  page: PageData;
  blocks: BlockData[];
}
