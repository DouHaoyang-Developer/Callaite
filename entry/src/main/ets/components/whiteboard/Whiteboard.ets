import { AppState } from '../../state/AppState';
import { TablerIcon } from '../common/Icons';

/**
 * Whiteboard — 白板画布。
 * 对应 Logseq Whiteboards 功能，Lunius Canvas 参考。
 * P6 MVP: 无限画布 + 缩放 + 待扩展形状/连线工具。
 */
@Component
export struct Whiteboard {
  @State private scaleValue: number = 1;

  build() {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Row() { TablerIcon('arrow-left', 18, $r('app.color.text')) }
        .width(32).height(32)
        .onClick(() => { AppState.setCurrentPage('Journal'); })

        Text('白板')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.text'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      // 画布区域
      Stack() {
        Column() {
          Text('白板画布')
            .fontSize(24).fontColor($r('app.color.muted_text'))
          Text('缩放: ' + this.scaleValue.toFixed(1) + 'x')
            .fontSize(13).fontColor($r('app.color.muted_text'))
          Text('拖拽 / 捏合以缩放平移')
            .fontSize(12).fontColor($r('app.color.muted_text'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.surface1'))
        .gesture(
          PinchGesture({ fingers: 2 })
            .onActionUpdate((event: GestureEvent) => {
              this.scaleValue = Math.max(0.2, Math.min(3, event.scale));
            })
        )
      }
      .width('100%')
      .layoutWeight(1)

      // 工具栏
      Row({ space: 8 }) {
        Text('矩形').fontSize(12).fontColor($r('app.color.muted_text'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4).backgroundColor($r('app.color.surface2'))
        Text('椭圆').fontSize(12).fontColor($r('app.color.muted_text'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4).backgroundColor($r('app.color.surface2'))
        Text('文本').fontSize(12).fontColor($r('app.color.muted_text'))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(4).backgroundColor($r('app.color.surface2'))
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.surface0'))
  }
}
