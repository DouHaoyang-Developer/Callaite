import { WorkspaceService } from './WorkspaceService';
import { BlockData } from '../core/models/Block';

/**
 * FlashcardService — 闪卡系统（基础间隔重复）。
 *
 * 对应 Logseq extensions/srs/handler.cljs。
 * 从 #card 标记的 Block 创建闪卡，支持简单的间隔重复逻辑。
 */
export class FlashcardService {
  private static readonly CARD_MARKER = '#card';
  private static readonly CLOZE_PREFIX = '{{cloze';
  private static readonly CLOZE_SUFFIX = '}}';

  /**
   * 获取所有闪卡 Block。
   */
  static getFlashcards(): BlockData[] {
    const ws = WorkspaceService.getInstance();
    const pages = ws.getAllPages();
    const cards: BlockData[] = [];
    for (let i = 0; i < pages.length; i++) {
      const blocks = ws.getPageBlocks(pages[i].uuid);
      for (let j = 0; j < blocks.length; j++) {
        if (FlashcardService.isCard(blocks[j])) {
          cards.push(blocks[j]);
        }
      }
    }
    return cards;
  }

  /**
   * 判断是否闪卡。
   */
  static isCard(block: BlockData): boolean {
    return block.content.indexOf(FlashcardService.CARD_MARKER) >= 0 ||
           block.tags.indexOf('card') >= 0;
  }

  /**
   * 获取卡片的正面内容（过滤掉标记）。
   */
  static getCardFront(block: BlockData): string {
    let content = block.content;
    content = content.replace(new RegExp(FlashcardService.CARD_MARKER, 'g'), '');
    // 隐藏 cloze 答案部分
    const clozeRegex = new RegExp('\\{\\{cloze\\s+([^}]+)\\}\\}', 'g');
    content = content.replace(clozeRegex, '[...]');
    return content.trim();
  }

  /**
   * 获取卡片背面内容（仅 cloze 卡片有区别）。
   */
  static getCardBack(block: BlockData): string {
    let content = block.content;
    content = content.replace(new RegExp(FlashcardService.CARD_MARKER, 'g'), '');
    const clozeRegex = new RegExp('\\{\\{cloze\\s+([^}]+)\\}\\}', 'g');
    let match = clozeRegex.exec(block.content);
    if (match) {
      return match[1];
    }
    return content.trim();
  }

  /**
   * 简单间隔重复评分。
   * 0=忘记, 1=困难, 2=良好, 3=简单
   */
  static rateCard(blockUuid: string, score: number): void {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(blockUuid);
    if (!block) return;

    let interval = 1;
    const currentInterval = block.properties.get('srs_interval');
    if (currentInterval) {
      interval = parseInt(currentInterval) || 1;
    }

    if (score === 0) interval = 1;
    else if (score === 1) interval = Math.max(1, Math.floor(interval * 0.8));
    else if (score === 2) interval = Math.floor(interval * 1.5);
    else if (score === 3) interval = Math.floor(interval * 2.5);

    block.properties.set('srs_interval', interval.toString());
    block.properties.set('srs_last_review', new Date().toISOString().substring(0, 10));
  }

  /**
   * 获取今日待复习卡片数量。
   */
  static getDueCount(): number {
    return FlashcardService.getFlashcards().length;
  }
}
