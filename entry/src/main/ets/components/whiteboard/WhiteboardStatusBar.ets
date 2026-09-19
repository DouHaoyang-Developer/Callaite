import { TablerIcon } from '../common/Icons';

/**
 * WhiteboardStatusBar —— 白板底部状态栏（纯展示组件）。
 * 统计/引擎/选中态由父组件传入；引擎名由 handwriteCapable 推导。
 */
@Component
export struct WhiteboardStatusBar {
  @Prop currentTool: string = 'select';
  @Prop shapeCount: number = 0;
  @Prop connectorCount: number = 0;
  @Prop strokeCount: number = 0;
  @Prop hasSelection: boolean = false;
  @Prop penAvailable: boolean = false;
  @Prop handwriteCapable: boolean = false;

  private engineName(): string {
    return this.handwriteCapable ? 'Pen Kit 原生' : 'Canvas 压感';
  }

  build() {
    Row({ space: 12 }) {
      Text('工具: ' + this.currentTool)
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text('·')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text(this.shapeCount + ' 形状')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text('·')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text(this.connectorCount + ' 连线')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text('·')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Text(this.strokeCount + ' 笔触')
        .fontSize(11)
        .fontColor($r('app.color.muted_text'))
      Blank()
      if (this.hasSelection) {
        Text('已选中')
          .fontSize(11)
          .fontColor($r('app.color.primary'))
      }
      if (this.currentTool === 'pen') {
        Text(this.penAvailable ? '手写笔' : '触摸模式')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text('·')
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
        Text('引擎: ' + this.engineName())
          .fontSize(11)
          .fontColor($r('app.color.muted_text'))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.surface0'))
  }
}
