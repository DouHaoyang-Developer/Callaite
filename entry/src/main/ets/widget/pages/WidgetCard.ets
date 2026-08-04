/**
 * WidgetCard — 桌面服务卡片 UI。
 *
 * 显示应用名称 + 页面数 + 最新 Block 预览。
 * 2×2 尺寸卡片，点击跳转主应用。
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('title') title: string = 'Callaite';
  @LocalStorageProp('pageCount') pageCount: string = '0';
  @LocalStorageProp('preview1') preview1: string = '';
  @LocalStorageProp('preview2') preview2: string = '';
  @LocalStorageProp('preview3') preview3: string = '';

  build() {
    Column({ space: 4 }) {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')
        .maxLines(1)

      Text(this.pageCount + ' 个页面')
        .fontSize(11)
        .fontColor('#9CA3AF')

      if (this.preview1 !== '') {
        Text(this.preview1)
          .fontSize(10)
          .fontColor('#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.preview2 !== '') {
        Text(this.preview2)
          .fontSize(10)
          .fontColor('#6B7280')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }
}
