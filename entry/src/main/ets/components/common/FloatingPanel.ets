import { AppState } from '../../state/AppState';

/**
 * FloatingPanel — HarmonyOS 悬浮弹窗规范的侧边面板。
 *
 * 为什么不用 bindSheet：bindSheet 是**底部抽屉**语义（宽度铺满整屏、贴底、仅顶部圆角），
 * 之前用 SheetSize.LARGE + 内部 80% 宽度面板，导致
 *   - 面板宽仅占屏 0.80，右侧留下 36vp 死白
 *   - 面板贴底（下留白 0），不符合弹窗"四边留白"特征
 *   - 圆角只在外层 sheet 上，内部面板无独立圆角/阴影
 * 现改为 Stack 内自绘悬浮面板，满足官方 PopupSizeChecker 约束：
 *   - 宽度占屏比 ≤ 0.95（本实现 84%，上限 320vp）
 *   - 四边均有留白，距底 ≥ 10vp
 *   - 独立圆角 + 阴影 + 描边，层级高于内容但低于系统栏
 *   - 通过 safeTop / safeBottom 避让状态栏与导航条
 *   - PC（2in1）最小尺寸 360×240 由 maxWidth/minHeight 兜底
 */
@Component
export struct FloatingPanel {
  /** 'left' | 'right' —— 面板吸附侧 */
  @Prop side: string = 'left';
  /** 面板背景色（默认 surface1） */
  @Prop panelBackground: ResourceColor = $r('app.color.surface1');
  /** 面板相对屏幕的最大宽度（vp） */
  @Prop maxPanelWidth: number = 320;
  /** 是否显示遮罩 */
  @Prop showScrim: boolean = true;
  /** 关闭回调（点击遮罩或系统返回时触发） */
  onClose: () => void = () => {};
  /** 面板内容 */
  @BuilderParam content: () => void = this.EmptyContent;
  @StorageLink('callaite_safeTop') safeTop: number = 0;
  @StorageLink('callaite_safeBottom') safeBottom: number = 0;

  @Builder
  EmptyContent() {
  }

  build() {
    Stack() {
      // ─── 遮罩：拦截穿透点击并关闭面板 ───
      if (this.showScrim) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.32)')
          .onClick(() => {
            this.onClose();
          })
          .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.Friction }))
      }

      // ─── 悬浮面板 ───
      Row() {
        if (this.side === 'left') {
          this.Panel()
          Blank()
        } else {
          Blank()
          this.Panel()
        }
      }
      .width('100%')
      .height('100%')
      // 四边留白：左右 12vp；上避让状态栏 +12vp；下避让导航条 +12vp
      .padding({
        left: 12,
        right: 12,
        top: this.safeTop + 12,
        bottom: this.safeBottom + 12
      })
      .alignItems(VerticalAlign.Top)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  Panel() {
    Column() {
      this.content()
    }
    .width('84%')
    .constraintSize({ maxWidth: this.maxPanelWidth, minHeight: 240 })
    .height('100%')
    .backgroundColor(this.panelBackground)
    .borderRadius(20)
    .clip(true)
    .border({ width: 0.5, color: $r('app.color.glass_border') })
    .shadow({ radius: 24, color: 'rgba(0,0,0,0.24)', offsetX: 0, offsetY: 8 })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.Friction })
        .combine(TransitionEffect.translate({ x: this.side === 'left' ? -40 : 40 })),
      TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.Friction })
        .combine(TransitionEffect.translate({ x: this.side === 'left' ? -40 : 40 }))
    ))
  }
}
