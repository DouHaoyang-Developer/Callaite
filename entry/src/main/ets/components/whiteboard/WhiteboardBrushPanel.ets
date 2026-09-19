import { TablerIcon } from '../common/Icons';
import { PenKitService, PenBrushType, BrushPresetItem } from '../../services/PenKitService';

/**
 * WhiteboardBrushPanel —— 笔刷选择面板（笔迹引擎标识 + 4 笔刷 + 颜色 + 粗细）。
 *
 * 对齐示例组件划分：展示组件 + 单例服务（PenKitService）直连，
 * 笔刷状态经 @Link 与父组件（Whiteboard）双向同步。
 */
@Component
export struct WhiteboardBrushPanel {
  @Link currentBrushType: PenBrushType;
  @Link currentBrushColor: number;
  @Link currentBrushSize: number;
  /** 手写套件能力（官方 SysCap 运行时探测结果，由父组件传入） */
  @Prop handwriteCapable: boolean = false;
  private penKit: PenKitService = PenKitService.getInstance();

  private brushIcon(type: PenBrushType): string {
    if (type === PenBrushType.PEN) {
      return 'ballpen';
    }
    if (type === PenBrushType.PENCIL) {
      return 'pencil';
    }
    if (type === PenBrushType.MARKER) {
      return 'highlight';
    }
    return 'eraser';
  }

  private engineName(): string {
    return this.handwriteCapable ? 'Pen Kit 原生' : 'Canvas 压感';
  }

  build() {
    Column({ space: 10 }) {
      // 笔迹引擎标识（运行时 SysCap 探测）
      Row({ space: 6 }) {
        TablerIcon('pencil', 12, $r('app.color.muted_text'))
        Text('笔迹引擎: ' + this.engineName())
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
        if (this.handwriteCapable) {
          Text('原生管线已就绪')
            .fontSize(10)
            .fontColor($r('app.color.primary'))
        } else {
          Text('SysCap 未支持 · Canvas 兜底')
            .fontSize(10)
            .fontColor($r('app.color.muted_text'))
        }
      }
      .alignItems(VerticalAlign.Center)

      // 笔刷类型
      Row({ space: 8 }) {
        ForEach(this.penKit.getBrushPresets(), (preset: BrushPresetItem) => {
          Column({ space: 2 }) {
            TablerIcon(this.brushIcon(preset.type), 16,
              this.currentBrushType === preset.type ? $r('app.color.primary') : $r('app.color.text'))
            Text(preset.label)
              .fontSize(9)
              .fontColor(this.currentBrushType === preset.type ? $r('app.color.primary') : $r('app.color.muted_text'))
          }
          .width(48)
          .height(40)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(6)
          .backgroundColor(this.currentBrushType === preset.type ? $r('app.color.surface2') : Color.Transparent)
          .onClick(() => {
            this.penKit.setBrushType(preset.type);
            this.currentBrushType = preset.type;
          })
        }, (preset: BrushPresetItem) => preset.type)
      }

      // 颜色选择
      Row({ space: 8 }) {
        ForEach(this.penKit.getPresetColors(), (color: number, index: number) => {
          Row()
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(PenKitService.colorToHex(color))
            .border({
              width: this.currentBrushColor === color ? 2 : 1,
              color: this.currentBrushColor === color ? $r('app.color.primary') : $r('app.color.border')
            })
            .onClick(() => {
              this.penKit.setBrushColor(color);
              this.currentBrushColor = color;
            })
        }, (color: number, index: number) => index.toString())
      }

      // 粗细滑块
      Row({ space: 8 }) {
        Text('细')
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
        Slider({ value: this.currentBrushSize, min: 1, max: 20, step: 1 })
          .layoutWeight(1)
          .onChange((value: number) => {
            const rounded = Math.round(value);
            this.penKit.setBrushSize(rounded);
            this.currentBrushSize = rounded;
          })
        Text('粗')
          .fontSize(10)
          .fontColor($r('app.color.muted_text'))
        Text(this.currentBrushSize.toString())
          .fontSize(11)
          .fontColor($r('app.color.text'))
          .width(24)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.surface0'))
  }
}
