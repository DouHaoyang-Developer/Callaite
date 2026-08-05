/**
 * WidgetCard — 桌面服务卡片 UI。
 *
 * 支持两种布局：
 *  - overview  概览卡片：显示应用名称 + 页面数 + 最新 3 条 Block 预览
 *  - quicknote 速记卡片：说明文本 + 打开应用按钮，点击跳转主应用进行速记
 *    （卡片不支持 TextInput，输入在主应用内完成）
 *
 * 2×2 尺寸卡片，点击主体可跳转主应用。
 */

let storage = new LocalStorage();

interface RouterAction {
  action: string;
  abilityName: string;
}

const CARD_TYPE_OVERVIEW: string = 'overview';
const CARD_TYPE_QUICKNOTE: string = 'quicknote';

@Entry(storage)
@Component
struct WidgetCard {
  // ─── 概览卡片数据 ───
  @LocalStorageProp('title') title: string = 'Callaite';
  @LocalStorageProp('pageCount') pageCount: string = '0';
  @LocalStorageProp('preview1') preview1: string = '';
  @LocalStorageProp('preview2') preview2: string = '';
  @LocalStorageProp('preview3') preview3: string = '';

  // ─── 卡片类型 ───
  @LocalStorageProp('cardType') cardType: string = CARD_TYPE_OVERVIEW;

  build() {
    Column() {
      if (this.cardType === CARD_TYPE_QUICKNOTE) {
        this.buildQuickNote()
      } else {
        this.buildOverview()
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface0'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  buildOverview() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))
        .maxLines(1)

      Text(this.pageCount + ' 个页面')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))

      if (this.preview1 !== '') {
        Text(this.preview1)
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.preview2 !== '') {
        Text(this.preview2)
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.preview3 !== '') {
        Text(this.preview3)
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  buildQuickNote() {
    Column({ space: 8 }) {
      Text('速记')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text'))

      // 卡片不支持 TextInput，点击按钮跳转主应用进行速记
      Text('在应用内记录想法，支持 Markdown 与大纲')
        .fontSize(10)
        .fontColor($r('app.color.muted_text'))
        .maxLines(2)

      Button('打开应用')
        .fontSize(12)
        .fontColor($r('app.color.surface0'))
        .backgroundColor($r('app.color.primary'))
        .borderRadius(8)
        .height(32)
        .width('100%')
        .onClick(() => {
          this.openApp();
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  /**
   * 跳转主应用：通过 postCardAction 发送 router 事件。
   */
  private openApp(): void {
    const action: RouterAction = {
      action: 'router',
      abilityName: 'EntryAbility'
    };
    postCardAction(this, action);
  }
}
