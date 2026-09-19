import { uiMaterial } from '@kit.ArkUI';

/**
 * MaterialRole —— 沉浸光感材质角色（对齐 HarmonyOS 7 官方"沉浸光感"场景规范）。
 *
 * 官方规范（设计指南 · 沉浸光感）：不同位置/存在方式的交互组件应使用不同材质档位
 *   · 顶部悬浮组件      → ULTRA_THIN，并结合渐变模糊延展顶部内容展示空间
 *   · 底部悬浮组件      → THIN，并结合渐变颜色蒙层延展底部内容展示空间
 *   · 非常驻、任意位置弹出 → THICK，保证复杂场景下内容可读性
 *   · 半模态 / 弹出框    → ULTRA_THICK，面积大、内容丰富度强
 *   · 常规内容承载      → REGULAR（ImmersiveMaterial 默认档）
 *
 * 项目落位映射见 MATERIAL_SPECS。
 */
export enum MaterialRole {
  /** 顶部悬浮（移动端玻璃顶栏） */
  TOP_FLOATING = 0,
  /** 底部悬浮（移动端玻璃胶囊栏） */
  BOTTOM_FLOATING = 1,
  /** 任意位置弹出的临时浮层（侧边悬浮面板） */
  TRANSIENT = 2,
  /** 半模态 / 弹窗（菜单面板） */
  MODAL = 3,
  /** 常规内容承载（停靠面板、卡片） */
  CONTENT = 4
}

/**
 * MaterialSpec —— 单档材质的完整参数。
 *
 * 设计意图：把"视觉强度"收口为**语义 Token**，页面不再散落模糊半径/阴影/透明度数值
 * （对应官方最佳实践中"把材质参数收口到 Token"的工程要求）。
 * 字段全为原始类型，便于在 ArkTS 中做 @State/@Prop 传递。
 */
export interface MaterialSpec {
  /** 角色标识 */
  role: MaterialRole;
  /** 官方材质厚度档位（0=ULTRA_THIN … 4=ULTRA_THICK） */
  styleIndex: number;
  /** 降级路径：背景模糊半径（vp） */
  blurRadius: number;
  /** 降级路径：材质填充不透明度（0–1） */
  fillAlpha: number;
  /** 降级路径：顶部高光层强度（0–1） */
  sheenAlpha: number;
  /** 降级路径：投影半径（vp） */
  shadowRadius: number;
  /** 降级路径：投影不透明度（0–1） */
  shadowAlpha: number;
  /** 是否启用按压缩放反馈 */
  interactive: boolean;
  /** 是否启用触点光感反馈 */
  lightEffect: boolean;
  /** 可读的档位名称，便于埋点与调试 */
  levelName: string;
}

/**
 * 项目材质 Token 表 —— 官方五档语义 → 具体落位与参数。
 *
 * 参数推导原则（与官方档位"厚度"单调一致）：
 *   越薄 → 模糊越小、越通透、高光越明显、阴影越轻
 *   越厚 → 模糊越强、越遮蔽底层、高光越弱、阴影越重
 */
export const MATERIAL_SPECS: MaterialSpec[] = [
  // ULTRA_THIN —— 顶部悬浮
  {
    role: MaterialRole.TOP_FLOATING, styleIndex: 0,
    blurRadius: 12, fillAlpha: 0.55, sheenAlpha: 0.30,
    shadowRadius: 10, shadowAlpha: 0.10,
    interactive: false, lightEffect: false, levelName: 'ULTRA_THIN'
  },
  // THIN —— 底部悬浮
  {
    role: MaterialRole.BOTTOM_FLOATING, styleIndex: 1,
    blurRadius: 18, fillAlpha: 0.66, sheenAlpha: 0.24,
    shadowRadius: 20, shadowAlpha: 0.16,
    interactive: true, lightEffect: true, levelName: 'THIN'
  },
  // THICK —— 任意位置弹出的临时浮层
  {
    role: MaterialRole.TRANSIENT, styleIndex: 3,
    blurRadius: 28, fillAlpha: 0.86, sheenAlpha: 0.14,
    shadowRadius: 24, shadowAlpha: 0.24,
    interactive: false, lightEffect: false, levelName: 'THICK'
  },
  // ULTRA_THICK —— 半模态 / 弹窗
  {
    role: MaterialRole.MODAL, styleIndex: 4,
    blurRadius: 36, fillAlpha: 0.94, sheenAlpha: 0.08,
    shadowRadius: 28, shadowAlpha: 0.28,
    interactive: false, lightEffect: false, levelName: 'ULTRA_THICK'
  },
  // REGULAR —— 常规内容承载
  {
    role: MaterialRole.CONTENT, styleIndex: 2,
    blurRadius: 22, fillAlpha: 0.78, sheenAlpha: 0.18,
    shadowRadius: 14, shadowAlpha: 0.12,
    interactive: false, lightEffect: false, levelName: 'REGULAR'
  }
];

/**
 * ImmersiveMaterialResolver —— 系统沉浸材质能力探测与构造。
 *
 * 两条路径（对应官方"双轨适配"中的普通组件轨道）：
 *   1. 系统材质可用  → 构造 uiMaterial.ImmersiveMaterial，交由 systemMaterial 渲染
 *   2. 系统材质不可用 → 退回自研 GlassSurface 的降级参数（MATERIAL_SPECS）
 *
 * 重要约束（官方 API 参考原文）：
 *   "通过 systemMaterial 设置组件的系统材质时，仅在 Navigation 或 NavDestination 的标题栏，
 *    或横向 Tabs 中 barPosition 为 BarPosition.End 的底部 TabBar 中生效。"
 *   → 本项目外壳由自定义 Column/Row + GlassSurface 构成，**不在该生效范围内**，
 *     因此当前以"路径 2"为主；待外壳迁移到 Navigation/NavDestination 后即可无缝切到路径 1。
 */
export class ImmersiveMaterialResolver {
  private static supportedCache: number = -1;   // -1 未知 / 0 不支持 / 1 支持

  /**
   * 设备是否支持沉浸式系统材质。
   * 官方建议设置 ImmersiveMaterial 前先用 isImmersiveMaterialSupported() 判断，
   * 不支持的设备上设置该材质"可设置但无效果"。
   */
  static isSystemMaterialSupported(): boolean {
    if (ImmersiveMaterialResolver.supportedCache >= 0) {
      return ImmersiveMaterialResolver.supportedCache === 1;
    }
    let ok = false;
    try {
      ok = uiMaterial.isImmersiveMaterialSupported();
    } catch (e) {
      // 低于 API 26 的设备无该接口，视为不支持
      ok = false;
    }
    ImmersiveMaterialResolver.supportedCache = ok ? 1 : 0;
    return ok;
  }

  /**
   * 当前设备的材质等级（由设备算力决定，不可设置）。
   * EXQUISITE=高算力 / GENTLE=中算力 / SMOOTH=低算力。
   */
  static deviceLevelName(): string {
    try {
      const lv: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      if (lv === uiMaterial.MaterialLevel.EXQUISITE) {
        return 'EXQUISITE';
      }
      if (lv === uiMaterial.MaterialLevel.GENTLE) {
        return 'GENTLE';
      }
      return 'SMOOTH';
    } catch (e) {
      return 'UNKNOWN';
    }
  }

  /** 角色 → 官方档位枚举 */
  private static styleOf(role: MaterialRole): uiMaterial.ImmersiveStyle {
    if (role === MaterialRole.TOP_FLOATING) {
      return uiMaterial.ImmersiveStyle.ULTRA_THIN;
    }
    if (role === MaterialRole.BOTTOM_FLOATING) {
      return uiMaterial.ImmersiveStyle.THIN;
    }
    if (role === MaterialRole.TRANSIENT) {
      return uiMaterial.ImmersiveStyle.THICK;
    }
    if (role === MaterialRole.MODAL) {
      return uiMaterial.ImmersiveStyle.ULTRA_THICK;
    }
    return uiMaterial.ImmersiveStyle.REGULAR;
  }

  /** 取角色的降级参数 */
  static specOf(role: MaterialRole): MaterialSpec {
    for (let i = 0; i < MATERIAL_SPECS.length; i++) {
      if (MATERIAL_SPECS[i].role === role) {
        return MATERIAL_SPECS[i];
      }
    }
    return MATERIAL_SPECS[MATERIAL_SPECS.length - 1];
  }

  /**
   * 构造系统沉浸材质对象；设备不支持时返回 undefined（调用方应退回自研玻璃参数）。
   *
   * 参数要点（均来自官方声明文件默认值）：
   *   · style        默认 REGULAR
   *   · interactive  默认 false —— 按压缩放反馈
   *   · lightEffect  默认 undefined —— 触点光感；传 null 关闭
   *   · applyShadow  默认 true —— **材质阴影优先于通用 shadow 属性**；
   *                  本项目自研阴影已按 MaterialSpec 调参，这里显式置 false 以免被覆盖
   *   · colorInvert  需要至少 THIN/ULTRA_THIN 档位才可能生效，故仅在薄档开启
   */
  static buildSystemMaterial(role: MaterialRole): uiMaterial.Material | undefined {
    if (!ImmersiveMaterialResolver.isSystemMaterialSupported()) {
      return undefined;
    }
    const spec: MaterialSpec = ImmersiveMaterialResolver.specOf(role);
    try {
      return new uiMaterial.ImmersiveMaterial({
        style: ImmersiveMaterialResolver.styleOf(role),
        interactive: spec.interactive,
        lightEffect: spec.lightEffect ? { color: Color.White } : null,
        // 自研阴影优先，避免材质自带阴影覆盖 GlassSurface 的投影调参
        applyShadow: false,
        // 自动反色仅在足够薄的档位有意义
        colorInvert: spec.styleIndex <= 1
      });
    } catch (e) {
      return undefined;
    }
  }

  /** 关闭系统材质（官方提供 Material.empty） */
  static emptyMaterial(): uiMaterial.Material {
    return uiMaterial.Material.empty;
  }
}
