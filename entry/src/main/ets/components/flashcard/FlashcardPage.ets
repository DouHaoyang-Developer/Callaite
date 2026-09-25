import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { FlashcardService, Rating, CardData } from '../../services/FlashcardService';
import { BlockData } from '../../core/models/Block';
import { promptAction } from '@kit.ArkUI';

/**
 * FlashcardPage — FSRS 闪卡复习页面。
 *
 * 流程：
 *  1. aboutToAppear 加载到期卡片（getDueCards）
 *  2. 显示卡片正面，点击翻转查看答案
 *  3. 翻转后显示 4 个评分按钮（Again/Hard/Good/Easy）
 *  4. 评分后调用 FlashcardService.rateCard 调度，切换下一张
 *  5. 完成后显示统计摘要（复习数、平均难度、下次到期）
 *  6. 无到期卡片时显示"今日复习完成"空状态
 */
@Component
export struct FlashcardPage {
  @State cards: BlockData[] = [];
  @State currentIndex: number = 0;
  @State showBack: boolean = false;
  @State finished: boolean = false;
  @State reviewedCount: number = 0;
  @State totalToReview: number = 0;
  @State statsTotal: number = 0;
  @State statsReview: number = 0;
  @State statsLearning: number = 0;
  @State statsNewCount: number = 0;
  @State avgDifficulty: number = 0;
  @State nextDue: number = 0;

  aboutToAppear(): void {
    this.refreshCards();
  }

  private refreshCards(): void {
    this.cards = FlashcardService.getDueCards();
    this.totalToReview = this.cards.length;
    this.currentIndex = 0;
    this.showBack = false;
    this.reviewedCount = 0;
    this.avgDifficulty = 0;
    this.nextDue = 0;
    this.finished = this.cards.length === 0;
    this.refreshStats();
  }

  private refreshStats(): void {
    const s = FlashcardService.getReviewStats();
    this.statsTotal = s.total;
    this.statsReview = s.review;
    this.statsLearning = s.learning;
    this.statsNewCount = s.newCount;
  }

  build() {
    Column({ space: 16 }) {
      // 顶部导航 + 进度
      Row({ space: 12 }) {
        Row() { TablerIcon('arrow-left', 20, $r('app.color.text')) }
        .width(36).height(36)
        .onClick(() => { AppState.setCurrentPage('Journal'); })

        Text('闪卡复习')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .layoutWeight(1)

        if (!this.finished && this.cards.length > 0) {
          Text((this.currentIndex + 1) + ' / ' + this.totalToReview)
            .fontSize(14).fontColor($r('app.color.muted_text'))
        }
      }
      .width('100%').padding({ top: 24, bottom: 12 })

      if (this.finished) {
        this.buildFinished()
      } else {
        this.buildCard()
        Blank()
      }
    }
    .width('100%').height('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildFinished() {
    Column({ space: 16 }) {
      TablerIcon('check', 56, '#10B981')
      Text('今日复习完成')
        .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))

      // 6 项统计收进「卡片统计」信息块（标题行 + 分隔线 + 两行三列共享网格）
      this.buildStatsCard()

      if (this.nextDue > 0) {
        Text('下次到期：' + this.formatDate(this.nextDue))
          .fontSize(13).fontColor($r('app.color.muted_text'))
      }

      // 操作区：主 CTA（实心主色，原「刷新」的 surface1 与侧栏同色，白底页上形似禁用态）
      Row({ space: 12 }) {
        Button('开始复习')
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontColor($r('app.color.on_primary'))
          .backgroundColor($r('app.color.primary'))
          .height(40)
          .borderRadius(6)
          .padding({ left: 24, right: 24 })
          .onClick(() => { this.startReview(); })

        Button('刷新')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor($r('app.color.text'))
          .backgroundColor($r('app.color.surface2'))
          .height(40)
          .borderRadius(6)
          .padding({ left: 20, right: 20 })
          .onClick(() => { this.refreshCards(); })
      }
      .margin({ top: 8 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 24, bottom: 24 })
  }

  /**
   * 卡片统计信息块。
   * 结构性修复：统计项由「Row({ space: 32 }) + 自适应宽度 Column」改为
   * 等宽 layoutWeight(1) 单元格 —— 此前两行列心因数值位数不同各差 6vp，无法严格同列。
   * 数据来源与口径不变（FlashcardService.getReviewStats + 本页会话计数）。
   */
  @Builder
  buildStatsCard() {
    Column({ space: 0 }) {
      // 标题行：小号弱化文字 + 底部分隔线
      Text('卡片统计')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted_text'))
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 8 })

      Divider().color($r('app.color.border'))

      Row() {
        this.StatCell('已复习', this.reviewedCount.toString())
        this.StatCell('总卡片', this.statsTotal.toString())
        this.StatCell('复习中', this.statsReview.toString())
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 12, bottom: 6 })

      Row() {
        this.StatCell('学习中', this.statsLearning.toString())
        this.StatCell('未开始', this.statsNewCount.toString())
        this.StatCell('平均难度', this.avgDifficulty.toFixed(2))
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6, bottom: 12 })
    }
    .width('100%')
    .backgroundColor($r('app.color.surface1'))
    .borderRadius(8)
  }

  /**
   * 统计单元格：等宽（layoutWeight(1)）—— 两行三列共用同一套列宽，保证严格同列对齐。
   */
  @Builder
  StatCell(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(12).fontColor($r('app.color.muted_text'))
      Text(value)
        .fontSize(20).fontColor($r('app.color.text'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildCard() {
    Column() {
      // 进度条
      Row() {
        Row()
          .width(this.progressPercent())
          .height(4)
          .backgroundColor('#0078D4')
      }
      .width('100%').height(4)
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(2)
      .margin({ bottom: 16 })

      // 卡片正反面
      Column() {
        Text(this.showBack ? '答案' : '问题')
          .fontSize(12).fontColor($r('app.color.muted_text')).margin({ bottom: 8 })
        Text(this.showBack
          ? FlashcardService.getCardBack(this.cards[this.currentIndex])
          : FlashcardService.getCardFront(this.cards[this.currentIndex]))
          .fontSize(18).fontColor($r('app.color.text'))
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding(32)
      .backgroundColor($r('app.color.surface1'))
      .borderRadius(12)
      .onClick(() => { this.showBack = !this.showBack; })

      // 评分按钮（翻转后显示）
      if (this.showBack) {
        Row({ space: 8 }) {
          Button('Again').type(ButtonType.Capsule).fontSize(14).backgroundColor('#EF4444').fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => { this.rate(Rating.AGAIN); })
          Button('Hard').type(ButtonType.Capsule).fontSize(14).backgroundColor('#F59E0B').fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => { this.rate(Rating.HARD); })
          Button('Good').type(ButtonType.Capsule).fontSize(14).backgroundColor('#0078D4').fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => { this.rate(Rating.GOOD); })
          Button('Easy').type(ButtonType.Capsule).fontSize(14).backgroundColor('#10B981').fontColor('#FFFFFF')
            .layoutWeight(1)
            .onClick(() => { this.rate(Rating.EASY); })
        }
        .width('100%').padding({ top: 16 })
      }
    }
    .width('100%')
  }

  /**
   * 主 CTA「开始复习」：先查到期卡片（与 refreshCards 同一数据源 FlashcardService.getDueCards），
   * 有卡才重置会话并进入复习；无卡时保留本轮统计并给出明确反馈，
   * 避免「点了没反应」或把刚完成的复习数据清零。
   */
  private startReview(): void {
    const due: BlockData[] = FlashcardService.getDueCards();
    if (due.length === 0) {
      promptAction.openToast({ message: '暂无到期卡片，可稍后再复习' }).catch(() => {});
      return;
    }
    this.refreshCards();
  }

  private progressPercent(): string {
    if (this.totalToReview <= 0) return '0%';
    const pct = (this.currentIndex / this.totalToReview) * 100;
    return pct + '%';
  }

  private rate(rating: Rating): void {
    if (this.currentIndex >= this.cards.length) return;
    const card: CardData = FlashcardService.rateCard(this.cards[this.currentIndex].uuid, rating);
    // 累计平均难度（增量平均）
    const newAvg = (this.avgDifficulty * this.reviewedCount + card.difficulty) / (this.reviewedCount + 1);
    this.avgDifficulty = newAvg;
    this.nextDue = card.due;
    this.reviewedCount = this.reviewedCount + 1;
    this.showBack = false;

    if (this.currentIndex < this.cards.length - 1) {
      this.currentIndex = this.currentIndex + 1;
    } else {
      this.finished = true;
      this.refreshStats();
    }
  }

  private formatDate(ts: number): string {
    if (ts <= 0) return '';
    const d = new Date(ts);
    const y = d.getFullYear();
    const m = this.pad2(d.getMonth() + 1);
    const day = this.pad2(d.getDate());
    const h = this.pad2(d.getHours());
    const min = this.pad2(d.getMinutes());
    return y + '-' + m + '-' + day + ' ' + h + ':' + min;
  }

  private pad2(n: number): string {
    if (n < 10) return '0' + n.toString();
    return n.toString();
  }
}
