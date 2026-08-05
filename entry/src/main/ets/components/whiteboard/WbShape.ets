/**
 * WbShapeData — 白板形状数据模型。
 * 对应 Logseq Whiteboards 的 frame/shape 数据结构。
 */
export interface WbShapeData {
  id: string;
  type: string;          // 'rect' | 'ellipse' | 'diamond' | 'text' | 'line'
  x: number;
  y: number;
  width: number;
  height: number;
  text: string;
  fillColor: string;
  borderColor: string;
  rotation: number;
}

/**
 * 缩放手柄位置信息。
 */
interface HandlePosition {
  x: number;
  y: number;
}

/**
 * WbShape — 白板形状渲染组件。
 *
 * 职责：
 *  - 根据 type 渲染矩形/椭圆/菱形/文本/线条
 *  - 选中状态：蓝色边框 + 4 角缩放手柄 + 顶部旋转手柄
 *  - 文本编辑：isEditing 为 true 时显示 TextArea
 *  - 通过 onTextChange 回调通知父组件文本变更
 */
@Component
export struct WbShape {
  @Prop shape: WbShapeData;
  @Prop isSelected: boolean = false;
  // 命名 zoomScale，避免与组件 scale() 属性方法冲突
  @Prop zoomScale: number = 1;
  @Prop @Watch('onEditingChange') isEditing: boolean = false;
  @State editText: string = '';

  onTextChange: (id: string, text: string) => void = (id: string, text: string) => {};

  aboutToAppear(): void {
    this.editText = this.shape.text;
  }

  /**
   * isEditing 变化时同步 editText。
   */
  onEditingChange(): void {
    if (this.isEditing) {
      this.editText = this.shape.text;
    }
  }

  /**
   * 渲染形状内容（根据 type 分支）。
   */
  @Builder ShapeContent() {
    if (this.shape.type === 'rect') {
      Row() {
        Text(this.shape.text)
          .fontSize(14)
          .fontColor($r('app.color.text'))
          .textAlign(TextAlign.Center)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.shape.fillColor)
      .border({ width: 1.5, color: this.shape.borderColor })
      .borderRadius(4)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .padding(8)
    } else if (this.shape.type === 'ellipse') {
      Row() {
        Text(this.shape.text)
          .fontSize(14)
          .fontColor($r('app.color.text'))
          .textAlign(TextAlign.Center)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.shape.fillColor)
      .border({ width: 1.5, color: this.shape.borderColor })
      .borderRadius('50%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .padding(8)
    } else if (this.shape.type === 'diamond') {
      Row() {
        Text(this.shape.text)
          .fontSize(14)
          .fontColor($r('app.color.text'))
          .textAlign(TextAlign.Center)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.shape.fillColor)
      .border({ width: 1.5, color: this.shape.borderColor })
      .borderRadius(4)
      .rotate({ angle: 45 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .padding(8)
    } else if (this.shape.type === 'text') {
      if (this.isEditing) {
        TextArea({ text: this.editText })
          .fontSize(14)
          .fontColor($r('app.color.text'))
          .backgroundColor(Color.Transparent)
          .borderWidth(0)
          .constraintSize({ maxWidth: '100%' })
          .onChange((value: string) => {
            this.editText = value;
            this.onTextChange(this.shape.id, value);
          })
      } else {
        Text(this.shape.text)
          .fontSize(14)
          .fontColor($r('app.color.text'))
          .maxLines(10)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    } else if (this.shape.type === 'line') {
      Shape() {
        Path()
          .commands('M 0 0 L ' + (this.shape.width * this.zoomScale) + ' ' + (this.shape.height * this.zoomScale))
          .stroke(this.shape.borderColor)
          .strokeWidth(2)
          .strokeLineCap(LineCapStyle.Round)
          .fillOpacity(0)
      }
      .width('100%')
      .height('100%')
    } else {
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor(this.shape.fillColor)
        .border({ width: 1.5, color: this.shape.borderColor })
        .borderRadius(4)
    }
  }

  /**
   * 计算四角缩放手柄位置。
   */
  private getCornerHandles(): HandlePosition[] {
    const w = this.shape.width * this.zoomScale;
    const h = this.shape.height * this.zoomScale;
    const handles: HandlePosition[] = [];
    handles[0] = { x: -4, y: -4 };                           // top-left
    handles[1] = { x: w - 4, y: -4 };                        // top-right
    handles[2] = { x: -4, y: h - 4 };                        // bottom-left
    handles[3] = { x: w - 4, y: h - 4 };                     // bottom-right
    return handles;
  }

  /**
   * 渲染选中状态手柄（4 角 + 旋转）。
   */
  @Builder SelectionHandles() {
    Stack() {
      ForEach(this.getCornerHandles(), (hp: HandlePosition, index: number) => {
        Circle({ width: 8, height: 8 })
          .fill(Color.White)
          .stroke($r('app.color.primary'))
          .strokeWidth(1.5)
          .position({ x: hp.x, y: hp.y })
      }, (hp: HandlePosition, index: number) => `${index}`)
      // 旋转手柄连线（startPoint/endPoint 仅接受 [x, y] 数组）
      Line()
        .startPoint([this.shape.width * this.zoomScale / 2, 0])
        .endPoint([this.shape.width * this.zoomScale / 2, -10])
        .stroke($r('app.color.primary'))
        .strokeWidth(1.5)
      // 旋转手柄圆点
      Circle({ width: 8, height: 8 })
        .fill($r('app.color.primary'))
        .position({ x: this.shape.width * this.zoomScale / 2 - 4, y: -18 })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      this.ShapeContent()
      if (this.isSelected) {
        Column()
          .width('100%')
          .height('100%')
          .border({ width: 2, color: $r('app.color.primary') })
          .borderRadius(4)
        this.SelectionHandles()
      }
    }
    .width(this.shape.width * this.zoomScale)
    .height(this.shape.height * this.zoomScale)
    .rotate({ angle: this.shape.rotation })
  }
}
