import { fileIo as fs } from '@kit.CoreFileKit';
import { WorkspaceService } from './WorkspaceService';
import { BlockMarker } from '../core/models/Constants';
import { InsertBlockOp, NewPageOp } from '../core/engine/OutlinerOps';

/**
 * 导入结果。
 */
export interface ImportResult {
  pageName: string;
  blockCount: number;
  success: boolean;
  error: string;
}

/**
 * 解析后的临时 Block 结构。
 */
interface ParsedBlock {
  content: string;
  level: number;
  marker: string;
}

/**
 * ImportService — 导入外部 .md 文件，拆分为 Block。
 *
 * 解析逻辑：
 *  - 按行拆分
 *  - 识别 `- ` / `* ` 前缀作为 Block
 *  - 识别缩进（2 空格或 Tab）作为子 Block 层级
 *  - 识别 `# ` 标题作为顶层 Block
 *  - 识别 `- [ ]` / `- [x]` 作为 TODO Block
 *  - 识别 `---` 作为分隔符
 *  - 识别 ``` 代码块（合并为单个 Block）
 */
export class ImportService {

  /**
   * 读取 .md 文件，解析为 Block 列表（不入库）。
   */
  static importMarkdownFile(filePath: string): ImportResult {
    const pageName = ImportService.derivePageName(filePath);

    let content = '';
    try {
      content = fs.readTextSync(filePath);
    } catch (e) {
      const msg = (e instanceof Error) ? e.message : '读取失败';
      const r: ImportResult = {
        pageName: pageName,
        blockCount: 0,
        success: false,
        error: '读取文件失败：' + msg
      };
      return r;
    }

    if (!content || content.length === 0) {
      const r: ImportResult = {
        pageName: pageName,
        blockCount: 0,
        success: false,
        error: '文件内容为空'
      };
      return r;
    }

    const blocks = ImportService.parseMarkdown(content);
    const r: ImportResult = {
      pageName: pageName,
      blockCount: blocks.length,
      success: true,
      error: ''
    };
    return r;
  }

  /**
   * 导入到指定页面。
   */
  static importToPage(filePath: string, pageName: string): boolean {
    const ws = WorkspaceService.getInstance();
    const page = ws.getPageByName(pageName);
    if (!page) return false;

    let content = '';
    try {
      content = fs.readTextSync(filePath);
    } catch (_e) { return false; }

    if (!content || content.length === 0) return false;

    const parsed = ImportService.parseMarkdown(content);
    return ImportService.insertBlocks(parsed, page.uuid, page.uuid);
  }

  /**
   * 导入为新页面（文件名作为页面名），返回页面名。
   * 失败返回空字符串。
   */
  static importAsNewPage(filePath: string): string {
    const ws = WorkspaceService.getInstance();
    const pageName = ImportService.derivePageName(filePath);

    // 创建页面（若不存在）
    let page = ws.getPageByName(pageName);
    if (!page) {
      const newPageOp: NewPageOp = {
        type: 'new-page',
        name: pageName,
        originalName: pageName
      };
      const r = ws.executeOp(newPageOp);
      if (!r.success) return '';
      page = ws.getPageByName(pageName);
      if (!page) return '';
    }

    let content = '';
    try {
      content = fs.readTextSync(filePath);
    } catch (_e) { return ''; }

    if (!content || content.length === 0) return '';

    const parsed = ImportService.parseMarkdown(content);
    if (!ImportService.insertBlocks(parsed, page.uuid, page.uuid)) return '';
    return pageName;
  }

  // ─── 内部工具 ───

  /**
   * 从文件路径推导页面名（不含扩展名）。
   */
  private static derivePageName(filePath: string): string {
    const slash1 = filePath.lastIndexOf('/');
    const slash2 = filePath.lastIndexOf('\\');
    const slashIdx = slash1 > slash2 ? slash1 : slash2;
    const fileName = slashIdx >= 0 ? filePath.substring(slashIdx + 1) : filePath;
    const dotIdx = fileName.lastIndexOf('.');
    return dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
  }

  /**
   * 解析 Markdown 文本为 ParsedBlock 列表。
   */
  private static parseMarkdown(content: string): ParsedBlock[] {
    const result: ParsedBlock[] = [];
    const lines = content.split('\n');

    let inCodeBlock = false;
    let codeBuffer = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();

      // 代码块开始/结束
      if (trimmed.indexOf('```') === 0) {
        if (inCodeBlock) {
          // 结束代码块
          codeBuffer += '\n' + line;
          const pb: ParsedBlock = {
            content: codeBuffer,
            level: 0,
            marker: BlockMarker.NONE
          };
          result.push(pb);
          codeBuffer = '';
          inCodeBlock = false;
        } else {
          // 开始代码块
          inCodeBlock = true;
          codeBuffer = line;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer += '\n' + line;
        continue;
      }

      // 空行跳过
      if (trimmed.length === 0) continue;

      // 分隔符
      if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
        const pb: ParsedBlock = {
          content: '---',
          level: 0,
          marker: BlockMarker.NONE
        };
        result.push(pb);
        continue;
      }

      // 标题 # ## ###
      if (trimmed.indexOf('# ') === 0 || trimmed.indexOf('## ') === 0 ||
          trimmed.indexOf('### ') === 0 || trimmed.indexOf('#### ') === 0) {
        const body = trimmed.replace(new RegExp('^#+\\s+'), '');
        const pb: ParsedBlock = {
          content: body,
          level: 0,
          marker: BlockMarker.NONE
        };
        result.push(pb);
        continue;
      }

      // 计算缩进层级（2 空格 = 1 级，Tab = 1 级）
      let indent = 0;
      let j = 0;
      while (j < line.length) {
        const ch = line.charAt(j);
        if (ch === ' ') {
          indent++;
          j++;
        } else if (ch === '\t') {
          indent += 2;
          j++;
        } else {
          break;
        }
      }
      const level = Math.floor(indent / 2);

      let body = line.substring(j);
      let marker = BlockMarker.NONE;

      // - [ ] / - [x] TODO 标记
      if (body.indexOf('- [ ] ') === 0) {
        marker = BlockMarker.TODO;
        body = body.substring(6);
      } else if (body.indexOf('- [x] ') === 0 || body.indexOf('- [X] ') === 0) {
        marker = BlockMarker.DONE;
        body = body.substring(6);
      } else if (body.indexOf('- ') === 0) {
        body = body.substring(2);
      } else if (body.indexOf('* ') === 0) {
        body = body.substring(2);
      }

      const pb: ParsedBlock = {
        content: body.trim(),
        level: level,
        marker: marker
      };
      result.push(pb);
    }

    // 未闭合的代码块
    if (inCodeBlock && codeBuffer.length > 0) {
      const pb: ParsedBlock = {
        content: codeBuffer,
        level: 0,
        marker: BlockMarker.NONE
      };
      result.push(pb);
    }

    return result;
  }

  /**
   * 批量插入 ParsedBlock 到页面。
   * @param parsed 解析后的 Block 列表
   * @param pageId 页面 UUID
   * @param rootParentId 顶层 Block 的 parentId（即 pageId）
   */
  private static insertBlocks(parsed: ParsedBlock[], pageId: string, rootParentId: string): boolean {
    const ws = WorkspaceService.getInstance();
    if (parsed.length === 0) return true;

    // lastAtLevel[k] = 第 k 层最后一个 block 的 uuid
    // 索引 0 表示顶层；为空字符串表示该层尚无 block
    const lastAtLevel: string[] = [];

    for (let i = 0; i < parsed.length; i++) {
      const pb = parsed[i];
      const level = pb.level;

      // 确定 parentId：取上一层的最后一个 block
      let parentId = '';
      if (level === 0) {
        parentId = rootParentId;
      } else {
        for (let k = level - 1; k >= 0; k--) {
          if (k < lastAtLevel.length && lastAtLevel[k].length > 0) {
            parentId = lastAtLevel[k];
            break;
          }
        }
        if (parentId.length === 0) parentId = rootParentId;
      }

      // 确定 leftId：取当前层的最后一个 block
      let leftId = '';
      if (level < lastAtLevel.length) {
        leftId = lastAtLevel[level];
      }

      const op: InsertBlockOp = {
        type: 'insert-block',
        content: pb.content,
        pageId: pageId,
        parentId: parentId,
        leftId: leftId,
        level: level
      };
      const r = ws.executeOp(op);
      if (!r.success) return false;

      // 更新 lastAtLevel
      if (r.affectedUuids.length > 0) {
        const newUuid = r.affectedUuids[0];
        while (lastAtLevel.length <= level) {
          lastAtLevel.push('');
        }
        lastAtLevel[level] = newUuid;
        // 清除更深层级
        while (lastAtLevel.length > level + 1) {
          lastAtLevel.pop();
        }
      }
    }

    return true;
  }
}
