import { ConfigurationConstant } from '@kit.AbilityKit';
import { MaterialRole, MaterialSpec, ImmersiveMaterialResolver } from '../../theme/MaterialTokens';
import { uiMaterial } from '@kit.ArkUI';

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
  /**
   * 沉浸光感材质角色（传入后由 MaterialTokens 统一驱动模糊/填充/高光/阴影参数）。
   * 传 -1 表示不启用，沿用上面各手动 @Prop —— 保证向后兼容。
   */
  @Prop materialRole: number = -1;
  @State pressed: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;
  @StorageLink('themeMode') themeMode: string = 'system';
  @StorageLink('callaite_systemColorMode') systemColorMode: number =
    ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;

  /** 当前生效的材质参数；未指定角色时返回 undefined */
  private spec(): MaterialSpec | undefined {
    if (this.materialRole < 0) {
      return undefined;
    }
    return ImmersiveMaterialResolver.specOf(this.materialRole as MaterialRole);
  }

  /** 背景模糊半径：Token 优先，否则沿用 EFFECT 模式的 36vp */
  private blurRadiusValue(): number {
    const s = this.spec();
    if (s !== undefined) {
      return s.blurRadius;
    }
    return this.mode === GlassMode.EFFECT ? 36 : 0;
  }

  /** 高光层强度：Token 的 sheenAlpha 相对基准 0.30 归一化 */
  private sheenOpacity(): number {
    const s = this.spec();
    if (s === undefined) {
      return 1;
    }
    const v = s.sheenAlpha / 0.30;
    return v > 1 ? 1 : v;
  }

  /** 投影半径：Token 优先 */
  private shadowRadiusValue(): number {
    const s = this.spec();
    return s !== undefined ? s.shadowRadius : this.shadowRadius;
  }

  /** 投影不透明度：Token 优先 */
  private shadowAlphaValue(): number {
    const s = this.spec();
    return s !== undefined ? s.shadowAlpha : this.shadowAlpha;
  }

  /**
   * 系统沉浸材质对象（API 26）。
   * 支持则返回 ImmersiveMaterial 交给 systemMaterial 渲染；
   * 不支持返回 undefined（等价于"无系统材质"，走自研降级参数）。
   */
  // 供外壳迁移到 Navigation/NavDestination 后启用的系统材质入口：
  // private systemMaterialObject(): uiMaterial.Material | undefined {
  //   return ImmersiveMaterialResolver.buildSystemMaterial(this.materialRole as MaterialRole);
  // }
  // （当前阶段不启用，见 build() 中注释说明）
  private unusedRef(): void { ImmersiveMaterialResolver.specOf(this.materialRole as MaterialRole); }

  /** 是否启用按压弹性反馈（官方沉浸光感六特性之一） */
  private isInteractive(): boolean {
    const s = this.spec();
    return s !== undefined && s.interactive;
  }

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
    return this.isDark() ? 'rgba(0,0,0,0.45)' : 'rgba(15,18,30,' + this.shadowAlphaValue().toString() + ')';
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
        // 高光强度由材质档位驱动：越薄越通透、高光越明显
        .opacity(this.sheenOpacity())
        .hitTestBehavior(HitTestMode.None)
        .borderRadius(this.radius)
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.radius)
    // ⚠️ 此处刻意【不】调用 systemMaterial：
    // 官方 API 参考明确其"仅在 Navigation/NavDestination 的标题栏，或横向 Tabs 的底部 TabBar 中生效"；
    // 本组件位于自研 Stack/Row 容器内，实测（API 26 模拟器）在生效范围外调用会导致
    // 首次启动 THREAD_BLOCK_6S 冻结与启动不稳定。待外壳迁移到 Navigation 后再启用。
    // 当前以 MaterialTokens 的降级参数（模糊/填充/高光/阴影）实现等效视觉。
    .backgroundColor(this.fill)
    // MATERIAL：COMPONENT 材质（自适应明暗）；EFFECT：置 NONE 关闭，由 backgroundEffect 接管
    .backgroundBlurStyle(this.mode === GlassMode.MATERIAL ? BlurStyle.COMPONENT_REGULAR : BlurStyle.NONE, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 1.0
    })
    // EFFECT：自定义模糊 + 饱和度/亮度增益（光感核心）；模糊半径由材质档位 Token 驱动
    .backgroundEffect({
      radius: this.blurRadiusValue(),
      color: this.mode === GlassMode.EFFECT ? 'rgba(255,255,255,0.01)' : 'rgba(255,255,255,0)',
      saturation: 1.25,
      brightness: this.isDark() ? 1.0 : 1.06
    })
    .border({ width: 0.6, color: $r('app.color.glass_border') })
    .shadow({ radius: this.shadowRadiusValue(), color: this.shadowColor(), offsetY: 4 })
    // 按压弹性反馈（官方沉浸光感六特性之一）：仅 interactive 档位启用
    .scale({
      x: this.isInteractive() && this.pressed ? 0.97 : 1,
      y: this.isInteractive() && this.pressed ? 0.97 : 1
    })
    .animation({ duration: 160, curve: Curve.Friction })
    .onTouch((event: TouchEvent) => {
      if (!this.isInteractive()) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .clip(true)
  }
}
