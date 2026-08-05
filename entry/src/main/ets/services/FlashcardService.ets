import { WorkspaceService } from './WorkspaceService';
import { BlockData } from '../core/models/Block';

// ─── 枚举 ───

/**
 * 卡片调度状态。
 *  NEW        — 新卡，未开始复习
 *  LEARNING   — 学习中（首次或重学阶段）
 *  REVIEW     — 已进入正常复习队列
 *  RELEARNING — 复习中遗忘后重新学习
 */
export enum CardState {
  NEW = 0,
  LEARNING = 1,
  REVIEW = 2,
  RELEARNING = 3
}

/**
 * 评分等级（FSRS 标准 1-4）。
 */
export enum Rating {
  AGAIN = 1,
  HARD = 2,
  GOOD = 3,
  EASY = 4
}

// ─── 数据接口 ───

export interface CardData {
  uuid: string;
  stability: number;
  difficulty: number;
  lastReview: number;
  reps: number;
  lapses: number;
  state: CardState;
  due: number;
}

export interface ReviewStats {
  total: number;
  due: number;
  newCount: number;
  learning: number;
  review: number;
}

// ─── FSRS-4.5 常量 ───

const DAY_MS: number = 24 * 60 * 60 * 1000;
const TARGET_DIFFICULTY: number = 5.0;
const MIN_STABILITY: number = 0.1;
const MIN_DIFFICULTY: number = 1.0;
const MAX_DIFFICULTY: number = 10.0;

/**
 * FlashcardService — FSRS-4.5 间隔重复算法。
 *
 * 卡片调度数据持久化到 Block.properties（键名 fsrs_*）。
 * 19 个默认参数 w 取自 FSRS-4.5 官方默认值。
 */
export class FlashcardService {
  private static readonly CARD_MARKER: string = '#card';

  // FSRS-4.5 默认参数（19 个）
  //  [0-3]   初始稳定性（AGAIN/HARD/GOOD/EASY）
  //  [4-5]   初始难度基础与评分影响
  //  [6]     难度更新中旧难度权重
  //  [7]     难度回归系数
  //  [8-10]  成功稳定性更新因子
  //  [11-14] 失败稳定性更新因子
  //  [15-16] hard penalty / easy bonus
  //  [17-18] 保留
  private static readonly W: number[] = [
    0.4, 0.6, 2.4, 5.8,
    4.93, 0.94, 0.86, 0.01,
    1.49, 0.14, 0.94,
    2.18, 0.05, 0.34, 1.26,
    0.29, 2.61, 0.7, 0.0
  ];

  private static readonly PROP_STABILITY: string = 'fsrs_stability';
  private static readonly PROP_DIFFICULTY: string = 'fsrs_difficulty';
  private static readonly PROP_LAST_REVIEW: string = 'fsrs_last_review';
  private static readonly PROP_REPS: string = 'fsrs_reps';
  private static readonly PROP_LAPSES: string = 'fsrs_lapses';
  private static readonly PROP_STATE: string = 'fsrs_state';
  private static readonly PROP_DUE: string = 'fsrs_due';

  // ─── 卡片识别 ───

  /**
   * 获取所有 #card 标记的 Block。
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

  static isCard(block: BlockData): boolean {
    return block.content.indexOf(FlashcardService.CARD_MARKER) >= 0 ||
           block.tags.indexOf('card') >= 0;
  }

  /**
   * 卡片正面：隐藏 cloze 答案。
   */
  static getCardFront(block: BlockData): string {
    let content = block.content;
    content = content.replace(new RegExp(FlashcardService.CARD_MARKER, 'g'), '');
    const clozeRegex = new RegExp('\\{\\{cloze\\s+([^}]+)\\}\\}', 'g');
    content = content.replace(clozeRegex, '[...]');
    return content.trim();
  }

  /**
   * 卡片背面：完整内容（cloze 卡片仅显示填空部分）。
   */
  static getCardBack(block: BlockData): string {
    let content = block.content;
    content = content.replace(new RegExp(FlashcardService.CARD_MARKER, 'g'), '');
    const clozeRegex = new RegExp('\\{\\{cloze\\s+([^}]+)\\}\\}', 'g');
    const match = clozeRegex.exec(block.content);
    if (match) {
      return match[1];
    }
    return content.trim();
  }

  // ─── CardData 读写 ───

  /**
   * 获取闪卡调度数据。无记录则返回 NEW 默认值。
   */
  static getCardData(blockUuid: string): CardData {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(blockUuid);
    if (!block) {
      return FlashcardService.createDefaultCardData(blockUuid);
    }
    const stabilityStr = block.properties.get(FlashcardService.PROP_STABILITY);
    if (!stabilityStr) {
      return FlashcardService.createDefaultCardData(blockUuid);
    }
    const stability = parseFloat(stabilityStr);
    const difficulty = parseFloat(block.properties.get(FlashcardService.PROP_DIFFICULTY));
    const lastReview = parseInt(block.properties.get(FlashcardService.PROP_LAST_REVIEW), 10);
    const reps = parseInt(block.properties.get(FlashcardService.PROP_REPS), 10);
    const lapses = parseInt(block.properties.get(FlashcardService.PROP_LAPSES), 10);
    const state = FlashcardService.parseCardState(block.properties.get(FlashcardService.PROP_STATE));
    const dueStr = block.properties.get(FlashcardService.PROP_DUE);
    const due = dueStr ? parseInt(dueStr, 10) : Date.now();

    return {
      uuid: blockUuid,
      stability: isNaN(stability) ? 0 : stability,
      difficulty: isNaN(difficulty) ? 0 : difficulty,
      lastReview: isNaN(lastReview) ? 0 : lastReview,
      reps: isNaN(reps) ? 0 : reps,
      lapses: isNaN(lapses) ? 0 : lapses,
      state: state,
      due: isNaN(due) ? Date.now() : due
    };
  }

  private static createDefaultCardData(blockUuid: string): CardData {
    return {
      uuid: blockUuid,
      stability: 0,
      difficulty: 0,
      lastReview: 0,
      reps: 0,
      lapses: 0,
      state: CardState.NEW,
      due: Date.now()
    };
  }

  private static parseCardState(s: string): CardState {
    if (s === '1') return CardState.LEARNING;
    if (s === '2') return CardState.REVIEW;
    if (s === '3') return CardState.RELEARNING;
    return CardState.NEW;
  }

  private static stateToString(state: CardState): string {
    if (state === CardState.LEARNING) return '1';
    if (state === CardState.REVIEW) return '2';
    if (state === CardState.RELEARNING) return '3';
    return '0';
  }

  /**
   * 将 CardData 持久化到 Block.properties 并触发页面保存。
   */
  private static setCardDataToBlock(card: CardData): void {
    const ws = WorkspaceService.getInstance();
    const block = ws.getBlock(card.uuid);
    if (!block) return;
    block.properties.set(FlashcardService.PROP_STABILITY, card.stability.toString());
    block.properties.set(FlashcardService.PROP_DIFFICULTY, card.difficulty.toString());
    block.properties.set(FlashcardService.PROP_LAST_REVIEW, card.lastReview.toString());
    block.properties.set(FlashcardService.PROP_REPS, card.reps.toString());
    block.properties.set(FlashcardService.PROP_LAPSES, card.lapses.toString());
    block.properties.set(FlashcardService.PROP_STATE, FlashcardService.stateToString(card.state));
    block.properties.set(FlashcardService.PROP_DUE, card.due.toString());

    const pageUuid = ws.getPageUuidForBlock(card.uuid);
    if (pageUuid) {
      ws.savePage(pageUuid);
    }
  }

  // ─── FSRS-4.5 核心计算 ───

  /**
   * 新卡初始稳定性 = w[rating-1]。
   */
  static initStability(rating: Rating): number {
    const idx = rating - 1;
    if (idx < 0 || idx >= 4) return MIN_STABILITY;
    return Math.max(FlashcardService.W[idx], MIN_STABILITY);
  }

  /**
   * 新卡初始难度 = w[4] - (rating-3) * w[5]，clamp 到 [1, 10]。
   */
  static initDifficulty(rating: Rating): number {
    const d = FlashcardService.W[4] - (rating - 3) * FlashcardService.W[5];
    return FlashcardService.clampDifficulty(d);
  }

  /**
   * 下一难度：旧难度与初始难度的加权平均，再做均值回归。
   */
  static nextDifficulty(d: number, rating: Rating): number {
    const id = FlashcardService.initDifficulty(rating);
    const next = FlashcardService.W[6] * d + (1 - FlashcardService.W[6]) * id;
    return FlashcardService.clampDifficulty(FlashcardService.meanReversion(next));
  }

  /**
   * 难度均值回归：向 5.0 缓慢靠拢。
   */
  static meanReversion(d: number): number {
    const reversion = 0.1;
    return reversion * TARGET_DIFFICULTY + (1 - reversion) * d;
  }

  /**
   * 可提取性 R = exp(-elapsedDays / s)。
   */
  static nextRetrievability(s: number, elapsedDays: number): number {
    if (s <= 0) return 0;
    return Math.exp(-elapsedDays / s);
  }

  /**
   * 间隔天数 = round(s * 9)，最小 1。
   */
  static nextInterval(s: number): number {
    const interval = Math.round(s * 9);
    return Math.max(interval, 1);
  }

  /**
   * 下一稳定性：
   *  - AGAIN（遗忘）：基于难度与遗忘程度的重置公式
   *  - HARD/GOOD/EASY（成功）：基于难度、稳定性、可提取性的增长公式
   */
  static nextStability(d: number, s: number, r: number, rating: Rating): number {
    if (rating === Rating.AGAIN) {
      const base = FlashcardService.W[11];
      const dFactor = Math.pow(d, -FlashcardService.W[12]);
      const sFactor = Math.pow(s + 1, FlashcardService.W[13]) - 1;
      const rFactor = Math.exp(-(1 - r) * FlashcardService.W[14]);
      const newS = base * dFactor * sFactor * rFactor;
      return Math.max(newS, MIN_STABILITY);
    }
    let adjust = 1.0;
    if (rating === Rating.HARD) {
      adjust = 1 - FlashcardService.W[15];
    } else if (rating === Rating.EASY) {
      adjust = 1 + FlashcardService.W[16];
    }
    const safeS = Math.max(s, MIN_STABILITY);
    const successFactor = 1 + Math.exp(FlashcardService.W[8]) *
      (11 - d) *
      Math.pow(safeS, -FlashcardService.W[9]) *
      (Math.exp((1 - r) * FlashcardService.W[10]) - 1) * adjust;
    const newS = s * successFactor;
    return Math.max(newS, MIN_STABILITY);
  }

  private static clampDifficulty(d: number): number {
    if (d < MIN_DIFFICULTY) return MIN_DIFFICULTY;
    if (d > MAX_DIFFICULTY) return MAX_DIFFICULTY;
    return d;
  }

  // ─── 评分入口 ───

  /**
   * 评分后更新调度数据并返回新 CardData。
   */
  static rateCard(blockUuid: string, rating: Rating): CardData {
    const card = FlashcardService.getCardData(blockUuid);
    const now = Date.now();
    const elapsedMs = card.lastReview > 0 ? now - card.lastReview : 0;
    const elapsedDays = elapsedMs / DAY_MS;
    const r = card.state === CardState.REVIEW
      ? FlashcardService.nextRetrievability(card.stability, elapsedDays)
      : 0;

    let newStability: number;
    let newDifficulty: number;
    let newState: CardState;
    let newInterval: number;

    if (card.state === CardState.NEW) {
      newStability = FlashcardService.initStability(rating);
      newDifficulty = FlashcardService.initDifficulty(rating);
      if (rating === Rating.AGAIN) {
        newState = CardState.LEARNING;
        newInterval = 1;
      } else {
        newState = CardState.REVIEW;
        newInterval = FlashcardService.nextInterval(newStability);
      }
    } else if (card.state === CardState.LEARNING || card.state === CardState.RELEARNING) {
      newStability = FlashcardService.initStability(rating);
      newDifficulty = FlashcardService.nextDifficulty(card.difficulty, rating);
      if (rating === Rating.AGAIN) {
        newState = card.state === CardState.LEARNING ? CardState.LEARNING : CardState.RELEARNING;
        newInterval = 1;
      } else {
        newState = CardState.REVIEW;
        newInterval = FlashcardService.nextInterval(newStability);
      }
    } else {
      // REVIEW 状态
      if (rating === Rating.AGAIN) {
        newStability = FlashcardService.nextStability(card.difficulty, card.stability, r, rating);
        newDifficulty = FlashcardService.nextDifficulty(card.difficulty, rating);
        newState = CardState.RELEARNING;
        newInterval = 1;
        card.lapses = card.lapses + 1;
      } else {
        newStability = FlashcardService.nextStability(card.difficulty, card.stability, r, rating);
        newDifficulty = FlashcardService.nextDifficulty(card.difficulty, rating);
        newState = CardState.REVIEW;
        newInterval = FlashcardService.nextInterval(newStability);
      }
    }

    card.stability = newStability;
    card.difficulty = newDifficulty;
    card.state = newState;
    card.lastReview = now;
    card.reps = card.reps + 1;
    card.due = now + newInterval * DAY_MS;

    FlashcardService.setCardDataToBlock(card);
    return card;
  }

  // ─── 卡片列表与统计 ───

  /**
   * 获取到期卡片（due <= now）。
   */
  static getDueCards(): BlockData[] {
    const all = FlashcardService.getFlashcards();
    const now = Date.now();
    const due: BlockData[] = [];
    for (let i = 0; i < all.length; i++) {
      const card = FlashcardService.getCardData(all[i].uuid);
      if (card.due <= now) {
        due.push(all[i]);
      }
    }
    return due;
  }

  /**
   * 获取复习统计。
   */
  static getReviewStats(): ReviewStats {
    const all = FlashcardService.getFlashcards();
    const now = Date.now();
    let due = 0;
    let newCount = 0;
    let learning = 0;
    let review = 0;
    for (let i = 0; i < all.length; i++) {
      const card = FlashcardService.getCardData(all[i].uuid);
      if (card.due <= now) {
        due++;
      }
      if (card.state === CardState.NEW) {
        newCount++;
      } else if (card.state === CardState.LEARNING || card.state === CardState.RELEARNING) {
        learning++;
      } else if (card.state === CardState.REVIEW) {
        review++;
      }
    }
    return {
      total: all.length,
      due: due,
      newCount: newCount,
      learning: learning,
      review: review
    };
  }

  /**
   * 兼容旧接口：到期卡片数量。
   */
  static getDueCount(): number {
    return FlashcardService.getDueCards().length;
  }
}
