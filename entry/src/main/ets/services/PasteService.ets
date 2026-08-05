import { WorkspaceService } from './WorkspaceService';
import { BlockData } from '../core/models/Block';
import { InsertBlockOp } from '../core/engine/OutlinerOps';
import { AppState } from '../state/AppState';

/**
 * ParsedBlock — 解析后的临时 Block 结构。
 * 仅包含内容和缩进层级，在插入时转换为完整 OutlinerOp。
 */
interface ParsedBlock {
  content: string;
  level: number;
}

/**
 * PasteService — 智能粘贴服务（单例）。
 *
 * 将 Markdown 文本解析为 Block 树并批量插入到指定位置。
 * 保留缩进层级，支持 - / * 列表前缀。
 *
 * 解析规则：
 *   - 按 \n 拆分行
 *   - 检测缩进（前导空格数 / 2 = level）
 *   - 移除 - 或 * 前缀（后跟空格）
 *   - 跳过空行
 *
 * 插入策略：
 *   - pasteAtBlock：在目标 Block 下方插入，首块作为兄弟节点
 *   - pasteAtEnd：在页面末尾插入，首块作为顶层节点
 *   - 使用 levelStack 维护各层级最后插入的 uuid，计算 parentId/leftId
 */
export class PasteService {
  private static instance: PasteService | undefined;

  private constructor() {}

  static getInstance(): PasteService {
    if (!PasteService.instance) {
      PasteService.instance = new PasteService();
    }
    return PasteService.instance;
  }

  /**
   * 将 Markdown 文本解析为 ParsedBlock 数组。
   *  - 按 \n 拆分行
   *  - 检测缩进（前导空格数 / 2 = level）
   *  - 移除 - 或 * 前缀
   *  - 跳过空行
   */
  parseMarkdownToBlocks(markdown: string): ParsedBlock[] {
    const result: ParsedBlock[] = [];
    if (markdown.length === 0) {
      return result;
    }

    const lines: string[] = markdown.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];

      // 计算前导空格数
      let leadingSpaces = 0;
      for (let j = 0; j < line.length; j++) {
        if (line.charAt(j) === ' ') {
          leadingSpaces++;
        } else {
          break;
        }
      }
      const level: number = Math.floor(leadingSpaces / 2);

      // 移除前导空格
      let content: string = line.substring(leadingSpaces);

      // 移除 - 或 * 前缀（后跟空格）
      if (content.length >= 2 && (content.charAt(0) === '-' || content.charAt(0) === '*') && content.charAt(1) === ' ') {
        content = content.substring(2);
      }

      // 跳过空行
      if (content.trim().length === 0) {
        continue;
      }

      const parsed: ParsedBlock = { content: content.trim(), level: level };
      result.push(parsed);
    }
    return result;
  }

  /**
   * 在 targetBlock 下方批量插入解析后的 Block。
   * 首块作为 targetBlock 的兄弟节点，后续块基于相对缩进计算层级。
   */
  pasteAtBlock(markdown: string, pageId: string, targetBlockUuid: string): void {
    const ws = WorkspaceService.getInstance();
    const target: BlockData | undefined = ws.getBlock(targetBlockUuid);
    if (!target) {
      return;
    }

    const parsed: ParsedBlock[] = this.parseMarkdownToBlocks(markdown);
    if (parsed.length === 0) {
      return;
    }

    const baseLevel: number = target.level;
    const baseIndent: number = parsed[0].level;

    // levelStack[L] = 该层级最后插入（或预存）的 block uuid
    const levelStack: string[] = [];
    for (let i = 0; i < 64; i++) {
      levelStack.push('');
    }
    // target 作为 baseLevel 层的前一个兄弟
    levelStack[baseLevel] = targetBlockUuid;
    // target 的 parent 作为上一层节点（用于计算新兄弟的 parentId）
    if (baseLevel > 0) {
      levelStack[baseLevel - 1] = target.parentId;
    }

    for (let i = 0; i < parsed.length; i++) {
      const pb: ParsedBlock = parsed[i];
      const relLevel: number = pb.level - baseIndent;
      const newLevel: number = baseLevel + relLevel;
      if (newLevel < 0) {
        continue;
      }

      // parentId = 上一层级的最后节点；level 0 时为 pageId
      let parentId: string = pageId;
      if (newLevel > 0) {
        const candidate: string = levelStack[newLevel - 1];
        parentId = candidate.length > 0 ? candidate : pageId;
      }

      // leftId = 同层级的最后节点
      const leftId: string = levelStack[newLevel];

      const op: InsertBlockOp = {
        type: 'insert-block',
        content: pb.content,
        pageId: pageId,
        parentId: parentId,
        leftId: leftId,
        level: newLevel
      };
      const result = ws.executeOp(op);
      if (result.success && result.affectedUuids.length > 0) {
        const newUuid: string = result.affectedUuids[0];
        levelStack[newLevel] = newUuid;
        // 清掉更深层级的栈（新分支重置）
        for (let k = newLevel + 1; k < 64; k++) {
          levelStack[k] = '';
        }
      }
    }

    AppState.bumpBlocksVersion();
  }

  /**
   * 在页面末尾插入解析后的 Block。
   * 首块作为顶层节点（level 0），追加到最后一个顶层 Block 之后。
   */
  pasteAtEnd(markdown: string, pageId: string): void {
    const ws = WorkspaceService.getInstance();
    const parsed: ParsedBlock[] = this.parseMarkdownToBlocks(markdown);
    if (parsed.length === 0) {
      return;
    }

    const topLevelBlocks: BlockData[] = ws.getPageBlocks(pageId);
    let lastTopUuid: string = '';
    if (topLevelBlocks.length > 0) {
      lastTopUuid = topLevelBlocks[topLevelBlocks.length - 1].uuid;
    }

    const baseIndent: number = parsed[0].level;
    const levelStack: string[] = [];
    for (let i = 0; i < 64; i++) {
      levelStack.push('');
    }
    levelStack[0] = lastTopUuid;

    for (let i = 0; i < parsed.length; i++) {
      const pb: ParsedBlock = parsed[i];
      const relLevel: number = pb.level - baseIndent;
      const newLevel: number = relLevel;
      if (newLevel < 0) {
        continue;
      }

      let parentId: string = pageId;
      if (newLevel > 0) {
        const candidate: string = levelStack[newLevel - 1];
        parentId = candidate.length > 0 ? candidate : pageId;
      }

      const leftId: string = levelStack[newLevel];

      const op: InsertBlockOp = {
        type: 'insert-block',
        content: pb.content,
        pageId: pageId,
        parentId: parentId,
        leftId: leftId,
        level: newLevel
      };
      const result = ws.executeOp(op);
      if (result.success && result.affectedUuids.length > 0) {
        const newUuid: string = result.affectedUuids[0];
        levelStack[newLevel] = newUuid;
        for (let k = newLevel + 1; k < 64; k++) {
          levelStack[k] = '';
        }
      }
    }

    AppState.bumpBlocksVersion();
  }
}
