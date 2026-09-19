/**
 * SplitDivider —— 内容区左右分屏的可拖拽分隔条（对齐 Obsidian 桌面分屏）。
 *
 * 交互：
 *   · 悬停   —— 中线高亮，提示可拖拽
 *   · 拖拽   —— PanGesture 水平位移换算为左窗格宽度比例
 *   · 双击   —— 复位为 50%
 * 无障碍：热区宽度 10vp（中线视觉 1vp），满足官方点击热区下限要求。
 */
@Component
export struct SplitDivider {
  /** 当前左窗格宽度占比（0.2 – 0.8） */
  @Prop ratio: number = 0.5;
  /** 分屏容器总宽度（vp），用于把像素位移换算为比例 */
  @Prop totalWidth: number = 0;
  /** 拖拽回调：返回新的左窗格占比 */
  onRatioChange: (r: number) => void = () => {};
  @State hovered: boolean = false;
  @State dragging: boolean = false;
  /**
   * 手势起始时的占比快照。
   * PanGesture.onActionUpdate 的 offsetX 是**相对手势起点**的累计位移，
   * 若直接叠加到实时更新的 ratio 上会二次累加（实测位移被放大近 2 倍），
   * 因此必须以起始快照为基准计算。
   */
  @State startRatio: number = 0;

  private static readonly MIN_RATIO: number = 0.2;
  private static readonly MAX_RATIO: number = 0.8;

  private clamp(v: number): number {
    if (v < SplitDivider.MIN_RATIO) {
      return SplitDivider.MIN_RATIO;
    }
    if (v > SplitDivider.MAX_RATIO) {
      return SplitDivider.MAX_RATIO;
    }
    return v;
  }

  build() {
    Row() {
      // 中线
      Column()
        .width(this.hovered || this.dragging ? 2 : 1)
        .height('100%')
        .backgroundColor(this.dragging
          ? $r('app.color.primary')
          : (this.hovered ? $r('app.color.surface3') : $r('app.color.border')))
        .animation({ duration: 120, curve: Curve.EaseOut })
    }
    .width(10)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 1 })
        .onActionStart(() => {
          this.dragging = true;
          this.startRatio = this.ratio;
        })
        .onActionUpdate((event: GestureEvent) => {
          if (this.totalWidth <= 0) {
            return;
          }
          // 以起始快照为基准，避免二次累加
          const next = this.clamp(this.startRatio + event.offsetX / this.totalWidth);
          this.onRatioChange(next);
        })
        .onActionEnd(() => {
          this.dragging = false;
        })
    )
    .onClick(() => {
      // 单击复位为均分（拖拽由 PanGesture 消费，不会误触发）
      this.onRatioChange(0.5);
    })
  }
}
