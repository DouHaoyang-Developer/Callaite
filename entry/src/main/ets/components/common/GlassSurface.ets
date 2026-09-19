import { ConfigurationConstant } from '@kit.AbilityKit';

/**
 * GlassMode — 玻璃材质实现方式。
 *  - material：backgroundBlurStyle COMPONENT 材质（自适应明暗，适合停靠面板）
 *  - effect：backgroundEffect 自定义模糊（亮度提升 + 饱和度增益，"光感"更强，适合悬浮件）
 */
export enum GlassMode {
  MATERIAL = 0,
  EFFECT = 1
}

/**
 * GlassSurface — 鸿蒙玻璃光感容器（毛玻璃 + 顶部高光渐层 + 描边 + 投影）。
 *
 * 用法：
 *   GlassSurface({ radius: 20, fill: $r('app.color.glass_fill'), mode: GlassMode.EFFECT }) {
 *     Row() { ... }   // 内容
 *   }
 *
 * 高光层（specular sheen）模拟光在玻璃边缘的反射，是"光感"的关键；
 * hitTestBehavior(None) 保证不拦截触摸事件。
 */
@Component
export struct GlassSurface {
  @Prop radius: number = 16;
  @Prop fill: ResourceColor = $r('app.color.glass_fill');
  @Prop mode: number = GlassMode.MATERIAL;
  // 注意：材质级别不再开放为 @Prop —— CustomComponent 基类已声明 blur 属性方法，
  // 同名字段会产生联合类型冲突；此处固定为 COMPONENT 材质。
  @Prop shadowRadius: number = 14;
  @Prop shadowAlpha: number = 0.10;
  @Prop sheen: ResourceColor = $r('app.color.glass_sheen');
  @BuilderParam content: () => void = this.emptyContent;
  @StorageLink('themeMode') themeMode: string = 'system';
  @StorageLink('callaite_systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

  private isDark(): boolean {
    if (this.themeMode === 'dark') {
      return true;
    }
    if (this.themeMode === 'light') {
      return false;
    }
    return this.systemColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private shadowColor(): string {
    return this.isDark() ? 'rgba(0,0,0,0.45)' : 'rgba(15,18,30,' + this.shadowAlpha.toString() + ')';
  }

  @Builder
  emptyContent() {
  }

  build() {
    Stack() {
      // 内容层
      this.content()

      // 高光层 — 顶部斜向渐变，模拟玻璃反光
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 165,
          colors: [[this.sheen, 0.0], ['rgba(255,255,255,0)', 0.55]]
        })
        .hitTestBehavior(HitTestMode.None)
        .borderRadius(this.radius)
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.radius)
    .backgroundColor(this.fill)
    // MATERIAL：COMPONENT 材质（自适应明暗）；EFFECT：置 NONE 关闭，由 backgroundEffect 接管
    .backgroundBlurStyle(this.mode === GlassMode.MATERIAL ? BlurStyle.COMPONENT_REGULAR : BlurStyle.NONE, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 1.0
    })
    // EFFECT：自定义模糊 + 饱和度/亮度增益（光感核心）；MATERIAL 时半径 0 全透明（no-op）
    .backgroundEffect({
      radius: this.mode === GlassMode.EFFECT ? 36 : 0,
      color: this.mode === GlassMode.EFFECT ? 'rgba(255,255,255,0.01)' : 'rgba(255,255,255,0)',
      saturation: 1.25,
      brightness: this.isDark() ? 1.0 : 1.06
    })
    .border({ width: 0.6, color: $r('app.color.glass_border') })
    .shadow({ radius: this.shadowRadius, color: this.shadowColor(), offsetY: 4 })
    .clip(true)
  }
}
