/**
 * S4-W1 · DesignTokens v2 —— 系统地基（间距 / 字号 / 圆角 / 尺寸 / 行高 / 动效）
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 为什么是「ArkTS 常量模块」而不是 `resources/base/element/float.json`
 * ────────────────────────────────────────────────────────────────────────────
 * W1 必须回答的架构问题是：尺寸类令牌走**资源**（`$r('app.float.*')`）还是走
 * **ArkTS 常量**。本仓颜色走资源是因为**暗色要换值**；而间距/字号/圆角/尺寸
 * 在明暗两套下**同值**（`resources/dark/element/` 下没有 float.json 也印证了这点）。
 * 判据不是「能不能编译」，而是「**一种机制能不能覆盖全部取用位**」——
 * 全仓取用位分布（W1 普查）：
 *
 *   `space:`           314 处  ← 最大的一类
 *   `.padding({...})`  231 处
 *   `.fontSize()`      387 处
 *   `.height()/.width()` 350 处
 *   `.borderRadius()`  184 处
 *   `.lineHeight()`      1 处
 *   `duration:`         45 处
 *
 * 其中 **`space:` 是 `string | number`**（SDK `column.d.ts:68` `ColumnOptions.space`）。
 * 它要等到 **API 18** 的 `ColumnOptionsV2.space?: SpaceType` 才接受 Resource
 * （SDK `column.d.ts:103`，`@since 18`）。也就是说资源路线要么覆盖不到这 314 处，
 * 要么必须改写成 V2 形态 —— 前者会让同一个概念在仓里出现**两套写法的分叉**
 * （正是 AGENTS §7 陷阱 29 的教训：同一概念两套判据迟早分叉），
 * 后者是一次与令牌化无关的 API 形态迁移。
 *
 * ArkTS 常量则**一处定义、全位可取**，且附带三条资源路线给不了的能力：
 *   ① **拼写错误 = 编译错误**（资源名写错是运行时静默不生效 —— 本仓 `float.json`
 *      那个 `page_text_font_size` 令牌被引用 0 次，正是「静默」的现成样本）；
 *   ② **可参与算术与拼接**（`Size.TOUCH_MIN / 2`、`Space.MD * 2`）；
 *   ③ **可 grep、可计数**（W7 复测口径「新增零字面量 + 四屏文件清零」要靠它）。
 *
 * ⇒ **裁决**：**尺寸类统一走本模块**；**颜色继续走 `color.json` 资源**（暗色必需）。
 *   两条腿各管一件事，互不重叠 ⇒ 不存在「同一概念两套判据」。
 *
 * 实测证据见 `docs/docs/S4-W1-系统地基.md` §1（最小探针页装机读数；该探针页已按纪律删除）。
 *
 * ────────────────────────────────────────────────────────────────────────────
 * 用法
 * ────────────────────────────────────────────────────────────────────────────
 *   import { Space, Font, Radius, Size, LineH, Motion } from '../../utils/DesignTokens';
 *   Column({ space: Space.SM }) { ... }        // space 直接用数字令牌
 *   Text('x').fontSize(Font.BODY).padding(Space.SM).borderRadius(Radius.SM)
 *
 * ⚠️ 单位：本模块所有值均为 **vp**（字号为 **fp**，由 ArkUI 的 `.fontSize(number)`
 *    语义决定 —— 数字默认按 fp 解析）。
 */

/**
 * 间距台阶（4 基栅格）。
 *
 * `HAIR` 是**唯一的有意例外**：2vp 半栅格，只用于「图标紧邻文字」「两个 1px 描边之间」
 * 这类必须比 4vp 更紧的位置（原 `space: 2` 22 处）。它被单列出来是为了可审计 ——
 * 新代码若想用 2，必须先解释为什么 4 不行。
 */
export class Space {
  static readonly NONE: number = 0;
  /** 半栅格例外：见类注释 */
  static readonly HAIR: number = 2;
  /** 4 —— 图标与文字、相邻小控件 */
  static readonly XS: number = 4;
  /** 8 —— 默认项间距（全仓最高频） */
  static readonly SM: number = 8;
  /** 12 —— 容器内边距 */
  static readonly MD: number = 12;
  /** 16 —— 区块间距 / 大内边距 */
  static readonly LG: number = 16;
  /** 24 —— 分组间距 */
  static readonly XL: number = 24;
  /** 32 —— 大区块 / 空态留白 */
  static readonly XXL: number = 32;
}

/**
 * 字号台阶（7 档）。
 *
 * 参数化依据（`EXEC-SPRINT-04` 守卫 5「Obsidian 水平参数化」—— **对照区间读数，
 * 不做像素复刻**）：正文 15–16vp · 行高 1.5–1.6 · 标题/正文比 1.6–1.8×。
 *
 * 本表取 **正文 = 15**（落在区间内），**H1 = 25** ⇒ 25/15 = **1.667×**，落在
 * [1.6, 1.8] 的正中。原仓是 28/15 = 1.87×（超出上沿）与 19 个取值。
 *
 * ⚠️ 与取值个数无关的一条硬约束：**相邻档必须实机可分辨**。
 * 原仓 14.5/15/15.5/16 四档只差 ≤1.5vp（W20 §2.2 ink 实测）⇒ 层级成了噪声。
 * 本表最小相邻间距 = 1vp（MICRO 10 → LABEL 11），但**语义相邻的两档**（BODY_SM 13 →
 * BODY 15 → TITLE 20 → H1 25）间距为 2/5/5vp，均可分辨。
 */
export class Font {
  /** 10 —— 角标 / 极小徽标 */
  static readonly MICRO: number = 10;
  /** 11 —— 辅助文字 / 状态栏 / 标记 chip */
  static readonly CAPTION: number = 11;
  /** 12 —— chip 标签 / 次要信息 */
  static readonly LABEL: number = 12;
  /** 13 —— 列表行 / 属性行（原仓最高频档 86 处） */
  static readonly BODY_SM: number = 13;
  /** 15 —— **正文**（参数化基准） */
  static readonly BODY: number = 15;
  /** 20 —— 节标题 / 面板标题 */
  static readonly TITLE: number = 20;
  /** 25 —— 页标题（25/15 = 1.667×，落在 1.6–1.8 正中） */
  static readonly H1: number = 25;
}

/**
 * 圆角台阶（4 档 + 1 语义档）。
 *
 * 原仓 14 个取值，其中 **1 / 2 / 2.5 / 3 在实机上互相不可分辨**（纯噪声，W20 D5）
 * ⇒ 合并到 `SM`。
 * `FULL` 不是「很大的圆角」，而是**胶囊/圆形语义**：写 `borderRadius(Radius.FULL)`
 * 的盒子无论尺寸怎么变都保持胶囊形，而写 `borderRadius(12)` 的 24vp 圆点一旦改尺寸
 * 就会退化成圆角矩形 —— 原仓有 3 处这种「靠尺寸巧合成立的圆」。
 */
export class Radius {
  /** 4 —— 小控件 / 行内 chip / 标记 */
  static readonly SM: number = 4;
  /** 8 —— 按钮 / 列表行 / 图标格 */
  static readonly MD: number = 8;
  /** 12 —— 卡片 / 菜单 / 浮层 */
  static readonly LG: number = 12;
  /** 16 —— 大面板 / 对话框 */
  static readonly XL: number = 16;
  /** 胶囊 / 圆形（语义档，随尺寸自适应） */
  static readonly FULL: number = 9999;
}

/**
 * 尺寸台阶（4 基栅格）。
 *
 * ⚠️ 本表**只覆盖「可复用的控件/栏尺寸」**。原仓 `.height()` 的 31 个取值里，
 * 有一类是**一次性布局尺寸**（对话框宽 360 / 侧栏宽 280 / 画布 300×240 / 上限 420 …）
 * —— 那些**不应令牌化**：它们不是「系统的一部分」，而是某个布局的具体约束，
 * 硬套令牌只会造出 `Size.DIALOG_W` 这种一次性 token，把令牌表变成第二个字面量表。
 * 一次性尺寸的判据 = **全仓只出现 1 次且语义上属于某个具体容器**（见迁移映射表的
 * 「不收敛」段）。
 */
export class Size {
  static readonly NONE: number = 0;
  /** 1 —— 1vp 分隔线（原 `.width(1)` 缩进引导线） */
  static readonly HAIRLINE: number = 1;
  /** 2 —— 细条 / 引导线 */
  static readonly HAIR: number = 2;
  /** 4 —— 极小间距块 */
  static readonly XXS: number = 4;
  /** 8 —— 小间隙块 */
  static readonly XS: number = 8;
  /** 16 —— 小图标 */
  static readonly ICON_SM: number = 16;
  /** 20 —— 图标 / 小圆点 */
  static readonly ICON_MD: number = 20;
  /** 24 —— 小按钮 / 选择圈 / 圆点容器 */
  static readonly MD: number = 24;
  /** 28 —— 紧凑行 */
  static readonly ROW_SM: number = 28;
  /** 32 —— 标准行 / 中按钮 */
  static readonly ROW_MD: number = 32;
  /** 36 —— 工具栏行 */
  static readonly ROW_LG: number = 36;
  /**
   * 40 —— **交互元素最小尺寸**（全局热区规范，见 `HOTZONE_MIN`）。
   * 任何可点控件的**命中区**都必须 ≥ 本值；视觉尺寸可以更小，
   * 差额由 `.responseRegion()` 或外层留白补足。
   */
  static readonly TOUCH_MIN: number = 40;
  /** 44 —— 图标条按钮 / 大按钮 */
  static readonly BAR: number = 44;
  /** 48 —— 栏高 / 对话框按钮 */
  static readonly BAR_SM: number = 48;
  /** 52 —— 移动工具栏 */
  static readonly BAR_LG: number = 52;
  /** 56 —— 移动头/底栏 */
  static readonly BAR_XL: number = 56;
}

/**
 * 行高（vp 绝对值，不是倍率）。
 *
 * ArkUI 的 `.lineHeight()` 收的是 **Length**，不是倍数 ⇒ 令牌只能给绝对值。
 * 倍率由「值 ÷ 配套字号」保证，并在下表逐条标注：
 *   - `BODY`  = 23 / Font.BODY(15)     = **1.533**  ∈ [1.5, 1.6] ✓
 *   - `SMALL` = 20 / Font.BODY_SM(13)  = **1.538**  ∈ [1.5, 1.6] ✓
 * ⇒ **换字号令牌时必须同步换行高令牌**，否则倍率漂出区间。
 */
export class LineH {
  /** 23vp —— 配 Font.BODY(15) */
  static readonly BODY: number = 23;
  /** 20vp —— 配 Font.BODY_SM(13)（也是原仓唯一一处 `.lineHeight(20)`） */
  static readonly SMALL: number = 20;
}

/**
 * 动效时长（ms）。
 *
 * 原仓 9 个取值，140ms 主导（26/45 = 58%）。本表把其余的收敛为
 * `FAST / BASE / SLOW` 三档 + 一个 `EMPHASIS`（原 420/500 的长动效，
 * 例如图谱/块拖拽这类「需要被看见的过程」，**刻意保留为独立档**
 * 而不是并进 SLOW —— 那是 W20 D9「要么补齐要么删掉」的另一半）。
 */
export class Motion {
  /** 120 —— 微反馈（分割条、hover 线） */
  static readonly FAST: number = 120;
  /** 140 —— 默认（原仓主导值，项目自述「三态动效统一 140ms」） */
  static readonly BASE: number = 140;
  /** 220 —— 面板/布局变化 */
  static readonly SLOW: number = 220;
  /** 420 —— 需要被看见的过程（保留档） */
  static readonly EMPHASIS: number = 420;
}

/**
 * 动效曲线（2 档）。
 * 原仓 `Curve.EaseOut`(33) / `Curve.Friction`(10) / `Curve.FastOutSlowIn`(1 处孤例)。
 * 孤例并进 `STD`。
 */
export class MotionCurve {
  /** 默认缓出 */
  static readonly STD: string = 'EaseOut';
  /** 手势/拖拽跟手 */
  static readonly GESTURE: string = 'Friction';
}

/**
 * 全局热区规范（v1）。
 *
 * 判据（可执行）：**任何可点元素的命中矩形短边 ≥ 40vp**。
 * 落地手段按优先级：
 *   ① 视觉尺寸本来就 ≥40 ⇒ 无需处理；
 *   ② 视觉必须更小 ⇒ `.responseRegion({ x: '-Xvp', y: '-Xvp', width: 'Wvp', height: 'Hvp' })`
 *      把命中区向外扩张（**布局与视觉完全不变**）；
 *   ③ 密集行内控件（如块的项目符）⇒ 用 ② 但**扩张量以「不与相邻控件命中区重叠」为上界**
 *      （重叠会让点击落到错误控件上，比热区不足更糟）。
 *
 * ⚠️ 已知代价：`.responseRegion()` **不改变布局几何** ⇒ `dumpLayout` 的可点区域读数
 *   **可能不反映扩张结果**（本窗口已实测，见交付文档 §3）。因此热区验收采用
 *   **双判据**：`dumpLayout` 几何（能读到就报）+ **越界点击行为对照**
 *   （点「旧命中区之外、新命中区之内」的坐标，看动作是否触发）。
 */
export class HotZone {
  /** 规范值：交互元素最小命中短边（vp） */
  static readonly MIN: number = 40;
  /** 触屏推荐的宽松值 */
  static readonly COMFORT: number = 44;
}

/**
 * 层高（阴影）语义档。
 * 原仓 `.shadow()` 的 radius 有 14 个取值、无语义映射 ⇒ 无法回答「浮层该用哪一档」。
 * 颜色由调用点给（必须走 `$r('app.color.*')`，因为阴影色也要跟随暗色）。
 */
export interface ElevationSpec {
  /** 模糊半径（vp） */
  radius: number;
  /** 纵向偏移（vp） */
  offsetY: number;
  /** 透明度 */
  alpha: number;
}

export class Elevation {
  /** 贴地层：卡片 */
  static readonly CARD: ElevationSpec = { radius: 8, offsetY: 2, alpha: 0.10 };
  /** 悬浮层：菜单 / 下拉 */
  static readonly MENU: ElevationSpec = { radius: 12, offsetY: 4, alpha: 0.16 };
  /** 模态层：对话框 / 命令面板 */
  static readonly MODAL: ElevationSpec = { radius: 24, offsetY: 8, alpha: 0.22 };
}
