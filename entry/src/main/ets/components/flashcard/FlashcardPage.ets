import { TablerIcon } from '../common/Icons';
import { AppState } from '../../state/AppState';
import { FlashcardService } from '../../services/FlashcardService';
import { BlockData } from '../../core/models/Block';

/**
 * FlashcardPage — 闪卡复习页面。
 * 显示 #card 标记的 Block，点击翻转查看答案。
 */
@Component
export struct FlashcardPage {
  @State cards: BlockData[] = [];
  @State currentIndex: number = 0;
  @State showBack: boolean = false;

  aboutToAppear(): void {
    this.cards = FlashcardService.getFlashcards();
  }

  build() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Row() { TablerIcon('arrow-left', 18, $r('app.color.text')) }
        .width(36).height(36)
        .onClick(() => { AppState.setCurrentPage('Journal'); })

        Text('闪卡复习')
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .layoutWeight(1)

        Text(this.currentIndex + 1 + '/' + this.cards.length)
          .fontSize(14).fontColor($r('app.color.muted_text'))
      }
      .width('100%').padding({ top: 24, bottom: 12 })

      if (this.cards.length === 0) {
        Column({ space: 12 }) {
          TablerIcon('bulb', 40, '#D1D5DB')
          Text('暂无闪卡').fontSize(16).fontColor($r('app.color.muted_text'))
          Text('在 Block 中添加 #card 标签创建闪卡').fontSize(13).fontColor($r('app.color.muted_text'))
        }
        .width('100%').alignItems(HorizontalAlign.Center).padding({ top: 60 })
      } else {
        // 卡片
        Column() {
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

          if (this.showBack) {
            Row({ space: 12 }) {
              Button('忘记').fontSize(14).backgroundColor('#EF4444')
                .onClick(() => { FlashcardService.rateCard(this.cards[this.currentIndex].uuid, 0); this.next(); })
              Button('困难').fontSize(14).backgroundColor('#F59E0B')
                .onClick(() => { FlashcardService.rateCard(this.cards[this.currentIndex].uuid, 1); this.next(); })
              Button('良好').fontSize(14).backgroundColor('#10B981')
                .onClick(() => { FlashcardService.rateCard(this.cards[this.currentIndex].uuid, 2); this.next(); })
              Button('简单').fontSize(14).backgroundColor('#0078D4')
                .onClick(() => { FlashcardService.rateCard(this.cards[this.currentIndex].uuid, 3); this.next(); })
            }
            .width('100%').justifyContent(FlexAlign.SpaceEvenly).padding({ top: 16 })
          }
        }
        .width('100%')
      }
      Blank()
    }
    .width('100%').height('100%').padding({ left: 24, right: 24 }).alignItems(HorizontalAlign.Start)
  }

  next(): void {
    this.showBack = false;
    if (this.currentIndex < this.cards.length - 1) {
      this.currentIndex++;
    } else {
      this.currentIndex = 0;
    }
  }
}
